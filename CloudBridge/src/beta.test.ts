import {create} from '@bufbuild/protobuf';
import {ColorSchema} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
import {parseNoteDocument,encodeNoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
import {compressNoteDocument,decompressNoteDocument} from '../vendor/icloud-md/src/notes/noteText.js';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {newTable,tableFields} from './tableCreate.js';
import {decode,encodeCreate,encodeEdit,plain,editTable,merge,type Document} from './document.js';
import {catalog,assertWritableRecord} from './policy.js';
import type {CloudKitRecord} from '../vendor/icloud-md/src/cloudkit/databaseClient.js';
const replica=new Uint8Array(16).fill(0xa7);
const record=(id:string,type:string,values:Record<string,unknown>={}):CloudKitRecord=>({recordName:id,recordType:type,recordChangeTag:'tag',fields:Object.fromEntries(Object.entries(values).map(([k,value])=>[k,{value,type:'STRING'}]))});
test('new table gets distinct clocks and round trips all cells',()=>{
 const grid=[['한글 😀',''],['','본문']];const one=newTable(grid,replica),two=newTable(grid,replica);assert.notEqual(one,two);
});
test('insert table preserves mixed existing body, checks, inline styles and reloads',()=>{
 const original:Document={paragraphs:[plain('제목','title'),{...plain('체크','todoList'),done:true},plain('서식'),plain('아래 본문')],tables:[]};original.paragraphs[2]!.spans[0]!.bold=true;
 const body=encodeCreate(original,replica),edited=decode(body,[]),id=randomUUID();edited.paragraphs.splice(3,0,{...plain('\ufffc'),tableID:id});edited.tables.push({id,grid:[['항목','내용'],['한글','😀']]});
 const table=record(id,'Attachment',Object.fromEntries(Object.entries(tableFields('note',newTable(edited.tables[0]!.grid,replica))).map(([k,v])=>[k,v.value])));
 const encoded=encodeEdit(body,edited,replica),read=decode(encoded,[table]);
 assert.equal(read.paragraphs[1]!.done,true);assert.equal(read.paragraphs[2]!.spans[0]!.bold,true);assert.equal(read.paragraphs.at(-1)!.text,'아래 본문');assert.deepEqual(read.tables,edited.tables);
 const row=[...read.tables[0]!.grid,['새 행','내용']];const updated=editTable(table,row,replica)!;table.fields.MergeableDataEncrypted!.value=updated;
 assert.deepEqual(decode(encoded,[table]).tables[0]!.grid,row);
});
test('catalog includes existing nested notes but excludes trash and protects shared parents',()=>{
 const folder=record('folder','Folder',{TitleEncrypted:Buffer.from('기존 폴더').toString('base64')});
 const shared={...record('shared','Folder'),shareRecordName:'share'};
 const child=record('child','Folder',{ParentFolder:{recordName:'shared'}});
 const notes=[record('a','Note',{Folder:{recordName:'folder'},CreationDate:1}),record('locked','PasswordProtectedNote',{Folder:{recordName:'folder'}}),record('trash','Note',{Folder:{recordName:'TrashFolder-CloudKit'}}),record('deleted','Note',{Folder:{recordName:'folder'},Deleted:1})];
 const out=catalog([folder,shared,child,...notes]);assert.deepEqual(out.notes.map(n=>n.id),['a','locked']);assert.equal(out.folders.find(f=>f.id==='child')!.shared,true);assert.ok(out.notes[1]!.readOnlyReason);
 assert.throws(()=>assertWritableRecord(notes[1]!));assert.throws(()=>assertWritableRecord(record('asset','Note',{TextDataAsset:{asset:'large'},TextDataEncrypted:'body'})));
});

test('unrepresented color is protected before any upload can be prepared',()=>{
 const original=encodeCreate({paragraphs:[plain('색상 있는 기존 메모')],tables:[]},replica);
 const doc=parseNoteDocument(decompressNoteDocument(Buffer.from(original,'base64')));doc.attributeRuns[0]!.color=create(ColorSchema,{red:1,green:0,blue:0,alpha:1});
 const colored=compressNoteDocument(encodeNoteDocument(doc)).toString('base64');assert.throws(()=>decode(colored,[]),/읽기 전용/);assert.throws(()=>encodeEdit(colored,{paragraphs:[plain('replacement')],tables:[]},replica),/읽기 전용/);
});
