// Streaming SHA-256 used by B Send browser send/receive.
// Pure ECMAScript with constant memory; also embedded in browser HTML via
// BSendSHA256.toString() so Cloudflare has no external CDN dependency.
export class BSendSHA256 {
  static K = new Uint32Array([
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
  ]);
  constructor() {
    this.h = new Uint32Array([0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
       0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]);
    this.buffer = new Uint8Array(64);
    this.used = 0;
    this.bytes = 0;
    this.finished = false;
  }
  block(data,start) {
    const w=new Uint32Array(64);
    for(let i=0;i<16;i++){
      const j=start+i*4;
      w[i]=((data[j]<<24)|(data[j+1]<<16)|(data[j+2]<<8)|data[j+3])>>>0;
    }
    const rr=(v,n)=>(v>>>n)|(v<<(32-n));
    for(let i=16;i<64;i++){
      const x=w[i-15],y=w[i-2];
      const s0=rr(x,7)^rr(x,18)^(x>>>3);
      const s1=rr(y,17)^rr(y,19)^(y>>>10);
      w[i]=(w[i-16]+s0+w[i-7]+s1)>>>0;
    }
    let [a,b,c,d,e,f,g,h]=this.h;
    for(let i=0;i<64;i++){
      const s1=rr(e,6)^rr(e,11)^rr(e,25);
      const ch=(e&f)^(~e&g);
      const t1=(h+s1+ch+this.constructor.K[i]+w[i])>>>0;
      const s0=rr(a,2)^rr(a,13)^rr(a,22);
      const maj=(a&b)^(a&c)^(b&c);
      const t2=(s0+maj)>>>0;
      h=g;g=f;f=e;e=(d+t1)>>>0;d=c;c=b;b=a;a=(t1+t2)>>>0;
    }
    const result=[a,b,c,d,e,f,g,h];
    for(let i=0;i<8;i++)this.h[i]=(this.h[i]+result[i])>>>0;
  }
  update(input){
    if(this.finished)throw Error("SHA-256 already finalized");
    const data=input instanceof Uint8Array?input:new Uint8Array(input);
    this.bytes+=data.length;
    if(!Number.isSafeInteger(this.bytes))throw Error("SHA-256 file too large");
    let p=0;
    if(this.used){
      const copy=Math.min(64-this.used,data.length);
      this.buffer.set(data.subarray(0,copy),this.used);
      this.used+=copy;p+=copy;
      if(this.used===64){this.block(this.buffer,0);this.used=0;}
    }
    while(p+64<=data.length){this.block(data,p);p+=64;}
    if(p<data.length){
      this.buffer.set(data.subarray(p),0);
      this.used=data.length-p;
    }
    return this;
  }
  hex(){
    if(this.finished)throw Error("SHA-256 already finalized");
    const bits=this.bytes*8;
    const padLength=this.used<56?56-this.used:120-this.used;
    const pad=new Uint8Array(padLength+8);
    pad[0]=0x80;
    const high=Math.floor(bits/0x100000000),low=bits>>>0;
    pad[padLength]=(high>>>24)&255;
    pad[padLength+1]=(high>>>16)&255;
    pad[padLength+2]=(high>>>8)&255;
    pad[padLength+3]=high&255;
    pad[padLength+4]=(low>>>24)&255;
    pad[padLength+5]=(low>>>16)&255;
    pad[padLength+6]=(low>>>8)&255;
    pad[padLength+7]=low&255;
    this.update(pad);
    this.finished=true;
    return Array.from(this.h,n=>n.toString(16).padStart(8,"0")).join("");
  }
}
