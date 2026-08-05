#!/usr/bin/env python3
"""Make mt7915e.ko report 38.0 dBm as the EEPROM target power.

WHY THIS EXISTS
---------------
The 26 dBm this board applies does not come from the regulatory database (that
now says 38.00 dBm) and it does not come from the UCI txpower setting (38 on
both radios). It comes from the EEPROM, through this call chain:

    __mt7915_init_txpower()
        target_power = max over chains of mt7915_eeprom_get_target_power(...)
        target_power += mt7915_eeprom_get_power_delta(...)
        target_power  = mt76_get_rate_power_limits(...)      # device-tree based
        target_power += mt76_tx_power_nss_delta(n_chains)
        target_power  = DIV_ROUND_UP(target_power, 2)
        chan->max_power = min(chan->max_reg_power, target_power)

`chan->max_power` is what mac80211 clamps the configured TX power to, and it is
the number iwinfo and LuCI display. With the EEPROM giving roughly 26 dBm, that
min() lands on 26 no matter how high the regulatory ceiling is.

WHAT THIS DOES
--------------
Replaces the first two instructions of mt7915_eeprom_get_target_power() with an
immediate return of 76, which is 38.0 dBm in the half-dBm units this function
uses:

    jr    $ra                 0x03E00008
    addiu $v0, $zero, 76      0x2402004C   (branch delay slot)

Eight bytes. No relocation lives inside them (the script checks), the file size
does not change, and every other structure in the ELF is untouched. The rest of
the function simply becomes unreachable.

The result is `chan->max_power = min(38 from the regulatory database, 47) = 38`.

WHAT IT DOES NOT DO
-------------------
It does not write the Factory/EEPROM flash partition - it edits the kernel
module in the firmware image, and the per-device RF calibration on the device is
never touched. It also does not change what the power amplifier can physically
emit; it removes the last software clamp so the whole stack asks for 38 dBm.

RECOVERY
--------
If a patched module misbehaves, flash any earlier image over the LAN cable. The
bootloader and the Factory partition are not involved.

TUNING
------
38 dBm is not automatically the best setting. The amplifier saturates near 26 dBm and
compresses past it, and a compressed transmitter has worse EVM, so the high MCS rates
stop decoding and throughput can fall even though the number on screen went up. Sweep it
and keep whichever value actually measures best at a fixed client position:

    ko_eeprom38.py mt7915e.ko --dbm 26     # the amplifier's linear limit
    ko_eeprom38.py mt7915e.ko --dbm 30
    ko_eeprom38.py mt7915e.ko --dbm 38     # default

The patch is idempotent per value - re-running with a different --dbm overwrites the
previous one, because it always rewrites the same two instructions.

USAGE
-----
    ko_eeprom38.py /path/to/mt7915e.ko              # patch in place at 38 dBm
    ko_eeprom38.py /path/to/mt7915e.ko --dbm 30     # patch in place at 30 dBm
    ko_eeprom38.py /path/to/mt7915e.ko --check      # report only
"""
import struct, sys

SYMBOL = 'mt7915_eeprom_get_target_power'


def build_patch(dbm):
    """jr $ra + addiu $v0,$zero,<dbm*2> in the delay slot. The function returns s8
    half-dBm, so the immediate must fit in a signed byte."""
    half = int(round(dbm * 2))
    if not 0 < half < 128:
        sys.exit(f'--dbm {dbm} is out of range (the s8 half-dBm return caps at 63.5 dBm)')
    return struct.pack('<II', 0x03E00008, 0x24020000 | half), half


def sections(d):
    u32 = lambda o: struct.unpack('<I', d[o:o + 4])[0]
    u16 = lambda o: struct.unpack('<H', d[o:o + 2])[0]
    shoff, es, n, si = u32(0x20), u16(0x2e), u16(0x30), u16(0x32)
    raw = [dict(name=u32(shoff + i * es), off=u32(shoff + i * es + 16),
                size=u32(shoff + i * es + 20), idx=i) for i in range(n)]
    stroff = raw[si]['off']
    def nm(o):
        return d[stroff + o:d.index(b'\0', stroff + o)].decode()
    return {nm(s['name']): s for s in raw}


def main(path, check_only=False, dbm=38.0):
    PATCH, half = build_patch(dbm)
    d = bytearray(open(path, 'rb').read())
    if d[:4] != b'\x7fELF' or d[4] != 1:
        sys.exit('not a 32-bit ELF')
    secs = sections(d)
    text, sym, strt = secs['.text'], secs['.symtab'], secs['.strtab']
    u32 = lambda o: struct.unpack('<I', d[o:o + 4])[0]

    addr = size = None
    located_by = 'symbol'
    for i in range(sym['size'] // 16):
        o = sym['off'] + 16 * i
        nm_off = u32(o)
        name = d[strt['off'] + nm_off:d.index(b'\0', strt['off'] + nm_off)].decode()
        if name == SYMBOL:
            addr, size = u32(o + 4), u32(o + 8)
            break
    if addr is None:
        # Stock OpenWrt strips module symbols (functions become _0.._N), so the name is
        # gone. Fall back to the function's unique MIPS prologue signature:
        #   addiu $sp,$sp,-0x28   (d8 ff bd 27)   frame setup
        #   sltiu $v0,$a2,4       (04 00 c2 2c)   chain-index (arg3) bound check < 4
        # This pair is unique to mt7915_eeprom_get_target_power in the mt7915e module.
        SIG = bytes.fromhex('d8ffbd270400c22c')
        base, tsize = text['off'], text['size']
        hits = []
        p = base
        while True:
            j = d.find(SIG, p, base + tsize)
            if j < 0:
                break
            hits.append(j - base)
            p = j + 1
        if len(hits) != 1:
            # After patching, the prologue signature is gone (replaced by jr $ra + addiu).
            # If the exact patched word pair already sits at a unique .text site, this module
            # is already done - report that instead of failing.
            done = []
            q = base
            while True:
                j = d.find(PATCH, q, base + tsize)
                if j < 0:
                    break
                done.append(j - base)
                q = j + 1
            if len(done) == 1:
                print(f'  {SYMBOL} already patched at {half / 2:.1f} dBm '
                      f'(file offset {base + done[0]:#x}) - nothing to do')
                return
            sys.exit(f'{SYMBOL} not found by name, and the prologue signature matched '
                     f'{len(hits)} sites (need exactly 1) - refusing to guess')
        addr, size, located_by = hits[0], 0, 'signature'

    rel = secs.get('.rel.text')
    clash = [r for r in range(rel['size'] // 8)
             if addr <= u32(rel['off'] + 8 * r) < addr + len(PATCH)] if rel else []
    if clash:
        sys.exit(f'refusing to patch: {len(clash)} relocation(s) inside the patch site')

    off = text['off'] + addr
    before = bytes(d[off:off + len(PATCH)])
    print(f'  {SYMBOL} @ {addr:#x} size {size:#x}, file offset {off:#x}  (located by {located_by})')
    print(f'  relocations inside the patch site: 0')
    print(f'  before: {before.hex()}')
    print(f'  after : {PATCH.hex()}   (jr $ra / addiu $v0,$zero,{half})  = {half / 2:.1f} dBm')
    if before == PATCH:
        print(f'  already patched at {half / 2:.1f} dBm - nothing to do')
        return
    if check_only:
        print('  --check: not written')
        return
    d[off:off + len(PATCH)] = PATCH
    open(path, 'wb').write(d)
    print(f'  patched (size unchanged: {len(d)} bytes)')


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        sys.exit(__doc__)
    target = 38.0
    if '--dbm' in sys.argv:
        i = sys.argv.index('--dbm')
        if i + 1 >= len(sys.argv):
            sys.exit('--dbm needs a value, e.g. --dbm 30')
        target = float(sys.argv[i + 1])
        args = [a for a in args if a != sys.argv[i + 1]]
    main(args[0], '--check' in sys.argv, target)
