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
function ktIcSvg(n){return '<svg class="kti" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(KTI[n]||KTI.dot)+'</svg>';}
function ktIc(n){var d=document.createElement('div');d.innerHTML=ktIcSvg(n);return d.firstChild;}

/* KT412 MK APP — DSA Switch / Port Manager (التحكم بالمنافذ).
   DSA (qca8k), NOT swconfig. Ports: lan1-4 + wan, conduit eth0, bridge br-lan.
   - op=getswitch : link/speed/duplex (/sys/class/net) + bridge membership
   - op=setswitch : enable/disable, add/remove from bridge, set bridge-vlan
   Visual port tiles + a simple port/VLAN matrix. RTL Arabic, mobile-first. */

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

function portLabel(name){
	if (name === 'wan') return 'WAN';
	return name.toUpperCase();
}

return view.extend({
	load: function(){
		return call({ op:'getswitch' }).catch(function(){ return {}; });
	},
	render: function(res){
		var data = res || {};
		var bridge = data.bridge || 'br-lan';
		var grid = E('div', { class:'kt-grid kt-cols-3' });
		var matrixWrap = E('div', { class:'kt-card', style:'overflow-x:auto' });

		function notify(r){
			if (r && r.ok) { ui.addNotification(null, E('p', {}, r.msg || _('تم.')), 'info'); refresh(); }
			else ui.addNotification(null, E('p', {}, _('فشل: %s').format((r&&r.error)||'')), 'error');
		}

		function tile(p){
			var linkUp = +p.carrier === 1;
			var color = linkUp ? 'linear-gradient(135deg,#1faa6e,#54e3ad)' : 'linear-gradient(135deg,#5b6275,#3a3f4c)';
			var speed = (p.speed && +p.speed > 0) ? (p.speed + 'Mbps') : _('لا رابط');
			var t = E('div', { class:'kt-tile', style:'background:'+color }, [
				E('div', { class:'ti' }, [ ktIc('dot') ]),
				E('div', { class:'tn', style:'font-size:20px' }, portLabel(p.name)),
				E('div', { class:'tl' }, speed + (linkUp && p.duplex && p.duplex!=='unknown' ? ' · ' + p.duplex : '')),
				E('div', { class:'tl' }, +p.in_bridge ? _('داخل الجسر') : _('خارج الجسر'))
			]);

			var btnEn = E('button', { class:'kt-btn sec', style:'flex:1' }, p.oper==='down' ? _('تفعيل') : _('تعطيل'));
			btnEn.onclick = function(){
				btnEn.textContent='…';
				call({ op:'setswitch', port:p.name, action: (p.oper==='down'?'enable':'disable') }, true).then(notify);
			};
			var btnBr = E('button', { class:'kt-btn sec', style:'flex:1' }, +p.in_bridge ? _('إزالة من الجسر') : _('إضافة للجسر'));
			btnBr.onclick = function(){
				btnBr.textContent='…';
				call({ op:'setswitch', port:p.name, action: (+p.in_bridge?'del_bridge':'add_bridge') }, true).then(notify);
			};

			var vlanIn = E('input', { type:'text', class:'cbi-input-text', placeholder:'VLAN', style:'flex:1;min-width:0' });
			var btnVlan = E('button', { class:'kt-btn sec' }, _('ضبط') );
			btnVlan.onclick = function(){
				var v = (vlanIn.value||'').replace(/[^0-9]/g,'');
				if (!v) { ui.addNotification(null, E('p', {}, _('أدخل رقم VLAN صالحاً.')), 'warning'); return; }
				btnVlan.textContent='…';
				call({ op:'setswitch', port:p.name, action:'set_vlan', vlan:v }, true).then(notify);
			};

			return E('div', { class:'kt-card' }, [
				t,
				E('div', { style:'display:flex;gap:8px;margin-top:10px' }, [ btnEn, btnBr ]),
				E('div', { style:'display:flex;gap:8px;margin-top:8px;align-items:center' }, [ vlanIn, btnVlan ])
			]);
		}

		function renderMatrix(ports){
			matrixWrap.innerHTML = '';
			var thead = E('tr', {}, [ E('th', { style:'text-align:start;padding:6px 10px' }, _('المنفذ')) ]
				.concat([ _('الحالة'), _('السرعة'), _('Duplex'), _('الجسر') ].map(function(h){
					return E('th', { style:'text-align:start;padding:6px 10px' }, h);
				})));
			var rows = ports.map(function(p){
				var up = +p.carrier === 1;
				return E('tr', {}, [
					E('td', { style:'padding:6px 10px;font-weight:700' }, portLabel(p.name)),
					E('td', { style:'padding:6px 10px' }, E('span', { class:'kt-badge ' + (up?'ok':'warn') }, up ? _('متصل') : _('غير متصل'))),
					E('td', { style:'padding:6px 10px' }, (p.speed && +p.speed>0) ? (p.speed+'M') : '—'),
					E('td', { style:'padding:6px 10px' }, (p.duplex && p.duplex!=='unknown') ? p.duplex : '—'),
					E('td', { style:'padding:6px 10px' }, +p.in_bridge ? E('span', {}, [ ktIc('check') ]) : '—')
				]);
			});
			matrixWrap.appendChild(E('table', { class:'table', style:'width:100%;border-collapse:collapse' }, [
				E('thead', {}, thead), E('tbody', {}, rows)
			]));
		}

		function paint(d){
			bridge = d.bridge || bridge;
			var ports = d.ports || [];
			grid.innerHTML = '';
			ports.forEach(function(p){ grid.appendChild(tile(p)); });
			renderMatrix(ports);
		}

		function refresh(){
			call({ op:'getswitch' }).then(paint);
		}

		paint(data);

		var refreshBtn = E('button', { class:'kt-btn sec' }, [ ktIc('refresh'), ' ' + _('تحديث') ]);
		refreshBtn.onclick = refresh;

		return E('div', {}, [
			E('h2', {}, _('التحكم بالمنافذ — مبدّل DSA')),
			E('p', { class:'kt-sub', style:'margin-bottom:12px' },
				_('الجسر: %s · منفذ التوصيل: eth0 · منافذ: lan1-4 و wan').format(bridge)),
			E('div', { style:'margin-bottom:12px' }, refreshBtn),
			grid,
			E('h3', { style:'margin:18px 0 8px' }, _('مصفوفة المنافذ')),
			matrixWrap
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
