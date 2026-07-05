# OpenWrt 24.10.6 from source — Xiaomi CR6608 build kit

Builds a custom OpenWrt **24.10.6** firmware for the **Xiaomi CR6608**
(SoC MediaTek MT7621, target `ramips/mt7621`, device profile
`xiaomi,mi-router-cr6608`) on your own Ubuntu machine.

It bakes in:

- the **complete v85 Smart AP overlay** (`files/`, ~293 files): the full dashboard
  (`/www/dashboard.js`, `/www/index.html`, all `/www/cgi-bin/*` CGIs), the patched LuCI
  assets (`ui.js`/`luci.js` single "final apply" button, `controller/admin/uci.uc`
  server-side final-apply, argon theme, `version.lua` cache-bust), the Quick Settings
  view, every `/etc/config/*`, the performance-pack sysctl, all `cr6608-*`/`smartap-*`
  services + scripts + uci-defaults + hotplug, the patched `regulatory.db` (36 dBm,
  no DFS), `/etc/modprobe.d/mt7915e.conf`, and the `cr6608-eeprom-power` tool. The
  built image is therefore **identical in design and features to v85**.
- an **mt76 driver patch** (`999-mt7915-cr6608-rf-35dbm.patch`) that lifts the
  driver-side TX-power SKU/target ceiling to **35 dBm on both bands**.

Because `build.sh` pins the **same** OpenWrt tag (`v24.10.6`) that v85 was built from,
the overlaid LuCI/`ui.js`/`luci.js`/`uci.uc` files match the freshly built LuCI version
exactly — no version mismatch.

```
ubuntu-build/
├── build.sh                # the one script you run
├── cr6608.seed.config      # diffconfig seed fed into .config
├── README.md               # this file
├── patches/
│   └── 999-mt7915-cr6608-rf-35dbm.patch
└── files/                  # the full v85 overlay, baked verbatim into the rootfs
    ├── etc/config/{network,system,wireless}
    ├── etc/modprobe.d/mt7915e.conf
    ├── lib/firmware/        # put your binary regulatory.db here (see below)
    ├── usr/sbin/set-txpower
    └── www/cr6608.html
```

---

## 1. Prerequisites

- **Ubuntu 22.04 or 24.04** (native or a VM/WSL2), x86-64.
- **Internet access** (clones OpenWrt, feeds, and ~hundreds of source tarballs).
- **~30–60 GB free disk**. A full first build produces a large `build_dir`,
  `staging_dir`, toolchain, and downloads. 60 GB is comfortable.
- **Time: a few hours.** The toolchain + kernel + packages compile from
  scratch the first time. Rebuilds are much faster.
- **Do NOT run as root.** OpenWrt's buildroot refuses to build as root. The
  script only uses `sudo` for the one `apt-get install` step.
- A few GB of RAM; 8 GB+ recommended for a parallel build.

The dependencies installed by the script are:

```
build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
gettext git libncurses-dev libssl-dev python3-setuptools rsync swig
unzip zlib1g-dev file wget
```

---

## 2. (Optional) provide your own regulatory.db

`regulatory.db` is a **binary** file, so it is not shipped as text in this kit.

- If you want a specific regdb, drop it at
  **`files/lib/firmware/regulatory.db`** (and optionally `regulatory.db.p7s`).
- If you leave it empty, `build.sh` **automatically downloads the official
  wireless-regdb copy** so the image still ships a valid one.

See `files/lib/firmware/README.regulatory.txt` for how to build a custom regdb.
Note the honest limits in section 6.

---

## 3. Build

```bash
cd cr6608-kit
./build.sh
```

The script runs nine clearly-labelled steps:

1. install Ubuntu build deps (`sudo apt-get install …`)
2. `git clone` OpenWrt and `git checkout v24.10.6`
3. `./scripts/feeds update -a && ./scripts/feeds install -a`
4. copy the mt76 patch into `package/kernel/mt76/patches/`
5. ensure a `regulatory.db` exists (fetch if you didn't supply one)
6. copy `files/` into the buildroot `files/` overlay
7. write the seed `.config`, then `make defconfig`
8. `make download -j8`
9. `make -j$(nproc)`; on any failure it retries `make -j1 V=s` so you can
   see exactly which package broke.

`set -euo pipefail` plus an `ERR` trap means the script stops at the first
failure and tells you the line and command that failed.

### Output

When it finishes, the images are in:

```
openwrt/bin/targets/ramips/mt7621/
```

The file you flash is the **sysupgrade** image, named like:

```
openwrt-24.10.6-ramips-mt7621-xiaomi_mi-router-cr6608-squashfs-sysupgrade.bin
```

(There is also a `…-squashfs-factory.bin` for initial installs from stock.)

---

## 4. Flashing

> Flashing is at your own risk and can brick the device. Have a UART/TFTP
> recovery plan (serial console + `mtd`/U-Boot recovery) before you start.

If the router already runs OpenWrt (`sysupgrade`, keep or wipe settings):

```bash
scp openwrt-24.10.6-…-cr6608-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1
sysupgrade -v /tmp/openwrt-24.10.6-…-cr6608-squashfs-sysupgrade.bin
# add -n to NOT keep settings
```

Or via **LuCI → System → Backup / Flash Firmware → Flash new firmware image**.

Coming from **stock Xiaomi firmware** you first need the documented CR6608
exploit / U-Boot / TFTP procedure to get an OpenWrt image on at all — follow
the device page on the OpenWrt wiki. The `…factory.bin` is for that first
install; `…sysupgrade.bin` is for updates once OpenWrt is running.

After boot, the router is at **192.168.1.1** (see `files/etc/config/network`).

---

## 5. What the overlay does / how to use it

- `files/etc/config/wireless` sets up 2.4 + 5 GHz APs with WPA3 (SAE-mixed).
  **Change the SSIDs and keys** before shipping to real use.
- `files/usr/sbin/set-txpower` — request a TX power ceiling at runtime:
  ```
  set-txpower phy0 30      # request 30 dBm on phy0
  set-txpower              # apply 30 dBm to every phy
  iw phy0 info | grep txpower   # read back what the kernel ACTUALLY allows
  ```
- `files/etc/modprobe.d/mt7915e.conf` — module options for `mt7915e`.
- `files/www/cr6608.html` — reachable at `http://192.168.1.1/cr6608.html`.

---

## 6. HONEST section — read this before chasing "35 dBm"

Building from source genuinely lets you change three things that a stock
binary won't let you touch:

1. **the driver** (the mt76 patch here raises the driver-side power ceiling),
2. **the regulatory database** (`regulatory.db` — the legal/reg ceiling), and
3. **the DTS / device tree** (antenna gain, per-chain calibration hints).

**But none of that changes physics.** The ceiling is not the output. On the
CR6608 the actual radiated power is bounded by the **MT7915 power-amplifier
hardware**:

- **~20–22 dBm conducted** output per chain is about what the internal PAs
  can produce, roughly independent of what number you type in.
- **~30 dBm EIRP** is the practical ceiling once antenna gain is included.
- The **"35"** you may have seen is a **requested ceiling**, not a physical
  output level. The driver/regdb clamp to the *lowest* of {reg limit, driver
  cap, calibrated PA target}, and the PA target wins because it is hardware.

So you can raise every software cap to 35 and `iw … info` may even print a
higher number, yet a spectrum analyzer / real throughput will still show
~20–22 dBm conducted. Pushing the PA past its calibrated target mostly buys
you **heat, distortion (EVM), spectral regrowth, and a shorter chip life** —
not more usable range.

**The only way to real higher power is more/better hardware:**

- an **external PA** (a separate amplifier stage after the MT7915), and/or
- **higher-gain antennas** (raises EIRP without pushing the PA harder), and
- respecting the **legal EIRP limits for your country and band** — exceeding
  them is illegal in most jurisdictions and your responsibility.

Treat this kit as: "unlock the software ceilings and ship a clean custom
image," **not** "make a stock CR6608 transmit at 35 dBm." It can't.

---

## 7. Regenerating the patch (if it fails to apply)

The mt76 patch context targets the mt76 revision pinned by v24.10.6. If OpenWrt
bumped mt76 and the hunk fails, regenerate it with quilt:

```bash
cd openwrt
export QUILT_PATCHES=patches
make package/kernel/mt76/{clean,prepare} V=s QUILT=1
cd build_dir/target-*/linux-*/mt76-*/
quilt push -a            # apply existing patches
quilt new 999-mt7915-raise-txpower-ceiling.patch
quilt add mt7915/init.c
# ...edit mt7915/init.c to add the ceiling boost...
quilt refresh
# copy the refreshed patch back over patches/999-...patch in this kit
```

---

## 8. Rebuilding / cleaning

```bash
cd openwrt
make -j$(nproc)                 # incremental rebuild
make package/kernel/mt76/clean  # rebuild just mt76 after editing the patch
make dirclean                   # nuke build_dir/staging_dir (keeps .config + dl)
```
