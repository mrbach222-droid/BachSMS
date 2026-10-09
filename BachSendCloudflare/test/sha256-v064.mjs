import assert from "node:assert/strict";
import {createHash,randomBytes} from "node:crypto";
import {BSendSHA256} from "../src/sha256.js";
import browserPage from "../src/page.js";
import {runInNewContext} from "node:vm";
const cases=[
 Buffer.from(""),Buffer.from("abc"),Buffer.from("Hello, B Send v0.6.4!"),
 Buffer.alloc(1000000,0x61),randomBytes(48*1024+137),randomBytes(4*1024*1024+77)
];
for(const buf of cases){
 const expected=createHash("sha256").update(buf).digest("hex");
 for(const n of [1,7,64,4096,48*1024,1024*1024]){
  const dig=new BSendSHA256();
  for(let i=0;i<buf.length;i+=n)dig.update(buf.subarray(i,i+n));
  assert.equal(dig.hex(),expected,"SHA-256 vector mismatch "+buf.length+" / "+n);
 }
}
console.log("PASS SHA-256 NIST empty/abc/million-a + 4MB random streaming in six chunk sizes");

// Wrangler/minifiers may rename the imported class. The HTML must provide
// a stable identifier to the browser even if its constructor is "class a".
const minifiedClass=BSendSHA256.toString().replace("class BSendSHA256","class a");
const simulatedResult=runInNewContext(
 "const BSendSHA256 = ("+minifiedClass+"); new BSendSHA256().update(new Uint8Array([97,98,99])).hex()",
 {Uint32Array,Uint8Array,Array,Number,Math,Error});
assert.equal(simulatedResult,createHash("sha256").update("abc").digest("hex"));
const html=browserPage("");
const rendered=html.match(/<script>([\s\S]*?)<\/script>/)?.[1]||"";
const prelude=rendered.split("(async function(){")[0];
assert(prelude.includes("const BSendSHA256 = ("));
const runtimeResult=runInNewContext(prelude+
  "\nnew BSendSHA256().update(new Uint8Array([97,98,99])).hex()",
  {Uint32Array,Uint8Array,Array,Number,Math,Error});
assert.equal(runtimeResult,createHash("sha256").update("abc").digest("hex"));
console.log("PASS SHA-256 browser-bundled class binding survives minified constructor names");
