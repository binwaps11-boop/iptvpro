#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LIB="$ROOT/files/usr/libexec/cr6608-network-safety"
BUILD="$ROOT/build.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-network-safety.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() {
	printf 'network_safety_runtime_tests=fail: %s\n' "$*" >&2
	exit 1
}

[ -s "$LIB" ] || fail "missing network-safety library"
[ -s "$BUILD" ] || fail "missing build script"
grep -Fq 'record_regular_input source-test "${NETWORK_SAFETY_TEST}"' "$BUILD" ||
	fail "network-safety test is absent from the reproducible input manifest"
CR6608_SYS_CLASS_NET="$TMP/sys/class/net"
export CR6608_SYS_CLASS_NET
mkdir -p "$CR6608_SYS_CLASS_NET"

FAKE_UCI="$TMP/uci"
cat >"$FAKE_UCI" <<'EOF'
#!/bin/sh
[ "${FAKE_UCI_FAIL:-0}" = 0 ] || exit 1
case "$*" in
	'-q show network')
		printf '%s\n' 'network.guest=interface' 'network.vpn=interface'
		;;
	'-q get network.guest.device') printf '%s\n' br-guest ;;
	'-q get network.vpn.device') printf '%s\n' wg1 ;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$FAKE_UCI"
CR6608_UCI_BIN="$FAKE_UCI"
export CR6608_UCI_BIN

# shellcheck source=/dev/null
. "$LIB"

for device in br-lan br-lan.50 lan1 lan2 lan3 wan eth0 lo phy0-ap0 phy1-sta0; do
	mkdir -p "$CR6608_SYS_CLASS_NET/$device"
	if cr6608_safe_l3_device "$device"; then
		fail "core/DSA device accepted: $device"
	fi
done

for device in br-guest wg0 tun0 tap0 gre0 gretap0 sit0 dummy0; do
	mkdir -p "$CR6608_SYS_CLASS_NET/$device"
	cr6608_safe_l3_device "$device" || fail "documented virtual device rejected: $device"
done

mkdir -p "$CR6608_SYS_CLASS_NET/veth0"
if cr6608_safe_l3_device veth0; then
	fail "undocumented virtual family accepted"
fi
if cr6608_safe_l3_device absent0; then
	fail "absent device accepted"
fi

mkdir -p "$TMP/master" "$TMP/physical" \
	"$CR6608_SYS_CLASS_NET/br-enslaved" "$CR6608_SYS_CLASS_NET/wg9"
ln -s "$TMP/master" "$CR6608_SYS_CLASS_NET/br-enslaved/master"
if cr6608_safe_l3_device br-enslaved; then
	fail "enslaved virtual bridge accepted"
fi
ln -s "$TMP/physical" "$CR6608_SYS_CLASS_NET/wg9/device"
if cr6608_safe_l3_device wg9; then
	fail "physical-backed device accepted"
fi

cr6608_l3_device_available br-guest guest || fail "existing owner cannot retain its device"
if cr6608_l3_device_available br-guest custom; then
	fail "duplicate L3 owner accepted"
fi
cr6608_l3_device_available wg0 custom || fail "unassigned safe device rejected"
FAKE_UCI_FAIL=1
export FAKE_UCI_FAIL
if cr6608_l3_device_available wg0 custom; then
	fail "device accepted when UCI ownership could not be verified"
fi

# Bridge membership is an atomic request.  The production handler uses this
# validator before backup or UCI writes; exercise that sequencing with a fake
# writer and prove invalid-only and mixed lists produce no mutation at all.
MUTATION_LOG="$TMP/bridge-uci-mutations.log"
: >"$MUTATION_LOG"
uci() {
	case "$1" in set|delete|commit|add_list|del_list) printf '%s\n' "$*" >>"$MUTATION_LOG" ;; esac
}
mock_bridge_apply() {
	ports="$(cr6608_normalize_bridge_ports "$1")" || return 1
	uci set network.bridge.stp=1
	uci delete network.bridge.ports
	for bridge_port in $ports; do uci add_list "network.bridge.ports=$bridge_port"; done
	uci commit network
}
if mock_bridge_apply 'wan'; then
	fail "invalid-only bridge list was accepted"
fi
[ ! -s "$MUTATION_LOG" ] || fail "invalid-only bridge list caused a UCI mutation"
if mock_bridge_apply 'lan1 wan lan2'; then
	fail "mixed valid/invalid bridge list was accepted"
fi
[ ! -s "$MUTATION_LOG" ] || fail "mixed bridge list caused a UCI mutation"
normalized="$(cr6608_normalize_bridge_ports 'lan3 lan1 lan3 lan2')" ||
	fail "valid bridge list was rejected"
[ "$normalized" = 'lan3 lan1 lan2' ] || fail "valid bridge list was not deduplicated in order"
mock_bridge_apply 'lan1 lan1 lan2' || fail "valid bridge list did not reach the writer"
[ -s "$MUTATION_LOG" ] || fail "valid bridge control did not exercise the fake UCI writer"

printf 'network_safety_runtime_tests=pass\n'
