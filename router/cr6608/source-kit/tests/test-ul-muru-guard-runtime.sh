#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GUARD="$ROOT/files/usr/sbin/cr6608-ul-muru-guard"

fail() {
	printf 'ul_muru_guard_runtime=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$GUARD" ] && [ ! -L "$GUARD" ] && [ -x "$GUARD" ] ||
	fail 'guard is absent, linked, or not executable'
sh -n "$GUARD" || fail 'guard syntax failed'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ul-guard.XXXXXX")" || exit 1
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
BIN="$TMP/bin"
DEBUG="$TMP/debug"
RUNTIME="$TMP/runtime"
mkdir -p "$BIN" "$DEBUG/phy0/mt76" "$DEBUG/phy1/mt76" "$RUNTIME"

cat >"$TMP/private-runtime" <<'SH'
cr6608_private_runtime_dir() {
	mkdir -p "$CR6608_TEST_ROOT/runtime"
	printf '%s\n' "$CR6608_TEST_ROOT/runtime"
}
cr6608_private_mktemp() { mktemp "$1/$2.XXXXXX"; }
cr6608_private_publish_file() { mv -f -- "$1" "$2"; }
SH

cat >"$BIN/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
command="${1:-}"
[ "$#" -eq 0 ] || shift
key_file() {
	case "$1" in
		smartap.experimental.ul_muru) printf '%s/uci-legacy\n' "$CR6608_TEST_ROOT" ;;
		smartap.experimental.muru_mask) printf '%s/uci-mask\n' "$CR6608_TEST_ROOT" ;;
		smartap.experimental.ul_muru_guard) printf '%s/uci-guard\n' "$CR6608_TEST_ROOT" ;;
		smartap.experimental.ul_muru_state) printf '%s/uci-state\n' "$CR6608_TEST_ROOT" ;;
		smartap.experimental.ul_muru_reason) printf '%s/uci-reason\n' "$CR6608_TEST_ROOT" ;;
		smartap.experimental.ul_muru_reconcile) printf '%s/uci-reconcile\n' "$CR6608_TEST_ROOT" ;;
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
		assignment="${1:-}"
		key="${assignment%%=*}"
		value="${assignment#*=}"
		file="$(key_file "$key")" || exit 1
		printf '%s\n' "$value" >"$file"
		;;
	commit) [ "${1:-}" = smartap ] ;;
	*) exit 1 ;;
esac
SH

cat >"$BIN/logger" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$BIN/logread" <<'SH'
#!/bin/sh
cat "$CR6608_TEST_ROOT/logread.log" 2>/dev/null || true
SH
cat >"$BIN/sync" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$BIN/sleep" <<'SH'
#!/bin/sh
[ "${1:-}" = 3600 ] || exec /bin/sleep "$@"
if [ ! -e "$CR6608_TEST_ROOT/rotation-done" ]; then
	case "${MOCK_SLEEP_MODE:-idle}" in
		rotate-same)
			head -n 1 "$CR6608_TEST_ROOT/logread.log" \
				>"$CR6608_TEST_ROOT/logread.next"
			printf '%s\n' \
				'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aef timeout' \
				>>"$CR6608_TEST_ROOT/logread.next"
			tail -n 1 "$CR6608_TEST_ROOT/logread.log" \
				>>"$CR6608_TEST_ROOT/logread.next"
			;;
		decrease)
			tail -n +2 "$CR6608_TEST_ROOT/logread.log" \
				>"$CR6608_TEST_ROOT/logread.next"
			;;
		decrease-new)
			tail -n 1 "$CR6608_TEST_ROOT/logread.log" \
				>"$CR6608_TEST_ROOT/logread.next"
			printf '%s\n' \
				'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aef timeout' \
				>>"$CR6608_TEST_ROOT/logread.next"
			;;
		*) exit 1 ;;
	esac
	mv -f "$CR6608_TEST_ROOT/logread.next" \
		"$CR6608_TEST_ROOT/logread.log"
	: >"$CR6608_TEST_ROOT/rotation-done"
	exit 0
fi
exit 1
SH
cat >"$BIN/reboot" <<'SH'
#!/bin/sh
printf 'reboot-requested\n' >>"$CR6608_TEST_ROOT/reboot.log"
exit 0
SH
cat >"$BIN/guard-init" <<'SH'
#!/bin/sh
[ "${1:-}" = disable ] || exit 1
[ "$(cat "$CR6608_TEST_ROOT/fail-disable" 2>/dev/null || printf 0)" != 1 ] || exit 1
printf 'disable\n' >>"$CR6608_TEST_ROOT/init-actions"
SH
chmod 0755 "$BIN/uci" "$BIN/logger" "$BIN/logread" "$BIN/sync" \
	"$BIN/sleep" "$BIN/reboot" "$BIN/guard-init"

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
		unknown) printf 'profile=unknown\n' >"$TMP/profile" ;;
	esac
}

write_driver_state() {
	mask="$1" allowed="$2" fault="$3" latches="$4"
	attempted="$5" response_ok="$6" failed="$7" timeout="$8"
	if [ "$mask" = 15 ]; then enabled=1; bit=1; else enabled=0; bit=0; fi
	for phy in phy0 phy1; do
		printf '%s\n' \
			"candidate_allowed=$allowed" "candidate_ul_enabled=$enabled" \
			"candidate_mask=$mask" "candidate_dl_ofdma=$bit" \
			"candidate_ul_ofdma=$bit" "candidate_dl_mumimo=$bit" \
			"candidate_ul_mumimo=$bit" \
			"fault_latched=$fault" "fault_latches=$latches" \
			'policy=mediatek-25.12-mu-onoff-sta-rec-port' \
			"sta_rec_attempted=$attempted" "sta_rec_response_ok=$response_ok" \
			"sta_rec_failed=$failed" "sta_rec_timeout=$timeout" \
			'he_sta_rec_updates=0' 'mimo_capable_updates=0' \
			>"$DEBUG/$phy/mt76/cr6608_ul_muru_state"
	done
}

prepare_common() {
	profile="$1" runtime_mask="$2" uci_mask="$3" debug_mask="$4"
	module_mask="$5" guard_policy="$6" policy_state="$7"
	write_profile "$profile"
	printf 'N\n' >"$TMP/legacy-param"
	printf '%s\n' "$runtime_mask" >"$TMP/mask-param"
	printf '0\n' >"$TMP/uci-legacy"
	printf '%s\n' "$uci_mask" >"$TMP/uci-mask"
	printf '%s\n' "$guard_policy" >"$TMP/uci-guard"
	printf '%s\n' "$policy_state" >"$TMP/uci-state"
	printf 'test\n' >"$TMP/uci-reason"
	printf '0\n' >"$TMP/uci-reconcile"
	printf '0\n' >"$TMP/fail-disable"
	legacy_gate=0
	[ "$debug_mask" = 15 ] && legacy_gate=1
	for phy in phy0 phy1; do
		printf '%s\n' "$debug_mask" >"$DEBUG/$phy/mt76/cr6608_muru_mask"
		printf '%s\n' "$legacy_gate" >"$DEBUG/$phy/mt76/cr6608_ul_muru"
		printf '0\n' >"$DEBUG/$phy/mt76/muru_debug"
	done
	printf 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=%s\n' \
		"$module_mask" >"$TMP/module-file"
	: >"$TMP/logread.log"
	rm -f -- "$RUNTIME/state.json" "$TMP/reboot.log" "$TMP/init-actions" \
		"$TMP/rotation-done"
}

run_guard() {
	set +e
	CR6608_TEST_ROOT="$TMP" \
	CR6608_PRIVATE_RUNTIME_LIB="$TMP/private-runtime" \
	CR6608_UL_MURU_ARTIFACT_PROFILE="$TMP/profile" \
	CR6608_UL_MURU_MODULE_FILE="$TMP/module-file" \
	CR6608_UL_MURU_MODULE_PARAM="$TMP/legacy-param" \
	CR6608_MURU_MASK_MODULE_PARAM="$TMP/mask-param" \
	CR6608_UL_MURU_DEBUG_ROOT="$DEBUG" \
	CR6608_UL_MURU_REBOOT_CMD="$BIN/reboot" \
	CR6608_UL_MURU_GUARD_INIT="$BIN/guard-init" \
	CR6608_UL_MURU_REBOOT_DELAY=0 \
	CR6608_UL_MURU_INTERVAL=3600 \
	MOCK_SLEEP_MODE="${MOCK_SLEEP_MODE:-idle}" \
	PATH="$BIN:$PATH" sh "$GUARD" >"$TMP/guard.log" 2>&1
	guard_rc=$?
	set -e
}

expect_stable_disabled() {
	[ "$guard_rc" -eq 0 ] || fail "$1 consistent mask-zero policy returned failure"
	grep -Fq '"state":"disabled"' "$RUNTIME/state.json" ||
		fail "$1 was not reported disabled"
	[ ! -e "$TMP/reboot.log" ] || fail "$1 requested reboot"
}

expect_armed() {
	[ "$guard_rc" -eq 0 ] || fail 'valid UL RAM profile returned failure'
	grep -Fq '"state":"armed"' "$RUNTIME/state.json" ||
		fail 'valid UL RAM profile was not armed'
	[ ! -e "$TMP/reboot.log" ] || fail 'valid UL RAM profile requested reboot'
}

expect_fail_closed_reboot() {
	case_name="$1"
	[ "$guard_rc" -ne 0 ] || fail "$case_name did not stop after fail-closed recovery"
	for phy in phy0 phy1; do
		[ "$(cat "$DEBUG/$phy/mt76/cr6608_muru_mask")" = 0 ] ||
			fail "$case_name left $phy bitmap enabled"
		[ "$(cat "$DEBUG/$phy/mt76/cr6608_ul_muru")" = 0 ] ||
			fail "$case_name left $phy legacy gate enabled"
	done
	[ "$(cat "$TMP/uci-legacy")" = 0 ] || fail "$case_name left legacy UCI enabled"
	[ "$(cat "$TMP/uci-mask")" = 0 ] || fail "$case_name left bitmap UCI enabled"
	[ "$(cat "$TMP/uci-guard")" = 0 ] || fail "$case_name left guard policy armed"
	[ "$(cat "$TMP/uci-reconcile")" = 1 ] || fail "$case_name did not persist reconciliation"
	[ "$(awk '{for(i=1;i<=NF;i++) if($i ~ /^cr6608_ul_muru=/) print $i}' "$TMP/module-file")" = cr6608_ul_muru=0 ] ||
		fail "$case_name did not zero the legacy module policy"
	[ "$(awk '{for(i=1;i<=NF;i++) if($i ~ /^cr6608_muru_mask=/) print $i}' "$TMP/module-file")" = cr6608_muru_mask=0 ] ||
		fail "$case_name did not zero the bitmap module policy"
	grep -Fqx reboot-requested "$TMP/reboot.log" ||
		fail "$case_name did not request the mandatory wiphy-refresh reboot"
}

prepare_common lab 0 0 0 0 1 disabled-upstream-hang-risk
write_driver_state 0 0 0 0 0 0 0 0
run_guard
expect_stable_disabled lab

prepare_common retail 0 0 0 0 0 retail-disabled
printf '1\n' >"$TMP/uci-reconcile"
write_driver_state 0 0 0 0 0 0 0 0
run_guard
expect_stable_disabled retail
grep -Fqx disable "$TMP/init-actions" || fail 'retail policy did not remove the next-boot guard link'
[ "$(cat "$TMP/uci-reconcile")" = 0 ] || fail 'retail policy did not clear reconciliation'

prepare_common retail 0 0 0 0 0 retail-disabled
printf '1\n' >"$TMP/fail-disable"
write_driver_state 0 0 0 0 0 0 0 0
run_guard
[ "$guard_rc" -ne 0 ] || fail 'guard-link disable failure returned success'
grep -Fq '"state":"service-disable-failed"' "$RUNTIME/state.json" ||
	fail 'guard-link disable failure was not reported'

prepare_common ul 15 15 15 15 1 qualification-requested
write_driver_state 15 1 0 0 0 0 0 0
run_guard
expect_armed

prepare_common ul 15 15 15 15 1 qualification-requested
write_driver_state 15 1 0 0 0 0 0 0
printf '%s\n' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aec timeout' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aed timeout' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aee timeout' \
	>"$TMP/logread.log"
MOCK_SLEEP_MODE=rotate-same
run_guard
MOCK_SLEEP_MODE=idle
expect_fail_closed_reboot 'same-count log rotation'
grep -Fq 'mt7915-hang-signature-3-to-3-fingerprint-' "$RUNTIME/state.json" ||
	fail 'same-count/same-last log replacement was not detected by the full fingerprint'

prepare_common ul 15 15 15 15 1 qualification-requested
write_driver_state 15 1 0 0 0 0 0 0
printf '%s\n' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aec timeout' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aed timeout' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aee timeout' \
	>"$TMP/logread.log"
MOCK_SLEEP_MODE=decrease-new
run_guard
MOCK_SLEEP_MODE=idle
expect_fail_closed_reboot 'count-decrease eviction with new signature'
grep -Fq 'mt7915-hang-signature-3-to-2-fingerprint-' "$RUNTIME/state.json" ||
	fail 'count-decrease eviction plus a new signature was not detected'

prepare_common ul 15 15 15 15 1 qualification-requested
write_driver_state 15 1 0 0 0 0 0 0
printf '%s\n' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aec timeout' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aed timeout' \
	'Aug 26 kernel: mt7915e 0000:02:00.0: Message 00005aee timeout' \
	>"$TMP/logread.log"
MOCK_SLEEP_MODE=decrease
run_guard
MOCK_SLEEP_MODE=idle
expect_armed
grep -Fq 'signatures-2-fingerprint-' "$RUNTIME/state.json" ||
	fail 'benign signature eviction did not rebase the fingerprint baseline'

prepare_common ul 15 15 15 0 1 qualification-requested
write_driver_state 15 1 0 0 0 0 0 0
run_guard
expect_fail_closed_reboot 'next-boot bitmap drift'

prepare_common ul 15 15 0 15 1 qualification-requested
write_driver_state 0 1 1 1 1 0 1 1
run_guard
expect_fail_closed_reboot 'kernel fault latch'
grep -Fq 'startup-telemetry-fault-latched' "$RUNTIME/state.json" ||
	fail 'kernel fault latch reason was not retained'

prepare_common ul 15 15 15 15 1 qualification-requested
write_driver_state 15 1 0 0 1 0 1 0
run_guard
expect_fail_closed_reboot 'STA_REC failure telemetry'

prepare_common ul 15 15 15 15 1 qualification-requested
write_driver_state 15 1 0 0 1 1 0 0
run_guard
expect_fail_closed_reboot 'response/HE snapshot mismatch'

prepare_common ul 15 15 15 15 1 qualification-requested
write_driver_state 15 1 0 0 0 0 0 0
sed -i 's/^mimo_capable_updates=0$/mimo_capable_updates=1/' \
	"$DEBUG/phy0/mt76/cr6608_ul_muru_state"
run_guard
expect_fail_closed_reboot 'MIMO/response snapshot mismatch'

prepare_common lab 0 0 15 15 1 disabled-upstream-hang-risk
write_driver_state 15 1 0 0 0 0 0 0
run_guard
expect_fail_closed_reboot 'LAB active bitmap tamper'

prepare_common unknown 0 0 0 0 0 retail-disabled
write_driver_state 0 0 0 0 0 0 0 0
run_guard
expect_fail_closed_reboot 'unknown artifact profile'

printf 'ul_muru_guard_runtime=pass\n'
