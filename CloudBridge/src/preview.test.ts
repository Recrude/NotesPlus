import {test} from 'node:test';import assert from 'node:assert/strict';import {imagePreview} from './preview.js';
test('preview never sends cookies or follows an asset redirect outside Apple hosts',async()=>{
 const original=globalThis.fetch;let calls=0;
 try{globalThis.fetch=(async(input:any,options:any)=>{calls++;assert.equal(options.redirect,'manual');assert.equal(options.headers,undefined);return new Response('',{status:302,headers:{location:'https://example.org/trap'}})}) as typeof fetch;
 assert.equal(await imagePreview('https://p01-content.icloud-content.com/asset'),undefined);assert.equal(calls,1);
 assert.equal(await imagePreview('https://icloud.com.example.org/asset'),undefined);assert.equal(calls,1);
 assert.equal(await imagePreview('http://icloud.com/asset'),undefined);assert.equal(calls,1);
 }finally{globalThis.fetch=original}
});
test('preview size limit rejects oversized assets before reading them',async()=>{
 const original=globalThis.fetch;
 try{globalThis.fetch=(async()=>new Response('large',{headers:{'content-length':String(20*1024*1024)}})) as typeof fetch;assert.equal(await imagePreview('https://icloud-content.com/asset'),undefined)}finally{globalThis.fetch=original}
});
