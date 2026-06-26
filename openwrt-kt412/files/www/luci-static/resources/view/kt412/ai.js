'use strict';
'require view';
'require ui';
'require uci';

/* KT412 MK APP — Smart AI Diagnostic Assistant (المساعد الذكي).
   Client-side LuCI view. Talks to our own POSIX-sh CGI /cgi-bin/kt412-diag.
   - op=diag  : server-side checklist -> red/green findings + One-Click Fix
   - op=fix   : whitelisted safe fix
   - op=llm   : sends the collected diag JSON + prompt to a real LLM (key from
                uci kt412.ai) and renders the natural-language analysis.
   RTL Arabic, mobile-first, reuses the kt-* theme. */

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

function badgeClass(sev){ return sev==='ok' ? 'ok' : (sev==='bad' ? 'bad' : 'warn'); }
function sevIcon(sev){ return sev==='ok' ? '✅' : (sev==='bad' ? '⛔' : '⚠️'); }

return view.extend({
	load: function(){
		return Promise.all([
			call({op:'diag'}),
			uci.load('kt412').catch(function(){ return null; })
		]).catch(function(){ return [{}, null]; });
	},
	render: function(res){
		var diag = res[0] || {};
		var self = this;
		var lastDiag = diag;   /* keep latest diag json for the LLM call */

		/* ---------- settings area (uci kt412.ai) ---------- */
		var provider = E('select', { class:'cbi-input-select' }, [
			E('option', { value:'anthropic' }, 'Anthropic (Claude)'),
			E('option', { value:'openai' }, 'OpenAI-compatible')
		]);
		var endpoint = E('input', { type:'text', class:'cbi-input-text', placeholder:'https://api.anthropic.com/v1/messages' });
		var model    = E('input', { type:'text', class:'cbi-input-text', placeholder:'claude-opus-4-8' });
		var apikey   = E('input', { type:'password', class:'cbi-input-text', placeholder:_('أدخل مفتاح API الخاص بك') });

		var saveBtn = E('button', { class:'kt-btn sec' }, _('💾 حفظ الإعدادات'));

		/* settings are stored in uci kt412.ai (loaded in load()). */
		provider.value = uci.get('kt412','ai','provider') || 'anthropic';
		endpoint.value = uci.get('kt412','ai','endpoint') || '';
		model.value    = uci.get('kt412','ai','model') || '';
		/* never prefill the secret; just indicate one is saved */
		if (uci.get('kt412','ai','apikey')) apikey.placeholder = '•••••••• (' + _('محفوظ') + ')';

		saveBtn.onclick = function(){
			saveBtn.textContent = '…';
			uci.set('kt412','ai','provider', provider.value || 'anthropic');
			uci.set('kt412','ai','endpoint', endpoint.value || '');
			uci.set('kt412','ai','model', model.value || 'claude-opus-4-8');
			if (apikey.value) uci.set('kt412','ai','apikey', apikey.value);
			uci.save().then(function(){ return uci.apply(); }).then(function(){
				saveBtn.textContent = _('💾 حفظ الإعدادات');
				apikey.value = '';
				ui.addNotification(null, E('p', {}, _('تم حفظ إعدادات الذكاء الاصطناعي.')), 'info');
			}).catch(function(){
				saveBtn.textContent = _('💾 حفظ الإعدادات');
				ui.addNotification(null, E('p', {}, _('تعذّر الحفظ.')), 'error');
			});
		};

		/* ---------- findings list ---------- */
		var list = E('div', { class:'kt-grid' });

		function renderFindings(d){
			list.innerHTML = '';
			lastDiag = d;
			var fs = (d && d.findings) ? d.findings : [];
			if (!fs.length){
				list.appendChild(E('div', { class:'kt-card' }, E('p', {}, _('لا توجد نتائج فحص.'))));
				return;
			}
			fs.forEach(function(f){
				var row = E('div', { class:'kt-card' }, [
					E('div', { style:'display:flex;align-items:center;gap:10px;justify-content:space-between' }, [
						E('div', { style:'display:flex;align-items:center;gap:8px' }, [
							E('span', {}, sevIcon(f.severity)),
							E('span', { style:'font-weight:700' }, f.summary)
						]),
						E('span', { class:'kt-badge ' + badgeClass(f.severity) },
							f.severity==='ok' ? _('سليم') : (f.severity==='bad' ? _('مشكلة') : _('تحذير')))
					])
				]);
				if (f.fix_id){
					var fixBtn = E('button', { class:'kt-btn', style:'margin-top:10px' }, _('🛠️ إصلاح بنقرة'));
					fixBtn.onclick = function(){
						fixBtn.textContent = '…';
						call({ op:'fix', id:f.fix_id }, true).then(function(r){
							if (r && r.ok){
								ui.addNotification(null, E('p', {}, r.msg || _('تم الإصلاح.')), 'info');
								refresh();
							} else {
								fixBtn.textContent = _('🛠️ إصلاح بنقرة');
								ui.addNotification(null, E('p', {}, _('فشل الإصلاح: %s').format((r&&r.error)||'')), 'error');
							}
						});
					};
					row.appendChild(fixBtn);
				}
				list.appendChild(row);
			});
		}

		function refresh(){
			list.innerHTML = '';
			list.appendChild(E('div', { class:'kt-card' }, E('p', {}, _('… جارٍ الفحص'))));
			call({ op:'diag' }).then(renderFindings);
		}

		renderFindings(diag);

		/* ---------- AI analysis ---------- */
		var aiBox = E('div', { class:'kt-card', style:'white-space:pre-wrap;line-height:1.7' },
			E('p', { class:'kt-sub' }, _('اضغط "اسأل الذكاء الاصطناعي" لتحليل النتائج. يتطلب اتصال إنترنت ومفتاح API صالح.')));

		var askBtn = E('button', { class:'kt-btn' }, _('🤖 اسأل الذكاء الاصطناعي'));
		askBtn.onclick = function(){
			askBtn.textContent = '…';
			aiBox.innerHTML = '';
			aiBox.appendChild(E('p', { class:'kt-sub' }, _('… جارٍ التحليل (قد يستغرق لحظات)')));
			call({ op:'llm', diag: JSON.stringify(lastDiag || {}) }, true).then(function(r){
				askBtn.textContent = _('🤖 اسأل الذكاء الاصطناعي');
				aiBox.innerHTML = '';
				if (r && r.ok){
					aiBox.appendChild(E('div', {}, r.analysis));
				} else if (r && r.error === 'no_apikey'){
					aiBox.appendChild(E('p', { style:'color:var(--kt-bad,#ff6b8a)' },
						_('لم يتم ضبط مفتاح API. أدخل مفتاحك في قسم الإعدادات بالأسفل ثم احفظ.')));
				} else if (r && r.error === 'network'){
					aiBox.appendChild(E('p', { style:'color:var(--kt-bad,#ff6b8a)' },
						_('تعذّر الاتصال بالإنترنت أو انتهت المهلة. تأكد من اتصال WAN ثم أعد المحاولة.')));
				} else if (r && r.error === 'no_curl'){
					aiBox.appendChild(E('p', { style:'color:var(--kt-bad,#ff6b8a)' },
						_('أداة curl غير مثبّتة على الجهاز.')));
				} else {
					aiBox.appendChild(E('p', { style:'color:var(--kt-bad,#ff6b8a)' },
						_('تعذّر التحليل: %s').format((r&&r.error)||'')));
				}
			});
		};

		var refreshBtn = E('button', { class:'kt-btn sec' }, _('🔄 إعادة الفحص'));
		refreshBtn.onclick = refresh;

		return E('div', {}, [
			E('h2', {}, _('المساعد الذكي — التشخيص')),
			E('div', { style:'display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px' }, [ refreshBtn, askBtn ]),
			E('h3', { style:'margin:12px 0 8px' }, _('نتائج الفحص الذاتي')),
			list,
			E('h3', { style:'margin:18px 0 8px' }, _('تحليل الذكاء الاصطناعي')),
			aiBox,
			E('h3', { style:'margin:18px 0 8px' }, _('إعدادات الذكاء الاصطناعي')),
			E('div', { class:'kt-card' }, [
				E('p', { class:'kt-sub', style:'margin-bottom:8px' },
					_('يحتاج المساعد إلى اتصال إنترنت ومفتاح API صالح. لا يُخزَّن المفتاح إلا على جهازك.')),
				E('div', { class:'kt-grid kt-cols-2' }, [
					E('div', { class:'kt-field' }, [ E('label', {}, _('المزوّد')), provider ]),
					E('div', { class:'kt-field' }, [ E('label', {}, _('النموذج (Model)')), model ])
				]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('نقطة النهاية (Endpoint) — اختياري')), endpoint ]),
				E('div', { class:'kt-field' }, [ E('label', {}, _('مفتاح API')), apikey ]),
				saveBtn
			])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
