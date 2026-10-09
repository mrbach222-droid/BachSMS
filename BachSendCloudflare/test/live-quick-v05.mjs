import assert from "node:assert/strict";
import {webcrypto} from "node:crypto";

const base="https://bachsend-relay.mrbach222.workers.dev";
const enc=new TextEncoder(), dec=new TextDecoder();
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function expectReady(){
 for(let i=0;i<22;i++){
  try{
   const h=await fetch(base+"/api/health",{cache:"no-store"});
   const j=await h.json();
   if(j.version==="0.5-quick")return j;
   console.log("Waiting for 0.5 deployment, now",j.version);
  }catch(e){console.log("Waiting for Worker health",e.message)}
  await pause(5000);
 }
 throw new Error("Cloudflare not deployed to v0.5 after ~110s");
}
const health=await expectReady();
assert.equal(health.status,"ready");
assert.equal(health.shortCodes,true);
console.log("PASS live Cloudflare 0.5 health");

const created=await fetch(base+"/api/session",{method:"POST",headers:{"content-type":"application/json"},body:"{}"});
assert.equal(created.status,201,await created.text().catch(()=>""));
const room=await created.json();
assert.match(room.code,/^[A-HJ-NP-Z2-9]{8}$/);
assert.equal(room.shortURL,base+"/p/"+room.code);
assert.match(room.ownerWebSocketURL,/^wss:/);
const lookup=await fetch(base+"/api/code/"+room.code);
assert.equal(lookup.status,200,"Resolve short code");
const data=await lookup.json();
assert.equal(data.room,room.room);
assert.match(data.guestToken,/^[a-f0-9]{64}$/);
console.log("PASS short code generated & resolved",room.code);

const homepage=await fetch(base+"/");
const html=await homepage.text();
assert(homepage.ok&&html.includes("QUICK CONNECT"));
assert(html.includes("className=\"thumb\"")||html.includes("function preview("));
const shortPage=await fetch(room.shortURL);
assert(shortPage.ok&&(await shortPage.text()).includes("Kết nối"));
console.log("PASS branded PC homepage and short-link route");

const owner=new WebSocket(room.ownerWebSocketURL);
const guestURL="wss://"+new URL(base).host+"/api/room/"+room.room+"/ws?role=guest&token="+data.guestToken;
const guest=new WebSocket(guestURL);
owner.binaryType="arraybuffer";guest.binaryType="arraybuffer";
function waitOpen(socket){
 return new Promise((resolve,reject)=>{
  if(socket.readyState===WebSocket.OPEN)return resolve();
  const t=setTimeout(()=>reject(new Error("WebSocket open timeout")),12000);
  socket.addEventListener("open",()=>{clearTimeout(t);resolve()},{once:true});
  socket.addEventListener("error",()=>{clearTimeout(t);reject(new Error("WebSocket handshake error"))},{once:true});
 });
}
function receive(socket,check){
 return new Promise((resolve,reject)=>{
  const t=setTimeout(()=>{socket.removeEventListener("message",cb);reject(new Error("Frame timeout"))},12000);
  function cb(e){try{if(!check(e.data))return;clearTimeout(t);socket.removeEventListener("message",cb);resolve(e.data)}catch(err){clearTimeout(t);socket.removeEventListener("message",cb);reject(err)}}
  socket.addEventListener("message",cb);
 });
}
try{
 await Promise.all([waitOpen(owner),waitOpen(guest)]);
 console.log("PASS Owner/PC WebSocket handshakes");
 const pc=await webcrypto.subtle.generateKey({name:"ECDH",namedCurve:"P-256"},true,["deriveBits"]);
 const phone=await webcrypto.subtle.generateKey({name:"ECDH",namedCurve:"P-256"},true,["deriveBits"]);
 const pcPub=new Uint8Array(await webcrypto.subtle.exportKey("raw",pc.publicKey));
 const phonePub=new Uint8Array(await webcrypto.subtle.exportKey("raw",phone.publicKey));
 const offer={type:"key-offer",pub:Buffer.from(pcPub).toString("base64")};
 const offerWait=receive(owner,x=>typeof x==="string"&&JSON.parse(x).type==="key-offer");
 guest.send(JSON.stringify(offer));
 assert.equal(JSON.parse(await offerWait).pub,offer.pub);
 const answer={type:"key-answer",pub:Buffer.from(phonePub).toString("base64")};
 const answerWait=receive(guest,x=>typeof x==="string"&&JSON.parse(x).type==="key-answer");
 owner.send(JSON.stringify(answer));assert.equal(JSON.parse(await answerWait).pub,answer.pub);
 const pubPC=await webcrypto.subtle.importKey("raw",phonePub,{name:"ECDH",namedCurve:"P-256"},false,[]);
 const pubPhone=await webcrypto.subtle.importKey("raw",pcPub,{name:"ECDH",namedCurve:"P-256"},false,[]);
 const bitsA=await webcrypto.subtle.deriveBits({name:"ECDH",public:pubPC},pc.privateKey,256);
 const bitsB=await webcrypto.subtle.deriveBits({name:"ECDH",public:pubPhone},phone.privateKey,256);
 assert.deepEqual(Buffer.from(bitsA),Buffer.from(bitsB));
 const hkdf=await webcrypto.subtle.importKey("raw",bitsA,"HKDF",false,["deriveBits"]);
 const keyBytes=new Uint8Array(await webcrypto.subtle.deriveBits({name:"HKDF",hash:"SHA-256",salt:new Uint8Array(),info:enc.encode("B Send v0.5:"+room.room)},hkdf,256));
 const key=await webcrypto.subtle.importKey("raw",keyBytes,{name:"AES-GCM"},false,["encrypt","decrypt"]);
 async function seal(data){
  const iv=webcrypto.getRandomValues(new Uint8Array(12));
  const ciphertext=new Uint8Array(await webcrypto.subtle.encrypt({name:"AES-GCM",iv},key,data));
  const result=new Uint8Array(12+ciphertext.length);result.set(iv);result.set(ciphertext,12);return result
 }
 async function open(data){
  return new Uint8Array(await webcrypto.subtle.decrypt({name:"AES-GCM",iv:data.slice(0,12)},key,data.slice(12)));
 }
 const verify=enc.encode(JSON.stringify({type:"pair-approved"}));
 const payload=await seal(verify);
 const envelope={type:"enc",blob:Buffer.from(payload).toString("base64")};
 const msgWait=receive(guest,x=>typeof x==="string"&&JSON.parse(x).type==="enc");
 owner.send(JSON.stringify(envelope));
 const got=JSON.parse(await msgWait);assert.equal(dec.decode(await open(Buffer.from(got.blob,"base64"))),dec.decode(verify));
 console.log("PASS ECDH key agreement, derived AES-GCM and encrypted approval");
 const clear=enc.encode("B Send thumbnail sample");
 const blob=await seal(clear);
 const blobWait=receive(owner,x=>x instanceof ArrayBuffer);
 guest.send(blob);
 const forwarded=new Uint8Array(await blobWait);
 assert.equal(dec.decode(await open(forwarded)),dec.decode(clear));
 console.log("PASS encrypted binary file chunks through relay");
}finally{owner.close();guest.close()}
console.log("PASS live B Send v0.5 short-code pairing smoke test");
