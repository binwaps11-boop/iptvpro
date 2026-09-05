#!/bin/sh
# /root/verify-ports.sh - per-port real status for CR6606 (DSA).
# Ports: lan1 lan2 lan3 (switch) + wan (dedicated gmac1). Read-only.
PORTS="lan1 lan2 lan3 wan"

echo "===== CR6606 PORT STATUS (DSA) ====="
printf "%-6s %-5s %-7s %-6s %-12s %-14s %-8s %-8s\n" \
  PORT LINK SPEED DUPLEX ROLE "RX/TX bytes" ERRORS DROPS

for p in $PORTS; do
	[ -e "/sys/class/net/$p" ] || { printf "%-6s %s\n" "$p" "absent"; continue; }
	carrier="$(cat /sys/class/net/$p/carrier 2>/dev/null)"
	link="down"; [ "$carrier" = "1" ] && link="up"
	speed="-"; duplex="-"
	if command -v ethtool >/dev/null 2>&1; then
		e="$(ethtool "$p" 2>/dev/null)"
		speed="$(echo "$e" | sed -n 's/.*Speed: \([0-9]*\)Mb.*/\1/p')"; [ -z "$speed" ] && speed="-"
		duplex="$(echo "$e" | sed -n 's/.*Duplex: \(.*\)/\1/p')"; [ -z "$duplex" ] && duplex="-"
	fi
	# Role: wan port vs lan (bridge member)
	role="lan"; [ "$p" = "wan" ] && role="wan"
	rx="$(cat /sys/class/net/$p/statistics/rx_bytes 2>/dev/null)"
	tx="$(cat /sys/class/net/$p/statistics/tx_bytes 2>/dev/null)"
	rxe="$(cat /sys/class/net/$p/statistics/rx_errors 2>/dev/null)"
	txe="$(cat /sys/class/net/$p/statistics/tx_errors 2>/dev/null)"
	rxd="$(cat /sys/class/net/$p/statistics/rx_dropped 2>/dev/null)"
	txd="$(cat /sys/class/net/$p/statistics/tx_dropped 2>/dev/null)"
	printf "%-6s %-5s %-7s %-6s %-12s %-14s %-8s %-8s\n" \
	  "$p" "$link" "$speed" "$duplex" "$role" "${rx:-0}/${tx:-0}" "${rxe:-0}/${txe:-0}" "${rxd:-0}/${txd:-0}"
done

echo
echo "===== VLAN MEMBERSHIP (bridge vlan show) ====="
bridge vlan show 2>/dev/null || echo "bridge cmd missing (install ip-bridge)"
echo
echo "===== BRIDGE LINK ====="
bridge link 2>/dev/null
echo
echo "===== verify-ports DONE ====="
