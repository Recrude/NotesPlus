import {test} from 'node:test';
import assert from 'node:assert/strict';
import {create} from '@bufbuild/protobuf';
import {decode,encodeCreate,encodeEdit,editTable,merge,plain,equal,type Document} from './document.js';
import {parseNoteDocument,encodeNoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
import {compressNoteDocument,decompressNoteDocument} from '../vendor/icloud-md/src/notes/noteText.js';
import {AttributeRunSchema,AttachmentInfoSchema} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
import {TABLE_FIRST_REVISION} from '../vendor/icloud-md/src/notes/realFixtures.js';
import type {CloudKitRecord} from '../vendor/icloud-md/src/cloudkit/databaseClient.js';
const replica=new Uint8Array(16).fill(71);
const doc=(...text:string[]):Document=>({paragraphs:text.map(t=>plain(t)),tables:[]});
test('native checklist creation, toggle, text edit survives Apple protobuf',()=>{
 const original=doc('체크리스트 검증','한글 😀 항목','별표 * 그대로');original.paragraphs[0]!.kind='title';original.paragraphs[1]!.kind='todoList';original.paragraphs[1]!.done=false;
 const body=encodeCreate(original,replica),loaded=decode(body,[]);
 assert.equal(loaded.paragraphs[1]!.done,false);
 loaded.paragraphs[1]!.done=true;
 const toggled=encodeEdit(body,loaded,replica);
 assert.equal(decode(toggled,[]).paragraphs[1]!.done,true);
 const after=decode(toggled,[]);after.paragraphs[2]=plain('iPhone 수정 후에도 계속 편집');
 assert.equal(decode(encodeEdit(toggled,after,replica),[]).paragraphs[1]!.done,true);
});
test('inline styles, list kinds, literal stars, Korean and emoji round trip without Markdown',()=>{
 const d=doc('제목','굵은 한글 😀','순서','* literal','— 내용');d.paragraphs[1]!.spans[0]!.bold=true;d.paragraphs[1]!.spans[0]!.underline=true;d.paragraphs[2]!.kind='numberedList';d.paragraphs[2]!.startNumber=4;d.paragraphs[4]!.kind='dashList';
 const encoded=encodeCreate(d,replica),loaded=decode(encoded,[]);assert.ok(equal(d,loaded));assert.equal(encodeEdit(encoded,loaded,replica),encoded);
});
test('independent remote paragraph and checklist edits merge',()=>{
 const b=decode(encodeCreate(doc('제목','first','second'),replica),[]),l=structuredClone(b),r=structuredClone(b);
 l.paragraphs[1]=plain('first local');r.paragraphs[2]=plain('second iPhone');
 const combined=merge(b,l,r);assert.equal(combined.paragraphs[1]!.text,'first local');assert.equal(combined.paragraphs[2]!.text,'second iPhone');
});
test('same paragraph conflict never selects a partial winner',()=>{
 const b=doc('base'),l=doc('local full draft'),r=doc('remote');assert.throws(()=>merge(b,l,r),/같은 문단/);assert.equal(l.paragraphs[0]!.text,'local full draft');
});
test('an empty final checklist item persists its paragraph style on a real separator',()=>{
 const d=doc('제목','');d.paragraphs[1]!.kind='todoList';d.paragraphs[1]!.done=false;
 const body=encodeCreate(d,replica),read=decode(body,[]);
 assert.equal(read.paragraphs[1]!.kind,'todoList');assert.equal(read.paragraphs[1]!.done,false);
 assert.doesNotThrow(()=>encodeEdit(body,d,replica));
});
test('native auto-numbering starts at one without writing an explicit zero or failing verification',()=>{
 const original=doc('제목','본문'),body=encodeCreate(original,replica),changed=decode(body,[]);
 changed.paragraphs.push({...plain('첫 번째','numberedList'),startNumber:1},plain('두 번째','numberedList'));
 const written=encodeEdit(body,changed,replica),loaded=decode(written,[]);
 assert.ok(equal(changed,loaded));assert.equal(loaded.paragraphs[2]!.kind,'numberedList');assert.equal(loaded.paragraphs[2]!.startNumber,0);
});
test('mixed bullet, checklist, real table, body retain structure and table identity',()=>{
 const input=doc('Mixed','Bullet','Check','\uFFFC','After table');input.paragraphs[1]!.kind='bulletList';input.paragraphs[2]!.kind='todoList';input.paragraphs[2]!.done=false;
 const initial=parseNoteDocument(decompressNoteDocument(Buffer.from(encodeCreate(input,replica),'base64')));
 let at=0;const runs=[];
 for(const run of initial.attributeRuns) {
   const pos=initial.text.indexOf('\uFFFC');
   if(at<=pos && at+run.length>pos) {
    if(pos>at) runs.push(create(AttributeRunSchema,{...run,length:pos-at}));
    runs.push(create(AttributeRunSchema,{...run,length:1,attachmentInfo:create(AttachmentInfoSchema,{attachmentIdentifier:'table-1',typeUTI:'com.apple.notes.table'})}));
    if(at+run.length>pos+1) runs.push(create(AttributeRunSchema,{...run,length:at+run.length-pos-1}));
   }else runs.push(run);at+=run.length;
 }
 initial.attributeRuns=runs;
 const body=compressNoteDocument(encodeNoteDocument(initial)).toString('base64');
 const table:CloudKitRecord={recordName:'table-1',recordType:'Attachment',recordChangeTag:'1',fields:{MergeableDataEncrypted:{value:TABLE_FIRST_REVISION,type:'ENCRYPTED_BYTES'}}};
 const loaded=decode(body,[table]);loaded.paragraphs[2]!.done=true;loaded.paragraphs[4]=plain('After table edited');loaded.tables[0]!.grid[0]![1]='한글 셀 변경 😀';
 const newBody=encodeEdit(body,loaded,replica),newTable=editTable(table,loaded.tables[0]!.grid,replica)!;
 table.fields.MergeableDataEncrypted!.value=newTable;
 const reloaded=decode(newBody,[table]);assert.equal(reloaded.paragraphs[1]!.kind,'bulletList');assert.equal(reloaded.paragraphs[2]!.done,true);assert.equal(reloaded.paragraphs[3]!.tableID,'table-1');assert.equal(reloaded.paragraphs[4]!.text,'After table edited');assert.equal(reloaded.tables[0]!.grid[0]![1],'한글 셀 변경 😀');
 const local=structuredClone(reloaded),remote=structuredClone(reloaded);local.tables[0]!.grid[0]![0]='local';remote.tables[0]!.grid[1]![1]='phone';
 const merged=merge(reloaded,local,remote);assert.equal(merged.tables[0]!.grid[0]![0],'local');assert.equal(merged.tables[0]!.grid[1]![1],'phone');
});
