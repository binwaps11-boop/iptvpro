#!/bin/sh
# KT412 RF / antenna / power diagnostic. Read-only — prints state, changes nothing.
# Run: sh /root/kt412_check.sh
PHY="$(for p in /sys/kernel/debug/ieee80211/phy*/ath9k; do [ -d "$p" ] && basename "$(dirname "$p")" && break; done)"
[ -n "$PHY" ] || PHY=phy1
echo "=== ath9k PHY detected: $PHY ==="
echo "=== iwinfo ==="; iwinfo 2>/dev/null
echo "=== wifi status ==="; wifi status 2>/dev/null
echo "=== iw $PHY info (antennas + 2.4G channels + dBm) ==="
iw phy "$PHY" info 2>/dev/null | grep -E "Available Antennas|Configured Antennas|2412|2437|2462|dBm" -A1
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
echo "=== chainmask / power (debugfs) ==="
cat /sys/kernel/debug/ieee80211/$PHY/ath9k/tx_chainmask 2>/dev/null | sed 's/^/tx_chainmask=/'
cat /sys/kernel/debug/ieee80211/$PHY/ath9k/rx_chainmask 2>/dev/null | sed 's/^/rx_chainmask=/'
for f in /sys/kernel/debug/ieee80211/$PHY/ath9k/*power* /sys/kernel/debug/ieee80211/$PHY/netdev:*/txpower; do
	[ -e "$f" ] && printf '%s = %s\n' "$f" "$(cat "$f" 2>/dev/null)"
done
echo "=== stations ==="
for i in $(iwinfo 2>/dev/null | sed -n 's/^\([A-Za-z0-9._-]*\) *ESSID.*/\1/p'); do
	echo "-- $i --"; iw dev "$i" station dump 2>/dev/null | grep -E "Station|signal|tx bitrate|rx bitrate"
done
echo "=== survey (in use) ==="
for i in $(iwinfo 2>/dev/null | sed -n 's/^\([A-Za-z0-9._-]*\) *ESSID.*/\1/p'); do
	iw dev "$i" survey dump 2>/dev/null | grep -A6 "in use"
done
echo "=== dmesg markers ==="
dmesg 2>/dev/null | grep -Ei "KT412|30DBM|ANTENNAS|ath9k|eeprom|cal|txpower" | tail -40
echo "=== done ==="
