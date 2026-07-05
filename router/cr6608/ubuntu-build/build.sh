#!/usr/bin/env bash
#
# build.sh - Build OpenWrt 24.10.6 from source for the Xiaomi CR6608
#            (ramips/mt7621, profile: xiaomi,mi-router-cr6608)
#
# Runs on a normal Ubuntu 22.04 / 24.04 machine with internet access.
# Bakes in a custom files/ overlay and an mt76 driver patch.
#
# Usage:   ./build.sh
# Output:  openwrt/bin/targets/ramips/mt7621/*cr6608*sysupgrade.bin
#
# DO NOT run this script as root. OpenWrt's buildroot refuses to build as
# root and it is not needed (only the apt step uses sudo).
# ---------------------------------------------------------------------------

set -euo pipefail

# --- config -----------------------------------------------------------------
OPENWRT_URL="https://git.openwrt.org/openwrt/openwrt.git"
OPENWRT_TAG="v24.10.6"
DEVICE_PROFILE="xiaomi_mi-router-cr6608"
REGDB_URL="https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git/plain/regulatory.db"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_FILES="${SCRIPT_DIR}/files"
SRC_PATCH="${SCRIPT_DIR}/patches/999-mt7915-cr6608-rf-35dbm.patch"
SRC_SEED="${SCRIPT_DIR}/cr6608.seed.config"
OPENWRT_DIR="${SCRIPT_DIR}/openwrt"

# --- pretty output + error trap ---------------------------------------------
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    [ok] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    [warn] %s\033[0m\n' "$*"; }

on_error() {
	local ec=$?
	printf '\n\033[1;31m!!! build.sh FAILED (exit %s) at line %s: %s\033[0m\n' \
		"${ec}" "${BASH_LINENO[0]:-?}" "${BASH_COMMAND}" >&2
	printf '\033[1;31m    See the last output above. For a verbose single-threaded\n'
	printf '    retry of the compile step run:  cd %s && make -j1 V=s\033[0m\n' "${OPENWRT_DIR}" >&2
	exit "${ec}"
}
trap on_error ERR

if [ "$(id -u)" -eq 0 ]; then
	echo "Refusing to run as root. Run as a normal user (apt uses sudo)." >&2
	exit 1
fi

# ---------------------------------------------------------------------------
say "[1/9] Installing Ubuntu build dependencies (needs sudo)"
sudo apt-get update
sudo apt-get install -y \
	build-essential clang flex bison g++ gawk \
	gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev \
	python3-setuptools rsync swig unzip zlib1g-dev file wget
ok "dependencies installed"

# ---------------------------------------------------------------------------
say "[2/9] Cloning OpenWrt and checking out ${OPENWRT_TAG}"
if [ ! -d "${OPENWRT_DIR}/.git" ]; then
	git clone "${OPENWRT_URL}" "${OPENWRT_DIR}"
else
	ok "openwrt/ already cloned, reusing it"
fi
cd "${OPENWRT_DIR}"
git fetch --tags --force
git checkout "${OPENWRT_TAG}"
ok "checked out $(git describe --tags --always)"

# ---------------------------------------------------------------------------
say "[3/9] Updating and installing feeds"
./scripts/feeds update -a
./scripts/feeds install -a
ok "feeds ready"

# ---------------------------------------------------------------------------
say "[4/9] Dropping the mt76 driver patch into the package patch dir"
MT76_PATCH_DIR="${OPENWRT_DIR}/package/kernel/mt76/patches"
if [ ! -d "${MT76_PATCH_DIR}" ]; then
	warn "package/kernel/mt76/patches did not exist yet - creating it"
	mkdir -p "${MT76_PATCH_DIR}"
fi
cp -v "${SRC_PATCH}" "${MT76_PATCH_DIR}/"
ok "patch staged at package/kernel/mt76/patches/$(basename "${SRC_PATCH}")"

# ---------------------------------------------------------------------------
say "[5/9] Ensuring a regulatory.db exists in the files/ overlay"
if [ ! -s "${SRC_FILES}/lib/firmware/regulatory.db" ]; then
	warn "no regulatory.db in files/lib/firmware - fetching the official wireless-regdb copy"
	wget -O "${SRC_FILES}/lib/firmware/regulatory.db" "${REGDB_URL}"
	ok "fetched regulatory.db ($(stat -c%s "${SRC_FILES}/lib/firmware/regulatory.db") bytes)"
else
	ok "using the regulatory.db you provided"
fi

# ---------------------------------------------------------------------------
say "[6/9] Copying the custom files/ overlay into the buildroot"
# Everything under files/ is baked verbatim into the rootfs image.
mkdir -p "${OPENWRT_DIR}/files"
cp -a "${SRC_FILES}/." "${OPENWRT_DIR}/files/"
# Make sure shipped scripts are executable inside the image.
chmod 0755 "${OPENWRT_DIR}"/files/usr/sbin/* 2>/dev/null || true
# The text README for regulatory.db must not ship in the firmware.
rm -f "${OPENWRT_DIR}/files/lib/firmware/README.regulatory.txt"
ok "overlay copied to openwrt/files/ (etc/config, lib/firmware, usr/sbin, etc/modprobe.d, www)"

# ---------------------------------------------------------------------------
say "[7/9] Writing the seed .config and expanding it with defconfig"
cp "${SRC_SEED}" "${OPENWRT_DIR}/.config"
make defconfig
# Sanity-check the device profile actually got selected.
if ! grep -q "^CONFIG_TARGET_ramips_mt7621_DEVICE_${DEVICE_PROFILE}=y" "${OPENWRT_DIR}/.config"; then
	warn "device profile ${DEVICE_PROFILE} is NOT selected in .config after defconfig!"
	warn "check cr6608.seed.config against 'make menuconfig' target list."
else
	ok "device profile ${DEVICE_PROFILE} selected"
fi

# ---------------------------------------------------------------------------
say "[8/9] Downloading all sources (make download -j8)"
make download -j8
ok "all source tarballs downloaded"

# ---------------------------------------------------------------------------
say "[9/9] Compiling the image (make -j\$(nproc), fallback make -j1 V=s)"
if ! make -j"$(nproc)"; then
	warn "parallel build failed - retrying single-threaded with verbose output"
	warn "this will show exactly which package failed"
	make -j1 V=s
fi
ok "build finished"

# ---------------------------------------------------------------------------
say "DONE. Firmware images are here:"
BIN_DIR="${OPENWRT_DIR}/bin/targets/ramips/mt7621"
ls -lh "${BIN_DIR}"/*cr6608* 2>/dev/null || ls -lh "${BIN_DIR}" || true
echo
echo "Flash the *sysupgrade.bin file, for example:"
echo "  ${BIN_DIR}/openwrt-24.10.6-ramips-mt7621-${DEVICE_PROFILE}-squashfs-sysupgrade.bin"
echo
echo "See README.md -> 'Flashing' before you write it to the router."
