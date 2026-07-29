# ESM-48150B1 EEPROM Analysis

Reverse-engineering toolkit for **Huawei ESM / LiFePO4 battery BMS EEPROM
dumps** (256 Kbit / 32 KB, e.g. a 24C256 running at 1.8 V). It scans a `.bin`
dump — or a whole folder of them — classifies each chip, and renders a
dashboard.

The scanner is **read-only**: it classifies and catalogs dumps you already
have. It does not write to, patch, or modify any chip image.

## Usage

```bash
# one chip
python3 analyze.py bin/ESM48150B1_V114_full_patched.bin data/

# a whole folder (writes one .json per chip + _index.json)
python3 analyze.py bin/ data/

# rebuild the dashboard after re-scanning
python3 build_dashboard.py        # injects data/_index.json into dashboard.html
```

Open `dashboard.html` in a browser. It is fully self-contained (data embedded,
no network needed).

## Layout

```
analyze.py          scanner  -> JSON per chip
build_dashboard.py  injects data/_index.json into the dashboard template
dashboard.html      self-contained dashboard (data embedded)
bin/                raw .bin dumps
data/               generated JSON (one per chip + _index.json)
```

## What the scanner reports

| Field | Meaning |
|-------|---------|
| **BMS magic** | `0x55AACCDD` (`dd cc aa 55` LE). Marks each BMS config record. Multiple instances = primary + mirror copies for redundancy. |
| **FW constants** | Firmware fingerprint dwords shared across the ESM family. Their presence and offsets identify the firmware generation. |
| **Discriminators** | The two dwords at `0x0344` / `0x0362` that separate **V114** from **V117** (the two are otherwise byte-for-byte identical). Plus the HW-variant ASCII tag (e.g. `TBEW`). |
| **Fabrication** | Unix timestamp at `0x01AC`, decoded to a date. Matches the e-Label `Manufactured` field. |
| **e-Labels** | Huawei `ArchivesInfo` blocks (byte-swapped ASCII) at `0x3000` / `0x3400` — board type, barcode, item code, description, vendor. |
| **Zones** | Non-`0xFF` data regions. The main config zone (`< 0x3000`) holds BMS parameters; the `0x3000+` zones hold e-Labels and calibration. |
| **Alarm signature** | `88 88 88 88` runs. Hits **inside the main config zone** flag a live anti-theft / alarm record. |
| **Serials** | Direct-ASCII serial near `0x00AE` and the byte-swapped pack barcode near `0x3840`. |

## State classification

The `state` field is a **catalog label** the scanner assigns from the alarm
heuristic — it describes what the dump contains, for inventory purposes:

| Code | Label | Trigger |
|------|-------|---------|
| `sana` | Sana (clean) | no alarm signature in the main config zone |
| `alarma_anti_theft` | Solo alarma Anti-theft | `88 88 88 88` present in the main zone |
| `bloqueo_salida` | Bloqueo de salida + Anti-theft | output-lock + anti-theft indicators |
| `desconocido` | Desconocido | no BMS magic found (not a recognized ESM dump) |

## V114 vs V117

Both firmware revisions produce **structurally identical** dumps: same magic
layout, same zone map, same e-Label format, same 32 KB size. They differ only
in the two discriminator constants at `0x0344` and `0x0362`. You cannot tell
them apart from the e-Label text alone — you must read those two offsets (the
scanner reports them under `discriminators`).

## Notes on the format

- The whole image is ~90 % `0xFF` (erased flash); real data sits in ~17 sparse
  zones.
- Numeric fields (magic, constants, timestamps) are little-endian.
- e-Label **text** is stored with a 16-bit word byte-swap; the scanner
  un-swaps it (`deswap()`) before parsing.
- The primary BMS block (`0x0080`) and its mirror (`0x0480`) are identical.
