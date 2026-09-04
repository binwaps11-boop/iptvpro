#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SEED="$ROOT/cr6608.seed.config"
QUICK="$ROOT/files/etc/config/cr6608quick"
USTEER="$ROOT/files/etc/config/usteer"
DEFAULTS="$ROOT/files/etc/uci-defaults/99-cr6608-runtime-services"
VIEW="$ROOT/files/www/luci-static/resources/view/cr6608/quicksettings.js"
CGI="$ROOT/files/www/cgi-bin/cr6608-quick-apply"
EXECUTOR="$ROOT/files/usr/sbin/cr6608-quicksettings-apply"
ACL="$ROOT/files/usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json"
SAFE_APPLY="$ROOT/files/usr/sbin/cr6608-safe-apply"
LUCI_FEED_PATCH="$ROOT/patches/993-luci-wireless-preserve-configured-txpower.patch"
PYTHON_BIN="${PYTHON_BIN:-python3}"

fail() { printf 'roaming/steering contract failed: %s\n' "$*" >&2; exit 1; }

assignment_has_word() {
	_ahw_file="$1"
	_ahw_name="$2"
	_ahw_wanted="$3"
	_ahw_value="$(sed -n "s/^${_ahw_name}=//p" "$_ahw_file" | sed -n '1p')"
	case "$_ahw_value" in
		\'*\') _ahw_value="${_ahw_value#\'}"; _ahw_value="${_ahw_value%\'}" ;;
		\"*\") _ahw_value="${_ahw_value#\"}"; _ahw_value="${_ahw_value%\"}" ;;
		*) return 1 ;;
	esac
	for _ahw_word in $_ahw_value; do
		[ "$_ahw_word" != "$_ahw_wanted" ] || return 0
	done
	return 1
}

for symbol in CONFIG_PACKAGE_usteer=y CONFIG_PACKAGE_luci-app-usteer=y \
	CONFIG_PACKAGE_wpad-openssl=y; do
	grep -Fqx "$symbol" "$SEED" || fail "seed lacks $symbol"
done

for null_guard in \
	'Hosts = data[1] || {};' \
	'Remotehosts = data[2] || {};' \
	'Remoteinfo = data[3] || {};' \
	'Localinfo = data[4] || {};' \
	'Clients = data[5] || {};' \
	'WifiNetworks = data[6] || [];' \
	"Initscript = data[7] || '';"; do
	grep -Fq "$null_guard" "$LUCI_FEED_PATCH" || \
		fail "LuCI usteer stopped-service guard lacks: $null_guard"
done

grep -Fq "option smart_connect '0'" "$QUICK" || fail 'Smart Connect is not off by default'
grep -Fq "option fast_transition '0'" "$QUICK" || fail '802.11r is not off by default'
for safe_default in \
	"option enabled '0'" \
	"option local_mode '1'" \
	"option assoc_steering '0'" \
	"option aggressiveness '1'" \
	"option min_connect_snr '0'" \
	"option min_snr '0'" \
	"option load_kick_enabled '0'" \
	"option band_steering_interval '0'" \
	"option link_measurement_interval '0'"; do
	grep -Fq "$safe_default" "$USTEER" || fail "unsafe usteer default: $safe_default"
done
grep -Fq '/etc/init.d/usteer enable || exit 1' "$DEFAULTS" || fail 'usteer boot state is not managed'
grep -Fq 'if [ "$(uci -q get usteer.main.enabled 2>/dev/null)" = "1" ]; then' "$DEFAULTS" || \
	fail 'disabled usteer is started as a fatal first-boot action'

grep -Fq "'ssid5','smart_connect'" "$VIEW" || fail 'LuCI payload omits Smart Connect'
grep -Fq "'fast_transition','channel24'" "$VIEW" || fail 'LuCI payload omits 802.11r'
grep -Fq "form.Flag, 'smart_connect'" "$VIEW" || fail 'LuCI lacks Smart Connect control'
grep -Fq "form.Flag, 'fast_transition'" "$VIEW" || fail 'LuCI lacks 802.11r control'
grep -Fq "o.depends('smart_connect', '0')" "$VIEW" || fail 'separate 5 GHz SSID is not hidden under Smart Connect'
grep -Fq "smart_connect: '1', security: 'wpa2'" "$VIEW" || fail '802.11r UI is not protected-mode scoped'

grep -Fq 'ssid5 smart_connect fast_transition channel24' "$CGI" || fail 'CGI scalar validation omits roaming controls'
grep -Fq '[ "$smart_connect" = "1" ] && ssid5="$ssid"' "$CGI" || fail 'CGI does not enforce one Smart Connect SSID'
grep -Fq 'Smart Connect requires both radios enabled' "$CGI" || fail 'CGI accepts single-radio Smart Connect'
grep -Fq '802.11r requires protected WPA2/WPA3 security' "$CGI" || fail 'CGI accepts FT on an open network'
grep -Fq '802.11s mesh supports SAE or open security' "$CGI" || fail 'CGI accepts misleading mesh WPA2/mixed security'
grep -Fq 'json_add_string smart_connect "$smart_connect"' "$CGI" || fail 'CGI drops Smart Connect before the executor'
grep -Fq 'json_add_string fast_transition "$fast_transition"' "$CGI" || fail 'CGI drops 802.11r before the executor'
assignment_has_word "$CGI" WRITE_PACKAGES usteer ||
	fail 'CGI authentication does not authorize the usteer transaction'
"$PYTHON_BIN" -I -B - "$ACL" <<'PY' || fail 'LuCI ACL cannot read/write the steering policy'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
grant = document.get("luci-app-cr6608-quicksettings", {})
for mode in ("read", "write"):
    packages = grant.get(mode, {}).get("uci")
    if not isinstance(packages, list) or "usteer" not in packages:
        raise SystemExit(1)
PY

assignment_has_word "$EXECUTOR" UCI_PACKAGES usteer || fail 'usteer is outside the transactional UCI set'
grep -Fq 'uci set wireless."$sid".bss_transition='"'"'1'"'"'' "$EXECUTOR" || fail '802.11v BSS transition is not enabled'
! grep -Fq 'uci set wireless."$sid".ieee80211v=' "$EXECUTOR" || fail 'executor relies on unsupported ieee80211v UCI'
grep -Fq 'uci set usteer.main.assoc_steering='"'"'0'"'"'' "$EXECUTOR" || fail 'association rejection is enabled'
grep -Fq 'uci set usteer.main.aggressiveness='"'"'1'"'"'' "$EXECUTOR" || fail 'usteer may send an aggressive disassociation request'
grep -Fq 'uci set usteer.main.load_kick_enabled='"'"'0'"'"'' "$EXECUTOR" || fail 'load kicking is enabled'
grep -Fq 'uci set usteer.main.min_snr='"'"'0'"'"'' "$EXECUTOR" || fail 'low-SNR kicking is enabled'
grep -Fq 'uci set usteer.main.band_steering_interval='"'"'120000'"'"'' "$EXECUTOR" || fail 'conservative band-steering interval is missing'
grep -Fq 'uci add_list usteer.main.ssid_list="$shared_ssid"' "$EXECUTOR" || fail 'usteer is not restricted to the shared SSID'
grep -Fq 'apply_usteer_runtime || failed=1' "$EXECUTOR" || fail 'rollback does not restore live usteer state'
grep -Fq 'apply_usteer_runtime || service_failed=1' "$EXECUTOR" || fail 'live usteer state is not applied'
grep -A18 -F 'apply_usteer_runtime() {' "$EXECUTOR" | grep -Fq '"$INITD_DIR/usteer" stop' || \
	fail 'disabling Smart Connect cannot stop usteer without a false restart failure'
safe_restore_block="$(sed -n '/^restore_loaded() {/,/^}/p' "$SAFE_APPLY")"
safe_revert_words="$(printf '%s\n' "$safe_restore_block" |
	sed -n 's/^[[:space:]]*for pkg in \(.*\); do$/\1/p' | sed -n '1p')"
found_usteer=0
for safe_package in $safe_revert_words; do
	[ "$safe_package" != usteer ] || found_usteer=1
done
[ "$found_usteer" = 1 ] || fail 'persistent rollback does not revert usteer staging'
grep -Fq '/etc/init.d/usteer restart' "$SAFE_APPLY" || fail 'persistent rollback leaves live usteer state stale'

grep -Fq 'clear_fast_transition "$sid"' "$EXECUTOR" || fail 'security changes retain stale FT state'
grep -Fq 'uci set wireless."$sid".ieee80211w='"'"'1'"'"'' "$EXECUTOR" || fail 'WPA2/mixed PMF policy is absent'
grep -Fq 'uci set wireless."$sid".ieee80211w='"'"'2'"'"'' "$EXECUTOR" || fail 'SAE does not require PMF'
grep -Fq 'uci -q delete wireless."$sid".ieee80211w' "$EXECUTOR" || fail 'open security can retain stale PMF'
grep -Fq 'uci set "wireless.${sid}.ieee80211r=1"' "$EXECUTOR" || fail 'explicit FT cannot be applied'
grep -Fq '802.11r requires Smart Connect and one shared SSID' "$EXECUTOR" || fail 'executor accepts FT across different SSIDs'
grep -Fq '802.11r requires protected WPA2/WPA3 security' "$EXECUTOR" || fail 'executor accepts FT on open Wi-Fi'
grep -Fq '802.11s mesh requires SAE or open security' "$EXECUTOR" || fail 'executor accepts mesh WPA2/mixed security'

mesh_gate="$(grep -n '802.11s mesh requires SAE or open security' "$EXECUTOR" | sed -n '1s/:.*//p')"
transaction="$(grep -n 'transaction_begin ||' "$EXECUTOR" | sed -n '1s/:.*//p')"
[ -n "$mesh_gate" ] && [ -n "$transaction" ] && [ "$mesh_gate" -lt "$transaction" ] || \
	fail 'mesh security validation occurs after configuration mutation'

printf 'roaming_steering_contract=pass\n'
