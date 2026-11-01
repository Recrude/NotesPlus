import { randomUUID } from 'node:crypto';
import { checkAuthentication } from '../vendor/icloud-md/src/cloudkit/setupClient.js';
import { fetchAllZoneRecords, lookupRecords, createFolderRecord, createNoteRecord, updateRecords, type CloudKitRecord } from '../vendor/icloud-md/src/cloudkit/databaseClient.js';
import { buildNoteCreateFields, buildNoteUpdateFields } from '../vendor/icloud-md/src/notes/encodeNoteRecord.js';
import { decodeNoteEmbedSlots } from '../vendor/icloud-md/src/notes/noteAttachments.js';
import { decode, encodeCreate, encodeEdit, editTable, merge, layout, plain, type Document } from './document.js';

const zone = {zoneName: 'Notes'};
const folderTitle = 'NotesPlus 실험';
const b64 = (s: unknown) => typeof s === 'string' ? Buffer.from(s,'base64').toString('utf8') : '';
const parent = (r:CloudKitRecord) => (r.fields.Folder?.value as any)?.recordName;
const title = (r:CloudKitRecord) => b64(r.fields.TitleEncrypted?.value);
const active = (r:CloudKitRecord) => !r.deleted && r.fields.Deleted?.value !== 1;
function requireRecord(r: CloudKitRecord|undefined): CloudKitRecord {
  if (!r || !active(r) || r.recordType !== 'Note' || !r.recordChangeTag || typeof r.fields.TextDataEncrypted?.value !== 'string' || r.fields.TextDataAsset?.value != null) throw new Error('메모의 전체 원본을 읽을 수 없습니다.');
  return r;
}
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
  const read = async(id:string) => {
    for(let attempt=0;attempt<3;attempt++) {
      const record=requireRecord((await lookup([id]))[0]);
      const slots=decodeNoteEmbedSlots(Buffer.from(record.fields.TextDataEncrypted!.value as string,'base64'));
      const ids=(slots || []).flatMap(s=>s.kind==='attachment'?[s.ref.attachmentIdentifier]:[]);
      const attachments=ids.length ? await lookup(ids) : [];
      const checked=await lookup([id,...ids]);
      if([record,...attachments].some(r=>checked.find(c=>c.recordName===r.recordName)?.recordChangeTag!==r.recordChangeTag)) continue;
      return {record,attachments,document:decode(record.fields.TextDataEncrypted!.value as string,attachments)};
    }
    throw new Error('다른 기기의 저장이 진행 중입니다. 완성된 원본을 다시 확인합니다.');
  };
  const version = (record:CloudKitRecord,attachments:CloudKitRecord[]) => [record.recordChangeTag,...attachments.map(r=>`${r.recordName}:${r.recordChangeTag}`).sort()].join('|');
  const snapshot = (r:any) => ({id:r.record.recordName,title:title(r.record),tag:version(r.record,r.attachments),created:r.record.fields.CreationDate?.value || 0,document:r.document});
  if(q.command==='list') {
    const records=await fetchAllZoneRecords(session,host,dsid);
    const folder=records.find(r=>r.recordType==='Folder' && active(r) && title(r)===folderTitle);
    // Experimental build is contained to its own folder. No existing user note is rewritten.
    return {folderID:folder?.recordName,notes:records.filter(r=>r.recordType==='Note' && active(r) && folder && parent(r)===folder.recordName).map(r=>({id:r.recordName,title:title(r),created:r.fields.CreationDate?.value || 0})).sort((a:any,b:any)=>b.created-a.created)};
  }
  if(q.command==='read') return snapshot(await read(q.id));
  const replica=Buffer.from(q.replica.replaceAll('-',''),'hex');
  if(replica.length!==16) throw new Error('Invalid editor replica');
  if(q.command==='create') {
    const records=await fetchAllZoneRecords(session,host,dsid);
    let folder=records.find(r=>r.recordType==='Folder' && active(r) && title(r)===folderTitle)?.recordName;
    if(!folder) {
      folder=randomUUID();
      const result=await createFolderRecord(session,host,dsid,'private',zone,folder,{TitleEncrypted:{value:Buffer.from(folderTitle).toString('base64')}});
      if(!result.ok) throw new Error('테스트 폴더를 만들지 못했습니다.');
    }
    const id=randomUUID(), document:Document={paragraphs:[plain('새로운 메모','title'),plain('')],tables:[]};
    const result=await createNoteRecord(session,host,dsid,'private',zone,id,buildNoteCreateFields(encodeCreate(document,replica),layout(document).text,Date.now(),folder));
    if(!result.ok) throw new Error('메모를 만들지 못했습니다.');
    return snapshot(await read(id));
  }
  if(q.command==='save') {
    const current=await read(q.id);
    const folder=(await lookup([parent(current.record)]))[0];
    if(!folder || folder.recordType!=='Folder' || title(folder)!==folderTitle) throw new Error('실험 빌드에서는 NotesPlus 실험 폴더에만 저장할 수 있습니다.');
    const desired=merge(q.base,q.document,current.document);
    const body=encodeEdit(current.record.fields.TextDataEncrypted!.value as string,desired,replica);
    const updates:any[]=[{recordName:q.id,recordType:'Note',recordChangeTag:current.record.recordChangeTag,fields:buildNoteUpdateFields(current.record,body,layout(desired).text,Date.now()),parentRecordName:current.record.parentRecordName}];
    for(const table of desired.tables) {
      const record=current.attachments.find(r=>r.recordName===table.id);
      if(!record?.recordChangeTag) throw new Error('표의 최신 버전을 읽을 수 없습니다.');
      const data=editTable(record,table.grid,replica);
      // Even an untouched table participates in the atomic change-tag check.
      // A concurrent cell edit must fail the batch, never leave a mixed snapshot.
      updates.push({recordName:record.recordName,recordType:record.recordType,recordChangeTag:record.recordChangeTag,fields:{MergeableDataEncrypted:{value:data ?? record.fields.MergeableDataEncrypted!.value}}});
    }
    const results=await updateRecords(session,host,dsid,'private',zone,updates);
    if(results.length!==updates.length || results.some(r=>!r.ok)) {
      const error:any=new Error('저장 중 다른 기기에서 변경되었습니다. 초안을 유지하고 다시 확인합니다.'); error.code='CONFLICT'; throw error;
    }
    // Use the acknowledged record as the base. A lagging read must not overwrite this document.
    const applied=results.flatMap(r=>r.ok?[r.record]:[]);
    return {id:q.id,title:desired.paragraphs[0]?.text || '',tag:version(applied[0]!,applied.slice(1)),document:desired,created:current.record.fields.CreationDate?.value || 0};
  }
  throw new Error('Unknown command');
}
let input='';
for await(const chunk of process.stdin) input+=chunk;
try { const result=await main(JSON.parse(input)); process.stdout.write(JSON.stringify({ok:true,result})); }
catch(error:any) { process.stdout.write(JSON.stringify({ok:false,error:{code:error.code || 'BRIDGE',message:error.message || 'iCloud 연결 오류'}})); }
