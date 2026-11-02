Source: https://github.com/coddingtonbear/icloud-md
Commit: ffa20ef6378a453f0935d26f03acedf3e58540f2
License: MIT (LICENSE).
Selected source and test dependency closure. debugLog.ts is replaced with a no-log fetch wrapper: no session cookies or note bodies are logged. databaseClient.updateRecords explicitly requests atomic:true for note + table batches, matching CloudKit's documented default. The native formatting adaptation is maintained separately in ../../src/nativeFormat.ts.
Generated files have a redundant blank line removed at EOF; no generated declarations changed.

## NotesPlus 0.8 beta integration

`databaseClient.ts` additionally accepts explicitly marked `create` operations
in an atomic record batch. An update still requires a change tag. This allows
new table attachments to be created atomically with the note that references
them. `src/tableCreate.ts` outside this vendor directory derives a fresh empty
table from the MIT-licensed empty fixture, remapping all UUIDs while preserving
clock ordering, then uses the upstream incremental editor and validation gates.

`noteDocument.ts` registers new topotext replicas in UUID-sorted order and
remaps existing character and style coordinates, matching the rule already
implemented in upstream `tableEdit.ts`. Appending a lower UUID to the table
caused full-body duplication on native Notes merge in a controlled live test.
Unsorted or duplicate source replica tables are refused rather than guessed at.
