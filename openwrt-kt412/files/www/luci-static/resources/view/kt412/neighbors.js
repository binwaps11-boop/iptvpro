'use strict';
'require view';
'require poll';

/* KT412 Smart AP — Neighbors (جيران الشبكة): the kernel ARP / IPv6-ND neighbour
   table (ip neigh) showing every L2/L3 neighbour: IP, MAC, interface, state.
   Backend: /cgi-bin/kt412 op=neighbors -> {ok, neighbors:[{ip,mac,dev,state}]}. */

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

function stClass(s){
	s = String(s||'').toUpperCase();
	if (s.indexOf('REACHABLE') >= 0) return 'ok';
	if (s.indexOf('FAILED') >= 0 || s.indexOf('INCOMPLETE') >= 0) return 'bad';
	return 'warn';   // STALE / DELAY / PROBE / NOARP / PERMANENT
}

function reload(box){
	return call({op:'neighbors'}).then(function(j){
		if (!(j && j.ok)){ box.innerHTML = '<div class="kt-sub">تعذّر التحميل</div>'; return; }
		var ns = (j.neighbors || []).filter(function(n){ return n.mac && n.mac !== '00:00:00:00:00:00'; });
		ns.sort(function(a,b){ return (a.dev+'|'+a.ip).localeCompare(b.dev+'|'+b.ip); });
		var ok = ns.filter(function(n){ return stClass(n.state)==='ok'; }).length;
		var rows = ns.map(function(n){
			return '<div class="kt-kv">'
				+ '<span class="k" dir="ltr" style="text-align:left">'+esc(n.ip)+'</span>'
				+ '<span class="v" dir="ltr" style="text-align:left;direction:ltr">'+esc(n.mac)+' · '+esc(n.dev)
				+ ' <span class="kt-badge '+stClass(n.state)+'">'+esc(n.state)+'</span></span>'
				+ '</div>';
		}).join('');
		box.innerHTML =
			'<div class="kt-grid kt-cols-2">'
			+ '<div class="kt-tile kt-t-blue"><div class="ti">🧭</div><div class="tn">'+ns.length+'</div><div class="tl">جيران الشبكة</div></div>'
			+ '<div class="kt-tile kt-t-green"><div class="ti">✅</div><div class="tn">'+ok+'</div><div class="tl">REACHABLE</div></div>'
			+ '</div>'
			+ '<div class="kt-card"><h3>🧭 جدول الجيران (ARP / IPv6 ND)</h3>'
			+ (rows || '<div class="kt-sub">لا جيران مكتشفون بعد</div>')
			+ '</div>';
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('جيران الشبكة — Neighbors')),
			E('div', { 'class':'kt-sub' }, _('كل جهاز معروف على الشبكة (IP · MAC · المنفذ · الحالة) من جدول نواة النظام.')),
			E('div', { 'class':'kt-body', style:'margin-top:10px' }, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')))
		]);
		var body = box.querySelector('.kt-body');
		reload(body);
		poll.add(function(){ return reload(body); }, 10);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
