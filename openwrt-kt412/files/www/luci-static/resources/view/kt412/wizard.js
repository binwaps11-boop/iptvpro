'use strict';
'require view';
'require ui';

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
function bandTitle(band){ return is5g(band) ? _('📡 واي‑فاي 5G') : _('📶 واي‑فاي 2.4G'); }
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
		E('label', {}, _('🔒 كلمة المرور')),
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
	var scanBtn = E('button', { class:'kt-btn', style:'margin-bottom:8px' }, _('🔍 بحث عن الشبكات'));
	scanBtn.addEventListener('click', function(){
		scanBtn.disabled = true;
		var lbl = scanBtn.textContent; scanBtn.textContent = _('جارٍ البحث…');
		scanResults.innerHTML = '';
		call({ op:'wscan', radio:r.radio }).then(function(j){
			scanBtn.disabled = false; scanBtn.textContent = lbl;
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
		E('label', {}, _('📡 الشبكات القريبة')),
		scanBtn,
		scanResults
	]);

	/* ---- mode <select> wiring: dynamic SSID/Mesh-ID label + scan visibility ---- */
	function syncMode(){
		var m = modeSel.value;
		if (m === 'mesh'){
			ssidLabel.textContent = _('🕸️ Mesh ID (معرّف الشبكة)');
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

	var btn = E('button', { class:'kt-btn' }, _('💾 تطبيق'));
	btn.addEventListener('click', function(){
		if (!validSsid(ssid.value))
			return ui.addNotification(null, E('p', {}, _('SSID مطلوب (1–32 حرفاً)')), 'error');
		var open = (secSel.value === 'open');
		/* secured network + blank key + a key already exists => keep the current key */
		var keepkey = (!open && !key.value && hasKey);
		if (!open && !keepkey && !validKey(key.value))
			return ui.addNotification(null, E('p', {}, _('المفتاح يجب أن يكون 8–63 حرفاً')), 'error');
		btn.disabled = true; var lbl = btn.textContent; btn.textContent = '…';
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
			btn.disabled = false; btn.textContent = lbl;
			if (jp && jp.ok)
				ui.addNotification(null, E('p', {}, _('الطاقة: مطلوب %s / مُطبّق %s dBm').format(jp.requested, jp.actual)), 'info');
			else
				notify(jp);   /* surface a txpower failure instead of silently swallowing it */
		}).catch(function(){
			btn.disabled = false; btn.textContent = lbl; notify(null);
		});
	});

	var bandIcon = is5g(r.band) ? '📡' : '📶';
	var bandSub  = is5g(r.band)
		? _('نطاق 5 جيجاهرتز — سرعة أعلى ومدى أقصر')
		: _('نطاق 2.4 جيجاهرتز — تغطية أوسع وتوافق أعلى');

	/* power control: live neon bubble + scale rail */
	var pwrBlock = E('div', { class:'kt-wz-pwr' }, [
		E('div', { class:'kt-wz-pwr-top' }, [
			E('span', { class:'lbl' }, [ E('span', {}, '⚡'), E('span', {}, _('الطاقة (TxPower)')) ]),
			pwval
		]),
		rng,
		E('div', { class:'kt-wz-scale' }, [ E('span', {}, '0'), E('span', {}, '15'), E('span', {}, '30 dBm') ])
	]);

	return E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
		cardHead(bandIcon, bandTitle(r.band).replace(/^[^\s]+\s/, ''), bandSub + ' · ' + (r.radio||''),
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
		E('div', { class:'kt-field' }, [ E('label', {}, _('👤 المستخدم')), pUser ]),
		E('div', { class:'kt-field' }, [ E('label', {}, _('🔒 كلمة المرور')), pPass ])
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

	var btn = E('button', { class:'kt-btn' }, _('💾 تطبيق WAN'));
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
		btn.disabled = true; var lbl = btn.textContent; btn.textContent = '…';
		postCall(params).then(function(j){ btn.disabled = false; btn.textContent = lbl; notify(j); });
	});

	return E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
		cardHead('🌐', _('إعداد WAN / الإنترنت'), _('اختر نوع اتصالك بالإنترنت — DHCP تلقائي أو PPPoE أو عنوان ثابت'), 'g'),
		segField(_('نوع الاتصال (proto)'), proto),
		pppoeBox, staticBox,
		E('div', { class:'kt-wz-foot' }, [
			E('span', { class:'fhint' }, _('يُعاد ضبط واجهة WAN فور التطبيق')),
			btn
		])
	]);
}

/* ---------------- VLAN-per-SSID card ---------------- */
function vlanCard(radios){
	var sel = E('select', { class:'cbi-input-select' },
		radios.filter(function(r){ return r.iface; }).map(function(r){
			return E('option', { value:r.iface }, bandShort(r.band) + ' — ' + (r.ssid || r.iface));
		}));
	var vid = E('input', { type:'text', class:'cbi-input-text', maxlength:'4', placeholder:_('2–4094، فارغ=LAN') });
	var btn = E('button', { class:'kt-btn' }, _('تطبيق'));
	btn.addEventListener('click', function(){
		if (!sel.value) return ui.addNotification(null, E('p', {}, _('لا توجد واجهة SSID')), 'error');
		if (!validVid(vid.value)) return ui.addNotification(null, E('p', {}, _('VLAN ID يجب أن يكون 1–4094 أو فارغاً')), 'error');
		btn.disabled = true; var lbl = btn.textContent; btn.textContent = '…';
		postCall({ act:'vlan_ssid', ssid:sel.value, vid:vid.value }).then(function(j){
			btn.disabled = false; btn.textContent = lbl; notify(j);
		});
	});
	return E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
		cardHead('🏷️', _('ربط SSID بـ VLAN'), _('اعزل شبكة لاسلكية على VLAN موسوم أو اتركها على LAN'), 'v'),
		E('div', { class:'kt-grid kt-cols-2' }, [
			segField('SSID', sel),
			E('div', { class:'kt-field' }, [ E('label', {}, _('VLAN ID')), vid ])
		]),
		E('div', { class:'kt-note' }, _('فارغ أو 1 = LAN غير موسوم. غير ذلك = VLAN موسوم (2–4094).')),
		E('div', { class:'kt-wz-foot' }, [
			E('span', { class:'fhint' }, _('يربط الواجهة المحددة بالشبكة المختارة')),
			btn
		])
	]);
}

return view.extend({
	load: function(){ return call({op:'wifi_radios'}); },

	render: function(rad){
		rad = rad || {};
		var radios = (rad.ok && rad.radios) ? rad.radios : [];

		var box = E('div', { dir:'rtl' }, [
			E('div', { class:'kt-wz-hero kt-wz-anim' }, [
				E('div', { class:'kt-wz-hero-row' }, [
					E('div', { class:'kt-wz-hero-ic' }, '⚙️'),
					E('div', { class:'kt-wz-hero-txt' }, [
						E('h2', {}, _('الإعدادات السريعة — ضبط فوري')),
						E('p', {}, _('كل بطاقة تُطبّق فوراً عند الضغط على «تطبيق» — لا حاجة للتنقّل بين صفحات الواجهات أو الوايرلس أو VLAN. اضبط الراديو والـ WAN (مع PPPoE) وربط SSID بـ VLAN من مكان واحد.'))
					]),
					E('span', { class:'kt-wz-hero-chip' }, _('⚡ تطبيق فوري'))
				])
			])
		]);

		/* ---- Tab panels (ALL kept in the DOM at all times; tabs only show/hide
		   them via .is-active, so every element handle/closure built below stays
		   live — the WAN async refill, scan rows, mode wiring, toggles, etc.). ---- */

		/* TAB 1 — Wireless: the per-radio cards (or an empty-state card) */
		var wlPanel = E('div', { class:'kt-tab-panel is-active', 'data-tab':'wifi' });
		if (!radios.length){
			wlPanel.appendChild(E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
				cardHead('📶', _('الوايرلس'), _('لم يتم العثور على إعدادات راديو'), ''),
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

		/* TAB 3 — VLAN: SSID↔VLAN binding (only when we actually have radios) */
		var vlanPanel = E('div', { class:'kt-tab-panel', 'data-tab':'vlan' });
		if (radios.length) vlanPanel.appendChild(vlanCard(radios));
		else vlanPanel.appendChild(E('div', { class:'kt-card kt-wz-card kt-wz-anim' }, [
			cardHead('🏷️', _('ربط SSID بـ VLAN'), _('لا توجد واجهات لاسلكية متاحة'), 'v'),
			E('div', { class:'kt-note' }, _('تعذّر العثور على واجهات SSID لربطها بـ VLAN'))
		]));

		var panels = [ wlPanel, wanPanel, vlanPanel ];

		/* ---- styled tab bar: buttons toggle which panel is visible (default first).
		   We NEVER detach panels — only flip the .is-active class, so existing
		   element handles and event closures keep working. ---- */
		var tabDefs = [
			{ key:'wifi', icon:'📶', label:_('الوايرلس') },
			{ key:'wan',  icon:'🌐', label:_('WAN') },
			{ key:'vlan', icon:'🏷️', label:_('VLAN') }
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
				class:'kt-tab' + (t.key === 'wifi' ? ' is-active' : ''),
				type:'button', role:'tab', 'data-tab':t.key,
				'aria-selected': (t.key === 'wifi') ? 'true' : 'false'
			}, [
				E('span', { class:'kt-tab-ic' }, t.icon),
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
