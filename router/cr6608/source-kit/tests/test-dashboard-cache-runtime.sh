#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LIB="$ROOT/files/usr/libexec/cr6608-dashboard-cache-state"

# Run the killed-collector fixture in a fresh shell process. POSIX keeps $$
# unchanged inside a mere `( ... ) &` subshell, which would make the guardian
# monitor the test runner rather than the collector process being killed.
if [ "${1:-}" = --collector-holder ]; then
	TMP="$2"
	exec 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
	. "$LIB"
	cr6608_dashboard_cache_collector_acquire || exit 11
	_collector_residue="$CR6608_DASHBOARD_CACHE_DIR/.dashcmd-out.$$.SIGKILL"
	printf 'live-request-telemetry\n' >"$_collector_residue"
	(
		exec 8>&-
		exec 3>>"$_collector_residue" || exit 12
		: >"$TMP/collector-long-child-ready"
		while [ ! -e "$TMP/collector-long-child-write" ]; do sleep 0.1; done
		printf 'late-after-parent-death\n' >&3
		exec 3>&-
		: >"$TMP/collector-long-child-done"
	) &
	printf '%s\n' "$!" >"$TMP/collector-long-child-pid"
	printf '%s\n' "$$" >"$TMP/collector-parent-pid"
	printf '%s\n' "$_collector_residue" >"$TMP/collector-residue-path"
	: >"$TMP/collector-held"
	# Yield without allowing a sleeper to carry the guardian lock.
	while :; do ( exec 8>&-; sleep 0.1 ); done
fi

if [ "${1:-}" = --handoff-owner ]; then
	TMP="$2"
	exec 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
	. "$LIB"
	cr6608_dashboard_cache_collector_acquire || exit 21
	_handoff_residue="$CR6608_DASHBOARD_CACHE_DIR/.linklog.$$.HANDOFF"
	printf 'handoff-request-telemetry\n' >"$_handoff_residue"
	printf '%s\n' "$_handoff_residue" >"$TMP/handoff-residue-path"
	printf '%s\n' "$$" >"$TMP/handoff-owner-pid"
	: >"$TMP/handoff-owner-held"
	while :; do ( exec 8>&-; sleep 0.1 ); done
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-coordination-test.XXXXXX")"
holder_pid=""
collector_long_child_pid=""
slow_guardian_pid=""
mutator_pid=""
handoff_owner_pid=""
handoff_waiter_pid=""
purge_failure_pid=""
pid_reuse_probe_pid=""
cleanup() {
	trap - EXIT HUP INT TERM
	[ ! -d "$TMP" ] || {
		: >"$TMP/collector-long-child-write"
		: >"$TMP/slow-identity-go"
	}
	for _cleanup_pid in "$holder_pid" "$collector_long_child_pid" \
		"$slow_guardian_pid" "$mutator_pid" \
		"$handoff_owner_pid" "$handoff_waiter_pid" "$purge_failure_pid" \
		"$pid_reuse_probe_pid"; do
		[ -n "$_cleanup_pid" ] || continue
		kill -KILL "$_cleanup_pid" 2>/dev/null || true
	done
	rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

fail() { printf 'dashboard_cache_runtime=FAIL %s\n' "$1" >&2; exit 1; }

command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is unavailable'
command -v flock >/dev/null 2>&1 || fail 'flock is unavailable'
TEST_SHELL_EXE="$(readlink "/proc/$$/exe" 2>/dev/null)" ||
	fail 'cannot resolve the shell executable'
[ -x "$TEST_SHELL_EXE" ] || fail 'resolved shell executable is not executable'
TEST_SHELL_NAME="${TEST_SHELL_EXE##*/}"
FIXTURE_WAIT_TRIES=150

CR6608_DASHBOARD_CACHE_DIR="$TMP/state"
CR6608_DASHBOARD_CACHE_EXPECT_UID="$(id -u)"
printf 'network-v1\n' >"$TMP/config-network"
printf 'wireless-v1\n' >"$TMP/config-wireless"
CR6608_DASHBOARD_FINGERPRINT_PATHS="$TMP/config-network $TMP/config-wireless"
export CR6608_DASHBOARD_CACHE_DIR CR6608_DASHBOARD_CACHE_EXPECT_UID
export CR6608_DASHBOARD_FINGERPRINT_PATHS
. "$LIB"

assert_no_telemetry() {
	_phase="$1"
	for _leaf in response.json perf lite.cpu cpu traffic traffic.topology \
		iface.lan1 sta.001122334455 survey.phy0-ap0; do
		{ [ ! -e "$CR6608_DASHBOARD_CACHE_DIR/$_leaf" ] &&
		  [ ! -L "$CR6608_DASHBOARD_CACHE_DIR/$_leaf" ]; } ||
			fail "$_phase retained $_leaf"
	done
	if find "$CR6608_DASHBOARD_CACHE_DIR" -maxdepth 1 \( \
			-name '.dashcmd-out.*.*' -o -name '.dashcmd-err.*.*' -o \
			-name '.linklog.*.*' -o -name '.devices.*' -o \
			-name '.arp.*' -o -name '.fdb.*' -o -name '.lease.*' -o \
			-name '.degraded.*' -o -name '.view.*.*' -o \
			-name '.emit.*.*' -o -name '.publish.*.*' -o \
			-name '.publish-final.*.*' -o -name '.perf.*.*' -o \
			-name '.collect.*.*' \) -print -quit 2>/dev/null | grep -q .; then
		fail "$_phase retained request-private telemetry"
	fi
}

seed_legacy_telemetry() {
	mkdir -p "$CR6608_DASHBOARD_CACHE_DIR"
	for _leaf in response.json perf lite.cpu cpu traffic traffic.topology \
		iface.lan1 sta.001122334455 survey.phy0-ap0; do
		printf 'legacy-private-telemetry\n' >"$CR6608_DASHBOARD_CACHE_DIR/$_leaf"
	done
}

seed_request_telemetry() {
	for _leaf in \
		.dashcmd-out.700.RESIDUE .dashcmd-err.700.RESIDUE \
		.linklog.700.RESIDUE .devices.700 .arp.700 .fdb.700 .lease.700 \
		.degraded.700 .view.700.RESIDUE .emit.700.RESIDUE \
		.publish.700.RESIDUE .publish-final.700.RESIDUE \
		.perf.700.RESIDUE .collect.700.RESIDUE; do
		printf 'request-private-telemetry\n' >"$CR6608_DASHBOARD_CACHE_DIR/$_leaf"
	done
}

# A hostile directory symlink is rejected without touching its target.
printf 'victim-state\n' >"$TMP/victim-state"
ln -s "$TMP/victim-state" "$CR6608_DASHBOARD_CACHE_DIR"
if cr6608_dashboard_cache_prepare; then fail 'state-dir symlink accepted'; fi
[ "$(cat "$TMP/victim-state")" = victim-state ] || fail 'state-dir symlink target changed'
rm -f "$CR6608_DASHBOARD_CACHE_DIR"

# Concurrent first users converge on one validated private state directory.
prepare_pids=""
for _prepare_n in 1 2 3 4 5 6 7 8; do
	( . "$LIB"; cr6608_dashboard_cache_prepare ) &
	prepare_pids="$prepare_pids $!"
done
for _prepare_pid in $prepare_pids; do
	wait "$_prepare_pid" || fail 'concurrent first prepare failed'
done
[ -d "$CR6608_DASHBOARD_CACHE_DIR" ] && [ ! -L "$CR6608_DASHBOARD_CACHE_DIR" ] ||
	fail 'prepare did not create a safe state directory'

# Recovery uses FD9 only inside a subshell. A caller may already reserve and
# lock FD9 (safe-wifi-reload does during handoff), so prepare must leave the
# descriptor target, contents and independently observable lock unchanged.
printf 'caller-fd9-sentinel\n' >"$TMP/fd9-sentinel"
exec 9>>"$TMP/fd9-sentinel"
flock -xn 9 || fail 'could not acquire caller FD9 sentinel lock'
fd9_before="$(readlink "/proc/$$/fd/9" 2>/dev/null)"
fd9_hash_before="$(sha256sum "$TMP/fd9-sentinel" | awk '{print $1}')"
cr6608_dashboard_cache_prepare || fail 'prepare failed with caller FD9 reserved'
fd9_after="$(readlink "/proc/$$/fd/9" 2>/dev/null)"
fd9_hash_after="$(sha256sum "$TMP/fd9-sentinel" | awk '{print $1}')"
[ -n "$fd9_before" ] && [ "$fd9_after" = "$fd9_before" ] ||
	fail 'prepare replaced or closed caller FD9'
[ "$fd9_hash_after" = "$fd9_hash_before" ] || fail 'prepare modified caller FD9 target'
if ( exec 3>>"$TMP/fd9-sentinel"; flock -xn 3 ); then
	fail 'prepare released caller FD9 lock'
fi
flock -u 9 || fail 'could not release caller FD9 sentinel lock'
exec 9>&-

# prepare is the global/boot migration gate: every historical shared or
# request-private telemetry leaf is removed, including hostile symlinks, while
# metadata and unrelated state stay.
printf 'victim-response\n' >"$TMP/victim-response"
ln -s "$TMP/victim-response" "$CR6608_DASHBOARD_CACHE_DIR/response.json"
for _leaf in perf lite.cpu cpu traffic traffic.topology iface.lan1 \
	sta.001122334455 survey.phy0-ap0; do
	printf 'legacy-private-telemetry\n' >"$CR6608_DASHBOARD_CACHE_DIR/$_leaf"
done
seed_request_telemetry
printf 'victim-request\n' >"$TMP/victim-request"
ln -s "$TMP/victim-request" "$CR6608_DASHBOARD_CACHE_DIR/.dashcmd-err.701.SYMLINK"
printf 'operator-runtime-state\n' >"$CR6608_DASHBOARD_CACHE_DIR/operator.keep"
cr6608_dashboard_cache_prepare || fail 'prepare migration failed'
assert_no_telemetry 'prepare migration'
[ "$(cat "$TMP/victim-response")" = victim-response ] ||
	fail 'telemetry symlink target was modified'
[ "$(cat "$TMP/victim-request")" = victim-request ] ||
	fail 'request-private telemetry symlink target was modified'
[ "$(cat "$CR6608_DASHBOARD_CACHE_DIR/operator.keep")" = operator-runtime-state ] ||
	fail 'prepare removed unrelated runtime state'

# Configuration fingerprints remain coordination metadata and advance only the
# generation; they never create a dashboard response.
cr6608_dashboard_cache_external_sync || fail 'initial fingerprint failed'
generation0="$(cr6608_dashboard_cache_generation)"
printf 'wireless-v2-expanded\n' >"$TMP/config-wireless"
cr6608_dashboard_cache_external_sync || fail 'changed fingerprint failed'
generation1="$(cr6608_dashboard_cache_generation)"
[ "$generation1" != "$generation0" ] || fail 'external edit did not advance generation'
assert_no_telemetry 'external fingerprint sync'

# A healthy acquisition transfers FD8 exclusively to a guardian with null
# stdio. The collector parent closes FD8 before it can launch sampling children,
# and normal release requests guardian exit, reaps it and removes its control.
cr6608_dashboard_cache_collector_acquire || fail 'normal guardian acquisition failed'
normal_guardian_pid="$CR6608_DASHBOARD_CACHE_GUARDIAN_PID"
normal_guardian_start="$CR6608_DASHBOARD_CACHE_GUARDIAN_START"
normal_guardian_control="$CR6608_DASHBOARD_CACHE_GUARDIAN_CONTROL"
[ "$CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER" = 1 ] ||
	fail 'normal acquisition did not publish ownership'
cr6608_dashboard_cache_process_matches "$normal_guardian_pid" "$normal_guardian_start" ||
	fail 'normal guardian identity is not live'
[ ! -e "/proc/$$/fd/8" ] || fail 'collector parent retained FD8 after acquisition'
[ -e "/proc/$normal_guardian_pid/fd/8" ] || fail 'guardian does not retain FD8'
for _guardian_stdio in 0 1 2; do
	[ "$(readlink "/proc/$normal_guardian_pid/fd/$_guardian_stdio" 2>/dev/null)" = /dev/null ] ||
		fail "guardian FD$_guardian_stdio is not /dev/null"
done
[ -f "$normal_guardian_control" ] && [ ! -L "$normal_guardian_control" ] ||
	fail 'normal guardian control is unsafe'
[ "$(cat "$normal_guardian_control")" = ready ] || fail 'normal guardian is not ready'
cr6608_dashboard_cache_collector_release || fail 'normal guardian release failed'
[ "$CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER" = 0 ] ||
	fail 'normal release retained ownership'
if cr6608_dashboard_cache_process_matches "$normal_guardian_pid" "$normal_guardian_start"; then
	fail 'normal release retained guardian process'
fi
[ ! -e "$normal_guardian_control" ] && [ ! -L "$normal_guardian_control" ] ||
	fail 'normal release retained guardian control'
[ -z "$CR6608_DASHBOARD_CACHE_GUARDIAN_PID$CR6608_DASHBOARD_CACHE_GUARDIAN_START$CR6608_DASHBOARD_CACHE_GUARDIAN_CONTROL" ] ||
	fail 'normal release retained guardian state'

# Model a reused guardian PID with a live child carrying a deliberately
# different starttime. Stale cleanup may fail, but it must not signal the child.
pid_reuse_control="$CR6608_DASHBOARD_CACHE_DIR/.collector-control.$$.PIDREUSE"
printf 'ready\n' >"$pid_reuse_control"
chmod 0600 "$pid_reuse_control"
sleep 30 &
pid_reuse_probe_pid=$!
pid_reuse_identity="$(cr6608_dashboard_cache_process_identity "$pid_reuse_probe_pid")" ||
	fail 'could not identify PID-reuse probe'
pid_reuse_start="${pid_reuse_identity#* }"
pid_reuse_wrong_start=$((pid_reuse_start + 1))
set +e
cr6608_dashboard_cache_collector_guardian_stop \
	"$pid_reuse_probe_pid" "$pid_reuse_wrong_start" "$pid_reuse_control"
pid_reuse_stop_rc=$?
set -e
[ "$pid_reuse_stop_rc" -ne 0 ] || fail 'stale guardian identity was accepted'
kill -0 "$pid_reuse_probe_pid" 2>/dev/null ||
	fail 'stale guardian PID signalled an unrelated process'
kill -KILL "$pid_reuse_probe_pid" 2>/dev/null || true
wait "$pid_reuse_probe_pid" 2>/dev/null || true
pid_reuse_probe_pid=""
[ ! -e "$pid_reuse_control" ] && [ ! -L "$pid_reuse_control" ] ||
	fail 'stale guardian control was retained'

# Regression for the subtle command-substitution carrier: inject a deliberately
# slow process_identity helper, kill the guardian while it waits, and acquire
# collector.lock while that helper is still blocked. Any outer `$()` shell that
# retained FD8 would keep this acquisition from succeeding.
slow_control="$CR6608_DASHBOARD_CACHE_DIR/.collector-control.$$.SLOW"
printf 'starting\n' >"$slow_control"
chmod 0600 "$slow_control"
(
	exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
	exec 8>>"$CR6608_DASHBOARD_CACHE_DIR/collector.lock" || exit 51
	flock -xn 8 || exit 52
	cr6608_dashboard_cache_process_identity() {
		: >"$TMP/slow-identity-started"
		while [ ! -e "$TMP/slow-identity-go" ]; do sleep 0.1; done
		printf 'R 1\n'
	}
	cr6608_dashboard_cache_collector_guardian_loop "$$" 1 "$slow_control"
) &
slow_guardian_pid=$!
waited=0
while [ ! -e "$TMP/slow-identity-started" ] &&
	[ "$waited" -lt "$FIXTURE_WAIT_TRIES" ]; do
	sleep 0.1; waited=$((waited + 1))
done
[ -e "$TMP/slow-identity-started" ] || fail 'slow identity guardian did not enter helper'
[ -e "/proc/$slow_guardian_pid/fd/8" ] || fail 'slow identity guardian lacks FD8'
kill -KILL "$slow_guardian_pid"
set +e
wait "$slow_guardian_pid" 2>/dev/null
slow_guardian_rc=$?
set -e
slow_guardian_pid=""
[ "$slow_guardian_rc" -ne 0 ] || fail 'killed slow identity guardian exited successfully'
exec 3>>"$CR6608_DASHBOARD_CACHE_DIR/collector.lock" ||
	fail 'cannot open collector lock after killing slow guardian'
flock -xn 3 || fail 'slow identity command substitution inherited FD8'
flock -u 3 || fail 'cannot release slow identity verification lock'
exec 3>&-
: >"$TMP/slow-identity-go"
rm -f -- "$slow_control"

# Collector exclusion remains atomic across SIGKILL. A fresh shell is the real
# monitored parent and launches a long child which keeps a telemetry inode open
# but has no FD8. The guardian notices parent death, the next acquisition purges
# the namespace, and a late write to that deleted inode cannot recreate a file.
rm -f "$TMP/collector-held" "$TMP/collector-long-child-ready" \
	"$TMP/collector-long-child-write" "$TMP/collector-long-child-done" \
	"$TMP/collector-long-child-pid" "$TMP/collector-parent-pid" \
	"$TMP/collector-residue-path"
case "$TEST_SHELL_NAME" in
	busybox) "$TEST_SHELL_EXE" sh "$0" --collector-holder "$TMP" & ;;
	*) "$TEST_SHELL_EXE" "$0" --collector-holder "$TMP" & ;;
esac
holder_pid=$!
waited=0
while { [ ! -e "$TMP/collector-held" ] ||
	[ ! -e "$TMP/collector-long-child-ready" ]; } &&
	[ "$waited" -lt "$FIXTURE_WAIT_TRIES" ]; do
	sleep 0.1; waited=$((waited + 1))
done
[ -e "$TMP/collector-held" ] || fail 'collector holder did not start'
[ -e "$TMP/collector-long-child-ready" ] || fail 'collector long child did not start'
[ "$(cat "$TMP/collector-parent-pid")" = "$holder_pid" ] ||
	fail 'guardian fixture is not a fresh collector process'
collector_long_child_pid="$(cat "$TMP/collector-long-child-pid")"
case "$collector_long_child_pid" in ''|*[!0-9]*|0) fail 'invalid long child PID' ;; esac
kill -0 "$collector_long_child_pid" 2>/dev/null || fail 'collector long child is not live'
[ ! -e "/proc/$collector_long_child_pid/fd/8" ] ||
	fail 'collector long child inherited FD8'
collector_residue="$(cat "$TMP/collector-residue-path")"
[ -f "$collector_residue" ] || fail 'collector residue fixture is missing'
cr6608_dashboard_cache_prepare || fail 'prepare failed while collector was live'
[ -f "$collector_residue" ] || fail 'prepare deleted active collector telemetry'
if cr6608_dashboard_cache_collector_acquire; then fail 'collectors overlapped'; fi
kill -KILL "$holder_pid"
set +e
wait "$holder_pid" 2>/dev/null
holder_rc=$?
set -e
holder_pid=""
[ "$holder_rc" -ne 0 ] || fail 'SIGKILL collector exited successfully'
kill -0 "$collector_long_child_pid" 2>/dev/null ||
	fail 'collector long child did not survive parent SIGKILL'
collector_recovered=0
collector_recover_try=0
while [ "$collector_recover_try" -lt "$FIXTURE_WAIT_TRIES" ]; do
	if cr6608_dashboard_cache_collector_acquire; then
		collector_recovered=1
		break
	fi
	sleep 0.1
	collector_recover_try=$((collector_recover_try + 1))
done
[ "$collector_recovered" = 1 ] || fail 'guardian did not release killed collector lock'
[ ! -e "$collector_residue" ] && [ ! -L "$collector_residue" ] ||
	fail 'next acquisition retained SIGKILL collector telemetry'
deleted_inode="$(readlink "/proc/$collector_long_child_pid/fd/3" 2>/dev/null)" ||
	fail 'long child lost its deliberately open telemetry inode too early'
case "$deleted_inode" in
	*' (deleted)') ;;
	*) fail 'next acquisition did not unlink the long child telemetry inode' ;;
esac
cr6608_dashboard_cache_collector_release || fail 'post-SIGKILL guardian release failed'
: >"$TMP/collector-long-child-write"
waited=0
while [ ! -e "$TMP/collector-long-child-done" ] &&
	[ "$waited" -lt "$FIXTURE_WAIT_TRIES" ]; do
	sleep 0.1; waited=$((waited + 1))
done
[ -e "$TMP/collector-long-child-done" ] || fail 'long child did not complete late write'
[ ! -e "/proc/$collector_long_child_pid/fd/3" ] ||
	fail 'completed long child retained the telemetry inode'
[ ! -e "$collector_residue" ] && [ ! -L "$collector_residue" ] ||
	fail 'late write recreated request-private telemetry'
collector_long_child_pid=""
assert_no_telemetry 'post-SIGKILL long-child recovery'

# Deterministic prepare -> lock-handoff race. Owner A remains alive while B's
# overridden prepare completes, proving B skipped global private cleanup. A is
# then SIGKILLed before B continues to FD8. The post-flock purge in
# collector_acquire must remove A's residue before B publishes ownership.
rm -f "$TMP/handoff-owner-held" "$TMP/handoff-waiter-prepared" \
	"$TMP/handoff-go" "$TMP/handoff-acquired" "$TMP/handoff-residue-path" \
	"$TMP/handoff-owner-pid"
case "$TEST_SHELL_NAME" in
	busybox) "$TEST_SHELL_EXE" sh "$0" --handoff-owner "$TMP" & ;;
	*) "$TEST_SHELL_EXE" "$0" --handoff-owner "$TMP" & ;;
esac
handoff_owner_pid=$!
waited=0
while [ ! -e "$TMP/handoff-owner-held" ] &&
	[ "$waited" -lt "$FIXTURE_WAIT_TRIES" ]; do
	sleep 0.1; waited=$((waited + 1))
done
[ -e "$TMP/handoff-owner-held" ] || fail 'handoff owner did not start'
[ "$(cat "$TMP/handoff-owner-pid")" = "$handoff_owner_pid" ] ||
	fail 'handoff fixture is not a fresh collector process'
handoff_residue="$(cat "$TMP/handoff-residue-path")"
[ -f "$handoff_residue" ] || fail 'handoff residue fixture is missing'
(
	exec 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
	. "$LIB"
	cr6608_dashboard_cache_prepare() {
		( . "$LIB"; cr6608_dashboard_cache_prepare ) || return 1
		: >"$TMP/handoff-waiter-prepared"
		while [ ! -e "$TMP/handoff-go" ]; do sleep 0.05; done
	}
	_handoff_try=0
	while ! cr6608_dashboard_cache_collector_acquire; do
		_handoff_try=$((_handoff_try + 1))
		[ "$_handoff_try" -lt "$FIXTURE_WAIT_TRIES" ] || exit 22
		sleep 0.1
	done
	[ ! -e "$handoff_residue" ] && [ ! -L "$handoff_residue" ] || exit 23
	: >"$TMP/handoff-acquired"
	cr6608_dashboard_cache_collector_release || exit 24
) &
handoff_waiter_pid=$!
waited=0
while [ ! -e "$TMP/handoff-waiter-prepared" ] &&
	[ "$waited" -lt "$FIXTURE_WAIT_TRIES" ]; do
	sleep 0.1; waited=$((waited + 1))
done
[ -e "$TMP/handoff-waiter-prepared" ] || fail 'handoff waiter did not finish prepare'
[ -f "$handoff_residue" ] || fail 'prepare removed live handoff residue'
kill -KILL "$handoff_owner_pid"
set +e
wait "$handoff_owner_pid" 2>/dev/null
handoff_owner_rc=$?
set -e
handoff_owner_pid=""
[ "$handoff_owner_rc" -ne 0 ] || fail 'handoff owner SIGKILL exited successfully'
: >"$TMP/handoff-go"
set +e
wait "$handoff_waiter_pid"
handoff_waiter_rc=$?
set -e
handoff_waiter_pid=""
[ "$handoff_waiter_rc" -eq 0 ] || fail "handoff waiter failed: $handoff_waiter_rc"
[ -e "$TMP/handoff-acquired" ] || fail 'handoff waiter did not acquire FD8'
[ ! -e "$handoff_residue" ] && [ ! -L "$handoff_residue" ] ||
	fail 'FD8 handoff retained killed collector telemetry'
assert_no_telemetry 'collector FD8 handoff'

# If post-flock cleanup encounters an unexpected object, acquisition must fail
# closed, clear OWNER, close FD8 and leave collector.lock immediately reusable.
rm -f "$TMP/purge-failure-prepared" "$TMP/purge-failure-go" \
	"$TMP/purge-failure-verified"
(
	exec 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
	. "$LIB"
	cr6608_dashboard_cache_prepare() {
		( . "$LIB"; cr6608_dashboard_cache_prepare ) || return 1
		: >"$TMP/purge-failure-prepared"
		while [ ! -e "$TMP/purge-failure-go" ]; do sleep 0.05; done
	}
	if cr6608_dashboard_cache_collector_acquire; then exit 31; fi
	[ "$CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER" = 0 ] || exit 32
	exec 3>>"$CR6608_DASHBOARD_CACHE_DIR/collector.lock" || exit 33
	flock -xn 3 || exit 34
	flock -u 3 || exit 35
	exec 3>&-
	: >"$TMP/purge-failure-verified"
) &
purge_failure_pid=$!
waited=0
while [ ! -e "$TMP/purge-failure-prepared" ] &&
	[ "$waited" -lt "$FIXTURE_WAIT_TRIES" ]; do
	sleep 0.1; waited=$((waited + 1))
done
[ -e "$TMP/purge-failure-prepared" ] || fail 'purge-failure waiter did not finish prepare'
mkdir "$CR6608_DASHBOARD_CACHE_DIR/.devices.999"
: >"$TMP/purge-failure-go"
set +e
wait "$purge_failure_pid"
purge_failure_rc=$?
set -e
purge_failure_pid=""
[ "$purge_failure_rc" -eq 0 ] || fail "purge failure was not fail-closed: $purge_failure_rc"
[ -e "$TMP/purge-failure-verified" ] || fail 'failed purge retained FD8 or ownership'
rmdir "$CR6608_DASHBOARD_CACHE_DIR/.devices.999"
cr6608_dashboard_cache_collector_acquire || fail 'collector lock unusable after purge failure'
cr6608_dashboard_cache_collector_release || fail 'collector release failed after purge failure'

# If the guardian exits before publishing ready, acquisition must fail closed,
# reap it, remove the control file and leave collector.lock independently usable.
if ! (
	exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
	. "$LIB"
	cr6608_dashboard_cache_collector_guardian_loop() {
		exec 8>&-
		return 77
	}
	if cr6608_dashboard_cache_collector_acquire; then exit 41; fi
	[ "$CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER" = 0 ] || exit 42
	[ -z "$CR6608_DASHBOARD_CACHE_GUARDIAN_PID$CR6608_DASHBOARD_CACHE_GUARDIAN_START$CR6608_DASHBOARD_CACHE_GUARDIAN_CONTROL" ] ||
		exit 43
	exec 3>>"$CR6608_DASHBOARD_CACHE_DIR/collector.lock" || exit 44
	flock -xn 3 || exit 45
	flock -u 3 || exit 46
	exec 3>&-
	if find "$CR6608_DASHBOARD_CACHE_DIR" -maxdepth 1 \
		-name '.collector-control.*.*' -print -quit | grep -q .; then
		exit 47
	fi
); then
	fail 'guardian startup failure was not fail-closed'
fi

# A replaced control path is never followed. Release reports the tamper, stops
# the guardian anyway, unlinks only the symlink and leaves its target unchanged.
printf 'guardian-control-victim\n' >"$TMP/guardian-control-victim"
cr6608_dashboard_cache_collector_acquire || fail 'control-symlink fixture acquire failed'
tampered_guardian_pid="$CR6608_DASHBOARD_CACHE_GUARDIAN_PID"
tampered_guardian_start="$CR6608_DASHBOARD_CACHE_GUARDIAN_START"
tampered_guardian_control="$CR6608_DASHBOARD_CACHE_GUARDIAN_CONTROL"
rm -f -- "$tampered_guardian_control"
ln -s "$TMP/guardian-control-victim" "$tampered_guardian_control"
set +e
cr6608_dashboard_cache_collector_release
tampered_release_rc=$?
set -e
[ "$tampered_release_rc" -ne 0 ] || fail 'control symlink tamper was accepted'
[ "$(cat "$TMP/guardian-control-victim")" = guardian-control-victim ] ||
	fail 'control symlink target was modified'
[ ! -e "$tampered_guardian_control" ] && [ ! -L "$tampered_guardian_control" ] ||
	fail 'tampered guardian control symlink was retained'
[ "$CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER" = 0 ] ||
	fail 'tampered release retained ownership'
if cr6608_dashboard_cache_process_matches "$tampered_guardian_pid" "$tampered_guardian_start"; then
	fail 'tampered release retained guardian process'
fi
cr6608_dashboard_cache_collector_acquire ||
	fail 'collector lock unusable after control symlink tamper'
cr6608_dashboard_cache_collector_release ||
	fail 'collector release failed after control symlink tamper'

# Managed changes remain generation-safe and purge any legacy artifacts at both
# bracket edges without publishing a response.
seed_legacy_telemetry
cr6608_dashboard_cache_mutation_begin || fail 'mutation begin failed'
assert_no_telemetry 'mutation begin'
cr6608_dashboard_cache_mutation_active || fail 'active mutation was not visible'
mutation_generation="$(cr6608_dashboard_cache_generation)"
seed_legacy_telemetry
cr6608_dashboard_cache_mutation_finish || fail 'mutation finish failed'
assert_no_telemetry 'mutation finish'
final_generation="$(cr6608_dashboard_cache_generation)"
[ "$final_generation" != "$mutation_generation" ] ||
	fail 'mutation finish did not advance generation'
if cr6608_dashboard_cache_mutation_active; then fail 'finished mutation stayed active'; fi

# A killed mutator leaves a fail-closed dirty marker; recovery advances the
# generation, removes the marker and still leaves no telemetry.
(
	exec 4>&- 5>&- 6>&- 7>&- 8>&-
	. "$LIB"
	cr6608_dashboard_cache_mutation_begin || exit 12
	: >"$TMP/mutator-held"
	# Stay in this shell; every sleeper closes its inherited mutation lock.
	while :; do ( exec 7>&-; sleep 0.1 ); done
) &
mutator_pid=$!
waited=0
while [ ! -e "$TMP/mutator-held" ] &&
	[ "$waited" -lt "$FIXTURE_WAIT_TRIES" ]; do
	sleep 0.1; waited=$((waited + 1))
done
[ -e "$TMP/mutator-held" ] || fail 'mutator holder did not start'
kill -KILL "$mutator_pid"
set +e
wait "$mutator_pid" 2>/dev/null
mutator_rc=$?
set -e
mutator_pid=""
[ "$mutator_rc" -ne 0 ] || fail 'SIGKILL mutator exited successfully'
[ -f "$CR6608_DASHBOARD_CACHE_DIR/mutation.dirty" ] || fail 'dirty marker missing'
seed_legacy_telemetry
cr6608_dashboard_cache_recover_dirty || fail 'dirty recovery failed'
[ ! -e "$CR6608_DASHBOARD_CACHE_DIR/mutation.dirty" ] || fail 'dirty marker retained'
assert_no_telemetry 'dirty recovery'

# The removed cache ABI cannot be reintroduced accidentally through the shared
# state helper.
for forbidden_function in \
	cr6608_dashboard_cache_snapshot \
	cr6608_dashboard_cache_inspect \
	cr6608_dashboard_cache_publish; do
	! command -v "$forbidden_function" >/dev/null 2>&1 ||
		fail "forbidden function exists: $forbidden_function"
done

printf 'dashboard_cache_runtime=pass\n'
