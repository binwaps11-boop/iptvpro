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

## Upstream history (governing commits, verified in the mt76 tree)

Every statement below was checked against the full upstream history at
`github.com/openwrt/mt76` and against MediaTek's official 25.12 feed
(`github.com/mediatek/mtk-openwrt-feeds` at `629dc1c1`, the commit this kit
pins). Hashes are upstream mt76 commits.

| commit | date | author | what it did | quoted rationale |
|---|---|---|---|---|
| `135a5085` | 2020-04-25 | Ryder Lee (MediaTek) | first HE peer support; `ofdma_dl/ofdma_ul/mimo_dl/mimo_ul` all `true` | — |
| `75977a85` | 2020-09-29 | Felix Fietkau | removed `ofdma_ul_en` **and** `mimo_ul_en` | "The feature is not ready in firmware yet, and it leads to hangs" |
| `cfbbd861` | 2021-10-18 | Shayne Chen (MediaTek) | restored `mimo_ul_en` for all chips and replaced a direct MIB register write with `MCU_EXT_CMD_RX_AIRTIME_CTRL` (0x4a) | "For sending trigger frames, one of the conditions fw uses is to check if mib rx airtime meets the threshold … we need to enable the register by mcu cmd" |
| `f1f505cb` | 2021-10-18 | MediaTek | `MURU_SET_PLATFORM_TYPE` = `PERF_LEVEL_2` at init | "notify fw to init corresponding algorithm" |
| `abd80cf6` | 2022-02-15 | MeiChia Chiu (MediaTek) | moved the `cfg.*_en` assignments above the `has_he` early return so every station carries the same bits | "The muru enable/disable are only set after the first station connection. Without this patch, the firmware couldn't enable muru if the first connected station is non-HE type." |
| `e5228343` | 2022-06-21 | Felix Fietkau | wrapped `mimo_ul_en` and the HE PHY CAP2 `UL_MU_FULL\|PARTIAL` advertisement in `if (!is_mt7915())` | "it can produce multi-second latency spikes and tx hangs when pushing traffic. It should work better for MT7916 and MT7986" |
| `a2838480` | 2025-05-15 | Howard Hsu (MediaTek) | removed `UL_MU_PARTIAL_MU_MIMO` family-wide; **left the `is_mt7915` guard in place** | "The firmware only supports full bandwidth UL MU-MIMO" |

Facts that follow from the table and from the blobs:

- `cfg.ofdma_ul_en` has never been set by upstream for **any** chip since
  `75977a85` — not for mt7916/mt7981/mt7986 and not for mt7996 either. The only
  precedent for bit 1 (UL OFDMA) is MediaTek's downstream default
  `phy->muru_onoff = OFDMA_DL | OFDMA_UL | MUMIMO_DL | MUMIMO_UL` (0099 patch
  line 1960), mapped straight into `STA_REC_MURU` (lines 3843–3845).
- Upstream mt7996's "full UL MU support" is only the B22 advertisement plus the
  same `STA_REC_MURU` TLV with the DL bits set; it sends no global MU command
  that mt7915 lacks. There is no missing "UL enable" command to copy.
- The 2022 hang report (`e5228343`) was made against the firmware of
  `4876688c` (2022-01-11). The blob this kit pins — `mt7915_wm.bin`
  `73ae4c95…`, firmware `20240429200502` (`6ccafa50`, 2024-08-05) — is two
  releases newer and is **byte-identical** in OpenWrt 25.12.5's mt76 pin
  (`39c960c3`), in MediaTek's 25.12 downstream base (`9f95baf9`) and in
  MediaTek's legacy 5.4 release tree. MediaTek ships all four scheduler bits on,
  for every peer, on exactly this blob; its hostapd `MU_SET` path is inert on
  mt7915 because `mt7915_vendor_register()` returns before registering the
  vendor commands, so the 0xF default is what their mt7915 product runs.
- The firmware decides per WCID whether to trigger a peer. Its own log strings
  say so: `fgTrigOn=FALSE, OMI_UL_MU_DISABLE = TRUE`,
  `fgTrigOn=FALSE, Invalid BSR or SUCC cnt`, `fgTrigOn=TRUE, Valid BSR and SUCC
  cnt`. Uplink scheduling therefore also depends on the client sending valid
  BSRs and not disabling UL MU through OM control — a client-side condition no
  host bit can override.
- MediaTek's downstream does **not** re-advertise HE PHY CAP2 B22
  (`UL_MU_FULL_MU_MIMO`) for mt7915 while enabling `mimo_ul_en`; this kit
  advertises it when bit 3 is armed. That is the single capability-level
  divergence from MediaTek and is an open over-the-air question, not a defect.

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

No global MURU_CTRL command beyond upstream's own is sent. On the normal
association path both upstream `39c960c3` and MediaTek's 25.12 downstream send
exactly one: `MURU_SET_PLATFORM_TYPE` (25) = `PERF_LEVEL_2` at
`mt7915_mcu_init()`, which this tree keeps, followed by `RX_AIRTIME_CTRL`
(0x4a), the MIB rx-airtime enable that MediaTek documented as a firmware
precondition for sending Trigger frames (commit `cfbbd861`). MediaTek's
additional sub-commands (`BSRP_CTRL`=1, `SUTX`=16, `MUMIMO_CTRL`=17,
`MANUAL_CFG`=100, `MU_DL_ACK_POLICY`=200, `TRIG_TYPE`=201, `20M_DYN_ALGO`=202,
`PROT_FRAME_THR`=204, `CERT_MU_EDCA_OVERRIDE`=205) are reachable in their tree
only from the unregistered vendor path, a debugfs knob, or the Wi-Fi Alliance
certification path, never from association; this tree deliberately sends none
of them, and the source gates reject any patch that adds one. (Earlier
revisions of this document referred to "legacy global commands 80/81"; no such
command IDs exist in MediaTek's patches, upstream mt76, or the firmware, and
the wording was wrong.) The project
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
