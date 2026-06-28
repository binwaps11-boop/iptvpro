'use strict';
'require view';
'require poll';

/* ---- KT412 professional inline-icon set (replaces emoji). currentColor,
   crisp line style. ktIc(name) -> DOM <svg> node for E() child arrays;
   ktIcSvg(name) -> string for innerHTML template contexts. ---- */
var KTI={
wifi:'<path d="M5 12.55a11 11 0 0 1 14 0"/><path d="M8.5 16.1a6 6 0 0 1 7 0"/><path d="M2 9a15 15 0 0 1 20 0"/><path d="M12 20h.01"/>',
radio:'<path d="M4.93 19.07A10 10 0 0 1 19.07 4.93"/><path d="M7.76 16.24a6 6 0 0 1 8.48-8.48"/><circle cx="12" cy="12" r="2"/>',
bolt:'<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 0 1 0 18 M12 3a15 15 0 0 0 0 18"/>',
plug:'<path d="M9 2v6 M15 2v6 M7 8h10v2a5 5 0 0 1-10 0z M12 15v7"/>',
tag:'<path d="M3 7v5l9 9 7-7-9-9z"/><circle cx="7.5" cy="11.5" r="1.2"/>',
down:'<path d="M12 5v14 M6 13l6 6 6-6"/>',
up:'<path d="M12 19V5 M6 11l6-6 6 6"/>',
speed:'<path d="M3 17l6-6 4 4 8-8 M15 7h6v6"/>',
search:'<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
edit:'<path d="M12 20h9 M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
monitor:'<rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8 M12 17v4"/>',
phone:'<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>',
users:'<circle cx="9" cy="8" r="3"/><path d="M3 20a6 6 0 0 1 12 0 M17 6a3 3 0 0 1 0 6 M22 20a6 6 0 0 0-4-5.7"/>',
user:'<circle cx="12" cy="8" r="3.2"/><path d="M5 20a7 7 0 0 1 14 0"/>',
lock:'<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
unlock:'<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V7.5A4 4 0 0 1 15 5"/>',
mesh:'<circle cx="6" cy="6" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><path d="M7.6 7.6 11 16 M16.4 7.6 13 16 M8 6h8"/>',
link:'<path d="M9 15 15 9 M10 6l1-1a4 4 0 0 1 6 6l-1 1 M14 18l-1 1a4 4 0 0 1-6-6l1-1"/>',
warn:'<path d="M12 3 2 20h20z M12 9v5 M12 17h.01"/>',
check:'<path d="M20 6 9 17l-5-5"/>',
timer:'<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2 M9 2h6"/>',
gear:'<circle cx="12" cy="12" r="3"/><path d="M12 2v3 M12 19v3 M2 12h3 M19 12h3 M4.9 4.9l2.1 2.1 M17 17l2.1 2.1 M19.1 4.9 17 7 M7 17l-2.1 2.1"/>',
ruler:'<path d="M3 17 17 3l4 4L7 21z M7 9l2 2 M11 5l2 2 M13 13l2 2"/>',
refresh:'<path d="M3 12a9 9 0 0 1 15-6l3 3 M21 6v5h-5 M21 12a9 9 0 0 1-15 6l-3-3 M3 18v-5h5"/>',
swap:'<path d="M7 8 3 12l4 4 M17 8l4 4-4 4 M3 12h18"/>',
ban:'<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>',
question:'<circle cx="12" cy="12" r="9"/><path d="M9.6 9a2.5 2.5 0 0 1 4.4 1.6c0 1.6-2 2-2 3.4 M12 17h.01"/>',
eye:'<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="2.5"/>',
box:'<path d="M21 8 12 3 3 8v8l9 5 9-5z M3 8l9 5 9-5 M12 13v8"/>',
health:'<path d="M3 4v6a4 4 0 0 0 8 0V4 M7 20a3 3 0 0 0 3-3v-2 M17 14a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"/>',
compass:'<circle cx="12" cy="12" r="9"/><path d="m15 9-2 6-4 0 2-6z"/>',
save:'<path d="M5 3h12l4 4v14H5z M8 3v5h7 M8 21v-6h8v6"/>',
cpu:'<rect x="7" y="7" width="10" height="10" rx="2"/><path d="M9 3v2 M15 3v2 M9 19v2 M15 19v2 M3 9h2 M3 15h2 M19 9h2 M19 15h2"/>',
star:'<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17.8 6.6 20l1-6.1L3.2 9.5l6.1-.9z"/>',
dot:'<circle cx="12" cy="12" r="5"/>'
};
function ktIcSvg(n){return '<svg class="kti" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(KTI[n]||KTI.dot)+'</svg>';}
function ktIc(n){var d=document.createElement('div');d.innerHTML=ktIcSvg(n);return d.firstChild;}

/* ============================================================================
   KT412 / MK APP — modern dashboard home (glassmorphism, RTL Arabic).
   Set as the admin index in menu.d/luci-app-kt412-dash.json so it loads first.
   Reuses the shared backend /cgi-bin/kt412:
     op=summary  -> cpu_pct, mem_total/free/buf, fs_total/used, model/uptime
     op=traffic  -> per-iface rx/tx bytes + rx_err/rx_drop/tx_err/tx_drop
     op=ports    -> wan / lan1..4 link state
   All client-side rendering; styling lives in kt412-mk/theme-mk.css.
   Theme kill-switch: a toggle sets <html data-mk-skin> + localStorage so the
   custom cascade can fall back to plain bootstrap for troubleshooting.
   ============================================================================ */

var API = '/cgi-bin/kt412';
var TOKEN = '';
var SKIN_KEY = 'kt412_mk_skin';

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c];}); }
function clamp(n,a,b){ n=+n; if(isNaN(n)) n=a; return n<a?a:(n>b?b:n); }

function adopt(){
	if (TOKEN) return Promise.resolve(TOKEN);
	var sid = (L.env && L.env.sessionid) ? L.env.sessionid : '';
	return fetch(API, {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:'op=adopt&token='+encodeURIComponent(sid)})
		.then(function(r){ return r.json(); })
		.then(function(j){ if (j && j.ok && j.token) TOKEN = j.token; return TOKEN; })
		.catch(function(){ return ''; });
}
function call(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API + '?' + usp.toString()).then(function(r){ return r.json(); }).catch(function(){ return {ok:false}; });
	});
}

/* ---- formatting helpers ---- */
function fmtBytes(b){
	b = +b || 0; var u = ['B','KB','MB','GB','TB']; var i = 0;
	while (b >= 1024 && i < u.length-1){ b/=1024; i++; }
	return (b<10 && i>0 ? b.toFixed(1) : Math.round(b)) + ' ' + u[i];
}
function fmtRate(bps){ return fmtBytes(bps) + '/s'; }
function fmtUptime(s){
	s = +s||0; var d=Math.floor(s/86400), h=Math.floor((s%86400)/3600), m=Math.floor((s%3600)/60);
	if (d) return d+' يوم '+h+' س'; if (h) return h+' س '+m+' د'; return m+' دقيقة';
}
/* ---- tiny inline SVG icon set (currentColor stroked) ---- */
function ic(name){
	var p = {
		cpu:    '<rect x="4.5" y="4.5" width="15" height="15" rx="2"/><rect x="8.5" y="8.5" width="7" height="7" rx="1"/><path d="M9 1.5v3M12 1.5v3M15 1.5v3M9 19.5v3M12 19.5v3M15 19.5v3M1.5 9h3M1.5 12h3M1.5 15h3M19.5 9h3M19.5 12h3M19.5 15h3"/>',
		ram:    '<rect x="2.5" y="7" width="19" height="10" rx="1.5"/><path d="M6 7v-2M10 7v-2M14 7v-2M18 7v-2M6 22v-5M18 22v-5"/><path d="M6.5 11h2M11 11h2M15.5 11h2"/>',
		disk:   '<path d="M3 8l2-4h14l2 4"/><rect x="3" y="8" width="18" height="11" rx="2"/><circle cx="8" cy="13.5" r="1.4"/><path d="M12 12.5h6M12 15h6"/>',
		net:    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.6 2.4 4 5.6 4 9s-1.4 6.6-4 9c-2.6-2.4-4-5.6-4-9s1.4-6.6 4-9z"/>',
		ports:  '<rect x="3" y="9" width="18" height="11" rx="2"/><path d="M8 9V6a4 4 0 0 1 8 0v3M8 13v3M12 13v3M16 13v3"/>',
		power:  '<path d="M13 2L4.5 13.5H11l-1 8.5L19.5 10H13z"/>',
		up:     '<path d="M12 19V5M5 12l7-7 7 7"/>',
		down:   '<path d="M12 5v14M5 12l7 7 7-7"/>',
		clock:  '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
		chip:   '<rect x="5" y="5" width="14" height="14" rx="2"/><path d="M9 1.5v3M15 1.5v3M9 19.5v3M15 19.5v3M1.5 9h3M1.5 15h3M19.5 9h3M19.5 15h3"/>',
		fw:     '<path d="M12 2l8 3v6c0 5-3.4 8.4-8 11-4.6-2.6-8-6-8-11V5z"/><path d="M9 12l2 2 4-4"/>',
		users:  '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 20a5.5 5.5 0 0 1 11 0"/><path d="M16 5.2a3.2 3.2 0 0 1 0 5.6M16.5 13.5a5.5 5.5 0 0 1 4 6.5"/>',
		wifi:   '<path d="M2 8.5a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8 15.5a5 5 0 0 1 8 0"/><circle cx="12" cy="19.5" r="1.3" fill="currentColor" stroke="none"/>',
		lan:    '<rect x="6" y="3" width="12" height="18" rx="1.5"/><path d="M9 3v-1h6v1M9 21v1h6v-1M6 8h-2M6 12h-2M6 16h-2M20 8h-2M20 12h-2M20 16h-2"/>',
		err:    '<path d="M12 2l10 18H2z"/><path d="M12 9v5M12 17.5v.5" stroke-linecap="round"/>',
		check:  '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.5 2.5 5.5-6"/>'
	};
	// INTRINSIC width/height attributes so the icon can NEVER balloon if the CSS
	// size rule is slow/missing (that was the giant-plug/huge-icon bug on desktop).
	// CSS .mk-ic / context rules can still scale it down where needed.
	return '<svg class="mk-ic" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" '
		+ 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(p[name]||'')+'</svg>';
}
/* status chip for the header bar */
function chip(icon, label, value, cls){
	return '<div class="mk-chip '+(cls||'')+'">'+ic(icon)
		+ '<span class="ck">'+esc(label)+'</span>'
		+ '<b class="cv">'+esc(value)+'</b></div>';
}
/* section header: icon + title + subtle divider */
function section(icon, title, sub){
	return '<div class="mk-sec">'+ic(icon)
		+ '<div class="mk-sec-t"><span class="t">'+esc(title)+'</span>'
		+ (sub?'<span class="s">'+esc(sub)+'</span>':'')+'</div>'
		+ '<span class="mk-sec-rule"></span></div>';
}

/* per-gauge base neon accent: CPU=cyan, RAM=green, Storage/Flash=purple */
var GAUGE_BASE = { cpu:'#06B6D4', ram:'#22C55E', disk:'#8b5cf6' };
/* arc colour: keep each gauge's neon identity at normal load, but escalate to
   amber (high) / crimson (critical) so the user still sees pressure. */
function gColor(p, id){ p=+p;
	if (p>=85) return '#EF4444';                 /* crimson — critical */
	if (p>=70) return '#F59E0B';                 /* amber  — high load */
	return GAUGE_BASE[id] || '#06B6D4';          /* neon identity      */
}

/* ---- circular gauge (inline SVG) ---- */
function gauge(id, label, icon, pct, meta){
	pct = clamp(pct,0,100);
	var R = 52, C = 2*Math.PI*R, off = C*(1-pct/100);
	return ''
		+ '<div class="mk-gauge" data-gid="'+id+'">'
		+ '<div class="mk-gring">'
		// width/height + fill="none" are set INLINE (not only via CSS) so the gauge can
		// never render as a giant 60vw black disk if the stylesheet is slow/absent.
		// No rotation on the <svg> or a counter-rotated text group (that flung the % out
		// of view): only the arc is rotated, via a transform ATTRIBUTE around (64,64), so
		// the % value stays upright and centered.
		+ '<svg width="124" height="124" viewBox="0 0 128 128" aria-hidden="true">'
		+   '<circle class="track" cx="64" cy="64" r="'+R+'" fill="none" stroke="#334155" stroke-width="11"></circle>'
		+   '<circle class="arc" cx="64" cy="64" r="'+R+'" fill="none" stroke-width="11" stroke-linecap="round" transform="rotate(-90 64 64)" '
		+     'stroke="'+gColor(pct,id)+'" stroke-dasharray="'+C.toFixed(1)+'" '
		+     'stroke-dashoffset="'+off.toFixed(1)+'"></circle>'
		+   '<text class="mk-gval" x="64" y="60" text-anchor="middle" dominant-baseline="central">'+Math.round(pct)+'<tspan class="mk-gunit" font-size="15" dy="-1">%</tspan></text>'
		+   '<text class="mk-gcap" x="64" y="84" text-anchor="middle" dominant-baseline="central">USAGE</text>'
		+ '</svg>'
		+ '</div>'
		+ '<div class="mk-glabel">'+ic(icon)+'<span>'+esc(label)+'</span></div>'
		+ '<div class="mk-gmeta">'+esc(meta||'')+'</div>'
		+ '</div>';
}
function updateGauge(root, id, pct, meta){
	var g = root.querySelector('.mk-gauge[data-gid="'+id+'"]'); if (!g) return;
	/* pct null or <0 => "warming up": show "--", grey ring, no % — never a fake number. */
	var ready = (pct != null && pct >= 0);
	var p = ready ? clamp(pct,0,100) : 0;
	var R=52, C=2*Math.PI*R, off=C*(1-p/100);
	var arc = g.querySelector('.arc'); arc.setAttribute('stroke-dashoffset', off.toFixed(1));
	arc.setAttribute('stroke', ready ? gColor(p,id) : '#475569');
	g.querySelector('.mk-gval').firstChild.nodeValue = ready ? String(Math.round(p)) : '--';
	var unit = g.querySelector('.mk-gunit'); if (unit) unit.style.display = ready ? '' : 'none';
	if (meta!=null) g.querySelector('.mk-gmeta').textContent = meta;
}

/* ---- sparkline (RTL: newest sample at the LEFT edge) ---- */
function sparkline(values, color){
	var W=320, H=80, n=values.length, max=1;
	for (var i=0;i<n;i++) if (values[i]>max) max=values[i];
	var pts=[];
	for (var j=0;j<n;j++){
		var x = W - (j/(Math.max(1,n-1)))*W;          // newest (j=0) on the left
		var y = H - (values[j]/max)*(H-6) - 3;
		pts.push(x.toFixed(1)+','+y.toFixed(1));
	}
	var line = pts.join(' ');
	var area = (n>1) ? ('M '+pts[0]+' L '+line.split(' ').slice(1).join(' L ')+' L 0,'+H+' L '+W+','+H+' Z') : '';
	return '<polyline fill="none" stroke="'+color+'" stroke-width="2" points="'+line+'"></polyline>'
		+ (area?('<path d="'+area+'" fill="'+color+'" opacity="0.12"></path>'):'');
}

/* WAN-ish interface picker for the traffic graph */
function pickWanIf(ifaces){
	var names = ifaces.map(function(x){return x['if'];});
	var prefs = ['pppoe-wan','wan','eth1','eth0'];
	for (var i=0;i<prefs.length;i++) if (names.indexOf(prefs[i])>=0) return prefs[i];
	// else the busiest non-loopback
	var best=null, bv=-1;
	ifaces.forEach(function(x){ var t=(+x.rx)+(+x.tx); if (t>bv){bv=t; best=x['if'];} });
	return best;
}

var ST = { last:null, lastTs:0, rxHist:[], txHist:[], wif:null, errs:null };
var HIST = 40;

/* ---- interface / RJ45 port tiles ----
   plugged (up) -> neon green tile + a small speed badge (1000/100 Mbps);
   unplugged (down) -> dark slate grey, dim. `speed` is Mbps (e.g. 1000/100). */
function ifTile(name, label, icon, up, speed, kind){
	var spd = up && speed ? (+speed>=1000?'1000':(''+speed)) : '';
	var badge = (up && speed)
		? '<span class="spd '+(+speed>=1000?'gig':'fe')+'">'+esc(spd)+'<i>Mbps</i></span>'
		: (up ? '<span class="spd link">●<i>link</i></span>' : '<span class="spd off">—</span>');
	return '<div class="mk-iftile '+(kind||'rj45')+' '+(up?'up':'down')+'">'
		+ '<span class="led"></span>'
		+ '<div class="ico">'+ic(icon)+'</div>'
		+ '<div class="nm">'+esc(label)+'</div>'
		+ '<div class="st">'+esc(up?'متصل':'غير متصل')+'</div>'
		+ badge
		+ '</div>';
}

function shell(){
	var skinOff = (localStorage.getItem(SKIN_KEY)==='off');
	return ''
	+ '<div class="mk-wrap">'
	/* ===== premium top HEADER bar ===== */
	+ '  <div class="mk-topbar">'
	+ '    <div class="mk-brand">'
	+ '      <div class="mk-mark">'+ic('wifi')+'</div>'
	+ '      <div class="mk-brand-t">'
	+ '        <div class="mk-logo">Smart AP</div>'
	+ '        <div class="mk-sub">لوحة التحكم الذكية — Smart Control Panel</div>'
	+ '      </div>'
	+ '    </div>'
	+ '    <div class="mk-spacer"></div>'
	+ '    <div class="mk-toggle'+(skinOff?'':' on')+'" id="mk-skin-toggle" title="تبديل الواجهة الزجاجية / Bootstrap">'
	+ '      <span class="sw"><i></i></span><span>الواجهة الزجاجية</span>'
	+ '    </div>'
	+ '  </div>'
	/* status chip row */
	+ '  <div class="mk-chips" id="mk-chips">'
	+      chip('clock','التشغيل','—','c-up')
	+      chip('chip','الطراز','—','c-model')
	+      chip('fw','الإصدار','—','c-fw')
	+      chip('users','الأجهزة','—','c-clients')
	+      chip('wifi','2.4G','—','c-w24')
	+      chip('wifi','5G','—','c-w5')
	+      chip('clock','آخر تحديث','—','c-upd')
	+ '  </div>'

	/* ===== النظام — System gauges ===== */
	+      section('cpu','النظام','System · CPU / RAM / Storage')
	+ '  <div class="mk-grid mk-cols-3" id="mk-gauges">'
	+ '    <div class="mk-card mk-gcard">'+gauge('cpu','استخدام المعالج CPU','cpu',0,'—')+'</div>'
	+ '    <div class="mk-card mk-gcard">'+gauge('ram','استخدام الذاكرة RAM','ram',0,'—')+'</div>'
	+ '    <div class="mk-card mk-gcard">'+gauge('disk','استخدام التخزين Storage','disk',0,'—')+'</div>'
	+ '  </div>'

	/* ===== الشبكة — Network ===== */
	+      section('net','الشبكة','Network · Traffic & Errors')
	+ '  <div class="mk-grid mk-cols-2">'
	+ '    <div class="mk-card mk-traffic">'
	+ '      <h3>'+ic('net')+'<span>حركة الشبكة — RX / TX</span><span class="mk-hint" id="mk-wif"></span></h3>'
	+ '      <svg class="mk-spark" viewBox="0 0 320 80" preserveAspectRatio="none" id="mk-spark">'
	+ '        <defs>'
	+ '          <linearGradient id="mk-gr-rx" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#06B6D4" stop-opacity="0.32"/><stop offset="1" stop-color="#06B6D4" stop-opacity="0"/></linearGradient>'
	+ '          <linearGradient id="mk-gr-tx" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8b5cf6" stop-opacity="0.30"/><stop offset="1" stop-color="#8b5cf6" stop-opacity="0"/></linearGradient>'
	+ '        </defs>'
	+ '        <g class="mk-spark-grid">'
	+ '          <line x1="0" y1="20" x2="320" y2="20"></line>'
	+ '          <line x1="0" y1="40" x2="320" y2="40" class="mk-spark-axis"></line>'
	+ '          <line x1="0" y1="60" x2="320" y2="60"></line>'
	+ '        </g>'
	+ '        <g id="mk-spark-rx"></g><g id="mk-spark-tx"></g>'
	+ '      </svg>'
	+ '      <div class="mk-traffic-rates">'
	+ '        <div class="mk-rate rx"><span class="ri">'+ic('down')+'</span><span class="rl">تنزيل RX</span><b id="mk-rx">—</b></div>'
	+ '        <div class="mk-rate tx"><span class="ri">'+ic('up')+'</span><span class="rl">رفع TX</span><b id="mk-tx">—</b></div>'
	+ '      </div>'
	+ '      <div class="mk-errs" id="mk-errs"></div>'
	+ '    </div>'
	+ '    <div class="mk-card mk-portcard">'
	+ '      <h3>'+ic('ports')+'<span>الواجهات النشطة — Interfaces</span></h3>'
	+ '      <div class="mk-iftiles mk-iftiles-net" id="mk-iftiles-net"><div class="mk-load">…</div></div>'
	+ '    </div>'
	+ '  </div>'

	/* ===== المنافذ — RJ45 port map ===== */
	+      section('ports','المنافذ','Ports · RJ45 Map & Radios')
	+ '  <div class="mk-card mk-portmap">'
	+ '    <div class="mk-iftiles" id="mk-iftiles"><div class="mk-load">…</div></div>'
	+ '  </div>'

	/* ===== الطاقة — Power ===== */
	+      section('power','الطاقة','Power · Voltage Stability')
	+ '  <div class="mk-card mk-power" id="mk-power">'
	+ '    <div id="mk-power-badge" class="mk-pwr-badge info">معلومة — Info</div>'
	+ '    <div class="mk-pwr-text">'
	+ '      تأكد من مصدر طاقة مستقر <b>12V 1.5A/2A</b> لتفادي سقوط الواي فاي تحت الحمل.'
	+ '      <br><span class="mk-hint">Ensure a stable 12V 1.5A/2A supply to prevent wireless drops under load.</span>'
	+ '    </div>'
	+ '  </div>'
	+ '</div>';
}

function applySkin(off){
	var html = document.documentElement;
	if (off){ html.setAttribute('data-mk-skin','off'); localStorage.setItem(SKIN_KEY,'off'); }
	else { html.removeAttribute('data-mk-skin'); localStorage.setItem(SKIN_KEY,'on'); }
}

function wireToggle(root){
	var t = root.querySelector('#mk-skin-toggle');
	if (!t) return;
	t.addEventListener('click', function(){
		var off = t.classList.toggle('on') === false;  // toggled OFF -> skin off
		applySkin(off);
	});
}

function refresh(root){
	/* CPU saver: gauges + traffic need a live read every cycle, but the RJ45
	   port map (operstate per port) changes rarely. Fetch op=ports only every
	   3rd cycle (~30s) and reuse the cached result in between, so each idle
	   refresh forks 2 CGIs instead of 3 -> ~33% fewer forks on the 720MHz core. */
	var needPorts = ((ST.cyc|0) % 3) === 0; ST.cyc = (ST.cyc|0) + 1;
	return Promise.all([ call({op:'summary'}), call({op:'traffic'}),
		needPorts ? call({op:'ports'}) : Promise.resolve(ST.lastPorts||{}) ])
	.then(function(res){
		var sm = res[0]||{}, tr = res[1]||{};
		var pt = (needPorts && res[2] && res[2].ok) ? res[2] : (ST.lastPorts||{});
		if (needPorts && res[2] && res[2].ok) ST.lastPorts = res[2];

		/* stale/disconnected indicator: after >=2 consecutive failed reads, dim the
		   header chips so a dead link/device is obvious (no silent stale numbers). */
		ST.fail = sm.ok ? 0 : ((ST.fail|0) + 1);
		var chipsEl = root.querySelector('.mk-chips');
		if (chipsEl){ if (ST.fail >= 2) chipsEl.classList.add('mk-stale'); else chipsEl.classList.remove('mk-stale'); }

		/* ----- gauges (truthful readings) ----- */
		if (sm.ok){
			/* CPU: backend sends -1 = "warming up" (no /proc/stat baseline yet). Show
			   "--" then, NEVER a fake 100%. loadavg is shown only as a caption, not as %. */
			var cpu = (sm.cpu_pct==null || +sm.cpu_pct < 0) ? null : +sm.cpu_pct;
			/* RAM: used = MemTotal - MemAvailable (kernel's real in-use, cache excluded).
			   Falls back to total-free-buffers only if mem_avail is missing. */
			var mt=+sm.mem_total||0, mf=+sm.mem_free||0, mb=+sm.mem_buf||0, ma=+sm.mem_avail||0;
			var used = ma>0 ? (mt-ma) : (mt-mf-mb); if (used<0) used=0;
			var ramP = mt>0 ? (100*used/mt) : 0;
			/* Storage = OVERLAY (user-writable). rootfs/squashfs is read-only and always
			   ~100% by design — backend already reports /overlay, never the firmware image. */
			var ft=+sm.fs_total||0, fu=+sm.fs_used||0; var dP = ft>0 ? (100*fu/ft) : 0;
			updateGauge(root,'cpu',cpu,'الحِمل '+(sm.load? (sm.load/65536).toFixed(2):'—'));
			updateGauge(root,'ram',ramP, fmtBytes(used*1024)+' / '+fmtBytes(mt*1024));
			updateGauge(root,'disk',dP, 'Overlay · '+fmtBytes(fu*1024)+' / '+fmtBytes(ft*1024));
		}

		/* ----- header status chips ----- */
		function setChip(cls, val, on){
			var c = root.querySelector('.mk-chip.'+cls); if (!c) return;
			c.querySelector('.cv').textContent = val;
			if (on===true) c.classList.add('ok'); else if (on===false) c.classList.remove('ok');
		}
		if (sm.ok){
			setChip('c-up', fmtUptime(sm.uptime));
			setChip('c-model', sm.model ? String(sm.model).replace(/^.*\s/,'').slice(0,18) || sm.model : '—');
			setChip('c-fw', sm.fw || sm.firmware || sm.release || (sm.openwrt? 'OpenWrt '+sm.openwrt : '—'));
			/* live "last updated" stamp so the operator sees the data is fresh */
			var d=new Date(), z=function(n){return (n<10?'0':'')+n;};
			setChip('c-upd', z(d.getHours())+':'+z(d.getMinutes())+':'+z(d.getSeconds()));
		}
		/* radios (2.4G / 5G) presence from traffic ifaces */
		var radios = (tr.ok && tr.ifaces ? tr.ifaces : []).filter(function(x){ return /^(wlan|ath|phy|wl)/.test(x['if']); });
		setChip('c-w24', radios.length>=1 ? 'يعمل' : 'مغلق', radios.length>=1);
		setChip('c-w5',  radios.length>=2 ? 'يعمل' : (radios.length>=1?'—':'مغلق'), radios.length>=2);
		/* connected clients: REAL count (unique associated Wi-Fi stations + wired
		   neighbours) from op=summary — was wrongly showing the RADIO count, so one
		   device read as "2". Fall back to the old estimate only if the field is absent. */
		if (sm.ok && sm.clients != null){
			setChip('c-clients', String(sm.clients));
		} else if (pt.ok && Array.isArray(pt.ports)){
			var linkedLan = pt.ports.filter(function(p){ return /^lan/.test(p.name) && p.link==='up'; }).length;
			setChip('c-clients', String(linkedLan));
		}

		/* ----- power / voltage advisory ----- */
		var pb = root.querySelector('#mk-power-badge'), pc = root.querySelector('#mk-power');
		if (pb && pc){
			if (tr.ok && +tr.undervolt === 1){
				pc.classList.add('alert');
				pb.className = 'mk-pwr-badge bad';
				pb.innerHTML = ktIcSvg('warn')+' تحذير: رُصد هبوط جهد / إعادة تشغيل — Under-voltage / brown-out detected';
			} else {
				pc.classList.remove('alert');
				pb.className = 'mk-pwr-badge info';
				pb.textContent = 'الحالة سليمة — لا توجد إشارات هبوط جهد · OK';
			}
		}

		/* ----- traffic ----- */
		if (tr.ok && Array.isArray(tr.ifaces)){
			if (!ST.wif) ST.wif = pickWanIf(tr.ifaces);
			var cur = tr.ifaces.filter(function(x){return x['if']===ST.wif;})[0] || tr.ifaces[0];
			var wifEl = root.querySelector('#mk-wif'); if (wifEl && cur) wifEl.textContent = '('+esc(cur['if'])+')';
			if (cur){
				var ts = +tr.ts || (Date.now()/1000);
				if (ST.last && ST.lastTs && ts>ST.lastTs){
					var dt = ts - ST.lastTs;
					var rxr = Math.max(0,(+cur.rx - +ST.last.rx)/dt);
					var txr = Math.max(0,(+cur.tx - +ST.last.tx)/dt);
					ST.rxHist.unshift(rxr); ST.txHist.unshift(txr);
					if (ST.rxHist.length>HIST){ ST.rxHist.pop(); ST.txHist.pop(); }
					root.querySelector('#mk-rx').textContent = fmtRate(rxr);
					root.querySelector('#mk-tx').textContent = fmtRate(txr);
					root.querySelector('#mk-spark-rx').innerHTML = sparkline(ST.rxHist,'var(--mk-cyan)');
					root.querySelector('#mk-spark-tx').innerHTML = sparkline(ST.txHist,'var(--mk-violet)');
				}
				ST.last = { rx:+cur.rx, tx:+cur.tx }; ST.lastTs = ts;
				var te = (+cur.rx_err||0)+(+cur.tx_err||0), td = (+cur.rx_drop||0)+(+cur.tx_drop||0);
				var clean = (te===0 && td===0);
				root.querySelector('#mk-errs').innerHTML =
					'الأخطاء: <span class="'+(te?'bad':'ok')+'">'+te+'</span> · '
					+ 'المسقطة: <span class="'+(td?'bad':'ok')+'">'+td+'</span>'
					+ (clean?' — سليمة '+ktIcSvg('check'):'');
			}
		}

		/* ----- interface tiles: full RJ45 port map + radios ----- */
		var pmap = {};
		if (pt.ok && Array.isArray(pt.ports)) pt.ports.forEach(function(p){ pmap[p.name]=p; });
		var wifis = (tr.ok && tr.ifaces ? tr.ifaces : []).filter(function(x){ return /^(wlan|ath|phy|wl)/.test(x['if']); });

		var tilesEl = root.querySelector('#mk-iftiles');
		if (tilesEl){
			var html = '';
			var w = pmap['wan']; var wup = w && w.link==='up';
			html += ifTile('wan','WAN','net', wup, wup && w.speed ? w.speed : '', 'rj45 wan');
			var lanDefs = [['lan1','LAN 1'],['lan2','LAN 2'],['lan3','LAN 3'],['lan4','LAN 4']];
			lanDefs.forEach(function(d){
				var p = pmap[d[0]]; var up = p && p.link==='up';
				html += ifTile(d[0], d[1], 'lan', up, up && p.speed ? p.speed : '', 'rj45');
			});
			// wifi radios from traffic ifaces (wlan*/phy*/ath*) rendered as device tiles
			if (wifis.length){
				wifis.forEach(function(x,i){
					html += ifTile(x['if'], (i===0?'WiFi 2.4G':'WiFi 5G'), 'wifi', true, '', 'radio');
				});
			} else {
				html += ifTile('wifi','WiFi','wifi', false, '', 'radio');
			}
			tilesEl.innerHTML = html;
		}

		/* ----- compact interface summary inside the Network card ----- */
		var netTilesEl = root.querySelector('#mk-iftiles-net');
		if (netTilesEl){
			var nh = '';
			var wn = pmap['wan']; var wnup = wn && wn.link==='up';
			nh += ifTile('wan','WAN','net', wnup, wnup && wn.speed ? wn.speed : '', 'rj45 wan');
			var lanUp = (pt.ok && Array.isArray(pt.ports)) ? pt.ports.filter(function(p){ return /^lan/.test(p.name) && p.link==='up'; }).length : 0;
			nh += '<div class="mk-iftile rj45 '+(lanUp?'up':'down')+'"><span class="led"></span>'
				+ '<div class="ico">'+ic('ports')+'</div><div class="nm">LAN</div>'
				+ '<div class="st">'+lanUp+' / 4 نشط</div>'
				+ '<span class="spd '+(lanUp?'link':'off')+'">'+(lanUp?lanUp+'×':'—')+'<i>up</i></span></div>';
			if (wifis.length){
				wifis.forEach(function(x,i){
					nh += ifTile(x['if'], (i===0?'2.4G':'5G'), 'wifi', true, '', 'radio');
				});
			} else {
				nh += ifTile('wifi','WiFi','wifi', false, '', 'radio');
			}
			netTilesEl.innerHTML = nh;
		}
	});
}

return view.extend({
	load: function(){ return Promise.resolve(); },
	render: function(){
		// apply persisted skin preference immediately
		applySkin(localStorage.getItem(SKIN_KEY)==='off');
		var root = E('div', {});
		root.innerHTML = shell();
		wireToggle(root);
		refresh(root);
		// Poll every 20s with TWO CPU guards the single-core QCA9558 needs:
		//   1) overlap guard — never start a new refresh while the previous set of
		//      CGI calls is still in flight (no request pile-up).
		//   2) visibility guard — skip polling entirely while the tab is hidden
		//      (background tab / phone screen off) so it consumes zero CPU then.
		// Poll every 5s so CPU/RAM/traffic update LIVE without reopening the page.
		// The sampler daemon writes a fresh point every 3s and the backend caches the
		// heavy iwinfo sweep 30s, so 5s stays responsive yet cheap. Guards below keep
		// it from piling up (inflight) and from polling a hidden tab (document.hidden).
		var inflight = false;
		poll.add(function(){
			if (inflight) return Promise.resolve();
			if (typeof document !== 'undefined' && document.hidden) return Promise.resolve();
			inflight = true;
			return refresh(root).then(function(){ inflight = false; }, function(){ inflight = false; });
		}, 5);
		return root;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
