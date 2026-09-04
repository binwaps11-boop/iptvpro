#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CTL="$ROOT/files/www/cgi-bin/dashctl"
JS="$ROOT/files/www/dashboard.js"
CACHE_LIB="$ROOT/files/usr/libexec/cr6608-dashboard-cache-state"

fail() {
	printf 'control_recovery_contract=fail: %s\n' "$*" >&2
	exit 1
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-control-recovery.XXXXXX")" || exit 1
busy_pid=""
worker_pid=""
cleanup() {
	touch "$TMP/orphan-worker-release" 2>/dev/null || true
	[ -z "$worker_pid" ] || kill "$worker_pid" 2>/dev/null || true
	[ -z "$worker_pid" ] || wait "$worker_pid" 2>/dev/null || true
	[ -z "$busy_pid" ] || kill "$busy_pid" 2>/dev/null || true
	[ -z "$busy_pid" ] || wait "$busy_pid" 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

sh -n "$CTL" || fail "dashctl syntax"
grep -Fq '[ "$section" = apply_status ]' "$CTL" || fail "authenticated recovery endpoint missing"
grep -Fq 'run_limit 3 "$safe_apply_status_cmd" status' "$CTL" || fail "Safe Apply status is not bounded"
grep -Fq 'valid_rollback_token "$safe_token" || safe_token=""' "$CTL" || fail "recovered token is not validated"
grep -Fq '[ "$safe_status" = armed ] || safe_token=""' "$CTL" || fail "non-armed state can expose a stale token"
grep -Fq 'safe_status="invalid"' "$CTL" || fail "missing Safe Apply helper can be reported clean"
grep -Fq '[ "$safe_ready_token" = "$safe_token" ] && safe_ready=true' "$CTL" || fail "completed-success marker is not bound to the armed token"
grep -Fq '"busy":%s,"pending":%s' "$CTL" || fail "recovery state omits busy/pending"
grep -Fq '"rollback_token":%s' "$CTL" || fail "recovery response omits the matching token"
grep -Fq '"confirmation_ready":%s' "$CTL" || fail "recovery response omits confirmation readiness"

grep -Fq 'var WIFI_CONTROL_TIMEOUT_MS = 740000;' "$JS" || fail "browser still expires before uhttpd"
grep -Fq 'var WIFI_RECOVERY_WINDOW_MS = 1740000;' "$JS" || fail "recovery does not cover the backend Wi-Fi worker guard"
grep -Fq 'controlActionTimeoutMs(section, actionName)' "$JS" || fail "control timeout is not action-aware"
grep -Fq 'dashboardActionTimeoutMs(name)' "$JS" || fail "dashboard action timeout is not action-aware"
grep -Fq 'controlRecoveryWindowMs(section, actionName)' "$JS" || fail "control recovery deadline is not action-aware"
grep -Fq 'dashboardRecoveryWindowMs(name)' "$JS" || fail "radio recovery deadline is not action-aware"
grep -Fq 'CTL + "?section=apply_status"' "$JS" || fail "browser cannot probe recovery status"
grep -Fq 'state.controlTokens[section] = token' "$JS" || fail "recovered rollback token is not retained"
grep -Fq 'presentPendingApply(section, box, status)' "$JS" || fail "recovered transaction is not shown to the user"
grep -Fq 'waitForRouterReachable(name, button)' "$JS" || fail "radio/WAN reconnect UX missing"
grep -Fq 'recoveryPollDelayMs(attempt++)' "$JS" || fail "long recovery polling has no bounded backoff"
grep -Fq 'cr6608_dashboard_cache_mutation_active' "$CTL" || fail "orphan Wi-Fi worker state is ignored"
grep -Fq '"Configuration worker busy"' "$CTL" || fail "Keep changes can confirm while a worker is active"
[ -r "$CACHE_LIB" ] || fail "dashboard cache state helper missing"

if [ -x /usr/bin/setsid ] && [ -w /var/run ] && command -v flock >/dev/null 2>&1; then
cat >"$TMP/session-auth" <<'EOF'
cr6608_session_from_request() { printf '%s\n' test-session; }
cr6608_session_valid() { [ "$1" = test-session ]; }
cr6608_ubus() { printf '%s\n' '{}'; }
EOF
cat >"$TMP/cache-state-inactive" <<'EOF'
cr6608_dashboard_cache_mutation_active() { return 1; }
EOF
cat >"$TMP/safe-apply" <<'EOF'
#!/bin/sh
case "${1:-}" in
	status)
		printf '%s\n' \
			"state=${CR6608_TEST_SAFE_STATE:-armed}" \
			'token=0123456789abcdef0123456789abcdef' \
			'backup=/root/dashboard-backups/private-do-not-expose.tar.gz' \
			"remaining=${CR6608_TEST_SAFE_REMAINING:-119}"
		;;
	ready)
		[ "${CR6608_TEST_SAFE_REMAINING:-119}" -gt 0 ] 2>/dev/null || exit 3
		printf '%s\n' "$2" >"$CR6608_SAFE_READY"
		chmod 0600 "$CR6608_SAFE_READY"
		;;
	*) exit 2 ;;
esac
EOF
chmod 0700 "$TMP/safe-apply"

run_status() {
	REQUEST_METHOD=GET QUERY_STRING='section=apply_status' CONTENT_LENGTH=0 \
	CR6608_SESSION_AUTH_LIB="$TMP/session-auth" \
	CR6608_DASHBOARD_CACHE_STATE_LIB="$TMP/cache-state-inactive" \
	CR6608_SAFE_APPLY_STATUS_CMD="$TMP/safe-apply" \
	CR6608_SAFE_APPLY_CMD="$TMP/safe-apply" \
	CR6608_SAFE_READY="$TMP/safe-ready" \
	CR6608_APPLY_LOCK="$TMP/apply.lock" \
	sh "$CTL"
}

unready_response="$(run_status)"
printf '%s\n' "$unready_response" | grep -Fq '"busy":false,"pending":true' ||
	fail "armed transaction without a marker was not kept pending"
printf '%s\n' "$unready_response" | grep -Fq '"confirmation_ready":false' ||
	fail "armed transaction without a marker was confirmable"
printf '%s\n' "$unready_response" | grep -Fq '"rollback_token":""' ||
	fail "armed transaction without a marker exposed its token"
printf '%s\n' "$unready_response" | grep -Fq '"actions":[]' ||
	fail "armed transaction without a marker exposed Keep"

printf '%s\n' 0123456789abcdef0123456789abcdef >"$TMP/safe-ready"
chmod 0600 "$TMP/safe-ready"
clean_response="$(run_status)"
printf '%s\n' "$clean_response" | grep -Fq '"busy":false,"pending":true' ||
	fail "runtime recovery did not return a completed pending transaction"
printf '%s\n' "$clean_response" | grep -Fq '"confirmation_ready":true' ||
	fail "matching completed-success marker did not enable confirmation"
printf '%s\n' "$clean_response" | grep -Fq '"remaining_s":119' ||
	fail "runtime recovery lost the remaining safety window"
printf '%s\n' "$clean_response" | grep -Fq '"rollback_token":"0123456789abcdef0123456789abcdef"' ||
	fail "runtime recovery lost the validated rollback token"
! printf '%s\n' "$clean_response" | grep -Fq 'private-do-not-expose' ||
	fail "runtime recovery exposed the private backup path"

printf '%s\n' ffffffffffffffffffffffffffffffff >"$TMP/safe-ready"
mismatched_response="$(run_status)"
printf '%s\n' "$mismatched_response" | grep -Fq '"confirmation_ready":false' ||
	fail "mismatched success marker enabled confirmation"
rm -f "$TMP/safe-ready"
ln -s "$TMP/safe-apply" "$TMP/safe-ready"
symlink_marker_response="$(run_status)"
printf '%s\n' "$symlink_marker_response" | grep -Fq '"confirmation_ready":false' ||
	fail "symlink success marker enabled confirmation"
rm -f "$TMP/safe-ready"
printf '%s\n' 0123456789abcdef0123456789abcdef >"$TMP/safe-ready"
expired_response="$(CR6608_TEST_SAFE_REMAINING=0 run_status)"
printf '%s\n' "$expired_response" | grep -Fq '"confirmation_ready":false' ||
	fail "expired armed transaction enabled confirmation"
printf '%s\n' "$expired_response" | grep -Fq '"rollback_token":""' ||
	fail "expired armed transaction exposed its token"

invalid_response="$(CR6608_TEST_SAFE_STATE=invalid run_status)"
printf '%s\n' "$invalid_response" | grep -Fq '"busy":false,"pending":false' ||
	fail "invalid Safe Apply state was presented as a pending transaction"
printf '%s\n' "$invalid_response" | grep -Fq '"rollback_token":""' ||
	fail "invalid Safe Apply state exposed a stale rollback token"

missing_helper_response="$(REQUEST_METHOD=GET QUERY_STRING='section=apply_status' CONTENT_LENGTH=0 \
	CR6608_SESSION_AUTH_LIB="$TMP/session-auth" \
	CR6608_DASHBOARD_CACHE_STATE_LIB="$TMP/cache-state-inactive" \
	CR6608_SAFE_APPLY_STATUS_CMD="$TMP/missing-safe-apply" \
	CR6608_SAFE_READY="$TMP/safe-ready" \
	CR6608_APPLY_LOCK="$TMP/missing-helper.lock" \
	sh "$CTL")"
printf '%s\n' "$missing_helper_response" | grep -Fq '"safe_state":"invalid"' ||
	fail "missing Safe Apply helper was reported clean"
printf '%s\n' "$missing_helper_response" | grep -Fq '"confirmation_ready":false' ||
	fail "missing Safe Apply helper enabled confirmation"

ln -s "$TMP/safe-apply" "$TMP/safe-apply-link"
symlink_helper_response="$(REQUEST_METHOD=GET QUERY_STRING='section=apply_status' CONTENT_LENGTH=0 \
	CR6608_SESSION_AUTH_LIB="$TMP/session-auth" \
	CR6608_DASHBOARD_CACHE_STATE_LIB="$TMP/cache-state-inactive" \
	CR6608_SAFE_APPLY_STATUS_CMD="$TMP/safe-apply-link" \
	CR6608_SAFE_READY="$TMP/safe-ready" \
	CR6608_APPLY_LOCK="$TMP/symlink-helper.lock" \
	sh "$CTL")"
printf '%s\n' "$symlink_helper_response" | grep -Fq '"safe_state":"invalid"' ||
	fail "symlink Safe Apply helper was trusted"

missing_guard_response="$(REQUEST_METHOD=GET QUERY_STRING='section=apply_status' CONTENT_LENGTH=0 \
	CR6608_SESSION_AUTH_LIB="$TMP/session-auth" \
	CR6608_DASHBOARD_CACHE_STATE_LIB="$TMP/missing-cache-lib" \
	CR6608_SAFE_APPLY_STATUS_CMD="$TMP/safe-apply" \
	CR6608_SAFE_APPLY_CMD="$TMP/safe-apply" \
	CR6608_SAFE_READY="$TMP/safe-ready" \
	CR6608_APPLY_LOCK="$TMP/missing-guard-apply.lock" \
	sh "$CTL")"
printf '%s\n' "$missing_guard_response" | grep -Fq '"busy":true,"pending":true' ||
	fail "missing mutation guard was not treated fail-closed"
printf '%s\n' "$missing_guard_response" | grep -Fq '"rollback_token":""' ||
	fail "missing mutation guard exposed a confirmation token"

mkdir "$TMP/apply.lock"
sleep 30 & busy_pid=$!
busy_start="$(awk '{print $22}' "/proc/$busy_pid/stat")"
printf '%s %s\n' "$busy_pid" "$busy_start" >"$TMP/apply.lock/owner"
busy_response="$(run_status)"
printf '%s\n' "$busy_response" | grep -Fq '"busy":true,"pending":true' ||
	fail "runtime recovery did not distinguish an active apply"
kill "$busy_pid" 2>/dev/null || true
wait "$busy_pid" 2>/dev/null || true
busy_pid=""

# Model the uhttpd-timeout case: the parent apply.lock owner is gone, but the
# detached Safe Wi-Fi worker still owns the transferred mutation flock and the
# Safe Apply token is armed. Status must stay busy and Keep must not confirm.
cache_uid="$(id -u)"
orphan_cache="$TMP/orphan-cache"
(
	CR6608_DASHBOARD_CACHE_DIR="$orphan_cache"
	CR6608_DASHBOARD_CACHE_EXPECT_UID="$cache_uid"
	export CR6608_DASHBOARD_CACHE_DIR CR6608_DASHBOARD_CACHE_EXPECT_UID
	# shellcheck disable=SC1090
	. "$CACHE_LIB"
	cr6608_dashboard_cache_mutation_begin || exit 31
	: >"$TMP/orphan-worker-ready"
	while [ ! -e "$TMP/orphan-worker-release" ]; do sleep 0.1; done
	cr6608_dashboard_cache_mutation_finish
) &
worker_pid=$!
orphan_wait=0
while [ ! -e "$TMP/orphan-worker-ready" ] && [ "$orphan_wait" -lt 100 ]; do
	sleep 0.1
	orphan_wait=$((orphan_wait + 1))
done
[ -e "$TMP/orphan-worker-ready" ] || fail "orphan worker fixture did not acquire mutation.lock"
mkdir "$TMP/orphan-apply.lock"
printf '%s %s\n' 999999 1 >"$TMP/orphan-apply.lock/owner"

run_orphan_status() {
	REQUEST_METHOD=GET QUERY_STRING='section=apply_status' CONTENT_LENGTH=0 \
	CR6608_SESSION_AUTH_LIB="$TMP/session-auth" \
	CR6608_DASHBOARD_CACHE_STATE_LIB="$CACHE_LIB" \
	CR6608_DASHBOARD_CACHE_DIR="$orphan_cache" \
	CR6608_DASHBOARD_CACHE_EXPECT_UID="$cache_uid" \
	CR6608_SAFE_APPLY_STATUS_CMD="$TMP/safe-apply" \
	CR6608_SAFE_APPLY_CMD="$TMP/safe-apply" \
	CR6608_SAFE_READY="$TMP/safe-ready" \
	CR6608_APPLY_LOCK="$TMP/orphan-apply.lock" \
	sh "$CTL"
}

orphan_response="$(run_orphan_status)"
printf '%s\n' "$orphan_response" | grep -Fq '"busy":true,"pending":true' ||
	fail "orphan worker with a dead apply.lock owner was reported ready"
printf '%s\n' "$orphan_response" | grep -Fq '"actions":[]' ||
	fail "orphan worker status offered confirmation actions prematurely"
printf '%s\n' "$orphan_response" | grep -Fq '"rollback_token":""' ||
	fail "orphan worker status exposed an actionable token prematurely"

keep_body='section=wizard&action=keep_changes&rollback_token=0123456789abcdef0123456789abcdef'
keep_response="$(printf '%s' "$keep_body" | env \
	REQUEST_METHOD=POST QUERY_STRING='' CONTENT_LENGTH="${#keep_body}" \
	CR6608_SESSION_AUTH_LIB="$TMP/session-auth" \
	CR6608_DASHBOARD_CACHE_STATE_LIB="$CACHE_LIB" \
	CR6608_DASHBOARD_CACHE_DIR="$orphan_cache" \
	CR6608_DASHBOARD_CACHE_EXPECT_UID="$cache_uid" \
	CR6608_SAFE_APPLY_CMD="$TMP/safe-apply" \
	CR6608_SAFE_READY="$TMP/safe-ready" \
	CR6608_APPLY_LOCK="$TMP/orphan-confirm.lock" \
	sh "$CTL")"
printf '%s\n' "$keep_response" | grep -Fq '"ok":false' ||
	fail "Keep changes succeeded while the orphan worker was active"
printf '%s\n' "$keep_response" | grep -Fq '"summary":"Configuration worker busy"' ||
	fail "Keep changes did not return an explicit worker-busy result"

: >"$TMP/orphan-worker-release"
wait "$worker_pid" || fail "orphan worker fixture did not finish cleanly"
worker_pid=""
settled_response="$(run_orphan_status)"
printf '%s\n' "$settled_response" | grep -Fq '"busy":false,"pending":true' ||
	fail "recovery stayed busy after the orphan worker released mutation.lock"
fi

printf 'control_recovery_contract=pass\n'
