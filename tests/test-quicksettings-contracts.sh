#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
EXECUTOR="$ROOT/files/usr/sbin/cr6608-quicksettings-apply"
CGI="$ROOT/files/www/cgi-bin/cr6608-quick-apply"
DASH="$ROOT/files/www/cgi-bin/dashctl"
DASH_JS="$ROOT/files/www/dashboard.js"
SAFE="$ROOT/files/usr/sbin/cr6608-safe-apply"
BOOTSTRAP="$ROOT/files/usr/sbin/smartap-bootstrap"
QUICK_CFG="$ROOT/files/etc/config/cr6608quick"
TX_APPLY="$ROOT/files/usr/sbin/cr6608-force-txpower38"
VLAN_LIB="$ROOT/files/usr/libexec/cr6608-vlan-lib"
QUICK_CGI="$ROOT/files/www/cgi-bin/cr6608-quick-apply"
SECURITY_APPLY="$ROOT/files/usr/sbin/cr6608-security-apply"
SECURITY_HOTPLUG="$ROOT/files/etc/hotplug.d/iface/98-cr6608-security-runtime"
LUCI_QUICK="$ROOT/files/www/luci-static/resources/view/cr6608/quicksettings.js"
NETWORK_CFG="$ROOT/files/etc/config/network"
SESSION_AUTH="$ROOT/files/usr/libexec/cr6608-session-auth"

fail() {
	printf 'quicksettings_contracts=fail: %s\n' "$*" >&2
	exit 1
}

for file in "$EXECUTOR" "$CGI" "$DASH" "$DASH_JS" "$SAFE" "$BOOTSTRAP" "$QUICK_CFG" "$TX_APPLY" "$VLAN_LIB" "$QUICK_CGI" "$SECURITY_APPLY" "$SECURITY_HOTPLUG" "$LUCI_QUICK" "$NETWORK_CFG" "$SESSION_AUTH"; do
	[ -s "$file" ] || fail "missing $file"
done
grep -Fq 'cr6608_path_permissions()' "$SESSION_AUTH" || fail "actual quick apply lacks its secure mode helper"

# Keep official LuCI's checked apply/rollback implementation. Local copies of
# these core files previously converted every checked apply into an unchecked one.
[ ! -e "$ROOT/files/www/luci-static/resources/ui.js" ] || fail "local LuCI ui.js override bypasses Safe Apply"
[ ! -e "$ROOT/files/usr/share/ucode/luci/controller/admin/uci.uc" ] || fail "local LuCI UCI controller bypasses Safe Apply"

# Mode is authoritative. A stale broadband checkbox must never turn an AP
# transition back into PPPoE, DHCP, or NAT.
grep -Fq 'if [ "$mode" = "pppoe" ]; then' "$EXECUTOR" || fail "executor lacks mode-owned PPPoE policy"
grep -Fq "broadband_enabled='0'" "$EXECUTOR" || fail "executor does not clear AP broadband state"
grep -Fq "dhcp_server='0'" "$EXECUTOR" || fail "executor does not clear AP DHCP state"
grep -Fq "nat_enabled='0'" "$EXECUTOR" || fail "executor does not clear AP NAT state"
grep -Fq 'if [ "$program_mode" = "pppoe_ap" ]; then' "$DASH" || fail "Smart AP writer lacks mode-owned PPPoE policy"
grep -Fq 'broadband_enabled="0"' "$DASH" || fail "Smart AP writer does not clear AP broadband state"
grep -Fq 'dhcp_server="0"' "$DASH" || fail "Smart AP writer does not clear AP DHCP state"
grep -Fq 'nat_enabled="0"' "$DASH" || fail "Smart AP writer does not clear AP NAT state"
grep -Fq 'if (field) field.value = pppoe ? "1" : "0";' "$DASH_JS" || fail "dashboard mode synchronizer is missing"

# A mode switch always removes stale VLAN, mesh, WDS, guest, and PPPoE state.
grep -Fq "clear_previous='1'" "$EXECUTOR" || fail "executor cleanup is not mandatory"
grep -Fq "clr='1'" "$CGI" || fail "LuCI CGI cleanup is not mandatory"
grep -Fq 'delete_previous="1"' "$DASH" || fail "Smart AP cleanup is not mandatory"
grep -Fq "option clear_previous '1'" "$QUICK_CFG" || fail "clean-image cleanup default is not enabled"
for artifact in wireless.smartap_guest network.smartap_vdev dhcp.cr6608_vlan; do
	grep -Fq "delete $artifact" "$EXECUTOR" || fail "executor does not remove $artifact"
done

# The chosen management address replaces the previous address and metadata;
# Safe Apply retains only a temporary address on the actual bridge device.
grep -Fq 'uci set "smartap.management.ipaddr=$ip"' "$EXECUTOR" || fail "executor management metadata is stale"
grep -Fq 'royal_set "smartap.management.ipaddr=$device_ip"' "$DASH" || fail "Smart AP management metadata is stale"
grep -Fq 'management_device="$(qget network.lan.device)"' "$EXECUTOR" || fail "executor hard-codes the Safe Apply bridge"
grep -Fq 'current_management_device="$(uci -q get network.lan.device' "$DASH" || fail "Smart AP hard-codes the Safe Apply bridge"
grep -Fq 'network="$(printf' "$EXECUTOR" || fail "executor lacks network-address rejection"
grep -Fq 'broadcast="$(printf' "$CGI" || fail "CGI lacks broadcast-address rejection"
grep -Fq 'valid_management_host "$ipaddr" "$netmask"' "$DASH" || fail "Interfaces page lacks network/broadcast-address rejection"
grep -Fq 'management_ip="$(g network.lan.ipaddr)"' "$BOOTSTRAP" || fail "bootstrap does not preserve the selected management address"
grep -Fq 'ip="$(pick lan_ipaddr ipaddr device_ip)"' "$QUICK_CGI" || fail "CGI does not prefer the explicitly submitted management address"
grep -Fq 'ip="$(qget network.lan.ipaddr)"' "$QUICK_CGI" || fail "CGI can restore stale quick-settings management metadata"

# Old cached clients get an explicit refusal; there is no second configuration
# writer that can silently reintroduce legacy behavior.
[ "$(grep -Fc 'save_quick)' "$DASH")" -eq 1 ] || fail "legacy save_quick handler count is not exactly one"
grep -A1 -F 'save_quick)' "$DASH" | grep -Fq 'Legacy handler retired' || fail "legacy save_quick is still active"
! grep -Fq 'legacy_save_quick_disabled)' "$DASH" || fail "dead legacy handler remains"

# Pending transactions and temporary addresses are single-owner and fail closed.
grep -Fq 'refusing to replace an existing pending rollback transaction' "$SAFE" || fail "Safe Apply allows transaction overwrite"
grep -Fq 'refusing to arm while temporary management address cleanup is pending' "$SAFE" || fail "Safe Apply can lose a temporary-address cleanup marker"

# Channel selection must reject both iwinfo representations of a disabled
# channel, and the TX helper must fail when runtime does not match the target.
for channel_owner in "$EXECUTOR" "$CGI" "$DASH"; do
	grep -Fq '.disabled' "$channel_owner" || fail "disabled channel flag is ignored in $channel_owner"
	grep -Fq '.flags[*]' "$channel_owner" || fail "channel flags are ignored in $channel_owner"
done
grep -Fq 'auto|1|2|3|4|5|6|7|8|9|10|11|12|13' "$EXECUTOR" || fail "executor does not accept enabled channels 12-13"
grep -Fq "''|auto|1|2|3|4|5|6|7|8|9|10|11|12|13" "$CGI" || fail "LuCI CGI does not accept enabled channels 12-13"
grep -Fq 'auto|1|2|3|4|5|6|7|8|9|10|11|12|13' "$DASH" || fail "Smart AP does not accept enabled channels 12-13"
grep -Fq 'for _c in 1 2 3 4 5 6 7 8 9 10 11 12 13' "$DASH" || fail "Smart AP does not list live channels 12-13"
grep -Fq 'channel > 13' "$LUCI_QUICK" || fail "LuCI list still hides channels 12-13"
! grep -Fq 'channel > 11' "$LUCI_QUICK" || fail "LuCI list still enforces the old channel 11 ceiling"
grep -Fq 'row.disabled === true' "$LUCI_QUICK" || fail "LuCI list exposes disabled channels"
grep -Fq '_disabled="$(printf' "$DASH" || fail "Smart AP list ignores the explicit disabled channel field"
grep -Fq '_flags="$(printf' "$DASH" || fail "Smart AP list ignores disabled channel flags"
grep -Fq 'phy_for_radio()' "$TX_APPLY" || fail "TX helper still assumes radio-to-phy numbering"
grep -Fq 'TX-power runtime verification failed' "$TX_APPLY" || fail "TX helper hides runtime mismatch"
! grep -Fq 'set txpower limit "$mbm" 2>/dev/null || true' "$TX_APPLY" || fail "TX helper suppresses iw failure"

# Every bridge owner resolves br-lan by name. WAN remains reserved and never
# returns to the LAN bridge through a positional @device[0] assumption.
for bridge_owner in "$EXECUTOR" "$VLAN_LIB" "$DASH" "$SECURITY_APPLY"; do
	! grep -Fq 'network.@device[0]' "$bridge_owner" || fail "positional bridge ownership remains in $bridge_owner"
done
grep -Fq 'Every access VLAN needs a tagged path' "$VLAN_LIB" || fail "orphan access VLANs are not rejected"
grep -Fq 'WAN is reserved for the uplink/PPPoE client' "$DASH" || fail "WAN reservation is not exposed by the switch controls"
grep -Fq 'runtime_ap_ifaces()' "$SECURITY_APPLY" || fail "DHCP guard still assumes fixed AP interface names"
grep -Fq "option stp '1'" "$NETWORK_CFG" || fail "clean image does not enable STP loop protection"
grep -Fq "option forward_delay '2'" "$NETWORK_CFG" || fail "clean image lacks the fast STP forwarding delay"
grep -Fq 'uci set "$bridge.stp=$want"' "$SECURITY_APPLY" || fail "loop guard does not own bridge STP state"
grep -Fq 'cr6608_strip_reserved_wan_from_vlans' "$VLAN_LIB" || fail "stale bridge VLANs can retain WAN membership"
grep -Fq 'ifup:lan|ifupdate:lan' "$SECURITY_HOTPLUG" || fail "LAN reload does not replay runtime isolation"
grep -Fq 'cr6608-security-apply hotplug' "$SECURITY_HOTPLUG" || fail "hotplug does not use the lock-aware runtime replay"
grep -A7 -F 'hotplug)' "$SECURITY_APPLY" | grep -Fq '/etc/init.d/cr6608-security enabled' || fail "hotplug does not re-check the service after acquiring the lock"
grep -Fq 'clear-runtime) clear_runtime' "$SECURITY_APPLY" || fail "security service cannot remove runtime nft/port policy"
grep -A5 -F 'stop() {' "$ROOT/files/etc/init.d/cr6608-security" | grep -Fq 'clear-runtime' || fail "stopping security leaves runtime policy active"
hotplug_sleep_line="$(grep -n 'sleep 1' "$SECURITY_HOTPLUG" | head -n 1 | cut -d: -f1)"
hotplug_apply_line="$(grep -n 'cr6608-security-apply hotplug' "$SECURITY_HOTPLUG" | head -n 1 | cut -d: -f1)"
[ -n "$hotplug_sleep_line" ] && [ -n "$hotplug_apply_line" ] && [ "$hotplug_sleep_line" -lt "$hotplug_apply_line" ] || \
	fail "hotplug runtime replay is not delayed until LAN settles"
grep -Fq 'while ! mkdir "$LOCK"' "$SECURITY_APPLY" || fail "security apply lock does not wait for concurrent operations"
grep -Fq 'timed out waiting for apply lock' "$SECURITY_APPLY" || fail "security apply lock has no bounded timeout"
grep -A18 -F 'clear_runtime() {' "$SECURITY_APPLY" | grep -Fq 'nft list table bridge smartap_guard' || fail "runtime cleanup cannot verify nft removal"
grep -Fq 'network_changed=0' "$EXECUTOR" || fail "executor does not track network-device changes for fw4"
grep -Fq '[ "$network_changed" = "1" ] || [ "$pre_fw" !=' "$EXECUTOR" || fail "fw4 is not reloaded when LAN moves between br-lan and br-lan.1"
grep -Fq 'transaction_restore_runtime()' "$EXECUTOR" || fail "transaction rollback lacks a runtime restore owner"
grep -A20 -F 'transaction_restore_runtime()' "$EXECUTOR" | grep -Fq '"$INITD_DIR/firewall" reload' || fail "rollback runtime restore leaves stale fw4 bindings"
grep -A35 -F 'transaction_rollback()' "$EXECUTOR" | grep -Fq 'transaction_restore_runtime || failed=1' || fail "signal/failure rollback does not restore runtime services"
grep -Fq '/etc/init.d/firewall reload' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN round-trip restore leaves stale fw4 interface bindings"
grep -Fq 'first, then rebuild fw4 so AP <-> AP+VLAN' "$DASH" || fail "Smart AP reloads fw4 before its VLAN/network transition"
grep -Fq 'VLAN/network must settle before fw4 resolves the lan zone device' "$SECURITY_APPLY" || fail "isolation apply reloads fw4 before changing LAN VLAN devices"
grep -Fq '_action_network_reload=1' "$DASH" || fail "advanced Smart AP network actions do not refresh fw4 device bindings"
grep -Fq 'firewall reload after vlan change failed' "$SECURITY_APPLY" || fail "direct isolation VLAN apply leaves stale fw4 bindings"
grep -Fq '[ "$committed_network" = 1 ] && /etc/init.d/firewall enabled' "$BOOTSTRAP" || fail "management bootstrap leaves fw4 stale after network repair"

# The rollback is armed before the first persistent commit.
arm_line="$(grep -n 'if ! safe_arm_transaction; then' "$EXECUTOR" | tail -n 1 | cut -d: -f1)"
commit_line="$(grep -n 'for pkg in $UCI_PACKAGES; do' "$EXECUTOR" | tail -n 1 | cut -d: -f1)"
[ -n "$arm_line" ] && [ -n "$commit_line" ] && [ "$arm_line" -lt "$commit_line" ] || fail "Safe Apply is armed after commit"

# Smart AP must never cancel a valid rollback transaction after a partial
# commit. All disruptive handlers arm before the first persistent mutation.
grep -A24 -F 'action_commit() {' "$DASH" | grep -Fq 'action_rollback_pending' || fail "action commit failure does not restore the guarded backup"
! grep -A24 -F 'action_commit() {' "$DASH" | grep -Fq 'cr6608-safe-apply confirm' || fail "action commit failure cancels the rollback guard"
grep -A18 -F 'action_arm_rollback() {' "$DASH" | grep -Fq 'uci -q revert' || fail "failed rollback arming leaves staged UCI changes"

if awk '
	/(action_commit|royal_commit_packages|uci commit)/ { previous_commit=NR; next }
	/(action_arm_rollback|arm_rollback)/ {
		if (previous_commit == NR - 1) bad=1
	}
	{ previous_commit=0 }
	END { exit bad ? 0 : 1 }
' "$DASH"; then
	fail "persistent mutation immediately precedes rollback arming"
fi

wizard_arm_line="$(grep -n 'arm_rollback "$backup" || royal_abort_apply "Could not arm the 120-second rollback guard."' "$DASH" | tail -n 1 | cut -d: -f1)"
wizard_password_line="$(grep -n 'passwd root.*/dev/null' "$DASH" | tail -n 1 | cut -d: -f1)"
wizard_commit_line="$(grep -n 'royal_commit_packages wireless network dhcp firewall smartap cr6608quick' "$DASH" | tail -n 1 | cut -d: -f1)"
wizard_store_line="$(grep -n 'store_royal_config || royal_abort_apply' "$DASH" | tail -n 1 | cut -d: -f1)"
[ -n "$wizard_arm_line" ] && [ -n "$wizard_password_line" ] && [ -n "$wizard_commit_line" ] && \
	[ -n "$wizard_store_line" ] && [ "$wizard_arm_line" -lt "$wizard_store_line" ] && \
	[ "$wizard_arm_line" -lt "$wizard_password_line" ] && [ "$wizard_arm_line" -lt "$wizard_commit_line" ] || \
	fail "Quick Setup mutates password/config before rollback arming"
wizard_reset_line="$(grep -n 'royal_reset_policy || royal_abort_apply "Could not apply the reset-button policy."' "$DASH" | tail -n 1 | cut -d: -f1)"
[ -n "$wizard_reset_line" ] && [ "$wizard_arm_line" -lt "$wizard_reset_line" ] || fail "Quick Setup mutates reset-button policy before rollback arming"
reset_arm_line="$(grep -n 'arm_rollback "$backup" || royal_abort_apply "Could not arm the 120-second rollback guard."' "$DASH" | head -n 1 | cut -d: -f1)"
reset_policy_line="$(grep -n 'royal_reset_policy || royal_abort_apply "Could not restore the factory reset-button policy."' "$DASH" | head -n 1 | cut -d: -f1)"
[ -n "$reset_arm_line" ] && [ -n "$reset_policy_line" ] && [ "$reset_arm_line" -lt "$reset_policy_line" ] || fail "Quick Setup reset mutates reset-button policy before rollback arming"
isolation_arm_line="$(grep -n 'arm_rollback "$backup" || isolation_abort' "$DASH" | head -n 1 | cut -d: -f1)"
isolation_heal_line="$(grep -n 'smartap_heal || isolation_abort' "$DASH" | head -n 1 | cut -d: -f1)"
[ -n "$isolation_arm_line" ] && [ -n "$isolation_heal_line" ] && [ "$isolation_arm_line" -lt "$isolation_heal_line" ] || fail "Isolation mutates Smart AP config before rollback arming"
grep -Fq 'actual_dash_ap_vlan_100=pass' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test omits Smart AP apply_royal"
grep -Fq 'actual_dash_isolation=pass' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test omits Smart AP apply_isolation"
grep -Fq 'actual_fw4_vlan_device=pass' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test omits live nft interface verification"
grep -Fq 'actual_fw4_isolation_device=pass' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "Isolation runtime test omits live nft interface verification"
grep -Fq 'nft list table inet fw4' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test accepts nft rules outside live fw4"
grep -Fq 'OLD_FIREWALL_ENABLED' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test does not restore firewall enable state"
grep -Fq 'OLD_SECURITY_ENABLED' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test does not restore security service state"
grep -Fq 'sha256sum -c "$BACKUP_HASHES"' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test reports exact restore without file verification"
grep -Fq 'etc/rc.button/reset' "$ROOT/tests/router-vlan-roundtrip.sh" || fail "VLAN runtime test does not restore reset-button policy"

# Critical service writers must participate in token-bound Safe Apply. These
# checks cover firewall, DNS/DHCP, STP, guest Wi-Fi, MAC rules, and IPTV.
for marker in \
	'action_arm_rollback "Firewall"' \
	'action_arm_rollback "DHCP"' \
	'action_arm_rollback "DHCP / DNS"' \
	'action_arm_rollback "Firewall defaults"' \
	'action_arm_rollback "Loop Guard"' \
	'action_arm_rollback "Block device"' \
	'action_arm_rollback "Unblock device"' \
	'action_arm_rollback "Guest Wi-Fi"' \
	'action_arm_rollback "IPTV"'; do
	grep -Fq "$marker" "$DASH" || fail "critical writer lacks rollback arm: $marker"
done
guest_network_line="$(grep -n '/etc/init.d/network reload >/tmp/dashctl.action' "$DASH" | tail -n 1 | cut -d: -f1)"
guest_wifi_line="$(grep -n 'action_reload "Guest Wi-Fi" "Wi-Fi reload failed"' "$DASH" | tail -n 1 | cut -d: -f1)"
guest_firewall_line="$(grep -n 'action_reload "Guest Wi-Fi" "Firewall reload failed"' "$DASH" | tail -n 1 | cut -d: -f1)"
[ -n "$guest_network_line" ] && [ -n "$guest_wifi_line" ] && [ -n "$guest_firewall_line" ] && \
	[ "$guest_network_line" -lt "$guest_wifi_line" ] && [ "$guest_wifi_line" -lt "$guest_firewall_line" ] || \
	fail "Guest Wi-Fi does not settle network/Wi-Fi before rebuilding fw4"

printf 'quicksettings_contracts=pass\n'
