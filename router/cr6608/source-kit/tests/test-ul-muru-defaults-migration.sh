#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/etc/uci-defaults/98-cr6608-ul-muru-guard"

fail() {
	printf 'ul_muru_defaults_migration=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] && [ ! -L "$SOURCE" ] || fail 'migration source is missing or linked'
sh -n "$SOURCE" || fail 'migration source syntax failed'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ul-defaults.XXXXXX")" || exit 1
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
BIN="$TMP/bin"
STORE="$TMP/store"
mkdir -p "$BIN" "$STORE"

cat >"$BIN/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
command="${1:-}"
[ "$#" -eq 0 ] || shift
key_file() {
	case "$1" in
		smartap.experimental) printf '%s/section\n' "$CR6608_TEST_STORE" ;;
		smartap.experimental.ul_muru) printf '%s/legacy\n' "$CR6608_TEST_STORE" ;;
		smartap.experimental.muru_mask) printf '%s/mask\n' "$CR6608_TEST_STORE" ;;
		smartap.experimental.ul_muru_state) printf '%s/state\n' "$CR6608_TEST_STORE" ;;
		smartap.experimental.ul_muru_reason) printf '%s/reason\n' "$CR6608_TEST_STORE" ;;
		smartap.experimental.ul_muru_guard) printf '%s/guard\n' "$CR6608_TEST_STORE" ;;
		smartap.experimental.ul_muru_reconcile) printf '%s/reconcile\n' "$CR6608_TEST_STORE" ;;
		*) return 1 ;;
	esac
}
case "$command" in
	get)
		file="$(key_file "${1:-}")" || exit 1
		[ -f "$file" ] || exit 1
		cat "$file"
		;;
	set)
		[ "${CR6608_TEST_FAIL_SET:-0}" != 1 ] || exit 1
		assignment="${1:-}"
		key="${assignment%%=*}"
		value="${assignment#*=}"
		file="$(key_file "$key")" || exit 1
		printf '%s\n' "$value" >"$file"
		;;
	commit)
		[ "${1:-}" = smartap ] || exit 1
		[ "${CR6608_TEST_FAIL_COMMIT:-0}" != 1 ] || exit 1
		printf 'commit\n' >>"$CR6608_TEST_STORE/actions"
		;;
	*) exit 1 ;;
esac
SH

cat >"$BIN/guard" <<'SH'
#!/bin/sh
case "${1:-}" in
	enable)
		[ "${CR6608_TEST_FAIL_ENABLE:-0}" != 1 ] || exit 1
		printf 'enable\n' >>"$CR6608_TEST_STORE/actions"
		;;
	disable)
		[ "${CR6608_TEST_FAIL_DISABLE:-0}" != 1 ] || exit 1
		printf 'disable\n' >>"$CR6608_TEST_STORE/actions"
		;;
	*) exit 1 ;;
esac
SH
chmod 0755 "$BIN/uci" "$BIN/guard"

MIGRATION="$TMP/migration"
sed -e "s#/etc/init.d/cr6608-ul-muru-guard#$BIN/guard#g" "$SOURCE" >"$MIGRATION"
chmod 0755 "$MIGRATION"

write_profile() {
	case "$1" in
		lab)
			printf '%s\n' 'profile=lab-operator-v1' 'sale_ready=NO' \
				'radio_policy=lab-operator-38dbm-ul-muru' >"$TMP/profile" ;;
		retail)
			printf '%s\n' 'profile=retail-v1' 'sale_ready=NO' \
				'radio_policy=retail-disabled' >"$TMP/profile" ;;
		ul)
			printf '%s\n' 'profile=ul-muru-ram-v1' 'sale_ready=NO' \
				'radio_policy=ul-muru-ram-qualification' >"$TMP/profile" ;;
		forced)
			printf '%s\n' 'profile=ul-muru-forced-lab-v1' 'sale_ready=NO' \
				'radio_policy=ul-muru-persistent-mask15-38dbm-lab' >"$TMP/profile" ;;
		unknown) printf '%s\n' 'profile=forged' 'sale_ready=YES' >"$TMP/profile" ;;
	esac
}

prepare_case() {
	profile="$1" state="$2" guard="$3" module_line="$4"
	rm -rf -- "$STORE"
	mkdir -p "$STORE"
	write_profile "$profile"
	printf 'experimental\n' >"$STORE/section"
	[ "$state" = missing ] || printf '%s\n' "$state" >"$STORE/state"
	[ "$guard" = missing ] || printf '%s\n' "$guard" >"$STORE/guard"
	printf '0\n' >"$STORE/reconcile"
	: >"$STORE/actions"
	case "$module_line" in
		old) printf 'mt7915e cr6608_rf_38dbm=1\n' >"$TMP/module-file" ;;
		on) printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=1 cr6608_muru_mask=15\n' >"$TMP/module-file" ;;
		ul) printf 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=15\n' >"$TMP/module-file" ;;
		forced) printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=15\n' >"$TMP/module-file" ;;
		off) printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=0\n' >"$TMP/module-file" ;;
	esac
}

run_case() {
	CR6608_TEST_STORE="$STORE" \
	CR6608_UL_MURU_ARTIFACT_PROFILE="$TMP/profile" \
	CR6608_UL_MURU_MODULE_FILE="$TMP/module-file" \
	PATH="$BIN:$PATH" sh "$MIGRATION"
}

prepare_case retail retail-disabled 1 on
run_case
[ "$(cat "$STORE/legacy")" = 0 ] || fail 'retail migration enabled legacy MURU'
[ "$(cat "$STORE/mask")" = 0 ] || fail 'retail migration enabled the bitmap'
[ "$(cat "$STORE/guard")" = 0 ] || fail 'retail migration left the guard armed'
[ "$(cat "$STORE/reconcile")" = 1 ] || fail 'retail migration omitted reconciliation'
[ "$(cat "$TMP/module-file")" = \
	'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0' ] ||
	fail 'retail module policy is not the exact fail-closed line'
grep -Fqx disable "$STORE/actions" || fail 'retail migration left its service link enabled'

prepare_case lab missing missing old
rm -f -- "$STORE/section"
run_case
[ "$(cat "$STORE/section")" = experimental ] || fail 'clean LAB migration did not create the UCI section'
[ "$(cat "$STORE/legacy")" = 0 ] || fail 'clean LAB migration enabled legacy MURU'
[ "$(cat "$STORE/mask")" = 0 ] || fail 'clean LAB migration enabled the bitmap'
[ "$(cat "$STORE/state")" = disabled-upstream-hang-risk ] || fail 'clean LAB state is unsafe'
[ "$(cat "$STORE/guard")" = 1 ] || fail 'clean LAB watchdog was not enabled'
grep -Fq 'cr6608_ul_muru=0 cr6608_muru_mask=0' "$TMP/module-file" ||
	fail 'legacy LAB module line was not migrated to both zero tokens'
grep -Fqx enable "$STORE/actions" || fail 'clean LAB watchdog service was not enabled'

prepare_case ul missing missing ul
run_case
[ "$(cat "$STORE/legacy")" = 0 ] || fail 'UL RAM profile enabled the legacy bool'
[ "$(cat "$STORE/mask")" = 15 ] || fail 'UL RAM profile did not request bitmap 15'
[ "$(cat "$STORE/guard")" = 1 ] || fail 'UL RAM profile did not arm the guard policy'
[ "$(cat "$STORE/state")" = qualification-requested ] || fail 'UL RAM profile state is wrong'
[ "$(cat "$TMP/module-file")" = \
	'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=15' ] ||
	fail 'UL RAM module policy is not mask 15 with legacy off'
grep -Fqx enable "$STORE/actions" || fail 'UL RAM guard service was not enabled'

prepare_case forced missing missing forced
run_case
[ "$(cat "$STORE/legacy")" = 0 ] || fail 'forced LAB profile enabled the legacy bool'
[ "$(cat "$STORE/mask")" = 15 ] || fail 'forced LAB profile did not request bitmap 15'
[ "$(cat "$STORE/guard")" = 1 ] || fail 'forced LAB profile did not arm the guard policy'
[ "$(cat "$STORE/state")" = qualification-requested ] || fail 'forced LAB profile state is wrong'
[ "$(cat "$STORE/reason")" = forced-persistent-lab-profile ] || fail 'forced LAB reason is wrong'
[ "$(cat "$TMP/module-file")" = \
	'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=15' ] ||
	fail 'forced LAB module policy is not the exact mask 15 and 38 dBm request line'
grep -Fqx enable "$STORE/actions" || fail 'forced LAB guard service was not enabled'

prepare_case ul disabled-by-guard 0 ul
run_case
[ "$(cat "$STORE/mask")" = 0 ] || fail 'prior fault was silently re-armed by UL RAM defaults'
[ "$(cat "$STORE/state")" = disabled-by-guard ] || fail 'prior fault state was overwritten'
[ "$(cat "$STORE/guard")" = 0 ] || fail 'prior fault left the guard policy armed'
grep -Fq 'cr6608_ul_muru=0 cr6608_muru_mask=0' "$TMP/module-file" ||
	fail 'prior fault did not zero both next-boot tokens'
grep -Fqx disable "$STORE/actions" || fail 'prior fault did not disable the next-boot service link'

prepare_case unknown missing missing on
run_case
[ "$(cat "$STORE/mask")" = 0 ] || fail 'unknown profile enabled a MURU bit'
[ "$(cat "$STORE/state")" = retail-disabled ] || fail 'unknown profile was not treated fail-closed'
[ "$(cat "$TMP/module-file")" = \
	'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0' ] ||
	fail 'unknown profile did not receive the exact retail-safe line'

expect_failure() {
	name="$1" profile="$2" state="$3" guard="$4" module="$5"
	shift 5
	prepare_case "$profile" "$state" "$guard" "$module"
	if CR6608_TEST_STORE="$STORE" \
		CR6608_UL_MURU_ARTIFACT_PROFILE="$TMP/profile" \
		CR6608_UL_MURU_MODULE_FILE="$TMP/module-file" \
		PATH="$BIN:$PATH" "$@" sh "$MIGRATION" >"$TMP/$name.out" 2>&1; then
		fail "$name unexpectedly returned success"
	fi
}

expect_failure set-failure retail retail-disabled 0 off env CR6608_TEST_FAIL_SET=1
expect_failure commit-failure retail retail-disabled 0 off env CR6608_TEST_FAIL_COMMIT=1
expect_failure disable-failure retail retail-disabled 0 off env CR6608_TEST_FAIL_DISABLE=1
expect_failure enable-failure ul missing missing ul env CR6608_TEST_FAIL_ENABLE=1

printf 'ul_muru_defaults_migration=pass\n'
