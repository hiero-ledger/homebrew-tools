class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"
  # The URL points to your npm package tarball
  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.43.2.tgz"
  sha256 "7bdd34604200ccf1e956a1ae87afbddbaf3c543a0a3f813c425e091fff92ecfd" # Get this from the npm registry info

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
