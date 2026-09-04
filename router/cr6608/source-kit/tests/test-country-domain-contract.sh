#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASH="$ROOT/files/www/cgi-bin/dashctl"
CGI="$ROOT/files/www/cgi-bin/cr6608-quick-apply"
EXECUTOR="$ROOT/files/usr/sbin/cr6608-quicksettings-apply"
PATCH="$ROOT/patches/993-luci-wireless-preserve-configured-txpower.patch"
SCANNER="$ROOT/files/usr/bin/cr6608-country-power-scan"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$DASH" "$CGI" "$EXECUTOR" "$PATCH" "$SCANNER"; do
	[ -s "$file" ] || fail "missing country-domain input: $file"
done

line_of() {
	grep -nF "$2" "$1" | head -n 1 | cut -d: -f1
}

assert_before() {
	file="$1"
	first="$2"
	second="$3"
	message="$4"
	first_line="$(line_of "$file" "$first")"
	second_line="$(line_of "$file" "$second")"
	[ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ] ||
		fail "$message"
}

# Native LuCI: a changed country is legal only with every channel explicitly
# Automatic, then write/remove synchronizes every wifi-device.
grep -Fq "uci.sections('wireless', 'wifi-device')" "$PATCH" ||
	fail "LuCI country control does not enumerate every wifi-device"
grep -Fq ".filter(radio => String(radio.channel || '') !== 'auto')" "$PATCH" ||
	fail "LuCI country control does not reject a fixed channel on either radio"
grep -Fq "uci.set('wireless', radio['.name'], 'country', value)" "$PATCH" ||
	fail "LuCI country write is not synchronized across radios"
grep -Fq "uci.unset('wireless', radio['.name'], 'country')" "$PATCH" ||
	fail "LuCI country reset is not synchronized across radios"

# Quick CGI rejects a mixed pair before creating even the temporary request
# handoff, and a real domain change requires both radios on Automatic.
assert_before "$CGI" \
	'[ "$cc24" = "$cc5" ] || fail_request "409 Conflict" "country_domain"' \
	'REQUEST_FILE="$(mktemp' \
	"Quick CGI can create request state before rejecting mixed countries"
grep -Fq '[ "$c24" = "auto" ] && [ "$c5" = "auto" ]' "$CGI" ||
	fail "Quick CGI does not require Automatic on both radios for a domain change"

# The privileged executor repeats the trust-boundary validation before its
# transaction backup and before any UCI write.
assert_before "$EXECUTOR" \
	'[ "$country24" = "$country5" ] || { log "mixed regulatory countries rejected before apply"; return 2; }' \
	'transaction_begin ||' \
	"executor starts a transaction before rejecting mixed countries"
grep -Fq '[ "$ch24" = "auto" ] && [ "$ch5" = "auto" ]' "$EXECUTOR" ||
	fail "executor does not require Automatic on both radios for a domain change"

# Dashboard Quick Setup validates the shared domain before its transaction.
royal_block="$(sed -n '/^royal_params_valid()/,/^}/p' "$DASH")"
printf '%s\n' "$royal_block" | grep -Fq '[ "$country24" = "$country5" ]' ||
	fail "dashboard Quick Setup accepts two regulatory countries"
printf '%s\n' "$royal_block" | grep -Fq '[ "$ch24" = "auto" ] && [ "$ch5" = "auto" ]' ||
	fail "dashboard Quick Setup does not require both channels Automatic"
assert_before "$DASH" \
	'royal_params_valid || { emit false "Quick Setup" "Invalid settings"' \
	'royal_begin_transaction royal-save' \
	"dashboard Quick Setup can mutate before country-domain validation"

# The per-radio editor changes the shared country only after checking the other
# radio, reloads/verifies both radios, and rejects before its backup/mutation.
radio_block="$(sed -n '/^  save_wifi_radio)/,/^  set_txpower)/p' "$DASH")"
guard_line="$(printf '%s\n' "$radio_block" | grep -nF 'other_channel="$(uci -q get wireless."$other_radio".channel' | head -n 1 | cut -d: -f1)"
backup_line="$(printf '%s\n' "$radio_block" | grep -nF 'action_backup wifi-radio' | head -n 1 | cut -d: -f1)"
[ -n "$guard_line" ] && [ -n "$backup_line" ] && [ "$guard_line" -lt "$backup_line" ] ||
	fail "per-radio editor checks the other channel after mutation begins"
printf '%s\n' "$radio_block" | grep -Fq 'uci set wireless."$other_radio".country="$country"' ||
	fail "per-radio editor does not synchronize the other radio"
printf '%s\n' "$radio_block" | grep -Fq 'wifi_scope=all' ||
	fail "shared-country change does not verify both radio runtimes"

# Raw UCI cannot bypass the synchronized country writer.
raw_block="$(sed -n '/^  raw_uci_set|raw_uci_delete/,/^  save_dsa_vlan|delete_dsa_vlan)/p' "$DASH")"
country_guard_line="$(printf '%s\n' "$raw_block" | grep -nF '[ "$cfg" = "wireless" ] && [ "$opt" = "country" ]' | head -n 1 | cut -d: -f1)"
raw_backup_line="$(printf '%s\n' "$raw_block" | grep -nF 'action_backup raw-uci' | head -n 1 | cut -d: -f1)"
[ -n "$country_guard_line" ] && [ -n "$raw_backup_line" ] && [ "$country_guard_line" -lt "$raw_backup_line" ] ||
	fail "raw UCI country rejection occurs after mutation begins"

sh -n "$SCANNER" || fail "country-power scanner syntax"
grep -Fq 'lock="$COUNTRY_RUNTIME_DIR/lock"' "$SCANNER" ||
	fail "country-power scanner lock is not private"
grep -Fq 'RESTORE_WIFI_RELOAD=failed after retry' "$SCANNER" ||
	fail "country-power scanner hides a failed regulatory restore"

case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW*|MSYS*|CYGWIN*) ;;
	*)
		country_restore_retry_test() (
			tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-country-restore.XXXXXX")" || exit 1
			trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
			mkdir -p "$tmp/bin"
			printf 'xiaomi,mi-router-cr6608\n' >"$tmp/board"
			cat >"$tmp/bin/iw" <<'EOF'
#!/bin/sh
case "$*" in
	'reg set US') exit 0 ;;
	'reg get') printf 'country US: DFS-FCC\n' ;;
	*) exit 0 ;;
esac
EOF
			cat >"$tmp/bin/iwinfo" <<'EOF'
#!/bin/sh
exit 0
EOF
			cat >"$tmp/bin/ubus" <<'EOF'
#!/bin/sh
printf '{"results":[{"iso3166":"US"}]}\n'
EOF
			cat >"$tmp/bin/jsonfilter" <<'EOF'
#!/bin/sh
printf 'US\n'
EOF
			cat >"$tmp/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
			cat >"$tmp/bin/wifi" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$CR6608_TEST_WIFI_COUNT" ] || count="$(cat "$CR6608_TEST_WIFI_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" >"$CR6608_TEST_WIFI_COUNT"
exit 1
EOF
			chmod 0700 "$tmp/bin"/*
			if PATH="$tmp/bin:$PATH" \
			   CR6608_PRIVATE_RUNTIME_LIB="$ROOT/files/usr/libexec/cr6608-private-runtime" \
			   CR6608_PRIVATE_RUNTIME_ROOT="$tmp/private" \
			   CR6608_PRIVATE_EXPECTED_UID="$(id -u)" \
			   CR6608_BOARD_NAME_FILE="$tmp/board" \
			   CR6608_TEST_WIFI_COUNT="$tmp/wifi-count" \
			   sh "$SCANNER" --probe-all >/dev/null 2>&1; then
				exit 2
			fi
			[ "$(cat "$tmp/wifi-count" 2>/dev/null)" = 2 ] || exit 3
			[ ! -e "$tmp/private/country-power-scan/lock" ] || exit 4
			printf 'country_restore_retry=pass\n'
		)
		[ "$(country_restore_retry_test)" = country_restore_retry=pass ] ||
			fail "failed regulatory restore was not retried and surfaced"
		;;
esac

printf 'country_domain_contract=pass\n'
