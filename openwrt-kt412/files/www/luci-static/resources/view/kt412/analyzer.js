'use strict';
'require view';

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
		+ '<div class="kt-note">⭐ '+_('أفضل قناة مقترحة')+': <b>'+rec+'</b> — '+_('الأقل ازدحاماً')+'</div>'
		+ '<div style="display:flex;align-items:flex-end;gap:2px;height:96px;margin-top:8px;overflow-x:auto">'+bars+'</div></div>';
}
function netRow(n){
	return '<div class="kt-dev">'
		+ '<div class="dic">📶</div>'
		+ '<div class="dmain"><div class="dname">'+esc(n.essid||_('(مخفي)'))+' <span class="kt-badge">CH '+esc(n.ch)+'</span></div>'
		+ '<div class="dmeta" dir="ltr" style="direction:ltr">'+esc(n.bssid)+' · '+esc(n.sig)+' dBm · '+esc(n.enc||'')+'</div></div>'
		+ '<div class="kt-sigbar"><i style="width:'+sigPct(n.sig)+'%;background:'+sigColor(n.sig)+'"></i></div>'
		+ '</div>';
}
function render(box, nets){
	if (!nets.length){ box.innerHTML = '<div class="kt-sub">'+_('لا شبكات مكتشفة — أعد المسح')+'</div>'; return; }
	var a = analyze(nets);
	var rec24 = recommend24(a.b24), rec5 = recommend5(a.b5);
	var sorted = nets.slice().sort(function(x,y){ return (+y.sig)-(+x.sig); });
	box.innerHTML =
		chartFor(_('📶 ازدحام 2.4G (القنوات 1–13)'), a.b24, [1,2,3,4,5,6,7,8,9,10,11,12,13], rec24)
		+ chartFor(_('📡 ازدحام 5G'), a.b5, [36,40,44,48,149,153,157,161], rec5)
		+ '<div class="kt-card"><h3>🌐 '+_('الشبكات المجاورة')+' ('+nets.length+')</h3>'+sorted.map(netRow).join('')+'</div>';
}

return view.extend({
	render: function(){
		var body = E('div', { 'class':'kt-body', style:'margin-top:12px' }, E('div', { 'class':'kt-sub' }, _('اضغط «مسح الشبكات» للبدء.')));
		var btn  = E('button', { 'class':'kt-btn' }, '🔍 '+_('مسح الشبكات'));
		btn.addEventListener('click', function(){
			btn.disabled = true; var t = btn.textContent; btn.textContent = '⏳ '+_('جارٍ المسح…');
			body.innerHTML = '<div class="kt-sub">'+_('جارٍ المسح… قد ينقطع الواي فاي للحظة')+'</div>';
			call({op:'scan'}).then(function(j){
				btn.disabled = false; btn.textContent = t;
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
