#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
app="$1"
mkdir -p "$app/Contents/Resources" build/structured
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
