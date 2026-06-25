'use strict';
'require view';
'require ui';

/* KT412 Smart AP — Quick Settings (إعدادات سريعة) LuCI view.
   Reuses the EXISTING backend act=quick_setup (one-shot SSID/pass/country/
   mode/channels/LAN IP). TX power is intentionally NOT controlled here — power
   is adjusted only in LuCI's native Network > Wireless section. Labels/values
   only, no explanatory text. */

var API = '/cgi-bin/kt412';
var TOKEN = '';

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

function chanFill(sel, list, band){
	sel.innerHTML = '';
	sel.appendChild(E('option', {value:''}, _('بلا تغيير')));
	(list||[]).forEach(function(c){ sel.appendChild(E('option', {value:String(c.ch)}, String(c.ch)+(+c.dfs?' (DFS)':''))); });
}

return view.extend({
	load: function(){
		return Promise.all([ call({op:'chanlist'}), call({op:'lan'}) ]);
	},
	render: function(res){
		var cl = res[0] || {}, lan = res[1] || {};

		var ssid    = E('input', { type:'text', class:'cbi-input-text', placeholder:'KT412' });
		var pass    = E('input', { type:'text', class:'cbi-input-text', placeholder:_('اتركها فارغة للإبقاء') });
		var open    = E('input', { type:'checkbox' });
		var hidden  = E('input', { type:'checkbox' });
		var country = E('input', { type:'text', class:'cbi-input-text', value:'US', maxlength:'2', style:'text-transform:uppercase' });
		var lanip   = E('input', { type:'text', class:'cbi-input-text', placeholder:(lan.ok && lan.ip) ? lan.ip : '192.168.1.1' });

		var mode = E('select', { class:'cbi-input-select' }, [
			E('option', { value:'access' }, _('Access / راوتر (AP)')),
			E('option', { value:'pppoe' }, _('PPPoE Client')),
			E('option', { value:'station' }, _('Station (عميل واي‑فاي)'))
		]);
		var pUser = E('input', { type:'text', class:'cbi-input-text', placeholder:'username' });
		var pPass = E('input', { type:'text', class:'cbi-input-text', placeholder:'password' });
		var pppoeRow = E('div', { class:'kt-grid kt-cols-2', style:'display:none' }, [
			E('div', { class:'kt-field' }, [ E('label', {}, _('👤 مستخدم PPPoE')), pUser ]),
			E('div', { class:'kt-field' }, [ E('label', {}, _('🔒 كلمة مرور PPPoE')), pPass ])
		]);
		mode.onchange = function(){ pppoeRow.style.display = (mode.value==='pppoe') ? 'grid' : 'none'; };

		var ch24 = E('select', { class:'cbi-input-select' });
		var ch5  = E('select', { class:'cbi-input-select' });
		var r24 = (cl.radios||[]).filter(function(x){ return x.band==='2g'; })[0];
		var r5  = (cl.radios||[]).filter(function(x){ return x.band==='5g'; })[0];
		chanFill(ch24, r24 ? r24.channels : [], '2g');
		chanFill(ch5,  r5  ? r5.channels  : [], '5g');

		var ht24 = E('select', { class:'cbi-input-select' }, [
			E('option', {value:''}, _('بلا تغيير')), E('option', {value:'HT20'}, '20MHz'), E('option', {value:'HT40'}, '40MHz')
		]);
		var ht5 = E('select', { class:'cbi-input-select' }, [
			E('option', {value:''}, _('بلا تغيير')), E('option', {value:'VHT20'}, '20MHz'), E('option', {value:'VHT40'}, '40MHz'), E('option', {value:'VHT80'}, '80MHz')
		]);

		var apply = E('button', { class:'kt-btn', style:'margin-top:14px' }, _('⚡ تطبيق سريع (Safe Apply)'));
		apply.onclick = function(){
			apply.textContent = '…';
			var p = {
				act:'quick_setup',
				ssid: ssid.value, pass: pass.value, country: country.value,
				lan_ip: lanip.value, mode: mode.value,
				pppoe_user: pUser.value, pppoe_pass: pPass.value,
				ch24: ch24.value, ch5: ch5.value, ht24: ht24.value, ht5: ht5.value,
				open: open.checked ? '1' : '0', hidden: hidden.checked ? '1' : '0',
				en24: '1', en5: '1'
			};
			/* Safe Apply: arm rollback first, then apply */
			call({act:'safe_arm'}, true).then(function(a){
				return call(p, true).then(function(r){
					apply.textContent = _('⚡ تطبيق سريع (Safe Apply)');
					if (r && r.ok) ui.addNotification(null, E('p', {}, (r.msg||_('طُبّق')) + ' — ' + _('سيرجع تلقائياً خلال %s ثانية إن انقطع الوصول.').format((a&&a.timeout)||80)), 'warning');
					else ui.addNotification(null, E('p', {}, _('فشل: %s').format((r&&r.error)||'')), 'error');
				});
			});
		};

		var box = E('div', {}, [
			E('h2', {}, _('إعدادات سريعة — Quick Settings')),
			E('div', { class:'kt-card' }, [
				E('div', { class:'kt-grid kt-cols-2' }, [
					E('div', { class:'kt-field' }, [ E('label', {}, _('⚙️ وضع الجهاز')), mode ]),
					E('div', { class:'kt-field' }, [ E('label', {}, _('🌍 الدولة')), country ])
				]),
				pppoeRow,
				E('div', { class:'kt-grid kt-cols-2' }, [
					E('div', { class:'kt-field' }, [ E('label', {}, _('📶 اسم الواي‑فاي (SSID)')), ssid ]),
					E('div', { class:'kt-field' }, [ E('label', {}, _('🔑 كلمة المرور (8 أحرف+)')), pass ])
				]),
				E('div', { class:'kt-grid kt-cols-2' }, [
					E('div', { class:'kt-field' }, [ E('label', {}, [ open, ' ', _('🔓 شبكة مفتوحة') ]) ]),
					E('div', { class:'kt-field' }, [ E('label', {}, [ hidden, ' ', _('🙈 إخفاء اسم الشبكة') ]) ])
				]),
				E('div', { class:'kt-grid kt-cols-2' }, [
					E('div', { class:'kt-field' }, [ E('label', {}, _('📻 قناة 2.4G')), ch24 ]),
					E('div', { class:'kt-field' }, [ E('label', {}, _('📡 قناة 5G')), ch5 ])
				]),
				E('div', { class:'kt-grid kt-cols-2' }, [
					E('div', { class:'kt-field' }, [ E('label', {}, _('📐 عرض قناة 2.4G')), ht24 ]),
					E('div', { class:'kt-field' }, [ E('label', {}, _('📐 عرض قناة 5G')), ht5 ])
				]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('🖥️ IP الإدارة (LAN)')), lanip ]),
				apply
			])
		]);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
