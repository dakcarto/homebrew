# Install a formula and dependencies from pre-made bottles or as built bottles.
#
# Useful for creating a portable Homebrew directory for a specific OS version.
# Example: portable domain-specific software stack in custom Homebrew prefix
#
# Hint: Use command in `brew bundle` Brewfiles to quickly build full stacks.
#       Also, --dry option helps create correctly ordered Brewfiles when you
#       want to use custom options for dependencies and build them first.

require "formula"
require "utils"
require "hooks/bottles"

def usage; <<-EOS
  Usage: brew stack [--dry] [install-options...] formula [formula-options...]

         Same options as for `brew install`, but only for a single formula.
         Note: --interactive install option is not supported

  Options: --dry  Don't install anything, just output topologically ordered list
                  of install commands.

  EOS
end

# Stupid global to track what's installed, to make --dry avoid endless loops
# and to avoid multiple spawnings of `brew list`.
$installed = %x[brew list].split("\n")

class Stack
  attr_reader :argv, :opts, :f, :dry

  def initialize formula, options=[], argv=nil, dry=false
    @f = formula
    @opts = options
    @argv = argv
    @dry = dry
  end

  def install
    # Install dependencies in topological order, without sub-dependencies.
    # This is necessary to ensure --build-bottle is used for any source builds.
    f_build_opts = @f.build.used_options.as_flags
    unless @argv && @argv.ignore_deps?
      deps = %x[brew deps -n #{@f.name} #{f_build_opts.join(" ")}].split("\n").uniq
      deps -= $installed

      if @dry && !f_build_opts.empty?
        ohai "Used build options for #{@f.name}: #{f_build_opts}"
        ohai "build options for #{@f.name}: #{@f.build.as_flags}"
      end
      ohai "Dependencies for #{@f.name}: #{deps.join(" ")}" if @dry && !deps.empty?

      deps.each do |d|
        d_args = []
        d_args.concat @opts - f_build_opts
        # strip these options
        d_args -= %W[--ignore-dependencies --only-dependencies]
        d_args -= %W[--build-from-source --force-bottle --build-bottle]
        d_args -= %W[--devel --HEAD]
        # recurse down into dependencies
        stack = Stack.new(Formulary.factory(d), options=d_args, argv=nil, dry=@dry)
        stack.install
      end
    end

    # Install formula
    unless @argv && @argv.only_deps?
      if $installed.include? @f.name
        ohai "#{@f.name} already installed"
      else
        f_args = []
        f_args.concat @opts
        if (@argv && @argv.build_from_source?) || !pour_bottle?(@f)
          f_args |= %W[--build-bottle]
        end
        attempt_install @f.name, f_args
      end
    end
  end

  def attempt_install f, args
    args -= %W[--dry]
    args << f
    ohai "brew install #{args.join(" ")}"
    if @dry
      $installed += [f]
      return
    end

    if system "brew", "install", *args
      $installed += [f]
      return
    end

    if args.include?("--build-bottle")
      odie "Source bottle build failed"
    else
      opoo "Bottle may have failed to install"
      ohai "Attempting to build from source with --build-bottle option"
      args |= %W[--build-bottle]

      if system "brew", "install", *args
        $installed += [f]
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
      opoo "Bottle blocked by #{req} requirement"
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

stack = Stack.new(ARGV.formulae[0], options=ARGV.options_only,
                  argv=ARGV, dry=ARGV.include?("--dry"))
stack.install

exit 0
