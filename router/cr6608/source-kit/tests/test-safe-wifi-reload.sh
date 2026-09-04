#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/files/usr/sbin/cr6608-safe-wifi-reload"
SCHEDULE="$ROOT/files/usr/sbin/cr6608-wifi-schedule"
DASHCTL="$ROOT/files/www/cgi-bin/dashctl"
SENTINEL="$ROOT/files/usr/sbin/cr6608-wifi-sentinel"
SELFTEST="$ROOT/files/usr/sbin/smartap-selftest"
BUILD="$ROOT/build.sh"
PRIVATE_STAT_BIN=stat
HEALTHY_TIMEOUT=8
RUN_FAILURE_MATRIX=1
case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW*|MSYS*|CYGWIN*)
		PRIVATE_STAT_BIN="$ROOT/tests/helpers/cr6608-private-stat-msys"
		# Process-heavy runtime probes are materially slower under the MSYS
		# compatibility layer; production and Linux keep the tighter contract
		# and Linux executes the complete rollback/failure matrix below.
		HEALTHY_TIMEOUT=90
		RUN_FAILURE_MATRIX=0
		;;
esac

fail() {
	printf 'safe_wifi_reload_test=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$SOURCE" ] || fail "missing $SOURCE"
[ -f "$SCHEDULE" ] || fail "missing $SCHEDULE"
sh -n "$SCHEDULE" || fail "scheduled Wi-Fi watchdog shell syntax failed"
grep -Fq 'exec /usr/bin/setsid "$@"' "$SCHEDULE" || fail "scheduled Wi-Fi commands lack a private process group"
grep -Fq '/bin/kill -KILL "-$_rb_pid"' "$SCHEDULE" || fail "scheduled Wi-Fi watchdog does not kill the command group"
grep -Fq 'cr6608_dashboard_cache_mutation_begin' "$SCHEDULE" || fail "scheduled Wi-Fi changes bypass cache invalidation"
grep -Fq 'CR6608_APPLY_LOCK:-/var/run/cr6608-apply.lock' "$SCHEDULE" || fail "scheduled Wi-Fi changes bypass the global apply lock"
grep -Fq '/usr/sbin/cr6608-safe-wifi-reload --verify-only 660 all' "$SCHEDULE" || fail "scheduled Wi-Fi up lacks bounded runtime verification"
grep -Fq '/usr/sbin/cr6608-wifi-schedule down # smartap-wifi-timer' "$DASHCTL" || fail "dashboard still emits an unbounded Wi-Fi-down cron command"
grep -Fq '/usr/sbin/cr6608-wifi-schedule up # smartap-wifi-timer' "$DASHCTL" || fail "dashboard still emits an unbounded Wi-Fi-up cron command"
! grep -Fq '/sbin/wifi down # smartap-wifi-timer' "$DASHCTL" || fail "raw Wi-Fi-down cron command remains"
! grep -Fq '/sbin/wifi up # smartap-wifi-timer' "$DASHCTL" || fail "raw Wi-Fi-up cron command remains"
grep -Fq '$6=="/usr/sbin/cr6608-wifi-schedule"' "$SENTINEL" || fail "sentinel cannot recognize the bounded Wi-Fi schedule"
grep -Fq '$6=="/usr/sbin/cr6608-wifi-schedule"' "$SELFTEST" || fail "self-test cannot recognize the bounded Wi-Fi schedule"
[ "$(grep -F -c '"${SRC_FILES}/usr/sbin/cr6608-wifi-schedule"' "$BUILD")" -ge 2 ] || fail "build does not require and syntax-check the Wi-Fi schedule helper"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-safe-wifi.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BIN="$TMP/bin"
RUNTIME="$TMP/cr6608-safe-wifi-reload"
mkdir -p "$BIN" "$TMP/etc/config"

cat >"$TMP/cache-state" <<'EOF'
cr6608_dashboard_cache_mutation_begin() { return 0; }
cr6608_dashboard_cache_mutation_finish() { return 0; }
EOF

sed "s|/etc/config/wireless|$TMP/etc/config/wireless|g" "$SOURCE" >"$RUNTIME"
chmod 0700 "$RUNTIME"
printf 'config wifi-device radio0\n' >"$TMP/backup-wireless"
cp "$TMP/backup-wireless" "$TMP/etc/config/wireless"

cat >"$BIN/uci" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-q" ]; then shift; fi
case "${1:-}:${2:-}" in
	get:wireless.radio0.disabled) printf '0\n' ;;
	get:wireless.radio1.disabled) printf '1\n' ;;
	get:wireless.radio0.channel) printf '11\n' ;;
	get:wireless.radio1.channel) printf '36\n' ;;
	get:wireless.radio0.country) printf 'US\n' ;;
	get:wireless.radio0.htmode) printf 'HE20\n' ;;
	get:wireless.radio0.txpower) printf '30\n' ;;
	get:wireless.radio0.band) printf '2g\n' ;;
	show:wireless)
		printf '%s\n' \
			'wireless.wifinet0=wifi-iface' \
			"wireless.wifinet0.device='radio0'" \
			"wireless.wifinet0.mode='${CR6608_TEST_MODE:-ap}'"
		;;
	get:wireless.wifinet0.device) printf 'radio0\n' ;;
	get:wireless.wifinet0.disabled) printf '0\n' ;;
	get:wireless.wifinet0.mode) printf '%s\n' "${CR6608_TEST_MODE:-ap}" ;;
	get:wireless.wifinet0.ssid) printf 'Smart ap 2.4G\n' ;;
	get:wireless.wifinet0.encryption) printf 'none\n' ;;
	get:wireless.wifinet0.network) printf 'lan\n' ;;
	revert:wireless|commit:wireless) ;;
	*) exit 1 ;;
esac
EOF

cat >"$BIN/ubus" <<'EOF'
#!/bin/sh
case "$*" in
	'-S call network.wireless status') printf '{}\n' ;;
	'-S list hostapd.phy0-ap0')
		if ! grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null ||
			[ "${CR6608_HOSTAPD_OK:-1}" = 1 ]; then
			printf 'hostapd.phy0-ap0\n'
		fi
		;;
	'-S call hostapd.phy0-ap0 get_status')
		if grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null; then
			[ "${CR6608_HOSTAPD_OK:-1}" = 1 ] || exit 1
			printf '{"status":"%s","ssid":"%s"}\n' \
				"${CR6608_HOSTAPD_STATE:-ENABLED}" \
				"${CR6608_RUNTIME_SSID:-Smart ap 2.4G}"
		else
			printf '{"status":"ENABLED","ssid":"Smart ap 2.4G"}\n'
		fi
		;;
	*) exit 1 ;;
esac
EOF

cat >"$BIN/jsonfilter" <<'EOF'
#!/bin/sh
case "$*" in
	*'@.radio0.up'*) printf 'true\n' ;;
	*'@.radio0.disabled'*) printf 'false\n' ;;
	*'@.radio0.pending'*) printf 'false\n' ;;
	*'@.radio1.up'*) printf 'false\n' ;;
	*'@.radio1.disabled'*) printf 'true\n' ;;
	*'@.radio1.pending'*) printf 'false\n' ;;
	*'@.radio0.config.channel'*)
		if grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null; then
			printf '%s\n' "${CR6608_RUNTIME_CHANNEL:-11}"
		else
			printf '11\n'
		fi
		;;
	*'@.radio0.config.country'*) printf 'US\n' ;;
	*'@.radio0.config.htmode'*) printf 'HE20\n' ;;
	*'@.radio0.config.txpower'*) printf '30\n' ;;
	*'@.radio0.config.band'*) printf '2g\n' ;;
	*'@.radio0.interfaces[0].section'*)
		if grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null; then
			printf '%s\n' "${CR6608_RUNTIME_SECTION:-wifinet0}"
		else
			printf 'wifinet0\n'
		fi
		;;
	*'@.radio0.interfaces[1].section'*) exit 1 ;;
	*'@.radio0.interfaces[0].ifname'*) printf 'phy0-ap0\n' ;;
	*'@.radio0.interfaces[0].config.mode'*) printf '%s\n' "${CR6608_TEST_MODE:-ap}" ;;
	*'@.radio0.interfaces[0].config.ssid'*)
		if grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null; then
			printf '%s\n' "${CR6608_RUNTIME_SSID:-Smart ap 2.4G}"
		else
			printf 'Smart ap 2.4G\n'
		fi
		;;
	*'@.radio0.interfaces[0].config.encryption'*) printf 'none\n' ;;
	*'@.radio0.interfaces[0].config.network'*) printf 'lan\n' ;;
	*'@.radio1.interfaces'*.ifname*) exit 1 ;;
	*'@.status'*)
		if grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null; then
			printf '%s\n' "${CR6608_HOSTAPD_STATE:-ENABLED}"
		else
			printf 'ENABLED\n'
		fi
		;;
	*'@.ssid'*)
		if grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null; then
			printf '%s\n' "${CR6608_RUNTIME_SSID:-Smart ap 2.4G}"
		else
			printf 'Smart ap 2.4G\n'
		fi
		;;
	*) exit 1 ;;
esac
EOF

cat >"$BIN/iw" <<'EOF'
#!/bin/sh
case "$*" in
	'dev')
		printf '%s\n' 'phy#0' '	Interface phy0-ap0' "		type ${CR6608_TEST_IW_TYPE:-AP}"
		;;
	'dev phy0-ap0 info')
		if grep -q broken-radio "$CR6608_TEST_WIRELESS" 2>/dev/null; then
			channel="${CR6608_RUNTIME_CHANNEL:-11}"
		else
			channel=11
		fi
		printf '%s\n' 'Interface phy0-ap0' "	type ${CR6608_TEST_IW_TYPE:-AP}" \
			"	channel $channel (2462 MHz), width: 20 MHz, center1: 2462 MHz"
		;;
	*) exit 1 ;;
esac
EOF

cat >"$BIN/wifi" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$BIN/logger" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$BIN/sleep" <<'EOF'
#!/bin/sh
exec /bin/sleep "$@"
EOF

chmod 0700 "$BIN"/*
PATH="$BIN:$PATH"
CR6608_TEST_WIRELESS="$TMP/etc/config/wireless"
CR6608_WIFI_MIN_TIMEOUT=8
CR6608_DASHBOARD_CACHE_STATE_LIB="$TMP/cache-state"
CR6608_WIFI_WATCHDOG_DIR="$TMP"
CR6608_PRIVATE_RUNTIME_LIB="$ROOT/files/usr/libexec/cr6608-private-runtime"
CR6608_PRIVATE_RUNTIME_ROOT="$TMP/private-runtime"
CR6608_PRIVATE_EXPECTED_UID="$(id -u)"
CR6608_PRIVATE_STAT_BIN="$PRIVATE_STAT_BIN"
CR6608_APPLY_LOCK="$TMP/apply.lock"
CR6608_UBUS_BIN="$BIN/ubus"
CR6608_IW_BIN="$BIN/iw"
CR6608_WIFI_BIN="$BIN/wifi"
CR6608_SETSID_BIN="$BIN/setsid-not-present"
export PATH CR6608_TEST_WIRELESS CR6608_WIFI_MIN_TIMEOUT
export CR6608_DASHBOARD_CACHE_STATE_LIB CR6608_WIFI_WATCHDOG_DIR CR6608_APPLY_LOCK
export CR6608_PRIVATE_RUNTIME_LIB CR6608_PRIVATE_RUNTIME_ROOT CR6608_PRIVATE_EXPECTED_UID
export CR6608_PRIVATE_STAT_BIN
export CR6608_UBUS_BIN CR6608_IW_BIN CR6608_WIFI_BIN CR6608_SETSID_BIN

"$RUNTIME" "$HEALTHY_TIMEOUT" "$TMP/backup-wireless" all ||
	fail "matching netifd section and hostapd object were rejected"
"$RUNTIME" --verify-only "$HEALTHY_TIMEOUT" all ||
	fail "verify-only mode rejected a healthy restored runtime"
CR6608_TEST_MODE=mesh CR6608_TEST_IW_TYPE='mesh point' \
	"$RUNTIME" --verify-only "$HEALTHY_TIMEOUT" all ||
	fail "healthy 802.11s 'type mesh point' runtime was rejected"
"$RUNTIME" "$HEALTHY_TIMEOUT" "$TMP/absent-auto-backup" all ||
	fail "private automatic backup path rejected a healthy reload"
! find "$CR6608_PRIVATE_RUNTIME_ROOT/safe-wifi" -maxdepth 1 \
	-type f -name 'wireless-backup.*' -print -quit | grep -q . ||
	fail "successful reload retained its private automatic backup"
[ "$RUN_FAILURE_MATRIX" = 1 ] || {
	printf 'safe_wifi_reload_test=pass (MSYS healthy path; Linux failure matrix required)\n'
	exit 0
}

printf 'config wifi-device broken-radio\n' >"$TMP/etc/config/wireless"
set +e
CR6608_RUNTIME_SECTION=guest0 "$RUNTIME" 1 "$TMP/backup-wireless" all
wrong_section_rc=$?
set -e
[ "$wrong_section_rc" -ne 0 ] ||
	fail "an unrelated AP interface satisfied the configured wifinet0 section"
[ "$wrong_section_rc" = 1 ] ||
	fail "wrong-section rollback restored the file but did not verify the restored runtime"
cmp -s "$TMP/backup-wireless" "$TMP/etc/config/wireless" ||
	fail "wrong-section failure did not restore the previous plain wireless file"

printf 'config wifi-device broken-radio\n' >"$TMP/etc/config/wireless"
set +e
CR6608_HOSTAPD_OK=0 "$RUNTIME" 1 "$TMP/backup-wireless" all
missing_hostapd_rc=$?
set -e
[ "$missing_hostapd_rc" -ne 0 ] ||
	fail "a configured AP without its hostapd ubus object was accepted"
[ "$missing_hostapd_rc" = 1 ] ||
	fail "missing-hostapd rollback did not verify the restored runtime"
cmp -s "$TMP/backup-wireless" "$TMP/etc/config/wireless" ||
	fail "missing-hostapd failure did not restore the previous plain wireless file"

printf 'config wifi-device broken-radio\n' >"$TMP/etc/config/wireless"
set +e
CR6608_HOSTAPD_STATE=DISABLED "$RUNTIME" 1 "$TMP/backup-wireless" all
disabled_hostapd_rc=$?
set -e
[ "$disabled_hostapd_rc" -ne 0 ] ||
	fail "a hostapd object without ENABLED runtime state was accepted"
[ "$disabled_hostapd_rc" = 1 ] ||
	fail "disabled-hostapd rollback did not verify the restored runtime"
cmp -s "$TMP/backup-wireless" "$TMP/etc/config/wireless" ||
	fail "disabled-hostapd failure did not restore the previous plain wireless file"

printf 'config wifi-device broken-radio\n' >"$TMP/etc/config/wireless"
set +e
CR6608_RUNTIME_CHANNEL=6 "$RUNTIME" 1 "$TMP/backup-wireless" all
stale_runtime_rc=$?
set -e
[ "$stale_runtime_rc" = 1 ] ||
	fail "stale channel runtime was not rejected and restored with verified state"
cmp -s "$TMP/backup-wireless" "$TMP/etc/config/wireless" ||
	fail "stale-channel failure did not restore the previous plain wireless file"

printf 'safe_wifi_reload_tests=pass\n'
