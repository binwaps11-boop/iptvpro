#!/bin/sh
set -eu

stage_script="${1:?usage: test_stage_guards.sh STAGE_SCRIPT}"
test_dir="/tmp/cr6608-stage-guard-test.$$"
mkdir "$test_dir"
functions_file="$test_dir/functions.sh"
sed '/^case "${1:-}" in/,$d' "$stage_script" >"$functions_file"

cleanup_test() {
	rm -f "$test_dir"/*
	rmdir "$test_dir"
}
trap cleanup_test EXIT HUP INT TERM

run_apply_signal_test() {
	sh -c '
		. "$1"
		LOG="$2"
		MTD_DEV=/dev/null
		PERSISTENT_BLOCK0=/tmp/mock-original-block0
		STAGED_BLOCK=
		hash_file() { echo partial; }
		write_original_now() { echo restore >>"$LOG"; return 0; }
		remove_staged_block() { echo cleanup >>"$LOG"; }
		write_started=1
		candidate_committed=0
		trap apply_exit_guard EXIT
		trap "exit 129" HUP
		trap "exit 130" INT
		trap "exit 143" TERM
		kill -TERM $$
	' sh "$functions_file" "$test_dir/apply.log"
}

set +e
run_apply_signal_test
apply_rc=$?
set -e
[ "$apply_rc" -eq 143 ] || {
	echo "FAIL apply signal rc=$apply_rc" >&2
	exit 1
}
[ "$(grep -c '^restore$' "$test_dir/apply.log")" -eq 1 ] || {
	echo 'FAIL apply restore did not run exactly once' >&2
	exit 1
}
[ "$(grep -c '^cleanup$' "$test_dir/apply.log")" -eq 1 ] || {
	echo 'FAIL apply cleanup did not run exactly once' >&2
	exit 1
}

run_restore_signal_test() {
	sh -c '
		. "$1"
		LOG="$2"
		MTD_DEV=/dev/null
		RESTORE_SOURCE=/tmp/mock-original-block0
		STAGED_BLOCK=
		hash_file() { echo partial; }
		write_original_now() { echo restore >>"$LOG"; return 0; }
		remove_staged_block() { echo cleanup >>"$LOG"; }
		restore_started=1
		trap restore_exit_guard EXIT
		trap "exit 129" HUP
		trap "exit 130" INT
		trap "exit 143" TERM
		# Pipeline children may inherit SIGINT as ignored, and nohup children
		# inherit SIGHUP as ignored. POSIX does not allow an ignored signal to be
		# made trappable again. USR1 is independent of both terminal conditions
		# and still exercises the restore EXIT guard through a separate signal.
		trap "exit 138" USR1
		kill -USR1 $$
	' sh "$functions_file" "$test_dir/restore.log"
}

set +e
run_restore_signal_test
restore_rc=$?
set -e
[ "$restore_rc" -eq 138 ] || {
	echo "FAIL restore signal rc=$restore_rc" >&2
	exit 1
}
[ "$(grep -c '^restore$' "$test_dir/restore.log")" -eq 1 ] || {
	echo 'FAIL restore retry did not run exactly once' >&2
	exit 1
}
[ "$(grep -c '^cleanup$' "$test_dir/restore.log")" -eq 1 ] || {
	echo 'FAIL restore cleanup did not run exactly once' >&2
	exit 1
}

lock_file="$test_dir/transaction.lock"
lock_ready="$test_dir/transaction.ready"
flock "$lock_file" -c "printf 'ready\\n' >'$lock_ready'; sleep 5" &
lock_holder=$!
wait_loops=0
while [ ! -s "$lock_ready" ] && [ "$wait_loops" -lt 100 ]; do
	sleep 0.05
	wait_loops=$((wait_loops + 1))
done
[ -s "$lock_ready" ] || {
	echo 'FAIL concurrent lock holder did not become ready' >&2
	kill "$lock_holder" 2>/dev/null || true
	wait "$lock_holder" 2>/dev/null || true
	exit 1
}
set +e
(
	. "$functions_file"
	LOCK_FILE="$lock_file"
	acquire_lock
)
lock_rc=$?
set -e
wait "$lock_holder"
[ "$lock_rc" -eq 1 ] || {
	echo "FAIL concurrent lock rc=$lock_rc" >&2
	exit 1
}

echo 'STAGE_GUARD_TESTS=PASS'
