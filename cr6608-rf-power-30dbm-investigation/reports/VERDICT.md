# VERDICT — Can the CR6608 (MT7915) reach a REAL 30 dBm by software?

## Answer: **B — 30 dBm is NOT achievable in software on this hardware.**

Not because of UCI, not because of country/regdb (your own `iw reg get` shows those are already
open with region=PA), but because of **two stacked limits**, the second of which is physical:

1. **Driver clamp (movable):** `mt7915/init.c → __mt7915_init_txpower()`
   `chan->max_power = min_t(int, chan->max_reg_power, target_power)`.
   With regdb open, the binding term is `target_power` = **EEPROM calibrated power** (+ rate delta).
   This is exactly why `iw phy` cuts to 26 (2.4G) / 24 (5G) even though `iw reg get` is high.
2. **PA / front-end P1dB (NOT movable in software):** the EEPROM target is set *at* the integrated
   PA's linear limit. MT7915 is a ~20–22 dBm/chain part; 2×2 combine ≈ +3 dB ⇒ ~23–26 dBm composite.
   That ceiling **is** your measurement. Pushing the requested number past it produces **clipping**
   (EVM/mask failure, more retries), not more usable power. 30 dBm = 1 W is ~4–7 dB beyond the
   transistor's clean limit.

So a "30" in `iwinfo` is achievable as a **number** (patch the `min_t`), but it would be the fake
win you explicitly forbade — Phase‑4 station/survey would show no real signal/bitrate gain.

## Where the cut happens, exactly
| Layer | File / mechanism | Is it the limiter here? |
|---|---|---|
| regulatory / cfg80211 | regdb `max_eirp`, region=PA | **No** — already open (your `iw reg get`) |
| driver SKU limit | `mt7915_mcu_set_sku_en()` / `sku_limit_en` | Secondary gate, small effect |
| **driver cal clamp** | `__mt7915_init_txpower()` `min_t(...target_power)` | **Yes — the visible cut to 26/24** |
| **EEPROM target** | `MT_EE_TX0/1_POWER_*` @ `0x2fc`/`0x34b` | **Yes — the value being clamped to** |
| **PA / FEM P1dB** | silicon | **Yes — the real physical ceiling** |

## Highest *realistic* clean values (software only, expect to PROVE via Phase 4, not assume)
| Band/Chan | Your now | Realistic clean ceiling (software) | Why |
|---|---|---|---|
| 2.4 GHz | 26 | **~27–28** | 2.4G FEM usually has a little margin above cal target |
| 5 GHz ch36 (UNII‑1) | 23–24 | **~24–25** | low band, least PA droop, near cal already |
| 5 GHz ch149 (UNII‑3) | `<measure>` | **~22–24** | high band PA droop is worst; often *below* ch36 |

These are *estimates of clean output*; the only truth is Phase‑4 with EVM/retries. Anything labeled
30 without that proof is rejected.

## Hardware plan to actually reach 30 dBm EIRP
You reach 30 dBm **EIRP** far more cheaply via antenna gain than via raw conducted power.

1. **Antenna gain (cheapest, legal, real):** swap stock ~3–5 dBi for **higher-gain** antennas.
   EIRP = conducted + antenna gain − cable loss. 24 dBm conducted + 6 dBi = **30 dBm EIRP** with
   *zero* RF redesign. This is almost certainly what you actually want. Directional (panel/yagi)
   gives the biggest, most useful gain.
2. **External PA / FEM:** add a 5 GHz/2.4 GHz power amplifier module after the chip's TX path
   (e.g. a Qorvo/Skyworks FEM). Requires PCB rework or an inline bidirectional amp, proper
   TX/RX switching, and re‑calibration. Real +6–10 dB but: heat, EVM, legality, and it can't be
   driven from the chip's existing matched output without an external board.
3. **Band-pass filter** after the PA to keep the wider/clipped spectrum legal (mask/OBW).
4. **Power/supply:** a 1 W-class PA needs clean, higher‑current 3.3/5 V; budget for LDO/DC‑DC headroom.
5. **Cooling:** PA + chip at sustained high power need a heatsink/airflow or you'll thermal‑throttle
   (mt76 TSSI/thermal will back power off — visible in dmesg).
6. **RF measurement:** verify with a **spectrum analyzer + power meter** (or a calibrated SDR with
   attenuator). Conducted power at the connector, plus EVM/mask. Never trust `iwinfo` for RF truth.

## Bottom line
- **Software ceiling:** ~27–28 dBm (2.4G), ~24–25 dBm (5G low) — *if* Phase 4 proves it clean.
- **Real 30 dBm:** only via **antenna gain (do this)** or **external PA (hard)**, not via EEPROM/driver.
- No build claiming 30 dBm is provided, because none can be honestly proven on this silicon.
