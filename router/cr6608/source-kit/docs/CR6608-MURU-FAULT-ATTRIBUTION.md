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

## Patch 08 — live record refresh and strike decay

`patches/zzzzzz-08-mt7915-cr6608-muru-live-refresh.patch` closes the two gaps
patch 06 left open for a device that must run indefinitely without a reboot.

### Live record refresh

A partial firmware reset keeps the station records alive, so patch 06 only
re-armed the host mask afterwards. Any peer that (re)associated during the
disarm window therefore kept a DL-only `STA_REC_MURU` until it re-associated
on its own. The same was true of the runtime kill switch and a debugfs mask
write: the new value only reached peers that associated later, which is why
the userspace guard followed each write with a Wi-Fi reload.

The refresh replays each associated peer's full station record through the
same `STA_REC_UPDATE` the AUTHORIZE path already sends, so the MURU TLV picks
up the live mask in place:

- `mt7915_mac_sta_event()` records the `conn_state` of the last record sent
  (`CONNECT` on ASSOC, `PORT_SECURE` only after a *successful* AUTHORIZE send,
  `DISCONNECT` on DISASSOC). A replay uses exactly that state; re-sending
  `CONNECT` for a port-secure peer would downgrade it in firmware.
- `mt7915_cr6608_muru_refresh_stations()` queues every peer of both phys
  through the existing rate-control work (`ieee80211_iterate_stations_atomic`
  + `dev->rc_work`), the pattern `mt7915_set_bitrate_mask()` already uses.
  A private `msta->changed` bit outside the `IEEE80211_RC_*` space carries
  the request.
- `mt7915_mac_sta_rc_work()` performs the send from process context, skipping
  peers that are gone or mid-teardown and never while `MT76_MCU_RESET` /
  `MT76_RESET` is set.

It is called from the verified-partial-reset re-arm, the runtime kill switch
and the debugfs mask writer. It is deliberately **not** called after a full
reset: `ieee80211_restart_hw()` makes mac80211 replay the records itself.

For reference, MediaTek's own downstream (`0099-cp-mtk-mt76-mt7915-add-connac2-support.patch`,
`mt7915_set_wireless_vif()`) stores a new `muru_onoff` bitmap and lets it apply
to the *next* association only; it does not refresh live peers. The refresh
here is an addition, built from a record the firmware already accepts.

### Strike decay

Patch 06 bounded unattributed re-arms with three strikes, but the counter
never decayed, so three unrelated recoveries spread over months would still
have spent the permanent latch. `mt7915_cr6608_muru_strike_decay()`, run from
the periodic MAC work on the primary phy, resets the counter once
`CR6608_MURU_STRIKE_DECAY` (15 minutes) has passed since the last disarm with
no further disarm. It never runs on a latched device, never while a recovery
is in flight, and touches neither the mask nor the ceiling. Three unrelated
recoveries *inside* the window still latch.

`cr6608_muru_last_disarm` is stamped by every disarm, in whatever context the
disarm happens (including the tasklet path of `mt7915_reset()`), with a plain
`WRITE_ONCE`.

## Two-source on-device proof (`cr6608-ul-mu-evidence --with-firmware`)

The evidence tool has two modes.

`cr6608-ul-mu-evidence` (cumulative) reads the host-side per-WCID counters
from patch 07 and answers from them alone.

`cr6608-ul-mu-evidence --with-firmware [--window SECONDS]` adds the second,
independent source: the MURU statistics the closed firmware itself reports
through `MURU_GET_TXC_TX_STATS` (`struct mt7915_mcu_muru_stats.ul`:
`hetrig_su_cnt`, `hetrig_2ru…gtr16ru_cnt`, `hetrig_2mu/3mu/4mu_cnt`), which
`muru_stats` prints as `Total HE OFDMA UL TB PPDU count`, `Total HE MU-MIMO UL
TB PPDU count` and `All HE UL TB PPDU count`. These are the firmware's own
counts of the trigger-based PPDUs it received — that is, of the uplink
transmissions it scheduled. The tool enables `muru_debug` for the window
(the statistics are only produced while it is on) and restores the previous
value on every exit path.

Everything in window mode is a **delta over the window**, so counters that
were already high before the test cannot count as activity. The verdict is
still decided by the client-attributed host counters (two distinct peers in
one PPDU), and the firmware counters are reported as corroboration:

| host verdict | firmware delta | reported |
|---|---|---|
| `UL_MUMIMO_CLIENT_ATTRIBUTED` | `he_mumimo_ul_tb_ppdu > 0` | `FIRMWARE_CORROBORATED` |
| `UL_OFDMA_CLIENT_ATTRIBUTED` | `he_ofdma_ul_tb_ppdu > 0` | `FIRMWARE_CORROBORATED` |
| any host activity | matching counter `0` | `FIRMWARE_DISAGREES_*` + `inconclusive` |
| no host activity | `he_ul_tb_ppdu > 0` | `FIRMWARE_SAW_TB_PPDUS_HOST_DID_NOT` + `inconclusive` |
| no host activity | `0` | `FIRMWARE_AGREES_NOTHING_SCHEDULED` |
| — | `muru_stats` missing | `FIRMWARE_STATS_UNAVAILABLE` |

A disagreement is never resolved in favour of the stronger claim.

Procedure that cannot be satisfied by one client or by downlink-only traffic:
two HE clients that advertise full-bandwidth UL MU-MIMO, both uploading at
the same time to the AP (e.g. `iperf3 -R` from the router side, or two
uploads), then `cr6608-ul-mu-evidence --with-firmware --window 60`. Expected
on a working uplink scheduler: `verdict=UL_OFDMA_CLIENT_ATTRIBUTED` or
`verdict=UL_MUMIMO_CLIENT_ATTRIBUTED` with `firmware_corroboration=FIRMWARE_CORROBORATED`.
Anything else is reported as exactly what it is.

## Patch 09 — uniform per-peer cfg bits and boot-frozen, vendor-parity B22

Two evidence-backed corrections to the station-record and capability path.

### The first-station latch (`abd80cf6`)

MeiChia Chiu's upstream fix `abd80cf6` (2022-02-15) states the firmware
behaviour directly: *"The muru enable/disable are only set after the first
station connection. Without this patch, the firmware couldn't enable muru if
the first connected station is non-HE type."* Its fix was to send identical
`cfg.*_en` bits for every station. MediaTek's shipped mt7915 build does the
same (`0099` lines 3843–3845: every peer gets `muru_onoff`'s bits, HE or not).

The kit, until patch 09, downgraded the bits per peer: non-HE peers were sent
DL-only bits, and `mimo_ul_en` was set only for HE peers advertising B22. On a
firmware that latches from the first record, a legacy/VHT client or an HE
phone without B22 associating first could leave the uplink scheduler unarmed
for the whole BSS — "UL never observed", no hang, and invisible to the
synchronous-response telemetry. That is a plausible mechanism for exactly the
symptom this work set out to explain.

Patch 09 sends the phy-wide effective mask to every peer and leaves
eligibility where upstream and mt7996 keep it: in the per-peer capability
fields (`mimo_ul.full_ul_mimo`, `ofdma_ul.t_frame_dur/mu_cascading/uo_ra`,
…) that the firmware reads per WCID. Partial-bandwidth UL MU-MIMO stays
forced off on mt7915 (`a2838480`). Non-MT7915 chips are restored to exactly
upstream's request (DL bits and UL MU-MIMO; upstream has never requested UL
OFDMA on any chip), fixing an unintended behaviour change in the earlier
port.

### B22: vendor parity by default, frozen at boot

MediaTek's mt7915 build enables `mimo_ul_en` per peer **without**
advertising HE PHY CAP2 B22 (the upstream `!is_mt7915` guard is untouched in
`0099`). That is the only mt7915 UL MU-MIMO configuration any vendor has
shipped and field-tested on the pinned firmware. The kit's previous
behaviour — advertising B22 whenever bit 3 was armed — was a third variant
neither upstream nor MediaTek runs.

Per IEEE 802.11ax-2021 Table 9-322c the AP's B22 states reception support;
the normative scheduling constraint is the *peer's* B22, which the driver
already reads. So removing the AP bit does not by itself stop the firmware
from soliciting full-bandwidth UL MU-MIMO.

Patch 09 therefore:

- defaults to vendor parity (`cr6608_advertise_ul_mumimo=0`, B22 off,
  scheduler bits requested per peer);
- keeps the previous behaviour as an explicit opt-in
  (`cr6608_advertise_ul_mumimo=1`) so the two configurations can be compared
  over the air with `cr6608-ul-mu-evidence`;
- decides the advertisement **once at driver load** and exposes it as
  `ul_mimo_advertised=` in `cr6608_ul_muru_state`. Previously the gate read
  the live mask, and `mt7915_set_antenna()` re-runs
  `mt7915_set_stream_he_caps()`, so an antenna change while disarmed could
  silently drop B22 with no re-arm path to restore it.

Withheld on purpose, and recorded so nobody "enables everything" later: TRS,
MU Cascading, OFDMA RA (UORA), NDP Feedback Report, Triggered CQI Feedback,
BSRP/BQRP A-MPDU aggregation, UL 2×996 RU, partial-bandwidth UL MU-MIMO. No
chip in this driver (mt7915/mt7916/mt7986/mt7996) advertises them, MediaTek's
downstream does not add them, and the firmware consumes only the *peer's*
values for them. Advertising any of them would be a fake capability.

## Patch 10 — evidence honesty

### The per-peer counters were structurally zero on MT7915

The firmware-blob audit found a defect in patch 07: on MT7915 the RX PHY
type of a received PPDU is decoded from the C-RXV group (RXD group 5,
`mt76_connac_mac.c`), and upstream clears `MT_DMA_DCR0_RXD_G5_EN` at init
(`d33943ba`: *"When per-packet rate reporting is enabled, the hardware can
get stuck under some conditions"*), enabling it only for a monitor interface.
In normal AP operation `mode` therefore never equals `MT_PHY_TYPE_HE_TB` and
`cr6608_ul_attribution` reads `he_tb_ppdu=0` whatever the scheduler does.
Read as "no trigger responses", that would have been a false negative — the
exact kind of misleading evidence this project must not produce.

Patch 10 makes the nodes say what they can see:

- `rxv_group5_enabled=` on the per-radio node, read from `MT_DMA_DCR0`;
- `evidence=unavailable-crxv-disabled` (per radio and per peer) whenever
  group 5 is off on mt7915, instead of the client-attribution claim;
- a `0600` `cr6608_rxv_group5` knob that sets the same register bit upstream
  sets for monitor mode. It is gated on the CR6608 experiment, mutex-protected,
  refuses a stopped phy, logs the `d33943ba` risk when enabled, is re-cleared
  by any firmware reset, and is never touched by a profile. The evidence tool
  enables it only for `--enable-crxv` windows and restores it on every exit.

`cr6608-ul-mu-evidence` v3 reports `host_attribution=` and returns
`HOST_ATTRIBUTION_UNAVAILABLE_RXV_GROUP5_OFF` when no radio can see PPDU
types; in that state the firmware's own `hetrig_*` counters are the proof and
are reported as `FIRMWARE_ONLY_*`, explicitly marked as not client-attributed.

### Firmware statistics that cannot be produced

`muru_stats` now prints `firmware-stats-unavailable err=<errno>` instead of
failing the read when `MURU_GET_TXC_TX_STATS` is refused or times out. The
evidence tool probes once before enabling the 500 ms poll and leaves
`muru_debug` off if the probe fails, so an unsupported sub-command cannot
turn an evidence window into a stream of MCU timeouts (which patch 06 would
count as strikes).

### Firmware identity

The audited firmware is `mt7915_wm.bin` release
`t-neptune-mp-mt7915-2045-MT7915_MP_7_4_2045-20240429200502`, trailer build
`20240429200752`, which the driver prints as the WM firmware version. The
evidence tool reads it (`ethtool -i`, or the kernel log) and prints
`firmware_build=` and `firmware_baseline_match=`; a different build is
flagged because none of this evidence contract has been checked against it.

### Upstream bug carried along

`e4823530` dropped the `he_ext_su_cnt` accumulation in
`mt7915_mcu_muru_debug_get()`, so the `HE EXT` column and the HE DL total in
`muru_stats` were wrong on every mt7915. Patch 10 restores it.
