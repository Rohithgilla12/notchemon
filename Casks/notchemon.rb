# Template for a Homebrew tap (for example Rohithgilla12/homebrew-tap).
# After each release, set version and sha256 from the output of scripts/release.sh.
# The app is signed with "Developer ID Application: Rohith Gilla (7D2V3RM56T)"
# and notarised, so Gatekeeper opens it without a quarantine prompt.
cask "notchemon" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_PRINTED_BY_RELEASE_SCRIPT"

  url "https://github.com/Rohithgilla12/notchemon/releases/download/v#{version}/Notchemon-#{version}.zip"
  name "Notchemon"
  desc "Creature companion that lives in the MacBook notch"
  homepage "https://github.com/Rohithgilla12/notchemon"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Notchemon.app"

  uninstall quit: "com.rohithgilla.Notchemon"

  zap trash: [
    "~/Library/Application Support/Notchemon",
    "~/Library/Preferences/com.rohithgilla.Notchemon.plist",
  ]
end
