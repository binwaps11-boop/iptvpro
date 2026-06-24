'use strict';
const API='/cgi-bin/kt412';
let TOKEN = sessionStorage.getItem('kt412tok') || '';
let timer=null, trafPrev=null;

const $=s=>document.querySelector(s);
const $$=s=>document.querySelectorAll(s);
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

function toast(msg, ok){
  const t=$('#toast'); t.textContent=msg; t.className='show '+(ok===false?'bad':(ok?'ok':''));
  clearTimeout(t._t); t._t=setTimeout(()=>t.className='', 3200);
}
async function call(params, post){
  const usp=new URLSearchParams(params);
  if(TOKEN) usp.set('token', TOKEN);
  let r;
  try{
    if(post) r=await fetch(API,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:usp.toString()});
    else r=await fetch(API+'?'+usp.toString());
  }catch(e){ return {ok:false,error:'network'}; }
  let j; try{ j=await r.json(); }catch(e){ return {ok:false,error:'parse'}; }
  if(j && j.ok===false && j.error==='unauthorized'){ logout(); }
  return j;
}

/* ---------- auth ---------- */
async function doLogin(){
  const btn=$('#loginBtn'); btn.innerHTML='<span class="spin"></span>'; btn.disabled=true;
  const r=await call({op:'login', password:$('#pw').value}, true);
  btn.innerHTML='دخول'; btn.disabled=false;
  if(r.ok && r.token){
    TOKEN=r.token; sessionStorage.setItem('kt412tok', TOKEN);
    showApp();
  }else{
    const m=$('#loginMsg'); m.classList.remove('hide');
    m.textContent = r.error==='bad_password' ? 'كلمة المرور غير صحيحة.' : 'تعذّر تسجيل الدخول: '+(r.error||'خطأ');
  }
}
function logout(){
  TOKEN=''; sessionStorage.removeItem('kt412tok');
  if(timer) clearInterval(timer);
  $('#app').classList.add('hide'); $('#login').classList.remove('hide'); $('#pw').value='';
}
function showApp(){
  $('#login').classList.add('hide'); $('#app').classList.remove('hide');
  switchTab('dash'); startLoop();
}

/* ---------- helpers ---------- */
function human(b){ b=+b||0; const u=['B','KB','MB','GB','TB']; let i=0; while(b>=1024&&i<u.length-1){b/=1024;i++;} return b.toFixed(b<10&&i>0?1:0)+' '+u[i]; }
function dur(s){ s=+s||0; const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);
  if(d>0) return d+'ي '+h+'س'; if(h>0) return h+'س '+m+'د'; return m+'د'; }

/* ---------- dashboard ---------- */
async function loadDash(){
  const s=await call({op:'summary'});
  if(s && s.ok){
    $('#d_model').textContent=s.model||'KT412';
    $('#d_rel').textContent=s.release||'';
    $('#d_up').textContent=dur(s.uptime);
    $('#d_load').textContent='الحِمل: '+((+s.load/65536)||0).toFixed(2);
    const used=(+s.mem_total)-(+s.mem_free)-(+s.mem_buf);
    const pct=s.mem_total>0?Math.round(used/s.mem_total*100):0;
    $('#d_mem').innerHTML=pct+'<small>%</small>';
    $('#d_membar').style.width=pct+'%';
    $('#d_memsub').textContent=human(used)+' / '+human(s.mem_total);
  }
  const w=await call({op:'wan'});
  if(w && w.ok){
    const up=w.up===true||w.up==='true';
    $('#d_wan').innerHTML = up?'<span style="color:var(--ok)">متصل</span>':'<span style="color:var(--bad)">منقطع</span>';
    $('#d_wanip').textContent=(w.ip||'—')+' · '+(w.proto||'');
    $('#netDot').className='dot '+(up?'on':'off');
    $('#netTxt').textContent=up?'متصل':'منقطع';
  }
  const wi=await call({op:'wifi'});
  if(wi && wi.ok){
    $('#d_wifi').innerHTML = (wi.radios||[]).map(r=>
      `<div class="kv"><span class="k">${esc(r.essid||'—')} <span class="badge ok">${esc(r.band)}</span></span>`+
      `<span class="v">${r.txpower} dBm · ${r.clients} جهاز</span></div>`).join('') || '<div class="sub">لا توجد شبكات نشطة</div>';
  }
  const h=await call({op:'health'});
  if(h && h.ok){
    const row=(n,o)=>{const good=(+o.loss)<100;return `<div class="kv"><span class="k">${n}</span><span class="v">`+
      (good?`<span class="badge ok">${o.rtt} ms</span>`:`<span class="badge bad">منقطع</span>`)+`</span></div>`;};
    $('#d_health').innerHTML=row('Cloudflare',h.cf)+row('Google',h.goog)+
      `<div class="kv"><span class="k">Multi‑WAN online</span><span class="v">${h.mwan_online}</span></div>`;
  }
}

/* ---------- WAN ---------- */
let wanMode='dhcp';
function wanFormHtml(m){
  if(m==='pppoe') return `<label class="f">اسم المستخدم</label><input id="w_user" class="t">
    <label class="f">كلمة المرور</label><input id="w_pass" class="t" type="text">`;
  if(m==='static') return `<div class="row"><div><label class="f">IP</label><input id="w_ip" class="t" placeholder="192.168.1.2"></div>
    <div><label class="f">Netmask</label><input id="w_mask" class="t" placeholder="255.255.255.0"></div></div>
    <div class="row"><div><label class="f">Gateway</label><input id="w_gw" class="t" placeholder="192.168.1.1"></div>
    <div><label class="f">DNS</label><input id="w_dns" class="t" placeholder="1.1.1.1"></div></div>`;
  return `<div class="sub" style="margin-top:10px">سيحصل الراوتر على عنوان تلقائياً من مزوّد الخدمة.</div>`;
}
async function loadWan(){
  const w=await call({op:'wan'});
  if(w && w.ok){
    const up=w.up===true||w.up==='true';
    $('#wanStatus').innerHTML=
      `<div class="kv"><span class="k">الحالة</span><span class="v">${up?'<span class="badge ok">متصل</span>':'<span class="badge bad">منقطع</span>'}</span></div>`+
      `<div class="kv"><span class="k">النوع</span><span class="v">${esc(w.proto||'—')}</span></div>`+
      `<div class="kv"><span class="k">عنوان IP</span><span class="v">${esc(w.ip||'—')}</span></div>`+
      `<div class="kv"><span class="k">البوابة</span><span class="v">${esc(w.gateway||'—')}</span></div>`+
      `<div class="kv"><span class="k">DNS</span><span class="v">${esc(w.dns||'—')}</span></div>`+
      `<div class="kv"><span class="k">مدة الاتصال</span><span class="v">${dur(w.uptime)}</span></div>`;
    wanMode=(w.proto==='pppoe'||w.proto==='static')?w.proto:'dhcp';
    $$('#wanSeg button').forEach(b=>b.classList.toggle('active', b.dataset.m===wanMode));
    $('#wanForm').innerHTML=wanFormHtml(wanMode);
  }
}
async function applyWan(){
  let p={act:'wan_'+wanMode};
  if(wanMode==='pppoe'){ p.user=$('#w_user').value; p.pass=$('#w_pass').value; }
  if(wanMode==='static'){ p.ip=$('#w_ip').value; p.mask=$('#w_mask').value; p.gw=$('#w_gw').value; p.dns=$('#w_dns').value; }
  const r=await call(p,true); toast(r.ok?(r.msg||'تم'):('فشل: '+(r.error||'')), r.ok);
  if(r.ok) setTimeout(loadWan,1500);
}

/* ---------- WIFI ---------- */
async function loadWifi(){
  const r=await call({op:'wifi_radios'});
  const live=await call({op:'wifi'});
  const liveMap={};
  if(live&&live.ok)(live.radios||[]).forEach((x,i)=>liveMap[i]=x);
  if(!(r&&r.ok)){ $('#wifiCards').innerHTML='<div class="card"><div class="sub">تعذّر التحميل</div></div>'; return; }
  $('#wifiCards').innerHTML=(r.radios||[]).map((rd,i)=>{
    const lv=liveMap[i]||{};
    const is5=(rd.band==='5g'||(lv.band&&lv.band.indexOf('5')>=0));
    const max=30, cur=+(rd.txpower||lv.txpower||(is5?30:24));
    return `<div class="card" data-radio="${esc(rd.radio)}">
      <h3>${is5?'📡 5GHz':'📶 2.4GHz'} <span class="badge ok">${esc(rd.radio)}</span></h3>
      <label class="f">اسم الشبكة (SSID)</label>
      <input class="t wssid" value="${esc(rd.ssid||'')}">
      <label class="f">كلمة المرور (فارغة = مفتوحة)</label>
      <input class="t wkey" type="text" placeholder="••••••••">
      <label class="f">قوة الإرسال: <span class="pw-val wpv">${cur}</span> dBm</label>
      <input class="t wpow" type="range" min="10" max="${max}" value="${cur}">
      ${!is5?'<div class="note">القيمة الفعلية على 2.4GHz محدودة بالعتاد (~24–27dBm).</div>':''}
      <div class="sub" style="margin-top:8px">القناة: ${esc(rd.channel||lv.channel||'auto')} · المتصلون: ${lv.clients||0}</div>
      <button class="btn wapply">حفظ الشبكة</button>
    </div>`;
  }).join('') || '<div class="card"><div class="sub">لا توجد راديوهات</div></div>';

  $$('#wifiCards .card').forEach(card=>{
    const pow=card.querySelector('.wpow'), pv=card.querySelector('.wpv');
    if(pow) pow.oninput=()=>pv.textContent=pow.value;
    const b=card.querySelector('.wapply');
    if(b) b.onclick=async()=>{
      const radio=card.dataset.radio;
      const ssid=card.querySelector('.wssid').value;
      const key=card.querySelector('.wkey').value;
      const dbm=card.querySelector('.wpow').value;
      b.innerHTML='<span class="spin"></span>'; b.disabled=true;
      let r1=await call({act:'wifi_apply',radio,ssid,key},true);
      let r2=await call({act:'txpower',radio,dbm},true);
      b.innerHTML='حفظ الشبكة'; b.disabled=false;
      if(r1.ok){
        let m='تم تحديث الشبكة';
        if(r2.ok) m+=` · القوة المطلوبة ${r2.requested} والفعلية ${r2.actual}dBm`;
        toast(m,true); setTimeout(loadWifi,2000);
      }else toast('فشل: '+(r1.error||''),false);
    };
  });
}

/* ---------- PORTS ---------- */
async function loadPorts(){
  const r=await call({op:'ports'});
  if(!(r&&r.ok)){ $('#portsBox').innerHTML='<div class="sub">تعذّر التحميل</div>'; return; }
  $('#portsBox').innerHTML=(r.ports||[]).map(p=>{
    const up=p.link==='up';
    return `<div class="port ${up?'up':''}"><div class="ic"></div>
      <div class="nm">${esc(p.name)}</div>
      <div class="sp">${up?(p.speed?p.speed+'M':'متصل'):'مفصول'}</div></div>`;
  }).join('') || '<div class="sub">لا توجد منافذ مقروءة (قد يكون السويتش DSA)</div>';
}

/* ---------- HEALTH ---------- */
async function loadHealth(){
  const h=await call({op:'health'});
  if(!(h&&h.ok)) return;
  const set=(idEl,idSub,o)=>{ const g=(+o.loss)<100;
    $(idEl).innerHTML=g?o.rtt+'<small> ms</small>':'<span style="color:var(--bad)">✕</span>';
    $(idSub).textContent=g?('فقد: '+o.loss+'%'):'لا استجابة'; };
  set('#h_cf','#h_cf_s',h.cf); set('#h_gg','#h_gg_s',h.goog);
  $('#h_mw').textContent=h.mwan_online;
}

/* ---------- QUICK ---------- */
async function applyQuick(){
  const ssid=$('#q_ssid').value, key=$('#q_key').value;
  const p24=$('#q_p24').value, p5=$('#q_p5').value;
  if(!ssid){ toast('اكتب اسم الواي‑فاي', false); return; }
  const b=$('#qApply'); b.innerHTML='<span class="spin"></span>'; b.disabled=true;
  const rr=await call({op:'wifi_radios'});
  let done=0, msgs=[];
  if(rr&&rr.ok){
    for(const rd of (rr.radios||[])){
      const is5=rd.band==='5g';
      await call({act:'wifi_apply',radio:rd.radio,ssid:ssid+(is5?'-5G':''),key},true);
      const pr=await call({act:'txpower',radio:rd.radio,dbm:is5?p5:p24},true);
      if(pr.ok) msgs.push(`${is5?'5G':'2.4G'}: ${pr.actual}dBm`);
      done++;
    }
  }
  b.innerHTML='تطبيق الإعداد السريع'; b.disabled=false;
  toast(done?('تم الإعداد · '+msgs.join(' · ')):'لم يتم العثور على راديو', !!done);
  if(done) setTimeout(()=>{loadWifi();loadDash();},2000);
}

/* ---------- nav + loop ---------- */
function switchTab(tab){
  $$('#nav button').forEach(b=>b.classList.toggle('active', b.dataset.tab===tab));
  $$('section[data-pane]').forEach(s=>s.classList.toggle('hide', s.dataset.pane!==tab));
  if(tab==='dash') loadDash();
  if(tab==='wan') loadWan();
  if(tab==='wifi') loadWifi();
  if(tab==='ports') loadPorts();
  if(tab==='health') loadHealth();
}
function startLoop(){ if(timer) clearInterval(timer); timer=setInterval(()=>{
  const active=document.querySelector('#nav button.active');
  if(active && active.dataset.tab==='dash') loadDash();
},5000); }

/* ---------- wire up ---------- */
$('#loginBtn').onclick=doLogin;
$('#pw').addEventListener('keydown',e=>{if(e.key==='Enter')doLogin();});
$('#logoutBtn').onclick=logout;
$('#nav').addEventListener('click',e=>{const b=e.target.closest('button');if(b)switchTab(b.dataset.tab);});
$('#wanSeg').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
  wanMode=b.dataset.m; $$('#wanSeg button').forEach(x=>x.classList.toggle('active',x===b)); $('#wanForm').innerHTML=wanFormHtml(wanMode);});
$('#wanApply').onclick=applyWan;
$('#wanReco').onclick=async()=>{const r=await call({act:'wan_reconnect'},true);toast(r.ok?'يُعاد الاتصال…':'فشل',r.ok);};
$('#hRefresh').onclick=loadHealth;
$('#qApply').onclick=applyQuick;
$('#q_p24').oninput=()=>$('#q_p24v').textContent=$('#q_p24').value;
$('#q_p5').oninput=()=>$('#q_p5v').textContent=$('#q_p5').value;

/* boot: if we have a token, try to use it; else show login */
(async function(){
  if(TOKEN){ const s=await call({op:'summary'}); if(s&&s.ok){ showApp(); return; } TOKEN=''; sessionStorage.removeItem('kt412tok'); }
  $('#login').classList.remove('hide');
})();
