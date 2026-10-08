#!/usr/bin/env bash
# Starts a release: sets the marketing version in project.yml, increments the
# build number, which Sparkle compares to find updates, and files everything
# under "## [Unreleased]" in CHANGELOG.md under a new dated heading.
#
# Usage: scripts/bump-version.sh <x.y.z>
# RELEASE_DATE (YYYY-MM-DD) overrides today's date. NOTCHEMON_ROOT points the
# script at another checkout, which the script tests use.
set -euo pipefail

new="${1:?usage: bump-version.sh <x.y.z>}"
root="${NOTCHEMON_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
project="$root/project.yml"
changelog="$root/CHANGELOG.md"
date="${RELEASE_DATE:-$(date +%F)}"

fail() {
  echo "bump-version: $*" >&2
  exit 1
}

[[ "$new" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "'$new' is not x.y.z"

current="$(sed -nE 's/^[[:space:]]*CFBundleShortVersionString: "([^"]*)"$/\1/p' "$project")"
build="$(sed -nE 's/^[[:space:]]*CFBundleVersion: "([0-9]+)"$/\1/p' "$project")"
[[ -n "$current" && -n "$build" ]] || fail "could not read the version and build from project.yml"

# Compares numerically field by field, so 0.10.0 is newer than 0.9.0.
is_newer() {
  local a b i
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    ((a[i] > b[i])) && return 0
    ((a[i] < b[i])) && return 1
  done
  return 1
}
is_newer "$new" "$current" || fail "$new is not newer than $current"

grep -q '^## \[Unreleased\]' "$changelog" || fail "CHANGELOG.md has no '## [Unreleased]' heading"
grep -qF "## [$new]" "$changelog" && fail "CHANGELOG.md already has a section for $new"
unreleased="$(awk '/^## \[Unreleased\]/ { inside = 1; next } inside && /^## / { exit } inside && /[^[:space:]]/ { print }' "$changelog")"
[[ -n "$unreleased" ]] || fail "nothing is listed under '## [Unreleased]'; add the changes first"

next_build=$((build + 1))
sed -i '' -E \
  -e "s/^([[:space:]]*CFBundleShortVersionString:) \"[^\"]*\"$/\1 \"$new\"/" \
  -e "s/^([[:space:]]*CFBundleVersion:) \"[0-9]+\"$/\1 \"$next_build\"/" \
  "$project"

awk -v heading="## [$new] - $date" '
  { print }
  /^## \[Unreleased\]/ && !done { print ""; print heading; done = 1 }
' "$changelog" >"$changelog.tmp"
mv "$changelog.tmp" "$changelog"

echo "Version $current (build $build) -> $new (build $next_build)."
echo "Review the diff, commit it, then tag v$new. See docs/releasing.md."
