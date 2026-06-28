# cr6608-rf-power-30dbm-investigation

Full-stack RF TX-power investigation for the **Xiaomi CR6608 (MediaTek MT7915 / MT7975 front-end)**
on **OpenWrt 24.10**, across three layers:

1. EEPROM / Factory / caldata
2. mt76 / mt7915 driver
3. regulatory / mac80211 / cfg80211

**Goal under test:** can `2.4 GHz` and `5 GHz` reach a *real* (not faked) **30 dBm** by software only?

---

## ⚠️ Read this first — scope of what was done here vs. what you must run

This investigation was authored in a sandbox that has **no access to your router** and **no
OpenWrt build tree**. Therefore:

| Phase | Who runs it | Status |
|-------|-------------|--------|
| 1. Read-only data collection | **You, on the CR6608** | Script provided: `scripts/phase1-collect.sh` |
| 2. EEPROM/caldata analysis | Me (source-grounded) + your Phase-1 data | `reports/phase2-eeprom-caldata.md` |
| 3. Driver/mt76 clamp analysis | Me (grounded in real mt76 source) | `reports/phase3-driver-mt76-clamp.md` |
| 4. Before/after proof | **You, on the CR6608** | Template: `results/phase4-before-after-TEMPLATE.md` |
| 5. Backup/rollback | **You, on the CR6608** | Procedure: `reports/phase5-backup-rollback.md` |
| Verdict + HW plan | Me | `reports/VERDICT.md` |

**No fabricated `iwinfo` output appears anywhere in this project.** Any number you see attributed
to your device came from *your* prompt (2.4G=26, 5G ch36=23/24) or is labeled as a *placeholder you
must fill*.

## How to use

1. Copy `scripts/phase1-collect.sh` to the router, run it, paste the output back (or commit it to
   `results/phase1-<date>.txt`).
2. Read `reports/VERDICT.md` for the bottom-line answer (A or B) and why.
3. If you decide to raise the software ceiling, `reports/phase5-backup-rollback.md` first, then
   `patches/` — but read why this does **not** get you to 30 dBm in `reports/VERDICT.md`.

## Source references (OpenWrt mt76, verified, not from memory)

- `mt7915/eeprom.c`, `mt7915/eeprom.h` — power-table offsets and parsing
- `mt7915/init.c` — `__mt7915_init_txpower()`, the `min_t()` clamp
- `mt7915/mcu.c` — `mt7915_mcu_set_txpower_sku()`, SKU limit table
