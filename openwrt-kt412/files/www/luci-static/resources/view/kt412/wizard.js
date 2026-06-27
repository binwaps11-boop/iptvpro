'use strict';
'require view';
'require ui';

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

/* KT412 Quick Config (إعدادات سريعة) — all-in-one NATIVE wireless + network panel.
   Mirrors OpenWrt's native wireless options (mode + per-radio settings) AND WAN
   (incl. PPPoE) AND VLAN-on-SSID, each card with its OWN instant Apply — no page
   hopping. Talks to the MAIN backend /cgi-bin/kt412 using the same adopt()/call()
   auth pattern as devices.js; state-changing actions go through postCall() which
   POSTs a form-urlencoded body (incl. token), mirroring devices.js adopt() style. */

var API = '/cgi-bin/kt412';
var TOKEN = '';

function adopt(){
	if (TOKEN) return Promise.resolve(TOKEN);
	var sid = (L.env && L.env.sessionid) ? L.env.sessionid : '';
	return fetch(API, {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'},
			body:'op=adopt&token='+encodeURIComponent(sid)})
		.then(function(r){ return r.json(); })
		.then(function(j){ if (j && j.ok && j.token) TOKEN = j.token; return TOKEN; })
		.catch(function(){ return ''; });
}
/* GET read */
function call(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API + '?' + usp.toString()).then(function(r){ return r.json(); })
			.catch(function(){ return {ok:false,error:'network'}; });
	});
}
/* POST action (form-urlencoded body incl. token), mirroring devices.js adopt() body style */
function postCall(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API, {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'},
				body:usp.toString()})
			.then(function(r){ return r.json(); })
			.catch(function(){ return {ok:false,error:'network'}; });
	});
}

/* ---- client-side validators (the CGI re-validates server-side) ---- */
function validKey(k){ return (typeof k === 'string') && k.length >= 8 && k.length <= 63; }
function validVid(v){ if (v === '' || v === null || v === undefined) return true; var n = +v; return Number.isInteger(n) && n >= 1 && n <= 4094; }
function validSsid(s){ return (typeof s === 'string') && s.length >= 1 && s.length <= 32; }

function notify(r, okMsg){
	if (r && r.ok) ui.addNotification(null, E('p', {}, r.msg || okMsg || _('تم التطبيق')), 'info');
	else ui.addNotification(null, E('p', {}, _('فشل: %s').format((r && r.error) || 'unknown')), 'error');
}

/* signal-strength colour for scan rows (dBm): strong=green, ok=amber, weak=red */
function sigColor(sig){
	var v = parseInt(sig, 10); if (isNaN(v)) return 'var(--kt-warn)';
	if (v >= -67) return 'var(--kt-ok)';
	if (v >= -78) return 'var(--kt-warn)';
	return 'var(--kt-bad)';
}

function is5g(band){ return String(band||'').toLowerCase().indexOf('5') >= 0; }
function bandTitle(band){ return is5g(band) ? _('واي‑فاي 5G') : _('واي‑فاي 2.4G'); }
function bandShort(band){ return is5g(band) ? '5G' : '2.4G'; }

/* ---- premium presentation helpers (visual only) ---- */
/* polished card header: icon tile + bold title (+ optional inline node) + muted subtitle */
function cardHead(icon, title, subtitle, tone, titleExtra){
	var tline = [ E('span', {}, title) ];
	if (titleExtra) tline.push(titleExtra);
	return E('div', { class:'kt-wz-head' }, [
		E('div', { class:'kt-wz-ic' + (tone ? ' ' + tone : '') }, icon),
		E('div', { class:'kt-wz-htxt' }, [
			E('div', { class:'t' }, tline),
			subtitle ? E('div', { class:'s' }, subtitle) : ''
		])
	]);
}
/* labelled field */
function fld(lbl, node){ return E('div', { class:'kt-field' }, [ E('label', {}, lbl), node ]); }
/* wrap a native <select> in the segmented-pill chrome (purely cosmetic) */
function segField(lbl, sel){ return E('div', { class:'kt-field' }, [ E('label', {}, lbl), E('div', { class:'kt-wz-seg' }, sel) ]); }
/* a styled toggle pill carrying an existing checkbox + label (+ optional trailing badge) */
function togglePill(cb, label, trailing){
	var kids = [ cb, E('span', { class:'lab' }, label) ];
	if (trailing){ kids.push(E('span', { class:'sp' })); kids.push(trailing); }
	return E('label', { class:'kt-wz-toggle' }, kids);
}

/* band-appropriate channel <option> lists (incl. 'auto') */
function chanOptions(band, cur){
	var list = is5g(band) ? [36,40,44,48,149,153,157,161] : [1,2,3,4,5,6,7,8,9,10,11];
	var opts = [ E('option', { value:'auto' }, _('تلقائي (auto)')) ];
	list.forEach(function(c){ opts.push(E('option', { value:String(c) }, String(c))); });
	var o = E('select', { class:'cbi-input-select' }, opts);
	var v = (cur === '' || cur == null) ? 'auto' : String(cur);
	/* if the saved channel isn't in our static list, inject it so it stays selected */
	if (v !== 'auto' && list.indexOf(+v) < 0){ o.appendChild(E('option', { value:v }, v)); }
	o.value = v;
	return o;
}

function htOptions(band, cur){
	var list = is5g(band) ? ['VHT20','VHT40','VHT80'] : ['HT20','HT40'];
	var o = E('select', { class:'cbi-input-select' }, list.map(function(h){ return E('option', { value:h }, h); }));
	var v = String(cur||'');
	if (v && list.indexOf(v) < 0){ o.appendChild(E('option', { value:v }, v)); }
	o.value = v || list[0];
	return o;
}

/* ---------------- per-radio card ---------------- */
function radioCard(r){
	var modeSel = E('select', { class:'cbi-input-select' }, [
		E('option', { value:'ap' },     _('نقطة وصول (AP)')),
		E('option', { value:'sta' },    _('عميل (استقبال)')),
		E('option', { value:'mesh' },   _('شبكة Mesh')),
		E('option', { value:'ap-wds' }, _('جسر AP+WDS'))
	]);
	modeSel.value = r.mode || 'ap';

	var ssid = E('input', { type:'text', class:'cbi-input-text', maxlength:'32', value:(r.ssid||'') });
	/* SSID field is wrapped via fld(); keep a handle on its <label> so the mode
	   <select> can relabel it (e.g. "Mesh ID" when mode='mesh') and to the field
	   wrapper so we can guarantee it's always shown/enabled. */
	var ssidField = fld('SSID', ssid);
	var ssidLabel = ssidField.querySelector('label');
	/* bssid of a scan-picked network (only used if backend wifi_apply reads it;
	   the current wifi_apply handler does NOT, so this stays informational) */
	var pickedBssid = '';

	var secSel = E('select', { class:'cbi-input-select' }, [
		E('option', { value:'open' }, _('مفتوحة (بدون تشفير)')),
		E('option', { value:'psk2' }, 'WPA2 (PSK)')
	]);
	/* current encryption + whether a key already exists (from wifi_radios). Lets us
	   preselect WPA2 and treat an empty key as "keep the existing one" instead of
	   forcing psk2 with a blank field (which downgraded WPA2 -> open on apply). */
	var hasKey = (r.has_key === true);
	var curEnc = String(r.encryption || '').toLowerCase();
	var key = E('input', { type:'text', class:'cbi-input-text kt-pwval', maxlength:'63',
		placeholder: hasKey ? _('اتركه فارغاً للإبقاء على المفتاح الحالي') : _('8 أحرف على الأقل') });
	var keyWrap = E('div', { class:'kt-field' }, [
		E('label', {}, [ ktIc('lock'), ' ' + _('كلمة المرور') ]),
		key
	]);
	secSel.value = (curEnc && curEnc !== 'none') ? 'psk2' : 'open';
	function syncSec(){ keyWrap.style.display = (secSel.value === 'open') ? 'none' : ''; }
	secSel.onchange = syncSec; syncSec();

	var chan = chanOptions(r.band, r.channel);
	var ht   = htOptions(r.band, r.htmode);
	var ctry = E('input', { type:'text', class:'cbi-input-text', maxlength:'2', style:'width:74px', value:(r.country || 'US') });

	var tpInit = parseInt(r.txpower, 10); if (isNaN(tpInit)) tpInit = 20;
	if (tpInit < 0) tpInit = 0; if (tpInit > 30) tpInit = 30;
	var pwval = E('span', { class:'kt-wz-bubble' }, tpInit + ' dBm');
	var rng   = E('input', { type:'range', class:'kt-range', min:'0', max:'30', step:'1', value:String(tpInit) });
	rng.addEventListener('input', function(){ pwval.textContent = rng.value + ' dBm'; });

	var hidden = E('input', { type:'checkbox' }); hidden.checked = (String(r.hidden) === '1');

	var en = E('input', { type:'checkbox' }); en.checked = (r.enabled === true || r.enabled === 'true' || r.enabled === 1);
	var enBadge = E('span', { class:'kt-badge ' + (en.checked ? 'ok' : 'bad') }, en.checked ? _('مُفعّل') : _('معطّل'));
	en.addEventListener('change', function(){
		var on = en.checked ? '1' : '0';
		en.disabled = true;
		postCall({act:'wifi_toggle', radio:r.radio, on:on}).then(function(j){
			en.disabled = false;
			enBadge.className = 'kt-badge ' + (en.checked ? 'ok' : 'bad');
			enBadge.textContent = en.checked ? _('مُفعّل') : _('معطّل');
			notify(j);
		});
	});

	/* ---- Station (sta) network scanner — shown only when mode='sta' ---- */
	var scanResults = E('div', {});           /* network list / status messages land here */
	var scanBtn = E('button', { class:'kt-btn', style:'margin-bottom:8px' }, [ ktIc('search'), ' ' + _('بحث عن الشبكات') ]);
	scanBtn.addEventListener('click', function(){
		scanBtn.disabled = true;
		var lbl = scanBtn.innerHTML; scanBtn.textContent = _('جارٍ البحث…');
		scanResults.innerHTML = '';
		call({ op:'wscan', radio:r.radio }).then(function(j){
			scanBtn.disabled = false; scanBtn.innerHTML = lbl;
			scanResults.innerHTML = '';
			if (!j || !j.ok){
				scanResults.appendChild(E('div', { class:'kt-note' }, _('فشل البحث: %s').format((j && j.error) || 'unknown')));
				return;
			}
			var nets = (j.nets || []).slice().sort(function(a, b){
				return (parseInt(b.sig, 10) || -999) - (parseInt(a.sig, 10) || -999);
			});
			if (!nets.length){
				scanResults.appendChild(E('div', { class:'kt-note' }, _('لا شبكات')));
				return;
			}
			nets.forEach(function(n){
				var nssid = n.ssid || n.essid || '';
				var row = E('div', { class:'kt-dev', style:'cursor:pointer;align-items:center;gap:8px' }, [
					E('span', { class:'kt-sigbar', style:'display:inline-block;width:10px;height:10px;border-radius:50%;background:' + sigColor(n.sig) }),
					E('span', { style:'flex:1;font-weight:600' }, nssid || _('(مخفية)')),
					E('span', { class:'kt-badge', dir:'ltr', style:'color:' + sigColor(n.sig) }, (n.sig || '?') + ' dBm'),
					E('span', { class:'kt-sub', dir:'ltr' }, 'CH ' + (n.ch || '?')),
					E('span', { class:'kt-sub' }, n.enc || _('مفتوحة'))
				]);
				row.addEventListener('click', function(){
					ssid.value = nssid;
					pickedBssid = n.bssid || '';
					/* highlight the picked row */
					Array.prototype.forEach.call(scanResults.children, function(c){ c.style.outline = ''; });
					row.style.outline = '2px solid var(--kt-ok)';
				});
				scanResults.appendChild(row);
			});
		});
	});
	var scanBox = E('div', { class:'kt-field', style:'display:none' }, [
		E('label', {}, [ ktIc('radio'), ' ' + _('الشبكات القريبة') ]),
		scanBtn,
		scanResults
	]);

	/* ---- mode <select> wiring: dynamic SSID/Mesh-ID label + scan visibility ---- */
	function syncMode(){
		var m = modeSel.value;
		if (m === 'mesh'){
			ssidLabel.innerHTML = ktIcSvg('mesh') + ' ' + _('Mesh ID (معرّف الشبكة)');
			ssid.placeholder = _('اكتب معرّف الميش');
		} else {
			ssidLabel.textContent = 'SSID';
			ssid.placeholder = '';
		}
		ssid.disabled = false;                 /* always editable across all modes */
		scanBox.style.display = (m === 'sta') ? '' : 'none';
	}
	modeSel.addEventListener('change', syncMode);
	syncMode();

	var btn = E('button', { class:'kt-btn' }, [ ktIc('save'), ' ' + _('تطبيق') ]);
	btn.addEventListener('click', function(){
		if (!validSsid(ssid.value))
			return ui.addNotification(null, E('p', {}, _('SSID مطلوب (1–32 حرفاً)')), 'error');
		var open = (secSel.value === 'open');
		/* secured network + blank key + a key already exists => keep the current key */
		var keepkey = (!open && !key.value && hasKey);
		if (!open && !keepkey && !validKey(key.value))
			return ui.addNotification(null, E('p', {}, _('المفتاح يجب أن يكون 8–63 حرفاً')), 'error');
		btn.disabled = true; var lbl = btn.innerHTML; btn.textContent = '…';
		var dbm = String(parseInt(rng.value, 10) || 0);
		postCall({
			act:'wifi_apply', radio:r.radio, mode:modeSel.value, ssid:ssid.value,
			key:(open ? '' : key.value), keepkey:(keepkey ? '1' : '0'),
			channel:chan.value, htmode:ht.value,
			country:ctry.value, hidden:(hidden.checked ? '1' : '0')
		}).then(function(j){
			notify(j);
			/* chain txpower right after the wifi config applies */
			return postCall({act:'txpower', radio:r.radio, dbm:dbm});
		}).then(function(jp){
			btn.disabled = false; btn.innerHTML = lbl;
			if (jp && jp.ok)
				ui.addNotification(null, E('p', {}, _('الطاقة: مطلوب %s / مُطبّق %s dBm').format(jp.requested, jp.actual)), 'info');
			else
				notify(jp);   /* surface a txpower failure instead of silently swallowing it */
		}).catch(function(){
			btn.disabled = false; btn.innerHTML = lbl; notify(null);
		});
	});

	var bandIcon = ktIc(is5g(r.band) ? 'radio' : 'wifi');
	var bandSub  = is5g(r.band)
		? _('نطاق 5 جيجاهرتز — سرعة أعلى ومدى أقصر')
		: _('نطاق 2.4 جيجاهرتز — تغطية أوسع وتوافق أعلى');

	/* power control: live neon bubble + scale rail */
	var pwrBlock = E('div', { class:'kt-wz-pwr' }, [
		E('div', { class:'kt-wz-pwr-top' }, [
			E('span', { class:'lbl' }, [ E('span', {}, [ ktIc('bolt') ]), E('span', {}, _('الطاقة (TxPower)')) ]),
			pwval
		]),
		rng,
		E('div', { class:'kt-wz-scale' }, [ E('span', {}, '0'), E('span', {}, '15'), E('span', {}, '30 dBm') ])
	]);

	return E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
		cardHead(bandIcon, bandTitle(r.band), bandSub + ' · ' + (r.radio||''),
			is5g(r.band) ? 'v' : '', enBadge),
		E('div', { class:'kt-grid kt-cols-2' }, [
			segField(_('الوضع'), modeSel),
			ssidField
		]),
		scanBox,
		E('div', { class:'kt-grid kt-cols-2' }, [
			segField(_('التشفير'), secSel),
			keyWrap
		]),
		E('div', { class:'kt-grid kt-cols-3' }, [
			segField(_('القناة'), chan),
			segField(_('عرض القناة (HTmode)'), ht),
			fld(_('الدولة'), ctry)
		]),
		pwrBlock,
		E('div', { class:'kt-wz-toggles' }, [
			togglePill(hidden, _('إخفاء SSID')),
			togglePill(en, _('تفعيل الراديو'))
		]),
		E('div', { class:'kt-wz-foot' }, [
			E('span', { class:'fhint' }, _('يُطبّق فوراً على هذا الراديو')),
			btn
		])
	]);
}

/* ---------------- WAN card ---------------- */
function wanCard(curProto){
	var proto = E('select', { class:'cbi-input-select' }, [
		E('option', { value:'dhcp' },   _('تلقائي DHCP')),
		E('option', { value:'pppoe' },  'PPPoE'),
		E('option', { value:'static' }, _('ثابت (Static)'))
	]);
	if (curProto === 'pppoe' || curProto === 'static' || curProto === 'dhcp') proto.value = curProto;

	var pUser = E('input', { type:'text', class:'cbi-input-text', placeholder:'username' });
	var pPass = E('input', { type:'text', class:'cbi-input-text', placeholder:'password' });
	var pppoeBox = E('div', { class:'kt-grid kt-cols-2' }, [
		E('div', { class:'kt-field' }, [ E('label', {}, [ ktIc('user'), ' ' + _('المستخدم') ]), pUser ]),
		E('div', { class:'kt-field' }, [ E('label', {}, [ ktIc('lock'), ' ' + _('كلمة المرور') ]), pPass ])
	]);

	var sIp   = E('input', { type:'text', class:'cbi-input-text', placeholder:'192.168.1.2' });
	var sMask = E('input', { type:'text', class:'cbi-input-text', placeholder:'255.255.255.0' });
	var sGw   = E('input', { type:'text', class:'cbi-input-text', placeholder:'192.168.1.1' });
	var sDns  = E('input', { type:'text', class:'cbi-input-text', placeholder:'1.1.1.1' });
	var staticBox = E('div', { class:'kt-grid kt-cols-2' }, [
		E('div', { class:'kt-field' }, [ E('label', {}, _('IP العنوان')), sIp ]),
		E('div', { class:'kt-field' }, [ E('label', {}, _('قناع الشبكة')), sMask ]),
		E('div', { class:'kt-field' }, [ E('label', {}, _('البوابة')), sGw ]),
		E('div', { class:'kt-field' }, [ E('label', {}, 'DNS'), sDns ])
	]);

	function sync(){
		pppoeBox.style.display  = (proto.value === 'pppoe')  ? '' : 'none';
		staticBox.style.display = (proto.value === 'static') ? '' : 'none';
	}
	proto.onchange = sync; sync();

	var btn = E('button', { class:'kt-btn' }, [ ktIc('save'), ' ' + _('تطبيق WAN') ]);
	btn.addEventListener('click', function(){
		var p = proto.value, params;
		if (p === 'pppoe'){
			if (!pUser.value) return ui.addNotification(null, E('p', {}, _('اسم مستخدم PPPoE مطلوب')), 'error');
			params = { act:'wan_pppoe', user:pUser.value, pass:pPass.value };
		} else if (p === 'static'){
			if (!sIp.value) return ui.addNotification(null, E('p', {}, _('عنوان IP مطلوب')), 'error');
			params = { act:'wan_static', ip:sIp.value, mask:sMask.value, gw:sGw.value, dns:sDns.value };
		} else {
			params = { act:'wan_dhcp' };
		}
		btn.disabled = true; var lbl = btn.innerHTML; btn.textContent = '…';
		postCall(params).then(function(j){ btn.disabled = false; btn.innerHTML = lbl; notify(j); });
	});

	return E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
		cardHead(ktIc('globe'), _('إعداد WAN / الإنترنت'), _('اختر نوع اتصالك بالإنترنت — DHCP تلقائي أو PPPoE أو عنوان ثابت'), 'g'),
		segField(_('نوع الاتصال (proto)'), proto),
		pppoeBox, staticBox,
		E('div', { class:'kt-wz-foot' }, [
			E('span', { class:'fhint' }, _('يُعاد ضبط واجهة WAN فور التطبيق')),
			btn
		])
	]);
}

/* ---------------- UNIFIED device-wide VLAN card ----------------
   ONE VLAN id applied to the WHOLE AP at once: tagged on every LAN port AND
   bound to every Wi-Fi SSID (both bands) together — not a per-SSID toggle.
   Management stays on the untagged LAN (the backend keeps VLAN 1 untagged on
   all ports) so applying a VLAN can never lock the operator out. */
/* 3 modes only: Bridge (no VLAN) / VLAN (pick the entry port) / Mesh-in-VLAN.
   Maps to the vlan_flex backend; management stays reachable via the VLAN gateway. */
function vlanFlexCard(radios){
	var modeSel = E('select', { class:'cbi-input-select' }, [
		E('option', { value:'bridge' }, _('بردج — بدون VLAN (LAN عادي)')),
		E('option', { value:'vlan' },   _('VLAN — اختيار منفذ الدخول')),
		E('option', { value:'mesh' },   _('Mesh ضمن الـ VLAN'))
	]);
	var vid = E('input', { type:'text', class:'cbi-input-text', maxlength:'4', placeholder:_('2–4094') });
	var vidField = E('div', { class:'kt-field' }, [ E('label', {}, _('VLAN ID')), vid ]);
	var portSel = E('select', { class:'cbi-input-select' },
		['lan1','lan2','lan3','lan4'].map(function(p){ return E('option', { value:p }, p.toUpperCase()); }));
	var portField = segField(_('منفذ الدخول'), portSel);
	/* mesh-mode controls: pick the band/radio + Mesh ID + optional key. The chosen
	   radio runs the mesh AND serves phone clients on the same band (backend). */
	var meshRadios = (radios || []).filter(function(r){ return r.radio; });
	var radioSel = E('select', { class:'cbi-input-select' },
		meshRadios.map(function(r){ return E('option', { value:r.radio }, (is5g(r.band) ? '5G' : '2.4G') + ' — ' + r.radio); }));
	var meshId = E('input', { type:'text', class:'cbi-input-text', maxlength:'32', placeholder:_('مثال: mesh-home') });
	var meshKey = E('input', { type:'text', class:'cbi-input-text', maxlength:'63', placeholder:_('8+ أحرف، فارغ = مفتوح') });
	var meshFields = E('div', {}, [
		segField(_('تردد الميش (الراديو)'), radioSel),
		E('div', { class:'kt-field' }, [ E('label', {}, _('Mesh ID')), meshId ]),
		E('div', { class:'kt-field' }, [ E('label', {}, _('مفتاح الميش (اختياري)')), meshKey ])
	]);
	function syncMode(){
		var m = modeSel.value;
		vidField.style.display   = (m === 'bridge') ? 'none' : '';
		portField.style.display  = (m === 'vlan')   ? '' : 'none';
		meshFields.style.display = (m === 'mesh')   ? '' : 'none';
	}
	modeSel.addEventListener('change', syncMode);
	var btn = E('button', { class:'kt-btn' }, [ ktIc('check'), ' ' + _('تطبيق') ]);
	btn.addEventListener('click', function(){
		var m = modeSel.value;
		btn.disabled = true;
		var p;
		if (m === 'bridge') {
			p = { act:'vlan_flex', vid:'' };                                  /* reset to plain LAN */
		} else {
			if (!/^([0-9]{1,4})$/.test(vid.value) || +vid.value < 2 || +vid.value > 4094) {
				btn.disabled = false;
				return ui.addNotification(null, E('p', {}, _('أدخل رقم VLAN صحيح (2–4094)')), 'error');
			}
			if (m === 'mesh') {
				if (!meshId.value.trim()){ btn.disabled = false; return ui.addNotification(null, E('p', {}, _('أدخل Mesh ID')), 'error'); }
				if (!radioSel.value){ btn.disabled = false; return ui.addNotification(null, E('p', {}, _('لا يوجد راديو متاح للميش')), 'error'); }
				p = { act:'mesh_vlan', vid:vid.value, radio:radioSel.value, mesh_id:meshId.value.trim(), key:meshKey.value };
			} else {
				/* VLAN mode: chosen port on the VLAN AND both Wi-Fi bands on it too */
				p = { act:'vlan_flex', vid:vid.value, mode:'access', wifi:'1', mesh:'0', ports:portSel.value };
			}
		}
		postCall(p).then(function(j){ btn.disabled = false; notify(j); setTimeout(refreshState, 600); })
			.catch(function(){ btn.disabled = false; notify(null); });
	});
	/* live read-back of the ACTUAL applied config (proves it is real, not fake) */
	var stateBox = E('div', { class:'kt-note muted', style:'margin-top:10px' }, [ ktIc('search'), ' ' + _('جارٍ قراءة الحالة الفعلية من الجهاز…') ]);
	function refreshState(){
		call({ op:'vlan_state' }).then(function(s){
			if (!s || !s.ok){ stateBox.textContent = _('تعذّر قراءة الحالة'); return; }
			var parts = [ (s.filtering === '1') ? _('VLAN مفعّل') : _('بردج (بدون VLAN)') ];
			(s.vlans || []).forEach(function(v){ if (v.vlan && v.vlan !== '1') parts.push('VLAN ' + v.vlan + (v.ports ? (' [' + v.ports + ']') : '')); });
			(s.wifi || []).forEach(function(w){ if (w.network && w.network !== 'lan') parts.push((w.ssid || w.mode || 'wifi') + ' → ' + w.network); });
			stateBox.textContent = '';
			stateBox.appendChild(ktIc('check'));
			stateBox.appendChild(document.createTextNode(' ' + _('المطبّق فعلياً على الجهاز') + ': ' + parts.join(' · ')));
		}).catch(function(){ stateBox.textContent = _('تعذّر قراءة الحالة'); });
	}
	var card = E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
		cardHead(ktIc('tag'), _('VLAN'), _('اختر الوضعية — والباقي يبقى LAN.'), 'v'),
		segField(_('الوضعية'), modeSel),
		vidField,
		portField,
		meshFields,
		E('div', { class:'kt-note info' }, _('بردج = بدون VLAN. VLAN = يضع المنفذ المختار + الواي‑فاي (2.4G و5G) على الـ VLAN، والباقي LAN. Mesh = يشغّل الميش على التردد المختار ويخدم الجوالات على نفس التردد، الكل على الـ VLAN. الإدارة تبقى قابلة للوصول دائماً.')),
		stateBox,
		E('div', { class:'kt-wz-foot' }, [ E('span', { class:'fhint' }, _('يطبّق فوراً')), btn ])
	]);
	syncMode();
	refreshState();
	return card;
}

return view.extend({
	load: function(){ return call({op:'wifi_radios'}); },

	render: function(rad){
		rad = rad || {};
		var radios = (rad.ok && rad.radios) ? rad.radios : [];

		var box = E('div', { dir:'rtl' }, [
			E('div', { class:'kt-wz-hero kt-wz-anim' }, [
				E('div', { class:'kt-wz-hero-row' }, [
					E('div', { class:'kt-wz-hero-ic' }, [ ktIc('gear') ]),
					E('div', { class:'kt-wz-hero-txt' }, [
						E('h2', {}, _('الإعدادات السريعة — ضبط فوري')),
						E('p', {}, _('كل بطاقة تُطبّق فوراً عند الضغط على «تطبيق» — لا حاجة للتنقّل بين صفحات الواجهات أو الوايرلس أو VLAN. اضبط الراديو والـ WAN (مع PPPoE) وربط SSID بـ VLAN من مكان واحد.'))
					]),
					E('span', { class:'kt-wz-hero-chip' }, [ ktIc('bolt'), ' ' + _('تطبيق فوري') ])
				])
			])
		]);

		/* ---- Tab panels (ALL kept in the DOM at all times; tabs only show/hide
		   them via .is-active, so every element handle/closure built below stays
		   live — the WAN async refill, scan rows, mode wiring, toggles, etc.). ---- */

		/* Wireless: the per-radio cards (or an empty-state card) — not the default tab */
		var wlPanel = E('div', { class:'kt-tab-panel', 'data-tab':'wifi' });
		if (!radios.length){
			wlPanel.appendChild(E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
				cardHead(ktIc('wifi'), _('الوايرلس'), _('لم يتم العثور على إعدادات راديو'), ''),
				E('div', { class:'kt-note' }, _('تعذّر قراءة إعدادات الوايرلس'))
			]));
		} else {
			var grid = E('div', { class:'kt-grid kt-cols-2' });
			radios.forEach(function(r){ grid.appendChild(radioCard(r)); });
			wlPanel.appendChild(grid);
		}

		/* TAB 2 — WAN: render a placeholder now, then fire-and-fill proto from op=wan */
		var wanPanel = E('div', { class:'kt-tab-panel', 'data-tab':'wan' });
		var wanSlot = E('div', {}, wanCard(''));
		wanPanel.appendChild(wanSlot);
		call({op:'wan'}).then(function(w){
			if (w && w.ok){ wanSlot.innerHTML = ''; wanSlot.appendChild(wanCard(w.proto || '')); }
		});

		/* TAB 1 (DEFAULT) — VLAN: unified device-wide VLAN (all ports + all wifi) */
		var vlanPanel = E('div', { class:'kt-tab-panel is-active', 'data-tab':'vlan' });
		vlanPanel.appendChild(vlanFlexCard(radios));

		var panels = [ vlanPanel, wlPanel, wanPanel ];

		/* ---- styled tab bar: buttons toggle which panel is visible (default first).
		   We NEVER detach panels — only flip the .is-active class, so existing
		   element handles and event closures keep working. ---- */
		var tabDefs = [
			{ key:'vlan', icon:'tag', label:_('VLAN') },
			{ key:'wifi', icon:'wifi', label:_('الوايرلس') },
			{ key:'wan',  icon:'globe', label:_('WAN') }
		];
		var tabBtns = [];
		function selectTab(key){
			tabBtns.forEach(function(b){
				var on = (b.getAttribute('data-tab') === key);
				b.classList.toggle('is-active', on);
				b.setAttribute('aria-selected', on ? 'true' : 'false');
			});
			panels.forEach(function(p){
				p.classList.toggle('is-active', p.getAttribute('data-tab') === key);
			});
		}
		var tabBar = E('div', { class:'kt-tabs', role:'tablist' }, tabDefs.map(function(t){
			var b = E('button', {
				class:'kt-tab' + (t.key === 'vlan' ? ' is-active' : ''),
				type:'button', role:'tab', 'data-tab':t.key,
				'aria-selected': (t.key === 'vlan') ? 'true' : 'false'
			}, [
				E('span', { class:'kt-tab-ic' }, [ ktIc(t.icon) ]),
				E('span', { class:'kt-tab-lbl' }, t.label)
			]);
			b.addEventListener('click', function(){ selectTab(t.key); });
			tabBtns.push(b);
			return b;
		}));

		box.appendChild(tabBar);
		box.appendChild(E('div', { class:'kt-tab-body' }, panels));

		return box;
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
