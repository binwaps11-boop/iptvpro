#!/usr/bin/env bash
# Clean source build of OpenWrt 25.12.5 for Xiaomi Mi Router CR6608.

set -euo pipefail
umask 022

OPENWRT_URL="https://git.openwrt.org/openwrt/openwrt.git"
OPENWRT_TAG="v25.12.5"
OPENWRT_COMMIT="f0a60eee2fe051741c643ea6118718aae1ef17fb"
DEVICE_PROFILE="xiaomi_mi-router-cr6608"
FINAL_IMAGE="cr6608-SMARTAP-v29-CANDIDATE-sysupgrade.bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINAL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_FILES="${SCRIPT_DIR}/files"
SRC_PATCH="${SCRIPT_DIR}/patches/999-mt7915-cr6608-rf-38dbm-linear.patch"
SRC_SERIAL_PATCH="${SCRIPT_DIR}/patches/998-cr6608-disable-serial-console.patch"
SRC_KERNEL_CONSOLE_PATCH="${SCRIPT_DIR}/patches/997-cr6608-disable-8250-kernel-console.patch"
SRC_SEED="${SCRIPT_DIR}/cr6608.seed.config"
INSPECTOR="${SCRIPT_DIR}/inspect-image.sh"
VLAN_TEST="${SCRIPT_DIR}/tests/test-vlan-lib.sh"
SAFE_APPLY_TEST="${SCRIPT_DIR}/tests/test-safe-apply.sh"
SAFE_APPLY_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-safe-apply-runtime.sh"
QUICKSETTINGS_CONTRACT_TEST="${SCRIPT_DIR}/tests/test-quicksettings-contracts.sh"
AUTH_LIFECYCLE_TEST="${SCRIPT_DIR}/tests/test-auth-lifecycle.sh"
UI_CONTRACT_TEST="${SCRIPT_DIR}/tests/test-dashboard-ui-contracts.sh"
MOBILE_LAYOUT_TEST="${SCRIPT_DIR}/tests/test-mobile-layout.js"
ROUTER_QUICKSETTINGS_TEST="${SCRIPT_DIR}/tests/router-quicksettings-dryrun.sh"
ROUTER_VLAN_ROUNDTRIP_TEST="${SCRIPT_DIR}/tests/router-vlan-roundtrip.sh"
SRC_FW_SIGNING_KEY="${CR6608_FW_SIGNING_KEY:-${FINAL_ROOT}/secrets/key-build-v29}"
SRC_FW_SIGNING_PUB="${SCRIPT_DIR}/signing/key-build.pub"
SRC_FW_SIGNING_CERT="${SCRIPT_DIR}/signing/key-build.ucert"
SRC_APK_SIGNING_KEY="${CR6608_APK_SIGNING_KEY:-${FINAL_ROOT}/secrets/private-key-v29.pem}"
SRC_APK_SIGNING_PUB="${SCRIPT_DIR}/signing/public-key.pem"
OPENWRT_DIR="${FINAL_ROOT}/openwrt"
LOG_DIR="${FINAL_ROOT}/logs"
OUTPUT_DIR="${FINAL_ROOT}/output"
RELEASES_DIR="${OUTPUT_DIR}/releases"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
BUILD_EPOCH="${SMARTAP_BUILD_EPOCH:-$(date -u +%s)}"
BUILD_TIME=""
BUILD_LOG="${LOG_DIR}/build-v29-candidate-${RUN_ID}.log"
DOWNLOAD_LOG="${LOG_DIR}/download-v29-candidate-${RUN_ID}.log"
MT76_LOG="${LOG_DIR}/mt76-prepare-v29-candidate-${RUN_ID}.log"
DIFFCONFIG_LOG="${LOG_DIR}/v29-candidate-diffconfig-${RUN_ID}.txt"
INPUT_MANIFEST="${LOG_DIR}/build-inputs-v29-candidate-${RUN_ID}.txt"
INSPECTION_LOG="${LOG_DIR}/prepublish-inspection-v29-candidate-${RUN_ID}.txt"
LOCK_FILE="${FINAL_ROOT}/.cr6608-build.lock"
PUBLISH_DIR=""
CR6608_DTS_RELATIVE="target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts"
EXPECTED_SERIAL_DTS_SHA256="7e867d664d3eb07e238c0caa534507f95978de55933a8083bdb9e8fca6f8b7ed"
CR6608_KERNEL_CONFIG_RELATIVE="target/linux/ramips/mt7621/config-6.12"
EXPECTED_SERIAL_KERNEL_CONFIG_SHA256="411fe5c77dd508086e1432f5f6deb9b40036e9bb6e4993c2342cc588e4478c1b"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    [ok] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
	if [ -n "${PUBLISH_DIR}" ]; then
		case "${PUBLISH_DIR}" in
			"${RELEASES_DIR}"/.publish.*) rm -rf -- "${PUBLISH_DIR}" || true ;;
		esac
	fi
}

on_error() {
	local ec=$?
	trap - ERR
	printf '\n\033[1;31mBUILD FAILED (exit %s) at line %s: %s\033[0m\n' \
		"${ec}" "${BASH_LINENO[0]:-?}" "${BASH_COMMAND}" >&2
	exit "${ec}"
}
trap on_error ERR
trap cleanup EXIT

case "${BUILD_EPOCH}" in
	''|*[!0-9]*) die "SMARTAP_BUILD_EPOCH must be a decimal Unix timestamp" ;;
esac
[ "${#BUILD_EPOCH}" -eq 10 ] && [ "${BUILD_EPOCH}" -ge 1577836800 ] 2>/dev/null ||
	die "SMARTAP_BUILD_EPOCH is outside the accepted range"
BUILD_TIME="$(date -u -d "@${BUILD_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)" ||
	die "SMARTAP_BUILD_EPOCH cannot be formatted"

if [ "$(id -u)" -eq 0 ]; then
	die "Refusing to run OpenWrt buildroot as root."
fi

required=(
	bash git make gcc g++ gawk flex bison gettext python3 rsync perl tar xz
	unzip file wget sha256sum flock find sort stat readlink cmp diff mktemp od
	nproc date node sh install openssl
)
missing=()
for cmd in "${required[@]}"; do
	command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
done
if [ "${#missing[@]}" -ne 0 ]; then
	die "Missing Ubuntu build tools: ${missing[*]}"
fi

mkdir -p "${LOG_DIR}" "${OUTPUT_DIR}" "${RELEASES_DIR}"
exec {LOCK_FD}>"${LOCK_FILE}"
flock -n "${LOCK_FD}" || die "Another CR6608 build holds ${LOCK_FILE}"

recreate_link() {
	local root="$1"
	local relative_path="$2"
	local target="$3"
	local path="${root}/${relative_path}"
	[ -d "$(dirname "${path}")" ] || die "Symlink parent missing: ${relative_path}"
	if [ -e "${path}" ] && [ ! -L "${path}" ]; then
		die "Refusing to replace non-symlink overlay path: ${relative_path}"
	fi
	rm -f -- "${path}"
	ln -s -- "${target}" "${path}"
	[ -L "${path}" ] && [ "$(readlink "${path}")" = "${target}" ] || \
		die "Could not create exact overlay symlink: ${relative_path} -> ${target}"
}

assert_link() {
	local root="$1"
	local relative_path="$2"
	local target="$3"
	local path="${root}/${relative_path}"
	[ -L "${path}" ] || die "Required overlay symlink missing: ${relative_path}"
	[ "$(readlink "${path}")" = "${target}" ] || \
		die "Wrong overlay symlink target: ${relative_path}"
}

recreate_required_links() {
	local root="$1"
	recreate_link "${root}" usr/share/ucode/luci/template/themes/bootstrap-dark bootstrap
	recreate_link "${root}" usr/share/ucode/luci/template/themes/bootstrap-light bootstrap
	recreate_link "${root}" www/luci-static/bootstrap-dark bootstrap
	recreate_link "${root}" www/luci-static/bootstrap-light bootstrap
	recreate_link "${root}" www/cgi-bin/cgi-exec ../../usr/libexec/cgi-io
	recreate_link "${root}" www/cgi-bin/cgi-upload ../../usr/libexec/cgi-io
	recreate_link "${root}" www/cgi-bin/cgi-backup ../../usr/libexec/cgi-io
	recreate_link "${root}" www/cgi-bin/cgi-download ../../usr/libexec/cgi-io
}

assert_required_links() {
	local root="$1"
	assert_link "${root}" usr/share/ucode/luci/template/themes/bootstrap-dark bootstrap
	assert_link "${root}" usr/share/ucode/luci/template/themes/bootstrap-light bootstrap
	assert_link "${root}" www/luci-static/bootstrap-dark bootstrap
	assert_link "${root}" www/luci-static/bootstrap-light bootstrap
	assert_link "${root}" www/cgi-bin/cgi-exec ../../usr/libexec/cgi-io
	assert_link "${root}" www/cgi-bin/cgi-upload ../../usr/libexec/cgi-io
	assert_link "${root}" www/cgi-bin/cgi-backup ../../usr/libexec/cgi-io
	assert_link "${root}" www/cgi-bin/cgi-download ../../usr/libexec/cgi-io
}

normalize_source_permissions() {
	local writable_list
	writable_list="$(mktemp "${LOG_DIR}/.writable-source.XXXXXX")"
	find "${OPENWRT_DIR}" \
		\( -path "${OPENWRT_DIR}/.git" -o \
		   -path "${OPENWRT_DIR}/build_dir" -o \
		   -path "${OPENWRT_DIR}/staging_dir" -o \
		   -path "${OPENWRT_DIR}/bin" -o \
		   -path "${OPENWRT_DIR}/tmp" -o \
		   -path "${OPENWRT_DIR}/dl" \) -prune -o \
		-type f -perm /022 -print0 > "${writable_list}"
	if [ -s "${writable_list}" ]; then
		xargs -0r chmod go-w < "${writable_list}"
	fi
	rm -f -- "${writable_list}"
}

record_regular_input() {
	local kind="$1"
	local path="$2"
	local relative_path
	case "${path}" in
		"${SCRIPT_DIR}"/*) relative_path="${path#"${SCRIPT_DIR}/"}" ;;
		"${FINAL_ROOT}/secrets"/*) relative_path="secrets/${path##*/}" ;;
		*) die "Input is outside the final source and secrets roots: ${path}" ;;
	esac
	printf '%s\t%s\t%s\t%s\n' \
		"${kind}" "$(stat -c '%a' "${path}")" \
		"$(sha256sum "${path}" | awk '{print $1}')" "${relative_path}"
}

write_input_manifest() {
	local output="$1"
	local temporary="${output}.tmp.$$"
	{
		printf 'kind\tmode\tsha256_or_target\tpath\n'
		printf 'openwrt-origin\t-\t-\t%s\n' "${OPENWRT_URL}"
		printf 'openwrt-commit\t-\t-\t%s\n' "${OPENWRT_COMMIT}"
		printf 'generated-file\t644\t%s\t%s\n' \
			"$(printf '%s\n' "${BUILD_TIME}" | sha256sum | awk '{print $1}')" \
			'files/etc/smartap-build-time'
		printf 'generated-file\t644\t%s\t%s\n' \
			"$(printf '%s\n' "${BUILD_EPOCH}" | sha256sum | awk '{print $1}')" \
		'files/etc/smartap-time-anchor'
		record_regular_input build-script "${SCRIPT_DIR}/build.sh"
		record_regular_input inspection-script "${INSPECTOR}"
		record_regular_input source-test "${VLAN_TEST}"
		record_regular_input source-test "${SAFE_APPLY_TEST}"
		record_regular_input source-test "${SAFE_APPLY_RUNTIME_TEST}"
		record_regular_input source-test "${QUICKSETTINGS_CONTRACT_TEST}"
		record_regular_input source-test "${AUTH_LIFECYCLE_TEST}"
		record_regular_input source-test "${UI_CONTRACT_TEST}"
		record_regular_input browser-layout-test "${MOBILE_LAYOUT_TEST}"
		record_regular_input router-runtime-test "${ROUTER_QUICKSETTINGS_TEST}"
		record_regular_input router-runtime-test "${ROUTER_VLAN_ROUNDTRIP_TEST}"
		record_regular_input seed "${SRC_SEED}"
		record_regular_input patch "${SRC_PATCH}"
		record_regular_input platform-patch "${SRC_SERIAL_PATCH}"
		record_regular_input firmware-signing-private-key "${SRC_FW_SIGNING_KEY}"
		record_regular_input firmware-signing-public-key "${SRC_FW_SIGNING_PUB}"
		record_regular_input firmware-signing-certificate "${SRC_FW_SIGNING_CERT}"
		record_regular_input apk-signing-private-key "${SRC_APK_SIGNING_KEY}"
		record_regular_input apk-signing-public-key "${SRC_APK_SIGNING_PUB}"
		while IFS= read -r -d '' path; do
			relative_path="${path#"${SCRIPT_DIR}/"}"
			case "${relative_path}" in
				*$'\n'*|*$'\t'*) die "Unsupported overlay path characters: ${relative_path}" ;;
			esac
			if [ -L "${path}" ]; then
				target="$(readlink "${path}")"
				case "${target}" in
					*$'\n'*|*$'\t'*) die "Unsupported symlink target characters: ${relative_path}" ;;
				esac
				printf 'overlay-symlink\t%s\t%s\t%s\n' \
					"$(stat -c '%a' "${path}")" "${target}" "${relative_path}"
			elif [ -f "${path}" ]; then
				printf 'overlay-file\t%s\t%s\t%s\n' \
					"$(stat -c '%a' "${path}")" \
					"$(sha256sum "${path}" | awk '{print $1}')" "${relative_path}"
			elif [ -d "${path}" ]; then
				printf 'overlay-directory\t%s\t-\t%s\n' \
					"$(stat -c '%a' "${path}")" "${relative_path}"
			else
				die "Unsupported overlay input type: ${relative_path}"
			fi
		done < <(find "${SRC_FILES}" -mindepth 1 -print0 | LC_ALL=C sort -z)
	} > "${temporary}"
	mv -f -- "${temporary}" "${output}"
	chmod 0644 "${output}"
}

assert_origin() {
	mapfile -t origin_urls < <(git -C "${OPENWRT_DIR}" remote get-url --all origin)
	[ "${#origin_urls[@]}" -eq 1 ] || die "OpenWrt origin must have exactly one URL"
	[ "${origin_urls[0]}" = "${OPENWRT_URL}" ] || \
		die "Unexpected OpenWrt origin: ${origin_urls[0]}"
}

assert_official_checkout() {
	assert_origin
	[ "$(git -C "${OPENWRT_DIR}" rev-parse HEAD)" = "${OPENWRT_COMMIT}" ] || \
		die "OpenWrt HEAD is not ${OPENWRT_COMMIT}"
	[ "$(git -C "${OPENWRT_DIR}" rev-parse "${OPENWRT_TAG}^{commit}")" = \
		"${OPENWRT_COMMIT}" ] || die "${OPENWRT_TAG} does not peel to ${OPENWRT_COMMIT}"
}

verify_serial_console_patch() {
	local dts="${OPENWRT_DIR}/${CR6608_DTS_RELATIVE}"
	local kernel_config="${OPENWRT_DIR}/${CR6608_KERNEL_CONFIG_RELATIVE}"
	mapfile -t tracked_changes < <(git -C "${OPENWRT_DIR}" diff --name-only --)
	[ "${#tracked_changes[@]}" -eq 2 ] && \
		printf '%s\n' "${tracked_changes[@]}" | grep -Fqx "${CR6608_DTS_RELATIVE}" && \
		printf '%s\n' "${tracked_changes[@]}" | grep -Fqx "${CR6608_KERNEL_CONFIG_RELATIVE}" || \
		die "Unexpected tracked OpenWrt source change"
	[ "$(sha256sum "${dts}" | awk '{print $1}')" = \
		"${EXPECTED_SERIAL_DTS_SHA256}" ] || die "Serial-disabled CR6608 DTS changed"
	grep -Fqx $'\t\tbootargs = "rootfstype=squashfs,jffs2 console=ttynull";' "${dts}" || \
		die "CR6608 DTS bootargs are not serial-free"
	grep -Fqx $'\t\tbootargs-override = "rootfstype=squashfs,jffs2 console=ttynull";' "${dts}" || \
		die "CR6608 DTS does not override bootloader console arguments"
	if grep -Eq 'console=ttyS[0-9]|stdout-path' "${dts}"; then
		die "CR6608 DTS still exposes a serial console"
	fi
	[ "$(sha256sum "${kernel_config}" | awk '{print $1}')" = \
		"${EXPECTED_SERIAL_KERNEL_CONFIG_SHA256}" ] || \
		die "Serial-console-disabled mt7621 kernel config changed"
	grep -Fqx '# CONFIG_SERIAL_8250_CONSOLE is not set' "${kernel_config}" || \
		die "mt7621 kernel config still enables the 8250 console"
	grep -Fqx 'CONFIG_NULL_TTY=y' "${kernel_config}" || \
		die "mt7621 kernel config does not provide the null userspace console"
	if grep -Eq '^CONFIG_SERIAL_8250_CONSOLE=' "${kernel_config}"; then
		die "mt7621 kernel config has a conflicting 8250 console value"
	fi
}

restore_build_signing_keys() {
	install -m 0600 -- "${SRC_FW_SIGNING_KEY}" "${OPENWRT_DIR}/key-build"
	install -m 0644 -- "${SRC_FW_SIGNING_PUB}" "${OPENWRT_DIR}/key-build.pub"
	install -m 0644 -- "${SRC_FW_SIGNING_CERT}" "${OPENWRT_DIR}/key-build.ucert"
	install -m 0600 -- "${SRC_APK_SIGNING_KEY}" "${OPENWRT_DIR}/private-key.pem"
	install -m 0644 -- "${SRC_APK_SIGNING_PUB}" "${OPENWRT_DIR}/public-key.pem"
	cmp -s "${SRC_FW_SIGNING_KEY}" "${OPENWRT_DIR}/key-build" || \
		die "Restored private build key differs from the pinned signing input"
	cmp -s "${SRC_FW_SIGNING_PUB}" "${OPENWRT_DIR}/key-build.pub" || \
		die "Restored public build key differs from the pinned signing input"
	cmp -s "${SRC_FW_SIGNING_CERT}" "${OPENWRT_DIR}/key-build.ucert" || \
		die "Restored firmware signing certificate differs from the pinned input"
	cmp -s "${SRC_APK_SIGNING_KEY}" "${OPENWRT_DIR}/private-key.pem" || \
		die "Restored APK private key differs from the pinned signing input"
	cmp -s "${SRC_APK_SIGNING_PUB}" "${OPENWRT_DIR}/public-key.pem" || \
		die "Restored APK public key differs from the pinned signing input"
	[ "$(stat -c '%a' "${OPENWRT_DIR}/key-build")" = 600 ] || \
		die "OpenWrt key-build mode is not 600"
	[ "$(stat -c '%a' "${OPENWRT_DIR}/key-build.pub")" = 644 ] || \
		die "OpenWrt key-build.pub mode is not 644"
	[ "$(stat -c '%a' "${OPENWRT_DIR}/key-build.ucert")" = 644 ] || \
		die "OpenWrt key-build.ucert mode is not 644"
	[ "$(stat -c '%a' "${OPENWRT_DIR}/private-key.pem")" = 600 ] || \
		die "OpenWrt APK private key mode is not 600"
	[ "$(stat -c '%a' "${OPENWRT_DIR}/public-key.pem")" = 644 ] || \
		die "OpenWrt APK public key mode is not 644"
}

for signing_input in "${SRC_FW_SIGNING_KEY}" "${SRC_FW_SIGNING_PUB}" \
	"${SRC_FW_SIGNING_CERT}" \
	"${SRC_APK_SIGNING_KEY}" "${SRC_APK_SIGNING_PUB}"; do
	[ -f "${signing_input}" ] && [ ! -L "${signing_input}" ] && \
		[ -s "${signing_input}" ] || die "Required signing input missing: ${signing_input}"
done
[ "$(stat -c '%a' "${SRC_FW_SIGNING_KEY}")" = 600 ] || \
	die "External firmware signing private key must have mode 600"
[ "$(stat -c '%a' "${SRC_APK_SIGNING_KEY}")" = 600 ] || \
	die "External APK signing private key must have mode 600"

for required_file in "${SRC_PATCH}" "${SRC_SERIAL_PATCH}" "${SRC_SEED}" "${INSPECTOR}" "${VLAN_TEST}" "${SAFE_APPLY_TEST}" "${SAFE_APPLY_RUNTIME_TEST}" "${QUICKSETTINGS_CONTRACT_TEST}" "${AUTH_LIFECYCLE_TEST}" "${UI_CONTRACT_TEST}" \
	"${SRC_FILES}/www/cgi-bin/dashluci" \
	"${SRC_FILES}/www/cgi-bin/dashlogout" \
	"${SRC_FILES}/www/cgi-bin/dashlogin" \
	"${SRC_FILES}/www/cgi-bin/dashctl" \
	"${SRC_FILES}/www/dashboard.js" \
	"${SRC_FILES}/usr/sbin/smartap-bootstrap" \
	"${SRC_FILES}/usr/sbin/cr6608-eeprom-power" \
	"${SRC_FILES}/usr/sbin/cr6608-security-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-session-reaper" \
	"${SRC_FILES}/usr/libexec/cr6608-vlan-lib" \
	"${SRC_FILES}/etc/uci-defaults/97-smartap-bootstrap" \
	"${SRC_FILES}/usr/sbin/smartap-time-anchor" \
	"${SRC_FILES}/etc/init.d/smartap-time-anchor" \
	"${SRC_FILES}/etc/uci-defaults/00-smartap-time-anchor" \
	"${SRC_FILES}/usr/libexec/cr6608-session-auth" \
	"${SRC_FILES}/usr/libexec/cr6608-luci-acl-names.uc" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-wifi-reload" \
	"${SRC_FILES}/usr/sbin/cr6608-quicksettings-apply" \
	"${SRC_FILES}/etc/init.d/cr6608-safe-apply" \
	"${SRC_FILES}/etc/init.d/cr6608-quicksettings" \
	"${SRC_FILES}/etc/init.d/smartap-qos" \
	"${SRC_FILES}/etc/init.d/cr6608-rescue-guard" \
	"${SRC_FILES}/etc/init.d/cr6608-security" \
	"${SRC_FILES}/etc/init.d/cr6608-neighbor" \
	"${SRC_FILES}/etc/uci-defaults/97-cr6608-security" \
	"${SRC_FILES}/etc/uci-defaults/98-cr6608-safe-apply" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-neighbor-enable" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-runtime-services" \
	"${SRC_FILES}/etc/config/cr6608quick" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-apply" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-confirm" \
	"${SRC_FILES}/www/luci-static/resources/view/cr6608/quicksettings.js" \
	"${SRC_FILES}/usr/share/luci/menu.d/luci-app-cr6608-quicksettings.json" \
	"${SRC_FILES}/usr/share/luci/menu.d/zz-cr6608-logout.json" \
	"${SRC_FILES}/usr/share/ucode/luci/controller/cr6608/logout.uc" \
	"${SRC_FILES}/usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json" \
	"${SRC_FILES}/etc/modules.d/mt7915e"; do
	[ -s "${required_file}" ] || die "Required source file missing: ${required_file}"
done

for shell_source in \
	"${SRC_FILES}/www/cgi-bin/dashlogin" \
	"${SRC_FILES}/www/cgi-bin/dashluci" \
	"${SRC_FILES}/www/cgi-bin/dashlogout" \
	"${SRC_FILES}/www/cgi-bin/dashctl" \
	"${SRC_FILES}/usr/libexec/cr6608-session-auth" \
	"${SRC_FILES}/usr/libexec/cr6608-vlan-lib" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-wifi-reload" \
	"${SRC_FILES}/usr/sbin/cr6608-quicksettings-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-security-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-session-reaper" \
	"${SRC_FILES}/usr/sbin/cr6608-eeprom-power" \
	"${SRC_FILES}/usr/sbin/smartap-bootstrap" \
	"${SRC_FILES}/etc/init.d/cr6608-safe-apply" \
	"${SRC_FILES}/etc/init.d/cr6608-quicksettings" \
	"${SRC_FILES}/etc/init.d/smartap-qos" \
	"${SRC_FILES}/etc/init.d/cr6608-rescue-guard" \
	"${SRC_FILES}/etc/init.d/cr6608-security" \
	"${SRC_FILES}/etc/init.d/cr6608-neighbor" \
	"${SRC_FILES}/etc/uci-defaults/97-cr6608-security" \
	"${SRC_FILES}/etc/uci-defaults/98-cr6608-safe-apply" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-neighbor-enable" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-runtime-services" \
	"${SRC_FILES}/etc/uci-defaults/97-smartap-bootstrap" \
	"${SRC_FILES}/etc/config/cr6608quick" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-apply" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-confirm" \
	"${SRC_FILES}/usr/sbin/smartap-time-anchor" \
	"${SRC_FILES}/etc/init.d/smartap-time-anchor" \
	"${SRC_FILES}/etc/uci-defaults/00-smartap-time-anchor"; do
	sh -n "${shell_source}" || die "Shell syntax failed: ${shell_source}"
done
node --check "${SRC_FILES}/www/dashboard.js" >/dev/null || \
	die "Dashboard JavaScript syntax failed"
node --check "${SRC_FILES}/www/luci-static/resources/view/cr6608/quicksettings.js" \
	>/dev/null || die "Quick-settings JavaScript syntax failed"
for json_source in \
	"${SRC_FILES}/usr/share/luci/menu.d/luci-app-cr6608-quicksettings.json" \
	"${SRC_FILES}/usr/share/luci/menu.d/zz-cr6608-logout.json" \
	"${SRC_FILES}/usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json"; do
	python3 -m json.tool "${json_source}" >/dev/null || \
		die "JSON syntax failed: ${json_source}"
done
bash -n "${INSPECTOR}" || die "Image inspector syntax failed"
sh -n "${VLAN_TEST}" || die "VLAN test syntax failed"
sh "${VLAN_TEST}" | grep -qx 'vlan_lib_tests=pass' || \
	die "VLAN ownership tests failed"
sh -n "${SAFE_APPLY_TEST}" || die "Safe Apply regression test syntax failed"
sh "${SAFE_APPLY_TEST}" | grep -qx 'safe_apply_tests=pass' || \
	die "Safe Apply confirmation regression test failed"
sh -n "${SAFE_APPLY_RUNTIME_TEST}" || die "Safe Apply runtime test syntax failed"
sh "${SAFE_APPLY_RUNTIME_TEST}" | grep -qx 'safe_apply_runtime_tests=pass' || \
	die "Safe Apply token and management-IP runtime tests failed"
sh -n "${QUICKSETTINGS_CONTRACT_TEST}" || die "Quick-settings contract test syntax failed"
sh "${QUICKSETTINGS_CONTRACT_TEST}" | grep -qx 'quicksettings_contracts=pass' || \
	die "Quick-settings ownership and cleanup contracts failed"
sh -n "${AUTH_LIFECYCLE_TEST}" || die "Authentication lifecycle test syntax failed"
auth_test_output="$(sh "${AUTH_LIFECYCLE_TEST}")" || \
	die "Authentication lifecycle tests failed"
printf '%s\n' "${auth_test_output}"
printf '%s\n' "${auth_test_output}" | grep -qx 'auth_lifecycle_test=pass' || \
	die "Authentication lifecycle positive gate did not pass"
printf '%s\n' "${auth_test_output}" | grep -qx 'auth_lifecycle_negative_tests=pass' || \
	die "Authentication lifecycle negative gates did not pass"
sh -n "${UI_CONTRACT_TEST}" || die "Dashboard UI contract test syntax failed"
sh "${UI_CONTRACT_TEST}" | grep -qx 'dashboard_ui_contracts=pass' || \
	die "Dashboard UI performance and layout contracts failed"

recreate_required_links "${SRC_FILES}"
assert_required_links "${SRC_FILES}"
printf 'mt7915e cr6608_rf_38dbm=1\n' | \
	cmp -s - "${SRC_FILES}/etc/modules.d/mt7915e" || \
	die "Invalid etc/modules.d/mt7915e in final overlay"
[ ! -e "${SRC_FILES}/etc/modprobe.d" ] && [ ! -L "${SRC_FILES}/etc/modprobe.d" ] || \
	die "Stale files/etc/modprobe.d path must not be present"
if grep -RIsaEq 'cr6608_rf_35dbm|CR6608-RF-35DBM' "${SRC_FILES}" "${SRC_PATCH}"; then
	die "Stale 35 dBm input is present"
fi

say "[1/10] Resetting one clean OpenWrt source tree to ${OPENWRT_TAG}"
if [ -e "${OPENWRT_DIR}" ] && [ ! -d "${OPENWRT_DIR}/.git" ]; then
	die "OpenWrt path exists but is not a Git checkout: ${OPENWRT_DIR}"
fi
if [ ! -d "${OPENWRT_DIR}/.git" ]; then
	git clone --branch "${OPENWRT_TAG}" --depth 1 "${OPENWRT_URL}" "${OPENWRT_DIR}"
fi
assert_origin
cd "${OPENWRT_DIR}"
mapfile -t remote_tag_lines < <(git ls-remote origin "refs/tags/${OPENWRT_TAG}^{}")
[ "${#remote_tag_lines[@]}" -eq 1 ] || die "Official peeled ${OPENWRT_TAG} ref is absent"
remote_tag_commit="$(printf '%s\n' "${remote_tag_lines[0]}" | awk '{print $1}')"
[ "${remote_tag_commit}" = "${OPENWRT_COMMIT}" ] || \
	die "Official ${OPENWRT_TAG} is ${remote_tag_commit}, expected ${OPENWRT_COMMIT}"
git fetch --force --depth 1 origin \
	"+refs/tags/${OPENWRT_TAG}:refs/tags/${OPENWRT_TAG}"
git checkout --detach --force "${OPENWRT_COMMIT}"
git reset --hard "${OPENWRT_COMMIT}"
# Keep the immutable download cache. Everything that can affect the image is
# reset and rebuilt from the pinned source, patch, seed and overlay inputs.
git clean -ffdx -e dl/
restore_build_signing_keys
assert_official_checkout
[ -z "$(git status --porcelain --untracked-files=all)" ] || \
	die "OpenWrt checkout is not clean after reset"
git apply --check "${SRC_SERIAL_PATCH}"
git apply "${SRC_SERIAL_PATCH}"
git apply --check "${SRC_KERNEL_CONSOLE_PATCH}"
git apply "${SRC_KERNEL_CONSOLE_PATCH}"
verify_serial_console_patch
ok "official origin, commit, and pinned signing keys verified"

say "[2/10] Updating and installing release feeds"
./scripts/feeds update -a
./scripts/feeds install -a
normalize_source_permissions
ok "feeds ready and source permissions normalized"

say "[3/10] Recording inputs and installing only the final mt76 patch"
write_input_manifest "${INPUT_MANIFEST}"
MT76_PATCH_DIR="${OPENWRT_DIR}/package/kernel/mt76/patches"
mkdir -p "${MT76_PATCH_DIR}"
rm -f "${MT76_PATCH_DIR}"/999-mt7915-cr6608-rf-*.patch
cp -v -- "${SRC_PATCH}" "${MT76_PATCH_DIR}/$(basename "${SRC_PATCH}")"
cmp -s "${SRC_PATCH}" "${MT76_PATCH_DIR}/$(basename "${SRC_PATCH}")" || \
	die "Staged mt76 patch differs from the recorded input"
mapfile -t cr6608_rf_patches < <(
	find "${MT76_PATCH_DIR}" -maxdepth 1 -type f -name '*mt7915-cr6608-rf-*.patch' -print
)
[ "${#cr6608_rf_patches[@]}" -eq 1 ] || die "Expected exactly one CR6608 RF patch"
if grep -RIsaEq 'cr6608_rf_35dbm|CR6608-RF-35DBM' "${MT76_PATCH_DIR}"; then
	die "Stale 35 dBm mt76 patch content is present"
fi
ok "input manifest recorded and final mt76 patch staged"

say "[4/10] Installing the final Smart AP overlay with deterministic modes"
rm -rf "${OPENWRT_DIR}/files"
mkdir -p "${OPENWRT_DIR}/files"
cp -a "${SRC_FILES}/." "${OPENWRT_DIR}/files/"
find "${OPENWRT_DIR}/files" -type d -exec chmod 0755 {} +
find "${OPENWRT_DIR}/files" -type f -exec chmod 0644 {} +
for executable_dir in \
	etc/init.d etc/hotplug.d etc/uci-defaults usr/sbin usr/libexec www/cgi-bin; do
	[ ! -d "${OPENWRT_DIR}/files/${executable_dir}" ] || \
		find "${OPENWRT_DIR}/files/${executable_dir}" -type f -exec chmod 0755 {} +
done
for executable_file in \
	etc/rc.local sbin/sysupgrade lib/netifd/wireless/mac80211.sh; do
	[ ! -f "${OPENWRT_DIR}/files/${executable_file}" ] || \
		chmod 0755 "${OPENWRT_DIR}/files/${executable_file}"
done
[ ! -d "${OPENWRT_DIR}/files/etc/config" ] || \
	find "${OPENWRT_DIR}/files/etc/config" -type f -exec chmod 0600 {} +
[ ! -f "${OPENWRT_DIR}/files/etc/shadow" ] || \
	chmod 0600 "${OPENWRT_DIR}/files/etc/shadow"
[ ! -f "${OPENWRT_DIR}/files/etc/crontabs/root" ] || \
	chmod 0600 "${OPENWRT_DIR}/files/etc/crontabs/root"
rm -f "${OPENWRT_DIR}/files/lib/firmware/README.regulatory.txt"
printf '%s\n' "${BUILD_TIME}" > "${OPENWRT_DIR}/files/etc/smartap-build-time"
printf '%s\n' "${BUILD_EPOCH}" > "${OPENWRT_DIR}/files/etc/smartap-time-anchor"
assert_required_links "${OPENWRT_DIR}/files"
printf 'mt7915e cr6608_rf_38dbm=1\n' | \
	cmp -s - "${OPENWRT_DIR}/files/etc/modules.d/mt7915e" || \
	die "Staged overlay has an invalid mt7915e module line"
[ ! -e "${OPENWRT_DIR}/files/etc/modprobe.d" ] && \
	[ ! -L "${OPENWRT_DIR}/files/etc/modprobe.d" ] || \
	die "Staged overlay contains a stale modprobe.d path"
ok "overlay copied, package public key installed, modes normalized, and symlinks asserted"

say "[5/10] Expanding the exact CR6608 package seed"
cp -- "${SRC_SEED}" "${OPENWRT_DIR}/.config"
chmod 0644 "${OPENWRT_DIR}/.config"
make defconfig
grep -q "^CONFIG_TARGET_ramips_mt7621_DEVICE_${DEVICE_PROFILE}=y" \
	"${OPENWRT_DIR}/.config" || die "CR6608 profile was not selected after defconfig"
grep -q '^CONFIG_SIGNED_PACKAGES=y' "${OPENWRT_DIR}/.config" || \
	die "OpenWrt package signing is not enabled"
grep -q '^CONFIG_USE_APK=y' "${OPENWRT_DIR}/.config" || \
	die "OpenWrt 25.12.5 is not using its default APK package manager"
grep -q '^CONFIG_PACKAGE_wpad-openssl=y' "${OPENWRT_DIR}/.config" || \
	die "wpad-openssl was not selected"
grep -q '^CONFIG_PACKAGE_coreutils-stat=y' "${OPENWRT_DIR}/.config" || \
	die "coreutils-stat was not selected for runtime ownership checks"
./scripts/diffconfig.sh > "${DIFFCONFIG_LOG}"
ok "device profile and package seed selected"

say "[6/10] Downloading all sources"
command -v aria2c >/dev/null 2>&1 || \
	die "aria2c is required for resilient verified source downloads"
make CONFIG_DOWNLOAD_TOOL_CUSTOM=aria2c download -j"$(nproc)" 2>&1 | tee "${DOWNLOAD_LOG}"
ok "all source tarballs downloaded"

say "[7/10] Proving that the final mt76 patch applies"
make package/kernel/mt76/clean V=s
make package/kernel/mt76/prepare V=s 2>&1 | tee "${MT76_LOG}"
grep -Rqs 'CR6608-RF-38DBM-LINEAR enabled' "${OPENWRT_DIR}/build_dir" || \
	die "mt76 prepared source does not contain the final RF marker"
if grep -RIsaEq 'cr6608_rf_35dbm|CR6608-RF-35DBM' "${OPENWRT_DIR}/build_dir"; then
	die "mt76 prepared source contains a stale 35 dBm marker"
fi
ok "mt76 patch applied to the pinned v25.12.5 source"

say "[8/10] Full verbose build: make -j\$(nproc) V=s"
make -j$(nproc) V=s 2>&1 | tee "${BUILD_LOG}"
ok "full source build finished without fallback"

say "[9/10] Running pre-publication image gates"
assert_official_checkout
verify_serial_console_patch
input_recheck="$(mktemp "${LOG_DIR}/.build-inputs-recheck.XXXXXX")"
write_input_manifest "${input_recheck}"
if ! cmp -s "${INPUT_MANIFEST}" "${input_recheck}"; then
	diff -u "${INPUT_MANIFEST}" "${input_recheck}" >&2 || true
	rm -f -- "${input_recheck}"
	die "Seed, patch, overlay, or build scripts changed during the build"
fi
rm -f -- "${input_recheck}"

BIN_DIR="${OPENWRT_DIR}/bin/targets/ramips/mt7621"
mapfile -t images < <(find "${BIN_DIR}" -maxdepth 1 -type f \
	-name "*${DEVICE_PROFILE}*squashfs-sysupgrade.bin" -print)
[ "${#images[@]}" -eq 1 ] || {
	printf 'Expected exactly one CR6608 sysupgrade image, found %s\n' \
		"${#images[@]}" >&2
	printf '%s\n' "${images[@]}" >&2
	exit 1
}
mapfile -t firmware_images < <(find "${BIN_DIR}" -maxdepth 1 -type f \
	-name "*${DEVICE_PROFILE}*squashfs-firmware.bin" -print)
[ "${#firmware_images[@]}" -eq 1 ] || {
	printf 'Expected exactly one CR6608 firmware image, found %s\n' \
		"${#firmware_images[@]}" >&2
	printf '%s\n' "${firmware_images[@]}" >&2
	exit 1
}
FWTOOL="${OPENWRT_DIR}/staging_dir/host/bin/fwtool"
[ -x "${FWTOOL}" ] || die "Built host fwtool is unavailable for signature inspection"
signature_probe="$(mktemp "${LOG_DIR}/.image-signature.XXXXXX")"
if ! "${FWTOOL}" -s "${signature_probe}" "${images[0]}" >/dev/null 2>&1; then
	rm -f -- "${signature_probe}"
	die "Built sysupgrade image has no fwtool signature chunk"
fi
[ -s "${signature_probe}" ] || {
	rm -f -- "${signature_probe}"
	die "Built sysupgrade image has an empty fwtool signature chunk"
}
rm -f -- "${signature_probe}"
ok "fwtool signature is present and will be verified by the image inspector"
bash "${INSPECTOR}" "${images[0]}" "${firmware_images[0]}" \
	"${OPENWRT_DIR}" "${OPENWRT_DIR}/files" 2>&1 | tee "${INSPECTION_LOG}"
grep -qx 'gate_status=pass' "${INSPECTION_LOG}" || \
	die "Pre-publication inspection did not report success"
ok "signed metadata-bearing sysupgrade, package key, overlay, size, and RF gates passed"

inspection_value() {
	local key="$1"
	awk -v key="${key}" '
		index($0, key "=") == 1 { print substr($0, length(key) + 2); found = 1; exit }
		END { if (!found) exit 1 }
	' "${INSPECTION_LOG}"
}

say "[10/10] Publishing the validated release directory atomically"
PUBLISH_DIR="$(mktemp -d "${RELEASES_DIR}/.publish.XXXXXX")"
cp -- "${images[0]}" "${PUBLISH_DIR}/${FINAL_IMAGE}"
cp -- "${INPUT_MANIFEST}" "${PUBLISH_DIR}/build-inputs.txt"
cp -- "${INSPECTION_LOG}" "${PUBLISH_DIR}/prepublish-inspection.txt"
chmod 0644 "${PUBLISH_DIR}/${FINAL_IMAGE}" \
	"${PUBLISH_DIR}/build-inputs.txt" "${PUBLISH_DIR}/prepublish-inspection.txt"
(
	cd "${PUBLISH_DIR}"
	sha256sum "${FINAL_IMAGE}" > "${FINAL_IMAGE}.sha256"
	sha256sum -c "${FINAL_IMAGE}.sha256"
)
image_sha256="$(awk '{print $1}' "${PUBLISH_DIR}/${FINAL_IMAGE}.sha256")"
{
	printf 'release_status=candidate_pending_router_boot_test\n'
	printf 'openwrt_tag=%s\n' "${OPENWRT_TAG}"
	printf 'openwrt_commit=%s\n' "${OPENWRT_COMMIT}"
	printf 'openwrt_origin=%s\n' "${OPENWRT_URL}"
	printf 'smartap_build_epoch=%s\n' "${BUILD_EPOCH}"
	printf 'smartap_build_time=%s\n' "${BUILD_TIME}"
	printf 'seed_sha256=%s\n' "$(sha256sum "${SRC_SEED}" | awk '{print $1}')"
	printf 'mt76_patch_sha256=%s\n' "$(sha256sum "${SRC_PATCH}" | awk '{print $1}')"
	printf 'serial_console_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_SERIAL_PATCH}" | awk '{print $1}')"
	printf 'kernel_console_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_KERNEL_CONSOLE_PATCH}" | awk '{print $1}')"
	printf 'serial_console=disabled\n'
	printf 'firmware_pubkey_sha256=%s\n' \
		"$(sha256sum "${SRC_FW_SIGNING_PUB}" | awk '{print $1}')"
	printf 'firmware_ucert_sha256=%s\n' \
		"$(sha256sum "${SRC_FW_SIGNING_CERT}" | awk '{print $1}')"
	printf 'apk_pubkey_sha256=%s\n' \
		"$(sha256sum "${SRC_APK_SIGNING_PUB}" | awk '{print $1}')"
	printf 'fwtool_signature=present_verified\n'
	printf 'input_manifest=build-inputs.txt\n'
	printf 'input_manifest_sha256=%s\n' \
		"$(sha256sum "${INPUT_MANIFEST}" | awk '{print $1}')"
	printf 'target_definition_sha256=%s\n' \
		"$(inspection_value target_definition_sha256)"
	printf 'kernel_limit_bytes=%s\n' "$(inspection_value kernel_limit_bytes)"
	printf 'kernel_bytes=%s\n' "$(inspection_value kernel_bytes)"
	printf 'rootfs_bytes=%s\n' "$(inspection_value rootfs_bytes)"
	printf 'image_limit_bytes=%s\n' "$(inspection_value image_limit_bytes)"
	printf 'firmware_bytes=%s\n' "$(inspection_value firmware_bytes)"
	printf 'image=%s\n' "${FINAL_IMAGE}"
	printf 'image_bytes=%s\n' "$(inspection_value sysupgrade_bytes)"
	printf 'image_sha256=%s\n' "${image_sha256}"
	printf 'checksum=%s.sha256\n' "${FINAL_IMAGE}"
	printf 'inspection=prepublish-inspection.txt\n'
	printf 'build_log=%s\n' "${BUILD_LOG}"
} > "${PUBLISH_DIR}/build-manifest.txt"
chmod 0644 "${PUBLISH_DIR}/${FINAL_IMAGE}.sha256" \
	"${PUBLISH_DIR}/build-manifest.txt"

release_name="v29-${RUN_ID}-${image_sha256:0:16}"
release_dir="${RELEASES_DIR}/${release_name}"
[ ! -e "${release_dir}" ] || die "Release directory already exists: ${release_dir}"
mv -- "${PUBLISH_DIR}" "${release_dir}"
PUBLISH_DIR=""
current_link_tmp="${OUTPUT_DIR}/.current-v29.${RUN_ID}"
ln -s -- "releases/${release_name}" "${current_link_tmp}"
mv -Tf -- "${current_link_tmp}" "${OUTPUT_DIR}/current-v29"
(
	cd "${release_dir}"
	sha256sum -c "${FINAL_IMAGE}.sha256"
)
ls -lh "${release_dir}/${FINAL_IMAGE}"
ok "candidate image published at ${release_dir}/${FINAL_IMAGE}"
