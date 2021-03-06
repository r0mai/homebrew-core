class Mesos < Formula
  desc "Apache cluster manager"
  homepage "https://mesos.apache.org"
  url "https://www.apache.org/dyn/closer.cgi?path=mesos/1.0.0/mesos-1.0.0.tar.gz"
  mirror "https://archive.apache.org/dist/mesos/1.0.0/mesos-1.0.0.tar.gz"
  sha256 "dabca5b60604fd672aaa34e4178bb42c6513eab59a07a98ece1e057eb34c28b2"

  bottle do
    sha256 "7bbf7f532c4ce172a754232a6b8ad8066a7245db06147ef54c5b2901ffe60a3f" => :sierra
    sha256 "8a4d45b766546eb80be55bb65c50b66a6d1e3b0f655646b222e5252384330b0f" => :el_capitan
    sha256 "3ba5bc60511694dc4cdebbacc8f409fd4dc17ba12961bc78eccc2d1d3dfc7ade" => :yosemite
    sha256 "2b0aab36735f07c2db20b45b8b381003d93898213c41ff6ed071cdd26da54346" => :mavericks
  end

  depends_on :java => "1.7+"
  depends_on :macos => :mountain_lion
  depends_on :apr => :build
  depends_on "maven" => :build
  depends_on "subversion"

  resource "boto" do
    url "https://pypi.python.org/packages/6f/ce/3447e2136c629ae895611d946879b43c19346c54876dea614316306b17dd/boto-2.40.0.tar.gz"
    sha256 "e12d5fca11fcabfd0acd18f78651e0f0dba60f958a0520ff4e9b73e35cd9928f"
  end

  resource "protobuf" do
    url "https://pypi.python.org/packages/source/p/protobuf/protobuf-2.6.1.tar.gz"
    sha256 "8faca1fb462ee1be58d00f5efb4ca4f64bde92187fe61fde32615bbee7b3e745"
  end

  # build dependencies for protobuf
  resource "six" do
    url "https://pypi.python.org/packages/source/s/six/six-1.9.0.tar.gz"
    sha256 "e24052411fc4fbd1f672635537c3fc2330d9481b18c0317695b46259512c91d5"
  end

  resource "python-dateutil" do
    url "https://pypi.python.org/packages/source/p/python-dateutil/python-dateutil-2.4.0.tar.gz"
    sha256 "439df33ce47ef1478a4f4765f3390eab0ed3ec4ae10be32f2930000c8d19f417"
  end

  resource "pytz" do
    url "https://pypi.python.org/packages/source/p/pytz/pytz-2014.10.tar.bz2"
    sha256 "387f968fde793b142865802916561839f5591d8b4b14c941125eb0fca7e4e58d"
  end

  resource "python-gflags" do
    url "https://pypi.python.org/packages/source/p/python-gflags/python-gflags-2.0.tar.gz"
    sha256 "0dff6360423f3ec08cbe3bfaf37b339461a54a21d13be0dd5d9c9999ce531078"
  end

  resource "google-apputils" do
    url "https://pypi.python.org/packages/source/g/google-apputils/google-apputils-0.4.2.tar.gz"
    sha256 "47959d0651c32102c10ad919b8a0ffe0ae85f44b8457ddcf2bdc0358fb03dc29"
  end

  needs :cxx11

  def install
    ENV.java_cache

    boto_path = libexec/"boto/lib/python2.7/site-packages"
    ENV.prepend_create_path "PYTHONPATH", boto_path
    resource("boto").stage do
      system "python", *Language::Python.setup_install_args(libexec/"boto")
    end
    (lib/"python2.7/site-packages").mkpath
    (lib/"python2.7/site-packages/homebrew-mesos-boto.pth").write "#{boto_path}\n"

    # work around distutils abusing CC instead of using CXX
    # https://issues.apache.org/jira/browse/MESOS-799
    # https://github.com/Homebrew/homebrew/pull/37087
    native_patch = <<-EOS.undent
      import os
      os.environ["CC"] = os.environ["CXX"]
      os.environ["LDFLAGS"] = "@LIBS@"
      \\0
    EOS
    inreplace "src/python/executor/setup.py.in",
              "import ext_modules",
              native_patch

    inreplace "src/python/scheduler/setup.py.in",
              "import ext_modules",
              native_patch

    # skip build javadoc because Homebrew sandbox ENV.java_cache
    # would trigger maven-javadoc-plugin bug.
    # https://issues.apache.org/jira/browse/MESOS-3482
    maven_javadoc_patch = <<-EOS.undent
      <properties>
        <maven.javadoc.skip>true</maven.javadoc.skip>
      </properties>
      \\0
    EOS
    inreplace "src/java/mesos.pom.in",
              "<url>http://mesos.apache.org</url>",
              maven_javadoc_patch

    args = %W[
      --prefix=#{prefix}
      --disable-debug
      --disable-dependency-tracking
      --disable-silent-rules
      --with-svn=#{Formula["subversion"].opt_prefix}
    ]

    unless MacOS::CLT.installed?
      args << "--with-apr=#{Formula["apr"].opt_libexec}"
    end

    ENV.cxx11

    system "./configure", "--disable-python", *args
    system "make"
    system "make", "install"

    # The native Python modules `executor` and `scheduler` (see below) fail to
    # link to Subversion libraries if Homebrew isn't installed in `/usr/local`.
    ENV.append_to_cflags "-L#{Formula["subversion"].opt_lib}"

    system "./configure", "--enable-python", *args
    ["native", "interface", "executor", "scheduler", "cli", ""].each do |p|
      cd "src/python/#{p}" do
        system "python", *Language::Python.setup_install_args(prefix)
      end
    end

    # stage protobuf build dependencies
    ENV.prepend_create_path "PYTHONPATH", buildpath/"protobuf/lib/python2.7/site-packages"
    %w[six python-dateutil pytz python-gflags google-apputils].each do |r|
      resource(r).stage do
        system "python", *Language::Python.setup_install_args(buildpath/"protobuf")
      end
    end

    protobuf_path = libexec/"protobuf/lib/python2.7/site-packages"
    ENV.prepend_create_path "PYTHONPATH", protobuf_path
    resource("protobuf").stage do
      ln_s buildpath/"protobuf/lib/python2.7/site-packages/google/apputils", "google/apputils"
      system "python", *Language::Python.setup_install_args(libexec/"protobuf")
    end
    pth_contents = "import site; site.addsitedir('#{protobuf_path}')\n"
    (lib/"python2.7/site-packages/homebrew-mesos-protobuf.pth").write pth_contents
  end

  test do
    require "timeout"

    master = fork do
      exec "#{sbin}/mesos-master", "--ip=127.0.0.1",
                                   "--registry=in_memory"
    end
    agent = fork do
      exec "#{sbin}/mesos-agent", "--master=127.0.0.1:5050",
                                  "--work_dir=#{testpath}"
    end
    Timeout.timeout(15) do
      system "#{bin}/mesos", "execute",
                             "--master=127.0.0.1:5050",
                             "--name=execute-touch",
                             "--command=touch\s#{testpath}/executed"
    end
    Process.kill("TERM", master)
    Process.kill("TERM", agent)
    assert File.exist?("#{testpath}/executed")
    system "python", "-c", "import mesos.native"
  end
end
