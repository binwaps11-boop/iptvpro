#!/usr/bin/env bash
# Publish an already-built image only after rerunning inspect-image.sh against
# the exact bytes being copied into the release directory.

set -euo pipefail
umask 022

[ "$#" -eq 3 ] || {
	printf 'usage: %s INSPECTION_LOG SOURCE_TEST_LOG BUILD_LOG\n' "$0" >&2
	exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINAL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENWRT_DIR="${FINAL_ROOT}/openwrt"
RELEASES_DIR="${FINAL_ROOT}/output/releases"
INSPECTION_LOG="$(readlink -f "$1")"
SOURCE_TEST_LOG="$(readlink -f "$2")"
BUILD_LOG="$(readlink -f "$3")"
IMAGE="${OPENWRT_DIR}/bin/targets/ramips/mt7621/openwrt-ramips-mt7621-xiaomi_mi-router-cr6608-squashfs-sysupgrade.bin"
FIRMWARE="${OPENWRT_DIR}/bin/targets/ramips/mt7621/openwrt-ramips-mt7621-xiaomi_mi-router-cr6608-squashfs-firmware.bin"
INSPECTOR="${SCRIPT_DIR}/inspect-image.sh"
FINAL_IMAGE="cr6608-SMARTAP-v29-CANDIDATE-sysupgrade.bin"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
PUBLISH_DIR=""

die() {
	printf 'PUBLISH FAILED: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	if [ -n "${PUBLISH_DIR}" ]; then
		case "${PUBLISH_DIR}" in
			"${RELEASES_DIR}"/.publish.*) rm -rf -- "${PUBLISH_DIR}" ;;
		esac
	fi
}
trap cleanup EXIT

for path in "${INSPECTION_LOG}" "${SOURCE_TEST_LOG}" "${BUILD_LOG}" \
	"${IMAGE}" "${FIRMWARE}" "${INSPECTOR}"; do
	[ -s "${path}" ] || die "required input is missing or empty: ${path}"
done
grep -qx 'gate_status=pass' "${INSPECTION_LOG}" || die "image inspection did not pass"
for marker in \
	'vlan_lib_tests=pass' \
	'safe_apply_tests=pass' \
	'safe_apply_runtime_tests=pass' \
	'quicksettings_contracts=pass' \
	'auth_lifecycle_test=pass' \
	'auth_lifecycle_negative_tests=pass' \
	'dashboard_ui_contracts=pass' \
	'mobile_layout_tests=pass'; do
	grep -Fqx "${marker}" "${SOURCE_TEST_LOG}" || die "source test marker is absent: ${marker}"
done

mkdir -p "${RELEASES_DIR}"
PUBLISH_DIR="$(mktemp -d "${RELEASES_DIR}/.publish.XXXXXX")"
cp -- "${IMAGE}" "${PUBLISH_DIR}/${FINAL_IMAGE}"
cp -- "${SOURCE_TEST_LOG}" "${PUBLISH_DIR}/source-tests.txt"

# A caller-supplied pass marker is not sufficient: it may belong to an older
# image. Re-run the complete fail-closed gate and require byte-for-byte output
# equality with the supplied log before publication.
"${INSPECTOR}" "${IMAGE}" "${FIRMWARE}" "${OPENWRT_DIR}" "${OPENWRT_DIR}/files" \
	> "${PUBLISH_DIR}/prepublish-inspection.txt"
grep -qx 'gate_status=pass' "${PUBLISH_DIR}/prepublish-inspection.txt" || \
	die "fresh image inspection did not pass"
cmp -s "${INSPECTION_LOG}" "${PUBLISH_DIR}/prepublish-inspection.txt" || \
	die "supplied inspection log does not match the exact image"
IMAGE_SHA256_CURRENT="$(sha256sum "${IMAGE}" | awk '{print $1}')"
printf 'image_sha256=%s\n' "${IMAGE_SHA256_CURRENT}" >> \
	"${PUBLISH_DIR}/prepublish-inspection.txt"

INPUT_MANIFEST="${PUBLISH_DIR}/build-inputs.txt"
{
	printf 'kind\tmode\tsha256_or_target\tpath\n'
	printf 'openwrt-origin\t-\t-\thttps://git.openwrt.org/openwrt/openwrt.git\n'
	printf 'openwrt-commit\t-\t-\tf0a60eee2fe051741c643ea6118718aae1ef17fb\n'
	while IFS= read -r -d '' path; do
		relative="${path#"${SCRIPT_DIR}/"}"
		if [ -L "${path}" ]; then
			printf 'source-symlink\t%s\t%s\t%s\n' \
				"$(stat -c '%a' "${path}")" "$(readlink "${path}")" "${relative}"
		elif [ -f "${path}" ]; then
			printf 'source-file\t%s\t%s\t%s\n' \
				"$(stat -c '%a' "${path}")" \
				"$(sha256sum "${path}" | awk '{print $1}')" "${relative}"
		elif [ -d "${path}" ]; then
			printf 'source-directory\t%s\t-\t%s\n' \
				"$(stat -c '%a' "${path}")" "${relative}"
		fi
	done < <(find "${SCRIPT_DIR}" -mindepth 1 -print0 | LC_ALL=C sort -z)
	for secret in key-build-v29 private-key-v29.pem; do
		secret_path="${FINAL_ROOT}/secrets/${secret}"
		[ -f "${secret_path}" ] && [ ! -L "${secret_path}" ] || \
			die "required private signing key is absent: ${secret_path}"
		printf 'private-signing-key\t%s\t%s\tsecrets/%s\n' \
			"$(stat -c '%a' "${secret_path}")" \
			"$(sha256sum "${secret_path}" | awk '{print $1}')" "${secret}"
	done
} > "${INPUT_MANIFEST}"

SOURCE_EPOCH="$(cat "${OPENWRT_DIR}/files/etc/smartap-time-anchor")"
case "${SOURCE_EPOCH}" in ''|*[!0-9]*) die "invalid Smart AP source epoch" ;; esac
tar --sort=name --mtime="@${SOURCE_EPOCH}" --owner=0 --group=0 --numeric-owner \
	-cJf "${PUBLISH_DIR}/cr6608-SMARTAP-v29-source.tar.xz" \
	-C "${SCRIPT_DIR}" .

(
	cd "${PUBLISH_DIR}"
	sha256sum "${FINAL_IMAGE}" > "${FINAL_IMAGE}.sha256"
	sha256sum -c "${FINAL_IMAGE}.sha256"
)
IMAGE_SHA256="$(awk '{print $1}' "${PUBLISH_DIR}/${FINAL_IMAGE}.sha256")"
[ "${IMAGE_SHA256}" = "${IMAGE_SHA256_CURRENT}" ] || \
	die "published image checksum changed after inspection"

inspection_value() {
	local key="$1"
	awk -v key="${key}" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' \
		"${PUBLISH_DIR}/prepublish-inspection.txt"
}

{
	printf 'release_status=candidate_pending_router_boot_test\n'
	printf 'openwrt_version=25.12.5\n'
	printf 'openwrt_revision=r33051-f5dae5ece4\n'
	printf 'openwrt_commit=f0a60eee2fe051741c643ea6118718aae1ef17fb\n'
	printf 'device=xiaomi,mi-router-cr6608\n'
	printf 'image=%s\n' "${FINAL_IMAGE}"
	printf 'image_bytes=%s\n' "$(stat -c '%s' "${PUBLISH_DIR}/${FINAL_IMAGE}")"
	printf 'image_sha256=%s\n' "${IMAGE_SHA256}"
	printf 'smartap_build_epoch=%s\n' "${SOURCE_EPOCH}"
	printf 'kernel_bytes=%s\n' "$(inspection_value kernel_bytes)"
	printf 'rootfs_bytes=%s\n' "$(inspection_value rootfs_bytes)"
	printf 'firmware_bytes=%s\n' "$(inspection_value firmware_bytes)"
	printf 'fwtool_metadata=present\n'
	printf 'fwtool_signature=present_verified\n'
	printf 'rootfs_group_world_writable_regular_files=0\n'
	printf 'source_tests=pass\n'
	printf 'image_gate=pass\n'
	printf 'source_archive=cr6608-SMARTAP-v29-source.tar.xz\n'
	printf 'source_archive_sha256=%s\n' \
		"$(sha256sum "${PUBLISH_DIR}/cr6608-SMARTAP-v29-source.tar.xz" | awk '{print $1}')"
	printf 'build_log=%s\n' "${BUILD_LOG}"
} > "${PUBLISH_DIR}/build-manifest.txt"

chmod 0644 "${PUBLISH_DIR}"/*
RELEASE_NAME="v29-${RUN_ID}-${IMAGE_SHA256:0:16}"
RELEASE_DIR="${RELEASES_DIR}/${RELEASE_NAME}"
[ ! -e "${RELEASE_DIR}" ] || die "release already exists: ${RELEASE_DIR}"
mv -- "${PUBLISH_DIR}" "${RELEASE_DIR}"
PUBLISH_DIR=""
LINK_TMP="${FINAL_ROOT}/output/.current-v29.${RUN_ID}"
ln -s -- "releases/${RELEASE_NAME}" "${LINK_TMP}"
mv -Tf -- "${LINK_TMP}" "${FINAL_ROOT}/output/current-v29"
printf 'release_dir=%s\nimage_sha256=%s\n' "${RELEASE_DIR}" "${IMAGE_SHA256}"
