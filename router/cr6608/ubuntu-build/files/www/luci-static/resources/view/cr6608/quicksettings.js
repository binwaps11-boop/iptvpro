'use strict';
'require view';
'require uci';
'require form';
'require fs';
'require ui';
'require rpc';

return view.extend({
	callFrequencyList: rpc.declare({
		object: 'iwinfo',
		method: 'freqlist',
		params: [ 'device' ],
		expect: { results: [] }
	}),

	callCountryList: rpc.declare({
		object: 'iwinfo',
		method: 'countrylist',
		params: [ 'device' ],
		expect: { results: [] }
	}),

	callWirelessInfo: rpc.declare({
		object: 'iwinfo',
		method: 'info',
		params: [ 'device' ],
		expect: {}
	}),

	callTxPowerList: rpc.declare({
		object: 'iwinfo',
		method: 'txpowerlist',
		params: [ 'device' ],
		expect: { results: [] }
	}),

	callWirelessStatus: rpc.declare({
		object: 'network.wireless',
		method: 'status',
		expect: {}
	}),

	// Save & Apply must REALLY apply. LuCI's handleSave only STAGES cr6608quick in the
	// rpcd session (that is the "UNSAVED CHANGES: 6" the user saw) — the CLI executor
	// then reads stale on-disk values. So instead: read the form values the user just
	// entered and POST them to /cgi-bin/cr6608-quick-apply, which writes cr6608quick to
	// disk and runs the executor (real uci set -> commit -> network/wifi reload),
	// returning a real ok/fail. Then drop LuCI's stale change cache so no ghost
	// "unsaved changes" remains.
	FIELDS: ['mode','mesh_role','lan_ipaddr','lan_netmask','vlan_id','ssid','ssid5','channel24',
		'channel5','country24','country5','htmode24','htmode5','radio0_enabled',
		'radio1_enabled','txpower_radio0','txpower_radio1','txpower','mesh_id',
		'wds_ssid','hide_ssid','security','wifi_key','change_password',
		'clear_previous','pppoe_user','pppoe_pass','pppoe_port','reset_lock',
		'reset_custom','reset_seconds','nat_enabled','dhcp_server','firewall_enabled',
		'watchcat_enabled','broadband_enabled','fake_mesh'],
	handleSaveApply: function(ev, mode) {
		var self = this;
		var adminPassword = self.adminPasswordOption ? self.adminPasswordOption.formvalue('default') : '';
		// this.handleSave flushes the form widgets into the in-memory uci session, so
		// uci.get returns exactly what the user typed (no disk round-trip needed).
		return this.handleSave(ev).then(function() {
			var payload = {};
			self.FIELDS.forEach(function(k) {
				var v = uci.get('cr6608quick', 'default', k);
				if (v !== null && v !== undefined) payload[k] = String(v);
			});
			if (payload.change_password === '1' && adminPassword)
				payload.admin_password = String(adminPassword);
			if (payload.mode === 'mesh' || payload.mode === 'mesh_vlan')
				payload.radio1_enabled = '1';
			// pass the live LuCI ubus session id explicitly so the CGI can authenticate
			// even if cookie parsing is unreliable behind the browser.
			try { payload.luci_sid = rpc.getSessionID(); } catch (e) {}
			return fetch('/cgi-bin/cr6608-quick-apply', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(payload),
				credentials: 'same-origin',
				cache: 'no-store'
			}).then(function(r) {
				return r.json().catch(function() {
					return { ok:false, code:'invalid_response', detail:'The router returned an invalid response.' };
				}).then(function(j) {
					if (r.status === 401 || r.status === 403) {
						window.location.href = '/cgi-bin/luci/';
						throw new Error(_('Your session expired. Sign in again.'));
					}
					if (!r.ok && (!j || j.ok !== false))
						return { ok:false, code:String(r.status), detail:r.statusText || 'Apply failed' };
					return j;
				});
			});
		}).then(function(j) {
			if (!j || !j.ok || !j.pending_confirmation)
				return j;
			self.showReachabilityConfirmation(j);
			return { deferred: true };
		}).then(function(j) {
			if (j && j.deferred) return;
			if (j && j.ok)
				ui.addNotification(null, E('p', _('تم الحفظ والتطبيق الفعلي على الشبكة والواي فاي.')), 'info');
			else
				ui.addNotification(null, E('p', _('حُفظ الإعداد لكن التطبيق أرجع خطأ: ') + ((j && (j.detail || j.code)) || '?')), 'warning');
			window.setTimeout(function() { window.location.reload(); }, 1800);
		}).catch(function(e) {
			ui.addNotification(null, E('p', _('تعذّر إرسال التطبيق: ') + e), 'error');
		});
	},

	showReachabilityConfirmation: function(result) {
		var remaining = 120;
		var counter = E('strong', {}, String(remaining));
		var token = String((result && result.rollback_token) || '');
		var targetIp = String((result && result.management_ip) || '');
		var timer = window.setInterval(function() {
			remaining -= 1;
			counter.textContent = String(Math.max(0, remaining));
			if (remaining <= 0) {
				window.clearInterval(timer);
				ui.hideModal();
				window.setTimeout(function() { window.location.reload(); }, 2500);
			}
		}, 1000);
		var keep = function() {
			var payload = { token: token };
			try { payload.luci_sid = rpc.getSessionID(); } catch (e) {}
			return fetch('/cgi-bin/cr6608-quick-confirm', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(payload),
				credentials: 'same-origin',
				cache: 'no-store'
			}).then(function(r) {
				return r.json().catch(function() {
					return { ok:false, error:'invalid_response' };
				}).then(function(c) {
					if (r.status === 401 || r.status === 403) {
						window.location.href = '/cgi-bin/luci/';
						throw new Error(_('Your session expired. Sign in again.'));
					}
					if (!r.ok && (!c || c.ok !== false))
						throw new Error(r.statusText || 'Confirmation failed');
					return c;
				});
			}).then(function(c) {
				if (!c || !c.ok) throw new Error('The guarded transaction did not match.');
				window.clearInterval(timer);
				ui.hideModal();
				if (/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.test(targetIp) && targetIp !== window.location.hostname) {
					var port = window.location.port ? ':' + window.location.port : '';
					window.location.href = window.location.protocol + '//' + targetIp + port +
						window.location.pathname + window.location.search + window.location.hash;
				}
				else
					window.location.reload();
			}).catch(function(e) {
				ui.addNotification(null, E('p', _('فشل تأكيد الوصول، وسيبقى الرجوع التلقائي مفعلاً: ') + e), 'error');
			});
		};
		ui.showModal(_('Safe Apply'), [
			E('p', {}, _('اختبر الاتصال والقناة وVLAN الآن. لا يتم تثبيت التغيير تلقائياً.')),
			E('p', {}, [ _('الرجوع التلقائي بعد '), counter, _(' ثانية إذا لم تضغط احتفظ بالتغييرات.') ]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', click: function() { window.clearInterval(timer); ui.hideModal(); window.location.reload(); } }, _('اترك الحماية مفعلة')),
				E('button', { 'class': 'btn cbi-button-positive', click: keep }, _('احتفظ بالتغييرات'))
			])
		]);
	},

	load: function() {
		var self = this;
		return Promise.all([
			uci.load('cr6608quick'),
			uci.load('network'),
			uci.load('wireless'),
			uci.load('dhcp'),
			uci.load('firewall'),
			this.callFrequencyList('radio0').catch(function() { return []; }),
			this.callFrequencyList('radio1').catch(function() { return []; }),
			this.callCountryList('radio0').catch(function() { return []; }),
			this.callCountryList('radio1').catch(function() { return []; }),
			this.callWirelessInfo('radio0').catch(function() { return {}; }),
			this.callWirelessInfo('radio1').catch(function() { return {}; }),
			this.callTxPowerList('radio0').catch(function() { return []; }),
			this.callTxPowerList('radio1').catch(function() { return []; }),
			this.callWirelessStatus().catch(function() { return {}; })
		]).then(function(data) {
			self.frequencyLists = { radio0: data[5] || [], radio1: data[6] || [] };
			self.countryLists = { radio0: data[7] || [], radio1: data[8] || [] };
			self.runtimeInfo = { radio0: data[9] || {}, radio1: data[10] || {} };
			self.txPowerLists = { radio0: data[11] || [], radio1: data[12] || [] };
			self.networkWirelessStatus = data[13] || {};
			return data.slice(0, 5);
		});
	},

	render: function() {
		var m, s, o;
		var live = function(section, option, fallback) {
			var value = uci.get('wireless', section, option);
			return value !== null && value !== undefined && value !== '' ? String(value) : fallback;
		};
		var liveEnabled = function(section) {
			return live(section, 'disabled', '0') === '1' ? '0' : '1';
		};
		var finiteNumber = function(value) {
			if (value === null || value === undefined || String(value).trim() === '')
				return Number.NaN;
			var number = Number(value);
			return Number.isFinite(number) ? number : Number.NaN;
		};
		var runtimePowerSummary = function(radio) {
			var requested = finiteNumber(live(radio, 'txpower', ''));
			var info = (this.runtimeInfo && this.runtimeInfo[radio]) || {};
			var netifd = (this.networkWirelessStatus && this.networkWirelessStatus[radio]) || {};
			var applied = finiteNumber(info.txpower);
			var powerRows = (this.txPowerLists && this.txPowerLists[radio]) || [];
			var driverMaximum = powerRows.reduce(function(max, row) {
				var value = finiteNumber(row.dbm);
				return Number.isFinite(value) && value > max ? value : max;
			}, Number.NEGATIVE_INFINITY);
			var channel = live(radio, 'channel', '');
			var frequencyRows = (this.frequencyLists && this.frequencyLists[radio]) || [];
			var channelRow = frequencyRows.find(function(row) {
				return String(row.channel) === String(channel);
			}) || {};
			var channelMaximum = finiteNumber(channelRow.max_txpower);
			if (!Number.isFinite(channelMaximum))
				channelMaximum = finiteNumber(channelRow.max_power);
			if (!Number.isFinite(channelMaximum))
				channelMaximum = finiteNumber(channelRow.txpower);
			var requestedText = Number.isFinite(requested) ? requested + ' dBm' : '-';
			var channelText = Number.isFinite(channelMaximum) ? channelMaximum + ' dBm' : '-';
			var disabled = live(radio, 'disabled', '0') === '1' || netifd.disabled === true;
			var status = disabled ? 'disabled' : (!Number.isFinite(applied) ?
				(netifd.up === true ? 'starting' : 'down') :
				(Number.isFinite(requested) && applied < requested ? 'limited' : 'accepted'));
			var reason = disabled ? 'disabled by configuration' :
				(status === 'down' ? 'netifd/hostapd did not create a runtime interface' :
				(status === 'starting' ? 'runtime power read-back is not available yet' :
				(status === 'limited' && Number.isFinite(channelMaximum) && channelMaximum < requested ?
				'channel/kernel limit' : (status === 'limited' ? 'driver/firmware/calibration limit' : ''))));
			var summary = 'Requested=' + requestedText + ' / Regulatory+channel max=' + channelText;
			if (Number.isFinite(driverMaximum))
				summary += ' / Driver max=' + driverMaximum + ' dBm';
			if (Number.isFinite(applied))
				summary += ' / Current=' + applied + ' dBm';
			return summary + ' / Status=' + status + (reason ? ' (' + reason + ')' : '');
		}.bind(this);
		var addCountries = function(option, rows, current) {
			var seen = {};
			(rows || []).slice().sort(function(a, b) {
				return String(a.code || '').localeCompare(String(b.code || ''));
			}).forEach(function(row) {
				var code = String(row.iso3166 || row.code || '').toUpperCase();
				if (!/^[A-Z0-9]{2}$/.test(code) || seen[code]) return;
				seen[code] = true;
				option.value(code, code + (row.country ? ' - ' + row.country : ''));
			});
			current = String(current || '').toUpperCase();
			if (/^[A-Z0-9]{2}$/.test(current) && !seen[current]) option.value(current, current);
		};
		var addChannels = function(option, rows, band, current) {
			var seen = {}, disabled = [];
			option.value('auto', _('Automatic'));
			(rows || []).slice().sort(function(a, b) {
				return (+a.channel || 0) - (+b.channel || 0);
			}).forEach(function(row) {
				var channel = +row.channel, mhz = +row.mhz;
				if (!Number.isInteger(channel) || channel < 1) return;
				if (band === 2 && (channel < 1 || channel > 13)) return;
				if (band === 5 && channel < 30) return;
				if (seen[channel]) return;
				seen[channel] = true;
				var flags = Array.isArray(row.flags) ? row.flags : [];
				var blocked = row.restricted === true || row.disabled === true || row.disabled === 1 ||
					String(row.disabled || '').toLowerCase() === 'true' || flags.indexOf('disabled') !== -1;
				var dfs = band === 5 && ((channel >= 52 && channel <= 144) || flags.indexOf('radar') !== -1);
				var label = String(channel) + ' | ' + (mhz || '?') + ' MHz | ' +
					(band === 2 ? '2.4 GHz' : '5 GHz') + ' | ' +
					(dfs ? 'DFS' : 'non-DFS') + ' | ' + (blocked ? 'Disabled' : 'Enabled');
				if (blocked) disabled.push(label);
				else option.value(String(channel), label);
			});
			current = String(current || '');
			if (current !== 'auto' && /^\d+$/.test(current) && !seen[+current])
				disabled.push(current + ' | unavailable for the current country | Disabled');
			return disabled;
		};

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

		o = s.taboption('device', form.ListValue, 'mesh_role', _('Mesh role'));
		o.value('sender', _('Sender'));
		o.value('receiver', _('Receiver'));
		o.default = 'sender';
		o.depends('mode', 'mesh');
		o.depends('mode', 'mesh_vlan');

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
		o.cfgvalue = function() {
			return live('wifinet0', 'ssid', uci.get('cr6608quick', 'default', 'ssid'));
		};

		o = s.taboption('device', form.Value, 'ssid5', _('اسم بث 5G'));
		o.datatype = 'maxlength(32)';
		o.placeholder = 'Smart-AP-5G';
		o.cfgvalue = function() {
			return live('wifinet1', 'ssid', uci.get('cr6608quick', 'default', 'ssid5'));
		};

		o = s.taboption('device', form.ListValue, 'country24', _('Country 2.4G'));
		addCountries(o, (this.countryLists || {}).radio0, uci.get('wireless', 'radio0', 'country') || 'US');
		o.rmempty = false;
		o.cfgvalue = function() { return live('radio0', 'country', 'US'); };
		o.description = _('All countries reported by the driver are accepted and persist after reboot. When changing country, select Automatic channel for this apply, then choose from the refreshed live list.');

		o = s.taboption('device', form.ListValue, 'country5', _('Country 5G'));
		addCountries(o, (this.countryLists || {}).radio1, uci.get('wireless', 'radio1', 'country') || 'US');
		o.rmempty = false;
		o.cfgvalue = function() { return live('radio1', 'country', 'US'); };
		o.description = _('When changing country, select Automatic channel for this apply. The page reload then reads that country\'s live channel availability.');

		o = s.taboption('device', form.ListValue, 'htmode24', _('2.4G width'));
		o.value('HE20', 'HE20');
		o.value('HE40', 'HE40');
		o.value('HT20', 'HT20');
		o.value('HT40', 'HT40');
		o.cfgvalue = function() { return live('radio0', 'htmode', 'HE20'); };

		o = s.taboption('device', form.ListValue, 'htmode5', _('5G width'));
		o.value('HE80', 'HE80');
		o.value('HE40', 'HE40');
		o.value('HE20', 'HE20');
		o.value('VHT80', 'VHT80');
		o.value('VHT40', 'VHT40');
		o.value('HT20', 'HT20');
		o.cfgvalue = function() { return live('radio1', 'htmode', 'HE80'); };

		o = s.taboption('device', form.Flag, 'radio0_enabled', _('Enable 2.4G radio'));
		o.default = '1';
		o.cfgvalue = function() { return liveEnabled('radio0'); };

		o = s.taboption('device', form.Flag, 'radio1_enabled', _('Enable 5G radio'));
		o.default = '1';
		o.cfgvalue = function() { return liveEnabled('radio1'); };

		o = s.taboption('device', form.ListValue, 'channel24', _('قناة 2.4G'));
		addChannels(o, (this.frequencyLists || {}).radio0, 2,
			uci.get('wireless', 'radio0', 'channel') || 'auto');
		o.cfgvalue = function() { return live('radio0', 'channel', 'auto'); };
		o.description = _('Channels 1-13 are offered only when iwinfo reports them enabled for the active country.');

		o = s.taboption('device', form.ListValue, 'channel5', _('قناة 5G'));
		var disabled5 = addChannels(o, (this.frequencyLists || {}).radio1, 5,
			uci.get('wireless', 'radio1', 'channel') || 'auto');
		o.cfgvalue = function() { return live('radio1', 'channel', 'auto'); };
		o.description = _('DFS channels remain visible and labelled. Disabled channels are reported below and cannot be selected.');

		o = s.taboption('device', form.DummyValue, '_channel5_disabled', _('Restricted 5G channels reported by driver'));
		o.cfgvalue = function() {
			return disabled5.length ? disabled5.join('; ') : _('None exposed by iwinfo. Omitted or disabled channels are never selectable.');
		};

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

		o = s.taboption('device', form.Value, '_admin_password', _('كلمة مرور الجهاز الجديدة'));
		o.password = true;
		o.depends('change_password', '1');
		o.cfgvalue = function() { return ''; };
		o.write = function() {};
		o.remove = function() {};
		this.adminPasswordOption = o;

		o = s.taboption('device', form.Flag, 'clear_previous', _('حذف إعدادات البرمجة السابقة'));
		o.default = '1';
		o.readonly = true;
		o.default = '0';

		o = s.taboption('device', form.Value, 'pppoe_user', _('اسم مستخدم PAP/CHAP'));
		o.depends('mode', 'pppoe');

		o = s.taboption('device', form.Value, 'pppoe_pass', _('كلمة سر PAP/CHAP'));
		o.password = true;
		o.depends('mode', 'pppoe');

		o = s.taboption('device', form.ListValue, 'pppoe_port', _('منفذ البرودباند'));
		o.value('wan', 'wan');
		o.readonly = true;
		o.description = _('WAN is reserved for PPPoE. LAN1-LAN3 remain available for switch and VLAN use.');
		o.depends('mode', 'pppoe');

		o = s.taboption('security', form.Flag, 'reset_lock', _('إيقاف زر الفورمات'));
		o.default = '0';

		o = s.taboption('security', form.Flag, 'reset_custom', _('تخصيص طريقة الفورمات'));
		o.default = '0';

		o = s.taboption('security', form.Value, 'reset_seconds', _('مدة الضغط للفورمات بالثواني'));
		o.datatype = 'range(5,1000)';
		o.depends('reset_custom', '1');

		o = s.taboption('advanced', form.Flag, 'nat_enabled', _('NAT'));
		o.default = '1';
		o.description = _('Enabled automatically in PPPoE mode.');

		o = s.taboption('advanced', form.Flag, 'dhcp_server', _('DHCP Server'));
		o.default = '0';
		o.description = _('Off in AP/VLAN/Mesh/WDS modes; enabled automatically in PPPoE mode.');

		o = s.taboption('advanced', form.Flag, 'firewall_enabled', _('جدار الحماية'));
		o.default = '1';

		o = s.taboption('advanced', form.Flag, 'broadband_enabled', _('البرودباند'));
		o.default = '0';

		o = s.taboption('advanced', form.Flag, 'fake_mesh', _('FAKE MESH (WDS)'));
		o.default = '0';

		o = s.taboption('advanced', form.DummyValue, 'txpower_locked', _('طاقة البث'));
		o.rawhtml = false;
		o.cfgvalue = function() {
			return '2.4G: ' + runtimePowerSummary('radio0') + ' | 5G: ' + runtimePowerSummary('radio1');
		};

		o = s.taboption('advanced', form.Value, 'txpower_radio0', _('Maximum transmit power 2.4G'));
		o.datatype = 'range(1,38)';
		o.default = '38';
		o.rmempty = false;
		o.description = _('Allowed range is 1-38 dBm. Requested and driver-accepted power are shown separately. Regulatory, channel, calibration, rate, SAR, firmware, or thermal limits may lower the accepted value.');

		o = s.taboption('advanced', form.Value, 'txpower_radio1', _('Maximum transmit power 5G'));
		o.datatype = 'range(1,38)';
		o.default = '38';
		o.rmempty = false;
		o.description = _('Allowed range is 1-38 dBm. Requested and driver-accepted power are shown separately. Regulatory, channel, calibration, rate, SAR, firmware, or thermal limits may lower the accepted value.');

		return m.render();
	}
});
