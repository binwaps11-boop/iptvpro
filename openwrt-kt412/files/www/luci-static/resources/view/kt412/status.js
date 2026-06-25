'use strict';
'require view';
'require poll';

/* KT412 Smart AP — Status / Mesh (الحالة وmesh) LuCI view.
   Reuses existing backend ops: summary, health, ports, mesh_status.
   Renders gauges (CPU/RAM/Storage) + health pings + link speeds + mesh peers. */

var API = '/cgi-bin/kt412';
var TOKEN = '';

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c];}); }
function human(b){ b = +b||0; var u=['B','KB','MB','GB','TB'], i=0; while(b>=1024&&i<u.length-1){b/=1024;i++;} return b.toFixed(b<10&&i>0?1:0)+' '+u[i]; }
function dur(s){ s=+s||0; var d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60); if(d>0)return d+'ي '+h+'س'; if(h>0)return h+'س '+m+'د'; return m+'د'; }

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

function gauge(p, color, label, sub){
	p = Math.max(0, Math.min(100, Math.round(+p||0)));
	return '<div class="kt-card kt-gcard"><div class="kt-gauge" style="--p:'+p+';--gc:'+color+'"><span>'+p+'%</span></div>'
		+ '<div class="kt-glabel">'+label+'</div><div class="kt-sub">'+esc(sub||'')+'</div></div>';
}

function reload(container){
	return Promise.all([ call({op:'summary'}), call({op:'health'}), call({op:'ports'}), call({op:'mesh_status'}) ])
	.then(function(res){
		var s=res[0], h=res[1], p=res[2], me=res[3];
		var html = '';

		/* gauges */
		var gauges = '';
		if (s && s.ok){
			var used = (+s.mem_total)-(+s.mem_free)-(+s.mem_buf);
			var memPct = s.mem_total>0 ? Math.round(used/s.mem_total*100) : 0;
			var cpuPct = Math.max(0, Math.min(100, Math.round(+s.cpu_pct||0)));
			var stoPct = (s.fs_total && +s.fs_total>0) ? Math.round(+s.fs_used/+s.fs_total*100) : 0;
			gauges = gauge(cpuPct, 'var(--kt-accent)', 'المعالج / الحِمل', (s.ncpu?(s.ncpu+' نواة'):''))
				+ gauge(memPct, '#b07cff', 'الذاكرة (RAM)', human(used)+' / '+human(s.mem_total))
				+ gauge(stoPct, '#37d39b', 'التخزين', (s.fs_total? (human(+s.fs_used*1024)+' / '+human(+s.fs_total*1024)) : '—'))
				+ '<div class="kt-card"><h3>🖥️ النظام</h3><div class="kt-kv"><span class="k">الموديل</span><span class="v">'+esc(s.model||'KT412')+'</span></div>'
				+ '<div class="kt-kv"><span class="k">الإصدار</span><span class="v">'+esc(s.release||'')+'</span></div>'
				+ '<div class="kt-kv"><span class="k">التشغيل</span><span class="v">⏱ '+dur(s.uptime)+'</span></div></div>';
		}
		html += '<div class="kt-grid kt-cols-4">'+(gauges||'<div class="kt-sub">—</div>')+'</div>';

		/* health + links */
		var healthHtml = '<div class="kt-sub">—</div>';
		if (h && h.ok){
			var row = function(n,o){ var g=(+o.loss)<100; return '<div class="kt-kv"><span class="k">'+n+'</span><span class="v">'
				+ (g?('<span class="kt-badge ok">'+esc(o.rtt)+' ms</span>'):'<span class="kt-badge bad">منقطع</span>')+'</span></div>'; };
			healthHtml = row('Cloudflare 1.1.1.1', h.cf) + row('Google 8.8.8.8', h.goog)
				+ '<div class="kt-kv"><span class="k">Multi‑WAN online</span><span class="v">'+esc(h.mwan_online)+'</span></div>';
		}
		var linksHtml = '<div class="kt-sub">—</div>';
		if (p && p.ok){
			linksHtml = (p.ports||[]).map(function(x){ return '<div class="kt-kv"><span class="k">'+esc(x.name)+'</span><span class="v">'
				+ (x.link==='up' ? (x.speed ? (esc(x.speed)+' Mbps') : 'متصل') : 'مفصول')+'</span></div>'; }).join('') || '<div class="kt-sub">—</div>';
		}
		html += '<div class="kt-grid kt-cols-2">'
			+ '<div class="kt-card"><h3>🩺 حالة الاتصال</h3>'+healthHtml+'</div>'
			+ '<div class="kt-card"><h3>🔗 سرعة الارتباط (Link)</h3>'+linksHtml+'</div></div>';

		/* mesh */
		var ms = (me && me.ok) ? (me.mesh||[]) : [];
		if (ms.length){
			var meshHtml = ms.map(function(m){
				var peers = (m.peers||[]).map(function(pr){ return '<div class="kt-kv"><span class="k">'+esc(pr.mac)+'</span><span class="v">'
					+ esc(pr.signal||'?')+'dBm · ↓'+esc(pr.rxrate||'?')+'/↑'+esc(pr.txrate||'?')+' Mbps</span></div>'; }).join('')
					|| '<div class="kt-sub">لا أقران (peers) متصلين</div>';
				return '<div class="kt-kv"><span class="k">Mesh ID</span><span class="v"><b>'+esc(m.mesh_id||'—')+'</b> · '+esc(m.iface)+'</span></div>'
					+ '<div class="kt-kv"><span class="k">عدد الأقران</span><span class="v"><span class="kt-badge '+(+m.peer_count>0?'ok':'warn')+'">'+esc(m.peer_count)+'</span></span></div>'+peers;
			}).join('');
			html += '<div class="kt-card"><h3>🕸️ حالة Mesh (802.11s)</h3>'+meshHtml+'</div>';
		} else {
			html += '<div class="kt-card"><h3>🕸️ حالة Mesh (802.11s)</h3><div class="kt-sub">لا توجد واجهة Mesh نشطة (الوضع AP حالياً)</div></div>';
		}

		container.innerHTML = html;
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('الحالة و Mesh — Status')),
			E('div', { 'class':'kt-body' }, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')))
		]);
		var body = box.querySelector('.kt-body');
		reload(body);
		poll.add(function(){ return reload(body); }, 8);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
