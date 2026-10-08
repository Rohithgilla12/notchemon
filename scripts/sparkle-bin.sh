#!/usr/bin/env bash
# Prints the directory that holds Sparkle's command-line tools (generate_keys,
# generate_appcast, sign_update) for the Sparkle version pinned in project.yml.
# Swift Package Manager downloads them with the framework into .build/spm.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
packages="$root/.build/spm"

(cd "$root" && xcodegen generate -q)
xcodebuild -resolvePackageDependencies \
  -project "$root/Notchemon.xcodeproj" \
  -scheme Notchemon \
  -clonedSourcePackagesDirPath "$packages" \
  -quiet >&2

bin="$packages/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$bin/generate_appcast" ]]; then
  echo "Sparkle's tools are missing from $bin" >&2
  exit 1
fi
echo "$bin"
