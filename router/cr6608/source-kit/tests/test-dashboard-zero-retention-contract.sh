#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
API="$ROOT/files/www/cgi-bin/dashapi2"
STATE="$ROOT/files/usr/libexec/cr6608-dashboard-cache-state"

INDEX="$ROOT/files/www/index.html"
DASHBOARD="$ROOT/files/www/dashboard.js"
ZERO_RETENTION="$ROOT/files/www/smartap-zero-retention.js"
DEFAULTS="$ROOT/files/etc/uci-defaults/99-cr6608-runtime-services"
BUILD="$ROOT/build.sh"
REMOTE_BUILD="$ROOT/build.remote.sh"

fail() {
	printf 'dashboard_zero_retention_contract=FAIL %s\n' "$1" >&2
	exit 1
}

# The router's BusyBox sleep rejects fractional arguments. Short collector
# waits must go through the quiet ucode-backed compatibility helper so a live
# dashboard cannot flood logread with "sleep: invalid number" errors.
grep -Fq 'cr6608_dashboard_cache_fast_grace() {' "$STATE" ||
	fail 'BusyBox-compatible short-delay helper is missing'
grep -Fq "sleep 0.1 2>/dev/null && return 0" "$STATE" ||
	fail 'fractional sleep probe is not quiet'
grep -Fq "/usr/bin/ucode -e 'sleep(100)' >/dev/null 2>&1" "$STATE" ||
	fail 'ucode millisecond fallback is missing'
[ "$(grep -Ec '^[[:space:]]*sleep 0\.1([[:space:]]|$)' "$STATE" || true)" -eq 1 ] ||
	fail 'fractional sleep exists outside the quiet compatibility probe'

# The live entry point may keep bounded state in the open page's heap, but it
# must never create browser-persistent state. The migration helper is the sole
# Web Storage exception: it may only remove exact legacy keys.
for live_ui in "$INDEX" "$DASHBOARD"; do
	if grep -Eiq 'localStorage|sessionStorage|document[[:space:]]*\.[[:space:]]*cookie|cookieStore|openDatabase|indexedDB|CacheStorage|(^|[^[:alnum:]_])caches([^[:alnum:]_]|$)|serviceWorker|ServiceWorkerRegistration|navigator[[:space:]]*\.[[:space:]]*storage|StorageFoundation|sharedStorage|show(OpenFile|SaveFile|Directory)Picker' "$live_ui"; then
		fail "browser persistence API remains in $(basename "$live_ui")"
	fi
done
if grep -Eiq 'document[[:space:]]*\.[[:space:]]*cookie|cookieStore|openDatabase|indexedDB|CacheStorage|(^|[^[:alnum:]_])caches([^[:alnum:]_]|$)|serviceWorker|ServiceWorkerRegistration|navigator[[:space:]]*\.[[:space:]]*storage|StorageFoundation|sharedStorage|show(OpenFile|SaveFile|Directory)Picker' "$ZERO_RETENTION"; then
	fail 'legacy purge helper can create non-Web-Storage persistence'
fi
! grep -Eq '\.(setItem|getItem|clear|key)\(' "$ZERO_RETENTION" ||
	fail 'legacy purge helper reads, creates, enumerates or clears browser storage'
grep -Fq "worker-src 'none'" "$INDEX" || fail 'Smart AP CSP does not disable workers'
if find "$ROOT/files/www" -type f \( \
	-iname 'sw.js' -o -iname '*serviceworker*' -o \
	-iname '*service-worker*' -o -iname '*service_worker*' \) \
	-print -quit | grep -q .; then
	fail 'a service-worker script is shipped'
fi

# There is no boot collector and upgrades remove historical links/copies.
[ ! -e "$ROOT/files/usr/sbin/cr6608-dashboard-prewarm" ] ||
	fail 'boot prewarm worker is still shipped'
[ ! -e "$ROOT/files/etc/init.d/cr6608-dashboard-cache" ] ||
	fail 'boot prewarm service is still shipped'
grep -Fq 'for service in cr6608-ipv4-only smartap-qos cr6608-quicksettings cr6608-management-guard; do' "$DEFAULTS" ||
	fail 'runtime services are not on the explicit no-prewarm allowlist'
! grep -Eq '(enable|start).*(cr6608-dashboard-cache|cr6608-dashboard-prewarm)|cr6608-dashboard-(cache|prewarm).*(enable|start)' "$DEFAULTS" ||
	fail 'UCI defaults still activate dashboard prewarm'
for legacy_link in \
	'/etc/rc.d/S99cr6608-dashboard-cache' \
	'/etc/rc.d/K99cr6608-dashboard-cache' \
	'/etc/init.d/cr6608-dashboard-cache' \
	'/usr/sbin/cr6608-dashboard-prewarm'; do
	grep -Fq "$legacy_link" "$DEFAULTS" ||
		fail "UCI defaults do not remove legacy artifact $legacy_link"
done

# All callers use one live collector. Internal/prewarm compatibility is a purge
# no-op, and a legacy request without live=1 cannot select a cache-read branch.
grep -Fq 'live_only=1' "$API" || fail 'API does not force live collection'
grep -Fq 'if [ "$internal_refresh" = 1 ]; then' "$API" ||
	fail 'internal compatibility mode is not explicit'
grep -Fq 'dashapi_telemetry_purge' "$API" || fail 'API lacks legacy telemetry purge'
grep -Fq '"snapshot_live":true,"snapshot_stored":false' "$API" ||
	fail 'responses do not declare live/non-stored semantics'
for forbidden_symbol in \
	'cache_load_view' \
	'dashapi_start_detached_refresh' \
	'cr6608_dashboard_cache_snapshot' \
	'cr6608_dashboard_cache_inspect' \
	'cr6608_dashboard_cache_publish' \
	'response_cache=' \
	'perf_cache=' \
	'cpu_prev=' \
	'traffic_prev=' \
	'survey_prev=' \
	'dashapi_topology_cache_store' \
	'dashapi_topology_cache_load'; do
	! grep -Fq "$forbidden_symbol" "$API" ||
		fail "API retains forbidden path $forbidden_symbol"
done

# Retained telemetry names may occur only in the explicit purge implementation;
# no function in the state library can publish or snapshot response telemetry.
grep -Fq 'cr6608_dashboard_telemetry_purge()' "$STATE" ||
	fail 'state library lacks global legacy purge'
grep -Fq 'cr6608_dashboard_request_telemetry_purge()' "$STATE" ||
	fail 'state library lacks request-private telemetry purge'
grep -Fq 'cr6608_dashboard_request_telemetry_recover() (' "$STATE" ||
	fail 'post-crash recovery does not isolate its FD9 in a subshell'
grep -Fq 'flock -xn 9' "$STATE" ||
	fail 'request-private purge is not serialized by collector.lock'
collector_acquire_block="$(sed -n '/^cr6608_dashboard_cache_collector_acquire() {$/,/^}$/p' "$STATE")"
printf '%s\n' "$collector_acquire_block" |
	grep -Fq 'cr6608_dashboard_request_telemetry_purge "$CR6608_DASHBOARD_CACHE_DIR"' ||
	fail 'collector handoff does not purge request-private residues under FD8'
handoff_flock_line="$(printf '%s\n' "$collector_acquire_block" | grep -nF 'flock -xn 8' | cut -d: -f1)"
handoff_purge_line="$(printf '%s\n' "$collector_acquire_block" | grep -nF 'cr6608_dashboard_request_telemetry_purge' | cut -d: -f1)"
handoff_guardian_line="$(printf '%s\n' "$collector_acquire_block" | grep -nF 'cr6608_dashboard_cache_collector_guardian_loop' | cut -d: -f1)"
handoff_parent_close_line="$(printf '%s\n' "$collector_acquire_block" | grep -nF 'exec 8>&-' | tail -n 1 | cut -d: -f1)"
handoff_owner_line="$(printf '%s\n' "$collector_acquire_block" | grep -nF 'CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER=1' | cut -d: -f1)"
[ -n "$handoff_flock_line" ] && [ -n "$handoff_purge_line" ] &&
	[ -n "$handoff_guardian_line" ] && [ -n "$handoff_parent_close_line" ] &&
	[ -n "$handoff_owner_line" ] &&
	[ "$handoff_flock_line" -lt "$handoff_purge_line" ] &&
	[ "$handoff_purge_line" -lt "$handoff_guardian_line" ] &&
	[ "$handoff_guardian_line" -lt "$handoff_parent_close_line" ] &&
	[ "$handoff_parent_close_line" -lt "$handoff_owner_line" ] ||
	fail 'collector handoff does not purge, spawn guardian, then close parent FD8'
printf '%s\n' "$collector_acquire_block" |
	grep -Fq 'exec 0</dev/null 1>/dev/null 2>&1' ||
	fail 'guardian stdio is not redirected to /dev/null'
printf '%s\n' "$collector_acquire_block" |
	grep -Fq 'exec 3>&- 4>&- 5>&- 6>&- 7>&- 9>&-' ||
	fail 'guardian does not close inherited coordination descriptors including FD9'
printf '%s\n' "$collector_acquire_block" |
	grep -Fq '.collector-control.$$.XXXXXX' ||
	fail 'guardian control is not request-unique'
guardian_loop_block="$(sed -n '/^cr6608_dashboard_cache_collector_guardian_loop() {$/,/^}$/p' "$STATE")"
printf '%s\n' "$guardian_loop_block" |
	grep -Fq '[ -n "$_cache_guard_parent_identity" ] || break' ||
	fail 'guardian does not fail closed when parent identity is unreadable'
printf '%s\n' "$guardian_loop_block" |
	grep -Fq '[ "$_cache_guard_parent_state" != Z ] || break' ||
	fail 'guardian does not release for a zombie parent'
printf '%s\n' "$guardian_loop_block" |
	grep -Fq '[ "$_cache_guard_seen_start" = "$_cache_guard_parent_start" ] || break' ||
	fail 'guardian does not bind parent PID to starttime'
printf '%s\n' "$guardian_loop_block" |
	grep -Fq '( exec 8>&-; sleep 1 )' ||
	fail 'guardian sleep subprocess can inherit FD8'
! printf '%s\n' "$guardian_loop_block" |
	grep -Fq '( exec 8>&-; cr6608_dashboard_cache_process_identity' ||
	fail 'guardian identity command substitution retains an outer FD8 carrier'
guardian_release_block="$(sed -n '/^cr6608_dashboard_cache_collector_release() {$/,/^}$/p' "$STATE")"
printf '%s\n' "$guardian_release_block" |
	grep -Fq 'cr6608_dashboard_cache_collector_guardian_stop' ||
	fail 'collector release does not stop the guardian'
! printf '%s\n' "$guardian_release_block" | grep -Fq 'flock -u 8' ||
	fail 'collector parent still claims direct FD8 ownership on release'
guardian_stop_block="$(sed -n '/^cr6608_dashboard_cache_collector_guardian_stop() {$/,/^}$/p' "$STATE")"
for guardian_stop_marker in "printf 'release\\n'" 'kill -TERM' 'kill -KILL' 'wait "$_cache_stop_pid"'; do
	printf '%s\n' "$guardian_stop_block" | grep -Fq "$guardian_stop_marker" ||
		fail "guardian stop lacks bounded cleanup marker $guardian_stop_marker"
done
grep -Fq 'cr6608_dashboard_request_telemetry_purge "$cache_dir" "$$"' "$API" ||
	fail 'normal request cleanup is not PID-scoped'
for request_residue_pattern in \
	'.dashcmd-out.*.*' '.dashcmd-err.*.*' '.linklog.*.*' \
	'.devices.*' '.arp.*' '.fdb.*' '.lease.*' '.degraded.*' \
	'.view.*.*' '.emit.*.*' '.publish.*.*' '.publish-final.*.*' \
	'.perf.*.*' '.collect.*.*'; do
	grep -Fq "$request_residue_pattern" "$STATE" ||
		fail "state library does not purge $request_residue_pattern"
done
for forbidden_symbol in \
	'cr6608_dashboard_cache_snapshot()' \
	'cr6608_dashboard_cache_inspect()' \
	'cr6608_dashboard_cache_publish()' \
	'CR6608_DASHBOARD_JSONFILTER_BIN'; do
	! grep -Fq "$forbidden_symbol" "$STATE" ||
		fail "state library retains forbidden path $forbidden_symbol"
done

# Reject all shared baseline reads/writes. Exact telemetry leaf names still
# appear in rm/find purge commands, which is intentional for upgrade cleanup.
if grep -Eq '(^|[;&|[:space:]])(cat|read|sed|cp|mv)[[:space:]].*\$cache_dir/(response[.]json|perf|lite[.]cpu|cpu|traffic|traffic[.]topology|iface[.]|sta[.]|survey[.])' "$API"; then
	fail 'API reads or publishes a shared telemetry leaf'
fi
if grep -Eq '>[[:space:]]*"?\$cache_dir/(response[.]json|perf|lite[.]cpu|cpu|traffic|traffic[.]topology|iface[.]|sta[.]|survey[.])' "$API"; then
	fail 'API writes a shared telemetry leaf'
fi

for build in "$BUILD" "$REMOTE_BUILD"; do
	grep -Fq 'DASHBOARD_ZERO_RETENTION_TEST=' "$build" ||
		fail "$(basename "$build") omits zero-retention gate"
	! grep -Fq 'DASHBOARD_PREWARM_TEST=' "$build" ||
		fail "$(basename "$build") still defines the prewarm gate"
	! grep -Fq 'usr/sbin/cr6608-dashboard-prewarm' "$build" ||
		fail "$(basename "$build") still requires the prewarm worker"
	! grep -Fq 'etc/init.d/cr6608-dashboard-cache' "$build" ||
		fail "$(basename "$build") still requires the prewarm service"
done
cmp -s "$BUILD" "$REMOTE_BUILD" || fail 'local and remote build scripts diverged'

printf 'dashboard_zero_retention_contract=pass\n'
