#!/bin/sh
# KT412 services health
for s in network firewall dnsmasq uhttpd dropbear odhcpd mwan3; do
	echo "===== $s ====="
	if [ -x "/etc/init.d/$s" ]; then
		/etc/init.d/$s enabled 2>/dev/null && echo "boot: enabled" || echo "boot: disabled"
		/etc/init.d/$s status 2>/dev/null || echo "  (no status verb)"
		pgrep -fl "$s" 2>/dev/null | head -3
	else
		echo "not installed"
	fi
	echo
done
echo "===== WATCHDOG ====="
[ -e /dev/watchdog ] && echo "/dev/watchdog present" || echo "no /dev/watchdog"
echo "===== LISTENING SOCKETS ====="
netstat -ltnp 2>/dev/null || ss -ltnp 2>/dev/null
echo "===== RECENT ERRORS ====="
logread | grep -iE 'error|fail|panic|oom|reset|crash' | tail -40
