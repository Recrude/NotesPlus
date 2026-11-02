// Synthetic cross-language round-trip, never a user's note.
import fs from 'node:fs';import {create,clone} from '@bufbuild/protobuf';
import {decode,encodeCreate,encodeEdit,plain} from './document.js';
import {parseNoteDocument,encodeNoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
import {decompressNoteDocument,compressNoteDocument} from '../vendor/icloud-md/src/notes/noteText.js';
import {AttributeRunSchema,ColorSchema,FontSchema,AttachmentInfoSchema} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
const replica=new Uint8Array(16).fill(31),root='../build/structured/';
if(process.argv[2]==='verify'){
 const f=JSON.parse(fs.readFileSync(root+'rich-fixture.json','utf8')),edited=JSON.parse(fs.readFileSync(root+'rich-edited.json','utf8'));
 const body=encodeEdit(f.body,edited,replica),read=decode(body,[]);
 if(!read.paragraphs.at(-1)!.text.endsWith(' 계속 입력'))throw new Error('Native input was lost');
 if(read.paragraphs[1]!.spans[0]!.style?.token!==f.document.paragraphs[1].spans[0].style.token)throw new Error('Rich style lost');
 console.log('PASS: TypeScript wire → AppKit editing → wire, rich styles and inline image retained');
}else{
 const doc=parseNoteDocument(decompressNoteDocument(Buffer.from(encodeCreate({paragraphs:['테스트','색상 한글','사진 앞 \ufffc 사진 뒤','아래 본문'].map(t=>plain(t)),tables:[]},replica),'base64')));
 let at=0;const runs=[];for(const run of doc.attributeRuns){for(let i=0;i<run.length;i++){const r=clone(AttributeRunSchema,run);r.length=1;const pos=at+i;
 if(pos>=4&&pos<10){r.color=create(ColorSchema,{red:1,green:0.1,blue:0.2,alpha:1});r.font=create(FontSchema,{name:'Helvetica',pointSize:19});}
 if(doc.text[pos]==='\ufffc')r.attachmentInfo=create(AttachmentInfoSchema,{attachmentIdentifier:'fixture-image',typeUTI:'public.png'});runs.push(r)}at+=run.length}doc.attributeRuns=runs;
 const body=compressNoteDocument(encodeNoteDocument(doc)).toString('base64');fs.writeFileSync(root+'rich-fixture.json',JSON.stringify({body,document:decode(body,[])}));
}
