#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PYTHON_BIN="${CR6608_PYTHON_BIN:-python3}"
EXECUTOR="$ROOT/files/usr/sbin/cr6608-quicksettings-apply"
CGI="$ROOT/files/www/cgi-bin/cr6608-quick-apply"
DASH="$ROOT/files/www/cgi-bin/dashctl"
DASH_JS="$ROOT/files/www/dashboard.js"
SAFE="$ROOT/files/usr/sbin/cr6608-safe-apply"
BOOTSTRAP="$ROOT/files/usr/sbin/smartap-bootstrap"
QUICK_CFG="$ROOT/files/etc/config/cr6608quick"
TX_LIB="$ROOT/files/usr/libexec/cr6608-txpower-lib"
TX_VERIFY="$ROOT/files/usr/bin/cr6608-txpower-verify"
FULL_TX_VERIFY="$ROOT/files/usr/bin/cr6608-wifi-full-verify"
COUNTRY_SCAN="$ROOT/files/usr/bin/cr6608-country-power-scan"
TX_DEFAULTS="$ROOT/files/etc/uci-defaults/94-cr6608-txpower"
SMARTAP_HEAL="$ROOT/files/etc/uci-defaults/93-cr6608-smartap-heal"
CHANNEL_DEFAULTS="$ROOT/files/etc/uci-defaults/95-cr6608-unique-channel"
QUICK_INIT="$ROOT/files/etc/init.d/cr6608-quicksettings"
AUTOCHANNEL="$ROOT/files/usr/sbin/smartap-autochannel"
UCI_SYNC_RUNTIME="$ROOT/tests/test-uci-sync-runtime.sh"
VLAN_LIB="$ROOT/files/usr/libexec/cr6608-vlan-lib"
PORT_LIB="$ROOT/files/usr/libexec/cr6608-port-readiness-lib"
QUICK_CGI="$ROOT/files/www/cgi-bin/cr6608-quick-apply"
SECURITY_APPLY="$ROOT/files/usr/sbin/cr6608-security-apply"
SECURITY_HOTPLUG="$ROOT/files/etc/hotplug.d/iface/98-cr6608-security-runtime"
LUCI_QUICK="$ROOT/files/www/luci-static/resources/view/cr6608/quicksettings.js"
RPC_ACL="$ROOT/files/usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json"
NETWORK_CFG="$ROOT/files/etc/config/network"
SESSION_AUTH="$ROOT/files/usr/libexec/cr6608-session-auth"
NETWORK_SAFETY="$ROOT/files/usr/libexec/cr6608-network-safety"
UHTTPD_CFG="$ROOT/files/etc/config/uhttpd"
SAFE_DEFAULTS="$ROOT/files/etc/uci-defaults/98-cr6608-safe-apply"

fail() {
	printf 'quicksettings_contracts=fail: %s\n' "$*" >&2
	exit 1
}

for file in "$EXECUTOR" "$CGI" "$DASH" "$DASH_JS" "$SAFE" "$BOOTSTRAP" "$QUICK_CFG" "$TX_LIB" "$TX_VERIFY" "$FULL_TX_VERIFY" "$COUNTRY_SCAN" "$TX_DEFAULTS" "$SMARTAP_HEAL" "$CHANNEL_DEFAULTS" "$QUICK_INIT" "$AUTOCHANNEL" "$UCI_SYNC_RUNTIME" "$VLAN_LIB" "$PORT_LIB" "$QUICK_CGI" "$SECURITY_APPLY" "$SECURITY_HOTPLUG" "$LUCI_QUICK" "$NETWORK_CFG" "$SESSION_AUTH" "$NETWORK_SAFETY"; do
	[ -s "$file" ] || fail "missing $file"
done
grep -Fq 'cr6608_path_permissions()' "$SESSION_AUTH" || fail "actual quick apply lacks its secure mode helper"
grep -Fq "o.datatype = 'range(2,4094)'" "$LUCI_QUICK" ||
	fail "LuCI Quick Settings does not enforce the backend VLAN range 2-4094"
[ "$(grep -Fc "o.datatype = 'range(1,4094)'" "$LUCI_QUICK")" -eq 1 ] ||
	fail "LuCI Quick Settings WAN VLAN range is missing or applied to multiple fields"
grep -B2 -A4 -F "o.datatype = 'range(1,4094)'" "$LUCI_QUICK" | grep -Fq "'pppoe_vlan_id'" ||
	fail "VLAN 1 is not isolated to the PPPoE WAN tag field"
grep -Fq "form.Flag, 'pppoe_vlan_enabled'" "$LUCI_QUICK" ||
	fail "LuCI Quick Settings lacks an explicit bare/tagged WAN selector"
grep -Fq "'pppoe_vlan_enabled','pppoe_vlan_id'" "$LUCI_QUICK" ||
	fail "LuCI Save & Apply payload omits the WAN VLAN controls"
grep -Fq "form.DummyValue, '_pppoe_wan_status'" "$LUCI_QUICK" &&
	grep -Fq "return _('Bare WAN (untagged)')" "$LUCI_QUICK" &&
	grep -Fq "return _('Tagged WAN: ') + device" "$LUCI_QUICK" ||
	fail "LuCI does not display the current bare/tagged WAN state"
grep -Fq "option pppoe_vlan_enabled '0'" "$QUICK_CFG" ||
	fail "clean image does not default PPPoE to bare WAN"
grep -Fq 'valid_wan_vlan()' "$CGI" &&
	grep -Fq 'PPPoE WAN VLAN ID must be 1-4094' "$CGI" ||
	fail "Quick Settings API does not validate the independent WAN VID"
grep -Fq 'json_add_string pppoe_vlan_enabled "$pppoe_vlan_enabled"' "$CGI" &&
	grep -Fq 'json_add_string pppoe_vlan_id "$pppoe_vlan_id"' "$CGI" ||
	fail "sanitized request handoff drops PPPoE WAN VLAN state"
grep -Fq 'smartap.quick.pppoe_vlan_enabled=$pppoe_vlan_enabled' "$EXECUTOR" &&
	grep -Fq 'smartap.quick.pppoe_vlan_id=$pppoe_vlan_id' "$EXECUTOR" &&
	grep -Fq 'smartap.quick.broadband_port=$pppoe_port' "$EXECUTOR" ||
	fail "LuCI Quick Settings leaves the Smart AP PPPoE WAN metadata stale"
grep -Fq "network.cr6608_wan_vlan.cr6608_owner='quicksettings-wan-vlan-v1'" "$EXECUTOR" &&
	grep -Fq "network.cr6608_wan_vlan.type='8021q'" "$EXECUTOR" &&
	grep -Fq 'network.cr6608_wan_vlan.ifname='"'"'wan'"'"'' "$EXECUTOR" &&
	grep -Fq 'network.cr6608_wan_vlan.name="$wan_device"' "$EXECUTOR" ||
	fail "executor does not create a fully owned 802.1Q WAN device"
grep -Fq 'cr6608_wan_ownership_available "$wan_target_vid" "$clear_previous"' "$EXECUTOR" ||
	fail "executor bypasses the fail-closed WAN ownership preflight"
grep -Fq 'cr6608_managed_wan_vlan_vid()' "$PORT_LIB" &&
	grep -Fq 'pppoe-vlan-active:$device_vid' "$PORT_LIB" ||
	fail "port readiness does not verify and report an owned PPPoE WAN VLAN"
grep -Fq 'uci set network.wan.device='"'"'wan'"'"'' "$EXECUTOR" &&
	grep -Fq 'remove_managed_wan_vlan || return 1' "$EXECUTOR" ||
	fail "returning to bare/parked WAN can leave a stale tagged device"
executor_park_block="$(sed -n '/^park_wan() {/,/^}/p' "$EXECUTOR")"
for parked_assignment in \
	"network.wan.proto='none'" \
	"network.wan.device='wan'" \
	"network.wan.disabled='1'" \
	"network.wan.auto='0'"; do
	printf '%s\n' "$executor_park_block" | grep -Fq "$parked_assignment" ||
		fail "privileged writer does not always stage parked WAN field: $parked_assignment"
done
printf '%s\n' "$executor_park_block" | grep -Fq 'cr6608_dump_section_type "$dump" network.wan' &&
	printf '%s\n' "$executor_park_block" | grep -Fq 'remove_managed_wan_vlan || return 1' ||
	fail "privileged WAN parker does not validate section/owner state before mutation"
grep -A14 -F 'remove_managed_wan_vlan()' "$EXECUTOR" | grep -Fq 'cr6608_managed_wan_vlan_state' ||
	fail "privileged writer still treats managed-owner read failure as absence"
grep -Fq 'cr6608_optional_get_from_dump()' "$PORT_LIB" &&
	grep -Fq 'cr6608_wan_bridge_reference_conflicts()' "$PORT_LIB" &&
	grep -Fq '[ -z "$type" ] && [ -z "$ifname" ] && [ -z "$ports" ] || return 1' "$PORT_LIB" ||
	fail "WAN ownership helper lacks fail-closed option reads or plain physical-device enforcement"
grep -Fq 'cr6608_wan_uci_pppoe_active()' "$PORT_LIB" &&
	grep -Fq 'cr6608_wan_uci_pppoe_active "$wan_target_vid"' "$EXECUTOR" ||
	fail "privileged writer does not read back the complete staged PPPoE state"
grep -A24 -F 'cr6608_wan_uci_parked()' "$PORT_LIB" |
	grep -Fq 'cr6608_dump_option_declared "$dump" network.wan.username' ||
	fail "parked WAN verification accepts retained PPPoE credentials"
grep -Fq 'set_pppoe_wan "$pppoe_user" "$pppoe_pass" "$pppoe_port" "$ipv6_enabled" "$wan_target_vid" || MUTATION_FAILED=1' "$EXECUTOR" &&
	grep -Fq 'set_ap_ports || MUTATION_FAILED=1' "$EXECUTOR" ||
	fail "privileged writer ignores a failed WAN staging helper"
wan_preflight_line="$(grep -nF 'cr6608_wan_ownership_available "$wan_target_vid" "$clear_previous"' "$EXECUTOR" | head -n1 | cut -d: -f1)"
wan_backup_line="$(grep -nF 'transaction_begin ||' "$EXECUTOR" | head -n1 | cut -d: -f1)"
wan_stage_line="$(grep -nF 'set_pppoe_wan "$pppoe_user"' "$EXECUTOR" | head -n1 | cut -d: -f1)"
wan_arm_line="$(grep -nF 'if ! safe_arm_transaction; then' "$EXECUTOR" | head -n1 | cut -d: -f1)"
wan_commit_line="$(grep -nF 'if ! uci commit "$pkg"; then' "$EXECUTOR" | head -n1 | cut -d: -f1)"
[ -n "$wan_preflight_line" ] && [ -n "$wan_backup_line" ] && [ -n "$wan_stage_line" ] &&
	[ -n "$wan_arm_line" ] && [ -n "$wan_commit_line" ] &&
	[ "$wan_preflight_line" -lt "$wan_backup_line" ] &&
	[ "$wan_backup_line" -lt "$wan_stage_line" ] &&
	[ "$wan_stage_line" -lt "$wan_arm_line" ] &&
	[ "$wan_arm_line" -lt "$wan_commit_line" ] ||
	fail "WAN VLAN preflight/staging is outside the transaction and Safe Apply order"
! grep -Fq "form.Flag, 'change_password'" "$LUCI_QUICK" ||
	fail "LuCI Quick Settings still exposes the console-password toggle"
! grep -Fq "form.Value, '_admin_password'" "$LUCI_QUICK" ||
	fail "LuCI Quick Settings still exposes the console-password field"
grep -Fq 'console_password_locked' "$CGI" ||
	fail "Quick Settings CGI does not reject direct console-password requests"
grep -Fq 'developer SSH/console password changes are locked' "$EXECUTOR" ||
	fail "privileged Quick Settings writer does not fail closed on password handoff"
! grep -Fq 'passwd root' "$DASH" ||
	fail "Smart AP still contains a root-password mutation"
for policy in nat dhcp broadband; do
	grep -Fq "form.DummyValue, '_${policy}_mode_policy'" "$LUCI_QUICK" ||
		fail "$policy is not displayed as a mode-derived policy"
done
for legacy_flag in nat_enabled dhcp_server broadband_enabled; do
	! grep -Fq "form.Flag, '$legacy_flag'" "$LUCI_QUICK" ||
		fail "$legacy_flag is still exposed as an operator-controlled flag"
done
[ "$(grep -Fc "=== 'pppoe'" "$LUCI_QUICK")" -ge 3 ] ||
	fail "NAT/DHCP/broadband policy is not derived from PPPoE mode"

# Every independent writer joins the dashboard generation bracket, while the
# global apply lock lives below root-owned /var/run rather than public /tmp.
for cache_writer in "$EXECUTOR" "$AUTOCHANNEL" "$ROOT/files/usr/sbin/cr6608-safe-apply" \
	"$ROOT/files/usr/sbin/cr6608-safe-wifi-reload" "$ROOT/files/usr/sbin/cr6608-wifi-sentinel" \
	"$ROOT/files/usr/sbin/cr6608-wifi-schedule" "$QUICK_CGI"; do
	grep -Fq 'cr6608_dashboard_cache_mutation_begin' "$cache_writer" ||
		fail "dashboard cache mutation bracket is missing from $cache_writer"
done
grep -Fq 'do_rollback()' "$ROOT/files/usr/sbin/cr6608-safe-apply" || fail "Safe Apply rollback owner is missing"
grep -A8 -F 'do_rollback()' "$ROOT/files/usr/sbin/cr6608-safe-apply" | grep -Fq 'cr6608_dashboard_cache_mutation_begin' ||
	fail "automatic rollback can mutate outside the dashboard generation bracket"
if grep -R -n -F '/tmp/cr6608-apply.lock' "$ROOT/files" >/dev/null 2>&1; then
	fail "a writer still uses the public /tmp apply lock"
fi
! grep -Fq 'LOCK="/tmp/cr6608-security.lock"' "$SECURITY_APPLY" ||
	fail "security policy still locks below public /tmp"
! grep -Fq '/tmp/' "$EXECUTOR" || fail "Quick Settings still writes below public /tmp"
grep -Fq 'cr6608_private_runtime_dir quicksettings' "$EXECUTOR" ||
	fail "Quick Settings lacks a private transaction runtime"
grep -Fq 'cr6608_private_runtime_dir safe-apply' "$EXECUTOR" ||
	fail "Quick Settings does not read the unified private Safe Apply runtime"
grep -Fq 'mktemp -d "$QUICK_RUNTIME_DIR/transaction.XXXXXX"' "$EXECUTOR" ||
	fail "Quick Settings transaction directory is not randomly created below private runtime"
grep -Fq 'wireless_backup="$(quick_mktemp wireless-preapply)"' "$EXECUTOR" ||
	fail "wireless rollback snapshot still has a predictable pathname"
if grep -Fq '.tmp.$$' "$EXECUTOR" || grep -Fq 'cr6608-wireless-preapply.$$' "$EXECUTOR"; then
	fail "Quick Settings retains a predictable root temporary file"
fi
grep -Fq 'printf '\''%s\n'\'' "$deployment_ruleset" | nft -c -f -' "$SECURITY_APPLY" ||
	fail "security nft guard is not checked from an in-memory snapshot"
grep -Fq 'printf '\''%s\n'\'' "$deployment_ruleset" | nft -f -' "$SECURITY_APPLY" ||
	fail "security nft guard does not apply the checked in-memory snapshot"
grep -Fq 'delete table bridge smartap_guard' "$SECURITY_APPLY" ||
	fail "security nft replacement does not atomically remove the prior table"
grep -A8 -F 'remove_bridge_guard()' "$SECURITY_APPLY" | grep -Fq 'nft list table bridge smartap_guard' ||
	fail "security guard removal is not verified against the live nft table"
grep -A8 -F 'bridge_guard_absent()' "$SECURITY_APPLY" | grep -Fq 'nft list tables bridge' ||
	fail "security guard absence conflates nft query failure with a removed table"
grep -A12 -F 'apply_bridge_guard()' "$SECURITY_APPLY" | grep -Fq 'remove_bridge_guard' ||
	fail "disabled security can report success while stale bridge drops remain"
grep -A35 -F 'reset_target_secure()' "$EXECUTOR" | grep -Fq "stat -c '%u:%a:%h'" ||
	fail "reset policy trusts a path without owner/mode/link-count validation"
grep -A35 -F 'reset_target_secure()' "$EXECUTOR" | grep -Fq '[ "${metadata##*:}" = 1 ]' ||
	fail "reset policy accepts multiply-linked restore sources"
grep -Fq '/usr/sbin/cr6608-dashboard-invalidate' "$SECURITY_APPLY" ||
	fail "standalone security policy changes do not invalidate dashboard state"
grep -Fq '/usr/sbin/cr6608-dashboard-invalidate' "$BOOTSTRAP" ||
	fail "standalone bootstrap changes do not invalidate dashboard state"

# Generic interface editing must not put L3 directly on a DSA slave, eth0,
# WAN, loopback, br-lan, or a generated br-lan VLAN.  Those devices have
# dedicated owners and are deliberately absent from the generic selector.
grep -Fq 'cr6608_safe_l3_device()' "$NETWORK_SAFETY" || fail "network safety helper is missing"
[ "$(grep -Fc 'available_extra_l3_device "$dev" "$ifname"' "$DASH")" -eq 2 ] ||
	fail "the device gate must remain scoped to the two generic interface writers"
grep -Fq 'cr6608_l3_device_available()' "$NETWORK_SAFETY" ||
	fail "network safety helper does not enforce unique L3 ownership"
grep -Fq 'cr6608_l3_device_available "$1" "$2"' "$DASH" ||
	fail "generic interface writer bypasses ownership validation"
grep -Fq 'valid_extra_l3_device "$d" || continue' "$DASH" ||
	fail "interface selector does not use the shared allowlist"
if grep -Fq 'for d in br-lan wan lan1 lan2 lan3 eth0 lo' "$DASH"; then
	fail "generic interface selector still advertises core/DSA devices"
fi
grep -Fq 'if_ipaddr|IPv4 address|${if_ip_cur}|Required when Static is selected' "$DASH" ||
	fail "generic interface editor still pre-fills the LAN management address"
grep -Fq '"Unsafe device"' "$DASH" || fail "generic interface rejection lacks a clear error title"
grep -Fq 'DSA LAN ports, eth0, WAN, loopback, br-lan and its VLANs are owned by Quick Settings.' "$DASH" ||
	fail "generic interface rejection does not direct the user to the owning workflow"

# The allowlist is intentionally local to the advanced generic editor.  The
# documented VLAN and PPPoE workflows remain owned by Quick Settings and must
# continue to create their generated interface/WAN directly.
grep -Fq 'cr6608_apply_port_vlans "$vlan_id" "$_ignore_policy" "$delete_previous"' "$DASH" ||
	fail "documented VLAN workflow no longer calls the VLAN owner"
grep -Fq 'royal_set "network.cr6608_vlan.device=br-lan.$vlan_id"' "$DASH" ||
	fail "documented VLAN workflow no longer binds its generated L3 interface"
grep -Fq 'royal_set "network.wan.device=$royal_wan_device"' "$DASH" ||
	fail "documented PPPoE workflow no longer binds the reserved WAN device"
grep -Fq 'royal_set "network.wan.proto=pppoe"' "$DASH" ||
	fail "documented PPPoE workflow no longer stages PPPoE"

# Smart AP is a second writer for the same PPPoE topology.  It must expose,
# validate, persist and stage the exact same owned wan.<VID> model as LuCI.
grep -Fq 'PORT_READINESS_LIB="${CR6608_PORT_READINESS_LIB:-/usr/libexec/cr6608-port-readiness-lib}"' "$DASH" ||
	fail "Smart AP does not load the shared WAN ownership contract"
grep -Fq 'pppoe_vlan_enabled|وسم PPPoE WAN|${pppoe_vlan_enabled:-0}' "$DASH" &&
	grep -Fq 'pppoe_vlan_id|رقم VLAN لمنفذ PPPoE WAN|${pppoe_vlan_id:-35}' "$DASH" ||
	fail "Smart AP wizard lacks independent bare/tagged WAN controls"
grep -Fq 'cr6608_wan_vlan_id_valid "$pppoe_vlan_id"' "$DASH" &&
	grep -Fq 'PPPoE WAN VLAN ID must contain only digits and be in the range 1-4094.' "$DASH" ||
	fail "Smart AP backend does not validate the PPPoE WAN VID"
for royal_wan_store in \
	'smartap.quick.pppoe_vlan_enabled=$pppoe_vlan_enabled' \
	'smartap.quick.pppoe_vlan_id=$pppoe_vlan_id' \
	'cr6608quick.default.pppoe_vlan_enabled=$pppoe_vlan_enabled' \
	'cr6608quick.default.pppoe_vlan_id=$pppoe_vlan_id'; do
	grep -Fq "$royal_wan_store" "$DASH" || fail "Smart AP leaves a WAN VLAN persistence store stale: $royal_wan_store"
done
grep -Fq 'network.cr6608_wan_vlan.cr6608_owner=quicksettings-wan-vlan-v1' "$DASH" &&
	grep -Fq 'network.cr6608_wan_vlan.type=8021q' "$DASH" &&
	grep -Fq 'network.cr6608_wan_vlan.ifname=wan' "$DASH" &&
	grep -Fq 'network.cr6608_wan_vlan.name=$royal_wan_device' "$DASH" ||
	fail "Smart AP does not stage the complete owned 802.1Q WAN device"
grep -A28 -F 'royal_strip_wan_bridge_membership()' "$DASH" | grep -Fq 'network.@bridge-vlan[$_royal_bridge_vlan_idx].ports' &&
	[ "$(grep -Fc 'royal_strip_wan_bridge_membership || royal_abort_apply' "$DASH")" -eq 2 ] ||
	fail "Smart AP explicit takeover does not remove WAN from both bridge and bridge-VLAN membership"
grep -A14 -F 'royal_verify_wan_vlan_stage()' "$DASH" | grep -Fq 'cr6608_wan_ownership_available "$_royal_verify_vid" 0' ||
	fail "Smart AP does not verify that bridge/stacked WAN conflicts are gone before commit"
royal_park_block="$(sed -n '/^royal_park_wan() {/,/^}/p' "$DASH")"
for parked_assignment in \
	'network.wan.proto=none' \
	'network.wan.device=wan' \
	'network.wan.disabled=1' \
	'network.wan.auto=0'; do
	printf '%s\n' "$royal_park_block" | grep -Fq "$parked_assignment" ||
		fail "Smart AP does not always stage parked WAN field: $parked_assignment"
done
grep -A14 -F 'royal_remove_managed_wan_vlan()' "$DASH" | grep -Fq 'cr6608_managed_wan_vlan_state' ||
	fail "Smart AP still treats managed-owner read failure as absence before delete"
grep -A35 -F 'royal_verify_wan_vlan_stage()' "$DASH" | grep -Fq 'cr6608_wan_uci_parked "$_royal_verify_dump"' ||
	fail "Smart AP parked verification does not require proto/device/disabled/auto"
grep -A35 -F 'royal_verify_wan_vlan_stage()' "$DASH" | grep -Fq 'cr6608_wan_uci_pppoe_active "$_royal_verify_vid" "$_royal_verify_dump"' ||
	fail "Smart AP mapping verification does not require complete active PPPoE state"
grep -A12 -F 'royal_delete()' "$DASH" | grep -Fq 'royal_reference_snapshot "$_royal_delete_ref"' &&
	grep -A12 -F 'royal_del_list()' "$DASH" | grep -Fq 'royal_reference_snapshot "$_royal_list_ref"' ||
	fail "Smart AP delete/list helpers still conflate backend failure with absence"
grep -Fq 'PPPoE WAN|$wan_link_state|Live owned bare/tagged mapping|$wan_link_level' "$DASH" ||
	fail "Smart AP does not display the live bare/tagged WAN ownership state"
grep -Fq 'wanVid.disabled = !pppoe || !wanTag || wanTag.value !== "1"' "$DASH_JS" &&
	grep -Fq 'function validateWizardWanVlan(section, actionName)' "$DASH_JS" &&
	grep -Fq 'wan." + (fv("pppoe_vlan_id") || "?") + " (802.1Q)' "$DASH_JS" ||
	fail "Smart AP browser UI does not synchronize, preview and validate WAN tagging"

# UCI staging is global.  Every dashboard transaction must reject a pre-existing
# delta before it consults WAN ownership, creates a committed-file backup, or
# commits packages.  A staged deletion must never hide a competing WAN owner.
grep -A18 -F 'action_backup()' "$DASH" | grep -Fq 'dashctl_transaction_uci_clean' ||
	fail "generic dashboard transactions can merge pre-existing UCI changes"
grep -A8 -F 'royal_begin_transaction()' "$DASH" | grep -Fq 'royal_require_clean_uci || return 1' ||
	fail "Royal transactions do not recheck clean UCI state before backup"
grep -A16 -F 'transaction_begin()' "$EXECUTOR" | grep -Fq 'if ! pending="$(uci -q changes "$pkg" 2>/dev/null)"; then' ||
	fail "privileged Quick Settings treats a UCI change-query failure as clean"
(
	eval "$(sed -n '/^DASHCTL_TRANSACTION_UCI_PACKAGES=/,/^backup_cfg() {/p' "$DASH" | sed '$d')"
	eval "$(sed -n '/^royal_begin_transaction() {/,/^}/p' "$DASH")"
	delta_tmp="$(mktemp -d)" || fail "could not create staged-delta test workspace"
	trap 'rm -rf -- "$delta_tmp"' EXIT HUP INT TERM
	delta_scenario=clean
	commit_calls=0
	uci() {
		[ "${1:-}" = -q ] && shift
		case "${1:-}" in
			changes)
				[ "$delta_scenario" != query_failure ] || return 1
				if [ "$delta_scenario" = staged_delete ] && [ "${2:-}" = network ]; then
					printf '%s\n' '-network.uplink'
				fi
				return 0
				;;
			commit) commit_calls=$((commit_calls + 1)); return 0 ;;
		esac
		return 1
	}
	capture_rollback_state() { :; }
	backup_cfg() { : >"$delta_tmp/backup-called"; printf '/tmp/mock-backup.tgz'; }
	royal_backup_valid() { return 0; }

	royal_begin_transaction clean || fail "clean Royal transaction was rejected"
	[ -e "$delta_tmp/backup-called" ] || fail "clean Royal transaction did not reach backup"
	rm -f "$delta_tmp/backup-called"
	delta_scenario=staged_delete
	if royal_begin_transaction staged-delete; then
		uci commit network
		fail "staged WAN-owner deletion reached the transaction body"
	fi
	[ ! -e "$delta_tmp/backup-called" ] || fail "staged WAN-owner deletion reached committed-file backup"
	[ "$commit_calls" -eq 0 ] || fail "staged WAN-owner deletion was merged by commit"
	case "$royal_backup_error" in *network*) ;; *) fail "staged-delta rejection does not identify network" ;; esac
	delta_scenario=query_failure
	if royal_begin_transaction query-failure >/dev/null 2>&1; then
		fail "UCI change-query failure was accepted as clean"
	fi
) || exit 1

smart_wan_apply_block="$(sed -n '/^  apply_royal)/,/^  save_quick)/p' "$DASH")"
smart_wan_clean_line="$(printf '%s\n' "$smart_wan_apply_block" | grep -nF 'royal_require_clean_uci ||' | head -n1 | cut -d: -f1)"
smart_wan_preflight_line="$(printf '%s\n' "$smart_wan_apply_block" | grep -nF 'cr6608_wan_ownership_available "$wan_target_vid" "$delete_previous"' | head -n1 | cut -d: -f1)"
smart_wan_begin_line="$(printf '%s\n' "$smart_wan_apply_block" | grep -nF 'royal_begin_transaction royal-apply' | head -n1 | cut -d: -f1)"
smart_wan_arm_line="$(printf '%s\n' "$smart_wan_apply_block" | grep -nF 'arm_rollback "$backup"' | head -n1 | cut -d: -f1)"
smart_wan_stage_line="$(printf '%s\n' "$smart_wan_apply_block" | grep -nF 'royal_stage_wan_vlan "$wan_target_vid"' | head -n1 | cut -d: -f1)"
smart_wan_commit_line="$(printf '%s\n' "$smart_wan_apply_block" | grep -nF 'royal_commit_packages wireless network' | head -n1 | cut -d: -f1)"
[ -n "$smart_wan_clean_line" ] && [ -n "$smart_wan_preflight_line" ] && [ -n "$smart_wan_begin_line" ] &&
	[ -n "$smart_wan_arm_line" ] && [ -n "$smart_wan_stage_line" ] && [ -n "$smart_wan_commit_line" ] &&
	[ "$smart_wan_clean_line" -lt "$smart_wan_preflight_line" ] &&
	[ "$smart_wan_preflight_line" -lt "$smart_wan_begin_line" ] &&
	[ "$smart_wan_begin_line" -lt "$smart_wan_arm_line" ] &&
	[ "$smart_wan_arm_line" -lt "$smart_wan_stage_line" ] &&
	[ "$smart_wan_stage_line" -lt "$smart_wan_commit_line" ] ||
	fail "Smart AP WAN preflight/staging is outside backup and Safe Apply ordering"
printf '%s\n' "$smart_wan_apply_block" | grep -Fq 'royal_park_wan ||' &&
	printf '%s\n' "$smart_wan_apply_block" | grep -Fq 'royal_verify_wan_vlan_stage "$wan_target_vid" "$royal_wan_verify_mode"' ||
	fail "Smart AP can leave a stale tagged owner when parking/baring WAN"
smart_wan_reset_block="$(sed -n '/^  reset_royal)/,/^  apply_royal)/p' "$DASH")"
reset_clean_line="$(printf '%s\n' "$smart_wan_reset_block" | grep -nF 'royal_require_clean_uci ||' | head -n1 | cut -d: -f1)"
reset_wan_line="$(printf '%s\n' "$smart_wan_reset_block" | grep -nF 'cr6608_wan_ownership_available "" 1' | head -n1 | cut -d: -f1)"
[ -n "$reset_clean_line" ] && [ -n "$reset_wan_line" ] && [ "$reset_clean_line" -lt "$reset_wan_line" ] &&
	printf '%s\n' "$smart_wan_reset_block" | grep -Fq 'royal_park_wan ||' &&
	printf '%s\n' "$smart_wan_reset_block" | grep -Fq 'royal_verify_wan_vlan_stage "" parked' ||
	fail "Smart AP reset can delete or retain WAN VLAN state without ownership verification"
smart_wan_save_block="$(sed -n '/^  save_royal)/,/^  reset_royal)/p' "$DASH")"
printf '%s\n' "$smart_wan_save_block" | grep -Fq 'royal_require_clean_uci ||' ||
	fail "Smart AP save can merge a pre-existing UCI delta"
for secret_param in wifi_password device_password pppoe_pass; do
	printf '%s\n' "$smart_wan_save_block" | grep -Fq "param $secret_param" ||
		fail "Smart AP save does not reject direct $secret_param submission"
done
printf '%s\n' "$smart_wan_save_block" | grep -Fq 'Secrets were not saved' ||
	fail "Smart AP save can report an ambiguous result for rejected secrets"
save_secret_reject_line="$(printf '%s\n' "$smart_wan_save_block" | grep -nF 'Secrets were not saved' | head -n1 | cut -d: -f1)"
save_load_line="$(printf '%s\n' "$smart_wan_save_block" | grep -nF 'load_royal_params' | head -n1 | cut -d: -f1)"
[ -n "$save_secret_reject_line" ] && [ -n "$save_load_line" ] &&
	[ "$save_secret_reject_line" -lt "$save_load_line" ] ||
	fail "Smart AP checks direct secrets only after loading save parameters"
wizard_view_block="$(sed -n '/^  wizard)/,/^  specs)/p' "$DASH")"
if printf '%s\n' "$wizard_view_block" | grep -Fq '"id":"save_royal"'; then
	fail "Quick Setup still exposes Save without Apply for secret-bearing fields"
fi

# A no-op Smart AP wizard apply must preserve the clean-flash SSID pair, and
# the isolation page must report live UCI names rather than old hard-coded
# branding.  These contracts protect the exact defects found on real v73 RAM.
grep -Fq '*2.4G) ssid5="${ssid%2.4G}5G"' "$DASH" ||
	fail "Smart AP wizard no longer maps a 2.4G suffix to the matching 5G SSID"
grep -Fq 'iso_ssid24="$(uci -q get wireless.wifinet0.ssid' "$DASH" ||
	fail "isolation cards do not read the live 2.4G SSID"
grep -Fq 'iso_ssid5="$(uci -q get wireless.wifinet1.ssid' "$DASH" ||
	fail "isolation cards do not read the live 5G SSID"
if grep -Fq '|Smart-AP-5G|' "$DASH"; then
	fail "isolation cards still expose a hard-coded legacy 5G SSID"
fi

# Bridge edits are disruptive and arm Safe Apply.  The response must expose
# both token-bound choices, otherwise the timer silently rolls back a save.
bridge_save_block="$(sed -n '/^  save_bridge_options|set_port_state)/,/^  set_admin_password)/p' "$DASH")"
printf '%s\n' "$bridge_save_block" | grep -Fq '"id":"keep_changes"' ||
	fail "bridge save response lacks Keep changes"
printf '%s\n' "$bridge_save_block" | grep -Fq '"id":"rollback_last"' ||
	fail "bridge save response lacks Rollback now"
bridge_validate_line="$(printf '%s\n' "$bridge_save_block" | grep -nF 'cr6608_normalize_bridge_ports "$bports_raw"' | head -n1 | cut -d: -f1)"
bridge_backup_line="$(printf '%s\n' "$bridge_save_block" | grep -nF 'action_backup switch' | head -n1 | cut -d: -f1)"
bridge_mutation_line="$(printf '%s\n' "$bridge_save_block" | grep -nE 'uci (set|-q delete|-q del_list|add_list)' | head -n1 | cut -d: -f1)"
[ -n "$bridge_validate_line" ] && [ -n "$bridge_backup_line" ] && [ -n "$bridge_mutation_line" ] &&
	[ "$bridge_validate_line" -lt "$bridge_backup_line" ] && [ "$bridge_backup_line" -lt "$bridge_mutation_line" ] ||
	fail "bridge ports are not fully validated before backup/UCI mutation"
printf '%s\n' "$bridge_save_block" | grep -Fq 'WAN and mixed valid/invalid lists are rejected; nothing was changed.' ||
	fail "bridge validation does not explicitly reject mixed/invalid requests"

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

# Normal saves preserve LuCI/DSA ownership. Destructive cleanup is an explicit,
# validated takeover and an unmanaged br-lan model is rejected before mutation.
! grep -Fq "clear_previous='1'" "$EXECUTOR" || fail "executor still forces destructive cleanup"
! grep -Fq "clr='1'" "$CGI" || fail "LuCI Quick Settings CGI still forces destructive cleanup"
! grep -Fq 'delete_previous="1"' "$DASH" || fail "Smart AP still forces destructive cleanup"
grep -Fq "option clear_previous '0'" "$QUICK_CFG" || fail "clean-image cleanup default is not safe"
grep -Fq 'cr6608_unmanaged_port_vlans_exist' "$EXECUTOR" || fail "executor lacks unmanaged VLAN conflict detection"
grep -Fq 'cr6608_unmanaged_port_vlans_exist' "$DASH" || fail "Smart AP lacks unmanaged VLAN conflict detection"
grep -Fq 'cr6608_port_vlan_is_owned()' "$VLAN_LIB" || fail "VLAN helper lacks SmartAP ownership markers"
grep -Fq 'cr6608_clear_port_vlans "$takeover"' "$VLAN_LIB" || fail "VLAN cleanup is not takeover-aware"
grep -Fq 'primary_ap_section()' "$EXECUTOR" ||
	fail "quick executor does not discover renamed AP sections"
direct_wifinet_refs="$(grep -Ec 'wireless\.wifinet[01]\.' "$EXECUTOR" || true)"
[ "$direct_wifinet_refs" -eq 0 ] ||
	fail "quick executor still mutates fixed wifinet0/wifinet1 sections"
grep -Fq 'primary_ap_canonical_eligible()' "$EXECUTOR" &&
	grep -Fq 'primary_ap_fallback_eligible()' "$EXECUTOR" ||
	fail "quick executor lacks distinct canonical/fallback role policy"
grep -Fq '_cr_pa_canonical_eligible()' "$DASH" &&
	grep -Fq '_cr_pa_client_eligible()' "$DASH" ||
	fail "Smart AP writer lacks distinct canonical/fallback role policy"

# Exercise the resolver itself.  A canonical WDS sender must remain selectable
# so the next plain-AP apply can clear WDS; Multi-AP remains rejected because it
# may carry a separate backhaul credential.  Fallbacks must be unique LAN APs.
POLICY_TMP="$(mktemp -d)"
case "$POLICY_TMP" in /tmp/*|/var/tmp/*) ;; *) fail "unsafe resolver temp directory" ;; esac
cleanup_policy_tmp() { rm -rf -- "$POLICY_TMP"; }
trap cleanup_policy_tmp EXIT HUP INT TERM
sed -n '/^primary_ap_network_eligible()/,/^clear_fast_transition()/p' "$EXECUTOR" |
	sed '$d' > "$POLICY_TMP/resolver.sh"
cat > "$POLICY_TMP/driver.sh" <<'EOF'
#!/bin/sh
set -eu
scenario="$1"
resolver="$2"
uci() {
	[ "${1:-}" = -q ] && shift
	action="${1:-}"; key="${2:-}"
	if [ "$action:$key" = show:wireless ]; then
		case "$scenario" in
			wds|multi) printf 'wireless.wifinet0=wifi-iface\n' ;;
			fallback) printf '%s\n' 'wireless.guest=wifi-iface' 'wireless.backhaul=wifi-iface' 'wireless.ap_alpha=wifi-iface' ;;
			ambiguous) printf '%s\n' 'wireless.ap_alpha=wifi-iface' 'wireless.ap_gamma=wifi-iface' ;;
		esac
		return 0
	fi
	[ "$action" = get ] || return 1
	case "$key" in
		wireless.wifinet0)
			case "$scenario" in wds|multi) printf 'wifi-iface\n' ;; *) return 1 ;; esac ;;
		wireless.wifinet0.device) printf 'radio0\n' ;;
		wireless.wifinet0.mode) printf 'ap\n' ;;
		wireless.wifinet0.network) printf 'lan\n' ;;
		wireless.wifinet0.wds) [ "$scenario" = wds ] && printf '1\n' || return 1 ;;
		wireless.wifinet0.multi_ap) [ "$scenario" = multi ] && printf '1\n' || return 1 ;;
		wireless.guest|wireless.backhaul|wireless.ap_alpha|wireless.ap_gamma) printf 'wifi-iface\n' ;;
		wireless.guest.device|wireless.backhaul.device|wireless.ap_alpha.device|wireless.ap_gamma.device) printf 'radio0\n' ;;
		wireless.guest.mode|wireless.backhaul.mode|wireless.ap_alpha.mode|wireless.ap_gamma.mode) printf 'ap\n' ;;
		wireless.guest.network) printf 'guest\n' ;;
		wireless.backhaul.network|wireless.ap_alpha.network|wireless.ap_gamma.network) printf 'lan\n' ;;
		wireless.backhaul.wds) printf '1\n' ;;
		*) return 1 ;;
	esac
}
. "$resolver"
primary_ap_section radio0 wifinet0
EOF
chmod 0755 "$POLICY_TMP/driver.sh"
[ "$(CR6608_TEST_SCENARIO=wds sh "$POLICY_TMP/driver.sh" wds "$POLICY_TMP/resolver.sh")" = wifinet0 ] ||
	fail "WDS sender to AP transition can no longer resolve the canonical AP"
grep -Fq 'uci -q delete "wireless.${ap24}.wds"' "$EXECUTOR" &&
	grep -Fq 'uci -q delete "wireless.${ap5}.wds"' "$EXECUTOR" ||
	fail "plain AP transition does not clear canonical WDS sender state"
if sh "$POLICY_TMP/driver.sh" multi "$POLICY_TMP/resolver.sh" >/dev/null 2>&1; then
	fail "canonical Multi-AP backhaul was selected as a client AP"
fi
[ "$(sh "$POLICY_TMP/driver.sh" fallback "$POLICY_TMP/resolver.sh")" = ap_alpha ] ||
	fail "unique LAN fallback AP was not selected"
if sh "$POLICY_TMP/driver.sh" ambiguous "$POLICY_TMP/resolver.sh" >/dev/null 2>&1; then
	fail "ambiguous LAN fallback APs were accepted"
fi

quick_security_block="$(sed -n '/^set_security()/,/^}/p' "$EXECUTOR")"
dash_security_block="$(sed -n '/^set_wifi_security()/,/^}/p' "$DASH")"
for stale_option in sae_password sae_password_file wpa_psk_file ppsk ppsk_file \
	multi_ap_backhaul_ssid multi_ap_backhaul_key wps_pin wps_pushbutton wps_label \
	ext_registrar wps_pbc_in_m1 wps_independent ap_pin hostapd_bss_options; do
	printf '%s\n' "$quick_security_block" | grep -Fq "$stale_option" ||
		fail "Quick security transition retains $stale_option"
	printf '%s\n' "$dash_security_block" | grep -Fq "$stale_option" ||
		fail "Smart AP security transition retains $stale_option"
done
rm -rf -- "$POLICY_TMP"
trap - EXIT HUP INT TERM
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
# channel. TX power is requested through UCI/netifd and read back separately.
for channel_owner in "$EXECUTOR" "$CGI" "$DASH"; do
	grep -Fq '.disabled' "$channel_owner" || fail "disabled channel flag is ignored in $channel_owner"
	grep -Fq '.flags[*]' "$channel_owner" || fail "channel flags are ignored in $channel_owner"
done
grep -Fq 'auto|1|2|3|4|5|6|7|8|9|10|11|12|13' "$EXECUTOR" || fail "executor does not accept enabled channels 12-13"
grep -Fq "''|auto|1|2|3|4|5|6|7|8|9|10|11|12|13" "$CGI" || fail "LuCI CGI does not accept enabled channels 12-13"
grep -Fq 'auto|1|2|3|4|5|6|7|8|9|10|11|12|13' "$DASH" || fail "Smart AP does not accept enabled channels 12-13"
grep -Fq '2g) set -- 1 2 3 4 5 6 7 8 9 10 11 12 13' "$DASH" || fail "Smart AP does not list live channels 12-13"
grep -Fq 'channel > 13' "$LUCI_QUICK" || fail "LuCI list still hides channels 12-13"
! grep -Fq 'channel > 11' "$LUCI_QUICK" || fail "LuCI list still enforces the old channel 11 ceiling"
grep -Fq 'row.disabled === true' "$LUCI_QUICK" || fail "LuCI list exposes disabled channels"
grep -Fq '@.results[@.disabled=true].channel' "$DASH" || fail "Smart AP list ignores the explicit disabled channel field"
grep -Fq '@.results[@.flags[*]="disabled"].channel' "$DASH" || fail "Smart AP list ignores disabled channel flags"

# First-boot healing is idempotent: remove only the unsupported legacy distance
# value, seed only absent radio/AP options, and never overwrite retained values.
grep -Fq '[ "$(uci -q get "wireless.${radio}.distance" 2>/dev/null)" = "auto" ]' "$SMARTAP_HEAL" ||
	fail "first-boot heal does not remove legacy distance=auto"
grep -Fq 'uci -q get "wireless.${section}.${option}" >/dev/null 2>&1 && return 0' "$SMARTAP_HEAL" ||
	fail "first-boot heal overwrites existing wireless options"
for seed in \
	'seed_wireless_option "$radio" ldpc 1' \
	'seed_wireless_option "$radio" legacy_rates 0' \
	'seed_wireless_option "$iface" wmm 1' \
	'seed_wireless_option "$iface" isolate 0'; do
	grep -Fq "$seed" "$SMARTAP_HEAL" || fail "missing first-boot wireless seed: $seed"
done
grep -Fq '[ "$wireless_changed" -eq 0 ] || uci commit wireless' "$SMARTAP_HEAL" ||
	fail "first-boot heal does not commit wireless only when changed"
grep -Fq 'if [ "$("$UCI_BIN" -q get "wireless.${radio}.distance" 2>/dev/null)" = "auto" ]; then' "$EXECUTOR" ||
	fail "quick apply does not limit distance cleanup to the legacy auto value"
grep -Fq 'uci -q delete "wireless.${radio}.distance"' "$EXECUTOR" ||
	fail "quick apply does not remove legacy distance=auto"
grep -Fq 'if ! "$UCI_BIN" -q get "wireless.${radio}.legacy_rates"' "$EXECUTOR" ||
	fail "quick apply does not preserve an explicit legacy_rates choice"
grep -Fq 'if ! uci -q get wireless.radio0.channel' "$CHANNEL_DEFAULTS" ||
	fail "channel 11 default overwrites a retained channel"

# Saved Quick Settings metadata must never be replayed by service reload.
! grep -Fq 'cr6608-quicksettings-apply' "$QUICK_INIT" ||
	fail "Quick Settings service reload reapplies saved profile metadata"

# Hardware-facing CGI fallbacks read live wireless UCI before saved metadata.
grep -Fq 'wireless_resolved()' "$QUICK_CGI" || fail "Quick CGI lacks live wireless fallback"
live_fallback_line="$(grep -nF 'value="$(qget "wireless.$wireless_key")"' "$QUICK_CGI" | head -n 1 | cut -d: -f1)"
quick_fallback_line="$(grep -nF 'value="$(qget "cr6608quick.default.$quick_key")"' "$QUICK_CGI" | head -n 1 | cut -d: -f1)"
[ -n "$live_fallback_line" ] && [ -n "$quick_fallback_line" ] &&
	[ "$live_fallback_line" -lt "$quick_fallback_line" ] ||
	fail "Quick CGI reads saved metadata before live wireless UCI"
for live_field in \
	'radio0.channel channel24' \
	'radio1.channel channel5' \
	'radio0.country country24' \
	'radio1.country country5' \
	'radio0.htmode htmode24' \
	'radio1.htmode htmode5' \
	'radio0.txpower txpower_radio0' \
	'radio1.txpower txpower_radio1'; do
	grep -Fq "wireless_resolved" "$QUICK_CGI" &&
		grep -Fq "$live_field" "$QUICK_CGI" ||
		fail "Quick CGI lacks live fallback for $live_field"
done

# Quick apply seeds LDPC only when absent. Auto-channel updates wireless and
# both quick metadata stores, then restores both stores from the old live pair.
grep -Fq 'if ! "$UCI_BIN" -q get "wireless.${radio}.ldpc"' "$EXECUTOR" ||
	fail "Quick apply does not seed missing LDPC"
grep -Fq 'uci set "wireless.${radio}.ldpc=1"' "$EXECUTOR" ||
	fail "Quick apply lacks the LDPC seed value"
for channel_sync in \
	'uci set cr6608quick.default.channel24="$best24"' \
	'uci set cr6608quick.default.channel5="$best5"' \
	'uci set cr6608quick.default.channel24="$cur24"' \
	'uci set cr6608quick.default.channel5="$cur5"' \
	'uci commit cr6608quick' \
	'uci set smartap.quick.ch24="$best24"' \
	'uci set smartap.quick.ch5="$best5"' \
	'uci set smartap.quick.ch24="$cur24"' \
	'uci set smartap.quick.ch5="$cur5"' \
	'uci commit smartap'; do
	grep -Fq "$channel_sync" "$AUTOCHANNEL" ||
		fail "auto-channel synchronization is missing: $channel_sync"
done
for lock_contract in \
	'APPLY_LOCK="${CR6608_APPLY_LOCK:-/var/run/cr6608-apply.lock}"' \
	'apply_lock_owned_by_ancestor()' \
	'live_start="$(apply_process_start "$owner_pid")"' \
	'printf '\''%s %s\n'\'' "$$" "$APPLY_LOCK_START" > "$APPLY_LOCK/owner"' \
	'cleanup_exit()' \
	'trap cleanup_exit EXIT'; do
	grep -Fq "$lock_contract" "$AUTOCHANNEL" ||
		fail "auto-channel transaction lock contract is missing: $lock_contract"
done
grep -A8 -F 'cleanup_exit()' "$AUTOCHANNEL" | grep -Fq 'release_apply_lock' ||
	fail "auto-channel exit cleanup does not release the transaction lock"

auto_optimize_handler="$(sed -n '/^  auto_optimize)/,/^  run_selftest)/p' "$DASH")"
apply_best_handler="$(sed -n '/^  apply_best_channels)/,/^  save_autochannel)/p' "$DASH")"
manual_autochannel_handler="$(sed -n '/^  run_autochannel_now)/,/^  enable_stp)/p' "$DASH")"
for handler_name in auto_optimize apply_best_channels; do
	case "$handler_name" in
		auto_optimize) handler_text="$auto_optimize_handler" ;;
		*) handler_text="$apply_best_handler" ;;
	esac
	for channel_contract in \
		'stage_channel_metadata "$channel24_target" "$channel5_target"' \
		'action_commit cr6608quick' \
		'action_commit smartap'; do
		printf '%s\n' "$handler_text" | grep -Fq "$channel_contract" ||
			fail "$handler_name does not synchronize $channel_contract"
	done
done
printf '%s\n' "$manual_autochannel_handler" |
	grep -Fq 'if ! /usr/sbin/smartap-autochannel' ||
	fail "manual auto-channel ignores the worker exit status"
printf '%s\n' "$manual_autochannel_handler" |
	grep -Fq 'emit false "أفضل قناة الآن" "فشل الفحص أو التطبيق"' ||
	fail "manual auto-channel still reports a failed worker as success"

for obsolete_power_helper in cr6608-force-txpower30 cr6608-force-txpower38; do
	[ ! -e "$ROOT/files/usr/sbin/$obsolete_power_helper" ] ||
		fail "recurring fixed-power helper remains: $obsolete_power_helper"
done
[ ! -e "$ROOT/files/etc/hotplug.d/ieee80211/99-cr6608-txpower" ] || fail "recurring fixed-power hotplug remains"
grep -Fq '[ "$1" -ge 1 ]' "$TX_LIB" || fail "TX library lacks the 1 dBm lower bound"
grep -Fq '[ "$1" -le 38 ]' "$TX_LIB" || fail "TX library lacks the 38 dBm upper bound"
grep -Fq '[ "$1" -ge 1 ]' "$EXECUTOR" || fail "quick executor lacks the 1 dBm lower bound"
grep -Fq '[ "$1" -le 38 ]' "$EXECUTOR" || fail "quick executor lacks the 38 dBm upper bound"
grep -Fq -- '--probe-3800' "$TX_VERIFY" || fail "explicit 3800 mBm probe is absent"
grep -Fq 'set txpower fixed 3800' "$TX_VERIFY" || fail "verification tool does not test cfg80211"
grep -Fq 'set txpower fixed 3800' "$FULL_TX_VERIFY" || fail "full-channel verifier does not test cfg80211"
grep -Fq 'set txpower fixed 3800' "$COUNTRY_SCAN" || fail "country scanner does not test cfg80211"
fixed_users="$(grep -RIl 'set txpower fixed 3800' "$ROOT/files" 2>/dev/null | sort || true)"
expected_fixed_users="$(printf '%s\n' "$TX_VERIFY" "$FULL_TX_VERIFY" "$COUNTRY_SCAN" | sort)"
[ "$fixed_users" = "$expected_fixed_users" ] || \
	fail "fixed 3800 mBm appears outside the three explicit verification tools"
grep -Fq 'xiaomi,mi-router-cr6608' "$TX_DEFAULTS" || fail "first-boot TX defaults are not board-gated"
grep -Fq 'wifi-device' "$TX_DEFAULTS" || fail "first-boot TX defaults do not discover radios dynamically"
grep -Fq 'if ! uci -q get "wireless.${radio}.txpower"' "$TX_DEFAULTS" || fail "first-boot TX defaults overwrite saved power"
for marker in \
	'profile=ul-muru-forced-lab-v1' \
	'radio_policy=ul-muru-persistent-mask15-38dbm-lab'; do
	grep -Fq "$marker" "$TX_DEFAULTS" ||
		fail "first-boot TX defaults do not recognize forced UL-MURU LAB policy: $marker"
done
grep -Fq "method: 'txpowerlist'" "$LUCI_QUICK" || fail "LuCI does not read the driver TX power list"
grep -Fq "method: 'info'" "$LUCI_QUICK" || fail "LuCI does not read runtime wireless information"
grep -Fq "Requested=" "$LUCI_QUICK" || fail "LuCI does not identify requested power"
grep -Fq "Regulatory+channel max=" "$LUCI_QUICK" || fail "LuCI does not identify the channel maximum"
grep -Fq "Driver max=" "$LUCI_QUICK" || fail "LuCI does not identify the driver maximum"
grep -Fq "Current=" "$LUCI_QUICK" || fail "LuCI does not identify current power"
grep -Fq "Status=" "$LUCI_QUICK" || fail "LuCI does not identify the acceptance status"
grep -Fq "callWirelessStatus: rpc.declare" "$LUCI_QUICK" || fail "LuCI does not query netifd radio state"
grep -Fq "object: 'network.wireless'" "$LUCI_QUICK" || fail "LuCI netifd status RPC is missing"
"$PYTHON_BIN" - "$RPC_ACL" <<'PY' || fail "LuCI ACL does not grant the netifd wireless status RPC"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    document = json.load(stream)

methods = (
    document
    .get("luci-app-cr6608-quicksettings", {})
    .get("read", {})
    .get("ubus", {})
    .get("network.wireless")
)
if methods != ["status"]:
    raise SystemExit(1)
PY
grep -Fq "netifd/hostapd did not create a runtime interface" "$LUCI_QUICK" ||
	fail "LuCI does not explain an inactive radio"
grep -Fq "window.location.port ? ':' + window.location.port : ''" "$LUCI_QUICK" ||
	fail "Safe Apply redirect drops a custom management port"
grep -Fq "o.datatype = 'range(1,38)'" "$LUCI_QUICK" || fail "LuCI power input is not bounded to 1-38 dBm"
! grep -Fq "38 dBm requested maximum" "$LUCI_QUICK" || fail "LuCI renders a fixed success label instead of telemetry"

# Every bridge owner resolves br-lan by name. WAN remains reserved and never
# returns to the LAN bridge through a positional @device[0] assumption.
for bridge_owner in "$EXECUTOR" "$VLAN_LIB" "$DASH" "$SECURITY_APPLY"; do
	! grep -Fq 'network.@device[0]' "$bridge_owner" || fail "positional bridge ownership remains in $bridge_owner"
done
grep -Fq 'Every access VLAN needs a tagged path' "$VLAN_LIB" || fail "orphan access VLANs are not rejected"
grep -Fq 'WAN is reserved for the uplink/PPPoE client' "$DASH" || fail "WAN reservation is not exposed by the switch controls"
grep -Fq 'runtime_ap_ifaces()' "$SECURITY_APPLY" || fail "DHCP guard still assumes fixed AP interface names"
grep -Fq "option stp '0'" "$NETWORK_CFG" || fail "clean image does not forward DSA LAN ports immediately"
if grep -Fq "option forward_delay '2'" "$NETWORK_CFG"; then
	fail "clean image unexpectedly delays DSA LAN forwarding"
fi
grep -Fq 'uci set "$bridge.stp=$want"' "$SECURITY_APPLY" || fail "loop guard does not own bridge STP state"
grep -Fq '[ "$owner" = smartap ] || return 0' "$SECURITY_APPLY" || fail "default security save can overwrite LuCI STP"
grep -Fq 'uci set "$bridge.forward_delay=2"' "$SECURITY_APPLY" || fail "explicit loop guard cannot enable its short STP delay"
grep -Fq 'uci -q delete "$bridge.forward_delay"' "$SECURITY_APPLY" || fail "disabled loop guard does not remove the STP delay"
grep -Fq 'configured_ap_sections()' "$SECURITY_APPLY" ||
	fail "Wi-Fi isolation does not discover all configured AP sections"
if grep -Eq 'wireless\.wifinet[01]\.isolate' "$SECURITY_APPLY"; then
	fail "Wi-Fi isolation is still tied to fixed wifinet section names"
fi
grep -Fq '[ "$device" = "br-lan" ] || continue' "$VLAN_LIB" ||
	fail "bridge-VLAN cleanup is not scoped to br-lan"
if grep -Fq 'cr6608_strip_reserved_wan_from_vlans' "$VLAN_LIB"; then
	fail "global WAN stripping can modify bridge-VLANs owned by another bridge"
fi
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
grep -A18 -F 'clear_runtime() {' "$SECURITY_APPLY" | grep -Fq 'remove_bridge_guard' || fail "runtime cleanup bypasses verified nft removal"
grep -Fq 'network_changed=0' "$EXECUTOR" || fail "executor does not track network-device changes for fw4"
grep -Fq '[ "$network_changed" = "1" ] || [ "$pre_fw" !=' "$EXECUTOR" || fail "fw4 is not reloaded when LAN moves between br-lan and br-lan.1"
grep -Fq 'transaction_restore_runtime()' "$EXECUTOR" || fail "transaction rollback lacks a runtime restore owner"
grep -A35 -F 'transaction_restore_runtime()' "$EXECUTOR" | grep -Fq '"$INITD_DIR/firewall" reload' || fail "rollback runtime restore leaves stale fw4 bindings"
grep -A35 -F 'transaction_rollback()' "$EXECUTOR" | grep -Fq 'transaction_restore_runtime || failed=1' || fail "signal/failure rollback does not restore runtime services"
grep -A35 -F 'transaction_rollback()' "$EXECUTOR" | grep -Fq '[ "$failed" = "0" ] && [ "$DRY_RUN" != "1" ]' || fail "dry-run rollback still reloads runtime services"
grep -A35 -F 'transaction_rollback()' "$EXECUTOR" | grep -Fq 'uci -q revert "$pkg" >/dev/null 2>&1 || failed=1' ||
	fail "quick-settings rollback can report success with a surviving UCI delta"
grep -A8 -F 'safe_cancel()' "$EXECUTOR" | grep -Fq 'confirm "$SAFE_TOKEN" >/dev/null 2>&1 || return 1' ||
	fail "quick-settings rollback hides Safe Apply cancellation failure"
grep -A20 -F 'royal_restore_backup()' "$DASH" | grep -Fq 'uci -q revert "$_royal_pkg" >/dev/null 2>&1 || _royal_restore_rc=1' ||
	fail "Smart AP rollback can report success with a surviving UCI delta"
grep -A45 -F 'transaction_restore_runtime()' "$EXECUTOR" | grep -Fq 'cr6608-safe-wifi-reload" --verify-only 30 all' ||
	fail "quick-settings rollback does not verify restored netifd/hostapd runtime"
grep -Fq 'APPLY_LOCK="${CR6608_APPLY_LOCK:-/var/run/cr6608-apply.lock}"' "$EXECUTOR" ||
	fail "quick-settings executor does not share the global configuration lock"
grep -A14 -F 'safe_arm_transaction()' "$EXECUTOR" | grep -Fq 'safe_timeout=720' ||
	fail "quick-settings Safe Apply expires before DFS CAC can finish"
grep -A14 -F 'safe_arm_transaction()' "$EXECUTOR" | grep -Fq 'auto|52|56|60|64' ||
	fail "quick-settings Safe Apply does not protect auto-channel ACS/CAC with the long window"
grep -Fq "printf 'version=6" "$SAFE" || fail "Safe Apply does not write the boot-bound monotonic v6 schema"
grep -Fq 'CR6608_SAFE_UPTIME_FILE:-/proc/uptime' "$SAFE" || fail "Safe Apply is not anchored to /proc/uptime"
grep -Fq 'CR6608_SAFE_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id' "$SAFE" || fail "Safe Apply is not bound to the current boot identity"
grep -Fq 'armed_boot_id=%s' "$SAFE" || fail "Safe Apply state does not persist its boot identity"
grep -Fq 'timing_source=monotonic' "$SAFE" || fail "Safe Apply v6 status does not report monotonic timing"
grep -A12 -F 'do_confirm()' "$SAFE" | grep -Fq 'state_remaining' ||
	fail "Safe Apply can confirm a token without checking its monotonic deadline"
for timing_field in armed_epoch armed_uptime timeout remaining timing_source; do
	grep -Fq "${timing_field}=%s" "$SAFE" || fail "Safe Apply status does not expose $timing_field"
done
grep -Fq "option script_timeout '750'" "$UHTTPD_CFG" ||
	fail "uhttpd can terminate a valid auto/DFS Quick Apply before ACS/CAC finishes"
grep -Fq "[ \"\$script_timeout\" -lt 750 ]" "$SAFE_DEFAULTS" ||
	fail "retained uhttpd configurations are not upgraded for long guarded applies"
grep -Fq 'rollback_timeout_s' "$CGI" || fail "Quick Apply response omits the guarded timeout"
grep -Fq 'rollback_remaining_s' "$CGI" || fail "Quick Apply response omits the guarded remaining time"
grep -Fq 'requestJson: function(url, options, timeoutMs)' "$LUCI_QUICK" ||
	fail "LuCI Quick Settings lacks a body-bounded request helper"
! grep -Fq 'needsDfsWindow(payload.channel24' "$LUCI_QUICK" ||
	fail "LuCI Quick Settings incorrectly gives 2.4 GHz auto a DFS-length timeout"
grep -Fq 'needsDfsWindow(payload.channel5, payload.radio1_enabled)' "$LUCI_QUICK" ||
	fail "LuCI Quick Settings ignores long 5 GHz auto/DFS applies"
grep -Fq 'reportedRemaining = Number(result && result.rollback_remaining_s)' "$LUCI_QUICK" ||
	fail "LuCI Quick Settings still uses a fixed rollback countdown"
grep -Fq 'recoverPendingApply: function(payload)' "$LUCI_QUICK" ||
	fail "LuCI Quick Settings cannot recover a Safe Apply after a lost response"
grep -Fq "'/cgi-bin/dashctl?section=apply_status'" "$LUCI_QUICK" ||
	fail "LuCI Quick Settings does not query the authoritative apply state"
grep -Fq 'confirmInFlight' "$LUCI_QUICK" || fail "LuCI Quick Settings allows duplicate confirmations"
command -v node >/dev/null 2>&1 || fail "Node.js is required for the Quick Settings runtime gate"
node --check "$ROOT/tests/test-quicksettings-safe-apply.js" >/dev/null ||
	fail "Quick Settings Safe Apply runtime test has invalid JavaScript"
node "$ROOT/tests/test-quicksettings-safe-apply.js" >/dev/null ||
	fail "Quick Settings Safe Apply runtime behavior failed"
grep -A4 -F "form.Flag, 'clear_previous'" "$LUCI_QUICK" | grep -Fq "o.default = '0';" ||
	fail "explicit cleanup/takeover is not off by default"
! grep -A4 -F "form.Flag, 'clear_previous'" "$LUCI_QUICK" | grep -Fq "o.readonly = true" ||
	fail "explicit cleanup/takeover cannot be selected by the operator"
grep -A18 -F 'transaction_begin()' "$EXECUTOR" | grep -Fq '/etc/smartap-pending-rollback' ||
	fail "quick-settings creates a backup while another Safe Apply is pending"
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
grep -Fq 'TX_OLD_UHTTPD_RUNTIME' "$EXECUTOR" || fail "Quick Settings rollback does not preserve uhttpd runtime state"
grep -Fq 'TX_OLD_DROPBEAR_RUNTIME' "$EXECUTOR" || fail "Quick Settings rollback does not preserve dropbear runtime state"
grep -A30 -F 'safe_arm_transaction() {' "$EXECUTOR" | grep -Fq '"$TX_OLD_DROPBEAR_RUNTIME"' || fail "Quick Settings still uses the legacy Safe Apply service-state schema"

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

wizard_arm_line="$(grep -n 'arm_rollback "$backup" || royal_abort_apply "Could not arm the rollback guard."' "$DASH" | tail -n 1 | cut -d: -f1)"
wizard_commit_line="$(grep -n 'royal_commit_packages wireless network dhcp firewall smartap cr6608quick' "$DASH" | tail -n 1 | cut -d: -f1)"
wizard_store_line="$(grep -n 'store_royal_config || royal_abort_apply' "$DASH" | tail -n 1 | cut -d: -f1)"
[ -n "$wizard_arm_line" ] && [ -n "$wizard_commit_line" ] && \
	[ -n "$wizard_store_line" ] && [ "$wizard_arm_line" -lt "$wizard_store_line" ] && \
	[ "$wizard_arm_line" -lt "$wizard_commit_line" ] || \
	fail "Quick Setup mutates config before rollback arming"
wizard_reset_line="$(grep -n 'royal_reset_policy || royal_abort_apply "Could not apply the reset-button policy."' "$DASH" | tail -n 1 | cut -d: -f1)"
[ -n "$wizard_reset_line" ] && [ "$wizard_arm_line" -lt "$wizard_reset_line" ] || fail "Quick Setup mutates reset-button policy before rollback arming"
reset_arm_line="$(grep -n 'arm_rollback "$backup" || royal_abort_apply "Could not arm the rollback guard."' "$DASH" | head -n 1 | cut -d: -f1)"
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
grep -Fq 'reset_plain_switch_policy' "$EXECUTOR" || fail "unified Quick Setup does not clear stale per-port VLAN policy"
grep -Fq 'royal_reset_plain_switch_policy' "$DASH" || fail "Smart AP Quick Setup does not clear stale per-port VLAN policy"

# Critical service writers must participate in token-bound Safe Apply. These
# checks cover firewall, DNS/DHCP, STP, guest Wi-Fi, MAC rules, and IPTV.
grep -Fq 'command -v nft' "$DASH" || fail "per-client policer does not verify its nftables backend"
! grep -Fq 'command -v tc >/dev/null 2>&1 || { emit false "Speed limit"' "$DASH" || \
	fail "per-client nftables policer is still incorrectly gated on tc"
grep -Fq 'WAN SQM/CAKE' "$DASH" || fail "per-client policing is not distinguished from WAN queueing"
grep -Fq 'bss_transition=' "$DASH" || fail "dashboard performance apply does not enable 802.11v through bss_transition"
! grep -Fq 'ieee80211v=' "$DASH" || fail "dashboard still relies on the ignored ieee80211v UCI key"

# Security-sensitive device writers accept only exact unicast MAC syntax. The
# validator may lowercase a syntactically complete value, but must not turn
# hostile/malformed text into a different valid address by deleting bytes.
eval "$(sed -n '/^canonical_unicast_mac()/,/^}/p' "$DASH")"
[ "$(canonical_unicast_mac 'AA:BC:DE:F0:12:34')" = 'aa:bc:de:f0:12:34' ] ||
	fail "canonical MAC validator does not normalize a valid exact address"
for bad_mac in \
	'00:00:00:00:00:00' 'ff:ff:ff:ff:ff:ff' \
	'01:00:5e:00:00:01' '33:33:00:00:00:01' 'ab:00:00:00:00:02' \
	'aabbccddeeff' 'aa-bb-cc-dd-ee-ff' 'aa:bb:cc:dd:ee' \
	'aa:bb:cc:dd:ee:ff00' 'aa:bb:cc:dd:ee:fg' ' aa:bb:cc:dd:ee:fe'; do
	if canonical_unicast_mac "$bad_mac" >/dev/null 2>&1; then
		fail "canonical MAC validator accepted hostile value: $bad_mac"
	fi
done
block_contract="$(sed -n '/^  block_mac)/,/^  unblock_mac)/p' "$DASH")"
unblock_contract="$(sed -n '/^  unblock_mac)/,/^  set_client_limit)/p' "$DASH")"
limit_contract="$(sed -n '/^  set_client_limit)/,/^  clear_client_limits)/p' "$DASH")"
for writer_contract in "$block_contract" "$unblock_contract" "$limit_contract"; do
	printf '%s\n' "$writer_contract" | grep -Fq 'canonical_unicast_mac "$(param mac)"' ||
		fail "block/unblock/limit writer bypasses the canonical unicast MAC validator"
done
[ "$(printf '%s\n' "$block_contract" | grep -Fc 'smartap_qos_apply_bounded')" -ge 2 ] ||
	fail "existing block rule does not heal bridged enforcement idempotently"
printf '%s\n' "$unblock_contract" | grep -Fq 'smartap_qos_apply_bounded || {' ||
	fail "unblock does not fail closed when bridged enforcement cannot be rebuilt"
for writer_contract in "$block_contract" "$unblock_contract"; do
	! printf '%s\n' "$writer_contract" | grep -Fq 'smartap-qos-apply >/dev/null 2>&1 || true' ||
		fail "MAC policy writer still ignores smartap-qos-apply failure"
	printf '%s\n' "$writer_contract" | grep -Fq 'action_rollback_pending' ||
		fail "MAC policy writer does not request immediate rollback after bridge-policy failure"
done
grep -Fq 'run_limit "${CR6608_SERVICE_TIMEOUT:-45}" /usr/sbin/smartap-qos-apply' "$DASH" ||
	fail "MAC bridge policy apply is not bounded"
grep -Fq 'previous policy restored' "$ROOT/files/usr/sbin/smartap-qos-apply" || \
	fail "per-client policer cannot restore its previous rules after a failed update"
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
guest_network_line="$(grep -n 'action_reload "Guest Wi-Fi" "Network reload failed or timed out" /etc/init.d/network reload' "$DASH" | tail -n 1 | cut -d: -f1)"
guest_wifi_line="$(grep -n 'action_wifi_reload "Guest Wi-Fi" "Wi-Fi runtime verification failed"' "$DASH" | tail -n 1 | cut -d: -f1)"
guest_firewall_line="$(grep -n 'action_reload "Guest Wi-Fi" "Firewall reload failed"' "$DASH" | tail -n 1 | cut -d: -f1)"
[ -n "$guest_network_line" ] && [ -n "$guest_wifi_line" ] && [ -n "$guest_firewall_line" ] && \
	[ "$guest_network_line" -lt "$guest_wifi_line" ] && [ "$guest_wifi_line" -lt "$guest_firewall_line" ] || \
	fail "Guest Wi-Fi does not settle network/Wi-Fi before rebuilding fw4"

# Exercise the private runtime primitive without executing a real network
# transaction. A reserved legacy filename and a symlinked runtime directory
# must never redirect the root snapshot write.
case "$(uname -s)" in
	MINGW*|MSYS*) : ;; # Windows ACL projection cannot represent the Linux 0700 contract.
	*)
TEMP_HARDEN_TMP="$(mktemp -d)"
chmod 0700 "$TEMP_HARDEN_TMP"
sed -n '/^quick_runtime_dir_secure()/,/^run_without_dashboard_fds()/p' "$EXECUTOR" |
	sed '$d' >"$TEMP_HARDEN_TMP/runtime-functions.sh"
cat >"$TEMP_HARDEN_TMP/runtime-driver.sh" <<'EOF'
#!/bin/sh
set -eu
QUICK_RUNTIME_DIR="$1"
SAFE_RUNTIME_DIR="$QUICK_RUNTIME_DIR"
. "$2"
quick_runtime_dir_secure "$QUICK_RUNTIME_DIR"
created="$(quick_mktemp wireless-preapply)"
[ -f "$created" ] && [ ! -L "$created" ]
[ "$(stat -c '%a' "$created")" = 600 ]
printf '%s\n' "$created"
EOF
chmod 0700 "$TEMP_HARDEN_TMP/runtime-driver.sh"
mkdir "$TEMP_HARDEN_TMP/private"
chmod 0700 "$TEMP_HARDEN_TMP/private"
printf 'victim-unchanged\n' >"$TEMP_HARDEN_TMP/victim"
ln -s "$TEMP_HARDEN_TMP/victim" "$TEMP_HARDEN_TMP/private/cr6608-wireless-preapply.$$"
created_path="$(sh "$TEMP_HARDEN_TMP/runtime-driver.sh" "$TEMP_HARDEN_TMP/private" "$TEMP_HARDEN_TMP/runtime-functions.sh")" ||
	fail "private Quick Settings runtime rejected a secure directory"
[ "$created_path" != "$TEMP_HARDEN_TMP/private/cr6608-wireless-preapply.$$" ] ||
	fail "Quick Settings reused a hostile predictable filename"
grep -Fqx 'victim-unchanged' "$TEMP_HARDEN_TMP/victim" ||
	fail "Quick Settings private temp creation clobbered a symlink target"
ln -s "$TEMP_HARDEN_TMP/private" "$TEMP_HARDEN_TMP/private-link"
if sh "$TEMP_HARDEN_TMP/runtime-driver.sh" "$TEMP_HARDEN_TMP/private-link" \
	"$TEMP_HARDEN_TMP/runtime-functions.sh" >/dev/null 2>&1; then
	fail "Quick Settings accepted a symlinked runtime directory"
fi
rm -rf -- "$TEMP_HARDEN_TMP"
		;;
esac

# The live DHCP guard replacement is one checked nft transaction. An apply-only
# failure keeps the old table, while a disabled-policy delete failure is visible
# to the caller instead of reporting stale drops as removed.
SECURITY_HARDEN_TMP="$(mktemp -d)"
sed -n '/^bridge_guard_absent()/,/^apply_dhcp_guard()/p' "$SECURITY_APPLY" | sed '$d' |
	sed -e 's|\[ ! -x /usr/sbin/nft \]|false|' -e 's|\[ -x /usr/sbin/nft \]|true|' >"$SECURITY_HARDEN_TMP/functions.sh"
cat >"$SECURITY_HARDEN_TMP/driver.sh" <<'EOF'
#!/bin/sh
set -eu
scenario="$1"
state_dir="$2"
. "$3"
action="${4:-apply}"
STATE=smartap
PORTS='lan1 lan2 lan3'
g() {
	case "$1" in
		smartap.security.enabled) [ "$scenario" = disabled ] && printf '0\n' || printf '1\n' ;;
		smartap.security.rogue_dhcp_guard) printf '1\n' ;;
		smartap.*.isolate) printf '0\n' ;;
		smartap.*.vlan_mode) printf 'plain\n' ;;
		smartap.*.vlan) printf '1\n' ;;
	esac
}
runtime_ap_ifaces() { printf 'phy0-ap0\n'; }
log() { printf '%s\n' "$*" >>"$state_dir/logger"; }
nft() {
	printf '%s\n' "$*" >>"$state_dir/calls"
	case "$1" in
		list)
			[ ! -e "$state_dir/fail-list" ] || return 44
			[ "$*" != 'list tables bridge' ] || return 0
			[ -e "$state_dir/table" ]
			;;
		delete)
			[ ! -e "$state_dir/fail-delete" ] || return 42
			rm -f "$state_dir/table"
			;;
		-c) cat >"$state_dir/check" ;;
		-f)
			cat >"$state_dir/apply"
			[ ! -e "$state_dir/fail-apply" ] || return 43
			: >"$state_dir/table"
			;;
		*) return 64 ;;
	esac
}
case "$action" in clear) clear_runtime ;; *) apply_bridge_guard ;; esac
EOF
chmod 0700 "$SECURITY_HARDEN_TMP/driver.sh"
: >"$SECURITY_HARDEN_TMP/table"
: >"$SECURITY_HARDEN_TMP/fail-apply"
if sh "$SECURITY_HARDEN_TMP/driver.sh" enabled "$SECURITY_HARDEN_TMP" \
	"$SECURITY_HARDEN_TMP/functions.sh"; then
	fail "security nft apply failure unexpectedly succeeded"
fi
[ -e "$SECURITY_HARDEN_TMP/table" ] || fail "failed nft replacement removed the previous DHCP guard"
cmp -s "$SECURITY_HARDEN_TMP/check" "$SECURITY_HARDEN_TMP/apply" ||
	fail "security nft check and apply did not consume identical transactions"
grep -Fqx 'delete table bridge smartap_guard' "$SECURITY_HARDEN_TMP/check" ||
	fail "security nft replacement is not an atomic delete+create transaction"
if grep -Fqx 'delete table bridge smartap_guard' "$SECURITY_HARDEN_TMP/calls"; then
	fail "security nft replacement deletes the live table outside its checked batch"
fi
rm -f "$SECURITY_HARDEN_TMP/fail-apply"
: >"$SECURITY_HARDEN_TMP/fail-list"
if sh "$SECURITY_HARDEN_TMP/driver.sh" disabled "$SECURITY_HARDEN_TMP" \
	"$SECURITY_HARDEN_TMP/functions.sh"; then
	fail "disabled security hid an nft query failure"
fi
[ -e "$SECURITY_HARDEN_TMP/table" ] || fail "nft query failure changed mock live state"
if sh "$SECURITY_HARDEN_TMP/driver.sh" disabled "$SECURITY_HARDEN_TMP" \
	"$SECURITY_HARDEN_TMP/functions.sh" clear; then
	fail "clear-runtime hid an nft query failure"
fi
[ -e "$SECURITY_HARDEN_TMP/table" ] || fail "clear-runtime query failure changed mock live state"
rm -f "$SECURITY_HARDEN_TMP/fail-list"
: >"$SECURITY_HARDEN_TMP/fail-delete"
if sh "$SECURITY_HARDEN_TMP/driver.sh" disabled "$SECURITY_HARDEN_TMP" \
	"$SECURITY_HARDEN_TMP/functions.sh"; then
	fail "disabled security hid a live nft deletion failure"
fi
[ -e "$SECURITY_HARDEN_TMP/table" ] || fail "failed disabled-policy removal changed mock live state"
rm -f "$SECURITY_HARDEN_TMP/fail-delete"
sh "$SECURITY_HARDEN_TMP/driver.sh" disabled "$SECURITY_HARDEN_TMP" \
	"$SECURITY_HARDEN_TMP/functions.sh" || fail "verified security nft removal failed"
[ ! -e "$SECURITY_HARDEN_TMP/table" ] || fail "security nft table remained after successful removal"
rm -rf -- "$SECURITY_HARDEN_TMP"

sh "$UCI_SYNC_RUNTIME" | grep -qx 'uci_sync_runtime=pass' ||
	fail "UCI synchronization runtime tests failed"

printf 'quicksettings_contracts=pass\n'
