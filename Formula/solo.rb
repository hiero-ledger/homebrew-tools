class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"
  # The URL points to the npm package tarball
  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.47.0.tgz"
  sha256 "9b640c698942a569be083cff82eb7a503ad46a430faa65d7f3ab229b124a92f1" # Get this from the npm registry info

  depends_on "node"

  def install
    # This runs `npm install` inside a sandbox with Homebrew's
    # recommended settings for global packages.
    system "npm", "install", *std_npm_args

    # npm installs the executable to libexec/bin. You need to symlink it to bin.
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    assert_match "Usage: solo", shell_output("#{bin}/solo --help")
  end
end
