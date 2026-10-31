#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
sparkle_version=2.10.1
sparkle_digest=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
archive="$PWD/build/dependencies/Sparkle-$sparkle_version.tar.xz"
destination="$PWD/build/dependencies/Sparkle-$sparkle_version"
mkdir -p "$(dirname -- "$archive")"
if [[ ! -f "$archive" ]]; then
  /usr/bin/curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" -o "$archive.download"
  mv "$archive.download" "$archive"
fi
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
[[ "$actual" == "$sparkle_digest" ]] || { echo 'Sparkle archive checksum mismatch.' >&2; exit 1; }
if [[ ! -f "$destination/.verified-$sparkle_digest" ]]; then
  mkdir -p "$destination"
  tar -xJf "$archive" -C "$destination"
  touch "$destination/.verified-$sparkle_digest"
fi
printf '%s\n' "$destination"
