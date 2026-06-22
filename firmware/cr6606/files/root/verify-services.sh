#!/bin/sh
# verify-services.sh — proves each service is enabled AND running. READ-ONLY.
#   sh /root/verify-services.sh | tee /tmp/services.txt
chk(){ # $1=initname  $2=process
  printf "%-12s enabled=" "$1"
  /etc/init.d/$1 enabled 2>/dev/null && printf "yes " || printf "no  "
  printf "running="
  pgrep -f "${2:-$1}" >/dev/null 2>&1 && echo "yes" || echo "no"
}
echo "=== core services ==="
chk uhttpd      uhttpd      # LuCI web
chk dropbear    dropbear    # SSH
chk dnsmasq     dnsmasq     # DHCP + DNS
chk odhcpd      odhcpd      # IPv6 DHCP
chk firewall    fw4         # NAT/firewall
chk network     netifd      # network
chk cron        crond
chk irqbalance  irqbalance

echo
echo "=== LuCI reachable? ==="
ubus list 2>/dev/null | grep -q '^uci$' && echo "ubus/uci OK"
pgrep -x uhttpd >/dev/null && echo "uhttpd listening -> open http://192.168.100.1" || echo "uhttpd DOWN"

echo
echo "=== watchdog (hardware) ==="
dmesg | grep -i watchdog | head -3
[ -c /dev/watchdog ] && echo "/dev/watchdog present (procd manages it)" || echo "no /dev/watchdog"

echo
echo "=== health-check cron ==="
crontab -l 2>/dev/null | grep healthcheck || echo "  (cron line missing)"
[ -x /etc/health/healthcheck.sh ] && echo "  healthcheck.sh present" || echo "  healthcheck.sh MISSING"
echo
echo "DONE -> /tmp/services.txt"
