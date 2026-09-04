#!/usr/bin/env bash
# Clean source build of OpenWrt 25.12.5 for Xiaomi Mi Router CR6608.

set -euo pipefail
umask 022

# Git can gain new repository/ref/config/protocol environment switches. Scrub
# the complete namespace instead of maintaining a brittle denylist.
while IFS= read -r git_env_name; do
	unset "${git_env_name}"
done < <(compgen -A variable GIT_ || true)
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_ATTR_NOSYSTEM=1
export GIT_NO_REPLACE_OBJECTS=1
export GIT_TERMINAL_PROMPT=0
export LC_ALL=C

OPENWRT_URL="https://git.openwrt.org/openwrt/openwrt.git"
OPENWRT_TAG="v25.12.5"
OPENWRT_COMMIT="f0a60eee2fe051741c643ea6118718aae1ef17fb"
OPENWRT_TAG_OBJECT="e20bc3ec9eb9e3dbd0519ddc18f81f3eedc0f45e"
OPENWRT_RELEASE_KEY_SHA256="f9c4a14810bbec006795243807910dbbcb18b6046ae9505f9f289c0e22be3b1e"
OPENWRT_RELEASE_SIGNER="CB3D3FB8071DF89C179B0B43F1B767859CB2EBC7"
KIT_BASE_COMMIT="18c4f07f930a255becda4c8af0b73b0b4f8ef4b2"
AUTH_FIX_COMMIT="2fdeb2311364b8dfe5a31057cf0b8583cdf0c33c"
PRESERVED_CONFIG_MIGRATION_VERSION="8"
PRODUCT_VERSION="v86"
DEVICE_PROFILE="xiaomi_mi-router-cr6608"
OFFLINE_PINNED_SOURCES="${CR6608_OFFLINE_PINNED_SOURCES:-0}"
case "${OFFLINE_PINNED_SOURCES}" in
	0|1) ;;
	*)
		printf 'ERROR: CR6608_OFFLINE_PINNED_SOURCES must be 0 or 1\n' >&2
		exit 1
		;;
esac
FEED_UPDATE_TIMEOUT_SECONDS="${CR6608_FEED_UPDATE_TIMEOUT_SECONDS:-900}"
case "${FEED_UPDATE_TIMEOUT_SECONDS}" in
	''|*[!0-9]*|0[0-9]*)
		printf 'ERROR: CR6608_FEED_UPDATE_TIMEOUT_SECONDS must be an integer from 120 to 1800\n' >&2
		exit 1
		;;
esac
if [ "${#FEED_UPDATE_TIMEOUT_SECONDS}" -gt 4 ]; then
	printf 'ERROR: CR6608_FEED_UPDATE_TIMEOUT_SECONDS must be an integer from 120 to 1800\n' >&2
	exit 1
fi
if [ "${FEED_UPDATE_TIMEOUT_SECONDS}" -lt 120 ] || [ "${FEED_UPDATE_TIMEOUT_SECONDS}" -gt 1800 ]; then
	printf 'ERROR: CR6608_FEED_UPDATE_TIMEOUT_SECONDS must be an integer from 120 to 1800\n' >&2
	exit 1
fi
BUILD_PROFILE="${CR6608_BUILD_PROFILE:-${profile:-lab}}"
if [ -n "${CR6608_BUILD_PROFILE:-}" ] && [ -n "${profile:-}" ] && \
	[ "${CR6608_BUILD_PROFILE}" != "${profile}" ]; then
	printf 'ERROR: CR6608_BUILD_PROFILE and profile disagree\n' >&2
	exit 1
fi
case "${BUILD_PROFILE}" in
	lab)
		FINAL_IMAGE="cr6608-SMARTAP-v86-LAB-NONSALE-CANDIDATE-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM-sysupgrade.bin"
		COMBINED_IMAGE="cr6608-SMARTAP-v86-LAB-NONSALE-CANDIDATE-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM-firmware.bin"
		INITRAMFS_IMAGE="cr6608-SMARTAP-v86-LAB-NONSALE-CANDIDATE-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM-initramfs-kernel.bin"
		ARTIFACT_PROFILE_LABEL='lab_operator'
		RELEASE_STATUS='candidate_only_not_final'
		RETAIL_RADIO_GATE_STATUS='blocked_lab_artifact_requires_retail_rebuild'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=0'
		PROFILE_FLASHABLE_IMAGES=1
		;;
	retail)
		FINAL_IMAGE="cr6608-SMARTAP-v86-RETAIL-v1-UNPROVISIONED-NONSALE-RADIO-LOCKED-sysupgrade.bin"
		COMBINED_IMAGE="cr6608-SMARTAP-v86-RETAIL-v1-UNPROVISIONED-NONSALE-RADIO-LOCKED-firmware.bin"
		INITRAMFS_IMAGE="cr6608-SMARTAP-v86-RETAIL-v1-UNPROVISIONED-NONSALE-RADIO-LOCKED-initramfs-kernel.bin"
		ARTIFACT_PROFILE_LABEL='retail_v1'
		RELEASE_STATUS='retail_unprovisioned_not_sale_ready'
		RETAIL_RADIO_GATE_STATUS='blocked_pending_per_device_provisioning_radio_audit_and_external_rf_verification'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0'
		PROFILE_FLASHABLE_IMAGES=1
		;;
	ul-forced-lab)
		FINAL_IMAGE="cr6608-SMARTAP-v86-UL-MURU-FORCED-LAB-NONSALE-38DBM-sysupgrade.bin"
		COMBINED_IMAGE="cr6608-SMARTAP-v86-UL-MURU-FORCED-LAB-NONSALE-38DBM-firmware.bin"
		INITRAMFS_IMAGE="cr6608-SMARTAP-v86-UL-MURU-FORCED-LAB-NONSALE-38DBM-initramfs-kernel.bin"
		ARTIFACT_PROFILE_LABEL='ul_muru_forced_lab_v1'
		RELEASE_STATUS='ul_muru_forced_persistent_lab_not_sale_ready'
		RETAIL_RADIO_GATE_STATUS='blocked_forced_ul_muru_requires_ota_soak_and_external_rf_verification'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=15'
		PROFILE_FLASHABLE_IMAGES=1
		;;
	ul-lab)
		FINAL_IMAGE=""
		COMBINED_IMAGE=""
		INITRAMFS_IMAGE="cr6608-SMARTAP-v86-UL-MURU-RAM-QUALIFICATION-initramfs-kernel.bin"
		ARTIFACT_PROFILE_LABEL='ul_muru_ram_v1'
		RELEASE_STATUS='ul_muru_ram_qualification_not_sale_ready'
		RETAIL_RADIO_GATE_STATUS='blocked_ram_qualification_requires_ota_soak_and_external_rf_verification'
		EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=15'
		PROFILE_FLASHABLE_IMAGES=0
		;;
	*)
		printf 'ERROR: build profile must be lab, retail, ul-forced-lab, or ul-lab\n' >&2
		exit 1
		;;
esac
RETAIL_COMMISSIONING_MODE="${CR6608_RETAIL_COMMISSIONING_MODE:-0}"
RETAIL_COMMISSIONING_KEY="${CR6608_RETAIL_COMMISSIONING_KEY:-}"
case "${RETAIL_COMMISSIONING_MODE}" in
	0) [ -z "${RETAIL_COMMISSIONING_KEY}" ] || {
		printf 'ERROR: commissioning key supplied while commissioning mode is disabled\n' >&2
		exit 1
	} ;;
	1)
		[ "${BUILD_PROFILE}" = retail ] || {
			printf 'ERROR: Retail commissioning mode requires the retail profile\n' >&2
			exit 1
		}
		[ -n "${RETAIL_COMMISSIONING_KEY}" ] || {
			printf 'ERROR: Retail commissioning mode requires a public key file\n' >&2
			exit 1
		}
		FINAL_IMAGE=""
		COMBINED_IMAGE=""
		INITRAMFS_IMAGE="cr6608-SMARTAP-v86-RETAIL-v1-FACTORY-COMMISSIONING-NONSALE-RAMBOOT-ONLY-initramfs-kernel.bin"
		RELEASE_STATUS='retail_factory_commissioning_ram_boot_only_not_sale_ready'
		RETAIL_RADIO_GATE_STATUS='blocked_commissioning_ram_requires_unique_provisioning_and_external_rf_verification'
		PROFILE_FLASHABLE_IMAGES=0
		;;
	*)
		printf 'ERROR: CR6608_RETAIL_COMMISSIONING_MODE must be 0 or 1\n' >&2
		exit 1
		;;
esac
PUBLISH_FLASHABLE_IMAGES="${PROFILE_FLASHABLE_IMAGES}"
SOURCE_TEST_ONLY="${CR6608_SOURCE_TEST_ONLY:-0}"
BUILD_PRIVATE_KEYS_INSTALLED=0
case "${SOURCE_TEST_ONLY}" in
	0|1) ;;
	*)
		printf 'ERROR: CR6608_SOURCE_TEST_ONLY must be 0 or 1\n' >&2
		exit 1
		;;
esac
VERIFIED_SOURCE_BUNDLE="${CR6608_VERIFIED_SOURCE_BUNDLE:-}"
EXPECTED_SOURCE_BUNDLE_SHA256="${CR6608_EXPECTED_SOURCE_BUNDLE_SHA256:-}"
EXPECTED_ORIGINAL_COMMIT="${CR6608_EXPECTED_ORIGINAL_COMMIT:-}"
EXPECTED_ORIGINAL_TREE="${CR6608_EXPECTED_ORIGINAL_TREE:-}"
EXPECTED_CONTAINER_COMMIT="${CR6608_EXPECTED_CONTAINER_COMMIT:-}"
EXPECTED_CONTAINER_TREE="${CR6608_EXPECTED_CONTAINER_TREE:-}"
EXPECTED_PAYLOAD_MANIFEST_SHA256="${CR6608_EXPECTED_PAYLOAD_MANIFEST_SHA256:-}"
RESCUE_REAL_EVIDENCE="${CR6608_RESCUE_REAL_EVIDENCE:-}"
FACTORY38_BUILD_MODE="${CR6608_FACTORY38_BUILD_MODE:-normal}"
if [ "${SOURCE_TEST_ONLY}" = 1 ]; then
	FACTORY38_BUILD_MODE=normal
fi
case "${FACTORY38_BUILD_MODE}" in
	normal) ;;
	maintenance)
		[ "${RETAIL_COMMISSIONING_MODE}" = 0 ] || {
			printf 'ERROR: Factory-38 maintenance and Retail commissioning are mutually exclusive\n' >&2
			exit 1
		}
		[ "${BUILD_PROFILE}" = lab ] || {
			printf 'ERROR: Factory-38 maintenance is LAB-only\n' >&2
			exit 1
		}
		FINAL_IMAGE=""
		COMBINED_IMAGE=""
		INITRAMFS_IMAGE="cr6608-SMARTAP-v86-MAINTENANCE-RAMBOOT-ONLY-initramfs-kernel.bin"
		PUBLISH_FLASHABLE_IMAGES=0
		;;
	*)
		printf 'ERROR: CR6608_FACTORY38_BUILD_MODE must be normal or maintenance\n' >&2
		exit 1
		;;
esac
if [ "${PUBLISH_FLASHABLE_IMAGES}" = 1 ]; then
	PRIMARY_IMAGE="${FINAL_IMAGE}"
else
	PRIMARY_IMAGE="${INITRAMFS_IMAGE}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINAL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_FILES="${SCRIPT_DIR}/files"
SRC_PROFILE_APPLIER="${SCRIPT_DIR}/profiles/apply-build-profile.sh"
PINNED_FEED_CACHE_DIR="/home/root123/feeds-pinned-cache-20260809"
FEED_CACHE_TOOL="${SCRIPT_DIR}/tools/cr6608-feed-cache.py"
OPENWRT_TAG_GATE="${SCRIPT_DIR}/tools/cr6608-openwrt-tag-gate.sh"
OPENWRT_RELEASE_KEY="${SCRIPT_DIR}/signing/openwrt-release-hauke.asc"
OFFLINE_SOURCE_FALLBACK_TEST="${SCRIPT_DIR}/tests/test-offline-source-fallback.py"
SRC_RETAIL_COMMISSIONING_STAGE="${SCRIPT_DIR}/tools/stage-retail-commissioning-key.sh"
SRC_RETAIL_PROFILE_FILES="${SCRIPT_DIR}/profiles/retail/files"
SRC_UL_LAB_PROFILE_FILES="${SCRIPT_DIR}/profiles/ul-lab/files"
SRC_UL_FORCED_LAB_PROFILE_FILES="${SCRIPT_DIR}/profiles/ul-forced-lab/files"
if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	case "${RETAIL_COMMISSIONING_KEY}" in
		*$'\n'*|*$'\t'*)
			printf 'ERROR: commissioning key path contains unsupported characters\n' >&2
			exit 1
			;;
	esac
	[ -f "${RETAIL_COMMISSIONING_KEY}" ] && [ ! -L "${RETAIL_COMMISSIONING_KEY}" ] || {
		printf 'ERROR: commissioning key must be a regular non-symlink file\n' >&2
		exit 1
	}
	RETAIL_COMMISSIONING_KEY="$(realpath -e -- "${RETAIL_COMMISSIONING_KEY}")" || {
		printf 'ERROR: commissioning key cannot be canonicalized\n' >&2
		exit 1
	}
	case "${RETAIL_COMMISSIONING_KEY}" in
		"${FINAL_ROOT}/device-inputs/"*) ;;
		*)
			printf 'ERROR: commissioning key must be under the final device-inputs directory\n' >&2
			exit 1
			;;
	esac
fi
SRC_INITRAMFS_UBI_DETACH="${SRC_FILES}/lib/preinit/71_cr6608_initramfs_detach_ubi"
SRC_UL_MURU_DEFERRED="${SRC_FILES}/etc/rc.d/S97cr6608-ul-muru-reconcile"
SRC_PATCH="${SCRIPT_DIR}/patches/999-mt7915-cr6608-rf-38dbm-request-path.patch"
SRC_FACTORY38_PATCH="${SCRIPT_DIR}/patches/zz-mt7915-cr6608-factory38-path.patch"
SRC_FIRMWARE_EEPROM_SHADOW_PATCH="${SCRIPT_DIR}/patches/zzz-mt7915-cr6608-firmware-eeprom-shadow.patch"
SRC_UL_MURU_PATCH="${SCRIPT_DIR}/patches/zzzz-mt7915-cr6608-ul-muru-experimental.patch"
SRC_UL_MURU_STOCK_POLICY_PATCH="${SCRIPT_DIR}/patches/zzzzz-mt7915-cr6608-ul-muru-vendor-baseline.patch"
SRC_MURU_PORT_PATCHES=(
	"${SCRIPT_DIR}/patches/zzzzzz-01-mt7915-cr6608-muru-mask-state.patch"
	"${SCRIPT_DIR}/patches/zzzzzz-02-mt7915-cr6608-muru-mask-init.patch"
	"${SCRIPT_DIR}/patches/zzzzzz-03-mt7915-cr6608-muru-fault-latch-mac.patch"
	"${SCRIPT_DIR}/patches/zzzzzz-04-mt7915-cr6608-muru-telemetry-debugfs.patch"
	"${SCRIPT_DIR}/patches/zzzzzz-05-mt7915-cr6608-muru-mcu-response.patch"
	"${SCRIPT_DIR}/patches/zzzzzz-06-mt7915-cr6608-muru-fault-attribution.patch"
	"${SCRIPT_DIR}/patches/zzzzzz-07-mt7915-cr6608-muru-ul-tb-attribution.patch"
	"${SCRIPT_DIR}/patches/zzzzzz-08-mt7915-cr6608-muru-live-refresh.patch"
)
MURU_FIRMWARE_VERIFY="${SCRIPT_DIR}/tools/verify-mt7915-muru-firmware.sh"
SRC_RF_DTS_PATCH="${SCRIPT_DIR}/patches/996-cr6608-dts-rf-38dbm-lab-mode.patch"
SRC_UL_MURU_DTS_PATCH="${SCRIPT_DIR}/patches/996a-cr6608-dts-ul-muru-ram-gate.patch"
SRC_FACTORY38_WRITE_GATE_PATCH="${SCRIPT_DIR}/patches/997-cr6608-factory38-maintenance-write-gate.patch"
SRC_FACTORY38_BUILDER="${SCRIPT_DIR}/factory38/build_factory38.py"
SRC_FACTORY38_STAGE="${SCRIPT_DIR}/factory38/cr6608-factory38-stage"
SRC_FACTORY38_MARKER="${SCRIPT_DIR}/factory38/cr6608-factory38-writegate.marker"
SRC_FACTORY38_WIFI_DISABLE="${SCRIPT_DIR}/factory38/01-cr6608-factory38-maintenance"
SRC_CRASHLOG_WRITE_GATE_PATCH="${SCRIPT_DIR}/patches/995-cr6608-crashlog-maintenance-write-gate.patch"
SRC_CRASHLOG_BUILDER="${SCRIPT_DIR}/crashlog/build-cr6608-crashlog-initramfs.sh"
SRC_CRASHLOG_SANITIZER="${SCRIPT_DIR}/crashlog/cr6608-crashlog-sanitize"
SRC_CRASHLOG_MARKER="${SCRIPT_DIR}/crashlog/cr6608-crashlog-maintenance.marker"
SRC_CRASHLOG_WIFI_DISABLE="${SCRIPT_DIR}/crashlog/01-cr6608-crashlog-maintenance"
SRC_CRASHLOG_README="${SCRIPT_DIR}/crashlog/README.md"
SRC_MAC80211_PATCH="${SCRIPT_DIR}/patches/995-mac80211-cr6608-txpower-trace.patch"
SRC_LUCI_WIRELESS_PATCH="${SCRIPT_DIR}/patches/993-luci-wireless-preserve-configured-txpower.patch"
SRC_DSA_EEE_PATCH="${SCRIPT_DIR}/patches/140-net-dsa-mt7530-do-not-advertise-EEE-on-MT7621-switch.patch"
SRC_UBI_INITRAMFS_GUARD_PATCH="${SCRIPT_DIR}/patches/141-mtd-ubi-skip-auto-attach-for-embedded-initramfs.patch"
SRC_UHTTPD_PATCH="${SCRIPT_DIR}/patches/992-uhttpd-normalize-dispatch-and-close-unread-body.patch"
UHTTPD_SECURITY_HEADERS="${SRC_FILES}/etc/uhttpd/security-headers.json"
SRC_PRPLMESH_PACKAGE="${SCRIPT_DIR}/packages/prplmesh"
SRC_MNDP_PACKAGE="${SCRIPT_DIR}/packages/cr6608-mndp"
SRC_MNDP_SOURCE="${SCRIPT_DIR}/src/cr6608-mndp-advertise.c"
SRC_SEED="${SCRIPT_DIR}/cr6608.seed.config"
INSPECTOR="${SCRIPT_DIR}/inspect-image.sh"
FWTOOL_RUNTIME_POLICY="${SRC_FILES}/lib/upgrade/fwtool.sh"
FW_OWNER_TRUST_KEY="${SRC_FILES}/etc/opkg/keys/c2b162a7217acaa4"
VLAN_TEST="${SCRIPT_DIR}/tests/test-vlan-lib.sh"
NETWORK_SAFETY_TEST="${SCRIPT_DIR}/tests/test-network-safety.sh"
INITRAMFS_UBI_DETACH_TEST="${SCRIPT_DIR}/tests/test-initramfs-ubi-detach.sh"
SAFE_APPLY_TEST="${SCRIPT_DIR}/tests/test-safe-apply.sh"
SAFE_APPLY_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-safe-apply-runtime.sh"
SAFE_WIFI_RELOAD_TEST="${SCRIPT_DIR}/tests/test-safe-wifi-reload.sh"
QUICKSETTINGS_CONTRACT_TEST="${SCRIPT_DIR}/tests/test-quicksettings-contracts.sh"
SMARTAP_QOS_TEST="${SCRIPT_DIR}/tests/test-smartap-qos-apply.sh"
DASHCTL_MAC_QOS_TRANSACTION_TEST="${SCRIPT_DIR}/tests/test-dashctl-mac-qos-transactions.sh"
IPV6_DUALSTACK_TEST="${SCRIPT_DIR}/tests/test-ipv6-dualstack-contract.sh"
IPV6_UPGRADE_MIGRATION_TEST="${SCRIPT_DIR}/tests/test-ipv6-upgrade-migration.py"
IPV4_ONLY_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ipv4-only-runtime.sh"
MAC_IDENTITY_TEST="${SCRIPT_DIR}/tests/test-mac-identity-contract.sh"
FLEET_MAC_AUDIT_TEST="${SCRIPT_DIR}/tests/test-fleet-mac-audit.py"
GUEST_NETWORK_TEST="${SCRIPT_DIR}/tests/test-guest-network-contract.sh"
DASHBOARD_ZERO_RETENTION_TEST="${SCRIPT_DIR}/tests/test-dashboard-zero-retention-contract.sh"
MANAGEMENT_GUARD_TEST="${SCRIPT_DIR}/tests/test-management-guard.sh"
RESCUE_GUARD_TEST="${SCRIPT_DIR}/tests/test-rescue-guard-contract.sh"
DASHBOARD_CACHE_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-dashboard-cache-runtime.sh"
DASHBOARD_LIVE_NO_CACHE_TEST="${SCRIPT_DIR}/tests/test-dashboard-live-no-cache.sh"
DASHBOARD_REQUEST_COORDINATION_TEST="${SCRIPT_DIR}/tests/test-dashboard-request-coordination.js"
CONTROL_RECOVERY_TEST="${SCRIPT_DIR}/tests/test-control-recovery-contract.sh"
DASHCTL_JSON_BUILDERS_TEST="${SCRIPT_DIR}/tests/test-dashctl-json-builders.sh"
JSON_CHARSET_TEST="${SCRIPT_DIR}/tests/test-json-charset-contract.sh"
PACKAGE_MANAGER_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-package-manager-runtime.sh"
WIZARD_CHANNEL_OPTIONS_TEST="${SCRIPT_DIR}/tests/test-wizard-channel-options.sh"
DASHCTL_RUN_LIMIT_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-dashctl-run-limit-runtime.sh"
SQM_SAFETY_TEST="${SCRIPT_DIR}/tests/test-sqm-safety-contract.sh"
ROAMING_STEERING_TEST="${SCRIPT_DIR}/tests/test-roaming-steering-contract.sh"
UCI_SYNC_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-uci-sync-runtime.sh"
DASHCTL_WIFI_APPLY_TEST="${SCRIPT_DIR}/tests/test-dashctl-wifi-apply.sh"
LUCI_WIRELESS_TXPOWER_TEST="${SCRIPT_DIR}/tests/test-luci-wireless-txpower-preserve.sh"
FACTORY38_BUILDER_TEST="${SCRIPT_DIR}/tests/test_factory38_builder.py"
ALL_CHANNEL_38_TEST="${SCRIPT_DIR}/tests/test-all-channel-38-contract.py"
FACTORY38_STAGE_GUARD_TEST="${SCRIPT_DIR}/tests/test_factory38_stage_guards.sh"
FACTORY38_STAGE_MOCK_TEST="${SCRIPT_DIR}/tests/test_factory38_stage_mock.sh"
CRASHLOG_SANITIZE_MOCK_TEST="${SCRIPT_DIR}/tests/test-cr6608-crashlog-sanitize-mock.sh"
CRASHLOG_BUILD_CONTRACT_TEST="${SCRIPT_DIR}/tests/test-cr6608-crashlog-build-contract.sh"
LEGACY_11B_TEST="${SCRIPT_DIR}/tests/test-legacy-11b-contract.sh"
COUNTRY_DOMAIN_TEST="${SCRIPT_DIR}/tests/test-country-domain-contract.sh"
AUTH_LIFECYCLE_TEST="${SCRIPT_DIR}/tests/test-auth-lifecycle.sh"
AUTH_BOUNDED_BLOCKING_TEST="${SCRIPT_DIR}/tests/test-auth-bounded-blocking.py"
TIME_ANCHOR_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-time-anchor-runtime.sh"
RETAIL_SECURITY_TEST="${SCRIPT_DIR}/tests/test-retail-security-contract.sh"
RETAIL_RADIO_POLICY_TEST="${SCRIPT_DIR}/tests/test-retail-radio-policy.sh"
RETAIL_BUILD_PROFILE_TEST="${SCRIPT_DIR}/tests/test-retail-build-profile.sh"
RETAIL_COMMISSIONING_TEST="${SCRIPT_DIR}/tests/test-retail-commissioning-key.sh"
UL_LAB_BUILD_PROFILE_TEST="${SCRIPT_DIR}/tests/test-ul-lab-build-profile.sh"
SECURE_CONSOLE_TEST="${SCRIPT_DIR}/tests/test-secure-console-migration.sh"
SMART_AP_BRAND_GENERATOR="${SCRIPT_DIR}/tools/generate-smart-ap-brand.py"
SMART_AP_BRANDING_TEST="${SCRIPT_DIR}/tests/test-smart-ap-branding.py"
LOGIN_CACHE_TEST="${SCRIPT_DIR}/tests/test-login-cache-contract.sh"
SMARTAP_ONLY_ROUTING_TEST="${SCRIPT_DIR}/tests/test-smartap-only-routing.sh"
FETCH_BODY_TIMEOUT_TEST="${SCRIPT_DIR}/tests/test-fetch-body-timeout.js"
UI_CONTRACT_TEST="${SCRIPT_DIR}/tests/test-dashboard-ui-contracts.sh"
UI_PASSWORD_TEST="${SCRIPT_DIR}/tests/test-ui-password-separation.sh"
PRESERVED_CONFIG_TEST="${SCRIPT_DIR}/tests/test-preserved-config-migration.py"
DSA_PORT_TEST="${SCRIPT_DIR}/tests/test-dsa-port-contract.sh"
DSA_EEE_TEST="${SCRIPT_DIR}/tests/test-mt7621-eee-early-disable.sh"
DASHAPI_STATUS_TEST="${SCRIPT_DIR}/tests/test-dashapi2-status-contract.sh"
DASHAPI_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-dashapi2-runtime.sh"
AX_FEATURE_TEST="${SCRIPT_DIR}/tests/test-ax-feature-contracts.sh"
UL_MURU_GUARD_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-guard-runtime.sh"
UL_MURU_VERIFIER_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-verifier-runtime.sh"
UL_MURU_DEFAULTS_MIGRATION_TEST="${SCRIPT_DIR}/tests/test-ul-muru-defaults-migration.sh"
UL_MURU_DEFERRED_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-deferred-runtime.sh"
UL_MURU_AIRTEST_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-airtest-runtime.sh"
MURU_DRIVER_PORT_TEST="${SCRIPT_DIR}/tests/test-muru-driver-port.sh"
MURU_FAULT_ATTRIBUTION_TEST="${SCRIPT_DIR}/tests/test-muru-fault-attribution.sh"
UL_MU_EVIDENCE_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-mu-evidence-runtime.sh"
MURU_LIVE_REFRESH_TEST="${SCRIPT_DIR}/tests/test-muru-live-refresh.sh"
EASYMESH_VERIFIER_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-easymesh-verifier-runtime.sh"
PORT_READINESS_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-port-readiness-runtime.sh"
PRPLMESH_ROLE_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-prplmesh-role-runtime.sh"
PRPLMESH_CREDENTIAL_SYNC_TEST="${SCRIPT_DIR}/tests/test-prplmesh-credential-sync.sh"
PRPLMESH_CREDENTIAL_SYNC_HELPER="${SCRIPT_DIR}/packages/prplmesh/files/usr/sbin/cr6608-prplmesh-sync"
SSH_PORT_TEST="${SCRIPT_DIR}/tests/test-ssh-port-contract.sh"
EXECUTABLE_FORMAT_TEST="${SCRIPT_DIR}/tests/test-executable-line-endings.sh"
TXPOWER_COLLECTOR_TEST="${SCRIPT_DIR}/tests/test-txpower-collector-contract.sh"
MNDP_SOURCE_TEST="${SCRIPT_DIR}/tests/test-mndp-source-contract.sh"
MNDP_PACKET_TEST="${SCRIPT_DIR}/tests/test-mndp-packet.py"
PRIVATE_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-private-runtime-contract.sh"
PRIVATE_RUNTIME_STAT_MOCK="${SCRIPT_DIR}/tests/helpers/cr6608-private-stat-msys"
LAN_SCAN_RENDER_TEST="${SCRIPT_DIR}/tests/test-lan-scan-render.js"
RELEASE_PACKAGE_TEST="${SCRIPT_DIR}/tests/test-release-package-contract.sh"
MAINTENANCE_PUBLICATION_TEST="${SCRIPT_DIR}/tests/test-maintenance-publication-guards.sh"
SOURCE_KIT_TOOL="${SCRIPT_DIR}/tools/cr6608_source_kit.py"
FLEET_MAC_AUDIT_TOOL="${SCRIPT_DIR}/tools/cr6608-fleet-mac-audit.py"
SOURCE_KIT_TEST="${SCRIPT_DIR}/tests/test-source-kit-contract.py"
LOGIN_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-login-runtime.js"
MOBILE_LAYOUT_TEST="${SCRIPT_DIR}/tests/test-mobile-layout.js"
UI_SCREENSHOT_DIR="${CR6608_UI_SCREENSHOT_DIR:-${SCRIPT_DIR}/.mobile-layout}"
UI_SCREENSHOT_PARENT=""
ARGON_MOBILE_CSS="${SRC_FILES}/www/luci-static/argon/css/cr6608-mobile.css"
ARGON_LOCALTIME_JS="${SRC_FILES}/www/luci-static/argon/js/cr6608-localtime.js"
ARGON_HEADER="${SRC_FILES}/usr/share/ucode/luci/template/themes/argon/header.ut"
BROWSER_SETUP_TEST="${SCRIPT_DIR}/tests/setup-browser-tests.sh"
PLAYWRIGHT_PACKAGE_JSON="${SCRIPT_DIR}/test-tools/playwright/package.json"
PLAYWRIGHT_PACKAGE_LOCK="${SCRIPT_DIR}/test-tools/playwright/package-lock.json"
PLAYWRIGHT_EXPECTED_VERSION="1.58.2"
PLAYWRIGHT_CORE_DIR=""
CHROMIUM_EXECUTABLE=""
CHROMIUM_SHA256=""
BROWSER_TEST_EVIDENCE="${CR6608_BROWSER_TEST_EVIDENCE:-}"
ROUTER_QUICKSETTINGS_TEST="${SCRIPT_DIR}/tests/router-quicksettings-dryrun.sh"
ROUTER_VLAN_ROUNDTRIP_TEST="${SCRIPT_DIR}/tests/router-vlan-roundtrip.sh"
ROUTER_UHTTPD_SMARTAP_TEST="${SCRIPT_DIR}/tests/test-router-uhttpd-smartap.sh"
SRC_FW_SIGNING_KEY="${CR6608_FW_SIGNING_KEY:-${FINAL_ROOT}/secrets/key-build-v29}"
SRC_FW_SIGNING_PUB="${SCRIPT_DIR}/signing/key-build.pub"
SRC_FW_SIGNING_CERT="${SCRIPT_DIR}/signing/key-build.ucert"
SRC_APK_SIGNING_KEY="${CR6608_APK_SIGNING_KEY:-${FINAL_ROOT}/secrets/private-key-v29.pem}"
SRC_APK_SIGNING_PUB="${SCRIPT_DIR}/signing/public-key.pem"
OPENWRT_DIR="${FINAL_ROOT}/openwrt"
BIN_DIR="${OPENWRT_DIR}/bin/targets/ramips/mt7621"
LOG_DIR="${FINAL_ROOT}/logs"
OUTPUT_DIR="${FINAL_ROOT}/output"
RELEASES_DIR="${OUTPUT_DIR}/releases"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
BUILD_EPOCH="${SMARTAP_BUILD_EPOCH:-$(date -u +%s)}"
BUILD_TIME=""
FACTORY38_SOURCE="${CR6608_FACTORY_BACKUP:-}"
FACTORY38_PRIVATE_OUTPUT="${CR6608_FACTORY38_PRIVATE_OUTPUT:-}"
# Source tests exercise only public, reproducible source inputs. Ignore any
# caller environment left over from a private Factory export invocation.
if [ "${SOURCE_TEST_ONLY}" = 1 ]; then
	FACTORY38_SOURCE=""
	FACTORY38_PRIVATE_OUTPUT=""
	RESCUE_REAL_EVIDENCE=""
	BROWSER_TEST_EVIDENCE=""
fi
FACTORY38_BUNDLE_ENABLED=0
FACTORY38_WORK_DIR=""
FACTORY38_WORK_IDENTITY=""
FACTORY38_BUNDLE_DIR=""
FACTORY38_PRIVATE_PARENT=""
FACTORY38_PRIVATE_PARENT_IDENTITY=""
FACTORY38_PENDING_OUTPUT=""
FACTORY38_PENDING_OUTPUT_IDENTITY=""
FACTORY38_BOUND_INITRAMFS_SHA256=""
FACTORY38_BOUND_INSPECTOR_SHA256=""
FACTORY38_BOUND_INSPECTION_SHA256=""
FACTORY38_BOUND_PACKAGE_MANIFEST_SHA256=""
FACTORY38_BOUND_SHA256SUMS_SHA256=""
INSPECTOR_EXECUTED_SHA256=""
INSPECTION_LOG_VERIFIED_SHA256=""
FACTORY38_ORIGINAL_SHA256="aca3a3b012d96972466e7492e150bb2e00ba24f9f43201912db0223a32c98439"
FACTORY38_ORIGINAL_BLOCK0_SHA256="b72eca62ecbaff9a93176ec5e9912e2ee9d6404c1c9f6005f4e8b66bc9bde224"
FACTORY38_CANDIDATE_SHA256="b6a775087df306c21c70c29520c27fd5ea3e62dcfb8a945b340304895b038eb0"
FACTORY38_CANDIDATE_BLOCK0_SHA256="950b682023077bab5e2e35212e77b7e8d6bcf00f2249f922d38bdad0bed66aab"
BUILD_LOG="${LOG_DIR}/build-candidate-${RUN_ID}.log"
HOST_ZSTD_LOG="${LOG_DIR}/host-zstd-candidate-${RUN_ID}.log"
DOWNLOAD_LOG="${LOG_DIR}/download-candidate-${RUN_ID}.log"
UHTTPD_LOG="${LOG_DIR}/uhttpd-prepare-candidate-${RUN_ID}.log"
MT76_LOG="${LOG_DIR}/mt76-prepare-candidate-${RUN_ID}.log"
REGDB_LOG="${LOG_DIR}/regdb-prepare-candidate-${RUN_ID}.log"
DIFFCONFIG_LOG="${LOG_DIR}/candidate-diffconfig-${RUN_ID}.txt"
INPUT_MANIFEST="${LOG_DIR}/build-inputs-candidate-${RUN_ID}.txt"
SOURCE_MANIFEST="${LOG_DIR}/source-manifest-candidate-${RUN_ID}.txt"
SOURCE_TEST_LOG="${LOG_DIR}/source-tests-candidate-${RUN_ID}.txt"
INSPECTION_LOG="${LOG_DIR}/prepublish-inspection-candidate-${RUN_ID}.txt"
UI_EVIDENCE_MANIFEST="${LOG_DIR}/ui-screenshots-candidate-${RUN_ID}.sha256"
LOCK_FILE="${FINAL_ROOT}/.cr6608-build.lock"
PUBLISH_DIR=""
PUBLISH_DIR_IDENTITY=""
PUBLISH_PENDING_DIR=""
PUBLISH_PENDING_IDENTITY=""
MAINTENANCE_FLASHABLE_DIR=""
MAINTENANCE_SYSUPGRADE_ARTIFACT=""
MAINTENANCE_FIRMWARE_ARTIFACT=""
MAINTENANCE_BIN_CLEANUP_ARMED=0
INSPECTED_SYSUPGRADE_SHA256=""
INSPECTED_FIRMWARE_SHA256=""
INSPECTED_INITRAMFS_SHA256=""
INSPECTED_PACKAGE_MANIFEST_SHA256=""
SOURCE_MANIFEST_SHA256=""
UI_EVIDENCE_MANIFEST_SHA256=""
SOURCE_REPOSITORY_MODE=""
KIT_ORIGINAL_COMMIT=""
KIT_ORIGINAL_TREE=""
KIT_CONTAINER_COMMIT=""
KIT_CONTAINER_TREE=""
KIT_PAYLOAD_MANIFEST_SHA256=""
SOURCE_TRUST_GATE_STATUS="not-required-reviewed-source-test"
TRUSTED_SOURCE_BUNDLE_SHA256=""
TRUSTED_SOURCE_BUNDLE_IDENTITY=""
RESCUE_REAL_EVIDENCE_SHA256=""
RESCUE_REAL_EVIDENCE_IDENTITY=""
RESCUE_REAL_EVIDENCE_GATE_STATUS="not-required-source-test"
CR6608_DTS_RELATIVE="target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts"
CR6608_DTSI_RELATIVE="target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    [ok] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

require_lower_hex() {
	local value="$1" length="$2" label="$3"
	[ "${#value}" -eq "${length}" ] && [[ "${value}" =~ ^[0-9a-f]+$ ]] ||
		die "${label} must be lowercase ${length}-hex"
}

verify_trusted_source_bundle_unchanged() {
	local actual_sha heads refs fsck_output current_identity
	[ -n "${VERIFIED_SOURCE_BUNDLE}" ] ||
		die "Trusted source bundle path is missing"
	case "${VERIFIED_SOURCE_BUNDLE}" in
		*$'\n'*|*$'\t'*) die "Trusted source bundle path contains a newline or tab" ;;
	esac
	[ -f "${VERIFIED_SOURCE_BUNDLE}" ] && [ ! -L "${VERIFIED_SOURCE_BUNDLE}" ] ||
		die "Trusted source bundle must be a regular non-symlink file"
	current_identity="$(stat -c '%d:%i' "${VERIFIED_SOURCE_BUNDLE}")" ||
		die "Trusted source bundle identity cannot be read"
	if [ -n "${TRUSTED_SOURCE_BUNDLE_IDENTITY}" ]; then
		[ "${current_identity}" = "${TRUSTED_SOURCE_BUNDLE_IDENTITY}" ] ||
			die "Trusted source bundle inode changed after verification"
	else
		TRUSTED_SOURCE_BUNDLE_IDENTITY="${current_identity}"
	fi
	actual_sha="$(sha256sum "${VERIFIED_SOURCE_BUNDLE}" | awk '{print $1}')"
	[ "${actual_sha}" = "${EXPECTED_SOURCE_BUNDLE_SHA256}" ] ||
		die "Trusted source bundle SHA-256 changed or differs from the external pin"
	heads="$(git bundle list-heads "${VERIFIED_SOURCE_BUNDLE}")" ||
		die "Trusted source bundle cannot list its head"
	[ "${heads}" = "${EXPECTED_CONTAINER_COMMIT} refs/heads/source-kit" ] ||
		die "Trusted source bundle exposes an unexpected commit or ref"
	refs="$(git -C "${SCRIPT_DIR}" for-each-ref --format='%(objectname) %(refname)')" ||
		die "Verified source checkout refs cannot be enumerated"
	[ "${refs}" = "${EXPECTED_CONTAINER_COMMIT} refs/heads/source-kit" ] ||
		die "Verified source checkout contains an unexpected ref"
	[ ! -e "${SCRIPT_DIR}/.git/objects/info/alternates" ] &&
		[ ! -L "${SCRIPT_DIR}/.git/objects/info/alternates" ] ||
		die "Verified source checkout uses forbidden object alternates"
	[ ! -e "${SCRIPT_DIR}/.git/info/grafts" ] &&
		[ ! -L "${SCRIPT_DIR}/.git/info/grafts" ] ||
		die "Verified source checkout uses forbidden grafts"
	[ ! -e "${SCRIPT_DIR}/.git/shallow" ] && [ ! -L "${SCRIPT_DIR}/.git/shallow" ] ||
		die "Verified source checkout must not be shallow"
	[ -z "$(git -C "${SCRIPT_DIR}" replace -l)" ] ||
		die "Verified source checkout contains replacement refs"
	if ! fsck_output="$(git -C "${SCRIPT_DIR}" fsck --full --no-reflogs --unreachable --no-progress 2>&1)"; then
		die "Verified source checkout object closure failed: ${fsck_output}"
	fi
	[ -z "${fsck_output}" ] ||
		die "Verified source checkout contains unreachable objects: ${fsck_output}"
	TRUSTED_SOURCE_BUNDLE_SHA256="${actual_sha}"
}

write_expected_rescue_real_evidence() {
	local output="$1"
	{
		printf 'rescue_real_evidence_version=1\n'
		printf 'rescue_real_result=pass\n'
		printf 'source_original_commit=%s\n' "${KIT_ORIGINAL_COMMIT}"
		printf 'source_original_tree=%s\n' "${KIT_ORIGINAL_TREE}"
		printf 'source_container_commit=%s\n' "${KIT_CONTAINER_COMMIT}"
		printf 'source_container_tree=%s\n' "${KIT_CONTAINER_TREE}"
		printf 'source_payload_manifest_sha256=%s\n' \
			"${KIT_PAYLOAD_MANIFEST_SHA256}"
		printf 'rescue_guard_sha256=%s\n' \
			"$(sha256sum "${SRC_FILES}/usr/sbin/cr6608-rescue-guard" | awk '{print $1}')"
		printf 'rescue_test_sha256=%s\n' \
			"$(sha256sum "${RESCUE_GUARD_TEST}" | awk '{print $1}')"
		printf 'rescue_firewall_include_sha256=%s\n' \
			"$(sha256sum "${SRC_FILES}/usr/libexec/cr6608-rescue-firewall-include" | awk '{print $1}')"
		printf 'rescue_firewall_init_sha256=%s\n' \
			"$(sha256sum "${SRC_FILES}/etc/init.d/firewall" | awk '{print $1}')"
		printf 'rescue_real_paths=br-lan,br-lan.100\n'
		printf 'rescue_real_arp_ignore=all,default,br-lan:1\n'
		printf 'rescue_real_spoof=arp,ipv4,vlan-arp,vlan-ipv4\n'
		printf 'rescue_real_firewall_stop=fw4-own-table\n'
	} > "${output}"
}

verify_rescue_real_evidence_unchanged() {
	local current_identity actual_sha expected
	[ "${RESCUE_REAL_EVIDENCE_GATE_STATUS}" = pass-root-owned-real-netns-v1 ] ||
		die "Real rescue evidence was not validated"
	[ -f "${RESCUE_REAL_EVIDENCE}" ] && [ ! -L "${RESCUE_REAL_EVIDENCE}" ] ||
		die "Real rescue evidence must remain a regular non-symlink file"
	[ "$(stat -c '%u' "${RESCUE_REAL_EVIDENCE}")" = 0 ] ||
		die "Real rescue evidence must remain root-owned"
	[ "$(stat -c '%a' "${RESCUE_REAL_EVIDENCE}")" = 444 ] ||
		die "Real rescue evidence must remain mode 0444"
	[ "$(stat -c '%h' "${RESCUE_REAL_EVIDENCE}")" = 1 ] ||
		die "Real rescue evidence must have exactly one hard link"
	current_identity="$(stat -c '%d:%i' "${RESCUE_REAL_EVIDENCE}")" ||
		die "Real rescue evidence identity cannot be read"
	[ "${current_identity}" = "${RESCUE_REAL_EVIDENCE_IDENTITY}" ] ||
		die "Real rescue evidence inode changed after validation"
	actual_sha="$(sha256sum "${RESCUE_REAL_EVIDENCE}" | awk '{print $1}')"
	[ "${actual_sha}" = "${RESCUE_REAL_EVIDENCE_SHA256}" ] ||
		die "Real rescue evidence changed after validation"
	expected="$(mktemp "${LOG_DIR}/.rescue-real-expected.XXXXXX")" ||
		die "Cannot allocate expected real rescue evidence"
	write_expected_rescue_real_evidence "${expected}"
	if ! cmp -s "${expected}" "${RESCUE_REAL_EVIDENCE}"; then
		diff -u "${expected}" "${RESCUE_REAL_EVIDENCE}" >&2 || true
		rm -f -- "${expected}"
		die "Real rescue evidence is not bound to this exact source and test"
	fi
	rm -f -- "${expected}"
}

validate_rescue_real_evidence() {
	local resolved_evidence
	[ -n "${RESCUE_REAL_EVIDENCE}" ] ||
		die "A full build requires CR6608_RESCUE_REAL_EVIDENCE"
	case "${RESCUE_REAL_EVIDENCE}" in
		*$'\n'*|*$'\t'*) die "Real rescue evidence path contains a newline or tab" ;;
	esac
	[ -f "${RESCUE_REAL_EVIDENCE}" ] && [ ! -L "${RESCUE_REAL_EVIDENCE}" ] ||
		die "Real rescue evidence must be a regular non-symlink file"
	resolved_evidence="$(readlink -f -- "${RESCUE_REAL_EVIDENCE}")" ||
		die "Real rescue evidence path cannot be canonicalized"
	[ -n "${resolved_evidence}" ] || die "Real rescue evidence canonical path is empty"
	RESCUE_REAL_EVIDENCE="${resolved_evidence}"
	[ "$(stat -c '%u' "${RESCUE_REAL_EVIDENCE}")" = 0 ] ||
		die "Real rescue evidence must be root-owned"
	[ "$(stat -c '%a' "${RESCUE_REAL_EVIDENCE}")" = 444 ] ||
		die "Real rescue evidence must be mode 0444"
	[ "$(stat -c '%h' "${RESCUE_REAL_EVIDENCE}")" = 1 ] ||
		die "Real rescue evidence must have exactly one hard link"
	RESCUE_REAL_EVIDENCE_IDENTITY="$(stat -c '%d:%i' "${RESCUE_REAL_EVIDENCE}")" ||
		die "Real rescue evidence identity cannot be read"
	RESCUE_REAL_EVIDENCE_SHA256="$(sha256sum "${RESCUE_REAL_EVIDENCE}" | awk '{print $1}')"
	require_lower_hex "${RESCUE_REAL_EVIDENCE_SHA256}" 64 \
		"Real rescue evidence SHA-256"
	RESCUE_REAL_EVIDENCE_GATE_STATUS="pass-root-owned-real-netns-v1"
	verify_rescue_real_evidence_unchanged
}

validate_trusted_source_gate() {
	local value resolved_bundle
	for value in \
		"${VERIFIED_SOURCE_BUNDLE}" "${EXPECTED_SOURCE_BUNDLE_SHA256}" \
		"${EXPECTED_ORIGINAL_COMMIT}" "${EXPECTED_ORIGINAL_TREE}" \
		"${EXPECTED_CONTAINER_COMMIT}" "${EXPECTED_CONTAINER_TREE}" \
		"${EXPECTED_PAYLOAD_MANIFEST_SHA256}"; do
		[ -n "${value}" ] ||
			die "All externally trusted source bundle pins are required together"
	done
	require_lower_hex "${EXPECTED_SOURCE_BUNDLE_SHA256}" 64 "Trusted bundle SHA-256"
	require_lower_hex "${EXPECTED_ORIGINAL_COMMIT}" 40 "Trusted original commit"
	require_lower_hex "${EXPECTED_ORIGINAL_TREE}" 40 "Trusted original tree"
	require_lower_hex "${EXPECTED_CONTAINER_COMMIT}" 40 "Trusted container commit"
	require_lower_hex "${EXPECTED_CONTAINER_TREE}" 40 "Trusted container tree"
	require_lower_hex "${EXPECTED_PAYLOAD_MANIFEST_SHA256}" 64 "Trusted payload manifest SHA-256"
	resolved_bundle="$(readlink -f -- "${VERIFIED_SOURCE_BUNDLE}")" ||
		die "Trusted source bundle path cannot be canonicalized"
	[ -n "${resolved_bundle}" ] || die "Trusted source bundle canonical path is empty"
	VERIFIED_SOURCE_BUNDLE="${resolved_bundle}"
	[ "${KIT_ORIGINAL_COMMIT}" = "${EXPECTED_ORIGINAL_COMMIT}" ] ||
		die "Source original commit differs from the external pin"
	[ "${KIT_ORIGINAL_TREE}" = "${EXPECTED_ORIGINAL_TREE}" ] ||
		die "Source original tree differs from the external pin"
	[ "${KIT_CONTAINER_COMMIT}" = "${EXPECTED_CONTAINER_COMMIT}" ] ||
		die "Source container commit differs from the external pin"
	[ "${KIT_CONTAINER_TREE}" = "${EXPECTED_CONTAINER_TREE}" ] ||
		die "Source container tree differs from the external pin"
	[ "${KIT_PAYLOAD_MANIFEST_SHA256}" = "${EXPECTED_PAYLOAD_MANIFEST_SHA256}" ] ||
		die "Source payload manifest differs from the external pin"
	verify_trusted_source_bundle_unchanged
	SOURCE_TRUST_GATE_STATUS="pass-external-expected-values"
}

select_node_runtime() {
	local candidate resolved major node_dir
	local -a candidates=()
	[ -z "${CR6608_NODE_BIN:-}" ] || candidates+=("${CR6608_NODE_BIN}")
	[ ! -x "${HOME}/tools/node20/bin/node" ] || \
		candidates+=("${HOME}/tools/node20/bin/node")
	if command -v node >/dev/null 2>&1; then
		candidates+=("$(command -v node)")
	fi
	for candidate in "${candidates[@]}"; do
		[ -x "${candidate}" ] || continue
		resolved="$(readlink -f -- "${candidate}")" || continue
		major="$("${resolved}" -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
		case "${major}" in ''|*[!0-9]*) continue ;; esac
		[ "${major}" -ge 18 ] || continue
		node_dir="${resolved%/node}"
		PATH="${node_dir}:${PATH}"
		export PATH
		NODE_RUNTIME="${resolved}"
		return 0
	done
	die "Node.js 18 or newer is required for the real Playwright UI tests"
}

resolve_browser_runtime() {
	local candidate version
	for candidate in \
		"${SCRIPT_DIR}/test-tools/playwright/node_modules/playwright-core" \
		"${FINAL_ROOT}/tools/playwright/node_modules/playwright-core" \
		"${HOME}/tools/playwright/node_modules/playwright-core"; do
		[ -s "${candidate}/package.json" ] || continue
		version="$("${NODE_RUNTIME}" -e \
			'process.stdout.write(require(process.argv[1]).version)' \
			"${candidate}/package.json")" || continue
		[ "${version}" = "${PLAYWRIGHT_EXPECTED_VERSION}" ] || continue
		PLAYWRIGHT_CORE_DIR="$(readlink -f -- "${candidate}")"
		break
	done
	[ -n "${PLAYWRIGHT_CORE_DIR}" ] || \
		die "Pinned playwright-core ${PLAYWRIGHT_EXPECTED_VERSION} is missing; run tests/setup-browser-tests.sh"
	CHROMIUM_EXECUTABLE="$("${NODE_RUNTIME}" -e \
		'const { chromium } = require(process.argv[1]); process.stdout.write(chromium.executablePath())' \
		"${PLAYWRIGHT_CORE_DIR}")"
	[ -x "${CHROMIUM_EXECUTABLE}" ] || \
		die "Pinned Playwright Chromium executable is missing; run tests/setup-browser-tests.sh"
	CHROMIUM_EXECUTABLE="$(readlink -f -- "${CHROMIUM_EXECUTABLE}")"
	CHROMIUM_SHA256="$(sha256sum "${CHROMIUM_EXECUTABLE}" | awk '{print $1}')"
}

maintenance_flashable_basename_is_expected() {
	case "$1" in
		*"${DEVICE_PROFILE}"*squashfs-sysupgrade.bin|\
		*"${DEVICE_PROFILE}"*squashfs-firmware.bin) return 0 ;;
		*) return 1 ;;
	esac
}

remove_maintenance_flashables_from_bin() {
	local expected_bin candidate parent scan_file rc=0
	local -a candidates=()
	[ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ] || return 0
	[ "${MAINTENANCE_BIN_CLEANUP_ARMED}" = 1 ] || return 0
	expected_bin="${OPENWRT_DIR}/bin/targets/ramips/mt7621"
	[ "${BIN_DIR}" = "${expected_bin}" ] || return 1
	[ ! -e "${BIN_DIR}" ] && return 0
	[ -d "${BIN_DIR}" ] && [ ! -L "${BIN_DIR}" ] || return 1
	scan_file="$(mktemp "${LOG_DIR}/.maintenance-bin-scan.XXXXXX")" || return 1
	if ! find "${BIN_DIR}" -maxdepth 1 \
			\( -type f -o -type l \) \
			\( -name "*${DEVICE_PROFILE}*squashfs-sysupgrade.bin" -o \
			   -name "*${DEVICE_PROFILE}*squashfs-firmware.bin" \) \
			-print0 > "${scan_file}"; then
		rm -f -- "${scan_file}"
		return 1
	fi
	mapfile -d '' -t candidates < "${scan_file}" || {
		rm -f -- "${scan_file}"
		return 1
	}
	rm -f -- "${scan_file}"
	for candidate in "${candidates[@]}"; do
		parent="$(dirname -- "${candidate}")"
		if [ "${parent}" != "${BIN_DIR}" ] || \
			! maintenance_flashable_basename_is_expected "${candidate##*/}"; then
			printf 'Refusing unsafe maintenance cleanup target: %s\n' \
				"${candidate}" >&2
			rc=1
			continue
		fi
		rm -f -- "${candidate}" || rc=1
		if [ -e "${candidate}" ] || [ -L "${candidate}" ]; then
			printf 'Maintenance flashable remained after cleanup: %s\n' \
				"${candidate}" >&2
			rc=1
		fi
	done
	scan_file="$(mktemp "${LOG_DIR}/.maintenance-bin-rescan.XXXXXX")" || return 1
	if ! find "${BIN_DIR}" -maxdepth 1 \
			\( -type f -o -type l \) \
			\( -name "*${DEVICE_PROFILE}*squashfs-sysupgrade.bin" -o \
			   -name "*${DEVICE_PROFILE}*squashfs-firmware.bin" \) \
			-print0 > "${scan_file}"; then
		rm -f -- "${scan_file}"
		return 1
	fi
	if [ -s "${scan_file}" ]; then
		printf 'Maintenance flashable appeared during final cleanup rescan\n' >&2
		rc=1
	fi
	rm -f -- "${scan_file}"
	return "${rc}"
}

cleanup_maintenance_flashable_staging() {
	local artifact
	[ -n "${MAINTENANCE_FLASHABLE_DIR}" ] || return 0
	case "${MAINTENANCE_FLASHABLE_DIR}" in
		"${LOG_DIR}"/.maintenance-flashables.*) ;;
		*)
			printf 'Refusing unsafe maintenance staging cleanup: %s\n' \
				"${MAINTENANCE_FLASHABLE_DIR}" >&2
			return 1
			;;
	esac
	[ ! -L "${MAINTENANCE_FLASHABLE_DIR}" ] || return 1
	for artifact in "${MAINTENANCE_SYSUPGRADE_ARTIFACT}" \
		"${MAINTENANCE_FIRMWARE_ARTIFACT}"; do
		[ -n "${artifact}" ] || continue
		case "${artifact}" in
			"${MAINTENANCE_FLASHABLE_DIR}"/cr6608-maintenance-*.DO-NOT-FLASH.bin) ;;
			*)
				printf 'Refusing unsafe staged maintenance artifact cleanup: %s\n' \
					"${artifact}" >&2
				return 1
				;;
		esac
		rm -f -- "${artifact}" || return 1
		[ ! -e "${artifact}" ] && [ ! -L "${artifact}" ] || return 1
	done
	if [ -d "${MAINTENANCE_FLASHABLE_DIR}" ]; then
		rmdir -- "${MAINTENANCE_FLASHABLE_DIR}" || return 1
	fi
	MAINTENANCE_FLASHABLE_DIR=""
	MAINTENANCE_SYSUPGRADE_ARTIFACT=""
	MAINTENANCE_FIRMWARE_ARTIFACT=""
}

quarantine_maintenance_flashables() {
	local source_sysupgrade source_firmware sysupgrade_scan firmware_scan
	local -a found_sysupgrades=() found_firmwares=()
	[ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ] || return 0
	[ "${MAINTENANCE_BIN_CLEANUP_ARMED}" = 1 ] || \
		die 'Maintenance flashable quarantine was not armed by the locked full build'
	[ -d "${BIN_DIR}" ] && [ ! -L "${BIN_DIR}" ] || \
		die "Maintenance build output directory is unavailable: ${BIN_DIR}"
	sysupgrade_scan="$(mktemp "${LOG_DIR}/.maintenance-sysupgrade-scan.XXXXXX")" || \
		die 'Could not allocate maintenance sysupgrade scan file'
	firmware_scan="$(mktemp "${LOG_DIR}/.maintenance-firmware-scan.XXXXXX")" || {
		rm -f -- "${sysupgrade_scan}"
		die 'Could not allocate maintenance firmware scan file'
	}
	if ! find "${BIN_DIR}" -maxdepth 1 -type f \
		-name "*${DEVICE_PROFILE}*squashfs-sysupgrade.bin" -print0 > "${sysupgrade_scan}" || \
		! find "${BIN_DIR}" -maxdepth 1 -type f \
		-name "*${DEVICE_PROFILE}*squashfs-firmware.bin" -print0 > "${firmware_scan}"; then
		rm -f -- "${sysupgrade_scan}" "${firmware_scan}"
		die 'Could not scan maintenance flashable build artifacts'
	fi
	mapfile -d '' -t found_sysupgrades < "${sysupgrade_scan}" || {
		rm -f -- "${sysupgrade_scan}" "${firmware_scan}"
		die 'Could not parse maintenance sysupgrade scan'
	}
	mapfile -d '' -t found_firmwares < "${firmware_scan}" || {
		rm -f -- "${sysupgrade_scan}" "${firmware_scan}"
		die 'Could not parse maintenance firmware scan'
	}
	rm -f -- "${sysupgrade_scan}" "${firmware_scan}"
	[ "${#found_sysupgrades[@]}" -eq 1 ] || \
		die "Expected exactly one maintenance sysupgrade artifact, found ${#found_sysupgrades[@]}"
	[ "${#found_firmwares[@]}" -eq 1 ] || \
		die "Expected exactly one maintenance combined-firmware artifact, found ${#found_firmwares[@]}"
	source_sysupgrade="${found_sysupgrades[0]}"
	source_firmware="${found_firmwares[0]}"
	MAINTENANCE_FLASHABLE_DIR="$(mktemp -d "${LOG_DIR}/.maintenance-flashables.XXXXXX")"
	chmod 0700 -- "${MAINTENANCE_FLASHABLE_DIR}"
	MAINTENANCE_SYSUPGRADE_ARTIFACT="${MAINTENANCE_FLASHABLE_DIR}/cr6608-maintenance-sysupgrade.DO-NOT-FLASH.bin"
	MAINTENANCE_FIRMWARE_ARTIFACT="${MAINTENANCE_FLASHABLE_DIR}/cr6608-maintenance-firmware.DO-NOT-FLASH.bin"
	mv -T -- "${source_sysupgrade}" "${MAINTENANCE_SYSUPGRADE_ARTIFACT}"
	mv -T -- "${source_firmware}" "${MAINTENANCE_FIRMWARE_ARTIFACT}"
	[ -s "${MAINTENANCE_SYSUPGRADE_ARTIFACT}" ] && \
		[ -s "${MAINTENANCE_FIRMWARE_ARTIFACT}" ] || \
		die 'Maintenance flashable quarantine is incomplete'
	remove_maintenance_flashables_from_bin || \
		die 'Could not purge maintenance flashables from the public build tree'
	ok 'maintenance flashables quarantined for inspection and tracked by EXIT cleanup'
}

capture_image_inspection_hashes() {
	local sysupgrade="$1"
	local firmware="$2"
	local initramfs="$3"
	local packages="$4"
	local path
	for path in "${sysupgrade}" "${firmware}" "${initramfs}" "${packages}"; do
		[ -f "${path}" ] && [ ! -L "${path}" ] && [ -s "${path}" ] || \
			die "Inspection input is not a non-empty regular file: ${path}"
	done
	INSPECTED_SYSUPGRADE_SHA256="$(sha256sum "${sysupgrade}" | awk '{print $1}')"
	INSPECTED_FIRMWARE_SHA256="$(sha256sum "${firmware}" | awk '{print $1}')"
	INSPECTED_INITRAMFS_SHA256="$(sha256sum "${initramfs}" | awk '{print $1}')"
	INSPECTED_PACKAGE_MANIFEST_SHA256="$(sha256sum "${packages}" | awk '{print $1}')"
}

verify_image_inspection_hashes_unchanged() {
	local sysupgrade="$1"
	local firmware="$2"
	local initramfs="$3"
	local packages="$4"
	[ -n "${INSPECTED_SYSUPGRADE_SHA256}" ] && \
		[ -n "${INSPECTED_FIRMWARE_SHA256}" ] && \
		[ -n "${INSPECTED_INITRAMFS_SHA256}" ] && \
		[ -n "${INSPECTED_PACKAGE_MANIFEST_SHA256}" ] || \
		die 'Image inspection hash state is incomplete'
	[ "$(sha256sum "${sysupgrade}" | awk '{print $1}')" = \
		"${INSPECTED_SYSUPGRADE_SHA256}" ] || \
		die 'Sysupgrade bytes changed during or after image inspection'
	[ "$(sha256sum "${firmware}" | awk '{print $1}')" = \
		"${INSPECTED_FIRMWARE_SHA256}" ] || \
		die 'Combined-firmware bytes changed during or after image inspection'
	[ "$(sha256sum "${initramfs}" | awk '{print $1}')" = \
		"${INSPECTED_INITRAMFS_SHA256}" ] || \
		die 'Initramfs bytes changed during or after image inspection'
	[ "$(sha256sum "${packages}" | awk '{print $1}')" = \
		"${INSPECTED_PACKAGE_MANIFEST_SHA256}" ] || \
		die 'Package manifest changed during or after image inspection'
}

verify_published_images_match_inspection() {
	local publication_root="${1:-${PUBLISH_DIR}}"
	if [ "${PUBLISH_FLASHABLE_IMAGES}" = 1 ]; then
		[ "$(sha256sum "${publication_root}/${FINAL_IMAGE}" | awk '{print $1}')" = \
			"${INSPECTED_SYSUPGRADE_SHA256}" ] || \
			die 'Published sysupgrade differs from the inspected image'
		[ "$(sha256sum "${publication_root}/${COMBINED_IMAGE}" | awk '{print $1}')" = \
			"${INSPECTED_FIRMWARE_SHA256}" ] || \
			die 'Published combined firmware differs from the inspected image'
	fi
	[ "$(sha256sum "${publication_root}/${INITRAMFS_IMAGE}" | awk '{print $1}')" = \
		"${INSPECTED_INITRAMFS_SHA256}" ] || \
		die 'Published initramfs differs from the inspected image'
	[ "$(sha256sum "${publication_root}/openwrt-package-manifest.txt" | awk '{print $1}')" = \
		"${INSPECTED_PACKAGE_MANIFEST_SHA256}" ] || \
		die 'Published package manifest differs from the inspected input'
}

read_regular_file_sha256() {
	local path="${1:-}"
	local checksum_line checksum
	[ -n "${path}" ] && [ -f "${path}" ] && [ ! -L "${path}" ] || return 1
	checksum_line="$(sha256sum -- "${path}")" || return 1
	checksum="${checksum_line%% *}"
	[[ "${checksum}" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s\n' "${checksum}"
}

verify_inspection_attestation_unchanged() {
	local publication_root="${1:-}"
	local current_inspector_sha current_log_sha published_log_sha
	[ -n "${INSPECTOR_EXECUTED_SHA256}" ] && \
		[ -n "${INSPECTION_LOG_VERIFIED_SHA256}" ] || \
		die 'Verified inspector execution attestation is incomplete'
	if ! current_inspector_sha="$(read_regular_file_sha256 "${INSPECTOR}")"; then
		die 'Image inspector hash could not be recomputed after execution'
	fi
	[ "${current_inspector_sha}" = "${INSPECTOR_EXECUTED_SHA256}" ] || \
		die 'Image inspector changed after its verified execution'
	if ! current_log_sha="$(read_regular_file_sha256 "${INSPECTION_LOG}")"; then
		die 'Verified image inspection log hash could not be recomputed'
	fi
	[ "${current_log_sha}" = "${INSPECTION_LOG_VERIFIED_SHA256}" ] || \
		die 'Image inspection log changed after its gates passed'
	if [ -n "${publication_root}" ]; then
		[ -d "${publication_root}" ] && [ ! -L "${publication_root}" ] || \
			die 'Publication root is unavailable for inspection-attestation verification'
		if ! published_log_sha="$(read_regular_file_sha256 \
				"${publication_root}/prepublish-inspection.txt")"; then
			die 'Published image inspection log hash could not be computed'
		fi
		[ "${published_log_sha}" = "${INSPECTION_LOG_VERIFIED_SHA256}" ] || \
			die 'Published image inspection log differs from the gate-passing log'
	fi
}

cleanup_build_private_signing_keys() {
	local expected_uid key
	[ "${BUILD_PRIVATE_KEYS_INSTALLED}" = 1 ] || return 0
	expected_uid="$(id -u)" || return 1
	for key in "${OPENWRT_DIR}/key-build" "${OPENWRT_DIR}/private-key.pem"; do
		if [ ! -e "${key}" ] && [ ! -L "${key}" ]; then
			continue
		fi
		case "${key}" in
			"${OPENWRT_DIR}/key-build"|"${OPENWRT_DIR}/private-key.pem") ;;
			*) return 1 ;;
		esac
		[ -f "${key}" ] && [ ! -L "${key}" ] &&
			[ "$(stat -c '%u' "${key}" 2>/dev/null || true)" = "${expected_uid}" ] &&
			[ "$(stat -c '%a' "${key}" 2>/dev/null || true)" = 600 ] || {
			printf 'WARNING: refusing unverified build-key cleanup: %s\n' "${key}" >&2
			return 1
		}
		rm -f -- "${key}" || return 1
	done
	BUILD_PRIVATE_KEYS_INSTALLED=0
}

cleanup() {
	local original_status="${1:-$?}"
	local cleanup_failed=0
	trap - EXIT ERR
	if ! cleanup_build_private_signing_keys; then
		printf 'WARNING: private build-key cleanup was incomplete\n' >&2
		cleanup_failed=1
	fi
	if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
		if ! cleanup_maintenance_flashable_staging; then
			printf 'WARNING: maintenance staging cleanup was incomplete\n' >&2
			cleanup_failed=1
		fi
		if ! remove_maintenance_flashables_from_bin; then
			printf 'WARNING: maintenance bin cleanup was incomplete\n' >&2
			cleanup_failed=1
		fi
	fi
	if [ -n "${PUBLISH_DIR}" ]; then
		cleanup_failed=1
		case "${PUBLISH_DIR}" in
			"${RELEASES_DIR}"/.publish.*)
				if [ -n "${PUBLISH_DIR_IDENTITY}" ] && \
					[ -d "${PUBLISH_DIR}" ] && [ ! -L "${PUBLISH_DIR}" ] && \
					[ "$(stat -c '%d:%i' "${PUBLISH_DIR}" 2>/dev/null || true)" = \
						"${PUBLISH_DIR_IDENTITY}" ]; then
					rm -rf -- "${PUBLISH_DIR}" || cleanup_failed=1
				else
					printf 'WARNING: refusing unverified public staging cleanup: %s\n' \
						"${PUBLISH_DIR}" >&2
				fi
				;;
			*)
				printf 'WARNING: refusing unsafe public staging cleanup: %s\n' \
					"${PUBLISH_DIR}" >&2
				;;
		esac
	fi
	if [ -n "${PUBLISH_PENDING_DIR}" ]; then
		cleanup_failed=1
		case "${PUBLISH_PENDING_DIR}" in
			"${RELEASES_DIR}"/maintenance-*|"${RELEASES_DIR}"/commissioning-*|"${RELEASES_DIR}"/candidate-*|"${RELEASES_DIR}"/qualification-*|"${RELEASES_DIR}"/forced-ul-lab-*)
				if [ -n "${PUBLISH_PENDING_IDENTITY}" ] && \
					[ -d "${PUBLISH_PENDING_DIR}" ] && \
					[ ! -L "${PUBLISH_PENDING_DIR}" ] && \
					[ "$(stat -c '%d:%i' "${PUBLISH_PENDING_DIR}" 2>/dev/null || true)" = \
						"${PUBLISH_PENDING_IDENTITY}" ]; then
					rm -rf -- "${PUBLISH_PENDING_DIR}" || cleanup_failed=1
				else
					printf 'WARNING: refusing unverified pending release cleanup: %s\n' \
						"${PUBLISH_PENDING_DIR}" >&2
				fi
				;;
			*)
				printf 'WARNING: refusing unsafe pending release cleanup: %s\n' \
					"${PUBLISH_PENDING_DIR}" >&2
				;;
		esac
	fi
	if [ -n "${FACTORY38_BUNDLE_DIR}" ]; then
		cleanup_failed=1
		case "${FACTORY38_BUNDLE_DIR##*/}" in
			.factory38-device-bundle-*)
				if [ "${FACTORY38_BUNDLE_DIR}" = "${FACTORY38_WORK_DIR}" ] && \
					[ -d "${FACTORY38_BUNDLE_DIR}" ] && \
					[ ! -L "${FACTORY38_BUNDLE_DIR}" ] && \
					[ -n "${FACTORY38_WORK_IDENTITY}" ] && \
					[ "$(stat -c '%d:%i' "${FACTORY38_BUNDLE_DIR}" 2>/dev/null || true)" = \
						"${FACTORY38_WORK_IDENTITY}" ] && \
					[ -n "${FACTORY38_PRIVATE_PARENT_IDENTITY}" ] && \
					[ "$(stat -c '%d:%i' "${FACTORY38_PRIVATE_PARENT}" 2>/dev/null || true)" = \
						"${FACTORY38_PRIVATE_PARENT_IDENTITY}" ]; then
					rm -rf -- "${FACTORY38_BUNDLE_DIR}" || cleanup_failed=1
				elif [ "${FACTORY38_BUNDLE_DIR}" = "${FACTORY38_WORK_DIR}" ] && \
					[ -z "${FACTORY38_WORK_IDENTITY}" ] && \
					[ -d "${FACTORY38_BUNDLE_DIR}" ] && \
					[ ! -L "${FACTORY38_BUNDLE_DIR}" ] && \
					[ "$(stat -c '%a' "${FACTORY38_BUNDLE_DIR}" 2>/dev/null || true)" = 700 ] && \
					[ "$(stat -c '%u' "${FACTORY38_BUNDLE_DIR}" 2>/dev/null || true)" = "$(id -u)" ] && \
					[ "$(stat -c '%d:%i' "${FACTORY38_PRIVATE_PARENT}" 2>/dev/null || true)" = \
						"${FACTORY38_PRIVATE_PARENT_IDENTITY}" ]; then
					rmdir -- "${FACTORY38_BUNDLE_DIR}" || cleanup_failed=1
				else
					printf 'WARNING: refusing unverified private staging cleanup: %s\n' \
						"${FACTORY38_BUNDLE_DIR}" >&2
				fi
				;;
			*)
				printf 'WARNING: refusing unsafe private staging cleanup: %s\n' \
					"${FACTORY38_BUNDLE_DIR}" >&2
				;;
		esac
	fi
	if [ -n "${FACTORY38_PENDING_OUTPUT}" ]; then
		cleanup_failed=1
		if [ "${FACTORY38_PENDING_OUTPUT}" = "${FACTORY38_PRIVATE_OUTPUT}" ] && \
			[ -n "${FACTORY38_PENDING_OUTPUT_IDENTITY}" ] && \
			[ -d "${FACTORY38_PENDING_OUTPUT}" ] && \
			[ ! -L "${FACTORY38_PENDING_OUTPUT}" ] && \
			[ "$(stat -c '%d:%i' "${FACTORY38_PENDING_OUTPUT}" 2>/dev/null || true)" = \
				"${FACTORY38_PENDING_OUTPUT_IDENTITY}" ] && \
			[ "$(stat -c '%d:%i' "${FACTORY38_PRIVATE_PARENT}" 2>/dev/null || true)" = \
				"${FACTORY38_PRIVATE_PARENT_IDENTITY}" ]; then
			rm -rf -- "${FACTORY38_PENDING_OUTPUT}" || cleanup_failed=1
		else
			printf 'WARNING: refusing unverified pending private cleanup: %s\n' \
				"${FACTORY38_PENDING_OUTPUT}" >&2
		fi
	fi
	if [ "${original_status}" -eq 0 ] && [ "${cleanup_failed}" -ne 0 ]; then
		original_status=1
	fi
	exit "${original_status}"
}

on_error() {
	local ec=$?
	trap - ERR
	printf '\n\033[1;31mBUILD FAILED (exit %s) at line %s: %s\033[0m\n' \
		"${ec}" "${BASH_LINENO[0]:-?}" "${BASH_COMMAND}" >&2
	exit "${ec}"
}
trap on_error ERR
trap 'cleanup $?' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

case "${BUILD_EPOCH}" in
	''|*[!0-9]*) die "SMARTAP_BUILD_EPOCH must be a decimal Unix timestamp" ;;
esac
[ "${#BUILD_EPOCH}" -eq 10 ] &&
	[ "${BUILD_EPOCH}" -ge 1577836800 ] 2>/dev/null &&
	[ "${BUILD_EPOCH}" -le 2145916800 ] 2>/dev/null ||
	die "SMARTAP_BUILD_EPOCH is outside the accepted range"
BUILD_TIME="$(date -u -d "@${BUILD_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)" ||
	die "SMARTAP_BUILD_EPOCH cannot be formatted"

if [ "$(id -u)" -eq 0 ]; then
	die "Refusing to run OpenWrt buildroot as root."
fi

case "${UI_SCREENSHOT_DIR}" in
	/*/.mobile-layout) ;;
	*) die "CR6608_UI_SCREENSHOT_DIR must be an absolute .mobile-layout path" ;;
esac
UI_SCREENSHOT_PARENT="${UI_SCREENSHOT_DIR%/.mobile-layout}"
UI_SCREENSHOT_PARENT="$(readlink -f -- "${UI_SCREENSHOT_PARENT}")" || \
	die "UI screenshot parent cannot be canonicalized"
[ -d "${UI_SCREENSHOT_PARENT}" ] && [ ! -L "${UI_SCREENSHOT_PARENT}" ] || \
	die "UI screenshot parent is missing or unsafe"
[ "$(stat -c '%u' "${UI_SCREENSHOT_PARENT}")" -eq "$(id -u)" ] || \
	die "UI screenshot parent must be owned by the build user"
[ -z "$(find "${UI_SCREENSHOT_PARENT}" -maxdepth 0 -perm /022 -print -quit)" ] || \
	die "UI screenshot parent must not be group/world writable"
UI_SCREENSHOT_DIR="${UI_SCREENSHOT_PARENT}/.mobile-layout"
if [ -e "${UI_SCREENSHOT_DIR}" ] || [ -L "${UI_SCREENSHOT_DIR}" ]; then
	[ -d "${UI_SCREENSHOT_DIR}" ] && [ ! -L "${UI_SCREENSHOT_DIR}" ] && \
		[ "$(stat -c '%u' "${UI_SCREENSHOT_DIR}")" -eq "$(id -u)" ] || \
		die "Existing UI screenshot directory is unsafe"
fi
export CR6608_UI_SCREENSHOT_DIR="${UI_SCREENSHOT_DIR}"

select_node_runtime
[ -d "${SCRIPT_DIR}/.git" ] || die "Source kit is not a Git checkout"
[ -z "$(git -C "${SCRIPT_DIR}" status --porcelain --untracked-files=all)" ] || \
	die "Commit the complete source kit before testing or building"
if ! source_identity_output="$(
	python3 -I -B "${SOURCE_KIT_TOOL}" verify \
		--repo "${SCRIPT_DIR}" \
		--kit-base "${KIT_BASE_COMMIT}" \
		--auth-fix "${AUTH_FIX_COMMIT}" \
		--product-version "${PRODUCT_VERSION}" \
		--build-epoch "${BUILD_EPOCH}"
)"; then
	die "Source checkout failed the reviewed/sanitized identity gate"
fi
mapfile -t source_identity_lines <<<"${source_identity_output}"
[ "${#source_identity_lines[@]}" -eq 10 ] || \
	die "Source identity emitted an unexpected field count"
case "${source_identity_lines[0]}" in source_repository_mode=*) ;; *) die "Source identity mode is missing" ;; esac
case "${source_identity_lines[1]}" in source_product_version=*) ;; *) die "Source product version is missing" ;; esac
case "${source_identity_lines[2]}" in source_build_epoch=*) ;; *) die "Source build epoch is missing" ;; esac
case "${source_identity_lines[3]}" in source_original_commit=*) ;; *) die "Source original commit is missing" ;; esac
case "${source_identity_lines[4]}" in source_original_tree=*) ;; *) die "Source original tree is missing" ;; esac
case "${source_identity_lines[5]}" in source_container_commit=*) ;; *) die "Source container commit is missing" ;; esac
case "${source_identity_lines[6]}" in source_container_tree=*) ;; *) die "Source container tree is missing" ;; esac
case "${source_identity_lines[7]}" in source_kit_base_commit=*) ;; *) die "Source baseline identity is missing" ;; esac
case "${source_identity_lines[8]}" in source_auth_fix_commit=*) ;; *) die "Source authentication identity is missing" ;; esac
case "${source_identity_lines[9]}" in source_payload_manifest_sha256=*) ;; *) die "Source payload identity is missing" ;; esac
SOURCE_REPOSITORY_MODE="${source_identity_lines[0]#source_repository_mode=}"
[ "${source_identity_lines[1]}" = "source_product_version=${PRODUCT_VERSION}" ] || \
	die "Source identity product version changed"
[ "${source_identity_lines[2]}" = "source_build_epoch=${BUILD_EPOCH}" ] || \
	die "Source identity build epoch changed"
KIT_ORIGINAL_COMMIT="${source_identity_lines[3]#source_original_commit=}"
KIT_ORIGINAL_TREE="${source_identity_lines[4]#source_original_tree=}"
KIT_CONTAINER_COMMIT="${source_identity_lines[5]#source_container_commit=}"
KIT_CONTAINER_TREE="${source_identity_lines[6]#source_container_tree=}"
KIT_PAYLOAD_MANIFEST_SHA256="${source_identity_lines[9]#source_payload_manifest_sha256=}"
[ "${source_identity_lines[7]}" = "source_kit_base_commit=${KIT_BASE_COMMIT}" ] || \
	die "Source identity baseline pin changed"
[ "${source_identity_lines[8]}" = "source_auth_fix_commit=${AUTH_FIX_COMMIT}" ] || \
	die "Source identity authentication pin changed"
[ "${KIT_CONTAINER_COMMIT}" = "$(git -C "${SCRIPT_DIR}" rev-parse HEAD)" ] || \
	die "Source identity container is not the checked-out HEAD"
KIT_HEAD_COMMIT="${KIT_CONTAINER_COMMIT}"
if [ "${SOURCE_TEST_ONLY}" = 0 ] && \
	[ "${SOURCE_REPOSITORY_MODE}" != sanitized-source-kit ]; then
	die "A full build must start from the verified one-root sanitized source bundle"
fi
source_trust_values_present=0
for source_trust_value in \
	"${VERIFIED_SOURCE_BUNDLE}" "${EXPECTED_SOURCE_BUNDLE_SHA256}" \
	"${EXPECTED_ORIGINAL_COMMIT}" "${EXPECTED_ORIGINAL_TREE}" \
	"${EXPECTED_CONTAINER_COMMIT}" "${EXPECTED_CONTAINER_TREE}" \
	"${EXPECTED_PAYLOAD_MANIFEST_SHA256}"; do
	[ -z "${source_trust_value}" ] ||
		source_trust_values_present=$((source_trust_values_present + 1))
done
if [ "${SOURCE_TEST_ONLY}" = 0 ] || [ "${source_trust_values_present}" -ne 0 ]; then
	[ "${SOURCE_REPOSITORY_MODE}" = sanitized-source-kit ] ||
		die "Externally pinned bundle verification applies only to sanitized source"
	validate_trusted_source_gate
fi

required=(
	bash git make gcc g++ gawk flex bison gettext python3 rsync perl tar xz
	unzip file wget sha256sum flock find sort stat readlink cmp diff mktemp od tee
	nproc date node sh install openssl dd strings gpg timeout
)
missing=()
for cmd in "${required[@]}"; do
	command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
done
if [ "${#missing[@]}" -ne 0 ]; then
	die "Missing Ubuntu build tools: ${missing[*]}"
fi

if [ -n "${FACTORY38_SOURCE}" ] && [ -z "${FACTORY38_PRIVATE_OUTPUT}" ]; then
	die "CR6608_FACTORY_BACKUP requires the separate CR6608_FACTORY38_PRIVATE_OUTPUT opt-in"
fi
if [ -n "${FACTORY38_PRIVATE_OUTPUT}" ]; then
	[ "${FACTORY38_BUILD_MODE}" = maintenance ] || \
		die 'The device-private Factory-38 bundle is available only in maintenance mode'
	FACTORY38_BUNDLE_ENABLED=1
	[ -n "${FACTORY38_SOURCE}" ] || \
		FACTORY38_SOURCE="${FINAL_ROOT}/device-inputs/cr6608-factory-original.bin"
	case "${FACTORY38_SOURCE}" in
		*$'\n'*|*$'\t'*) die "Factory backup path contains a newline or tab" ;;
	esac
	case "${FACTORY38_PRIVATE_OUTPUT}" in
		*$'\n'*|*$'\t'*) die "Factory private output path contains a newline or tab" ;;
	esac
	[ -f "${FACTORY38_SOURCE}" ] && [ ! -L "${FACTORY38_SOURCE}" ] ||
		die "Factory backup must be a regular non-symlink file: ${FACTORY38_SOURCE}"
	FACTORY38_SOURCE="$(readlink -f -- "${FACTORY38_SOURCE}")" ||
		die "Factory backup path cannot be canonicalized"
	FACTORY38_PRIVATE_OUTPUT="$(readlink -m -- "${FACTORY38_PRIVATE_OUTPUT}")" ||
		die "Factory private output path cannot be canonicalized"
	factory38_private_parent="$(dirname -- "${FACTORY38_PRIVATE_OUTPUT}")"
	FACTORY38_PRIVATE_PARENT="${factory38_private_parent}"
	[ -d "${factory38_private_parent}" ] && \
		[ ! -L "${factory38_private_parent}" ] ||
		die "Factory private output parent must be an existing real directory: ${factory38_private_parent}"
	[ "$(stat -c '%a' "${factory38_private_parent}")" = 700 ] || \
		die "Factory private output parent must have mode 700: ${factory38_private_parent}"
	[ "$(stat -c '%u' "${factory38_private_parent}")" = "$(id -u)" ] || \
		die "Factory private output parent must be owned by the build user: ${factory38_private_parent}"
	FACTORY38_PRIVATE_PARENT_IDENTITY="$(stat -c '%d:%i' "${factory38_private_parent}")"
	case "${FACTORY38_PRIVATE_OUTPUT}" in
		/|"${SCRIPT_DIR}"|"${SCRIPT_DIR}"/*|"${OPENWRT_DIR}"|"${OPENWRT_DIR}"/*|\
		"${LOG_DIR}"|"${LOG_DIR}"/*|"${OUTPUT_DIR}"|"${OUTPUT_DIR}"/*)
			die "Factory private output must be outside source, build, log, and public output trees"
			;;
	esac
	[ ! -e "${FACTORY38_PRIVATE_OUTPUT}" ] && \
		[ ! -L "${FACTORY38_PRIVATE_OUTPUT}" ] ||
		die "Factory private output already exists: ${FACTORY38_PRIVATE_OUTPUT}"
	FACTORY38_WORK_DIR="${factory38_private_parent}/.factory38-device-bundle-${RUN_ID}.$$"
	[ ! -e "${FACTORY38_WORK_DIR}" ] && [ ! -L "${FACTORY38_WORK_DIR}" ] ||
		die "Factory private staging path already exists: ${FACTORY38_WORK_DIR}"
fi
resolve_browser_runtime

mkdir -p "${LOG_DIR}" "${OUTPUT_DIR}" "${RELEASES_DIR}"
if [ "${SOURCE_TEST_ONLY}" = 0 ] || [ -n "${RESCUE_REAL_EVIDENCE}" ]; then
	validate_rescue_real_evidence
fi
exec {LOCK_FD}>"${LOCK_FILE}"
flock -n "${LOCK_FD}" || die "Another CR6608 build holds ${LOCK_FILE}"

recreate_link() {
	local root="$1"
	local relative_path="$2"
	local target="$3"
	local path="${root}/${relative_path}"
	[ -d "$(dirname "${path}")" ] || die "Symlink parent missing: ${relative_path}"
	if [ -L "${path}" ]; then
		[ "$(readlink "${path}")" = "${target}" ] || \
			die "Refusing to replace wrong overlay symlink: ${relative_path}"
		return 0
	fi
	if [ -e "${path}" ] && [ ! -L "${path}" ]; then
		# Windows checkouts without symlink support materialize a link as a
		# tiny regular file containing only its target.
		[ -f "${path}" ] && [ "$(cat "${path}")" = "${target}" ] || \
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

remove_stale_bootstrap_placeholders() {
	local root="$1"
	local relative_path path

	for relative_path in \
		usr/share/ucode/luci/template/themes/bootstrap \
		www/luci-static/bootstrap; do
		path="${root}/${relative_path}"
		[ ! -e "${path}" ] && [ ! -L "${path}" ] && continue
		[ -f "${path}" ] && [ ! -L "${path}" ] && \
			[ "$(cat "${path}")" = bootstrap ] || \
			die "Refusing to remove package-owned overlay path: ${relative_path}"
		rm -f -- "${path}"
	done
}

recreate_required_links() {
	local root="$1"
	remove_stale_bootstrap_placeholders "${root}"
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

generate_factory38_bundle() {
	local original candidate original_block candidate_block manifest readme
	[ -d "${FACTORY38_PRIVATE_PARENT}" ] && [ ! -L "${FACTORY38_PRIVATE_PARENT}" ] && \
		[ "$(stat -c '%d:%i' "${FACTORY38_PRIVATE_PARENT}")" = \
			"${FACTORY38_PRIVATE_PARENT_IDENTITY}" ] && \
		[ "$(stat -c '%a' "${FACTORY38_PRIVATE_PARENT}")" = 700 ] && \
		[ "$(stat -c '%u' "${FACTORY38_PRIVATE_PARENT}")" = "$(id -u)" ] || \
		die 'Factory-38 private output parent changed before bundle generation'
	[ ! -e "${FACTORY38_WORK_DIR}" ] ||
		die "Factory-38 work directory already exists: ${FACTORY38_WORK_DIR}"
	# Track the exact not-yet-created path before mkdir. Bash defers trapped
	# signals until mkdir returns, so cleanup can remove a signal-window empty
	# directory even before its inode is recorded.
	FACTORY38_BUNDLE_DIR="${FACTORY38_WORK_DIR}"
	mkdir -m 0700 -- "${FACTORY38_WORK_DIR}"
	FACTORY38_WORK_IDENTITY="$(stat -c '%d:%i' "${FACTORY38_WORK_DIR}")"
	original="${FACTORY38_WORK_DIR}/factory-original.device-private.bin"
	candidate="${FACTORY38_WORK_DIR}/factory-38.device-private.bin"
	original_block="${FACTORY38_WORK_DIR}/factory-original.block0.device-private.bin"
	candidate_block="${FACTORY38_WORK_DIR}/factory-38.block0.device-private.bin"
	manifest="${FACTORY38_WORK_DIR}/factory-38.manifest.json"
	readme="${FACTORY38_WORK_DIR}/README-DEVICE-PRIVATE.txt"

	install -m 0600 -- "${FACTORY38_SOURCE}" "${original}"
	python3 -I -B "${SRC_FACTORY38_BUILDER}" "${original}" "${candidate}" \
		--block0 "${candidate_block}" --manifest "${manifest}"
	dd if="${original}" of="${original_block}" bs=131072 count=1 status=none
	chmod 0600 -- "${original_block}"

	[ "$(sha256sum "${original}" | awk '{print $1}')" = "${FACTORY38_ORIGINAL_SHA256}" ] ||
		die 'Factory-38 bundled original hash mismatch'
	[ "$(sha256sum "${original_block}" | awk '{print $1}')" = "${FACTORY38_ORIGINAL_BLOCK0_SHA256}" ] ||
		die 'Factory-38 bundled original block-0 hash mismatch'
	[ "$(sha256sum "${candidate}" | awk '{print $1}')" = "${FACTORY38_CANDIDATE_SHA256}" ] ||
		die 'Factory-38 candidate hash mismatch'
	[ "$(sha256sum "${candidate_block}" | awk '{print $1}')" = "${FACTORY38_CANDIDATE_BLOCK0_SHA256}" ] ||
		die 'Factory-38 candidate block-0 hash mismatch'
	python3 -I -B - "${manifest}" <<'PY' || \
		die 'Factory-38 generated manifest validation failed'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))

def require(condition, message):
    if not condition:
        raise SystemExit(f"Factory-38 manifest validation failed: {message}")

require(manifest.get("schema") == "cr6608-factory38-offline-artifact", "schema")
require(manifest.get("schema_version") == 1, "schema_version")
require(manifest.get("source_sha256") == "aca3a3b012d96972466e7492e150bb2e00ba24f9f43201912db0223a32c98439", "source_sha256")
require(manifest.get("source_crc32") == "963cdfeb", "source_crc32")
require(manifest.get("output_sha256") == "b6a775087df306c21c70c29520c27fd5ea3e62dcfb8a945b340304895b038eb0", "output_sha256")
require(manifest.get("output_crc32") == "60048964", "output_crc32")
eraseblock0 = manifest.get("eraseblock0")
require(isinstance(eraseblock0, dict), "eraseblock0")
require(eraseblock0.get("source_sha256") == "b72eca62ecbaff9a93176ec5e9912e2ee9d6404c1c9f6005f4e8b66bc9bde224", "eraseblock0.source_sha256")
require(eraseblock0.get("source_crc32") == "73ba4c38", "eraseblock0.source_crc32")
require(eraseblock0.get("output_sha256") == "950b682023077bab5e2e35212e77b7e8d6bcf00f2249f922d38bdad0bed66aab", "eraseblock0.output_sha256")
require(eraseblock0.get("output_crc32") == "71e2a6ca", "eraseblock0.output_crc32")
require(manifest.get("changed_byte_count") == 36, "changed_byte_count")
coverage = manifest.get("channel_group_coverage")
require(isinstance(coverage, dict), "channel_group_coverage")
require(coverage.get("chain_count") == 4, "channel_group_coverage.chain_count")
require(coverage.get("all_supported_channels_targeted") is True, "channel_group_coverage.all_supported_channels_targeted")
coverage_2g = coverage.get("2g")
coverage_5g = coverage.get("5g")
require(isinstance(coverage_2g, dict), "channel_group_coverage.2g")
require(isinstance(coverage_5g, dict), "channel_group_coverage.5g")
require(coverage_2g.get("group_count") == 1, "channel_group_coverage.2g.group_count")
require(coverage_2g.get("groups") == [0], "channel_group_coverage.2g.groups")
require(coverage_2g.get("all_supported_channels_targeted") is True, "channel_group_coverage.2g.all_supported_channels_targeted")
require(coverage_5g.get("group_count") == 8, "channel_group_coverage.5g.group_count")
require(coverage_5g.get("groups") == list(range(8)), "channel_group_coverage.5g.groups")
require(coverage_5g.get("all_supported_channels_targeted") is True, "channel_group_coverage.5g.all_supported_channels_targeted")
diff = manifest.get("diff")
require(isinstance(diff, dict) and diff.get("exact_declared_offsets") is True, "diff.exact_declared_offsets")
for key in ("source", "output", "manifest"):
    value = manifest.get(key)
    require(isinstance(value, str) and pathlib.Path(value).name == value, key)
value = eraseblock0.get("output")
require(isinstance(value, str) and pathlib.Path(value).name == value, "eraseblock0.output")
PY

	printf '%s\n' \
		'PRIVATE DEVICE-SPECIFIC CR6608 FACTORY BUNDLE - DO NOT DISTRIBUTE.' \
		'Never write this bundle automatically or to another router.' \
		'Boot only the gated maintenance initramfs in RAM; never flash a maintenance sysupgrade or firmware image.' \
		'Use the exact confirmation token, verified wired SSH, and proven COM8/PB-Boot recovery.' \
		'After a successful write, reboot immediately into the normal read-only-Factory image before enabling Wi-Fi.' \
		> "${readme}"
	chmod 0600 -- "${readme}"
}

verify_factory38_bundle_exact_file_set() {
	local bundle_dir="${1:-}"
	local file_name file_marks unexpected_entry
	local expected_files=(
		factory-original.device-private.bin
		factory-38.device-private.bin
		factory-original.block0.device-private.bin
		factory-38.block0.device-private.bin
		factory-38.manifest.json
		README-DEVICE-PRIVATE.txt
		MAINTENANCE-IMAGE-BINDING.txt
		SHA256SUMS
	)
	[ -n "${bundle_dir}" ] && [ -d "${bundle_dir}" ] && [ ! -L "${bundle_dir}" ] || \
		die 'Factory-38 private bundle directory is unavailable for exact-set verification'
	for file_name in "${expected_files[@]}"; do
		[ -f "${bundle_dir}/${file_name}" ] && [ ! -L "${bundle_dir}/${file_name}" ] || \
			die "Factory-38 private bundle is missing exact regular file: ${file_name}"
	done
	if ! file_marks="$(find "${bundle_dir}" -mindepth 1 -maxdepth 1 -type f -printf x)"; then
		die 'Factory-38 private bundle exact file-count scan failed'
	fi
	[ "${#file_marks}" = "${#expected_files[@]}" ] || \
		die 'Factory-38 private bundle exact file set has an unexpected count'
	if ! unexpected_entry="$(find "${bundle_dir}" -mindepth 1 -maxdepth 1 \
			! -type f -printf x -quit)"; then
		die 'Factory-38 private bundle exact entry-type scan failed'
	fi
	[ -z "${unexpected_entry}" ] || \
		die 'Factory-38 private bundle exact file set contains a non-regular entry'
}

verify_factory38_bound_checksum_manifest() {
	local bundle_dir="${1:-}"
	local checksum_line actual_sha256
	[ -n "${FACTORY38_BOUND_SHA256SUMS_SHA256}" ] || \
		die 'Factory-38 trusted checksum-manifest hash is unavailable'
	[ -f "${bundle_dir}/SHA256SUMS" ] && [ ! -L "${bundle_dir}/SHA256SUMS" ] || \
		die 'Factory-38 checksum manifest is unavailable'
	if ! checksum_line="$(sha256sum -- "${bundle_dir}/SHA256SUMS")"; then
		die 'Factory-38 checksum-manifest hash calculation failed'
	fi
	actual_sha256="${checksum_line%% *}"
	[ -n "${actual_sha256}" ] && \
		[ "${actual_sha256}" = "${FACTORY38_BOUND_SHA256SUMS_SHA256}" ] || \
		die 'Factory-38 checksum manifest changed after trusted binding'
}

bind_factory38_bundle_to_maintenance_image() {
	local image="$1"
	local manifest readme binding image_sha inspector_sha inspection_sha package_manifest_sha
	local checksum_line checksum_manifest_sha256 publication_root
	[ "${FACTORY38_BUNDLE_ENABLED}" = 1 ] || return 0
	[ "${FACTORY38_BUILD_MODE}" = maintenance ] || \
		die 'Refusing to bind a Factory-38 bundle outside maintenance mode'
	[ -d "${FACTORY38_BUNDLE_DIR}" ] && [ ! -L "${FACTORY38_BUNDLE_DIR}" ] && \
		[ "$(stat -c '%d:%i' "${FACTORY38_BUNDLE_DIR}")" = "${FACTORY38_WORK_IDENTITY}" ] || \
		die 'Factory-38 private bundle staging is unavailable for binding'
	[ -f "${image}" ] && [ ! -L "${image}" ] && [ -s "${image}" ] || \
		die 'Inspected maintenance initramfs is unavailable for private binding'
	[ -s "${INSPECTION_LOG}" ] || die 'Inspection log is unavailable for private binding'
	[ -s "${package_manifest}" ] || die 'Package manifest is unavailable for private binding'
	if ! publication_root="$(dirname -- "${image}")"; then
		die 'Maintenance publication root could not be resolved for private binding'
	fi
	verify_inspection_attestation_unchanged "${publication_root}"
	manifest="${FACTORY38_BUNDLE_DIR}/factory-38.manifest.json"
	readme="${FACTORY38_BUNDLE_DIR}/README-DEVICE-PRIVATE.txt"
	binding="${FACTORY38_BUNDLE_DIR}/MAINTENANCE-IMAGE-BINDING.txt"
	image_sha="$(sha256sum "${image}" | awk '{print $1}')"
	inspector_sha="${INSPECTOR_EXECUTED_SHA256}"
	inspection_sha="${INSPECTION_LOG_VERIFIED_SHA256}"
	package_manifest_sha="$(sha256sum "${package_manifest}" | awk '{print $1}')"

	python3 -I -B - "${manifest}" "${KIT_HEAD_COMMIT}" "${OPENWRT_COMMIT}" \
		"${INITRAMFS_IMAGE}" "${image_sha}" "${inspector_sha}" \
		"${inspection_sha}" "${package_manifest_sha}" <<'PY' || \
		die 'Factory-38 maintenance binding could not be written'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if "maintenance_binding" in data:
    raise SystemExit("Factory-38 manifest already has a maintenance binding")
data["maintenance_binding"] = {
    "factory38_build_mode": "maintenance",
    "source_kit_commit": sys.argv[2],
    "openwrt_commit": sys.argv[3],
    "published_initramfs": sys.argv[4],
    "maintenance_initramfs_sha256": sys.argv[5],
    "inspector_sha256": sys.argv[6],
    "inspection_log_sha256": sys.argv[7],
    "package_manifest_sha256": sys.argv[8],
    "image_integrity_gate_status": "pass",
    "release_gate_status": "blocked_pending_router_runtime_and_external_rf_verification",
}
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
	printf '%s\n' \
		'factory38_binding_schema=cr6608-factory38-maintenance-image-v1' \
		'factory38_build_mode=maintenance' \
		"source_kit_commit=${KIT_HEAD_COMMIT}" \
		"openwrt_commit=${OPENWRT_COMMIT}" \
		"published_initramfs=${INITRAMFS_IMAGE}" \
		"maintenance_initramfs_sha256=${image_sha}" \
		"inspector_sha256=${inspector_sha}" \
		"inspection_log_sha256=${inspection_sha}" \
		"package_manifest_sha256=${package_manifest_sha}" \
		'image_integrity_gate_status=pass' \
		'release_gate_status=blocked_pending_router_runtime_and_external_rf_verification' \
		> "${binding}"
	printf '\n%s\n' \
		'MAINTENANCE IMAGE BINDING:' \
		"Source kit commit: ${KIT_HEAD_COMMIT}" \
		"OpenWrt commit: ${OPENWRT_COMMIT}" \
		"RAM-only image: ${INITRAMFS_IMAGE}" \
		"RAM-only image SHA256: ${image_sha}" \
		"Inspection log SHA256: ${inspection_sha}" \
		'Release remains blocked until router runtime and independent RF verification pass.' \
		>> "${readme}"
	chmod 0600 -- "${manifest}" "${readme}" "${binding}"
	(
		cd "${FACTORY38_BUNDLE_DIR}" || exit 1
		find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
			LC_ALL=C sort -z | xargs -0 sha256sum -- > SHA256SUMS || exit 1
		chmod 0600 -- SHA256SUMS || exit 1
		sha256sum -c SHA256SUMS || exit 1
	) || die 'Factory-38 bound private checksum generation or verification failed'
	verify_factory38_bundle_exact_file_set "${FACTORY38_BUNDLE_DIR}"
	if ! checksum_line="$(sha256sum -- "${FACTORY38_BUNDLE_DIR}/SHA256SUMS")"; then
		die 'Factory-38 trusted checksum-manifest hash could not be captured'
	fi
	checksum_manifest_sha256="${checksum_line%% *}"
	[[ "${checksum_manifest_sha256}" =~ ^[0-9a-f]{64}$ ]] || \
		die 'Factory-38 trusted checksum-manifest hash is malformed'
	FACTORY38_BOUND_SHA256SUMS_SHA256="${checksum_manifest_sha256}"
	FACTORY38_BOUND_INITRAMFS_SHA256="${image_sha}"
	FACTORY38_BOUND_INSPECTOR_SHA256="${inspector_sha}"
	FACTORY38_BOUND_INSPECTION_SHA256="${inspection_sha}"
	FACTORY38_BOUND_PACKAGE_MANIFEST_SHA256="${package_manifest_sha}"
	ok 'device-private Factory-38 bundle bound to the inspected maintenance initramfs'
}

verify_factory38_bundle_binding_to_publication() {
	local publication_root="${1:-${PUBLISH_DIR}}"
	local public_initramfs="${publication_root}/${INITRAMFS_IMAGE}"
	local manifest="${FACTORY38_BUNDLE_DIR}/factory-38.manifest.json"
	local binding="${FACTORY38_BUNDLE_DIR}/MAINTENANCE-IMAGE-BINDING.txt"
	[ "${FACTORY38_BUNDLE_ENABLED}" = 1 ] || return 0
	verify_inspection_attestation_unchanged "${publication_root}"
	[ -n "${FACTORY38_BOUND_INITRAMFS_SHA256}" ] && \
	[ -n "${FACTORY38_BOUND_INSPECTOR_SHA256}" ] && \
		[ -n "${FACTORY38_BOUND_INSPECTION_SHA256}" ] && \
		[ -n "${FACTORY38_BOUND_PACKAGE_MANIFEST_SHA256}" ] && \
		[ -n "${FACTORY38_BOUND_SHA256SUMS_SHA256}" ] || \
		die 'Factory-38 maintenance binding state is incomplete'
	verify_factory38_bundle_exact_file_set "${FACTORY38_BUNDLE_DIR}"
	verify_factory38_bound_checksum_manifest "${FACTORY38_BUNDLE_DIR}"
	[ "$(sha256sum "${public_initramfs}" | awk '{print $1}')" = \
		"${FACTORY38_BOUND_INITRAMFS_SHA256}" ] || \
		die 'Published maintenance initramfs changed after private binding'
	[ "$(sha256sum "${INSPECTOR}" | awk '{print $1}')" = \
		"${FACTORY38_BOUND_INSPECTOR_SHA256}" ] || \
		die 'Image inspector changed after private binding'
	[ "$(sha256sum "${publication_root}/prepublish-inspection.txt" | awk '{print $1}')" = \
		"${FACTORY38_BOUND_INSPECTION_SHA256}" ] || \
		die 'Published inspection log differs from the private binding'
	[ "$(sha256sum "${publication_root}/openwrt-package-manifest.txt" | awk '{print $1}')" = \
		"${FACTORY38_BOUND_PACKAGE_MANIFEST_SHA256}" ] || \
		die 'Published package manifest differs from the private binding'
	python3 -I -B - "${manifest}" "${KIT_HEAD_COMMIT}" "${OPENWRT_COMMIT}" \
		"${INITRAMFS_IMAGE}" "${FACTORY38_BOUND_INITRAMFS_SHA256}" \
		"${FACTORY38_BOUND_INSPECTOR_SHA256}" \
		"${FACTORY38_BOUND_INSPECTION_SHA256}" \
		"${FACTORY38_BOUND_PACKAGE_MANIFEST_SHA256}" <<'PY' || \
		die 'Factory-38 trusted maintenance manifest binding verification failed'
import json
import pathlib
import sys

binding = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")).get(
    "maintenance_binding"
)
expected = {
    "factory38_build_mode": "maintenance",
    "source_kit_commit": sys.argv[2],
    "openwrt_commit": sys.argv[3],
    "published_initramfs": sys.argv[4],
    "maintenance_initramfs_sha256": sys.argv[5],
    "inspector_sha256": sys.argv[6],
    "inspection_log_sha256": sys.argv[7],
    "package_manifest_sha256": sys.argv[8],
    "image_integrity_gate_status": "pass",
    "release_gate_status": "blocked_pending_router_runtime_and_external_rf_verification",
}
if binding != expected:
    raise SystemExit("Factory-38 maintenance manifest binding changed before publication")
PY
	grep -Fqx "maintenance_initramfs_sha256=${FACTORY38_BOUND_INITRAMFS_SHA256}" \
		"${binding}" || die 'Factory-38 text binding lost the maintenance image hash'
	(
		cd "${FACTORY38_BUNDLE_DIR}" || exit 1
		sha256sum -c SHA256SUMS || exit 1
	) || die 'Factory-38 trusted private checksum verification failed'
	ok 'device-private Factory-38 binding matches the staged public maintenance release'
}

publish_factory38_bundle() {
	local release_root="${1:-}"
	local source_identity output_identity unsupported_entry unsafe_mode_entry
	[ "${FACTORY38_BUNDLE_ENABLED}" = 1 ] || return 0
	[ -n "${release_root}" ] || \
		die 'Verified public maintenance release path is required for private publication'
	[ "${FACTORY38_BUILD_MODE}" = maintenance ] || \
		die 'Refusing to publish a Factory-38 bundle outside maintenance mode'
	[ -d "${FACTORY38_BUNDLE_DIR}" ] && [ ! -L "${FACTORY38_BUNDLE_DIR}" ] && \
		[ "$(stat -c '%d:%i' "${FACTORY38_BUNDLE_DIR}")" = "${FACTORY38_WORK_IDENTITY}" ] ||
		die "verified Factory-38 private bundle is unavailable"
	[ "$(dirname -- "${FACTORY38_PRIVATE_OUTPUT}")" = "${FACTORY38_PRIVATE_PARENT}" ] && \
		[ -d "${FACTORY38_PRIVATE_PARENT}" ] && [ ! -L "${FACTORY38_PRIVATE_PARENT}" ] && \
		[ "$(stat -c '%d:%i' "${FACTORY38_PRIVATE_PARENT}")" = \
			"${FACTORY38_PRIVATE_PARENT_IDENTITY}" ] && \
		[ "$(stat -c '%a' "${FACTORY38_PRIVATE_PARENT}")" = 700 ] && \
		[ "$(stat -c '%u' "${FACTORY38_PRIVATE_PARENT}")" = "$(id -u)" ] || \
		die 'Factory-38 private output parent changed before publication'
	[ ! -e "${FACTORY38_PRIVATE_OUTPUT}" ] && \
		[ ! -L "${FACTORY38_PRIVATE_OUTPUT}" ] ||
		die "Factory-38 private output already exists: ${FACTORY38_PRIVATE_OUTPUT}"
	[ "$(stat -c '%a' "${FACTORY38_BUNDLE_DIR}")" = 700 ] || \
		die 'Factory-38 private bundle directory mode is not 700'
	if ! unsupported_entry="$(find "${FACTORY38_BUNDLE_DIR}" -mindepth 1 -maxdepth 1 \
			! -type f -printf x -quit)"; then
		die 'Factory-38 private bundle entry-type scan failed before publication'
	fi
	[ -z "${unsupported_entry}" ] || \
		die 'Factory-38 private bundle contains an unsupported entry'
	if ! unsafe_mode_entry="$(find "${FACTORY38_BUNDLE_DIR}" -mindepth 1 -maxdepth 1 \
			-type f ! -perm 0600 -printf x -quit)"; then
		die 'Factory-38 private bundle mode scan failed before publication'
	fi
	[ -z "${unsafe_mode_entry}" ] || \
		die 'Factory-38 private bundle contains a file with an unsafe mode'
	verify_factory38_bundle_exact_file_set "${FACTORY38_BUNDLE_DIR}"
	verify_factory38_bound_checksum_manifest "${FACTORY38_BUNDLE_DIR}"
	(
		cd "${FACTORY38_BUNDLE_DIR}" || exit 1
		sha256sum -c SHA256SUMS || exit 1
	) || die 'Factory-38 private checksum verification failed before publication'
	# Recheck the private binding against the final public release immediately
	# before the no-clobber rename; SHA256SUMS alone is not a trusted anchor.
	verify_factory38_bundle_binding_to_publication "${release_root}"
	if ! source_identity="$(stat -c '%d:%i' "${FACTORY38_BUNDLE_DIR}")"; then
		die 'Factory-38 private source identity lookup failed before publication'
	fi
	[ -n "${source_identity}" ] || \
		die 'Factory-38 private source identity is empty before publication'
	FACTORY38_PENDING_OUTPUT="${FACTORY38_PRIVATE_OUTPUT}"
	FACTORY38_PENDING_OUTPUT_IDENTITY="${source_identity}"
	# -n closes the check/rename race: an independently created destination is
	# never replaced, while -T prevents accidental directory nesting.
	mv -Tn -- "${FACTORY38_BUNDLE_DIR}" "${FACTORY38_PRIVATE_OUTPUT}"
	[ ! -e "${FACTORY38_BUNDLE_DIR}" ] && [ ! -L "${FACTORY38_BUNDLE_DIR}" ] || \
		die 'Factory-38 private publication lost the no-clobber race'
	[ -d "${FACTORY38_PRIVATE_OUTPUT}" ] && [ ! -L "${FACTORY38_PRIVATE_OUTPUT}" ] || \
		die 'Factory-38 private output is absent after atomic publication'
	if ! output_identity="$(stat -c '%d:%i' "${FACTORY38_PRIVATE_OUTPUT}")"; then
		die 'Factory-38 private output identity lookup failed after publication'
	fi
	[ -n "${output_identity}" ] || \
		die 'Factory-38 private output identity is empty after publication'
	[ "${output_identity}" = "${source_identity}" ] || \
		die 'Factory-38 private output identity changed during publication'
	verify_factory38_bundle_exact_file_set "${FACTORY38_PRIVATE_OUTPUT}"
	verify_factory38_bound_checksum_manifest "${FACTORY38_PRIVATE_OUTPUT}"
	(
		cd "${FACTORY38_PRIVATE_OUTPUT}" || exit 1
		sha256sum -c SHA256SUMS || exit 1
	) || die 'Factory-38 private checksum verification failed after publication'
	FACTORY38_BUNDLE_DIR=""
	FACTORY38_PENDING_OUTPUT=""
	FACTORY38_PENDING_OUTPUT_IDENTITY=""
	ok "device-private Factory-38 bundle exported separately to ${FACTORY38_PRIVATE_OUTPUT}"
}

record_regular_input() {
	local kind="$1"
	local path="$2"
	local relative_path
	case "${path}" in
		*$'\n'*|*$'\t'*) die "Unsupported external input path characters" ;;
	esac
	case "${path}" in
		"${SCRIPT_DIR}"/*) relative_path="${path#"${SCRIPT_DIR}/"}" ;;
		"${FACTORY38_SOURCE}") relative_path="device-inputs/${path##*/}" ;;
		"${FINAL_ROOT}/device-inputs"/*) relative_path="device-inputs/${path##*/}" ;;
		"${FINAL_ROOT}/secrets"/*) relative_path="secrets/${path##*/}" ;;
		"${SRC_FW_SIGNING_KEY}") relative_path="secrets/${path##*/}" ;;
		"${SRC_APK_SIGNING_KEY}") relative_path="secrets/${path##*/}" ;;
		*) die "Input is outside the final source and secrets roots: ${path}" ;;
	esac
	case "${relative_path}" in
		*$'\n'*|*$'\t'*) die "Unsupported external input manifest path characters" ;;
	esac
	printf '%s\t%s\t%s\t%s\n' \
		"${kind}" "$(stat -c '%a' "${path}")" \
		"$(sha256sum "${path}" | awk '{print $1}')" "${relative_path}"
}

write_input_manifest() {
	local output="$1"
	local temporary="${output}.tmp.$$"
	if [ "${SOURCE_TRUST_GATE_STATUS}" = pass-external-expected-values ]; then
		verify_trusted_source_bundle_unchanged
	fi
	if [ "${RESCUE_REAL_EVIDENCE_GATE_STATUS}" = pass-root-owned-real-netns-v1 ]; then
		verify_rescue_real_evidence_unchanged
	fi
	{
		printf 'kind\tmode\tsha256_or_target\tpath\n'
		printf 'openwrt-origin\t-\t-\t%s\n' "${OPENWRT_URL}"
		printf 'openwrt-commit\t-\t-\t%s\n' "${OPENWRT_COMMIT}"
		printf 'openwrt-tag-object\t-\t-\t%s\n' "${OPENWRT_TAG_OBJECT}"
		printf 'openwrt-release-signer\t-\t-\t%s\n' "${OPENWRT_RELEASE_SIGNER}"
		printf 'offline-pinned-sources\t-\t-\t%s\n' "${OFFLINE_PINNED_SOURCES}"
		printf 'build-profile\t-\t-\t%s\n' "${BUILD_PROFILE}"
		printf 'source-trust-gate\t-\t-\t%s\n' "${SOURCE_TRUST_GATE_STATUS}"
		if [ "${SOURCE_TRUST_GATE_STATUS}" = pass-external-expected-values ]; then
			printf 'trusted-source-bundle\t-\t%s\toperator-out-of-band/source-bundle\n' \
				"${TRUSTED_SOURCE_BUNDLE_SHA256}"
			printf 'trusted-source-original-commit\t-\t%s\toperator-out-of-band/original-commit\n' \
				"${EXPECTED_ORIGINAL_COMMIT}"
			printf 'trusted-source-original-tree\t-\t%s\toperator-out-of-band/original-tree\n' \
				"${EXPECTED_ORIGINAL_TREE}"
			printf 'trusted-source-container-commit\t-\t%s\toperator-out-of-band/container-commit\n' \
				"${EXPECTED_CONTAINER_COMMIT}"
			printf 'trusted-source-container-tree\t-\t%s\toperator-out-of-band/container-tree\n' \
				"${EXPECTED_CONTAINER_TREE}"
			printf 'trusted-source-payload-manifest\t-\t%s\toperator-out-of-band/payload-manifest\n' \
				"${EXPECTED_PAYLOAD_MANIFEST_SHA256}"
		fi
		printf 'rescue-real-netns-gate\t-\t-\t%s\n' \
			"${RESCUE_REAL_EVIDENCE_GATE_STATUS}"
		if [ "${RESCUE_REAL_EVIDENCE_GATE_STATUS}" = pass-root-owned-real-netns-v1 ]; then
			printf 'rescue-real-netns-evidence\t444\t%s\toperator-out-of-band/rescue-real-netns-evidence-v1\n' \
				"${RESCUE_REAL_EVIDENCE_SHA256}"
		fi
		while read -r feed expected; do
			printf 'feed-commit\t-\t%s\t%s\n' "${expected}" "${feed}"
		done < <(feed_commit_matrix)
		while read -r feed expected archive_sha256 expected_origin; do
			printf 'feed-cache-archive\t-\t%s\toperator-local-cache/feed-%s.tar.gz\n' \
				"${archive_sha256}" "${feed}"
			printf 'feed-origin\t-\t-\t%s=%s\n' "${feed}" "${expected_origin}"
		done < <(feed_source_matrix)
		printf 'generated-file\t644\t%s\t%s\n' \
			"$(printf '%s\n' "${BUILD_TIME}" | sha256sum | awk '{print $1}')" \
			'files/etc/smartap-build-time'
		printf 'generated-file\t644\t%s\t%s\n' \
			"$(printf '%s\n' "${BUILD_EPOCH}" | sha256sum | awk '{print $1}')" \
		'files/etc/smartap-time-anchor'
		record_regular_input build-script "${SCRIPT_DIR}/build.sh"
		record_regular_input inspection-script "${INSPECTOR}"
		record_regular_input source-tool "${FEED_CACHE_TOOL}"
		record_regular_input source-tool "${OPENWRT_TAG_GATE}"
		record_regular_input source-trust-key "${OPENWRT_RELEASE_KEY}"
		record_regular_input source-test "${OFFLINE_SOURCE_FALLBACK_TEST}"
		record_regular_input source-test "${VLAN_TEST}"
		record_regular_input source-test "${NETWORK_SAFETY_TEST}"
		record_regular_input source-test "${INITRAMFS_UBI_DETACH_TEST}"
		record_regular_input source-test "${SAFE_APPLY_TEST}"
		record_regular_input source-test "${SAFE_APPLY_RUNTIME_TEST}"
		record_regular_input source-test "${SAFE_WIFI_RELOAD_TEST}"
		record_regular_input source-test "${QUICKSETTINGS_CONTRACT_TEST}"
		record_regular_input source-test "${SMARTAP_QOS_TEST}"
		record_regular_input source-test "${DASHCTL_MAC_QOS_TRANSACTION_TEST}"
		record_regular_input source-test "${IPV6_DUALSTACK_TEST}"
		record_regular_input source-test "${IPV6_UPGRADE_MIGRATION_TEST}"
		record_regular_input source-test "${IPV4_ONLY_RUNTIME_TEST}"
		record_regular_input source-test "${MAC_IDENTITY_TEST}"
		record_regular_input source-test "${FLEET_MAC_AUDIT_TEST}"
		record_regular_input source-test "${GUEST_NETWORK_TEST}"
		record_regular_input source-test "${DASHBOARD_ZERO_RETENTION_TEST}"
		record_regular_input source-test "${MANAGEMENT_GUARD_TEST}"
		record_regular_input source-test "${RESCUE_GUARD_TEST}"
		record_regular_input source-test "${DASHBOARD_CACHE_RUNTIME_TEST}"
		record_regular_input source-test "${DASHBOARD_LIVE_NO_CACHE_TEST}"
		record_regular_input source-test "${DASHBOARD_REQUEST_COORDINATION_TEST}"
		record_regular_input source-test "${CONTROL_RECOVERY_TEST}"
		record_regular_input source-test "${DASHCTL_JSON_BUILDERS_TEST}"
		record_regular_input source-test "${JSON_CHARSET_TEST}"
		record_regular_input source-test "${PACKAGE_MANAGER_RUNTIME_TEST}"
		record_regular_input source-test "${WIZARD_CHANNEL_OPTIONS_TEST}"
		record_regular_input source-test "${DASHCTL_RUN_LIMIT_RUNTIME_TEST}"
		record_regular_input source-test "${SQM_SAFETY_TEST}"
		record_regular_input source-test "${ROAMING_STEERING_TEST}"
		record_regular_input source-test "${UCI_SYNC_RUNTIME_TEST}"
		record_regular_input source-test "${DASHCTL_WIFI_APPLY_TEST}"
		record_regular_input source-test "${LUCI_WIRELESS_TXPOWER_TEST}"
		record_regular_input source-test "${FACTORY38_BUILDER_TEST}"
		record_regular_input source-test "${ALL_CHANNEL_38_TEST}"
		record_regular_input source-test "${FACTORY38_STAGE_GUARD_TEST}"
		record_regular_input source-test "${FACTORY38_STAGE_MOCK_TEST}"
		record_regular_input source-maintenance-builder "${SRC_CRASHLOG_BUILDER}"
		record_regular_input source-maintenance-tool "${SRC_CRASHLOG_SANITIZER}"
		record_regular_input source-maintenance-marker "${SRC_CRASHLOG_MARKER}"
		record_regular_input source-maintenance-wifi-gate "${SRC_CRASHLOG_WIFI_DISABLE}"
		record_regular_input source-maintenance-document "${SRC_CRASHLOG_README}"
		record_regular_input source-maintenance-patch "${SRC_CRASHLOG_WRITE_GATE_PATCH}"
		record_regular_input source-test "${CRASHLOG_SANITIZE_MOCK_TEST}"
		record_regular_input source-test "${CRASHLOG_BUILD_CONTRACT_TEST}"
		record_regular_input source-test "${LEGACY_11B_TEST}"
		record_regular_input source-test "${COUNTRY_DOMAIN_TEST}"
		record_regular_input source-test "${AUTH_LIFECYCLE_TEST}"
		record_regular_input source-test "${AUTH_BOUNDED_BLOCKING_TEST}"
		record_regular_input source-test "${TIME_ANCHOR_RUNTIME_TEST}"
		record_regular_input source-test "${RETAIL_SECURITY_TEST}"
		record_regular_input source-test "${RETAIL_RADIO_POLICY_TEST}"
		record_regular_input source-test "${RETAIL_BUILD_PROFILE_TEST}"
		record_regular_input source-tool "${SRC_RETAIL_COMMISSIONING_STAGE}"
		record_regular_input source-tool "${FLEET_MAC_AUDIT_TOOL}"
		record_regular_input source-test "${RETAIL_COMMISSIONING_TEST}"
		if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
			record_regular_input device-public-key "${RETAIL_COMMISSIONING_KEY}"
		fi
		record_regular_input source-test "${UL_LAB_BUILD_PROFILE_TEST}"
		record_regular_input source-profile-applier "${SRC_PROFILE_APPLIER}"
		record_regular_input source-test "${SECURE_CONSOLE_TEST}"
		record_regular_input source-kit-tool "${SOURCE_KIT_TOOL}"
		record_regular_input source-test "${SOURCE_KIT_TEST}"
		record_regular_input source-generator "${SMART_AP_BRAND_GENERATOR}"
		record_regular_input source-test "${SMART_AP_BRANDING_TEST}"
		record_regular_input source-test "${LOGIN_CACHE_TEST}"
		record_regular_input source-test "${SMARTAP_ONLY_ROUTING_TEST}"
		record_regular_input source-test "${FETCH_BODY_TIMEOUT_TEST}"
		record_regular_input source-test "${UI_CONTRACT_TEST}"
		record_regular_input source-test "${UI_PASSWORD_TEST}"
		record_regular_input source-test "${PRESERVED_CONFIG_TEST}"
		record_regular_input source-test "${DSA_PORT_TEST}"
		record_regular_input source-test "${DSA_EEE_TEST}"
		record_regular_input source-test "${DASHAPI_STATUS_TEST}"
		record_regular_input source-test "${DASHAPI_RUNTIME_TEST}"
		record_regular_input source-test "${AX_FEATURE_TEST}"
		record_regular_input source-test "${UL_MURU_GUARD_RUNTIME_TEST}"
		record_regular_input source-test "${UL_MURU_VERIFIER_RUNTIME_TEST}"
		record_regular_input source-test "${UL_MURU_DEFAULTS_MIGRATION_TEST}"
		record_regular_input source-test "${UL_MURU_DEFERRED_RUNTIME_TEST}"
		record_regular_input source-test "${UL_MURU_AIRTEST_RUNTIME_TEST}"
		record_regular_input source-test "${MURU_DRIVER_PORT_TEST}"
		record_regular_input source-test "${MURU_FAULT_ATTRIBUTION_TEST}"
		record_regular_input source-test "${UL_MU_EVIDENCE_RUNTIME_TEST}"
		record_regular_input source-test "${MURU_LIVE_REFRESH_TEST}"
		record_regular_input source-test "${EASYMESH_VERIFIER_RUNTIME_TEST}"
		record_regular_input source-test "${PORT_READINESS_RUNTIME_TEST}"
		record_regular_input source-test "${PRPLMESH_ROLE_RUNTIME_TEST}"
		record_regular_input source-test "${PRPLMESH_CREDENTIAL_SYNC_TEST}"
		record_regular_input source-runtime "${PRPLMESH_CREDENTIAL_SYNC_HELPER}"
		record_regular_input source-test "${SSH_PORT_TEST}"
		record_regular_input source-test "${EXECUTABLE_FORMAT_TEST}"
		record_regular_input source-test "${TXPOWER_COLLECTOR_TEST}"
		record_regular_input source-test "${MNDP_SOURCE_TEST}"
		record_regular_input source-test "${MNDP_PACKET_TEST}"
		record_regular_input source-test "${PRIVATE_RUNTIME_TEST}"
		record_regular_input source-test-helper "${PRIVATE_RUNTIME_STAT_MOCK}"
		record_regular_input source-test "${LAN_SCAN_RENDER_TEST}"
		record_regular_input source-test "${RELEASE_PACKAGE_TEST}"
		record_regular_input source-test "${MAINTENANCE_PUBLICATION_TEST}"
		record_regular_input source-test "${LOGIN_RUNTIME_TEST}"
		record_regular_input browser-layout-test "${MOBILE_LAYOUT_TEST}"
		record_regular_input source-ui-asset "${ARGON_LOCALTIME_JS}"
		record_regular_input browser-runtime-setup "${BROWSER_SETUP_TEST}"
		record_regular_input browser-runtime-lock "${PLAYWRIGHT_PACKAGE_JSON}"
		record_regular_input browser-runtime-lock "${PLAYWRIGHT_PACKAGE_LOCK}"
		printf 'browser-runtime\t-\t%s\tplaywright-core@%s\n' \
			"$(sha256sum "${PLAYWRIGHT_CORE_DIR}/package.json" | awk '{print $1}')" \
			"${PLAYWRIGHT_EXPECTED_VERSION}"
		printf 'browser-runtime\t-\t%s\tchromium/%s\n' \
			"${CHROMIUM_SHA256}" "$(basename "${CHROMIUM_EXECUTABLE}")"
		if [ -n "${BROWSER_TEST_EVIDENCE}" ]; then
			record_regular_input browser-test-evidence "${BROWSER_TEST_EVIDENCE}"
		fi
		record_regular_input router-runtime-test "${ROUTER_QUICKSETTINGS_TEST}"
		record_regular_input router-runtime-test "${ROUTER_VLAN_ROUNDTRIP_TEST}"
		record_regular_input router-runtime-test "${ROUTER_UHTTPD_SMARTAP_TEST}"
		record_regular_input seed "${SRC_SEED}"
		while IFS= read -r -d '' path; do
			record_regular_input retail-profile-overlay "${path}"
		done < <(find "${SRC_RETAIL_PROFILE_FILES}" -type f -print0 | LC_ALL=C sort -z)
		while IFS= read -r -d '' path; do
			record_regular_input ul-lab-profile-overlay "${path}"
		done < <(find "${SRC_UL_LAB_PROFILE_FILES}" -type f -print0 | LC_ALL=C sort -z)
		while IFS= read -r -d '' path; do
			record_regular_input ul-forced-lab-profile-overlay "${path}"
		done < <(find "${SRC_UL_FORCED_LAB_PROFILE_FILES}" -type f -print0 | LC_ALL=C sort -z)
		while IFS= read -r -d '' path; do
			record_regular_input prplmesh-package "${path}"
		done < <(find "${SRC_PRPLMESH_PACKAGE}" -type f -print0 | LC_ALL=C sort -z)
		while IFS= read -r -d '' path; do
			record_regular_input mndp-package "${path}"
		done < <(find "${SRC_MNDP_PACKAGE}" -type f -print0 | LC_ALL=C sort -z)
		record_regular_input mndp-source "${SRC_MNDP_SOURCE}"
		record_regular_input factory38-builder "${SRC_FACTORY38_BUILDER}"
		record_regular_input factory38-stage "${SRC_FACTORY38_STAGE}"
		record_regular_input factory38-maintenance-marker "${SRC_FACTORY38_MARKER}"
		record_regular_input factory38-maintenance-wifi-disable "${SRC_FACTORY38_WIFI_DISABLE}"
		record_regular_input patch "${SRC_PATCH}"
		record_regular_input factory38-patch "${SRC_FACTORY38_PATCH}"
		record_regular_input firmware-eeprom-shadow-patch "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}"
		record_regular_input experimental-ul-muru-patch "${SRC_UL_MURU_PATCH}"
		record_regular_input mediatek-vendor-ul-muru-proof-patch "${SRC_UL_MURU_STOCK_POLICY_PATCH}"
		for muru_port_patch in "${SRC_MURU_PORT_PATCHES[@]}"; do
			record_regular_input mediatek-25.12-muru-port-patch "${muru_port_patch}"
		done
		record_regular_input firmware-baseline-verifier "${MURU_FIRMWARE_VERIFY}"
		record_regular_input platform-patch "${SRC_RF_DTS_PATCH}"
		if [ "${BUILD_PROFILE}" = ul-lab ] || [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
			record_regular_input ul-muru-ram-platform-patch "${SRC_UL_MURU_DTS_PATCH}"
		fi
		if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
			record_regular_input maintenance-platform-patch "${SRC_FACTORY38_WRITE_GATE_PATCH}"
		fi
		record_regular_input kernel-patch "${SRC_MAC80211_PATCH}"
		record_regular_input luci-feed-patch "${SRC_LUCI_WIRELESS_PATCH}"
		record_regular_input uhttpd-patch "${SRC_UHTTPD_PATCH}"
		record_regular_input platform-patch "${SRC_DSA_EEE_PATCH}"
		record_regular_input platform-patch "${SRC_UBI_INITRAMFS_GUARD_PATCH}"
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

write_source_manifest() {
	local root="$1"
	local output="$2"
	local temporary="${output}.tmp.$$"
	local path relative secret_path target
	{
		printf 'kind\tmode\tsha256_or_target\tpath\n'
		printf 'manifest-format\t-\tcr6608-source-v1\t-\n'
		printf 'openwrt-origin\t-\t-\t%s\n' "${OPENWRT_URL}"
		printf 'openwrt-commit\t-\t-\t%s\n' "${OPENWRT_COMMIT}"
		printf 'build-profile\t-\t-\t%s\n' "${BUILD_PROFILE}"
		while IFS= read -r -d '' path; do
			relative="${path#"${root}/"}"
			case "${relative}" in
				*$'\n'*|*$'\t'*) die "Unsupported source path characters: ${relative}" ;;
			esac
			if [ -L "${path}" ]; then
				target="$(readlink "${path}")"
				case "${target}" in
					*$'\n'*|*$'\t'*) die "Unsupported source symlink target: ${relative}" ;;
				esac
				printf 'source-symlink\t%s\t%s\t%s\n' \
					"$(stat -c '%a' "${path}")" "${target}" "${relative}"
			elif [ -f "${path}" ]; then
				printf 'source-file\t%s\t%s\t%s\n' \
					"$(stat -c '%a' "${path}")" \
					"$(sha256sum "${path}" | awk '{print $1}')" "${relative}"
			elif [ -d "${path}" ]; then
				printf 'source-directory\t%s\t-\t%s\n' \
					"$(stat -c '%a' "${path}")" "${relative}"
			else
				die "Unsupported source input type: ${relative}"
			fi
		done < <(
			find "${root}" -mindepth 1 \
				-path "${root}/.git" -prune -o \
				-path "${root}/release-evidence" -prune -o \
				-path "${root}/.mobile-layout" -prune -o \
				-path "${root}/.router-mobile-ui" -prune -o \
				-name 'inspect-image.sh.pre-*' -prune -o \
				-print0 | LC_ALL=C sort -z
		)
		if [ "${SOURCE_TEST_ONLY}" = 0 ]; then
			for secret_path in "${SRC_FW_SIGNING_KEY}" "${SRC_APK_SIGNING_KEY}"; do
				[ -f "${secret_path}" ] && [ ! -L "${secret_path}" ] || \
					die "Required private signing key is absent: ${secret_path}"
				printf 'private-signing-key\t%s\t%s\tsecrets/%s\n' \
					"$(stat -c '%a' "${secret_path}")" \
					"$(sha256sum "${secret_path}" | awk '{print $1}')" \
					"${secret_path##*/}"
			done
		fi
	} > "${temporary}"
	mv -f -- "${temporary}" "${output}"
	chmod 0644 "${output}"
}

verify_source_manifest_unchanged() {
	local reason="$1"
	local recheck
	recheck="$(mktemp "${LOG_DIR}/.source-manifest-recheck.XXXXXX")"
	write_source_manifest "${SCRIPT_DIR}" "${recheck}"
	if ! cmp -s "${SOURCE_MANIFEST}" "${recheck}"; then
		diff -u "${SOURCE_MANIFEST}" "${recheck}" >&2 || true
		rm -f -- "${recheck}"
		die "${reason}"
	fi
	rm -f -- "${recheck}"
	[ "$(sha256sum "${SOURCE_MANIFEST}" | awk '{print $1}')" = \
		"${SOURCE_MANIFEST_SHA256}" ] || die "Recorded source manifest changed after testing"
}

write_ui_evidence_hashes() {
	local output="$1"
	(
		cd "${UI_SCREENSHOT_DIR}" || exit 1
		find . -maxdepth 1 -type f -name '*.png' -print0 | \
			LC_ALL=C sort -z | xargs -0r sha256sum -- | \
			sed 's#  \./#  .mobile-layout/#'
	) > "${output}"
}

verify_ui_evidence_unchanged() {
	local reason="${1:-UI screenshot evidence changed after its browser gate}"
	local recheck
	[ -n "${UI_EVIDENCE_MANIFEST_SHA256}" ] || \
		die "UI screenshot evidence hash was not pinned"
	recheck="$(mktemp "${LOG_DIR}/.ui-screenshots-recheck.XXXXXX")"
	write_ui_evidence_hashes "${recheck}" || {
		rm -f -- "${recheck}"
		die "UI screenshot evidence could not be rehashed"
	}
	if ! cmp -s "${UI_EVIDENCE_MANIFEST}" "${recheck}"; then
		diff -u "${UI_EVIDENCE_MANIFEST}" "${recheck}" >&2 || true
		rm -f -- "${recheck}"
		die "${reason}"
	fi
	rm -f -- "${recheck}"
	[ "$(sha256sum "${UI_EVIDENCE_MANIFEST}" | awk '{print $1}')" = \
		"${UI_EVIDENCE_MANIFEST_SHA256}" ] || \
		die "Pinned UI screenshot evidence manifest changed"
}

assert_origin() {
	mapfile -t origin_urls < <(git -C "${OPENWRT_DIR}" remote get-url --all origin)
	[ "${#origin_urls[@]}" -eq 1 ] || die "OpenWrt origin must have exactly one URL"
	[ "${origin_urls[0]}" = "${OPENWRT_URL}" ] || \
		die "Unexpected OpenWrt origin: ${origin_urls[0]}"
}

verify_openwrt_source_gate() {
	local network_mode="$1" gate_output
	gate_output="$(bash "${OPENWRT_TAG_GATE}" \
		"${OPENWRT_DIR}" "${OPENWRT_URL}" "${OPENWRT_TAG}" \
		"${OPENWRT_COMMIT}" "${OPENWRT_TAG_OBJECT}" \
		"${OPENWRT_RELEASE_KEY}" "${OPENWRT_RELEASE_KEY_SHA256}" \
		"${OPENWRT_RELEASE_SIGNER}" "${network_mode}" 5 \
		/usr/bin/git /usr/bin/gpg /usr/bin/timeout)" ||
		die "OpenWrt signed release source gate failed"
	printf '%s\n' "${gate_output}"
	printf '%s\n' "${gate_output}" | grep -Fqx \
		"openwrt_source_gate=pass remote=$([ "${network_mode}" = offline-only ] && printf skipped || printf verified) local_signature=verified commit=${OPENWRT_COMMIT}" && return 0
	[ "${network_mode}" = online-fallback ] && printf '%s\n' "${gate_output}" | grep -Fqx \
		"openwrt_source_gate=pass remote=unavailable local_signature=verified commit=${OPENWRT_COMMIT}" ||
		die "OpenWrt signed release source gate returned an unexpected result"
}

feed_source_matrix() {
	cat <<'EOF'
packages 5caa62e0bc9f7fb9b0c12a23267bceb7724214dd c846b27bb1fde53ee3f06460e34e5396aaa0c90778d0e67d80f0ff11e01c234d https://git.openwrt.org/feed/packages.git
luci 128a7812f4be233c5dd7f7466f534fd888785caf 29d0b463543c14f86b51ba3774ebf5fad1ea842c36dcff7d2b7644651b58ff7f https://git.openwrt.org/project/luci.git
routing 3d7d0dc7fa43d3eb09498417407e95a6552e5312 5bec191d590b861709892a22ef1b5766c075a66087dc3a7237042d435bd376e1 https://git.openwrt.org/feed/routing.git
telephony 2618106d5846a4a542fdf5809f0d3ed228ce439b b39f2a29b8a578c0495bdc0b27921474c918cdc298ab5c4a67411c6c1e85acb9 https://git.openwrt.org/feed/telephony.git
video 094bf58da6682f895255a35a84349a79dab4bf95 3939e29b8e76e747b3c24170170bd26ede05a81f97fe81a734bfff558bc0806c https://github.com/openwrt/video.git
EOF
}

feed_commit_matrix() {
	local feed expected archive_sha256 expected_origin
	while read -r feed expected archive_sha256 expected_origin; do
		printf '%s %s\n' "${feed}" "${expected}"
	done < <(feed_source_matrix)
}

verify_feed_identity() {
	local feed="$1" expected="$2" expected_origin="$3" feed_dir
	local -a origin_urls
	feed_dir="${OPENWRT_DIR}/feeds/${feed}"
	[ -d "${feed_dir}/.git" ] && [ ! -L "${feed_dir}/.git" ] ||
		die "Prepared feed is absent or unsafe: ${feed}"
	mapfile -t origin_urls < <(git -C "${feed_dir}" remote get-url --all origin)
	[ "${#origin_urls[@]}" -eq 1 ] && [ "${origin_urls[0]}" = "${expected_origin}" ] ||
		die "Prepared feed origin mismatch: ${feed}"
	[ "$(git -C "${feed_dir}" rev-parse --verify HEAD)" = "${expected}" ] ||
		die "Prepared feed commit mismatch: ${feed}"
	git -C "${feed_dir}" cat-file -e "${expected}^{commit}" ||
		die "Prepared feed commit object is absent: ${feed}"
	[ -z "$(git -C "${feed_dir}" status --porcelain --untracked-files=all)" ] ||
		die "Prepared feed worktree is dirty: ${feed}"
}

restore_pinned_feed_cache() {
	local feed="$1" expected="$2" archive_sha256="$3" expected_origin="$4"
	local feed_root feed_dir feed_tmp archive
	feed_root="${OPENWRT_DIR}/feeds"
	feed_dir="${OPENWRT_DIR}/feeds/${feed}"
	feed_tmp="${OPENWRT_DIR}/feeds/${feed}.tmp"
	archive="${PINNED_FEED_CACHE_DIR}/feed-${feed}.tar.gz"
	case "${feed_root}" in "${OPENWRT_DIR}"/feeds) ;; *) die "Unsafe feed root: ${feed_root}" ;; esac
	case "${feed_dir}" in "${OPENWRT_DIR}"/feeds/*) ;; *) die "Unsafe feed destination: ${feed_dir}" ;; esac
	case "${feed_tmp}" in "${OPENWRT_DIR}"/feeds/*.tmp) ;; *) die "Unsafe feed index path: ${feed_tmp}" ;; esac
	case "${archive}" in "${PINNED_FEED_CACHE_DIR}"/feed-*.tar.gz) ;; *) die "Unsafe feed cache path: ${archive}" ;; esac
	[ -d "${PINNED_FEED_CACHE_DIR}" ] && [ ! -L "${PINNED_FEED_CACHE_DIR}" ] ||
		die "Pinned feed cache directory is missing or unsafe"
	[ ! -L "${feed_root}" ] || die "Feed root is a symlink"
	install -d -m 0755 -- "${feed_root}"
	rm -rf -- "${feed_dir}"
	rm -rf -- "${feed_tmp}"
	rm -f -- "${OPENWRT_DIR}/feeds/${feed}.index" \
		"${OPENWRT_DIR}/feeds/${feed}.targetindex"
	PYTHONDONTWRITEBYTECODE=1 python3 -I -B "${FEED_CACHE_TOOL}" \
		"${archive}" "${feed_dir}" "${archive_sha256}" "${expected}" \
		"${expected_origin}" /usr/bin/git ||
		die "Pinned feed cache verification or extraction failed: ${feed}"
	./scripts/feeds update -i "${feed}" ||
		die "Could not build the local index for cached feed ${feed}"
	verify_feed_identity "${feed}" "${expected}" "${expected_origin}"
}

feed_update_network_failure() {
	local status="$1" log="$2"
	[ "${status}" -eq 124 ] && return 0
	grep -Eqi 'Could not resolve host|Temporary failure in name resolution|Name or service not known|Network is unreachable|No route to host|Connection (timed out|refused|reset by peer)|Failed to connect|Could not connect to server|Operation timed out|The operation timed out|Recv failure|Empty reply from server|remote end hung up unexpectedly|RPC failed|HTTP/[0-9.]+ stream|unexpected disconnect|early EOF|fetch-pack: invalid index-pack output|HTTP[^0-9]*(502|503|504)|requested URL returned error: (502|503|504)' "${log}"
}

clone_openwrt_release_source() {
	local attempt=1 clone_status clone_log clone_dir
	clone_dir="${OPENWRT_DIR}.clone.$$"
	case "${OPENWRT_DIR}" in
		"${FINAL_ROOT}"/openwrt) ;;
		*) die "Unsafe OpenWrt checkout path: ${OPENWRT_DIR}" ;;
	esac
	case "${clone_dir}" in
		"${FINAL_ROOT}"/openwrt.clone.*) ;;
		*) die "Unsafe temporary OpenWrt clone path: ${clone_dir}" ;;
	esac
	[ ! -e "${OPENWRT_DIR}" ] && [ ! -L "${OPENWRT_DIR}" ] || \
		die "OpenWrt checkout destination already exists"
	[ ! -e "${clone_dir}" ] && [ ! -L "${clone_dir}" ] || \
		die "Temporary OpenWrt clone destination already exists"
	clone_log="$(mktemp "${LOG_DIR}/.openwrt-clone.XXXXXX")" ||
		die "Cannot allocate OpenWrt clone log"
	while [ "${attempt}" -le 3 ]; do
		set +e
		/usr/bin/timeout "${FEED_UPDATE_TIMEOUT_SECONDS}" \
			git clone --branch "${OPENWRT_TAG}" --depth 1 \
			"${OPENWRT_URL}" "${clone_dir}" >"${clone_log}" 2>&1
		clone_status=$?
		set -e
		if [ "${clone_status}" -eq 0 ]; then
			cat "${clone_log}"
			rm -f -- "${clone_log}"
			mv -- "${clone_dir}" "${OPENWRT_DIR}"
			return 0
		fi
		cat "${clone_log}" >&2
		if ! feed_update_network_failure "${clone_status}" "${clone_log}"; then
			rm -rf -- "${clone_dir}"
			rm -f -- "${clone_log}"
			die "OpenWrt source clone failed for a non-network reason"
		fi
		rm -rf -- "${clone_dir}"
		if [ "${attempt}" -eq 3 ]; then
			rm -f -- "${clone_log}"
			die "OpenWrt source clone failed after 3 bounded network attempts"
		fi
		warn "OpenWrt source clone network failure (attempt ${attempt}/3); retrying"
		sleep "$((attempt * 5))"
		attempt="$((attempt + 1))"
	done
}

update_release_feeds() {
	local feed expected archive_sha256 expected_origin attempt feed_dir update_log update_status
	while read -r feed expected archive_sha256 expected_origin; do
		feed_dir="${OPENWRT_DIR}/feeds/${feed}"
		case "${feed_dir}" in
			"${OPENWRT_DIR}"/feeds/*) ;;
			*) die "Refusing to clean an unsafe feed path: ${feed_dir}" ;;
		esac
		if [ "${OFFLINE_PINNED_SOURCES}" = 1 ]; then
			restore_pinned_feed_cache "${feed}" "${expected}" "${archive_sha256}" "${expected_origin}"
			continue
		fi
		update_log="$(mktemp "${LOG_DIR}/.feed-update-${feed}.XXXXXX")" ||
			die "Cannot allocate feed update log: ${feed}"
		attempt=1
		while [ "${attempt}" -le 3 ]; do
			set +e
			/usr/bin/timeout "${FEED_UPDATE_TIMEOUT_SECONDS}" ./scripts/feeds update "${feed}" >"${update_log}" 2>&1
			update_status=$?
			set -e
			if [ "${update_status}" -eq 0 ]; then
				cat "${update_log}"
				rm -f -- "${update_log}"
				verify_feed_identity "${feed}" "${expected}" "${expected_origin}"
				break
			fi
			cat "${update_log}" >&2
			if ! feed_update_network_failure "${update_status}" "${update_log}"; then
				rm -f -- "${update_log}"
				die "Feed ${feed} update failed for a non-network reason"
			fi
			rm -rf -- "${feed_dir}"
			rm -rf -- "${OPENWRT_DIR}/feeds/${feed}.tmp"
			rm -f -- "${OPENWRT_DIR}/feeds/${feed}.index" \
				"${OPENWRT_DIR}/feeds/${feed}.targetindex"
			if [ "${attempt}" -eq 3 ]; then
				warn "Feed ${feed} network unavailable after 3 bounded attempts; using its pinned verified cache"
				rm -f -- "${update_log}"
				restore_pinned_feed_cache "${feed}" "${expected}" "${archive_sha256}" "${expected_origin}"
				break
			fi
			warn "Feed ${feed} network update failed (attempt ${attempt}/3); retrying from a clean feed directory"
			sleep "$((attempt * 5))"
			attempt="$((attempt + 1))"
		done
	done < <(feed_source_matrix)
}

verify_feed_commits() {
	local feed expected archive_sha256 expected_origin
	while read -r feed expected archive_sha256 expected_origin; do
		verify_feed_identity "${feed}" "${expected}" "${expected_origin}"
	done < <(feed_source_matrix)
}

pin_feed_commits() {
	local feed expected attempt
	while read -r feed expected; do
		if ! git -C "${OPENWRT_DIR}/feeds/${feed}" cat-file -e "${expected}^{commit}"; then
			attempt=1
			while ! git -C "${OPENWRT_DIR}/feeds/${feed}" \
				fetch --force --depth 1 origin "${expected}"; do
				[ "${attempt}" -lt 3 ] || \
					die "Unable to fetch pinned feed commit ${feed} after ${attempt} attempts"
				warn "Feed ${feed} pin fetch failed (attempt ${attempt}/3); retrying"
				sleep "$((attempt * 5))"
				attempt="$((attempt + 1))"
			done
		fi
		[ "$(git -C "${OPENWRT_DIR}/feeds/${feed}" rev-parse HEAD)" = "${expected}" ] || \
			die "Feed ${feed} changed after its verified update"
		git -C "${OPENWRT_DIR}/feeds/${feed}" checkout --detach --force "${expected}"
		git -C "${OPENWRT_DIR}/feeds/${feed}" reset --hard "${expected}"
		git -C "${OPENWRT_DIR}/feeds/${feed}" clean -ffdx
	done < <(feed_commit_matrix)
	verify_feed_commits
}

stage_luci_wireless_txpower_patch() {
	local feed_dir="${OPENWRT_DIR}/feeds/luci"
	local wireless_relative="modules/luci-mod-network/htdocs/luci-static/resources/view/network/wireless.js"
	local usteer_relative="applications/luci-app-usteer/htdocs/luci-static/resources/view/usteer/usteer.js"
	local target="${feed_dir}/${wireless_relative}"
	local usteer_target="${feed_dir}/${usteer_relative}"
	local expected_status feed_status previous_patch

	[ -d "${feed_dir}/.git" ] || die "Pinned LuCI feed is absent"
	[ -f "${target}" ] || die "Pinned LuCI wireless view is absent"
	[ -f "${usteer_target}" ] || die "Pinned LuCI usteer view is absent"
	expected_status="$(printf ' M %s\n M %s' "${usteer_relative}" "${wireless_relative}")"

	feed_status="$(git -C "${feed_dir}" status --porcelain --untracked-files=all)"
	if [ -n "${feed_status}" ]; then
		[ "${feed_status}" = "${expected_status}" ] || \
			die "Unexpected dirty LuCI feed before runtime patch"
		if ! git -C "${feed_dir}" apply --reverse --check "${SRC_LUCI_WIRELESS_PATCH}"; then
			# One-time migration from the immediately preceding recorded patch,
			# which lacks only the new runtime Usteer null-guard hunk.
			previous_patch="$(mktemp)" || die "Cannot allocate prior LuCI patch check"
			awk '
				/^@@ -235,9 \+235,11 @@/ { skip=1; next }
				skip && /^@@ -419,/ { skip=0 }
				!skip { print }
			' "${SRC_LUCI_WIRELESS_PATCH}" >"${previous_patch}"
			if ! git -C "${feed_dir}" apply --reverse --check "${previous_patch}"; then
				rm -f "${previous_patch}"
				die "Prepared LuCI change is neither the current nor prior recorded patch"
			fi
			rm -f "${previous_patch}"
		fi
		git -C "${feed_dir}" checkout -- "${wireless_relative}" "${usteer_relative}"
	fi

	[ -z "$(git -C "${feed_dir}" status --porcelain --untracked-files=all)" ] || \
		die "LuCI feed did not return to its pinned clean state"
	git -C "${feed_dir}" apply --check "${SRC_LUCI_WIRELESS_PATCH}" || \
		die "LuCI runtime patch does not apply to the pinned feed"
	git -C "${feed_dir}" apply "${SRC_LUCI_WIRELESS_PATCH}"
	git -C "${feed_dir}" diff --check -- "${wireless_relative}" "${usteer_relative}" || \
		die "LuCI runtime patch introduces whitespace errors"
	[ "$(git -C "${feed_dir}" status --porcelain --untracked-files=all)" = \
		"${expected_status}" ] || die "LuCI feed contains an unexpected post-patch change"
	node --check "${target}" >/dev/null || die "Patched LuCI wireless JavaScript syntax failed"
	node --check "${usteer_target}" >/dev/null || die "Patched LuCI usteer JavaScript syntax failed"
	grep -Fq 'for (let dbm = 1; dbm <= 38; dbm++)' "${target}" || \
		die "Patched LuCI wireless view lost its complete 1-38 dBm list"
	! grep -Fq 'configured request, outside current driver list' "${target}" || \
		die "Patched LuCI wireless view still renders the removed 38 dBm suffix"
	grep -Fq 'Remotehosts = data[2] || {};' "${usteer_target}" || \
		die "Patched LuCI usteer view lost its stopped-service null guard"
	grep -Fq 'Remotehosts = Remotehosts || {};' "${usteer_target}" || \
		die "Patched LuCI usteer view lost its runtime remote-host null guard"
	grep -Fq '!Object.prototype.hasOwnProperty.call(dns_cache, IPaddr)' "${usteer_target}" || \
		die "Patched LuCI usteer view lost its safe DNS-cache membership check"
}

assert_official_checkout() {
	assert_origin
	[ "$(git -C "${OPENWRT_DIR}" rev-parse HEAD)" = "${OPENWRT_COMMIT}" ] || \
		die "OpenWrt HEAD is not ${OPENWRT_COMMIT}"
	[ "$(git -C "${OPENWRT_DIR}" rev-parse "${OPENWRT_TAG}^{commit}")" = \
		"${OPENWRT_COMMIT}" ] || die "${OPENWRT_TAG} does not peel to ${OPENWRT_COMMIT}"
}

verify_cr6608_device_tree_gate() {
	local dts="${OPENWRT_DIR}/${CR6608_DTS_RELATIVE}"
	local dtsi="${OPENWRT_DIR}/${CR6608_DTSI_RELATIVE}"
	mapfile -t tracked_changes < <(git -C "${OPENWRT_DIR}" diff --name-only --)
	if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
		[ "${#tracked_changes[@]}" -eq 2 ] ||
			die "Maintenance source must change exactly the CR6608 DTS and family DTSI"
		printf '%s\n' "${tracked_changes[@]}" | grep -Fqx "${CR6608_DTS_RELATIVE}" ||
			die "Maintenance source lacks the CR6608 DTS change"
		printf '%s\n' "${tracked_changes[@]}" | grep -Fqx "${CR6608_DTSI_RELATIVE}" ||
			die "Maintenance source lacks the CR6608 family DTSI label change"
		grep -Fqx $'\t\tfactory: partition@100000 {' "${dtsi}" ||
			die "Maintenance DTSI lacks the exact Factory phandle label"
		grep -Fqx $'\t/delete-property/ read-only;' "${dts}" ||
			die "Maintenance DTS does not remove Factory read-only"
	else
		[ "${#tracked_changes[@]}" -eq 2 ] ||
			die "Normal source must change exactly the CR6608 DTS and family DTSI"
		printf '%s\n' "${tracked_changes[@]}" | grep -Fqx "${CR6608_DTS_RELATIVE}" ||
			die "Normal source lacks the CR6608 DTS change"
		printf '%s\n' "${tracked_changes[@]}" | grep -Fqx "${CR6608_DTSI_RELATIVE}" ||
			die "Normal source lacks the CR6608 family DTSI change"
		grep -Fqx $'\t\tpartition@100000 {' "${dtsi}" ||
			die "Normal DTSI no longer has the stock Factory partition"
		! grep -Fq 'factory: partition@100000' "${dtsi}" ||
			die "Normal image must not label Factory for a writable override"
		! grep -Fq '/delete-property/ read-only;' "${dts}" ||
			die "Normal image must keep Factory kernel read-only"
	fi
	grep -Fqx $'\t\tmediatek,cr6608-lab-txpower-38dbm;' "${dts}" || \
		die "CR6608 DTS lacks its device-specific LAB-38 request gate"
	if [ "${BUILD_PROFILE}" = ul-lab ] || [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
		[ "$(grep -Fxc $'\t\tmediatek,cr6608-experimental-ul-muru;' "${dts}")" -eq 1 ] || \
			die "UL MURU profile DTS lacks its single device-specific MURU gate"
	else
		! grep -Fq 'mediatek,cr6608-experimental-ul-muru' "${dts}" || \
			die "Stable/Retail DTS must not expose the UL MURU RAM gate"
	fi
	[ "$(tail -n 2 "${dts}")" = $'\t};\n};' ] || \
		die "CR6608 DTS does not close both the Wi-Fi and PCIe nodes"
	! grep -Fq 'mediatek,disable-radar-background' "${dtsi}" || \
		die "CR6608 DTS still suppresses the MT7915 background-radar capability"
	grep -Fqx $'\t\tbootargs = "console=ttyS0,115200n8";' "${dtsi}" || \
		die "CR6608 family DTSI no longer exposes the stock 115200 serial console"
	if grep -Eq 'console=ttynull|bootargs-override' "${dts}"; then
		die "CR6608 DTS overrides or disables the stock serial console"
	fi
}

restore_build_signing_keys() {
	[ -d "${OPENWRT_DIR}" ] && [ ! -L "${OPENWRT_DIR}" ] &&
		[ "$(stat -c '%u' "${OPENWRT_DIR}")" = "$(id -u)" ] ||
		die "OpenWrt build root ownership is not trusted"
	BUILD_PRIVATE_KEYS_INSTALLED=1
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
	for installed_key in key-build key-build.pub key-build.ucert private-key.pem public-key.pem; do
		[ "$(stat -c '%u' "${OPENWRT_DIR}/${installed_key}")" = "$(id -u)" ] ||
			die "OpenWrt signing material owner is not the build user: ${installed_key}"
	done
}

# --- Signing material -------------------------------------------------------
# Firmware signing is mandatory. OpenWrt 25.12 generates an APK key when it is
# absent, but it does not generate key-build/key-build.ucert for image signing.
# Failing here prevents publishing a metadata-bearing but unsigned sysupgrade.
USE_EXTERNAL_SIGNING=0
if [ "${SOURCE_TEST_ONLY}" = 0 ]; then
	USE_EXTERNAL_SIGNING=1
	for signing_input in "${SRC_FW_SIGNING_KEY}" "${SRC_FW_SIGNING_PUB}" \
		"${SRC_FW_SIGNING_CERT}" \
		"${SRC_APK_SIGNING_KEY}" "${SRC_APK_SIGNING_PUB}"; do
		[ -f "${signing_input}" ] && [ ! -L "${signing_input}" ] && \
			[ -s "${signing_input}" ] || die "Required signing input missing: ${signing_input}"
	done
	[ "$(stat -c '%a' "${SRC_FW_SIGNING_KEY}")" = 600 ] || \
		die "Firmware signing private key must have mode 600"
	[ "$(stat -c '%a' "${SRC_APK_SIGNING_KEY}")" = 600 ] || \
		die "APK signing private key must have mode 600"
fi

for required_muru_input in \
	"${UL_LAB_BUILD_PROFILE_TEST}" "${DASHBOARD_LIVE_NO_CACHE_TEST}" \
	"${MURU_FIRMWARE_VERIFY}" "${MURU_DRIVER_PORT_TEST}" \
	"${MURU_FAULT_ATTRIBUTION_TEST}" \
	"${UL_MU_EVIDENCE_RUNTIME_TEST}" \
	"${MURU_LIVE_REFRESH_TEST}" \
	"${PORT_READINESS_RUNTIME_TEST}" "${PRPLMESH_ROLE_RUNTIME_TEST}" \
	"${PRPLMESH_CREDENTIAL_SYNC_TEST}" "${PRPLMESH_CREDENTIAL_SYNC_HELPER}" \
	"${SRC_UL_MURU_DTS_PATCH}" \
	"${SRC_MURU_PORT_PATCHES[@]}"; do
	[ -s "${required_muru_input}" ] ||
		die "Required v86 qualification input missing: ${required_muru_input}"
done

for required_file in "${SRC_PROFILE_APPLIER}" "${RETAIL_BUILD_PROFILE_TEST}" "${SRC_RETAIL_COMMISSIONING_STAGE}" "${RETAIL_COMMISSIONING_TEST}" "${SRC_FACTORY38_BUILDER}" "${SRC_FACTORY38_STAGE}" "${SRC_FACTORY38_MARKER}" "${SRC_FACTORY38_WIFI_DISABLE}" "${SRC_FACTORY38_WRITE_GATE_PATCH}" "${FACTORY38_BUILDER_TEST}" "${ALL_CHANNEL_38_TEST}" "${FACTORY38_STAGE_GUARD_TEST}" "${FACTORY38_STAGE_MOCK_TEST}" "${LEGACY_11B_TEST}" "${SRC_PATCH}" "${SRC_FACTORY38_PATCH}" "${SRC_UL_MURU_PATCH}" "${SRC_UL_MURU_STOCK_POLICY_PATCH}" "${SRC_RF_DTS_PATCH}" "${SRC_MAC80211_PATCH}" "${SRC_LUCI_WIRELESS_PATCH}" "${SRC_DSA_EEE_PATCH}" "${SRC_UBI_INITRAMFS_GUARD_PATCH}" "${SRC_UHTTPD_PATCH}" "${SRC_MNDP_SOURCE}" "${SRC_MNDP_PACKAGE}/Makefile" "${SRC_SEED}" "${INSPECTOR}" "${VLAN_TEST}" "${NETWORK_SAFETY_TEST}" "${INITRAMFS_UBI_DETACH_TEST}" "${SRC_INITRAMFS_UBI_DETACH}" "${SRC_UL_MURU_DEFERRED}" "${SAFE_APPLY_TEST}" "${SAFE_APPLY_RUNTIME_TEST}" "${SAFE_WIFI_RELOAD_TEST}" "${QUICKSETTINGS_CONTRACT_TEST}" "${ROAMING_STEERING_TEST}" "${LUCI_WIRELESS_TXPOWER_TEST}" "${COUNTRY_DOMAIN_TEST}" "${AUTH_LIFECYCLE_TEST}" "${AUTH_BOUNDED_BLOCKING_TEST}" "${TIME_ANCHOR_RUNTIME_TEST}" "${RETAIL_SECURITY_TEST}" "${RETAIL_RADIO_POLICY_TEST}" "${SECURE_CONSOLE_TEST}" "${SMART_AP_BRAND_GENERATOR}" "${SMART_AP_BRANDING_TEST}" "${LOGIN_CACHE_TEST}" "${SMARTAP_ONLY_ROUTING_TEST}" "${FETCH_BODY_TIMEOUT_TEST}" "${UI_CONTRACT_TEST}" "${UI_PASSWORD_TEST}" "${PRESERVED_CONFIG_TEST}" "${DSA_PORT_TEST}" "${DSA_EEE_TEST}" "${DASHAPI_STATUS_TEST}" "${DASHAPI_RUNTIME_TEST}" "${AX_FEATURE_TEST}" "${UL_MURU_GUARD_RUNTIME_TEST}" "${UL_MURU_VERIFIER_RUNTIME_TEST}" "${UL_MURU_DEFAULTS_MIGRATION_TEST}" "${UL_MURU_DEFERRED_RUNTIME_TEST}" "${UL_MURU_AIRTEST_RUNTIME_TEST}" "${EASYMESH_VERIFIER_RUNTIME_TEST}" "${EXECUTABLE_FORMAT_TEST}" "${TXPOWER_COLLECTOR_TEST}" "${MNDP_SOURCE_TEST}" "${PRIVATE_RUNTIME_TEST}" "${LAN_SCAN_RENDER_TEST}" "${RELEASE_PACKAGE_TEST}" "${MAINTENANCE_PUBLICATION_TEST}" "${ROUTER_UHTTPD_SMARTAP_TEST}" "${LOGIN_RUNTIME_TEST}" "${MOBILE_LAYOUT_TEST}" "${CONTROL_RECOVERY_TEST}" "${JSON_CHARSET_TEST}" "${PACKAGE_MANAGER_RUNTIME_TEST}" "${ARGON_MOBILE_CSS}" "${ARGON_LOCALTIME_JS}" "${ARGON_HEADER}" "${BROWSER_SETUP_TEST}" "${PLAYWRIGHT_PACKAGE_JSON}" "${PLAYWRIGHT_PACKAGE_LOCK}" \
	"${SRC_FILES}/usr/share/ucode/luci/template/themes/argon/sysauth.ut" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-smartap-only" \
	"${UHTTPD_SECURITY_HEADERS}" \
	"${SRC_FILES}/www/cgi-bin/dashluci" \
	"${SRC_FILES}/www/cgi-bin/dashlogout" \
	"${SRC_FILES}/www/cgi-bin/dashlogin" \
	"${SRC_FILES}/www/cgi-bin/dashapi2" \
	"${SRC_FILES}/www/cgi-bin/dashctl" \
	"${SRC_FILES}/www/dashboard.js" \
	"${SRC_FILES}/www/smartap-zero-retention.js" \
	"${SRC_FILES}/usr/sbin/smartap-bootstrap" \
	"${SRC_FILES}/usr/sbin/cr6608-eeprom-power" \
	"${SRC_FILES}/usr/sbin/cr6608-ul-muru-guard" \
	"${SRC_FILES}/usr/sbin/cr6608-ul-muru-verify" \
	"${SRC_FILES}/usr/sbin/cr6608-ul-muru-airtest" \
	"${SRC_FILES}/etc/init.d/cr6608-ul-muru-guard" \
	"${SRC_FILES}/etc/uci-defaults/98-cr6608-ul-muru-guard" \
	"${SRC_FILES}/usr/sbin/cr6608-security-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-session-reaper" \
	"${SRC_FILES}/usr/sbin/cr6608-retail-provision" \
	"${SRC_FILES}/usr/sbin/cr6608-retail-audit" \
	"${SRC_FILES}/usr/sbin/cr6608-retail-radio-audit" \
	"${SRC_FILES}/etc/uci-defaults/98-cr6608-https-capability" \
	"${SRC_FILES}/lib/upgrade/keep.d/cr6608-retail" \
	"${SCRIPT_DIR}/docs/RETAIL-PROVISIONING.md" \
	"${SRC_FILES}/usr/libexec/cr6608-network-safety" \
	"${SRC_FILES}/usr/libexec/cr6608-vlan-lib" \
	"${SRC_FILES}/usr/libexec/cr6608-rescue-firewall-include" \
	"${SRC_FILES}/etc/uci-defaults/97-smartap-bootstrap" \
	"${SRC_FILES}/usr/sbin/smartap-time-anchor" \
	"${SRC_FILES}/etc/init.d/smartap-time-anchor" \
	"${SRC_FILES}/etc/uci-defaults/00-smartap-time-anchor" \
	"${SRC_FILES}/usr/libexec/cr6608-session-auth" \
	"${SRC_FILES}/usr/libexec/cr6608-dashboard-cache-state" \
	"${SRC_FILES}/usr/libexec/cr6608-luci-acl-names.uc" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-wifi-reload" \
	"${SRC_FILES}/usr/sbin/cr6608-quicksettings-apply" \
	"${SRC_FILES}/usr/bin/cr6608-txpower-verify" \
	"${SRC_FILES}/usr/bin/cr6608-country-power-scan" \
	"${SRC_FILES}/usr/bin/cr6608-wifi-full-verify" \
	"${SRC_FILES}/usr/sbin/cr6608-txpower-step-test" \
	"${SRC_FILES}/usr/sbin/cr6608-txpower-channel-table" \
	"${SRC_FILES}/usr/sbin/cr6608-ax-verify" \
	"${SRC_FILES}/usr/libexec/cr6608-txpower-lib" \
	"${SRC_FILES}/usr/sbin/cr6608-wifi-sentinel" \
	"${SRC_FILES}/usr/sbin/cr6608-wifi-schedule" \
	"${SRC_FILES}/usr/sbin/smartap-qos-apply" \
	"${SRC_FILES}/usr/sbin/smartap-selftest" \
	"${SRC_FILES}/usr/sbin/cr6608-management-guard" \
	"${SRC_FILES}/usr/sbin/cr6608-rescue-guard" \
	"${SRC_FILES}/usr/sbin/cr6608-dashboard-invalidate" \
	"${SRC_FILES}/usr/sbin/smartap-autochannel" \
	"${SRC_FILES}/etc/init.d/cr6608-safe-apply" \
	"${SRC_FILES}/etc/init.d/cr6608-quicksettings" \
	"${SRC_FILES}/etc/init.d/cr6608-management-guard" \
	"${SRC_FILES}/etc/init.d/smartap-qos" \
	"${SRC_FILES}/etc/init.d/cr6608-rescue-guard" \
	"${SRC_FILES}/etc/init.d/firewall" \
	"${SRC_FILES}/etc/hotplug.d/iface/99-cr6608-rescue-guard" \
	"${SRC_FILES}/etc/hotplug.d/net/99-cr6608-rescue-guard" \
	"${SRC_FILES}/etc/init.d/cr6608-security" \
	"${SRC_FILES}/etc/init.d/cr6608-neighbor" \
	"${SRC_FILES}/etc/uci-defaults/97-cr6608-security" \
	"${SRC_FILES}/etc/uci-defaults/98-cr6608-safe-apply" \
	"${SRC_FILES}/etc/uci-defaults/96-cr6608-wlanrescue-isolation" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-neighbor-enable" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-runtime-services" \
	"${SRC_FILES}/etc/uci-defaults/96-cr6608-ssh-port" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-secure-console" \
	"${SRC_FILES}/etc/uci-defaults/95-cr6608-dhcp-off" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-preserved-config-v2" \
	"${SRC_FILES}/etc/hotplug.d/iface/99-cr6608-dashboard-cache" \
	"${SRC_FILES}/etc/hotplug.d/net/99-cr6608-dashboard-cache" \
	"${SRC_FILES}/etc/config/cr6608quick" \
	"${SRC_FILES}/etc/config/usteer" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-apply" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-confirm" \
	"${SRC_FILES}/www/luci-static/resources/view/cr6608/quicksettings.js" \
	"${SRC_FILES}/usr/share/luci/menu.d/luci-app-cr6608-quicksettings.json" \
	"${SRC_FILES}/usr/share/luci/menu.d/zz-cr6608-logout.json" \
	"${SRC_FILES}/usr/share/ucode/luci/controller/cr6608/logout.uc" \
	"${SRC_FILES}/usr/share/rpcd/acl.d/luci-app-cr6608-quicksettings.json" \
	"${SRC_FILES}/etc/modules.d/mt7915e" \
	"${FWTOOL_RUNTIME_POLICY}" "${FW_OWNER_TRUST_KEY}"; do
	[ -s "${required_file}" ] || die "Required source file missing: ${required_file}"
done
[ -d "${SRC_RETAIL_PROFILE_FILES}" ] && [ ! -L "${SRC_RETAIL_PROFILE_FILES}" ] ||
	die 'Retail profile overlay directory is missing or unsafe'
[ -z "$(find "${SRC_RETAIL_PROFILE_FILES}" -type l -print -quit)" ] ||
	die 'Retail profile overlay contains a symlink'
[ "$(find "${SRC_RETAIL_PROFILE_FILES}" -type f | wc -l)" -ge 7 ] ||
	die 'Retail profile overlay is incomplete'
[ -d "${SRC_UL_LAB_PROFILE_FILES}" ] && [ ! -L "${SRC_UL_LAB_PROFILE_FILES}" ] ||
	die 'UL-lab profile overlay directory is missing or unsafe'
[ -z "$(find "${SRC_UL_LAB_PROFILE_FILES}" -type l -print -quit)" ] ||
	die 'UL-lab profile overlay contains a symlink'
[ "$(find "${SRC_UL_LAB_PROFILE_FILES}" -type f | wc -l)" -ge 6 ] ||
	die 'UL-lab profile overlay is incomplete'
for source_kit_required in "${SOURCE_KIT_TOOL}" "${SOURCE_KIT_TEST}" \
	"${FLEET_MAC_AUDIT_TOOL}" "${FLEET_MAC_AUDIT_TEST}" \
	"${MNDP_PACKET_TEST}" "${PRIVATE_RUNTIME_STAT_MOCK}"; do
	[ -s "${source_kit_required}" ] || \
		die "Required history-free source-kit input missing: ${source_kit_required}"
done
for offline_source_required in "${FEED_CACHE_TOOL}" "${OPENWRT_TAG_GATE}" \
	"${OPENWRT_RELEASE_KEY}" "${OFFLINE_SOURCE_FALLBACK_TEST}"; do
	[ -s "${offline_source_required}" ] && [ ! -L "${offline_source_required}" ] ||
		die "Required offline-source fallback input missing or unsafe: ${offline_source_required}"
done
[ "$(sha256sum "${OPENWRT_RELEASE_KEY}" | awk '{print $1}')" = \
	"${OPENWRT_RELEASE_KEY_SHA256}" ] || die "Pinned OpenWrt release key hash mismatch"
for required_maintenance_source in \
	"${SRC_CRASHLOG_WRITE_GATE_PATCH}" "${SRC_CRASHLOG_BUILDER}" \
	"${SRC_CRASHLOG_SANITIZER}" "${SRC_CRASHLOG_MARKER}" \
	"${SRC_CRASHLOG_WIFI_DISABLE}" "${SRC_CRASHLOG_README}" \
	"${CRASHLOG_SANITIZE_MOCK_TEST}" \
	"${CRASHLOG_BUILD_CONTRACT_TEST}"; do
	[ -s "${required_maintenance_source}" ] || \
		die "Required crash-log maintenance source missing: ${required_maintenance_source}"
done
for required_file in "${SMARTAP_QOS_TEST}" "${DASHCTL_MAC_QOS_TRANSACTION_TEST}" "${IPV6_DUALSTACK_TEST}" "${IPV6_UPGRADE_MIGRATION_TEST}" "${IPV4_ONLY_RUNTIME_TEST}" "${MAC_IDENTITY_TEST}" "${FLEET_MAC_AUDIT_TEST}" "${GUEST_NETWORK_TEST}" "${DASHBOARD_ZERO_RETENTION_TEST}" "${MANAGEMENT_GUARD_TEST}" "${RESCUE_GUARD_TEST}" "${INITRAMFS_UBI_DETACH_TEST}" "${DASHBOARD_CACHE_RUNTIME_TEST}" "${DASHBOARD_REQUEST_COORDINATION_TEST}" "${DASHCTL_JSON_BUILDERS_TEST}" "${JSON_CHARSET_TEST}" "${PACKAGE_MANAGER_RUNTIME_TEST}" "${WIZARD_CHANNEL_OPTIONS_TEST}" "${DASHCTL_RUN_LIMIT_RUNTIME_TEST}" "${DASHAPI_RUNTIME_TEST}" "${SQM_SAFETY_TEST}" "${ROAMING_STEERING_TEST}" \
	"${SRC_FILES}/usr/sbin/cr6608-management-guard" "${SRC_FILES}/etc/init.d/cr6608-management-guard"; do
	[ -s "${required_file}" ] || die "Required stability test missing: ${required_file}"
done
grep -Fqx "VERSION='${PRESERVED_CONFIG_MIGRATION_VERSION}'" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-preserved-config-v2" || \
	die "Preserved-config migration version disagrees with release metadata"
if [ "${FACTORY38_BUNDLE_ENABLED}" = 1 ]; then
	[ -f "${FACTORY38_SOURCE}" ] && [ ! -L "${FACTORY38_SOURCE}" ] ||
		die 'Factory backup must remain a regular non-symlink file'
	[ "$(stat -c '%s' "${FACTORY38_SOURCE}")" = 524288 ] ||
		die 'Factory backup must be exactly 524288 bytes'
	[ "$(sha256sum "${FACTORY38_SOURCE}" | awk '{print $1}')" = "${FACTORY38_ORIGINAL_SHA256}" ] ||
		die 'Factory backup does not match the preserved CR6608 device image'
fi

if [ -e "${OPENWRT_DIR}" ] && [ ! -d "${OPENWRT_DIR}/.git" ]; then
	die "OpenWrt path exists but is not a Git checkout: ${OPENWRT_DIR}"
fi
if [ ! -d "${OPENWRT_DIR}/.git" ]; then
	[ "${OFFLINE_PINNED_SOURCES}" = 0 ] ||
		die "Offline pinned-source mode requires the existing signed OpenWrt checkout"
	clone_openwrt_release_source
fi
assert_origin
[ "$(git -C "${OPENWRT_DIR}" rev-parse HEAD)" = "${OPENWRT_COMMIT}" ] || \
	die "OpenWrt preflight checkout is not at ${OPENWRT_COMMIT}"
verify_openwrt_source_gate offline-only

grep -Fq '/sys/firmware/devicetree/base' \
	"${SRC_FILES}/usr/bin/cr6608-txpower-verify" || \
	die "TX-power verifier does not traverse the real device-tree directory"
grep -Fq "mediatek,cr6608-lab-txpower-38dbm" \
	"${SRC_FILES}/usr/bin/cr6608-txpower-verify" || \
	die "TX-power verifier does not check the exact CR6608 DTS property"
grep -Fqx 'REQUIRE_IMAGE_SIGNATURE=1' "${FWTOOL_RUNTIME_POLICY}" &&
	grep -Fqx 'REQUIRE_IMAGE_METADATA=1' "${FWTOOL_RUNTIME_POLICY}" ||
	die "Runtime sysupgrade policy does not fail closed on signature and metadata"
cmp -s "${SRC_FW_SIGNING_PUB}" "${FW_OWNER_TRUST_KEY}" ||
	die "Runtime firmware trust key differs from the pinned signing public key"

recreate_required_links "${SRC_FILES}"
assert_required_links "${SRC_FILES}"
write_source_manifest "${SCRIPT_DIR}" "${SOURCE_MANIFEST}"
SOURCE_MANIFEST_SHA256="$(sha256sum "${SOURCE_MANIFEST}" | awk '{print $1}')"
{
	printf 'source_manifest=source-manifest.txt\n'
	printf 'source_manifest_format=cr6608-source-v1\n'
	printf 'source_manifest_sha256=%s\n' "${SOURCE_MANIFEST_SHA256}"
	printf 'firmware_signature_enforcement_contract=pass\n'
} > "${SOURCE_TEST_LOG}"
chmod 0644 "${SOURCE_TEST_LOG}"

{
	printf 'build_profile=%s\n' "${BUILD_PROFILE}"
	printf 'node_runtime=%s\n' "$(node --version)"
	printf 'playwright_core_version=%s\n' "${PLAYWRIGHT_EXPECTED_VERSION}"
	printf 'chromium_sha256=%s\n' "${CHROMIUM_SHA256}"
for shell_source in \
	"${SRC_FILES}/www/cgi-bin/dashlogin" \
	"${SRC_FILES}/www/cgi-bin/dashluci" \
	"${SRC_FILES}/www/cgi-bin/dashlogout" \
	"${SRC_FILES}/www/cgi-bin/dashapi2" \
	"${SRC_FILES}/www/cgi-bin/dashctl" \
	"${SRC_FILES}/usr/libexec/cr6608-session-auth" \
	"${SRC_FILES}/usr/libexec/cr6608-dashboard-cache-state" \
	"${SRC_FILES}/usr/libexec/cr6608-network-safety" \
	"${SRC_FILES}/usr/libexec/cr6608-vlan-lib" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-safe-wifi-reload" \
	"${SRC_FILES}/usr/sbin/cr6608-quicksettings-apply" \
	"${SRC_FILES}/usr/bin/cr6608-txpower-verify" \
	"${SRC_FILES}/usr/bin/cr6608-country-power-scan" \
	"${SRC_FILES}/usr/bin/cr6608-wifi-full-verify" \
	"${SRC_FILES}/usr/sbin/cr6608-txpower-step-test" \
	"${SRC_FILES}/usr/sbin/cr6608-txpower-channel-table" \
	"${SRC_FILES}/usr/sbin/cr6608-ax-verify" \
	"${SRC_FILES}/usr/libexec/cr6608-txpower-lib" \
	"${SRC_FILES}/usr/sbin/cr6608-wifi-sentinel" \
	"${SRC_FILES}/usr/sbin/cr6608-wifi-schedule" \
	"${SRC_FILES}/usr/sbin/smartap-qos-apply" \
	"${SRC_FILES}/usr/sbin/smartap-selftest" \
	"${SRC_FILES}/usr/sbin/cr6608-management-guard" \
	"${SRC_FILES}/usr/sbin/cr6608-rescue-guard" \
	"${SRC_FILES}/usr/sbin/cr6608-dashboard-invalidate" \
	"${SRC_FILES}/usr/sbin/smartap-autochannel" \
	"${SRC_FILES}/usr/sbin/cr6608-security-apply" \
	"${SRC_FILES}/usr/sbin/cr6608-session-reaper" \
	"${SRC_FILES}/usr/sbin/cr6608-eeprom-power" \
	"${SRC_FILES}/usr/sbin/smartap-bootstrap" \
	"${SRC_FILES}/etc/init.d/cr6608-safe-apply" \
	"${SRC_FILES}/etc/init.d/cr6608-quicksettings" \
	"${SRC_FILES}/etc/init.d/cr6608-management-guard" \
	"${SRC_FILES}/etc/init.d/smartap-qos" \
	"${SRC_FILES}/etc/init.d/cr6608-rescue-guard" \
	"${SRC_FILES}/etc/init.d/firewall" \
	"${SRC_FILES}/etc/hotplug.d/iface/99-cr6608-rescue-guard" \
	"${SRC_FILES}/etc/hotplug.d/net/99-cr6608-rescue-guard" \
	"${SRC_FILES}/etc/init.d/cr6608-security" \
	"${SRC_FILES}/etc/init.d/cr6608-neighbor" \
	"${SRC_FILES}/etc/uci-defaults/97-cr6608-security" \
	"${SRC_FILES}/etc/uci-defaults/98-cr6608-safe-apply" \
	"${SRC_FILES}/etc/uci-defaults/96-cr6608-wlanrescue-isolation" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-neighbor-enable" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-runtime-services" \
	"${SRC_FILES}/etc/uci-defaults/96-cr6608-ssh-port" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-secure-console" \
	"${SRC_FILES}/etc/uci-defaults/95-cr6608-dhcp-off" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-preserved-config-v2" \
	"${SRC_FILES}/etc/uci-defaults/99-cr6608-smartap-only" \
	"${SRC_FILES}/etc/uci-defaults/94-cr6608-txpower" \
	"${SRC_FILES}/etc/uci-defaults/97-smartap-bootstrap" \
	"${SRC_FILES}/etc/hotplug.d/iface/99-cr6608-dashboard-cache" \
	"${SRC_FILES}/etc/hotplug.d/net/99-cr6608-dashboard-cache" \
	"${SRC_FILES}/etc/config/cr6608quick" \
	"${SRC_FILES}/etc/config/usteer" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-apply" \
	"${SRC_FILES}/www/cgi-bin/cr6608-quick-confirm" \
	"${SRC_FILES}/usr/sbin/smartap-time-anchor" \
	"${SRC_FILES}/etc/init.d/smartap-time-anchor" \
	"${SRC_FILES}/etc/uci-defaults/00-smartap-time-anchor"; do
	sh -n "${shell_source}" || die "Shell syntax failed: ${shell_source}"
done
node --check "${SRC_FILES}/www/dashboard.js" >/dev/null || \
	die "Dashboard JavaScript syntax failed"
node --check "${SRC_FILES}/www/smartap-zero-retention.js" >/dev/null || \
	die "Smart AP zero-retention migration JavaScript syntax failed"
node --check "${ARGON_LOCALTIME_JS}" >/dev/null || \
	die "Argon local-time JavaScript syntax failed"
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
printf 'vlan_lib_tests=pass\n'
sh -n "${NETWORK_SAFETY_TEST}" || die "Network-safety runtime test syntax failed"
sh "${NETWORK_SAFETY_TEST}" | grep -qx 'network_safety_runtime_tests=pass' || \
	die "Generic L3/DSA device isolation tests failed"
printf 'network_safety_runtime_tests=pass\n'
sh -n "${SAFE_APPLY_TEST}" || die "Safe Apply regression test syntax failed"
sh "${SAFE_APPLY_TEST}" | grep -qx 'safe_apply_tests=pass' || \
	die "Safe Apply confirmation regression test failed"
printf 'safe_apply_tests=pass\n'
sh -n "${SAFE_APPLY_RUNTIME_TEST}" || die "Safe Apply runtime test syntax failed"
sh "${SAFE_APPLY_RUNTIME_TEST}" | grep -qx 'safe_apply_runtime_tests=pass' || \
	die "Safe Apply token and management-IP runtime tests failed"
printf 'safe_apply_runtime_tests=pass\n'
sh -n "${INITRAMFS_UBI_DETACH_TEST}" || die "Initramfs UBI detach test syntax failed"
sh "${INITRAMFS_UBI_DETACH_TEST}" | grep -qx 'initramfs_ubi_detach_contract=pass' || \
	die "Initramfs UBI detach safety gates failed"
printf 'initramfs_ubi_detach_contract=pass\n'
sh -n "${SAFE_WIFI_RELOAD_TEST}" || die "Safe Wi-Fi runtime test syntax failed"
sh "${SAFE_WIFI_RELOAD_TEST}" | grep -qx 'safe_wifi_reload_tests=pass' || \
	die "Safe Wi-Fi section and hostapd runtime tests failed"
printf 'safe_wifi_reload_tests=pass\n'
sh -n "${QUICKSETTINGS_CONTRACT_TEST}" || die "Quick-settings contract test syntax failed"
sh "${QUICKSETTINGS_CONTRACT_TEST}" | grep -qx 'quicksettings_contracts=pass' || \
	die "Quick-settings ownership and cleanup contracts failed"
printf 'quicksettings_contracts=pass\n'
sh -n "${SMARTAP_QOS_TEST}" || die "Smart AP per-client policer test syntax failed"
sh "${SMARTAP_QOS_TEST}" | grep -qx 'smartap_qos_apply=pass' || \
	die "Smart AP per-client policer apply/rollback tests failed"
printf 'smartap_qos_apply=pass\n'
sh -n "${DASHCTL_MAC_QOS_TRANSACTION_TEST}" || die "Dashboard MAC/QoS transaction test syntax failed"
sh "${DASHCTL_MAC_QOS_TRANSACTION_TEST}" | grep -qx 'dashctl_mac_qos_transactions=pass' || \
	die "Dashboard MAC block and client-limit rollback transaction tests failed"
printf 'dashctl_mac_qos_transactions=pass\n'
sh -n "${IPV6_DUALSTACK_TEST}" || die "IPv6 dual-stack contract test syntax failed"
sh "${IPV6_DUALSTACK_TEST}" | grep -qx 'ipv6_dualstack_contract=pass' || \
	die "IPv6 dual-stack/AP isolation contracts failed"
printf 'ipv6_dualstack_contract=pass\n'
python3 -B "${IPV6_UPGRADE_MIGRATION_TEST}" | grep -qx 'ipv6_upgrade_migration=pass' || \
	die "Preserved v53 IPv6 upgrade migration failed"
printf 'ipv6_upgrade_migration=pass\n'
sh -n "${IPV4_ONLY_RUNTIME_TEST}" || die "IPv4-only runtime test syntax failed"
sh "${IPV4_ONLY_RUNTIME_TEST}" | grep -qx 'ipv4_only_runtime=pass' || \
	die "IPv4-only dynamic-interface or listener runtime contract failed"
printf 'ipv4_only_runtime=pass\n'
sh -n "${GUEST_NETWORK_TEST}" || die "Guest network contract test syntax failed"
sh "${GUEST_NETWORK_TEST}" | grep -qx 'guest_network_contract=pass' || \
	die "Guest DHCP/DNS/isolation/WAN-forwarding contracts failed"
printf 'guest_network_contract=pass\n'
sh -n "${DASHBOARD_ZERO_RETENTION_TEST}" || die "Dashboard zero-retention contract test syntax failed"
sh "${DASHBOARD_ZERO_RETENTION_TEST}" | grep -qx 'dashboard_zero_retention_contract=pass' || \
	die "Dashboard boot and global zero-retention contracts failed"
printf 'dashboard_zero_retention_contract=pass\n'
sh -n "${MANAGEMENT_GUARD_TEST}" || die "Management guard test syntax failed"
sh "${MANAGEMENT_GUARD_TEST}" | grep -qx 'management_guard=pass' || \
	die "Management guard fail-safe and cooldown tests failed"
printf 'management_guard=pass\n'
sh -n "${RESCUE_GUARD_TEST}" || die "Rescue guard test syntax failed"
sh "${RESCUE_GUARD_TEST}" | grep -qx 'rescue_guard_contract=pass' || \
	die "Rescue Wi-Fi isolation, fail-closed, and lifecycle contracts failed"
printf 'rescue_guard_contract=pass\n'
sh -n "${DASHBOARD_CACHE_RUNTIME_TEST}" || die "Dashboard cache runtime test syntax failed"
sh "${DASHBOARD_CACHE_RUNTIME_TEST}" | grep -qx 'dashboard_cache_runtime=pass' || \
	die "Dashboard guardian, long-child/SIGKILL-residue, lock, and telemetry-purge runtime tests failed"
printf 'dashboard_cache_runtime=pass\n'
sh -n "${DASHBOARD_LIVE_NO_CACHE_TEST}" || die "Dashboard live no-cache test syntax failed"
sh "${DASHBOARD_LIVE_NO_CACHE_TEST}" | grep -qx 'dashboard_live_no_cache=pass' || \
	die "Live dashboard retained or reused telemetry cache files"
printf 'dashboard_live_no_cache=pass\n'
node --check "${DASHBOARD_REQUEST_COORDINATION_TEST}" >/dev/null || \
	die "Dashboard request-coordination test syntax failed"
node "${DASHBOARD_REQUEST_COORDINATION_TEST}" | grep -qx 'dashboard_request_coordination=pass' || \
	die "Dashboard stale-read, AbortController, POST-lock, or scoped-binding contracts failed"
printf 'dashboard_request_coordination=pass\n'
sh -n "${CONTROL_RECOVERY_TEST}" || die "Control recovery contract test syntax failed"
sh "${CONTROL_RECOVERY_TEST}" | grep -qx 'control_recovery_contract=pass' || \
	die "Control recovery / orphan-worker safety contracts failed"
printf 'control_recovery_contract=pass\n'
sh -n "${DASHCTL_JSON_BUILDERS_TEST}" || die "Dashboard JSON builder test syntax failed"
sh "${DASHCTL_JSON_BUILDERS_TEST}" | grep -qx 'dashctl_json_builders=pass' || \
	die "Dashboard bulk JSON builders changed field semantics or escaping"
printf 'dashctl_json_builders=pass\n'
sh -n "${JSON_CHARSET_TEST}" || die "JSON charset contract test syntax failed"
sh "${JSON_CHARSET_TEST}" | grep -qx 'json_charset_contract=pass' || \
	die "Smart AP JSON endpoints do not declare UTF-8 consistently"
printf 'json_charset_contract=pass\n'
sh -n "${PACKAGE_MANAGER_RUNTIME_TEST}" || die "Package-manager runtime test syntax failed"
sh "${PACKAGE_MANAGER_RUNTIME_TEST}" | grep -qx 'package_manager_runtime=pass' || \
	die "Smart AP package actions do not match apk/opkg runtime semantics"
printf 'package_manager_runtime=pass\n'
sh -n "${WIZARD_CHANNEL_OPTIONS_TEST}" || die "Wizard channel option test syntax failed"
sh "${WIZARD_CHANNEL_OPTIONS_TEST}" | grep -qx 'wizard_channel_options=pass' || \
	die "Wizard live channel bulk parser changed filtering, order, or DFS labels"
printf 'wizard_channel_options=pass\n'
sh -n "${DASHCTL_RUN_LIMIT_RUNTIME_TEST}" || die "Dashboard command deadline runtime test syntax failed"
sh "${DASHCTL_RUN_LIMIT_RUNTIME_TEST}" | grep -q '^dashctl_run_limit_runtime=pass ' || \
	die "Dashboard command deadlines changed output, timing, process-tree cleanup, or descriptor isolation"
printf 'dashctl_run_limit_runtime=pass\n'
sh -n "${SQM_SAFETY_TEST}" || die "SQM safety contract test syntax failed"
sh "${SQM_SAFETY_TEST}" | grep -qx 'sqm_safety_contract=pass' || \
	die "SQM rate/offload/rollback safety contracts failed"
printf 'sqm_safety_contract=pass\n'
sh -n "${ROAMING_STEERING_TEST}" || die "Roaming/steering contract test syntax failed"
sh "${ROAMING_STEERING_TEST}" | grep -qx 'roaming_steering_contract=pass' || \
	die "Smart Connect, usteer, 802.11k/v/r, and mesh-security contracts failed"
printf 'roaming_steering_contract=pass\n'
sh -n "${UCI_SYNC_RUNTIME_TEST}" || die "UCI synchronization runtime test syntax failed"
sh "${UCI_SYNC_RUNTIME_TEST}" | grep -qx 'uci_sync_runtime=pass' || \
	die "UCI wireless/Quick Settings synchronization tests failed"
printf 'uci_sync_runtime=pass\n'
sh -n "${DASHCTL_WIFI_APPLY_TEST}" || die "Dashboard Wi-Fi apply test syntax failed"
sh "${DASHCTL_WIFI_APPLY_TEST}" | grep -qx 'dashctl_wifi_apply_tests=pass' || \
	die "Dashboard Wi-Fi backup, reload, and hostapd verification tests failed"
printf 'dashctl_wifi_apply_tests=pass\n'
sh -n "${LUCI_WIRELESS_TXPOWER_TEST}" || \
	die "LuCI wireless txpower preservation test syntax failed"
LUCI_WIRELESS_PATCH="${SRC_LUCI_WIRELESS_PATCH}" NODE_BIN="${NODE_RUNTIME}" \
	sh "${LUCI_WIRELESS_TXPOWER_TEST}" | \
	grep -qx 'luci_wireless_txpower_preserve=pass' || \
	die "LuCI radio modal does not preserve an out-of-list configured txpower request"
printf 'luci_wireless_txpower_preserve=pass\n'
python3 -B "${FACTORY38_BUILDER_TEST}" ||
	die 'Factory-38 offline builder tests failed'
printf 'factory38_builder_tests=pass\n'
python3 -B "${ALL_CHANNEL_38_TEST}" | grep -qx 'all_channel_38_contract=pass' ||
	die 'Factory-38 all-channel source contract failed'
printf 'all_channel_38_contract=pass\n'
sh -n "${FACTORY38_STAGE_GUARD_TEST}" ||
	die 'Factory-38 stage guard test syntax failed'
sh "${FACTORY38_STAGE_GUARD_TEST}" "${SRC_FACTORY38_STAGE}" |
	grep -qx 'STAGE_GUARD_TESTS=PASS' ||
	die 'Factory-38 signal/lock guard tests failed'
printf 'factory38_stage_guards=pass\n'
sh -n "${FACTORY38_STAGE_MOCK_TEST}" ||
	die 'Factory-38 full-flow mock test syntax failed'
sh "${FACTORY38_STAGE_MOCK_TEST}" "${SRC_FACTORY38_STAGE}" |
	grep -Eq '^FACTORY38_STAGE_MOCK_TESTS=PASS cases=[0-9]+ nand_real_writes=0$' ||
	die 'Factory-38 full-flow mock tests failed'
printf 'factory38_stage_mock=pass\n'
sh -n "${SRC_CRASHLOG_SANITIZER}" || die 'Crash-log sanitizer syntax failed'
sh -n "${SRC_CRASHLOG_WIFI_DISABLE}" || die 'Crash-log Wi-Fi gate syntax failed'
bash -n "${SRC_CRASHLOG_BUILDER}" || die 'Crash-log maintenance builder syntax failed'
sh -n "${CRASHLOG_SANITIZE_MOCK_TEST}" || die 'Crash-log sanitizer mock syntax failed'
sh "${CRASHLOG_SANITIZE_MOCK_TEST}" | \
	grep -Eq '^CR6608_CRASHLOG_SANITIZE_MOCK_TESTS=PASS cases=[0-9]+ nand_real_writes=0$' || \
	die 'Crash-log sanitizer fail-closed mocks failed'
bash -n "${CRASHLOG_BUILD_CONTRACT_TEST}" || die 'Crash-log build contract syntax failed'
bash "${CRASHLOG_BUILD_CONTRACT_TEST}" | \
	grep -Eq '^CR6608_CRASHLOG_BUILD_CONTRACT_TESTS=PASS cases=[0-9]+ real_builds=0 nand_writes=0$' || \
	die 'Crash-log maintenance publication contracts failed'
printf 'crashlog_maintenance_contracts=pass\n'
sh "${LEGACY_11B_TEST}" | grep -qx 'legacy_11b_contract=pass' ||
	die '2.4 GHz legacy 802.11b policy contract failed'
printf 'legacy_11b_contract=pass\n'
sh -n "${COUNTRY_DOMAIN_TEST}" || die "Shared regulatory country contract test syntax failed"
sh "${COUNTRY_DOMAIN_TEST}" | grep -qx 'country_domain_contract=pass' || \
	die "Shared cfg80211 country-domain synchronization contracts failed"
printf 'country_domain_contract=pass\n'
sh -n "${AUTH_LIFECYCLE_TEST}" || die "Authentication lifecycle test syntax failed"
auth_test_output="$(sh "${AUTH_LIFECYCLE_TEST}")" || \
	die "Authentication lifecycle tests failed"
printf '%s\n' "${auth_test_output}"
printf '%s\n' "${auth_test_output}" | grep -qx 'auth_lifecycle_test=pass' || \
	die "Authentication lifecycle positive gate did not pass"
printf '%s\n' "${auth_test_output}" | grep -qx 'auth_lifecycle_negative_tests=pass' || \
	die "Authentication lifecycle negative gates did not pass"
printf '%s\n' "${auth_test_output}" | grep -qx 'auth_protocol_cookie_tests=pass' || \
	die "HTTP/HTTPS authentication cookie isolation gates did not pass"
auth_bounded_output="$(PYTHONDONTWRITEBYTECODE=1 python3 "${AUTH_BOUNDED_BLOCKING_TEST}")" || \
	die "Bounded authentication fault-injection tests failed"
printf '%s\n' "${auth_bounded_output}"
printf '%s\n' "${auth_bounded_output}" | grep -qx 'auth_bounded_blocking_test=PASS' || \
	die "Bounded authentication fault-injection gate did not pass"
sh -n "${TIME_ANCHOR_RUNTIME_TEST}" || die "Persistent time anchor test syntax failed"
sh "${TIME_ANCHOR_RUNTIME_TEST}" | grep -qx 'time_anchor_runtime_tests=pass' || \
	die "Power-loss and sysupgrade time anchor regression tests failed"
printf 'time_anchor_runtime_tests=pass\n'
sh -n "${RETAIL_SECURITY_TEST}" || die "Retail security contract test syntax failed"
sh "${RETAIL_SECURITY_TEST}" | grep -qx 'retail_security_contract=pass' || \
	die "Retail unique-credential, protected-Wi-Fi, and TLS gate failed"
printf 'retail_security_contract=pass\n'
sh -n "${RETAIL_RADIO_POLICY_TEST}" || die "Retail radio policy test syntax failed"
sh "${RETAIL_RADIO_POLICY_TEST}" | grep -qx 'retail_radio_policy_contract=pass' || \
	die "Retail radio policy fail-closed gates failed"
printf 'retail_radio_policy_contract=pass\n'
sh -n "${RETAIL_BUILD_PROFILE_TEST}" || die "Retail build profile test syntax failed"
sh "${RETAIL_BUILD_PROFILE_TEST}" | grep -qx 'retail_build_profile_contract=pass' || \
	die "Retail build profile isolation and fail-closed defaults failed"
printf 'retail_build_profile_contract=pass\n'
sh -n "${RETAIL_COMMISSIONING_TEST}" ||
	die "Retail commissioning key contract test syntax failed"
sh "${RETAIL_COMMISSIONING_TEST}" |
	grep -qx 'retail_commissioning_key_contract=pass' ||
	die "Retail RAM-only commissioning key gates failed"
printf 'retail_commissioning_key_contract=pass\n'
sh -n "${UL_LAB_BUILD_PROFILE_TEST}" || die "UL-lab build profile test syntax failed"
sh "${UL_LAB_BUILD_PROFILE_TEST}" | grep -qx 'ul_lab_build_profile_contract=pass' || \
	die "UL MURU RAM-only build profile isolation failed"
printf 'ul_lab_build_profile_contract=pass\n'
sh -n "${SECURE_CONSOLE_TEST}" || die "Secure console migration test syntax failed"
sh "${SECURE_CONSOLE_TEST}" | grep -qx 'secure_console_migration=pass' || \
	die "Preserved root password does not safely gate the serial console"
printf 'secure_console_migration=pass\n'
PYTHONDONTWRITEBYTECODE=1 python3 "${SMART_AP_BRAND_GENERATOR}" --check | \
	grep -Eq '^smart_ap_brand_check=pass files=[0-9]+$' || \
	die "Smart AP generated brand assets are stale"
smart_ap_branding_output="$(PYTHONDONTWRITEBYTECODE=1 python3 "${SMART_AP_BRANDING_TEST}")" || \
	die "Smart AP branding contracts failed"
printf '%s\n' "${smart_ap_branding_output}"
printf '%s\n' "${smart_ap_branding_output}" | grep -qx 'smart_ap_branding_test=pass' || \
	die "Smart AP branding positive gate did not pass"
sh -n "${LOGIN_CACHE_TEST}" || die "Login/cache contract test syntax failed"
sh "${LOGIN_CACHE_TEST}" | grep -qx 'login_cache_contract=pass' || \
	die "Login timeout and browser-cache contracts failed"
printf 'login_cache_contract=pass\n'
sh -n "${SMARTAP_ONLY_ROUTING_TEST}" || die "Smart AP/LuCI handoff routing test syntax failed"
sh "${SMARTAP_ONLY_ROUTING_TEST}" | grep -qx 'smartap_luci_handoff=pass' || \
	die "Smart AP/LuCI authenticated handoff contract failed"
printf 'smartap_luci_handoff=pass\n'
sh -n "${ROUTER_UHTTPD_SMARTAP_TEST}" || die "Router uhttpd Smart AP runtime test syntax failed"
printf 'router_uhttpd_smartap_test_syntax=pass\n'
node --check "${FETCH_BODY_TIMEOUT_TEST}" >/dev/null || \
	die "Fetch body-timeout regression test syntax failed"
node "${FETCH_BODY_TIMEOUT_TEST}" | grep -qx 'fetch_body_timeout=pass' || \
	die "Fetch timeout does not cover stalled response bodies"
printf 'fetch_body_timeout=pass\n'
sh -n "${UI_CONTRACT_TEST}" || die "Dashboard UI contract test syntax failed"
sh "${UI_CONTRACT_TEST}" | grep -qx 'dashboard_ui_contracts=pass' || \
	die "Dashboard UI performance and layout contracts failed"
printf 'dashboard_ui_contracts=pass\n'
sh -n "${UI_PASSWORD_TEST}" || die "UI password synchronization test syntax failed"
sh "${UI_PASSWORD_TEST}" | grep -qx 'ui_password_separation=pass' || \
	die "Smart AP/LuCI and SSH/serial credential-separation contract failed"
printf 'ui_password_separation=pass\n'
PYTHONDONTWRITEBYTECODE=1 python3 "${PRESERVED_CONFIG_TEST}" | \
	grep -qx 'preserved_config_migration=pass' || \
	die "Preserved-config migration tests failed"
printf 'preserved_config_migration=pass\n'
sh -n "${DSA_PORT_TEST}" || die "DSA port contract test syntax failed"
sh "${DSA_PORT_TEST}" | grep -qx 'dsa_port_contract=pass' || \
	die "DSA LAN port default-forwarding contract failed"
printf 'dsa_port_contract=pass\n'
sh -n "${MAC_IDENTITY_TEST}" || die "Factory MAC identity contract test syntax failed"
sh "${MAC_IDENTITY_TEST}" | grep -qx 'mac_identity_contract=pass' || \
	die "Factory MAC identity, DSA sharing, or runtime matching contract failed"
printf 'mac_identity_contract=pass\n'
PYTHONDONTWRITEBYTECODE=1 python3 "${FLEET_MAC_AUDIT_TEST}" | \
	grep -qx 'fleet_mac_audit_tests=pass' || \
	die "Fleet MAC uniqueness audit tests failed"
printf 'fleet_mac_audit_tests=pass\n'
sh -n "${DSA_EEE_TEST}" || die "MT7621 early-EEE test syntax failed"
PATCH_FILE="${SRC_DSA_EEE_PATCH}" OPENWRT_ROOT="${OPENWRT_DIR}" \
	sh "${DSA_EEE_TEST}" | grep -qx 'mt7621_eee_early_disable_contract=pass' || \
	die "MT7621 early-EEE source contract failed"
printf 'mt7621_eee_early_disable_contract=pass\n'
sh -n "${DASHAPI_STATUS_TEST}" || die "Dashboard status API contract test syntax failed"
sh "${DASHAPI_STATUS_TEST}" | grep -qx 'dashapi2_status_contract=pass' || \
	die "Dashboard status API contract failed"
printf 'dashapi2_status_contract=pass\n'
sh -n "${DASHAPI_RUNTIME_TEST}" || die "Dashboard status API runtime test syntax failed"
sh "${DASHAPI_RUNTIME_TEST}" | grep -qx 'dashapi2_runtime=pass' || \
	die "Dashboard monotonic rates or bounded process-tree cleanup failed"
printf 'dashapi2_runtime=pass\n'
sh -n "${AX_FEATURE_TEST}" || die "AX feature contract test syntax failed"
sh "${AX_FEATURE_TEST}" | grep -qx 'ax_feature_contracts=pass' || \
	die "AX/OFDMA/MU-MIMO source contracts failed"
printf 'ax_feature_contracts=pass\n'
sh -n "${UL_MURU_GUARD_RUNTIME_TEST}" || \
	die "UL MURU fail-closed guard runtime test syntax failed"
sh "${UL_MURU_GUARD_RUNTIME_TEST}" | \
	grep -qx 'ul_muru_guard_runtime=pass' || \
	die "UL MURU fail-closed startup state machine failed"
printf 'ul_muru_guard_runtime=pass\n'
sh -n "${UL_MURU_VERIFIER_RUNTIME_TEST}" || \
	die "UL MURU verifier runtime test syntax failed"
sh "${UL_MURU_VERIFIER_RUNTIME_TEST}" | \
	grep -qx 'ul_muru_verifier_runtime=pass' || \
	die "UL MURU verifier accepted a stopped, missing, or stale guard"
printf 'ul_muru_verifier_runtime=pass\n'
sh -n "${UL_MURU_DEFAULTS_MIGRATION_TEST}" || \
	die "UL MURU defaults migration test syntax failed"
sh "${UL_MURU_DEFAULTS_MIGRATION_TEST}" | \
	grep -qx 'ul_muru_defaults_migration=pass' || \
	die "UL MURU retail/explicit-disable migration policy failed"
printf 'ul_muru_defaults_migration=pass\n'
sh -n "${UL_MURU_DEFERRED_RUNTIME_TEST}" || \
	die "UL MURU late-boot reconciler runtime test syntax failed"
sh "${UL_MURU_DEFERRED_RUNTIME_TEST}" | \
	grep -qx 'ul_muru_deferred_runtime=pass' || \
	die "UL MURU late-boot reconciliation failed"
printf 'ul_muru_deferred_runtime=pass\n'
sh -n "${UL_MURU_AIRTEST_RUNTIME_TEST}" || \
	die "UL MURU radio-counter correlation runtime test syntax failed"
sh "${UL_MURU_AIRTEST_RUNTIME_TEST}" | \
	grep -qx 'ul_muru_airtest_runtime=pass' || \
	die "UL MURU full-bandwidth client and correlation-boundary gates failed"
printf 'ul_muru_airtest_runtime=pass\n'
sh -n "${MURU_DRIVER_PORT_TEST}" || die "MURU driver port test syntax failed"
sh "${MURU_DRIVER_PORT_TEST}" | grep -qx 'muru_driver_port_contract=pass' || \
	die "MediaTek MURU bitmap, response-only telemetry, or fault-latch contract failed"
printf 'muru_driver_port_contract=pass\n'
sh -n "${MURU_FAULT_ATTRIBUTION_TEST}" || \
	die "MURU fault attribution test syntax failed"
sh "${MURU_FAULT_ATTRIBUTION_TEST}" | \
	grep -qx 'muru_fault_attribution_contract=pass' || \
	die "MURU fault attribution, guarded re-arm, upstream DL floor, or client-attributed uplink evidence contract failed"
printf 'muru_fault_attribution_contract=pass\n'
sh -n "${UL_MU_EVIDENCE_RUNTIME_TEST}" || \
	die "UL MU evidence runtime test syntax failed"
sh "${UL_MU_EVIDENCE_RUNTIME_TEST}" | grep -qx 'ul_mu_evidence_runtime=pass' || \
	die "client-attributed UL MU evidence contract failed"
printf 'ul_mu_evidence_runtime=pass\n'
sh -n "${MURU_LIVE_REFRESH_TEST}" || \
	die "MURU live refresh test syntax failed"
sh "${MURU_LIVE_REFRESH_TEST}" | grep -qx 'muru_live_refresh_contract=pass' || \
	die "MURU live record refresh or strike decay contract failed"
printf 'muru_live_refresh_contract=pass\n'
sh -n "${EASYMESH_VERIFIER_RUNTIME_TEST}" || \
	die "EasyMesh verifier runtime test syntax failed"
sh "${EASYMESH_VERIFIER_RUNTIME_TEST}" | \
	grep -qx 'easymesh_verifier_runtime=pass' || \
	die "EasyMesh disabled-policy verifier did not return immediately"
printf 'easymesh_verifier_runtime=pass\n'
sh -n "${PORT_READINESS_RUNTIME_TEST}" || die "Port readiness runtime test syntax failed"
sh "${PORT_READINESS_RUNTIME_TEST}" | grep -qx 'port_readiness_runtime=pass' || \
	die "LAN/VLAN/WAN carrier and traffic readiness contracts failed"
printf 'port_readiness_runtime=pass\n'
sh -n "${PRPLMESH_ROLE_RUNTIME_TEST}" || die "prplMesh role runtime test syntax failed"
sh "${PRPLMESH_ROLE_RUNTIME_TEST}" | grep -qx 'prplmesh_role_runtime=pass' || \
	die "EasyMesh Controller/Agent role enforcement failed"
printf 'prplmesh_role_runtime=pass\n'
sh -n "${PRPLMESH_CREDENTIAL_SYNC_HELPER}" || \
	die "prplMesh credential synchronizer syntax failed"
sh -n "${PRPLMESH_CREDENTIAL_SYNC_TEST}" || \
	die "prplMesh credential synchronization test syntax failed"
sh "${PRPLMESH_CREDENTIAL_SYNC_TEST}" | \
	grep -qx 'prplmesh_credential_sync_contract=pass' || \
	die "Retail/Quick Settings prplMesh credential synchronization failed"
printf 'prplmesh_credential_sync_contract=pass\n'
sh -n "${SSH_PORT_TEST}" || die "SSH port migration contract test syntax failed"
sh "${SSH_PORT_TEST}" | grep -qx 'ssh_port_contract=pass' || \
	die "SSH port 2003 clean/preserved-config migration contract failed"
printf 'ssh_port_contract=pass\n'
sh -n "${EXECUTABLE_FORMAT_TEST}" || die "Executable line-ending test syntax failed"
sh "${EXECUTABLE_FORMAT_TEST}" | grep -qx 'executable_line_endings=pass' || \
	die "Executable files contain Windows CRLF line endings"
printf 'executable_line_endings=pass\n'
sh -n "${TXPOWER_COLLECTOR_TEST}" || die "Tx-power collector test syntax failed"
sh "${TXPOWER_COLLECTOR_TEST}" | grep -qx 'txpower_collector_contract=pass' || \
	die "Tx-power JSON/CSV collector source contract failed"
printf 'txpower_collector_contract=pass\n'
sh -n "${MNDP_SOURCE_TEST}" || die "MNDP source test syntax failed"
sh "${MNDP_SOURCE_TEST}" | grep -qx 'mndp_source_contract=pass' || \
	die "MNDP source compilation and packet contract failed"
printf 'mndp_source_contract=pass\n'
sh -n "${PRIVATE_RUNTIME_TEST}" || die "Private runtime test syntax failed"
sh "${PRIVATE_RUNTIME_TEST}" | grep -qx 'private_runtime_contract=pass' || \
	die "Private runtime hostile-path contract failed"
printf 'private_runtime_contract=pass\n'
node --check "${LAN_SCAN_RENDER_TEST}" >/dev/null || \
	die "LAN scan rendering test JavaScript syntax failed"
node "${LAN_SCAN_RENDER_TEST}" | grep -qx 'lan_scan_render=pass' || \
	die "LAN scan device/LLDP rendering contract failed"
printf 'lan_scan_render=pass\n'
bash -n "${MAINTENANCE_PUBLICATION_TEST}" || \
	die "Maintenance publication guard test syntax failed"
bash "${MAINTENANCE_PUBLICATION_TEST}" | \
	grep -qx 'maintenance_publication_guard_tests=pass' || \
	die "Maintenance flashable/private publication guard behavior failed"
printf 'maintenance_publication_guard_tests=pass\n'
offline_source_fallback_output="$(
	PYTHONDONTWRITEBYTECODE=1 python3 -I -B "${OFFLINE_SOURCE_FALLBACK_TEST}"
)" || die "Offline pinned-source fallback functional and tamper tests failed"
printf '%s\n' "${offline_source_fallback_output}"
printf '%s\n' "${offline_source_fallback_output}" | \
	grep -qx 'offline_source_fallback_tests=pass' ||
	die "Offline pinned-source fallback tests did not reach their pass marker"
sh -n "${RELEASE_PACKAGE_TEST}" || die "Release-package test syntax failed"
sh "${RELEASE_PACKAGE_TEST}" | grep -qx 'release_package_contract=pass' || \
	die "Release-package source/config/patch contract failed"
printf 'release_package_contract=pass\n'
source_kit_contract_output="$(
	PYTHONDONTWRITEBYTECODE=1 python3 -I -B "${SOURCE_KIT_TEST}"
)" || die "History-free source-kit functional and tamper tests failed"
printf '%s\n' "${source_kit_contract_output}"
printf '%s\n' "${source_kit_contract_output}" | \
	grep -qx 'source_kit_contract=pass' || \
	die "History-free source-kit contract did not reach its pass marker"
node --check "${LOGIN_RUNTIME_TEST}" >/dev/null || \
	die "Login runtime test JavaScript syntax failed"
login_runtime_output="$(node "${LOGIN_RUNTIME_TEST}")" || \
	die "Dashboard login/session runtime tests failed"
printf '%s\n' "${login_runtime_output}"
printf '%s\n' "${login_runtime_output}" | grep -qx 'login_runtime_tests=pass' || \
	die "Dashboard login/session runtime positive gate did not pass"
node --check "${MOBILE_LAYOUT_TEST}" >/dev/null || \
	die "Mobile layout test JavaScript syntax failed"
if [ -n "${BROWSER_TEST_EVIDENCE}" ]; then
	[ -f "${BROWSER_TEST_EVIDENCE}" ] && [ ! -L "${BROWSER_TEST_EVIDENCE}" ] || \
		die "Browser test evidence is missing"
	grep -Fqx 'result=mobile_layout_tests=pass' "${BROWSER_TEST_EVIDENCE}" || \
		die "Browser test evidence lacks a pass result"
	for evidence_pair in \
		"test_script_sha256:${MOBILE_LAYOUT_TEST}" \
		"dashboard_js_sha256:${SRC_FILES}/www/dashboard.js" \
		"index_html_sha256:${SRC_FILES}/www/index.html" \
		"cascade_css_sha256:${SRC_FILES}/www/luci-static/argon/css/cascade.css" \
		"argon_mobile_css_sha256:${ARGON_MOBILE_CSS}" \
		"argon_localtime_js_sha256:${ARGON_LOCALTIME_JS}" \
		"argon_header_sha256:${ARGON_HEADER}"; do
		evidence_key="${evidence_pair%%:*}"
		evidence_file="${evidence_pair#*:}"
		evidence_hash="$(sed -n "s/^${evidence_key}=//p" "${BROWSER_TEST_EVIDENCE}")"
		[ "${evidence_hash}" = "$(sha256sum "${evidence_file}" | awk '{print $1}')" ] || \
			die "Browser evidence does not match ${evidence_key}"
	done
	printf 'mobile_layout_test_mode=verified-external-evidence\n'
	printf 'mobile_layout_evidence_sha256=%s\n' \
		"$(sha256sum "${BROWSER_TEST_EVIDENCE}" | awk '{print $1}')"
fi
mobile_layout_output="$(node "${MOBILE_LAYOUT_TEST}")" || \
	die "Mobile layout browser tests failed"
printf '%s\n' "${mobile_layout_output}"
printf '%s\n' "${mobile_layout_output}" | grep -qx 'mobile_layout_tests=pass' || \
	die "Mobile layout browser positive gate did not pass"
[ -d "${UI_SCREENSHOT_DIR}" ] && [ ! -L "${UI_SCREENSHOT_DIR}" ] || \
	die "Mobile layout screenshot directory is missing or unsafe"
expected_screenshot_count=0
for viewport_width in 360 390 430; do
	for screenshot_page in login overview quick isolation network devices wifi insights system actions; do
		screenshot_file="${UI_SCREENSHOT_DIR}/smartap-${screenshot_page}-${viewport_width}.png"
		[ -s "${screenshot_file}" ] && [ ! -L "${screenshot_file}" ] || \
			die "Required mobile screenshot is missing or unsafe: $(basename "${screenshot_file}")"
		expected_screenshot_count=$((expected_screenshot_count + 1))
	done
done
for design_width in 360 390 430 1440; do
	for design_language in ar en; do
		for design_theme in dark light; do
			screenshot_file="${UI_SCREENSHOT_DIR}/smartap-design-${design_language}-${design_theme}-${design_width}.png"
			[ -s "${screenshot_file}" ] && [ ! -L "${screenshot_file}" ] || \
				die "Required design-system screenshot is missing or unsafe: $(basename "${screenshot_file}")"
			expected_screenshot_count=$((expected_screenshot_count + 1))
		done
	done
done
for screenshot_name in \
	smartap-luci-redirect-390.png \
	smartap-overview-partial-390.png \
	smartap-nonlive-rejected-390.png \
	smartap-overview-desktop-1440.png \
	smartap-wifi-disabled-390.png \
	smartap-insights-tabs-rtl-360.png \
	smartap-insights-tabs-rtl-390.png \
	smartap-insights-tabs-rtl-430.png \
	smartap-isolation-clearance-1440.png \
	argon-admin-390.png \
	argon-interfaces-390.png \
	argon-system-ltr-390.png \
	argon-system-rtl-390.png \
	argon-system-ltr-1440.png \
	argon-system-rtl-1440.png \
	argon-wireless-390.png \
	argon-status-ltr-390.png \
	argon-status-rtl-390.png \
	argon-status-ltr-1440.png \
	argon-status-rtl-1440.png; do
	screenshot_file="${UI_SCREENSHOT_DIR}/${screenshot_name}"
	[ -s "${screenshot_file}" ] && [ ! -L "${screenshot_file}" ] || \
		die "Required browser screenshot is missing or unsafe: ${screenshot_name}"
	expected_screenshot_count=$((expected_screenshot_count + 1))
done
[ "$(find "${UI_SCREENSHOT_DIR}" -maxdepth 1 -type f -name '*.png' | wc -l)" -eq "${expected_screenshot_count}" ] || \
	die "Mobile layout screenshot matrix is incomplete"
ui_evidence_temporary="${UI_EVIDENCE_MANIFEST}.tmp.$$"
write_ui_evidence_hashes "${ui_evidence_temporary}" || {
	rm -f -- "${ui_evidence_temporary}"
	die "UI screenshot evidence could not be pinned after its browser gate"
}
[ "$(wc -l < "${ui_evidence_temporary}")" -eq "${expected_screenshot_count}" ] || {
	rm -f -- "${ui_evidence_temporary}"
	die "UI screenshot evidence manifest has the wrong exact file count"
}
mv -f -- "${ui_evidence_temporary}" "${UI_EVIDENCE_MANIFEST}"
chmod 0644 "${UI_EVIDENCE_MANIFEST}"
UI_EVIDENCE_MANIFEST_SHA256="$(
	sha256sum "${UI_EVIDENCE_MANIFEST}" | awk '{print $1}'
)"
[ -n "${UI_EVIDENCE_MANIFEST_SHA256}" ] || \
	die "UI screenshot evidence manifest hash is empty"
verify_ui_evidence_unchanged
printf 'ui_evidence_manifest_sha256=%s\n' "${UI_EVIDENCE_MANIFEST_SHA256}"
printf 'mobile_layout_tests=pass\n'

printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=0\n' | \
	cmp -s - "${SRC_FILES}/etc/modules.d/mt7915e" || \
	die "Invalid etc/modules.d/mt7915e in final overlay"
[ ! -e "${SRC_FILES}/etc/modprobe.d" ] && [ ! -L "${SRC_FILES}/etc/modprobe.d" ] || \
	die "Stale files/etc/modprobe.d path must not be present"
if grep -RIsaEq 'cr6608_rf_(30|35)dbm|CR6608-RF-(30|35)DBM' "${SRC_FILES}" "${SRC_PATCH}" "${SRC_FACTORY38_PATCH}"; then
	die "Stale 30/35 dBm driver gate is present"
fi
[ "$(grep -c '^diff --git ' "${SRC_PATCH}")" -eq 8 ] || \
	die "mt76 verified-transaction patch must modify exactly eight audited files"
for expected_mt76_file in mac80211.c mt7915/debugfs.c mt7915/init.c mt7915/mac.c mt7915/main.c mt7915/mcu.c mt7915/mmio.c mt7915/mt7915.h; do
	grep -Fq "diff --git a/${expected_mt76_file} b/${expected_mt76_file}" \
		"${SRC_PATCH}" || die "mt76 patch lacks ${expected_mt76_file}"
done
[ "$(grep -c '^diff --git ' "${SRC_FACTORY38_PATCH}")" -eq 2 ] || \
	die "Factory-38 companion patch must modify exactly mt7915/eeprom.c and mt7915/mt7915.h"
for factory38_file in mt7915/eeprom.c mt7915/mt7915.h; do
	grep -Fq "diff --git a/${factory38_file} b/${factory38_file}" \
		"${SRC_FACTORY38_PATCH}" || die "Factory-38 patch lacks ${factory38_file}"
done
[ "$(grep -c '^--- a/mt7915/mcu.c' "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}")" -eq 1 ] && \
	[ "$(grep -c '^+++ b/mt7915/mcu.c' "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}")" -eq 1 ] || \
	die "Firmware EEPROM shadow patch must modify only mt7915/mcu.c"
grep -Fq 'mt7915_cr6608_prepare_firmware_eeprom_shadow' \
	"${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" || \
	die "Firmware EEPROM shadow patch lacks its gated shadow builder"
grep -Fq 'shadow[MT_EE_TX0_POWER_2G + chain * 3]' \
	"${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" && \
	grep -Fq 'shadow[MT_EE_TX0_POWER_5G + chain * 12 + group]' \
	"${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" || \
	die "Firmware EEPROM shadow does not cover every audited target byte"
grep -Fq 'CR6608_FIRMWARE_TARGET_2G' "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" && \
	grep -Fq 'CR6608_FIRMWARE_TARGET_5G' "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" && \
	grep -Fq '0x40' "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" && \
	grep -Fq '0x42' "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" || \
	die "Firmware EEPROM shadow lacks the audited 0x40/0x42 targets"
grep -Fq 'kmemdup(eep, eeprom_size, GFP_KERNEL)' \
	"${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" && \
	grep -Fq 'kfree(shadow);' "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" || \
	die "Firmware EEPROM shadow does not use a private bounded copy"
grep -Fq 'module_param(cr6608_rf_38dbm, bool, 0444);' "${SRC_PATCH}" || \
	die "mt76 patch lacks the read-only CR6608 module gate"
grep -Fq 'mediatek,cr6608-lab-txpower-38dbm' "${SRC_PATCH}" || \
	die "mt76 patch lacks the CR6608 DTS property gate"
grep -Fq 'mt76_get_rate_power_limits' "${SRC_PATCH}" || \
	die "mt76 patch no longer follows the real rate-SKU path"
grep -Fq 'mt7915_cr6608_poll_sku_readback' "${SRC_PATCH}" || \
	die "mt76 patch lacks MCU SKU readback verification"
grep -Fq 'mt7915_cr6608_rf_rollback_sku' "${SRC_PATCH}" || \
	die "mt76 patch lacks verified conservative rollback"
grep -Fq 'mt7915_mcu_schedule_full_recovery' "${SRC_PATCH}" || \
	die "mt76 patch lacks fail-closed full recovery"
grep -Fq 'required_rate_peak = requested_power * 2 - path_delta;' "${SRC_PATCH}" || \
	die "mt76 patch lacks exact two-chain half-dBm accounting"
grep -Fq 'return requested_power > 38 ? -ERANGE : mt7915_mcu_set_txpower_sku_default(phy);' "${SRC_PATCH}" || \
	die "mt76 patch does not reject requests above the audited 38 dBm ceiling"
grep -Fq 'hweight16(phy->mt76->chainmask) != 2' "${SRC_PATCH}" || \
	die "mt76 patch lacks the exact two-chain fail-closed gate"
grep -Fq 'mphy->txpower_cur = readback_peak;' "${SRC_PATCH}" || \
	die "mt76 patch does not publish verified MCU readback as current power"
[ "$(grep -c '^diff --git ' "${SRC_UL_MURU_PATCH}")" -eq 4 ] || \
	die "Experimental UL MURU patch must modify exactly four audited mt7915 files"
for ul_muru_file in mt7915/debugfs.c mt7915/init.c mt7915/mcu.c mt7915/mt7915.h; do
	grep -Fq "diff --git a/${ul_muru_file} b/${ul_muru_file}" \
		"${SRC_UL_MURU_PATCH}" || die "UL MURU patch lacks ${ul_muru_file}"
done
grep -Fq 'muru->cfg.ofdma_ul_en = true;' "${SRC_UL_MURU_PATCH}" && \
	grep -Fq 'muru->cfg.mimo_ul_en = true;' "${SRC_UL_MURU_PATCH}" && \
	grep -Fq 'IEEE80211_HE_PHY_CAP2_UL_MU_FULL_MU_MIMO' "${SRC_UL_MURU_PATCH}" && \
	! grep -Fq 'mediatek,cr6608-experimental-ul-muru' "${SRC_RF_DTS_PATCH}" && \
	grep -Fq 'mediatek,cr6608-experimental-ul-muru' "${SRC_UL_MURU_DTS_PATCH}" || \
	die "Experimental UL MURU host/MCU/DTS gates are incomplete"
[ "$(grep -c '^diff --git ' "${SRC_UL_MURU_STOCK_POLICY_PATCH}")" -eq 4 ] || \
	die "MediaTek-vendor UL MURU baseline patch must modify exactly four audited mt7915 files"
for ul_muru_policy_file in mt7915/debugfs.c mt7915/init.c mt7915/mcu.c mt7915/mt7915.h; do
	grep -Fq "diff --git a/${ul_muru_policy_file} b/${ul_muru_policy_file}" \
		"${SRC_UL_MURU_STOCK_POLICY_PATCH}" || \
		die "MediaTek-vendor UL MURU baseline patch lacks ${ul_muru_policy_file}"
done
for ul_muru_policy_marker in \
	'policy=mediatek-vendor-sta-rec-muru' \
	'cr6608_muru_capabilities' 'ul_ofdma_sta_rec_eligible' \
	'ul_mumimo_capable=%u\n", full' \
	'muru->mimo_ul.full_ul_mimo)'; do
	grep -Fq "${ul_muru_policy_marker}" "${SRC_UL_MURU_STOCK_POLICY_PATCH}" || \
		die "MediaTek-vendor UL MURU baseline patch lacks ${ul_muru_policy_marker}"
done
if grep -Eq 'MURU_SET_(BSRP_CTRL|SUTX|MUMIMO_CTRL|MANUAL_CFG|MU_DL_ACK_POLICY|TRIG_TYPE|20M_DYN_ALGO|PROT_FRAME_THR|CERT_MU_EDCA_OVERRIDE|ARB_OP_MODE)|mt7915_mcu_set_muru_cfg|mt7915_mcu_set_mu_dl_ack_policy|mt7915_mcu_set_mu_prot_frame_th|mt7915_mcu_set_cr6608_ul_muru' \
	"${SRC_UL_MURU_STOCK_POLICY_PATCH}"; then
	die "A MediaTek-only MURU_CTRL sub-command or an unverified MURU sender must not be staged"
fi
grep -Fq '#define CR6608_FACTORY38_TARGET_2G' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq '0x40' "${SRC_FACTORY38_PATCH}" ||
	die "Factory-38 patch lacks the exact audited 2.4 GHz persisted target"
grep -Fq '#define CR6608_FACTORY38_TARGET_5G' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq '0x42' "${SRC_FACTORY38_PATCH}" ||
	die "Factory-38 patch lacks the exact audited 5 GHz persisted target"
grep -Fq 'cr6608_factory38_persisted_match' "${SRC_FACTORY38_PATCH}" ||
	die "Factory-38 patch lacks read-only persisted-byte telemetry"
grep -Fq 'mt7915_cr6608_factory38_raw_match(dev)' "${SRC_FACTORY38_PATCH}" ||
	die "Factory-38 patch does not verify the raw EEPROM image"
grep -Fq 'bool mt7915_cr6608_factory38_raw_match(struct mt7915_dev *dev);' \
	"${SRC_FACTORY38_PATCH}" || die "Factory-38 patch does not export its exact-match gate"
grep -Fq 'bool mt7915_cr6608_rf_request_armed(struct mt7915_dev *dev);' \
	"${SRC_FACTORY38_PATCH}" || die "Factory-38 patch does not export its armed request gate"
grep -Fq 'bool enabled = mt7915_cr6608_rf_request_armed(dev);' \
	"${SRC_PATCH}" || die "CR6608 RF request path lacks the armed volatile override"
grep -Fq 'mt7915_cr6608_factory38_raw_match(dev);' "${SRC_PATCH}" || \
	die "CR6608 RF request path does not retain persisted Factory telemetry"
grep -Fq 'if (mt7915_cr6608_rf_request_armed(dev))' "${SRC_PATCH}" &&
	grep -Fq 'return -EPERM;' "${SRC_PATCH}" ||
	die "CR6608 RF patch does not reject the unverified debugfs SKU write path"
grep -Fq 'activating the audited volatile 38 dBm target override' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq 'target_power = CR6608_FACTORY38_TARGET_2G;' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq 'target_power = CR6608_FACTORY38_TARGET_5G;' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq 'CR6608_FACTORY38_SAFE_DELTA_2G' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq 'CR6608_FACTORY38_SAFE_DELTA_5G' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq 'return CR6608_FACTORY38_SAFE_DELTA_2G;' "${SRC_FACTORY38_PATCH}" &&
	grep -Fq 'return CR6608_FACTORY38_SAFE_DELTA_5G;' "${SRC_FACTORY38_PATCH}" ||
	die "Factory-38 volatile path does not override both bands with audited targets and rate deltas"
! grep -Fq 'target_power = min_t(int, target_power' "${SRC_FACTORY38_PATCH}" || \
	die "Factory-38 volatile path still contains the old stock-safe clamp"
! grep -Fq 'target_power <' "${SRC_FACTORY38_PATCH}" ||
	die "Factory-38 patch still contains a RAM target floor"
grep -Fq 'mt7915_cr6608_rf_request_enabled(dev)' "${SRC_FACTORY38_PATCH}" || \
	die "Factory-38 patch is not protected by the CR6608 gate"
added_mt76_lines="$(sed -n '/^+++ /d; /^+/s/^+//p' "${SRC_PATCH}" "${SRC_FACTORY38_PATCH}" "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" "${SRC_UL_MURU_PATCH}" "${SRC_UL_MURU_STOCK_POLICY_PATCH}" "${SRC_MURU_PORT_PATCHES[@]}")"
if printf '%s\n' "${added_mt76_lines}" |
	grep -Eq 'mtd(write|_write)|mtd_erase|reg_rule'; then
	die "mt76 patches write calibration storage or alter cfg80211 regulatory rules"
fi
[ "$(grep -c '^diff --git ' "${SRC_MAC80211_PATCH}")" -eq 3 ] || \
	die "mac80211 trace patch must modify exactly main.c, debugfs.c and ieee80211_i.h"
grep -Fq 'diff --git a/net/mac80211/main.c b/net/mac80211/main.c' \
	"${SRC_MAC80211_PATCH}" || die "mac80211 trace patch targets the wrong file"
grep -Fq 'diff --git a/net/mac80211/debugfs.c b/net/mac80211/debugfs.c' \
	"${SRC_MAC80211_PATCH}" || die "mac80211 trace patch lacks the expected debugfs.c change"
grep -Fq 'diff --git a/net/mac80211/ieee80211_i.h b/net/mac80211/ieee80211_i.h' \
	"${SRC_MAC80211_PATCH}" || die "mac80211 trace patch lacks the expected ieee80211_i.h change"
grep -Fq 'CR6608-TXTRACE stage=mac80211' "${SRC_MAC80211_PATCH}" || \
	die "mac80211 trace patch lacks its structured marker"
grep -Fq 'DEBUGFS_ADD(txpower_state)' "${SRC_MAC80211_PATCH}" || \
	die "mac80211 trace patch lacks the txpower_state debugfs endpoint"
added_mac80211_lines="$(sed -n '/^+++ /d; /^+/s/^+//p' "${SRC_MAC80211_PATCH}")"
if printf '%s\n' "${added_mac80211_lines}" |
	grep -Eq 'chan->(max_reg_power|max_power)[[:space:]]*=|reg_rule|mtd(write|_write)'; then
	die "mac80211 trace patch changes regulatory/calibration data"
fi
printf 'source_tests=pass\n'
} 2>&1 | tee -a "${SOURCE_TEST_LOG}"
grep -Fqx 'source_manifest=source-manifest.txt' "${SOURCE_TEST_LOG}" ||
	die "Source test log lost its manifest name binding"
grep -Fqx 'source_manifest_format=cr6608-source-v1' "${SOURCE_TEST_LOG}" ||
	die "Source test log lost its manifest format binding"
grep -Fqx "source_manifest_sha256=${SOURCE_MANIFEST_SHA256}" \
	"${SOURCE_TEST_LOG}" || die "Source test log lost its manifest hash binding"
grep -Fqx 'source_tests=pass' "${SOURCE_TEST_LOG}" ||
	die "Source test log did not reach its final pass marker"
ui_evidence_manifest_record_count="$(
	grep -c '^ui_evidence_manifest_sha256=' "${SOURCE_TEST_LOG}" || true
)"
[ "${ui_evidence_manifest_record_count}" -eq 1 ] ||
	die "Source test log must contain exactly one UI evidence manifest hash"
UI_EVIDENCE_MANIFEST_SHA256="$(
	sed -n 's/^ui_evidence_manifest_sha256=//p' "${SOURCE_TEST_LOG}"
)"
require_lower_hex "${UI_EVIDENCE_MANIFEST_SHA256}" 64 \
	"Bound UI screenshot evidence manifest SHA-256"
verify_ui_evidence_unchanged \
	"UI screenshot evidence changed after its source-test log binding"
verify_source_manifest_unchanged "Source changed while its bound tests were running"

if [ "${SOURCE_TEST_ONLY}" = 1 ]; then
	printf 'source_test_log=%s\n' "${SOURCE_TEST_LOG}"
	exit 0
fi

if [ "${FACTORY38_BUNDLE_ENABLED}" != 1 ]; then
	ok "device-private Factory-38 bundle disabled; no private device data will be published"
fi

say "[1/10] Resetting one clean OpenWrt source tree to ${OPENWRT_TAG}"
reuse_prepared_tree="${CR6608_REUSE_PREPARED_TREE:-0}"
case "${reuse_prepared_tree}" in
	0) BUILD_EXECUTION_MODE=clean_source ;;
	1) BUILD_EXECUTION_MODE=verified_incremental_cache ;;
	*) die "CR6608_REUSE_PREPARED_TREE must be 0 or 1" ;;
esac
assert_origin
cd "${OPENWRT_DIR}"
if [ "${OFFLINE_PINNED_SOURCES}" = 1 ]; then
	verify_openwrt_source_gate offline-only
else
	verify_openwrt_source_gate online-fallback
fi
git checkout --detach --force "${OPENWRT_COMMIT}"
git reset --hard "${OPENWRT_COMMIT}"
if [ "${reuse_prepared_tree}" = 1 ]; then
	# Reuse only compiler/toolchain output from the immediately preceding,
	# pinned OpenWrt checkout. Source, feeds, configuration, overlay, tmp and
	# published images are still deleted and reconstructed below. This makes a
	# small follow-up image rebuild fast without accepting stale source inputs.
	for cache_dir in dl build_dir staging_dir; do
		cache_path="${OPENWRT_DIR}/${cache_dir}"
		[ -d "${cache_path}" ] && [ ! -L "${cache_path}" ] &&
			[ "$(stat -c '%u' "${cache_path}")" = "$(id -u)" ] ||
			die "Verified incremental cache is unavailable or untrusted: ${cache_dir}"
	done
	git clean -ffdx -e dl/ -e build_dir/ -e staging_dir/
	[ -d "${OPENWRT_DIR}/build_dir" ] && [ -d "${OPENWRT_DIR}/staging_dir" ] ||
		die "Verified incremental compiler caches were not retained"
	ok "verified compiler/toolchain caches retained; source and image outputs reset"
else
	# Keep only the immutable download cache for a fully clean source build.
	git clean -ffdx -e dl/
fi
restore_build_signing_keys
assert_official_checkout
[ -z "$(git status --porcelain --untracked-files=all)" ] || \
	die "OpenWrt checkout is not clean after reset"
PRPLMESH_PACKAGE_DIR="${OPENWRT_DIR}/package/network/services/prplmesh"
[ ! -e "${PRPLMESH_PACKAGE_DIR}" ] || \
	die "Official source unexpectedly already contains a prplMesh package"
cp -a -- "${SRC_PRPLMESH_PACKAGE}" "${PRPLMESH_PACKAGE_DIR}"
diff -qr -- "${SRC_PRPLMESH_PACKAGE}" "${PRPLMESH_PACKAGE_DIR}" >/dev/null || \
	die "Staged prplMesh package differs from the recorded input"
MNDP_PACKAGE_DIR="${OPENWRT_DIR}/package/network/services/cr6608-mndp"
[ ! -e "${MNDP_PACKAGE_DIR}" ] || \
	die "Official source unexpectedly already contains a CR6608 MNDP package"
cp -a -- "${SRC_MNDP_PACKAGE}" "${MNDP_PACKAGE_DIR}"
mkdir -p "${MNDP_PACKAGE_DIR}/src"
install -m 0644 -- "${SRC_MNDP_SOURCE}" \
	"${MNDP_PACKAGE_DIR}/src/cr6608-mndp-advertise.c"
cmp -s -- "${SRC_MNDP_SOURCE}" \
	"${MNDP_PACKAGE_DIR}/src/cr6608-mndp-advertise.c" || \
	die "Staged MNDP source differs from the recorded input"
git apply --check "${SRC_RF_DTS_PATCH}"
git apply "${SRC_RF_DTS_PATCH}"
if [ "${BUILD_PROFILE}" = ul-lab ] || [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
	git apply --check "${SRC_UL_MURU_DTS_PATCH}"
	git apply "${SRC_UL_MURU_DTS_PATCH}"
fi
if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	git apply --check "${SRC_FACTORY38_WRITE_GATE_PATCH}"
	git apply "${SRC_FACTORY38_WRITE_GATE_PATCH}"
fi
install -m 0644 -- "${SRC_MAC80211_PATCH}" \
	"${OPENWRT_DIR}/package/kernel/mac80211/patches/subsys/995-cr6608-txpower-trace.patch"
verify_cr6608_device_tree_gate
ok "official origin, commit, and pinned signing keys verified"

say "[2/10] Updating and installing release feeds"
update_release_feeds
pin_feed_commits
./scripts/feeds install -a
verify_feed_commits
stage_luci_wireless_txpower_patch
normalize_source_permissions
ok "feeds ready, LuCI txpower preservation patch staged, and source permissions normalized"

say "[3/10] Recording inputs and installing the verified mt76 patch pair"
write_input_manifest "${INPUT_MANIFEST}"
RAMIPS_PATCH_DIR="${OPENWRT_DIR}/target/linux/ramips/patches-6.12"
mkdir -p "${RAMIPS_PATCH_DIR}"
install -m 0644 -- "${SRC_DSA_EEE_PATCH}" \
	"${RAMIPS_PATCH_DIR}/$(basename "${SRC_DSA_EEE_PATCH}")"
cmp -s "${SRC_DSA_EEE_PATCH}" \
	"${RAMIPS_PATCH_DIR}/$(basename "${SRC_DSA_EEE_PATCH}")" || \
	die "Staged MT7621 early-EEE patch differs from the recorded input"
install -m 0644 -- "${SRC_UBI_INITRAMFS_GUARD_PATCH}" \
	"${RAMIPS_PATCH_DIR}/$(basename "${SRC_UBI_INITRAMFS_GUARD_PATCH}")"
cmp -s "${SRC_UBI_INITRAMFS_GUARD_PATCH}" \
	"${RAMIPS_PATCH_DIR}/$(basename "${SRC_UBI_INITRAMFS_GUARD_PATCH}")" || \
	die "Staged embedded-initramfs UBI guard differs from the recorded input"
UHTTPD_PATCH_DIR="${OPENWRT_DIR}/package/network/services/uhttpd/patches"
mkdir -p "${UHTTPD_PATCH_DIR}"
rm -f -- "${UHTTPD_PATCH_DIR}"/994-uhttpd-smartap-no-store.patch
install -m 0644 -- "${SRC_UHTTPD_PATCH}" \
	"${UHTTPD_PATCH_DIR}/$(basename "${SRC_UHTTPD_PATCH}")"
cmp -s "${SRC_UHTTPD_PATCH}" \
	"${UHTTPD_PATCH_DIR}/$(basename "${SRC_UHTTPD_PATCH}")" || \
	die "Staged uhttpd canonical-routing patch differs from the recorded input"
# Every static response is explicitly marked no-store by the staged uhttpd
# patch. Every authenticated CGI emits no-store itself as well, so neither live
# telemetry nor the management UI payload is retained between browser visits.
MT76_PATCH_DIR="${OPENWRT_DIR}/package/kernel/mt76/patches"
mkdir -p "${MT76_PATCH_DIR}"
rm -f "${MT76_PATCH_DIR}"/*mt7915-cr6608-rf-*.patch \
	"${MT76_PATCH_DIR}"/*mt7915-cr6608-factory38-*.patch \
	"${MT76_PATCH_DIR}"/*mt7915-cr6608-firmware-eeprom-shadow.patch \
	"${MT76_PATCH_DIR}"/*mt7915-cr6608-ul-muru-experimental.patch \
	"${MT76_PATCH_DIR}"/*mt7915-cr6608-ul-muru-stock-policy.patch \
	"${MT76_PATCH_DIR}"/*mt7915-cr6608-ul-muru-vendor-*.patch \
	"${MT76_PATCH_DIR}"/zzzzzz-*-mt7915-cr6608-muru-*.patch
cp -v -- "${SRC_PATCH}" "${MT76_PATCH_DIR}/$(basename "${SRC_PATCH}")"
cp -v -- "${SRC_FACTORY38_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_FACTORY38_PATCH}")"
cp -v -- "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}")"
cp -v -- "${SRC_UL_MURU_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_UL_MURU_PATCH}")"
cp -v -- "${SRC_UL_MURU_STOCK_POLICY_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_UL_MURU_STOCK_POLICY_PATCH}")"
for muru_port_patch in "${SRC_MURU_PORT_PATCHES[@]}"; do
	cp -v -- "${muru_port_patch}" \
		"${MT76_PATCH_DIR}/$(basename "${muru_port_patch}")"
done
cmp -s "${SRC_PATCH}" "${MT76_PATCH_DIR}/$(basename "${SRC_PATCH}")" || \
	die "Staged mt76 patch differs from the recorded input"
cmp -s "${SRC_FACTORY38_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_FACTORY38_PATCH}")" || \
	die "Staged Factory-38 patch differs from the recorded input"
cmp -s "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}")" || \
	die "Staged firmware EEPROM shadow patch differs from the recorded input"
cmp -s "${SRC_UL_MURU_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_UL_MURU_PATCH}")" || \
	die "Staged experimental UL MURU patch differs from the recorded input"
cmp -s "${SRC_UL_MURU_STOCK_POLICY_PATCH}" \
	"${MT76_PATCH_DIR}/$(basename "${SRC_UL_MURU_STOCK_POLICY_PATCH}")" || \
	die "Staged MediaTek-vendor UL MURU baseline patch differs from the recorded input"
for muru_port_patch in "${SRC_MURU_PORT_PATCHES[@]}"; do
	cmp -s "${muru_port_patch}" \
		"${MT76_PATCH_DIR}/$(basename "${muru_port_patch}")" ||
		die "Staged MediaTek 25.12 MURU port patch differs from the recorded input"
done
mapfile -t cr6608_muru_port_patches < <(
	find "${MT76_PATCH_DIR}" -maxdepth 1 -type f \
		-name 'zzzzzz-*-mt7915-cr6608-muru-*.patch' -print
)
[ "${#cr6608_muru_port_patches[@]}" -eq 8 ] ||
	die "Expected exactly eight ordered MediaTek 25.12 MURU port patches"
mapfile -t cr6608_rf_patches < <(
	find "${MT76_PATCH_DIR}" -maxdepth 1 -type f -name '*mt7915-cr6608-rf-*.patch' -print
)
[ "${#cr6608_rf_patches[@]}" -eq 1 ] || die "Expected exactly one CR6608 RF patch"
mapfile -t cr6608_factory38_patches < <(
	find "${MT76_PATCH_DIR}" -maxdepth 1 -type f -name '*mt7915-cr6608-factory38-*.patch' -print
)
[ "${#cr6608_factory38_patches[@]}" -eq 1 ] || \
	die "Expected exactly one CR6608 Factory-38 companion patch"
mapfile -t cr6608_firmware_shadow_patches < <(
	find "${MT76_PATCH_DIR}" -maxdepth 1 -type f -name '*mt7915-cr6608-firmware-eeprom-shadow.patch' -print
)
[ "${#cr6608_firmware_shadow_patches[@]}" -eq 1 ] || \
	die "Expected exactly one CR6608 firmware EEPROM shadow patch"
if grep -RIsaEq 'cr6608_rf_(30|35)dbm|CR6608-RF-(30|35)DBM|MAX_HALF_DBM[[:space:]]+76|CAP_MCS_HALF[[:space:]]+72|CAP_RU_HALF[[:space:]]+68' "${MT76_PATCH_DIR}"; then
	die "Stale or unsafe CR6608 RF implementation is present"
fi
ok "input manifest recorded and final mt76 patch staged"

say "[4/10] Installing the final Smart AP overlay with deterministic modes"
rm -rf "${OPENWRT_DIR}/files"
mkdir -p "${OPENWRT_DIR}/files"
cp -a "${SRC_FILES}/." "${OPENWRT_DIR}/files/"
sh "${SRC_PROFILE_APPLIER}" "${BUILD_PROFILE}" "${OPENWRT_DIR}/files" ||
	die "Could not apply the selected ${BUILD_PROFILE} build profile"
if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	sh "${SRC_RETAIL_COMMISSIONING_STAGE}" \
		"${OPENWRT_DIR}/files" "${RETAIL_COMMISSIONING_KEY}" |
		grep -qx 'retail_commissioning_key_stage=pass' ||
		die "Could not stage the Retail RAM-only commissioning key"
fi
[ ! -e "${OPENWRT_DIR}/files/usr/sbin/cr6608-mndp-advertise" ] && \
	[ ! -L "${OPENWRT_DIR}/files/usr/sbin/cr6608-mndp-advertise" ] || \
	die "Opaque MNDP overlay binary is forbidden; use the source-built package"
rm -f -- \
	"${OPENWRT_DIR}/files/usr/sbin/cr6608-factory38-stage" \
	"${OPENWRT_DIR}/files/etc/cr6608-factory38-writegate.marker" \
	"${OPENWRT_DIR}/files/etc/uci-defaults/01-cr6608-factory38-maintenance"
if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	install -D -m 0755 -- "${SRC_FACTORY38_STAGE}" \
		"${OPENWRT_DIR}/files/usr/sbin/cr6608-factory38-stage"
	install -D -m 0644 -- "${SRC_FACTORY38_MARKER}" \
		"${OPENWRT_DIR}/files/etc/cr6608-factory38-writegate.marker"
	install -D -m 0755 -- "${SRC_FACTORY38_WIFI_DISABLE}" \
		"${OPENWRT_DIR}/files/etc/uci-defaults/01-cr6608-factory38-maintenance"
fi
find "${OPENWRT_DIR}/files" -type d -exec chmod 0755 {} +
find "${OPENWRT_DIR}/files" -type f -exec chmod 0644 {} +
for executable_dir in \
	etc/init.d etc/hotplug.d etc/rc.d etc/uci-defaults lib/preinit usr/bin usr/sbin usr/libexec www/cgi-bin; do
	[ ! -d "${OPENWRT_DIR}/files/${executable_dir}" ] || \
		find "${OPENWRT_DIR}/files/${executable_dir}" -type f -exec chmod 0755 {} +
done
[ ! -f "${OPENWRT_DIR}/files/usr/libexec/cr6608-private-runtime" ] || \
	chmod 0644 "${OPENWRT_DIR}/files/usr/libexec/cr6608-private-runtime"
for executable_file in \
	etc/rc.local sbin/sysupgrade lib/netifd/wireless/mac80211.sh; do
	[ ! -f "${OPENWRT_DIR}/files/${executable_file}" ] || \
		chmod 0755 "${OPENWRT_DIR}/files/${executable_file}"
done
[ ! -d "${OPENWRT_DIR}/files/etc/config" ] || \
	find "${OPENWRT_DIR}/files/etc/config" -type f -exec chmod 0600 {} +
[ ! -f "${OPENWRT_DIR}/files/etc/shadow" ] || \
	chmod 0600 "${OPENWRT_DIR}/files/etc/shadow"
if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	chmod 0600 "${OPENWRT_DIR}/files/etc/dropbear/authorized_keys"
	chmod 0400 "${OPENWRT_DIR}/files/etc/cr6608-retail-commissioning-ram"
	grep -Eq "^[[:space:]]*option PasswordAuth 'off'$" \
		"${OPENWRT_DIR}/files/etc/config/dropbear" ||
		die "Commissioning image password authentication is not disabled"
	grep -Eq "^[[:space:]]*option RootPasswordAuth 'off'$" \
		"${OPENWRT_DIR}/files/etc/config/dropbear" ||
		die "Commissioning image root password authentication is not disabled"
else
	[ ! -e "${OPENWRT_DIR}/files/etc/cr6608-retail-commissioning-ram" ] &&
		[ ! -e "${OPENWRT_DIR}/files/etc/dropbear/authorized_keys" ] ||
		die "Non-commissioning image contains a factory access path"
fi
[ ! -f "${OPENWRT_DIR}/files/etc/crontabs/root" ] || \
	chmod 0600 "${OPENWRT_DIR}/files/etc/crontabs/root"
rm -f "${OPENWRT_DIR}/files/lib/firmware/README.regulatory.txt"
printf '%s\n' "${BUILD_TIME}" > "${OPENWRT_DIR}/files/etc/smartap-build-time"
printf '%s\n' "${BUILD_EPOCH}" > "${OPENWRT_DIR}/files/etc/smartap-time-anchor"
assert_required_links "${OPENWRT_DIR}/files"
printf '%s\n' "${EXPECTED_MODULE_LINE}" | \
	cmp -s - "${OPENWRT_DIR}/files/etc/modules.d/mt7915e" || \
	die "Staged ${BUILD_PROFILE} overlay has an invalid mt7915e module line"
[ ! -e "${OPENWRT_DIR}/files/etc/modprobe.d" ] && \
	[ ! -L "${OPENWRT_DIR}/files/etc/modprobe.d" ] || \
	die "Staged overlay contains a stale modprobe.d path"
if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	cmp -s "${SRC_FACTORY38_STAGE}" \
		"${OPENWRT_DIR}/files/usr/sbin/cr6608-factory38-stage" ||
		die "Staged Factory-38 writer differs from the gated source input"
	cmp -s "${SRC_FACTORY38_MARKER}" \
		"${OPENWRT_DIR}/files/etc/cr6608-factory38-writegate.marker" ||
		die "Staged Factory-38 maintenance marker differs from its source"
else
	[ ! -e "${OPENWRT_DIR}/files/usr/sbin/cr6608-factory38-stage" ] ||
		die "Normal image must not contain the Factory writer"
	[ ! -e "${OPENWRT_DIR}/files/etc/cr6608-factory38-writegate.marker" ] ||
		die "Normal image must not contain the Factory write marker"
fi
ok "overlay copied, package public key installed, modes normalized, and symlinks asserted"

say "[5/10] Expanding the exact CR6608 package seed"
cp -- "${SRC_SEED}" "${OPENWRT_DIR}/.config"
chmod 0644 "${OPENWRT_DIR}/.config"
if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	printf '%s\n' \
		'CONFIG_PACKAGE_nand-utils=y' \
		'CONFIG_PACKAGE_flock=y' >> "${OPENWRT_DIR}/.config"
fi
make defconfig
grep -q "^CONFIG_TARGET_ramips_mt7621_DEVICE_${DEVICE_PROFILE}=y" \
	"${OPENWRT_DIR}/.config" || die "CR6608 profile was not selected after defconfig"
grep -q '^CONFIG_SIGNED_PACKAGES=y' "${OPENWRT_DIR}/.config" || \
	die "OpenWrt package signing is not enabled"
grep -q '^CONFIG_SIGNATURE_CHECK=y' "${OPENWRT_DIR}/.config" || \
	die "Runtime sysupgrade signature enforcement is not enabled"
grep -q '^CONFIG_PACKAGE_ucert=y' "${OPENWRT_DIR}/.config" || \
	die "Target-side ucert signature verifier was not selected"
grep -q '^CONFIG_PACKAGE_openwrt-keyring=y' "${OPENWRT_DIR}/.config" || \
	die "Target trusted firmware keyring was not selected"
grep -q '^CONFIG_USE_APK=y' "${OPENWRT_DIR}/.config" || \
	die "OpenWrt 25.12.5 is not using its default APK package manager"
grep -q '^CONFIG_PACKAGE_wpad-openssl=y' "${OPENWRT_DIR}/.config" || \
	die "wpad-openssl was not selected"
for discovery_package in cr6608-mndp lldpd; do
	grep -q "^CONFIG_PACKAGE_${discovery_package}=y" "${OPENWRT_DIR}/.config" || \
		die "required source-backed discovery package is absent: ${discovery_package}"
done
grep -q '^CONFIG_LLDPD_WITH_CDP=y' "${OPENWRT_DIR}/.config" || \
	die "lldpd was built without the dashboard-advertised CDP support"
for ax_package in \
	kmod-cfg80211 \
	kmod-mac80211 \
	kmod-mt7915e \
	kmod-mt7915-firmware \
	hostapd-common; do
	grep -q "^CONFIG_PACKAGE_${ax_package}=y" "${OPENWRT_DIR}/.config" || \
		die "required upstream Wi-Fi 6 component is absent: ${ax_package}"
done
grep -q '^CONFIG_PACKAGE_coreutils-stat=y' "${OPENWRT_DIR}/.config" || \
	die "coreutils-stat was not selected for runtime ownership checks"
grep -q '^CONFIG_PACKAGE_kmod-nft-bridge=y' "${OPENWRT_DIR}/.config" || \
	die "kmod-nft-bridge was not selected for the rescue security boundary"
! grep -q '^CONFIG_PACKAGE_luci-app-package-manager=y' "${OPENWRT_DIR}/.config" || \
	die "unguarded stock LuCI package manager was selected"
for guarded_luci_component in luci-light libustream-mbedtls px5g-mbedtls; do
	grep -q "^CONFIG_PACKAGE_${guarded_luci_component}=y" "${OPENWRT_DIR}/.config" || \
		die "guarded LuCI component was not selected: ${guarded_luci_component}"
done
for forbidden_luci_meta in luci luci-ssl; do
	! grep -q "^CONFIG_PACKAGE_${forbidden_luci_meta}=y" "${OPENWRT_DIR}/.config" || \
		die "LuCI meta package reselected stock package manager: ${forbidden_luci_meta}"
done
if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	grep -q '^CONFIG_PACKAGE_nand-utils=y' "${OPENWRT_DIR}/.config" ||
		die "maintenance image lacks flash_erase/nandwrite from nand-utils"
	grep -q '^CONFIG_PACKAGE_flock=y' "${OPENWRT_DIR}/.config" ||
		die "maintenance image lacks the required flock transaction lock"
fi
./scripts/diffconfig.sh > "${DIFFCONFIG_LOG}"
ok "device profile and package seed selected"

say "[6/10] Downloading all sources"
command -v aria2c >/dev/null 2>&1 || \
	die "aria2c is required for resilient verified source downloads"
# OpenWrt's download target may bootstrap the host zstd tool.  Building that
# prerequisite serially avoids a host-tool race observed in an otherwise clean
# parallel source download while leaving target compilation parallel below.
make tools/zstd/compile -j1 V=s 2>&1 | tee "${HOST_ZSTD_LOG}"
test -x staging_dir/host/bin/zstd || \
	die "serial host zstd bootstrap did not produce staging_dir/host/bin/zstd"
make CONFIG_DOWNLOAD_TOOL_CUSTOM=aria2c download -j"$(nproc)" 2>&1 | tee "${DOWNLOAD_LOG}"
ok "all source tarballs downloaded"

say "[7/10] Cleaning target components and proving uhttpd, wireless and kernel preparations"
make package/kernel/mt76/clean V=s
make package/kernel/mac80211/clean V=s
make package/firmware/wireless-regdb/clean V=s
make package/network/services/uhttpd/clean V=s
make target/linux/clean V=s
mapfile -t stale_uhttpd_dirs < <(
	find "${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl" \
		-maxdepth 1 -type d -name 'uhttpd-*' -print | sort
)
[ "${#stale_uhttpd_dirs[@]}" -eq 0 ] ||
	die "uhttpd clean left a stale prepared source directory"
make package/network/services/uhttpd/prepare V=s 2>&1 | tee "${UHTTPD_LOG}"
mapfile -t prepared_uhttpd_dirs < <(
	find "${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl" \
		-maxdepth 1 -type d -name 'uhttpd-*' -print | sort
)
[ "${#prepared_uhttpd_dirs[@]}" -eq 1 ] ||
	die "Expected exactly one prepared uhttpd source directory"
[ "$(basename -- "${prepared_uhttpd_dirs[0]}")" = 'uhttpd-2026.06.16~7b1bec45' ] ||
	die "Prepared uhttpd source does not match the pinned revision"
mapfile -t prepared_uhttpd_final_stamps < <(
	find "${prepared_uhttpd_dirs[0]}" -maxdepth 1 -type f \
		-name '.prepared_*' ! -name '*_check' -print | sort
)
mapfile -t prepared_uhttpd_check_stamps < <(
	find "${prepared_uhttpd_dirs[0]}" -maxdepth 1 -type f \
		-name '.prepared_*_check' -print | sort
)
[ "${#prepared_uhttpd_final_stamps[@]}" -eq 1 ] &&
	[ "${#prepared_uhttpd_check_stamps[@]}" -eq 1 ] &&
	[ "${prepared_uhttpd_check_stamps[0]}" = "${prepared_uhttpd_final_stamps[0]}_check" ] ||
	die "Prepared uhttpd source lacks one linked final/check stamp pair"
python3 - "${prepared_uhttpd_dirs[0]}" <<'PY' || \
	die "prepared uhttpd source failed the canonical-routing and connection-safety gate"
from pathlib import Path
import sys

source = Path(sys.argv[1])
client = (source / "client.c").read_text(encoding="utf-8")
file_source = (source / "file.c").read_text(encoding="utf-8")
proc = (source / "proc.c").read_text(encoding="utf-8")
header_source = (source / "uhttpd.h").read_text(encoding="utf-8")
guard = "if (r->transfer_chunked || r->content_length > 0)"
header_start = client.index("void uh_http_header(")
header_end = client.index("\nstatic void uh_connection_close", header_start)
header = client[header_start:header_end]
if header.count(guard) != 1 or header.index(guard) > header.index("if (!uh_use_chunked(cl))"):
    raise SystemExit("unread-body close decision is not made before response framing")
done_start = client.index("void uh_request_done(")
done_end = client.index("\nvoid __printf", done_start)
request_done = client[done_start:done_end]
if request_done.count(guard) != 1 or request_done.index(guard) > request_done.index("if (!conf.http_keepalive"):
    raise SystemExit("unread-body safety guard is not applied before keepalive reuse")
if client.count(guard) != 2:
    raise SystemExit("unread-body close guard is missing or duplicated")
if header.count('!uh_proc_header_exists(cl, "Strict-Transport-Security")') != 1:
    raise SystemExit("CGI-aware TLS-only HSTS guard is missing or duplicated")
if header.count("Strict-Transport-Security: max-age=31536000") != 1:
    raise SystemExit("TLS-only HSTS guard is missing")
if client.count("uh_proc_header_exists(") != 2:
    raise SystemExit("CGI response-header de-duplication call count changed")
for managed_header in (
    "X-Content-Type-Options:",
    "X-Frame-Options:",
    "Referrer-Policy:",
    "Permissions-Policy:",
    "Cross-Origin-Resource-Policy:",
    "Content-Security-Policy:",
):
    if managed_header in client:
        raise SystemExit(f"JSON-managed response header is duplicated in client.c: {managed_header}")
for marker, expected_count in {
    "normalize_dispatch_url": 2,
    "canonpath_lexical(decoded, normalized)": 1,
    "dispatch_find(dispatch_url, NULL)": 1,
    "uh_invoke_handler(cl, d, dispatch_url, NULL)": 1,
    "cl->dispatch.no_cache = true;": 1,
    "Cache-Control: no-store, no-cache, must-revalidate": 1,
}.items():
    actual_count = file_source.count(marker)
    if actual_count != expected_count:
        raise SystemExit(
            f"prepared uhttpd source has {actual_count} copies of {marker}, "
            f"expected {expected_count}"
        )
for marker in (
    "bool uh_proc_header_exists(struct client *cl, const char *name)",
    "cl->dispatch.free != proc_free",
    "p->r.header_cb || !p->hdr.head",
    "!strcasecmp(blobmsg_name(cur), name)",
):
    if proc.count(marker) != 1:
        raise SystemExit(f"prepared uhttpd proc source lacks one exact marker: {marker}")
if header_source.count(
    "bool uh_proc_header_exists(struct client *cl, const char *name);"
) != 1:
    raise SystemExit("prepared uhttpd header lacks one de-duplication prototype")
PY
make package/firmware/wireless-regdb/prepare V=s 2>&1 | tee "${REGDB_LOG}"
make target/linux/prepare V=s 2>&1 | tee "${MT76_LOG}"
grep -Fq 'UBI: skip auto-attach for embedded initramfs' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/linux-6.12.94/drivers/mtd/ubi/build.c" || \
	die "prepared kernel lacks the embedded-initramfs UBI auto-attach guard"
# target/linux/prepare recreates the whole target kernel build directory.
# Prepare mt76 afterwards so both prepared trees exist for the trace gates.
make package/kernel/mt76/prepare V=s 2>&1 | tee -a "${MT76_LOG}"
mapfile -t prepared_mt76_dirs < <(
	find "${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621" \
		-maxdepth 1 -type d -name 'mt76-*' -print
)
[ "${#prepared_mt76_dirs[@]}" -eq 1 ] ||
	die "Expected exactly one prepared mt76 source directory"
sh "${MURU_FIRMWARE_VERIFY}" "${prepared_mt76_dirs[0]}" | \
	grep -qx 'mt7915_muru_firmware_baseline=pass' ||
	die "Pinned MT7915 ROM/WM/WA firmware baseline verification failed"
make package/kernel/mac80211/prepare V=s 2>&1 | tee -a "${MT76_LOG}"
grep -Rqs 'mt7915_cr6608_poll_sku_readback' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks verified MCU SKU readback"
grep -Rqs 'mt7915_cr6608_rf_rollback_sku' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks verified conservative rollback"
grep -Rqs 'CR6608_FACTORY38_TARGET_2G' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks the exact 2.4 GHz persisted target path"
grep -Rqs 'CR6608_FACTORY38_TARGET_5G' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks the exact 5 GHz persisted target path"
grep -Rqs 'cr6608_factory38_persisted_match' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks persisted Factory-38 telemetry"
grep -Rqs 'activating the audited volatile 38 dBm target override' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks the volatile target override"
grep -Rqs 'CR6608-RF firmware EEPROM shadow active' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks the firmware EEPROM shadow"
grep -Rqs 'mt7915_cr6608_rf_request_enabled(dev)' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared Factory-38 EEPROM path is not protected by the CR6608 gate"
grep -Rqs 'mt7915_mcu_schedule_full_recovery' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks fail-closed full recovery"
grep -Rqs 'reconfig_verified_generation' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mt76-"* || \
	die "prepared mt76 source lacks verified recovery-generation handoff"
for muru_prepared_marker in \
	CR6608_MURU_MUMIMO_UL \
	mt7915_cr6608_muru_fault_latch \
	cr6608_ul_muru_sta_rec_response_ok \
	cr6608_ul_muru_sta_rec_timeout; do
	grep -Rqs "${muru_prepared_marker}" "${prepared_mt76_dirs[0]}" ||
		die "prepared mt76 source lacks MURU marker: ${muru_prepared_marker}"
done
grep -Rqs 'CR6608-TXTRACE stage=mac80211' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mac80211-regular" || \
	die "prepared kernel source does not contain the mac80211 trace marker"
grep -Rqs 'DEBUGFS_ADD(txpower_state)' \
	"${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/mac80211-regular" || \
	die "prepared mac80211 source lacks the txpower_state debugfs endpoint"
if grep -RIsaEq 'cr6608_rf_(30|35)dbm|CR6608-RF-(30|35)DBM|MAX_HALF_DBM[[:space:]]+76|CAP_MCS_HALF[[:space:]]+72|CAP_RU_HALF[[:space:]]+68' "${OPENWRT_DIR}/build_dir"; then
	die "mt76 prepared source contains a stale or unsafe CR6608 RF implementation"
fi
ok "mt76 patch applied to the pinned v25.12.5 source"

say "[8/10] Full verbose build: make -j\$(nproc) V=s"
if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
	# Arm destructive cleanup only now: the global build flock is already held,
	# source-test-only has already exited, and this invocation is about to create
	# its own writable-Factory flashable intermediates.
	MAINTENANCE_BIN_CLEANUP_ARMED=1
	remove_maintenance_flashables_from_bin || \
		die 'Could not clear stale maintenance flashables before the locked build'
fi
make -j$(nproc) V=s 2>&1 | tee "${BUILD_LOG}"
# A failed make is covered by the EXIT-time bin sweep. After a successful
# maintenance build, move the forbidden flashables out of bin before any later
# validation can fail and leave them discoverable.
quarantine_maintenance_flashables
normal_vmlinux="${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/vmlinux"
initramfs_vmlinux="${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/vmlinux-initramfs"
[ -s "${normal_vmlinux}" ] && [ -s "${initramfs_vmlinux}" ] ||
	die "Normal or embedded-initramfs kernel proof input is missing"
grep -aFq 'UBI: auto-attach mtd%d' "${normal_vmlinux}" ||
	die "Normal flash kernel lost its persistent-root UBI auto-attach path"
! grep -aFq 'UBI: skip auto-attach for embedded initramfs' "${normal_vmlinux}" ||
	die "Normal flash kernel was compiled with the embedded-initramfs guard active"
grep -aFq 'UBI: skip auto-attach for embedded initramfs' "${initramfs_vmlinux}" ||
	die "Embedded-initramfs kernel lacks the compiled UBI auto-attach guard"
! grep -aFq 'UBI: auto-attach mtd%d' "${initramfs_vmlinux}" ||
	die "Embedded-initramfs kernel still contains the reachable UBI auto-attach path"
ok "normal UBI boot path retained and embedded-initramfs auto-attach compiled out"
mac80211_module="${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/root-ramips/lib/modules/6.12.94/mac80211.ko"
[ -s "${mac80211_module}" ] || die "built mac80211 module is absent"
grep -aq 'CR6608-TXTRACE stage=mac80211' "${mac80211_module}" || \
	die "built mac80211 module lacks the instrumentation marker"
grep -aq 'txpower_state' "${mac80211_module}" || \
	die "built mac80211 module lacks its txpower_state debugfs endpoint"
mt7915_module="${OPENWRT_DIR}/build_dir/target-mipsel_24kc_musl/root-ramips/lib/modules/6.12.94/mt7915e.ko"
[ -s "${mt7915_module}" ] || die "built mt7915e module is absent"
grep -aFq 'CR6608-RF-38DBM LAB enabled' "${mt7915_module}" || \
	die "built mt7915e module lacks the gated Factory-38 marker"
grep -aFq 'rate-SKU MCU witness verified' "${mt7915_module}" || \
	die "built mt7915e module lacks the MCU readback witness"
grep -aFq 'SKU rollback verification failed' "${mt7915_module}" || \
	die "built mt7915e module lacks verified rollback handling"
grep -aFq 'cr6608_rf_band0_mcu_result' "${mt7915_module}" || \
	die "built mt7915e module lacks read-only MCU telemetry"
grep -aFq 'cr6608_factory38_persisted_match' "${mt7915_module}" ||
	die "built mt7915e module lacks read-only persisted-Factory telemetry"
grep -aFq 'activating the audited volatile 38 dBm target override' "${mt7915_module}" ||
	die "built mt7915e module lacks the volatile target override marker"
grep -aFq 'CR6608-RF firmware EEPROM shadow active' "${mt7915_module}" ||
	die "built mt7915e module lacks the firmware EEPROM shadow marker"
for muru_module_marker in \
	'CR6608 MediaTek MURU candidate enabled' \
	'cr6608_muru_mask' \
	'sta_rec_response_ok=' \
	'sta_rec_timeout='; do
	grep -aFq "${muru_module_marker}" "${mt7915_module}" ||
		die "built mt7915e module lacks MURU marker: ${muru_module_marker}"
done
ok "full source build finished without fallback"

say "[9/10] Running pre-publication image gates"
assert_official_checkout
verify_cr6608_device_tree_gate
input_recheck="$(mktemp "${LOG_DIR}/.build-inputs-recheck.XXXXXX")"
write_input_manifest "${input_recheck}"
if ! cmp -s "${INPUT_MANIFEST}" "${input_recheck}"; then
	diff -u "${INPUT_MANIFEST}" "${input_recheck}" >&2 || true
	rm -f -- "${input_recheck}"
	die "Seed, patch, overlay, or build scripts changed during the build"
fi
rm -f -- "${input_recheck}"
verify_source_manifest_unchanged "Source changed after its bound test run"

if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
	images=("${MAINTENANCE_SYSUPGRADE_ARTIFACT}")
	firmware_images=("${MAINTENANCE_FIRMWARE_ARTIFACT}")
	[ -s "${images[0]}" ] && [ -s "${firmware_images[0]}" ] || \
		die 'Tracked maintenance flashable inspection references are unavailable'
else
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
fi
mapfile -t initramfs_images < <(find "${BIN_DIR}" -maxdepth 1 -type f \
	-name "*${DEVICE_PROFILE}*initramfs-kernel.bin" -print)
[ "${#initramfs_images[@]}" -eq 1 ] || {
	printf 'Expected exactly one CR6608 initramfs image, found %s\n' \
		"${#initramfs_images[@]}" >&2
	printf '%s\n' "${initramfs_images[@]}" >&2
	exit 1
}
package_manifest="${BIN_DIR}/openwrt-ramips-mt7621-${DEVICE_PROFILE}.manifest"
[ -s "${package_manifest}" ] || die "OpenWrt package manifest is absent"
awk '$1 == "kmod-nft-bridge" { found++ } END { exit(found == 1 ? 0 : 1) }' \
	"${package_manifest}" || die "built package manifest lacks exactly one kmod-nft-bridge"
for discovery_package in cr6608-mndp lldpd; do
	awk -v package="${discovery_package}" \
		'$1 == package { found++ } END { exit(found == 1 ? 0 : 1) }' \
		"${package_manifest}" || \
		die "built package manifest lacks exactly one ${discovery_package}"
done
awk '$1 == "ucert" { found++ } END { exit(found == 1 ? 0 : 1) }' \
	"${package_manifest}" || die "built package manifest lacks exactly one ucert"
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
capture_image_inspection_hashes "${images[0]}" "${firmware_images[0]}" \
	"${initramfs_images[0]}" "${package_manifest}"
if ! INSPECTOR_EXECUTED_SHA256="$(read_regular_file_sha256 "${INSPECTOR}")"; then
	die 'Image inspector hash could not be pinned before execution'
fi
if ! CR6608_FACTORY38_BUILD_MODE="${FACTORY38_BUILD_MODE}" \
	CR6608_RETAIL_COMMISSIONING_MODE="${RETAIL_COMMISSIONING_MODE}" \
	CR6608_BUILD_PROFILE="${BUILD_PROFILE}" \
	bash "${INSPECTOR}" "${images[0]}" "${firmware_images[0]}" \
	"${initramfs_images[0]}" "${OPENWRT_DIR}" "${OPENWRT_DIR}/files" \
	2>&1 | tee "${INSPECTION_LOG}"; then
	die 'Pre-publication image inspector execution failed'
fi
if ! inspector_after_sha256="$(read_regular_file_sha256 "${INSPECTOR}")"; then
	die 'Image inspector hash could not be recomputed after execution'
fi
[ "${inspector_after_sha256}" = "${INSPECTOR_EXECUTED_SHA256}" ] || \
	die 'Image inspector changed while it was executing'
grep -qx 'image_integrity_gate_status=pass' "${INSPECTION_LOG}" || \
	die "Pre-publication inspection did not report success"
grep -qx 'retail_security_gate_status=blocked_pending_unique_device_provisioning' \
	"${INSPECTION_LOG}" || die "Retail unique-device provisioning gate is missing or unsafe"
grep -Fqx "artifact_profile=${ARTIFACT_PROFILE_LABEL}" "${INSPECTION_LOG}" ||
	die "Inspector did not bind the selected non-sale artifact profile"
grep -qx 'sale_ready=NO' "${INSPECTION_LOG}" ||
	die "Inspector emitted an unsafe sale readiness state"
grep -Fqx "retail_radio_gate_status=${RETAIL_RADIO_GATE_STATUS}" \
	"${INSPECTION_LOG}" || die "Retail radio gate classification is missing or unsafe"
grep -qx 'release_gate_status=blocked_pending_router_runtime_and_external_rf_verification' \
	"${INSPECTION_LOG}" || die "Release gate classification is missing or unsafe"
grep -Fqx "factory38_build_mode=${FACTORY38_BUILD_MODE}" "${INSPECTION_LOG}" ||
	die "Inspector did not verify the selected Factory-38 build mode"
grep -Fqx "retail_commissioning_mode=${RETAIL_COMMISSIONING_MODE}" \
	"${INSPECTION_LOG}" || die "Inspector did not verify the commissioning mode"
if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	grep -Fqx 'retail_commissioning_access_gate_status=pass_ed25519_public_key_password_auth_disabled' \
		"${INSPECTION_LOG}" || die "Inspector did not verify commissioning access isolation"
else
	grep -Fqx 'retail_commissioning_access_gate_status=not_present' \
		"${INSPECTION_LOG}" || die "Inspector found an unexpected commissioning access path"
fi
grep -Fqx 'initramfs_rootfs_gate_status=pass' "${INSPECTION_LOG}" ||
	die "Inspector did not bind and verify the initramfs rootfs"
grep -Fqx 'initramfs_lldp_package_gate_status=pass' "${INSPECTION_LOG}" ||
	die "Inspector did not verify the initramfs LLDP package layout"
for bridge_inspection_record in \
	'rescue_nft_bridge_kernel_release=6.12.94' \
	'rescue_nft_bridge_kernel_configs=CONFIG_NETFILTER_FAMILY_BRIDGE=y,CONFIG_NF_TABLES_BRIDGE=m,CONFIG_NFT_BRIDGE_META=m,CONFIG_NFT_BRIDGE_REJECT=m,CONFIG_NF_CONNTRACK_BRIDGE=m' \
	'rescue_nft_bridge_core_module=nf_tables.ko' \
	'rescue_nft_bridge_modules=nf_conntrack_bridge.ko,nft_meta_bridge.ko,nft_reject_bridge.ko' \
	'rescue_nft_bridge_autoload_file=etc/modules.d/nft-bridge' \
	'rescue_nft_bridge_autoloads=nf_conntrack_bridge,nft_meta_bridge,nft_reject_bridge' \
	'rescue_nft_bridge_squashfs_gate_status=pass' \
	'rescue_nft_bridge_initramfs_gate_status=pass' \
	'rescue_nft_bridge_parser_gate=guard_runtime_atomic_precheck' \
	'rescue_nft_bridge_gate_status=pass'; do
	grep -Fqx "${bridge_inspection_record}" "${INSPECTION_LOG}" || \
		die "Inspector did not verify the exact rescue nft bridge image contract: ${bridge_inspection_record}"
done
verify_image_inspection_hashes_unchanged "${images[0]}" "${firmware_images[0]}" \
	"${initramfs_images[0]}" "${package_manifest}"
if ! INSPECTION_LOG_VERIFIED_SHA256="$(read_regular_file_sha256 "${INSPECTION_LOG}")"; then
	die 'Gate-passing image inspection log hash could not be pinned'
fi
verify_inspection_attestation_unchanged
ok "sysupgrade reference, initramfs bytes, package key, overlay, size, and RF gates passed"
if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
	# The inspector consumed private quarantined references. EXIT cleanup and the
	# guarded bin sweep also cover every earlier failure path.
	cleanup_maintenance_flashable_staging || \
		die 'maintenance flashable quarantine could not be removed'
	remove_maintenance_flashables_from_bin || \
		die 'maintenance flashables remained in the public build tree'
	ok "maintenance-only flashable build artifacts removed after inspection"
fi

if [ "${FACTORY38_BUNDLE_ENABLED}" = 1 ]; then
	generate_factory38_bundle
fi

inspection_value() {
	local key="$1"
	awk -v key="${key}" '
		index($0, key "=") == 1 { print substr($0, length(key) + 2); found = 1; exit }
		END { if (!found) exit 1 }
	' "${INSPECTION_LOG}"
}

say "[10/10] Publishing the validated release directory atomically"
verify_source_manifest_unchanged "Source changed before release publication"
verify_trusted_source_bundle_unchanged
[ -s "${SOURCE_TEST_LOG}" ] || die "Bound source test log is missing or empty"
[ -s "${BUILD_LOG}" ] || die "Build log is missing or empty"
PUBLISH_DIR="$(mktemp -d "${RELEASES_DIR}/.publish.XXXXXX")"
PUBLISH_DIR_IDENTITY="$(stat -c '%d:%i' "${PUBLISH_DIR}")"
if [ "${PUBLISH_FLASHABLE_IMAGES}" = 1 ]; then
	cp -- "${images[0]}" "${PUBLISH_DIR}/${FINAL_IMAGE}"
	cp -- "${firmware_images[0]}" "${PUBLISH_DIR}/${COMBINED_IMAGE}"
fi
cp -- "${initramfs_images[0]}" "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
cp -- "${package_manifest}" "${PUBLISH_DIR}/openwrt-package-manifest.txt"
cp -- "${OPENWRT_DIR}/.config" "${PUBLISH_DIR}/openwrt.config"
cp -- "${DIFFCONFIG_LOG}" "${PUBLISH_DIR}/openwrt-diffconfig.txt"
cp -- "${INPUT_MANIFEST}" "${PUBLISH_DIR}/build-inputs.txt"
cp -- "${SOURCE_MANIFEST}" "${PUBLISH_DIR}/source-manifest.txt"
cp -- "${SOURCE_TEST_LOG}" "${PUBLISH_DIR}/source-tests.txt"
cp -- "${BUILD_LOG}" "${PUBLISH_DIR}/build.log"
cp -- "${INSPECTION_LOG}" "${PUBLISH_DIR}/prepublish-inspection.txt"
verify_rescue_real_evidence_unchanged
cp -- "${RESCUE_REAL_EVIDENCE}" \
	"${PUBLISH_DIR}/rescue-real-netns-evidence.txt"
[ "$(sha256sum "${PUBLISH_DIR}/rescue-real-netns-evidence.txt" | awk '{print $1}')" = \
	"${RESCUE_REAL_EVIDENCE_SHA256}" ] || \
	die "Published real rescue evidence differs from the validated input"
verify_ui_evidence_unchanged "UI screenshot evidence changed before publication"
cp -- "${UI_EVIDENCE_MANIFEST}" \
	"${PUBLISH_DIR}/ui-browser-screenshots.sha256"
tar -C "${UI_SCREENSHOT_PARENT}" -cf - .mobile-layout | \
	xz -T0 -9 > "${PUBLISH_DIR}/ui-browser-screenshots.tar.xz"
[ -s "${PUBLISH_DIR}/ui-browser-screenshots.tar.xz" ] || \
	die "UI browser screenshot evidence archive is empty"
verify_ui_evidence_unchanged "UI screenshot evidence changed while its archive was created"
verify_trusted_source_bundle_unchanged
if ! source_kit_create_output="$(
	PYTHONDONTWRITEBYTECODE=1 python3 -I -B "${SOURCE_KIT_TOOL}" create \
		--repo "${SCRIPT_DIR}" \
		--output-dir "${PUBLISH_DIR}" \
		--kit-base "${KIT_BASE_COMMIT}" \
		--auth-fix "${AUTH_FIX_COMMIT}" \
		--build-epoch "${BUILD_EPOCH}" \
		--product-version "${PRODUCT_VERSION}" \
		--canonical-bundle "${VERIFIED_SOURCE_BUNDLE}" \
		--expected-canonical-bundle-sha256 "${TRUSTED_SOURCE_BUNDLE_SHA256}"
)"; then
	die "History-free source kit creation or bundle reproduction failed"
fi
printf '%s\n' "${source_kit_create_output}" > \
	"${PUBLISH_DIR}/source-kit-create.txt"
verify_trusted_source_bundle_unchanged
cmp -s "${PUBLISH_DIR}/source-kit-create.txt" \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Source-kit creation output differs from its published metadata"
for source_kit_artifact in \
	cr6608-source-kit.bundle cr6608-source-kit.tar.xz \
	source-kit-reproduction.txt source-kit-identity.txt \
	source-kit-payload.tsv source-kit-metadata.txt source-kit-create.txt; do
	[ -s "${PUBLISH_DIR}/${source_kit_artifact}" ] && \
		[ -f "${PUBLISH_DIR}/${source_kit_artifact}" ] && \
		[ ! -L "${PUBLISH_DIR}/${source_kit_artifact}" ] || \
		die "Published source-kit artifact is missing or unsafe: ${source_kit_artifact}"
done
grep -Fqx "source_kit_original_commit=${KIT_ORIGINAL_COMMIT}" \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source kit lost the original commit binding"
grep -Fqx "source_kit_original_tree=${KIT_ORIGINAL_TREE}" \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source kit lost the original tree binding"
grep -Fqx "source_kit_container_commit=${KIT_CONTAINER_COMMIT}" \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source-kit root commit differs from the built checkout"
grep -Fqx "source_kit_container_tree=${KIT_CONTAINER_TREE}" \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source-kit tree differs from the built checkout"
grep -Fqx "source_kit_payload_manifest_sha256=${KIT_PAYLOAD_MANIFEST_SHA256}" \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source kit lost the payload-manifest binding"
grep -Fqx 'source_kit_root_commit_count=1' \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source kit is not a one-root history"
grep -Fqx 'source_kit_reproduction_status=pass' \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source kit lacks a successful bundle-clone reproduction"
grep -Fqx 'source_kit_bundle_role=externally-trusted-build-input' \
	"${PUBLISH_DIR}/source-kit-metadata.txt" || \
	die "Published source kit is not the exact externally trusted build input"
source_kit_bundle_heads="$(
	git bundle list-heads "${PUBLISH_DIR}/cr6608-source-kit.bundle"
)" || die "Published source Git bundle cannot list its refs"
[ "${source_kit_bundle_heads}" = \
	"${KIT_CONTAINER_COMMIT} refs/heads/source-kit" ] || \
	die "Published source Git bundle exposes an unexpected commit or ref"
[ "$(sha256sum "${PUBLISH_DIR}/cr6608-source-kit.bundle" | awk '{print $1}')" = \
	"${TRUSTED_SOURCE_BUNDLE_SHA256}" ] || \
	die "Published canonical source bundle differs from the externally verified build input"
verify_ui_evidence_unchanged "UI screenshot evidence changed during source-kit publication"
if [ "${PUBLISH_FLASHABLE_IMAGES}" = 1 ]; then
	chmod 0644 "${PUBLISH_DIR}/${FINAL_IMAGE}" \
		"${PUBLISH_DIR}/${COMBINED_IMAGE}"
fi
chmod 0644 "${PUBLISH_DIR}/${INITRAMFS_IMAGE}" \
	"${PUBLISH_DIR}/openwrt-package-manifest.txt" \
	"${PUBLISH_DIR}/openwrt.config" \
	"${PUBLISH_DIR}/openwrt-diffconfig.txt" \
	"${PUBLISH_DIR}/build-inputs.txt" "${PUBLISH_DIR}/source-manifest.txt" \
	"${PUBLISH_DIR}/source-tests.txt" "${PUBLISH_DIR}/build.log" \
	"${PUBLISH_DIR}/prepublish-inspection.txt" \
	"${PUBLISH_DIR}/rescue-real-netns-evidence.txt" \
	"${PUBLISH_DIR}/ui-browser-screenshots.sha256" \
	"${PUBLISH_DIR}/ui-browser-screenshots.tar.xz" \
	"${PUBLISH_DIR}/cr6608-source-kit.tar.xz" \
	"${PUBLISH_DIR}/cr6608-source-kit.bundle" \
	"${PUBLISH_DIR}/source-kit-reproduction.txt" \
	"${PUBLISH_DIR}/source-kit-identity.txt" \
	"${PUBLISH_DIR}/source-kit-payload.tsv" \
	"${PUBLISH_DIR}/source-kit-metadata.txt" \
	"${PUBLISH_DIR}/source-kit-create.txt"
verify_published_images_match_inspection
verify_inspection_attestation_unchanged "${PUBLISH_DIR}"
if [ "${FACTORY38_BUNDLE_ENABLED}" = 1 ]; then
	bind_factory38_bundle_to_maintenance_image "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"
fi
delivered_source_manifest_sha256="$(
	sha256sum "${PUBLISH_DIR}/source-manifest.txt" | awk '{print $1}'
)"
[ "${delivered_source_manifest_sha256}" = "${SOURCE_MANIFEST_SHA256}" ] || \
	die "Delivered source manifest differs from the manifest bound to the tests"
grep -Fqx 'source_manifest=source-manifest.txt' \
	"${PUBLISH_DIR}/source-tests.txt" ||
	die "Delivered source test log lacks the manifest name binding"
grep -Fqx 'source_manifest_format=cr6608-source-v1' \
	"${PUBLISH_DIR}/source-tests.txt" ||
	die "Delivered source test log lacks the manifest format binding"
grep -Fqx "source_manifest_sha256=${delivered_source_manifest_sha256}" \
	"${PUBLISH_DIR}/source-tests.txt" ||
	die "Delivered source test log is not bound to the delivered source manifest"
delivered_source_test_log_sha256="$(
	sha256sum "${PUBLISH_DIR}/source-tests.txt" | awk '{print $1}'
)"
delivered_build_log_sha256="$(
	sha256sum "${PUBLISH_DIR}/build.log" | awk '{print $1}'
)"
(
	cd "${PUBLISH_DIR}" || exit 1
	sha256sum "${PRIMARY_IMAGE}" > "${PRIMARY_IMAGE}.sha256" || exit 1
	sha256sum -c "${PRIMARY_IMAGE}.sha256" || exit 1
) || die 'Primary image checksum generation or verification failed'
image_sha256="$(awk '{print $1}' "${PUBLISH_DIR}/${PRIMARY_IMAGE}.sha256")"
{
	if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
		printf 'release_status=maintenance_initramfs_ram_boot_only\n'
	else
		printf 'release_status=%s\n' "${RELEASE_STATUS}"
	fi
	printf 'build_profile=%s\n' "${BUILD_PROFILE}"
	printf 'build_execution_mode=%s\n' "${BUILD_EXECUTION_MODE}"
	printf 'artifact_profile=%s\n' "${ARTIFACT_PROFILE_LABEL}"
	printf 'sale_ready=NO\n'
	printf 'release_gate_status=blocked_pending_router_runtime_and_external_rf_verification\n'
	printf 'retail_security_gate_status=blocked_pending_unique_device_provisioning\n'
	printf 'retail_radio_gate_status=%s\n' "${RETAIL_RADIO_GATE_STATUS}"
	printf 'factory38_build_mode=%s\n' "${FACTORY38_BUILD_MODE}"
	printf 'retail_commissioning_mode=%s\n' "${RETAIL_COMMISSIONING_MODE}"
	if [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
		printf 'retail_commissioning_transport=ed25519_public_key_password_auth_disabled\n'
		printf 'retail_commissioning_key_fingerprint=%s\n' \
			"$(ssh-keygen -E sha256 -lf "${RETAIL_COMMISSIONING_KEY}" | awk '{print $2}')"
	fi
	printf 'factory38_persisted_gate=exact_identity_rate_delta_tssi_and_36_target_bytes\n'
	printf 'factory38_current_power_policy=publish_only_verified_mcu_readback\n'
	printf 'legacy_80211b_policy=enabled_on_2g_only\n'
	printf 'inspected_sysupgrade_sha256=%s\n' "${INSPECTED_SYSUPGRADE_SHA256}"
	printf 'inspected_combined_firmware_sha256=%s\n' "${INSPECTED_FIRMWARE_SHA256}"
	printf 'inspected_initramfs_sha256=%s\n' "${INSPECTED_INITRAMFS_SHA256}"
	printf 'inspected_package_manifest_sha256=%s\n' "${INSPECTED_PACKAGE_MANIFEST_SHA256}"
	if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
		printf 'factory_partition_policy=maintenance_initramfs_writable_wifi_forced_disabled_ram_boot_only\n'
	else
		printf 'factory_partition_policy=kernel_read_only\n'
	fi
	printf 'factory38_private_bundle=excluded_from_public_release\n'
	if [ "${FACTORY38_BUNDLE_ENABLED}" = 1 ]; then
		printf 'factory38_private_bundle_export=separate_opt_in_output\n'
	else
		printf 'factory38_private_bundle_export=disabled\n'
	fi
	printf 'factory38_original_sha256=%s\n' "${FACTORY38_ORIGINAL_SHA256}"
	printf 'factory38_original_crc32=963cdfeb\n'
	printf 'factory38_original_block0_sha256=%s\n' "${FACTORY38_ORIGINAL_BLOCK0_SHA256}"
	printf 'factory38_original_block0_crc32=73ba4c38\n'
	printf 'factory38_candidate_sha256=%s\n' "${FACTORY38_CANDIDATE_SHA256}"
	printf 'factory38_candidate_crc32=60048964\n'
	printf 'factory38_candidate_block0_sha256=%s\n' "${FACTORY38_CANDIDATE_BLOCK0_SHA256}"
	printf 'factory38_candidate_block0_crc32=71e2a6ca\n'
	printf 'factory38_changed_byte_count=36\n'
	printf 'factory38_chain_count=4\n'
	printf 'factory38_2g_channel_groups=1\n'
	printf 'factory38_5g_channel_groups=8\n'
	printf 'factory38_all_supported_channels_targeted=1\n'
	if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
		printf 'boot_policy=ram_boot_only_no_sysupgrade_or_firmware_published\n'
		printf 'flashable_image_publication=none\n'
		printf 'flashable_build_artifacts=quarantined_before_validation_removed_after_inspection_with_exit_signal_cleanup\n'
	else
		printf 'upgrade_compat_version=1.1\n'
		printf 'upgrade_policy=sysupgrade_T_required_no_force\n'
	fi
	printf 'preserved_config_migration=%s\n' "${PRESERVED_CONFIG_MIGRATION_VERSION}"
	printf 'product_version=%s\n' "${PRODUCT_VERSION}"
	printf 'openwrt_tag=%s\n' "${OPENWRT_TAG}"
	printf 'openwrt_commit=%s\n' "${OPENWRT_COMMIT}"
	printf 'openwrt_origin=%s\n' "${OPENWRT_URL}"
	printf 'openwrt_tag_object=%s\n' "${OPENWRT_TAG_OBJECT}"
	printf 'openwrt_release_signer=%s\n' "${OPENWRT_RELEASE_SIGNER}"
	printf 'offline_pinned_sources=%s\n' "${OFFLINE_PINNED_SOURCES}"
	while read -r feed expected; do
		printf 'feed_%s_commit=%s\n' "${feed}" "${expected}"
	done < <(feed_commit_matrix)
	printf 'source_kit_base_commit=%s\n' "${KIT_BASE_COMMIT}"
	printf 'auth_fix_commit=%s\n' "${AUTH_FIX_COMMIT}"
	printf 'source_kit_head_commit=%s\n' "${KIT_HEAD_COMMIT}"
	printf 'source_repository_mode=%s\n' "${SOURCE_REPOSITORY_MODE}"
	printf 'source_kit_original_commit=%s\n' "${KIT_ORIGINAL_COMMIT}"
	printf 'source_kit_original_tree=%s\n' "${KIT_ORIGINAL_TREE}"
	printf 'source_kit_container_commit=%s\n' "${KIT_CONTAINER_COMMIT}"
	printf 'source_kit_container_tree=%s\n' "${KIT_CONTAINER_TREE}"
	printf 'source_kit_payload_manifest_sha256=%s\n' \
		"${KIT_PAYLOAD_MANIFEST_SHA256}"
	printf 'source_trust_gate=%s\n' "${SOURCE_TRUST_GATE_STATUS}"
	printf 'trusted_source_bundle_sha256=%s\n' "${TRUSTED_SOURCE_BUNDLE_SHA256}"
	printf 'rescue_real_netns_gate=%s\n' "${RESCUE_REAL_EVIDENCE_GATE_STATUS}"
	printf 'rescue_real_netns_evidence=rescue-real-netns-evidence.txt\n'
	printf 'rescue_real_netns_evidence_sha256=%s\n' \
		"${RESCUE_REAL_EVIDENCE_SHA256}"
	printf 'smartap_build_epoch=%s\n' "${BUILD_EPOCH}"
	printf 'smartap_build_time=%s\n' "${BUILD_TIME}"
	printf 'seed_sha256=%s\n' "$(sha256sum "${SRC_SEED}" | awk '{print $1}')"
	printf 'mt76_patch_sha256=%s\n' "$(sha256sum "${SRC_PATCH}" | awk '{print $1}')"
	printf 'mt76_factory38_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_FACTORY38_PATCH}" | awk '{print $1}')"
	printf 'mt76_firmware_eeprom_shadow_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_FIRMWARE_EEPROM_SHADOW_PATCH}" | awk '{print $1}')"
	printf 'mt76_experimental_ul_muru_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_UL_MURU_PATCH}" | awk '{print $1}')"
	printf 'mt76_mediatek_vendor_ul_muru_baseline_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_UL_MURU_STOCK_POLICY_PATCH}" | awk '{print $1}')"
	for muru_port_patch in "${SRC_MURU_PORT_PATCHES[@]}"; do
		printf 'mt76_%s_sha256=%s\n' \
			"$(basename "${muru_port_patch}" .patch)" \
			"$(sha256sum "${muru_port_patch}" | awk '{print $1}')"
	done
	printf 'mt7915_firmware_baseline_verifier_sha256=%s\n' \
		"$(sha256sum "${MURU_FIRMWARE_VERIFY}" | awk '{print $1}')"
	printf 'rf_dts_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_RF_DTS_PATCH}" | awk '{print $1}')"
	if [ "${BUILD_PROFILE}" = ul-lab ] || [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
		printf 'ul_muru_ram_dts_patch_sha256=%s\n' \
			"$(sha256sum "${SRC_UL_MURU_DTS_PATCH}" | awk '{print $1}')"
	fi
	if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
		printf 'factory38_write_gate_patch_sha256=%s\n' \
			"$(sha256sum "${SRC_FACTORY38_WRITE_GATE_PATCH}" | awk '{print $1}')"
	fi
	printf 'factory38_builder_sha256=%s\n' \
		"$(sha256sum "${SRC_FACTORY38_BUILDER}" | awk '{print $1}')"
	printf 'factory38_stage_sha256=%s\n' \
		"$(sha256sum "${SRC_FACTORY38_STAGE}" | awk '{print $1}')"
	printf 'luci_wireless_txpower_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_LUCI_WIRELESS_PATCH}" | awk '{print $1}')"
	printf 'uhttpd_smartap_routing_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_UHTTPD_PATCH}" | awk '{print $1}')"
	printf 'mt7621_eee_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_DSA_EEE_PATCH}" | awk '{print $1}')"
	printf 'initramfs_ubi_guard_patch_sha256=%s\n' \
		"$(sha256sum "${SRC_UBI_INITRAMFS_GUARD_PATCH}" | awk '{print $1}')"
	printf 'playwright_core_version=%s\n' "${PLAYWRIGHT_EXPECTED_VERSION}"
	printf 'playwright_core_package_sha256=%s\n' \
		"$(sha256sum "${PLAYWRIGHT_CORE_DIR}/package.json" | awk '{print $1}')"
	printf 'chromium_executable_sha256=%s\n' "${CHROMIUM_SHA256}"
	printf 'serial_console=stock_ttyS0_115200_enabled\n'
	if [ "${USE_EXTERNAL_SIGNING}" = 1 ]; then
		printf 'firmware_signing=pinned_owner_key\n'
		printf 'firmware_pubkey_sha256=%s\n' \
			"$(sha256sum "${SRC_FW_SIGNING_PUB}" | awk '{print $1}')"
		printf 'firmware_ucert_sha256=%s\n' \
			"$(sha256sum "${SRC_FW_SIGNING_CERT}" | awk '{print $1}')"
		printf 'apk_pubkey_sha256=%s\n' \
			"$(sha256sum "${SRC_APK_SIGNING_PUB}" | awk '{print $1}')"
	else
		printf 'firmware_signing=openwrt_local_self_signed\n'
		printf 'firmware_pubkey_sha256=%s\n' \
			"$(sha256sum "${OPENWRT_DIR}/key-build.pub" 2>/dev/null | awk '{print $1}')"
		printf 'apk_pubkey_sha256=%s\n' \
			"$(sha256sum "${OPENWRT_DIR}/public-key.pem" 2>/dev/null | awk '{print $1}')"
	fi
	if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
		printf 'reference_sysupgrade_fwtool_signature=present_verified_not_published\n'
	else
		printf 'fwtool_signature=present_verified\n'
	fi
	printf 'input_manifest=build-inputs.txt\n'
	printf 'input_manifest_sha256=%s\n' \
		"$(sha256sum "${INPUT_MANIFEST}" | awk '{print $1}')"
	printf 'source_manifest=source-manifest.txt\n'
	printf 'source_manifest_format=cr6608-source-v1\n'
	printf 'source_manifest_sha256=%s\n' "${delivered_source_manifest_sha256}"
	printf 'source_test_log=source-tests.txt\n'
	printf 'source_test_log_sha256=%s\n' "${delivered_source_test_log_sha256}"
	printf 'build_log=build.log\n'
	printf 'build_log_sha256=%s\n' "${delivered_build_log_sha256}"
	printf 'target_definition_sha256=%s\n' \
		"$(inspection_value target_definition_sha256)"
	printf 'kernel_limit_bytes=%s\n' "$(inspection_value kernel_limit_bytes)"
	printf 'kernel_bytes=%s\n' "$(inspection_value kernel_bytes)"
	printf 'rootfs_bytes=%s\n' "$(inspection_value rootfs_bytes)"
	printf 'image_limit_bytes=%s\n' "$(inspection_value image_limit_bytes)"
	printf 'firmware_bytes=%s\n' "$(inspection_value firmware_bytes)"
	printf 'image=%s\n' "${PRIMARY_IMAGE}"
	if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
		if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
			printf 'image_kind=maintenance_initramfs_ram_boot_only\n'
		elif [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
			printf 'image_kind=retail_factory_commissioning_initramfs_ram_boot_only\n'
		else
			printf 'image_kind=ul_muru_qualification_initramfs_ram_boot_only\n'
		fi
		printf 'image_bytes=%s\n' "$(inspection_value initramfs_bytes)"
	else
		printf 'image_kind=sysupgrade\n'
		printf 'image_bytes=%s\n' "$(inspection_value sysupgrade_bytes)"
	fi
	printf 'image_sha256=%s\n' "${image_sha256}"
	if [ "${PUBLISH_FLASHABLE_IMAGES}" = 1 ]; then
		printf 'combined_firmware=%s\n' "${COMBINED_IMAGE}"
		printf 'combined_firmware_sha256=%s\n' \
			"$(sha256sum "${PUBLISH_DIR}/${COMBINED_IMAGE}" | awk '{print $1}')"
	fi
	printf 'initramfs=%s\n' "${INITRAMFS_IMAGE}"
	printf 'initramfs_sha256=%s\n' \
		"$(sha256sum "${PUBLISH_DIR}/${INITRAMFS_IMAGE}" | awk '{print $1}')"
	printf 'openwrt_config=openwrt.config\n'
	printf 'openwrt_config_sha256=%s\n' \
		"$(sha256sum "${PUBLISH_DIR}/openwrt.config" | awk '{print $1}')"
	printf 'openwrt_diffconfig=openwrt-diffconfig.txt\n'
	printf 'openwrt_package_manifest=openwrt-package-manifest.txt\n'
	printf 'rescue_nft_bridge_package=kmod-nft-bridge\n'
	printf 'rescue_nft_bridge_kernel_release=6.12.94\n'
	printf 'rescue_nft_bridge_kernel_configs=CONFIG_NETFILTER_FAMILY_BRIDGE=y,CONFIG_NF_TABLES_BRIDGE=m,CONFIG_NFT_BRIDGE_META=m,CONFIG_NFT_BRIDGE_REJECT=m,CONFIG_NF_CONNTRACK_BRIDGE=m\n'
	printf 'rescue_nft_bridge_core_module=nf_tables.ko\n'
	printf 'rescue_nft_bridge_modules=nf_conntrack_bridge.ko,nft_meta_bridge.ko,nft_reject_bridge.ko\n'
	printf 'rescue_nft_bridge_autoload_file=etc/modules.d/nft-bridge\n'
	printf 'rescue_nft_bridge_autoloads=nf_conntrack_bridge,nft_meta_bridge,nft_reject_bridge\n'
	printf 'rescue_nft_bridge_squashfs_gate_status=pass\n'
	printf 'rescue_nft_bridge_initramfs_gate_status=pass\n'
	printf 'rescue_nft_bridge_parser_gate=guard_runtime_atomic_precheck\n'
	printf 'rescue_nft_bridge_gate_status=pass\n'
	printf 'checksum=%s.sha256\n' "${PRIMARY_IMAGE}"
	printf 'inspection=prepublish-inspection.txt\n'
	printf 'ui_browser_screenshots=ui-browser-screenshots.tar.xz\n'
	printf 'ui_browser_screenshots_sha256=%s\n' \
		"$(sha256sum "${PUBLISH_DIR}/ui-browser-screenshots.tar.xz" | awk '{print $1}')"
	printf 'ui_browser_screenshot_manifest=ui-browser-screenshots.sha256\n'
	printf 'ui_browser_screenshot_manifest_sha256=%s\n' \
		"$(sha256sum "${PUBLISH_DIR}/ui-browser-screenshots.sha256" | awk '{print $1}')"
	printf 'source_archive=cr6608-source-kit.tar.xz\n'
	printf 'source_archive_role=inspection_only_not_build_input\n'
	printf 'source_archive_sha256=%s\n' \
		"$(sha256sum "${PUBLISH_DIR}/cr6608-source-kit.tar.xz" | awk '{print $1}')"
	printf 'source_bundle=cr6608-source-kit.bundle\n'
	printf 'source_bundle_role=canonical_reproducible_build_input\n'
	printf 'source_bundle_sha256=%s\n' \
		"$(sha256sum "${PUBLISH_DIR}/cr6608-source-kit.bundle" | awk '{print $1}')"
	for source_kit_record in \
		source-kit-create.txt source-kit-metadata.txt source-kit-identity.txt \
		source-kit-payload.tsv source-kit-reproduction.txt; do
		source_kit_record_key="${source_kit_record//[-.]/_}"
		printf '%s=%s\n' "${source_kit_record_key}" "${source_kit_record}"
		printf '%s_sha256=%s\n' "${source_kit_record_key}" \
			"$(sha256sum "${PUBLISH_DIR}/${source_kit_record}" | awk '{print $1}')"
	done
} > "${PUBLISH_DIR}/build-manifest.txt"
chmod 0644 "${PUBLISH_DIR}/${PRIMARY_IMAGE}.sha256" \
	"${PUBLISH_DIR}/build-manifest.txt"

verify_factory38_bundle_binding_to_publication
verify_published_images_match_inspection
verify_inspection_attestation_unchanged "${PUBLISH_DIR}"
verify_trusted_source_bundle_unchanged
verify_rescue_real_evidence_unchanged
(
	cd "${PUBLISH_DIR}" || exit 1
	find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | \
		xargs -0 sha256sum -- > SHA256SUMS || exit 1
	sha256sum -c SHA256SUMS || exit 1
) || die 'Public release checksum generation or verification failed'
verify_trusted_source_bundle_unchanged
verify_rescue_real_evidence_unchanged

if [ "${FACTORY38_BUILD_MODE}" = maintenance ]; then
	release_name="maintenance-${PRODUCT_VERSION}-${RUN_ID}-${image_sha256:0:16}"
	current_link_name="current-maintenance"
elif [ "${RETAIL_COMMISSIONING_MODE}" = 1 ]; then
	release_name="commissioning-${PRODUCT_VERSION}-${RUN_ID}-${image_sha256:0:16}"
	current_link_name="current-retail-commissioning"
elif [ "${BUILD_PROFILE}" = ul-lab ]; then
	release_name="qualification-${PRODUCT_VERSION}-${RUN_ID}-${image_sha256:0:16}"
	current_link_name="current-ul-muru-qualification"
elif [ "${BUILD_PROFILE}" = ul-forced-lab ]; then
	release_name="forced-ul-lab-${PRODUCT_VERSION}-${RUN_ID}-${image_sha256:0:16}"
	current_link_name="current-ul-muru-forced-lab"
else
	release_name="candidate-${PRODUCT_VERSION}-${RUN_ID}-${image_sha256:0:16}"
	current_link_name="current-candidate"
fi
release_dir="${RELEASES_DIR}/${release_name}"
[ ! -e "${release_dir}" ] || die "Release directory already exists: ${release_dir}"
PUBLISH_PENDING_DIR="${release_dir}"
PUBLISH_PENDING_IDENTITY="${PUBLISH_DIR_IDENTITY}"
mv -Tn -- "${PUBLISH_DIR}" "${release_dir}"
[ ! -e "${PUBLISH_DIR}" ] && [ ! -L "${PUBLISH_DIR}" ] || \
	die 'Release publication lost the no-clobber race'
[ -d "${release_dir}" ] && [ ! -L "${release_dir}" ] && \
	[ "$(stat -c '%d:%i' "${release_dir}")" = "${PUBLISH_PENDING_IDENTITY}" ] || \
	die 'Release directory identity changed during atomic publication'
(
	cd "${release_dir}" || exit 1
	sha256sum -c SHA256SUMS || exit 1
) || die 'Published release checksum verification failed after publication'
verify_trusted_source_bundle_unchanged
verify_rescue_real_evidence_unchanged
verify_published_images_match_inspection "${release_dir}"
verify_inspection_attestation_unchanged "${release_dir}"
PUBLISH_DIR=""
PUBLISH_DIR_IDENTITY=""
PUBLISH_PENDING_DIR=""
PUBLISH_PENDING_IDENTITY=""
publish_factory38_bundle "${release_dir}"
current_link_tmp="${OUTPUT_DIR}/.${current_link_name}.${RUN_ID}"
ln -s -- "releases/${release_name}" "${current_link_tmp}"
mv -Tf -- "${current_link_tmp}" "${OUTPUT_DIR}/${current_link_name}"
ls -lh "${release_dir}/${PRIMARY_IMAGE}"
if [ "${PUBLISH_FLASHABLE_IMAGES}" = 0 ]; then
	ok "RAM-boot-only image published at ${release_dir}/${PRIMARY_IMAGE}"
else
	ok "candidate image published at ${release_dir}/${PRIMARY_IMAGE}"
fi
