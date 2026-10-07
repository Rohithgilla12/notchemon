#!/usr/bin/env bash
# Guardrail 1: no creature IP ships with Notchemon. Fails when the repository,
# or any .app passed as an argument, contains image or audio files or the names
# of the default starters and their evolution lines.
#
# Usage: scripts/check-no-assets.sh [path/to/Notchemon.app ...]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# Hex-encoded so this script does not itself contain the names it hunts for.
encoded_names="62756c626173617572 69767973617572 76656e7573617572 636861726d616e646572
636861726d656c656f6e 63686172697a617264 7371756972746c65 776172746f72746c65
626c6173746f697365 7069636875 70696b61636875 726169636875"

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

for app in "$@"; do
  if [[ ! -d "$app" ]]; then
    fail "no app bundle at $app"
    continue
  fi
  app_files=()
  while IFS= read -r path; do
    app_files+=("$path")
  done < <(find "$app" -type f)
  scan "$(basename "$app")" "${app_files[@]}"
done

if [[ $failures -gt 0 ]]; then
  echo "check-no-assets: $failures problem(s) found"
  exit 1
fi
echo "check-no-assets: clean"
