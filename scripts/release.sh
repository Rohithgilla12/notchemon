#!/usr/bin/env bash
# Builds a Developer ID signed Release of Notchemon and verifies it. Writes two
# artifacts to dist/: a zip for Sparkle and the Homebrew cask, and a
# drag-to-Applications DMG for people who download by hand. When credentials
# exist, it notarises and staples the app, then the DMG. It ends by printing
# the version and each artifact's path and SHA-256.
#
# Notarisation credentials, in order of preference:
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   App Store Connect API key (CI)
#   NOTARY_PROFILE (default "notchemon")            notarytool keychain profile
# SKIP_NOTARIZE=1 skips notarisation outright.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

build_dir="$root/.build/release"
archive="$build_dir/Notchemon.xcarchive"
export_dir="$build_dir/export"
dist_dir="$root/dist"
profile="${NOTARY_PROFILE:-notchemon}"

# Archive and export rather than build: only a Developer ID export re-signs
# Sparkle's nested helpers, which ship with Sparkle's ad hoc signature.
xcodegen generate -q
rm -rf "$archive" "$export_dir"
xcodebuild archive \
  -project Notchemon.xcodeproj \
  -scheme Notchemon \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" \
  -archivePath "$archive" \
  -quiet
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "$root/scripts/ExportOptions.plist" \
  -quiet

app="$export_dir/Notchemon.app"
# Read from the built bundle, which XcodeGen filled from project.yml.
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
zip="$dist_dir/Notchemon-$version.zip"
dmg="$dist_dir/Notchemon-$version.dmg"

"$root/scripts/verify-signing.sh" "$app"
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q "get-task-allow"; then
  echo "Release build carries get-task-allow; notarisation would reject it." >&2
  exit 1
fi
"$root/scripts/check-no-assets.sh" "$app"

make_zip() {
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
}

# The app beside a link to /Applications, in a compressed read-only image.
make_dmg() {
  local staging
  staging="$(mktemp -d)"
  ditto "$app" "$staging/Notchemon.app"
  ln -s /Applications "$staging/Applications"
  rm -f "$dmg"
  hdiutil create -quiet -volname Notchemon -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"
  rm -rf "$staging"
  codesign --sign "Developer ID Application" --timestamp "$dmg"
  codesign --verify --strict --verbose=2 "$dmg"
}

notarize() {
  local file="$1"
  if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    xcrun notarytool submit "$file" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  else
    xcrun notarytool submit "$file" --keychain-profile "$profile" --wait
  fi
}

has_keychain_profile() {
  security find-generic-password -s "com.apple.gke.notary.tool" -a "$profile" >/dev/null 2>&1
}

mkdir -p "$dist_dir"
make_zip

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "Skipping notarisation: SKIP_NOTARIZE=1."
  make_dmg
elif [[ -n "${NOTARY_KEY_PATH:-}" ]] || has_keychain_profile; then
  # Staple the app before it goes into the final zip and the DMG, so it opens
  # offline whichever way it arrives.
  notarize "$zip"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
  make_zip
  make_dmg
  notarize "$dmg"
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
else
  echo "Skipping notarisation: no API key in NOTARY_KEY_PATH and no keychain profile named '$profile'."
  echo "Create one with: xcrun notarytool store-credentials $profile --apple-id <id> --team-id 7D2V3RM56T"
  make_dmg
fi

echo "version: $version"
echo "zip: $zip"
echo "zip sha256: $(shasum -a 256 "$zip" | cut -d' ' -f1)"
echo "dmg: $dmg"
echo "dmg sha256: $(shasum -a 256 "$dmg" | cut -d' ' -f1)"
