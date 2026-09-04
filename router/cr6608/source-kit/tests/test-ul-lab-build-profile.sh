#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH= cd -- "${script_dir}/.." && pwd)"
applier="${root}/profiles/apply-build-profile.sh"
overlay="${root}/profiles/ul-lab/files"
forced_overlay="${root}/profiles/ul-forced-lab/files"
rf_dts_patch="${root}/patches/996-cr6608-dts-rf-38dbm-lab-mode.patch"
ul_muru_dts_patch="${root}/patches/996a-cr6608-dts-ul-muru-ram-gate.patch"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ul-lab-profile.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

fail() {
	printf 'UL-lab build profile contract failed: %s\n' "$*" >&2
	exit 1
}

for required in \
	etc/cr6608-artifact-profile \
	etc/modules.d/mt7915e \
	etc/config/wireless \
	etc/config/cr6608quick \
	etc/config/smartap \
	etc/smartap-version; do
	[ -s "${overlay}/${required}" ] || fail "missing overlay input: ${required}"
done
[ -s "$rf_dts_patch" ] && [ -s "$ul_muru_dts_patch" ] ||
	fail 'missing split CR6608 DTS inputs'
git apply --numstat "$rf_dts_patch" >/dev/null 2>&1 ||
	fail 'base RF DTS patch is malformed'
git apply --numstat "$ul_muru_dts_patch" >/dev/null 2>&1 ||
	fail 'UL-lab DTS patch is malformed'
! grep -Fq 'mediatek,cr6608-experimental-ul-muru' "$rf_dts_patch" ||
	fail 'stable LAB/Retail DTS input still exposes the UL MURU RAM gate'
[ "$(grep -Fxc '+		mediatek,cr6608-experimental-ul-muru;' "$ul_muru_dts_patch")" -eq 1 ] ||
	fail 'UL-lab DTS input does not add exactly one UL MURU RAM gate'

mkdir -p "$tmp/root"
cp -a -- "${root}/files/." "$tmp/root/"
original_shadow_sha="$(sha256sum "$tmp/root/etc/shadow" | awk '{print $1}')"
sh "$applier" ul-lab "$tmp/root"

printf '%s\n' \
	'profile=ul-muru-ram-v1' \
	'sale_ready=NO' \
	'radio_policy=ul-muru-ram-qualification' |
	cmp -s - "$tmp/root/etc/cr6608-artifact-profile" ||
	fail 'immutable RAM qualification metadata mismatch'
printf 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=15\n' |
	cmp -s - "$tmp/root/etc/modules.d/mt7915e" ||
	fail 'MediaTek MURU bitmap is not exact'

[ "$(sha256sum "$tmp/root/etc/shadow" | awk '{print $1}')" = "$original_shadow_sha" ] ||
	fail 'RAM qualification profile changed the operator credential'

wireless="$tmp/root/etc/config/wireless"
[ "$(grep -Ec "^[[:space:]]*option txpower '20'$" "$wireless")" -eq 2 ] ||
	fail 'qualification radios are not pinned to the conservative 20 dBm request'
[ "$(grep -Ec "^[[:space:]]*option disabled '0'$" "$wireless")" -eq 4 ] ||
	fail 'qualification radios/BSSs are not enabled for over-air testing'
! grep -Eq "^[[:space:]]*option txpower '38'$" "$wireless" ||
	fail 'qualification overlay retained a 38 dBm request'

smartap="$tmp/root/etc/config/smartap"
grep -Eq "^[[:space:]]*option ul_muru '1'$" "$smartap" &&
	grep -Eq "^[[:space:]]*option muru_mask '15'$" "$smartap" &&
	grep -Eq "^[[:space:]]*option ul_muru_guard '1'$" "$smartap" &&
	grep -Eq "^[[:space:]]*option ul_muru_state 'qualification-ram-only'$" "$smartap" ||
	fail 'qualification UCI policy is not fully armed'

quick="$tmp/root/etc/config/cr6608quick"
[ "$(grep -Ec "^[[:space:]]*option pppoe_vlan_enabled '0'$" "$quick")" -eq 1 ] ||
	fail 'qualification quick settings do not default PPPoE to bare WAN'

mkdir -p "$tmp/forced-root"
cp -a -- "${root}/files/." "$tmp/forced-root/"
sh "$applier" ul-forced-lab "$tmp/forced-root"
printf '%s\n' \
	'profile=ul-muru-forced-lab-v1' \
	'sale_ready=NO' \
	'radio_policy=ul-muru-persistent-mask15-38dbm-lab' |
	cmp -s - "$tmp/forced-root/etc/cr6608-artifact-profile" ||
	fail 'persistent forced-lab metadata mismatch'
printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=15\n' |
	cmp -s - "$tmp/forced-root/etc/modules.d/mt7915e" ||
	fail 'persistent forced-lab module policy mismatch'
grep -Eq "^[[:space:]]*option muru_mask '15'$" "$tmp/forced-root/etc/config/smartap" ||
	fail 'persistent forced-lab UCI mask is not armed'

for build in "${root}/build.sh" "${root}/build.remote.sh"; do
	grep -Fq 'ul-lab)' "$build" || fail "build lacks ul-lab case: ${build##*/}"
	grep -Fq 'ul-forced-lab)' "$build" || fail "build lacks ul-forced-lab case: ${build##*/}"
	grep -Fq 'PUBLISH_FLASHABLE_IMAGES=0' "$build" ||
		fail "build lacks RAM-only publication policy: ${build##*/}"
	grep -Fq 'cr6608-SMARTAP-v86-UL-MURU-RAM-QUALIFICATION-initramfs-kernel.bin' "$build" ||
		fail "build lacks exact UL-lab artifact name: ${build##*/}"
	grep -Fq 'SRC_UL_MURU_DTS_PATCH="${SCRIPT_DIR}/patches/996a-cr6608-dts-ul-muru-ram-gate.patch"' "$build" ||
		fail "build lacks the dedicated UL-lab DTS input: ${build##*/}"
	awk '
		prev == "if [ \"${BUILD_PROFILE}\" = ul-lab ] || [ \"${BUILD_PROFILE}\" = ul-forced-lab ]; then" &&
		$0 == "\tgit apply --check \"${SRC_UL_MURU_DTS_PATCH}\"" { check = 1 }
		prev == "\tgit apply --check \"${SRC_UL_MURU_DTS_PATCH}\"" &&
		$0 == "\tgit apply \"${SRC_UL_MURU_DTS_PATCH}\"" { apply = 1 }
		{ prev = $0 }
		END { exit !(check && apply) }
	' "$build" || fail "UL DTS patch is not applied only inside an enabled MURU profile branch: ${build##*/}"
	grep -Fq 'record_regular_input ul-muru-ram-platform-patch "${SRC_UL_MURU_DTS_PATCH}"' "$build" ||
		fail "UL-lab DTS input is absent from the build manifest: ${build##*/}"
	grep -Fq 'ul_muru_ram_dts_patch_sha256=' "$build" ||
		fail "UL-lab DTS input hash is absent from release metadata: ${build##*/}"
	grep -Fq 'Stable/Retail DTS must not expose the UL MURU RAM gate' "$build" ||
		fail "stable profile DTS absence is not fail-closed: ${build##*/}"
done

mkdir -p "$tmp/link-target"
ln -s "$tmp/link-target" "$tmp/link-root"

# MSYS without native-symlink support materializes `ln -s DIR LINK` as an
# ordinary directory copy.  Exercise the rejection only when a link was
# actually created; a copied directory is not a symlink attack.
if [ -L "$tmp/link-root" ] &&
   sh "$applier" ul-lab "$tmp/link-root" >/dev/null 2>&1; then
	fail 'profile applier accepted a symlinked target'
fi

printf 'ul_lab_build_profile_contract=pass\n'
