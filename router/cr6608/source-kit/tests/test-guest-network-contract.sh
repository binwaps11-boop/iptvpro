#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASH="$ROOT/files/www/cgi-bin/dashctl"

fail() { printf 'guest network contract failed: %s\n' "$*" >&2; exit 1; }

for marker in \
	'Router mode required' \
	'guest_security' \
	'wpa2|wpa3|mixed|owe' \
	'valid_wpa_key "$gpass"' \
	'[ "$(uci -q get network.wan.ipv6 2>/dev/null)" = "auto" ] && guest_ipv6=1' \
	"network.guest.ip6assign='64'" \
	'uci -q delete network.guest.ip6assign' \
	"dhcp.guest.dhcpv6='server'" \
	"dhcp.guest.dhcpv6='disabled'" \
	"firewall.smartap_guest='zone'" \
	"firewall.smartap_guest_dhcp='rule'" \
	"firewall.smartap_guest_dns='rule'" \
	"firewall.smartap_guest_dhcpv6='rule'" \
	"firewall.smartap_guest_icmpv6='rule'" \
	"firewall.smartap_guest_wan='forwarding'" \
	"firewall.smartap_guest_wan.src='guest'" \
	"firewall.smartap_guest_wan.dest='wan'" \
	"wireless.smartap_guest.encryption='owe'" \
	"wireless.smartap_guest.ieee80211w='2'" \
	'uci -q delete wireless.smartap_guest.key' \
	'[ "$gtype" = "wifi-iface" ]' \
	'uci -q delete wireless.smartap_guest' \
	'uci -q delete network.guest' \
	'uci -q delete dhcp.guest'; do
	grep -Fq "$marker" "$DASH" || fail "missing $marker"
done

! grep -Fq "if ! uci show firewall | grep -q \"name='guest'\"" "$DASH" || \
	fail 'legacy incomplete anonymous guest zone still exists'

router_gate="$(grep -n 'Router mode required' "$DASH" | sed -n '1s/:.*//p')"
backup="$(grep -n 'action_backup guest' "$DASH" | sed -n '1s/:.*//p')"
password_gate="$(grep -n 'valid_wpa_key "$gpass"' "$DASH" | sed -n '1s/:.*//p')"
[ -n "$router_gate" ] && [ -n "$password_gate" ] && [ -n "$backup" ] && \
	[ "$router_gate" -lt "$backup" ] && [ "$password_gate" -lt "$backup" ] || \
	fail 'guest preflight can mutate before WAN/password validation'

network_reload="$(grep -n 'action_reload "Guest Wi-Fi" "Network reload failed or timed out"' "$DASH" | tail -n 1 | cut -d: -f1)"
wifi_reload="$(grep -n 'action_wifi_reload "Guest Wi-Fi"' "$DASH" | tail -n 1 | cut -d: -f1)"
dns_reload="$(grep -n 'action_reload "Guest Wi-Fi" "dnsmasq restart failed"' "$DASH" | tail -n 1 | cut -d: -f1)"
odhcpd_reload="$(grep -n 'action_reload "Guest Wi-Fi" "odhcpd restart failed"' "$DASH" | tail -n 1 | cut -d: -f1)"
firewall_reload="$(grep -n 'action_reload "Guest Wi-Fi" "Firewall reload failed"' "$DASH" | tail -n 1 | cut -d: -f1)"
[ -n "$network_reload" ] && [ -n "$wifi_reload" ] && [ -n "$dns_reload" ] && \
	[ -n "$odhcpd_reload" ] && [ -n "$firewall_reload" ] && \
	[ "$network_reload" -lt "$wifi_reload" ] && [ "$wifi_reload" -lt "$dns_reload" ] && \
	[ "$dns_reload" -lt "$odhcpd_reload" ] && [ "$odhcpd_reload" -lt "$firewall_reload" ] || \
	fail 'guest services reload in an unsafe order'

printf 'guest_network_contract=pass\n'
