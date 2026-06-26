#!/bin/sh
# kt412-watchcat.sh -- ping-based internet watchdog (WatchCat-style).
#
# Run from cron (default every 5 min, set up by 43-kt412-maint). It pings a set
# of well-known hosts; if NONE answer for >= FAIL_MINUTES consecutive minutes it
# takes a recovery ACTION:
#   ACTION=ifdown  -> restart the WAN interface (ifup wan) -- soft recovery
#   ACTION=reboot  -> reboot the whole device              -- hard recovery
# The "down since" timestamp is persisted in /tmp so consecutive cron runs build
# up the elapsed-down time without a long-running daemon.
#
# POSIX sh. Safe to run repeatedly. Does nothing while internet is up.
#
# Tunables (env or edit here):
FAIL_MINUTES="${FAIL_MINUTES:-10}"     # minutes of continuous loss before acting
ACTION="${ACTION:-ifdown}"             # ifdown | reboot
HOSTS="${HOSTS:-1.1.1.1 8.8.8.8 9.9.9.9}"
WANIF="${WANIF:-wan}"

STATE=/tmp/kt412-watchcat.down         # holds epoch seconds of first failure
PINGCNT=2
PINGTO=3

online() {
	for h in $HOSTS; do
		if ping -q -c "$PINGCNT" -W "$PINGTO" "$h" >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

now="$(date +%s 2>/dev/null)"; [ -n "$now" ] || now=0

if online; then
	# internet is up: clear any pending down-state and exit
	rm -f "$STATE"
	exit 0
fi

# internet is down -- record / read the first-failure timestamp
if [ -f "$STATE" ]; then
	first="$(cat "$STATE" 2>/dev/null)"
	case "$first" in ''|*[!0-9]*) first="$now";; esac
else
	first="$now"
	echo "$first" > "$STATE"
fi

elapsed=$(( now - first ))
need=$(( FAIL_MINUTES * 60 ))

if [ "$elapsed" -ge "$need" ]; then
	logger -t kt412-watchcat "internet down for ${elapsed}s (>= ${need}s) -> action=${ACTION}"
	rm -f "$STATE"
	case "$ACTION" in
		reboot)
			reboot
			;;
		*)
			# soft recovery: bounce WAN; if PPPoE it re-dials
			ifup "$WANIF" >/dev/null 2>&1
			# also kick wifi station uplinks if any (harmless on pure AP)
			wifi up >/dev/null 2>&1
			;;
	esac
fi

exit 0
