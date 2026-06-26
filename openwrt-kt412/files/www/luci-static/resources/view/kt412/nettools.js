'use strict';
'require view';
'require ui';

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
			graph.innerHTML = '<div class="kt-card"><h3>📈 '+_('زمن الذهاب والإياب لكل حزمة (ms)')+'</h3>'+latencyGraph(j.rtts||[])+'</div>';
		});
	});

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '🛰️ '+_('Ping متقدم')),
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
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">↑ TX</div><div class="kt-sub" style="font-size:24px;color:var(--kt-accent)">'+esc(j.tx_mbps)+' Mbps</div></div>'
				+ '<div class="kt-card kt-gcard"><div class="kt-glabel">↓ RX</div><div class="kt-sub" style="font-size:24px;color:var(--kt-ok)">'+esc(j.rx_mbps)+' Mbps</div></div>'
				+ '</div>';
		});
	});

	return E('div', { 'class':'kt-card' }, [
		E('h3', {}, '🚀 '+_('اختبار السرعة (iperf3)')),
		E('div', { 'class':'kt-sub' }, _('يتطلب خادم iperf3 يمكن الوصول إليه (شغّل "iperf3 -s" على جهاز في الشبكة).')),
		E('div', { 'class':'kt-row', style:'margin-top:10px' }, [
			E('div', { 'class':'kt-field', style:'flex:1;min-width:200px' }, [ E('label',{},_('عنوان خادم iperf3')), srv ]),
			E('label', { 'class':'kt-row', style:'gap:6px;margin:0;align-self:flex-end' }, [ rev, E('span',{'class':'kt-sub'}, _('عكسي (تنزيل)')) ]),
			E('div', { style:'align-self:flex-end' }, btn)
		]),
		stat, res
	]);
}

return view.extend({
	render: function(){
		return E('div', {}, [
			E('h2', {}, _('أدوات الشبكة')),
			E('div', { 'dir':'rtl' }, [
				E('div', { 'class':'kt-grid' }, [ pingCard() ]),
				E('div', { 'class':'kt-grid', style:'margin-top:14px' }, [ iperfCard() ])
			])
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
