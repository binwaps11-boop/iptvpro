#!/bin/sh
# KT412 — full state check. Tells you if the PRO build is REALLY active.
echo "================ KT412 STATE CHECK ================"
echo
echo "== OpenWrt build =="
cat /etc/openwrt_release 2>/dev/null | grep -E 'DESCRIPTION|REVISION'
echo "uptime: $(uptime)"
echo
echo "== LuCI theme (active) =="
echo "mediaurlbase = $(uci -q get luci.main.mediaurlbase)"
echo
echo "== Key PRO packages installed? =="
for p in luci-theme-material luci-app-sqm sqm-scripts kmod-sched-cake ttyd luci-app-ttyd luci-app-mwan3 mwan3 luci-app-commands; do
  if opkg list-installed 2>/dev/null | grep -q "^$p "; then echo "  [YES] $p"; else echo "  [ -- ] $p  MISSING"; fi
done
echo
echo "== Banner =="
head -2 /etc/banner 2>/dev/null
echo
echo "== Network / IP =="
echo "LAN ip = $(uci -q get network.lan.ipaddr)"
echo "flow_offloading = $(uci -q get firewall.@defaults[0].flow_offloading)"
echo "packet_steering = $(uci -q get network.@globals[0].packet_steering)"
echo
echo "== Wi-Fi =="
iwinfo 2>/dev/null | grep -iE 'ESSID|Tx-Power|Channel' | head
echo
echo "== Switch / ports / VLAN =="
swconfig dev switch0 show 2>/dev/null | grep -iE 'link|vlan|ports' | head -20
echo
echo "== Services =="
for s in network firewall dnsmasq uhttpd dropbear mwan3 sqm ttyd; do
  printf "  %-9s: " "$s"; /etc/init.d/$s enabled 2>/dev/null && echo on || echo off
done
echo
echo "== Errors (oom/panic/reset) =="
logread 2>/dev/null | grep -iE 'oom|panic|reset|crash' | tail -5
echo
echo "================ VERDICT ================"
HAVE=0
opkg list-installed 2>/dev/null | grep -q '^luci-app-sqm '  && HAVE=$((HAVE+1))
opkg list-installed 2>/dev/null | grep -q '^ttyd '          && HAVE=$((HAVE+1))
opkg list-installed 2>/dev/null | grep -q '^luci-theme-material ' && HAVE=$((HAVE+1))
if [ "$HAVE" -ge 2 ]; then
  echo "[OK] PRO MAX IS FLASHED. (sqm/ttyd/material present)"
  if [ "$(uci -q get luci.main.mediaurlbase)" != "/luci-static/material" ]; then
    echo "    -> Theme not active. Run:"
    echo "       uci set luci.main.mediaurlbase=/luci-static/material; uci commit luci; /etc/init.d/uhttpd restart"
    echo "    Then refresh browser with Ctrl+F5."
  else
    echo "    -> Theme active. If UI looks old: press Ctrl+F5 (clear browser cache)."
  fi
else
  echo "[NO] PRO MAX is NOT flashed. You are on the OLD system."
  echo "    -> Flash kt412-PRO-MAX-sysupgrade.bin via LuCI (System -> Flash),"
  echo "       UNCHECK 'Keep settings', then it boots on 192.168.100.1."
fi
echo "========================================="
