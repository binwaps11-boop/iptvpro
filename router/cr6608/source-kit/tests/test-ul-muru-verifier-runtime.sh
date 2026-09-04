#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AX_VERIFY="$ROOT/files/usr/sbin/cr6608-ax-verify"
FULL_VERIFY="$ROOT/files/usr/sbin/cr6608-ul-muru-verify"

fail() {
	printf 'ul_muru_verifier_runtime=fail: %s\n' "$*" >&2
	exit 1
}

sh -n "$AX_VERIFY" || fail 'AX verifier syntax failed'
sh -n "$FULL_VERIFY" || fail 'UL verifier syntax failed'
grep -Fq '[ "$guard_health" = armed-fresh ]' "$FULL_VERIFY" ||
	fail 'full UL verifier does not require a live fresh guard'
grep -Fq 'fault_latched' "$FULL_VERIFY" || fail 'full verifier ignores fault telemetry'
grep -Fq 'sta_rec_timeout' "$FULL_VERIFY" || fail 'full verifier ignores MCU timeout telemetry'
grep -Fq 'sta_rec_response_ok' "$FULL_VERIFY" ||
	fail 'full verifier lacks response-only STA_REC telemetry'
grep -Fq 'not Firmware apply or OTA proof' "$FULL_VERIFY" ||
	fail 'full verifier presents response_ok as stronger proof than it is'
! grep -Fq 'sta_rec_acked' "$FULL_VERIFY" ||
	fail 'full verifier retains the misleading ACK telemetry name'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ul-verifier.XXXXXX")" || exit 1
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
BIN="$TMP/bin"
DEBUG="$TMP/debug"
mkdir -p "$BIN" "$DEBUG/phy0/mt76" "$DEBUG/phy1/mt76"

cat >"$BIN/uci" <<'SH'
#!/bin/sh
[ "${1:-}" = -q ] && shift
[ "${1:-}" = get ] || exit 1
case "${2:-}" in
	smartap.experimental.ul_muru) printf '%s\n' "$CR6608_TEST_UCI_LEGACY" ;;
	smartap.experimental.muru_mask) printf '%s\n' "$CR6608_TEST_UCI_MASK" ;;
	*) exit 1 ;;
esac
SH
cat >"$BIN/guard-init" <<'SH'
#!/bin/sh
[ "${1:-}" = running ] && [ "${CR6608_TEST_GUARD_RUNNING:-0}" = 1 ]
SH
cat >"$BIN/iw" <<'SH'
#!/bin/sh
if [ "${1:-}" = phy ] && [ "$#" -eq 1 ]; then
	[ "${CR6608_TEST_CAP:-0}" = 1 ] &&
		printf 'HE MAC Capabilities: Full Bandwidth UL MU-MIMO\n'
	exit 0
fi
exit 0
SH
cat >"$BIN/ubus" <<'SH'
#!/bin/sh
[ "${1:-}" = list ] && exit 0
exit 1
SH
chmod 0755 "$BIN/uci" "$BIN/guard-init" "$BIN/iw" "$BIN/ubus"

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

write_state_nodes() {
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

write_runtime() {
	profile="$1" mask="$2"
	write_profile "$profile"
	printf 'N\n' >"$TMP/legacy-param"
	printf '%s\n' "$mask" >"$TMP/mask-param"
	printf 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=%s\n' \
		"$mask" >"$TMP/module-file"
	CR6608_TEST_UCI_LEGACY_VALUE=0
	CR6608_TEST_UCI_MASK_VALUE="$mask"
	legacy_gate=0
	allowed=0
	[ "$mask" = 15 ] && { legacy_gate=1; allowed=1; }
	for phy in phy0 phy1; do
		printf '%s\n' "$mask" >"$DEBUG/$phy/mt76/cr6608_muru_mask"
		printf '%s\n' "$legacy_gate" >"$DEBUG/$phy/mt76/cr6608_ul_muru"
		printf '0\n' >"$DEBUG/$phy/mt76/muru_debug"
		printf '%s\n' 'Uplink' 'Total HE MU-MIMO UL TB PPDU count: 0' \
			'Total HE OFDMA UL TB PPDU count: 0' >"$DEBUG/$phy/mt76/muru_stats"
	done
	write_state_nodes "$mask" "$allowed" 0 0 0 0 0 0
}

run_state() {
	running="$1"
	set +e
	state_output="$(
		CR6608_TEST_UCI_LEGACY="$CR6608_TEST_UCI_LEGACY_VALUE" \
		CR6608_TEST_UCI_MASK="$CR6608_TEST_UCI_MASK_VALUE" \
		CR6608_TEST_GUARD_RUNNING="$running" \
		CR6608_UL_MURU_ARTIFACT_PROFILE="$TMP/profile" \
		CR6608_UL_MURU_MODULE_FILE="$TMP/module-file" \
		CR6608_UL_MURU_MODULE_PARAM="$TMP/legacy-param" \
		CR6608_MURU_MASK_MODULE_PARAM="$TMP/mask-param" \
		CR6608_UL_MURU_DEBUG_ROOT="$DEBUG" \
		CR6608_UL_MURU_GUARD_INIT="$BIN/guard-init" \
		CR6608_UL_MURU_GUARD_STATE_FILE="$TMP/guard-state.json" \
		CR6608_UL_MURU_GUARD_MAX_AGE=60 \
		PATH="$BIN:$PATH" sh "$AX_VERIFY" --ul-muru-state-only
	)"
	state_rc=$?
	set -e
}

run_full() {
	running="$1" cap="$2"
	set +e
	full_output="$(
		CR6608_TEST_UCI_LEGACY="$CR6608_TEST_UCI_LEGACY_VALUE" \
		CR6608_TEST_UCI_MASK="$CR6608_TEST_UCI_MASK_VALUE" \
		CR6608_TEST_GUARD_RUNNING="$running" CR6608_TEST_CAP="$cap" \
		CR6608_UL_MURU_ARTIFACT_PROFILE="$TMP/profile" \
		CR6608_UL_MURU_MODULE_FILE="$TMP/module-file" \
		CR6608_UL_MURU_MODULE_PARAM="$TMP/legacy-param" \
		CR6608_MURU_MASK_MODULE_PARAM="$TMP/mask-param" \
		CR6608_UL_MURU_DEBUG_ROOT="$DEBUG" \
		CR6608_UL_MURU_GUARD_INIT="$BIN/guard-init" \
		CR6608_UL_MURU_GUARD_STATE_FILE="$TMP/guard-state.json" \
		CR6608_UL_MURU_GUARD_MAX_AGE=60 \
		PATH="$BIN:$PATH" sh "$FULL_VERIFY"
	)"
	full_rc=$?
	set -e
}

now="$(date +%s)"
write_runtime lab 0
rm -f -- "$TMP/guard-state.json"
run_state 0
[ "$state_rc" -eq 0 ] && [ "$state_output" = stable-disabled ] ||
	fail 'LAB mask-zero policy incorrectly requires a running guard'
run_full 0 0
[ "$full_rc" -eq 0 ] && printf '%s\n' "$full_output" |
	grep -qx 'RESULT_UL_MURU_MASK=0' || fail 'full verifier rejected valid LAB mask-zero policy'

write_runtime retail 0
run_state 0
[ "$state_rc" -eq 0 ] && [ "$state_output" = stable-disabled ] ||
	fail 'retail mask-zero policy did not pass'

write_runtime ul 15
printf '{"state":"armed","reason":"test","time":%s}\n' "$now" >"$TMP/guard-state.json"
run_state 1
[ "$state_rc" -eq 0 ] && [ "$state_output" = armed ] ||
	fail 'fresh mask-15 state with a running guard did not pass'
run_full 1 1
[ "$full_rc" -eq 0 ] && printf '%s\n' "$full_output" |
	grep -qx 'RESULT_UL_MURU_MASK=15' || fail 'full verifier rejected valid mask-15 qualification state'
printf '%s\n' "$full_output" | grep -Fq 'not Firmware apply or OTA proof' ||
	fail 'full verifier output omits the response-only proof boundary'
printf '%s\n' "$full_output" |
	grep -qx 'EVIDENCE_SCOPE=AGGREGATE_RADIO_COUNTERS_NOT_CLIENT_ATTRIBUTION' ||
	fail 'full verifier does not label aggregate counters as non-attributed'
printf '%s\n' "$full_output" |
	grep -qx 'CLIENT_ATTRIBUTED_OTA_PROOF=REQUIRES_PER_PEER_SCHEDULER_TELEMETRY_OR_PACKET_CAPTURE_HARDWARE' ||
	fail 'full verifier omits the client-attributed OTA evidence requirement'

run_state 0
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'stopped guard was accepted as armed'

stale=$((now - 61))
printf '{"state":"armed","reason":"test","time":%s}\n' "$stale" >"$TMP/guard-state.json"
run_state 1
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'stale guard heartbeat was accepted as armed'

printf '{"state":"armed","reason":"test","time":%s}\n' "$now" >"$TMP/guard-state.json"
printf '0\n' >"$DEBUG/phy0/mt76/cr6608_muru_mask"
run_state 1
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'partial bitmap clear was accepted as armed'

write_runtime ul 15
printf '{"state":"armed","reason":"test","time":%s}\n' "$now" >"$TMP/guard-state.json"
write_state_nodes 15 1 1 1 1 0 1 1
run_state 1
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'fault-latched telemetry was accepted as armed'

write_runtime ul 15
printf '{"state":"armed","reason":"test","time":%s}\n' "$now" >"$TMP/guard-state.json"
write_state_nodes 15 1 0 0 1 0 1 0
run_state 1
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'failed STA_REC telemetry was accepted as armed'

write_runtime ul 15
printf '{"state":"armed","reason":"test","time":%s}\n' "$now" >"$TMP/guard-state.json"
write_state_nodes 15 1 0 0 1 1 0 0
run_state 1
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'response_ok without its HE update was accepted as a coherent snapshot'

write_runtime ul 15
printf '{"state":"armed","reason":"test","time":%s}\n' "$now" >"$TMP/guard-state.json"
sed -i 's/^mimo_capable_updates=0$/mimo_capable_updates=1/' \
	"$DEBUG/phy0/mt76/cr6608_ul_muru_state"
run_state 1
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'mimo_capable_updates above response_ok was accepted'

write_runtime unknown 0
run_state 0
[ "$state_rc" -ne 0 ] && [ "$state_output" = inconsistent ] ||
	fail 'unknown artifact profile was accepted as stable'

printf 'ul_muru_verifier_runtime=pass\n'
