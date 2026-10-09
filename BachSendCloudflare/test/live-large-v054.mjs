import assert from "node:assert/strict";
import { randomBytes, webcrypto } from "node:crypto";

const base = "https://bachsend-relay.mrbach222.workers.dev";
const pause = ms => new Promise(done=>setTimeout(done,ms));
let health;
for(let attempts=0;attempts<45;attempts++){
  try{
    const response=await fetch(base+"/api/health",{cache:"no-store"});
    health=await response.json();
    if(health.version==="0.5.4-large") break;
    console.log("Awaiting v0.5.4 Cloudflare deployment, currently",health.version);
  }catch(error){console.log("Worker not ready",error.message)}
  await pause(4000);
}
assert.equal(health?.version,"0.5.4-large","Expected new production deployment");
assert.equal(health.largeFiles,true);
console.log("PASS v0.5.4 Cloudflare health confirms large file mode");

const created=await fetch(base+"/api/session",{
 method:"POST",headers:{"content-type":"application/json"},body:"{}"
});
assert.equal(created.status,201,"Room creation");
const session=await created.json();
const directory=await fetch(base+"/api/code/"+session.code);
assert.equal(directory.status,200);
const guestToken=(await directory.json()).guestToken;
const owner=new WebSocket(session.ownerWebSocketURL);
const guest=new WebSocket("wss://"+new URL(base).host+"/api/room/"+session.room+
 "/ws?role=guest&token="+guestToken);
owner.binaryType="arraybuffer";guest.binaryType="arraybuffer";
function open(sock){
 return new Promise((resolve,reject)=>{
  if(sock.readyState===1)return resolve();
  const timer=setTimeout(()=>reject(Error("WebSocket connect timeout")),20000);
  sock.addEventListener("open",()=>{clearTimeout(timer);resolve()},{once:true});
  sock.addEventListener("error",()=>{clearTimeout(timer);reject(Error("WebSocket handshake failed"))},{once:true});
 });
}
await Promise.all([open(owner),open(guest)]);
console.log("PASS owner/PC encrypted relay connected");

const enc=new TextEncoder(),dec=new TextDecoder();
const raw=webcrypto.getRandomValues(new Uint8Array(32));
const key=await webcrypto.subtle.importKey("raw",raw,{name:"AES-GCM"},false,["encrypt","decrypt"]);
async function seal(buf){
 const nonce=randomBytes(12);
 const encrypted=new Uint8Array(await webcrypto.subtle.encrypt({name:"AES-GCM",iv:nonce},key,buf));
 const pack=new Uint8Array(encrypted.length+12);
 pack.set(nonce);pack.set(encrypted,12);return pack;
}
async function openPack(pack){
 const input=new Uint8Array(pack);
 return new Uint8Array(await webcrypto.subtle.decrypt(
  {name:"AES-GCM",iv:input.slice(0,12)},key,input.slice(12)));
}
async function sendControl(ws,body){
 const clear=enc.encode(JSON.stringify(body)),sealed=await seal(clear);
 ws.send(JSON.stringify({type:"enc",blob:Buffer.from(sealed).toString("base64")}));
}
const FILESIZE=52*1024*1024+17;
const CHUNK=48*1024;
let ownerRead=0,ownerPackets=0,ownerCompleted=false,ownerFailure=null,ackedBytes=0;
const id="test-52mb-windowed-chunks";
let ownerSerial=Promise.resolve();
owner.addEventListener("message",event=>{
 ownerSerial=ownerSerial.then(async()=>{
  if(typeof event.data==="string"){
   let envelope=JSON.parse(event.data);
   if(envelope.type!=="enc")return;
   const msg=JSON.parse(dec.decode(await openPack(Buffer.from(envelope.blob,"base64"))));
   if(msg.type==="file-start"){assert.equal(msg.size,FILESIZE);return}
   if(msg.type==="file-end"){
    assert.equal(msg.id,id);
    assert.equal(ownerRead,FILESIZE,"File completeness");
    await sendControl(owner,{type:"file-ack",id});
    ownerCompleted=true;
   }
   return;
  }
  const clear=await openPack(event.data);
  assert(clear.length<=CHUNK,"Chunk bound");
  for(const x of clear){if(x!==0x41)throw Error("Corrupt data")}
  ownerRead+=clear.length;ownerPackets++;
  if(ownerPackets%16===0)await sendControl(owner,{type:"file-progress",id,received:ownerRead});
 }).catch(error=>{ownerFailure=error;console.error("Receiver error",error.message)});
});
let acknowledged=false,guestFailure=null;
guest.addEventListener("message",event=>{
 if(typeof event.data!=="string")return;
 (async()=>{
  const msg=JSON.parse(event.data);if(msg.type!=="enc")return;
  const inner=JSON.parse(dec.decode(await openPack(Buffer.from(msg.blob,"base64"))));
  if(inner.type==="file-progress"){ackedBytes=Math.max(ackedBytes,inner.received)}
  if(inner.type==="file-ack"){assert.equal(inner.id,id);acknowledged=true}
 })().catch(error=>{guestFailure=error});
});
try{
 await sendControl(guest,{type:"file-start",id,name:"large-test.bin",size:FILESIZE});
 const start=Date.now();const block=new Uint8Array(CHUNK).fill(0x41);
 let sent=0,chunks=0;
 while(sent<FILESIZE){
  if(ownerFailure||guestFailure)throw ownerFailure||guestFailure;
  const n=Math.min(CHUNK,FILESIZE-sent);
  while(guest.bufferedAmount>512*1024)await pause(10);
  guest.send(await seal(block.subarray(0,n)));
  sent+=n;chunks++;
  if(chunks%16===0){
   const end=Date.now()+90000;
   while(ackedBytes<sent){
    if(ownerFailure||guestFailure)throw ownerFailure||guestFailure;
    if(Date.now()>end)throw Error("Receiver window ack timeout");
    await pause(15);
   }
  }
 }
 await sendControl(guest,{type:"file-end",id});
 const end=Date.now()+30000;
 while(!acknowledged){
  if(ownerFailure||guestFailure)throw ownerFailure||guestFailure;
  if(Date.now()>end)throw Error("No final file ACK");
  await pause(20);
 }
 assert(ownerCompleted);
 assert.equal(ownerRead,FILESIZE);
 console.log("PASS encrypted "+(FILESIZE/1048576).toFixed(2)+" MiB transferred in "+chunks+
  " file frames with paced acknowledgements ("+((Date.now()-start)/1000).toFixed(1)+"s)");
}finally{
 owner.close();guest.close();
}
console.log("PASS B Send v0.5.4 large-file relay smoke test");
