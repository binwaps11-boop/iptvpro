# CR6608 MURU fault attribution, guarded re-arm and client-attributed uplink evidence

This document covers `patches/zzzzzz-06-mt7915-cr6608-muru-fault-attribution.patch`
and `patches/zzzzzz-07-mt7915-cr6608-muru-ul-tb-attribution.patch`. Both are
host-side only. Neither adds a firmware command, changes a capability
advertisement, touches the TX-power path, or writes any persistent storage;
the source gate `tests/test-muru-fault-attribution.sh` asserts that.

## The defect these patches fix

Up to and including v86 the driver had exactly one MU-RU shutdown primitive,
`mt7915_cr6608_muru_fault_latch()`. It cleared the scheduler mask **and**
spent a one-way latch that can only be released by a fresh driver load. It was
called from:

- `mt7915_mac_reset_work()` on entry, for every reset reason;
- `mt7915_reset()` for every recovery, watchdog or not;
- `mt7915_mcu_parse_response()` for **any** timed-out MCU command;
- `mt7915_mcu_schedule_full_recovery()`, the shared recovery entry point;
- the genuinely MU-RU-attributed sites in `__mt7915_mcu_add_sta()`.

The first four are not MU-RU faults. On this device they are dominated by the
38 dBm request path, which calls `mt7915_mcu_schedule_full_recovery()` when a
SKU snapshot, readback or rollback cannot be verified, and by
`mt7915_regd_notifier()`, which forces a full recovery whenever a regulatory
update lands while a reconfiguration is pending.

The `ul-forced-lab` profile is exactly the combination that suffers: it runs
`cr6608_rf_38dbm=1` **and** `cr6608_muru_mask=15`. One regulatory refresh, one
MCU log-command timeout, or one unverifiable SKU transaction permanently
disabled every MU-RU scheduler bit for the rest of the uptime — with no
watchdog, no TX hang, and nothing wrong with the scheduler. That is the
mechanism behind "MU is off because of the MediaTek firmware": in this stack
the uplink experiment was being switched off by the *power* path.

A second, quieter regression came from the same primitive. Once the mask
reached zero, `mt7915_mcu_sta_muru_tlv()` computed `mask = 0`, so
`ofdma_dl_en` and `mimo_dl_en` also went false. Upstream MT7915 always
requests DL OFDMA and requests DL MU-MIMO for a beamforming-capable BSS.
A failed uplink experiment therefore dragged the radio **below** plain
upstream behaviour, losing supported, stable downlink features.

## What patch 06 changes

Three primitives replace the single latch:

| Primitive | Clears live mask | Spends one-way latch | Lowers re-arm ceiling |
|---|---|---|---|
| `mt7915_cr6608_muru_disarm()` | yes | no | no |
| `mt7915_cr6608_muru_fault_latch()` | yes | yes | yes (to 0) |
| `mt7915_cr6608_muru_lower_ceiling()` | via caller | no | yes |

Every recovery still takes the scheduler down before the firmware is reset, so
no scheduler bit can survive into a reset — the fail-closed property of v86 is
unchanged. What changed is *who gets blamed*:

- **Watchdog reset** (`MT_MCU_CMD_WDT_MASK` in `mt7915_reset()` and in
  `mt7915_mac_reset_work()`): latch. This is the exact failure mode upstream
  cited when it removed MT7915 UL-MU, so it stays permanent.
- **Timed-out `MCU_EXT_CMD(STA_REC_UPDATE)`**: latch. That is the only command
  that carries MU-RU state.
- **Any other timed-out command, and the shared recovery entry point**:
  disarm plus one strike.
- **Mask race or STA_REC failure in `__mt7915_mcu_add_sta()`**: unchanged,
  still latch.

`mt7915_cr6608_muru_rearm()` restores the mask after a *verified* reset —
after the full-reset path reaches `MT_MCU_CMD_NORMAL_STATE` and before
`ieee80211_restart_hw()`, so the replayed `STA_REC_MURU` records carry the
restored bits, and after a partial reset only when `partial_ok` is true.

Re-arm can only ever restore the **ceiling**, a one-way value seeded from the
operator-locked boot mask and lowered by the debugfs writers and by the fault
latch. It refuses a latched device, and it converts an exhausted strike budget
(`CR6608_MURU_MAX_STRIKES`, 3) into a permanent latch, so repeated
unattributed recovery while the scheduler is live still ends the experiment
rather than cycling forever.

The `cr6608_muru_dl_floor` holds `CR6608_MURU_OFDMA_DL | CR6608_MURU_MUMIMO_DL`
and is lowered **only** by an explicit operator mask write.
`mt7915_mcu_sta_muru_tlv()` now uses `mt7915_cr6608_muru_effective_mask()`
(live mask OR floor), so a retired, disarmed or latched uplink experiment can
never regress this radio below upstream downlink behaviour.

`cr6608_ul_muru_state` gains `candidate_ceiling`, `upstream_dl_floor`,
`unattributed_disarms`, `rearms`, `strikes` and `strike_limit`.

## What patch 07 adds

`docs/CR6608-STOCK-MURU-PORT.md` lists client-attributed OTA evidence as a
promotion blocker, solvable only with capture hardware or per-peer scheduler
telemetry. Patch 07 provides the per-peer telemetry from data the driver
already receives.

A HE trigger-based (TB) PPDU exists **only** as a response to a Trigger frame
this AP transmitted. The RX descriptor carries the transmitting peer's WCID
and, in the P-RXV, the HE RU allocation. Counting `MT_PHY_TYPE_HE_TB` per WCID
is therefore direct, client-attributed proof that the firmware MU-RU scheduler
solicited uplink airtime from one specific client — the attribution aggregate
radio counters cannot give.

Classification, all derived from the descriptor:

- RU smaller than the operating bandwidth → **UL OFDMA** for that peer.
- RU equal to the full operating bandwidth → full-bandwidth TB PPDU: either a
  single-user trigger, or UL MU-MIMO.
- Two or more **distinct** peers whose TB PPDUs share the same PHY start
  timestamp → a genuine simultaneous uplink multi-user transmission. On
  full bandwidth that is full-bandwidth UL MU-MIMO, the only uplink MIMO mode
  MT7915 supports; on smaller RUs it is UL OFDMA.

Accounting runs only for `MT_PHY_TYPE_HE_TB` frames and only while an uplink
bit is armed, so the retail and stable mask-0 profiles pay nothing. It is
strictly read-only: it never changes scheduling, capability, power or recovery
state.

Exposed as:

- `<phy>/cr6608_ul_attribution`: `he_tb_ppdu`, `he_tb_ul_ofdma_ru`,
  `he_tb_full_bw`, `ul_ofdma_multi_user_ppdus`,
  `ul_mumimo_multi_user_ppdus`, `max_peers_in_one_ppdu`.
- `<phy>/netdev:*/stations/*/cr6608_ul_attribution`: the same, per peer, plus
  `he_tb_ul_mumimo_shared` and `last_tb_timestamp`.

## Evidence boundary

These numbers are host-observed scheduling evidence. A non-zero
`ul_mumimo_multi_user_ppdus` shows the firmware scheduled two clients in one
uplink PPDU on this radio, attributed to their WCIDs. It is **not** an RF
measurement, a regulatory result, a throughput claim, or a sale approval, and
it does not by itself clear the remaining promotion blockers in
`docs/CR6608-STOCK-MURU-PORT.md` (long-duration stress, DFS/thermal/
coexistence, regulatory testing, a reviewed retail profile).
