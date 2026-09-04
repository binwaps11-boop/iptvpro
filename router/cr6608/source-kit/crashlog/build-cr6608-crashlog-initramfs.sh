#!/usr/bin/env bash
# Build the CR6608 crash-log maintenance kernel from an already prepared,
# successfully built normal OpenWrt tree. The only published image is an
# initramfs kernel intended for RAM boot; no flashable image may escape.

set -Eeuo pipefail
umask 077

EXPECTED_OPENWRT_COMMIT='f0a60eee2fe051741c643ea6118718aae1ef17fb'
DEVICE_PROFILE='xiaomi_mi-router-cr6608'
PUBLISHED_IMAGE='cr6608-CRASHLOG-SANITIZE-MAINTENANCE-RAMBOOT-ONLY-initramfs-kernel.bin'
MAINTENANCE_UCI_BASENAME='zzzz-cr6608-crashlog-maintenance'
EXPECTED_MARKER_SHA256='c4597a2051d8a59278e3d360842197b35739297cf7c06974477b8ccf24b4da44'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DTS_PATCH="$KIT_DIR/patches/995-cr6608-crashlog-maintenance-write-gate.patch"
SANITIZER_SOURCE="$SCRIPT_DIR/cr6608-crashlog-sanitize"
MARKER_SOURCE="$SCRIPT_DIR/cr6608-crashlog-maintenance.marker"
WIFI_DISABLE_SOURCE="$SCRIPT_DIR/01-cr6608-crashlog-maintenance"

OPENWRT_DIR=''
PUBLISH_DIR=''
PUBLISH_PARENT=''
PUBLISH_PARENT_IDENTITY=''
WORK_DIR=''
WORK_DIR_IDENTITY=''
ISOLATED_OUTPUT=''
ISOLATED_OUTPUT_IDENTITY=''
QUARANTINE_DIR=''
QUARANTINE_DIR_IDENTITY=''
PUBLISH_STAGE=''
CONFIG_BACKUP=''
CONFIG_BEFORE_SHA=''
CONFIG_BEFORE_MODE=''
DEFAULT_BIN_BACKUP=''
DEFAULT_BIN_IDENTITY=''
OPENWRT_PARENT_IDENTITY=''
DTSI_BEFORE_SHA=''
DTS_BEFORE_SHA=''
PATCH_APPLIED=0
OVERLAY_INSTALLED=0
CONFIG_MUTATED=0
TREE_RESTORED=0
QUARANTINED_FLASHABLES=0
LOCK_FD=''

say() {
	printf '%s\n' "$*"
}

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "required host command is missing: $1"
}

require_regular_input() {
	local path=$1
	[ -f "$path" ] && [ ! -L "$path" ] || die "required source input is not a regular file: $path"
}

canonical_existing_dir() {
	local raw=$1
	local resolved
	[ -n "$raw" ] || die 'empty directory path'
	[[ "$raw" = /* ]] || die "directory path must be absolute: $raw"
	[[ "$raw" =~ ^/[A-Za-z0-9._/-]+$ ]] || \
		die "directory path contains characters unsafe for GNU make: $raw"
	[ -d "$raw" ] && [ ! -L "$raw" ] || die "directory is absent or is a symlink: $raw"
	resolved="$(realpath -e -- "$raw")" || die "cannot resolve directory: $raw"
	[ "$resolved" = "$raw" ] || die "directory path must already be canonical: $raw"
	printf '%s\n' "$resolved"
}

prepare_publish_target() {
	local requested=$1
	local parent base resolved_parent
	[ -n "$requested" ] || die 'empty publication path'
	[[ "$requested" = /* ]] || die "publication path must be absolute: $requested"
	[[ "$requested" =~ ^/[A-Za-z0-9._/-]+$ ]] || \
		die "publication path contains characters unsafe for GNU make: $requested"
	[ ! -e "$requested" ] && [ ! -L "$requested" ] || \
		die "publication path already exists: $requested"
	parent="$(dirname -- "$requested")"
	base="$(basename -- "$requested")"
	case "$base" in
		''|.|..|.*) die "unsafe publication directory name: $base" ;;
	esac
	case "$requested" in *$'\n'*|*'"'*) die 'publication path contains a forbidden character' ;; esac
	[ -d "$parent" ] && [ ! -L "$parent" ] || \
		die "publication parent is absent or is a symlink: $parent"
	resolved_parent="$(realpath -e -- "$parent")" || die 'cannot resolve publication parent'
	[ "$parent" = "$resolved_parent" ] || \
		die "publication parent path must already be canonical: $parent"
	PUBLISH_PARENT=$resolved_parent
	PUBLISH_PARENT_IDENTITY="$(stat -c '%d:%i' "$resolved_parent")"
	PUBLISH_DIR="$resolved_parent/$base"
}

snapshot_bin_tree() {
	local root=$1
	local destination=$2
	local scan rc=0
	: >"$destination"
	[ ! -e "$root" ] && return 0
	[ -d "$root" ] && [ ! -L "$root" ] || return 1
	[ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] || return 1
	scan="$(mktemp "$WORK_DIR/.bin-snapshot.XXXXXX")" || return 1
	if ! find "$root" ! -type d ! -type f ! -type l -print0 >"$scan"; then
		rm -f -- "$scan"
		return 1
	fi
	if [ -s "$scan" ]; then
		rm -f -- "$scan"
		return 1
	fi
	if ! find "$root" \( -type f -o -type l \) -printf '%P\0' >"$scan" ||
		! LC_ALL=C sort -z "$scan" -o "$scan"; then
		rm -f -- "$scan"
		return 1
	fi
	while IFS= read -r -d '' relative; do
		local path hash
		path="$root/$relative"
		if [ -L "$path" ]; then
			printf 'SYMLINK:%s:%s  %s\n' \
				"$(stat -c '%f:%u:%g' "$path")" "$(readlink -- "$path")" "$relative" ||
				{ rc=1; break; }
		elif [ -f "$path" ]; then
			hash="$(sha256sum "$path" | awk '{print $1}')" ||
				{ rc=1; break; }
			printf '%s:%s  %s\n' "$(stat -c '%f:%u:%g:%s' "$path")" "$hash" "$relative" ||
				{ rc=1; break; }
		else
			rc=1
			break
		fi
	done <"$scan"
	rm -f -- "$scan"
	return "$rc"
}

restore_normal_bin_tree() {
	local current_manifest="$WORK_DIR/default-bin.current"
	local restored_manifest="$WORK_DIR/default-bin.restored-check"
	local contaminated="$WORK_DIR/contaminated-default-bin"
	local restore_stage="$WORK_DIR/default-bin.restore-stage"
	[ -n "$DEFAULT_BIN_BACKUP" ] && [ -d "$DEFAULT_BIN_BACKUP" ] || return 1
	[ "$(stat -c '%d:%i' "$(dirname "$OPENWRT_DIR")")" = "$OPENWRT_PARENT_IDENTITY" ] ||
		return 1
	if snapshot_bin_tree "$OPENWRT_DIR/bin" "$current_manifest" &&
		cmp -s "$WORK_DIR/default-bin.before" "$current_manifest"; then
		return 0
	fi
	if [ -e "$restore_stage" ] || [ -L "$restore_stage" ]; then
		case "$restore_stage" in "$WORK_DIR/default-bin.restore-stage") ;; *) return 1 ;; esac
		[ -d "$restore_stage" ] && [ ! -L "$restore_stage" ] || return 1
		rm -rf -- "$restore_stage" || return 1
	fi
	cp -a -- "$DEFAULT_BIN_BACKUP" "$restore_stage" || return 1
	snapshot_bin_tree "$restore_stage" "$restored_manifest" || return 1
	cmp -s "$WORK_DIR/default-bin.before" "$restored_manifest" || return 1
	if [ -e "$OPENWRT_DIR/bin" ] || [ -L "$OPENWRT_DIR/bin" ]; then
		[ -d "$OPENWRT_DIR/bin" ] && [ ! -L "$OPENWRT_DIR/bin" ] || return 1
		[ "$(stat -c '%d:%i' "$OPENWRT_DIR/bin")" = "$DEFAULT_BIN_IDENTITY" ] ||
			return 1
		if [ ! -e "$contaminated" ] && [ ! -L "$contaminated" ]; then
			mv -T -- "$OPENWRT_DIR/bin" "$contaminated" || return 1
		else
			return 1
		fi
	elif [ ! -d "$contaminated" ] || [ -L "$contaminated" ]; then
		return 1
	fi
	mv -T -- "$restore_stage" "$OPENWRT_DIR/bin" || return 1
	DEFAULT_BIN_IDENTITY="$(stat -c '%d:%i' "$OPENWRT_DIR/bin")" || return 1
	snapshot_bin_tree "$OPENWRT_DIR/bin" "$restored_manifest" || return 1
	cmp -s "$WORK_DIR/default-bin.before" "$restored_manifest" || return 1
	return 0
}

set_config_bool() {
	local key=$1
	local value=$2
	local line edit
	case "$key" in CONFIG_[A-Z0-9_]*) ;; *) die "invalid config key: $key" ;; esac
	case "$value" in
		y) line="$key=y" ;;
		n) line="# $key is not set" ;;
		*) die "invalid boolean config value: $value" ;;
	esac
	edit="$WORK_DIR/config.edit"
	awk -v key="$key" -v line="$line" '
		$0 == "# " key " is not set" { next }
		index($0, key "=") == 1 { next }
		{ print }
		END { print line }
	' "$OPENWRT_DIR/.config" >"$edit"
	mv -- "$edit" "$OPENWRT_DIR/.config"
}

set_config_string() {
	local key=$1
	local value=$2
	local edit
	case "$key" in CONFIG_[A-Z0-9_]*) ;; *) die "invalid config key: $key" ;; esac
	case "$value" in *$'\n'*|*'"'*) die "unsafe config string for $key" ;; esac
	edit="$WORK_DIR/config.edit"
	awk -v key="$key" -v value="$value" '
		$0 == "# " key " is not set" { next }
		index($0, key "=") == 1 { next }
		{ print }
		END { printf "%s=\"%s\"\n", key, value }
	' "$OPENWRT_DIR/.config" >"$edit"
	mv -- "$edit" "$OPENWRT_DIR/.config"
}

verify_overlay_staging() {
	local overlay="$OPENWRT_DIR/files"
	local sanitizer="$overlay/usr/sbin/cr6608-crashlog-sanitize"
	local marker="$overlay/etc/cr6608-crashlog-maintenance.marker"
	local wifi_disable="$overlay/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"
	local last scan

	cmp -s -- "$SANITIZER_SOURCE" "$sanitizer" || \
		die 'staged sanitizer differs from its source'
	cmp -s -- "$MARKER_SOURCE" "$marker" || \
		die 'staged maintenance marker differs from its source'
	cmp -s -- "$WIFI_DISABLE_SOURCE" "$wifi_disable" || \
		die 'staged Wi-Fi disable default differs from its source'
	[ -x "$sanitizer" ] && [ -x "$wifi_disable" ] || \
		die 'maintenance executables lost executable mode'
	[ "$(stat -c '%a' "$marker")" = 644 ] || die 'maintenance marker mode is not 0644'
	[ "$(sha256sum "$marker" | awk '{print $1}')" = "$EXPECTED_MARKER_SHA256" ] || \
		die 'staged maintenance marker hash mismatch'
	scan="$(mktemp "$WORK_DIR/.uci-default-scan.XXXXXX")" || \
		die 'could not allocate UCI-default scan'
	if ! find "$overlay/etc/uci-defaults" -maxdepth 1 -type f \
		-printf '%f\n' >"$scan"; then
		die 'could not enumerate staged UCI defaults'
	fi
	last="$(LC_ALL=C sort "$scan" | tail -n 1)"
	rm -f -- "$scan"
	[ "$last" = "$MAINTENANCE_UCI_BASENAME" ] || \
		die "Wi-Fi disable default is not lexically last: last=$last"
}

quarantine_flashables() {
	local output_root=$1
	local quarantine=$2
	local counter=0
	local candidate resolved scan
	mkdir -p -- "$quarantine"
	[ -d "$output_root" ] && [ ! -L "$output_root" ] || \
		die "isolated output root is invalid: $output_root"
	[ -d "$quarantine" ] && [ ! -L "$quarantine" ] || \
		die "quarantine root is invalid: $quarantine"
	scan="$(mktemp "$quarantine/.flashable-scan.XXXXXX")" || \
		die 'could not allocate flashable scan'
	if ! find "$output_root" -type l \
		\( -name '*sysupgrade*.bin' -o -name '*firmware*.bin' \) \
		-print0 >"$scan"; then
		die 'could not scan isolated output for flashable symlinks'
	fi
	if [ -s "$scan" ]; then
		die 'isolated output contains a forbidden flashable symlink'
	fi
	if ! find "$output_root" -type f \
		\( -name '*sysupgrade*.bin' -o -name '*firmware*.bin' \) \
		-print0 >"$scan"; then
		die 'could not scan isolated output for flashable files'
	fi
	while IFS= read -r -d '' candidate; do
		resolved="$(realpath -e -- "$candidate")" || \
			die "cannot resolve maintenance flashable: $candidate"
		case "$resolved" in "$output_root"/*) ;; *)
			die "flashable escaped isolated output: $resolved"
		esac
		[ -f "$resolved" ] && [ ! -L "$resolved" ] || \
			die "maintenance flashable is not a regular file: $resolved"
		counter=$((counter + 1))
		mv -- "$resolved" "$quarantine/$(printf '%04d' "$counter")-$(basename -- "$resolved").DO-NOT-FLASH"
	done <"$scan"
	if ! find "$output_root" \( -type f -o -type l \) \
			\( -name '*sysupgrade*.bin' -o -name '*firmware*.bin' \) \
			-print0 >"$scan"; then
		die 'could not rescan isolated output after quarantine'
	fi
	if [ -s "$scan" ]; then
		die 'flashable image remained in the isolated output after quarantine'
	fi
	rm -f -- "$scan"
	QUARANTINED_FLASHABLES=$counter
}

find_exact_initramfs() {
	local output_root=$1
	local -a images=()
	local scan resolved_output candidate resolved_candidate
	resolved_output="$(realpath -e -- "$output_root")" || \
		die 'cannot resolve isolated initramfs output root'
	[ "$resolved_output" = "$output_root" ] || \
		die 'isolated initramfs output root is not canonical'
	scan="$(mktemp "$WORK_DIR/.initramfs-scan.XXXXXX")" || \
		die 'could not allocate initramfs scan'
	if ! find "$output_root/targets/ramips/mt7621" -maxdepth 1 -type f \
		-name "*$DEVICE_PROFILE*initramfs-kernel.bin" -print0 >"$scan"; then
		die 'could not scan isolated output for initramfs'
	fi
	while IFS= read -r -d '' candidate; do
		resolved_candidate="$(realpath -e -- "$candidate")" || \
			die "cannot resolve initramfs candidate: $candidate"
		case "$resolved_candidate" in "$resolved_output"/*) ;; *)
			die "initramfs candidate escaped isolated output: $resolved_candidate"
		esac
		[ -f "$resolved_candidate" ] && [ ! -L "$resolved_candidate" ] || \
			die 'initramfs candidate is not a regular non-symlink file'
		images+=("$resolved_candidate")
	done <"$scan"
	rm -f -- "$scan"
	[ "${#images[@]}" -eq 1 ] || \
		die "expected exactly one CR6608 initramfs, found ${#images[@]}"
	[ ! -L "${images[0]}" ] || die 'initramfs output is a symlink'
	printf '%s\n' "${images[0]}"
}

find_built_root() {
	local -a roots=()
	local scan root
	scan="$(mktemp "$WORK_DIR/.rootfs-scan.XXXXXX")" || \
		die 'could not allocate rootfs scan'
	if ! find "$OPENWRT_DIR/build_dir" -type d -name root-ramips -print0 >"$scan"; then
		die 'could not scan build tree for rootfs staging'
	fi
	while IFS= read -r -d '' root; do
		[ -f "$root/usr/sbin/cr6608-crashlog-sanitize" ] && roots+=("$root")
	done <"$scan"
	rm -f -- "$scan"
	[ "${#roots[@]}" -eq 1 ] || \
		die "expected one maintenance rootfs staging tree, found ${#roots[@]}"
	printf '%s\n' "${roots[0]}"
}

require_rootfs_command() {
	local root=$1
	shift
	local candidate
	for candidate in "$@"; do
		[ -x "$root/$candidate" ] && return 0
	done
	die "maintenance rootfs lacks required command: $*"
}

verify_built_root() {
	local root=$1
	local last_default
	cmp -s -- "$SANITIZER_SOURCE" "$root/usr/sbin/cr6608-crashlog-sanitize" || \
		die 'built rootfs sanitizer differs from source'
	cmp -s -- "$MARKER_SOURCE" "$root/etc/cr6608-crashlog-maintenance.marker" || \
		die 'built rootfs marker differs from source'
	cmp -s -- "$WIFI_DISABLE_SOURCE" \
		"$root/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME" || \
		die 'built rootfs Wi-Fi disable default differs from source'
	last_default="$(find "$root/etc/uci-defaults" -maxdepth 1 -type f -printf '%f\n' | \
		LC_ALL=C sort | tail -n 1)"
	[ "$last_default" = "$MAINTENANCE_UCI_BASENAME" ] || \
		die "built rootfs Wi-Fi disable default is not lexically last: $last_default"
	require_rootfs_command "$root" sbin/mtd usr/sbin/mtd
	require_rootfs_command "$root" usr/bin/flock bin/flock
	require_rootfs_command "$root" usr/bin/stat bin/stat
	require_rootfs_command "$root" usr/sbin/iw sbin/iw
	require_rootfs_command "$root" usr/sbin/bridge sbin/bridge
	require_rootfs_command "$root" usr/sbin/ip sbin/ip
	require_rootfs_command "$root" usr/bin/sha256sum bin/sha256sum
}

verify_built_dtb() {
	local -a dtbs=()
	local dtb properties node scan
	scan="$(mktemp "$WORK_DIR/.dtb-scan.XXXXXX")" || \
		die 'could not allocate DTB scan'
	if ! find "$OPENWRT_DIR/build_dir" -type f \
		-name 'image-mt7621_xiaomi_mi-router-cr6608.dtb' -print0 >"$scan"; then
		die 'could not scan build tree for compiled CR6608 DTB'
	fi
	mapfile -d '' -t dtbs <"$scan"
	rm -f -- "$scan"
	[ "${#dtbs[@]}" -eq 1 ] || \
		die "expected one compiled CR6608 DTB, found ${#dtbs[@]}"
	dtb="${dtbs[0]}"
	[ "$(fdtget -t s "$dtb" /nand/partitions/partition@1c0000 label)" = crash_log ] || \
		die 'compiled DTB crash-log label mismatch'
	properties="$(fdtget -p "$dtb" /nand/partitions/partition@1c0000)" || \
		die 'cannot inspect compiled DTB crash-log properties'
	if grep -Fqx 'read-only' <<<"$properties"; then
		die 'compiled maintenance DTB kept crash_log read-only'
	fi
	for node in \
		partition@0 partition@80000 partition@c0000 \
		partition@100000 partition@180000; do
		properties="$(fdtget -p "$dtb" "/nand/partitions/$node")" || \
			die "cannot inspect protected DTB node: $node"
		grep -Fqx 'read-only' <<<"$properties" || \
			die "compiled maintenance DTB made a protected node writable: $node"
	done
}

verify_generated_initramfs_archive() {
	local image=$1
	local -a archives=()
	local archive audit_dir archive_time image_time scan
	scan="$(mktemp "$WORK_DIR/.cpio-scan.XXXXXX")" || \
		die 'could not allocate initramfs cpio scan'
	if ! find "$OPENWRT_DIR/build_dir" -type f \
		-name 'initramfs_data.cpio' -print0 >"$scan"; then
		die 'could not scan build tree for generated initramfs cpio'
	fi
	mapfile -d '' -t archives <"$scan"
	rm -f -- "$scan"
	[ "${#archives[@]}" -eq 1 ] || \
		die "expected one generated initramfs cpio, found ${#archives[@]}"
	archive="${archives[0]}"
	audit_dir="$WORK_DIR/initramfs-cpio-audit"
	mkdir -p -- "$audit_dir"
	(
		cd "$audit_dir"
		cpio --quiet -id --no-absolute-filenames \
			usr/sbin/cr6608-crashlog-sanitize \
			etc/cr6608-crashlog-maintenance.marker \
			"etc/uci-defaults/$MAINTENANCE_UCI_BASENAME" <"$archive"
	)
	cmp -s -- "$SANITIZER_SOURCE" \
		"$audit_dir/usr/sbin/cr6608-crashlog-sanitize" || \
		die 'generated initramfs cpio sanitizer differs from source'
	cmp -s -- "$MARKER_SOURCE" \
		"$audit_dir/etc/cr6608-crashlog-maintenance.marker" || \
		die 'generated initramfs cpio marker differs from source'
	cmp -s -- "$WIFI_DISABLE_SOURCE" \
		"$audit_dir/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME" || \
		die 'generated initramfs cpio Wi-Fi default differs from source'
	[ -x "$audit_dir/usr/sbin/cr6608-crashlog-sanitize" ] && \
		[ -x "$audit_dir/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME" ] || \
		die 'generated initramfs cpio lost executable modes'
	archive_time="$(stat -c '%Y' "$archive")"
	image_time="$(stat -c '%Y' "$image")"
	[ "$image_time" -ge "$archive_time" ] || \
		die 'published initramfs predates its generated cpio'
}

verify_initramfs_envelope() {
	local image=$1
	local size
	[ -s "$image" ] && [ -f "$image" ] && [ ! -L "$image" ] || \
		die 'initramfs image is absent or unsafe'
	size="$(stat -c '%s' "$image")"
	[ "$size" -gt 1048576 ] || die "initramfs image is unexpectedly small: $size"
	python3 - "$image" <<'PY'
import binascii
import pathlib
import struct
import sys

path = pathlib.Path(sys.argv[1])
image = path.read_bytes()
if len(image) <= 64 or len(image) > 128 * 1024 * 1024:
    raise SystemExit("invalid uImage byte length")
header = bytearray(image[:64])
try:
    (
        magic,
        header_crc,
        _timestamp,
        payload_size,
        load,
        entry,
        data_crc,
        os_id,
        arch_id,
        image_type,
        compression,
        _name,
    ) = struct.unpack(">7I4B32s", header)
except struct.error as exc:
    raise SystemExit(f"cannot decode uImage header: {exc}")
if magic != 0x27051956:
    raise SystemExit("legacy uImage magic mismatch")
header[4:8] = b"\0\0\0\0"
if binascii.crc32(header) & 0xFFFFFFFF != header_crc:
    raise SystemExit("uImage header CRC mismatch")
payload = image[64:]
if payload_size != len(payload):
    raise SystemExit("uImage payload length mismatch")
if binascii.crc32(payload) & 0xFFFFFFFF != data_crc:
    raise SystemExit("uImage payload CRC mismatch")
if (os_id, arch_id, image_type, compression) != (5, 5, 2, 0):
    raise SystemExit("unexpected uImage OS/architecture/type/compression")
if (load, entry) != (0x80001000, 0x80001000):
    raise SystemExit("unexpected uImage load or entry address")
PY
}

verify_publication_file_set() {
	local root=$1
	local expected checksum manifest scan actual
	local -a entries=()
	checksum="$PUBLISHED_IMAGE.sha256"
	manifest='build-manifest.txt'
	expected="$(printf '%s\n%s\n%s\n' "$PUBLISHED_IMAGE" "$checksum" "$manifest" | LC_ALL=C sort)"
	scan="$(mktemp "$WORK_DIR/.publication-scan.XXXXXX")" || \
		die 'could not allocate publication scan'
	if ! find "$root" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' >"$scan"; then
		die 'could not enumerate publication files'
	fi
	actual="$(LC_ALL=C sort "$scan")"
	[ "$actual" = "$expected" ] || die 'publication contains an unexpected file set'
	if ! find "$root" -mindepth 1 -maxdepth 1 -type d -print0 >"$scan"; then
		die 'could not enumerate publication directories'
	fi
	[ ! -s "$scan" ] || \
		die 'publication contains an unexpected directory'
	if ! find "$root" -mindepth 1 -maxdepth 1 -type l -print0 >"$scan"; then
		die 'could not enumerate publication symlinks'
	fi
	[ ! -s "$scan" ] || \
		die 'publication contains an unexpected symlink'
	if ! find "$root" -maxdepth 1 -type f -name '*.bin' -print0 >"$scan"; then
		die 'could not enumerate publication binary images'
	fi
	mapfile -d '' -t entries <"$scan"
	[ "${#entries[@]}" -eq 1 ] || \
		die 'publication must contain exactly one binary image'
	if ! find "$root" \( -type f -o -type l \) \
			\( -iname '*sysupgrade*' -o -iname '*firmware*' \) \
			-print0 >"$scan"; then
		die 'could not scan publication for forbidden flashables'
	fi
	if [ -s "$scan" ]; then
		die 'publication contains a forbidden flashable image'
	fi
	if ! find "$root" -mindepth 1 ! -type f -print0 >"$scan"; then
		die 'could not scan publication entry types'
	fi
	[ ! -s "$scan" ] || die 'publication contains a non-regular entry'
	rm -f -- "$scan"
	(
		cd "$root"
		sha256sum -c "$checksum" >/dev/null
	) || die 'published initramfs checksum verification failed'
}

destroy_private_generated_output() {
	local path expected_identity
	[ "$(stat -c '%d:%i' "$WORK_DIR")" = "$WORK_DIR_IDENTITY" ] || \
		die 'private work identity changed before generated-output cleanup'
	for path in "$ISOLATED_OUTPUT" "$QUARANTINE_DIR"; do
		case "$path" in "$WORK_DIR/output") expected_identity=$ISOLATED_OUTPUT_IDENTITY ;;
			"$WORK_DIR/quarantine") expected_identity=$QUARANTINE_DIR_IDENTITY ;;
			*) die "unsafe generated-output cleanup path: $path" ;;
		esac
		[ -d "$path" ] && [ ! -L "$path" ] || \
			die "generated-output cleanup target is unsafe: $path"
		[ "$(stat -c '%d:%i' "$path")" = "$expected_identity" ] || \
			die "generated-output identity changed before cleanup: $path"
		rm -rf -- "$path"
		[ ! -e "$path" ] && [ ! -L "$path" ] || \
			die "generated-output cleanup failed: $path"
	done
}

purge_maintenance_root_staging() {
	local root scan
	[ ! -d "$OPENWRT_DIR/build_dir" ] && return 0
	scan="$(mktemp "$WORK_DIR/.root-purge-scan.XXXXXX")" || return 1
	if ! find "$OPENWRT_DIR/build_dir" -type d -name root-ramips -print0 >"$scan"; then
		rm -f -- "$scan"
		return 1
	fi
	while IFS= read -r -d '' root; do
		if ! rm -f -- \
			"$root/usr/sbin/cr6608-crashlog-sanitize" \
			"$root/etc/cr6608-crashlog-maintenance.marker" \
			"$root/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"; then
			rm -f -- "$scan"
			return 1
		fi
	done <"$scan"
	rm -f -- "$scan"
}

restore_prepared_tree() {
	local failed=0 current_dtsi current_dts current_config
	set +e
	if [ -n "$CONFIG_BACKUP" ]; then
		if rm -f -- \
			"$OPENWRT_DIR/files/usr/sbin/cr6608-crashlog-sanitize" \
			"$OPENWRT_DIR/files/etc/cr6608-crashlog-maintenance.marker" \
			"$OPENWRT_DIR/files/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"; then
			OVERLAY_INSTALLED=0
		else
			failed=1
		fi
	fi
	purge_maintenance_root_staging || failed=1
	if [ -n "$DEFAULT_BIN_BACKUP" ]; then
		restore_normal_bin_tree || failed=1
	fi
	if [ -n "$DTSI_BEFORE_SHA" ] && [ -n "$DTS_BEFORE_SHA" ]; then
		current_dtsi="$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi" 2>/dev/null | awk '{print $1}')"
		current_dts="$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts" 2>/dev/null | awk '{print $1}')"
		if [ "$current_dtsi" != "$DTSI_BEFORE_SHA" ] ||
			[ "$current_dts" != "$DTS_BEFORE_SHA" ]; then
			if ! git -C "$OPENWRT_DIR" apply --reverse --check "$DTS_PATCH" ||
				! git -C "$OPENWRT_DIR" apply --reverse "$DTS_PATCH"; then
				failed=1
			fi
		fi
		current_dtsi="$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi" 2>/dev/null | awk '{print $1}')"
		current_dts="$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts" 2>/dev/null | awk '{print $1}')"
		[ "$current_dtsi" = "$DTSI_BEFORE_SHA" ] &&
			[ "$current_dts" = "$DTS_BEFORE_SHA" ] && PATCH_APPLIED=0 ||
			failed=1
	fi
	if [ -n "$CONFIG_BEFORE_SHA" ] && [ -f "$CONFIG_BACKUP" ]; then
		current_config="$(sha256sum "$OPENWRT_DIR/.config" 2>/dev/null | awk '{print $1}')"
		if [ "$current_config" != "$CONFIG_BEFORE_SHA" ]; then
			if ! cp -- "$CONFIG_BACKUP" "$OPENWRT_DIR/.config" ||
				! chmod "$CONFIG_BEFORE_MODE" "$OPENWRT_DIR/.config"; then
				failed=1
			fi
		fi
		current_config="$(sha256sum "$OPENWRT_DIR/.config" 2>/dev/null | awk '{print $1}')"
		[ "$current_config" = "$CONFIG_BEFORE_SHA" ] && CONFIG_MUTATED=0 ||
			failed=1
	fi
	if [ "$failed" -eq 0 ]; then
		[ "$(sha256sum "$OPENWRT_DIR/.config" | awk '{print $1}')" = "$CONFIG_BEFORE_SHA" ] ||
			failed=1
		[ "$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi" | awk '{print $1}')" = "$DTSI_BEFORE_SHA" ] ||
			failed=1
		[ "$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts" | awk '{print $1}')" = "$DTS_BEFORE_SHA" ] ||
			failed=1
	fi
	if [ "$failed" -eq 0 ]; then
		(
			cd "$OPENWRT_DIR" &&
				make target/linux/clean V=s >/dev/null
		) || failed=1
	fi
	set -e
	if [ "$failed" -eq 0 ]; then
		TREE_RESTORED=1
		return 0
	fi
	return 1
}

cleanup_workdir() {
	[ -n "$WORK_DIR" ] || return 0
	case "$WORK_DIR" in
		"$PUBLISH_PARENT"/.cr6608-crashlog-build.*) ;;
		*) printf 'WARNING: refusing unsafe work-directory cleanup: %s\n' "$WORK_DIR" >&2; return 1 ;;
	esac
	[ ! -e "$WORK_DIR" ] && return 0
	[ -d "$WORK_DIR" ] && [ ! -L "$WORK_DIR" ] || return 1
	[ "$(stat -c '%d:%i' "$WORK_DIR")" = "$WORK_DIR_IDENTITY" ] || return 1
	[ "$(stat -c '%d:%i' "$PUBLISH_PARENT")" = "$PUBLISH_PARENT_IDENTITY" ] || return 1
	rm -rf -- "$WORK_DIR"
}

exit_guard() {
	local rc=$?
	local restore_ok=1
	trap - EXIT HUP INT TERM
	if [ "$TREE_RESTORED" != 1 ] && [ -n "$OPENWRT_DIR" ] && [ -n "$CONFIG_BACKUP" ]; then
		if ! restore_prepared_tree; then
			restore_ok=0
			printf 'FATAL: prepared OpenWrt tree restoration failed; recovery work retained at %s\n' \
				"$WORK_DIR" >&2
		fi
	fi
	if [ "$restore_ok" = 1 ] && [ "$TREE_RESTORED" = 1 ]; then
		cleanup_workdir || \
			printf 'WARNING: private maintenance work cleanup was incomplete\n' >&2
	else
		printf 'WARNING: private maintenance work was not deleted because restoration is incomplete\n' >&2
	fi
	exit "$rc"
}

main() {
	[ "$#" -eq 2 ] || {
		printf 'Usage: %s /absolute/prepared/openwrt /absolute/new/publication-dir\n' "$0" >&2
		exit 2
	}

	for command_name in \
		awk basename chmod cmp cp cpio dirname fdtget find flock git grep \
		install make mkdir mktemp mv nproc od python3 readlink realpath rm \
		sha256sum sort stat tail tee tr wc; do
		require_command "$command_name"
	done
	require_regular_input "$DTS_PATCH"
	require_regular_input "$SANITIZER_SOURCE"
	require_regular_input "$MARKER_SOURCE"
	require_regular_input "$WIFI_DISABLE_SOURCE"
	[ "$(sha256sum "$MARKER_SOURCE" | awk '{print $1}')" = "$EXPECTED_MARKER_SHA256" ] || \
		die 'source maintenance marker hash mismatch'

	OPENWRT_DIR="$(canonical_existing_dir "$1")"
	prepare_publish_target "$2"
	case "$PUBLISH_PARENT" in
		"$OPENWRT_DIR"|"$OPENWRT_DIR"/*)
			die 'publication must be outside the prepared OpenWrt tree'
			;;
	esac
	case "$OPENWRT_DIR" in *$'\n'*|*'"'*) die 'OpenWrt path contains a forbidden character' ;; esac
	[ -d "$OPENWRT_DIR/.git" ] || die 'prepared OpenWrt tree lacks Git metadata'
	require_regular_input "$OPENWRT_DIR/.config"
	require_regular_input "$OPENWRT_DIR/Makefile"
	[ "$(git -C "$OPENWRT_DIR" rev-parse HEAD)" = "$EXPECTED_OPENWRT_COMMIT" ] || \
		die 'prepared OpenWrt tree is not at the pinned release commit'
	git -C "$OPENWRT_DIR" diff --check
	grep -Fqx "CONFIG_TARGET_ramips_mt7621_DEVICE_$DEVICE_PROFILE=y" \
		"$OPENWRT_DIR/.config" || die 'prepared tree does not select CR6608'
	[ -d "$OPENWRT_DIR/build_dir" ] && [ -d "$OPENWRT_DIR/staging_dir" ] || \
		die 'OpenWrt tree was not prepared by a completed normal build'

	local -a normal_sysupgrades=() normal_firmwares=()
	local normal_scan
	normal_scan="$(mktemp "$PUBLISH_PARENT/.normal-image-scan.XXXXXX")" || \
		die 'could not allocate normal-image scan'
	if ! find "$OPENWRT_DIR/bin/targets/ramips/mt7621" -maxdepth 1 -type f \
		-name "*$DEVICE_PROFILE*sysupgrade.bin" -print0 >"$normal_scan"; then
		rm -f -- "$normal_scan"
		die 'could not scan for the normal sysupgrade reference'
	fi
	mapfile -d '' -t normal_sysupgrades <"$normal_scan"
	if ! find "$OPENWRT_DIR/bin/targets/ramips/mt7621" -maxdepth 1 -type f \
		-name "*$DEVICE_PROFILE*firmware.bin" -print0 >"$normal_scan"; then
		rm -f -- "$normal_scan"
		die 'could not scan for the normal combined-firmware reference'
	fi
	mapfile -d '' -t normal_firmwares <"$normal_scan"
	rm -f -- "$normal_scan"
	[ "${#normal_sysupgrades[@]}" -eq 1 ] && [ "${#normal_firmwares[@]}" -eq 1 ] || \
		die 'a completed normal CR6608 build must exist before maintenance build'

	local overlay="$OPENWRT_DIR/files"
	[ -d "$overlay/etc/uci-defaults" ] && [ ! -L "$overlay" ] || \
		die 'prepared normal overlay is unavailable or unsafe'
	local overlay_dir resolved_overlay_dir
	for overlay_dir in \
		"$overlay" "$overlay/usr" "$overlay/usr/sbin" \
		"$overlay/etc" "$overlay/etc/uci-defaults"; do
		[ -d "$overlay_dir" ] && [ ! -L "$overlay_dir" ] || \
			die "overlay component is absent or is a symlink: $overlay_dir"
		resolved_overlay_dir="$(realpath -e -- "$overlay_dir")" || \
			die "cannot resolve overlay component: $overlay_dir"
		case "$resolved_overlay_dir" in "$overlay"|"$overlay"/*) ;; *)
			die "overlay component escapes the prepared tree: $overlay_dir"
		esac
	done
	for absent in \
		"$overlay/usr/sbin/cr6608-crashlog-sanitize" \
		"$overlay/etc/cr6608-crashlog-maintenance.marker" \
		"$overlay/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"; do
		[ ! -e "$absent" ] && [ ! -L "$absent" ] || \
			die "normal prepared tree already contains maintenance material: $absent"
	done
	git -C "$OPENWRT_DIR" apply --check "$DTS_PATCH" || \
		die 'crash-log write-gate patch does not apply exactly once to the normal tree'

	local lock_path lock_identity fd_identity
	lock_path="$(dirname "$OPENWRT_DIR")/.cr6608-build.lock"
	if [ -e "$lock_path" ] || [ -L "$lock_path" ]; then
		[ -f "$lock_path" ] && [ ! -L "$lock_path" ] || \
			die 'shared build lock is not a regular file'
	else
		( set -o noclobber; : >"$lock_path" ) 2>/dev/null || true
		[ -f "$lock_path" ] && [ ! -L "$lock_path" ] || \
			die 'could not safely create the shared build lock'
	fi
	lock_identity="$(stat -c '%d:%i' "$lock_path")"
	exec {LOCK_FD}>>"$lock_path"
	fd_identity="$(stat -Lc '%d:%i' "/proc/$$/fd/$LOCK_FD")" || \
		die 'could not identify the opened shared build lock'
	[ "$fd_identity" = "$lock_identity" ] && [ ! -L "$lock_path" ] || \
		die 'shared build lock identity changed while opening it'
	flock -n "$LOCK_FD" || die 'another CR6608 build holds the shared build lock'

	WORK_DIR="$(mktemp -d "$PUBLISH_PARENT/.cr6608-crashlog-build.XXXXXX")"
	[ -d "$WORK_DIR" ] && [ ! -L "$WORK_DIR" ] || die 'private work directory creation failed'
	WORK_DIR_IDENTITY="$(stat -c '%d:%i' "$WORK_DIR")"
	OPENWRT_PARENT_IDENTITY="$(stat -c '%d:%i' "$(dirname "$OPENWRT_DIR")")"
	ISOLATED_OUTPUT="$WORK_DIR/output"
	QUARANTINE_DIR="$WORK_DIR/quarantine"
	PUBLISH_STAGE="$WORK_DIR/publication"
	CONFIG_BACKUP="$WORK_DIR/config.normal"
	mkdir -p -- "$ISOLATED_OUTPUT" "$QUARANTINE_DIR" "$PUBLISH_STAGE"
	ISOLATED_OUTPUT_IDENTITY="$(stat -c '%d:%i' "$ISOLATED_OUTPUT")"
	QUARANTINE_DIR_IDENTITY="$(stat -c '%d:%i' "$QUARANTINE_DIR")"
	trap exit_guard EXIT
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM

	cp -- "$OPENWRT_DIR/.config" "$CONFIG_BACKUP"
	[ -d "$OPENWRT_DIR/bin" ] && [ ! -L "$OPENWRT_DIR/bin" ] || \
		die 'normal binary tree is absent or unsafe'
	DEFAULT_BIN_IDENTITY="$(stat -c '%d:%i' "$OPENWRT_DIR/bin")"
	DEFAULT_BIN_BACKUP="$WORK_DIR/default-bin.normal"
	cp -a -- "$OPENWRT_DIR/bin" "$DEFAULT_BIN_BACKUP"
	[ -d "$DEFAULT_BIN_BACKUP" ] && [ ! -L "$DEFAULT_BIN_BACKUP" ] || \
		die 'normal binary-tree backup failed'
	CONFIG_BEFORE_SHA="$(sha256sum "$CONFIG_BACKUP" | awk '{print $1}')"
	CONFIG_BEFORE_MODE="$(stat -c '%a' "$OPENWRT_DIR/.config")"
	DTSI_BEFORE_SHA="$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi" | awk '{print $1}')"
	DTS_BEFORE_SHA="$(sha256sum "$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts" | awk '{print $1}')"
	snapshot_bin_tree "$OPENWRT_DIR/bin" "$WORK_DIR/default-bin.before" || \
		die 'could not snapshot the normal binary tree'
	CONFIG_MUTATED=1

	PATCH_APPLIED=1
	git -C "$OPENWRT_DIR" apply "$DTS_PATCH"
	grep -Fqx $'\t\tcrash_log: partition@1c0000 {' \
		"$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi" || \
		die 'shared DTSI lacks the labelled crash_log node'
	grep -Fqx '&crash_log {' \
		"$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6608.dts" || \
		die 'CR6608 DTS lacks the device-only crash_log override'

	OVERLAY_INSTALLED=1
	install -D -m 0755 -- "$SANITIZER_SOURCE" \
		"$overlay/usr/sbin/cr6608-crashlog-sanitize"
	install -D -m 0644 -- "$MARKER_SOURCE" \
		"$overlay/etc/cr6608-crashlog-maintenance.marker"
	install -D -m 0755 -- "$WIFI_DISABLE_SOURCE" \
		"$overlay/etc/uci-defaults/$MAINTENANCE_UCI_BASENAME"
	verify_overlay_staging

	set_config_bool CONFIG_TARGET_ROOTFS_INITRAMFS y
	for rootfs_option in \
		CONFIG_TARGET_ROOTFS_SQUASHFS \
		CONFIG_TARGET_ROOTFS_EXT4FS \
		CONFIG_TARGET_ROOTFS_UBIFS \
		CONFIG_TARGET_ROOTFS_JFFS2 \
		CONFIG_TARGET_ROOTFS_F2FS \
		CONFIG_TARGET_ROOTFS_TARGZ; do
		set_config_bool "$rootfs_option" n
	done
	set_config_bool CONFIG_PACKAGE_flock y
	set_config_bool CONFIG_PACKAGE_mtd y
	set_config_bool CONFIG_PACKAGE_coreutils-stat y
	set_config_string CONFIG_BINARY_FOLDER "$ISOLATED_OUTPUT"
	(
		cd "$OPENWRT_DIR"
		make defconfig
	)
	grep -Fqx 'CONFIG_TARGET_ROOTFS_INITRAMFS=y' "$OPENWRT_DIR/.config" || \
		die 'initramfs rootfs was not enabled'
	if grep -Eq '^CONFIG_TARGET_ROOTFS_(SQUASHFS|EXT4FS|UBIFS|JFFS2|F2FS|TARGZ)=y$' \
		"$OPENWRT_DIR/.config"; then
		die 'a flashable rootfs format remained enabled'
	fi
	for required_config in CONFIG_PACKAGE_flock=y CONFIG_PACKAGE_mtd=y CONFIG_PACKAGE_coreutils-stat=y; do
		grep -Fqx "$required_config" "$OPENWRT_DIR/.config" || \
			die "maintenance dependency was not selected: $required_config"
	done
	grep -Fqx "CONFIG_BINARY_FOLDER=\"$ISOLATED_OUTPUT\"" "$OPENWRT_DIR/.config" || \
		die 'isolated binary folder was not preserved by defconfig'
	verify_overlay_staging

	local jobs="${CR6608_CRASHLOG_JOBS:-$(nproc)}"
	case "$jobs" in ''|*[!0-9]*) die 'CR6608_CRASHLOG_JOBS must be a positive integer' ;; esac
	[ "$jobs" -gt 0 ] || die 'CR6608_CRASHLOG_JOBS must be greater than zero'
	say "Building isolated crash-log maintenance initramfs with $jobs job(s)"
	(
		cd "$OPENWRT_DIR"
		make -j"$jobs" V=s CONFIG_BINARY_FOLDER="$ISOLATED_OUTPUT"
	) 2>&1 | tee "$WORK_DIR/build.log"

	snapshot_bin_tree "$OPENWRT_DIR/bin" "$WORK_DIR/default-bin.after" || \
		die 'could not rescan the normal binary tree'
	cmp -s "$WORK_DIR/default-bin.before" "$WORK_DIR/default-bin.after" || \
		die 'maintenance build changed the normal binary tree'

	quarantine_flashables "$ISOLATED_OUTPUT" "$QUARANTINE_DIR"
	local initramfs built_root image_sha patch_sha sanitizer_sha marker_sha wifi_sha
	initramfs="$(find_exact_initramfs "$ISOLATED_OUTPUT")"
	verify_initramfs_envelope "$initramfs"
	built_root="$(find_built_root)"
	verify_built_root "$built_root"
	verify_built_dtb
	verify_generated_initramfs_archive "$initramfs"

	cp -- "$initramfs" "$PUBLISH_STAGE/$PUBLISHED_IMAGE"
	chmod 0644 "$PUBLISH_STAGE/$PUBLISHED_IMAGE"
	(
		cd "$PUBLISH_STAGE"
		sha256sum "$PUBLISHED_IMAGE" >"$PUBLISHED_IMAGE.sha256"
		sha256sum -c "$PUBLISHED_IMAGE.sha256" >/dev/null
	)
	image_sha="$(sha256sum "$PUBLISH_STAGE/$PUBLISHED_IMAGE" | awk '{print $1}')"
	patch_sha="$(sha256sum "$DTS_PATCH" | awk '{print $1}')"
	sanitizer_sha="$(sha256sum "$SANITIZER_SOURCE" | awk '{print $1}')"
	marker_sha="$(sha256sum "$MARKER_SOURCE" | awk '{print $1}')"
	wifi_sha="$(sha256sum "$WIFI_DISABLE_SOURCE" | awk '{print $1}')"
	destroy_private_generated_output
	{
		printf 'release_status=maintenance_initramfs_ram_boot_only\n'
		printf 'boot_policy=ram_boot_only_never_flash\n'
		printf 'published_binary_count=1\n'
		printf 'flashable_image_publication=none\n'
		printf 'generated_flashables_quarantined_then_deleted=%s\n' "$QUARANTINED_FLASHABLES"
		printf 'partition_policy=crash_log_writable_only_in_dedicated_maintenance_kernel\n'
		printf 'wifi_policy=all_radios_disabled_by_lexically_last_uci_default\n'
		printf 'maintenance_uci_default=%s\n' "$MAINTENANCE_UCI_BASENAME"
		printf 'openwrt_commit=%s\n' "$EXPECTED_OPENWRT_COMMIT"
		printf 'device_profile=%s\n' "$DEVICE_PROFILE"
		printf 'initramfs_image=%s\n' "$PUBLISHED_IMAGE"
		printf 'initramfs_sha256=%s\n' "$image_sha"
		printf 'dts_patch_sha256=%s\n' "$patch_sha"
		printf 'sanitizer_sha256=%s\n' "$sanitizer_sha"
		printf 'marker_sha256=%s\n' "$marker_sha"
		printf 'wifi_disable_sha256=%s\n' "$wifi_sha"
	} >"$PUBLISH_STAGE/build-manifest.txt"
	chmod 0644 "$PUBLISH_STAGE/$PUBLISHED_IMAGE.sha256" \
		"$PUBLISH_STAGE/build-manifest.txt"
	verify_publication_file_set "$PUBLISH_STAGE"

	restore_prepared_tree || die 'failed to restore and clean the prepared normal OpenWrt tree'
	snapshot_bin_tree "$OPENWRT_DIR/bin" "$WORK_DIR/default-bin.restored" || \
		die 'could not verify the restored normal binary tree'
	cmp -s "$WORK_DIR/default-bin.before" "$WORK_DIR/default-bin.restored" || \
		die 'normal binary tree differs after maintenance cleanup'

	[ "$(stat -c '%d:%i' "$PUBLISH_PARENT")" = "$PUBLISH_PARENT_IDENTITY" ] || \
		die 'publication parent identity changed before atomic publication'
	[ ! -e "$PUBLISH_DIR" ] && [ ! -L "$PUBLISH_DIR" ] || \
		die 'publication destination appeared before atomic publication'
	mv -T -- "$PUBLISH_STAGE" "$PUBLISH_DIR"
	verify_publication_file_set "$PUBLISH_DIR"
	cleanup_workdir
	WORK_DIR=''
	trap - EXIT HUP INT TERM
	say "CR6608_CRASHLOG_INITRAMFS_BUILD=PASS"
	say "published=$PUBLISH_DIR/$PUBLISHED_IMAGE"
	say "sha256=$image_sha"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
