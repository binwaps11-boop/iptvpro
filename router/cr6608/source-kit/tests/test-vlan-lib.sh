#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
LIB="${VLAN_LIB:-$ROOT/files/usr/libexec/cr6608-vlan-lib}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-vlan-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/sys/lan1" "$TMP/sys/lan2" "$TMP/sys/lan3"
LOG="$TMP/uci.log"
COUNT="$TMP/count"
STALE_STATE="$TMP/stale-state"
OTHER_WAN_STATE="$TMP/other-wan-state"
printf '0\n' >"$COUNT"

scenario=auto

expect_invalid_unchanged() {
	label="$1"
	shift
	: >"$LOG"
	touch "$STALE_STATE"
	touch "$OTHER_WAN_STATE"
	count_before="$(sed -n '1p' "$COUNT")"
	if "$@"; then
		echo "$label was accepted" >&2
		exit 1
	else
		[ "$?" -eq 3 ] || { echo "wrong $label error" >&2; exit 1; }
	fi
	[ -e "$STALE_STATE" ] || {
		echo "$label deleted the existing bridge-vlan before validation" >&2
		exit 1
	}
	[ -e "$OTHER_WAN_STATE" ] || {
		echo "$label stripped WAN from a bridge-vlan owned by another bridge" >&2
		exit 1
	}
	[ "$(sed -n '1p' "$COUNT")" = "$count_before" ] || {
		echo "$label added an anonymous UCI section before validation" >&2
		exit 1
	}
	[ ! -s "$LOG" ] || {
		echo "$label left a staged UCI delta before validation:" >&2
		cat "$LOG" >&2
		exit 1
	}
}

uci() {
	quiet=0
	if [ "${1:-}" = "-q" ]; then quiet=1; shift; fi
	cmd="${1:-}"; shift || true
	case "$cmd:$*" in
		show:network)
			printf "%s\n" "network.@device[0]=device" "network.@device[0].name='br-lan'"
			if [ -f "$STALE_STATE" ]; then
				printf "%s\n" \
					"network.@bridge-vlan[0]=bridge-vlan" \
					"network.@bridge-vlan[0].device='br-lan'" \
					"network.@bridge-vlan[0].name='Legacy-LuCI-VLAN'"
			fi
			if [ -f "$STALE_STATE" ]; then other_index=1; else other_index=0; fi
			printf "%s\n" \
				"network.@bridge-vlan[$other_index]=bridge-vlan" \
				"network.@bridge-vlan[$other_index].device='br-other'"
			;;
		get:network.@device\[0\]) echo device ;;
		get:network.@bridge-vlan\[0\].device)
			if [ -f "$STALE_STATE" ]; then echo br-lan; else echo br-other; fi
			;;
		get:network.@bridge-vlan\[1\].device) [ -f "$STALE_STATE" ] && echo br-other || return 1 ;;
		get:network.@bridge-vlan\[0\].ports)
			if [ -f "$STALE_STATE" ]; then
				echo 'lan1:u*'
			elif [ -f "$OTHER_WAN_STATE" ]; then
				echo 'wan:t lan2:u*'
			else
				echo 'lan2:u*'
			fi
			;;
		get:network.@bridge-vlan\[1\].ports)
			[ -f "$STALE_STATE" ] || return 1
			[ -f "$OTHER_WAN_STATE" ] && echo 'wan:t lan2:u*' || echo 'lan2:u*'
			;;
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
			n="$(sed -n '1p' "$COUNT")"; n=$((n + 1)); printf '%s\n' "$n" >"$COUNT"
			printf '%s %s\n' "$cmd" "$*" >>"$LOG"
			printf 'v%s\n' "$n"
			;;
		delete:network.@bridge-vlan\[0\])
			rm -f "$STALE_STATE"
			printf '%s %s\n' "$cmd" "$*" >>"$LOG"
			;;
		del_list:network.@bridge-vlan\[0\].ports=wan:t|del_list:network.@bridge-vlan\[1\].ports=wan:t)
			rm -f "$OTHER_WAN_STATE"
			printf '%s %s\n' "$cmd" "$*" >>"$LOG"
			;;
		set:*|add_list:*|delete:*) printf '%s %s\n' "$cmd" "$*" >>"$LOG" ;;
		*) [ "$quiet" = 1 ] && return 1; echo "unexpected uci call: $cmd $*" >&2; return 1 ;;
	esac
}

. "$LIB"
SYS_CLASS_NET="$TMP/sys"

: >"$LOG"
touch "$STALE_STATE"
touch "$OTHER_WAN_STATE"
cr6608_clear_port_vlans
! grep -Fq 'delete network.@bridge-vlan[0]' "$LOG" ||
	{ echo "normal cleanup removed a LuCI-owned br-lan VLAN" >&2; exit 1; }
! grep -Fq 'delete network.@bridge-vlan[1]' "$LOG" ||
	{ echo "bridge-vlan owned by another bridge was removed" >&2; exit 1; }
[ -e "$STALE_STATE" ] ||
	{ echo "normal cleanup did not preserve the LuCI-owned br-lan VLAN" >&2; exit 1; }
[ -e "$OTHER_WAN_STATE" ] ||
	{ echo "WAN was stripped from a bridge-vlan owned by another bridge" >&2; exit 1; }
! grep -Fq 'del_list network.@bridge-vlan' "$LOG" ||
	{ echo "cleanup staged a WAN removal on another bridge" >&2; exit 1; }

: >"$LOG"
cr6608_clear_port_vlans 1
grep -Fq 'delete network.@bridge-vlan[0]' "$LOG" ||
	{ echo "explicit takeover did not remove the external br-lan VLAN" >&2; exit 1; }
[ ! -e "$STALE_STATE" ] ||
	{ echo "explicit takeover did not converge" >&2; exit 1; }

: >"$LOG"
touch "$OTHER_WAN_STATE"
scenario=auto
cr6608_apply_port_vlans 50 0
for port in lan1 lan2 lan3; do
	grep -Fq "ports=$port:t" "$LOG" || { echo "missing automatic trunk for $port" >&2; exit 1; }
done
[ -e "$OTHER_WAN_STATE" ] ||
	{ echo "valid apply stripped WAN from another bridge-vlan" >&2; exit 1; }
! grep -Fq 'del_list network.@bridge-vlan' "$LOG" ||
	{ echo "valid apply staged WAN removal on another bridge" >&2; exit 1; }

: >"$LOG"
touch "$STALE_STATE"
count_before="$(sed -n '1p' "$COUNT")"
if cr6608_apply_port_vlans 50 0; then
	echo "unmanaged br-lan VLAN conflict was accepted" >&2
	exit 1
else
	[ "$?" -eq 4 ] || { echo "wrong unmanaged VLAN conflict error" >&2; exit 1; }
fi
[ -e "$STALE_STATE" ] || { echo "conflict path deleted the LuCI-owned VLAN" >&2; exit 1; }
[ "$(sed -n '1p' "$COUNT")" = "$count_before" ] || { echo "conflict path added a VLAN section" >&2; exit 1; }
: >"$LOG"
rm -f "$STALE_STATE"

scenario=plain
expect_invalid_unchanged no-trunk cr6608_apply_port_vlans 50 0
rm -f "$STALE_STATE"

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

scenario=disabledtrunk
expect_invalid_unchanged disabled-trunk cr6608_apply_port_vlans 50 0

scenario=orphan
expect_invalid_unchanged orphan-access cr6608_apply_port_vlans 50 0

echo "vlan_lib_tests=pass"
