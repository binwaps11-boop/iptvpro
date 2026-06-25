'use strict';
const API='/cgi-bin/kt412';
const API_FW='/cgi-bin/kt412-fw';
let fwForce=0;
let TOKEN = sessionStorage.getItem('kt412tok') || '';
let timer=null, logKind='sys';

const $=s=>document.querySelector(s);
const $$=s=>document.querySelectorAll(s);
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function b64dec(s){ try{return decodeURIComponent(escape(atob(s||'')));}catch(e){try{return atob(s||'');}catch(_){return '';}} }

function toast(msg, ok){
  const t=$('#toast'); t.textContent=msg; t.className='show '+(ok===false?'bad':(ok?'ok':''));
  clearTimeout(t._t); t._t=setTimeout(()=>t.className='', 3400);
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
  if(r.ok && r.token){ TOKEN=r.token; sessionStorage.setItem('kt412tok',TOKEN); showApp(); }
  else{ const m=$('#loginMsg'); m.classList.remove('hide');
    m.textContent = r.error==='bad_password' ? 'كلمة المرور غير صحيحة.' : 'تعذّر الدخول: '+(r.error||'خطأ'); }
}
function logout(){ TOKEN=''; sessionStorage.removeItem('kt412tok'); if(timer)clearInterval(timer);
  $('#app').classList.add('hide'); $('#login').classList.remove('hide'); $('#pw').value=''; }
function showApp(){ $('#login').classList.add('hide'); $('#app').classList.remove('hide'); renderSidebar(); selectPane('dash'); startLoop(); }

/* ---------- helpers ---------- */
function human(b){ b=+b||0; const u=['B','KB','MB','GB','TB']; let i=0; while(b>=1024&&i<u.length-1){b/=1024;i++;} return b.toFixed(b<10&&i>0?1:0)+' '+u[i]; }
function dur(s){ s=+s||0; const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);
  if(d>0)return d+'ي '+h+'س'; if(h>0)return h+'س '+m+'د'; return m+'د'; }

/* ---------- dashboard ---------- */
async function renderControls(){
  const box=$('#quickControls'); if(!box)return;
  const r=await call({op:'wifi_radios'});
  const rs=(r&&r.ok)?(r.radios||[]):[];
  if(!rs.length){ box.innerHTML='<div class="sub">لا راديوهات</div>'; return; }
  box.innerHTML=rs.map(rd=>{
    const is5=rd.band==='5g'; const en=(rd.enabled===true||rd.enabled==='true');
    const tp=Math.max(0,Math.min(30,+rd.txpower||30));
    return `<div class="ctrlrow" data-radio="${esc(rd.radio)}">
      <div class="ci">${is5?'📡':'📶'}</div>
      <div class="cm"><b>${is5?'الواي‑فاي 5GHz':'الواي‑فاي 2.4GHz'}</b><div class="sub">${esc(rd.ssid||'—')} · قناة ${esc(rd.channel||'auto')}</div></div>
      <div class="cr">
        <div class="pwrwrap"><span class="sub">الطاقة</span><input type="range" class="cpw" min="0" max="30" step="1" value="${tp}" style="width:110px"><b class="cpwv">${tp}</b></div>
        <label class="switch"><input type="checkbox" class="csw" ${en?'checked':''}><span class="sl"></span></label>
      </div></div>`;
  }).join('');
  $$('#quickControls .ctrlrow').forEach(row=>{
    const radio=row.dataset.radio;
    const sw=row.querySelector('.csw');
    if(sw) sw.onchange=async()=>{ const r=await call({act:'wifi_toggle',radio,on:sw.checked?1:0},true);
      toast(r&&r.ok?(sw.checked?'تم تشغيل الراديو':'تم إيقاف الراديو'):'فشل',r&&r.ok); };
    const pw=row.querySelector('.cpw'), pv=row.querySelector('.cpwv');
    if(pw){ pw.oninput=()=>{ if(pv)pv.textContent=pw.value; };
      pw.onchange=async()=>{ const r=await call({act:'txpower',radio,dbm:pw.value},true);
        toast(r&&r.ok?('الطاقة '+(r.requested||pw.value)+'dBm · مطبّق '+(r.actual||'?')):'فشل',r&&r.ok); }; }
  });
}
async function loadDash(){
  renderControls();
  const s=await call({op:'summary'});
  if(s&&s.ok){
    $('#d_model').textContent=s.model||'KT412'; $('#d_rel').textContent=s.release||'';
    $('#d_up').textContent=dur(s.uptime); $('#d_load').textContent='الحِمل: '+((+s.load/65536)||0).toFixed(2);
    const used=(+s.mem_total)-(+s.mem_free)-(+s.mem_buf);
    const pct=s.mem_total>0?Math.round(used/s.mem_total*100):0;
    $('#d_mem').innerHTML=pct+'<small>%</small>'; $('#d_membar').style.width=pct+'%';
    $('#d_memsub').textContent=human(used)+' / '+human(s.mem_total);
    setGauge('g_mem',pct,pct+'%');
    const loadv=(+s.load/65536)||0;
    // real CPU utilization % from /proc/stat jiffie diff across polls (load avg sits near 0 on idle)
    let cpuPct=0;
    if(_cpuTotalPrev>0 && +s.cpu_total>_cpuTotalPrev){
      const dTotal=(+s.cpu_total)-_cpuTotalPrev, dIdle=(+s.cpu_idle)-_cpuIdlePrev;
      if(dTotal>0) cpuPct=Math.max(0,Math.min(100,Math.round(100*(1-dIdle/dTotal))));
    }
    _cpuIdlePrev=+s.cpu_idle||0; _cpuTotalPrev=+s.cpu_total||0;
    setGauge('g_load',cpuPct,cpuPct+'%');
    if(s.fs_total&&+s.fs_total>0){ const sp=Math.round(+s.fs_used/+s.fs_total*100);
      setGauge('g_store',sp,sp+'%'); $('#d_storage').textContent='التخزين: '+human(+s.fs_used*1024)+' / '+human(+s.fs_total*1024); }
    $('#d_up').textContent='⏱ '+dur(s.uptime);
    if(s.ncpu)$('#d_cpu').textContent='المعالج: '+s.ncpu+' نواة · حِمل '+loadv.toFixed(2);
  }
  const w=await call({op:'wan'});
  if(w&&w.ok){ const up=w.up===true||w.up==='true';
    window._wanDev=w.device||'';
    $('#d_wan').innerHTML=up?'<span style="color:var(--ok)">● متصل</span>':'<span style="color:var(--bad)">● منقطع</span>';
    $('#d_wanip').textContent=(w.ip||'—')+' · '+(w.proto||'');
    $('#netDot').className='dot '+(up?'on':'off'); $('#netTxt').textContent=up?'متصل':'منقطع';
    const d2=$('#netDot2'),t2=$('#netTxt2'); if(d2)d2.className='dot '+(up?'on':'off'); if(t2)t2.textContent=up?'متصل':'منقطع'; }
  const p=await call({op:'ports'});
  if(p&&p.ok){ $('#d_links').innerHTML=(p.ports||[]).map(x=>`<div class="kv"><span class="k">${esc(x.name)}</span>`+
    `<span class="v">${x.link==='up'?(x.speed?x.speed+' Mbps':'متصل'):'مفصول'}</span></div>`).join('')||'<div class="sub">—</div>';
    const act=(p.ports||[]).filter(x=>x.link==='up').length; const tp=$('#t_ports'); if(tp)tp.textContent=act; }
  const c=await call({op:'devices'});
  if(c&&c.ok){ const ds=c.devices||[];
    $('#d_clients').textContent=ds.length; const tc=$('#t_clients'); if(tc)tc.textContent=ds.length;
    const t2=$('#t_clients2'); if(t2)t2.textContent=ds.length;
    const dc=$('#d_devlist');
    if(dc) dc.innerHTML = ds.length ? ds.slice(0,8).map(x=>{
      const band=x.kind==='wifi5g'?'5G':(x.kind==='wifi2g'?'2.4G':'سلكي');
      const sig=(String(x.kind).indexOf('wifi')>=0&&x.signal)?' · '+esc(x.signal)+'dBm'+(x.dist?' ('+esc(x.dist)+')':''):'';
      return `<div class="kv"><span class="k">${esc(x.name||'جهاز')} <span class="badge ok">${band}</span></span>`+
             `<span class="v">${esc(x.ip||'—')}${sig}</span></div>`;
    }).join('') + (ds.length>8?`<div class="sub" style="margin-top:4px">+${ds.length-8} المزيد…</div>`:'')
      : '<div class="sub">لا أجهزة متصلة</div>';
  }
  const tr=await call({op:'traffic'});
  if(tr&&tr.ok){ const dev=window._wanDev; const wi=(tr.ifaces||[]).find(x=>x.if===dev);
    if(wi) $('#d_wanusage').innerHTML=`<div class="kv"><span class="k">↓ تنزيل</span><span class="v">${human(wi.rx)}</span></div>`+
      `<div class="kv"><span class="k">↑ رفع</span><span class="v">${human(wi.tx)}</span></div>`;
    else $('#d_wanusage').innerHTML='<div class="sub">—</div>'; }
  const wi=await call({op:'wifi'});
  if(wi&&wi.ok){ $('#d_wifi').innerHTML=(wi.radios||[]).map(r=>
    `<div class="kv"><span class="k">${esc(r.essid||r.mode||'—')} <span class="badge ok">${esc(r.band)}</span></span>`+
    `<span class="v">${r.txpower} dBm · ${r.clients} جهاز</span></div>`).join('')||'<div class="sub">لا شبكات نشطة</div>';
    let w24=0,w5=0; (wi.radios||[]).forEach(r=>{ const n=+r.clients||0; (String(r.band).indexOf('5')>=0)?w5+=n:w24+=n; });
    const a=$('#t_w24'),b=$('#t_w5'); if(a)a.textContent=w24; if(b)b.textContent=w5; }
  const h=await call({op:'health'});
  if(h&&h.ok){ const row=(n,o)=>{const g=(+o.loss)<100;return `<div class="kv"><span class="k">${n}</span><span class="v">`+
    (g?`<span class="badge ok">${o.rtt} ms</span>`:`<span class="badge bad">منقطع</span>`)+`</span></div>`;};
    $('#d_health').innerHTML=row('Cloudflare',h.cf)+row('Google',h.goog)+
      `<div class="kv"><span class="k">Multi‑WAN online</span><span class="v">${h.mwan_online}</span></div>`; }
}

/* ---------- NETWORK: WAN ---------- */
let wanMode='dhcp';
function wanFormHtml(m){
  if(m==='pppoe')return `<label class="f">اسم المستخدم</label><input id="w_user" class="t">
    <label class="f">كلمة المرور</label><input id="w_pass" class="t" type="text">`;
  if(m==='static')return `<div class="row"><div><label class="f">IP</label><input id="w_ip" class="t"></div>
    <div><label class="f">Netmask</label><input id="w_mask" class="t" placeholder="255.255.255.0"></div></div>
    <div class="row"><div><label class="f">Gateway</label><input id="w_gw" class="t"></div>
    <div><label class="f">DNS</label><input id="w_dns" class="t" placeholder="1.1.1.1"></div></div>`;
  return `<div class="sub" style="margin:8px 0">عنوان تلقائي من مزوّد الخدمة.</div>`;
}
async function loadWan(){
  const w=await call({op:'wan'});
  if(w&&w.ok){ const up=w.up===true||w.up==='true';
    $('#wanStatus').innerHTML=
      `<div class="kv"><span class="k">الحالة</span><span class="v">${up?'<span class="badge ok">متصل</span>':'<span class="badge bad">منقطع</span>'}</span></div>`+
      `<div class="kv"><span class="k">النوع</span><span class="v">${esc(w.proto||'—')}</span></div>`+
      `<div class="kv"><span class="k">IP</span><span class="v">${esc(w.ip||'—')}</span></div>`+
      `<div class="kv"><span class="k">البوابة</span><span class="v">${esc(w.gateway||'—')}</span></div>`+
      `<div class="kv"><span class="k">VLAN</span><span class="v">${esc(w.vlan||'—')}</span></div>`;
    wanMode=(w.proto==='pppoe'||w.proto==='static')?w.proto:'dhcp';
    $$('#wanSeg button').forEach(b=>b.classList.toggle('active',b.dataset.m===wanMode));
    $('#wanForm').innerHTML=wanFormHtml(wanMode);
    if(w.vlan) $('#w_vlan').value=w.vlan;
  }
}
async function applyWan(){
  let p={act:'wan_'+wanMode};
  if(wanMode==='pppoe'){ p.user=$('#w_user').value; p.pass=$('#w_pass').value; }
  if(wanMode==='static'){ p.ip=$('#w_ip').value; p.mask=$('#w_mask').value; p.gw=$('#w_gw').value; p.dns=$('#w_dns').value; }
  const r=await safeApply(()=>call(p,true)); toast(r&&r.ok?(r.msg||'طُبّق — أكّد خلال 80ث'):('فشل: '+((r&&r.error)||'')),r&&r.ok); if(r&&r.ok)setTimeout(loadWan,1500);
}

/* ---------- live WAN throughput (rx/tx Mbps) ---------- */
let lastTr={}, lastTrTs=0;
async function loadSpeed(){
  const r=await call({op:'traffic'}); if(!(r&&r.ok))return;
  const m={}; (r.ifaces||[]).forEach(x=>m[x.if]={rx:+x.rx,tx:+x.tx});
  const ts=+r.ts, dev=window._wanDev;
  if(lastTrTs && dev && m[dev] && lastTr[dev]){
    const dt=ts-lastTrTs;
    if(dt>0){
      const dl=Math.max(0,(m[dev].rx-lastTr[dev].rx)*8/1e6/dt);
      const ul=Math.max(0,(m[dev].tx-lastTr[dev].tx)*8/1e6/dt);
      const sp=$('#d_speed'); if(sp)sp.innerHTML=dl.toFixed(1)+'<small> ↓</small> / '+ul.toFixed(1)+'<small> ↑</small>';
      const a=$('#d_dl'),b=$('#d_ul'); if(a)a.textContent=dl.toFixed(1); if(b)b.textContent=ul.toFixed(1);
      dlH.push(dl); ulH.push(ul); if(dlH.length>HIST)dlH.shift(); if(ulH.length>HIST)ulH.shift();
      drawChart();
    }
  }
  lastTr=m; lastTrTs=ts;
}

/* ---------- NETWORK: device mode ---------- */
let netMode='router';
async function loadNetMode(){
  const r=await call({op:'netmode'});
  if(r&&r.ok){ netMode=r.mode||'router';
    $$('#netModeSeg button').forEach(b=>b.classList.toggle('active',b.dataset.m===netMode)); }
}

/* ---------- VLAN Manager ---------- */
async function loadVlan(){
  const r=await call({op:'vlan_list'});
  const vlans=(r&&r.ok)?(r.vlans||[]):[];
  $('#vlanList').innerHTML = vlans.length? vlans.map(v=>
    `<div class="kv"><span class="k">VLAN ${esc(v.vid)} <span class="sub">${esc(v.ip||'')} ${esc(v.ports||'')}</span></span>`+
    `<span class="v">${v.dhcp?'<span class="badge ok">DHCP</span> ':''}`+
    (v.vid!=='1'?`<button class="btn-ghost vdel" data-vid="${esc(v.vid)}" style="font-size:11px;padding:2px 8px">حذف</button>`:'<span class="badge warn">إدارة</span>')+
    `</span></div>`).join('') : '<div class="sub">لا VLANs — الوضع العادي (جسر واحد بدون VLAN).</div>';
  const vopts='<option value="1">1 (إدارة)</option>'+vlans.filter(v=>v.vid!=='1').map(v=>`<option value="${esc(v.vid)}">${esc(v.vid)}</option>`).join('');
  $('#vlanPortVid').innerHTML=vopts; $('#vlanSsidVid').innerHTML=vopts;
  const p=await call({op:'ports'});
  $('#vlanPortSel').innerHTML=((p&&p.ok)?(p.ports||[]):[]).filter(x=>/^(lan|wan)/.test(x.name)).map(x=>`<option>${esc(x.name)}</option>`).join('')||'<option>lan1</option>';
  const w=await call({op:'wifi_radios'});
  $('#vlanSsidSel').innerHTML=((w&&w.ok)?(w.radios||[]):[]).filter(r=>r.iface).map(r=>`<option value="${esc(r.iface)}">${esc(r.ssid||r.radio)} (${esc(r.band)})</option>`).join('')||'<option value="">—</option>';
  $$('#vlanList .vdel').forEach(b=>b.onclick=async()=>{ if(!confirm('حذف VLAN '+b.dataset.vid+'؟'))return;
    const r=await safeApply(()=>call({act:'vlan_del',vid:b.dataset.vid},true)); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadVlan,1500); });
}

/* ---------- NETWORK: LAN ---------- */
let dhcpOn='1';
async function loadLan(){
  const l=await call({op:'lan'});
  if(l&&l.ok){ $('#l_ip').value=l.ip||''; $('#l_mask').value=l.mask||''; $('#l_start').value=l.start||'';
    $('#l_limit').value=l.limit||''; $('#l_lease').value=l.lease||'';
    dhcpOn=(l.dhcp===true||l.dhcp==='true')?'1':'0';
    $$('#dhcpSeg button').forEach(b=>b.classList.toggle('active',b.dataset.d===dhcpOn)); }
}
async function applyLan(){
  const r=await safeApply(()=>call({act:'lan_set',ip:$('#l_ip').value,mask:$('#l_mask').value,dhcp:dhcpOn,
    start:$('#l_start').value,limit:$('#l_limit').value,lease:$('#l_lease').value},true));
  toast(r&&r.ok?(r.msg||'طُبّق — أكّد خلال 80ث'):('فشل: '+((r&&r.error)||'')),r&&r.ok);
}

/* ---------- WIFI (modes) ---------- */
// real hardware support: 2.4G QCA9550 = 20/40 only; 5G QCA9880 = 20/40/80 (no 160)
const HTMODES={'2g':['HT40','HT20'],'5g':['VHT80','VHT40','VHT20']};
const MODES=[['ap','نقطة وصول (AP)'],['ap-wds','نقطة وصول + WDS'],['mesh','شبكة Mesh (802.11s)'],['sta','عميل / Client']];
async function loadWifi(){
  const r=await call({op:'wifi_radios'});
  const live=await call({op:'wifi'});
  const lm={}; if(live&&live.ok)(live.radios||[]).forEach((x,i)=>lm[i]=x);
  if(!(r&&r.ok)){ $('#wifiCards').innerHTML='<div class="card"><div class="sub">تعذّر التحميل</div></div>'; return; }
  $('#wifiCards').innerHTML=(r.radios||[]).map((rd,i)=>{
    const lv=lm[i]||{}; const is5=(rd.band==='5g'); const band=is5?'5GHz':'2.4GHz';
    const cur=+(rd.txpower||lv.txpower||30); const en=(rd.enabled===true||rd.enabled==='true');
    const hts=(HTMODES[rd.band]||HTMODES['5g']).map(h=>`<option value="${h}" ${rd.htmode===h?'selected':''}>${h}</option>`).join('');
    const modes=MODES.map(m=>`<option value="${m[0]}" ${rd.mode===m[0]?'selected':''}>${m[1]}</option>`).join('');
    const chans=is5?['auto',36,40,44,48,149,153,157,161,165]:['auto',1,2,3,4,5,6,7,8,9,10,11];
    const chopts=chans.map(c=>`<option value="${c}" ${String(rd.channel||'')===String(c)?'selected':''}>${c==='auto'?'تلقائي (Auto)':c}</option>`).join('');
    return `<div class="card" data-radio="${esc(rd.radio)}" data-band="${esc(rd.band)}">
      <h3>${is5?'📡':'📶'} ${band} <span class="badge ok">${esc(rd.radio)}</span>
        <span style="flex:1"></span>
        <label style="display:flex;align-items:center;gap:6px;font-size:12px;color:var(--txt2)">
          <input type="checkbox" class="wen" ${en?'checked':''}> مُفعّل</label></h3>
      <label class="f">الوضع (Mode)</label>
      <select class="t wmode">${modes}</select>
      <label class="f wssidlbl">اسم الشبكة (SSID)</label>
      <input class="t wssid" value="${esc(rd.ssid||'')}">
      <label class="f">كلمة المرور (فارغة = مفتوحة)</label>
      <input class="t wkey" type="text" placeholder="••••••••">
      <div class="row">
        <div><label class="f">القناة <label style="font-weight:400;font-size:11px;color:var(--txt2)"><input type="checkbox" class="wauto" ${rd.channel==='auto'?'checked':''}> تلقائي</label></label>
          <select class="t wchan" ${rd.channel==='auto'?'disabled':''}>${chopts}</select></div>
        <div><label class="f">العرض (HT)</label><select class="t wht">${hts}</select></div>
        <div><label class="f">الدولة</label><input class="t wcc" value="${esc(rd.country||'US')}" maxlength="2" style="text-transform:uppercase"></div>
      </div>
      <label class="f">قوة الإرسال: <span class="pw-val wpv">${cur}</span> dBm</label>
      <input class="t wpow" type="range" min="10" max="30" value="${cur}">
      ${!is5?'<div class="note">الفعلي على 2.4GHz محدود بالعتاد (~24–27).</div>':''}
      <label style="display:flex;align-items:center;gap:8px;margin-top:8px;font-size:13px;color:var(--txt2)">
        <input type="checkbox" class="whid" ${rd.hidden==='1'?'checked':''}> إخفاء اسم الشبكة</label>
      <div class="sub" style="margin-top:6px">المتصلون: ${lv.clients||0} · الوضع الحالي: ${esc(lv.mode||rd.mode||'ap')}</div>
      <div class="row">
        <div><button class="btn wapply" style="width:100%">حفظ الإعدادات</button></div>
        <div><button class="btn sec wopt" style="width:100%">تحسين تلقائي (أفضل قناة)</button></div>
      </div>
    </div>`;
  }).join('')||'<div class="card"><div class="sub">لا توجد راديوهات</div></div>';

  $$('#wifiCards .card').forEach(card=>{
    const pow=card.querySelector('.wpow'), pv=card.querySelector('.wpv');
    if(pow)pow.oninput=()=>pv.textContent=pow.value;
    const mode=card.querySelector('.wmode'), lbl=card.querySelector('.wssidlbl');
    if(mode)mode.onchange=()=>{ lbl.textContent= mode.value==='mesh'?'معرّف الشبكة (Mesh ID)': (mode.value==='sta'?'اسم شبكة الاتصال (SSID)':'اسم الشبكة (SSID)'); };
    const en=card.querySelector('.wen');
    if(en)en.onchange=async()=>{ const r=await call({act:'wifi_toggle',radio:card.dataset.radio,on:en.checked?'1':'0'},true);
      toast(r.ok?(r.msg||'تم'):'فشل',r.ok); };
    const au=card.querySelector('.wauto'), chsel=card.querySelector('.wchan');
    if(au)au.onchange=async()=>{ if(chsel)chsel.disabled=au.checked;
      const r=await call({act:'wifi_autochan',radio:card.dataset.radio,on:au.checked?'1':'0',channel:chsel?chsel.value:''},true);
      toast(r.ok?(au.checked?'القناة تلقائية مفعّلة (ACS)':'قناة ثابتة: '+r.channel):'فشل',r.ok); };
    const opt=card.querySelector('.wopt');
    if(opt)opt.onclick=async()=>{ opt.innerHTML='<span class="spin"></span>';
      const r=await call({act:'wifi_optimize',radio:card.dataset.radio},true);
      opt.innerHTML='تحسين تلقائي (أفضل قناة)';
      if(r.ok)toast(`أفضل قناة: ${r.channel} (${r.neighbors} جار)`,true); else toast('فشل التحسين',false);
      setTimeout(loadWifi,2000);
    };
    const b=card.querySelector('.wapply');
    if(b)b.onclick=async()=>{
      const g=c=>card.querySelector(c);
      b.innerHTML='<span class="spin"></span>'; b.disabled=true;
      const r1=await call({act:'wifi_apply',radio:card.dataset.radio,ssid:g('.wssid').value,key:g('.wkey').value,
        mode:g('.wmode').value,channel:g('.wchan').value,htmode:g('.wht').value,country:g('.wcc').value,
        hidden:g('.whid').checked?'1':'0'},true);
      const r2=await call({act:'txpower',radio:card.dataset.radio,dbm:g('.wpow').value},true);
      b.innerHTML='حفظ الإعدادات'; b.disabled=false;
      if(r1.ok){ let m=r1.msg||'تم'; if(r2.ok)m+=` · القوة المطلوبة ${r2.requested} والفعلية ${r2.actual}dBm`;
        toast(m,true); setTimeout(loadWifi,2200); }
      else toast('فشل: '+(r1.error||''),false);
    };
  });
}

/* ---------- CLIENTS ---------- */
async function loadClients(){
  const r=await call({op:'clients'});
  if(!(r&&r.ok)){ $('#clientsBox').innerHTML='<div class="sub">تعذّر التحميل</div>'; return; }
  const c=r.clients||[];
  $('#clientsBox').innerHTML = c.length? c.map(x=>
    `<div class="kv"><span class="k">${esc(x.name&&x.name!=='*'?x.name:'جهاز')}<br><span class="sub">${esc(x.mac)}</span></span>`+
    `<span class="v">${esc(x.ip)} <button class="btn-ghost blkb" data-mac="${esc(x.mac)}" style="font-size:11px;padding:2px 8px">حظر</button></span></div>`).join('')
    : '<div class="sub">لا أجهزة مؤجَّرة حالياً</div>';
  $$('#clientsBox .blkb').forEach(b=>b.onclick=async()=>{ if(!confirm('حظر '+b.dataset.mac+' من الإنترنت؟'))return;
    const r=await call({act:'client_block',mac:b.dataset.mac},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadBlocked,800); });
  loadBlocked();
}

/* ---------- PORTS ---------- */
async function loadPorts(){
  const r=await call({op:'ports'});
  if(!(r&&r.ok)){ $('#portsBox').innerHTML='<div class="sub">تعذّر التحميل</div>'; return; }
  $('#portsBox').innerHTML=(r.ports||[]).map(p=>{ const up=p.link==='up';
    return `<div class="port ${up?'up':''}" data-port="${esc(p.name)}"><div class="ic"></div><div class="nm">${esc(p.name)}</div>
      <div class="sp">${up?(p.speed?p.speed+'M':'متصل'):'مفصول'}</div>
      <div class="prate" style="font-size:11px;color:var(--txt2);margin-top:4px">—</div>
      <div class="pcons" style="font-size:11px;color:var(--txt2)">—</div>
      <div style="margin-top:6px;display:flex;gap:4px;justify-content:center">
        <button class="btn-ghost ptgl" data-on="1" style="font-size:11px;padding:3px 8px">تشغيل</button>
        <button class="btn-ghost ptgl" data-on="0" style="font-size:11px;padding:3px 8px">إيقاف</button></div>
    </div>`;
  }).join('')||'<div class="sub">لا منافذ مقروءة</div>';
  $$('#portsBox .port').forEach(el=>{ el.querySelectorAll('.ptgl').forEach(btn=>{ btn.onclick=async()=>{
    const r=await call({act:'port_toggle',port:el.dataset.port,on:btn.dataset.on},true);
    toast(r.ok?`المنفذ ${el.dataset.port} → ${r.state}`:'تعذّر (منافذ DSA فقط)', r.ok);
    setTimeout(loadPorts,1200);
  };});});
  loadPortRates();
}
let lastPort={}, lastPortTs=0;
async function loadPortRates(){
  const r=await call({op:'traffic'}); if(!(r&&r.ok))return;
  const m={}; (r.ifaces||[]).forEach(x=>m[x.if]={rx:+x.rx,tx:+x.tx}); const ts=+r.ts;
  $$('#portsBox .port').forEach(el=>{ const name=el.dataset.port, cur=m[name];
    if(!cur)return;
    const cons=el.querySelector('.pcons'), rate=el.querySelector('.prate');
    if(cons)cons.textContent='استهلك ↓'+human(cur.rx)+' ↑'+human(cur.tx);
    if(lastPortTs && lastPort[name] && rate){ const dt=ts-lastPortTs;
      if(dt>0){ const dl=Math.max(0,(cur.rx-lastPort[name].rx)*8/1e6/dt), ul=Math.max(0,(cur.tx-lastPort[name].tx)*8/1e6/dt);
        rate.textContent='↓'+dl.toFixed(1)+' ↑'+ul.toFixed(1)+' Mbps'; } }
  });
  lastPort=m; lastPortTs=ts;
}

/* ---------- NEIGHBORS / scan ---------- */
async function loadScan(){
  $('#scanBox').innerHTML='<div class="sub">جارٍ الفحص… (~10 ثوانٍ)</div>'; $('#chanBars').innerHTML='';
  const r=await call({op:'scan'});
  if(!(r&&r.ok)){ $('#scanBox').innerHTML='<div class="sub">تعذّر الفحص</div>'; return; }
  // dedupe by BSSID (virtual APs on the same phy show up once) so the congestion bars match LuCI
  const seen={}; const nets=(r.nets||[]).filter(n=>{ const k=n.bssid||((n.essid||'')+'/'+n.ch); if(seen[k])return false; seen[k]=1; return true; })
    .sort((a,b)=>(+b.sig||-999)-(+a.sig||-999));
  $('#scanBox').innerHTML = nets.length? nets.map(n=>
    `<div class="kv"><span class="k">${esc(n.essid||'(مخفية)')} <span class="badge ok">قناة ${esc(n.ch)}</span></span>`+
    `<span class="v">${esc(n.sig)} dBm · ${esc(n.enc||'')}</span></div>`).join('')
    : '<div class="sub">لا شبكات مجاورة</div>';
  const tally={}; nets.forEach(n=>{ if(n.ch) tally[n.ch]=(tally[n.ch]||0)+1; });
  const keys=Object.keys(tally).sort((a,b)=>(+a)-(+b)); const max=Math.max(1,...Object.values(tally));
  $('#chanBars').innerHTML = keys.length? '<div class="sub" style="margin-bottom:6px">ازدحام القنوات (الأقل = الأفضل):</div>'+
    keys.map(ch=>`<div class="kv"><span class="k">قناة ${esc(ch)}</span><span class="v" style="flex:1;max-width:55%">`+
    `<span class="bar"><i style="width:${Math.round(tally[ch]/max*100)}%"></i></span> ${tally[ch]}</span></div>`).join('') : '';
}

/* ---------- HEALTH ---------- */
async function loadHealth(){
  const h=await call({op:'health'}); if(!(h&&h.ok))return;
  const set=(e,s,o)=>{const g=(+o.loss)<100;$(e).innerHTML=g?o.rtt+'<small> ms</small>':'<span style="color:var(--bad)">✕</span>';
    $(s).textContent=g?('فقد: '+o.loss+'%'):'لا استجابة';};
  set('#h_cf','#h_cf_s',h.cf); set('#h_gg','#h_gg_s',h.goog); $('#h_mw').textContent=h.mwan_online;
}

/* ---------- LOGS ---------- */
async function loadLogs(){
  $('#logBox').textContent='جارٍ التحميل…';
  const r=await call({op:'logs',filter:($('#logFilter')?$('#logFilter').value:'')});
  if(!(r&&r.ok)){ $('#logBox').textContent='تعذّر التحميل'; return; }
  window._logRaw=b64dec(logKind==='ker'?r.ker:r.sys)||'(فارغ)'; renderLog();
}
function renderLog(){
  let txt=window._logRaw||''; const q=($('#logSearch')?$('#logSearch').value:'').trim();
  if(q) txt=txt.split('\n').filter(l=>l.toLowerCase().indexOf(q.toLowerCase())>=0).join('\n')||'(لا نتائج)';
  $('#logBox').textContent=txt;
}

/* ---------- POWER CONTROL ---------- */
/* ---------- QUICK SETUP ---------- */
async function loadQuick(){
  // prefill txpower (from 2.4G radio) + LAN ip placeholder from current config
  const p=await call({op:'power'});
  if(p&&p.ok&&p.radios&&p.radios.length){ const rd=p.radios.find(x=>x.band!=='5g')||p.radios[0];
    const t=$('#qs_tx'), v=$('#qs_txv'); if(t&&rd&&rd.requested){ t.value=Math.max(0,Math.min(30,+rd.requested||30)); if(v)v.textContent=t.value; } }
  const l=await call({op:'lan'});
  if(l&&l.ok&&l.ip){ const e=$('#qs_lan'); if(e&&!e.value)e.placeholder=l.ip; }
  // device-mode toggling: show PPPoE fields or the Station scan-picker
  const ms=$('#qs_mode');
  if(ms){ const toggle=()=>{
      const pr=$('#qs_pppoe_row'); if(pr)pr.style.display = ms.value==='pppoe'?'flex':'none';
      const sr=$('#qs_sta_row');  if(sr)sr.style.display  = ms.value==='station'?'block':'none';
    }; ms.onchange=toggle; toggle(); }
  // populate the station radio picker
  const rad=$('#qs_sta_radio');
  if(rad){ const r=await call({op:'wifi_radios'});
    rad.innerHTML=((r&&r.ok)?(r.radios||[]):[]).map(x=>
      `<option value="${esc(x.radio)}">${esc(x.radio)} · ${esc(x.band==='5g'?'5GHz':'2.4GHz')} (${esc(x.ssid||'—')})</option>`).join('')||'<option value="">—</option>'; }
  const sb=$('#qsScanBtn');  if(sb) sb.onclick=qsStationScan;
  const ap=$('#qsStaApply'); if(ap) ap.onclick=qsStationApply;
}
async function qsStationScan(){
  const radio=$('#qs_sta_radio').value;
  if(!radio){ toast('اختر الراديو أولاً',false); return; }
  const box=$('#qsScanList'), btn=$('#qsScanBtn');
  box.innerHTML='<div class="sub">جارٍ الفحص… (~10 ثوانٍ)</div>'; btn.disabled=true;
  const r=await call({op:'wscan',radio});
  btn.disabled=false;
  if(!(r&&r.ok)){ box.innerHTML='<div class="sub">تعذّر الفحص</div>'; return; }
  const nets=(r.nets||[]).filter(n=>n.essid).sort((a,b)=>(+b.sig||-999)-(+a.sig||-999));
  box.innerHTML = nets.length ? nets.map(n=>{
    const open=/none|open/i.test(n.enc||'');
    return `<div class="kv qsNet" data-ssid="${esc(n.essid)}" data-bssid="${esc(n.bssid||'')}" data-open="${open?1:0}" style="cursor:pointer">`+
      `<span class="k">${esc(n.essid)} <span class="sub">${esc(n.bssid||'')}</span></span>`+
      `<span class="v"><span class="badge ok">قناة ${esc(n.ch)}</span> ${esc(n.sig)}dBm · ${open?'مفتوحة':esc((n.enc||'').slice(0,12))}</span></div>`;
  }).join('') : '<div class="sub">لا شبكات مجاورة</div>';
  $$('#qsScanList .qsNet').forEach(el=>el.onclick=()=>{
    $('#qs_sta_ssid').value=el.dataset.ssid; $('#qs_sta_bssid').value=el.dataset.bssid;
    if(el.dataset.open==='1') $('#qs_sta_key').value=''; $('#qs_sta_key').focus();
    $$('#qsScanList .qsNet').forEach(x=>x.style.background=''); el.style.background='rgba(124,58,18,.25)';
  });
}
async function qsStationApply(){
  const radio=$('#qs_sta_radio').value, ssid=$('#qs_sta_ssid').value.trim();
  if(!radio||!ssid){ toast('اختر شبكة من القائمة أولاً',false); return; }
  const r=await safeApply(()=>call({act:'station_uplink',radio,ssid,bssid:$('#qs_sta_bssid').value,key:$('#qs_sta_key').value},true));
  toast(r&&r.ok?(r.msg||'طُبّق — أكّد خلال 80ث'):('فشل: '+((r&&r.error)||'')),r&&r.ok);
}
async function loadPower(){
  const r=await call({op:'power'});
  if(!(r&&r.ok)){ $('#powerBox').innerHTML='<div class="sub">تعذّر التحميل</div>'; return; }
  const pv=x=>{ x=(x==null?'':String(x)); return (x===''||x==='?')?'—':x; };
  $('#powerBox').innerHTML=(r.radios||[]).map(rd=>{
    const is5=rd.band==='5g'; const req=Math.max(0,Math.min(30,+rd.requested||0));
    const nd=pv(rd.netdev), ap=pv(rd.applied);
    const match = (ap!=='—' && String(ap)===String(req)); // applied == requested ?
    return `<div class="card" data-radio="${esc(rd.radio)}" data-req="${req}" style="margin-top:14px;background:rgba(255,255,255,.04)">
      <h3>${is5?'📡 5GHz · radio1':'📶 2.4GHz · radio0'} <span class="badge ok">${esc(rd.radio)}</span></h3>
      <div class="kv"><span class="k">Requested Power (uci)</span><span class="v" data-f="req">${esc(rd.requested)} dBm</span></div>
      <div class="kv"><span class="k">Applied / Driver (iwinfo)</span><span class="v"><span class="badge ${match?'ok':'warn'}" data-f="ap">${pv(rd.applied)} dBm</span></span></div>
      <div class="kv"><span class="k">PHY Power (iw phy)</span><span class="v"><span class="badge ${pv(rd.phy_limit)==='30'?'ok':'warn'}" data-f="phy">${pv(rd.phy_limit)} dBm</span></span></div>
      <div class="kv"><span class="k">DebugFS user_power</span><span class="v" data-f="up">${pv(rd.user_power)}</span></div>
      <div class="kv"><span class="k">DebugFS netdev txpower</span><span class="v"><span class="badge ${nd==='30'||(nd!=='—'&&match)?'ok':'warn'}" data-f="nd">${nd}</span></span></div>
      <label class="f">TX Power: <b class="wpowval">${req}</b> dBm <span class="sub">(0 – 30 · الأقصى 30)</span></label>
      <input type="range" class="wpow" min="0" max="30" step="1" value="${req}" style="width:100%">
      <div class="row" style="margin-top:8px">
        <button class="btn sm pwapply">تطبيق آمن (Safe Apply)</button>
        <button class="btn sm sec pwverify">تحقّق الآن</button>
      </div>
      ${is5?'':'<div class="sub" style="margin-top:6px">⚠ على 2.4GHz: الرقم البرمجي يصل 30، لكن RF النظيف الحقيقي ≈25–26 (غير مُقاس). راجع POWER-REPORT.</div>'}
    </div>`;
  }).join('')||'<div class="sub">لا راديوهات</div>';
  $$('#powerBox .card').forEach(card=>{
    const sl=card.querySelector('.wpow'), val=card.querySelector('.wpowval');
    if(sl&&val) sl.oninput=()=>{ val.textContent=sl.value; };
    const apply=card.querySelector('.pwapply');
    if(apply) apply.onclick=async()=>{
      const dbm=sl?sl.value:'30';
      if(+dbm>=27 && card.dataset.radio.indexOf('1')<0){ if(!confirm('على 2.4GHz: '+dbm+' dBm = رقم برمجي قد يقصّ الـRF (غير نظيف مخبريًا). متابعة؟'))return; }
      apply.innerHTML='<span class="spin"></span>';
      // Safe Apply: arm rollback + countdown; auto-revert in 80s unless confirmed
      const r=await safeApply(()=>call({act:'txpower',radio:card.dataset.radio,dbm},true));
      if(r&&r.ok) toast(`طُبّق ${r.requested}dBm — المُطبَّق (iwinfo) ${r.actual}dBm. أكّد خلال 80ث وإلا رجوع تلقائي.`,true);
      else toast('فشل: '+((r&&r.error)||''),false);
      setTimeout(loadPower,2000);
    };
    const ver=card.querySelector('.pwverify');
    if(ver) ver.onclick=()=>loadPower();
  });
}

/* ---------- SYSTEM ---------- */
async function loadSystem(){
  const s=await call({op:'system'}); if(!(s&&s.ok))return;
  const hp=(s.has_password===true||s.has_password==='true');
  $('#sysInfo').innerHTML=
    `<div class="kv"><span class="k">الإصدار</span><span class="v">${esc(s.release||'—')}</span></div>`+
    `<div class="kv"><span class="k">الاسم</span><span class="v">${esc(s.host||'—')}</span></div>`+
    `<div class="kv"><span class="k">الوقت</span><span class="v">${esc(s.time||'—')}</span></div>`+
    `<div class="kv"><span class="k">المنطقة</span><span class="v">${esc(s.tz||'UTC')}</span></div>`+
    `<div class="kv"><span class="k">كلمة المرور</span><span class="v">${hp?'<span class="badge ok">مضبوطة</span>':'<span class="badge warn">غير مضبوطة!</span>'}</span></div>`;
  $('#s_host').value=s.host||''; $('#s_tz').value=s.tz||'';
  const nt=(s.ntp||'').trim().split(/\s+/); if($('#s_ntp1'))$('#s_ntp1').value=nt[0]||''; if($('#s_ntp2'))$('#s_ntp2').value=nt[1]||'';
}

/* ---------- Safe Apply / auto-rollback ---------- */
let safeTimer=null;
async function safeApply(actionFn){
  const a=await call({act:'safe_arm'},true);        // snapshot + schedule revert
  const r=await actionFn();                          // apply the risky change
  let n=(a&&a.timeout)?a.timeout:80;
  const banner=$('#safeBanner'), cnt=$('#safeCount');
  if(banner){ banner.classList.remove('hide'); cnt.textContent=n;
    if(safeTimer)clearInterval(safeTimer);
    safeTimer=setInterval(()=>{ n--; if(cnt)cnt.textContent=n; if(n<=0){ clearInterval(safeTimer); banner.classList.add('hide'); } },1000); }
  return r;
}

/* ---------- reports & super-check ---------- */
async function showReport(f){
  const box=$('#reportBox'); box.classList.remove('hide'); box.textContent='…';
  const r=await call({op:'readfile',f}); box.textContent=(r&&r.ok)?b64dec(r.content):'تعذّر القراءة';
}
function pollSuper(){
  const box=$('#reportBox'); box.classList.remove('hide'); box.textContent='جارٍ الفحص الشامل… (~2-3 دقائق)';
  let n=0; const iv=setInterval(async()=>{ n++;
    const s=await call({op:'super_status'});
    if(s&&s.ok){ if(s.report)box.textContent=b64dec(s.report);
      if(s.done){ clearInterval(iv); box.textContent=(s.report?b64dec(s.report):'')+'\n\n[اكتمل] الحزمة: '+(s.bundle||''); } }
    if(n>80)clearInterval(iv);
  },3000);
}

/* ---------- FIREWALL / DNS / LEASES / ROUTES ---------- */
async function loadFw(){
  const r=await call({op:'fw_list'});
  const rules=(r&&r.ok)?(r.rules||[]):[];
  $('#fwList').innerHTML = rules.length? rules.map(x=>
    `<div class="kv"><span class="k">${esc(x.name||x.id)} <span class="sub">${esc(x.proto||'')} ${esc(x.sport)}→${esc(x.dip)}:${esc(x.dport||x.sport)}</span></span>`+
    `<span class="v"><button class="btn-ghost fwdel" data-id="${esc(x.id)}" style="font-size:11px;padding:2px 8px">حذف</button></span></div>`).join('')
    : '<div class="sub">لا توجد توجيهات.</div>';
  if(r&&r.ok&&r.dmz)$('#fw_dmz').value=r.dmz;
  $$('#fwList .fwdel').forEach(b=>b.onclick=async()=>{ const x=await call({act:'fw_forward_del',name:b.dataset.id},true);
    toast(x&&x.ok?(x.msg||'حُذف'):'فشل',x&&x.ok); setTimeout(loadFw,800); });
}
async function loadDns(){
  const r=await call({op:'dns_get'}); if(!(r&&r.ok))return;
  $('#dns1').value=r.dns1||''; $('#dns2').value=r.dns2||''; $('#dnsForce').checked=(r.force===true||r.force==='true');
}
async function loadLeases(){
  const r=await call({op:'lease_list'});
  const ls=(r&&r.ok)?(r.leases||[]):[];
  $('#leaseList').innerHTML = ls.length? ls.map(x=>
    `<div class="kv"><span class="k">${esc(x.name||'جهاز')} <span class="sub">${esc(x.mac)}</span></span>`+
    `<span class="v">${esc(x.ip)} <button class="btn-ghost lsdel" data-mac="${esc(x.mac)}" style="font-size:11px;padding:2px 8px">حذف</button></span></div>`).join('')
    : '<div class="sub">لا حجوزات.</div>';
  $$('#leaseList .lsdel').forEach(b=>b.onclick=async()=>{ const x=await call({act:'lease_del',mac:b.dataset.mac},true);
    toast(x&&x.ok?'حُذف':'فشل',x&&x.ok); setTimeout(loadLeases,800); });
}
async function loadRoutes(){
  const r=await call({op:'route_list'});
  const rs=(r&&r.ok)?(r.routes||[]):[];
  $('#routeList').innerHTML = rs.length? rs.map(x=>
    `<div class="kv"><span class="k">${esc(x.target)}/${esc(x.mask)} → ${esc(x.gw)}</span>`+
    `<span class="v"><button class="btn-ghost rtdel" data-t="${esc(x.target)}" style="font-size:11px;padding:2px 8px">حذف</button></span></div>`).join('')
    : '<div class="sub">لا مسارات.</div>';
  $$('#routeList .rtdel').forEach(b=>b.onclick=async()=>{ const x=await call({act:'route_del',target:b.dataset.t},true);
    toast(x&&x.ok?'حُذف':'فشل',x&&x.ok); setTimeout(loadRoutes,800); });
}

/* ---------- INTERFACES overview (enable/disable + MTU) ---------- */
async function loadInterfaces(){
  const r=await call({op:'ifaces'});
  const ifs=(r&&r.ok)?(r.ifaces||[]):[];
  $('#ifaceList').innerHTML = ifs.length? ifs.map(x=>{
    const up=x.link==='up'; const en=x.enabled===true||x.enabled==='true';
    return `<div class="kv" style="flex-wrap:wrap"><span class="k">${esc(x.name)} <span class="sub">${esc(x.device||'')} · ${esc(x.proto||'')} · ${esc(x.ip||'—')}</span><br>`+
      `<span class="sub">MTU ${esc(x.mtu||'—')} · MAC ${esc(x.mac||'—')} · ↓${human(+x.rx)} ↑${human(+x.tx)}</span></span>`+
      `<span class="v" style="display:flex;gap:4px;align-items:center;flex-wrap:wrap">`+
      (up?'<span class="badge ok">up</span>':'<span class="badge bad">down</span>')+
      `<input class="t ifmtu" data-if="${esc(x.name)}" value="${esc(x.mtu||'1500')}" style="width:70px;padding:5px 7px;font-size:12px">`+
      `<button class="btn-ghost ifmtub" data-if="${esc(x.name)}" style="font-size:11px;padding:3px 8px">MTU</button>`+
      `<button class="btn-ghost iftgl" data-if="${esc(x.name)}" data-on="${en?'0':'1'}" style="font-size:11px;padding:3px 8px">${en?'تعطيل':'تفعيل'}</button>`+
      `</span></div>`;
  }).join('') : '<div class="sub">—</div>';
  $$('#ifaceList .iftgl').forEach(b=>b.onclick=async()=>{ const r=await safeApply(()=>call({act:'iface_toggle',iface:b.dataset.if,on:b.dataset.on},true));
    toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadInterfaces,1500); });
  $$('#ifaceList .ifmtub').forEach(b=>b.onclick=async()=>{ const inp=document.querySelector('.ifmtu[data-if="'+b.dataset.if+'"]');
    const r=await safeApply(()=>call({act:'iface_mtu',iface:b.dataset.if,mtu:inp?inp.value:''},true)); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); });
}

/* ---------- FIREWALL zones (masquerade/NAT + restart) ---------- */
async function loadZones(){
  const r=await call({op:'fw_zones'});
  const zs=(r&&r.ok)?(r.zones||[]):[];
  $('#zoneList').innerHTML = zs.length? zs.map(z=>{
    const masq=z.masq==='1'||z.masq===1||z.masq===true;
    return `<div class="kv" style="flex-wrap:wrap"><span class="k">${esc(z.name)} <span class="sub">in:${esc(z.input)} out:${esc(z.output)} fwd:${esc(z.forward)} · ${esc(z.network||'')}</span></span>`+
      `<span class="v"><button class="btn-ghost zmasq" data-z="${esc(z.name)}" data-on="${masq?'0':'1'}" style="font-size:11px;padding:3px 8px">${masq?'NAT ✓':'NAT ✕'}</button></span></div>`;
  }).join('') : '<div class="sub">—</div>';
  $$('#zoneList .zmasq').forEach(b=>b.onclick=async()=>{ const r=await safeApply(()=>call({act:'fw_masq',zone:b.dataset.z,on:b.dataset.on},true));
    toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadZones,1200); });
}

/* ---------- BLOCKED clients ---------- */
async function loadBlocked(){
  const r=await call({op:'blocklist'});
  const bs=(r&&r.ok)?(r.blocked||[]):[];
  $('#blockedBox').innerHTML = bs.length? bs.map(x=>
    `<div class="kv"><span class="k">${esc(x.mac)}</span><span class="v"><button class="btn-ghost unblk" data-mac="${esc(x.mac)}" style="font-size:11px;padding:2px 8px">رفع الحظر</button></span></div>`).join('')
    : '<div class="sub">لا أجهزة محظورة.</div>';
  $$('#blockedBox .unblk').forEach(b=>b.onclick=async()=>{ const r=await call({act:'client_unblock',mac:b.dataset.mac},true);
    toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(()=>{loadBlocked();loadClients();},800); });
}

/* ---------- SERVICES (guest / upnp / adblock / ddns / init) ---------- */
async function loadSvcStates(){
  const r=await call({op:'svc_states'}); if(!(r&&r.ok))return;
  const set=(id,on)=>{ const b=$(id); if(!b)return; b.textContent=on?'مفعّل ✓':'تفعيل'; b.dataset.on=on?'1':'0'; };
  set('#upnpToggle', r.upnp===true||r.upnp==='true');
  set('#adblockToggle', r.adblock===true||r.adblock==='true');
  if(r.ddns_domain)$('#dd_domain').value=r.ddns_domain;
}
async function loadSvcList(){
  const r=await call({op:'svc_list'});
  const ss=(r&&r.ok)?(r.services||[]):[];
  $('#svcList').innerHTML = ss.length? ss.map(x=>{
    const en=x.enabled===true||x.enabled==='true', rn=x.running===true||x.running==='true';
    return `<div class="kv"><span class="k">${esc(x.name)} ${rn?'<span class="badge ok">يعمل</span>':'<span class="badge bad">متوقف</span>'} ${en?'<span class="badge ok">تلقائي</span>':'<span class="badge warn">يدوي</span>'}</span>`+
    `<span class="v" style="display:flex;gap:4px;flex-wrap:wrap;justify-content:flex-end">`+
    `<button class="btn-ghost svcb" data-n="${esc(x.name)}" data-do="restart" style="font-size:11px;padding:2px 8px">↻</button>`+
    `<button class="btn-ghost svcb" data-n="${esc(x.name)}" data-do="${rn?'stop':'start'}" style="font-size:11px;padding:2px 8px">${rn?'إيقاف':'تشغيل'}</button>`+
    `<button class="btn-ghost svcb" data-n="${esc(x.name)}" data-do="${en?'disable':'enable'}" style="font-size:11px;padding:2px 8px">${en?'يدوي':'تلقائي'}</button>`+
    `</span></div>`;
  }).join('') : '<div class="sub">—</div>';
  $$('#svcList .svcb').forEach(b=>b.onclick=async()=>{ const x=await call({act:'svc_toggle',name:b.dataset.n,do:b.dataset.do},true);
    toast(x&&x.ok?(x.msg||'تم'):'فشل',x&&x.ok); setTimeout(loadSvcList,1000); });
}

/* ---------- TOOLS: diagnostics + packages ---------- */
async function runDiag(){
  const box=$('#diagBox'); box.classList.remove('hide'); box.textContent='جارٍ التشغيل…';
  const r=await call({op:'diag',type:$('#dg_type').value,target:$('#dg_target').value});
  box.textContent=(r&&r.ok)?(b64dec(r.out)||'(لا مخرجات)'):('فشل: '+((r&&r.error)||''));
}
let pkgAll=[];
async function loadPkgs(){
  $('#pkgBox').innerHTML='<div class="sub">جارٍ التحميل…</div>';
  const r=await call({op:'pkg_list'});
  if(!(r&&r.ok)){ $('#pkgBox').innerHTML='<div class="sub">تعذّر</div>'; return; }
  pkgAll=b64dec(r.list).split('\n').filter(Boolean); renderPkgs();
}
function renderPkgs(){
  const q=($('#pkg_search').value||'').toLowerCase();
  const list=pkgAll.filter(p=>!q||p.toLowerCase().indexOf(q)>=0).slice(0,300);
  $('#pkgBox').innerHTML = list.length? list.map(p=>
    `<div class="kv"><span class="k">${esc(p)}</span><span class="v"><button class="btn-ghost pkgdel" data-p="${esc(p)}" style="font-size:11px;padding:2px 8px">إزالة</button></span></div>`).join('')
    : '<div class="sub">لا نتائج</div>';
  $$('#pkgBox .pkgdel').forEach(b=>b.onclick=async()=>{ if(!confirm('إزالة '+b.dataset.p+'؟'))return;
    b.innerHTML='<span class="spin"></span>'; const x=await call({act:'pkg_remove',name:b.dataset.p},true);
    toast(x&&x.ok?(x.msg||'تم'):'فشل',x&&x.ok); setTimeout(loadPkgs,1500); });
}

/* ---------- CRON ---------- */
async function loadCron(){ const r=await call({op:'cron_get'}); if(r&&r.ok)$('#cronBox').value=b64dec(r.body); }

/* ---------- LIVE MONITOR ---------- */
async function loadMonitor(){
  const c=await call({op:'conns'});
  if(c&&c.ok){ const cnt=+c.count||0, mx=+c.max||1; const pct=Math.min(100,Math.round(cnt/mx*100));
    $('#mon_conn').innerHTML=cnt+'<small> اتصال نشط</small>'; $('#mon_connbar').style.width=pct+'%';
    $('#mon_connsub').textContent=cnt+' / '+mx+' ('+pct+'%)';
    $('#mon_conntop').textContent=b64dec(c.top)||'—'; }
  const s=await call({op:'stations'}); if(s&&s.ok)$('#mon_sta').textContent=b64dec(s.out)||'لا أجهزة لاسلكية';
  const u=await call({op:'usage'}); if(u&&u.ok)$('#mon_usage').textContent=b64dec(u.out)||'—';
  const p=await call({op:'procs'}); if(p&&p.ok)$('#mon_procs').textContent=b64dec(p.out)||'—';
  const r=await call({op:'routes'}); if(r&&r.ok)$('#mon_routes').textContent=b64dec(r.out)||'—';
}

/* ---------- nav (LuCI-style: category -> submenu -> single page) ---------- */
const MENU=[
  {cat:'الحالة', items:[
    {id:'quick',name:'إعدادات سريعة',i:'⚡'},
    {id:'dash',name:'نظرة عامة',i:'▦'},
    {id:'monitor',name:'الاتصالات والمراقبة',i:'📊'},
    {id:'health',name:'فحص الاتصال',i:'🩺'},
    {id:'smartap',name:'صحة Smart AP',i:'💚'},
    {id:'clients',name:'الأجهزة والإيجارات',i:'📱'},
    {id:'logs',name:'السجلّات',i:'📜'},
  ]},
  {cat:'الشبكة', items:[
    {id:'net',name:'الواجهات',i:'🌐'},
    {id:'wifi',name:'اللاسلكي',i:'📶'},
    {id:'firewall',name:'الجدار الناري وDNS',i:'🛡️'},
    {id:'ports',name:'منافذ DSA',i:'🔌'},
  ]},
  {cat:'الخدمات', items:[
    {id:'services',name:'الخدمات والضيوف',i:'🧩'},
    {id:'power',name:'قوة الإرسال',i:'⚡'},
  ]},
  {cat:'النظام', items:[
    {id:'system',name:'النظام والنسخ والترقية',i:'⚙️'},
    {id:'tools',name:'الأدوات والتشخيص',i:'🧰'},
  ]},
];
const PANE_LOAD={
  quick:loadQuick,
  dash:loadDash, monitor:loadMonitor, health:loadHealth, smartap:loadSmartap, clients:()=>{loadClients();loadDevices();}, logs:loadLogs,
  net:()=>{loadWan();loadLan();loadNetMode();loadVlan();loadInterfaces();},
  wifi:loadWifi, firewall:()=>{loadFw();loadDns();loadLeases();loadRoutes();loadZones();}, ports:loadPorts,
  services:()=>{loadSvcStates();loadSvcList();}, power:loadPower,
  system:()=>{loadSystem();loadCron();}, tools:()=>{},
};
let curPane='dash';
function renderSidebar(){
  let h='';
  MENU.forEach((m,gi)=>{
    h+=`<div class="side-group" data-g="${gi}">`+
       `<button class="side-cat" data-g="${gi}" aria-expanded="true"><span class="cat-t">${esc(m.cat)}</span><span class="cat-caret">▾</span></button>`+
       `<div class="side-items">`;
    m.items.forEach(it=>{ h+=`<button class="side-item" data-pane="${it.id}"><span class="si">${it.i}</span><span class="sn">${esc(it.name)}</span></button>`; });
    h+=`</div></div>`;
  });
  $('#sideNav').innerHTML=h;
  $$('#sideNav .side-item').forEach(b=>b.onclick=()=>{ selectPane(b.dataset.pane); closeDrawer(); });
  $$('#sideNav .side-cat').forEach(c=>c.onclick=()=>{
    const g=c.closest('.side-group'); const collapsed=g.classList.toggle('collapsed');
    c.setAttribute('aria-expanded', collapsed?'false':'true');
  });
}
function selectPane(id){
  curPane=id;
  let title=id; MENU.forEach(m=>m.items.forEach(it=>{ if(it.id===id)title=it.name; }));
  const pt=$('#pageTitle'); if(pt)pt.textContent=title;
  $$('#sideNav .side-item').forEach(b=>b.classList.toggle('active',b.dataset.pane===id));
  const ai=$('#sideNav .side-item.active'); if(ai){ const g=ai.closest('.side-group'); if(g)g.classList.remove('collapsed'); }
  $$('section[data-pane]').forEach(s=>s.classList.toggle('hide',s.dataset.pane!==id));
  const fn=PANE_LOAD[id]; if(fn)fn();
  if(id==='dash')setTimeout(drawChart,60);
}
function openDrawer(){ $('#side').classList.add('open'); $('#scrim').classList.add('show'); }
function closeDrawer(){ $('#side').classList.remove('open'); $('#scrim').classList.remove('show'); }
/* gauges + live chart */
function setGauge(id,pct,text){ const g=$('#'+id); if(!g)return; pct=Math.max(0,Math.min(100,pct||0));
  g.style.setProperty('--p',pct); const s=g.querySelector('span'); if(s)s.textContent=(text!=null?text:Math.round(pct)+'%'); }
const HIST=44; let dlH=[], ulH=[];
let _cpuIdlePrev=0, _cpuTotalPrev=0;
function drawChart(){
  const cv=$('#trafChart'); if(!cv||!cv.offsetWidth)return;
  const ctx=cv.getContext('2d'); const W=cv.width=cv.offsetWidth, H=cv.height=130;
  ctx.clearRect(0,0,W,H);
  const max=Math.max(1,...dlH,...ulH);
  ctx.strokeStyle='rgba(255,255,255,.06)'; ctx.lineWidth=1;
  for(let i=0;i<=4;i++){ const y=H*i/4; ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(W,y); ctx.stroke(); }
  const plot=(arr,col,fill)=>{ if(arr.length<2)return;
    ctx.beginPath(); arr.forEach((v,i)=>{ const x=W*i/(HIST-1), y=H-(v/max)*(H-10)-5; i?ctx.lineTo(x,y):ctx.moveTo(x,y); });
    ctx.strokeStyle=col; ctx.lineWidth=2.2; ctx.lineJoin='round'; ctx.stroke();
    ctx.lineTo(W*(arr.length-1)/(HIST-1),H); ctx.lineTo(0,H); ctx.closePath(); ctx.fillStyle=fill; ctx.fill(); };
  plot(dlH,'#3bc9db','rgba(59,201,219,.13)'); plot(ulH,'#ff6ba6','rgba(255,107,166,.13)');
}
function startLoop(){ if(timer)clearInterval(timer); let tick=0; timer=setInterval(()=>{
  // 3s cadence (lighter on the single-core CPU than 2s); heavy refreshes spaced out.
  if(curPane==='dash'){ loadSpeed(); if(tick%4===0)loadDash(); }
  else if(curPane==='net'||curPane==='ports'){ loadPortRates(); }
  else if(curPane==='clients'&&tick%4===0){ loadDevices(); }
  tick++;
},3000); }
/* rich device row: signal -> distance estimate */
function sigInfo(sig){
  const r=parseInt(sig,10); if(isNaN(r))return null;
  const d=Math.pow(10,((-50)-r)/(10*2.7));               // ref -50dBm@1m, n=2.7 (تقديري)
  let cls='near',lbl='قريب'; if(r<-75){cls='far';lbl='بعيد';} else if(r<-62){cls='mid';lbl='متوسط';}
  const pct=Math.max(5,Math.min(100,2*(r+100)));
  const col=cls==='near'?'var(--ok)':(cls==='mid'?'var(--warn)':'var(--bad)');
  return {dist:(d<1?'~1':'~'+d.toFixed(d<10?1:0)),cls,lbl,pct,col};
}
async function loadSmartap(){
  const r=await call({op:'selfheal'}); const b=$('#smartapBox');
  if(b)b.textContent=(r&&r.ok)?b64dec(r.out):'تعذّر التحميل';
}
async function loadDevices(){
  const r=await call({op:'devices'});
  const ds=(r&&r.ok)?(r.devices||[]):[];
  const fmtT=s=>{ s=+s||0; if(!s)return''; const h=Math.floor(s/3600),m=Math.floor((s%3600)/60); return h?(h+'س '+m+'د'):(m+'د'); };
  let head='';
  if(r&&r.ok) head=`<div class="ctrlrow" style="margin-bottom:10px"><div class="ci">📊</div>`+
    `<div class="cm"><b>استهلاك الباند (هذه الجلسة)</b><div class="sub">📶 2.4G: ${human(+r.band24||0)} &nbsp;·&nbsp; 📡 5G: ${human(+r.band5||0)}</div></div>`+
    `<div class="cr"><span class="badge ok">${ds.length} جهاز</span></div></div>`;
  if(!ds.length){ $('#devicesBox').innerHTML=head+'<div class="sub">لا أجهزة على الجسر حالياً</div>'; return; }
  $('#devicesBox').innerHTML=head+ds.map(x=>{
    const wifi=String(x.kind).indexOf('wifi')>=0; const band=x.kind==='wifi5g'?'5G':(x.kind==='wifi2g'?'2.4G':'');
    const ic=wifi?'<div class="dic w">📶</div>':'<div class="dic l">🔌</div>';
    let right='';
    if(wifi && x.signal){ const s=sigInfo(x.signal);
      if(s) right=`<span class="badge ${s.cls}">${s.lbl} ${s.dist}م</span>`+
        `<div class="sigbar"><i style="width:${s.pct}%;background:${s.col}"></i></div>`+
        `<span class="sub">${esc(x.signal)}dBm</span>`; }
    else right='<span class="badge ok">سلكي</span>';
    const rate=wifi&&(x.rxrate||x.txrate)?`<span class="sub">↓${esc(x.rxrate||'?')} ↑${esc(x.txrate||'?')} Mb</span>`:'';
    const usage=(+x.bytes)?`<span class="sub">⬇⬆ ${human(+x.bytes)}</span>`:'';
    const t=fmtT(x.conn), tt=t?`<span class="sub">⏱ ${t}</span>`:'';
    return `<div class="dev">${ic}<div class="dmain"><div class="dname">${esc(x.name||'جهاز')} ${band?'<span class="badge ok">'+band+'</span>':''}</div>`+
      `<div class="dmeta">${esc(x.ip||'—')} · ${esc(x.mac)}${x.dev?' · '+esc(x.dev):''} ${tt} ${usage}</div></div>`+
      `<div class="dright">${rate}${right}<button class="btn-ghost devblk" data-mac="${esc(x.mac)}" style="font-size:11px;padding:3px 8px">حظر</button></div></div>`;
  }).join('');
  $$('#devicesBox .devblk').forEach(b=>b.onclick=async()=>{ if(!confirm('حظر '+b.dataset.mac+'؟'))return;
    const r=await call({act:'client_block',mac:b.dataset.mac},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadDevices,800); });
}

/* ---------- wire up ---------- */
$('#loginBtn').onclick=doLogin;
$('#pw').addEventListener('keydown',e=>{if(e.key==='Enter')doLogin();});
$('#logoutBtn').onclick=logout;
$('#wanSeg').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
  wanMode=b.dataset.m; $$('#wanSeg button').forEach(x=>x.classList.toggle('active',x===b)); $('#wanForm').innerHTML=wanFormHtml(wanMode);});
$('#netModeSeg').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
  netMode=b.dataset.m; $$('#netModeSeg button').forEach(x=>x.classList.toggle('active',x===b));});
$('#netModeApply').onclick=async()=>{
  if(netMode==='ap' && !confirm('وضع Access Point: كل المنافذ تُجسَّر وDHCP يُعطَّل. الإدارة تبقى 192.168.100.1. متابعة؟'))return;
  const r=await safeApply(()=>call({act:'net_mode',mode:netMode},true));
  toast(r&&r.ok?(r.msg||'طُبّق — أكّد خلال 80ث'):('فشل: '+((r&&r.error)||'')),r&&r.ok);
};
$('#safeConfirmBtn').onclick=async()=>{ await call({act:'safe_confirm'},true); if(safeTimer)clearInterval(safeTimer); $('#safeBanner').classList.add('hide'); toast('تم الإبقاء على الإعدادات',true); };
$('#safeRestoreBtn').onclick=async()=>{ await call({act:'safe_restore'},true); if(safeTimer)clearInterval(safeTimer); $('#safeBanner').classList.add('hide'); toast('رجوع لآخر إعداد عامل…',true); setTimeout(()=>location.reload(),1500); };
$('#viewPower').onclick=()=>showReport('POWER-REPORT');
$('#viewRf').onclick=()=>showReport('RF-SOLUTION');
$('#runSuper').onclick=async()=>{ const r=await call({act:'super_check'},true); toast(r&&r.ok?(r.msg||'بدأ'):'فشل',r&&r.ok); if(r&&r.ok)pollSuper(); };
$('#wanApply').onclick=applyWan;
$('#wanReco').onclick=async()=>{const r=await call({act:'wan_reconnect'},true);toast(r.ok?'يُعاد الاتصال…':'فشل',r.ok);};
$('#wanVlanBtn').onclick=async()=>{const v=$('#w_vlan').value.trim();
  if(!v){toast('اكتب رقم VLAN',false);return;} const r=await call({act:'wan_vlan',vid:v},true);
  toast(r.ok?(r.msg||'تم'):('فشل: '+(r.error||'')),r.ok); if(r.ok)setTimeout(loadWan,1500);};
$('#dhcpSeg').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
  dhcpOn=b.dataset.d; $$('#dhcpSeg button').forEach(x=>x.classList.toggle('active',x===b));});
$('#lanApply').onclick=applyLan;
$('#vlanAdd').onclick=async()=>{ const vid=$('#vlanVid').value.trim();
  if(!vid||+vid<2||+vid>4094){toast('اكتب رقم VLAN بين 2 و 4094',false);return;}
  const gv=(id,d)=>{ const e=$(id); return e?e.value:d; };
  // simple mode: just a number -> isolated internet-only VLAN + DHCP. Advanced pane overrides.
  const mode=gv('#vlanMode','vlan');
  const routing = mode==='bridge' ? 'inter' : gv('#vlanRouting','internet');
  const nat = mode==='bridge' ? 'on' : gv('#vlanNat','on');
  // sane default: DHCP ON when the checkbox is absent/unchecked-by-default isn't desired
  const dhcp = $('#vlanDhcp') ? ($('#vlanDhcp').checked?1:0) : 1;
  const r=await safeApply(()=>call({act:'vlan_add',vid,ip:gv('#vlanIp',''),dhcp,
    routing,allow_vids:gv('#vlanAllow',''),nat,
    dns_mode:gv('#vlanDns','auto'),dns1:gv('#vlanDns1',''),dns2:gv('#vlanDns2','')},true));
  toast(r&&r.ok?(r.msg||'تم — أكّد خلال 80ث'):('فشل: '+((r&&r.error)||'')),r&&r.ok); if(r&&r.ok)setTimeout(loadVlan,1800); };
$('#vlanImport').onclick=async()=>{ const d=$('#vlanImportData').value.trim(); if(!d){toast('ألصق الإعداد',false);return;}
  let b64; try{ b64=btoa(unescape(encodeURIComponent(d))); }catch(e){ toast('نص غير صالح',false); return; }
  const r=await safeApply(()=>call({act:'vlan_import',config:b64},true));
  toast(r&&r.ok?(r.msg||'تم'):('فشل: '+((r&&r.error)||'')),r&&r.ok); if(r&&r.ok)setTimeout(loadVlan,1800); };
$('#vlanPortApply').onclick=async()=>{ const r=await safeApply(()=>call({act:'vlan_port',vid:$('#vlanPortVid').value,port:$('#vlanPortSel').value,mode:$('#vlanPortMode').value},true));
  toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); if(r&&r.ok)setTimeout(loadVlan,1800); };
$('#vlanSsidApply').onclick=async()=>{ const r=await safeApply(()=>call({act:'vlan_ssid',ssid:$('#vlanSsidSel').value,vid:$('#vlanSsidVid').value},true));
  toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); };
$('#vlanExport').onclick=async()=>{ const r=await call({op:'vlan_export'}); const box=$('#vlanExportBox'); box.classList.remove('hide'); box.textContent=(r&&r.ok)?(b64dec(r.config)||'(فارغ)'):'تعذّر'; };
$('#vlanReset').onclick=async()=>{ if(!confirm('إعادة ضبط كل VLANs؟ (الإدارة تبقى سليمة)'))return;
  const r=await safeApply(()=>call({act:'vlan_reset'},true)); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); if(r&&r.ok)setTimeout(loadVlan,1800); };
$('#clRefresh').onclick=loadClients;
$('#scanBtn').onclick=loadScan;
$('#hRefresh').onclick=loadHealth;
$('#logRefresh').onclick=loadLogs;
$('#logSeg').addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
  logKind=b.dataset.l; $$('#logSeg button').forEach(x=>x.classList.toggle('active',x===b)); loadLogs();});
$('#pwApply').onclick=async()=>{
  const a=$('#s_pw1').value,b=$('#s_pw2').value;
  if(!a){toast('اكتب كلمة المرور',false);return;} if(a!==b){toast('كلمتا المرور غير متطابقتين',false);return;}
  const r=await call({act:'sys_passwd',newpass:a},true);
  toast(r.ok?'تم تغيير كلمة المرور':('فشل: '+(r.error||'')),r.ok); if(r.ok){$('#s_pw1').value='';$('#s_pw2').value='';loadSystem();}};
$('#hostApply').onclick=async()=>{const r=await call({act:'sys_hostname',hostname:$('#s_host').value},true);
  toast(r.ok?(r.msg||'تم'):'فشل',r.ok);};
$('#tzApply').onclick=async()=>{const r=await call({act:'sys_timezone',tz:$('#s_tz').value},true);
  toast(r.ok?(r.msg||'تم'):'فشل',r.ok);};
$('#fwUpload').onclick=async()=>{
  const f=$('#fwFile').files[0];
  if(!f){ toast('اختر ملف الفيرموير أولاً',false); return; }
  const m=$('#fwMsg'); m.classList.remove('hide'); m.textContent='جارٍ الرفع والفحص…';
  const b=$('#fwUpload'); b.disabled=true; $('#fwFlash').disabled=true;
  try{
    const r=await fetch(API_FW+'?act=upload&token='+encodeURIComponent(TOKEN),{method:'POST',body:f});
    const j=await r.json(); b.disabled=false;
    if(!j.ok){ m.textContent='فشل الرفع: '+(j.error||''); return; }
    const mb=(j.size/1048576).toFixed(1);
    if(j.valid){ m.innerHTML='✅ الملف صالح ومتوافق مع الجهاز ('+mb+' MB). اضغط «تفليش الآن».'; fwForce=0; $('#fwFlash').disabled=false; }
    else { m.innerHTML='⚠ الملف غير مُتحقق لهذا الجهاز ('+mb+' MB): '+esc(j.detail||'')+'<br>التفليش بالإجبار متاح على مسؤوليتك.'; fwForce=1; $('#fwFlash').disabled=false; }
  }catch(e){ b.disabled=false; m.textContent='خطأ شبكة أثناء الرفع'; }
};
$('#fwFlash').onclick=async()=>{
  if(!confirm('تفليش الفيرموير الآن؟ سيُعاد تشغيل الجهاز ويعود على 192.168.100.1'))return;
  const keep=$('#fwKeep').checked?1:0;
  try{
    const r=await fetch(API_FW+'?act=flash&keep='+keep+'&force='+fwForce+'&token='+encodeURIComponent(TOKEN),{method:'POST'});
    const j=await r.json();
    toast(j.ok?(j.msg||'يُفلَّش…'):('فشل: '+(j.error||'')), j.ok);
  }catch(e){ toast('بدأ التفليش — انتظر ~3 دقائق ثم افتح 192.168.100.1', true); }
};
$('#rebootBtn').onclick=async()=>{ if(!confirm('إعادة تشغيل الراوتر الآن؟'))return;
  const r=await call({act:'reboot'},true); toast(r.ok?'يُعاد التشغيل…':'فشل',r.ok); };
$('#factoryBtn').onclick=async()=>{ if(!confirm('تحذير: ضبط المصنع يمسح كل الإعدادات. متابعة؟'))return;
  const r=await call({act:'factory'},true); toast(r.ok?'ضبط مصنع + إعادة تشغيل…':'فشل',r.ok); };

/* ---------- wire up: firewall / dns / leases / routes ---------- */
$('#fwAdd').onclick=async()=>{ const r=await call({act:'fw_forward',name:$('#fw_name').value,proto:$('#fw_proto').value,sport:$('#fw_sport').value,dip:$('#fw_dip').value,dport:$('#fw_dport').value},true);
  toast(r&&r.ok?(r.msg||'تم'):('فشل: '+((r&&r.error)||'')),r&&r.ok); if(r&&r.ok)setTimeout(loadFw,800); };
$('#fwDmzBtn').onclick=async()=>{ const r=await call({act:'fw_dmz',ip:$('#fw_dmz').value},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); };
$('#dnsApply').onclick=async()=>{ const r=await call({act:'dns_set',dns1:$('#dns1').value,dns2:$('#dns2').value,force:$('#dnsForce').checked?'1':'0'},true);
  toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); };
$('#leaseAdd').onclick=async()=>{ const r=await call({act:'lease_add',mac:$('#ls_mac').value,ip:$('#ls_ip').value,name:$('#ls_name').value},true);
  toast(r&&r.ok?(r.msg||'تم'):('فشل: '+((r&&r.error)||'')),r&&r.ok); if(r&&r.ok)setTimeout(loadLeases,800); };
$('#routeAdd').onclick=async()=>{ const r=await call({act:'route_add',target:$('#rt_target').value,mask:$('#rt_mask').value,gw:$('#rt_gw').value,iface:'lan'},true);
  toast(r&&r.ok?(r.msg||'تم'):('فشل: '+((r&&r.error)||'')),r&&r.ok); if(r&&r.ok)setTimeout(loadRoutes,800); };

/* ---------- wire up: services ---------- */
$('#guestOn').onclick=async()=>{ const r=await call({act:'guest_wifi',enabled:'1',ssid:$('#g_ssid').value,key:$('#g_key').value},true);
  toast(r&&r.ok?(r.msg||'تم'):('فشل: '+((r&&r.error)||'')),r&&r.ok); setTimeout(loadSvcStates,1200); };
$('#guestOff').onclick=async()=>{ if(!confirm('إيقاف شبكة الضيوف؟'))return; const r=await call({act:'guest_wifi',enabled:'0'},true);
  toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadSvcStates,1200); };
$('#upnpToggle').onclick=async()=>{ const on=$('#upnpToggle').dataset.on==='1'?'0':'1';
  const r=await call({act:'upnp_toggle',enabled:on},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadSvcStates,800); };
$('#adblockToggle').onclick=async()=>{ const on=$('#adblockToggle').dataset.on==='1'?'0':'1';
  const r=await call({act:'adblock_toggle',enabled:on},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); setTimeout(loadSvcStates,800); };
$('#ddnsApply').onclick=async()=>{ const r=await call({act:'ddns_set',provider:$('#dd_provider').value,domain:$('#dd_domain').value,user:$('#dd_user').value,pass:$('#dd_pass').value},true);
  toast(r&&r.ok?(r.msg||'تم'):('فشل: '+((r&&r.error)||'')),r&&r.ok); };

/* ---------- wire up: tools (diag + packages) ---------- */
$('#diagRun').onclick=runDiag;
$('#speedBtn').onclick=async()=>{ const el=$('#speedRes'); el.textContent='جارٍ القياس… (~15ث)'; const b=$('#speedBtn'); b.disabled=true;
  const r=await call({op:'speedtest'}); b.disabled=false;
  if(r&&r.ok&&+r.bps>0){ el.innerHTML=(+r.bps*8/1e6).toFixed(1)+'<small> Mbps ↓</small>'; } else el.textContent='تعذّر القياس'; };
$('#monRefresh').onclick=loadMonitor;
$('#menuToggle').onclick=openDrawer;
$('#scrim').onclick=closeDrawer;
$('#devRefresh').onclick=loadDevices;
if($('#smartapRef')) $('#smartapRef').onclick=loadSmartap;
if($('#sqmOn')) $('#sqmOn').onclick=async()=>{ const r=await call({act:'sqm',enabled:1,down:$('#sqm_dn').value,up:$('#sqm_up').value},true);
  toast(r&&r.ok?(r.msg||'تم تفعيل SQM'):'فشل',r&&r.ok); };
if($('#sqmOff')) $('#sqmOff').onclick=async()=>{ const r=await call({act:'sqm',enabled:0,down:$('#sqm_dn').value,up:$('#sqm_up').value},true);
  toast(r&&r.ok?(r.msg||'تم إيقاف SQM'):'فشل',r&&r.ok); };
if($('#qs_tx')) $('#qs_tx').oninput=()=>{ const v=$('#qs_txv'); if(v)v.textContent=$('#qs_tx').value; };
if($('#qs_mode')) $('#qs_mode').onchange=()=>{ const p=$('#qs_pppoe_row'); if(p)p.style.display=($('#qs_mode').value==='pppoe')?'flex':'none'; };
if($('#qsApply')) $('#qsApply').onclick=async()=>{
  const v=id=>{ const e=$(id); return e?e.value:''; };
  const r=await safeApply(()=>call({act:'quick_setup',mode:v('#qs_mode'),ssid:v('#qs_ssid'),pass:v('#qs_pass'),
    country:v('#qs_country'),txpower:v('#qs_tx'),lan_ip:v('#qs_lan'),ch24:v('#qs_ch24'),ch5:v('#qs_ch5'),
    pppoe_user:v('#qs_pu'),pppoe_pass:v('#qs_pp')},true));
  const vlan=v('#qs_vlan').trim();
  if(r&&r.ok&&vlan) await call({act:'vlan_add',vid:vlan,routing:'internet',nat:'on',dns_mode:'auto'},true);
  toast(r&&r.ok?(r.msg||'تم — أكّد خلال 80ث'):('فشل: '+((r&&r.error)||'')),r&&r.ok);
};
window.addEventListener('resize',()=>{ if(curPane==='dash')drawChart(); });
/* interfaces / firewall zones / ntp / logs filter+search+download */
$('#ntpApply').onclick=async()=>{ const r=await call({act:'ntp_set',ntp1:$('#s_ntp1').value,ntp2:$('#s_ntp2').value},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); };
$('#fwRestart').onclick=async()=>{ const r=await call({act:'fw_restart'},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); };
$('#logFilter').addEventListener('change',loadLogs);
$('#logSearch').addEventListener('input',renderLog);
$('#logDownload').onclick=()=>{ const t=window._logRaw||$('#logBox').textContent||''; const a=document.createElement('a');
  a.href='data:text/plain;charset=utf-8,'+encodeURIComponent(t); a.download='kt412-log.txt'; document.body.appendChild(a); a.click(); a.remove(); };
$('#pkgRefresh').onclick=loadPkgs;
$('#pkg_search').addEventListener('input',renderPkgs);
$('#pkgInstall').onclick=async()=>{ const n=$('#pkg_name').value.trim(); if(!n){toast('اكتب اسم الحزمة',false);return;}
  toast('جارٍ التثبيت…',true); const r=await call({act:'pkg_install',name:n},true);
  toast(r&&r.ok?(r.msg||'تم'):('فشل: '+((r&&r.error)||'')),r&&r.ok); if(r&&r.ok)setTimeout(loadPkgs,1500); };

/* ---------- wire up: cron / backup / restore ---------- */
$('#cronSave').onclick=async()=>{ let b64; try{b64=btoa(unescape(encodeURIComponent($('#cronBox').value)));}catch(e){toast('نص غير صالح',false);return;}
  const r=await call({act:'cron_set',body:b64},true); toast(r&&r.ok?(r.msg||'تم'):'فشل',r&&r.ok); };
$('#backupBtn').onclick=async()=>{ const r=await call({op:'backup_make'}); if(!(r&&r.ok)){toast('فشل النسخ',false);return;}
  const a=document.createElement('a'); a.href='data:application/gzip;base64,'+r.data; a.download='kt412-backup.tar.gz';
  document.body.appendChild(a); a.click(); a.remove(); toast('تم تنزيل النسخة الاحتياطية',true); };
$('#restoreBtn').onclick=async()=>{ const f=$('#restoreFile').files[0]; if(!f){toast('اختر ملف النسخة',false);return;}
  if(!confirm('استعادة الإعدادات من الملف؟ ستُستبدل الإعدادات الحالية.'))return;
  const buf=await f.arrayBuffer(); const u8=new Uint8Array(buf); let bin='';
  for(let i=0;i<u8.length;i++)bin+=String.fromCharCode(u8[i]);
  const r=await call({act:'restore_cfg',body:btoa(bin)},true);
  toast(r&&r.ok?(r.msg||'تمت الاستعادة'):('فشل: '+((r&&r.error)||'')),r&&r.ok);
  if(r&&r.ok)setTimeout(()=>location.reload(),2500); };

/* boot */
(async function(){
  if(TOKEN){ const s=await call({op:'summary'}); if(s&&s.ok){ showApp(); return; } TOKEN=''; sessionStorage.removeItem('kt412tok'); }
  $('#login').classList.remove('hide');
})();
