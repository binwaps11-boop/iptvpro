#!/usr/bin/env python3
"""Raise the Wi-Fi EIRP ceilings in a kernel regulatory.db to 38.00 dBm.

The rule pool is shared between countries, so rewriting a rule's max_eirp lifts
the ceiling for every country that references it. Only max_eirp is touched: it
is a fixed-width __be16 inside struct fwdb_rule, so the file keeps its exact
size and every pointer in the database stays valid. Flags are left alone on
purpose - DFS radar detection stays enabled.

Layout (net/wireless/reg.c):
  header      __be32 magic 'RGDB', __be32 version
  country     u8 alpha2[2], __be16 coll_ptr        (ptr in dwords)
  collection  u8 len, u8 n_rules, u8 dfs_region; __be16 rule_ptrs[] at +ALIGN(len,2)
  rule        u8 len, u8 flags, __be16 max_eirp, __be32 start, end, max_bw
"""
import struct, sys

TARGET_CDBM = 3800                                  # 38.00 dBm
BANDS = [(2400_000, 2500_000), (5150_000, 5900_000)]  # kHz: 2.4 GHz + all of 5 GHz

def main(path):
    d = bytearray(open(path, 'rb').read())
    assert d[:4] == b'RGDB', 'not a regulatory.db'
    assert struct.unpack('>I', d[4:8])[0] == 20, 'unexpected regdb version'

    # walk the country table, collecting every rule pointer that is reachable
    rules, countries, off, prev = set(), 0, 8, b''
    while off + 4 <= len(d):
        a2 = d[off:off+2]
        cp, = struct.unpack('>H', d[off+2:off+4])
        if cp == 0 or bytes(a2) < prev or not bytes(a2).isalnum():
            break
        co = cp << 2
        n = d[co+1]
        ro = co + ((d[co] + 1) & ~1)                # ALIGN(len, 2)
        for i in range(n):
            rules.add(struct.unpack('>H', d[ro+2*i:ro+2*i+2])[0])
        countries += 1
        prev = bytes(a2)
        off += 4

    raised = skipped = 0
    for rp in sorted(rules):
        o = rp << 2
        start, end = struct.unpack('>II', d[o+4:o+12])
        if not any(start < hi and end > lo for lo, hi in BANDS):
            skipped += 1
            continue
        old, = struct.unpack('>H', d[o+2:o+4])
        if old >= TARGET_CDBM:
            skipped += 1
            continue
        d[o+2:o+4] = struct.pack('>H', TARGET_CDBM)
        raised += 1

    open(path, 'wb').write(d)
    print(f"  countries={countries}  wifi rules raised={raised}  left alone={skipped}")

if __name__ == '__main__':
    main(sys.argv[1])
