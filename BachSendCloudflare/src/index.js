import { DurableObject } from "cloudflare:workers";
import browserPage from "./page.js";

// B Send v0.5.2: one-tap pairing uses short-lived rooms and explicit iPhone consent.
// Payloads use session-derived AES-GCM; room discovery is restricted to one active
// iPhone. As an un-audited preview, never transfer confidential company files.
const TTL = 4 * 60 * 60 * 1000; // four-hour transfer session for large files
const TOKEN_PATTERN = /^[a-f0-9]{64}$/;
const ROOM_PATTERN = /^[a-f0-9]{32}$/;
const CODE_PATTERN = /^[A-HJ-NP-Z2-9]{8}$/;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function shortCode(){
  const bytes=crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes,v=>ALPHABET[v % ALPHABET.length]).join("");
}
const encoder = new TextEncoder();
function nonce(length) {
  return Array.from(crypto.getRandomValues(new Uint8Array(length)),
    value => value.toString(16).padStart(2, "0")).join("");
}
async function hashed(token) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(token));
  return Array.from(new Uint8Array(digest),
    value => value.toString(16).padStart(2, "0")).join("");
}
function result(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: {
    "content-type": "application/json;charset=utf-8",
    "cache-control": "no-store", "x-content-type-options": "nosniff",
  } });
}

export class QuickCodes extends DurableObject {
  async fetch(req){
    const url=new URL(req.url);
    if(url.pathname==="/register" && req.method==="POST"){
      const {code,room,guestToken,expiresAt}=await req.json();
      if(!CODE_PATTERN.test(code)||!ROOM_PATTERN.test(room)||!TOKEN_PATTERN.test(guestToken)||
         !Number.isFinite(expiresAt))return result({error:"bad_data"},400);
      const old=await this.ctx.storage.get("code:"+code);
      if(old&&old.expiresAt>Date.now())return result({error:"collision"},409);
      await this.ctx.storage.put("code:"+code,{room,guestToken,expiresAt,createdAt:Date.now()});
      const alarm=await this.ctx.storage.getAlarm();
      if(!alarm||alarm>Date.now()+60000)await this.ctx.storage.setAlarm(Date.now()+60000);
      return result({ok:true});
    }
    if(url.pathname==="/register-device" && req.method==="POST"){
      const data=await req.json();
      const {deviceId,deviceSecret,room,guestToken,expiresAt}=data;
      const name=String(data.deviceName||"iPhone").trim().slice(0,48).replace(/[\\x00-\\x1f\\x7f]/g,"");
      if(!ROOM_PATTERN.test(deviceId)||!TOKEN_PATTERN.test(deviceSecret)||
         !ROOM_PATTERN.test(room)||!TOKEN_PATTERN.test(guestToken)||
         !Number.isFinite(expiresAt)||expiresAt<=Date.now()||expiresAt>Date.now()+TTL+60000)
        return result({error:"bad_device_data"},400);
      const identityKey="identity:"+deviceId;
      const suppliedHash=await hashed(deviceSecret);
      const registered=await this.ctx.storage.get(identityKey);
      if(registered&&registered!==suppliedHash)
        return result({error:"device_identity_conflict"},403);
      if(!registered)await this.ctx.storage.put(identityKey,suppliedHash);
      await this.ctx.storage.put("device:"+deviceId,{room,guestToken,expiresAt,name});
      return result({ok:true});
    }
    if(url.pathname==="/connect-device" && req.method==="POST"){
      const ip=(req.headers.get("CF-Connecting-IP")||"unknown").slice(0,80);
      const period=Math.floor(Date.now()/60000),rateKey="device-rate:"+ip+":"+period;
      const hits=await this.ctx.storage.get(rateKey)||0;
      if(hits>=40)return result({error:"rate_limited"},429);
      await this.ctx.storage.put(rateKey,hits+1);
      let body;try{body=await req.json()}catch{return result({error:"bad_json"},400)}
      if(!ROOM_PATTERN.test(body?.deviceId||"")||!TOKEN_PATTERN.test(body?.deviceSecret||""))
        return result({error:"invalid_device_link"},400);
      const identity=await this.ctx.storage.get("identity:"+body.deviceId);
      if(!identity||identity!==await hashed(body.deviceSecret))
        return result({error:"invalid_device_link"},403);
      const entry=await this.ctx.storage.get("device:"+body.deviceId);
      if(!entry||entry.expiresAt<=Date.now())return result({error:"device_offline"},404);
      const stub=this.env.SESSIONS.get(this.env.SESSIONS.idFromName(entry.room));
      const presence=await stub.fetch(new Request("https://room.internal/presence"));
      if(!presence.ok)return result({error:"device_offline"},404);
      const status=await presence.json();
      if(!status.ownerOnline)return result({error:"device_offline"},404);
      if(status.guestOnline)return result({error:"device_busy"},409);
      return result({room:entry.room,guestToken:entry.guestToken,
                     expiresAt:entry.expiresAt,name:entry.name});
    }
    // Do not let a stranger globally discover the only online iPhone.
    if(url.pathname==="/connect-auto" && req.method==="GET")
      return result({error:"private_device_link_required"},410);
    const m=url.pathname.match(/^\/resolve\/([A-HJ-NP-Z2-9]{8})$/);
    if(m&&req.method==="GET"){
      const ip=(req.headers.get("CF-Connecting-IP")||"unknown").slice(0,80);
      const period=Math.floor(Date.now()/60000),key="ip:"+ip+":"+period;
      const hits=await this.ctx.storage.get(key)||0;
      if(hits>=12)return result({error:"rate_limited"},429);
      await this.ctx.storage.put(key,hits+1);
      const data=await this.ctx.storage.get("code:"+m[1]);
      if(!data||data.expiresAt<=Date.now())return result({error:"not_found_or_expired"},404);
      return result(data);
    }
    return result({error:"not_found",from:"directory",path:url.pathname},404);
  }
  async alarm(){
    const data=await this.ctx.storage.list(),now=Date.now(),period=Math.floor(now/60000);
    let open=false;
    for(const [key,value] of data){
      if(key.startsWith("code:")){
        if(value.expiresAt<=now)await this.ctx.storage.delete(key);
        else open=true;
      }else if(key.startsWith("device:")){
        if(value.expiresAt<=now)await this.ctx.storage.delete(key);
        else open=true;
      }else if((key.startsWith("ip:")||key.startsWith("auto:")||
                 key.startsWith("device-rate:"))&&Number(key.split(":").at(-1))<period-3){
        await this.ctx.storage.delete(key);
      }
    }
    if(open)await this.ctx.storage.setAlarm(now+60000);
  }
}

export class TransferRoom extends DurableObject {
  async fetch(request) {
    const uri = new URL(request.url);
    if (uri.pathname === "/init" && request.method === "POST") {
      if (await this.ctx.storage.get("expiresAt")) return result({ error: "exists" }, 409);
      const data = await request.json();
      if (!TOKEN_PATTERN.test(data.ownerToken) || !TOKEN_PATTERN.test(data.guestToken))
        return result({ error: "bad_token" }, 400);
      const expiresAt = Date.now() + TTL;
      await this.ctx.storage.put({
        ownerHash: await hashed(data.ownerToken),
        guestHash: await hashed(data.guestToken),
        expiresAt,
      });
      await this.ctx.storage.setAlarm(expiresAt);
      return result({ ok: true, expiresAt });
    }
    if(uri.pathname==="/presence" && request.method==="GET"){
      const sockets=this.ctx.getWebSockets();
      return result({
        ownerOnline:sockets.some(s=>s.readyState===1&&s.deserializeAttachment()?.role==="owner"),
        guestOnline:sockets.some(s=>s.readyState===1&&s.deserializeAttachment()?.role==="guest")
      });
    }
    if (uri.pathname !== "/ws" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket")
      return result({ error: "not_found" }, 404);
    const role = uri.searchParams.get("role");
    const token = uri.searchParams.get("token") || "";
    if (!["owner", "guest"].includes(role) || !TOKEN_PATTERN.test(token))
      return result({ error: "unauthorized" }, 401);
    const expiration = await this.ctx.storage.get("expiresAt");
    if (!expiration || expiration <= Date.now()) return result({ error: "expired" }, 410);
    const expected = await this.ctx.storage.get(role === "owner" ? "ownerHash" : "guestHash");
    if (await hashed(token) !== expected) return result({ error: "unauthorized" }, 401);
    if (this.ctx.getWebSockets().some(ws =>
      ws.deserializeAttachment()?.role === role && ws.readyState === 1))
      return result({ error: "role_connected" }, 409);
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ role });
    server.send(JSON.stringify({ type: "ready", role, expiresAt: expiration }));
    const opposite = role === "owner" ? "guest" : "owner";
    const peers = this.ctx.getWebSockets().filter(ws =>
      ws !== server && ws.readyState === 1 && ws.deserializeAttachment()?.role === opposite);
    server.send(JSON.stringify({ type: "peer", online: peers.length !== 0 }));
    for (const ws of peers) ws.send(JSON.stringify({ type: "peer", online: true }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, payload) {
    const meta = ws.deserializeAttachment();
    const expiration = await this.ctx.storage.get("expiresAt");
    if (!meta || !expiration || expiration <= Date.now()) {
      ws.close(1008, "Session expired"); return;
    }
    if (typeof payload === "string") {
      if (encoder.encode(payload).byteLength > 4096) {
        ws.close(1009, "Metadata too big"); return;
      }
      let frame;
      try { frame = JSON.parse(payload); } catch { return; }
      // Metadata is encrypted on iPhone/PC. Relay only forwards opaque sealed envelopes.
      if(frame.type === "key-offer" || frame.type === "key-answer"){
        if(typeof frame.pub !== "string" || !/^[A-Za-z0-9+/=]{85,95}$/.test(frame.pub))return;
      }else if (frame.type !== "enc" || typeof frame.blob !== "string" ||
          frame.blob.length < 40 || frame.blob.length > 4000 ||
          !/^[A-Za-z0-9+/=]+$/.test(frame.blob))return;
    } else if (payload.byteLength > 65536) {
      ws.close(1009, "Chunk too big"); return;
    }
    const other = meta.role === "owner" ? "guest" : "owner";
    for (const peer of this.ctx.getWebSockets()) {
      if (peer !== ws && peer.readyState === 1 &&
          peer.deserializeAttachment()?.role === other) peer.send(payload);
    }
  }

  async webSocketClose(ws) {
    const role = ws.deserializeAttachment()?.role;
    const other = role === "owner" ? "guest" : "owner";
    for (const peer of this.ctx.getWebSockets()) {
      if (peer !== ws && peer.readyState === 1 &&
          peer.deserializeAttachment()?.role === other)
        peer.send(JSON.stringify({ type: "peer", online: false }));
    }
  }

  async alarm() {
    for (const ws of this.ctx.getWebSockets()) {
      try { ws.close(1000, "Session expired"); } catch {}
    }
    await this.ctx.storage.deleteAll();
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/" && request.method === "GET")
      return new Response(browserPage("", true), {
        headers: { "content-type": "text/html;charset=utf-8", "cache-control": "no-store",
          "referrer-policy": "no-referrer", "x-content-type-options": "nosniff",
          "content-security-policy": "default-src 'none';frame-ancestors 'none';base-uri 'none';" +
            "script-src 'unsafe-inline';style-src 'unsafe-inline';connect-src 'self' wss:;img-src 'self' data: blob:;media-src blob:",
        }
      });
    if (url.pathname === "/api/health" && request.method === "GET")
      return result({ status: "ready", version: "0.6.0-private-device", transport: "wss", privateDevices: true, globalDiscovery: false, shortCodes: true, largeFiles: true });
    if (url.pathname === "/api/session" && request.method === "POST") {
      let requestBody={};
      try{requestBody=await request.json()}catch{return result({error:"bad_json"},400)}
      const room = nonce(16), ownerToken = nonce(32), guestToken = nonce(32);
      const obj = env.SESSIONS.get(env.SESSIONS.idFromName(room));
      const create = await obj.fetch(new Request("https://internal.room/init", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ ownerToken, guestToken }),
      }));
      if (!create.ok) return result({ error: "create_failed" }, 502);
      const data = await create.json();
      const dir=env.CODES.get(env.CODES.idFromName("quick-directory"));
      let code=null;
      for(let i=0;i<12;i++){
        const candidate=shortCode();
        const attempt=await dir.fetch(new Request("https://directory.internal/register",{
          method:"POST",headers:{"content-type":"application/json"},
          body:JSON.stringify({code:candidate,room,guestToken,expiresAt:data.expiresAt})
        }));
        if(attempt.ok){code=candidate;break;}
      }
      if(!code)return result({error:"quick_code_capacity"},503);
      if(requestBody.deviceId||requestBody.deviceSecret){
        const registered=await dir.fetch(new Request("https://directory.internal/register-device",{
          method:"POST",headers:{"content-type":"application/json"},
          body:JSON.stringify({deviceId:requestBody.deviceId,
              deviceSecret:requestBody.deviceSecret,
              deviceName:requestBody.deviceName,
              room,guestToken,expiresAt:data.expiresAt})
        }));
        if(!registered.ok){
          const error=await registered.json();
          return result({error:error.error||"device_registration_failed"},registered.status);
        }
      }
      return result({
        code,
        shortURL: url.origin+"/p/"+code,
        room, expiresAt: data.expiresAt,
        ownerWebSocketURL: "wss://" + url.host + "/api/room/" + room +
          "/ws?role=owner&token=" + ownerToken,
        guestURL: url.origin + "/s/" + room + "#" + guestToken,
      }, 201);
    }
    if(url.pathname==="/api/device/connect" && request.method==="POST"){
      const dir=env.CODES.get(env.CODES.idFromName("quick-directory"));
      return dir.fetch(new Request("https://directory.internal/connect-device",{
        method:"POST",
        headers:{"content-type":"application/json",
                 "CF-Connecting-IP":request.headers.get("CF-Connecting-IP")||"unknown"},
        body:await request.text()
      }));
    }
    if(url.pathname==="/api/auto-connect" && request.method==="GET"){
      const dir=env.CODES.get(env.CODES.idFromName("quick-directory"));
      const forwarded=new Request("https://directory.internal/connect-auto",{
        headers:{"CF-Connecting-IP":request.headers.get("CF-Connecting-IP")||"unknown"}
      });
      return dir.fetch(forwarded);
    }
    const lookup=url.pathname.match(/^\/api\/code\/([A-HJ-NP-Z2-9]{8})$/);
    if(lookup&&request.method==="GET"){
      const dir=env.CODES.get(env.CODES.idFromName("quick-directory"));
      const requestToRoom=new Request("https://directory.internal/resolve/"+lookup[1],{
        headers:{"CF-Connecting-IP":request.headers.get("CF-Connecting-IP")||"unknown"}
      });
      return dir.fetch(requestToRoom);
    }
    const short=url.pathname.match(/^\/p\/([A-HJ-NP-Z2-9]{8})$/);
    if(short&&request.method==="GET"){
      return new Response(browserPage(short[1],true),{
        headers:{"content-type":"text/html;charset=utf-8","cache-control":"no-store",
          "referrer-policy":"no-referrer","x-content-type-options":"nosniff",
          "content-security-policy":"default-src 'none';frame-ancestors 'none';base-uri 'none';" +
            "script-src 'unsafe-inline';style-src 'unsafe-inline';connect-src 'self' wss:;img-src 'self' data: blob:;media-src blob:"}
      });
    }
    const device = url.pathname.match(/^\/d\/([a-f0-9]{32})$/);
    if(device && request.method==="GET"){
      return new Response(browserPage(""), {
        headers: {"content-type":"text/html;charset=utf-8","cache-control":"no-store",
          "referrer-policy":"no-referrer","x-content-type-options":"nosniff",
          "content-security-policy":"default-src 'none';frame-ancestors 'none';base-uri 'none';" +
          "script-src 'unsafe-inline';style-src 'unsafe-inline';connect-src 'self' wss:;img-src 'self' data: blob:;media-src blob:"}
      });
    }
    const page = url.pathname.match(/^\/s\/([a-f0-9]{32})$/);
    if (page && request.method === "GET") {
      return new Response(browserPage(page[1]), {
        headers: {
          "content-type": "text/html;charset=utf-8",
          "cache-control": "no-store", "x-content-type-options": "nosniff",
          "referrer-policy": "no-referrer",
          "content-security-policy": "default-src 'none';base-uri 'none';frame-ancestors 'none';" +
            "script-src 'unsafe-inline';style-src 'unsafe-inline';connect-src 'self' wss:;img-src 'self' data: blob:;media-src blob:",
        },
      });
    }
    const socket = url.pathname.match(/^\/api\/room\/([a-f0-9]{32})\/ws$/);
    if (socket && request.method === "GET") {
      const obj = env.SESSIONS.get(env.SESSIONS.idFromName(socket[1]));
      return obj.fetch(new Request("https://internal.room/ws" + url.search,
        { method: "GET", headers: request.headers }));
    }
    return result({ error: "not_found", from:"worker", path:url.pathname }, 404);
  },
};
