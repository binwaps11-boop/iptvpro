#!/bin/sh
# =============================================================================
# SmartAP — one-shot fetch/build helper for JCG Q20 and Xiaomi CR6608
# =============================================================================
# Run this on a normal Ubuntu box (20.04/22.04/24.04) over SSH.
#
#   ./smartap.sh get              # wget the prebuilt .bin images + source (fast, ~20s)
#   ./smartap.sh build q20        # reproducible from-source build of the Q20 image (~1h)
#   ./smartap.sh build cr6608     # reproducible from-source build of the CR6608 image (~1h)
#   ./smartap.sh build both       # build BOTH images from source
#
# 'get' downloads:
#   - smartap-jcg-q20-sysupgrade-38dbm.bin
#   - smartap-cr6608-sysupgrade-38dbm.bin
#   - SHA256SUMS   (and verifies them)
#   - smartap-source.tar.gz   (the full source tree: overlay + driver patches + CI)
#
# 'build' reproduces EXACTLY what GitHub Actions builds: OpenWrt v25.12.5, the
# 38 dBm mt76 driver patch (target power -> 38.0 dBm, proof-marker gated), the
# PCIe warm-reboot fix, the full SmartAP overlay, then greps the finished
# mt7915e.ko to PROVE the 38 dBm driver shipped before declaring success.
#
# Everything is idempotent and retries transient network failures.
# =============================================================================
set -eu

OWNER="binwaps11-boop"
REPO="iptvpro"
BRANCH="claude/xiaomi-cr6608-firmware-fix-gnymma"
DELIVERY_BRANCH="q20-delivery"
OPENWRT_REF="v25.12.5"
RAW="https://raw.githubusercontent.com/${OWNER}/${REPO}/${DELIVERY_BRANCH}/dist"
SRC_TARBALL="https://codeload.github.com/${OWNER}/${REPO}/tar.gz/refs/heads/${BRANCH}"
OUT="${OUT:-$PWD/smartap-out}"

say(){ printf '\033[1;36m==> %s\033[0m\n' "$*"; }
err(){ printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# retry <n> <cmd...> : run cmd, retry up to n times with linear backoff
retry(){ _n=$1; shift; _i=0; until "$@"; do _i=$((_i+1)); [ "$_i" -ge "$_n" ] && return 1; echo "  retry $_i/$_n: $*"; sleep $((_i*8)); done; }

dl(){ # dl <url> <outfile>  — prefer wget, fall back to curl
  if command -v wget >/dev/null 2>&1; then retry 5 wget -q -O "$2" "$1"
  else retry 5 curl -fsSL -o "$2" "$1"; fi
}

# -----------------------------------------------------------------------------
cmd_get(){
  mkdir -p "$OUT"; cd "$OUT"
  say "Downloading prebuilt SmartAP images from the ${DELIVERY_BRANCH} branch"
  dl "$RAW/smartap-jcg-q20-sysupgrade-38dbm.bin"   smartap-jcg-q20-sysupgrade-38dbm.bin   || err "Q20 image download failed"
  dl "$RAW/smartap-cr6608-sysupgrade-38dbm.bin"    smartap-cr6608-sysupgrade-38dbm.bin    || err "CR6608 image download failed"
  dl "$RAW/SHA256SUMS" SHA256SUMS || echo "  (no SHA256SUMS published yet — skipping checksum)"
  say "Downloading full source tree"
  dl "$SRC_TARBALL" smartap-source.tar.gz || err "source download failed"
  if [ -s SHA256SUMS ]; then
    say "Verifying checksums"
    sha256sum -c SHA256SUMS || err "CHECKSUM MISMATCH — do not flash these files"
    echo "  checksums OK"
  fi
  echo
  say "Done. Files in: $OUT"
  ls -lh "$OUT"
  cat <<EOF

Flash on the router (over SSH to the device):
  # copy the matching .bin to the router, then:
  sysupgrade -n /tmp/smartap-jcg-q20-sysupgrade-38dbm.bin      # JCG Q20
  sysupgrade -n /tmp/smartap-cr6608-sysupgrade-38dbm.bin       # Xiaomi CR6608
  # -n = do not keep settings (clean flash). Change the admin password after first login.
EOF
}

# -----------------------------------------------------------------------------
install_deps(){
  say "Installing OpenWrt build dependencies (sudo apt)"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-distutils python3-setuptools \
    rsync unzip zlib1g-dev file wget qemu-utils ccache subversion swig \
    libelf-dev ecj fastjar java-propose-classpath squashfs-tools \
    binutils python3 >/dev/null
}

clone_repo(){ # -> $SRCDIR
  SRCDIR="$OUT/src"
  if [ -d "$SRCDIR/.git" ]; then
    say "Refreshing SmartAP source"; ( cd "$SRCDIR" && retry 5 git fetch --depth 1 origin "$BRANCH" && git checkout -f FETCH_HEAD )
  else
    say "Cloning SmartAP source ($BRANCH)"
    retry 5 git clone --depth 1 -b "$BRANCH" "https://github.com/${OWNER}/${REPO}.git" "$SRCDIR"
  fi
}

# build_one <q20|cr6608>
build_one(){
  dev="$1"
  case "$dev" in
    q20)
      OVERLAY="$SRCDIR/router/jcg-q20/files"
      SEED="$SRCDIR/router/jcg-q20/kernel-build/jcg-q20.seed.config"
      PCIE="$SRCDIR/router/jcg-q20/kernel-build/patches/399-pcie-mt7621-longer-reset-delays.patch"
      APPLY="$SRCDIR/router/jcg-q20/kernel-build/apply-mt76-38.py"
      DEVSYM="CONFIG_TARGET_ramips_mt7621_DEVICE_jcg_q20=y"
      MARKER="SMARTAP-Q20-RF-38DBM-LINEAR"
      OUTNAME="smartap-jcg-q20-sysupgrade-38dbm.bin" ;;
    cr6608)
      OVERLAY="$SRCDIR/router/cr6608/ubuntu-build/files"
      SEED="$SRCDIR/router/cr6608/ubuntu-build/cr6608.seed.config"
      PCIE="$SRCDIR/router/cr6608/ubuntu-build/399-pcie-mt7621-longer-reset-delays.patch"
      APPLY="$SRCDIR/router/cr6608/ubuntu-build/apply-mt76-38.py"
      DEVSYM="CONFIG_TARGET_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6608=y"
      MARKER="SMARTAP-CR6608-RF-38DBM-LINEAR"
      OUTNAME="smartap-cr6608-sysupgrade-38dbm.bin" ;;
    *) err "unknown device '$dev' (use q20 or cr6608)" ;;
  esac
  [ -f "$SEED" ]  || err "seed config missing: $SEED"
  [ -d "$OVERLAY" ] || err "overlay missing: $OVERLAY"
  [ -f "$APPLY" ] || err "38 dBm patcher missing: $APPLY"

  OW="$OUT/ow-$dev"
  say "[$dev] Clone OpenWrt $OPENWRT_REF"
  if [ ! -d "$OW/.git" ]; then retry 5 git clone https://git.openwrt.org/openwrt/openwrt.git "$OW"; fi
  cd "$OW"; git checkout "$OPENWRT_REF"; git log -1 --oneline

  say "[$dev] Update & install feeds (with retry + presence check)"
  retry 5 ./scripts/feeds update -a
  for f in luci routing packages; do
    [ -d "feeds/$f" ] || { echo "  feed $f missing — retrying update"; retry 5 ./scripts/feeds update -a; break; }
  done
  [ -d feeds/luci ] && [ -d feeds/routing ] && [ -d feeds/packages ] || err "core feeds still missing"
  retry 5 ./scripts/feeds install -a

  say "[$dev] PCIe warm-reboot fix (100->500 ms)"
  install -m 0644 "$PCIE" "target/linux/ramips/patches-6.12/399-pcie-mt7621-longer-reset-delays.patch"

  say "[$dev] Bake in the SmartAP overlay"
  mkdir -p files
  cp -a "$OVERLAY/." files/
  # The driver is compiled from patched SOURCE here; drop any stale prebuilt .ko so
  # the source-built (proof-marked) mt7915e.ko is the one that ships.
  rm -rf files/lib/modules
  for t in bootstrap-dark bootstrap-light; do
    d="files/usr/share/ucode/luci/template/themes/$t"
    [ -L "$d" ] || { rm -rf "$d" 2>/dev/null || true; [ -d "files/usr/share/ucode/luci/template/themes" ] && ln -s bootstrap "$d" || true; }
  done
  chmod 0755 files/usr/sbin/* files/usr/bin/* files/etc/init.d/* files/www/cgi-bin/* 2>/dev/null || true

  say "[$dev] Seed .config and expand"
  cp "$SEED" .config
  make defconfig
  grep -q "$DEVSYM" .config || err "[$dev] device profile NOT selected after defconfig"

  say "[$dev] Apply the 38 dBm mt76 driver patch (persisted so it survives re-prepare)"
  make package/kernel/mt76/prepare V=s QUILT=1 2>&1 | tail -3 || make package/kernel/mt76/prepare V=s 2>&1 | tail -3 || true
  MT76DIR="$(find build_dir -maxdepth 5 -type d -name 'mt76-*' 2>/dev/null | head -1)"
  [ -n "$MT76DIR" ] || err "[$dev] no mt76 build dir"
  # Snapshot the pristine source, apply the 38 dBm early-return, then persist the delta
  # with diff(1) on REAL files. (git diff on the build_dir emits 0 bytes — build_dir is
  # gitignored and the nearest .git is OpenWrt's own, which sees none of these files.)
  cp "$MT76DIR/mt7915/eeprom.c" "$MT76DIR/mt7915/eeprom.c.orig"
  python3 "$APPLY" "$MT76DIR"
  mkdir -p package/kernel/mt76/patches
  # diff returns 1 when files differ; `|| true` is MANDATORY under `set -eu`.
  diff -u -L a/mt7915/eeprom.c -L b/mt7915/eeprom.c \
    "$MT76DIR/mt7915/eeprom.c.orig" "$MT76DIR/mt7915/eeprom.c" \
    > package/kernel/mt76/patches/999-smartap-38dbm.patch || true
  rm -f "$MT76DIR/mt7915/eeprom.c.orig"
  test -s package/kernel/mt76/patches/999-smartap-38dbm.patch \
    || err "[$dev] empty 38 dBm patch — refusing to build a driver that would fail the marker gate"
  # Clean so the full build re-extracts pristine mt76 and re-applies ALL patches (incl. ours).
  make package/kernel/mt76/clean V=s 2>&1 | tail -2 || true

  say "[$dev] Download sources"
  retry 3 make download -j8 V=s

  say "[$dev] Build (this is the ~1h step)"
  make -j"$(nproc)" || make -j1 V=s

  BIN="$(ls bin/targets/ramips/mt7621/*sysupgrade.bin 2>/dev/null | head -1)"
  [ -n "$BIN" ] || err "[$dev] no sysupgrade.bin produced"

  say "[$dev] PROVE the 38 dBm driver shipped (marker gate)"
  rm -rf /tmp/sq-$dev; mkdir -p /tmp/sq-$dev
  tar -xf "$BIN" -C /tmp/sq-$dev
  ROOT="$(find /tmp/sq-$dev -name root -type f | head -1)"
  unsquashfs -q -f -d /tmp/sq-$dev/rootfs "$ROOT" >/dev/null 2>&1 || true
  KO="$(find /tmp/sq-$dev/rootfs -name 'mt7915e.ko' | head -1)"
  [ -n "$KO" ] && strings -a "$KO" | grep -q "$MARKER" \
    || err "[$dev] 38 dBm marker NOT in mt7915e.ko — refusing this image"
  mkdir -p "$OUT"; cp "$BIN" "$OUT/$OUTNAME"
  ( cd "$OUT" && sha256sum "$OUTNAME" )
  say "[$dev] OK -> $OUT/$OUTNAME (38 dBm driver proven)"
}

cmd_build(){
  which="${1:-both}"
  install_deps
  clone_repo
  case "$which" in
    q20)    build_one q20 ;;
    cr6608) build_one cr6608 ;;
    both)   build_one q20; build_one cr6608 ;;
    *) err "usage: ./smartap.sh build [q20|cr6608|both]" ;;
  esac
  echo; say "All requested builds done. Images in: $OUT"; ls -lh "$OUT"/*.bin 2>/dev/null || true
  cat <<EOF

Flash (over SSH to the router):
  sysupgrade -n /tmp/<image>.bin
EOF
}

# -----------------------------------------------------------------------------
case "${1:-get}" in
  get)   cmd_get ;;
  build) shift; cmd_build "${1:-both}" ;;
  *) cat <<EOF
SmartAP helper — JCG Q20 & Xiaomi CR6608

  ./smartap.sh get             download prebuilt .bin images + source (fast)
  ./smartap.sh build q20       build the Q20 image from source (~1h)
  ./smartap.sh build cr6608    build the CR6608 image from source (~1h)
  ./smartap.sh build both      build both from source
EOF
  exit 1 ;;
esac
