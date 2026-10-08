#!/usr/bin/env bash
# Guardrail 1: no creature IP ships with Notchemon. Fails when the repository,
# or any .app passed as an argument, contains image or audio files or the names
# of the default starters and their evolution lines. It also fails on the
# franchise's own names outside the deliberate mentions in allowed_names, so
# the UI stays creature-neutral and the original-creature provider can
# replace the content (docs/takedown.md).
#
# Usage: scripts/check-no-assets.sh [path/to/Notchemon.app ...]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# Hex-encoded so this script does not itself contain the names it hunts for.
encoded_names="62756c626173617572 69767973617572 76656e7573617572 636861726d616e646572
636861726d656c656f6e 63686172697a617264 7371756972746c65 776172746f72746c65
626c6173746f697365 7069636875 70696b61636875 726169636875"

# Case-insensitive Perl regexes over raw bytes, escaped for the same reason.
# An accented e is UTF-8 lower or upper case, or e plus a combining acute.
acute='(?:\xc3\xa9|\xc3\x89|e\xcc\x81)'
franchise_names="pok(?:e|${acute})mon|pok${acute}|poke[ _-]?ball|r[o]tom"

# Each entry is "<path glob> <regex>". A name inside a match of an entry whose
# glob matches the file's path (from the repository root, or from the .app
# for a bundle) is allowed and reported. Any other name fails.
allowed_names=(
  # The data source, credited by name. A name glued to it still fails.
  "* pok${acute}api"
  # The IP disclaimer, which AboutTests keeps identical in both files.
  "README.md pok${acute}mon is a trademark of Nintendo, The pok${acute}mon Company"
  "Notchemon/App/AboutWindow.swift pok${acute}mon is a trademark of Nintendo, The pok${acute}mon Company"
  "*.app/Contents/MacOS/* pok${acute}mon is a trademark of Nintendo, The pok${acute}mon Company"
  # The data source's endpoint paths, which its provider requests by name.
  'Notchemon/Creature/PokeAPICreatureProvider.swift "pok[e]mon(?:-species)?/'
  'NotchemonTests/CreatureProviderTests.swift "pok[e]mon(?:-species)?/'
  'NotchemonTests/Fixtures.swift pokeapi\.co/api/v2/pok[e]mon-species/'
  '*.app/Contents/MacOS/* pok[e]mon(?:-species)?/'
  '*.app/Contents/PlugIns/NotchemonTests.xctest/* pok[e]mon(?:-species)?/'
)

media_extensions='png|jpe?g|gif|webp|bmp|tiff?|heic|heif|ico|icns|svg|car|mp3|wav|aiff?|m4a|aac|ogg|oga|flac|caf|mid'

patterns="$(mktemp)"
trap 'rm -f "$patterns"' EXIT
for hex in $encoded_names; do
  printf '%s' "$hex" | xxd -r -p >> "$patterns"
  printf '\n' >> "$patterns"
done

failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

is_media() {
  local file="$1"
  if echo "$file" | grep -Eiq "\.(${media_extensions})$"; then
    return 0
  fi
  case "$(file -b --mime-type "$file" 2>/dev/null)" in
    image/* | audio/*) return 0 ;;
  esac
  return 1
}

scan() {
  local label="$1"
  shift
  local count=0
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    count=$((count + 1))
    if is_media "$file"; then
      fail "$label: media file ${file#"$root"/}"
    fi
    if grep -a -i -q -F -f "$patterns" "$file"; then
      fail "$label: creature name inside ${file#"$root"/}"
    fi
  done
  echo "$label: scanned $count files"
}

# Prints "allowed:" for each name an allowed_names entry covers and "FAIL:"
# for any other, and returns 1 on a FAIL. Files are shown relative to base.
scan_names() {
  local label="$1" base="$2"
  shift 2
  perl -e '
    use strict;
    use warnings;
    my ($label, $base, $names, $rules) = splice(@ARGV, 0, 4);
    my @rules;
    for my $entry (split /\n/, $rules) {
      my ($glob, $regex) = split / /, $entry, 2;
      my $scope = join ".*", map { quotemeta } split /\*/, $glob, -1;
      push @rules, [qr/^$scope$/, qr/$regex/i, $regex];
    }
    my $names_re = qr/$names/i;
    my $failed = 0;
    for my $file (@ARGV) {
      next unless -f $file;
      my $shown = substr($file, length($base) + 1);
      open my $fh, "<:raw", $file or die "$file: $!";
      my $data = do { local $/; <$fh> } // "";
      next unless $data =~ $names_re;
      my @spans;
      for my $rule (grep { $shown =~ $_->[0] } @rules) {
        push @spans, [$-[0], $+[0], $rule->[2]] while $data =~ /$rule->[1]/g;
      }
      while ($data =~ /$names_re/g) {
        my ($start, $end) = ($-[0], $+[0]);
        my $line = 1 + (substr($data, 0, $start) =~ tr/\n//);
        my $hit = substr($data, $start, $end - $start);
        my ($cover) = grep { $_->[0] <= $start && $end <= $_->[1] } @spans;
        if ($cover) {
          print "allowed: $label: $shown:$line: $hit, by $cover->[2]\n";
        } else {
          print "FAIL: $label: franchise name $hit in $shown:$line\n";
          $failed = 1;
        }
      }
    }
    exit $failed;
  ' "$label" "$base" "$franchise_names" "$(printf '%s\n' "${allowed_names[@]}")" "$@"
}

repo_files=()
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r path; do
    repo_files+=("$root/$path")
  done < <(git -C "$root" ls-files --cached --others --exclude-standard)
else
  while IFS= read -r path; do
    repo_files+=("$path")
  done < <(find "$root" -type f -not -path '*/.build/*' -not -path '*/.git/*')
fi
scan "repo" "${repo_files[@]}"
scan_names "repo" "$root" "${repo_files[@]}" || fail "repo: franchise names outside allowed_names"

for app in "$@"; do
  if [[ ! -d "$app" ]]; then
    fail "no app bundle at $app"
    continue
  fi
  app_dir="$(cd "$app" && pwd)"
  app_files=()
  while IFS= read -r path; do
    app_files+=("$path")
  done < <(find "$app_dir" -type f)
  scan "$(basename "$app")" "${app_files[@]}"
  scan_names "$(basename "$app")" "$(dirname "$app_dir")" "${app_files[@]}" || fail "$(basename "$app"): franchise names outside allowed_names"
done

if [[ $failures -gt 0 ]]; then
  echo "check-no-assets: $failures problem(s) found"
  exit 1
fi
echo "check-no-assets: clean"
