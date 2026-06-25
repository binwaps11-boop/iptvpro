#!/bin/sh
# Smart AP self-heal watchdog. Runs every 2 min from cron. SOFT-recovers a wedged
# WiFi radio (ath10k goes WEDGED after 4 self-restarts) and a stuck DSA LAN/WAN
# port WITHOUT rebooting. The procd HW /dev/watchdog (30s) is the only reboot path.
# Radio<->iface is resolved via ubus (NOT by phy index, which is swapped on this
# board: 2.4G=phy1/radio0, 5G=phy0/radio1) so healthy radios are never bounced.
ST=/tmp/smartap-wd; mkdir -p "$ST"
log(){ logger -t smartap-wd "$1"; }
ifc_of(){ ubus call network.wireless status 2>/dev/null | jsonfilter -e "@.$1.interfaces[0].ifname" 2>/dev/null; }

# ---------- 1) Per-radio WiFi health (conservative: only real wedges) ----------
for r in $(uci show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.=]*\)=wifi-device/\1/p'); do
	[ "$(uci -q get wireless.$r.disabled)" = "1" ] && { rm -f "$ST/fail_$r"; continue; }
	ifc="$(ifc_of "$r")"
	bad=0
	# wedged = the AP iface that SHOULD exist is gone, or its PHY no longer answers
	if [ -z "$ifc" ] || [ ! -e "/sys/class/net/$ifc" ]; then bad=1
	elif ! iw dev "$ifc" info >/dev/null 2>&1; then bad=1; fi
	fcf="$ST/fail_$r"
	if [ "$bad" = "1" ]; then
		n=$(( $(cat "$fcf" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$fcf"
		log "radio $r (${ifc:-no-iface}) wedged (strike $n) -> soft recover"
		if   [ "$n" -le 1 ]; then wifi down "$r" 2>/dev/null; sleep 2; wifi up "$r" 2>/dev/null
		elif [ "$n" -le 2 ]; then wifi reload 2>/dev/null
		else
			case "$(uci -q get wireless.$r.band)" in
				5g) rmmod ath10k_pci 2>/dev/null; rmmod ath10k_core 2>/dev/null; sleep 2
				    modprobe ath10k_core 2>/dev/null; modprobe ath10k_pci 2>/dev/null;;
				*)  rmmod ath9k 2>/dev/null; sleep 2; modprobe ath9k 2>/dev/null;;
			esac
			sleep 3; wifi reload 2>/dev/null
			nifc="$(ifc_of "$r")"
			[ -n "$nifc" ] && [ -e "/sys/class/net/$nifc" ] && echo 0 > "$fcf"   # reset only if it came back
		fi
	else
		rm -f "$fcf"
	fi
done

# ---------- 2) DSA LAN/WAN port health (NOT the eth0/eth1 conduit) ----------
for p in lan1 lan2 lan3 lan4 wan; do
	[ -e "/sys/class/net/$p" ] || continue
	[ "$(cat /sys/class/net/$p/carrier 2>/dev/null)" = "1" ] || { rm -f "$ST/po_$p" "$ST/pf_$p"; continue; }
	rx="$(cat /sys/class/net/$p/statistics/rx_bytes 2>/dev/null)"; tx="$(cat /sys/class/net/$p/statistics/tx_bytes 2>/dev/null)"
	prev="$(cat "$ST/po_$p" 2>/dev/null)"; echo "$rx $tx" > "$ST/po_$p"
	[ -n "$prev" ] || continue
	set -- $prev
	if [ "$rx" = "$1" ] && [ "$tx" = "$2" ]; then
		n=$(( $(cat "$ST/pf_$p" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$ST/pf_$p"
		if [ "$n" -ge 3 ]; then           # ~6 min carrier-up but zero traffic both ways
			log "port $p frozen -> bounce link"
			ip link set "$p" down 2>/dev/null; sleep 1; ip link set "$p" up 2>/dev/null
			rm -f "$ST/pf_$p"
		fi
	else
		rm -f "$ST/pf_$p"
	fi
done

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
