class Squish < Formula
  desc "Watch a folder and auto-compress videos with ffmpeg"
  homepage "https://github.com/maheshj01/squish"
  # After tagging a release (e.g. v0.1.0), point url at its tarball and fill in
  # the sha256:  curl -sL <url> | shasum -a 256
  url "https://github.com/maheshj01/squish/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/maheshj01/squish.git", branch: "main"

  depends_on "ffmpeg"
  depends_on :macos

  def install
    # The entry point resolves its own path, so lib/ just needs to sit beside it.
    libexec.install "squish", "lib"
    bin.install_symlink libexec/"squish"
    zsh_completion.install "completions/_squish"
  end

  def caveats
    <<~EOS
      Start watching (creates ~/Movies/squish/{clips,compressed} and loads the
      launchd agent):
        squish start

      Drop videos into ~/Movies/squish/clips; compressed copies land in
      ~/Movies/squish/compressed/<name>/. Stop anytime with `squish stop`.
    EOS
  end

  test do
    assert_match "squish", shell_output("#{bin}/squish version")
  end
end
