class Yakkity < Formula
  desc "Search, resume, and hand off conversations between coding agents"
  homepage "https://yakkity.dev"
  url "https://github.com/tonykastaneda/yakkity/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "148a6c13df7c7640224c2a146914bc7b34bc031843eebdd12444426188b07a8b"
  license "MIT"
  head "https://github.com/tonykastaneda/yakkity.git", branch: "main"

  depends_on "fzf"
  depends_on "jq"
  depends_on :macos

  def install
    bin.install "yakk.zsh" => "yakk"
  end

  test do
    assert_match "yakkity 0.2.1", shell_output("#{bin}/yakk --version")
    assert_match "Usage: yakk", shell_output("#{bin}/yakk --help")
  end
end
