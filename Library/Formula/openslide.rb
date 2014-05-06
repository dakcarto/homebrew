require 'formula'

class Openslide < Formula
  homepage 'http://openslide.org/'
  url 'http://download.openslide.org/releases/openslide/openslide-3.3.3.tar.gz'
  sha1 '2315f0daa5d963e6ba9f1e67517cee44f9deabe5'
  revision 2

  depends_on 'pkg-config' => :build
  depends_on 'libpng'
  depends_on 'jpeg'
  depends_on 'libxml2'
  depends_on 'libtiff'
  depends_on 'glib'
  depends_on 'cairo'
  depends_on "little-cms2" => :build
  depends_on "libpng" => :build

  resource "openjpeg" do
    url 'https://openjpeg.googlecode.com/files/openjpeg-1.5.1.tar.gz'
    sha1 '1b0b74d1af4c297fd82806a9325bb544caf9bb8b'
  end

  def install
    resource("openjpeg").stage do
      # vendor v.1.5.x, since 2.0 is unsupported
      # see: https://github.com/Homebrew/homebrew/pull/28526
      system "./configure", "--disable-dependency-tracking", "--prefix=#{libexec}"
      system "make", "install"
    end
    ENV.append_path "PKG_CONFIG_PATH", "#{libexec}/lib/pkgconfig"

    system "./configure", "--disable-dependency-tracking",
                          "--prefix=#{prefix}"
    system "make install"
  end
end
