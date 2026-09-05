#!/bin/sh
# /root/verify-wifi.sh - Wi-Fi snapshot for CR6606 (mt7915 / mt76). Read-only.
sec() { echo; echo "===== $1 ====="; }

sec "IWINFO";        iwinfo 2>/dev/null
sec "REG DOMAIN";    iw reg get
sec "IW DEV";        iw dev
sec "WIFI STATUS";   wifi status 2>/dev/null
sec "CONFIG wireless"; cat /etc/config/wireless
sec "PHY CAPABILITIES (Band/MHz/dBm/HE/VHT/HT)"
iw list | grep -E "Band|MHz|dBm|TX power|Frequencies|HE|VHT|HT" -A 80
echo
echo "===== verify-wifi DONE ====="
