'use strict';
'require view';

/* KT412 Smart AP — LAN / DHCP control panel.
   Surfaces the existing backend ops: op=lan (read) + act=lan_set (write) so the
   operator can set the device LAN IP / netmask and the DHCP server range/lease
   from the custom UI. Same adopt()/call()/postCall() auth as the other views. */

var KTI = {
	globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 0 1 0 18 M12 3a15 15 0 0 0 0 18"/>',
	save:'<path d="M5 3h12l4 4v14H5z M8 3v5h7 M8 21v-6h8v6"/>',
	check:'<path d="M20 6 9 17l-5-5"/>',
	warn:'<path d="M12 3 2 20h20z M12 9v5 M12 17h.01"/>',
	dot:'<circle cx="12" cy="12" r="5"/>'
};
function ktIcSvg(n){return '<svg class="kti" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(KTI[n]||KTI.dot)+'</svg>';}
function ktIc(n){var d=document.createElement('div');d.innerHTML=ktIcSvg(n);return d.firstChild;}
function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c];}); }

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
function fld(lbl, node){ return E('div', { 'class':'kt-field' }, [ E('label', {}, lbl), node ]); }
function validIp(v){ return /^(\d{1,3}\.){3}\d{1,3}$/.test(v); }

function lanCard(){
	var ip   = E('input', { type:'text', class:'cbi-input-text', placeholder:'192.168.1.1' });
	var mask = E('input', { type:'text', class:'cbi-input-text', placeholder:'255.255.255.0' });
	var dh   = E('input', { type:'checkbox' });
	var st   = E('input', { type:'number', class:'cbi-input-text', min:'2', max:'254', placeholder:'100', style:'max-width:130px' });
	var lim  = E('input', { type:'number', class:'cbi-input-text', min:'1', max:'253', placeholder:'150', style:'max-width:130px' });
	var lt   = E('input', { type:'text', class:'cbi-input-text', placeholder:'12h', style:'max-width:130px' });
	var dhcpBox = E('div', { class:'kt-grid kt-cols-3' }, [ fld(_('بداية النطاق'), st), fld(_('عدد العناوين'), lim), fld(_('مدة الإيجار'), lt) ]);
	var stat = E('div', { 'class':'kt-note muted', style:'margin-top:10px' }, _('جارٍ القراءة…'));
	var btn  = E('button', { 'class':'kt-btn' }, [ ktIc('save'), ' ' + _('حفظ') ]);

	function syncDh(){ dhcpBox.style.display = dh.checked ? '' : 'none'; }
	dh.addEventListener('change', syncDh);

	function refresh(){
		call({ op:'lan' }).then(function(j){
			if (!j || !j.ok){ stat.textContent = _('تعذّر القراءة'); return; }
			ip.value = j.ip || ''; mask.value = j.mask || '';
			dh.checked = (j.dhcp !== false);
			st.value = j.start || '100'; lim.value = j.limit || '150'; lt.value = j.lease || '12h';
			syncDh();
			stat.textContent = ''; stat.appendChild(ktIc('check'));
			stat.appendChild(document.createTextNode(' ' + _('العنوان الحالي') + ': ' + (j.ip||'—') + (j.dhcp!==false ? (' · DHCP ' + _('مُفعّل')) : (' · DHCP ' + _('مُطفأ')))));
		}).catch(function(){ stat.textContent = _('تعذّر القراءة'); });
	}

	btn.addEventListener('click', function(){
		if (ip.value && !validIp(ip.value)){ stat.style.color='var(--kt-bad)'; stat.textContent = _('عنوان IP غير صحيح'); return; }
		if (mask.value && !validIp(mask.value)){ stat.style.color='var(--kt-bad)'; stat.textContent = _('قناع الشبكة غير صحيح'); return; }
		btn.disabled = true;
		postCall({ act:'lan_set', ip:ip.value, mask:mask.value, dhcp: dh.checked?'1':'0', start:st.value, limit:lim.value, lease:lt.value })
			.then(function(j){
				btn.disabled = false; stat.style.color = '';
				if (j && j.ok){ stat.style.color='var(--kt-ok)'; stat.textContent = (j.msg || _('تم الحفظ')) + ' — ' + _('إن غيّرت الـ IP أعد الاتصال على العنوان الجديد'); }
				else { stat.style.color='var(--kt-bad)'; stat.textContent = _('فشل الحفظ'); }
				setTimeout(refresh, 1200);
			}).catch(function(){ btn.disabled = false; stat.textContent = _('فشل الحفظ'); });
	});

	refresh();
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ ktIc('globe'), ' ' + _('إعدادات LAN / DHCP') ]),
		E('div', { 'class':'kt-sub' }, _('عنوان الجهاز على الشبكة المحلية وخادم توزيع العناوين (DHCP).')),
		E('div', { 'class':'kt-grid kt-cols-2', style:'margin-top:10px' }, [ fld(_('عنوان IP'), ip), fld(_('قناع الشبكة'), mask) ]),
		E('div', { 'class':'kt-field' }, [ E('label', { style:'display:flex;align-items:center;gap:8px' }, [ dh, E('span', {}, _('تفعيل خادم DHCP')) ]) ]),
		dhcpBox,
		E('div', { 'class':'kt-note info' }, [ ktIc('warn'), ' ' + _('تغيير عنوان IP يقطع جلستك — افتح اللوحة على العنوان الجديد بعد الحفظ.') ]),
		stat,
		E('div', { style:'margin-top:10px' }, btn)
	]);
}

return view.extend({
	render: function(){
		return E('div', { 'dir':'rtl' }, [
			E('h2', {}, _('LAN / DHCP')),
			E('div', { 'class':'kt-grid' }, [ lanCard() ])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
