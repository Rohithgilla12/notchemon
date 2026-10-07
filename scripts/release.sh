#!/usr/bin/env bash
# Builds a Developer ID signed Release of Notchemon, verifies the signature,
# zips it, notarises and staples it when credentials exist, and prints the
# SHA-256 for the Homebrew cask.
#
# Notarisation credentials, in order of preference:
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   App Store Connect API key (CI)
#   NOTARY_PROFILE (default "notchemon")            notarytool keychain profile
# SKIP_NOTARIZE=1 skips notarisation outright.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

build_dir="$root/.build/release"
dist_dir="$root/dist"
profile="${NOTARY_PROFILE:-notchemon}"

xcodegen generate -q
xcodebuild build \
  -project Notchemon.xcodeproj \
  -scheme Notchemon \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" \
  -quiet

app="$build_dir/Build/Products/Release/Notchemon.app"
# Read from the built bundle, which XcodeGen filled from project.yml.
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
zip="$dist_dir/Notchemon-$version.zip"

codesign --verify --deep --strict --verbose=2 "$app"
if codesign -d --entitlements - "$app" 2>/dev/null | grep -q "get-task-allow"; then
  echo "Release build carries get-task-allow; notarisation would reject it." >&2
  exit 1
fi
"$root/scripts/check-no-assets.sh" "$app"

mkdir -p "$dist_dir"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

notarize() {
  if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    xcrun notarytool submit "$zip" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  else
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
  fi
}

has_keychain_profile() {
  security find-generic-password -s "com.apple.gke.notary.tool" -a "$profile" >/dev/null 2>&1
}

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "Skipping notarisation: SKIP_NOTARIZE=1."
elif [[ -n "${NOTARY_KEY_PATH:-}" ]] || has_keychain_profile; then
  notarize
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  spctl --assess --type execute --verbose=2 "$app"
else
  echo "Skipping notarisation: no API key in NOTARY_KEY_PATH and no keychain profile named '$profile'."
  echo "Create one with: xcrun notarytool store-credentials $profile --apple-id <id> --team-id 7D2V3RM56T"
fi

echo "Artifact: $zip"
echo "sha256: $(shasum -a 256 "$zip" | cut -d' ' -f1)"
