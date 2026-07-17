#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/files/usr/libexec/cr6608-vlan-lib"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-vlan-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/sys/lan1" "$TMP/sys/lan2" "$TMP/sys/lan3"
LOG="$TMP/uci.log"
COUNT="$TMP/count"
printf '0\n' >"$COUNT"

scenario=auto

uci() {
	quiet=0
	if [ "${1:-}" = "-q" ]; then quiet=1; shift; fi
	cmd="${1:-}"; shift || true
	case "$cmd:$*" in
		show:network)
			printf "%s\n" "network.@device[0]=device" "network.@device[0].name='br-lan'"
			;;
		get:network.@device\[0\]) echo device ;;
		get:smartap.lan*.vlan_mode)
			port="${1#smartap.}"; port="${port%.vlan_mode}"
			case "$scenario" in
				auto) echo auto ;;
				plain) echo plain ;;
				mixed) [ "$port" = lan1 ] && echo trunk || echo access ;;
				disabledtrunk) [ "$port" = lan1 ] && echo trunk || echo plain ;;
				orphan) [ "$port" = lan1 ] && echo trunk || echo access ;;
			esac
			;;
		get:smartap.lan*.vlan)
			case "$scenario" in
				mixed) [ "$1" = smartap.lan1.vlan ] && echo 1 || echo 50 ;;
				disabledtrunk) [ "$1" = smartap.lan1.vlan ] && echo 50 || echo 1 ;;
				orphan) [ "$1" = smartap.lan1.vlan ] && echo 50 || echo 60 ;;
				*) echo 1 ;;
			esac
			;;
		get:smartap.lan*.enabled)
			port="${1#smartap.}"; port="${port%.enabled}"
			if [ "$scenario" = disabledtrunk ] && [ "$port" = lan1 ]; then echo 0; else echo 1; fi
			;;
		get:network.recovery|get:network.@device\[0\].vlan_filtering) return 1 ;;
		add:network\ bridge-vlan)
			n="$(sed -n '1p' "$COUNT")"; n=$((n + 1)); printf '%s\n' "$n" >"$COUNT"; printf 'v%s\n' "$n"
			;;
		set:*|add_list:*|delete:*) printf '%s %s\n' "$cmd" "$*" >>"$LOG" ;;
		*) [ "$quiet" = 1 ] && return 1; echo "unexpected uci call: $cmd $*" >&2; return 1 ;;
	esac
}

. "$LIB"
SYS_CLASS_NET="$TMP/sys"

: >"$LOG"
scenario=auto
cr6608_apply_port_vlans 50 0
for port in lan1 lan2 lan3; do
	grep -Fq "ports=$port:t" "$LOG" || { echo "missing automatic trunk for $port" >&2; exit 1; }
done

: >"$LOG"
scenario=plain
if cr6608_apply_port_vlans 50 0; then
	echo "quick VLAN without a trunk was accepted" >&2
	exit 1
else
	[ "$?" -eq 3 ] || { echo "wrong no-trunk error" >&2; exit 1; }
fi
! grep -Fq 'vlan_filtering=1' "$LOG" || { echo "invalid VLAN was staged" >&2; exit 1; }

: >"$LOG"
scenario=auto
cr6608_apply_port_vlans '' 0
grep -Fq "network.lan.device=br-lan" "$LOG" || { echo "plain bridge was not restored" >&2; exit 1; }
! grep -Fq ':t' "$LOG" || { echo "plain AP unexpectedly created a trunk" >&2; exit 1; }

: >"$LOG"
scenario=mixed
cr6608_apply_port_vlans 50 0
grep -Fq 'ports=lan1:t' "$LOG" || { echo "explicit trunk was not retained" >&2; exit 1; }
grep -Fq 'ports=lan2:u*' "$LOG" || { echo "access port was not retained" >&2; exit 1; }

: >"$LOG"
scenario=disabledtrunk
if cr6608_apply_port_vlans 50 0; then
	echo "disabled trunk was accepted as the quick VLAN uplink" >&2
	exit 1
else
	[ "$?" -eq 3 ] || { echo "wrong disabled-trunk error" >&2; exit 1; }
fi
! grep -Fq 'vlan_filtering=1' "$LOG" || { echo "disabled-trunk VLAN was staged" >&2; exit 1; }

: >"$LOG"
scenario=orphan
if cr6608_apply_port_vlans 50 0; then
	echo "access VLAN without a matching tagged uplink was accepted" >&2
	exit 1
else
	[ "$?" -eq 3 ] || { echo "wrong orphan-access error" >&2; exit 1; }
fi
! grep -Fq 'vlan_filtering=1' "$LOG" || { echo "orphan access VLAN was staged" >&2; exit 1; }

echo "vlan_lib_tests=pass"
