#!/bin/sh
#
# Source contract for patch 11 (record serialisation and in-flight fault
# attribution), patch 12 (upstream e59324380042 backport), patch 13
# (recovery-lifecycle attribution) and patch 14 (attribution accounting v2).
#
# Evidence these encode:
#   mac80211.c mt76_sta_state   only sta_add/sta_remove hold dev->mt76.mutex;
#                               ASSOC/AUTHORIZE/DISASSOC events do not.
#   mt7996/main.c, mt7996/mac.c the upstream precedent: sta_event and
#                               sta_rc_work both hold dev->mt76.mutex.
#   dma.c / mcu.c               MT76_MCU_RESET makes a queued send return
#                               -ENOMEM and wakes the response wait early, so
#                               a STA_REC failure inside a pending recovery is
#                               that recovery's, not scheduler evidence.
#   e59324380042                dcm_rx_max_nss assigned twice, dcm_max_ru
#                               never written (mt76 master, not in 39c960c3).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
P11="$ROOT/patches/zzzzzz-11-mt7915-cr6608-muru-record-serialisation.patch"
P12="$ROOT/patches/zzzzzz-12-mt7915-cr6608-muru-he-dcm-max-ru-upstream-e5932438.patch"
P13="$ROOT/patches/zzzzzz-13-mt7915-cr6608-muru-recovery-lifecycle.patch"
P14="$ROOT/patches/zzzzzz-14-mt7915-cr6608-muru-ul-attribution-v2.patch"

fail() {
	printf 'muru record serialisation contract failed: %s\n' "$*" >&2
	exit 1
}

GATE='MURU_SET_(BSRP_CTRL|SUTX|MUMIMO_CTRL|MANUAL_CFG|MU_DL_ACK_POLICY|TRIG_TYPE|20M_DYN_ALGO|PROT_FRAME_THR|CERT_MU_EDCA_OVERRIDE|ARB_OP_MODE)|mt7915_mcu_set_muru_cfg|mt7915_mcu_set_mu_dl_ack_policy|mt7915_mcu_set_mu_prot_frame_th|mt7915_mcu_set_cr6608_ul_muru'
for patch in "$P11" "$P12" "$P13" "$P14"; do
	[ -s "$patch" ] || fail "missing $(basename "$patch")"
	! grep -Eqi "mtd_(write|erase)|MTD_OPS_PLACE_OOB|$GATE" "$patch" ||
		fail "unsafe storage write or MediaTek-only MURU_CTRL sub-command in $(basename "$patch")"
	! grep -E '^\+' "$patch" | grep -Fq 'mt76_mcu_send_msg' ||
		fail "$(basename "$patch") introduces a new MCU command"
	! grep -E '^\+' "$patch" | grep -Eq 'IEEE80211_HE_(MAC|PHY)_CAP[0-9]_[A-Z_0-9]+' ||
		fail "$(basename "$patch") touches a capability advertisement"
done

hunk_of() {
	# print the diff hunks of file $2 in patch $1 whose header names $3
	awk -v file="$2" -v fn="$3" '
		/^diff --git/ { infile = ($0 ~ "b/" file "$") }
		infile && /^@@/ { inhunk = ($0 ~ fn) }
		infile && inhunk { print }
	' "$1"
}

# --- 1. serialisation ------------------------------------------------------
ev="$(hunk_of "$P11" mt7915/main.c mt7915_mac_sta_event)"
[ -n "$ev" ] || fail 'sta_event hunk not found'
printf '%s\n' "$ev" | grep -Fq '+	mutex_lock(&dev->mt76.mutex);' ||
	fail 'sta_event does not take dev->mt76.mutex'
printf '%s\n' "$ev" | grep -Fq '+	mutex_unlock(&dev->mt76.mutex);' ||
	fail 'sta_event does not release dev->mt76.mutex'
printf '%s\n' "$ev" | grep -Fq -e '-		mutex_lock(&dev->mt76.mutex);' ||
	fail 'inner DISASSOC lock was not folded into the outer critical section'
for st in CONN_STATE_CONNECT CONN_STATE_PORT_SECURE CONN_STATE_DISCONNECT; do
	printf '%s\n' "$ev" | grep -Eq "^\+.*WRITE_ONCE\(msta->cr6608_conn_state,( |$)" ||
		fail 'conn_state is not written with WRITE_ONCE'
	printf '%s\n' "$ev" | grep -Fq "$st" || fail "sta_event lost $st"
done
# PORT_SECURE is still recorded only after a successful send.
printf '%s\n' "$ev" | awk '/CONN_STATE_PORT_SECURE,$/{f=1} f&&/if \(!ret\)/{ok=1} END{exit !ok}' ||
	fail 'PORT_SECURE recorded even when the MCU rejected it'
# The events must not return from inside the critical section: no added
# return between the lock and the unlock.
printf '%s\n' "$ev" | awk '
	/^\+\tmutex_lock\(&dev->mt76.mutex\);/ { inside = 1; next }
	/^\+\tmutex_unlock\(&dev->mt76.mutex\);/ { inside = 0; next }
	inside && /^\+[\t ]+return / { bad = 1 }
	END { exit bad }' ||
	fail 'sta_event returns while holding the mutex'

rc="$(hunk_of "$P11" mt7915/mac.c mt7915_mac_sta_rc_work)"
[ -n "$rc" ] || fail 'rc_work hunk not found'
printf '%s\n' "$rc" | grep -Fq '+	mutex_lock(&dev->mt76.mutex);' ||
	fail 'rc_work replay is not serialised under dev->mt76.mutex'
printf '%s\n' "$rc" | grep -Fq '+	mutex_unlock(&dev->mt76.mutex);' ||
	fail 'rc_work does not release dev->mt76.mutex'
printf '%s\n' "$rc" | grep -Fq 'READ_ONCE(msta->cr6608_conn_state)' ||
	fail 'replay does not re-read conn_state under the mutex'
printf '%s\n' "$rc" | grep -Fq 'mt7915_mcu_add_sta(dev, vif, sta, state,' ||
	fail 'replay no longer reuses the standard STA_REC_UPDATE path'

# --- 4. parking instead of dropping ---------------------------------------
printf '%s\n' "$rc" | grep -Fq 'test_bit(MT76_RESET, &peer_phy->state)' ||
	fail 'replay ignores the peer phy reset state'
printf '%s\n' "$rc" | grep -Fq 'msta->changed |= CR6608_RC_MURU_REFRESH;' ||
	fail 'a replay that meets a reset window is not parked'
printf '%s\n' "$rc" | grep -Fq 'list_add_tail(&msta->rc_list,' ||
	fail 'parked replay is not put back on sta_rc_list'
printf '%s\n' "$rc" | grep -Fq 'mt7915_recovery_pending(dev)' ||
	fail 'a replay failure inside a pending recovery is not parked'
rel="$(hunk_of "$P11" mt7915/main.c mt7915_reconfig_tx_release)"
printf '%s\n' "$rel" | grep -Fq '+	if (state == MT7915_RECONFIG_TX_RELEASED)' &&
printf '%s\n' "$rel" | grep -Fq '+		ieee80211_queue_work(mt76_hw(dev), &dev->rc_work);' ||
	fail 'band release does not run the parked replays'
grep -Fq -e '-static bool mt7915_recovery_pending(struct mt7915_dev *dev)' "$P11" &&
grep -Fq '+bool mt7915_recovery_pending(struct mt7915_dev *dev)' "$P11" ||
	fail 'mt7915_recovery_pending is not exported to the MCU path'

# --- 2. no latch on host mask changes; recovery owns in-flight failures ---
add="$(hunk_of "$P11" mt7915/mcu.c '__mt7915_mcu_add_sta|@@ out:$')"
[ -n "$add" ] || fail 'add_sta hunk not found'
# The two mask-change latches are removed and no latch is added; the one
# surviving latch (send failed with no recovery pending) is untouched code,
# which is why it does not appear in the diff at all.
removed_latches="$(printf '%s\n' "$add" | grep -c '^-.*mt7915_cr6608_muru_fault_latch(dev);' || true)"
added_latches="$(printf '%s\n' "$add" | grep -c '^+.*mt7915_cr6608_muru_fault_latch(dev);' || true)"
[ "$removed_latches" -eq 2 ] || fail "expected the two mask-change latches removed, found $removed_latches"
[ "$added_latches" -eq 0 ] || fail "a latch was added to the station-record path"
printf '%s\n' "$add" | grep -Fq '+rebuild:' &&
printf '%s\n' "$add" | grep -Fq 'goto rebuild;' &&
printf '%s\n' "$add" | grep -Fq 'CR6608_MURU_STA_REC_REBUILDS' ||
	fail 'a record overtaken before the send is not rebuilt from the live mask'
! printf '%s\n' "$add" | grep -Eq '^\+.*return -ECANCELED;' ||
	fail 'a stale record still fails the association'
[ "$(printf '%s\n' "$add" | grep -c '^+.*mt7915_cr6608_muru_queue_refresh(dev, msta);')" -eq 2 ] ||
	fail 'stale records are not re-queued for a live replay'
printf '%s\n' "$add" | grep -Fq '+		} else if (test_bit(MT76_MCU_RESET, &dev->mphy.state) ||' &&
printf '%s\n' "$add" | grep -Fq '+			   mt7915_recovery_pending(dev)) {' ||
	fail 'a STA_REC failure inside a pending recovery still spends the latch'
# The failure-with-no-recovery-pending branch (latch + forced recovery) is
# untouched: nothing removes its recovery call, and the new branch only
# counts and warns.
[ "$(printf '%s\n' "$add" | grep -c '^-.*mt7915_mcu_schedule_full_recovery(dev);' || true)" -eq 2 ] ||
	fail 'expected exactly the two mask-change forced recoveries removed'
! printf '%s\n' "$add" | grep -q '^+.*mt7915_mcu_schedule_full_recovery(dev);' ||
	fail 'a forced recovery was added to the station-record path'
printf '%s\n' "$add" | grep -Fq 'inside a pending recovery; attributed to that recovery' ||
	fail 'in-flight failure is not reported as attributed to the pending recovery'
printf '%s\n' "$add" | grep -Fq 'atomic_inc(&dev->cr6608_ul_muru_sta_rec_stale);' ||
	fail 'stale records are not counted'
grep -Fq '+	seq_printf(file, "sta_rec_stale=%d\n",' "$P11" ||
	fail 'sta_rec_stale is not exposed in cr6608_ul_muru_state'
pr="$(hunk_of "$P11" mt7915/mcu.c mt7915_mcu_parse_response)"
printf '%s\n' "$pr" | grep -Fq '+		if (cmd == MCU_EXT_CMD(STA_REC_UPDATE) &&' &&
printf '%s\n' "$pr" | grep -Fq '+		    !test_bit(MT76_MCU_RESET, &dev->mphy.state)) {' ||
	fail 'a STA_REC timeout woken by a pending reset still latches'

# --- 3. converge after every verified partial reset ----------------------
rw="$(hunk_of "$P11" mt7915/mac.c 'mt7915_mac_reset_work|@@ restart_check:$')"
printf '%s\n' "$rw" | grep -Fq -e '-		if (muru_rearmed) {' ||
	fail 'partial-reset refresh is still gated on a successful re-arm'
printf '%s\n' "$rw" | grep -Fq '"partial reset without re-arm");' ||
	fail 'partial reset without re-arm does not replay the records'
printf '%s\n' "$rw" | grep -Fq '"partial reset re-arm" :' ||
	fail 'partial reset re-arm reason lost'
# Still exactly one refresh call site in mac.c, still not in the full-reset path.
mac_calls="$(awk '/^diff --git a\/mt7915\/mac.c/{f=1;next} /^diff --git/{f=0} f' "$P11" |
	grep -c '^+.*mt7915_cr6608_muru_refresh_stations(dev,' || true)"
[ "$mac_calls" = 1 ] || fail "expected exactly one refresh call in mac.c, found $mac_calls"
! printf '%s\n' "$rw" | grep -Fq 'ieee80211_restart_hw' ||
	fail 'refresh hunk reaches into the full-reset path'

# --- helper ---------------------------------------------------------------
grep -Fq '+void mt7915_cr6608_muru_queue_refresh(struct mt7915_dev *dev,' "$P11" ||
	fail 'queue_refresh helper missing'
grep -Fq '+	ieee80211_queue_work(mt76_hw(dev), &dev->rc_work);' "$P11" ||
	fail 'queue_refresh does not run rc_work'

# --- patch 12: verbatim upstream backport ---------------------------------
grep -Fq 'e59324380042cb2f0a6ab0405f5950ffead97003' "$P12" ||
	fail 'patch 12 does not cite the upstream commit'
files="$(grep -E '^\+\+\+ b/' "$P12" | sed 's|^+++ b/||' | sort | tr '\n' ' ')"
[ "$files" = 'mt76_connac_mcu.c mt7915/mcu.c ' ] || fail "patch 12 touches unexpected files: $files"
[ "$(grep -c '^-	he->dcm_rx_max_nss =$' "$P12")" -eq 2 ] ||
	fail 'patch 12 does not remove the duplicate dcm_rx_max_nss assignment twice'
[ "$(grep -c '^+	he->dcm_max_ru =$' "$P12")" -eq 2 ] ||
	fail 'patch 12 does not write dcm_max_ru twice'
[ "$(grep -Ec '^[-+][^-+]' "$P12")" -eq 4 ] || fail 'patch 12 changes more than the two lines'


# --- patch 13: recovery-lifecycle attribution ------------------------------
rs="$(hunk_of "$P13" mt7915/mac.c mt7915_reset)"
[ -n "$rs" ] || fail 'mt7915_reset hunk not found in patch 13'
printf '%s\n' "$rs" | grep -Fq '+	else if (claim_tx)' &&
printf '%s\n' "$rs" | grep -Fq 'muru_disarmed = mt7915_cr6608_muru_disarm(dev);' ||
	fail 'mt7915_reset still disarms on handshake acknowledgements'
printf '%s\n' "$rs" | grep -Fq '!READ_ONCE(dev->cr6608_operator_reset))' ||
	fail 'operator fw_ser reset still spends the latch in mt7915_reset'
grep -Fq '+		WRITE_ONCE(dev->cr6608_operator_reset, true);' "$P13" ||
	fail 'fw_ser full reset is not flagged as operator-initiated'
grep -Fq '+			WRITE_ONCE(dev->cr6608_operator_reset, false);' "$P13" ||
	fail 'operator flag is not cleared at the full-reset commit'
# strikes only when exercised
grep -Fq '+	atomic_t cr6608_muru_exercised;' "$P13" || fail 'exercised flag missing'
grep -Fq '+	atomic_set(&dev->cr6608_muru_exercised, 1);' "$P13" ||
	fail 'an acknowledged UL-bearing record does not mark the scheduler exercised'
grep -Fq '+		atomic_set(&dev->cr6608_muru_exercised, 0);' "$P13" ||
	fail 're-arm does not clear the exercised flag'
grep -Fq '+	if (!READ_ONCE(dev->cr6608_muru_last_disarm_exercised)) {' "$P13" ||
	fail 'report_disarm does not gate the strike on the exercised flag'
# reset_work entry no longer increments strikes directly
grep -Fq -e '-		atomic_inc(&dev->cr6608_muru_strikes);' "$P13" ||
	fail 'reset_work entry still charges a strike unconditionally'
# host-initiated recoveries never strike
grep -Fq '+void __mt7915_mcu_schedule_full_recovery(struct mt7915_dev *dev,' "$P13" &&
grep -Fq 'mt7915_mcu_schedule_full_recovery_host(struct mt7915_dev *dev)' "$P13" ||
	fail 'host-initiated recovery variant missing'
[ "$(grep -c '^+.*mt7915_mcu_schedule_full_recovery_host(' "$P13")" -ge 4 ] ||
	fail 'the three host-initiated sites do not use the no-strike variant'
grep -Fq -e '-			mt7915_mcu_schedule_full_recovery(dev);' "$P13" ||
	fail 'host-initiated site not converted'
# decay + replay no longer keyed on band 0
grep -Fq -e '-		if (mphy == &phy->dev->mphy)' "$P13" || fail 'strike decay still band-0 only'
grep -Fq '+	if (mt7915_recovery_pending(dev))' "$P13" || fail 'strike decay not keyed on recovery state'
grep -Fq -e '-				test_bit(MT76_RESET, &dev->mphy.state) ||' "$P13" ||
	fail 'replay still parked on band 0 sticky bit'
grep -Fq '+	if (!list_empty(&phy->dev->sta_rc_list) &&' "$P13" ||
	fail 'parked replays are not re-kicked from mac_work'
# mask writer: ceiling first, validated against the ceiling, old & val
grep -Fq '+	if (val & ~(atomic_read(&dev->cr6608_muru_ceiling) & CR6608_MURU_MASK))' "$P13" ||
	fail 'mask writer does not validate against the ceiling'
printf '%s\n' "$(hunk_of "$P13" mt7915/debugfs.c mt7915_cr6608_muru_mask_set)" |
	awk '/^\+\tmt7915_cr6608_muru_lower_ceiling\(dev, \(u8\)val\);/{c=NR} /^[+ ]\t\told = mt7915_cr6608_muru_mask\(dev\);/{l=NR} END{exit !(c && l && c < l)}' ||
	fail 'mask writer does not lower the ceiling before the live mask'
grep -Fq '+					  old & (int)val);' "$P13" || fail 'mask writer can raise a disarmed live mask'
# firmware statistics enable re-sent after a reload
grep -Fq '+		int r = mt7915_mcu_muru_debug_set(dev, true);' "$P13" ||
	fail 'muru_debug is not re-applied after firmware restart'
# wording: no promise of an unconditional re-arm
! grep -Eq '^\+.*it re-arms after a verified reset' "$P13" || fail 'unconditional re-arm promise remains'
grep -Fq '"exercised_since_rearm=%d\n"' "$P13" || fail 'exercised flag not exposed'

# --- patch 14: attribution accounting v2 ----------------------------------
ac="$(hunk_of "$P14" mt7915/mac.c mt7915_cr6608_ul_account_tb)"
[ -n "$ac" ] || fail 'account_tb hunk not found in patch 14'
grep -Fq '+			    __le16 fc, bool have_ts)' "$P14" || fail 'account_tb lacks fc/have_ts'
grep -Fq '+	if (status->flag & RX_FLAG_FAILED_FCS_CRC)' "$P14" || fail 'no FCS guard'
grep -Fq '+	new_ppdu = !have_ts || !msta->cr6608_ul.tb_ppdu ||' "$P14" || fail 'no per-PPDU dedupe'
grep -Fq '+		phy->cr6608_ul.tb_no_timestamp++;' "$P14" || fail 'no group-2 guard'
grep -Fq '+	bool is_data = fc && ieee80211_is_data_present(fc);' "$P14" || fail 'no data split'
grep -Fq 'ieee80211_is_qos_nullfunc(fc)' "$P14" || fail 'QoS-Null not recognised'
grep -Fq '+static void mt7915_cr6608_ul_credit_mumimo(struct mt7915_phy *phy, u16 idx)' "$P14" &&
grep -Fq 'phy, phy->cr6608_ul.group_wcid[0]);' "$P14" || fail 'first peer of a MU-MIMO group not credited'
grep -Fq 'mt76_wcid_ptr(phy->dev, idx)' "$P14" || fail 'peer lookup does not use the RCU wcid table'
grep -Fq 'hweight8(phy->cr6608_ul.group_data_mask) >= 2' "$P14" || fail 'data groups not counted on two data peers'
for key in he_tb_mpdu he_tb_data_ppdu he_tb_nulldata_ppdu he_tb_fc_unknown he_tb_no_timestamp \
	   ul_ofdma_multi_user_data_ppdus ul_mumimo_multi_user_data_ppdus; do
	grep -Fq "\"$key=%u\\n\"" "$P14" || fail "debugfs key $key missing"
done
[ "$(grep -c '^+	seq_puts(file, "schema=2\\n");' "$P14")" -eq 2 ] || fail 'schema=2 not on both nodes'
grep -Fq 'semantics=firmware-txcmd-side-he-trigger-accounting-by-solicited-allocation;rx-decoding-not-implied' "$P14" ||
	fail 'muru_stats lacks the source-semantics footer'
for k in ul_hetrig_su ul_hetrig_gtr16ru ul_hetrig_4mu dl_he_ext_su; do
	grep -Fq "__muru_kv($k, ${k}_cnt);" "$P14" || fail "muru_stats key $k missing"
done
# The RX hot-path change stays gated on HE TB + armed UL bit (call site unchanged
# except for the two new arguments).
cs="$(hunk_of "$P14" mt7915/mac.c mt7915_mac_fill_rx)"
printf '%s\n' "$cs" | grep -Fq ' 			     CR6608_MURU_UL_MASK) &&' &&
printf '%s\n' "$cs" | grep -Fq ' 			    mphy->chandef.chan)' ||
	fail 'call-site gate lost'
! grep -Eq '^\+.*mt76_mcu_send_msg|^\+.*MCU_EXT_CMD\(' "$P14" || fail 'patch 14 sends an MCU command'

printf 'muru_record_serialisation_contract=pass\n'
