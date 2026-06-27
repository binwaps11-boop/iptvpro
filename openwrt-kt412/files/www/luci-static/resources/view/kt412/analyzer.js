'use strict';
'require view';

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
function ktIcSvg(n){return '<svg class="kti" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(KTI[n]||KTI.dot)+'</svg>';}
function ktIc(n){var d=document.createElement('div');d.innerHTML=ktIcSvg(n);return d.firstChild;}

/* KT412 Smart AP — WiFi Analyzer (محلل الواي فاي): scans nearby networks, shows
   per-channel congestion for 2.4G and 5G, recommends the least-busy channel, and
   lists neighbouring APs by signal. Backend: /cgi-bin/kt412 op=scan ->
   {ok, nets:[{essid,bssid,ch,sig,enc}]}. Scan is button-triggered (it briefly
   disturbs the AP), not auto-polled. */

var API = '/cgi-bin/kt412';
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
function call(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API + '?' + usp.toString()).then(function(r){ return r.json(); }).catch(function(){ return {ok:false}; });
	});
}

function sigPct(s){ s = +s; var p = 2*(s+100); return p<0?0:(p>100?100:p); }
function sigColor(s){ s = +s; if (s>=-60) return 'var(--kt-ok)'; if (s>=-75) return 'var(--kt-warn)'; return 'var(--kt-bad)'; }

/* tally networks per channel for each band */
function analyze(nets){
	var b24 = {}, b5 = {};
	nets.forEach(function(n){
		var ch = +n.ch; if (!ch) return;
		var t = (ch <= 14) ? b24 : b5;
		if (!t[ch]) t[ch] = { count:0, best:-100 };
		t[ch].count++; if (+n.sig > t[ch].best) t[ch].best = +n.sig;
	});
	return { b24:b24, b5:b5 };
}
/* 2.4G: pick the least-congested of 1/6/11 counting adjacent-channel overlap (±4) */
function recommend24(b24){
	var cands = [1,6,11], best = 1, bestw = 1e9;
	cands.forEach(function(c){
		var w = 0;
		for (var ch in b24){ var d = Math.abs((+ch)-c); if (d <= 4) w += b24[ch].count * (d<=1?2:1); }
		if (w < bestw){ bestw = w; best = c; }
	});
	return best;
}
/* 5G: least-busy of the non-DFS channels */
function recommend5(b5){
	var cands = [36,40,44,48,149,153,157,161], best = 36, bestw = 1e9;
	cands.forEach(function(c){ var w = b5[c] ? b5[c].count : 0; if (w < bestw){ bestw = w; best = c; } });
	return best;
}
function chartFor(title, band, chans, rec){
	var maxc = 1; chans.forEach(function(c){ if (band[c] && band[c].count > maxc) maxc = band[c].count; });
	var bars = chans.map(function(c){
		var cnt = band[c] ? band[c].count : 0;
		var h = Math.round(cnt / maxc * 64);
		var isRec = (c === rec);
		return '<div style="display:flex;flex-direction:column;align-items:center;gap:3px;flex:1;min-width:0">'
			+ '<div style="font-size:10px;color:var(--kt-muted)">'+cnt+'</div>'
			+ '<div style="width:78%;height:'+(h||2)+'px;border-radius:4px 4px 0 0;background:'+(isRec?'var(--kt-ok)':'var(--kt-accent)')+'"></div>'
			+ '<div style="font-size:10px;font-weight:'+(isRec?'800':'400')+';color:'+(isRec?'var(--kt-ok)':'var(--kt-txt2)')+'">'+c+'</div>'
			+ '</div>';
	}).join('');
	return '<div class="kt-card"><h3>'+title+'</h3>'
		+ '<div class="kt-note">'+ktIcSvg('star')+' '+_('أفضل قناة مقترحة')+': <b>'+rec+'</b> — '+_('الأقل ازدحاماً')+'</div>'
		+ '<div style="display:flex;align-items:flex-end;gap:2px;height:96px;margin-top:8px;overflow-x:auto">'+bars+'</div></div>';
}
function netRow(n){
	return '<div class="kt-dev">'
		+ '<div class="dic">'+ktIcSvg('wifi')+'</div>'
		+ '<div class="dmain"><div class="dname">'+esc(n.essid||_('(مخفي)'))+' <span class="kt-badge">CH '+esc(n.ch)+'</span></div>'
		+ '<div class="dmeta" dir="ltr" style="direction:ltr">'+esc(n.bssid)+' · '+esc(n.sig)+' dBm · '+esc(n.enc||'')+'</div></div>'
		+ '<div class="kt-sigbar"><i style="width:'+sigPct(n.sig)+'%;background:'+sigColor(n.sig)+'"></i></div>'
		+ '</div>';
}
function render(box, nets){
	if (!nets.length){ box.innerHTML = '<div class="kt-empty">'+ktIcSvg('wifi')+'<div class="kt-empty-t">'+_('لا شبكات مكتشفة — أعد المسح')+'</div></div>'; return; }
	var a = analyze(nets);
	var rec24 = recommend24(a.b24), rec5 = recommend5(a.b5);
	var sorted = nets.slice().sort(function(x,y){ return (+y.sig)-(+x.sig); });
	box.innerHTML =
		chartFor(ktIcSvg('wifi')+' '+_('ازدحام 2.4G (القنوات 1–13)'), a.b24, [1,2,3,4,5,6,7,8,9,10,11,12,13], rec24)
		+ chartFor(ktIcSvg('radio')+' '+_('ازدحام 5G'), a.b5, [36,40,44,48,149,153,157,161], rec5)
		+ '<div class="kt-card"><h3>'+ktIcSvg('globe')+' '+_('الشبكات المجاورة')+' ('+nets.length+')</h3>'+sorted.map(netRow).join('')+'</div>';
}

return view.extend({
	render: function(){
		var body = E('div', { 'class':'kt-body', style:'margin-top:12px' }, E('div', { 'class':'kt-sub' }, _('اضغط «مسح الشبكات» للبدء.')));
		var btn  = E('button', { 'class':'kt-btn' }, [ktIc('search'), ' '+_('مسح الشبكات')]);
		btn.addEventListener('click', function(){
			btn.disabled = true; var t = btn.innerHTML; btn.innerHTML = ktIcSvg('timer')+' '+_('جارٍ المسح…');
			body.innerHTML = '<div class="kt-sub">'+_('جارٍ المسح… قد ينقطع الواي فاي للحظة')+'</div>';
			call({op:'scan'}).then(function(j){
				btn.disabled = false; btn.innerHTML = t;
				if (!(j && j.ok)){ body.innerHTML = '<div class="kt-sub" style="color:var(--kt-bad)">'+_('فشل المسح')+'</div>'; return; }
				render(body, j.nets || []);
			});
		});
		return E('div', {}, [
			E('h2', {}, _('محلل الواي فاي — WiFi Analyzer')),
			E('div', { 'class':'kt-sub' }, _('يمسح الشبكات المجاورة، يعرض ازدحام القنوات، ويقترح أفضل قناة.')),
			E('div', { style:'margin:10px 0' }, btn),
			body
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
