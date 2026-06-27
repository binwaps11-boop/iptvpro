'use strict';
'require view';
'require poll';

/* KT412 "MK APP" — Overview / Specifications (بيانات الجهاز والمواصفات).
   Card grid of SoC/CPU, arch/target, brand/model, kernel, OpenWrt version,
   exact uptime, RAM/flash totals, MAC, wifi phys. Backend: kt412-tools op=specs. */

var API = '/cgi-bin/kt412-tools';
var TOKEN = '';

function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c];}); }
function human(kb){ var b=(+kb||0)*1024, u=['B','KB','MB','GB','TB'], i=0; while(b>=1024&&i<u.length-1){b/=1024;i++;} return b.toFixed(b<10&&i>0?1:0)+' '+u[i]; }

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

function kv(k,v){ return '<div class="kt-kv"><span class="k">'+esc(k)+'</span><span class="v">'+esc(v)+'</span></div>'; }
function dur(s){
	/* coerce + default so a missing field never prints the literal "undefined" */
	if (s.up_d==null && s.up_h==null && s.up_m==null && s.up_s==null) return '—';
	var d=+s.up_d||0, h=+s.up_h||0, m=+s.up_m||0, sec=+s.up_s||0;
	return d+'ي : '+h+'س : '+m+'د : '+sec+'ث';
}

function reload(container){
	return call({op:'specs'}).then(function(s){
		if (!s || !s.ok){ container.innerHTML = '<div class="kt-card"><div class="kt-sub">'+_('تعذّر قراءة بيانات الجهاز')+'</div></div>'; return; }

		var phys = (s.phys && s.phys.length) ? s.phys.join('، ') : '—';
		var freq = (+s.cpu_freq_mhz>0) ? (s.cpu_freq_mhz+' MHz') : (s.cpu_bogomips ? (s.cpu_bogomips+' BogoMIPS') : '—');

		var cardSoc = '<div class="kt-card"><h3>🧠 '+_('المعالج (SoC / CPU)')+'</h3>'
			+ kv(_('الطراز'), s.cpu_model||'—')
			+ kv(_('الأنوية'), s.cpu_cores)
			+ kv(_('التردد'), freq)
			+ kv(_('المعمارية'), s.arch||'—')
			+ kv(_('الهدف (target)'), s.target||'ath79/nand')
			+ '</div>';

		var cardDev = '<div class="kt-card"><h3>📦 '+_('الجهاز')+'</h3>'
			+ kv(_('الموديل'), s.model||'KT412')
			+ kv(_('اسم اللوحة'), s.board_name||'—')
			+ kv(_('MAC الأساسي'), s.mac||'—')
			+ kv(_('واجهات الواي‑فاي (PHY)'), phys)
			+ '</div>';

		var cardSys = '<div class="kt-card"><h3>🛠️ '+_('النظام')+'</h3>'
			+ kv(_('إصدار OpenWrt'), s.release||'—')
			+ kv(_('نواة Kernel'), s.kernel||'—')
			+ kv(_('مدة التشغيل'), dur(s))
			+ '</div>';

		var memUsed = (+s.mem_total_kb) - (+s.mem_avail_kb);
		var cardMem = '<div class="kt-card"><h3>💾 '+_('الذاكرة والتخزين')+'</h3>'
			+ kv(_('RAM الكلية'), human(s.mem_total_kb))
			+ kv(_('RAM المستخدمة'), human(memUsed)+' / '+human(s.mem_total_kb))
			+ kv(_('فلاش (نظام /)'), human(s.root_used_kb)+' / '+human(s.root_total_kb))
			+ ((+s.ovl_total_kb>0) ? kv(_('فلاش (overlay)'), human(s.ovl_used_kb)+' / '+human(s.ovl_total_kb)) : '')
			+ '</div>';

		container.innerHTML = '<div class="kt-grid kt-cols-2">'+cardSoc+cardDev+cardSys+cardMem+'</div>';
	});
}

return view.extend({
	render: function(){
		var box = E('div', {}, [
			E('h2', {}, _('بيانات الجهاز والمواصفات')),
			E('div', { 'class':'kt-body', 'dir':'rtl' }, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')))
		]);
		var body = box.querySelector('.kt-body');
		reload(body);
		poll.add(function(){ return reload(body); }, 5);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
