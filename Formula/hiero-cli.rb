require "language/node"
class HieroCli < Formula
  desc "Command-line interface for interacting with the Hedera network"
  homepage "https://github.com/hiero-ledger/hiero-cli"
  url "https://registry.npmjs.org/@hiero-ledger/hiero-cli/-/hiero-cli-0.13.0.tgz"
  sha256 "cd00199d2b744f0e73b5473c7e494c71293a50b1b53530486f14884a0a3de369"
  license "Apache-2.0"

  depends_on "node"

  def install
    system "npm", "install", *Language::Node.std_npm_install_args(libexec)
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end

  def caveats
    <<~EOS
      First-time setup (Initialization): When you run any command that requires an operator (like transferring HBAR or creating fungible tokens) in interactive mode, the CLI will automatically launch an initialization wizard to guide you through configuring the operator account, private key, and settings. In script mode (non-interactive), an error will be thrown instead, requiring you to use hcli network set-operator to configure the operator first.
    EOS
  end

  test do
    system "#{bin}/hcli", "--help"
  end
end