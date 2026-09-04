#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
stage="$root/tools/stage-retail-commissioning-key.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-retail-commissioning.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

fail() { printf 'retail commissioning key contract failed: %s\n' "$*" >&2; exit 1; }
[ -x "$stage" ] || fail 'stage helper is missing or not executable'

make_root() {
	dst="$1"
	mkdir -p "$dst/etc/config"
	printf '%s\n' 'profile=retail-v1' 'sale_ready=NO' 'radio_policy=retail-disabled' > \
		"$dst/etc/cr6608-artifact-profile"
	cat > "$dst/etc/config/dropbear" <<'EOF'
config dropbear main
	option enable '1'
	option PasswordAuth 'on'
	option RootPasswordAuth 'on'
	option Port '2003'
EOF
}

ssh-keygen -q -t ed25519 -N '' -C cr6608-test -f "$tmp/key" >/dev/null
make_root "$tmp/good"
[ "$(sh "$stage" "$tmp/good" "$tmp/key.pub")" = 'retail_commissioning_key_stage=pass' ] ||
	fail 'valid ED25519 key was rejected'
grep -Eq "^[[:space:]]*option PasswordAuth 'off'$" "$tmp/good/etc/config/dropbear" ||
	fail 'password authentication remained enabled'
grep -Eq "^[[:space:]]*option RootPasswordAuth 'off'$" "$tmp/good/etc/config/dropbear" ||
	fail 'root password authentication remained enabled'
cmp -s "$tmp/key.pub" "$tmp/good/etc/dropbear/authorized_keys" ||
	fail 'installed public key differs'
[ "$(stat -c '%a' "$tmp/good/etc/dropbear/authorized_keys")" = 600 ] ||
	fail 'authorized_keys mode is unsafe'
grep -Fqx 'boot_policy=ram-only' "$tmp/good/etc/cr6608-retail-commissioning-ram" ||
	fail 'RAM-only marker is missing'
grep -Fqx "factory_key_sha256=$(sha256sum "$tmp/key.pub" | awk '{print $1}')" \
	"$tmp/good/etc/cr6608-retail-commissioning-ram" ||
	fail 'marker is not bound to the authorized key bytes'

make_root "$tmp/rsa"
ssh-keygen -q -t rsa -b 2048 -N '' -C cr6608-test -f "$tmp/rsa-key" >/dev/null
if sh "$stage" "$tmp/rsa" "$tmp/rsa-key.pub" >/dev/null 2>&1; then
	fail 'RSA key was accepted'
fi

make_root "$tmp/bad-profile"
sed -i 's/sale_ready=NO/sale_ready=YES/' "$tmp/bad-profile/etc/cr6608-artifact-profile"
if sh "$stage" "$tmp/bad-profile" "$tmp/key.pub" >/dev/null 2>&1; then
	fail 'sale-ready metadata was accepted'
fi

make_root "$tmp/existing"
mkdir -p "$tmp/existing/etc/dropbear"
: > "$tmp/existing/etc/dropbear/authorized_keys"
if sh "$stage" "$tmp/existing" "$tmp/key.pub" >/dev/null 2>&1; then
	fail 'an existing authorized_keys file was overwritten'
fi

printf 'retail_commissioning_key_contract=pass\n'
