#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HEAL="$ROOT/files/etc/uci-defaults/93-cr6608-smartap-heal"
CHANNEL_DEFAULTS="$ROOT/files/etc/uci-defaults/95-cr6608-unique-channel"
AUTOCHANNEL="$ROOT/files/usr/sbin/smartap-autochannel"
PRIVATE_STAT_BIN=stat
case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW*|MSYS*|CYGWIN*) PRIVATE_STAT_BIN="$ROOT/tests/helpers/cr6608-private-stat-msys" ;;
esac

fail() {
	printf 'uci_sync_runtime=fail: %s\n' "$*" >&2
	exit 1
}

for source in "$HEAL" "$CHANNEL_DEFAULTS" "$AUTOCHANNEL"; do
	[ -s "$source" ] || fail "missing $source"
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-uci-sync.XXXXXX")"
BIN="$TMP/bin"
STATE="$TMP/state"
VALUES="$STATE/values"
LOG="$STATE/uci.log"
WIFI_COUNT="$STATE/wifi-count"
AUTO_RUNTIME="$TMP/smartap-autochannel"
PRIVATE_RUNTIME="$TMP/private-runtime"
APPLY_LOCK="$TMP/cr6608-apply.lock"
LOCK_OBSERVED="$STATE/lock-observed"
WIRELESS_CONFIG="$TMP/wireless.conf"
CACHE_STATE="$TMP/cache-state"
LIVE_LOCK_PID=""
mkdir -p "$BIN" "$VALUES"

cp "$AUTOCHANNEL" "$AUTO_RUNTIME"
chmod 0700 "$AUTO_RUNTIME"

cat >"$CACHE_STATE" <<'EOF'
cr6608_dashboard_cache_mutation_begin() { return 0; }
cr6608_dashboard_cache_mutation_finish() { return 0; }
EOF

cleanup() {
	[ -z "$LIVE_LOCK_PID" ] || kill "$LIVE_LOCK_PID" 2>/dev/null || true
	rm -rf "$TMP"
}
trap cleanup EXIT
trap 'cleanup; exit 130' HUP INT TERM

cat >"$BIN/uci" <<'EOF'
#!/bin/sh
set -eu
[ "${1:-}" = "-q" ] && shift
action="${1:-}"
[ "$#" -gt 0 ] && shift
values="$CR6608_TEST_UCI_STATE/values"
log="$CR6608_TEST_UCI_STATE/uci.log"
mkdir -p "$values"

case "$action" in
	get)
		key="${1:-}"
		[ -f "$values/$key" ] || exit 1
		cat "$values/$key"
		;;
	show)
		prefix="${1:-}."
		found=0
		for path in "$values"/"$prefix"*; do
			[ -f "$path" ] || continue
			key="${path##*/}"
			value="$(cat "$path")"
			printf "%s='%s'\n" "$key" "$value"
			found=1
		done
		[ "$found" = 1 ]
		;;
	set)
		assignment="${1:-}"
		key="${assignment%%=*}"
		value="${assignment#*=}"
		[ -n "$key" ] && [ "$key" != "$assignment" ] || exit 1
		printf '%s\n' "$value" >"$values/$key"
		printf 'set:%s=%s\n' "$key" "$value" >>"$log"
		;;
	delete)
		key="${1:-}"
		rm -f "$values/$key"
		printf 'delete:%s\n' "$key" >>"$log"
		;;
	commit)
		printf 'commit:%s\n' "${1:-}" >>"$log"
		;;
	revert)
		printf 'revert:%s\n' "${1:-}" >>"$log"
		;;
	*)
		exit 1
		;;
esac
EOF

cat >"$BIN/logger" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$BIN/iw" <<'EOF'
#!/bin/sh
if [ "${CR6608_TEST_ASSERT_LOCK:-0}" = 1 ]; then
	read lock_pid lock_start <"$CR6608_APPLY_LOCK/owner" || exit 1
	case "$lock_pid:$lock_start" in *[!0-9:]*|:|*:) exit 1 ;; esac
	live_start="$(awk '{print $22}' "/proc/$lock_pid/stat" 2>/dev/null)"
	[ -n "$live_start" ] && [ "$live_start" = "$lock_start" ] || exit 1
	: >"$CR6608_TEST_LOCK_OBSERVED"
fi
case "$*" in
	'phy phy0 channels') printf '* 2462 MHz [11] (30.0 dBm)\n' ;;
	'phy phy1 channels') printf '* 5745 MHz [149] (30.0 dBm)\n' ;;
	*) exit 1 ;;
esac
EOF

cat >"$BIN/iwinfo" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$BIN/wifi" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$CR6608_TEST_WIFI_COUNT" ] || count="$(cat "$CR6608_TEST_WIFI_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" >"$CR6608_TEST_WIFI_COUNT"
if [ "${CR6608_TEST_WIFI_FAIL_FIRST:-0}" = 1 ] && [ "$count" -eq 1 ]; then
	exit 1
fi
exit 0
EOF

chmod 0700 "$BIN/uci" "$BIN/logger" "$BIN/iw" "$BIN/iwinfo" "$BIN/wifi"
printf 'config wifi-device radio0\nconfig wifi-device radio1\n' >"$WIRELESS_CONFIG"
CR6608_TEST_UCI_STATE="$STATE"
CR6608_TEST_WIFI_COUNT="$WIFI_COUNT"
CR6608_APPLY_LOCK="$APPLY_LOCK"
CR6608_TEST_LOCK_OBSERVED="$LOCK_OBSERVED"
CR6608_SAFE_WIFI_RELOAD="$BIN/wifi"
CR6608_WIRELESS_CONFIG="$WIRELESS_CONFIG"
CR6608_DASHBOARD_CACHE_STATE_LIB="$CACHE_STATE"
CR6608_PRIVATE_RUNTIME_LIB="$ROOT/files/usr/libexec/cr6608-private-runtime"
CR6608_PRIVATE_RUNTIME_ROOT="$PRIVATE_RUNTIME"
CR6608_PRIVATE_EXPECTED_UID="$(id -u)"
CR6608_PRIVATE_STAT_BIN="$PRIVATE_STAT_BIN"
export CR6608_TEST_UCI_STATE CR6608_TEST_WIFI_COUNT CR6608_APPLY_LOCK
export CR6608_TEST_LOCK_OBSERVED CR6608_SAFE_WIFI_RELOAD CR6608_WIRELESS_CONFIG
export CR6608_DASHBOARD_CACHE_STATE_LIB CR6608_PRIVATE_RUNTIME_LIB
export CR6608_PRIVATE_RUNTIME_ROOT CR6608_PRIVATE_EXPECTED_UID
export CR6608_PRIVATE_STAT_BIN
PATH="$BIN:$PATH"
export PATH

reset_state() {
	rm -rf "$VALUES"
	mkdir -p "$VALUES"
	: >"$LOG"
	rm -f "$WIFI_COUNT" "$PRIVATE_RUNTIME/autochannel/status.json" "$LOCK_OBSERVED"
	rm -rf "$APPLY_LOCK"
	unset CR6608_TEST_WIFI_FAIL_FIRST || true
	unset CR6608_TEST_ASSERT_LOCK || true
}

put() {
	printf '%s\n' "$2" >"$VALUES/$1"
}

value() {
	[ -f "$VALUES/$1" ] || return 1
	cat "$VALUES/$1"
}

expect_value() {
	actual="$(value "$1")" || fail "missing UCI value $1"
	[ "$actual" = "$2" ] || fail "$1 expected '$2', got '$actual'"
}

expect_status() {
	expected="$1"
	shift
	set +e
	"$@"
	actual=$?
	set -e
	[ "$actual" -eq "$expected" ] ||
		fail "expected status $expected from $*, got $actual"
}

# 93: remove only distance=auto, preserve existing values, seed only absences,
# and avoid a second commit when a repeated run has nothing left to heal.
reset_state
put smartap.quick quicksettings
put wireless.radio0 wifi-device
put wireless.radio1 wifi-device
put wireless.wifinet0 wifi-iface
put wireless.wifinet1 wifi-iface
put wireless.radio0.distance auto
put wireless.radio1.distance 42
put wireless.radio1.ldpc 0
put wireless.radio1.legacy_rates 1
put wireless.wifinet0.isolate 1
put wireless.wifinet1.wmm 0
expect_status 0 sh "$HEAL"
[ ! -e "$VALUES/wireless.radio0.distance" ] || fail "radio0 distance=auto survived heal"
expect_value wireless.radio1.distance 42
expect_value wireless.radio0.ldpc 1
expect_value wireless.radio1.ldpc 0
expect_value wireless.radio0.legacy_rates 0
expect_value wireless.radio1.legacy_rates 1
expect_value wireless.wifinet0.wmm 1
expect_value wireless.wifinet0.isolate 1
expect_value wireless.wifinet1.wmm 0
expect_value wireless.wifinet1.isolate 0
[ "$(grep -Fc 'commit:wireless' "$LOG")" -eq 1 ] ||
	fail "first heal did not commit wireless exactly once"
expect_status 0 sh "$HEAL"
[ "$(grep -Fc 'commit:wireless' "$LOG")" -eq 1 ] ||
	fail "idempotent heal committed unchanged wireless state"

# 95: an existing operator channel is retained; a genuinely absent channel is seeded.
reset_state
put wireless.radio0 wifi-device
put wireless.radio0.channel 6
expect_status 0 sh "$CHANNEL_DEFAULTS"
expect_value wireless.radio0.channel 6
! grep -Fq 'commit:wireless' "$LOG" || fail "channel default committed over retained channel"
rm -f "$VALUES/wireless.radio0.channel"
expect_status 0 sh "$CHANNEL_DEFAULTS"
expect_value wireless.radio0.channel 11
[ "$(grep -Fc 'commit:wireless' "$LOG")" -eq 1 ] ||
	fail "missing channel was not committed exactly once"

seed_autochannel_state() {
	put smartap.autochannel.enabled 1
	put smartap.quick quicksettings
	put wireless.radio0 wifi-device
	put wireless.radio1 wifi-device
	put wireless.radio0.channel "$1"
	put wireless.radio1.channel "$2"
	put cr6608quick.default quick
	put cr6608quick.default.channel24 "$3"
	put cr6608quick.default.channel5 "$4"
	put smartap.quick.ch24 "$5"
	put smartap.quick.ch5 "$6"
}

# A live unrelated owner blocks the operation without changing any UCI package.
reset_state
seed_autochannel_state 1 36 6 44 9 161
sleep 30 &
LIVE_LOCK_PID=$!
live_lock_start="$(awk '{print $22}' "/proc/$LIVE_LOCK_PID/stat" 2>/dev/null)"
[ -n "$live_lock_start" ] || fail "could not read the live test lock owner starttime"
mkdir "$APPLY_LOCK"
printf '%s %s\n' "$LIVE_LOCK_PID" "$live_lock_start" >"$APPLY_LOCK/owner"
expect_status 5 sh "$AUTO_RUNTIME"
expect_value wireless.radio0.channel 1
expect_value wireless.radio1.channel 36
expect_value cr6608quick.default.channel24 6
expect_value cr6608quick.default.channel5 44
expect_value smartap.quick.ch24 9
expect_value smartap.quick.ch5 161
[ "$(cat "$APPLY_LOCK/owner")" = "$LIVE_LOCK_PID $live_lock_start" ] ||
	fail "auto-channel replaced another live transaction owner"
! grep -Fq 'commit:' "$LOG" || fail "blocked auto-channel committed UCI changes"
kill "$LIVE_LOCK_PID" 2>/dev/null || true
wait "$LIVE_LOCK_PID" 2>/dev/null || true
LIVE_LOCK_PID=""
rm -f "$APPLY_LOCK/owner"
rmdir "$APPLY_LOCK"

# A lock owned by an ancestor is the same transaction (the dashctl manual path);
# the child may run but must leave its ancestor's owner record untouched.
reset_state
seed_autochannel_state 11 149 1 36 6 44
ancestor_start="$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null)"
[ -n "$ancestor_start" ] || fail "could not read the ancestor lock owner starttime"
mkdir "$APPLY_LOCK"
printf '%s %s\n' "$$" "$ancestor_start" >"$APPLY_LOCK/owner"
expect_status 0 sh "$AUTO_RUNTIME"
expect_value cr6608quick.default.channel24 11
expect_value cr6608quick.default.channel5 149
expect_value smartap.quick.ch24 11
expect_value smartap.quick.ch5 149
[ "$(cat "$APPLY_LOCK/owner")" = "$$ $ancestor_start" ] ||
	fail "nested auto-channel removed or replaced its ancestor lock"
rm -f "$APPLY_LOCK/owner"
rmdir "$APPLY_LOCK"

# A stale owner is reclaimed. Successful selection records PID STARTTIME while
# running, then cleans the lock and updates all three channel stores.
reset_state
seed_autochannel_state 1 36 6 44 9 161
mkdir "$APPLY_LOCK"
printf '999999 1\n' >"$APPLY_LOCK/owner"
CR6608_TEST_ASSERT_LOCK=1
export CR6608_TEST_ASSERT_LOCK
expect_status 0 sh "$AUTO_RUNTIME"
expect_value wireless.radio0.channel 11
expect_value wireless.radio1.channel 149
expect_value cr6608quick.default.channel24 11
expect_value cr6608quick.default.channel5 149
expect_value smartap.quick.ch24 11
expect_value smartap.quick.ch5 149
[ "$(grep -Fc 'commit:wireless' "$LOG")" -eq 1 ] ||
	fail "successful auto-channel did not commit wireless exactly once"
[ "$(grep -Fc 'commit:cr6608quick' "$LOG")" -eq 1 ] ||
	fail "successful auto-channel did not commit cr6608quick exactly once"
[ "$(grep -Fc 'commit:smartap' "$LOG")" -eq 1 ] ||
	fail "successful auto-channel did not commit smartap exactly once"
[ "$(cat "$WIFI_COUNT")" -eq 1 ] || fail "wireless channel change did not reload once"
[ -e "$LOCK_OBSERVED" ] || fail "auto-channel did not expose a live PID STARTTIME owner"
[ ! -e "$APPLY_LOCK" ] || fail "successful auto-channel did not clean its apply lock"

# A reload failure restores the old live pair into all three UCI packages.
reset_state
seed_autochannel_state 1 36 6 44 9 161
CR6608_TEST_WIFI_FAIL_FIRST=1
export CR6608_TEST_WIFI_FAIL_FIRST
expect_status 1 sh "$AUTO_RUNTIME"
expect_value wireless.radio0.channel 1
expect_value wireless.radio1.channel 36
expect_value cr6608quick.default.channel24 1
expect_value cr6608quick.default.channel5 36
expect_value smartap.quick.ch24 1
expect_value smartap.quick.ch5 36
[ "$(grep -Fc 'commit:wireless' "$LOG")" -eq 2 ] ||
	fail "failed auto-channel did not commit apply and restore wireless states"
[ "$(grep -Fc 'commit:cr6608quick' "$LOG")" -eq 2 ] ||
	fail "failed auto-channel did not commit apply and restore cr6608quick states"
[ "$(grep -Fc 'commit:smartap' "$LOG")" -eq 2 ] ||
	fail "failed auto-channel did not commit apply and restore smartap states"
[ "$(cat "$WIFI_COUNT")" -eq 2 ] || fail "failed apply did not reload restored channels"
[ ! -e "$APPLY_LOCK" ] || fail "failed auto-channel did not clean its apply lock"

# Stale metadata alone is healed without disrupting already-correct radios.
reset_state
seed_autochannel_state 11 149 1 36 6 44
expect_status 0 sh "$AUTO_RUNTIME"
expect_value cr6608quick.default.channel24 11
expect_value cr6608quick.default.channel5 149
expect_value smartap.quick.ch24 11
expect_value smartap.quick.ch5 149
! grep -Fq 'commit:wireless' "$LOG" ||
	fail "metadata-only synchronization committed wireless"
[ "$(grep -Fc 'commit:cr6608quick' "$LOG")" -eq 1 ] ||
	fail "metadata-only synchronization did not commit cr6608quick once"
[ "$(grep -Fc 'commit:smartap' "$LOG")" -eq 1 ] ||
	fail "metadata-only synchronization did not commit smartap once"
[ ! -e "$WIFI_COUNT" ] || fail "metadata-only synchronization reloaded Wi-Fi"
[ ! -e "$APPLY_LOCK" ] || fail "metadata-only synchronization did not clean its apply lock"

printf 'uci_sync_runtime=pass\n'
