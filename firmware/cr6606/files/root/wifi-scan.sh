#!/bin/sh
# /root/wifi-scan.sh - exact post-flash diagnostic commands requested for CR6606.
sec(){ echo; echo "===== $1 ====="; }
sec "iwinfo";                 iwinfo
sec "iw phy";                 iw phy
sec "wlan0 station dump";     iw dev wlan0 station dump 2>/dev/null || echo "wlan0 n/a"
sec "wlan1 station dump";     iw dev wlan1 station dump 2>/dev/null || echo "wlan1 n/a"
sec "wlan0 survey dump";      iw dev wlan0 survey dump 2>/dev/null || echo "wlan0 n/a"
sec "wlan1 survey dump";      iw dev wlan1 survey dump 2>/dev/null || echo "wlan1 n/a"
sec "dmesg mt76/power/cal/marker"
dmesg | grep -Ei "mt76|mt7915|wifi|power|eeprom|cal|CR6606" || echo "(no matching lines)"
echo; echo "===== wifi-scan DONE ====="
