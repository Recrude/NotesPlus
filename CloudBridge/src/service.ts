import {newTable,tableFields} from './tableCreate.js';
import {catalog, parentID, active, textField, assertWritableRecord} from './policy.js';
import {decompressNoteDocument} from '../vendor/icloud-md/src/notes/noteText.js';
import {parseNoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
import { randomUUID } from 'node:crypto';
import { checkAuthentication } from '../vendor/icloud-md/src/cloudkit/setupClient.js';
import { fetchAllZoneRecords, lookupRecords, createNoteRecord, updateRecords, type CloudKitRecord } from '../vendor/icloud-md/src/cloudkit/databaseClient.js';
import { buildNoteCreateFields, buildNoteUpdateFields } from '../vendor/icloud-md/src/notes/encodeNoteRecord.js';
import { decodeNoteEmbedSlots } from '../vendor/icloud-md/src/notes/noteAttachments.js';
import { decode, encodeCreate, encodeEdit, editTable, merge, layout, plain, type Document } from './document.js';

const zone = {zoneName: 'Notes'};
const parent=parentID;
const title=(r:CloudKitRecord)=>textField(r,'TitleEncrypted');

async function main(q:any) {
  if (q.command === 'authorize') {
    const result = await checkAuthentication(q.session);
    if (!result.ok || !result.ckdatabasewsUrl) throw new Error('iCloud 로그인을 완료해 주세요. 2단계 인증과 메모 접근 승인이 필요할 수 있습니다.');
    if (!/^https:\/\/p\d+-ckdatabasews\.icloud\.com(?::443)?$/.test(result.ckdatabasewsUrl)) throw new Error('Unexpected iCloud service host');
    return {session:result.session,dsid:result.dsid,host:result.ckdatabasewsUrl};
  }
  const {session,host,dsid} = q.account;
  if (!/^https:\/\/p\d+-ckdatabasews\.icloud\.com(?::443)?$/.test(host)) throw new Error('Invalid service host');
  const lookup = (ids:string[]) => lookupRecords(session,host,dsid,'private',zone,ids);
  const writableFolder=async(id:string)=>{
    if(typeof id!=='string' || !id)throw new Error('메모의 폴더를 확인할 수 없습니다.');
    const seen=new Set<string>();let next:string|undefined=id;
    while(next) {
      if(seen.has(next))throw new Error('폴더 구조를 확인할 수 없습니다.');seen.add(next);
      const folder=(await lookup([next]))[0];
      if(!folder || folder.recordType!=='Folder' || !active(folder) || folder.shareRecordName)throw new Error('공유·삭제된 폴더는 편집하지 않습니다.');
      next=parent(folder);
    }
  };
  const read = async(id:string,strict=false) => {
    for(let attempt=0;attempt<3;attempt++) {
      const record=(await lookup([id]))[0];
      if(!record || !active(record))throw new Error('메모가 삭제되었거나 iCloud에서 찾을 수 없습니다. 초안은 유지됩니다.');
      let attachments:CloudKitRecord[]=[],document:Document={paragraphs:[plain(title(record))],tables:[]},readOnlyReason:string|undefined;
      try {
        assertWritableRecord(record);await writableFolder(parent(record));
        const slots=decodeNoteEmbedSlots(Buffer.from(record.fields.TextDataEncrypted!.value as string,'base64'));
        const ids=[...new Set((slots || []).flatMap(s=>s.kind==='attachment'?[s.ref.attachmentIdentifier]:[]))];
        attachments=ids.length ? await lookup(ids) : [];
        const checked=await lookup([id,...ids]);
        if([record,...attachments].some(r=>checked.find(c=>c.recordName===r.recordName)?.recordChangeTag!==r.recordChangeTag))continue;
        document=decode(record.fields.TextDataEncrypted!.value as string,attachments);
      } catch(error:any) {
        if(strict)throw error;
        readOnlyReason=error.message;
        try {
          const text=parseNoteDocument(decompressNoteDocument(Buffer.from(record.fields.TextDataEncrypted!.value as string,'base64'))).text;
          document={paragraphs:text.split(/\r\n?|\n/).map(t=>plain(t.replaceAll('\ufffc','[첨부]'))),tables:[]};
        }catch{}
      }
      return {record,attachments,document,readOnlyReason};
    }
    throw new Error('다른 기기의 저장이 진행 중입니다. 완성된 원본을 다시 확인합니다.');
  };
  const version = (record:CloudKitRecord,attachments:CloudKitRecord[]) => [record.recordChangeTag,...attachments.map(r=>`${r.recordName}:${r.recordChangeTag}`).sort()].join('|');
  const snapshot = (r:any) => ({id:r.record.recordName,title:title(r.record),tag:version(r.record,r.attachments),created:r.record.fields.CreationDate?.value || 0,modified:r.record.fields.ModificationDate?.value || 0,folderID:parent(r.record),document:r.document,readOnlyReason:r.readOnlyReason,backup:JSON.stringify({record:r.record,attachments:r.attachments})});
  if(q.command==='list') {
    const records=await fetchAllZoneRecords(session,host,dsid);
    return catalog(records);
  }
  if(q.command==='read') return snapshot(await read(q.id));
  const replica=Buffer.from(q.replica.replaceAll('-',''),'hex');
  if(replica.length!==16) throw new Error('Invalid editor replica');
  if(q.command==='create') {
    const folder=q.folderID;
    if(typeof folder!=='string' || !folder)throw new Error('새 메모를 만들 폴더를 선택해 주세요.');
    await writableFolder(folder);
    const id=randomUUID(), document:Document={paragraphs:[plain('',['body','title','heading','subheading'].includes(q.style)?q.style:'body'),plain('')],tables:[]};
    const result=await createNoteRecord(session,host,dsid,'private',zone,id,buildNoteCreateFields(encodeCreate(document,replica),layout(document).text,Date.now(),folder));
    if(!result.ok) throw new Error('메모를 만들지 못했습니다.');
    return snapshot(await read(id));
  }
  if(q.command==='save') {
    const current=await read(q.id,true);
    if(!q.expectedTag || version(current.record,current.attachments)!==q.expectedTag) {const e:any=new Error('백업 이후 원본이 변경되었습니다. 초안을 유지하고 다시 확인합니다.');e.code='RETRY';throw e;}

    const desired=merge(q.base,q.document,current.document);
    const body=encodeEdit(current.record.fields.TextDataEncrypted!.value as string,desired,replica);
    const updates:any[]=[{recordName:q.id,recordType:'Note',recordChangeTag:current.record.recordChangeTag,fields:buildNoteUpdateFields(current.record,body,layout(desired).text,Date.now()),parentRecordName:current.record.parentRecordName}];
    for(const key of ['FirstAttachmentThumbnail','FirstAttachmentUTIEncrypted']) {if(current.record.fields[key]) updates[0].fields[key]={value:current.record.fields[key]!.value};}
    for(const table of desired.tables) {
      const record=current.attachments.find(r=>r.recordName===table.id);
      if(!record){
        if(!/^[0-9a-f-]{36}$/i.test(table.id))throw new Error('새 표 식별자가 올바르지 않습니다.');
        updates.push({operationType:'create',recordName:table.id,recordType:'Attachment',fields:tableFields(q.id,newTable(table.grid,replica))});continue;
      }
      if(!record.recordChangeTag)throw new Error('표의 최신 버전을 읽을 수 없습니다.');
      const data=editTable(record,table.grid,replica);
      // Even an untouched table participates in the atomic change-tag check.
      // A concurrent cell edit must fail the batch, never leave a mixed snapshot.
      updates.push({recordName:record.recordName,recordType:record.recordType,recordChangeTag:record.recordChangeTag,fields:{MergeableDataEncrypted:{value:data ?? record.fields.MergeableDataEncrypted!.value}}});
    }
    const results=await updateRecords(session,host,dsid,'private',zone,updates);
    if(results.length!==updates.length || results.some(r=>!r.ok)) {
      const error:any=new Error('저장 중 다른 기기에서 변경되었습니다. 초안을 유지하고 다시 확인합니다.'); error.code='RETRY'; throw error;
    }
    // Use the acknowledged record as the base. A lagging read must not overwrite this document.
    const applied=results.flatMap(r=>r.ok?[r.record]:[]);
    return {id:q.id,title:desired.paragraphs[0]?.text || '',tag:version(applied[0]!,applied.slice(1)),document:desired,created:current.record.fields.CreationDate?.value || 0,modified:Date.now(),folderID:parent(current.record)};
  }
  throw new Error('Unknown command');
}
let input='';
for await(const chunk of process.stdin) input+=chunk;
try { const result=await main(JSON.parse(input)); process.stdout.write(JSON.stringify({ok:true,result})); }
catch(error:any) { process.stdout.write(JSON.stringify({ok:false,error:{code:error.code || 'BRIDGE',message:error.message || 'iCloud 연결 오류'}})); }
