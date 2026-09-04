#!/bin/sh
#
# Source contract for patches 09 (uniform per-peer cfg bits, boot-frozen
# vendor-parity B22 advertisement) and 10 (evidence honesty).
#
# Evidence these encode (upstream mt76 history and MediaTek's 25.12 feed):
#   abd80cf6  firmware latches MURU enable from the FIRST station record, so
#             every peer must carry the same cfg.*_en bits (MediaTek sends
#             muru_onoff bits to every peer, HE or not).
#   0099:1960 MediaTek ships mt7915 with all four bits on and does NOT
#             advertise HE PHY CAP2 B22 -> vendor parity is B22 off.
#   e5228343  the original guard: non-MT7915 chips must stay bit-identical
#             to upstream (mimo_ul_en on, ofdma_ul_en never set).
#   d33943ba  RXD group 5 is off by default on MT7915, so per-packet PHY
#             type (and therefore host TB attribution) is unavailable.
#   e4823530  upstream dropped the he_ext_su_cnt accumulation.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
P09="$ROOT/patches/zzzzzz-09-mt7915-cr6608-muru-uniform-cfg-vendor-parity.patch"
P10="$ROOT/patches/zzzzzz-10-mt7915-cr6608-muru-evidence-honesty.patch"

fail() {
	printf 'muru vendor parity contract failed: %s\n' "$*" >&2
	exit 1
}

GATE='MURU_SET_(BSRP_CTRL|SUTX|MUMIMO_CTRL|MANUAL_CFG|MU_DL_ACK_POLICY|TRIG_TYPE|20M_DYN_ALGO|PROT_FRAME_THR|CERT_MU_EDCA_OVERRIDE|ARB_OP_MODE)|mt7915_mcu_set_muru_cfg|mt7915_mcu_set_mu_dl_ack_policy|mt7915_mcu_set_mu_prot_frame_th|mt7915_mcu_set_cr6608_ul_muru'
for patch in "$P09" "$P10"; do
	[ -s "$patch" ] || fail "missing $(basename "$patch")"
	! grep -Eqi "mtd_(write|erase)|MTD_OPS_PLACE_OOB|$GATE" "$patch" ||
		fail "unsafe storage write or MediaTek-only MURU_CTRL sub-command in $(basename "$patch")"
	! grep -E '^\+' "$patch" | grep -Fq 'mt76_mcu_send_msg' ||
		fail "$(basename "$patch") introduces a new MCU command"
done

# --- patch 09: uniform cfg bits -------------------------------------------
# The per-peer downgrade must be a removal.
grep -Fq -e '-		if (!sta->deflink.he_cap.has_he)' "$P09" ||
	fail 'non-HE downgrade was not removed'
grep -Fq -e '-			mask &= CR6608_MURU_DL_MASK;' "$P09" ||
	fail 'non-HE DL-only masking was not removed'
! grep -Eq '^\+.*has_he.*mask &=|^\+.*mask &= CR6608_MURU_DL_MASK' "$P09" ||
	fail 'a per-peer cfg downgrade was re-added'
# mimo_ul_en follows the phy-wide bit for every chip, no per-peer B22 gate.
grep -Fq '+	muru->cfg.mimo_ul_en = !!(mask & CR6608_MURU_MUMIMO_UL);' "$P09" ||
	fail 'mimo_ul_en is not the phy-wide bit'
grep -Fq -e '-	muru->cfg.mimo_ul_en = !is_mt7915(&dev->mt76) &&' "$P09" ||
	fail 'old is_mt7915-gated mimo_ul_en not removed'
! grep -Eq '^\+.*muru->cfg.mimo_ul_en = true;' "$P09" ||
	fail 'per-peer late enable of mimo_ul_en re-added'
grep -Fq -e '-		state &= ~CR6608_MURU_MUMIMO_UL;' "$P09" ||
	fail 'per-peer UL bit clearing in the state byte not removed'
# Peer eligibility fields must still be filled from the peer's HE element.
for kept in 'mimo_ul.full_ul_mimo' 'ofdma_ul.t_frame_dur' 'ofdma_ul.mu_cascading' 'ofdma_ul.uo_ra'; do
	! grep -Eq "^-.*muru->$kept =" "$P09" || fail "peer eligibility field $kept was removed"
done
# Partial-bandwidth UL MU-MIMO stays off on mt7915 (a2838480).
! grep -Eq '^[-+].*partial_ul_mimo' "$P09" || fail 'partial_ul_mimo handling was touched'
# Non-MT7915 chips: exactly upstream (DL bits + UL MU-MIMO, no UL OFDMA).
grep -Fq '+		mask = CR6608_MURU_DL_MASK | CR6608_MURU_MUMIMO_UL;' "$P09" ||
	fail 'non-mt7915 mask is not upstream-identical'
grep -Fq -e '-		mask = CR6608_MURU_MASK;' "$P09" ||
	fail 'old non-mt7915 all-bits mask not removed'

# --- patch 09: boot-frozen, vendor-parity B22 ------------------------------
grep -Fq '+	bool cr6608_ul_mimo_advertise;' "$P09" || fail 'advertise flag missing'
grep -Fq '+module_param(cr6608_advertise_ul_mumimo, bool, 0444);' "$P09" ||
	fail 'advertise parameter missing or writable'
grep -Fq '+static bool cr6608_advertise_ul_mumimo;' "$P09" ||
	fail 'advertise parameter default is not vendor parity (off)'
grep -Fq '+	if (!is_mt7915(&dev->mt76) || dev->cr6608_ul_mimo_advertise)' "$P09" ||
	fail 'B22 gate does not use the boot-frozen flag'
grep -Fq -e '-	    (mt7915_cr6608_muru_mask(dev) & CR6608_MURU_MUMIMO_UL))' "$P09" ||
	fail 'live-mask B22 gate not removed'
! grep -Eq '^\+.*cr6608_ul_mimo_advertise =.*' "$P09" | grep -v register ||
	:
# The flag is derived from the boot mask AND the parameter, never the live mask.
awk '/\+\t\tdev->cr6608_ul_mimo_advertise =/{f=1} f{print} /cr6608_advertise_ul_mumimo;/{if(f)exit}' "$P09" |
	grep -Fq 'boot_mask & CR6608_MURU_MUMIMO_UL' ||
	fail 'advertise flag is not derived from the boot mask'
! awk '/\+\t\tdev->cr6608_ul_mimo_advertise =/{f=1} f{print} /cr6608_advertise_ul_mumimo;/{if(f)exit}' "$P09" |
	grep -Fq 'mt7915_cr6608_muru_mask' ||
	fail 'advertise flag reads the live mask'
grep -Fq 'ul_mimo_advertised=%u' "$P09" || fail 'advertisement state not exposed'
! grep -Fq 'fixed when the wiphy is registered' "$P09" ||
	{ grep -Fq -e '-	 * capabilities is fixed when the wiphy is registered' "$P09" ||
	  fail 'stale debugfs comment not corrected'; }

# --- patch 10: evidence honesty --------------------------------------------
grep -Fq '+	__dl_u32(he_ext_su_cnt);' "$P10" || fail 'he_ext_su_cnt accumulation missing'
grep -Fq 'firmware-stats-unavailable err=%d' "$P10" || fail 'stats failure not surfaced'
grep -Fq 'rxv_group5_enabled=%u' "$P10" || fail 'group-5 state not reported'
grep -Fq 'evidence=unavailable-crxv-disabled' "$P10" || fail 'unavailable evidence line missing'
grep -Fq 'MT_DMA_DCR0_RXD_G5_EN' "$P10" || fail 'group-5 bit not read from MT_DMA_DCR0'
# The opt-in knob must be gated, mutex-protected, and refuse values other than 0/1.
knob="$(awk '/static int mt7915_cr6608_rxv_group5_set/,/^\+}/' "$P10")"
[ -n "$knob" ] || fail 'group-5 knob not found'
for g in 'if (val > 1)' 'if (!dev->cr6608_ul_muru_allowed)' 'mutex_lock(&dev->mt76.mutex);' 'MT76_STATE_RUNNING'; do
	printf '%s\n' "$knob" | grep -Fq "$g" || fail "group-5 knob lacks guard: $g"
done
printf '%s\n' "$knob" | grep -Fq 'can stall RX' || fail 'group-5 knob does not warn about d33943ba'
grep -Fq 'debugfs_create_file("cr6608_rxv_group5", 0600' "$P10" || fail 'knob not registered as 0600'
# The knob must never be enabled by any profile or default.
! grep -rqs 'cr6608_rxv_group5' "$ROOT/files/etc" "$ROOT/profiles" ||
	fail 'a profile or default enables the group-5 knob'

# --- logging honesty --------------------------------------------------------
for patch in "$P09" "$P10"; do
	! grep -E '^\+.*(dev_info|dev_warn|dev_crit|seq_printf|seq_puts|MODULE_PARM_DESC)' "$patch" |
		grep -Eiq 'works|supported officially|certified|proven' ||
		fail "a log string in $(basename "$patch") overclaims"
done

printf 'muru_vendor_parity_contract=pass\n'
