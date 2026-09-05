#!/bin/sh
# /root/cr6606-ab-compare.sh
# REAL before/after measurement for CR6606 (mt7915). Decide by NUMBERS, not talk.
#
# Usage (measure from the SAME spot, same client connected):
#   sh /root/cr6606-ab-compare.sh save before     # on OLD firmware/config
#   ... flash/change, reconnect the SAME client ...
#   sh /root/cr6606-ab-compare.sh save after      # on NEW firmware/config
#   sh /root/cr6606-ab-compare.sh report          # prints before<->after table
#   sh /root/cr6606-ab-compare.sh now             # one-shot current table
#   sh /root/cr6606-ab-compare.sh raw             # raw iw/iwinfo/dmesg dump
#
# Metrics per band: Power(dBm) Signal(dBm) TXrate RXrate Retries Failed
#                   ExpThroughput ChannelBusy%
BEFORE=/tmp/cr6606-ab-before.txt
AFTER=/tmp/cr6606-ab-after.txt

iface_band() { iwinfo "$1" info 2>/dev/null | grep -q "5\." && echo 5G || echo 2.4G; }

# capture one CSV line per AP iface: band|pwr|sig|txr|rxr|ret|fail|exp|busy
capture() {
	for w in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
		typ="$(iw dev "$w" info 2>/dev/null | awk '/type/{print $2}')"
		[ "$typ" = "AP" ] || continue
		info="$(iwinfo "$w" info 2>/dev/null)"
		band="$(echo "$info" | grep -q "5\." && echo 5G || echo 2.4G)"
		pwr="$(echo "$info" | sed -n 's/.*Tx-Power: \([0-9]*\) dBm.*/\1/p')"
		# first associated station
		sd="$(iw dev "$w" station dump 2>/dev/null)"
		sig="$(echo "$sd"  | awk '/signal:/&&!/avg/{print $2; exit}')"
		txr="$(echo "$sd"  | awk '/tx bitrate:/{print $3; exit}')"
		rxr="$(echo "$sd"  | awk '/rx bitrate:/{print $3; exit}')"
		ret="$(echo "$sd"  | awk '/tx retries:/{print $3; exit}')"
		fail="$(echo "$sd" | awk '/tx failed:/{print $3; exit}')"
		exp="$(echo "$sd"  | awk '/expected throughput:/{print $3; exit}')"
		# channel busy% from in-use survey
		busy="$(iw dev "$w" survey dump 2>/dev/null | awk '
			/in use/{u=1}
			u&&/channel active time/{a=$4}
			u&&/channel busy time/{b=$4; if(a>0) printf "%.0f", b*100/a; exit}')"
		echo "${band}|${pwr:-?}|${sig:-?}|${txr:-?}|${rxr:-?}|${ret:-0}|${fail:-0}|${exp:-?}|${busy:-?}"
	done
}

print_table() { # $1=file or "-" for live
	echo "Band  | Power | Signal | TXrate    | RXrate    | Retries | Failed | ExpThr   | Busy%"
	echo "------+-------+--------+-----------+-----------+---------+--------+----------+------"
	local src; [ "$1" = "-" ] && src="$(capture)" || src="$(cat "$1" 2>/dev/null)"
	echo "$src" | while IFS='|' read band pwr sig txr rxr ret fail exp busy; do
		[ -z "$band" ] && continue
		printf "%-5s | %-5s | %-6s | %-9s | %-9s | %-7s | %-6s | %-8s | %s\n" \
			"$band" "$pwr" "$sig" "$txr" "$rxr" "$ret" "$fail" "$exp" "$busy"
	done
}

report() {
	echo "================= BEFORE ================="; print_table "$BEFORE"
	echo; echo "================= AFTER  ================="; print_table "$AFTER"
	echo
	echo "Read it like this: if Power went up but Signal/TXrate did NOT improve and"
	echo "Retries/Failed did NOT drop -> the extra dBm is NOT real usable gain."
}

case "$1" in
	save)
		case "$2" in
			before) capture > "$BEFORE"; echo "saved BEFORE:"; print_table "$BEFORE" ;;
			after)  capture > "$AFTER";  echo "saved AFTER:";  print_table "$AFTER"  ;;
			*) echo "usage: $0 save before|after" ;;
		esac ;;
	report) report ;;
	now)    print_table - ;;
	raw)
		echo "===== iwinfo ====="; iwinfo
		echo "===== iw phy ====="; iw phy
		echo "===== wlan0 station dump ====="; iw dev wlan0 station dump 2>/dev/null
		echo "===== wlan1 station dump ====="; iw dev wlan1 station dump 2>/dev/null
		echo "===== wlan0 survey dump ====="; iw dev wlan0 survey dump 2>/dev/null
		echo "===== wlan1 survey dump ====="; iw dev wlan1 survey dump 2>/dev/null
		echo "===== dmesg (rf/power) ====="
		dmesg | grep -Ei "CR6606|mt76|mt7915|eeprom|cal|power|txpower|thermal|chain" ;;
	*) echo "usage: $0 {save before|save after|report|now|raw}"; print_table - ;;
esac
