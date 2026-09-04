#!/usr/bin/env bash
# Fail-closed inspection of the CR6608 images produced by build.sh.

set -euo pipefail
umask 022
SOURCE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

EXPECTED_ORIGIN="https://git.openwrt.org/openwrt/openwrt.git"
EXPECTED_COMMIT="f0a60eee2fe051741c643ea6118718aae1ef17fb"
EXPECTED_VERSION="25.12.5"
EXPECTED_REVISION="r33051-f5dae5ece4"
EXPECTED_DASHBOARD_UI_VERSION="cr6608-smartap-v86-live-design-27.0.0"
EXPECTED_DASHBOARD_CSS_ASSET="/dashboard.css?v=20260902-smartap-v86-live-design-v1"
EXPECTED_DASHBOARD_JS_ASSET="/dashboard.js?v=20260902-smartap-v86-live-design-v1"
DEVICE_PROFILE="xiaomi_mi-router-cr6608"
SUPPORTED_DEVICE="xiaomi,mi-router-cr6608"
COMPAT_MESSAGE="Config cannot be migrated from swconfig to DSA"
EXPECTED_TARGET_SHA256="72d2942546de37529723eca17231d7b4c39abee061ecf8dabd4a8607596e9da1"
EXPECTED_KERNEL_RELEASE="6.12.94"
RESCUE_NFT_BRIDGE_KERNEL_CONFIGS_CSV="CONFIG_NETFILTER_FAMILY_BRIDGE=y,CONFIG_NF_TABLES_BRIDGE=m,CONFIG_NFT_BRIDGE_META=m,CONFIG_NFT_BRIDGE_REJECT=m,CONFIG_NF_CONNTRACK_BRIDGE=m"
RESCUE_NFT_BRIDGE_CORE_MODULE="nf_tables.ko"
RESCUE_NFT_BRIDGE_MODULES_CSV="nf_conntrack_bridge.ko,nft_meta_bridge.ko,nft_reject_bridge.ko"
RESCUE_NFT_BRIDGE_AUTOLOAD_FILE="etc/modules.d/nft-bridge"
RESCUE_NFT_BRIDGE_AUTOLOADS_CSV="nf_conntrack_bridge,nft_meta_bridge,nft_reject_bridge"
IFS=, read -r -a RESCUE_NFT_BRIDGE_KERNEL_CONFIGS <<< \
	"${RESCUE_NFT_BRIDGE_KERNEL_CONFIGS_CSV}"
IFS=, read -r -a RESCUE_NFT_BRIDGE_MODULES <<< \
	"${RESCUE_NFT_BRIDGE_MODULES_CSV}"
IFS=, read -r -a RESCUE_NFT_BRIDGE_AUTOLOADS <<< \
	"${RESCUE_NFT_BRIDGE_AUTOLOADS_CSV}"

die() {
	printf 'IMAGE GATE FAILED: %s\n' "$*" >&2
	exit 1
}

check_javascript_syntax() {
	local javascript_file="$1"
	# Ubuntu 20.04 ships Node 12, whose parser keeps optional chaining and the
	# nullish coalescing operator behind harmony flags.  LuCI 25.12 legitimately
	# emits both.  Prefer the normal parser and use the two narrowly scoped flags
	# only when that parser rejects the file; malformed JavaScript still fails
	# both checks.
	node --check "${javascript_file}" >/dev/null 2>&1 ||
		node --harmony-optional-chaining --harmony-nullish --check \
			"${javascript_file}" >/dev/null 2>&1
}

[ "$#" -eq 5 ] || die \
	"usage: $0 SYSUPGRADE_IMAGE FIRMWARE_IMAGE INITRAMFS_IMAGE OPENWRT_DIR STAGED_OVERLAY"

IMAGE="$1"
FIRMWARE_IMAGE="$2"
INITRAMFS_IMAGE="$3"
OPENWRT_DIR="$4"
STAGED_OVERLAY="$5"
BUILD_PROFILE="${CR6608_BUILD_PROFILE:-lab}"
case "${BUILD_PROFILE}" in
	lab)
		ARTIFACT_PROFILE_LABEL='lab_operator'
		RETAIL_RADIO_GATE_STATUS='blocked_lab_artifact_requires_retail_rebuild'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=0'
		EXPECTED_SMARTAP_VERSION='SmartAP CR6608 v86-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM / OpenWrt 25.12.5 (non-sale lab 38 dBm request path; visible open default Wi-Fi; channel 36 default; MT7621 packet steering and EEE disabled; DSA TX-watchdog telemetry; bounded uhttpd recovery and supported security headers; MediaTek 25.12 MURU bitmap port compiled but stable-disabled, with synchronous command-response telemetry that is not apply or OTA proof, a one-way kernel fault latch, and RAM-only qualification profile; live Smart UI retains no telemetry cache; role-correct EasyMesh and carrier-aware port readiness; apk/opkg-aware package actions; UTF-8 JSON; LuCI-owned VLAN preservation with explicit takeover; one-hour live rpcd session validation; password-gated clean/preserved SSH and serial console; distinct per-device Web credential path with explicit sale block; Safe Apply; responsive Smart/Argon UI)'
		;;
	retail)
		ARTIFACT_PROFILE_LABEL='retail_v1'
		RETAIL_RADIO_GATE_STATUS='blocked_pending_per_device_provisioning_radio_audit_and_external_rf_verification'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0'
		EXPECTED_SMARTAP_VERSION='SmartAP CR6608 v86 RETAIL-v1 UNSALE PROVISIONING-REQUIRED / OpenWrt 25.12.5 (immutable radio policy disabled; no shared active credentials; Wi-Fi fail-closed until per-device provisioning; 38 dBm and MURU mask unarmed; sale approval requires device security/radio audits and external RF verification)'
		;;
	ul-forced-lab)
		ARTIFACT_PROFILE_LABEL='ul_muru_forced_lab_v1'
		RETAIL_RADIO_GATE_STATUS='blocked_forced_ul_muru_requires_ota_soak_and_external_rf_verification'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=15'
		EXPECTED_SMARTAP_VERSION='SmartAP CR6608 v86 UL-MURU-FORCED-LAB / OpenWrt 25.12.5 (persistent non-sale lab profile; mask 15 requests DL/UL OFDMA and DL/UL MU-MIMO; 38 dBm software request path; kernel fault latch and recovery retained; over-air multi-client and long-duration qualification pending)'
		;;
	ul-lab)
		ARTIFACT_PROFILE_LABEL='ul_muru_ram_v1'
		RETAIL_RADIO_GATE_STATUS='blocked_ram_qualification_requires_ota_soak_and_external_rf_verification'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=15'
		EXPECTED_SMARTAP_VERSION='SmartAP CR6608 v86 UL-MURU-RAM-QUALIFICATION / OpenWrt 25.12.5 (RAM-boot-only, non-sale MediaTek 25.12 STA_REC MURU bitmap port; mask 15 requests DL/UL OFDMA and DL/UL MU-MIMO; 38 dBm path disabled; synchronous command-response telemetry is not apply or OTA proof; one-way fault latch required; over-air and long-duration qualification pending)'
		;;
	*) die 'CR6608_BUILD_PROFILE must be lab, retail, ul-forced-lab, or ul-lab' ;;
esac
RETAIL_COMMISSIONING_MODE="${CR6608_RETAIL_COMMISSIONING_MODE:-0}"
case "${RETAIL_COMMISSIONING_MODE}" in
	0) ;;
	1)
		[ "${BUILD_PROFILE}" = retail ] ||
			die 'Retail commissioning inspection requires the retail profile'
		RETAIL_RADIO_GATE_STATUS='blocked_commissioning_ram_requires_unique_provisioning_and_external_rf_verification'
		;;
	*) die 'CR6608_RETAIL_COMMISSIONING_MODE must be 0 or 1' ;;
esac
FACTORY38_BUILD_MODE="${CR6608_FACTORY38_BUILD_MODE:-normal}"
case "${FACTORY38_BUILD_MODE}" in
	normal|maintenance) ;;
	*) die "CR6608_FACTORY38_BUILD_MODE must be normal or maintenance" ;;
esac
[ "${FACTORY38_BUILD_MODE}" != maintenance ] || [ "${BUILD_PROFILE}" = lab ] ||
	die 'Factory-38 maintenance is LAB-only'
TARGET_DEFINITION="${OPENWRT_DIR}/target/linux/ramips/image/mt7621.mk"
CR6608_DTS="${OPENWRT_DIR}/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts"
CR6608_DTSI="${OPENWRT_DIR}/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi"
FWTOOL="${OPENWRT_DIR}/staging_dir/host/bin/fwtool"
USIGN="${OPENWRT_DIR}/staging_dir/host/bin/usign"
UCERT="${OPENWRT_DIR}/staging_dir/host/bin/ucert"
APK="${OPENWRT_DIR}/staging_dir/host/bin/apk"
UNSQUASHFS="${OPENWRT_DIR}/staging_dir/host/bin/unsquashfs4"
FAKEROOT="${OPENWRT_DIR}/staging_dir/host/bin/fakeroot"
FW_SIGNING_KEY="${OPENWRT_DIR}/key-build"
FW_SIGNING_PUB="${OPENWRT_DIR}/key-build.pub"
APK_SIGNING_KEY="${OPENWRT_DIR}/private-key.pem"
APK_SIGNING_PUB="${OPENWRT_DIR}/public-key.pem"

[ -s "${IMAGE}" ] || die "sysupgrade image is missing or empty: ${IMAGE}"
[ -s "${FIRMWARE_IMAGE}" ] || die "firmware image is missing or empty: ${FIRMWARE_IMAGE}"
[ -s "${INITRAMFS_IMAGE}" ] || die "initramfs image is missing or empty: ${INITRAMFS_IMAGE}"
[ -d "${STAGED_OVERLAY}" ] || die "staged overlay is missing: ${STAGED_OVERLAY}"
[ ! -e "${STAGED_OVERLAY}/usr/sbin/cr6608-mndp-advertise" ] && \
	[ ! -L "${STAGED_OVERLAY}/usr/sbin/cr6608-mndp-advertise" ] || \
	die "opaque MNDP overlay binary is forbidden; it must be built from source"
[ ! -e "${STAGED_OVERLAY}/www/luci-static/resources/ui.js" ] || \
	die "staged overlay replaces LuCI ui.js and can bypass checked apply"
[ ! -e "${STAGED_OVERLAY}/usr/share/ucode/luci/controller/admin/uci.uc" ] || \
	die "staged overlay replaces LuCI's UCI controller"
for forbidden_overlay_path in \
	sbin/sysupgrade \
	lib/netifd/wireless/mac80211.sh \
	usr/lib/lua/luci/version.lua \
	www/cgi-bin/luci \
	www/luci-static/resources/luci.js \
	www/luci-static/resources/form.js \
	www/luci-static/resources/network.js; do
	[ ! -e "${STAGED_OVERLAY}/${forbidden_overlay_path}" ] || \
		die "staged overlay replaces a 25.12.5 package-owned file: ${forbidden_overlay_path}"
done
[ -s "${TARGET_DEFINITION}" ] || die "official target definition is missing"
[ -x "${FWTOOL}" ] || die "host fwtool was not built"
[ -x "${USIGN}" ] || die "host usign was not built"
[ -x "${UCERT}" ] || die "host ucert was not built"
[ -x "${APK}" ] || die "host apk was not built"
[ -x "${UNSQUASHFS}" ] || die "host unsquashfs4 was not built"
[ -x "${FAKEROOT}" ] || die "host fakeroot was not built"
[ -f "${FW_SIGNING_KEY}" ] && [ ! -L "${FW_SIGNING_KEY}" ] && \
	[ -s "${FW_SIGNING_KEY}" ] || die "OpenWrt key-build is missing"
[ -f "${FW_SIGNING_PUB}" ] && [ ! -L "${FW_SIGNING_PUB}" ] && \
	[ -s "${FW_SIGNING_PUB}" ] || die "OpenWrt key-build.pub is missing"
[ -f "${APK_SIGNING_KEY}" ] && [ ! -L "${APK_SIGNING_KEY}" ] && \
	[ -s "${APK_SIGNING_KEY}" ] || die "OpenWrt APK private key is missing"
[ -f "${APK_SIGNING_PUB}" ] && [ ! -L "${APK_SIGNING_PUB}" ] && \
	[ -s "${APK_SIGNING_PUB}" ] || die "OpenWrt APK public key is missing"
[ "$(stat -c '%a' "${FW_SIGNING_KEY}")" = 600 ] || \
	die "OpenWrt key-build mode is not 600"
[ "$(stat -c '%a' "${FW_SIGNING_PUB}")" = 644 ] || \
	die "OpenWrt key-build.pub mode is not 644"
[ "$(stat -c '%a' "${APK_SIGNING_KEY}")" = 600 ] || \
	die "OpenWrt APK private key mode is not 600"
[ "$(stat -c '%a' "${APK_SIGNING_PUB}")" = 644 ] || \
	die "OpenWrt APK public key mode is not 644"

[ "$(git -C "${OPENWRT_DIR}" remote get-url origin)" = "${EXPECTED_ORIGIN}" ] || \
	die "OpenWrt origin changed before inspection"
[ "$(git -C "${OPENWRT_DIR}" rev-parse HEAD)" = "${EXPECTED_COMMIT}" ] || \
	die "OpenWrt HEAD changed before inspection"
[ "$(sha256sum "${TARGET_DEFINITION}" | awk '{print $1}')" = \
	"${EXPECTED_TARGET_SHA256}" ] || die "official target definition changed"
grep -Fqx $'\t\tmediatek,cr6608-lab-txpower-38dbm;' "${CR6608_DTS}" || \
	die "CR6608 DTS lacks the device-specific LAB-38 request gate"
if [ "${BUILD_PROFILE}" = ul-lab ] || [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
	[ "$(grep -Fxc $'\t\tmediatek,cr6608-experimental-ul-muru;' "${CR6608_DTS}")" -eq 1 ] ||
		die "UL-lab DTS lacks the unique experimental MURU RAM gate"
else
	! grep -Fq 'mediatek,cr6608-experimental-ul-muru' "${CR6608_DTS}" ||
		die "Stable/Retail DTS exposes the experimental MURU RAM gate"
fi
if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	grep -Fqx $'\t\tfactory: partition@100000 {' "${CR6608_DTSI}" ||
		die "maintenance DTSI lacks the exact Factory phandle label"
	grep -Fqx $'\t/delete-property/ read-only;' "${CR6608_DTS}" ||
		die "maintenance DTS does not make Factory writable"
else
	grep -Fqx $'\t\tpartition@100000 {' "${CR6608_DTSI}" ||
		die "normal DTSI lacks the stock Factory partition"
	! grep -Fq 'factory: partition@100000' "${CR6608_DTSI}" ||
		die "normal image labels Factory for a writable override"
	! grep -Fq '/delete-property/ read-only;' "${CR6608_DTS}" ||
		die "normal image does not keep Factory read-only"
fi
grep -Fqx $'\t\tbootargs = "console=ttyS0,115200n8";' "${CR6608_DTSI}" || \
	die "CR6608 family DTSI no longer exposes the stock 115200 serial console"
if grep -Eq 'console=ttynull|bootargs-override' "${CR6608_DTS}"; then
	die "CR6608 DTS overrides or disables the stock serial console"
fi

device_block() {
	local name="$1"
	awk -v name="${name}" '
		$0 == "define Device/" name { inside = 1; found = 1 }
		inside { print }
		inside && $0 == "endef" { exit }
		END { if (!found) exit 1 }
	' "${TARGET_DEFINITION}"
}

block_var() {
	local block="$1"
	local key="$2"
	printf '%s\n' "${block}" | awk -v key="${key}" '
		$1 == key && $2 == ":=" { value = $3; count++ }
		END {
			if (count != 1) exit 1
			print value
		}
	'
}

unit_to_bytes() {
	local value="$1"
	case "${value}" in
		*[!0-9kKmM]*) die "unsupported target size value: ${value}" ;;
		*k|*K) printf '%s\n' "$(( ${value%[kK]} * 1024 ))" ;;
		*m|*M) printf '%s\n' "$(( ${value%[mM]} * 1024 * 1024 ))" ;;
		*) printf '%s\n' "$(( value ))" ;;
	esac
}

nand_block="$(device_block nand)" || die "Device/nand definition is missing"
parent_block="$(device_block xiaomi_mi-router-cr660x)" || \
	die "CR660x parent definition is missing"
device_block_text="$(device_block "${DEVICE_PROFILE}")" || \
	die "CR6608 target definition is missing"

printf '%s\n' "${parent_block}" | \
	grep -Eq '^[[:space:]]*\$\(Device/nand\)[[:space:]]*$' || \
	die "CR660x no longer inherits the official NAND definition"
printf '%s\n' "${device_block_text}" | \
	grep -Eq '^[[:space:]]*\$\(Device/xiaomi_mi-router-cr660x\)[[:space:]]*$' || \
	die "CR6608 no longer inherits the official CR660x definition"
! printf '%s\n' "${parent_block}" | grep -Eq '^[[:space:]]*KERNEL_SIZE[[:space:]]*:=' || \
	die "unexpected CR660x KERNEL_SIZE override"
! printf '%s\n' "${device_block_text}" | \
	grep -Eq '^[[:space:]]*(KERNEL_SIZE|IMAGE_SIZE)[[:space:]]*:=' || \
	die "unexpected CR6608 size override"

kernel_limit_value="$(block_var "${nand_block}" KERNEL_SIZE)" || \
	die "could not derive KERNEL_SIZE from Device/nand"
image_limit_value="$(block_var "${parent_block}" IMAGE_SIZE)" || \
	die "could not derive IMAGE_SIZE from the CR660x definition"
kernel_limit_bytes="$(unit_to_bytes "${kernel_limit_value}")"
image_limit_bytes="$(unit_to_bytes "${image_limit_value}")"
[ "${kernel_limit_bytes}" -gt 0 ] || die "invalid kernel partition limit"
[ "${image_limit_bytes}" -gt "${kernel_limit_bytes}" ] || die "invalid image limit"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-image-gate.XXXXXX")"
cleanup() {
	case "${tmp_dir}" in
		"${TMPDIR:-/tmp}"/cr6608-image-gate.*) rm -rf -- "${tmp_dir}" ;;
	esac
}
trap cleanup EXIT

signing_probe="${tmp_dir}/package-signing-probe"
signing_probe_signature="${signing_probe}.sig"
printf 'cr6608 package signing probe\n' > "${signing_probe}"
if ! "${USIGN}" -S -m "${signing_probe}" -s "${FW_SIGNING_KEY}" \
	-x "${signing_probe_signature}" >/dev/null 2>&1; then
	die "private build key could not sign the package-key probe"
fi
if ! "${USIGN}" -V -m "${signing_probe}" -p "${FW_SIGNING_PUB}" \
	-x "${signing_probe_signature}" >/dev/null 2>&1; then
	die "key-build and key-build.pub are not a matching signing pair"
fi
apk_pub_probe="${tmp_dir}/apk-public-key.pem"
apk_pub_canonical="${tmp_dir}/apk-public-key-canonical.pem"
if ! openssl pkey -in "${APK_SIGNING_KEY}" -pubout -out "${apk_pub_probe}" \
	>/dev/null 2>&1; then
	die "APK private key is not a valid EC private key"
fi
if ! openssl pkey -pubin -in "${APK_SIGNING_PUB}" -pubout \
	-out "${apk_pub_canonical}" >/dev/null 2>&1; then
	die "APK public key is not a valid EC public key"
fi
cmp -s "${apk_pub_probe}" "${apk_pub_canonical}" || \
	die "private-key.pem and public-key.pem are not a matching APK signing pair"

apk_index_list="${tmp_dir}/apk-indexes.list0"
apk_index_sorted="${tmp_dir}/apk-indexes.sorted0"
find "${OPENWRT_DIR}/bin" -type f -name packages.adb -print0 > "${apk_index_list}" || \
	die "could not enumerate APK indexes"
LC_ALL=C sort -z "${apk_index_list}" > "${apk_index_sorted}" || \
	die "could not sort APK indexes"
mapfile -d '' -t apk_indexes < "${apk_index_sorted}"
apk_indexes_checked=0
apk_verify_root="${tmp_dir}/apk-verify-root"
mkdir -p "${apk_verify_root}/etc/apk/keys"
cp -- "${APK_SIGNING_PUB}" "${apk_verify_root}/etc/apk/keys/public-key.pem"
for apk_index in "${apk_indexes[@]}"; do
	[ -s "${apk_index}" ] || die "APK index is empty: ${apk_index}"
	if ! "${APK}" --root "${apk_verify_root}" \
		--keys-dir "${apk_verify_root}/etc/apk/keys" --no-logfile --no-cache \
		--repositories-file /dev/null --repository "file://${apk_index}" \
		search >/dev/null 2>&1; then
		die "APK index is not trusted by public-key.pem: ${apk_index}"
	fi
	apk_indexes_checked=$(( apk_indexes_checked + 1 ))
done
[ "${apk_indexes_checked}" -gt 0 ] || die "no signed APK indexes were produced"

tar_prefix="sysupgrade-${DEVICE_PROFILE}"
expected_members="${tmp_dir}/expected-members.txt"
actual_members="${tmp_dir}/actual-members.txt"
printf '%s\n' \
	"${tar_prefix}/" \
	"${tar_prefix}/CONTROL" \
	"${tar_prefix}/kernel" \
	"${tar_prefix}/root" > "${expected_members}"
tar -tf "${IMAGE}" > "${actual_members}"
if ! cmp -s "${expected_members}" "${actual_members}"; then
	diff -u "${expected_members}" "${actual_members}" >&2 || true
	die "sysupgrade tar member set is not exact"
fi

control="$(tar -xOf "${IMAGE}" "${tar_prefix}/CONTROL")"
[ "${control}" = "BOARD=${DEVICE_PROFILE}" ] || die "invalid sysupgrade CONTROL member"

kernel_member="${tmp_dir}/kernel"
root_member="${tmp_dir}/root.squashfs"
tar -xOf "${IMAGE}" "${tar_prefix}/kernel" > "${kernel_member}"
tar -xOf "${IMAGE}" "${tar_prefix}/root" > "${root_member}"
[ -s "${kernel_member}" ] || die "empty kernel member"
[ -s "${root_member}" ] || die "empty root member"

kernel_magic="$(dd if="${kernel_member}" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
root_magic="$(dd if="${root_member}" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "${kernel_magic}" = "27051956" ] || die "kernel member is not a uImage"
[ "${root_magic}" = "68737173" ] || die "root member is not little-endian squashfs"

kernel_bytes="$(stat -c '%s' "${kernel_member}")"
rootfs_bytes="$(stat -c '%s' "${root_member}")"
image_bytes="$(stat -c '%s' "${IMAGE}")"
firmware_bytes="$(stat -c '%s' "${FIRMWARE_IMAGE}")"
initramfs_bytes="$(stat -c '%s' "${INITRAMFS_IMAGE}")"
rootfs_budget_bytes="$(( image_limit_bytes - kernel_limit_bytes ))"
payload_bytes="$(( kernel_bytes + rootfs_bytes ))"

[ "${kernel_bytes}" -le "${kernel_limit_bytes}" ] || \
	die "kernel ${kernel_bytes} exceeds official limit ${kernel_limit_bytes}"
[ "${rootfs_bytes}" -le "${rootfs_budget_bytes}" ] || \
	die "rootfs ${rootfs_bytes} exceeds official post-kernel budget ${rootfs_budget_bytes}"
[ "${payload_bytes}" -le "${image_limit_bytes}" ] || \
	die "kernel plus rootfs exceeds the official image limit"
[ "${image_bytes}" -le "${image_limit_bytes}" ] || \
	die "sysupgrade container exceeds the official image limit"
[ "${firmware_bytes}" -le "${image_limit_bytes}" ] || \
	die "firmware image exceeds the official image limit"
[ "${initramfs_bytes}" -le "${image_limit_bytes}" ] || \
	die "RAM-boot initramfs image exceeds the official image-size safety bound"

firmware_magic="$(dd if="${FIRMWARE_IMAGE}" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "${firmware_magic}" = "27051956" ] || die "firmware image does not begin with the built uImage"
initramfs_magic="$(dd if="${INITRAMFS_IMAGE}" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "${initramfs_magic}" = "27051956" ] || die "initramfs image is not a uImage"
cmp -n "${kernel_bytes}" "${kernel_member}" "${FIRMWARE_IMAGE}" || \
	die "firmware image kernel differs from the sysupgrade kernel"
ubi_magic="$(od -An -j "${kernel_limit_bytes}" -N 4 -tx1 "${FIRMWARE_IMAGE}" | tr -d ' \n')"
[ "${ubi_magic}" = "55424923" ] || \
	die "firmware image lacks UBI at the official kernel boundary"

metadata="${tmp_dir}/metadata.json"
if ! "${FWTOOL}" -i "${metadata}" "${IMAGE}"; then
	die "fwtool metadata is absent"
fi
[ -s "${metadata}" ] || die "fwtool metadata is absent"
image_signature="${tmp_dir}/image-signature"
unsigned_image="${tmp_dir}/image-without-signature.bin"
"${FWTOOL}" -s "${image_signature}" "${IMAGE}" >/dev/null 2>&1 || \
	die "fwtool signature chunk is absent"
[ -s "${image_signature}" ] || die "fwtool signature chunk is empty"
"${FWTOOL}" -T -s /dev/null "${IMAGE}" > "${unsigned_image}" || \
	die "could not derive the signed image payload"
[ -s "${unsigned_image}" ] || die "signed image payload is empty"
PATH="$(dirname "${USIGN}"):${PATH}" "${UCERT}" -V \
	-c "${image_signature}" -m "${unsigned_image}" -p "${FW_SIGNING_PUB}" \
	-q >/dev/null 2>&1 || \
	die "sysupgrade image certificate is not valid for key-build.pub"
python3 - "${metadata}" "${EXPECTED_VERSION}" "${DEVICE_PROFILE}" \
	"${SUPPORTED_DEVICE}" "${EXPECTED_REVISION}" "${COMPAT_MESSAGE}" <<'PY'
import json
import sys

(
    path,
    expected_version,
    expected_board,
    expected_device,
    expected_revision,
    compat_message,
) = sys.argv[1:]

try:
    with open(path, "r", encoding="utf-8") as stream:
        metadata = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as exc:
    raise SystemExit(f"IMAGE GATE FAILED: invalid fwtool metadata: {exc}")

version = metadata.get("version")
if not isinstance(version, dict):
    raise SystemExit("IMAGE GATE FAILED: metadata version object is absent")

expected = {
    "dist": "OpenWrt",
    "version": expected_version,
    "target": "ramips/mt7621",
    "board": expected_board,
}
for key, value in expected.items():
    if version.get(key) != value:
        raise SystemExit(
            f"IMAGE GATE FAILED: metadata {key} is {version.get(key)!r}, expected {value!r}"
        )

if metadata.get("metadata_version") != "1.1":
    raise SystemExit("IMAGE GATE FAILED: metadata_version is not 1.1")
if metadata.get("compat_version") != "1.1":
    raise SystemExit("IMAGE GATE FAILED: compat_version is not 1.1")
if metadata.get("compat_message") != compat_message:
    raise SystemExit("IMAGE GATE FAILED: compat_message is not exact")
if version.get("revision") != expected_revision:
    raise SystemExit(
        f"IMAGE GATE FAILED: metadata revision is {version.get('revision')!r}, "
        f"expected {expected_revision!r}"
    )

new_supported = metadata.get("new_supported_devices")
legacy_supported = metadata.get("supported_devices")
expected_legacy = (
    f"{expected_device} - Image version mismatch: image 1.1, device 1.0. "
    "Please wipe config during upgrade (force required) or reinstall. "
    f"Reason: {compat_message}"
)
if new_supported != [expected_device]:
    raise SystemExit(
        f"IMAGE GATE FAILED: new_supported_devices is {new_supported!r}, "
        f"expected {[expected_device]!r}"
    )
if legacy_supported != [expected_legacy]:
    raise SystemExit(
        f"IMAGE GATE FAILED: supported_devices is {legacy_supported!r}, "
        f"expected {[expected_legacy]!r}"
    )
PY

rootfs_dir="${tmp_dir}/rootfs"
# OpenWrt rootfs images contain /dev nodes.  Fakeroot lets an unprivileged,
# reproducible build inspect them without weakening unsquashfs error handling.
"${FAKEROOT}" -- "${UNSQUASHFS}" -no-progress \
	-d "${rootfs_dir}" "${root_member}" >/dev/null
[ -d "${rootfs_dir}" ] || die "rootfs extraction failed"
grep -Fqx 'CONFIG_SIGNATURE_CHECK=y' "${OPENWRT_DIR}/.config" || \
	die "built configuration does not enforce sysupgrade signatures"
grep -Fqx 'CONFIG_PACKAGE_ucert=y' "${OPENWRT_DIR}/.config" || \
	die "built configuration does not include target ucert"
[ -x "${rootfs_dir}/usr/bin/ucert" ] || \
	die "rootfs lacks the executable target-side ucert verifier"
grep -Fqx 'REQUIRE_IMAGE_SIGNATURE=1' "${rootfs_dir}/lib/upgrade/fwtool.sh" || \
	die "rootfs does not require image signatures during sysupgrade"
grep -Fqx 'REQUIRE_IMAGE_METADATA=1' "${rootfs_dir}/lib/upgrade/fwtool.sh" || \
	die "rootfs does not require image metadata during sysupgrade"
cmp -s "${FW_SIGNING_PUB}" \
	"${rootfs_dir}/etc/opkg/keys/c2b162a7217acaa4" || \
	die "rootfs owner firmware trust key differs from the pinned signing key"
grep -Fqx 'CONFIG_PACKAGE_kmod-nft-bridge=y' "${OPENWRT_DIR}/.config" || \
	die "built OpenWrt config lacks kmod-nft-bridge"
! grep -Fqx 'CONFIG_PACKAGE_luci-app-package-manager=y' "${OPENWRT_DIR}/.config" || \
	die "retail image exposes the unguarded stock LuCI package manager"
for guarded_luci_component in luci-light libustream-mbedtls px5g-mbedtls; do
	grep -Fqx "CONFIG_PACKAGE_${guarded_luci_component}=y" "${OPENWRT_DIR}/.config" || \
		die "retail image lacks explicit guarded LuCI component: ${guarded_luci_component}"
done
for forbidden_luci_meta in luci luci-ssl; do
	! grep -Fqx "CONFIG_PACKAGE_${forbidden_luci_meta}=y" "${OPENWRT_DIR}/.config" || \
		die "retail image selected LuCI meta package: ${forbidden_luci_meta}"
done
mapfile -d '' -t rescue_nft_module_dirs < <(
	find "${rootfs_dir}/lib/modules" -mindepth 1 -maxdepth 1 -type d -print0
)
[ "${#rescue_nft_module_dirs[@]}" -eq 1 ] || \
	die "rootfs must contain exactly one kernel module release directory"
rescue_nft_bridge_kernel_release="$(basename -- "${rescue_nft_module_dirs[0]}")"
[ "${rescue_nft_bridge_kernel_release}" = "${EXPECTED_KERNEL_RELEASE}" ] || \
	die "rootfs nft bridge kernel release is not ${EXPECTED_KERNEL_RELEASE}"
rescue_nft_bridge_core_path=""
rescue_nft_bridge_module_paths=()
for rescue_nft_module in \
	"${RESCUE_NFT_BRIDGE_CORE_MODULE}" \
	"${RESCUE_NFT_BRIDGE_MODULES[@]}"; do
	mapfile -d '' -t rescue_nft_module_matches < <(
		find "${rootfs_dir}/lib/modules" -type f \
			-name "${rescue_nft_module}" -print0
	)
	[ "${#rescue_nft_module_matches[@]}" -eq 1 ] || \
		die "rootfs must contain exactly one ${rescue_nft_module} kernel module"
	rescue_nft_module_path="${rescue_nft_module_matches[0]}"
	[ "$(dirname -- "${rescue_nft_module_path}")" = \
		"${rescue_nft_module_dirs[0]}" ] || \
		die "rootfs ${rescue_nft_module} is outside the exact kernel release directory"
	[ -f "${rescue_nft_module_path}" ] && [ ! -L "${rescue_nft_module_path}" ] && \
		[ -s "${rescue_nft_module_path}" ] || \
		die "rootfs ${rescue_nft_module} is not a non-empty regular file"
	[ "$(stat -c '%a' "${rescue_nft_module_path}")" = 644 ] || \
		die "rootfs ${rescue_nft_module} mode is not 644"
	if [ "${rescue_nft_module}" = "${RESCUE_NFT_BRIDGE_CORE_MODULE}" ]; then
		rescue_nft_bridge_core_path="${rescue_nft_module_path}"
	else
		rescue_nft_bridge_module_paths+=("${rescue_nft_module_path}")
	fi
done
[ -n "${rescue_nft_bridge_core_path}" ] && \
	[ "${#rescue_nft_bridge_module_paths[@]}" -eq \
		"${#RESCUE_NFT_BRIDGE_MODULES[@]}" ] || \
	die "rootfs nft bridge module set is incomplete"
rescue_nft_bridge_autoload_path="${rootfs_dir}/${RESCUE_NFT_BRIDGE_AUTOLOAD_FILE}"
[ -f "${rescue_nft_bridge_autoload_path}" ] && \
	[ ! -L "${rescue_nft_bridge_autoload_path}" ] || \
	die "rootfs nft bridge modules.d autoload file is absent or unsafe"
[ "$(stat -c '%a' "${rescue_nft_bridge_autoload_path}")" = 644 ] || \
	die "rootfs nft bridge modules.d autoload mode is not 644"
rescue_nft_bridge_expected_autoload="${tmp_dir}/nft-bridge.modules.expected"
printf '%s\n' "${RESCUE_NFT_BRIDGE_AUTOLOADS[@]}" > \
	"${rescue_nft_bridge_expected_autoload}"
cmp -s "${rescue_nft_bridge_expected_autoload}" \
	"${rescue_nft_bridge_autoload_path}" || \
	die "rootfs nft bridge modules.d autoload bytes or order differ"
rescue_nft_bridge_autoload_line=0
for rescue_nft_bridge_autoload in "${RESCUE_NFT_BRIDGE_AUTOLOADS[@]}"; do
	rescue_nft_bridge_autoload_line=$(( rescue_nft_bridge_autoload_line + 1 ))
	mapfile -t rescue_nft_bridge_autoload_occurrences < <(
		find "${rootfs_dir}/etc/modules.d" -type f -exec \
			awk -v module="${rescue_nft_bridge_autoload}" \
				'$1 == module { print FILENAME ":" FNR }' {} +
	)
	[ "${#rescue_nft_bridge_autoload_occurrences[@]}" -eq 1 ] && \
		[ "${rescue_nft_bridge_autoload_occurrences[0]}" = \
			"${rescue_nft_bridge_autoload_path}:${rescue_nft_bridge_autoload_line}" ] || \
		die "rootfs ${rescue_nft_bridge_autoload} autoload is missing, duplicated, or misplaced"
done

crlf_executables="${tmp_dir}/crlf-executables.txt"
: > "${crlf_executables}"
while IFS= read -r -d '' executable; do
	if [ "$(head -c 2 "${executable}" 2>/dev/null)" = '#!' ] && \
		LC_ALL=C grep -Fq $'\r' "${executable}"; then
		printf '%s\n' "${executable#"${rootfs_dir}/"}" >> "${crlf_executables}"
	fi
done < <(find "${rootfs_dir}" -type f -perm /111 -print0)
if [ -s "${crlf_executables}" ]; then
	cat "${crlf_executables}" >&2
	die "rootfs contains executable scripts with Windows CRLF line endings"
fi

writable_files="${tmp_dir}/group-or-world-writable-files.txt"
find "${rootfs_dir}" -type f -perm /022 -printf '%m %P\n' | \
	LC_ALL=C sort > "${writable_files}"
if [ -s "${writable_files}" ]; then
	cat "${writable_files}" >&2
	die "rootfs contains group- or world-writable regular files"
fi

overlay_list="${tmp_dir}/overlay.list0"
overlay_sorted="${tmp_dir}/overlay.sorted0"
find "${STAGED_OVERLAY}" -mindepth 1 -print0 > "${overlay_list}" || \
	die "could not enumerate the staged overlay"
LC_ALL=C sort -z "${overlay_list}" > "${overlay_sorted}" || \
	die "could not sort the staged overlay"
mapfile -d '' -t overlay_paths < "${overlay_sorted}"
overlay_entries=0
for source_path in "${overlay_paths[@]}"; do
	relative_path="${source_path#"${STAGED_OVERLAY}/"}"
	built_path="${rootfs_dir}/${relative_path}"
	if [ -L "${source_path}" ]; then
		[ -L "${built_path}" ] || die "overlay symlink missing from rootfs: ${relative_path}"
		[ "$(readlink "${source_path}")" = "$(readlink "${built_path}")" ] || \
			die "overlay symlink target changed: ${relative_path}"
		[ "$(stat -c '%a' "${source_path}")" = "$(stat -c '%a' "${built_path}")" ] || \
			die "overlay symlink mode changed in rootfs: ${relative_path}"
	elif [ -f "${source_path}" ]; then
		[ -f "${built_path}" ] && [ ! -L "${built_path}" ] || \
			die "overlay file missing from rootfs: ${relative_path}"
		if LC_ALL=C grep -Iq . "${source_path}" && \
			LC_ALL=C grep -Fq $'\r' "${source_path}"; then
			die "text file in staged overlay contains Windows CRLF: ${relative_path}"
		fi
		if [ "${relative_path}" = "etc/shadow" ]; then
			expected_shadow="${tmp_dir}/expected-shadow"
			{
				cat "${source_path}"
				printf '%s\n' \
					'ntp:x:0:0:99999:7:::' \
					'dnsmasq:x:0:0:99999:7:::' \
					'lldp:x:0:0:99999:7:::' \
					'logd:x:0:0:99999:7:::' \
					'ubus:x:0:0:99999:7:::'
			} > "${expected_shadow}"
			cmp -s "${expected_shadow}" "${built_path}" || \
				die "root password or final shadow account set changed"
		else
			cmp -s "${source_path}" "${built_path}" || \
				die "overlay file content changed in rootfs: ${relative_path}"
		fi
		[ "$(stat -c '%a' "${source_path}")" = "$(stat -c '%a' "${built_path}")" ] || \
			die "overlay file mode changed in rootfs: ${relative_path}"
	elif [ -d "${source_path}" ]; then
		[ -d "${built_path}" ] && [ ! -L "${built_path}" ] || \
			die "overlay directory missing from rootfs: ${relative_path}"
		[ "$(stat -c '%a' "${source_path}")" = "$(stat -c '%a' "${built_path}")" ] || \
			die "overlay directory mode changed in rootfs: ${relative_path}"
	else
		die "unsupported staged overlay entry: ${relative_path}"
	fi
	overlay_entries=$(( overlay_entries + 1 ))
done
[ "${overlay_entries}" -gt 0 ] || die "staged overlay was empty"

require_mode() {
	local relative_path="$1"
	local expected_mode="$2"
	local path="${rootfs_dir}/${relative_path}"
	[ -f "${path}" ] && [ ! -L "${path}" ] || die "required file absent: ${relative_path}"
	[ "$(stat -c '%a' "${path}")" = "${expected_mode}" ] || \
		die "required mode ${expected_mode} not set on ${relative_path}"
}

require_symlink() {
	local relative_path="$1"
	local expected_target="$2"
	local path="${rootfs_dir}/${relative_path}"
	[ -L "${path}" ] || die "required symlink absent: ${relative_path}"
	[ "$(readlink -- "${path}")" = "${expected_target}" ] || \
		die "required symlink target changed: ${relative_path}"
}

require_mode www/cgi-bin/dashluci 755
require_mode www/cgi-bin/dashlogin 755
require_mode www/cgi-bin/dashlogout 755
require_mode www/cgi-bin/dashapi2 755
require_mode www/cgi-bin/dashctl 755
require_mode lib/preinit/71_cr6608_initramfs_detach_ubi 755
require_mode etc/rc.d/S97cr6608-ul-muru-reconcile 755
require_mode usr/share/ucode/luci/template/themes/argon/sysauth.ut 644
require_mode usr/lib/uhttpd_ucode.so 755
require_mode etc/uhttpd/security-headers.json 644
require_mode etc/init.d/uhttpd 755
require_mode usr/libexec/cr6608-session-auth 755
require_mode usr/libexec/cr6608-luci-acl-names.uc 755
require_mode usr/libexec/cr6608-dashboard-cache-state 755
require_mode usr/libexec/cr6608-mac-identity-lib 755
for removed_dashboard_prewarm_path in \
	usr/sbin/cr6608-dashboard-prewarm \
	etc/init.d/cr6608-dashboard-cache \
	etc/rc.d/S99cr6608-dashboard-cache \
	etc/rc.d/K99cr6608-dashboard-cache; do
	[ ! -e "${rootfs_dir}/${removed_dashboard_prewarm_path}" ] && \
		[ ! -L "${rootfs_dir}/${removed_dashboard_prewarm_path}" ] || \
		die "removed dashboard prewarm path remains in rootfs: ${removed_dashboard_prewarm_path}"
done
require_mode usr/libexec/cr6608-vlan-lib 755
require_mode usr/libexec/cr6608-rescue-firewall-include 755
require_mode usr/libexec/cr6608-private-runtime 644
require_mode usr/sbin/cr6608-safe-apply 755
require_mode usr/sbin/cr6608-safe-wifi-reload 755
require_mode usr/sbin/cr6608-quicksettings-apply 755
require_mode usr/sbin/smartap-qos-apply 755
require_mode usr/bin/cr6608-txpower-verify 755
require_mode usr/bin/cr6608-country-power-scan 755
require_mode usr/bin/cr6608-wifi-full-verify 755
require_mode usr/sbin/cr6608-security-apply 755
require_mode usr/sbin/cr6608-session-reaper 755
require_mode usr/sbin/cr6608-management-guard 755
require_mode usr/sbin/cr6608-rescue-guard 755
require_mode usr/sbin/cr6608-mac-verify 755
require_mode usr/sbin/cr6608-ipv4-only 755
require_mode etc/init.d/cr6608-ipv4-only 755
require_mode etc/hotplug.d/net/90-cr6608-ipv4-only 755
require_mode usr/sbin/cr6608-retail-provision 755
require_mode usr/sbin/cr6608-retail-audit 755
require_mode usr/sbin/cr6608-retail-radio-audit 755
require_mode usr/bin/openssl 755
require_mode bin/uclient-fetch 755
require_mode usr/sbin/cr6608-eeprom-power 755
require_mode usr/sbin/smartap-bootstrap 755
require_mode usr/sbin/cr6608-neighbor-service 755
require_mode usr/sbin/cr6608-mndp-advertise 755
require_mode usr/sbin/lldpd 755
require_mode usr/sbin/lldpcli 755
require_symlink usr/sbin/lldpctl lldpcli
require_mode etc/init.d/lldpd 755
require_mode etc/config/lldpd 600
require_mode usr/sbin/cr6608-wifi-sentinel 755
require_mode usr/sbin/cr6608-wifi-schedule 755
require_mode usr/sbin/cr6608-dashboard-invalidate 755
require_mode usr/sbin/smartap-autochannel 755
require_mode etc/uci-defaults/99-cr6608-smartap-only 755
require_mode etc/hotplug.d/iface/99-cr6608-dashboard-cache 755
require_mode etc/hotplug.d/net/99-cr6608-dashboard-cache 755
require_mode etc/init.d/cr6608-safe-apply 755
require_mode etc/init.d/cr6608-quicksettings 755

mac_identity_lib="${rootfs_dir}/usr/libexec/cr6608-mac-identity-lib"
mac_identity_verify="${rootfs_dir}/usr/sbin/cr6608-mac-verify"
grep -Fq 'mtd_get_mac_binary Factory "$cmf_offset"' "${mac_identity_lib}" ||
	die "MAC identity verifier does not read the immutable Factory partition"
for factory_offset in 4 10 262132 262138; do
	grep -Fq "cr6608_mac_factory_read ${factory_offset}" "${mac_identity_lib}" ||
		die "MAC identity verifier lacks Factory offset ${factory_offset}"
done
grep -Fq 'for cmd_ifname in eth0 br-lan lan1 lan2 lan3' "${mac_identity_lib}" ||
	die "MAC identity verifier lost the CR6608 DSA sharing policy"
grep -Fq '"shared_by_design":true' "${mac_identity_verify}" ||
	die "MAC identity verifier does not publish the DSA inheritance result"
! grep -Eq 'd4:35:38:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}' \
	"${mac_identity_lib}" "${mac_identity_verify}" ||
	die "a unit-specific MAC address was baked into the rootfs verifier"
grep -Fq '"mac_identity":%s' "${rootfs_dir}/www/cgi-bin/dashapi2" ||
	die "Smart AP API omits live Factory identity verification"
grep -Fq 'renderFactoryIdentity(data)' "${rootfs_dir}/www/dashboard.js" ||
	die "Smart AP UI omits the Factory identity card"
grep -Fq 'for cia_path in "$IPV6_CONF_ROOT"/*/disable_ipv6' \
	"${rootfs_dir}/usr/sbin/cr6608-ipv4-only" ||
	die "IPv4-only runtime guard does not cover dynamically-created interfaces"
grep -Fq 'kernel.kptr_restrict=2' "${rootfs_dir}/etc/sysctl.d/99-smartap-perf.conf" ||
	die "kernel pointer hardening is absent"
require_mode etc/init.d/smartap-qos 755
require_mode etc/init.d/cr6608-rescue-guard 755
require_mode etc/init.d/firewall 755
require_mode etc/hotplug.d/iface/99-cr6608-rescue-guard 755
require_mode etc/hotplug.d/net/99-cr6608-rescue-guard 755
require_mode etc/init.d/cr6608-security 755
require_mode etc/hotplug.d/iface/98-cr6608-security-runtime 755
require_mode etc/init.d/cr6608-neighbor 755
require_mode etc/init.d/cr6608-management-guard 755
require_mode etc/uci-defaults/97-cr6608-security 755
require_mode etc/uci-defaults/98-cr6608-safe-apply 755
require_mode etc/uci-defaults/96-cr6608-wlanrescue-isolation 755
require_mode etc/uci-defaults/99-cr6608-neighbor-enable 755
require_mode etc/uci-defaults/99-cr6608-runtime-services 755
require_mode etc/uci-defaults/97-smartap-bootstrap 755
require_mode etc/uci-defaults/96-cr6608-ssh-port 755
require_mode etc/uci-defaults/98-cr6608-https-capability 755
require_mode etc/uci-defaults/99-cr6608-root-pass 755
require_mode etc/uci-defaults/99-cr6608-secure-console 755
require_mode etc/config/cr6608quick 600
require_mode etc/config/system 600
require_mode www/cgi-bin/cr6608-quick-apply 755
require_mode www/cgi-bin/cr6608-quick-confirm 755
require_mode www/luci-static/resources/view/cr6608/quicksettings.js 644
require_mode usr/share/luci/menu.d/luci-app-cr6608-quicksettings.json 644
require_mode usr/share/luci/menu.d/zz-cr6608-logout.json 644
require_mode usr/share/ucode/luci/controller/cr6608/logout.uc 644
require_mode usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json 644
require_mode usr/sbin/smartap-time-anchor 755
[ -L "${rootfs_dir}/bin/stat" ] || die "runtime stat command link is absent from rootfs"
[ "$(readlink "${rootfs_dir}/bin/stat")" = /usr/libexec/stat-coreutils ] || \
	die "runtime stat command points to an unexpected implementation"
require_mode usr/libexec/stat-coreutils 755
smartap_qos_apply="${rootfs_dir}/usr/sbin/smartap-qos-apply"
grep -Fq 'exec 9>"$LOCK_FILE"' "${smartap_qos_apply}" ||
	die "Smart AP QoS transactions do not pin a private lock descriptor"
grep -Fq '"$FLOCK_BIN" -xn 9' "${smartap_qos_apply}" ||
	die "Smart AP QoS transactions lack a BusyBox-compatible nonblocking lock"
grep -Fq '"$FLOCK_BIN" -u 9' "${smartap_qos_apply}" ||
	die "Smart AP QoS transactions do not explicitly release their descriptor lock"
! grep -Eq '"\$FLOCK_BIN"[[:space:]].*(-w|-E)([[:space:]]|$)' "${smartap_qos_apply}" ||
	die "Smart AP QoS transactions use util-linux-only flock options"
grep -Fq 'valid_unicast_mac()' "${smartap_qos_apply}" &&
	grep -Fq 'ether saddr $src_mac counter drop' "${smartap_qos_apply}" &&
	grep -Fq 'ether daddr $src_mac counter drop' "${smartap_qos_apply}" ||
	die "Smart AP QoS lacks guarded bridged-client MAC blocking"
python3 - "${rootfs_dir}/lib/firmware/regulatory.db" <<'PY' || \
	die "regulatory.db does not contain the required country set"
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
if len(data) < 12 or data[:4] != b"RGDB":
    raise SystemExit(1)
codes = []
for offset in range(8, len(data) - 3, 4):
    code = data[offset:offset + 2]
    if not all(chr(ch).isdigit() or 65 <= ch <= 90 for ch in code):
        break
    codes.append(code.decode("ascii"))
required = {"PA", "US", "YE", "SA", "AE", "EG", "DE", "FR", "GB", "CN", "JP"}
if len(codes) < 100 or not required.issubset(codes):
    raise SystemExit(1)
PY
require_mode etc/init.d/smartap-time-anchor 755
require_mode etc/uci-defaults/00-smartap-time-anchor 755
require_mode etc/smartap-time-anchor 644
require_mode etc/smartap-build-time 644
require_mode www/dashboard.js 644
require_mode www/smartap-zero-retention.js 644
require_mode www/index.html 644
require_mode etc/smartap-version 644
require_mode etc/board.d/05_fw_defaults 644
require_mode etc/modules.d/mt7915e 644
require_mode etc/inittab 644
require_mode etc/shadow 600
require_mode lib/upgrade/keep.d/cr6608-retail 644
require_mode etc/config/openssl 644
require_mode etc/crontabs/root 600
require_mode etc/config/wireless 600
require_mode etc/config/dropbear 600
if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	require_mode etc/cr6608-retail-commissioning-ram 400
	require_mode etc/dropbear/authorized_keys 600
	commissioning_marker="${rootfs_dir}/etc/cr6608-retail-commissioning-ram"
	commissioning_key="${rootfs_dir}/etc/dropbear/authorized_keys"
	[ "$(wc -l < "${commissioning_marker}" | tr -d '[:space:]')" = 6 ] ||
		die 'commissioning marker has an unexpected line count'
	for commissioning_record in \
		'profile=retail-commissioning-ram-v1' \
		'sale_ready=NO' \
		'boot_policy=ram-only' \
		'password_auth=disabled'; do
		grep -Fqx "${commissioning_record}" "${commissioning_marker}" ||
			die "commissioning marker lacks: ${commissioning_record}"
	done
	commissioning_key_listing="$(ssh-keygen -E sha256 -lf "${commissioning_key}" 2>/dev/null)" ||
		die 'commissioning authorized key is invalid'
	case "${commissioning_key_listing}" in
		'256 SHA256:'*' (ED25519)') ;;
		*) die 'commissioning access is not exactly one ED25519 key' ;;
	esac
	commissioning_key_fingerprint="$(printf '%s\n' "${commissioning_key_listing}" | awk '{print $2}')"
	grep -Fqx "factory_key_fingerprint=${commissioning_key_fingerprint}" \
		"${commissioning_marker}" ||
		die 'commissioning marker is not bound to its authorized key'
	commissioning_key_sha256="$(sha256sum "${commissioning_key}" | awk '{print $1}')"
	grep -Fqx "factory_key_sha256=${commissioning_key_sha256}" \
		"${commissioning_marker}" ||
		die 'commissioning marker SHA-256 is not bound to its authorized key bytes'
	grep -Eq "^[[:space:]]*option PasswordAuth 'off'$" \
		"${rootfs_dir}/etc/config/dropbear" ||
		die 'commissioning password authentication is enabled'
	grep -Eq "^[[:space:]]*option RootPasswordAuth 'off'$" \
		"${rootfs_dir}/etc/config/dropbear" ||
		die 'commissioning root password authentication is enabled'
else
	[ ! -e "${rootfs_dir}/etc/cr6608-retail-commissioning-ram" ] &&
		[ ! -L "${rootfs_dir}/etc/cr6608-retail-commissioning-ram" ] ||
		die 'non-commissioning image contains a commissioning marker'
	[ ! -e "${rootfs_dir}/etc/dropbear/authorized_keys" ] &&
		[ ! -L "${rootfs_dir}/etc/dropbear/authorized_keys" ] ||
		die 'non-commissioning image contains a factory authorized key'
fi
require_mode sbin/sysupgrade 755
require_mode usr/sbin/uhttpd 755
# OpenWrt packages libustream-ssl.so with INSTALL_DATA (0644).  The shared
# object does not need an executable bit: the dynamic loader maps it directly.
# Requiring 0755 here would reject the stock, working TLS provider.
require_mode lib/libustream-ssl.so 644
require_mode lib/netifd/wireless/mac80211.sh 755
require_mode etc/apk/keys/public-key.pem 644
require_mode www/luci-static/resources/ui.js 644
require_mode www/luci-static/resources/view/network/wireless.js 644
require_mode usr/share/ucode/luci/controller/admin/uci.uc 644
require_mode usr/sbin/cr6608-ax-verify 755
require_mode usr/sbin/cr6608-ul-muru-verify 755
require_mode usr/sbin/cr6608-ul-muru-airtest 755
require_mode usr/sbin/cr6608-ul-muru-guard 755
require_mode usr/sbin/ubidetach 755
require_mode etc/init.d/cr6608-ul-muru-guard 755
require_mode etc/uci-defaults/98-cr6608-ul-muru-guard 755
require_mode usr/sbin/cr6608-easymesh-verify 755
require_mode usr/sbin/cr6608-port-readiness 755
require_mode usr/libexec/cr6608-port-readiness-lib 755
require_mode usr/share/cr6608/ax-feature-support 644
require_mode etc/init.d/prplmesh 755
require_mode etc/uci-defaults/95-prplmesh-cr6608 755
require_mode usr/sbin/cr6608-prplmesh-sync 755
require_mode etc/uci-defaults/96-cr6608-sqm-dsa-defaults 755
require_mode etc/config/prplmesh 600
require_mode usr/bin/getopt 755
require_mode opt/prplmesh/bin/ieee1905_transport 755
require_mode opt/prplmesh/bin/beerocks_controller 755
require_mode opt/prplmesh/bin/beerocks_agent 755
require_mode opt/prplmesh/bin/beerocks_fronthaul 755
require_mode opt/prplmesh/bin/beerocks_cli 755
require_mode opt/prplmesh/share/prplmesh_platform_db 644
require_mode opt/prplmesh/scripts/prplmesh_utils.sh 755
require_mode opt/prplmesh/config/beerocks_agent.conf 644
require_mode opt/prplmesh/config/beerocks_controller.conf 644

grep -Fqx '[ -r /etc/fw_env.config ] || exit 0' \
	"${rootfs_dir}/etc/board.d/05_fw_defaults" || \
	die "early uboot environment import is not guarded"

prplmesh_config="${rootfs_dir}/etc/config/prplmesh"
prplmesh_defaults="${rootfs_dir}/etc/uci-defaults/95-prplmesh-cr6608"
prplmesh_sync="${rootfs_dir}/usr/sbin/cr6608-prplmesh-sync"
[ "$(sha256sum "${prplmesh_sync}" | awk '{print $1}')" = \
	'988339adb858f6efbcf58e79ed1180150cd463837226b44ce785e6eaf103503a' ] || \
	die 'prplMesh credential synchronizer differs from the audited fail-closed implementation'
grep -Fq 'gates_closed || fail easymesh_gate_open' "${prplmesh_sync}" && \
	grep -Fq 'gates_closed || fail easymesh_gate_changed' "${prplmesh_sync}" && \
	grep -Fq '"$UCI_BIN" -q batch' "${prplmesh_sync}" && \
	! grep -Fq 'commit prplmesh' "${prplmesh_sync}" || \
	die 'prplMesh credential synchronizer can bypass its caller transaction or safety gates'
grep -Fq 'UCI_PACKAGES="network wireless dhcp firewall cr6608quick smartap usteer prplmesh"' \
	"${rootfs_dir}/usr/sbin/cr6608-quicksettings-apply" && \
	grep -Fq '"$PRPLMESH_SYNC_BIN" --stage "$ap24" "$ap5"' \
		"${rootfs_dir}/usr/sbin/cr6608-retail-provision" && \
	grep -Fq '"$UCI_BIN" commit system && "$UCI_BIN" commit prplmesh' \
		"${rootfs_dir}/usr/sbin/cr6608-retail-provision" || \
	die 'Retail or Quick Settings image omits transactional prplMesh credential synchronization'
for prplmesh_gate in enable operational active_control_confirmed; do
	grep -Eq "^[[:space:]]*option ${prplmesh_gate} '0'$" \
		"${prplmesh_config}" || \
		die "prplMesh image default leaves ${prplmesh_gate} open"
	grep -Fq '"$UCI_BIN" -q set "prplmesh.config.'"${prplmesh_gate}"'=0"' \
		"${prplmesh_defaults}" || \
		die "prplMesh preserved-overlay migration does not close ${prplmesh_gate}"
done
for prplmesh_agent_policy in wired_backhaul require_encrypted_fronthaul; do
	grep -Eq "^[[:space:]]*option ${prplmesh_agent_policy} '1'$" \
		"${prplmesh_config}" || \
		die "prplMesh image default weakens Agent policy: ${prplmesh_agent_policy}"
	grep -Fq 'set prplmesh.config.'"${prplmesh_agent_policy}"'='"'1'" \
		"${prplmesh_defaults}" || \
		die "prplMesh migration does not force Agent policy: ${prplmesh_agent_policy}"
done
prplmesh_gate_commit_line="$(grep -nF '"$UCI_BIN" -q commit prplmesh' \
	"${prplmesh_defaults}" | sed -n '1s/:.*//p')"
prplmesh_wireless_sync_line="$(grep -nF 'wireless_ap_section()' \
	"${prplmesh_defaults}" | sed -n '1s/:.*//p')"
[ -n "${prplmesh_gate_commit_line}" ] && \
	[ -n "${prplmesh_wireless_sync_line}" ] && \
[ "${prplmesh_gate_commit_line}" -lt "${prplmesh_wireless_sync_line}" ] || \
	die 'prplMesh preserved-overlay safety gates are not committed before wireless sync'

prplmesh_init="${rootfs_dir}/etc/init.d/prplmesh"
prplmesh_start_block="$(sed -n '/^start_service() {$/,/^}$/p' "${prplmesh_init}")"
prplmesh_agent_gate_line="$(printf '%s\n' "${prplmesh_start_block}" | \
	grep -nF 'agent_runtime_policy_valid "$wired_backhaul" "$require_encrypted"' | \
	head -n 1 | cut -d: -f1)"
prplmesh_prepare_line="$(printf '%s\n' "${prplmesh_start_block}" | \
	grep -nF 'prepare_runtime_dirs' | head -n 1 | cut -d: -f1)"
grep -Fq 'agent_runtime_policy_valid()' "${prplmesh_init}" && \
	[ -n "${prplmesh_agent_gate_line}" ] && [ -n "${prplmesh_prepare_line}" ] && \
	[ "${prplmesh_agent_gate_line}" -lt "${prplmesh_prepare_line}" ] || \
	die 'prplMesh Agent safety policy is not enforced before runtime preparation'
easymesh_verify="${rootfs_dir}/usr/sbin/cr6608-easymesh-verify"
easymesh_policy_line="$(grep -nF '! agent_runtime_policy_valid "$wired_backhaul" "$require_encrypted"' \
	"${easymesh_verify}" | head -n 1 | cut -d: -f1)"
easymesh_wait_line="$(grep -nE '^[[:space:]]*sleep[[:space:]]+[0-9]+' \
	"${easymesh_verify}" | head -n 1 | cut -d: -f1)"
grep -Fq 'RESULT_EASYMESH_SOFTWARE_CONTRACT=INVALID_AGENT_SAFETY_POLICY' \
	"${easymesh_verify}" && \
	grep -Fq 'RESULT_EASYMESH_PHYSICAL_INTEROPERABILITY=NOT_PROVEN_EXTERNAL_CONTROLLER_AGENT_AND_RF_TEST_REQUIRED' \
		"${easymesh_verify}" && \
	[ -n "${easymesh_policy_line}" ] && [ -n "${easymesh_wait_line}" ] && \
	[ "${easymesh_policy_line}" -lt "${easymesh_wait_line}" ] || \
	die 'EasyMesh verifier omits the Agent safety gate or overstates physical interoperability'

for prplmesh_log_config in \
	opt/prplmesh/config/beerocks_agent.conf \
	opt/prplmesh/config/beerocks_controller.conf; do
	grep -Fqx 'log_global_levels=error,info,warning,fatal' \
		"${rootfs_dir}/${prplmesh_log_config}" || \
		die "${prplmesh_log_config} enables an unbounded production log level"
	grep -Fqx 'log_global_syslog_levels=error,warning,fatal' \
		"${rootfs_dir}/${prplmesh_log_config}" || \
		die "${prplmesh_log_config} has an unexpected syslog level set"
	grep -Fqx 'log_global_size=262144' \
		"${rootfs_dir}/${prplmesh_log_config}" || \
		die "${prplmesh_log_config} lacks the bounded rollover size"
done
grep -Fqx 'monitor_polling_rate_msec=1000' \
	"${rootfs_dir}/opt/prplmesh/config/beerocks_agent.conf" || \
	die 'prplMesh monitor polling remains at the high-frequency upstream default'
grep -Fq '[ "$#" -eq 1 ] && [ "$1" = "roll_logs" ]' \
	"${rootfs_dir}/opt/prplmesh/scripts/prplmesh_utils.sh" || \
	die 'prplMesh emergency log-roll fast path is missing'

LC_ALL=C grep -aFq 'Cache-Control: no-store, no-cache, must-revalidate' \
	"${rootfs_dir}/usr/sbin/uhttpd" || \
	die "built uhttpd lacks the all-static no-store response path"
LC_ALL=C grep -aFq 'Strict-Transport-Security: max-age=31536000' \
	"${rootfs_dir}/usr/sbin/uhttpd" || \
	die "built uhttpd lacks the TLS-only HSTS response path"

muru_guard="${rootfs_dir}/usr/sbin/cr6608-ul-muru-guard"
for muru_guard_marker in \
	'matching_signatures()' \
	'signature_snapshot()' \
	'signatures_are_pure_suffix()' \
	'signature_baseline_lines="$(matching_signatures)"' \
	'signature_baseline_snapshot="$(signature_snapshot "$signature_baseline_lines")"' \
	'signature_baseline_fingerprint="${signature_baseline_snapshot#*:}"' \
	'current_signature_snapshot="$(signature_snapshot "$current_signature_lines")"' \
	'current_signature_fingerprint="${current_signature_snapshot#*:}"' \
	'[ "$current_signatures" -gt "$signature_baseline_count" ]' \
	'[ "$current_signature_fingerprint" != "$signature_baseline_fingerprint" ]' \
	'! signatures_are_pure_suffix "$signature_baseline_lines" "$current_signature_lines"' \
	'runtime_disable "mt7915-hang-signature-'; do
	grep -Fq "${muru_guard_marker}" "${muru_guard}" || \
		die "MURU guard lacks lossless log-rotation fault handling: ${muru_guard_marker}"
done
muru_airtest="${rootfs_dir}/usr/sbin/cr6608-ul-muru-airtest"
for muru_airtest_marker in \
	'qualification_gate_armed()' \
	'RESULT_UL_MURU_AIRTEST=ERROR_QUALIFICATION_GATE_NOT_ARMED_BEFORE' \
	'RESULT_UL_MURU_AIRTEST=ERROR_QUALIFICATION_GATE_NOT_ARMED_AFTER' \
	'full_ul_mumimo_station_count' \
	'EVIDENCE_SCOPE=AGGREGATE_SAME_RADIO_COUNTER_CORRELATION_NOT_CLIENT_ATTRIBUTION' \
	'RESULT_UL_MURU_AIRTEST=BOTH_RADIO_COUNTERS_CORRELATED_NOT_CLIENT_ATTRIBUTED'; do
	grep -Fq "${muru_airtest_marker}" "${muru_airtest}" || \
		die "MURU airtest overstates or omits its qualification boundary: ${muru_airtest_marker}"
done

ax_support_manifest="${rootfs_dir}/usr/share/cr6608/ax-feature-support"
for ax_support_record in \
	'format=1' \
	'board=xiaomi,mi-router-cr6608' \
	'wifi_stack=openwrt-upstream-mac80211-mt76-hostapd' \
	'driver=mt7915e' \
	'beamforming_su=enabled' \
	'beamforming_dl_mu_mimo=enabled' \
	'ofdma=dl-enabled-plus-mediatek-25.12-muru-bitmap-qualification-path' \
	'ofdma_dl=enabled' \
	'ofdma_ul=mask-bit-1-runtime-guarded-ram-or-forced-lab' \
	'mu_mimo_dl=enabled' \
	'mu_mimo_ul=mask-bit-3-runtime-guarded-ram-or-forced-lab' \
	'ul_muru_policy=mediatek-25.12-mu-onoff-sta-rec-port' \
	'ul_muru_default=stable-and-retail-mask-0' \
	'ul_muru_qualification=ram-boot-only-mask-15' \
	'ul_muru_forced_lab=persistent-mask-15-nonsale' \
	'ul_muru_mcu_telemetry=attempted-response-ok-failed-timeout-not-apply-or-ota-proof' \
	'ul_muru_fault_policy=kernel-attributed-latch-watchdog-or-sta-rec-plus-unattributed-disarm' \
	'ul_muru_rearm_policy=one-way-ceiling-restored-after-verified-reset-max-3-unattributed-strikes' \
	'ul_muru_dl_floor=upstream-dl-ofdma-and-dl-mumimo-retained-through-fault' \
	'ul_muru_global_mcu_commands=not-used' \
	'dfs=enabled' \
	'background_cac=enabled-driver-runtime-capability-gated' \
	'easymesh=prplmesh-controller-agent-runtime-gated' \
	'mesh_80211s=supported-by-wpad-openssl' \
	'runtime_gate=immutable-profile-plus-read-only-module-mask-plus-kernel-fault-latch-plus-muru-debugfs' \
	'ota_evidence=per-peer-he-tb-ppdu-wcid-attribution-plus-shared-ppdu-timestamp-grouping-not-an-rf-or-regulatory-measurement'; do
	grep -Fqx "${ax_support_record}" "${ax_support_manifest}" || \
		die "rootfs AX support manifest lacks ${ax_support_record}"
done

cmp -s "${APK_SIGNING_PUB}" \
	"${rootfs_dir}/etc/apk/keys/public-key.pem" || \
	die "rootfs APK public key differs from public-key.pem"
[ ! -e "${rootfs_dir}/key-build" ] && [ ! -L "${rootfs_dir}/key-build" ] || \
	die "private build key leaked into rootfs"
[ ! -e "${rootfs_dir}/private-key.pem" ] && [ ! -L "${rootfs_dir}/private-key.pem" ] || \
	die "private APK signing key leaked into rootfs"
grep -Eq "request\\.request\\(L\\.url\\('admin/uci',[[:space:]]*checked[[:space:]]*\\?[[:space:]]*'apply_rollback'[[:space:]]*:[[:space:]]*'apply_unchecked'\\)" \
	"${rootfs_dir}/www/luci-static/resources/ui.js" || \
	die "rootfs LuCI UI does not use checked apply"
grep -Fq 'const token = uci_apply(true);' \
	"${rootfs_dir}/usr/share/ucode/luci/controller/admin/uci.uc" || \
	die "rootfs LuCI controller does not arm rollback"
grep -Fq "uci_confirm(http.formvalue('token'));" \
	"${rootfs_dir}/usr/share/ucode/luci/controller/admin/uci.uc" || \
	die "rootfs LuCI controller does not confirm rollback tokens"
luci_wireless_view="${rootfs_dir}/www/luci-static/resources/view/network/wireless.js"
check_javascript_syntax "${luci_wireless_view}" || \
	die "rootfs LuCI wireless JavaScript syntax failed"
grep -Eq 'for[[:space:]]*\([[:space:]]*let[[:space:]]+dbm[[:space:]]*=[[:space:]]*1;[[:space:]]*dbm[[:space:]]*<=[[:space:]]*38;[[:space:]]*dbm\+\+[[:space:]]*\)' \
	"${luci_wireless_view}" || \
	die "rootfs LuCI wireless view does not expose the complete 1-38 dBm list"
grep -Eq 'const[[:space:]]+key[[:space:]]*=[[:space:]]*String\(dbm\);[[:space:]]*this\.value\(key,[[:space:]]*`\$\{key\}[[:space:]]+dBm`\);' \
	"${luci_wireless_view}" || \
	die "rootfs LuCI wireless view does not render every 1-38 dBm list entry"
! grep -Fq 'configured request, outside current driver list' \
	"${luci_wireless_view}" || \
	die "rootfs LuCI wireless view still contains the removed 38 dBm suffix"
grep -Eq 'this\.powerval[[:space:]]*=[[:space:]]*this\.wifiNetwork[[:space:]]*\?[[:space:]]*this\.wifiNetwork\.getTXPower\(\)[[:space:]]*:[[:space:]]*null' \
	"${luci_wireless_view}" || \
	die "rootfs LuCI Current power is not sourced from the live wireless driver"
if grep -Eq 'powerval[[:space:]]*=[[:space:]]*38|Current power.*38[[:space:]]*dBm' \
	"${luci_wireless_view}"; then
	die "rootfs LuCI Current power is hardcoded to 38 dBm"
fi
grep -Eq "uci\\.set\\('wireless',[[:space:]]*radio\\['\\.name'\\],[[:space:]]*'country',[[:space:]]*value\\)[[:space:]]*;?" \
	"${luci_wireless_view}" || \
	die "rootfs LuCI wireless view does not synchronize the shared regulatory country"
grep -Eq "uci\\.unset\\('wireless',[[:space:]]*radio\\['\\.name'\\],[[:space:]]*'country'\\)[[:space:]]*;?" \
	"${luci_wireless_view}" || \
	die "rootfs LuCI wireless view does not synchronize shared-country removal"

printf "\nconfig provider 'legacy'\n\toption enabled '1'\n" | \
	cmp -s - "${rootfs_dir}/etc/config/openssl" || \
	die "OpenSSL legacy provider config is missing or duplicated"

printf '%s\n' "${EXPECTED_MODULE_LINE}" | \
	cmp -s - "${rootfs_dir}/etc/modules.d/mt7915e" ||
	die "${BUILD_PROFILE} module policy is not exact"
case "${BUILD_PROFILE}" in
	lab)
		printf '%s\n' \
			'profile=lab-operator-v1' \
			'sale_ready=NO' \
			'radio_policy=lab-operator-38dbm-ul-muru' ;;
	retail)
		printf '%s\n' \
			'profile=retail-v1' \
			'sale_ready=NO' \
			'radio_policy=retail-disabled' ;;
	ul-lab)
		printf '%s\n' \
			'profile=ul-muru-ram-v1' \
			'sale_ready=NO' \
			'radio_policy=ul-muru-ram-qualification' ;;
	ul-forced-lab)
		printf '%s\n' \
			'profile=ul-muru-forced-lab-v1' \
			'sale_ready=NO' \
			'radio_policy=ul-muru-persistent-mask15-38dbm-lab' ;;
esac | cmp -s - "${rootfs_dir}/etc/cr6608-artifact-profile" ||
	die "immutable ${BUILD_PROFILE} artifact profile is missing or unsafe"
[ "$(grep -Ec "^[[:space:]]*option Port[[:space:]]+'2003'$" \
	"${rootfs_dir}/etc/config/dropbear")" -eq 1 ] || \
	die "rootfs SSH port is not pinned to 2003"
ssh_port_migration="${rootfs_dir}/etc/uci-defaults/96-cr6608-ssh-port"
grep -Fq 'uci -q set "dropbear.${section}.Port=2003"' "${ssh_port_migration}" ||
	die "rootfs lacks preserved-config SSH port migration"
grep -Fq 'uci -q commit dropbear' "${ssh_port_migration}" ||
	die "rootfs SSH port migration does not commit"
if grep -Eq 'Port=22|Port[[:space:]]+22|listen.*:22' "${ssh_port_migration}"; then
	die "rootfs SSH migration reintroduces port 22"
fi
wireless_config="${rootfs_dir}/etc/config/wireless"
radio0_config="$(
	sed -n "/^config wifi-device 'radio0'$/,/^config /p" "${wireless_config}"
)"
radio1_config="$(
	sed -n "/^config wifi-device 'radio1'$/,/^config /p" "${wireless_config}"
)"
printf '%s\n' "${radio1_config}" | grep -Fqx "	option channel '36'" || \
	die "rootfs radio1 does not default to channel 36"
if [ "${BUILD_PROFILE}" != retail ]; then
	expected_txpower=38
	[ "${BUILD_PROFILE}" != ul-lab ] || expected_txpower=20
	printf '%s\n' "${radio0_config}" | grep -Eq "^[[:space:]]*option txpower '${expected_txpower}'$" || \
		die "rootfs radio0 does not request ${expected_txpower} dBm"
	printf '%s\n' "${radio1_config}" | grep -Eq "^[[:space:]]*option txpower '${expected_txpower}'$" || \
		die "rootfs radio1 does not request ${expected_txpower} dBm"
	if [ "${BUILD_PROFILE}" = ul-lab ]; then
		! grep -Eq "^[[:space:]]*option txpower '38'$" "${wireless_config}" || \
			die "UL-lab wireless config retains a 38 dBm request"
	fi
	[ "$(grep -Ec "^[[:space:]]*option encryption 'none'$" "${wireless_config}")" -eq 2 ] || \
		die "active lab rootfs does not configure both primary APs as open"
	[ "$(grep -Ec "^[[:space:]]*option hidden '0'$" "${wireless_config}")" -eq 2 ] || \
		die "active lab rootfs does not advertise both primary APs"
	[ "$(grep -Ec "^[[:space:]]*option ieee80211w '0'$" "${wireless_config}")" -eq 2 ] || \
		die "active lab rootfs retains PMF on an open primary AP"
	[ "$(grep -Ec "^[[:space:]]*option disabled '0'$" "${wireless_config}")" -eq 4 ] || \
		die "active lab rootfs must enable both radios and both primary AP interfaces"
	[ "$(grep -Ec "^[[:space:]]*option country 'US'$" "${wireless_config}")" -eq 2 ] || \
		die "LAB wireless config does not default both radios to US"
else
	! grep -Eq "^[[:space:]]*option (txpower|country|key|sae_password) " "${wireless_config}" || \
		die "Retail wireless config embeds a forced radio value or secret"
	[ "$(grep -Ec "^[[:space:]]*option encryption 'sae-mixed'$" "${wireless_config}")" -eq 2 ] || \
		die "Retail primary BSS placeholders are not protected"
	[ "$(grep -Ec "^[[:space:]]*option hidden '1'$" "${wireless_config}")" -eq 2 ] || \
		die "Retail primary BSS placeholders are not hidden"
	[ "$(grep -Ec "^[[:space:]]*option ieee80211w '2'$" "${wireless_config}")" -eq 2 ] || \
		die "Retail primary BSS placeholders do not require PMF"
	[ "$(grep -Ec "^[[:space:]]*option disabled '1'$" "${wireless_config}")" -eq 4 ] || \
		die "Retail rootfs does not disable both radios and both primary BSSs"
	! grep -Eq "^[[:space:]]*option (encryption 'none'|disabled '0')$" "${wireless_config}" || \
		die "Retail rootfs contains an open or active primary radio default"
fi
! grep -Eq "^[[:space:]]*option (key|sae_password) " "${wireless_config}" || \
	die "rootfs embeds a Wi-Fi secret"
for ax_option in \
	he_su_beamformer \
	he_su_beamformee \
	he_mu_beamformer \
	he_bss_color_enabled \
	he_spr_sr_control; do
	[ "$(grep -Ec "^[[:space:]]*option ${ax_option} '[13]'$" \
		"${rootfs_dir}/etc/config/wireless")" -eq 2 ] || \
		die "rootfs wireless config lacks ${ax_option} on both radios"
done
for obsolete_power_helper in \
	cr6608-force-txpower30 \
	cr6608-force-txpower38; do
	[ ! -e "${rootfs_dir}/usr/sbin/${obsolete_power_helper}" ] || \
		die "obsolete recurring TX-power helper is present: ${obsolete_power_helper}"
done
[ ! -e "${rootfs_dir}/etc/hotplug.d/ieee80211/99-cr6608-txpower" ] || \
	die "obsolete TX-power hotplug hook is present"
mapfile -t fixed_3800_users < <(
	grep -RIl 'set txpower fixed 3800' "${rootfs_dir}" 2>/dev/null || true
)
[ "${#fixed_3800_users[@]}" -eq 3 ] || \
	die "fixed 3800 mBm must appear only in the three explicit verification tools"
printf '%s\n' "${fixed_3800_users[@]}" | sort | \
	cmp -s - <(printf '%s\n' \
		"${rootfs_dir}/usr/bin/cr6608-country-power-scan" \
		"${rootfs_dir}/usr/bin/cr6608-txpower-verify" \
		"${rootfs_dir}/usr/bin/cr6608-wifi-full-verify" | sort) || \
	die "fixed 3800 mBm is present outside explicit verification tools"
for evidence_tool in \
	usr/bin/cr6608-txpower-verify \
	usr/bin/cr6608-wifi-full-verify \
	usr/bin/cr6608-country-power-scan \
	usr/sbin/cr6608-txpower-step-test \
	usr/sbin/cr6608-txpower-channel-table \
	usr/sbin/cr6608-ax-verify; do
	[ -x "${rootfs_dir}/${evidence_tool}" ] || \
		die "TX-power evidence tool is missing or not executable: ${evidence_tool}"
done
grep -Fq '/sys/firmware/devicetree/base' \
	"${rootfs_dir}/usr/bin/cr6608-txpower-verify" || \
	die "TX-power verifier does not traverse the real device-tree directory"
grep -Fq 'mediatek,cr6608-lab-txpower-38dbm' \
	"${rootfs_dir}/usr/bin/cr6608-txpower-verify" || \
	die "TX-power verifier does not check the exact CR6608 DTS property"
printf '%s\n' \
	'::sysinit:/etc/init.d/rcS S boot' \
	'::shutdown:/etc/init.d/rcS K shutdown' \
	'::askconsole:/usr/libexec/login.sh' | \
	cmp -s - "${rootfs_dir}/etc/inittab" || \
	die "rootfs does not expose the stock authenticated serial login"
grep -Fq 'date -u -s "@$anchor"' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor helper does not set the clock"
grep -Fq '[ "$now" -lt "$anchor" ]' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor helper lacks its forward-only guard"
grep -Fq '/rom/etc/smartap-time-anchor' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor helper does not retain the immutable image floor"
grep -Fq 'SMARTAP_TIME_ANCHOR_MIN_WRITE_ADVANCE:-21600' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor helper lacks the flash-wear write coalescer"
grep -Fq '/etc/init.d/smartap-time-anchor enable' \
	"${rootfs_dir}/etc/uci-defaults/00-smartap-time-anchor" || \
	die "time anchor service is not enabled on first boot"
grep -Eq '^START=01$' "${rootfs_dir}/etc/init.d/smartap-time-anchor" || \
	die "time anchor service does not run immediately after sysfixtime"
grep -Fq '/usr/sbin/smartap-time-anchor' \
	"${rootfs_dir}/etc/init.d/smartap-time-anchor" || \
	die "time anchor init script does not invoke the helper"
grep -Fq 'USE_PROCD=1' "${rootfs_dir}/etc/init.d/smartap-time-anchor" || \
	die "time anchor monitor is not procd-managed"
grep -Fq 'smartap-time-anchor monitor' \
	"${rootfs_dir}/etc/init.d/smartap-time-anchor" || \
	die "time anchor monitor is not supervised"
grep -Fq 'flock -xn 9' "${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor writers are not serialized by an exclusive kernel lock"
grep -Fq 'refusing to replace a newer persistent time floor' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor writer lacks its locked final rollback guard"
grep -Fq 'refusing authenticated time rollback below the current clock' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "authenticated time can roll CLOCK_REALTIME backwards"
grep -Fq '/usr/sbin/smartap-time-anchor set "$epoch"' \
	"${rootfs_dir}/www/cgi-bin/dashctl" || \
	die "authenticated browser time bypasses the forward-only anchor helper"
for syntax_file in \
	usr/sbin/cr6608-safe-apply \
	usr/sbin/cr6608-safe-wifi-reload \
	usr/sbin/cr6608-quicksettings-apply \
	usr/bin/cr6608-txpower-verify \
	usr/bin/cr6608-country-power-scan \
	usr/bin/cr6608-wifi-full-verify \
	usr/sbin/cr6608-ax-verify \
	usr/sbin/cr6608-easymesh-verify \
	usr/sbin/cr6608-management-guard \
	usr/sbin/cr6608-rescue-guard \
	etc/init.d/cr6608-safe-apply \
	etc/init.d/cr6608-management-guard \
	etc/init.d/cr6608-rescue-guard \
	etc/init.d/prplmesh \
	etc/init.d/cr6608-quicksettings \
	etc/uci-defaults/98-cr6608-safe-apply \
	etc/uci-defaults/96-cr6608-wlanrescue-isolation \
	etc/hotplug.d/iface/99-cr6608-rescue-guard \
	etc/hotplug.d/net/99-cr6608-rescue-guard \
	etc/uci-defaults/99-cr6608-runtime-services \
	etc/uci-defaults/99-cr6608-smartap-only \
	etc/uci-defaults/95-prplmesh-cr6608 \
	etc/config/cr6608quick \
	www/cgi-bin/cr6608-quick-apply \
	www/cgi-bin/cr6608-quick-confirm \
	www/cgi-bin/dashctl \
	www/cgi-bin/dashapi2 \
	usr/libexec/cr6608-vlan-lib \
	usr/libexec/cr6608-rescue-firewall-include \
	usr/sbin/cr6608-security-apply \
	usr/sbin/cr6608-session-reaper \
	usr/sbin/cr6608-eeprom-power \
	usr/sbin/smartap-bootstrap \
	usr/sbin/cr6608-wifi-sentinel \
	usr/sbin/smartap-autochannel \
	etc/uci-defaults/97-smartap-bootstrap \
	usr/sbin/smartap-time-anchor \
	etc/init.d/smartap-time-anchor \
	etc/uci-defaults/00-smartap-time-anchor \
	www/cgi-bin/dashlogin \
	www/cgi-bin/dashluci \
	www/cgi-bin/dashlogout \
	usr/libexec/cr6608-session-auth; do
	sh -n "${rootfs_dir}/${syntax_file}" || die "shell syntax failed: ${syntax_file}"
done
check_javascript_syntax \
	"${rootfs_dir}/www/luci-static/resources/view/cr6608/quicksettings.js" || \
	die "quick-settings JavaScript syntax failed"
check_javascript_syntax "${rootfs_dir}/www/dashboard.js" || \
	die "dashboard JavaScript syntax failed"
check_javascript_syntax "${rootfs_dir}/www/smartap-zero-retention.js" || \
	die "Smart AP zero-retention migration JavaScript syntax failed"
luci_sysauth="${rootfs_dir}/usr/share/ucode/luci/template/themes/argon/sysauth.ut"
luci_mapping="/cgi-bin/luci=/usr/share/ucode/luci/uhttpd.uc"
[ "$(grep -Fc "list ucode_prefix '${luci_mapping}'" \
	"${rootfs_dir}/etc/config/uhttpd")" = 1 ] || \
	die "uhttpd does not have exactly one canonical LuCI route"
if grep -Fq '/cgi-bin/luci=/usr/share/ucode/cr6608/smartap-redirect.uc' \
	"${rootfs_dir}/etc/config/uhttpd"; then
	die "uhttpd still uses the retired Smart AP redirect handler"
fi
grep -Fq "http.redirect('/');" "${luci_sysauth}" || \
	die "unauthenticated LuCI does not return to Smart AP"
quick_ui="${rootfs_dir}/www/luci-static/resources/view/cr6608/quicksettings.js"
grep -Fq "method: 'freqlist'" "${quick_ui}" || die "quick-settings live channel RPC is absent"
grep -Fq "method: 'countrylist'" "${quick_ui}" || die "quick-settings country RPC is absent"
grep -Fq "form.Value, 'txpower_radio0'" "${quick_ui}" || die "quick-settings radio0 TX power input is absent"
grep -Fq "form.Value, 'txpower_radio1'" "${quick_ui}" || die "quick-settings radio1 TX power input is absent"
grep -Fq "o.datatype = 'range(1,38)'" "${quick_ui}" || die "quick-settings TX power range is absent"
grep -Fq 'Requested=' "${quick_ui}" || die "quick-settings requested TX power is absent"
grep -Fq 'Regulatory+channel max=' "${quick_ui}" || die "quick-settings channel maximum is absent"
grep -Fq 'Driver max=' "${quick_ui}" || die "quick-settings driver maximum is absent"
grep -Fq 'Current=' "${quick_ui}" || die "quick-settings current TX power is absent"
grep -Fq 'Status=' "${quick_ui}" || die "quick-settings TX power status is absent"
if grep -Fq '38 dBm requested maximum' "${quick_ui}"; then
	die "quick-settings renders a fixed TX power label instead of runtime telemetry"
fi
grep -Fq 'Restricted 5G channels reported by driver' "${quick_ui}" || die "quick-settings restricted-channel report is absent"
grep -Fq 'rollback_token' "${rootfs_dir}/www/cgi-bin/cr6608-quick-apply" || die "quick-settings transaction token response is absent"
grep -Fq 'retain-ip' "${rootfs_dir}/usr/sbin/cr6608-safe-apply" || die "temporary management-IP reachability guard is absent"
quick_executor="${rootfs_dir}/usr/sbin/cr6608-quicksettings-apply"
quick_cgi="${rootfs_dir}/www/cgi-bin/cr6608-quick-apply"
dashctl="${rootfs_dir}/www/cgi-bin/dashctl"
dashboard_js="${rootfs_dir}/www/dashboard.js"
dashapi2="${rootfs_dir}/www/cgi-bin/dashapi2"
safe_apply="${rootfs_dir}/usr/sbin/cr6608-safe-apply"
bootstrap="${rootfs_dir}/usr/sbin/smartap-bootstrap"
bootstrap_firstboot="${rootfs_dir}/etc/uci-defaults/97-smartap-bootstrap"
private_runtime="${rootfs_dir}/usr/libexec/cr6608-private-runtime"
neighbor_service="${rootfs_dir}/usr/sbin/cr6608-neighbor-service"
mndp_sender="${rootfs_dir}/usr/sbin/cr6608-mndp-advertise"
mndp_source="${SOURCE_ROOT}/src/cr6608-mndp-advertise.c"
[ -s "${mndp_source}" ] || die "auditable MNDP sender source is absent"
grep -Fq 'destination.sin_addr.s_addr = htonl(INADDR_BROADCAST)' \
	"${mndp_source}" && \
	grep -Fq 'packet_info->ipi_spec_dst = source' "${mndp_source}" && \
	grep -Fq 'local.sin_port = htons(MNDP_PORT)' "${mndp_source}" || \
	die "auditable MNDP source lacks packet/source-port/interface contract"
grep -Fq 'cr6608-mndp-source-v4' "${mndp_source}" && \
	strings "${mndp_sender}" | grep -Fqx 'cr6608-mndp-source-v4' || \
	die "installed MNDP binary lacks the source-build provenance marker"
python3 - "${mndp_sender}" <<'PY_MNDP_ELF' || \
	die "installed MNDP sender is not a little-endian MIPS32 ELF"
import pathlib
import struct
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()[:20]
if len(data) != 20 or data[:4] != b"\x7fELF" or data[4:6] != b"\x01\x01":
    raise SystemExit(1)
if struct.unpack_from("<H", data, 18)[0] != 8:
    raise SystemExit(1)
PY_MNDP_ELF
for private_consumer in "${dashctl}" "${dashapi2}" "${neighbor_service}"; do
	! grep -Fq '/tmp/cr6608-mndp.fields' "${private_consumer}" && \
		! grep -Fq '/tmp/cr6608-neighbor.status' "${private_consumer}" || \
		die "neighbor runtime still trusts predictable /tmp state"
done
grep -Fq 'cr6608_private_runtime_dir neighbor' "${neighbor_service}" && \
	grep -Fq 'cr6608_private_mktemp' "${neighbor_service}" && \
	grep -Fq 'cr6608_private_publish_file' "${neighbor_service}" || \
	die "neighbor fields are not prepared in root-private atomic storage"
grep -Fq "CR6608_PRIVATE_RUNTIME_ROOT=\"\${CR6608_PRIVATE_RUNTIME_ROOT:-/var/run/cr6608-private}\"" \
	"${private_runtime}" && \
	grep -Fq 'cr6608_private_dir_secure' "${private_runtime}" || \
	die "root-private runtime helper is absent or not owner/mode gated"
if strings "${mndp_sender}" | grep -Eq \
	'/tmp/(cr6608-mndp[.]fields|cr6608-neighbor[.]status)'; then
	die "installed MNDP sender still embeds predictable legacy state paths"
fi
for legacy_dashctl_writer in /tmp/dashctl.action /tmp/smartap.cron '/tmp/lanscan.$$'; do
	! grep -Fq "${legacy_dashctl_writer}" "${dashctl}" || \
		die "dashctl retains predictable root writer ${legacy_dashctl_writer}"
done
grep -Fq "PRIVATE_RUNTIME_LIB='/usr/libexec/cr6608-private-runtime'" "${dashctl}" && \
	grep -Fq 'ACTION_LOG="$(cr6608_private_mktemp' "${dashctl}" && \
	grep -Fq 'trap dashctl_exit_cleanup EXIT' "${dashctl}" && \
	grep -Fq 'cron_file="$DASHCTL_REQUEST_DIR/scheduled-reboot.cron"' "${dashctl}" && \
	grep -Fq 'st="$DASHCTL_REQUEST_DIR/lanscan"' "${dashctl}" || \
	die "dashctl root actions do not use request-private storage with cleanup"
for stock_package_surface in \
	"${rootfs_dir}/www/luci-static/resources/view/system/package-manager.js" \
	"${rootfs_dir}/usr/share/luci/menu.d/luci-app-package-manager.json" \
	"${rootfs_dir}/usr/share/rpcd/acl.d/luci-app-package-manager.json" \
	"${rootfs_dir}/usr/libexec/package-manager-call"; do
	[ ! -e "${stock_package_surface}" ] || \
		die "retail rootfs contains unguarded stock package surface: ${stock_package_surface#${rootfs_dir}/}"
done
"${APK}" --root "${rootfs_dir}" --no-logfile --no-cache \
	--repositories-file /dev/null info --installed base-files >/dev/null 2>&1 || \
	die "could not query the delivered rootfs APK installation database"
for discovery_package in cr6608-mndp lldpd; do
	"${APK}" --root "${rootfs_dir}" --no-logfile --no-cache \
		--repositories-file /dev/null info --installed "${discovery_package}" \
		>/dev/null 2>&1 || \
		die "delivered rootfs lacks installed discovery package ${discovery_package}"
done
"${APK}" --root "${rootfs_dir}" --no-logfile --no-cache \
	--repositories-file /dev/null info --installed ucert >/dev/null 2>&1 || \
	die "delivered rootfs lacks installed ucert"
if "${APK}" --root "${rootfs_dir}" --no-logfile --no-cache \
	--repositories-file /dev/null info --installed luci-app-package-manager \
	>/dev/null 2>&1; then
	die "delivered rootfs APK database contains luci-app-package-manager"
fi
grep -Fq 'package installation and removal are disabled in the retail Web UI' "${dashctl}" && \
	grep -Fq 'return 126' "${dashctl}" || \
	die "SmartAP package actions do not enforce refresh-only retail policy"
if grep -F 'actions=' "${dashctl}" | grep -Eq '"id":"opkg_(install|remove)"'; then
	die "SmartAP Software page still advertises Web package mutation"
fi
package_run_block="${tmp_dir}/package-manager-run.sh"
sed -n '/^package_manager_run() {$/,/^}$/p' "${dashctl}" >"${package_run_block}"
package_deny_line="$(grep -n -m1 'installation and removal are disabled' \
	"${package_run_block}" | cut -d: -f1)"
package_detect_line="$(grep -n -m1 'package_manager_detect' \
	"${package_run_block}" | cut -d: -f1)"
[ -n "${package_deny_line}" ] && [ -n "${package_detect_line}" ] && \
	[ "${package_deny_line}" -lt "${package_detect_line}" ] || \
	die "SmartAP package mutation denial occurs after manager detection"
! grep -Fq 'package_manager_preflight()' "${dashctl}" && \
	! grep -Fq 'package_manager_installed_names()' "${dashctl}" && \
	! grep -Fq 'package_spec_is_valid()' "${dashctl}" && \
	! grep -Fq 'safe_package_spec()' "${dashctl}" || \
	die "dead Web package mutation machinery remains reachable in dashctl"
! grep -Fq "clear_previous='1'" "${quick_executor}" || die "quick-settings executor forces destructive cleanup"
grep -Fq 'setting clear_previous)" 0' "${quick_executor}" || die "quick-settings executor does not default cleanup off"
grep -Fq 'clear_previous 0)" 0' "${quick_cgi}" || die "quick-settings CGI does not default cleanup off"
grep -Fq 'delete_previous="0"' "${dashctl}" || die "Smart AP does not default cleanup off"
grep -Fq 'cr6608_port_vlan_is_owned()' "${rootfs_dir}/usr/libexec/cr6608-vlan-lib" || \
	die "Smart AP VLAN cleanup has no ownership boundary"
port_readiness_lib="${rootfs_dir}/usr/libexec/cr6608-port-readiness-lib"
grep -Fq 'CR6608_WAN_VLAN_OWNER="quicksettings-wan-vlan-v1"' \
	"${port_readiness_lib}" && \
	grep -Fq 'cr6608_managed_wan_vlan_vid()' "${port_readiness_lib}" && \
	grep -Fq 'cr6608_managed_wan_vlan_state()' "${port_readiness_lib}" && \
	grep -Fq 'cr6608_wan_ownership_available()' "${port_readiness_lib}" && \
	grep -Fq 'cr6608_wan_uci_pppoe_active()' "${port_readiness_lib}" && \
	grep -Fq 'cr6608_wan_uci_parked()' "${port_readiness_lib}" && \
	grep -Fq 'state="pppoe-vlan-active:$device_vid"' "${port_readiness_lib}" || \
	die "WAN readiness lacks the owned PPPoE-over-802.1Q contract"
grep -Fq 'dump="$("$CR6608_PORT_UCI_BIN" -q show network 2>/dev/null)" || return 1' \
	"${port_readiness_lib}" && \
	grep -Fq 'cr6608_dump_option_declared "$dump" network.wan.username' \
		"${port_readiness_lib}" && \
	grep -Fq 'cr6608_dump_option_declared "$dump" network.wan.password' \
		"${port_readiness_lib}" && \
	grep -Fq 'cr6608_wan_uci_parked "$dump" || return 1' \
		"${port_readiness_lib}" || \
	die "WAN readiness collapses UCI read failure or retained credentials into a parked state"
grep -Fq 'cr6608_wan_l3_reference_conflicts()' "${port_readiness_lib}" && \
	grep -Fq 'cr6608_wan_companion_alias_safe()' "${port_readiness_lib}" && \
	grep -Fq "[ \"\$iface\" = wan6 ] && [ \"\$device\" = @wan ]" "${port_readiness_lib}" || \
	die "WAN ownership gate lacks token/alias-aware L3 conflict detection"
grep -Fq "option pppoe_vlan_enabled '0'" \
	"${rootfs_dir}/etc/config/cr6608quick" || \
	die "clean-image PPPoE does not default to bare WAN"
grep -Fq 'cr6608_wan_ownership_available "$wan_target_vid" "$clear_previous"' \
	"${quick_executor}" && \
	grep -Fq "network.cr6608_wan_vlan.cr6608_owner='quicksettings-wan-vlan-v1'" \
		"${quick_executor}" && \
	grep -Fq "network.cr6608_wan_vlan.type='8021q'" "${quick_executor}" && \
	grep -Fq "network.cr6608_wan_vlan.ifname='wan'" "${quick_executor}" && \
	grep -Fq 'uci set network.wan.device="$wan_device"' "${quick_executor}" || \
	die "Quick Settings lacks fail-closed bare/tagged PPPoE WAN staging"
grep -Fq 'set_pppoe_wan "$pppoe_user" "$pppoe_pass" "$pppoe_port" "$ipv6_enabled" "$wan_target_vid" || MUTATION_FAILED=1' \
	"${quick_executor}" && \
	grep -Fq 'set_ap_ports || MUTATION_FAILED=1' "${quick_executor}" && \
	grep -Fq 'for reference in network.wan.username network.wan.password; do' \
		"${quick_executor}" && \
	grep -Fq 'uci -q revert "$pkg" >/dev/null 2>&1 || failed=1' \
		"${quick_executor}" && \
	grep -Fq 'confirm "$SAFE_TOKEN" >/dev/null 2>&1 || return 1' \
		"${quick_executor}" || \
	die "Quick Settings can ignore WAN staging, credential reads, or rollback failure"
grep -Fq 'if ! pending="$(uci -q changes "$pkg" 2>/dev/null)"; then' \
	"${quick_executor}" && \
	grep -Fq 'could not inspect pre-existing UCI delta for package $pkg' \
		"${quick_executor}" && \
	grep -Fq 'refusing to merge pre-existing UCI delta for package $pkg' \
		"${quick_executor}" || \
	die "Quick Settings transaction does not fail closed on UCI delta/query errors"
grep -Fq 'WRITE_PACKAGES="network wireless dhcp firewall cr6608quick smartap usteer prplmesh"' \
	"${quick_cgi}" && \
	[ "$(grep -Fc 'for package in $WRITE_PACKAGES; do' "${quick_cgi}")" -ge 2 ] || \
	die "Quick Settings CGI omits prplMesh from authorization or staged-delta cleanup"
grep -Fq 'for pkg in network wireless dhcp firewall smartap cr6608quick usteer prplmesh sqm system uhttpd dropbear; do' \
	"${safe_apply}" || \
	die "Safe Apply rollback omits the prplMesh configuration"
grep -Fq 'PORT_READINESS_LIB="${CR6608_PORT_READINESS_LIB:-/usr/libexec/cr6608-port-readiness-lib}"' \
	"${dashctl}" && \
	grep -Fq 'cr6608_wan_ownership_available "$wan_target_vid" "$delete_previous"' \
		"${dashctl}" && \
grep -Fq 'royal_stage_wan_vlan "$wan_target_vid"' "${dashctl}" && \
	grep -Fq 'royal_verify_wan_vlan_stage "$wan_target_vid"' "${dashctl}" && \
	grep -Fq 'cr6608_wan_uci_pppoe_active "$_royal_verify_vid" "$_royal_verify_dump"' \
		"${dashctl}" && \
	grep -Fq 'cr6608_wan_uci_parked "$_royal_verify_dump"' "${dashctl}" && \
	grep -Fq 'royal_reference_snapshot "$_royal_delete_ref"' "${dashctl}" && \
	grep -Fq 'royal_reference_snapshot "$_royal_list_ref"' "${dashctl}" && \
	grep -Fq 'uci -q revert "$_royal_pkg" >/dev/null 2>&1 || _royal_restore_rc=1' \
		"${dashctl}" || \
	die "Smart dashboard bypasses the shared PPPoE WAN VLAN ownership gate"
grep -Fq "DASHCTL_TRANSACTION_UCI_PACKAGES='network wireless dhcp firewall system smartap cr6608quick uhttpd dropbear sqm usteer prplmesh'" \
	"${dashctl}" && \
	grep -Fq 'uci -q changes "$_dtuc_pkg"' "${dashctl}" && \
	grep -Fq 'royal_require_clean_uci || return 1' "${dashctl}" && \
	[ "$(grep -Fc 'royal_require_clean_uci ||' "${dashctl}")" -ge 4 ] || \
	die "Smart dashboard transactions do not fail closed on pre-existing UCI deltas"
grep -Fq '/etc/config/prplmesh \' "${dashctl}" && \
	grep -Fq 'for _action_pkg in $DASHCTL_TRANSACTION_UCI_PACKAGES; do' \
		"${dashctl}" && \
	grep -Fq 'for _royal_pkg in $DASHCTL_TRANSACTION_UCI_PACKAGES; do' \
		"${dashctl}" && \
	grep -Fq 'dashctl_prplmesh_run --stage "$PRPLMESH_SYNC_AP24" "$PRPLMESH_SYNC_AP5"' \
		"${dashctl}" && \
	grep -Fq 'dashctl_prplmesh_run --verify "$PRPLMESH_SYNC_AP24" "$PRPLMESH_SYNC_AP5"' \
		"${dashctl}" || \
	die "Smart dashboard prplMesh transaction, backup, or rollback coverage is incomplete"
python3 - "${dashctl}" <<'PY_PRPLMESH_DASHCTL'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").replace("\r\n", "\n")


def fail(message):
    raise SystemExit(f"IMAGE GATE FAILED: {message}")


def action_block(header):
    marker = f"  {header})\n"
    start = source.find(marker)
    if start < 0:
        fail(f"Smart dashboard prplMesh action arm is absent: {header}")
    body_start = start + len(marker)
    next_arm = re.search(r"(?m)^  [^ \t\n][^\n]*\)$", source[body_start:])
    body_end = body_start + next_arm.start() if next_arm else len(source)
    return source[body_start:body_end]


flows = {
    "save_wifi": (
        'action_arm_rollback "Wireless" || exit 0',
        "dashctl_prplmesh_stage || {",
        'action_commit wireless "Wireless" || exit 0',
        'action_commit prplmesh "Wireless" || exit 0',
        'action_wifi_reload "Wireless"',
        "dashctl_prplmesh_verify || {",
    ),
    "delete_wifi": (
        'action_arm_rollback "Wireless" || exit 0',
        "dashctl_prplmesh_stage || {",
        'action_commit wireless "Wireless" || exit 0',
        'action_commit prplmesh "Wireless" || exit 0',
        'action_wifi_reload "Wireless"',
        "dashctl_prplmesh_verify || {",
    ),
    "raw_uci_set|raw_uci_delete|raw_uci_add_section|raw_uci_delete_section|raw_uci_commit_reload": (
        'arm_rollback "$backup" || {',
        'if [ "$cfg" = "wireless" ] && ! dashctl_prplmesh_stage; then',
        'uci commit "$cfg"',
        'action_commit prplmesh "Raw OpenWrt UCI" || exit 0',
        'action_wifi_reload "Raw OpenWrt UCI"',
        "dashctl_prplmesh_verify || {",
    ),
    "reset_royal": (
        'arm_rollback "$backup" || royal_abort_apply',
        'dashctl_prplmesh_stage "$ifc24" "$ifc5" || royal_abort_apply',
        "royal_commit_packages network wireless dhcp firewall prplmesh || royal_abort_apply",
        "royal_apply_services || royal_abort_apply",
        "dashctl_prplmesh_verify || royal_abort_apply",
    ),
    "apply_royal": (
        'arm_rollback "$backup" "$ch24" "$ch5" "$radio0_enabled" "$radio1_enabled" ||',
        'dashctl_prplmesh_stage "$ifc24" "$ifc5" || royal_abort_apply',
        "royal_commit_packages wireless network dhcp firewall smartap cr6608quick prplmesh || royal_abort_apply",
        "royal_apply_services || royal_abort_apply",
        "dashctl_prplmesh_verify || royal_abort_apply",
    ),
}

for action_name, ordered_tokens in flows.items():
    block = action_block(action_name)
    positions = []
    cursor = 0
    for token in ordered_tokens:
        position = block.find(token, cursor)
        if position < 0:
            fail(
                f"Smart dashboard prplMesh {action_name} "
                "stage/commit/runtime/verify order is incomplete"
            )
        positions.append(position)
        cursor = position + len(token)
    if action_name in {
        "save_wifi",
        "delete_wifi",
        "raw_uci_set|raw_uci_delete|raw_uci_add_section|raw_uci_delete_section|raw_uci_commit_reload",
    }:
        if block.find("action_rollback_pending", positions[1], positions[2]) < 0:
            fail(
                f"Smart dashboard prplMesh {action_name} stage failure lacks rollback"
            )
        if block.find("action_rollback_pending", positions[-1]) < 0:
            fail(
                f"Smart dashboard prplMesh {action_name} verify failure lacks rollback"
            )

guest_block = action_block("save_guest")
if "wireless.smartap_guest.network='guest'" not in guest_block:
    fail("Smart dashboard guest BSS is not isolated from the primary fronthaul")
if re.search(
    r"dashctl_prplmesh_(?:stage|verify|run)"
    r"|action_commit\s+prplmesh\b"
    r"|royal_commit_packages[^\n]*\bprplmesh\b",
    guest_block,
):
    fail("Smart dashboard mirrors guest credentials into the primary prplMesh store")
if "/etc/init.d/prplmesh" in source:
    fail("Smart dashboard controls the gated prplMesh service during credential sync")
PY_PRPLMESH_DASHCTL
grep -Fq 'pppoe_vlan_enabled' "${rootfs_dir}/www/luci-static/resources/view/cr6608/quicksettings.js" && \
	grep -Fq 'pppoe_vlan_id' "${rootfs_dir}/www/luci-static/resources/view/cr6608/quicksettings.js" && \
	grep -Fq 'function validateWizardWanVlan(section, actionName)' "${dashboard_js}" || \
	die "Web interfaces do not expose and validate PPPoE WAN VLAN controls"
grep -Fq 'if (field) field.value = pppoe ? "1" : "0";' "${dashboard_js}" || \
	die "Smart AP mode synchronizer does not clear stale PPPoE toggles"
grep -Fq '?speedtest=1&nonce=' "${dashboard_js}" || \
	die "Smart AP authenticated local throughput client is absent"
grep -Fq 'Content-Length: 8388608' "${dashapi2}" || \
	die "Smart AP bounded local throughput payload is absent"
grep -Fq 'dd if=/dev/zero bs=65536 count=128' "${dashapi2}" || \
	die "Smart AP local throughput payload is not streamed"
grep -Fq 'ubus call network.wireless status' \
	"${rootfs_dir}/usr/sbin/cr6608-wifi-sentinel" || \
	die "Wi-Fi sentinel does not discover live interface names"
grep -Fq 'iw phy "$1" channels' \
	"${rootfs_dir}/usr/sbin/smartap-autochannel" || \
	die "autochannel does not use the driver enabled-channel list"
grep -Fq "option clear_previous '0'" "${rootfs_dir}/etc/config/cr6608quick" || \
	die "clean-image quick-settings cleanup/takeover is not fail-safe"
grep -Fq "option channel5 '36'" "${rootfs_dir}/etc/config/cr6608quick" || \
	die "clean-image quick-settings 5 GHz default is not channel 36"
if [ "${BUILD_PROFILE}" != retail ]; then
	grep -Fq "option security 'none'" "${rootfs_dir}/etc/config/cr6608quick" || \
		die "active lab quick-settings security default is not open"
	grep -Fq "option hide_ssid '0'" "${rootfs_dir}/etc/config/cr6608quick" || \
		die "active lab quick-settings default is hidden"
	[ "$(grep -Ec "^[[:space:]]*option radio[01]_enabled '1'$" \
		"${rootfs_dir}/etc/config/cr6608quick")" -eq 2 ] || \
		die "active lab quick-settings does not enable both radios"
	for smartap_open_default in \
		"option radio0_enabled '1'" \
		"option radio1_enabled '1'" \
		"option hide_ssid '0'" \
		"option security 'none'"; do
		grep -Fq "${smartap_open_default}" "${rootfs_dir}/etc/config/smartap" || \
			die "Smart AP defaults lack: ${smartap_open_default}"
	done
	expected_quick_txpower=38
	[ "${BUILD_PROFILE}" != ul-lab ] || expected_quick_txpower=20
	[ "$(grep -Ec "^[[:space:]]*option txpower(_radio[01])? '${expected_quick_txpower}'$" \
		"${rootfs_dir}/etc/config/cr6608quick")" -eq 3 ] || \
		die "active lab quick-settings txpower does not match ${expected_quick_txpower} dBm"
	if [ "${BUILD_PROFILE}" = ul-lab ]; then
		grep -Fq "option ul_muru '1'" "${rootfs_dir}/etc/config/smartap" &&
			grep -Fq "option muru_mask '15'" "${rootfs_dir}/etc/config/smartap" &&
			grep -Fq "option ul_muru_guard '1'" "${rootfs_dir}/etc/config/smartap" ||
			die "UL-lab MURU bitmap/guard policy is not armed"
	elif [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
		grep -Fq "option ul_muru '0'" "${rootfs_dir}/etc/config/smartap" &&
			grep -Fq "option muru_mask '15'" "${rootfs_dir}/etc/config/smartap" &&
			grep -Fq "option ul_muru_guard '1'" "${rootfs_dir}/etc/config/smartap" ||
			die "UL-forced-lab MURU bitmap/guard policy is not armed"
	fi
else
	for retail_defaults in \
		"${rootfs_dir}/etc/config/cr6608quick" \
		"${rootfs_dir}/etc/config/smartap"; do
		grep -Fq "option security 'mixed'" "${retail_defaults}" || \
			die "Retail UI metadata is not protected"
		grep -Fq "option hide_ssid '1'" "${retail_defaults}" || \
			die "Retail UI metadata exposes an unprovisioned SSID"
		[ "$(grep -Ec "^[[:space:]]*option radio[01]_enabled '0'$" \
			"${retail_defaults}")" -eq 2 ] || \
			die "Retail UI metadata enables an unprovisioned radio"
		! grep -Eq "^[[:space:]]*option (txpower|txpower_radio[01]|country|country24|country5) " \
			"${retail_defaults}" || die "Retail UI metadata forces country or power"
	done
	grep -Fq "option ul_muru_state 'retail-disabled'" \
		"${rootfs_dir}/etc/config/smartap" || die "Retail UL MURU state is not disabled"
	grep -Fq "option ul_muru_guard '0'" "${rootfs_dir}/etc/config/smartap" || \
		die "Retail UL MURU guard is armed"
fi
grep -Fq 'uci set "smartap.management.ipaddr=$ip"' "${quick_executor}" || \
	die "quick-settings management metadata does not follow the selected address"
grep -Fq 'royal_set "smartap.management.ipaddr=$device_ip"' "${dashctl}" || \
	die "Smart AP management metadata does not follow the selected address"
grep -Fq 'management_device="$(qget network.lan.device)"' "${quick_executor}" || \
	die "quick-settings Safe Apply bridge is hard-coded"
grep -Fq 'current_management_device="$(uci -q get network.lan.device' "${dashctl}" || \
	die "Smart AP Safe Apply bridge is hard-coded"
grep -Fq 'valid_management_host "$ipaddr" "$netmask"' "${dashctl}" || \
	die "Interfaces page accepts network or broadcast management addresses"
grep -Fq 'management_ip="$(g network.lan.ipaddr)"' "${bootstrap}" || \
	die "bootstrap can restore stale management metadata"
grep -Fq '/usr/sbin/smartap-bootstrap firstboot' "${bootstrap_firstboot}" || \
	die "UCI-default bootstrap does not select commit-only firstboot mode"
! grep -Eq '/etc/init.d/(network|firewall|dnsmasq)[[:space:]]+(start|reload|restart)|wifi[[:space:]]+reload|cr6608-dashboard-invalidate' \
	"${bootstrap_firstboot}" || \
	die "UCI-default bootstrap mutates runtime services before normal boot order"
grep -Fq 'normal|quiet|firstboot)' "${bootstrap}" && \
	grep -Fq 'if [ "$smartap_bootstrap_mode" != firstboot ]; then' "${bootstrap}" && \
	grep -Fq 'if [ "$smartap_bootstrap_mode" != firstboot ] && [ "$changed" = 1 ]' \
		"${bootstrap}" || \
	die "bootstrap firstboot mode can reload services or invalidate the dashboard"
[ "$(grep -Fc 'save_quick)' "${dashctl}")" -eq 1 ] || \
	die "legacy save_quick handler count is not exactly one"
grep -A1 -F 'save_quick)' "${dashctl}" | grep -Fq 'Legacy handler retired' || \
	die "legacy save_quick handler is active"
if grep -Fq 'legacy_save_quick_disabled)' "${dashctl}"; then
	die "dead legacy quick-settings handler remains"
fi
grep -Fq 'refusing to replace an existing pending rollback transaction' "${safe_apply}" || \
	die "Safe Apply can overwrite a pending transaction"
grep -Fq 'refusing to arm while temporary management address cleanup is pending' "${safe_apply}" || \
	die "Safe Apply can lose a temporary-address cleanup marker"
if grep -Eq "\.value\('(12|13|14)'" "${quick_ui}"; then
	die "quick-settings offers forbidden 2.4 GHz channels"
fi
python3 - \
	"${rootfs_dir}/usr/share/luci/menu.d/luci-app-cr6608-quicksettings.json" \
	"${rootfs_dir}/usr/share/luci/menu.d/zz-cr6608-logout.json" \
	"${rootfs_dir}/usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    try:
        with open(path, "r", encoding="utf-8") as stream:
            json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f"IMAGE GATE FAILED: invalid JSON in {path}: {exc}")

with open(sys.argv[3], "r", encoding="utf-8") as stream:
    acl = json.load(stream)
acl_section = acl.get("luci-app-cr6608-quicksettings", {})
for access_name in ("read", "write"):
    uci_packages = acl_section.get(access_name, {}).get("uci")
    if not isinstance(uci_packages, list) or uci_packages.count("prplmesh") != 1:
        raise SystemExit(
            "IMAGE GATE FAILED: LuCI Quick Settings ACL omits exact prplMesh "
            f"{access_name} authorization"
        )
methods = (
    acl_section
    .get("read", {})
    .get("ubus", {})
    .get("network.wireless")
)
if methods != ["status"]:
    raise SystemExit(
        "IMAGE GATE FAILED: LuCI ACL does not grant network.wireless status"
    )
PY
python3 - "${rootfs_dir}/usr/share/luci/menu.d/zz-cr6608-logout.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    menu = json.load(stream)
expected_action = {
    "type": "function",
    "module": "luci.controller.cr6608.logout",
    "function": "action_logout",
}
node = menu.get("admin/logout")
if not isinstance(node, dict) or node.get("action") != expected_action:
    raise SystemExit("IMAGE GATE FAILED: unified LuCI logout action is not exact")
PY
python3 - "${rootfs_dir}/etc/smartap-time-anchor" \
	"${rootfs_dir}/etc/smartap-build-time" <<'PY'
import datetime
import re
import sys

anchor_path, time_path = sys.argv[1:]
anchor_text = open(anchor_path, encoding="ascii").read()
time_text = open(time_path, encoding="ascii").read()
if not re.fullmatch(r"[0-9]{10}\n", anchor_text):
    raise SystemExit("IMAGE GATE FAILED: generated time anchor is not one Unix epoch line")
if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\n", time_text):
    raise SystemExit("IMAGE GATE FAILED: generated build time is not canonical UTC")
anchor = int(anchor_text)
stamp = int(datetime.datetime.fromisoformat(time_text.strip().replace("Z", "+00:00")).timestamp())
if anchor < 1577836800 or anchor > 2145916800 or stamp != anchor:
    raise SystemExit("IMAGE GATE FAILED: generated build time and anchor disagree")
PY
session_auth="${rootfs_dir}/usr/libexec/cr6608-session-auth"
dashlogin="${rootfs_dir}/www/cgi-bin/dashlogin"
dashluci="${rootfs_dir}/www/cgi-bin/dashluci"
dashlogout="${rootfs_dir}/www/cgi-bin/dashlogout"
dashctl="${rootfs_dir}/www/cgi-bin/dashctl"
logout_controller="${rootfs_dir}/usr/share/ucode/luci/controller/cr6608/logout.uc"
grep -Fq '[ "${REQUEST_METHOD:-GET}" = POST ]' "${dashluci}" || \
	die "LuCI bridge is not POST-only"
grep -Fq 'cr6608_session_from_request' "${dashluci}" || \
	die "LuCI bridge does not validate the HttpOnly Smart AP session"
grep -Fq 'cr6608_luci_session_lock' "${dashluci}" || \
	die "LuCI bridge does not serialize session-map access"
grep -Fq 'map_file="$map_dir/$request_sid"' "${dashluci}" || \
	die "LuCI bridge does not read the login-created session map"
grep -Fq 'cr6608_path_owned_by_root "$map_file"' "${dashluci}" || \
	die "LuCI bridge does not require a root-owned session map"
grep -Fq 'cr6608_valid_hex32 "$mapped_luci_sid"' "${dashluci}" || \
	die "LuCI bridge does not validate the mapped LuCI session"
grep -Fq 'luci_session_reauthentication_required' "${dashluci}" || \
	die "LuCI bridge does not fail closed when its session map is unavailable"
for forbidden_bridge_token in \
	'session create' \
	'session grant' \
	'grant_access_groups' \
	'grant_pairs' \
	'ACL_HELPER'; do
	if grep -Fq "${forbidden_bridge_token}" "${dashluci}"; then
		die "LuCI bridge still contains forbidden privileged fallback: ${forbidden_bridge_token}"
	fi
done
grep -Fq '"target":"/cgi-bin/luci/admin/network/wireless"' "${dashluci}" || \
	die "LuCI bridge does not return the fixed wireless-settings target"
for smart_cookie in cr6608_sid_http cr6608_sid_https; do
	grep -Fq "${smart_cookie}" "${session_auth}" || \
		die "Smart AP session helper lacks protocol cookie ${smart_cookie}"
done
grep -Fq '[ "$count" = 1 ]' "${session_auth}" || \
	die "Smart AP session helper does not reject duplicate cookies"
grep -Fq 'cr6608_cookie_value_unique cr6608_sid' "${session_auth}" || \
	die "Smart AP session helper lacks bounded legacy-cookie migration"
grep -Fq 'CLEAR_LEGACY_COOKIE="cr6608_sid=; Path=/; Max-Age=0;' "${dashlogin}" || \
	die "Smart AP login does not retire the legacy cookie"
if grep -Fq 'HTTP_X_CR6608_SESSION' "${session_auth}" "${dashlogin}" \
	"${dashluci}" "${dashlogout}" "${rootfs_dir}/www/dashboard.js"; then
	die "Smart AP bearer is still accepted through a request header"
fi
grep -Fq '{"ok":true}' "${dashlogin}" || \
	die "Smart AP login response is not bearer-free"
if grep -Eq 'data\.sid|"sid"[[:space:]]*:' "${rootfs_dir}/www/dashboard.js" "${dashlogin}"; then
	die "Smart AP bearer is exposed to browser JavaScript"
fi
grep -Fq 'id="openWrtBtn"' "${rootfs_dir}/www/index.html" || \
	die "Smart AP lacks the authenticated OpenWrt settings button"
grep -Fq 'async function ensureLuciSession()' "${rootfs_dir}/www/dashboard.js" || \
	die "dashboard lacks the secure LuCI session exchange"
grep -Fq 'window.location.assign("/cgi-bin/luci/admin/network/wireless")' \
	"${rootfs_dir}/www/dashboard.js" || \
	die "dashboard lacks fixed LuCI wireless-settings navigation"
grep -Fq 'function quiesceDataReadsForNavigation()' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'await quiesceDataReadsForNavigation();' "${rootfs_dir}/www/dashboard.js" || \
	die "dashboard does not drain live reads before LuCI navigation"
! grep -Eq '(^|[^A-Za-z])(localStorage|sessionStorage)([^A-Za-z]|$)' \
	"${rootfs_dir}/www/dashboard.js" || \
	die "dashboard retains browser-persistent or session storage"
if grep -Eiq 'document[[:space:]]*\.[[:space:]]*cookie|cookieStore|openDatabase|indexedDB|CacheStorage|(^|[^[:alnum:]_])caches([^[:alnum:]_]|$)|serviceWorker|ServiceWorkerRegistration|navigator[[:space:]]*\.[[:space:]]*storage|StorageFoundation|sharedStorage|show(OpenFile|SaveFile|Directory)Picker' \
	"${rootfs_dir}/www/index.html" "${rootfs_dir}/www/dashboard.js"; then
	die "dashboard can create browser-persistent state outside Web Storage"
fi
grep -Fq "worker-src 'none'" "${rootfs_dir}/www/index.html" || \
	die "dashboard CSP does not disable workers"
if find "${rootfs_dir}/www" -type f \( \
	-iname 'sw.js' -o -iname '*serviceworker*' -o \
	-iname '*service-worker*' -o -iname '*service_worker*' \) \
	-print -quit | grep -q .; then
	die "dashboard image ships a service-worker script"
fi
grep -Fq 'var MAX_PAGE_CLIENT_MACS = 128;' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'clientMacLru: []' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'while (order.length > MAX_PAGE_CLIENT_MACS) {' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'delete state.knownMacs[oldest];' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'delete state.deviceNames[oldest];' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'delete state.histories["sig_" + oldest];' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'delete state.histories["rate_" + oldest];' "${rootfs_dir}/www/dashboard.js" || \
	die "dashboard lacks bounded page-client memory eviction"
grep -Fq 'clientInventoryOverflow: false' "${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'var suppressNewDeviceAlerts = first || overflow || state.clientInventoryOverflow;' \
		"${rootfs_dir}/www/dashboard.js" && \
	grep -Fq 'state.clientInventoryOverflow = overflow;' "${rootfs_dir}/www/dashboard.js" || \
	die "dashboard lacks client-overflow alert suppression"
zero_retention_js="${rootfs_dir}/www/smartap-zero-retention.js"
[ "$(sha256sum "${zero_retention_js}" | awk '{print $1}')" = \
	'94563b77aedaeaa30c241d84a50299f67f379d6f432d0693ceff44f37dfdd3b2' ] || \
	die "zero-retention migration content differs from the audited delete-only program"
grep -Fqx '  var LEGACY_LOCAL_KEYS = ["smartap.availability", "smartap.cardOrder", "smartap.dailyBudgetGb", "smartap.dayBaseRx", "smartap.dayBaseTx", "smartap.devNames", "smartap.events", "smartap.histories", "smartap.insightCategory", "smartap.interval", "smartap.knownMacs", "smartap.lang", "smartap.latHist", "smartap.monthBaseRx", "smartap.monthBaseTx", "smartap.monthBudgetGb", "smartap.outageLog", "smartap.theme", "smartap.themePref", "smartap.uiVersion", "smartap.weeklyLog", "smartap.yearBaseRx", "smartap.yearBaseTx"];' \
	"${zero_retention_js}" || \
	die "zero-retention migration localStorage allowlist is missing or widened"
grep -Fqx '  var LEGACY_SESSION_KEYS = ["smartap.session"];' \
	"${zero_retention_js}" || \
	die "zero-retention migration sessionStorage allowlist is missing or widened"
[ "$(grep -Fc 'storage.removeItem(key);' "${zero_retention_js}")" = 1 ] || \
	die "zero-retention migration lacks one generic exact-key removal path"
[ "$(grep -Fc 'purgeExactKeys(window.localStorage, LEGACY_LOCAL_KEYS);' "${zero_retention_js}")" = 1 ] && \
	[ "$(grep -Fc 'purgeExactKeys(window.sessionStorage, LEGACY_SESSION_KEYS);' "${zero_retention_js}")" = 1 ] || \
	die "zero-retention migration does not target both historical stores exactly once"
if grep -Eq '\.(setItem|getItem|clear|key)\(' "${zero_retention_js}" || \
	grep -Eq 'Object\.(keys|values|entries)|for[[:space:]]*\([^)]*in[[:space:]]' \
		"${zero_retention_js}"; then
	die "zero-retention migration reads, creates, enumerates, or broadly clears browser storage"
fi
[ -s "${rootfs_dir}/www/dashboard.css" ] || \
	die "unified dashboard stylesheet is missing"
[ "$(grep -Fxc "  <link rel=\"stylesheet\" href=\"${EXPECTED_DASHBOARD_CSS_ASSET}\">" \
	"${rootfs_dir}/www/index.html")" = 1 ] || \
	die "unified dashboard stylesheet is not loaded with the expected cache-buster"
[ "$(grep -Fc "${EXPECTED_DASHBOARD_CSS_ASSET}" \
	"${rootfs_dir}/www/index.html")" = 1 ] || \
	die "unified dashboard stylesheet is missing or loaded more than once"
[ "$(grep -Fxc '  <script src="/smartap-zero-retention.js?v=20260826-exact-legacy-purge-v1" defer></script>' \
	"${rootfs_dir}/www/index.html")" = 1 ] && \
	[ "$(grep -Fxc "  <script src=\"${EXPECTED_DASHBOARD_JS_ASSET}\" defer></script>" \
		"${rootfs_dir}/www/index.html")" = 1 ] || \
	die "zero-retention migration and dashboard are not exact defer scripts"
[ "$(grep -Fc "${EXPECTED_DASHBOARD_JS_ASSET}" \
	"${rootfs_dir}/www/index.html")" = 1 ] || \
	die "dashboard script is missing or loaded more than once"
[ "$(grep -Ec 'src="/smartap-zero-retention[.]js([?"/])' \
	"${rootfs_dir}/www/index.html")" = 1 ] && \
	[ "$(grep -Ec 'src="/dashboard[.]js([?"/])' \
		"${rootfs_dir}/www/index.html")" = 1 ] || \
	die "zero-retention migration or dashboard is loaded more than once"
zero_retention_line="$(grep -nF '/smartap-zero-retention.js?v=20260826-exact-legacy-purge-v1' \
	"${rootfs_dir}/www/index.html" | cut -d: -f1)"
dashboard_line="$(grep -nF "${EXPECTED_DASHBOARD_JS_ASSET}" \
	"${rootfs_dir}/www/index.html" | cut -d: -f1)"
[ -n "${zero_retention_line}" ] && [ -n "${dashboard_line}" ] && \
	[ "${zero_retention_line}" -lt "${dashboard_line}" ] || \
	die "zero-retention migration does not run before the live dashboard"
grep -Fq 'state.session = "cookie";' "${rootfs_dir}/www/dashboard.js" || \
	die "dashboard lacks the page-memory cookie authentication marker"
for page_memory_marker in \
	'window.addEventListener("pagehide"' \
	'window.addEventListener("pageshow"' \
	'window.location.reload();' \
	'chartDrawJobs = Object.create(null);'; do
	grep -Fq "${page_memory_marker}" "${rootfs_dir}/www/dashboard.js" ||
		die "dashboard page-memory scrub lacks: ${page_memory_marker}"
done
dashboard_state_lib="${rootfs_dir}/usr/libexec/cr6608-dashboard-cache-state"
for live_no_cache_marker in \
	'live_only=1' \
	'dashapi_telemetry_purge()' \
	'if [ "$internal_refresh" = 1 ]; then' \
	'"snapshot_live":true,"snapshot_stored":false'; do
	grep -Fq "${live_no_cache_marker}" "${rootfs_dir}/www/cgi-bin/dashapi2" ||
		die "live dashboard zero-retention contract lacks: ${live_no_cache_marker}"
done
grep -Fq 'cr6608_dashboard_telemetry_purge()' "${dashboard_state_lib}" || \
	die "dashboard coordination library lacks legacy telemetry purge"
grep -Fq 'cr6608_dashboard_request_telemetry_purge()' "${dashboard_state_lib}" && \
	grep -Fq 'cr6608_dashboard_request_telemetry_recover() (' "${dashboard_state_lib}" && \
	grep -Fq 'exec 9>>"$_cache_recover_dir/collector.lock"' "${dashboard_state_lib}" && \
	grep -Fq 'flock -xn 9' "${dashboard_state_lib}" || \
	die "dashboard lacks lock-proven recovery of request-private SIGKILL residue"
for dashboard_guardian_marker in \
	'cr6608_dashboard_cache_process_identity()' \
	'cr6608_dashboard_cache_process_matches()' \
	'cr6608_dashboard_cache_collector_guardian_loop()' \
	'cr6608_dashboard_cache_collector_guardian_stop()'; do
	grep -Fq "${dashboard_guardian_marker}" "${dashboard_state_lib}" ||
		die "dashboard FD8 guardian lacks: ${dashboard_guardian_marker}"
done
dashboard_guardian_loop_block="$(sed -n \
	'/^cr6608_dashboard_cache_collector_guardian_loop() {$/,/^}$/p' \
	"${dashboard_state_lib}")"
printf '%s\n' "${dashboard_guardian_loop_block}" | \
	grep -Fq 'cr6608_dashboard_cache_process_identity "$_cache_guard_parent_pid"' && \
printf '%s\n' "${dashboard_guardian_loop_block}" | \
	grep -Fq 'exec 8>&-' && \
	printf '%s\n' "${dashboard_guardian_loop_block}" | \
		grep -Fq '( exec 8>&-; sleep 1 )' && \
	! printf '%s\n' "${dashboard_guardian_loop_block}" | \
		grep -Fq '( exec 8>&-; cr6608_dashboard_cache_process_identity' || \
	die "dashboard guardian descendants can retain the FD8 collector lock"
dashboard_guardian_stop_block="$(sed -n \
	'/^cr6608_dashboard_cache_collector_guardian_stop() {$/,/^}$/p' \
	"${dashboard_state_lib}")"
for dashboard_guardian_stop_marker in \
	'cr6608_dashboard_cache_process_matches "$_cache_stop_pid" "$_cache_stop_start"' \
	'kill -TERM "$_cache_stop_pid"' \
	'kill -KILL "$_cache_stop_pid"' \
	'wait "$_cache_stop_pid"'; do
	printf '%s\n' "${dashboard_guardian_stop_block}" | \
		grep -Fq "${dashboard_guardian_stop_marker}" || \
		die "dashboard guardian stop lacks PID+starttime-bound cleanup: ${dashboard_guardian_stop_marker}"
done
dashboard_collector_acquire_block="$(sed -n \
	'/^cr6608_dashboard_cache_collector_acquire() {$/,/^}$/p' \
	"${dashboard_state_lib}")"
collector_flock_line="$(printf '%s\n' "${dashboard_collector_acquire_block}" | \
	grep -nF 'flock -xn 8' | head -n 1 | cut -d: -f1)"
collector_purge_line="$(printf '%s\n' "${dashboard_collector_acquire_block}" | \
	grep -nF 'cr6608_dashboard_request_telemetry_purge "$CR6608_DASHBOARD_CACHE_DIR"' | \
	head -n 1 | cut -d: -f1)"
collector_guardian_line="$(printf '%s\n' "${dashboard_collector_acquire_block}" | \
	grep -nF 'cr6608_dashboard_cache_collector_guardian_loop' | \
	head -n 1 | cut -d: -f1)"
collector_parent_close_line="$(printf '%s\n' "${dashboard_collector_acquire_block}" | \
	grep -nF 'exec 8>&-' | tail -n 1 | cut -d: -f1)"
collector_owner_line="$(printf '%s\n' "${dashboard_collector_acquire_block}" | \
	grep -nF 'CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER=1' | head -n 1 | cut -d: -f1)"
[ -n "${collector_flock_line}" ] && [ -n "${collector_purge_line}" ] && \
	[ -n "${collector_guardian_line}" ] && \
	[ -n "${collector_parent_close_line}" ] && [ -n "${collector_owner_line}" ] && \
	[ "${collector_flock_line}" -lt "${collector_purge_line}" ] && \
	[ "${collector_purge_line}" -lt "${collector_guardian_line}" ] && \
	[ "${collector_guardian_line}" -lt "${collector_parent_close_line}" ] && \
	[ "${collector_parent_close_line}" -lt "${collector_owner_line}" ] && \
	printf '%s\n' "${dashboard_collector_acquire_block}" | \
		grep -Fq 'exec 0</dev/null 1>/dev/null 2>&1' && \
	printf '%s\n' "${dashboard_collector_acquire_block}" | \
		grep -Fq 'exec 3>&- 4>&- 5>&- 6>&- 7>&- 9>&-' && \
	printf '%s\n' "${dashboard_collector_acquire_block}" | \
		grep -Fq 'CR6608_DASHBOARD_CACHE_COLLECTOR_OWNER=0' || \
	die "dashboard collector handoff does not transfer FD8 solely to its guardian before publishing ownership"
dashboard_collector_release_block="$(sed -n \
	'/^cr6608_dashboard_cache_collector_release() {$/,/^}$/p' \
	"${dashboard_state_lib}")"
printf '%s\n' "${dashboard_collector_release_block}" | \
	grep -Fq 'cr6608_dashboard_cache_collector_guardian_stop' && \
	! printf '%s\n' "${dashboard_collector_release_block}" | grep -Fq 'flock -u 8' || \
	die "dashboard collector release still assumes the CGI parent owns FD8"
for request_private_telemetry_pattern in \
	'.dashcmd-out.*.*' \
	'.dashcmd-err.*.*' \
	'.linklog.*.*' \
	'.devices.*' \
	'.arp.*' \
	'.fdb.*' \
	'.lease.*' \
	'.degraded.*'; do
	grep -Fq "${request_private_telemetry_pattern}" "${dashboard_state_lib}" || \
		die "dashboard SIGKILL recovery omits: ${request_private_telemetry_pattern}"
done
grep -Fq 'cr6608_dashboard_cache_cleanup_process' \
	"${rootfs_dir}/www/cgi-bin/dashapi2" || \
	die "dashboard normal exit does not purge its request-private telemetry"
for retained_telemetry_symbol in \
	'cache_load_view' \
	'dashapi_start_detached_refresh' \
	'cr6608_dashboard_cache_snapshot' \
	'cr6608_dashboard_cache_inspect' \
	'cr6608_dashboard_cache_publish' \
	'response_cache=' \
	'perf_cache=' \
	'cpu_prev=' \
	'traffic_prev=' \
	'survey_prev=' \
	'dashapi_topology_cache_store' \
	'dashapi_topology_cache_load'; do
	! grep -Fq "${retained_telemetry_symbol}" \
		"${rootfs_dir}/www/cgi-bin/dashapi2" "${dashboard_state_lib}" || \
		die "dashboard retains forbidden telemetry path: ${retained_telemetry_symbol}"
done
if grep -Eq '>[[:space:]]*"?\$cache_dir/(response[.]json|perf|lite[.]cpu|cpu|traffic|traffic[.]topology|iface[.]|sta[.]|survey[.])' \
	"${rootfs_dir}/www/cgi-bin/dashapi2"; then
	die "dashboard writes retained telemetry below its coordination directory"
fi
grep -Fq 'cr6608_random_hex32' "${dashlogin}" || \
	die "Smart AP login does not use the exact entropy helper"
grep -Fq 'flock -xn 8 || reply "503 Service Unavailable"' "${dashlogin}" || \
	die "Smart AP login rate limiter is not serialized with a nonblocking fail-closed lock"
grep -Fq 'SET_COOKIE="$cookie_name=$tok; Path=/;${secure_cookie} HttpOnly; SameSite=Strict"' \
	"${dashlogin}" || die "Smart AP login cookie is not browser-session-only"
! grep -Fq 'SET_COOKIE="$cookie_name=$tok; Path=/; Max-Age=' "${dashlogin}" || \
	die "Smart AP successful login persists a browser cookie lifetime"
for protected_cgi in "${dashlogin}" "${dashluci}" "${dashlogout}" "${dashctl}"; do
	grep -Fq 'X-Frame-Options:' "${protected_cgi}" || \
		die "Smart AP CGI lacks an actual X-Frame-Options header: ${protected_cgi}"
	grep -Fq 'frame-ancestors' "${protected_cgi}" || \
		die "Smart AP CGI lacks an actual CSP frame-ancestors header: ${protected_cgi}"
done
grep -Fq 'set_admin_password)' "${dashctl}" || \
	die "Smart AP root password action is not explicitly locked"
grep -Fq 'The SSH/console root password cannot be changed from Smart AP.' "${dashctl}" || \
	die "Smart AP root password lock does not return the expected rejection"
! grep -Fq 'passwd root' "${dashctl}" || \
	die "Smart AP still contains a root password mutation command"
! grep -Fq 'root_password_param()' "${dashctl}" || \
	die "Smart AP still contains a root password input helper"
! grep -Fq 'valid_root_password()' "${dashctl}" || \
	die "Smart AP still contains obsolete root password validation code"
grep -Fq 'if [ -n "$(qparam device_password)" ] || [ -n "$(qparam admin_password)" ] || [ -n "$(qparam change_password)" ]; then' "${dashctl}" || \
	die "Smart AP quick setup does not reject legacy password parameters"
grep -Fq "ubus.call('session', 'destroy'" "${logout_controller}" || \
	die "LuCI logout controller does not destroy the active child session"
for smart_cookie in cr6608_sid_http cr6608_sid_https cr6608_sid; do
	grep -Fq "Set-Cookie: ${smart_cookie}=; Path=/; Max-Age=0;" "${dashlogout}" || \
		die "unified logout does not clear ${smart_cookie}"
done
for cookie_path in \
	'Path=/;' \
	'Path=/cgi-bin/luci;' \
	'Path=/cgi-bin/luci/;'; do
	grep -Fq "sysauth_http=; ${cookie_path}" "${dashlogout}" || \
		die "unified logout does not clear sysauth_http at ${cookie_path}"
	grep -Fq "sysauth_https=; ${cookie_path}" "${dashlogout}" || \
		die "unified logout does not clear sysauth_https at ${cookie_path}"
done
grep -Fqx '* * * * * /usr/sbin/cr6608-session-reaper >/dev/null 2>&1' \
	"${rootfs_dir}/etc/crontabs/root" || \
	die "expired Smart AP child-session reaper is not scheduled"
if grep -Fq 'startupSessionCleanup = revokeServerSessions(staleSid)' \
	"${rootfs_dir}/www/dashboard.js"; then
	die "dashboard still revokes another tab during startup"
fi
[ "$(cat "${rootfs_dir}/etc/smartap-version")" = "${EXPECTED_SMARTAP_VERSION}" ] || \
	die "installed Smart AP release identity is stale"
grep -Fq "var UI_VERSION = \"${EXPECTED_DASHBOARD_UI_VERSION}\";" \
	"${rootfs_dir}/www/dashboard.js" || \
	die "installed dashboard UI version is stale"
grep -Fq "${EXPECTED_DASHBOARD_CSS_ASSET}" \
	"${rootfs_dir}/www/index.html" || \
	die "dashboard stylesheet cache-buster is stale"
grep -Fq "${EXPECTED_DASHBOARD_JS_ASSET}" \
	"${rootfs_dir}/www/index.html" || \
	die "dashboard cache-buster is stale"
grep -Fq '/smartap-zero-retention.js?v=20260826-exact-legacy-purge-v1' \
	"${rootfs_dir}/www/index.html" || \
	die "zero-retention migration cache-buster is stale"
[ -s "${rootfs_dir}/www/luci-static/resources/icons/loading.svg" ] || \
	die "LuCI loading spinner asset is missing"
grep -Fq 'url(/luci-static/resources/icons/loading.svg)' \
	"${rootfs_dir}/www/luci-static/argon/css/cascade.css" || \
	die "Argon loading spinner does not use the installed LuCI SVG asset"
if grep -Fq 'url(/luci-static/resources/icons/loading.gif)' \
	"${rootfs_dir}/www/luci-static/argon/css/cascade.css"; then
	die "Argon still references the removed LuCI loading GIF"
fi
argon_mobile_css="${rootfs_dir}/www/luci-static/argon/css/cr6608-mobile.css"
argon_localtime_js="${rootfs_dir}/www/luci-static/argon/js/cr6608-localtime.js"
argon_header="${rootfs_dir}/usr/share/ucode/luci/template/themes/argon/header.ut"
[ -s "${argon_mobile_css}" ] || \
	die "Argon CR6608 mobile compatibility stylesheet is missing"
[ -s "${argon_localtime_js}" ] || \
	die "Argon Local Time bidi helper is missing"
grep -Fq '/css/cr6608-mobile.css?v=20260816-argon-mobile-v64-rtlfix1' \
	"${argon_header}" || \
	die "Argon CR6608 mobile compatibility stylesheet is not loaded last"
grep -Fq '/js/cr6608-localtime.js?v=20260816-argon-localtime-v64-rtlfix1' \
	"${argon_header}" || \
	die "Argon Local Time bidi helper is not loaded"
grep -Fq "http.header('Content-Security-Policy', \"default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; font-src 'self' data:; frame-ancestors 'self'; object-src 'none'; base-uri 'self'; form-action 'self'\");" \
	"${argon_header}" || \
	die "LuCI CSP does not permit the inline bootstrap and luci.js module evaluator"
if grep -Fq "'unsafe-eval'" "${rootfs_dir}/etc/uhttpd/security-headers.json" ||
   grep -Fq "'unsafe-eval'" "${rootfs_dir}/www/index.html"; then
	die "unsafe-eval escaped the LuCI-only CSP boundary"
fi
grep -Fq 'body[data-page="admin-status-overview"]' "${argon_mobile_css}" || \
	die "Argon status Local Time bidi protection is missing"
grep -Fq 'body[data-page="admin-network-wireless"]' "${argon_mobile_css}" || \
	die "Argon wireless mobile stacking protection is missing"
grep -Fq 'unicode-bidi: isolate' "${argon_mobile_css}" || \
	die "Argon mixed RTL/LTR time isolation is missing"
grep -Fq 'function isolateTokens(value)' "${argon_localtime_js}" || \
	die "Argon Local Time tokens are not directionally isolated"
uhttpd_config="${rootfs_dir}/etc/config/uhttpd"
uhttpd_security_headers="${rootfs_dir}/etc/uhttpd/security-headers.json"
uhttpd_init="${rootfs_dir}/etc/init.d/uhttpd"
[ "$(grep -Ec "^[[:space:]]*list listen_http '.*:80'$" "${uhttpd_config}")" -eq 1 ] || \
	die "HTTP management listener is not exactly IPv4-only"
grep -Fq "list listen_http '0.0.0.0:80'" "${uhttpd_config}" || \
	die "IPv4 HTTP management listener is missing"
! grep -Fq "list listen_http '[::]:80'" "${uhttpd_config}" || \
	die "IPv6 HTTP management listener is still enabled"
[ "$(grep -Ec "^[[:space:]]*list listen_https '.*:443'$" "${uhttpd_config}")" -eq 1 ] || \
	die "HTTPS management listener is not exactly IPv4-only"
grep -Fq "list listen_https '0.0.0.0:443'" "${uhttpd_config}" || \
	die "IPv4 HTTPS management listener is missing"
! grep -Fq "list listen_https '[::]:443'" "${uhttpd_config}" || \
	die "IPv6 HTTPS management listener is still enabled"
grep -Fq "option cert '/etc/uhttpd.crt'" "${uhttpd_config}" || \
	die "HTTPS certificate path is missing"
grep -Fq "option key '/etc/uhttpd.key'" "${uhttpd_config}" || \
	die "HTTPS key path is missing"
grep -Fq "option redirect_https '0'" "${uhttpd_config}" || \
	die "unprovisioned recovery HTTP policy changed"
[ "$(grep -Ec "^[[:space:]]*option rfc1918_filter '1'$" "${uhttpd_config}")" -eq 1 ] || \
	die "uhttpd global RFC1918 rebinding protection is not enabled exactly once"
[ "$(grep -Ec "^[[:space:]]*option json_script '/etc/uhttpd/security-headers.json'$" "${uhttpd_config}")" -eq 1 ] || \
	die "uhttpd does not load exactly one supported JSON security-header handler"
! grep -Eq "^[[:space:]]*list json_script " "${uhttpd_config}" || \
	die "uhttpd security-header handler is incorrectly configured as a UCI list"
# The official init script treats json_script as one scalar, splits it on
# whitespace, and supplies every readable path through uhttpd's -H interface.
# This permits the preserved-config migration to retain an operator handler
# and append the mandatory policy without misusing an unsupported UCI list.
grep -Fq 'config_get json_script "$cfg" json_script' "${uhttpd_init}" && \
	grep -Fq 'for file in $json_script; do' "${uhttpd_init}" && \
	grep -Fq 'procd_append_param command -H "$file"' "${uhttpd_init}" || \
	die "uhttpd init lacks supported scalar multi-path json_script handling"
python3 - "${uhttpd_security_headers}" <<'PY' || \
	die "uhttpd security-header JSON policy is malformed or incomplete"
import json
import pathlib
import sys

expected = {
    "request": [
        [
            ["add-header", "X-Content-Type-Options", "nosniff"],
            ["add-header", "X-Frame-Options", "SAMEORIGIN"],
            ["add-header", "Referrer-Policy", "no-referrer"],
            ["add-header", "Permissions-Policy", "camera=(), microphone=(), geolocation=()"],
            ["add-header", "Cross-Origin-Resource-Policy", "same-origin"],
            ["add-header", "Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; font-src 'self'; frame-ancestors 'self'; object-src 'none'; base-uri 'self'; form-action 'self'"],
        ]
    ]
}
with pathlib.Path(sys.argv[1]).open("r", encoding="utf-8") as stream:
    actual = json.load(stream)
if actual != expected:
    raise SystemExit("unexpected uhttpd security-header policy")
PY

# Rescue endpoint contract: UCI stores only addressless ownership metadata.
# The guard resolves the primary AP's live L3 bridge/VLAN and attaches the /32
# only after a dynamic Wi-Fi AP nft ruleset passes validation.
rescue_network="${rootfs_dir}/etc/config/network"
rescue_firewall="${rootfs_dir}/etc/config/firewall"
rescue_guard="${rootfs_dir}/usr/sbin/cr6608-rescue-guard"
rescue_init="${rootfs_dir}/etc/init.d/cr6608-rescue-guard"
rescue_migration="${rootfs_dir}/etc/uci-defaults/96-cr6608-wlanrescue-isolation"
rescue_iface_hotplug="${rootfs_dir}/etc/hotplug.d/iface/99-cr6608-rescue-guard"
rescue_net_hotplug="${rootfs_dir}/etc/hotplug.d/net/99-cr6608-rescue-guard"
rescue_firewall_include="${rootfs_dir}/usr/libexec/cr6608-rescue-firewall-include"
rescue_runtime_defaults="${rootfs_dir}/etc/uci-defaults/99-cr6608-runtime-services"
rescue_firewall_init="${rootfs_dir}/etc/init.d/firewall"
[ -x "${rootfs_dir}/bin/busybox" ] || die "rootfs lacks BusyBox for detached runtime applets"
for rescue_busybox_applet in usr/bin/setsid usr/bin/env bin/kill; do
	rescue_applet_path="${rootfs_dir}/${rescue_busybox_applet}"
	[ -L "${rescue_applet_path}" ] || \
		die "rescue watchdog applet is not a BusyBox link: ${rescue_busybox_applet}"
	case "$(readlink "${rescue_applet_path}")" in
		busybox|*/bin/busybox) ;;
		*) die "unexpected rescue watchdog applet target: ${rescue_busybox_applet}" ;;
	esac
done
rescue_flock_path="${rootfs_dir}/usr/bin/flock"
[ -L "${rescue_flock_path}" ] || die "rootfs lacks a linked flock implementation"
case "$(readlink "${rescue_flock_path}")" in
	busybox|*/bin/busybox) ;;
	/usr/bin/util-linux-flock)
		[ "${FACTORY38_BUILD_MODE}" = maintenance ] && \
			[ -x "${rootfs_dir}/usr/bin/util-linux-flock" ] || \
			die "unexpected util-linux flock outside maintenance image"
		;;
	*) die "unexpected rescue flock target" ;;
esac
rescue_network_block="$(sed -n "/^config interface 'wlanrescue'$/,/^$/p" "${rescue_network}")"
printf '%s\n' "${rescue_network_block}" | grep -Fq "option cr6608_owner 'wlanrescue-v1'" && \
	printf '%s\n' "${rescue_network_block}" | grep -Fq "option proto 'none'" && \
	printf '%s\n' "${rescue_network_block}" | grep -Fq "option ipv6 '0'" && \
	printf '%s\n' "${rescue_network_block}" | grep -Fq "option delegate '0'" || \
	die "rescue addressless ownership metadata is incomplete"
printf '%s\n' "${rescue_network_block}" | grep -Fq "option auto '0'" || \
	die "rescue interface can auto-start before nft isolation"
! printf '%s\n' "${rescue_network_block}" | grep -Eq \
	"^[[:space:]]*option (device|ipaddr|netmask|ip6addr)[[:space:]]" || \
	die "rescue metadata still lets netifd attach an address or device"
! grep -Fq "config device 'cr6608_rescue_dev'" "${rescue_network}" || \
	die "obsolete rescue dummy device remains in the shipped network config"
rescue_lan_zone="$(sed -n "/^config zone 'lan'$/,/^$/p" "${rescue_firewall}")"
! printf '%s\n' "${rescue_lan_zone}" | grep -Fq wlanrescue || \
	die "wlanrescue remains in the trusted LAN firewall zone"
rescue_zone="$(sed -n "/^config zone 'cr6608_rescue_zone'$/,/^$/p" "${rescue_firewall}")"
printf '%s\n' "${rescue_zone}" | grep -Fq "list network 'wlanrescue'" && \
	printf '%s\n' "${rescue_zone}" | grep -Fq "option cr6608_owner 'wlanrescue-v1'" && \
	printf '%s\n' "${rescue_zone}" | grep -Fq "option input 'REJECT'" && \
	printf '%s\n' "${rescue_zone}" | grep -Fq "option forward 'REJECT'" || \
	die "isolated rescue firewall zone is incomplete"
for rescue_rule in cr6608_rescue_web cr6608_rescue_ping cr6608_rescue_reject; do
	grep -Fq "config rule '${rescue_rule}'" "${rescue_firewall}" || \
		die "rescue firewall rule missing: ${rescue_rule}"
done
for rescue_allow_rule in cr6608_rescue_web cr6608_rescue_ping; do
	rescue_allow_block="$(sed -n "/^config rule '${rescue_allow_rule}'$/,/^$/p" "${rescue_firewall}")"
	printf '%s\n' "${rescue_allow_block}" | \
		grep -Fq "option mark '0x6608cafe/0xffffffff'" || \
		die "rescue allow rule lacks exact AP packet mark: ${rescue_allow_rule}"
done
grep -Fq "NFT_BIN='/usr/sbin/nft'" "${rescue_guard}" && \
	grep -Fq "UBUS_BIN='/bin/ubus'" "${rescue_guard}" && \
	grep -Fq "JSONFILTER_BIN='/usr/bin/jsonfilter'" "${rescue_guard}" && \
	grep -Fq "RESCUE_INIT='/etc/init.d/cr6608-rescue-guard'" "${rescue_guard}" && \
	grep -Fq "SYS_CLASS_NET='/sys/class/net'" "${rescue_guard}" && \
	grep -Fq "SETSID_BIN='/usr/bin/setsid'" "${rescue_guard}" && \
	grep -Fq "KILL_BIN='/bin/kill'" "${rescue_guard}" && \
	grep -Fq "PROC_ROOT='/proc'" "${rescue_guard}" || \
	die "rescue guard production paths are not fixed"
! grep -Fq '${CR6608_RESCUE_' "${rescue_guard}" || \
	die "rescue guard exposes a production path/sysfs override"
grep -Fq '$1 == "type" && $2 == "AP"' "${rescue_guard}" && \
	grep -Fq 'set wifi_ap_ifaces' "${rescue_guard}" && \
	grep -Fq 'got_count != want_count' "${rescue_guard}" && \
	grep -Fq 'CR6608_RESCUE_WIRED_DENY' "${rescue_guard}" && \
	grep -Fq 'CR6608_RESCUE_WIRED_REPLY_DENY' "${rescue_guard}" && \
	grep -Fq 'CR6608_RESCUE_SOURCE_SPOOF_ARP_DENY' "${rescue_guard}" && \
	grep -Fq 'CR6608_RESCUE_SOURCE_SPOOF_IP_DENY' "${rescue_guard}" && \
	grep -Fq 'meta mark set $RESCUE_PACKET_MARK' "${rescue_guard}" && \
	grep -Fq 'meta mark $RESCUE_PACKET_MARK ip daddr' "${rescue_guard}" || \
	die "rescue guard lacks exact AP-set verification or wired deny rules"
grep -Fq 'tcp sport { 80, 443 } meta mark $RESCUE_PACKET_MARK accept' \
	"${rescue_guard}" && \
	grep -Fq 'ip protocol icmp meta mark $RESCUE_PACKET_MARK accept' \
		"${rescue_guard}" || \
	die "rescue reply path can synthesize a mark for forwarded spoof traffic"
grep -Fq '"$NFT_BIN" -c -f "$RULES_FILE"' "${rescue_guard}" || \
	die "rescue nft rules are not syntax-checked before activation"
rescue_nft_apply_line="$(grep -n -m1 '"$NFT_BIN" -f "$RULES_FILE"' "${rescue_guard}" | cut -d: -f1)"
rescue_addr_add_line="$(grep -n -m1 '"$IP_BIN" -4 addr add "$RESCUE_CIDR"' "${rescue_guard}" | cut -d: -f1)"
[ -n "${rescue_nft_apply_line}" ] && [ -n "${rescue_addr_add_line}" ] && \
	[ "${rescue_nft_apply_line}" -lt "${rescue_addr_add_line}" ] || \
	die "rescue address can start before nft rules apply"
! grep -Eq 'IFUP_BIN|ifup wlanrescue|ifdown wlanrescue|RESCUE_DEVICE|cr-rescue' \
	"${rescue_guard}" || die "rescue guard still contains the obsolete dummy/ifup path"
grep -Fq 'run_close_timed "$IP_BIN" -4 -o addr show' "${rescue_guard}" && \
	grep -Fq 'addr del "$rescue_addr_cidr"' "${rescue_guard}" && \
	grep -Fq "fail_closed 'rules-health'" "${rescue_guard}" || \
	die "rescue health failures do not remove every exact rescue address"
grep -Fq "verify_rules || fail_closed 'rules-health'" "${rescue_guard}" && \
	grep -Fq "MONITOR_INTERVAL='10'" "${rescue_guard}" && \
	grep -Fq "MONITOR_RECOVERY_ATTEMPTS='3'" "${rescue_guard}" && \
	grep -Fq '"$GUARD_BIN" health' "${rescue_guard}" && \
	grep -Fq '"$GUARD_BIN" apply' "${rescue_guard}" || \
	die "rescue guard lacks bounded fail-closed health recovery"
grep -Fq 'guard_serialized_close' "${rescue_guard}" && \
	grep -Fq '"$monitor_health_rc" -eq 75' "${rescue_guard}" && \
	grep -Fq "MONITOR_BUSY_LIMIT='3'" "${rescue_guard}" && \
	grep -Fq 'install_emergency_deny_rules' "${rescue_guard}" && \
	grep -Fq "MONITOR_FAILURE_BACKOFF='30'" "${rescue_guard}" && \
	grep -Fq "FAIL reason=monitor-recovery-exhausted" "${rescue_guard}" && \
	grep -Fq 'exit 75' "${rescue_guard}" || \
	die "rescue monitor can race or mutate an active serialized transaction"
grep -Fq 'run_limit_process_identity' "${rescue_guard}" && \
	grep -Fq 'run_limit_signal_group TERM' "${rescue_guard}" && \
	grep -Fq 'run_limit_signal_group KILL' "${rescue_guard}" && \
	grep -Fq '"$FLOCK_BIN" -xn 9' "${rescue_guard}" && \
	grep -Fq '( exec "$SETSID_BIN" "$@" ) 9>&-' "${rescue_guard}" && \
	grep -Fq 'run_stdin_close_timed "$NFT_BIN" -f -' "${rescue_guard}" || \
	die "rescue guard external commands or lock are not watchdog bounded"
! grep -Fq '"$FLOCK_BIN" -x 9' "${rescue_guard}" || \
	die "rescue guard contains a blocking flock acquisition"
! grep -Fq 'run_timed_seconds_lock_fd' "${rescue_guard}" || \
	die "rescue guard retains an obsolete child lock-fd escape hatch"
! grep -Fq 'TIMEOUT_BIN=' "${rescue_guard}" || \
	die "rescue guard depends on an unavailable timeout binary"
rescue_apply_close_line="$(grep -n -m1 "close_endpoint || fail_closed 'dark-close'" \
	"${rescue_guard}" | cut -d: -f1)"
rescue_full_validation_line="$(grep -n -m1 '^validate_configuration$' "${rescue_guard}" | cut -d: -f1)"
[ -n "${rescue_apply_close_line}" ] && [ -n "${rescue_full_validation_line}" ] && \
	[ "${rescue_apply_close_line}" -lt "${rescue_full_validation_line}" ] && \
	[ "${rescue_full_validation_line}" -lt "${rescue_nft_apply_line}" ] || \
	die "rescue apply does not close before full UCI/iw validation"
rescue_firewall_stop_line="$(grep -n -m1 '"$FW4_BIN" stop' \
	"${rescue_guard}" | cut -d: -f1)"
[ -n "${rescue_firewall_stop_line}" ] && \
	[ "${rescue_apply_close_line}" -lt "${rescue_firewall_stop_line}" ] && \
	[ "${rescue_firewall_stop_line}" -lt "${rescue_full_validation_line}" ] && \
	grep -Fq 'start|apply|firewall-stop)' "${rescue_guard}" || \
	die "firewall stop is not serialized between rescue close and re-activation"
rescue_health_block="$(sed -n '/^if \[ "$mode" = health \]; then$/,/^fi$/p' "${rescue_guard}")"
printf '%s\n' "${rescue_health_block}" | grep -Fq 'load_route_owner' && \
	printf '%s\n' "${rescue_health_block}" | grep -Fq 'verify_ruleset_snapshot' && \
	printf '%s\n' "${rescue_health_block}" | grep -Fq 'build_wifi_elements' && \
	printf '%s\n' "${rescue_health_block}" | grep -Fq 'verify_rules' && \
	printf '%s\n' "${rescue_health_block}" | grep -Fq 'verify_address' && \
	printf '%s\n' "${rescue_health_block}" | grep -Fq 'verify_route' || \
	die "rescue health mode lacks exact runtime verification"
! printf '%s\n' "${rescue_health_block}" | \
	grep -Eq 'UCI_BIN|validate_configuration|uci_get' || \
	die "rescue monitor health mode performs a full UCI walk"
rescue_health_snapshot_line="$(printf '%s\n' "${rescue_health_block}" | grep -n -m1 'verify_ruleset_snapshot' | cut -d: -f1)"
rescue_health_iw_line="$(printf '%s\n' "${rescue_health_block}" | grep -n -m1 'build_wifi_elements' | cut -d: -f1)"
[ -n "${rescue_health_snapshot_line}" ] && [ -n "${rescue_health_iw_line}" ] && \
	[ "${rescue_health_snapshot_line}" -lt "${rescue_health_iw_line}" ] || \
	die "rescue health waits on iw before its exact nft snapshot"
grep -Fq "RESCUE_ROUTE_PROTO='221'" "${rescue_guard}" && \
	grep -Fq 'ROUTE_OWNER_FILE="$STATE_DIR/route-owner"' "${rescue_guard}" && \
	grep -Fq 'RULESET_STATE_FILE="$STATE_DIR/ruleset.snapshot"' "${rescue_guard}" && \
	grep -Fq 'route_records_match_owner' "${rescue_guard}" && \
	grep -Fq 'chmod 0600 "$route_owner_tmp"' "${rescue_guard}" && \
	grep -Fq 'chmod 0600 "$ruleset_state_tmp"' "${rescue_guard}" || \
	die "rescue route lacks exact protocol/state ownership"
rescue_route_add_line="$(grep -n -m1 'route add "$RESCUE_CLIENT_SUBNET"' "${rescue_guard}" | cut -d: -f1)"
rescue_owner_publish_line="$(grep -n -m1 '^if ! write_route_owner; then$' "${rescue_guard}" | cut -d: -f1)"
[ -n "${rescue_route_add_line}" ] && [ -n "${rescue_owner_publish_line}" ] && \
	[ "${rescue_route_add_line}" -lt "${rescue_owner_publish_line}" ] && \
	grep -Fq "PRESERVE_ROUTE_ON_CLOSE='1'" "${rescue_guard}" || \
	die "rescue route publication can delete an indistinguishable race"
grep -Fq 'derive_primary_ap_path' "${rescue_guard}" && \
	grep -Fq 'primary_ap_eligible' "${rescue_guard}" && \
	grep -Fq '[ -n "$primary_section" ] || continue' "${rescue_guard}" && \
	grep -Fq "fail_closed 'network:no-active-primary-ap'" "${rescue_guard}" && \
	grep -Fq 'runtime_path_for_network' "${rescue_guard}" && \
	grep -Fq '"$UBUS_BIN" -S call' "${rescue_guard}" && \
	grep -Fq "fail_closed 'network:primary-ap-path-conflict'" "${rescue_guard}" || \
	die "rescue return path is not derived safely from enabled primary APs"
grep -Fq '/usr/sbin/cr6608-rescue-guard firewall-stop' "${rescue_firewall_init}" && \
	grep -Fq '"$FW4_BIN" stop' "${rescue_guard}" && \
	grep -Fq 'verify_fw4_absent' "${rescue_guard}" && \
	grep -Fq 'run_timed "$NFT_BIN" list tables' "${rescue_guard}" && \
	grep -Fq 'firewall_monitor_was_running' "${rescue_guard}" && \
	grep -Fq 'rescue_monitor_is_running' "${rescue_guard}" && \
	grep -Fq 'CR6608_RESCUE_GUARD=CLOSED mode=firewall-stop monitor=stopped' \
		"${rescue_guard}" && \
	grep -Fq 'QUIESCE_FILE="$STATE_DIR/operator-quiesced"' "${rescue_guard}" && \
	grep -Fq 'publish_quiesce_state || fail_closed' "${rescue_guard}" && \
	grep -Fq 'clear_quiesce_state || fail_closed' "${rescue_guard}" && \
	! grep -Eq '(^|[[:space:]])fw4[[:space:]]+flush([[:space:]]|$)' \
		"${rescue_firewall_init}" "${rescue_guard}" || \
	die "direct firewall stop can flush product nft tables or bypass rescue serialization"
rescue_quiesce_clear_line="$(grep -n -m1 'clear_quiesce_state || fail_closed' \
	"${rescue_guard}" | cut -d: -f1)"
rescue_final_verify_line="$(grep -n 'verify_ruleset_snapshot || fail_closed' \
	"${rescue_guard}" | tail -n1 | cut -d: -f1)"
[ -n "${rescue_quiesce_clear_line}" ] && [ -n "${rescue_final_verify_line}" ] && \
	[ "${rescue_final_verify_line}" -lt "${rescue_quiesce_clear_line}" ] || \
	die "explicit rescue start clears quiesce before full activation verification"
grep -Fq 'procd_set_param command "$GUARD" monitor' "${rescue_init}" && \
	grep -Fq 'procd_set_param respawn 10 2 0' "${rescue_init}" && \
	grep -Fq 'procd_open_instance "$RESCUE_INSTANCE"' "${rescue_init}" && \
	grep -Fq 'service_running "$rescue_running_instance"' "${rescue_init}" && \
	grep -Fq 'rescue_process_start_ticks()' "${rescue_init}" && \
	grep -Fq '"$GUARD" start' "${rescue_init}" && \
	grep -Fq 'service_started()' "${rescue_init}" && \
	grep -Fq 'rescue_instance_running "$RESCUE_INSTANCE"' "${rescue_init}" && \
	grep -Fq "PROCD_SERVICE='cr6608-rescue-guard'" "${rescue_init}" && \
	grep -Fq ".instances['\$rescue_running_instance'].running" "${rescue_init}" && \
	grep -Fq 'RESCUE_START_PREPARED' "${rescue_init}" && \
	grep -Fq 'RESCUE_REGISTRATION_ATTEMPTS=30' "${rescue_init}" && \
	grep -Fq '"$GUARD" quiesce' "${rescue_init}" && \
	grep -Fq 'service_stopped()' "${rescue_init}" && \
	grep -Fq '"$GUARD" close' "${rescue_init}" || \
	die "rescue monitor is not procd-supervised with bounded respawn"
rescue_start_quiesce_line="$(grep -n -m1 '"$GUARD" quiesce' \
	"${rescue_init}" | cut -d: -f1)"
rescue_procd_open_line="$(grep -n -m1 'procd_open_instance' \
	"${rescue_init}" | cut -d: -f1)"
rescue_procd_publish_line="$(grep -n -m1 'procd_close_instance' \
	"${rescue_init}" | cut -d: -f1)"
rescue_start_activate_line="$(grep -n -m1 '"$GUARD" start' \
	"${rescue_init}" | cut -d: -f1)"
[ -n "${rescue_start_quiesce_line}" ] && \
	[ "${rescue_start_quiesce_line}" -lt "${rescue_procd_open_line}" ] && \
	[ "${rescue_procd_publish_line}" -lt "${rescue_start_activate_line}" ] || \
	die "rescue address can activate before procd monitor publication"
for rescue_hotplug in "${rescue_iface_hotplug}" "${rescue_net_hotplug}"; do
	grep -Fq '"$INIT" running' "${rescue_hotplug}" && \
		grep -Fq '"$INIT" reload' "${rescue_hotplug}" && \
		! grep -Fq '"$INIT" start' "${rescue_hotplug}" || \
		die "rescue hotplug can activate without monitor/quiesce ownership"
done
grep -Fq '/etc/init.d/cr6608-rescue-guard enable' "${rescue_runtime_defaults}" && \
	! grep -Fq '/etc/init.d/cr6608-rescue-guard start' "${rescue_runtime_defaults}" || \
	die "first-boot UCI defaults start rescue before netifd/AP readiness"
grep -Fq '"$INIT" running' "${rescue_firewall_include}" && \
	grep -Fq '"$INIT" reload' "${rescue_firewall_include}" && \
	! grep -Fq '"$INIT" start' "${rescue_firewall_include}" && \
	grep -Fq '"$GUARD" close' "${rescue_firewall_include}" && \
	grep -Fq '75) exit 0' "${rescue_firewall_include}" && \
	grep -Fq "option path '/usr/libexec/cr6608-rescue-firewall-include'" "${rescue_firewall}" && \
	grep -Fq "option fw4_compatible '1'" "${rescue_firewall}" || \
	die "firewall reload does not restore monitored rescue or close before enable"
grep -Fq "network.wlanrescue.proto='none'" "${rescue_migration}" && \
	grep -Fq "network.wlanrescue.cr6608_owner=\"\$RESCUE_CONFIG_OWNER\"" \
		"${rescue_migration}" && \
	grep -Fq 'delete network.cr6608_rescue_dev' "${rescue_migration}" && \
	grep -Fq 'uci -P "$MIGRATION_UCI_SAVEDIR"' "${rescue_migration}" && \
	grep -Fq 'uci -t "$MIGRATION_UCI_SAVEDIR" commit' "${rescue_migration}" && \
	grep -Fq "uhttpd.main.rfc1918_filter='1'" "${rescue_migration}" || \
	die "rescue upgrade migration lacks private addressless ownership staging"
! grep -Eq '/etc/init.d/(network|firewall|uhttpd) (reload|restart)' \
	"${rescue_migration}" || \
	die "rescue UCI-default migration starts services before normal boot ordering"
! grep -Fq 'ifdown wlanrescue' "${rescue_migration}" || \
	die "rescue migration can take down an untrusted preserved binding"
grep -Fq "LEGACY_RESCUE_IP='169.254.66.1'" "${rescue_migration}" && \
	grep -Fq '"$RESCUE_GUARD" close' "${rescue_migration}" && \
	grep -Fq 'RESCUE_PACKET_MARK=' "${rescue_migration}" && \
	grep -Fq 'addr show dev "$old_rescue_device"' "${rescue_migration}" && \
	grep -Fq 'proto "$RESCUE_ROUTE_PROTO" dev "$old_rescue_device"' "${rescue_migration}" && \
	grep -Fq 'src "$RESCUE_IP" scope link proto "$RESCUE_ROUTE_PROTO"' "${rescue_migration}" || \
	die "rescue migration cleanup is not restricted to known addresses and exact route"
! grep -Fq 'old_rescue_ip=' "${rescue_migration}" || \
	die "rescue migration trusts an arbitrary preserved ipaddr"
! grep -Eq 'nft .*delete table|nft .*flush table' "${rescue_migration}" || \
	die "rescue migration directly removes its deny boundary"
for rescue_writer in \
	"${rescue_network}" "${rescue_firewall}" "${uhttpd_config}" \
	"${rootfs_dir}/usr/sbin/smartap-bootstrap" \
	"${rootfs_dir}/usr/sbin/cr6608-quicksettings-apply" \
	"${rootfs_dir}/www/cgi-bin/dashctl"; do
	! grep -Fq '169.254.66.1' "${rescue_writer}" || \
		die "legacy rescue address remains in ${rescue_writer#${rootfs_dir}/}"
	! grep -Eq 'wlanrescue\.device=.*br-lan' "${rescue_writer}" || \
		die "wired bridge rescue assignment remains in ${rescue_writer#${rootfs_dir}/}"
done
[ "$(grep -Fc '169.254.66.1' "${rescue_guard}")" -eq 1 ] && \
	grep -Fq 'CR6608_RESCUE_LEGACY_BRIDGE_ARP_IN' "${rescue_guard}" && \
	grep -Fq 'CR6608_RESCUE_LEGACY_INET_IN' "${rescue_guard}" && \
	! grep -Fq 'CR6608_RESCUE_LEGACY_BRIDGE_IP_IN' "${rescue_guard}" || \
	die "legacy rescue denial is missing or black-holes separately routed traffic"
[ "$(grep -Fc '169.254.66.1' "${rescue_migration}")" -eq 1 ] || \
	die "legacy rescue address has a non-migration use"
for rescue_stop_owner in \
	"${rootfs_dir}/usr/sbin/cr6608-quicksettings-apply" \
	"${rootfs_dir}/usr/sbin/cr6608-safe-apply" \
	"${rootfs_dir}/www/cgi-bin/dashctl"; do
	grep -Fq 'firewall-stop' "${rescue_stop_owner}" || \
		die "firewall stop owner bypasses serialized rescue restore: ${rescue_stop_owner#${rootfs_dir}/}"
done
[ ! -e "${rootfs_dir}/etc/hotplug.d/iface/99-rescue221" ] || \
	die "legacy rescue hotplug remains in rootfs"
[ ! -e "${rootfs_dir}/etc/uci-defaults/99-rescue221" ] || \
	die "legacy rescue defaults remain in rootfs"

operator_root_hash="$(awk -F: '$1 == "root" { print $2; exit }' "${rootfs_dir}/etc/shadow")"
if [ "${BUILD_PROFILE}" != retail ]; then
	case "${operator_root_hash}" in
		\$6\$CR6608v74op\$*) ;;
		*) die "operator rootfs lacks the requested SHA-512 recovery credential" ;;
	esac
	[ "$(printf %s "${operator_root_hash}" | sha256sum | awk '{print $1}')" = \
		'b6139c45d43bc9a0262c02a42d8784da248e498eda9434e3cb673dbd4cf40ebe' ] || \
		die "operator root credential hash changed unexpectedly"
else
	[ "${operator_root_hash}" = '!' ] || \
		die "generic Retail-v1 root account is not locked"
	[ "$(awk -F: '$1 == "root" { print NF; count++ } END { if (count != 1) exit 1 }' \
		"${rootfs_dir}/etc/shadow")" = 9 ] || die "Retail root shadow record is malformed"
	grep -Fqx "	option password '!'" "${rootfs_dir}/etc/config/rpcd" || \
		die "generic Retail-v1 Web account is not locked"
	! grep -Eq '\$[156y]\$' "${rootfs_dir}/etc/config/rpcd" || \
		die "Retail-v1 rpcd config embeds a reusable password verifier"
	grep -Fqx "RPCD_ROOT_PASSWORD='!'" \
		"${rootfs_dir}/etc/uci-defaults/99-cr6608-preserved-config-v2" || \
		die "Retail-v1 migration does not lock the legacy Web verifier"
	! grep -Fq '$6$CR6608dashAdm$' \
		"${rootfs_dir}/etc/uci-defaults/99-cr6608-preserved-config-v2" || \
		die "Retail-v1 migration embeds the retired shared Web verifier"
fi
grep -Fq "option ttylogin '1'" "${rootfs_dir}/etc/config/system" || \
	die "operator rootfs does not password-gate the serial console"
retail_provision="${rootfs_dir}/usr/sbin/cr6608-retail-provision"
retail_audit="${rootfs_dir}/usr/sbin/cr6608-retail-audit"
retail_radio_audit="${rootfs_dir}/usr/sbin/cr6608-retail-radio-audit"
root_pass_migration="${rootfs_dir}/etc/uci-defaults/99-cr6608-root-pass"
secure_console_migration="${rootfs_dir}/etc/uci-defaults/99-cr6608-secure-console"
preserved_config_migration="${rootfs_dir}/etc/uci-defaults/99-cr6608-preserved-config-v2"
grep -Fq -- '--root-password-file' "${retail_provision}" || \
	die "retail provisioner lacks the root-only password-file interface"
grep -Fq -- '--wifi-key-file' "${retail_provision}" || \
	die "retail provisioner lacks the root-only Wi-Fi-key-file interface"
grep -Fq -- '--web-password-file' "${retail_provision}" || \
	die "retail provisioner lacks the root-only Web-password-file interface"
grep -Fq -- '--web-password-file' "${retail_audit}" || \
	die "retail audit lacks credential-backed Web verification"
grep -Fq -- '--wifi-key-file' "${retail_audit}" || \
	die "retail audit lacks exact Wi-Fi credential verification"
grep -Fq -- '--root-password-file' "${retail_audit}" || \
	die "retail audit lacks manufactured root credential verification"
grep -Fq -- '--market-country' "${retail_provision}" || \
	die "retail provisioner does not bind the manufacturing market"
grep -Fq 'sale_ready=NO radio_policy=LAB_ARTIFACT_BLOCKED' \
	"${retail_provision}" || \
	die "lab credential provisioning can be confused with sale approval"
grep -Fq 'retail_security=PASS sale_ready=NO radio_policy=LAB_ARTIFACT_BLOCKED' \
	"${retail_audit}" || \
	die "security audit can be confused with sale approval"
grep -Fq 'security_provision=PASS sale_ready=NO radio_policy=retail-disabled-after-reboot reboot_required=1' \
	"${retail_provision}" || \
	die "Retail-v1 provisioner does not retain its post-reboot radio gate"
grep -Fq 'retail_security=PASS sale_ready=NO radio_policy=retail-disabled-after-reboot' \
	"${retail_audit}" || \
	die "Retail-v1 security audit does not retain its radio-policy boundary"
for artifact_bound_tool in "${retail_provision}" "${retail_audit}"; do
	grep -Fq "ARTIFACT_PROFILE='/rom/etc/cr6608-artifact-profile'" \
		"${artifact_bound_tool}" || die "retail tool is not bound to immutable artifact identity"
	grep -Fq "EXPECTED_RADIO_POLICY=" "${artifact_bound_tool}" || \
		die "retail tool does not derive its marker policy from the artifact"
done
for immutable_root_tool in "${retail_provision}" "${retail_audit}"; do
	grep -Fq '[ "$(/usr/bin/id -u 2>/dev/null)" = 0 ] || fail must_run_as_root' \
		"${immutable_root_tool}" || \
		die "retail security tool lacks an immutable root gate"
	grep -Fq "PATH='/usr/sbin:/usr/bin:/sbin:/bin'" "${immutable_root_tool}" || \
		die "retail security tool does not pin its command path"
	! grep -Fq 'CR6608_RETAIL_' "${immutable_root_tool}" || \
		die "retail security tool exposes production test overrides"
done
grep -Fq "AUDIT_BIN='/usr/sbin/cr6608-retail-audit'" "${retail_provision}" || \
	die "retail provisioner does not pin the post-provision security audit"
grep -Fq "CACHE_STATE_LIB='/usr/libexec/cr6608-dashboard-cache-state'" "${retail_provision}" && \
	grep -Fq "APPLY_LOCK='/var/run/cr6608-apply.lock'" "${retail_provision}" || \
	die "retail provisioner does not pin the shared configuration locks"
apply_lock_line="$(grep -n '^acquire_apply_lock || fail provisioning_busy$' "${retail_provision}" | cut -d: -f1)"
mutation_lock_line="$(grep -n '^cr6608_dashboard_cache_mutation_begin' "${retail_provision}" | cut -d: -f1)"
[ -n "${apply_lock_line}" ] && [ -n "${mutation_lock_line}" ] && \
	[ "${apply_lock_line}" -lt "${mutation_lock_line}" ] || \
	die "retail provisioner lock order differs from Quick Settings"
grep -Fq 'run_without_mutation_fds "$AUDIT_BIN"' "${retail_provision}" || \
	die "retail audit child can inherit the mutation flock"
grep -Fq "TLS_PROBE_BIN='/bin/uclient-fetch'" "${retail_audit}" || \
	die "retail security audit does not pin the TLS probe"
grep -Fq 'run_without_mutation_fds "$PASSWD_BIN" -a sha512 root' \
	"${retail_provision}" || die "retail root password is not forced to SHA-512-crypt"
grep -Fq 'stage_wifi_secret_values()' "${retail_provision}" && \
	grep -Fq 'run_without_mutation_fds "$UCI_BIN" -q batch' "${retail_provision}" && \
	! grep -Fq 'key=$wifi_key' "${retail_provision}" || \
	die "retail Wi-Fi plaintext can appear in a UCI process argument"
grep -Fq "RF_ACTIVE_PARAM='/sys/module/mt7915e/parameters/cr6608_rf_38dbm_active'" \
	"${retail_radio_audit}" || die "retail radio audit ignores actual 38 dBm driver state"
grep -Fq 'reg_raw="$($IW_BIN reg get 2>/dev/null)" || fail regulatory_runtime_unavailable' \
	"${retail_radio_audit}" || die "retail radio audit can ignore an iw failure"
grep -Fq 'radio_policy)" = retail-disabled-after-reboot' \
	"${retail_radio_audit}" || die "retail radio audit is not bound to a retail artifact marker"
grep -Fq 'external_rf_verification=REQUIRED artifact_sha_verification=REQUIRED' \
	"${retail_radio_audit}" || die "retail radio audit overstates its evidence boundary"
grep -Fq 'wireless_ap_per_phy' "${retail_radio_audit}" && \
	grep -Fq 'runtime_primary_ifname()' "${retail_radio_audit}" || \
	die "retail radio audit does not bind each marker AP to live per-PHY runtime"
grep -Fq '[ "$(/usr/bin/id -u 2>/dev/null)" = 0 ] || fail must_run_as_root' \
	"${retail_radio_audit}" || die "retail radio audit lacks an immutable root gate"
! grep -Fq 'CR6608_RETAIL_' "${retail_radio_audit}" || \
	die "retail radio audit exposes production test overrides"
grep -Fq 'retired_shared_root_credential' "${retail_audit}" || \
	die "retail audit does not reject the retired shared root credential"
grep -Fq 'retired_shared_web_credential' "${retail_audit}" || \
	die "retail audit does not reject the retired shared Web credential"
grep -Fq 'b6139c45d43bc9a0262c02a42d8784da248e498eda9434e3cb673dbd4cf40ebe' "${retail_audit}" || \
	die "retail audit does not reject the operator-build shared credential"
grep -Fq 'open_or_unsupported_encryption' "${retail_audit}" || \
	die "retail audit does not reject an open access point"
grep -Fq 'raw_hostapd_options' "${retail_audit}" && \
	grep -Fq 'raw_hostapd_bss_options' "${retail_audit}" && \
	grep -Fq 'wds_ap_role_not_allowlisted' "${retail_audit}" && \
	grep -Fq 'runtime_primary_ifname()' "${retail_audit}" || \
	die "retail audit permits raw hostapd/WDS overrides or unbound primary runtime"
for audit_contract in \
	console_password_login_disabled \
	https_listener_unexpected \
	https_cert_file_invalid \
	https_key_file_invalid \
	https_cert_parse_or_expired \
	https_key_invalid \
	https_cert_key_mismatch \
	https_ipv4_runtime_missing \
	ipv6_policy_probe_missing \
	ipv6_policy_runtime_failed \
	https_tls_handshake_failed \
	root_password_mismatch \
	provisioning_pending \
	pmf_disabled \
	protected_ap_missing; do
	grep -Fq "${audit_contract}" "${retail_audit}" || \
		die "retail audit lacks contract: ${audit_contract}"
done
grep -Fq 'find_primary_ap()' "${retail_provision}" || \
	die "retail provisioner does not discover primary APs dynamically"
grep -Fq 'primary_ap_base_eligible()' "${retail_provision}" && \
	grep -Fq 'wireless.${section}.device' "${retail_provision}" && \
	grep -Fq 'primary_ap_canonical_eligible()' "${retail_provision}" && \
	grep -Fq 'primary_ap_fallback_eligible()' "${retail_provision}" && \
	grep -Fq 'find_primary_ap radio0 wifinet0' "${retail_provision}" && \
	grep -Fq 'find_primary_ap radio1 wifinet1' "${retail_provision}" && \
	grep -Fq 'primary_ap_ambiguous' "${retail_provision}" || \
	die "retail primary AP selection is not canonical-first and ambiguity-safe"
grep -Fq 'hostapd_options' "${retail_provision}" && \
	grep -Fq 'hostapd_bss_options' "${retail_provision}" || \
	die "retail provisioning leaves opaque hostapd override channels"
grep -Fq 'wait_post_provision_audit()' "${retail_provision}" && \
	grep -Fq 'AUDIT_READY_MAX_ATTEMPTS=16' "${retail_provision}" && \
	grep -Fq 'post_provision_runtime_timeout' "${retail_provision}" || \
	die "retail provisioner lacks bounded asynchronous Wi-Fi readiness handling"
grep -Fq 'restore_previous_markers || {' "${retail_provision}" && \
	grep -Fq 'force_pending_state' "${retail_provision}" && \
	grep -Fq 'rollback_transaction 1 >/dev/null 2>&1 || true' "${retail_provision}" || \
	die "retail rollback failure can expose an old complete marker"
grep -Fq 'create_apply_claim()' "${retail_provision}" && \
	grep -Fq 'ownerless_lock_reclaimable()' "${retail_provision}" && \
	grep -Fq '.cr6608-apply.claim.' "${retail_provision}" || \
	die "retail apply-lock creation window is not crash-recoverable"
grep -Fq "system.@system[0].ttylogin=1" "${retail_provision}" || \
	die "retail provisioner does not password-gate serial login"
grep -Fq "trap 'signal_exit 143' TERM" "${retail_provision}" || \
	die "retail provisioner signal handler may continue after TERM"
grep -Fq 'restore_runtime || rollback_rc=1' "${retail_provision}" || \
	die "retail rollback does not verify old runtime restoration"
grep -Fq 'cp -pf "$backup/shadow" "$SHADOW_PATH" || restore_rc=1' \
	"${retail_provision}" || die "retail rollback does not verify restored files"
grep -Fq 'cp -pf "$backup/rpcd" "$RPCD_CONFIG" || restore_rc=1' \
	"${retail_provision}" || die "retail rollback does not restore rpcd"
grep -Fq 'if [ "$retail_provisioned" = 0 ]; then' \
	"${preserved_config_migration}" || \
	die "preserved-config migration does not isolate provisioned security state"
grep -Fq 'if [ -e "$PENDING_MARKER" ] || [ -L "$PENDING_MARKER" ]; then' \
	"${preserved_config_migration}" && \
	grep -Fq 'fail_closed_pending' "${preserved_config_migration}" || \
	die "preserved-config migration does not fail closed on pending provisioning"
grep -Fq "trap 'exit 1' HUP INT TERM" "${root_pass_migration}" || \
	die "root-password migration signal handler may continue"
grep -Fq "' \"\$shadow_file\" > \"\$tmp\" || exit 1" "${root_pass_migration}" || \
	die "root-password migration ignores awk or missing-root failure"
grep -Fq 'chmod 0600 "$tmp" || exit 1' "${root_pass_migration}" || \
	die "root-password migration ignores chmod failure"
grep -Fq 'mv -f "$tmp" "$shadow_file" || exit 1' "${root_pass_migration}" || \
	die "root-password migration ignores atomic replacement failure"
grep -Fq "[ \"\$board\" = 'xiaomi,mi-router-cr6608' ] || exit 0" \
	"${secure_console_migration}" || \
	die "secure-console migration is not scoped to the CR6608"
grep -Fq "''|x|\\!*|\\**) exit 0 ;;" "${secure_console_migration}" || \
	die "secure-console migration does not preserve locked-root provisioning"
grep -Fq '"$UCI_BIN" set "${uci_key}=1"' "${secure_console_migration}" || \
	die "secure-console migration does not enable password login"
grep -Fq '"$UCI_BIN" commit system' "${secure_console_migration}" || \
	die "secure-console migration does not persist its change"
grep -Fq 'rollback() {' "${secure_console_migration}" || \
	die "secure-console migration lacks a rollback path"
grep -Fq '[ "$("$UCI_BIN" -q get "$uci_key"' "${secure_console_migration}" || \
	die "secure-console migration does not verify the committed state"
grep -Fxq '/etc/cr6608-retail-provisioned' \
	"${rootfs_dir}/lib/upgrade/keep.d/cr6608-retail" || \
	die "settings-preserving sysupgrade loses the retail provisioning marker"
grep -Fxq '/etc/cr6608-retail-provisioning-pending' \
	"${rootfs_dir}/lib/upgrade/keep.d/cr6608-retail" || \
	die "settings-preserving sysupgrade loses the pending provisioning journal"
grep -Fxq '/etc/smartap-time-anchor' \
	"${rootfs_dir}/lib/upgrade/keep.d/cr6608-retail" || \
	die "settings-preserving sysupgrade loses the persistent time floor"
dashaction="${rootfs_dir}/www/cgi-bin/dashaction"
grep -Fq 'wifi_radio0)' "${dashaction}" || die "radio0 action is missing"
grep -Fq 'wifi_radio1)' "${dashaction}" || die "radio1 action is missing"
grep -Fq '/usr/sbin/cr6608-safe-wifi-reload 20 "$backup" "$radio"' \
	"${dashaction}" || die "radio actions bypass device-specific safe apply"
safe_wifi_reload="${rootfs_dir}/usr/sbin/cr6608-safe-wifi-reload"
grep -Fq 'case "$SCOPE" in' "${safe_wifi_reload}" || \
	die "radio action rollback helper does not validate its device scope"
grep -Fq 'run_bounded "$WIFI_COMMAND_TIMEOUT" "$WIFI_BIN" up "$SCOPE"' \
	"${safe_wifi_reload}" || \
	die "radio action apply does not use the bounded device-specific up path"
grep -Fq 'run_bounded "$WIFI_COMMAND_TIMEOUT" "$WIFI_BIN" down "$SCOPE"' \
	"${safe_wifi_reload}" || \
	die "radio action apply does not use the bounded device-specific down path"
grep -Fq 'run_bounded "$WIFI_COMMAND_TIMEOUT" "$WIFI_BIN" reload' \
	"${safe_wifi_reload}" || \
	die "all-radio apply does not use the bounded reload path"
grep -Fq 'cp -f "$BACKUP" /etc/config/wireless' "${safe_wifi_reload}" || \
	die "radio action rollback does not restore the saved wireless configuration"
grep -Fq 'apply_wifi_scope || restore_rc=1' "${safe_wifi_reload}" || \
	die "radio action rollback does not reapply the restored device scope"
grep -Fq 'wait_runtime_ready' "${safe_wifi_reload}" || \
	die "radio action rollback does not verify the restored runtime"
if grep -Fq 'wifi_toggle)' "${dashaction}"; then
	die "unsafe all-radio toggle is still present"
fi
grep -Fq 'txpower_applied_for_if()' "${rootfs_dir}/www/cgi-bin/dashapi2" || \
	die "runtime TX-power fallback is missing"
runtime_services_default="${rootfs_dir}/etc/uci-defaults/99-cr6608-runtime-services"
grep -Fqx '[ -x /etc/init.d/cr6608-rescue-guard ] || exit 1' \
	"${runtime_services_default}" && \
	grep -Fqx '/etc/init.d/cr6608-rescue-guard enable || exit 1' \
		"${runtime_services_default}" || \
	die "clean-flash rescue monitor is not enabled fail-closed"
! grep -Fq '/etc/init.d/cr6608-rescue-guard start' \
	"${runtime_services_default}" || \
	die "rescue monitor is started before netifd during UCI defaults"
grep -Fq 'for service in cr6608-ipv4-only smartap-qos cr6608-quicksettings cr6608-management-guard; do' \
	"${runtime_services_default}" || \
	die "clean-flash runtime service list is incomplete"
! grep -Eq '(enable|start).*(cr6608-dashboard-cache|cr6608-dashboard-prewarm)|cr6608-dashboard-(cache|prewarm).*(enable|start)' \
	"${runtime_services_default}" || \
	die "runtime defaults still activate removed dashboard prewarm"
for removed_dashboard_link in \
	/etc/rc.d/S99cr6608-dashboard-cache \
	/etc/rc.d/K99cr6608-dashboard-cache; do
	grep -Fq "${removed_dashboard_link}" "${runtime_services_default}" || \
		die "upgrade migration does not remove ${removed_dashboard_link}"
done
grep -Fq 'FAILURE_THRESHOLD=3' "${rootfs_dir}/usr/sbin/cr6608-management-guard" || \
	die "management guard does not require three consecutive failures"
grep -Fq '"$UHTTPD_INIT" restart' "${rootfs_dir}/usr/sbin/cr6608-management-guard" || \
	die "management guard lacks the bounded uhttpd-only recovery action"
if grep -Eq '/etc/init.d/network|wifi (reload|down|up)|ifdown|ifup|reboot' \
	"${rootfs_dir}/usr/sbin/cr6608-management-guard"; then
	die "management guard contains a network, Wi-Fi, or reboot recovery action"
fi
grep -Fq '"/etc/init.d/$service" enable || exit 1' \
	"${runtime_services_default}" || \
	die "clean-flash runtime services are not enabled fail-closed"
grep -Fq '"/etc/init.d/$service" start || exit 1' \
	"${runtime_services_default}" || \
	die "clean-flash runtime services are not started on the first boot"
security_service_default="${rootfs_dir}/etc/uci-defaults/97-cr6608-security"
security_runtime_hotplug="${rootfs_dir}/etc/hotplug.d/iface/98-cr6608-security-runtime"
grep -Fqx '[ -x /etc/init.d/cr6608-security ] || exit 1' \
	"${security_service_default}" || \
	die "clean-flash security service existence check is not fail-closed"
grep -Fqx '/etc/init.d/cr6608-security enable || exit 1' \
	"${security_service_default}" || \
	die "clean-flash security service enable is not fail-closed"
! grep -Eq '/etc/init.d/cr6608-security[[:space:]]+(start|restart|reload)' \
	"${security_service_default}" || \
	die "security runtime policy is applied before network/firewall startup"
grep -Fq 'ifup:lan|ifupdate:lan)' "${security_runtime_hotplug}" && \
	grep -Fq '/usr/sbin/cr6608-security-apply hotplug' \
		"${security_runtime_hotplug}" && \
	grep -A8 -F 'hotplug)' "${rootfs_dir}/usr/sbin/cr6608-security-apply" | \
		grep -Fq '/etc/init.d/cr6608-security enabled' || \
	die "first-boot security replay is not gated on live LAN and enabled state"
[ ! -e "${rootfs_dir}/etc/modprobe.d" ] && [ ! -L "${rootfs_dir}/etc/modprobe.d" ] || \
	die "stale /etc/modprobe.d path is present"
require_mode etc/uci-defaults/95-cr6608-enable-legacy-11b 755
grep -Fq 'legacy_rates=1' \
	"${rootfs_dir}/etc/uci-defaults/95-cr6608-enable-legacy-11b" ||
	die "rootfs lacks the requested 2.4 GHz legacy 802.11b policy"
if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	require_mode usr/sbin/cr6608-factory38-stage 755
	require_mode etc/cr6608-factory38-writegate.marker 644
	require_mode etc/uci-defaults/01-cr6608-factory38-maintenance 755
	[ -x "${rootfs_dir}/usr/sbin/flash_erase" ] ||
		die "maintenance rootfs lacks flash_erase"
	[ -x "${rootfs_dir}/usr/sbin/nandwrite" ] ||
		die "maintenance rootfs lacks nandwrite"
	if [ -L "${rootfs_dir}/usr/bin/flock" ]; then
		[ "$(readlink "${rootfs_dir}/usr/bin/flock")" = \
			'/usr/bin/util-linux-flock' ] ||
			die "maintenance rootfs flock alternative has an unexpected target"
		[ -x "${rootfs_dir}/usr/bin/util-linux-flock" ] ||
			die "maintenance rootfs lacks the util-linux flock target"
	else
		[ -x "${rootfs_dir}/usr/bin/flock" ] ||
			die "maintenance rootfs lacks flock"
	fi
else
	for forbidden_factory_path in \
		usr/sbin/cr6608-factory38-stage \
		etc/cr6608-factory38-writegate.marker \
		etc/uci-defaults/01-cr6608-factory38-maintenance; do
		[ ! -e "${rootfs_dir}/${forbidden_factory_path}" ] ||
			die "normal rootfs contains maintenance-only path: ${forbidden_factory_path}"
	done
fi

driver_list="${tmp_dir}/drivers.list0"
find "${rootfs_dir}/lib/modules" -type f -name 'mt7915e.ko' -print0 > \
	"${driver_list}" || die "could not enumerate mt7915e modules"
mapfile -d '' -t driver_files < "${driver_list}"
[ "${#driver_files[@]}" -eq 1 ] || \
	die "expected exactly one built mt7915e.ko, found ${#driver_files[@]}"
driver_file="${driver_files[0]}"
grep -aFq 'CR6608-RF-38DBM LAB enabled' "${driver_file}" || \
	die "built mt7915e driver lacks the gated Factory-38 marker"
grep -aFq 'audited volatile 38 dBm targets cover' \
	"${driver_file}" || \
	die "built mt7915e driver lacks the volatile Factory-38 target path"
grep -aFq 'DFS, SAR, per-rate and thermal protection remain active' \
	"${driver_file}" || \
	die "built mt7915e driver lacks the retained-protection marker"
grep -aFq 'all eight 5 GHz EEPROM channel groups' "${driver_file}" || \
	die "built mt7915e driver lacks the all-5 GHz-channel-groups marker"
grep -aFq 'every channel change requires MCU SKU readback' \
	"${driver_file}" || \
	die "built mt7915e driver lacks the per-channel MCU-readback marker"
grep -aFq 'rate-SKU MCU witness verified' "${driver_file}" || \
	die "built mt7915e driver lacks verified MCU SKU readback"
grep -aFq 'SKU rollback verification failed' "${driver_file}" || \
	die "built mt7915e driver lacks verified rollback handling"
grep -aFq 'cr6608_rf_band0_mcu_result' "${driver_file}" || \
	die "built mt7915e driver lacks read-only MCU telemetry"
grep -aFq 'cr6608_rf_38dbm' "${driver_file}" || \
	die "built mt7915e driver lacks the LAB-38 parameter"
grep -aFq 'cr6608_factory38_persisted_match' "${driver_file}" ||
	die "built mt7915e driver lacks read-only persisted-Factory telemetry"
grep -aFq 'activating the audited volatile 38 dBm target override' "${driver_file}" ||
	die "built mt7915e driver lacks the volatile override marker"
grep -aFq 'CR6608-RF firmware EEPROM shadow active' "${driver_file}" ||
	die "built mt7915e driver lacks the firmware EEPROM shadow marker"
grep -aFq 'CR6608 DTS property and cr6608_rf_38dbm=1 are both required' \
	"${driver_file}" || \
	die "built mt7915e driver lacks the armed-request rejection marker"
for muru_driver_marker in \
	'CR6608 MediaTek MURU candidate enabled' \
	'cr6608_muru_mask' \
	'candidate_allowed=' \
	'candidate_mask=' \
	'candidate_ul_mumimo=' \
	'sta_rec_response_ok=' \
	'sta_rec_timeout=' \
	'fault_latched='; do
	grep -aFq "${muru_driver_marker}" "${driver_file}" ||
		die "built mt7915e driver lacks MURU marker: ${muru_driver_marker}"
done

eeprom_source_list="${tmp_dir}/mt7915-eeprom-sources.list0"
find "${OPENWRT_DIR}/build_dir" -type f \
	-path '*/mt76-*/mt7915/eeprom.c' -print0 > "${eeprom_source_list}" || \
	die "could not enumerate prepared mt7915 EEPROM sources"
mapfile -d '' -t eeprom_sources < "${eeprom_source_list}"
[ "${#eeprom_sources[@]}" -eq 1 ] || \
	die "expected exactly one prepared mt7915/eeprom.c, found ${#eeprom_sources[@]}"
grep -Fq 'CR6608_FACTORY38_TARGET_2G' "${eeprom_sources[0]}" || \
	die "prepared mt7915 EEPROM source lacks the exact 2.4 GHz persisted target"
grep -Fq 'CR6608_FACTORY38_TARGET_5G' "${eeprom_sources[0]}" || \
	die "prepared mt7915 EEPROM source lacks the exact 5 GHz persisted target"
grep -Fq 'target_power = CR6608_FACTORY38_TARGET_2G;' "${eeprom_sources[0]}" &&
	grep -Fq 'target_power = CR6608_FACTORY38_TARGET_5G;' "${eeprom_sources[0]}" &&
	grep -Eq '^#define[[:space:]]+CR6608_FACTORY38_SAFE_DELTA_2G[[:space:]]+6$' "${eeprom_sources[0]}" &&
	grep -Eq '^#define[[:space:]]+CR6608_FACTORY38_SAFE_DELTA_5G[[:space:]]+4$' "${eeprom_sources[0]}" &&
	grep -Fq 'activating the audited volatile 38 dBm target override' "${eeprom_sources[0]}" &&
	grep -Fq 'if (mt7915_cr6608_rf_request_armed(dev))' "${eeprom_sources[0]}" &&
	grep -Fq 'return CR6608_FACTORY38_SAFE_DELTA_2G;' "${eeprom_sources[0]}" &&
	grep -Fq 'return CR6608_FACTORY38_SAFE_DELTA_5G;' "${eeprom_sources[0]}" ||
	die "prepared mt7915 EEPROM source lacks the volatile target and rate-delta override"
grep -Eq '^#define[[:space:]]+CR6608_FACTORY38_CHAINS[[:space:]]+4$' \
	"${eeprom_sources[0]}" || \
	die "prepared mt7915 EEPROM source lacks the exact four-chain Factory gate"
grep -Eq '^#define[[:space:]]+CR6608_FACTORY38_5G_GROUPS[[:space:]]+8$' \
	"${eeprom_sources[0]}" || \
	die "prepared mt7915 EEPROM source lacks all eight 5 GHz channel groups"
grep -Eq 'for \(chain = 0; chain < CR6608_FACTORY38_CHAINS; chain\+\+\)' \
	"${eeprom_sources[0]}" || \
	die "prepared mt7915 EEPROM source does not validate every RF chain"
grep -Eq 'for \(group = 0; group < CR6608_FACTORY38_5G_GROUPS; group\+\+\)' \
	"${eeprom_sources[0]}" || \
	die "prepared mt7915 EEPROM source does not validate every 5 GHz group"
grep -Fq 'mt7915_cr6608_factory38_raw_match' "${eeprom_sources[0]}" ||
	die "prepared mt7915 EEPROM source lacks the raw persisted-byte gate"
grep -Fq 'mt7915_cr6608_rf_request_enabled(dev)' "${eeprom_sources[0]}" || \
	die "prepared Factory-38 EEPROM source lacks the CR6608 gate"
mcu_source_list="${tmp_dir}/mt7915-mcu-sources.list0"
find "${OPENWRT_DIR}/build_dir" -type f \
	-path '*/mt76-*/mt7915/mcu.c' -print0 > "${mcu_source_list}" || \
	die "could not enumerate prepared mt7915 MCU sources"
mapfile -d '' -t mcu_sources < "${mcu_source_list}"
[ "${#mcu_sources[@]}" -eq 1 ] || \
	die "expected exactly one prepared mt7915/mcu.c, found ${#mcu_sources[@]}"
grep -Fq 'bool enabled = mt7915_cr6608_rf_request_armed(dev);' \
	"${mcu_sources[0]}" || \
	die "prepared mt7915 MCU source lacks the armed volatile override"
grep -Fq 'mt7915_cr6608_factory38_raw_match(dev);' "${mcu_sources[0]}" || \
	die "prepared mt7915 MCU source lacks persisted Factory telemetry"
for muru_mcu_marker in \
	'mask &= CR6608_MURU_OFDMA_DL | CR6608_MURU_MUMIMO_DL;' \
	'muru->cfg.ofdma_ul_en = !!(mask & CR6608_MURU_OFDMA_UL);' \
	'muru->cfg.mimo_ul_en = !is_mt7915(&dev->mt76) &&' \
	'if (muru->mimo_ul.full_ul_mimo) {' \
	'muru->cfg.mimo_ul_en = true;' \
	'!is_mt7915(&dev->mt76) &&' \
	'(cr6608_tx_mask & CR6608_MURU_UL_MASK);' \
	'mt7915_cr6608_muru_sta_rec_attempt(dev);' \
	'mt7915_cr6608_muru_sta_rec_response(dev,' \
	'mt7915_cr6608_muru_sta_rec_failure(dev,'; do
	grep -Fq "${muru_mcu_marker}" "${mcu_sources[0]}" || \
		die "prepared mt7915 MCU source lacks MURU invariant: ${muru_mcu_marker}"
done
if grep -Eq 'MURU_(CFG_DLUL_LIMIT|SET_DLUL_EN)|mt7915_mcu_set_cr6608_ul_muru' \
	"${mcu_sources[0]}"; then
	die "prepared mt7915 MCU source contains an unverified global MURU command"
fi
muru_attempt_line="$(grep -nF 'mt7915_cr6608_muru_sta_rec_attempt(dev);' \
	"${mcu_sources[0]}" | head -n 1 | cut -d: -f1)"
muru_response_line="$(grep -nF 'mt7915_cr6608_muru_sta_rec_response(dev,' \
	"${mcu_sources[0]}" | head -n 1 | cut -d: -f1)"
muru_send_line="$(grep -nF 'ret = mt76_mcu_skb_send_msg' \
	"${mcu_sources[0]}" | cut -d: -f1 | awk \
	-v attempt="${muru_attempt_line}" -v response="${muru_response_line}" \
	'$1 > attempt && $1 < response { print; exit }')"
[ -n "${muru_attempt_line}" ] && [ -n "${muru_send_line}" ] && \
	[ -n "${muru_response_line}" ] && \
	[ "${muru_attempt_line}" -lt "${muru_send_line}" ] && \
	[ "${muru_send_line}" -lt "${muru_response_line}" ] || \
	die "prepared mt7915 MCU response telemetry is not ordered around the synchronous send"
debugfs_source_list="${tmp_dir}/mt7915-debugfs-sources.list0"
find "${OPENWRT_DIR}/build_dir" -type f \
	-path '*/mt76-*/mt7915/debugfs.c' -print0 > "${debugfs_source_list}" || \
	die "could not enumerate prepared mt7915 debugfs sources"
mapfile -d '' -t debugfs_sources < "${debugfs_source_list}"
[ "${#debugfs_sources[@]}" -eq 1 ] || \
	die "expected exactly one prepared mt7915/debugfs.c, found ${#debugfs_sources[@]}"
grep -Fq 'if (mt7915_cr6608_rf_request_armed(dev))' \
	"${debugfs_sources[0]}" &&
	grep -Fq 'return -EPERM;' "${debugfs_sources[0]}" ||
	die "prepared mt7915 debugfs source permits an unverified armed SKU write"
for muru_debugfs_marker in \
	'candidate_allowed=%u' \
	'candidate_ul_enabled=%u' \
	'candidate_mask=%u' \
	'candidate_dl_ofdma=%u' \
	'candidate_ul_ofdma=%u' \
	'candidate_dl_mumimo=%u' \
	'candidate_ul_mumimo=%u' \
	'sta_rec_response_ok=%d' \
	'spin_lock_irqsave(&dev->cr6608_muru_telemetry_lock, flags);'; do
	grep -Fq "${muru_debugfs_marker}" "${debugfs_sources[0]}" || \
		die "prepared mt7915 debugfs source lacks coherent candidate telemetry: ${muru_debugfs_marker}"
done
header_source_list="${tmp_dir}/mt7915-header-sources.list0"
find "${OPENWRT_DIR}/build_dir" -type f \
	-path '*/mt76-*/mt7915/mt7915.h' -print0 > "${header_source_list}" || \
	die "could not enumerate prepared mt7915 headers"
mapfile -d '' -t header_sources < "${header_source_list}"
[ "${#header_sources[@]}" -eq 1 ] || \
	die "expected exactly one prepared mt7915/mt7915.h, found ${#header_sources[@]}"
grep -Fq 'bool mt7915_cr6608_factory38_raw_match(struct mt7915_dev *dev);' \
	"${header_sources[0]}" || \
	die "prepared mt7915 header lacks the persisted-Factory gate declaration"
grep -Fq 'bool mt7915_cr6608_rf_request_armed(struct mt7915_dev *dev);' \
	"${header_sources[0]}" || \
	die "prepared mt7915 header lacks the armed Factory request declaration"
for muru_header_marker in \
	'spinlock_t cr6608_muru_telemetry_lock;' \
	'mt7915_cr6608_muru_sta_rec_attempt' \
	'mt7915_cr6608_muru_sta_rec_response' \
	'mt7915_cr6608_muru_sta_rec_failure' \
	'mt7915_cr6608_muru_fault_latch'; do
	grep -Fq "${muru_header_marker}" "${header_sources[0]}" || \
		die "prepared mt7915 header lacks MURU telemetry/fault primitive: ${muru_header_marker}"
done
if grep -aEq 'cr6608_rf_(30|35)dbm|CR6608-RF-(30|35)DBM' "${driver_file}"; then
	die "built mt7915e driver contains a stale 30/35 dBm marker"
fi
if grep -RIsaEq 'cr6608_rf_(30|35)dbm|CR6608-RF-(30|35)DBM' "${rootfs_dir}"; then
	die "rootfs contains a stale 30/35 dBm driver gate"
fi

kernel_config_list="${tmp_dir}/kernel-configs.list0"
find "${OPENWRT_DIR}/build_dir" -type f \
	-path '*/linux-ramips_mt7621/linux-6.12.94/.config' -print0 > \
	"${kernel_config_list}" || die "could not enumerate built kernel configs"
mapfile -d '' -t built_kernel_configs < "${kernel_config_list}"
[ "${#built_kernel_configs[@]}" -eq 1 ] || \
	die "expected exactly one built mt7621 kernel config, found ${#built_kernel_configs[@]}"
grep -Fqx 'CONFIG_SERIAL_8250=y' "${built_kernel_configs[0]}" || \
	die "built kernel unexpectedly removed the 8250 UART driver"
grep -Fqx 'CONFIG_SERIAL_8250_CONSOLE=y' "${built_kernel_configs[0]}" || \
	die "built kernel does not expose the stock 8250 serial console"
for rescue_nft_bridge_kernel_config in \
	"${RESCUE_NFT_BRIDGE_KERNEL_CONFIGS[@]}"; do
	grep -Fqx "${rescue_nft_bridge_kernel_config}" \
		"${built_kernel_configs[0]}" || \
		die "built kernel lacks exact nft bridge config: ${rescue_nft_bridge_kernel_config}"
done

dtb_list="${tmp_dir}/dtbs.list0"
find "${OPENWRT_DIR}/build_dir" -type f \
	-name 'image-mt7621_xiaomi_mi-router-cr6608.dtb' -print0 > \
	"${dtb_list}" || die "could not enumerate built CR6608 DTBs"
mapfile -d '' -t built_dtbs < "${dtb_list}"
[ "${#built_dtbs[@]}" -eq 1 ] || \
	die "expected exactly one built CR6608 DTB, found ${#built_dtbs[@]}"
grep -aFq 'console=ttyS0,115200n8' "${built_dtbs[0]}" || \
	die "built CR6608 DTB lacks the stock 115200 serial console"
grep -aFq 'mediatek,cr6608-lab-txpower-38dbm' "${built_dtbs[0]}" || \
	die "built CR6608 DTB lacks the RF request property"
if [ "${BUILD_PROFILE}" = ul-lab ] || [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
	grep -aFq 'mediatek,cr6608-experimental-ul-muru' "${built_dtbs[0]}" ||
		die "built UL-lab CR6608 DTB lacks the experimental MURU RAM gate"
else
	! grep -aFq 'mediatek,cr6608-experimental-ul-muru' "${built_dtbs[0]}" ||
		die "built Stable/Retail CR6608 DTB exposes the experimental MURU RAM gate"
fi
if grep -aFq 'console=ttynull' "${built_dtbs[0]}"; then
	die "built CR6608 DTB disables the serial console"
fi

# The CR6608 uImages contain a small loader followed by an LZMA-alone stream.
# Validate both legacy uImage envelopes and bind the compiled DTB to the
# sysupgrade kernel and to the RAM-boot initramfs that is actually published.
# The initramfs cpio is then parsed from that same decompressed kernel.  Every
# staged-overlay entry and every Factory writer command dependency is resolved
# inside that archive, so none can be inferred from a staging directory or a
# different image.
kernel_dtb="${tmp_dir}/kernel-embedded-cr6608.dtb"
initramfs_dtb="${tmp_dir}/initramfs-embedded-cr6608.dtb"
python3 - "${kernel_member}" "${INITRAMFS_IMAGE}" "${built_dtbs[0]}" \
	"${kernel_dtb}" "${initramfs_dtb}" "${STAGED_OVERLAY}" \
	"${FACTORY38_BUILD_MODE}" "${EXPECTED_KERNEL_RELEASE}" \
	"${RESCUE_NFT_BRIDGE_CORE_MODULE}" "${RESCUE_NFT_BRIDGE_MODULES_CSV}" \
	"${RESCUE_NFT_BRIDGE_AUTOLOAD_FILE}" \
	"${RESCUE_NFT_BRIDGE_AUTOLOADS_CSV}" <<'PY'
import binascii
import lzma
import os
import pathlib
import stat
import struct
import sys
import zlib

(
    kernel_path,
    initramfs_path,
    built_dtb_path,
    kernel_dtb_path,
    initramfs_dtb_path,
    overlay_path,
) = map(pathlib.Path, sys.argv[1:7])
build_mode = sys.argv[7]
expected_kernel_release = sys.argv[8]
rescue_nft_bridge_core_module = sys.argv[9]
rescue_nft_bridge_modules = tuple(sys.argv[10].split(","))
rescue_nft_bridge_autoload_file = sys.argv[11]
rescue_nft_bridge_autoloads = tuple(sys.argv[12].split(","))
if (
    not expected_kernel_release
    or not rescue_nft_bridge_core_module
    or not rescue_nft_bridge_modules
    or any(not name for name in rescue_nft_bridge_modules)
    or len(set(rescue_nft_bridge_modules)) != len(rescue_nft_bridge_modules)
    or not rescue_nft_bridge_autoload_file
    or not rescue_nft_bridge_autoloads
    or any(not name for name in rescue_nft_bridge_autoloads)
    or len(set(rescue_nft_bridge_autoloads)) != len(rescue_nft_bridge_autoloads)
):
    raise SystemExit("IMAGE GATE FAILED: invalid nft bridge inspection contract")
built_dtb = built_dtb_path.read_bytes()
EXPECTED_UIMAGE_LOAD = 0x80001000
EXPECTED_UIMAGE_ENTRY = 0x80001000
EXPECTED_UIMAGE_NAME = f"MIPS OpenWrt Linux-{expected_kernel_release}"
MAX_UNPACKED_BYTES = 256 * 1024 * 1024
MAX_CPIO_SYMLINKS = 40
CPIO_COMMAND_PATH = ("/usr/sbin", "/usr/bin", "/sbin", "/bin")
FACTORY38_STAGE_COMMANDS = (
    "awk",
    "bridge",
    "cat",
    "chmod",
    "cp",
    "dd",
    "dirname",
    "flash_erase",
    "flock",
    "grep",
    "ip",
    "iw",
    "jsonfilter",
    "mkdir",
    "nandwrite",
    "rm",
    "sha256sum",
    "sleep",
    "sync",
    "touch",
    "tr",
    "ubus",
    "wc",
    "wifi",
)
SHADOW_PACKAGE_ACCOUNTS = (
    b"ntp:x:0:0:99999:7:::\n"
    b"dnsmasq:x:0:0:99999:7:::\n"
    b"lldp:x:0:0:99999:7:::\n"
    b"logd:x:0:0:99999:7:::\n"
    b"ubus:x:0:0:99999:7:::\n"
)


def fail(message):
    raise SystemExit(f"IMAGE GATE FAILED: {message}")


def read_uimage(path, label):
    image = path.read_bytes()
    if len(image) <= 64:
        fail(f"{label} is not a complete uImage")
    header = bytearray(image[:64])
    try:
        magic, header_crc, _timestamp, payload_size, load, entry, data_crc, os_id, arch_id, image_type, compression, raw_name = struct.unpack(
            ">7I4B32s", header
        )
    except struct.error as exc:
        fail(f"{label} uImage header cannot be decoded: {exc}")
    if magic != 0x27051956:
        fail(f"{label} lacks the legacy uImage magic")
    header[4:8] = b"\0\0\0\0"
    if binascii.crc32(header) & 0xFFFFFFFF != header_crc:
        fail(f"{label} uImage header CRC is invalid")
    if payload_size != len(image) - 64:
        fail(
            f"{label} uImage payload size is {payload_size}, expected {len(image) - 64}"
        )
    payload = image[64:]
    if binascii.crc32(payload) & 0xFFFFFFFF != data_crc:
        fail(f"{label} uImage payload CRC is invalid")
    if (os_id, arch_id, image_type) != (5, 5, 2):
        fail(
            f"{label} uImage OS/architecture/type is "
            f"{os_id}/{arch_id}/{image_type}, expected Linux/MIPS/kernel"
        )
    if compression != 0:
        fail(f"{label} uImage compression is {compression}, expected none (0)")
    if load != EXPECTED_UIMAGE_LOAD or entry != EXPECTED_UIMAGE_ENTRY:
        fail(
            f"{label} uImage load/entry is {load:#010x}/{entry:#010x}, expected "
            f"{EXPECTED_UIMAGE_LOAD:#010x}/{EXPECTED_UIMAGE_ENTRY:#010x}"
        )
    raw_name_value, separator, name_padding = raw_name.partition(b"\0")
    if separator and any(name_padding):
        fail(f"{label} uImage name has non-zero bytes after its terminator")
    try:
        name = raw_name_value.decode("ascii")
    except UnicodeDecodeError:
        fail(f"{label} uImage name is not ASCII")
    if name != EXPECTED_UIMAGE_NAME:
        fail(
            f"{label} uImage name is {name!r}, expected {EXPECTED_UIMAGE_NAME!r}"
        )
    print(f"{label}_uimage_payload_bytes={payload_size}")
    print(f"{label}_uimage_name={name}")
    return payload


def validate_factory_dtb(dtb, mode):
    if len(dtb) < 40:
        fail("built CR6608 DTB is shorter than its fixed header")
    try:
        (
            magic,
            total_size,
            struct_offset,
            strings_offset,
            reserve_offset,
            version,
            last_compatible_version,
            _boot_cpu,
            strings_size,
            struct_size,
        ) = struct.unpack_from(">10I", dtb)
    except struct.error as exc:
        fail(f"built CR6608 DTB header cannot be decoded: {exc}")
    if magic != 0xD00DFEED:
        fail("built CR6608 DTB lacks the flattened-device-tree magic")
    if total_size != len(dtb):
        fail(
            f"built CR6608 DTB total size is {total_size}, expected {len(dtb)}"
        )
    if version < 17 or last_compatible_version > 16:
        fail(
            "built CR6608 DTB has an unsupported version pair "
            f"{version}/{last_compatible_version}"
        )

    def region(offset, size, description, alignment=4):
        if offset < 40 or offset % alignment or size > total_size - offset:
            fail(f"built CR6608 DTB has invalid {description} bounds")
        return offset, offset + size

    struct_start, struct_end = region(
        struct_offset, struct_size, "structure block"
    )
    strings_start, strings_end = region(
        strings_offset, strings_size, "strings block", alignment=1
    )
    if max(struct_start, strings_start) < min(struct_end, strings_end):
        fail("built CR6608 DTB structure and strings blocks overlap")
    if reserve_offset < 40 or reserve_offset % 8:
        fail("built CR6608 DTB has an invalid reservation-map offset")
    reserve_cursor = reserve_offset
    for _ in range(4096):
        if reserve_cursor + 16 > total_size:
            fail("built CR6608 DTB reservation map is unterminated")
        address, size = struct.unpack_from(">QQ", dtb, reserve_cursor)
        reserve_cursor += 16
        if address == 0 and size == 0:
            break
    else:
        fail("built CR6608 DTB reservation map has too many entries")

    strings = dtb[strings_start:strings_end]

    def property_name(name_offset):
        if name_offset >= len(strings):
            fail("built CR6608 DTB property name offset is out of bounds")
        terminator = strings.find(b"\0", name_offset)
        if terminator < 0:
            fail("built CR6608 DTB property name is unterminated")
        raw = strings[name_offset:terminator]
        if not raw:
            fail("built CR6608 DTB contains an empty property name")
        try:
            return raw.decode("ascii")
        except UnicodeDecodeError:
            fail("built CR6608 DTB property name is not ASCII")

    cursor = struct_start
    stack = []
    nodes = {}
    root_seen = False
    end_seen = False
    while cursor < struct_end:
        if cursor + 4 > struct_end:
            fail("built CR6608 DTB has a truncated structure token")
        token = struct.unpack_from(">I", dtb, cursor)[0]
        cursor += 4
        if token == 1:  # FDT_BEGIN_NODE
            terminator = dtb.find(b"\0", cursor, struct_end)
            if terminator < 0:
                fail("built CR6608 DTB contains an unterminated node name")
            raw_name = dtb[cursor:terminator]
            try:
                name = raw_name.decode("ascii")
            except UnicodeDecodeError:
                fail("built CR6608 DTB node name is not ASCII")
            padded = (terminator + 4) & ~3
            if padded > struct_end or any(dtb[terminator + 1:padded]):
                fail("built CR6608 DTB node-name padding is not zero")
            cursor = padded
            if not stack:
                if root_seen or name:
                    fail("built CR6608 DTB does not have one empty-name root node")
                root_seen = True
            elif not name or "/" in name:
                fail("built CR6608 DTB contains an invalid child-node name")
            stack.append(name)
            path = "/" + "/".join(part for part in stack if part)
            if path in nodes:
                fail(f"built CR6608 DTB contains duplicate node {path}")
            nodes[path] = {}
        elif token == 2:  # FDT_END_NODE
            if not stack:
                fail("built CR6608 DTB contains an unmatched end-node token")
            stack.pop()
        elif token == 3:  # FDT_PROP
            if not stack or cursor + 8 > struct_end:
                fail("built CR6608 DTB contains a misplaced or truncated property")
            length, name_offset = struct.unpack_from(">II", dtb, cursor)
            cursor += 8
            if length > struct_end - cursor:
                fail("built CR6608 DTB property value exceeds the structure block")
            value_end = cursor + length
            padded = (value_end + 3) & ~3
            if padded > struct_end or any(dtb[value_end:padded]):
                fail("built CR6608 DTB property padding is not zero")
            name = property_name(name_offset)
            path = "/" + "/".join(part for part in stack if part)
            if name in nodes[path]:
                fail(f"built CR6608 DTB node {path} repeats property {name}")
            nodes[path][name] = dtb[cursor:value_end]
            cursor = padded
        elif token == 4:  # FDT_NOP
            continue
        elif token == 9:  # FDT_END
            if stack:
                fail("built CR6608 DTB ends with unclosed nodes")
            if any(dtb[cursor:struct_end]):
                fail("built CR6608 DTB has non-zero data after FDT_END")
            end_seen = True
            cursor = struct_end
        else:
            fail(f"built CR6608 DTB contains unknown token {token:#x}")
    if not root_seen or not end_seen:
        fail("built CR6608 DTB structure is incomplete")

    factory_nodes = [
        (path, properties)
        for path, properties in nodes.items()
        if properties.get("label") == b"Factory\0"
    ]
    if len(factory_nodes) != 1:
        fail(
            "built CR6608 DTB must contain exactly one Factory-labelled node, "
            f"found {len(factory_nodes)}"
        )
    factory_path, factory_properties = factory_nodes[0]
    if factory_path.rsplit("/", 1)[-1] != "partition@100000":
        fail(f"built CR6608 DTB Factory node has unexpected path {factory_path}")
    expected_reg = struct.pack(">II", 0x00100000, 0x00080000)
    if factory_properties.get("reg") != expected_reg:
        fail("built CR6608 DTB Factory node has unexpected offset or size")
    read_only_present = "read-only" in factory_properties
    if read_only_present and factory_properties["read-only"]:
        fail("built CR6608 DTB Factory read-only property is not empty")
    expected_read_only = mode == "normal"
    if read_only_present != expected_read_only:
        state = "present" if read_only_present else "absent"
        expected = "present" if expected_read_only else "absent"
        fail(
            f"built CR6608 DTB Factory read-only property is {state}, expected {expected}"
        )
    print(f"factory_dtb_node={factory_path}")
    print(f"factory_dtb_read_only={'present' if read_only_present else 'absent'}")


def lzma_streams(buffer):
    dictionaries = set()
    value = 4096
    while value <= 64 * 1024 * 1024:
        dictionaries.add(value)
        if value * 3 <= 64 * 1024 * 1024:
            dictionaries.add(value * 3)
        value *= 2
    offsets = set()
    for dictionary in dictionaries:
        needle = dictionary.to_bytes(4, "little")
        cursor = 1
        while True:
            cursor = buffer.find(needle, cursor)
            if cursor < 0:
                break
            if buffer[cursor - 1] <= 224:
                offsets.add(cursor - 1)
            cursor += 1
    for offset in sorted(offsets):
        declared_size = int.from_bytes(buffer[offset + 5:offset + 13], "little")
        if declared_size != 0xFFFFFFFFFFFFFFFF and not (
            1024 <= declared_size <= MAX_UNPACKED_BYTES
        ):
            continue
        try:
            decompressor = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
            unpacked = decompressor.decompress(
                buffer[offset:], max_length=MAX_UNPACKED_BYTES
            )
        except lzma.LZMAError:
            continue
        if decompressor.eof and unpacked:
            yield offset, unpacked


def bind_dtb(path, output_path, label):
    payload = read_uimage(path, label)
    matches = []
    for lzma_offset, unpacked in lzma_streams(payload):
        cursor = 0
        while True:
            cursor = unpacked.find(b"\xd0\x0d\xfe\xed", cursor)
            if cursor < 0:
                break
            if cursor + 8 <= len(unpacked):
                total = struct.unpack_from(">I", unpacked, cursor + 4)[0]
                if 256 <= total <= 1024 * 1024 and cursor + total <= len(unpacked):
                    candidate = unpacked[cursor:cursor + total]
                    if candidate == built_dtb:
                        matches.append((lzma_offset, cursor, candidate, unpacked))
            cursor += 4
    if len(matches) != 1:
        fail(
            f"expected exactly one {label}-embedded CR6608 DTB matching the built "
            f"DTB, found {len(matches)}"
        )
    lzma_offset, dtb_offset, candidate, unpacked = matches[0]
    output_path.write_bytes(candidate)
    print(f"{label}_lzma_offset={lzma_offset}")
    print(f"{label}_dtb_offset={dtb_offset}")
    print(f"{label}_dtb_sha256={__import__('hashlib').sha256(candidate).hexdigest()}")
    return unpacked


def align4(value):
    return (value + 3) & ~3


def parse_newc(buffer, start):
    if start < 0 or start >= len(buffer):
        return None
    cursor = start
    entries = {}
    hexadecimal = frozenset(b"0123456789abcdefABCDEF")
    for _ in range(200000):
        if cursor + 110 > len(buffer) or buffer[cursor:cursor + 6] not in (
            b"070701",
            b"070702",
        ):
            return None
        magic = buffer[cursor:cursor + 6]
        raw_fields = [
            buffer[cursor + 6 + field * 8:cursor + 14 + field * 8]
            for field in range(13)
        ]
        if any(
            len(raw) != 8 or any(byte not in hexadecimal for byte in raw)
            for raw in raw_fields
        ):
            return None
        fields = [int(raw, 16) for raw in raw_fields]
        mode = fields[1]
        file_size = fields[6]
        name_size = fields[11]
        checksum = fields[12]
        if name_size < 1 or name_size > 4096:
            return None
        name_start = cursor + 110
        name_end = name_start + name_size
        if name_end > len(buffer) or buffer[name_end - 1] != 0:
            return None
        raw_name = buffer[name_start:name_end - 1]
        if not raw_name or b"\0" in raw_name:
            return None
        try:
            name = raw_name.decode("utf-8")
        except UnicodeDecodeError:
            return None
        data_start = start + align4(name_end - start)
        if data_start > len(buffer) or any(buffer[name_end:data_start]):
            return None
        data_end = data_start + file_size
        if data_end > len(buffer):
            return None
        data = buffer[data_start:data_end]
        if magic == b"070701":
            if checksum != 0:
                return None
        elif sum(data) & 0xFFFFFFFF != checksum:
            return None
        next_cursor = start + align4(data_end - start)
        if next_cursor > len(buffer) or any(buffer[data_end:next_cursor]):
            return None
        if name == "TRAILER!!!":
            expected_trailer = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 11, 0]
            if fields != expected_trailer:
                return None
            trailing_padding = buffer[next_cursor:]
            if (
                len(trailing_padding) > 511
                or any(trailing_padding)
                or (len(buffer) - start) % 512
            ):
                return None
            return entries, next_cursor
        if name.startswith("/"):
            return None
        components = name.split("/")
        if any(component in ("", ".", "..") for component in components):
            return None
        if name in entries:
            return None
        entries[name] = (mode, data)
        cursor = next_cursor
    return None


def embedded_buffers(unpacked):
    yield "raw", unpacked
    cursor = 0
    while True:
        cursor = unpacked.find(b"\x1f\x8b\x08", cursor)
        if cursor < 0:
            break
        try:
            decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
            nested = decompressor.decompress(
                unpacked[cursor:], MAX_UNPACKED_BYTES
            )
            nested += decompressor.flush()
        except zlib.error:
            nested = b""
        if decompressor.eof and nested:
            yield f"gzip@{cursor}", nested
        cursor += 3
    cursor = 0
    while True:
        cursor = unpacked.find(b"\xfd7zXZ\x00", cursor)
        if cursor < 0:
            break
        try:
            decompressor = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
            nested = decompressor.decompress(
                unpacked[cursor:], max_length=MAX_UNPACKED_BYTES
            )
        except lzma.LZMAError:
            nested = b""
        if decompressor.eof and nested:
            yield f"xz@{cursor}", nested
        cursor += 6
    for offset, nested in lzma_streams(unpacked):
        yield f"lzma@{offset}", nested


def find_initramfs_cpio(unpacked):
    candidates = []
    for container, buffer in embedded_buffers(unpacked):
        # OpenWrt's decompressor emits the complete initramfs archive from byte
        # zero.  Accepting a later newc header would also accept a valid-looking
        # suffix of a malicious or truncated archive.
        parsed = parse_newc(buffer, 0)
        if parsed is not None:
            entries, _end = parsed
            if "etc/config/wireless" in entries and "etc/smartap-version" in entries:
                candidates.append((container, entries))
    if len(candidates) != 1:
        fail(
            "expected exactly one initramfs cpio containing the Smart AP overlay, "
            f"found {len(candidates)}"
        )
    return candidates[0]


def require_regular(entries, relative_path, expected_mode=None, source=None):
    entry = entries.get(relative_path)
    if entry is None:
        fail(f"initramfs lacks {relative_path}")
    mode, data = entry
    if stat.S_IFMT(mode) != stat.S_IFREG:
        fail(f"initramfs {relative_path} is not a regular file")
    if expected_mode is not None and stat.S_IMODE(mode) != expected_mode:
        fail(
            f"initramfs mode for {relative_path} is {stat.S_IMODE(mode):o}, "
            f"expected {expected_mode:o}"
        )
    if source is not None and data != source.read_bytes():
        fail(f"initramfs content differs from staged overlay: {relative_path}")
    return data


def require_cpio_symlink(entries, relative_path, expected_target):
    entry = entries.get(relative_path)
    if entry is None:
        fail(f"initramfs lacks symlink {relative_path}")
    mode, data = entry
    if stat.S_IFMT(mode) != stat.S_IFLNK:
        fail(f"initramfs {relative_path} is not a symlink")
    expected_data = expected_target.encode("utf-8") + b"\0"
    if data != expected_data:
        fail(
            f"initramfs symlink target changed: {relative_path}; "
            f"expected={expected_data.hex()}, actual={data.hex()}"
        )


def staged_overlay_entries(root):
    result = []

    def visit(directory, prefix):
        try:
            children = sorted(
                os.scandir(directory),
                key=lambda child: os.fsencode(child.name),
            )
        except OSError as exc:
            fail(f"cannot enumerate staged overlay {prefix or '.'}: {exc}")
        for child in children:
            relative_path = f"{prefix}/{child.name}" if prefix else child.name
            try:
                relative_path.encode("utf-8")
                source_stat = child.stat(follow_symlinks=False)
            except (OSError, UnicodeError) as exc:
                fail(f"cannot inspect staged overlay {relative_path!r}: {exc}")
            file_type = stat.S_IFMT(source_stat.st_mode)
            source_mode = stat.S_IMODE(source_stat.st_mode)
            if file_type == stat.S_IFREG:
                try:
                    source_data = pathlib.Path(child.path).read_bytes()
                except OSError as exc:
                    fail(f"cannot read staged overlay file {relative_path}: {exc}")
            elif file_type == stat.S_IFLNK:
                try:
                    source_target = os.readlink(child.path)
                    source_data = source_target.encode("utf-8")
                except (OSError, UnicodeError) as exc:
                    fail(
                        f"cannot read staged overlay symlink {relative_path}: {exc}"
                    )
                if not source_data or b"\0" in source_data:
                    fail(f"staged overlay symlink has an invalid target: {relative_path}")
            elif file_type == stat.S_IFDIR:
                source_data = b""
            else:
                fail(f"unsupported staged overlay entry type: {relative_path}")
            result.append((relative_path, file_type, source_mode, source_data))
            if file_type == stat.S_IFDIR:
                visit(child.path, relative_path)

    visit(root, "")
    if not result:
        fail("staged overlay was empty while inspecting initramfs")
    return result


def expected_overlay_data(relative_path, file_type, source_data):
    if file_type == stat.S_IFREG and relative_path == "etc/shadow":
        return source_data + SHADOW_PACKAGE_ACCOUNTS
    if file_type == stat.S_IFLNK:
        # Linux gen_init_cpio stores the symlink target with one terminating
        # NUL byte.  The installed VFS link itself exposes the target without
        # that terminator, so compare against the exact on-archive encoding.
        return source_data + b"\0"
    return source_data


def require_complete_overlay(entries, root):
    checked = 0
    for relative_path, source_type, source_mode, source_data in staged_overlay_entries(
        root
    ):
        entry = entries.get(relative_path)
        if entry is None:
            fail(f"initramfs lacks staged overlay path: {relative_path}")
        cpio_mode, cpio_data = entry
        cpio_type = stat.S_IFMT(cpio_mode)
        if cpio_type != source_type:
            fail(f"initramfs type differs from staged overlay: {relative_path}")
        if stat.S_IMODE(cpio_mode) != source_mode:
            fail(
                f"initramfs mode for {relative_path} is "
                f"{stat.S_IMODE(cpio_mode):o}, expected staged mode {source_mode:o}"
            )
        expected_data = expected_overlay_data(
            relative_path, source_type, source_data
        )
        if cpio_data != expected_data:
            if source_type == stat.S_IFLNK:
                fail(
                    "initramfs symlink target differs from staged overlay: "
                    f"{relative_path}; staged={source_data.hex()}, "
                    f"initramfs={cpio_data.hex()}"
                )
            if source_type == stat.S_IFDIR:
                fail(f"initramfs directory carries data: {relative_path}")
            fail(f"initramfs content differs from staged overlay: {relative_path}")
        checked += 1
    return checked


class CpioResolutionError(ValueError):
    pass


class CpioNotFound(CpioResolutionError):
    pass


def resolve_cpio_path(entries, absolute_path):
    if not isinstance(absolute_path, str) or not absolute_path.startswith("/"):
        raise CpioResolutionError(f"CPIO path is not absolute: {absolute_path!r}")
    if "\0" in absolute_path:
        raise CpioResolutionError("CPIO path contains NUL")
    resolved = []
    pending = absolute_path.split("/")[1:]
    visited = set()
    symlinks = 0
    final_entry = None
    while pending:
        state = (tuple(resolved), tuple(pending))
        if state in visited:
            raise CpioResolutionError(f"CPIO symlink cycle while resolving {absolute_path}")
        visited.add(state)
        component = pending.pop(0)
        if component in ("", "."):
            continue
        if component == "..":
            if not resolved:
                raise CpioResolutionError(
                    f"CPIO symlink escapes archive root while resolving {absolute_path}"
                )
            resolved.pop()
            final_entry = None
            continue
        if "/" in component or "\0" in component:
            raise CpioResolutionError(
                f"invalid CPIO path component while resolving {absolute_path}"
            )
        candidate_components = resolved + [component]
        candidate = "/".join(candidate_components)
        entry = entries.get(candidate)
        if entry is None:
            raise CpioNotFound(
                f"CPIO path is missing while resolving {absolute_path}: /{candidate}"
            )
        mode, data = entry
        if stat.S_IFMT(mode) == stat.S_IFLNK:
            symlinks += 1
            if symlinks > MAX_CPIO_SYMLINKS:
                raise CpioResolutionError(
                    f"too many CPIO symlinks while resolving {absolute_path}"
                )
            # Linux gen_init_cpio stores the link target with exactly one
            # trailing NUL.  Remove that archive terminator before resolving
            # the VFS path, while rejecting missing or embedded terminators.
            if data[-1:] != b"\0" or b"\0" in data[:-1]:
                raise CpioResolutionError(
                    f"CPIO symlink target is invalid: /{candidate}"
                )
            try:
                target = data[:-1].decode("utf-8")
            except UnicodeDecodeError as exc:
                raise CpioResolutionError(
                    f"CPIO symlink target is not UTF-8: /{candidate}"
                ) from exc
            if not target:
                raise CpioResolutionError(
                    f"CPIO symlink target is invalid: /{candidate}"
                )
            if target.startswith("/"):
                resolved = []
            pending = target.split("/") + pending
            final_entry = None
            continue
        resolved.append(component)
        final_entry = entry
        if pending and stat.S_IFMT(mode) != stat.S_IFDIR:
            raise CpioResolutionError(
                f"non-directory CPIO path component while resolving {absolute_path}: "
                f"/{candidate}"
            )
    if not resolved or final_entry is None:
        raise CpioResolutionError(f"CPIO path resolves to archive root: {absolute_path}")
    return "/" + "/".join(resolved), final_entry


def require_cpio_executable(entries, absolute_path):
    try:
        resolved_path, (mode, data) = resolve_cpio_path(entries, absolute_path)
    except CpioResolutionError as exc:
        fail(str(exc))
    if stat.S_IFMT(mode) != stat.S_IFREG or not stat.S_IMODE(mode) & 0o111:
        fail(
            f"CPIO executable dependency is not an executable regular file: "
            f"{absolute_path} -> {resolved_path}"
        )
    return resolved_path, data


def resolve_cpio_command(entries, command):
    if not command or "/" in command or command in (".", ".."):
        fail(f"invalid Factory-38 stage command name: {command!r}")
    failures = []
    for directory in CPIO_COMMAND_PATH:
        candidate = f"{directory}/{command}"
        try:
            resolved_directory, (directory_mode, _directory_data) = (
                resolve_cpio_path(entries, directory)
            )
        except CpioResolutionError as exc:
            fail(
                f"unsafe CPIO PATH directory while resolving Factory-38 command "
                f"{command}: "
                f"{exc}"
            )
        if stat.S_IFMT(directory_mode) != stat.S_IFDIR:
            fail(
                f"CPIO PATH component is not a directory: "
                f"{directory} -> {resolved_directory}"
            )
        resolved_candidate = (
            f"{resolved_directory.rstrip('/')}/{command}".lstrip("/")
        )
        if resolved_candidate not in entries:
            failures.append(f"{candidate} is absent")
            continue
        try:
            resolved_path, (mode, data) = resolve_cpio_path(entries, candidate)
        except CpioResolutionError as exc:
            fail(
                f"unsafe CPIO path while resolving Factory-38 command {command}: "
                f"{exc}"
            )
        if stat.S_IFMT(mode) == stat.S_IFREG and stat.S_IMODE(mode) & 0o111:
            return candidate, resolved_path, data
        fail(
            f"Factory-38 command path is present but not an executable regular file: "
            f"{candidate} -> {resolved_path}"
        )
    fail(
        f"maintenance initramfs cannot resolve Factory-38 command {command}: "
        + "; ".join(failures)
    )


def elf_program_interpreter(data, label):
    if not data.startswith(b"\x7fELF"):
        return None
    if len(data) < 16:
        fail(f"truncated ELF dependency: {label}")
    elf_class = data[4]
    elf_data = data[5]
    if elf_data == 1:
        byte_order = "<"
    elif elf_data == 2:
        byte_order = ">"
    else:
        fail(f"ELF dependency has invalid byte order: {label}")
    if elf_class == 1:
        header_format = byte_order + "HHIIIIIHHHHHH"
        program_format = byte_order + "IIIIIIII"
        program_offset_index = 1
        program_size_index = 4
    elif elf_class == 2:
        header_format = byte_order + "HHIQQQIHHHHHH"
        program_format = byte_order + "IIQQQQQQ"
        program_offset_index = 2
        program_size_index = 5
    else:
        fail(f"ELF dependency has invalid class: {label}")
    header_size = struct.calcsize(header_format)
    if len(data) < 16 + header_size:
        fail(f"truncated ELF header: {label}")
    header = struct.unpack_from(header_format, data, 16)
    program_offset = header[4]
    program_entry_size = header[8]
    program_count = header[9]
    expected_program_size = struct.calcsize(program_format)
    if program_entry_size < expected_program_size or program_count > 4096:
        fail(f"invalid ELF program-header table: {label}")
    if program_offset > len(data) or program_count * program_entry_size > len(data) - program_offset:
        fail(f"ELF program-header table is out of bounds: {label}")
    interpreters = []
    for index in range(program_count):
        offset = program_offset + index * program_entry_size
        program = struct.unpack_from(program_format, data, offset)
        if program[0] != 3:  # PT_INTERP
            continue
        interpreter_offset = program[program_offset_index]
        interpreter_size = program[program_size_index]
        if (
            interpreter_size < 2
            or interpreter_offset > len(data)
            or interpreter_size > len(data) - interpreter_offset
        ):
            fail(f"ELF PT_INTERP is out of bounds: {label}")
        raw = data[interpreter_offset:interpreter_offset + interpreter_size]
        if raw[-1:] != b"\0" or b"\0" in raw[:-1]:
            fail(f"ELF PT_INTERP is malformed: {label}")
        try:
            interpreter = raw[:-1].decode("ascii")
        except UnicodeDecodeError:
            fail(f"ELF PT_INTERP is not ASCII: {label}")
        if not interpreter.startswith("/"):
            fail(f"ELF PT_INTERP is not absolute: {label}")
        interpreters.append(interpreter)
    if len(interpreters) > 1:
        fail(f"ELF dependency has multiple PT_INTERP headers: {label}")
    return interpreters[0] if interpreters else None


def require_executable_dependencies(entries, displayed_path, resolved_path, data, checked):
    if resolved_path in checked:
        return
    checked.add(resolved_path)
    interpreter = None
    if data.startswith(b"#!"):
        first_line = data.split(b"\n", 1)[0][2:].strip()
        try:
            interpreter_words = first_line.decode("ascii").split()
        except UnicodeDecodeError:
            fail(f"executable shebang is not ASCII: {displayed_path}")
        if not interpreter_words or not interpreter_words[0].startswith("/"):
            fail(f"executable shebang is not absolute: {displayed_path}")
        interpreter = interpreter_words[0]
    else:
        interpreter = elf_program_interpreter(data, displayed_path)
    if interpreter is None:
        return
    dependency_path, dependency_data = require_cpio_executable(entries, interpreter)
    require_executable_dependencies(
        entries,
        interpreter,
        dependency_path,
        dependency_data,
        checked,
    )


def require_factory38_stage_dependencies(entries, stage_data):
    stage_path, resolved_stage_data = require_cpio_executable(
        entries, "/usr/sbin/cr6608-factory38-stage"
    )
    if resolved_stage_data != stage_data:
        fail("resolved Factory-38 stage content changed during CPIO lookup")
    checked_dependencies = set()
    require_executable_dependencies(
        entries,
        "/usr/sbin/cr6608-factory38-stage",
        stage_path,
        stage_data,
        checked_dependencies,
    )
    for command in FACTORY38_STAGE_COMMANDS:
        invoked_path, resolved_path, command_data = resolve_cpio_command(
            entries, command
        )
        require_executable_dependencies(
            entries,
            invoked_path,
            resolved_path,
            command_data,
            checked_dependencies,
        )
    return len(FACTORY38_STAGE_COMMANDS), len(checked_dependencies)


validate_factory_dtb(built_dtb, build_mode)
kernel_unpacked = bind_dtb(kernel_path, kernel_dtb_path, "kernel")
initramfs_unpacked = bind_dtb(initramfs_path, initramfs_dtb_path, "initramfs")
del kernel_unpacked
cpio_container, cpio_entries = find_initramfs_cpio(initramfs_unpacked)
initramfs_overlay_entries = require_complete_overlay(cpio_entries, overlay_path)

for relative_path, mode in (
    ("etc/config/wireless", 0o600),
    ("etc/inittab", 0o644),
    ("etc/smartap-version", 0o644),
):
    require_regular(
        cpio_entries,
        relative_path,
        mode,
        overlay_path / relative_path,
    )

require_regular(cpio_entries, "usr/sbin/lldpd", 0o755)
require_regular(cpio_entries, "usr/sbin/lldpcli", 0o755)
require_cpio_symlink(cpio_entries, "usr/sbin/lldpctl", "lldpcli")

maintenance_paths = (
    ("usr/sbin/cr6608-factory38-stage", 0o755),
    ("etc/cr6608-factory38-writegate.marker", 0o644),
    ("etc/uci-defaults/01-cr6608-factory38-maintenance", 0o755),
)
if build_mode == "maintenance":
    stage_data = None
    for relative_path, mode in maintenance_paths:
        maintenance_data = require_regular(
            cpio_entries,
            relative_path,
            mode,
            overlay_path / relative_path,
        )
        if relative_path == "usr/sbin/cr6608-factory38-stage":
            stage_data = maintenance_data
    if stage_data is None:
        fail("maintenance initramfs lacks the Factory-38 stage source")
    factory38_stage_commands, factory38_stage_dependencies = (
        require_factory38_stage_dependencies(cpio_entries, stage_data)
    )
else:
    for relative_path, _mode in maintenance_paths:
        if relative_path in cpio_entries:
            fail(f"normal initramfs contains maintenance-only path: {relative_path}")

drivers = [
    (name, entry)
    for name, entry in cpio_entries.items()
    if name.endswith("/mt7915e.ko")
]
if len(drivers) != 1:
    fail(f"expected one mt7915e.ko in initramfs, found {len(drivers)}")
driver_mode, driver_data = drivers[0][1]
if stat.S_IFMT(driver_mode) != stat.S_IFREG:
    fail("initramfs mt7915e.ko is not a regular file")
for marker in (
    b"CR6608-RF-38DBM LAB enabled",
    b"all eight 5 GHz EEPROM channel groups",
    b"every channel change requires MCU SKU readback",
    b"CR6608 DTS property and cr6608_rf_38dbm=1 are both required",
    b"cr6608_factory38_persisted_match",
    b"activating the audited volatile 38 dBm target override",
    b"CR6608-RF firmware EEPROM shadow active",
    b"CR6608 MediaTek MURU candidate enabled",
    b"cr6608_muru_mask",
    b"candidate_allowed=",
    b"candidate_mask=",
    b"candidate_ul_mumimo=",
    b"sta_rec_response_ok=",
    b"sta_rec_timeout=",
    b"fault_latched=",
):
    if marker not in driver_data:
        fail(f"initramfs mt7915e.ko lacks marker {marker.decode('ascii')}")

expected_nft_module_names = (
    rescue_nft_bridge_core_module,
) + rescue_nft_bridge_modules
for module_name in expected_nft_module_names:
    module_matches = [
        (name, entry)
        for name, entry in cpio_entries.items()
        if name.rsplit("/", 1)[-1] == module_name
    ]
    if len(module_matches) != 1:
        fail(
            f"expected exactly one initramfs {module_name} kernel module, "
            f"found {len(module_matches)}"
        )
    module_path, (module_mode, module_data) = module_matches[0]
    expected_module_path = (
        f"lib/modules/{expected_kernel_release}/{module_name}"
    )
    if module_path != expected_module_path:
        fail(
            f"initramfs {module_name} path is {module_path!r}, "
            f"expected {expected_module_path!r}"
        )
    if (
        stat.S_IFMT(module_mode) != stat.S_IFREG
        or stat.S_IMODE(module_mode) != 0o644
        or not module_data
    ):
        fail(
            f"initramfs {module_name} is not a non-empty mode-0644 regular file"
        )

expected_bridge_autoload_data = b"".join(
    name.encode("ascii") + b"\n" for name in rescue_nft_bridge_autoloads
)
bridge_autoload_entry = cpio_entries.get(rescue_nft_bridge_autoload_file)
if bridge_autoload_entry is None:
    fail("initramfs nft bridge modules.d autoload file is absent")
bridge_autoload_mode, bridge_autoload_data = bridge_autoload_entry
if (
    stat.S_IFMT(bridge_autoload_mode) != stat.S_IFREG
    or stat.S_IMODE(bridge_autoload_mode) != 0o644
):
    fail("initramfs nft bridge modules.d autoload is not mode-0644 regular")
if bridge_autoload_data != expected_bridge_autoload_data:
    fail("initramfs nft bridge modules.d autoload bytes or order differ")

expected_autoload_tokens = tuple(
    name.encode("ascii") for name in rescue_nft_bridge_autoloads
)
autoload_occurrences = {token: [] for token in expected_autoload_tokens}
for name, (mode, data) in cpio_entries.items():
    if not name.startswith("etc/modules.d/") or stat.S_IFMT(mode) != stat.S_IFREG:
        continue
    for line_number, line in enumerate(data.splitlines(), start=1):
        fields = line.split()
        if fields and fields[0] in autoload_occurrences:
            autoload_occurrences[fields[0]].append((name, line_number))
for expected_line, token in enumerate(expected_autoload_tokens, start=1):
    if autoload_occurrences[token] != [
        (rescue_nft_bridge_autoload_file, expected_line)
    ]:
        fail(
            "initramfs nft bridge autoload is missing, duplicated, or misplaced: "
            f"{token.decode('ascii')} -> {autoload_occurrences[token]!r}"
        )

print(f"initramfs_cpio_container={cpio_container}")
print(f"initramfs_cpio_entries={len(cpio_entries)}")
print(f"initramfs_overlay_entries_checked={initramfs_overlay_entries}")
print("initramfs_overlay_gate_status=pass")
print("initramfs_lldp_package_gate_status=pass")
if build_mode == "maintenance":
    print("factory38_stage_commands=" + ",".join(FACTORY38_STAGE_COMMANDS))
    print(f"factory38_stage_commands_checked={factory38_stage_commands}")
    print(f"factory38_stage_dependencies_checked={factory38_stage_dependencies}")
    print("factory38_stage_dependency_gate_status=pass")
else:
    print("factory38_stage_dependency_gate_status=not_applicable_normal")
print("rescue_nft_bridge_initramfs_gate_status=pass")
print("initramfs_rootfs_gate_status=pass")
PY
cmp -s "${kernel_dtb}" "${built_dtbs[0]}" || \
	die "kernel-embedded CR6608 DTB differs from the built DTB"
cmp -s "${initramfs_dtb}" "${built_dtbs[0]}" || \
	die "initramfs-embedded CR6608 DTB differs from the built DTB"

printf 'openwrt_commit=%s\n' "${EXPECTED_COMMIT}"
printf 'target_definition_sha256=%s\n' \
	"$(sha256sum "${TARGET_DEFINITION}" | awk '{print $1}')"
printf 'kernel_limit=%s\n' "${kernel_limit_value}"
printf 'kernel_limit_bytes=%s\n' "${kernel_limit_bytes}"
printf 'image_limit=%s\n' "${image_limit_value}"
printf 'image_limit_bytes=%s\n' "${image_limit_bytes}"
printf 'kernel_bytes=%s\n' "${kernel_bytes}"
printf 'rootfs_bytes=%s\n' "${rootfs_bytes}"
printf 'sysupgrade_bytes=%s\n' "${image_bytes}"
printf 'firmware_bytes=%s\n' "${firmware_bytes}"
printf 'initramfs_bytes=%s\n' "${initramfs_bytes}"
printf 'overlay_entries_checked=%s\n' "${overlay_entries}"
printf 'fwtool_metadata=present\n'
printf 'fwtool_signature=present_verified\n'
printf 'apk_pubkey_sha256=%s\n' "$(sha256sum "${APK_SIGNING_PUB}" | awk '{print $1}')"
printf 'apk_indexes_checked=%s\n' "${apk_indexes_checked}"
printf 'supported_device=%s\n' "${SUPPORTED_DEVICE}"
printf 'driver=%s\n' "${driver_file#"${rootfs_dir}/"}"
printf 'factory38_build_mode=%s\n' "${FACTORY38_BUILD_MODE}"
printf 'rescue_nft_bridge_kernel_release=%s\n' \
	"${rescue_nft_bridge_kernel_release}"
printf 'rescue_nft_bridge_kernel_configs=%s\n' \
	"${RESCUE_NFT_BRIDGE_KERNEL_CONFIGS_CSV}"
printf 'rescue_nft_bridge_core_module=%s\n' \
	"${RESCUE_NFT_BRIDGE_CORE_MODULE}"
printf 'rescue_nft_bridge_modules=%s\n' \
	"${RESCUE_NFT_BRIDGE_MODULES_CSV}"
printf 'rescue_nft_bridge_autoload_file=%s\n' \
	"${RESCUE_NFT_BRIDGE_AUTOLOAD_FILE}"
printf 'rescue_nft_bridge_autoloads=%s\n' \
	"${RESCUE_NFT_BRIDGE_AUTOLOADS_CSV}"
printf 'rescue_nft_bridge_squashfs_gate_status=pass\n'
printf 'rescue_nft_bridge_parser_gate=guard_runtime_atomic_precheck\n'
printf 'rescue_nft_bridge_gate_status=pass\n'
printf 'serial_console=stock_ttyS0_115200_enabled\n'
printf 'compat_version=1.1\n'
if [ "${FACTORY38_BUILD_MODE}" = maintenance ] || [ "${BUILD_PROFILE}" = ul-lab ] ||
	[ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	printf 'boot_policy=ram_boot_only_no_sysupgrade_or_firmware_published\n'
else
	printf 'upgrade_compat_policy=sysupgrade_T_required_no_force\n'
fi
printf 'image_integrity_gate_status=pass\n'
printf 'build_profile=%s\n' "${BUILD_PROFILE}"
printf 'retail_commissioning_mode=%s\n' "${RETAIL_COMMISSIONING_MODE}"
if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	printf 'retail_commissioning_access_gate_status=pass_ed25519_public_key_password_auth_disabled\n'
else
	printf 'retail_commissioning_access_gate_status=not_present\n'
fi
printf 'artifact_profile=%s\n' "${ARTIFACT_PROFILE_LABEL}"
printf 'sale_ready=NO\n'
printf 'retail_security_gate_status=blocked_pending_unique_device_provisioning\n'
printf 'retail_radio_gate_status=%s\n' "${RETAIL_RADIO_GATE_STATUS}"
printf 'release_gate_status=blocked_pending_router_runtime_and_external_rf_verification\n'
