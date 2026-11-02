#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
# The structured editor is now the main NotesPlus application.
NOTESPLUS_APP_PATH="${NOTESPLUS_STRUCTURED_APP_PATH:-$PWD/build/NotesPlus.app}" bash build.sh
