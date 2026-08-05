#!/usr/bin/env python3
"""Patch the mt76 driver source so mt7915_eeprom_get_target_power() returns 38.0 dBm.

This is the from-source equivalent of tools/ko_eeprom38.py (which binary-patches the
shipped .ko). When you build the whole image from source on GitHub Actions the symbols
are intact, so we edit the C directly. The function returns s8 half-dBm units, so 38.0
dBm is 76.

We insert, as the first statement of the function body, an early return of 76 guarded by
a unique marker string. The marker is a no-op that also lands in the compiled module's
string table, so the CI job can grep the finished mt7915e.ko and PROVE the 38 build
actually shipped (exactly how the CR6608 workflow gates its artifact).

Idempotent: re-running detects the marker and does nothing.

Usage:  apply-mt76-38.py <mt76 source dir>      (the build_dir/.../mt76-* directory)
"""
import re, sys, os

MARKER = "SMARTAP-Q20-RF-38DBM-LINEAR"

def die(m): sys.exit(f"apply-mt76-38: {m}")

def main(mt76dir):
    eeprom = os.path.join(mt76dir, "mt7915", "eeprom.c")
    if not os.path.isfile(eeprom):
        die(f"not found: {eeprom}")
    src = open(eeprom).read()
    if MARKER in src:
        print("apply-mt76-38: marker already present — nothing to do")
        return

    # Find the function definition and the opening brace of its body.
    m = re.search(r'mt7915_eeprom_get_target_power\s*\([^)]*\)\s*\{', src)
    if not m:
        die("could not find mt7915_eeprom_get_target_power() definition")
    ins = m.end()
    early = ('\n\t/* ' + MARKER + ': force EEPROM target to 38.0 dBm (76 half-dBm).'
             '\n\t * Removes the last software clamp so the whole TX-power stack asks'
             '\n\t * for 38 dBm; regulatory.db + UCI txpower do the rest. */'
             '\n\t{ static const char smartap_q20_rf[] = "' + MARKER + '"; (void)smartap_q20_rf; }'
             '\n\treturn 76;\n')
    src = src[:ins] + early + src[ins:]
    open(eeprom, 'w').write(src)
    print(f"apply-mt76-38: patched {eeprom}")
    print("  inserted early 'return 76;' (=38.0 dBm) with proof marker", MARKER)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        die("usage: apply-mt76-38.py <mt76 source dir>")
    main(sys.argv[1])
