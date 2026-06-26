'use strict';
'require view';
'require poll';

/* KT412 Smart AP — Neighbors (جيران الشبكة), MikroTik-style: the kernel ARP /
   IPv6-ND table with a resolved DEVICE NAME per entry, and you can name / rename
   any device from here (✏️). Backend /cgi-bin/kt412:
     op=neighbors -> {ok, neighbors:[{ip,mac,dev,state,name,custom}]}
     act=set_label {mac,name}  (empty name clears the custom label) */

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
		ns.sort(function(a,b){
			var an = a.name?0:1, bn = b.name?0:1;          // named first
			if (an !== bn) return an - bn;
			return (a.dev+'|'+a.ip).localeCompare(b.dev+'|'+b.ip);
		});
		var ok = ns.filter(function(n){ return stClass(n.state)==='ok'; }).length;
		var named = ns.filter(function(n){ return n.name; }).length;
		var rows = ns.map(function(n){
			var nm = n.name || _('(بدون اسم)');
			var icon = n.custom ? '🏷️' : (n.name ? '🖥️' : '❔');
			return '<div class="kt-dev">'
				+ '<div class="dic">'+icon+'</div>'
				+ '<div class="dmain">'
				+   '<div class="dname">'+esc(nm)+' <span class="kt-badge '+stClass(n.state)+'">'+esc(n.state)+'</span></div>'
				+   '<div class="dmeta" dir="ltr" style="direction:ltr">'+esc(n.ip)+' · '+esc(n.mac)+' · '+esc(n.dev)+'</div>'
				+ '</div>'
				+ '<button class="kt-btn sec kt-edit" data-mac="'+esc(n.mac)+'" data-name="'+esc(n.name||'')+'" title="'+_('تسمية')+'">✏️</button>'
				+ '</div>';
		}).join('');
		box.innerHTML =
			'<div class="kt-grid kt-cols-3">'
			+ '<div class="kt-tile kt-t-blue"><div class="ti">🧭</div><div class="tn">'+ns.length+'</div><div class="tl">جيران الشبكة</div></div>'
			+ '<div class="kt-tile kt-t-green"><div class="ti">✅</div><div class="tn">'+ok+'</div><div class="tl">REACHABLE</div></div>'
			+ '<div class="kt-tile kt-t-cyan"><div class="ti">🏷️</div><div class="tn">'+named+'</div><div class="tl">مُسمّاة</div></div>'
			+ '</div>'
			+ '<div class="kt-card"><h3>🧭 جدول الجيران — الاسم · IP · MAC · المنفذ · الحالة</h3>'
			+ (rows || '<div class="kt-sub">لا جيران مكتشفون بعد</div>')
			+ '</div>';
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('جيران الشبكة — Neighbors')),
			E('div', { 'class':'kt-sub' }, _('كل جهاز على الشبكة باسمه (مثل ميكروتك). اضغط ✏️ لتسمية أو تعديل اسم أي جهاز.')),
			E('div', { 'class':'kt-body', style:'margin-top:10px' }, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')))
		]);
		var body = box.querySelector('.kt-body');
		/* one delegated handler survives the innerHTML refresh on each poll */
		body.addEventListener('click', function(e){
			var b = e.target.closest ? e.target.closest('.kt-edit') : null;
			if (!b) return;
			var mac = b.getAttribute('data-mac'), cur = b.getAttribute('data-name') || '';
			var nm = prompt(_('اسم الجهاز لـ ') + mac + ' :', cur);
			if (nm === null) return;                       // cancelled
			b.disabled = true;
			postCall({ act:'set_label', mac:mac, name:nm }).then(function(){ reload(body); });
		});
		reload(body);
		poll.add(function(){ return reload(body); }, 10);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
