#!/bin/sh
# KT412 SUPER CHECK — full power/stability/performance test.
# Output: /tmp/kt412-super-check-<ts>/report.txt  +  /tmp/kt412-super-check-<ts>.tar.gz
TS="$(date +%s 2>/dev/null || echo now)"
OUT="/tmp/kt412-super-check-$TS"
mkdir -p "$OUT"; LOG="$OUT/report.txt"
{
echo "================= KT412 SUPER CHECK  $(date) ================="
echo; echo "## BOARD"; ubus call system board; cat /etc/openwrt_release

echo; echo "## POWER — iwinfo"; iwinfo
echo; echo "## 2.4G iwinfo"; iwinfo phy1-ap0 info
echo; echo "## 5G iwinfo"; iwinfo phy0-ap0 info
echo; echo "## iw phy phy1 (2.4G channels)"; iw phy phy1 info | grep -E "2412|2417|2422|2427|2432|2437|2442|2447|2452|2457|2462|dBm" -A1
echo; echo "## iw phy phy0 (5G)"; iw phy phy0 info | grep -E "MHz \[" | head
echo; echo "## debugfs"; mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
echo -n "user_power="; cat /sys/kernel/debug/ieee80211/phy1/user_power 2>/dev/null
echo -n "netdev txpower="; cat /sys/kernel/debug/ieee80211/phy1/netdev:phy1-ap0/txpower 2>/dev/null

echo; echo "## ===== 2.4G POWER — 6 LAYERS (strict, never mixed) ====="
PB="/sys/kernel/debug/ieee80211/phy1"
L1="$(uci -q get wireless.radio0.txpower)"
L3="$(iwinfo phy1-ap0 info 2>/dev/null | sed -n 's/.*Tx-Power: \([0-9]*\).*/\1/p')"
L4u="$(cat $PB/user_power 2>/dev/null)"; L4n="$(cat $PB/netdev:phy1-ap0/txpower 2>/dev/null)"
echo "Layer 1  System Power      (uci txpower)        = ${L1:-?} dBm"
echo "Layer 2  Driver Power      (ath9k patch)        = compiled-in (build gate markers=2)"
echo "Layer 3  PHY Advertised    (iwinfo/iw phy)      = ${L3:-?} dBm"
echo "Layer 4  DebugFS Applied   (user_power/txpower) = user_power=${L4u:-?}  netdev_txpower=${L4n:-?}"
echo "Layer 5  Conducted RF      (chip pin, RF meter) = NOT MEASURED (no external RF meter)"
echo "Layer 6  EIRP              (after antenna)      = NOT MEASURED (needs antenna gain + cable loss)"
#   Optional EIRP estimate: pass ANT_GAIN and CABLE_LOSS (dB) in the environment.
if [ -n "$ANT_GAIN" ]; then
  COND="${COND_TX:-24}"   # assumed CLEAN conducted (override with COND_TX once measured)
  EIRP=$(( COND + ANT_GAIN - ${CABLE_LOSS:-0} ))
  echo "         EIRP estimate     = ${COND}(assumed clean conducted) + ${ANT_GAIN} dBi - ${CABLE_LOSS:-0} dB = ${EIRP} dBm  (EIRP, NOT conducted)"
fi

echo; echo "## POWER PER CHANNEL 1..11 (sets ch + txpower 30; reject if any != 30)"
FAILCH=0
for ch in 1 2 3 4 5 6 7 8 9 10 11; do
  uci set wireless.radio0.channel="$ch"; uci set wireless.radio0.txpower='30'; uci commit wireless
  wifi reload >/dev/null 2>&1; sleep 6
  p="$(iwinfo phy1-ap0 info 2>/dev/null | sed -n 's/.*Tx-Power: \([0-9]*\).*/\1/p')"
  up="$(cat $PB/user_power 2>/dev/null)"; nt="$(cat $PB/netdev:phy1-ap0/txpower 2>/dev/null)"
  if [ "$p" = "30" ]; then v="PASS"; else v="FAIL"; FAILCH=$((FAILCH+1)); fi
  printf 'CH%-2s = %s PASS_VALUE(iwinfo=%s user_power=%s netdev=%s) %s\n' "$ch" "${p:-?}" "${p:-?}" "${up:-?}" "${nt:-?}" "$v"
done

echo; echo "## ===== SYSTEM-30 VERDICT (layers 1-4, CH1..11) ====="
if [ "$FAILCH" = "0" ] && [ "$L3" = "30" ]; then
  echo "SYSTEM-30 (in-system, CH1..11): PASS  — all channels report 30 dBm"
else
  echo "SYSTEM-30 (in-system, CH1..11): FAIL  — $FAILCH channel(s) != 30 (or iwinfo != 30) -> REJECT"
fi
echo "RF / EIRP GATE (explicit):"
echo "  Conducted RF 30 dBm : NOT MEASURED  (needs RF power meter / spectrum analyzer)"
if [ -n "$ANT_GAIN" ]; then
  echo "  EIRP 30 dBm        : ESTIMATE ONLY = assumed_conducted + ${ANT_GAIN} dBi - ${CABLE_LOSS:-0} dB (state assumptions; NOT a measurement)"
else
  echo "  EIRP 30 dBm        : NOT MEASURED  (run with ANT_GAIN=<dBi> [CABLE_LOSS=<dB>] for an EIRP estimate)"
fi
echo "  => 'real RF/EIRP 30' is claimed ONLY with a meter reading or a stated EIRP calculation."

echo; echo "## CLIENTS / signal / bitrate"
for i in phy0-ap0 phy1-ap0; do echo "[$i]"; iwinfo "$i" assoclist 2>/dev/null; done

echo; echo "## CONNECTIVITY"
GW="$(ip route 2>/dev/null | awk '/default/{print $3; exit}')"
echo "-- ping gateway $GW --"; ping -c3 -W2 "$GW" 2>&1 | tail -3
echo "-- ping 1.1.1.1 --";     ping -c3 -W2 1.1.1.1 2>&1 | tail -3
echo "-- ping 8.8.8.8 --";     ping -c3 -W2 8.8.8.8 2>&1 | tail -3
echo "-- DNS --";              nslookup openwrt.org 2>&1 | head -5
echo "-- download 1MB --";     wget -q -O /dev/null http://speedtest.tele2.net/1MB.zip && echo "download OK" || echo "download FAILED"

echo; echo "## DSA PORTS"
for p in wan lan1 lan2 lan3 lan4 eth0 eth1; do
  [ -e "/sys/class/net/$p" ] && echo "$p: state=$(cat /sys/class/net/$p/operstate 2>/dev/null) speed=$(cat /sys/class/net/$p/speed 2>/dev/null) rx=$(cat /sys/class/net/$p/statistics/rx_bytes 2>/dev/null) tx=$(cat /sys/class/net/$p/statistics/tx_bytes 2>/dev/null)"
done

echo; echo "## SYSTEM"
uptime; echo; free -m; echo
echo "conntrack: $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null)/$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null)"
for t in /sys/class/thermal/thermal_zone*/temp; do [ -e "$t" ] && echo "temp $t = $(cat "$t")"; done

echo; echo "## VLAN"
echo "-- bridge-vlan + vlan_filtering --"; uci show network 2>/dev/null | grep -E "bridge-vlan|vlan_filtering" || echo "(none — normal bridge)"
echo "-- bridge vlan show (PVID / tagged-untagged per port) --"; bridge vlan show 2>/dev/null | head -40
echo "-- VLAN interfaces (IP) --"; uci show network 2>/dev/null | grep -E "network\.vlan[0-9]"
echo "-- DHCP per VLAN (+ dhcp_option DNS) --"; uci show dhcp 2>/dev/null | grep -E "vlan[0-9]"
echo "-- firewall zones / forwardings / redirects per VLAN (NAT, inter-VLAN, DNS force) --"; uci show firewall 2>/dev/null | grep -iE "vlan[0-9]"
echo "-- Safe Apply backup present? --"; ls /tmp/kt412-rb 2>/dev/null && echo "backup dir EXISTS" || echo "(no active safe-apply backup right now)"
echo "-- Restore (safe_restore) present in API? --"; grep -c 'safe_restore' /www/cgi-bin/kt412 2>/dev/null

echo; echo "## WIFI STABILITY — 60s ping"
ping -c60 -W2 1.1.1.1 2>&1 | tail -4

echo; echo "## ERRORS — logread (reset/timeout/deauth/disconnect/ath9k/ath10k/crash)"
logread 2>/dev/null | grep -iE "reset|timeout|deauth|disconn|ath9k|ath10k|crash|firmware|error" | tail -60
echo; echo "## ERRORS — dmesg"
dmesg 2>/dev/null | grep -iE "ath9k|ath10k|reset|timeout|crash|firmware|error" | tail -60

echo; echo "================= END ================="
} > "$LOG" 2>&1

tar czf "$OUT.tar.gz" -C /tmp "kt412-super-check-$TS" 2>/dev/null
echo "Report : $LOG"
echo "Bundle : $OUT.tar.gz"
echo "(download the bundle from the dashboard or: scp it off the device)"
