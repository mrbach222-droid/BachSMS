import assert from "node:assert/strict";
import { randomBytes, webcrypto } from "node:crypto";

const endpoint = "https://bachsend-relay.mrbach222.workers.dev";
const health = await fetch(endpoint + "/api/health");
assert.equal(health.status, 200, "Worker health status");
const healthBody = await health.json();
assert.equal(healthBody.status, "ready");
assert.equal(healthBody.transport, "wss");
console.log("PASS health",healthBody.version);
const response = await fetch(endpoint + "/api/session", {
  method: "POST", headers: { "content-type": "application/json" }, body: "{}"
});
assert.equal(response.status, 201, "Create ephemeral session");
const session = await response.json();
assert.match(session.ownerWebSocketURL, /^wss:\/\/bachsend-relay\./);
assert.match(session.guestURL, /^https:\/\/bachsend-relay\./);
assert.equal(session.room.length, 32);
console.log("PASS new room with private owner/guest access");

const guestLink = new URL(session.guestURL);
assert.equal(guestLink.hash.length, 65, "Guest token in fragment only");
const guestToken = guestLink.hash.substring(1);
const guestWSURL = "wss://" + guestLink.host + "/api/room/" + session.room +
  "/ws?role=guest&token=" + guestToken;
const owner = new WebSocket(session.ownerWebSocketURL);
const guest = new WebSocket(guestWSURL);
owner.binaryType = "arraybuffer";
guest.binaryType = "arraybuffer";
function opened(sock) {
  return new Promise((resolve,reject)=>{
    if(sock.readyState===1)return resolve();
    const timer=setTimeout(()=>reject(new Error("WebSocket handshake timeout")),12000);
    sock.addEventListener("open",()=>{clearTimeout(timer);resolve();},{once:true});
    sock.addEventListener("error",()=>{clearTimeout(timer);reject(new Error("WebSocket rejected"))},{once:true});
  });
}
function frame(sock, predicate) {
  return new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>{
      sock.removeEventListener("message",handler);
      reject(new Error("Missing relayed frame"));
    },12000);
    function handler(event){
      try {
        if (!predicate(event.data)) return;
        clearTimeout(timeout);
        sock.removeEventListener("message",handler);
        resolve(event.data);
      }catch(err){clearTimeout(timeout);sock.removeEventListener("message",handler);reject(err)}
    }
    sock.addEventListener("message",handler);
  });
}
try {
  await Promise.all([opened(owner),opened(guest)]);
  console.log("PASS owner + PC guest WSS handshakes");
  const keyBytes=randomBytes(32), nonce=randomBytes(12);
  const key=await webcrypto.subtle.importKey("raw",keyBytes,{name:"AES-GCM"},false,["encrypt","decrypt"]);
  const plain=new TextEncoder().encode(JSON.stringify({type:"file-start",id:"sample",name:"demo.txt",size:4}));
  const sealed=new Uint8Array(await webcrypto.subtle.encrypt({name:"AES-GCM",iv:nonce},key,plain));
  const packet=Buffer.concat([nonce,Buffer.from(sealed)]);
  const envelope={type:"enc",blob:packet.toString("base64")};
  const awaited=frame(owner,bytes=>{
    if(typeof bytes!=="string")return false;
    const content=JSON.parse(bytes);
    return content.type==="enc"&&content.blob===envelope.blob;
  });
  guest.send(JSON.stringify(envelope));
  const forwarded=JSON.parse(await awaited);
  const encrypted=Buffer.from(forwarded.blob,"base64");
  const decoded=await webcrypto.subtle.decrypt({name:"AES-GCM",iv:encrypted.subarray(0,12)},key,encrypted.subarray(12));
  assert.equal(Buffer.from(decoded).toString(),Buffer.from(plain).toString());
  console.log("PASS encrypted metadata delivered unmodified");
  const plaintext=Buffer.from("test");
  const n=randomBytes(12);
  const crypted=new Uint8Array(await webcrypto.subtle.encrypt({name:"AES-GCM",iv:n},key,plaintext));
  const frameBytes=Buffer.concat([n,Buffer.from(crypted)]);
  const frameAwait=frame(owner,data=>data instanceof ArrayBuffer);
  guest.send(frameBytes);
  const actual=new Uint8Array(await frameAwait);
  assert.deepEqual(Buffer.from(actual),frameBytes);
  const decodedChunk=await webcrypto.subtle.decrypt({name:"AES-GCM",iv:actual.slice(0,12)},key,actual.slice(12));
  assert.equal(Buffer.from(decodedChunk).toString(),"test");
  console.log("PASS E2E encrypted file chunk relayed and decrypted");
} finally {
  owner.close(); guest.close();
}
console.log("PASS live cross-network Cloudflare relay smoke test");
