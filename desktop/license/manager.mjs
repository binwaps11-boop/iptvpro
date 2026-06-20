#!/usr/bin/env node
/*
 * تطبيق إدارة الاشتراكات المنفصل (لصاحب الخدمة فقط).
 * واجهة ويب لتوليد سيريالات الاشتراك للعملاء وحفظ سجلّ بها.
 *
 * التشغيل:  node license/manager.mjs    ثم افتح  http://localhost:8899
 * يتطلب: license/private.pem  (أنشئه عبر setup-keys.mjs)
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateSerial } from './keygen.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PRIV_PATH = path.join(__dirname, 'private.pem');
const ISSUED_PATH = path.join(__dirname, 'issued.json');
const PORT = process.env.MANAGER_PORT || 8899;

if (!fs.existsSync(PRIV_PATH)) {
  console.error('✗ المفتاح الخاص غير موجود. شغّل أولاً:  node license/setup-keys.mjs');
  process.exit(1);
}
const PRIV = fs.readFileSync(PRIV_PATH, 'utf8');

const loadIssued = () => {
  try {
    return JSON.parse(fs.readFileSync(ISSUED_PATH, 'utf8'));
  } catch {
    return [];
  }
};
const saveIssued = (a) => fs.writeFileSync(ISSUED_PATH, JSON.stringify(a, null, 2));

const PAGE = `<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>إدارة الاشتراكات</title>
<style>
 body{font-family:Tahoma,system-ui;background:#0b1020;color:#e8eefc;margin:0;padding:24px}
 .wrap{max-width:780px;margin:auto}
 h1{font-size:22px}.muted{color:#8aa0c8}
 .card{background:#16203f;border:1px solid #243153;border-radius:14px;padding:18px;margin-bottom:16px}
 label{display:block;font-size:13px;margin:8px 0 4px;color:#aab8d8}
 input,select{width:100%;padding:10px;border-radius:10px;border:1px solid #243153;background:#0d1430;color:#fff;box-sizing:border-box}
 .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}
 button{margin-top:14px;width:100%;padding:12px;border:none;border-radius:10px;background:#3b82f6;color:#fff;font-weight:700;cursor:pointer}
 .serial{font-family:monospace;background:#0d1430;border:1px solid #3b82f6;border-radius:10px;padding:12px;word-break:break-all;margin-top:10px}
 table{width:100%;border-collapse:collapse;font-size:13px}td,th{border-bottom:1px solid #243153;padding:8px;text-align:right}
 .copy{background:#22d3ee;color:#003;margin-top:8px}
</style></head><body><div class="wrap">
 <h1>🔑 إدارة اشتراكات IPTV Pro</h1>
 <p class="muted">ولّد سيريالاً للعميل، ثم أرسله له ليُدخله في خانة «التفعيل» داخل التطبيق.</p>
 <div class="card">
   <label>اسم العميل</label><input id="customer" placeholder="مثال: أحمد علي">
   <div class="row">
     <div><label>المدة (أيام)</label><input id="days" type="number" value="30"></div>
     <div><label>حد الأجهزة (0 = بلا حد)</label><input id="devices" type="number" value="1000"></div>
   </div>
   <label>الباقة</label>
   <select id="plan"><option value="standard">قياسي</option><option value="gold">ذهبي</option><option value="vip">VIP</option></select>
   <button onclick="gen()">توليد السيريال</button>
   <div id="out"></div>
 </div>
 <div class="card"><h3>السيريالات المُصدَرة</h3><div id="list">…</div></div>
</div>
<script>
async function gen(){
  const body={customer:customer.value,days:+days.value,devices:+devices.value,plan:plan.value};
  const r=await fetch('/gen',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}).then(x=>x.json());
  out.innerHTML='<div class="serial" id="s">'+r.serial+'</div><button class="copy" onclick="navigator.clipboard.writeText(document.getElementById(\\'s\\').textContent)">نسخ</button>';
  load();
}
async function load(){
  const a=await fetch('/issued').then(x=>x.json());
  list.innerHTML=a.length?'<table><tr><th>العميل</th><th>الباقة</th><th>أجهزة</th><th>ينتهي</th></tr>'+
    a.reverse().map(i=>'<tr><td>'+i.customer+'</td><td>'+i.plan+'</td><td>'+(i.maxDevices||'∞')+'</td><td>'+(i.exp?new Date(i.exp).toLocaleDateString('ar'):'دائم')+'</td></tr>').join('')+'</table>':'<span class="muted">لا يوجد بعد</span>';
}
load();
</script></body></html>`;

http.createServer(async (req, res) => {
  if (req.url === '/' ) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(PAGE);
  }
  if (req.url === '/issued') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify(loadIssued()));
  }
  if (req.url === '/gen' && req.method === 'POST') {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const b = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
    const days = Number(b.days || 30);
    const data = {
      id: Math.random().toString(36).slice(2, 10),
      customer: b.customer || 'عميل',
      plan: b.plan || 'standard',
      maxDevices: Number(b.devices || 0),
      iat: Date.now(),
      exp: days > 0 ? Date.now() + days * 86400000 : 0,
    };
    const serial = generateSerial(data, PRIV);
    const issued = loadIssued();
    issued.push({ ...data, serial });
    saveIssued(issued);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ serial, data }));
  }
  res.writeHead(404);
  res.end();
}).listen(PORT, () => {
  console.log(`\n  🔑 تطبيق إدارة الاشتراكات يعمل على:  http://localhost:${PORT}\n`);
});
