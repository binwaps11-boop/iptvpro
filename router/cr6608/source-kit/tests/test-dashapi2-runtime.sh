#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/www/cgi-bin/dashapi2"

fail() {
	printf 'dashapi2_runtime=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "missing $SOURCE"
[ -x /usr/bin/setsid ] || fail "missing /usr/bin/setsid"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-dashapi2-runtime.XXXXXX")" || exit 1
cleanup() {
	[ -z "${stubborn_parent:-}" ] || /bin/kill -KILL "$stubborn_parent" 2>/dev/null || true
	[ -z "${stubborn_child:-}" ] || /bin/kill -KILL "$stubborn_child" 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

HELPERS="$TMP/monotonic-helpers.sh"
RUNNER="$TMP/run-limit.sh"
TXPOWER_HELPER="$TMP/txpower-snapshot-helper.sh"
WIRELESS_STATUS_HELPER="$TMP/wireless-status-helper.sh"
CLIENT_TRAFFIC_HELPER="$TMP/client-traffic-helper.sh"
LINK_DIAGNOSTICS_HELPER="$TMP/link-diagnostics-helper.sh"
UL_GUARD_HELPER="$TMP/ul-guard-helper.sh"
awk '
	/^# BEGIN CR6608_DASHAPI2_MONOTONIC_HELPERS$/ { copy=1; next }
	/^# END CR6608_DASHAPI2_MONOTONIC_HELPERS$/ { exit }
	copy { print }
' "$SOURCE" >"$HELPERS"
awk '
	/^# BEGIN CR6608_DASHAPI2_RUN_LIMIT$/ { copy=1; next }
	/^# END CR6608_DASHAPI2_RUN_LIMIT$/ { exit }
	copy { print }
' "$SOURCE" >"$RUNNER"
awk '
	/^# BEGIN CR6608_DASHAPI2_TXPOWER_SNAPSHOT_HELPER$/ { copy=1; next }
	/^# END CR6608_DASHAPI2_TXPOWER_SNAPSHOT_HELPER$/ { exit }
	copy { print }
' "$SOURCE" >"$TXPOWER_HELPER"
awk '
	/^# BEGIN CR6608_DASHAPI2_WIRELESS_STATUS_HELPER$/ { copy=1; next }
	/^# END CR6608_DASHAPI2_WIRELESS_STATUS_HELPER$/ { exit }
	copy { print }
' "$SOURCE" >"$WIRELESS_STATUS_HELPER"
awk '
	/^# BEGIN CR6608_DASHAPI2_CLIENT_TRAFFIC_HELPER$/ { copy=1; next }
	/^# END CR6608_DASHAPI2_CLIENT_TRAFFIC_HELPER$/ { exit }
	copy { print }
' "$SOURCE" >"$CLIENT_TRAFFIC_HELPER"
awk '
	/^# BEGIN CR6608_DASHAPI2_LINK_DIAGNOSTICS_HELPER$/ { copy=1; next }
	/^# END CR6608_DASHAPI2_LINK_DIAGNOSTICS_HELPER$/ { exit }
	copy { print }
' "$SOURCE" >"$LINK_DIAGNOSTICS_HELPER"
awk '
	/^# BEGIN CR6608_DASHAPI2_UL_GUARD_HELPER$/ { copy=1; next }
	/^# END CR6608_DASHAPI2_UL_GUARD_HELPER$/ { exit }
	copy { print }
' "$SOURCE" >"$UL_GUARD_HELPER"
grep -q '^dashapi_monotonic_seconds()' "$HELPERS" || fail "could not extract monotonic helper"
grep -q '^run_limit()' "$RUNNER" || fail "could not extract bounded runner"
grep -q '^txpower_applied_from_text()' "$TXPOWER_HELPER" ||
	fail "could not extract txpower snapshot helper"
grep -q '^iw_snapshot_for_if()' "$TXPOWER_HELPER" ||
	fail "could not extract iw interface snapshot helper"
grep -q '^txpower_max_from_text()' "$TXPOWER_HELPER" ||
	fail "could not extract txpower maximum helper"
grep -q '^wifi_dev_from_status()' "$WIRELESS_STATUS_HELPER" ||
	fail "could not extract wireless status mapping helper"
grep -q '^wifi_dev_for_if()' "$WIRELESS_STATUS_HELPER" ||
	fail "could not extract wireless status retry helper"
grep -q '^dashapi_client_edge_counters()' "$CLIENT_TRAFFIC_HELPER" ||
	fail "could not extract client-edge traffic helper"
grep -q '^dashapi_client_topology_complete()' "$CLIENT_TRAFFIC_HELPER" ||
	fail "could not extract client topology completeness helper"
grep -q '^dashapi_collect_link_diagnostics()' "$LINK_DIAGNOSTICS_HELPER" ||
	fail "could not extract DSA link diagnostics helper"
grep -q '^dashapi_ul_guard_health()' "$UL_GUARD_HELPER" ||
	fail "could not extract UL guard health helper"
. "$UL_GUARD_HELPER"
[ "$(dashapi_ul_guard_health armed 100 110 1 60)" = true:10 ] ||
	fail "fresh running UL guard was not healthy"
[ "$(dashapi_ul_guard_health armed 100 161 1 60)" = false:61 ] ||
	fail "stale UL guard heartbeat was accepted"
[ "$(dashapi_ul_guard_health armed 100 110 0 60)" = false:10 ] ||
	fail "stopped UL guard was accepted"
[ "$(dashapi_ul_guard_health armed 111 110 1 60)" = false:null ] ||
	fail "future-dated UL guard heartbeat was accepted"
[ "$(dashapi_ul_guard_health rebooting 100 110 1 60)" = false:10 ] ||
	fail "non-armed UL guard state was accepted"

# The local link test must remain authenticated and byte-exact. It exits
# before the dashboard cache collector, so the runtime fixture needs only the
# session contract and proves that no unauthenticated 8 MiB response is sent.
SESSION_ALLOW="$TMP/session-allow.sh"
SESSION_DENY="$TMP/session-deny.sh"
cat >"$SESSION_ALLOW" <<'SH'
cr6608_session_from_request() { printf '%s\n' fixture-session; }
cr6608_session_valid() { return 0; }
SH
cat >"$SESSION_DENY" <<'SH'
cr6608_session_from_request() { printf '%s\n' fixture-session; }
cr6608_session_valid() { return 1; }
SH
CR6608_SESSION_AUTH_LIB="$SESSION_ALLOW" QUERY_STRING='speedtest=1&nonce=fixture' \
	"$SOURCE" >"$TMP/speed-allowed.out"
python3 - "$TMP/speed-allowed.out" <<'PY'
import pathlib
import sys

raw = pathlib.Path(sys.argv[1]).read_bytes()
header, payload = raw.split(b"\r\n\r\n", 1)
assert b"Content-Type: application/octet-stream" in header
assert b"Content-Length: 8388608" in header
assert b"Cache-Control: no-store" in header
assert len(payload) == 8 * 1024 * 1024, len(payload)
assert not payload.strip(b"\x00")
PY
CR6608_SESSION_AUTH_LIB="$SESSION_DENY" QUERY_STRING='speedtest=1&nonce=fixture' \
	"$SOURCE" >"$TMP/speed-denied.out"
grep -aFq 'Status: 403 Forbidden' "$TMP/speed-denied.out" ||
	fail "unauthenticated local link test was not denied"
if grep -aFq 'Content-Length: 8388608' "$TMP/speed-denied.out"; then
	fail "unauthenticated local link test exposed the payload"
fi

# DSA and AP counters are both client edges.  TX is download to a client and
# RX is upload from a client.  Excluding the gateway-facing DSA port prevents
# the same forwarded packet being counted at the uplink and client edge.
# shellcheck disable=SC1090
. "$CLIENT_TRAFFIC_HELPER"
cat >"$TMP/proc-net-dev" <<'EOF'
Inter-|   Receive                                                |  Transmit
 face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed
br-lan: 9000 0 0 0 0 0 0 0 8000 0 0 0 0 0 0 0
eth0: 7000 0 0 0 0 0 0 0 6000 0 0 0 0 0 0 0
lan1: 5000 0 0 0 0 0 0 0 4000 0 0 0 0 0 0 0
lan2: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
lan3: 300 0 0 0 0 0 0 0 400 0 0 0 0 0 0 0
phy0-ap0: 700 0 0 0 0 0 0 0 800 0 0 0 0 0 0 0
phy1-ap0: 900 0 0 0 0 0 0 0 1000 0 0 0 0 0 0 0
phy1-sta0: 9900 0 0 0 0 0 0 0 9900 0 0 0 0 0 0 0
EOF
set -- $(dashapi_client_edge_counters "$TMP/proc-net-dev" lan1 true)
[ "$1" -eq 4200 ] || fail "client download did not sum wired+Wi-Fi TX: $1"
[ "$2" -eq 2900 ] || fail "client upload did not sum wired+Wi-Fi RX: $2"
[ "$3" -eq 4 ] || fail "client edge count is wrong: $3"
[ "$4" = 'lan2,lan3,phy0-ap0,phy1-ap0' ] || fail "resolved client-edge signature is wrong: $4"
set -- $(dashapi_client_edge_counters "$TMP/proc-net-dev" "" false)
[ "$1" -eq 1800 ] || fail "unresolved topology did not retain the known Wi-Fi download subtotal: $1"
[ "$2" -eq 1600 ] || fail "unresolved topology Wi-Fi upload subtotal is wrong: $2"
[ "$3" -eq 2 ] || fail "unresolved topology included an unclassified DSA edge: $3"
[ "$4" = 'phy0-ap0,phy1-ap0' ] || fail "unresolved Wi-Fi edge signature is wrong: $4"

# AP mode resolves the upstream gateway through the bridge FDB; routed PPPoE
# is complete only when its configured device proves the physical WAN member.
wan_device=lan3
ip() {
	case "$*" in
		"neigh show to 192.168.1.254 dev br-lan"|"neigh show to 192.168.1.254")
			printf '%s\n' '192.168.1.254 dev br-lan lladdr aa:bb:cc:dd:ee:ff REACHABLE' ;;
		*) return 1 ;;
	esac
}
bridge() { printf '%s\n' 'aa:bb:cc:dd:ee:ff dev lan1 master br-lan'; }
uci() {
	[ "$1" = -q ] && [ "$2" = get ] && [ "$3" = network.wan.device ] || return 1
	printf '%s\n' "$wan_device"
}
[ "$(dashapi_client_uplink_port br-lan 192.168.1.254 br-lan)" = lan1 ] ||
	fail "AP gateway FDB did not resolve the uplink"
[ "$(dashapi_client_uplink_port pppoe-wan '' br-lan)" = lan3 ] ||
	fail "routed WAN device did not resolve the uplink"
dashapi_client_topology_complete br-lan lan1 || fail "resolved AP topology was reported incomplete"
if dashapi_client_topology_complete br-lan ''; then fail "unresolved AP topology was reported complete"; fi
dashapi_client_topology_complete '' lan1 || fail "sole-carrier no-route topology was reported incomplete"
dashapi_client_topology_complete pppoe-wan lan3 || fail "proven PPPoE DSA uplink was reported incomplete"
if dashapi_client_topology_complete pppoe-wan ''; then fail "unresolved PPPoE topology was reported complete"; fi
wan_device=lan3.35
[ "$(dashapi_client_uplink_port pppoe-wan '' br-lan)" = lan3 ] ||
	fail "VLAN WAN device did not resolve to its physical DSA port"
wan_device=wan
[ "$(dashapi_client_uplink_port pppoe-wan '' br-lan)" = wan ] ||
	fail "dedicated WAN device was not accepted as a proven non-client edge"
dashapi_client_topology_complete pppoe-wan wan || fail "proven dedicated WAN topology was reported incomplete"
wan_device='@wan'
if dashapi_client_uplink_port pppoe-wan '' br-lan >/dev/null 2>&1; then
	fail "logical WAN alias was accepted without resolving its physical device"
fi

# A bridge-only AP has no default route on purpose.  A single carrier is an
# unambiguous uplink; multiple live ports must remain unresolved.
mkdir -p "$TMP/sys-class-net/lan1" "$TMP/sys-class-net/lan2" "$TMP/sys-class-net/lan3"
printf '1\n' >"$TMP/sys-class-net/lan1/carrier"
printf '0\n' >"$TMP/sys-class-net/lan2/carrier"
printf '0\n' >"$TMP/sys-class-net/lan3/carrier"
[ "$(dashapi_client_uplink_port '' '' br-lan "$TMP/sys-class-net")" = lan1 ] ||
	fail "sole-carrier AP uplink was not resolved"
printf '1\n' >"$TMP/sys-class-net/lan2/carrier"
if dashapi_client_uplink_port '' '' br-lan "$TMP/sys-class-net" >/dev/null 2>&1; then
	fail "ambiguous multi-carrier AP topology invented an uplink"
fi
unset -f ip bridge uci 2>/dev/null || true

# Every lite poll resolves topology from current state and retains no result
# after the request.  Repeated calls therefore re-run the resolver, while an
# unresolved AP topology remains explicitly incomplete rather than invented.
topology_calls="$TMP/topology.calls"
: >"$topology_calls"
ip() {
	printf '%s\n' ip >>"$topology_calls"
	[ "$1" = -4 ] && printf '%s\n' 'default via 192.168.1.254 dev br-lan'
}
uci() { printf '%s\n' uci >>"$topology_calls"; return 1; }
dashapi_client_uplink_port() {
	printf '%s\n' resolver >>"$topology_calls"
	printf '%s\n' lan1
}
dashapi_client_topology_live
[ "$DASHAPI_TOPOLOGY_UPLINK" = lan1 ] || fail "initial topology resolution failed"
dashapi_client_topology_live
[ "$(grep -c '^resolver$' "$topology_calls")" -eq 2 ] || fail "live topology result was retained between calls"
if find "$TMP" -maxdepth 1 -type f -name 'traffic.topology' -print -quit 2>/dev/null | grep -q .; then
	fail "live topology created retained telemetry"
fi

: >"$topology_calls"
dashapi_client_uplink_port() { printf '%s\n' resolver >>"$topology_calls"; return 1; }
dashapi_client_topology_live
[ "$DASHAPI_TOPOLOGY_COMPLETE" = false ] || fail "unresolved AP topology was reported complete"
[ -z "$DASHAPI_TOPOLOGY_UPLINK" ] || fail "unresolved AP topology invented an uplink"
dashapi_client_topology_live
[ "$(grep -c '^resolver$' "$topology_calls")" -eq 2 ] || fail "unresolved topology result was retained"

# The deployed bridge can temporarily have no default route at all.  Without a
# gateway/FDB observation no LAN member can honestly be identified as the
# backhaul, so DSA counters are withheld and only the known Wi-Fi subtotal is
# available with topology_complete=false.
: >"$topology_calls"
ip() { printf '%s\n' ip >>"$topology_calls"; return 0; }
uci() {
	printf '%s\n' uci >>"$topology_calls"
	[ "$1" = -q ] && [ "$2" = get ] && [ "$3" = network.lan.device ] || return 1
	printf '%s\n' br-lan
}
dashapi_client_topology_live
[ -z "$DASHAPI_TOPOLOGY_DEFAULT_DEV" ] || fail "no-route fixture invented a default device"
[ "$DASHAPI_TOPOLOGY_LAN_DEV" = br-lan ] || fail "no-route AP did not retain its bridge device"
[ "$DASHAPI_TOPOLOGY_COMPLETE" = false ] || fail "no-default-route AP topology was reported complete"
[ -z "$DASHAPI_TOPOLOGY_UPLINK" ] || fail "no-default-route AP topology invented an uplink"
unset -f ip uci dashapi_client_uplink_port 2>/dev/null || true

# Link diagnostics are observations only.  Prefer the per-netdevice kernel
# counter; use one bounded log snapshot only for ports whose kernel lacks it.
# The fixture also proves that bridge "disabled state" duplicates are not
# added when explicit MT7530 "Link is Down" messages are available.
link_root="$TMP/link-sys-class-net"
link_state="$TMP/link-state"
mkdir -p "$link_root/lan1" "$link_root/lan2" "$link_root/lan2.35" "$link_root/lan3" "$link_state"
printf '1\n' >"$link_root/lan1/carrier"
printf '100\n' >"$link_root/lan1/speed"
printf '3\n' >"$link_root/lan1/carrier_down_count"
printf '1\n' >"$link_root/lan2/carrier"
printf '1000\n' >"$link_root/lan2/speed"
printf '1\n' >"$link_root/lan2/carrier_down_count"
printf '1\n' >"$link_root/lan2.35/carrier"
printf '100\n' >"$link_root/lan2.35/speed"
printf '99\n' >"$link_root/lan2.35/carrier_down_count"
printf '0\n' >"$link_root/lan3/carrier"
printf '0\n' >"$link_root/lan3/speed"
cat >"$TMP/link-log.txt" <<'LOG'
kernel: mt7530-mdio mdio-bus:1f lan3: Link is Down
kernel: br-lan: port 3(lan3) entered disabled state
kernel: mt7530-mdio mdio-bus:1f lan3: Link is Down
kernel: br-lan: port 3(lan3) entered disabled state
LOG
cat >"$TMP/link-logread.sh" <<'SH'
#!/bin/sh
cat "$CR6608_TEST_LINK_LOG"
SH
chmod 0700 "$TMP/link-logread.sh"
CR6608_TEST_LINK_LOG="$TMP/link-log.txt"
export CR6608_TEST_LINK_LOG
link_run_calls="$TMP/link-run.calls"
: >"$link_run_calls"
run_limit() {
	[ "$1" = 2 ] || fail "link logread timeout was not two seconds"
	shift
	printf 'run\n' >>"$link_run_calls"
	"$@"
}
catv() { [ -r "$1" ] && cat "$1" 2>/dev/null; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '; }
jstr() { printf '"%s"' "$(json_escape "$1")"; }
jnum() {
	case "$1" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$1" ;; esac
}
# shellcheck disable=SC1090
. "$LINK_DIAGNOSTICS_HELPER"
cache_dir="$link_state"
CR6608_SYS_CLASS_NET="$link_root"
CR6608_LOGREAD_BIN="$TMP/link-logread.sh"
export CR6608_SYS_CLASS_NET CR6608_LOGREAD_BIN
dashapi_collect_link_diagnostics
printf '%s\n' "$DASHAPI_LINK_DIAGNOSTICS_JSON" >"$TMP/link-diagnostics.json"
[ "$(wc -l <"$link_run_calls" | tr -d ' ')" -eq 1 ] ||
	fail "DSA diagnostics did not take exactly one bounded log snapshot"
python3 - "$TMP/link-diagnostics.json" <<'PY'
import json
import pathlib
import sys

d = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert d["read_only"] is True
assert d["boot_observation"] is True
assert d["complete"] is False
assert d["source"] == "mixed"
assert d["count_scope"] == "per-port-source-see-ports"
assert d["link_down_events_total"] == 6
assert d["slow_100m_ports"] == 1
p = {item["name"]: item for item in d["ports"]}
assert p["lan1"]["link_down_events"] == 3
assert p["lan1"]["link_down_count_complete"] is True
assert p["lan1"]["slow_100m"] is True
assert p["lan1"]["capability_mbps"] == 1000
assert p["lan2"]["slow_100m"] is False
assert "lan2.35" not in p
assert p["lan3"]["link_down_events"] == 2
assert p["lan3"]["link_down_source"] == "logread-buffer"
assert p["lan3"]["link_down_count_complete"] is False
PY
[ "$(dashapi_link_down_log_count lan3 "$TMP/link-log.txt")" -eq 2 ] ||
	fail "explicit Link Down messages were double-counted with bridge state messages"
[ "$(dashapi_dsa_link_down_count "$link_root" lan3)" = '0|unavailable|false' ] ||
	fail "missing sysfs/log evidence was presented as complete"
unset CR6608_SYS_CLASS_NET CR6608_LOGREAD_BIN CR6608_TEST_LINK_LOG
unset -f run_limit catv json_escape jstr jnum 2>/dev/null || true

# Source contracts guard the actual call sites as well as the extracted code.
grep -Fq 'collector_started="$(dashapi_monotonic_seconds 2>/dev/null)"' "$SOURCE" ||
	fail "collector deadline does not use monotonic uptime"
grep -Fq 'traffic_uplink="$(dashapi_client_uplink_port "$default_dev" "$default_gw" "$lan_dev"' "$SOURCE" ||
	fail "full collector does not resolve the physical uplink"
grep -Fq 'dashapi_client_topology_live' "$SOURCE" ||
	fail "lite collector does not resolve topology from live state"
lite_source="$(sed -n '/^case "${internal_refresh}:&${QUERY_STRING:-}&" in$/,/^esac$/p' "$SOURCE")"
printf '%s\n' "$lite_source" | grep -Fq 'dashapi_client_topology_live' ||
	fail "lite request does not invoke the live topology resolver"
grep -Fq '"scope":"client-edge"' "$SOURCE" || fail "traffic scope is not explicit"
grep -Fq '"calendar_accounting":false' "$SOURCE" || fail "volatile counters still claim calendar accounting"
grep -Fq '"counter_signature"' "$SOURCE" || fail "traffic topology signature is not exposed"
grep -Fq '"uplink_device":"%s"' "$SOURCE" || fail "lite traffic omits the resolved uplink device"
grep -Fq 'dashapi_client_edge_counters /proc/net/dev "$lite_uplink" "$DASHAPI_TOPOLOGY_COMPLETE"' "$SOURCE" ||
	fail "lite traffic does not fail closed when topology is incomplete"
grep -Fq 'rx_bps=""; tx_bps=""' "$SOURCE" || fail "full collector fabricates rates without a retained baseline"
! grep -Eq '(^|[[:space:]])(dashapi_counter_rate|dashapi_scoped_counter_rate)\(' "$SOURCE" ||
	fail "retained-baseline traffic rate helper remains"
! grep -Eq '(^|[[:space:]])(old_rx|old_tx|old_ts|old_signature)=' "$SOURCE" ||
	fail "retained traffic baseline variables remain"
! grep -Eq '>[[:space:]]*"\$cache_dir/(traffic|traffic\.topology|iface\.|sta\.|survey\.)' "$SOURCE" ||
	fail "collector still writes retained telemetry"
[ "$(grep -Fc 'dashapi_client_topology_complete ' "$SOURCE")" -eq 2 ] ||
	fail "lite/full collectors do not share topology completeness semantics"
grep -Fq '/sys/class/net/phy[0-9]*-ap[0-9]*' "$SOURCE" || fail "dynamic AP interfaces are not enumerated"
! grep -Fq '$1 ~ /^phy[0-9]+-ap[0-9]+:$/ {dl+=$10; ul+=$2}' "$SOURCE" ||
	fail "legacy Wi-Fi-only aggregate remains"
grep -Fq 'exec /usr/bin/setsid "$@"' "$RUNNER" ||
	fail "bounded commands do not get a private process group"
grep -Fq 'run_limit_signal_group TERM "$_rl_pid"' "$RUNNER" ||
	fail "timeout does not TERM the process group"
grep -Fq 'run_limit_signal_group KILL "$_rl_pid"' "$RUNNER" ||
	fail "timeout does not KILL the process group"
! grep -Fq 'guard=$!' "$RUNNER" || fail "legacy watchdog process remains"

# A previously collected iw/iwinfo snapshot must remain authoritative even if
# the collector no longer has enough budget to execute another driver command.
# Prefer the direct iw value, accept iwinfo as a live fallback, and never turn
# malformed text into a numeric power reading.
# shellcheck disable=SC1090
. "$TXPOWER_HELPER"
txpower_both="$(printf '%s\n' \
	'txpower 38.00 dBm' \
	'Tx-Power: 37 dBm Link Quality: 70/70' | txpower_applied_from_text)"
[ "$txpower_both" = 38.00 ] || fail "iw snapshot was not preferred: $txpower_both"
txpower_iwinfo="$(printf '%s\n' \
	'Tx-Power: 38 dBm Link Quality: 70/70' | txpower_applied_from_text)"
[ "$txpower_iwinfo" = 38 ] || fail "iwinfo snapshot was not reused: $txpower_iwinfo"
txpower_bad="$(printf '%s\n' 'txpower unavailable' 'Tx-Power: unknown' | txpower_applied_from_text)"
[ -z "$txpower_bad" ] || fail "malformed snapshot became numeric: $txpower_bad"
txpower_max_lower="$(printf '%s\n' '  37 dbm (5011 mW)' '* 38 dbm (6309 mW)' | txpower_max_from_text)"
[ "$txpower_max_lower" = 38 ] || fail "lowercase dbm maximum was lost: $txpower_max_lower"
txpower_max_mixed="$(printf '%s\n' '  37 dBm (5011 mW)' '* 38 dBm (6309 mW)' | txpower_max_from_text)"
[ "$txpower_max_mixed" = 38 ] || fail "mixed-case dBm maximum was lost: $txpower_max_mixed"
txpower_max_bad="$(printf '%s\n' 'Current maximum dBm unavailable' | txpower_max_from_text)"
[ -z "$txpower_max_bad" ] || fail "malformed maximum became numeric: $txpower_max_bad"

two_radio_snapshot='phy#1
	Interface phy1-ap0
		ssid Smart ap 5G
		type AP
		channel 36 (5180 MHz), width: 80 MHz
		txpower 38.00 dBm
phy#0
	Interface phy0-ap0
		ssid Smart ap 2.4G
		type AP
		channel 11 (2462 MHz), width: 20 MHz
		txpower 38.00 dBm'
radio0_snapshot="$(printf '%s\n' "$two_radio_snapshot" | iw_snapshot_for_if phy0-ap0)"
radio1_snapshot="$(printf '%s\n' "$two_radio_snapshot" | iw_snapshot_for_if phy1-ap0)"
[ "$(printf '%s\n' "$radio0_snapshot" | txpower_applied_from_text)" = 38.00 ] ||
	fail "radio0 was lost from the shared iw snapshot"
[ "$(printf '%s\n' "$radio1_snapshot" | txpower_applied_from_text)" = 38.00 ] ||
	fail "radio1 was lost from the shared iw snapshot"
! printf '%s\n' "$radio0_snapshot" | grep -Fq phy1-ap0 ||
	fail "radio0 snapshot leaked into radio1"
! printf '%s\n' "$radio1_snapshot" | grep -Fq phy0-ap0 ||
	fail "radio1 snapshot leaked into radio0"
! printf '%s\n' "$radio1_snapshot" | grep -Fq 'phy#0' ||
	fail "radio1 snapshot leaked the next phy header"

# A valid early-boot status can contain only radio0 even though the shared iw
# snapshot already sees radio1.  The mapper must retry ubus once, recover the
# radio1 mapping, and avoid an extra call when the cached mapping already hits.
# shellcheck disable=SC1090
. "$WIRELESS_STATUS_HELPER"
wireless_status_calls="$TMP/wireless-status.calls"
wireless_status_live="$TMP/wireless-status.live"
printf '%s\n' '{"radio0":{"interfaces":[{"ifname":"phy0-ap0"}]},"radio1":{"interfaces":[{"ifname":"phy1-ap0"}]}}' >"$wireless_status_live"
uci() {
	[ "$1" = -q ] && [ "$2" = show ] && [ "$3" = wireless ] || return 1
	printf '%s\n' 'wireless.radio0=wifi-device' 'wireless.radio1=wifi-device'
}
jsonfilter() {
	_status_expr=""; _status_data="$(cat)"
	while [ "$#" -gt 0 ]; do
		case "$1" in -e) shift; _status_expr="$1" ;; esac
		shift
	done
	case "$_status_expr:$_status_data" in
		*@.radio0.interfaces*:*phy0-ap0*) printf '%s\n' phy0-ap0 ;;
		*@.radio1.interfaces*:*phy1-ap0*) printf '%s\n' phy1-ap0 ;;
	esac
}
ubus() {
	printf '%s\n' call >>"$wireless_status_calls"
	cat "$wireless_status_live"
}
wireless_status_snapshot_ready=1
wireless_status_snapshot='{"radio0":{"interfaces":[{"ifname":"phy0-ap0"}]}}'
: >"$wireless_status_calls"
[ "$(wifi_dev_for_if phy1-ap0)" = radio1 ] || fail "partial cached status did not recover radio1"
[ "$(wc -l <"$wireless_status_calls" | tr -d ' ')" -eq 1 ] || fail "partial cached status did not retry ubus exactly once"
: >"$wireless_status_calls"
[ "$(wifi_dev_for_if phy0-ap0)" = radio0 ] || fail "cached radio0 mapping was lost"
[ ! -s "$wireless_status_calls" ] || fail "cache hit performed an unnecessary ubus retry"
printf '%s\n' '{"radio0":{"interfaces":[{"ifname":"phy0-ap0"}]}}' >"$wireless_status_live"
: >"$wireless_status_calls"
if wifi_dev_for_if phy1-ap0 >/dev/null; then fail "missing live radio1 mapping was invented"; fi
[ "$(wc -l <"$wireless_status_calls" | tr -d ' ')" -eq 1 ] || fail "failed mapping retried ubus more than once"
unset -f uci jsonfilter ubus 2>/dev/null || true

# shellcheck disable=SC1090
. "$HELPERS"

mkdir -m 0700 "$TMP/bin"
cat >"$TMP/bin/date" <<'SH'
#!/bin/sh
printf 'date-called\n' >>"$CR6608_DATE_CALL_LOG"
cat "$CR6608_FAKE_WALL_FILE"
SH
chmod 0700 "$TMP/bin/date"
CR6608_DATE_CALL_LOG="$TMP/date.calls"
CR6608_FAKE_WALL_FILE="$TMP/wall-clock"
CR6608_PROC_UPTIME_FILE="$TMP/uptime"
export CR6608_DATE_CALL_LOG CR6608_FAKE_WALL_FILE CR6608_PROC_UPTIME_FILE
PATH="$TMP/bin:$PATH"
export PATH
: >"$CR6608_DATE_CALL_LOG"

# Simulate NTP first jumping years forwards and then backwards. Only the two
# explicit probes below may call date; collector deadlines use uptime.
printf '4102444800\n' >"$CR6608_FAKE_WALL_FILE"
wall_forward="$(date +%s)"
printf '100.75 50.00\n' >"$CR6608_PROC_UPTIME_FILE"
mono_forward="$(dashapi_monotonic_seconds)"

printf '1\n' >"$CR6608_FAKE_WALL_FILE"
wall_backward="$(date +%s)"
printf '103.10 51.00\n' >"$CR6608_PROC_UPTIME_FILE"
mono_backward="$(dashapi_monotonic_seconds)"

[ "$wall_forward" -gt "$wall_backward" ] || fail "wall-clock jump fixture is invalid"
[ "$mono_forward" -eq 100 ] || fail "uptime fraction was not truncated safely"
[ "$mono_backward" -eq 103 ] || fail "monotonic uptime did not advance"
[ "$(wc -l <"$CR6608_DATE_CALL_LOG" | tr -d ' ')" -eq 2 ] ||
	fail "monotonic helper consulted wall time"

unset CR6608_PROC_UPTIME_FILE
cache_dir="$TMP/state"
mkdir -m 0700 "$cache_dir"
close_dashboard_fds() { exec 4>&- 5>&- 6>&- 7>&- 8>&-; }
CR6608_DASHAPI_BUDGET=10
export CR6608_DASHAPI_BUDGET
# shellcheck disable=SC1090
. "$RUNNER"

monotonic_ms() {
	awk '{ printf "%.0f\n", $1 * 1000 }' /proc/uptime
}

process_alive() {
	_pid="$1"
	case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
	[ -r "/proc/$_pid/stat" ] || return 1
	_state="$(awk '
		{
			line=$0; close_at=0
			for (i=length(line)-1; i>0; i--)
				if (substr(line,i,2)==") ") { close_at=i; break }
			if (!close_at) exit 1
			split(substr(line,close_at+2), field, " ")
			print field[1]
		}' "/proc/$_pid/stat" 2>/dev/null || true)"
	[ -n "$_state" ] && [ "$_state" != Z ]
}

cat >"$TMP/result-command.sh" <<'SH'
#!/bin/sh
printf 'stdout-preserved\n'
printf 'stderr-preserved\n' >&2
sleep 0.2
exit 37
SH
chmod 0700 "$TMP/result-command.sh"
set +e
run_limit 2 "$TMP/result-command.sh" >"$TMP/result.out" 2>"$TMP/result.err"
result_rc=$?
set -e
[ "$result_rc" -eq 37 ] || fail "exit code changed from 37 to $result_rc"
[ "$(cat "$TMP/result.out")" = stdout-preserved ] || fail "stdout was not preserved"
[ "$(cat "$TMP/result.err")" = stderr-preserved ] || fail "stderr was not preserved"

cat >"$TMP/stubborn-command.sh" <<'SH'
#!/bin/sh
trap '' HUP INT TERM
printf '%s\n' "$$" >"$CR6608_TEST_PARENT_PID"
(
	trap '' HUP INT TERM
	while :; do sleep 1; done
) &
stubborn_child=$!
printf '%s\n' "$stubborn_child" >"$CR6608_TEST_CHILD_PID"
wait "$stubborn_child"
SH
chmod 0700 "$TMP/stubborn-command.sh"
CR6608_TEST_PARENT_PID="$TMP/stubborn-parent.pid"
CR6608_TEST_CHILD_PID="$TMP/stubborn-child.pid"
export CR6608_TEST_PARENT_PID CR6608_TEST_CHILD_PID

timeout_start="$(monotonic_ms)"
set +e
run_limit 1 "$TMP/stubborn-command.sh" >"$TMP/timeout.out" 2>"$TMP/timeout.err"
timeout_rc=$?
set -e
timeout_end="$(monotonic_ms)"
timeout_elapsed=$((timeout_end - timeout_start))
[ "$timeout_rc" -eq 124 ] || fail "timeout returned $timeout_rc instead of 124"
[ "$timeout_elapsed" -ge 900 ] || fail "timeout fired too early (${timeout_elapsed}ms)"
[ "$timeout_elapsed" -le 6000 ] || fail "timeout did not remain bounded (${timeout_elapsed}ms)"
[ -f "$collector_degraded_marker" ] || fail "timeout did not mark snapshot degraded"

stubborn_parent="$(sed -n '1p' "$CR6608_TEST_PARENT_PID" 2>/dev/null || true)"
stubborn_child="$(sed -n '1p' "$CR6608_TEST_CHILD_PID" 2>/dev/null || true)"
[ -n "$stubborn_parent" ] || fail "stubborn parent did not start"
[ -n "$stubborn_child" ] || fail "stubborn child did not start"
reap_i=0
while { process_alive "$stubborn_parent" || process_alive "$stubborn_child"; } &&
	[ "$reap_i" -lt 30 ]; do
	sleep 0.1
	reap_i=$((reap_i + 1))
done
! process_alive "$stubborn_parent" || fail "timed-out parent $stubborn_parent remains alive"
! process_alive "$stubborn_child" || fail "timed-out child $stubborn_child remains alive"

[ -z "$RUN_LIMIT_PID" ] || fail "active runner PID leaked"
[ -z "$RUN_LIMIT_START" ] || fail "active runner identity leaked"
[ -z "$RUN_LIMIT_OUT" ] || fail "runner stdout path leaked"
[ -z "$RUN_LIMIT_ERR" ] || fail "runner stderr path leaked"
if find "$cache_dir" -maxdepth 1 -type f \
	\( -name '.dashcmd-out.*' -o -name '.dashcmd-err.*' \) \
	-print -quit 2>/dev/null | grep -q .; then
	fail "private runner files leaked"
fi

printf 'dashapi2_runtime=pass\n'
