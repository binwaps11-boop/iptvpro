#!/bin/sh
# KT412-ANTENNAS — pin the 2.4G ath9k radio to TX/RX chainmask 0x3 (full 2x2,
# both chains). ath9k already defaults to all available chains (0x3), so this is
# belt-and-suspenders + a visible marker. It writes ONLY to debugfs at runtime —
# it NEVER touches ART / EEPROM / caldata / mtd10 and never changes the MAC.
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
done_any=0
for d in /sys/kernel/debug/ieee80211/phy*/ath9k; do
	[ -d "$d" ] || continue
	echo 3 > "$d/tx_chainmask" 2>/dev/null || true
	echo 3 > "$d/rx_chainmask" 2>/dev/null || true
	phy="$(basename "$(dirname "$d")")"
	tx="$(cat "$d/tx_chainmask" 2>/dev/null)"; rx="$(cat "$d/rx_chainmask" 2>/dev/null)"
	logger -t kt412 "KT412-ANTENNAS $phy pinned 2x2 (tx_chainmask=$tx rx_chainmask=$rx)"
	done_any=1
done
[ "$done_any" = 1 ] || logger -t kt412 "KT412-ANTENNAS: no ath9k debugfs found (driver default 0x3 still applies)"
exit 0
