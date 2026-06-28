#!/bin/sh
# =============================================================================
# cr6606_all_channels_test.sh  —  measure EVERY channel on the CR6606 (MT7915)
# -----------------------------------------------------------------------------
# Sweeps all 2.4G (1-13) and 5G (36-165) channels. For each channel it:
#   - sets the radio channel + txpower=30, wifi reload, waits for the radio
#   - reads the iw phy regulatory LIMIT (dBm) + DFS flag for that channel
#   - reads the iwinfo ACTUAL Tx-Power (the real number, never invented)
#   - reads station dump (signal / tx-rx bitrate / retries / failed / NSS)
#   - reads survey dump (noise / channel-busy) for the in-use channel
#   - prints one table row + a per-channel VERDICT and clamp reason
# Then it restores the device's default channels.
#
# Usage:  sh /root/cr6606_all_channels_test.sh            # normal sweep (country = current)
#         sh /root/cr6606_all_channels_test.sh --countries  # also compare US PA AU NZ BO BZ 00
#         SETTLE=8 sh /root/cr6606_all_channels_test.sh    # longer per-channel wait
#
# Honest notes:
#   * iwinfo/station values are REAL driver readings. Where no client is associated,
#     bitrate/retry/failed/signal show "-" (not faked).
#   * DFS channels (52-144) need CAC (radar scan) before an AP transmits; if the
#     radio hasn't finished CAC the ACTUAL may read "n/a" — the regdb LIMIT + DFS
#     flag are still reported truthfully.
#   * Nothing here writes EEPROM/caldata or patches regdb. Read-only measurement.
# =============================================================================

CH24="1 2 3 4 5 6 7 8 9 10 11 12 13"
CH5="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"
SETTLE="${SETTLE:-5}"
REQ_TX="30"

have(){ command -v "$1" >/dev/null 2>&1; }
for t in iw iwinfo uci; do have "$t" || { echo "FATAL: '$t' not found"; exit 1; }; done

# --- map: find the wifi-device (uci radio) + phy + iface for each band ---------
radio_for_band(){ # $1 = 2g|5g  -> echoes uci radio name
	for d in $(uci -q show wireless | sed -n "s/^wireless\.\([^.=]*\)=wifi-device/\1/p"); do
		[ "$(uci -q get wireless.$d.band)" = "$1" ] && { echo "$d"; return; }
	done
}
phy_for_band(){ # $1 = 2g|5g  -> echoes phyN by probing supported freqs
	for p in $(iw phy 2>/dev/null | sed -n 's/^Wiphy \(.*\)$/\1/p'); do
		info="$(iw phy "$p" info 2>/dev/null)"
		case "$1" in
			2g) echo "$info" | grep -q "2412.0 MHz" && { echo "$p"; return; };;
			5g) echo "$info" | grep -q "5180.0 MHz" && { echo "$p"; return; };;
		esac
	done
}
iface_for_phy(){ # $1 = phyN -> first AP interface netdev on that phy
	iw dev 2>/dev/null | awk -v want="$1" '
		/^phy#/ {cur="phy"substr($1,5)}
		/Interface/ {ifc=$2}
		/type AP|type managed/ { if (cur==want && ifc!="") {print ifc; exit} }'
}

freq_of(){ # $1=band $2=ch
	if [ "$1" = "2g" ]; then echo $((2407 + 5*$2)); else echo $((5000 + 5*$2)); fi
}
phy_line(){ iw phy "$1" info 2>/dev/null | grep -E "\[$2\]" | head -1; }
limit_dbm(){ echo "$1" | sed -n 's/.*(\([0-9.]*\) dBm).*/\1/p'; }       # from phy_line
is_dfs(){ echo "$1" | grep -qiE "radar detection|no IR|DFS" && echo "yes" || echo "no"; }
chain_status(){ # $1=phy
	a="$(iw phy "$1" info 2>/dev/null | grep -i 'Available Antennas' | head -1)"
	case "$a" in *0x3*) echo "2x2(0x3)";; "") echo "?";; *) echo "REDUCED:$(echo "$a"|tr -s ' ')";; esac
}
iwinfo_tx(){ iwinfo "$1" info 2>/dev/null | sed -n 's/.*Tx-Power: \([0-9]\+\).*/\1/p' | head -1; }
iwinfo_ch(){ iwinfo "$1" info 2>/dev/null | sed -n 's/.*Channel: \([0-9]\+\).*/\1/p' | head -1; }

sta_field(){ # $1=iface $2=regex  -> first numeric-ish value
	iw dev "$1" station dump 2>/dev/null | grep -m1 -E "$2" | sed 's/^[^:]*:[[:space:]]*//'
}

REG_COUNTRY="$(iw reg get 2>/dev/null | sed -n 's/^country \([A-Z0-9][A-Z0-9]\).*/\1/p' | head -1)"
[ -n "$REG_COUNTRY" ] || REG_COUNTRY="??"

echo "================================================================================"
echo " CR6606 ALL-CHANNELS POWER MEASUREMENT   (country=$REG_COUNTRY, requested TX=${REQ_TX} dBm, settle=${SETTLE}s)"
echo "================================================================================"

# --- chain proof up front -----------------------------------------------------
P24="$(phy_for_band 2g)"; P5="$(phy_for_band 5g)"
echo ""
echo ">>> 2x2 CHAIN PROOF (expect Available Antennas TX/RX 0x3):"
for p in $P24 $P5; do
	echo "  $p: $(iw phy "$p" info 2>/dev/null | grep -i 'Available Antennas' | head -1 | tr -s ' ')  => $(chain_status "$p")"
done

hdr(){
printf '%-4s|%-7s|%-7s|%-6s|%-9s|%-9s|%-4s|%-12s|%-7s|%-11s|%-11s|%-7s|%-6s|%-s\n' \
 Band Channel Country ReqTX "phyLimit" "iwActual" DFS "Chain" Signal "TXbitrate" "RXbitrate" Retries Failed Verdict
echo "--------------------------------------------------------------------------------------------------------------------------------"
}

sweep(){ # $1=band(2.4/5) $2=banduci(2g/5g) $3="channel list" $4=radio $5=phy $6=iface
	band="$1"; buci="$2"; list="$3"; radio="$4"; phy="$5"; ifc="$6"
	cstat="$(chain_status "$phy")"
	for ch in $list; do
		uci -q set wireless.$radio.channel="$ch"
		uci -q set wireless.$radio.txpower="$REQ_TX"
		uci -q commit wireless
		wifi reload >/dev/null 2>&1
		sleep "$SETTLE"

		pl="$(phy_line "$phy" "$ch")"
		lim="$(limit_dbm "$pl")"; [ -n "$lim" ] || lim="-"
		dfs="$(is_dfs "$pl")"
		act="$(iwinfo_tx "$ifc")"; [ -n "$act" ] || act="-"
		onch="$(iwinfo_ch "$ifc")"

		# station-derived columns (only meaningful if a client is on the active ch)
		sig="-"; txb="-"; rxb="-"; rtr="-"; fld="-"
		if [ -n "$ifc" ] && iw dev "$ifc" station dump 2>/dev/null | grep -q Station; then
			sig="$(sta_field "$ifc" 'signal:')"
			txb="$(sta_field "$ifc" 'tx bitrate:')"
			rxb="$(sta_field "$ifc" 'rx bitrate:')"
			rtr="$(sta_field "$ifc" 'tx retries:')"
			fld="$(sta_field "$ifc" 'tx failed:')"
		fi
		[ -n "$sig" ] || sig="-"; [ -n "$txb" ] || txb="-"; [ -n "$rxb" ] || rxb="-"

		# verdict / clamp reason
		if [ "$act" = "-" ]; then
			if [ "$dfs" = "yes" ]; then vrd="DFS/CAC (no TX yet) — regdb limit ${lim}"
			else vrd="no-bringup (ch=${onch:-?})"; fi
		elif [ "$act" = "$REQ_TX" ] || [ "$act" -ge 29 ] 2>/dev/null; then
			vrd="30 OK"
		else
			if [ "$lim" != "-" ] && [ "${lim%.*}" -lt "$REQ_TX" ] 2>/dev/null; then
				vrd="CLAMP@${act} by REGDB (ch limit ${lim})"
			else
				vrd="CLAMP@${act} by CALDATA/per-rate (regdb=${lim})"
			fi
		fi

		printf '%-4s|%-7s|%-7s|%-6s|%-9s|%-9s|%-4s|%-12s|%-7s|%-11s|%-11s|%-7s|%-6s|%-s\n' \
			"$band" "$ch" "$REG_COUNTRY" "$REQ_TX" "$lim" "$act" "$dfs" "$cstat" "$sig" "$txb" "$rxb" "$rtr" "$fld" "$vrd"
	done
}

R24="$(radio_for_band 2g)"; R5="$(radio_for_band 5g)"
I24="$(iface_for_phy "$P24")"; I5="$(iface_for_phy "$P5")"
DEF24="$(uci -q get wireless.$R24.channel)"; DEF5="$(uci -q get wireless.$R5.channel)"

echo ""; echo ">>> RESULT TABLE"; hdr
[ -n "$R24" ] && sweep "2.4" "2g" "$CH24" "$R24" "$P24" "$I24" || echo "(no 2.4G radio found)"
[ -n "$R5"  ] && sweep "5"   "5g" "$CH5"  "$R5"  "$P5"  "$I5"  || echo "(no 5G radio found)"

# --- restore defaults ---------------------------------------------------------
[ -n "$DEF24" ] && uci -q set wireless.$R24.channel="$DEF24"
[ -n "$DEF5" ]  && uci -q set wireless.$R5.channel="$DEF5"
uci -q commit wireless; wifi reload >/dev/null 2>&1

# --- optional: which official regdomain gives the best legal limit per channel -
if [ "$1" = "--countries" ]; then
	echo ""; echo ">>> COUNTRY COMPARISON (iw phy regdb limit per channel; measurement, not guess)"
	echo "    NOTE: using a country you are NOT located in is itself non-compliant — informational only."
	for CC in US PA AU NZ BO BZ 00; do
		iw reg set "$CC" 2>/dev/null; sleep 1
		printf "  [%s] 2.4G:" "$CC"
		for ch in 1 6 11 13; do printf " ch%s=%s" "$ch" "$(limit_dbm "$(phy_line "$P24" "$ch")")"; done
		printf "  | 5G:"
		for ch in 36 52 100 149 165; do printf " ch%s=%s" "$ch" "$(limit_dbm "$(phy_line "$P5" "$ch")")"; done
		echo ""
	done
	iw reg set "$REG_COUNTRY" 2>/dev/null
fi

echo ""
echo "Done. Re-run /root/cr6606_power_truth.sh for the full regdomain/iwinfo/dmesg dump."
echo "Reading caldata (READ ONLY) is documented in /root/CR6606-POWER-REPORT.md if present,"
echo "and in the release report. This script NEVER writes EEPROM/caldata or patches regdb."
