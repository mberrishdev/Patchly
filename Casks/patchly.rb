cask "patchly" do
  version "0.1.0"
  sha256 "a79cf652d224c089b97bd42cc96a632a56344e0100d55c1e5f0bfb1d24386860"

  url "https://github.com/mberrishdev/Patchly/releases/download/v#{version}/Patchly-#{version}.dmg",
      verified: "github.com/mberrishdev/Patchly/"
  name "Patchly"
  desc "Menu-bar utility that reports which installed apps have updates available"
  homepage "https://github.com/mberrishdev/Patchly"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Patchly.app"

  uninstall quit: "com.mberrish.Patchly"

  zap trash: [
    "~/Library/Application Support/Patchly",
    "~/Library/Preferences/com.mberrish.Patchly.plist",
  ]

  # Patchly is ad-hoc signed (no Apple Developer ID yet), so without this
  # macOS reports it as "damaged and can't be opened" on first launch —
  # Gatekeeper's message for a quarantined app it can't notarization-verify,
  # not actual corruption. Clearing the quarantine flag here means a plain
  # `brew install --cask patchly` just works; only a manual DMG install
  # (outside Homebrew) still needs this run by hand.
  postflight do
    system_command "/usr/bin/xattr",
                    args: ["-cr", "#{appdir}/Patchly.app"]
  end

  caveats do
    <<~EOS
      Patchly is ad-hoc signed (no Apple Developer ID yet). This cask already
      clears the quarantine flag for you; if you instead installed the DMG
      manually and macOS says Patchly is damaged and can't be opened, run:
        xattr -cr "#{appdir}/Patchly.app"
    EOS
  end
end
