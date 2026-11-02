// Rich fields travel with their text independently from NotesPlus display preferences.
// Tokens are immutable copies of original protobuf fields, not instructions to
// invent unknown wire data. A save accepts only tokens present in its source.
import {clone,create,clearField,fromBinary,toBinary} from '@bufbuild/protobuf';
import {AttributeRunSchema,ParagraphStyleSchema,type AttributeRun} from '../vendor/icloud-md/src/notes/gen/topotext_pb.js';
import {inlineStyleOfRun,type FormatParagraph,type InlineSpan} from '../vendor/icloud-md/src/notes/noteFormat.js';
import {applyFormattingOp,type NoteDocument} from '../vendor/icloud-md/src/notes/noteDocument.js';
export interface PreservedStyle {token:string;fontName?:string;fontSize?:number;color?:number[];superscript?:number;emphasis?:number;protected?:boolean}
export interface PreservedParagraph {token:string;alignment:number;direction:number}
export interface Embed {id:string;uti:string;title:string}
export type RichSpan=InlineSpan & {style?:PreservedStyle;embed?:Embed};
export type RichParagraph=Omit<FormatParagraph,'spans'> & {spans:RichSpan[];paragraphStyle?:PreservedParagraph;separatorStyle?:PreservedStyle};
const clear=(v:any,schema:any,names:string[])=>{for(const f of schema.fields)if(names.includes(f.localName))clearField(v,f)};
function customFont(r:AttributeRun){const standard=r.fontHints===3?'SFUIText-BoldItalic':r.fontHints===1?'SFUIText-Bold':r.fontHints===2?'SFUIText-LightItalic':undefined;return r.font && (r.font.name!==standard || r.font.pointSize!==0 || r.font.fontHints!==0 || r.font.$unknown?.length)}
function extraRun(r:AttributeRun):AttributeRun {
 const v=clone(AttributeRunSchema,r);v.length=0;
 clear(v,AttributeRunSchema,['paragraphStyle','attachmentInfo','fontHints','link','timestamp']);
 if(!customFont(r))clear(v,AttributeRunSchema,['font']);
 if(r.fontHints & ~3)v.fontHints=r.fontHints & ~3;
 if(r.underline<=1)clear(v,AttributeRunSchema,['underline']);
 if(r.strikethrough<=1)clear(v,AttributeRunSchema,['strikethrough']);
 // Explicit default scalars do not represent extra styling.
 for(const name of ['superscript','writingDirection','emphasis'])if(!(v as any)[name])clear(v,AttributeRunSchema,[name]);
 return v;
}
const emptyToken=Buffer.from(toBinary(AttributeRunSchema,create(AttributeRunSchema,{length:0}))).toString('base64');
export function preservedStyle(r:AttributeRun):PreservedStyle|undefined {
 const extra=extraRun(r),token=Buffer.from(toBinary(AttributeRunSchema,extra)).toString('base64');if(token===emptyToken)return;
 return {token,...(extra.font?{fontName:extra.font.name,fontSize:extra.font.pointSize}:{}),...(extra.color?{color:[extra.color.red,extra.color.green,extra.color.blue,extra.color.alpha]}:{}),...(extra.superscript?{superscript:extra.superscript}:{}),...(extra.emphasis?{emphasis:extra.emphasis}:{}),...((extra.$unknown?.length || extra.systemAttachmentInfo)?{protected:true}:{})};
}
export function preservedParagraph(r:AttributeRun):PreservedParagraph|undefined {
 if(!r.paragraphStyle)return;const p=clone(ParagraphStyleSchema,r.paragraphStyle);
 clear(p,ParagraphStyleSchema,['style','indent','todo','startingListItemNumber','blockQuoteLevel','uuid']);
 if(p.writingDirection<=1 && (p.alignment===0 || p.alignment===4))clear(p,ParagraphStyleSchema,['alignment']);
 if(!p.writingDirection)clear(p,ParagraphStyleSchema,['writingDirection']);
 if(!p.paragraphHints)clear(p,ParagraphStyleSchema,['paragraphHints']);
 const bytes=toBinary(ParagraphStyleSchema,p);if(!bytes.length)return;
 return {token:Buffer.from(bytes).toString('base64'),alignment:p.alignment,direction:p.writingDirection};
}
export function enrich(paragraphs:FormatParagraph[],runs:readonly AttributeRun[]):RichParagraph[] {
 let at=0;const intervals=runs.map(run=>{const start=at;at+=run.length;return {run,start,end:at}});
 return paragraphs.map(p=>{
  const first=intervals.find(i=>i.start<=p.start && i.end>p.start),spans:RichSpan[]=[];
  for(let offset=p.start;offset<p.start+p.text.length;){const item=intervals.find(i=>i.start<=offset&&offset<i.end);if(!item)throw new Error('서식 범위를 확인할 수 없어 저장을 중단합니다.');
   const end=Math.min(item.end,p.start+p.text.length),style=preservedStyle(item.run),info=item.run.attachmentInfo;
   const span:RichSpan={...inlineStyleOfRun(item.run),length:end-offset,...(style?{style}:{}),...(info?{embed:{id:info.attachmentIdentifier,uti:info.typeUTI,title:info.typeUTI.startsWith('public.')?'이미지':'첨부'}}:{})},last=spans.at(-1);
   if(last && !info && JSON.stringify({...last,length:0})===JSON.stringify({...span,length:0}))last.length+=span.length;else spans.push(span);offset=end;
  }
  const separator=intervals.find(i=>i.start<=p.start+p.text.length && i.end>p.start+p.text.length);
  return {...p,spans,...(separator && preservedStyle(separator.run)?{separatorStyle:preservedStyle(separator.run)}:{}),...(first && preservedParagraph(first.run)?{paragraphStyle:preservedParagraph(first.run)}:{})};
 });
}
export function restoreExtras(doc:NoteDocument,desired:readonly RichParagraph[],original:readonly AttributeRun[],replica:Uint8Array) {
 const inline=new Set(original.map(preservedStyle).flatMap(s=>s?[s.token]:[])),paragraph=new Set(original.map(preservedParagraph).flatMap(s=>s?[s.token]:[]));
 const intervals:{start:number;end:number;style?:PreservedStyle;p?:PreservedParagraph}[]=[];
 desired.forEach((p,i)=>{let at=p.start;const end=desired[i+1]?.start ?? p.start+p.text.length;
  if(p.paragraphStyle && !paragraph.has(p.paragraphStyle.token))throw new Error('원본에서 확인되지 않은 문단 서식입니다.');
  for(const span of p.spans){if(span.style && !inline.has(span.style.token))throw new Error('원본에서 확인되지 않은 추가 서식입니다.');intervals.push({start:at,end:at+span.length,style:span.style,p:p.paragraphStyle});at+=span.length}
  if(p.separatorStyle && !inline.has(p.separatorStyle.token))throw new Error('원본에서 확인되지 않은 줄바꿈 서식입니다.');
  if(at<end)intervals.push({start:at,end,style:p.separatorStyle,p:p.paragraphStyle});
 });
 const changes:{start:number;end:number}[]=[],out:AttributeRun[]=[];let offset=0;
 for(const run of doc.attributeRuns){const end=offset+run.length;let at=offset;
  while(at<end){const interval=intervals.find(i=>i.start<=at && at<i.end);if(!interval)throw new Error('추가 서식 저장 범위가 본문과 일치하지 않습니다.');
   const stop=Math.min(end,interval.end),piece=clone(AttributeRunSchema,run);piece.length=stop-at;
   const before=toBinary(AttributeRunSchema,piece);
   const oldExtra=preservedStyle(piece),oldP=preservedParagraph(piece);
   if(oldExtra?.token!==interval.style?.token){
    const extra=interval.style?fromBinary(AttributeRunSchema,Buffer.from(interval.style.token,'base64')):create(AttributeRunSchema,{length:0});
    for(const name of ['color','superscript','writingDirection','emphasis','systemAttachmentInfo']){clear(piece,AttributeRunSchema,[name]);if(toBinary(AttributeRunSchema,extra).length && (extra as any)[name]!==undefined && (extra as any)[name]!==0)(piece as any)[name]=(extra as any)[name]}
    piece.$unknown=extra.$unknown?.map(u=>({...u,data:u.data.slice()}));
    if(extra.font)piece.font=clone(AttributeRunSchema,extra).font;else if(customFont(piece))clear(piece,AttributeRunSchema,['font']);
    piece.fontHints=(piece.fontHints&3)|(extra.fontHints&~3);
    if(extra.underline>1)piece.underline=extra.underline;else if(piece.underline>1)piece.underline=0;
    if(extra.strikethrough>1)piece.strikethrough=extra.strikethrough;else if(piece.strikethrough>1)piece.strikethrough=0;
   }
   if(oldP?.token!==interval.p?.token){
    const extra=interval.p?fromBinary(ParagraphStyleSchema,Buffer.from(interval.p.token,'base64')):create(ParagraphStyleSchema,{});
    piece.paragraphStyle ??= create(ParagraphStyleSchema,{style:3});const p=piece.paragraphStyle;
    for(const name of ['alignment','writingDirection','paragraphHints']){clear(p,ParagraphStyleSchema,[name]);if((extra as any)[name]!==0)(p as any)[name]=(extra as any)[name]}
    p.$unknown=extra.$unknown?.map(u=>({...u,data:u.data.slice()}));
   }
   if(!Buffer.from(before).equals(Buffer.from(toBinary(AttributeRunSchema,piece))))changes.push({start:at,end:stop});out.push(piece);at=stop;
  }offset=end;
 }
 if(changes.length){doc.attributeRuns=out;applyFormattingOp(doc,changes,replica)}
}
// Exact unknown/system-linked text islands cannot be edited or lost unnoticed.
export function protectedIslands(text:string,runs:readonly AttributeRun[]) {
 let at=0;const result:{text:string;token:string}[]=[];
 for(const run of runs){const style=preservedStyle(run);if(style?.protected){const previous=result.at(-1),part=text.slice(at,at+run.length);if(previous?.token===style.token)previous.text+=part;else result.push({text:part,token:style.token})}at+=run.length}
 return result;
}
