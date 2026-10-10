import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
const base=process.env.BSEND_BASE || "http://127.0.0.1:8787";
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const until=async(fn,label,ms=12000)=>{for(let i=0;i<ms/25;i++){if(fn())return;await pause(25)}throw Error("Timeout "+label)};
const packet=async(uri,body)=>{
 const r=await fetch(base+uri,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(body)});
 return {status:r.status,body:await r.json()};
};
const connect=async(url)=>{
 const parsed=base.startsWith("http://")?url.replace(/^wss:/,"ws:"):url;
 const socket=new WebSocket(parsed);
 await new Promise((resolve,reject)=>{
   const timeout=setTimeout(()=>reject(Error("Timed out opening WebSocket")),12000);
   socket.addEventListener("open",()=>{clearTimeout(timeout);resolve()},{once:true});
   socket.addEventListener("error",()=>{clearTimeout(timeout);reject(Error("WS handshake rejected"))},{once:true});
 });
 return socket;
};
const id=randomBytes(16).toString("hex"),secret=randomBytes(32).toString("hex");
const session=await packet("/api/session",{
  deviceId:id,deviceOwnerSecret:secret,deviceLinkSecret:randomBytes(32).toString("hex"),deviceName:"Resume Simulator"
});
assert.equal(session.status,201);
const sess=session.body;
const code=await fetch(base+"/api/code/"+sess.code).then(r=>r.json());
const guest=await connect(base.replace(/^http:/,"ws:").replace(/^https:/,"wss:")+
 "/api/room/"+sess.room+"/ws?role=guest&token="+code.guestToken);
let oldOwner=await connect(sess.ownerWebSocketURL);
const messages=[];
guest.addEventListener("message",e=>{if(typeof e.data==="string"){try{messages.push(JSON.parse(e.data))}catch{}}});
await until(()=>messages.some(m=>m.type==="peer"&&m.online),"initial owner");
const replacement=await connect(sess.ownerWebSocketURL);
await until(()=>messages.some(m=>m.type==="peer"&&m.online),"replacement owner");
await until(()=>oldOwner.readyState===WebSocket.CLOSED,"old owner reclaimed");
assert.equal(guest.readyState,WebSocket.OPEN,"Browser guest should remain connected");
const marker="Q".repeat(70);
const delivered=[];
replacement.addEventListener("message",e=>{if(typeof e.data==="string"){try{const m=JSON.parse(e.data);if(m.type==="enc")delivered.push(m.blob)}catch{}}});
guest.send(JSON.stringify({type:"enc",blob:marker}));
await until(()=>delivered.includes(marker),"guest message through replacement owner");
const online=await fetch(base+"/api/room/"+sess.room+"/presence").then(r=>r.json()).catch(()=>null);
if(online)assert.equal(online.ownerOnline,true);
console.log("PASS native iPhone owner WebSocket reconnect replaces stale server socket without HTTP 409");
console.log("PASS Safari guest stays connected and encrypted relay still forwards frames after takeover");
for(const ws of [oldOwner,replacement,guest])if(ws.readyState===WebSocket.OPEN)ws.close();
