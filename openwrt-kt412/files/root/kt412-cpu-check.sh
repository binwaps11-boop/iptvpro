#!/bin/sh
# KT412 CPU check — find what is eating the single 720MHz core. Read-only.
# Run: sh /root/kt412-cpu-check.sh   (copy the whole output back)
echo "===================== KT412 CPU CHECK ====================="
echo "## uptime / load"; uptime; cat /proc/loadavg
echo
echo "## cores"; grep -c ^processor /proc/cpuinfo
echo
echo "## TOP (by CPU) ----------------------------------------------"
top -bn1 2>/dev/null | head -40
echo
echo "## TOP CPU PROCESS"
top -bn1 2>/dev/null | awk 'NR>6 && $0!~/top -bn1/ {print}' | sort -rn -k7 2>/dev/null | head -1
top -bn1 2>/dev/null | grep -E '%CPU|CPU:' | head -3
echo
echo "## ps w ------------------------------------------------------"
ps w 2>/dev/null
echo
echo "## kernel softirq/irq load (ksoftirqd high = network/wifi interrupt storm)"
ps w 2>/dev/null | grep -E 'ksoftirqd|kworker|irq/' | grep -v grep
echo
echo "## ath10k firmware health (SWBA overrun / restart spikes CPU + drops 5G)"
dmesg 2>/dev/null | grep -Ei 'ath10k|SWBA|firmware|restart|crash|wmi' | tail -25
echo
echo "## ath9k events"
dmesg 2>/dev/null | grep -Ei 'ath9k|wmac' | tail -10
echo
echo "## hostapd / wpad"
ps w 2>/dev/null | grep -E 'hostapd|wpad' | grep -v grep
echo
echo "## logread (errors/loops)"
logread 2>/dev/null | tail -60
echo
echo "## conntrack count (high = NAT churn)"
echo "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)/$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
echo
echo "## dashboard backend cache (should exist, <5s old, prevents re-fork)"
ls -l /tmp/kt_devices.json 2>/dev/null || echo "(no cache yet - open the dashboard once)"
echo "===================== END CPU CHECK ====================="
