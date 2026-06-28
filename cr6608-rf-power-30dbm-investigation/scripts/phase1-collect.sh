#!/bin/sh
# phase1-collect.sh  —  READ-ONLY RF/EEPROM data collection for Xiaomi CR6608 (MT7915)
# Run ON THE ROUTER (OpenWrt 24.10). Nothing here writes, flashes, or changes config.
# Usage:  sh phase1-collect.sh  > /tmp/phase1.txt 2>&1   ; then copy /tmp/phase1.txt off the device.
#
# SAFETY: every command below is a read. No `mtd write`, no `uci commit`, no `iw set`.

set -u
sep(){ echo; echo "######## $* ########"; }

sep "0. IDENTITY / VERSION"
cat /etc/openwrt_release 2>/dev/null
cat /proc/version 2>/dev/null
cat /tmp/sysinfo/model 2>/dev/null
cat /tmp/sysinfo/board_name 2>/dev/null

sep "1. MTD PARTITIONS (find Factory/caldata)"
cat /proc/mtd

sep "2. DTS nvmem / caldata mapping (where the driver reads cal from)"
# Shows which partition + offset mt76 pulls EEPROM from, and any mac/precal nodes.
find /sys/firmware/devicetree/base -iname '*cal*'    2>/dev/null
find /sys/firmware/devicetree/base -iname '*eeprom*' 2>/dev/null
find /sys/firmware/devicetree/base -iname '*factory*' 2>/dev/null
# Dump nvmem cells if present
ls -l /sys/bus/nvmem/devices/ 2>/dev/null
for f in /sys/bus/mtd/devices/*/of_node/reg ; do echo "-- $f"; hexdump -C "$f" 2>/dev/null; done

sep "3. DMESG — cal/eeprom/power/chain/thermal"
dmesg | grep -Ei "factory|eeprom|cal|mt76|mt7915|mt7975|nvmem|power|txpower|chain|thermal|precal|adie|efuse"

sep "4. REGULATORY (cfg80211 view)"
iw reg get

sep "5. IWINFO (composite reported power)"
iwinfo

sep "6. IW PHY (per-phy channel max powers — THIS is where the clamp shows)"
for p in $(ls /sys/class/ieee80211/ 2>/dev/null); do
  echo "==== $p ===="
  iw phy "$p" info
done

sep "7. UCI WIRELESS"
uci show wireless

sep "8. ANTENNA / CHAINMASK / TX-RX paths"
for p in $(ls /sys/class/ieee80211/ 2>/dev/null); do
  echo "==== $p ===="
  iw phy "$p" info | grep -Ei "Configured Antennas|Available Antennas|TX/RX|antenna"
done

sep "9. SKU LIMIT / DEBUGFS TXPOWER (if mt76 debugfs present)"
# These expose the actual per-rate SKU power-limit table the driver programmed.
for d in /sys/kernel/debug/ieee80211/phy*/mt76 ; do
  [ -d "$d" ] || continue
  echo "==== $d ===="
  ls -l "$d"
  for f in txpower_sku txpower rate_txpower xmit-queues eeprom ; do
    [ -e "$d/$f" ] && { echo "-- $f --"; cat "$d/$f" 2>/dev/null | head -200; }
  done
done

sep "10. THERMAL / TSSI"
for t in /sys/class/thermal/thermal_zone*/temp; do echo "$t = $(cat $t 2>/dev/null)"; done
dmesg | grep -Ei "thermal|tssi|temperature"

sep "11. LIVE STATION / SURVEY (run while a client is connected & passing traffic)"
for i in wlan0 wlan1 phy0-ap0 phy1-ap0; do
  iw dev "$i" info        >/dev/null 2>&1 && { echo "==== $i station dump ===="; iw dev "$i" station dump; }
done
for i in wlan0 wlan1 phy0-ap0 phy1-ap0; do
  iw dev "$i" info        >/dev/null 2>&1 && { echo "==== $i survey dump ===="; iw dev "$i" survey dump; }
done

sep "12. RAW FACTORY DUMP COMMAND (for Phase 2 — DOES NOT MODIFY, only computes hash + dumps)"
# Replace mtdX with the Factory partition number from section 1.
echo "Run manually after identifying the partition, e.g.:"
echo "  FAC=\$(grep -i factory /proc/mtd | cut -d: -f1)   # e.g. mtd5"
echo "  cat /dev/\$FAC > /tmp/factory.bin"
echo "  sha256sum /tmp/factory.bin"
echo "  hexdump -C /tmp/factory.bin | sed -n '1,40p'        # header"
echo "  # MT7915 power fields live around 0x2fc(2G),0x34b(5G); v2 0x441/0x445."

sep "DONE"
echo "Copy this whole output back into results/phase1-<date>.txt"
