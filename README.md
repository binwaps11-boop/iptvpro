# KT412 — Custom OpenWrt Firmware (Dongwon DW02-412H)

This repository contains **only the verified KT412 firmware build** (KT GiGA WiFi home
= Dongwon T&I DW02-412H, ath79/nand, QCA9558/QCA9557, swconfig, dual-band Wi-Fi).

## Contents
- **`openwrt-kt412/`** — the build kit:
  - `kt412-all-in-one.sh` — one-shot: build custom `factory.img` + `sysupgrade.bin` + TFTP flash code
  - `build.sh`, `packages.txt`, `files/` — ImageBuilder recipe + baked-in light config
  - `setup-kt412.sh` — apply full KT412 config on a running OpenWrt
  - `RECOVERY.md` — U-Boot / initramfs recovery
  - `README.md`, `UI-GUIDE.md` — analysis, build, flash, UI guide
- **`.github/workflows/build-kt412.yml`** — CI that builds the firmware and publishes the
  **Release** (`kt412-fw` tag) with `factory.img`, `sysupgrade.bin`, `initramfs-kernel.bin`,
  manifests and SHA256 for both 64m/128m variants.

## Get the firmware
Download from the Release: <https://github.com/binwaps11-boop/iptvpro/releases/tag/kt412-fw>

## Flash (correct method)
- `factory.img` / `initramfs-kernel.bin` → via U-Boot TFTP.
- `sysupgrade.bin` → **only** via the `sysupgrade` command on a running system (never raw via U-Boot).

Default after flashing the custom image: **http://192.168.100.1**.

Policy: keep only the correct build — any incorrect build is removed.
