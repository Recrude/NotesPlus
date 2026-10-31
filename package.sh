#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
source_app="${1:-$PWD/../outputs/NotesPlus.app}"
output_dir="$PWD/../outputs"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$source_app/Contents/Info.plist")
bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$source_app/Contents/Info.plist")
[[ "$bundle" == "dev.notesplus.prototype" ]] || { echo 'Unexpected app bundle.' >&2; exit 1; }
codesign --verify --deep --strict "$source_app"
mkdir -p "$output_dir"
release_temp=$(mktemp -d "${TMPDIR:-/tmp}/notesplus-release.XXXXXX")
trap 'rm -rf "$release_temp"' EXIT
mkdir -p "$release_temp/image"
release_app="$release_temp/image/NotesPlus.app"
ditto "$source_app" "$release_app"
identity="${NOTESPLUS_SIGN_IDENTITY:--}"
profile="${NOTESPLUS_NOTARY_PROFILE:-}"
if [[ -n "$profile" && "$identity" == "-" ]]; then
  echo 'Notarization requires NOTESPLUS_SIGN_IDENTITY (Developer ID Application).' >&2; exit 1
fi
if [[ "$identity" != "-" ]]; then
  codesign --force --sign "$identity" --timestamp --options runtime --entitlements Resources/NotesPlus.entitlements "$release_app"
fi
codesign --verify --deep --strict "$release_app"
archive="$release_temp/NotesPlus-$version-macOS-arm64.zip"
disk_image="$release_temp/NotesPlus-$version-macOS-arm64.dmg"
notarize() {
  local artifact="$1" report="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait --output-format json > "$report"
  python3 - "$report" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('status')!='Accepted':
    raise SystemExit('Notarization was not accepted; inspect '+sys.argv[1])
PY
}
if [[ -n "$profile" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_temp/notarization.zip"
  notarize "$release_temp/notarization.zip" "$output_dir/NotesPlus-$version-app-notarization.json"
  xcrun stapler staple "$release_app"
  xcrun stapler validate "$release_app"
  spctl --assess --type execute --verbose "$release_app"
fi
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$archive"
ln -s /Applications "$release_temp/image/Applications"
cp Release/READ-ME.txt "$release_temp/image/READ-ME.txt"
if [[ -n "$profile" ]]; then
  printf '\n이 패키지는 Developer ID 서명 및 Apple 공증을 완료했습니다.\n' >> "$release_temp/image/READ-ME.txt"
else
  printf '\n이 패키지는 공증 전 시험 빌드입니다. 공개 배포용 공증이 완료되지 않았습니다.\n' >> "$release_temp/image/READ-ME.txt"
fi
hdiutil create -volname "NotesPlus $version" -srcfolder "$release_temp/image" -format UDZO -ov "$disk_image"
if [[ "$identity" != "-" ]]; then codesign --force --sign "$identity" --timestamp "$disk_image"; fi
if [[ -n "$profile" ]]; then
  notarize "$disk_image" "$output_dir/NotesPlus-$version-dmg-notarization.json"
  xcrun stapler staple "$disk_image"
  xcrun stapler validate "$disk_image"
fi
hdiutil verify "$disk_image"
python3 - "$archive" "$disk_image" "$version" "$identity" "$profile" <<'PY'
import hashlib,json,pathlib,sys,zipfile
archive,disk_image,version,identity,profile=sys.argv[1:]
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    actual={n for n in z.namelist() if not n.endswith('/') and not n.startswith('__MACOSX/')}
    allowed={'NotesPlus.app/Contents/'+n for n in ['MacOS/NotesPlus','Info.plist','Resources/AppIcon.icns','Resources/Sparkle-LICENSE.txt','_CodeSignature/CodeResources']}
    unexpected={n for n in actual-allowed if not n.startswith('NotesPlus.app/Contents/Frameworks/Sparkle.framework/')}
    assert not unexpected, 'Unexpected files in application archive: '+str(unexpected)
artifacts=[pathlib.Path(archive),pathlib.Path(disk_image)]
checksums={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in artifacts}
out=artifacts[0].parent
(out/f'NotesPlus-{version}-SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name,digest in checksums.items()))
manifest={'version':version,'architecture':'arm64','minimum_macos':'26.0','signing':'ad-hoc' if identity=='-' else 'Developer ID','notarized':bool(profile),'release_channel':'release' if profile else 'prerelease','requires_manual_open':not bool(profile),'artifacts':checksums}
(out/f'NotesPlus-{version}-release.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
PY
mv -f "$archive" "$disk_image" "$release_temp/NotesPlus-$version-SHA256SUMS.txt" "$release_temp/NotesPlus-$version-release.json" "$output_dir/"
