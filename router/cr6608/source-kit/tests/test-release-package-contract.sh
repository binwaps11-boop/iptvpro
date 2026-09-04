#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KIT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
BUILD="${KIT_DIR}/build.sh"
REMOTE_BUILD="${KIT_DIR}/build.remote.sh"
README="${KIT_DIR}/README.md"
INSPECTOR="${KIT_DIR}/inspect-image.sh"
SEED="${KIT_DIR}/cr6608.seed.config"
MIGRATION="${KIT_DIR}/files/etc/uci-defaults/99-cr6608-preserved-config-v2"
SECURE_CONSOLE_MIGRATION="${KIT_DIR}/files/etc/uci-defaults/99-cr6608-secure-console"
VERSION_FILE="${KIT_DIR}/files/etc/smartap-version"
WIRELESS_DEFAULTS="${KIT_DIR}/files/etc/config/wireless"
QUICK_DEFAULTS="${KIT_DIR}/files/etc/config/cr6608quick"
MAINTENANCE_PUBLICATION_TEST="${KIT_DIR}/tests/test-maintenance-publication-guards.sh"
ALL_CHANNEL_38_TEST="${KIT_DIR}/tests/test-all-channel-38-contract.py"
FULL_VERIFY="${KIT_DIR}/files/usr/bin/cr6608-wifi-full-verify"
TXPOWER_COLLECTOR="${KIT_DIR}/files/usr/sbin/cr6608-txpower-collect"
UHTTPD_PATCH="${KIT_DIR}/patches/992-uhttpd-normalize-dispatch-and-close-unread-body.patch"
SMARTAP_ONLY_ROUTING_TEST="${KIT_DIR}/tests/test-smartap-only-routing.sh"
UHTTPD_CONFIG="${KIT_DIR}/files/etc/config/uhttpd"
UHTTPD_SECURITY_HEADERS="${KIT_DIR}/files/etc/uhttpd/security-headers.json"
RUN_LIMIT_TEST="${KIT_DIR}/tests/test-dashctl-run-limit-runtime.sh"
DASHCTL_MAC_QOS_TRANSACTION_TEST="${KIT_DIR}/tests/test-dashctl-mac-qos-transactions.sh"
DASHAPI_RUNTIME_TEST="${KIT_DIR}/tests/test-dashapi2-runtime.sh"
ROUTER_UHTTPD_TEST="${KIT_DIR}/tests/test-router-uhttpd-smartap.sh"
UL_MURU_AIRTEST_RUNTIME_TEST="${KIT_DIR}/tests/test-ul-muru-airtest-runtime.sh"
UL_MURU_DEFERRED_RUNTIME_TEST="${KIT_DIR}/tests/test-ul-muru-deferred-runtime.sh"
UL_MURU_DEFERRED="${KIT_DIR}/files/etc/rc.d/S97cr6608-ul-muru-reconcile"
EASYMESH_VERIFIER_RUNTIME_TEST="${KIT_DIR}/tests/test-easymesh-verifier-runtime.sh"
PRPLMESH_CREDENTIAL_SYNC_TEST="${KIT_DIR}/tests/test-prplmesh-credential-sync.sh"
PRPLMESH_CREDENTIAL_SYNC_HELPER="${KIT_DIR}/packages/prplmesh/files/usr/sbin/cr6608-prplmesh-sync"
AUTH_LIFECYCLE_TEST="${KIT_DIR}/tests/test-auth-lifecycle.sh"
RETAIL_RADIO_POLICY_TEST="${KIT_DIR}/tests/test-retail-radio-policy.sh"
RETAIL_RADIO_AUDIT="${KIT_DIR}/files/usr/sbin/cr6608-retail-radio-audit"
RETAIL_PROVISION="${KIT_DIR}/files/usr/sbin/cr6608-retail-provision"
RETAIL_SECURITY_AUDIT="${KIT_DIR}/files/usr/sbin/cr6608-retail-audit"
ARTIFACT_PROFILE="${KIT_DIR}/files/etc/cr6608-artifact-profile"
CRASHLOG_BUILDER="${KIT_DIR}/crashlog/build-cr6608-crashlog-initramfs.sh"
CRASHLOG_SANITIZER_TEST="${KIT_DIR}/tests/test-cr6608-crashlog-sanitize-mock.sh"
CRASHLOG_BUILD_TEST="${KIT_DIR}/tests/test-cr6608-crashlog-build-contract.sh"
CRASHLOG_README="${KIT_DIR}/crashlog/README.md"
DASHBOARD_REQUEST_COORDINATION_TEST="${KIT_DIR}/tests/test-dashboard-request-coordination.js"
CONTROL_RECOVERY_TEST="${KIT_DIR}/tests/test-control-recovery-contract.sh"
JSON_CHARSET_TEST="${KIT_DIR}/tests/test-json-charset-contract.sh"
PACKAGE_MANAGER_RUNTIME_TEST="${KIT_DIR}/tests/test-package-manager-runtime.sh"
SOURCE_KIT_TOOL="${KIT_DIR}/tools/cr6608_source_kit.py"
SOURCE_KIT_TEST="${KIT_DIR}/tests/test-source-kit-contract.py"
FEED_CACHE_TOOL="${KIT_DIR}/tools/cr6608-feed-cache.py"
OPENWRT_TAG_GATE="${KIT_DIR}/tools/cr6608-openwrt-tag-gate.sh"
OPENWRT_RELEASE_KEY="${KIT_DIR}/signing/openwrt-release-hauke.asc"
OFFLINE_SOURCE_FALLBACK_TEST="${KIT_DIR}/tests/test-offline-source-fallback.py"
ARGON_LOCALTIME_JS="${KIT_DIR}/files/www/luci-static/argon/js/cr6608-localtime.js"
FW_DEFAULTS_GUARD="${KIT_DIR}/files/etc/board.d/05_fw_defaults"
SQM_DSA_DEFAULTS="${KIT_DIR}/files/etc/uci-defaults/96-cr6608-sqm-dsa-defaults"

[ -s "${BUILD}" ]
[ -s "${REMOTE_BUILD}" ]
[ -s "${README}" ]
[ -s "${INSPECTOR}" ]
[ -s "${SEED}" ]
[ -s "${MIGRATION}" ]
[ -s "${SECURE_CONSOLE_MIGRATION}" ]
[ -s "${VERSION_FILE}" ]
[ -s "${WIRELESS_DEFAULTS}" ]
[ -s "${QUICK_DEFAULTS}" ]
[ -s "${MAINTENANCE_PUBLICATION_TEST}" ]
[ -s "${ALL_CHANNEL_38_TEST}" ]
[ -s "${FULL_VERIFY}" ]
[ -s "${TXPOWER_COLLECTOR}" ]
[ -s "${SMARTAP_ONLY_ROUTING_TEST}" ]
[ -s "${UHTTPD_PATCH}" ]
[ -s "${UHTTPD_CONFIG}" ]
[ -s "${UHTTPD_SECURITY_HEADERS}" ]
[ -s "${RUN_LIMIT_TEST}" ]
[ -s "${DASHAPI_RUNTIME_TEST}" ]
[ -s "${ROUTER_UHTTPD_TEST}" ]
[ -s "${UL_MURU_AIRTEST_RUNTIME_TEST}" ]
[ -s "${UL_MURU_DEFERRED_RUNTIME_TEST}" ]
[ -s "${UL_MURU_DEFERRED}" ]
[ -s "${EASYMESH_VERIFIER_RUNTIME_TEST}" ]
[ -s "${PRPLMESH_CREDENTIAL_SYNC_TEST}" ]
[ -s "${PRPLMESH_CREDENTIAL_SYNC_HELPER}" ]
[ -s "${AUTH_LIFECYCLE_TEST}" ]
[ -s "${RETAIL_RADIO_POLICY_TEST}" ]
[ -s "${RETAIL_RADIO_AUDIT}" ]
[ -s "${CRASHLOG_BUILDER}" ]
[ -s "${CRASHLOG_SANITIZER_TEST}" ]
[ -s "${CRASHLOG_BUILD_TEST}" ]
[ -s "${CRASHLOG_README}" ]
[ -s "${DASHBOARD_REQUEST_COORDINATION_TEST}" ]
[ -s "${CONTROL_RECOVERY_TEST}" ]
[ -s "${JSON_CHARSET_TEST}" ]
[ -s "${PACKAGE_MANAGER_RUNTIME_TEST}" ]
[ -s "${SOURCE_KIT_TOOL}" ]
[ -s "${SOURCE_KIT_TEST}" ]
[ -s "${FEED_CACHE_TOOL}" ]
[ -s "${OPENWRT_TAG_GATE}" ]
[ -s "${OPENWRT_RELEASE_KEY}" ]
[ -s "${OFFLINE_SOURCE_FALLBACK_TEST}" ]
[ -s "${ARGON_LOCALTIME_JS}" ]
[ -s "${FW_DEFAULTS_GUARD}" ]
[ -s "${SQM_DSA_DEFAULTS}" ]

require_seed_once() {
	seed_symbol="$1"
	seed_count="$(grep -Fxc "${seed_symbol}" "${SEED}" || true)"
	[ "${seed_count}" -eq 1 ] || {
		printf 'release package contract: expected one seed entry: %s\n' "${seed_symbol}" >&2
		exit 1
	}
}

# Pin the official OpenWrt 25.12.5 package names used for opt-in traffic
# shaping, UPnP/PCP/NAT-PMP, roaming assistance and IPv6 support.
for seed_symbol in \
	'CONFIG_IPV6=y' \
	'CONFIG_PACKAGE_sqm-scripts=y' \
	'CONFIG_PACKAGE_luci-app-sqm=y' \
	'CONFIG_PACKAGE_tc-tiny=y' \
	'CONFIG_PACKAGE_ip-tiny=y' \
	'CONFIG_PACKAGE_kmod-nft-bridge=y' \
	'CONFIG_PACKAGE_kmod-sched-core=y' \
	'CONFIG_PACKAGE_kmod-sched-cake=y' \
	'CONFIG_PACKAGE_kmod-ifb=y' \
	'CONFIG_PACKAGE_iptables=y' \
	'CONFIG_PACKAGE_iptables-mod-ipopt=y' \
	'CONFIG_PACKAGE_miniupnpd-nftables=y' \
	'CONFIG_PACKAGE_luci-app-upnp=y' \
	'CONFIG_PACKAGE_usteer=y' \
	'CONFIG_PACKAGE_luci-app-usteer=y' \
	'CONFIG_PACKAGE_odhcp6c=y' \
	'CONFIG_PACKAGE_odhcpd-ipv6only=y' \
	'CONFIG_PACKAGE_uhttpd-mod-ucode=y' \
	'CONFIG_PACKAGE_luci-proto-ipv6=y' \
	'CONFIG_PACKAGE_cr6608-mndp=y' \
	'CONFIG_PACKAGE_lldpd=y' \
	'CONFIG_LLDPD_WITH_PRIVSEP=y' \
	'CONFIG_LLDPD_WITH_CDP=y'; do
	require_seed_once "${seed_symbol}"
done

# Pin the OpenWrt 25.12/Linux 6.12 nft bridge contract to the modules and
# autoload order that are present in both published filesystem variants.
NFT_BRIDGE_KERNEL_CONFIGS='CONFIG_NETFILTER_FAMILY_BRIDGE=y,CONFIG_NF_TABLES_BRIDGE=m,CONFIG_NFT_BRIDGE_META=m,CONFIG_NFT_BRIDGE_REJECT=m,CONFIG_NF_CONNTRACK_BRIDGE=m'
NFT_BRIDGE_MODULES='nf_conntrack_bridge.ko,nft_meta_bridge.ko,nft_reject_bridge.ko'
NFT_BRIDGE_AUTOLOADS='nf_conntrack_bridge,nft_meta_bridge,nft_reject_bridge'
grep -Fq 'EXPECTED_KERNEL_RELEASE="6.12.94"' "${INSPECTOR}"
grep -Fq "${NFT_BRIDGE_KERNEL_CONFIGS}" "${INSPECTOR}"
grep -Fq 'RESCUE_NFT_BRIDGE_CORE_MODULE="nf_tables.ko"' "${INSPECTOR}"
grep -Fq "${NFT_BRIDGE_MODULES}" "${INSPECTOR}"
grep -Fq 'RESCUE_NFT_BRIDGE_AUTOLOAD_FILE="etc/modules.d/nft-bridge"' \
	"${INSPECTOR}"
grep -Fq "${NFT_BRIDGE_AUTOLOADS}" "${INSPECTOR}"
grep -Fq 'rootfs must contain exactly one ${rescue_nft_module} kernel module' \
	"${INSPECTOR}"
grep -Fq 'rootfs nft bridge modules.d autoload bytes or order differ' \
	"${INSPECTOR}"
grep -Fq 'built kernel lacks exact nft bridge config:' "${INSPECTOR}"
grep -Fq 'expected exactly one initramfs {module_name} kernel module' \
	"${INSPECTOR}"
grep -Fq 'stat.S_IMODE(module_mode) != 0o644' "${INSPECTOR}"
grep -Fq 'bridge_autoload_data != expected_bridge_autoload_data' "${INSPECTOR}"
grep -Fq 'autoload_occurrences[token] != [' "${INSPECTOR}"
grep -Fq 'rescue_nft_bridge_initramfs_gate_status=pass' "${INSPECTOR}"
! grep -Fq 'nf_tables_bridge.ko' "${INSPECTOR}"

for build_variant in "${BUILD}" "${REMOTE_BUILD}"; do
	! grep -Fq 'nf_tables_bridge.ko' "${build_variant}"
	for bridge_record in \
		'rescue_nft_bridge_kernel_release=6.12.94' \
		"rescue_nft_bridge_kernel_configs=${NFT_BRIDGE_KERNEL_CONFIGS}" \
		'rescue_nft_bridge_core_module=nf_tables.ko' \
		"rescue_nft_bridge_modules=${NFT_BRIDGE_MODULES}" \
		'rescue_nft_bridge_autoload_file=etc/modules.d/nft-bridge' \
		"rescue_nft_bridge_autoloads=${NFT_BRIDGE_AUTOLOADS}" \
		'rescue_nft_bridge_squashfs_gate_status=pass' \
		'rescue_nft_bridge_initramfs_gate_status=pass' \
		'rescue_nft_bridge_parser_gate=guard_runtime_atomic_precheck' \
		'rescue_nft_bridge_gate_status=pass'; do
		bridge_record_count="$(grep -Fc "${bridge_record}" "${build_variant}" || true)"
		[ "${bridge_record_count}" -ge 2 ]
	done
done

for build_variant in "${BUILD}" "${REMOTE_BUILD}"; do
	grep -Fq 'SRC_MNDP_SOURCE="${SCRIPT_DIR}/src/cr6608-mndp-advertise.c"' "${build_variant}"
	grep -Fq 'install -m 0644 -- "${SRC_MNDP_SOURCE}"' "${build_variant}"
	grep -Fq 'Opaque MNDP overlay binary is forbidden' "${build_variant}"
	grep -Fq 'for discovery_package in cr6608-mndp lldpd; do' "${build_variant}"
	grep -Fq 'built package manifest lacks exactly one ${discovery_package}' "${build_variant}"
done
grep -Fq 'require_mode usr/sbin/cr6608-mndp-advertise 755' "${INSPECTOR}"
grep -Fq 'require_mode usr/sbin/lldpd 755' "${INSPECTOR}"
grep -Fq 'require_mode usr/sbin/lldpcli 755' "${INSPECTOR}"
grep -Fq 'require_mode usr/sbin/ubidetach 755' "${INSPECTOR}"
grep -Fqx 'CONFIG_PACKAGE_ubi-utils=y' "${SEED}"
grep -Fq 'require_symlink usr/sbin/lldpctl lldpcli' "${INSPECTOR}"
! grep -Fq 'require_mode usr/sbin/lldpctl' "${INSPECTOR}"
grep -Fq 'require_cpio_symlink(cpio_entries, "usr/sbin/lldpctl", "lldpcli")' \
	"${INSPECTOR}"
grep -Fq 'print("initramfs_lldp_package_gate_status=pass")' "${INSPECTOR}"
for build_variant in "${BUILD}" "${REMOTE_BUILD}"; do
	grep -Fq "grep -Fqx 'initramfs_lldp_package_gate_status=pass'" \
		"${build_variant}"
done
grep -Fq 'installed MNDP binary lacks the source-build provenance marker' "${INSPECTOR}"
grep -Fq 'delivered rootfs lacks installed discovery package ${discovery_package}' "${INSPECTOR}"
shadow_lldp_record='lldp:x:0:0:99999:7:::'
[ "$(grep -Fc "${shadow_lldp_record}" "${INSPECTOR}")" -eq 2 ]
sed -n '/expected_shadow="${tmp_dir}\/expected-shadow"/,/} > "${expected_shadow}"/p' \
	"${INSPECTOR}" | grep -Fq "'${shadow_lldp_record}'"
sed -n '/^SHADOW_PACKAGE_ACCOUNTS = (/,/^)/p' "${INSPECTOR}" | \
	grep -Fq "b\"${shadow_lldp_record}\\n\""
grep -Fq 'require_mode usr/libexec/cr6608-private-runtime 644' "${INSPECTOR}"
for build_variant in "${BUILD}" "${REMOTE_BUILD}"; do
	grep -Fq 'chmod 0644 "${OPENWRT_DIR}/files/usr/libexec/cr6608-private-runtime"' \
		"${build_variant}"
done
grep -Fq 'require_mode etc/board.d/05_fw_defaults 644' "${INSPECTOR}"
! grep -Fq 'require_mode etc/board.d/05_fw_defaults 755' "${INSPECTOR}"
[ "$(stat -c '%a' "${FW_DEFAULTS_GUARD}")" = 644 ]

# Keep the firewall4-compatible miniupnpd provider unambiguous.
! grep -Fqx 'CONFIG_PACKAGE_miniupnpd-iptables=y' "${SEED}"

# Package inclusion must not invent a device uplink or enable either service.
# With no overlay config, the pinned upstream packages retain their disabled
# defaults until the administrator explicitly supplies an uplink and rates.
[ ! -e "${KIT_DIR}/files/etc/config/sqm" ]
[ ! -e "${KIT_DIR}/files/etc/config/upnpd" ]
for startup_path in \
	"${KIT_DIR}/files/etc/uci-defaults" \
	"${KIT_DIR}/files/etc/init.d" \
	"${KIT_DIR}/files/etc/hotplug.d" \
	"${KIT_DIR}/files/etc/rc.local"; do
	[ -e "${startup_path}" ] || continue
	! grep -R -E \
		'(/etc/init\.d/)?(sqm|miniupnpd)[[:space:]]+(enable|start|restart)([[:space:]]|$)' \
		"${startup_path}"
	! grep -R -E \
		'uci([[:space:]].*)?[[:space:]]set[[:space:]]+(sqm|upnpd)\.[^=]*\.enabled=(1|true)' \
		"${startup_path}"
done

grep -Fq 'select_node_runtime()' "${BUILD}"
grep -Fq 'Node.js 18 or newer is required' "${BUILD}"
grep -Eq '^warn\(\)[[:space:]]*\{.*WARNING: %s.*>&2;[[:space:]]*\}$' "${BUILD}"
grep -Fq 'warn "Feed ${feed} network update failed' "${BUILD}"
grep -Fq 'FEED_UPDATE_TIMEOUT_SECONDS="${CR6608_FEED_UPDATE_TIMEOUT_SECONDS:-900}"' "${BUILD}"
grep -Fq 'CR6608_FEED_UPDATE_TIMEOUT_SECONDS must be an integer from 120 to 1800' "${BUILD}"
grep -Fq '/usr/bin/timeout "${FEED_UPDATE_TIMEOUT_SECONDS}" ./scripts/feeds update "${feed}"' "${BUILD}"
grep -Fq 'clone_openwrt_release_source()' "${BUILD}"
grep -Fq '"${FINAL_ROOT}"/openwrt.clone.*' "${BUILD}"
grep -Fq 'OpenWrt source clone failed after 3 bounded network attempts' "${BUILD}"
grep -Fq 'OpenWrt source clone network failure (attempt ${attempt}/3); retrying' "${BUILD}"
grep -Fq 'CR6608_REUSE_PREPARED_TREE must be 0 or 1' "${BUILD}"
grep -Fq 'BUILD_EXECUTION_MODE=verified_incremental_cache' "${BUILD}"
grep -Fq 'git clean -ffdx -e dl/ -e build_dir/ -e staging_dir/' "${BUILD}"
grep -Fq 'verified compiler/toolchain caches retained; source and image outputs reset' "${BUILD}"
grep -Fq "printf 'build_execution_mode=%s\\n'" "${BUILD}"
grep -Fq 'HOST_ZSTD_LOG="${LOG_DIR}/host-zstd-candidate-${RUN_ID}.log"' "${BUILD}"
grep -Fq 'make tools/zstd/compile -j1 V=s 2>&1 | tee "${HOST_ZSTD_LOG}"' "${BUILD}"
grep -Fq 'test -x staging_dir/host/bin/zstd' "${BUILD}"
grep -Fq 'SOURCE_TEST_ONLY="${CR6608_SOURCE_TEST_ONLY:-0}"' "${BUILD}"
grep -Fq 'CR6608_SOURCE_TEST_ONLY must be 0 or 1' "${BUILD}"
grep -Fq 'OFFLINE_PINNED_SOURCES="${CR6608_OFFLINE_PINNED_SOURCES:-0}"' "${BUILD}"
grep -Fq 'CR6608_OFFLINE_PINNED_SOURCES must be 0 or 1' "${BUILD}"
grep -Fq '`CR6608_OFFLINE_PINNED_SOURCES=1`' "${README}"
grep -Fq 'remote identity mismatches never fall back' "${README}"
grep -Fq 'PINNED_FEED_CACHE_DIR="/home/root123/feeds-pinned-cache-20260809"' "${BUILD}"
grep -Fq 'verify_openwrt_source_gate offline-only' "${BUILD}"
grep -Fq 'verify_openwrt_source_gate online-fallback' "${BUILD}"
grep -Fq 'restore_pinned_feed_cache' "${BUILD}"
grep -Fq './scripts/feeds update -i "${feed}"' "${BUILD}"
for pinned_feed_hash in \
	c846b27bb1fde53ee3f06460e34e5396aaa0c90778d0e67d80f0ff11e01c234d \
	29d0b463543c14f86b51ba3774ebf5fad1ea842c36dcff7d2b7644651b58ff7f \
	5bec191d590b861709892a22ef1b5766c075a66087dc3a7237042d435bd376e1 \
	b39f2a29b8a578c0495bdc0b27921474c918cdc298ab5c4a67411c6c1e85acb9 \
	3939e29b8e76e747b3c24170170bd26ede05a81f97fe81a734bfff558bc0806c; do
	grep -Fq "${pinned_feed_hash}" "${BUILD}"
done
grep -Fq 'OPENWRT_TAG_OBJECT="e20bc3ec9eb9e3dbd0519ddc18f81f3eedc0f45e"' "${BUILD}"
grep -Fq 'OPENWRT_RELEASE_KEY_SHA256="f9c4a14810bbec006795243807910dbbcb18b6046ae9505f9f289c0e22be3b1e"' "${BUILD}"
grep -Fq 'OPENWRT_RELEASE_SIGNER="CB3D3FB8071DF89C179B0B43F1B767859CB2EBC7"' "${BUILD}"
grep -Fq 'feed_cache_restore=pass' "${FEED_CACHE_TOOL}"
grep -Fq 'archive contains parent traversal' "${FEED_CACHE_TOOL}"
grep -Fq 'local release tag signature invalid' "${OPENWRT_TAG_GATE}"
grep -Fq 'remote release-tag check failed for a non-network reason' "${OPENWRT_TAG_GATE}"
grep -Fq 'offline_source_fallback_tests=pass' "${OFFLINE_SOURCE_FALLBACK_TEST}"
grep -Fq 'ALL_CHANNEL_38_TEST="${SCRIPT_DIR}/tests/test-all-channel-38-contract.py"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${ALL_CHANNEL_38_TEST}"' "${BUILD}"
grep -Fq '"${FACTORY38_BUILDER_TEST}" "${ALL_CHANNEL_38_TEST}" "${FACTORY38_STAGE_GUARD_TEST}"' "${BUILD}"
grep -Fq 'python3 -B "${ALL_CHANNEL_38_TEST}"' "${BUILD}"
grep -Fq "grep -qx 'all_channel_38_contract=pass'" "${BUILD}"
grep -Fq 'all_channel_38_contract=pass' "${ALL_CHANNEL_38_TEST}"
grep -Fq 'SRC_UHTTPD_PATCH="${SCRIPT_DIR}/patches/992-uhttpd-normalize-dispatch-and-close-unread-body.patch"' "${BUILD}"
grep -Fq 'UHTTPD_SECURITY_HEADERS="${SRC_FILES}/etc/uhttpd/security-headers.json"' "${BUILD}"
grep -Fq '"${UHTTPD_SECURITY_HEADERS}" \' "${BUILD}"
grep -Fq 'record_regular_input uhttpd-patch "${SRC_UHTTPD_PATCH}"' "${BUILD}"
grep -Fq 'install -m 0644 -- "${SRC_UHTTPD_PATCH}"' "${BUILD}"
grep -Fq 'Staged uhttpd canonical-routing patch differs from the recorded input' "${BUILD}"
grep -Fq 'uhttpd_smartap_routing_patch_sha256=' "${BUILD}"
for build_variant in "${BUILD}" "${REMOTE_BUILD}"; do
	grep -Fq 'UHTTPD_LOG="${LOG_DIR}/uhttpd-prepare-candidate-${RUN_ID}.log"' "${build_variant}"
	grep -Fq 'uhttpd clean left a stale prepared source directory' "${build_variant}"
	grep -Fq 'make package/network/services/uhttpd/prepare V=s 2>&1 | tee "${UHTTPD_LOG}"' "${build_variant}"
	grep -Fq 'Expected exactly one prepared uhttpd source directory' "${build_variant}"
	grep -Fq "uhttpd-2026.06.16~7b1bec45" "${build_variant}"
	grep -Fq "! -name '*_check'" "${build_variant}"
	grep -Fq 'Prepared uhttpd source lacks one linked final/check stamp pair' "${build_variant}"
	grep -Fq 'unread-body close decision is not made before response framing' "${build_variant}"
	grep -Fq 'unread-body safety guard is not applied before keepalive reuse' "${build_variant}"
	grep -Fq 'prepared uhttpd source failed the canonical-routing and connection-safety gate' "${build_variant}"
done
[ "$(grep -Ec "^[[:space:]]*option json_script '/etc/uhttpd/security-headers.json'$" "${UHTTPD_CONFIG}")" -eq 1 ]
! grep -Eq "^[[:space:]]*list json_script " "${UHTTPD_CONFIG}"
! grep -Fq 'Strict-Transport-Security' "${UHTTPD_SECURITY_HEADERS}"
grep -Fq 'if (cl->tls &&' "${UHTTPD_PATCH}"
grep -Fq 'Strict-Transport-Security: max-age=31536000' "${UHTTPD_PATCH}"
grep -Fq 'default-src '\''self'\''; script-src '\''self'\''; style-src '\''self'\'' '\''unsafe-inline'\''; img-src '\''self'\'' data:; connect-src '\''self'\''; font-src '\''self'\''; frame-ancestors '\''self'\''; object-src '\''none'\''; base-uri '\''self'\''; form-action '\''self'\''' "${UHTTPD_SECURITY_HEADERS}"
! grep -Eqi 'includeSubDomains|preload' "${UHTTPD_SECURITY_HEADERS}"
grep -Fq 'uhttpd security-header JSON policy is malformed or incomplete' "${INSPECTOR}"
grep -Fq 'uhttpd init lacks supported scalar multi-path json_script handling' "${INSPECTOR}"
grep -Fq 'built uhttpd lacks the TLS-only HSTS response path' "${INSPECTOR}"
! grep -Fq 'built uhttpd lacks global security header' "${INSPECTOR}"
grep -Fq 'DASHCTL_RUN_LIMIT_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-dashctl-run-limit-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${DASHCTL_RUN_LIMIT_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'sh "${DASHCTL_RUN_LIMIT_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'dashctl_run_limit_runtime=pass' "${RUN_LIMIT_TEST}"
grep -Fq 'DASHCTL_MAC_QOS_TRANSACTION_TEST="${SCRIPT_DIR}/tests/test-dashctl-mac-qos-transactions.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${DASHCTL_MAC_QOS_TRANSACTION_TEST}"' "${BUILD}"
grep -Fq 'sh "${DASHCTL_MAC_QOS_TRANSACTION_TEST}"' "${BUILD}"
grep -Fq 'dashctl_mac_qos_transactions=pass' "${DASHCTL_MAC_QOS_TRANSACTION_TEST}"
grep -Fq 'require_mode usr/sbin/smartap-qos-apply 755' "${INSPECTOR}"
grep -Fq 'Smart AP QoS transactions lack a BusyBox-compatible nonblocking lock' "${INSPECTOR}"
grep -Fq 'Smart AP QoS transactions use util-linux-only flock options' "${INSPECTOR}"
grep -Fq 'Smart AP QoS lacks guarded bridged-client MAC blocking' "${INSPECTOR}"
grep -Fq 'DASHAPI_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-dashapi2-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${DASHAPI_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'sh "${DASHAPI_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'dashapi2_runtime=pass' "${DASHAPI_RUNTIME_TEST}"
for build_variant in "${BUILD}" "${REMOTE_BUILD}"; do
	grep -Fq "grep -qx 'dashapi2_runtime=pass'" "${build_variant}"
	! grep -Fq "grep -q '^dashapi2_runtime=pass '" "${build_variant}"
done
grep -Fq 'ROUTER_UHTTPD_SMARTAP_TEST="${SCRIPT_DIR}/tests/test-router-uhttpd-smartap.sh"' "${BUILD}"
grep -Fq 'git apply --numstat -- "$UHTTPD_PATCH"' "${SMARTAP_ONLY_ROUTING_TEST}"
grep -Fq 'uhttpd patch hunk line count validation failed' "${SMARTAP_ONLY_ROUTING_TEST}"
grep -Fq 'cl->dispatch.free != proc_free' "${SMARTAP_ONLY_ROUTING_TEST}"
grep -Fq 'p->r.header_cb || !p->hdr.head' "${SMARTAP_ONLY_ROUTING_TEST}"
grep -Fq 'record_regular_input router-runtime-test "${ROUTER_UHTTPD_SMARTAP_TEST}"' "${BUILD}"
grep -Fq '"${ROUTER_UHTTPD_SMARTAP_TEST}" "${LOGIN_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'sh -n "${ROUTER_UHTTPD_SMARTAP_TEST}"' "${BUILD}"
grep -Fq 'uhttpd_smartap_runtime=pass' "${ROUTER_UHTTPD_TEST}"
grep -Fq -- '-H "$HEADERS"' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'probe_route http "$PORT" /cgi-bin/dashlogin' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'probe_route http "$PORT" /cr6608-security-header-missing' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'probe_route https "$TLS_PORT" /cgi-bin/dashlogin' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'probe_route https "$TLS_PORT" /cr6608-security-header-missing' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'response_profile="$4"' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'json_cgi)' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'http_incomplete_cgi baseline' "${ROUTER_UHTTPD_TEST}"
grep -Fq "sed -n 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//p'" "${ROUTER_UHTTPD_TEST}"
grep -Fq '[ "$luci_headers" = 1 ]' "${ROUTER_UHTTPD_TEST}"
grep -Fq '[ "$post_luci_headers" = 1 ]' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'unread body advertised keepalive' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'unread chunked body advertised keepalive' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'consumed request did not preserve keepalive' "${ROUTER_UHTTPD_TEST}"
grep -Fq 'UL_MURU_AIRTEST_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-airtest-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${UL_MURU_AIRTEST_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'sh "${UL_MURU_AIRTEST_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'ul_muru_airtest_runtime=pass' "${UL_MURU_AIRTEST_RUNTIME_TEST}"
grep -Fq 'EASYMESH_VERIFIER_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-easymesh-verifier-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${EASYMESH_VERIFIER_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'sh "${EASYMESH_VERIFIER_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'easymesh_verifier_runtime=pass' "${EASYMESH_VERIFIER_RUNTIME_TEST}"
grep -Fq 'PRPLMESH_CREDENTIAL_SYNC_TEST="${SCRIPT_DIR}/tests/test-prplmesh-credential-sync.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${PRPLMESH_CREDENTIAL_SYNC_TEST}"' "${BUILD}"
grep -Fq 'record_regular_input source-runtime "${PRPLMESH_CREDENTIAL_SYNC_HELPER}"' "${BUILD}"
grep -Fq 'sh "${PRPLMESH_CREDENTIAL_SYNC_TEST}"' "${BUILD}"
grep -Fq "grep -qx 'prplmesh_credential_sync_contract=pass'" "${BUILD}"
grep -Fq 'require_mode usr/sbin/cr6608-prplmesh-sync 755' "${INSPECTOR}"
grep -Fq '988339adb858f6efbcf58e79ed1180150cd463837226b44ce785e6eaf103503a' \
	"${INSPECTOR}"
grep -Fq 'Quick Settings CGI omits prplMesh from authorization or staged-delta cleanup' \
	"${INSPECTOR}"
grep -Fq 'Safe Apply rollback omits the prplMesh configuration' "${INSPECTOR}"
grep -Fq 'LuCI Quick Settings ACL omits exact prplMesh' "${INSPECTOR}"
grep -Fq "DASHCTL_TRANSACTION_UCI_PACKAGES='network wireless dhcp firewall system smartap cr6608quick uhttpd dropbear sqm usteer prplmesh'" \
	"${INSPECTOR}"
grep -Fq 'Smart dashboard prplMesh transaction, backup, or rollback coverage is incomplete' \
	"${INSPECTOR}"
grep -Fq 'Smart dashboard prplMesh action arm is absent' "${INSPECTOR}"
grep -Fq 'stage/commit/runtime/verify order is incomplete' "${INSPECTOR}"
for prplmesh_dashctl_action in \
	'"save_wifi": (' \
	'"delete_wifi": (' \
	'"raw_uci_set|raw_uci_delete|raw_uci_add_section|raw_uci_delete_section|raw_uci_commit_reload": (' \
	'"reset_royal": (' \
	'"apply_royal": ('; do
	grep -Fq "${prplmesh_dashctl_action}" "${INSPECTOR}"
done
grep -Fq 'prplmesh_credential_sync_contract=pass' "${PRPLMESH_CREDENTIAL_SYNC_TEST}"
grep -Fq 'AUTH_LIFECYCLE_TEST="${SCRIPT_DIR}/tests/test-auth-lifecycle.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${AUTH_LIFECYCLE_TEST}"' "${BUILD}"
grep -Fq "grep -qx 'auth_protocol_cookie_tests=pass'" "${BUILD}"
grep -Fq 'auth_protocol_cookie_tests=pass' "${AUTH_LIFECYCLE_TEST}"
grep -Fq 'RETAIL_RADIO_POLICY_TEST="${SCRIPT_DIR}/tests/test-retail-radio-policy.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${RETAIL_RADIO_POLICY_TEST}"' "${BUILD}"
grep -Fq 'sh "${RETAIL_RADIO_POLICY_TEST}"' "${BUILD}"
grep -Fq 'retail_radio_policy_contract=pass' "${RETAIL_RADIO_POLICY_TEST}"
grep -Fq 'external_rf_verification=REQUIRED artifact_sha_verification=REQUIRED' \
	"${RETAIL_RADIO_AUDIT}"
grep -Fq 'sale_ready=NO' "${RETAIL_RADIO_AUDIT}"
! grep -Fq 'CR6608_RETAIL_' "${RETAIL_RADIO_AUDIT}"
for retail_security_tool in "${RETAIL_PROVISION}" "${RETAIL_SECURITY_AUDIT}"; do
	grep -Fq "PATH='/usr/sbin:/usr/bin:/sbin:/bin'" "${retail_security_tool}"
	! grep -Fq 'CR6608_RETAIL_' "${retail_security_tool}"
done
grep -Fq "AUDIT_BIN='/usr/sbin/cr6608-retail-audit'" "${RETAIL_PROVISION}"
grep -Fq "TLS_PROBE_BIN='/bin/uclient-fetch'" "${RETAIL_SECURITY_AUDIT}"
grep -Fq -- '--root-password-file' "${RETAIL_SECURITY_AUDIT}"
grep -Fq -- '--wifi-key-file' "${RETAIL_SECURITY_AUDIT}"
grep -Fq "CACHE_STATE_LIB='/usr/libexec/cr6608-dashboard-cache-state'" "${RETAIL_PROVISION}"
grep -Fq "APPLY_LOCK='/var/run/cr6608-apply.lock'" "${RETAIL_PROVISION}"
retail_apply_lock_line="$(grep -n '^acquire_apply_lock || fail provisioning_busy$' "${RETAIL_PROVISION}" | cut -d: -f1)"
retail_mutation_lock_line="$(grep -n '^cr6608_dashboard_cache_mutation_begin' "${RETAIL_PROVISION}" | cut -d: -f1)"
[ -n "${retail_apply_lock_line}" ] && [ -n "${retail_mutation_lock_line}" ]
[ "${retail_apply_lock_line}" -lt "${retail_mutation_lock_line}" ]
grep -Fq 'run_without_mutation_fds "$AUDIT_BIN"' "${RETAIL_PROVISION}"
grep -Fq 'run_without_mutation_fds "$PASSWD_BIN" -a sha512 root' "${RETAIL_PROVISION}"
grep -Fq 'stage_wifi_secret_values()' "${RETAIL_PROVISION}"
grep -Fq 'run_without_mutation_fds "$UCI_BIN" -q batch' "${RETAIL_PROVISION}"
! grep -Fq 'key=$wifi_key' "${RETAIL_PROVISION}"
grep -Fq 'wait_post_provision_audit()' "${RETAIL_PROVISION}"
grep -Fq 'AUDIT_READY_MAX_ATTEMPTS=16' "${RETAIL_PROVISION}"
grep -Fq 'post_provision_runtime_timeout' "${RETAIL_PROVISION}"
grep -Fq 'root_password_mismatch' "${RETAIL_SECURITY_AUDIT}"
grep -Fq 'fail provisioning_pending' "${RETAIL_SECURITY_AUDIT}"
grep -Fq 'restore_previous_markers || {' "${RETAIL_PROVISION}"
grep -Fq 'force_pending_state' "${RETAIL_PROVISION}"
grep -Fq 'rollback_transaction 1 >/dev/null 2>&1 || true' "${RETAIL_PROVISION}"
grep -Fq 'create_apply_claim()' "${RETAIL_PROVISION}"
grep -Fq 'ownerless_lock_reclaimable()' "${RETAIL_PROVISION}"
grep -Fq 'hostapd_options' "${RETAIL_PROVISION}"
grep -Fq 'hostapd_bss_options' "${RETAIL_PROVISION}"
grep -Fq 'raw_hostapd_options' "${RETAIL_SECURITY_AUDIT}"
grep -Fq 'raw_hostapd_bss_options' "${RETAIL_SECURITY_AUDIT}"
grep -Fq 'wds_ap_role_not_allowlisted' "${RETAIL_SECURITY_AUDIT}"
grep -Fq 'runtime_primary_ifname()' "${RETAIL_SECURITY_AUDIT}"
grep -Fq 'runtime_primary_ifname()' "${RETAIL_RADIO_AUDIT}"
printf '%s\n' \
	'profile=lab-operator-v1' \
	'sale_ready=NO' \
	'radio_policy=lab-operator-38dbm-ul-muru' | cmp -s - "${ARTIFACT_PROFILE}"
grep -Fq "cmp -s - \"\${rootfs_dir}/etc/cr6608-artifact-profile\"" "${INSPECTOR}"
grep -Fq 'BUILD_PROFILE="${CR6608_BUILD_PROFILE:-lab}"' "${INSPECTOR}"
grep -Fq "ARTIFACT_PROFILE_LABEL='lab_operator'" "${INSPECTOR}"
grep -Fq "ARTIFACT_PROFILE_LABEL='retail_v1'" "${INSPECTOR}"
grep -Fq "printf 'artifact_profile=%s\\n'" "${INSPECTOR}"
grep -Fq 'BUILD_PROFILE="${CR6608_BUILD_PROFILE:-${profile:-lab}}"' "${BUILD}"
grep -Fq "ARTIFACT_PROFILE_LABEL='lab_operator'" "${BUILD}"
grep -Fq "ARTIFACT_PROFILE_LABEL='retail_v1'" "${BUILD}"
grep -Fq "printf 'artifact_profile=%s\\n'" "${BUILD}"
grep -Fq "printf 'sale_ready=NO\\n'" "${BUILD}"
grep -Fq "printf 'retail_radio_gate_status=%s\\n'" \
	"${BUILD}"
grep -Fq 'SRC_CRASHLOG_BUILDER="${SCRIPT_DIR}/crashlog/build-cr6608-crashlog-initramfs.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-maintenance-builder "${SRC_CRASHLOG_BUILDER}"' "${BUILD}"
grep -Fq 'sh "${CRASHLOG_SANITIZE_MOCK_TEST}"' "${BUILD}"
grep -Fq 'bash "${CRASHLOG_BUILD_CONTRACT_TEST}"' "${BUILD}"
grep -Fq 'CR6608_CRASHLOG_SANITIZE_MOCK_TESTS=PASS' "${CRASHLOG_SANITIZER_TEST}"
grep -Fq 'CR6608_CRASHLOG_BUILD_CONTRACT_TESTS=PASS' "${CRASHLOG_BUILD_TEST}"
grep -Fq 'RAM-boot initramfs' "${CRASHLOG_README}"
grep -Fq 'Never write it to NAND' "${CRASHLOG_README}"
grep -Fq 'DASHBOARD_REQUEST_COORDINATION_TEST="${SCRIPT_DIR}/tests/test-dashboard-request-coordination.js"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${DASHBOARD_REQUEST_COORDINATION_TEST}"' "${BUILD}"
grep -Fq '"${DASHBOARD_REQUEST_COORDINATION_TEST}" "${DASHCTL_JSON_BUILDERS_TEST}"' "${BUILD}"
grep -Fq 'node --check "${DASHBOARD_REQUEST_COORDINATION_TEST}"' "${BUILD}"
grep -Fq 'node "${DASHBOARD_REQUEST_COORDINATION_TEST}"' "${BUILD}"
grep -Fq 'dashboard_request_coordination=pass' "${DASHBOARD_REQUEST_COORDINATION_TEST}"
grep -Fq 'dashboard can create browser-persistent state outside Web Storage' "${INSPECTOR}"
grep -Fq 'dashboard image ships a service-worker script' "${INSPECTOR}"
grep -Fq 'dashboard lacks bounded page-client memory eviction' "${INSPECTOR}"
grep -Fq 'dashboard lacks client-overflow alert suppression' "${INSPECTOR}"
grep -Fq 'CONTROL_RECOVERY_TEST="${SCRIPT_DIR}/tests/test-control-recovery-contract.sh"' "${BUILD}"
grep -Fq 'ARGON_LOCALTIME_JS="${SRC_FILES}/www/luci-static/argon/js/cr6608-localtime.js"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${CONTROL_RECOVERY_TEST}"' "${BUILD}"
grep -Fq 'record_regular_input source-ui-asset "${ARGON_LOCALTIME_JS}"' "${BUILD}"
grep -Fq '"${MOBILE_LAYOUT_TEST}" "${CONTROL_RECOVERY_TEST}" "${JSON_CHARSET_TEST}" "${PACKAGE_MANAGER_RUNTIME_TEST}" "${ARGON_MOBILE_CSS}" "${ARGON_LOCALTIME_JS}" "${ARGON_HEADER}"' "${BUILD}"
grep -Fq 'node --check "${ARGON_LOCALTIME_JS}"' "${BUILD}"
grep -Fq 'sh -n "${CONTROL_RECOVERY_TEST}"' "${BUILD}"
grep -Fq 'sh "${CONTROL_RECOVERY_TEST}" | grep -qx '\''control_recovery_contract=pass'\''' "${BUILD}"
grep -Fq 'control_recovery_contract=pass' "${CONTROL_RECOVERY_TEST}"
grep -Fq 'JSON_CHARSET_TEST="${SCRIPT_DIR}/tests/test-json-charset-contract.sh"' "${BUILD}"
grep -Fq 'PACKAGE_MANAGER_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-package-manager-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${JSON_CHARSET_TEST}"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${PACKAGE_MANAGER_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'sh "${JSON_CHARSET_TEST}"' "${BUILD}"
grep -Fq 'sh "${PACKAGE_MANAGER_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'json_charset_contract=pass' "${JSON_CHARSET_TEST}"
grep -Fq 'package_manager_runtime=pass' "${PACKAGE_MANAGER_RUNTIME_TEST}"
grep -Fq '"argon_localtime_js_sha256:${ARGON_LOCALTIME_JS}"' "${BUILD}"
grep -Fq 'USE_EXTERNAL_SIGNING=0' "${BUILD}"
! grep -Fq 'if [ "${CR6608_SOURCE_TEST_ONLY:-0}" = "1" ]' "${BUILD}"
awk '
	index($0, "if [ \"${SOURCE_TEST_ONLY}\" = 0 ]; then") {
		if (getline > 0 && index($0, "for secret_path in") > 0)
			manifest_key_guard = 1
	}
	END { exit(manifest_key_guard ? 0 : 1) }
' "${BUILD}"

contract_tmp="$(mktemp -d)"
trap 'rm -rf -- "${contract_tmp}"' EXIT HUP INT TERM
timeout_policy_probe="${contract_tmp}/feed-timeout-policy.sh"
sed '/^BUILD_PROFILE=/,$d' "${BUILD}" >"${timeout_policy_probe}"
printf '%s\n' 'printf "feed_timeout=%s\n" "${FEED_UPDATE_TIMEOUT_SECONDS}"' >>"${timeout_policy_probe}"
[ "$(env -u CR6608_FEED_UPDATE_TIMEOUT_SECONDS bash "${timeout_policy_probe}")" = 'feed_timeout=900' ]
for valid_timeout in 120 900 1800; do
	[ "$(CR6608_FEED_UPDATE_TIMEOUT_SECONDS="${valid_timeout}" bash "${timeout_policy_probe}")" = \
		"feed_timeout=${valid_timeout}" ]
done
for invalid_timeout in 119 1801 9223372036854775808 0900 invalid; do
	set +e
	CR6608_FEED_UPDATE_TIMEOUT_SECONDS="${invalid_timeout}" \
		bash "${timeout_policy_probe}" >/dev/null 2>&1
	invalid_timeout_status=$?
	set -e
	[ "${invalid_timeout_status}" -ne 0 ]
done

network_classifier_probe="${contract_tmp}/feed-network-classifier.sh"
sed -n '/^feed_update_network_failure() {/,/^}/p' "${BUILD}" >"${network_classifier_probe}"
network_classifier_log="${contract_tmp}/feed-network-classifier.log"
for transient_message in \
	'RPC failed; curl 92 HTTP/2 stream 5 was not closed cleanly' \
	'unexpected disconnect while reading sideband packet' \
	'fatal: early EOF' \
	'fatal: fetch-pack: invalid index-pack output'; do
	printf '%s\n' "${transient_message}" >"${network_classifier_log}"
	bash -c '. "$1"; feed_update_network_failure 1 "$2"' \
		feed-network-test "${network_classifier_probe}" "${network_classifier_log}"
done
printf '%s\n' 'fatal: repository metadata is malformed' >"${network_classifier_log}"
set +e
bash -c '. "$1"; feed_update_network_failure 1 "$2"' \
	feed-network-test "${network_classifier_probe}" "${network_classifier_log}"
non_network_status=$?
set -e
[ "${non_network_status}" -ne 0 ]

source_only_probe="${contract_tmp}/source-only-policy.sh"
sed '/^say()  {/,$d' "${BUILD}" > "${source_only_probe}"
printf '%s\n' \
	'printf "source_test_only=%s\\nfactory_mode=%s\\nfactory_source=%s\\nfactory_output=%s\\nrescue_evidence=%s\\nbrowser_evidence=%s\\n" "${SOURCE_TEST_ONLY}" "${FACTORY38_BUILD_MODE}" "${FACTORY38_SOURCE}" "${FACTORY38_PRIVATE_OUTPUT}" "${RESCUE_REAL_EVIDENCE}" "${BROWSER_TEST_EVIDENCE}"' \
	>> "${source_only_probe}"
source_only_result="$(
	CR6608_SOURCE_TEST_ONLY=1 \
	CR6608_FACTORY38_BUILD_MODE=maintenance \
	CR6608_FACTORY_BACKUP="${contract_tmp}/missing-factory.bin" \
	CR6608_FACTORY38_PRIVATE_OUTPUT="${contract_tmp}/private-output" \
	CR6608_RESCUE_REAL_EVIDENCE="${contract_tmp}/caller-private-rescue-evidence" \
	CR6608_BROWSER_TEST_EVIDENCE="${contract_tmp}/caller-private-browser-evidence" \
	CR6608_RETAIL_COMMISSIONING_MODE=0 \
	CR6608_RETAIL_COMMISSIONING_KEY= \
	bash "${source_only_probe}"
)"
[ "${source_only_result}" = \
	"$(printf 'source_test_only=1\nfactory_mode=normal\nfactory_source=\nfactory_output=\nrescue_evidence=\nbrowser_evidence=')" ]

signing_probe="${contract_tmp}/signing-policy.sh"
{
	printf '%s\n' 'set -euo pipefail' 'die() { exit 97; }'
	awk '
		$0 == "USE_EXTERNAL_SIGNING=0" { copy = 1 }
		copy {
			if ($0 ~ /^for required_(muru_input|file) in /)
				exit
			print
		}
	' "${BUILD}"
	printf '%s\n' 'printf "external_signing=%s\\n" "${USE_EXTERNAL_SIGNING}"'
} > "${signing_probe}"
signing_env_result="$(
	SOURCE_TEST_ONLY=1 \
	SRC_FW_SIGNING_KEY="${contract_tmp}/missing-fw-private" \
	SRC_FW_SIGNING_PUB="${contract_tmp}/missing-fw-public" \
	SRC_FW_SIGNING_CERT="${contract_tmp}/missing-fw-cert" \
	SRC_APK_SIGNING_KEY="${contract_tmp}/missing-apk-private" \
	SRC_APK_SIGNING_PUB="${contract_tmp}/missing-apk-public" \
	bash "${signing_probe}"
)"
[ "${signing_env_result}" = 'external_signing=0' ]
set +e
SOURCE_TEST_ONLY=0 \
SRC_FW_SIGNING_KEY="${contract_tmp}/missing-fw-private" \
SRC_FW_SIGNING_PUB="${contract_tmp}/missing-fw-public" \
SRC_FW_SIGNING_CERT="${contract_tmp}/missing-fw-cert" \
SRC_APK_SIGNING_KEY="${contract_tmp}/missing-apk-private" \
SRC_APK_SIGNING_PUB="${contract_tmp}/missing-apk-public" \
	bash "${signing_probe}" >/dev/null 2>&1
signing_required_status=$?
set -e
[ "${signing_required_status}" -eq 97 ]

grep -Fq 'PLAYWRIGHT_EXPECTED_VERSION="1.58.2"' "${BUILD}"
grep -Fq 'pin_feed_commits()' "${BUILD}"
grep -Fq 'cat-file -e "${expected}^{commit}"' "${BUILD}"
grep -Fq 'Feed ${feed} pin fetch failed (attempt ${attempt}/3); retrying' "${BUILD}"
grep -Fq 'Feed ${feed} changed after its verified update' "${BUILD}"
grep -Fq 'verify_feed_commits' "${BUILD}"
grep -Fq 'AUTH_FIX_COMMIT="2fdeb2311364b8dfe5a31057cf0b8583cdf0c33c"' "${BUILD}"
grep -Fq 'python3 -I -B "${SOURCE_KIT_TOOL}" verify' "${BUILD}"
grep -Fq 'source_auth_fix_commit=${AUTH_FIX_COMMIT}' "${BUILD}"
grep -Fq 'SOURCE_REPOSITORY_MODE="${source_identity_lines[0]#source_repository_mode=}"' "${BUILD}"
grep -Fq 'source_product_version=${PRODUCT_VERSION}' "${BUILD}"
grep -Fq 'source_build_epoch=${BUILD_EPOCH}' "${BUILD}"
grep -Fq 'validate_trusted_source_gate' "${BUILD}"
grep -Fq 'verify_trusted_source_bundle_unchanged' "${BUILD}"
grep -Fq 'CR6608_EXPECTED_SOURCE_BUNDLE_SHA256' "${BUILD}"
grep -Fq 'pass-external-expected-values' "${BUILD}"
grep -Fq 'preserved_config_migration=%s\n' "${BUILD}"
grep -Fq 'auth_fix_commit=%s\n' "${BUILD}"
grep -Fqx '[ -r /etc/fw_env.config ] || exit 0' "${FW_DEFAULTS_GUARD}"
grep -Fqx 'fw_loadenv' "${FW_DEFAULTS_GUARD}"
[ "$(grep -Fxc 'fw_loadenv' "${FW_DEFAULTS_GUARD}")" -eq 1 ]
grep -Fq '"$UCI_BIN" set sqm.smartap.interface='"'"'wan'"'"'' "${SQM_DSA_DEFAULTS}"
grep -Fq "set_default qdisc cake" "${SQM_DSA_DEFAULTS}"
[ "$(grep -Ec '^PRESERVED_CONFIG_MIGRATION_VERSION="[0-9]+"$' "${BUILD}")" -eq 1 ]
[ "$(grep -Ec "^VERSION='[0-9]+'$" "${MIGRATION}")" -eq 1 ]
build_migration_version="$(sed -n 's/^PRESERVED_CONFIG_MIGRATION_VERSION="\([0-9][0-9]*\)"$/\1/p' "${BUILD}")"
script_migration_version="$(sed -n "s/^VERSION='\([0-9][0-9]*\)'$/\1/p" "${MIGRATION}")"
[ "${build_migration_version}" = 8 ]
[ "${script_migration_version}" = "${build_migration_version}" ]
grep -Fq "preserved_config_version=${build_migration_version}" "${README}"
grep -Fq 'historical filename' "${README}"
cmp -s "${BUILD}" "${REMOTE_BUILD}"
mismatch_migration="${contract_tmp}/preserved-config-version-mismatch"
sed "s/^VERSION='${script_migration_version}'$/VERSION='999'/" "${MIGRATION}" > "${mismatch_migration}"
! grep -Fqx "VERSION='${build_migration_version}'" "${mismatch_migration}"
grep -Fqx 'SmartAP CR6608 v86-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM / OpenWrt 25.12.5 (non-sale lab 38 dBm request path; visible open default Wi-Fi; channel 36 default; MT7621 packet steering and EEE disabled; DSA TX-watchdog telemetry; bounded uhttpd recovery and supported security headers; MediaTek 25.12 MURU bitmap port compiled but stable-disabled, with synchronous command-response telemetry that is not apply or OTA proof, a one-way kernel fault latch, and RAM-only qualification profile; live Smart UI retains no telemetry cache; role-correct EasyMesh and carrier-aware port readiness; apk/opkg-aware package actions; UTF-8 JSON; LuCI-owned VLAN preservation with explicit takeover; one-hour live rpcd session validation; password-gated clean/preserved SSH and serial console; distinct per-device Web credential path with explicit sale block; Safe Apply; responsive Smart/Argon UI)' "${VERSION_FILE}"
grep -Fq 'PRODUCT_VERSION="v86"' "${BUILD}"
grep -Fq "printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=0\\n'" "${BUILD}"
grep -Fq 'FINAL_IMAGE="cr6608-SMARTAP-v86-LAB-NONSALE-CANDIDATE-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM-sysupgrade.bin"' "${BUILD}"
grep -Fq 'COMBINED_IMAGE="cr6608-SMARTAP-v86-LAB-NONSALE-CANDIDATE-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM-firmware.bin"' "${BUILD}"
grep -Fq 'INITRAMFS_IMAGE="cr6608-SMARTAP-v86-LAB-NONSALE-CANDIDATE-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM-initramfs-kernel.bin"' "${BUILD}"
grep -Fq 'SECURE_CONSOLE_TEST="${SCRIPT_DIR}/tests/test-secure-console-migration.sh"' "${BUILD}"
grep -Fq '"${SRC_FILES}/etc/uci-defaults/99-cr6608-secure-console"' "${BUILD}"
sed -n "/config wifi-device 'radio1'/,/config wifi-iface/p" "${WIRELESS_DEFAULTS}" |
	grep -Fqx "	option channel '36'"
grep -Fqx "	option channel5 '36'" "${QUICK_DEFAULTS}"
grep -Fqx "	option security 'none'" "${QUICK_DEFAULTS}"
grep -Fqx "	option hide_ssid '0'" "${QUICK_DEFAULTS}"
[ "$(grep -Ec "^[[:space:]]*option radio[01]_enabled '1'$" "${QUICK_DEFAULTS}")" -eq 2 ]
[ "$(grep -Ec "^[[:space:]]*option disabled '0'$" "${WIRELESS_DEFAULTS}")" -eq 4 ]
[ "$(grep -Ec "^[[:space:]]*option encryption 'none'$" "${WIRELESS_DEFAULTS}")" -eq 2 ]
[ "$(grep -Ec "^[[:space:]]*option hidden '0'$" "${WIRELESS_DEFAULTS}")" -eq 2 ]
[ "$(grep -Ec "^[[:space:]]*option ieee80211w '0'$" "${WIRELESS_DEFAULTS}")" -eq 2 ]
! grep -Eq "^[[:space:]]*option (key|sae_password) " "${WIRELESS_DEFAULTS}"
grep -Fq 'smartap-nonlive-rejected-390.png' "${BUILD}"
grep -Fq 'smartap-overview-partial-390.png' "${BUILD}"
for browser_screenshot in \
	smartap-insights-tabs-rtl-360.png \
	smartap-insights-tabs-rtl-390.png \
	smartap-insights-tabs-rtl-430.png \
	smartap-isolation-clearance-1440.png \
	argon-system-ltr-390.png \
	argon-system-rtl-390.png \
	argon-system-ltr-1440.png \
	argon-system-rtl-1440.png; do
	grep -Fq "${browser_screenshot}" "${BUILD}"
done
for build_script in "${BUILD}" "${REMOTE_BUILD}"; do
	grep -Fq 'for design_width in 360 390 430 1440; do' "${build_script}"
	grep -Fq 'for design_language in ar en; do' "${build_script}"
	grep -Fq 'for design_theme in dark light; do' "${build_script}"
	grep -Fq 'smartap-design-${design_language}-${design_theme}-${design_width}.png' "${build_script}"
	grep -Fq 'Required design-system screenshot is missing or unsafe' "${build_script}"
done
! grep -Fq 'argon-system-390.png' "${BUILD}"
for history_export_input in "${BUILD}" "${REMOTE_BUILD}" "${SOURCE_KIT_TOOL}"; do
	! grep -Eq 'format-patch|bundle.*--all' \
		"${history_export_input}"
done
! grep -Fq 'cr6608-candidate-source.patch' "${BUILD}"
grep -Fq 'SOURCE_KIT_TOOL="${SCRIPT_DIR}/tools/cr6608_source_kit.py"' "${BUILD}"
grep -Fq 'SOURCE_KIT_TEST="${SCRIPT_DIR}/tests/test-source-kit-contract.py"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${MANAGEMENT_GUARD_TEST}"' "${BUILD}"
grep -Fq 'INITRAMFS_UBI_DETACH_TEST="${SCRIPT_DIR}/tests/test-initramfs-ubi-detach.sh"' "${BUILD}"
grep -Fq 'SRC_INITRAMFS_UBI_DETACH="${SRC_FILES}/lib/preinit/71_cr6608_initramfs_detach_ubi"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${INITRAMFS_UBI_DETACH_TEST}"' "${BUILD}"
grep -Fq 'initramfs_ubi_detach_contract=pass' "${BUILD}"
grep -Fq 'UL_MURU_GUARD_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-guard-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${UL_MURU_GUARD_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'ul_muru_guard_runtime=pass' "${BUILD}"
grep -Fq 'UL_MURU_VERIFIER_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-verifier-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${UL_MURU_VERIFIER_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'ul_muru_verifier_runtime=pass' "${BUILD}"
grep -Fq 'UL_MURU_DEFAULTS_MIGRATION_TEST="${SCRIPT_DIR}/tests/test-ul-muru-defaults-migration.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${UL_MURU_DEFAULTS_MIGRATION_TEST}"' "${BUILD}"
grep -Fq 'ul_muru_defaults_migration=pass' "${BUILD}"
grep -Fq 'SRC_UL_MURU_DEFERRED="${SRC_FILES}/etc/rc.d/S97cr6608-ul-muru-reconcile"' "${BUILD}"
grep -Fq 'UL_MURU_DEFERRED_RUNTIME_TEST="${SCRIPT_DIR}/tests/test-ul-muru-deferred-runtime.sh"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${UL_MURU_DEFERRED_RUNTIME_TEST}"' "${BUILD}"
grep -Fq 'ul_muru_deferred_runtime=pass' "${BUILD}"
grep -Fq 'record_regular_input source-test "${SECURE_CONSOLE_TEST}"' "${BUILD}"
grep -Fq 'record_regular_input source-kit-tool "${SOURCE_KIT_TOOL}"' "${BUILD}"
grep -Fq 'record_regular_input source-test "${SOURCE_KIT_TEST}"' "${BUILD}"
grep -Fq 'python3 -I -B "${SOURCE_KIT_TEST}"' "${BUILD}"
grep -Fq 'A full build must start from the verified one-root sanitized source bundle' "${BUILD}"
grep -Fq 'source_kit_root_commit_count=1' "${BUILD}"
grep -Fq 'source_kit_reproduction_status=pass' "${BUILD}"
grep -Fq -- '--canonical-bundle "${VERIFIED_SOURCE_BUNDLE}"' "${BUILD}"
grep -Fq -- '--expected-canonical-bundle-sha256 "${TRUSTED_SOURCE_BUNDLE_SHA256}"' "${BUILD}"
grep -Fq 'source_kit_bundle_role=externally-trusted-build-input' "${BUILD}"
grep -Fq 'A full build requires CR6608_RESCUE_REAL_EVIDENCE' "${BUILD}"
grep -Fq 'pass-root-owned-real-netns-v1' "${BUILD}"
grep -Fq 'rescue-real-netns-evidence.txt' "${BUILD}"
grep -Fq 'RESCUE_REAL_EVIDENCE=""' "${BUILD}"
grep -Fq 'GIT_CONFIG_GLOBAL=/dev/null' "${BUILD}"
grep -Fq 'compgen -A variable GIT_' "${BUILD}"
grep -Fq 'CR6608_REQUIRE_REAL_NETNS=1' "${README}"
grep -Fq 'CR6608_RESCUE_REAL_EVIDENCE="$RESCUE_EVIDENCE"' "${README}"
grep -Fq 'source_archive_role=inspection_only_not_build_input' "${BUILD}"
grep -Fq 'source_bundle_role=canonical_reproducible_build_input' "${BUILD}"
grep -Fq 'source-kit-identity.txt' "${BUILD}"
grep -Fq 'source-kit-payload.tsv' "${BUILD}"
grep -Fq 'source-kit-reproduction.txt' "${BUILD}"
grep -Fq 'cr6608-source-kit.tar.xz' "${BUILD}"
grep -Fq 'cr6608-source-kit.bundle' "${BUILD}"
grep -Fq 'git bundle list-heads' "${BUILD}"
grep -Fq 'verify-bundle' "${SOURCE_KIT_TOOL}"
grep -Fq 'expected-bundle-sha256' "${SOURCE_KIT_TOOL}"
grep -Fq 'SHA-256 differs from the trusted value' "${SOURCE_KIT_TOOL}"
grep -Fq 'sanitized repository object closure is not exact' "${SOURCE_KIT_TOOL}"
grep -Fq 'cr6608-sanitized-source-identity-v3' "${SOURCE_KIT_TOOL}"
grep -Fq 'openwrt.config' "${BUILD}"
grep -Fq 'openwrt-package-manifest.txt' "${BUILD}"
grep -Fq 'ui-browser-screenshots.tar.xz' "${BUILD}"
grep -Fq 'ui-browser-screenshots.sha256' "${BUILD}"
grep -Fq "printf 'ui_evidence_manifest_sha256=%s\\n'" "${BUILD}"
grep -Fq "grep -c '^ui_evidence_manifest_sha256='" "${BUILD}"
grep -Fq "sed -n 's/^ui_evidence_manifest_sha256=//p'" "${BUILD}"
grep -Fq 'Source test log must contain exactly one UI evidence manifest hash' "${BUILD}"
grep -Fq 'Bound UI screenshot evidence manifest SHA-256' "${BUILD}"
grep -Fq 'UI screenshot evidence changed after its source-test log binding' "${BUILD}"
grep -Fq 'verify_ui_evidence_unchanged "UI screenshot evidence changed before publication"' "${BUILD}"
grep -Fq 'Mobile layout screenshot matrix is incomplete' "${BUILD}"
grep -Fq 'UI_SCREENSHOT_DIR="${CR6608_UI_SCREENSHOT_DIR:-${SCRIPT_DIR}/.mobile-layout}"' "${BUILD}"
grep -Fq 'export CR6608_UI_SCREENSHOT_DIR="${UI_SCREENSHOT_DIR}"' "${BUILD}"
grep -Fq 'write_ui_evidence_hashes "${ui_evidence_temporary}"' "${BUILD}"
grep -Fq 'tar -C "${UI_SCREENSHOT_PARENT}" -cf - .mobile-layout' "${BUILD}"
grep -Fq 'Refusing to replace wrong overlay symlink' "${BUILD}"
grep -Fq 'find . -type f ! -name SHA256SUMS' "${BUILD}"
grep -Fq 'release_name="candidate-${PRODUCT_VERSION}-${RUN_ID}-${image_sha256:0:16}"' "${BUILD}"
grep -Fq 'current_link_name="current-candidate"' "${BUILD}"
grep -Fq 'PUBLISH_DIR_IDENTITY=' "${BUILD}"
grep -Fq 'PUBLISH_PENDING_IDENTITY=' "${BUILD}"
grep -Fq 'mv -Tn -- "${PUBLISH_DIR}" "${release_dir}"' "${BUILD}"
grep -Fq 'Release publication lost the no-clobber race' "${BUILD}"
grep -Fq 'Release directory identity changed during atomic publication' "${BUILD}"
! grep -Fq 'mv -- "${PUBLISH_DIR}" "${release_dir}"' "${BUILD}"
grep -Fq 'www/luci-static/resources/view/network/wireless.js' "${INSPECTOR}"
grep -Fq 'require_mode lib/preinit/71_cr6608_initramfs_detach_ubi 755' "${INSPECTOR}"
grep -Fq 'require_mode etc/rc.d/S97cr6608-ul-muru-reconcile 755' "${INSPECTOR}"
for build_variant in "${BUILD}" "${REMOTE_BUILD}"; do
	grep -Fq 'etc/init.d etc/hotplug.d etc/rc.d etc/uci-defaults lib/preinit usr/bin usr/sbin usr/libexec www/cgi-bin' \
		"${build_variant}"
done
! grep -Fq 'configured request, outside current driver list; actual may be lower' "${INSPECTOR}"
grep -Fq 'rootfs LuCI wireless view still contains the removed 38 dBm suffix' "${INSPECTOR}"
grep -Fq 'rootfs LuCI Current power is not sourced from the live wireless driver' "${INSPECTOR}"
grep -Fq 'rootfs LuCI Current power is hardcoded to 38 dBm' "${INSPECTOR}"
grep -Fq 'dbm[[:space:]]*<=[[:space:]]*38' "${INSPECTOR}"
grep -Fq 'rootfs LuCI wireless view does not render every 1-38 dBm list entry' "${INSPECTOR}"
grep -Fq 'this\.wifiNetwork\.getTXPower\(\)' "${INSPECTOR}"
grep -Fq 'if file_type == stat.S_IFLNK:' "${INSPECTOR}"
grep -Fq 'return source_data + b"\0"' "${INSPECTOR}"
grep -Fq 'rate-SKU MCU witness verified' "${INSPECTOR}"
grep -Fq 'CR6608_FACTORY38_TARGET_2G' "${INSPECTOR}"
grep -Fq 'CR6608_FACTORY38_TARGET_5G' "${INSPECTOR}"
grep -Fq 'CR6608_FACTORY38_5G_GROUPS' "${INSPECTOR}"
grep -Fq 'CR6608_FACTORY38_SAFE_DELTA_2G' "${INSPECTOR}"
grep -Fq 'CR6608_FACTORY38_SAFE_DELTA_5G' "${INSPECTOR}"
grep -Fq 'volatile target and rate-delta override' "${INSPECTOR}"
grep -Fq 'CR6608-RF firmware EEPROM shadow active' "${INSPECTOR}"
grep -Fq 'mt7915-debugfs-sources.list0' "${INSPECTOR}"
grep -Fq 'prepared mt7915 debugfs source permits an unverified armed SKU write' "${INSPECTOR}"
grep -Fq 'all eight 5 GHz EEPROM channel groups' "${INSPECTOR}"
grep -Fq 'every channel change requires MCU SKU readback' "${INSPECTOR}"
grep -Fq 'CR6608 DTS property and cr6608_rf_38dbm=1 are both required' "${INSPECTOR}"
grep -Fq 'mt7915_cr6608_factory38_raw_match' "${INSPECTOR}"
grep -Fq 'cr6608_factory38_persisted_match' "${INSPECTOR}"
grep -Fq 'mt76_factory38_patch_sha256=' "${BUILD}"
grep -Fq 'FACTORY38_BUILD_MODE="${CR6608_FACTORY38_BUILD_MODE:-normal}"' "${BUILD}"
grep -Fq 'The device-private Factory-38 bundle is available only in maintenance mode' "${BUILD}"
grep -Fq 'INITRAMFS_IMAGE="cr6608-SMARTAP-v86-MAINTENANCE-RAMBOOT-ONLY-initramfs-kernel.bin"' "${BUILD}"
grep -Fq 'PUBLISH_FLASHABLE_IMAGES=0' "${BUILD}"
! grep -Fq 'cr6608-FACTORY38-MAINTENANCE-sysupgrade.bin' "${BUILD}"
! grep -Fq 'cr6608-FACTORY38-MAINTENANCE-firmware.bin' "${BUILD}"
grep -Fq 'CR6608_FACTORY38_PRIVATE_OUTPUT' "${BUILD}"
grep -Fq 'factory38_private_bundle=excluded_from_public_release' "${BUILD}"
! grep -Fq 'factory38_device_bundle=device-factory38' "${BUILD}"
grep -Fq 'FACTORY38_BUNDLE_DIR="${FACTORY38_WORK_DIR}"' "${BUILD}"
grep -Fq 'Track the exact not-yet-created path before mkdir' "${BUILD}"
grep -Fq 'rmdir -- "${FACTORY38_BUNDLE_DIR}"' "${BUILD}"
grep -Fq 'bind_factory38_bundle_to_maintenance_image()' "${BUILD}"
grep -Fq 'verify_factory38_bundle_binding_to_publication()' "${BUILD}"
grep -Fq 'bind_factory38_bundle_to_maintenance_image "${PUBLISH_DIR}/${INITRAMFS_IMAGE}"' "${BUILD}"
grep -Fq 'verify_factory38_bundle_binding_to_publication' "${BUILD}"
grep -Fq 'factory38_binding_schema=cr6608-factory38-maintenance-image-v1' "${BUILD}"
grep -Fq 'FACTORY38_BOUND_SHA256SUMS_SHA256=' "${BUILD}"
grep -Fq 'verify_factory38_bundle_exact_file_set()' "${BUILD}"
grep -Fq 'verify_factory38_bound_checksum_manifest()' "${BUILD}"
grep -Fq 'Factory-38 checksum manifest changed after trusted binding' "${BUILD}"
grep -Fq 'maintenance_initramfs_sha256' "${BUILD}"
grep -Fq 'source_kit_commit' "${BUILD}"
grep -Fq 'image_integrity_gate_status' "${BUILD}"
grep -Fq 'INSPECTOR_EXECUTED_SHA256=' "${BUILD}"
grep -Fq 'INSPECTION_LOG_VERIFIED_SHA256=' "${BUILD}"
grep -Fq 'read_regular_file_sha256()' "${BUILD}"
grep -Fq 'verify_inspection_attestation_unchanged()' "${BUILD}"
grep -Fq 'verify_inspection_attestation_unchanged "${PUBLISH_DIR}"' "${BUILD}"
grep -Fq 'verify_inspection_attestation_unchanged "${release_dir}"' "${BUILD}"
awk '
	/if ! INSPECTOR_EXECUTED_SHA256=.*read_regular_file_sha256/ { inspector_pin = NR }
	/bash "\$\{INSPECTOR\}"/ { inspector_run = NR }
	/initramfs_rootfs_gate_status=pass/ { final_gate = NR }
	/if ! INSPECTION_LOG_VERIFIED_SHA256=.*read_regular_file_sha256/ { log_pin = NR }
	END {
		exit(inspector_pin && inspector_run && inspector_pin < inspector_run &&
			final_gate && log_pin > final_gate ? 0 : 1)
	}
' "${BUILD}"
grep -Fq 'Published maintenance initramfs changed after private binding' "${BUILD}"
grep -Fq 'post-binding maintenance image mutation was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'self-consistent but untrusted private binding mutation was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'SHA256SUMS alone is not a trusted anchor' "${BUILD}"
grep -Fq 'Factory-38 trusted maintenance manifest binding verification failed' "${BUILD}"
grep -Fq 'mv -Tn -- "${FACTORY38_BUNDLE_DIR}" "${FACTORY38_PRIVATE_OUTPUT}"' "${BUILD}"
grep -Fq 'Factory-38 private checksum verification failed after publication' "${BUILD}"
grep -Fq 'Factory-38 private bundle entry-type scan failed before publication' "${BUILD}"
grep -Fq 'Factory-38 private bundle mode scan failed before publication' "${BUILD}"
grep -Fq 'Factory-38 private source identity lookup failed before publication' "${BUILD}"
grep -Fq 'Factory-38 private output identity lookup failed after publication' "${BUILD}"
grep -Fq 'Factory-38 bound private checksum generation or verification failed' "${BUILD}"
grep -Fq 'Public release checksum generation or verification failed' "${BUILD}"
grep -Fq 'Published release checksum verification failed after publication' "${BUILD}"
grep -Fq 'private checksum generation accepted a partial failed find pipeline' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'self-consistent private binary and checksum mutation was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'additional regular mode-0600 private file was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'failed source and output identity lookups were accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'post-execution inspector mutation was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'post-gate source inspection-log mutation was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'staged inspection-log mutation was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
! grep -Fq '[ -z "$(find "${FACTORY38_BUNDLE_DIR}"' "${BUILD}"
! grep -Fq 'mv -- "${FACTORY38_BUNDLE_DIR}" "${FACTORY38_PRIVATE_OUTPUT}"' "${BUILD}"
grep -Fq 'FACTORY38_SOURCE="$(readlink -f -- "${FACTORY38_SOURCE}")"' "${BUILD}"
grep -Fq 'Factory private output parent must have mode 700' "${BUILD}"
grep -Fq 'FACTORY38_PRIVATE_PARENT_IDENTITY=' "${BUILD}"
grep -Fq 'FACTORY38_WORK_IDENTITY=' "${BUILD}"
grep -Fq 'FACTORY38_PENDING_OUTPUT=' "${BUILD}"
grep -Fq 'FACTORY38_PENDING_OUTPUT_IDENTITY=' "${BUILD}"
grep -Fq "stat -c '%d:%i'" "${BUILD}"
grep -Fq 'Unsupported external input path characters' "${BUILD}"
grep -Fq 'Factory-38 manifest validation failed:' "${BUILD}"
grep -Fq 'python3 -I -B - "${manifest}"' "${BUILD}"
! grep -Fq 'assert manifest[' "${BUILD}"
grep -Fq 'factory38_changed_byte_count=36' "${BUILD}"
grep -Fq 'factory38_chain_count=4' "${BUILD}"
grep -Fq 'factory38_2g_channel_groups=1' "${BUILD}"
grep -Fq 'factory38_5g_channel_groups=8' "${BUILD}"
grep -Fq 'factory38_all_supported_channels_targeted=1' "${BUILD}"
grep -Fq 'channel_group_coverage.5g.group_count' "${BUILD}"
grep -Fq 'rf_witness_for_channel' "${FULL_VERIFY}"
grep -Fq 'run_coverage_complete' "${FULL_VERIFY}"
grep -Fq 'RUN_COVERAGE=2.4GHz:' "${FULL_VERIFY}"
grep -Fq '[ "$mcu_witness" = verified ]' "${FULL_VERIFY}"
grep -Fq '($1 + 0) == 38' "${FULL_VERIFY}"
! grep -Fq '($1 + 0) >= 38' "${FULL_VERIFY}"
grep -Fq 'module_bool_is_true' "${TXPOWER_COLLECTOR}"
grep -Fq 'factory38_candidate_crc32=60048964' "${BUILD}"
grep -Fq 'factory38_original_crc32=963cdfeb' "${BUILD}"
grep -Fq 'Normal image must not contain the Factory writer' "${BUILD}"
grep -Fq 'maintenance_initramfs_writable_wifi_forced_disabled_ram_boot_only' "${BUILD}"
grep -Fq 'boot_policy=ram_boot_only_no_sysupgrade_or_firmware_published' "${BUILD}"
grep -Fq 'maintenance-only flashable build artifacts removed after inspection' "${BUILD}"
grep -Fq 'quarantine_maintenance_flashables' "${BUILD}"
grep -Fq 'capture_image_inspection_hashes()' "${BUILD}"
grep -Fq 'verify_image_inspection_hashes_unchanged()' "${BUILD}"
grep -Fq 'verify_published_images_match_inspection()' "${BUILD}"
grep -Fq 'Sysupgrade bytes changed during or after image inspection' "${BUILD}"
grep -Fq 'Published initramfs differs from the inspected image' "${BUILD}"
grep -Fq 'verify_published_images_match_inspection "${release_dir}"' "${BUILD}"
grep -Fq 'inspected_sysupgrade_sha256=%s' "${BUILD}"
grep -Fq 'inspected_combined_firmware_sha256=%s' "${BUILD}"
grep -Fq 'inspected_initramfs_sha256=%s' "${BUILD}"
grep -Fq 'inspected_package_manifest_sha256=%s' "${BUILD}"
grep -Fq 'source image mutation after inspection hash capture was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'published image mutation after inspection was accepted' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'remove_maintenance_flashables_from_bin' "${BUILD}"
grep -Fq 'cleanup_maintenance_flashable_staging' "${BUILD}"
grep -Fq 'MAINTENANCE_BIN_CLEANUP_ARMED=0' "${BUILD}"
grep -Fq '[ "${MAINTENANCE_BIN_CLEANUP_ARMED}" = 1 ] || return 0' "${BUILD}"
grep -Fq '.maintenance-bin-scan.XXXXXX' "${BUILD}"
grep -Fq '.maintenance-bin-rescan.XXXXXX' "${BUILD}"
grep -Fq 'Maintenance flashable appeared during final cleanup rescan' "${BUILD}"
grep -Fq 'maintenance cleanup accepted a failed find scan' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq "trap 'exit 143' TERM" "${BUILD}"
grep -Fq "trap 'cleanup \$?' EXIT" "${BUILD}"
grep -Fq 'original_status=1' "${BUILD}"
grep -Fq 'unarmed EXIT cleanup deleted another invocation output' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'successful build status survived EXIT cleanup scan failure' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'TERM cleanup retained sysupgrade' "${MAINTENANCE_PUBLICATION_TEST}"
grep -Fq 'maintenance flashables quarantined for inspection and tracked by EXIT cleanup' "${BUILD}"
grep -Fq 'MAINTENANCE_PUBLICATION_TEST=' "${BUILD}"
grep -Fq 'maintenance_publication_guard_tests=pass' "${BUILD}"
grep -Fq 'flashable_build_artifacts=quarantined_before_validation_removed_after_inspection_with_exit_signal_cleanup' "${BUILD}"
grep -Fq 'release_name="maintenance-${PRODUCT_VERSION}-${RUN_ID}-${image_sha256:0:16}"' "${BUILD}"
grep -Fq 'current_link_name="current-maintenance"' "${BUILD}"
grep -Fq 'sha256sum -c SHA256SUMS' "${BUILD}"

inspector_call_line="$(grep -n 'bash "${INSPECTOR}" "${images\[0\]}"' "${BUILD}" | head -n 1 | cut -d: -f1)"
factory_generate_call_line="$(grep -n '^[[:space:]]*generate_factory38_bundle$' "${BUILD}" | head -n 1 | cut -d: -f1)"
factory_publish_call_line="$(grep -n '^publish_factory38_bundle$' "${BUILD}" | head -n 1 | cut -d: -f1)"
build_lock_line="$(grep -n 'flock -n "${LOCK_FD}"' "${BUILD}" | head -n 1 | cut -d: -f1)"
maintenance_cleanup_arm_line="$(grep -n '^[[:space:]]*MAINTENANCE_BIN_CLEANUP_ARMED=1$' "${BUILD}" | head -n 1 | cut -d: -f1)"
[ -n "${inspector_call_line}" ] && [ -n "${factory_generate_call_line}" ] && \
	[ "${factory_generate_call_line}" -gt "${inspector_call_line}" ]
[ -n "${factory_publish_call_line}" ] && \
	[ "${factory_publish_call_line}" -gt "${factory_generate_call_line}" ]
[ -n "${build_lock_line}" ] && [ -n "${maintenance_cleanup_arm_line}" ] && \
	[ "${maintenance_cleanup_arm_line}" -gt "${build_lock_line}" ]
grep -Fq '"${initramfs_images[0]}" "${OPENWRT_DIR}" "${OPENWRT_DIR}/files"' "${BUILD}"
grep -Fq 'normal image does not keep Factory read-only' "${INSPECTOR}"
grep -Fq 'maintenance rootfs lacks nandwrite' "${INSPECTOR}"
grep -Fq 'for rescue_busybox_applet in usr/bin/setsid usr/bin/env bin/kill' "${INSPECTOR}"
grep -Fq 'INITRAMFS_IMAGE OPENWRT_DIR STAGED_OVERLAY' "${INSPECTOR}"
grep -Fq 'uImage payload CRC is invalid' "${INSPECTOR}"
grep -Fq 'def resolve_cpio_path(entries, absolute_path):' "${INSPECTOR}"
grep -Fq 'CPIO symlink cycle while resolving' "${INSPECTOR}"
grep -Fq 'CPIO symlink escapes archive root while resolving' "${INSPECTOR}"
grep -Fq 'if data[-1:] != b"\0" or b"\0" in data[:-1]:' "${INSPECTOR}"
grep -Fq 'target = data[:-1].decode("utf-8")' "${INSPECTOR}"
grep -Fq 'initramfs type differs from staged overlay' "${INSPECTOR}"
grep -Fq 'initramfs symlink target differs from staged overlay' "${INSPECTOR}"
grep -Fq 'initramfs_overlay_entries_checked=' "${INSPECTOR}"
grep -Fq 'initramfs_overlay_gate_status=pass' "${INSPECTOR}"
grep -Fq 'factory38_stage_commands_checked=' "${INSPECTOR}"
grep -Fq 'factory38_stage_dependencies_checked=' "${INSPECTOR}"
grep -Fq 'factory38_stage_dependency_gate_status=pass' "${INSPECTOR}"
grep -Fq 'initramfs_rootfs_gate_status=pass' "${INSPECTOR}"
grep -Fq 'maintenance initramfs cannot resolve Factory-38 command' "${INSPECTOR}"
grep -Fq "grep -Eq \"uci\\\\.set\\\\('wireless',[[:space:]]*radio" "${INSPECTOR}"
grep -Fq "grep -Eq \"uci\\\\.unset\\\\('wireless',[[:space:]]*radio" "${INSPECTOR}"

country_set_re="uci\\.set\\('wireless',[[:space:]]*radio\\['\\.name'\\],[[:space:]]*'country',[[:space:]]*value\\)[[:space:]]*;?"
country_unset_re="uci\\.unset\\('wireless',[[:space:]]*radio\\['\\.name'\\],[[:space:]]*'country'\\)[[:space:]]*;?"
for fixture in \
	"uci.set('wireless', radio['.name'], 'country', value); uci.unset('wireless', radio['.name'], 'country');" \
	"uci.set('wireless',radio['.name'],'country',value);uci.unset('wireless',radio['.name'],'country')"; do
	printf '%s\n' "${fixture}" | grep -Eq "${country_set_re}"
	printf '%s\n' "${fixture}" | grep -Eq "${country_unset_re}"
done
! grep -Fq 'release_name="instrumentation-' "${BUILD}"
! grep -Fq 'current-instrumentation' "${BUILD}"
! grep -Fq 'current-lab38' "${BUILD}"
grep -Fq 'never labelled `PASS_38`' "${README}"
grep -Fq 'output/current-maintenance' "${README}"
grep -Fq 'private bundle is maintenance-only' "${README}"
grep -Fq 'bind it to the inspected RAM-only image SHA-256' "${README}"
grep -Fq 'quarantines its' "${README}"
grep -Fq 'checked again against the staged and atomically published release' "${README}"
grep -Fq 'never updates' "${README}"
grep -Fq '`output/current-candidate`' "${README}"

printf 'release_package_contract=pass\n'
