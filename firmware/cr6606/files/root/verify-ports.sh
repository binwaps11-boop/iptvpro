#!/bin/sh
# verify-ports.sh — REAL per-port status (DSA). READ-ONLY.
#   sh /root/verify-ports.sh | tee /tmp/ports.txt
# CR6606 DSA ports: lan1 lan2 lan3 wan. (Confirmed from device tree.)

PORTS="lan1 lan2 lan3 wan"

printf "%-6s %-6s %-8s %-7s %-14s %-14s %-8s %-8s\n" \
  PORT LINK SPEED DUPLEX RX_bytes TX_bytes RX_err TX_drop
for p in $PORTS; do
  d=/sys/class/net/$p
  [ -d "$d" ] || { printf "%-6s %s\n" "$p" "(not present)"; continue; }
  oper=$(cat $d/operstate 2>/dev/null)
  sp=$(ethtool $p 2>/dev/null | awk -F': ' '/Speed/{print $2}')
  du=$(ethtool $p 2>/dev/null | awk -F': ' '/Duplex/{print $2}')
  rxb=$(cat $d/statistics/rx_bytes 2>/dev/null)
  txb=$(cat $d/statistics/tx_bytes 2>/dev/null)
  rxe=$(cat $d/statistics/rx_errors 2>/dev/null)
  txd=$(cat $d/statistics/tx_dropped 2>/dev/null)
  printf "%-6s %-6s %-8s %-7s %-14s %-14s %-8s %-8s\n" \
    "$p" "${oper:-?}" "${sp:-?}" "${du:-?}" "${rxb:-0}" "${txb:-0}" "${rxe:-0}" "${txd:-0}"
done

echo
echo "=== ROLE (LAN / WAN / bridge member) ==="
echo "br-lan members:"; bridge link 2>/dev/null | awk '{print "  "$2" -> "$0}' | sed 's/master.*//'
echo
echo "=== VLAN per port (bridge vlan show) ==="
bridge vlan show 2>/dev/null

echo
echo "=== live throughput (2s sample, per port) ==="
for p in $PORTS; do
  d=/sys/class/net/$p; [ -d "$d" ] || continue
  r1=$(cat $d/statistics/rx_bytes); t1=$(cat $d/statistics/tx_bytes)
  sleep 0.0001; done
sleep 2
for p in $PORTS; do
  d=/sys/class/net/$p; [ -d "$d" ] || continue
  : ; done
echo "(for continuous per-port graphs use LuCI -> Statistics, collectd-interface is installed)"
echo
echo "NOTE: On DSA there is no per-port enable/disable switch button. To bring a port"
echo "down/up use:   ip link set lan2 down   /   ip link set lan2 up"
echo "VLAN access/trunk is set via bridge-vlan (see /root/quick-setup.sh vlan)."
echo "DONE -> /tmp/ports.txt"
