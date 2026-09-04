#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASHCTL="$ROOT/files/www/cgi-bin/dashctl"

fail() {
	printf 'dashctl_wifi_apply_test=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$DASHCTL" ] || fail "missing $DASHCTL"

plain_block="$(sed -n '/^capture_wireless_plain_backup()/,/^}/p' "$DASHCTL")"
printf '%s\n' "$plain_block" | \
	grep -Fq 'wireless_plain_backup="$(cr6608_private_mktemp "$DASHCTL_REQUEST_DIR" wireless)"' ||
	fail "plain wireless backup is not created in private request storage"
! printf '%s\n' "$plain_block" | grep -Fq '/tmp/cr6608-dashctl-wireless' ||
	fail "plain wireless backup still uses predictable public tmp storage"
printf '%s\n' "$plain_block" | grep -Fq 'chmod 0600 "$wireless_plain_backup"' ||
	fail "plain wireless backup is not restricted to mode 0600"
printf '%s\n' "$plain_block" | grep -Fq 'cp -f /etc/config/wireless "$wireless_plain_backup"' ||
	fail "wireless is not copied as a plain file before mutation"
printf '%s\n' "$plain_block" | grep -Fq "config[[:space:]]+wifi-(device|iface)" ||
	fail "plain wireless backup is not distinguished from an archive"

verify_block="$(sed -n '/^verified_wifi_reload()/,/^}/p' "$DASHCTL")"
printf '%s\n' "$verify_block" | grep -Fq '/usr/sbin/cr6608-safe-wifi-reload 30' ||
	fail "runtime verifier is not invoked"
printf '%s\n' "$verify_block" | grep -Fq '"$wireless_plain_backup" "$_verified_wifi_scope"' ||
	fail "runtime verifier does not receive the plain wireless backup"
printf '%s\n' "$verify_block" | grep -Fq 'cleanup_wireless_plain_backup' ||
	fail "temporary wireless backup is not cleaned after verification"

action_verify_block="$(sed -n '/^action_wifi_reload()/,/^}/p' "$DASHCTL")"
printf '%s\n' "$action_verify_block" | grep -Fq 'action_rollback_pending' ||
	fail "runtime verification failure does not trigger the guarded rollback"
printf '%s\n' "$action_verify_block" | grep -Fq 'hostapd runtime did not become ready' ||
	fail "runtime failure is not tied to radio/hostapd readiness"

release_block="$(sed -n '/^release_apply_lock()/,/^}/p' "$DASHCTL")"
printf '%s\n' "$release_block" | grep -Fq 'cleanup_wireless_plain_backup' ||
	fail "request exit does not clean a pending wireless backup"

save_block="$(sed -n '/^  save_wifi)/,/^  delete_wifi)/p' "$DASHCTL")"
printf '%s\n' "$save_block" | grep -Fq 'action_capture_wireless "Wireless"' ||
	fail "save_wifi does not snapshot wireless before editing"
printf '%s\n' "$save_block" | grep -Fq 'action_wifi_reload "Wireless" "Wi-Fi runtime verification failed" "$wifi_scope"' ||
	fail "save_wifi does not verify its affected radio runtime"

delete_block="$(sed -n '/^  delete_wifi)/,/^  save_dhcp_static|delete_dhcp_static)/p' "$DASHCTL")"
printf '%s\n' "$delete_block" | grep -Fq 'action_capture_wireless "Wireless"' ||
	fail "delete_wifi does not snapshot wireless before editing"
printf '%s\n' "$delete_block" | grep -Fq 'action_wifi_reload "Wireless" "Wi-Fi runtime verification failed" "$wifi_scope"' ||
	fail "delete_wifi does not verify its affected radio runtime"

radio_block="$(sed -n '/^  save_wifi_radio)/,/^  set_txpower)/p' "$DASHCTL")"
printf '%s\n' "$radio_block" | grep -Fq 'action_capture_wireless "Wi-Fi radio"' ||
	fail "save_wifi_radio does not capture a plain backup"
printf '%s\n' "$radio_block" | grep -Fq 'action_wifi_reload "Wi-Fi radio" "Wi-Fi runtime verification failed" "$wifi_scope"' ||
	fail "save_wifi_radio does not verify radio/hostapd runtime"
printf '%s\n' "$radio_block" | grep -Fq 'old_distance="$(uci -q get wireless."$radio".distance' ||
	fail "save_wifi_radio does not inspect the previous distance"
printf '%s\n' "$radio_block" | grep -Fq '[ "$old_distance" = "auto" ]' ||
	fail "save_wifi_radio does not recognize a legacy automatic distance"
printf '%s\n' "$radio_block" | grep -Fq 'uci -q delete wireless."$radio".distance' ||
	fail "save_wifi_radio does not delete an automatic distance without a numeric value"
printf '%s\n' "$radio_block" | grep -Fq 'in auto) channel=auto' ||
	fail "save_wifi_radio does not preserve an explicit Automatic channel"

country_guard_line="$(printf '%s\n' "$radio_block" | grep -nF 'if [ -n "$country" ] && [ "$country" != "$active_country" ]; then' | cut -d: -f1)"
channel_check_line="$(printf '%s\n' "$radio_block" | grep -nF 'wireless_channel_supported "$radio" "$channel"' | cut -d: -f1)"
[ -n "$country_guard_line" ] && [ -n "$channel_check_line" ] &&
	[ "$country_guard_line" -lt "$channel_check_line" ] ||
	fail "fixed-channel country changes are not rejected before old-domain channel validation"

txpower_block="$(sed -n '/^  set_txpower)/,/^  save_dnsmasq)/p' "$DASHCTL")"
printf '%s\n' "$txpower_block" | grep -Fq 'action_capture_wireless "TX Power"' ||
	fail "set_txpower does not capture a plain backup"
printf '%s\n' "$txpower_block" | grep -Fq 'action_wifi_reload "TX Power" "Wi-Fi runtime verification failed" all' ||
	fail "set_txpower does not verify both radios and hostapd runtimes"

for contract in \
	'action_capture_wireless "Auto optimize"' \
	'action_wifi_reload "Auto optimize" "Wi-Fi runtime verification failed" all' \
	'action_capture_wireless "Best Channel"' \
	'action_wifi_reload "Best Channel" "Wi-Fi runtime verification failed" "$channel_scope"' \
	'action_capture_wireless "Guest Wi-Fi"' \
	'action_wifi_reload "Guest Wi-Fi" "Wi-Fi runtime verification failed" "$guest_reload_scope"' \
	'action_wifi_reload "Raw OpenWrt UCI" "Wi-Fi runtime verification failed" all' \
	'verified_wifi_reload all || isolation_abort' \
	'verified_wifi_reload all || { emit false "Wi-Fi reload"'; do
	grep -Fq "$contract" "$DASHCTL" || fail "missing verified Wi-Fi apply contract: $contract"
done

guest_block="$(sed -n '/^  save_guest)/,/^  save_iptv)/p' "$DASHCTL")"
printf '%s\n' "$guest_block" | grep -Fq 'prev_guest_radio="$(uci -q get wireless.smartap_guest.device' ||
	fail "guest Wi-Fi does not inspect a retained BSS placement"
printf '%s\n' "$guest_block" | grep -Fq 'guest_reload_scope="all"' ||
	fail "guest Wi-Fi may leave a previous cross-radio BSS live"

[ "$(grep -cF 'wifi reload >/dev/null' "$DASHCTL")" -eq 0 ] ||
	fail "a direct wifi reload remains outside the full-backup restore path"
grep -Fq '"$royal_wifi_backup_dir/etc/config/wireless" all' "$DASHCTL" ||
	fail "Quick Setup does not pass an extracted plain wireless file"
if grep -Eq 'cr6608-safe-wifi-reload[^[:cntrl:]]*"\$backup"' "$DASHCTL"; then
	fail "a tar backup is passed to cr6608-safe-wifi-reload"
fi

printf 'dashctl_wifi_apply_tests=pass\n'
