#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
VERIFIER="${ROOT}/files/usr/sbin/cr6608-easymesh-verify"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-easymesh-verify.XXXXXX")" || exit 1
MOCK_BIN="${TEST_ROOT}/bin"
SLEEP_CALLED="${TEST_ROOT}/sleep-called"
FUNCTIONS="${TEST_ROOT}/verifier-functions"

cleanup() {
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
	printf '%s\n' "$*" >&2
	exit 1
}

assert_equal() {
	local expected="$1" actual="$2" description="$3"

	[ "$actual" = "$expected" ] ||
		fail "$description: expected [$expected], got [$actual]"
}

# Source the verifier's real role/policy/observability functions without
# running its production entry point.  Paths and probes are replaced below;
# the installed verifier itself has no environment-controlled bypass.
awk '
	/^printf '\''CR6608 prplMesh EasyMesh verification/ { exit }
	{ print }
' "$VERIFIER" > "$FUNCTIONS"
# shellcheck disable=SC1090
. "$FUNCTIONS"

runtime_root="${TEST_ROOT}/runtime"
mkdir -p "$runtime_root/logs"
sys_class_net="${TEST_ROOT}/sys/class/net"
mkdir -p "$sys_class_net/br-lan" "$sys_class_net/lan1" "$sys_class_net/wan"
ln -s ../br-lan "$sys_class_net/lan1/master"
printf '1\n' > "$sys_class_net/lan1/carrier"
printf '0\n' > "$sys_class_net/wan/carrier"

MOCK_PROCESSES=''
MOCK_SOCKETS=''

process_pids() {
	case " $MOCK_PROCESSES " in
		*" $1 "*) printf '%s\n' "pid-$1" ;;
		*) printf '\n' ;;
	esac
}

socket_present() {
	case " $MOCK_SOCKETS " in
		*" $1 "*) return 0 ;;
		*) return 1 ;;
	esac
}

uci() {
	case "${3-}" in
		prplmesh.radio0.hostap_iface) printf 'phy0-ap0\n' ;;
		prplmesh.radio1.hostap_iface) printf 'phy1-ap0\n' ;;
		network)
			[ "${2-}" = show ] || return 1
			printf '%s\n' "network.bridge=device" "network.bridge.name='br-lan'"
			;;
		network.bridge) printf 'device\n' ;;
		network.bridge.ports) printf 'lan1 lan2 lan3\n' ;;
		*) return 1 ;;
	esac
}

prepare_agent_logs() {
	local requested_mode="$1" m2_count="${2:-2}" iface count

	rm -f "$runtime_root/logs"/*.log
	for iface in phy0-ap0 phy1-ap0; do
		printf '%s\n' 'send ACTION_APMANAGER_JOINED_NOTIFICATION' > \
			"$runtime_root/logs/beerocks_ap_manager_${iface}.log"
		if [ "$requested_mode" = passive ]; then
			printf '%s\n' \
				'Autoconfiguration: passive OpenWrt mode keeps netifd hostapd data intact' >> \
				"$runtime_root/logs/beerocks_ap_manager_${iface}.log"
		fi
	done
	: > "$runtime_root/logs/beerocks_agent.log"
	count=0
	while [ "$count" -lt "$m2_count" ]; do
		printf '%s\n' 'Finished M2 parsing with test data and 0 errors.' >> \
			"$runtime_root/logs/beerocks_agent.log"
		count=$((count + 1))
	done
}

assert_observable() {
	local description="$1"

	control_plane_observable || fail "$description: expected observable control plane"
}

assert_not_observable() {
	local description="$1"

	if control_plane_observable; then
		fail "$description: unexpectedly reported observable control plane"
	fi
}

# Git for Windows may materialize a directory-link request as an ordinary
# directory copy. Test the real symlink contract whenever the platform
# actually created one; Linux/OpenWrt always exercises this branch.
if [ -L "$sys_class_net/lan1/master" ]; then
	backhaul_topology_valid lan1 || fail 'valid br-lan DSA backhaul rejected'
	if backhaul_topology_valid wan; then fail 'WAN accepted as EasyMesh backhaul'; fi
fi
backhaul_carrier_up lan1 || fail 'live backhaul carrier rejected'
if backhaul_carrier_up wan; then fail 'down WAN carrier accepted'; fi
agent_runtime_policy_valid 1 1 || fail 'audited Agent safety policy rejected'
for invalid_agent_policy in '0 1' '1 0' '0 0' 'missing 1' '1 missing'; do
	set -- $invalid_agent_policy
	if agent_runtime_policy_valid "$1" "$2"; then
		fail "unsafe Agent policy accepted: wired=$1 encrypted=$2"
	fi
done
radio_credentials_valid wpa2-psk 'Secure Mesh' '0123456789ab' 1 ||
	fail 'valid encrypted credentials rejected'
if radio_credentials_valid none 'Open Mesh' '' 1; then
	fail 'open fronthaul accepted while encryption is required'
fi
if radio_credentials_valid wpa2-psk 'Secure Mesh' short 1; then
	fail 'short WPA2 key accepted'
fi

# Policy is fail-closed: only the three supported roles and explicit 0/1
# passive states are valid.  Active operation needs its second confirmation.
for mode_under_test in Multi-AP-Controller Multi-AP-Agent Multi-AP-Controller-and-Agent; do
	runtime_policy_error "$mode_under_test" 1 0 >/dev/null ||
		fail "$mode_under_test passive policy rejected"
	runtime_policy_error "$mode_under_test" 0 1 >/dev/null ||
		fail "$mode_under_test confirmed-active policy rejected"
done
if policy_output="$(runtime_policy_error Multi-AP-Agent 0 0)"; then
	fail 'unconfirmed active policy accepted'
fi
assert_equal ACTIVE_CONTROL_NOT_CONFIRMED "$policy_output" \
	'unconfirmed active policy reason'
if policy_output="$(runtime_policy_error Multi-AP-Agent missing 1)"; then
	fail 'missing passive policy accepted'
fi
assert_equal INVALID_PASSIVE_MODE "$policy_output" 'invalid passive policy reason'
if policy_output="$(runtime_policy_error Non-Prpl-Controller-and-Agent 1 0)"; then
	fail 'unsupported management role accepted'
fi
assert_equal INVALID_MANAGEMENT_MODE "$policy_output" 'invalid role policy reason'

assert_equal 'uds_broker
uds_controller' "$(required_socket_names Multi-AP-Controller)" \
	'controller socket set'
assert_equal 'uds_broker
uds_agent
uds_backhaul
uds_platform' "$(required_socket_names Multi-AP-Agent)" 'agent socket set'
assert_equal 'uds_broker
uds_controller
uds_agent
uds_backhaul
uds_platform' "$(required_socket_names Multi-AP-Controller-and-Agent)" \
	'combined-role socket set'

# Controller-only: no Agent processes, AP-manager logs, or Agent sockets are
# required.  Active/passive policy does not change the controller role proof.
mode=Multi-AP-Controller
MOCK_PROCESSES='ieee1905_transport beerocks_controller'
MOCK_SOCKETS='uds_broker uds_controller'
passive=1
assert_observable 'passive controller'
passive=0
assert_observable 'active controller'
MOCK_SOCKETS='uds_broker'
assert_not_observable 'controller missing controller socket'
MOCK_SOCKETS='uds_broker uds_controller'
MOCK_PROCESSES='ieee1905_transport'
assert_not_observable 'controller missing controller process'

# Agent-only: the controller process and uds_controller are deliberately
# absent.  Its own processes, sockets, AP join events and two M2 parses remain
# mandatory.
mode=Multi-AP-Agent
MOCK_PROCESSES='ieee1905_transport beerocks_agent beerocks_fronthaul'
MOCK_SOCKETS='uds_broker uds_agent uds_backhaul uds_platform'
passive=1
prepare_agent_logs passive 2
assert_observable 'passive agent without local controller'
prepare_agent_logs active 2
assert_not_observable 'passive agent missing passive marker'
passive=0
assert_observable 'active agent without passive marker'
prepare_agent_logs passive 2
assert_not_observable 'active agent with contradictory passive marker'
prepare_agent_logs active 1
assert_not_observable 'active agent with incomplete M2 evidence'
prepare_agent_logs active 2
MOCK_SOCKETS='uds_broker uds_agent uds_platform'
assert_not_observable 'agent missing backhaul socket'

# The combined role requires the union of controller and Agent evidence in
# both operation modes.
mode=Multi-AP-Controller-and-Agent
MOCK_PROCESSES='ieee1905_transport beerocks_controller beerocks_agent beerocks_fronthaul'
MOCK_SOCKETS='uds_broker uds_controller uds_agent uds_backhaul uds_platform'
passive=1
prepare_agent_logs passive 2
assert_observable 'passive combined role'
passive=0
prepare_agent_logs active 2
assert_observable 'active combined role'
MOCK_PROCESSES='ieee1905_transport beerocks_agent beerocks_fronthaul'
assert_not_observable 'combined role missing controller process'

mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/uci" <<'EOF'
#!/bin/sh
key="${3-}"
case "$key" in
	prplmesh.config.enable) printf '0\n' ;;
	prplmesh.config.operational) printf '0\n' ;;
	prplmesh.config.management_mode) printf 'Multi-AP-Controller-and-Agent\n' ;;
	prplmesh.config.passive_mode) printf '1\n' ;;
	prplmesh.config.active_control_confirmed) printf '0\n' ;;
	*) exit 1 ;;
esac
EOF
cat > "$MOCK_BIN/sleep" <<'EOF'
#!/bin/sh
: > "$CR6608_TEST_SLEEP_CALLED"
exit 99
EOF
chmod 755 "$MOCK_BIN/uci" "$MOCK_BIN/sleep"

# Execute the real entry-point prefix too: a disabled policy must return before
# any settle/stability sleep, independent of role-specific readiness checks.
prefix="${TEST_ROOT}/verifier-prefix"
awk '
	{ print }
	seen && /^[[:space:]]*fi$/ { exit }
	/RESULT_EASYMESH_CONTROL_PLANE=DISABLED_BY_POLICY/ { seen = 1 }
' "$VERIFIER" | sed "s|if \[ ! -f /etc/config/prplmesh \]; then|if false; then|" > "$prefix"
chmod 755 "$prefix"

set +e
output="$(PATH="$MOCK_BIN:$PATH" CR6608_TEST_SLEEP_CALLED="$SLEEP_CALLED" sh "$prefix" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "disabled verifier returned $rc: $output"
printf '%s\n' "$output" | grep -qx \
	'RESULT_EASYMESH_PHYSICAL_INTEROPERABILITY=NOT_PROVEN_EXTERNAL_CONTROLLER_AGENT_AND_RF_TEST_REQUIRED' ||
	fail 'disabled verifier omitted the physical-interoperability limitation'
printf '%s\n' "$output" | grep -qx \
	'RESULT_EASYMESH_SOFTWARE_CONTRACT=DISABLED_BY_POLICY' ||
	fail 'disabled verifier software-contract result missing'
printf '%s\n' "$output" | grep -qx \
	'RESULT_EASYMESH_CONTROL_PLANE=DISABLED_BY_POLICY' ||
	fail 'disabled verifier result missing'
[ ! -e "$SLEEP_CALLED" ] || fail 'disabled verifier called sleep'

# A stale Agent policy must also fail immediately. It must never be confused
# with a slow controller/agent discovery failure.
cat > "$MOCK_BIN/uci" <<'EOF'
#!/bin/sh
key="${3-}"
case "$key" in
	prplmesh.config.enable|prplmesh.config.operational) printf '1\n' ;;
	prplmesh.config.management_mode) printf 'Multi-AP-Agent\n' ;;
	prplmesh.config.passive_mode) printf '1\n' ;;
	prplmesh.config.active_control_confirmed) printf '0\n' ;;
	prplmesh.config.wired_backhaul) printf '1\n' ;;
	prplmesh.config.require_encrypted_fronthaul) printf '0\n' ;;
	*) exit 1 ;;
esac
EOF
rm -f "$SLEEP_CALLED"
policy_prefix="${TEST_ROOT}/verifier-agent-policy-prefix"
awk '
	{ print }
	seen && /^[[:space:]]*fi$/ { exit }
	/RESULT_EASYMESH_CONTROL_PLANE=INVALID_AGENT_SAFETY_POLICY/ { seen = 1 }
' "$VERIFIER" | sed "s|if \[ ! -f /etc/config/prplmesh \]; then|if false; then|" > "$policy_prefix"
chmod 755 "$policy_prefix"
set +e
output="$(PATH="$MOCK_BIN:$PATH" CR6608_TEST_SLEEP_CALLED="$SLEEP_CALLED" sh "$policy_prefix" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "unsafe Agent policy verifier returned $rc: $output"
printf '%s\n' "$output" | grep -qx \
	'RESULT_EASYMESH_SOFTWARE_CONTRACT=INVALID_AGENT_SAFETY_POLICY' ||
	fail 'unsafe Agent policy software-contract result missing'
printf '%s\n' "$output" | grep -qx \
	'RESULT_EASYMESH_CONTROL_PLANE=INVALID_AGENT_SAFETY_POLICY' ||
	fail 'unsafe Agent policy control-plane result missing'
[ ! -e "$SLEEP_CALLED" ] || fail 'unsafe Agent policy verifier entered the settle loop'

# The service must launch exactly the processes owned by the selected role.
# In particular, Controller-only used to start beerocks_agent even though its
# verifier correctly expected no Agent process.
(
	INIT="${ROOT}/packages/prplmesh/files/etc/init.d/prplmesh"
	. "$INIT"
	test_mode=Multi-AP-Controller-and-Agent
	started=""
	config_load() { :; }
	config_get_bool() {
		case "$3" in
			enable|operational|passive_mode) value=1 ;;
			active_control_confirmed) value=0 ;;
			*) value="${4-0}" ;;
		esac
		eval "$1=\$value"
	}
	config_get() {
		case "$3" in
			management_mode) value="$test_mode" ;;
			operating_mode) value=Gateway ;;
			*) value="${4-}" ;;
		esac
		eval "$1=\$value"
	}
	prepare_runtime_dirs() { :; }
	prepare_platform_db() { :; }
	ebtables() { :; }
	logger() { :; }
	start_prplmesh_instance() { started="${started}${started:+ }$1"; }
	assert_role() {
		test_mode="$1"; expected="$2"; started=""
		start_service || exit 31
		[ "$started" = "$expected" ] || exit 32
	}
	assert_role Multi-AP-Controller 'ieee1905_transport beerocks_controller'
	assert_role Multi-AP-Agent 'ieee1905_transport beerocks_agent'
	assert_role Multi-AP-Controller-and-Agent \
		'ieee1905_transport beerocks_controller beerocks_agent'
) || fail 'prplMesh service process set does not match its management role'

printf 'easymesh_verifier_runtime=pass\n'
