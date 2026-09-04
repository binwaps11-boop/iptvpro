# CR6608 MediaTek 25.12 MURU qualification port

## Evidence boundary

This source contains a reviewable MT7915 MURU bitmap port based on MediaTek's
public OpenWrt 25.12 downstream policy. It does not contain Xiaomi's proprietary
Linux 4.4 `mt_wifi` driver and does not send undocumented Xiaomi or legacy SWRT
firmware commands.

The normal `lab` and `retail` profiles omit the CR6608 UL-MURU DTS property and
keep both the legacy boolean and `cr6608_muru_mask` at zero. The `ul-lab` build
applies the dedicated DTS gate and requests mask `15` in initramfs for RAM-only
qualification. The separate `ul-forced-lab` profile also requests mask `15`
persistently and can publish flashable LAB artifacts. Both profiles remain
explicitly non-sale; persistence does not establish firmware application,
over-air scheduling, OTA proof, or regulatory approval.

Upstream removed MT7915 HE UL-MU advertisement after firmware hangs. MediaTek's
current downstream patch also leaves its nl80211 vendor registration disabled
and does not remove that upstream guard. Consequently, this local port is a
controlled qualification candidate, not official product support. A successful
compile, driver load, capability advertisement, or station-record update does
not prove UL airtime or retail safety.

## Pinned baseline and bitmap

The authoritative hashes, commits, and firmware identities are recorded in
`docs/MT7915-MURU-VENDOR-BASELINE.md` and enforced by
`tools/verify-mt7915-muru-firmware.sh`. The local mapping preserves MediaTek's
four-bit `mu_onoff` layout exactly:

| Bit | Value | Scheduler request |
|---:|---:|---|
| 0 | 1 | DL OFDMA |
| 1 | 2 | UL OFDMA |
| 2 | 4 | DL MU-MIMO |
| 3 | 8 | UL MU-MIMO |

Mask `15` requests all four independently. The boot parameter is read-only;
runtime debugfs writes may only clear bits. Re-enabling any cleared bit requires
a fresh driver load, and the compare/exchange path prevents a concurrent stale
write from restoring a bit cleared by the fault latch.

Primary public references:

- MediaTek OpenWrt 25.12 mt76 patch
  `0099-cp-mtk-mt76-mt7915-add-connac2-support.patch` at pinned feed commit
  `629dc1c1f90cf135394312bb5ee919f4b1999146`.
- MediaTek OpenWrt 25.12 hostapd patch
  `0020-mtk-hostapd-Add-hostapd-MU-SET-GET-control.patch` at the same commit.
- The upstream MT7915 UL-MU removal:
  <https://github.com/openwrt/mt76/commit/75977a8>.
- MediaTek's full-bandwidth MT7915 UL MU-MIMO clarification:
  <https://lists.infradead.org/pipermail/linux-mediatek/2025-May/093325.html>.

Xiaomi stock profiles setting `MuOfdmaUlEnable=1` and `MuMimoUlEnable=1` are
corroborating evidence only. They do not make an independent mac80211/mt76 port
equivalent to Xiaomi's opaque firmware stack.

## Maintained implementation

The CR6608 DTS gate and the read-only module mask must both pass before any MURU
bit can be active. The v86 patch stack then:

1. maps each bitmap bit independently into the normal `STA_REC_MURU` record;
2. advertises full-bandwidth UL MU-MIMO only when its independent bit is active,
   enables the per-peer MT7915 request only for a HE peer reporting the full
   capability, and never sends the unsupported partial-bandwidth request;
3. preserves peer HE/OFDMA/full/partial UL-MIMO eligibility for diagnostics;
4. sends the standard station-record update with a synchronous MCU response;
5. records attempted, command-response-ok, failed, and timed-out transactions;
6. rejects a transaction if the live mask changed before send or during the synchronous response;
7. atomically clears every MURU bit and permanently latches the fault before
   MCU timeout/reset recovery is queued;
8. exposes read-only per-phy state and per-peer eligibility through debugfs.

Legacy global firmware commands 80/81 are deliberately not sent. The project
also does not register or depend on MediaTek's currently skipped nl80211 vendor
control. This keeps the qualification surface limited to the reviewed
station-record path and the immutable boot profile.

The full-bandwidth restriction is MT7915-specific. Non-MT7915 behavior remains
on its upstream path. In the UL-lab profile, a non-HE/VHT peer retains the
stable DL OFDMA/DL MU-MIMO bits while both UL bits are forced off, so UL
qualification cannot regress official VHT DL MU-MIMO behavior.

## Runtime proof

`cr6608_ul_muru_state` reports `candidate_*` fields for this qualification
port's requested mask and decoded bits, plus the one-way fault state/count and
attempted/response-ok/failed/timeout counters. These fields deliberately do not
claim to report the effective upstream DL scheduler state when the candidate
port is disabled. A dedicated spinlock makes every cross-counter debugfs read a
real snapshot; response, HE-peer and MIMO-peer updates are published as one
group, as are failure/timeout and fault-flag/fault-count updates.
`response-ok` means only that the synchronous command returned success; it is
not proof that Firmware applied the scheduler state or that an OTA PPDU occurred.
Each associated station may expose a read-only `cr6608_muru_capabilities`
record. `cr6608-ul-muru-verify` keeps host-path readiness separate from firmware
airtime counters.

`cr6608-ul-muru-airtest` is stricter: before and after the sample window it
requires the immutable UL-lab profile, mask 15, a clean kernel fault/telemetry
snapshot, and a fresh armed guard heartbeat. It maps the selected AP interface
to its exact phy and requires two simultaneously uploading HE clients that
advertise full-bandwidth UL MU-MIMO.

Positive `Total HE MU-MIMO UL TB PPDU count` and `Total HE OFDMA UL TB PPDU
count` deltas are only same-radio aggregate counter correlations. They cannot
attribute a PPDU to either selected client. The success token therefore ends in
`BOTH_RADIO_COUNTERS_CORRELATED_NOT_CLIENT_ATTRIBUTED`; it is not an OTA feature
pass.

Client-attributed OTA proof requires appropriate capture hardware or reviewed
per-peer scheduler telemetry, in addition to compatible simultaneous clients.
A fabricated pass is never substituted for missing attribution evidence.

## Promotion blockers

The following are mandatory before this can be described as production support
or included in a sale-ready image:

- repeated OTA tests on both bands with at least two compatible simultaneous
  upload clients, using capture hardware or per-peer scheduler telemetry that
  independently attributes UL MU-MIMO and UL-OFDMA scheduling;
- long-duration mixed-traffic, reconnect, channel-change, reboot, temperature,
  and firmware-recovery stress with zero fault-latch or timeout events;
- conducted/radiated RF, DFS, thermal, coexistence, and market-regulatory tests;
- verification that DL behavior and ordinary non-MURU clients do not regress;
- a separately reviewed retail profile and per-device security provisioning.

Until all those gates pass, `sale_ready=NO` and the retail mask remains zero.
Any mask-15 RAM or persistent forced-LAB artifact remains qualification media,
not a retail release.
