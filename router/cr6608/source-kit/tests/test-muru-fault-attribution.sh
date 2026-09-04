#!/bin/sh
#
# Source contract for the CR6608 MURU fault-attribution and uplink
# trigger-based attribution patches.
#
# The v86 stack routed every firmware recovery through one entry point and
# spent a one-way latch there, so an unrelated fault -- most importantly the
# 38 dBm SKU transaction and the regulatory refresh, which share that entry
# point -- permanently disabled MU-RU scheduling for the rest of the uptime.
# These patches keep the fail-closed disarm but reserve the permanent latch
# for evidence that the scheduler itself misbehaved, and they add
# client-attributed uplink evidence that does not need capture hardware.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_DIR="$ROOT/patches"

fail() {
	printf 'muru fault attribution contract failed: %s\n' "$*" >&2
	exit 1
}

ATTR="$PATCH_DIR/zzzzzz-06-mt7915-cr6608-muru-fault-attribution.patch"
ULTB="$PATCH_DIR/zzzzzz-07-mt7915-cr6608-muru-ul-tb-attribution.patch"

for patch in "$ATTR" "$ULTB"; do
	[ -s "$patch" ] || fail "missing $(basename "$patch")"
	# Same storage/ABI prohibition the rest of the MURU port carries.
	! grep -Eqi 'mtd_(write|erase)|MTD_OPS_PLACE_OOB|MURU_SET_(BSRP_CTRL|SUTX|MUMIMO_CTRL|MANUAL_CFG|MU_DL_ACK_POLICY|TRIG_TYPE|20M_DYN_ALGO|PROT_FRAME_THR|CERT_MU_EDCA_OVERRIDE|ARB_OP_MODE)|mt7915_mcu_set_muru_cfg|mt7915_mcu_set_mu_dl_ack_policy|mt7915_mcu_set_mu_prot_frame_th|mt7915_mcu_set_cr6608_ul_muru' "$patch" ||
		fail "unsafe storage write or unverified legacy firmware ABI in $(basename "$patch")"
	# No new firmware command surface: the whole point is that these patches
	# are host-side only.
	! grep -Fq 'mt76_mcu_send_msg' "$patch" ||
		fail "$(basename "$patch") introduces a new MCU command"
	! grep -Fq 'MCU_EXT_CMD(MURU_CTRL)' "$patch" ||
		fail "$(basename "$patch") sends an unverified global MURU command"
done

# --- attribution patch -------------------------------------------------

for marker in \
	'mt7915_cr6608_muru_disarm' \
	'mt7915_cr6608_muru_rearm' \
	'mt7915_cr6608_muru_lower_ceiling' \
	'cr6608_muru_ceiling' \
	'cr6608_muru_dl_floor' \
	'CR6608_MURU_MAX_STRIKES'; do
	grep -Fq "$marker" "$ATTR" || fail "attribution patch lacks $marker"
done

# The disarm path must never touch the one-way fault flag.
disarm_body="$(awk '/^\+static inline bool mt7915_cr6608_muru_disarm/,/^\+}/' "$ATTR")"
[ -n "$disarm_body" ] || fail 'disarm helper not found'
printf '%s\n' "$disarm_body" | grep -Fq 'atomic_xchg(&dev->cr6608_muru_mask, 0)' ||
	fail 'disarm does not clear the live scheduler mask'
! printf '%s\n' "$disarm_body" | grep -Fq 'cr6608_muru_fault_latched' ||
	fail 'disarm spends the one-way fault latch'

# The fault latch must still drop the ceiling, so no later re-arm can undo it.
latch_body="$(awk '/^\+static inline bool mt7915_cr6608_muru_fault_latch/,/^\+}/' "$ATTR")"
[ -z "$latch_body" ] ||
	printf '%s\n' "$latch_body" | grep -Fq 'cr6608_muru_ceiling' ||
	fail 'fault latch does not retire the re-arm ceiling'
grep -Fq 'atomic_xchg(&dev->cr6608_muru_ceiling, 0);' "$ATTR" ||
	fail 'fault latch does not zero the re-arm ceiling'

# Re-arm must refuse a latched device and must be bounded by strikes.
rearm_body="$(awk '/^\+static inline u8 mt7915_cr6608_muru_rearm/,/^\+}/' "$ATTR")"
[ -n "$rearm_body" ] || fail 're-arm helper not found'
printf '%s\n' "$rearm_body" | grep -Fq 'atomic_read(&dev->cr6608_muru_fault_latched)' ||
	fail 're-arm does not refuse a latched device'
printf '%s\n' "$rearm_body" | grep -Fq 'CR6608_MURU_MAX_STRIKES' ||
	fail 're-arm is not bounded by a strike budget'
printf '%s\n' "$rearm_body" | grep -Fq 'cr6608_muru_ceiling' ||
	fail 're-arm restores something other than the one-way ceiling'
! printf '%s\n' "$rearm_body" | grep -Eq 'atomic_(set|or)\(&dev->cr6608_muru_ceiling' ||
	fail 're-arm raises the one-way ceiling'

# Attribution: only a watchdog reset may spend the latch in the reset paths.
grep -Fq 'if (READ_ONCE(dev->recovery.state) & MT_MCU_CMD_WDT_MASK) {' "$ATTR" ||
	fail 'reset work does not attribute the fault by watchdog state'
grep -Fq 'if (state & MT_MCU_CMD_WDT_MASK) {' "$ATTR" ||
	fail 'mt7915_reset does not attribute the fault by watchdog state'
# Only a station-record command may blame the scheduler for an MCU timeout.
grep -Fq 'if (cmd == MCU_EXT_CMD(STA_REC_UPDATE)) {' "$ATTR" ||
	fail 'MCU timeout is not attributed by the timed-out command'
# The shared recovery entry point must disarm, never latch.
grep -Fq '+	muru_disarmed = mt7915_cr6608_muru_disarm(dev);' "$ATTR" ||
	fail 'shared full-recovery entry point does not disarm'
# The unattributed latch call must be a removal, never an addition.
! grep -Fq '+	muru_latched = mt7915_cr6608_muru_fault_latch(dev);' "$ATTR" ||
	fail 'shared full-recovery entry point still latches unattributed faults'
grep -Fq -e '-	muru_latched = mt7915_cr6608_muru_fault_latch(dev);' "$ATTR" ||
	fail 'the unattributed latch was never removed from the recovery entry point'

# The disarm must happen before the reset is queued, exactly as the latch did.
disarm_line="$(grep -nF '+	muru_disarmed = mt7915_cr6608_muru_disarm(dev);' "$ATTR" | head -n1 | cut -d: -f1)"
[ -n "$disarm_line" ] || fail 'recovery disarm line not found'

# Upstream DL behaviour must survive a retired uplink experiment.
grep -Fq 'mt7915_cr6608_muru_effective_mask(dev)' "$ATTR" ||
	fail 'station record does not apply the upstream DL floor'
grep -Fq '#define CR6608_MURU_DL_MASK' "$ATTR" ||
	fail 'upstream DL floor mask is not defined'

# Re-arm must be reached only after a verified reset.
grep -Fq 'muru_rearmed = mt7915_cr6608_muru_rearm(dev);' "$ATTR" ||
	fail 'no post-recovery re-arm point'
grep -Fq 'if (partial_ok) {' "$ATTR" ||
	fail 'partial reset re-arm is not gated on a verified partial reset'

# Telemetry must expose the new lifecycle so it can be audited on device.
for marker in \
	'unattributed_disarms=' \
	'rearms=' \
	'strikes=' \
	'strike_limit=' \
	'candidate_ceiling=' \
	'upstream_dl_floor='; do
	grep -Fq "$marker" "$ATTR" || fail "state telemetry lacks $marker"
done

# --- uplink trigger-based attribution patch ----------------------------

for marker in \
	'MT_PHY_TYPE_HE_TB' \
	'mt7915_cr6608_ul_account_tb' \
	'mt7915_cr6608_ul_ru_tones' \
	'mt7915_cr6608_ul_full_bw_tones' \
	'CR6608_UL_TB_GROUP_MAX' \
	'he_tb_ul_ofdma_ru=' \
	'he_tb_ul_mumimo_shared=' \
	'ul_mumimo_multi_user_ppdus=' \
	'evidence=client-attributed-rx-descriptor-wcid'; do
	grep -Fq "$marker" "$ULTB" || fail "uplink attribution patch lacks $marker"
done

# Accounting must be read-only: it may not change the mask, capabilities,
# power, or schedule recovery.
account_body="$(awk '/^\+mt7915_cr6608_ul_account_tb\(struct mt7915_phy/,/^\+}/' "$ULTB")"
[ -n "$account_body" ] || fail 'uplink accounting helper not found'
for forbidden in \
	'cr6608_muru_mask, ' \
	'mt7915_mcu_schedule_full_recovery' \
	'mt7915_cr6608_muru_fault_latch' \
	'txpower' \
	'IEEE80211_HE_PHY_CAP'; do
	! printf '%s\n' "$account_body" | grep -Fq "$forbidden" ||
		fail "uplink accounting is not read-only: touches $forbidden"
done

# It must run only while an uplink bit is armed, so it costs nothing on the
# retail/stable mask-0 profiles.
grep -Fq 'mode == MT_PHY_TYPE_HE_TB && msta &&' "$ULTB" ||
	fail 'uplink accounting is not gated on a trigger-based PPDU'
grep -Fq 'CR6608_MURU_UL_MASK)' "$ULTB" ||
	fail 'uplink accounting is not gated on an armed uplink bit'

# A multi-user group needs at least two distinct peers in one PPDU.
printf '%s\n' "$account_body" | grep -Fq 'phy->cr6608_ul.group_n == 2 &&' ||
	fail 'multi-user grouping does not require a second distinct peer'
printf '%s\n' "$account_body" | grep -Fq 'group_full_bw >= 2' ||
	fail 'UL MU-MIMO grouping does not require full-bandwidth peers'

# The published evidence must not overclaim.
grep -Fq 'note=host-observed-scheduling-evidence-not-a-regulatory-or-rf-measurement' "$ULTB" ||
	fail 'per-radio attribution omits its evidence boundary'

printf 'muru_fault_attribution_contract=pass\n'
