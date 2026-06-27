'use strict';
'require view';

/* KT412 Smart AP — IPTV playlist manager.
   Accepts an M3U/M3U8 URL (fetched server-side by curl) OR an uploaded .m3u/.m3u8
   file (read in the browser, sent base64). Saved to /www/iptv/playlist.m3u and
   served by uhttpd at http://<device>/iptv/playlist.m3u for any player. Backend:
   act=iptv_save / act=iptv_clear / op=iptv_status on /cgi-bin/kt412. */

var KTI = {
	tv:'<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M8 21h8 M9 6 5 2 M15 6l4-4"/>',
	link:'<path d="M9 15 15 9 M10 6l1-1a4 4 0 0 1 6 6l-1 1 M14 18l-1 1a4 4 0 0 1-6-6l1-1"/>',
	up:'<path d="M12 19V5 M6 11l6-6 6 6"/>',
	check:'<path d="M20 6 9 17l-5-5"/>',
	ban:'<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>',
	copy:'<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>',
	dot:'<circle cx="12" cy="12" r="5"/>'
};
function ktIcSvg(n){return '<svg class="kti" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(KTI[n]||KTI.dot)+'</svg>';}
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
function b64utf8(s){ return btoa(unescape(encodeURIComponent(s))); }

function iptvCard(){
	var url  = E('input', { type:'text', class:'cbi-input-text', placeholder:'https://…/playlist.m3u8', dir:'ltr' });
	var file = E('input', { type:'file', accept:'.m3u,.m3u8,.txt,text/plain', class:'cbi-input-text' });
	var btnU = E('button', { 'class':'kt-btn' }, [ ktIc('link'), ' ' + _('جلب وحفظ الرابط') ]);
	var btnF = E('button', { 'class':'kt-btn sec' }, [ ktIc('up'), ' ' + _('رفع الملف') ]);
	var btnC = E('button', { 'class':'kt-btn sec' }, [ ktIc('ban'), ' ' + _('حذف') ]);
	var stat = E('div', { 'class':'kt-note muted', style:'margin-top:10px' }, _('جارٍ القراءة…'));
	var out  = E('div', { style:'margin-top:10px' });

	function showStatus(j){
		out.innerHTML = '';
		if (j && j.exists !== false && j.url && (j.exists || j.channels)){
			out.innerHTML = '<div class="kt-card kt-gcard"><div class="kt-glabel">'+ktIcSvg('tv')+' '+_('قائمة التشغيل جاهزة')+'</div>'
				+ '<div class="kt-sub">'+_('عدد القنوات')+': <b>'+esc(j.channels||0)+'</b></div>'
				+ '<div class="kt-sub" style="margin-top:6px">'+_('الرابط لمشغّلك')+':</div>'
				+ '<div class="kt-kv" style="margin-top:4px"><span class="v" dir="ltr" style="direction:ltr;word-break:break-all"><b>'+esc(j.url)+'</b></span></div></div>';
		}
	}
	function refresh(){
		call({ op:'iptv_status' }).then(function(j){
			if (!j || !j.ok){ stat.textContent = _('تعذّر القراءة'); return; }
			if (j.exists){ stat.textContent=''; stat.appendChild(ktIc('check')); stat.appendChild(document.createTextNode(' '+_('توجد قائمة تشغيل محفوظة')+' ('+(j.channels||0)+' '+_('قناة')+')')); }
			else { stat.textContent = _('لا توجد قائمة تشغيل بعد — أضف رابطاً أو ارفع ملفاً.'); }
			showStatus(j);
		}).catch(function(){ stat.textContent = _('تعذّر القراءة'); });
	}

	btnU.addEventListener('click', function(){
		var u = (url.value||'').trim();
		if (!/^https?:\/\//i.test(u)){ stat.style.color='var(--kt-bad)'; stat.textContent=_('أدخل رابط m3u/m3u8 صحيح يبدأ بـ http'); return; }
		btnU.disabled=true; stat.style.color=''; stat.textContent=_('جارٍ الجلب…');
		postCall({ act:'iptv_save', url:u }).then(function(j){
			btnU.disabled=false;
			if (j && j.ok){ stat.style.color='var(--kt-ok)'; stat.textContent=_('تم الحفظ')+' ('+(j.channels||0)+' '+_('قناة')+')'; showStatus(j); }
			else { stat.style.color='var(--kt-bad)'; stat.textContent=_('فشل الجلب — تحقّق من الرابط/الاتصال'); }
		});
	});
	btnF.addEventListener('click', function(){
		var f = file.files && file.files[0];
		if (!f){ stat.style.color='var(--kt-bad)'; stat.textContent=_('اختر ملف m3u/m3u8 أولاً'); return; }
		if (f.size > 4*1024*1024){ stat.style.color='var(--kt-bad)'; stat.textContent=_('الملف كبير جداً (الحد 4MB) — استخدم رابطاً بدلاً منه'); return; }
		btnF.disabled=true; stat.style.color=''; stat.textContent=_('جارٍ الرفع…');
		var fr = new FileReader();
		fr.onload = function(){
			postCall({ act:'iptv_save', body: b64utf8(String(fr.result||'')) }).then(function(j){
				btnF.disabled=false;
				if (j && j.ok){ stat.style.color='var(--kt-ok)'; stat.textContent=_('تم الرفع والحفظ')+' ('+(j.channels||0)+' '+_('قناة')+')'; showStatus(j); }
				else { stat.style.color='var(--kt-bad)'; stat.textContent=_('فشل الرفع'); }
			});
		};
		fr.onerror = function(){ btnF.disabled=false; stat.style.color='var(--kt-bad)'; stat.textContent=_('تعذّر قراءة الملف'); };
		fr.readAsText(f);
	});
	btnC.addEventListener('click', function(){
		btnC.disabled=true;
		postCall({ act:'iptv_clear' }).then(function(j){ btnC.disabled=false; out.innerHTML=''; refresh(); });
	});

	refresh();
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ ktIc('tv'), ' ' + _('قائمة تشغيل IPTV') ]),
		E('div', { 'class':'kt-sub' }, _('أضف قائمة قنواتك عبر رابط m3u/m3u8 أو برفع ملف. تُحفظ على الجهاز وتُقدَّم لأي مشغّل (TiviMate/VLC) عبر رابط محلي.')),
		E('div', { 'class':'kt-field', style:'margin-top:10px' }, [ E('label', {}, [ ktIc('link'), ' ' + _('رابط m3u / m3u8') ]), url ]),
		E('div', { style:'margin-top:6px' }, btnU),
		E('div', { 'class':'kt-field', style:'margin-top:14px' }, [ E('label', {}, [ ktIc('up'), ' ' + _('أو رفع ملف m3u/m3u8') ]), file ]),
		E('div', { style:'margin-top:6px;display:flex;gap:8px;flex-wrap:wrap' }, [ btnF, btnC ]),
		stat, out
	]);
}

return view.extend({
	render: function(){
		return E('div', { 'dir':'rtl' }, [
			E('h2', {}, _('IPTV')),
			E('div', { 'class':'kt-grid' }, [ iptvCard() ])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
