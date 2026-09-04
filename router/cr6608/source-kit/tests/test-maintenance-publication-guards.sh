#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/../build.sh"
TEST_ROOT="$(mktemp -d)"
EXTRACTED="${TEST_ROOT}/release-guard-functions.sh"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# Load the exact production functions without executing build.sh's top-level
# OpenWrt/signing preflight. Function boundaries are the next top-level
# function declaration, so heredocs and shell parameter expansions are kept
# byte-for-byte and do not need a fragile brace parser.
python3 -I -B - "${BUILD_SCRIPT}" "${EXTRACTED}" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines(keepends=True)
wanted = {
    "maintenance_flashable_basename_is_expected",
    "remove_maintenance_flashables_from_bin",
    "cleanup_maintenance_flashable_staging",
    "quarantine_maintenance_flashables",
    "capture_image_inspection_hashes",
    "verify_image_inspection_hashes_unchanged",
    "verify_published_images_match_inspection",
    "cleanup_build_private_signing_keys",
    "cleanup",
    "read_regular_file_sha256",
    "verify_inspection_attestation_unchanged",
    "verify_factory38_bundle_exact_file_set",
    "verify_factory38_bound_checksum_manifest",
    "bind_factory38_bundle_to_maintenance_image",
    "verify_factory38_bundle_binding_to_publication",
    "publish_factory38_bundle",
}
starts = []
for index, line in enumerate(source):
    match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\(\) \{\n?", line)
    if match:
        starts.append((index, match.group(1)))
starts.append((len(source), "<eof>"))
chunks = []
found = set()
for position in range(len(starts) - 1):
    begin, name = starts[position]
    end, _ = starts[position + 1]
    if name in wanted:
        chunks.extend(source[begin:end])
        found.add(name)
missing = sorted(wanted - found)
if missing:
    raise SystemExit(f"missing production function(s): {', '.join(missing)}")
pathlib.Path(sys.argv[2]).write_text("".join(chunks), encoding="utf-8")
PY

# Production die exits the process. Keeping that behavior is important for
# failure-path tests executed in subshells.
die() { printf 'EXPECTED-REFUSAL: %s\n' "$*" >&2; exit 97; }
ok() { :; }
# shellcheck source=/dev/null
source "${EXTRACTED}"

# Git for Windows exposes NTFS files through a noacl mount where chmod(0600)
# still reports 0644 and chmod(0700) reports 0755. The production build runs on
# Ubuntu and exercises real modes. For this optional Windows developer run,
# emulate only those two mode-query surfaces; all path, identity, move,
# checksum, refusal, and cleanup behavior still executes unchanged.
REAL_STAT_BIN="$(command -v stat)"
REAL_FIND_BIN="$(command -v find)"
WINDOWS_NOACL=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS_NOACL=1 ;; esac
stat() {
	local stat_path=''
	if [ "$#" -ge 3 ] && [ "$1" = -c ] && [ "$2" = '%d:%i' ]; then
		stat_path="${!#}"
		if [ -n "${CR6608_TEST_STAT_FAIL_PATH:-}" ] && \
			[ "${stat_path}" = "${CR6608_TEST_STAT_FAIL_PATH}" ]; then
			return 45
		fi
		if [ -n "${CR6608_TEST_STAT_FAIL_AFTER_FIRST_PATH:-}" ] && \
			[ "${stat_path}" = "${CR6608_TEST_STAT_FAIL_AFTER_FIRST_PATH}" ]; then
			[ -n "${CR6608_TEST_STAT_SENTINEL:-}" ] || return 46
			if [ -e "${CR6608_TEST_STAT_SENTINEL}" ]; then
				return 47
			fi
			: > "${CR6608_TEST_STAT_SENTINEL}"
		fi
	fi
	if [ "${WINDOWS_NOACL}" = 1 ] && [ "$#" -eq 3 ] && \
		[ "$1" = -c ] && [ "$2" = '%a' ]; then
		if [ -d "$3" ]; then printf '700\n'; else printf '600\n'; fi
		return 0
	fi
	"${REAL_STAT_BIN}" "$@"
}
find() {
	[ "${CR6608_TEST_FIND_FAIL:-0}" != 1 ] || return 42
	if [ "${CR6608_TEST_FIND_PARTIAL_FAIL:-0}" = 1 ]; then
		printf '%s\0' './factory-original.device-private.bin'
		return 44
	fi
	if [ "${CR6608_TEST_FIND_FAIL_ON_MODE_SCAN:-0}" = 1 ]; then
		case " $* " in
			*' ! -perm 0600 '*) return 43 ;;
		esac
	fi
	if [ "${WINDOWS_NOACL}" = 1 ]; then
		case " $* " in
			*' ! -perm 0600 '*) return 0 ;;
		esac
	fi
	"${REAL_FIND_BIN}" "$@"
}

make_mode_0700_dir() {
	mkdir -- "$1"
	if ! chmod 0700 -- "$1"; then
		[ "${WINDOWS_NOACL:-0}" = 1 ] || fail "cannot set mode 700 on $1"
	fi
}

DEVICE_PROFILE='xiaomi_mi-router-cr6608'
FACTORY38_BUILD_MODE='maintenance'
PUBLISH_FLASHABLE_IMAGES=0
OPENWRT_DIR="${TEST_ROOT}/openwrt"
BIN_DIR="${OPENWRT_DIR}/bin/targets/ramips/mt7621"
LOG_DIR="${TEST_ROOT}/logs"
mkdir -p -- "${BIN_DIR}" "${LOG_DIR}"

sysupgrade_name="openwrt-test-${DEVICE_PROFILE}-squashfs-sysupgrade.bin"
firmware_name="openwrt-test-${DEVICE_PROFILE}-squashfs-firmware.bin"
printf 'sysupgrade\n' > "${BIN_DIR}/${sysupgrade_name}"
printf 'firmware\n' > "${BIN_DIR}/${firmware_name}"
printf 'keep\n' > "${BIN_DIR}/unrelated.bin"
MAINTENANCE_BIN_CLEANUP_ARMED=0
remove_maintenance_flashables_from_bin
[ -f "${BIN_DIR}/${sysupgrade_name}" ] || fail 'unarmed cleanup removed sysupgrade'
[ -f "${BIN_DIR}/${firmware_name}" ] || fail 'unarmed cleanup removed firmware'
MAINTENANCE_BIN_CLEANUP_ARMED=1
CR6608_TEST_FIND_FAIL=1
if remove_maintenance_flashables_from_bin; then
	fail 'maintenance cleanup accepted a failed find scan'
fi
CR6608_TEST_FIND_FAIL=0
[ -f "${BIN_DIR}/${sysupgrade_name}" ] || fail 'failed scan removed sysupgrade'
[ -f "${BIN_DIR}/${firmware_name}" ] || fail 'failed scan removed firmware'
remove_maintenance_flashables_from_bin
[ ! -e "${BIN_DIR}/${sysupgrade_name}" ] || fail 'bin cleanup retained sysupgrade'
[ ! -e "${BIN_DIR}/${firmware_name}" ] || fail 'bin cleanup retained firmware'
[ -f "${BIN_DIR}/unrelated.bin" ] || fail 'bin cleanup touched an unrelated file'

printf 'sysupgrade-two\n' > "${BIN_DIR}/${sysupgrade_name}"
printf 'firmware-two\n' > "${BIN_DIR}/${firmware_name}"
MAINTENANCE_FLASHABLE_DIR=''
MAINTENANCE_SYSUPGRADE_ARTIFACT=''
MAINTENANCE_FIRMWARE_ARTIFACT=''
quarantine_maintenance_flashables
[ ! -e "${BIN_DIR}/${sysupgrade_name}" ] || fail 'quarantine left sysupgrade in bin'
[ ! -e "${BIN_DIR}/${firmware_name}" ] || fail 'quarantine left firmware in bin'
[ -s "${MAINTENANCE_SYSUPGRADE_ARTIFACT}" ] || fail 'quarantined sysupgrade is absent'
[ -s "${MAINTENANCE_FIRMWARE_ARTIFACT}" ] || fail 'quarantined firmware is absent'
[ "$(stat -c '%a' "${MAINTENANCE_FLASHABLE_DIR}")" = 700 ] || \
	fail 'quarantine directory mode is not 700'
tracked_staging="${MAINTENANCE_FLASHABLE_DIR}"
cleanup_maintenance_flashable_staging
[ ! -e "${tracked_staging}" ] || fail 'tracked quarantine survived cleanup'
[ -z "${MAINTENANCE_FLASHABLE_DIR}" ] || fail 'quarantine tracking was not cleared'

outside="${TEST_ROOT}/outside"
mkdir -- "${outside}"
outside_artifact="${outside}/must-remain.bin"
printf 'sentinel\n' > "${outside_artifact}"
if (
	MAINTENANCE_FLASHABLE_DIR="${outside}"
	MAINTENANCE_SYSUPGRADE_ARTIFACT="${outside_artifact}"
	MAINTENANCE_FIRMWARE_ARTIFACT=''
	cleanup_maintenance_flashable_staging
); then
	fail 'unsafe staging directory was accepted'
fi
[ -f "${outside_artifact}" ] || fail 'unsafe cleanup removed an outside file'

inspection_root="${TEST_ROOT}/inspection-binding"
mkdir -p -- "${inspection_root}/public"
inspection_sysupgrade="${inspection_root}/sysupgrade.bin"
inspection_firmware="${inspection_root}/firmware.bin"
inspection_initramfs="${inspection_root}/initramfs.bin"
inspection_packages="${inspection_root}/packages.manifest"
printf 'inspected-sysupgrade\n' > "${inspection_sysupgrade}"
printf 'inspected-firmware\n' > "${inspection_firmware}"
printf 'inspected-initramfs\n' > "${inspection_initramfs}"
printf 'inspected-packages\n' > "${inspection_packages}"
capture_image_inspection_hashes "${inspection_sysupgrade}" "${inspection_firmware}" \
	"${inspection_initramfs}" "${inspection_packages}"
verify_image_inspection_hashes_unchanged "${inspection_sysupgrade}" \
	"${inspection_firmware}" "${inspection_initramfs}" "${inspection_packages}"
printf 'mutation-during-inspection\n' >> "${inspection_initramfs}"
if (verify_image_inspection_hashes_unchanged "${inspection_sysupgrade}" \
	"${inspection_firmware}" "${inspection_initramfs}" "${inspection_packages}"); then
	fail 'source image mutation after inspection hash capture was accepted'
fi
printf 'inspected-initramfs\n' > "${inspection_initramfs}"
verify_image_inspection_hashes_unchanged "${inspection_sysupgrade}" \
	"${inspection_firmware}" "${inspection_initramfs}" "${inspection_packages}"

PUBLISH_DIR="${inspection_root}/public"
FINAL_IMAGE='published-sysupgrade.bin'
COMBINED_IMAGE='published-firmware.bin'
INITRAMFS_IMAGE='published-initramfs.bin'
PUBLISH_FLASHABLE_IMAGES=1
cp -- "${inspection_sysupgrade}" "${PUBLISH_DIR}/${FINAL_IMAGE}"
cp -- "${inspection_firmware}" "${PUBLISH_DIR}/${COMBINED_IMAGE}"
cp -- "${inspection_initramfs}" "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
cp -- "${inspection_packages}" "${PUBLISH_DIR}/openwrt-package-manifest.txt"
verify_published_images_match_inspection
printf 'mutation-after-inspection\n' >> "${PUBLISH_DIR}/${COMBINED_IMAGE}"
if (verify_published_images_match_inspection); then
	fail 'published image mutation after inspection was accepted'
fi
cp -- "${inspection_firmware}" "${PUBLISH_DIR}/${COMBINED_IMAGE}"
verify_published_images_match_inspection

set_cleanup_globals() {
	local root="$1"
	local armed="$2"
	OPENWRT_DIR="${root}/openwrt"
	BIN_DIR="${OPENWRT_DIR}/bin/targets/ramips/mt7621"
	LOG_DIR="${root}/logs"
	RELEASES_DIR="${root}/releases"
	FACTORY38_BUILD_MODE='maintenance'
	PUBLISH_FLASHABLE_IMAGES=0
	MAINTENANCE_BIN_CLEANUP_ARMED="${armed}"
	MAINTENANCE_FLASHABLE_DIR=''
	MAINTENANCE_SYSUPGRADE_ARTIFACT=''
	MAINTENANCE_FIRMWARE_ARTIFACT=''
	PUBLISH_DIR=''
	PUBLISH_DIR_IDENTITY=''
	PUBLISH_PENDING_DIR=''
	PUBLISH_PENDING_IDENTITY=''
	FACTORY38_BUNDLE_DIR=''
	FACTORY38_WORK_DIR=''
	FACTORY38_WORK_IDENTITY=''
	FACTORY38_PRIVATE_PARENT=''
	FACTORY38_PRIVATE_PARENT_IDENTITY=''
	FACTORY38_PENDING_OUTPUT=''
	FACTORY38_PENDING_OUTPUT_IDENTITY=''
	BUILD_PRIVATE_KEYS_INSTALLED=0
	mkdir -p -- "${BIN_DIR}" "${LOG_DIR}" "${RELEASES_DIR}"
}

signing_cleanup_root="${TEST_ROOT}/signing-cleanup"
set_cleanup_globals "${signing_cleanup_root}" 0
printf 'firmware-private-key\n' > "${OPENWRT_DIR}/key-build"
printf 'apk-private-key\n' > "${OPENWRT_DIR}/private-key.pem"
chmod 0600 -- "${OPENWRT_DIR}/key-build" "${OPENWRT_DIR}/private-key.pem"
cleanup_build_private_signing_keys
[ -f "${OPENWRT_DIR}/key-build" ] && [ -f "${OPENWRT_DIR}/private-key.pem" ] || \
	fail 'inactive build-key cleanup removed retained keys'
BUILD_PRIVATE_KEYS_INSTALLED=1
cleanup_build_private_signing_keys
[ ! -e "${OPENWRT_DIR}/key-build" ] && [ ! -e "${OPENWRT_DIR}/private-key.pem" ] || \
	fail 'active build-key cleanup retained temporary private keys'
[ "${BUILD_PRIVATE_KEYS_INSTALLED}" = 0 ] || fail 'build-key cleanup flag was not disarmed'

unarmed_root="${TEST_ROOT}/cleanup-unarmed"
set_cleanup_globals "${unarmed_root}" 0
printf 'must-survive-unarmed\n' > "${BIN_DIR}/${sysupgrade_name}"
(
	set_cleanup_globals "${unarmed_root}" 0
	trap 'cleanup $?' EXIT
	exit 0
)
[ -f "${unarmed_root}/openwrt/bin/targets/ramips/mt7621/${sysupgrade_name}" ] || \
	fail 'unarmed EXIT cleanup deleted another invocation output'

armed_root="${TEST_ROOT}/cleanup-armed"
set_cleanup_globals "${armed_root}" 1
printf 'armed-sysupgrade\n' > "${BIN_DIR}/${sysupgrade_name}"
printf 'armed-firmware\n' > "${BIN_DIR}/${firmware_name}"
armed_staging="${LOG_DIR}/.maintenance-flashables.exit-test"
make_mode_0700_dir "${armed_staging}"
printf 'staged-sysupgrade\n' > \
	"${armed_staging}/cr6608-maintenance-sysupgrade.DO-NOT-FLASH.bin"
printf 'staged-firmware\n' > \
	"${armed_staging}/cr6608-maintenance-firmware.DO-NOT-FLASH.bin"
(
	set_cleanup_globals "${armed_root}" 1
	MAINTENANCE_FLASHABLE_DIR="${armed_staging}"
	MAINTENANCE_SYSUPGRADE_ARTIFACT="${armed_staging}/cr6608-maintenance-sysupgrade.DO-NOT-FLASH.bin"
	MAINTENANCE_FIRMWARE_ARTIFACT="${armed_staging}/cr6608-maintenance-firmware.DO-NOT-FLASH.bin"
	trap 'cleanup $?' EXIT
	exit 0
)
[ ! -e "${armed_staging}" ] || fail 'armed EXIT cleanup retained staging'
[ ! -e "${armed_root}/openwrt/bin/targets/ramips/mt7621/${sysupgrade_name}" ] || \
	fail 'armed EXIT cleanup retained sysupgrade'
[ ! -e "${armed_root}/openwrt/bin/targets/ramips/mt7621/${firmware_name}" ] || \
	fail 'armed EXIT cleanup retained firmware'

find_failure_root="${TEST_ROOT}/cleanup-find-failure"
set_cleanup_globals "${find_failure_root}" 1
set +e
(
	set_cleanup_globals "${find_failure_root}" 1
	CR6608_TEST_FIND_FAIL=1
	trap 'cleanup $?' EXIT
	exit 0
)
find_failure_status=$?
set -e
[ "${find_failure_status}" -ne 0 ] || \
	fail 'successful build status survived EXIT cleanup scan failure'

term_root="${TEST_ROOT}/cleanup-term"
set_cleanup_globals "${term_root}" 1
printf 'term-sysupgrade\n' > "${BIN_DIR}/${sysupgrade_name}"
printf 'term-firmware\n' > "${BIN_DIR}/${firmware_name}"
set +e
(
	set_cleanup_globals "${term_root}" 1
	trap 'cleanup $?' EXIT
	trap 'exit 143' TERM
	kill -TERM "${BASHPID}"
	exit 99
)
term_status=$?
set -e
[ "${term_status}" -eq 143 ] || fail "TERM cleanup exited ${term_status}, expected 143"
[ ! -e "${term_root}/openwrt/bin/targets/ramips/mt7621/${sysupgrade_name}" ] || \
	fail 'TERM cleanup retained sysupgrade'
[ ! -e "${term_root}/openwrt/bin/targets/ramips/mt7621/${firmware_name}" ] || \
	fail 'TERM cleanup retained firmware'

# UL-MURU qualification publication uses its own release namespace. If a
# failure lands after the atomic staging rename but before publication state is
# cleared, EXIT cleanup must remove the inode-bound partial release just as it
# does for maintenance and candidate namespaces.
qualification_root="${TEST_ROOT}/cleanup-qualification-pending"
set_cleanup_globals "${qualification_root}" 0
qualification_pending="${RELEASES_DIR}/qualification-v86-test"
mkdir -- "${qualification_pending}"
printf 'partial\n' > "${qualification_pending}/partial.txt"
qualification_identity="$(stat -c '%d:%i' "${qualification_pending}")"
set +e
(
	set_cleanup_globals "${qualification_root}" 0
	PUBLISH_PENDING_DIR="${qualification_pending}"
	PUBLISH_PENDING_IDENTITY="${qualification_identity}"
	trap 'cleanup $?' EXIT
	exit 0
)
qualification_cleanup_status=$?
set -e
[ "${qualification_cleanup_status}" -ne 0 ] || \
	fail 'partial qualification publication cleanup preserved a successful status'
[ ! -e "${qualification_pending}" ] || \
	fail 'EXIT cleanup retained a partial UL-MURU qualification release'

private_parent="${TEST_ROOT}/private"
bundle="${private_parent}/.factory38-device-bundle-test"
make_mode_0700_dir "${private_parent}"
make_mode_0700_dir "${bundle}"
for file in \
	factory-original.device-private.bin \
	factory-38.device-private.bin \
	factory-original.block0.device-private.bin \
	factory-38.block0.device-private.bin; do
	printf '%s\n' "${file}" > "${bundle}/${file}"
done
printf '{}\n' > "${bundle}/factory-38.manifest.json"
printf 'private test bundle\n' > "${bundle}/README-DEVICE-PRIVATE.txt"
chmod 0600 -- "${bundle}"/*

image="${TEST_ROOT}/maintenance-initramfs.bin"
inspector="${TEST_ROOT}/inspect-image.sh"
inspection_log="${TEST_ROOT}/inspection.txt"
package_manifest="${TEST_ROOT}/packages.manifest"
printf 'ram-only-image\n' > "${image}"
printf '# inspector\n' > "${inspector}"
printf '%s\n' \
	'image_integrity_gate_status=pass' \
	'release_gate_status=blocked_pending_router_runtime_and_external_rf_verification' \
	> "${inspection_log}"
printf 'base-files - 1\n' > "${package_manifest}"

FACTORY38_BUNDLE_ENABLED=1
FACTORY38_BUNDLE_DIR="${bundle}"
FACTORY38_WORK_IDENTITY="$(stat -c '%d:%i' "${bundle}")"
FACTORY38_PRIVATE_PARENT="${private_parent}"
FACTORY38_PRIVATE_PARENT_IDENTITY="$(stat -c '%d:%i' "${private_parent}")"
FACTORY38_PRIVATE_OUTPUT="${private_parent}/published-device-private"
KIT_HEAD_COMMIT='0123456789abcdef0123456789abcdef01234567'
OPENWRT_COMMIT='89abcdef0123456789abcdef0123456789abcdef'
INITRAMFS_IMAGE='cr6608-SMARTAP-v78-MAINTENANCE-RAMBOOT-ONLY-initramfs-kernel.bin'
INSPECTOR="${inspector}"
INSPECTION_LOG="${inspection_log}"
PUBLISH_DIR="${TEST_ROOT}/public-release-staging"
make_mode_0700_dir "${PUBLISH_DIR}"
cp -- "${image}" "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
cp -- "${inspection_log}" "${PUBLISH_DIR}/prepublish-inspection.txt"
cp -- "${package_manifest}" "${PUBLISH_DIR}/openwrt-package-manifest.txt"
INSPECTOR_EXECUTED_SHA256="$(read_regular_file_sha256 "${INSPECTOR}")"
INSPECTION_LOG_VERIFIED_SHA256="$(read_regular_file_sha256 "${INSPECTION_LOG}")"
verify_inspection_attestation_unchanged "${PUBLISH_DIR}"
trusted_inspector="${TEST_ROOT}/trusted-inspector.sh"
trusted_inspection_log="${TEST_ROOT}/trusted-inspection.log"
cp -- "${INSPECTOR}" "${trusted_inspector}"
cp -- "${INSPECTION_LOG}" "${trusted_inspection_log}"
printf '# post-execution inspector mutation\n' >> "${INSPECTOR}"
if (verify_inspection_attestation_unchanged "${PUBLISH_DIR}"); then
	fail 'post-execution inspector mutation was accepted'
fi
cp -- "${trusted_inspector}" "${INSPECTOR}"
printf 'post-gate-log-mutation=1\n' >> "${INSPECTION_LOG}"
if (verify_inspection_attestation_unchanged "${PUBLISH_DIR}"); then
	fail 'post-gate source inspection-log mutation was accepted'
fi
cp -- "${trusted_inspection_log}" "${INSPECTION_LOG}"
printf 'staged-log-mutation=1\n' >> "${PUBLISH_DIR}/prepublish-inspection.txt"
if (verify_inspection_attestation_unchanged "${PUBLISH_DIR}"); then
	fail 'staged inspection-log mutation was accepted'
fi
cp -- "${trusted_inspection_log}" "${PUBLISH_DIR}/prepublish-inspection.txt"
verify_inspection_attestation_unchanged "${PUBLISH_DIR}"
partial_failure_bundle="${private_parent}/.factory38-partial-find-failure"
cp -a -- "${bundle}" "${partial_failure_bundle}"
if (
	FACTORY38_BUNDLE_DIR="${partial_failure_bundle}"
	FACTORY38_WORK_IDENTITY="$(stat -c '%d:%i' "${partial_failure_bundle}")"
	CR6608_TEST_FIND_PARTIAL_FAIL=1
	bind_factory38_bundle_to_maintenance_image "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
); then
	fail 'private checksum generation accepted a partial failed find pipeline'
fi
rm -rf -- "${partial_failure_bundle}"
bind_factory38_bundle_to_maintenance_image "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
verify_factory38_bundle_binding_to_publication

python3 -I -B - "${bundle}/factory-38.manifest.json" \
	"${PUBLISH_DIR}/${INITRAMFS_IMAGE}" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
binding = manifest.get("maintenance_binding")
if not isinstance(binding, dict):
    raise SystemExit("maintenance_binding is absent")
expected = hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
if binding.get("factory38_build_mode") != "maintenance":
    raise SystemExit("maintenance build mode is not bound")
if binding.get("maintenance_initramfs_sha256") != expected:
    raise SystemExit("maintenance image hash is not bound")
if binding.get("image_integrity_gate_status") != "pass":
    raise SystemExit("inspection pass state is not bound")
PY
printf 'mutated-after-binding\n' >> "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
if (verify_factory38_bundle_binding_to_publication); then
	fail 'post-binding maintenance image mutation was accepted'
fi
cp -- "${image}" "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
verify_factory38_bundle_binding_to_publication
(
	cd "${bundle}"
	sha256sum -c SHA256SUMS >/dev/null
)
[ "$(find "${bundle}" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" = 8 ] || \
	fail 'bound bundle file count is not exact'

trusted_candidate="${TEST_ROOT}/trusted-factory38-candidate.bin"
cp -- "${bundle}/factory-38.device-private.bin" "${trusted_candidate}"
printf 'self-consistent-binary-mutation\n' >> "${bundle}/factory-38.device-private.bin"
(
	cd "${bundle}"
	find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
		LC_ALL=C sort -z | xargs -0 sha256sum -- > SHA256SUMS
)
if (publish_factory38_bundle "${PUBLISH_DIR}"); then
	fail 'self-consistent private binary and checksum mutation was accepted'
fi
[ -d "${bundle}" ] || fail 'rejected binary mutation moved its private source'
cp -- "${trusted_candidate}" "${bundle}/factory-38.device-private.bin"
(
	cd "${bundle}"
	find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
		LC_ALL=C sort -z | xargs -0 sha256sum -- > SHA256SUMS
)
verify_factory38_bundle_binding_to_publication

printf 'unexpected-private-file\n' > "${bundle}/unexpected.device-private"
chmod 0600 -- "${bundle}/unexpected.device-private"
if (publish_factory38_bundle "${PUBLISH_DIR}"); then
	fail 'additional regular mode-0600 private file was accepted'
fi
[ -d "${bundle}" ] || fail 'rejected additional file moved the private source'
rm -f -- "${bundle}/unexpected.device-private"
verify_factory38_bundle_binding_to_publication

trusted_manifest="${TEST_ROOT}/trusted-factory38-manifest.json"
cp -- "${bundle}/factory-38.manifest.json" "${trusted_manifest}"
python3 -I -B - "${bundle}/factory-38.manifest.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
manifest["maintenance_binding"]["source_kit_commit"] = "0" * 40
path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
(
	cd "${bundle}"
	find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
		LC_ALL=C sort -z | xargs -0 sha256sum -- > SHA256SUMS
)
if (publish_factory38_bundle "${PUBLISH_DIR}"); then
	fail 'self-consistent but untrusted private binding mutation was accepted'
fi
[ -d "${bundle}" ] || fail 'rejected private binding mutation moved its source'
cp -- "${trusted_manifest}" "${bundle}/factory-38.manifest.json"
(
	cd "${bundle}"
	find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
		LC_ALL=C sort -z | xargs -0 sha256sum -- > SHA256SUMS
)
CR6608_TEST_FIND_FAIL=1
if (publish_factory38_bundle "${PUBLISH_DIR}"); then
	fail 'private publication accepted a failed entry-type find scan'
fi
CR6608_TEST_FIND_FAIL=0
[ -d "${bundle}" ] || fail 'failed entry-type scan moved the private source'
CR6608_TEST_FIND_FAIL_ON_MODE_SCAN=1
if (publish_factory38_bundle "${PUBLISH_DIR}"); then
	fail 'private publication accepted a failed mode find scan'
fi
CR6608_TEST_FIND_FAIL_ON_MODE_SCAN=0
[ -d "${bundle}" ] || fail 'failed mode scan moved the private source'

identity_source="${private_parent}/.factory38-device-bundle-stat-failure"
identity_destination="${private_parent}/stat-failure-destination"
identity_sentinel="${TEST_ROOT}/stat-source-seen"
cp -a -- "${bundle}" "${identity_source}"
identity_source_id="$("${REAL_STAT_BIN}" -c '%d:%i' "${identity_source}")"
if (
	FACTORY38_BUNDLE_DIR="${identity_source}"
	FACTORY38_WORK_IDENTITY="${identity_source_id}"
	FACTORY38_PRIVATE_OUTPUT="${identity_destination}"
	CR6608_TEST_STAT_FAIL_AFTER_FIRST_PATH="${identity_source}"
	CR6608_TEST_STAT_FAIL_PATH="${identity_destination}"
	CR6608_TEST_STAT_SENTINEL="${identity_sentinel}"
	publish_factory38_bundle "${PUBLISH_DIR}"
); then
	fail 'failed source and output identity lookups were accepted'
fi
[ -d "${identity_source}" ] || fail 'failed source identity lookup moved the private source'
[ ! -e "${identity_destination}" ] || fail 'failed source identity lookup created an output'
rm -rf -- "${identity_source}"
rm -f -- "${identity_sentinel}"
publish_factory38_bundle "${PUBLISH_DIR}"
[ ! -e "${bundle}" ] || fail 'published bundle remained at its staging path'
[ -d "${FACTORY38_PRIVATE_OUTPUT}" ] || fail 'private publication is absent'
(
	cd "${FACTORY38_PRIVATE_OUTPUT}"
	sha256sum -c SHA256SUMS >/dev/null
)

race_source="${private_parent}/.factory38-device-bundle-race"
cp -a -- "${FACTORY38_PRIVATE_OUTPUT}" "${race_source}"
race_destination="${private_parent}/existing-destination"
make_mode_0700_dir "${race_destination}"
printf 'do-not-replace\n' > "${race_destination}/sentinel"
chmod 0600 -- "${race_destination}/sentinel"
if (
	FACTORY38_BUNDLE_DIR="${race_source}"
	FACTORY38_WORK_IDENTITY="$(stat -c '%d:%i' "${race_source}")"
	FACTORY38_PRIVATE_OUTPUT="${race_destination}"
	publish_factory38_bundle "${PUBLISH_DIR}"
); then
	fail 'existing private destination was accepted'
fi
[ -d "${race_source}" ] || fail 'refused private source was moved or deleted'
[ "$(cat "${race_destination}/sentinel")" = 'do-not-replace' ] || \
	fail 'existing private destination was replaced'

printf 'maintenance_publication_guard_tests=pass\n'
