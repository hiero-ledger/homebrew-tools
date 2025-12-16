class SoloAT0490 < Formula # Class name must be unique!
  desc "An opinionated CLI tool to deploy and manage standalone test networks (v0.49.0)."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.49.0.tgz"
  sha256 "f1674a7d1a6bb82de01cbe601dec4fa92b40eff7b1b2972b235cef5228351258"
  version "0.49.0"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    assert_match "Usage: solo", shell_output("#{bin}/solo --help")
  end
end
