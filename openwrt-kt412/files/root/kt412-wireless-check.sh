#!/bin/sh
# KT412 wireless check (read-only): radios, modes, 5G health, mesh, clients.
OUT=/root/WIRELESS_RESULT.txt
{
echo "===================== KT412 WIRELESS CHECK ====================="
echo "## wifi status"; wifi status 2>/dev/null
echo "## iw dev"; iw dev 2>/dev/null
echo "## 2.4G (phy1)"; iwinfo phy1-ap0 info 2>/dev/null
echo "## 5G (phy0)"; iwinfo phy0-ap0 info 2>/dev/null
echo "## 5G hostapd/phy errors (expect NONE)"
logread 2>/dev/null | grep -Ei 'phy0|ath10k|hostapd|BRIDGE_NOT_ALLOWED|Failed to open' | tail -30
echo "## mesh (if any)"; for i in $(iw dev 2>/dev/null | sed -n 's/.*Interface \(.*\)/\1/p'); do
  m=$(iw dev "$i" info 2>/dev/null | grep -i 'type mesh'); [ -n "$m" ] && { echo "mesh iface $i:"; iw dev "$i" station dump 2>/dev/null | grep -E 'Station|signal|rx bitrate|tx bitrate'; iw dev "$i" mpath dump 2>/dev/null; }
done
echo "## /etc/config/wireless"; cat /etc/config/wireless 2>/dev/null
echo "===================== END ====================="
} | tee "$OUT"
