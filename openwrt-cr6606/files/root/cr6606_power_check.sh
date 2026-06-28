#!/bin/sh
# =============================================================================
# cr6606_power_check.sh  —  PROVE the real Tx power / chains on the CR6606
# -----------------------------------------------------------------------------
# Run on the router:   sh /root/cr6606_power_check.sh
#
# This reports the ACTUAL, driver-reported values (no guessing, no fake numbers):
#   * iwinfo            -> negotiated Tx-Power per interface (dBm)
#   * iw phy ... info   -> per-channel regulatory Tx-power limits (dBm) + antennas
#   * iw reg get        -> active regulatory domain (where the clamp comes from)
#   * station dump      -> per-client NSS / bitrate => proves 2x2 spatial streams
#   * survey dump       -> in-use channel, noise floor, channel-busy time
#   * dmesg grep        -> driver power/EEPROM/regulatory clamp evidence
#
# If iwinfo shows LESS than 30 dBm, that is NOT a failure and NOT a fake — it is
# the chip's true clean ceiling. The "WHY < 30?" section below tells you exactly
# which limiter (regdb vs EEPROM caldata vs per-rate vs width) is binding.
# =============================================================================

line() { echo "==================================================================="; }
have() { command -v "$1" >/dev/null 2>&1; }

echo
line; echo " CR6606 POWER / CHAIN PROOF — $(date 2>/dev/null)"; line

# --- discover wireless interfaces + their phys ------------------------------
IFACES="$( (iw dev 2>/dev/null | sed -n 's/^[[:space:]]*Interface[[:space:]]\+\(.*\)$/\1/p') )"
[ -n "$IFACES" ] || IFACES="$(ls /sys/class/net 2>/dev/null | grep -E '^(wlan|phy|ra)' )"

echo
echo ">>> Regulatory domain in effect (the legal clamp source):"
if have iw; then iw reg get 2>/dev/null; else echo "  (iw not installed)"; fi

# --- per-interface report ----------------------------------------------------
for IF in $IFACES; do
	line
	echo " INTERFACE: $IF"
	line

	echo
	echo ">>> iwinfo $IF info  (NEGOTIATED Tx-Power = the real number):"
	if have iwinfo; then
		iwinfo "$IF" info 2>/dev/null | grep -iE 'tx-power|channel|mode|bit rate|signal|encryption|ssid' \
			|| iwinfo "$IF" info 2>/dev/null
	else
		echo "  (iwinfo not installed)"
	fi

	# map interface -> phy
	PHY="$(iw dev "$IF" info 2>/dev/null | sed -n 's/^[[:space:]]*wiphy[[:space:]]\+\([0-9]\+\).*/phy\1/p')"
	[ -n "$PHY" ] || PHY="$(basename "$(readlink -f /sys/class/net/$IF/phy80211/device/ieee80211/* 2>/dev/null)" 2>/dev/null)"

	if [ -n "$PHY" ] && have iw; then
		echo
		echo ">>> iw phy $PHY — antenna chains (proves 2x2):"
		iw phy "$PHY" info 2>/dev/null | grep -iE 'antenna' || echo "  (no antenna line)"

		echo
		echo ">>> iw phy $PHY — per-channel Tx-power LIMITS (dBm) for the active band:"
		# show only frequencies that report a power limit (compact)
		iw phy "$PHY" info 2>/dev/null | grep -iE 'MHz \[.*\].*dBm' | grep -v 'disabled' | head -40 \
			|| echo "  (no per-channel dBm lines)"
	fi

	echo
	echo ">>> station dump $IF  (NSS / Rx-Rx bitrate per client = 2x2 in practice):"
	if have iw; then
		out="$(iw dev "$IF" station dump 2>/dev/null)"
		if [ -n "$out" ]; then
			echo "$out" | grep -iE 'Station|signal|tx bitrate|rx bitrate|tx packets|nss|mcs' | head -40
		else
			echo "  (no clients associated — connect a device to see NSS/bitrate)"
		fi
	fi

	echo
	echo ">>> survey dump $IF  (in-use channel, noise floor, busy time):"
	if have iw; then
		iw dev "$IF" survey dump 2>/dev/null | sed -n '/\[in use\]/,/^$/p' | head -20 \
			|| echo "  (survey unavailable)"
	fi
done

# --- driver-level clamp evidence --------------------------------------------
line
echo " DRIVER / EEPROM / REGULATORY CLAMP EVIDENCE (dmesg)"
line
echo
echo ">>> mt7915 / power / eeprom / regulatory lines from the kernel log:"
dmesg 2>/dev/null | grep -iE 'mt7915|mt76|eeprom|cal|tx[_ ]?power|txpower|power limit|regulatory|reg domain|country|EIRP|antenna' \
	| tail -40 || echo "  (no matching dmesg lines)"

# --- interpretation guide ----------------------------------------------------
line
echo " HOW TO READ THIS — WHY Tx-Power MAY BE < 30 dBm (all legitimate)"
line
cat <<'EOF'

The number from `iwinfo ... info` is the TRUE clean Tx power. We requested 30 dBm
(US legal max); the mt76 driver outputs min() of all of these limiters:

  1) Regulatory (regdb / `iw reg get`):
       The country code caps per-channel EIRP. On 5G UNII-3 (ch149/157) US allows
       up to 30 dBm; on 2.4G US allows ~30 dBm. If reg shows a lower cap on your
       channel, that cap wins — change channel (1/6/11, 149/157) to the higher one.

  2) EEPROM / caldata (per-chip factory calibration):
       Xiaomi's factory calibration stores a per-rate power table. mt76 will not
       exceed it (doing so = dirty/clipped TX). This is the usual reason you see
       ~23-27 dBm on some rates even after requesting 30. We do NOT edit caldata,
       so this is the chip's honest ceiling.

  3) Per-rate / per-MCS back-off:
       High HE-MCS (e.g. HE-MCS 11, 1024-QAM) needs more linearity, so the driver
       backs power off on the top rates while keeping low MCS near the cap. The
       per-channel dBm table above shows the regulatory ceiling, not the per-rate
       value.

  4) Channel width:
       Wider channels (HE80) spread the same power over more spectrum, so the
       per-Hz figure differs from HE20. The total conducted dBm is what iwinfo
       reports.

  5) Thermal / DPD:
       If the PA runs hot the driver may trim power. Cooling/airflow restores it.

  6) Chains (this is about EIRP, not the per-chain dBm):
       2x2 means two PA chains. iwinfo reports per-chain conducted power; the two
       chains + antenna gain give the over-the-air EIRP. The station dump NSS=2 and
       the `iw phy` "Available Antennas" mask = 0x3 confirm BOTH chains are active.

Bottom line: 30 in UCI is a REQUEST. The value above is what the chip legally and
cleanly delivers. To raise real coverage further the legitimate levers are: pick
the higher-limit channel (149/157, 1/6/11), keep 2x2 active, and use higher-gain
antennas — NOT editing regdb/caldata (which would be illegal and would distort the
signal).
EOF
echo
exit 0
