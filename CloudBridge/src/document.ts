import {clone,toBinary} from '@bufbuild/protobuf';
import {AttributeRunSchema,AttachmentInfoSchema} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
import {enrich,restoreExtras,protectedIslands,preservedStyle,preservedParagraph,type RichParagraph} from './preservation.js';
import {attachAt} from './tableCreate.js';
import {type AttributeRun} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
import {resolveTable} from '../vendor/icloud-md/src/notes/decodeTableRecord.js';
import {parseCellDocument} from '../vendor/icloud-md/src/notes/tableCellEdit.js';
import { diff3Merge } from 'node-diff3';
import { applyTextEdit, buildInitialNoteDocument, computeSplices, encodeNoteDocument, noteDocumentRoundTrips, parseNoteDocument, validateDocumentInvariants } from '../vendor/icloud-md/src/notes/noteDocument.js';
import { compressNoteDocument, decompressNoteDocument } from '../vendor/icloud-md/src/notes/noteText.js';
import { decodeNoteFormat, type FormatParagraph } from '../vendor/icloud-md/src/notes/noteFormat.js';
import { reconcileNoteFormat } from './nativeFormat.js';
import { decodeNoteEmbedSlots } from '../vendor/icloud-md/src/notes/noteAttachments.js';
import { gridFromTableDocument, parseTableDocument, tableDocumentRoundTrips } from '../vendor/icloud-md/src/notes/decodeTableRecord.js';
import { prepareTableAttachmentUpdate } from '../vendor/icloud-md/src/notes/tablePushEdit.js';
import type { CloudKitRecord } from '../vendor/icloud-md/src/cloudkit/databaseClient.js';

export type Paragraph = RichParagraph & { tableID?: string; separator?: string };
export interface Document { paragraphs: Paragraph[]; tables: { id: string; grid: string[][]; protected?:boolean }[] }
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
function richTable(record:CloudKitRecord):boolean {
 const data=record.fields.MergeableDataEncrypted?.value;if(typeof data!=='string')return true;
 const tableDoc=parseTableDocument(Buffer.from(data,'base64'));
 for(const cell of resolveTable(tableDoc).cells.values()){const str=tableDoc.objects[cell.textRef]?.string;if(!str)continue;
  for(const r of parseCellDocument(str).attributeRuns){const p=r.paragraphStyle;if(preservedStyle(r) || preservedParagraph(r) || r.attachmentInfo || r.fontHints || r.underline || r.strikethrough || r.link || p && (p.style!==0 && p.style!==3 || p.todo || p.indent || p.blockQuoteLevel))return true;}
 }return false;
}
export function decode(body: string, attachments: CloudKitRecord[]): Document {
  const compressed = Buffer.from(body, 'base64');
  const raw = decompressNoteDocument(compressed);
  if (!noteDocumentRoundTrips(raw)) throw new Error('이 메모의 원본 구조를 완전히 보존할 수 없습니다.');
  const doc = parseNoteDocument(raw);
  validateDocumentInvariants(doc);
  const format = decodeNoteFormat(doc.text, doc.attributeRuns);
  if (format.status !== 'ok') throw new Error(format.reason);
  const slots = decodeNoteEmbedSlots(compressed);
  if (!slots) throw new Error('첨부 데이터 구조를 확인할 수 없습니다.');
  const tables: Document['tables'] = [];
  for (const slot of slots) {
    if (slot.kind !== 'attachment') throw new Error('식별되지 않은 첨부 구조는 아직 편집할 수 없습니다.');
    if(slot.ref.typeUti !== 'com.apple.notes.table')continue;
    const record = attachments.find(r => r.recordName === slot.ref.attachmentIdentifier);
    const data = record?.fields.MergeableDataEncrypted?.value;
    if (typeof data !== 'string' || !tableDocumentRoundTrips(Buffer.from(data, 'base64'))) throw new Error('표 원본을 완전히 읽지 못했습니다.');
    const tableDoc=parseTableDocument(Buffer.from(data,'base64'));
    tables.push({id: slot.ref.attachmentIdentifier, grid: gridFromTableDocument(tableDoc),...(richTable(record!)?{protected:true}:{})});
  }
  const separators = [...doc.text.matchAll(/\r\n?|\n/g)].map(m => m[0]);
  const paragraphs: Paragraph[] = enrich(format.paragraphs,doc.attributeRuns).map((p, i) => {
    const tableSpan=p.spans.find(s=>s.embed?.uti==='com.apple.notes.table'),tableID=tableSpan?.embed?.id;
    if(tableSpan && p.text!=='\ufffc')throw new Error('문단 안에 섞인 표 위치는 아직 편집할 수 없습니다.');
    if(tableSpan)for(const span of p.spans)delete span.embed;
    return {...p, separator: separators[i] || '', ...(tableSpan ? {tableID:tableID!} : {})};
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
  validateDocumentInvariants(doc);
  const originalRuns=doc.attributeRuns.map(r=>clone(AttributeRunSchema,r)),originalText=doc.text;
  const slots = decodeNoteEmbedSlots(Buffer.from(body, 'base64'));
  for (const s of computeSplices(doc.text, desired.text)) {
    if (doc.text.slice(s.start, s.start + s.deleteLength).includes('\uFFFC')) throw new Error('첨부·표 전체의 이동이나 삭제는 원본 보존을 위해 아직 지원하지 않습니다.');
  }
  const oldIDs=(slots || []).map(s=>s.kind==='attachment'?s.ref.attachmentIdentifier:'');
  const desiredIDs=desired.paragraphs.flatMap(p=>p.tableID?[p.tableID]:p.spans.flatMap(s=>s.embed?[s.embed.id]:[]));
  const tableIDs=desired.paragraphs.flatMap(p=>p.tableID?[p.tableID]:[]);
  for(const p of desired.paragraphs)for(const span of p.spans){if(span.embed && (span.length!==1 || !oldIDs.includes(span.embed.id)))throw new Error('첨부 식별자 또는 범위가 변경되었습니다.');}
  if(JSON.stringify(desiredIDs.filter(id=>oldIDs.includes(id)))!==JSON.stringify(oldIDs))throw new Error('기존 표의 순서와 식별자가 바뀌었습니다.');
  if(new Set(desiredIDs).size!==desiredIDs.length || input.tables.length!==tableIDs.length || !input.tables.every(t=>tableIDs.includes(t.id)))throw new Error('표 식별자가 중복되었거나 누락됐습니다.');
  const wantedSlots=desired.paragraphs.flatMap(p=>{if(p.tableID)return [{at:p.start,id:p.tableID,uti:'com.apple.notes.table'}];let at=p.start;return p.spans.flatMap(s=>{const slot=s.embed?[{at,id:s.embed.id,uti:s.embed.uti}]:[];if(s.embed && desired.text[at]!=='\ufffc')throw new Error('첨부 위치가 변경되었습니다.');at+=s.length;return slot})});
  applyTextEdit(doc, desired.text, {replicaId: replica});
  for(const p of desired.paragraphs){if(p.tableID && !oldIDs.includes(p.tableID)){if(p.text!=='\ufffc')throw new Error('표 문단이 잘못되었습니다.');attachAt(doc,p.start,p.tableID)}}
  let slotOffset=0;const actualSlots=doc.attributeRuns.flatMap(r=>{const slot=r.attachmentInfo?[{at:slotOffset,id:r.attachmentInfo.attachmentIdentifier,uti:r.attachmentInfo.typeUTI}]:[];slotOffset+=r.length;return slot});
  if(JSON.stringify(wantedSlots)!==JSON.stringify(actualSlots))throw new Error('첨부의 위치나 형식이 원본과 달라졌습니다.');
  const result = reconcileNoteFormat(doc, desired.paragraphs, replica);
  if (!result.ok) throw new Error(result.reason);
  restoreExtras(doc,desired.paragraphs,originalRuns,replica);
  const attachmentBytes=(runs:typeof originalRuns)=>runs.flatMap(r=>r.attachmentInfo?[Buffer.from(toBinary(AttachmentInfoSchema,r.attachmentInfo)).toString('base64')]:[]);
  const oldAttachments=attachmentBytes(originalRuns),remaining=doc.attributeRuns.filter(r=>r.attachmentInfo && oldIDs.includes(r.attachmentInfo.attachmentIdentifier));
  if(JSON.stringify(oldAttachments)!==JSON.stringify(attachmentBytes(remaining)))throw new Error('원본 첨부 참조가 달라져 저장을 중단합니다.');
  if(JSON.stringify(protectedIslands(originalText,originalRuns))!==JSON.stringify(protectedIslands(doc.text,doc.attributeRuns)))throw new Error('보호된 원본 영역을 변경할 수 없습니다.');
  verifyRetainedExtras(originalText,originalRuns,doc);
  validateDocumentInvariants(doc);
  const encoded = encodeNoteDocument(doc);
  if (!noteDocumentRoundTrips(encoded)) throw new Error('Edited document failed preservation check');
  const bytes = compressNoteDocument(encoded);
  if (JSON.stringify(decodeNoteEmbedSlots(bytes)?.map(s=>s.kind==='attachment'?s.ref.attachmentIdentifier:'')) !== JSON.stringify(desiredIDs)) throw new Error('Attachment identity changed');
  const check = decodeNoteFormat(doc.text, parseNoteDocument(encoded).attributeRuns);
  if (check.status !== 'ok' || JSON.stringify(canonicalParagraphs(enrich(check.paragraphs,doc.attributeRuns),true)) !== JSON.stringify(canonicalParagraphs(desired.paragraphs,true))) throw new Error('저장 검증 중 본문 서식이 달라졌습니다. 초안을 보관합니다.');
  return bytes.toString('base64');
}
function verifyRetainedExtras(oldText:string,oldRuns:AttributeRun[],doc:ReturnType<typeof parseNoteDocument>) {
 const styles=(runs:AttributeRun[])=>runs.flatMap(r=>Array(r.length).fill(JSON.stringify([preservedStyle(r)?.token ?? null,preservedParagraph(r)?.token ?? null])));
 const before=styles(oldRuns),after=styles(doc.attributeRuns);let oldAt=0,newAt=0;
 const keep=(end:number)=>{while(oldAt<end){if(before[oldAt]!==after[newAt])throw new Error('편집하지 않은 본문의 원본 서식이 달라져 저장을 중단했습니다. 초안은 보관됩니다.');oldAt++;newAt++}};
 for(const splice of computeSplices(oldText,doc.text)){keep(splice.start);oldAt+=splice.deleteLength;newAt+=splice.insertText.length}keep(oldText.length);
}
function canonicalStyle(s:Paragraph['spans'][number]['style']){return s?{token:s.token,fontName:s.fontName,fontSize:s.fontSize,color:s.color,superscript:s.superscript,emphasis:s.emphasis,protected:s.protected}:null}
function canonicalTables(d:Document){return d.tables.map(t=>({id:t.id,grid:t.grid,protected:t.protected===true}))}
function canonicalParagraphs(ps: Paragraph[],wireCheck=false) {
  return ps.map(p => {
    const spans: any[] = [];
    for (const s of p.spans) {
      const item={length:s.length,bold:s.bold,italic:s.italic,underline:s.underline,strikethrough:s.strikethrough,link:s.link,style:canonicalStyle(s.style),embed:!wireCheck && s.embed?{id:s.embed.id,uti:s.embed.uti,title:s.embed.title}:null},last=spans.at(-1);
      if(last && JSON.stringify({...last,length:0})===JSON.stringify({...item,length:0}))last.length+=s.length;else spans.push(item);
    }
    return {kind:p.kind, text:p.text, indent:p.indent, blockQuoteLevel:p.blockQuoteLevel, startNumber:p.startNumber === 1 ? 0 : p.startNumber || 0, done:p.kind === 'todoList' ? !!p.done : false, spans,...(p.paragraphStyle?{paragraphStyle:{token:p.paragraphStyle.token,alignment:p.paragraphStyle.alignment,direction:p.paragraphStyle.direction}}:{}),...(p.separatorStyle?{separatorStyle:canonicalStyle(p.separatorStyle)}:{})};
  });
}
export function equal(a: Document, b: Document): boolean {
  return JSON.stringify({p:canonicalParagraphs(a.paragraphs),t:canonicalTables(a)}) === JSON.stringify({p:canonicalParagraphs(b.paragraphs),t:canonicalTables(b)});
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
    return {...r,grid:r.grid.map((row,i)=>row.map((cell,j)=> {
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
  if(richTable(record)){const before=gridFromTableDocument(parseTableDocument(Buffer.from(record.fields.MergeableDataEncrypted!.value as string,'base64')));if(JSON.stringify(before)!==JSON.stringify(grid))throw new Error('복합 서식이 있는 표는 원본을 유지합니다. 표 밖의 본문은 편집할 수 있습니다.');return undefined;}
  const result = prepareTableAttachmentUpdate(record, grid, replica);
  if (!result.ok) throw new Error(result.reason);
  return result.changed ? result.mergeableDataBase64 : undefined;
}
