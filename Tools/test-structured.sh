#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
mkdir -p build/structured
(cd CloudBridge && npm test && npx --no-install tsc --noEmit --strict --skipLibCheck --target ES2022 --module NodeNext --moduleResolution NodeNext src/service.ts)
xcrun swiftc -swift-version 5 -parse-as-library Sources/Structured/CloudClient.swift Sources/Structured/StructuredEditor.swift Tests/StructuredEditorTests.swift -framework AppKit -framework SwiftUI -framework Security -o build/structured/editor-tests
build/structured/editor-tests
xcrun swiftc -swift-version 5 -D STRUCTURED_MODEL_TESTS -parse-as-library Sources/Structured/*.swift Tests/StructuredSyncTests.swift -framework AppKit -framework SwiftUI -framework Security -framework WebKit -o build/structured/sync-tests
build/structured/sync-tests
