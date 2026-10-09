import { DurableObject } from "cloudflare:workers";
import browserPage from "./page.js";

// B Send v0.4 technical preview: WSS with ephemeral rooms.
// TLS transport only. End-to-end encryption is not implemented yet.
// Do not use this preview for confidential or company data.
const TTL = 60 * 60 * 1000;
const TOKEN_PATTERN = /^[a-f0-9]{64}$/;
const ROOM_PATTERN = /^[a-f0-9]{32}$/;
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
      if (frame.type !== "enc" || typeof frame.blob !== "string" ||
          frame.blob.length < 40 || frame.blob.length > 4000 ||
          !/^[A-Za-z0-9+/=]+$/.test(frame.blob)) return;
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
      return new Response("B Send relay deployed. Open a pairing link issued by the iPhone.", {
        headers: { "content-type": "text/plain;charset=utf-8", "cache-control": "no-store" },
      });
    if (url.pathname === "/api/health" && request.method === "GET")
      return result({ status: "ready", version: "0.4-preview", transport: "wss" });
    if (url.pathname === "/api/session" && request.method === "POST") {
      const room = nonce(16), ownerToken = nonce(32), guestToken = nonce(32);
      const obj = env.SESSIONS.get(env.SESSIONS.idFromName(room));
      const create = await obj.fetch(new Request("https://internal.room/init", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ ownerToken, guestToken }),
      }));
      if (!create.ok) return result({ error: "create_failed" }, 502);
      const data = await create.json();
      return result({
        room, expiresAt: data.expiresAt,
        ownerWebSocketURL: "wss://" + url.host + "/api/room/" + room +
          "/ws?role=owner&token=" + ownerToken,
        guestURL: url.origin + "/s/" + room + "#" + guestToken,
      }, 201);
    }
    const page = url.pathname.match(/^\/s\/([a-f0-9]{32})$/);
    if (page && request.method === "GET") {
      return new Response(browserPage(page[1]), {
        headers: {
          "content-type": "text/html;charset=utf-8",
          "cache-control": "no-store", "x-content-type-options": "nosniff",
          "referrer-policy": "no-referrer",
          "content-security-policy": "default-src 'none';base-uri 'none';frame-ancestors 'none';" +
            "script-src 'unsafe-inline';style-src 'unsafe-inline';connect-src 'self' wss:;img-src 'self' data:",
        },
      });
    }
    const socket = url.pathname.match(/^\/api\/room\/([a-f0-9]{32})\/ws$/);
    if (socket && request.method === "GET") {
      const obj = env.SESSIONS.get(env.SESSIONS.idFromName(socket[1]));
      return obj.fetch(new Request("https://internal.room/ws" + url.search,
        { method: "GET", headers: request.headers }));
    }
    return result({ error: "not_found" }, 404);
  },
};
