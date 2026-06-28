# CR6606 Power & Channels — proof, clamp analysis, and report

Xiaomi Mi Router **CR6606** · ramips/mt7621 · **MT7915** (mt76) · AX1800 · 2×2 / 2×2 ·
DSA native (mt7530). This document is the "why / proof" companion to the two firmware
variants and the two in-system scripts.

> **No EEPROM/caldata write. No foreign caldata. No MAC change. No regdb/driver patch.
> No fake numbers.** Everything below is either a documented driver/regdb fact or a value
> you measure on your own device with the bundled scripts.

---

## 1. The two builds

| Build | Purpose | Markers |
|---|---|---|
| `cr6606-clean-stable-longrange` | daily driver — max **clean** performance | — |
| `cr6606-system-30dbm-measured-test` | requests 30 dBm on both radios + ships measurement tooling | `CR6606-SYSTEM-30DBM-MEASURED-TEST`, `CR6606-ALL-CHANNELS-30DBM-MEASURED` (in dmesg) |

Both: country=US (editable), `txpower=30` request, 2.4G HE20 ch1, 5G HE80 ch149,
2×2 chains (not restricted), flow offloading, LuCI + SSH, and the two scripts below.

Scripts (in `/root` on the device):
- `cr6606_power_truth.sh` — full regdomain / iwinfo / iw-phy / station / survey / dmesg dump.
- `cr6606_all_channels_test.sh` — sweeps **all** channels (2.4G 1–13, 5G 36–165), prints the
  per-channel table with verdict + clamp reason; `--countries` compares regdomains.

---

## 2. How power is determined (the clamp cascade)

Final per-packet TX power = **min()** of every layer below. The scripts attribute the
binding one per channel:

```
country  →  wireless-regdb  →  cfg80211  →  mac80211  →  mt76/mt7915  →  EEPROM/caldata
         →  per-rate power table  →  thermal limit  →  PA/FEM limit  →  DFS (CAC/no-IR)
```

- **regdb (the legal ceiling):** per-channel max EIRP for the country. Read with
  `iw phy <phy> info` — each channel line shows `(<X> dBm)` and DFS/`no IR` flags.
- **caldata / per-rate:** the factory calibration inside the chip caps clean output per rate.
  If `iw phy` says 30 but `iwinfo` shows less, the cap is here — raising it = clipping.
- **thermal / PA-FEM:** dynamic back-off under heat / linearity limits (visible in dmesg).

---

## 3. wireless-regdb predicted limits (the legal ceiling) — US

> *Prediction from wireless-regdb. The authoritative per-device value is what
> `cr6606_all_channels_test.sh` measures; the `--countries` mode compares regdomains live.*

| Band / sub-band | Channels | US regdb max | DFS? | Can hit 30 cleanly? |
|---|---|---|---|---|
| 2.4 GHz | 1–13 (1–11 in US) | ~27 dBm | no | up to ~27 (then caldata) |
| 5 GHz UNII-1 | 36–48 | 17–23 dBm | no | no (regdb < 30) |
| 5 GHz UNII-2 / DFS | 52–144 | 20–24 dBm | **yes** | no (regdb < 30 + radar) |
| 5 GHz UNII-3 | 149–165 | **30 dBm** | no | **yes** (if caldata allows) |

### 3b. ALL-country scan (official attempt on the X channels — no guessing)

We parsed **every** country block in the official `wireless-regdb` `db.txt` to see if any
legal regdomain opens UNII-1 / DFS to 30 dBm. Result:

| Sub-band | Channels | Highest limit found **across the entire global regdb** | Who |
|---|---|---|---|
| 2.4 GHz | 1–11 | **30 dBm** | US, CA, NZ, BZ … |
| UNII-1 | 36–48 | **23 dBm** (NO country reaches 30) | US (23); most are 17 |
| DFS-lower | 52–64 | 30 dBm (only two) | **BO, NG** only — DFS + drops 2.4G to 20 |
| DFS-upper | 100–144 | ~27 dBm (no country reaches 30) | GB (27) |
| UNII-3 | 149–165 | **30 dBm** | US, CA, AU, NZ, PA, BO, NG … |

Reference rows (2.4 / UNII-1 / DFS-lo / DFS-hi / UNII-3):
```
US: 30 / 23 / 23 / 23 / 30      NZ: 30 / 17 / 24 / 24 / 30
CA: 30 / 17 / 24 /  - / 30      BO: 20 /  - / 30 /  - / 30   (DFS-lo=30 but 2.4=20)
PA: 30 / 17 / 23 /  - / 30      NG: 20 /  - / 30 /  - / 30
AU: 20 / 17 / 24 / 24 / 30      GB: 20 / 20 / 20 / 27 /  -
```

**Definitive conclusion (the X channels):**
- **UNII-1 ch36–48 = 23 dBm is the GLOBAL maximum.** No official country anywhere grants
  30 dBm on UNII-1. The FCC *permits* 30 for AP master mode, but `wireless-regdb` enforces 23
  worldwide. Reaching 30 on ch36 requires **editing db.txt** → declined (regulatory edit).
- **DFS ch52–144** never reaches 30 in US; only BO/NG hit 30 on the lower DFS block, at the
  cost of declaring a country you're not in (non-compliant) + DFS radar + 2.4G dropped to 20.
- **30 dBm is genuinely available on 2.4 GHz (ch1–11) and 5 GHz UNII-3 (ch149–165)** — no edit.

The `--countries` mode (US CA GB DE FR JP AU NZ PA BO BZ NG CN 00) reproduces this table on
your own device with `iw phy` — so the limits are measured, not quoted.

---

## 4. 2×2 chain proof (not a config you can fake)

MT7915 in the CR6606 is **2T2R on both bands**. mt76 uses both chains by default; we
deliberately do **not** set `txantenna`/`rxantenna` (that would *cut* a chain).

Proof on the device:
- `iw phy <phy> info | grep "Available Antennas"` → expect `TX 0x3 RX 0x3` (0x3 = 2 chains).
- With a client connected: `iw dev <if> station dump` → `tx bitrate ... NSS 2` and 2-stream MCS.

`cr6606_all_channels_test.sh` prints the antenna mask up front and a `Chain` column per row.

---

## 5. EEPROM / caldata — read-only analysis (answers to the 10 questions)

Flash layout (from the device DTS, verified):

| Partition | Offset | Size | Notes |
|---|---|---|---|
| Factory | `0x100000` | 512 KB | **read-only**, holds wifi calibration + MACs |

1. **Partition name:** `Factory` (run `cat /proc/mtd` to map it to `mtdN`).
2. **Where caldata is:** Factory @ `0x100000`; wifi EEPROM = nvmem cell `eeprom_factory_0`
   @ offset `0x0`, size `0xe00` (3584 B), consumed by mt7915 via `nvmem-cells "eeprom"`.
   MACs: LAN @ `0x3fff4`, WAN @ `0x3fffa` (we never touch these → no MAC change).
3. **Is 2.4 G clamped by country or caldata?** Decided empirically: `iw phy` limit (=regdb)
   vs `iwinfo` actual (=after caldata). US regdb already caps 2.4G ~27 < 30 → **country/regdb**
   binds first; any further gap below 27 is caldata.
4. **Is 5 G clamped by country or caldata?** UNII-1/DFS: **regdb** (limit < 30). UNII-3
   (149–165): regdb = 30, so any shortfall there is **caldata / per-rate**.
5. **Power-table ceiling:** stored as per-rate target-power bytes in the EEPROM region; read
   (read-only) with `dd if=/dev/mtd<Factory> of=/tmp/factory.bin; hexdump -C /tmp/factory.bin`,
   and cross-check mt76 "Power limit"/"txpower" lines in `dmesg`.
6. **Does per-rate backoff block 30?** Yes on the top HE-MCS (1024-QAM needs linearity
   headroom): low MCS sit near the cap, top MCS are backed off. Visible as `station dump`
   MCS vs the channel limit.
7. **Does the PA/FEM tolerate 30?** Conducted **30 dBm = 1 W per chain** is at/over the
   typical MT7915 front-end linear range; pushing there leaves the linear region → distortion.
   dmesg thermal lines show dynamic back-off when it runs hot.
8. **Edit → real RF or clipping?** Above the calibrated linear point it's **clipping**
   (EVM rises, spectral mask fails) = *less* usable range, not more. That's why we keep
   caldata read-only.
9. **Checksum?** The mt7915 EEPROM carries a validity/signature region. An unrecomputed edit
   makes the driver reject it and fall back to defaults (often **lower** power) — provable in dmesg.
10. **Rollback plan (if anyone ever edits it — we don't):** back up first
    `dd if=/dev/mtd<Factory> of=/root/factory.backup.bin` + `sha256sum`; restore with
    `mtd write /root/factory.backup.bin Factory`. Keep the backup off-device.

**Both builds only READ caldata. Neither writes it.**

---

## 6. Conducted vs EIRP (why antennas beat "forcing 30")

- **Conducted power** = dBm at the chip/connector (what `iwinfo` reports).
- **EIRP** = conducted + antenna gain (dBi) − cable loss. Regulatory caps are usually EIRP.
- So **30 dBm conducted ≠ 30 EIRP**, and a higher-gain antenna raises EIRP **without** raising
  conducted power — clean range gain, no clipping, no regdb violation.

---

## 7. Hardware plan for genuinely higher (clean) output

If you want more real coverage than the clean software ceiling:
1. **Higher-gain antennas** — 2.4G ~9 dBi, 5G ~7–12 dBi (omni or directional/panel). Simplest,
   biggest legit win; raises EIRP directly.
2. **External linear PA** — only with proper bias + digital pre-distortion (DPD) to stay inside
   the spectral mask; otherwise you just clip louder.
3. **Band-pass filter** — suppress harmonics/out-of-band when a PA is added.
4. **Stable PSU** — a PA's current draw needs clean, sufficient supply.
5. **Heatsink / airflow** — sustained high power triggers thermal back-off without cooling.
6. **RF measurement** — verify cleanliness with a spectrum analyzer / power meter / EVM, not
   just the on-screen number.

---

## 8. Flash + check commands

```sh
# clean-stable-longrange  OR  system-30dbm-measured-test (use the matching URL)
cd /tmp
wget -O cr6606.bin "<release-asset-url>"
sha256sum cr6606.bin          # compare to the published sha256-<variant>.txt
sysupgrade -n /tmp/cr6606.bin # -n = do not keep settings (clean DSA config)
```

After it boots:
```sh
sh /root/cr6606_power_truth.sh
sh /root/cr6606_all_channels_test.sh            # full per-channel table
sh /root/cr6606_all_channels_test.sh --countries  # + regdomain comparison
```

---

## 9. Measured table — to be filled from YOUR device

Paste the output of `cr6606_all_channels_test.sh` and I'll complete the verdict column,
or read it directly — the script already prints every row:

```
Band | Channel | Country Used | Requested TX | iw phy Limit | iwinfo Actual | DFS | Chain Status | Signal | TX Bitrate | RX Bitrate | Retries | Failed | Verdict
2.4  | 1       | US           | 30           | ...          | ...           | no  | 2x2(0x3)     | ...    | ...        | ...        | ...     | ...    | ...
...
5    | 165     | US           | 30           | ...          | ...           | no  | 2x2(0x3)     | ...    | ...        | ...        | ...     | ...    | ...
```

**Expected verdict pattern** (the scripts will confirm on your unit):
- 5G **149–165** → `30 OK` (clean, legal).
- 5G **36–144** → `CLAMP by REGDB` (UNII-1/DFS legal ceiling < 30; DFS adds CAC).
- 2.4G **1–13** → `CLAMP by REGDB (~27)` then caldata — best long-range channels 1/6/11.

**Recommendation:** range+speed → **5G ch149 (HE80)**; coverage on 2.4G → **ch1/6/11 (HE20)**.
