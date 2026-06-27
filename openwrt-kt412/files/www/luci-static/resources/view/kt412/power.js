'use strict';
'require view';
'require ui';
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

/* KT412 "MK APP" — Power & dBm Control (التحكم بالباور).
   Per-radio (2.4G/5G) current txpower + a slider/input to set txpower 0..30 dBm
   via uci + `iw phy set txpower` (backend kt412-tools op=getpower/setpower).
   Shows the live iw-phy ceiling + netdev applied txpower so the operator sees the
   real value. Does NOT re-patch the 2.4G driver — only reads/sets/re-pins uci. */

var API = '/cgi-bin/kt412-tools';
var TOKEN = '';
/* while non-zero and in the future, the background poll must NOT rebuild the
   cards (it would wipe the apply success/error message before it can be read). */
var applyBusyUntil = 0;

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c];}); }

function adopt(){
	if (TOKEN) return Promise.resolve(TOKEN);
	var sid = (L.env && L.env.sessionid) ? L.env.sessionid : '';
	return fetch(API, {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:'op=adopt&token='+encodeURIComponent(sid)})
		.then(function(r){ return r.json(); })
		.then(function(j){ if (j && j.ok && j.token) TOKEN = j.token; return TOKEN; })
		.catch(function(){ return ''; });
}
function call(params, post){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		var opt = post ? {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:usp.toString()} : undefined;
		var url = post ? API : (API + '?' + usp.toString());
		return fetch(url, opt).then(function(r){ return r.json(); }).catch(function(){ return {ok:false,error:'network'}; });
	});
}

function bandLabel(r){
	var b = (r.band||'').toLowerCase();
	if (b.indexOf('2g')>=0 || b==='11g' || b==='11ng') return '2.4 GHz';
	if (b.indexOf('5g')>=0 || b==='11a' || b==='11na' || b==='11ac' || b==='11ax') return '5 GHz';
	return r.band || r.radio;
}

function radioCard(r){
	var cur = (r.uci_txpower!=='' && r.uci_txpower!=null) ? parseInt(r.uci_txpower,10) : 20;
	if (isNaN(cur)) cur = 20;
	if (cur<0) cur=0; if (cur>30) cur=30;

	var out  = E('span', { 'class':'kt-badge ok' }, cur+' dBm');
	var rng  = E('input', { type:'range', class:'kt-range', min:'0', max:'30', step:'1', value:String(cur), style:'flex:1' });
	var num  = E('input', { type:'number', class:'cbi-input-text', min:'0', max:'30', value:String(cur), style:'width:74px' });
	var btn  = E('button', { 'class':'kt-btn' }, _('تطبيق'));
	var msg  = E('div', { 'class':'kt-sub', style:'margin-top:8px' }, '');

	rng.addEventListener('input', function(){ num.value=rng.value; out.textContent=rng.value+' dBm'; });
	num.addEventListener('input', function(){
		var v=parseInt(num.value,10); if(isNaN(v))return; if(v<0)v=0; if(v>30)v=30;
		rng.value=String(v); out.textContent=v+' dBm';
	});
	btn.addEventListener('click', function(){
		var v=parseInt(num.value,10);
		if (isNaN(v)||v<0||v>30){ msg.textContent=_('القيمة يجب أن تكون بين 0 و 30 dBm'); msg.style.color='var(--kt-bad)'; return; }
		btn.disabled=true; msg.style.color='var(--kt-txt2)'; msg.textContent=_('جارٍ التطبيق…');
		applyBusyUntil = Date.now() + 15000;
		call({op:'setpower', radio:r.radio, dbm:String(v)}, true).then(function(j){
			btn.disabled=false;
			if (j && j.ok){ msg.style.color='var(--kt-ok)'; msg.textContent=_('تم الضبط على')+' '+v+' dBm — '+_('يُعاد تحميل الواي‑فاي'); }
			else { msg.style.color='var(--kt-bad)'; msg.textContent=_('فشل التطبيق')+': '+esc((j&&j.error)||'?'); }
			/* keep the result on screen ~8s after completion before the poll resumes */
			applyBusyUntil = Date.now() + 8000;
		});
	});

	var info = E('div', {}, [
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('قيمة uci الحالية')), E('span',{'class':'v'}, out) ]),
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('السقف الحي (iw phy)')), E('span',{'class':'v'}, (r.phy_max?(r.phy_max+' dBm'):'—')) ]),
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('المُطبّق فعلياً (netdev)')), E('span',{'class':'v'}, (r.netdev_txpower?(r.netdev_txpower+' dBm'):'—')) ]),
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('PHY / القناة')), E('span',{'class':'v'}, esc(r.phy||'—')+' · '+esc(r.channel||'—')) ])
	]);

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ktIc('wifi'), ' '+bandLabel(r)+' ('+esc(r.radio)+')']),
		info,
		E('div', { 'class':'kt-row', style:'margin-top:12px' }, [ rng, num, btn ]),
		msg
	]);
}

function reload(container){
	return call({op:'getpower'}).then(function(j){
		container.innerHTML='';
		if (!j || !j.ok || !j.radios || !j.radios.length){
			container.appendChild(E('div',{'class':'kt-card'}, E('div',{'class':'kt-sub'}, _('لا توجد أجهزة لاسلكية'))));
			return;
		}
		var grid = E('div', { 'class':'kt-grid kt-cols-2' });
		j.radios.forEach(function(r){ grid.appendChild(radioCard(r)); });
		container.appendChild(grid);
		container.appendChild(E('div', { 'class':'kt-card' }, [
			E('div', { 'class':'kt-sub' }, _('المدى 0–30 dBm، يُطبَّق عبر uci و iw مع تثبيت الدولة US. النطاق 2.4G مُرقّع مسبقاً للوصول إلى 30 على مستوى النظام؛ هذه الصفحة تقرأ وتثبّت قيمة uci فقط ولا تُعيد ترقيع التعريف.'))
		]));
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('التحكم بالباور (dBm)')),
			E('div', { 'class':'kt-body', 'dir':'rtl' }, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')))
		]);
		var body = box.querySelector('.kt-body');
		reload(body);
		/* refresh live netdev/phy values periodically, but only when not editing */
		poll.add(function(){
			if (Date.now() < applyBusyUntil) return Promise.resolve();
			if (document.activeElement && /INPUT|SELECT|BUTTON/.test(document.activeElement.tagName)) return Promise.resolve();
			return reload(body);
		}, 12);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
