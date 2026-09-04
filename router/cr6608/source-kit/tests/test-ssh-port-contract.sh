#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEFAULT="$ROOT/files/etc/config/dropbear"
MIGRATION="$ROOT/files/etc/uci-defaults/96-cr6608-ssh-port"

fail() {
	printf 'ssh_port_contract=fail: %s\n' "$*" >&2
	exit 1
}

[ -s "$DEFAULT" ] && [ ! -L "$DEFAULT" ] || fail "default Dropbear config is missing"
[ -s "$MIGRATION" ] && [ ! -L "$MIGRATION" ] || fail "port migration is missing"
sh -n "$MIGRATION" || fail "port migration shell syntax failed"
[ "$(grep -Ec "^[[:space:]]*option Port[[:space:]]+'2003'$" "$DEFAULT")" -eq 1 ] ||
	fail "clean image is not pinned to port 2003"
grep -Fq 'sed -n '\''s/^dropbear\.\([^.=]*\)=dropbear$/\1/p'\''' "$MIGRATION" ||
	fail "migration does not enumerate every Dropbear instance"
grep -Fq 'uci -q set "dropbear.${section}.Port=2003"' "$MIGRATION" ||
	fail "migration does not replace preserved ports"
grep -Fq 'uci -q commit dropbear' "$MIGRATION" ||
	fail "migration does not commit the result"
grep -Fq 'uci -q revert dropbear' "$MIGRATION" ||
	fail "migration failure path does not discard partial changes"
if grep -Eq 'Port=22|Port[[:space:]]+22|listen.*:22' "$MIGRATION"; then
	fail "migration reintroduces SSH port 22"
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ssh-port.XXXXXX")" ||
	fail "cannot create test directory"
trap 'rm -rf "$tmp"' 0 HUP INT TERM
calls="$tmp/calls"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = -q ] && shift
case "${1:-}" in
	show)
		printf '%s\n' \
			'dropbear.main=dropbear' \
			'dropbear.main.Port='\''22'\''' \
			'dropbear.@dropbear[1]=dropbear' \
			'dropbear.@dropbear[1].Port='\''2200'\'''
		;;
	set)
		printf 'set %s\n' "${2:-}" >>"$SSH_TEST_CALLS"
		;;
	get)
		if [ "${SSH_TEST_FAIL_GET:-0}" = 1 ]; then
			printf '22\n'
		else
			printf '2003\n'
		fi
		;;
	commit)
		printf 'commit %s\n' "${2:-}" >>"$SSH_TEST_CALLS"
		;;
	revert)
		printf 'revert %s\n' "${2:-}" >>"$SSH_TEST_CALLS"
		;;
	add)
		printf 'cfgtest\n'
		;;
	*)
		exit 1
		;;
esac
EOF
chmod 0755 "$tmp/bin/uci"
: >"$calls"
SSH_TEST_CALLS="$calls" PATH="$tmp/bin:$PATH" sh "$MIGRATION" ||
	fail "migration rejected a preserved configuration"

for expected in \
	'set dropbear.main.enable=1' \
	'set dropbear.main.Port=2003' \
	'set dropbear.@dropbear[1].enable=1' \
	'set dropbear.@dropbear[1].Port=2003' \
	'commit dropbear'; do
	grep -Fqx "$expected" "$calls" || fail "missing migration call: $expected"
done
[ "$(grep -c 'Port=2003$' "$calls")" -eq 2 ] ||
	fail "migration did not pin every preserved instance"

: >"$calls"
if SSH_TEST_CALLS="$calls" SSH_TEST_FAIL_GET=1 PATH="$tmp/bin:$PATH" sh "$MIGRATION"; then
	fail "migration accepted an unverified port write"
fi
grep -Fqx 'revert dropbear' "$calls" ||
	fail "migration did not revert after a verification failure"

rm -rf "$tmp"
trap - 0 HUP INT TERM
printf 'ssh_port_contract=pass\n'
