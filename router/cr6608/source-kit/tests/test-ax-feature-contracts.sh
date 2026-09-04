#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
WIRELESS="${ROOT}/files/etc/config/wireless"
VERIFY="${ROOT}/files/usr/sbin/cr6608-ax-verify"
FULL_VERIFY="${ROOT}/files/usr/bin/cr6608-wifi-full-verify"
SEED="${ROOT}/cr6608.seed.config"
SUPPORT="${ROOT}/files/usr/share/cr6608/ax-feature-support"
EASY_VERIFY="${ROOT}/files/usr/sbin/cr6608-easymesh-verify"
PRPL_PACKAGE="${ROOT}/packages/prplmesh/Makefile"
PRPL_INIT="${ROOT}/packages/prplmesh/files/etc/init.d/prplmesh"
PRPL_DEFAULTS="${ROOT}/packages/prplmesh/files/etc/uci-defaults/95-prplmesh-cr6608"
PRPL_CONFIG="${ROOT}/packages/prplmesh/files/etc/config/prplmesh"
PRPL_GCC14_PATCH="${ROOT}/packages/prplmesh/patches/015-gcc14-key-value-parser-cstdint.patch"
PRPL_OVERLOAD_PATCH="${ROOT}/packages/prplmesh/patches/016-gcc14-nl80211-overload-visibility.patch"
PRPL_MOVE_PATCH="${ROOT}/packages/prplmesh/patches/017-gcc14-remove-pessimizing-moves.patch"
PRPL_UCI_PATCH="${ROOT}/packages/prplmesh/patches/021-openwrt-modern-uci-compatibility.patch"
PRPL_HOSTAPD_PATCH="${ROOT}/packages/prplmesh/patches/022-nl80211-hostapd-update-path-and-passive-mode.patch"
PRPL_MULTI_AP_PATCH="${ROOT}/packages/prplmesh/patches/023-nl80211-accept-hostapd-multi-ap-zero.patch"
PRPL_EMPTY_STRING_PATCH="${ROOT}/packages/prplmesh/patches/024-tlvf-empty-char-array-string.patch"
PRPL_STABILITY_PATCH="${ROOT}/packages/prplmesh/patches/025-openwrt-runtime-stability.patch"
IMAGE_INSPECTOR="${ROOT}/inspect-image.sh"
UL_MURU_PATCH="${ROOT}/patches/zzzz-mt7915-cr6608-ul-muru-experimental.patch"
UL_MURU_STOCK_POLICY_PATCH="${ROOT}/patches/zzzzz-mt7915-cr6608-ul-muru-vendor-baseline.patch"
UL_MURU_GUARD="${ROOT}/files/usr/sbin/cr6608-ul-muru-guard"
UL_MURU_VERIFY="${ROOT}/files/usr/sbin/cr6608-ul-muru-verify"
UL_MURU_AIRTEST="${ROOT}/files/usr/sbin/cr6608-ul-muru-airtest"
UL_MURU_INIT="${ROOT}/files/etc/init.d/cr6608-ul-muru-guard"
UL_MURU_DEFAULTS="${ROOT}/files/etc/uci-defaults/98-cr6608-ul-muru-guard"
UL_MURU_DEFERRED="${ROOT}/files/etc/rc.d/S97cr6608-ul-muru-reconcile"
RF_DTS_PATCH="${ROOT}/patches/996-cr6608-dts-rf-38dbm-lab-mode.patch"
UL_MURU_DTS_PATCH="${ROOT}/patches/996a-cr6608-dts-ul-muru-ram-gate.patch"
MT7915_MODULES="${ROOT}/files/etc/modules.d/mt7915e"
BUILD="${ROOT}/build.sh"
BUILD_REMOTE="${ROOT}/build.remote.sh"

fail() {
	printf 'ax feature contract failed: %s\n' "$*" >&2
	exit 1
}

for required_file in "${UL_MURU_PATCH}" "${UL_MURU_STOCK_POLICY_PATCH}" \
	"${RF_DTS_PATCH}" "${UL_MURU_DTS_PATCH}" \
	"${UL_MURU_GUARD}" \
	"${UL_MURU_VERIFY}" "${UL_MURU_AIRTEST}" \
	"${UL_MURU_INIT}" "${UL_MURU_DEFAULTS}" "${UL_MURU_DEFERRED}"; do
	[ -f "${required_file}" ] || fail "missing experimental UL MURU input: ${required_file}"
done
git apply --numstat "${UL_MURU_PATCH}" >/dev/null 2>&1 || \
	fail "experimental UL MURU patch has malformed unified-diff hunks"
git apply --numstat "${UL_MURU_STOCK_POLICY_PATCH}" >/dev/null 2>&1 || \
	fail "MediaTek-vendor UL MURU baseline patch has malformed unified-diff hunks"
for marker in \
	'policy=mediatek-vendor-sta-rec-muru' \
	'cr6608_ul_muru_sta_rec_updates' \
	'cr6608_ul_muru_mimo_capable_updates' \
	'cr6608_muru_capabilities' \
	'ul_ofdma_sta_rec_eligible' \
	'ul_mumimo_capable' \
	'ul_mumimo_capable=%u\n", full' \
	'muru->mimo_ul.full_ul_mimo)' \
	'cr6608_ul_muru_state'; do
	grep -Fq "${marker}" "${UL_MURU_STOCK_POLICY_PATCH}" || \
		fail "MediaTek-vendor UL MURU baseline patch lacks ${marker}"
done
if grep -Eq 'MURU_(CFG_DLUL_LIMIT|SET_DLUL_EN)|mt7915_mcu_set_cr6608_ul_muru' \
	"${UL_MURU_STOCK_POLICY_PATCH}"; then
	fail "unverified legacy global MURU MCU commands remain in the MT7915 port"
fi
if grep -Fq 'full || partial' "${UL_MURU_STOCK_POLICY_PATCH}"; then
	fail "partial-only peers must not be counted as MT7915 UL MU-MIMO capable"
fi

for marker in \
	'muru->cfg.ofdma_ul_en = true;' \
	'muru->cfg.mimo_ul_en = true;' \
	'IEEE80211_HE_PHY_CAP2_UL_MU_FULL_MU_MIMO' \
	'cr6608_ul_muru_allowed' \
	'cr6608_ul_muru' \
	'CR6608 experimental UL MU-MIMO/OFDMA runtime kill switch engaged'; do
	grep -Fq "${marker}" "${UL_MURU_PATCH}" || \
		fail "experimental UL MURU patch lacks ${marker}"
done
! grep -Fq 'mediatek,cr6608-experimental-ul-muru' "${RF_DTS_PATCH}" || \
	fail "stable CR6608 DTS still exposes qualification-only UL MURU"
grep -Fq 'mediatek,cr6608-experimental-ul-muru' "${UL_MURU_DTS_PATCH}" || \
	fail "dedicated UL-lab DTS patch does not add the runtime gate"
grep -Fqx '@@ -6,3 +6,9 @@' "${RF_DTS_PATCH}" || \
	fail "CR6608 DTS patch hunk does not account for both closing braces"
[ "$(grep -Fxc '+};' "${RF_DTS_PATCH}")" -eq 1 ] || \
	fail "CR6608 DTS patch lacks the outer PCIe closing brace"
grep -Fqx '@@ -10,5 +10,6 @@' "${UL_MURU_DTS_PATCH}" || \
	fail "UL-lab DTS patch is not anchored inside the CR6608 PCIe Wi-Fi node"
grep -Fqx 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=0' "${MT7915_MODULES}" || \
	fail "experimental UL MURU is not fail-closed in the candidate module policy"
for build_variant in "${BUILD}" "${BUILD_REMOTE}"; do
	grep -Fq 'SRC_UL_MURU_STOCK_POLICY_PATCH="${SCRIPT_DIR}/patches/zzzzz-mt7915-cr6608-ul-muru-vendor-baseline.patch"' \
		"${build_variant}" || \
		fail "$(basename "${build_variant}") does not stage the MediaTek-vendor UL MURU baseline patch"
	grep -Fq "EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=0 cr6608_muru_mask=0'" \
		"${build_variant}" || \
		fail "$(basename "${build_variant}") lost the fail-closed LAB module policy"
	grep -Fq "EXPECTED_MODULE_LINE='mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0'" \
		"${build_variant}" || \
		fail "$(basename "${build_variant}") lost the unarmed Retail module policy"
	grep -Fq 'printf '\''%s\n'\'' "${EXPECTED_MODULE_LINE}"' "${build_variant}" || \
		fail "$(basename "${build_variant}") does not gate the staged module line by build profile"
	if grep -Fq "printf 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=1\\n'" "${build_variant}"; then
		fail "$(basename "${build_variant}") still arms experimental UL MURU"
	fi
	if grep -Fq "printf 'mt7915e cr6608_rf_38dbm=1\\n'" "${build_variant}"; then
		fail "$(basename "${build_variant}") still contains the obsolete Factory-38-only mt7915e module gate"
	fi
done
grep -Fq "smartap.experimental.ul_muru='0'" "${UL_MURU_DEFAULTS}" || \
	fail "clean first boot does not disable experimental UL MURU"
! grep -Fq "smartap.experimental.ul_muru='1'" "${UL_MURU_DEFAULTS}" || \
	fail "upgrade defaults may silently arm experimental UL MURU"
grep -Fq "option ul_muru '0'" "${ROOT}/files/etc/config/smartap" || \
	fail "clean image does not disable experimental UL MURU"
grep -Fq "option ul_muru_state 'disabled-upstream-hang-risk'" "${ROOT}/files/etc/config/smartap" || \
	fail "clean image lacks the upstream MT7915 hang-risk state"
grep -Fq "disabled-by-guard|reboot-required|rebooting|reboot-failed|fault-latched|retail-disabled" "${UL_MURU_DEFAULTS}" || \
	fail "upgrade migration does not preserve a previous UL MURU guard trip"
for marker in \
	'profile_kind=ul-muru-ram-v1' \
	'target_mask=15' \
	"smartap.experimental.muru_mask='15'" \
	"smartap.experimental.muru_mask='0'" \
	"smartap.experimental.ul_muru_guard='0'" \
	"smartap.experimental.ul_muru_reconcile='1'" \
	'cr6608_ul_muru=0 cr6608_muru_mask=0' \
	"smartap.experimental.ul_muru_guard='1'" \
	"smartap.experimental.ul_muru_reconcile='0'" \
	'/etc/init.d/cr6608-ul-muru-guard disable' \
	'/etc/init.d/cr6608-ul-muru-guard enable'; do
	grep -Fq "$marker" "${UL_MURU_DEFAULTS}" || \
		fail "UL MURU migration lacks service-policy gate: $marker"
done
! grep -Fq '/etc/init.d/cr6608-ul-muru-guard start' "${UL_MURU_DEFAULTS}" || \
	fail "UL MURU guard starts inside UCI defaults before later migrations commit"
for marker in \
	'[ "${1:-}" = boot ]' \
	'smartap.experimental.ul_muru_guard' \
	'smartap.experimental.ul_muru_reconcile' \
	'"$GUARD_INIT" running' \
	'"$GUARD_INIT" start'; do
	grep -Fq "$marker" "${UL_MURU_DEFERRED}" || \
		fail "UL MURU late-boot reconciler lacks: $marker"
done

for marker in \
	'cr6608_ul_muru=0' \
	'cr6608_muru_mask=0' \
	'fault_latched' \
	'sta_rec_attempted' \
	'sta_rec_response_ok' \
	'sta_rec_failed' \
	'sta_rec_timeout' \
	'ul-muru-ram-v1' \
	'SYS_RESET_COUNT:' \
	'Message[[:space:]]+[[:xdigit:]]+[[:space:]]+timeout' \
	'wifi subsystem reset failure' \
	'Could not release semaphore' \
	'Timeout for initializing firmware' \
	'Firmware did not enter download state' \
	'chip full reset failed' \
	'driver-gates-${MASK_NODE_MATCHING}-of-${MASK_NODE_COUNT}' \
	'${reason}-wiphy-capability-refresh' \
	'uci -q set smartap.experimental.ul_muru=' \
	'uci -q set smartap.experimental.muru_mask=' \
	'[ "$(uci -q get smartap.experimental.ul_muru 2>/dev/null)" = 0 ]' \
	'cannot retract them' \
	'write_state rebooting' \
	'/sbin/reboot' \
	'automatic reboot refused because the persistent MURU disable was not verified' \
	'write_state disabled' \
	'driver_contract_matches 0' \
	'driver_contract_matches 15' \
	'startup-disabled-policy-runtime-mismatch' \
	'startup-enabled-policy-runtime-mismatch'; do
	grep -Fq "${marker}" "${UL_MURU_GUARD}" || \
		fail "UL MURU guard lacks ${marker}"
done
for marker in \
	'matching_signatures()' \
	'signature_snapshot()' \
	'signatures_are_pure_suffix()' \
	'signature_baseline_lines="$(matching_signatures)"' \
	'signature_baseline_snapshot="$(signature_snapshot "$signature_baseline_lines")"' \
	'signature_baseline_fingerprint="${signature_baseline_snapshot#*:}"' \
	'[ "$current_signature_fingerprint" != "$signature_baseline_fingerprint" ]' \
	'! signatures_are_pure_suffix "$signature_baseline_lines" "$current_signature_lines"' \
	'signature_baseline_lines="$current_signature_lines"' \
	'a proven pure suffix eviction'; do
	grep -Fq "${marker}" "${UL_MURU_GUARD}" || \
		fail "UL MURU guard lacks post-arm signature baseline protection: ${marker}"
done
grep -Fq 'write_state reboot-required' "${UL_MURU_GUARD}" || \
	fail "UL MURU guard must report a failed runtime kill switch"
for marker in \
	'/usr/libexec/cr6608-private-runtime' \
	'cr6608_private_runtime_dir ul-muru' \
	'cr6608_private_mktemp "$UL_MURU_RUNTIME_DIR" state' \
	'cr6608_private_publish_file "$state_tmp" "$STATE_FILE"'; do
	grep -Fq "${marker}" "${UL_MURU_GUARD}" || \
		fail "UL MURU guard lacks private atomic state handling: ${marker}"
done
! grep -Fq '/tmp/cr6608-ul-muru-state' "${UL_MURU_GUARD}" || \
	fail "UL MURU guard still writes a predictable world-writable state path"
persist_line="$(grep -nF 'persist_disabled_module_policy || persisted=0' "${UL_MURU_GUARD}" | tail -n 1 | cut -d: -f1)"
reboot_line="$(grep -nF '"$REBOOT_CMD"' "${UL_MURU_GUARD}" | tail -n 1 | cut -d: -f1)"
[ -n "$persist_line" ] && [ -n "$reboot_line" ] && [ "$persist_line" -lt "$reboot_line" ] || \
	fail "UL MURU guard may reboot before verifying the persistent disable"
sh "${UL_MURU_GUARD}" --signature-self-test | \
	grep -qx 'ul_muru_guard_signature_self_test=pass' || \
	fail "UL MURU guard does not recognize the observed MT7915 MCU failure signatures"
if grep -Eq 'uci[^#]*(set|delete|rename|commit)[^#]*wireless|option[[:space:]]+ssid' \
	"${UL_MURU_GUARD}"; then
	fail "UL MURU guard must not change SSIDs or wireless UCI"
fi
for marker in \
	'Full Bandwidth UL MU-MIMO' \
	'RESULT_UL_MURU_FW_POLICY=STABLE_DISABLED_UPSTREAM_HANG_RISK' \
	'RESULT_UL_MURU_HOST_PATH=DISABLED' \
	'NOT_APPLICABLE_DISABLED' \
	'persistent_module_state' \
	'next-boot module policy' \
	'driver policies disabled' \
	'mediatek-25.12-mu-onoff-sta-rec-port' \
	'fault_latched' \
	'sta_rec_attempted' \
	'RESULT_UL_MURU_MASK=0' \
	'RESULT_UL_MURU_MASK=15' \
	'firmware MURU stats query' \
	'temporarily-enabled' \
	'restore_muru_debug' \
	"trap 'exit 143' TERM" \
	'firmware MURU stats radios' \
	'[ "$stats_count" -eq "$mask_count" ]' \
	'RESULT_UL_MURU_FW_POLICY=MEDIATEK_VENDOR_STA_REC_ARMED' \
	'Total HE MU-MIMO UL TB PPDU count:' \
	'Total HE OFDMA UL TB PPDU count:' \
	'RESULT_UL_MURU_HOST_PATH=ARMED' \
	'RESULT_UL_MUMIMO_AGGREGATE_RADIO_COUNTER=NONZERO_NOT_CLIENT_ATTRIBUTED' \
	'RESULT_UL_OFDMA_AGGREGATE_RADIO_COUNTER=NONZERO_NOT_CLIENT_ATTRIBUTED' \
	'RESULT_UL_MURU_AGGREGATE_RADIO_COUNTERS=BOTH_NONZERO_NOT_CLIENT_ATTRIBUTED' \
	'EVIDENCE_SCOPE=AGGREGATE_RADIO_COUNTERS_NOT_CLIENT_ATTRIBUTION' \
	'CLIENT_ATTRIBUTED_OTA_PROOF=REQUIRES_PER_PEER_SCHEDULER_TELEMETRY_OR_PACKET_CAPTURE_HARDWARE'; do
	grep -Fq "${marker}" "${UL_MURU_VERIFY}" || \
		fail "UL MURU verifier lacks ${marker}"
done
for marker in \
	'Connect at least two Wi-Fi 6 clients' \
	'selected AP interface' \
	'selected firmware stats phy' \
	'associated HE stations same radio' \
	'full-bandwidth UL MU-MIMO clients' \
	'capable_clients_file' \
	'"$debugfs_root/$target_phy/mt76/muru_stats"' \
	'ul_mumimo_full=1' \
	'two-client overlapping 2s samples' \
	'UL MU-MIMO TB PPDU delta' \
	'UL OFDMA TB PPDU delta' \
	'RESULT_UL_MURU_AIRTEST=PREREQUISITE_MISSING_TWO_HE_CLIENTS' \
	'RESULT_UL_MURU_AIRTEST=PREREQUISITE_MISSING_TWO_FULL_BW_UL_MUMIMO_CLIENTS' \
	'RESULT_UL_MURU_AIRTEST=ERROR_QUALIFICATION_GATE_NOT_ARMED_BEFORE' \
	'RESULT_UL_MURU_AIRTEST=ERROR_QUALIFICATION_GATE_NOT_ARMED_AFTER' \
	'qualification_gate_armed()' \
	'candidate_mask' \
	'fault_latched' \
	'RESULT_UL_MUMIMO_RADIO_COUNTER_CORRELATION=OBSERVED_IN_WINDOW' \
	'RESULT_UL_OFDMA_RADIO_COUNTER_CORRELATION=OBSERVED_IN_WINDOW' \
	'RESULT_UL_MURU_AIRTEST=BOTH_RADIO_COUNTERS_CORRELATED_NOT_CLIENT_ATTRIBUTED' \
	'EVIDENCE_SCOPE=AGGREGATE_SAME_RADIO_COUNTER_CORRELATION_NOT_CLIENT_ATTRIBUTION' \
	'CLIENT_ATTRIBUTED_OTA_PROOF=REQUIRES_PER_PEER_SCHEDULER_TELEMETRY_OR_PACKET_CAPTURE_HARDWARE'; do
	grep -Fq "${marker}" "${UL_MURU_AIRTEST}" || \
		fail "UL MURU controlled airtime test lacks ${marker}"
done
if grep -Fq '"$debugfs_root"/phy*/mt76/muru_stats' "${UL_MURU_AIRTEST}"; then
	fail "UL MURU airtime test must not aggregate counters from unrelated phys"
fi
if grep -Eq 'uci[^#]*(set|delete|rename|commit)[^#]*wireless|option[[:space:]]+ssid' \
	"${UL_MURU_AIRTEST}"; then
	fail "UL MURU airtime test must not change SSIDs or wireless UCI"
fi

radio_block() {
	radio="$1"
	awk -v wanted="${radio}" '
		$1 == "config" {
			section = $3
			gsub(/\r/, "", section)
			gsub(/\047/, "", section)
			active = ($2 == "wifi-device" && section == wanted)
			next
		}
		active { print }
	' "${WIRELESS}" | tr -d '\r'
}

require_radio_option() {
	radio="$1"
	key="$2"
	value="$3"
	radio_block "${radio}" | grep -Fqx "	option ${key} '${value}'" || \
		fail "${radio} must set ${key}=${value}"
}

for package in \
	kmod-cfg80211 \
	kmod-mac80211 \
	kmod-mt7915e \
	kmod-mt7915-firmware \
	prplmesh \
	wpad-openssl; do
	grep -Fqx "CONFIG_PACKAGE_${package}=y" "${SEED}" || \
		fail "seed lacks ${package}"
done

for required_file in "${EASY_VERIFY}" "${PRPL_PACKAGE}" "${PRPL_INIT}" \
	"${PRPL_DEFAULTS}" "${PRPL_CONFIG}" "${PRPL_GCC14_PATCH}" \
	"${PRPL_UCI_PATCH}" "${PRPL_HOSTAPD_PATCH}" "${PRPL_MULTI_AP_PATCH}" \
	"${PRPL_STABILITY_PATCH}"; do
	[ -f "${required_file}" ] || fail "missing prplMesh input: ${required_file}"
done
grep -Fq '#include <cstdint>' "${PRPL_GCC14_PATCH}" || \
	fail "GCC 14 key-value parser compatibility patch lacks cstdint"
[ -f "${PRPL_OVERLOAD_PATCH}" ] || \
	fail "missing GCC 14 NL80211 overload visibility patch"
grep -Fq 'using nl_genl_socket::send_receive_msg;' "${PRPL_OVERLOAD_PATCH}" || \
	fail "GCC 14 NL80211 compatibility patch hides the inherited overload"
[ -f "${PRPL_MOVE_PATCH}" ] || fail "missing GCC 14 copy-elision patch"
[ "$(grep -Fc -- '-        auto agent_name = std::move(std::string' "${PRPL_MOVE_PATCH}")" -eq 2 ] || \
	fail "GCC 14 copy-elision patch does not cover both agent-name temporaries"
grep -Fq -- '-        std::move(std::set<std::string>' "${PRPL_MOVE_PATCH}" || \
	fail "GCC 14 copy-elision patch does not cover the temporary set"
grep -Fq -- '-        result = std::move(std::make_unique' "${PRPL_MOVE_PATCH}" || \
	fail "GCC 14 copy-elision patch does not cover the temporary unique_ptr"

for marker in \
	'PKG_VERSION:=4.3.1' \
	'PKG_SOURCE_VERSION:=25ffcee47f57343e1798c9488f6f802fccc0e0ff' \
	'PKG_HASH:=8a21124cab0ec71fd235662b561717104d92dda323676cf1244124f86ff41d73' \
	'-DBWL_TYPE=NL80211' \
	'-DENABLE_NBAPI=OFF' \
	'-DUSE_PRPLMESH_WHM=OFF' \
	'-DBEEROCKS_BRIDGE_IFACE=br-lan' \
	'-DBEEROCKS_BH_WIRE_IFACE=lan1' \
	'-DBEEROCKS_WLAN1_IFACE=phy0-ap0' \
	'-DBEEROCKS_WLAN2_IFACE=phy1-ap0' \
	'-DBEEROCKS_MONITOR_POLLING_RATE_MSEC=1000' \
	'-DBEEROCKS_CONTROLLER_LOG_SIZE=262144' \
	'-DBEEROCKS_AGENT_LOG_SIZE=262144' \
	'-DBEEROCKS_LOG_FILES_AUTO_ROLL=true' \
	'+getopt' \
	'+wpad-openssl'; do
	grep -Fq -- "${marker}" "${PRPL_PACKAGE}" || \
		fail "prplMesh package lacks ${marker}"
done

for binary in ieee1905_transport beerocks_controller beerocks_agent; do
	grep -Fq "${binary}" "${PRPL_INIT}" || fail "init lacks ${binary}"
	grep -Fq "${binary}" "${EASY_VERIFY}" || fail "verifier lacks ${binary}"
done
grep -Fq 'beerocks_fronthaul beerocks_cli; do' "${EASY_VERIFY}" || \
	fail "verifier does not check the complete prplMesh 4.3.1 executable set"
if grep -Fq 'prplmesh_cli' "${EASY_VERIFY}" "${IMAGE_INSPECTOR}"; then
	fail "prplMesh 4.3.1 verifier requests a nonexistent prplmesh_cli binary"
fi
grep -Fq 'prepare_platform_db "$mode" "$operating_mode"' "${PRPL_INIT}" || \
	fail "init does not prepare the required runtime platform database"
grep -Fq 'wireless.%s.ssid=%s' "${PRPL_INIT}" || \
	fail "init does not generate per-radio runtime credentials"
grep -Fq 'example credentials' "${EASY_VERIFY}" || \
	fail "runtime verifier does not reject upstream example credentials"
grep -Fq 'process stability (8s)' "${EASY_VERIFY}" || \
	fail "runtime verifier does not check process stability"
grep -Fq 'readlink -f "$proc/exe"' "${EASY_VERIFY}" || \
	fail "runtime verifier does not handle Linux process-name truncation"
if grep -Eq '^[[:space:]]*([^#].*=.*)?pidof([[:space:]]|$)' "${EASY_VERIFY}"; then
	fail "EasyMesh verifier still relies on truncated kernel process names"
fi
grep -Fq 'send ACTION_APMANAGER_JOINED_NOTIFICATION' "${EASY_VERIFY}" || \
	fail "runtime verifier does not use an INFO-level AP readiness event"
grep -Fq 'Finished M2 parsing with .* and 0 errors' "${EASY_VERIFY}" || \
	fail "runtime verifier does not require successful WSC M2 processing"
grep -Fq 'control-plane error scan' "${EASY_VERIFY}" || \
	fail "runtime verifier does not reject known EasyMesh failures"
grep -Fq 'wired backhaul FSM' "${EASY_VERIFY}" || \
	fail "runtime verifier does not require an operational wired backhaul"
grep -Fq 'AP manager' "${EASY_VERIFY}" || \
	fail "runtime verifier does not require operational per-radio managers"
grep -Fq '$(INSTALL_CONF) ./files/etc/config/prplmesh' "${PRPL_PACKAGE}" || \
	fail "package does not install a persistent prplMesh UCI configuration"
grep -Fq 'PRPLMESH_PASSIVE_MODE=$PRPLMESH_PASSIVE' "${PRPL_INIT}" || \
	fail "init does not protect the existing OpenWrt wireless configuration"
grep -Fq 'config_get_bool operational config operational 0' "${PRPL_INIT}" || \
	fail "init does not require the operational runtime gate"
grep -Fq 'active control requires active_control_confirmed=1' "${PRPL_INIT}" || \
	fail "init does not guard active wireless control"
operational_gate_line="$(grep -nF 'config_get_bool operational config operational 0' \
	"${PRPL_INIT}" | cut -d: -f1)"
active_gate_line="$(grep -nF 'active control requires active_control_confirmed=1' \
	"${PRPL_INIT}" | cut -d: -f1)"
runtime_cleanup_line="$(grep -nF 'prepare_runtime_dirs || {' "${PRPL_INIT}" | cut -d: -f1)"
[ -n "${operational_gate_line}" ] && [ -n "${active_gate_line}" ] && \
	[ -n "${runtime_cleanup_line}" ] && \
	[ "${operational_gate_line}" -lt "${runtime_cleanup_line}" ] && \
	[ "${active_gate_line}" -lt "${runtime_cleanup_line}" ] || \
	fail "prplMesh may mutate runtime state before both safety gates pass"

prplmesh_gate_runtime_test() (
	. "${PRPL_INIT}"
	test_enable=0
	test_operational=0
	test_passive=1
	test_active_control=0
	last_log=

	config_load() { :; }
	config_get() {
		case "$3" in
			management_mode) value=Multi-AP-Controller-and-Agent ;;
			operating_mode) value=Gateway ;;
			*) value="${4-}" ;;
		esac
		eval "$1=\$value"
	}
	config_get_bool() {
		case "$3" in
			enable) value="$test_enable" ;;
			operational) value="$test_operational" ;;
			passive_mode) value="$test_passive" ;;
			active_control_confirmed) value="$test_active_control" ;;
			*) value="${4-0}" ;;
		esac
		eval "$1=\$value"
	}
	logger() { last_log="$*"; }
	# Crossing either gate would reach one of these mutations and fail the test.
	rm() { exit 91; }
	mkdir() { exit 92; }
	ebtables() { exit 93; }

	start_service || exit 1
	[ -z "$last_log" ] || exit 2

	test_enable=1
	last_log=
	start_service || exit 3
	[ "$last_log" = \
		'-t prplmesh enable requested while the operational gate is closed; refusing start' ] || \
		exit 4

	test_operational=1
	test_passive=0
	last_log=
	if start_service; then
		exit 5
	fi
	[ "$last_log" = \
		'-t prplmesh active control requires active_control_confirmed=1; refusing start' ] || \
		exit 6

	printf 'prplmesh_gate_runtime=pass\n'
)
[ "$(prplmesh_gate_runtime_test)" = prplmesh_gate_runtime=pass ] || \
	fail "prplMesh safety gates failed their mocked runtime test"
for runtime_marker in \
	'PRPLMESH_RUNTIME_DIR="${CR6608_PRPLMESH_RUNTIME_DIR:-/tmp/beerocks}"' \
	'runtime_paths_allowed()' \
	'rm -rf -- "$PRPLMESH_RUNTIME_DIR"' \
	'mkdir -m 0700 "$PRPLMESH_RUNTIME_DIR"' \
	'runtime_dir_secure "$PRPLMESH_RUNTIME_DIR"' \
	'prepare_runtime_dirs || {'; do
	grep -Fq "$runtime_marker" "${PRPL_INIT}" ||
		fail "prplMesh private runtime contract lacks ${runtime_marker}"
done
! grep -Fq 'mkdir -p /tmp/beerocks' "${PRPL_INIT}" ||
	fail "prplMesh still follows a predictable /tmp runtime directory"

case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW*|MSYS*) ;;
	*)
		prplmesh_runtime_hostile_test() (
			test_root="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-prplmesh-test.XXXXXX")" || exit 1
			trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
			mkdir -m 0700 "$test_root/victim"
			printf 'preserve\n' >"$test_root/victim/proof"
			ln -s "$test_root/victim" "$test_root/beerocks"
			CR6608_PRPLMESH_RUNTIME_DIR="$test_root/beerocks"
			CR6608_PRPLMESH_CONTROL_DIR="$test_root/control"
			CR6608_PRPLMESH_EXPECT_UID="$(id -u)"
			CR6608_PRPLMESH_TEST_MODE=1
			export CR6608_PRPLMESH_RUNTIME_DIR CR6608_PRPLMESH_CONTROL_DIR
			export CR6608_PRPLMESH_EXPECT_UID CR6608_PRPLMESH_TEST_MODE
			. "${PRPL_INIT}"
			prepare_runtime_dirs || exit 2
			[ -f "$test_root/victim/proof" ] || exit 3
			[ -d "$test_root/beerocks" ] && [ ! -L "$test_root/beerocks" ] || exit 4
			[ "$(stat -c '%u:%a' "$test_root/beerocks")" = "$(id -u):700" ] || exit 5
			[ "$(stat -c '%u:%a' "$test_root/beerocks/logs")" = "$(id -u):700" ] || exit 6

			rm -rf -- "$test_root/beerocks"
			mkdir() {
				mkdir_last=""
				for mkdir_arg in "$@"; do mkdir_last="$mkdir_arg"; done
				if [ "$mkdir_last" = "$test_root/beerocks" ]; then
					ln -s "$test_root/victim" "$test_root/beerocks"
					return 1
				fi
				command mkdir "$@"
			}
			if prepare_runtime_dirs; then exit 7; fi
			[ -f "$test_root/victim/proof" ] || exit 8
			printf 'prplmesh_runtime_hostile=pass\n'
		)
		[ "$(prplmesh_runtime_hostile_test)" = prplmesh_runtime_hostile=pass ] ||
			fail "prplMesh hostile runtime-path test failed"
		;;
esac
grep -Fq 'band_steering=0' "${PRPL_INIT}" || \
	fail "passive mode does not suppress stale steering settings"
grep -Fq "option active_control_confirmed '0'" "${PRPL_CONFIG}" || \
	fail "persistent prplMesh defaults do not gate active control"
grep -Fq "set prplmesh.config.active_control_confirmed='0'" "${PRPL_DEFAULTS}" || \
	fail "preserved-overlay migration does not gate active control"
for preserved_gate in enable operational active_control_confirmed; do
	grep -Fq '"$UCI_BIN" -q set "prplmesh.config.'"${preserved_gate}"'=0"' \
		"${PRPL_DEFAULTS}" || \
		fail "preserved-overlay migration does not reset ${preserved_gate}"
done
grep -Fq 'close_preserved_runtime_gates || exit 1' "${PRPL_DEFAULTS}" || \
	fail "preserved-overlay gate migration is not fail-closed"
preserved_enable_line="$(grep -nF '"$UCI_BIN" -q set "prplmesh.config.enable=0"' \
	"${PRPL_DEFAULTS}" | sed -n '1s/:.*//p')"
preserved_commit_line="$(grep -nF '"$UCI_BIN" -q commit prplmesh' \
	"${PRPL_DEFAULTS}" | sed -n '1s/:.*//p')"
preserved_sync_line="$(grep -nF 'wireless_ap_section()' "${PRPL_DEFAULTS}" | \
	sed -n '1s/:.*//p')"
[ -n "${preserved_enable_line}" ] && [ -n "${preserved_commit_line}" ] && \
	[ -n "${preserved_sync_line}" ] && \
	[ "${preserved_enable_line}" -lt "${preserved_commit_line}" ] && \
	[ "${preserved_commit_line}" -lt "${preserved_sync_line}" ] || \
	fail "preserved prplMesh gates are not committed before wireless sync"

prplmesh_preserved_defaults_test() (
	test_dir="$(mktemp -d "${TMPDIR:-/tmp}/prplmesh-defaults.XXXXXX")" || exit 1
	trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
	state="${test_dir}/state"
	log="${test_dir}/uci.log"
	mock_uci="${test_dir}/uci"
	config="${test_dir}/prplmesh"
	: > "${config}"
	printf 'enable=1\noperational=1\nactive_control_confirmed=1\n' > "${state}"
	: > "${log}"
	cat > "${mock_uci}" <<'EOF'
#!/bin/sh
set -eu

[ "${1-}" = -q ] && shift
command="${1-}"
[ "$#" -eq 0 ] || shift

read_state() {
	# Test-only file contains three numeric assignments written by this mock.
	. "${MOCK_UCI_STATE}"
}

write_state() {
	state_tmp="${MOCK_UCI_STATE}.tmp.$$"
	{
		printf 'enable=%s\n' "${enable}"
		printf 'operational=%s\n' "${operational}"
		printf 'active_control_confirmed=%s\n' "${active_control_confirmed}"
	} > "${state_tmp}"
	mv "${state_tmp}" "${MOCK_UCI_STATE}"
}

case "${command}" in
	get)
		case "${1-}" in
			prplmesh.config) printf '%s\n' prplmesh ;;
			prplmesh.config.enable)
				read_state; printf '%s\n' "${enable}" ;;
			prplmesh.config.operational)
				read_state; printf '%s\n' "${operational}" ;;
			prplmesh.config.active_control_confirmed)
				read_state; printf '%s\n' "${active_control_confirmed}" ;;
			*) exit 1 ;;
		esac
		;;
	set)
		assignment="${1-}"
		key="${assignment%%=*}"
		value="${assignment#*=}"
		read_state
		case "${key}" in
			prplmesh.config.enable) enable="${value}" ;;
			prplmesh.config.operational) operational="${value}" ;;
			prplmesh.config.active_control_confirmed)
				active_control_confirmed="${value}" ;;
			*) exit 2 ;;
		esac
		write_state
		printf 'set:%s=%s\n' "${key}" "${value}" >> "${MOCK_UCI_LOG}"
		;;
	commit)
		read_state
		printf 'commit:%s:%s/%s/%s\n' "${1-}" "${enable}" \
			"${operational}" "${active_control_confirmed}" >> "${MOCK_UCI_LOG}"
		[ "${MOCK_UCI_FAIL_COMMIT:-0}" -ne 1 ] || exit 70
		;;
	show)
		[ "${1-}" = wireless ] || exit 3
		;;
	batch)
		# A preserved config must never enter the new-config batch path.
		exit 4
		;;
	*) exit 5 ;;
esac
EOF
	chmod 755 "${mock_uci}"

	PRPLMESH_UCI_BIN="${mock_uci}" PRPLMESH_CONFIG="${config}" \
		MOCK_UCI_STATE="${state}" MOCK_UCI_LOG="${log}" \
		sh "${PRPL_DEFAULTS}" || exit 10
	. "${state}"
	[ "${enable}/${operational}/${active_control_confirmed}" = 0/0/0 ] || exit 11
	[ "$(grep -m1 '^commit:' "${log}")" = 'commit:prplmesh:0/0/0' ] || exit 12

	# A second run must converge to the same safe state.
	PRPLMESH_UCI_BIN="${mock_uci}" PRPLMESH_CONFIG="${config}" \
		MOCK_UCI_STATE="${state}" MOCK_UCI_LOG="${log}" \
		sh "${PRPL_DEFAULTS}" || exit 13
	. "${state}"
	[ "${enable}/${operational}/${active_control_confirmed}" = 0/0/0 ] || exit 14

	# A failed commit must abort the migration while all pending gates stay shut.
	printf 'enable=1\noperational=1\nactive_control_confirmed=1\n' > "${state}"
	if PRPLMESH_UCI_BIN="${mock_uci}" PRPLMESH_CONFIG="${config}" \
		MOCK_UCI_STATE="${state}" MOCK_UCI_LOG="${log}" MOCK_UCI_FAIL_COMMIT=1 \
		sh "${PRPL_DEFAULTS}"; then
		exit 15
	fi
	. "${state}"
	[ "${enable}/${operational}/${active_control_confirmed}" = 0/0/0 ] || exit 16

	printf 'prplmesh_preserved_defaults=pass\n'
)
[ "$(prplmesh_preserved_defaults_test)" = prplmesh_preserved_defaults=pass ] || \
	fail "preserved prplMesh safety-gate migration failed its UCI mock test"
grep -Fq '"band", band' "${PRPL_UCI_PATCH}" || \
	fail "UCI compatibility patch does not support modern OpenWrt band"
grep -Fq -- '+        std::string hwmode;' "${PRPL_UCI_PATCH}" || \
	fail "UCI compatibility patch does not keep the fallback hwmode in function scope"
grep -Fq -- '-        std::string hwmode;' "${PRPL_UCI_PATCH}" || \
	fail "UCI compatibility patch leaves a shadowed block-scoped hwmode"
grep -Fq '(band.empty() ? hwmode : band)' "${PRPL_UCI_PATCH}" || \
	fail "UCI compatibility patch cannot log the selected modern or legacy band"
grep -Fq 'passive OpenWrt mode keeps netifd hostapd data intact' "${PRPL_HOSTAPD_PATCH}" || \
	fail "NL80211 patch lacks the non-disruptive OpenWrt integration"
grep -Fq 'UPDATE " + conf.file_name()' "${PRPL_HOSTAPD_PATCH}" || \
	fail "NL80211 patch does not provide hostapd the update path"
[ "$(grep -c '^diff --git ' "${PRPL_EMPTY_STRING_PATCH}")" -eq 1 ] || \
	fail "TLVF empty-string patch must modify exactly one source file"
grep -Fq 'diff --git a/framework/tlvf/tlvf.py b/framework/tlvf/tlvf.py' \
	"${PRPL_EMPTY_STRING_PATCH}" || \
	fail "TLVF empty-string patch targets the wrong source file"
grep -Fq 'if (m_%s_idx__ == 0) { return std::string(); }' \
	"${PRPL_EMPTY_STRING_PATCH}" || \
	fail "TLVF string helper does not accept a legitimate zero-length value"
grep -Fq 'Keep the raw' "${PRPL_EMPTY_STRING_PATCH}" || \
	fail "TLVF patch does not document preservation of strict raw-array access"
for marker in \
	'log_global_levels=error,info,warning,fatal' \
	'log_global_syslog_levels=error,warning,fatal' \
	'Monitor polling interval in milliseconds' \
	'else if (channel_survey_info.in_use)' \
	'cleanup_roll_lock' \
	'trap cleanup_roll_lock EXIT' \
	"trap 'exit 1' INT TERM" \
	'[ "$#" -eq 1 ] && [ "$1" = "roll_logs" ]'; do
	grep -Fq "${marker}" "${PRPL_STABILITY_PATCH}" || \
		fail "prplMesh stability patch lacks ${marker}"
done
[ "$(grep -c '^--- a/' "${PRPL_STABILITY_PATCH}")" -eq 5 ] || \
	fail "prplMesh stability patch must remain scoped to five audited upstream files"
if grep '^+' "${PRPL_STABILITY_PATCH}" | grep -Eq \
	'log_global_(syslog_)?levels=.*(trace|debug)'; then
	fail "production prplMesh logging still enables trace/debug"
fi
if grep '^+' "${PRPL_STABILITY_PATCH}" | grep -Fq \
	'LOG(TRACE) << "NL80211_SURVEY_INFO_NOISE attribute is missing"'; then
	fail "optional inactive-channel survey noise is still logged every poll"
fi
if grep '^+' "${PRPL_STABILITY_PATCH}" | grep -Eq \
	'NOT IMPLEMENTED|return[[:space:]]+true.*(unimplemented|unsupported)'; then
	fail "stability patch must not fabricate support for unimplemented EasyMesh operations"
fi
grep -Fq "set prplmesh.config.enable='0'" "${PRPL_DEFAULTS}" || \
	fail "prplMesh must remain gated until the on-device health check"
for marker in \
	'prplmesh.config.operational' \
	'prplmesh.config.passive_mode' \
	'prplmesh.config.active_control_confirmed' \
	'RESULT_EASYMESH_CONTROL_PLANE=DISABLED_BY_POLICY' \
	'RESULT_EASYMESH_CONTROL_PLANE=ACTIVE_CONTROL_NOT_CONFIRMED'; do
	grep -Fq "${marker}" "${EASY_VERIFY}" || \
		fail "EasyMesh verifier lacks bounded policy gate ${marker}"
done
if grep -Eq '(^|[[:space:]])(uci[^#]*(set|add|delete|rename|reorder|commit)[^#]*wireless|wifi[[:space:]]+(up|down|reload))' \
	"${PRPL_DEFAULTS}" "${PRPL_INIT}"; then
	fail "prplMesh integration must not mutate or reload the working wireless network"
fi
for builder in "${ROOT}/build.sh" "${ROOT}/build.remote.sh"; do
	grep -Fq 'record_regular_input prplmesh-package' "${builder}" || \
		fail "build input manifest does not bind prplMesh package files"
done

for marker in \
	'require_mode usr/sbin/cr6608-easymesh-verify 755' \
	'require_mode etc/init.d/prplmesh 755' \
	'require_mode usr/bin/getopt 755' \
	'require_mode opt/prplmesh/bin/ieee1905_transport 755' \
	'require_mode opt/prplmesh/bin/beerocks_controller 755' \
	'require_mode opt/prplmesh/bin/beerocks_agent 755' \
	'require_mode opt/prplmesh/scripts/prplmesh_utils.sh 755' \
	'log_global_levels=error,info,warning,fatal' \
	'log_global_size=262144' \
	'monitor_polling_rate_msec=1000' \
	'prplMesh emergency log-roll fast path is missing' \
	'prplMesh preserved-overlay migration does not close' \
	'prplMesh preserved-overlay safety gates are not committed before wireless sync' \
	'ofdma_ul=mask-bit-1-runtime-guarded-ram-or-forced-lab' \
	'mu_mimo_ul=mask-bit-3-runtime-guarded-ram-or-forced-lab' \
	'ul_muru_policy=mediatek-25.12-mu-onoff-sta-rec-port' \
	'ul_muru_default=stable-and-retail-mask-0' \
	'ul_muru_qualification=ram-boot-only-mask-15' \
	'ul_muru_mcu_telemetry=attempted-response-ok-failed-timeout-not-apply-or-ota-proof' \
	'ul_muru_fault_policy=kernel-attributed-latch-watchdog-or-sta-rec-plus-unattributed-disarm' \
	'ul_muru_rearm_policy=one-way-ceiling-restored-after-verified-reset-max-3-unattributed-strikes' \
	'ul_muru_dl_floor=upstream-dl-ofdma-and-dl-mumimo-retained-through-fault' \
	'ul_muru_global_mcu_commands=not-used' \
	'background_cac=enabled-driver-runtime-capability-gated' \
	'easymesh=prplmesh-controller-agent-runtime-gated'; do
	grep -Fq "${marker}" "${IMAGE_INSPECTOR}" || \
		fail "image inspector lacks ${marker}"
done
if grep -Eq 'unsupported-on-mt7915|background_cac=disabled-by-cr6608-dts' \
	"${IMAGE_INSPECTOR}"; then
	fail "image inspector still accepts a stale AX support contract"
fi

[ -f "${SUPPORT}" ] || fail "official AX feature support manifest is missing"
[ "$(wc -l < "${SUPPORT}" | tr -d '[:space:]')" -eq 26 ] ||
	fail "AX support manifest schema must contain exactly 26 lines"
grep -Fq '!= 26' "${VERIFY}" ||
	fail "runtime AX verifier does not enforce the 26-line support schema"
for marker in \
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
	grep -Fqx "${marker}" "${SUPPORT}" || fail "support manifest lacks ${marker}"
done

for radio in radio0 radio1; do
	radio_block "${radio}" | grep -Eq "	option htmode 'HE(20|40|80)'" || \
		fail "${radio} must use a supported HE mode"
	radio_block "${radio}" | grep -Fq "	option distance 'auto'" && \
		fail "${radio} must not pass the unsupported string distance=auto to netifd"
	require_radio_option "${radio}" he_su_beamformer 1
	require_radio_option "${radio}" he_su_beamformee 1
	require_radio_option "${radio}" he_mu_beamformer 1
	require_radio_option "${radio}" he_bss_color_enabled 1
	require_radio_option "${radio}" he_spr_sr_control 3
done

require_radio_option radio0 htmode HE20
require_radio_option radio1 mu_beamformer 1
require_radio_option radio1 su_beamformer 1
require_radio_option radio1 su_beamformee 1
require_radio_option radio1 htmode HE80

for marker in \
	'support_manifest=/usr/share/cr6608/ax-feature-support' \
	'verify_support_manifest()' \
	'AX capability manifest state' \
	'declared feature set' \
	'MediaTek 25.12 UL RAM or persistent forced LAB path' \
	'radio_sections()' \
	'radio_ap_interfaces()' \
	'interface_phy()' \
	'ap_he_capabilities()' \
	'he_mcs_nss_state()' \
	'[ "${1:-}" = --he-nss-from-stdin ]' \
	'config_exact_state()' \
	'config_regex_state()' \
	'config_mu_edca_state()' \
	'config_spatial_reuse_state()' \
	'[ "${1:-}" = --hostapd-config-from-file ]' \
	'HOSTAPD_HE_PROFILE=VALID' \
	'HE_NSS_PROFILE=NSS2_MCS0_11' \
	'hardware spatial-stream limit' \
	'NSS2 (2x2); NSS4 unsupported' \
	'CR6608 wifi-device topology' \
	'radio0:2g:HE20' \
	'radio1:5g:HE80' \
	'HE Iftypes:' \
	'SU Beamformer' \
	'MU Beamformer' \
	'242 tone RUs|PPE Threshold Present|BSR' \
	'config_exact_state "$conf" ieee80211ax 1' \
	'config_mu_edca_state "$conf"' \
	'config_exact_state "$conf" he_mu_beamformer 1' \
	'DL OFDMA support gate' \
	'UL OFDMA support gate' \
	'DL MU-MIMO support gate' \
	'UL MU-MIMO support gate' \
	'ul_muru_runtime_state()' \
	'Full Bandwidth UL MU-MIMO' \
	'vendor_sta_rec=$ul_muru_state' \
	'armed:supported|stable-disabled:not-advertised' \
	'ul_module_token_value()' \
	'cr6608_muru_mask' \
	'fault_latched' \
	'sta_rec_response_ok' \
	'sta_rec_timeout' \
	'ul-muru-ram-v1' \
	'ul_muru_guard_healthy()' \
	'[ "$persistent_legacy" = 0 ] && [ "$persistent_mask" = 15 ]' \
	'if [ "${1:-}" = --ul-muru-state-only ]' \
	'[ "$ul_policy_ok" != 1 ]' \
	'Background CAC capability' \
	'Radar background support' \
	'enabled-driver-runtime-capability-gated' \
	'prplmesh-controller-agent-runtime-gated' \
	'STA_REC response telemetry' \
	'not Firmware apply or OTA proof' \
	'observed_airtime=not-measured' \
	'observed_scheduling=not-measured' \
	'aggregate_radio_counter_correlation=not-measured' \
	'client_attribution=requires-per-peer-telemetry-or-capture-hardware' \
	'hostapd_runtime_status' \
	'[ "$hostapd_state" != ENABLED ]' \
	'[ "$su_bfer" != supported ]' \
	'[ "$he_su_bfer_runtime" != advertised ]' \
	'[ "$mu_bfer" != supported ]' \
	'[ "$he_mu_bfer_runtime" != advertised ]' \
	'[ "$bss_color_runtime" != advertised ]' \
	'[ "$spatial_reuse_runtime" != advertised ]' \
	'[ "$ru_cap" != supported ]' \
	'[ "$mu_edca_runtime" != advertised ]' \
	'runtime_channel_width_mhz' \
	'[ "$runtime_width" != "$expected_width" ]' \
	'RESULT_AX_CONFIGURATION=DRIVER_GATE_PASS_AIRTIME_UNVERIFIED' \
	'RESULT_AX_CONFIGURATION=FAIL'; do
	grep -Fq "${marker}" "${VERIFY}" || fail "runtime verifier lacks ${marker}"
done
! grep -Fq 'official support manifest' "${VERIFY}" || \
	fail "runtime verifier incorrectly presents the experimental UL path as official support"

grep -Fq 'if [ "$status" -eq 0 ]' "${VERIFY}" || \
	fail "runtime driver gate must be conditional"
if grep -Fq 'RESULT_AX_FEATURES=PASS' "${VERIFY}"; then
	fail "runtime verifier must not claim an unqualified AX feature PASS"
fi
if grep -Eq 'check_phy[[:space:]]+phy[01]|check_radio[[:space:]]+radio[01]' "${VERIFY}"; then
	fail "AX verifier hard-codes radio or phy names"
fi

valid_he_mcs="$(cat <<'EOF'
	HE Iftypes: AP
		HE RX MCS and NSS set <= 80 MHz
			1 streams: MCS 0-11
			2 streams: MCS 0-11
			3 streams: not supported
			4 streams: not supported
			5 streams: not supported
			6 streams: not supported
			7 streams: not supported
			8 streams: not supported
		HE TX MCS and NSS set <= 80 MHz
			1 streams: MCS 0-11
			2 streams: MCS 0-11
			3 streams: not supported
			4 streams: not supported
			5 streams: not supported
			6 streams: not supported
			7 streams: not supported
			8 streams: not supported
	HE Iftypes: mesh point
EOF
)"
valid_he_output="$(printf '%s\n' "$valid_he_mcs" |
	sh "$VERIFY" --he-nss-from-stdin)" ||
	fail "exact 2x2 HE RX/TX MCS map was rejected"
printf '%s\n' "$valid_he_output" |
	grep -Fqx 'HE_RX_NSS_PROFILE=nss2-mcs0-11' ||
	fail "valid HE RX NSS2 profile was not reported"
printf '%s\n' "$valid_he_output" |
	grep -Fqx 'HE_TX_NSS_PROFILE=nss2-mcs0-11' ||
	fail "valid HE TX NSS2 profile was not reported"
printf '%s\n' "$valid_he_output" |
	grep -Fqx 'HE_NSS_PROFILE=NSS2_MCS0_11' ||
	fail "valid HE NSS2 profile did not pass"

invalid_nss4="$(printf '%s\n' "$valid_he_mcs" |
	awk '!changed && /4 streams: not supported/ {
		sub(/4 streams: not supported/, "4 streams: MCS 0-11")
		changed=1
	} { print }')"
if printf '%s\n' "$invalid_nss4" |
	sh "$VERIFY" --he-nss-from-stdin >/dev/null 2>&1; then
	fail "an invalid NSS4 claim was accepted"
fi
missing_tx="$(printf '%s\n' "$valid_he_mcs" |
	awk '/HE TX MCS and NSS set/ { exit } { print }')"
if printf '%s\n' "$missing_tx" |
	sh "$VERIFY" --he-nss-from-stdin >/dev/null 2>&1; then
	fail "a missing HE TX MCS map was accepted"
fi

hostapd_he_config_test() (
	test_dir="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-hostapd-he.XXXXXX")" || exit 1
	trap 'rm -rf -- "$test_dir"' EXIT HUP INT TERM
	conf="$test_dir/hostapd.conf"
	cat > "$conf" <<'EOF'
interface=phy0-ap0
ieee80211ax=1
he_su_beamformer=1
he_su_beamformee=1
he_mu_beamformer=1
he_bss_color=1
he_spr_non_srg_obss_pd_max_offset=5
he_spr_sr_control=7
he_mu_edca_qos_info_param_count=0
he_mu_edca_qos_info_q_ack=0
he_mu_edca_qos_info_queue_request=0
he_mu_edca_qos_info_txop_request=0
he_mu_edca_ac_be_aifsn=8
he_mu_edca_ac_be_aci=0
he_mu_edca_ac_be_ecwmin=9
he_mu_edca_ac_be_ecwmax=10
he_mu_edca_ac_be_timer=255
he_mu_edca_ac_bk_aifsn=15
he_mu_edca_ac_bk_aci=1
he_mu_edca_ac_bk_ecwmin=9
he_mu_edca_ac_bk_ecwmax=10
he_mu_edca_ac_bk_timer=255
he_mu_edca_ac_vi_aifsn=5
he_mu_edca_ac_vi_aci=2
he_mu_edca_ac_vi_ecwmin=5
he_mu_edca_ac_vi_ecwmax=7
he_mu_edca_ac_vi_timer=255
he_mu_edca_ac_vo_aifsn=5
he_mu_edca_ac_vo_aci=3
he_mu_edca_ac_vo_ecwmin=5
he_mu_edca_ac_vo_ecwmax=7
he_mu_edca_ac_vo_timer=255
EOF
	sh "$VERIFY" --hostapd-config-from-file "$conf" |
		grep -Fqx 'HOSTAPD_HE_PROFILE=VALID' || exit 2

	cp "$conf" "$test_dir/valid.conf"
	printf '%s\n' 'ieee80211ax=0' >> "$conf"
	if sh "$VERIFY" --hostapd-config-from-file "$conf" >/dev/null 2>&1; then exit 3; fi
	cp "$test_dir/valid.conf" "$conf"
	printf '%s\n' 'he_mu_edca_ac_be_aifsn=1' >> "$conf"
	if sh "$VERIFY" --hostapd-config-from-file "$conf" >/dev/null 2>&1; then exit 4; fi
	cp "$test_dir/valid.conf" "$conf"
	sed -i '/^he_mu_edca_ac_vo_timer=/d' "$conf"
	if sh "$VERIFY" --hostapd-config-from-file "$conf" >/dev/null 2>&1; then exit 5; fi
	cp "$test_dir/valid.conf" "$conf"
	printf '%s\n' 'he_mu_edca_unexpected=1' >> "$conf"
	if sh "$VERIFY" --hostapd-config-from-file "$conf" >/dev/null 2>&1; then exit 6; fi
	cp "$test_dir/valid.conf" "$conf"
	sed -i 's/^he_bss_color=.*/he_bss_color=64/' "$conf"
	if sh "$VERIFY" --hostapd-config-from-file "$conf" >/dev/null 2>&1; then exit 7; fi
	cp "$test_dir/valid.conf" "$conf"
	printf '%s\n' 'he_spr_sr_control=3' >> "$conf"
	if sh "$VERIFY" --hostapd-config-from-file "$conf" >/dev/null 2>&1; then exit 8; fi
	printf 'hostapd_he_config=pass\n'
)
[ "$(hostapd_he_config_test)" = hostapd_he_config=pass ] ||
	fail "hostapd HE configuration schema did not fail closed"

for marker in \
	'--run' \
	'radio_sections()' \
	'radio_ap_interfaces()' \
	'radio_phy()' \
	'extract_channel_rows()' \
	'HE20' \
	'HE40' \
	'HE80' \
	'cac_timeout' \
	'@.dfs.cac_active' \
	'set txpower fixed 3800' \
	'cp -p /etc/config/wireless' \
	'trap cleanup EXIT' \
	"trap 'exit 130' INT" \
	'restore_wireless()' \
	'Driver Maximum' \
	'Accepted dBm' \
	'Beamforming Capability' \
	'HE Capability' \
	'requested-38-accepted-' \
	'expected_band=2.4GHz' \
	'expected_band=5GHz' \
	'run_failures=$((run_failures + 1))' \
	'RESULT=BUILD_REJECTED failures=' \
	'RESULT=DRIVER_GATE_PASS' \
	'RF_MEASURED_POWER=NOT_MEASURED'; do
	grep -Fq -- "$marker" "${FULL_VERIFY}" || \
		fail "full channel verifier lacks ${marker}"
done

if grep -Eq 'for[[:space:]]+phy[[:space:]]+in[[:space:]]+phy0[[:space:]]+phy1' "${FULL_VERIFY}"; then
	fail "full channel verifier hard-codes phy names"
fi
if grep -Fq 'uci -q commit wireless' "${FULL_VERIFY}"; then
	fail "channel tests must remain uncommitted so power loss cannot persist a test channel"
fi

probe_line="$(grep -Fn 'set txpower fixed 3800' "${FULL_VERIFY}" |
	sed -n '1s/:.*//p')"
accepted_line="$(grep -Fn 'accepted="$(iw dev "$iface" info' "${FULL_VERIFY}" |
	sed -n '1s/:.*//p')"
[ -n "$probe_line" ] && [ -n "$accepted_line" ] &&
	[ "$accepted_line" -gt "$probe_line" ] ||
	fail "accepted power must be read after the explicit fixed-3800 probe"

down_line="$(grep -Fn 'if ! wifi down "$radio"' "${FULL_VERIFY}" |
	sed -n '1s/:.*//p')"
up_line="$(grep -Fn 'if ! wifi up "$radio"' "${FULL_VERIFY}" |
	sed -n '1s/:.*//p')"
[ -n "$down_line" ] && [ -n "$up_line" ] && [ "$up_line" -gt "$down_line" ] ||
	fail "wifi up must run independently after wifi down"

grep -Fq "sed 's/\"/\"\"/g;" "${FULL_VERIFY}" ||
	fail "CSV writer must escape embedded double quotes"
if grep -Eq 'RF_MEASURED_POWER[[:space:]]*=[[:space:]]*[0-9]' "${FULL_VERIFY}"; then
	fail "software verifier must not fabricate external RF measurements"
fi

printf 'ax_feature_contracts=pass\n'
