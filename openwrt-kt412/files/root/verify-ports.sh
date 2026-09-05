#!/bin/sh
# KT412 per-port status (swconfig switch0: WAN=port1, LAN1..4=ports 5,4,3,2)
echo "===== SWITCH (swconfig dev switch0) ====="
swconfig dev switch0 show 2>/dev/null
echo
echo "===== PORT LINK / SPEED / DUPLEX ====="
for p in 0 1 2 3 4 5; do
	echo "--- switch0 port $p ---"
	swconfig dev switch0 port $p get link 2>/dev/null
done
echo
echo "===== CPU IFACES (eth0 / VLAN ifaces) ====="
for d in eth0 eth0.1 eth0.2 eth1; do
	[ -e "/sys/class/net/$d" ] || continue
	echo "--- $d ---"
	ip -s link show "$d"
	echo "    operstate: $(cat /sys/class/net/$d/operstate 2>/dev/null)  speed: $(cat /sys/class/net/$d/speed 2>/dev/null)Mb"
done
echo
echo "===== RX/TX/ERRORS/DROPS ====="
cat /proc/net/dev
echo
echo "===== VLAN MAP ====="
bridge vlan show 2>/dev/null
uci show network | grep -i 'switch_vlan\|ifname\|ports' 2>/dev/null
