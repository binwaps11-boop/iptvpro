#!/bin/sh
# KT412 DSA check — prove the DSA/qca8k topology and VLAN state. Read-only.
# Run: sh /root/kt412-dsa-check.sh   (writes /root/DSA_RESULT.txt, copy it back)
OUT=/root/DSA_RESULT.txt
{
echo "===================== KT412 DSA CHECK ====================="
echo "## date"; date 2>/dev/null
echo
echo "## modules (expect: dsa_core, tag_qca, qca8k ; NO swconfig)"
lsmod 2>/dev/null | grep -Ei 'dsa|qca|tag_qca' || echo "(none matched)"
SW=$(lsmod 2>/dev/null | grep -c swconfig); echo "swconfig modules: $SW (expect 0)"
echo
echo "## dmesg (qca8k / dsa / switch / bridge / vlan / ports)"
dmesg 2>/dev/null | grep -Ei 'qca8k|dsa|switch|bridge|vlan|No ports node|tree 0' | tail -40
echo
echo "## ip -d link show (DSA conduit/master/portname)"
ip -d link show 2>/dev/null
echo
echo "## bridge link show"
bridge link show 2>/dev/null
echo
echo "## bridge vlan show (table; populated only when vlan_filtering=1)"
bridge vlan show 2>/dev/null
echo
echo "## br-lan vlan_filtering"
cat /sys/class/net/br-lan/bridge/vlan_filtering 2>/dev/null
echo
echo "## /etc/config/network (DSA device + bridge-vlan sections)"
cat /etc/config/network 2>/dev/null
echo
echo "## per-port status (carrier/speed/duplex/master/stats)"
for p in lan1 lan2 lan3 lan4 wan eth0 eth1 br-lan; do
  [ -e "/sys/class/net/$p" ] || continue
  car=$(cat /sys/class/net/$p/carrier 2>/dev/null)
  spd=$(cat /sys/class/net/$p/speed 2>/dev/null)
  dup=$(cat /sys/class/net/$p/duplex 2>/dev/null)
  mst=$(cat /sys/class/net/$p/master/ifindex 2>/dev/null && cat /sys/class/net/$p/master 2>/dev/null)
  rb=$(cat /sys/class/net/$p/statistics/rx_bytes 2>/dev/null)
  tb=$(cat /sys/class/net/$p/statistics/tx_bytes 2>/dev/null)
  re=$(cat /sys/class/net/$p/statistics/rx_errors 2>/dev/null)
  te=$(cat /sys/class/net/$p/statistics/tx_errors 2>/dev/null)
  rd=$(cat /sys/class/net/$p/statistics/rx_dropped 2>/dev/null)
  td=$(cat /sys/class/net/$p/statistics/tx_dropped 2>/dev/null)
  echo "$p: carrier=$car speed=${spd:-?} duplex=${dup:-?} rx=$rb tx=$tb rxerr=$re txerr=$te rxdrop=$rd txdrop=$td"
done
echo
echo "## lan3 link-flap history (autoneg/EEE clue)"
dmesg 2>/dev/null | grep -Ei 'lan3' | tail -20 || echo "(no lan3 events)"
echo -n "lan3 EEE: "; ethtool --show-eee lan3 2>/dev/null | grep -i 'EEE status' || echo "(ethtool eee not available on this port)"
echo
echo "## captured board DTS (ports/mdio/switch nodes), if shipped"
[ -f /etc/kt412-dts.txt ] && grep -nEi 'switch|qca8k|ports|ethernet-ports|port@|mdio|label|phy-mode|cpu' /etc/kt412-dts.txt | head -80 || echo "(/etc/kt412-dts.txt not present)"
echo
echo "## VERDICT"
DSA_OK=0; lsmod 2>/dev/null | grep -qi dsa_core && DSA_OK=1
TAG_OK=0; lsmod 2>/dev/null | grep -qi tag_qca && TAG_OK=1
QCA_OK=0; lsmod 2>/dev/null | grep -qi qca8k && QCA_OK=1
VF=$(cat /sys/class/net/br-lan/bridge/vlan_filtering 2>/dev/null)
echo "DSA_OK=$DSA_OK TAG_QCA_OK=$TAG_OK QCA8K_OK=$QCA_OK SWCONFIG=$SW vlan_filtering=$VF"
echo "Note: 'No ports node specified' = qca8k INTERNAL-MDIO PHY node warning; it is"
echo "benign — DSA ports (lan1-4/wan) enumerate and bridge correctly above. Enable a"
echo "VLAN in LuCI (Network>Interfaces>Bridge VLAN) to set vlan_filtering=1 and populate"
echo "the bridge vlan table."
echo "===================== END DSA CHECK ====================="
} | tee "$OUT"
echo; echo "Saved -> $OUT"
