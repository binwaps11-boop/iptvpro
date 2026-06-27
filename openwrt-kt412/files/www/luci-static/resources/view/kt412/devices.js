'use strict';
'require view';
'require poll';

/* KT412 Smart AP — Devices (الأجهزة المتصلة) LuCI view.
   Reuses the EXISTING backend op=devices. Renders the same device rows
   (type / signal / distance) as the old dashboard. */

var API = '/cgi-bin/kt412';
var TOKEN = '';

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c];}); }

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
		return fetch(API + '?' + usp.toString()).then(function(r){ return r.json(); })
			/* invalidate a stale session so the NEXT poll re-adopts instead of
			   failing forever; reset only on an explicit auth error to avoid
			   adopt storms on the single core. */
			.then(function(j){ if (j && j.ok===false && (j.error==='unauthorized'||j.error==='no_token')) TOKEN=''; return j; })
			.catch(function(){ return {ok:false}; });
	});
}

function sigColor(s){ s = +s; if (s >= -60) return 'var(--kt-ok)'; if (s >= -72) return 'var(--kt-warn)'; return 'var(--kt-bad)'; }

function devRow(x){
	var isWifi = String(x.kind||'').indexOf('wifi') >= 0;
	var band = x.kind==='wifi5g' ? '5G' : (x.kind==='wifi2g' ? '2.4G' : 'سلكي');
	var icon = isWifi ? '📶' : '🔌';
	var sig = (isWifi && x.signal) ? (esc(x.signal)+'dBm'+(x.dist?(' · '+esc(x.dist)):'')) : '';
	var pct = (isWifi && x.signal) ? Math.max(0, Math.min(100, 2*((+x.signal||-100)+100))) : 0;
	return '<div class="kt-dev">'
		+ '<div class="dic">'+icon+'</div>'
		+ '<div class="dmain"><div class="dname">'+esc(x.name||'جهاز')+' <span class="kt-badge ok">'+band+'</span></div>'
		+ '<div class="dmeta">'+esc(x.ip||'—')+' · '+esc(x.mac||'')+(sig?(' · '+sig):'')+'</div></div>'
		+ (isWifi && x.signal ? '<div class="kt-sigbar"><i style="width:'+pct+'%;background:'+sigColor(x.signal)+'"></i></div>' : '')
		+ '</div>';
}

function reload(container){
	return call({op:'devices'}).then(function(c){
		if (!(c && c.ok)){ container.innerHTML = '<div class="kt-sub">تعذّر التحميل</div>'; return; }
		var ds = c.devices || [];
		var online = ds.filter(function(d){ return +d.online === 1; });
		var n24 = online.filter(function(d){ return d.kind==='wifi2g'; }).length;
		var n5  = online.filter(function(d){ return d.kind==='wifi5g'; }).length;
		var wired = online.filter(function(d){ return String(d.kind||'').indexOf('wifi') < 0; }).length;
		container.innerHTML =
			'<div class="kt-grid kt-cols-4">'
			+ '<div class="kt-tile kt-t-blue"><div class="ti">📱</div><div class="tn">'+online.length+'</div><div class="tl">أجهزة متصلة</div></div>'
			+ '<div class="kt-tile kt-t-green"><div class="ti">📶</div><div class="tn">'+n24+'</div><div class="tl">واي‑فاي 2.4G</div></div>'
			+ '<div class="kt-tile kt-t-cyan"><div class="ti">📡</div><div class="tn">'+n5+'</div><div class="tl">واي‑فاي 5G</div></div>'
			+ '<div class="kt-tile kt-t-orange"><div class="ti">🔌</div><div class="tn">'+wired+'</div><div class="tl">سلكية</div></div>'
			+ '</div>'
			+ '<div class="kt-card"><h3>🌐 كل الأجهزة على الشبكة — النوع · الإشارة · المسافة</h3>'
			+ (online.length ? online.map(devRow).join('') : '<div class="kt-sub">لا أجهزة متصلة</div>')
			+ '</div>';
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('الأجهزة المتصلة — Devices')),
			E('div', { 'class':'kt-body' }, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')))
		]);
		var body = box.querySelector('.kt-body');
		reload(body);
		poll.add(function(){ return reload(body); }, 10);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
