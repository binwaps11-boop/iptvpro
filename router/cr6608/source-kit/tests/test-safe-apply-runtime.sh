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
CR6608_TEST_REAL_STAT="$(command -v stat)" || exit 1

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
[ "$#" -eq 3 ] && [ "$1" = "-c" ] || exit 64
case "$2" in
	%u) printf '0\n' ;;
	%u:%a)
		if [ -e "$CR6608_TEST_FORCE_BAD_MODE" ] && [ "$3" = "$CR6608_SAFE_READY" ]; then
			printf '4242:644\n'
		elif [ -d "$3" ]; then
			printf '4242:700\n'
		else
			printf '4242:600\n'
		fi
		;;
	*) exit 64 ;;
esac
EOF

cat >"$BIN/id" <<'EOF'
#!/bin/sh
[ "$#" -eq 1 ] && [ "$1" = -u ] || exit 64
printf '4242\n'
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
{
	printf 'uci'
	for arg do printf '|%s' "$arg"; done
	printf '\n'
} >>"$CR6608_TEST_UCI_LOG"
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

cat >"$BIN/date" <<'EOF'
#!/bin/sh
[ "${1:-}" = "+%s" ] || exit 64
sed -n '1p' "$CR6608_TEST_EPOCH_FILE"
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
for service in network dnsmasq firewall uhttpd dropbear cr6608-security cr6608-neighbor; do
	cp "$TMP/root/etc/init.d/mock-service" "$TMP/root/etc/init.d/$service"
done

cat >"$TMP/root/usr/sbin/cr6608-security-apply" <<'EOF'
#!/bin/sh
printf 'security-apply|%s\n' "${1:-}" >>"$CR6608_TEST_SERVICE_LOG"
exit 0
EOF

cat >"$TMP/root/usr/sbin/smartap-qos-apply" <<'EOF'
#!/bin/sh
printf 'smartap-qos-apply|%s\n' "${1:-}" >>"$CR6608_TEST_SERVICE_LOG"
[ ! -e "$CR6608_TEST_QOS_APPLY_FAIL" ]
EOF

cat >"$TMP/root/usr/sbin/cr6608-safe-wifi-reload" <<'EOF'
#!/bin/sh
printf 'safe-wifi-verify|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" >>"$CR6608_TEST_SERVICE_LOG"
exit 0
EOF

cat >"$TMP/root/usr/sbin/cr6608-rescue-guard" <<'EOF'
#!/bin/sh
printf 'rescue-guard|%s\n' "${1:-}" >>"$CR6608_TEST_SERVICE_LOG"
[ "${1:-}" = firewall-stop ]
EOF

chmod 0700 "$BIN"/* "$TMP/root/etc/init.d/"* "$TMP/root/usr/sbin/"*

CR6608_TEST_BACKUP_ROOT="$TMP/backups"
CR6608_TEST_ROOT="$TMP/root"
CR6608_TEST_TAR_LOG="$TMP/tar.log"
CR6608_TEST_IP_LOG="$TMP/ip.log"
CR6608_TEST_DAEMON_LOG="$TMP/daemon.log"
CR6608_TEST_LOGGER_LOG="$TMP/logger.log"
CR6608_TEST_SLEEP_LOG="$TMP/sleep.log"
CR6608_TEST_UCI_LOG="$TMP/uci.log"
CR6608_TEST_CURRENT_IP="$TMP/current-ip"
CR6608_TEST_ASSIGNED_IP="$TMP/assigned-ip"
CR6608_TEST_DELETE_FAIL="$TMP/delete-fail"
CR6608_TEST_TAR_EXTRACT_OK="$TMP/tar-extract-ok"
CR6608_TEST_SERVICE_LOG="$TMP/service.log"
CR6608_TEST_SECURITY_ENABLED="$TMP/security-enabled"
CR6608_TEST_FIREWALL_ENABLED="$TMP/firewall-enabled"
CR6608_TEST_QOS_APPLY_FAIL="$TMP/qos-apply-fail"
CR6608_SAFE_STATE="$TMP/state"
CR6608_SAFE_POINTER="$TMP/pointer"
CR6608_SAFE_META="$TMP/meta"
CR6608_SAFE_ARMED="$TMP/armed"
CR6608_SAFE_READY="$TMP/ready"
CR6608_SAFE_RETAINED_IP="$TMP/retained-ip"
CR6608_SAFE_LOCK="$TMP/lock"
CR6608_SAFE_SELF="$RUNTIME"
CR6608_SAFE_UPTIME_FILE="$TMP/uptime"
CR6608_SAFE_BOOT_ID_FILE="$TMP/boot-id"
CR6608_TEST_EPOCH_FILE="$TMP/epoch"
CR6608_TEST_FORCE_BAD_MODE="$TMP/force-bad-mode"
TMPDIR="$TMP/tmp"
PATH="$BIN:$PATH"
export CR6608_TEST_BACKUP_ROOT CR6608_TEST_ROOT CR6608_TEST_TAR_LOG
export CR6608_TEST_IP_LOG CR6608_TEST_DAEMON_LOG CR6608_TEST_LOGGER_LOG
export CR6608_TEST_SLEEP_LOG CR6608_TEST_UCI_LOG CR6608_TEST_CURRENT_IP
export CR6608_TEST_ASSIGNED_IP CR6608_TEST_DELETE_FAIL
export CR6608_TEST_TAR_EXTRACT_OK CR6608_TEST_SERVICE_LOG
export CR6608_TEST_SECURITY_ENABLED CR6608_TEST_FIREWALL_ENABLED
export CR6608_TEST_QOS_APPLY_FAIL
export CR6608_SAFE_STATE CR6608_SAFE_POINTER CR6608_SAFE_META CR6608_SAFE_ARMED CR6608_SAFE_READY
export CR6608_SAFE_RETAINED_IP CR6608_SAFE_LOCK CR6608_SAFE_SELF CR6608_SAFE_UPTIME_FILE
export CR6608_SAFE_BOOT_ID_FILE CR6608_TEST_EPOCH_FILE CR6608_TEST_FORCE_BAD_MODE
export CR6608_TEST_REAL_STAT TMPDIR PATH

: >"$CR6608_TEST_TAR_LOG"
: >"$CR6608_TEST_IP_LOG"
: >"$CR6608_TEST_DAEMON_LOG"
: >"$CR6608_TEST_LOGGER_LOG"
: >"$CR6608_TEST_SLEEP_LOG"
: >"$CR6608_TEST_UCI_LOG"
: >"$CR6608_TEST_SERVICE_LOG"
printf '1700000000\n' >"$CR6608_TEST_EPOCH_FILE"
printf '1000.00 0.00\n' >"$CR6608_SAFE_UPTIME_FILE"
BOOT_ID_A=11111111-2222-4333-8444-555555555555
BOOT_ID_B=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee
printf '%s\n' "$BOOT_ID_A" >"$CR6608_SAFE_BOOT_ID_FILE"
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

expect_status 0 "armed status" "$RUNTIME" status
grep -Fqx 'state=armed' "$RUN_OUT" || fail "status does not report the armed transaction"
grep -Fqx "token=$token" "$RUN_OUT" || fail "status token does not match the armed transaction"
grep -Fqx 'timeout=30' "$RUN_OUT" || fail "status does not expose the stored rollback timeout"
LC_ALL=C grep -Eq '^armed_epoch=[0-9]+$' "$RUN_OUT" || fail "status does not expose a valid arm epoch"
grep -Fqx 'armed_uptime=1000' "$RUN_OUT" || fail "status does not expose the monotonic arm anchor"
grep -Fqx 'timing_source=monotonic' "$RUN_OUT" || fail "v6 status did not use monotonic time"
grep -Fqx 'remaining=29' "$RUN_OUT" || fail "initial monotonic countdown is not conservative"
printf '1007.00 0.00\n' >"$CR6608_SAFE_UPTIME_FILE"
expect_status 0 "advanced monotonic status" "$RUNTIME" status
grep -Fqx 'remaining=22' "$RUN_OUT" || fail "monotonic countdown did not advance by seven seconds"

expect_status 2 "wrong ready token" "$RUNTIME" ready 00000000000000000000000000000000
[ ! -e "$CR6608_SAFE_READY" ] || fail "wrong token created a completed-success marker"
expect_status 0 "matching ready token" "$RUNTIME" ready "$token"
grep -Fqx "$token" "$CR6608_SAFE_READY" || fail "ready marker is not bound to the armed token"

expect_status 3 "second arm while pending" "$RUNTIME" arm "$BACKUP" 1 1 1 1 1 0 30
grep -Fqx "token=$token" "$CR6608_SAFE_STATE" || fail "second arm replaced the original pending transaction"
[ "$(sed -n '1p' "$CR6608_SAFE_ARMED")" = "$token" ] || fail "second arm replaced the original armed marker"
grep -Fqx "$token" "$CR6608_SAFE_READY" || fail "rejected second arm cleared the original readiness marker"

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
[ ! -e "$CR6608_SAFE_READY" ] || fail "matching confirm left the readiness marker"
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

printf 'version=3\ntoken=broken\n' >"$CR6608_SAFE_STATE"
printf '%s\n' "$token" >"$CR6608_SAFE_ARMED"
: >"$CR6608_TEST_TAR_LOG"
expect_status 1 "corrupt pending state" "$RUNTIME" watch "$token" 30
[ -s "$CR6608_SAFE_STATE" ] || fail "corrupt pending state was cleared as if confirmed"
[ -s "$CR6608_SAFE_ARMED" ] || fail "corrupt armed marker was cleared as if confirmed"
if grep -Fq 'tar|-xzf|' "$CR6608_TEST_TAR_LOG"; then
	fail "corrupt state fell through to an unrelated manual backup"
fi
grep -Fq 'pending rollback state is invalid' "$CR6608_TEST_LOGGER_LOG" ||
	fail "corrupt pending state was not reported"
rm -f "$CR6608_SAFE_STATE" "$CR6608_SAFE_ARMED"

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
: >"$CR6608_TEST_IP_LOG"
expect_status 0 "retain IP for rollback ordering" "$RUNTIME" retain-ip "$retained_ip" 255.255.255.0 br-lan
marker3="$token3|$retained_ip|24|br-lan"
grep -Fqx "$marker3" "$CR6608_SAFE_RETAINED_IP" || fail "rollback-order retained marker is missing"
expect_status 0 "mark transaction ready before failed rollback" "$RUNTIME" ready "$token3"
grep -Fqx "$token3" "$CR6608_SAFE_READY" || fail "ready marker missing before rollback test"
expect_status 1 "failed restore keeps retained IP" "$RUNTIME" rollback "$token3"
grep -Fqx "$marker3" "$CR6608_SAFE_RETAINED_IP" || fail "failed restore discarded the retained-IP marker"
[ -s "$CR6608_TEST_ASSIGNED_IP" ] || fail "failed restore deleted the retained management address"
! grep -Fq '|address|del|' "$CR6608_TEST_IP_LOG" || fail "retained management address was deleted before restore succeeded"
[ -s "$CR6608_SAFE_STATE" ] || fail "failed restore cleared the pending rollback state"
[ ! -e "$CR6608_SAFE_READY" ] || fail "failed rollback left the transaction confirmable"
touch "$CR6608_TEST_TAR_EXTRACT_OK" "$CR6608_TEST_FIREWALL_ENABLED"
: >"$CR6608_TEST_UCI_LOG"
expect_status 0 "successful rollback restores disabled security" "$RUNTIME" rollback "$token3"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "successful rollback left pending state"
[ ! -e "$CR6608_SAFE_RETAINED_IP" ] || fail "successful rollback left the retained-IP marker"
[ ! -e "$CR6608_TEST_ASSIGNED_IP" ] || fail "successful rollback left the temporary management address assigned"
grep -Fq '|address|del|' "$CR6608_TEST_IP_LOG" || fail "successful rollback did not clean the retained management address"
[ ! -e "$CR6608_TEST_SECURITY_ENABLED" ] || fail "rollback enabled a previously disabled security service"
grep -Fqx 'security-apply|clear-runtime' "$CR6608_TEST_SERVICE_LOG" || fail "rollback did not clear disabled security runtime"
! grep -Fqx 'security-apply|boot' "$CR6608_TEST_SERVICE_LOG" || fail "rollback replayed disabled security runtime"
grep -Fqx 'smartap-qos-apply|' "$CR6608_TEST_SERVICE_LOG" || fail "rollback did not restore bridge QoS/block policy"
grep -Fqx 'cr6608-neighbor|restart' "$CR6608_TEST_SERVICE_LOG" || fail "rollback did not restart the restored neighbor identity"
grep -Fqx 'uci|-q|revert|prplmesh' "$CR6608_TEST_UCI_LOG" || fail "rollback did not discard the staged prplmesh overlay"
security_line="$(grep -nF 'security-apply|clear-runtime' "$CR6608_TEST_SERVICE_LOG" | tail -n 1 | cut -d: -f1)"
firewall_line="$(grep -nF 'firewall|enable' "$CR6608_TEST_SERVICE_LOG" | tail -n 1 | cut -d: -f1)"
qos_line="$(grep -nF 'smartap-qos-apply|' "$CR6608_TEST_SERVICE_LOG" | tail -n 1 | cut -d: -f1)"
neighbor_line="$(grep -nF 'cr6608-neighbor|restart' "$CR6608_TEST_SERVICE_LOG" | tail -n 1 | cut -d: -f1)"
[ -n "$security_line" ] && [ -n "$firewall_line" ] && [ "$security_line" -lt "$firewall_line" ] || fail "firewall was restored before security runtime settled"
[ -n "$qos_line" ] && [ -n "$firewall_line" ] && [ "$qos_line" -gt "$firewall_line" ] || fail "bridge block policy was replayed before firewall restore"
[ -n "$neighbor_line" ] && [ -n "$qos_line" ] && [ "$neighbor_line" -gt "$qos_line" ] || fail "neighbor identity restarted before restored SmartAP policy settled"

# Enabled services may intentionally have no live ruleset at transaction start.
# Rollback must preserve that distinction instead of activating new filtering
# rules while the management client is reconnecting.
: >"$CR6608_TEST_SERVICE_LOG"
expect_status 0 "arm with inactive runtimes" "$RUNTIME" arm "$BACKUP" 1 0 1 1 1 1 1 0 30
token4="$(sed -n '1p' "$RUN_OUT")"
grep -Fqx 'version=6' "$CR6608_SAFE_STATE" || fail "new rollback state is not version 6"
grep -Fqx 'armed_uptime=1007' "$CR6608_SAFE_STATE" || fail "v6 state did not persist its monotonic anchor"
grep -Fqx "armed_boot_id=$BOOT_ID_A" "$CR6608_SAFE_STATE" || fail "v6 state did not persist its boot identity"
grep -Fqx 'old_firewall_runtime=0' "$CR6608_SAFE_STATE" || fail "firewall runtime state was not preserved"
grep -Fqx 'old_uhttpd=1' "$CR6608_SAFE_STATE" || fail "uhttpd boot state was not preserved"
grep -Fqx 'old_dropbear_runtime=1' "$CR6608_SAFE_STATE" || fail "dropbear runtime state was not preserved"
grep -Fqx 'old_security_runtime=0' "$CR6608_SAFE_STATE" || fail "security runtime state was not preserved"
expect_status 0 "rollback preserves inactive runtimes" "$RUNTIME" rollback "$token4"
grep -Fqx 'firewall|enable' "$CR6608_TEST_SERVICE_LOG" || fail "enabled firewall service state was not restored"
grep -Fqx 'rescue-guard|firewall-stop' "$CR6608_TEST_SERVICE_LOG" || fail "inactive firewall runtime was not restored through the rescue guard"
! grep -Fqx 'firewall|start' "$CR6608_TEST_SERVICE_LOG" || fail "rollback activated a previously inactive firewall runtime"
! grep -Fqx 'firewall|reload' "$CR6608_TEST_SERVICE_LOG" || fail "rollback reloaded a previously inactive firewall runtime"
grep -Fqx 'cr6608-security|enable' "$CR6608_TEST_SERVICE_LOG" || fail "enabled security service state was not restored"
grep -Fqx 'security-apply|clear-runtime' "$CR6608_TEST_SERVICE_LOG" || fail "inactive security runtime was not restored"
! grep -Fqx 'security-apply|boot' "$CR6608_TEST_SERVICE_LOG" || fail "rollback replayed a previously inactive security runtime"

# A pending v4 transaction from an in-flight upgrade has no boot identity.
# It must remain rollback authority but can never be confirmed safely.
expect_status 0 "arm before legacy-v4 fail-closed test" "$RUNTIME" arm "$BACKUP" 1 0 1 1 1 1 1 0 30
legacy_token="$(sed -n '1p' "$RUN_OUT")"
sed '/^armed_uptime=/d; /^armed_boot_id=/d; s/^version=6$/version=4/' "$CR6608_SAFE_STATE" >"$TMP/state-v4"
mv "$TMP/state-v4" "$CR6608_SAFE_STATE"
printf '1700000007\n' >"$CR6608_TEST_EPOCH_FILE"
expect_status 1 "legacy v4 status fails closed" "$RUNTIME" status
grep -Fqx 'state=invalid' "$RUN_OUT" || fail "legacy v4 status did not fail closed"
expect_status 1 "legacy v4 confirmation fails closed" "$RUNTIME" confirm "$legacy_token"
grep -Fqx "token=$legacy_token" "$CR6608_SAFE_STATE" || fail "legacy v4 confirmation cleared pending rollback"
expect_status 0 "legacy v4 rollback remains available" "$RUNTIME" rollback "$legacy_token"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "legacy v4 rollback left pending state"

# A reboot changes boot_id. Even if the new uptime has already passed the old
# numeric anchor, the old token must not be confirmable before boot rollback.
expect_status 0 "arm before reboot identity test" "$RUNTIME" arm "$BACKUP" 1 0 1 1 1 1 1 0 30
reboot_token="$(sed -n '1p' "$RUN_OUT")"
printf '%s\n' "$BOOT_ID_B" >"$CR6608_SAFE_BOOT_ID_FILE"
printf '2000.00 0.00\n' >"$CR6608_SAFE_UPTIME_FILE"
expect_status 1 "status rejects previous-boot state" "$RUNTIME" status
grep -Fqx 'state=invalid' "$RUN_OUT" || fail "previous-boot status did not fail closed"
expect_status 1 "confirm rejects previous-boot token" "$RUNTIME" confirm "$reboot_token"
grep -Fqx "token=$reboot_token" "$CR6608_SAFE_STATE" || fail "previous-boot confirmation cleared pending rollback"
expect_status 0 "rollback survives boot identity change" "$RUNTIME" rollback "$reboot_token"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "rollback after boot identity change left pending state"

# Timing metadata is presentation data, not restoration authority. Corruption
# must fail the status API closed while leaving token-bound rollback functional.
expect_status 0 "arm before timing-corruption test" "$RUNTIME" arm "$BACKUP" 1 0 1 1 1 1 1 0 30
timing_token="$(sed -n '1p' "$RUN_OUT")"
sed 's/^timeout=.*/timeout=broken/' "$CR6608_SAFE_STATE" >"$TMP/state-corrupt"
mv "$TMP/state-corrupt" "$CR6608_SAFE_STATE"
expect_status 1 "status rejects corrupt timing" "$RUNTIME" status
grep -Fqx 'state=invalid' "$RUN_OUT" || fail "corrupt timing status did not fail closed"
expect_status 0 "rollback survives corrupt timing" "$RUNTIME" rollback "$timing_token"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "rollback with corrupt timing left pending state"

# A valid token cannot confirm after its monotonic deadline, even if its watcher
# is delayed behind the shared apply lock.
expect_status 0 "arm before deadline test" "$RUNTIME" arm "$BACKUP" 1 0 1 1 1 1 1 0 30
expired_token="$(sed -n '1p' "$RUN_OUT")"
printf '2031.00 0.00\n' >"$CR6608_SAFE_UPTIME_FILE"
expect_status 0 "expired monotonic status" "$RUNTIME" status
grep -Fqx 'remaining=0' "$RUN_OUT" || fail "expired monotonic transaction reports usable time"
expect_status 3 "expired confirmation" "$RUNTIME" confirm "$expired_token"
grep -Fqx "token=$expired_token" "$CR6608_SAFE_STATE" || fail "expired confirmation cleared pending rollback"
expect_status 0 "rollback after expired confirmation" "$RUNTIME" rollback "$expired_token"
[ ! -e "$CR6608_SAFE_STATE" ] || fail "expired transaction rollback left pending state"

# Runtime verification is mandatory. A missing verifier must retain the pending
# state instead of clearing it as a successful rollback.
expect_status 0 "arm before missing-verifier test" "$RUNTIME" arm "$BACKUP" 1 0 1 1 1 1 1 0 30
token5="$(sed -n '1p' "$RUN_OUT")"
touch "$CR6608_TEST_QOS_APPLY_FAIL"
expect_status 1 "rollback fails closed when bridge policy replay fails" "$RUNTIME" rollback "$token5"
[ -s "$CR6608_SAFE_STATE" ] || fail "bridge policy replay failure cleared the pending rollback state"
[ -s "$CR6608_SAFE_ARMED" ] || fail "bridge policy replay failure cleared the armed marker"
rm -f "$CR6608_TEST_QOS_APPLY_FAIL"
rm -f "$TMP/root/usr/sbin/cr6608-safe-wifi-reload"
expect_status 1 "rollback fails closed without Wi-Fi verifier" "$RUNTIME" rollback "$token5"
[ -s "$CR6608_SAFE_STATE" ] || fail "missing verifier cleared the pending rollback state"
[ -s "$CR6608_SAFE_ARMED" ] || fail "missing verifier cleared the armed marker"

# Every volatile marker lives below one private directory and is mode 0600.
# MSYS exposes a Windows ACL projection instead of stable chmod bits; Linux is
# the authoritative permission gate used by the build VM and target.
case "$(uname -s)" in
	MINGW*|MSYS*) : ;;
	*)
		[ "$("$CR6608_TEST_REAL_STAT" -c '%a' "$TMP")" = 700 ] ||
			fail "Safe Apply runtime parent is not private"
		for marker_path in "$CR6608_SAFE_POINTER" "$CR6608_SAFE_META" "$CR6608_SAFE_ARMED"; do
			[ ! -e "$marker_path" ] || [ "$("$CR6608_TEST_REAL_STAT" -c '%a' "$marker_path")" = 600 ] ||
				fail "Safe Apply marker is not mode 0600: $marker_path"
		done
		;;
esac

# A local user may reserve every old predictable name, but cannot redirect a
# root write: symlink and wrong-mode pre-creation both fail before the command.
rm -f "$CR6608_SAFE_STATE" "$CR6608_SAFE_POINTER" "$CR6608_SAFE_META" \
	"$CR6608_SAFE_ARMED" "$CR6608_SAFE_READY" "$CR6608_SAFE_RETAINED_IP"
victim="$TMP/hostile-victim"
printf 'victim-unchanged\n' >"$victim"
ln -s "$victim" "$CR6608_SAFE_READY"
case "$(uname -s)" in
	MINGW*|MSYS*)
		# Git for Windows may materialize `ln -s` as a regular text file.  The
		# real symlink rejection remains mandatory and exercised on Linux.
		set +e
		"$RUNTIME" status >/dev/null 2>&1
		set -e
		;;
	*) expect_status 1 "hostile ready symlink" "$RUNTIME" status ;;
esac
grep -Fqx 'victim-unchanged' "$victim" || fail "hostile ready symlink clobbered its target"
rm -f "$CR6608_SAFE_READY"
printf 'attacker-precreated\n' >"$CR6608_SAFE_READY"
chmod 0644 "$CR6608_SAFE_READY"
touch "$CR6608_TEST_FORCE_BAD_MODE"
expect_status 1 "hostile wrong-mode marker" "$RUNTIME" status
grep -Fqx 'attacker-precreated' "$CR6608_SAFE_READY" || fail "wrong-mode marker was overwritten"
rm -f "$CR6608_TEST_FORCE_BAD_MODE"

printf 'safe_apply_runtime_tests=pass\n'
