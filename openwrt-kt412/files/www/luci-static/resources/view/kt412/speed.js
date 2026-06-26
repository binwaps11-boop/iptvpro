'use strict';
'require view';
'require poll';

/* KT412 Smart AP — Speed test & graphs (اختبار السرعة والرسوم).
   Card A: data-download speed test (act=speedtest -> poll op=spd until done).
   Card B: last-hour history (op=history) drawn as three SVG sparklines
   (CPU%, RAM%, Traffic), reusing the nettools.js sparkline approach. */

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
function postCall(params){
	return adopt().then(function(){
		var usp = new URLSearchParams(params);
		if (TOKEN) usp.set('token', TOKEN);
		return fetch(API, {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:usp.toString()})
			.then(function(r){ return r.json(); }).catch(function(){ return {ok:false}; });
	});
}

/* Inline SVG sparkline (adapted from nettools.js latencyGraph). */
function sparkline(vals, color, fixedMax){
	var W=320, H=90, PADL=6, PADR=6, PADT=8, PADB=8;
	var svg='<svg viewBox="0 0 '+W+' '+H+'" width="100%" preserveAspectRatio="none" style="max-width:100%;height:auto">';
	var n=vals.length;
	if (!n){ return svg+'<text x="'+(W/2)+'" y="'+(H/2)+'" fill="#8a90a6" text-anchor="middle" font-size="12">'+_('لا بيانات')+'</text></svg>'; }
	var max=(fixedMax!=null?fixedMax:0), min=0;
	if (fixedMax==null){ vals.forEach(function(v){ v=+v; if(v>max)max=v; }); }
	if (max<=0) max=1;
	var span=(max-min)||1;
	var plotW=W-PADL-PADR, plotH=H-PADT-PADB;
	function X(i){ return PADL + (n>1 ? (i/(n-1))*plotW : plotW/2); }
	function Y(v){ return PADT + plotH - ((+v - min)/span)*plotH; }
	var d='';
	vals.forEach(function(v,i){ var x=X(i).toFixed(1), y=Y(v).toFixed(1); d+=(i?'L':'M')+x+' '+y+' '; });
	var area = 'M'+X(0).toFixed(1)+' '+(PADT+plotH)+' '+ d.replace(/^M/,'L') + 'L'+X(n-1).toFixed(1)+' '+(PADT+plotH)+' Z';
	svg+='<path d="'+area+'" fill="'+color+'" fill-opacity="0.16"/>';
	svg+='<path d="'+d+'" fill="none" stroke="'+color+'" stroke-width="2"/>';
	svg+='</svg>';
	return svg;
}

function speedCard(){
	var size = E('select', { 'class':'cbi-input-select' });
	[10,50,100].forEach(function(v){ var o=E('option',{value:String(v)}, v+' MB'); if(v===10)o.selected=true; size.appendChild(o); });
	var btn  = E('button', { 'class':'kt-btn' }, _('ابدأ الاختبار'));
	var stat = E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var res  = E('div', {}, '');
	var timer = null;

	function showResult(mbps){
		if (String(mbps) === '-1'){
			res.innerHTML = '<div class="kt-tile" style="background:linear-gradient(135deg,#dc2626,#EF4444)"><div class="ti">⚠️</div><div class="tn" style="font-size:18px">'+_('فشل الاختبار — تحقق من الإنترنت')+'</div></div>';
		} else {
			res.innerHTML = '<div class="kt-tile kt-t-cyan"><div class="ti">🚀</div><div class="tn">'+esc(mbps)+'</div><div class="tl">Mbit/s</div></div>';
		}
	}

	btn.addEventListener('click', function(){
		if (timer){ clearInterval(timer); timer=null; }
		btn.disabled = true; stat.style.color='var(--kt-txt2)'; stat.textContent=_('جارٍ الاختبار…'); res.innerHTML='';
		postCall({act:'speedtest', size: size.value}).then(function(j){
			if (!(j && j.ok)){ btn.disabled=false; stat.style.color='var(--kt-bad)'; stat.textContent=_('تعذّر بدء الاختبار'); return; }
			timer = setInterval(function(){
				call({op:'spd'}).then(function(s){
					if (s && s.ok && s.done){
						clearInterval(timer); timer=null;
						btn.disabled=false; stat.textContent='';
						showResult(s.mbps);
					}
				});
			}, 2000);
		});
	});

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '🚀 '+_('اختبار السرعة')),
		E('div', { 'class':'kt-field' }, [ E('label',{},_('حجم الاختبار')), size ]),
		E('div', { 'class':'kt-note' }, _('تحذير: يقوم الاختبار بتنزيل هذا الحجم من البيانات (مهم على الباقة).')),
		E('div', { style:'margin-top:8px' }, btn),
		stat, res
	]);
}

function graphCard(body){
	function reload(){
		return call({op:'history'}).then(function(j){
			var samples = (j && j.ok && j.samples) ? j.samples : [];
			if (!samples.length){ body.innerHTML = '<div class="kt-sub">'+_('يُجمَّع السجل… انتظر دقيقة')+'</div>'; return; }
			var cpu = samples.map(function(s){ return +s.cpu || 0; });
			var mem = samples.map(function(s){ return +s.mem || 0; });
			var traf = samples.map(function(s){ return (+s.rx||0) + (+s.tx||0); });
			var last = samples[samples.length-1];
			var lastTraf = (+last.rx||0) + (+last.tx||0);
			function fmtBps(b){ b=+b||0; if(b<1000)return b.toFixed(0)+' bps'; if(b<1000000)return (b/1000).toFixed(1)+' Kbps'; return (b/1000000).toFixed(2)+' Mbps'; }
			body.innerHTML =
				'<div class="kt-grid kt-cols-3">'
				+ '<div class="kt-card"><div class="kt-glabel">CPU · '+esc((+last.cpu||0).toFixed(0))+'%</div>'+sparkline(cpu, '#06B6D4', 100)+'</div>'
				+ '<div class="kt-card"><div class="kt-glabel">RAM · '+esc((+last.mem||0).toFixed(0))+'%</div>'+sparkline(mem, '#8b5cf6', 100)+'</div>'
				+ '<div class="kt-card"><div class="kt-glabel">'+_('الحركة')+' · '+esc(fmtBps(lastTraf))+'</div>'+sparkline(traf, '#22C55E', null)+'</div>'
				+ '</div>';
		});
	}
	reload();
	poll.add(function(){ return reload(); }, 15);
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '📈 '+_('السجل (آخر ساعة)')),
		body
	]);
}

return view.extend({
	render: function(){
		var gbody = E('div', {}, E('div', { 'class':'kt-sub' }, _('جارٍ التحميل…')));
		return E('div', {}, [
			E('h2', {}, _('اختبار السرعة والرسوم')),
			E('div', { 'dir':'rtl' }, [
				E('div', { 'class':'kt-grid' }, [ speedCard() ]),
				E('div', { 'class':'kt-grid', style:'margin-top:14px' }, [ graphCard(gbody) ])
			])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
