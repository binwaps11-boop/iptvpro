'use strict';
'require view';
'require uci';
'require form';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('cr6608quick'),
			uci.load('network'),
			uci.load('wireless'),
			uci.load('dhcp'),
			uci.load('firewall')
		]);
	},

	render: function() {
		var m, s, o;

		m = new form.Map('cr6608quick', _('الإعدادات السريعة'),
			_('إعداد موحد لجهاز Xiaomi CR6608. يتم الحفظ عبر UCI مع نسخة احتياطية، ولا يتم تغيير TX Power من هذه الصفحة.'));

		s = m.section(form.NamedSection, 'default', 'quick', _('Xiaomi CR6608'));
		s.addremove = false;

		s.tab('device', _('إعدادات الجهاز'));
		s.tab('security', _('إعدادات الحماية'));
		s.tab('advanced', _('إعدادات متقدمة'));

		o = s.taboption('device', form.ListValue, 'mode', _('وضع البرمجة'));
		o.rmempty = false;
		o.value('ap', _('Access Point (AP)'));
		o.value('ap_vlan', _('AP + VLAN'));
		o.value('mesh', _('Mesh'));
		o.value('mesh_vlan', _('Mesh + VLAN'));
		o.value('wds_sender', _('WDS مرسل'));
		o.value('wds_sender_vlan', _('WDS مرسل + VLAN'));
		o.value('wds_receiver', _('WDS مستقبل'));
		o.value('wds_receiver_vlan', _('WDS مستقبل + VLAN'));
		o.value('pppoe', _('Access Point برودباند (PPPoE)'));

		o = s.taboption('device', form.Value, 'lan_ipaddr', _('عنوان IP'));
		o.datatype = 'ip4addr';
		o.placeholder = '192.168.1.1';

		o = s.taboption('device', form.ListValue, 'lan_netmask', _('قناع الشبكة'));
		o.value('255.255.255.0');
		o.value('255.255.0.0');
		o.value('255.0.0.0');
		o.rmempty = false;

		o = s.taboption('device', form.Value, 'vlan_id', _('رقم VLAN'));
		o.datatype = 'range(1,4094)';
		o.depends('mode', 'ap_vlan');
		o.depends('mode', 'mesh_vlan');
		o.depends('mode', 'wds_sender_vlan');
		o.depends('mode', 'wds_receiver_vlan');

		o = s.taboption('device', form.Value, 'ssid', _('اسم بث 2.4G'));
		o.datatype = 'maxlength(32)';
		o.placeholder = 'Smart-AP';

		o = s.taboption('device', form.Value, 'ssid5', _('اسم بث 5G'));
		o.datatype = 'maxlength(32)';
		o.placeholder = 'Smart-AP-5G';

		o = s.taboption('device', form.ListValue, 'channel24', _('قناة 2.4G'));
		o.value('auto', _('تلقائي'));
		o.value('1', '1');
		o.value('6', '6');
		o.value('11', '11');

		o = s.taboption('device', form.ListValue, 'channel5', _('قناة 5G'));
		o.value('36', '36');
		o.value('40', '40');
		o.value('44', '44');
		o.value('48', '48');
		o.value('auto', _('تلقائي'));

		o = s.taboption('device', form.Value, 'mesh_id', _('عنوان Mesh'));
		o.datatype = 'maxlength(32)';
		o.depends('mode', 'mesh');
		o.depends('mode', 'mesh_vlan');

		o = s.taboption('device', form.Value, 'wds_ssid', _('اسم مرسل WDS'));
		o.datatype = 'maxlength(32)';
		o.depends('mode', 'wds_sender');
		o.depends('mode', 'wds_sender_vlan');
		o.depends('mode', 'wds_receiver');
		o.depends('mode', 'wds_receiver_vlan');

		o = s.taboption('device', form.Flag, 'hide_ssid', _('إخفاء البث'));
		o.depends('mode', 'wds_sender');
		o.depends('mode', 'wds_sender_vlan');

		o = s.taboption('device', form.ListValue, 'security', _('نوع الحماية'));
		o.value('open', _('مفتوح'));
		o.value('wpa2', 'WPA2-PSK');
		o.value('wpa3', 'WPA3-SAE');
		o.value('mixed', 'WPA2/WPA3 Mixed');
		o.rmempty = false;

		o = s.taboption('device', form.Value, 'wifi_key', _('كلمة مرور Wi-Fi'));
		o.datatype = 'wpakey';
		o.password = true;
		o.depends('security', 'wpa2');
		o.depends('security', 'wpa3');
		o.depends('security', 'mixed');

		o = s.taboption('device', form.Flag, 'change_password', _('تغيير كلمة مرور الجهاز'));
		o.default = '0';

		o = s.taboption('device', form.Value, 'admin_password', _('كلمة مرور الجهاز الجديدة'));
		o.password = true;
		o.depends('change_password', '1');

		o = s.taboption('device', form.Flag, 'clear_previous', _('حذف إعدادات البرمجة السابقة'));
		o.default = '0';

		o = s.taboption('device', form.Value, 'pppoe_user', _('اسم مستخدم PAP/CHAP'));
		o.depends('mode', 'pppoe');

		o = s.taboption('device', form.Value, 'pppoe_pass', _('كلمة سر PAP/CHAP'));
		o.password = true;
		o.depends('mode', 'pppoe');

		o = s.taboption('device', form.ListValue, 'pppoe_port', _('منفذ البرودباند'));
		o.value('wan', 'wan');
		o.depends('mode', 'pppoe');

		o = s.taboption('security', form.Flag, 'reset_lock', _('إيقاف زر الفورمات'));
		o.default = '0';

		o = s.taboption('security', form.Flag, 'reset_custom', _('تخصيص طريقة الفورمات'));
		o.default = '0';

		o = s.taboption('security', form.Value, 'reset_seconds', _('مدة الضغط للفورمات بالثواني'));
		o.datatype = 'range(5,1000)';
		o.depends('reset_custom', '1');

		o = s.taboption('advanced', form.Flag, 'nat_enabled', _('NAT'));
		o.default = '0';

		o = s.taboption('advanced', form.Flag, 'dhcp_server', _('DHCP Server'));
		o.default = '1';

		o = s.taboption('advanced', form.Flag, 'firewall_enabled', _('جدار الحماية'));
		o.default = '1';

		o = s.taboption('advanced', form.Flag, 'watchcat_enabled', _('إعادة التشغيل التلقائي (WatchCat)'));
		o.default = '0';

		o = s.taboption('advanced', form.Flag, 'broadband_enabled', _('البرودباند'));
		o.default = '0';

		o = s.taboption('advanced', form.Flag, 'fake_mesh', _('FAKE MESH (WDS)'));
		o.default = '0';

		o = s.taboption('advanced', form.DummyValue, 'txpower_locked', _('طاقة البث'));
		o.rawhtml = false;
		o.cfgvalue = function() {
			var p0 = uci.get('wireless', 'radio0', 'txpower') || '38';
			var p1 = uci.get('wireless', 'radio1', 'txpower') || '38';
			return '2.4G=' + p0 + ' dBm / 5G=' + p1 + ' dBm';
		};

		return m.render();
	}
});
