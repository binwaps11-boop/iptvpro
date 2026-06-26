'use strict';
'require view';
'require ui';
'require poll';

/* KT412 "MK APP" — Power & dBm Control (التحكم بالباور).
   Per-radio (2.4G/5G) current txpower + a slider/input to set txpower 0..30 dBm
   via uci + `iw phy set txpower` (backend kt412-tools op=getpower/setpower).
   Shows the live iw-phy ceiling + netdev applied txpower so the operator sees the
   real value. Does NOT re-patch the 2.4G driver — only reads/sets/re-pins uci. */

var API = '/cgi-bin/kt412-tools';
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
		call({op:'setpower', radio:r.radio, dbm:String(v)}, true).then(function(j){
			btn.disabled=false;
			if (j && j.ok){ msg.style.color='var(--kt-ok)'; msg.textContent=_('تم الضبط على')+' '+v+' dBm — '+_('يُعاد تحميل الواي‑فاي'); }
			else { msg.style.color='var(--kt-bad)'; msg.textContent=_('فشل التطبيق')+': '+esc((j&&j.error)||'?'); }
		});
	});

	var info = E('div', {}, [
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('قيمة uci الحالية')), E('span',{'class':'v'}, out) ]),
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('السقف الحي (iw phy)')), E('span',{'class':'v'}, (r.phy_max?(r.phy_max+' dBm'):'—')) ]),
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('المُطبّق فعلياً (netdev)')), E('span',{'class':'v'}, (r.netdev_txpower?(r.netdev_txpower+' dBm'):'—')) ]),
		E('div', { 'class':'kt-kv' }, [ E('span',{'class':'k'},_('PHY / القناة')), E('span',{'class':'v'}, esc(r.phy||'—')+' · '+esc(r.channel||'—')) ])
	]);

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '📶 '+bandLabel(r)+' ('+esc(r.radio)+')'),
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
			if (document.activeElement && /INPUT|SELECT/.test(document.activeElement.tagName)) return Promise.resolve();
			return reload(body);
		}, 12);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
