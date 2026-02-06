class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.54.0.tgz"
  sha256 "0e72b5b2c74b2aab64d5e7fc653791a27a07316e67c2f3c78c26c10773f83dd8"
  version "0.54.0"

  depends_on "node"

  def install
    npm_packages = ["@hiero-ledger/solo", "@hashgraph/solo"]
    npm_root = Utils.popen_read("npm", "root", "-g").strip

    npm_packages.each do |pkg|
      pkg_scope, pkg_name = pkg.split("/")
      pkg_path = File.join(npm_root, pkg_scope, pkg_name)

      if !npm_root.empty? && File.symlink?(pkg_path)
        opoo <<~EOS
          ATTENTION: Detected a global npm link for #{pkg}.
          Removing it to avoid conflicts with the Homebrew install.
        EOS
        system "npm", "unlink", "-g", pkg

        if File.symlink?(pkg_path)
          opoo <<~EOS
            ATTENTION: npm link for #{pkg} is still present.
            Please remove it manually: npm unlink -g #{pkg}
          EOS
        else
          ohai "Removed npm link for #{pkg}."
        end
      end
    end

    npm_packages.each do |pkg|
      if system "npm", "ls", "-g", "--depth=0", pkg
        opoo <<~EOS
          ATTENTION: Detected a global npm install for #{pkg}.
          Attempting to uninstall to avoid conflicts with the Homebrew install.
        EOS
        if system "npm", "uninstall", "-g", pkg
          ohai "Removed global npm install for #{pkg}."
        else
          odie <<~EOS
            ATTENTION: Detected a global npm install of #{pkg} that could not be removed.
            Please run: npm uninstall -g #{pkg}
          EOS
        end
      end
    end

    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    assert_match "Usage: solo", shell_output("#{bin}/solo --help")
  end
end
