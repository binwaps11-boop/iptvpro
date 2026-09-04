#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MAC_PATCH="${CR6608_MAC_PATCH_UNDER_TEST:-$ROOT/patches/995-mac80211-cr6608-txpower-trace.patch}"
MT7915_PATCH="${CR6608_MT7915_PATCH_UNDER_TEST:-$ROOT/patches/999-mt7915-cr6608-rf-38dbm-request-path.patch}"
FACTORY38_PATCH="${CR6608_FACTORY38_PATCH_UNDER_TEST:-$ROOT/patches/zz-mt7915-cr6608-factory38-path.patch}"
COLLECTOR="${CR6608_COLLECTOR_UNDER_TEST:-$ROOT/files/usr/sbin/cr6608-txpower-collect}"
VERIFY="${CR6608_TXPOWER_VERIFY_UNDER_TEST:-$ROOT/files/usr/bin/cr6608-txpower-verify}"

fail() {
	echo "txpower collector test failed: $*" >&2
	exit 1
}

assert_eq() {
	[ "$1" = "$2" ] || fail "expected '$2', got '$1' ($3)"
}

sh -n "$COLLECTOR"
sh -n "$VERIFY"
grep -Fq 'external_measurement_status=unmeasured' "$COLLECTOR"
grep -Fq 'json_add_null external_conducted_dbm' "$COLLECTOR"
grep -Fq 'RF_PARAM_ROOT=' "$COLLECTOR"
grep -Fq 'read_rf_telemetry_snapshot' "$COLLECTOR"
grep -Fq 'rf_snapshot_pair_is_stable' "$COLLECTOR"
grep -Fq 'generation_start=' "$COLLECTOR"
grep -Fq 'mcu_generation' "$COLLECTOR"
grep -Fq 'mcu_result' "$COLLECTOR"
grep -Fq 'sku_applied_per_path_half_dbm' "$COLLECTOR"
grep -Fq 'verified_driver_dbm' "$COLLECTOR"
grep -Fq 'mcu_readback_iw_applied_mismatch' "$COLLECTOR"
grep -Fq 'exact_half_dbm_accounting_mismatch' "$COLLECTOR"
grep -Fq 'sar_bound_exact_peak_mismatch' "$COLLECTOR"
grep -Fq 'rf_gate_not_active' "$COLLECTOR"
! grep -Fq 'factory38_persisted_match_missing' "$COLLECTOR"
grep -Fq 'factory38_persisted_match' "$COLLECTOR"
grep -Fq 'module_bool_is_true' "$COLLECTOR"
grep -Fq 'collector_schema 5' "$COLLECTOR"
grep -Fq 'requested_uci_dbm' "$COLLECTOR"
grep -Fq 'applied_driver_dbm' "$COLLECTOR"
grep -Fq 'mcu_rate_command_status' "$COLLECTOR"
grep -Fq 'collector error: incomplete' "$COLLECTOR"
grep -Fq 'evidence-sha256.txt' "$COLLECTOR"
grep -Fq 'class/thermal/thermal_zone*/temp' "$COLLECTOR"
grep -Fq 'available_tx_antennas_mask' "$COLLECTOR"
grep -Fq 'available_rx_antennas_mask' "$COLLECTOR"
grep -Fq 'iw_reported_channel_max_dbm' "$COLLECTOR"
grep -Fq 'SNAPSHOT_MAX_AGE_SEC' "$COLLECTOR"
grep -Fq 'snapshot_pair_is_stable' "$COLLECTOR"
grep -Fq 'resolve_radio_iface_phy' "$COLLECTOR"
grep -Fq 'trace_file="$RAW_DIR/dmesg.txt"' "$COLLECTOR"
! grep -Fq 'cr6608_txpower_state' "$COLLECTOR"
! grep -Fq 'driver_apply_inflight' "$COLLECTOR"
! grep -Fq 'driver_snapshot_seq' "$COLLECTOR"
! grep -Fq 'json_add_string chainmask ' "$COLLECTOR"
! grep -Fq 'set -u' "$COLLECTOR"
[ "$(grep -Fc '[ "$INCOMPLETE" -eq 0 ] || exit 1' "$COLLECTOR")" -eq 1 ]
[ "$(grep -Ec '^[[:space:]]*dmesg[[:space:]]*>' "$COLLECTOR")" -eq 1 ]
[ "$(grep -Ec '^snapshot_once$' "$COLLECTOR")" -eq 1 ]
grep -Fq 'probe_restore_needed=1' "$VERIFY"
grep -Fq 'RESTORE_WIFI_RELOAD=failed; cleanup retry armed' "$VERIFY"
grep -Fq '[ "$probe_restore_needed" = 1 ] || return 0' "$VERIFY"

case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW*|MSYS*) ;;
	*)
		verify_restore_retry_test() (
			tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-txpower-verify.XXXXXX")" || exit 1
			trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
			mkdir -p "$tmp/bin" "$tmp/sys/phy0"
			cat >"$tmp/bin/uci" <<'EOF'
#!/bin/sh
exit 0
EOF
			cat >"$tmp/bin/ubus" <<'EOF'
#!/bin/sh
printf '{}\n'
EOF
			cat >"$tmp/bin/jsonfilter" <<'EOF'
#!/bin/sh
exit 0
EOF
			cat >"$tmp/bin/iwinfo" <<'EOF'
#!/bin/sh
exit 0
EOF
			cat >"$tmp/bin/dmesg" <<'EOF'
#!/bin/sh
exit 0
EOF
			cat >"$tmp/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
			cat >"$tmp/bin/iw" <<'EOF'
#!/bin/sh
case "$*" in
	dev) printf 'phy#0\n\tInterface mock0\n' ;;
	'dev mock0 info') printf 'wiphy 0\ntxpower 38.00 dBm\n' ;;
	'phy phy0 set txpower fixed 3800') exit 0 ;;
	*) exit 0 ;;
esac
EOF
			cat >"$tmp/bin/wifi" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$CR6608_TEST_WIFI_COUNT" ] || count="$(cat "$CR6608_TEST_WIFI_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" >"$CR6608_TEST_WIFI_COUNT"
exit 1
EOF
			chmod 0700 "$tmp/bin"/*
			if PATH="$tmp/bin:$PATH" \
			   CR6608_PRIVATE_RUNTIME_LIB="$ROOT/files/usr/libexec/cr6608-private-runtime" \
			   CR6608_PRIVATE_RUNTIME_ROOT="$tmp/private" \
			   CR6608_PRIVATE_EXPECTED_UID="$(id -u)" \
			   CR6608_IEEE80211_ROOT="$tmp/sys" \
			   CR6608_TEST_WIFI_COUNT="$tmp/wifi-count" \
			   "$VERIFY" --probe-3800 >/dev/null 2>&1; then
				exit 2
			fi
			[ "$(cat "$tmp/wifi-count" 2>/dev/null)" = 2 ] || exit 3
			printf 'txpower_verify_restore_retry=pass\n'
		)
		[ "$(verify_restore_retry_test)" = txpower_verify_restore_retry=pass ] ||
			fail 'failed Wi-Fi restoration was not retried and surfaced'
		;;
esac

grep -Fq 'txpower_state_generation' "$MAC_PATCH"
grep -Fq 'DEBUGFS_ADD(txpower_state)' "$MAC_PATCH"
grep -Fq 'struct mt7915_cr6608_rf_band_state' "$MT7915_PATCH"
grep -Fq 'MT7915_CR6608_RF_BAND_PARAMS(0);' "$MT7915_PATCH"
grep -Fq 'MT7915_CR6608_RF_BAND_PARAMS(1);' "$MT7915_PATCH"
grep -Fq 'mt7915_cr6608_rf_record_start' "$MT7915_PATCH"
grep -Fq 'mt7915_cr6608_rf_record_mcu_result' "$MT7915_PATCH"
grep -Fq 'state->generation++;' "$MT7915_PATCH"
grep -Fq 'state->mcu_generation = generation + 2;' "$MT7915_PATCH"
grep -Fq 'state->mcu_result = result;' "$MT7915_PATCH"
grep -Fq 'state->sku_applied_per_path_half_dbm' "$MT7915_PATCH"
grep -Fq 'module_param_cb(cr6608_rf_band##_band##_mcu_result' "$MT7915_PATCH"
grep -Fq 'module_param_cb(cr6608_factory38_persisted_match' "$FACTORY38_PATCH"
grep -Fq 'mt7915_cr6608_factory38_raw_match' "$FACTORY38_PATCH"

fixture_test() (
	CR6608_TXPOWER_COLLECTOR_LIBRARY_ONLY=1
	set --
	. "$COLLECTOR"

	tmp="$(mktemp -d)"
	trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM
	RF_PARAM_ROOT="$tmp"
	printf '%s\n' Y > "$tmp/cr6608_factory38_persisted_match"
	for rf_pair in \
		'generation 12' \
		'requested_dbm 38' \
		'kernel_dbm 38' \
		'regulatory_dbm 30' \
		'frequency_mhz 5745' \
		'channel 149' \
		'path_delta_half_dbm 6' \
		'sar_bounded_per_path_half_dbm 70' \
		'rate_limited_per_path_half_dbm 70' \
		'eeprom_target_per_path_half_dbm 70' \
		'sku_applied_per_path_half_dbm 70' \
		'override_active 1' \
		'mcu_generation 12' \
		'channel_ready 1' \
		'mcu_result 0'; do
		set -- $rf_pair
		printf '%s\n' "$2" > "$tmp/cr6608_rf_band1_$1"
	done

	rf_before="$(read_rf_telemetry_snapshot 1)"
	rf_after="$(read_rf_telemetry_snapshot 1)"
	assert_eq "$(kv "$rf_after" generation_start)" 12 generation-start
	assert_eq "$(kv "$rf_after" generation)" 12 generation-end
	assert_eq "$(kv "$rf_after" requested_dbm)" 38 requested-dbm
	assert_eq "$(kv "$rf_after" sku_applied_per_path_half_dbm)" 70 sku-readback
	assert_eq "$(kv "$rf_after" factory38_persisted_match)" Y persisted-factory
	module_bool_is_true Y || fail 'kernel Y boolean rejected'
	module_bool_is_true 1 || fail 'numeric true boolean rejected'
	if module_bool_is_true N; then
		fail 'kernel N boolean accepted'
	fi
	rf_snapshot_pair_is_stable "$rf_before" "$rf_after" ||
		fail 'stable even telemetry pair rejected'
	rf_snapshot_context_matches "$rf_after" 1 149 5745 ||
		fail 'matching RF context rejected'
	assert_eq "$(mcu_rate_status_from_snapshot "$rf_after")" completed mcu-rate
	assert_eq "$(mcu_path_status_from_snapshot "$rf_after" 1)" completed mcu-path
	assert_eq "$(mcu_path_status_from_snapshot "$rf_after" 0)" not_configured mcu-path-disabled
	assert_eq "$(half_dbm_with_path_to_dbm 70 6)" 38.0 exact-two-chain-accounting

	changed="$(printf '%s\n' "$rf_after" | sed 's/generation=12/generation=14/')"
	if rf_snapshot_pair_is_stable "$rf_before" "$changed"; then
		fail 'generation change during capture accepted'
	fi
	odd="$(printf '%s\n' "$rf_after" |
		sed 's/generation_start=12 generation=12/generation_start=13 generation=13/')"
	if rf_snapshot_pair_is_stable "$odd" "$odd"; then
		fail 'odd in-progress generation accepted'
	fi
	inflight="$(printf '%s\n' "$rf_after" | sed 's/mcu_generation=12/mcu_generation=-1/')"
	assert_eq "$(mcu_rate_status_from_snapshot "$inflight" || true)" in_progress mcu-inflight
	failed="$(printf '%s\n' "$rf_after" | sed 's/mcu_result=0/mcu_result=-5/')"
	assert_eq "$(mcu_rate_status_from_snapshot "$failed" || true)" rejected mcu-failure
	wrong_context="$(printf '%s\n' "$rf_after" |
		sed 's/channel=149/channel=36/; s/frequency_mhz=5745/frequency_mhz=5180/')"
	if rf_snapshot_context_matches "$wrong_context" 1 149 5745; then
		fail 'changed RF context accepted'
	fi

	mac_before='snapshot_seq=11 snapshot_uptime_ms=999900 valid=1 wiphy=phy7 band=1 channel=149 freq=5745 width=3 user_dbm=38 chandef_dbm=38 vif_dbm=38 result_dbm=38'
	mac_after='snapshot_seq=11 snapshot_uptime_ms=999950 valid=1 wiphy=phy7 band=1 channel=149 freq=5745 width=3 user_dbm=38 chandef_dbm=38 vif_dbm=38 result_dbm=38'
	snapshot_is_fresh "$mac_before" 1000000 5 || fail 'fresh mac snapshot rejected'
	snapshot_pair_is_stable "$mac_before" "$mac_after" || fail 'stable mac pair rejected'
	snapshot_context_matches "$mac_after" phy7 149 5745 3 || fail 'mac context rejected'
	stale="$(printf '%s\n' "$mac_before" |
		sed 's/snapshot_uptime_ms=999900/snapshot_uptime_ms=990000/')"
	if snapshot_is_fresh "$stale" 1000000 5; then
		fail 'stale mac snapshot accepted'
	fi

	numeric_equal 38 38.0 || fail 'decimal power comparison rejected'
	assert_eq "$(nss_from_mask 0x3)" 2 two-chain-mask
	if unchanged_value 38 37; then
		fail 'concurrent UCI request change accepted'
	fi
	unchanged_value 38 38 || fail 'unchanged UCI request rejected'

	ubus() { printf '%s\n' '{"radio7":{"interfaces":[{"ifname":"mesh-ap0"}]}}'; }
	jsonfilter() { printf '%s\n' mesh-ap0; }
	iw() {
		[ "$1" = dev ] && [ "$2" = mesh-ap0 ] && [ "$3" = info ] || return 1
		printf '%s\n' 'Interface mesh-ap0' 'wiphy 7'
	}
	assert_eq "$(resolve_radio_iface_phy radio7)" 'mesh-ap0|phy7' dynamic-radio-phy-map
)

fixture_test

echo 'txpower_collector_contract=pass'
