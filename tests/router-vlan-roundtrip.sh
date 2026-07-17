#!/bin/sh
# Destructive runtime test: AP -> AP+VLAN -> AP, with exact config restoration.

set -eu

APPLY=/usr/sbin/cr6608-quicksettings-apply
SAFE=/usr/sbin/cr6608-safe-apply
DASH=/www/cgi-bin/dashctl
REQUEST=/tmp/cr6608-vlan-roundtrip.$$.json
BACKUP=/tmp/cr6608-vlan-roundtrip.$$.tar
DASH_RESPONSE=/tmp/cr6608-vlan-roundtrip.$$.dash
NFT_STATE=/tmp/cr6608-vlan-roundtrip.$$.nft
BACKUP_HASHES=/tmp/cr6608-vlan-roundtrip.$$.sha256
CONFIGS='network wireless dhcp firewall cr6608quick smartap'
RESTORE_FILES='etc/config/network etc/config/wireless etc/config/dhcp etc/config/firewall etc/config/cr6608quick etc/config/smartap etc/rc.button/reset etc/rc.button/reset.smartap-orig etc/passwd etc/shadow'
RESTORED=0
SESSION_ID=''
RESET_EXISTED=0
RESET_ORIG_EXISTED=0
OLD_FIREWALL_ENABLED=0
OLD_SECURITY_ENABLED=0
RESTORE_FAILED=0

restore_try() {
	"$@" >/dev/null 2>&1 || RESTORE_FAILED=1
}

restore_original() {
	[ "$RESTORED" = 0 ] || return 0
	RESTORED=1
	for config in $CONFIGS; do uci -q revert "$config" >/dev/null 2>&1 || RESTORE_FAILED=1; done
	restore_try tar -C / -xf "$BACKUP"
	if [ "$RESET_EXISTED" = 1 ]; then [ -e /etc/rc.button/reset ] || RESTORE_FAILED=1; else rm -f /etc/rc.button/reset || RESTORE_FAILED=1; fi
	if [ "$RESET_ORIG_EXISTED" = 1 ]; then [ -e /etc/rc.button/reset.smartap-orig ] || RESTORE_FAILED=1; else rm -f /etc/rc.button/reset.smartap-orig || RESTORE_FAILED=1; fi
	restore_try /etc/init.d/network reload
	restore_try wifi reload
	restore_try /etc/init.d/dnsmasq restart
	if [ "$OLD_SECURITY_ENABLED" = 1 ]; then
		restore_try /etc/init.d/cr6608-security enable
		restore_try /usr/sbin/cr6608-security-apply boot
	else
		restore_try /etc/init.d/cr6608-security disable
		restore_try /usr/sbin/cr6608-security-apply clear-runtime
	fi
	if [ "$OLD_FIREWALL_ENABLED" = 1 ]; then
		restore_try /etc/init.d/firewall enable
		restore_try /etc/init.d/firewall start
		restore_try /etc/init.d/firewall reload
	else
		restore_try /etc/init.d/firewall disable
		restore_try /etc/init.d/firewall stop
	fi
	if /etc/init.d/cr6608-security enabled >/dev/null 2>&1; then restored_security=1; else restored_security=0; fi
	if /etc/init.d/firewall enabled >/dev/null 2>&1; then restored_firewall=1; else restored_firewall=0; fi
	[ "$restored_security" = "$OLD_SECURITY_ENABLED" ] || RESTORE_FAILED=1
	[ "$restored_firewall" = "$OLD_FIREWALL_ENABLED" ] || RESTORE_FAILED=1
	if [ "$OLD_SECURITY_ENABLED" = 0 ] && nft list table bridge smartap_guard >/dev/null 2>&1; then RESTORE_FAILED=1; fi
	sha256sum -c "$BACKUP_HASHES" >/dev/null 2>&1 || RESTORE_FAILED=1
	[ -z "$SESSION_ID" ] || rm -f "/tmp/dashsess/$SESSION_ID"
	rm -f "$REQUEST" "$BACKUP" "$DASH_RESPONSE" "$NFT_STATE" "$BACKUP_HASHES"
	[ "$RESTORE_FAILED" = 0 ]
}
trap restore_original EXIT INT TERM

[ -e /etc/rc.button/reset ] && RESET_EXISTED=1
[ -e /etc/rc.button/reset.smartap-orig ] && RESET_ORIG_EXISTED=1
/etc/init.d/firewall enabled >/dev/null 2>&1 && OLD_FIREWALL_ENABLED=1
/etc/init.d/cr6608-security enabled >/dev/null 2>&1 && OLD_SECURITY_ENABLED=1
set --
 : >"$BACKUP_HASHES"
for restore_file in $RESTORE_FILES; do
	if [ -e "/$restore_file" ]; then
		set -- "$@" "$restore_file"
		sha256sum "/$restore_file" >>"$BACKUP_HASHES"
	fi
done
tar -C / -cf "$BACKUP" "$@"

write_request() {
	mode="$1"
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
  "security": "open",
  "txpower_radio0": "38",
  "txpower_radio1": "38",
  "radio0_enabled": "1",
  "radio1_enabled": "1",
  "clear_previous": "1"
}
EOF
	chmod 0600 "$REQUEST"
}

confirm_pending() {
	status="$($SAFE status)"
	token="$(printf '%s\n' "$status" | sed -n 's/^token=//p')"
	[ "$(printf '%s\n' "$status" | sed -n 's/^state=//p')" = armed ]
	[ "${#token}" -eq 32 ]
	$SAFE confirm "$token"
}

create_dash_session() {
	mkdir -p /tmp/dashsess
	chmod 0700 /tmp/dashsess
	SESSION_ID="$(hexdump -v -n 16 -e '1/1 "%02x"' /dev/urandom)"
	[ "${#SESSION_ID}" -eq 32 ]
	printf '%s %s\n' "$(date +%s)" "$(cut -d. -f1 /proc/uptime)" >"/tmp/dashsess/$SESSION_ID"
	chmod 0600 "/tmp/dashsess/$SESSION_ID"
}

dash_post() {
	body="$1"
	printf '%s' "$body" | env \
		REQUEST_METHOD=POST \
		CONTENT_TYPE=application/x-www-form-urlencoded \
		CONTENT_LENGTH="${#body}" \
		HTTP_COOKIE="cr6608_sid=$SESSION_ID" \
		"$DASH" >"$DASH_RESPONSE"
	grep -Fq '"ok":true' "$DASH_RESPONSE" || {
		cat "$DASH_RESPONSE" >&2
		return 1
	}
}

dash_apply_mode() {
	mode="$1"
	country0="$(uci -q get wireless.radio0.country 2>/dev/null | tr a-z A-Z)"
	country1="$(uci -q get wireless.radio1.country 2>/dev/null | tr a-z A-Z)"
	case "$country0" in ??) : ;; *) country0=PA ;; esac
	case "$country1" in ??) : ;; *) country1=PA ;; esac
	dash_post "section=royal&action=apply_royal&program_mode=$mode&device_ip=192.168.1.1&vlan_id=100&ssid=SmartAP-Test&ch24=11&ch5=36&country24=$country0&country5=$country1&htmode24=HE20&htmode5=HE80&security=open&hide_ssid=0&delete_previous=1&reset_button_enabled=1&reset_mode=factory&firewall_enabled=1&radio0_enabled=1&radio1_enabled=1&txpower_radio0=38&txpower_radio1=38&txpower=38"
}

expect_eq() {
	label="$1"
	actual="$2"
	expected="$3"
	if [ "$actual" != "$expected" ]; then
		printf 'check_failed=%s actual=%s expected=%s\n' "$label" "$actual" "$expected" >&2
		return 1
	fi
}

expect_nft_iface() {
	iface="$1"
	nft list table inet fw4 >"$NFT_STATE"
	grep -Ei "iifname.*\"${iface}\".*comment.*lan" "$NFT_STATE" || {
		printf 'check_failed=fw4_missing_interface iface=%s\n' "$iface" >&2
		grep -E 'iifname|oifname' "$NFT_STATE" >&2 || true
		return 1
	}
}

write_request ap_vlan
CR6608_QUICK_REQUEST_FILE="$REQUEST" "$APPLY" apply
sleep 12
uci -q show network | grep -E 'vlan_filtering|SmartAP-pv|\.ports='
uci -q show wireless | grep -E '^wireless\.wifinet[01]\.network='
expect_eq mode "$(uci -q get cr6608quick.default.mode)" ap_vlan
expect_eq lan_device "$(uci -q get network.lan.device)" br-lan.1
expect_eq radio0_network "$(uci -q get wireless.wifinet0.network)" cr6608_vlan
expect_eq radio1_network "$(uci -q get wireless.wifinet1.network)" cr6608_vlan
expect_nft_iface br-lan.1
echo actual_fw4_vlan_device=pass
for port in lan1 lan2 lan3; do
	uci -q show network | grep -F "name='SmartAP-pv-mgmt'" >/dev/null || exit 1
	uci -q show network | grep -Eq "(=| )'${port}:u\\*'($| )" || {
		printf 'check_failed=missing_untagged_management port=%s\n' "$port" >&2
		exit 1
	}
	uci -q show network | grep -Eq "(=| )'${port}:t'($| )" || {
		printf 'check_failed=missing_vlan_trunk port=%s\n' "$port" >&2
		exit 1
	}
done
! uci -q show network | grep -Eq "(=| )'wan(:[^']*)?'($| )"
bridge vlan show
confirm_pending
echo actual_ap_vlan_100=pass

write_request ap
CR6608_QUICK_REQUEST_FILE="$REQUEST" "$APPLY" apply
sleep 12
expect_eq restored_mode "$(uci -q get cr6608quick.default.mode)" ap
expect_eq restored_lan_device "$(uci -q get network.lan.device)" br-lan
expect_eq restored_radio0_network "$(uci -q get wireless.wifinet0.network)" lan
expect_eq restored_radio1_network "$(uci -q get wireless.wifinet1.network)" lan
expect_nft_iface br-lan
! grep -Fq '"br-lan.1"' "$NFT_STATE"
echo actual_fw4_plain_device=pass
! uci -q show network | grep -q "SmartAP-pv-"
confirm_pending
echo actual_ap_restore=pass

# Exercise the authenticated Smart AP writers too. This catches ordering bugs
# that cannot be seen by testing only the shared quick-settings executor.
create_dash_session
dash_apply_mode ap_vlan
sleep 12
expect_eq dash_mode "$(uci -q get cr6608quick.default.mode)" ap_vlan
expect_eq dash_lan_device "$(uci -q get network.lan.device)" br-lan.1
expect_eq dash_radio0_network "$(uci -q get wireless.wifinet0.network)" cr6608_vlan
expect_eq dash_radio1_network "$(uci -q get wireless.wifinet1.network)" cr6608_vlan
expect_nft_iface br-lan.1
confirm_pending
echo actual_dash_ap_vlan_100=pass

dash_post 'section=security&action=apply_isolation&sec_enabled=1&flood_guard=1&rogue_dhcp_guard=1&loop_guard=1&iso_wifi24=0&iso_wifi5=0&lan1_enabled=1&lan1_isolate=0&lan1_vlan=100&lan1_vlan_mode=trunk&lan2_enabled=1&lan2_isolate=0&lan2_vlan=100&lan2_vlan_mode=trunk&lan3_enabled=1&lan3_isolate=0&lan3_vlan=100&lan3_vlan_mode=trunk'
sleep 8
for port in lan1 lan2 lan3; do
	expect_eq "dash_${port}_mode" "$(uci -q get smartap.$port.vlan_mode)" trunk
	uci -q show network | grep -Eq "(=| )'${port}:t'($| )"
done
expect_nft_iface br-lan.1
echo actual_fw4_isolation_device=pass
confirm_pending
echo actual_dash_isolation=pass

dash_apply_mode ap
sleep 12
expect_eq dash_restored_mode "$(uci -q get cr6608quick.default.mode)" ap
expect_eq dash_restored_lan_device "$(uci -q get network.lan.device)" br-lan
expect_eq dash_restored_radio0_network "$(uci -q get wireless.wifinet0.network)" lan
expect_eq dash_restored_radio1_network "$(uci -q get wireless.wifinet1.network)" lan
expect_nft_iface br-lan
! grep -Fq '"br-lan.1"' "$NFT_STATE"
confirm_pending
echo actual_dash_ap_restore=pass

restore_original || { printf 'exact_config_restore=fail\n' >&2; exit 1; }
trap - EXIT INT TERM
echo exact_config_restore=pass
