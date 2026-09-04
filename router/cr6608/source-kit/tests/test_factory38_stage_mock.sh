#!/bin/sh
# Full-flow mock tests for cr6608-factory38-stage.
#
# The test rewrites only a temporary copy of the stage tool so that absolute
# OpenWrt paths point into MOCK_ROOT and the MTD character-device assertion
# accepts a regular mock file. flash_erase/nandwrite never touch a real device.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stage_script=${1:-"$script_dir/cr6608-factory38-stage"}
[ -f "$stage_script" ] || {
	echo "FAIL: stage script not found: $stage_script" >&2
	exit 1
}

test_dir=$(mktemp -d /tmp/cr6608-factory38-stage-mock.XXXXXX)
case "$test_dir" in
	/tmp/cr6608-factory38-stage-mock.*) ;;
	*) echo "FAIL: unsafe test directory: $test_dir" >&2; exit 1 ;;
esac

cleanup_test() {
	case "$test_dir" in
		/tmp/cr6608-factory38-stage-mock.*) rm -rf -- "$test_dir" ;;
	esac
}
trap cleanup_test EXIT HUP INT TERM

ORIGINAL_SHA256='aca3a3b012d96972466e7492e150bb2e00ba24f9f43201912db0223a32c98439'
FACTORY38_SHA256='b6a775087df306c21c70c29520c27fd5ea3e62dcfb8a945b340304895b038eb0'
ORIGINAL_BLOCK0_SHA256='b72eca62ecbaff9a93176ec5e9912e2ee9d6404c1c9f6005f4e8b66bc9bde224'
FACTORY38_BLOCK0_SHA256='950b682023077bab5e2e35212e77b7e8d6bcf00f2249f922d38bdad0bed66aab'
CONFIRM_TOKEN='CR6608_FACTORY38_I_ACCEPT_NAND_AND_RF_RISK'
RECOVERY_TEXT='CR6608_COM8_PBBOOT_RECOVERY_PATH_VERIFIED original_sha256=aca3a3b012d96972466e7492e150bb2e00ba24f9f43201912db0223a32c98439 original_crc32=963cdfeb'

runtime="$test_dir/cr6608-factory38-stage.mock"
sed \
	-e 's/\r$//' \
	-e 's|PERSISTENT_BACKUP='\''/root/cr6608-factory-original-aca3a3b0.bin'\''|PERSISTENT_BACKUP="${MOCK_ROOT:?}/root/cr6608-factory-original-aca3a3b0.bin"|' \
	-e 's|PERSISTENT_BLOCK0='\''/root/cr6608-factory-original-block0-b72eca62.bin'\''|PERSISTENT_BLOCK0="${MOCK_ROOT:?}/root/cr6608-factory-original-block0-b72eca62.bin"|' \
	-e 's|RECOVERY_ATTESTATION='\''/root/cr6608-com8-pbboot-recovery-verified.txt'\''|RECOVERY_ATTESTATION="${MOCK_ROOT:?}/root/cr6608-com8-pbboot-recovery-verified.txt"|' \
	-e 's|MAINTENANCE_MARKER='\''/etc/cr6608-factory38-writegate.marker'\''|MAINTENANCE_MARKER="${MOCK_ROOT:?}/etc/cr6608-factory38-writegate.marker"|' \
	-e 's|LOCK_FILE='\''/var/lock/cr6608-factory38-stage.lock'\''|LOCK_FILE="${MOCK_ROOT:?}/var/lock/cr6608-factory38-stage.lock"|' \
	-e 's|/tmp/sysinfo/board_name|${MOCK_ROOT:?}/tmp/sysinfo/board_name|g' \
	-e 's| /proc/mtd| "${MOCK_ROOT:?}/proc/mtd"|' \
	-e 's|MTD_DEV="/dev/$MTD_NAME"|MTD_DEV="${MOCK_ROOT:?}/dev/$MTD_NAME"|' \
	-e 's|SYS_MTD="/sys/class/mtd/$MTD_NAME"|SYS_MTD="${MOCK_ROOT:?}/sys/class/mtd/$MTD_NAME"|' \
	-e 's|\[ -c "$MTD_DEV" \]|[ -f "$MTD_DEV" ]|' \
	-e 's|preserve_file='\''/etc/sysupgrade.conf'\''|preserve_file="${MOCK_ROOT:?}/etc/sysupgrade.conf"|' \
	-e 's|/tmp/cr6608-factory38-block0\.|${MOCK_ROOT:?}/tmp/cr6608-factory38-block0.|g' \
	"$stage_script" >"$runtime"
chmod 0700 "$runtime"

functions_file="$test_dir/functions.sh"
sed '/^case "${1:-}" in/,$d' "$runtime" >"$functions_file"

mock_bin="$test_dir/mock-bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/sha256sum" <<'EOF'
#!/bin/sh
original='aca3a3b012d96972466e7492e150bb2e00ba24f9f43201912db0223a32c98439'
factory38='b6a775087df306c21c70c29520c27fd5ea3e62dcfb8a945b340304895b038eb0'
original_block='b72eca62ecbaff9a93176ec5e9912e2ee9d6404c1c9f6005f4e8b66bc9bde224'
factory38_block='950b682023077bab5e2e35212e77b7e8d6bcf00f2249f922d38bdad0bed66aab'
maintenance_marker='f6d3659a2151a14a652ef043e6886d6b2c9882cef7be9dd808da6d7d5b6cb441'
bad='0000000000000000000000000000000000000000000000000000000000000000'

if [ "$#" -eq 0 ]; then
	IFS= read -r marker || marker=''
	name='-'
else
	name=$1
	if [ "$name" = "${MOCK_ROOT:?}/dev/mtd0" ]; then
		marker=$(cat "${MOCK_STATE:?}")
	else
		marker=$(head -n 1 "$name" 2>/dev/null || true)
	fi
fi

case "$marker" in
	ORIGINAL|FULL_ORIGINAL) sum=$original ;;
	FACTORY38|FULL_FACTORY38) sum=$factory38 ;;
	BLOCK_ORIGINAL) sum=$original_block ;;
	BLOCK_FACTORY38) sum=$factory38_block ;;
	CR6608_FACTORY38_WRITE_ENABLED_RECOVERY_IMAGE=1) sum=$maintenance_marker ;;
	*) sum=$bad ;;
esac
printf '%s  %s\n' "$sum" "$name"
EOF

cat >"$mock_bin/dd" <<'EOF'
#!/bin/sh
input=''
output=''
count=''
for arg in "$@"; do
	case "$arg" in
		if=*) input=${arg#if=} ;;
		of=*) output=${arg#of=} ;;
		count=*) count=${arg#count=} ;;
	esac
done
[ "$input" = "${MOCK_ROOT:?}/dev/mtd0" ] || exit 2
state=$(cat "${MOCK_STATE:?}")
case "$state" in
	ORIGINAL) block_marker=BLOCK_ORIGINAL; full_marker=FULL_ORIGINAL ;;
	FACTORY38) block_marker=BLOCK_FACTORY38; full_marker=FULL_FACTORY38 ;;
	*) block_marker=BLOCK_MISMATCH; full_marker=FULL_MISMATCH ;;
esac
if [ -z "$output" ]; then
	printf '%s\n' "$block_marker"
	exit 0
fi
if [ "$count" = 1 ]; then
	size=131072
	marker=$block_marker
else
	size=524288
	marker=$full_marker
fi
: >"$output"
truncate -s "$size" "$output"
printf '%s\n' "$marker" | /usr/bin/dd of="$output" conv=notrunc status=none
EOF

cat >"$mock_bin/flash_erase" <<'EOF'
#!/bin/sh
printf 'flash_erase %s\n' "$*" >>"${MOCK_LOG:?}"
[ "${MOCK_FLASH_ERASE_FAIL:-0}" != 1 ] || exit 1
printf '%s\n' ERASED >"${MOCK_STATE:?}"
EOF

cat >"$mock_bin/nandwrite" <<'EOF'
#!/bin/sh
source_file=''
for arg in "$@"; do source_file=$arg; done
marker=$(head -n 1 "$source_file" 2>/dev/null || true)
printf 'nandwrite %s\n' "$marker" >>"${MOCK_LOG:?}"
case "$marker" in
	BLOCK_FACTORY38)
		[ "${MOCK_CANDIDATE_WRITE_FAIL:-0}" != 1 ] || exit 1
		if [ "${MOCK_CANDIDATE_READBACK_MISMATCH:-0}" = 1 ]; then
			printf '%s\n' MISMATCH >"${MOCK_STATE:?}"
		else
			printf '%s\n' FACTORY38 >"${MOCK_STATE:?}"
		fi
		;;
	BLOCK_ORIGINAL)
		[ "${MOCK_RESTORE_WRITE_FAIL:-0}" != 1 ] || exit 1
		printf '%s\n' ORIGINAL >"${MOCK_STATE:?}"
		;;
	*) exit 2 ;;
esac
EOF

cat >"$mock_bin/wifi" <<'EOF'
#!/bin/sh
printf 'wifi %s\n' "$*" >>"${MOCK_LOG:?}"
[ "$*" = down ] || exit 2
[ "${MOCK_WIFI_DOWN_FAIL:-0}" != 1 ] || exit 1
EOF

cat >"$mock_bin/ubus" <<'EOF'
#!/bin/sh
[ "$*" = 'call network.wireless status' ] || exit 2
printf '%s\n' '{"radio0":{"up":false}}'
EOF

cat >"$mock_bin/jsonfilter" <<'EOF'
#!/bin/sh
cat >/dev/null
[ "${MOCK_INVALID_JSON:-0}" != 1 ]
EOF

cat >"$mock_bin/iw" <<'EOF'
#!/bin/sh
[ "$*" = dev ] || exit 2
[ "${MOCK_WIFI_INTERFACE_REMAINS:-0}" != 1 ] || printf '%s\n' 'Interface wlan0'
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
	'-o link show')
		[ "${MOCK_WIRELESS_LINK_UP:-0}" != 1 ] || \
			printf '%s\n' '9: phy0-ap0: <BROADCAST,UP,LOWER_UP> mtu 1500'
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
printf 'flock %s\n' "$*" >>"${MOCK_LOG:?}"
[ "${MOCK_LOCK_HELD:-0}" != 1 ]
EOF

cat >"$mock_bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$mock_bin/sync" <<'EOF'
#!/bin/sh
exit 0
EOF

chmod 0700 "$mock_bin"/*
system_path=$PATH
PATH="$mock_bin:$PATH"
export PATH

make_image() {
	image=$1
	size=$2
	marker=$3
	: >"$image"
	truncate -s "$size" "$image"
	printf '%s\n' "$marker" | /usr/bin/dd of="$image" conv=notrunc status=none
}

unset_mock_controls() {
	unset MOCK_FLASH_ERASE_FAIL MOCK_CANDIDATE_WRITE_FAIL
	unset MOCK_CANDIDATE_READBACK_MISMATCH MOCK_RESTORE_WRITE_FAIL
	unset MOCK_WIFI_DOWN_FAIL MOCK_INVALID_JSON MOCK_WIFI_INTERFACE_REMAINS
	unset MOCK_NO_NEIGHBOR MOCK_NO_CARRIER MOCK_WIRELESS_LINK_UP
	unset MOCK_FDB_PORT MOCK_LOCK_HELD
}

new_fixture() {
	name=$1
	initial_state=$2
	unset_mock_controls
	MOCK_ROOT="$test_dir/case-$name"
	MOCK_STATE="$MOCK_ROOT/state"
	MOCK_LOG="$MOCK_ROOT/mock.log"
	export MOCK_ROOT MOCK_STATE MOCK_LOG
	mkdir -p \
		"$MOCK_ROOT/root" "$MOCK_ROOT/var/lock" \
		"$MOCK_ROOT/tmp/sysinfo" "$MOCK_ROOT/proc" \
		"$MOCK_ROOT/dev" "$MOCK_ROOT/sys/class/mtd/mtd0" \
		"$MOCK_ROOT/etc" "$MOCK_ROOT/inputs"
	printf '%s\n' "$initial_state" >"$MOCK_STATE"
	: >"$MOCK_LOG"
	: >"$MOCK_ROOT/dev/mtd0"
	: >"$MOCK_ROOT/etc/sysupgrade.conf"
	printf '%s\n' 'xiaomi,mi-router-cr6608' >"$MOCK_ROOT/tmp/sysinfo/board_name"
	printf '%s\n' 'mtd0: 00080000 00020000 "Factory"' >"$MOCK_ROOT/proc/mtd"
	printf '%s\n' Factory >"$MOCK_ROOT/sys/class/mtd/mtd0/name"
	printf '%s\n' 524288 >"$MOCK_ROOT/sys/class/mtd/mtd0/size"
	printf '%s\n' 131072 >"$MOCK_ROOT/sys/class/mtd/mtd0/erasesize"
	printf '%s\n' nand >"$MOCK_ROOT/sys/class/mtd/mtd0/type"
	printf '%s\n' 2048 >"$MOCK_ROOT/sys/class/mtd/mtd0/writesize"
	printf '%s\n' 0x400 >"$MOCK_ROOT/sys/class/mtd/mtd0/flags"
	printf '%s\n' 0 >"$MOCK_ROOT/sys/class/mtd/mtd0/bad_blocks"
	printf '%s\n' 0 >"$MOCK_ROOT/sys/class/mtd/mtd0/ecc_failures"
	printf '%s\n' 0 >"$MOCK_ROOT/sys/class/mtd/mtd0/corrected_bits"
	printf '%s\n' "$RECOVERY_TEXT" >"$MOCK_ROOT/root/cr6608-com8-pbboot-recovery-verified.txt"
	cat >"$MOCK_ROOT/etc/cr6608-factory38-writegate.marker" <<'EOF'
CR6608_FACTORY38_WRITE_ENABLED_RECOVERY_IMAGE=1
FACTORY_PARTITION_WRITABLE_WHILE_THIS_KERNEL_IS_RUNNING=1
FACTORY38_WRITER_REQUIRES_COM8_PBBOOT_ATTESTATION=1
WIFI_MUST_REMAIN_DOWN_DURING_FACTORY_TRANSACTION=1
REBOOT_TO_READ_ONLY_FACTORY_KERNEL_AFTER_TRANSACTION=1
EOF
	make_image "$MOCK_ROOT/inputs/factory38.block0" 131072 BLOCK_FACTORY38
	make_image "$MOCK_ROOT/inputs/original.block0" 131072 BLOCK_ORIGINAL
	SSH_CONNECTION='192.168.1.20 49152 192.168.1.1 22'
	export SSH_CONNECTION
}

case_count=0
pass_count=0
last_output=''
last_rc=0

run_stage() {
	case_count=$((case_count + 1))
	last_output="$MOCK_ROOT/output.txt"
	set +e
	"$runtime" "$@" >"$last_output" 2>&1
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
		sed -n '1,160p' "$last_output" >&2
		exit 1
	}
	grep -Fq "$pattern" "$last_output" || {
		echo "FAIL $name: missing output: $pattern" >&2
		sed -n '1,160p' "$last_output" >&2
		exit 1
	}
	pass_case "$name"
}

expect_refusal() {
	name=$1
	pattern=$2
	[ "$last_rc" -ne 0 ] || {
		echo "FAIL $name: expected nonzero rc" >&2
		sed -n '1,160p' "$last_output" >&2
		exit 1
	}
	grep -Fq "$pattern" "$last_output" || {
		echo "FAIL $name: missing refusal: $pattern" >&2
		sed -n '1,160p' "$last_output" >&2
		exit 1
	}
	pass_case "$name"
}

# Successful apply, including persistent backup and sysupgrade preservation.
new_fixture happy-apply ORIGINAL
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_success happy-apply 'FACTORY38_WRITE=PASS'
[ "$(cat "$MOCK_STATE")" = FACTORY38 ] || {
	echo 'FAIL happy-apply: final MTD state is not FACTORY38' >&2; exit 1;
}
[ "$(wc -c <"$MOCK_ROOT/root/cr6608-factory-original-aca3a3b0.bin" | tr -d ' ')" = 524288 ] || {
	echo 'FAIL happy-apply: full backup size mismatch' >&2; exit 1;
}
[ "$(wc -c <"$MOCK_ROOT/root/cr6608-factory-original-block0-b72eca62.bin" | tr -d ' ')" = 131072 ] || {
	echo 'FAIL happy-apply: block backup size mismatch' >&2; exit 1;
}
[ "$(grep -c '^/root/cr6608-' "$MOCK_ROOT/etc/sysupgrade.conf" || true)" -eq 0 ] || {
	echo 'FAIL happy-apply: preservation paths escaped the mock root' >&2; exit 1;
}
[ "$(grep -c "^$MOCK_ROOT/root/cr6608-" "$MOCK_ROOT/etc/sysupgrade.conf")" -eq 3 ] || {
	echo 'FAIL happy-apply: preservation list is incomplete' >&2; exit 1;
}

# Candidate file hash and size must both be exact.
new_fixture bad-hash ORIGINAL
make_image "$MOCK_ROOT/inputs/bad-hash.block0" 131072 BLOCK_BAD
run_stage apply "$MOCK_ROOT/inputs/bad-hash.block0" "$CONFIRM_TOKEN"
expect_refusal bad-hash 'input eraseblock file failed size/hash verification'
[ "$(cat "$MOCK_STATE")" = ORIGINAL ] || { echo 'FAIL bad-hash changed MTD state' >&2; exit 1; }

new_fixture bad-size ORIGINAL
make_image "$MOCK_ROOT/inputs/bad-size.block0" 4096 BLOCK_FACTORY38
run_stage apply "$MOCK_ROOT/inputs/bad-size.block0" "$CONFIRM_TOKEN"
expect_refusal bad-size 'input eraseblock file failed size/hash verification'
[ "$(cat "$MOCK_STATE")" = ORIGINAL ] || { echo 'FAIL bad-size changed MTD state' >&2; exit 1; }

# Board, geometry, writable bit, NAND health, recovery and wired-LAN gates.
new_fixture wrong-board ORIGINAL
printf '%s\n' 'xiaomi,other-router' >"$MOCK_ROOT/tmp/sysinfo/board_name"
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal wrong-board 'expected xiaomi,mi-router-cr6608'

new_fixture wrong-geometry ORIGINAL
printf '%s\n' 262144 >"$MOCK_ROOT/sys/class/mtd/mtd0/erasesize"
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal wrong-geometry 'Factory erase size mismatch'

new_fixture read-only ORIGINAL
printf '%s\n' 0x0 >"$MOCK_ROOT/sys/class/mtd/mtd0/flags"
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal read-only 'Factory is kernel read-only'

new_fixture unhealthy-nand ORIGINAL
printf '%s\n' 1 >"$MOCK_ROOT/sys/class/mtd/mtd0/ecc_failures"
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal unhealthy-nand 'uncorrectable ECC failure(s)'

new_fixture missing-maintenance-marker ORIGINAL
rm -f -- "$MOCK_ROOT/etc/cr6608-factory38-writegate.marker"
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal missing-maintenance-marker 'maintenance-image marker is missing'

new_fixture missing-recovery ORIGINAL
rm -f -- "$MOCK_ROOT/root/cr6608-com8-pbboot-recovery-verified.txt"
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal missing-recovery 'COM8/PB-Boot recovery attestation is missing'

new_fixture no-physical-lan ORIGINAL
MOCK_FDB_PORT=wlan0
export MOCK_FDB_PORT
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal no-physical-lan 'is not learned on a physical LAN port'
[ "$(cat "$MOCK_STATE")" = ORIGINAL ] || { echo 'FAIL no-physical-lan changed MTD state' >&2; exit 1; }

# A candidate readback mismatch must automatically restore the original block.
new_fixture readback-rollback ORIGINAL
MOCK_CANDIDATE_READBACK_MISMATCH=1
export MOCK_CANDIDATE_READBACK_MISMATCH
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal readback-rollback 'Factory-38 readback hash mismatch'
[ "$(cat "$MOCK_STATE")" = ORIGINAL ] || {
	echo 'FAIL readback-rollback: original state was not restored' >&2; exit 1;
}
grep -Fq 'RESTORE: original Factory hash verified' "$last_output" || {
	echo 'FAIL readback-rollback: verified restoration was not reported' >&2; exit 1;
}
[ "$(grep -c '^nandwrite BLOCK_ORIGINAL$' "$MOCK_LOG")" -eq 1 ] || {
	echo 'FAIL readback-rollback: original block was not written exactly once' >&2; exit 1;
}

# Explicit restore succeeds from Factory-38.
new_fixture restore-success FACTORY38
run_stage restore "$MOCK_ROOT/inputs/original.block0" "$CONFIRM_TOKEN"
expect_success restore-success 'FACTORY_RESTORE=PASS'
[ "$(cat "$MOCK_STATE")" = ORIGINAL ] || {
	echo 'FAIL restore-success: final state is not ORIGINAL' >&2; exit 1;
}

# If both the restore and its exit-guard retry fail, rc must remain nonzero.
new_fixture restore-failure FACTORY38
MOCK_RESTORE_WRITE_FAIL=1
export MOCK_RESTORE_WRITE_FAIL
run_stage restore "$MOCK_ROOT/inputs/original.block0" "$CONFIRM_TOKEN"
expect_refusal restore-failure 'FATAL: retry of original-Factory restoration failed'
[ "$(cat "$MOCK_STATE")" != ORIGINAL ] || {
	echo 'FAIL restore-failure: mock unexpectedly reports an original readback' >&2; exit 1;
}
[ "$(grep -c '^nandwrite BLOCK_ORIGINAL$' "$MOCK_LOG")" -eq 2 ] || {
	echo 'FAIL restore-failure: expected initial attempt plus one guard retry' >&2; exit 1;
}

# Signal guards are exercised directly so the expected 128+signal rc is stable
# across MSYS process boundaries, pipelines, and nohup execution.
signal_log="$test_dir/apply-signal.log"
set +e
MOCK_ROOT="$test_dir/signal-root" MOCK_STATE="$test_dir/signal-state" MOCK_LOG="$test_dir/signal-mock.log" \
	sh -c '
		. "$1"
		LOG=$2
		MTD_DEV=/dev/null
		PERSISTENT_BLOCK0=/tmp/mock-original-block0
		STAGED_BLOCK=
		hash_file() { echo partial; }
		write_original_now() { echo restore >>"$LOG"; return 0; }
		remove_staged_block() { echo cleanup >>"$LOG"; }
		write_started=1
		candidate_committed=0
		trap apply_exit_guard EXIT
		trap "exit 143" TERM
		kill -TERM $$
	' sh "$functions_file" "$signal_log"
signal_rc=$?
set -e
[ "$signal_rc" -eq 143 ] || { echo "FAIL apply-signal: rc=$signal_rc" >&2; exit 1; }
[ "$(grep -c '^restore$' "$signal_log")" -eq 1 ] || { echo 'FAIL apply-signal restore count' >&2; exit 1; }
[ "$(grep -c '^cleanup$' "$signal_log")" -eq 1 ] || { echo 'FAIL apply-signal cleanup count' >&2; exit 1; }
case_count=$((case_count + 1)); pass_case apply-signal

signal_log="$test_dir/restore-signal.log"
set +e
MOCK_ROOT="$test_dir/signal-root" MOCK_STATE="$test_dir/signal-state" MOCK_LOG="$test_dir/signal-mock.log" \
	sh -c '
		. "$1"
		LOG=$2
		MTD_DEV=/dev/null
		RESTORE_SOURCE=/tmp/mock-original-block0
		STAGED_BLOCK=
		hash_file() { echo partial; }
		write_original_now() { echo restore >>"$LOG"; return 0; }
		remove_staged_block() { echo cleanup >>"$LOG"; }
		restore_started=1
		trap restore_exit_guard EXIT
		# SIGINT and SIGHUP may be inherited as ignored under a pipeline or
		# nohup. USR1 is independent of both terminal execution conditions.
		trap "exit 138" USR1
		kill -USR1 $$
	' sh "$functions_file" "$signal_log"
signal_rc=$?
set -e
[ "$signal_rc" -eq 138 ] || { echo "FAIL restore-signal: rc=$signal_rc" >&2; exit 1; }
[ "$(grep -c '^restore$' "$signal_log")" -eq 1 ] || { echo 'FAIL restore-signal retry count' >&2; exit 1; }
[ "$(grep -c '^cleanup$' "$signal_log")" -eq 1 ] || { echo 'FAIL restore-signal cleanup count' >&2; exit 1; }
case_count=$((case_count + 1)); pass_case restore-signal

# Git for Windows does not ship flock. Its nonblocking-refusal branch is still
# covered by the mock returning failure for an already-held transaction lock.
new_fixture lock-held ORIGINAL
MOCK_LOCK_HELD=1
export MOCK_LOCK_HELD
run_stage apply "$MOCK_ROOT/inputs/factory38.block0" "$CONFIRM_TOKEN"
expect_refusal lock-held 'another Factory transaction is already running'

[ "$pass_count" -eq "$case_count" ] || {
	echo "FAIL: pass_count=$pass_count case_count=$case_count" >&2
	exit 1
}
printf 'FACTORY38_STAGE_MOCK_TESTS=PASS cases=%s nand_real_writes=0\n' "$pass_count"
