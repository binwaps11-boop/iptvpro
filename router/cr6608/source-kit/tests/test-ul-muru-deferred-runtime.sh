#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/etc/rc.d/S97cr6608-ul-muru-reconcile"

fail() {
	printf 'ul_muru_deferred_runtime=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] && [ ! -L "$SOURCE" ] && [ -x "$SOURCE" ] ||
	fail 'late-boot reconciler is absent, linked, or not executable'
sh -n "$SOURCE" || fail 'late-boot reconciler syntax failed'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ul-deferred.XXXXXX")" || exit 1
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
BIN="$TMP/bin"
mkdir -p "$BIN"

cat >"$BIN/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
[ "${1:-}" = get ] || exit 1
case "${2:-}" in
	smartap.experimental.ul_muru_guard) printf '%s\n' "$CR6608_TEST_GUARD_POLICY" ;;
	smartap.experimental.ul_muru_reconcile) printf '%s\n' "$CR6608_TEST_RECONCILE" ;;
	*) exit 1 ;;
esac
SH
cat >"$BIN/guard-init" <<'SH'
#!/bin/sh
case "${1:-}" in
	running) [ "$CR6608_TEST_RUNNING" = 1 ] ;;
	start)
		[ "$CR6608_TEST_FAIL_START" != 1 ] || exit 1
		printf 'start\n' >>"$CR6608_TEST_ACTIONS"
		;;
	*) exit 1 ;;
esac
SH
chmod 0755 "$BIN/uci" "$BIN/guard-init"

run_reconciler() {
	guard_policy="$1"
	reconcile="$2"
	running="$3"
	fail_start="$4"
	: >"$TMP/actions"
	set +e
	CR6608_TEST_GUARD_POLICY="$guard_policy" \
	CR6608_TEST_RECONCILE="$reconcile" \
	CR6608_TEST_RUNNING="$running" \
	CR6608_TEST_FAIL_START="$fail_start" \
	CR6608_TEST_ACTIONS="$TMP/actions" \
	CR6608_UL_MURU_GUARD_INIT="$BIN/guard-init" \
	PATH="$BIN:$PATH" sh "$SOURCE" boot
	reconcile_rc=$?
	set -e
}

run_reconciler 0 0 0 0
[ "$reconcile_rc" -eq 0 ] && [ ! -s "$TMP/actions" ] ||
	fail 'stable retail policy without a pending pass started the guard'

run_reconciler 0 1 0 0
[ "$reconcile_rc" -eq 0 ] || fail 'pending retail reconciliation failed'
grep -Fqx start "$TMP/actions" || fail 'pending retail reconciliation did not start the guard'

run_reconciler 1 0 0 0
[ "$reconcile_rc" -eq 0 ] || fail 'lab guard startup failed'
grep -Fqx start "$TMP/actions" || fail 'lab guard policy did not start the guard'

run_reconciler 1 0 1 0
[ "$reconcile_rc" -eq 0 ] && [ ! -s "$TMP/actions" ] ||
	fail 'already-running guard was started twice'

run_reconciler 0 1 0 1
[ "$reconcile_rc" -ne 0 ] || fail 'guard start failure was not propagated'

CR6608_TEST_GUARD_POLICY=1 CR6608_TEST_RECONCILE=0 \
CR6608_TEST_RUNNING=0 CR6608_TEST_FAIL_START=0 \
CR6608_TEST_ACTIONS="$TMP/actions" \
CR6608_UL_MURU_GUARD_INIT="$BIN/guard-init" \
PATH="$BIN:$PATH" sh "$SOURCE" stop || fail 'non-boot invocation returned failure'

printf 'ul_muru_deferred_runtime=pass\n'
