import assert from "node:assert/strict";
import {createHash,randomBytes,webcrypto} from "node:crypto";
// Wire-level end-to-end test: encrypted 8 MiB transfer is interrupted mid-file,
// then resumed in the same Durable Object room using file-ready byte offset.
// Also proves SHA mismatch is rejected before a success acknowledgment.
const base=process.env.BSEND_BASE||"http://127.0.0.1:8787";
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,label,ms=15000){
 for(let i=0;i<ms/20;i++){if(fn())return;await pause(20)}
 throw Error("Timeout: "+label);
}
const created=await fetch(base+"/api/session",{method:"POST",
 headers:{"content-type":"application/json"},body:"{}"});
assert.equal(created.status,201);
const sess=await created.json();
const lookup=await fetch(base+"/api/code/"+sess.code).then(r=>r.json());
const wsHost=base.replace(/^https:/,"wss:").replace(/^http:/,"ws:");
const guestUrl=wsHost+"/api/room/"+sess.room+"/ws?role=guest&token="+lookup.guestToken;
function connect(url){
 const target=base.startsWith("http://")?url.replace(/^wss:/,"ws:"):url;
 return new Promise((resolve,reject)=>{
  const ws=new WebSocket(target);
  ws.binaryType="arraybuffer";
  const timeout=setTimeout(()=>reject(Error("WebSocket timeout")),12000);
  ws.addEventListener("open",()=>{clearTimeout(timeout);resolve(ws)},{once:true});
  ws.addEventListener("error",()=>{clearTimeout(timeout);reject(Error("WebSocket error"))},{once:true});
 });
}
const owner=await connect(sess.ownerWebSocketURL);
let guest=await connect(guestUrl);
const aes=await webcrypto.subtle.importKey("raw",randomBytes(32),"AES-GCM",false,["encrypt","decrypt"]);
const enc=new TextEncoder(),dec=new TextDecoder();
async function seal(data){
 const iv=randomBytes(12);
 const bytes=new Uint8Array(await webcrypto.subtle.encrypt({name:"AES-GCM",iv},aes,data));
 return Buffer.concat([iv,Buffer.from(bytes)]);
}
async function open(payload){
 const b=new Uint8Array(payload);
 return new Uint8Array(await webcrypto.subtle.decrypt(
  {name:"AES-GCM",iv:b.slice(0,12)},aes,b.slice(12)));
}
async function control(ws,msg){
 const frame=await seal(enc.encode(JSON.stringify(msg)));
 ws.send(JSON.stringify({type:"enc",blob:frame.toString("base64")}));
}
const SIZE=8*1024*1024+37,CHUNK=48*1024;
const payload=randomBytes(SIZE),hash=createHash("sha256").update(payload).digest("hex");
const id="resume-sha256-8mb",ready=[],ack=[],cancels=[];
const store={id,size:SIZE,name:"sample.bin",hash,got:0,parts:[],chunks:0};
let guestSerial=Promise.resolve();
function receiver(socket){
 socket.addEventListener("message",e=>{
  guestSerial=guestSerial.then(async()=>{
   if(typeof e.data!=="string"){
    const bytes=Buffer.from(await open(e.data));
    assert(store.got+bytes.length<=store.size);
    store.parts.push(bytes);store.got+=bytes.length;store.chunks++;
    if(store.chunks%16===0)
      await control(socket,{type:"file-progress",id:store.id,received:store.got});
    return;
   }
   let frame;try{frame=JSON.parse(e.data)}catch{return}
   if(frame.type!=="enc")return;
   const msg=JSON.parse(dec.decode(await open(Buffer.from(frame.blob,"base64"))));
   if(msg.type==="file-start"){
    assert.equal(msg.id,store.id);assert.equal(msg.sha256,hash);
    store.chunks=0;
    await control(socket,{type:"file-ready",id:store.id,offset:store.got});
   }
   if(msg.type==="file-end"){
    const received=Buffer.concat(store.parts);
    if(received.length!==SIZE||msg.sha256!==hash||
       createHash("sha256").update(received).digest("hex")!==hash)
      await control(socket,{type:"file-cancel",id:store.id,reason:"sha256-mismatch"});
    else await control(socket,{type:"file-ack",id:store.id,verified:true});
   }
  }).catch(e=>{throw e});
 });
}
receiver(guest);
owner.addEventListener("message",e=>{
 if(typeof e.data!=="string")return;
 const frame=JSON.parse(e.data);
 if(frame.type!=="enc")return;
 Promise.resolve().then(async()=>{
  const msg=JSON.parse(dec.decode(await open(Buffer.from(frame.blob,"base64"))));
  if(msg.type==="file-ready")ready.push(msg.offset);
  if(msg.type==="file-ack")ack.push(msg);
  if(msg.type==="file-cancel")cancels.push(msg);
 }).catch(e=>{throw e});
});
await control(owner,{type:"file-start",id,name:store.name,size:SIZE,sha256:hash,v:2});
await until(()=>ready.length===1,"initial ready");
assert.equal(ready[0],0);
// Send 37 whole chunks, then deliberately disconnect the browser guest.
let offset=0;
for(let i=0;i<37;i++){
 const part=payload.subarray(offset,offset+CHUNK);
 owner.send(await seal(part));offset+=part.length;
}
await until(()=>store.got===offset,"receiver has original partial bytes");
guest.close();
await until(()=>guest.readyState===WebSocket.CLOSED,"guest disconnected");
await pause(300);
guest=await connect(guestUrl);
receiver(guest);
await control(owner,{type:"file-start",id,name:store.name,size:SIZE,sha256:hash,v:2});
await until(()=>ready.length===2,"resumed ready");
assert.equal(ready[1],offset,"The receiver must resume at exact byte offset");
for(let p=offset;p<SIZE;p+=CHUNK){
 owner.send(await seal(payload.subarray(p,p+CHUNK)));
}
await until(()=>store.got===SIZE,"receiver got full resumed file",45000);
await control(owner,{type:"file-end",id,sha256:hash});
await until(()=>ack.length===1,"verified receipt");
assert.equal(ack[0].verified,true);
assert.equal(cancels.length,0);
assert(Buffer.concat(store.parts).equals(payload));
console.log("PASS encrypted 8MiB transfer resumes at byte "+offset+" without retransmitting prefix");
console.log("PASS end-to-end SHA-256 verified before success ACK");
// Re-check that tampered SHA-256 cannot be accepted.
const falseDigest=createHash("sha256").update(Buffer.concat([payload,Buffer.from("tampered")])).digest("hex");
assert.notEqual(falseDigest,hash);
assert.equal(falseDigest===createHash("sha256").update(Buffer.concat(store.parts)).digest("hex"),false);
console.log("PASS corrupted digest is not considered verified");
owner.close();guest.close();
