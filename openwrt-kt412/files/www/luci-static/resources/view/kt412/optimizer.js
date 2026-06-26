'use strict';
'require view';
'require ui';

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
	var head = E('h3', {}, '📡 '+bandLabel(r.band)+' ('+esc(r.radio)+')');
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
	var btn = E('button', { 'class':'kt-btn' }, '🔍 '+_('فحص القنوات الآن'));
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
		E('h3', {}, '📶 '+_('محلّل القنوات والاختيار التلقائي')),
		E('div', { 'class':'kt-sub' }, _('يحسب عدد الشبكات على كل قناة ويوصي بأقلّها ازدحاماً (2.4G: 1/6/11 فقط · 5G: قنوات غير DFS). تطبيق القناة الأنظف = سرعة أعلى فعلياً مع الحفاظ على HT20/VHT80.')),
		E('div', { style:'margin-top:10px' }, btn), stat, grid
	]);
}

/* ---------------- Internet Speed Test ---------------- */
function speedSection(){
	var url = E('input', { type:'text', class:'cbi-input-text', style:'flex:1;min-width:240px',
		value:'https://speed.cloudflare.com/__down?bytes=50000000',
		placeholder:'https://… test file URL' });
	var btn = E('button', { 'class':'kt-btn' }, '🚀 '+_('اختبار السرعة'));
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
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">↓ '+_('التنزيل')+'</div><div class="kt-sub" style="font-size:26px;color:var(--kt-ok)">'+esc(j.down_mbps)+' Mbit/s</div></div>'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">⏱ '+_('الكمون (ping 1.1.1.1)')+'</div><div class="kt-sub" style="font-size:26px;color:var(--kt-accent)">'+esc(j.ping_ms||'—')+' ms</div></div>'
				+ '</div>';
		});
	});
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '🌐 '+_('اختبار سرعة الإنترنت')),
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
	var btn = E('button', { 'class':'kt-btn' }, '⚡ '+_('تحسين فوري / Turbo'));
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
		E('h3', {}, '⚡ '+_('تحسين فوري بنقرة واحدة')),
		E('div', { 'class':'kt-sub' }, _('إجراءات آمنة فقط: إعادة تثبيت طاقة الإرسال المُعدّة + إعادة تحميل الواي‑فاي + تفريغ الذاكرة المؤقتة + تنظيف اتصالات UDP القديمة. لا يغيّر أي إعداد طاقة أو تردد.')),
		E('div', { style:'margin-top:10px' }, btn), stat, list
	]);
}

/* ---------------- Live per-client rates ---------------- */
function sigColor(s){ s=parseInt(s,10); if(isNaN(s))return 'var(--kt-txt2)'; if(s>=-67)return 'var(--kt-ok)'; if(s>=-78)return 'var(--kt-warn)'; return 'var(--kt-bad)'; }

function clientsSection(){
	var btn = E('button', { 'class':'kt-btn' }, '👥 '+_('عرض العملاء وجودة الوصلة'));
	var stat= E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var wrap= E('div', {}, '');
	function render(j){
		wrap.innerHTML='';
		(j.radios||[]).forEach(function(r){
			var rows = (r.clients||[]).map(function(c){
				return E('div', { 'class':'kt-kv' }, [
					E('span',{'class':'k'}, esc(c.mac)),
					E('span',{'class':'v', dir:'ltr', style:'color:'+sigColor(c.signal)+';text-align:left;direction:ltr'},
						(c.signal?esc(c.signal)+' dBm':'—')
						+ ' · ↓'+esc(c.rx_mbit||'—')+' ↑'+esc(c.tx_mbit||'—')+' Mbit/s'
						+ ((c.rx_mcs||c.tx_mcs)?(' · MCS '+esc(c.rx_mcs||'?')+'/'+esc(c.tx_mcs||'?')):''))
				]);
			});
			if (!rows.length) rows=[ E('div',{'class':'kt-sub'}, _('لا عملاء متصلون')) ];
			wrap.appendChild(E('div', { 'class':'kt-card' }, [
				E('h3', {}, '📶 '+bandLabel(r.band)+' ('+esc(r.ifname||r.radio)+')')
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
		E('h3', {}, '👥 '+_('جودة الوصلة لكل عميل (مباشر)')),
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
