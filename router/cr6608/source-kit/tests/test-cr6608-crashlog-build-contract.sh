#!/usr/bin/env bash
# Contract and mock tests for the isolated crash-log initramfs builder.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILDER="$KIT_DIR/crashlog/build-cr6608-crashlog-initramfs.sh"

[ -f "$BUILDER" ] || {
	echo "FAIL: builder is missing: $BUILDER" >&2
	exit 1
}
bash -n "$BUILDER"
# shellcheck disable=SC1090
source "$BUILDER"

TEST_ROOT="$(mktemp -d /tmp/cr6608-crashlog-build-contract.XXXXXX)"
case "$TEST_ROOT" in
	/tmp/cr6608-crashlog-build-contract.*) ;;
	*) echo "FAIL: unsafe test root: $TEST_ROOT" >&2; exit 1 ;;
esac
cleanup() {
	case "$TEST_ROOT" in
		/tmp/cr6608-crashlog-build-contract.*) rm -rf -- "$TEST_ROOT" ;;
	esac
}
trap cleanup EXIT HUP INT TERM
WORK_DIR="$TEST_ROOT/work"
mkdir -p "$WORK_DIR"

pass_count=0
pass() {
	pass_count=$((pass_count + 1))
	printf 'PASS %s\n' "$1"
}
fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# Mock the quarantine flow. No command in this test can access a real image
# tree, NAND device, router, or publication directory.
mock_output="$TEST_ROOT/output"
mock_quarantine="$TEST_ROOT/quarantine"
mkdir -p "$mock_output/targets/ramips/mt7621" "$mock_quarantine"
target_dir="$mock_output/targets/ramips/mt7621"
printf 'initramfs\n' >"$target_dir/openwrt-test-$DEVICE_PROFILE-initramfs-kernel.bin"
printf 'unsafe-upgrade\n' >"$target_dir/openwrt-test-$DEVICE_PROFILE-squashfs-sysupgrade.bin"
printf 'unsafe-firmware\n' >"$target_dir/openwrt-test-$DEVICE_PROFILE-squashfs-firmware.bin"
printf 'package\n' >"$mock_output/unrelated.apk"

QUARANTINED_FLASHABLES=0
quarantine_flashables "$mock_output" "$mock_quarantine"
[ "$QUARANTINED_FLASHABLES" -eq 2 ] || fail 'quarantine count is not two'
[ -f "$target_dir/openwrt-test-$DEVICE_PROFILE-initramfs-kernel.bin" ] || \
	fail 'quarantine removed initramfs'
[ -f "$mock_output/unrelated.apk" ] || fail 'quarantine removed unrelated output'
[ "$(find "$mock_quarantine" -type f -name '*.DO-NOT-FLASH' | wc -l)" -eq 2 ] || \
	fail 'quarantine did not retain both forbidden images'
if find "$mock_output" -type f \
	\( -name '*sysupgrade*.bin' -o -name '*firmware*.bin' \) | grep -q .; then
	fail 'forbidden image remained outside quarantine'
fi
pass quarantine-only-flashables

# The publication whitelist permits one RAM-boot kernel plus checksum and
# manifest metadata, and rejects even one forbidden image.
mock_publication="$TEST_ROOT/publication"
mkdir -p "$mock_publication"
printf 'uimage\n' >"$mock_publication/$PUBLISHED_IMAGE"
(
	cd "$mock_publication"
	sha256sum "$PUBLISHED_IMAGE" >"$PUBLISHED_IMAGE.sha256"
)
printf 'release_status=maintenance_initramfs_ram_boot_only\n' \
	>"$mock_publication/build-manifest.txt"
verify_publication_file_set "$mock_publication"
pass publication-whitelist

printf 'forbidden\n' >"$mock_publication/forbidden-sysupgrade.bin"
if (verify_publication_file_set "$mock_publication") >/dev/null 2>&1; then
	fail 'publication whitelist accepted a sysupgrade'
fi
rm -f -- "$mock_publication/forbidden-sysupgrade.bin"
pass publication-rejects-flashable

# The maintenance UCI default must be byte-identical, executable, and the
# lexically final default in the staged root.
OPENWRT_DIR="$TEST_ROOT/openwrt"
mkdir -p \
	"$OPENWRT_DIR/files/usr/sbin" \
	"$OPENWRT_DIR/files/etc/uci-defaults" \
	"$OPENWRT_DIR/files/etc"
cp -- "$SANITIZER_SOURCE" \
	"$OPENWRT_DIR/files/usr/sbin/cr6608-crashlog-sanitize"
cp -- "$MARKER_SOURCE" \
	"$OPENWRT_DIR/files/etc/cr6608-crashlog-maintenance.marker"
cp -- "$WIFI_DISABLE_SOURCE" \
	"$OPENWRT_DIR/files/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"
printf '#!/bin/sh\nexit 0\n' \
	>"$OPENWRT_DIR/files/etc/uci-defaults/99-normal-default"
chmod 0755 \
	"$OPENWRT_DIR/files/usr/sbin/cr6608-crashlog-sanitize" \
	"$OPENWRT_DIR/files/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"
chmod 0644 "$OPENWRT_DIR/files/etc/cr6608-crashlog-maintenance.marker"
mkdir -p "$TEST_ROOT/mock-bin"
cat >"$TEST_ROOT/mock-bin/stat" <<'EOF'
#!/bin/sh
case "$*" in
	'-c %a '*/cr6608-crashlog-maintenance.marker) printf '%s\n' 644; exit 0 ;;
esac
exec /usr/bin/stat "$@"
EOF
chmod 0755 "$TEST_ROOT/mock-bin/stat"
PATH="$TEST_ROOT/mock-bin:$PATH"
export PATH
verify_overlay_staging
pass wifi-disable-is-last

printf '#!/bin/sh\nexit 0\n' \
	>"$OPENWRT_DIR/files/etc/uci-defaults/zzzzz-too-late"
if (verify_overlay_staging) >/dev/null 2>&1; then
	fail 'overlay verifier accepted a later UCI default'
fi
pass wifi-disable-rejects-later-default

# Mock restoration proves that overlay material and compiled root staging are
# removed, the normal config/DTS bytes return, and target/linux is cleaned.
restore_root="$TEST_ROOT/restore-openwrt"
restore_backups="$TEST_ROOT/restore-backups"
mkdir -p \
	"$restore_root/files/usr/sbin" \
	"$restore_root/files/etc/uci-defaults" \
	"$restore_root/target/linux/ramips/dts" \
	"$restore_root/build_dir/mock/root-ramips/usr/sbin" \
	"$restore_root/build_dir/mock/root-ramips/etc/uci-defaults" \
	"$restore_backups"
printf 'normal-config\n' >"$restore_backups/config"
printf 'normal-dtsi\n' >"$restore_backups/family.dtsi"
printf 'normal-dts\n' >"$restore_backups/device.dts"
printf 'maintenance-config\n' >"$restore_root/.config"
printf 'maintenance-dtsi\n' \
	>"$restore_root/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi"
printf 'maintenance-dts\n' \
	>"$restore_root/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts"
printf 'maintenance\n' >"$restore_root/files/usr/sbin/cr6608-crashlog-sanitize"
printf 'maintenance\n' >"$restore_root/files/etc/cr6608-crashlog-maintenance.marker"
printf 'maintenance\n' \
	>"$restore_root/files/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"
printf 'compiled-maintenance\n' \
	>"$restore_root/build_dir/mock/root-ramips/usr/sbin/cr6608-crashlog-sanitize"
printf 'compiled-maintenance\n' \
	>"$restore_root/build_dir/mock/root-ramips/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"

cat >"$TEST_ROOT/mock-bin/git" <<'EOF'
#!/bin/sh
case "$*" in
	*'apply --reverse --check '*) exit 0 ;;
	*'apply --reverse '*)
		cp "$MOCK_NORMAL_DTSI" \
			"$MOCK_RESTORE_ROOT/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi"
		cp "$MOCK_NORMAL_DTS" \
			"$MOCK_RESTORE_ROOT/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts"
		exit 0
		;;
esac
exit 2
EOF
cat >"$TEST_ROOT/mock-bin/make" <<'EOF'
#!/bin/sh
[ "$*" = 'target/linux/clean V=s' ] || exit 2
printf '%s\n' "$*" >>"$MOCK_MAKE_LOG"
EOF
chmod 0755 "$TEST_ROOT/mock-bin/git" "$TEST_ROOT/mock-bin/make"

OPENWRT_DIR="$restore_root"
CONFIG_BACKUP="$restore_backups/config"
CONFIG_BEFORE_SHA="$(sha256sum "$CONFIG_BACKUP" | awk '{print $1}')"
CONFIG_BEFORE_MODE=600
DTSI_BEFORE_SHA="$(sha256sum "$restore_backups/family.dtsi" | awk '{print $1}')"
DTS_BEFORE_SHA="$(sha256sum "$restore_backups/device.dts" | awk '{print $1}')"
PATCH_APPLIED=1
OVERLAY_INSTALLED=1
CONFIG_MUTATED=1
TREE_RESTORED=0
MOCK_NORMAL_DTSI="$restore_backups/family.dtsi"
MOCK_NORMAL_DTS="$restore_backups/device.dts"
MOCK_RESTORE_ROOT="$restore_root"
MOCK_MAKE_LOG="$TEST_ROOT/make.log"
export MOCK_NORMAL_DTSI MOCK_NORMAL_DTS MOCK_RESTORE_ROOT MOCK_MAKE_LOG
: >"$MOCK_MAKE_LOG"
restore_prepared_tree
[ "$TREE_RESTORED" = 1 ] || fail 'restore did not reach restored state'
[ "$PATCH_APPLIED:$OVERLAY_INSTALLED:$CONFIG_MUTATED" = '0:0:0' ] || \
	fail 'restore did not disarm mutation state'
cmp -s "$restore_backups/config" "$restore_root/.config" || \
	fail 'restore did not recover normal config'
cmp -s "$restore_backups/family.dtsi" \
	"$restore_root/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi" || \
	fail 'restore did not recover family DTSI'
cmp -s "$restore_backups/device.dts" \
	"$restore_root/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts" || \
	fail 'restore did not recover device DTS'
[ ! -e "$restore_root/files/usr/sbin/cr6608-crashlog-sanitize" ] || \
	fail 'restore retained sanitizer in normal overlay'
[ ! -e "$restore_root/build_dir/mock/root-ramips/usr/sbin/cr6608-crashlog-sanitize" ] || \
	fail 'restore retained sanitizer in compiled root staging'
grep -Fqx 'target/linux/clean V=s' "$MOCK_MAKE_LOG" || \
	fail 'restore did not clean the writable-kernel cache'
pass restore-normal-tree

# Static fail-closed contracts for the real build path.
grep -Fq "CONFIG_BINARY_FOLDER=\"\$ISOLATED_OUTPUT\"" "$BUILDER" || \
	fail 'builder does not bind make output to the isolated directory'
grep -Fq 'CONFIG_TARGET_ROOTFS_INITRAMFS y' "$BUILDER" || \
	fail 'builder does not enable initramfs'
grep -Fq 'CONFIG_TARGET_ROOTFS_SQUASHFS' "$BUILDER" || \
	fail 'builder does not explicitly disable squashfs'
grep -Fq 'quarantine_flashables "$ISOLATED_OUTPUT" "$QUARANTINE_DIR"' "$BUILDER" || \
	fail 'builder does not quarantine generated flashables'
grep -Fq 'make target/linux/clean V=s' "$BUILDER" || \
	fail 'builder does not purge the writable-kernel build cache'
grep -Fq 'git -C "$OPENWRT_DIR" apply --reverse "$DTS_PATCH"' "$BUILDER" || \
	fail 'builder does not restore the normal DTS'
grep -Fq "MAINTENANCE_UCI_BASENAME='zzzz-cr6608-crashlog-maintenance'" "$BUILDER" || \
	fail 'maintenance UCI default does not have the locked final name'
grep -Fq 'publication must contain exactly one binary image' "$BUILDER" || \
	fail 'publication one-image gate is absent'
grep -Fq 'maintenance build changed the normal binary tree' "$BUILDER" || \
	fail 'normal bin-tree immutability gate is absent'
if grep -Eq '(^|[[:space:]])(bash|sh)[[:space:]].*build\.sh|inspect-image\.sh' "$BUILDER"; then
	fail 'independent builder invokes the normal builder or inspector'
fi
pass static-build-contract

[ "$pass_count" -eq 7 ] || fail "unexpected pass count: $pass_count"
printf 'CR6608_CRASHLOG_BUILD_CONTRACT_TESTS=PASS cases=%s real_builds=0 nand_writes=0\n' \
	"$pass_count"
