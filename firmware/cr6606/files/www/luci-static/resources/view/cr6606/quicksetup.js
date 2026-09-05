'use strict';
'require view';
'require uci';
'require ui';
'require fs';

/* Safe Apply: uci.save() + uci.apply() uses OpenWrt's apply-with-rollback
   (config is auto-reverted if you do not confirm within the timeout), so a bad
   network/VLAN change can NEVER lock you out permanently. */

function section(title, desc, body){
	return E('div',{'style':'background:#fff;border:1px solid #e0e0e0;border-radius:10px;padding:14px;margin:10px 0'},[
		E('h3',{'style':'margin:0 0 4px;color:#0b5394'}, title),
		desc?E('p',{'class':'cbi-section-descr'}, desc):'',
		body
	]);
}
function field(label, el){
	return E('div',{'style':'display:flex;align-items:center;margin:4px 0;gap:8px'},[
		E('label',{'style':'width:180px;color:#444'}, label), el ]);
}
function inp(id,ph,val){ return E('input',{'id':id,'type':'text','placeholder':ph||'','value':val||'','class':'cbi-input-text','style':'flex:1'}); }
function val(id){ var e=document.getElementById(id); return e?e.value.trim():''; }

function safeApply(){
	return uci.save().then(function(){
		ui.addNotification(null, E('p', _('Applying with rollback — confirm within the countdown or it auto-reverts.')));
		return uci.apply();   /* shows the rollback countdown dialog */
	});
}

return view.extend({
	load: function(){ return uci.load(['network','wireless','dhcp','firewall']); },

	render: function(){
		var self=this;

		/* ---- Mode ---- */
		var modeBody = E('div',{},[
			E('button',{'class':'btn cbi-button cbi-button-positive','style':'margin:4px',
				'click': ui.createHandlerFn(this, function(){
					uci.set('network','wan','disabled','0');
					uci.set('network','wan','proto','dhcp');
					uci.set('dhcp','lan','ignore','0');
					uci.set('network','lan','ipaddr','192.168.100.1');
					return safeApply();
				})}, _('Normal Router Mode (NAT + DHCP)')),
			E('button',{'class':'btn cbi-button cbi-button-action','style':'margin:4px',
				'click': ui.createHandlerFn(this, function(){
					if (!confirm(_('AP/Bridge mode: WAN disabled, DHCP server off, uplink goes to a LAN port. Continue (rollback protected)?'))) return;
					uci.set('network','wan','disabled','1');
					uci.set('dhcp','lan','ignore','1');
					uci.set('network','lan','proto','dhcp');
					return safeApply();
				})}, _('AP / Bridge Mode'))
		]);

		/* ---- WAN DHCP ---- */
		var dhcpBody = E('div',{},[
			E('button',{'class':'btn cbi-button cbi-button-positive',
				'click': ui.createHandlerFn(this, function(){
					uci.set('network','wan','disabled','0');
					uci.set('network','wan','proto','dhcp');
					uci.unset('network','wan','username'); uci.unset('network','wan','password');
					return safeApply();
				})}, _('Set WAN = DHCP'))
		]);

		/* ---- WAN Static ---- */
		var stBody = E('div',{},[
			field(_('IP address'), inp('st_ip','192.168.1.2')),
			field(_('Netmask'), inp('st_mask','255.255.255.0')),
			field(_('Gateway'), inp('st_gw','192.168.1.1')),
			field('DNS', inp('st_dns','1.1.1.1 8.8.8.8')),
			field('MTU', inp('st_mtu','1500')),
			E('button',{'class':'btn cbi-button cbi-button-positive','style':'margin-top:6px',
				'click': ui.createHandlerFn(this, function(){
					uci.set('network','wan','disabled','0');
					uci.set('network','wan','proto','static');
					uci.set('network','wan','ipaddr', val('st_ip'));
					uci.set('network','wan','netmask', val('st_mask'));
					uci.set('network','wan','gateway', val('st_gw'));
					uci.set('network','wan','dns', val('st_dns'));
					if (val('st_mtu')) uci.set('network','wan','mtu', val('st_mtu'));
					return safeApply();
				})}, _('Apply Static WAN'))
		]);

		/* ---- PPPoE Broadband ---- */
		var ppBody = E('div',{},[
			field(_('Username'), inp('pp_user','user@isp')),
			field(_('Password'), inp('pp_pass','')),
			field('MTU', inp('pp_mtu','1492')),
			E('button',{'class':'btn cbi-button cbi-button-positive','style':'margin-top:6px',
				'click': ui.createHandlerFn(this, function(){
					uci.set('network','wan','disabled','0');
					uci.set('network','wan','proto','pppoe');
					uci.set('network','wan','username', val('pp_user'));
					uci.set('network','wan','password', val('pp_pass'));
					uci.set('network','wan','mtu', val('pp_mtu')||'1492');
					/* MSS clamp for PPPoE on the wan firewall zone */
					var zones = uci.sections('firewall','zone');
					zones.forEach(function(z){ if (z.name==='wan') uci.set('firewall', z['.name'], 'mtu_fix','1'); });
					return safeApply();
				})}, _('Connect PPPoE'))
		]);

		/* ---- Backup / Restore ---- */
		var brBody = E('div',{},[
			E('button',{'class':'btn cbi-button','style':'margin:4px',
				'click': function(){ location.href='/cgi-bin/luci/admin/system/flash'; }},
				_('Backup / Restore Config (official page)')),
			E('p',{'class':'cbi-section-descr'},
				_('CLI: backup before flashing → sysupgrade -b /tmp/backup-cr6606.tar.gz'))
		]);

		return E('div',{},[
			E('h2',{}, _('Quick Setup')),
			E('div',{'class':'alert-message','style':'background:#e3f2fd;border-color:#90caf9'},
				_('Every button here uses Safe Apply with automatic rollback. If a change would disconnect you, simply do not confirm and the router reverts on its own.')),
			section(_('Operating Mode'), _('Switch between a normal NAT router and an access point.'), modeBody),
			section(_('Broadband: WAN DHCP'), _('Most common — get an address from the modem/ISP automatically.'), dhcpBody),
			section(_('Broadband: WAN Static'), _('Fixed IP from the ISP.'), stBody),
			section(_('Broadband: PPPoE'), _('DSL/fiber login. MSS clamp is enabled automatically on the WAN zone.'), ppBody),
			section(_('VLAN / Port / Wi-Fi / Mesh'), _('Use the dedicated pages: CR6606 → Port Control, Network → Wireless (Wi-Fi/Mesh), Network → Interfaces / bridge VLAN. All honor Save & Apply rollback.'),
				E('div',{},[
					E('button',{'class':'btn cbi-button','style':'margin:4px','click':function(){location.href='/cgi-bin/luci/admin/network/network';}}, _('Interfaces / VLAN')),
					E('button',{'class':'btn cbi-button','style':'margin:4px','click':function(){location.href='/cgi-bin/luci/admin/network/wireless';}}, _('Wireless / Mesh')),
					E('button',{'class':'btn cbi-button','style':'margin:4px','click':function(){location.href='/cgi-bin/luci/admin/cr6606/portcontrol';}}, _('Port Control'))
				])),
			section(_('Backup / Restore'), _('Always back up before flashing.'), brBody)
		]);
	},

	handleSaveApply:null, handleSave:null, handleReset:null
});
