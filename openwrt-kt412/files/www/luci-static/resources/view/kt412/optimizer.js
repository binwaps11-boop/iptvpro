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
function ktIcSvg(n){return '<svg class="kti" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(KTI[n]||KTI.dot)+'</svg>';}
function ktIc(n){var d=document.createElement('div');d.innerHTML=ktIcSvg(n);return d.firstChild;}

/* KT412 "MK APP" — Performance / Optimizer (محسّن الأداء).
   Real client-side LuCI view talking to its OWN backend (/cgi-bin/kt412-perf).
   Tools:
     - Channel Analyzer + Auto-Pick (op=scan/setchan): counts APs per channel
       with congestion bars, recommends least-congested 2.4G (1/6/11) + clean
       non-DFS 5G, applies via uci + wifi reload keeping HT20/VHT80. REAL win.
     - Internet Speed Test (op=spdtest): AP-uplink download Mbit/s via curl +
       ping latency. Editable URL. Measurement only.
     - Turbo (op=turbo): safe housekeeping — re-pin configured txpower, wifi
       reload, drop pagecache, flush stale UDP conntrack. Minor.
     - Live per-client rates (op=clients): assoclist signal/RX/TX/MCS.
   Auth: adopt the LuCI ubus session id once, reuse as token. */

var API = '/cgi-bin/kt412-perf';
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

function bandLabel(b){
	b = String(b||'').toLowerCase();
	if (b.indexOf('2g')>=0) return '2.4 GHz';
	if (b.indexOf('5g')>=0) return '5 GHz';
	return b || '—';
}

/* ---------------- Channel Analyzer + Auto-Pick ---------------- */
function congestionBars(channels, recommend, current){
	var max = 1;
	channels.forEach(function(c){ if (+c.count>max) max=+c.count; });
	var rows = channels.map(function(c){
		var pct = Math.round((+c.count/max)*100);
		var isRec = (String(c.ch)===String(recommend));
		var isCur = (String(c.ch)===String(current));
		var col = isRec ? 'var(--kt-ok)' : (+c.count>=5 ? 'var(--kt-bad)' : (+c.count>=2 ? 'var(--kt-warn)' : 'var(--kt-accent)'));
		var tag = (isCur?' <span class="kt-badge">'+_('الحالية')+'</span>':'') + (isRec?' <span class="kt-badge ok">'+_('موصى بها')+'</span>':'');
		return E('div', { 'class':'kt-row', style:'align-items:center;gap:8px;margin:4px 0' }, [
			E('div', { style:'width:64px;font-size:13px;color:var(--kt-txt2)' }, [ E('span',{},_('قناة')+' '+esc(c.ch)) ]),
			E('div', { style:'flex:1;background:rgba(255,255,255,.06);border-radius:6px;height:16px;overflow:hidden' },
				E('div', { style:'height:100%;width:'+pct+'%;background:'+col+';transition:width .3s' })),
			E('div', { style:'width:120px;font-size:12px', dir:'rtl' }, [ E('span',{},esc(c.count)+' '+_('شبكة')), E('span',{}, tag) ])
		]);
	});
	return E('div', {}, rows);
}

function radioScanCard(r){
	var box = E('div', { 'class':'kt-card' });
	var head = E('h3', {}, [ ktIc('radio'), ' '+bandLabel(r.band)+' ('+esc(r.radio)+')' ]);
	var info = E('div', { 'class':'kt-sub', style:'margin-bottom:8px' },
		_('القناة الحالية')+': '+esc(r.current||'—')+' · '+_('الموصى بها')+': '+esc(r.recommend||'—'));
	var bars = congestionBars(r.channels||[], r.recommend, r.current);
	var msg  = E('div', { 'class':'kt-sub', style:'margin-top:8px' }, '');
	var applyBtn = E('button', { 'class':'kt-btn' },
		_('تطبيق القناة الموصى بها')+' ('+esc(r.recommend||'—')+')');
	applyBtn.disabled = !r.recommend || String(r.recommend)===String(r.current);
	if (String(r.recommend)===String(r.current))
		applyBtn.textContent = _('أنت على أفضل قناة بالفعل');
	applyBtn.addEventListener('click', function(){
		applyBtn.disabled = true; msg.style.color='var(--kt-txt2)'; msg.textContent=_('جارٍ التطبيق وإعادة تحميل الواي‑فاي…');
		call({op:'setchan', radio:r.radio, channel:String(r.recommend)}, true).then(function(j){
			if (j && j.ok){
				msg.style.color='var(--kt-ok)';
				msg.textContent=_('تم')+': '+_('من القناة')+' '+esc(j.before||'—')+' '+_('إلى')+' '+esc(j.after)+' ('+esc(j.htmode||'')+' '+_('محفوظ')+')';
			} else {
				msg.style.color='var(--kt-bad)';
				msg.textContent=_('فشل')+': '+esc((j&&j.error)||'?');
				applyBtn.disabled=false;
			}
		});
	});
	box.appendChild(head); box.appendChild(info); box.appendChild(bars);
	box.appendChild(E('div',{style:'margin-top:10px'},applyBtn)); box.appendChild(msg);
	return box;
}

function analyzerSection(){
	var btn = E('button', { 'class':'kt-btn' }, [ ktIc('search'), ' '+_('فحص القنوات الآن') ]);
	var stat= E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var grid= E('div', { 'class':'kt-grid kt-cols-2' }, '');
	btn.addEventListener('click', function(){
		btn.disabled=true; stat.style.color='var(--kt-txt2)';
		stat.textContent=_('جارٍ مسح الشبكات المجاورة… (قد يستغرق بضع ثوانٍ)'); grid.innerHTML='';
		call({op:'scan'}).then(function(j){
			btn.disabled=false;
			if (!j || !j.ok){ stat.style.color='var(--kt-bad)'; stat.textContent=_('فشل الفحص')+': '+esc((j&&j.error)||'?'); return; }
			if (!j.radios || !j.radios.length){ stat.textContent=_('لا توجد راديوهات'); return; }
			stat.style.color='var(--kt-ok)'; stat.textContent=_('اكتمل الفحص — الأشرطة الأطول = ازدحام أعلى');
			j.radios.forEach(function(r){ grid.appendChild(radioScanCard(r)); });
		});
	});
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ ktIc('wifi'), ' '+_('محلّل القنوات والاختيار التلقائي') ]),
		E('div', { 'class':'kt-sub' }, _('يحسب عدد الشبكات على كل قناة ويوصي بأقلّها ازدحاماً (2.4G: 1/6/11 فقط · 5G: قنوات غير DFS). تطبيق القناة الأنظف = سرعة أعلى فعلياً مع الحفاظ على HT20/VHT80.')),
		E('div', { style:'margin-top:10px' }, btn), stat, grid
	]);
}

/* ---------------- Internet Speed Test ---------------- */
function speedSection(){
	var url = E('input', { type:'text', class:'cbi-input-text', style:'flex:1;min-width:240px',
		value:'https://speed.cloudflare.com/__down?bytes=50000000',
		placeholder:'https://… test file URL' });
	var btn = E('button', { 'class':'kt-btn' }, [ ktIc('speed'), ' '+_('اختبار السرعة') ]);
	var stat= E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var res = E('div', {}, '');
	btn.addEventListener('click', function(){
		btn.disabled=true; stat.style.color='var(--kt-txt2)'; stat.textContent=_('جارٍ القياس… (~5 ثوانٍ)'); res.innerHTML='';
		call({op:'spdtest', url:url.value}, true).then(function(j){
			btn.disabled=false;
			if (!j || (!j.ok && j.error!=='no_internet')){ stat.style.color='var(--kt-bad)'; stat.textContent=_('فشل')+': '+esc((j&&j.error)||'?'); return; }
			if (j.error==='no_internet'){
				stat.style.color='var(--kt-bad)';
				stat.textContent=_('لا يوجد اتصال إنترنت على الوصلة الصاعدة')+(j.ping_ms?(' · ping '+esc(j.ping_ms)+' ms'):'');
				return;
			}
			stat.style.color='var(--kt-ok)'; stat.textContent=_('اكتمل (اختبار وصلة الجهاز الصاعدة)');
			res.innerHTML='<div class="kt-grid kt-cols-2">'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">'+ktIcSvg('down')+' '+_('التنزيل')+'</div><div class="kt-sub" style="font-size:26px;color:var(--kt-ok)">'+esc(j.down_mbps)+' Mbit/s</div></div>'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">'+ktIcSvg('timer')+' '+_('الكمون (ping 1.1.1.1)')+'</div><div class="kt-sub" style="font-size:26px;color:var(--kt-accent)">'+esc(j.ping_ms||'—')+' ms</div></div>'
				+ '</div>';
		});
	});
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ ktIc('globe'), ' '+_('اختبار سرعة الإنترنت') ]),
		E('div', { 'class':'kt-sub' }, _('يقيس سرعة تنزيل الوصلة الصاعدة لهذا الجهاز فقط (قياس، لا يُسرّع). يمكنك تعديل رابط ملف الاختبار.')),
		E('div', { 'class':'kt-row', style:'margin-top:10px' }, [
			E('div', { 'class':'kt-field', style:'flex:1' }, [ E('label',{},_('رابط ملف الاختبار')), url ]),
			E('div', { style:'align-self:flex-end' }, btn)
		]),
		stat, res
	]);
}

/* ---------------- Turbo ---------------- */
function turboSection(){
	var btn = E('button', { 'class':'kt-btn' }, [ ktIc('bolt'), ' '+_('تحسين فوري / Turbo') ]);
	var stat= E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var list= E('ul', { style:'margin:8px 0 0;padding-inline-start:20px' }, '');
	btn.addEventListener('click', function(){
		btn.disabled=true; stat.style.color='var(--kt-txt2)'; stat.textContent=_('جارٍ التحسين…'); list.innerHTML='';
		call({op:'turbo'}, true).then(function(j){
			btn.disabled=false;
			if (!j || !j.ok){ stat.style.color='var(--kt-bad)'; stat.textContent=_('فشل')+': '+esc((j&&j.error)||'?'); return; }
			stat.style.color='var(--kt-ok)'; stat.textContent=_('تم — تحسينات آمنة غير مدمّرة');
			(j.steps||[]).forEach(function(s){ list.appendChild(E('li',{style:'margin:3px 0'}, esc(s))); });
		});
	});
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ ktIc('bolt'), ' '+_('تحسين فوري بنقرة واحدة') ]),
		E('div', { 'class':'kt-sub' }, _('إجراءات آمنة فقط: إعادة تثبيت طاقة الإرسال المُعدّة + إعادة تحميل الواي‑فاي + تفريغ الذاكرة المؤقتة + تنظيف اتصالات UDP القديمة. لا يغيّر أي إعداد طاقة أو تردد.')),
		E('div', { style:'margin-top:10px' }, btn), stat, list
	]);
}

/* ---------------- Live per-client rates ---------------- */
function sigColor(s){ s=parseInt(s,10); if(isNaN(s))return 'var(--kt-txt2)'; if(s>=-67)return 'var(--kt-ok)'; if(s>=-78)return 'var(--kt-warn)'; return 'var(--kt-bad)'; }

function clientsSection(){
	var btn = E('button', { 'class':'kt-btn' }, [ ktIc('users'), ' '+_('عرض العملاء وجودة الوصلة') ]);
	var stat= E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var wrap= E('div', {}, '');
	function render(j){
		wrap.innerHTML='';
		(j.radios||[]).forEach(function(r){
			var rows = (r.clients||[]).map(function(c){
				var nm = (c.name && c.name !== '*') ? c.name : '';
				var label = nm ? (nm + (c.ip ? ' · ' + c.ip : '')) : c.mac;
				return E('div', { 'class':'kt-kv' }, [
					E('span',{'class':'k', title:c.mac}, esc(label)),
					E('span',{'class':'v', dir:'ltr', style:'color:'+sigColor(c.signal)+';text-align:left;direction:ltr'}, [
						(c.signal?esc(c.signal)+' dBm':'—')
						+ ' · ', ktIc('down'), esc(c.rx_mbit||'—')+' ', ktIc('up'), esc(c.tx_mbit||'—')+' Mbit/s'
						+ ((c.rx_mcs||c.tx_mcs)?(' · MCS '+esc(c.rx_mcs||'?')+'/'+esc(c.tx_mcs||'?')):'') ])
				]);
			});
			if (!rows.length) rows=[ E('div',{'class':'kt-sub'}, _('لا عملاء متصلون')) ];
			wrap.appendChild(E('div', { 'class':'kt-card' }, [
				E('h3', {}, [ ktIc('wifi'), ' '+bandLabel(r.band)+' ('+esc(r.ifname||r.radio)+')' ])
			].concat(rows)));
		});
	}
	btn.addEventListener('click', function(){
		btn.disabled=true; stat.style.color='var(--kt-txt2)'; stat.textContent=_('جارٍ القراءة…');
		call({op:'clients'}).then(function(j){
			btn.disabled=false;
			if (!j || !j.ok){ stat.style.color='var(--kt-bad)'; stat.textContent=_('فشل')+': '+esc((j&&j.error)||'?'); return; }
			stat.style.color='var(--kt-ok)'; stat.textContent=_('إشارة أخضر = ممتازة، برتقالي = متوسطة، أحمر = ضعيفة');
			render(j);
		});
	});
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ ktIc('users'), ' '+_('جودة الوصلة لكل عميل (مباشر)') ]),
		E('div', { 'class':'kt-sub' }, _('معدّلات الإرسال/الاستقبال وقيمة MCS وقوة الإشارة لكل جهاز متصل — يكشف من هو بطيء.')),
		E('div', { style:'margin-top:10px' }, btn), stat, wrap
	]);
}

return view.extend({
	render: function(){
		return E('div', {}, [
			E('h2', {}, _('محسّن الأداء / Performance')),
			E('div', { 'dir':'rtl' }, [
				E('div', { 'class':'kt-grid' }, [ analyzerSection() ]),
				E('div', { 'class':'kt-grid', style:'margin-top:14px' }, [ speedSection() ]),
				E('div', { 'class':'kt-grid', style:'margin-top:14px' }, [ turboSection() ]),
				E('div', { 'class':'kt-grid', style:'margin-top:14px' }, [ clientsSection() ])
			])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
