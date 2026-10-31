#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build
sparkle_path=$(bash Tools/fetch-sparkle.sh)
app_path="${NOTESPLUS_APP_PATH:-$PWD/../outputs/NotesPlus.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
ditto "$sparkle_path/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_path/LICENSE" "$app_path/Contents/Resources/Sparkle-LICENSE.txt"
xcrun clang -fobjc-arc -Wall -Wextra -c Sources/NotesStore.m -o build/NotesStore.o
xcrun clang -fobjc-arc Tests/SnapshotReadTests.m build/NotesStore.o -framework Foundation -framework ScriptingBridge -o build/notesplus-snapshot-tests
./build/notesplus-snapshot-tests | tee build/snapshot-test-results.txt
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library -O -import-objc-header Sources/NotesStore.h \
  Sources/MainWindow.swift Sources/NotesPlusApp.swift Sources/AppUpdater.swift Sources/Model.swift Sources/SyncHistory.swift Sources/DraftWriter.swift Sources/RichTextBridge.swift Sources/EditorSettings.swift Sources/Timestamp.swift Sources/NotesBackend.swift Sources/TextCodec.swift Sources/NoteDocument.swift Sources/NoteEditor.swift Sources/ListRules.swift build/NotesStore.o \
  -framework AppKit -framework SwiftUI -framework ScriptingBridge -F "$sparkle_path" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$app_path/Contents/MacOS/NotesPlus"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
fi
entitlements=Resources/NotesPlus.entitlements
if [[ "${NOTESPLUS_SIGN_IDENTITY:--}" == "-" ]]; then
  cp "$entitlements" build/NotesPlus-adhoc.entitlements
  /usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.disable-library-validation bool true' build/NotesPlus-adhoc.entitlements
  entitlements=build/NotesPlus-adhoc.entitlements
else
  codesign --force --sign "$NOTESPLUS_SIGN_IDENTITY" --timestamp "$app_path/Contents/Frameworks/Sparkle.framework"
fi
signing_args=(--force --sign "${NOTESPLUS_SIGN_IDENTITY:--}" --options runtime --entitlements "$entitlements")
if [[ "${NOTESPLUS_SIGN_IDENTITY:--}" != "-" ]]; then signing_args+=(--timestamp); fi
codesign "${signing_args[@]}" "$app_path"
codesign --verify --deep --strict "$app_path"
xcrun swiftc -swift-version 5 -parse-as-library Sources/TextCodec.swift Sources/NoteDocument.swift Tests/CodecTests.swift -framework AppKit -o build/notesplus-codec-tests
./build/notesplus-codec-tests | tee build/codec-test-results.txt
xcrun swiftc -swift-version 5 -parse-as-library -import-objc-header Sources/NotesStore.h \
  Sources/Model.swift Sources/SyncHistory.swift Sources/DraftWriter.swift Sources/RichTextBridge.swift Sources/EditorSettings.swift Sources/Timestamp.swift Sources/NotesBackend.swift Sources/TextCodec.swift Sources/NoteDocument.swift Tests/AutosaveTests.swift build/NotesStore.o \
  -framework AppKit -framework SwiftUI -framework ScriptingBridge -o build/notesplus-autosave-tests
./build/notesplus-autosave-tests | tee build/autosave-test-results.txt
xcrun swiftc -swift-version 5 -parse-as-library \
  Sources/EditorSettings.swift Sources/Timestamp.swift Sources/RichTextBridge.swift Sources/TextCodec.swift Sources/NoteDocument.swift Sources/ListRules.swift Sources/NoteEditor.swift Tests/SettingsTests.swift \
  -framework AppKit -framework SwiftUI -o build/notesplus-settings-tests
./build/notesplus-settings-tests | tee build/settings-test-results.txt
