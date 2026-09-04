#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
SOURCE_AUDIT="$ROOT/files/usr/sbin/cr6608-retail-radio-audit"
SOURCE_PROFILE="$ROOT/files/etc/cr6608-artifact-profile"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-retail-radio.XXXXXX")"
BIN="$TMP/bin"

cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT HUP INT TERM
fail() { printf '%s\n' "$*" >&2; exit 1; }

mkdir -p "$BIN" "$TMP/modules.d" "$TMP/modules-boot.d" \
	"$TMP/debug/phy0/mt76" "$TMP/debug/phy1/mt76"
printf '%s\n' N > "$TMP/rf"
printf '%s\n' N > "$TMP/rf-active"
printf '%s\n' N > "$TMP/ul"
printf '%s\n' 0 > "$TMP/muru-mask"
printf '%s\n' 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0' > "$TMP/modules.d/mt7915e"
printf '%s\n' 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0' > "$TMP/rom-mt7915e"
printf '%s\n' \
	'profile=retail-v1' \
	'sale_ready=NO' \
	'radio_policy=retail-disabled' > "$TMP/rom-profile"
for phy in phy0 phy1; do
	printf '%s\n' 0 > "$TMP/debug/$phy/mt76/cr6608_ul_muru"
	printf '%s\n' 0 > "$TMP/debug/$phy/mt76/cr6608_muru_mask"
	printf '%s\n' 'candidate_allowed=0' 'candidate_ul_enabled=0' \
		'candidate_mask=0' 'candidate_dl_ofdma=0' 'candidate_ul_ofdma=0' \
		'candidate_dl_mumimo=0' 'candidate_ul_mumimo=0' \
		'fault_latched=0' 'fault_latches=0' \
		'policy=mediatek-25.12-mu-onoff-sta-rec-port' \
		'sta_rec_attempted=0' 'sta_rec_response_ok=0' 'sta_rec_failed=0' \
		'sta_rec_timeout=0' 'he_sta_rec_updates=0' 'mimo_capable_updates=0' \
		> "$TMP/debug/$phy/mt76/cr6608_ul_muru_state"
done
printf '%s\n' \
	'profile=retail-v2' \
	'market_country=SA' \
	'primary_ap_radio0=wifinet0' \
	'primary_ap_radio1=wifinet1' \
	'sale_ready=NO' \
	'radio_policy=retail-disabled-after-reboot' \
	'audit_complete=YES' \
	'provisioned_utc=2026-08-23T00:00:00Z' > "$TMP/marker"
chmod 0600 "$TMP/marker"

cat > "$BIN/id" <<'EOF'
#!/bin/sh
[ "$*" = '-u' ] || exit 2
printf '0\n'
EOF
cat > "$BIN/stat" <<'EOF'
#!/bin/sh
[ "$1" = -c ] || exit 2
case "$2" in
	'%u') printf '0\n' ;;
	'%a') printf '600\n' ;;
	*) exit 2 ;;
esac
EOF
cat > "$BIN/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = -q ] && shift
[ "${1:-}" = get ] || exit 1
key="${2:-}"
case "$key" in
	wireless.radio0.country|wireless.radio1.country|smartap.quick.country24|smartap.quick.country5|cr6608quick.default.country|cr6608quick.default.country24|cr6608quick.default.country5)
		printf '%s\n' "${CR6608_TEST_UCI_COUNTRY:-SA}" ;;
	wireless.radio0.txpower|wireless.radio1.txpower|smartap.quick.txpower|smartap.quick.txpower_radio0|smartap.quick.txpower_radio1|cr6608quick.default.txpower|cr6608quick.default.txpower_radio0|cr6608quick.default.txpower_radio1)
		[ "${CR6608_TEST_FORCED_POWER:-0}" = 1 ] || exit 1
		printf '38\n' ;;
	smartap.experimental.ul_muru) printf '%s\n' "${CR6608_TEST_UL_POLICY:-0}" ;;
	smartap.experimental.muru_mask) printf '%s\n' "${CR6608_TEST_MURU_MASK_POLICY:-0}" ;;
	smartap.experimental.ul_muru_guard) printf '%s\n' "${CR6608_TEST_UL_GUARD:-0}" ;;
	smartap.experimental.ul_muru_state) printf '%s\n' "${CR6608_TEST_UL_STATE:-retail-disabled}" ;;
	*) exit 1 ;;
esac
EOF
cat > "$BIN/iw" <<'EOF'
#!/bin/sh
case "$*" in
	dev)
		[ "${CR6608_TEST_IW_DEV_FAIL:-0}" != 1 ] || exit 1
		if [ "${CR6608_TEST_AP_ONE_PHY:-0}" = 1 ]; then
			printf '%s\n' 'phy#0' '  Interface phy0-ap0' '    type AP' \
				'  Interface phy0-ap1' '    type AP' 'phy#1' \
				'  Interface phy1-sta0' '    type managed'
		else
			printf '%s\n' 'phy#0' '  Interface phy0-ap0' '    type AP' \
				'phy#1' '  Interface phy1-ap0' '    type AP'
		fi
		;;
	'dev phy0-ap0 info'|'dev phy1-ap0 info') printf 'Interface %s\n\ttype AP\n' "$2" ;;
	'reg get')
		printf 'global\ncountry %s: DFS-ETSI\n' "${CR6608_TEST_REG_COUNTRY:-SA}"
		[ "${CR6608_TEST_IW_REG_FAIL:-0}" != 1 ] || exit 1
		;;
	*) exit 1 ;;
esac
EOF
cat > "$BIN/ubus" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	case "$1" in -S) shift ;; -t) shift 2 ;; *) break ;; esac
done
case "${1:-}:${2:-}:${3:-}" in
	call:network.wireless:status) printf '{}\n' ;;
	list:hostapd.phy0-ap0:|list:hostapd.phy1-ap0:) printf '%s\n' "$2" ;;
	call:hostapd.phy0-ap0:get_status|call:hostapd.phy1-ap0:get_status) printf '{}\n' ;;
	*) exit 1 ;;
esac
EOF
cat > "$BIN/jsonfilter" <<'EOF'
#!/bin/sh
[ "${1:-}" = -e ] || exit 2
case "${2:-}" in
	'@.radio0.up'|'@.radio1.up') printf 'true\n' ;;
	'@.radio0.disabled'|'@.radio1.disabled'|'@.radio0.pending'|'@.radio1.pending') printf 'false\n' ;;
	'@.radio0.interfaces[0].section')
		if [ "${CR6608_TEST_PRIMARY_DOWN:-0}" = 1 ]; then printf 'secondary24\n'; else printf 'wifinet0\n'; fi ;;
	'@.radio1.interfaces[0].section') printf 'wifinet1\n' ;;
	'@.radio0.interfaces[0].ifname') printf 'phy0-ap0\n' ;;
	'@.radio1.interfaces[0].ifname') printf 'phy1-ap0\n' ;;
	'@.radio0.interfaces[0].config.mode'|'@.radio1.interfaces[0].config.mode') printf 'ap\n' ;;
	'@.radio0.interfaces[1].section'|'@.radio1.interfaces[1].section') exit 1 ;;
	'@.status') printf 'ENABLED\n' ;;
	*) exit 1 ;;
esac
EOF
cat > "$BIN/guard" <<'EOF'
#!/bin/sh
[ "${1:-}" = enabled ] || exit 2
[ "${CR6608_TEST_GUARD_ENABLED:-0}" = 1 ]
EOF
cat > "$BIN/ax-verify" <<'EOF'
#!/bin/sh
[ "$#" -eq 0 ] || exit 2
case "${CR6608_TEST_AX_VERIFY:-pass}" in
	pass) printf '%s\n' 'RESULT_AX_CONFIGURATION=DRIVER_GATE_PASS_AIRTIME_UNVERIFIED' ;;
	fail) printf '%s\n' 'RESULT_AX_CONFIGURATION=FAIL'; exit 1 ;;
	malformed) printf '%s\n' 'RESULT_AX_CONFIGURATION=DRIVER_GATE_PASS_AIRTIME_UNVERIFIED' \
		'RESULT_AX_CONFIGURATION=DRIVER_GATE_PASS_AIRTIME_UNVERIFIED' ;;
	*) exit 2 ;;
esac
EOF
chmod 0755 "$BIN"/*

# Rewrite only fixed production paths in a temporary test copy. The shipped
# auditor contains no environment override and always enforces UID 0.
AUDIT="$TMP/audit"
sed \
	-e "s|^UCI_BIN='/sbin/uci'$|UCI_BIN='$BIN/uci'|" \
	-e "s|^IW_BIN='/usr/sbin/iw'$|IW_BIN='$BIN/iw'|" \
	-e "s|^UBUS_BIN='/bin/ubus'$|UBUS_BIN='$BIN/ubus'|" \
	-e "s|^JSONFILTER_BIN='/usr/bin/jsonfilter'$|JSONFILTER_BIN='$BIN/jsonfilter'|" \
	-e "s|^AX_VERIFY_BIN='/usr/sbin/cr6608-ax-verify'$|AX_VERIFY_BIN='$BIN/ax-verify'|" \
	-e "s|^MARKER='/etc/cr6608-retail-provisioned'$|MARKER='$TMP/marker'|" \
	-e "s|^MODULE_FILE='/etc/modules.d/mt7915e'$|MODULE_FILE='$TMP/modules.d/mt7915e'|" \
	-e "s|^MODULE_DIRS='/etc/modules.d /etc/modules-boot.d'$|MODULE_DIRS='$TMP/modules.d $TMP/modules-boot.d'|" \
	-e "s|^ROM_PROFILE='/rom/etc/cr6608-artifact-profile'$|ROM_PROFILE='$TMP/rom-profile'|" \
	-e "s|^ROM_MODULE_FILE='/rom/etc/modules.d/mt7915e'$|ROM_MODULE_FILE='$TMP/rom-mt7915e'|" \
	-e "s|^RF_PARAM='/sys/module/mt7915e/parameters/cr6608_rf_38dbm'$|RF_PARAM='$TMP/rf'|" \
	-e "s|^RF_ACTIVE_PARAM='/sys/module/mt7915e/parameters/cr6608_rf_38dbm_active'$|RF_ACTIVE_PARAM='$TMP/rf-active'|" \
	-e "s|^UL_PARAM='/sys/module/mt7915e/parameters/cr6608_ul_muru'$|UL_PARAM='$TMP/ul'|" \
	-e "s|^MURU_MASK_PARAM='/sys/module/mt7915e/parameters/cr6608_muru_mask'$|MURU_MASK_PARAM='$TMP/muru-mask'|" \
	-e "s|^UL_GUARD_INIT='/etc/init.d/cr6608-ul-muru-guard'$|UL_GUARD_INIT='$BIN/guard'|" \
	-e "s|^DEBUG_ROOT='/sys/kernel/debug/ieee80211'$|DEBUG_ROOT='$TMP/debug'|" \
	-e "s|/usr/bin/id|$BIN/id|g" \
	-e "s|/bin/stat|$BIN/stat|g" \
	"$SOURCE_AUDIT" > "$AUDIT"
chmod 0755 "$AUDIT"

env sh "$AUDIT" | grep -Fqx \
	'retail_radio_policy=PASS country=SA sale_ready=NO external_rf_verification=REQUIRED artifact_sha_verification=REQUIRED' ||
	fail 'valid retail radio policy did not pass'

expect_failure() {
	name="$1" reason="$2"
	shift 2
	if env "$@" sh "$AUDIT" > "$TMP/$name.out" 2>&1; then
		fail "$name unexpectedly passed"
	fi
	grep -Fq "reason=$reason" "$TMP/$name.out" || fail "$name returned the wrong reason"
}

printf 'Y\n' > "$TMP/rf"
expect_failure lab_runtime lab_38dbm_runtime_enabled
printf 'N\n' > "$TMP/rf"
printf 'Y\n' > "$TMP/rf-active"
expect_failure lab_active lab_38dbm_driver_active
printf 'N\n' > "$TMP/rf-active"
printf 'Y\n' > "$TMP/ul"
expect_failure ul_runtime ul_muru_runtime_enabled
printf 'N\n' > "$TMP/ul"
printf '15\n' > "$TMP/muru-mask"
expect_failure muru_mask_runtime muru_mask_runtime_enabled
printf '0\n' > "$TMP/muru-mask"
printf '%s\n' 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=1 cr6608_muru_mask=0' > "$TMP/modules.d/mt7915e"
expect_failure module_ul module_policy_not_retail
printf '%s\n' 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=15' > "$TMP/modules.d/mt7915e"
expect_failure module_mask module_policy_not_retail
printf '%s\n' 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0' > "$TMP/modules.d/mt7915e"
printf '%s\n' 'mt7915e cr6608_rf_38dbm=1' > "$TMP/modules-boot.d/duplicate"
expect_failure duplicate_loader duplicate_module_policy
rm -f -- "$TMP/modules-boot.d/duplicate"
expect_failure forced_power radio0_forced_txpower CR6608_TEST_FORCED_POWER=1
expect_failure uci_country radio0_country_mismatch CR6608_TEST_UCI_COUNTRY=US
expect_failure reg_country regulatory_country_mismatch CR6608_TEST_REG_COUNTRY=US
expect_failure iw_partial regulatory_runtime_unavailable CR6608_TEST_IW_REG_FAIL=1
expect_failure iw_dev wireless_runtime_unavailable CR6608_TEST_IW_DEV_FAIL=1
expect_failure ap_one_phy wireless_ap_per_phy CR6608_TEST_AP_ONE_PHY=1
expect_failure primary_down radio0_primary_ap_runtime CR6608_TEST_PRIMARY_DOWN=1
expect_failure ul_policy ul_muru_policy_enabled CR6608_TEST_UL_POLICY=1
expect_failure muru_mask_policy muru_mask_policy_enabled CR6608_TEST_MURU_MASK_POLICY=15
expect_failure ul_guard ul_muru_guard_policy_enabled CR6608_TEST_UL_GUARD=1
expect_failure ul_state ul_muru_state_not_retail CR6608_TEST_UL_STATE=armed-by-default
expect_failure guard_service ul_muru_guard_service_enabled CR6608_TEST_GUARD_ENABLED=1
expect_failure ax_gate ax_configuration_gate CR6608_TEST_AX_VERIFY=fail
expect_failure ax_result ax_configuration_result CR6608_TEST_AX_VERIFY=malformed

printf '1\n' > "$TMP/debug/phy0/mt76/cr6608_ul_muru"
expect_failure debug_gate ul_muru_driver_gate_enabled
printf '0\n' > "$TMP/debug/phy0/mt76/cr6608_ul_muru"
printf '15\n' > "$TMP/debug/phy0/mt76/cr6608_muru_mask"
expect_failure debug_mask muru_mask_driver_gate_enabled
printf '0\n' > "$TMP/debug/phy0/mt76/cr6608_muru_mask"
sed -i 's/^candidate_allowed=0$/candidate_allowed=1/' "$TMP/debug/phy0/mt76/cr6608_ul_muru_state"
expect_failure debug_allowed ul_muru_driver_allowed
sed -i 's/^candidate_allowed=1$/candidate_allowed=0/' "$TMP/debug/phy0/mt76/cr6608_ul_muru_state"
sed -i 's/^fault_latched=0$/fault_latched=1/' "$TMP/debug/phy0/mt76/cr6608_ul_muru_state"
expect_failure debug_fault muru_fault_latched
sed -i 's/^fault_latched=1$/fault_latched=0/' "$TMP/debug/phy0/mt76/cr6608_ul_muru_state"
sed -i 's/^sta_rec_failed=0$/sta_rec_failed=1/' "$TMP/debug/phy0/mt76/cr6608_ul_muru_state"
expect_failure debug_failed muru_sta_rec_failed
sed -i 's/^sta_rec_failed=1$/sta_rec_failed=0/' "$TMP/debug/phy0/mt76/cr6608_ul_muru_state"

sed -i 's/^radio_policy=.*/radio_policy=LAB_ARTIFACT_BLOCKED/' "$TMP/marker"
expect_failure lab_marker artifact_profile_not_retail
sed -i 's/^radio_policy=.*/radio_policy=retail-disabled-after-reboot/' "$TMP/marker"
sed -i 's/^market_country=.*/market_country=US/' "$TMP/marker"
expect_failure bound_country radio0_country_mismatch
sed -i 's/^market_country=.*/market_country=SA/' "$TMP/marker"

sed -i 's/^profile=.*/profile=lab-operator-v1/' "$TMP/rom-profile"
expect_failure immutable_lab_profile artifact_profile_not_retail
sed -i 's/^profile=.*/profile=retail-v1/' "$TMP/rom-profile"
printf '%s\n' 'mt7915e cr6608_rf_38dbm=1 cr6608_ul_muru=1 cr6608_muru_mask=15' > "$TMP/rom-mt7915e"
expect_failure immutable_lab_module artifact_profile_not_retail
printf '%s\n' 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0' > "$TMP/rom-mt7915e"

[ "$(cat "$SOURCE_PROFILE")" = "$(printf '%s\n' \
	'profile=lab-operator-v1' \
	'sale_ready=NO' \
	'radio_policy=lab-operator-38dbm-ul-muru')" ] ||
	fail 'shipped LAB artifact profile is missing or unsafe'

# Static security gate: the shipped file has immutable probes and root check.
! grep -Fq 'CR6608_RETAIL_' "$SOURCE_AUDIT" || fail 'production auditor exposes test overrides'
grep -Fq '[ "$(/usr/bin/id -u 2>/dev/null)" = 0 ] || fail must_run_as_root' "$SOURCE_AUDIT" ||
	fail 'production root gate is missing'
grep -Fq "AX_VERIFY_BIN='/usr/sbin/cr6608-ax-verify'" "$SOURCE_AUDIT" ||
	fail 'production AX verifier path is not pinned'
grep -Fq 'RESULT_AX_CONFIGURATION=DRIVER_GATE_PASS_AIRTIME_UNVERIFIED' "$SOURCE_AUDIT" ||
	fail 'retail radio policy does not require the bounded AX driver result'

printf 'retail_radio_policy_contract=pass\n'
