#!/bin/sh
# /root/verify-all.sh - full device snapshot & proof. Read-only. CR6606.
sec() { echo; echo "===== $1 ====="; }

sec "BOARD";              ubus call system board
sec "RELEASE";            cat /etc/openwrt_release
sec "MEMORY (MB)";        free -m
sec "STORAGE";            df -h
sec "UPTIME";             cat /proc/uptime
sec "IP ADDR";            ip addr
sec "IP ROUTE";           ip route
sec "IP LINK";            ip link
sec "BRIDGE VLAN SHOW";   bridge vlan show 2>/dev/null || echo "bridge cmd missing (install ip-bridge)"
sec "IWINFO";             iwinfo 2>/dev/null
sec "REG DOMAIN";         iw reg get
sec "WIFI STATUS";        wifi status 2>/dev/null
sec "CONFIG: network";    cat /etc/config/network
sec "CONFIG: wireless";   cat /etc/config/wireless
sec "CONFIG: firewall";   cat /etc/config/firewall
sec "SERVICE: network";   /etc/init.d/network   status 2>/dev/null || /etc/init.d/network   enabled && echo enabled
sec "SERVICE: firewall";  /etc/init.d/firewall  status 2>/dev/null || /etc/init.d/firewall  enabled && echo enabled
sec "SERVICE: dnsmasq";   /etc/init.d/dnsmasq   status 2>/dev/null || /etc/init.d/dnsmasq   enabled && echo enabled
sec "SERVICE: uhttpd";    /etc/init.d/uhttpd    status 2>/dev/null || /etc/init.d/uhttpd    enabled && echo enabled
sec "SERVICE: dropbear";  /etc/init.d/dropbear  status 2>/dev/null || /etc/init.d/dropbear  enabled && echo enabled
sec "SERVICE: odhcpd";    /etc/init.d/odhcpd    status 2>/dev/null || /etc/init.d/odhcpd    enabled && echo enabled
sec "SERVICE: watchdog";  ls -l /dev/watchdog* 2>/dev/null; (ubus call system watchdog 2>/dev/null || echo "procd manages hw watchdog")
sec "SERVICE: health";    /etc/init.d/cr6606-health status 2>/dev/null || echo "n/a"
sec "LOGREAD (tail 300)"; logread | tail -n 300
sec "DMESG (tail 300)";   dmesg | tail -n 300
echo; echo "===== verify-all DONE ====="
