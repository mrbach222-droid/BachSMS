// Bách CRM -> Bách SMS Cloudflare relay 1.0.0. No third-party dependencies.
const LIMIT = 40;
const TTL = 24 * 60 * 60;
const encoder = new TextEncoder();
class HttpError extends Error { constructor(status, message) { super(message); this.status = status; } }
const fail = (status, message) => { throw new HttpError(status, message); };
const json = (data, status = 200) => new Response(JSON.stringify(data), {status, headers: {
  "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer"
}});
const hash = async value => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))), b => b.toString(16).padStart(2,"0")).join("");
const random = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2,"0")).join("");
const id = value => typeof value === "string" && /^[A-Za-z0-9_-]{8,100}$/.test(value);
const token = request => (request.headers.get("Authorization") || "").replace(/^Bearer /, "");
function text(value, max, required = false) {
  if (value == null && !required) return "";
  if (typeof value !== "string" || value.length > max || (required && !value.trim())) fail(400,"Trường dữ liệu chưa hợp lệ.");
  return value.trim();
}
async function body(request) {
  if (!request.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) fail(415,"Cần dữ liệu JSON.");
  if (Number(request.headers.get("Content-Length") || 0) > 150000) fail(413,"Gói dữ liệu quá lớn.");
  const reader = request.body?.getReader(); let length = 0, chunks = [];
  if (!reader) fail(400,"Thiếu dữ liệu.");
  while (true) { const {done,value} = await reader.read(); if (done) break; length += value.length;
    if (length > 150000) { await reader.cancel(); fail(413,"Gói dữ liệu quá lớn."); } chunks.push(value); }
  const bytes = new Uint8Array(length);let pos=0;for(const c of chunks){bytes.set(c,pos);pos+=c.length;}
  try { const value = JSON.parse(new TextDecoder().decode(bytes)); if(!value||Array.isArray(value)||typeof value!=="object")throw Error();return value; }
  catch { fail(400,"JSON chưa hợp lệ."); }
}
async function authorize(request, env, role) {
  const raw = token(request); if (!/^[wr]_[a-f0-9]{64}$/.test(raw)) fail(401,"Khóa kết nối chưa đúng.");
  const field = role === "writer" ? "writer_hash" : "reader_hash";
  const row = await env.DB.prepare(`SELECT id,label FROM channels WHERE ${field}=?`).bind(await hash(raw)).first();
  if (!row) fail(401,"Khóa kết nối chưa đúng hoặc đã bị thu hồi.");return row;
}
function cleanJob(raw, now) {
  if(!raw||typeof raw!=="object"||!id(raw.id))fail(400,"Mã khách chưa hợp lệ.");
  const phone=text(raw.phone,30,true).replace(/[\s().+-]/g,"").replace(/^84/,"0");
  if(!/^0[35789]\d{8}$/.test(phone))fail(400,"Số di động Việt Nam chưa hợp lệ.");
  const date = new Date(raw.created_at || now * 1000);if(!Number.isFinite(date.getTime()))fail(400,"Ngày tạo chưa hợp lệ.");
  return {id:raw.id,cif:text(raw.cif,100,true),contract_number:text(raw.contract_number,1000),
    customer_name:text(raw.customer_name,200,true),phone,message:text(raw.message,2000),revision:1,
    created_at:date.toISOString().replace(/\.\d{3}Z$/,"Z")};
}
async function handle(request, env) {
  const url = new URL(request.url), path = url.pathname.replace(/\/$/,"") || "/";
  if (url.protocol !== "https:" && url.hostname !== "localhost" && url.hostname !== "127.0.0.1")fail(400,"Kết nối Cloudflare cần HTTPS.");
  if(!env.DB)fail(503,"Chưa cấu hình D1 binding tên DB.");
  if(request.method==="GET"&&(path==="/"||path==="/health")){
    try{await env.DB.prepare("SELECT id FROM channels LIMIT 1").first();}catch{fail(503,"Chưa chạy schema.sql trong D1.");}
    return json({service:"BachCRM-BachSMS",version:"1.0.0",ready:true});
  }
  const now = Math.floor(Date.now()/1000);
  if(request.method==="POST"&&path==="/api/v1/channels"){
    if(typeof env.ADMIN_KEY!=="string"||env.ADMIN_KEY.length<32)fail(503,"Chưa đặt secret ADMIN_KEY dài tối thiểu 32 ký tự.");
    if(await hash(token(request))!==await hash(env.ADMIN_KEY))fail(401,"Khóa quản trị chưa đúng.");
    const data=await body(request), channel=crypto.randomUUID(), writer="w_"+random(), reader="r_"+random();
    const label=text(data.label,100,true);
    await env.DB.prepare("INSERT INTO channels(id,label,writer_hash,reader_hash,created_at) VALUES(?,?,?,?,?)")
      .bind(channel,label,await hash(writer),await hash(reader),now).run();
    const pairing={url:url.origin,channel,token:reader};
    const code="bachsms1."+btoa(JSON.stringify(pairing)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
    return json({channel,label,writer_token:writer,pair_code:code},201);
  }
  if(path==="/api/v1/batches"&&request.method==="POST"){
    const channel=await authorize(request,env,"writer"), data=await body(request);
    if(!id(data.id)||!Array.isArray(data.jobs)||data.jobs.length<1||data.jobs.length>LIMIT)fail(400,"Mỗi gói cần từ 1 đến 40 khách.");
    const jobs=data.jobs.map(j=>cleanJob(j,now));if(new Set(jobs.map(j=>j.id)).size!==jobs.length)fail(400,"Trùng mã khách trong gói.");
    const digest=await hash(JSON.stringify(jobs));
    const previous=await env.DB.prepare("SELECT digest FROM batches WHERE channel=? AND id=?").bind(channel.id,data.id).first();
    if(previous){if(previous.digest!==digest)fail(409,"Mã gói đã được dùng cho dữ liệu khác.");return json({id:data.id,accepted:jobs.length,duplicate:true});}
    const statements=[env.DB.prepare("INSERT OR IGNORE INTO batches(channel,id,digest,created_at) VALUES(?,?,?,?)").bind(channel.id,data.id,digest,now)];
    for(const job of jobs){const serialized=JSON.stringify(job), jd=await hash(serialized);
      statements.push(env.DB.prepare("INSERT OR IGNORE INTO jobs(channel,id,batch_id,digest,payload,created_at,expires_at) SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM batches WHERE channel=? AND id=? AND digest=?)")
        .bind(channel.id,job.id,data.id,jd,serialized,now,now+TTL,channel.id,data.id,digest));}
    await env.DB.batch(statements);
    const saved=await env.DB.prepare("SELECT digest FROM batches WHERE channel=? AND id=?").bind(channel.id,data.id).first();
    if(saved?.digest!==digest)fail(409,"Mã gói bị xung đột; dữ liệu này chưa được giao.");
    return json({id:data.id,accepted:jobs.length,duplicate:false},201);
  }
  if(path==="/api/v1/jobs"&&request.method==="GET"){
    const channel=await authorize(request,env,"reader");
    const rows=await env.DB.prepare("SELECT payload FROM jobs WHERE channel=? AND received_at IS NULL AND payload IS NOT NULL AND expires_at>? ORDER BY created_at,id LIMIT 40").bind(channel.id,now).all();
    return json({jobs:rows.results.map(r=>JSON.parse(r.payload)),cursor:null});
  }
  if(path==="/api/v1/received"&&request.method==="POST"){
    const channel=await authorize(request,env,"reader"), data=await body(request);
    if(!Array.isArray(data.job_ids)||data.job_ids.length<1||data.job_ids.length>LIMIT||!data.job_ids.every(id))fail(400,"Danh sách xác nhận chưa hợp lệ.");
    const keys=[...new Set(data.job_ids)],placeholders=keys.map(()=>"?").join(",");
    await env.DB.prepare(`UPDATE jobs SET payload=NULL,received_at=COALESCE(received_at,?),status=CASE WHEN status='pending' THEN 'received' ELSE status END WHERE channel=? AND id IN (${placeholders})`).bind(now,channel.id,...keys).run();
    return json({received_ids:keys});
  }
  if(path==="/api/v1/statuses"&&request.method==="POST"){
    const channel=await authorize(request,env,"reader"), data=await body(request);
    if(!Array.isArray(data.events)||data.events.length<1||data.events.length>20)fail(400,"Mỗi lần đồng bộ tối đa 20 trạng thái.");
    const accepted=[],statements=[];
    for(const event of data.events){
      if(!id(event.id)||!id(event.job_id)||!["confirmed_sent","skipped","failed"].includes(event.status))fail(400,"Trạng thái chưa hợp lệ.");
      const date=new Date(event.occurred_at);if(!Number.isFinite(date.getTime()))fail(400,"Thời gian trạng thái chưa hợp lệ.");
      accepted.push(event.id);
      statements.push(env.DB.prepare("INSERT OR IGNORE INTO events(channel,id,job_id,status,occurred_at,created_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE channel=? AND id=?)").bind(channel.id,event.id,event.job_id,event.status,date.toISOString(),now,channel.id,event.job_id));
      statements.push(env.DB.prepare("UPDATE jobs SET status=CASE WHEN status='confirmed_sent' THEN status ELSE ? END WHERE channel=? AND id=?").bind(event.status,channel.id,event.job_id));
    }
    await env.DB.batch(statements);return json({accepted_ids:accepted});
  }
  if(path==="/api/v1/summary"&&request.method==="GET"){
    const channel=await authorize(request,env,"writer");
    const rows=await env.DB.prepare("SELECT status,COUNT(*) AS count FROM jobs WHERE channel=? GROUP BY status").bind(channel.id).all();return json({channel:channel.id,counts:rows.results});
  }
  if(path==="/api/v1/channel"&&request.method==="DELETE"){
    const channel=await authorize(request,env,"writer");
    await env.DB.batch([env.DB.prepare("DELETE FROM events WHERE channel=?").bind(channel.id),env.DB.prepare("DELETE FROM jobs WHERE channel=?").bind(channel.id),env.DB.prepare("DELETE FROM batches WHERE channel=?").bind(channel.id),env.DB.prepare("DELETE FROM channels WHERE id=?").bind(channel.id)]);
    return json({revoked:true});
  }
  fail(404,"Không có chức năng này.");
}
export default {
  async fetch(request,env){try{return await handle(request,env);}catch(error){return json({error:error instanceof HttpError?error.message:"Dịch vụ chưa sẵn sàng. Kiểm tra D1 và cấu hình Worker."},error.status||503);}},
  async scheduled(_event,env){const now=Math.floor(Date.now()/1000);await env.DB.batch([
    env.DB.prepare("UPDATE jobs SET payload=NULL,status=CASE WHEN status='pending' THEN 'expired' ELSE status END WHERE payload IS NOT NULL AND expires_at<=?").bind(now),
    env.DB.prepare("DELETE FROM events WHERE created_at<?").bind(now-30*86400),
    env.DB.prepare("DELETE FROM jobs WHERE created_at<?").bind(now-30*86400),
    env.DB.prepare("DELETE FROM batches WHERE created_at<?").bind(now-30*86400)
  ]);}
};
