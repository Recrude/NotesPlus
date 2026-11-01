import { diff3Merge } from 'node-diff3';
import { applyTextEdit, buildInitialNoteDocument, computeSplices, encodeNoteDocument, noteDocumentRoundTrips, parseNoteDocument, validateDocumentInvariants } from '../vendor/icloud-md/src/notes/noteDocument.js';
import { compressNoteDocument, decompressNoteDocument } from '../vendor/icloud-md/src/notes/noteText.js';
import { decodeNoteFormat, type FormatParagraph } from '../vendor/icloud-md/src/notes/noteFormat.js';
import { reconcileNoteFormat } from './nativeFormat.js';
import { decodeNoteEmbedSlots } from '../vendor/icloud-md/src/notes/noteAttachments.js';
import { gridFromTableDocument, parseTableDocument, tableDocumentRoundTrips } from '../vendor/icloud-md/src/notes/decodeTableRecord.js';
import { prepareTableAttachmentUpdate } from '../vendor/icloud-md/src/notes/tablePushEdit.js';
import type { CloudKitRecord } from '../vendor/icloud-md/src/cloudkit/databaseClient.js';

export type Paragraph = FormatParagraph & { tableID?: string; separator?: string };
export interface Document { paragraphs: Paragraph[]; tables: { id: string; grid: string[][] }[] }
export class Conflict extends Error { code = 'CONFLICT'; }
export const plain = (text: string, kind = 'body'): Paragraph => ({kind: kind as any, text, start: 0, indent: 0, blockQuoteLevel: 0, startNumber: 0, spans: text.length ? [{length: text.length, bold: false, italic: false, underline: false, strikethrough: false, link: ''}] : []});
export function layout(input: Document): {text: string; paragraphs: Paragraph[]} {
  let text = '';
  // An empty list item needs a real separator carrying its paragraph style.
  // Apple has no attributes at the zero-length final insertion point.
  const source=[...input.paragraphs];
  if(source.at(-1)?.text==='' && source.at(-1)?.kind!=='body') source.push(plain(''));
  const paragraphs = source.map((p, i) => {
    if (p.spans.reduce((n, s) => n + s.length, 0) !== p.text.length) throw new Error('Invalid UTF-16 formatting spans');
    if (/[\r\n]/.test(p.text)) throw new Error('Paragraph contains a separator');
    const next = {...p, start: text.length};
    text += p.text + (i < source.length - 1 ? p.separator || '\n' : '');
    return next;
  });
  return {text, paragraphs};
}
export function decode(body: string, attachments: CloudKitRecord[]): Document {
  const compressed = Buffer.from(body, 'base64');
  const raw = decompressNoteDocument(compressed);
  if (!noteDocumentRoundTrips(raw)) throw new Error('이 메모의 원본 구조를 완전히 보존할 수 없습니다.');
  const doc = parseNoteDocument(raw), format = decodeNoteFormat(doc.text, doc.attributeRuns);
  if (format.status !== 'ok') throw new Error(format.reason);
  const slots = decodeNoteEmbedSlots(compressed);
  if (!slots) throw new Error('첨부 데이터 구조를 확인할 수 없습니다.');
  const tables: Document['tables'] = [];
  for (const slot of slots) {
    if (slot.kind !== 'attachment' || slot.ref.typeUti !== 'com.apple.notes.table') throw new Error('이 실험 빌드는 표 이외의 첨부 편집을 아직 지원하지 않습니다.');
    const record = attachments.find(r => r.recordName === slot.ref.attachmentIdentifier);
    const data = record?.fields.MergeableDataEncrypted?.value;
    if (typeof data !== 'string' || !tableDocumentRoundTrips(Buffer.from(data, 'base64'))) throw new Error('표 원본을 완전히 읽지 못했습니다.');
    tables.push({id: slot.ref.attachmentIdentifier, grid: gridFromTableDocument(parseTableDocument(Buffer.from(data, 'base64')))});
  }
  let table = 0;
  const separators = [...doc.text.matchAll(/\r\n?|\n/g)].map(m => m[0]);
  const paragraphs: Paragraph[] = format.paragraphs.map((p, i) => {
    if (p.text.includes('\uFFFC') && p.text !== '\uFFFC') throw new Error('문단 안의 표 위치를 보존할 수 없습니다.');
    return {...p, separator: separators[i] || '', ...(p.text === '\uFFFC' ? {tableID: tables[table++]!.id} : {})};
  });
  return {paragraphs, tables};
}
export function encodeCreate(input: Document, replica: Uint8Array): string {
  if (input.tables.length) throw new Error('Create the note before inserting a table');
  const desired = layout(input), doc = buildInitialNoteDocument(desired.text, replica);
  const result = reconcileNoteFormat(doc, desired.paragraphs, replica);
  if (!result.ok) throw new Error(result.reason);
  return compressNoteDocument(encodeNoteDocument(doc)).toString('base64');
}
export function encodeEdit(body: string, input: Document, replica: Uint8Array): string {
  const raw = decompressNoteDocument(Buffer.from(body, 'base64'));
  if (!noteDocumentRoundTrips(raw)) throw new Error('Original document failed preservation check');
  const doc = parseNoteDocument(raw), desired = layout(input);
  const slots = decodeNoteEmbedSlots(Buffer.from(body, 'base64'));
  for (const s of computeSplices(doc.text, desired.text)) {
    if (doc.text.slice(s.start, s.start + s.deleteLength).includes('\uFFFC') || s.insertText.includes('\uFFFC')) throw new Error('표 이동·삭제는 이 실험 빌드에서 아직 지원하지 않습니다.');
  }
  applyTextEdit(doc, desired.text, {replicaId: replica});
  const result = reconcileNoteFormat(doc, desired.paragraphs, replica);
  if (!result.ok) throw new Error(result.reason);
  validateDocumentInvariants(doc);
  const encoded = encodeNoteDocument(doc);
  if (!noteDocumentRoundTrips(encoded)) throw new Error('Edited document failed preservation check');
  const bytes = compressNoteDocument(encoded);
  if (JSON.stringify(decodeNoteEmbedSlots(bytes)) !== JSON.stringify(slots)) throw new Error('Attachment identity changed');
  const check = decodeNoteFormat(doc.text, parseNoteDocument(encoded).attributeRuns);
  if (check.status !== 'ok' || JSON.stringify(canonicalParagraphs(check.paragraphs)) !== JSON.stringify(canonicalParagraphs(desired.paragraphs))) throw new Error('저장 검증 중 본문 서식이 달라졌습니다. 초안을 보관합니다.');
  return bytes.toString('base64');
}
function canonicalParagraphs(ps: Paragraph[]) {
  return ps.map(p => {
    const spans: any[] = [];
    for (const s of p.spans) {
      const {length, ...style} = s, last = spans.at(-1);
      if (last && Object.keys(style).every(k => last[k] === (style as any)[k])) last.length += length;
      else spans.push({length:s.length,bold:s.bold,italic:s.italic,underline:s.underline,strikethrough:s.strikethrough,link:s.link});
    }
    return {kind:p.kind, text:p.text, indent:p.indent, blockQuoteLevel:p.blockQuoteLevel, startNumber:p.startNumber === 1 ? 0 : p.startNumber || 0, done:p.kind === 'todoList' ? !!p.done : false, spans};
  });
}
export function equal(a: Document, b: Document): boolean {
  return JSON.stringify({p:canonicalParagraphs(a.paragraphs),t:a.tables}) === JSON.stringify({p:canonicalParagraphs(b.paragraphs),t:b.tables});
}
export function merge(base: Document, local: Document, remote: Document): Document {
  if (equal(base, remote)) return local;
  if (equal(base, local) || equal(local, remote)) return remote;
  const lines = (d: Document) => d.paragraphs.map((p,i) => JSON.stringify({...canonicalParagraphs([p])[0],tableID:p.tableID || null,separator:p.separator || (i<d.paragraphs.length-1?'\n':'')}));
  const chunks = diff3Merge(lines(local), lines(base), lines(remote));
  const resolved=chunks.flatMap(c=>{
    if(c.ok)return c.ok;
    const conflict=c.conflict!;
    if(conflict.a.length!==conflict.o.length || conflict.b.length!==conflict.o.length) throw new Conflict('같은 문단이 양쪽에서 변경되었습니다. 입력은 계속할 수 있고 초안은 보관됩니다.');
    return conflict.o.map((old,i)=>{
      const mine=conflict.a[i]!,remote=conflict.b[i]!;
      if(mine===old || mine===remote)return remote;
      if(remote===old)return mine;
      throw new Conflict('같은 문단이 양쪽에서 변경되었습니다. 입력은 계속할 수 있고 초안은 보관됩니다.');
    });
  });
  const paragraphs = resolved.map(s => ({...JSON.parse(s),start:0}));
  const tables = remote.tables.map(r => {
    const b=base.tables.find(t=>t.id===r.id), l=local.tables.find(t=>t.id===r.id);
    if (!b || !l) throw new Conflict('표 구성이 양쪽에서 변경되었습니다.');
    const eq = (x:any,y:any) => JSON.stringify(x)===JSON.stringify(y);
    if (eq(b.grid,l.grid)) return r;
    if (eq(b.grid,r.grid) || eq(l.grid,r.grid)) return l;
    if (!eq(b.grid.map(row=>row.length),l.grid.map(row=>row.length)) || !eq(b.grid.map(row=>row.length),r.grid.map(row=>row.length))) throw new Conflict('표 크기가 양쪽에서 변경되었습니다.');
    return {id:r.id,grid:r.grid.map((row,i)=>row.map((cell,j)=> {
      const old=b.grid[i]![j], mine=l.grid[i]![j];
      if(cell===old || cell===mine) return mine!;
      if(mine===old) return cell;
      throw new Conflict('같은 표 셀이 양쪽에서 변경되었습니다.');
    }))};
  });
  if (base.tables.length !== local.tables.length || base.tables.length !== remote.tables.length) throw new Conflict('표 구성이 변경되었습니다.');
  return {paragraphs,tables};
}
export function editTable(record: CloudKitRecord, grid: string[][], replica: Uint8Array): string | undefined {
  const result = prepareTableAttachmentUpdate(record, grid, replica);
  if (!result.ok) throw new Error(result.reason);
  return result.changed ? result.mergeableDataBase64 : undefined;
}
