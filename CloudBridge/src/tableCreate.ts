// Empty Apple table structure from icloud-md's MIT-licensed realFixtures.ts.
// Fresh per-document UUIDs preserve the original ordering of all clock tables.
import {randomBytes} from 'node:crypto';
import {create, clone} from '@bufbuild/protobuf';
import {TABLE_EVOLUTION_REVISIONS} from '../vendor/icloud-md/src/notes/realFixtures.js';
import {parseTableDocument,encodeTableDocument,tableDocumentRoundTrips,gridFromTableDocument} from '../vendor/icloud-md/src/notes/decodeTableRecord.js';
import {validateTableDocumentInvariants,applyTableEdit} from '../vendor/icloud-md/src/notes/tableEdit.js';
import {AttributeRunSchema,AttachmentInfoSchema} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
import type {NoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
export function newTable(grid:string[][],replica:Uint8Array):string {
  const original=parseTableDocument(Buffer.from(TABLE_EVOLUTION_REVISIONS[0]!.base64,'base64'));
  const ids=new Set<string>();
  const visit=(v:any,change?:(v:Uint8Array)=>Uint8Array):any=>{
    if(v instanceof Uint8Array){if(v.length===16){ids.add(Buffer.from(v).toString('hex'));return change?change(v):v}return v}
    if(Array.isArray(v)){for(let i=0;i<v.length;i++)v[i]=visit(v[i],change)}else if(v && typeof v==='object'){for(const k of Object.keys(v))v[k]=visit(v[k],change)}
    return v;
  };
  visit(original.document);const prefix=randomBytes(8),map=new Map<string,Uint8Array>();
  [...ids].sort().forEach((id,i)=>{const b=Buffer.alloc(16);prefix.copy(b);b.writeBigUInt64BE(BigInt(i+1),8);map.set(id,b)});
  visit(original.document,v=>map.get(Buffer.from(v).toString('hex'))!);
  // Reparse to rebuild all references into the remapped message arrays.
  const doc=parseTableDocument(encodeTableDocument(original));
  applyTableEdit(doc,grid,replica);validateTableDocumentInvariants(doc);
  const bytes=encodeTableDocument(doc);
  if(!tableDocumentRoundTrips(bytes) || JSON.stringify(gridFromTableDocument(parseTableDocument(bytes)))!==JSON.stringify(grid))throw new Error('새 표 구조 검증에 실패했습니다.');
  return bytes.toString('base64');
}
export function attachAt(doc:NoteDocument,offset:number,id:string) {
  let at=0,attached=false;const runs=[];
  for(const run of doc.attributeRuns){const end=at+run.length;
    if(at<=offset && offset<end){
      if(offset>at){const head=clone(AttributeRunSchema,run);head.length=offset-at;runs.push(head)}
      const one=clone(AttributeRunSchema,run);one.length=1;one.attachmentInfo=create(AttachmentInfoSchema,{attachmentIdentifier:id,typeUTI:'com.apple.notes.table'});runs.push(one);
      if(offset+1<end){const tail=clone(AttributeRunSchema,run);tail.length=end-offset-1;tail.attachmentInfo=undefined;runs.push(tail)}
      attached=true;
    }else runs.push(run);at=end;
  }
  if(!attached)throw new Error('표 위치를 원본 구조에 연결하지 못했습니다.');doc.attributeRuns=runs;
}
export function tableFields(noteID:string,data:string) {
  return {CreationDate:{value:Date.now()},Note:{value:{action:'VALIDATE',recordName:noteID,zoneID:{zoneName:'Notes'}}},UTIEncrypted:{value:Buffer.from('com.apple.notes.table').toString('base64')},UTI:{value:'com.apple.notes.table'},MinimumSupportedNotesVersion:{value:2},TitleEncrypted:{value:Buffer.from('Table').toString('base64')},MergeableDataEncrypted:{value:data},MergeableDataAsset:{value:null},EncryptedValues:{value:null},EncryptedValuesAsset:{value:null}};
}
