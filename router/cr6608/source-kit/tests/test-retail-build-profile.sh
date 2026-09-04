#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH= cd -- "${script_dir}/.." && pwd)"
applier="${root}/profiles/apply-build-profile.sh"
retail_overlay="${root}/profiles/retail/files"
build="${root}/build.sh"
remote_build="${root}/build.remote.sh"
inspector="${root}/inspect-image.sh"
rf_dts_patch="${root}/patches/996-cr6608-dts-rf-38dbm-lab-mode.patch"
ul_muru_dts_patch="${root}/patches/996a-cr6608-dts-ul-muru-ram-gate.patch"
provision="${root}/files/usr/sbin/cr6608-retail-provision"
audit="${root}/files/usr/sbin/cr6608-retail-audit"
txpower_defaults="${root}/files/etc/uci-defaults/94-cr6608-txpower"
ul_defaults="${root}/files/etc/uci-defaults/98-cr6608-ul-muru-guard"
preserved_defaults="${root}/files/etc/uci-defaults/99-cr6608-preserved-config-v2"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-retail-profile.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

fail() { printf 'retail build profile contract failed: %s\n' "$*" >&2; exit 1; }

for required in "$applier" "$retail_overlay/etc/cr6608-artifact-profile" \
	"$retail_overlay/etc/modules.d/mt7915e" \
	"$retail_overlay/etc/config/wireless" "$retail_overlay/etc/config/rpcd" \
	"$retail_overlay/etc/config/cr6608quick" "$retail_overlay/etc/config/smartap" \
	"$retail_overlay/etc/smartap-version" "$build" "$remote_build" "$inspector" \
	"$rf_dts_patch" "$ul_muru_dts_patch"; do
	[ -s "$required" ] || fail "missing input: $required"
done
! grep -Fq 'mediatek,cr6608-experimental-ul-muru' "$rf_dts_patch" ||
	fail 'the shared LAB/Retail DTS patch still exposes the UL MURU RAM gate'
[ "$(grep -Fxc '+		mediatek,cr6608-experimental-ul-muru;' "$ul_muru_dts_patch")" -eq 1 ] ||
	fail 'the qualification-only DTS patch does not own the single UL MURU gate'

mkdir -p "$tmp/lab" "$tmp/retail"
cp -a -- "${root}/files/." "$tmp/lab/"
cp -a -- "${root}/files/." "$tmp/retail/"
sh "$applier" lab "$tmp/lab"
diff -qr --no-dereference -- "${root}/files" "$tmp/lab" >/dev/null ||
	fail 'lab profile is not byte-for-byte unchanged'
sh "$applier" retail "$tmp/retail"

printf '%s\n' 'profile=retail-v1' 'sale_ready=NO' 'radio_policy=retail-disabled' |
	cmp -s - "$tmp/retail/etc/cr6608-artifact-profile" ||
	fail 'retail-v1 metadata mismatch'
printf 'mt7915e cr6608_rf_38dbm=0 cr6608_ul_muru=0 cr6608_muru_mask=0\n' |
	cmp -s - "$tmp/retail/etc/modules.d/mt7915e" ||
	fail 'retail module gates are not locked'
[ "$(awk -F: '$1 == "root" { print $2; count++ } END { if (count != 1) exit 1 }' "$tmp/retail/etc/shadow")" = '!' ] ||
	fail 'generic retail root account is usable'
[ "$(awk -F: '$1 == "root" { print NF; count++ } END { if (count != 1) exit 1 }' "$tmp/retail/etc/shadow")" = 9 ] ||
	fail 'retail root shadow record is malformed'
grep -Eq "^[[:space:]]*option password '!'$" "$tmp/retail/etc/config/rpcd" ||
	fail 'generic retail Web login is not locked'
! grep -Eq '\$[156y]\$' "$tmp/retail/etc/config/rpcd" ||
	fail 'retail Web config embeds a reusable password verifier'
retail_migration="$tmp/retail/etc/uci-defaults/99-cr6608-preserved-config-v2"
[ "$(grep -Fxc "RPCD_ROOT_PASSWORD='!'" "$retail_migration")" -eq 1 ] ||
	fail 'retail migration does not lock the legacy Web verifier'
! grep -R -Fq '$6$CR6608dashAdm$' "$tmp/retail" ||
	fail 'retail rootfs still embeds the retired shared Web verifier'

wireless="$tmp/retail/etc/config/wireless"
[ "$(grep -Ec "^[[:space:]]*option disabled '1'$" "$wireless")" -eq 4 ] ||
	fail 'both retail radios and both primary BSSs are not disabled'
[ "$(grep -Ec "^[[:space:]]*option encryption 'sae-mixed'$" "$wireless")" -eq 2 ] ||
	fail 'retail primary BSSs are not protected fail-closed placeholders'
[ "$(grep -Ec "^[[:space:]]*option hidden '1'$" "$wireless")" -eq 2 ] ||
	fail 'retail primary BSSs are not hidden before provisioning'
! grep -Eq "^[[:space:]]*option (encryption 'none'|disabled '0'|txpower |country |key |sae_password )" "$wireless" ||
	fail 'retail wireless defaults contain an active/open/forced/secret value'

for cfg in "$tmp/retail/etc/config/cr6608quick" "$tmp/retail/etc/config/smartap"; do
	[ "$(grep -Ec "^[[:space:]]*option radio[01]_enabled '0'$" "$cfg")" -eq 2 ] ||
		fail "retail UI metadata can enable a radio: $cfg"
	! grep -Eq "^[[:space:]]*option (txpower|txpower_radio[01]|country|country24|country5) " "$cfg" ||
		fail "retail UI metadata forces country/power: $cfg"
done
[ "$(grep -Ec "^[[:space:]]*option pppoe_vlan_enabled '0'$" \
	"$tmp/retail/etc/config/cr6608quick")" -eq 1 ] ||
	fail 'retail quick settings do not default PPPoE to bare WAN'
grep -Eq "^[[:space:]]*option ul_muru '0'$" "$tmp/retail/etc/config/smartap" &&
	grep -Eq "^[[:space:]]*option muru_mask '0'$" "$tmp/retail/etc/config/smartap" &&
	grep -Eq "^[[:space:]]*option ul_muru_guard '0'$" "$tmp/retail/etc/config/smartap" &&
	grep -Eq "^[[:space:]]*option ul_muru_state 'retail-disabled'$" "$tmp/retail/etc/config/smartap" ||
	fail 'retail UL MURU policy is armed'

for guarded_default in "$txpower_defaults" "$ul_defaults" "$preserved_defaults"; do
	grep -Fq 'profile=retail-v1' "$guarded_default" ||
		fail "first-boot path is not retail-profile-aware: $guarded_default"
done
grep -Fq 'EXPECTED_RADIO_POLICY=' "$provision" &&
	grep -Fq 'retail-disabled-after-reboot' "$provision" ||
	fail 'provisioner does not emit a retail-bound marker'
grep -Fq 'EXPECTED_RADIO_POLICY=' "$audit" &&
	grep -Fq 'retail-disabled-after-reboot' "$audit" ||
	fail 'security audit does not bind the retail marker policy'

# Execute the exact artifact-policy function from both production tools. A
# writable LAB identity cannot yield the Retail marker, and malformed immutable
# metadata is rejected instead of falling back to a permissive classification.
for policy_tool in "$provision" "$audit"; do
	policy_helper="$tmp/policy-${policy_tool##*/}"
	{
		printf '%s\n' '#!/bin/sh' 'set -eu' 'ARTIFACT_PROFILE="$1"'
		sed -n '/^artifact_radio_policy() {$/,/^}$/p' "$policy_tool"
		printf '%s\n' 'artifact_radio_policy'
	} > "$policy_helper"
	[ "$(sh "$policy_helper" "${root}/files/etc/cr6608-artifact-profile")" = LAB_ARTIFACT_BLOCKED ] ||
		fail "LAB artifact gained a Retail policy: ${policy_tool##*/}"
	[ "$(sh "$policy_helper" "$tmp/retail/etc/cr6608-artifact-profile")" = retail-disabled-after-reboot ] ||
		fail "Retail artifact did not gain its reboot gate: ${policy_tool##*/}"
	printf '%s\n' 'profile=retail-v1' 'sale_ready=YES' 'radio_policy=retail-disabled' \
		> "$tmp/malformed-profile"
	if sh "$policy_helper" "$tmp/malformed-profile" >/dev/null 2>&1; then
		fail "malformed artifact metadata was accepted: ${policy_tool##*/}"
	fi
done

# An unprovisioned Retail-v1 first boot must close both radios and exit
# retryable before reaching any shared-rpcd/open-WLAN migration.
printf 'xiaomi,mi-router-cr6608\n' > "$tmp/board-name"
mkdir -p "$tmp/migration-bin"
cat > "$tmp/migration-bin/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = -q ] && shift
case "${1:-}:${2:-}" in
	get:wireless.radio0|get:wireless.radio1) printf 'wifi-device\n' ;;
	set:wireless.radio0.disabled=1|set:wireless.radio1.disabled=1)
		printf '%s:%s\n' "$1" "$2" >> "$CR6608_TEST_LOG" ;;
	commit:wireless) printf '%s:%s\n' "$1" "$2" >> "$CR6608_TEST_LOG" ;;
	*) printf 'unexpected:%s:%s\n' "${1:-}" "${2:-}" >> "$CR6608_TEST_LOG"; exit 1 ;;
esac
EOF
cat > "$tmp/migration-bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$tmp/migration-bin/uci" "$tmp/migration-bin/logger"
: > "$tmp/migration.log"
if env CR6608_TEST_LOG="$tmp/migration.log" \
	CR6608_MIGRATION_UCI_BIN="$tmp/migration-bin/uci" \
	CR6608_MIGRATION_LOGGER_BIN="$tmp/migration-bin/logger" \
	CR6608_MIGRATION_BOARD_NAME_FILE="$tmp/board-name" \
	CR6608_MIGRATION_ARTIFACT_PROFILE="$tmp/retail/etc/cr6608-artifact-profile" \
	CR6608_MIGRATION_RETAIL_MARKER="$tmp/no-retail-marker" \
	CR6608_MIGRATION_PENDING_MARKER="$tmp/no-pending-marker" \
	sh "$retail_migration" >/dev/null 2>&1; then
	fail 'unprovisioned Retail-v1 migration did not remain retryable'
fi
grep -Fqx 'set:wireless.radio0.disabled=1' "$tmp/migration.log" &&
	grep -Fqx 'set:wireless.radio1.disabled=1' "$tmp/migration.log" &&
	grep -Fqx 'commit:wireless' "$tmp/migration.log" ||
	fail 'unprovisioned Retail-v1 migration did not close both radios'
! grep -Eq 'rpcd|encryption|key|disabled=0|unexpected' "$tmp/migration.log" ||
	fail 'unprovisioned Retail-v1 migration entered onboarding'

grep -Fq 'BUILD_PROFILE="${CR6608_BUILD_PROFILE:-${profile:-lab}}"' "$build" ||
	fail 'build profile does not default to lab with the documented overrides'
grep -Fq 'sh "${SRC_PROFILE_APPLIER}" "${BUILD_PROFILE}" "${OPENWRT_DIR}/files"' "$build" ||
	fail 'build does not apply the selected overlay'
grep -Fq 'CR6608_BUILD_PROFILE="${BUILD_PROFILE}"' "$build" ||
	fail 'build does not bind the inspector to the selected profile'
grep -Fq "ARTIFACT_PROFILE_LABEL='retail_v1'" "$inspector" ||
	fail 'inspector does not emit the retail-v1 identity'
cmp -s "$build" "$remote_build" || fail 'local and remote build paths diverged'
for builder in "$build" "$remote_build"; do
	grep -Fq 'if [ "${BUILD_PROFILE}" = ul-lab ]; then' "$builder" &&
		grep -Fq 'git apply "${SRC_UL_MURU_DTS_PATCH}"' "$builder" &&
		grep -Fq 'Stable/Retail DTS must not expose the UL MURU RAM gate' "$builder" ||
		fail "LAB/Retail DTS isolation is missing: ${builder##*/}"
done

mkdir -p "$tmp/link-target"
ln -s "$tmp/link-target" "$tmp/link-root"
if sh "$applier" retail "$tmp/link-root" >/dev/null 2>&1; then
	fail 'profile applier accepted a symlinked staged root'
fi
if sh "$applier" unsafe "$tmp/retail" >/dev/null 2>&1; then
	fail 'profile applier accepted an unknown profile'
fi

printf 'retail_build_profile_contract=pass\n'
