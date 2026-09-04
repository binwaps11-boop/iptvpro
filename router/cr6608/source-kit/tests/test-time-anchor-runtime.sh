#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/files/usr/sbin/smartap-time-anchor"
INIT="$ROOT/files/etc/init.d/smartap-time-anchor"
DEFAULTS="$ROOT/files/etc/uci-defaults/00-smartap-time-anchor"
KEEP="$ROOT/files/lib/upgrade/keep.d/cr6608-retail"
DASHCTL="$ROOT/files/www/cgi-bin/dashctl"
BUILD="$ROOT/build.sh"
TMP="$(mktemp -d)"
REAL_FLOCK="$(command -v flock 2>/dev/null || true)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() {
	printf 'time anchor test failed: %s\n' "$1" >&2
	exit 1
}

assert_file() {
	actual="$(cat "$1")"
	[ "$actual" = "$2" ] || fail "$3 (got $actual, expected $2)"
}

mkdir -p "$TMP/bin" "$TMP/etc" "$TMP/rom/etc" "$TMP/run"
cat >"$TMP/bin/date" <<'EOF'
#!/bin/sh
if [ "${1:-}" = '+%s' ] && [ "$#" -eq 1 ]; then
	cat "$FAKE_CLOCK"
	exit 0
fi
if [ "${1:-}" = '-u' ] && [ "${2:-}" = '-s' ] && [ "$#" -eq 3 ]; then
	value="${3#@}"
	case "$value" in ''|*[!0-9]*) exit 1 ;; esac
	if [ -n "${FAKE_SLOW_SET_EPOCH:-}" ] && [ "$value" = "$FAKE_SLOW_SET_EPOCH" ]; then
		: >"$FAKE_SLOW_STARTED"
		sleep "${FAKE_SLOW_SET_DELAY:-2}"
	fi
	printf '%s\n' "$value" >"$FAKE_CLOCK"
	exit 0
fi
exit 1
EOF
cat >"$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/bin/sync" <<'EOF'
#!/bin/sh
printf 'sync\n' >>"$FAKE_SYNC_LOG"
exit 0
EOF
chmod 0755 "$TMP/bin/date" "$TMP/bin/logger" "$TMP/bin/sync"
if [ -z "$REAL_FLOCK" ]; then
	# Git for Windows has no flock. Sequential semantics are still exercised;
	# the real kernel-concurrency case runs on the Linux build host.
	cat >"$TMP/bin/flock" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod 0755 "$TMP/bin/flock"
fi

export PATH="$TMP/bin:$PATH"
export FAKE_CLOCK="$TMP/clock"
export FAKE_SYNC_LOG="$TMP/sync.log"
export SMARTAP_TIME_ANCHOR_STATE_FILE="$TMP/etc/smartap-time-anchor"
export SMARTAP_TIME_ANCHOR_IMAGE_FILE="$TMP/rom/etc/smartap-time-anchor"
export SMARTAP_TIME_ANCHOR_MIN_WRITE_ADVANCE=100
export SMARTAP_TIME_ANCHOR_LOCK_DIR="$TMP/run/smartap-time-anchor"
export SMARTAP_TIME_ANCHOR_LOCK_EXPECT_UID="$(id -u)"

reset_case() {
	printf '%s\n' "$1" >"$SMARTAP_TIME_ANCHOR_IMAGE_FILE"
	printf '%s\n' "$2" >"$SMARTAP_TIME_ANCHOR_STATE_FILE"
	printf '%s\n' "$3" >"$FAKE_CLOCK"
	: >"$FAKE_SYNC_LOG"
}

# The greatest valid image/state floor wins, even when the RTC is invalid.
reset_case 1700000000 1700000100 100
sh "$HELPER" apply
assert_file "$FAKE_CLOCK" 1700000100 'apply did not select the preserved state floor'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000100 'apply rewrote a current state'
[ ! -s "$FAKE_SYNC_LOG" ] || fail 'an ordinary boot caused a flash write'

# A newer firmware floor is applied and persisted once after sysupgrade.
reset_case 1700010000 1700000000 1700005000
sh "$HELPER" apply
assert_file "$FAKE_CLOCK" 1700010000 'new image floor was not applied'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700010000 'new image floor was not persisted'
[ "$(wc -l <"$FAKE_SYNC_LOG")" -eq 1 ] || fail 'new image floor was not synchronized exactly once'

# Downgrading an image must never lower a newer preserved floor.
reset_case 1700000000 1700020000 1700010000
sh "$HELPER" apply
assert_file "$FAKE_CLOCK" 1700020000 'newer preserved floor lost to an older image'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700020000 'newer preserved state was modified'
[ ! -s "$FAKE_SYNC_LOG" ] || fail 'downgrade protection caused an unnecessary write'

# A corrupt overlay is ignored, then repaired from the immutable image copy.
reset_case 1700030000 broken 100
sh "$HELPER" apply
assert_file "$FAKE_CLOCK" 1700030000 'corrupt state prevented image recovery'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700030000 'corrupt state was not repaired'
[ "$(wc -l <"$FAKE_SYNC_LOG")" -eq 1 ] || fail 'corrupt state recovery did not synchronize once'

# Without any valid floor, fail closed and do not change the clock.
reset_case broken invalid 1700040000
if sh "$HELPER" apply >/dev/null 2>&1; then
	fail 'invalid image and state anchors were accepted'
fi
assert_file "$FAKE_CLOCK" 1700040000 'failed apply changed the clock'

# Periodic refreshes are coalesced to protect flash, and become durable at the
# configured threshold. Repeating the same epoch does not write again.
reset_case 1700000000 1700000000 1700000099
sh "$HELPER" refresh
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000000 'sub-threshold refresh wrote state'
[ ! -s "$FAKE_SYNC_LOG" ] || fail 'sub-threshold refresh synchronized flash'
printf '%s\n' 1700000100 >"$FAKE_CLOCK"
sh "$HELPER" refresh
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000100 'threshold refresh did not advance state'
[ "$(wc -l <"$FAKE_SYNC_LOG")" -eq 1 ] || fail 'threshold refresh was not synchronized once'
sh "$HELPER" refresh
[ "$(wc -l <"$FAKE_SYNC_LOG")" -eq 1 ] || fail 'unchanged refresh rewrote flash'

# Runtime clock rollback can never overwrite the persistent floor.
reset_case 1700000000 1700000200 1700000100
if sh "$HELPER" refresh >/dev/null 2>&1; then
	fail 'refresh accepted a clock below the persistent floor'
fi
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000200 'rollback refresh lowered state'
[ ! -s "$FAKE_SYNC_LOG" ] || fail 'rollback refresh synchronized flash'

# A browser value above the persistent floor but below the already-valid
# running clock must be rejected before date(1) can move CLOCK_REALTIME back.
reset_case 1700000000 1700000000 1700000600
if sh "$HELPER" set 1700000500 >/dev/null 2>&1; then
	fail 'authenticated time below the current clock was accepted'
fi
assert_file "$FAKE_CLOCK" 1700000600 'current-clock rollback changed CLOCK_REALTIME'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000000 'current-clock rollback changed state'
[ ! -s "$FAKE_SYNC_LOG" ] || fail 'current-clock rollback synchronized flash'

# Authenticated browser time is applied immediately and materially newer time
# is persisted. A request below the floor is rejected before CLOCK_REALTIME is
# changed, while repeated logins remain subject to write coalescing.
reset_case 1700000000 1700000000 1700000000
sh "$HELPER" set 1700000500
assert_file "$FAKE_CLOCK" 1700000500 'authenticated forward time was not set'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000500 'authenticated time was not persisted'
: >"$FAKE_SYNC_LOG"
sh "$HELPER" set 1700000501
assert_file "$FAKE_CLOCK" 1700000501 'small authenticated correction was not applied'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000500 'repeated login bypassed write coalescing'
[ ! -s "$FAKE_SYNC_LOG" ] || fail 'repeated login synchronized flash'
if sh "$HELPER" set 1700000400 >/dev/null 2>&1; then
	fail 'authenticated rollback below the floor was accepted'
fi
assert_file "$FAKE_CLOCK" 1700000501 'rejected authenticated rollback changed the clock'
assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000500 'rejected authenticated rollback changed state'
[ ! -s "$FAKE_SYNC_LOG" ] || fail 'rejected authenticated rollback synchronized flash'

# A root-owned non-symlinked runtime directory is mandatory; predictable lock
# names below a hostile symlink must fail closed.
rm -rf "$SMARTAP_TIME_ANCHOR_LOCK_DIR"
ln -s "$TMP/etc" "$SMARTAP_TIME_ANCHOR_LOCK_DIR"
if [ -L "$SMARTAP_TIME_ANCHOR_LOCK_DIR" ]; then
	if sh "$HELPER" apply >/dev/null 2>&1; then
		fail 'symlinked time anchor lock directory was accepted'
	fi
fi
rm -rf "$SMARTAP_TIME_ANCHOR_LOCK_DIR"

# Linux CI/build hosts exercise a true kernel-flock race. The older request is
# paused after validation while holding the lock; the newer writer must wait,
# then publish last. Without serialization the paused writer can otherwise set
# CLOCK_REALTIME back after the newer process has completed.
if [ -n "$REAL_FLOCK" ]; then
	reset_case 1700000000 1700000000 1700000000
	export FAKE_SLOW_SET_EPOCH=1700000200
	export FAKE_SLOW_SET_DELAY=2
	export FAKE_SLOW_STARTED="$TMP/slow-set-started"
	rm -f "$FAKE_SLOW_STARTED"
	sh "$HELPER" set 1700000200 &
	older_pid=$!
	waited=0
	while [ ! -e "$FAKE_SLOW_STARTED" ] && [ "$waited" -lt 50 ]; do
		sleep 0.1
		waited=$((waited + 1))
	done
	[ -e "$FAKE_SLOW_STARTED" ] || fail 'older concurrent writer did not reach the date hook'
	sh "$HELPER" set 1700000300 &
	newer_pid=$!
	wait "$older_pid" || fail 'older serialized writer failed'
	wait "$newer_pid" || fail 'newer serialized writer failed'
	assert_file "$FAKE_CLOCK" 1700000300 'concurrent older writer rolled CLOCK_REALTIME back'
	assert_file "$SMARTAP_TIME_ANCHOR_STATE_FILE" 1700000300 'concurrent older writer rolled state back'
	unset FAKE_SLOW_SET_EPOCH FAKE_SLOW_SET_DELAY FAKE_SLOW_STARTED
fi

# Static integration gates: procd owns the low-write monitor, first boot starts
# it, sysupgrade preserves state, and dashctl cannot bypass the helper.
grep -Fq 'USE_PROCD=1' "$INIT" || fail 'time anchor service is not procd-managed'
grep -Fq 'smartap-time-anchor monitor' "$INIT" || fail 'periodic monitor is not supervised'
grep -Fq 'smartap-time-anchor start' "$DEFAULTS" || fail 'first boot does not start the monitor'
[ "$(grep -Fxc '/etc/smartap-time-anchor' "$KEEP")" -eq 1 ] ||
	fail 'sysupgrade does not preserve exactly one time anchor path'
grep -Fq '/usr/sbin/smartap-time-anchor set "$epoch"' "$DASHCTL" ||
	fail 'dashboard time synchronization bypasses the helper'
! grep -Fq 'anchor_tmp="/etc/smartap-time-anchor' "$DASHCTL" ||
	fail 'dashboard still writes the state file directly'
grep -Fq 'MIN_WRITE_ADVANCE="${SMARTAP_TIME_ANCHOR_MIN_WRITE_ADVANCE:-21600}"' "$HELPER" ||
	fail 'six-hour flash-write coalescing policy is missing'
grep -Fq 'IMAGE_FILE="${SMARTAP_TIME_ANCHOR_IMAGE_FILE:-/rom/etc/smartap-time-anchor}"' "$HELPER" ||
	fail 'immutable image anchor is missing'
grep -Fq 'flock -xn 9' "$HELPER" || fail 'time anchor writers lack an exclusive kernel lock'
grep -Fq 'refusing to replace a newer persistent time floor' "$HELPER" ||
	fail 'locked write path lacks its final state rollback guard'
grep -Fq 'refusing authenticated time rollback below the current clock' "$HELPER" ||
	fail 'authenticated set path lacks current-clock rollback protection'
grep -Fq '[ "${BUILD_EPOCH}" -le 2145916800 ]' "$BUILD" ||
	fail 'build-time epoch range exceeds the runtime-safe maximum'

printf 'time_anchor_runtime_tests=pass\n'
