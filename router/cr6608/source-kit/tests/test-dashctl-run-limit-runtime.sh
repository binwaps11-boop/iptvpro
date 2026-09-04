#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/www/cgi-bin/dashctl"
PRIVATE_RUNTIME="$ROOT/files/usr/libexec/cr6608-private-runtime"

fail() {
	printf 'dashctl_run_limit_runtime=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "missing $SOURCE"
[ -f "$PRIVATE_RUNTIME" ] || fail "missing $PRIVATE_RUNTIME"
[ -x /usr/bin/setsid ] || fail "missing /usr/bin/setsid"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-run-limit-runtime.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

BLOCK="$TMP/run-limit.sh"
awk '
	/^close_dashboard_fds\(\)/ { copy=1 }
	/^# libubus has its own two-second deadline/ { exit }
	copy { print }
' "$SOURCE" >"$BLOCK"
grep -q '^run_limit()' "$BLOCK" || fail "could not extract run_limit"

# Production gives run_limit a random request directory below the root-only
# private runtime. Recreate that contract beneath this fixture's 0700 tmpdir;
# do not weaken dashctl with a test-only path override or fall back to /tmp.
CR6608_PRIVATE_RUNTIME_ROOT="$TMP/private-runtime"
CR6608_PRIVATE_EXPECTED_UID="$(id -u)"
export CR6608_PRIVATE_RUNTIME_ROOT CR6608_PRIVATE_EXPECTED_UID
# shellcheck disable=SC1090
. "$PRIVATE_RUNTIME"
DASHCTL_RUNTIME_DIR="$(cr6608_private_runtime_dir dashctl)" ||
	fail "could not prepare private dashctl runtime"
DASHCTL_REQUEST_DIR="$(mktemp -d "$DASHCTL_RUNTIME_DIR/request.XXXXXX")" ||
	fail "could not prepare private request directory"
chmod 0700 "$DASHCTL_REQUEST_DIR"
cr6608_private_dir_secure "$DASHCTL_REQUEST_DIR" ||
	fail "private request directory is not secure"
export DASHCTL_REQUEST_DIR
STATE_DIR="$DASHCTL_REQUEST_DIR"

# shellcheck disable=SC1090
. "$BLOCK"

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

runtime_files() {
	find /var/run -maxdepth 1 -type f \
		\( -name 'cr6608-dashcmd-out.*' -o -name 'cr6608-dashcmd-err.*' \) \
		-print 2>/dev/null | LC_ALL=C sort
}

runtime_files >"$TMP/var-run.before"

# The former one-second poll floor made twenty trivial commands take about
# twenty seconds. Keep enough headroom for a loaded VM and the intentional
# 100-ms grace while still detecting that regression.
fast_start="$(monotonic_ms)"
fast_i=0
while [ "$fast_i" -lt 20 ]; do
	run_limit 3 /bin/true >/dev/null 2>&1 ||
		fail "fast command $fast_i failed"
	fast_i=$((fast_i + 1))
done
fast_end="$(monotonic_ms)"
fast_elapsed=$((fast_end - fast_start))
fast_budget="${CR6608_RUN_LIMIT_FAST_BUDGET_MS:-6000}"
[ "$fast_elapsed" -le "$fast_budget" ] ||
	fail "20 fast commands took ${fast_elapsed}ms (budget ${fast_budget}ms)"

cat >"$TMP/result-command.sh" <<'SH'
#!/bin/sh
printf 'stdout-preserved\n'
printf 'stderr-preserved\n' >&2
exit 37
SH
chmod 0700 "$TMP/result-command.sh"
set +e
run_limit 3 "$TMP/result-command.sh" >"$TMP/result.out" 2>"$TMP/result.err"
result_rc=$?
set -e
[ "$result_rc" -eq 37 ] || fail "exit code changed from 37 to $result_rc"
[ "$(cat "$TMP/result.out")" = stdout-preserved ] || fail "stdout was not preserved"
[ "$(cat "$TMP/result.err")" = stderr-preserved ] || fail "stderr was not preserved"

cat >"$TMP/stdin-command.sh" <<'SH'
#!/bin/sh
stdin_target="$(readlink "/proc/$$/fd/0" 2>/dev/null || true)"
printf 'stdin=%s\n' "$stdin_target"
if IFS= read -r unexpected; then
	printf 'unexpected-input=%s\n' "$unexpected"
	exit 41
fi
printf 'stdin-eof=yes\n'
SH
chmod 0700 "$TMP/stdin-command.sh"
set +e
printf 'cgi-request-body-must-not-leak\n' |
	run_limit 3 "$TMP/stdin-command.sh" >"$TMP/stdin.out" 2>"$TMP/stdin.err"
stdin_rc=$?
set -e
[ "$stdin_rc" -eq 0 ] || fail "stdin probe returned $stdin_rc"
grep -Fqx 'stdin=/dev/null' "$TMP/stdin.out" || fail "child stdin was not /dev/null"
grep -Fqx 'stdin-eof=yes' "$TMP/stdin.out" || fail "child could read CGI input"
! grep -q '^unexpected-input=' "$TMP/stdin.out" || fail "CGI input leaked to child"

cat >"$TMP/stubborn-command.sh" <<'SH'
#!/bin/sh
trap '' HUP INT TERM
printf '%s\n' "$$" >"$CR6608_TEST_PARENT_PID"
(
	trap '' HUP INT TERM
	while :; do sleep 1; done
) &
stubborn_child=$!
# A subshell's $$ is not distinct on every POSIX shell, so record the actual
# asynchronous PID supplied by the parent shell.
printf '%s\n' "$stubborn_child" >"$CR6608_TEST_CHILD_PID"
wait "$stubborn_child"
SH
chmod 0700 "$TMP/stubborn-command.sh"
CR6608_TEST_PARENT_PID="$TMP/stubborn-parent.pid"
CR6608_TEST_CHILD_PID="$TMP/stubborn-child.pid"
export CR6608_TEST_PARENT_PID CR6608_TEST_CHILD_PID
timeout_start="$(monotonic_ms)"
set +e
# Keep the test runner outside the process group being exercised. If a broken
# group calculation signals the run_limit caller, setsid reports 137/143 here
# and the test can diagnose it instead of disappearing with the target.
/usr/bin/setsid /bin/sh -c '
	. "$1"
	. "$2"
	run_limit 1 "$3"
' cr6608-run-limit-test "$PRIVATE_RUNTIME" "$BLOCK" "$TMP/stubborn-command.sh" \
	>"$TMP/timeout.out" 2>"$TMP/timeout.err"
timeout_rc=$?
set -e
timeout_end="$(monotonic_ms)"
timeout_elapsed=$((timeout_end - timeout_start))
if [ "$timeout_rc" -ne 124 ]; then
	[ "$timeout_rc" -ne 143 ] ||
		printf '%s\n' 'process-group TERM reached the caller; external kill requires -- before a negative PID' >&2
	fail "timeout returned $timeout_rc instead of 124"
fi
[ "$timeout_elapsed" -ge 900 ] || fail "timeout fired too early (${timeout_elapsed}ms)"
[ "$timeout_elapsed" -le 6000 ] || fail "timeout did not remain bounded (${timeout_elapsed}ms)"

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

runtime_files >"$TMP/var-run.after"
cmp -s "$TMP/var-run.before" "$TMP/var-run.after" || {
	printf '%s\n' 'new /var/run command files:' >&2
	comm -13 "$TMP/var-run.before" "$TMP/var-run.after" >&2 || true
	fail "/var/run command files leaked"
}

if find "$STATE_DIR" -maxdepth 1 -type f \
	\( -name 'command-out.*' -o -name 'command-err.*' -o \
	   -name 'cr6608-dashcmd-out.*' -o -name 'cr6608-dashcmd-err.*' \) \
	-print -quit 2>/dev/null | grep -q .; then
	fail "command files leaked in $STATE_DIR"
fi

printf 'dashctl_run_limit_runtime=pass fast_ms=%s timeout_ms=%s state_dir=%s\n' \
	"$fast_elapsed" "$timeout_elapsed" "$STATE_DIR"
