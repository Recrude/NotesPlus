import {test} from 'node:test';
import assert from 'node:assert/strict';
import {applyTextEdit,applyFormattingOp,buildInitialNoteDocument,validateDocumentInvariants,encodeNoteDocument,parseNoteDocument,type NoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
const id=(n:number)=>new Uint8Array(16).fill(n);
// Resolve by UUID, as the native sorted timestamp table does. Array-index
// roundtrips alone missed the live full-body duplication regression.
function identities(d:NoteDocument){return d.runs.flatMap(r=>r.coord.replica && !r.tombstone?Array.from({length:r.length},(_,i)=>`${Buffer.from(d.replicas[r.coord.replica-1]!.id).toString('hex')}:${r.coord.clock+i}`):[])}
for(const join of [0x10,0xb0,0xf0])test(`native merge keeps character identities when replica ${join} joins`,()=>{
 const d=buildInitialNoteDocument('원본 이미지\ufffc와 서식',id(0xa0));
 applyTextEdit(d,d.text+' 다른 기기',{replicaId:id(0xc0)});
 applyFormattingOp(d,[{start:0,end:2}],id(0xc0));
 const before=identities(d),anchors=d.runs.map(r=>r.anchor.replica?`${Buffer.from(d.replicas[r.anchor.replica-1]!.id).toString('hex')}:${r.anchor.clock}`:'origin');
 applyTextEdit(d,d.text+' 추가',{replicaId:id(join)});
 validateDocumentInvariants(d);
 const reread=parseNoteDocument(encodeNoteDocument(d)),after=identities(reread);
 assert.deepEqual(after.slice(0,before.length),before);
 assert.equal(new Set([...before,...after]).size,after.length,'native identity union must not duplicate old text');
 assert.deepEqual(reread.replicas.map(r=>r.id[0]),[0xa0,0xc0,join].sort((a,b)=>a-b));
 d.runs.slice(0,anchors.length-1).forEach((r,i)=>assert.equal(r.anchor.replica?`${Buffer.from(d.replicas[r.anchor.replica-1]!.id).toString('hex')}:${r.anchor.clock}`:'origin',anchors[i]));
});
test('already malformed replica order refuses writing instead of repairing attribution',()=>{
 const d=buildInitialNoteDocument('test',id(0xc0));d.replicas.push({id:id(0x10),counters:[0,0]});
 assert.throws(()=>applyTextEdit(d,'test!',{replicaId:id(0x20)}),/동기화 이력/);
});
