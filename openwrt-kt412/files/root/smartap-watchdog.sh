#!/bin/sh
# Smart AP self-heal watchdog. Runs every 2 min from cron. SOFT-recovers a wedged
# WiFi radio (ath10k goes WEDGED after 4 self-restarts) and a stuck DSA LAN/WAN
# port WITHOUT rebooting. The procd HW /dev/watchdog (30s) is the only reboot path.
# Radio<->iface is resolved via ubus (NOT by phy index, which is swapped on this
# board: 2.4G=phy1/radio0, 5G=phy0/radio1) so healthy radios are never bounced.
ST=/tmp/smartap-wd; mkdir -p "$ST"
log(){ logger -t smartap-wd "$1"; }
ifc_of(){ ubus call network.wireless status 2>/dev/null | jsonfilter -e "@.$1.interfaces[0].ifname" 2>/dev/null; }

# Boot grace: WiFi bring-up (especially the ath10k 5G firmware load) takes ~60-90s
# after boot. If the watchdog acts before that, a still-initialising radio looks
# "wedged" (its AP iface doesn't exist yet) and gets bounced (wifi down/up) -> the
# signal appears late or flaps. Skip ALL radio recovery until the device has settled.
UP="$(cut -d. -f1 /proc/uptime 2>/dev/null)"; case "$UP" in ''|*[!0-9]*) UP=999;; esac
# ath10k 5G firmware loads ~35s after boot. Grace must clear that (so we don't
# bounce a still-loading radio) but be short enough to recover a 5G that failed
# "hostapd: Failed to open phy0" reasonably fast on every reboot.
WIFI_GRACE=90

# ---------- 1) Per-radio WiFi health (conservative: only real wedges) ----------
for r in $(uci show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.=]*\)=wifi-device/\1/p'); do
	[ "$(uci -q get wireless.$r.disabled)" = "1" ] && { rm -f "$ST/fail_$r"; continue; }
	# don't touch radios while they're still coming up after boot
	[ "$UP" -lt "$WIFI_GRACE" ] && { rm -f "$ST/fail_$r"; continue; }
	ifc="$(ifc_of "$r")"
	# FALLBACK: ubus 'network.wireless status' can momentarily return an empty
	# ifname during a reconfig, which used to make a perfectly healthy radio look
	# wedged (seen as 'radio radio0 (no-iface) wedged' while phy1-ap0 was UP) and
	# get bounced. If ubus didn't resolve, find a LIVE AP iface for this radio's
	# band via iwinfo before deciding anything.
	if [ -z "$ifc" ] || [ ! -e "/sys/class/net/$ifc" ]; then
		band="$(uci -q get wireless.$r.band)"
		for d in $(iwinfo 2>/dev/null | sed -n 's/^\([A-Za-z0-9._-]*\) *ESSID:.*/\1/p'); do
			b=2g; iwinfo "$d" info 2>/dev/null | grep -qi '5\.[0-9]* GHz' && b=5g
			[ "$b" = "$band" ] && [ -e "/sys/class/net/$d" ] && { ifc="$d"; break; }
		done
	fi
	bad=0
	# wedged = genuinely NO AP iface for this radio (ubus AND iwinfo agree), or its PHY no longer answers
	if [ -z "$ifc" ] || [ ! -e "/sys/class/net/$ifc" ]; then bad=1
	elif ! iw dev "$ifc" info >/dev/null 2>&1; then bad=1; fi
	# Distinguish "PHY entirely MISSING" (driver never registered the radio — e.g.
	# the empty-ART ath9k probe failure) from "merely wedged" (phy present, iface
	# missing). A missing PHY only recovers via a MODULE RELOAD, so for that case we
	# go straight to the reload on strike 1 instead of wasting two strikes (~4 min)
	# on wifi down/up + reload that cannot work without a phy. phy index is
	# board-swapped (2.4G=phy1, 5G=phy0) so we detect by band, not index.
	phy_missing=0
	if [ "$bad" = "1" ]; then
		bandp="$(uci -q get wireless.$r.band)"
		found_phy=0
		for p in /sys/class/ieee80211/phy*; do
			[ -e "$p" ] || continue; idx="${p##*phy}"
			if [ "$bandp" = "5g" ]; then
				iw phy "phy$idx" channels 2>/dev/null | grep -q '5[0-9][0-9][0-9] MHz' && { found_phy=1; break; }
			else
				iw phy "phy$idx" channels 2>/dev/null | grep -q '24[0-9][0-9] MHz' && { found_phy=1; break; }
			fi
		done
		[ "$found_phy" = 0 ] && phy_missing=1
	fi
	fcf="$ST/fail_$r"
	if [ "$bad" = "1" ]; then
		n=$(( $(cat "$fcf" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$fcf"
		do_reload() {
			case "$(uci -q get wireless.$r.band)" in
				5g) rmmod ath10k_pci 2>/dev/null; rmmod ath10k_core 2>/dev/null; sleep 2
				    modprobe ath10k_core 2>/dev/null; modprobe ath10k_pci 2>/dev/null;;
				*)  rmmod ath9k 2>/dev/null; sleep 2; modprobe ath9k 2>/dev/null;;
			esac
			# Apply the EXISTING /etc/config/wireless (configured SSID/HT/encryption).
			# Do NOT `wifi config`: after a module reload the phy can still be mid-
			# registration, and `wifi config` would regenerate the config from detected
			# phys and APPEND a default section -> the radio comes up as the stray
			# "OpenWrt" AP (open, "HT Mode: null") instead of our configured "KT412".
			sleep 3; ubus call network.reload >/dev/null 2>&1; wifi reload 2>/dev/null
			nifc="$(ifc_of "$r")"
			[ -n "$nifc" ] && [ -e "/sys/class/net/$nifc" ] && echo 0 > "$fcf"   # reset only if it came back
		}
		if [ "$phy_missing" = "1" ]; then
			# PHY absent: module reload is the ONLY thing that helps -> do it now.
			log "radio $r (${bandp}) PHY ABSENT (strike $n) -> module reload (fast path)"
			do_reload
		elif [ "$n" -le 1 ]; then
			log "radio $r (${ifc:-no-iface}) wedged (strike $n) -> wifi down/up"
			wifi down "$r" 2>/dev/null; sleep 2; wifi up "$r" 2>/dev/null
		elif [ "$n" -le 2 ]; then
			log "radio $r (${ifc:-no-iface}) wedged (strike $n) -> wifi reload"
			wifi reload 2>/dev/null
		else
			log "radio $r (${ifc:-no-iface}) wedged (strike $n) -> module reload"
			do_reload
		fi
	else
		rm -f "$fcf"
	fi
	# enforce the configured txpower at the DRIVER (firmware can negotiate back down to
	# the calibrated ceiling, so iwinfo/iw phy show 24 even when uci says 30). Re-pin it.
	if [ -n "$ifc" ] && [ -e "/sys/class/net/$ifc" ]; then
		tp="$(uci -q get wireless.$r.txpower)"; phyn="$(cat /sys/class/net/$ifc/phy80211/index 2>/dev/null)"
		[ -n "$tp" ] && [ -n "$phyn" ] && iw phy "phy$phyn" set txpower fixed "$((tp*100))" >/dev/null 2>&1
	fi
done

# ---------- 2) DSA port health: DISABLED (was bouncing idle-but-healthy ports) ----------
# Old logic bounced any carrier-up port with no traffic for ~6 min. But an idle
# connected device (a PC asleep, a TV on standby) legitimately sends zero bytes,
# so this produced false "port frozen -> bounce" events and link flap on lan3.
# Zero traffic is NOT a fault. Port recovery is left to the qca8k driver + the
# kernel hardware watchdog; we never bounce a DSA port on a traffic heuristic.

# ---------- 3) conntrack near full -> drop UDP entries (safe) ----------
cmax="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 16384)"
ccnt="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
[ "$ccnt" -gt $(( cmax * 90 / 100 )) ] 2>/dev/null && { conntrack -D -p udp >/dev/null 2>&1; log "conntrack ${ccnt}/${cmax} -> flushed udp"; }

# ---------- 4) low memory -> drop pagecache only (safe) ----------
ma="$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)"
[ -n "$ma" ] && [ "$ma" -lt 8000 ] 2>/dev/null && { sync; echo 1 > /proc/sys/vm/drop_caches 2>/dev/null; log "low mem ${ma}kB -> dropped caches"; }

# ---------- 5) critical services alive (pidof, not pgrep -f) ----------
for s in dnsmasq uhttpd rpcd netifd; do
	pidof "$s" >/dev/null 2>&1 || { [ "$s" = netifd ] && /etc/init.d/network restart >/dev/null 2>&1 || /etc/init.d/"$s" restart >/dev/null 2>&1; }
done
exit 0
