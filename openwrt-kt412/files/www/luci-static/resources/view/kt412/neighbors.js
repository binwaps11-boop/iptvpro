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
function ktIcSvg(n){return '<svg class="kti" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(KTI[n]||KTI.dot)+'</svg>';}
function ktIc(n){var d=document.createElement('div');d.innerHTML=ktIcSvg(n);return d.firstChild;}

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
/* reset a stale token on an explicit auth error so the next poll re-adopts */
function authReset(j){ if (j && j.ok===false && (j.error==='unauthorized'||j.error==='no_token')) TOKEN=''; return j; }
function call(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API + '?' + usp.toString()).then(function(r){ return r.json(); }).then(authReset).catch(function(){ return {ok:false}; });
	});
}
function postCall(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API, {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:usp.toString()})
			.then(function(r){ return r.json(); }).then(authReset).catch(function(){ return {ok:false}; });
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
			var icon = n.custom ? ktIcSvg('tag') : (n.name ? ktIcSvg('monitor') : ktIcSvg('question'));
			return '<div class="kt-dev">'
				+ '<div class="dic">'+icon+'</div>'
				+ '<div class="dmain">'
				+   '<div class="dname">'+esc(nm)+' <span class="kt-badge '+stClass(n.state)+'">'+esc(n.state)+'</span></div>'
				+   '<div class="dmeta" dir="ltr" style="direction:ltr">'+esc(n.ip)+' · '+esc(n.mac)+' · '+esc(n.dev)+'</div>'
				+ '</div>'
				+ '<button class="kt-btn sec kt-edit" data-mac="'+esc(n.mac)+'" data-name="'+esc(n.name||'')+'" title="'+_('تسمية')+'">'+ktIcSvg('edit')+'</button>'
				+ '</div>';
		}).join('');
		box.innerHTML =
			'<div class="kt-grid kt-cols-3">'
			+ '<div class="kt-tile kt-t-blue"><div class="ti">'+ktIcSvg('compass')+'</div><div class="tn">'+ns.length+'</div><div class="tl">جيران الشبكة</div></div>'
			+ '<div class="kt-tile kt-t-green"><div class="ti">'+ktIcSvg('check')+'</div><div class="tn">'+ok+'</div><div class="tl">REACHABLE</div></div>'
			+ '<div class="kt-tile kt-t-cyan"><div class="ti">'+ktIcSvg('tag')+'</div><div class="tn">'+named+'</div><div class="tl">مُسمّاة</div></div>'
			+ '</div>'
			+ '<div class="kt-card"><h3>'+ktIcSvg('compass')+' جدول الجيران — الاسم · IP · MAC · المنفذ · الحالة</h3>'
			+ (rows || '<div class="kt-sub">لا جيران مكتشفون بعد</div>')
			+ '</div>';
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('جيران الشبكة — Neighbors')),
			E('div', { 'class':'kt-sub' }, [_('كل جهاز على الشبكة باسمه (مثل ميكروتك). اضغط '), ktIc('edit'), _(' لتسمية أو تعديل اسم أي جهاز.')]),
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
