class Solo < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.48.0.tgz"
  sha256 "c6bb42b303e8785940c8870415350d42b02ea4e1c7e7151e82d530a1d5657b75"
  version "0.48.0" # Explicitly define the version

  resource "0.47.0" do
    url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.47.0.tgz"
    sha256 "9b640c698942a569be083cff82eb7a503ad46a430faa65d7f3ab229b124a92f1"
  end

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
