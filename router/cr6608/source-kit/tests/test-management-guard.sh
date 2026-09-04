#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORKER="$ROOT/files/usr/sbin/cr6608-management-guard"
INIT="$ROOT/files/etc/init.d/cr6608-management-guard"
DEFAULTS="$ROOT/files/etc/uci-defaults/99-cr6608-runtime-services"
PRIVATE_STAT_BIN=stat
case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW*|MSYS*|CYGWIN*) PRIVATE_STAT_BIN="$ROOT/tests/helpers/cr6608-private-stat-msys" ;;
esac

fail() {
	printf 'management_guard=fail: %s\n' "$*" >&2
	exit 1
}

for marker in \
	'URL="${CR6608_MGMT_URL:-http://127.0.0.1/}"' \
	'FAILURE_THRESHOLD=3' \
	'COOLDOWN="${CR6608_MGMT_COOLDOWN:-300}"' \
	'marker_exists "$PENDING_ROLLBACK"' \
	'marker_exists "$ROLLBACK_ARMED"' \
	"-f 'cr6608-quicksettings-apply'" \
	"-f 'cr6608-safe-apply'" \
	'"$UHTTPD_INIT" restart'; do
	grep -Fq -- "$marker" "$WORKER" || fail "missing worker contract: $marker"
done
for forbidden in '/etc/init.d/network' '/sbin/wifi' ' wifi ' 'reboot'; do
	! grep -Fq -- "$forbidden" "$WORKER" || fail "management guard contains forbidden recovery action: $forbidden"
done
grep -Fq 'USE_PROCD=1' "$INIT" || fail 'init script is not procd-managed'
grep -Fq 'procd_set_param command /usr/sbin/cr6608-management-guard' "$INIT" || fail 'wrong procd worker'
grep -Fq 'procd_set_param respawn 3600 5 5' "$INIT" || fail 'procd respawn is not bounded'
grep -Fq 'cr6608-management-guard' "$DEFAULTS" || fail 'runtime service is not enabled on install'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/state" "$TMP/bin"
chmod 0700 "$TMP/state"
printf '1000.00 0.00\n' >"$TMP/uptime"
printf 'fail\n' >"$TMP/probe-mode"
: >"$TMP/service.log"

cat >"$TMP/bin/http-probe" <<'EOF'
#!/bin/sh
[ "$(cat "$CR6608_TEST_PROBE_MODE")" = pass ]
EOF
cat >"$TMP/bin/uhttpd" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CR6608_TEST_SERVICE_LOG"
case "$1" in enabled|restart) exit 0 ;; *) exit 1 ;; esac
EOF
cat >"$TMP/bin/pgrep" <<'EOF'
#!/bin/sh
[ -e "$CR6608_TEST_PROCESS_BUSY" ]
EOF
cat >"$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$TMP/bin/http-probe" "$TMP/bin/uhttpd" "$TMP/bin/pgrep" "$TMP/bin/logger"

run_guard() {
	CR6608_MGMT_ONESHOT=1 \
	CR6608_MGMT_HTTP_BIN="$TMP/bin/http-probe" \
	CR6608_MGMT_UHTTPD_INIT="$TMP/bin/uhttpd" \
	CR6608_MGMT_PGREP_BIN="$TMP/bin/pgrep" \
	CR6608_MGMT_LOGGER_BIN="$TMP/bin/logger" \
	CR6608_MGMT_UPTIME_FILE="$TMP/uptime" \
	CR6608_MGMT_STATE_DIR="$TMP/state" \
	CR6608_PRIVATE_RUNTIME_LIB="$ROOT/files/usr/libexec/cr6608-private-runtime" \
	CR6608_PRIVATE_EXPECTED_UID="$(id -u)" \
	CR6608_PRIVATE_STAT_BIN="$PRIVATE_STAT_BIN" \
	CR6608_APPLY_LOCK="$TMP/apply.lock" \
	CR6608_MGMT_PENDING_ROLLBACK="$TMP/pending" \
	CR6608_MGMT_ROLLBACK_ARMED="$TMP/armed" \
	CR6608_MGMT_BOOT_GRACE=0 \
	CR6608_MGMT_COOLDOWN=300 \
	CR6608_TEST_PROBE_MODE="$TMP/probe-mode" \
	CR6608_TEST_SERVICE_LOG="$TMP/service.log" \
	CR6608_TEST_PROCESS_BUSY="$TMP/process-busy" \
	/bin/sh "$WORKER"
}

restart_count() {
	grep -xc 'restart' "$TMP/service.log" 2>/dev/null || true
}

# Fewer than three consecutive failures cannot heal anything.
run_guard
run_guard
[ "$(restart_count)" -eq 0 ] || fail 'uhttpd restarted before the third failure'
[ "$(cat "$TMP/state/failures")" -eq 2 ] || fail 'failure streak was not retained'

# A pending rollback resets the streak and blocks recovery.
: >"$TMP/pending"
run_guard
rm -f "$TMP/pending"
[ "$(cat "$TMP/state/failures")" -eq 0 ] || fail 'pending rollback did not reset the failure streak'

# Exactly three failures trigger one uhttpd-only restart.
run_guard
run_guard
run_guard
[ "$(restart_count)" -eq 1 ] || fail 'three failures did not trigger exactly one restart'
[ "$(cat "$TMP/state/last_restart")" -eq 1000 ] || fail 'restart time was not persisted'
[ ! -e "$TMP/apply.lock" ] || fail 'shared apply lock leaked after recovery'

# Further failures inside the cooldown cannot flap uhttpd.
printf '1100.00 0.00\n' >"$TMP/uptime"
run_guard
run_guard
run_guard
[ "$(restart_count)" -eq 1 ] || fail 'cooldown allowed a repeated restart'

# Both the mutation lock and live apply-process guard suppress healing.
printf '1400.00 0.00\n' >"$TMP/uptime"
mkdir "$TMP/apply.lock"
run_guard
rmdir "$TMP/apply.lock"
: >"$TMP/process-busy"
run_guard
rm -f "$TMP/process-busy"
[ "$(cat "$TMP/state/failures")" -eq 0 ] || fail 'maintenance activity did not reset the failure streak'
[ "$(restart_count)" -eq 1 ] || fail 'maintenance activity restarted uhttpd'

# After cooldown, three new failures permit one new targeted restart.
run_guard
run_guard
run_guard
[ "$(restart_count)" -eq 2 ] || fail 'post-cooldown recovery did not restart uhttpd once'

# A successful health check clears consecutive failure state.
printf 'pass\n' >"$TMP/probe-mode"
run_guard
[ "$(cat "$TMP/state/failures")" -eq 0 ] || fail 'healthy HTTP did not clear the failure streak'
[ "$(restart_count)" -eq 2 ] || fail 'healthy HTTP caused a restart'

# No recovery command other than `uhttpd restart` was ever issued.
awk '$0 != "enabled" && $0 != "restart" { exit 1 }' "$TMP/service.log" || fail 'unexpected init action was invoked'

printf 'management_guard=pass\n'
