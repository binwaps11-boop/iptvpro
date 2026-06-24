#!/bin/sh
# KT412 SUPER CHECK — full power/stability/performance test.
# Output: /tmp/kt412-super-check-<ts>/report.txt  +  /tmp/kt412-super-check-<ts>.tar.gz
TS="$(date +%s 2>/dev/null || echo now)"
OUT="/tmp/kt412-super-check-$TS"
mkdir -p "$OUT"; LOG="$OUT/report.txt"
{
echo "================= KT412 SUPER CHECK  $(date) ================="
echo; echo "## BOARD"; ubus call system board; cat /etc/openwrt_release

echo; echo "## POWER — iwinfo"; iwinfo
echo; echo "## 2.4G iwinfo"; iwinfo phy1-ap0 info
echo; echo "## 5G iwinfo"; iwinfo phy0-ap0 info
echo; echo "## iw phy phy1 (2.4G channels)"; iw phy phy1 info | grep -E "2412|2417|2422|2427|2432|2437|2442|2447|2452|2457|2462|dBm" -A1
echo; echo "## iw phy phy0 (5G)"; iw phy phy0 info | grep -E "MHz \[" | head
echo; echo "## debugfs"; mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
echo -n "user_power="; cat /sys/kernel/debug/ieee80211/phy1/user_power 2>/dev/null
echo -n "netdev txpower="; cat /sys/kernel/debug/ieee80211/phy1/netdev:phy1-ap0/txpower 2>/dev/null

echo; echo "## POWER PER CHANNEL 1..11 (sets ch + txpower 30, reads applied)"
for ch in 1 2 3 4 5 6 7 8 9 10 11; do
  uci set wireless.radio0.channel="$ch"; uci set wireless.radio0.txpower='30'; uci commit wireless
  wifi reload >/dev/null 2>&1; sleep 6
  p="$(iwinfo phy1-ap0 info 2>/dev/null | sed -n 's/.*Tx-Power: \([0-9]*\).*/\1/p')"
  up="$(cat /sys/kernel/debug/ieee80211/phy1/user_power 2>/dev/null)"
  echo "CH$ch  iwinfo_tx=${p:-?}  user_power=${up:-?}  $( [ "$p" = "30" ] && echo PASS || echo CHECK )"
done

echo; echo "## CLIENTS / signal / bitrate"
for i in phy0-ap0 phy1-ap0; do echo "[$i]"; iwinfo "$i" assoclist 2>/dev/null; done

echo; echo "## CONNECTIVITY"
GW="$(ip route 2>/dev/null | awk '/default/{print $3; exit}')"
echo "-- ping gateway $GW --"; ping -c3 -W2 "$GW" 2>&1 | tail -3
echo "-- ping 1.1.1.1 --";     ping -c3 -W2 1.1.1.1 2>&1 | tail -3
echo "-- ping 8.8.8.8 --";     ping -c3 -W2 8.8.8.8 2>&1 | tail -3
echo "-- DNS --";              nslookup openwrt.org 2>&1 | head -5
echo "-- download 1MB --";     wget -q -O /dev/null http://speedtest.tele2.net/1MB.zip && echo "download OK" || echo "download FAILED"

echo; echo "## DSA PORTS"
for p in wan lan1 lan2 lan3 lan4 eth0 eth1; do
  [ -e "/sys/class/net/$p" ] && echo "$p: state=$(cat /sys/class/net/$p/operstate 2>/dev/null) speed=$(cat /sys/class/net/$p/speed 2>/dev/null) rx=$(cat /sys/class/net/$p/statistics/rx_bytes 2>/dev/null) tx=$(cat /sys/class/net/$p/statistics/tx_bytes 2>/dev/null)"
done

echo; echo "## SYSTEM"
uptime; echo; free -m; echo
echo "conntrack: $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)/$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
for t in /sys/class/thermal/thermal_zone*/temp; do [ -e "$t" ] && echo "temp $t = $(cat "$t")"; done

echo; echo "## VLAN"
uci show network 2>/dev/null | grep -E "bridge-vlan|vlan_filtering|vlan[0-9]" || echo "(no custom VLANs — normal bridge)"
bridge vlan show 2>/dev/null | head -30

echo; echo "## WIFI STABILITY — 60s ping"
ping -c60 -W2 1.1.1.1 2>&1 | tail -4

echo; echo "## ERRORS — logread (reset/timeout/deauth/disconnect/ath9k/ath10k/crash)"
logread 2>/dev/null | grep -iE "reset|timeout|deauth|disconn|ath9k|ath10k|crash|firmware|error" | tail -60
echo; echo "## ERRORS — dmesg"
dmesg 2>/dev/null | grep -iE "ath9k|ath10k|reset|timeout|crash|firmware|error" | tail -60

echo; echo "================= END ================="
} > "$LOG" 2>&1

tar czf "$OUT.tar.gz" -C /tmp "kt412-super-check-$TS" 2>/dev/null
echo "Report : $LOG"
echo "Bundle : $OUT.tar.gz"
echo "(download the bundle from the dashboard or: scp it off the device)"
