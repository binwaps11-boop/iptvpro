#!/bin/sh
# /root/wifi-perf.sh - REAL Wi-Fi link quality & per-client throughput (mt7915/mt76).
# Shows signal, tx/rx bitrate, tx retries, tx failed, channel-busy, clients, and
# LIVE per-client download/upload (sampled over 1s). Nothing faked.

sample_bytes() { # $1=iface  -> "mac rx tx" lines
	iw dev "$1" station dump 2>/dev/null | awk '
		/^Station/ {mac=$2}
		/rx bytes:/ {rx=$3}
		/tx bytes:/ {tx=$3; print mac, rx, tx}'
}

for w in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
	typ="$(iw dev "$w" info 2>/dev/null | awk '/type/{print $2}')"
	[ "$typ" = "AP" ] || [ "$typ" = "managed" ] || continue
	echo "============================================================"
	echo "IFACE $w"
	iwinfo "$w" info 2>/dev/null | grep -E "ESSID|Mode|Channel|HT|VHT|HE|Tx-Power|Bit Rate|Signal|Noise" | sed 's/^/  /'

	# NSS / chains proof (2x2 expected on CR6606)
	phy="$(iw dev "$w" info 2>/dev/null | awk '/wiphy/{print "phy"$2}')"
	echo "  --- chains/antennas ($phy) ---"
	iw phy "$phy" info 2>/dev/null | grep -E "Configured Antennas|Available Antennas|TX MCS|max NSS" | sed 's/^/    /'

	# channel busy / survey for the in-use frequency
	echo "  --- survey (in-use channel) ---"
	iw dev "$w" survey dump 2>/dev/null | awk '
		/frequency/ {f=$2; inuse=0}
		/in use/ {inuse=1; print "    freq "f" MHz [in use]"}
		inuse && /(channel active time|channel busy time|channel receive time|channel transmit time|noise):/ {print "      "$0}'

	# per-client: signal/bitrate/retries/failed + live throughput
	echo "  --- clients (live) ---"
	TMP1="/tmp/.wp1.$$"; TMP2="/tmp/.wp2.$$"
	sample_bytes "$w" > "$TMP1"
	# capture static stats now
	iw dev "$w" station dump 2>/dev/null | awk '
		/^Station/ {mac=$2; s[mac]=mac}
		/signal:/ && !/avg/ {sig[mac]=$2}
		/tx bitrate:/ {txr[mac]=$3" "$4}
		/rx bitrate:/ {rxr[mac]=$3" "$4}
		/tx retries:/ {ret[mac]=$3}
		/tx failed:/ {fail[mac]=$3}
		END{for(m in s) printf "%s|%s|%s|%s|%s|%s\n", m, sig[m], txr[m], rxr[m], ret[m], fail[m]}' > /tmp/.wpstat.$$
	sleep 1
	sample_bytes "$w" > "$TMP2"

	if [ ! -s "$TMP1" ]; then
		echo "    (no associated clients)"
	else
		while IFS='|' read -r mac sig txr rxr ret fail; do
			r1=$(awk -v m="$mac" '$1==m{print $2}' "$TMP1"); t1=$(awk -v m="$mac" '$1==m{print $3}' "$TMP1")
			r2=$(awk -v m="$mac" '$1==m{print $2}' "$TMP2"); t2=$(awk -v m="$mac" '$1==m{print $3}' "$TMP2")
			dl=$(( ( ${r2:-0} - ${r1:-0} ) * 8 / 1000 ))   # client download = AP rx, kbps
			ul=$(( ( ${t2:-0} - ${t1:-0} ) * 8 / 1000 ))   # client upload   = AP tx, kbps
			echo "    $mac  signal:${sig:-?}dBm  tx:${txr:-?}  rx:${rxr:-?}  retries:${ret:-0}  failed:${fail:-0}  DL:${dl}kbps UL:${ul}kbps"
		done < /tmp/.wpstat.$$
	fi
	rm -f "$TMP1" "$TMP2" /tmp/.wpstat.$$
done
echo "============================================================"
echo "wifi-perf DONE"
