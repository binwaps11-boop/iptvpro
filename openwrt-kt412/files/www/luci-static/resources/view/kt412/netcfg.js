'use strict';
'require view';

/* KT412 Smart AP — Scheduling & Guest network (الجدولة وشبكة الضيوف).
   Card A: daily WiFi off/on schedule (op=sched_get / act=wifi_sched).
   Card B: guest SSID (op=guest_get / act=guest). Uses the same adopt()/call()
   auth as devices.js plus a postCall() for the POST actions. */

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

function hourSelect(sel){
	var s = E('select', { 'class':'cbi-input-select' });
	for (var h = 0; h < 24; h++){
		var o = E('option', { value:String(h) }, (h<10?'0':'')+h+':00');
		if (+sel === h) o.selected = true;
		s.appendChild(o);
	}
	return s;
}

function schedCard(){
	var enabled = E('input', { type:'checkbox' });
	var offSel  = hourSelect(0);
	var onSel   = hourSelect(0);
	var note    = E('div', { 'class':'kt-note' }, _('تُطفئ الواي‑فاي يومياً في ساعة الإطفاء وتعيد تشغيله في ساعة التشغيل.'));
	var btn     = E('button', { 'class':'kt-btn' }, _('حفظ'));

	call({op:'sched_get'}).then(function(j){
		if (j && j.ok){
			enabled.checked = (+j.enabled === 1);
			[offSel].forEach(function(){}); // noop
			Array.prototype.forEach.call(offSel.options, function(o){ o.selected = (+o.value === +j.off_h); });
			Array.prototype.forEach.call(onSel.options,  function(o){ o.selected = (+o.value === +j.on_h); });
		}
	});

	btn.addEventListener('click', function(){
		btn.disabled = true; note.textContent = _('جارٍ الحفظ…');
		postCall({act:'wifi_sched', enabled: enabled.checked?'1':'0', off_h: offSel.value, on_h: onSel.value}).then(function(j){
			btn.disabled = false;
			note.textContent = (j && j.ok) ? (j.msg || _('تم الحفظ')) : _('فشل الحفظ');
		});
	});

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '⏰ '+_('جدولة الواي‑فاي')),
		E('label', { 'class':'kt-row', style:'gap:8px;margin:0 0 10px' }, [ enabled, E('span', { 'class':'kt-sub' }, _('تفعيل الجدولة')) ]),
		E('div', { 'class':'kt-row' }, [
			E('div', { 'class':'kt-field' }, [ E('label',{},_('إطفاء الساعة')), offSel ]),
			E('div', { 'class':'kt-field' }, [ E('label',{},_('تشغيل الساعة')), onSel ])
		]),
		note,
		E('div', { style:'margin-top:8px' }, btn)
	]);
}

function guestCard(){
	var enabled = E('input', { type:'checkbox' });
	var ssid    = E('input', { type:'text', 'class':'cbi-input-text', value:'KT412-Guest' });
	var key     = E('input', { type:'text', 'class':'cbi-input-text', placeholder:_('اتركه فارغاً = مفتوحة، أو 8 أحرف+') });
	var note    = E('div', { 'class':'kt-note' }, _('أجهزة الضيوف معزولة عن بعضها وعن شبكتك الرئيسية.'));
	var btn     = E('button', { 'class':'kt-btn' }, _('حفظ'));

	call({op:'guest_get'}).then(function(j){
		if (j && j.ok){
			enabled.checked = (+j.enabled === 1);
			if (j.ssid) ssid.value = j.ssid;
		}
	});

	btn.addEventListener('click', function(){
		var k = key.value || '';
		if (k && k.length < 8){ note.textContent = _('كلمة المرور يجب أن تكون 8 أحرف على الأقل أو فارغة (شبكة مفتوحة).'); return; }
		btn.disabled = true; note.textContent = _('جارٍ الحفظ…');
		postCall({act:'guest', enabled: enabled.checked?'1':'0', ssid: ssid.value || 'KT412-Guest', key: k}).then(function(j){
			btn.disabled = false;
			note.textContent = (j && j.ok) ? (j.msg || _('تم الحفظ')) : _('فشل الحفظ');
		});
	});

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '👥 '+_('شبكة الضيوف')),
		E('label', { 'class':'kt-row', style:'gap:8px;margin:0 0 10px' }, [ enabled, E('span', { 'class':'kt-sub' }, _('تفعيل شبكة الضيوف')) ]),
		E('div', { 'class':'kt-field' }, [ E('label',{},_('اسم الشبكة (SSID)')), ssid ]),
		E('div', { 'class':'kt-field' }, [ E('label',{},_('كلمة المرور (اختياري)')), key ]),
		note,
		E('div', { style:'margin-top:8px' }, btn)
	]);
}

return view.extend({
	render: function(){
		return E('div', {}, [
			E('h2', {}, _('الجدولة وشبكة الضيوف')),
			E('div', { 'dir':'rtl' }, [
				E('div', { 'class':'kt-grid kt-cols-2' }, [ schedCard(), guestCard() ])
			])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
