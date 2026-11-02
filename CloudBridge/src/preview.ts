// Download only the already-linked Apple asset, without forwarding iCloud cookies.
export async function imagePreview(url:string):Promise<string|undefined> {
 const allowed=(s:string)=>{const u=new URL(s);return u.protocol==='https:' && !u.username && !u.password && (!u.port || u.port==='443') && ['icloud.com','icloud-content.com','apple.com','apple-cloudkit.com'].some(d=>u.hostname===d || u.hostname.endsWith('.'+d))};
 if(!allowed(url))return;
 const max=12*1024*1024;let next=url;
 for(let redirects=0;redirects<4;redirects++){
  const response=await fetch(next,{redirect:'manual',signal:AbortSignal.timeout(15000)});
  if(response.status>=300&&response.status<400){const location=response.headers.get('location');await response.body?.cancel();if(!location)return;next=new URL(location,next).href;if(!allowed(next))return;continue;}
  if(!response.ok || !response.body || Number(response.headers.get('content-length'))>max){await response.body?.cancel();return;}
  const chunks:Uint8Array[]=[];let count=0;const reader=response.body.getReader();try{for(;;){const {done,value}=await reader.read();if(done)break;count+=value.length;if(count>max){await reader.cancel();return;}chunks.push(value)}}finally{reader.releaseLock()}
  return Buffer.concat(chunks).toString('base64');
 }
}
