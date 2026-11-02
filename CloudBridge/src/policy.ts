import type { CloudKitRecord } from '../vendor/icloud-md/src/cloudkit/databaseClient.js';
export const textField=(r:CloudKitRecord,key:string)=>typeof r.fields[key]?.value==='string'?Buffer.from(r.fields[key]!.value as string,'base64').toString('utf8'):'';
export const parentID=(r:CloudKitRecord)=>(r.fields.Folder?.value as any)?.recordName || (r.fields.ParentFolder?.value as any)?.recordName || r.parentRecordName;
export const active=(r:CloudKitRecord)=>!r.deleted && r.fields.Deleted?.value!==1 && r.recordName!=='TrashFolder-CloudKit' && parentID(r)!=='TrashFolder-CloudKit';
export function folderBlocked(record:CloudKitRecord,records:CloudKitRecord[]):boolean {
  const seen=new Set<string>();let current:CloudKitRecord|undefined=record;
  while(current) {
    if(seen.has(current.recordName) || !active(current) || current.shareRecordName)return true;
    seen.add(current.recordName);const id=parentID(current);current=id?records.find(r=>r.recordName===id):undefined;
  }
  return false;
}
export function catalog(records:CloudKitRecord[]) {
  const folders=records.filter(r=>r.recordType==='Folder' && active(r));
  const notes=records.filter(r=>['Note','PasswordProtectedNote'].includes(r.recordType) && active(r) && folders.some(f=>f.recordName===parentID(r)));
  return {
    folders:folders.map(r=>({id:r.recordName,name:textField(r,'TitleEncrypted') || '메모',parentID:parentID(r),shared:folderBlocked(r,records),count:notes.filter(n=>parentID(n)===r.recordName).length})),
    notes:notes.map(r=>({id:r.recordName,title:textField(r,'TitleEncrypted') || (r.recordType==='PasswordProtectedNote'?'잠긴 메모':''),created:r.fields.CreationDate?.value || 0,modified:r.fields.ModificationDate?.value || 0,folderID:parentID(r),preview:textField(r,'SnippetEncrypted'),readOnlyReason:r.recordType==='PasswordProtectedNote'?'잠긴 메모는 이 베타에서 편집할 수 없습니다.':undefined}))
  };
}
export function assertWritableRecord(r:CloudKitRecord) {
  if(r.recordType!=='Note' || !active(r) || r.shareRecordName || !r.recordChangeTag || typeof r.fields.TextDataEncrypted?.value!=='string' || r.fields.TextDataAsset?.value!=null)throw new Error('잠금·공유·대용량 또는 삭제된 메모는 이 베타에서 편집하지 않습니다.');
}
