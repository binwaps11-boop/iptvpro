#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/files/usr/sbin/cr6608-ipv4-only"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ipv4-only.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'ipv4-only runtime failed: %s\n' "$*" >&2; exit 1; }
mkdir -p "$TMP/conf/all" "$TMP/conf/default" "$TMP/conf/lo" "$TMP/conf/eth0" \
	"$TMP/bin" "$TMP/proc/77/fd"
for item in all default lo eth0; do printf '%s\n' 0 > "$TMP/conf/$item/disable_ipv6"; done
printf '%s\n' '  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode' > "$TMP/tcp6"
cp "$TMP/tcp6" "$TMP/udp6"
printf '%s\n' 'ntp:x:123:123:ntp:/var/run/ntp:/bin/false' > "$TMP/passwd"
cat > "$TMP/bin/ip" <<'EOF'
#!/bin/sh
case "$*" in
	'-6 address show')
		[ "${CR6608_TEST_IP_FAIL:-0}" != 1 ] || exit 42
		[ "${CR6608_TEST_INET6:-0}" != 1 ] ||
			printf '%s\n' '    inet6 fe80::1/64 scope link'
		;;
	'-6 route show table all')
		[ "${CR6608_TEST_ROUTE_FAIL:-0}" != 1 ] || exit 43
		[ "${CR6608_TEST_ROUTE:-0}" != 1 ] ||
			printf '%s\n' 'blackhole 2001:db8::/64 dev lo metric 1024'
		;;
	*) exit 44 ;;
esac
EOF
cat > "$TMP/bin/readlink" <<'EOF'
#!/bin/sh
[ "$#" -eq 1 ] || exit 2
[ "$1" = "${CR6608_TEST_NTP_FD:?}" ] || exit 1
printf '%s\n' 'socket:[112646]'
EOF
chmod 0755 "$TMP/bin/ip" "$TMP/bin/readlink"
printf '%s\n' '32768 60999' > "$TMP/port-range"
printf 'Name:\tntpd\nUid:\t123\t123\t123\t123\n' > "$TMP/proc/77/status"
printf '/usr/sbin/ntpd\000-n\000' > "$TMP/proc/77/cmdline"
: > "$TMP/proc/77/fd/4"

export CR6608_IPV6_CONF_ROOT="$TMP/conf"
export CR6608_IPV6_IP_BIN="$TMP/bin/ip"
export CR6608_IPV6_PROC_TCP6="$TMP/tcp6"
export CR6608_IPV6_PROC_UDP6="$TMP/udp6"
export CR6608_IPV6_PASSWD_FILE="$TMP/passwd"
export CR6608_IPV6_PROC_ROOT="$TMP/proc"
export CR6608_IPV6_PORT_RANGE="$TMP/port-range"
export CR6608_IPV6_READLINK_BIN="$TMP/bin/readlink"
export CR6608_TEST_NTP_FD="$TMP/proc/77/fd/4"
export CR6608_IPV6_LISTENER_RETRIES=1

sh "$SCRIPT" apply || fail 'apply rejected a valid fixture'
for item in all default lo eth0; do
	[ "$(cat "$TMP/conf/$item/disable_ipv6")" = 1 ] || fail "$item remained IPv6 enabled"
done
sh "$SCRIPT" --json | grep -Fq '"ipv6_disabled":true' || fail 'JSON verifier did not pass'
if env CR6608_TEST_IP_FAIL=1 sh "$SCRIPT" --json 2>/dev/null; then
	fail 'failed iproute address query passed as empty evidence'
fi
if env CR6608_TEST_INET6=1 sh "$SCRIPT" verify 2>/dev/null; then
	fail 'reported IPv6 address was not rejected'
fi
if env CR6608_TEST_ROUTE_FAIL=1 sh "$SCRIPT" verify 2>/dev/null; then
	fail 'failed iproute route query passed as empty evidence'
fi
if env CR6608_TEST_ROUTE=1 sh "$SCRIPT" verify 2>/dev/null; then
	fail 'reported IPv6 route was not rejected'
fi

printf '%s\n' 0 > "$TMP/conf/eth0/disable_ipv6"
sh "$SCRIPT" interface eth0 || fail 'hotplug interface application failed'
[ "$(cat "$TMP/conf/eth0/disable_ipv6")" = 1 ] || fail 'hotplug did not disable eth0'
if sh "$SCRIPT" interface '../Factory' 2>/dev/null; then fail 'unsafe interface name accepted'; fi

printf '%s\n' '   0: 00000000000000000000000000000000:0035 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 1 1 0000000000000000 100 0 0 10 0' >> "$TMP/udp6"
if sh "$SCRIPT" apply 2>/dev/null; then fail 'IPv6 listener was not rejected'; fi

# A short-lived unknown listener may disappear between samples, while a
# persistent listener must still fail.
(
	sleep 1
	sed -i '$d' "$TMP/udp6"
) &
transient_pid=$!
CR6608_IPV6_LISTENER_RETRIES=3 sh "$SCRIPT" verify ||
	fail 'bounded transient IPv6 client socket was not debounced'
wait "$transient_pid"
printf '%s\n' '   0: 00000000000000000000000000000000:0035 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 1 1 0000000000000000 100 0 0 10 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'persistent IPv6 listener was not rejected'; fi

# BusyBox ntpd keeps one unconnected AF_INET6 wildcard socket for dual-stack
# IPv4 client traffic. Accept only the observed ntp-uid, ephemeral-port shape.
sed -i '$d' "$TMP/udp6"
printf '%s\n' '  47: 00000000000000000000000000000000:E05E 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000 123 0 112646 2 00000000 0' >> "$TMP/udp6"
sh "$SCRIPT" verify || fail 'strict BusyBox ntpd client socket was rejected'
if env CR6608_TEST_NTP_FD="$TMP/proc/77/fd/missing" sh "$SCRIPT" verify 2>/dev/null; then
	fail 'unowned ntpd-shaped inode was accepted'
fi
cp "$TMP/proc/77/cmdline" "$TMP/proc/77/cmdline.good"
printf '/usr/sbin/not-ntpd\000' > "$TMP/proc/77/cmdline"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'wrong socket-owner command was accepted'; fi
mv "$TMP/proc/77/cmdline.good" "$TMP/proc/77/cmdline"
cp "$TMP/proc/77/status" "$TMP/proc/77/status.good"
printf 'Name:\tntpd\nUid:\t124\t124\t124\t124\n' > "$TMP/proc/77/status"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'wrong socket-owner uid was accepted'; fi
mv "$TMP/proc/77/status.good" "$TMP/proc/77/status"
printf '%s\n' '  48: 00000000000000000000000000000000:E05F 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000 123 0 112647 2 00000000 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'two ntpd-shaped sockets were accepted'; fi
sed -i '$d' "$TMP/udp6"
sed -i '$d' "$TMP/udp6"
printf '%s\n' '  47: 00000000000000000000000000000000:007B 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000 123 0 112646 2 00000000 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'NTP server port was accepted'; fi
sed -i '$d' "$TMP/udp6"
printf '%s\n' '  47: 00000000000000000000000000000000:E05E 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000 0 0 112646 2 00000000 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'wrong uid was accepted as ntpd'; fi
sed -i '$d' "$TMP/udp6"
printf '%s\n' '  47: 00000000000000000000000000000000:01BB 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000 123 0 112646 2 00000000 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'low privileged port was accepted as ephemeral'; fi
sed -i '$d' "$TMP/udp6"
printf '%s\n' '  47: 00000000000000000000000000000000:ZZZZ 00000000000000000000000000000000:0000 07 00000000:00000000 00:00000000 00000000 123 0 112646 2 00000000 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'malformed local port was accepted'; fi
sed -i '$d' "$TMP/udp6"
printf '%s\n' '  47: 00000000000000000000000000000000:E05E 00000000000000000000000000000001:0000 07 00000000:00000000 00:00000000 00000000 123 0 112646 2 00000000 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'nonzero IPv6 peer was accepted'; fi
sed -i '$d' "$TMP/udp6"
printf '%s\n' '  47: 00000000000000000000000000000000:E05E 00000000000000000000000000000000:0000 01 00000000:00000000 00:00000000 00000000 123 0 112646 2 00000000 0' >> "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'unexpected UDP6 state was accepted'; fi
sed -i '$d' "$TMP/udp6"

cp "$TMP/udp6" "$TMP/udp6.good"
sed 's/remote_address/rem_address/' "$TMP/udp6.good" > "$TMP/udp6"
sh "$SCRIPT" verify || fail 'standard rem_address udp6 header was rejected'
cp "$TMP/udp6.good" "$TMP/udp6"
printf '%s\n' 'bad header' > "$TMP/udp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'malformed udp6 header was accepted'; fi
mv "$TMP/udp6.good" "$TMP/udp6"
cp "$TMP/tcp6" "$TMP/tcp6.good"
sed 's/remote_address/rem_address/' "$TMP/tcp6.good" > "$TMP/tcp6"
sh "$SCRIPT" verify || fail 'standard rem_address tcp6 header was rejected'
cp "$TMP/tcp6.good" "$TMP/tcp6"
printf '%s\n' 'bad header' > "$TMP/tcp6"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'malformed tcp6 header was accepted'; fi
mv "$TMP/tcp6.good" "$TMP/tcp6"
cp "$TMP/passwd" "$TMP/passwd.good"
printf '%s\n' 'ntp:x:123:123:ntp:/var/run/ntp:/bin/false' >> "$TMP/passwd"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'duplicate ntp identity was accepted'; fi
mv "$TMP/passwd.good" "$TMP/passwd"

# Runtime evidence is mandatory. A missing kernel socket table must not be
# treated as an empty table by either the service verifier or the retail gate.
mv "$TMP/tcp6" "$TMP/tcp6.missing"
if sh "$SCRIPT" --json 2>/dev/null; then fail 'missing tcp6 evidence passed'; fi
mv "$TMP/tcp6.missing" "$TMP/tcp6"
mv "$TMP/udp6" "$TMP/udp6.missing"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'missing udp6 evidence passed'; fi
mv "$TMP/udp6.missing" "$TMP/udp6"
: > "$TMP/tcp6"
if sh "$SCRIPT" --json 2>/dev/null; then fail 'empty tcp6 evidence passed'; fi
printf '%s\n' '  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode' > "$TMP/tcp6"
mv "$TMP/conf/all/disable_ipv6" "$TMP/conf/all/disable_ipv6.missing"
if sh "$SCRIPT" verify 2>/dev/null; then fail 'missing global IPv6 policy passed'; fi
mv "$TMP/conf/all/disable_ipv6.missing" "$TMP/conf/all/disable_ipv6"
mv "$TMP/bin/ip" "$TMP/bin/ip.missing"
if sh "$SCRIPT" --json 2>/dev/null; then fail 'missing iproute verifier passed'; fi
mv "$TMP/bin/ip.missing" "$TMP/bin/ip"

printf '%s\n' 'ipv4_only_runtime=pass'
