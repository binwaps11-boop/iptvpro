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

/* KT412 "MK APP" — Network Tools (أدوات الشبكة).
   Advanced Ping: host + count -> server-side ping, RTT min/avg/max + live SVG
   latency graph of per-packet RTT.
   Speed Test (iperf3): client UI -> `iperf3 -c <server> [-R]`, TX/RX Mbps.
   Handles iperf3 missing and the no-server case. Backend: kt412-tools. */

var API = '/cgi-bin/kt412-tools';
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

/* Client-side sanitize mirror of the backend (defense in depth). */
function saniHost(s){ return String(s||'').replace(/[^A-Za-z0-9.:_-]/g,'').replace(/^-+/,'').slice(0,64); }

/* Inline SVG latency graph of per-packet RTT (ms). */
function latencyGraph(rtts){
	var W=520, H=160, PADL=34, PADB=20, PADT=12, PADR=10;
	var svg='<svg viewBox="0 0 '+W+' '+H+'" width="100%" preserveAspectRatio="none" style="max-width:100%;height:auto">';
	var n=rtts.length;
	if (!n){ return svg+'<text x="'+(W/2)+'" y="'+(H/2)+'" fill="#8a90a6" text-anchor="middle" font-size="13">'+_('لا بيانات')+'</text></svg>'; }
	var max=0, min=1e9;
	rtts.forEach(function(v){ v=+v; if(v>max)max=v; if(v<min)min=v; });
	if (max<=0) max=1;
	var span=(max-min)||1;
	var plotW=W-PADL-PADR, plotH=H-PADT-PADB;
	function X(i){ return PADL + (n>1 ? (i/(n-1))*plotW : plotW/2); }
	function Y(v){ return PADT + plotH - ((+v - min)/span)*plotH; }
	/* gridlines + axis labels (max/min) */
	svg+='<line x1="'+PADL+'" y1="'+PADT+'" x2="'+PADL+'" y2="'+(PADT+plotH)+'" stroke="#3a3f55" stroke-width="1"/>';
	svg+='<line x1="'+PADL+'" y1="'+(PADT+plotH)+'" x2="'+(W-PADR)+'" y2="'+(PADT+plotH)+'" stroke="#3a3f55" stroke-width="1"/>';
	svg+='<text x="4" y="'+(PADT+8)+'" fill="#8a90a6" font-size="10">'+max.toFixed(1)+'</text>';
	svg+='<text x="4" y="'+(PADT+plotH)+'" fill="#8a90a6" font-size="10">'+min.toFixed(1)+'</text>';
	/* area + line path */
	var d='', area='';
	rtts.forEach(function(v,i){ var x=X(i).toFixed(1), y=Y(v).toFixed(1); d+=(i?'L':'M')+x+' '+y+' '; });
	area = 'M'+X(0).toFixed(1)+' '+(PADT+plotH)+' '+ d.replace(/^M/,'L') + 'L'+X(n-1).toFixed(1)+' '+(PADT+plotH)+' Z';
	svg+='<path d="'+area+'" fill="rgba(124,77,255,.18)"/>';
	svg+='<path d="'+d+'" fill="none" stroke="#7c4dff" stroke-width="2"/>';
	/* points */
	rtts.forEach(function(v,i){ svg+='<circle cx="'+X(i).toFixed(1)+'" cy="'+Y(v).toFixed(1)+'" r="2.5" fill="#54e3ad"/>'; });
	svg+='</svg>';
	return svg;
}

function pingCard(){
	var host  = E('input', { type:'text', class:'cbi-input-text', placeholder:'1.1.1.1 / example.com', value:'1.1.1.1' });
	var count = E('input', { type:'number', class:'cbi-input-text', min:'1', max:'30', value:'8', style:'width:80px' });
	var btn   = E('button', { 'class':'kt-btn' }, _('ابدأ Ping'));
	var stat  = E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var summ  = E('div', {}, '');
	var graph = E('div', { style:'margin-top:10px' }, '');

	btn.addEventListener('click', function(){
		var h = saniHost(host.value);
		if (!h){ stat.style.color='var(--kt-bad)'; stat.textContent=_('مضيف غير صالح'); return; }
		host.value = h;
		var c = parseInt(count.value,10); if(isNaN(c)||c<1)c=1; if(c>30)c=30; count.value=String(c);
		btn.disabled=true; stat.style.color='var(--kt-txt2)'; stat.textContent=_('جارٍ القياس…'); summ.innerHTML=''; graph.innerHTML='';
		call({op:'ping', host:h, count:String(c)}).then(function(j){
			btn.disabled=false;
			if (!j || !j.ok){ stat.style.color='var(--kt-bad)'; stat.textContent=_('فشل')+': '+esc((j&&j.error)||'?'); return; }
			var lossBad = (+j.loss)>=100;
			stat.style.color = lossBad ? 'var(--kt-bad)' : 'var(--kt-ok)';
			stat.textContent = j.rx+'/'+j.tx+' '+_('حِزم وصلت')+' · '+_('فقد')+' '+j.loss+'%';
			summ.innerHTML =
				'<div class="kt-grid kt-cols-3">'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">'+_('الأدنى')+'</div><div class="kt-sub" style="font-size:20px;color:var(--kt-ok)">'+esc(j.min||'—')+' ms</div></div>'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">'+_('المتوسط')+'</div><div class="kt-sub" style="font-size:20px;color:var(--kt-accent)">'+esc(j.avg||'—')+' ms</div></div>'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">'+_('الأعلى')+'</div><div class="kt-sub" style="font-size:20px;color:var(--kt-warn)">'+esc(j.max||'—')+' ms</div></div>'
				+ '</div>';
			graph.innerHTML = '<div class="kt-card"><h3>'+ktIcSvg('speed')+' '+_('زمن الذهاب والإياب لكل حزمة (ms)')+'</h3>'+latencyGraph(j.rtts||[])+'</div>';
		});
	});

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ktIc('radio'), ' '+_('Ping متقدم')]),
		E('div', { 'class':'kt-row' }, [
			E('div', { 'class':'kt-field', style:'flex:1;min-width:160px' }, [ E('label',{},_('المضيف (host)')), host ]),
			E('div', { 'class':'kt-field' }, [ E('label',{},_('عدد الحِزم')), count ]),
			E('div', { style:'align-self:flex-end' }, btn)
		]),
		stat, summ, graph
	]);
}

function iperfCard(){
	var srv = E('input', { type:'text', class:'cbi-input-text', placeholder:'iperf3 server IP (e.g. 192.168.1.50)' });
	var rev = E('input', { type:'checkbox' });
	var btn = E('button', { 'class':'kt-btn' }, _('ابدأ اختبار السرعة'));
	var stat= E('div', { 'class':'kt-sub', style:'margin:8px 0' }, '');
	var res = E('div', {}, '');

	btn.addEventListener('click', function(){
		var s = saniHost(srv.value);
		if (!s){ stat.style.color='var(--kt-bad)'; stat.textContent=_('أدخل عنوان خادم iperf3 (IP أو اسم مضيف)'); return; }
		srv.value = s;
		btn.disabled=true; stat.style.color='var(--kt-txt2)'; stat.textContent=_('جارٍ الاختبار… (قد يستغرق بضع ثوانٍ)'); res.innerHTML='';
		call({op:'iperf3', server:s, reverse: rev.checked?'1':'0'}).then(function(j){
			btn.disabled=false;
			if (!j || !j.ok){
				stat.style.color='var(--kt-bad)';
				if (j && j.error==='iperf3_missing') stat.textContent=_('الحزمة iperf3 غير مثبّتة — أبلغ المطوّر بإضافة حزمة iperf3 إلى الصورة');
				else if (j && j.error==='no_server') stat.textContent=_('لا يوجد خادم — أدخل عنوان خادم iperf3');
				else if (j && j.error==='iperf3_error') stat.textContent=_('تعذّر الاتصال بالخادم')+': '+esc(j.detail||'');
				else stat.textContent=_('فشل')+': '+esc((j&&j.error)||'?');
				return;
			}
			stat.style.color='var(--kt-ok)'; stat.textContent=_('اكتمل الاختبار');
			res.innerHTML='<div class="kt-grid kt-cols-2">'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">'+ktIcSvg('up')+' TX</div><div class="kt-sub" style="font-size:24px;color:var(--kt-accent)">'+esc(j.tx_mbps)+' Mbps</div></div>'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">'+ktIcSvg('down')+' RX</div><div class="kt-sub" style="font-size:24px;color:var(--kt-ok)">'+esc(j.rx_mbps)+' Mbps</div></div>'
				+ '</div>';
		});
	});

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ktIc('speed'), ' '+_('اختبار السرعة (iperf3)')]),
		E('div', { 'class':'kt-sub' }, _('يتطلب خادم iperf3 يمكن الوصول إليه (شغّل "iperf3 -s" على جهاز في الشبكة).')),
		E('div', { 'class':'kt-row', style:'margin-top:10px' }, [
			E('div', { 'class':'kt-field', style:'flex:1;min-width:200px' }, [ E('label',{},_('عنوان خادم iperf3')), srv ]),
			E('label', { 'class':'kt-row', style:'gap:6px;margin:0;align-self:flex-end' }, [ rev, E('span',{'class':'kt-sub'}, _('عكسي (تنزيل)')) ]),
			E('div', { style:'align-self:flex-end' }, btn)
		]),
		stat, res
	]);
}

/* zero-setup speed test: run iperf3 -s ON THE DEVICE so a phone/PC can test
   against it directly (iperf3 -c <device-ip>) with no other machine needed. */
function iperfServerCard(){
	var stat = E('div', { 'class':'kt-sub', style:'margin-top:8px' }, _('جارٍ القراءة…'));
	var btn  = E('button', { 'class':'kt-btn' }, _('تشغيل الخادم'));
	function paint(j){
		if (!j || !j.ok){ stat.textContent = (j&&j.error==='iperf3_missing') ? _('iperf3 غير مثبّت') : _('غير متاح'); return; }
		if (j.running){
			btn.textContent = _('إيقاف الخادم');
			stat.style.color = 'var(--kt-ok)';
			stat.innerHTML = ktIcSvg('check') + ' ' + _('الخادم يعمل — على جوالك شغّل:') + ' <b dir="ltr">iperf3 -c ' + esc(j.ip||'') + ' -p ' + esc(j.port||5201) + '</b>';
		} else {
			btn.textContent = _('تشغيل الخادم');
			stat.style.color = 'var(--kt-txt2)';
			stat.textContent = _('الخادم متوقف. شغّله ثم اختبر من جوالك ضد عنوان الجهاز.');
		}
	}
	function refresh(){ call({op:'iperf3_server', action:'status'}).then(paint); }
	btn.addEventListener('click', function(){
		btn.disabled = true;
		var on = /إيقاف/.test(btn.textContent);
		call({op:'iperf3_server', action: on?'stop':'start'}).then(function(j){ btn.disabled=false; paint(j); });
	});
	refresh();
	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, [ktIc('speed'), ' '+_('خادم السرعة على الجهاز (بدون إعداد)')]),
		E('div', { 'class':'kt-sub' }, _('شغّل خادم iperf3 هنا، ثم على جوالك/حاسوبك نفّذ الأمر الظاهر — تقيس السرعة الفعلية مباشرة ضد الجهاز.')),
		E('div', { style:'margin-top:10px' }, btn),
		stat
	]);
}

return view.extend({
	render: function(){
		return E('div', {}, [
			E('h2', {}, _('أدوات الشبكة')),
			E('div', { 'dir':'rtl' }, [
				E('div', { 'class':'kt-grid' }, [ pingCard() ]),
				E('div', { 'class':'kt-grid', style:'margin-top:14px' }, [ iperfServerCard() ]),
				E('div', { 'class':'kt-grid', style:'margin-top:14px' }, [ iperfCard() ])
			])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
