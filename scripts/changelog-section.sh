#!/usr/bin/env bash
# Prints the body of one version's section of CHANGELOG.md, without its
# heading and without surrounding blank lines. Fails when the section is
# missing or empty, so a release never ships without notes.
#
# Usage: scripts/changelog-section.sh <x.y.z> [path/to/CHANGELOG.md]
set -euo pipefail

version="${1:?usage: changelog-section.sh <x.y.z> [CHANGELOG.md]}"
changelog="${2:-$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md}"

body="$(awk -v heading="## [$version]" '
  index($0, heading) == 1 { inside = 1; next }
  inside && /^## / { exit }
  inside { print }
' "$changelog" | sed '/./,$!d')"

if [[ -z "$body" ]]; then
  echo "CHANGELOG has no notes under '## [$version]'." >&2
  exit 1
fi
printf '%s\n' "$body"
