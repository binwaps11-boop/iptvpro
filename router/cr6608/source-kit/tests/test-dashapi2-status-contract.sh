#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
API="$ROOT/files/www/cgi-bin/dashapi2"
ACTION="$ROOT/files/www/cgi-bin/dashaction"
CTL="$ROOT/files/www/cgi-bin/dashctl"
CACHE_STATE="$ROOT/files/usr/libexec/cr6608-dashboard-cache-state"
INVALIDATE="$ROOT/files/usr/sbin/cr6608-dashboard-invalidate"
IFACE_HOTPLUG="$ROOT/files/etc/hotplug.d/iface/99-cr6608-dashboard-cache"
NET_HOTPLUG="$ROOT/files/etc/hotplug.d/net/99-cr6608-dashboard-cache"
BUILD="$ROOT/build.sh"

fail() { printf 'dashapi2_status_contract=FAIL %s\n' "$1" >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-dashapi-json.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# Execute the actual JSON builders.  This catches malformed responses caused
# by control bytes in an SSID/UCI value and JSON-invalid leading-zero numbers.
sed -n '/^json_escape() {$/,/^}$/p; /^jstr()/p; /^jnum() {$/,/^}$/p' "$API" > "$TMP/builders.sh"
# shellcheck disable=SC1090
. "$TMP/builders.sh"
encoded="$(jstr "$(printf 'alpha\tbeta\001gamma\r\n\\path "quoted"')")"
python3 - "$encoded" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert all(ord(char) >= 0x20 for char in value)
assert '\\path' in value
assert '"quoted"' in value
PY
[ "$(jnum 0)" = 0 ]
[ "$(jnum 0.5)" = 0.5 ]
[ "$(jnum -12.25)" = -12.25 ]
[ "$(jnum 038)" = null ]
[ "$(jnum -01)" = null ]
[ "$(jnum 1.2.3)" = null ]

# sha256sum is present in the target image; BusyBox cksum is not enabled in
# the CR6608 profile.  A host-only cksum dependency makes the live dashboard
# return cache_fingerprint after an otherwise successful login.
grep -Fq 'sha256sum' "$CACHE_STATE"
grep -Fq 'sha256sum' "$API"
! grep -Eq '(^|[^[:alnum:]_])cksum([^[:alnum:]_]|$)' "$CACHE_STATE" "$API"

for cache_hook in "$INVALIDATE" "$IFACE_HOTPLUG" "$NET_HOTPLUG"; do
	[ -s "$cache_hook" ]
	[ "$(sed -n '1p' "$cache_hook")" = '#!/bin/sh' ]
	sh -n "$cache_hook"
done

# LuCI/SSH/network writers that bypass the Smart AP CGIs still advance the
# shared generation.  Hotplug handlers stay non-blocking and delegate retries
# to the FD-clean helper.
grep -Fq 'CACHE_STATE_LIB="${CR6608_DASHBOARD_CACHE_STATE_LIB:-/usr/libexec/cr6608-dashboard-cache-state}"' "$INVALIDATE"
grep -Fq '. "$CACHE_STATE_LIB" || exit 1' "$INVALIDATE"
grep -Fq 'for cr6608_close_fd in 4 5 6 7 8; do' "$INVALIDATE"
grep -Fq 'eval "exec ${cr6608_close_fd}>&-"' "$INVALIDATE"
grep -Fq 'CR6608_DASHBOARD_INVALIDATE_ATTEMPTS:-5' "$INVALIDATE"
grep -Fq 'cr6608_dashboard_cache_invalidate && exit 0' "$INVALIDATE"
grep -Fq 'case "${ACTION:-}" in ifup|ifdown|ifupdate)' "$IFACE_HOTPLUG"
grep -Fq 'case "${ACTION:-}" in add|remove|move|register|unregister)' "$NET_HOTPLUG"
for cache_hotplug in "$IFACE_HOTPLUG" "$NET_HOTPLUG"; do
	grep -Fq '[ -x /usr/sbin/cr6608-dashboard-invalidate ] || exit 0' "$cache_hotplug"
	grep -Fq '/usr/sbin/cr6608-dashboard-invalidate >/dev/null 2>&1 &' "$cache_hotplug"
done

# Each new overlay script is both a required source and a shell-syntax input;
# the existing directory-wide chmod pass makes the installed helper/hooks 0755.
for cache_source in \
	'"${SRC_FILES}/usr/sbin/cr6608-dashboard-invalidate"' \
	'"${SRC_FILES}/etc/hotplug.d/iface/99-cr6608-dashboard-cache"' \
	'"${SRC_FILES}/etc/hotplug.d/net/99-cr6608-dashboard-cache"'; do
	[ "$(grep -F -c "$cache_source" "$BUILD")" -ge 2 ]
done
grep -Fq 'etc/init.d etc/hotplug.d etc/rc.d etc/uci-defaults lib/preinit usr/bin usr/sbin usr/libexec www/cgi-bin; do' "$BUILD"

grep -Fq 'Content-Type: application/json; charset=utf-8' "$API"
grep -Fq '\"radio\":$(jstr "$dev")' "$API"
grep -Fq '\"up\":true,\"disabled\":false,\"state\":\"up\",\"reason\":$(jstr "$tx_reason"),\"radio_reason\":\"\",\"power_status\":$(jstr "$tx_state"),\"power_reason\":$(jstr "$tx_reason")' "$API"
grep -Fq '\"up\":false,\"disabled\":$([ "$disabled" = "1" ]' "$API"
grep -Fq '\"radio_reason\":$(jstr "$reason"),\"power_status\":$(jstr "$state"),\"power_reason\":$(jstr "$reason")' "$API"

# Both active and inactive constructors expose the flat status contract while
# retaining the nested txpower object for older Smart AP clients.
[ "$(grep -F -c '\"requested_dbm\":$(jnum "$tx_req"),\"applied_dbm\"' "$API")" -ge 2 ]
[ "$(grep -F -c '\"regulatory_max_dbm\":$(jnum "$tx_regulatory_max"),\"channel_max_dbm\"' "$API")" -ge 2 ]
[ "$(grep -F -c '\"driver_accepted_dbm\"' "$API")" -ge 2 ]
[ "$(grep -F -c '\"current_reported_dbm\"' "$API")" -ge 2 ]
[ "$(grep -F -c '\"power_status\"' "$API")" -ge 2 ]
[ "$(grep -F -c '\"power_reason\"' "$API")" -ge 2 ]

grep -Fq "''|*[!0-9.]*|.*|*.|*.*.*) printf 'null'" "$API"
grep -Fq "0|0.[0-9]*) printf '%s' \"\$number\"" "$API"
grep -Fq "0*) printf 'null'" "$API"
grep -Fq '[ "$role" = AP ] || continue' "$API"
grep -Fq 'hostapd_raw="$(ubus -S call "hostapd.${IF}" get_status' "$API"
grep -Fq 'hostapd_rc=$?' "$API"
grep -Fq 'case "$hostapd_rc" in' "$API"
grep -Fq '[ "$hostapd_state" = ENABLED ] || continue' "$API"
grep -Fq 'jsonfilter -e "@.${dev}.interfaces[*].ifname"' "$API"
grep -Fq 'phy_for_dev()' "$API"
! grep -Eq 'case "\$wiphy" in 0\).*radio0|case "\$dev" in radio0\).*phy0' "$API"
grep -Fq 'txpower_effective_max()' "$API"
grep -Fq 'tolower($0) ~ /dbm/' "$API"
grep -Fq 'if (token !~ /^[0-9]+([.][0-9]+)?$/) next' "$API"
grep -Fq 'iwinfo "$1" txpowerlist 2>/dev/null | txpower_max_from_text' "$API"
grep -Fq 'tx_max="$(txpower_effective_max "$tx_regulatory_max" "$tx_driver_max")"' "$API"
! grep -Fq 'tx_max="$tx_driver_max"' "$API"
grep -Fq 'tx_applied="$({ printf '\''%s\n'\'' "$iw_snapshot"; printf '\''%s\n'\'' "$cli"; } | txpower_applied_from_text)"' "$API"
grep -Fq '[ -n "$tx_applied" ] || tx_applied="$(txpower_applied_for_if "$IF")"' "$API"
grep -Fq 'tx_regulatory_max="$(txpower_channel_max_for_dev "$dev" "$IF" "$phy_hint")"' "$API"

# Every route is live/storage-free, including omitted live=1 and the removed
# internal prewarm compatibility path. No snapshot/publish ABI remains.
grep -Fq 'CACHE_STATE_LIB="${CR6608_DASHBOARD_CACHE_STATE_LIB:-/usr/libexec/cr6608-dashboard-cache-state}"' "$API"
grep -Fq 'cache_dir="$CR6608_DASHBOARD_CACHE_DIR"' "$API"
grep -Fq 'live_only=1' "$API"
grep -Fq '"snapshot_live":true,"snapshot_stored":false' "$API"
grep -Fq 'cr6608_dashboard_cache_collector_acquire' "$API"
grep -Fq 'cr6608_dashboard_cache_recover_dirty' "$API"
grep -Fq 'cr6608_dashboard_cache_reader_acquire' "$API"
grep -Fq 'if [ "$internal_refresh" = 1 ]; then' "$API"
grep -Fq 'dashapi_telemetry_purge' "$API"
for forbidden_cache_path in cache_load_view dashapi_start_detached_refresh \
	cr6608_dashboard_cache_snapshot cr6608_dashboard_cache_inspect \
	cr6608_dashboard_cache_publish 'response_cache=' 'perf_cache=' \
	'cpu_prev=' 'traffic_prev=' 'survey_prev='; do
	! grep -Fq "$forbidden_cache_path" "$API" ||
		fail "retained cache path remains: $forbidden_cache_path"
done
release_line="$(grep -nF 'cr6608_dashboard_cache_reader_release' "$API" | tail -n1 | cut -d: -f1)"
socket_line="$(grep -nF 'printf '\''{"ok":true,"snapshot_live":true' "$API" | cut -d: -f1)"
[ -n "$release_line" ] && [ -n "$socket_line" ] && [ "$release_line" -lt "$socket_line" ] ||
	fail 'reader lock is not released before the response socket write'
grep -Fq '"authenticated":false' "$API"
grep -Fq 'CR6608_DASHBOARD_CACHE_DIR="${CR6608_DASHBOARD_CACHE_DIR:-/var/run/cr6608-dashboard-cache}"' "$CACHE_STATE"
grep -Fq 'stat -c %u "$_cache_dir"' "$CACHE_STATE"
grep -Fq 'chmod 0700 "$_cache_dir"' "$CACHE_STATE"
grep -Fq 'flock -xn 8' "$CACHE_STATE"
grep -Fq 'mutation.dirty' "$CACHE_STATE"
grep -Fq 'cr6608_dashboard_cache_recover_dirty()' "$CACHE_STATE"
grep -Fq 'cr6608_dashboard_cache_flock_bounded x 5 5' "$CACHE_STATE"
grep -Fq 'cr6608_dashboard_telemetry_purge()' "$CACHE_STATE"
! grep -Fq 'CR6608_DASHBOARD_JSONFILTER_BIN' "$CACHE_STATE"
! grep -Fq 'cr6608_dashboard_cache_publish()' "$CACHE_STATE"
grep -Fq 'cr6608_dashboard_cache_mutation_begin' "$ACTION"
grep -Fq 'cr6608_dashboard_cache_mutation_finish' "$ACTION"
grep -Fq 'cr6608_dashboard_cache_mutation_begin' "$CTL"
grep -Fq 'cr6608_dashboard_cache_mutation_finish' "$CTL"
grep -Fq 'cr6608_dashboard_cache_clear' "$CTL"
! grep -Fq '/tmp/dashapi2.' "$API"
! grep -Fq '/tmp/dashapi2.' "$ACTION"
! grep -Fq '/tmp/dashapi2.' "$CTL"
! grep -Fq 'dashapi2.invalidate' "$API"
! grep -Fq 'dashapi2.invalidate' "$ACTION"
! grep -Fq 'dashapi2.invalidate' "$CTL"
grep -Fq 'collector_budget_seconds="${CR6608_DASHAPI_BUDGET:-10}"' "$API"
grep -Fq 'remaining="$(collector_remaining)"' "$API"
grep -Fq '"collector_degraded":%s' "$API"
grep -Fq 'collector_remaining >/dev/null || { : > "$collector_degraded_marker"; return 124; }' "$API"
grep -Fq 'cr6608_ubus "$@"' "$API"
grep -Fq 'iw_dev_snapshot="$(iw dev 2>/dev/null)"' "$API"
grep -Fq 'wireless_status_snapshot="$(ubus -S call network.wireless status 2>/dev/null)"' "$API"
grep -Fq 'wireless_status_snapshot_ready=0' "$API"
grep -Fq "/usr/bin/jsonfilter -e '@.radio0.up'" "$API"
grep -Fq 'wireless_status_snapshot_ready=1' "$API"
grep -Fq 'status="$wireless_status_snapshot"' "$API"
grep -Fq 'dev="$(wifi_dev_from_status "$ifn" "$status")" || dev=""' "$API"
grep -Fq '[ "$used_cached" = 1 ] || return 1' "$API"
grep -Fq 'status="$(ubus -S call network.wireless status 2>/dev/null)"' "$API"
[ "$(grep -Fc 'dev="$(wifi_dev_from_status "$ifn" "$status")" || dev=""' "$API")" -eq 2 ]
grep -Fq 'ifc="$(uci_iface_for_if "$IF" "$role" "$dev")"' "$API"
grep -Fq 'iw_snapshot="$(printf '\''%s\n'\'' "$iw_dev_snapshot" | iw_snapshot_for_if "$IF")"' "$API"
grep -Fq '124)' "$API"
grep -Fq ': > "$collector_degraded_marker"' "$API"
! grep -Fq '[ -z "$hostapd_state" ] || [ "$hostapd_state" = ENABLED ] || continue' "$API"
grep -Fq '[ -n "$ssid" ] || ssid="$(printf '\''%s\n'\'' "$iw_snapshot"' "$API"
grep -Fq '[ -n "$channel" ] || channel="$(printf '\''%s\n'\'' "$iw_snapshot"' "$API"
grep -Fq '[ -n "$htmode" ] || htmode="$(uci -q get wireless."$dev".htmode' "$API"
grep -Fq 'phy_hint="$(readlink -f "/sys/class/net/$IF/phy80211" 2>/dev/null)"' "$API"
grep -Fq "case \"\$phy_digits\" in ''|*[!0-9]*) phy_hint=\"\" ;; esac" "$API"
grep -Fq '[ "$internal_refresh" = 0 ]' "$API"
grep -Fq '"ipv6_stack":%s,"ipv6_lan":%s,"ipv6_bridge_passthrough":true' "$API"
grep -Fq 'cat /proc/sys/net/ipv6/conf/all/disable_ipv6' "$API"
grep -Fq 'ip -6 -o addr show dev "$lan_dev"' "$API"

# DSA link diagnostics remain observational: use the kernel counter when
# available and a single time-bounded log snapshot as an honest fallback.
link_diagnostics_block="$(sed -n '/^# BEGIN CR6608_DASHAPI2_LINK_DIAGNOSTICS_HELPER$/,/^# END CR6608_DASHAPI2_LINK_DIAGNOSTICS_HELPER$/p' "$API")"
printf '%s\n' "$link_diagnostics_block" | grep -Fq 'carrier_down_count'
printf '%s\n' "$link_diagnostics_block" | grep -Fq 'run_limit 2 "$_ld_bin"'
printf '%s\n' "$link_diagnostics_block" | grep -Fq 'tail -n 2048'
printf '%s\n' "$link_diagnostics_block" | grep -Fq '\"read_only\":true'
printf '%s\n' "$link_diagnostics_block" | grep -Fq '\"capability_mbps\":1000'
printf '%s\n' "$link_diagnostics_block" | grep -Fq 'since-interface-registration-current-boot'
printf '%s\n' "$link_diagnostics_block" | grep -Fq 'available-current-boot-log-buffer'
! printf '%s\n' "$link_diagnostics_block" | grep -Eq '/etc/init.d/network|wifi (reload|down|up)|ifdown|ifup|uci (set|commit)'
grep -Fq 'dashapi_collect_link_diagnostics' "$API"
grep -Fq '"link_diagnostics":%s' "$API"

# Station rates retain the full iw bitrate value (MCS/NSS/GI/channel width)
# while the original numeric tx_rate/rx_rate fields remain API-compatible.
grep -Fq '/tx bitrate:/ { txr=$3; txdetail=$0; sub(/^[ \t]*tx bitrate:[ \t]*/, "", txdetail) }' "$API"
grep -Fq '/rx bitrate:/ { rxr=$3; rxdetail=$0; sub(/^[ \t]*rx bitrate:[ \t]*/, "", rxdetail) }' "$API"
grep -Fq '"tx_rate":%s,"rx_rate":%s,"tx_rate_detail":%s,"rx_rate_detail":%s' "$API"
grep -Fq '"$(jnum "$txr")" "$(jnum "$rxr")" "$(jstr "$txdetail")" "$(jstr "$rxdetail")"' "$API"

# The guarded UL host-request state and performance fields are both read live so
# a mask change or guard trip appears in the same Smart AP refresh.  The API
# must keep host arming separate from airtime, OTA, and sale evidence.
grep -Fq 'ul_guard_state="$(sed -n' "$API"
grep -Fq 'perf="${perf%?},\"ul_muru_state\"' "$API"
grep -Fq '\"ul_muru_reason\"' "$API"
grep -Fq '\"ul_muru_module\"' "$API"
grep -Fq '\"ul_muru_guard_state\"' "$API"
grep -Fq '\"ul_muru_guard_reason\"' "$API"
grep -Fq '\"ul_muru_legacy_module\"' "$API"
grep -Fq '\"ul_muru_mask_module\"' "$API"
grep -Fq '\"ul_muru_host_request\"' "$API"
grep -Fq '\"ul_muru_airtime_evidence\"' "$API"
grep -Fq '\"ul_muru_ota_evidence\"' "$API"
grep -Fq '\"ul_muru_sale_ready\"' "$API"
grep -Fq '\"ul_muru_guard_running\"' "$API"
grep -Fq '\"ul_muru_guard_healthy\"' "$API"
grep -Fq '\"ul_muru_guard_age_s\"' "$API"
grep -Fq 'dashapi_ul_guard_health()' "$API"
grep -Fq 'dashapi_ul_muru_host_state()' "$API"
grep -Fq '/sys/module/mt7915e/parameters/cr6608_muru_mask' "$API"
grep -Fq 'ul_muru_airtime_evidence=unverified' "$API"
grep -Fq 'ul_muru_ota_evidence=not-established' "$API"
grep -Fq 'ul_muru_sale_ready=false' "$API"
! grep -Fq 'ul_muru_sale_ready=true' "$API"
grep -Fq '/etc/init.d/cr6608-ul-muru-guard running' "$API"
perf_live_line="$(grep -nF 'drv_banner="$(dmesg' "$API" | cut -d: -f1)"
ul_inject_line="$(grep -nF 'perf="${perf%?},\"ul_muru_state\"' "$API" | cut -d: -f1)"
[ -n "$perf_live_line" ] && [ -n "$ul_inject_line" ] && [ "$ul_inject_line" -gt "$perf_live_line" ]

ul_host_state_block="$(sed -n '/^# BEGIN CR6608_DASHAPI2_UL_MURU_HOST_STATE_HELPER$/,/^# END CR6608_DASHAPI2_UL_MURU_HOST_STATE_HELPER$/p' "$API")"
[ -n "$ul_host_state_block" ]
printf '%s\n' "$ul_host_state_block" >"$TMP/ul-host-state.sh"
# shellcheck disable=SC1090
. "$TMP/ul-host-state.sh"
[ "$(dashapi_ul_muru_host_state 15 armed true)" = mask15-guarded ]
[ "$(dashapi_ul_muru_host_state 15 armed false)" = mask15-guard-unhealthy ]
[ "$(dashapi_ul_muru_host_state 15 reboot-required true)" = mask15-guard-unhealthy ]
[ "$(dashapi_ul_muru_host_state 0 disabled false)" = mask0-disabled ]
[ "$(dashapi_ul_muru_host_state 0 fault-latched false)" = mask0-fault-disabled ]
[ "$(dashapi_ul_muru_host_state 0 service-disable-failed false)" = mask0-fault-disabled ]
[ "$(dashapi_ul_muru_host_state 0 missing false)" = mask0-guard-unhealthy ]
[ "$(dashapi_ul_muru_host_state 0 invalid false)" = mask0-guard-unhealthy ]
[ "$(dashapi_ul_muru_host_state 0 unavailable false)" = mask0-guard-unhealthy ]
[ "$(dashapi_ul_muru_host_state missing armed true)" = unknown ]
[ "$(dashapi_ul_muru_host_state 7 armed true)" = unknown ]

printf 'dashapi2_status_contract=pass\n'
