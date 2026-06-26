'use strict';
'require view';
'require ui';

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
				E('div', { class:'ti' }, linkUp ? '🟢' : '⚪'),
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
					E('td', { style:'padding:6px 10px' }, +p.in_bridge ? '✅' : '—')
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

		var refreshBtn = E('button', { class:'kt-btn sec' }, _('🔄 تحديث'));
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
