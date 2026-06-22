'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

/* All data comes from the rpcd "cr6606" backend -> real ubus/iwinfo/sysfs. */
var callSystem = rpc.declare({ object: 'cr6606', method: 'system' });
var callPorts  = rpc.declare({ object: 'cr6606', method: 'ports'  });
var callWifi   = rpc.declare({ object: 'cr6606', method: 'wifi'   });
var callWan    = rpc.declare({ object: 'cr6606', method: 'wan'    });
var callWanAct = rpc.declare({ object: 'cr6606', method: 'wan_action',  params: ['action'] });
var callWifiAct= rpc.declare({ object: 'cr6606', method: 'wifi_action', params: ['action'] });

function fmtBytes(n) {
	n = parseInt(n) || 0;
	var u = ['B','KB','MB','GB','TB'], i = 0;
	while (n >= 1024 && i < u.length-1) { n /= 1024; i++; }
	return n.toFixed(i ? 2 : 0) + ' ' + u[i];
}
function fmtUptime(s) {
	s = parseInt(s) || 0;
	var d = Math.floor(s/86400); s%=86400;
	var h = Math.floor(s/3600);  s%=3600;
	var m = Math.floor(s/60);
	return (d?d+'d ':'') + h + 'h ' + m + 'm';
}
function badge(ok, text) {
	return E('span', { 'style': 'padding:2px 8px;border-radius:10px;color:#fff;font-size:11px;background:' +
		(ok ? '#2e7d32' : '#c62828') }, text);
}
function card(title, body) {
	return E('div', { 'style': 'background:#fff;border:1px solid #e0e0e0;border-radius:10px;' +
		'box-shadow:0 1px 3px rgba(0,0,0,.08);padding:14px;margin:8px;flex:1 1 320px;min-width:300px' }, [
		E('h3', { 'style': 'margin:0 0 10px;color:#0b5394;border-bottom:2px solid #0b5394;padding-bottom:6px' }, title),
		body
	]);
}
function row(k, v) {
	return E('div', { 'style':'display:flex;justify-content:space-between;padding:3px 0;border-bottom:1px dotted #eee' }, [
		E('span', { 'style':'color:#555' }, k),
		E('span', { 'style':'font-weight:600;text-align:right' }, v)
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			callSystem().catch(function(){return {}}),
			callPorts().catch(function(){return {ports:[]}}),
			callWifi().catch(function(){return {radios:[]}}),
			callWan().catch(function(){return {}})
		]);
	},

	render: function(data) {
		var self = this;
		var container = E('div', { 'id': 'cr6606-dash' });
		this.draw(container, data);

		poll.add(L.bind(function() {
			return Promise.all([ callSystem(), callPorts(), callWifi(), callWan() ])
				.then(function(d) {
					var c = document.getElementById('cr6606-dash');
					if (c) { c.innerHTML=''; self.draw(c, d); }
				});
		}, this), 5);

		return container;
	},

	draw: function(container, data) {
		var sys = data[0]||{}, ports=(data[1]||{}).ports||[], wifi=(data[2]||{}).radios||[], wan=data[3]||{};

		/* ---- SYSTEM ---- */
		var memPct = sys.mem_total ? Math.round(100*(sys.mem_total-sys.mem_avail)/sys.mem_total) : 0;
		var flPct  = sys.flash_total ? Math.round(100*sys.flash_used/sys.flash_total) : 0;
		var temp = (typeof sys.temp_mc === 'number') ? (sys.temp_mc/1000).toFixed(1)+' °C' : 'n/a';
		var sysBody = E('div', {}, [
			row(_('Model'), sys.model||'?'),
			row(_('Firmware'), sys.release||'?'),
			row(_('Uptime'), fmtUptime(sys.uptime)),
			row(_('Load (1/5/15m)'), sys.load||'?'),
			row(_('RAM'), memPct+'%  ('+fmtBytes((sys.mem_total-sys.mem_avail)*1024)+' / '+fmtBytes(sys.mem_total*1024)+')'),
			row(_('Flash'), flPct+'%  ('+fmtBytes(sys.flash_used*1024)+' / '+fmtBytes(sys.flash_total*1024)+')'),
			row(_('Temperature'), temp)
		]);

		/* services badges */
		var svc = sys.services||{}, svcRow = E('div', { 'style':'margin-top:8px;display:flex;flex-wrap:wrap;gap:6px' });
		Object.keys(svc).forEach(function(k){
			if (svc[k]==='n/a') return;
			svcRow.appendChild(badge(svc[k]==='up', k));
		});
		sysBody.appendChild(E('div',{'style':'margin-top:8px;color:#555'}, _('Services')));
		sysBody.appendChild(svcRow);

		/* ---- WAN ---- */
		var wanUp = !!wan.up;
		var wanBody = E('div', {}, [
			E('div',{'style':'margin-bottom:6px'}, [ badge(wanUp, wanUp?_('CONNECTED'):_('DOWN')) ]),
			row(_('Protocol'), (wan.proto||'?').toUpperCase()),
			row(_('IP'), wan.ip||'-'),
			row(_('Gateway'), wan.gateway||'-'),
			row(_('DNS'), wan.dns||'-'),
			row(_('Connected for'), fmtUptime(wan.uptime)),
			row(_('Downloaded'), fmtBytes(wan.rx_bytes)),
			row(_('Uploaded'), fmtBytes(wan.tx_bytes)),
			E('button', { 'class':'btn cbi-button cbi-button-action', 'style':'margin-top:8px',
				'click': ui.createHandlerFn(this, function(){
					return callWanAct('reconnect').then(function(){ ui.addNotification(null, E('p',_('WAN reconnect triggered'))); });
				}) }, _('Reconnect WAN'))
		]);

		/* ---- PORTS ---- */
		var ptbl = E('table', { 'class':'table', 'style':'width:100%' }, [
			E('tr', { 'class':'tr table-titles' }, [
				E('th',{'class':'th'},_('Port')), E('th',{'class':'th'},_('Link')),
				E('th',{'class':'th'},_('Speed')), E('th',{'class':'th'},_('Role')),
				E('th',{'class':'th'},_('VLANs')), E('th',{'class':'th'},'RX/TX'),
				E('th',{'class':'th'},_('Err/Drop'))
			])
		]);
		ports.forEach(function(p){
			ptbl.appendChild(E('tr',{'class':'tr'},[
				E('td',{'class':'td'}, p.name),
				E('td',{'class':'td'}, badge(p.link==='up', p.link)),
				E('td',{'class':'td'}, p.speed==='-'?'-':(p.speed+'M '+(p.duplex||''))),
				E('td',{'class':'td'}, p.role + (p.admin==='disabled'?' (off)':'')),
				E('td',{'class':'td'}, p.vlans||'-'),
				E('td',{'class':'td'}, fmtBytes(p.rx_bytes)+' / '+fmtBytes(p.tx_bytes)),
				E('td',{'class':'td'}, (p.rx_err+p.tx_err)+' / '+(p.rx_drop+p.tx_drop))
			]));
		});

		/* ---- WIFI ---- */
		var wf = E('div', {});
		wf.appendChild(E('div',{'style':'margin-bottom:8px'},[
			E('button',{'class':'btn cbi-button cbi-button-action','style':'margin-right:6px',
				'click': ui.createHandlerFn(this, function(){
					return callWifiAct('restart').then(function(){ ui.addNotification(null,E('p',_('Wi-Fi restarted'))); });
				})}, _('Restart Wi-Fi')),
			E('button',{'class':'btn cbi-button','click': function(){ location.href='/cgi-bin/luci/admin/network/wireless'; }}, _('Wi-Fi Scan / Config'))
		]));
		wifi.forEach(function(r){
			var actual = r.txpower_actual, req = r.txpower_req;
			var pwTxt = (actual==='down'||!actual) ? _('radio down')
				: (actual + ' dBm ' + (parseInt(actual)>=parseInt(req) ? '('+_('reached %s').format(req)+')' : '('+_('requested %s, real %s').format(req, actual)+')'));
			wf.appendChild(E('div',{'style':'border:1px solid #eee;border-radius:8px;padding:8px;margin-bottom:6px'},[
				E('div',{'style':'font-weight:700;color:#0b5394'}, (r.band||'?').toUpperCase()+'  ['+(r.iface||r.phy)+']'),
				row('SSID', r.ssid||'-'),
				row(_('Channel / Width'), (r.channel||'-')+' / '+(r.htmode||'-')),
				row(_('Tx-Power (req → real)'), pwTxt),
				row(_('Noise'), r.noise?(r.noise+' dBm'):'-'),
				row(_('Clients'), String(r.client_count||0))
			]));
		});

		container.appendChild(E('h2', {}, _('CR6606 Dashboard')));
		container.appendChild(E('div', { 'style':'display:flex;flex-wrap:wrap' }, [
			card(_('System'), sysBody),
			card(_('WAN / Internet'), wanBody),
			card(_('LAN / Ports'), ptbl),
			card(_('Wi-Fi'), wf)
		]));

		/* logs */
		container.appendChild(card(_('Recent log errors'),
			E('pre',{'style':'white-space:pre-wrap;font-size:11px;max-height:140px;overflow:auto;background:#fafafa'},
				(sys.log_errors||_('none'))+'\n'+(sys.dmesg_tail||''))));
		return container;
	},

	handleSaveApply: null, handleSave: null, handleReset: null
});
