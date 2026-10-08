#!/usr/bin/env bash
# Writes dist/appcast.xml for the release that scripts/release.sh left in
# dist/. The feed has one item: the zip, signed with the EdDSA private key,
# downloaded from the GitHub release for its tag, with that version's
# CHANGELOG.md section embedded as release notes. Installed apps read the feed
# from the latest release, so it never needs older items.
#
# The private key comes from SPARKLE_ED_PRIVATE_KEY when set (CI), and from
# the login Keychain otherwise.
#
# Usage: scripts/make-appcast.sh <x.y.z>
set -euo pipefail

version="${1:?usage: make-appcast.sh <x.y.z>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
zip="$root/dist/Notchemon-$version.zip"
appcast="$root/dist/appcast.xml"
[[ -f "$zip" ]] || { echo "make-appcast: no $zip; run scripts/release.sh first" >&2; exit 1; }

bin="$("$root/scripts/sparkle-bin.sh")"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

# generate_appcast takes release notes from a file named like the archive.
cp "$zip" "$staging/"
"$root/scripts/changelog-section.sh" "$version" >"$staging/Notchemon-$version.md"

args=(
  --embed-release-notes
  --download-url-prefix "https://github.com/Rohithgilla12/notchemon/releases/download/v$version/"
  --link "https://github.com/Rohithgilla12/notchemon"
  -o "$appcast"
)
rm -f "$appcast"
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$bin/generate_appcast" --ed-key-file - "${args[@]}" "$staging"
else
  "$bin/generate_appcast" --account notchemon "${args[@]}" "$staging"
fi

grep -q 'sparkle:edSignature=' "$appcast" || { echo "make-appcast: $appcast has no EdDSA signature" >&2; exit 1; }
echo "appcast: $appcast"
