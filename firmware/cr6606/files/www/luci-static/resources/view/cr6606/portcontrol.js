'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callPorts   = rpc.declare({ object:'cr6606', method:'ports' });
var callPortAct = rpc.declare({ object:'cr6606', method:'port_action', params:['port','action'] });

function fmtBytes(n){ n=parseInt(n)||0; var u=['B','KB','MB','GB','TB'],i=0;
	while(n>=1024&&i<u.length-1){n/=1024;i++;} return n.toFixed(i?2:0)+' '+u[i]; }
function badge(ok,t){ return E('span',{'style':'padding:2px 8px;border-radius:10px;color:#fff;font-size:11px;background:'+(ok?'#2e7d32':'#c62828')},t); }

return view.extend({
	load: function(){ return callPorts().catch(function(){return {ports:[]}}); },

	render: function(data){
		var self=this;
		var box=E('div',{'id':'pc-box'});
		this.draw(box, data);
		poll.add(L.bind(function(){
			return callPorts().then(function(d){ var c=document.getElementById('pc-box'); if(c){c.innerHTML='';self.draw(c,d);} });
		}, this), 5);
		return E('div',{},[
			E('h2',{},_('Port Control')),
			E('p',{'class':'cbi-section-descr'}, _('Real per-port control on CR6606 (DSA: lan1/lan2/lan3 on the switch + a dedicated WAN port). Enable/Disable/Restart act immediately via the kernel and the disabled state is persisted in /etc/config/cr6606 across reboots.')),
			box,
			E('div',{'class':'alert-message warning','style':'margin-top:12px'}, [
				E('strong',{},_('LAN ↔ WAN role change: ')),
				_('On CR6606 the WAN port is a physically separate MAC/PHY (gmac1), while lan1–lan3 sit on the mt7530 switch. A switch LAN port therefore cannot become the hardware WAN uplink. To route a LAN port to the WAN/Internet zone, use a VLAN + firewall zone (Network → Interfaces / the VLAN page) — that is the supported method. No fake LAN↔WAN button is shown here on purpose.')
			])
		]);
	},

	draw: function(container, data){
		var ports=(data||{}).ports||[];
		var tbl=E('table',{'class':'table','style':'width:100%'},[
			E('tr',{'class':'tr table-titles'},[
				E('th',{'class':'th'},_('Port')), E('th',{'class':'th'},_('Admin')),
				E('th',{'class':'th'},_('Link')), E('th',{'class':'th'},_('Speed/Duplex')),
				E('th',{'class':'th'},_('Role')), E('th',{'class':'th'},_('VLANs')),
				E('th',{'class':'th'},_('RX / TX total')), E('th',{'class':'th'},_('Err / Drop')),
				E('th',{'class':'th'},_('Actions'))
			])
		]);
		ports.forEach(L.bind(function(p){
			var mkBtn=L.bind(function(label,cls,action){
				return E('button',{'class':'btn cbi-button '+cls,'style':'margin:1px',
					'click': ui.createHandlerFn(this, function(){
						return callPortAct(p.name, action).then(function(r){
							ui.addNotification(null, E('p', (r&&r.result)||(r&&r.error)||action));
						});
					})}, label);
			}, this);
			tbl.appendChild(E('tr',{'class':'tr'},[
				E('td',{'class':'td'}, E('b',{},p.name)),
				E('td',{'class':'td'}, badge(p.admin!=='disabled', p.admin)),
				E('td',{'class':'td'}, badge(p.link==='up', p.link)),
				E('td',{'class':'td'}, p.speed==='-'?'-':(p.speed+'M / '+(p.duplex||'-'))),
				E('td',{'class':'td'}, p.role),
				E('td',{'class':'td'}, p.vlans||'-'),
				E('td',{'class':'td'}, fmtBytes(p.rx_bytes)+' / '+fmtBytes(p.tx_bytes)),
				E('td',{'class':'td'}, (p.rx_err+p.tx_err)+' / '+(p.rx_drop+p.tx_drop)),
				E('td',{'class':'td'},[
					mkBtn(_('Enable'),'cbi-button-positive','enable'),
					mkBtn(_('Disable'),'cbi-button-negative','disable'),
					mkBtn(_('Restart'),'cbi-button-action','restart')
				])
			]));
		}, this));
		container.appendChild(tbl);
		return container;
	},

	handleSaveApply:null, handleSave:null, handleReset:null
});
