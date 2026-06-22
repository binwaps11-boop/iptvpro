#!/bin/sh
# /root/verify-wifi-channels.sh
# Proves the REAL achievable Tx-Power per channel on CR6606 (mt7915).
# Shows requested vs actual, which channels reach 30 dBm and which do not,
# the highest real power per channel. NO faked numbers - all from iw/iwinfo.
# Portable: uses sed/grep only (busybox-safe), no gawk extensions.
TARGET=30

echo "######################################################################"
echo "# CR6606 Wi-Fi channel / Tx-Power reality check (target = ${TARGET} dBm)"
echo "# UCI requests txpower 30 ; ACTUAL = min(req, US-regulatory, board-limit)"
echo "######################################################################"
echo "Regulatory domain:"; iw reg get | grep -E "country|DFS" | sed 's/^/  /'

for phy in $(ls /sys/class/ieee80211/ 2>/dev/null); do
	echo
	echo "==================== $phy ===================="

	# Map phy -> running iface to read ACTUAL applied power via iwinfo.
	ifc="$(ls /sys/class/ieee80211/$phy/device/net 2>/dev/null | head -n1)"
	if [ -n "$ifc" ] && [ -d "/sys/class/net/$ifc" ]; then
		info="$(iwinfo "$ifc" info 2>/dev/null)"
		actual_now="$(echo "$info" | sed -n 's/.*Tx-Power: \([0-9]*\) dBm.*/\1/p')"
		chan_now="$(echo "$info" | sed -n 's/.*Channel: \([0-9]*\).*/\1/p')"
		echo "Operating iface: $ifc | channel: ${chan_now:-?} | ACTUAL Tx-Power now (iwinfo): ${actual_now:-not-up} dBm"
		if [ -n "$actual_now" ]; then
			if [ "$actual_now" -ge "$TARGET" ] 2>/dev/null; then
				echo "  -> On the CURRENT channel, 30 dBm IS real (iwinfo confirms ${actual_now})."
			else
				echo "  -> On the CURRENT channel, the highest REAL value is ${actual_now} dBm (< 30; this is the truth)."
			fi
		fi
	else
		echo "Operating iface: (radio not up) - enable Wi-Fi to read live iwinfo txpower"
	fi

	echo
	echo "Per-channel MAX achievable power (regdb + board limits, via 'iw phy info'):"
	printf "  %-6s %-9s %-9s %-7s %s\n" CHAN FREQ MAX_dBm REACH30 FLAGS
	reach=""; noreach=""
	iw phy "$phy" info 2>/dev/null | grep "MHz \[" | while read -r line; do
		freq="$(echo "$line"  | sed -n 's/.*[* ]\([0-9.]*\) MHz.*/\1/p')"
		ch="$(echo "$line"    | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')"
		pw="$(echo "$line"    | sed -n 's/.*(\([0-9.]*\) dBm).*/\1/p')"
		flags=""
		echo "$line" | grep -q "disabled" && { pw="disabled"; flags="disabled"; }
		echo "$line" | grep -q "radar"    && flags="$flags DFS"
		echo "$line" | grep -q "no IR"    && flags="$flags no-IR"
		r="no"
		case "$pw" in
			disabled|"") r="n/a" ;;
			*) [ "${pw%.*}" -ge "$TARGET" ] 2>/dev/null && r="YES" ;;
		esac
		printf "  %-6s %-9s %-9s %-7s %s\n" "${ch:-?}" "${freq:-?}" "$pw" "$r" "$flags"
	done

	echo
	printf "Channels REACHING %s dBm : " "$TARGET"
	iw phy "$phy" info 2>/dev/null | grep "MHz \[" | while read -r line; do
		ch="$(echo "$line" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')"
		pw="$(echo "$line" | sed -n 's/.*(\([0-9.]*\) dBm).*/\1/p')"
		[ -n "$pw" ] && [ "${pw%.*}" -ge "$TARGET" ] 2>/dev/null && printf "%s " "$ch"
	done; echo
	printf "Channels NOT reaching %s dBm : " "$TARGET"
	iw phy "$phy" info 2>/dev/null | grep "MHz \[" | while read -r line; do
		ch="$(echo "$line" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')"
		pw="$(echo "$line" | sed -n 's/.*(\([0-9.]*\) dBm).*/\1/p')"
		[ -n "$pw" ] && [ "${pw%.*}" -lt "$TARGET" ] 2>/dev/null && printf "%s " "$ch"
	done; echo
done

echo
echo "----------------------------------------------------------------------"
echo "RECOMMENDATION (stability + range):"
echo "  2.4GHz: channel 1 / 6 / 11 (20MHz) - best wall penetration & range."
echo "  5GHz  : channel 36 (UNII-1, non-DFS) = instant start, no radar CAC;"
echo "          channel 149 (UNII-3) often allows the highest 5G power."
echo "  DFS channels (52-144) usually show lower power + add a CAC start delay."
echo "----------------------------------------------------------------------"
echo "===== verify-wifi-channels DONE ====="
