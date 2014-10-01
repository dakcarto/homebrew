require 'formula'

class Cryptopp < Formula
  homepage 'http://www.cryptopp.com/'
  url 'https://downloads.sourceforge.net/project/cryptopp/cryptopp/5.6.2/cryptopp562.zip'
  sha1 'ddc18ae41c2c940317cd6efe81871686846fa293'
  version '5.6.2'

  option "without-dynamic", "Build only the static lib"

  stable do
      patch :DATA if build.with? "dynamic"
  end

  def install
    # patches welcome to re-enable this on configurations that support it
    ENV.append 'CXXFLAGS', '-DCRYPTOPP_DISABLE_ASM'
    ENV.append "CXXFLAGS", "-fPIC" if build.with? "dynamic"

    args = ["static"]
    args << "dynamic" if build.with? "dynamic"
    # args << "test"

    system "make", "CXX=#{ENV.cxx}", "CXXFLAGS=#{ENV.cxxflags}", "PREFIX=#{prefix}", *args
    system "make", "PREFIX=#{prefix}", "install"

    system "make", "PREFIX=#{prefix}", "test"
    # move all test components to libexec
    libexec.install "cryptest.exe", Dir["Test*"]
  end

  test do
    # will test dynamic if building dynamic, static otherwise
    cd libexec
    system "./cryptest.exe", "v"
  end
end

__END__
diff --git a/GNUmakefile b/GNUmakefile
index b1ab537..2a7954b 100755
--- a/GNUmakefile
+++ b/GNUmakefile
@@ -1,12 +1,17 @@
-CXXFLAGS = -DNDEBUG -g -O2
+#CXXFLAGS = -DNDEBUG -g -O2
+#CXXFLAGS += -DNDEBUG -g2 -Os -fPIC
+
 # -O3 fails to link on Cygwin GCC version 4.5.3
 # -fPIC is supported. Please report any breakage of -fPIC as a bug.
 # CXXFLAGS += -fPIC
+SO = so
+SOFLAGS = -shared
 # the following options reduce code size, but breaks link or makes link very slow on some systems
 # CXXFLAGS += -ffunction-sections -fdata-sections
 # LDFLAGS += -Wl,--gc-sections
+CXXFLAGS += -Wno-unused-function -Wno-unused-parameter -Wno-unused-variable
 ARFLAGS = -cr	# ar needs the dash on OpenBSD
-RANLIB = ranlib
+RANLIB ?= ranlib
 CP = cp
 MKDIR = mkdir
 EGREP = egrep
@@ -14,8 +19,9 @@ UNAME = $(shell uname)
 ISX86 = $(shell uname -m | $(EGREP) -c "i.86|x86|i86|amd64")
 IS_SUN_CC = $(shell $(CXX) -V 2>&1 | $(EGREP) -c "CC: Sun")
 IS_LINUX = $(shell $(CXX) -dumpmachine 2>&1 | $(EGREP) -c "linux")
+IS_DARWIN = $(shell uname -s | $(EGREP) -i -c "Darwin")
 IS_MINGW = $(shell $(CXX) -dumpmachine 2>&1 | $(EGREP) -c "mingw")
-CLANG_COMPILER = $(shell $(CXX) --version 2>&1 | $(EGREP) -i -c "clang version")
+CLANG_COMPILER = $(shell $(CXX) --version 2>&1 | $(EGREP) -i -c "clang")
 
 # Default prefix for make install
 ifeq ($(PREFIX),)
@@ -36,11 +42,11 @@ GAS217_OR_LATER = $(shell $(CXX) -xc -c /dev/null -Wa,-v -o/dev/null 2>&1 | $(EG
 GAS219_OR_LATER = $(shell $(CXX) -xc -c /dev/null -Wa,-v -o/dev/null 2>&1 | $(EGREP) -c "GNU assembler version (2\.19|2\.[2-9]|[3-9])")
 
 ifneq ($(GCC42_OR_LATER),0)
-ifeq ($(UNAME),Darwin)
-CXXFLAGS += -arch x86_64 -arch i386
-else
 CXXFLAGS += -march=native
 endif
+
+ifeq ($(IS_DARWIN),1)
+CXXFLAGS += -arch x86_64 -maes -mpclmul -msse2 -mssse3 -msse4 -msse4.2
 endif
 
 ifneq ($(INTEL_COMPILER),0)
@@ -86,16 +92,20 @@ M32OR64 = -m64
 endif
 endif
 
-ifeq ($(UNAME),Darwin)
-AR = libtool
-ARFLAGS = -static -o
-CXX = c++
-IS_GCC2 = $(shell $(CXX) -v 2>&1 | $(EGREP) -c gcc-932)
-ifeq ($(IS_GCC2),1)
-CXXFLAGS += -fno-coalesce-templates -fno-coalesce-static-vtables
-LDLIBS += -lstdc++
-LDFLAGS += -flat_namespace -undefined suppress -m
-endif
+ifeq ($(IS_DARWIN),1)
+  SOFLAGS += -dynamiclib -undefined dynamic_lookup
+  SOFLAGS += -install_name ${PREFIX}/lib/libcryptopp.dylib
+  SOFLAGS += -compatibility_version 5.6 -current_version 5.6.2
+  SO = dylib
+  AR = libtool
+  ARFLAGS = -static -o
+  CXX = clang++
+  IS_GCC2 = $(shell $(CXX) -v 2>&1 | $(EGREP) -c gcc-932)
+  ifeq ($(IS_GCC2),1)
+    CXXFLAGS += -fno-coalesce-templates -fno-coalesce-static-vtables
+    # LDLIBS += -lstdc++
+    LDFLAGS += -flat_namespace -undefined suppress -m
+  endif
 endif
 
 ifeq ($(UNAME),SunOS)
@@ -104,7 +114,7 @@ M32OR64 = -m$(shell isainfo -b)
 endif
 
 ifneq ($(CLANG_COMPILER),0)
-CXXFLAGS += -Wno-tautological-compare
+CXXFLAGS += -Wno-tautological-compare -Wno-unused-value
 endif
 
 ifneq ($(IS_SUN_CC),0)	# override flags for CC Sun C++ compiler
@@ -139,36 +149,36 @@ DLLTESTOBJS = dlltest.dllonly.o
 
 all: cryptest.exe
 static: libcryptopp.a
-dynamic: libcryptopp.so
+dynamic: libcryptopp.$(SO)
 
 test: cryptest.exe
-	./cryptest.exe v
+	./cryptest.exe V
 
 clean:
-	-$(RM) cryptest.exe libcryptopp.a libcryptopp.so $(LIBOBJS) $(TESTOBJS) cryptopp.dll libcryptopp.dll.a libcryptopp.import.a cryptest.import.exe dlltest.exe $(DLLOBJS) $(LIBIMPORTOBJS) $(TESTI MPORTOBJS) $(DLLTESTOBJS)
+	-$(RM) cryptest.exe libcryptopp.a libcryptopp.$(SO) $(LIBOBJS) $(TESTOBJS) cryptopp.dll libcryptopp.dll.a libcryptopp.import.a cryptest.import.exe dlltest.exe $(DLLOBJS) $(LIBIMPORTOBJS) $(TESTI MPORTOBJS) $(DLLTESTOBJS)
 
 install:
 	$(MKDIR) -p $(PREFIX)/include/cryptopp $(PREFIX)/lib $(PREFIX)/bin
 	-$(CP) *.h $(PREFIX)/include/cryptopp
 	-$(CP) *.a $(PREFIX)/lib
-	-$(CP) *.so $(PREFIX)/lib
-	-$(CP) *.exe $(PREFIX)/bin
+	-$(RANLIB) $(PREFIX)/lib/libcryptopp.a
+	-$(CP) *.$(SO) $(PREFIX)/lib
 
 remove:
 	-$(RM) -rf $(PREFIX)/include/cryptopp
 	-$(RM) $(PREFIX)/lib/libcryptopp.a
-	-$(RM) $(PREFIX)/lib/libcryptopp.so
+	-$(RM) $(PREFIX)/lib/libcryptopp.$(SO)
 	-$(RM) $(PREFIX)/bin/cryptest.exe
 
 libcryptopp.a: $(LIBOBJS)
 	$(AR) $(ARFLAGS) $@ $(LIBOBJS)
 	$(RANLIB) $@
 
-libcryptopp.so: $(LIBOBJS)
-	$(CXX) -shared -o $@ $(LIBOBJS)
+libcryptopp.$(SO): $(LIBOBJS)
+	$(CXX) $(CXXFLAGS) $(SOFLAGS) -o $@ $(LIBOBJS) $(LDFLAGS) $(LDLIBS)
 
-cryptest.exe: libcryptopp.a $(TESTOBJS)
-	$(CXX) -o $@ $(CXXFLAGS) $(TESTOBJS) ./libcryptopp.a $(LDFLAGS) $(LDLIBS)
+cryptest.exe: libcryptopp.$(SO) $(TESTOBJS)
+	$(CXX) -o $@ $(CXXFLAGS) $(TESTOBJS) $(LDFLAGS) -L$(PREFIX)/lib -lcryptopp $(LDLIBS)
 
 nolib: $(OBJS)		# makes it faster to test changes
 	$(CXX) -o ct $(CXXFLAGS) $(OBJS) $(LDFLAGS) $(LDLIBS)
