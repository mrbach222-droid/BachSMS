import assert from "node:assert/strict";
import {randomBytes,createECDH,hkdfSync,createCipheriv,createHash} from "node:crypto";
import {webkit} from "playwright";
const base=process.env.BSEND_BASE||"http://127.0.0.1:8787";
const deviceId=randomBytes(16).toString("hex");
const deviceOwnerSecret=randomBytes(32).toString("hex");
const deviceLinkSecret=randomBytes(32).toString("hex");
const signaled=[];
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
 if(message.type==="key-offer"){
  try{
   const clientKey=Buffer.from(message.pub,"base64");
   assert.equal(clientKey.length,65);
   const ownECDH=createECDH("prime256v1");ownECDH.generateKeys();
   derivedKey=Buffer.from(hkdfSync("sha256",ownECDH.computeSecret(clientKey),
      Buffer.alloc(0),Buffer.from("B Send v0.5:"+info.room),32));
   owner.send(JSON.stringify({type:"key-answer",pub:ownECDH.getPublicKey().toString("base64")}));
   const iv=randomBytes(12),cipher=createCipheriv("aes-256-gcm",derivedKey,iv);
   const raw=Buffer.from(JSON.stringify({type:"pair-approved"}));
   const box=Buffer.concat([iv,cipher.update(raw),cipher.final(),cipher.getAuthTag()]);
   owner.send(JSON.stringify({type:"enc",blob:box.toString("base64")}));
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
 assert(signaled.includes("key-answer"),"The owner must receive Safari's initial key-offer");
 await page.close();
 await new Promise(resolve=>setTimeout(resolve,300));
 page=await connectSafari(base+"/","remembered-device");
 // Send a verified image to the actual WebKit browser through the local
 // Worker room, then reload the page and prove it can still be previewed.
 const image=Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/k00AAAAASUVORK5CYII=","base64");
 const digest=createHash("sha256").update(image).digest("hex"),fileID=randomBytes(16).toString("hex");
 function encryptPayload(bytes){
  const iv=randomBytes(12),c=createCipheriv("aes-256-gcm",derivedKey,iv);
  return Buffer.concat([iv,c.update(bytes),c.final(),c.getAuthTag()]);
 }
 function sendEncryptedControl(value){
  owner.send(JSON.stringify({type:"enc",blob:encryptPayload(Buffer.from(JSON.stringify(value))).toString("base64")}));
 }
 sendEncryptedControl({type:"file-start",id:fileID,name:"test-photo.png",size:image.length,sha256:digest,v:2});
 await page.waitForFunction(()=>document.getElementById("incomingName")?.textContent==="test-photo.png",null,{timeout:12000});
 owner.send(encryptPayload(image));
 await page.waitForFunction(()=>document.getElementById("incomingPercent")?.textContent==="100%",null,{timeout:12000});
 sendEncryptedControl({type:"file-end",id:fileID,sha256:digest});
 await page.waitForFunction(()=>Array.from(document.querySelectorAll("#received .file")).some(r=>r.dataset.name==="test-photo.png"),null,{timeout:12000});
 assert.equal(await page.locator("#received button").filter({hasText:"Xem"}).count(),1,"Image preview action missing");
 await page.getByRole("button",{name:"Xem"}).first().click();
 await page.locator("#previewModal:not(.hidden) img").waitFor();
 assert.equal(await page.locator("#previewSave").textContent(),"Lưu vào Ảnh / Chia sẻ");
 await page.locator("#previewClose").click();
 await page.waitForFunction(async()=>{
  return new Promise(resolve=>{
   const req=indexedDB.open("bsend.local-received.v066",1);
   req.onsuccess=()=>{
    const db=req.result,t=db.transaction("files","readonly"),items=t.objectStore("files").getAll();
    items.onsuccess=()=>{resolve(items.result.some(x=>x.name==="test-photo.png"));db.close()};
    items.onerror=()=>{db.close();resolve(false)}
   };
   req.onerror=()=>resolve(false);
  });
 },null,{timeout:12000});
 console.log("PASS Safari received image preview, SHA256 verified and IndexedDB durable save");
 await page.reload({waitUntil:"domcontentloaded"});
 await page.waitForFunction(()=>Array.from(document.querySelectorAll("#received .file")).some(r=>r.dataset.name==="test-photo.png"),null,{timeout:12000});
 await page.getByRole("button",{name:"Xem"}).first().click();
 await page.locator("#previewModal:not(.hidden) img").waitFor();
 console.log("PASS Safari finished-file persists across page reload without cloud storage");
 await page.locator("#previewClose").click();
 assert.equal(errors.length,0,JSON.stringify(errors));
 console.log("PASS Safari/WebKit remembered iPhone, media preview and completed-file persistence");
}finally{await browser.close();owner.close();}
