require 'formula'

class Qca < Formula
  homepage 'http://delta.affinix.com/qca/'
  url 'http://delta.affinix.com/download/qca/2.0/qca-2.0.3.tar.bz2'
  sha1 '9c868b05b81dce172c41b813de4de68554154c60'

  head "git://anongit.kde.org/qca.git", :branch => "master"

  depends_on 'qt'

  if build.head?
    option "with-api-docs", "Build Doxygen API documentation"
    option "with-tests", "Build tests and run them before install"
    option "without-plugins", "Skip building plugins"

    depends_on "cmake" => :build
    depends_on "qt5" => :optional

    # plugins (QCA needs at least one plugin to do anything useful)
    if build.with? "plugins"
      depends_on "openssl" # qca-ossl
      depends_on "botan" # qca-botan
      depends_on "libgcrypt" # qca-gcrypt
      depends_on "gnupg" # qca-gnupg (currently segfaults in tests)
      depends_on "nss" # qca-nss
      depends_on "pkcs11-helper" # qca-pkcs11
    end
    if build.with? "api-docs"
      depends_on "graphviz" => :build
      depends_on "doxygen" => [:build, "with-dot"]
    end
  end

  head do
    # add Apple-specific output (.dylib modules)
    patch :DATA
  end

  stable do
    # Fix for clang adhering strictly to standard, see:
    # http://clang.llvm.org/compatibility.html#dep_lookup_bases
    patch do
      url "http://quickgit.kde.org/?p=qca.git&a=commitdiff&h=312b69&o=plain"
      sha1 "f3b1f645e35f46919d9bf9ed6f790619c7d03631"
    end
  end

  def certs_store
    prefix/"certs"
  end

  def root_certs
    certs_store/"rootcerts.pem"
  end

  def populate_store
    # culled from openssl formula
    keychains = %w[
      /Library/Keychains/System.keychain
      /System/Library/Keychains/SystemRootCertificates.keychain
    ]

    certs_store.mkpath
    rm_f root_certs
    root_certs.atomic_write `security find-certificate -a -p #{keychains.join(" ")}`
  end

  def install
    if build.head?
      args = std_cmake_args
      args << "-DQT4_BUILD=#{build.with?("qt5") ? "OFF" : "ON"}"
      args << "-DBUILD_TESTS=#{build.with?("tests") ? "ON" : "OFF"}"
      args << "-DBUILD_PLUGINS=#{build.with?("plugins") ? "auto" : "none"}"

      mkdir "build" do
        system "cmake", "..", *args
        system "make"

        if build.with? "tests"
          ln_s "../lib", "bin/"
          begin
            safe_system "ctest"
          rescue ErrorDuringExecution
            opoo "Something with tests failed. Moving along..."
          end
          rm "bin/lib"
        end

        system "make", "install"

        if build.with? "api-docs"
          system "make", "doc"
          doc.install "apidocs/html"
        end
      end

      # symlink plugins into qt formula prefix
      # first move plugins out of lib, or segfault on unload of plugin provider instance
      qca_prefix = prefix/"../HEAD"
      qca_plugins = "#{qca_prefix}/qca_plugins"
      mkpath qca_plugins
      mv "#{qca_prefix}/lib/qca/crypto", "#{qca_plugins}/crypto"
      ln_sf "#{qca_plugins}/crypto", Formula["qt"].prefix/"plugins/"
    else
      system "./configure", "--prefix=#{prefix}", "--disable-tests"
      system "make install"
    end

  end

  def post_install
      populate_store
  end
end

__END__
diff --git a/plugins/CMakeLists.txt b/plugins/CMakeLists.txt
index 258b0b0..a1c6549 100644
--- a/plugins/CMakeLists.txt
+++ b/plugins/CMakeLists.txt
@@ -2,6 +2,10 @@
 set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib/${QCA_LIB_NAME}/crypto")
 set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib/${QCA_LIB_NAME}/crypto")
 
+if(APPLE)
+ set(CMAKE_SHARED_MODULE_SUFFIX ".dylib")
+endif(APPLE)
+
 set(PLUGINS "botan;cyrus-sasl;gcrypt;gnupg;logger;nss;ossl;pkcs11;softstore" CACHE INTERNAL "")
 
 # Initialize WITH_${PLUGIN}_PLUGIN cache variables
