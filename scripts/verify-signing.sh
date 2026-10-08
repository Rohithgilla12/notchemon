#!/usr/bin/env bash
# Verifies a Developer ID signed Notchemon.app: the bundle passes a deep strict
# check, and the app and every piece of Sparkle's nested code carry the team's
# identity, the hardened runtime, and a secure timestamp, which notarisation
# requires.
#
# Usage: scripts/verify-signing.sh path/to/Notchemon.app
set -euo pipefail

app="${1:?usage: verify-signing.sh path/to/Notchemon.app}"
team="7D2V3RM56T"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"

codesign --verify --deep --strict --verbose=2 "$app"

code_paths=("$app" "$sparkle" "$sparkle/Autoupdate" "$sparkle/Updater.app")
for xpc in "$sparkle"/XPCServices/*.xpc; do
  [[ -e "$xpc" ]] && code_paths+=("$xpc")
done

failures=0
for code in "${code_paths[@]}"; do
  details="$(codesign -dv --verbose=4 "$code" 2>&1)"
  echo "${code#"$app"/}"
  grep -E "^(Authority|TeamIdentifier|Timestamp)=" <<<"$details" | sed 's/^/  /'
  if ! grep -q "^TeamIdentifier=$team$" <<<"$details"; then
    echo "  FAIL: not signed by team $team"
    failures=$((failures + 1))
  fi
  if ! grep -Eq "^CodeDirectory .*flags=.*runtime" <<<"$details"; then
    echo "  FAIL: hardened runtime is off"
    failures=$((failures + 1))
  fi
  if ! grep -q "^Timestamp=" <<<"$details"; then
    echo "  FAIL: no secure timestamp"
    failures=$((failures + 1))
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "verify-signing: $failures problem(s) found"
  exit 1
fi
echo "verify-signing: ok"
