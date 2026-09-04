#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PATCH_FILE="${LUCI_WIRELESS_PATCH:-${SCRIPT_DIR}/../patches/993-luci-wireless-preserve-configured-txpower.patch}"
NODE_BIN="${NODE_BIN:-node}"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[ -s "$PATCH_FILE" ] || fail "missing LuCI wireless patch: $PATCH_FILE"
PATCH_FILE="$(CDPATH= cd -- "$(dirname -- "$PATCH_FILE")" && pwd)/$(basename -- "$PATCH_FILE")"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v "$NODE_BIN" >/dev/null 2>&1 || fail "Node.js is required"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

relative='modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js'
mkdir -p "$tmp/original/$(dirname "$relative")" "$tmp/patched/$(dirname "$relative")"

# Minimal, exact upstream fixture for the one hunk. The build separately checks
# this patch against the pinned LuCI feed before applying it to the real source.
cat > "$tmp/original/$relative" <<'EOF'
var CBIWifiTxPowerValue = form.ListValue.extend({
	callTxPowerList: rpc.declare({
		object: 'iwinfo',
		method: 'txpowerlist',
		params: [ 'device' ],
		expect: { results: [] }
	}),

	load: function(section_id) {
		return this.callTxPowerList(section_id).then(L.bind(function(pwrlist) {
			this.powerval = this.wifiNetwork ? this.wifiNetwork.getTXPower() : null;
			this.poweroff = this.wifiNetwork ? this.wifiNetwork.getTXPowerOffset() : null;

			this.value('', _('driver default'));

			for (let p of pwrlist)
				this.value(p.dbm, `${p.dbm} dBm (${p.mw} mW)`);

			return form.ListValue.prototype.load.apply(this, [section_id]);
		}, this));
	},

	renderWidget: function(section_id, option_index, cfgvalue) {
		return form.ListValue.prototype.renderWidget.apply(this, [section_id, option_index, cfgvalue]);
	}
});

var CBIWifiCountryValue = form.Value.extend({
	callCountryList: rpc.declare({
		object: 'iwinfo',
		method: 'countrylist',
		params: [ 'device' ],
		expect: { results: [] }
	}),

	load: function(section_id) {
		return this.callCountryList(section_id).then(L.bind(function(countrylist) {
			if (Array.isArray(countrylist) && countrylist.length > 0) {
				this.value('', _('driver default'));

				for (let c of countrylist)
					this.value(c.iso3166, `${c.iso3166} - ${c.country}`);
			}

			return form.Value.prototype.load.apply(this, [section_id]);
		}, this));
	},

	validate: function(section_id, formvalue) {
		if (formvalue != null && formvalue != '' && !/^[A-Z0-9][A-Z0-9]$/.test(formvalue))
			return _('Use ISO/IEC 3166 alpha2 country codes.');

		return true;
	},

	renderWidget: function(section_id, option_index, cfgvalue) {
		const typeClass = (this.keylist && this.keylist.length) ? form.ListValue : form.Value;
		return typeClass.prototype.renderWidget.apply(this, [section_id, option_index, cfgvalue]);
	}
});
EOF

cp "$tmp/original/$relative" "$tmp/patched/$relative"
wireless_patch="$tmp/wireless-only.patch"
awk '/^diff --git a\/applications\/luci-app-usteer\// { exit } { print }' \
	"$PATCH_FILE" > "$wireless_patch"
git -C "$tmp/patched" apply --check "$wireless_patch" || fail "wireless patch does not apply to its upstream fixture"
git -C "$tmp/patched" apply "$wireless_patch" || fail "wireless patch application failed"

"$NODE_BIN" - "$tmp/original/$relative" "$tmp/patched/$relative" <<'EOF'
'use strict';

const fs = require('fs');

if (!String.prototype.format) {
	Object.defineProperty(String.prototype, 'format', {
		configurable: true,
		value: function(...args) {
			let index = 0;
			return this.replace(/%s/g, () => String(args[index++]));
		}
	});
}

const requested = {
	radio0: '38',
	known: '26',
	zero: '0',
	tooHigh: '39',
	exponent: '1e2',
	decimal: '38.0',
	negative: '-1',
	leadingZero: '038',
	invalid: 'not-a-number'
};
const driverList = Array.from({ length: 26 }, (_, index) => ({
	dbm: index + 1,
	mw: Math.round(Math.pow(10, (index + 1) / 10))
}));

function loadClass(path) {
	const source = fs.readFileSync(path, 'utf8');
	const start = source.indexOf('var CBIWifiTxPowerValue = form.ListValue.extend({');
	const end = source.indexOf('\nvar CBIWifiCountryValue', start);
	if (start < 0 || end < 0)
		throw new Error(`unable to extract CBIWifiTxPowerValue from ${path}`);

	function ListValue() {}
	ListValue.extend = definition => definition;
	ListValue.prototype.load = function() { return Promise.resolve(this); };
	ListValue.prototype.renderWidget = function() { return {}; };

	const form = { ListValue };
	const rpc = {
		declare: () => function() { return Promise.resolve(driverList); }
	};
	const L = {
		bind: (fn, context, ...args) => fn.bind(context, ...args)
	};
	const uci = {
		get: (config, section, option) =>
			(config === 'wireless' && option === 'txpower') ? requested[section] : null
	};
	const translate = value => value;
	const element = () => ({});

	return new Function('form', 'rpc', 'L', 'uci', '_', 'E',
		`${source.slice(start, end)}\nreturn CBIWifiTxPowerValue;`)(
			form, rpc, L, uci, translate, element);
}

function loadCountryClass(path, state) {
	const source = fs.readFileSync(path, 'utf8');
	const start = source.indexOf('var CBIWifiCountryValue = form.Value.extend({');
	let end = source.indexOf('\n\nreturn view.extend', start);
	if (end < 0)
		end = source.length;
	if (start < 0)
		throw new Error(`unable to extract CBIWifiCountryValue from ${path}`);

	function ListValue() {}
	ListValue.prototype.renderWidget = function() { return {}; };

	function Value() {}
	Value.extend = definition => definition;
	Value.prototype.load = function() { return Promise.resolve(this); };
	Value.prototype.renderWidget = function() { return {}; };

	const form = { ListValue, Value };
	const rpc = {
		declare: () => function() { return Promise.resolve([]); }
	};
	const L = {
		bind: (fn, context, ...args) => fn.bind(context, ...args)
	};
	const uci = {
		get(config, section, option) {
			if (config !== 'wireless')
				return null;
			const radio = state.radios.find(candidate => candidate['.name'] === section);
			return (radio && radio[option] != null) ? radio[option] : null;
		},
		sections(config, type) {
			return (config === 'wireless' && type === 'wifi-device') ? state.radios : [];
		},
		set(config, section, option, value) {
			const radio = state.radios.find(candidate => candidate['.name'] === section);
			if (!radio)
				throw new Error(`unknown radio ${section}`);
			radio[option] = value;
			state.mutations.push([ 'set', config, section, option, value ]);
		},
		unset(config, section, option) {
			const radio = state.radios.find(candidate => candidate['.name'] === section);
			if (!radio)
				throw new Error(`unknown radio ${section}`);
			delete radio[option];
			state.mutations.push([ 'unset', config, section, option ]);
		}
	};
	const translate = value => value;

	return new Function('form', 'rpc', 'L', 'uci', '_',
		`${source.slice(start, end)}\nreturn CBIWifiCountryValue;`)(
			form, rpc, L, uci, translate);
}

function countryState(country0, channel0, country1, channel1) {
	return {
		radios: [
			{ '.name': 'radio0', country: country0, channel: channel0 },
			{ '.name': 'radio1', country: country1, channel: channel1 }
		],
		mutations: []
	};
}

function newOption(definition) {
	return Object.assign({
		keylist: [],
		vallist: [],
		value(key, label) {
			this.keylist.push(String(key));
			this.vallist.push(String(label));
		},
		wifiNetwork: {
			getTXPower: () => 26,
			getTXPowerOffset: () => 0
		}
	}, definition);
}

function saveRadio0Modal(config, option) {
	// LuCI ListValue can retain only a value present in its select choices.
	const configured = String(config.txpower);
	const formValue = option.keylist.includes(configured) ? configured : '';
	if (formValue === '')
		delete config.txpower;
	else
		config.txpower = formValue;
}

(async () => {
	const originalDefinition = loadClass(process.argv[2]);
	const patchedDefinition = loadClass(process.argv[3]);
	const original = newOption(originalDefinition);
	const patched = newOption(patchedDefinition);

	await original.load('radio0');
	await patched.load('radio0');
	if (patched.powerval !== 26)
		throw new Error(`current power did not preserve the live 26 dBm readback: ${patched.powerval}`);

	const live38 = newOption(patchedDefinition);
	live38.wifiNetwork = {
		getTXPower: () => 38,
		getTXPowerOffset: () => 0
	};
	await live38.load('radio0');
	if (live38.powerval !== 38)
		throw new Error(`current power did not follow the live 38 dBm readback: ${live38.powerval}`);

	const unavailable = newOption(patchedDefinition);
	unavailable.wifiNetwork = {
		getTXPower: () => null,
		getTXPowerOffset: () => null
	};
	await unavailable.load('radio0');
	if (unavailable.powerval !== null)
		throw new Error(`unavailable current power was replaced with a hardcoded value: ${unavailable.powerval}`);

	if (original.keylist.includes('38'))
		throw new Error('pre-patch fixture unexpectedly represents txpower=38');
	if (!patched.keylist.includes('38'))
		throw new Error('patched radio0 modal does not represent configured txpower=38');
	if (patched.keylist.filter(value => value === '38').length !== 1)
		throw new Error('configured txpower choice is duplicated');
	const expectedPowerKeys = [ '', ...Array.from({ length: 38 }, (_, index) => String(index + 1)) ];
	if (patched.keylist.length !== expectedPowerKeys.length ||
	    expectedPowerKeys.some((value, index) => patched.keylist[index] !== value))
		throw new Error(`patched power choices are not the exact 1-38 dBm range: ${patched.keylist.join(',')}`);

	const label = patched.vallist[patched.keylist.indexOf('38')];
	if (label !== '38 dBm')
		throw new Error(`configured request label is not the requested compact form: ${label}`);

	const before = { txpower: '38', country: 'US' };
	const after = { txpower: '38', country: 'PA' };
	saveRadio0Modal(before, original);
	saveRadio0Modal(after, patched);
	if ('txpower' in before)
		throw new Error('pre-patch regression model did not reproduce the deletion');
	if (after.txpower !== '38' || after.country !== 'PA')
		throw new Error('patched radio0 modal did not preserve txpower=38 while saving country');

	const known = newOption(patchedDefinition);
	await known.load('known');
	if (known.keylist.filter(value => value === '26').length !== 1)
		throw new Error('driver-listed configured power was duplicated');
	const knownLabel = known.vallist[known.keylist.indexOf('26')];
	if (knownLabel !== '26 dBm')
		throw new Error(`driver-listed power label is not compact: ${knownLabel}`);

	for (const section of [
		'zero', 'tooHigh', 'exponent', 'decimal', 'negative', 'leadingZero', 'invalid'
	]) {
		const invalid = newOption(patchedDefinition);
		await invalid.load(section);
		if (invalid.keylist.includes(requested[section]))
			throw new Error(`invalid configured power was exposed as a choice: ${requested[section]}`);
	}

	const fixedState = countryState('US', 'auto', 'US', '36');
	const fixedCountry = loadCountryClass(process.argv[3], fixedState);
	const fixedResult = fixedCountry.validate('radio0', 'PA');
	if (fixedResult === true || !/shared by all radios/.test(fixedResult) || !/Automatic/.test(fixedResult))
		throw new Error(`fixed-channel country change was not rejected clearly: ${fixedResult}`);
	if (fixedState.mutations.length !== 0)
		throw new Error('rejected fixed-channel country change mutated UCI');

	const autoState = countryState('US', 'auto', 'US', 'auto');
	const autoCountry = loadCountryClass(process.argv[3], autoState);
	if (autoCountry.validate('radio0', 'PA') !== true)
		throw new Error('all-auto country change was rejected');
	autoCountry.write('radio0', 'PA');
	if (autoState.radios.some(radio => radio.country !== 'PA'))
		throw new Error('native LuCI country write did not synchronize every radio');
	if (autoState.mutations.length !== 2 || autoState.mutations.some(mutation => mutation[0] !== 'set'))
		throw new Error('native LuCI country write did not make exactly one set per radio');

	const removeState = countryState('PA', 'auto', 'PA', 'auto');
	const removeCountry = loadCountryClass(process.argv[3], removeState);
	if (removeCountry.validate('radio1', '') !== true)
		throw new Error('all-auto country reset was rejected');
	removeCountry.remove('radio1');
	if (removeState.radios.some(radio => 'country' in radio))
		throw new Error('native LuCI country reset did not synchronize every radio');
	if (removeState.mutations.length !== 2 || removeState.mutations.some(mutation => mutation[0] !== 'unset'))
		throw new Error('native LuCI country reset did not make exactly one unset per radio');

	const mixedState = countryState('PA', '36', 'US', '149');
	const mixedCountry = loadCountryClass(process.argv[3], mixedState);
	if (mixedCountry.validate('radio0', 'PA') !== true)
		throw new Error('unchanged country was blocked, preventing fixed-channel recovery');
	if (mixedState.mutations.length !== 0)
		throw new Error('unchanged country validation mutated UCI');

	const invalidCountryState = countryState('US', 'auto', 'US', 'auto');
	const invalidCountry = loadCountryClass(process.argv[3], invalidCountryState);
	if (invalidCountry.validate('radio0', 'p@') === true)
		throw new Error('invalid country code was accepted');
	if (invalidCountryState.mutations.length !== 0)
		throw new Error('invalid country validation mutated UCI');

	process.stdout.write('luci_wireless_txpower_preserve=pass\n');
})().catch(error => {
	process.stderr.write(`${error.stack || error}\n`);
	process.exit(1);
});
EOF

# Model the Usteer stopped/empty RPC result which previously threw from
# Object.keys(undefined) on every poll. The complete production patch is also
# checked against the pinned feed during the build.
usteer_relative='applications/luci-app-usteer/htdocs/luci-static/resources/view/usteer/usteer.js'
mkdir -p "$tmp/usteer/$(dirname "$usteer_relative")"
# Preserve the upstream line anchor so git-apply exercises the exact hunk.
fixture_line=1
while [ "$fixture_line" -le 229 ]; do
	printf '\n' >>"$tmp/usteer/$usteer_relative"
	fixture_line=$((fixture_line + 1))
done
cat >>"$tmp/usteer/$usteer_relative" <<'EOF'
const callNetworkRrdnsLookup = rpc.declare({
	object: 'network.rrdns',
	method: 'lookup',
	params: [ 'addrs', 'timeout', 'limit' ],
	expect: { '': {} }
});


function collectRemoteHosts (remotehosttableentries,Remotehosts) {
	const getUndefinedDnsCacheIPs = (Remotehosts, dns_cache) =>
		Object.keys(Remotehosts).filter(IPaddr => !dns_cache.hasOwnProperty(IPaddr));

	const ipAddrs = getUndefinedDnsCacheIPs(Remotehosts, dns_cache);

}
EOF
usteer_patch="$tmp/usteer-only.patch"
awk 'BEGIN { emit=0 } /^diff --git a\/applications\/luci-app-usteer\// { emit=1 } emit { print }' \
	"$PATCH_FILE" | awk '/^@@ -419,/ { exit } { print }' >"$usteer_patch"
git -C "$tmp/usteer" apply --check "$usteer_patch" || fail "Usteer runtime null-guard patch does not apply"
git -C "$tmp/usteer" apply "$usteer_patch" || fail "Usteer runtime null-guard patch application failed"
grep -Fq 'Remotehosts = Remotehosts || {};' "$tmp/usteer/$usteer_relative" ||
	fail 'Usteer remote-host argument is not normalized'
grep -Fq '!Object.prototype.hasOwnProperty.call(dns_cache, IPaddr)' "$tmp/usteer/$usteer_relative" ||
	fail 'Usteer DNS-cache membership check is not null/prototype safe'
"$NODE_BIN" --check "$tmp/usteer/$usteer_relative" >/dev/null || fail 'patched Usteer JavaScript syntax failed'
