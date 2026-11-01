#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
app="${NOTESPLUS_STRUCTURED_APP_PATH:-$PWD/build/NotesPlus Experimental.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
(cd CloudBridge && npm run build)
cp build/structured/bridge.mjs "$app/Contents/Resources/bridge.mjs"
node_archive=build/structured/node-v22.23.4-darwin-arm64.tar.gz
if [ ! -f "$node_archive" ]; then
  curl -fLsS https://nodejs.org/dist/v22.23.4/node-v22.23.4-darwin-arm64.tar.gz -o "$node_archive"
fi
printf '%s  %s\n' c9e1dbc748b33ed2d14f42445191ecaf14c56259c7a9a26d0042c49ec2b66428 "$node_archive" | shasum -a 256 -c -
if [ ! -d build/structured/node-v22.23.4-darwin-arm64 ]; then tar -xzf "$node_archive" -C build/structured; fi
cp -f build/structured/node-v22.23.4-darwin-arm64/bin/node "$app/Contents/Resources/node"
cp build/structured/node-v22.23.4-darwin-arm64/LICENSE "$app/Contents/Resources/Node-LICENSE.txt"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp CloudBridge/vendor/icloud-md/LICENSE "$app/Contents/Resources/icloud-md-LICENSE.txt"
python3 - "$app/Contents/Resources/ThirdParty-Licenses.txt" <<'PY'
from pathlib import Path
import sys
root=Path('CloudBridge/node_modules')
licenses=[]
for path in sorted(root.rglob('*')):
    if path.is_file() and path.name.lower() in ('license','license.md','license.txt','copying'):
        licenses.append(str(path.relative_to(root))+'\n\n'+path.read_text(errors='replace'))
Path(sys.argv[1]).write_text('\n\n'.join(licenses))
PY
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.notesplus.structured-experiment</string>
<key>CFBundleName</key><string>NotesPlus Experimental</string>
<key>CFBundleDisplayName</key><string>NotesPlus Experimental</string>
<key>CFBundleExecutable</key><string>NotesPlus</string>
<key>CFBundleShortVersionString</key><string>0.8.0-experimental</string>
<key>CFBundleVersion</key><string>8</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -parse-as-library -g Sources/Structured/*.swift -framework AppKit -framework SwiftUI -framework WebKit -framework Security -o "$app/Contents/MacOS/NotesPlus"
codesign --force --sign - "$app"
printf '%s\n' "$app"
