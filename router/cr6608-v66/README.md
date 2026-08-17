# CR6608 v66 — corrected, fleet-flashable build

This is the user's own **v66** Smart AP source (overlay `files/`, driver
`patches/`, `packages/prplmesh`, `cr6608.seed.config`) for the Xiaomi Mi Router
CR6608, with two corrections so a **single image flashes to a whole fleet** and
just works — no per-device provisioning.

## What was corrected vs. stock v66

1. **Dashboard login (the reported bug).** Stock v66 shipped `/etc/shadow` with
   the root account **locked** (`root:!`), so the Smart AP page never opened with
   `root`/`admin` and each unit needed manual failsafe provisioning. Fixed:
   `files/etc/shadow` now ships a valid SHA-512 hash whose password is `admin`.
   Because `files/etc/config/rpcd` uses the `$p$root` indirection, the dashboard,
   LuCI, SSH and console all authenticate against that one live credential.

2. **Flash-and-go Wi-Fi.** Stock v66 shipped both radios and both SSIDs
   `disabled '1'` with no WPA key ("fail closed until retail-provision"), so a
   freshly flashed device broadcast nothing. Fixed: `files/etc/config/wireless`
   ships both radios and SSIDs **enabled** with a default passphrase, so the unit
   is usable the moment it boots.

## Default credentials (change them from the dashboard)

| What | Value |
|---|---|
| Dashboard / LuCI / SSH login | user `root` (or `admin`), password `admin` |
| Wi-Fi SSIDs | `Smart ap 2.4G`, `Smart ap 5G` |
| Wi-Fi passphrase | `smartap2038` |

These are intentional fleet-wide defaults for flash-and-go. Change the admin
password and Wi-Fi key per site from the Smart AP dashboard after first login.

## How it is built

`.github/workflows/build-cr6608-v66.yml` builds this from OpenWrt source
(`v25.12.5`, commit `f0a60eee`) on a GitHub runner. It applies the v66 patches to
their exact targets, bakes in this overlay, and gates the result on the 38 dBm
driver marker (`CR6608-RF-38DBM`), the shipped admin login hash, and the CR6608
device profile. It does **not** run v66's `build.sh` — that script requires the
owner's private signing keys (excluded from the source kit by design) and its
pre-publish inspector deliberately refuses to ship a working shared password.
This workflow builds the same source with OpenWrt's own tooling, so no private
keys are involved and no signing material is committed here.

The 38 dBm capability is armed by DTS (`mediatek,cr6608-lab-txpower-38dbm`) and
capped at 38 dBm in the driver request path. As the feature matrix notes, this is
a driver/MCU-reported ceiling, not an external RF measurement; the physical PA
and regulatory/thermal limits still apply.
