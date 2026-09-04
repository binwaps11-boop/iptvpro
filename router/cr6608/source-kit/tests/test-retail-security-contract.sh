#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
SHADOW="${ROOT}/files/etc/shadow"
ROOT_MIGRATION="${ROOT}/files/etc/uci-defaults/99-cr6608-root-pass"
SECURE_CONSOLE_MIGRATION="${ROOT}/files/etc/uci-defaults/99-cr6608-secure-console"
HTTPS_MIGRATION="${ROOT}/files/etc/uci-defaults/98-cr6608-https-capability"
PRESERVED_MIGRATION="${ROOT}/files/etc/uci-defaults/99-cr6608-preserved-config-v2"
WIRELESS="${ROOT}/files/etc/config/wireless"
QUICK="${ROOT}/files/etc/config/cr6608quick"
SMARTAP="${ROOT}/files/etc/config/smartap"
UHTTPD="${ROOT}/files/etc/config/uhttpd"
RPCD="${ROOT}/files/etc/config/rpcd"
SYSTEM="${ROOT}/files/etc/config/system"
SEED="${ROOT}/cr6608.seed.config"
PROVISION_SOURCE="${ROOT}/files/usr/sbin/cr6608-retail-provision"
AUDIT_SOURCE="${ROOT}/files/usr/sbin/cr6608-retail-audit"
IPV4_ONLY_SOURCE="${ROOT}/files/usr/sbin/cr6608-ipv4-only"
PROVISION="${PROVISION_SOURCE}"
AUDIT="${AUDIT_SOURCE}"
KEEP="${ROOT}/files/lib/upgrade/keep.d/cr6608-retail"
DOC="${ROOT}/docs/RETAIL-PROVISIONING.md"
DASH="${ROOT}/files/www/cgi-bin/dashctl"
INSPECTOR="${ROOT}/inspect-image.sh"

fail() {
	printf 'retail security contract failed: %s\n' "$*" >&2
	exit 1
}

for path in "$SHADOW" "$ROOT_MIGRATION" "$SECURE_CONSOLE_MIGRATION" "$HTTPS_MIGRATION" "$WIRELESS" \
	"$PRESERVED_MIGRATION" "$QUICK" "$SMARTAP" "$UHTTPD" "$RPCD" "$SYSTEM" "$PROVISION" "$AUDIT" \
	"$IPV4_ONLY_SOURCE" "$KEEP" "$DOC" "$DASH" "$INSPECTOR"; do
	[ -s "$path" ] || fail "missing $path"
done
for guarded_luci_component in luci-light libustream-mbedtls px5g-mbedtls; do
	grep -Fxq "CONFIG_PACKAGE_${guarded_luci_component}=y" "$SEED" || \
		fail "guarded TLS/LuCI component is not selected: $guarded_luci_component"
done
for forbidden_luci_meta in luci luci-ssl luci-app-package-manager; do
	grep -Fxq "# CONFIG_PACKAGE_${forbidden_luci_meta} is not set" "$SEED" || \
		fail "unguarded LuCI package surface can be selected: $forbidden_luci_meta"
done
grep -Fxq 'CONFIG_PACKAGE_openssl-util=y' "$SEED" || \
	fail 'stdin-capable SHA-512 Web password hasher is not selected'
grep -Fxq 'CONFIG_PACKAGE_uclient-fetch=y' "$SEED" || \
	fail 'runtime TLS handshake probe is not selected'

# The owner-requested operator image password-gates SSH and serial recovery on
# clean boot. It is still not sale-ready: the audit explicitly rejects this
# shared hash until per-device provisioning replaces it.
operator_root_hash="$(awk -F: '$1 == "root" { print $2; exit }' "$SHADOW")"
case "$operator_root_hash" in \$6\$*) ;; *) fail 'operator image lacks a SHA-512 root hash' ;; esac
operator_root_fingerprint="$(printf %s "$operator_root_hash" | sha256sum | awk '{print $1}')"
[ "$operator_root_fingerprint" = 'b6139c45d43bc9a0262c02a42d8784da248e498eda9434e3cb673dbd4cf40ebe' ] || \
	fail 'operator root hash changed unexpectedly'
grep -Fq "$operator_root_fingerprint" "$AUDIT" || \
	fail 'sale audit does not reject the shared operator credential'
! grep -Eq "^[[:space:]]*(pinned_hash|legacy_hash)=" "$ROOT_MIGRATION" || \
	fail 'root migration embeds a shared password hash'
grep -Fq "option ttylogin '1'" "$SYSTEM" || \
	fail 'operator image does not password-gate the serial console'
grep -Fq "[ \"\$board\" = 'xiaomi,mi-router-cr6608' ] || exit 0" \
	"$SECURE_CONSOLE_MIGRATION" || fail 'secure-console migration is not board-scoped'
grep -Fq "''|x|\\!*|\\**) exit 0 ;;" "$SECURE_CONSOLE_MIGRATION" || \
	fail 'secure-console migration mishandles a locked preserved account'
! grep -Eq '\$(1|5|6|y)\$' "$SECURE_CONSOLE_MIGRATION" || \
	fail 'secure-console migration embeds a password hash'

# The user-requested open-lab onboarding profile exposes the two primary APs
# immediately. It deliberately remains ineligible for sale until the separate
# provisioner installs unique credentials and the runtime sale audit passes.
[ "$(grep -Ec "^[[:space:]]*option disabled '0'$" "$WIRELESS")" -eq 4 ] || \
	fail 'open-lab image does not enable both radios and both primary APs'
[ "$(grep -Ec "^[[:space:]]*option encryption 'none'$" "$WIRELESS")" -eq 2 ] || \
	fail 'open-lab image does not configure both primary APs as open'
[ "$(grep -Ec "^[[:space:]]*option hidden '0'$" "$WIRELESS")" -eq 2 ] || \
	fail 'open-lab image does not advertise both primary APs'
[ "$(grep -Ec "^[[:space:]]*option ieee80211w '0'$" "$WIRELESS")" -eq 2 ] || \
	fail 'open-lab image retains PMF on an open primary AP'
! grep -Eq "^[[:space:]]*option (key|sae_password) " "$WIRELESS" || \
	fail 'open-lab image embeds a Wi-Fi secret'
grep -Fq "option security 'none'" "$QUICK" || fail 'Quick Settings is not open by default'
grep -Fq "option hide_ssid '0'" "$QUICK" || fail 'Quick Settings hides the default SSIDs'
! grep -Eq "^[[:space:]]*option wifi_key " "$QUICK" || fail 'Quick Settings embeds a Wi-Fi key'
[ "$(grep -Ec "^[[:space:]]*option radio[01]_enabled '1'$" "$QUICK")" -eq 2 ] || \
	fail 'Quick Settings does not enable both radios'
for smartap_default in \
	"option radio0_enabled '1'" \
	"option radio1_enabled '1'" \
	"option hide_ssid '0'" \
	"option security 'none'"; do
	grep -Fq "$smartap_default" "$SMARTAP" || \
		fail "Smart AP defaults lack: $smartap_default"
done
! grep -Eq "^[[:space:]]*option (wifi_key|key|sae_password) " "$SMARTAP" || \
	fail 'Smart AP defaults embed a Wi-Fi secret'

# TLS is available in clean and preserved configurations. Redirect is deferred
# until credentials are installed so a kept-settings upgrade cannot lock out a
# currently deployed unit.
[ "$(grep -Ec "^[[:space:]]*list listen_http '.*:80'$" "$UHTTPD")" -eq 1 ] || \
	fail 'the IPv4-only HTTP listener set is invalid'
[ "$(grep -Ec "^[[:space:]]*list listen_https '.*:443'$" "$UHTTPD")" -eq 1 ] || \
	fail 'the IPv4-only HTTPS listener set is invalid'
! grep -Fq '[::]' "$UHTTPD" || fail 'factory Web configuration still exposes IPv6'
grep -Fq "option cert '/etc/uhttpd.crt'" "$UHTTPD" || fail 'TLS certificate path is missing'
grep -Fq "option key '/etc/uhttpd.key'" "$UHTTPD" || fail 'TLS key path is missing'
grep -Fq "option redirect_https '0'" "$UHTTPD" || fail 'factory-state HTTP policy changed'
grep -Fq 'listen_https=0.0.0.0:443' "$HTTPS_MIGRATION" || \
	fail 'preserved HTTP-only configurations do not gain IPv4 TLS'
grep -Fq 'del_list "uhttpd.${section}.listen_https=$listener"' "$HTTPS_MIGRATION" || \
	fail 'preserved HTTPS configurations do not remove IPv6 listeners'
[ "$(grep -Fc '[ -n "$board" ] || exit 1' "$HTTPS_MIGRATION")" -eq 1 ] || \
	fail 'HTTPS migration does not retry after transient board detection failure'
! grep -Fq 'redirect_https=1' "$HTTPS_MIGRATION" || \
	fail 'upgrade migration would force a redirect before provisioning'
admin_access="$(sed -n '/^  save_admin_access)/,/^  opkg_update/p' "$DASH")"
printf '%s\n' "$admin_access" | grep -Fq 'uhttpd.main.listen_http="0.0.0.0:$http_port"' || \
	fail 'Smart AP access settings do not retain the IPv4 HTTP listener'
! printf '%s\n' "$admin_access" | grep -Fq 'uhttpd.main.listen_http="[::]:$http_port"' || \
	fail 'Smart AP access settings can recreate an IPv6 HTTP listener'

# Exercise the shadow migration: clean/blank inputs stay locked, while a
# non-empty operator hash survives a keep-settings sysupgrade byte-for-byte.
TMP="$(mktemp -d)"
case "$TMP" in /tmp/*|/var/tmp/*) ;; *) fail 'unsafe temporary directory' ;; esac
concurrent_pid=''
cleanup() {
	if [ -n "$concurrent_pid" ]; then
		kill "$concurrent_pid" 2>/dev/null || true
		wait "$concurrent_pid" 2>/dev/null || true
	fi
	rm -rf -- "$TMP"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP/bin"
cat > "$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$TMP/bin/logger"

# Execute the uhttpd migration against preserved listeners. It must remove or
# translate IPv6 wildcards, remain idempotent, and leave address-specific or
# intentionally absent HTTP listeners untouched.
mkdir -p "$TMP/http-bin" "$TMP/http-state"
cat > "$TMP/http-bin/cat" <<'EOF'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = /tmp/sysinfo/board_name ]; then
	printf 'xiaomi,mi-router-cr6608\n'
	exit 0
fi
exec /bin/cat "$@"
EOF
cat > "$TMP/http-bin/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = -q ] && shift
action="${1:-}"
arg="${2:-}"
state="${CR6608_TEST_UHTTPD_STATE:?}"
option_file() {
	key="$1"
	case "$key" in uhttpd.main.*) printf '%s/%s\n' "$state" "${key##*.}" ;; *) return 1 ;; esac
}
case "$action" in
	show)
		[ "$arg" = uhttpd ] || exit 1
		printf 'uhttpd.main=uhttpd\n'
		;;
	get)
		file="$(option_file "$arg")" || exit 1
		[ -f "$file" ] || exit 1
		tr '\n' ' ' < "$file"
		printf '\n'
		;;
	add_list|set|del_list)
		key="${arg%%=*}"
		value="${arg#*=}"
		[ "$key" != "$arg" ] || exit 1
		file="$(option_file "$key")" || exit 1
		if [ "$action" = add_list ]; then
			printf '%s\n' "$value" >> "$file"
		elif [ "$action" = del_list ]; then
			[ -f "$file" ] || exit 0
			tmp="$file.$$"
			grep -Fvx "$value" "$file" > "$tmp" || true
			mv "$tmp" "$file"
		else
			printf '%s\n' "$value" > "$file"
		fi
		;;
	commit)
		[ "$arg" = uhttpd ] || exit 1
		printf 'uhttpd\n' >> "$state/commits"
		;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$TMP/http-bin/cat" "$TMP/http-bin/uci"

reset_http_state() {
	rm -f "$TMP/http-state/"*
	printf '%s\n' '0.0.0.0:443' '[::]:443' > "$TMP/http-state/listen_https"
	printf '/etc/uhttpd.crt\n' > "$TMP/http-state/cert"
	printf '/etc/uhttpd.key\n' > "$TMP/http-state/key"
}
run_http_migration() {
	CR6608_TEST_UHTTPD_STATE="$TMP/http-state" \
		PATH="$TMP/http-bin:$PATH" sh "$HTTPS_MIGRATION"
}

reset_http_state
printf '0.0.0.0:8080\n' > "$TMP/http-state/listen_http"
run_http_migration || fail 'IPv4-only preserved HTTP migration failed'
grep -Fxq '0.0.0.0:8080' "$TMP/http-state/listen_http" || \
	fail 'migration removed the preserved IPv4 HTTP listener'
[ "$(wc -l < "$TMP/http-state/listen_http" | tr -d ' ')" -eq 1 ] || \
	fail 'migration added an unexpected HTTP endpoint'
[ "$(wc -l < "$TMP/http-state/commits" | tr -d ' ')" -eq 1 ] || \
	fail 'IPv4-only listener repair was not committed exactly once'
run_http_migration || fail 'idempotent HTTP migration rerun failed'
[ "$(wc -l < "$TMP/http-state/listen_http" | tr -d ' ')" -eq 1 ] || \
	fail 'migration duplicated HTTP listeners on rerun'
[ "$(wc -l < "$TMP/http-state/commits" | tr -d ' ')" -eq 1 ] || \
	fail 'idempotent HTTP migration committed unchanged state'

reset_http_state
printf '[::]:9090\n' > "$TMP/http-state/listen_http"
run_http_migration || fail 'IPv6-only preserved HTTP migration failed'
! grep -Fxq '[::]:9090' "$TMP/http-state/listen_http" && \
	grep -Fxq '0.0.0.0:9090' "$TMP/http-state/listen_http" || \
	fail 'migration did not add the matching IPv4 HTTP listener'
[ "$(wc -l < "$TMP/http-state/listen_http" | tr -d ' ')" -eq 1 ] || \
	fail 'IPv6-only migration added an unexpected HTTP endpoint'

reset_http_state
printf '0.0.0.0:443\n' > "$TMP/http-state/listen_https"
printf '192.168.1.1:8080\n' > "$TMP/http-state/listen_http"
run_http_migration || fail 'address-specific HTTP migration failed'
[ "$(wc -l < "$TMP/http-state/listen_http" | tr -d ' ')" -eq 1 ] && \
	grep -Fxq '192.168.1.1:8080' "$TMP/http-state/listen_http" || \
	fail 'migration widened an address-specific HTTP listener'
[ ! -e "$TMP/http-state/commits" ] || \
	fail 'address-specific unchanged HTTP state was committed'

reset_http_state
printf '0.0.0.0:443\n' > "$TMP/http-state/listen_https"
run_http_migration || fail 'HTTPS-only preserved migration failed'
[ ! -e "$TMP/http-state/listen_http" ] || \
	fail 'migration re-enabled an intentionally absent HTTP listener'
[ ! -e "$TMP/http-state/commits" ] || \
	fail 'HTTPS-only unchanged state was committed'

run_shadow_case() {
	input_hash="$1"
	expected_hash="$2"
	shadow_case="$TMP/shadow"
	printf 'root:%s:20647:0:99999:7:::\ndaemon:*:0:0:99999:7:::\n' \
		"$input_hash" > "$shadow_case"
	PATH="$TMP/bin:$PATH" CR6608_SHADOW_FILE="$shadow_case" sh "$ROOT_MIGRATION"
	actual_hash="$(awk -F: '$1 == "root" { print $2; exit }' "$shadow_case")"
	[ "$actual_hash" = "$expected_hash" ] || fail 'shadow migration changed the wrong hash'
	[ "$(awk -F: '$1 == "root" { print NF; exit }' "$shadow_case")" -eq 9 ] || \
		fail 'root shadow record is not nine fields'
	grep -Fqx 'daemon:*:0:0:99999:7:::' "$shadow_case" || \
		fail 'shadow migration changed a non-root account'
}
run_shadow_case '!' '!'
run_shadow_case '' '!'
operator_hash='$6$operator-unit$unique-hash-preserved'
run_shadow_case "$operator_hash" "$operator_hash"

printf 'daemon:*:0:0:99999:7:::\n' > "$TMP/shadow"
if PATH="$TMP/bin:$PATH" CR6608_SHADOW_FILE="$TMP/shadow" sh "$ROOT_MIGRATION"; then
	fail 'root migration accepted a shadow file without root'
fi
for failing_tool in awk chmod mv; do
	printf 'root:!:20647:0:99999:7:::\ndaemon:*:0:0:99999:7:::\n' > "$TMP/shadow"
	mkdir -p "$TMP/fail-bin"
	cat > "$TMP/fail-bin/$failing_tool" <<'EOF'
#!/bin/sh
exit 1
EOF
	chmod 0755 "$TMP/fail-bin/$failing_tool"
	if PATH="$TMP/fail-bin:$TMP/bin:$PATH" CR6608_SHADOW_FILE="$TMP/shadow" \
		sh "$ROOT_MIGRATION"; then
		fail "root migration ignored $failing_tool failure"
	fi
	rm -f "$TMP/fail-bin/$failing_tool"
done
grep -Fq "trap 'exit 1' HUP INT TERM" "$ROOT_MIGRATION" || \
	fail 'root migration signal trap can continue after cleanup'

# The runtime sale audit is independently executable. A mock UCI database
# proves a protected provisioned unit passes and an open AP fails.
cat > "$TMP/bin/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { printf '0\n'; exit 0; }
exec /usr/bin/id "$@"
EOF
cat > "$TMP/bin/stat" <<'EOF'
#!/bin/sh
[ "${1:-}" = -c ] || exit 2
case "${2:-}" in
	'%u') printf '0\n' ;;
	'%a')
		case "${3:-}" in
			*uhttpd.crt) printf '644\n' ;;
			*uhttpd.key) printf '600\n' ;;
			*marker*|*commissioning-ram) printf '400\n' ;;
			*cr6608-apply.lock) printf '700\n' ;;
			*) printf '600\n' ;;
		esac
		;;
	*) exit 2 ;;
esac
EOF
cat > "$TMP/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = -q ] && shift
action="${1:-}"; key="${2:-}"
case "$action:$key" in
	show:rpcd) printf '%s\n' 'rpcd.web=login' ;;
	get:rpcd.web.username) printf 'root\n' ;;
	get:rpcd.web.password) printf '%s\n' "$CR6608_TEST_WEB_HASH" ;;
	get:rpcd.web.read|get:rpcd.web.write) printf '*\n' ;;
	get:system.@system\[0\].ttylogin) printf '%s\n' "${CR6608_TEST_TTYLOGIN:-1}" ;;
	get:uhttpd.main.redirect_https) printf '1\n' ;;
	get:uhttpd.main.listen_https)
		printf '0.0.0.0:443%s\n' "${CR6608_TEST_EXTRA_ENDPOINT:+ 127.0.0.1:8443}"
		;;
	get:uhttpd.main.cert) printf '%s\n' "$CR6608_TEST_CERT" ;;
	get:uhttpd.main.key) printf '%s\n' "$CR6608_TEST_KEY" ;;
	show:wireless)
		printf '%s\n' \
			'wireless.radio0=wifi-device' 'wireless.radio1=wifi-device' \
			'wireless.primary24=wifi-iface'
		[ "${CR6608_TEST_NO_RADIO1_AP:-0}" = 1 ] || printf '%s\n' 'wireless.primary5=wifi-iface'
		[ "${CR6608_TEST_OPEN_MESH:-0}" != 1 ] || printf '%s\n' 'wireless.smartap_mesh=wifi-iface'
		;;
	get:wireless.radio0.disabled|get:wireless.radio1.disabled) printf '0\n' ;;
	get:wireless.radio0.hostapd_options)
		[ "${CR6608_TEST_RAW_RADIO:-0}" = 1 ] || exit 1
		printf 'wps_state=2\n'
		;;
	get:wireless.primary24|get:wireless.primary5) printf 'wifi-iface\n' ;;
	get:wireless.primary24.device) printf 'radio0\n' ;;
	get:wireless.primary5.device) printf 'radio1\n' ;;
	get:wireless.primary24.mode|get:wireless.primary5.mode) printf 'ap\n' ;;
	get:wireless.primary24.network|get:wireless.primary5.network) printf 'lan\n' ;;
	get:wireless.primary24.disabled|get:wireless.primary5.disabled) printf '0\n' ;;
	get:wireless.primary24.encryption|get:wireless.primary5.encryption)
		if [ "${CR6608_TEST_OPEN:-0}" = 1 ]; then printf 'none\n'; else printf 'sae-mixed\n'; fi
		;;
	get:wireless.primary24.ieee80211w|get:wireless.primary5.ieee80211w)
		if [ "${CR6608_TEST_NO_PMF:-0}" = 1 ]; then printf '0\n'; else printf '1\n'; fi
		;;
	get:wireless.primary24.key|get:wireless.primary5.key)
		printf '%s\n' "${CR6608_TEST_WIFI_KEY:-unit-specific-wifi-key-42}"
		;;
	get:wireless.primary24.sae_password)
		[ "${CR6608_TEST_ALT_CREDENTIAL:-0}" = 1 ] || exit 1
		printf 'retained-alternate-secret\n'
		;;
	get:wireless.primary24.multi_ap)
		[ "${CR6608_TEST_MULTI_AP:-0}" = 1 ] || exit 1
		printf '1\n'
		;;
	get:wireless.primary24.wds)
		[ "${CR6608_TEST_AP_WDS:-0}" = 1 ] || exit 1
		printf '1\n'
		;;
	get:wireless.primary24.multi_ap_backhaul_key)
		[ "${CR6608_TEST_BACKHAUL_KEY:-0}" = 1 ] || exit 1
		printf 'retained-backhaul-secret\n'
		;;
	get:wireless.primary24.wps_pin)
		[ "${CR6608_TEST_WPS_PIN:-0}" = 1 ] || exit 1
		printf '12345670\n'
		;;
	get:wireless.primary24.wps_pushbutton)
		[ "${CR6608_TEST_WPS_PBC:-0}" = 1 ] || exit 1
		printf '1\n'
		;;
	get:wireless.primary24.hostapd_bss_options)
		[ "${CR6608_TEST_RAW_BSS:-0}" = 1 ] || exit 1
		printf 'wpa_passphrase=attacker-controlled\n'
		;;
	get:wireless.smartap_mesh.device) printf 'radio1\n' ;;
	get:wireless.smartap_mesh.mode) printf 'mesh\n' ;;
	get:wireless.smartap_mesh.disabled) printf '0\n' ;;
	get:wireless.smartap_mesh.network) printf 'lan\n' ;;
	get:wireless.smartap_mesh.mesh_id) printf 'factory-mesh\n' ;;
	get:wireless.smartap_mesh.mesh_fwding) printf '1\n' ;;
	get:wireless.smartap_mesh.encryption) printf 'none\n' ;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$TMP/bin/id" "$TMP/bin/stat" "$TMP/uci"
cat > "$TMP/bin/openssl" <<'EOF'
#!/bin/sh
case "${1:-}" in
	passwd)
		secret="$(sed -n '1p')"
		if [ "$secret" = "$CR6608_TEST_EXPECTED_WEB" ]; then
			printf '%s\n' "$CR6608_TEST_WEB_HASH"
		elif [ "$secret" = "$CR6608_TEST_EXPECTED_ROOT" ]; then
			printf '%s\n' "$CR6608_TEST_ROOT_HASH"
		else
			printf '%s\n' '$6$unitweb1$BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
		fi
		;;
	x509)
		case " $* " in
			*' -checkend 0 '*) [ "${CR6608_TEST_CERT_CRYPTO_FAIL:-0}" != 1 ] ;;
			*' -pubkey '*)
				[ "${CR6608_TEST_CERT_PUBLIC_FAIL:-0}" != 1 ] || exit 1
				printf '%s\n%s\n%s\n' '-----BEGIN PUBLIC KEY-----' \
					"${CR6608_TEST_CERT_PUBLIC_ID:-unit-cert-key}" \
					'-----END PUBLIC KEY-----'
				;;
			*) exit 1 ;;
		esac
		;;
	pkey)
		case " $* " in
			*' -check '*) [ "${CR6608_TEST_KEY_CRYPTO_FAIL:-0}" != 1 ] ;;
			*' -pubout '*)
				[ "${CR6608_TEST_KEY_PUBLIC_FAIL:-0}" != 1 ] || exit 1
				printf '%s\n%s\n%s\n' '-----BEGIN PUBLIC KEY-----' \
					"${CR6608_TEST_KEY_PUBLIC_ID:-unit-cert-key}" \
					'-----END PUBLIC KEY-----'
				;;
			*) exit 1 ;;
		esac
		;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$TMP/bin/openssl"
cat > "$TMP/bin/tls-probe" <<'EOF'
#!/bin/sh
[ "${CR6608_TEST_TLS_FAIL:-0}" != 1 ]
EOF
cat > "$TMP/bin/ubus" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	case "$1" in -S) shift ;; -t) shift 2 ;; *) break ;; esac
done
case "${1:-}:${2:-}:${3:-}" in
	call:network.wireless:status) printf '{}\n' ;;
	list:hostapd.phy0-ap0:|list:hostapd.phy1-ap0:) printf '%s\n' "$2" ;;
	call:hostapd.phy0-ap0:get_status|call:hostapd.phy1-ap0:get_status) printf '{}\n' ;;
	*) exit 1 ;;
esac
EOF
cat > "$TMP/bin/jsonfilter" <<'EOF'
#!/bin/sh
[ "${1:-}" = -e ] || exit 2
expression="${2:-}"
case "$expression" in
	'@.radio0.up'|'@.radio1.up') printf 'true\n' ;;
	'@.radio0.disabled'|'@.radio1.disabled'|'@.radio0.pending'|'@.radio1.pending') printf 'false\n' ;;
	'@.radio0.interfaces[0].section')
		if [ "${CR6608_TEST_PRIMARY_RUNTIME_DOWN:-0}" = 1 ]; then printf 'secondary24\n'; else printf 'primary24\n'; fi ;;
	'@.radio1.interfaces[0].section') printf 'primary5\n' ;;
	'@.radio0.interfaces[0].ifname') printf 'phy0-ap0\n' ;;
	'@.radio1.interfaces[0].ifname') printf 'phy1-ap0\n' ;;
	'@.radio0.interfaces[0].config.mode'|'@.radio1.interfaces[0].config.mode') printf 'ap\n' ;;
	'@.radio0.interfaces[1].section'|'@.radio1.interfaces[1].section') exit 1 ;;
	'@.status') printf 'ENABLED\n' ;;
	*) exit 1 ;;
esac
EOF
cat > "$TMP/bin/iw" <<'EOF'
#!/bin/sh
case "$*" in
	'dev phy0-ap0 info'|'dev phy1-ap0 info')
		if [ "${CR6608_TEST_PRIMARY_RUNTIME_NOT_AP:-0}" = 1 ] && [ "$2" = phy0-ap0 ]; then
			printf 'Interface %s\n\ttype managed\n' "$2"
		else
			printf 'Interface %s\n\ttype AP\n' "$2"
		fi
		;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$TMP/bin/tls-probe" "$TMP/bin/ubus" "$TMP/bin/jsonfilter" "$TMP/bin/iw"
printf '%s\n' \
	'profile=retail-v2' \
	'market_country=SA' \
	'primary_ap_radio0=primary24' \
	'primary_ap_radio1=primary5' \
	'sale_ready=NO' \
	'radio_policy=LAB_ARTIFACT_BLOCKED' \
	'audit_complete=YES' \
	'provisioned_utc=2026-08-23T00:00:00Z' > "$TMP/marker"
chmod 0400 "$TMP/marker"
root_hash_body="$(printf '%086d' 0 | tr 0 C)"
root_hash="\$6\$unitroot1\$$root_hash_body"
printf 'root:%s:20647:0:99999:7:::\n' "$root_hash" > "$TMP/audit-shadow"
printf '%s\n' 'unique-root-secret-168' > "$TMP/root-audit.secret"
printf '%s\n' 'unique-web-secret-126' > "$TMP/web.secret"
printf '%s\n' 'unit-specific-wifi-key-42' > "$TMP/wifi.secret"
chmod 0600 "$TMP/root-audit.secret" "$TMP/web.secret" "$TMP/wifi.secret"
printf '%s\n' 'profile=retail-v1' 'sale_ready=NO' 'radio_policy=retail-disabled' > \
	"$TMP/commissioning-artifact-profile"
printf 'tmpfs / tmpfs rw,nosuid,nodev 0 0\n' > "$TMP/commissioning-mounts"
printf '%s\n' 'test certificate' > "$TMP/uhttpd.crt"
printf '%s\n' 'test private key' > "$TMP/uhttpd.key"
cat > "$TMP/tcp" <<'EOF'
  sl  local_address rem_address   st
   0: 00000000:01BB 00000000:0000 0A
EOF
cat > "$TMP/tcp6" <<'EOF'
  sl  local_address                         remote_address                        st
EOF
cp "$TMP/tcp6" "$TMP/udp6"
mkdir -p "$TMP/ipv6-conf/all" "$TMP/ipv6-conf/default" "$TMP/ipv6-conf/lo" "$TMP/ipv6-conf/eth0"
for ipv6_scope in all default lo eth0; do
	printf '%s\n' 1 > "$TMP/ipv6-conf/$ipv6_scope/disable_ipv6"
done
# Keep the IPv4-only verifier fixture independent of the build host.  The
# verifier intentionally requires explicit NTP UID and ephemeral-port evidence
# even when the mocked UDP6 table is empty, so never borrow /etc/passwd or the
# host kernel's port range here.
printf '%s\n' 'ntp:x:123:123:Network Time:/var/run/ntpd:/bin/false' > "$TMP/ipv6-passwd"
printf '%s\n' '32768 60999' > "$TMP/ipv6-port-range"
mkdir -p "$TMP/ipv6-proc"
cp "$IPV4_ONLY_SOURCE" "$TMP/bin/ipv4-only"
cat > "$TMP/bin/ipv6-ip" <<'EOF'
#!/bin/sh
[ "${CR6608_TEST_IPV6_ADDRESS:-0}" = 0 ] || {
	printf '%s\n' '2: eth0    inet6 fe80::1/64 scope link'
}
exit 0
EOF
chmod 0755 "$TMP/bin/ipv4-only" "$TMP/bin/ipv6-ip"

AUDIT="$TMP/retail-audit-under-test"
PROVISION="$TMP/retail-provision-under-test"
sed \
	-e "s|^PATH='/usr/sbin:/usr/bin:/sbin:/bin'$|PATH='$TMP/bin:/usr/sbin:/usr/bin:/sbin:/bin'|" \
	-e "s|^MARKER='/etc/cr6608-retail-provisioned'$|MARKER='$TMP/marker'|" \
	-e "s|^PENDING_MARKER='/etc/cr6608-retail-provisioning-pending'$|PENDING_MARKER='$TMP/pending-marker'|" \
	-e "s|^COMMISSIONING_ARTIFACT_PROFILE='/etc/cr6608-artifact-profile'$|COMMISSIONING_ARTIFACT_PROFILE='$TMP/commissioning-artifact-profile'|" \
	-e "s|^PROC_MOUNTS='/proc/self/mounts'$|PROC_MOUNTS='$TMP/commissioning-mounts'|" \
	-e "s|^COMMISSIONING_MARKER='/etc/cr6608-retail-commissioning-ram'$|COMMISSIONING_MARKER='$TMP/commissioning-marker'|" \
	-e "s|^COMMISSIONING_AUTHORIZED_KEYS='/etc/dropbear/authorized_keys'$|COMMISSIONING_AUTHORIZED_KEYS='$TMP/commissioning-authorized-keys'|" \
	-e "s|^SHADOW='/etc/shadow'$|SHADOW='$TMP/audit-shadow'|" \
	-e "s|^UCI_BIN='/sbin/uci'$|UCI_BIN='$TMP/uci'|" \
	-e "s|^OPENSSL_BIN='/usr/bin/openssl'$|OPENSSL_BIN='$TMP/bin/openssl'|" \
	-e "s|^TLS_PROBE_BIN='/bin/uclient-fetch'$|TLS_PROBE_BIN='$TMP/bin/tls-probe'|" \
	-e "s|^PROC_NET_TCP='/proc/net/tcp'$|PROC_NET_TCP='$TMP/tcp'|" \
	-e "s|^IPV4_ONLY_BIN='/usr/sbin/cr6608-ipv4-only'$|IPV4_ONLY_BIN='$TMP/bin/ipv4-only'|" \
	-e "s|^UBUS_BIN='/bin/ubus'$|UBUS_BIN='$TMP/bin/ubus'|" \
	-e "s|^JSONFILTER_BIN='/usr/bin/jsonfilter'$|JSONFILTER_BIN='$TMP/bin/jsonfilter'|" \
	-e "s|^IW_BIN='/usr/sbin/iw'$|IW_BIN='$TMP/bin/iw'|" \
	-e "s|/usr/bin/id|$TMP/bin/id|g" \
	-e "s|/bin/stat|$TMP/bin/stat|g" \
	"$AUDIT_SOURCE" > "$AUDIT"
sed \
	-e "s|^PATH='/usr/sbin:/usr/bin:/sbin:/bin'$|PATH='$TMP/bin:/usr/sbin:/usr/bin:/sbin:/bin'|" \
	-e "s|^MARKER='/etc/cr6608-retail-provisioned'$|MARKER='$TMP/device/etc/cr6608-retail-provisioned'|" \
	-e "s|^PENDING_MARKER='/etc/cr6608-retail-provisioning-pending'$|PENDING_MARKER='$TMP/device/etc/cr6608-retail-provisioning-pending'|" \
	-e "s|^COMMISSIONING_ARTIFACT_PROFILE='/etc/cr6608-artifact-profile'$|COMMISSIONING_ARTIFACT_PROFILE='$TMP/commissioning-artifact-profile'|" \
	-e "s|^PROC_MOUNTS='/proc/self/mounts'$|PROC_MOUNTS='$TMP/commissioning-mounts'|" \
	-e "s|^COMMISSIONING_MARKER='/etc/cr6608-retail-commissioning-ram'$|COMMISSIONING_MARKER='$TMP/device/etc/cr6608-retail-commissioning-ram'|" \
	-e "s|^COMMISSIONING_AUTHORIZED_KEYS='/etc/dropbear/authorized_keys'$|COMMISSIONING_AUTHORIZED_KEYS='$TMP/device/etc/dropbear/authorized_keys'|" \
	-e "s|^SHADOW_PATH='/etc/shadow'$|SHADOW_PATH='$TMP/device/etc/shadow'|" \
	-e "s|^WIRELESS_CONFIG='/etc/config/wireless'$|WIRELESS_CONFIG='$TMP/device/etc/config/wireless'|" \
	-e "s|^QUICK_CONFIG='/etc/config/cr6608quick'$|QUICK_CONFIG='$TMP/device/etc/config/cr6608quick'|" \
	-e "s|^SMARTAP_CONFIG='/etc/config/smartap'$|SMARTAP_CONFIG='$TMP/device/etc/config/smartap'|" \
	-e "s|^UHTTPD_CONFIG='/etc/config/uhttpd'$|UHTTPD_CONFIG='$TMP/device/etc/config/uhttpd'|" \
	-e "s|^RPCD_CONFIG='/etc/config/rpcd'$|RPCD_CONFIG='$TMP/device/etc/config/rpcd'|" \
	-e "s|^SYSTEM_CONFIG='/etc/config/system'$|SYSTEM_CONFIG='$TMP/device/etc/config/system'|" \
	-e "s|^PRPLMESH_CONFIG='/etc/config/prplmesh'$|PRPLMESH_CONFIG='$TMP/device/etc/config/prplmesh'|" \
	-e "s|^DROPBEAR_CONFIG='/etc/config/dropbear'$|DROPBEAR_CONFIG='$TMP/device/etc/config/dropbear'|" \
	-e "s|^UCI_BIN='/sbin/uci'$|UCI_BIN='$TMP/runtime-bin/uci'|" \
	-e "s|^PASSWD_BIN='/usr/bin/passwd'$|PASSWD_BIN='$TMP/runtime-bin/passwd'|" \
	-e "s|^OPENSSL_BIN='/usr/bin/openssl'$|OPENSSL_BIN='$TMP/runtime-bin/openssl'|" \
	-e "s|^UHTTPD_INIT='/etc/init.d/uhttpd'$|UHTTPD_INIT='$TMP/runtime-bin/uhttpd'|" \
	-e "s|^RPCD_INIT='/etc/init.d/rpcd'$|RPCD_INIT='$TMP/runtime-bin/rpcd'|" \
	-e "s|^WIFI_BIN='/sbin/wifi'$|WIFI_BIN='$TMP/runtime-bin/wifi'|" \
	-e "s|^AUDIT_BIN='/usr/sbin/cr6608-retail-audit'$|AUDIT_BIN='$TMP/runtime-bin/audit'|" \
	-e "s|^SLEEP_BIN='/bin/sleep'$|SLEEP_BIN='$TMP/runtime-bin/sleep'|" \
	-e "s|^PRPLMESH_SYNC_BIN='/usr/sbin/cr6608-prplmesh-sync'$|PRPLMESH_SYNC_BIN='$TMP/runtime-bin/prplmesh-sync'|" \
	-e 's|^AUDIT_READY_MAX_ATTEMPTS=16$|AUDIT_READY_MAX_ATTEMPTS=3|' \
	-e 's|^AUDIT_READY_INTERVAL_SECONDS=2$|AUDIT_READY_INTERVAL_SECONDS=0|' \
	-e "s|^CACHE_STATE_LIB='/usr/libexec/cr6608-dashboard-cache-state'$|CACHE_STATE_LIB='$TMP/runtime-bin/cache-state'|" \
	-e "s|^APPLY_LOCK='/var/run/cr6608-apply.lock'$|APPLY_LOCK='$TMP/cr6608-apply.lock'|" \
	-e "s|/usr/bin/id|$TMP/bin/id|g" \
	-e "s|/bin/stat|$TMP/bin/stat|g" \
	"$PROVISION_SOURCE" > "$PROVISION"
chmod 0755 "$AUDIT" "$PROVISION"
audit_env="CR6608_TEST_ROOT_HASH=$root_hash CR6608_TEST_EXPECTED_ROOT=unique-root-secret-168 CR6608_TEST_WEB_HASH=\$6\$unitweb1\$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA CR6608_TEST_EXPECTED_WEB=unique-web-secret-126 CR6608_TEST_CERT=$TMP/uhttpd.crt CR6608_TEST_KEY=$TMP/uhttpd.key CR6608_IPV6_CONF_ROOT=$TMP/ipv6-conf CR6608_IPV6_IP_BIN=$TMP/bin/ipv6-ip CR6608_IPV6_PROC_TCP6=$TMP/tcp6 CR6608_IPV6_PROC_UDP6=$TMP/udp6 CR6608_IPV6_PASSWD_FILE=$TMP/ipv6-passwd CR6608_IPV6_PROC_ROOT=$TMP/ipv6-proc CR6608_IPV6_PORT_RANGE=$TMP/ipv6-port-range"
if [ "${CR6608_TEST_PROVISION_ONLY:-0}" != 1 ]; then
# shellcheck disable=SC2086
env $audit_env sh "$AUDIT" \
	--root-password-file "$TMP/root-audit.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" | grep -qx \
	'retail_security=PASS sale_ready=NO radio_policy=LAB_ARTIFACT_BLOCKED' || \
	fail 'protected provisioned fixture did not pass the sale audit'
cat > "$TMP/commissioning-marker" <<'EOF'
profile=retail-commissioning-ram-v1
sale_ready=NO
boot_policy=ram-only
password_auth=disabled
factory_key_fingerprint=SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
factory_key_sha256=d036215e80ab00eb6c293e7191559083a773345a0c0de1948e7d4a47436a0e0c
EOF
printf 'ssh-ed25519 test commissioning\n' > "$TMP/commissioning-authorized-keys"
chmod 0400 "$TMP/commissioning-marker"
chmod 0600 "$TMP/commissioning-authorized-keys"
if env $audit_env sh "$AUDIT" \
	--root-password-file "$TMP/root-audit.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" > "$TMP/commissioning-audit.out" 2>&1; then
	fail 'sale audit accepted a retained factory commissioning key'
fi
grep -Fq 'factory_commissioning_access_present' "$TMP/commissioning-audit.out" ||
	fail 'retained commissioning-key failure reason is missing'
rm -f "$TMP/commissioning-marker" "$TMP/commissioning-authorized-keys"
if env CR6608_TEST_OPEN=1 $audit_env sh "$AUDIT" \
	--root-password-file "$TMP/root-audit.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" \
	> "$TMP/open.out" 2>&1; then
	fail 'sale audit accepted an open AP'
fi
grep -Fq 'open_or_unsupported_encryption' "$TMP/open.out" || \
	fail 'open-AP audit failure reason is missing'
fi

expect_audit_failure() {
	case_name="$1"
	expected_reason="$2"
	shift 2
	# shellcheck disable=SC2086
	if env $audit_env "$@" sh "$AUDIT" \
		--root-password-file "$TMP/root-audit.secret" --wifi-key-file "$TMP/wifi.secret" \
		--web-password-file "$TMP/web.secret" \
		> "$TMP/${case_name}.out" 2>&1; then
		fail "sale audit accepted invalid fixture: $case_name"
	fi
	grep -Fq "$expected_reason" "$TMP/${case_name}.out" || \
		fail "audit failure reason is missing: $case_name"
}
if [ "${CR6608_TEST_PROVISION_ONLY:-0}" != 1 ]; then
: > "$TMP/no-listener"
expect_audit_failure ttylogin console_password_login_disabled CR6608_TEST_TTYLOGIN=0
expect_audit_failure extra_endpoint https_listener_unexpected CR6608_TEST_EXTRA_ENDPOINT=1
expect_audit_failure missing_cert https_cert_file_invalid CR6608_TEST_CERT="$TMP/missing.crt"
expect_audit_failure cert_crypto https_cert_parse_or_expired \
	CR6608_TEST_CERT_CRYPTO_FAIL=1
expect_audit_failure key_crypto https_key_invalid CR6608_TEST_KEY_CRYPTO_FAIL=1
expect_audit_failure cert_public https_cert_public_key_invalid \
	CR6608_TEST_CERT_PUBLIC_FAIL=1
expect_audit_failure key_public https_key_public_key_invalid \
	CR6608_TEST_KEY_PUBLIC_FAIL=1
expect_audit_failure cert_key_mismatch https_cert_key_mismatch \
	CR6608_TEST_KEY_PUBLIC_ID=other-unit-key
printf '%s\n' 0 > "$TMP/ipv6-conf/eth0/disable_ipv6"
expect_audit_failure ipv6_interface_enabled ipv6_policy_runtime_failed
printf '%s\n' 1 > "$TMP/ipv6-conf/eth0/disable_ipv6"
printf '%s\n' '   0: 00000000000000000000000000000000:01BB 00000000000000000000000000000000:0000 0A' >> "$TMP/tcp6"
expect_audit_failure ipv6_tcp_listener ipv6_policy_runtime_failed
sed -i '$d' "$TMP/tcp6"
printf '%s\n' '   0: 00000000000000000000000000000000:0035 00000000000000000000000000000000:0000 0A' >> "$TMP/udp6"
expect_audit_failure ipv6_udp_listener ipv6_policy_runtime_failed
sed -i '$d' "$TMP/udp6"
mv "$TMP/tcp6" "$TMP/tcp6.missing"
expect_audit_failure ipv6_evidence_missing ipv6_policy_runtime_failed
mv "$TMP/tcp6.missing" "$TMP/tcp6"
expect_audit_failure ipv6_address_present ipv6_policy_runtime_failed CR6608_TEST_IPV6_ADDRESS=1
expect_audit_failure tls_handshake https_tls_handshake_failed CR6608_TEST_TLS_FAIL=1
expect_audit_failure pmf primary24_pmf_disabled CR6608_TEST_NO_PMF=1
expect_audit_failure radio1_ap radio1_primary_ap_resolution CR6608_TEST_NO_RADIO1_AP=1
expect_audit_failure alternate_credential primary24_alternate_credential_sae_password \
	CR6608_TEST_ALT_CREDENTIAL=1
expect_audit_failure backhaul_credential primary24_alternate_credential_multi_ap_backhaul_key \
	CR6608_TEST_BACKHAUL_KEY=1
expect_audit_failure wps_pin primary24_alternate_credential_wps_pin \
	CR6608_TEST_WPS_PIN=1
expect_audit_failure wps_pbc primary24_wps_enabled_wps_pushbutton \
	CR6608_TEST_WPS_PBC=1
expect_audit_failure multi_ap primary24_multi_ap_role_not_allowlisted CR6608_TEST_MULTI_AP=1
expect_audit_failure ap_wds primary24_wds_ap_role_not_allowlisted CR6608_TEST_AP_WDS=1
expect_audit_failure raw_radio radio0_raw_hostapd_options CR6608_TEST_RAW_RADIO=1
expect_audit_failure raw_bss primary24_raw_hostapd_bss_options CR6608_TEST_RAW_BSS=1
expect_audit_failure open_mesh smartap_mesh_open_or_unsupported_encryption \
	CR6608_TEST_OPEN_MESH=1
expect_audit_failure primary_runtime_down primary24_runtime_missing \
	CR6608_TEST_PRIMARY_RUNTIME_DOWN=1
expect_audit_failure primary_runtime_not_ap primary24_runtime_not_ap \
	CR6608_TEST_PRIMARY_RUNTIME_NOT_AP=1
expect_audit_failure web_mismatch web_password_mismatch \
	CR6608_TEST_EXPECTED_WEB=some-other-web-secret
expect_audit_failure root_mismatch root_password_mismatch \
	CR6608_TEST_EXPECTED_ROOT=some-other-root-secret
expect_audit_failure web_wifi_reuse primary24_web_key_reuse \
	CR6608_TEST_WIFI_KEY=unique-web-secret-126
expect_audit_failure shared_web retired_shared_web_credential \
	'CR6608_TEST_WEB_HASH=$6$CR6608dashAdm$BQqw1LRyISWT1W76KgXLbFMpuB0lDBY4CVz7vdm4PMg1YZ6y9fh.GZ0hKRp8X9NGb4FR5dGd7lsMiuCOK3hwl.'

sed 's/^profile=retail-v2$/profile=retail-v1/' "$TMP/marker" > "$TMP/marker-v1"
cp "$TMP/marker" "$TMP/marker.valid"
chmod 0600 "$TMP/marker"
cp "$TMP/marker-v1" "$TMP/marker"
expect_audit_failure marker_v1 provisioning_marker_profile
mv "$TMP/marker.valid" "$TMP/marker"
chmod 0600 "$TMP/marker"

sed 's/^market_country=SA$/market_country=00/' "$TMP/marker" > "$TMP/marker-country-00"
cp "$TMP/marker" "$TMP/marker.valid"
cp "$TMP/marker-country-00" "$TMP/marker"
expect_audit_failure marker_country_00 provisioning_marker_country
mv "$TMP/marker.valid" "$TMP/marker"
chmod 0600 "$TMP/marker"

# A pending journal always overrides an older complete marker. Only the
# provisioner's explicit pending-audit mode may evaluate that in-flight state.
sed 's/^audit_complete=YES$/audit_complete=NO/' "$TMP/marker" > "$TMP/pending-marker"
chmod 0400 "$TMP/pending-marker"
expect_audit_failure pending_precedence provisioning_pending
# shellcheck disable=SC2086
env $audit_env sh "$AUDIT" --provisioning-pending \
	--root-password-file "$TMP/root-audit.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" | grep -qx \
	'retail_security=PENDING_PASS sale_ready=NO radio_policy=LAB_ARTIFACT_BLOCKED' || \
	fail 'explicit pending audit did not accept the valid provisioning journal'
rm -f "$TMP/pending-marker"

cat > "$TMP/bin/sha256sum" <<'EOF'
#!/bin/sh
printf '086f9f99e700f9d639639e9a3ea28a0bdf4838d0ddec68c9752641ab9be2779b  -\n'
EOF
chmod 0755 "$TMP/bin/sha256sum"
if env $audit_env sh "$AUDIT" \
	--root-password-file "$TMP/root-audit.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" > "$TMP/retired.out" 2>&1; then
	fail 'sale audit accepted a retired shared root credential'
fi
grep -Fq 'retired_shared_root_credential' "$TMP/retired.out" || \
	fail 'retired-credential audit failure reason is missing'
rm -f "$TMP/bin/sha256sum"
fi

# Execute provisioning transactions with non-default AP section names and a
# stateful country mirror. First, fault-inject the Wi-Fi activation: every old
# file/country and runtime must be restored without leaving a retail marker.
# Then run the success path and prove SA reaches every authoritative mirror.
mkdir -p "$TMP/device/etc/config" "$TMP/runtime-bin"
printf 'root:!:20647:0:99999:7:::\n' > "$TMP/device/etc/shadow"
printf 'old-wireless\n' > "$TMP/device/etc/config/wireless"
printf 'old-quick\n' > "$TMP/device/etc/config/cr6608quick"
printf 'old-smartap\n' > "$TMP/device/etc/config/smartap"
printf 'old-uhttpd\n' > "$TMP/device/etc/config/uhttpd"
printf 'old-rpcd\n' > "$TMP/device/etc/config/rpcd"
printf "config system\n\toption ttylogin '0'\n" > "$TMP/device/etc/config/system"
printf 'old-prplmesh\n' > "$TMP/device/etc/config/prplmesh"
printf "config dropbear main\n\toption PasswordAuth 'on'\n\toption RootPasswordAuth 'on'\n" > "$TMP/device/etc/config/dropbear"
cp "$TMP/device/etc/shadow" "$TMP/original-shadow"
cp "$TMP/device/etc/config/wireless" "$TMP/original-wireless"
cp "$TMP/device/etc/config/cr6608quick" "$TMP/original-quick"
cp "$TMP/device/etc/config/smartap" "$TMP/original-smartap"
cp "$TMP/device/etc/config/uhttpd" "$TMP/original-uhttpd"
cp "$TMP/device/etc/config/rpcd" "$TMP/original-rpcd"
cp "$TMP/device/etc/config/system" "$TMP/original-system"
cp "$TMP/device/etc/config/prplmesh" "$TMP/original-prplmesh"
cp "$TMP/device/etc/config/dropbear" "$TMP/original-dropbear"
printf '%s\n' 'unique-root-secret-42' > "$TMP/root.secret"
printf '%s\n' 'unique-wifi-secret-84' > "$TMP/wifi.secret"
printf '%s\n' 'unique-web-secret-126' > "$TMP/web.secret"

cat > "$TMP/runtime-bin/uci" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do
	printf 'uci:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"
done
[ "${1:-}" = -q ] && shift
action="${1:-}"; value="${2:-}"
is_country_key() {
	case "$1" in
		wireless.radio0.country|wireless.radio1.country|\
		smartap.quick.country24|smartap.quick.country5|\
		cr6608quick.default.country|cr6608quick.default.country24|\
		cr6608quick.default.country5) return 0 ;;
		*) return 1 ;;
	esac
}
country_get() {
	awk -F= -v wanted="$1" '
		$1 == wanted { value=$2; found=1 }
		END { if (!found) exit 1; print value }
	' "$CR6608_TEST_COUNTRY_STATE"
}
case "$action:$value" in
	batch:)
		batch_radio0=0; batch_radio1=0; batch_mirror=0
		while IFS= read -r batch_command; do
			case "$batch_command" in
				"set wireless.ap_alpha.key='$CR6608_TEST_WIFI_SECRET'"|\
				"set wireless.wifinet0.key='$CR6608_TEST_WIFI_SECRET'") batch_radio0=1 ;;
				"set wireless.ap_beta.key='$CR6608_TEST_WIFI_SECRET'") batch_radio1=1 ;;
				"set cr6608quick.default.wifi_key='$CR6608_TEST_WIFI_SECRET'") batch_mirror=1 ;;
				*) exit 1 ;;
			esac
		done
		[ "$batch_radio0" = 1 ] && [ "$batch_radio1" = 1 ] && [ "$batch_mirror" = 1 ] || exit 1
		printf 'batch wifi-secrets-from-stdin\n' >> "$CR6608_TEST_RUNTIME_LOG"
		;;
	show:wireless)
		[ "${CR6608_TEST_CANONICAL_WDS:-0}" != 1 ] || printf '%s\n' 'wireless.wifinet0=wifi-iface'
		printf '%s\n' 'wireless.guest24=wifi-iface' 'wireless.backhaul24=wifi-iface' \
			'wireless.ap_alpha=wifi-iface' 'wireless.ap_beta=wifi-iface'
		[ "${CR6608_TEST_AMBIGUOUS_PRIMARY:-0}" != 1 ] || printf '%s\n' 'wireless.ap_gamma=wifi-iface'
		;;
	show:rpcd) printf '%s\n' 'rpcd.web=login' ;;
	get:wireless.wifinet0)
		[ "${CR6608_TEST_CANONICAL_WDS:-0}" = 1 ] || exit 1
		printf 'wifi-iface\n'
		;;
	get:wireless.ap_alpha|get:wireless.ap_beta|get:wireless.ap_gamma|get:wireless.guest24|get:wireless.backhaul24) printf 'wifi-iface\n' ;;
	get:wireless.wifinet0.device)
		[ "${CR6608_TEST_CANONICAL_WDS:-0}" = 1 ] || exit 1
		printf 'radio0\n'
		;;
	get:wireless.ap_alpha.device) printf 'radio0\n' ;;
	get:wireless.ap_beta.device) printf 'radio1\n' ;;
	get:wireless.ap_gamma.device|get:wireless.guest24.device|get:wireless.backhaul24.device) printf 'radio0\n' ;;
	get:wireless.wifinet0.mode|get:wireless.wifinet0.network)
		[ "${CR6608_TEST_CANONICAL_WDS:-0}" = 1 ] || exit 1
		case "$value" in *.mode) printf 'ap\n' ;; *) printf 'lan\n' ;; esac
		;;
	get:wireless.ap_alpha.mode|get:wireless.ap_beta.mode|get:wireless.ap_gamma.mode|get:wireless.guest24.mode|get:wireless.backhaul24.mode) printf 'ap\n' ;;
	get:wireless.ap_alpha.network|get:wireless.ap_beta.network) printf 'lan\n' ;;
	get:wireless.ap_gamma.network|get:wireless.backhaul24.network) printf 'lan\n' ;;
	get:wireless.guest24.network) printf 'guest\n' ;;
	get:wireless.backhaul24.wds) printf '1\n' ;;
	get:wireless.wifinet0.wds)
		[ -e "$CR6608_TEST_WDS_STATE" ] || exit 1
		printf '1\n'
		;;
	get:wireless.ap_alpha.multi_ap)
		[ "${CR6608_TEST_PRIMARY_MULTI_AP:-0}" = 1 ] || exit 1
		printf '1\n'
		;;
	get:wireless.ap_alpha.multi_ap_backhaul_key)
		[ "${CR6608_TEST_PRIMARY_MULTI_AP:-0}" = 1 ] || exit 1
		printf 'retained-backhaul-secret\n'
		;;
	get:wireless.wifinet0.key)
		[ "${CR6608_TEST_CANONICAL_WDS:-0}" = 1 ] || exit 1
		printf 'unique-wifi-secret-84\n'
		;;
	get:wireless.ap_alpha.key|get:wireless.ap_beta.key) printf 'unique-wifi-secret-84\n' ;;
	get:rpcd.web.username) printf 'root\n' ;;
	get:rpcd.web.password) cat "$CR6608_TEST_RPCD_PASSWORD_STATE" ;;
	get:dropbear.main.PasswordAuth|get:dropbear.main.RootPasswordAuth)
		awk -F= -v wanted="$value" '$1 == wanted { print $2; found=1 } END { if (!found) exit 1 }' \
			"$CR6608_TEST_DROPBEAR_STATE"
		;;
	get:*) is_country_key "$value" && country_get "$value" ;;
	set:rpcd.web.password=*)
		printf '%s\n' "${value#*=}" > "$CR6608_TEST_RPCD_PASSWORD_STATE"
		printf 'set %s\n' "$value" >> "$CR6608_TEST_RUNTIME_LOG"
		;;
	set:dropbear.main.PasswordAuth=*|set:dropbear.main.RootPasswordAuth=*)
		key="${value%%=*}"
		grep -v "^${key}=" "$CR6608_TEST_DROPBEAR_STATE" > \
			"$CR6608_TEST_DROPBEAR_STATE.tmp" || true
		printf '%s=%s\n' "$key" "${value#*=}" >> "$CR6608_TEST_DROPBEAR_STATE.tmp"
		mv "$CR6608_TEST_DROPBEAR_STATE.tmp" "$CR6608_TEST_DROPBEAR_STATE"
		printf 'set %s\n' "$value" >> "$CR6608_TEST_RUNTIME_LOG"
		;;
	set:*)
		key="${value%%=*}"
		if is_country_key "$key"; then
			printf '%s=%s\n' "$key" "${value#*=}" >> "$CR6608_TEST_COUNTRY_STATE"
		fi
		printf 'set %s\n' "$value" >> "$CR6608_TEST_RUNTIME_LOG"
		;;
	delete:wireless.wifinet0.wds)
		rm -f "$CR6608_TEST_WDS_STATE"
		printf 'delete %s\n' "$value" >> "$CR6608_TEST_RUNTIME_LOG"
		;;
	revert:wireless|revert:cr6608quick|revert:smartap)
		[ "${CR6608_TEST_REVERT_FAIL:-}" != "$value" ] || exit 1
		cp "$CR6608_TEST_COUNTRY_INITIAL" "$CR6608_TEST_COUNTRY_STATE"
		[ "$action:$value" != revert:wireless ] || \
			[ "${CR6608_TEST_CANONICAL_WDS:-0}" != 1 ] || : > "$CR6608_TEST_WDS_STATE"
		printf '%s %s\n' "$action" "$value" >> "$CR6608_TEST_RUNTIME_LOG"
		;;
	commit:*|revert:*) printf '%s %s\n' "$action" "$value" >> "$CR6608_TEST_RUNTIME_LOG" ;;
	*) exit 1 ;;
esac
EOF
cat > "$TMP/runtime-bin/passwd" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'passwd:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
[ "$1" = -a ] && [ "$2" = sha512 ] && [ "$3" = root ] || exit 1
IFS= read -r first
IFS= read -r second
[ "$first" = "$second" ] || exit 1
printf 'root:$6$provisioned$temporary:20647:0:99999:7:::\n' > "$CR6608_TEST_SHADOW"
EOF
cat > "$TMP/runtime-bin/uhttpd" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'uhttpd:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
printf 'uhttpd %s\n' "$1" >> "$CR6608_TEST_RUNTIME_LOG"
case "$1" in running|restart|stop) exit 0 ;; *) exit 1 ;; esac
EOF
cat > "$TMP/runtime-bin/rpcd" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'rpcd:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
printf 'rpcd %s\n' "$1" >> "$CR6608_TEST_RUNTIME_LOG"
case "$1" in running|restart|stop) exit 0 ;; *) exit 1 ;; esac
EOF
cat > "$TMP/runtime-bin/openssl" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'openssl:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
sed -n '1p' >/dev/null
printf '%s\n' '$6$provsalt$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
EOF
cat > "$TMP/runtime-bin/wifi" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'wifi:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
printf 'wifi %s\n' "$1" >> "$CR6608_TEST_RUNTIME_LOG"
count="$(cat "$CR6608_TEST_WIFI_COUNT" 2>/dev/null || printf 0)"
count=$((count + 1))
printf '%s\n' "$count" > "$CR6608_TEST_WIFI_COUNT"
if [ "${CR6608_TEST_WIFI_FAIL_ONCE:-0}" = 1 ] && [ "$count" -eq 1 ]; then
	exit 1
fi
exit 0
EOF
cat > "$TMP/runtime-bin/audit" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'audit:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
[ "$1" = --provisioning-pending ] && [ "$2" = --root-password-file ] && \
	[ "$3" = "$CR6608_TEST_ROOT_PASSWORD_FILE" ] && [ "$4" = --wifi-key-file ] && \
	[ "$5" = "$CR6608_TEST_WIFI_KEY_FILE" ] && [ "$6" = --web-password-file ] && \
	[ "$7" = "$CR6608_TEST_WEB_PASSWORD_FILE" ] || exit 1
if [ "${CR6608_TEST_POWER_CUT:-0}" = 1 ]; then
	grep -Fxq 'audit_complete=NO' "$CR6608_TEST_PENDING_MARKER" || exit 1
	printf 'power-cut-at-pending-audit\n' >> "$CR6608_TEST_RUNTIME_LOG"
	kill -KILL "$PPID"
	exit 137
fi
audit_count="$(cat "$CR6608_TEST_AUDIT_COUNT_FILE" 2>/dev/null || printf 0)"
audit_count=$((audit_count + 1))
printf '%s\n' "$audit_count" > "$CR6608_TEST_AUDIT_COUNT_FILE"
printf 'audit-called\n' >> "$CR6608_TEST_RUNTIME_LOG"
if [ "${CR6608_TEST_AUDIT_NEVER_READY:-0}" = 1 ] || \
	[ "$audit_count" -lt "${CR6608_TEST_AUDIT_READY_AFTER:-1}" ]; then
	printf 'retail_security=FAIL reason=primary24_hostapd_not_enabled\n' >&2
	exit 1
fi
if [ "${CR6608_TEST_HOLD_AUDIT:-0}" = 1 ]; then
	: > "$CR6608_TEST_AUDIT_READY"
	while [ ! -e "$CR6608_TEST_AUDIT_RELEASE" ]; do sleep 0.05; done
fi
exit 0
EOF
cat > "$TMP/runtime-bin/sleep" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'sleep:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
exit 0
EOF
cat > "$TMP/runtime-bin/prplmesh-sync" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'prplmesh-sync:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
case "${1:-}:${2:-}:${3:-}" in
	--stage:ap_alpha:ap_beta|--verify:ap_alpha:ap_beta|\
	--stage:wifinet0:ap_beta|--verify:wifinet0:ap_beta) ;;
	*) exit 1 ;;
esac
printf 'prplmesh-sync %s %s %s\n' "$1" "$2" "$3" >> "$CR6608_TEST_RUNTIME_LOG"
EOF
cat > "$TMP/bin/cp" <<'EOF'
#!/bin/sh
for captured_arg in "$@"; do printf 'cp:%s\n' "$captured_arg" >> "$CR6608_TEST_ARGV_LOG"; done
if [ "${CR6608_TEST_RESTORE_COPY_FAIL:-0}" = 1 ] && [ "${1:-}" = -pf ] && \
	[ "${3:-}" = "$CR6608_TEST_SHADOW" ]; then
	exit 1
fi
exec /usr/bin/cp "$@"
EOF
cat > "$TMP/runtime-bin/cache-state" <<'EOF'
#!/bin/sh
CR6608_DASHBOARD_CACHE_MUTATION_OWNER=0
cr6608_dashboard_cache_mutation_begin() {
	mkdir "$CR6608_TEST_MUTATION_LOCK_DIR" 2>/dev/null || return 1
	printf '%s\n' "$$" > "$CR6608_TEST_MUTATION_LOCK_DIR/owner" || return 1
	CR6608_DASHBOARD_CACHE_MUTATION_OWNER=1
	printf 'mutation-begin\n' >> "$CR6608_TEST_RUNTIME_LOG"
}
cr6608_dashboard_cache_mutation_finish() {
	[ "$CR6608_DASHBOARD_CACHE_MUTATION_OWNER" = 1 ] || return 0
	rm -f "$CR6608_TEST_MUTATION_LOCK_DIR/owner" 2>/dev/null || true
	rmdir "$CR6608_TEST_MUTATION_LOCK_DIR" 2>/dev/null || true
	CR6608_DASHBOARD_CACHE_MUTATION_OWNER=0
	printf 'mutation-finish\n' >> "$CR6608_TEST_RUNTIME_LOG"
}
EOF
chmod 0755 "$TMP/runtime-bin/"*
chmod 0755 "$TMP/bin/cp"
: > "$TMP/runtime.log"
: > "$TMP/wifi.count"
: > "$TMP/argv.log"
printf 'old-web-hash\n' > "$TMP/rpcd-password.state"
cat > "$TMP/country.initial" <<'EOF'
wireless.radio0.country=US
wireless.radio1.country=US
smartap.quick.country24=US
smartap.quick.country5=US
cr6608quick.default.country=US
cr6608quick.default.country24=US
cr6608quick.default.country5=US
EOF
cp "$TMP/country.initial" "$TMP/country.state"
printf '%s\n' 'dropbear.main.PasswordAuth=off' 'dropbear.main.RootPasswordAuth=off' > "$TMP/dropbear.state"
runtime_env="CR6608_TEST_SHADOW=$TMP/device/etc/shadow CR6608_TEST_RUNTIME_LOG=$TMP/runtime.log CR6608_TEST_ARGV_LOG=$TMP/argv.log CR6608_TEST_WIFI_COUNT=$TMP/wifi.count CR6608_TEST_AUDIT_COUNT_FILE=$TMP/audit.count CR6608_TEST_RPCD_PASSWORD_STATE=$TMP/rpcd-password.state CR6608_TEST_DROPBEAR_STATE=$TMP/dropbear.state CR6608_TEST_ROOT_PASSWORD_FILE=$TMP/root.secret CR6608_TEST_WEB_PASSWORD_FILE=$TMP/web.secret CR6608_TEST_WIFI_KEY_FILE=$TMP/wifi.secret CR6608_TEST_WIFI_SECRET=unique-wifi-secret-84 CR6608_TEST_PENDING_MARKER=$TMP/device/etc/cr6608-retail-provisioning-pending CR6608_TEST_COUNTRY_STATE=$TMP/country.state CR6608_TEST_COUNTRY_INITIAL=$TMP/country.initial CR6608_TEST_MUTATION_LOCK_DIR=$TMP/mutation-lock CR6608_TEST_WDS_STATE=$TMP/wds.state"
chmod 0600 "$TMP/root.secret" "$TMP/wifi.secret" "$TMP/web.secret"

# The mobile login normalizes clipboard whitespace and display controls.  A
# retail web credential must therefore use the documented reproducible ASCII
# alphabet; reject an otherwise long value before any transaction mutation.
cp "$TMP/web.secret" "$TMP/web.secret.valid"
# Leading whitespace is deliberately significant here: the Smart AP login
# normalizer strips it, so accepting this credential would provision a valid
# rpcd password which no user could reproduce through the login form.
printf '%s\n' ' leading-space-web-secret-84' > "$TMP/web.secret"
# shellcheck disable=SC2086
if env $runtime_env sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/provision-web-alphabet.out" 2>&1; then
	fail 'provisioner accepted a web password the Smart AP login cannot reproduce'
fi
grep -Fq 'reason=web_password_unsupported_character' "$TMP/provision-web-alphabet.out" || \
	fail 'unsupported web-password alphabet returned the wrong reason'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioning-pending" ] || \
	fail 'invalid web-password alphabet mutated durable provisioning state'
mv "$TMP/web.secret.valid" "$TMP/web.secret"
chmod 0600 "$TMP/web.secret"

# The apply-lock creator publishes recoverable PID/start evidence before mkdir.
# Kill the process after every acquisition publication step, then prove the
# next nonblocking transaction reclaims only dead state and reaches AP policy.
for lock_step in claim-temp-ready claim-published directory-owned owner-published; do
	lock_variant="$TMP/provision-lock-crash-$lock_step"
	awk -v needle="apply-lock-step: $lock_step" '
		{ print }
		index($0, needle) { print "\tkill -KILL $$"; found++ }
		END { if (found != 1) exit 2 }
	' "$PROVISION" > "$lock_variant" || fail "could not create lock crash fixture: $lock_step"
	chmod 0755 "$lock_variant"
	# shellcheck disable=SC2086
	if env $runtime_env sh "$lock_variant" --root-password-file "$TMP/root.secret" \
		--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
		--market-country SA > "$TMP/lock-crash-$lock_step.out" 2>&1; then
		fail "apply-lock crash fixture unexpectedly returned success: $lock_step"
	fi
	# shellcheck disable=SC2086
	if env $runtime_env CR6608_TEST_PRIMARY_MULTI_AP=1 sh "$PROVISION" \
		--root-password-file "$TMP/root.secret" --wifi-key-file "$TMP/wifi.secret" \
		--web-password-file "$TMP/web.secret" --market-country SA \
		> "$TMP/lock-recover-$lock_step.out" 2>&1; then
		fail "lock recovery probe unexpectedly provisioned: $lock_step"
	fi
	grep -Fq 'reason=radio0_primary_ap_missing' "$TMP/lock-recover-$lock_step.out" || \
		fail "dead apply-lock acquisition state was not recovered: $lock_step"
	[ ! -e "$TMP/cr6608-apply.lock" ] && [ ! -L "$TMP/cr6608-apply.lock" ] || \
		fail "apply-lock directory remained after recovery: $lock_step"
	for stale_claim in "$TMP"/.cr6608-apply.claim.*; do
		[ ! -e "$stale_claim" ] && [ ! -L "$stale_claim" ] || \
			fail "stable apply-lock claim remained after recovery: $lock_step"
	done
done

# A live creator paused after mkdir but before owner publication protects the
# ownerless directory with its external PID/start claim. A contender must fail
# busy without mutation; after release, the creator completes and cleans up.
ownerless_variant="$TMP/provision-lock-ownerless-live"
awk '
	{ print }
	/apply-lock-step: directory-owned/ {
		print "\t: > \"$CR6608_TEST_OWNERLESS_READY\""
		print "\twhile [ ! -e \"$CR6608_TEST_OWNERLESS_RELEASE\" ]; do /usr/bin/sleep 0.05; done"
		found++
	}
	END { if (found != 1) exit 2 }
' "$PROVISION" > "$ownerless_variant" || fail 'could not create live ownerless-lock fixture'
chmod 0755 "$ownerless_variant"
rm -f "$TMP/ownerless-ready" "$TMP/ownerless-release"
# shellcheck disable=SC2086
env $runtime_env CR6608_TEST_PRIMARY_MULTI_AP=1 \
	CR6608_TEST_OWNERLESS_READY="$TMP/ownerless-ready" \
	CR6608_TEST_OWNERLESS_RELEASE="$TMP/ownerless-release" \
	sh "$ownerless_variant" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/ownerless-creator.out" 2>&1 &
concurrent_pid=$!
wait_loops=0
while [ ! -e "$TMP/ownerless-ready" ] && kill -0 "$concurrent_pid" 2>/dev/null; do
	[ "$wait_loops" -lt 2000 ] || fail 'live ownerless-lock creator did not reach mkdir window'
	wait_loops=$((wait_loops + 1))
	sleep 0.05
done
[ -e "$TMP/ownerless-ready" ] || fail 'live ownerless-lock creator exited early'
# shellcheck disable=SC2086
if env $runtime_env CR6608_TEST_PRIMARY_MULTI_AP=1 sh "$PROVISION" \
	--root-password-file "$TMP/root.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" --market-country SA \
	> "$TMP/ownerless-contender.out" 2>&1; then
	fail 'ownerless-lock contender unexpectedly succeeded'
fi
grep -Fq 'reason=provisioning_busy' "$TMP/ownerless-contender.out" || \
	fail 'ownerless-lock contender stole or misclassified a live creator'
: > "$TMP/ownerless-release"
if wait "$concurrent_pid"; then
	fail 'ownerless-lock creator unexpectedly passed the Multi-AP policy probe'
fi
concurrent_pid=''
grep -Fq 'reason=radio0_primary_ap_missing' "$TMP/ownerless-creator.out" || \
	fail 'ownerless-lock creator did not resume after release'
[ ! -e "$TMP/cr6608-apply.lock" ] && [ ! -L "$TMP/cr6608-apply.lock" ] || \
	fail 'live ownerless-lock fixture left the apply lock behind'

# A canonical/fallback Multi-AP BSS carries a distinct backhaul role and
# credential.  Manufacturing must fail before journaling or repurposing it.
# shellcheck disable=SC2086
if env $runtime_env CR6608_TEST_PRIMARY_MULTI_AP=1 sh "$PROVISION" \
	--root-password-file "$TMP/root.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" --market-country SA \
	> "$TMP/provision-multi-ap.out" 2>&1; then
	fail 'Multi-AP primary provisioning unexpectedly succeeded'
fi
grep -Fq 'reason=radio0_primary_ap_missing' "$TMP/provision-multi-ap.out" || \
	fail 'Multi-AP primary returned the wrong failure reason'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioning-pending" ] || \
	fail 'Multi-AP primary rejection mutated the durable provisioning state'

# Two fallback LAN APs are ambiguous.  A guest BSS and a WDS backhaul are
# present in every fixture and must never count as a primary candidate.
# shellcheck disable=SC2086
if env $runtime_env CR6608_TEST_AMBIGUOUS_PRIMARY=1 sh "$PROVISION" \
	--root-password-file "$TMP/root.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" --market-country SA \
	> "$TMP/provision-ambiguous.out" 2>&1; then
	fail 'ambiguous primary AP provisioning unexpectedly succeeded'
fi
grep -Fq 'reason=radio0_primary_ap_ambiguous' "$TMP/provision-ambiguous.out" || \
	fail 'ambiguous primary AP returned the wrong failure reason'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioning-pending" ] || \
	fail 'primary AP ambiguity mutated the durable provisioning state'

# shellcheck disable=SC2086
if env $runtime_env CR6608_TEST_WIFI_FAIL_ONCE=1 sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA \
	> "$TMP/provision.out" 2>&1; then
	fail 'fault-injected Wi-Fi activation unexpectedly succeeded'
fi
grep -Fq 'reason=wifi_reload' "$TMP/provision.out" || \
	fail 'fault-injected provisioning failed for the wrong reason'
cmp -s "$TMP/original-shadow" "$TMP/device/etc/shadow" || \
	fail 'failed provisioning did not restore the previous root credential'
cmp -s "$TMP/original-wireless" "$TMP/device/etc/config/wireless" || \
	fail 'failed provisioning did not restore the previous wireless configuration'
cmp -s "$TMP/original-quick" "$TMP/device/etc/config/cr6608quick" || \
	fail 'failed provisioning did not restore the previous Quick Settings configuration'
cmp -s "$TMP/original-smartap" "$TMP/device/etc/config/smartap" || \
	fail 'failed provisioning did not restore the previous Smart AP configuration'
cmp -s "$TMP/original-rpcd" "$TMP/device/etc/config/rpcd" || \
	fail 'failed provisioning did not restore the previous rpcd configuration'
cmp -s "$TMP/original-system" "$TMP/device/etc/config/system" || \
	fail 'failed provisioning did not restore the serial-login policy'
cmp -s "$TMP/original-prplmesh" "$TMP/device/etc/config/prplmesh" || \
	fail 'failed provisioning did not restore the previous prplmesh configuration'
[ "$(grep -Fc 'uhttpd restart' "$TMP/runtime.log")" -eq 2 ] || \
	fail 'failed provisioning did not restore the previous uhttpd runtime'
[ "$(grep -Fc 'rpcd restart' "$TMP/runtime.log")" -eq 2 ] || \
	fail 'failed provisioning did not restore the previous rpcd runtime'
[ "$(grep -Fc 'wifi reload' "$TMP/runtime.log")" -eq 2 ] || \
	fail 'failed provisioning did not reapply the previous Wi-Fi runtime'
grep -Fq 'wireless.ap_alpha.encryption=sae-mixed' "$TMP/runtime.log" || \
	fail 'dynamic radio0 AP was not provisioned'
grep -Fq 'wireless.ap_beta.encryption=sae-mixed' "$TMP/runtime.log" || \
	fail 'dynamic radio1 AP was not provisioned'
! grep -Eq 'wireless\.(guest24|backhaul24)\.(encryption|key|disabled)=' "$TMP/runtime.log" || \
	fail 'guest or backhaul AP was modified as a primary AP'
grep -Fq 'system.@system[0].ttylogin=1' "$TMP/runtime.log" || \
	fail 'provisioning transaction did not password-gate the serial console'
! grep -Fq 'audit-called' "$TMP/runtime.log" || \
	fail 'audit ran after a failed Wi-Fi activation'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioned" ] && \
	[ ! -L "$TMP/device/etc/cr6608-retail-provisioned" ] || \
	fail 'failed country activation left a misleading retail marker'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioning-pending" ] && \
	[ ! -L "$TMP/device/etc/cr6608-retail-provisioning-pending" ] || \
	fail 'ordinary rollback left a stale provisioning journal'
cmp -s "$TMP/country.initial" "$TMP/country.state" || \
	fail 'failed country activation did not restore every previous country mirror'

reset_transaction_fixture() {
	chmod 0600 "$TMP/device/etc/cr6608-retail-provisioned" \
		"$TMP/device/etc/cr6608-retail-provisioning-pending" 2>/dev/null || true
	rm -f "$TMP/device/etc/cr6608-retail-provisioned" \
		"$TMP/device/etc/cr6608-retail-provisioning-pending" "$TMP/wds.state"
	cp "$TMP/original-shadow" "$TMP/device/etc/shadow"
	cp "$TMP/original-wireless" "$TMP/device/etc/config/wireless"
	cp "$TMP/original-quick" "$TMP/device/etc/config/cr6608quick"
	cp "$TMP/original-smartap" "$TMP/device/etc/config/smartap"
	cp "$TMP/original-uhttpd" "$TMP/device/etc/config/uhttpd"
	cp "$TMP/original-rpcd" "$TMP/device/etc/config/rpcd"
	cp "$TMP/original-system" "$TMP/device/etc/config/system"
	cp "$TMP/original-prplmesh" "$TMP/device/etc/config/prplmesh"
	printf 'old-web-hash\n' > "$TMP/rpcd-password.state"
	cp "$TMP/country.initial" "$TMP/country.state"
	: > "$TMP/runtime.log"
	: > "$TMP/argv.log"
	: > "$TMP/wifi.count"
	: > "$TMP/audit.count"
}

assert_device_pending_rejected() {
	pending_case="$1"
	chmod 0600 "$TMP/pending-marker" 2>/dev/null || true
	rm -f "$TMP/pending-marker"
	cp "$TMP/device/etc/cr6608-retail-provisioning-pending" "$TMP/pending-marker"
	chmod 0400 "$TMP/pending-marker"
	expect_audit_failure "$pending_case" provisioning_pending
	chmod 0600 "$TMP/pending-marker"
	rm -f "$TMP/pending-marker"
}

# Marker restoration is the last rollback step. If a configuration copy or UCI
# revert fails, the old complete marker must not reappear: a synchronized
# pending journal remains and the normal sale audit refuses the mixed state.
for rollback_fault in restore_copy revert_wireless; do
	reset_transaction_fixture
	case "$rollback_fault" in
		restore_copy) rollback_fault_env='CR6608_TEST_RESTORE_COPY_FAIL=1' ;;
		*) rollback_fault_env='CR6608_TEST_REVERT_FAIL=wireless' ;;
	esac
	# shellcheck disable=SC2086
	if env $runtime_env $rollback_fault_env CR6608_TEST_WIFI_FAIL_ONCE=1 sh "$PROVISION" \
		--root-password-file "$TMP/root.secret" --wifi-key-file "$TMP/wifi.secret" \
		--web-password-file "$TMP/web.secret" --market-country SA \
		> "$TMP/provision-$rollback_fault.out" 2>&1; then
		fail "rollback fault unexpectedly provisioned: $rollback_fault"
	fi
	grep -Fq 'reason=wifi_reload_rollback_failed' "$TMP/provision-$rollback_fault.out" || \
		fail "rollback fault returned the wrong reason: $rollback_fault"
	grep -Fxq 'audit_complete=NO' "$TMP/device/etc/cr6608-retail-provisioning-pending" || \
		fail "rollback fault did not retain a valid pending journal: $rollback_fault"
	[ ! -e "$TMP/device/etc/cr6608-retail-provisioned" ] && \
		[ ! -L "$TMP/device/etc/cr6608-retail-provisioned" ] || \
		fail "rollback fault restored an unsafe complete marker: $rollback_fault"
	assert_device_pending_rejected "rollback_$rollback_fault"
done

# Signals use the identical rollback state machine. Hold the pending audit,
# inject a failed wireless revert, send TERM, then release the child so ash can
# run its trap; the mixed state must remain fail-closed and retryable.
reset_transaction_fixture
rm -f "$TMP/audit-ready" "$TMP/audit-release"
# shellcheck disable=SC2086
env $runtime_env CR6608_TEST_HOLD_AUDIT=1 CR6608_TEST_REVERT_FAIL=wireless \
	CR6608_TEST_AUDIT_READY="$TMP/audit-ready" \
	CR6608_TEST_AUDIT_RELEASE="$TMP/audit-release" \
	sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/provision-signal.out" 2>&1 &
concurrent_pid=$!
wait_loops=0
while [ ! -e "$TMP/audit-ready" ] && kill -0 "$concurrent_pid" 2>/dev/null; do
	[ "$wait_loops" -lt 2000 ] || fail 'signal fixture did not reach the pending audit'
	wait_loops=$((wait_loops + 1))
	sleep 0.05
done
[ -e "$TMP/audit-ready" ] || fail 'signal fixture exited before the pending audit'
kill -TERM "$concurrent_pid"
: > "$TMP/audit-release"
if wait "$concurrent_pid"; then
	fail 'TERM-interrupted provisioner unexpectedly returned success'
fi
concurrent_pid=''
grep -Fxq 'audit_complete=NO' "$TMP/device/etc/cr6608-retail-provisioning-pending" || \
	fail 'signal rollback failure did not retain the pending journal'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioned" ] && \
	[ ! -L "$TMP/device/etc/cr6608-retail-provisioned" ] || \
	fail 'signal rollback failure retained a complete marker'
assert_device_pending_rejected signal_rollback

# A canonical AP left in WDS sender mode is the deterministic provisioning
# target. netifd/hostapd may become ready after the reload returns, so two
# transient audit failures must be retried and the third successful binding
# must publish the complete marker without releasing either transaction lock.
reset_transaction_fixture
: > "$TMP/wds.state"
# shellcheck disable=SC2086
env $runtime_env CR6608_TEST_CANONICAL_WDS=1 CR6608_TEST_AUDIT_READY_AFTER=3 \
	sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/provision-delayed-ready.out" 2>&1 || \
	fail 'delayed primary runtime readiness did not converge'
[ "$(cat "$TMP/audit.count")" -eq 3 ] && \
	[ "$(grep -Fc 'audit-called' "$TMP/runtime.log")" -eq 3 ] || \
	fail 'transient primary readiness was not retried exactly to success'
grep -Fxq 'primary_ap_radio0=wifinet0' "$TMP/device/etc/cr6608-retail-provisioned" || \
	fail 'canonical WDS sender was not selected deterministically'
grep -Fxq 'delete wireless.wifinet0.wds' "$TMP/runtime.log" && \
	[ ! -e "$TMP/wds.state" ] || fail 'canonical WDS sender was not converted to a normal AP'
grep -Fxq 'batch wifi-secrets-from-stdin' "$TMP/runtime.log" || \
	fail 'Wi-Fi secrets were not staged through UCI batch stdin'
for secret_file in "$TMP/root.secret" "$TMP/wifi.secret" "$TMP/web.secret"; do
	secret_value="$(sed -n '1p' "$secret_file")"
	! grep -Fq -- "$secret_value" "$TMP/argv.log" || \
		fail "plaintext secret appeared in external argv: ${secret_file##*/}"
done

# Restore the fixture to its original unprovisioned state, then make runtime
# readiness fail on every bounded attempt. The timeout must roll back files,
# services, Wi-Fi state, and both durable markers.
reset_transaction_fixture
# shellcheck disable=SC2086
if env $runtime_env CR6608_TEST_AUDIT_NEVER_READY=1 sh "$PROVISION" \
	--root-password-file "$TMP/root.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" --market-country SA \
	> "$TMP/provision-never-ready.out" 2>&1; then
	fail 'permanently unavailable primary runtime unexpectedly provisioned'
fi
grep -Fq 'reason=post_provision_runtime_timeout' "$TMP/provision-never-ready.out" || \
	fail 'permanent primary readiness failure returned the wrong reason'
[ "$(cat "$TMP/audit.count")" -eq 3 ] || \
	fail 'primary readiness timeout did not honor the bounded attempt count'
cmp -s "$TMP/original-shadow" "$TMP/device/etc/shadow" && \
	cmp -s "$TMP/original-wireless" "$TMP/device/etc/config/wireless" && \
	cmp -s "$TMP/original-rpcd" "$TMP/device/etc/config/rpcd" && \
	cmp -s "$TMP/original-prplmesh" "$TMP/device/etc/config/prplmesh" || \
	fail 'primary readiness timeout did not restore credential/config files'
[ "$(grep -Fc 'wifi reload' "$TMP/runtime.log")" -eq 2 ] || \
	fail 'primary readiness timeout did not restore the previous Wi-Fi runtime'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioned" ] && \
	[ ! -e "$TMP/device/etc/cr6608-retail-provisioning-pending" ] || \
	fail 'primary readiness timeout left a complete or pending marker'

# SIGKILL models loss of power after runtime activation reaches the pending
# audit but before the complete marker can be published.  There is deliberately
# no shell trap/rollback in this case: the durable journal is the recovery gate.
: > "$TMP/runtime.log"
: > "$TMP/wifi.count"
# shellcheck disable=SC2086
if env $runtime_env CR6608_TEST_POWER_CUT=1 sh "$PROVISION" \
	--root-password-file "$TMP/root.secret" --wifi-key-file "$TMP/wifi.secret" \
	--web-password-file "$TMP/web.secret" --market-country SA \
	> "$TMP/provision-power-cut.out" 2>&1; then
	fail 'power-cut provisioning fixture unexpectedly completed'
fi
grep -Fxq 'audit_complete=NO' "$TMP/device/etc/cr6608-retail-provisioning-pending" || \
	fail 'power cut did not retain the durable pending journal'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioned" ] || \
	fail 'power cut published an unaudited complete marker'
grep -Fq 'power-cut-at-pending-audit' "$TMP/runtime.log" || \
	fail 'power-cut fixture did not reach the pending audit boundary'
# The production flock is released by the kernel on SIGKILL.  The portable
# test double uses a directory, so model that kernel cleanup explicitly.
rm -f "$TMP/mutation-lock/owner"
rmdir "$TMP/mutation-lock"
rm -f "$TMP/cr6608-apply.lock/owner"
rmdir "$TMP/cr6608-apply.lock"

cp "$TMP/device/etc/shadow" "$TMP/pending-shadow"
cp "$TMP/device/etc/config/rpcd" "$TMP/pending-rpcd"
printf 'xiaomi,mi-router-cr6608\n' > "$TMP/board-name"
cat > "$TMP/runtime-bin/migration-uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = -q ] && shift
action="${1:-}"; key="${2:-}"
case "$action:$key" in
	get:wireless.radio0|get:wireless.radio1) printf 'wifi-device\n' ;;
	set:wireless.radio0.disabled=1|set:wireless.radio1.disabled=1)
		printf '%s:%s\n' "$action" "$key" >> "$CR6608_TEST_MIGRATION_LOG"
		;;
	commit:wireless)
		printf '%s:%s\n' "$action" "$key" >> "$CR6608_TEST_MIGRATION_LOG"
		;;
	*) exit 1 ;;
esac
EOF
cat > "$TMP/runtime-bin/migration-logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$TMP/runtime-bin/migration-uci" "$TMP/runtime-bin/migration-logger"
: > "$TMP/migration.log"
if env CR6608_TEST_MIGRATION_LOG="$TMP/migration.log" \
	CR6608_MIGRATION_UCI_BIN="$TMP/runtime-bin/migration-uci" \
	CR6608_MIGRATION_LOGGER_BIN="$TMP/runtime-bin/migration-logger" \
	CR6608_MIGRATION_BOARD_NAME_FILE="$TMP/board-name" \
	CR6608_MIGRATION_RETAIL_MARKER="$TMP/device/etc/cr6608-retail-provisioned" \
	CR6608_MIGRATION_PENDING_MARKER="$TMP/device/etc/cr6608-retail-provisioning-pending" \
	CR6608_MIGRATION_STAT_BIN="$TMP/bin/stat" \
	sh "$PRESERVED_MIGRATION" > "$TMP/migration-power-cut.out" 2>&1; then
	fail 'pending-marker reboot migration did not remain retryable/fail-closed'
fi
grep -Fxq 'set:wireless.radio0.disabled=1' "$TMP/migration.log" && \
	grep -Fxq 'set:wireless.radio1.disabled=1' "$TMP/migration.log" && \
	grep -Fxq 'commit:wireless' "$TMP/migration.log" || \
	fail 'pending-marker reboot did not disable both radios'
! grep -Eq 'rpcd|wireless\..*\.(key|encryption)=' "$TMP/migration.log" || \
	fail 'pending-marker reboot changed a credential or entered onboarding'
cmp -s "$TMP/pending-shadow" "$TMP/device/etc/shadow" && \
	cmp -s "$TMP/pending-rpcd" "$TMP/device/etc/config/rpcd" || \
	fail 'pending-marker reboot did not preserve provisioned credentials'

# Country 00 is not an assignable manufacturing domain.  A formally complete
# marker carrying it is invalid and must take the same fail-closed boot path.
cat > "$TMP/device/etc/cr6608-retail-provisioned" <<'EOF'
profile=retail-v2
market_country=00
primary_ap_radio0=ap_alpha
primary_ap_radio1=ap_beta
sale_ready=NO
radio_policy=LAB_ARTIFACT_BLOCKED
audit_complete=YES
provisioned_utc=2026-08-23T00:00:00Z
EOF
chmod 0400 "$TMP/device/etc/cr6608-retail-provisioned"
rm -f "$TMP/device/etc/cr6608-retail-provisioning-pending"
: > "$TMP/migration.log"
if env CR6608_TEST_MIGRATION_LOG="$TMP/migration.log" \
	CR6608_MIGRATION_UCI_BIN="$TMP/runtime-bin/migration-uci" \
	CR6608_MIGRATION_LOGGER_BIN="$TMP/runtime-bin/migration-logger" \
	CR6608_MIGRATION_BOARD_NAME_FILE="$TMP/board-name" \
	CR6608_MIGRATION_RETAIL_MARKER="$TMP/device/etc/cr6608-retail-provisioned" \
	CR6608_MIGRATION_PENDING_MARKER="$TMP/device/etc/cr6608-retail-provisioning-pending" \
	CR6608_MIGRATION_STAT_BIN="$TMP/bin/stat" \
	sh "$PRESERVED_MIGRATION" > "$TMP/migration-country-00.out" 2>&1; then
	fail 'country-00 retail marker did not remain retryable/fail-closed'
fi
grep -Fxq 'set:wireless.radio0.disabled=1' "$TMP/migration.log" && \
	grep -Fxq 'set:wireless.radio1.disabled=1' "$TMP/migration.log" || \
	fail 'country-00 marker did not disable both radios'
rm -f "$TMP/device/etc/cr6608-retail-provisioned"

# A controlled factory retry starts from the retained configuration.  Reset the
# test double's file-backed state only so the normal success path remains
# deterministic; a real rerun overwrites the same credentials transactionally.
rm -f "$TMP/device/etc/cr6608-retail-provisioning-pending"
cp "$TMP/original-shadow" "$TMP/device/etc/shadow"
cp "$TMP/original-wireless" "$TMP/device/etc/config/wireless"
cp "$TMP/original-quick" "$TMP/device/etc/config/cr6608quick"
cp "$TMP/original-smartap" "$TMP/device/etc/config/smartap"
cp "$TMP/original-uhttpd" "$TMP/device/etc/config/uhttpd"
cp "$TMP/original-rpcd" "$TMP/device/etc/config/rpcd"
cp "$TMP/original-system" "$TMP/device/etc/config/system"
cp "$TMP/original-prplmesh" "$TMP/device/etc/config/prplmesh"
printf 'old-web-hash\n' > "$TMP/rpcd-password.state"

: > "$TMP/runtime.log"
: > "$TMP/wifi.count"
cp "$TMP/country.initial" "$TMP/country.state"
# Hold the first process inside its audit while a second provisioner attempts
# to start.  The shared lock must reject the second process immediately and
# before it can alter the pending journal or any configuration/runtime log.
rm -f "$TMP/audit-ready" "$TMP/audit-release"
# shellcheck disable=SC2086
env $runtime_env CR6608_TEST_HOLD_AUDIT=1 \
	CR6608_TEST_AUDIT_READY="$TMP/audit-ready" \
	CR6608_TEST_AUDIT_RELEASE="$TMP/audit-release" \
	sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/provision-success.out" 2>&1 &
concurrent_pid=$!
wait_loops=0
while [ ! -e "$TMP/audit-ready" ] && kill -0 "$concurrent_pid" 2>/dev/null; do
	[ "$wait_loops" -lt 2000 ] || fail 'first provisioner did not reach the held audit'
	wait_loops=$((wait_loops + 1))
	sleep 0.05
done
[ -e "$TMP/audit-ready" ] || fail 'first provisioner exited before its held audit'
runtime_lines_before="$(wc -l < "$TMP/runtime.log" | tr -d ' ')"
pending_before="$(cksum "$TMP/device/etc/cr6608-retail-provisioning-pending")"
# shellcheck disable=SC2086
if env $runtime_env sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/provision-concurrent.out" 2>&1; then
	fail 'concurrent second provisioner unexpectedly succeeded'
fi
grep -Fq 'reason=provisioning_busy' "$TMP/provision-concurrent.out" || \
	fail 'concurrent second provisioner returned the wrong failure reason'
[ "$(wc -l < "$TMP/runtime.log" | tr -d ' ')" = "$runtime_lines_before" ] || \
	fail 'concurrent second provisioner mutated configuration/runtime state'
[ "$(cksum "$TMP/device/etc/cr6608-retail-provisioning-pending")" = "$pending_before" ] || \
	fail 'concurrent second provisioner rewrote the pending journal'
: > "$TMP/audit-release"
wait "$concurrent_pid" || fail 'country-synchronized provisioning success path failed'
concurrent_pid=''
grep -qx 'security_provision=PASS sale_ready=NO radio_policy=LAB_ARTIFACT_BLOCKED reboot_required=1' \
	"$TMP/provision-success.out" || fail 'provisioning success label changed or omitted the LAB sale block'
for country_key in \
	wireless.radio0.country wireless.radio1.country \
	smartap.quick.country24 smartap.quick.country5 \
	cr6608quick.default.country cr6608quick.default.country24 \
	cr6608quick.default.country5; do
	country_value="$(awk -F= -v wanted="$country_key" \
		'$1 == wanted { value=$2 } END { print value }' "$TMP/country.state")"
	[ "$country_value" = SA ] || fail "market country did not reach $country_key"
	grep -Fqx "set ${country_key}=SA" "$TMP/runtime.log" || \
		fail "market country was not staged for $country_key"
done
[ "$(grep -Fc 'wifi reload' "$TMP/runtime.log")" -eq 1 ] || \
	fail 'successful country provisioning did not perform exactly one Wi-Fi reload'
[ "$(grep -Fc 'audit-called' "$TMP/runtime.log")" -eq 1 ] || \
	fail 'successful country provisioning did not perform exactly one final audit'
grep -Fxq 'prplmesh-sync --stage ap_alpha ap_beta' "$TMP/runtime.log" && \
	grep -Fxq 'prplmesh-sync --verify ap_alpha ap_beta' "$TMP/runtime.log" || \
	fail 'successful provisioning did not stage and verify prplmesh credentials'
success_wifi_line="$(grep -n '^wifi reload$' "$TMP/runtime.log" | cut -d: -f1)"
success_audit_line="$(grep -n '^audit-called$' "$TMP/runtime.log" | cut -d: -f1)"
[ -n "$success_wifi_line" ] && [ -n "$success_audit_line" ] && \
	[ "$success_wifi_line" -lt "$success_audit_line" ] || \
	fail 'final audit ran before the synchronized country was reloaded'
grep -Fxq 'profile=retail-v2' "$TMP/device/etc/cr6608-retail-provisioned" && \
	grep -Fxq 'market_country=SA' "$TMP/device/etc/cr6608-retail-provisioned" && \
	grep -Fxq 'primary_ap_radio0=ap_alpha' "$TMP/device/etc/cr6608-retail-provisioned" && \
	grep -Fxq 'primary_ap_radio1=ap_beta' "$TMP/device/etc/cr6608-retail-provisioned" && \
	grep -Fxq 'sale_ready=NO' "$TMP/device/etc/cr6608-retail-provisioned" && \
	grep -Fxq 'radio_policy=LAB_ARTIFACT_BLOCKED' "$TMP/device/etc/cr6608-retail-provisioned" && \
	grep -Fxq 'audit_complete=YES' "$TMP/device/etc/cr6608-retail-provisioned" && \
	[ "$(wc -l < "$TMP/device/etc/cr6608-retail-provisioned" | tr -d ' ')" = 8 ] || \
	fail 'successful country provisioning wrote an invalid or sale-ready marker'
[ ! -e "$TMP/device/etc/cr6608-retail-provisioning-pending" ] || \
	fail 'successful provisioning retained its pending journal'

# The RAM-only commissioning path must atomically rotate to the unique root
# password, re-enable password authentication for the final generic Retail
# image, pass the in-transaction pending audit, and remove both factory access
# artifacts before the completed marker is published.
mkdir -p "$TMP/device/etc/dropbear"
cat > "$TMP/device/etc/cr6608-retail-commissioning-ram" <<'EOF'
profile=retail-commissioning-ram-v1
sale_ready=NO
boot_policy=ram-only
password_auth=disabled
factory_key_fingerprint=SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
factory_key_sha256=d036215e80ab00eb6c293e7191559083a773345a0c0de1948e7d4a47436a0e0c
EOF
printf 'ssh-ed25519 test commissioning\n' > \
	"$TMP/device/etc/dropbear/authorized_keys"
chmod 0400 "$TMP/device/etc/cr6608-retail-commissioning-ram"
chmod 0600 "$TMP/device/etc/dropbear/authorized_keys"
printf "config dropbear main\n\toption PasswordAuth 'off'\n\toption RootPasswordAuth 'off'\n" > \
	"$TMP/device/etc/config/dropbear"
printf '%s\n' 'dropbear.main.PasswordAuth=off' \
	'dropbear.main.RootPasswordAuth=off' > "$TMP/dropbear.state"
: > "$TMP/runtime.log"
: > "$TMP/wifi.count"
rm -f "$TMP/audit.count"
cp "$TMP/country.initial" "$TMP/country.state"
# A marker copied from another commissioning key must fail before any
# credential or radio mutation.
cp "$TMP/device/etc/cr6608-retail-commissioning-ram" "$TMP/commissioning-marker.valid"
sed 's/^factory_key_sha256=.*/factory_key_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
	"$TMP/commissioning-marker.valid" > "$TMP/commissioning-marker.mismatch"
mv "$TMP/commissioning-marker.mismatch" \
	"$TMP/device/etc/cr6608-retail-commissioning-ram"
chmod 0400 "$TMP/device/etc/cr6608-retail-commissioning-ram"
# shellcheck disable=SC2086
if env $runtime_env sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/provision-commissioning-mismatch.out" 2>&1; then
	fail 'commissioning accepted a marker bound to another authorized key'
fi
grep -Fq 'commissioning_key_binding_invalid' \
	"$TMP/provision-commissioning-mismatch.out" ||
	fail 'commissioning key-binding failure reason is missing'
mv "$TMP/commissioning-marker.valid" \
	"$TMP/device/etc/cr6608-retail-commissioning-ram"
chmod 0400 "$TMP/device/etc/cr6608-retail-commissioning-ram"
# shellcheck disable=SC2086
if ! env $runtime_env sh "$PROVISION" --root-password-file "$TMP/root.secret" \
	--wifi-key-file "$TMP/wifi.secret" --web-password-file "$TMP/web.secret" \
	--market-country SA > "$TMP/provision-commissioning.out" 2>&1; then
	tail -120 "$TMP/provision-commissioning.out" >&2
	fail 'RAM-only commissioning provisioning failed'
fi
grep -qx 'security_provision=PASS sale_ready=NO radio_policy=retail-disabled-after-reboot reboot_required=1 commissioning_finalized=1' \
	"$TMP/provision-commissioning.out" ||
	fail 'commissioning result is not bound to the Retail reboot policy'
[ ! -e "$TMP/device/etc/cr6608-retail-commissioning-ram" ] &&
	[ ! -L "$TMP/device/etc/cr6608-retail-commissioning-ram" ] ||
	fail 'commissioning marker survived successful provisioning'
[ ! -e "$TMP/device/etc/dropbear/authorized_keys" ] &&
	[ ! -L "$TMP/device/etc/dropbear/authorized_keys" ] ||
	fail 'factory authorized key survived successful provisioning'
grep -Fxq 'dropbear.main.PasswordAuth=on' "$TMP/dropbear.state" &&
	grep -Fxq 'dropbear.main.RootPasswordAuth=on' "$TMP/dropbear.state" ||
	fail 'commissioning did not restore unique-password SSH policy'
grep -Fqx 'set dropbear.main.PasswordAuth=on' "$TMP/runtime.log" &&
	grep -Fqx 'set dropbear.main.RootPasswordAuth=on' "$TMP/runtime.log" ||
	fail 'commissioning password-auth transition was not transactional'

# Provisioning must receive secrets through root-only files, require distinct
# non-common values, apply WPA/HTTPS/country state, activate it, and then audit.
grep -Fq -- '--root-password-file' "$PROVISION" || fail 'root secret file interface missing'
grep -Fq -- '--wifi-key-file' "$PROVISION" || fail 'Wi-Fi secret file interface missing'
grep -Fq -- '--web-password-file' "$PROVISION" || fail 'Web secret file interface missing'
grep -Fq -- '--market-country' "$PROVISION" || fail 'market-country interface missing'
grep -Fq -- '--web-password-file' "$AUDIT" || fail 'sale audit lacks Web secret verification input'
grep -Fq -- '--wifi-key-file' "$AUDIT" || fail 'sale audit lacks exact Wi-Fi key verification input'
grep -Fq -- '--root-password-file' "$AUDIT" || fail 'sale audit lacks root secret verification input'
! grep -Eq -- '--(root-password|wifi-key|web-password)([= ]|$)' "$PROVISION" || \
	fail 'provisioner accepts plaintext secret arguments'
grep -Fq 'credentials_must_be_distinct' "$PROVISION" || fail 'credential reuse is not rejected'
grep -Fq 'sale_ready=NO radio_policy=LAB_ARTIFACT_BLOCKED' "$PROVISION" || \
	fail 'credential provisioning can be confused with sale approval'
grep -Fq '[ "$(/usr/bin/id -u 2>/dev/null)" = 0 ] || fail must_run_as_root' \
	"$AUDIT_SOURCE" || fail 'shipped security audit lacks an immutable root gate'
grep -Fq '[ "$(/usr/bin/id -u 2>/dev/null)" = 0 ] || fail must_run_as_root' \
	"$PROVISION_SOURCE" || fail 'shipped provisioner lacks an immutable root gate'
for shipped_security_tool in "$AUDIT_SOURCE" "$PROVISION_SOURCE"; do
	grep -Fq "PATH='/usr/sbin:/usr/bin:/sbin:/bin'" "$shipped_security_tool" || \
		fail 'shipped retail security tool does not pin its command path'
	! grep -Fq 'CR6608_RETAIL_' "$shipped_security_tool" || \
		fail 'shipped retail security tool exposes production test overrides'
done
grep -Fq "AUDIT_BIN='/usr/sbin/cr6608-retail-audit'" "$PROVISION_SOURCE" || \
	fail 'shipped provisioner does not pin the post-provision security audit'
grep -Fq "TLS_PROBE_BIN='/bin/uclient-fetch'" "$AUDIT_SOURCE" || \
	fail 'shipped security audit does not pin the TLS probe'
grep -Fq "IPV4_ONLY_BIN='/usr/sbin/cr6608-ipv4-only'" "$AUDIT_SOURCE" && \
	grep -Fq '$IPV4_ONLY_BIN --json' "$AUDIT_SOURCE" || \
	fail 'shipped security audit does not require the IPv4-only runtime verifier'
! grep -Fq 'https_ipv6_runtime_missing' "$AUDIT_SOURCE" || \
	fail 'sale audit still requires an IPv6 HTTPS listener under IPv4-only policy'
for inspector_ipv6_contract in ipv6_policy_probe_missing ipv6_policy_runtime_failed; do
	grep -Fq "$inspector_ipv6_contract" "$INSPECTOR" ||
		fail "image inspector lacks IPv4-only audit contract: $inspector_ipv6_contract"
done
grep -Fq 'https_ipv4_runtime_missing' "$INSPECTOR" ||
	fail 'image inspector lost the IPv4 HTTPS listener contract'
! grep -Fq 'https_ipv6_runtime_missing' "$INSPECTOR" ||
	fail 'image inspector still requires an IPv6 HTTPS listener under IPv4-only policy'
grep -Fq 'run_without_mutation_fds "$PASSWD_BIN" -a sha512 root' "$PROVISION" || \
	fail 'root password provisioning does not require SHA-512-crypt'
grep -Fq 'stage_wifi_secret_values()' "$PROVISION" && \
	grep -Fq 'run_without_mutation_fds "$UCI_BIN" -q batch' "$PROVISION" && \
	! grep -Fq 'key=$wifi_key' "$PROVISION" || \
	fail 'Wi-Fi plaintext can appear in a UCI process argument'
grep -Fq '"$OPENSSL_BIN" passwd -6 -stdin < "$WEB_PASSWORD_FILE"' "$PROVISION" || \
	fail 'Web password is not hashed from stdin with SHA-512-crypt'
grep -Fq 'retired_shared_web_credential' "$AUDIT" || \
	fail 'sale audit does not reject the shared Web credential'
grep -Fq 'web_password_mismatch' "$AUDIT" || \
	fail 'sale audit does not verify the supplied Web credential'
grep -Fq 'root_password_mismatch' "$AUDIT" || \
	fail 'sale audit does not verify the supplied manufactured root credential'
grep -Fq 'fail provisioning_pending' "$AUDIT" || \
	fail 'normal sale audit does not reject an in-flight provisioning journal'
grep -Fq 'https_tls_handshake_failed' "$AUDIT" || \
	fail 'sale audit does not fail closed on a broken TLS handshake'
grep -Fq 'x509 -in "$cert_file" -noout -checkend 0' "$AUDIT" || \
	fail 'sale audit does not cryptographically validate certificate lifetime'
grep -Fq 'pkey -in "$key_file" -check -noout' "$AUDIT" || \
	fail 'sale audit does not cryptographically validate the private key'
grep -Fq 'https_cert_key_mismatch' "$AUDIT" || \
	fail 'sale audit does not reject a certificate/private-key mismatch'
grep -Fq 'find_primary_ap()' "$PROVISION" || fail 'primary AP discovery is not dynamic'
grep -Fq 'wireless.${section}.device' "$PROVISION" || \
	fail 'primary AP discovery is not bound to the radio device'
grep -Fq 'find_primary_ap radio0 wifinet0' "$PROVISION" && \
	grep -Fq 'find_primary_ap radio1 wifinet1' "$PROVISION" || \
	fail 'provisioner does not prefer validated canonical primary APs'
grep -Fq 'primary_ap_fallback_eligible' "$PROVISION" && \
	grep -Fq 'primary_ap_ambiguous' "$PROVISION" || \
	fail 'provisioner does not reject ambiguous preserved AP candidates'
grep -Fq 'wireless.${section}.encryption=sae-mixed' "$PROVISION" || \
	fail 'provisioner does not force protected AP mode'
grep -Fq 'hostapd_options' "$PROVISION" && grep -Fq 'hostapd_bss_options' "$PROVISION" || \
	fail 'provisioner does not clear opaque hostapd override channels'
grep -Fq 'raw_hostapd_options' "$AUDIT" && \
	grep -Fq 'raw_hostapd_bss_options' "$AUDIT" && \
	grep -Fq 'runtime_primary_ifname()' "$AUDIT" || \
	fail 'audit permits raw hostapd overrides or unbound primary runtime'
grep -Fq 'wait_post_provision_audit()' "$PROVISION" && \
	grep -Fq 'AUDIT_READY_MAX_ATTEMPTS=16' "$PROVISION_SOURCE" && \
	grep -Fq 'post_provision_runtime_timeout' "$PROVISION" || \
	fail 'provisioner lacks bounded asynchronous Wi-Fi readiness handling'
for country_key in \
	wireless.radio0.country wireless.radio1.country \
	smartap.quick.country24 smartap.quick.country5 \
	cr6608quick.default.country cr6608quick.default.country24 \
	cr6608quick.default.country5; do
	grep -Fq "$country_key" "$PROVISION" || \
		fail "provisioner omits the authoritative country mirror: $country_key"
done
grep -Fq '"$UCI_BIN" commit smartap' "$PROVISION" || \
	fail 'provisioner does not commit the Smart AP country mirror'
grep -Fq 'uhttpd.main.redirect_https=1' "$PROVISION" || \
	fail 'provisioner does not enable HTTPS redirect'
grep -Fq "system.@system[0].ttylogin=1" "$PROVISION" || \
	fail 'provisioner does not restore password-gated serial login'
grep -Fq "trap 'signal_exit 129' HUP" "$PROVISION" || \
	fail 'provisioner HUP trap does not exit'
grep -Fq "trap 'signal_exit 130' INT" "$PROVISION" || \
	fail 'provisioner INT trap does not exit'
grep -Fq "trap 'signal_exit 143' TERM" "$PROVISION" || \
	fail 'provisioner TERM trap does not exit'
grep -Fq 'cp -pf "$backup/shadow" "$SHADOW_PATH" || restore_rc=1' "$PROVISION" || \
	fail 'rollback does not verify restored configuration copies'
grep -Fq 'cp -pf "$backup/rpcd" "$RPCD_CONFIG" || restore_rc=1' "$PROVISION" || \
	fail 'rollback does not restore the previous rpcd configuration'
grep -Fq 'cp -pf "$backup/smartap" "$SMARTAP_CONFIG" || restore_rc=1' "$PROVISION" || \
	fail 'rollback does not restore the previous Smart AP country mirrors'
grep -Fq 'cp -pf "$backup/prplmesh" "$PRPLMESH_CONFIG" || restore_rc=1' "$PROVISION" || \
	fail 'rollback does not restore the previous prplmesh credential mirrors'
grep -Fq '"$UCI_BIN" commit system && "$UCI_BIN" commit prplmesh' "$PROVISION" || \
	fail 'provisioner does not commit prplmesh in the credential transaction'
grep -Fq 'restore_runtime || rollback_rc=1' "$PROVISION" || \
	fail 'rollback does not verify restoration of the previous runtime'
grep -Fq 'restore_previous_markers || {' "$PROVISION" && \
	grep -Fq 'force_pending_state' "$PROVISION" && \
	grep -Fq 'publish_marker "$PENDING_MARKER" NO || fail_closed_rc=1' "$PROVISION" && \
	grep -Fq 'rollback_transaction 1 >/dev/null 2>&1 || true' "$PROVISION" || \
	fail 'rollback/signal failure can expose an old complete marker'
grep -Fq 'run_without_mutation_fds "$RPCD_INIT" restart >/dev/null 2>&1 || runtime_rc=1' "$PROVISION" || \
	fail 'rollback does not restore the previous rpcd runtime'
grep -Fq 'run_without_mutation_fds "$WIFI_BIN" reload >/dev/null 2>&1 || runtime_rc=1' "$PROVISION" || \
	fail 'rollback does not reapply the previous Wi-Fi runtime'
audit_line="$(grep -n '^wait_post_provision_audit$' "$PROVISION" | cut -d: -f1)"
rpcd_line="$(grep -n '^run_without_mutation_fds "\$RPCD_INIT" restart' "$PROVISION" | cut -d: -f1)"
restart_line="$(grep -n '^run_without_mutation_fds "\$UHTTPD_INIT" restart' "$PROVISION" | cut -d: -f1)"
wifi_line="$(grep -n '^run_without_mutation_fds "\$WIFI_BIN" reload' "$PROVISION" | cut -d: -f1)"
pending_line="$(grep -n '^publish_marker "\$PENDING_MARKER" NO' "$PROVISION" | cut -d: -f1)"
marker_line="$(grep -n '^publish_marker "\$MARKER" YES' "$PROVISION" | cut -d: -f1)"
passwd_line="$(grep -n 'run_without_mutation_fds "\$PASSWD_BIN" -a sha512 root' "$PROVISION" | cut -d: -f1)"
apply_lock_line="$(grep -n '^acquire_apply_lock || fail provisioning_busy$' "$PROVISION" | cut -d: -f1)"
mutation_lock_line="$(grep -n '^cr6608_dashboard_cache_mutation_begin' "$PROVISION" | cut -d: -f1)"
[ -n "$audit_line" ] && [ -n "$rpcd_line" ] && [ -n "$restart_line" ] && \
	[ -n "$wifi_line" ] && [ -n "$pending_line" ] && [ -n "$marker_line" ] && \
	[ -n "$passwd_line" ] && [ -n "$apply_lock_line" ] && [ -n "$mutation_lock_line" ] && \
	[ "$apply_lock_line" -lt "$mutation_lock_line" ] && \
	[ "$mutation_lock_line" -lt "$pending_line" ] && [ "$pending_line" -lt "$passwd_line" ] && \
	[ "$pending_line" -lt "$rpcd_line" ] && \
	[ "$rpcd_line" -lt "$restart_line" ] && [ "$restart_line" -lt "$wifi_line" ] && \
	[ "$wifi_line" -lt "$audit_line" ] && [ "$audit_line" -lt "$marker_line" ] || \
	fail 'pending/audit/complete marker order is not power-loss safe'
grep -Fq 'create_apply_claim()' "$PROVISION" && \
	grep -Fq 'ownerless_lock_reclaimable()' "$PROVISION" && \
	grep -Fq '.cr6608-apply.claim.' "$PROVISION" && \
	grep -Fq 'owner_identity_live "$APPLY_LOCK/owner"' "$PROVISION" || \
	fail 'apply-lock creation window is not crash-recoverable'

grep -Fxq '/etc/cr6608-retail-provisioned' "$KEEP" || \
	fail 'settings-preserving sysupgrade loses the provisioning marker'
grep -Fxq '/etc/cr6608-retail-provisioning-pending' "$KEEP" || \
	fail 'settings-preserving sysupgrade loses the fail-closed pending journal'
grep -Fq 'settings-preserving sysupgrade keeps' "$DOC" || \
	fail 'upgrade credential preservation is undocumented'
if ! grep -Fq 'must' "$DOC" || ! grep -Fq 'enforce fleet-wide uniqueness' "$DOC"; then
	fail 'external fleet uniqueness requirement is undocumented'
fi

printf 'retail_security_contract=pass\n'
