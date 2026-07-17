#!/bin/sh
# Run on a CR6608. Every mode must validate and leave persistent UCI unchanged.

set -eu

APPLY=/usr/sbin/cr6608-quicksettings-apply
REQUEST=/tmp/cr6608-quicksettings-runtime-test.$$.json
BEFORE=/tmp/cr6608-quicksettings-runtime-test.$$.before
AFTER=/tmp/cr6608-quicksettings-runtime-test.$$.after

cleanup() {
	rm -f "$REQUEST" "$BEFORE" "$AFTER"
}
trap cleanup EXIT INT TERM

[ -x "$APPLY" ] || {
	echo "quick-settings executor is missing" >&2
	exit 1
}

config_digest() {
	find /etc/config -maxdepth 1 -type f -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum
}

config_digest > "$BEFORE"
[ -z "$(uci changes 2>/dev/null)" ] || {
	echo "pre-existing UCI changes prevent an isolated test" >&2
	exit 1
}

for mode in ap ap_vlan mesh mesh_vlan wds_sender wds_sender_vlan \
	wds_receiver wds_receiver_vlan pppoe; do
	cat > "$REQUEST" <<EOF
{
  "mode": "$mode",
  "lan_ipaddr": "192.168.1.1",
  "lan_netmask": "255.255.255.0",
  "vlan_id": "100",
  "ssid": "Smart ap 2.4G",
  "ssid5": "Smart ap 5G",
  "channel24": "11",
  "channel5": "36",
  "country24": "PA",
  "country5": "PA",
  "htmode24": "HE20",
  "htmode5": "HE80",
  "mesh_id": "CR6608-Mesh-Test",
  "mesh_role": "sender",
  "wds_ssid": "CR6608-WDS-Test",
  "security": "open",
  "pppoe_user": "runtime-test",
  "pppoe_pass": "runtime-test",
  "pppoe_port": "wan",
  "txpower_radio0": "38",
  "txpower_radio1": "38",
  "radio0_enabled": "1",
  "radio1_enabled": "1",
  "clear_previous": "1"
}
EOF
	chmod 0600 "$REQUEST"
	CR6608_DRY_RUN=1 CR6608_QUICK_REQUEST_FILE="$REQUEST" "$APPLY" apply
	[ -z "$(uci changes 2>/dev/null)" ] || {
		echo "$mode left pending UCI changes" >&2
		exit 1
	}
	config_digest > "$AFTER"
	cmp -s "$BEFORE" "$AFTER" || {
		echo "$mode changed persistent UCI during dry-run" >&2
		diff -u "$BEFORE" "$AFTER" >&2 || true
		exit 1
	}
	printf 'quicksettings_mode_%s=pass\n' "$mode"
done

echo 'router_quicksettings_dryrun=pass'
