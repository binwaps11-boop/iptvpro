#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="$ROOT/files/usr/libexec/cr6608-private-runtime"
DASHCTL="$ROOT/files/www/cgi-bin/dashctl"

fail() {
	printf 'private_runtime_contract=fail: %s\n' "$*" >&2
	exit 1
}

[ -s "$HELPER" ] || fail "private runtime helper missing"
[ -s "$DASHCTL" ] || fail "dashctl missing"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-private-runtime.XXXXXX")" || exit 1
cleanup() {
	trap - EXIT HUP INT TERM
	chmod -R u+rwX "$TMP" 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM
chmod 0700 "$TMP"

export CR6608_PRIVATE_EXPECTED_UID="$(id -u)"
CR6608_PRIVATE_RUNTIME_ROOT="$TMP/runtime"
export CR6608_PRIVATE_RUNTIME_ROOT

# MSYS exposes NTFS objects as 0755/0644 even after chmod.  Model the exact
# Unix metadata contract there; Linux and target runs continue to exercise the
# real stat command and real permission bits.
MOCK_STAT_DB=''
case "$(uname -s 2>/dev/null || printf unknown)" in
	MINGW*|MSYS*|CYGWIN*)
		MOCK_STAT_DB="$TMP/mock-stat.db"
		: >"$MOCK_STAT_DB"
		export MOCK_STAT_DB
		MOCK_STAT="$TMP/mock-stat"
		cat >"$MOCK_STAT" <<'EOF_MOCK_STAT'
#!/bin/sh
set -eu
[ "${1:-}" = -c ] && [ "$#" = 3 ] || exit 2
format="$2"
path="$3"
[ -e "$path" ] || [ -L "$path" ] || exit 1
mode=''
links=1
while IFS='	' read -r recorded_path recorded_mode recorded_links; do
	[ "$recorded_path" = "$path" ] || continue
	mode="$recorded_mode"
	links="${recorded_links:-1}"
done <"$MOCK_STAT_DB"
if [ -z "$mode" ]; then
	if [ -d "$path" ] && [ ! -L "$path" ]; then
		mode=700
	else
		mode=600
	fi
fi
case "$format" in
	'%u:%a') printf '%s:%s\n' "$CR6608_PRIVATE_EXPECTED_UID" "$mode" ;;
	'%u:%a:%h') printf '%s:%s:%s\n' "$CR6608_PRIVATE_EXPECTED_UID" "$mode" "$links" ;;
	*) exit 2 ;;
esac
EOF_MOCK_STAT
		chmod 0700 "$MOCK_STAT"
		CR6608_PRIVATE_STAT_BIN="$MOCK_STAT"
		export CR6608_PRIVATE_STAT_BIN
		;;
esac

mock_stat_mode() {
	[ -n "$MOCK_STAT_DB" ] || return 0
	printf '%s\t%s\t%s\n' "$1" "$2" "${3:-1}" >>"$MOCK_STAT_DB"
}

# shellcheck disable=SC1090
. "$HELPER"

runtime_root="$(cr6608_private_runtime_root)" || fail "secure root creation"
[ "$runtime_root" = "$TMP/runtime" ] || fail "runtime root changed"
component="$(cr6608_private_runtime_dir dashctl)" || fail "secure component creation"
[ "$(cr6608_private_stat -c '%u:%a' "$component")" = "$CR6608_PRIVATE_EXPECTED_UID:700" ] || \
	fail "component owner/mode"
temporary="$(cr6608_private_mktemp "$component" action)" || fail "private mktemp"
printf 'private-data\n' >"$temporary"
target="$component/result"
cr6608_private_publish_file "$temporary" "$target" || fail "atomic publish"
[ "$(cr6608_private_stat -c '%u:%a:%h' "$target")" = "$CR6608_PRIVATE_EXPECTED_UID:600:1" ] || \
	fail "published file owner/mode/link count"

sentinel="$TMP/sentinel"
printf 'DO-NOT-TOUCH\n' >"$sentinel"
ln -s "$sentinel" "$component/status"
temporary="$(cr6608_private_mktemp "$component" status-new)" || fail "status mktemp"
printf 'state=active\n' >"$temporary"
cr6608_private_publish_file "$temporary" "$component/status" || \
	fail "safe replacement of preplanted target symlink"
[ "$(cat "$sentinel")" = DO-NOT-TOUCH ] || fail "target symlink clobbered sentinel"
[ -f "$component/status" ] && [ ! -L "$component/status" ] || \
	fail "target symlink was not atomically replaced"

rm -rf "$CR6608_PRIVATE_RUNTIME_ROOT"
ln -s "$sentinel" "$CR6608_PRIVATE_RUNTIME_ROOT"
if cr6608_private_runtime_root >/dev/null 2>&1; then
	fail "preplanted runtime-root symlink accepted"
fi
[ "$(cat "$sentinel")" = DO-NOT-TOUCH ] || fail "runtime-root symlink clobbered sentinel"
rm "$CR6608_PRIVATE_RUNTIME_ROOT"
mkdir -m 0700 "$CR6608_PRIVATE_RUNTIME_ROOT" 2>/dev/null ||
	{ [ -n "$MOCK_STAT_DB" ] && [ -d "$CR6608_PRIVATE_RUNTIME_ROOT" ]; } ||
	fail "runtime-root fixture creation"
ln -s "$sentinel" "$CR6608_PRIVATE_RUNTIME_ROOT/neighbor"
if cr6608_private_runtime_dir neighbor >/dev/null 2>&1; then
	fail "preplanted component symlink accepted"
fi
rm "$CR6608_PRIVATE_RUNTIME_ROOT/neighbor"
mkdir -m 0777 "$CR6608_PRIVATE_RUNTIME_ROOT/neighbor" 2>/dev/null ||
	{ [ -n "$MOCK_STAT_DB" ] && [ -d "$CR6608_PRIVATE_RUNTIME_ROOT/neighbor" ]; } ||
	fail "attacker-directory fixture creation"
chmod 0777 "$CR6608_PRIVATE_RUNTIME_ROOT/neighbor" 2>/dev/null ||
	[ -n "$MOCK_STAT_DB" ] || fail "attacker-directory fixture mode"
mock_stat_mode "$CR6608_PRIVATE_RUNTIME_ROOT/neighbor" 777
if cr6608_private_runtime_dir neighbor >/dev/null 2>&1; then
	fail "attacker-writable component directory accepted"
fi

for invalid_component in . .. '../escape' 'bad/name' 'line
break'; do
	if cr6608_private_component_valid "$invalid_component"; then
		fail "invalid component accepted: $invalid_component"
	fi
done

for invalid_root in "$TMP/.." "$TMP/." "$TMP/runtime/" "$TMP//runtime" relative; do
	CR6608_PRIVATE_RUNTIME_ROOT="$invalid_root"
	export CR6608_PRIVATE_RUNTIME_ROOT
	if cr6608_private_runtime_root >/dev/null 2>&1; then
		fail "ambiguous/non-absolute runtime root accepted: $invalid_root"
	fi
done

group_parent="$TMP/group-parent"
mkdir -m 0770 "$group_parent" 2>/dev/null ||
	{ [ -n "$MOCK_STAT_DB" ] && [ -d "$group_parent" ]; } ||
	fail "group-parent fixture creation"
chmod 0770 "$group_parent" 2>/dev/null ||
	[ -n "$MOCK_STAT_DB" ] || fail "group-parent fixture mode"
mock_stat_mode "$group_parent" 770
CR6608_PRIVATE_RUNTIME_ROOT="$group_parent/runtime"
export CR6608_PRIVATE_RUNTIME_ROOT
if cr6608_private_runtime_root >/dev/null 2>&1; then
	fail "group-writable runtime parent accepted"
fi

for legacy_writer in /tmp/dashctl.action /tmp/smartap.cron '/tmp/lanscan.$$'; do
	! grep -Fq "$legacy_writer" "$DASHCTL" || fail "legacy predictable writer remains: $legacy_writer"
done
grep -Fq "PRIVATE_RUNTIME_LIB='/usr/libexec/cr6608-private-runtime'" "$DASHCTL" || \
	fail "dashctl does not require the private runtime helper"
grep -Fq 'ACTION_LOG="$(cr6608_private_mktemp' "$DASHCTL" || \
	fail "dashctl action log is not private/random"
grep -Fq 'cron_file="$DASHCTL_REQUEST_DIR/scheduled-reboot.cron"' "$DASHCTL" || \
	fail "crontab handoff is not inside the random request directory"
grep -Fq 'st="$DASHCTL_REQUEST_DIR/lanscan"' "$DASHCTL" || \
	fail "LAN scan does not use request-private state"
[ "$(grep -Fc 'trap dashctl_exit_cleanup EXIT' "$DASHCTL")" -ge 2 ] || \
	fail "action setup replaces the composite EXIT cleanup"
signal_block="$(sed -n '/^apply_signal_exit() {$/,/^}$/p' "$DASHCTL")"
printf '%s\n' "$signal_block" | grep -Fq 'release_apply_lock' && \
	printf '%s\n' "$signal_block" | grep -Fq 'dashctl_private_cleanup' || \
	fail "signal path does not release lock and request-private files"

printf 'private_runtime_contract=pass\n'
