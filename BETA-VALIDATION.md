# 0.8 beta validation — 2026-11-02

## 0.8.0-beta.2 / 802 — rich-note preservation

83 TypeScript tests, strict type checks, native editor/sync/beta/rich tests and
a TypeScript → AppKit → protobuf roundtrip passed. The 24,000-unit / 200-insert
input microbenchmark measured p95 0.13–0.24 ms, max 0.31–0.33 ms with one coalesced capture.
This measures an unattached text view, not system-wide frame time.

Synthetic checks cover custom font/color/emphasis, paragraph alignment, exact
attachment protobuf bytes, attachment deletion/replacement refusal, opaque
field protection, rich-table/body separation and cookie-free bounded previews.

Live tests used two newly created notes only, in `NotesPlus 실험`:
`NotesPlus 이미지 서식 검증 1102` and `NotesPlus 원본 보존 재검증 1102`.
The first uncovered a writer defect inherited from the pinned body codec:
registering a lower UUID by appending made native Notes resolve old character
coordinates to the wrong author and duplicate the body. The table codec already
implemented the required sorted registration rule. The body writer now inserts
at sorted rank and remaps all character/style coordinates; tests cover lower,
middle and higher UUID joins. Malformed source ordering is refused. The initial
test note is retained for diagnosis; no personal note was edited or repaired.

The second note was created in native Notes with an image, purple emphasis,
bold text, a link, bullets, a checklist and a 2×2 table. NotesPlus inserted text
after the image. Native Notes preserved the full body, image, highlight, list
and table, with no duplication. A native table-cell edit returned to NotesPlus.
iPhone displayed the same mixed content; changing its checkbox returned to
NotesPlus, and a subsequent NotesPlus body edit appeared on iPhone with the
image and formatting intact. The source attachment and unchanged table records
are not uploaded by a body-only save. Existing malformed/duplicated notes are
not automatically rewritten or deduplicated.

Image previews decode off the main thread and a bounded memory cache retains
previews across text/check-state refreshes. Preview failure falls back to an
attachment placeholder; it never changes the underlying attachment.

The beta.2 DMG passed mount/read-only integrity checks. Its version 802, strict
recursive code signature, executable and bridge bytes matched the built app.
The ZIP allowlist and artifact SHA256 manifest passed. The signed beta feed
contains 802 and 801; the stable feed was not changed. The app About panel
displayed 0.8.0-beta.2 (802).

The following sections record beta.1 and remain historical validation.


The main NotesPlus target now uses the structured AppKit editor and CloudKit
bridge. Bundle identity and preferences remain `dev.notesplus.prototype`.
The 0.7 HTML/Apple Events writer is not compiled into this app.

## Automated checks

`Tools/test-structured.sh` runs strict TypeScript checking, wire/format/CRDT
round trips, native editor checks, and asynchronous sync-model tests.

Covered regressions include:

- Local typing during a save; earlier acknowledged versions after restart.
- Save completion after selecting another note; out-of-order selection replies.
- Marked Hangul text excluded until commitment; pending input blocks a remote
  editor replacement before the deferred document capture has occurred.
- Repeated version-tag races retry without a false manual conflict.
- Whole structured drafts survive conflicts/restart; display-only font weight
  and spacing do not become document formatting.
- Native list conversion/continuation, literal star input, empty-list exit before
  ordinary text/timestamp, actual table insertion and row/column resizing.
- Fresh table UUIDs/clocks, table insert with mixed paragraphs, wire identity
  checks and unsupported-style protection before a write.

A local, unattached AppKit text-view microbenchmark used 24,000 UTF-16 units and
200 consecutive inserts. It captured the document once after the burst; the
observed p95 insert time was 0.11–0.14 ms across final runs. This is not a system-wide frame-time
or end-to-end network latency measurement.

## Live device checks

Only the new `NotesPlus 0.8 베타 검증 1102` note in `NotesPlus 실험` was edited for
this integration test. Existing personal notes were not rewritten. The earlier
experimental note was also read; the stricter unsupported-style guard now
protects it as a read-only text preview rather than rewriting its rich data.

On this Mac and the paired iPhone:

- Created a note in the integrated app, made a real checklist and bullet list.
- Created a native 2×2 Apple Notes table from NotesPlus, filled all four cells,
  then added a row. Mac Notes and iPhone Notes displayed the actual table and
  the full body following it.
- A NotesPlus check appeared as an actual checked item on iPhone; unchecked it
  on iPhone and received the change in NotesPlus.
- Created numbered paragraphs via `1.` + space and Return; iPhone displayed 1
  and 2. Used the timestamp command in the integrated app.

The live pass exposed three additional defects: a tag-only race was shown as a
manual conflict; exiting an empty list left list typing attributes on later
text; and metadata-only echoes unnecessarily reinstalled the editor, moving
the cursor when list marker lengths differed. All received source fixes and
regression tests. Semantic comparisons now ignore wire offsets/defaults, remote
refresh waits for idle input, and a genuine remote replacement remaps selection.

The final editor build was checked again on both devices: two numbered items
were followed by ordinary body text, a timestamp and a literal star. After
saving and receiving an iPhone checklist change, continued typing stayed at
the end of the same sentence. The table and following body remained present.
Settings displayed the retained user preferences and version 0.8.0-beta.1 (801).

Mac Notes initially showed a cached version until its next synchronization;
reopening it displayed the current full note. Device propagation latency is not
controlled or guaranteed by NotesPlus.

## Safety and release boundary

The bridge requires a pre-upload wire backup and rechecks the composite note +
attachment tags before its explicit atomic conditional write. Unsupported data
is read-only; no HTML fallback writes exist. A backup is per note/version and
contains the original record and attachment structures, with owner-only local
file permissions. New attachments use create operations in the same atomic
batch as their note body.

This beta does not establish complete Apple Notes parity. Unsupported categories
and table-edit limits are documented in `Release/READ-ME.txt`. The stable 0.7
appcast is unchanged; 0.8 uses a separate signed beta appcast. Build numbers for
later releases must be greater than 801 to upgrade this beta.

## Packaged artifacts

The final DMG and ZIP passed image/archive integrity checks, strict recursive
code-signature verification and an application-bundle file allowlist. The
archive signature and beta appcast signature were verified with the existing
update key. This is an ad-hoc signed, non-notarized Apple Silicon build.
