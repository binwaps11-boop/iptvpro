'use strict';
'require view';
'require poll';

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
function gColor(p){ p=+p; if (p<60) return 'var(--mk-green)'; if (p<85) return 'var(--mk-amber)'; return 'var(--mk-red)'; }

/* ---- circular gauge (inline SVG) ---- */
function gauge(id, label, pct, meta){
	pct = clamp(pct,0,100);
	var R = 52, C = 2*Math.PI*R, off = C*(1-pct/100);
	return ''
		+ '<div class="mk-gauge" data-gid="'+id+'">'
		+ '<svg viewBox="0 0 128 128" aria-hidden="true">'
		+   '<circle class="track" cx="64" cy="64" r="'+R+'"></circle>'
		+   '<circle class="arc" cx="64" cy="64" r="'+R+'" '
		+     'stroke="'+gColor(pct)+'" stroke-dasharray="'+C.toFixed(1)+'" '
		+     'stroke-dashoffset="'+off.toFixed(1)+'"></circle>'
		+   '<g class="mk-gtext"><text class="mk-gval" x="64" y="62" text-anchor="middle">'+Math.round(pct)+'<tspan font-size="14">%</tspan></text></g>'
		+ '</svg>'
		+ '<div class="mk-glabel">'+esc(label)+'</div>'
		+ '<div class="mk-gmeta">'+esc(meta||'')+'</div>'
		+ '</div>';
}
function updateGauge(root, id, pct, meta){
	var g = root.querySelector('.mk-gauge[data-gid="'+id+'"]'); if (!g) return;
	pct = clamp(pct,0,100);
	var R=52, C=2*Math.PI*R, off=C*(1-pct/100);
	var arc = g.querySelector('.arc'); arc.setAttribute('stroke-dashoffset', off.toFixed(1)); arc.setAttribute('stroke', gColor(pct));
	g.querySelector('.mk-gval').firstChild.nodeValue = String(Math.round(pct));
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

/* ---- interface tiles ---- */
function ifTile(name, label, icon, up, meta){
	return '<div class="mk-iftile '+(up?'up':'down')+'">'
		+ '<span class="led"></span>'
		+ '<div class="ico">'+icon+'</div>'
		+ '<div class="nm">'+esc(label)+'</div>'
		+ '<div class="st">'+esc(up?(meta||'متصل'):'غير متصل')+'</div>'
		+ '</div>';
}

function shell(){
	var skinOff = (localStorage.getItem(SKIN_KEY)==='off');
	return ''
	+ '<div class="mk-wrap">'
	+ '  <div class="mk-head">'
	+ '    <div><div class="mk-logo">KT412 · MK</div><div class="mk-sub">لوحة التحكم الذكية — Smart Dashboard</div></div>'
	+ '    <div class="mk-spacer"></div>'
	+ '    <div class="mk-toggle'+(skinOff?'':' on')+'" id="mk-skin-toggle" title="تبديل الواجهة الزجاجية / Bootstrap">'
	+ '      <span class="sw"><i></i></span><span>الواجهة الزجاجية</span>'
	+ '    </div>'
	+ '  </div>'
	+ '  <div class="mk-grid mk-cols-3" id="mk-gauges">'
	+ '    <div class="mk-card">'+gauge('cpu','المعالج CPU',0,'—')+'</div>'
	+ '    <div class="mk-card">'+gauge('ram','الذاكرة RAM',0,'—')+'</div>'
	+ '    <div class="mk-card">'+gauge('disk','التخزين Storage',0,'—')+'</div>'
	+ '  </div>'
	+ '  <div class="mk-grid mk-cols-2" style="margin-top:16px">'
	+ '    <div class="mk-card">'
	+ '      <h3>📈 حركة الشبكة — RX / TX <span class="mk-hint" id="mk-wif"></span></h3>'
	+ '      <svg class="mk-spark" viewBox="0 0 320 80" preserveAspectRatio="none" id="mk-spark">'
	+ '        <line class="mk-spark-axis" x1="0" y1="40" x2="320" y2="40"></line>'
	+ '        <g id="mk-spark-rx"></g><g id="mk-spark-tx"></g>'
	+ '      </svg>'
	+ '      <div class="mk-traffic-rates">'
	+ '        <div class="mk-rate rx"><span class="dot"></span>تنزيل RX <b id="mk-rx">—</b></div>'
	+ '        <div class="mk-rate tx"><span class="dot"></span>رفع TX <b id="mk-tx">—</b></div>'
	+ '      </div>'
	+ '      <div class="mk-errs" id="mk-errs"></div>'
	+ '    </div>'
	+ '    <div class="mk-card">'
	+ '      <h3>🔌 الواجهات النشطة — Interfaces</h3>'
	+ '      <div class="mk-iftiles" id="mk-iftiles"><div class="mk-load">…</div></div>'
	+ '    </div>'
	+ '  </div>'
	+ '  <div class="mk-card mk-power" id="mk-power" style="margin-top:16px">'
	+ '    <h3>⚡ استقرار الطاقة — Power &amp; Voltage</h3>'
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
	return Promise.all([ call({op:'summary'}), call({op:'traffic'}), call({op:'ports'}) ])
	.then(function(res){
		var sm = res[0]||{}, tr = res[1]||{}, pt = res[2]||{};

		/* ----- gauges ----- */
		if (sm.ok){
			var cpu = +sm.cpu_pct||0;
			var mt=+sm.mem_total||0, mf=+sm.mem_free||0, mb=+sm.mem_buf||0;
			var used = mt - mf - mb; var ramP = mt>0 ? (100*used/mt) : 0;
			var ft=+sm.fs_total||0, fu=+sm.fs_used||0; var dP = ft>0 ? (100*fu/ft) : 0;
			updateGauge(root,'cpu',cpu,'حِمل '+(sm.load? (sm.load/65536).toFixed(2):'—'));
			updateGauge(root,'ram',ramP, fmtBytes(used*1024)+' / '+fmtBytes(mt*1024));
			updateGauge(root,'disk',dP, fmtBytes(fu*1024)+' / '+fmtBytes(ft*1024));
		}

		/* ----- power / voltage advisory ----- */
		var pb = root.querySelector('#mk-power-badge'), pc = root.querySelector('#mk-power');
		if (pb && pc){
			if (tr.ok && +tr.undervolt === 1){
				pc.classList.add('alert');
				pb.className = 'mk-pwr-badge bad';
				pb.textContent = '⚠ تحذير: رُصد هبوط جهد / إعادة تشغيل — Under-voltage / brown-out detected';
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
					+ (clean?' — سليمة ✓':'');
			}
		}

		/* ----- interface tiles ----- */
		var tilesEl = root.querySelector('#mk-iftiles');
		if (tilesEl){
			var html = '';
			var pmap = {};
			if (pt.ok && Array.isArray(pt.ports)) pt.ports.forEach(function(p){ pmap[p.name]=p; });
			var lanDefs = [['lan1','LAN1'],['lan2','LAN2'],['lan3','LAN3'],['lan4','LAN4']];
			lanDefs.forEach(function(d){
				var p = pmap[d[0]]; var up = p && p.link==='up';
				html += ifTile(d[0], d[1], '🖧', up, up && p.speed ? (p.speed+'Mb') : '');
			});
			var w = pmap['wan']; var wup = w && w.link==='up';
			html += ifTile('wan','WAN','🌐', wup, wup && w.speed ? (w.speed+'Mb') : '');
			// wifi radios from traffic ifaces (wlan*/phy*/ath*)
			var wifis = (tr.ok && tr.ifaces ? tr.ifaces : []).filter(function(x){ return /^(wlan|ath|phy|wl)/.test(x['if']); });
			if (wifis.length){
				wifis.forEach(function(x,i){
					html += ifTile(x['if'], (i===0?'WiFi 2.4G':'WiFi 5G'), '📶', true, '');
				});
			} else {
				html += ifTile('wifi','WiFi','📶', false, '');
			}
			tilesEl.innerHTML = html;
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
		poll.add(function(){ return refresh(root); }, 4);
		return root;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
