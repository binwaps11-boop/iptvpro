#!/bin/sh
#
# Source contract for the CR6608 MURU live-refresh and strike-decay patch.
#
# Two properties, both required for "works automatically, no reboot":
#   1. A change to the live scheduler mask (re-arm after a partial reset,
#      runtime kill switch, debugfs mask write) is replayed into every
#      associated peer's firmware record with the SAME conn_state that was
#      last sent, so no peer keeps a stale record and no peer is downgraded.
#   2. Unattributed strikes decay after a healthy window, so three unrelated
#      recoveries months apart can never spend the permanent latch.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH="$ROOT/patches/zzzzzz-08-mt7915-cr6608-muru-live-refresh.patch"

fail() {
	printf 'muru live refresh contract failed: %s\n' "$*" >&2
	exit 1
}

[ -s "$PATCH" ] || fail 'missing patch'
! grep -Eqi 'mtd_(write|erase)|MTD_OPS_PLACE_OOB|MURU_SET_(BSRP_CTRL|SUTX|MUMIMO_CTRL|MANUAL_CFG|MU_DL_ACK_POLICY|TRIG_TYPE|20M_DYN_ALGO|PROT_FRAME_THR|CERT_MU_EDCA_OVERRIDE|ARB_OP_MODE)|mt7915_mcu_set_muru_cfg|mt7915_mcu_set_mu_dl_ack_policy|mt7915_mcu_set_mu_prot_frame_th|mt7915_mcu_set_cr6608_ul_muru' "$PATCH" ||
	fail 'unsafe storage write or unverified firmware ABI'
! grep -E '^\+' "$PATCH" | grep -Fq 'mt76_mcu_send_msg' ||
	fail 'patch introduces a new MCU command'
grep -Fq 'mt7915_mcu_add_sta(dev, vif, sta,' "$PATCH" ||
	fail 'refresh does not reuse the standard STA_REC_UPDATE path'

# --- conn_state fidelity ------------------------------------------------
grep -Fq '+	u8 cr6608_conn_state;' "$PATCH" ||
	fail 'last-sent conn_state is not recorded per peer'
grep -Fq '+		msta->cr6608_conn_state = CONN_STATE_CONNECT;' "$PATCH" ||
	fail 'ASSOC does not record CONNECT'
grep -Fq '+			msta->cr6608_conn_state = CONN_STATE_PORT_SECURE;' "$PATCH" ||
	fail 'AUTHORIZE does not record PORT_SECURE'
grep -Fq '+		msta->cr6608_conn_state = CONN_STATE_DISCONNECT;' "$PATCH" ||
	fail 'DISASSOC does not record DISCONNECT'
# PORT_SECURE must only be recorded when the send succeeded.
awk '/\+		ret = mt7915_mcu_add_sta\(dev, vif, sta, CONN_STATE_PORT_SECURE,/{f=1} f&&/\+		if \(!ret\)/{ok=1} END{exit !ok}' "$PATCH" ||
	fail 'PORT_SECURE recorded even when the MCU rejected it'

# --- replay uses the recorded state, never a fixed one --------------------
grep -Fq 'msta->cr6608_conn_state, false);' "$PATCH" ||
	fail 'replay does not use the last-sent conn_state'
! grep -Eq '^\+.*CR6608_RC_MURU_REFRESH.*CONN_STATE_(CONNECT|PORT_SECURE)\b' "$PATCH" ||
	fail 'replay hard-codes a conn_state'

# --- replay guards --------------------------------------------------------
body="$(awk '/if \(\(changed & CR6608_RC_MURU_REFRESH\) &&/,/msta->cr6608_conn_state, false\);/' "$PATCH")"
[ -n "$body" ] || fail 'refresh branch not found in rc_work'
for g in 'msta->wcid.sta && !msta->wcid.sta_disabled' \
	 'msta->cr6608_conn_state != CONN_STATE_DISCONNECT' \
	 '!test_bit(MT76_MCU_RESET, &dev->mphy.state)' \
	 '!test_bit(MT76_RESET, &dev->mphy.state)'; do
	printf '%s\n' "$body" | grep -Fq "$g" || fail "replay lacks guard: $g"
done

# --- refresh is reachable from every mask-changing path -------------------
grep -Fq '"partial reset re-arm"' "$PATCH" ||
	fail 'partial-reset re-arm does not refresh records'
grep -Fq '"runtime kill switch"' "$PATCH" ||
	fail 'kill switch does not refresh records'
grep -Fq '"debugfs mask write"' "$PATCH" ||
	fail 'debugfs mask write does not refresh records'
# In mac.c the refresh may be called from exactly one place, and that place
# must be the verified-partial-reset re-arm.  A full reset must NOT refresh:
# mac80211 replays the records itself after ieee80211_restart_hw().
mac_calls="$(awk '/^diff --git a\/mt7915\/mac.c/{f=1;next} /^diff --git/{f=0} f' "$PATCH" |
	grep -c '^+.*mt7915_cr6608_muru_refresh_stations(dev,')"
[ "$mac_calls" = 1 ] ||
	fail "expected exactly one refresh call in mac.c, found $mac_calls"
awk '/^diff --git a\/mt7915\/mac.c/{f=1;next} /^diff --git/{f=0} f' "$PATCH" |
	awk 'BEGIN{RS="\n@@"} /mt7915_cr6608_muru_refresh_stations\(dev,/ && /"partial reset re-arm"/{ok=1} END{exit !ok}' ||
	fail 'the mac.c refresh call is not in the partial-reset re-arm hunk'
# Both phys of a DBDC device.
grep -Fq 'ieee80211_iterate_stations_atomic(ext_phy->hw,' "$PATCH" ||
	fail 'refresh ignores the second phy'
# Private bit outside the IEEE80211_RC_* space (BIT(0..3)).
grep -Fq '#define CR6608_RC_MURU_REFRESH		BIT(31)' "$PATCH" ||
	fail 'refresh flag collides with mac80211 rate-control bits'

# --- strike decay ---------------------------------------------------------
grep -Fq '#define CR6608_MURU_STRIKE_DECAY	(15 * 60 * HZ)' "$PATCH" ||
	fail 'strike decay window missing or changed without updating this test'
decay="$(awk '/static inline void mt7915_cr6608_muru_strike_decay/,/^\+}/' "$PATCH")"
[ -n "$decay" ] || fail 'strike decay helper not found'
for g in 'atomic_read(&dev->cr6608_muru_fault_latched)' \
	 'test_bit(MT76_MCU_RESET, &dev->mphy.state)' \
	 'time_after(jiffies, last + CR6608_MURU_STRIKE_DECAY)' \
	 'atomic_cmpxchg(&dev->cr6608_muru_strikes, strikes, 0)'; do
	printf '%s\n' "$decay" | grep -Fq "$g" || fail "strike decay lacks: $g"
done
# Decay must never raise the mask or touch the ceiling.
! printf '%s\n' "$decay" | grep -Eq 'cr6608_muru_(mask|ceiling)' ||
	fail 'strike decay touches the mask or ceiling'
# Every disarm stamps the clock the decay measures from.
grep -Fq 'WRITE_ONCE(dev->cr6608_muru_last_disarm, jiffies);' "$PATCH" ||
	fail 'disarm does not stamp the decay clock'
# Runs from the periodic MAC work on the primary phy only.
grep -Fq 'if (mphy == &phy->dev->mphy)' "$PATCH" ||
	fail 'decay is not restricted to the primary phy'

# --- logging honesty ------------------------------------------------------
! grep -E '^\+.*(dev_info|dev_warn|dev_crit|seq_printf|seq_puts)' "$PATCH" |
	grep -Eiq 'works|supported officially|certified|proven' ||
	fail 'a log string overclaims'

printf 'muru_live_refresh_contract=pass\n'
