import assert from "node:assert/strict";
import {randomBytes,createECDH,hkdfSync,createCipheriv,createDecipheriv,createHash} from "node:crypto";
import {webkit} from "playwright";
const base=process.env.BSEND_BASE||"http://127.0.0.1:8787";
const deviceId=randomBytes(16).toString("hex");
const deviceOwnerSecret=randomBytes(32).toString("hex");
const deviceLinkSecret=randomBytes(32).toString("hex");
const signaled=[],readyOffsets=[],verifiedReceipts=[];
const fileId="mobile-5g-safari-checkpoint-test";
const blockLength=48*1024,initialBlocks=16;
const payload=randomBytes(25*blockLength+29);
const payloadSHA=createHash("sha256").update(payload).digest("hex");
async function waitFor(fn,label,seconds=20){
 for(let n=0;n<seconds*20;n++){if(fn())return;await new Promise(r=>setTimeout(r,50))}
 throw Error("Timeout "+label);
}
function encryptedFrame(plaintext){
 if(!derivedKey)throw Error("No paired AES-GCM key");
 const iv=randomBytes(12),cipher=createCipheriv("aes-256-gcm",derivedKey,iv);
 return Buffer.concat([iv,cipher.update(plaintext),cipher.final(),cipher.getAuthTag()]);
}
function sendControl(payload){
 const box=encryptedFrame(Buffer.from(JSON.stringify(payload)));
 owner.send(JSON.stringify({type:"enc",blob:box.toString("base64")}));
}
function decryptFrame(frame){
 const b=Buffer.from(frame.blob,"base64");
 const d=createDecipheriv("aes-256-gcm",derivedKey,b.subarray(0,12));
 d.setAuthTag(b.subarray(b.length-16));
 return JSON.parse(Buffer.concat([d.update(b.subarray(12,b.length-16)),d.final()]).toString());
}
const response=await fetch(base+"/api/session",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({
 deviceId,deviceOwnerSecret,deviceLinkSecret,deviceName:"Test Safari Private"
})});
if(response.status!==201)throw Error("Could not create private iPhone session: "+await response.text());
const info=await response.json();
const ownerURL=base.startsWith("http:")
 ?info.ownerWebSocketURL.replace(/^wss:/,"ws:"):info.ownerWebSocketURL;
const owner=new WebSocket(ownerURL);
await new Promise((resolve,reject)=>{
 const t=setTimeout(()=>reject(Error("Owner WebSocket timed out")),12000);
 owner.addEventListener("open",()=>{clearTimeout(t);resolve()},{once:true});
 owner.addEventListener("error",()=>{clearTimeout(t);reject(Error("Owner socket failed"))},{once:true});
});
let derivedKey=null;
owner.addEventListener("message",event=>{
 const message=JSON.parse(event.data);
 if(message.type==="enc"&&derivedKey){
   try{
    const frame=decryptFrame(message);
    if(frame.type==="file-ready")readyOffsets.push(frame.offset);
    if(frame.type==="file-ack")verifiedReceipts.push(frame);
   }catch(e){/* race with a re-pairing key */ }
 }
 if(message.type==="key-offer"){
  try{
   const clientKey=Buffer.from(message.pub,"base64");
   assert.equal(clientKey.length,65);
   const ownECDH=createECDH("prime256v1");ownECDH.generateKeys();
   derivedKey=Buffer.from(hkdfSync("sha256",ownECDH.computeSecret(clientKey),
      Buffer.alloc(0),Buffer.from("B Send v0.5:"+info.room),32));
   owner.send(JSON.stringify({type:"key-answer",pub:ownECDH.getPublicKey().toString("base64")}));
   sendControl({type:"pair-approved"});
   signaled.push("key-answer");
  }catch(error){signaled.push("ERR:"+error.message)}
 }
});
const browser=await webkit.launch({headless:true});
const errors=[];
const context=await browser.newContext({
  viewport:{width:393,height:852},deviceScaleFactor:3,isMobile:true,
  hasTouch:true,userAgent:"Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
});
async function connectSafari(url,name){
 const page=await context.newPage();
 page.on("pageerror",e=>{errors.push("pageerror "+e.message);console.log("WEBKIT PAGE ERROR",e.message,e.stack?.slice(0,500))});
 page.on("console",e=>{if(e.type()==="error"){errors.push("console "+e.text());console.log("WEBKIT CONSOLE ERROR",e.text())}});
 const navigated=await page.goto(url,{waitUntil:"domcontentloaded",timeout:20000});
 assert.equal(navigated.status(),200,name+": Bad HTTP response");
 const diagnosis=await page.evaluate(()=>({
   note:document.getElementById("deviceNote")?.textContent,
   state:document.getElementById("state")?.textContent,
   error:document.getElementById("notice")?.textContent,
   safari: /iPhone/i.test(navigator.userAgent),
   hash:location.hash,
   hasDevices:!!document.getElementById("devicesList")
 }));
 console.log(name,"initial",JSON.stringify(diagnosis));
 try{
  await page.waitForFunction(()=>{
    return document.getElementById("state")?.textContent.includes("Mã hóa đầu cuối");
  },null,{timeout:12000});
 }catch(e){
  const diag=await page.evaluate(()=>({
    state:document.getElementById("state")?.textContent,
    error:document.getElementById("notice")?.textContent,
    hash:location.hash,
    preferred:localStorage.getItem("bsend.personal.preferred.v062"),
    scripts:[...document.scripts].map(x=>x.textContent?.length),
    online:!!document.getElementById("pair"),
    ready:document.readyState
  })).catch(x=>({error:String(x)}));
  console.log("SAFARI DIAGNOSTIC",name,JSON.stringify({diag,errors,signaled}));
  throw e;
 }
 const data=await page.evaluate(()=>({
  state:document.getElementById("state")?.textContent,
  note:document.getElementById("notice")?.textContent,
  hash:location.hash
 }));
 assert.equal(data.hash,"","Private link must be hidden from Safari address bar");
 console.log("PASS",name,"Safari WebKit pairing:",JSON.stringify(data));
 return page;
}
let page=null;
try{
 page=await connectSafari(base+"/d/"+deviceId+"#"+deviceLinkSecret,"first-time");
 assert(signaled.includes("key-answer"),"Safari pairing must succeed");
 // Simulate a mobile 5G connection delivering 16 encrypted 48KiB chunks.
 sendControl({type:"file-start",id:fileId,name:"mobile-5g.bin",
  size:payload.length,sha256:payloadSHA,v:2});
 await waitFor(()=>readyOffsets.length===1,"first checkpoint offer");
 assert.equal(readyOffsets[0],0);
 for(let i=0;i<initialBlocks;i++){
  owner.send(encryptedFrame(payload.subarray(i*blockLength,(i+1)*blockLength)));
 }
 const checkpointBytes=initialBlocks*blockLength;
 await page.waitForFunction(n=>{
  const row=document.getElementById("incomingRow");
  return row&&!row.classList.contains("hidden")&&
    document.getElementById("incomingDetail").textContent.includes("768 KB");
 },null,{timeout:20000});
 const checkpoint=await page.evaluate(async({room,id})=>{
  const database=await new Promise((resolve,reject)=>{
   const request=indexedDB.open("bsend.local-received.v066",2);
   request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);
  });
  const record=await new Promise((resolve,reject)=>{
   const req=database.transaction("partial_meta","readonly")
     .objectStore("partial_meta").get(room+":"+id);
   req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);
  });
  database.close();return record;
 },{room:info.room,id:fileId});
 assert.equal(checkpoint?.got,checkpointBytes,"16 chunks must be committed before ACK");
 console.log("PASS WebKit Safari committed "+checkpointBytes+" encrypted bytes to IndexedDB");
 await page.close();
 await new Promise(r=>setTimeout(r,450));
 // Safari is restarted; browser JS memory is gone. Saved IndexedDB survives.
 page=await connectSafari(base+"/","remembered-device");
 sendControl({type:"file-start",id:fileId,name:"mobile-5g.bin",
  size:payload.length,sha256:payloadSHA,v:2});
 await waitFor(()=>readyOffsets.length===2,"resumed checkpoint offer");
 assert.equal(readyOffsets[1],checkpointBytes,
   "Safari must advertise persisted offset after tab restart");
 for(let p=checkpointBytes;p<payload.length;p+=blockLength)
  owner.send(encryptedFrame(payload.subarray(p,p+blockLength)));
 await page.waitForFunction(()=>document.getElementById("incomingPercent").textContent==="100%",
  null,{timeout:24000});
 sendControl({type:"file-end",id:fileId,sha256:payloadSHA});
 await waitFor(()=>verifiedReceipts.length===1,"SHA-256 verified acknowledgment");
 assert.equal(verifiedReceipts[0].verified,true);
 await page.waitForFunction(()=>document.querySelector('#received .file[data-name="mobile-5g.bin"]')!==null,
  null,{timeout:18000});
 const saved=await page.evaluate(async()=>{
  const db=await new Promise((resolve,reject)=>{
   const req=indexedDB.open("bsend.local-received.v066",2);
   req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);
  });
  const item=await new Promise((resolve,reject)=>{
   const req=db.transaction("files","readonly").objectStore("files")
     .get("mobile-5g-safari-checkpoint-test");
   req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);
  });
  db.close();
  const sha=new Uint8Array(await crypto.subtle.digest("SHA-256",await item.blob.arrayBuffer()));
  return {length:item.blob.size,sha:Array.from(sha,n=>n.toString(16).padStart(2,"0")).join("")};
 });
 assert.equal(saved.length,payload.length);
 assert.equal(saved.sha,payloadSHA,"Restored Safari file must match SHA-256");
 assert.equal(errors.length,0,JSON.stringify(errors));
 console.log("PASS WebKit tab close/reopen resumed "+checkpointBytes+
   " bytes and verified full "+payload.length+" byte SHA256 file");
}finally{await browser.close();owner.close();}
