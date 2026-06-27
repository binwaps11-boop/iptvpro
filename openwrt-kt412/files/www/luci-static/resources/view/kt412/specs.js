'use strict';
'require view';
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

		var cardSoc = '<div class="kt-card"><h3>'+ktIcSvg('cpu')+' '+_('المعالج (SoC / CPU)')+'</h3>'
			+ kv(_('الطراز'), s.cpu_model||'—')
			+ kv(_('الأنوية'), s.cpu_cores)
			+ kv(_('التردد'), freq)
			+ kv(_('المعمارية'), s.arch||'—')
			+ kv(_('الهدف (target)'), s.target||'ath79/nand')
			+ '</div>';

		var cardDev = '<div class="kt-card"><h3>'+ktIcSvg('box')+' '+_('الجهاز')+'</h3>'
			+ kv(_('الموديل'), s.model||'KT412')
			+ kv(_('اسم اللوحة'), s.board_name||'—')
			+ kv(_('MAC الأساسي'), s.mac||'—')
			+ kv(_('واجهات الواي‑فاي (PHY)'), phys)
			+ '</div>';

		var cardSys = '<div class="kt-card"><h3>'+ktIcSvg('gear')+' '+_('النظام')+'</h3>'
			+ kv(_('إصدار OpenWrt'), s.release||'—')
			+ kv(_('نواة Kernel'), s.kernel||'—')
			+ kv(_('مدة التشغيل'), dur(s))
			+ '</div>';

		var memUsed = (+s.mem_total_kb) - (+s.mem_avail_kb);
		var cardMem = '<div class="kt-card"><h3>'+ktIcSvg('save')+' '+_('الذاكرة والتخزين')+'</h3>'
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
		/* hardware specs are near-static (model/CPU/flash/kernel rarely change),
		   so a 5s poll forked the CGI 12x/min for nothing. 30s is plenty. */
		poll.add(function(){ return reload(body); }, 30);
		return box;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
