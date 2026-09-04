#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NETWORK="$ROOT/files/etc/config/network"
DHCP="$ROOT/files/etc/config/dhcp"
DEFAULTS="$ROOT/files/etc/uci-defaults/95-cr6608-dhcp-off"
SYSCTL="$ROOT/files/etc/sysctl.d/99-smartap-perf.conf"
IPV4_ONLY="$ROOT/files/usr/sbin/cr6608-ipv4-only"
IPV4_ONLY_INIT="$ROOT/files/etc/init.d/cr6608-ipv4-only"
IPV4_ONLY_HOTPLUG="$ROOT/files/etc/hotplug.d/net/90-cr6608-ipv4-only"
RUNTIME_SERVICES="$ROOT/files/etc/uci-defaults/99-cr6608-runtime-services"
UHTTPD="$ROOT/files/etc/config/uhttpd"
EXECUTOR="$ROOT/files/usr/sbin/cr6608-quicksettings-apply"
CGI="$ROOT/files/www/cgi-bin/cr6608-quick-apply"
VIEW="$ROOT/files/www/luci-static/resources/view/cr6608/quicksettings.js"
QUICK="$ROOT/files/etc/config/cr6608quick"
RETAIL_QUICK="$ROOT/profiles/retail/files/etc/config/cr6608quick"
UL_LAB_QUICK="$ROOT/profiles/ul-lab/files/etc/config/cr6608quick"
DASH="$ROOT/files/www/cgi-bin/dashctl"

fail() { printf 'ipv6 fixed-off contract failed: %s\n' "$*" >&2; exit 1; }

# This is a complete IPv4-only product policy: the kernel stack, listeners,
# routed interfaces, prefix delegation and advertisement services stay off.
[ "$(grep -c '^net\.ipv6\.conf\..*\.disable_ipv6=1$' "$SYSCTL")" -eq 3 ] ||
	fail 'packaged sysctl policy does not disable all/default/loopback IPv6'
[ -x "$IPV4_ONLY" ] || fail 'runtime IPv4-only verifier is not executable'
[ -x "$IPV4_ONLY_INIT" ] || fail 'runtime IPv4-only service is not executable'
[ -x "$IPV4_ONLY_HOTPLUG" ] || fail 'net hotplug IPv4-only guard is not executable'
grep -Fq 'for cia_path in "$IPV6_CONF_ROOT"/*/disable_ipv6' "$IPV4_ONLY" ||
	fail 'runtime IPv4-only guard does not sweep every existing interface'
grep -Fq '/usr/sbin/cr6608-ipv4-only interface "$device"' "$IPV4_ONLY_HOTPLUG" ||
	fail 'new interfaces are not forced through the IPv4-only guard'
grep -Fq 'for service in cr6608-ipv4-only smartap-qos' "$RUNTIME_SERVICES" ||
	fail 'runtime IPv4-only service is not enabled during migration'
! grep -Fq '[::]' "$UHTTPD" || fail 'packaged Web listener still exposes IPv6'
lan_block="$(awk '
	$1 == "config" { in_lan = ($2 == "interface" && $3 == "\047lan\047") }
	in_lan { print }
' "$NETWORK")"
printf '%s\n' "$lan_block" | grep -Fq "option ipv6 '0'" ||
	fail 'packaged LAN does not explicitly keep IPv6 routing off'
printf '%s\n' "$lan_block" | grep -Fq "option delegate '0'" ||
	fail 'packaged LAN can delegate an IPv6 prefix'
grep -Fq "option filter_aaaa '1'" "$DHCP" ||
	fail 'packaged resolver does not filter AAAA under the fixed-off policy'
odhcpd_block="$(sed -n "/^config odhcpd 'odhcpd'/,/^config /p" "$DHCP")"
printf '%s\n' "$odhcpd_block" | grep -Fq "option disabled '1'" ||
	fail 'packaged odhcpd service is not disabled'

# If a preserved DHCP section exists, all IPv6-originating roles must be off.
dhcp_lan_block="$(sed -n "/^config dhcp 'lan'/,/^config /p" "$DHCP")"
if [ -n "$dhcp_lan_block" ]; then
	printf '%s\n' "$dhcp_lan_block" | grep -Fq "option dhcpv6 'disabled'" ||
		fail 'packaged LAN DHCP section can still serve DHCPv6'
	printf '%s\n' "$dhcp_lan_block" | grep -Fq "option ra 'disabled'" ||
		fail 'packaged LAN DHCP section can still originate RA'
fi

for quick_profile in "$QUICK" "$RETAIL_QUICK" "$UL_LAB_QUICK"; do
	grep -Fq "option ipv6_enabled '0'" "$quick_profile" ||
		fail "IPv6 fixed-off state is absent from $quick_profile"
done

# Neither UI may expose an On switch.  The compatibility CGI may still parse
# the old field, but it must explicitly reject 1 and pass only constant 0.
! grep -Fq "'ipv6_enabled'" "$VIEW" || fail 'LuCI still exposes an IPv6 toggle'
wizard_view="$(sed -n '/^  wizard)/,/^  specs)/p' "$DASH")"
! printf '%s\n' "$wizard_view" | grep -Fq 'ipv6_enabled|' ||
	fail 'Smart AP wizard still exposes an IPv6 toggle'
grep -Fq 'ipv6_request="$(pick ipv6_enabled)"' "$CGI" ||
	fail 'legacy direct IPv6 field is not inspected'
grep -Fq "[ \"\$ipv6_request\" = '0' ] || fail_request" "$CGI" ||
	fail 'Quick Settings does not reject a direct IPv6=1 request'
grep -Fq "ipv6='0'" "$CGI" || fail 'Quick Settings does not pass constant IPv6 Off'
grep -Fq 'json_add_string ipv6_enabled "$ipv6"' "$CGI" ||
	fail 'Quick Settings executor payload omits the fixed policy value'

# The executor is the second trust boundary.  A stale store or hand-written
# executor request containing 1 must be ignored before any UCI mutation.
grep -Fq "ipv6_enabled='0'" "$EXECUTOR" ||
	fail 'executor does not override stale/direct IPv6 values with Off'
executor_force_line="$(grep -nF "ipv6_enabled='0'" "$EXECUTOR" | head -n1 | cut -d: -f1)"
executor_store_line="$(grep -nF 'uci set "$CFG.ipv6_enabled=$ipv6_enabled"' "$EXECUTOR" | head -n1 | cut -d: -f1)"
[ -n "$executor_force_line" ] && [ -n "$executor_store_line" ] &&
	[ "$executor_force_line" -lt "$executor_store_line" ] ||
	fail 'executor persists IPv6 before forcing the fixed-off value'
grep -Fq 'uci set "smartap.quick.ipv6_enabled=$ipv6_enabled"' "$EXECUTOR" ||
	fail 'executor does not synchronize Smart AP IPv6 store'

# Smart AP ignores a direct POST value at parameter load and then writes both
# stores from the forced zero.  It must also stage the L3/service policy inside
# the same Safe Apply transaction.
royal_load="$(sed -n '/^load_royal_params() {/,/^}/p' "$DASH")"
printf '%s\n' "$royal_load" | grep -Fq 'ipv6_enabled="0"' ||
	fail 'Smart AP does not force a direct IPv6 request to Off'
! printf '%s\n' "$royal_load" | grep -Fq 'param ipv6_enabled' ||
	fail 'Smart AP still accepts the direct IPv6 toggle value'
royal_store="$(sed -n '/^store_royal_config() {/,/^}/p' "$DASH")"
printf '%s\n' "$royal_store" | grep -Fq 'smartap.quick.ipv6_enabled=$ipv6_enabled' ||
	fail 'Smart AP does not synchronize its fixed-off store'
printf '%s\n' "$royal_store" | grep -Fq 'cr6608quick.default.ipv6_enabled=$ipv6_enabled' ||
	fail 'Smart AP does not synchronize the unified fixed-off store'
royal_policy="$(sed -n '/^royal_stage_ipv6_policy() {/,/^}/p' "$DASH")"
royal_apply="$(sed -n '/^  apply_royal)/,/^  save_quick)/p' "$DASH")"
printf '%s\n' "$royal_apply" | grep -Fq 'royal_stage_ipv6_policy || royal_abort_apply' ||
	fail 'Smart AP does not stage IPv6 Off transactionally'

# Execute the Smart AP policy with the only reachable value.  This catches
# regressions where stores say 0 while WAN/LAN/odhcpd is accidentally enabled.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ipv6-off.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
trace="$TMP/trace"
royal_set() { printf 'set %s\n' "$1" >>"$trace"; }
royal_delete() { printf 'delete %s\n' "$1" >>"$trace"; }
uci() {
	case "$*" in
		'-q get dhcp.lan') return 0 ;;
		'-q get dhcp.odhcpd') return 1 ;;
		*) return 1 ;;
	esac
}
eval "$royal_policy"
program_mode=pppoe_ap
ipv6_enabled=0
royal_values_validated=1
royal_store_error=''
: >"$trace"
royal_stage_ipv6_policy || fail 'Smart AP rejected its fixed-off policy'
for expected in \
	'set network.lan.ipv6=0' \
	'set network.wan.ipv6=0' \
	'set network.lan.delegate=0' \
	'set dhcp.lan.dhcpv6=disabled' \
	'set dhcp.lan.ra=disabled' \
	'set dhcp.odhcpd.disabled=1' \
	'set dhcp.@dnsmasq[0].filter_aaaa=1'; do
	grep -Fqx "$expected" "$trace" || fail "Smart AP policy missed: $expected"
done
! grep -Eq 'ipv6=auto|delegate=1|dhcpv6=server|ra=server|odhcpd.disabled=0' "$trace" ||
	fail 'Smart AP fixed-off transaction also staged an IPv6-on value'

# Upgrade/factory migration must erase every preserved On state, keep the
# service stopped, and enforce the IPv4-only kernel policy.
for expected in \
	'ipv6_policy_enabled=0' \
	'uset cr6608quick.default.ipv6_enabled=0' \
	'uset smartap.quick.ipv6_enabled=0' \
	'uset network.lan.ipv6=0' \
	'uset network.lan.delegate=0' \
	'uset dhcp.odhcpd.disabled=1' \
	'uset dhcp.lan.dhcpv6=disabled' \
	'uset dhcp.lan.ra=disabled'; do
	grep -Fq "$expected" "$DEFAULTS" || fail "migration fixed-off writer absent: $expected"
done
for expected in \
	'net.ipv6.conf.all.disable_ipv6=1' \
	'net.ipv6.conf.default.disable_ipv6=1' \
	'net.ipv6.conf.lo.disable_ipv6=1'; do
	grep -Fq "$expected" "$DEFAULTS" || fail "migration sysctl writer absent: $expected"
done
grep -Fq '"$INITD_DIR/odhcpd" disable' "$DEFAULTS" ||
	fail 'migration does not disable odhcpd autostart'
grep -Fq '"$INITD_DIR/odhcpd" stop' "$DEFAULTS" ||
	fail 'migration does not stop odhcpd'
sed -n '/^apply_odhcpd_runtime() {/,/^}/p' "$EXECUTOR" |
	grep -Fq '"$INITD_DIR/odhcpd" disable' || fail 'executor cannot disable odhcpd autostart'
sed -n '/^apply_odhcpd_runtime() {/,/^}/p' "$EXECUTOR" |
	grep -Fq '"$INITD_DIR/odhcpd" stop' || fail 'executor cannot stop odhcpd'

# Keep the historic marker name for the build orchestrator; the assertions
# above now enforce the stricter IPv4-only contract.
printf 'ipv6_dualstack_contract=pass\n'
