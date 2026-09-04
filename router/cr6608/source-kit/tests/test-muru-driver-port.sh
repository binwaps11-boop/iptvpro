#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_DIR="$ROOT/patches"

fail() {
	printf 'muru driver port contract failed: %s\n' "$*" >&2
	exit 1
}

STATE="$PATCH_DIR/zzzzzz-01-mt7915-cr6608-muru-mask-state.patch"
INIT="$PATCH_DIR/zzzzzz-02-mt7915-cr6608-muru-mask-init.patch"
MAC="$PATCH_DIR/zzzzzz-03-mt7915-cr6608-muru-fault-latch-mac.patch"
DEBUG="$PATCH_DIR/zzzzzz-04-mt7915-cr6608-muru-telemetry-debugfs.patch"
MCU="$PATCH_DIR/zzzzzz-05-mt7915-cr6608-muru-mcu-response.patch"

for patch in "$STATE" "$INIT" "$MAC" "$DEBUG" "$MCU"; do
	[ -s "$patch" ] || fail "missing $(basename "$patch")"
	! grep -Eqi 'mtd_(write|erase)|MTD_OPS_PLACE_OOB|MURU_SET_(BSRP_CTRL|SUTX|MUMIMO_CTRL|MANUAL_CFG|MU_DL_ACK_POLICY|TRIG_TYPE|20M_DYN_ALGO|PROT_FRAME_THR|CERT_MU_EDCA_OVERRIDE|ARB_OP_MODE)|mt7915_mcu_set_muru_cfg|mt7915_mcu_set_mu_dl_ack_policy|mt7915_mcu_set_mu_prot_frame_th|mt7915_mcu_set_cr6608_ul_muru' "$patch" ||
		fail "unsafe storage write or unverified legacy firmware ABI in $(basename "$patch")"
done

for marker in \
	'CR6608_MURU_OFDMA_DL.*BIT\(0\)' \
	'CR6608_MURU_OFDMA_UL.*BIT\(1\)' \
	'CR6608_MURU_MUMIMO_DL.*BIT\(2\)' \
	'CR6608_MURU_MUMIMO_UL.*BIT\(3\)'; do
	grep -Eq "$marker" "$STATE" || fail "state patch lacks $marker"
done
for marker in \
	'atomic_xchg(&dev->cr6608_muru_mask, 0)' \
	'atomic_xchg(&dev->cr6608_muru_fault_latched, 1)' \
	'cr6608_ul_muru_sta_rec_attempted' \
	'cr6608_ul_muru_sta_rec_response_ok' \
	'cr6608_ul_muru_sta_rec_failed' \
	'cr6608_ul_muru_sta_rec_timeout'; do
	grep -Fq "$marker" "$STATE" || fail "state patch lacks $marker"
done

mask_clear_line="$(grep -nF 'atomic_xchg(&dev->cr6608_muru_mask, 0);' "$STATE" | grep -F ':+' | cut -d: -f1)"
fault_arbiter_line="$(grep -nF 'atomic_xchg(&dev->cr6608_muru_fault_latched, 1)' "$STATE" | grep -F ':+' | cut -d: -f1)"
fault_count_line="$(grep -nF 'atomic_inc(&dev->cr6608_muru_fault_latches);' "$STATE" | grep -F ':+' | cut -d: -f1)"
[ -n "$mask_clear_line" ] && [ -n "$fault_arbiter_line" ] &&
	[ -n "$fault_count_line" ] && [ "$mask_clear_line" -lt "$fault_arbiter_line" ] &&
	[ "$fault_arbiter_line" -lt "$fault_count_line" ] ||
	fail 'fault latch is not a one-way flag after the atomic mask clear'
! grep -Fq '!atomic_xchg(&dev->cr6608_muru_mask, 0)' "$STATE" ||
	fail 'a prior kill-switch clear can still suppress recording the first real fault'

grep -Fq 'module_param(cr6608_muru_mask, byte, 0444);' "$INIT" ||
	fail 'read-only MediaTek-compatible bitmap parameter is missing'
grep -Fq 'IEEE80211_HE_PHY_CAP2_UL_MU_FULL_MU_MIMO' "$INIT" ||
	fail 'UL MU-MIMO capability advertisement is missing'
grep -Fq 'CR6608_MURU_MUMIMO_UL' "$INIT" ||
	fail 'UL MU-MIMO advertisement is not tied to its independent bit'

for marker in \
	'muru->cfg.ofdma_ul_en = !!(mask & CR6608_MURU_OFDMA_UL);' \
	'muru->cfg.mimo_dl_en = (mvif->cap.he_mu_ebfer ||' \
	'muru->cfg.ofdma_dl_en = !!(mask & CR6608_MURU_OFDMA_DL);' \
	'mask = mt7915_cr6608_muru_mask(dev);' \
	'mask &= CR6608_MURU_OFDMA_DL | CR6608_MURU_MUMIMO_DL;' \
	'muru->cfg.mimo_ul_en = !is_mt7915(&dev->mt76) &&' \
	'state &= ~CR6608_MURU_MUMIMO_UL;' \
	'if ((mask & CR6608_MURU_MUMIMO_DL) &&' \
	'sta->deflink.vht_cap.vht_supported)' \
	'(cr6608_tx_mask & CR6608_MURU_UL_MASK);' \
	'mt7915_cr6608_muru_sta_rec_attempt(dev);' \
	'mt7915_cr6608_muru_sta_rec_response(dev,' \
	'mt7915_cr6608_muru_sta_rec_failure(dev,'; do
	grep -Fq "$marker" "$MCU" || fail "MCU patch lacks $marker"
done

send_line="$(grep -nF 'ret = mt76_mcu_skb_send_msg(&dev->mt76, skb,' "$MCU" | grep -F ':+' | cut -d: -f1)"
response_ok_line="$(grep -nF 'mt7915_cr6608_muru_sta_rec_response(dev,' "$MCU" | grep -F ':+' | cut -d: -f1)"
[ -n "$send_line" ] && [ -n "$response_ok_line" ] && [ "$response_ok_line" -gt "$send_line" ] ||
	fail 'response_ok counter is not updated after the synchronous MCU response'
grep -Fq 'A zero synchronous response is not apply or OTA proof.' "$MCU" ||
	fail 'response_ok semantics are not explicitly limited to command response'
! grep -Fq 'sta_rec_acked' "$STATE" "$INIT" "$DEBUG" "$MCU" ||
	fail 'misleading STA_REC ACK telemetry name remains in the driver port'

grep -Fq 'mt7915_cr6608_muru_fault_latch(dev)' "$MAC" ||
	fail 'reset path does not invoke the kernel fault latch'
grep -Fq 'mt7915_cr6608_muru_fault_latch(dev)' "$MCU" ||
	fail 'MCU timeout path does not invoke the kernel fault latch'

for marker in \
	'cr6608_muru_mask' \
	'atomic_cmpxchg(&dev->cr6608_muru_mask, old,' \
	'candidate_mask=' \
	'candidate_dl_ofdma=' \
	'candidate_ul_mumimo=' \
	'fault_latched=' \
	'sta_rec_attempted=' \
	'sta_rec_response_ok=' \
	'sta_rec_failed=' \
	'sta_rec_timeout='; do
	grep -Fq "$marker" "$DEBUG" || fail "debug telemetry lacks $marker"
done
! grep -Eq '^\+.*seq_printf\(file, "(allowed|enabled|mask|dl_ofdma|ul_ofdma|dl_mumimo|ul_mumimo)=' "$DEBUG" ||
	fail 'candidate bitmap telemetry still claims to be effective radio state'

! grep -Fq 'atomic_set(&dev->cr6608_muru_mask, val)' "$DEBUG" ||
	fail 'runtime mask setter can restore bits from a stale read'
! grep -Fq 'if (mask && sta->deflink.vht_cap.vht_supported)' "$MCU" ||
	fail 'VHT DL MU-MIMO can be advertised without the DL MU-MIMO bit'
! grep -Fq '+		cr6608_tx_mask;' "$MCU" ||
	fail 'DL-only MURU transactions can contaminate UL response telemetry'

grep -Fq 'spinlock_t cr6608_muru_telemetry_lock;' "$STATE" &&
	grep -Fq 'spin_lock_init(&dev->cr6608_muru_telemetry_lock);' "$INIT" ||
	fail 'dedicated telemetry snapshot lock is missing or uninitialized'
snapshot_lock="$(grep -nF 'spin_lock_irqsave(&dev->cr6608_muru_telemetry_lock, flags);' "$DEBUG" | grep -F ':+' | cut -d: -f1)"
snapshot_unlock="$(grep -nF 'spin_unlock_irqrestore(&dev->cr6608_muru_telemetry_lock, flags);' "$DEBUG" | grep -F ':+' | cut -d: -f1)"
first_snapshot_read="$(grep -nF 'fault_latches = atomic_read(&dev->cr6608_muru_fault_latches);' "$DEBUG" | grep -F ':+' | cut -d: -f1)"
last_snapshot_read="$(grep -nF 'attempted = atomic_read(&dev->cr6608_ul_muru_sta_rec_attempted);' "$DEBUG" | grep -F ':+' | cut -d: -f1)"
[ -n "$snapshot_lock" ] && [ -n "$snapshot_unlock" ] &&
	[ -n "$first_snapshot_read" ] && [ -n "$last_snapshot_read" ] &&
	[ "$snapshot_lock" -lt "$first_snapshot_read" ] &&
	[ "$last_snapshot_read" -lt "$snapshot_unlock" ] ||
	fail 'debugfs does not read every related counter inside one locked snapshot'
for helper in \
	mt7915_cr6608_muru_sta_rec_attempt \
	mt7915_cr6608_muru_sta_rec_response \
	mt7915_cr6608_muru_sta_rec_failure \
	mt7915_cr6608_muru_fault_latch; do
	awk -v helper="$helper" '
		index($0, helper "(") { in_helper = 1 }
		in_helper && /spin_lock_irqsave.*cr6608_muru_telemetry_lock/ { locked = 1 }
		in_helper && /spin_unlock_irqrestore.*cr6608_muru_telemetry_lock/ { unlocked = 1 }
		in_helper && /^\+}/ { exit !(locked && unlocked) }
		END { if (!in_helper || !locked || !unlocked) exit 1 }
	' "$STATE" || fail "$helper does not update its complete counter group under the snapshot lock"
done
! grep -Eq '^\+.*atomic_inc\(&dev->cr6608_(ul_)?muru_' "$MCU" ||
	fail 'MCU code bypasses the locked telemetry helpers'
! grep -Eq '^\+.*spin_lock[^;]*recovery_tx_lock' "$STATE" ||
	fail 'telemetry lock can be nested with recovery_tx_lock'
for local_output in \
	'seq_printf(file, "sta_rec_attempted=%d\n", attempted);' \
	'seq_printf(file, "sta_rec_response_ok=%d\n", response_ok);' \
	'seq_printf(file, "sta_rec_failed=%d\n", failed);' \
	'seq_printf(file, "sta_rec_timeout=%d\n", timeout);' \
	'mimo_updates);'; do
	grep -Fq "$local_output" "$DEBUG" ||
		fail "debugfs output bypasses the ordered snapshot: $local_output"
done
# Patch 04 is applied after the vendor-baseline patch, whose HE counter still
# reads the atomic directly. The replacement must carry a real -/+ pair; making
# he_updates a context line produces a patch that cannot apply to the stack.
grep -Fq -- "$(printf '%s\t\t%s' '-' '   atomic_read(&dev->cr6608_ul_muru_he_sta_rec_updates));')" "$DEBUG" ||
	fail 'debugfs patch does not replace the vendor HE atomic read'
grep -Fq -- "$(printf '%s\t\t%s' '+' '   he_updates);')" "$DEBUG" ||
	fail 'debugfs patch does not emit HE telemetry from the locked snapshot'
! grep -Fq -- "$(printf '%s\t\t%s' ' ' '   he_updates);')" "$DEBUG" ||
	fail 'debugfs patch incorrectly assumes the HE snapshot local already exists'
grep -Fq '@@ -298,20 +297,99 @@ DEFINE_DEBUGFS_ATTRIBUTE(fops_cr6608_ul_muru,' "$DEBUG" ||
	fail 'debugfs state hunk counts are not the applicable vendor-baseline preimage'

reset_latch_line="$(grep -nF 'muru_latched = mt7915_cr6608_muru_fault_latch(dev);' "$MAC" | cut -d: -f1)"
reset_queue_line="$(grep -nF 'queue_work(dev->mt76.wq, &dev->reset_work);' "$MAC" | tail -n1 | cut -d: -f1)"
[ -n "$reset_latch_line" ] && [ -n "$reset_queue_line" ] &&
	[ "$reset_latch_line" -lt "$reset_queue_line" ] ||
	fail 'reset path does not clear the mask before queueing recovery work'

common_latch_line="$(grep -nF 'muru_latched = mt7915_cr6608_muru_fault_latch(dev);' "$MCU" | tail -n1 | cut -d: -f1)"
common_queue_line="$(grep -nF 'queue_work(dev->mt76.wq, &dev->reset_work);' "$MCU" | tail -n1 | cut -d: -f1)"
[ -n "$common_latch_line" ] && [ -n "$common_queue_line" ] &&
	[ "$common_latch_line" -lt "$common_queue_line" ] ||
	fail 'common full-recovery path queues work before the MURU fault latch'

for marker in \
	'CR6608_MURU_STA_HE' \
	'cr6608_tx_mask & ~cr6608_live_mask' \
	'CR6608 MURU mask changed before STA_REC send' \
	'CR6608 MURU mask changed during STA_REC response' \
	'return -ECANCELED;'; do
	grep -Fq "$marker" "$MCU" || fail "stale STA_REC guard lacks $marker"
done

non_he_prune_line="$(grep -nF 'mask &= CR6608_MURU_OFDMA_DL | CR6608_MURU_MUMIMO_DL;' "$MCU" | grep -F ':+' | cut -d: -f1)"
vht_dl_line="$(grep -nF 'if ((mask & CR6608_MURU_MUMIMO_DL) &&' "$MCU" | grep -F ':+' | cut -d: -f1)"
non_he_return_line="$(grep -nF 'return state;' "$MCU" | grep -F ':+' | head -n1 | cut -d: -f1)"
first_flag_line="$(grep -nF 'muru->cfg.mimo_dl_en = (mvif->cap.he_mu_ebfer ||' "$MCU" | grep -F ':+' | cut -d: -f1)"
[ -n "$non_he_prune_line" ] && [ -n "$first_flag_line" ] &&
	[ "$non_he_prune_line" -lt "$first_flag_line" ] &&
	[ -n "$vht_dl_line" ] && [ -n "$non_he_return_line" ] &&
	[ "$vht_dl_line" -lt "$non_he_return_line" ] ||
	fail 'UL-lab non-HE/VHT peers do not preserve stable DL bits while forcing UL off'

full_gate_line="$(grep -nF 'if (muru->mimo_ul.full_ul_mimo) {' "$MCU" | grep -F ':+' | cut -d: -f1)"
clear_ul_mimo_line="$(grep -nF 'state &= ~CR6608_MURU_MUMIMO_UL;' "$MCU" | grep -F ':+' | cut -d: -f1)"
[ -n "$full_gate_line" ] && [ -n "$clear_ul_mimo_line" ] &&
	[ "$full_gate_line" -lt "$clear_ul_mimo_line" ] &&
	grep -Fq '+		!is_mt7915(&dev->mt76) &&' "$MCU" ||
	fail 'MT7915 UL MU-MIMO is not restricted to full-bandwidth peers'

pre_mismatch_line="$(grep -nF 'CR6608 MURU mask changed before STA_REC send' "$MCU" | cut -d: -f1)"
response_mismatch_line="$(grep -nF 'CR6608 MURU mask changed during STA_REC response' "$MCU" | cut -d: -f1)"
ret_failure_line="$(grep -nF 'mt7915_cr6608_muru_sta_rec_failure(dev,' "$MCU" | grep -F ':+' | tail -n1 | cut -d: -f1)"
return_ret_line="$(grep -nF 'return ret;' "$MCU" | grep -F ':+' | tail -n1 | cut -d: -f1)"
for boundary in "$pre_mismatch_line:$send_line:pre-send" \
	"$response_mismatch_line:$response_ok_line:response-race" \
	"$ret_failure_line:$return_ret_line:send-error"; do
	start="${boundary%%:*}"
	rest="${boundary#*:}"
	end="${rest%%:*}"
	name="${rest#*:}"
	latch_line="$(awk -v start="$start" -v end="$end" \
		'NR > start && NR < end && index($0, "+\t\t\tmt7915_cr6608_muru_fault_latch(dev);") { print NR; exit }' "$MCU")"
	recovery_line="$(awk -v start="$start" -v end="$end" \
		'NR > start && NR < end && index($0, "+\t\t\tmt7915_mcu_schedule_full_recovery(dev);") { print NR; exit }' "$MCU")"
	[ -n "$latch_line" ] && [ -n "$recovery_line" ] &&
		[ "$latch_line" -lt "$recovery_line" ] ||
		fail "$name path does not latch before immediate recovery"
done

grep -Fq 'atomic_inc(&dev->cr6608_ul_muru_sta_rec_response_ok);' "$STATE" &&
	grep -Fq 'atomic_inc(&dev->cr6608_ul_muru_he_sta_rec_updates);' "$STATE" &&
	grep -Fq 'atomic_inc(&dev->cr6608_ul_muru_mimo_capable_updates);' "$STATE" &&
	[ "$response_ok_line" -gt "$send_line" ] ||
	fail 'response/HE/full-UL-MIMO counters are not one response-only locked group'

printf 'muru_driver_port_contract=pass\n'
