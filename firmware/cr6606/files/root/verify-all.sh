#!/bin/sh
# verify-all.sh — full system proof. READ-ONLY. Run after flashing:
#   sh /root/verify-all.sh | tee /tmp/verify-all.txt
s(){ echo; echo "===================== $1 ====================="; }

s "BOARD";            ubus call system board
s "RELEASE";          cat /etc/openwrt_release
s "CPU";              grep -E 'model name|system type|cpu model' /proc/cpuinfo | head
s "RAM";              free -m
s "STORAGE";          df -h | grep -E 'Filesystem|overlay|/$|tmpfs'
s "UPTIME/LOAD";      uptime
s "TEM（thermal)";    for z in /sys/class/thermal/thermal_zone*/temp; do [ -f "$z" ] && echo "$z = $(( $(cat $z)/1000 ))C"; done
s "IP ADDR";          ip -br addr
s "IP ROUTE";         ip route
s "BRIDGE VLAN";      bridge vlan show 2>/dev/null
s "DSA PORTS";        ls /sys/class/net/ | tr '\n' ' '; echo
s "WIFI STATUS";      wifi status 2>/dev/null
s "IWINFO";           iwinfo
s "REG";              iw reg get
s "NETWORK CFG";      cat /etc/config/network
s "WIRELESS CFG";     cat /etc/config/wireless
s "FIREWALL CFG";     cat /etc/config/firewall
s "SERVICES (enabled?)"
for x in network firewall dnsmasq odhcpd uhttpd dropbear cron irqbalance; do
  printf "  %-12s " "$x"; /etc/init.d/$x enabled 2>/dev/null && echo "ENABLED" || echo "off/none"
done
s "SERVICES (running?)"
for x in uhttpd dropbear dnsmasq odhcpd firewall netifd irqbalance; do
  printf "  %-12s " "$x"; pgrep -f "$x" >/dev/null && echo "RUNNING" || echo "down"
done
s "NAT (fw4)";        nft list table inet fw4 >/dev/null 2>&1 && echo "fw4 active" || echo "fw4 MISSING"
s "INSTALLED FEATURE PKGS"
for p in luci luci-theme-argon ppp-mod-pppoe wireguard-tools adblock sqm-scripts \
         ddns-scripts miniupnpd-nftables vnstat2 kmod-mt7915e luci-app-statistics; do
  printf "  %-22s " "$p"; (opkg list-installed 2>/dev/null | grep -q "^$p ") && echo "yes" || echo "NO"
done
s "LOGREAD tail";     logread | tail -300
s "DMESG tail";       dmesg | tail -300
s "ERROR SCAN"
( logread; dmesg ) 2>/dev/null | grep -iE "panic|oom|out of memory|mt7915.*(reset|fail|error)|watchdog|call trace|reboot" | tail -30 || echo "  none"
echo; echo "DONE -> /tmp/verify-all.txt"
