'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callMesh = rpc.declare({ object:'cr6606', method:'mesh' });

function row(k,v){ return E('div',{'style':'display:flex;justify-content:space-between;padding:3px 0;border-bottom:1px dotted #eee'},[
	E('span',{'style':'color:#555'},k), E('span',{'style':'font-weight:600'},v)]); }

return view.extend({
	load: function(){ return callMesh().catch(function(){return {supported:false,meshes:[]}}); },
	render: function(data){
		var self=this;
		var box=E('div',{'id':'mesh-box'}); this.draw(box,data);
		poll.add(L.bind(function(){ return callMesh().then(function(d){ var c=document.getElementById('mesh-box'); if(c){c.innerHTML='';self.draw(c,d);} }); },this),5);
		return E('div',{},[ E('h2',{},_('Mesh (802.11s)')), box ]);
	},
	draw: function(container, data){
		var supp=!!data.supported, meshes=data.meshes||[];
		container.appendChild(E('div',{'class':'alert-message','style':supp?'background:#e8f5e9;border-color:#a5d6a7':'background:#ffebee;border-color:#ef9a9a'},[
			E('strong',{}, supp?_('Mesh IS supported on this device. '):_('Mesh point mode not detected. ')),
			supp ? _('The CR6606 mt7915/mt76 radio supports 802.11s and this firmware ships wpad-mesh-mt76 (SAE encryption capable).')
			     : _('Ensure wpad-mesh-mt76 is installed (it is in this build). Driver: ')+(data.driver||'')
		]));
		container.appendChild(E('div',{'style':'background:#fff;border:1px solid #e0e0e0;border-radius:10px;padding:14px;margin:10px 0'},[
			row(_('Driver'), data.driver||'mt76 / mt7915'),
			row(_('802.11s capable'), supp?_('YES'):_('NO')),
			row(_('Active mesh interfaces'), String(meshes.length))
		]));
		meshes.forEach(function(m){
			container.appendChild(E('div',{'style':'background:#fff;border:1px solid #e0e0e0;border-radius:10px;padding:14px;margin:10px 0'},[
				E('h3',{'style':'margin:0 0 8px;color:#0b5394'}, m.iface),
				row('Mesh ID', m.mesh_id||'-'),
				row(_('Peers'), String(m.peers||0))
			]));
		});
		container.appendChild(E('div',{'class':'cbi-section-descr','style':'margin-top:8px'}, [
			E('strong',{},_('How to enable a mesh radio: ')),
			_('Go to Network → Wireless, Edit a radio, set Mode = "802.11s Mesh", enter a Mesh ID, choose SAE encryption, assign to the lan network, then Save & Apply. Peers and signal will appear here.')
		]));
		container.appendChild(E('button',{'class':'btn cbi-button cbi-button-action','style':'margin-top:8px',
			'click':function(){location.href='/cgi-bin/luci/admin/network/wireless';}}, _('Open Wireless to add a Mesh interface')));
		return container;
	},
	handleSaveApply:null, handleSave:null, handleReset:null
});
