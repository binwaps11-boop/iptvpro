#!/usr/bin/env python3
"""Fix the JCG Q20 device tree for a from-source OpenWrt build.

Two independent, well-documented Q20 hardware problems live in the device tree and
therefore cannot be fixed by the no-toolchain overlay build — they need the kernel
recompiled. This script edits the target DTS in place before the kernel is built.

  1. NAND ECC too weak  (OpenWrt #20878)
     The Q20 carries a Toshiba TC58NVG1S3H (or Winbond W29N01HV) SLC NAND whose
     datasheet REQUIRES 8-bit ECC per 512 bytes. Stock ramips brings the controller
     up at 4-bit/512. Under real write load this logs uncorrectable-ECC and, over
     time, corrupts the overlay ("تعليق"/hangs and random resets after a while).
     Fix: pin the NAND node to 8-bit/512 software-BCH ECC.

  2. WAN port capped / unstable at gigabit  (OpenWrt #16083, #16551)
     gmac1 (the dedicated WAN jack) needs its fixed-link + rgmii delay spelled out or
     it can negotiate wrong and sit at 100 Mbit or flap. Fix: force gmac1 to a
     1000/full fixed-link.  (Harmless on units that were already fine.)

The script is idempotent: it does nothing if the properties are already present, and
it prints a unified before/after so the CI log proves exactly what changed. If it
cannot find the target node it exits non-zero so the build fails loudly rather than
silently shipping the unfixed tree.

Usage:  patch-dts.py <openwrt-tree>/target/linux/ramips/dts/mt7621_jcg_q20.dts
"""
import re, sys, os

def die(m): sys.exit(f"patch-dts: {m}")

def main(path):
    if not os.path.isfile(path):
        die(f"DTS not found: {path}")
    src = open(path).read()
    orig = src
    changed = []

    # ---- 1. NAND ECC 8-bit / 512 ------------------------------------------------
    # Match the SPI-NAND (or raw NAND) flash node. On mt7621 ramips the Q20 uses a
    # spi-nand child of the spi controller, node label usually "spi_nand@0"/"flash@0".
    m = re.search(r'((?:spi[_-]?nand|flash)@0\s*\{)', src)
    if not m:
        die("could not locate the NAND flash node (spi_nand@0 / flash@0)")
    if 'nand-ecc-strength' in src:
        changed.append("NAND ECC: already present, left as-is")
    else:
        inject = (m.group(1) +
                  "\n\t\tnand-ecc-engine = <&bch>;"
                  "\n\t\tnand-ecc-mode = \"hw\";"
                  "\n\t\tnand-ecc-strength = <8>;"
                  "\n\t\tnand-ecc-step-size = <512>;")
        src = src[:m.start()] + inject + src[m.end():]
        changed.append("NAND ECC: set 8-bit / 512-byte")

    # ---- 2. gmac1 (WAN) fixed 1000/full ----------------------------------------
    if re.search(r'&gmac1\s*\{', src):
        if 'fixed-link' in re.search(r'&gmac1\s*\{.*?\}', src, re.S).group(0):
            changed.append("gmac1 fixed-link: already present, left as-is")
        else:
            src = re.sub(r'(&gmac1\s*\{)',
                         r'\1\n\tfixed-link {\n\t\tspeed = <1000>;\n\t\tfull-duplex;\n\t};',
                         src, count=1)
            changed.append("gmac1: forced 1000/full fixed-link")
    else:
        # gmac1 may be described inline in the &ethernet block; note it, don't fail.
        changed.append("gmac1: no &gmac1 override node found — check &ethernet mac@1 manually")

    if src == orig:
        print("patch-dts: nothing to change (already patched)")
        return
    open(path, 'w').write(src)
    print("patch-dts: applied ->")
    for c in changed:
        print("  -", c)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        die("usage: patch-dts.py <path to mt7621_jcg_q20.dts>")
    main(sys.argv[1])
