class SoloAT0470 < Formula # Class name must be unique!
  desc "An opinionated CLI tool to deploy and manage standalone test networks (v0.47.0)."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.47.0.tgz"
  sha256 "9b640c698942a569be083cff82eb7a503ad46a430faa65d7f3ab229b124a92f1"
  version "0.47.0"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    assert_match "Usage: solo", shell_output("#{bin}/solo --help")
  end
end
