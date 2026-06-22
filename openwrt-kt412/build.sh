#!/bin/bash
# =====================================================================
# KT412 (Dongwon DW02-412H) custom firmware builder — OpenWrt ImageBuilder
# Run on ANY Linux x86_64 machine WITH normal internet access.
# (This repo's sandbox cannot run it: OpenWrt servers are network-blocked.)
# =====================================================================
set -euo pipefail

# ---- CHOOSE YOUR VARIANT (must match your hardware NAND size) ----
#   64M  flash  -> dongwon_dw02-412h-64m   (image budget ~48MB)
#   128M flash  -> dongwon_dw02-412h-128m  (image budget ~112MB)
# Determine on the device:  cat /proc/mtd   (look at the 'ubi' partition size)
PROFILE="${PROFILE:-dongwon_dw02-412h-64m}"

# ---- CHOOSE RELEASE ----
#   Stable, swconfig (matches the configs in ./files):  23.05.5  or  24.10.x
VERSION="${VERSION:-23.05.5}"
TARGET="ath79/nand"

IB="openwrt-imagebuilder-${VERSION}-ath79-nand.Linux-x86_64"
URL="https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${IB}.tar.xz"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${HERE}/build"
OUT="${HERE}/output"
mkdir -p "$WORK" "$OUT"

echo "[*] Profile : $PROFILE"
echo "[*] Release : $VERSION ($TARGET)"

cd "$WORK"
if [ ! -d "$IB" ]; then
	echo "[*] Downloading ImageBuilder..."
	wget -q --show-progress "$URL"
	tar -xf "${IB}.tar.xz"
fi
cd "$IB"

# Package list (strip comments/blank lines)
PKGS="$(grep -vE '^\s*#|^\s*$' "${HERE}/packages.txt" | tr '\n' ' ')"

echo "[*] Building image with baked-in ./files overlay..."
make image \
	PROFILE="$PROFILE" \
	PACKAGES="$PKGS" \
	FILES="${HERE}/files" \
	EXTRA_IMAGE_NAME="kt412-custom"

# Collect + rename to the requested name + checksum + manifest
BINDIR="bin/targets/ath79/nand"
SYS="$(ls -1 ${BINDIR}/*${PROFILE}*sysupgrade.bin | head -1)"
FAC="$(ls -1 ${BINDIR}/*${PROFILE}*factory.img 2>/dev/null | head -1 || true)"

cp "$SYS" "${OUT}/openwrt-kt412-custom-sysupgrade.bin"
[ -n "${FAC:-}" ] && cp "$FAC" "${OUT}/openwrt-kt412-custom-factory.img" || true
cp "${BINDIR}"/*.manifest "${OUT}/openwrt-kt412-custom.manifest" 2>/dev/null || true

cd "$OUT"
sha256sum openwrt-kt412-custom-*.bin openwrt-kt412-custom-*.img 2>/dev/null > SHA256SUMS || true

echo
echo "==================== DONE ===================="
echo "Output dir: $OUT"
ls -lh "$OUT"
echo
echo "Verify before flashing:"
echo "  cat ${OUT}/SHA256SUMS"
