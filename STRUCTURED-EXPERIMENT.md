> Historical experiment record. The integrated 0.8 beta is described in README.md and BETA-VALIDATION.md.

# Structured iCloud editor experiment

This is a separate NotesPlus Experimental build, not the public 0.7 updater.
It replaces the HTML Apple Events bridge with a native AppKit editor and a
structured CloudKit bridge. The document is never converted through Markdown
or HTML. Checklists carry Apple's checklist UUID/state; tables keep their
attachment records and CRDT data.

## Verified on 2026-11-01

On this Mac and the user's paired iPhone, using only the `NotesPlus 실험` folder:

1. Created a note in NotesPlus, converted two paragraphs to checklists, and
   checked the first item. The Mac Notes accessibility tree reported a checked
   checklist item and the iPhone Notes screen displayed the actual yellow check.
2. Checked the second item and edited its text in iPhone Notes. NotesPlus
   received both changes and remained editable. Edited the item and trailing
   body in NotesPlus; both changes appeared in iPhone Notes.
3. Added an Apple Notes table to the same note, loaded it in NotesPlus, edited
   a cell, and applied a bullet list to another paragraph. Mac and iPhone Notes
   retained both checklist states, the bullet list, all four table cells and
   the trailing body. Restarted NotesPlus and reloaded the same structure.
4. Typed `1.` followed by space in an empty paragraph and continued with Return.
   NotesPlus displayed actual numbered paragraphs as 1 and 2. Fixed the save
   verifier to treat Apple's omitted default start number as 1, restored the
   complete draft after restart, and verified both numbered paragraphs alongside
   the checks, bullet, table and full body in Mac Notes. The paired phone was
   disconnected during this final numbered-list check; the three device checks
   above had already passed.

The test note is named `NotesPlus 구조 동기화 1101`. Existing personal notes were
not modified. Phone text input during automation produced isolated Hangul jamo;
those test characters were replaced in NotesPlus after verifying their arrival.
This was a keyboard automation issue, not evidence of an IME acceptance test.

## Build and test

```sh
cd CloudBridge
npm ci --ignore-scripts
cd ..
bash Tools/test-structured.sh
bash Tools/build-structured.sh
```

Build output: `build/NotesPlus Experimental.app` (macOS 26, Apple silicon).
The build downloads the official Node 22.23.4 arm64 runtime and verifies its
pinned SHA-256. Node and dependency licenses are included. Developer ID signing
and notarization are not applied.

Native tests cover mixed tables/lists/body, inline formatting, UTF-16 emoji,
checklist continuation, list conversion, numbered continuation, literal `* `,
typing while a save is pending, stale acknowledged-version readback, remote
edits, full conflict drafts, and retry. TypeScript tests include the pinned
upstream codec/CRDT tests and NotesPlus-specific round trips and merges.

## Saving and privacy

- Debounced autosave after 1.2 seconds; long typing sessions also save periodically.
- Network and encoding run outside the main thread. Save acknowledgements do not
  replace newer typing or reset its cursor.
- Reads verify record change tags before installing the document. Note and table
  updates use conditional change tags in an explicit atomic batch.
- Three-way reconciliation merges independent paragraph/cell edits. A conflicting
  paragraph keeps the full local document editable and journals it locally.
- Superseded versions are ignored after a successful save, including after restart.
- Authentication uses Apple's visible iCloud sign-in page. Session data is stored
  in the local Keychain and sent to the helper through stdin, never command-line
  arguments. The helper connects to Apple's iCloud hosts; it has no external server
  and logs neither cookies nor note bodies.
- Local drafts/history are stored with owner-only permissions under
  `~/Library/Application Support/NotesPlus Experimental`.

## Deliberate limits before integration into the release app

The new bridge is unofficial and uses Apple's undocumented Notes data format.
Passing these device tests does not establish full compatibility with every
Apple Notes feature or future macOS/iOS version.

This build lists and writes only `NotesPlus 실험`. It supports creating notes and
checklists, native body/list editing and editing existing table cells. It does
not yet offer table creation, row/column controls, moving/deleting tables, shared
or locked notes, non-table attachment editing, or very large asset-backed notes.
Complex simultaneous edits can require manual resolution; no full Apple CRDT
merge engine is claimed. Unsupported data fails preservation checks before upload.
The old app's full settings, timestamp shortcut, folder UI and Sparkle updater
have not yet been integrated into this experimental target. Those features remain
in the unchanged 0.7 release.

## Provenance

The bridge vendors the necessary source/test dependency closure from
[icloud-md](https://github.com/coddingtonbear/icloud-md), commit
`ffa20ef6378a453f0935d26f03acedf3e58540f2`, under its MIT license. See
`CloudBridge/vendor/icloud-md/UPSTREAM.md` for local adaptations. The native
formatting reconciler preserves exact list/inline styles rather than Markdown's
lossy normalization. Original wire codecs and byte-preservation gates remain.

CloudKit atomic writes/change-tag behavior:
[Apple records/modify reference](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/ModifyRecords.html).
