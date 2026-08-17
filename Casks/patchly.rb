cask "patchly" do
  version "0.0.8"
  sha256 "848830e4c21f90c501554d6542f2e2ca0318368b0816d0824bad3a5b67ac252e"

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

  caveats do
    <<~EOS
      Patchly is ad-hoc signed (no Apple Developer ID yet). If macOS says
      it's damaged and can't be opened, clear the quarantine flag:
        xattr -cr "#{appdir}/Patchly.app"
    EOS
  end
end
