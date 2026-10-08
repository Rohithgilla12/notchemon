# The release workflow sets version and sha256 on main after each release
# (scripts/update-cask.sh), so this repository works as a tap:
#   brew tap Rohithgilla12/notchemon https://github.com/Rohithgilla12/notchemon
# The app is signed with "Developer ID Application: Rohith Gilla (7D2V3RM56T)"
# and notarised, so Gatekeeper opens it without a quarantine prompt.
cask "notchemon" do
  version "0.2.2"
  sha256 "b6106ed167f900024e2f4df54b7f506b00beda0bcbcc55111479325c8ac44416"

  url "https://github.com/Rohithgilla12/notchemon/releases/download/v#{version}/Notchemon-#{version}.zip"
  name "Notchemon"
  desc "Creature companion that lives in the MacBook notch"
  homepage "https://github.com/Rohithgilla12/notchemon"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Notchemon.app"

  uninstall quit: "com.rohithgilla.Notchemon"

  zap trash: [
    "~/Library/Application Support/Notchemon",
    "~/Library/Preferences/com.rohithgilla.Notchemon.plist",
  ]
end
