# SmartAP Q20 — custom firmware for the JCG Q20

Built on the **official OpenWrt 25.12.5 (r33051-f5dae5ece4)** JCG Q20 sysupgrade image.
The Q20 is **MT7621 + MT7915** (one DBDC chip on pcie1) — the same silicon as the Xiaomi
CR6608 at the same OpenWrt revision, so the whole SmartAP design ports directly.

## Rebuild it yourself (no toolchain, Python 3 only)

```sh
./build-q20.sh openwrt-25.12.5-ramips-mt7621-jcg_q20-squashfs-sysupgrade.bin
```

That extracts the stock image, overlays `files/`, binary-patches the driver to 38 dBm
(`tools/ko_eeprom38.py`), raises the regulatory database (`tools/regdb38.py`), repacks the
squashfs and re-appends the fwtool trailer with a recomputed CRC. The **kernel is kept
byte-identical** — nothing here rebuilds it.

## What this build changes vs stock OpenWrt

- **DSA** is native on this image (the metadata even says so); the whole design is DSA.
- **38 dBm** at every software layer: driver `mt7915_eeprom_get_target_power` → 76 (=38.0),
  `regulatory.db` → 38 across 182 countries, `txpower 38` on both radios.
  `modules.d/mt7915e` loads the module **plain** (the stock driver has no cr6608 param).
- **2 LAN + WAN**: `br-lan` = lan1 + lan2; the gigabit WAN port stays free for router mode.
- **LEDs**: red:status (boot/failsafe), blue:status (running) — the device-tree defaults,
  no spurious red light on a bridged AP.
- **LuCI theme**: bootstrap (argon assets are not on this board).
- The full **Smart AP dashboard**, MU-MIMO / beamforming / HE40+HE80, session auth, the
  login→Smart-AP redirect, and the five security/correctness fixes from the CR6608 audit.

## Two levels of build

**1. Overlay build (this folder, `build-q20.sh`) — no toolchain, instant.**
Everything above. It keeps the stock kernel byte-identical, so it cannot touch anything
that lives in the kernel or the device tree.

**2. From-source build (`kernel-build/` + `.github/workflows/build-jcg-q20.yml`) — recompiles
the kernel, fixes the device-tree bugs the overlay physically cannot.**
Run it on GitHub Actions (Actions → *Build SmartAP Q20 (from source …)* → Run workflow).
Ubuntu runners have the open internet and toolchain this sandbox lacks. It:

- applies **`kernel-build/patch-dts.py`** to `mt7621_jcg_q20.dts`:
  - **NAND ECC → 8-bit / 512** (OpenWrt **#20878**). The Q20's Toshiba TC58NVG1S3H SLC NAND
    *requires* 8-bit/512 ECC; stock ramips brings it up at 4-bit/512, which logs
    uncorrectable-ECC under write load and is the root of the "يعلّق / random reset after a
    while" reports. **This is the single most important fix for stability** and it is only
    reachable by rebuilding the kernel.
  - **WAN `gmac1` → 1000/full fixed-link** (OpenWrt **#16083 / #16551**) — stable gigabit WAN.
- applies **`kernel-build/apply-mt76-38.py`** — the source-level twin of `ko_eeprom38.py`:
  `mt7915_eeprom_get_target_power()` returns 76 (=38.0 dBm), with a grep-gated proof marker
  so the workflow *fails* rather than ship an un-patched driver.
- bakes in the identical SmartAP overlay and uploads a flashable `sysupgrade.bin` artifact.

### What is deliberately NOT "fixed"
- **WED / hardware flow-offload (OpenWrt #868)** is an **MT7622 / MT7986 / MT7981** feature.
  The Q20's **MT7621 has no WED block at all**, so there is nothing to enable — claiming a
  WED build for this SoC would be false. Throughput on MT7621 comes from software NAT
  acceleration (already on) + the RF config, not WED.

## Honest note on power

38 dBm is *requested* at every layer, but the MT7915 power amplifier saturates near
26 dBm — real radiated power is PA-bound, exactly as measured on the CR6608 (26/32/38
builds were indistinguishable). Real range comes from HE40, MU-MIMO, correct RF config and
placement, not the number. `tools/ko_eeprom38.py --dbm N` lets you sweep the target.

## Recovery

If a build misbehaves, flash the stock JCG Q20 image back over the LAN cable. This build
never touches the bootloader or the Factory/EEPROM partition.
