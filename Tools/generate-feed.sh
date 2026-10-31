#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)
public_key=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Resources/Info.plist)
archive="${1:-$PWD/../outputs/NotesPlus-$version-macOS-arm64.zip}"
sparkle_path=$(bash Tools/fetch-sparkle.sh)
account="${NOTESPLUS_UPDATE_ACCOUNT:-dev.notesplus.updates}"
stored_key=$("$sparkle_path/bin/generate_keys" --account "$account" -p)
[[ "$stored_key" == "$public_key" ]] || { echo 'The release signing key does not match the app public key.' >&2; exit 1; }
stage=$(mktemp -d "$PWD/build/appcast.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp "$archive" "$stage/"
name=$(basename -- "$archive" .zip)
cp "Release/$version.html" "$stage/$name.html"
if [[ -f Release/appcast.xml ]]; then cp Release/appcast.xml "$stage/appcast.xml"; fi
"$sparkle_path/bin/generate_appcast" --account "$account" --versions "$build" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/Recrude/NotesPlus/releases/download/v$version/" \
  --link "https://github.com/Recrude/NotesPlus/releases/tag/v$version" --embed-release-notes "$stage"
"$sparkle_path/bin/sign_update" --account "$account" --verify "$stage/appcast.xml"
cp "$stage/appcast.xml" Release/appcast.xml
printf 'Signed update feed prepared for NotesPlus %s (%s).\n' "$version" "$build"
