#!/bin/sh
# Full-flow mocks for the CR6608 crash-log sanitizer. The production tool is
# rewritten into a temporary root; the mock mtd executable never accesses NAND.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
sanitize_script=${1:-"$source_root/crashlog/cr6608-crashlog-sanitize"}
maintenance_marker="$source_root/crashlog/cr6608-crashlog-maintenance.marker"
dts_patch="$source_root/patches/995-cr6608-crashlog-maintenance-write-gate.patch"

for required_file in "$sanitize_script" "$maintenance_marker" "$dts_patch"; do
	[ -f "$required_file" ] || {
		echo "FAIL: required source file is missing: $required_file" >&2
		exit 1
	}
done

test_dir=$(mktemp -d /tmp/cr6608-crashlog-sanitize-mock.XXXXXX)
case "$test_dir" in
	/tmp/cr6608-crashlog-sanitize-mock.*) ;;
	*) echo "FAIL: unsafe test directory: $test_dir" >&2; exit 1 ;;
esac

cleanup_test() {
	case "$test_dir" in
		/tmp/cr6608-crashlog-sanitize-mock.*) rm -rf -- "$test_dir" ;;
	esac
}
trap cleanup_test EXIT HUP INT TERM

ERASED_SHA256='3b874d3ba46c638fc3094f8e92fb744ca974893873f8885f54e23760f9b6311b'
CONFIRM_TOKEN='CR6608_CRASH_LOG_ERASE_OFF_DEVICE_BACKUP_VERIFIED'

runtime="$test_dir/cr6608-crashlog-sanitize.mock"
sed \
	-e 's/\r$//' \
	-e 's|BOARD_NAME='\''/tmp/sysinfo/board_name'\''|BOARD_NAME="${MOCK_ROOT:?}/tmp/sysinfo/board_name"|' \
	-e 's|PROC_MTD='\''/proc/mtd'\''|PROC_MTD="${MOCK_ROOT:?}/proc/mtd"|' \
	-e 's|SYS_MTD='\''/sys/class/mtd/mtd5'\''|SYS_MTD="${MOCK_ROOT:?}/sys/class/mtd/mtd5"|' \
	-e 's|MTD_CHAR_DEVICE='\''/dev/mtd5'\''|MTD_CHAR_DEVICE="${MOCK_ROOT:?}/dev/mtd5"|' \
	-e 's|MTD_READ_DEVICE='\''/dev/mtd5ro'\''|MTD_READ_DEVICE="${MOCK_ROOT:?}/dev/mtd5ro"|' \
	-e 's|MAINTENANCE_MARKER='\''/etc/cr6608-crashlog-maintenance.marker'\''|MAINTENANCE_MARKER="${MOCK_ROOT:?}/etc/cr6608-crashlog-maintenance.marker"|' \
	-e 's|BACKUP_ATTESTATION='\''/etc/cr6608-crashlog-external-backup.attestation'\''|BACKUP_ATTESTATION="${MOCK_ROOT:?}/etc/cr6608-crashlog-external-backup.attestation"|' \
	-e 's|LOCK_FILE='\''/var/lock/cr6608-crashlog-sanitize.lock'\''|LOCK_FILE="${MOCK_ROOT:?}/var/lock/cr6608-crashlog-sanitize.lock"|' \
	-e 's|\[ -c "$MTD_CHAR_DEVICE" \]|[ -f "$MTD_CHAR_DEVICE" ]|' \
	-e 's|\[ -c "$MTD_READ_DEVICE" \]|[ -f "$MTD_READ_DEVICE" ]|' \
	"$sanitize_script" >"$runtime"
chmod 0700 "$runtime"

mock_bin="$test_dir/mock-bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/stat" <<'EOF'
#!/bin/sh
[ "$1" = -c ] || exit 2
format=$2
path=$3
case "$path" in
	*/cr6608-crashlog-external-backup.attestation)
		owner=${MOCK_ATTEST_OWNER:-0}
		mode=${MOCK_ATTEST_MODE:-600}
		;;
	*/cr6608-crashlog-maintenance.marker)
		owner=${MOCK_MARKER_OWNER:-0}
		mode=${MOCK_MARKER_MODE:-444}
		;;
	*) exit 2 ;;
esac
case "$format" in
	%u) printf '%s\n' "$owner" ;;
	%a) printf '%s\n' "$mode" ;;
	*) exit 2 ;;
esac
EOF

cat >"$mock_bin/iw" <<'EOF'
#!/bin/sh
[ "$*" = dev ] || exit 2
[ "${MOCK_WIFI_ACTIVE:-0}" != 1 ] || printf '%s\n' 'Interface phy0-ap0'
EOF

cat >"$mock_bin/ip" <<'EOF'
#!/bin/sh
case "$*" in
	'neigh show '*" dev br-lan")
		[ "${MOCK_NO_NEIGHBOR:-0}" != 1 ] || exit 0
		peer=$3
		printf '%s lladdr aa:bb:cc:dd:ee:ff REACHABLE\n' "$peer"
		;;
	'-o link show lan1')
		if [ "${MOCK_NO_CARRIER:-0}" = 1 ]; then
			printf '%s\n' '7: lan1: <BROADCAST,MULTICAST,UP> mtu 1500'
		else
			printf '%s\n' '7: lan1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500'
		fi
		;;
	*) exit 2 ;;
esac
EOF

cat >"$mock_bin/bridge" <<'EOF'
#!/bin/sh
[ "$*" = 'fdb show br br-lan' ] || exit 2
port=${MOCK_FDB_PORT:-lan1}
printf 'aa:bb:cc:dd:ee:ff dev %s master br-lan\n' "$port"
EOF

cat >"$mock_bin/flock" <<'EOF'
#!/bin/sh
[ "$*" = '-n 9' ] || exit 2
[ "${MOCK_LOCK_HELD:-0}" != 1 ]
EOF

cat >"$mock_bin/mtd" <<'EOF'
#!/bin/sh
printf 'mtd %s\n' "$*" >>"${MOCK_LOG:?}"
[ "$*" = 'erase /dev/mtd5' ] || exit 97
[ "${MOCK_ERASE_FAIL:-0}" != 1 ] || exit 1
[ "${MOCK_READBACK_FAIL:-0}" = 1 ] && exit 0
dd if=/dev/zero bs=262144 count=1 status=none | tr '\000' '\377' >"${MOCK_ROOT:?}/dev/mtd5ro"
EOF

cat >"$mock_bin/sync" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$mock_bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

chmod 0700 "$mock_bin"/*
PATH="$mock_bin:$PATH"
export PATH

unset_controls() {
	unset MOCK_ATTEST_OWNER MOCK_ATTEST_MODE MOCK_MARKER_OWNER MOCK_MARKER_MODE
	unset MOCK_WIFI_ACTIVE MOCK_NO_NEIGHBOR MOCK_NO_CARRIER MOCK_FDB_PORT
	unset MOCK_LOCK_HELD MOCK_ERASE_FAIL MOCK_READBACK_FAIL
}

make_preimage() {
	dd if=/dev/zero bs=262144 count=1 status=none >"$MOCK_ROOT/dev/mtd5ro"
	printf 'sensitive-crash-residue\n' | dd of="$MOCK_ROOT/dev/mtd5ro" conv=notrunc status=none
}

make_erased_image() {
	dd if=/dev/zero bs=262144 count=1 status=none | tr '\000' '\377' >"$MOCK_ROOT/dev/mtd5ro"
}

write_attestation() {
	pre_hash=$(sha256sum "$MOCK_ROOT/dev/mtd5ro" | awk 'NR == 1 { print $1 }')
	cat >"$MOCK_ROOT/etc/cr6608-crashlog-external-backup.attestation" <<EOF
CR6608_CRASHLOG_EXTERNAL_BACKUP_ATTESTATION=1
BACKUP_STORED_OFF_DEVICE=1
CRASH_LOG_PRE_ERASE_SHA256=$pre_hash
EXTERNAL_BACKUP_SHA256=$pre_hash
EXTERNAL_BACKUP_VERIFIED=1
EOF
}

new_fixture() {
	name=$1
	unset_controls
	MOCK_ROOT="$test_dir/case-$name"
	MOCK_LOG="$MOCK_ROOT/mtd.log"
	export MOCK_ROOT MOCK_LOG
	mkdir -p \
		"$MOCK_ROOT/tmp/sysinfo" "$MOCK_ROOT/proc" \
		"$MOCK_ROOT/sys/class/mtd/mtd5" "$MOCK_ROOT/dev" \
		"$MOCK_ROOT/etc" "$MOCK_ROOT/var/lock"
	: >"$MOCK_LOG"
	: >"$MOCK_ROOT/dev/mtd5"
	printf '%s\n' 'xiaomi,mi-router-cr6608' >"$MOCK_ROOT/tmp/sysinfo/board_name"
	printf '%s\n' 'mtd5: 00040000 00020000 "crash_log"' >"$MOCK_ROOT/proc/mtd"
	printf '%s\n' crash_log >"$MOCK_ROOT/sys/class/mtd/mtd5/name"
	printf '%s\n' 262144 >"$MOCK_ROOT/sys/class/mtd/mtd5/size"
	printf '%s\n' 131072 >"$MOCK_ROOT/sys/class/mtd/mtd5/erasesize"
	printf '%s\n' nand >"$MOCK_ROOT/sys/class/mtd/mtd5/type"
	printf '%s\n' 2048 >"$MOCK_ROOT/sys/class/mtd/mtd5/writesize"
	printf '%s\n' 0x400 >"$MOCK_ROOT/sys/class/mtd/mtd5/flags"
	printf '%s\n' 0 >"$MOCK_ROOT/sys/class/mtd/mtd5/bad_blocks"
	printf '%s\n' 0 >"$MOCK_ROOT/sys/class/mtd/mtd5/ecc_failures"
	printf '%s\n' 0 >"$MOCK_ROOT/sys/class/mtd/mtd5/corrected_bits"
	cp "$maintenance_marker" "$MOCK_ROOT/etc/cr6608-crashlog-maintenance.marker"
	make_preimage
	write_attestation
	SSH_CONNECTION='192.168.1.20 49152 192.168.1.1 22'
	export SSH_CONNECTION
}

case_count=0
pass_count=0
last_output=''
last_rc=0

run_sanitize() {
	case_count=$((case_count + 1))
	last_output="$MOCK_ROOT/output.txt"
	set +e
	sh "$runtime" "$@" >"$last_output" 2>&1
	last_rc=$?
	set -e
}

pass_case() {
	pass_count=$((pass_count + 1))
	printf 'PASS %s\n' "$1"
}

expect_success() {
	name=$1
	pattern=$2
	[ "$last_rc" -eq 0 ] || {
		echo "FAIL $name: expected rc=0, got rc=$last_rc" >&2
		sed -n '1,120p' "$last_output" >&2
		exit 1
	}
	grep -Fq "$pattern" "$last_output" || {
		echo "FAIL $name: missing success output: $pattern" >&2
		sed -n '1,120p' "$last_output" >&2
		exit 1
	}
	pass_case "$name"
}

expect_refusal() {
	name=$1
	pattern=$2
	[ "$last_rc" -ne 0 ] || {
		echo "FAIL $name: expected a refusal" >&2
		sed -n '1,120p' "$last_output" >&2
		exit 1
	}
	grep -Fq "$pattern" "$last_output" || {
		echo "FAIL $name: missing refusal output: $pattern" >&2
		sed -n '1,120p' "$last_output" >&2
		exit 1
	}
	pass_case "$name"
}

expect_no_erase() {
	name=$1
	[ ! -s "$MOCK_LOG" ] || {
		echo "FAIL $name: destructive command ran unexpectedly" >&2
		cat "$MOCK_LOG" >&2
		exit 1
	}
}

expect_one_exact_erase() {
	name=$1
	[ "$(wc -l <"$MOCK_LOG" | tr -d '[:space:]')" = 1 ] || {
		echo "FAIL $name: expected exactly one mtd invocation" >&2
		cat "$MOCK_LOG" >&2
		exit 1
	}
	grep -Fqx 'mtd erase /dev/mtd5' "$MOCK_LOG" || {
		echo "FAIL $name: mtd invocation target or verb changed" >&2
		cat "$MOCK_LOG" >&2
		exit 1
	}
}

new_fixture success
run_sanitize erase "$CONFIRM_TOKEN"
expect_success success 'CRASH_LOG_SANITIZE=PASS already_erased=0'
expect_one_exact_erase success
[ "$(sha256sum "$MOCK_ROOT/dev/mtd5ro" | awk 'NR == 1 { print $1 }')" = "$ERASED_SHA256" ] || {
	echo 'FAIL success: readback is not the exact all-FF image' >&2
	exit 1
}

new_fixture idempotent
make_erased_image
rm -f -- "$MOCK_ROOT/etc/cr6608-crashlog-external-backup.attestation"
run_sanitize erase "$CONFIRM_TOKEN"
expect_success idempotent 'CRASH_LOG_SANITIZE=PASS already_erased=1'
expect_no_erase idempotent

new_fixture wrong-board
printf '%s\n' 'xiaomi,other-router' >"$MOCK_ROOT/tmp/sysinfo/board_name"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal wrong-board 'expected board xiaomi,mi-router-cr6608'
expect_no_erase wrong-board

new_fixture wrong-label
printf '%s\n' wrong_label >"$MOCK_ROOT/sys/class/mtd/mtd5/name"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal wrong-label 'MTD label mismatch'
expect_no_erase wrong-label

new_fixture wrong-index
printf '%s\n' 'mtdX: 00040000 00020000 "crash_log"' >"$MOCK_ROOT/proc/mtd"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal wrong-index 'not the exact expected MTD index and geometry'
expect_no_erase wrong-index

new_fixture wrong-geometry
printf '%s\n' 262145 >"$MOCK_ROOT/sys/class/mtd/mtd5/size"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal wrong-geometry 'crash_log size mismatch'
expect_no_erase wrong-geometry

new_fixture read-only
printf '%s\n' 0x0 >"$MOCK_ROOT/sys/class/mtd/mtd5/flags"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal read-only 'crash_log is kernel read-only'
expect_no_erase read-only

new_fixture bad-block
printf '%s\n' 1 >"$MOCK_ROOT/sys/class/mtd/mtd5/bad_blocks"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal bad-block 'crash_log has bad block(s)'
expect_no_erase bad-block

new_fixture ecc-failure
printf '%s\n' 1 >"$MOCK_ROOT/sys/class/mtd/mtd5/ecc_failures"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal ecc-failure 'uncorrectable ECC failure(s)'
expect_no_erase ecc-failure

new_fixture corrected-bits
printf '%s\n' 1 >"$MOCK_ROOT/sys/class/mtd/mtd5/corrected_bits"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal corrected-bits 'corrected-bit activity'
expect_no_erase corrected-bits

new_fixture missing-marker
rm -f -- "$MOCK_ROOT/etc/cr6608-crashlog-maintenance.marker"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal missing-marker 'required root-owned file is missing'
expect_no_erase missing-marker

new_fixture marker-hash
printf '%s\n' tampered >>"$MOCK_ROOT/etc/cr6608-crashlog-maintenance.marker"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal marker-hash 'maintenance-image marker hash mismatch'
expect_no_erase marker-hash

new_fixture missing-attestation
rm -f -- "$MOCK_ROOT/etc/cr6608-crashlog-external-backup.attestation"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal missing-attestation 'required root-owned file is missing'
expect_no_erase missing-attestation

new_fixture attestation-owner
MOCK_ATTEST_OWNER=1000
export MOCK_ATTEST_OWNER
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal attestation-owner 'file is not owned by root'
expect_no_erase attestation-owner

new_fixture attestation-mode
MOCK_ATTEST_MODE=644
export MOCK_ATTEST_MODE
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal attestation-mode 'file permissions are not root-only'
expect_no_erase attestation-mode

new_fixture attestation-hash
sed -i 's/^EXTERNAL_BACKUP_SHA256=.*/EXTERNAL_BACKUP_SHA256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff/' \
	"$MOCK_ROOT/etc/cr6608-crashlog-external-backup.attestation"
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal attestation-hash 'attested external-backup hash does not match'
expect_no_erase attestation-hash

new_fixture missing-ssh
unset SSH_CONNECTION
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal missing-ssh 'a wired SSH maintenance session is required'
expect_no_erase missing-ssh

new_fixture wifi-active
MOCK_WIFI_ACTIVE=1
export MOCK_WIFI_ACTIVE
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal wifi-active 'a Wi-Fi interface remains active'
expect_no_erase wifi-active

new_fixture wireless-peer
MOCK_FDB_PORT=phy0-ap0
export MOCK_FDB_PORT
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal wireless-peer 'not learned on a physical LAN port'
expect_no_erase wireless-peer

new_fixture lock-held
MOCK_LOCK_HELD=1
export MOCK_LOCK_HELD
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal lock-held 'another crash-log transaction is already running'
expect_no_erase lock-held

new_fixture confirmation
run_sanitize erase WRONG_TOKEN
expect_refusal confirmation 'confirmation token mismatch'
expect_no_erase confirmation

new_fixture erase-failure
MOCK_ERASE_FAIL=1
export MOCK_ERASE_FAIL
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal erase-failure 'MTD erase command failed'
expect_one_exact_erase erase-failure

new_fixture readback-failure
MOCK_READBACK_FAIL=1
export MOCK_READBACK_FAIL
run_sanitize erase "$CONFIRM_TOKEN"
expect_refusal readback-failure 'post-erase all-FF hash mismatch'
expect_one_exact_erase readback-failure

# Static scope gates: a single destructive command, a CR6608-only override,
# and no shared-family removal of the read-only property.
[ "$(grep -Ec '^[[:space:]]*mtd[[:space:]]+erase[[:space:]]+\"\$MTD_ERASE_ARGUMENT\"' "$sanitize_script")" = 1 ] || {
	echo 'FAIL static-scope: sanitizer must contain exactly one mtd erase command' >&2
	exit 1
}
grep -Fq 'crash_log: partition@1c0000 {' "$dts_patch" || {
	echo 'FAIL static-scope: shared partition node is not labelled' >&2
	exit 1
}
grep -Fq '&crash_log {' "$dts_patch" || {
	echo 'FAIL static-scope: device-specific override is missing' >&2
	exit 1
}
[ "$(grep -Fc '/delete-property/ read-only;' "$dts_patch")" = 1 ] || {
	echo 'FAIL static-scope: patch must delete exactly one read-only property' >&2
	exit 1
}
case_count=$((case_count + 1))
pass_case static-scope

[ "$pass_count" -eq "$case_count" ] || {
	echo "FAIL: pass_count=$pass_count case_count=$case_count" >&2
	exit 1
}
printf 'CR6608_CRASHLOG_SANITIZE_MOCK_TESTS=PASS cases=%s nand_real_writes=0\n' "$pass_count"
