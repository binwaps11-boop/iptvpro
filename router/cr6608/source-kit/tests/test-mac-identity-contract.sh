#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERIFY="$ROOT/files/usr/sbin/cr6608-mac-verify"
LIB="$ROOT/files/usr/libexec/cr6608-mac-identity-lib"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-mac-identity.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() { printf 'mac identity contract failed: %s\n' "$*" >&2; exit 1; }

mkdir -p "$TMP/sys/class/net" "$TMP/tmp/sysinfo" "$TMP/bin"
printf '%s\n' 'xiaomi,mi-router-cr6608' > "$TMP/tmp/sysinfo/board_name"
printf '%s\n' 'mtd3: 00080000 00020000 "Factory"' > "$TMP/proc-mtd"
for interface in eth0 br-lan lan1 lan2 lan3 wan phy0-ap0 phy1-ap0; do
	mkdir -p "$TMP/sys/class/net/$interface"
done
printf '%s\n' 'd4:35:38:d4:f3:c8' > "$TMP/sys/class/net/eth0/address"
for interface in br-lan lan1 lan2 lan3; do
	cp "$TMP/sys/class/net/eth0/address" "$TMP/sys/class/net/$interface/address"
done
printf '%s\n' 'd4:35:38:4a:09:2d' > "$TMP/sys/class/net/wan/address"
printf '%s\n' 'd4:35:38:d4:f3:ca' > "$TMP/sys/class/net/phy0-ap0/address"
printf '%s\n' 'd4:35:38:d4:f3:c9' > "$TMP/sys/class/net/phy1-ap0/address"

cat > "$TMP/system.sh" <<'EOF'
[ "${IPKG_INSTROOT+x}" = x ] || {
	printf '%s\n' 'IPKG_INSTROOT was not initialized before system library load' >&2
	return 97
}
mtd_get_mac_binary() {
	[ "$1" = Factory ] || return 1
	case "$2" in
		4) printf '%s\n' "${TEST_WIFI24:?}" ;;
		10) printf '%s\n' "${TEST_WIFI5:?}" ;;
		262132) printf '%s\n' "${TEST_LAN:?}" ;;
		262138) printf '%s\n' "${TEST_WAN:?}" ;;
		*) return 1 ;;
	esac
}
EOF
cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
[ "${TEST_UCI_FAIL:-0}" = 1 ] && exit 1
[ "$#" -eq 3 ] || exit 64
[ "$1" = -q ] && [ "$2" = show ] || exit 64
case "$3" in
	network)
		[ "${TEST_UCI_NETWORK_OVERRIDE:-0}" = 1 ] &&
			printf "%s\n" "network.lan.macaddr='02:00:11:22:33:44'"
		;;
	wireless)
		[ "${TEST_UCI_WIRELESS_OVERRIDE:-0}" = 1 ] &&
			printf "%s\n" "wireless.default_radio0.macaddr='02:00:11:22:33:45'"
		;;
	*) exit 1 ;;
esac
exit 0
EOF
chmod 0755 "$TMP/bin/uci"

export CR6608_MAC_IDENTITY_LIB="$LIB"
export CR6608_MAC_BOARD_FILE="$TMP/tmp/sysinfo/board_name"
export CR6608_MAC_PROC_MTD="$TMP/proc-mtd"
export CR6608_MAC_SYSTEM_LIB="$TMP/system.sh"
export CR6608_MAC_SYS_NET="$TMP/sys/class/net"
export CR6608_MAC_UCI_BIN="$TMP/bin/uci"
export TEST_LAN='d4:35:38:d4:f3:c8'
export TEST_WAN='d4:35:38:4a:09:2d'
export TEST_WIFI24='d4:35:38:d4:f3:ca'
export TEST_WIFI5='d4:35:38:d4:f3:c9'
export TEST_UCI_FAIL=0
export TEST_UCI_NETWORK_OVERRIDE=0
export TEST_UCI_WIRELESS_OVERRIDE=0
unset IPKG_INSTROOT

expect_pass() {
	out="$(sh "$VERIFY" --json)" || fail "$1 unexpectedly failed"
	printf '%s\n' "$out" | grep -Fq '"ok":true' || fail "$1 did not emit PASS JSON"
	printf '%s\n' "$out" | grep -Fq '"shared_by_design":true' || fail "$1 lost the DSA sharing policy"
}
expect_fail() {
	expected="$2"
	if out="$(sh "$VERIFY" --json 2>/dev/null)"; then fail "$1 unexpectedly passed"; fi
	printf '%s\n' "$out" | grep -Fq "\"reason\":\"$expected\"" || fail "$1 returned the wrong reason: $out"
}

expect_pass valid-factory-and-dsa

if "$TMP/bin/uci" -q show network wireless >/dev/null 2>&1; then
	fail 'fake UCI accepted the invalid multi-package syntax'
fi
TEST_UCI_WIRELESS_OVERRIDE=1; export TEST_UCI_WIRELESS_OVERRIDE
expect_fail wireless-uci-override uci_mac_override_present
TEST_UCI_WIRELESS_OVERRIDE=0; export TEST_UCI_WIRELESS_OVERRIDE
TEST_UCI_NETWORK_OVERRIDE=1; export TEST_UCI_NETWORK_OVERRIDE
expect_fail network-uci-override uci_mac_override_present
TEST_UCI_NETWORK_OVERRIDE=0; export TEST_UCI_NETWORK_OVERRIDE
TEST_UCI_FAIL=1; export TEST_UCI_FAIL
expect_fail unreadable-uci-fails-closed uci_mac_override_present
TEST_UCI_FAIL=0; export TEST_UCI_FAIL

TEST_WAN="$TEST_LAN"; export TEST_WAN
expect_fail duplicate-role factory_identity_invalid
TEST_WAN='d4:35:38:4a:09:2d'; export TEST_WAN

TEST_WIFI24='01:35:38:d4:f3:ca'; export TEST_WIFI24
expect_fail multicast-role factory_identity_invalid
TEST_WIFI24='d4:35:38:d4:f3:ca'; export TEST_WIFI24

printf '%s\n' '02:00:11:22:33:44' > "$TMP/sys/class/net/wan/address"
expect_fail runtime-mismatch wan_runtime_mismatch
printf '%s\n' "$TEST_WAN" > "$TMP/sys/class/net/wan/address"

rm -f "$TMP/sys/class/net/lan3/address"
expect_fail missing-dsa-port dsa_runtime_mismatch
printf '%s\n' "$TEST_LAN" > "$TMP/sys/class/net/lan3/address"

printf '%s\n' 'not,the,cr6608' > "$TMP/tmp/sysinfo/board_name"
expect_fail wrong-board unsupported_board
printf '%s\n' 'xiaomi,mi-router-cr6608' > "$TMP/tmp/sysinfo/board_name"

expect_pass restored-valid-state
! grep -Eq 'd4:35:38:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}' "$VERIFY" "$LIB" ||
	fail 'a unit MAC was baked into the product verifier'

printf '%s\n' 'mac_identity_contract=pass'
