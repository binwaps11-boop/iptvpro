#!/bin/sh
# verify-wifi-channels.sh — RUN ON THE ROUTER AFTER FLASHING.
# Shows the REAL applied TX-Power per channel (no faked numbers).
#  - txpower is requested at RADIO level (30 dBm) for both 2.4G and 5G.
#  - This script reads the regulatory ceiling per channel (iw list) AND actively
#    tests each non-DFS channel: sets it, reloads wifi, reads iwinfo, records.
#  - It RESTORES your original channels at the end.
#
# WARNING: Wi-Fi briefly drops while testing (each channel ~5s). Run over SSH/LAN
#   cable, not over Wi-Fi. Usage:  sh /root/verify-wifi-channels.sh | tee /tmp/chan-proof.txt
#
# DFS channels (52-144) are NOT actively switched (radar CAC = 60s each); their
# legal ceiling is shown from 'iw list' instead.

CH24="1 6 11"
CH5_NODFS="36 44 149 157 165"

radio_band(){ uci -q get wireless.$1.band; }
iface_of(){ # radio0 -> first interface under phy#0
  n=${1#radio}; iw dev | awk -v p="phy#$n" 'index($0,p){f=1;next} f&&/Interface/{print $2; exit}'
}
phy_of(){ echo "phy${1#radio}"; }
cur_pwr(){ iwinfo "$1" info 2>/dev/null | awk -F'[ ]+' '/Tx-Power/{print $4}'; }
cur_ch(){ iwinfo "$1" info 2>/dev/null | awk -F'[ ]+' '/Channel/{print $4}'; }

echo "================= REGULATORY CEILING PER CHANNEL (iw list) ================="
echo "(this is the max the driver will allow per channel = min(US-regdb, caldata))"
for ph in phy0 phy1; do
  echo "--- $ph ---"
  iw phy "$ph" info 2>/dev/null | awk '/MHz \[/{ \
     gsub(/[][()]/,""); printf "  %-6s %-7s %-9s %s\n",$2,$3,$4" "$5, ($0 ~ /radar/?"(DFS)":"") }'
done

echo
echo "================= ACTIVE PER-CHANNEL TEST (real iwinfo) ================="
# figure out which radio is which band
R24=""; R5=""
for r in radio0 radio1; do
  b=$(radio_band "$r"); [ "$b" = "2g" ] && R24="$r"; [ "$b" = "5g" ] && R5="$r"
done
[ -z "$R24" ] && R24="radio0"; [ -z "$R5" ] && R5="radio1"

ORIG24=$(uci -q get wireless.$R24.channel)
ORIG5=$(uci -q get wireless.$R5.channel)
REQ24=$(uci -q get wireless.$R24.txpower)
REQ5=$(uci -q get wireless.$R5.txpower)
echo "requested txpower: 2.4G($R24)=${REQ24:-unset}dBm  5G($R5)=${REQ5:-unset}dBm"
echo

test_band(){ # $1=radio  $2=channels  $3=label
  r="$1"; chans="$2"; lbl="$3"; ph=$(phy_of "$r")
  printf "%-10s %-10s %-12s %-10s %s\n" "[$lbl]" "channel" "requested" "actual" "reached_30?"
  for c in $chans; do
    uci -q set wireless.$r.channel="$c"; uci -q commit wireless
    wifi reload >/dev/null 2>&1; sleep 5
    ifc=$(iface_of "$r")
    act=$(cur_pwr "$ifc"); rc=$(cur_ch "$ifc")
    [ -z "$act" ] && act="?"
    yn="no"; [ "$act" = "30" ] && yn="YES"
    printf "%-10s %-10s %-12s %-10s %s\n" "" "$c (got $rc)" "${REQ:-30} dBm" "${act} dBm" "$yn"
  done
}
REQ="$REQ24"; test_band "$R24" "$CH24" "2.4GHz"
echo
REQ="$REQ5";  test_band "$R5"  "$CH5_NODFS" "5GHz"

# restore
uci -q set wireless.$R24.channel="$ORIG24"
uci -q set wireless.$R5.channel="$ORIG5"
uci -q commit wireless; wifi reload >/dev/null 2>&1; sleep 3
echo
echo "restored channels: 2.4G=$ORIG24  5G=$ORIG5"
echo
echo "================= SUMMARY ================="
echo "* 'actual' column = REAL emitted power reported by the driver (iwinfo)."
echo "* Channels showing 30 = 30 dBm is real there. Channels showing less = that's"
echo "  the true max for that channel on THIS hardware (US-regdb + caldata limit)."
echo "* For best real distance: pick the channel with the highest 'actual' that is"
echo "  also stable (no DFS). Re-check 'logread' for any mt7915 errors afterwards."
echo "DONE — send /tmp/chan-proof.txt"
