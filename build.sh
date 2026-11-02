#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build
sparkle_path=$(bash Tools/fetch-sparkle.sh)
app_path="${NOTESPLUS_APP_PATH:-$PWD/../outputs/NotesPlus.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
ditto "$sparkle_path/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_path/LICENSE" "$app_path/Contents/Resources/Sparkle-LICENSE.txt"
bash Tools/bundle-cloud.sh "$app_path"
xcrun swiftc -D STRUCTURED_APP -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library -O \
 Sources/Structured/*.swift Sources/EditorSettings.swift Sources/Timestamp.swift Sources/NotesPlusApp.swift Sources/AppUpdater.swift \
 -framework AppKit -framework SwiftUI -framework WebKit -framework Security -F "$sparkle_path" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
 -o "$app_path/Contents/MacOS/NotesPlus"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
# The bundled Node runtime uses JIT. It has its own signature and is not
# injected into the app process; no SIP changes or library injection are used.
codesign --force --sign "${NOTESPLUS_SIGN_IDENTITY:--}" "$app_path"
codesign --verify --deep --strict "$app_path"
printf '%s\n' "$app_path"
