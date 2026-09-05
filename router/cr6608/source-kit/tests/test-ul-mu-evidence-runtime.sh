#!/bin/sh
#
# Runtime contract for cr6608-ul-mu-evidence (v4) against a mocked debugfs
# tree.  The tool must never claim uplink MU from a single peer, never from
# BSR-poll (QoS-Null) responses alone, never when the driver lacks the
# schema-2 attribution nodes, never when the armed mask / group-5 state /
# firmware reset counters changed inside the window, and must always print
# its evidence boundary.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/files/usr/sbin/cr6608-ul-mu-evidence"

fail() {
	printf 'ul mu evidence contract failed: %s\n' "$*" >&2
	exit 1
}

[ -x "$TOOL" ] || fail 'tool missing or not executable'
sh -n "$TOOL" || fail 'tool syntax error'

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

mask_file="$WORK/mask"
printf '15\n' > "$mask_file"

G5=1
ARMED=15
SCHEMA=2
radio() {
	# radio <phy> <band> <tb> <mpdu> <ofdma_ru> <full_bw> <data> <null> <og> <mg> <ogd> <mgd> <max_peers>
	d="$WORK/debug/$1/mt76"
	mkdir -p "$d"
	{
		[ "$SCHEMA" = 2 ] && printf 'schema=2\n'
		printf 'band=%s\n' "$2"
		printf 'armed_mask=%s\n' "$ARMED"
		printf 'rxv_group5_enabled=%s\n' "$G5"
		printf 'he_tb_ppdu=%s\n' "$3"
		printf 'he_tb_mpdu=%s\n' "$4"
		printf 'he_tb_ul_ofdma_ru=%s\n' "$5"
		printf 'he_tb_full_bw=%s\n' "$6"
		printf 'he_tb_data_ppdu=%s\n' "$7"
		printf 'he_tb_nulldata_ppdu=%s\n' "$8"
		printf 'he_tb_fc_unknown=0\n'
		printf 'he_tb_no_timestamp=0\n'
		printf 'ul_ofdma_multi_user_ppdus=%s\n' "$9"
		printf 'ul_mumimo_multi_user_ppdus=%s\n' "${10}"
		printf 'ul_ofdma_multi_user_data_ppdus=%s\n' "${11}"
		printf 'ul_mumimo_multi_user_data_ppdus=%s\n' "${12}"
		printf 'max_peers_in_one_ppdu=%s\n' "${13}"
		printf 'evidence=client-attributed-rx-descriptor-wcid\n'
		printf 'note=host-observed-scheduling-evidence-not-a-regulatory-or-rf-measurement\n'
	} > "$d/cr6608_ul_attribution"
}

peer() {
	# peer <phy> <mac> <wcid> <tb> <ofdma_ru> <full_bw> <shared> <data> <null>
	d="$WORK/debug/$1/netdev:wlan0/stations/$2"
	mkdir -p "$d"
	{
		printf 'schema=2\n'
		printf 'wcid=%s\n' "$3"
		printf 'he_tb_ppdu=%s\n' "$4"
		printf 'he_tb_mpdu=%s\n' "$4"
		printf 'he_tb_data_ppdu=%s\n' "$8"
		printf 'he_tb_nulldata_ppdu=%s\n' "$9"
		printf 'he_tb_fc_unknown=0\n'
		printf 'he_tb_ul_ofdma_ru=%s\n' "$5"
		printf 'he_tb_full_bw=%s\n' "$6"
		printf 'he_tb_ul_mumimo_shared=%s\n' "$7"
		printf 'last_tb_timestamp=123456\n'
		printf 'evidence=client-attributed-rx-descriptor-wcid\n'
	} > "$d/cr6608_ul_attribution"
}

fw() {
	# fw <phy> <su> <2ru> <2mu>
	d="$WORK/debug/$1/mt76"
	mkdir -p "$d"
	{
		printf 'Uplink\nTrigger-based Uplink MU-MIMO\nData Type:  \n'
		printf 'Total HE MU-MIMO UL TB PPDU count: %s\n' "$4"
		printf 'Total HE OFDMA UL TB PPDU count: %s\n' "$3"
		printf 'All HE UL TB PPDU count: %s\n\n' "$(( $2 + $3 + $4 ))"
		printf 'ul_hetrig_su=%s\n' "$2"
		printf 'ul_hetrig_2ru=%s\nul_hetrig_3ru=0\nul_hetrig_4ru=0\nul_hetrig_5to8ru=0\nul_hetrig_9to16ru=0\nul_hetrig_gtr16ru=0\n' "$3"
		printf 'ul_hetrig_2mu=%s\nul_hetrig_3mu=0\nul_hetrig_4mu=0\n' "$4"
		printf 'source=MURU_GET_TXC_TX_STATS band=0 polled_ms=500\n'
	} > "$d/muru_stats"
	[ -f "$d/muru_debug" ] || printf '0\n' > "$d/muru_debug"
}

resets() {
	d="$WORK/debug/phy0/mt76"; mkdir -p "$d"
	printf 'SYS_RESET_COUNT: WM %s, WA 0\n' "$1" > "$d/sys_recovery"
}

run() {
	CR6608_UL_MURU_DEBUG_ROOT="$WORK/debug" \
	CR6608_MURU_MASK_MODULE_PARAM="$mask_file" \
	sh "$TOOL" --auto --window 0 "$@"
}

verdict_is() {
	want="$1"; shift
	out="$(run "$@")"
	got="$(printf '%s\n' "$out" | sed -n 's/^verdict=//p')"
	[ "$got" = "$want" ] || {
		printf '%s\n' "$out" >&2
		fail "expected verdict $want, got ${got:-<none>}"
	}
}

# 1. No driver nodes at all.
mkdir -p "$WORK/debug"
verdict_is NO_ATTRIBUTION_NODES

# 2. Schema-1 (pre-v2) nodes must not be interpreted.
SCHEMA=1 radio phy0 0 100 100 0 100 100 0 50 50 50 50 2
verdict_is NO_ATTRIBUTION_NODES
run | grep -q 'status=malformed' || fail 'schema-1 radio record was not rejected'
SCHEMA=2

# 3. Idle: nothing at all.
radio phy0 0 0 0 0 0 0 0 0 0 0 0 0
verdict_is NO_TRIGGER_ACTIVITY

# 4. Single peer answering triggers: never a multi-user claim.
radio phy0 0 40 80 0 40 40 0 0 0 0 0 1
peer phy0 aa:bb:cc:dd:ee:01 1 40 0 40 0 40 0
verdict_is TRIGGER_RESPONSE_SINGLE_USER_ONLY
run | grep -q 'verdict=UL_' && fail 'a single peer produced a multi-user claim'

# 5. Two idle peers answering BSR polls: groups but no data -> not uplink data.
radio phy0 0 60 60 60 0 0 60 30 0 0 0 2
peer phy0 aa:bb:cc:dd:ee:01 1 30 30 0 0 0 30
peer phy0 aa:bb:cc:dd:ee:02 2 30 30 0 0 0 30
verdict_is BSR_POLL_RESPONSES_ONLY
run | grep -q 'verdict=UL_' && fail 'BSR poll responses produced an uplink data claim'

# 6. Two peers, sub-bandwidth RUs, data-bearing groups: UL OFDMA on device.
radio phy0 0 80 160 80 0 80 0 40 0 40 0 2
peer phy0 aa:bb:cc:dd:ee:01 1 40 40 0 0 40 0
peer phy0 aa:bb:cc:dd:ee:02 2 40 40 0 0 40 0
verdict_is UL_OFDMA_DATA_MULTI_USER_OBSERVED_ON_DEVICE

# 7. Same but only one peer carried enough data: insufficient.
radio phy0 0 80 160 80 0 45 35 40 0 5 0 2
peer phy0 aa:bb:cc:dd:ee:01 1 40 40 0 0 40 0
peer phy0 aa:bb:cc:dd:ee:02 2 40 40 0 0 5 35
verdict_is INSUFFICIENT_MULTI_USER_DATA_PPDUS

# 8. Full-bandwidth shared groups with both peers credited: UL MU-MIMO.
radio phy0 0 80 160 0 80 80 0 0 40 0 40 2
peer phy0 aa:bb:cc:dd:ee:01 1 40 0 40 40 40 0
peer phy0 aa:bb:cc:dd:ee:02 2 40 0 40 40 40 0
verdict_is UL_MUMIMO_FULL_BW_DATA_MULTI_USER_OBSERVED_ON_DEVICE

# 9. Full-bandwidth groups but only one peer credited (pre-v2 first-peer
#    defect shape): must degrade to OFDMA-level claim, never MU-MIMO.
peer phy0 aa:bb:cc:dd:ee:02 2 40 0 40 0 40 0
verdict_is UL_OFDMA_DATA_MULTI_USER_OBSERVED_ON_DEVICE

# 10. Malformed radio record alongside a good one.
mkdir -p "$WORK/debug/phy1/mt76"
printf 'schema=2\nband=1\narmed_mask=15\nrxv_group5_enabled=1\nhe_tb_ppdu=abc\n' > "$WORK/debug/phy1/mt76/cr6608_ul_attribution"
run | grep -q 'status=malformed' || fail 'malformed radio record was not rejected'
rm -rf "$WORK/debug/phy1"

# 11. Boundary line and read-only behaviour.
run | grep -qx 'evidence_boundary=observed-on-this-device-in-this-window-not-a-support-certification-rf-or-regulatory-claim' ||
	fail 'evidence boundary line is missing'
before="$(find "$WORK/debug" -type f -exec cat {} + | cksum)"
run >/dev/null
after="$(find "$WORK/debug" -type f -exec cat {} + | cksum)"
[ "$before" = "$after" ] || fail 'tool modified the debugfs tree'

# 12. Firmware window: muru_debug always re-written (re-sends the enable) and
#     restored; idle firmware agrees.
radio phy0 0 0 0 0 0 0 0 0 0 0 0 0
rm -rf "$WORK/debug/phy0/netdev:wlan0"
fw phy0 0 0 0
printf '1\n' > "$WORK/debug/phy0/mt76/muru_debug"
out="$(run --with-firmware)"
[ "$(cat "$WORK/debug/phy0/mt76/muru_debug")" = 1 ] || fail 'muru_debug that was 1 was not restored to 1'
printf '%s\n' "$out" | grep -qx 'mode=host-plus-firmware-window' || fail 'window mode not reported'
printf '%s\n' "$out" | grep -qx 'verdict=NO_TRIGGER_ACTIVITY' || fail 'idle window gave a non-idle verdict'
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_AGREES_NOTHING_SCHEDULED' || fail 'idle window: firmware corroboration wrong'
printf '0\n' > "$WORK/debug/phy0/mt76/muru_debug"
run --with-firmware >/dev/null
[ "$(cat "$WORK/debug/phy0/mt76/muru_debug")" = 0 ] || fail 'muru_debug was not restored to 0'

# 13. Pre-existing counters are not window activity (window 0 = no delta).
radio phy0 0 500 900 500 0 500 0 250 0 250 0 2
peer phy0 aa:bb:cc:dd:ee:01 1 250 250 0 0 250 0
peer phy0 aa:bb:cc:dd:ee:02 2 250 250 0 0 250 0
fw phy0 100 250 0
out="$(run --with-firmware)"
printf '%s\n' "$out" | grep -qx 'verdict=NO_TRIGGER_ACTIVITY' || fail 'pre-existing counters were counted as window activity'

# 14. A real window: counters grow during the sleep.  Simulate with a
#     background writer and window 1.
grow_during_window() {
	# $1 script run in background after 0.3 s; remaining args go to the tool
	script="$1"; shift
	( sleep 0.3; sh -c "$script" >/dev/null ) &
	CR6608_UL_MURU_DEBUG_ROOT="$WORK/debug" CR6608_MURU_MASK_MODULE_PARAM="$mask_file" \
		sh "$TOOL" --auto --window 1 --with-firmware "$@"
	wait
}
radio phy0 0 0 0 0 0 0 0 0 0 0 0 0
peer phy0 aa:bb:cc:dd:ee:01 1 0 0 0 0 0 0
peer phy0 aa:bb:cc:dd:ee:02 2 0 0 0 0 0 0
fw phy0 0 0 0
out="$(grow_during_window "
	. /dev/null
	G5=1; ARMED=15; SCHEMA=2; WORK='$WORK'
	$(sed -n '/^radio()/,/^}/p;/^peer()/,/^}/p;/^fw()/,/^}/p' "$0")
	radio phy0 0 80 160 0 80 80 0 0 40 0 40 2
	peer phy0 aa:bb:cc:dd:ee:01 1 40 0 40 40 40 0
	peer phy0 aa:bb:cc:dd:ee:02 2 40 0 40 40 40 0
	fw phy0 5 0 40
")"
printf '%s\n' "$out" | grep -qx 'verdict=UL_MUMIMO_FULL_BW_DATA_MULTI_USER_OBSERVED_ON_DEVICE' || { printf '%s\n' "$out" >&2; fail 'window UL MU-MIMO not observed'; }
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_CORROBORATED' || fail 'firmware corroboration missing for UL MU-MIMO'
printf '%s\n' "$out" | grep -q '^phase=ul firmware=phy0 fw_hetrig_su=5 fw_hetrig_ofdma=0 fw_hetrig_mumimo=40 ' || { printf '%s\n' "$out" >&2; fail 'firmware deltas wrong'; }
printf '%s\n' "$out" | grep -q '^phase=ul peer=aa:bb:cc:dd:ee:01 radio=phy0 wcid=1 he_tb_ppdu=40 ' || fail 'peer delta wrong'
printf '%s\n' "$out" | grep -q 'fw_hetrig_nonsu=40 ' || fail 'non-SU firmware total missing'

# 15. Firmware disagreement: host sees OFDMA data groups, firmware reports none.
radio phy0 0 80 160 80 0 80 0 40 0 40 0 2
peer phy0 aa:bb:cc:dd:ee:01 1 40 40 0 0 40 0
peer phy0 aa:bb:cc:dd:ee:02 2 40 40 0 0 40 0
fw phy0 0 0 0
out="$(grow_during_window "
	WORK='$WORK'; G5=1; ARMED=15; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p;/^peer()/,/^}/p;/^fw()/,/^}/p' "$0")
	radio phy0 0 160 320 160 0 160 0 80 0 80 0 2
	peer phy0 aa:bb:cc:dd:ee:01 1 80 80 0 0 80 0
	peer phy0 aa:bb:cc:dd:ee:02 2 80 80 0 0 80 0
	fw phy0 0 0 0
")"
printf '%s\n' "$out" | grep -qx 'verdict=INCONCLUSIVE_HOST_EXCEEDS_FIRMWARE' || { printf '%s\n' "$out" >&2; fail 'host exceeding firmware not flagged inconclusive'; }

# 16. Firmware minimum: host proof present but firmware reports too few triggers.
out="$(grow_during_window "
	WORK='$WORK'; G5=1; ARMED=15; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p;/^peer()/,/^}/p;/^fw()/,/^}/p' "$0")
	radio phy0 0 240 480 240 0 240 0 120 0 120 0 2
	peer phy0 aa:bb:cc:dd:ee:01 1 120 120 0 0 120 0
	peer phy0 aa:bb:cc:dd:ee:02 2 120 120 0 0 120 0
	fw phy0 0 45 0
")"
printf '%s\n' "$out" | grep -qx 'verdict=UL_OFDMA_DATA_MULTI_USER_OBSERVED_ON_DEVICE' || { printf '%s\n' "$out" >&2; fail 'window UL OFDMA not observed'; }
out="$(grow_during_window "
	WORK='$WORK'; G5=1; ARMED=15; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p;/^peer()/,/^}/p;/^fw()/,/^}/p' "$0")
	radio phy0 0 264 528 264 0 264 0 132 0 132 0 2
	peer phy0 aa:bb:cc:dd:ee:01 1 132 132 0 0 132 0
	peer phy0 aa:bb:cc:dd:ee:02 2 132 132 0 0 132 0
	fw phy0 0 60 0
")"
printf '%s\n' "$out" | grep -qx 'verdict=INCONCLUSIVE_FIRMWARE_TRIGGER_COUNT_BELOW_MINIMUM' || { printf '%s\n' "$out" >&2; fail 'firmware below minimum not flagged'; }

# 17. Firmware-only activity while host saw nothing.
out="$(grow_during_window "
	WORK='$WORK'; G5=1; ARMED=15; SCHEMA=2
	$(sed -n '/^fw()/,/^}/p' "$0")
	fw phy0 30 60 0
")"
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_SAW_TRIGGERS_HOST_DID_NOT' || { printf '%s\n' "$out" >&2; fail 'firmware-only activity not flagged'; }

# 18. Missing muru_stats -> unavailable.
rm -f "$WORK/debug/phy0/mt76/muru_stats"
out="$(run --with-firmware)"
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_STATS_UNAVAILABLE' || fail 'missing muru_stats not reported as unavailable'
fw phy0 30 60 0

# 19. RXD group 5 off: host counters are unavailable, never "nothing".
G5=0 radio phy0 0 0 0 0 0 0 0 0 0 0 0 0
out="$(run --with-firmware)"
printf '%s\n' "$out" | grep -qx 'verdict=HOST_ATTRIBUTION_UNAVAILABLE_RXV_GROUP5_OFF' || { printf '%s\n' "$out" >&2; fail 'group-5-off not reported as unavailable'; }
printf '%s\n' "$out" | grep -qx 'host_attribution=unavailable-rxv-group5-off' || fail 'host_attribution line wrong'
out="$(grow_during_window "
	WORK='$WORK'; G5=0; ARMED=15; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p;/^fw()/,/^}/p' "$0")
	radio phy0 0 0 0 0 0 0 0 0 0 0 0 0
	fw phy0 30 90 0
")"
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_ONLY_UL_OFDMA_TRIGGERS_SEEN' || { printf '%s\n' "$out" >&2; fail 'firmware-only UL OFDMA evidence not reported'; }
printf '%s\n' "$out" | grep -q 'do-not-prove-tb-reception' || fail 'firmware-only note missing'
out="$(grow_during_window "
	WORK='$WORK'; G5=0; ARMED=15; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p;/^fw()/,/^}/p' "$0")
	radio phy0 0 0 0 0 0 0 0 0 0 0 0 0
	fw phy0 30 90 40
")"
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_ONLY_UL_MUMIMO_TRIGGERS_SEEN' || fail 'firmware-only UL MU-MIMO evidence not reported'
G5=1

# 20. --enable-crxv turns group 5 on for the run and restores it.
printf '0\n' > "$WORK/debug/phy0/mt76/cr6608_rxv_group5"
radio phy0 0 0 0 0 0 0 0 0 0 0 0 0
out="$(grow_during_window "cp '$WORK/debug/phy0/mt76/cr6608_rxv_group5' '$WORK/crxv_during'" --enable-crxv)"
[ "$(cat "$WORK/crxv_during")" = 1 ] || fail 'enable-crxv did not enable group 5 during the window'
[ "$(cat "$WORK/debug/phy0/mt76/cr6608_rxv_group5")" = 0 ] || fail 'enable-crxv did not restore group 5'
[ "$(cat "$WORK/debug/phy0/mt76/muru_debug")" = 0 ] || fail 'muru_debug not restored in enable-crxv run'

# 21. Stats probe failure leaves muru_debug off.
printf 'firmware-stats-unavailable err=-110\n' > "$WORK/debug/phy0/mt76/muru_stats"
out="$(grow_during_window "cp '$WORK/debug/phy0/mt76/muru_debug' '$WORK/md_during'")"
[ "$(cat "$WORK/md_during")" = 0 ] || fail 'muru_debug was left on although the stats probe failed'
printf '%s\n' "$out" | grep -q 'status=stats-probe-failed' || fail 'stats probe failure not reported'
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_STATS_UNAVAILABLE' || fail 'unavailable stats reported as something else'
fw phy0 0 0 0

# 22. State changes inside the window invalidate the run: armed mask, group 5,
#     firmware reset counter.
resets 0
radio phy0 0 80 160 80 0 80 0 40 0 40 0 2
peer phy0 aa:bb:cc:dd:ee:01 1 40 40 0 0 40 0
peer phy0 aa:bb:cc:dd:ee:02 2 40 40 0 0 40 0
out="$(grow_during_window "printf 'SYS_RESET_COUNT: WM 1, WA 0\n' > '$WORK/debug/phy0/mt76/sys_recovery'")"
printf '%s\n' "$out" | grep -qx 'verdict=INVALID_STATE_CHANGED_DURING_WINDOW' || { printf '%s\n' "$out" >&2; fail 'firmware reset during window not invalidating'; }
printf '%s\n' "$out" | grep -q 'reason=.*firmware-reset-counter' || fail 'reset reason missing'
resets 0
out="$(grow_during_window "
	WORK='$WORK'; G5=1; ARMED=7; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p' "$0")
	radio phy0 0 160 320 160 0 160 0 80 0 80 0 2
")"
printf '%s\n' "$out" | grep -qx 'verdict=INVALID_STATE_CHANGED_DURING_WINDOW' || { printf '%s\n' "$out" >&2; fail 'armed mask change during window not invalidating'; }
printf '%s\n' "$out" | grep -q 'armed-mask-phy0' || fail 'armed mask reason missing'
radio phy0 0 80 160 80 0 80 0 40 0 40 0 2

# 23. Control phases: the ul phase must exceed idle/dl by the control factor.
phased() {
	# the hook performs this phase's growth inside its window; $1 is the
	# growth script, which sees the phase name in $1
	CR6608_UL_MURU_DEBUG_ROOT="$WORK/debug" CR6608_MURU_MASK_MODULE_PARAM="$mask_file" \
		sh "$TOOL" --auto --window 1 --with-firmware --phases idle,dl,ul --hook "$1"
}
out="$(run --phases bogus 2>&1)" && fail 'unknown phase accepted'
out="$(run --phases idle 2>&1)" && fail 'phase list without ul accepted'
# Same growth in every phase (a BSR-poll-like constant background): not exceeded.
cnt="$WORK/cnt"; printf '0\n' > "$cnt"
out="$(phased "
	WORK='$WORK'; G5=1; ARMED=15; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p;/^peer()/,/^}/p;/^fw()/,/^}/p' "$0")
	n=\$(( \$(cat '$cnt') + 1 )); printf '%s\n' \"\$n\" > '$cnt'
	radio phy0 0 \$((n*80)) \$((n*160)) \$((n*80)) 0 \$((n*80)) 0 \$((n*40)) 0 \$((n*40)) 0 2
	peer phy0 aa:bb:cc:dd:ee:01 1 \$((n*40)) \$((n*40)) 0 0 \$((n*40)) 0
	peer phy0 aa:bb:cc:dd:ee:02 2 \$((n*40)) \$((n*40)) 0 0 \$((n*40)) 0
	fw phy0 0 \$((n*40)) 0
")"
printf '%s\n' "$out" | grep -qx 'phases=idle,dl,ul window_seconds=1' || { printf '%s\n' "$out" >&2; fail 'phase order not normalised'; }
printf '%s\n' "$out" | grep -q '^phase=idle radio=phy0 ' || fail 'idle phase not measured'
printf '%s\n' "$out" | grep -q '^phase=dl radio=phy0 ' || fail 'dl phase not measured'
printf '%s\n' "$out" | grep -qx 'verdict=INCONCLUSIVE_CONTROL_PHASE_NOT_EXCEEDED' || { printf '%s\n' "$out" >&2; fail 'constant background passed the control phases'; }
# Growth only in the ul phase: observed.
printf '0\n' > "$cnt"
out="$(phased "
	WORK='$WORK'; G5=1; ARMED=15; SCHEMA=2
	$(sed -n '/^radio()/,/^}/p;/^peer()/,/^}/p;/^fw()/,/^}/p' "$0")
	[ \"\$1\" = ul ] || exit 0
	radio phy0 0 400 800 400 0 400 0 200 0 200 0 2
	peer phy0 aa:bb:cc:dd:ee:01 1 200 200 0 0 200 0
	peer phy0 aa:bb:cc:dd:ee:02 2 200 200 0 0 200 0
	fw phy0 0 200 0
")"
printf '%s\n' "$out" | grep -qx 'verdict=UL_OFDMA_DATA_MULTI_USER_OBSERVED_ON_DEVICE' || { printf '%s\n' "$out" >&2; fail 'ul-only growth did not pass the control phases'; }
printf '%s\n' "$out" | grep -qx 'firmware_corroboration=FIRMWARE_CORROBORATED' || fail 'phased run lost firmware corroboration'

# 24. Firmware identity line and argument validation.
printf '%s\n' "$out" | grep -q '^firmware_build=' || fail 'firmware_build line missing'
! CR6608_UL_MURU_DEBUG_ROOT="$WORK/debug" sh "$TOOL" --window abc >/dev/null 2>&1 || fail 'non-integer window accepted'
! CR6608_UL_MURU_DEBUG_ROOT="$WORK/debug" sh "$TOOL" --bogus >/dev/null 2>&1 || fail 'unknown argument accepted'

printf 'ul_mu_evidence_runtime=pass\n'
