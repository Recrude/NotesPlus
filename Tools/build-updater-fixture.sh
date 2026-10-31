#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source_app="${1:-$PWD/build/staging-0.7/NotesPlus.app}"
stage=$(mktemp -d "$PWD/build/updater-fixture.XXXXXX")
sparkle_path=$(bash Tools/fetch-sparkle.sh)
python3 - "$stage" <<'PY'
from pathlib import Path
import sys
stage=Path(sys.argv[1])
(stage/'MainWindow.swift').write_text(Path('Sources/MainWindow.swift').read_text().replace('@main struct NotesPlusApp','struct NotesPlusApp'))
(stage/'FakeNotes.swift').write_text(Path('Tests/AutosaveTests.swift').read_text().split('@main struct AutosaveTests')[0])
PY
xcrun swiftc -swift-version 5 -parse-as-library -import-objc-header Sources/NotesStore.h \
  "$stage/MainWindow.swift" "$stage/FakeNotes.swift" Tests/UpdaterFixture.swift \
  Sources/NotesPlusApp.swift Sources/AppUpdater.swift Sources/Model.swift Sources/SyncHistory.swift Sources/DraftWriter.swift \
  Sources/RichTextBridge.swift Sources/EditorSettings.swift Sources/Timestamp.swift Sources/NotesBackend.swift \
  Sources/TextCodec.swift Sources/NoteDocument.swift Sources/NoteEditor.swift Sources/ListRules.swift build/NotesStore.o \
  -framework AppKit -framework SwiftUI -framework ScriptingBridge -F "$sparkle_path" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$stage/NotesPlus"
mkdir -p "$stage/installed" "$stage/next" "$stage/feed" "$stage/support"
for destination in installed next; do
  ditto "$source_app" "$stage/$destination/NotesPlus Update Test.app"
  cp "$stage/NotesPlus" "$stage/$destination/NotesPlus Update Test.app/Contents/MacOS/NotesPlus"
done
python3 - "$stage" <<'PY'
import plistlib,sys,uuid
from pathlib import Path
stage=Path(sys.argv[1]); identifier='dev.notesplus.updater-fixture.'+uuid.uuid4().hex
for destination,version,build in [('installed','0.6.9','6'),('next','0.7.0','7')]:
    p=stage/destination/'NotesPlus Update Test.app/Contents/Info.plist'
    info=plistlib.loads(p.read_bytes())
    info.update(CFBundleIdentifier=identifier,CFBundleName='NotesPlus Update Test',CFBundleDisplayName='NotesPlus Update Test',CFBundleShortVersionString=version,CFBundleVersion=build,SUFeedURL='http://127.0.0.1:8765/appcast.xml',SUEnableAutomaticChecks=False,NSAppTransportSecurity={'NSAllowsLocalNetworking':True},NotesPlusFixtureSupport=str(stage/'support'))
    p.write_bytes(plistlib.dumps(info))
print('Fixture bundle: '+identifier)
PY
for destination in installed next; do
  codesign --force --sign - --options runtime --entitlements build/NotesPlus-adhoc.entitlements "$stage/$destination/NotesPlus Update Test.app"
done
ditto -c -k --sequesterRsrc --keepParent "$stage/next/NotesPlus Update Test.app" "$stage/feed/NotesPlusUpdateTest-0.7.0.zip"
cp Release/0.7.0.html "$stage/feed/NotesPlusUpdateTest-0.7.0.html"
"$sparkle_path/bin/generate_appcast" --account dev.notesplus.updates --maximum-deltas 0 --download-url-prefix http://127.0.0.1:8765/ --embed-release-notes "$stage/feed"
printf '%s\n' "$stage" > build/latest-updater-fixture.txt
printf 'Fixture ready: %s\n' "$stage"
printf 'Serve: python3 -m http.server 8765 --bind 127.0.0.1 --directory "%s/feed"\n' "$stage"
