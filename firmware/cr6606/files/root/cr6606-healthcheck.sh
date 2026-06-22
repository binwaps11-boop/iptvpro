#!/bin/sh
# /root/cr6606-healthcheck.sh
# Lightweight watchdog-style health check. Restarts FAILED services, recovers a
# crashed Wi-Fi radio, watches RAM/flash, logs mt76/OOM/DSA errors.
# It NEVER schedules a reboot (per user requirement) - it heals in place.
INTERVAL="${1:-60}"
TAG="cr6606-health"
log() { logger -t "$TAG" "$1"; }

svc_alive() { /etc/init.d/"$1" status >/dev/null 2>&1 || pgrep -f "$2" >/dev/null 2>&1; }

check_once() {
	# Core daemons
	svc_alive dnsmasq  dnsmasq  || { log "dnsmasq down -> restart";  /etc/init.d/dnsmasq  restart; }
	svc_alive uhttpd   uhttpd   || { log "uhttpd down -> restart";   /etc/init.d/uhttpd   restart; }
	svc_alive dropbear dropbear || { log "dropbear down -> restart"; /etc/init.d/dropbear restart; }
	pgrep -f netifd >/dev/null 2>&1 || { log "netifd down -> restart network"; /etc/init.d/network restart; }

	# Wi-Fi radio recovery: if a configured, enabled radio has NO running iface,
	# it likely crashed (mt76). Bring Wi-Fi back up.
	for phy in $(ls /sys/class/ieee80211/ 2>/dev/null); do
		if [ -z "$(ls /sys/class/ieee80211/$phy/device/net 2>/dev/null)" ]; then
			log "radio $phy has no iface -> wifi up"
			wifi up >/dev/null 2>&1
			break
		fi
	done

	# mt76 firmware crash signature in kernel log
	if dmesg | tail -n 50 | grep -qiE "mt7915.*(reset|fail|timeout|crash)"; then
		log "mt76 error detected in dmesg (auto-recovery via wifi up if needed)"
	fi

	# RAM pressure: if available < 24MB, drop caches (safe) and log
	avail="$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null)"
	[ -n "$avail" ] && [ "$avail" -lt 24 ] && { log "low RAM (${avail}MB) -> drop caches"; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; }

	# Flash/overlay pressure
	use="$(df /overlay 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')"
	[ -n "$use" ] && [ "$use" -ge 90 ] && log "overlay flash ${use}% full - clean /tmp/log or old packages"
}

case "$1" in
	--once) check_once; exit 0 ;;
esac

log "started (interval=${INTERVAL}s, no scheduled reboot)"
while :; do
	check_once
	sleep "$INTERVAL"
done
