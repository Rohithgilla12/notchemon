#!/usr/bin/env bash
# One-time setup for signed updates. Creates the EdDSA key pair in your login
# Keychain, or reuses the one already there, and writes the public key into
# project.yml as SUPublicEDKey. The private key never leaves the Keychain and
# this script never prints it. Running it again changes nothing.
#
# Usage: scripts/setup-sparkle-keys.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
account="notchemon"
bin="$("$root/scripts/sparkle-bin.sh")"

# Without -p, generate_keys creates a key only when the account has none. It
# prints the public key and setup hints, never the private key; -p prints the
# public key alone.
"$bin/generate_keys" --account "$account" >/dev/null
public_key="$("$bin/generate_keys" --account "$account" -p)"

if [[ ! "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "generate_keys returned something that is not an EdDSA public key." >&2
  exit 1
fi

sed -i '' -E "s|^([[:space:]]*SUPublicEDKey:).*|\1 \"$public_key\"|" "$root/project.yml"
grep -q "SUPublicEDKey: \"$public_key\"" "$root/project.yml"

echo "SUPublicEDKey: $public_key"
echo "Wrote the public key to project.yml. Commit that change."
echo
echo "Back up the private key to 1Password now. If you lose it, installed copies"
echo "can never verify another update. See docs/releasing.md, or run:"
echo
echo "  backup=\"\$(mktemp -d)/sparkle-private-key\""
echo "  \"$bin/generate_keys\" --account $account -x \"\$backup\""
echo "  op item create --vault Private --category \"Secure Note\" --title notchemon-sparkle \"ed-private-key[file]=\$backup\""
echo "  rm -P \"\$backup\""
