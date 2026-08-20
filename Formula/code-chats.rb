class CodeChats < Formula
  desc "Search, resume, and hand off conversations between coding agents"
  homepage "https://github.com/tonykastaneda/code-chats"
  license "MIT"
  head "https://github.com/tonykastaneda/code-chats.git", branch: "main"

  depends_on "fzf"
  depends_on "jq"
  depends_on :macos

  def install
    bin.install "chat.zsh" => "chat"
  end

  test do
    assert_match "code-chats", shell_output("#{bin}/chat --version")
    assert_match "Usage: chat", shell_output("#{bin}/chat --help")
  end
end
