class SoloAT0.51.0 < Formula
  desc "An opinionated CLI tool to deploy and manage standalone test networks."
  homepage "https://github.com/hiero-ledger/solo"

  url "https://registry.npmjs.org/@hashgraph/solo/-/solo-0.51.0.tgz"
  sha256 "a05bf34b980a6c931bb5c52681d2b6b07b5c69e06d21970fbdaf750a8c381357"
  version "0.51.0"

  depends_on "node"

  def install
    system "npm", "install", *std_npm_args
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  test do
    assert_match "Usage: solo", shell_output("#{bin}/solo --help")
  end
end
