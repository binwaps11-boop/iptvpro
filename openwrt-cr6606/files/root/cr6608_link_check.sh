#!/bin/sh
# =============================================================================
# cr6608_link_check.sh — honest per-port Ethernet link diagnostic (CR6608/mt7530)
# -----------------------------------------------------------------------------
# Answers the "why is my port only 100M, not 1G?" question with REAL data:
#   * /sys/class/net/<p>/speed  : -1 = NO cable (link down), else negotiated Mbps
#   * carrier                   : 1 = link up, 0 = down
#   * ethtool <p>               : the port's OWN Supported modes (proves it CAN do
#                                 1000baseT) AND the Link partner advertised modes
#                                 (what the cable/peer offers) — this is the smoking
#                                 gun: if the partner doesn't advertise 1000baseT,
#                                 the limit is the CABLE or the OTHER device, not us.
#   * ethtool --show-eee <p>    : confirms EEE is disabled (our negotiation fix).
# No config is changed — read-only. Run: sh /root/cr6608_link_check.sh
# =============================================================================
PORTS="lan1 lan2 lan3 lan4 wan"
HAS_ETHTOOL=0
command -v ethtool >/dev/null 2>&1 && HAS_ETHTOOL=1

echo "=================================================================="
echo " CR6608 — Ethernet link check ($(date 2>/dev/null))"
echo "=================================================================="
echo " speed: -1 = NO cable connected (link down); else = negotiated Mbps"
echo "------------------------------------------------------------------"

for p in $PORTS; do
	[ -e "/sys/class/net/$p" ] || continue
	sp="$(cat /sys/class/net/$p/speed 2>/dev/null)"
	[ -n "$sp" ] || sp="?"
	car="$(cat /sys/class/net/$p/carrier 2>/dev/null)"
	case "$car" in 1) cars="UP";; 0) cars="down";; *) cars="?";; esac

	if [ "$sp" = "-1" ] || [ "$car" = "0" ]; then
		printf " %-5s : %s\n" "$p" "no cable (link down)"
		continue
	fi

	verdict=""
	case "$sp" in
		1000) verdict="GIGABIT OK";;
		100)  verdict="100M — see partner modes below";;
		10)   verdict="10M — bad cable/peer";;
	esac
	printf " %-5s : %s Mbps  (%s)  %s\n" "$p" "$sp" "$cars" "$verdict"

	if [ "$HAS_ETHTOOL" = "1" ]; then
		# Port capability + what the peer/cable advertises + EEE state.
		ethtool "$p" 2>/dev/null | awk '
			/Supported link modes:/      {print "        port can do : " $0; cap=1; next}
			/Advertised link modes:/     {cap=0}
			/Link partner advertised link modes:/ {print "        peer offers : " $0; lp=1; cap=0; next}
			/Speed:|Duplex:/             {print "        " $0; lp=0; next}
			{ if (cap==1 && /baseT/) print "                    " $1 " " $2;
			  if (lp==1  && /baseT/) print "                    " $1 " " $2 }'
		eee="$(ethtool --show-eee "$p" 2>/dev/null | grep -i 'EEE status' | sed 's/^[[:space:]]*//')"
		[ -n "$eee" ] && printf "        %s\n" "$eee"
	fi
	echo "------------------------------------------------------------------"
done

if [ "$HAS_ETHTOOL" = "0" ]; then
	echo " (install ethtool for partner-mode detail:  opkg update && opkg install ethtool)"
	echo "------------------------------------------------------------------"
fi

cat <<'NOTE'
 How to read this:
   * speed = -1 / "no cable"  -> nothing is plugged into that port.
   * 1000 Mbps                -> gigabit working. Done.
   * 100 Mbps + peer offers NO 1000baseT
        -> the limit is the CABLE or the connected DEVICE, not the router.
           Fix: use an intact Cat5e/Cat6 cable (gigabit needs ALL 4 pairs),
           reseat both ends, or try a known-gigabit device/port.
           No firmware can make a 2-pair / damaged cable run gigabit.
   * 100 Mbps + peer DOES offer 1000baseT but link stays 100
        -> driver-side negotiation issue. EEE is already disabled by this
           firmware (see "EEE status: disabled" above); reboot once and retry.
 The firmware does NOT cap port speed — auto-negotiation always picks the max
 the cable + both ends can do.
NOTE
exit 0
