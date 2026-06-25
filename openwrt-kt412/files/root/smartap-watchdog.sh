#!/bin/sh
# Smart AP self-heal watchdog. Runs every 2 min from cron. Soft-recovers a wedged
# WiFi radio (ath10k goes WEDGED after 4 failed self-restarts) and a stuck DSA
# LAN/WAN port WITHOUT rebooting. The hardware watchdog (procd, 30s) is the only
# thing allowed to reboot — and only on a true kernel hang, not soft WiFi issues.
ST=/tmp/smartap-wd; mkdir -p "$ST"
log(){ logger -t smartap-wd "$1"; }

# ---------- 1) Per-radio WiFi health + soft recovery ----------
for r in $(uci show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.=]*\)=wifi-device/\1/p'); do
	[ "$(uci -q get wireless.$r.disabled)" = "1" ] && { rm -f "$ST/fail_$r"; continue; }
	idx="$(printf '%s' "$r" | tr -cd '0-9')"
	ifc="$(iwinfo 2>/dev/null | sed -n 's/^\([A-Za-z0-9._-]*\) *ESSID:.*/\1/p' | sed -n "$((idx+1))p")"
	[ -n "$ifc" ] || ifc="phy${idx}-ap0"
	bad=0
	# a) PHY gone / interface command errors = wedged
	iw dev "$ifc" info >/dev/null 2>&1 || bad=1
	# b) configured (non-auto) channel but the iface reports none = silent drop-off (DFS/5G wedge)
	cch="$(uci -q get wireless.$r.channel)"
	if [ "$bad" = "0" ] && [ -n "$cch" ] && [ "$cch" != "auto" ]; then
		ach="$(iw dev "$ifc" info 2>/dev/null | awk '/channel/{print $2; exit}')"
		[ -z "$ach" ] && bad=1
	fi
	fcf="$ST/fail_$r"
	if [ "$bad" = "1" ]; then
		n=$(( $(cat "$fcf" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$fcf"
		log "radio $r ($ifc) wedged (strike $n) -> soft recover"
		if   [ "$n" -le 1 ]; then wifi down "$r" 2>/dev/null; sleep 2; wifi up "$r" 2>/dev/null
		elif [ "$n" -le 2 ]; then wifi reload 2>/dev/null
		else
			# full driver reload clears a WEDGED ath10k PCIe state (still NOT a reboot)
			case "$(uci -q get wireless.$r.band)" in
				5g) rmmod ath10k_pci 2>/dev/null; rmmod ath10k_core 2>/dev/null; sleep 2
				    modprobe ath10k_core 2>/dev/null; modprobe ath10k_pci 2>/dev/null;;
				*)  rmmod ath9k 2>/dev/null; sleep 2; modprobe ath9k 2>/dev/null;;
			esac
			sleep 3; wifi up "$r" 2>/dev/null; echo 0 > "$fcf"
		fi
	else
		rm -f "$fcf"
	fi
done

# ---------- 2) DSA LAN/WAN port health (carrier up but frozen -> bounce that port) ----------
for p in lan1 lan2 lan3 lan4 wan eth0 eth1; do
	[ -e "/sys/class/net/$p" ] || continue
	[ "$(cat /sys/class/net/$p/carrier 2>/dev/null)" = "1" ] || { rm -f "$ST/po_$p" "$ST/pf_$p"; continue; }
	rx="$(cat /sys/class/net/$p/statistics/rx_bytes 2>/dev/null)"; tx="$(cat /sys/class/net/$p/statistics/tx_bytes 2>/dev/null)"
	prev="$(cat "$ST/po_$p" 2>/dev/null)"; echo "$rx $tx" > "$ST/po_$p"
	[ -n "$prev" ] || continue
	set -- $prev
	if [ "$rx" = "$1" ] && [ "$tx" = "$2" ]; then
		n=$(( $(cat "$ST/pf_$p" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$ST/pf_$p"
		if [ "$n" -ge 3 ]; then           # ~6 min: carrier up, zero traffic both ways
			log "port $p frozen -> bounce link"
			ip link set "$p" down 2>/dev/null; sleep 1; ip link set "$p" up 2>/dev/null
			rm -f "$ST/pf_$p"
		fi
	else
		rm -f "$ST/pf_$p"
	fi
done

# ---------- 3) conntrack near full -> drop UDP entries (safe, keeps TCP sessions) ----------
cmax="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 16384)"
ccnt="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
[ "$ccnt" -gt $(( cmax * 90 / 100 )) ] 2>/dev/null && { conntrack -D -p udp >/dev/null 2>&1; log "conntrack ${ccnt}/${cmax} -> flushed udp"; }

# ---------- 4) low memory -> drop pagecache only (safe) ----------
ma="$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)"
[ -n "$ma" ] && [ "$ma" -lt 8000 ] 2>/dev/null && { sync; echo 1 > /proc/sys/vm/drop_caches 2>/dev/null; log "low mem ${ma}kB -> dropped caches"; }

# ---------- 5) critical services alive ----------
for s in dnsmasq uhttpd rpcd network; do
	pgrep -f "$s" >/dev/null 2>&1 || /etc/init.d/"$s" restart >/dev/null 2>&1
done
exit 0
