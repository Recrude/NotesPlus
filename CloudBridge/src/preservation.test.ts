import {test} from 'node:test';import assert from 'node:assert/strict';
import {create,clone,toBinary} from '@bufbuild/protobuf';
import {AttributeRunSchema,AttachmentInfoSchema,ColorSchema,FontSchema,ParagraphStyleSchema} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
import {parseNoteDocument,encodeNoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
import {compressNoteDocument,decompressNoteDocument} from '../vendor/icloud-md/src/notes/noteText.js';
import {decode,encodeCreate,encodeEdit,plain,merge,type Document} from './document.js';
import {preservedStyle,preservedParagraph} from './preservation.js';
const replica=new Uint8Array(16).fill(19),base=(...text:string[]):Document=>({paragraphs:text.map(t=>plain(t)),tables:[]});
const parse=(body:string)=>parseNoteDocument(decompressNoteDocument(Buffer.from(body,'base64'))),encode=(doc:ReturnType<typeof parse>)=>compressNoteDocument(encodeNoteDocument(doc)).toString('base64');
function fixture(){const original=parse(encodeCreate(base('제목','빨간 글씨 😀','일반 본문','사진 앞 \ufffc 사진 뒤','마지막'),replica));
 const runs=[];let at=0;for(const run of original.attributeRuns){for(let i=0;i<run.length;i++){const r=clone(AttributeRunSchema,run);r.length=1;const pos=at+i;
 if(pos>=3 && pos<13){r.color=create(ColorSchema,{red:0.8,green:0.2,blue:0.1,alpha:1});r.font=create(FontSchema,{name:'Helvetica',pointSize:19});r.emphasis=2;r.superscript=1;}
 if(original.text[pos]==='\ufffc')r.attachmentInfo=create(AttachmentInfoSchema,{attachmentIdentifier:'photo-uuid',typeUTI:'public.png',systemAttachmentClassName:'preserve-me'});
 runs.push(r)}at+=run.length}original.attributeRuns=runs;return encode(original)}
const attachmentBytes=(body:string)=>parse(body).attributeRuns.filter(r=>r.attachmentInfo).map(r=>Buffer.from(toBinary(AttachmentInfoSchema,r.attachmentInfo!)).toString('hex'));
const richBytes=(body:string)=>parse(body).attributeRuns.filter(r=>r.color).map(r=>preservedStyle(r)!.token);
test('inline image and rich text survive edits before and after them, no asset write needed',()=>{
 const body=fixture(),loaded=decode(body,[]);assert.ok(loaded.paragraphs[1]!.spans[0]!.style);assert.ok(loaded.paragraphs[3]!.spans.some(s=>s.embed?.id==='photo-uuid'));
 loaded.paragraphs[0]=plain('제목 수정');loaded.paragraphs[4]=plain('마지막 수정 😀');const written=encodeEdit(body,loaded,replica);
 assert.deepEqual(attachmentBytes(written),attachmentBytes(body));assert.deepEqual(richBytes(written),richBytes(body));assert.equal(decode(written,[]).paragraphs[4]!.text,'마지막 수정 😀');
});
test('typing inside colored custom-font text retains all original rich fields',()=>{
 const body=fixture(),loaded=decode(body,[]),p=loaded.paragraphs[1]!;p.text='가'+p.text;p.spans[0]!.length++;
 const written=encodeEdit(body,loaded,replica),read=decode(written,[]);assert.equal(read.paragraphs[1]!.text,p.text);assert.deepEqual(read.paragraphs[1]!.spans[0]!.style,p.spans[0]!.style);assert.deepEqual(attachmentBytes(written),attachmentBytes(body));
});
test('a client that drops existing extra style or changes attachment identity cannot prepare a write',()=>{
 const body=fixture(),loaded=decode(body,[]),loss=structuredClone(loaded);for(const s of loss.paragraphs[1]!.spans)delete s.style;
 assert.throws(()=>encodeEdit(body,loss,replica),/원본 서식/);
 const missing=structuredClone(loaded);for(const p of missing.paragraphs)for(const s of p.spans)if(s.embed)s.embed.id='different';assert.throws(()=>encodeEdit(body,missing,replica),/첨부 식별자/);
 const forged=structuredClone(loaded);forged.paragraphs[1]!.spans[0]!.style!.token='forged';assert.throws(()=>encodeEdit(body,forged,replica),/확인되지 않은/);
});
test('independent remote rich-format change and local plain edit merge without wiping color',()=>{
 const b=decode(fixture(),[]),local=structuredClone(b),remote=structuredClone(b);local.paragraphs[4]=plain('local continued');remote.paragraphs[0]!.spans[0]!.bold=true;
 const combined=merge(b,local,remote);assert.equal(combined.paragraphs[4]!.text,'local continued');assert.equal(combined.paragraphs[0]!.spans[0]!.bold,true);assert.equal(combined.paragraphs[1]!.spans.reduce((n,s)=>n+s.length,0),b.paragraphs[1]!.text.length);assert.equal(combined.paragraphs[1]!.spans[0]!.style!.token,b.paragraphs[1]!.spans[0]!.style!.token);
});
test('center alignment and direction survive edits in other paragraphs',()=>{
 const doc=parse(encodeCreate(base('가운데 문단','수정할 본문'),replica));const first=clone(AttributeRunSchema,doc.attributeRuns[0]!);first.length=7;const tail=clone(AttributeRunSchema,doc.attributeRuns[0]!);tail.length-=7;doc.attributeRuns=[first,tail];doc.attributeRuns[0]!.paragraphStyle=create(ParagraphStyleSchema,{style:3,alignment:1,writingDirection:1});
 const body=encode(doc),loaded=decode(body,[]);loaded.paragraphs[1]=plain('수정한 본문');const written=encodeEdit(body,loaded,replica);assert.deepEqual(preservedParagraph(parse(written).attributeRuns[0]!),preservedParagraph(doc.attributeRuns[0]!));
});
