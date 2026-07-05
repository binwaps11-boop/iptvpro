# CLAUDE.md — CR6608 OpenWrt Build Team (master instructions)

This repository builds custom OpenWrt firmware for the **Xiaomi CR6608**
(SoC MediaTek **MT7621**, radio **MT7915 AX1800 2×2 DBDC**, driver **mt76/mt7915e**,
OpenWrt **24.10.6**, kernel **6.6.127**). Role in the field: **Access Point** behind a
Mikrotik router.

Do **not** treat requests as a chat. Treat every change as an engineering process:
**read → back up → edit build system → build candidate → inspect image → flash →
verify on the real router → release gate → report.** A `.bin` is only `final` after
runtime proof from the device.

---

## Owner hard rules (never violate)
1. **TX power = 30 dBm** on both radios — the real hardware ceiling. Never raise the
   request to a fake higher number, never reduce power below 30.
2. **Never drop far clients** — no `disassoc_low_ack=1`, no min-rate culling that kicks
   weak clients, keep `max_inactivity` high.
3. **Wi-Fi stays OPEN** (`encryption 'none'`) unless the owner explicitly sets a key.
4. **No automatic reboots.** Prefer changes that apply without a reboot.
5. **Never touch EEPROM / Factory / calibration without a full backup + explicit
   warning** (see Recovery And Backup Engineer).
6. **No fake numbers.** A value shown in UI/UCI/regdb is a *request*; the *real* value
   must be proven by runtime commands on the device.

## The hardware-limit truth (state it honestly, every time it matters)
Emitted power = `min(txpower request, regdb, driver SKU, EEPROM target, PA/FEM)`.
On this 2×2 MT7915 the **PA caps real output at ~20–22 dBm conducted / ~30 dBm EIRP**.
No firmware, regdb, driver patch, or EEPROM edit can radiate 35 dBm — that needs an
external PA or higher-gain antennas. The **link rate 1200 Mbps** (5G) comes from
HE80 + 2 spatial streams + short-GI, and is independent of the power number.

---

## The team (subagents in `.claude/agents/`)
Invoke each with the Agent tool by its `name`. Each owns a stage; do not let one agent
do another's job.

| # | Agent | Owns |
|---|---|---|
| 1 | `openwrt-build-engineer` | source tree, feeds, `.config`, defconfig, build, image gen, sysupgrade.bin, SHA256, build logs |
| 2 | `kernel-driver-auditor` | mt76, mt7915e, cfg80211, mac80211, kmod load, module params, dmesg, firmware load, calibration warnings |
| 3 | `wireless-runtime-verifier` | post-flash SSH: `iw dev/phy/reg get`, `iwinfo`, `/sys/module/*` params, hostapd runtime, **real applied TX power**, reject fake numbers |
| 4 | `image-inspector` | inspect `.bin` before delivery: extract rootfs, verify `/etc/modules.d/*`, `/etc/config/*`, baked files, compare candidate vs requirement, block incomplete bins |
| 5 | `release-gatekeeper` | refuse `final` unless boot test + runtime verify + clean dmesg + no unknown params + no missing files + no manual post-flash steps |
| 6 | `regression-comparator` | diff each build vs previous, why a change passed/failed, prevent losing good changes, prevent perf regressions, document deltas |
| 7 | `recovery-backup-engineer` | backup before editing, restore plan, keep originals, rollback script, guard EEPROM/Factory/calibration |
| 8 | `log-analyzer` | build logs, boot logs, dmesg, kernel/wireless/firmware/calibration errors, module load order |
| 9 | `router-ssh-test-runner` | run verification commands on the real router after flash, collect full output (no truncation) |
| 10 | `safety-hardware-limits-auditor` | prove a change is not a fake number; classify each limit as driver / firmware / Factory / EEPROM / power table / PA-FEM / antenna-EIRP / regulatory |

## Mandatory process (in order)
1. Do not start with a random edit.
2. Read the project + relevant files first.
3. Identify the files responsible for the change.
4. **Back up** (recovery-backup-engineer).
5. Make the change **inside the build system** (not a repack hack, when a real build is possible).
6. Build a **candidate** bin (openwrt-build-engineer).
7. **Inspect** the bin content before flashing (image-inspector).
8. Flash the candidate on the **real router**.
9. Run **verification commands** (router-ssh-test-runner + wireless-runtime-verifier).
10. If it fails → **do not** name it final; explain the exact technical cause (log-analyzer).
11. If it passes → write the full report, then name it `final` (release-gatekeeper).

## Mandatory final-report format
```
- candidate/final bin path
- SHA256
- modified files
- inspected files
- build summary
- image inspection result
- router boot test
- verification commands output (full, untruncated)
- dmesg result
- PASS / FAIL
- technical explanation
```

## Strict rules
- No `final` bin without a real router test.
- Do not rely on a UI value alone, a UCI value alone, or `regulatory.db` alone.
- Do not rely on promises — every result must be proven by runtime commands.
- Every failure must be explained with its exact technical cause.
- Every risky change ships with a backup + restore plan.

## Environment reality (be honest)
- This sandbox **cannot compile OpenWrt from source** — egress to git/downloads.openwrt.org
  is blocked and rsync/flex are absent. From-source builds run on the user's **Ubuntu VPS**
  or via **GitHub Actions** (`.github/workflows/build-cr6608-v86.yml`). The build kit is in
  `router/cr6608/ubuntu-build/`.
- The sandbox **has no SSH to the router**, so stages 8–9 (flash + runtime verify) are run
  by the **user**, who pastes the command output back. Until that output exists, a bin is
  **candidate**, never `final`.
- Repacking the existing image (`router/cr6608/repack.sh`) is used when a from-source build
  is unavailable; it cannot change compiled code (kernel/driver) — only rootfs files.

## Repo layout
- `router/cr6608/` — curated custom overlay (www dashboard, scripts, etc-config, luci-view,
  regulatory.db, POWER-CHAIN.md, repack.sh).
- `router/cr6608/ubuntu-build/` — from-source build kit (build.sh, mt76 patch, files/ overlay).
- `.github/workflows/` — CI build.
- `.claude/agents/` — the 10 specialized subagents.
</content>
