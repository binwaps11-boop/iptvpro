#!/bin/sh
# ==========================================================================
# One-command local build for the CR6606 custom firmware using the OFFICIAL
# OpenWrt ImageBuilder. Run on any Linux box WITH internet access to
# downloads.openwrt.org. Produces dist/openwrt-cr6606-custom-sysupgrade.bin
# (+ sha256 + manifest + build.log). CR6606 ONLY.
#
# Usage:   sh build-local.sh            # uses version from build/profile.env
#          VERSION=24.10.2 sh build-local.sh
# ==========================================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/build/profile.env"
[ -n "$VERSION" ] && OPENWRT_VERSION="$VERSION"

TARGET="ramips"; SUBTARGET="mt7621"; PROFILE="xiaomi_mi-router-cr6606"
BASE="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}"
STEM="openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64"

echo ">> Building for $PROFILE (CR6606 ONLY), OpenWrt $OPENWRT_VERSION"
cd "$HERE"
mkdir -p .work && cd .work

if [ ! -d "$STEM" ]; then
  if wget -q "${BASE}/${STEM}.tar.zst"; then
    tar --use-compress-program=unzstd -xf "${STEM}.tar.zst"
  else
    wget -q "${BASE}/${STEM}.tar.xz"
    tar -xJf "${STEM}.tar.xz"
  fi
fi

cd "$STEM"
# Safety gate: refuse to build if this is not the CR6606 target.
if ! make info 2>/dev/null | grep -q "xiaomi_mi-router-cr6606"; then
  echo "ERROR: xiaomi_mi-router-cr6606 not found in ImageBuilder. Aborting." >&2
  exit 1
fi

PKGS="$(grep -vE '^[[:space:]]*#' "$HERE/build/packages.txt" | tr '\n' ' ')"
echo ">> Packages: $PKGS"
make image \
  PROFILE="$PROFILE" \
  PACKAGES="$PKGS" \
  FILES="$HERE/files" 2>&1 | tee "$HERE/.work/build.log"

OUT="bin/targets/${TARGET}/${SUBTARGET}"
SRC="$(ls ${OUT}/openwrt-*-${PROFILE}-squashfs-sysupgrade.bin)"
mkdir -p "$HERE/dist"
cp "$SRC" "$HERE/dist/openwrt-cr6606-custom-sysupgrade.bin"
cp ${OUT}/openwrt-*-${PROFILE}.manifest "$HERE/dist/manifest.txt"
cp ${OUT}/openwrt-*-${PROFILE}.manifest "$HERE/dist/packages.list"
cp "$HERE/.work/build.log" "$HERE/dist/build.log"
cd "$HERE/dist"
sha256sum openwrt-cr6606-custom-sysupgrade.bin > openwrt-cr6606-custom-sysupgrade.bin.sha256
echo ">> DONE. Output in: $HERE/dist"
cat openwrt-cr6606-custom-sysupgrade.bin.sha256
