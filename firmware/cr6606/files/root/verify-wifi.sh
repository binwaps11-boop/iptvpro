#!/bin/sh
# verify-wifi.sh  — RUN ON THE ROUTER AFTER FLASHING.  100% read-only.
# Produces the REAL proof of txpower + that features actually work.
#   ssh root@192.168.100.1  'sh /root/verify-wifi.sh'  | tee /tmp/proof.txt
# Then send /tmp/proof.txt back.

line(){ echo; echo "==================== $1 ===================="; }

line "1) REGULATORY DOMAIN (must be US)"
iw reg get

line "2) RADIOS"
iw dev

line "3) iwinfo (REAL applied TX-Power per radio)"
iwinfo

line "4) PER-RADIO TX-POWER (the number that truly matters)"
for p in phy0 phy1; do
  echo "--- $p ---"
  iwinfo $p info 2>/dev/null | grep -iE "Tx-Power|HW Mode|Channel|Mode"
done

line "5) requested vs accepted vs applied"
echo "[requested in config]"
uci -q get wireless.radio0.txpower | sed 's/^/  radio0(2.4G): /'
uci -q get wireless.radio1.txpower | sed 's/^/  radio1(5G):  /'
echo "[accepted by driver: 'iw' txpower]"
for d in $(iw dev | awk '/Interface/{print $2}'); do
  tp=$(iw dev "$d" info 2>/dev/null | awk '/txpower/{print $2" "$3}')
  echo "  $d -> $tp"
done

line "6) FULL CHANNEL/POWER TABLE (iw list)"
iw list | grep -E "Band|MHz|dBm|TX power|Frequencies" -A 80

line "7) wireless config"
cat /etc/config/wireless

line "8) FEATURE CHECKS (does it actually work?)"
echo "[LuCI / uhttpd]"; pgrep -x uhttpd >/dev/null && echo "  uhttpd RUNNING (open http://192.168.100.1)" || echo "  uhttpd DOWN"
echo "[SSH / dropbear]"; /etc/init.d/dropbear enabled && echo "  dropbear ENABLED" || echo "  dropbear off"
echo "[DHCP server]"; pgrep -x dnsmasq >/dev/null && echo "  dnsmasq RUNNING" || echo "  dnsmasq DOWN"
echo "  leases:"; cat /tmp/dhcp.leases 2>/dev/null | sed 's/^/    /' | head
echo "[WAN]"; ifstatus wan 2>/dev/null | grep -E '"up"|"address"' | sed 's/^/  /'
echo "[PPPoE available]"; (opkg list-installed 2>/dev/null | grep -q ppp-mod-pppoe) && echo "  ppp-mod-pppoe INSTALLED (ready)" || echo "  missing"
echo "[VLAN / DSA]"; bridge vlan show 2>/dev/null | head -20
echo "[Firewall/NAT]"; nft list table inet fw4 >/dev/null 2>&1 && echo "  fw4 active" || echo "  fw4 missing"
echo "  masquerade:"; nft list chain inet fw4 srcnat 2>/dev/null | grep -i masquerade | sed 's/^/    /'
echo "[Flow offload]"; uci -q get firewall.@defaults[0].flow_offloading | sed 's/^/  software offload = /'
echo "[Packet steering]"; uci -q get network.globals.packet_steering | sed 's/^/  = /'
echo "[irqbalance]"; pgrep -x irqbalance >/dev/null && echo "  RUNNING" || echo "  not running"
echo "[Watchdog]"; dmesg | grep -i watchdog | head -3 | sed 's/^/  /'
echo "[Health check]"; crontab -l 2>/dev/null | grep healthcheck | sed 's/^/  /'
echo "[WireGuard]"; (opkg list-installed 2>/dev/null | grep -q wireguard-tools) && echo "  installed" || echo "  missing"

line "9) STABILITY: errors in logs"
echo "[kernel panic/oom/crash/reset]"
( logread; dmesg ) 2>/dev/null | grep -iE "panic|out of memory|oom|mt7915.*(reset|fail|error)|watchdog|reboot|call trace" | tail -20 || echo "  (none found)"

line "10) RESOURCES"
free -m; echo; df -h | grep -E "overlay|/$|tmpfs"
echo; echo "uptime:"; uptime

line "DONE"
echo "Send /tmp/proof.txt back. The TX-Power in section 3/4 is the REAL emitted value."
