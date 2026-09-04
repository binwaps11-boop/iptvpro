#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOOK="$ROOT/files/lib/preinit/71_cr6608_initramfs_detach_ubi"
GUARD_PATCH="$ROOT/patches/141-mtd-ubi-skip-auto-attach-for-embedded-initramfs.patch"
SEED="$ROOT/cr6608.seed.config"
INSPECTOR="$ROOT/inspect-image.sh"
BUILD="$ROOT/build.sh"
REMOTE_BUILD="$ROOT/build.remote.sh"

fail() {
	printf 'initramfs_ubi_detach_contract=fail: %s\n' "$*" >&2
	exit 1
}

[ -f "$HOOK" ] && [ ! -L "$HOOK" ] && [ -x "$HOOK" ] ||
	fail 'preinit hook is absent, linked, or not executable'
[ -f "$GUARD_PATCH" ] && [ ! -L "$GUARD_PATCH" ] && [ -s "$GUARD_PATCH" ] ||
	fail 'embedded-initramfs UBI guard patch is absent, linked, or empty'
if [ -n "${CR6608_TEST_BUSYBOX_BIN:-}" ]; then
	"$CR6608_TEST_BUSYBOX_BIN" ash -n "$HOOK" || fail 'BusyBox ash preinit hook syntax failed'
else
	sh -n "$HOOK" || fail 'preinit hook syntax failed'
fi
grep -Fq -- '--- a/drivers/mtd/ubi/build.c' "$GUARD_PATCH" ||
	fail 'guard patch does not target the UBI auto-attach implementation'
grep -Fq "CONFIG_INITRAMFS_SOURCE[0] != '\\0'" "$GUARD_PATCH" ||
	fail 'guard patch does not distinguish the separately built embedded initramfs'
grep -Fq 'UBI: skip auto-attach for embedded initramfs' "$GUARD_PATCH" ||
	fail 'guard patch lacks its runtime serial witness'
! grep -Eq '^[-+]CONFIG_MTD_ROOTFS_ROOT_DEV' "$GUARD_PATCH" ||
	fail 'guard patch changes the normal persistent-root kernel policy'
for build_variant in "$BUILD" "$REMOTE_BUILD"; do
	grep -Fq 'SRC_UBI_INITRAMFS_GUARD_PATCH=' "$build_variant" ||
		fail "build does not name the guard input: $build_variant"
	grep -Fq 'record_regular_input platform-patch "${SRC_UBI_INITRAMFS_GUARD_PATCH}"' \
		"$build_variant" || fail "build does not bind the guard input: $build_variant"
	grep -Fq 'install -m 0644 -- "${SRC_UBI_INITRAMFS_GUARD_PATCH}"' \
		"$build_variant" || fail "build does not stage the guard patch: $build_variant"
	grep -Fq 'prepared kernel lacks the embedded-initramfs UBI auto-attach guard' \
		"$build_variant" || fail "build does not inspect the prepared guard: $build_variant"
	grep -Fq 'Normal flash kernel lost its persistent-root UBI auto-attach path' \
		"$build_variant" || fail "build does not preserve the normal UBI path: $build_variant"
	grep -Fq 'Embedded-initramfs kernel still contains the reachable UBI auto-attach path' \
		"$build_variant" || fail "build does not prove auto-attach was compiled out: $build_variant"
done
grep -Fq 'boot_hook_add initramfs cr6608_initramfs_detach_mtd7' "$HOOK" ||
	fail 'preinit hook is not registered on the initramfs phase'
! grep -Fq 'boot_hook_add preinit_main cr6608_initramfs_detach_mtd7' "$HOOK" ||
	fail 'preinit hook is dangerously registered on persistent preinit_main'
grep -Fq 'CR6608_INITRAMFS_UBI_FAIL_STOP reason=' "$HOOK" ||
	fail 'preinit hook lacks the stable serial fail-stop marker'
grep -Fq 'exec "$CR6608_UBI_FAIL_STOP_BIN" "$reason"' "$HOOK" ||
	fail 'preinit hook lacks its explicit testable fail-stop replacement'
grep -Fq '"$CR6608_UBI_SLEEP_BIN" 3600' "$HOOK" ||
	fail 'production fail-stop is not a non-returning bounded-sleep loop'
! grep -Eq 'failsafe_shell|askconsole|exec[[:space:]]+(/bin/)?(ash|bash|sh)([[:space:]]|$)' "$HOOK" ||
	fail 'preinit UBI failure path exposes an unauthenticated recovery shell'
grep -Fqx 'CONFIG_PACKAGE_ubi-utils=y' "$SEED" ||
	fail 'image seed does not explicitly include ubidetach'
grep -Fq 'require_mode usr/sbin/ubidetach 755' "$INSPECTOR" ||
	fail 'image inspector does not require the ubidetach executable'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cr6608-ubi-detach.XXXXXX")" || exit 1
trap 'rm -rf -- "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/sys/class/ubi" "$TMP/bin"
sed \
	-e "s#/proc/mounts#$TMP/mounts#g" \
	-e "s#/sys/class/ubi#$TMP/sys/class/ubi#g" \
	"$HOOK" >"$TMP/hook"

cat >"$TMP/bin/ubidetach" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$CR6608_TEST_DETACH_LOG"
case "${CR6608_TEST_DETACH_MODE:-success}" in
	success)
		for ubi_path in "$CR6608_TEST_UBI_CLASS"/ubi[0-9]*; do
			[ -r "$ubi_path/mtd_num" ] || continue
			mtd_num=
			IFS= read -r mtd_num <"$ubi_path/mtd_num" || exit 1
			[ "$mtd_num" = 7 ] || continue
			rm -rf -- "$ubi_path"
		done
		;;
	fail) printf 'mock ubidetach failure\n' >&2; exit 1 ;;
	stuck) ;;
	*) exit 2 ;;
esac
SH
chmod 0755 "$TMP/bin/ubidetach"
cat >"$TMP/bin/sleep" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$CR6608_TEST_SLEEP_LOG"
[ "${CR6608_TEST_SLEEP_MODE:-success}" = success ]
SH
chmod 0755 "$TMP/bin/sleep"
cat >"$TMP/bin/fail-stop" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$CR6608_TEST_FAIL_STOP_LOG"
exit 125
SH
chmod 0755 "$TMP/bin/fail-stop"
export PATH="$TMP/bin:$PATH"
export CR6608_TEST_DETACH_LOG="$TMP/detach.log"
export CR6608_TEST_SLEEP_LOG="$TMP/sleep.log"
export CR6608_TEST_FAIL_STOP_LOG="$TMP/fail-stop.log"
export CR6608_TEST_UBI_CLASS="$TMP/sys/class/ubi"
export CR6608_UBI_SLEEP_BIN="$TMP/bin/sleep"
export CR6608_UBI_FAIL_STOP_BIN="$TMP/bin/fail-stop"
export CR6608_UBI_CONSOLE_PATH="$TMP/console"

HOOK_REGISTRATION="$TMP/hook-registration"
boot_hook_add() {
	printf '%s %s\n' "$1" "$2" >"$HOOK_REGISTRATION"
}
# shellcheck disable=SC1090
. "$TMP/hook"
[ "$(cat "$HOOK_REGISTRATION" 2>/dev/null)" = \
	'initramfs cr6608_initramfs_detach_mtd7' ] ||
	fail 'sourced hook registered on the wrong boot phase'
INITRAMFS=1

reset_ubi() {
	rm -rf -- "$TMP/sys/class/ubi"
	mkdir -p "$TMP/sys/class/ubi"
	rm -f -- "$CR6608_TEST_DETACH_LOG" "$CR6608_TEST_SLEEP_LOG" \
		"$CR6608_TEST_FAIL_STOP_LOG" "$CR6608_UBI_CONSOLE_PATH" "$TMP/boot-continued"
	CR6608_TEST_DETACH_MODE=success
	CR6608_TEST_SLEEP_MODE=success
	export CR6608_TEST_DETACH_MODE CR6608_TEST_SLEEP_MODE
}

attach() {
	mkdir -p "$TMP/sys/class/ubi/$1"
	printf '%s\n' "$2" >"$TMP/sys/class/ubi/$1/mtd_num"
}

expect_none() {
	[ ! -e "$CR6608_TEST_DETACH_LOG" ] ||
		fail "unsafe detach attempted for $1"
}

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
cr6608_initramfs_detach_mtd7
[ "$(cat "$CR6608_TEST_DETACH_LOG" 2>/dev/null)" = '-m 7' ] ||
	fail 'unmistakable initramfs mtd7 attachment was not detached'
[ ! -e "$TMP/sys/class/ubi/ubi0" ] ||
	fail 'successful detach did not wait for the UBI sysfs node to disappear'
[ ! -e "$CR6608_TEST_SLEEP_LOG" ] ||
	fail 'immediate sysfs disappearance performed an unnecessary wait'

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
CR6608_TEST_DETACH_MODE=fail; export CR6608_TEST_DETACH_MODE
if detach_failure="$(
	{
		cr6608_initramfs_detach_mtd7
		printf 'unsafe continuation\n' >"$TMP/boot-continued"
	} 2>&1
)"; then
	fail 'non-zero ubidetach result was hidden'
else
	detach_rc=$?
fi
[ "$detach_rc" -eq 125 ] || fail "fail-stop mock returned unexpected status $detach_rc"
[ ! -e "$TMP/boot-continued" ] || fail 'boot command after UBI failure was executed'
printf '%s\n' "$detach_failure" | grep -Fq \
	'CR6608_INITRAMFS_UBI_FAIL_STOP reason=ubidetach returned non-zero for ubi0' ||
	fail 'non-zero ubidetach result lacked the precise fail-stop marker'
[ "$(cat "$CR6608_TEST_FAIL_STOP_LOG" 2>/dev/null)" = \
	'ubidetach returned non-zero for ubi0' ] || fail 'failure did not exec the fail-stop backend'
grep -Fqx 'CR6608_INITRAMFS_UBI_FAIL_STOP reason=ubidetach returned non-zero for ubi0' \
	"$CR6608_UBI_CONSOLE_PATH" || fail 'serial console did not receive the fail-stop marker'
[ -e "$TMP/sys/class/ubi/ubi0" ] || fail 'failed ubidetach unexpectedly removed the UBI node'

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
CR6608_TEST_DETACH_MODE=stuck; export CR6608_TEST_DETACH_MODE
if detach_failure="$(cr6608_initramfs_detach_mtd7 2>&1)"; then
	fail 'zero-exit ubidetach with persistent sysfs state was accepted'
fi
printf '%s\n' "$detach_failure" | grep -Fq 'ubi0 remained present after 5 seconds' ||
	fail 'bounded disappearance timeout lacked a precise diagnostic'
[ "$(wc -l <"$CR6608_TEST_SLEEP_LOG" 2>/dev/null)" -eq 5 ] ||
	fail 'sysfs disappearance wait was not bounded to five attempts'

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
CR6608_TEST_DETACH_MODE=stuck; CR6608_TEST_SLEEP_MODE=fail
export CR6608_TEST_DETACH_MODE CR6608_TEST_SLEEP_MODE
if detach_failure="$(cr6608_initramfs_detach_mtd7 2>&1)"; then
	fail 'sleep failure during sysfs wait was hidden'
fi
printf '%s\n' "$detach_failure" | grep -Fq 'wait for ubi0 disappearance was interrupted' ||
	fail 'sleep failure lacked a precise diagnostic'

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
saved_path="$PATH"
mkdir -p "$TMP/no-ubidetach"
PATH="$TMP/no-ubidetach"
if detach_failure="$(cr6608_initramfs_detach_mtd7 2>&1)"; then
	PATH="$saved_path"
	fail 'missing ubidetach was accepted while mtd7 was attached'
fi
PATH="$saved_path"
printf '%s\n' "$detach_failure" | grep -Fq 'ubidetach is unavailable while ubi0 is attached' ||
	fail 'missing ubidetach lacked a precise diagnostic'

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
rm -f -- "$TMP/sys/class/ubi/ubi0/mtd_num"
if detach_failure="$(cr6608_initramfs_detach_mtd7 2>&1)"; then
	fail 'unreadable top-level UBI mtd_num was accepted'
fi
printf '%s\n' "$detach_failure" | grep -Fq 'ubi0/mtd_num is unreadable' ||
	fail 'unreadable UBI identity lacked a precise diagnostic'

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 malformed
if detach_failure="$(cr6608_initramfs_detach_mtd7 2>&1)"; then
	fail 'malformed top-level UBI mtd_num was accepted'
fi
printf '%s\n' "$detach_failure" | grep -Fq 'ubi0/mtd_num is malformed' ||
	fail 'malformed UBI identity lacked a precise diagnostic'

reset_ubi
printf '%s\n' 'rootfs / rootfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
INITRAMFS=0
cr6608_initramfs_detach_mtd7
expect_none 'persistent boot hook context'
INITRAMFS=1

reset_ubi
printf '%s\n' \
	'tmpfs / tmpfs rw 0 0' \
	'/dev/ubiblock0_0 /rom squashfs ro 0 0' >"$TMP/mounts"
attach ubi0 7
cr6608_initramfs_detach_mtd7
expect_none 'persistent /rom mount'

reset_ubi
printf '%s\n' \
	'tmpfs / tmpfs rw 0 0' \
	'ubi0:data /mnt/data ubifs rw 0 0' >"$TMP/mounts"
attach ubi0 7
cr6608_initramfs_detach_mtd7
expect_none 'mounted UBI filesystem'

reset_ubi
printf '%s\n' '/dev/root / ext4 rw 0 0' >"$TMP/mounts"
attach ubi0 7
cr6608_initramfs_detach_mtd7
expect_none 'non-memory root'

reset_ubi
printf '%s\n' 'tmpfs / tmpfs rw 0 0' >"$TMP/mounts"
attach ubi0 7
attach ubi1 7
if detach_failure="$(cr6608_initramfs_detach_mtd7 2>&1)"; then
	fail 'ambiguous duplicate mtd7 attachment was accepted'
fi
printf '%s\n' "$detach_failure" | grep -Fq 'multiple UBI devices claim mtd7' ||
	fail 'duplicate mtd7 attachment lacked a precise diagnostic'
expect_none 'ambiguous duplicate mtd7 attachment'

reset_ubi
printf '%s\n' 'tmpfs / tmpfs rw 0 0' >"$TMP/mounts"
attach ubi0 8
cr6608_initramfs_detach_mtd7
expect_none 'different MTD attachment'

printf 'initramfs_ubi_detach_contract=pass\n'
