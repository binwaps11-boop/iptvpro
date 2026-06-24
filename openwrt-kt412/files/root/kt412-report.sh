#!/bin/sh
# KT412 — REAL proof report. Run on the device:  sh /root/kt412-report.sh
# Produces the exact evidence (power / DSA / persistence) with NO fake values.
LINE='========================================================'
echo "$LINE"; echo " KT412 PROOF REPORT  —  $(date)"; echo "$LINE"

echo; echo "## 1) Firmware / build"
sed -n 's/^DISTRIB_DESCRIPTION=//p' /etc/openwrt_release 2>/dev/null
uname -r

echo; echo "## 2) DSA proof (real DSA, not swconfig)"
echo "-- swconfig present? (should be ABSENT on DSA) --"
command -v swconfig >/dev/null 2>&1 && echo "  swconfig EXISTS (=swconfig build)" || echo "  swconfig absent  => DSA build OK"
echo "-- DSA switch ports (/sys/class/net/*/dsa or phy_mode) --"
for d in /sys/class/net/*; do
  n=$(basename "$d")
  [ -e "$d/dsa" ] && echo "  $n : DSA slave port"
done
echo "-- bridge / vlan --"
bridge vlan show 2>/dev/null | head -20
echo "-- LAN bridge + WAN --"
ip -br link 2>/dev/null | grep -E 'lan|wan|br-lan'

echo; echo "## 3) Wi-Fi power — REAL values"
echo "-- iwinfo (both radios) --"
for i in $(iwinfo 2>/dev/null | sed -n 's/^\([A-Za-z0-9._-]*\) *ESSID:.*/\1/p'); do
  echo "  [$i]"; iwinfo "$i" info 2>/dev/null | grep -iE 'ESSID|Mode|Channel|Tx-Power|Signal|Bit Rate'
done
echo "-- iw phy phy0 channel power table --"
iw phy phy0 info 2>/dev/null | grep -E 'MHz \[' | head -20
echo "-- iw phy phy1 channel power table --"
iw phy phy1 info 2>/dev/null | grep -E 'MHz \[' | head -20
echo "-- configured txpower (uci) --"
for r in $(uci show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.=]*\)=wifi-device/\1/p'); do
  echo "  $r: txpower=$(uci -q get wireless.$r.txpower) country=$(uci -q get wireless.$r.country) channel=$(uci -q get wireless.$r.channel)"
done
echo "-- ath9k debugfs (2.4G) user/reg power, if available --"
for f in /sys/kernel/debug/ieee80211/phy*/ath9k/dump_nfcal /sys/kernel/debug/ieee80211/phy*/ath9k/regidx; do :; done
grep -rH . /sys/kernel/debug/ieee80211/phy*/ath9k/*power* 2>/dev/null | head
echo "-- regulatory --"
iw reg get 2>/dev/null | head -8

echo; echo "## 4) Per-client signal / rate"
for i in $(iwinfo 2>/dev/null | sed -n 's/^\([A-Za-z0-9._-]*\) *ESSID:.*/\1/p'); do
  echo "  [$i]"; iwinfo "$i" assoclist 2>/dev/null | grep -iE 'dBm|SNR|Rate' | head
done

echo; echo "## 5) wifi status (ubus)"
ubus call network.wireless status 2>/dev/null | grep -iE 'ssid|up|mode|channel' | head

echo; echo "## 6) Persistence after reboot — saved config"
echo "  (run this report again AFTER a reboot; values must match)"
echo "  wireless ssids:"; uci -q show wireless | grep -E '\.ssid='
echo "  lan ip: $(uci -q get network.lan.ipaddr)"
echo "  wan proto: $(uci -q get network.wan.proto)"

echo; echo "## 7) Performance snapshot"
echo "  load:$(cut -d' ' -f1-3 /proc/loadavg)  mem:$(free -m | awk '/Mem/{print $3"/"$2" MB"}')"
echo "  conntrack:$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)/$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
echo "  flow offload:$(uci -q get firewall.@defaults[0].flow_offloading)"
echo "$LINE"; echo " END OF REPORT"; echo "$LINE"
