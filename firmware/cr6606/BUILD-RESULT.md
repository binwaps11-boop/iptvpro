# CR6606 — official build result

Built with the **official OpenWrt ImageBuilder** on GitHub Actions.
Latest build (run #3, [27921078563](https://github.com/binwaps11-boop/iptvpro/actions/runs/27921078563))
sets `txpower '30'` on both radios = "request maximum". The mt7915 driver clamps
it to the legal+calibrated cap (real ~20-23 dBm, visible in `iwinfo`). No reghack,
no EEPROM/ART/calibration edits, no faked numbers.

## (A) Build identity
| Field | Value |
|-------|-------|
| OpenWrt release | **25.12.4** (current stable) |
| target / subtarget | `ramips` / `mt7621` |
| profile | `xiaomi_mi-router-cr6606` |
| build method | ImageBuilder (no source patches needed) |

## (H) Files produced — which is which

> ✅ You are already on OpenWrt → use the **sysupgrade** file.
> The `firmware.bin` is only for going from **stock Xiaomi → OpenWrt** (initial install). Don't use it to upgrade.

| File | Role | SHA256 |
|------|------|--------|
| `openwrt-25.12.4-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin` | **SYSUPGRADE — flash this** (txpower=30 request) | `01a8c4943198bf8fab70d136fedacfe03d02192baf0b4d9793f022cecbe0872d` |
| `openwrt-25.12.4-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-firmware.bin` | FACTORY / initial-install (stock→OpenWrt only) | `31de9d75a4cb93a5b81222b7c27799966b5783ba408ab11fc84c3a548dfaf843` |
| `openwrt-25.12.4-ramips-mt7621-xiaomi_mi-router-cr6606.manifest` | package manifest | — |
| `build.log` | full build log | — |
| `SHA256SUMS.txt` | checksums | — |

## Download
GitHub → **Actions** → run *Build CR6606 OpenWrt image* →
**Artifacts** → `cr6606-firmware-25.12.4` (a zip; sign in to GitHub to download).
Direct: https://github.com/binwaps11-boop/iptvpro/actions/runs/27921078563

## (6) Backup BEFORE flashing — ✅ SAFE (run on router)
```sh
sysupgrade -b /tmp/backup-cr6606.tar.gz
# copy it off the device:
#   scp root@192.168.100.1:/tmp/backup-cr6606.tar.gz ./
```

## Verify the file — ✅ SAFE (run on router, after copying the .bin to /tmp)
```sh
sha256sum /tmp/openwrt-25.12.4-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin
# MUST equal:
# 01a8c4943198bf8fab70d136fedacfe03d02192baf0b4d9793f022cecbe0872d
```

## (5) Flash — 🔴 DANGEROUS (only after backup + checksum match)
```sh
sysupgrade -v -n /tmp/openwrt-25.12.4-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin
#   -n = don't keep old config, so our /etc/uci-defaults take effect.
#   Router reboots; LAN becomes 192.168.100.1. Do NOT power off during flash.
```

## (7) Recovery if it doesn't boot
See `docs/recovery.md` §N: failsafe mode (reset button → 192.168.1.1, `firstboot`),
or TFTP/U-Boot recovery per the OpenWrt CR6606 device page. Your saved
`backup-cr6606.tar.gz` restores settings; the `firmware.bin` above re-installs
OpenWrt if needed. Bootloader/factory/ART are never touched.
```
