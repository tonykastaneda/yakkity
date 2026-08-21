class Yakkity < Formula
  desc "Search, resume, and hand off conversations between coding agents"
  homepage "https://yakkity.dev"
  url "https://github.com/tonykastaneda/yakkity/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "ad2760d1d4c95723db57a56c791b76cffa2cc066f6a83907fe443bf9fd1c471f"
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
