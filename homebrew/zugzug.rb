class Zugzug < Formula
  desc "WC3 metagame for AI coding agents — sounds, achievements, economy, roasts"
  homepage "https://github.com/MikeKovetsky/zugzug.sh"
  url "https://github.com/MikeKovetsky/zugzug.sh/archive/refs/tags/v3.0.0.tar.gz"
  sha256 "eb0feb3e5e5a68a3add854cd832b2455f11d1dcf4e39939549618ef274da21cc"
  license "MIT"

  depends_on "python@3"

  def install
    libexec.install "peon.sh"
    libexec.install "relay.sh"
    libexec.install "VERSION"
    libexec.install "completions.bash"
    libexec.install "completions.fish"
    libexec.install "config.json"
    libexec.install "uninstall.sh"

    (libexec/"scripts").install Dir["scripts/*"]
    (libexec/"adapters").install Dir["adapters/*"]
    (libexec/"skills").install Dir["skills/*"]
    (libexec/"trainer").install Dir["trainer/*"]
    (libexec/"dashboard.html").write (buildpath/"dashboard/index.html").read

    (bin/"zugzug").write <<~EOS
      #!/bin/bash
      exec bash "#{libexec}/peon.sh" "$@"
    EOS
  end

  def caveats
    <<~EOS
      To set up zugzug with your IDE:

        zugzug help

      The WC3 dashboard auto-starts on first hook event, or run:

        zugzug dashboard

      To see your economy and achievements:

        zugzug economy
        zugzug achievements
        zugzug build list
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/zugzug help")
  end
end
