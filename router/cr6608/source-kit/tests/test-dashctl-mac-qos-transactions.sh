#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASH="$ROOT/files/www/cgi-bin/dashctl"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-dashctl-qos.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() {
	printf 'dashctl_mac_qos_transactions=fail: %s\n' "$*" >&2
	exit 1
}

for marker in \
	'delete_block_rules_staged "$mac" || {' \
	'uci -q revert firewall' \
	'action_backup client-limit' \
	'action_backup clear-client-limits' \
	'action_arm_rollback "Speed limit"' \
	'action_arm_rollback "Speed limits"' \
	'action_confirm_verified "Speed limit"' \
	'action_confirm_verified "Speed limits"' \
	'qos_worker_marker_prepare "$rollback_token"' \
	'reconcile_orphaned_qos_worker_marker' \
	'qos_marker_reconcile_deferred=1' \
	'qos_worker_process_identity "$_qwm_pid" "$_qwm_start"' \
	'recover_interrupted_qos_transaction' \
	'CR6608_INHERIT_CACHE_LOCK=1 run_limit "${CR6608_QOS_RECOVERY_TIMEOUT:-180}"' \
	'if ! uci commit smartap >"$ACTION_LOG" 2>&1; then' \
	'if ! smartap_qos_apply_bounded; then' \
	'qos_policy_restore_from_backup'; do
	grep -Fq "$marker" "$DASH" || fail "missing transactional marker: $marker"
done
! grep -Fq 'uci -q delete smartap."$key" 2>/dev/null; uci -q commit smartap' "$DASH" ||
	fail "set_client_limit still destroys the previous section after apply failure"
reconcile_call_line="$(grep -nF '        reconcile_orphaned_qos_worker_marker' "$DASH" | sed -n '1s/:.*//p')"
pending_check_line="$(grep -nF '      if [ -e /etc/smartap-pending-rollback ]' "$DASH" | sed -n '1s/:.*//p')"
[ -n "$reconcile_call_line" ] && [ "$reconcile_call_line" -lt "$pending_check_line" ] ||
	fail "orphaned QoS marker reconciliation does not run before the pending-state check"

extract_function() {
	sed -n "/^$1()/,/^}/p" "$DASH" | tr -d '\r'
}

eval "$(extract_function canonical_unicast_mac)"
[ "$(canonical_unicast_mac 'AA:BC:DE:F0:12:34')" = 'aa:bc:de:f0:12:34' ] ||
	fail "exact uppercase unicast MAC was not normalized"
for hostile_mac in \
	'00:00:00:00:00:00' 'ff:ff:ff:ff:ff:ff' \
	'01:00:5e:00:00:01' '33:33:00:00:00:01' 'ab:00:00:00:00:02' \
	'aabbccddeeff' 'aa-bb-cc-dd-ee-ff' 'aa:bb:cc:dd:ee' \
	'aa:bb:cc:dd:ee:ff00' 'aa:bb:cc:dd:ee:fg' ' aa:bb:cc:dd:ee:fe'; do
	if canonical_unicast_mac "$hostile_mac" >/dev/null 2>&1; then
		fail "canonical validator accepted hostile MAC: $hostile_mac"
	fi
done

extract_handler() {
	_start="$1"; _end="$2"; _name="$3"
	sed -n "/^  ${_start})/,/^  ${_end})/p" "$DASH" | awk -v end="  ${_end})" -v name="$_name" '
		{ sub(/\r$/, "") }
		NR == 1 { print name "() {"; next }
		$0 == end { print "}"; exit }
		{ sub(/[[:space:]]*;;[[:space:]]*$/, ""); print }
	'
}

line_of() {
	grep -nF "$2" "$1" | sed -n '1s/:.*//p'
}

assert_contract_order() {
	_contract="$1"; _title="$2"; _success="$3"
	_arm="$(line_of "$_contract" "action_arm_rollback \"$_title\"")"
	_commit="$(line_of "$_contract" 'uci commit smartap')"
	_apply="$(line_of "$_contract" 'smartap_qos_apply_bounded')"
	_confirm="$(line_of "$_contract" "action_confirm_verified \"$_title\"")"
	_success_line="$(line_of "$_contract" "$_success")"
	[ -n "$_arm" ] && [ "$_arm" -lt "$_commit" ] &&
		[ "$_commit" -lt "$_apply" ] && [ "$_apply" -lt "$_confirm" ] &&
		[ "$_confirm" -lt "$_success_line" ] ||
		fail "$_title is not ordered arm -> commit -> apply -> confirm -> success"
}

extract_handler set_client_limit clear_client_limits run_set_limit >"$TMP/set.contract"
extract_handler clear_client_limits save_wifi_timer run_clear_limits >"$TMP/clear.contract"
assert_contract_order "$TMP/set.contract" 'Speed limit' 'emit true "Speed limit"'
assert_contract_order "$TMP/clear.contract" 'Speed limits' 'emit true "Speed limits"'

mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/nft"
chmod 0755 "$TMP/bin/nft"

cat >"$TMP/bin/cr6608-safe-apply" <<'EOF_SAFE_APPLY'
#!/bin/sh
case "${1:-}" in
	status)
		if [ -f "$ARMED_FILE" ]; then
			_token="$(sed -n '1p' "$ARMED_FILE")"
			printf 'state=armed\ntoken=%s\nbackup=%s\n' "$_token" "${MOCK_RECOVERY_BACKUP:-/root/dashboard-backups/smartap-client-limit-20260823.tar.gz}"
		else
			printf 'state=clean\n'
		fi
		;;
	confirm)
		printf 'safe-confirm:%s\n' "${2:-}" >>"$LOG"
		[ "${MOCK_CONFIRM_FAIL:-0}" != 1 ] || exit 1
		[ -f "$ARMED_FILE" ] && [ "$(sed -n '1p' "$ARMED_FILE")" = "${2:-}" ] || exit 1
		rm -f "$ARMED_FILE"
		;;
	rollback)
		printf 'safe-rollback:%s\n' "${2:-}" >>"$LOG"
		[ -f "$ARMED_FILE" ] && [ "$(sed -n '1p' "$ARMED_FILE")" = "${2:-}" ] || exit 1
		printf 'old-policy\n' >"$QOS_CONFIG"
		printf 'qos-runtime-restored\n' >>"$LOG"
		rm -f "$ARMED_FILE"
		;;
	*) exit 2 ;;
esac
EOF_SAFE_APPLY
chmod 0755 "$TMP/bin/cr6608-safe-apply"

DRIVER="$TMP/driver.sh"
{
	cat <<'EOF_DRIVER'
#!/bin/sh
set -u
: "${TMP:?}"
LOG="$TMP/mock.log"
ACTION_LOG="$TMP/action.log"
QOS_CONFIG="$TMP/smartap"
APPLY_COUNT="$TMP/apply.count"
ARMED_FILE="$TMP/armed"
QOS_WORKER_MARKER="$TMP/qos-worker"
SAFE_APPLY="$TMP/bin/cr6608-safe-apply"
PATH="$TMP/bin:$PATH"
export PATH LOG ACTION_LOG QOS_CONFIG APPLY_COUNT ARMED_FILE QOS_WORKER_MARKER
MOCK_COMMIT_FAIL="${MOCK_COMMIT_FAIL:-0}"
MOCK_APPLY_FAIL_ONCE="${MOCK_APPLY_FAIL_ONCE:-0}"
MOCK_DELETE_FAIL="${MOCK_DELETE_FAIL:-0}"
MOCK_CLEAR_DELETE_FAIL="${MOCK_CLEAR_DELETE_FAIL:-0}"
MOCK_KILL_AFTER_COMMIT="${MOCK_KILL_AFTER_COMMIT:-0}"
MOCK_KILL_DURING_APPLY="${MOCK_KILL_DURING_APPLY:-0}"
MOCK_QUIESCE_FAIL="${MOCK_QUIESCE_FAIL:-0}"
MOCK_WORKER_LIVE="${MOCK_WORKER_LIVE:-0}"
MOCK_WORKER_IDENTITY="${MOCK_WORKER_IDENTITY:-1}"
MOCK_MARKER_SECURE="${MOCK_MARKER_SECURE:-1}"
backup="$TMP/backup.tar.gz"
smartap_existed=1
rollback_token=""

safe_num() { printf '%s' "$1" | sed 's/[^0-9]//g' | cut -c1-4; }
redact() { cat; }
royal_backup_valid() { return 0; }
valid_rollback_token() { case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac; [ "${#1}" -eq 32 ] 2>/dev/null; }
run_limit() { shift; "$@"; }
safe_apply_ready_clear() { printf 'ready-clear\n' >>"$LOG"; }
safe_apply_ready_read() { [ -n "${MOCK_READY_TOKEN:-}" ] && printf '%s\n' "$MOCK_READY_TOKEN"; }
param() {
	case "$1" in
		mac) printf '%s' 'aa:bc:de:f0:12:34' ;;
		limit_down) printf '%s' '25' ;;
		limit_up) printf '%s' '10' ;;
	esac
}
emit() { printf 'emit:%s:%s\n' "$2" "$3" >>"$LOG"; }
confirm_required() { printf 'confirm-required:%s\n' "$1" >>"$LOG"; }
action_backup() { backup="$TMP/backup.tar.gz"; smartap_existed=1; printf 'backup:%s\n' "$1" >>"$LOG"; }
action_arm_rollback() {
	rollback_token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
	printf '%s\n' "$rollback_token" >"$ARMED_FILE"
	printf 'arm:%s\n' "$1" >>"$LOG"
}
action_commit() { printf 'action-commit:%s\n' "$1" >>"$LOG"; }
action_reload() { printf 'reload:%s\n' "$1" >>"$LOG"; }
smartap_heal() { return 0; }
tar() { printf 'old-policy\n' >"$QOS_CONFIG"; return 0; }
qos_worker_marker_secure() {
	[ "$MOCK_MARKER_SECURE" = 1 ] && [ -f "$QOS_WORKER_MARKER" ] && [ ! -L "$QOS_WORKER_MARKER" ]
}
qos_worker_marker_clear() { printf 'marker-clear\n' >>"$LOG"; rm -f "$QOS_WORKER_MARKER"; }
run_limit_process_running() { [ "$MOCK_WORKER_LIVE" = 1 ]; }
qos_worker_process_identity() {
	printf 'process-identity:%s:%s\n' "$1" "$2" >>"$LOG"
	[ "$MOCK_WORKER_IDENTITY" = 1 ]
}
qos_worker_quiesce() {
	printf 'quiesce:%s\n' "$1" >>"$LOG"
	[ "$MOCK_QUIESCE_FAIL" != 1 ] || return 1
	if [ -f "$QOS_WORKER_MARKER" ]; then
		_qwm_mock_state=''; _qwm_mock_token=''
		read _qwm_mock_state _qwm_mock_token _qwm_mock_pid _qwm_mock_start <"$QOS_WORKER_MARKER" || return 1
		[ "$_qwm_mock_token" = "$1" ] || return 1
		rm -f "$QOS_WORKER_MARKER"
	fi
	return 0
}
run_limit_cancel_active() { printf 'cancel-active\n' >>"$LOG"; }
release_apply_lock() { printf 'release-lock\n' >>"$LOG"; }
dashctl_private_cleanup() { printf 'cleanup-private\n' >>"$LOG"; }
smartap_qos_apply_bounded() {
	_count="$(cat "$APPLY_COUNT" 2>/dev/null || printf 0)"
	_count=$((_count + 1))
	printf '%s\n' "$_count" >"$APPLY_COUNT"
	printf 'qos-apply:%s\n' "$_count" >>"$LOG"
	if valid_rollback_token "${rollback_token:-}"; then
		printf 'active %s 4242 777\n' "$rollback_token" >"$QOS_WORKER_MARKER"
	fi
	if [ "$MOCK_KILL_DURING_APPLY" = 1 ] && [ "$_count" = 1 ]; then
		/bin/kill -KILL "$$"
	fi
	rm -f "$QOS_WORKER_MARKER"
	if [ "$MOCK_APPLY_FAIL_ONCE" = 1 ] && [ "$_count" = 1 ]; then
		printf 'mock apply failure\n' >"$ACTION_LOG"
		return 1
	fi
	return 0
}
action_rollback_pending() {
	printf 'rollback-pending\n' >>"$LOG"
	_action_rollback_text='Automatic rollback remains armed.'
	if valid_rollback_token "${rollback_token:-}" && "$SAFE_APPLY" rollback "$rollback_token" >/dev/null 2>&1; then
		smartap_qos_apply_bounded >/dev/null 2>&1 || true
		rollback_token=""
		_action_rollback_text='Previous settings were restored.'
	fi
}
uci() {
	[ "${1:-}" != -q ] || shift
	_cmd="${1:-}"; shift || true
	_arg="${1:-}"
	case "$_cmd" in
		show)
			case "$_arg" in
				firewall)
					printf "%s\n" \
						"firewall.@rule[0]=rule" \
						"firewall.@rule[0].name='CR6608-Block-aa:bc:de:f0:12:34'"
					;;
				smartap) printf '%s\n' 'smartap.qos_old=qos' ;;
			esac
			;;
		delete)
			printf 'uci-delete:%s\n' "$_arg" >>"$LOG"
			case "$_arg" in
				firewall.*) [ "$MOCK_DELETE_FAIL" != 1 ] ;;
				smartap.*) [ "$MOCK_CLEAR_DELETE_FAIL" != 1 ] ;;
				*) return 0 ;;
			esac
			;;
		revert) printf 'uci-revert:%s\n' "$_arg" >>"$LOG"; return 0 ;;
		commit)
			printf 'uci-commit:%s\n' "$_arg" >>"$LOG"
			if [ "$MOCK_COMMIT_FAIL" = 1 ]; then printf 'mock commit failure\n' >"$ACTION_LOG"; return 1; fi
			if [ "$MOCK_KILL_AFTER_COMMIT" = 1 ]; then /bin/kill -KILL "$$"; fi
			return 0
			;;
		set) printf 'uci-set:%s\n' "$_arg" >>"$LOG"; return 0 ;;
		get) return 1 ;;
		add) printf '%s' 'cfgmock'; return 0 ;;
	esac
}
EOF_DRIVER
	extract_function canonical_unicast_mac
	extract_function action_confirm_verified |
		sed 's#/usr/sbin/cr6608-safe-apply#"$SAFE_APPLY"#g'
	extract_function reconcile_orphaned_qos_worker_marker |
		sed 's#/usr/sbin/cr6608-safe-apply#"$SAFE_APPLY"#g'
	extract_function recover_interrupted_qos_transaction |
		sed 's#/usr/sbin/cr6608-safe-apply#"$SAFE_APPLY"#g'
	extract_function apply_signal_exit
	extract_function qos_policy_restore_from_backup |
		sed 's#/etc/config/smartap#"$QOS_CONFIG"#g'
	extract_function delete_block_rules_staged
	cat "$TMP/set.contract"
	cat "$TMP/clear.contract"
	extract_handler unblock_mac set_client_limit run_unblock
	cat <<'EOF_DRIVER'
case "${1:-}" in
	unblock) run_unblock ;;
	set) run_set_limit ;;
	clear) run_clear_limits ;;
	reconcile) reconcile_orphaned_qos_worker_marker; exit $? ;;
	recover) recover_interrupted_qos_transaction; exit $? ;;
	signal)
		rollback_token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
		printf '%s\n' "$rollback_token" >"$ARMED_FILE"
		printf '%s\n' "$rollback_token" >"$QOS_WORKER_MARKER"
		apply_signal_exit 143
		;;
	*) exit 2 ;;
esac
EOF_DRIVER
} >"$DRIVER"
chmod 0700 "$DRIVER"

reset_case() {
	: >"$TMP/mock.log"
	: >"$TMP/action.log"
	rm -f "$TMP/apply.count" "$TMP/armed" "$TMP/qos-worker"
	printf 'new-policy\n' >"$TMP/smartap"
}

run_case() {
	_mode="$1"; shift
	reset_case
	env TMP="$TMP" "$@" sh "$DRIVER" "$_mode" >/dev/null 2>&1 ||
		fail "mock driver failed for $_mode ($*)"
}

assert_log_order() {
	_previous=0
	for _needle in "$@"; do
		_current="$(line_of "$TMP/mock.log" "$_needle")"
		[ -n "$_current" ] && [ "$_current" -gt "$_previous" ] ||
			fail "runtime order missing/out of order at: $_needle"
		_previous="$_current"
	done
}

run_case unblock MOCK_DELETE_FAIL=1
grep -Fq 'uci-delete:firewall.@rule[0]' "$TMP/mock.log" || fail "unblock delete failure was not exercised"
grep -Fq 'uci-revert:firewall' "$TMP/mock.log" || fail "unblock delete failure did not revert staged rules"
! grep -Fq 'arm:' "$TMP/mock.log" || fail "unblock armed/committed after a failed delete"
grep -Fq 'emit:Connected Devices:Unblock staging failed' "$TMP/mock.log" || fail "unblock delete failure was reported as success"

run_case set
assert_log_order 'arm:Speed limit' 'uci-commit:smartap' 'qos-apply:1' \
	'safe-confirm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'emit:Speed limit:Per-client policer active'
[ ! -e "$TMP/armed" ] || fail "set success left the persistent rollback armed"

run_case clear
assert_log_order 'arm:Speed limits' 'uci-commit:smartap' 'qos-apply:1' \
	'safe-confirm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'emit:Speed limits:Per-client policers cleared'
[ ! -e "$TMP/armed" ] || fail "clear success left the persistent rollback armed"

run_case set MOCK_COMMIT_FAIL=1
grep -Fq 'uci-commit:smartap' "$TMP/mock.log" || fail "set limit commit failure was not exercised"
grep -Fqx 'old-policy' "$TMP/smartap" || fail "set limit commit failure did not restore old config"
grep -Fq 'qos-apply:1' "$TMP/mock.log" || fail "set limit commit failure did not replay old runtime"
grep -Fq 'emit:Speed limit:QoS commit failed' "$TMP/mock.log" || fail "set limit commit failure was reported as success"
[ ! -e "$TMP/armed" ] || fail "set commit rollback left the guard armed"

run_case set MOCK_APPLY_FAIL_ONCE=1
[ "$(cat "$TMP/apply.count")" = 2 ] || fail "set limit apply failure did not replay old runtime"
grep -Fqx 'old-policy' "$TMP/smartap" || fail "set limit apply failure destroyed the old section"
grep -Fq 'emit:Speed limit:QoS apply failed' "$TMP/mock.log" || fail "set limit apply failure was reported as success"

run_case set MOCK_CONFIRM_FAIL=1
[ "$(cat "$TMP/apply.count")" = 2 ] || fail "set confirm failure did not replay old runtime"
grep -Fqx 'old-policy' "$TMP/smartap" || fail "set confirm failure did not restore old config"
grep -Fq 'emit:Speed limit:Safety confirmation failed' "$TMP/mock.log" || fail "set confirm failure was reported as success"
! grep -Fq 'emit:Speed limit:Per-client policer active' "$TMP/mock.log" || fail "set success escaped a failed confirmation"

run_case clear MOCK_CLEAR_DELETE_FAIL=1
grep -Fq 'uci-revert:smartap' "$TMP/mock.log" || fail "clear limit delete failure did not restore UCI"
grep -Fq 'emit:Speed limits:QoS cleanup staging failed' "$TMP/mock.log" || fail "clear delete failure was reported as success"

run_case clear MOCK_COMMIT_FAIL=1
grep -Fqx 'old-policy' "$TMP/smartap" || fail "clear limit commit failure did not restore old config"
grep -Fq 'qos-apply:1' "$TMP/mock.log" || fail "clear limit commit failure did not replay old runtime"
grep -Fq 'emit:Speed limits:QoS cleanup commit failed' "$TMP/mock.log" || fail "clear commit failure was reported as success"

run_case clear MOCK_APPLY_FAIL_ONCE=1
[ "$(cat "$TMP/apply.count")" = 2 ] || fail "clear limit apply failure did not replay old runtime"
grep -Fqx 'old-policy' "$TMP/smartap" || fail "clear limit apply failure did not restore old config"
grep -Fq 'emit:Speed limits:QoS cleanup apply failed' "$TMP/mock.log" || fail "clear apply failure was reported as success"

reset_case
set +e
env TMP="$TMP" sh "$DRIVER" signal >/dev/null 2>&1
signal_rc=$?
set -e
[ "$signal_rc" = 143 ] || fail "TERM cleanup returned $signal_rc instead of 143"
assert_log_order 'cancel-active' 'marker-clear' 'rollback-pending' 'release-lock' 'cleanup-private'
grep -Fqx 'old-policy' "$TMP/smartap" || fail "TERM cleanup did not restore the prior QoS policy"
[ ! -e "$TMP/armed" ] || fail "TERM cleanup left the persistent guard armed"

run_killed_case() {
	_mode="$1"; shift
	reset_case
	set +e
	env TMP="$TMP" "$@" sh "$DRIVER" "$_mode" >/dev/null 2>&1
	_killed_rc=$?
	set -e
	[ "$_killed_rc" = 137 ] || fail "$_mode interruption returned $_killed_rc instead of 137"
	[ -f "$TMP/armed" ] || fail "$_mode KILL lost the persistent rollback guard"
}

run_recovery() {
	_expected="$1"; shift
	set +e
	env TMP="$TMP" "$@" sh "$DRIVER" recover >/dev/null 2>&1
	_recovery_rc=$?
	set -e
	[ "$_recovery_rc" = "$_expected" ] || fail "next-start recovery returned $_recovery_rc instead of $_expected"
}

run_reconcile() {
	_expected="$1"; shift
	set +e
	env TMP="$TMP" "$@" sh "$DRIVER" reconcile >/dev/null 2>&1
	_reconcile_rc=$?
	set -e
	[ "$_reconcile_rc" = "$_expected" ] || fail "marker-only reconciliation returned $_reconcile_rc instead of $_expected"
}

# The independent Safe Apply watcher may finish rollback and remove its armed
# state after the CGI was killed, leaving only the guarded worker marker. A
# dead, exact marker is stale bookkeeping and must not poison all future QoS.
reset_case
printf 'active %s 4242 777\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$TMP/qos-worker"
run_reconcile 0
grep -Fq 'marker-clear' "$TMP/mock.log" || fail "watchdog-clean stale marker was not cleared"
[ ! -e "$TMP/qos-worker" ] || fail "watchdog-clean stale marker survived reconciliation"

# Cover the watcher transition itself: the first read defers while armed, then
# a completed watchdog rollback makes the second read clean and removable.
reset_case
printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$TMP/armed"
printf 'active %s 4242 777\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$TMP/qos-worker"
run_reconcile 2
[ -e "$TMP/qos-worker" ] || fail "armed transaction marker was cleared before rollback"
rm -f "$TMP/armed"
run_reconcile 0
[ ! -e "$TMP/qos-worker" ] || fail "armed-to-clean watcher transition left a stale marker"

# A still-running, positively identified QoS worker is stopped before the
# stale marker is released.
reset_case
printf 'active %s 4242 777\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$TMP/qos-worker"
run_reconcile 0 MOCK_WORKER_LIVE=1 MOCK_WORKER_IDENTITY=1
assert_log_order 'process-identity:4242:777' 'quiesce:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
[ ! -e "$TMP/qos-worker" ] || fail "quiesced orphan worker marker was not cleared"

# Never use a root-only marker as an arbitrary PID killer: incomplete records,
# insecure metadata, and live processes with the wrong command identity all
# remain fail-closed for maintenance inspection.
reset_case
printf 'pending %s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$TMP/qos-worker"
run_reconcile 1
[ -e "$TMP/qos-worker" ] || fail "malformed hostile marker was silently discarded"
! grep -Fq 'quiesce:' "$TMP/mock.log" || fail "malformed hostile marker reached process quiesce"

reset_case
printf 'active %s 4242 777\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$TMP/qos-worker"
run_reconcile 1 MOCK_MARKER_SECURE=0
[ -e "$TMP/qos-worker" ] || fail "insecure hostile marker was silently discarded"

reset_case
printf 'active %s 4242 777\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$TMP/qos-worker"
run_reconcile 1 MOCK_WORKER_LIVE=1 MOCK_WORKER_IDENTITY=0
grep -Fq 'process-identity:4242:777' "$TMP/mock.log" || fail "live hostile identity mismatch was not checked"
! grep -Fq 'quiesce:' "$TMP/mock.log" || fail "identity-mismatched process was signalled"
[ -e "$TMP/qos-worker" ] || fail "identity-mismatched marker was silently discarded"

run_killed_case set MOCK_KILL_AFTER_COMMIT=1
grep -Fq 'uci-commit:smartap' "$TMP/mock.log" || fail "post-commit KILL was not exercised"
! grep -Fq 'qos-apply:' "$TMP/mock.log" || fail "post-commit KILL reached QoS apply"
! grep -Fq 'safe-confirm:' "$TMP/mock.log" || fail "post-commit KILL confirmed an unverified transaction"
run_recovery 0
assert_log_order 'quiesce:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'safe-rollback:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
grep -Fqx 'old-policy' "$TMP/smartap" || fail "next start did not restore post-commit KILL"
[ ! -e "$TMP/armed" ] || fail "successful next-start recovery left the guard armed"

run_killed_case clear MOCK_KILL_DURING_APPLY=1
grep -Fq 'qos-apply:1' "$TMP/mock.log" || fail "during-apply KILL was not exercised"
[ -f "$TMP/qos-worker" ] || fail "during-apply KILL lost the persistent worker marker"
! grep -Fq 'safe-confirm:' "$TMP/mock.log" || fail "during-apply KILL confirmed an incomplete runtime"
run_recovery 1 MOCK_QUIESCE_FAIL=1 MOCK_RECOVERY_BACKUP=/root/dashboard-backups/smartap-clear-client-limits-20260823.tar.gz
[ -f "$TMP/armed" ] || fail "failed worker quiesce discarded the authoritative guard"
! grep -Fq 'safe-rollback:' "$TMP/mock.log" || fail "recovery raced rollback against an unquiesced QoS worker"
run_recovery 0 MOCK_RECOVERY_BACKUP=/root/dashboard-backups/smartap-clear-client-limits-20260823.tar.gz
assert_log_order 'quiesce:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'safe-rollback:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
grep -Fqx 'old-policy' "$TMP/smartap" || fail "next start did not restore during-apply KILL"
[ ! -e "$TMP/armed" ] && [ ! -e "$TMP/qos-worker" ] || fail "successful recovery left interruption state behind"

printf 'dashctl_mac_qos_transactions=pass\n'
