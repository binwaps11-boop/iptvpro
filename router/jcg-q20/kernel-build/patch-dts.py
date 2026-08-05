#!/usr/bin/env python3
"""Optional NAND-ECC device-tree tweak for the JCG Q20 (OpenWrt #20878).

BACKGROUND
----------
The Q20's SLC NAND (Toshiba TC58NVG1S3H / Winbond W29N01HV, 2 KiB page, 64-byte OOB)
is specified for 8-bit ECC per 512 bytes. Stock ramips brings the mt7621 NAND up at
4-bit/512. Reports of "hang / random reset after a while" (#20878) trace to
uncorrectable-ECC events accumulating under write load.

The generic NAND DT bindings the kernel core reads are exactly two properties:

    nand-ecc-strength = <8>;
    nand-ecc-step-size = <512>;

placed inside the board's `&nand { ... }` override. 8-bit BCH per 512 needs 13 ECC
bytes/512 -> 52 bytes for a 2 KiB page, which fits the 64-byte OOB, so it is the
right value for this chip.

WHY THIS IS OPT-IN
------------------
Whether the mt7621 on-host ECC engine + OOB layout accept strength 8 at runtime cannot
be proven without flashing real hardware. If the controller rejected it the NAND would
fail to attach and the unit would not boot. So the from-source workflow keeps this OFF
by default (a guaranteed-bootable image) and only calls this script when the operator
explicitly opts in. Only then is the two-property tweak applied.

This script deliberately does **nothing else** — it does NOT touch gmac1 (the Q20 WAN
uses a real gigabit PHY via `phy-handle = <&ethphy0>`, so the #16083 fixed-link change
does not apply to this board and would break WAN), and it never invents phandles.

It is idempotent and, by design, NON-FATAL: if it cannot find `&nand {` it prints a
warning and leaves the tree untouched so the build still succeeds with stock ECC.

Usage:  patch-dts.py <openwrt-tree>/target/linux/ramips/dts/mt7621_jcg_q20.dts
"""
import re, sys, os

def main(path):
    if not os.path.isfile(path):
        print(f"patch-dts: WARNING DTS not found ({path}); leaving stock ECC")
        return
    src = open(path).read()

    if 'nand-ecc-strength' in src:
        print("patch-dts: nand-ecc-strength already present — nothing to do")
        return

    m = re.search(r'&nand\s*\{', src)
    if not m:
        print("patch-dts: WARNING &nand node not found; leaving stock ECC (build continues)")
        return

    inject = (m.group(0) +
              "\n\t/* #20878: Toshiba/Winbond SLC NAND wants 8-bit/512 ECC */"
              "\n\tnand-ecc-strength = <8>;"
              "\n\tnand-ecc-step-size = <512>;")
    src = src[:m.start()] + inject + src[m.end():]
    open(path, 'w').write(src)
    print("patch-dts: applied NAND ECC 8-bit / 512-byte to &nand")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit("usage: patch-dts.py <path to mt7621_jcg_q20.dts>")
    main(sys.argv[1])
