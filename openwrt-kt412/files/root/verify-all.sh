#!/bin/sh
# KT412 full system verification
echo "===== BOARD ====="; ubus call system board
echo "===== RELEASE ====="; cat /etc/openwrt_release
echo "===== RAM ====="; free -m
echo "===== STORAGE ====="; df -h
echo "===== UPTIME ====="; cat /proc/uptime
echo "===== IP ADDR ====="; ip addr
echo "===== IP ROUTE ====="; ip route
echo "===== IP LINK ====="; ip link
echo "===== BRIDGE VLAN ====="; bridge vlan show 2>/dev/null
echo "===== SWCONFIG ====="; swconfig list 2>/dev/null; swconfig dev switch0 show 2>/dev/null
echo "===== WIFI ====="; iwinfo 2>/dev/null; iw reg get 2>/dev/null; wifi status 2>/dev/null
echo "===== NETWORK CFG ====="; cat /etc/config/network
echo "===== FIREWALL CFG ====="; cat /etc/config/firewall
echo "===== WIRELESS CFG ====="; cat /etc/config/wireless 2>/dev/null
echo "===== SERVICES ====="
for s in network firewall dnsmasq uhttpd dropbear odhcpd mwan3; do
	printf "%-10s: " "$s"; /etc/init.d/$s enabled 2>/dev/null && echo enabled || echo "disabled/none"
done
echo "===== LOGREAD (tail) ====="; logread | tail -300
echo "===== DMESG (tail) ====="; dmesg | tail -300
