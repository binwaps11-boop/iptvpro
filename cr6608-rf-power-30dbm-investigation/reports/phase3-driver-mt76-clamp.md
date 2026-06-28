# Phase 3 — Driver / mt76 / mt7915 clamp analysis (OpenWrt 24.10)

> Function and line names below were pulled from the live OpenWrt mt76 tree
> (`mt7915/init.c`, `mt7915/mcu.c`, `mt7915/eeprom.c`). The 24.10 branch pins a specific mt76
> commit; the power path is identical in shape. Confirm exact lines in *your* tree under
> `build_dir/target-*/linux-*/mt76-*/mt7915/`.

## 3.1 The power pipeline (top to bottom)

```
mac80211 hw->conf.power_level  (from regdb + user txpower, the high PA value)
        │
        ▼
mt7915_init.c  __mt7915_init_txpower()
        target_power = mt7915_eeprom_get_target_power(dev, chan, chain)   # EEPROM TX0/1_POWER
        target_power += mt7915_eeprom_get_power_delta(dev, band)          # EEPROM RATE_DELTA
        mt76_get_rate_power_limits(...)                                   # regdb SKU table
   >>>  chan->max_power = min_t(int, chan->max_reg_power, target_power)   # <<< THE CLAMP
        │
        ▼
mt7915_mcu.c  mt7915_mcu_set_txpower_sku()
        tx_power = mt76_get_power_bound(mphy, hw->conf.power_level)
        ... builds per-rate SKU limit table (mt7915_sku_group_len[]) ...
        mphy->txpower_cur = min_t(int, e2p_power_limit, tx_power)         # second min()
        │
        ▼
   firmware/PA  → conducted RF (what iwinfo reports as composite)
```

The **binding** constraint with region=PA is the first `min_t()` in `__mt7915_init_txpower()`:
`max_reg_power` is now large, so `target_power` (the EEPROM cal value) wins. **That is your 26/24.**

## 3.2 Clamp table

| File | Function | Clamp source | Before | Proposed change | Risk | Expected result |
|---|---|---|---|---|---|---|
| `mt7915/init.c` | `__mt7915_init_txpower()` | `min_t(int, chan->max_reg_power, target_power)` | binds to EEPROM `target_power` | (a) raise EEPROM target (Phase 2) **or** (b) patch to `chan->max_power = chan->max_reg_power` | **High** | `iw phy` will *report* higher max; **conducted RF rises only until PA P1dB, then clips** |
| `mt7915/mcu.c` | `mt7915_mcu_set_txpower_sku()` | `mphy->txpower_cur = min_t(int, e2p_power_limit, tx_power)` | re-applies EEPROM limit per rate | force `e2p_power_limit = tx_power` | **High** | per-rate SKU table opens; same PA ceiling applies physically |
| `mt7915/mcu.c` | `mt7915_mcu_set_sku_en()` | `phy->sku_limit_en` gate | SKU limits ON | set `sku_limit_en=0` (or `iw phy` user txpower) | Med | disables regulatory SKU enforcement only — **does not** raise cal target |
| `mt7915/eeprom.c` | `mt7915_eeprom_get_target_power()` | reads `MT_EE_TX0/1_POWER_*` | returns cal dBm | return is the real lever (see Phase 2) | High | this is *the* number; PA physics still caps it |
| `mac80211/cfg80211` | reg rules / `max_eirp` | regdb | already high (region=PA) | none needed | — | **already not the limiter** per your `iw reg get` |

## 3.3 What each "fix" actually buys you

- **Patch the `min_t()` to drop `target_power`** → `iw phy` shows e.g. 30, and the FW is *asked* for 30.
  The PA cannot deliver clean 30; you get compression/clipping. This is exactly the "fake 30 in
  iwinfo" you forbade. **Rejected unless Phase‑4 station/survey proves real gain.**
- **Disable SKU limits** (`sku_limit_en=0`) → opens per-rate regulatory ceiling only; cal target still
  caps. Small, legal-grey, no path to 30.
- **Raise EEPROM target** → real but tiny headroom on 2.4 G (FEM margin), ~none on 5 G; clips past P1dB.

## 3.4 Why no software path reaches 30 dBm

`30 dBm = 1 W` **conducted per the composite**. MT7915's integrated PA (and the CR6608's 5 GHz
front end) is a ~20–22 dBm/chain class device. Two chains combine to ≈ **+3 dB** ⇒ ~23–25 dBm
composite — which is precisely your measured 26 (2.4G, with FEM) / 23–24 (5G). The cal target is set
*at* the PA's linear limit on purpose. Software can move the *requested* number; it cannot move the
*transistor's* P1dB. Getting to 30 dBm needs external PAs/FEMs and/or antenna gain → `VERDICT.md` §HW.
