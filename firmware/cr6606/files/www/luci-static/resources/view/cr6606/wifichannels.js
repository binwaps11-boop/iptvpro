'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callWifi = rpc.declare({ object:'cr6606', method:'wifi' });

function row(k,v){ return E('div',{'style':'display:flex;justify-content:space-between;padding:3px 0;border-bottom:1px dotted #eee'},[
	E('span',{'style':'color:#555'},k), E('span',{'style':'font-weight:600'},v)]); }

return view.extend({
	load: function(){ return callWifi().catch(function(){return {radios:[]}}); },
	render: function(data){
		var self=this;
		var box=E('div',{'id':'wc-box'}); this.draw(box,data);
		poll.add(L.bind(function(){ return callWifi().then(function(d){ var c=document.getElementById('wc-box'); if(c){c.innerHTML='';self.draw(c,d);} }); },this),5);
		return E('div',{},[
			E('h2',{},_('Wi-Fi Channels & Power')),
			E('div',{'class':'alert-message','style':'background:#fff8e1;border-color:#ffe082'}, [
				E('strong',{},_('Honest power reporting. ')),
				_('UCI requests txpower 30 on both radios. The ACTUAL applied value = min(requested, US regulatory limit, mt7915 board limit) and is read live from iwinfo below — never faked. For a full per-channel breakdown (which channels reach 30 dBm and which do not), run on the device: '),
				E('code',{},'sh /root/verify-wifi-channels.sh')
			]),
			box
		]);
	},
	draw: function(container, data){
		var radios=(data||{}).radios||[];
		radios.forEach(function(r){
			var actual=r.txpower_actual, req=r.txpower_req;
			var verdict;
			if (actual==='down'||!actual) verdict=E('span',{'style':'color:#c62828'},_('radio is down — enable Wi-Fi to measure'));
			else if (parseInt(actual)>=parseInt(req)) verdict=E('span',{'style':'color:#2e7d32;font-weight:700'}, _('30 dBm is REAL here (iwinfo = %s dBm)').format(actual));
			else verdict=E('span',{'style':'color:#e65100;font-weight:700'}, _('Highest REAL value = %s dBm (below requested %s — this is the truth)').format(actual, req));
			container.appendChild(E('div',{'style':'background:#fff;border:1px solid #e0e0e0;border-radius:10px;padding:14px;margin:10px 0'},[
				E('h3',{'style':'margin:0 0 8px;color:#0b5394'}, (r.band||'?').toUpperCase()+'  ['+(r.iface||r.phy)+']'),
				row('SSID', r.ssid||'-'),
				row(_('Operating channel'), r.channel||'-'),
				row(_('Width (HE/VHT/HT)'), r.htmode||'-'),
				row(_('Tx-Power requested (UCI)'), (req||'?')+' dBm'),
				row(_('Tx-Power actual (iwinfo)'), (actual==='down'?'-':(actual+' dBm'))),
				row(_('Noise floor'), r.noise?(r.noise+' dBm'):'-'),
				row(_('Connected clients'), String(r.client_count||0)),
				E('div',{'style':'margin-top:8px;padding:8px;background:#fafafa;border-radius:6px'}, verdict)
			]));
		});
		if (!radios.length) container.appendChild(E('p',{},_('No radios detected.')));
		return container;
	},
	handleSaveApply:null, handleSave:null, handleReset:null
});
