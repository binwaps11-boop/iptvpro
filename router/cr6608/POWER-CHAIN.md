# CR6608 Wi-Fi Power Chain — What Each Layer Is and What This Firmware Does

Device: **Xiaomi CR6608** — SoC **MT7621** (ramips), radio **MT7915 AX1800 2×2 DBDC**,
driver **mt76 / mt7915e**, OpenWrt 24.10.6 (kernel 6.6.127). Prepared as a firmware
build (v85) for an academic demonstration of the complete transmit-power chain.

The **actual emitted power** at any instant is the **minimum** of every layer below.
Raising one layer only helps if it was the binding constraint.

| # | Layer (from the list) | What it is | What v85 does | Effect on real power |
|---|---|---|---|---|
| 1 | **country code** | Regulatory domain selector | `US` (patched regdb grants 36 dBm on all bands) | Not binding (≥ hardware) |
| 2 | **txpower** | Requested ceiling per radio | Pinned **35** on radio0/radio1 (request only) | Request, not a source of power |
| 3 | **wireless-regdb / regulatory.bin / db.txt** | The regulatory rule DB `cfg80211` enforces | `regulatory.db` patched in place: all 2.4/5G rules 36 dBm, **DFS/NO-IR cleared** | Removes reg clamp + unlocks channels |
| 4 | **cfg80211** | Kernel regulatory core | Receives the patched db; applies 36 dBm ceiling | Ceiling raised above hardware |
| 5 | **mac80211** | Kernel soft-MAC | Passes `iw set txpower fixed 3500` to driver | Passthrough |
| 6 | **hostapd** | AP daemon | `country_code`, `antenna_gain 0`, no extra cap | No EIRP subtraction |
| 7 | **mt76 / mt7915e** | The radio driver | **Vendor-patched**: module param `cr6608_rf_30dbm_test` **enabled** (see below) | **Lifts the SKU clamp — the real lever** |
| 8 | **EEPROM / calibration data** | Per-chip factory power/PA calibration in the `Factory` MTD (`/dev/mtd2`) | Optional guarded on-demand tool raises the **rate-delta** bytes +6 dB | Raises driver target up to the lifted ceiling |
| 9 | **target power table** | Per-band/per-chain base target in EEPROM (`MT_EE_TX0_POWER_2G/5G`) | Read/displayed; optionally bumped by the EEPROM tool | Bounded by PA |
| 10 | **rate power table** | Per-rate delta in EEPROM (`MT_EE_RATE_DELTA_2G@0x252 / 5G@0x29D`) | The two bytes the EEPROM tool patches (+6 dB, `0xCC`) | Reaches the SKU ceiling |
| 11 | **antenna gain** | dBi subtracted from EIRP headroom | `antenna_gain 0` — nothing subtracted | Max EIRP headroom |

### Layers that are hardware or not present on this chip (documented, not editable)
- **PA / Power Amplifier, FEM** — the physical amplifier/front-end. The true ceiling
  (~20 dBm conducted per chain). Firmware cannot exceed it; pushing past factory
  calibration only saturates it (distortion, EVM loss, heat).
- **ART partition / boarddata / board-2.bin / ath9k / ath10k** — these belong to
  **Qualcomm/Atheros** radios. This board is MediaTek MT7915 — **they do not exist here**.
- **DTS / Device Tree** — compiled into the kernel image (kept byte-identical), so the
  EEPROM is read from the `Factory` nvmem cell; not editable from the rootfs.
- **cable loss** — an external RF-plumbing quantity (coax between radio and antenna);
  no firmware control point.

## The decisive lever: the driver's `cr6608_rf_30dbm_test` override
The shipped `mt7915e.ko` is custom-built with a bool parameter
`cr6608_rf_30dbm_test`, gated on `of_machine_is_compatible("xiaomi,mi-router-cr6608")`,
with the banner **"CR6608-RF-30DBM-LINEAR max=30, data caps=26/24 dBm, Factory delta
preserved"**. Stock, the driver clamps 5 GHz output well below the PA ceiling via the
SKU (per-rate) power table. Enabling this parameter **rewrites the SKU limit** so the
radio runs toward its ~30 dBm linear cap (data-rate rows capped 26/24 dBm).

v85 enables it **permanently and safely** via `/etc/modprobe.d/mt7915e.conf`:
```
options mt7915e cr6608_rf_30dbm_test=1
```
This is a **driver runtime override — it writes no flash and cannot brick calibration**,
and is reversible by deleting the file. Verify on the device:
```
cat /sys/module/mt7915e/parameters/cr6608_rf_30dbm_test   # -> 1
dmesg | grep 30DBM                                         # -> CR6608-RF-30DBM-LINEAR banner
```

## The EEPROM experiment (on-demand, guarded — for the demonstration)
Tool: `/usr/sbin/cr6608-eeprom-power` (also via dashboard actions
`eeprom_backup` / `eeprom_boost` / `eeprom_restore` / `eeprom_status`). It is **not**
run at boot — you trigger it deliberately. It:
1. Backs up the whole `Factory` partition first (to `/overlay` and downloadable at
   `http://<router>/factory.orig`); refuses to proceed if the backup fails or the
   chip-id magic `0x7915` is wrong.
2. Changes **only two bytes** — the 2.4G/5G rate-delta cells `0x252`/`0x29D` — to `0xCC`
   (enable + sign + magnitude 12 = **+6.0 dB**), byte-identical everywhere else
   (`NDIFF ≤ 8` enforced).
3. Writes the full partition, verifies the readback, `wifi reload`, then requires **both
   phy0 and phy1** to return within 40 s — otherwise it **auto-restores** the backup.
4. An in-flight flag makes a mid-write reboot restore once (never a crash loop).

**Honest result for the report:** emitted power = `min(eeprom_target+delta, SKU, PA)`.
The SKU lift (layer 7) is what actually moves the needle; the EEPROM delta lets the
target reach that lifted ceiling. Realistic outcome is **~27–30 dBm on robust rates,
~24–26 dBm on dense-QAM data rates** — the **35 dBm request is not physically
reachable** on this 2×2 PA. Beyond factory calibration the amplifier compresses:
higher-order MCS fall back, throughput can *drop* while a CW tone reads higher, and
spectral regrowth/thermal rise. This is a **bench/demonstration** configuration; raising
EIRP beyond the local regulatory limit is not legal for deployment.
