class CodeChats < Formula
  desc "Search, resume, and hand off conversations between coding agents"
  homepage "https://github.com/tonykastaneda/code-chats"
  url "https://github.com/tonykastaneda/code-chats/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "a7f67830e58d895048b09725e0de512a7dcfa9730115be5fe97a8315c9d983e2"
  license "MIT"
  head "https://github.com/tonykastaneda/code-chats.git", branch: "main"

  depends_on "fzf"
  depends_on "jq"
  depends_on :macos

  def install
    bin.install "chat.zsh" => "chat"
  end

  test do
    assert_match "code-chats 0.1.0", shell_output("#{bin}/chat --version")
    assert_match "Usage: chat", shell_output("#{bin}/chat --help")
  end
end
