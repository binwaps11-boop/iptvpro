#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LIB="$ROOT/files/usr/libexec/cr6608-port-readiness-lib"
PROBE="$ROOT/files/usr/sbin/cr6608-port-readiness"
TEST_SHELL="${CR6608_TEST_SHELL:-sh}"
DASH="$ROOT/files/www/cgi-bin/dashctl"
EXECUTOR="$ROOT/files/usr/sbin/cr6608-quicksettings-apply"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-port-readiness-test.XXXXXX")"
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM

fail() {
	printf 'port_readiness_runtime=fail: %s\n' "$*" >&2
	exit 1
}

run_probe() {
	if [ -n "${CR6608_TEST_BUSYBOX_BIN:-}" ]; then
		CR6608_PORT_READINESS_LIB="$LIB" \
		CR6608_PORT_SLEEP_BIN="${CR6608_TEST_SLEEP_BIN:-/bin/sleep}" \
			"$CR6608_TEST_BUSYBOX_BIN" ash "$PROBE" "$@"
	else
		CR6608_PORT_READINESS_LIB="$LIB" \
		CR6608_PORT_SLEEP_BIN="${CR6608_TEST_SLEEP_BIN:-/bin/sleep}" \
			"$TEST_SHELL" "$PROBE" "$@"
	fi
}

expect_probe_final_fail() {
	local label="$1" output rc
	shift
	if output="$(run_probe "$@" 2>&1)"; then
		fail "$label returned success"
	else
		rc=$?
	fi
	[ "$rc" -ne 0 ] || fail "$label did not return non-zero"
	[ "$(printf '%s\n' "$output" | tail -n 1)" = 'result=FAIL' ] ||
		fail "$label lacked a final result=FAIL marker: $output"
	LAST_PROBE_OUTPUT="$output"
}

SYS="$TMP/sys/class/net"
mkdir -p "$SYS/br-lan" "$TMP/bin"
for port in lan1 lan2 lan3 wan; do
	mkdir -p "$SYS/$port/statistics"
	printf '1\n' > "$SYS/$port/carrier"
	printf 'up\n' > "$SYS/$port/operstate"
	printf '1000\n' > "$SYS/$port/speed"
	printf 'full\n' > "$SYS/$port/duplex"
	printf '0x1003\n' > "$SYS/$port/flags"
	for counter in rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped; do
		printf '0\n' > "$SYS/$port/statistics/$counter"
	done
done
for port in lan1 lan2 lan3; do
	ln -s ../br-lan "$SYS/$port/master"
done

MOCK_UCI="$TMP/bin/uci"
cat > "$MOCK_UCI" <<'EOF'
#!/bin/sh
[ "${1-}" = -q ] && shift
command="${1-}"; shift || true
key="${1-}"
scenario="${CR6608_TEST_SCENARIO:-plain}"
wan_disabled="${CR6608_TEST_WAN_DISABLED-0}"
wan_auto="${CR6608_TEST_WAN_AUTO-1}"
case "$command:$key" in
	show:network)
		[ "$scenario" != failshow ] || exit 1
		printf '%s\n' \
			"network.bridge=device" \
			"network.bridge.name='br-lan'" \
			"network.bridge.type='bridge'" \
			"network.bridge.ports='lan1 lan2 lan3'" \
			"network.lan=interface" \
			"network.lan.device='br-lan'"
		[ "$scenario" != duplicatebridge ] || printf '%s\n' \
			"network.bridge2=device" \
			"network.bridge2.name='br-lan'" \
			"network.bridge2.type='bridge'" \
			"network.bridge2.ports='lan1 lan2 lan3'"
		[ "$scenario" != vlan ] || printf '%s\n' \
			"network.vlan1=bridge-vlan" \
			"network.vlan1.device='br-lan'" \
			"network.vlan1.vlan='1'" \
			"network.vlan1.ports='lan1:u* lan2:u* lan3:u*'"
		case "$scenario" in
			pppoe|pppoevlan|pppoevlan1|safealias|badwan|missingowner|badowner|badvid|mismatch|foreignstack|bridgewan|bridgevlanwan)
				printf '%s\n' \
					"network.wan=interface" \
					"network.wan.proto='pppoe'" \
					"network.wan.username='user'"
				[ "$wan_disabled" = __absent__ ] || printf "network.wan.disabled='%s'\n" "$wan_disabled"
				[ "$wan_auto" = __absent__ ] || printf "network.wan.auto='%s'\n" "$wan_auto"
				;;
			parked|parkedsecrets) printf '%s\n' \
				"network.wan=interface" \
				"network.wan.proto='none'" \
				"network.wan.device='wan'" \
				"network.wan.disabled='1'" \
				"network.wan.auto='0'" ;;
		esac
		[ "$scenario" != parkedsecrets ] || printf '%s\n' \
			"network.wan.username='stale-user'" \
			"network.wan.password='stale-pass'"
		case "$scenario" in
			pppoe|safealias) printf '%s\n' "network.wan.device='wan'" ;;
			pppoevlan1) printf '%s\n' "network.wan.device='wan.1'" ;;
			pppoevlan|missingowner|badowner|mismatch|foreignstack|bridgewan|bridgevlanwan) printf '%s\n' "network.wan.device='wan.35'" ;;
			badvid) printf '%s\n' "network.wan.device='wan.4095'" ;;
			badwan) printf '%s\n' "network.wan.device='lan1'" ;;
		esac
		case "$scenario" in
			pppoevlan|pppoevlan1|badowner|badvid|mismatch|foreignstack|bridgewan|bridgevlanwan|staleowner)
				printf '%s\n' \
					"network.cr6608_wan_vlan=device" \
					"network.cr6608_wan_vlan.cr6608_owner='quicksettings-wan-vlan-v1'" \
					"network.cr6608_wan_vlan.type='8021q'" \
					"network.cr6608_wan_vlan.ifname='wan'" \
					"network.cr6608_wan_vlan.vid='35'" \
					"network.cr6608_wan_vlan.name='wan.35'"
				;;
		esac
		[ "$scenario" != pppoevlan1 ] || printf '%s\n' \
			"network.cr6608_wan_vlan.vid='1'" \
			"network.cr6608_wan_vlan.name='wan.1'"
		[ "$scenario" != badowner ] || printf '%s\n' "network.cr6608_wan_vlan.cr6608_owner='foreign'"
		[ "$scenario" != badvid ] || printf '%s\n' \
			"network.cr6608_wan_vlan.vid='4095'" \
			"network.cr6608_wan_vlan.name='wan.4095'"
		[ "$scenario" != mismatch ] || printf '%s\n' "network.cr6608_wan_vlan.name='wan.36'"
		case "$scenario" in
			badwanvlan|badalias|badaliasdot|badmulti_pre|badmulti_post|badmulti_vlan)
				printf '%s\n' "network.uplink=interface"
				;;
		esac
		case "$scenario" in
			badwanvlan) printf '%s\n' "network.uplink.device='wan.35'" ;;
			badalias) printf '%s\n' "network.uplink.device='@wan'" ;;
			badaliasdot) printf '%s\n' "network.uplink.device='@wan.35'" ;;
			badmulti_pre) printf '%s\n' "network.uplink.ifname='eth0 wan'" ;;
			badmulti_post) printf '%s\n' "network.uplink.ifname='wan lan1'" ;;
			badmulti_vlan) printf '%s\n' "network.uplink.ifname='eth0 wan.35'" ;;
		esac
		[ "$scenario" != safealias ] || printf '%s\n' \
			"network.wan6=interface" \
			"network.wan6.device='@wan'" \
			"network.wan6.proto='dhcpv6'"
		[ "$scenario" != foreignstack ] || printf '%s\n' \
			"network.foreign=device" \
			"network.foreign.name='wan.35'"
		[ "$scenario" != bridgevlanwan ] || printf '%s\n' \
			"network.vlanwan=bridge-vlan" \
			"network.vlanwan.device='br-lan'" \
			"network.vlanwan.ports='wan:t lan1:u*'"
		case "$scenario" in
			safephysical|badphysicaltype|badphysicalifname|failphysicaltype)
				printf '%s\n' "network.physical=device" "network.physical.name='wan'"
				;;
		esac
		[ "$scenario" != badphysicaltype ] || printf '%s\n' "network.physical.type='bridge'"
		[ "$scenario" != badphysicalifname ] || printf '%s\n' "network.physical.ifname='lan1'"
		[ "$scenario" != failphysicaltype ] || printf '%s\n' "network.physical.type='bridge'"
		case "$scenario" in
			baddevicealias|baddeviceifmulti|badbridgealias)
				printf '%s\n' "network.extra=device" "network.extra.name='extra0'"
				;;
		esac
		[ "$scenario" != baddevicealias ] || printf '%s\n' "network.extra.ifname='@wan.35'"
		[ "$scenario" != baddeviceifmulti ] || printf '%s\n' "network.extra.ifname='eth0 wan'"
		[ "$scenario" != badbridgealias ] || printf '%s\n' \
			"network.extra.type='bridge'" \
			"network.extra.ports='lan1 @wan'"
		[ "$scenario" != badbridgevlanalias ] || printf '%s\n' \
			"network.aliasvlan=bridge-vlan" \
			"network.aliasvlan.device='br-lan'" \
			"network.aliasvlan.ports='lan1:u* @wan:t'"
		;;
	get:network.bridge) printf 'device\n' ;;
	get:network.bridge.name) printf 'br-lan\n' ;;
	get:network.bridge.type) printf 'bridge\n' ;;
	get:network.bridge.ports)
		case "$scenario" in
			badbridge) printf 'lan1 lan2 lan3 wan\n' ;;
			bridgewan) printf 'lan1 lan2 lan3 wan.35\n' ;;
			*) printf 'lan1 lan2 lan3\n' ;;
		esac
		;;
	get:network.lan.device)
		if [ "$scenario" = vlan ]; then printf 'br-lan.1\n'; else printf 'br-lan\n'; fi
		;;
	get:network.vlan1.device) [ "$scenario" = vlan ] && printf 'br-lan\n' || exit 1 ;;
	get:network.vlan1.vlan) [ "$scenario" = vlan ] && printf '1\n' || exit 1 ;;
	get:network.vlan1.ports) [ "$scenario" = vlan ] && printf 'lan1:u* lan2:u* lan3:u*\n' || exit 1 ;;
		get:network.wan)
			case "$scenario" in pppoe|pppoevlan|pppoevlan1|safealias|badwan|missingowner|badowner|badvid|mismatch|foreignstack|bridgewan|bridgevlanwan|parked|parkedsecrets) printf 'interface\n' ;; *) exit 1 ;; esac
			;;
		get:network.wan.proto)
			case "$scenario" in parked|parkedsecrets) printf 'none\n'; exit 0 ;; esac
		case "$scenario" in pppoe|pppoevlan|pppoevlan1|safealias|badwan|missingowner|badowner|badvid|mismatch|foreignstack|bridgewan|bridgevlanwan) printf 'pppoe\n' ;; *) exit 1 ;; esac
		;;
	get:network.wan.device)
		case "$scenario" in
				pppoe|safealias|parked|parkedsecrets) printf 'wan\n' ;;
			pppoevlan1) printf 'wan.1\n' ;;
			pppoevlan|missingowner|badowner|mismatch|foreignstack|bridgewan|bridgevlanwan) printf 'wan.35\n' ;;
			badvid) printf 'wan.4095\n' ;;
			badwan) printf 'lan1\n' ;;
			*) exit 1 ;;
		esac
		;;
		get:network.wan.disabled)
			case "$scenario" in parked|parkedsecrets) printf '1\n' ;;
				*) [ "$wan_disabled" != __absent__ ] || exit 1; printf '%s\n' "$wan_disabled" ;;
			esac
			;;
		get:network.wan.auto)
			case "$scenario" in parked|parkedsecrets) printf '0\n' ;;
				*) [ "$wan_auto" != __absent__ ] || exit 1; printf '%s\n' "$wan_auto" ;;
			esac
			;;
		get:network.wan.username) [ "$scenario" = parked ] && exit 1; [ "$scenario" = parkedsecrets ] && printf 'stale-user\n' || printf 'user\n' ;;
		get:network.wan.password) [ "$scenario" = parkedsecrets ] && printf 'stale-pass\n' || exit 1 ;;
	get:network.wan6) [ "$scenario" = safealias ] && printf 'interface\n' || exit 1 ;;
	get:network.wan6.device) [ "$scenario" = safealias ] && printf '@wan\n' || exit 1 ;;
	get:network.wan6.ifname) exit 1 ;;
	get:network.wan6.proto) [ "$scenario" = safealias ] && printf 'dhcpv6\n' || exit 1 ;;
	get:network.cr6608_wan_vlan)
		case "$scenario" in pppoevlan|pppoevlan1|badowner|badvid|mismatch|foreignstack|bridgewan|bridgevlanwan|staleowner) printf 'device\n' ;; *) exit 1 ;; esac
		;;
	get:network.cr6608_wan_vlan.cr6608_owner)
		[ "$scenario" = badowner ] && printf 'foreign\n' || printf 'quicksettings-wan-vlan-v1\n'
		;;
	get:network.cr6608_wan_vlan.type) printf '8021q\n' ;;
	get:network.cr6608_wan_vlan.ifname) printf 'wan\n' ;;
	get:network.cr6608_wan_vlan.vid)
		case "$scenario" in pppoevlan1) printf '1\n' ;; badvid) printf '4095\n' ;; *) printf '35\n' ;; esac
		;;
	get:network.cr6608_wan_vlan.name)
		case "$scenario" in pppoevlan1) printf 'wan.1\n' ;; badvid) printf 'wan.4095\n' ;; mismatch) printf 'wan.36\n' ;; *) printf 'wan.35\n' ;; esac
		;;
	get:network.uplink.device)
		case "$scenario" in
			badwanvlan) printf 'wan.35\n' ;;
			badalias) printf '@wan\n' ;;
			badaliasdot) printf '@wan.35\n' ;;
			*) exit 1 ;;
		esac
		;;
	get:network.uplink.ifname)
		case "$scenario" in
			badmulti_pre) printf 'eth0 wan\n' ;;
			badmulti_post) printf 'wan lan1\n' ;;
			badmulti_vlan) printf 'eth0 wan.35\n' ;;
			*) exit 1 ;;
		esac
		;;
	get:network.foreign.name) [ "$scenario" = foreignstack ] && printf 'wan.35\n' || exit 1 ;;
	get:network.foreign.type|get:network.foreign.ifname|get:network.foreign.ports) exit 1 ;;
	get:network.vlanwan) [ "$scenario" = bridgevlanwan ] && printf 'bridge-vlan\n' || exit 1 ;;
	get:network.vlanwan.device) [ "$scenario" = bridgevlanwan ] && printf 'br-lan\n' || exit 1 ;;
	get:network.vlanwan.ports) [ "$scenario" = bridgevlanwan ] && printf 'wan:t lan1:u*\n' || exit 1 ;;
	get:network.physical.name) printf 'wan\n' ;;
	get:network.physical.type) [ "$scenario" != failphysicaltype ] || exit 1; [ "$scenario" = badphysicaltype ] && printf 'bridge\n' || exit 1 ;;
	get:network.physical.ifname) [ "$scenario" = badphysicalifname ] && printf 'lan1\n' || exit 1 ;;
	get:network.physical.ports) exit 1 ;;
	get:network.extra.name) printf 'extra0\n' ;;
	get:network.extra.type) [ "$scenario" = badbridgealias ] && printf 'bridge\n' || exit 1 ;;
	get:network.extra.ifname)
		case "$scenario" in baddevicealias) printf '@wan.35\n' ;; baddeviceifmulti) printf 'eth0 wan\n' ;; *) exit 1 ;; esac
		;;
	get:network.extra.ports) [ "$scenario" = badbridgealias ] && printf 'lan1 @wan\n' || exit 1 ;;
	get:network.aliasvlan.device) [ "$scenario" = badbridgevlanalias ] && printf 'br-lan\n' || exit 1 ;;
	get:network.aliasvlan.ports) [ "$scenario" = badbridgevlanalias ] && printf 'lan1:u* @wan:t\n' || exit 1 ;;
	*) exit 1 ;;
esac
EOF
chmod 755 "$MOCK_UCI"

CR6608_PORT_SYS_CLASS_NET="$SYS"
CR6608_PORT_UCI_BIN="$MOCK_UCI"
export CR6608_PORT_SYS_CLASS_NET CR6608_PORT_UCI_BIN
. "$LIB"

cr6608_bridge_membership_valid || fail 'plain bridge rejected'
cr6608_vlan_contract_valid || fail 'plain LAN device rejected'
[ "$(cr6608_wan_contract)" = reserved ] || fail 'reserved WAN rejected'

CR6608_TEST_SCENARIO=parked; export CR6608_TEST_SCENARIO
[ "$(cr6608_wan_contract)" = parked ] || fail 'parked bare WAN rejected'

CR6608_TEST_SCENARIO=parkedsecrets; export CR6608_TEST_SCENARIO
if cr6608_wan_contract >/dev/null; then fail 'runtime parked WAN accepted retained PPPoE credentials'; fi

CR6608_TEST_SCENARIO=pppoe; export CR6608_TEST_SCENARIO
[ "$(cr6608_wan_contract)" = pppoe-active ] || fail 'valid bare PPPoE rejected'

for invalid_disabled in __absent__ '' 1 2 true garbage; do
	CR6608_TEST_WAN_DISABLED="$invalid_disabled"; export CR6608_TEST_WAN_DISABLED
	if cr6608_wan_contract >/dev/null; then
		fail "runtime PPPoE accepted non-canonical disabled=${invalid_disabled:-empty}"
	fi
done
unset CR6608_TEST_WAN_DISABLED
for invalid_auto in __absent__ '' 0 2 true garbage; do
	CR6608_TEST_WAN_AUTO="$invalid_auto"; export CR6608_TEST_WAN_AUTO
	if cr6608_wan_contract >/dev/null; then
		fail "runtime PPPoE accepted non-canonical auto=${invalid_auto:-empty}"
	fi
done
unset CR6608_TEST_WAN_AUTO

CR6608_TEST_SCENARIO=duplicatebridge; export CR6608_TEST_SCENARIO
if cr6608_bridge_membership_valid; then fail 'duplicate br-lan device definitions were accepted'; fi

CR6608_TEST_SCENARIO=safealias; export CR6608_TEST_SCENARIO
[ "$(cr6608_wan_contract)" = pppoe-active ] || fail 'canonical wan6 @wan companion alias rejected'

CR6608_TEST_SCENARIO=pppoevlan; export CR6608_TEST_SCENARIO
[ "$(cr6608_wan_contract)" = 'pppoe-vlan-active:35' ] || fail 'owned PPPoE WAN VLAN rejected'

CR6608_TEST_SCENARIO=pppoevlan1; export CR6608_TEST_SCENARIO
[ "$(cr6608_wan_contract)" = 'pppoe-vlan-active:1' ] || fail 'lower-bound PPPoE WAN VLAN rejected'

CR6608_TEST_SCENARIO=safephysical; export CR6608_TEST_SCENARIO
[ "$(cr6608_wan_contract)" = reserved ] || fail 'plain physical config device name=wan rejected'

CR6608_TEST_SCENARIO=vlan; export CR6608_TEST_SCENARIO
cr6608_vlan_contract_valid || fail 'valid bridge VLAN rejected'

CR6608_TEST_SCENARIO=badbridge; export CR6608_TEST_SCENARIO
if cr6608_bridge_membership_valid; then fail 'WAN accepted in LAN bridge'; fi

CR6608_TEST_SCENARIO=badwan; export CR6608_TEST_SCENARIO
if cr6608_wan_contract >/dev/null; then fail 'PPPoE accepted on LAN1'; fi

CR6608_TEST_SCENARIO=badwanvlan; export CR6608_TEST_SCENARIO
if cr6608_wan_contract >/dev/null; then fail 'WAN VLAN owned by another interface was reported reserved'; fi

for invalid_scenario in missingowner badowner badvid mismatch foreignstack bridgewan bridgevlanwan staleowner badalias badaliasdot badmulti_pre badmulti_post badmulti_vlan badphysicaltype badphysicalifname failphysicaltype baddevicealias baddeviceifmulti badbridgealias badbridgevlanalias failshow; do
	CR6608_TEST_SCENARIO="$invalid_scenario"; export CR6608_TEST_SCENARIO
	if cr6608_wan_contract >/dev/null; then
		fail "invalid WAN VLAN ownership accepted: $invalid_scenario"
	fi
done

for conflicting_bridge_reference in wan wan:t wan.35:u* @wan @wan:t '@wan.35:u*' 'lan1:u* wan:t' 'lan1 @wan'; do
	cr6608_wan_bridge_reference_conflicts "$conflicting_bridge_reference" ||
		fail "WAN bridge reference was not detected: $conflicting_bridge_reference"
done
for safe_bridge_reference in '' lan1 'lan1:u* lan2:t' '@wan6:t'; do
	if cr6608_wan_bridge_reference_conflicts "$safe_bridge_reference"; then
		fail "safe bridge reference was rejected: ${safe_bridge_reference:-empty}"
	fi
done

for conflicting_reference in wan wan. wan.35 @wan @wan. @wan.35 'eth0 wan' 'wan lan1' 'eth0 wan.35'; do
	cr6608_wan_l3_reference_conflicts "$conflicting_reference" ||
		fail "WAN L3 reference was not detected: $conflicting_reference"
done
for safe_reference in '' lan1 '@wan6' 'eth0 lan1'; do
	if cr6608_wan_l3_reference_conflicts "$safe_reference"; then
		fail "safe non-WAN reference was rejected: ${safe_reference:-empty}"
	fi
done

cr6608_wan_vlan_id_valid 1 || fail 'VID 1 lower bound rejected'
cr6608_wan_vlan_id_valid 4094 || fail 'VID 4094 upper bound rejected'
for invalid_vid in '' 0 4095 -1 abc; do
	if cr6608_wan_vlan_id_valid "$invalid_vid"; then fail "invalid WAN VID accepted: ${invalid_vid:-empty}"; fi
done

CR6608_TEST_SCENARIO=plain; export CR6608_TEST_SCENARIO
# Git Bash without native-symlink support materializes `ln -s` as an ordinary
# file.  Keep the sysfs topology assertions mandatory on Linux (including the
# builder and router), while still running every UCI/WAN fault-injection case on
# that Windows-only host limitation.
if [ -L "$SYS/lan1/master" ] && [ -L "$SYS/lan2/master" ] && [ -L "$SYS/lan3/master" ]; then
	output="$(run_probe \
		--require-carrier lan1,lan2,lan3)" || fail "read-only probe rejected healthy mock topology: $output"
	printf '%s\n' "$output" | grep -qx 'result=PASS' || fail 'probe PASS marker missing'

	printf '0\n' > "$SYS/lan2/carrier"
	expect_probe_final_fail 'missing required LAN2 carrier' --require-carrier lan1,lan2,lan3
	printf '1\n' > "$SYS/lan2/carrier"
	rm -f -- "$SYS/lan2/carrier"
	expect_probe_final_fail 'unreadable LAN2 carrier telemetry'
	printf '1\n' > "$SYS/lan2/carrier"
	printf 'garbage\n' > "$SYS/lan2/speed"
	expect_probe_final_fail 'malformed linked-port speed telemetry'
	printf '1000\n' > "$SYS/lan2/speed"
	printf 'garbage\n' > "$SYS/lan2/duplex"
	expect_probe_final_fail 'malformed linked-port duplex telemetry'
	printf 'full\n' > "$SYS/lan2/duplex"
	rm -f -- "$SYS/lan2/statistics/rx_errors"
	expect_probe_final_fail 'missing counter snapshot'
	printf '%s\n' "$LAST_PROBE_OUTPUT" | grep -qx 'reason=counter-snapshot' ||
		fail 'missing counter did not identify the snapshot reason'
	printf 'not-a-counter\n' > "$SYS/lan2/statistics/rx_errors"
	expect_probe_final_fail 'malformed counter snapshot'
	printf '%s\n' "$LAST_PROBE_OUTPUT" | grep -qx 'reason=counter-snapshot' ||
		fail 'malformed counter did not identify the snapshot reason'
	printf '0\n' > "$SYS/lan2/statistics/rx_errors"

	# The kernel may return EINVAL for carrier/speed/duplex on an unused WAN
	# device.  Accept that only when UCI says reserved and flags proves IFF_UP=0.
	printf '0x1002\n' > "$SYS/wan/flags"
	printf 'down\n' > "$SYS/wan/operstate"
	rm -f -- "$SYS/wan/carrier" "$SYS/wan/speed" "$SYS/wan/duplex"
	output="$(run_probe)" || fail "reserved admin-down WAN was rejected: $output"
	printf '%s\n' "$output" | grep -q \
		'^port.wan.topology=PASS .*carrier=unavailable .*speed_mbps=unavailable duplex=unavailable reserved_admin_down=1 link_telemetry=PASS$' ||
		fail 'reserved admin-down WAN exception was not reported exactly'
	printf '%s\n' "$output" | tail -n 1 | grep -qx 'result=PASS' ||
		fail 'reserved admin-down WAN lacked final PASS'

	printf '0x1003\n' > "$SYS/wan/flags"
	expect_probe_final_fail 'reserved admin-up WAN with unavailable telemetry'
	printf '0x1002\n' > "$SYS/wan/flags"
	CR6608_TEST_SCENARIO=pppoe; export CR6608_TEST_SCENARIO
	expect_probe_final_fail 'configured WAN with unavailable telemetry'
	CR6608_TEST_SCENARIO=plain; export CR6608_TEST_SCENARIO
	expect_probe_final_fail 'required carrier on reserved admin-down WAN' --require-carrier wan
	expect_probe_final_fail 'required traffic on reserved admin-down WAN' --observe 1 --require-traffic wan
	printf '%s\n' "$LAST_PROBE_OUTPUT" | grep -q \
		'^port.wan.topology=PASS .*reserved_admin_down=0 link_telemetry=FAIL$' ||
		fail 'required-traffic WAN incorrectly received the reserved admin-down exception'
	printf 'not-flags\n' > "$SYS/wan/flags"
	expect_probe_final_fail 'reserved WAN with malformed admin flags'
	printf '0x1003\n' > "$SYS/wan/flags"
	printf '1\n' > "$SYS/wan/carrier"
	printf '1000\n' > "$SYS/wan/speed"
	printf 'full\n' > "$SYS/wan/duplex"
	printf 'up\n' > "$SYS/wan/operstate"
	cat > "$TMP/bin/sleep" <<'EOF'
#!/bin/sh
case "${CR6608_TEST_SLEEP_ACTION:-}" in
	drop) printf '1\n' > "$CR6608_PORT_SYS_CLASS_NET/lan1/statistics/rx_dropped" ;;
	lose-counter) rm -f -- "$CR6608_PORT_SYS_CLASS_NET/lan1/statistics/tx_packets" ;;
	fail) exit 1 ;;
esac
EOF
	chmod 755 "$TMP/bin/sleep"
	CR6608_TEST_SLEEP_BIN="$TMP/bin/sleep"; export CR6608_TEST_SLEEP_BIN
	CR6608_TEST_SLEEP_ACTION=drop; export CR6608_TEST_SLEEP_ACTION
	expect_probe_final_fail 'dropped-packet observation' --observe 1
	printf '%s\n' "$LAST_PROBE_OUTPUT" | grep -qx 'port.lan1.drop_delta=FAIL' ||
		fail 'dropped-packet growth during observation was accepted'
	printf '0\n' > "$SYS/lan1/statistics/rx_dropped"
	CR6608_TEST_SLEEP_ACTION=lose-counter; export CR6608_TEST_SLEEP_ACTION
	expect_probe_final_fail 'counter-loss observation' --observe 1
	printf '%s\n' "$LAST_PROBE_OUTPUT" | grep -qx 'port.lan1.counter_sample=FAIL' ||
		fail 'counter disappearance during observation was accepted'
	printf '0\n' > "$SYS/lan1/statistics/tx_packets"
	CR6608_TEST_SLEEP_ACTION=fail; export CR6608_TEST_SLEEP_ACTION
	expect_probe_final_fail 'observation sleep failure' --observe 1
	printf '%s\n' "$LAST_PROBE_OUTPUT" | grep -qx 'observation_wait=FAIL' ||
		fail 'observation sleep failure lacked its exact marker'
	unset CR6608_TEST_SLEEP_ACTION CR6608_TEST_SLEEP_BIN
	expect_probe_final_fail 'traffic proof without observation' --require-traffic lan1
else
	printf 'port_readiness_sysfs_topology=skip:no-native-symlink\n'
fi

# Execute the actual Smart AP WAN staging helpers against a mutable UCI mock.
# This proves that the second writer can move tagged -> bare, verifies its
# ownership record, and refuses to erase a corrupt/foreign section.
WAN_STATE="$TMP/wan-state"
STATE_UCI="$TMP/bin/state-uci"
cat > "$STATE_UCI" <<'EOF'
#!/bin/sh
[ "${1-}" = -q ] && shift
command="${1-}"; shift || true
state="${CR6608_WAN_STATE:?}"
case "$command" in
	get)
		key="${1-}"
		[ "${CR6608_WAN_FAIL_GET:-}" != "$key" ] || exit 1
		awk -v key="$key" 'index($0,key "=")==1 { print substr($0,length(key)+2); found=1 } END { exit found ? 0 : 1 }' "$state"
		;;
	set)
		assignment="${1-}"; key="${assignment%%=*}"; value="${assignment#*=}"
		[ -z "${CR6608_WAN_MUTATION_LOG:-}" ] || printf 'set %s\n' "$assignment" >>"$CR6608_WAN_MUTATION_LOG"
		[ "${CR6608_WAN_LIE_SET:-}" != "$assignment" ] || exit 0
		tmp="$state.new.$$"
		awk -v key="$key" 'index($0,key "=")!=1' "$state" >"$tmp" || exit 1
		printf '%s=%s\n' "$key" "$value" >>"$tmp" || exit 1
		mv "$tmp" "$state"
		;;
	delete)
		key="${1-}"; tmp="$state.new.$$"
		[ -z "${CR6608_WAN_MUTATION_LOG:-}" ] || printf 'delete %s\n' "$key" >>"$CR6608_WAN_MUTATION_LOG"
		[ "${CR6608_WAN_LIE_DELETE:-}" != "$key" ] || exit 0
		awk -v key="$key" 'index($0,key "=")!=1 && index($0,key ".")!=1' "$state" >"$tmp" || exit 1
		mv "$tmp" "$state"
		;;
	show)
		[ "${1-}" = network ] || exit 1
		[ "${CR6608_WAN_FAIL_SHOW:-0}" != 1 ] || exit 1
		cat "$state"
		;;
	*) exit 1 ;;
esac
EOF
chmod 755 "$STATE_UCI"
CR6608_WAN_STATE="$WAN_STATE"
CR6608_PORT_UCI_BIN="$STATE_UCI"
CR6608_WAN_MUTATION_LOG="$TMP/wan-mutations"
export CR6608_WAN_STATE CR6608_PORT_UCI_BIN CR6608_WAN_MUTATION_LOG
: >"$CR6608_WAN_MUTATION_LOG"
uci() { "$STATE_UCI" "$@"; }
eval "$(sed -n '/^royal_set() {/,/^royal_strip_wan_bridge_membership() {/p' "$DASH" | sed '$d')"

printf '%s\n' \
	'network.wan=interface' \
	'network.wan.proto=pppoe' \
	'network.wan.device=wan' \
	'network.wan.disabled=0' \
	'network.wan.auto=1' \
	'network.wan.username=user' >"$WAN_STATE"
royal_stage_wan_vlan 35 || fail 'Smart AP rejected valid WAN VID 35'
[ "$royal_wan_device" = wan.35 ] || fail 'Smart AP did not derive wan.35'
royal_set "network.wan.device=$royal_wan_device" || fail 'mock could not bind tagged WAN'
royal_verify_wan_vlan_stage 35 || fail 'Smart AP tagged staging verification failed'
[ "$(uci -q get network.cr6608_wan_vlan.cr6608_owner)" = quicksettings-wan-vlan-v1 ] || fail 'Smart AP owner marker missing'
[ "$(uci -q get network.cr6608_wan_vlan.type)" = 8021q ] || fail 'Smart AP 802.1Q type missing'
[ "$(uci -q get network.cr6608_wan_vlan.ifname)" = wan ] || fail 'Smart AP physical WAN parent missing'
[ "$(uci -q get network.cr6608_wan_vlan.name)" = wan.35 ] || fail 'Smart AP tagged netdev name mismatch'

uci -q set network.wan.auto=0 || fail 'could not inject PPPoE auto drift'
if royal_verify_wan_vlan_stage 35; then fail 'Smart AP accepted PPPoE auto=0 drift'; fi
uci -q set network.wan.auto=1 || fail 'could not restore PPPoE auto state'
uci -q set network.wan.disabled=1 || fail 'could not inject PPPoE disabled drift'
CR6608_WAN_LIE_SET='network.wan.disabled=0'; export CR6608_WAN_LIE_SET
royal_set "network.wan.disabled=0" || fail 'lying UCI set did not report success'
unset CR6608_WAN_LIE_SET
if royal_verify_wan_vlan_stage 35; then fail 'Smart AP trusted a lying UCI set without readback'; fi
uci -q set network.wan.disabled=0 || fail 'could not restore PPPoE disabled state'

royal_stage_wan_vlan "" || fail 'Smart AP could not remove its valid tagged owner'
royal_set "network.wan.device=$royal_wan_device" || fail 'mock could not bind bare WAN'
royal_verify_wan_vlan_stage "" || fail 'Smart AP bare WAN staging verification failed'
if uci -q get network.cr6608_wan_vlan >/dev/null 2>&1; then fail 'Smart AP retained a stale tagged owner'; fi

printf '%s\n' \
	'network.wan=interface' \
	'network.wan.device=wan.35' \
	'network.cr6608_wan_vlan=device' \
	'network.cr6608_wan_vlan.cr6608_owner=foreign' \
	'network.cr6608_wan_vlan.type=8021q' \
	'network.cr6608_wan_vlan.ifname=wan' \
	'network.cr6608_wan_vlan.vid=35' \
	'network.cr6608_wan_vlan.name=wan.35' >"$WAN_STATE"
if royal_stage_wan_vlan 36; then fail 'Smart AP replaced a foreign/corrupt WAN owner'; fi
[ "$(uci -q get network.cr6608_wan_vlan.cr6608_owner)" = foreign ] || fail 'Smart AP erased foreign owner metadata'

printf '%s\n' 'network.wan=interface' 'network.wan.device=wan' >"$WAN_STATE"
for invalid_vid in 0 4095 abc; do
	wan_before="$(cat "$WAN_STATE")"
	if royal_stage_wan_vlan "$invalid_vid"; then fail "Smart AP accepted invalid WAN VID $invalid_vid"; fi
	[ "$(cat "$WAN_STATE")" = "$wan_before" ] || fail "invalid WAN VID $invalid_vid mutated UCI"
done

# Both dashboard apply/reset paths use the same deterministic parker. Prove
# that DHCP and static WAN are converted to the complete parked contract.
for transition in dhcp static; do
	printf '%s\n' \
		'network.wan=interface' \
		"network.wan.proto=$transition" \
		'network.wan.device=wan' \
		'network.wan.disabled=0' \
		'network.wan.auto=1' \
		'network.wan.username=stale-user' \
		'network.wan.password=stale-pass' >"$WAN_STATE"
	: >"$CR6608_WAN_MUTATION_LOG"
	royal_park_wan || fail "Smart AP could not park $transition WAN"
	royal_verify_wan_vlan_stage "" parked || fail "Smart AP did not verify complete $transition -> parked transition"
	[ "$(uci -q get network.wan.proto)" = none ] || fail "Smart AP retained $transition WAN proto"
	[ "$(uci -q get network.wan.device)" = wan ] || fail 'Smart AP parked the wrong WAN device'
	[ "$(uci -q get network.wan.disabled)" = 1 ] || fail 'Smart AP did not disable parked WAN'
	[ "$(uci -q get network.wan.auto)" = 0 ] || fail 'Smart AP did not disable parked WAN autostart'
	if uci -q get network.wan.username >/dev/null 2>&1 || uci -q get network.wan.password >/dev/null 2>&1; then
		fail "Smart AP retained stale $transition credentials"
	fi
done

# A credential read fault is rejected before either parker writes anything,
# while a backend that lies about deletion is caught by the final parked-state
# readback because secrets are part of that contract.
printf '%s\n' \
	'network.wan=interface' \
	'network.wan.proto=dhcp' \
	'network.wan.device=wan' \
	'network.wan.disabled=0' \
	'network.wan.auto=1' \
	'network.wan.username=stale-user' \
	'network.wan.password=stale-pass' >"$WAN_STATE"
secret_before="$(cat "$WAN_STATE")"; : >"$CR6608_WAN_MUTATION_LOG"
CR6608_WAN_FAIL_GET=network.wan.username; export CR6608_WAN_FAIL_GET
if royal_park_wan; then fail 'Smart AP ignored a declared credential read failure'; fi
unset CR6608_WAN_FAIL_GET
[ "$(cat "$WAN_STATE")" = "$secret_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'Smart AP mutated WAN before credential preflight completed'
CR6608_WAN_LIE_DELETE=network.wan.username; export CR6608_WAN_LIE_DELETE
royal_park_wan || fail 'lying credential delete did not report mock success'
unset CR6608_WAN_LIE_DELETE
if royal_verify_wan_vlan_stage "" parked; then fail 'parked verifier accepted a retained PPPoE username'; fi

# Generic reset/apply deletion helpers must also distinguish proven absence
# from backend read failure before deleting a section or list member.
printf '%s\n' \
	'network.test=interface' \
	'network.bridge=device' \
	'network.bridge.name=br-lan' \
	'network.bridge.type=bridge' \
	'network.bridge.ports=lan1 lan2' >"$WAN_STATE"
delete_before="$(cat "$WAN_STATE")"; : >"$CR6608_WAN_MUTATION_LOG"
CR6608_WAN_FAIL_GET=network.test; export CR6608_WAN_FAIL_GET
if royal_delete network.test; then fail 'royal_delete treated a declared-section read failure as absence'; fi
unset CR6608_WAN_FAIL_GET
[ "$(cat "$WAN_STATE")" = "$delete_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'royal_delete mutated after a declared-section read failure'
CR6608_WAN_FAIL_GET=network.bridge.ports; export CR6608_WAN_FAIL_GET
if royal_del_list network.bridge.ports=lan1; then fail 'royal_del_list treated an option read failure as missing member'; fi
unset CR6608_WAN_FAIL_GET
[ "$(cat "$WAN_STATE")" = "$delete_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'royal_del_list mutated after an option read failure'
CR6608_WAN_FAIL_SHOW=1; export CR6608_WAN_FAIL_SHOW
if royal_delete network.absent; then fail 'royal_delete treated a package snapshot failure as proven absence'; fi
unset CR6608_WAN_FAIL_SHOW
[ "$(cat "$WAN_STATE")" = "$delete_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'royal_delete mutated after a package snapshot failure'
royal_delete network.absent || fail 'royal_delete rejected exact absence from a successful package dump'
[ ! -s "$CR6608_WAN_MUTATION_LOG" ] || fail 'royal_delete mutated a proven-absent reference'

# A declared owner field that cannot be read must stop before delete/set. The
# same applies when the network snapshot itself cannot be obtained.
printf '%s\n' \
	'network.wan=interface' \
	'network.wan.proto=pppoe' \
	'network.wan.device=wan.35' \
	'network.cr6608_wan_vlan=device' \
	'network.cr6608_wan_vlan.cr6608_owner=quicksettings-wan-vlan-v1' \
	'network.cr6608_wan_vlan.type=8021q' \
	'network.cr6608_wan_vlan.ifname=wan' \
	'network.cr6608_wan_vlan.vid=35' \
	'network.cr6608_wan_vlan.name=wan.35' >"$WAN_STATE"
wan_before="$(cat "$WAN_STATE")"; : >"$CR6608_WAN_MUTATION_LOG"
CR6608_WAN_FAIL_GET=network.cr6608_wan_vlan.cr6608_owner; export CR6608_WAN_FAIL_GET
if royal_stage_wan_vlan 36; then fail 'Smart AP ignored a managed-owner read failure'; fi
unset CR6608_WAN_FAIL_GET
[ "$(cat "$WAN_STATE")" = "$wan_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'Smart AP mutated WAN after a managed-owner read failure'
CR6608_WAN_FAIL_SHOW=1; export CR6608_WAN_FAIL_SHOW
if royal_stage_wan_vlan 36; then fail 'Smart AP ignored a network snapshot failure'; fi
unset CR6608_WAN_FAIL_SHOW
[ "$(cat "$WAN_STATE")" = "$wan_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'Smart AP mutated WAN after a network snapshot failure'

# Execute the privileged writer's real parker against the same mutable mock.
eval "$(sed -n '/^remove_managed_wan_vlan() {/,/^set_pppoe_wan() {/p' "$EXECUTOR" | sed '$d')"
for transition in dhcp static; do
	printf '%s\n' \
		'network.wan=interface' \
		"network.wan.proto=$transition" \
		'network.wan.device=wan' \
		'network.wan.disabled=0' \
		'network.wan.auto=1' \
		'network.wan.username=stale-user' \
		'network.wan.password=stale-pass' >"$WAN_STATE"
	: >"$CR6608_WAN_MUTATION_LOG"
	park_wan || fail "privileged writer could not park $transition WAN"
	cr6608_wan_uci_parked || fail "privileged writer did not produce complete $transition -> parked state"
done

printf '%s\n' \
	'network.wan=interface' \
	'network.wan.proto=static' \
	'network.wan.device=wan' \
	'network.wan.disabled=0' \
	'network.wan.auto=1' \
	'network.wan.username=stale-user' \
	'network.wan.password=stale-pass' >"$WAN_STATE"
secret_before="$(cat "$WAN_STATE")"; : >"$CR6608_WAN_MUTATION_LOG"
CR6608_WAN_FAIL_GET=network.wan.password; export CR6608_WAN_FAIL_GET
if park_wan; then fail 'privileged writer ignored a declared credential read failure'; fi
unset CR6608_WAN_FAIL_GET
[ "$(cat "$WAN_STATE")" = "$secret_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'privileged writer mutated WAN before credential preflight completed'

printf '%s\n' \
	'network.wan=interface' \
	'network.wan.proto=pppoe' \
	'network.wan.device=wan.35' \
	'network.cr6608_wan_vlan=device' \
	'network.cr6608_wan_vlan.cr6608_owner=quicksettings-wan-vlan-v1' \
	'network.cr6608_wan_vlan.type=8021q' \
	'network.cr6608_wan_vlan.ifname=wan' \
	'network.cr6608_wan_vlan.vid=35' \
	'network.cr6608_wan_vlan.name=wan.35' >"$WAN_STATE"
wan_before="$(cat "$WAN_STATE")"; : >"$CR6608_WAN_MUTATION_LOG"
CR6608_WAN_FAIL_GET=network.cr6608_wan_vlan.cr6608_owner; export CR6608_WAN_FAIL_GET
if park_wan; then fail 'privileged writer ignored a managed-owner read failure'; fi
unset CR6608_WAN_FAIL_GET
[ "$(cat "$WAN_STATE")" = "$wan_before" ] && [ ! -s "$CR6608_WAN_MUTATION_LOG" ] ||
	fail 'privileged writer mutated WAN after a managed-owner read failure'

printf 'port_readiness_runtime=pass\n'
