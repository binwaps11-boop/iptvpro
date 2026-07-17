#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/usr/sbin/cr6608-safe-apply"

fail() {
	printf 'safe_apply_runtime_test=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "missing $SOURCE"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-safe-apply-runtime.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' 0
trap 'exit 1' HUP INT TERM

BIN="$TMP/bin"
RUNTIME="$TMP/cr6608-safe-apply"
mkdir -p "$BIN" "$TMP/tmp" "$TMP/backups" "$TMP/root/etc/init.d" "$TMP/root/usr/sbin"

# Relocate the few paths without production environment overrides. The restore
# root is also redirected as a second safety barrier behind the failing tar mock.
sed \
	-e 's|/root/dashboard-backups/smartap-\*\.tar\.gz|${CR6608_TEST_BACKUP_ROOT}/smartap-*.tar.gz|' \
	-e 's|/root/cr6608-quicksettings-backups/config-before-\*\.tgz|${CR6608_TEST_BACKUP_ROOT}/config-before-*.tgz|' \
	-e 's|/bin/ipcalc\.sh|ipcalc.sh|g' \
	-e 's|mktemp /tmp/cr6608-safe-members\.XXXXXX|mktemp "${TMPDIR:-/tmp}/cr6608-safe-members.XXXXXX"|' \
	-e 's|tar -xzf "$backup" -C / |tar -xzf "$backup" -C "$CR6608_TEST_ROOT" |' \
	-e 's|/etc/|${CR6608_TEST_ROOT}/etc/|g' \
	-e 's|/usr/sbin/|${CR6608_TEST_ROOT}/usr/sbin/|g' \
	"$SOURCE" >"$RUNTIME"
chmod 0700 "$RUNTIME"

grep -Fq '${CR6608_TEST_BACKUP_ROOT}/smartap-*.tar.gz' "$RUNTIME" ||
	fail "backup path relocation did not apply"
grep -Fq 'ipcalc.sh "$1"' "$RUNTIME" || fail "ipcalc relocation did not apply"
grep -Fq 'tar -xzf "$backup" -C "$CR6608_TEST_ROOT"' "$RUNTIME" ||
	fail "restore root relocation did not apply"

cat >"$BIN/stat" <<'EOF'
#!/bin/sh
[ "$#" -eq 3 ] && [ "$1" = "-c" ] && [ "$2" = "%u" ] || exit 64
printf '0\n'
EOF

cat >"$BIN/hexdump" <<'EOF'
#!/bin/sh
[ "$#" -eq 6 ] || exit 64
[ "$1" = "-v" ] && [ "$2" = "-n" ] && [ "$3" = "16" ] && \
	[ "$4" = "-e" ] && [ "$5" = '1/1 "%02x"' ] && \
	[ "$6" = "/dev/urandom" ] || exit 64
printf '30313233343536373839616263646566'
EOF

cat >"$BIN/tar" <<'EOF'
#!/bin/sh
{
	printf 'tar'
	for arg do printf '|%s' "$arg"; done
	printf '\n'
} >>"$CR6608_TEST_TAR_LOG"
case "${1:-}" in
	-tzf) printf 'etc/config/network\n' ;;
	-xzf) [ -e "$CR6608_TEST_TAR_EXTRACT_OK" ] && exit 0; exit 97 ;;
	*) exit 64 ;;
esac
EOF

cat >"$BIN/ipcalc.sh" <<'EOF'
#!/bin/sh
case "${1:-}|${2:-}" in
	198.51.100.23\|255.255.255.255) printf 'PREFIX=32\n' ;;
	198.51.100.23\|255.255.255.0) printf 'PREFIX=24\n' ;;
	*) exit 1 ;;
esac
EOF

cat >"$BIN/uci" <<'EOF'
#!/bin/sh
if [ "$#" -eq 3 ] && [ "$1" = "-q" ] && [ "$2" = "get" ] &&
	[ "$3" = "network.lan.ipaddr" ]; then
	sed -n '1p' "$CR6608_TEST_CURRENT_IP"
	exit 0
fi
exit 1
EOF

cat >"$BIN/ip" <<'EOF'
#!/bin/sh
{
	printf 'ip'
	for arg do printf '|%s' "$arg"; done
	printf '\n'
} >>"$CR6608_TEST_IP_LOG"
case "$*" in
	'link show dev br-lan') exit 0 ;;
	'-4 address replace 198.51.100.23/24 dev br-lan')
		printf '198.51.100.23/24\n' >"$CR6608_TEST_ASSIGNED_IP"
		exit 0
		;;
	'-4 address show dev br-lan')
		if [ -s "$CR6608_TEST_ASSIGNED_IP" ]; then
			printf '5: br-lan    inet %s scope global br-lan\n' "$(sed -n '1p' "$CR6608_TEST_ASSIGNED_IP")"
		fi
		exit 0
		;;
	'-4 address del 198.51.100.23/24 dev br-lan')
		[ ! -e "$CR6608_TEST_DELETE_FAIL" ] || exit 65
		rm -f "$CR6608_TEST_ASSIGNED_IP"
		exit 0
		;;
	*) exit 64 ;;
esac
EOF

cat >"$BIN/start-stop-daemon" <<'EOF'
#!/bin/sh
{
	printf 'start-stop-daemon'
	for arg do printf '|%s' "$arg"; done
	printf '\n'
} >>"$CR6608_TEST_DAEMON_LOG"
exit 0
EOF

cat >"$BIN/logger" <<'EOF'
#!/bin/sh
{
	printf 'logger'
	for arg do printf '|%s' "$arg"; done
	printf '\n'
} >>"$CR6608_TEST_LOGGER_LOG"
exit 0
EOF

cat >"$BIN/sleep" <<'EOF'
#!/bin/sh
printf 'sleep|%s\n' "${1:-}" >>"$CR6608_TEST_SLEEP_LOG"
exit 0
EOF

cat >"$BIN/wifi" <<'EOF'
#!/bin/sh
printf 'wifi|%s\n' "${1:-}" >>"$CR6608_TEST_SERVICE_LOG"
exit 0
EOF

cat >"$TMP/root/etc/init.d/mock-service" <<'EOF'
#!/bin/sh
name="$(basename "$0")"
action="${1:-}"
printf '%s|%s\n' "$name" "$action" >>"$CR6608_TEST_SERVICE_LOG"
case "$name:$action" in
	cr6608-security:enabled) [ -e "$CR6608_TEST_SECURITY_ENABLED" ] ;;
	cr6608-security:enable) touch "$CR6608_TEST_SECURITY_ENABLED" ;;
	cr6608-security:disable) rm -f "$CR6608_TEST_SECURITY_ENABLED" ;;
	firewall:enabled) [ -e "$CR6608_TEST_FIREWALL_ENABLED" ] ;;
	firewall:enable) touch "$CR6608_TEST_FIREWALL_ENABLED" ;;
	firewall:disable) rm -f "$CR6608_TEST_FIREWALL_ENABLED" ;;
	*) exit 0 ;;
esac
EOF
for service in network dnsmasq firewall uhttpd dropbear cr6608-security; do
	cp "$TMP/root/etc/init.d/mock-service" "$TMP/root/etc/init.d/$service"
done

cat >"$TMP/root/usr/sbin/cr6608-security-apply" <<'EOF'
#!/bin/sh
printf 'security-apply|%s\n' "${1:-}" >>"$CR6608_TEST_SERVICE_LOG"
exit 0
EOF

chmod 0700 "$BIN"/* "$TMP/root/etc/init.d/"* "$TMP/root/usr/sbin/cr6608-security-apply"

CR6608_TEST_BACKUP_ROOT="$TMP/backups"
CR6608_TEST_ROOT="$TMP/root"
CR6608_TEST_TAR_LOG="$TMP/tar.log"
CR6608_TEST_IP_LOG="$TMP/ip.log"
CR6608_TEST_DAEMON_LOG="$TMP/daemon.log"
CR6608_TEST_LOGGER_LOG="$TMP/logger.log"
CR6608_TEST_SLEEP_LOG="$TMP/sleep.log"
CR6608_TEST_CURRENT_IP="$TMP/current-ip"
CR6608_TEST_ASSIGNED_IP="$TMP/assigned-ip"
CR6608_TEST_DELETE_FAIL="$TMP/delete-fail"
CR6608_TEST_TAR_EXTRACT_OK="$TMP/tar-extract-ok"
CR6608_TEST_SERVICE_LOG="$TMP/service.log"
CR6608_TEST_SECURITY_ENABLED="$TMP/security-enabled"
CR6608_TEST_FIREWALL_ENABLED="$TMP/firewall-enabled"
CR6608_SAFE_STATE="$TMP/state"
CR6608_SAFE_POINTER="$TMP/pointer"
CR6608_SAFE_META="$TMP/meta"
CR6608_SAFE_ARMED="$TMP/armed"
CR6608_SAFE_RETAINED_IP="$TMP/retained-ip"
CR6608_SAFE_LOCK="$TMP/lock"
CR6608_SAFE_SELF="$RUNTIME"
TMPDIR="$TMP/tmp"
PATH="$BIN:$PATH"
export CR6608_TEST_BACKUP_ROOT CR6608_TEST_ROOT CR6608_TEST_TAR_LOG
export CR6608_TEST_IP_LOG CR6608_TEST_DAEMON_LOG CR6608_TEST_LOGGER_LOG
export CR6608_TEST_SLEEP_LOG CR6608_TEST_CURRENT_IP
export CR6608_TEST_ASSIGNED_IP CR6608_TEST_DELETE_FAIL
export CR6608_TEST_TAR_EXTRACT_OK CR6608_TEST_SERVICE_LOG
export CR6608_TEST_SECURITY_ENABLED CR6608_TEST_FIREWALL_ENABLED
export CR6608_SAFE_STATE CR6608_SAFE_POINTER CR6608_SAFE_META CR6608_SAFE_ARMED
export CR6608_SAFE_RETAINED_IP CR6608_SAFE_LOCK CR6608_SAFE_SELF TMPDIR PATH

: >"$CR6608_TEST_TAR_LOG"
: >"$CR6608_TEST_IP_LOG"
: >"$CR6608_TEST_DAEMON_LOG"
: >"$CR6608_TEST_LOGGER_LOG"
: >"$CR6608_TEST_SLEEP_LOG"
: >"$CR6608_TEST_SERVICE_LOG"
printf '192.0.2.1\n' >"$CR6608_TEST_CURRENT_IP"
BACKUP="$CR6608_TEST_BACKUP_ROOT/smartap-runtime.tar.gz"
printf 'mock archive\n' >"$BACKUP"

RUN_OUT="$TMP/run.out"
RUN_ERR="$TMP/run.err"

expect_status() {
	expected="$1"
	label="$2"
	shift 2
	: >"$RUN_OUT"
	: >"$RUN_ERR"
	set +e
	"$@" >"$RUN_OUT" 2>"$RUN_ERR"
	actual=$?
	set -e
	if [ "$actual" -ne "$expected" ]; then
		printf '%s: expected status %s, got %s\n' "$label" "$expected" "$actual" >&2
		sed 's/^/stderr: /' "$RUN_ERR" >&2
		exit 1
	fi
}

expect_status 0 "arm" "$RUNTIME" arm "$BACKUP" 1 1 1 1 1 0 30
line_count="$(wc -l <"$RUN_OUT" | tr -d '[:space:]')"
[ "$line_count" = "1" ] || fail "arm did not emit exactly one line"
LC_ALL=C grep -Eq '^[0-9a-f]{32}$' "$RUN_OUT" || fail "arm token is not 32 lowercase hex characters"
token="$(sed -n '1p' "$RUN_OUT")"
[ "${#token}" -eq 32 ] || fail "arm token has the wrong length"

grep -Fqx "token=$token" "$CR6608_SAFE_STATE" || fail "state is not bound to the arm token"
grep -Fqx 'old_security=0' "$CR6608_SAFE_STATE" || fail "state does not preserve the security service state"
[ "$(sed -n '1p' "$CR6608_SAFE_ARMED")" = "$token" ] || fail "armed marker token mismatch"
grep -Fq "|--|watch|$token|30" "$CR6608_TEST_DAEMON_LOG" || fail "arm did not spawn its token-bound watcher"

expect_status 3 "second arm while pending" "$RUNTIME" arm "$BACKUP" 1 1 1 1 1 0 30
grep -Fqx "token=$token" "$CR6608_SAFE_STATE" || fail "second arm replaced the original pending transaction"
[ "$(sed -n '1p' "$CR6608_SAFE_ARMED")" = "$token" ] || fail "second arm replaced the original armed marker"

case "$token" in
	0*) wrong="1${token#?}" ;;
	*) wrong="0${token#?}" ;;
esac

expect_status 2 "empty confirm" "$RUNTIME" confirm
grep -Fqx "token=$token" "$CR6608_SAFE_STATE" || fail "empty confirm changed pending state"
expect_status 2 "wrong confirm" "$RUNTIME" confirm "$wrong"
grep -Fqx "token=$token" "$CR6608_SAFE_STATE" || fail "wrong confirm changed pending state"

retained_ip=198.51.100.23
expect_status 0 "retain-ip" "$RUNTIME" retain-ip "$retained_ip" 255.255.255.0 br-lan
marker="$token|$retained_ip|24|br-lan"
grep -Fqx "$marker" "$CR6608_SAFE_RETAINED_IP" || fail "retained address is not bound to the arm token"
grep -Fq "ip|-4|address|replace|$retained_ip/24|dev|br-lan" "$CR6608_TEST_IP_LOG" ||
	fail "retain-ip did not request the temporary address"

expect_status 2 "wrong-token cleanup" "$RUNTIME" cleanup-ip "$wrong" 1
grep -Fqx "$marker" "$CR6608_SAFE_RETAINED_IP" || fail "wrong token removed the retained-address marker"
if grep -Fq '|address|del|' "$CR6608_TEST_IP_LOG"; then
	fail "wrong token deleted the retained address"
fi

expect_status 0 "matching confirm" "$RUNTIME" confirm "$token"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "matching confirm left pending state"
[ ! -e "$CR6608_SAFE_ARMED" ] || fail "matching confirm left the armed marker"
[ -f "$CR6608_SAFE_RETAINED_IP" ] || fail "daemon mock unexpectedly ran cleanup"
grep -Fq "|--|cleanup-ip|$token|5" "$CR6608_TEST_DAEMON_LOG" ||
	fail "confirm did not schedule token-bound address cleanup"

expect_status 0 "confirmed watcher" "$RUNTIME" watch "$token" 30
[ ! -e "$CR6608_SAFE_STATE" ] || fail "confirmed watcher recreated pending state"
[ -f "$CR6608_SAFE_POINTER" ] && [ -f "$CR6608_SAFE_META" ] ||
	fail "confirmed watcher fell through to manual rollback cleanup"
grep -Fq 'expired rollback watcher ignored after confirmation' "$CR6608_TEST_LOGGER_LOG" ||
	fail "confirmed watcher was not ignored"
if grep -Fq 'tar|-xzf|' "$CR6608_TEST_TAR_LOG"; then
	fail "confirmed watcher attempted to restore the backup"
fi

printf '%s\n' "$retained_ip" >"$CR6608_TEST_CURRENT_IP"
expect_status 0 "current-IP cleanup" "$RUNTIME" cleanup-ip "$token" 1
[ ! -e "$CR6608_SAFE_RETAINED_IP" ] || fail "matching cleanup left the retained-address marker"
if grep -Fq '|address|del|' "$CR6608_TEST_IP_LOG"; then
	 fail "cleanup deleted the currently configured management IP"
fi

# A later transaction may reuse the same address. Deletion failure must keep
# the marker so boot can retry instead of reporting a false cleanup success.
printf '192.0.2.1\n' >"$CR6608_TEST_CURRENT_IP"
expect_status 0 "second arm after confirmation" "$RUNTIME" arm "$BACKUP" 1 1 1 1 1 0 30
token2="$(sed -n '1p' "$RUN_OUT")"
expect_status 0 "second retain-ip" "$RUNTIME" retain-ip "$retained_ip" 255.255.255.0 br-lan
marker2="$token2|$retained_ip|24|br-lan"
grep -Fqx "$marker2" "$CR6608_SAFE_RETAINED_IP" || fail "second retained address marker is missing"
touch "$CR6608_TEST_DELETE_FAIL"
expect_status 1 "failed retained-IP deletion" "$RUNTIME" cleanup-ip "$token2" 1
grep -Fqx "$marker2" "$CR6608_SAFE_RETAINED_IP" || fail "failed deletion discarded the retry marker"
expect_status 0 "second transaction confirmation" "$RUNTIME" confirm "$token2"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "second confirmation left pending state"
expect_status 1 "arm blocked by stale retained IP" "$RUNTIME" arm "$BACKUP" 1 1 1 1 1 0 30
[ ! -e "$CR6608_SAFE_STATE" ] || fail "blocked arm created a pending state"
[ ! -e "$CR6608_SAFE_ARMED" ] || fail "blocked arm created an armed marker"
grep -Fqx "$marker2" "$CR6608_SAFE_RETAINED_IP" || fail "blocked arm discarded the retained-IP retry marker"
rm -f "$CR6608_TEST_DELETE_FAIL"
expect_status 0 "retried retained-IP deletion" "$RUNTIME" cleanup-ip "$token2" 1
[ ! -e "$CR6608_SAFE_RETAINED_IP" ] || fail "successful deletion left the retained-address marker"
[ ! -e "$CR6608_TEST_ASSIGNED_IP" ] || fail "successful deletion left the temporary address assigned"

expect_status 0 "arm after retained-IP cleanup" "$RUNTIME" arm "$BACKUP" 1 1 1 1 1 0 30
[ -s "$CR6608_SAFE_STATE" ] || fail "clean arm did not create a pending state"
token3="$(sed -n '1p' "$RUN_OUT")"
touch "$CR6608_TEST_TAR_EXTRACT_OK" "$CR6608_TEST_FIREWALL_ENABLED"
expect_status 0 "successful rollback restores disabled security" "$RUNTIME" rollback "$token3"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "successful rollback left pending state"
[ ! -e "$CR6608_TEST_SECURITY_ENABLED" ] || fail "rollback enabled a previously disabled security service"
grep -Fqx 'security-apply|clear-runtime' "$CR6608_TEST_SERVICE_LOG" || fail "rollback did not clear disabled security runtime"
! grep -Fqx 'security-apply|boot' "$CR6608_TEST_SERVICE_LOG" || fail "rollback replayed disabled security runtime"
security_line="$(grep -nF 'security-apply|clear-runtime' "$CR6608_TEST_SERVICE_LOG" | tail -n 1 | cut -d: -f1)"
firewall_line="$(grep -nF 'firewall|enable' "$CR6608_TEST_SERVICE_LOG" | tail -n 1 | cut -d: -f1)"
[ -n "$security_line" ] && [ -n "$firewall_line" ] && [ "$security_line" -lt "$firewall_line" ] || fail "firewall was restored before security runtime settled"

printf 'safe_apply_runtime_tests=pass\n'
