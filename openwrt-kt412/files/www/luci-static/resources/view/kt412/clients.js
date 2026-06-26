'use strict';
'require view';
'require poll';

/* KT412 Smart AP — Clients & Control (الأجهزة والتحكم) LuCI view.
   Lists every device (op=devices) with usage, and lets the user block /
   unblock each MAC (act=block / act=unblock) against the current denylist
   (op=blocked). Offline-but-blocked MACs are shown as dim rows so they can
   be un-blocked too. */

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
		return fetch(API + '?' + usp.toString()).then(function(r){ return r.json(); }).catch(function(){ return {ok:false}; });
	});
}
function postCall(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API, {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:usp.toString()})
			.then(function(r){ return r.json(); }).catch(function(){ return {ok:false}; });
	});
}

function sigColor(s){ s = +s; if (s >= -60) return 'var(--kt-ok)'; if (s >= -72) return 'var(--kt-warn)'; return 'var(--kt-bad)'; }

function fmtBytes(n){
	n = +n || 0;
	if (n < 1024) return n.toFixed(0)+' B';
	if (n < 1048576) return (n/1024).toFixed(1)+' KB';
	if (n < 1073741824) return (n/1048576).toFixed(1)+' MB';
	return (n/1073741824).toFixed(2)+' GB';
}
function fmtRate(bps){
	bps = +bps || 0;
	if (bps < 1000) return bps.toFixed(0)+' bps';
	if (bps < 1000000) return (bps/1000).toFixed(1)+' Kbps';
	return (bps/1000000).toFixed(2)+' Mbps';
}

function devRow(x, isBlocked, offline){
	var isWifi = String(x.kind||'').indexOf('wifi') >= 0;
	var band = x.kind==='wifi5g' ? '5G' : (x.kind==='wifi2g' ? '2.4G' : 'سلكي');
	var icon = isWifi ? '📶' : '🔌';
	var sig = (isWifi && x.signal) ? (esc(x.signal)+'dBm'+(x.dist?(' · '+esc(x.dist)):'')) : '';
	var pct = (isWifi && x.signal) ? Math.max(0, Math.min(100, (x.sigpct!=null ? +x.sigpct : 2*((+x.signal||-100)+100)))) : 0;
	var usage = 'تنزيل '+fmtRate(x.dl_bps)+' · رفع '+fmtRate(x.ul_bps)+' · إجمالي '+fmtBytes(x.bytes);
	var mac = String(x.mac||'').toLowerCase();
	var btn = isBlocked
		? '<button class="kt-btn" data-act="unblock" data-mac="'+esc(mac)+'">إلغاء الحظر</button>'
		: '<button class="kt-btn sec" data-act="block" data-mac="'+esc(mac)+'">حظر</button>';
	return '<div class="kt-dev"'+(offline?' style="opacity:.55"':'')+'>'
		+ '<div class="dic">'+icon+'</div>'
		+ '<div class="dmain"><div class="dname">'+esc(x.name||'جهاز')+' <span class="kt-badge '+(offline?'bad':'ok')+'">'+band+'</span></div>'
		+ '<div class="dmeta">'+esc(x.ip||'—')+' · '+esc(x.mac||'')+(sig?(' · '+sig):'')+'</div>'
		+ '<div class="dmeta">'+esc(usage)+'</div></div>'
		+ (isWifi && x.signal ? '<div class="kt-sigbar"><i style="width:'+pct+'%;background:'+sigColor(x.signal)+'"></i></div>' : '')
		+ '<div style="align-self:center">'+btn+'</div>'
		+ '</div>';
}

function wire(container){
	container.querySelectorAll('button[data-mac]').forEach(function(b){
		b.addEventListener('click', function(){
			var mac = b.getAttribute('data-mac');
			var act = b.getAttribute('data-act');
			if (act === 'block' && !confirm('هل تريد حظر هذا الجهاز؟\n'+mac)) return;
			b.disabled = true;
			postCall({act:act, mac:mac}).then(function(){ reload(container); });
		});
	});
}

function reload(container){
	return Promise.all([ call({op:'devices'}), call({op:'blocked'}) ]).then(function(res){
		var c = res[0] || {}, bl = res[1] || {};
		if (!(c && c.ok)){ container.innerHTML = '<div class="kt-sub">تعذّر التحميل</div>'; return; }
		var ds = c.devices || [];
		var blocked = (bl && bl.ok && bl.blocked) ? bl.blocked.map(function(m){ return String(m).toLowerCase(); }) : [];
		var blSet = {}; blocked.forEach(function(m){ blSet[m] = true; });
		var online = ds.filter(function(d){ return +d.online === 1; });
		var n24 = online.filter(function(d){ return d.kind==='wifi2g'; }).length;
		var n5  = online.filter(function(d){ return d.kind==='wifi5g'; }).length;
		var wired = online.filter(function(d){ return String(d.kind||'').indexOf('wifi') < 0; }).length;

		var seen = {};
		var rows = ds.map(function(d){
			var mac = String(d.mac||'').toLowerCase();
			seen[mac] = true;
			return devRow(d, !!blSet[mac], +d.online !== 1);
		}).join('');
		/* blocked MACs that are not present in the device list at all */
		var extra = blocked.filter(function(m){ return !seen[m]; }).map(function(m){
			return devRow({mac:m, name:'محظور (غير متصل)', kind:'lan'}, true, true);
		}).join('');

		container.innerHTML =
			'<div class="kt-grid kt-cols-4">'
			+ '<div class="kt-tile kt-t-blue"><div class="ti">📱</div><div class="tn">'+online.length+'</div><div class="tl">أجهزة متصلة</div></div>'
			+ '<div class="kt-tile kt-t-green"><div class="ti">📶</div><div class="tn">'+n24+'</div><div class="tl">واي‑فاي 2.4G</div></div>'
			+ '<div class="kt-tile kt-t-cyan"><div class="ti">📡</div><div class="tn">'+n5+'</div><div class="tl">واي‑فاي 5G</div></div>'
			+ '<div class="kt-tile kt-t-orange"><div class="ti">🔌</div><div class="tn">'+wired+'</div><div class="tl">سلكية</div></div>'
			+ '</div>'
			+ '<div class="kt-card"><h3>🌐 الأجهزة والتحكم — حظر / إلغاء حظر</h3>'
			+ ((rows||extra) ? (rows+extra) : '<div class="kt-sub">لا أجهزة</div>')
			+ '</div>';
		wire(container);
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('الأجهزة والتحكم')),
			E('div', { 'dir':'rtl', 'class':'kt-body' }, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')))
		]);
		var body = box.querySelector('.kt-body');
		reload(body);
		poll.add(function(){ return reload(body); }, 10);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
