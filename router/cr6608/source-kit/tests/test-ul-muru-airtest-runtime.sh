#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
AIRTEST="${ROOT}/files/usr/sbin/cr6608-ul-muru-airtest"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ul-airtest.XXXXXX")" || exit 1
DEBUGFS="${TEST_ROOT}/debugfs"
MOCK_BIN="${TEST_ROOT}/bin"
STATE="${TEST_ROOT}/state"
PROFILE="${TEST_ROOT}/artifact-profile"
LEGACY_PARAM="${TEST_ROOT}/legacy-param"
MASK_PARAM="${TEST_ROOT}/mask-param"
GUARD_STATE="${TEST_ROOT}/guard-state.json"

cleanup() {
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$MOCK_BIN" \
	"$DEBUGFS/phy0/mt76" \
	"$DEBUGFS/phy1/mt76" \
	"$DEBUGFS/phy0/netdev:phy0-ap0/stations/02:00:00:00:00:01" \
	"$DEBUGFS/phy0/netdev:phy0-ap0/stations/02:00:00:00:00:02"
printf '0\n' > "$DEBUGFS/phy0/mt76/muru_debug"
printf '0\n' > "$DEBUGFS/phy1/mt76/muru_debug"

arm_gate() {
	printf '%s\n' \
		'profile=ul-muru-ram-v1' \
		'sale_ready=NO' \
		'radio_policy=ul-muru-ram-qualification' >"$PROFILE"
	printf 'N\n' >"$LEGACY_PARAM"
	printf '15\n' >"$MASK_PARAM"
	printf '{"state":"armed","profile":"ul-muru-ram-v1","time":%s}\n' \
		"$(date +%s)" >"$GUARD_STATE"
	for mt76_dir in "$DEBUGFS"/phy*/mt76; do
		printf '15\n' >"$mt76_dir/cr6608_muru_mask"
		printf '1\n' >"$mt76_dir/cr6608_ul_muru"
		cat >"$mt76_dir/cr6608_ul_muru_state" <<'EOF'
candidate_allowed=1
candidate_ul_enabled=1
candidate_mask=15
candidate_dl_ofdma=1
candidate_ul_ofdma=1
candidate_dl_mumimo=1
candidate_ul_mumimo=1
fault_latched=0
fault_latches=0
policy=mediatek-25.12-mu-onoff-sta-rec-port
sta_rec_attempted=0
sta_rec_response_ok=0
sta_rec_failed=0
sta_rec_timeout=0
he_sta_rec_updates=0
mimo_capable_updates=0
EOF
	done
}

write_stats() {
	value="$1"
	for mt76_dir in "$DEBUGFS"/phy*/mt76; do
		stats="${mt76_dir}/muru_stats"
		cat > "$stats" <<EOF
Uplink
Total HE MU-MIMO UL TB PPDU count: ${value}
Total HE OFDMA UL TB PPDU count: ${value}
EOF
	done
}

write_capabilities() {
	full="$1"
	partial="$2"
	capable="$3"
	for station in "$DEBUGFS/phy0/netdev:phy0-ap0/stations"/*; do
		cat > "$station/cr6608_muru_capabilities" <<EOF
he=1
ul_ofdma_sta_rec_eligible=1
ul_mumimo_full=${full}
ul_mumimo_partial=${partial}
ul_mumimo_capable=${capable}
EOF
	done
}

cat > "$MOCK_BIN/ubus" <<'EOF'
#!/bin/sh
case "${1-}" in
	list) printf '%s\n' hostapd.phy0-ap0 ;;
	call)
		cat <<'JSON'
{
  "02:00:00:00:00:01": {"he": true},
  "02:00:00:00:00:02": {"he": true}
}
JSON
		;;
	*) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/iw" <<'EOF'
#!/bin/sh
if [ "${1-}" = dev ] && [ "${2-}" = phy0-ap0 ] &&
   [ "${3-}" = info ]; then
	printf 'Interface phy0-ap0\n\twiphy 0\n\ttype AP\n'
	exit 0
fi
if [ "${1-}" = dev ] && [ "${2-}" = phy0-ap0 ] &&
   [ "${3-}" = station ] && [ "${4-}" = dump ]; then
	state="$(cat "$MOCK_STATE")"
	if [ "${MOCK_COUNTER_MODE:-target}" = noncapable ]; then
		first=100
		second=200
	else
		first=$((100 + state * 100))
		second=$((200 + state * 100))
	fi
	third=$((300 + state * 100))
	fourth=$((400 + state * 100))
	printf 'Station 02:00:00:00:00:01 (on phy0-ap0)\n\trx bytes: %s\n' "$first"
	printf 'Station 02:00:00:00:00:02 (on phy0-ap0)\n\trx bytes: %s\n' "$second"
	printf 'Station 02:00:00:00:00:03 (on phy0-ap0)\n\trx bytes: %s\n' "$third"
	printf 'Station 02:00:00:00:00:04 (on phy0-ap0)\n\trx bytes: %s\n' "$fourth"
	exit 0
fi
exit 1
EOF

cat > "$MOCK_BIN/sleep" <<'EOF'
#!/bin/sh
state="$(cat "$MOCK_STATE")"
state=$((state + 1))
printf '%s\n' "$state" > "$MOCK_STATE"
for stats in "$MOCK_DEBUGFS_ROOT"/phy*/mt76/muru_stats; do
	phy="$(basename "$(dirname "$(dirname "$stats")")")"
	value="$state"
	if [ "${MOCK_COUNTER_MODE:-target}" = other ]; then
		[ "$phy" = phy0 ] && value=0 || value="$state"
	fi
	cat > "$stats" <<STATS
Uplink
Total HE MU-MIMO UL TB PPDU count: ${value}
Total HE OFDMA UL TB PPDU count: $((value * 2))
STATS
done
if [ "${MOCK_GATE_MODE:-armed}" = drop-after ] &&
   [ ! -e "$MOCK_TEST_ROOT/gate-dropped" ]; then
	for state_node in "$MOCK_DEBUGFS_ROOT"/phy*/mt76/cr6608_ul_muru_state; do
		sed -i 's/^fault_latched=0$/fault_latched=1/;
			s/^fault_latches=0$/fault_latches=1/' "$state_node"
	done
	: >"$MOCK_TEST_ROOT/gate-dropped"
fi
EOF
cat > "$MOCK_BIN/guard-init" <<'EOF'
#!/bin/sh
[ "${1:-}" = running ]
EOF
chmod 755 "$MOCK_BIN/ubus" "$MOCK_BIN/iw" "$MOCK_BIN/sleep" \
	"$MOCK_BIN/guard-init"

run_airtest() {
	counter_mode="${1:-target}"
	gate_mode="${2:-armed}"
	rm -f -- "$TEST_ROOT/gate-dropped"
	PATH="$MOCK_BIN:$PATH" \
	MOCK_STATE="$STATE" \
	MOCK_DEBUGFS_ROOT="$DEBUGFS" \
	MOCK_TEST_ROOT="$TEST_ROOT" \
	MOCK_COUNTER_MODE="$counter_mode" \
	MOCK_GATE_MODE="$gate_mode" \
	CR6608_DEBUGFS_ROOT="$DEBUGFS" \
	CR6608_TMP_ROOT="$TEST_ROOT" \
	CR6608_UL_MURU_ARTIFACT_PROFILE="$PROFILE" \
	CR6608_UL_MURU_MODULE_PARAM="$LEGACY_PARAM" \
	CR6608_MURU_MASK_MODULE_PARAM="$MASK_PARAM" \
	CR6608_UL_MURU_GUARD_INIT="$MOCK_BIN/guard-init" \
	CR6608_UL_MURU_GUARD_STATE_FILE="$GUARD_STATE" \
	CR6608_UL_MURU_GUARD_MAX_AGE=60 \
		sh "$AIRTEST" 10
}

# A partial-only peer must never satisfy the MT7915 full-bandwidth filter.
arm_gate
printf '0\n' > "$STATE"
write_stats 0
write_capabilities 0 1 0
set +e
partial_output="$(run_airtest target 2>&1)"
partial_rc=$?
set -e
[ "$partial_rc" -eq 2 ] || {
	printf 'partial-only case returned %s\n%s\n' "$partial_rc" "$partial_output" >&2
	exit 1
}
printf '%s\n' "$partial_output" | grep -qx \
	'RESULT_UL_MURU_AIRTEST=PREREQUISITE_MISSING_TWO_FULL_BW_UL_MUMIMO_CLIENTS'

# Two full-bandwidth peers with overlapping uplink growth and both firmware
# counter deltas must pass the controlled correlation window.
arm_gate
printf '0\n' > "$STATE"
write_stats 0
write_capabilities 1 0 1
full_output="$(run_airtest target 2>&1)" || {
	printf '%s\n' "$full_output" >&2
	exit 1
}
printf '%s\n' "$full_output" | grep -Eq \
	'^full-bandwidth UL MU-MIMO clients[[:space:]]+2$'
printf '%s\n' "$full_output" | grep -qx \
	'RESULT_UL_MUMIMO_RADIO_COUNTER_CORRELATION=OBSERVED_IN_WINDOW'
printf '%s\n' "$full_output" | grep -qx \
	'RESULT_UL_OFDMA_RADIO_COUNTER_CORRELATION=OBSERVED_IN_WINDOW'
printf '%s\n' "$full_output" | grep -qx \
	'RESULT_UL_MURU_AIRTEST=BOTH_RADIO_COUNTERS_CORRELATED_NOT_CLIENT_ATTRIBUTED'
printf '%s\n' "$full_output" | grep -qx \
	'EVIDENCE_SCOPE=AGGREGATE_SAME_RADIO_COUNTER_CORRELATION_NOT_CLIENT_ATTRIBUTION'
printf '%s\n' "$full_output" | grep -qx \
	'CLIENT_ATTRIBUTED_OTA_PROOF=REQUIRES_PER_PEER_SCHEDULER_TELEMETRY_OR_PACKET_CAPTURE_HARDWARE'
[ "$(cat "$DEBUGFS/phy0/mt76/muru_debug")" = 0 ]

# Traffic and counters on the non-selected phy must never prove the selected
# interface's airtime scheduling.
arm_gate
printf '0\n' > "$STATE"
write_stats 0
set +e
other_output="$(run_airtest other 2>&1)"
other_rc=$?
set -e
[ "$other_rc" -eq 4 ] || {
	printf 'other-phy-only case returned %s\n%s\n' "$other_rc" "$other_output" >&2
	exit 1
}
printf '%s\n' "$other_output" | grep -qx \
	'RESULT_UL_MUMIMO_RADIO_COUNTER_CORRELATION=NOT_OBSERVED_IN_WINDOW'
printf '%s\n' "$other_output" | grep -qx \
	'RESULT_UL_OFDMA_RADIO_COUNTER_CORRELATION=NOT_OBSERVED_IN_WINDOW'
printf '%s\n' "$other_output" | grep -qx \
	'RESULT_UL_MURU_AIRTEST=INCOMPLETE_RADIO_COUNTER_CORRELATION'

# Uplink from unrelated peers must not be attributed to the two capable MACs.
arm_gate
printf '0\n' > "$STATE"
write_stats 0
set +e
noncapable_output="$(run_airtest noncapable 2>&1)"
noncapable_rc=$?
set -e
[ "$noncapable_rc" -eq 3 ] || {
	printf 'non-capable uploader case returned %s\n%s\n' \
		"$noncapable_rc" "$noncapable_output" >&2
	exit 1
}
printf '%s\n' "$noncapable_output" | grep -qx \
	'RESULT_UL_MURU_AIRTEST=INVALID_NOT_TWO_SIMULTANEOUS_UPLOADERS'

# An unarmed profile/mask/fault/guard is rejected before sampling.
arm_gate
printf '0\n' >"$MASK_PARAM"
set +e
before_gate_output="$(run_airtest target 2>&1)"
before_gate_rc=$?
set -e
[ "$before_gate_rc" -eq 1 ] || {
	printf 'pre-gate case returned %s\n%s\n' "$before_gate_rc" "$before_gate_output" >&2
	exit 1
}
printf '%s\n' "$before_gate_output" | grep -qx \
	'RESULT_UL_MURU_AIRTEST=ERROR_QUALIFICATION_GATE_NOT_ARMED_BEFORE'

# A fault appearing inside the sample window invalidates every counter delta.
arm_gate
printf '0\n' >"$STATE"
write_stats 0
write_capabilities 1 0 1
set +e
after_gate_output="$(run_airtest target drop-after 2>&1)"
after_gate_rc=$?
set -e
[ "$after_gate_rc" -eq 1 ] || {
	printf 'post-gate case returned %s\n%s\n' "$after_gate_rc" "$after_gate_output" >&2
	exit 1
}
printf '%s\n' "$after_gate_output" | grep -qx \
	'RESULT_UL_MURU_AIRTEST=ERROR_QUALIFICATION_GATE_NOT_ARMED_AFTER'

printf 'ul_muru_airtest_runtime=pass\n'
