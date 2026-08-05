#!/bin/bash
# Rebuild the SmartAP Q20 firmware from a STOCK OpenWrt JCG Q20 sysupgrade image.
# No cross-compiler needed - this overlays files and binary-patches the shipped driver.
#   ./build-q20.sh openwrt-25.12.5-ramips-mt7621-jcg_q20-squashfs-sysupgrade.bin
set -e
STOCK="${1:?usage: build-q20.sh <stock jcg_q20 sysupgrade.bin>}"
OUT="jcg-q20-SmartAP-38dBm-sysupgrade.bin"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

echo "[1/6] extract stock image"
tar -xf "$STOCK" -C "$work"
D="$work/sysupgrade-jcg_q20"
unsquashfs -d "$work/rootfs" -q "$D/root" >/dev/null

echo "[2/6] overlay the SmartAP customisation"
cp -a files/. "$work/rootfs/"
# bootstrap-dark/light must stay symlinks -> bootstrap (login redirect + templates)
for t in bootstrap-dark bootstrap-light; do
  d="$work/rootfs/usr/share/ucode/luci/template/themes/$t"
  [ -L "$d" ] || { rm -rf "$d"; ln -s bootstrap "$d"; }
done

echo "[3/6] 38 dBm: binary-patch the driver + raise the regulatory database"
python3 tools/ko_eeprom38.py "$work/rootfs/lib/modules/6.12.94/mt7915e.ko"
python3 tools/regdb38.py      "$work/rootfs/lib/firmware/regulatory.db"

echo "[4/6] repack rootfs (keep /dev/console, xz, 256K blocks, 4096 pad)"
mksquashfs "$work/rootfs" "$work/root.new" -comp xz -b 262144 -noappend -no-xattrs -root-owned -nopad
python3 - "$work" <<'PY'
import sys,os
w=sys.argv[1]; r=open(w+'/root.new','rb').read()
open(w+'/sysupgrade-jcg_q20/root','wb').write(r+b'\0'*((-len(r))%4096))
PY

echo "[5/6] tar (CONTROL/kernel/root) - kernel kept byte-identical"
( cd "$work" && tar --format=gnu --owner=0 --group=0 --numeric-owner --mtime='@1785000000' \
    -cf payload.tar --no-recursion sysupgrade-jcg_q20 \
    sysupgrade-jcg_q20/CONTROL sysupgrade-jcg_q20/kernel sysupgrade-jcg_q20/root )

echo "[6/6] append fwtool trailer (reuse stock metadata, recompute CRC)"
python3 - "$STOCK" "$work/payload.tar" "$OUT" <<'PY'
import sys,struct,zlib
stock,tar,out=sys.argv[1:4]
v=open(stock,'rb').read(); h=v.rfind(b'FWx0')
meta=v[h-struct.unpack('>I',v[h+12:h+16])[0]+16:h]
body=open(tar,'rb').read()+meta
crc=(~zlib.crc32(body))&0xffffffff
open(out,'wb').write(body+b'FWx0'+struct.pack('>I',crc)+bytes([1,0,0,0])+struct.pack('>I',len(meta)+16))
print('  wrote',out,len(body)+16,'bytes')
PY
echo "done -> $OUT"
