# CR6608 — engineering report and build path

Device: Xiaomi Mi Router CR6608 (MT7621A SoC + MT7915 Wi-Fi, ramips/mt7621).
Base: OpenWrt `v25.12.5`, mt76 pinned at `39c960c3ada558b4c2e7915772483d3731573d09`.

`source-kit/` is the CR6608 source kit, plus two new driver patches and the
tooling described below. `source-kit/DERIVED-TREE.md` records exactly what was
changed and why this tree is deliberately **not** re-attested as a release.

---

## 1. The 38 dBm path — what it actually is

Traced from the source, top to bottom:

| stage | file | unit | what happens |
|---|---|---|---|
| LuCI | `patches/993-*` | dBm | list rebuilt as a plain `1..38 dBm` |
| UCI | `files/etc/config/wireless` | dBm | `option txpower '38'` on both radios |
| netifd → nl80211 | upstream | **mBm** | `txpower * 100` |
| cfg80211 → mac80211 | upstream | dBm | `local->user_power_level` |
| mac80211 | `net/mac80211/main.c` | dBm | `power = min(user_power_level, ieee80211_chandef_max_power(&chandef))` |
| **ceiling raise** | `patches/999-*` → `__mt7915_init_txpower()` | dBm | with the gate armed, `chan->max_power = min(target_power, 38)` instead of `min(chan->max_reg_power, target_power)` |
| mt76 | `mt76_get_power_bound()` | **half-dBm** | `txpower*2`, then `-= path_delta` |
| driver | `mt7915_cr6608_mcu_set_txpower_sku()` | half-dBm | builds the Rate SKU table (and the Path SKU table when device data enables it) |
| firmware | `MCU_EXT_CMD(TX_POWER_FEATURE_CTRL)` | half-dBm | table written, then **read back** |
| verification | same function | half-dBm | requires `readback_peak == requested*2 - path_delta`, else rollback or recovery |
| published | `mphy->txpower_cur` | dBm | set only after that readback passes |

`path_delta` is `{0, 6, 9, 12, 14}[chains-1]` in half-dBm. The CR6608 is 2x2,
so `path_delta = 6` (3 dB), and 38 dBm requires a per-chain SKU cap of
`38*2 - 6 = 70` half-dBm = **35 dBm per chain**.

### The honest reading

This is a **real** path, not a cosmetic one. The number reaches the firmware,
the firmware echoes it back, and the driver refuses to publish the value if
the echo does not match. The `-EOPNOTSUPP` branch when `sku_limit_en` is off
exists precisely so a software-only value is never published.

It is also **not** a measurement of 38 dBm at the antenna. What the gate does
is remove the software and firmware *ceiling*, so the radio is no longer
capped below what the hardware can do. The actual radiated power is then set
by the PA/front-end and the EEPROM calibration. 35 dBm per chain conducted is
far above what the MT7915's integrated PA delivers, so the PA saturates well
below the cap; the SKU entry is a limit, not a drive level.

Separating the three things the brief asked to keep separate:

* **A — requestable / representable:** 1–38 dBm. Verified end to end above.
* **B — actually achievable:** bounded by the PA, front-end and calibration,
  not by this number. Requires a conducted RF measurement to state.
* **C — legally permitted:** the regulatory ceiling for the active country.
  The gate deliberately bypasses `chan->max_reg_power`, which is why every
  profile using it is marked `sale_ready=NO`. DFS, SAR, per-rate and thermal
  limits all remain active.

Nothing in the 38 dBm path was modified. Every power-related file is
byte-identical to the received kit (verified by `cmp`); see
`source-kit/DERIVED-TREE.md`.

---

## 2. MU-RU — the defect found, and the fix

### Root cause

The kit had exactly one MU-RU shutdown primitive,
`mt7915_cr6608_muru_fault_latch()`. It cleared the scheduler mask **and** spent
a one-way latch that only a fresh driver load can release. It was called from
every recovery path, including:

* `mt7915_mcu_schedule_full_recovery()` — the shared entry point that the
  **38 dBm SKU transaction** calls when a snapshot, readback or rollback
  cannot be verified;
* `mt7915_regd_notifier()` — every regulatory update landing on a pending
  reconfiguration;
* `mt7915_mcu_parse_response()` — **any** timed-out MCU command.

The `ul-forced-lab` profile runs `cr6608_rf_38dbm=1` *and*
`cr6608_muru_mask=15`. So on the exact image in use, one regulatory refresh,
one unrelated MCU timeout, or one unverifiable SKU transaction permanently
disabled every MU-RU bit for the rest of the uptime — with no watchdog, no TX
hang, and nothing wrong with the scheduler.

That is the mechanism behind "MU is off because of the MediaTek firmware". In
this stack the uplink feature was being switched off by the **power** path.

A second regression followed from the same primitive: once the mask hit zero,
`mt7915_mcu_sta_muru_tlv()` computed `mask = 0`, so `ofdma_dl_en` and
`mimo_dl_en` went false too. Upstream MT7915 always requests DL OFDMA and
requests DL MU-MIMO for a beamforming-capable BSS, so a failed *uplink*
experiment dragged the radio **below** plain upstream downlink behaviour.

### Patch 06 — fault attribution, guarded re-arm, upstream DL floor

`patches/zzzzzz-06-mt7915-cr6608-muru-fault-attribution.patch`

Every recovery still disarms the scheduler before the firmware is reset, so
the fail-closed property is unchanged. What changed is attribution:

* **latch** (permanent) for a MAC/MCU **watchdog** reset — the exact failure
  mode upstream cited when it removed MT7915 UL-MU — for a timed-out
  `STA_REC_UPDATE`, and for a station-record mask race;
* **disarm + one strike** for everything else, then re-arm after a *verified*
  reset, before mac80211 replays the station records, so the replayed
  `STA_REC_MURU` transactions carry the restored bits;
* re-arm restores a **one-way ceiling** only — seeded from the operator-locked
  boot mask, lowered by the debugfs writers and zeroed by the latch — so it
  can never resurrect a bit an operator or a real fault already retired;
* three unattributed strikes convert to a permanent latch;
* a `cr6608_muru_dl_floor` keeps DL OFDMA and DL MU-MIMO requested through any
  uplink fault. Only an explicit operator mask write retires a DL bit.

### Patch 07 — client-attributed uplink evidence

`patches/zzzzzz-07-mt7915-cr6608-muru-ul-tb-attribution.patch`

`docs/CR6608-STOCK-MURU-PORT.md` listed client-attributed OTA evidence as a
promotion blocker solvable only with capture hardware. This patch produces it
from data the driver already receives.

A HE trigger-based (TB) PPDU exists **only** as a response to a Trigger frame
the AP transmitted, and the RX descriptor carries the transmitting peer's WCID
plus the HE RU allocation. So:

* per-WCID `MT_PHY_TYPE_HE_TB` counts = per-client proof the scheduler
  solicited uplink airtime from that client;
* RU smaller than the operating bandwidth → **UL OFDMA** for that peer;
* two or more **distinct** peers whose TB PPDUs share the same PHY start
  timestamp → a real simultaneous uplink multi-user transmission: on full
  bandwidth that is full-bandwidth **UL MU-MIMO**, the only uplink MIMO mode
  MT7915 supports.

Read-only, and active only while an uplink bit is armed, so the retail and
mask-0 profiles pay nothing. Exposed as `cr6608_ul_attribution` per phy and
per station, and summarised by `cr6608-ul-mu-evidence`.

### Second pass — evidence audit findings (patches 08–10)

A multi-source audit (full upstream mt76 history, MediaTek's official 25.12
feed at the kit-pinned commit, the firmware blobs themselves) established:

- The MT7915 firmware blob is **byte-identical** across OpenWrt 25.12.5,
  MediaTek's 25.12 downstream and MediaTek's legacy 5.4 tree: release
  `MT7915_MP_7_4_2045`, built 2024-04-29, two releases newer than the 2022
  hang report upstream's guard still rests on. It demonstrably contains a
  trigger-based uplink scheduler (BSRP handling, Trigger composition, per-WCID
  `fgTrigOn` decisions, `UL OFDMA / UL MU-MIMO` counters).
- MediaTek ships mt7915 with all four scheduler bits on for **every** peer,
  through the same `STA_REC_MURU` path, with **no** global enable command and
  **without** advertising B22.
- Upstream `abd80cf6`: the firmware latches MURU from the **first** station
  record. The kit's per-peer downgrade could leave UL unarmed for the whole
  BSS if a legacy or non-B22 client associated first — patch 09 fixes it.
- Patch 07's per-peer counters were **unreachable** on MT7915 (RXD group 5 is
  off outside monitor mode) — patch 10 makes that state visible and adds a
  bounded opt-in window instead of pretending.
- The "commands 80/81" the kit claimed to withhold do not exist; the gates now
  name MediaTek's real MURU_CTRL inventory.
- The firmware triggers a peer only on valid BSRs, with OM-control UL-MU not
  disabled, and when its RX-airtime threshold is met — a quiet or
  single-client test legitimately shows zero.

Patch 08 adds live station-record refresh (no Wi-Fi reload) and strike decay.

### Third pass — lifecycle audit findings (patches 11–14, OpenWrt patch 994)

An eight-source audit (station-record flow, recovery lifecycle, firmware
statistics, HE capabilities, hostapd/netifd, MediaTek downstream, upstream
history, firmware blob) of the *previous* passes found defects in this work's
own patches. All are fixed from source; none adds a firmware command.

- **Replay raced the station lifecycle.** The live record replay and the
  ASSOC/AUTHORIZE/DISASSOC transitions ran without `dev->mt76.mutex`
  (mac80211 holds it only for add/remove), so a replay could downgrade a
  freshly authorised peer in firmware or touch a peer being freed. Both now
  hold the mutex, exactly as `mt7996` does (patch 11).
- **Host mask changes were booked as firmware faults.** An operator mask
  write or kill switch racing an association spent the *permanent* latch and
  forced a full firmware reset. A stale record is now rebuilt or re-queued;
  a `STA_REC` failure inside a recovery already in flight is attributed to
  that recovery (patch 11).
- **A refused re-arm left firmware records armed** after a partial reset
  while the host reported mask 0; every verified partial reset now replays
  the records, and a replay that meets a reset window is parked and re-run
  instead of dropped (patch 11).
- **Strikes were charged with the scheduler never exercised** (a post-load
  recovery loop with zero peers latched after three rounds), **handshake
  acknowledgements disarmed the mask**, **host-initiated recoveries struck**,
  **strike decay was dead on a 5 GHz-only router**, and an operator `fw_ser`
  reset spent the latch. All fixed (patch 13).
- **Per-peer TB counters were unreachable on every OpenWrt image**, not only
  because of RXD group 5: the mt76 package never passes
  `CONFIG_MAC80211_DEBUGFS` to the driver, so the per-station debugfs hook is
  compiled out regardless of `CONFIG_PACKAGE_MAC80211_DEBUGFS`. OpenWrt patch
  994 forwards it, and the CI proof step now checks the compiled module for
  the per-peer nodes. The earlier CI proof also relied on `parm=` modinfo
  records that OpenWrt's `MODULE_STRIPPED` kernel drops; it now checks the
  parameter name strings.
- **The counters counted descriptors, not PPDUs; BSR-poll QoS-Null responses
  counted as data; only the second peer of a MU-MIMO group was credited.**
  Patch 14 deduplicates per PPDU, splits data from null frames, credits every
  peer, guards missing timestamps and failed FCS, and prints the firmware
  counters as `key=value` lines with their real semantics: the firmware's
  `hetrig_*` counters are TX-command-side trigger accounting; nothing
  host-visible proves a bucket means a *received* TB PPDU. Host attribution
  is the only such proof.
- Upstream `e59324380042` (HE DCM max-RU encoding, not in the 25.12.5 pin)
  is backported verbatim (patch 12).

`cr6608-ul-mu-evidence` v4 turns this into a controlled protocol: idle,
download-only and upload phases with the same window, data-only multi-user
pass criteria from two distinct peers, firmware non-SU trigger minimums, and
an invalid result if the armed mask, group-5 state or firmware reset counters
change during the run. The verifiers no longer assume "armed implies B22": the
beacon is checked against the driver's boot-frozen vendor-parity decision.

### What was deliberately not done

No new or undocumented MCU command was added. `MURU_CTRL` sub-commands beyond
what upstream already sends, MediaTek's unregistered nl80211 vendor command,
and the legacy global commands 80/81 are all still unused. Guessing at an
undocumented firmware command is the fastest way to hang this radio, and
stability was the stated priority. `tests/test-muru-fault-attribution.sh`
asserts that neither new patch introduces one.

---

## 3. Verification actually performed

| check | result |
|---|---|
| 19 mt76 patches vs pinned mt76 `39c960c3` | all apply with `patch -F0`, **zero fuzz**; resulting tree byte-identical to the compiled one |
| DTS gates 996 + 996a and Makefile patch 994 vs OpenWrt `v25.12.5` | apply clean, sequentially |
| Driver compile, `-Werror` `W=1`, Linux 6.18.26 (same mac80211 generation as OpenWrt's `backports-6.18.26`) | **0 errors, 0 warnings** at every patch stage (bisectable) |
| `mt76.ko`, `mt76-connac-lib.ko`, `mt7915e.ko` | produced; every `cr6608_*` parameter name and every proof string present in the binary |
| Source test suite, modified tree | every MURU/AX/evidence/verifier/release/txpower/38 dBm contract passes; the 10 suite scripts that fail need node, ssh-keygen, a uhttpd binary, an OpenWrt root or a compiled sender and fail identically on the untouched tree |
| Power-path files vs pristine | byte-identical (`cmp`) |
| Contract tests, mutation-tested | 14 deliberate defects injected across the new tests, all caught |
| CI image build | OpenWrt 25.12.5 image compiles on the GitHub runner (runs 1–2); the proof step is what caught the stripped-modinfo and missing-debugfs-define defects above |

### What was *not* verified, and why

**No firmware image was built here, and none is claimed.** This sandbox's
egress policy permits only `github.com` and `gitlab.com`. `kernel.org`,
`gnu.org`, `downloads.openwrt.org` and `sources.openwrt.org` are all blocked,
so `make download` cannot fetch the toolchain and package tarballs an OpenWrt
image needs. That is why the driver was compiled against a real kernel tree
instead — it is the strongest verification the environment allows.

Nothing here is an over-the-air, RF or regulatory result. No radio was
powered on.

---

## 4. Building the .bin

`.github/workflows/build-cr6608-v87.yml` builds it on a GitHub Ubuntu runner,
which has the open internet this sandbox lacks.

Actions → **Build CR6608 v87 (OpenWrt 25.12.5, 38 dBm + MU-RU mask 15)** →
Run workflow → pick a profile:

| profile | 38 dBm | MU-RU mask | notes |
|---|---|---|---|
| `ul-forced-lab` *(default)* | on | 15 | what this work targets; persistent, non-sale |
| `lab` | on | 0 | 38 dBm only |
| `ul-lab` | off | 15 | MU-RU qualification only |
| `retail` | off | 0 | radio-locked, unprovisioned |

The workflow runs the kit's source gates first, proves every driver patch
applies with zero fuzz against the pinned mt76, then verifies the CR6608
symbols in both the compiled `mt7915e.ko` and the `.ko` unpacked from the
finished image, and fails if any are missing. Roughly 1–2 hours.

This is an **engineering build**, not the kit's attested release pipeline
(`source-kit/build.sh`), which additionally needs the private signing keys, an
independently delivered operator trust record, privileged network-namespace
rescue evidence, and a pinned Playwright/Chromium install.

---

## 5. On-device checks after flashing

```sh
# Power: requested vs regulatory vs what the MCU actually accepted
cr6608-txpower-verify
cat /sys/module/mt7915e/parameters/cr6608_rf_band0_sku_applied_per_path_half_dbm

# MU-RU host state, including the new lifecycle counters
cat /sys/kernel/debug/ieee80211/phy*/mt76/cr6608_ul_muru_state
#   candidate_ceiling / upstream_dl_floor / unattributed_disarms / rearms / strikes

# Client-attributed uplink evidence: two HE clients, three phases of the same
# window (no traffic / download only / both uploading), per-client attribution
# enabled for the run only
cr6608-ul-mu-evidence --with-firmware --enable-crxv --phases idle,dl,ul --window 60
```

The tool prompts before each phase (`--auto` skips the prompts, `--hook CMD`
runs a traffic script per phase). Verdicts on the upload phase:

* `UL_MUMIMO_FULL_BW_DATA_MULTI_USER_OBSERVED_ON_DEVICE` — ≥ 10 full-bandwidth
  PPDUs carrying data from two distinct peers, both credited, firmware
  MU-MIMO trigger count ≥ 10, upload phase ≥ 3× both control phases.
* `UL_OFDMA_DATA_MULTI_USER_OBSERVED_ON_DEVICE` — same on sub-bandwidth RUs,
  firmware non-SU triggers ≥ 20.
* `BSR_POLL_RESPONSES_ONLY` — multi-user PPDUs seen but none carried data
  from two peers: clients answer the firmware's BSR polls, nobody uploads.
* `TRIGGER_RESPONSE_SINGLE_USER_ONLY`, `NO_TRIGGER_ACTIVITY`,
  `INSUFFICIENT_MULTI_USER_DATA_PPDUS`, `INCONCLUSIVE_*` (control phase not
  exceeded, firmware below minimum, host exceeds firmware),
  `INVALID_STATE_CHANGED_DURING_WINDOW` (mask, group 5 or a firmware reset
  changed mid-run), `HOST_ATTRIBUTION_UNAVAILABLE_RXV_GROUP5_OFF`.

A single peer, idle peers, or download-only traffic never yield a multi-user
verdict, by construction and by test. The footer says what the result is:
observed on this device in this window, not a certification, RF or
regulatory claim.

---

## 6. Honest status of each constraint

**Hardware supports:** 802.11ax on both bands, SU beamforming, DL MU-MIMO,
DL OFDMA, HE RU, DFS with background CAC, and — per MediaTek's own May-2025
clarification — **full-bandwidth** UL MU-MIMO only. Partial-bandwidth UL
MU-MIMO is the configuration that hung MT7915 firmware; this stack never
requests it, and never advertises it for MT7915.

**Firmware-limited:** whether the MURU scheduler actually emits Trigger frames
is internal to the closed `mt7915_wm.bin`. The host side is now complete and
verified — capability advertisement, per-peer `STA_REC_MURU` with all four
bits, synchronous MCU acceptance, serialised record lifecycle, fault
attribution, recovery. Documented firmware limits, all with evidence in
`source-kit/docs/`: full-bandwidth UL MU-MIMO only; MURU enable latched from
the first station record; per-peer trigger decisions keyed on BSR validity,
OM-control and RX airtime, readable only from the firmware log; the only
host-readable uplink statistics are ten clear-on-read TX-command-side trigger
buckets with no per-peer breakdown and no proof of TB reception; per-packet
PHY type only with RXD group 5. Patches 07/14 and the v4 evidence protocol
exist precisely because the last step can only be settled by observation on
the device, and it now can be.

**Regulatory-limited:** 38 dBm exceeds the ceiling of essentially every
regulatory domain. The gate bypasses `chan->max_reg_power` by design, which is
why every profile that uses it records `sale_ready=NO`. Legal operation
requires a regulatory ceiling, not this one.

**Remaining blockers before this could be called production support** (from
`source-kit/docs/CR6608-STOCK-MURU-PORT.md`, all still open): long-duration
mixed-traffic, reconnect, channel-change, reboot and thermal stress with zero
fault latches; conducted/radiated RF, DFS and coexistence testing; market
regulatory approval; confirmation that ordinary non-MU clients do not regress;
and a separately reviewed retail profile.
