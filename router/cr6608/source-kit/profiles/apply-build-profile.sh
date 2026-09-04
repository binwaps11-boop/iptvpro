#!/bin/sh
# Apply a build-time-only CR6608 overlay. The lab profile deliberately leaves
# the historical operator tree byte-for-byte unchanged. Retail starts from the
# same audited source and then replaces only its immutable safety defaults.

set -eu
umask 077

fail() {
	printf 'profile apply failed: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || fail 'usage: apply-build-profile.sh lab|retail|ul-forced-lab|ul-lab STAGED_ROOT'
profile_name="$1"
staged_root="$2"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
retail_root="${script_dir}/retail/files"
ul_lab_root="${script_dir}/ul-lab/files"
ul_forced_lab_root="${script_dir}/ul-forced-lab/files"

case "$profile_name" in
	lab) ;;
	retail) ;;
	ul-forced-lab) ;;
	ul-lab) ;;
	*) fail 'profile must be lab, retail, ul-forced-lab, or ul-lab' ;;
esac

[ -d "$staged_root" ] && [ ! -L "$staged_root" ] ||
	fail 'staged root must be a real directory'

# Lab remains the default and must not be rewritten by this helper.  UL-lab is
# a RAM-boot-only qualification overlay and never locks or provisions secrets.
[ "$profile_name" != lab ] || exit 0

if [ "$profile_name" = retail ]; then
	profile_root="$retail_root"
	profile_label=retail
	required_profile_files='etc/cr6608-artifact-profile
etc/modules.d/mt7915e
etc/config/wireless
etc/config/rpcd
etc/config/cr6608quick
etc/config/smartap
etc/smartap-version'
else
	profile_root="$ul_lab_root"
	profile_label=ul-lab
	required_profile_files='etc/cr6608-artifact-profile
etc/modules.d/mt7915e
etc/config/wireless
etc/config/cr6608quick
etc/config/smartap
etc/smartap-version'
fi

if [ "$profile_name" = ul-forced-lab ]; then
	profile_root="$ul_forced_lab_root"
	profile_label=ul-forced-lab
	required_profile_files='etc/cr6608-artifact-profile
etc/modules.d/mt7915e
etc/config/smartap
etc/smartap-version'
fi

[ -d "$profile_root" ] && [ ! -L "$profile_root" ] ||
	fail "${profile_label} overlay is missing or unsafe"
if find "$profile_root" -type l -print -quit | grep -q .; then
	fail "${profile_label} overlay must not contain symlinks"
fi
printf '%s\n' "$required_profile_files" | while IFS= read -r required; do
	[ -n "$required" ] || continue
	[ -f "${profile_root}/${required}" ] && [ ! -L "${profile_root}/${required}" ] ||
		fail "${profile_label} overlay input is missing: ${required}"
done

cp -a -- "${profile_root}/." "${staged_root}/" ||
	fail "could not apply ${profile_label} overlay"

[ "$(grep -Ec "^[[:space:]]*option pppoe_vlan_enabled '0'$" \
	"${staged_root}/etc/config/cr6608quick")" -eq 1 ] ||
	fail "${profile_label} PPPoE must default exactly once to bare WAN"

if [ "$profile_name" = ul-lab ]; then
	printf '%s\n' \
		'profile=ul-muru-ram-v1' \
		'sale_ready=NO' \
		'radio_policy=ul-muru-ram-qualification' |
		cmp -s - "${staged_root}/etc/cr6608-artifact-profile" ||
		fail 'UL-lab artifact metadata is not exact'
	printf 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=15\n' |
		cmp -s - "${staged_root}/etc/modules.d/mt7915e" ||
		fail 'UL-lab module policy is not exact'
	exit 0
fi

if [ "$profile_name" = ul-forced-lab ]; then
	printf '%s\n' \
		'profile=ul-muru-forced-lab-v1' \
		'sale_ready=NO' \
		'radio_policy=ul-muru-persistent-mask15-38dbm-lab' |
		cmp -s - "${staged_root}/etc/cr6608-artifact-profile" ||
		fail 'UL-forced-lab artifact metadata is not exact'
	printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=15\n' |
		cmp -s - "${staged_root}/etc/modules.d/mt7915e" ||
		fail 'UL-forced-lab module policy is not exact'
	exit 0
fi

# A generic retail artifact contains no usable shared root credential. The
# per-device provisioner installs a unique SHA-512-crypt verifier later.
shadow_file="${staged_root}/etc/shadow"
[ -f "$shadow_file" ] && [ ! -L "$shadow_file" ] ||
	fail 'staged shadow file is missing or unsafe'
shadow_tmp="$(mktemp "${shadow_file}.retail.XXXXXX")" ||
	fail 'could not create locked-shadow replacement'
cleanup() { rm -f -- "$shadow_tmp"; }
trap cleanup EXIT HUP INT TERM
awk -F: -v OFS=: '
	$1 == "root" { $2="!"; root_count++ }
	{ print }
	END { if (root_count != 1) exit 1 }
' "$shadow_file" > "$shadow_tmp" || fail 'could not lock the retail root account'
chmod 0600 "$shadow_tmp" || fail 'could not protect the retail shadow file'
mv -f -- "$shadow_tmp" "$shadow_file" || fail 'could not publish the retail shadow file'
shadow_tmp=''
trap - EXIT HUP INT TERM

# The shared LAB Web verifier is needed only by the legacy/operator migration.
# Even though the Retail path exits fail-closed before using it, do not ship its
# bytes in a generic sale-bound rootfs. Replace the single audited assignment
# atomically and reject an unexpected source line instead of broad rewriting.
preserved_migration="${staged_root}/etc/uci-defaults/99-cr6608-preserved-config-v2"
[ -f "$preserved_migration" ] && [ ! -L "$preserved_migration" ] ||
	fail 'retail preserved-config migration is missing or unsafe'
shared_web_hash_line='RPCD_ROOT_PASSWORD='"'"'$6$CR6608dashAdm$BQqw1LRyISWT1W76KgXLbFMpuB0lDBY4CVz7vdm4PMg1YZ6y9fh.GZ0hKRp8X9NGb4FR5dGd7lsMiuCOK3hwl.'"'"''
[ "$(grep -Fxc "$shared_web_hash_line" "$preserved_migration")" -eq 1 ] ||
	fail 'retail migration shared-verifier source is not exact'
migration_tmp="$(mktemp "${preserved_migration}.retail.XXXXXX")" ||
	fail 'could not create retail migration replacement'
cleanup_migration() { rm -f -- "$migration_tmp"; }
trap cleanup_migration EXIT HUP INT TERM
sed "s|^RPCD_ROOT_PASSWORD=.*$|RPCD_ROOT_PASSWORD='!'|" \
	"$preserved_migration" > "$migration_tmp" ||
	fail 'could not remove the shared verifier from the retail migration'
chmod 0755 "$migration_tmp" || fail 'could not protect the retail migration replacement'
mv -f -- "$migration_tmp" "$preserved_migration" ||
	fail 'could not publish the retail migration replacement'
migration_tmp=''
trap - EXIT HUP INT TERM
[ "$(grep -Fxc "RPCD_ROOT_PASSWORD='!'" "$preserved_migration")" -eq 1 ] ||
	fail 'retail migration verifier was not locked'
! grep -Fq '$6$CR6608dashAdm$' "$preserved_migration" ||
	fail 'retail migration still embeds the shared verifier'

printf '%s\n' \
	'profile=retail-v1' \
	'sale_ready=NO' \
	'radio_policy=retail-disabled' |
	cmp -s - "${staged_root}/etc/cr6608-artifact-profile" ||
	fail 'retail artifact metadata is not exact'
printf 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0\n' |
	cmp -s - "${staged_root}/etc/modules.d/mt7915e" ||
	fail 'retail module policy is not exact'
[ "$(awk -F: '$1 == "root" { print $2; count++ } END { if (count != 1) exit 1 }' "$shadow_file")" = '!' ] ||
	fail 'retail root account did not remain locked'

exit 0
