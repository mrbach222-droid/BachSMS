import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";

const base = process.env.BSEND_BASE || "http://127.0.0.1:8787";
const hex = size => randomBytes(size).toString("hex");
const jsonPost = async (path, body) => {
  const resp = await fetch(base+path,{method:"POST",headers:{"content-type":"application/json"},
    body:JSON.stringify(body),cache:"no-store"});
  return {status:resp.status,body:await resp.json()};
};
const until = async (predicate,timeout=10000) => {
  const started=Date.now();
  while(Date.now()-started<timeout){
    if(predicate())return;
    await new Promise(done=>setTimeout(done,35));
  }
  throw Error("Timeout waiting for relay message");
};
const connect = async url => {
  const secureUrl=url.replace(/^http:/,"ws:").replace(/^https:/,"wss:");
  const ws = new WebSocket(base.startsWith("http://")
    ? secureUrl.replace(/^wss:/,"ws:") : secureUrl);
  await new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>reject(Error("WS timeout")),12000);
    ws.addEventListener("open",()=>{clearTimeout(timeout);resolve()},{once:true});
    ws.addEventListener("error",()=>{clearTimeout(timeout);reject(Error("WS rejected"))},{once:true});
  });
  return ws;
};
const wsFor = (session,token) =>
  base.replace(/^http:/,"ws:").replace(/^https:/,"wss:")+
  "/api/room/"+session.room+"/ws?role=guest&token="+token;

const health=await fetch(base+"/api/health").then(r=>r.json());
assert.equal(health.version,"0.6.0-private-device");
assert.equal(health.globalDiscovery,false);
const global=await fetch(base+"/api/auto-connect");
assert.equal(global.status,410,"Globally discovering other people's iPhones MUST be disabled");
console.log("PASS global discovery disabled");

const a={deviceId:hex(16),deviceOwnerSecret:hex(32),deviceLinkSecret:hex(32),deviceName:"iPhone A"};
const b={deviceId:hex(16),deviceOwnerSecret:hex(32),deviceLinkSecret:hex(32),deviceName:"iPhone B"};
const capA={deviceId:a.deviceId,deviceSecret:a.deviceLinkSecret};
const capB={deviceId:b.deviceId,deviceSecret:b.deviceLinkSecret};
const first=await jsonPost("/api/session",a),second=await jsonPost("/api/session",b);
assert.equal(first.status,201);
assert.equal(second.status,201);
assert.notEqual(first.body.room,second.body.room);
const sessionA=first.body,sessionB=second.body;
assert.equal((await jsonPost("/api/device/connect",capA)).status,404,
             "Offline iPhone must not appear available");

const ownerA=await connect(sessionA.ownerWebSocketURL);
const ownerB=await connect(sessionB.ownerWebSocketURL);
const wrong=await jsonPost("/api/device/connect",
  {deviceId:a.deviceId,deviceSecret:b.deviceLinkSecret});
assert.equal(wrong.status,403,"Link for user B must not access user A");
const spoof=await jsonPost("/api/session",{
  deviceId:a.deviceId,deviceOwnerSecret:a.deviceLinkSecret,
  deviceLinkSecret:a.deviceLinkSecret,deviceName:"Fake owner"
});
assert.equal(spoof.status,403,"Knowing the PC link must NOT permit owner impersonation");
const resolvedA=await jsonPost("/api/device/connect",capA);
const resolvedB=await jsonPost("/api/device/connect",capB);
assert.equal(resolvedA.status,200);
assert.equal(resolvedB.status,200);
assert.equal(resolvedA.body.room,sessionA.room);
assert.equal(resolvedB.body.room,sessionB.room);
assert.notEqual(resolvedA.body.guestToken,resolvedB.body.guestToken);
assert.equal(resolvedA.body.name,a.deviceName);
console.log("PASS two simultaneous private device discovery and secret isolation");

const guestA=await connect(wsFor(sessionA,resolvedA.body.guestToken));
const guestB=await connect(wsFor(sessionB,resolvedB.body.guestToken));
const busy=await jsonPost("/api/device/connect",capA);
assert.equal(busy.status,409,"A second PC must not seize a busy phone");

const heardA=[],heardB=[];
ownerA.addEventListener("message",event=>{
 try{const obj=JSON.parse(event.data);if(obj.type==="enc")heardA.push(obj.blob)}catch{}
});
ownerB.addEventListener("message",event=>{
 try{const obj=JSON.parse(event.data);if(obj.type==="enc")heardB.push(obj.blob)}catch{}
});
const signalA="Q".repeat(72),signalB="R".repeat(72);
guestA.send(JSON.stringify({type:"enc",blob:signalA}));
guestB.send(JSON.stringify({type:"enc",blob:signalB}));
await until(()=>heardA.includes(signalA)&&heardB.includes(signalB));
await new Promise(done=>setTimeout(done,250));
assert.deepEqual(heardA,[signalA],"Only A's frames may reach A");
assert.deepEqual(heardB,[signalB],"Only B's frames may reach B");
console.log("PASS two parallel WebSocket rooms: frames are never cross-forwarded");

const devicePage=await fetch(base+"/d/"+a.deviceId);
assert.equal(devicePage.status,200);
const html=await devicePage.text();
assert(html.includes("devicesList")&&html.includes("validPrivateLink"));
assert(!html.includes(a.deviceLinkSecret)&&!html.includes(a.deviceOwnerSecret));
console.log("PASS private device website serves no device credential");
for(const ws of [ownerA,ownerB,guestA,guestB])ws.close();
console.log("PASS B Send v0.6 multi-device private connect end-to-end");
