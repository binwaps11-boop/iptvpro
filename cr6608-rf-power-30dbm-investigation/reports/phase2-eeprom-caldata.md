# Phase 2 — EEPROM / Factory / caldata analysis (MT7915, CR6608)

> Offsets below are **verified from OpenWrt mt76 `mt7915/eeprom.h`**, not from memory.
> The CR6608 uses the MT7915 EEPROM **v1 layout** (flash/Factory-backed). If your Phase‑1
> dmesg shows `eeprom load fail` → `load_default`, you are running the bin-file default and the
> table is whatever ships in `mt7915_eeprom.bin` (firmware package), not the Factory partition.

## 2.1 Where caldata lives

- Partition: on Xiaomi MT7915 boards the calibration partition is named **`Factory`** (capital F),
  typically `mtd5`/`mtd6`. Confirm from Phase‑1 §1 (`cat /proc/mtd`). It is **not** `art` (that's an
  Atheros/ath name) and not lowercase `factory`.
- The driver reads it via **nvmem/DTS** (`mediatek,mtd-eeprom = <&factory 0x0>`), or via the
  `mt7915_eeprom.bin` default if the DTS/Factory read fails. Phase‑1 §2/§3 confirms which path.
- EEPROM size for MT7915: **0x1000 (4096 bytes)**.
- MAC address: stored in Factory; the wifi MAC is at the board's `mediatek,mtd-eeprom` base
  (MT7915 `MT_EE_MAC_ADDR = 0x004`). **We do not touch it.**

## 2.2 Field table (the fields that matter for your 26/24 ceiling)

| Field | Offset | Old value (read in Phase‑1) | Meaning | Current dBm limit | Can change? | Risk | Checksum impact |
|---|---|---|---|---|---|---|---|
| `MT_EE_TX0_POWER_2G` | `0x2fc` | `<fill>` | Chain‑0 target (calibrated) power, 2.4 GHz | maps to your ~26 dBm composite | Yes (byte) | **High** — sets PA drive point | MT7915 v1 EEPROM has **no global CRC** the driver enforces; mt76 does not recompute one. But TSSI/PA cal becomes inconsistent. |
| `MT_EE_TX1_POWER_2G` | `0x2fc + stride` | `<fill>` | Chain‑1 target power, 2.4 GHz | adds +3 dB combine | Yes | High | same |
| `MT_EE_TX0_POWER_5G` | `0x34b` | `<fill>` | Chain‑0 target power, 5 GHz (12‑byte stride per chain, per sub‑band) | maps to your ~23–24 dBm | Yes | **High** | same |
| `MT_EE_TX1_POWER_5G` | `0x34b + stride` | `<fill>` | Chain‑1 target power, 5 GHz | +3 dB combine | Yes | High | same |
| `MT_EE_RATE_DELTA_2G` | `0x252` | `<fill>` | Per‑rate backoff vs target (bit7 EN, bit6 sign, bits5:0 mag, 0.5 dB units) | subtracts from target | Yes | Med | none |
| `MT_EE_RATE_DELTA_5G` | `0x29d` | `<fill>` | Per‑rate backoff, 5 GHz | subtracts | Yes | Med | none |
| `MT_EE_WIFI_CONF0` TX_PATH | `GENMASK(2,0)` | `<fill>` | Number of TX chains enabled | 2 (2x2) expected | No (HW) | High | n/a |
| `MT_EE_MAC_ADDR` | `0x004` | `<read-only>` | Station MAC | — | **NO — forbidden** | Bricks identity | n/a |

> `RATE_DELTA` decode: `EN = byte & 0x80`, `sign = byte & 0x40` (set ⇒ negative),
> `mag = (byte & 0x3F)` in **0.5 dB** steps. So `0xC4` = enabled, negative, 4×0.5 = **−2.0 dB**.

## 2.3 Why 2.4 G stops at 26 and 5 G stops at 24 — ruling each cause in/out

| Hypothesis | Verdict | Evidence |
|---|---|---|
| **caldata target power** (`TX0/1_POWER_*`) | **PRIMARY CAUSE** | `__mt7915_init_txpower()` sets `chan->max_power = min_t(int, chan->max_reg_power, target_power)`. With region=PA, `max_reg_power` is high, so the binding limit is `target_power` = EEPROM value (+ rate delta). 26/24 dBm == the calibrated composite targets. |
| **per-rate table** (`RATE_DELTA`) | Contributing, per-rate only | Subtracts a few dB on specific MCS; explains why a single MCS is lower than the band max, not the band ceiling itself. |
| **PA / FEM limit** | **ROOT physical cause** | MT7915 internal PA (CR6608 has no external 5G FEM giving +6 dB headroom). The cal target *is* the PA's linear max. Raising EEPROM above it = clipping, not more clean power. |
| **mt76 clamp** | Mechanism, not source | The `min_t()` is just the messenger; it clamps *to* the cal target. See Phase 3. |
| **EIRP / antenna gain** | Bookkeeping | mt76 v1 does **not** subtract antenna gain from conducted power on this path; iwinfo shows conducted, so this is not why you're at 26/24. |
| **regulatory (regdb)** | **RULED OUT** by your own data | You said `iw reg get` shows high limits and region=PA applied, yet `iw phy` still cut. So regdb is *not* the binding constraint. ✔ matches your finding. |

## 2.4 Does editing EEPROM give real RF or just clipping?

- Raising `TX0/1_POWER_*` above the calibrated point **does** make the driver request more drive,
  but the on‑chip PA is already near its **P1dB compression** at the cal target. Past that:
  - output power rises only fractionally (diminishing dB-per-step),
  - **EVM degrades**, spectral mask / OBW fails, retries rise, *effective* throughput can drop,
  - TSSI loop and thermal back-off may fight the change.
- Net: a few **EEPROM** dB may be real on 2.4 G (FEM has some margin), but **30 dBm is not** reachable
  this way on either band — see `VERDICT.md`. The honest test is Phase‑4 station/survey, not iwinfo.
