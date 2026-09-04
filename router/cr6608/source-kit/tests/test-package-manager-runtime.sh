#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/www/cgi-bin/dashctl"
SEED="$ROOT/cr6608.seed.config"

fail() {
	printf 'package_manager_runtime=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "missing $SOURCE"
[ -f "$SEED" ] || fail "missing $SEED"
for guarded_luci_component in luci-light libustream-mbedtls px5g-mbedtls; do
	grep -Fqx "CONFIG_PACKAGE_${guarded_luci_component}=y" "$SEED" || \
		fail "seed lacks explicit guarded LuCI component $guarded_luci_component"
done
for forbidden_luci_meta in luci luci-ssl luci-app-package-manager; do
	grep -Fqx "# CONFIG_PACKAGE_${forbidden_luci_meta} is not set" "$SEED" || \
		fail "seed can reselect unguarded LuCI package surface: $forbidden_luci_meta"
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-package-manager.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
HELPERS="$TMP/package-manager.sh"
awk '
	/^package_manager_detect\(\)/ { copy=1 }
	/^# libubus has its own two-second deadline/ { exit }
	copy { print }
' "$SOURCE" >"$HELPERS"
grep -q '^package_manager_run()' "$HELPERS" || fail "could not extract package-manager helpers"

CALLS="$TMP/calls"
export CALLS
run_limit() {
	_timeout="$1"
	shift
	"$@"
}

# shellcheck disable=SC1090
. "$HELPERS"

mkdir "$TMP/bin"
make_mock() {
	_name="$1"
	cat >"$TMP/bin/$_name" <<'SH'
#!/bin/sh
printf '%s' "$0" >>"$CALLS"
for arg in "$@"; do printf '|%s' "$arg" >>"$CALLS"; done
printf '\n' >>"$CALLS"
exit "${PM_MOCK_RC:-0}"
SH
	chmod 0700 "$TMP/bin/$_name"
}
make_mock apk
make_mock opkg
PATH="$TMP/bin:/usr/bin:/bin"
export PATH

assert_mutations_denied() {
	_manager="$1"
	for _action in install remove; do
		for _spec in safe-addon delivered-helper luci-app-sqm kmod-video-core \
			base-files=2026.08 -u --allow-untrusted --force-overwrite \
			'bad package' '../base-files' 'name==1'; do
			: >"$CALLS"
			set +e
			package_manager_run "$_action" "$_spec" >/dev/null 2>&1
			_denied_rc=$?
			set -e
			[ "$_denied_rc" -eq 126 ] || \
				fail "$_manager $_action $_spec returned $_denied_rc instead of rc 126"
			[ ! -s "$CALLS" ] || \
				fail "$_manager executed for disabled $_action $_spec"
		done
	done
}

[ "$(package_manager_detect)" = apk ] || fail "apk was not preferred"
assert_mutations_denied apk
: >"$CALLS"
package_manager_run update
grep -Fqx "$TMP/bin/apk|update" "$CALLS" || fail "apk refresh translation is wrong"

PM_MOCK_RC=23
export PM_MOCK_RC
set +e
package_manager_run update >/dev/null 2>&1
failure_rc=$?
set -e
[ "$failure_rc" -eq 23 ] || fail "manager refresh failure changed to $failure_rc"
unset PM_MOCK_RC

rm "$TMP/bin/apk"
[ "$(package_manager_detect)" = opkg ] || fail "opkg fallback was not selected"
assert_mutations_denied opkg
: >"$CALLS"
package_manager_run update
grep -Fqx "$TMP/bin/opkg|update" "$CALLS" || fail "opkg refresh translation is wrong"

run_block="$TMP/package-manager-run.sh"
sed -n '/^package_manager_run() {$/,/^}$/p' "$SOURCE" >"$run_block"
deny_line="$(grep -n -m1 'installation and removal are disabled' "$run_block" | cut -d: -f1)"
detect_line="$(grep -n -m1 'package_manager_detect' "$run_block" | cut -d: -f1)"
[ -n "$deny_line" ] && [ -n "$detect_line" ] && [ "$deny_line" -lt "$detect_line" ] || \
	fail "mutation denial does not precede manager detection"
if grep -F 'actions=' "$SOURCE" | grep -Eq '"id":"opkg_(install|remove)"'; then
	fail "Software page advertises a retail package mutation action"
fi
! grep -Fq 'package_spec_is_valid()' "$SOURCE" && \
	! grep -Fq 'safe_package_spec()' "$SOURCE" || \
	fail "dead package-operand validation remains in refresh-only UI"
grep -F 'actions=' "$SOURCE" | grep -Fq '"id":"opkg_update"' || \
	fail "Software page lost read-only package refresh"

rm "$TMP/bin/opkg"
PATH="$TMP/bin"
export PATH
if package_manager_detect >/dev/null 2>&1; then fail "missing manager was reported as available"; fi
set +e
package_manager_run update >/dev/null 2>&1
missing_rc=$?
set -e
[ "$missing_rc" -eq 127 ] || fail "missing manager returned $missing_rc instead of 127"

PATH=/usr/bin:/bin
export PATH
printf 'package_manager_runtime=pass\n'
