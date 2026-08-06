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

## Security posture (first boot)

- **Wi-Fi is secured automatically.** On first boot, if the radios are still at the shipped
  open default, `99zz-smartap-secure-defaults` sets **WPA2-PSK with a unique random
  passphrase per unit**. It never overrides Wi-Fi you already secured. The key is surfaced
  on the boot console, in `/etc/smartap-credentials` (root, 0600), and in **Quick Settings**
  (read it over the wired LAN at `http://192.168.1.1`). Upgrade to WPA3 in Quick Settings.
- **Root SSH password is unique per unit.** On first boot `99zz-smartap-secure-defaults`
  also replaces the shared, image-extractable default root hash with a **random per-device
  password** (only when the account still carries that default — an operator-set password is
  never touched). SSH stays enabled with password auth exactly as before; this just closes
  the shared-secret hole. The password is written to `/etc/smartap-credentials` (root, 0600)
  next to the Wi-Fi key — read it in the panel over the wired LAN. If minting ever fails the
  prior valid record is left in place, so the account is never locked.
- **Recovery paths are never closed:** the wired LAN (`192.168.1.1`) and the Wi-Fi rescue
  IP `221.221.221.221` are aliases on `br-lan` and stay reachable by cable regardless of
  Wi-Fi encryption; the panel (`root`/`admin` over the LAN) is always available as recovery.
- **Panel login** stays `root` / `admin` by default and is now genuinely changeable from the
  panel (the change actually updates the credential you log in with). **Change it after first
  login.** The audit found no command injection, auth bypass or XSS in the panel/CGI code.

## What this build changes vs stock OpenWrt

- **DSA** is native on this image (the metadata even says so); the whole design is DSA.
- **38 dBm** at every software layer: driver `mt7915_eeprom_get_target_power` → 76 (=38.0),
  `regulatory.db` → 38 across 182 countries, `txpower 38` on both radios.
  `modules.d/mt7915e` loads the module **plain** (the stock driver has no cr6608 param).
- **2 LAN + WAN**: `br-lan` = lan1 + lan2; the gigabit WAN port stays free for router mode.
- **LEDs**: red:status (boot/failsafe), blue:status (running) — the device-tree defaults,
  no spurious red light on a bridged AP.
- **LuCI theme**: **Argon (Royal Obsidian)** — the same theme the CR6608 build ships, now
  vendored into this overlay (`www/luci-static/argon` + the `themes/argon` ucode templates
  + `/etc/config/argon`). `99-cr6608-argon` selects it at first boot, but only after
  asserting the assets exist, so a build without them falls back to bootstrap instead of
  pointing LuCI at a dead path. Bootstrap/-Dark/-Light stay installed and selectable.
  The Smart AP dashboard at `/` is a standalone page and is unaffected by the LuCI theme.
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

**Default (guaranteed-bootable) build:**
- applies **`kernel-build/apply-mt76-38.py`** — the source-level twin of `ko_eeprom38.py`:
  `mt7915_eeprom_get_target_power()` returns 76 (=38.0 dBm), with a `__attribute__((used))`
  proof marker the workflow greps out of the *final image* driver — so it **fails rather than
  ship an un-patched driver**.
- bakes in the identical `files/` overlay tree — minus `lib/modules`, which is recompiled
  from patched source rather than binary-patched — plus the curated package set below, then
  uploads a flashable `sysupgrade.bin` artifact (gated on the 38 dBm proof marker above).
- **stock kernel + device tree** — nothing risky is recompiled into the boot path, so a
  flashed unit always comes up.
- ships a **curated feature set** cherry-picked from what independent builds (ImmortalWrt,
  Lean, gl.inet, istoreOS) are actually loved for — see `kernel-build/jcg-q20.seed.config`:
  **SQM** (bufferbloat/latency), **WireGuard VPN**, **UPnP/NAT-PMP** (gaming NAT), **DDNS**,
  **encrypted DNS over HTTPS**, **adblock** (light, not RAM-heavy AdGuardHome), **watchcat**
  connectivity watchdog, **Wake-on-LAN**, and admin tools (opkg UI, ttyd web terminal, htop,
  nano, curl). "opkg UI" is the LuCI **package-manager** app (apk-era name). Every daemon is
  installed but **idle until you enable it**, so the default
  bridged-AP boot is unaffected. The placebo/risky "turbo" mods are deliberately excluded
  (see TUNING.md). Overlay-only builds can't add packages — this set is from-source only.

**Optional (`apply_nand_ecc = true` on the Run-workflow form):**
- **NAND ECC → 8-bit / 512** (OpenWrt **#20878**) via `kernel-build/patch-dts.py`. The Q20's
  SLC NAND is specified for 8-bit/512; stock ramips runs it at 4-bit/512, which logs
  uncorrectable-ECC under write load and is the likely root of the "يعلّق / random reset
  after a while" reports. 8-bit needs 52 ECC bytes/2 KiB page, which fits the 64-byte OOB, so
  the value is correct for this chip.
- **Why it is opt-in, not default:** whether the mt7621 on-host ECC engine accepts strength 8
  at *runtime* cannot be proven without flashing real hardware — if it were rejected the NAND
  would not attach and the unit would not boot. **Worse (community finding, Aug 2026):** the
  stock/pb-boot bootloader reads the kernel partition assuming the 4-bit layout, so a kernel
  *written* under an 8-bit layout may become unreadable to the bootloader — a brick that
  needs TTL serial (3.3 V, press `4` for the U-Boot console, `tftpboot` an initramfs) to
  recover. Also per-batch NAND differs: Winbond W29N01HV units are fine at 4-bit and gain
  nothing; only Toshiba TC58NVG1S3H units are spec'd for 8-bit — check your chip before
  even considering this. So the safe build leaves stock ECC and this is a switch you flip
  only on a bench unit with TTL access. The DT edit itself is just the two generic
  `nand-ecc-strength`/`nand-ecc-step-size` properties (no invented phandles), applied into
  the real `&nand` node and dtc-validated.

### What is deliberately NOT "fixed" (honest — no phantom fixes)
- **WAN `gmac1` fixed-link (OpenWrt #16083 / #16551)** does **not** apply to this board: the
  Q20's WAN uses a **real gigabit PHY** (`&gmac1` has `phy-handle = <&ethphy0>`), so it already
  negotiates 1000 and there is no fixed-link to add. Injecting one would *break* the WAN, so
  the DT script never touches gmac1.
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

**Before any cross-firmware conversion, back up the `Factory` partition**
(`dd if=/dev/mtd2 of=/tmp/factory.bin` — it holds the Wi-Fi calibration and both MACs at
`0x3fff4`/`0x3fffa`). Third-party firmwares (Padavan/iKuai conversions) have been seen
overwriting it; without the backup that means permanently dead Wi-Fi and garbage MACs.
For recovery prefer **pb-boot web recovery** (power off → hold reset → power on → release
after ~5 s → http://192.168.1.1) — at least one OEM-modified stock U-Boot has been reported
to *erase NAND* when entering its own recovery mode, so avoid it.

The WAN/LAN ports also carry a runtime fix for the MT7530 broken-EEE link flapping against
100 Mbps partners (openwrt #22464): `50-smartap-eee-off` disables EEE per port as it
registers, with a boot-time sweep in `smartap-perf` as backup.
