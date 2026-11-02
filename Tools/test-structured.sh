#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
mkdir -p build/structured
(cd CloudBridge && npm test && npx --no-install tsc --noEmit --strict --skipLibCheck --target ES2022 --module NodeNext --moduleResolution NodeNext src/service.ts)
xcrun swiftc -D STRUCTURED_APP -swift-version 5 -parse-as-library Sources/EditorSettings.swift Sources/Timestamp.swift Sources/Structured/CloudClient.swift Sources/Structured/StructuredEditor.swift Tests/StructuredEditorTests.swift -framework AppKit -framework SwiftUI -framework Security -o build/structured/editor-tests
build/structured/editor-tests
xcrun swiftc -D STRUCTURED_APP -swift-version 5 -D STRUCTURED_MODEL_TESTS -parse-as-library Sources/EditorSettings.swift Sources/Timestamp.swift Sources/Structured/CloudClient.swift Sources/Structured/CloudLogin.swift Sources/Structured/StructuredEditor.swift Sources/Structured/StructuredApp.swift Tests/StructuredSyncTests.swift -framework AppKit -framework SwiftUI -framework Security -framework WebKit -o build/structured/sync-tests
build/structured/sync-tests
xcrun swiftc -D STRUCTURED_APP -swift-version 5 -D STRUCTURED_MODEL_TESTS -parse-as-library Sources/EditorSettings.swift Sources/Timestamp.swift Sources/Structured/CloudClient.swift Sources/Structured/CloudLogin.swift Sources/Structured/StructuredEditor.swift Sources/Structured/StructuredApp.swift Tests/StructuredBetaTests.swift -framework AppKit -framework SwiftUI -framework Security -framework WebKit -o build/structured/beta-tests
build/structured/beta-tests
(cd CloudBridge && npx --no-install tsx src/editorFixture.ts)
xcrun swiftc -D STRUCTURED_APP -swift-version 5 -parse-as-library Sources/EditorSettings.swift Sources/Timestamp.swift Sources/Structured/CloudClient.swift Sources/Structured/StructuredEditor.swift Tests/StructuredRichTests.swift -framework AppKit -framework SwiftUI -framework Security -o build/structured/rich-editor-tests
build/structured/rich-editor-tests
(cd CloudBridge && npx --no-install tsx src/editorFixture.ts verify)
