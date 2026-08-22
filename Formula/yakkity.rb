class Yakkity < Formula
  desc "Search, resume, and hand off conversations between coding agents"
  homepage "https://yakkity.dev"
  url "https://github.com/tonykastaneda/yakkity/archive/refs/tags/v0.2.2.tar.gz"
  sha256 "263587a505e10d329556b4f971dca3c494823952827b129306d95c346e5f901d"
  license "MIT"
  head "https://github.com/tonykastaneda/yakkity.git", branch: "main"

  depends_on "fzf"
  depends_on "jq"
  depends_on :macos

  def install
    bin.install "yakk.zsh" => "yakk"
    man1.install "man/yakk.1" if (buildpath/"man/yakk.1").exist?
  end

  test do
    assert_match "yakkity 0.2.2", shell_output("#{bin}/yakk --version")
    assert_match "Usage: yakk", shell_output("#{bin}/yakk --help")
  end
end
