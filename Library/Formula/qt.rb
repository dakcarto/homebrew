require 'formula'

class Qt < Formula
  homepage 'http://qt-project.org/'
  url "http://download.qt-project.org/official_releases/qt/4.8/4.8.6/qt-everywhere-opensource-src-4.8.6.tar.gz"
  sha1 "ddf9c20ca8309a116e0466c42984238009525da6"
  revision 1

  head 'git://gitorious.org/qt/qt.git', :branch => '4.8'

  bottle do
    sha1 "114242a849d7ade7d55d46097b1f7790b871df8f" => :mavericks
    sha1 "5e022a402437b0a1bf5bf2d2d67491280f73a7a8" => :mountain_lion
    sha1 "212fce47b1f2f2d3bf4397db7d5967fb59223cec" => :lion
  end

  option :universal
  option 'with-qt3support', 'Build with deprecated Qt3Support module support'
  option 'with-docs', 'Build documentation'
  option 'developer', 'Build and link with developer options'

  depends_on "d-bus" => :optional
  depends_on "mysql" => :optional

  odie 'qt: --with-qtdbus has been renamed to --with-d-bus' if build.with? "qtdbus"
  odie 'qt: --with-demos-examples is no longer supported' if build.with? "demos-examples"
  odie 'qt: --with-debug-and-release is no longer supported' if build.with? "debug-and-release"

  def plugins
    'qt4-plugins'
  end

  def plugins_dir
    # location of Qt Plugins
    # so other formulae do not need to install their plugins to qt's keg
    HOMEBREW_PREFIX/"lib/#{plugins}"
  end

  def plugin_subdirs
    %W[accessible bearer codecs designer graphicssystems iconengines
       imageformats phonon_backend qmltooling sqldrivers]
  end

  patch :DATA

  def install
    raise
    ENV.universal_binary if build.universal?

    # generate Qt Plugins directory structure (remains even after uninstall)
    plugin_subdirs.each { |d| (plugins_dir/d).mkpath }

    args = ["-prefix", prefix,
            "-plugindir", lib/plugins,
            "-system-zlib",
            "-qt-libtiff", "-qt-libpng", "-qt-libjpeg",
            "-confirm-license", "-opensource",
            "-nomake", "demos", "-nomake", "examples",
            "-cocoa", "-fast", "-release"]

    # we have to disable these to avoid triggering optimization code
    # that will fail in superenv (in --env=std, Qt seems aware of this)
    args << "-no-3dnow" << "-no-ssse3" if superenv?

    args << "-L#{MacOS::X11.lib}" << "-I#{MacOS::X11.include}" if MacOS::X11.installed?

    if ENV.compiler == :clang
        args << "-platform"

        if MacOS.version >= :mavericks
          args << "unsupported/macx-clang-libc++"
        else
          args << "unsupported/macx-clang"
        end
    end

    args << "-plugin-sql-mysql" if build.with? 'mysql'

    if build.with? 'd-bus'
      dbus_opt = Formula["d-bus"].opt_prefix
      args << "-I#{dbus_opt}/lib/dbus-1.0/include"
      args << "-I#{dbus_opt}/include/dbus-1.0"
      args << "-L#{dbus_opt}/lib"
      args << "-ldbus-1"
      args << "-dbus-linked"
    end

    if build.with? 'qt3support'
      args << "-qt3support"
    else
      args << "-no-qt3support"
    end

    args << "-nomake" << "docs" if build.without? 'docs'

    if MacOS.prefer_64_bit? or build.universal?
      args << '-arch' << 'x86_64'
    end

    if !MacOS.prefer_64_bit? or build.universal?
      args << '-arch' << 'x86'
    end

    args << '-developer-build' if build.include? 'developer'

    system "./configure", *args
    system "make"
    ENV.j1
    system "make install"

    # what are these anyway?
    (bin+'pixeltool.app').rmtree
    (bin+'qhelpconverter.app').rmtree
    # remove porting file for non-humans
    (prefix+'q3porting.xml').unlink if build.without? 'qt3support'

    # Some config scripts will only find Qt in a "Frameworks" folder
    frameworks.install_symlink Dir["#{lib}/*.framework"]

    # The pkg-config files installed suggest that headers can be found in the
    # `include` directory. Make this so by creating symlinks from `include` to
    # the Frameworks' Headers folders.
    Pathname.glob("#{lib}/*.framework/Headers") do |path|
      include.install_symlink path => path.parent.basename(".framework")
    end

    Pathname.glob("#{bin}/*.app") { |app| mv app, prefix }
  end

  test do
    system "#{bin}/qmake", '-project'
  end

  def caveats; <<-EOS.undent
    We agreed to the Qt opensource license for you.
    If this is unacceptable you should uninstall.
    EOS
  end
end

__END__
diff --git a/src/corelib/tools/qstring.cpp b/src/corelib/tools/qstring.cpp
index 7c8986f..b48c081 100644
--- a/src/corelib/tools/qstring.cpp
+++ b/src/corelib/tools/qstring.cpp
@@ -3585,7 +3585,7 @@ static inline __m128i mergeQuestionMarks(__m128i chunk)
 {
     const __m128i questionMark = _mm_set1_epi16('?');
 
-# ifdef __SSE4_2__
+# if defined(QT_HAVE_SSE4_2) && defined(__SSE4_2__)
     // compare the unsigned shorts for the range 0x0100-0xFFFF
     // note on the use of _mm_cmpestrm:
     //  The MSDN documentation online (http://technet.microsoft.com/en-us/library/bb514080.aspx)
@@ -3615,7 +3615,7 @@ static inline __m128i mergeQuestionMarks(__m128i chunk)
     const __m128i signedChunk = _mm_add_epi16(chunk, signedBitOffset);
     const __m128i offLimitMask = _mm_cmpgt_epi16(signedChunk, thresholdMask);
 
-#  ifdef __SSE4_1__
+#  if defined(QT_HAVE_SSE4_1) && defined(__SSE4_1__)
     // replace the non-Latin 1 characters in the chunk with question marks
     chunk = _mm_blendv_epi8(chunk, questionMark, offLimitMask);
 #  else
