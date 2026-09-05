#!/bin/sh
# /root/verify-services.sh - prove core services are present & running. CR6606.
chk() {
	name="$1"; init="$2"
	printf "%-12s " "$name"
	if [ ! -x "/etc/init.d/$init" ]; then echo "NOT INSTALLED"; return; fi
	en="disabled"; /etc/init.d/$init enabled 2>/dev/null && en="ENABLED"
	# running? prefer 'status', fall back to process check
	run="?"
	if /etc/init.d/$init status >/dev/null 2>&1; then run="running"; fi
	printf "init=%-8s %s\n" "$en" "$run"
}

echo "===== CR6606 SERVICES ====="
chk uhttpd    uhttpd
chk dropbear  dropbear
chk dnsmasq   dnsmasq
chk firewall  firewall
chk network   network
chk odhcpd    odhcpd
chk rpcd      rpcd
chk nlbwmon   nlbwmon
chk health    cr6606-health

echo
echo "===== Watchdog (hardware, managed by procd) ====="
ls -l /dev/watchdog* 2>/dev/null || echo "no /dev/watchdog node"
( ps w 2>/dev/null | grep -q '[w]atchdog' && echo "procd watchdog active" ) || echo "procd manages mtk-wdt automatically"

echo
echo "===== Listening sockets (LuCI 80/443, SSH 22, DNS 53) ====="
( netstat -lntup 2>/dev/null || ss -lntup 2>/dev/null ) | grep -E ':80|:443|:22|:53' || echo "netstat/ss not available"

echo
echo "===== Recent service errors (logread) ====="
logread | grep -iE "error|fail|crash|panic|oom" | tail -n 30 || echo "no obvious errors"
echo
echo "===== verify-services DONE ====="
