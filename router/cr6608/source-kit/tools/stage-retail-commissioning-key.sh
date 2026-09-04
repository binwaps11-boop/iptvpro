#!/bin/sh
# Stage a public-key-only factory access path into a Retail RAM image.
# This helper must never be used for a persistent or sale artifact.

set -eu
umask 077

fail() {
	printf 'retail commissioning stage failed: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || fail 'usage: stage-retail-commissioning-key.sh STAGED_ROOT PUBLIC_KEY'
staged_root="$1"
public_key="$2"

[ -d "$staged_root" ] && [ ! -L "$staged_root" ] ||
	fail 'staged root must be a real directory'
[ -f "$public_key" ] && [ ! -L "$public_key" ] ||
	fail 'public key must be a regular non-symlink file'
[ "$(wc -c < "$public_key" | tr -d '[:space:]')" -le 1024 ] 2>/dev/null ||
	fail 'public key file is oversized'
[ "$(wc -l < "$public_key" | tr -d '[:space:]')" = 1 ] ||
	fail 'public key file must contain exactly one line'
! grep -q "$(printf '\r')" "$public_key" || fail 'public key contains CR bytes'

profile="$staged_root/etc/cr6608-artifact-profile"
[ -f "$profile" ] && [ ! -L "$profile" ] || fail 'Retail artifact profile is missing'
printf '%s\n' \
	'profile=retail-v1' \
	'sale_ready=NO' \
	'radio_policy=retail-disabled' |
	cmp -s - "$profile" || fail 'commissioning requires the exact locked Retail profile'

key_listing="$(ssh-keygen -E sha256 -lf "$public_key" 2>/dev/null)" ||
	fail 'ssh-keygen rejected the public key'
case "$key_listing" in
	'256 SHA256:'*' (ED25519)') ;;
	*) fail 'only one ED25519 factory public key is accepted' ;;
esac

dropbear="$staged_root/etc/config/dropbear"
[ -f "$dropbear" ] && [ ! -L "$dropbear" ] || fail 'Dropbear configuration is missing'
[ "$(grep -Ec "^[[:space:]]*option PasswordAuth 'on'$" "$dropbear")" -eq 1 ] ||
	fail 'unexpected PasswordAuth source policy'
[ "$(grep -Ec "^[[:space:]]*option RootPasswordAuth 'on'$" "$dropbear")" -eq 1 ] ||
	fail 'unexpected RootPasswordAuth source policy'

dropbear_tmp="$(mktemp "${dropbear}.commissioning.XXXXXX")" ||
	fail 'could not allocate Dropbear replacement'
cleanup() { rm -f -- "$dropbear_tmp"; }
trap cleanup EXIT HUP INT TERM
sed \
	-e "s/option PasswordAuth 'on'/option PasswordAuth 'off'/" \
	-e "s/option RootPasswordAuth 'on'/option RootPasswordAuth 'off'/" \
	"$dropbear" > "$dropbear_tmp" || fail 'could not disable password authentication'
chmod 0600 "$dropbear_tmp" || fail 'could not protect Dropbear replacement'
mv -f -- "$dropbear_tmp" "$dropbear" || fail 'could not publish Dropbear replacement'
dropbear_tmp=''
trap - EXIT HUP INT TERM

key_dir="$staged_root/etc/dropbear"
if [ -e "$key_dir" ]; then
	[ -d "$key_dir" ] && [ ! -L "$key_dir" ] || fail 'Dropbear key directory is unsafe'
else
	mkdir -m 0700 -- "$key_dir" || fail 'could not create Dropbear key directory'
fi
[ ! -e "$key_dir/authorized_keys" ] && [ ! -L "$key_dir/authorized_keys" ] ||
	fail 'refusing to replace an existing authorized_keys file'
install -m 0600 -- "$public_key" "$key_dir/authorized_keys" ||
	fail 'could not install the commissioning public key'

marker="$staged_root/etc/cr6608-retail-commissioning-ram"
[ ! -e "$marker" ] && [ ! -L "$marker" ] || fail 'commissioning marker already exists'
{
	printf '%s\n' \
		'profile=retail-commissioning-ram-v1' \
		'sale_ready=NO' \
		'boot_policy=ram-only' \
		'password_auth=disabled'
	printf 'factory_key_fingerprint=%s\n' "$(printf '%s\n' "$key_listing" | awk '{print $2}')"
	printf 'factory_key_sha256=%s\n' "$(sha256sum "$public_key" | awk '{print $1}')"
} > "$marker" || fail 'could not create commissioning marker'
chmod 0400 "$marker" || fail 'could not protect commissioning marker'

printf 'retail_commissioning_key_stage=pass\n'
