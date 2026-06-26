'use strict';
'require view';
'require ui';

/* KT412 Quick Config Wizard (إعدادات سريعة)
   Single RTL view, 4 device presets + per-SSID VLAN mapping. Each preset posts
   op=setmode&mode=... to the OWN backend /cgi-bin/kt412-wizard, which applies a
   pre-baked, idempotent UCI profile then reloads the affected services.
   Auth: adopt the current LuCI admin session id as the token (op=adopt). */

var API = '/cgi-bin/kt412-wizard';
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
function call(params, post){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		var opt = post ? {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:usp.toString()} : undefined;
		var url = post ? API : (API + '?' + usp.toString());
		return fetch(url, opt).then(function(r){ return r.json(); }).catch(function(){ return {ok:false,error:'network'}; });
	});
}

/* ---- client-side validators (the CGI re-validates server-side) ---- */
function validKey(k){ return (typeof k === 'string') && k.length >= 8 && k.length <= 63; }
function validVid(v){ if (v === '' || v === null) return true; var n = +v; return Number.isInteger(n) && n >= 1 && n <= 4094; }
function validSsid(s){ return (typeof s === 'string') && s.length >= 1 && s.length <= 32; }

function notify(r, okMsg){
	if (r && r.ok) ui.addNotification(null, E('p', {}, r.msg || okMsg || _('تم التطبيق')), 'info');
	else ui.addNotification(null, E('p', {}, _('فشل: %s').format((r && r.error) || 'unknown')), 'error');
}

return view.extend({
	load: function(){ return call({op:'getmode'}); },

	render: function(cur){
		cur = cur || {};
		var curMode = cur.ok ? cur.mode : '?';

		/* ---------------- AP MODE ---------------- */
		var apBtn = E('button', { class:'kt-btn' }, _('🛜 تطبيق وضع AP'));
		apBtn.onclick = function(){
			apBtn.textContent = '…';
			call({op:'setmode', mode:'ap'}, true).then(function(r){
				apBtn.textContent = _('🛜 تطبيق وضع AP'); notify(r); });
		};
		var apCard = E('div', { class:'kt-card' }, [
			E('h3', {}, _('① نقطة وصول (Access Point)')),
			E('p', {}, _('جسر LAN لكل المنافذ، DHCP معطّل، WAN غير مستخدم، طاقة عالية. الإدارة 192.168.1.1.')),
			apBtn
		]);

		/* ---------------- MESH (802.11s / batman) ---------------- */
		var mBackhaul = E('select', { class:'cbi-input-select' }, [
			E('option', { value:'11s' }, _('802.11s أصلي (mesh_fwding)')),
			E('option', { value:'batman' }, _('batman-adv (bat0) — مشفّر إلزامي'))
		]);
		var mId  = E('input', { type:'text', class:'cbi-input-text', value:'kt412-mesh', maxlength:'32' });
		var mEnc = E('select', { class:'cbi-input-select' }, [
			E('option', { value:'sae' }, 'WPA3-SAE'),
			E('option', { value:'sae-mixed' }, 'WPA2/3 (sae-mixed)'),
			E('option', { value:'psk2' }, 'WPA2-PSK')
		]);
		var mKey = E('input', { type:'text', class:'cbi-input-text', placeholder:_('مفتاح المش (8 أحرف+)') });
		var mHint = E('p', {}, _('802.11s: المفتاح اختياري (يُنصح به). batman-adv: المفتاح إلزامي لمنع التنصّت.'));
		mBackhaul.onchange = function(){
			mHint.textContent = (mBackhaul.value === 'batman')
				? _('batman-adv: المفتاح إلزامي. يتطلب حزم kmod-batman-adv + batctl.')
				: _('802.11s: المفتاح اختياري (يُنصح به). يتطلب wpad-mesh-mbedtls.');
		};
		var mBtn = E('button', { class:'kt-btn' }, _('🕸️ تفعيل Mesh'));
		mBtn.onclick = function(){
			var bh = mBackhaul.value, key = mKey.value, id = mId.value;
			if (!validSsid(id)) return ui.addNotification(null, E('p', {}, _('mesh_id غير صالح')), 'error');
			if (bh === 'batman' && !validKey(key))
				return ui.addNotification(null, E('p', {}, _('batman-adv يتطلب مفتاحاً من 8 أحرف على الأقل')), 'error');
			if (key && !validKey(key))
				return ui.addNotification(null, E('p', {}, _('المفتاح يجب أن يكون 8–63 حرفاً')), 'error');
			mBtn.textContent = '…';
			call({op:'setmode', mode:'mesh', backhaul:bh, mesh_id:id, enc:mEnc.value, key:key}, true).then(function(r){
				mBtn.textContent = _('🕸️ تفعيل Mesh'); notify(r); });
		};
		var meshCard = E('div', { class:'kt-card' }, [
			E('h3', {}, _('② شبكة Mesh (5G خلفية مخفية)')),
			E('div', { class:'kt-grid kt-cols-2' }, [
				E('div', { class:'kt-field' }, [ E('label', {}, _('نوع الخلفية')), mBackhaul ]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('Mesh ID')), mId ])
			]),
			E('div', { class:'kt-grid kt-cols-2' }, [
				E('div', { class:'kt-field' }, [ E('label', {}, _('التشفير')), mEnc ]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('المفتاح المشترك')), mKey ])
			]),
			mHint, mBtn
		]);

		/* ---------------- WDS ---------------- */
		var wRole = E('select', { class:'cbi-input-select' }, [
			E('option', { value:'ap' }, _('wds-ap (الجذر / Root)')),
			E('option', { value:'sta' }, _('wds-sta (الفرع / Leaf)'))
		]);
		var wBand = E('select', { class:'cbi-input-select' }, [
			E('option', { value:'5g' }, '5GHz'),
			E('option', { value:'2g' }, '2.4GHz')
		]);
		var wSsid = E('input', { type:'text', class:'cbi-input-text', placeholder:'KT412-WDS', maxlength:'32' });
		var wKey  = E('input', { type:'text', class:'cbi-input-text', placeholder:_('مفتاح مشترك (8 أحرف+، أو فارغ=مفتوح)') });
		var wBtn  = E('button', { class:'kt-btn' }, _('🔗 تطبيق WDS'));
		wBtn.onclick = function(){
			if (!validSsid(wSsid.value)) return ui.addNotification(null, E('p', {}, _('SSID مطلوب (1–32 حرفاً)')), 'error');
			if (wKey.value && !validKey(wKey.value)) return ui.addNotification(null, E('p', {}, _('المفتاح 8–63 حرفاً أو فارغ')), 'error');
			wBtn.textContent = '…';
			call({op:'setmode', mode:'wds', role:wRole.value, band:wBand.value, ssid:wSsid.value, key:wKey.value}, true).then(function(r){
				wBtn.textContent = _('🔗 تطبيق WDS'); notify(r); });
		};
		var wdsCard = E('div', { class:'kt-card' }, [
			E('h3', {}, _('③ WDS (جسر L2 شفّاف نقطة-لنقطة)')),
			E('p', {}, _('اضبط الطرفين بنفس SSID والمفتاح. أحدهما wds-ap والآخر wds-sta.')),
			E('div', { class:'kt-grid kt-cols-2' }, [
				E('div', { class:'kt-field' }, [ E('label', {}, _('الدور')), wRole ]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('النطاق')), wBand ])
			]),
			E('div', { class:'kt-grid kt-cols-2' }, [
				E('div', { class:'kt-field' }, [ E('label', {}, _('SSID')), wSsid ]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('المفتاح')), wKey ])
			]),
			wBtn
		]);

		/* ---------------- PPPoE ---------------- */
		var pUser = E('input', { type:'text', class:'cbi-input-text', placeholder:'username' });
		var pPass = E('input', { type:'text', class:'cbi-input-text', placeholder:'password' });
		var pBtn  = E('button', { class:'kt-btn' }, _('🌐 تطبيق PPPoE'));
		pBtn.onclick = function(){
			if (!pUser.value) return ui.addNotification(null, E('p', {}, _('اسم مستخدم PPPoE مطلوب')), 'error');
			pBtn.textContent = '…';
			call({op:'setmode', mode:'pppoe', user:pUser.value, pass:pPass.value}, true).then(function(r){
				pBtn.textContent = _('🌐 تطبيق PPPoE'); notify(r); });
		};
		var pppoeCard = E('div', { class:'kt-card' }, [
			E('h3', {}, _('④ عميل PPPoE (WAN)')),
			E('p', {}, _('يضبط WAN على PPPoE مع عزل WAN في الجدار الناري (MTU 1492).')),
			E('div', { class:'kt-grid kt-cols-2' }, [
				E('div', { class:'kt-field' }, [ E('label', {}, _('👤 المستخدم')), pUser ]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('🔒 كلمة المرور')), pPass ])
			]),
			pBtn
		]);

		/* ---------------- VLAN per SSID ---------------- */
		var vBand = E('select', { class:'cbi-input-select' }, [
			E('option', { value:'2g' }, _('SSID 2.4G')),
			E('option', { value:'5g' }, _('SSID 5G'))
		]);
		var vVid = E('input', { type:'text', class:'cbi-input-text', placeholder:_('VLAN ID 2–4094 (فارغ=LAN غير موسوم)'), maxlength:'4' });
		var vBtn = E('button', { class:'kt-btn' }, _('🏷️ ربط SSID بـ VLAN'));
		vBtn.onclick = function(){
			if (!validVid(vVid.value)) return ui.addNotification(null, E('p', {}, _('VLAN ID يجب أن يكون 1–4094')), 'error');
			vBtn.textContent = '…';
			call({op:'setmode', mode:'vlan', band:vBand.value, vid:vVid.value}, true).then(function(r){
				vBtn.textContent = _('🏷️ ربط SSID بـ VLAN'); notify(r); });
		};
		var vlanCard = E('div', { class:'kt-card' }, [
			E('h3', {}, _('⑤ VLAN لكل SSID (مستقل)')),
			E('p', {}, _('اربط كل SSID بـ VLAN موسوم على منافذ lan1-4 عبر جسر DSA، أو اتركه فارغاً = LAN غير موسوم.')),
			E('div', { class:'kt-grid kt-cols-2' }, [
				E('div', { class:'kt-field' }, [ E('label', {}, _('الشبكة')), vBand ]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('VLAN ID')), vVid ])
			]),
			vBtn
		]);

		return E('div', {}, [
			E('h2', {}, _('إعدادات سريعة — Quick Config Wizard')),
			E('div', { class:'kt-card', style:'margin-bottom:16px' }, [
				E('p', {}, _('الوضع الحالي: ') + curMode)
			]),
			apCard, meshCard, wdsCard, pppoeCard, vlanCard
		]);
	},

	handleSave: null, handleSaveApply: null, handleReset: null
});
