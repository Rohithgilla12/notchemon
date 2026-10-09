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

# Names are planted through printf escapes so this file passes the check too.
names_fixture() {
  rm -rf "$work/names"
  mkdir -p "$work/names/scripts" "$work/names/Notchemon"
  cp "$scripts/check-no-assets.sh" "$work/names/scripts/"
  printf 'struct PokeAPICreatureProvider {}\n' >"$work/names/Notchemon/PokeAPICreatureProvider.swift"
}

# Made-up species, so these tests never download the real list.
species="$work/species.txt"
printf 'zorbleflax\nquimbly\nmister-glonk\nvexel-f\n' >"$species"

names_check() {
  NOTCHEMON_SPECIES_LIST="$species" "$work/names/scripts/check-no-assets.sh" "$@" >"$work/names.out" 2>&1
}

# Runs the check with no list given, an empty cache, and a download that
# reads $work/download.json instead of the network.
download_check() {
  rm -rf "$work/cache"
  mkdir -p "$work/cache"
  env -u NOTCHEMON_SPECIES_LIST -u RUNNER_TEMP -u CI TMPDIR="$work/cache" \
    NOTCHEMON_SPECIES_URL="file://$work/download.json" "$@" \
    "$work/names/scripts/check-no-assets.sh" >"$work/names.out" 2>&1
}

names_fixture
names_check
check "name check passes the data source's identifiers" "0" "$?"
printf 'let title = "R\x6ftom Dex"\n' >"$work/names/Notchemon/Stats.swift"
names_check
check "name check fails on a species name" "1" "$?"

names_fixture
printf 'let title = "Pok\xc3\xa9 Ball Mode"\n' >"$work/names/Notchemon/Menu.swift"
names_check
check "name check fails on the ball's name" "1" "$?"

names_fixture
printf 'var p\x6fkeballMode = false\n' >"$work/names/Notchemon/Preferences.swift"
names_check
check "name check fails on a ball name in an identifier" "1" "$?"

names_fixture
printf 'let note = "Pok\xc3\xa9mon is a trademark of Nintendo, The Pok\xc3\xa9mon Company"\n' >"$work/names/Notchemon/Other.swift"
names_check
check "name check allows the disclaimer only where it belongs" "1" "$?"

species_case() {
  local name="$1" expected="$2" file="$3" text="$4"
  names_fixture
  mkdir -p "$(dirname "$work/names/$file")"
  printf '%s\n' "$text" >"$work/names/$file"
  names_check
  check "species check: $name" "$expected" "$?"
}

species_case "fails on a name in a string" 1 Notchemon/Title.swift 'let title = "Zorbleflax Forecast"'
species_case "fails on a name inside a camel-case identifier" 1 Notchemon/View.swift 'struct ZorbleflaxForecastView {}'
species_case "ignores case" 1 Notchemon/Title.swift 'let title = "QUIMBLY"'
species_case "ignores accents" 1 Notchemon/Title.swift 'let title = "Quïmbly"'
species_case "matches whole words only" 0 Notchemon/Title.swift 'let title = "Zorbleflaxing quimblyish"'
species_case "fails on a hyphenated name written apart" 1 Notchemon/Title.swift 'let title = "Mister Glonk"'
species_case "fails on a hyphenated name written joined" 1 Notchemon/View.swift 'struct MisterGlonkView {}'
check "species check: reports a joined name by its listed name" "1" "$(grep -c 'species name MisterGlonk (mister-glonk) in' "$work/names.out")"
species_case "fails on a form name without its letter" 1 Notchemon/Title.swift 'let title = "Vexel"'
species_case "fails on a name in project.yml" 1 project.yml 'NSLocationWhenInUseUsageDescription: "Quimbly weather"'
species_case "fails on a name in Info.plist" 1 Notchemon/Info.plist '<string>Quimbly weather</string>'
species_case "leaves Markdown to the franchise check" 0 README.md 'Quimbly'

names_fixture
mkdir -p "$work/names/Fake.app/Contents/MacOS"
printf 'abc\0Zorbleflax\0def' >"$work/names/Fake.app/Contents/MacOS/Fake"
names_check "$work/names/Fake.app"
check "species check: fails on a name in a built app" "1" "$?"
check "species check: names the file and line" "FAIL: Fake.app: species name Zorbleflax in Fake.app/Contents/MacOS/Fake:1 (string at byte 4)" \
  "$(grep '^FAIL: .*species name ' "$work/names.out")"

names_fixture
printf 'let tool = "/usr/bin/ditto"\n' >"$work/names/Notchemon/Title.swift"
printf 'ditto\n' >>"$species"
names_check
check "species check: fails on an ordinary word outside allowed_species" "1" "$?"
mkdir -p "$work/names/Fake.app/Contents/Frameworks/Sparkle.framework/Versions/B"
printf '/usr/bin/ditto' >"$work/names/Fake.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
rm "$work/names/Notchemon/Title.swift"
names_check "$work/names/Fake.app"
check "species check: allows an ordinary word where allowed_species says" "0" "$?"
check "species check: reports the allowed word" "1" "$(grep -c '^allowed: Fake.app: .*species name ditto' "$work/names.out")"
printf 'zorbleflax\nquimbly\nmister-glonk\nvexel-f\n' >"$species"

names_fixture
printf 'let title = "Quimbly"\n' >"$work/names/Notchemon/Title.swift"
perl -e 'print "{\"results\":[", join(",", map { "{\"name\":\"$_\"}" } (map { "zz$_" } "aaa" .. "bfz"), "quimbly"), "]}"' >"$work/download.json"
download_check
check "species check: downloads, parses, and fails on a listed name" "1" "$?"
check "species check: caches the download" "zzaaa quimbly" "$(sed -n '1p;$p' "$work/cache/notchemon-species-names.txt" | xargs)"
printf '{"results":[{"name":"quimbly"}]}' >"$work/download.json"
download_check
check "species check: a short list counts as a failed download" "0" "$?"
check "species check: says it skipped" "1" "$(grep -c 'species names: skipped' "$work/names.out")"
rm -f "$work/download.json"
download_check
check "species check: offline outside CI skips" "0" "$?"
download_check CI=true
check "species check: offline in CI fails" "1" "$?"

echo "test-scripts: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
