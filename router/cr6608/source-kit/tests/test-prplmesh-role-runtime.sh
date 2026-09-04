#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INIT="$ROOT/packages/prplmesh/files/etc/init.d/prplmesh"

fail() {
	printf 'prplmesh_role_runtime=fail: %s\n' "$*" >&2
	exit 1
}

# rc.common only dispatches functions when the file is executed.  Sourcing it
# here gives this test the exact production role-selection functions.
. "$INIT"

test_mode=Multi-AP-Controller-and-Agent
test_enable=1
test_operational=1
test_passive=1
test_active_confirmed=0
test_wired_backhaul=1
test_require_encrypted=1
started=""
prepare_calls=0
config_load() { :; }
config_get_bool() {
	case "$3" in
		enable) value="$test_enable" ;;
		operational) value="$test_operational" ;;
		passive_mode) value="$test_passive" ;;
		active_control_confirmed) value="$test_active_confirmed" ;;
		wired_backhaul) value="$test_wired_backhaul" ;;
		require_encrypted_fronthaul) value="$test_require_encrypted" ;;
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
prepare_runtime_dirs() { prepare_calls=$((prepare_calls + 1)); }
prepare_platform_db() { :; }
ebtables() { :; }
logger() { :; }
start_prplmesh_instance() { started="${started}${started:+ }$1"; }

assert_mode() {
	test_mode="$1"; expected="$2"; started=""; prepare_calls=0
	test_enable=1; test_operational=1; test_passive=1; test_active_confirmed=0
	test_wired_backhaul=1; test_require_encrypted=1
	start_service || fail "$test_mode failed to start"
	[ "$started" = "$expected" ] ||
		fail "$test_mode started [$started], expected [$expected]"
	[ "$prepare_calls" -eq 1 ] || fail "$test_mode did not prepare runtime exactly once"
}

assert_mode Multi-AP-Controller 'ieee1905_transport beerocks_controller'
assert_mode Multi-AP-Agent 'ieee1905_transport beerocks_agent'
assert_mode Multi-AP-Controller-and-Agent \
	'ieee1905_transport beerocks_controller beerocks_agent'

if mode_has_controller Multi-AP-Agent; then fail 'Agent role owns Controller'; fi
if mode_has_agent Multi-AP-Controller; then fail 'Controller role owns Agent'; fi

agent_runtime_policy_valid 1 1 || fail 'audited Agent policy rejected'
if agent_runtime_policy_valid 1 0; then fail 'open Agent fronthaul policy accepted'; fi
if agent_runtime_policy_valid 0 1; then fail 'non-wired Agent backhaul policy accepted'; fi
grep -Fq 'agent_runtime_policy_valid "$wired_backhaul" "$require_encrypted"' "$INIT" ||
	fail 'Agent policy helper is not enforced before platform DB creation'

started=""; prepare_calls=0; test_enable=0; test_operational=1
start_service || fail 'disabled primary gate returned failure'
[ -z "$started" ] && [ "$prepare_calls" -eq 0 ] ||
	fail 'disabled primary gate reached runtime startup'

started=""; prepare_calls=0; test_enable=1; test_operational=0
start_service || fail 'closed operational gate returned failure'
[ -z "$started" ] && [ "$prepare_calls" -eq 0 ] ||
	fail 'closed operational gate reached runtime startup'

started=""; prepare_calls=0; test_enable=1; test_operational=1
test_passive=0; test_active_confirmed=0
if start_service; then fail 'unconfirmed active control was accepted'; fi
[ -z "$started" ] && [ "$prepare_calls" -eq 0 ] ||
	fail 'unconfirmed active control reached runtime startup'

started=""; prepare_calls=0; test_passive=0; test_active_confirmed=1
test_mode=Multi-AP-Agent
start_service || fail 'explicitly confirmed active Agent was rejected'
[ "$started" = 'ieee1905_transport beerocks_agent' ] ||
	fail 'confirmed active Agent started the wrong process set'

started=""; prepare_calls=0; test_passive=1; test_active_confirmed=0
test_wired_backhaul=1; test_require_encrypted=0
if start_service; then fail 'Agent with optional/open fronthaul policy was accepted'; fi
[ -z "$started" ] && [ "$prepare_calls" -eq 0 ] ||
	fail 'unsafe Agent encryption policy reached runtime preparation'

# Agent-only constraints must not be projected onto a Controller-only role.
started=""; prepare_calls=0; test_mode=Multi-AP-Controller
test_wired_backhaul=0; test_require_encrypted=0
start_service || fail 'Controller-only role inherited Agent policy gates'
[ "$started" = 'ieee1905_transport beerocks_controller' ] ||
	fail 'Controller-only role started the wrong process set after Agent gate isolation'

printf 'prplmesh_role_runtime=pass\n'
