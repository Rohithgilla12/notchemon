#!/usr/bin/env bash
# Tests for the release scripts that edit files: changelog-section.sh,
# bump-version.sh, and update-cask.sh. Each test works on copies in a
# temporary directory.
#
# Usage: scripts/test-scripts.sh
set -uo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
passed=0
failed=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf 'FAIL: %s\n--- expected\n%s\n--- actual\n%s\n' "$name" "$expected" "$actual"
  fi
}

fixture() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/Casks"
  cat >"$work/repo/project.yml" <<'EOF'
targets:
  Notchemon:
    info:
      properties:
        CFBundleDisplayName: Notchemon
        CFBundleShortVersionString: "0.9.3"
        CFBundleVersion: "41"
        LSUIElement: true
EOF
  cat >"$work/repo/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

- Launch at login.

## [0.9.3] - 2026-10-01

### Fixed

- A crash.

## [0.9.2] - 2026-09-01

- First line.

EOF
  cat >"$work/repo/Casks/notchemon.rb" <<'EOF'
cask "notchemon" do
  version "0.9.3"
  sha256 "REPLACE_WITH_SHA256_PRINTED_BY_RELEASE_SCRIPT"
end
EOF
}

bump() {
  NOTCHEMON_ROOT="$work/repo" RELEASE_DATE=2026-10-08 "$scripts/bump-version.sh" "$@" >/dev/null 2>&1
}

fixture
check "section between headings, trimmed" "### Fixed

- A crash." "$("$scripts/changelog-section.sh" 0.9.3 "$work/repo/CHANGELOG.md")"
check "last section runs to end of file" "- First line." "$("$scripts/changelog-section.sh" 0.9.2 "$work/repo/CHANGELOG.md")"
"$scripts/changelog-section.sh" 0.9 "$work/repo/CHANGELOG.md" >/dev/null 2>&1
check "a version prefix is not a match" "1" "$?"
"$scripts/changelog-section.sh" 1.0.0 "$work/repo/CHANGELOG.md" >/dev/null 2>&1
check "missing section fails" "1" "$?"

fixture
bump 0.10.0
check "bump exits cleanly" "0" "$?"
check "bump sets the marketing version" '        CFBundleShortVersionString: "0.10.0"' "$(grep CFBundleShortVersionString "$work/repo/project.yml")"
check "bump increments the build" '        CFBundleVersion: "42"' "$(grep CFBundleVersion: "$work/repo/project.yml")"
check "bump touches nothing else in project.yml" "CFBundleDisplayName: Notchemon LSUIElement: true" \
  "$(grep -E 'CFBundleDisplayName|LSUIElement' "$work/repo/project.yml" | xargs)"
check "bump files Unreleased under the new heading" "### Added

- Launch at login." "$("$scripts/changelog-section.sh" 0.10.0 "$work/repo/CHANGELOG.md")"
check "bump keeps an empty Unreleased heading" "## [Unreleased]||## [0.10.0] - 2026-10-08" \
  "$(sed -n '3,5p' "$work/repo/CHANGELOG.md" | paste -sd '|' -)"
bump 0.11.0
check "bump refuses an empty Unreleased section" "1" "$?"
sed -i '' 's/^## \[Unreleased\]$/## [Unreleased]\
\
### Added\
/' "$work/repo/CHANGELOG.md"
bump 0.11.0
check "bump refuses an Unreleased section with only headings" "1" "$?"

for version in 0.9.3 0.9.2 1.0 v1.0.0 1.0.0-beta 01.0.0; do
  fixture
  bump "$version"
  check "bump refuses $version" "1" "$?"
  check "refused bump leaves project.yml alone" '        CFBundleVersion: "41"' "$(grep CFBundleVersion: "$work/repo/project.yml")"
done
fixture
bump 1.0.0
check "bump accepts a major version" '        CFBundleVersion: "42"' "$(grep CFBundleVersion: "$work/repo/project.yml")"

fixture
sha="$(printf 'notchemon' | shasum -a 256 | cut -d' ' -f1)"
"$scripts/update-cask.sh" 0.10.0 "$sha" "$work/repo/Casks/notchemon.rb"
check "cask gets version and sha256" "cask \"notchemon\" do
  version \"0.10.0\"
  sha256 \"$sha\"
end" "$(cat "$work/repo/Casks/notchemon.rb")"
"$scripts/update-cask.sh" 0.10.0 not-a-sha "$work/repo/Casks/notchemon.rb" 2>/dev/null
check "cask refuses a bad sha256" "1" "$?"

echo "test-scripts: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
