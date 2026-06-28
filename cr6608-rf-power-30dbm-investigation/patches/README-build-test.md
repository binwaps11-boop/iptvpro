# Build test — ceiling-raise patch (TEST ONLY, does not deliver real 30 dBm)

This patch exists so you can **empirically prove** whether any clean headroom exists above the
EEPROM cal target. It raises the *requested* power ceiling and prints a `CR6608-RF-30DBM-TEST`
marker to dmesg. The PA's physical P1dB still applies — see `../reports/VERDICT.md`.

> Do not flash this expecting 30 dBm. Flash it, run Phase 4, read the truth. Then revert.

## Apply to an OpenWrt 24.10 tree

```sh
# 1. Get the tree and select the CR6608 target/profile (Filogic MT7981+MT7915e):
git clone -b openwrt-24.10 https://github.com/openwrt/openwrt
cd openwrt
./scripts/feeds update -a && ./scripts/feeds install -a

# 2. Drop the patch into the mt76 package so it applies during build:
mkdir -p package/kernel/mt76/patches
cp ../999-cr6608-rf-ceiling-test.patch package/kernel/mt76/patches/

# 3. Configure for the exact CR6608 device, then build:
make menuconfig        # Target: MediaTek Filogic; select the Xiaomi CR6608 profile + kmod-mt7915e
make -j$(nproc) V=s

# 4. Verify the marker compiled in and (after flashing) appears at runtime:
dmesg | grep CR6608-RF-30DBM-TEST
```

## Pass/fail
- **PASS** only if `../results/phase4-before-after-TEMPLATE.md` shows higher power **with** improved
  signal/bitrate and no rise in retries/failed and no thermal throttle and (if measurable) clean
  spectrum. Otherwise it is **clipping** → revert to stock firmware.
- The marker proves the patch is live; it does **not** prove RF improved. Only Phase 4 does.

## Revert
Reflash a stock/unpatched OpenWrt 24.10 image. The driver patch lives only in this image; it is not
persistent across a clean flash. (No EEPROM was modified by this patch.)
```
