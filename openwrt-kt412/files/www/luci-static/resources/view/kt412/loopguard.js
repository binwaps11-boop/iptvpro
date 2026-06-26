'use strict';
'require view';
'require ui';

/* KT412 MK APP — Loop Prevention & Port/Client Isolation (مكافح اللوب).
   Toggles persisted via the kt412-diag CGI (op=getloop / op=setloop -> uci):
     - STP on br-lan
     - IGMP snooping (multicast snooping / BPDU-style flood guard)
     - AP/client isolation (wireless 'isolate')
     - per-port isolation (bridge_slave isolated)
   RTL Arabic, mobile-first. */

var API = '/cgi-bin/kt412-diag';
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

function toggle(checked){
	return E('input', { type:'checkbox', checked: checked ? 'checked' : null });
}

return view.extend({
	load: function(){
		return call({ op:'getloop' }).catch(function(){ return {}; });
	},
	render: function(res){
		var st = res || {};

		var cbStp  = toggle(+st.stp);
		var cbIgmp = toggle(+st.igmp_snooping);
		var cbAp   = toggle(+st.ap_isolate);
		var cbPort = toggle(+st.port_isolate);

		function field(cb, title, desc){
			return E('div', { class:'kt-card' }, [
				E('div', { style:'display:flex;align-items:center;justify-content:space-between;gap:10px' }, [
					E('div', {}, [
						E('div', { style:'font-weight:700' }, title),
						E('div', { class:'kt-sub' }, desc)
					]),
					E('label', { style:'flex:0 0 auto' }, cb)
				])
			]);
		}

		var applyBtn = E('button', { class:'kt-btn', style:'margin-top:14px' }, _('⚡ تطبيق'));
		applyBtn.onclick = function(){
			applyBtn.textContent = '…';
			call({
				op:'setloop',
				stp: cbStp.checked ? '1' : '0',
				igmp_snooping: cbIgmp.checked ? '1' : '0',
				ap_isolate: cbAp.checked ? '1' : '0',
				port_isolate: cbPort.checked ? '1' : '0'
			}, true).then(function(r){
				applyBtn.textContent = _('⚡ تطبيق');
				if (r && r.ok)
					ui.addNotification(null, E('p', {}, r.msg || _('تم التطبيق.')), 'info');
				else
					ui.addNotification(null, E('p', {}, _('فشل: %s').format((r&&r.error)||'')), 'error');
			});
		};

		return E('div', {}, [
			E('h2', {}, _('مكافح اللوب — منع اللوب والعزل')),
			E('div', { class:'kt-grid' }, [
				field(cbStp,  _('🔁 STP (شجرة الامتداد)'),
					_('يمنع حلقات اللوب على الجسر br-lan تلقائياً. يُنصح بتفعيله دائماً.')),
				field(cbIgmp, _('📡 تتبّع IGMP (Multicast Snooping)'),
					_('يقلّل إغراق البث المتعدد ويحدّ من عواصف البث الناتجة عن اللوب.')),
				field(cbAp,   _('🚫 عزل عملاء الواي‑فاي (AP Isolation)'),
					_('يمنع أجهزة الواي‑فاي من رؤية/مهاجمة بعضها — أمان للشبكات العامة.')),
				field(cbPort, _('🔌 عزل المنافذ (Port Isolation)'),
					_('يعزل منافذ LAN عن بعضها (تمر فقط نحو منفذ التوصيل) — يكسر اللوب بين المنافذ.'))
			]),
			applyBtn
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
