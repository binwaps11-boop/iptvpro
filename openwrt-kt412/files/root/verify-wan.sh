#!/bin/sh
# KT412 WAN / Multi-WAN verification
. /lib/functions/network.sh 2>/dev/null
echo "===== WAN INTERFACES (ubus) ====="
for i in wan wan2 wan6; do
	ubus call network.interface.$i status 2>/dev/null | grep -E '"up"|"proto"|"address"|"mask"|"nexthop"|"l3_device"|"uptime"' && echo "  [$i]"
done
echo
echo "===== ADDRESSES / GW / DNS ====="
for i in wan wan2; do
	ip=""; gw=""; network_get_ipaddr ip "$i" 2>/dev/null
	network_get_gateway gw "$i" 2>/dev/null
	echo "$i: ip=$ip gw=$gw"
done
echo "DNS:"; cat /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null
echo
echo "===== DEFAULT ROUTES ====="; ip route | grep -E 'default'
echo
echo "===== HEALTH PING (1.1.1.1 / 8.8.8.8) ====="
for t in 1.1.1.1 8.8.8.8; do
	printf "%-9s: " "$t"; ping -c2 -W2 "$t" >/dev/null 2>&1 && echo OK || echo FAIL
done
echo
echo "===== MWAN3 STATUS ====="
mwan3 status 2>/dev/null || echo "mwan3 not installed/active"
echo
echo "===== MWAN3 POLICIES ====="
mwan3 policies 2>/dev/null
