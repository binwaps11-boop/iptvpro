# KT412 — Custom OpenWrt Firmware Kit

**Device:** KT GiGA WiFi home = **Dongwon T&I DW02‑412H**
**Confirmed from OpenWrt source** (`target/linux/ath79/image/nand.mk`, `.../nand/base-files/etc/board.d/02_network`).

> ⚠️ The Claude Code sandbox that generated this kit **cannot build the `.bin`**:
> its network policy blocks `downloads.openwrt.org`, `dl.openwrt.ai`,
> `firmware-selector.openwrt.org`, `git.openwrt.org`/`sources.openwrt.org`
> (only github.com + pypi are reachable). So no ImageBuilder/SDK/source build can run here.
> A fabricated binary would be dangerous, so this kit gives you the **exact, verified recipe**
> and **all real config/scripts** — you generate the actual `.bin` in ~5 min (two easy ways below).

---

## 1. Device analysis (authoritative)

| Item | Value |
|------|-------|
| target / subtarget | **ath79 / nand** |
| profile | `dongwon_dw02-412h-64m` **or** `dongwon_dw02-412h-128m` |
| SoC | Qualcomm Atheros **QCA9557** (MIPS 74Kc ~720 MHz) |
| RAM | DDR2 **128 MB** (both variants) |
| Flash | SPI‑NOR 2 MB (u‑boot/art) + **NAND 64 MB or 128 MB** (rootfs/UBI) |
| Switch | **QCA8337N**, `swconfig` (NOT DSA), device `switch0` |
| Ports | **1× WAN + 4× LAN**, all Gigabit |
| Wi‑Fi 2.4G | QCA9557 WMAC → `ath9k` ✅ |
| Wi‑Fi 5G | QCA9882 (988x) → `ath10k-ct` ✅ (802.11ac) |
| Kernel partition | 8 MB ; image budget 48 MB (64M) / 112 MB (128M) |

**Physical port map (from official `board.d`):**
```
switch0:  0@eth0(CPU)   1:WAN   2:LAN4   3:LAN3   4:LAN2   5:LAN1
LAN  = eth0.1 (VLAN1, ports 2-5)     WAN = eth0.2 (VLAN2, port 1)
```

### Straight answers to the spec questions
- **DSA or swconfig?** → **swconfig**. VLANs via `config switch_vlan`; `swconfig dev switch0 show` works.
- **p1‑p4 only, or p5?** → There is **no separate p5 management port**. The 5 jacks are **WAN + LAN1‑4**. The 5th jack is WAN, not management. We did **not** invent a p5. Management `192.168.100.1` lives on `br-lan` (the 4 LAN ports) — safe.
- **Wi‑Fi supported?** → **Yes, dual‑band 11ac** (ath9k + ath10k‑ct). Real Tx power is whatever `iwinfo` reports (regdomain‑limited). We never show fake numbers and never touch EEPROM/caldata.
- **64M vs 128M?** → cannot be known remotely; check **on the device**: `cat /proc/mtd` → size of the `ubi` partition (≈0x3C00000 = 64M, ≈0x7C00000 = 128M). Pick the matching profile. **Flashing the wrong size image can fail/brick — so confirm this one fact.**

### Likely root causes of hangs/reboots on this device (general, confirm via `verify-all.sh`)
- **Heavy LuCI apps** (collectd/statistics, big charts, fast auto‑refresh) eat the 128 MB RAM → OOM/sluggish. → excluded here.
- **conntrack table too large** for 128 MB → OOM under many connections. → capped to 16384 in `sysctl.d`.
- **Unbounded logs** filling RAM/flash. → `log_size=64` + small dnsmasq cache.
- **PPPoE without MSS clamp** → stalled large packets. → `mtu_fix '1'` on wan zone.

---

## 2. Build the real `.bin` (pick ONE)

### Option A — OpenWrt Firmware Selector (easiest, builds server‑side)
1. Open <https://firmware-selector.openwrt.org/>
2. Search **`DW02-412H`** → pick the variant matching your flash (**64M** or **128M**).
3. Click **“Customize installed packages…”** and paste the list from `packages.txt`
   (the non‑comment lines).
4. *(Optional but recommended)* It can’t bake the `files/` overlay, so after flashing,
   copy the configs/scripts from `files/` via SCP, or just run `build.sh` (Option B) which
   **does** bake `files/` in. For the Selector path, apply configs post‑flash (see step 6 below).
5. Download → you get a real `…-sysupgrade.bin`. Rename to
   `openwrt-kt412-custom-sysupgrade.bin`.

### Option B — ImageBuilder via `build.sh` (bakes in all configs/scripts) ✅ recommended
On any Linux x86_64 box with normal internet:
```bash
cd openwrt-kt412
PROFILE=dongwon_dw02-412h-64m  VERSION=23.05.5  ./build.sh    # or -128m
```
Outputs to `openwrt-kt412/output/`:
- `openwrt-kt412-custom-sysupgrade.bin`
- `openwrt-kt412-custom-factory.img` (only needed for first install from stock)
- `openwrt-kt412-custom.manifest` (full package list w/ versions)
- `SHA256SUMS`

`build.sh` automatically applies **`packages.txt`** and the **`files/`** overlay
(default LAN 192.168.100.1, firewall/NAT, mwan3, dnsmasq, sysctl, wifi template,
custom-command buttons, and the `/root/verify-*.sh` scripts).

---

## 3. Backup → Flash → Verify

```bash
# 0) BACKUP first (keep it off-device!)
sysupgrade -b /tmp/backup-kt412.tar.gz
scp root@192.168.100.1:/tmp/backup-kt412.tar.gz ./

# 1) copy image to device
scp openwrt-kt412-custom-sysupgrade.bin root@<current-ip>:/tmp/

# 2) check it matches the device first (board name MUST contain dw02-412h)
ssh root@<current-ip> 'cat /tmp/openwrt-kt412-custom-sysupgrade.bin >/dev/null; \
   ubus call system board | grep -i board_name; cat /proc/mtd'

# 3) FLASH (-n = do NOT keep settings; our defaults take over cleanly)
sysupgrade -v -n /tmp/openwrt-kt412-custom-sysupgrade.bin
#   (omit -n if you want to KEEP current /etc/config instead of our templates)
```

After reboot, log in at **http://192.168.100.1** (root, no password → set one immediately).

---

## 4. Recovery (you have serial — lowest risk)
If a flash ever fails:
1. **Serial console** (3.3V UART, 115200 8N1). Interrupt U‑Boot (`Hit any key…`).
2. Use U‑Boot to TFTP the **factory.img** (or an OEM/stock image) back:
   typical flow — `setenv ipaddr 192.168.1.1; setenv serverip 192.168.1.2; tftpboot 0x82000000 factory.img; nand erase …; nand write …`
   (exact addresses come from `printenv` / `bdinfo` on your unit — capture them now, before flashing).
3. Failing factory.img install → reflash OpenWrt sysupgrade in **failsafe**: power‑cycle, press **Reset** when the LED flashes, `telnet 192.168.1.1`, then `sysupgrade -n …`.
> Capture `printenv` + boot log over serial **before** you flash — that’s your recovery map.

---

## 5. Post‑flash checklist
- [ ] `http://192.168.100.1` opens; set root password.
- [ ] `cat /proc/mtd` ubi size matches the variant you flashed.
- [ ] `/root/verify-all.sh` clean (no panic/OOM/reset in logs).
- [ ] `/root/verify-ports.sh` → WAN + LAN1‑4 link/speed correct.
- [ ] `/root/verify-wan.sh` → WAN got IP, ping 1.1.1.1 & 8.8.8.8 OK.
- [ ] `/root/verify-services.sh` → network/firewall/dnsmasq/uhttpd/dropbear up.
- [ ] LAN client gets DHCP, can browse.
- [ ] (Wi‑Fi) enable in Quick Setup, set country, `/root/verify-wifi.sh` shows real Tx power.

---

## 6. What the UI gives you (all real, all official LuCI — nothing fake)
See **[UI-GUIDE.md](UI-GUIDE.md)** for the full walkthrough of Dashboard, Quick Setup,
Port Control, WAN Manager, VLAN Manager, Health Monitor — mapped to the **official LuCI
pages + `luci-app-mwan3` + the custom‑command buttons**, so every button executes a real action.
