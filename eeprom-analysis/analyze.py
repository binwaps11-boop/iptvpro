#!/usr/bin/env python3
"""
ESM-48150B1 EEPROM analyzer.

Reverse-engineering scanner for Huawei ESM / LiFePO4 battery BMS EEPROM
dumps (256 Kbit / 32 KB, e.g. 24C256). Reads a single .bin or a whole
folder and emits one JSON record per chip describing:

  - the redundant BMS_MAGIC instances (0x55AACCDD)
  - firmware fingerprint constants and version discriminators
  - the fabrication timestamp
  - the Huawei e-Label archive blocks (byte-swapped ASCII)
  - detected data zones (primary + mirror)
  - an anti-theft / alarm signature heuristic

The scanner is read-only. It never writes back to any chip image; it only
classifies and catalogs dumps you already possess.
"""
import sys, os, json, struct, datetime, glob

MAGIC = 0x55AACCDD  # dd cc aa 55, little-endian

# Known firmware fingerprint constants seen across the ESM family.
# value -> (label, first-seen date)
FW_CONSTANTS = {
    1437256925: ("BMS_MAGIC universal", "2015-07-18"),
    1718157313: ("FW fingerprint V115/V124/V130", "2024-06-12"),
    1497759799: ("FW const", "2017-06-18"),
    1690042368: ("FW const", "2023-07-22"),
}


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def deswap(b):
    """Undo 16-bit word byte-swap used for Huawei e-Label ASCII."""
    out = bytearray(len(b))
    for i in range(0, len(b) - 1, 2):
        out[i] = b[i + 1]
        out[i + 1] = b[i]
    if len(b) % 2:
        out[-1] = b[-1]
    return bytes(out)


def find_all(d, pat):
    out, i = [], 0
    while True:
        j = d.find(pat, i)
        if j < 0:
            break
        out.append(j)
        i = j + 1
    return out


def data_regions(d, gap=16):
    """Return (start, end) of non-0xFF runs, merging gaps <= `gap`."""
    regions, start, run = [], None, 0
    for i, b in enumerate(d):
        if b != 0xFF:
            if start is None:
                start = i
            run = 0
        elif start is not None:
            run += 1
            if run > gap:
                regions.append((start, i - run + 1))
                start = None
    if start is not None:
        regions.append((start, len(d)))
    return regions


def parse_elabel(block):
    """Deswap + parse a Huawei ArchivesInfo e-Label block into key/values."""
    txt = deswap(block).decode("latin1")
    txt = txt.replace("\x00", "\n").replace("\xff", "")
    props = {}
    for line in txt.split("\n"):
        line = line.strip()
        if "=" in line and not line.startswith("/$["):
            k, _, v = line.partition("=")
            k = k.lstrip("/$").strip()
            if k and k not in props:
                props[k] = v.strip()
    return props


def find_elabels(d):
    """Locate ArchivesInfo blocks by their deswapped signature."""
    labels = []
    for (s, e) in data_regions(d):
        seg = deswap(d[s:e])
        if b"ArchivesInfo" in seg or b"BoardType" in seg:
            props = parse_elabel(d[s:e])
            if props:
                labels.append({"offset": f"0x{s:04X}", "properties": props})
    return labels


def ts(v):
    try:
        return datetime.datetime.utcfromtimestamp(v).strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return None


def analyze(path):
    d = open(path, "rb").read()
    size = len(d)
    r = {
        "file": os.path.basename(path),
        "size": size,
        "size_kbit": size * 8 // 1024,
        "ff_ratio": round(d.count(0xFF) / size, 4) if size else 0,
    }

    # --- BMS_MAGIC instances -------------------------------------------
    magics = [o for o in range(0, size - 3) if u32(d, o) == MAGIC]
    r["magic"] = {
        "value": MAGIC,
        "hex": f"0x{MAGIC:08X}",
        "instances": [f"0x{o:04X}" for o in magics],
        "count": len(magics),
    }
    has_magic = len(magics) > 0

    # --- firmware constants --------------------------------------------
    consts = []
    seen = set()
    for o in range(0, size - 3, 2):
        v = u32(d, o)
        if v in FW_CONSTANTS and v not in seen:
            seen.add(v)
            label, date = FW_CONSTANTS[v]
            offs = [f"0x{p:04X}" for p in range(0, size - 3, 2) if u32(d, p) == v][:8]
            consts.append({"value": v, "label": label, "date": date, "offsets": offs})
    r["fw_constants"] = consts

    # --- version discriminators (V114/V117) ----------------------------
    r["discriminators"] = {
        "const_0x0344": f"0x{u32(d, 0x0344):08X}" if size > 0x348 else None,
        "const_0x0362": f"0x{u32(d, 0x0362):08X}" if size > 0x366 else None,
        "hw_variant": _hw_variant(d),
    }

    # --- fabrication timestamp -----------------------------------------
    fab = u32(d, 0x01AC) if size > 0x1B0 else 0
    r["fabrication"] = {"offset": "0x01AC", "raw": fab, "utc": ts(fab)}

    # --- e-Labels ------------------------------------------------------
    r["elabels"] = find_elabels(d)

    # --- zones ---------------------------------------------------------
    zones = data_regions(d)
    r["zones"] = {
        "count": len(zones),
        "list": [{"start": f"0x{s:04X}", "end": f"0x{e:04X}", "len": e - s} for s, e in zones],
        "main_zone_end": f"0x{zones[2][1]:04X}" if len(zones) > 2 else None,
    }

    # --- anti-theft / alarm signature ----------------------------------
    alarm_sig = find_all(d, b"\x88\x88\x88\x88")
    r["alarm"] = {
        "signature": "88 88 88 88",
        "hits": [f"0x{o:04X}" for o in alarm_sig],
        # signatures inside the main config zone (< main_zone_end) flag a
        # live anti-theft / alarm record, not just e-label filler.
        "in_main_zone": [f"0x{o:04X}" for o in alarm_sig if o < 0x03A0],
    }

    # --- state classification (catalog label) --------------------------
    r["state"] = classify(r)

    # --- serials -------------------------------------------------------
    r["serials"] = extract_serials(d)
    return r


def _hw_variant(d):
    # HW variant tag lives near the serial (e.g. "...TBEWL..."). Pull the
    # 4-char uppercase run following the serial marker if present.
    import re
    for m in re.finditer(rb"[0-9A-Z]{8,}", d[:0x400]):
        s = m.group().decode()
        if "TBEW" in s:
            return "TBEW"
    return None


def extract_serials(d):
    import re
    out = []
    # direct ASCII serials
    for m in re.finditer(rb"[0-9A-Z]{10,}", d[:0x400]):
        out.append({"offset": f"0x{m.start():04X}", "value": m.group().decode()})
    # deswapped barcodes in the e-label area
    for (s, e) in data_regions(d):
        if s < 0x3800:
            continue
        seg = deswap(d[s:e]).decode("latin1")
        for m in re.finditer(r"[0-9A-Z]{10,}", seg):
            out.append({"offset": f"0x{s:04X}(swap)", "value": m.group()})
    return out


def classify(r):
    """
    Assign a catalog state label:
      sana                 - clean, no alarm signature in the main zone
      alarma_anti_theft    - anti-theft alarm signature present in main zone
      bloqueo_salida       - output-lock + anti-theft (both indicators)
    """
    in_main = r["alarm"]["in_main_zone"]
    if not r["magic"]["count"]:
        return {"code": "desconocido", "label": "Desconocido (sin BMS magic)"}
    if in_main:
        return {"code": "alarma_anti_theft", "label": "Solo alarma Anti-theft",
                "reason": f"firma 88 88 88 88 en zona main @ {', '.join(in_main)}"}
    return {"code": "sana", "label": "Sana", "reason": "sin firma de alarma en zona main"}


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: analyze.py <file.bin | folder> [out_dir]")
        sys.exit(1)
    target = args[0]
    out_dir = args[1] if len(args) > 1 else "data"
    os.makedirs(out_dir, exist_ok=True)

    files = []
    if os.path.isdir(target):
        files = sorted(glob.glob(os.path.join(target, "*.bin")))
    else:
        files = [target]

    results = []
    for f in files:
        rec = analyze(f)
        results.append(rec)
        name = os.path.splitext(os.path.basename(f))[0] + ".json"
        with open(os.path.join(out_dir, name), "w") as fh:
            json.dump(rec, fh, indent=2, ensure_ascii=False)
        st = rec["state"]["label"]
        print(f"[{st:24}] {rec['file']}")

    # index of everything
    with open(os.path.join(out_dir, "_index.json"), "w") as fh:
        json.dump(results, fh, indent=2, ensure_ascii=False)
    print(f"\n{len(results)} chip(s) -> {out_dir}/")


if __name__ == "__main__":
    main()
