#!/bin/sh
# =============================================================================
# cr6606_set_region.sh  —  switch the device regulatory domain (country) live
# -----------------------------------------------------------------------------
# Usage:  sh /root/cr6606_set_region.sh <CC>     e.g. US | MO | KR | NZ | PA ...
#         sh /root/cr6606_set_region.sh          (no arg -> show current + guide)
#
# Why: the MT7915/mt76 uses ONE global regdomain for the whole device. Different
# official countries open different 5 GHz channels to 30 dBm. This lets YOU pick:
#   US -> 2.4G=30 (1W) + 5G 30 on ch149-165          (best 2.4G)
#   MO -> 5G 30 on ch100-144(DFS)+149-165 (17 ch)    but 2.4G=23
#   KR -> 5G 30 on ch100-165 (16 ch)                 but 2.4G=20
# ch36-48 (UNII-1) is <=23 in EVERY country (no 30 anywhere).
#
# This is a STANDARD regdomain switch (the same option LuCI exposes) — NOT a
# regdb/caldata patch, NOT a DFS disable (CAC stays active). Choosing a country
# you are not located in is YOUR regulatory responsibility. No fake numbers:
# it prints the REAL iwinfo/iw phy result after applying.
# =============================================================================

CC="$1"

show_now() {
	echo "===== current regdomain ====="
	iw reg get 2>/dev/null | sed -n 's/^\(country .*\)/\1/p' | head -2
	echo "===== current Tx-Power per interface ====="
	for IF in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
		printf "  %-12s " "$IF"; iwinfo "$IF" info 2>/dev/null | grep -i 'Tx-Power' || echo
	done
}

if [ -z "$CC" ]; then
	echo "Usage: sh $0 <CC>    (US | MO | KR | NZ | PA | AU | BO | BZ ...)"
	echo
	echo "  US -> 2.4G=30(1W) + 5G 30 on ch149-165        (best 2.4G)"
	echo "  MO -> 5G 30 on ch100-144(DFS)+149-165 (17ch)  but 2.4G=23"
	echo "  KR -> 5G 30 on ch100-165 (16ch)               but 2.4G=20"
	echo "  ch36-48 is <=23 in every country (no 30 anywhere)."
	echo
	show_now
	exit 0
fi

# normalise to upper case (busybox tr)
CC="$(echo "$CC" | tr '[:lower:]' '[:upper:]')"
echo ">>> setting regdomain + per-radio country to: $CC"

# apply to the kernel reg + every radio, keep the 30 dBm request, keep 2x2
iw reg set "$CC" 2>/dev/null
for dev in $(uci -q show wireless | sed -n "s/^wireless\.\([^.=]*\)=wifi-device/\1/p"); do
	uci -q set wireless.$dev.country="$CC"
	uci -q set wireless.$dev.txpower='30'
	uci -q set wireless.$dev.cell_density='0'
done
uci -q commit wireless
wifi reload >/dev/null 2>&1
sleep 5

echo
echo "===== RESULT after $CC (real driver readings) ====="
show_now
echo
echo "Run  sh /root/cr6606_all_channels_test.sh  for the full per-channel table under $CC."
exit 0
