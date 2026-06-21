#!/bin/sh
# Health + self-heal. Runs every 5 min via cron. Reboot is LAST resort and OFF by
# default (REBOOT_AFTER=0). Hardware watchdog already covers true hangs.
LOG=/var/log/healthcheck.log
STATE=/tmp/healthcheck.fail
REBOOT_AFTER=0          # 0 = never auto-reboot; set e.g. 6 to reboot after 6 fails
PING_HOST=1.1.1.1

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

fail=0

# 1) memory pressure
free_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
[ "${free_kb:-100000}" -lt 16000 ] && { log "LOW MEM: ${free_kb}kB avail"; fail=1; }

# 2) default route present
if ! ip route | grep -q '^default'; then
  log "NO default route -> restarting wan"; ifup wan 2>/dev/null; fail=1
fi

# 3) WAN reachability (don't fail hard on transient loss)
if ! ping -c2 -W2 "$PING_HOST" >/dev/null 2>&1; then
  log "WAN ping failed"; fail=1
fi

# 4) Wi-Fi interfaces present/up
if ! iwinfo 2>/dev/null | grep -q 'ESSID'; then
  log "No Wi-Fi iface up -> wifi reload"; wifi reload 2>/dev/null; fail=1
fi

# 5) dnsmasq alive
if ! pgrep -x dnsmasq >/dev/null; then
  log "dnsmasq down -> restart"; /etc/init.d/dnsmasq restart 2>/dev/null; fail=1
fi

# 6) thermal note (mt7621 has no active cooling; just log if very hot)
for z in /sys/class/thermal/thermal_zone*/temp; do
  [ -f "$z" ] || continue
  t=$(cat "$z"); [ "$t" -gt 95000 ] && log "HIGH TEMP: $((t/1000))C ($z)"
done

# failure streak handling
if [ "$fail" = 1 ]; then
  n=$(cat "$STATE" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$STATE"
  log "fail streak=$n"
  if [ "$REBOOT_AFTER" -gt 0 ] && [ "$n" -ge "$REBOOT_AFTER" ]; then
    log "REBOOT_AFTER reached -> rebooting"; rm -f "$STATE"; sync; reboot
  fi
else
  rm -f "$STATE"
fi

# keep log small
tail -n 300 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
exit 0
