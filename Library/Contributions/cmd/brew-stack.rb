# Install a formula and dependencies from pre-made bottles or as built bottles.
#
# Useful for creating a portable Homebrew directory for a specific OS version.
# Example: portable domain-specific software stack in custom Homebrew prefix
#
# Hint: Use command in `brew bundle` Brewfiles to quickly build full stacks.
#       Also, --dry option helps create correctly ordered Brewfiles when you
#       want to use custom options for dependencies and build them first.

require "formula"
require "cmd/deps"
require "utils"
require "hooks/bottles"

def usage; <<-EOS
  Usage: brew stack [--dry] [install-options...] formula [formula-options...]

         Same options as for `brew install`, but only for a single formula.
         Note: --interactive install option is not supported

  Options: --dry  Don't install anything, just output topologically ordered list
                  of install commands.
           --all  List all dependencies, including installed, on --dry run.

  EOS
end

def tap_name(f_obj)
  (f_obj.tap? ? f_obj.tap.sub("homebrew-", "") + "/" : "") + f_obj.name
end

def to_tap_names(f_name_list)
  f_name_list.map { |f| tap_name(Formulary.factory(f)) }
end

# Stupid global to track what's installed, to make --dry avoid endless loops
# and to avoid multiple spawnings of `brew list`.
# $installed = to_tap_names(%x[brew list].split("\n"))

class Stack
  attr_reader :f, :opts, :argv, :dry, :all

  @@dry_installed = []

  def initialize formula, options=[], argv=nil, dry=false, all=false
    @f = formula
    @opts = options
    @argv = argv
    @dry = dry
    @all = all
  end

  def install
    # Install dependencies in topological order, without sub-dependencies.
    # This is necessary to ensure --build-bottle is used for any source builds.
    f_build_opts = @f.build.used_options.as_flags
    unless @argv && @argv.ignore_deps?
      # deps = to_tap_names(%x[brew deps -n #{@f.name} #{f_build_opts.join(" ")}].split("\n").uniq)
      # deps -= $installed

      deps = Homebrew.deps_for_formula(@f, true)
      deps = deps.select { |d| !d.installed? } unless @dry && @all
      deps = deps.select { |d| !@@dry_installed.include?(d.name) } if @dry

      if @dry
        # ohai "Installed formulae: #{$installed.join(" ")}"
        unless f_build_opts.empty?
          ohai "Build options used, #{@f.name}: #{f_build_opts.join(" ")}"
          ohai "Available options, #{@f.name}: #{@f.build.as_flags.join(" ")}"
        end
        unless deps.empty?
          deps_w_opts = deps.map do |d|
            d.to_s + (d.options.empty? ? "" : " ") + d.options.as_flags.join(" ")
          end
          ohai "Deps for #{@f.name}: #{deps_w_opts.join(", ")}"
        end
      end

      deps.each do |d|
        d_obj = d.to_formula
        d_args = []
        d_args.concat @opts - f_build_opts + d.options.as_flags
        # strip these options
        d_args -= %W[--ignore-dependencies --only-dependencies]
        d_args -= %W[--build-from-source --force-bottle --build-bottle]
        d_args -= %W[--devel --HEAD]
        # recurse down into dependencies, nixing argv
        stack = Stack.new(d_obj, options=d_args, argv=nil, dry=@dry, all=@all)
        stack.install
      end
    end

    # Install formula
    unless @argv && @argv.only_deps?
      f_tap_name = tap_name(@f)
      if (@f.installed? && !(@dry && @all)) || (@dry && @@dry_installed.include?(f_tap_name))
        ohai "#{f_tap_name} already installed"
      else
        f_args = []
        f_args.concat @opts
        if (@argv && @argv.build_from_source?) || !pour_bottle?(@f)
          f_args |= %W[--build-bottle]
        end
        attempt_install @f, f_args
      end
    end
  end

  def attempt_install f, args
    f_tap_name = tap_name(f)
    args -= %W[--dry --all]
    # args |= %W[--build-bottle] unless pour_bottle?(f)
    args << f_tap_name
    ohai "brew install #{args.join(" ")}"
    if @dry
      @@dry_installed += [f_tap_name]
      return
    end

    if system "brew", "install", *args
      return
    end

    if args.include?("--build-bottle")
      odie "Source bottle build failed"
    else
      opoo "Bottle may have failed to install"
      ohai "Attempting to build bottle from source"
      args |= %W[--build-bottle]

      if system "brew", "install", *args
        return
      end
      odie "Source bottle build failed"
    end
  end

  def pour_bottle? f
    # Culled from FormulaInstaller::pour_bottle?
    return true  if Homebrew::Hooks::Bottles.formula_has_bottle?(f)

    return true  if @argv && @argv.force_bottle? && f.bottle
    return false if @argv && (@argv.build_from_source? || @argv.build_bottle?)
    return false unless f.build.used_options.empty?

    return true  if f.local_bottle_path
    return false unless f.bottle && f.pour_bottle?

    f.requirements.each do |req|
      next if req.optional? || req.pour_bottle?
      opoo "Bottle for #{f} blocked by #{req} requirement"
      return false
    end

    unless f.bottle.compatible_cellar?
      opoo "Cellar of #{f}'s bottle is #{f.bottle.cellar}"
      return false
    end

    true
  end

end

# Necessary to raise error if bottle fails to install
ENV["HOMEBREW_DEVELOPER"] = "1"

if ARGV.formulae.length != 1 || ARGV.interactive?
  puts usage
  exit 1
end

if ARGV.include? "--help"
  puts usage
  exit 0
end

# Clear out known installed formulae, only once for initial formula
# $installed = [] if ARGV.include?("--dry") && ARGV.include?("--all")

stack = Stack.new(ARGV.formulae[0], options=ARGV.options_only, argv=ARGV,
                  dry=ARGV.include?("--dry"), all=ARGV.include?("--all"))
stack.install

exit 0
