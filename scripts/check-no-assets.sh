#!/usr/bin/env bash
# Guardrail 1: no creature IP ships with Notchemon. Fails when the repository,
# or any .app passed as an argument, contains image or audio files or the names
# of the default starters and their evolution lines. It also fails on the
# franchise's own names outside the deliberate mentions in allowed_names, so
# the UI stays creature-neutral and the original-creature provider can
# replace the content (docs/takedown.md).
#
# Guardrail 2: no species name in the code or the app. Swift sources, plists,
# project.yml, and every file of each .app are matched word by word against
# the full species list, downloaded from PokeAPI at check time and cached in a
# temporary folder, never in the repository. Offline, the step is skipped,
# except in CI (CI=true), where a failed download fails the check.
#
# Usage: scripts/check-no-assets.sh [path/to/Notchemon.app ...]
#
# NOTCHEMON_SPECIES_LIST names a file of species names, one per line, to use
# instead of the download. NOTCHEMON_SPECIES_URL overrides the download URL.
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
  'scripts/check-no-assets.sh pokeapi\.co/api/v2/pok[e]mon-species\?'
)

species_url="${NOTCHEMON_SPECIES_URL:-https://pokeapi.co/api/v2/pokemon-species?limit=2000}"

# Each entry is "<path glob> <species name>", for a name that is also an
# ordinary word and appears as that word in the files the glob matches. Every
# hit an entry covers is reported. Any other species name fails.
allowed_species=(
  # Sparkle's installer unpacks updates with /usr/bin/ditto.
  "*.app/*/Sparkle.framework/Versions/B/Autoupdate ditto"
  # Xcode's own test frameworks, which some Xcode versions copy into the
  # Debug test host. A Release build never contains them.
  "*.app/*/XCUIAutomation.framework/Versions/A/XCUIAutomation type-null"
  "*.app/*/Testing.framework/Versions/A/Testing paras"
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

# Prints the path of the species list, one name per line, downloading it into
# the cache on first use. Returns 1 when there is no list to use.
species_list() {
  if [[ -n "${NOTCHEMON_SPECIES_LIST:-}" ]]; then
    [[ -s "$NOTCHEMON_SPECIES_LIST" ]] || return 1
    printf '%s\n' "$NOTCHEMON_SPECIES_LIST"
    return 0
  fi
  local cache="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
  cache="${cache%/}/notchemon-species-names.txt"
  if [[ ! -s "$cache" ]]; then
    # A short or unparsable reply would make the check pass vacuously.
    curl -fsSL --max-time 30 "$species_url" 2>/dev/null | perl -MJSON::PP -e '
      local $/;
      my $reply = eval { decode_json(<STDIN>) } or exit 1;
      my @names = map { $_->{name} } @{ $reply->{results} || [] };
      exit 1 if @names < 800;
      print "$_\n" for @names;
    ' >"$cache.$$" && mv "$cache.$$" "$cache" || {
      rm -f "$cache.$$"
      return 1
    }
  fi
  printf '%s\n' "$cache"
}

# Splits text into words at spaces, punctuation, digits, and camel case, so
# "WeatherView" is two words and "Weathery" is one, and matches the words
# against the list. A hyphenated name matches its words in a row, joined or
# apart. Prints "allowed:" for each hit an allowed_species entry covers and
# "FAIL:" for any other, and returns 1 on a FAIL.
scan_species() {
  local label="$1" base="$2" list="$3"
  shift 3
  perl -e '
    use strict;
    use warnings;
    use Encode qw(decode);
    use Unicode::Normalize qw(NFD);
    my ($label, $base, $list, $rules) = splice(@ARGV, 0, 4);
    sub words {
      my $text = NFD(shift);
      $text =~ s/\p{Mn}//g;
      my @words;
      while ($text =~ /(\p{Lu}?\p{Ll}+|\p{Lu}+(?!\p{Ll})|\d+)/g) {
        push @words, [lc $1, $-[0], $+[0]];
      }
      return (\@words, $text);
    }
    my %by_first;
    # Each spelling keeps the name as listed, which allowed_species uses.
    sub add {
      my ($name, @parts) = @_;
      push @{ $by_first{ $parts[0] } }, [lc $name, \@parts];
    }
    open my $names, "<:encoding(UTF-8)", $list or die "$list: $!";
    while (my $name = <$names>) {
      chomp $name;
      my @parts = map { $_->[0] } @{ (words($name))[0] };
      next unless @parts;
      add($name, @parts);
      next unless @parts > 1;
      add($name, join "", @parts);
      # A one-letter last part marks a form, as in a name ending -f or -m.
      add($name, @parts[0 .. $#parts - 1]) if length $parts[-1] == 1;
    }
    $_ = [sort { @{ $b->[1] } <=> @{ $a->[1] } } @$_] for values %by_first;
    my @rules;
    for my $entry (split /\n/, $rules) {
      my ($glob, $word) = split / /, $entry, 2;
      my $scope = join ".*", map { quotemeta } split /\*/, $glob, -1;
      push @rules, [qr/^$scope$/, lc $word, $entry];
    }
    sub hits {
      my ($words, $text) = words(shift);
      my @hits;
      WORD: for my $i (0 .. $#$words) {
        my $candidates = $by_first{ $words->[$i][0] } or next;
        CANDIDATE: for my $candidate (@$candidates) {
          my ($name, $parts) = @$candidate;
          my $last = $i + $#$parts;
          next if $last > $#$words;
          for my $k (1 .. $#$parts) {
            next CANDIDATE if $words->[ $i + $k ][0] ne $parts->[$k];
            my ($after, $before) = ($words->[ $i + $k - 1 ][2], $words->[ $i + $k ][1]);
            next CANDIDATE unless substr($text, $after, $before - $after) =~ /^[\s._-]*$/;
          }
          my ($start, $end) = ($words->[$i][1], $words->[$last][2]);
          push @hits, [$start, substr($text, $start, $end - $start), $name];
          next WORD;
        }
      }
      return ($text, @hits);
    }
    # A text file is matched whole. A binary is matched string by string, as
    # strings(1) reads it, so bytes of machine code never run into a word.
    sub pieces {
      my ($raw) = @_;
      return ["", decode("UTF-8", $raw)] if index($raw, "\0") < 0;
      my @pieces;
      while ($raw =~ /((?:[\t\n\x20-\x7e]|[\xc2-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf]{2}|[\xf0-\xf4][\x80-\xbf]{3}){4,})/g) {
        push @pieces, [" (string at byte $-[0])", decode("UTF-8", $1)];
      }
      return @pieces;
    }
    my ($failed, %seen) = (0);
    for my $file (@ARGV) {
      next if $seen{$file}++ or !-f $file;
      my $shown = substr($file, length($base) + 1);
      my @mine = grep { $shown =~ $_->[0] } @rules;
      open my $fh, "<:raw", $file or die "$file: $!";
      my $raw = do { local $/; <$fh> } // "";
      for my $piece (pieces($raw)) {
        my ($where, $source) = @$piece;
        my ($text, @hits) = hits($source);
        my ($line, $counted) = (1, 0);
        for my $hit (@hits) {
          my ($start, $shown_hit, $name) = @$hit;
          $line += substr($text, $counted, $start - $counted) =~ tr/\n//;
          $counted = $start;
          $shown_hit .= " ($name)" if lc $shown_hit ne $name;
          my ($cover) = grep { $_->[1] eq $name } @mine;
          if ($cover) {
            print "allowed: $label: $shown:$line$where: species name $shown_hit, by $cover->[2]\n";
          } else {
            print "FAIL: $label: species name $shown_hit in $shown:$line$where\n";
            $failed = 1;
          }
        }
      }
    }
    exit $failed;
  ' "$label" "$base" "$list" "$(printf '%s\n' "${allowed_species[@]+"${allowed_species[@]}"}")" "$@"
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

if species="$(species_list)"; then
  echo "species names: $(grep -c . "$species") from $species"
else
  species=""
  if [[ "${CI:-}" == "true" ]]; then
    fail "species names: could not download the list from $species_url"
  else
    echo "species names: skipped, could not download the list from $species_url (offline?). CI runs this step."
  fi
fi

# XcodeGen writes Info.plist, so it is not among the tracked files.
species_files=("$root/Notchemon/Info.plist")
for file in "${repo_files[@]}"; do
  case "$file" in
    *.swift | *.plist | "$root/project.yml") species_files+=("$file") ;;
  esac
done
if [[ -n "$species" ]]; then
  scan_species "repo" "$root" "$species" "${species_files[@]}" || fail "repo: species names outside allowed_species"
fi

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
  if [[ -n "$species" ]]; then
    scan_species "$(basename "$app")" "$(dirname "$app_dir")" "$species" "${app_files[@]}" || fail "$(basename "$app"): species names outside allowed_species"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "check-no-assets: $failures problem(s) found"
  exit 1
fi
echo "check-no-assets: clean"
