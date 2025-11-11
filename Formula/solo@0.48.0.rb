class SoloAT0480 < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.48.0.tgz"
  sha256 "c6bb42b303e8785940c8870415350d42b02ea4e1c7e7151e82d530a1d5657b75"
  version "0.48.0"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    assert_match "Usage: solo", shell_output("#{bin}/solo --help")
  end
end
