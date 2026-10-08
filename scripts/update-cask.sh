#!/usr/bin/env bash
# Points Casks/notchemon.rb at a release: sets its version and the SHA-256 of
# that release's zip.
#
# Usage: scripts/update-cask.sh <x.y.z> <sha256> [path/to/notchemon.rb]
set -euo pipefail

version="${1:?usage: update-cask.sh <x.y.z> <sha256> [cask]}"
sha="${2:?usage: update-cask.sh <x.y.z> <sha256> [cask]}"
cask="${3:-$(cd "$(dirname "$0")/.." && pwd)/Casks/notchemon.rb}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "update-cask: '$version' is not x.y.z" >&2; exit 1; }
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "update-cask: '$sha' is not a SHA-256" >&2; exit 1; }

sed -i '' -E \
  -e "s/^([[:space:]]*version) \"[^\"]*\"$/\1 \"$version\"/" \
  -e "s/^([[:space:]]*sha256) \"[^\"]*\"$/\1 \"$sha\"/" \
  "$cask"
grep -q "version \"$version\"" "$cask" && grep -q "sha256 \"$sha\"" "$cask" || {
  echo "update-cask: $cask has no version or sha256 line to update" >&2
  exit 1
}
