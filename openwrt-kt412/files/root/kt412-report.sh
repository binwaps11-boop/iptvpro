#!/bin/sh
# KT412 — REAL proof report. Run on the device:  sh /root/kt412-report.sh
# Produces the exact power/DSA/persistence evidence. NO fabricated values.
LINE='========================================================'
echo "$LINE"; echo " KT412 PROOF REPORT  —  $(date)"; echo "$LINE"

echo; echo "## 1) Firmware / target"
sed -n 's/^DISTRIB_DESCRIPTION=//p' /etc/openwrt_release 2>/dev/null
echo "kernel: $(uname -r)"
echo "board:  $(cat /tmp/sysinfo/board_name 2>/dev/null)"

echo; echo "## 2) DSA proof (not swconfig)"
command -v swconfig >/dev/null 2>&1 && echo "  swconfig EXISTS" || echo "  swconfig absent => DSA OK"
for d in /sys/class/net/*; do [ -e "$d/dsa" ] && echo "  $(basename "$d"): DSA port"; done
bridge vlan show 2>/dev/null | head -20
ip -br link 2>/dev/null | grep -E 'lan|wan|br-lan'

echo; echo "## 3) WiFi POWER — exact commands"
echo "----- iwinfo -----";                 iwinfo 2>/dev/null
echo "----- iwinfo phy1-ap0 info (2.4G) -----"; iwinfo phy1-ap0 info 2>/dev/null
echo "----- iwinfo phy0-ap0 info (5G) -----";   iwinfo phy0-ap0 info 2>/dev/null
echo "----- iw phy phy1 info (2.4G channels) -----"; iw phy phy1 info 2>/dev/null | grep -E 'MHz \[' | head -20
echo "----- iw phy phy0 info (5G channels) -----";   iw phy phy0 info 2>/dev/null | grep -E 'MHz \[' | head -20
echo "----- wifi status -----";            ubus call network.wireless status 2>/dev/null | grep -iE 'ssid|up|mode|channel' | head
echo "----- iw reg get -----";             iw reg get 2>/dev/null | head -8
echo "----- debugfs user_power (phy1=2.4G) -----"
cat /sys/kernel/debug/ieee80211/phy1/user_power 2>/dev/null || echo "  (path differs; trying glob)"
cat /sys/kernel/debug/ieee80211/phy*/user_power 2>/dev/null
echo "----- debugfs netdev txpower (phy1-ap0) -----"
cat /sys/kernel/debug/ieee80211/phy1/netdev:phy1-ap0/txpower 2>/dev/null || true
cat /sys/kernel/debug/ieee80211/phy*/netdev:*/txpower 2>/dev/null
echo "----- configured (uci) -----"
for r in $(uci show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.=]*\)=wifi-device/\1/p'); do
  echo "  $r: txpower=$(uci -q get wireless.$r.txpower) band=$(uci -q get wireless.$r.band) country=$(uci -q get wireless.$r.country)"
done

echo; echo "## 4) Per-client signal / rate"
for i in $(iwinfo 2>/dev/null | sed -n 's/^\([A-Za-z0-9._-]*\) *ESSID:.*/\1/p'); do
  echo "  [$i]"; iwinfo "$i" assoclist 2>/dev/null | grep -iE 'dBm|SNR|Rate' | head
done

echo; echo "## 5) Persistence (run again AFTER reboot — values must match)"
for r in $(uci show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.=]*\)=wifi-device/\1/p'); do
  echo "  $r txpower=$(uci -q get wireless.$r.txpower)"
done
echo "  lan ip: $(uci -q get network.lan.ipaddr)  wan proto: $(uci -q get network.wan.proto)"

echo; echo "## 6) Performance"
echo "  load:$(cut -d' ' -f1-3 /proc/loadavg)"
free -m 2>/dev/null | awk '/Mem/{print "  mem: "$3"/"$2" MB used"}'
echo "  conntrack:$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)/$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
echo "$LINE"; echo " END OF REPORT"; echo "$LINE"
