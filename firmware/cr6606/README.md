# Xiaomi Mi Router CR6606 — Custom OpenWrt Firmware Kit

> Personal device only. No bootloader changes, no factory/ART/EEPROM/calibration
> writes, no MAC overwrite, no regulatory bypass, no reghack. Everything here is
> stable-first and legal-first.

## ⚠️ STATUS: NOT READY TO FLASH YET

Two inputs are still required before the **final flashing command** is produced:

1. **Your live diagnostic outputs.** Run `build/00-collect-diagnostics.sh` on the
   router (or paste the outputs of the script you already have). Save the result to
   `docs/diagnosis-REPORT.md`. The hardware facts below are verified for the
   CR6606 model in general, but your *channels, country, txpower table, port
   indexes, and log errors* are unit/environment specific and must be read from
   YOUR device — not guessed.
2. **Your country / regulatory domain** (e.g. `US`, `DE`, `GB`, `PK`, ...). This
   legally determines channels and max txpower. Files currently ship with the
   safe placeholder `country '00'` (world). Set your real ISO code before relying
   on coverage.

Until both are provided, treat `docs/recovery.md` § "Safe sysupgrade" as **draft**.

---

## Verified hardware facts (CR6606)

| Item            | Value |
|-----------------|-------|
| SoC             | MediaTek **MT7621AT** (dual-core MIPS 1004Kc, 880/900 MHz) |
| RAM             | 256 MB DDR3 |
| Flash           | 128 MB **NAND** (ESMT F59L1G81MB) |
| Switch          | MT7530 (integrated) → **DSA** in OpenWrt (not swconfig) |
| Wi-Fi           | MT7905DAN + MT7975DN = MT7915 family, driver **mt7915e / mt76** |
| 2.4 GHz         | 2x2, AX, up to 574 Mbps |
| 5 GHz           | 2x2, AX, up to 1201 Mbps |
| Ethernet        | 4× Gigabit (1× WAN + 3× LAN, confirm indexes from YOUR `ip link`) |
| OpenWrt target  | `ramips` / subtarget `mt7621` |
| OpenWrt profile | `xiaomi_mi-router-cr6606` |
| USB             | none |

Class: Xiaomi AX1800 (CR660x carrier series).

## Deliverables map (A–O)

| Item | Where |
|------|-------|
| A Full diagnosis report      | `docs/diagnosis-template.md` → fill into `docs/diagnosis-REPORT.md` |
| B Version recommendation     | `docs/build.md` |
| C Target/subtarget/profile   | `docs/build.md` (ramips/mt7621/xiaomi_mi-router-cr6606) |
| D ImageBuilder / BuildSystem | `build/imagebuilder-build.sh`, `docs/build.md` |
| E Package list               | `build/packages.txt` |
| F uci-defaults               | `files/etc/uci-defaults/99-custom-defaults` |
| G network (DSA)              | device-default DSA layout (lan1/lan2/lan3 + wan), LAN IP set by uci-defaults |
| H wireless template          | `templates/wireless.txt` (reference) + applied live by uci-defaults |
| I firewall template          | `files/etc/config/firewall` |
| J VLAN templates             | `templates/network-vlan-*.txt` |
| K PPPoE / broadband templates| `templates/network-pppoe.txt`, `templates/network-static-wan.txt` |
| L Backup commands            | `docs/recovery.md` |
| M Safe sysupgrade            | `docs/recovery.md` |
| N Recovery steps             | `docs/recovery.md` |
| O Post-flash test checklist  | `docs/post-flash-checklist.md` |
| Wi-Fi power truth            | `docs/txpower-explained.md` |

## Quick start (after both inputs are provided)

```sh
# on a Linux PC, NOT on the router
cd firmware/cr6606
./build/imagebuilder-build.sh          # produces a sysupgrade image, flashes nothing
# then follow docs/recovery.md for backup + sysupgrade
```
