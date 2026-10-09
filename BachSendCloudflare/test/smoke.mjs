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
assert(page.includes("không cần chọn thư mục"),"Safari must not require a folder picker before receiving");
assert(page.includes("showDirectoryPicker"),"Streaming file-save directory picker missing");
assert(page.includes("createWritable"),"Browser must write received data to disk");
assert(page.includes("file-progress"),"Bounded chunk-ACK protocol missing");
assert(page.includes("PROGRESS_WINDOW=16"),"Window backpressure missing");
assert(page.includes("RECEIVE_MEMORY_LIMIT") && page.includes("mobileBrowser?384:512"),
       "Mobile Safari must accept ~148 MB while bounding in-browser memory");
assert(page.includes('id="speedMode"'),"Turbo mode selector missing");
assert(page.includes('targetWindow'),"Adaptive sender window missing");
assert(page.includes('MB/s'),"Realtime throughput display missing");
assert(page.includes('id="clear"') && page.includes('id="clearReceived"'),"One-tap cleanup controls missing");
assert(page.includes('15*60*1000'),"Browser auto-purge missing");
assert(page.includes('id="incomingRow"') && page.includes("updateIncomingView(incoming)"),
       "Receiver must show incoming progress automatically");
assert(page.includes('id="desktopFolder"') && page.includes("canDirectorySave"),
       "Directory chooser should be optional and hidden on mobile browsers");
assert(page.includes('id="folder"') && page.includes('id="clearReceived"'),
       "Optional desktop streaming and received cleanup must remain available");
assert(page.includes('Lưu vào Tệp / Chia sẻ') &&
       page.includes('a.textContent=mobileBrowser?"⬇":"⬇ Tải xuống"') &&
       page.includes('menu.className="filemenu"'),
       "Compact Safari files must retain download and share/save menu controls");
assert(page.includes("previewURLs=new Set(),receivedURLs=new Set()"),
       "Received download URLs should not be revoked by outgoing file preview changes");
assert(page.includes("clearButton.onclick=clearOutgoing") &&
       page.includes("clearReceived.onclick=clearOnlyReceived"),
       "Clear-send and clear-received operations must not affect the other list");
assert(!page.includes('reason:"select-directory"'),
       "Safari receiving must not reject >128 MB files demanding a directory picker");
assert(page.includes('revokePreviewURLs()'),"Preview URL cleanup missing");
assert(page.includes('id="receivedSearch"') && page.includes("compactLists()"),"Compact list search, collapse and expand controls missing");
assert(page.includes("thumb{width:42px") && page.includes("listtools"),"Compact file thumbnail and list layout missing");
assert(page.includes("class BSendSHA256"),"Pure JS SHA-256 implementation must be embedded into browser");
assert(!page.includes("BSEND_SHA256_IMPL_PLACEHOLDER"),"No uncompiled SHA-256 source marker");
assert(page.includes('type:"file-ready"') && page.includes("fileReady.set("),
       "Receiver must advertise offsets and sender must listen for checkpoint");
assert(page.includes("incoming.expectedSHA===expectedSHA") && page.includes("incoming.got"),
       "Resume only identical file id/size/digest and in-room context");
assert(page.includes('reason:"sha256-mismatch"') && page.includes("receivedSHA"),
       "Hash mismatch must reject bytes and never expose the file");
assert(page.includes("pendingOutgoingFiles") && page.includes("resumeQueuedBrowserUpload"),
       "Browser sender must retry its queued file after reconnect");
assert(page.includes("updateIncomingView(incoming)") && page.includes('a.textContent="⬇ Tải xuống"'),
       "Safari direct receive must remain available");
console.log("PASS B Send v0.6.5 Compact List, Safari download/share, Smart Resume, SHA-256 and Personal Quick Connect");
