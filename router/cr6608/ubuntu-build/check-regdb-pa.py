#!/usr/bin/env python3
# CI gate: assert the built regulatory.db grants PA >= 38.0 dBm (max_eirp 3800 mBm)
# on the 2.4G rule. Exits 0 on pass, 1 on fail. Usage: check-regdb-pa.py <regulatory.db>
import struct, sys

d = open(sys.argv[1], "rb").read()
off = 8
while True:
    a = d[off:off + 2]
    p = struct.unpack_from(">H", d, off + 2)[0]
    if a == b"\x00\x00" and p == 0:
        print("::error::PA not present in regulatory.db")
        sys.exit(1)
    if a == b"PA":
        c = p * 4
        q = c + 3 + (c + 3) % 2
        r = struct.unpack_from(">H", d, q)[0] * 4
        e = struct.unpack_from(">H", d, r + 2)[0]
        print("PA 2.4G max_eirp mBm =", e)
        sys.exit(0 if e >= 3800 else 1)
    off += 4
