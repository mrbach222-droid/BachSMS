import assert from "node:assert/strict";
import { Script } from "node:vm";
import browserPage from "../src/page.js";

const page=browserPage("a".repeat(32));
const home=browserPage("",true);
assert(page.includes('const roomFromPage="a'.slice(0,24)), "Room marker should be substituted");
assert(!page.includes("ROOM_PLACEHOLDER"), "No raw room placeholder");
assert(home.includes("Thiết bị riêng của bạn"), "Private device homepage missing");
assert(page.includes("Nhận từ iPhone") && page.includes("Gửi từ PC"),"Two-way file UI missing");
assert(page.includes("chưa kiểm toán bảo mật"), "Unverified security warning missing");
assert(page.includes("AES-256-GCM"), "AES-GCM UI missing");
assert(page.includes("crypto.subtle.encrypt"), "Browser encryption missing");
assert(page.includes("crypto.subtle.decrypt"), "Browser decryption missing");
assert(page.includes("crypto.subtle.deriveBits"), "ECDH+HKDF key derivation missing");
assert(!page.includes('input id="code"'),"Code input must be removed");
assert(page.includes('id="pair"'),"Private connect button missing");
assert(!page.includes("/api/auto-connect"),"Global auto-connect must not be used by browser");
assert(page.includes("/api/device/connect"),"Per-device authenticated resolution missing");
assert(page.includes('id="devicesList"') && page.includes('id="privateLink"'),
       "Device list and private-link import missing");
assert(page.includes('id="privateLink" type="password"'),
       "Private credential should be masked in manual join field");
assert(page.includes("navigator.clipboard.readText()") && page.includes('id="pasteDevice"'),
       "Secure clipboard onboarding should not display raw device URL");
assert(!page.includes('id="privateLink" type="text"'),
       "Never expose sensitive private link as a visible text input");
assert(page.includes("localStorage") && page.includes("validPrivateLink"),
       "PC must persist authorized devices only");
assert(page.includes("history.replaceState"),"Secret fragment must be removed from the address bar");
assert(page.includes("personalKeyPair(currentDeviceId)") && page.includes("indexedDB"),
       "Personal ECDH private key must persist inside browser-only IndexedDB");
assert(page.includes('"trust-proof"') && page.includes('"trust-probe"'),
       "Trusted PC must cryptographically respond to a fresh iPhone challenge");
assert(page.includes("connectDevice(chosen)") && page.includes("preferredDevice()"),
       "Preferred personal iPhone should auto-connect when browser home opens");
assert(page.includes("setInterval") && page.includes("20000"),
       "Auto-retry offline iPhones without copying link again");
assert(page.includes("Chấp nhận"),"Phone approval message missing");
assert(page.includes('id="received"'),"Received file list missing");
assert(page.includes('className="thumb"'),"Preview thumbnails missing");
assert(page.includes('onloadedmetadata'),"Video duration missing");
const script=page.match(/<script>([\s\S]*?)<\/script>/);
assert(script, "Expected browser script");
new Script(script[1],{filename:"browser.js"});
assert(!page.includes("tối đa 50 MB"),"Old 50 MB cap must be removed");
assert(page.includes("Chọn thư mục để nhận file lớn"),"Large downloads require a streaming save folder");
assert(page.includes("showDirectoryPicker"),"Streaming file-save directory picker missing");
assert(page.includes("createWritable"),"Browser must write received data to disk");
assert(page.includes("file-progress"),"Bounded chunk-ACK protocol missing");
assert(page.includes("PROGRESS_WINDOW=16"),"Window backpressure missing");
assert(page.includes("IN_MEMORY_FALLBACK"),"RAM guard missing");
assert(page.includes('id="speedMode"'),"Turbo mode selector missing");
assert(page.includes('targetWindow'),"Adaptive sender window missing");
assert(page.includes('MB/s'),"Realtime throughput display missing");
assert(page.includes('id="clear"') && page.includes('id="clearReceived"'),"One-tap cleanup controls missing");
assert(page.includes('15*60*1000'),"Browser auto-purge missing");
assert(page.includes('revokePreviewURLs()'),"Preview URL cleanup missing");
console.log("PASS B Send v0.6.2 preferred-PC auto-connect, IndexedDB trust keys, challenge proof, hidden link, Turbo");
