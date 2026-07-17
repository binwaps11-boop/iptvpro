#!/usr/bin/env bash
# Fail-closed inspection of the CR6608 images produced by build.sh.

set -euo pipefail
umask 022

EXPECTED_ORIGIN="https://git.openwrt.org/openwrt/openwrt.git"
EXPECTED_COMMIT="f0a60eee2fe051741c643ea6118718aae1ef17fb"
EXPECTED_VERSION="25.12.5"
EXPECTED_REVISION="r33051-f5dae5ece4"
DEVICE_PROFILE="xiaomi_mi-router-cr6608"
SUPPORTED_DEVICE="xiaomi,mi-router-cr6608"
COMPAT_MESSAGE="Config cannot be migrated from swconfig to DSA"
EXPECTED_TARGET_SHA256="72d2942546de37529723eca17231d7b4c39abee061ecf8dabd4a8607596e9da1"
EXPECTED_SERIAL_DTS_SHA256="7e867d664d3eb07e238c0caa534507f95978de55933a8083bdb9e8fca6f8b7ed"
EXPECTED_SERIAL_KERNEL_CONFIG_SHA256="411fe5c77dd508086e1432f5f6deb9b40036e9bb6e4993c2342cc588e4478c1b"

die() {
	printf 'IMAGE GATE FAILED: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 4 ] || die \
	"usage: $0 SYSUPGRADE_IMAGE FIRMWARE_IMAGE OPENWRT_DIR STAGED_OVERLAY"

IMAGE="$1"
FIRMWARE_IMAGE="$2"
OPENWRT_DIR="$3"
STAGED_OVERLAY="$4"
TARGET_DEFINITION="${OPENWRT_DIR}/target/linux/ramips/image/mt7621.mk"
CR6608_DTS="${OPENWRT_DIR}/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts"
CR6608_KERNEL_CONFIG="${OPENWRT_DIR}/target/linux/ramips/mt7621/config-6.12"
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
[ -d "${STAGED_OVERLAY}" ] || die "staged overlay is missing: ${STAGED_OVERLAY}"
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
[ "$(sha256sum "${CR6608_DTS}" | awk '{print $1}')" = \
	"${EXPECTED_SERIAL_DTS_SHA256}" ] || die "serial-disabled CR6608 DTS changed"
grep -Fqx $'\t\tbootargs = "rootfstype=squashfs,jffs2 console=ttynull";' "${CR6608_DTS}" || \
	die "CR6608 DTS bootargs are not serial-free"
grep -Fqx $'\t\tbootargs-override = "rootfstype=squashfs,jffs2 console=ttynull";' "${CR6608_DTS}" || \
	die "CR6608 DTS lacks the bootloader console override"
if grep -Eq 'console=ttyS[0-9]|stdout-path' "${CR6608_DTS}"; then
	die "CR6608 DTS still exposes a serial console"
fi
[ "$(sha256sum "${CR6608_KERNEL_CONFIG}" | awk '{print $1}')" = \
	"${EXPECTED_SERIAL_KERNEL_CONFIG_SHA256}" ] || \
	die "serial-console-disabled mt7621 kernel config changed"
grep -Fqx '# CONFIG_SERIAL_8250_CONSOLE is not set' "${CR6608_KERNEL_CONFIG}" || \
	die "mt7621 source config still enables the 8250 console"
grep -Fqx 'CONFIG_NULL_TTY=y' "${CR6608_KERNEL_CONFIG}" || \
	die "mt7621 source config does not provide the null userspace console"
if grep -Eq '^CONFIG_SERIAL_8250_CONSOLE=' "${CR6608_KERNEL_CONFIG}"; then
	die "mt7621 source config has a conflicting 8250 console value"
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
if ! openssl pkey -in "${APK_SIGNING_KEY}" -pubout -out "${apk_pub_probe}" \
	>/dev/null 2>&1; then
	die "APK private key is not a valid EC private key"
fi
cmp -s "${apk_pub_probe}" "${APK_SIGNING_PUB}" || \
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

firmware_magic="$(dd if="${FIRMWARE_IMAGE}" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
[ "${firmware_magic}" = "27051956" ] || die "firmware image does not begin with the built uImage"
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
	elif [ -f "${source_path}" ]; then
		[ -f "${built_path}" ] && [ ! -L "${built_path}" ] || \
			die "overlay file missing from rootfs: ${relative_path}"
		if [ "${relative_path}" = "etc/shadow" ]; then
			expected_shadow="${tmp_dir}/expected-shadow"
			{
				cat "${source_path}"
				printf '%s\n' \
					'ntp:x:0:0:99999:7:::' \
					'dnsmasq:x:0:0:99999:7:::' \
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

require_mode www/cgi-bin/dashluci 755
require_mode www/cgi-bin/dashlogin 755
require_mode www/cgi-bin/dashlogout 755
require_mode www/cgi-bin/dashctl 755
require_mode usr/libexec/cr6608-session-auth 755
require_mode usr/libexec/cr6608-luci-acl-names.uc 755
require_mode usr/libexec/cr6608-vlan-lib 755
require_mode usr/sbin/cr6608-safe-apply 755
require_mode usr/sbin/cr6608-safe-wifi-reload 755
require_mode usr/sbin/cr6608-quicksettings-apply 755
require_mode usr/sbin/cr6608-security-apply 755
require_mode usr/sbin/cr6608-session-reaper 755
require_mode usr/sbin/cr6608-eeprom-power 755
require_mode usr/sbin/smartap-bootstrap 755
require_mode etc/init.d/cr6608-safe-apply 755
require_mode etc/init.d/cr6608-quicksettings 755
require_mode etc/init.d/smartap-qos 755
require_mode etc/init.d/cr6608-rescue-guard 755
require_mode etc/init.d/cr6608-security 755
require_mode etc/init.d/cr6608-neighbor 755
require_mode etc/uci-defaults/97-cr6608-security 755
require_mode etc/uci-defaults/98-cr6608-safe-apply 755
require_mode etc/uci-defaults/99-cr6608-neighbor-enable 755
require_mode etc/uci-defaults/99-cr6608-runtime-services 755
require_mode etc/uci-defaults/97-smartap-bootstrap 755
require_mode etc/config/cr6608quick 600
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
require_mode www/index.html 644
require_mode etc/smartap-version 644
require_mode etc/modules.d/mt7915e 644
require_mode etc/inittab 644
require_mode etc/shadow 600
require_mode etc/config/openssl 644
require_mode etc/crontabs/root 600
require_mode etc/config/wireless 600
require_mode sbin/sysupgrade 755
require_mode lib/netifd/wireless/mac80211.sh 755
require_mode etc/apk/keys/public-key.pem 644
require_mode www/luci-static/resources/ui.js 644
require_mode usr/share/ucode/luci/controller/admin/uci.uc 644

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

printf "\nconfig provider 'legacy'\n\toption enabled '1'\n" | \
	cmp -s - "${rootfs_dir}/etc/config/openssl" || \
	die "OpenSSL legacy provider config is missing or duplicated"

printf 'mt7915e cr6608_rf_38dbm=1\n' | \
	cmp -s - "${rootfs_dir}/etc/modules.d/mt7915e" || \
	die "38 dBm module line is not exact"
printf '%s\n' \
	'::sysinit:/etc/init.d/rcS S boot' \
	'::shutdown:/etc/init.d/rcS K shutdown' | \
	cmp -s - "${rootfs_dir}/etc/inittab" || \
	die "rootfs serial login is not disabled exactly"
if grep -Eqi 'askconsole|getty|ttyS[0-9]' "${rootfs_dir}/etc/inittab"; then
	die "rootfs inittab still starts a serial console"
fi
grep -Fq 'date -u -s "@$anchor"' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor helper does not set the clock"
grep -Fq '[ "$now" -lt "$anchor" ]' \
	"${rootfs_dir}/usr/sbin/smartap-time-anchor" || \
	die "time anchor helper lacks its forward-only guard"
grep -Fq '/etc/init.d/smartap-time-anchor enable' \
	"${rootfs_dir}/etc/uci-defaults/00-smartap-time-anchor" || \
	die "time anchor service is not enabled on first boot"
grep -Eq '^START=01$' "${rootfs_dir}/etc/init.d/smartap-time-anchor" || \
	die "time anchor service does not run immediately after sysfixtime"
grep -Fq '/usr/sbin/smartap-time-anchor' \
	"${rootfs_dir}/etc/init.d/smartap-time-anchor" || \
	die "time anchor init script does not invoke the helper"
for syntax_file in \
	usr/sbin/cr6608-safe-apply \
	usr/sbin/cr6608-safe-wifi-reload \
	usr/sbin/cr6608-quicksettings-apply \
	etc/init.d/cr6608-safe-apply \
	etc/init.d/cr6608-quicksettings \
	etc/uci-defaults/98-cr6608-safe-apply \
	etc/uci-defaults/99-cr6608-runtime-services \
	etc/config/cr6608quick \
	www/cgi-bin/cr6608-quick-apply \
	www/cgi-bin/cr6608-quick-confirm \
	www/cgi-bin/dashctl \
	usr/libexec/cr6608-vlan-lib \
	usr/sbin/cr6608-security-apply \
	usr/sbin/cr6608-session-reaper \
	usr/sbin/cr6608-eeprom-power \
	usr/sbin/smartap-bootstrap \
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
node --check "${rootfs_dir}/www/luci-static/resources/view/cr6608/quicksettings.js" \
	>/dev/null || die "quick-settings JavaScript syntax failed"
node --check "${rootfs_dir}/www/dashboard.js" >/dev/null || \
	die "dashboard JavaScript syntax failed"
quick_ui="${rootfs_dir}/www/luci-static/resources/view/cr6608/quicksettings.js"
grep -Fq "method: 'freqlist'" "${quick_ui}" || die "quick-settings live channel RPC is absent"
grep -Fq "method: 'countrylist'" "${quick_ui}" || die "quick-settings country RPC is absent"
grep -Fq 'CR6608TxPowerValue' "${quick_ui}" || die "quick-settings TX power slider is absent"
grep -Fq 'Max / Turbo 38 dBm' "${quick_ui}" || die "quick-settings 38 dBm preset is absent"
grep -Fq 'Restricted 5G channels reported by driver' "${quick_ui}" || die "quick-settings restricted-channel report is absent"
grep -Fq 'rollback_token' "${rootfs_dir}/www/cgi-bin/cr6608-quick-apply" || die "quick-settings transaction token response is absent"
grep -Fq 'retain-ip' "${rootfs_dir}/usr/sbin/cr6608-safe-apply" || die "temporary management-IP reachability guard is absent"
quick_executor="${rootfs_dir}/usr/sbin/cr6608-quicksettings-apply"
quick_cgi="${rootfs_dir}/www/cgi-bin/cr6608-quick-apply"
dashctl="${rootfs_dir}/www/cgi-bin/dashctl"
dashboard_js="${rootfs_dir}/www/dashboard.js"
safe_apply="${rootfs_dir}/usr/sbin/cr6608-safe-apply"
bootstrap="${rootfs_dir}/usr/sbin/smartap-bootstrap"
grep -Fq "clear_previous='1'" "${quick_executor}" || die "quick-settings cleanup is not mandatory"
grep -Fq "clr='1'" "${quick_cgi}" || die "quick-settings CGI cleanup is not mandatory"
grep -Fq 'delete_previous="1"' "${dashctl}" || die "Smart AP cleanup is not mandatory"
grep -Fq 'if (field) field.value = pppoe ? "1" : "0";' "${dashboard_js}" || \
	die "Smart AP mode synchronizer does not clear stale PPPoE toggles"
grep -Fq "option clear_previous '1'" "${rootfs_dir}/etc/config/cr6608quick" || \
	die "clean-image quick-settings cleanup default is disabled"
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
if anchor < 1577836800 or stamp != anchor:
    raise SystemExit("IMAGE GATE FAILED: generated build time and anchor disagree")
PY
grep -Fq 'luci_session_has_write "$old_luci_sid"' \
	"${rootfs_dir}/www/cgi-bin/dashluci" || \
	die "LuCI bridge is not idempotent"
grep -Fq 'luci_session_has_write "$NEW_LUCI_SID"' \
	"${rootfs_dir}/www/cgi-bin/dashluci" || \
	die "LuCI write access is not verified"
session_auth="${rootfs_dir}/usr/libexec/cr6608-session-auth"
dashlogin="${rootfs_dir}/www/cgi-bin/dashlogin"
dashluci="${rootfs_dir}/www/cgi-bin/dashluci"
dashlogout="${rootfs_dir}/www/cgi-bin/dashlogout"
logout_controller="${rootfs_dir}/usr/share/ucode/luci/controller/cr6608/logout.uc"
grep -Fq 'cr6608_sid=\([^[:space:];]*\)' "${session_auth}" || \
	die "Smart AP session helper does not read the HttpOnly cookie"
if grep -Fq 'HTTP_X_CR6608_SESSION' "${session_auth}" "${dashlogin}" \
	"${dashluci}" "${dashlogout}" "${rootfs_dir}/www/dashboard.js"; then
	die "Smart AP bearer is still accepted through a request header"
fi
grep -Fq '{"ok":true}' "${dashlogin}" || \
	die "Smart AP login response is not bearer-free"
if grep -Eq 'data\.sid|"sid"[[:space:]]*:' "${rootfs_dir}/www/dashboard.js" "${dashlogin}"; then
	die "Smart AP bearer is exposed to browser JavaScript"
fi
grep -Fq 'sessionStorage.setItem(LS + "session", "cookie")' \
	"${rootfs_dir}/www/dashboard.js" || \
	die "dashboard does not use the cookie-only authentication marker"
grep -Fq 'cr6608_random_hex32' "${dashlogin}" || \
	die "Smart AP login does not use the exact entropy helper"
grep -Fq 'flock -x 8' "${dashlogin}" || \
	die "Smart AP login rate limiter is not serialized"
grep -Fq "ubus.call('session', 'destroy'" "${logout_controller}" || \
	die "LuCI logout controller does not destroy the active child session"
for cookie_path in \
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
grep -Fxq 'SmartAP CR6608 v29 / OpenWrt 25.12.5 (CR6608-RF-38DBM-LINEAR; professional dashboard and resilient boot)' \
	"${rootfs_dir}/etc/smartap-version" || \
	die "installed Smart AP release identity is stale"
grep -Fq '/dashboard.js?v=20260716-v29-mobile-r1' \
	"${rootfs_dir}/www/index.html" || \
	die "dashboard cache-buster is stale"
runtime_services_default="${rootfs_dir}/etc/uci-defaults/99-cr6608-runtime-services"
grep -Fq 'for service in smartap-qos cr6608-rescue-guard cr6608-quicksettings; do' \
	"${runtime_services_default}" || \
	die "clean-flash runtime service list is incomplete"
grep -Fq '"/etc/init.d/$service" enable || exit 1' \
	"${runtime_services_default}" || \
	die "clean-flash runtime services are not enabled fail-closed"
grep -Fq '"/etc/init.d/$service" start || exit 1' \
	"${runtime_services_default}" || \
	die "clean-flash runtime services are not started on the first boot"
security_service_default="${rootfs_dir}/etc/uci-defaults/97-cr6608-security"
grep -Fqx '[ -x /etc/init.d/cr6608-security ] || exit 1' \
	"${security_service_default}" || \
	die "clean-flash security service existence check is not fail-closed"
grep -Fqx '/etc/init.d/cr6608-security enable || exit 1' \
	"${security_service_default}" || \
	die "clean-flash security service enable is not fail-closed"
grep -Fqx '/etc/init.d/cr6608-security start || exit 1' \
	"${security_service_default}" || \
	die "clean-flash security service is not started on the first boot"
[ ! -e "${rootfs_dir}/etc/modprobe.d" ] && [ ! -L "${rootfs_dir}/etc/modprobe.d" ] || \
	die "stale /etc/modprobe.d path is present"

driver_list="${tmp_dir}/drivers.list0"
find "${rootfs_dir}/lib/modules" -type f -name 'mt7915e.ko' -print0 > \
	"${driver_list}" || die "could not enumerate mt7915e modules"
mapfile -d '' -t driver_files < "${driver_list}"
[ "${#driver_files[@]}" -eq 1 ] || \
	die "expected exactly one built mt7915e.ko, found ${#driver_files[@]}"
driver_file="${driver_files[0]}"
grep -aFq 'CR6608-RF-38DBM-LINEAR enabled' "${driver_file}" || \
	die "built mt7915e driver lacks the 38 dBm marker"
grep -aFq 'cr6608_rf_38dbm' "${driver_file}" || \
	die "built mt7915e driver lacks the 38 dBm parameter"
if grep -aEq 'cr6608_rf_35dbm|CR6608-RF-35DBM' "${driver_file}"; then
	die "built mt7915e driver contains a stale 35 dBm marker"
fi
if grep -RIsaEq 'cr6608_rf_35dbm|CR6608-RF-35DBM' "${rootfs_dir}"; then
	die "rootfs contains stale 35 dBm content"
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
grep -Fqx '# CONFIG_SERIAL_8250_CONSOLE is not set' "${built_kernel_configs[0]}" || \
	die "built kernel still enables the 8250 serial console"
grep -Fqx 'CONFIG_NULL_TTY=y' "${built_kernel_configs[0]}" || \
	die "built kernel lacks the null userspace console"
if grep -Eq '^CONFIG_SERIAL_8250_CONSOLE=' "${built_kernel_configs[0]}"; then
	die "built kernel has a conflicting 8250 console value"
fi

dtb_list="${tmp_dir}/dtbs.list0"
find "${OPENWRT_DIR}/build_dir" -type f \
	-name 'image-mt7621_xiaomi_mi-router-cr6608.dtb' -print0 > \
	"${dtb_list}" || die "could not enumerate built CR6608 DTBs"
mapfile -d '' -t built_dtbs < "${dtb_list}"
[ "${#built_dtbs[@]}" -eq 1 ] || \
	die "expected exactly one built CR6608 DTB, found ${#built_dtbs[@]}"
grep -aFq 'bootargs-override' "${built_dtbs[0]}" || \
	die "built CR6608 DTB lacks bootargs-override"
grep -aFq 'rootfstype=squashfs,jffs2' "${built_dtbs[0]}" || \
	die "built CR6608 DTB lacks serial-free bootargs"
grep -aFq 'console=ttynull' "${built_dtbs[0]}" || \
	die "built CR6608 DTB lacks the null userspace console"
if grep -aEq 'console=ttyS[0-9]' "${built_dtbs[0]}"; then
	die "built CR6608 DTB still contains a serial console"
fi

# The CR6608 uImage contains a small loader followed by an LZMA-alone stream.
# Extract that stream, locate its appended FDT, and compare it byte-for-byte
# with the single DTB produced by this build. This binds the serial-console
# proof to the kernel member that is actually present in the release image.
kernel_dtb="${tmp_dir}/kernel-embedded-cr6608.dtb"
python3 - "${kernel_member}" "${built_dtbs[0]}" "${kernel_dtb}" <<'PY'
import hashlib
import lzma
import pathlib
import struct
import sys

kernel_path, built_dtb_path, output_path = map(pathlib.Path, sys.argv[1:])
kernel = kernel_path.read_bytes()
built_dtb = built_dtb_path.read_bytes()
if kernel[:4] != b"\x27\x05\x19\x56" or len(kernel) <= 64:
    raise SystemExit("IMAGE GATE FAILED: kernel member is not a complete uImage")

payload = kernel[64:]
matches = []
for offset in range(0, len(payload) - 13):
    props = payload[offset]
    if props > 224:
        continue
    dictionary = int.from_bytes(payload[offset + 1:offset + 5], "little")
    if dictionary < 4096 or dictionary > 64 * 1024 * 1024:
        continue
    power_of_two = dictionary & (dictionary - 1) == 0
    three_halves = dictionary % 3 == 0 and (
        (dictionary // 3) & ((dictionary // 3) - 1) == 0
    )
    if not (power_of_two or three_halves):
        continue
    try:
        decompressor = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
        unpacked = decompressor.decompress(payload[offset:])
    except lzma.LZMAError:
        continue
    if not decompressor.eof:
        continue
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
                    matches.append((offset, cursor, candidate))
        cursor += 4

if len(matches) != 1:
    expected = hashlib.sha256(built_dtb).hexdigest()
    raise SystemExit(
        "IMAGE GATE FAILED: expected exactly one kernel-embedded CR6608 DTB "
        f"matching {expected}, found {len(matches)}"
    )

output_path.write_bytes(matches[0][2])
print(f"kernel_lzma_offset={matches[0][0]}")
print(f"kernel_dtb_offset={matches[0][1]}")
print(f"kernel_dtb_sha256={hashlib.sha256(matches[0][2]).hexdigest()}")
PY
cmp -s "${kernel_dtb}" "${built_dtbs[0]}" || \
	die "kernel-embedded CR6608 DTB differs from the built DTB"

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
printf 'overlay_entries_checked=%s\n' "${overlay_entries}"
printf 'fwtool_metadata=present\n'
printf 'fwtool_signature=present_verified\n'
printf 'apk_pubkey_sha256=%s\n' "$(sha256sum "${APK_SIGNING_PUB}" | awk '{print $1}')"
printf 'apk_indexes_checked=%s\n' "${apk_indexes_checked}"
printf 'supported_device=%s\n' "${SUPPORTED_DEVICE}"
printf 'driver=%s\n' "${driver_file#"${rootfs_dir}/"}"
printf 'serial_console=disabled\n'
printf 'gate_status=pass\n'
