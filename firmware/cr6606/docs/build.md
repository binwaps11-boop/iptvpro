# Build guide (B, C, D)

## B) Version recommendation
Use the **latest stable OpenWrt release** (24.10.x at time of writing; check
https://openwrt.org for the current stable). Avoid `snapshot` for a daily-driver
router — snapshots don't ship LuCI by default and change kernels frequently
(stability risk). The CR6606 has been supported in mainline since Feb 2022, so the
stable release fully covers it.

Set the version in `build/imagebuilder-build.sh` via `VER=` (defaults to 24.10.0;
bump to the current stable).

## C) Target / subtarget / profile
| Field     | Value |
|-----------|-------|
| target    | `ramips` |
| subtarget | `mt7621` |
| profile   | `xiaomi_mi-router-cr6606` |
| image     | NAND sysupgrade (`...-squashfs-sysupgrade.bin`) |

Confirm the exact profile name on your version:
```sh
make info | grep -i cr6606          # in the ImageBuilder dir
```

## D) ImageBuilder vs full Build System
**Use ImageBuilder.** Everything you asked for — LuCI, PPPoE, VLAN, diagnostics,
Wi-Fi tools, watchdog/health scripts, default configs — is package selection +
`files/` overlay. No source patches required.

Use the **full Build System only if** you later need a *source* change (custom
kernel config, a driver patch, a package not in the feeds). You do not need it now.

### Build it (on a Linux PC, not the router)
```sh
cd firmware/cr6606
chmod +x build/*.sh files/etc/uci-defaults/* files/etc/health/*
# EDIT FIRST: files/etc/uci-defaults/99-custom-defaults  (country, tz, ssid, pw)
./build/imagebuilder-build.sh
```
Output: `~/owrt-build/<imagebuilder>/bin/targets/ramips/mt7621/*sysupgrade.bin`.
**This only creates a file. It flashes nothing.** Flashing = `docs/recovery.md`.

## E) Packages
See `build/packages.txt`. Lean by design; `luci-app-statistics` + collectd are the
only "nice to have" — delete those 4 lines if you want it even smaller.
