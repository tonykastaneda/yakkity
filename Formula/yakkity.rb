class Yakkity < Formula
  desc "Search, resume, and hand off conversations between coding agents"
  homepage "https://yakkity.dev"
  license "MIT"
  head "https://github.com/tonykastaneda/yakkity.git", branch: "main"

  depends_on "fzf"
  depends_on "jq"
  depends_on :macos

  def install
    bin.install "yakk.zsh" => "yakk"
  end

  test do
    assert_match "yakkity 0.2.0", shell_output("#{bin}/yakk --version")
    assert_match "Usage: yakk", shell_output("#{bin}/yakk --help")
  end
end
