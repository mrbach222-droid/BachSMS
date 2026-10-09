import assert from "node:assert/strict";
import {createHash,randomBytes} from "node:crypto";
import {BSendSHA256} from "../src/sha256.js";
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
