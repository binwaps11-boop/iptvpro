# Wi-Fi txpower on the CR6606 — the real story (no fake numbers)

## Short answer
**30 dBm (1 watt) is not a realistic or legal per-band figure for this router, and
the hardware/driver will not actually emit it.** Forcing "30" into config does not
create real coverage — it gets silently clamped. This kit deliberately leaves
`txpower` unset so the **driver applies the true legal maximum** from your country
regulatory rules *and* the device's own factory power table.

## Why 30 dBm doesn't apply here
1. **Hardware**: the MT7905/MT7975 (MT7915 class) front-end is a typical 2x2
   consumer radio. Per-chain conducted power tops out roughly in the **~19–21 dBm**
   range depending on band/channel/rate — not 30 dBm. The driver reads per-rate,
   per-channel limits from the on-chip calibration ("ePA/iPA power table"). We do
   **not** touch that calibration (your safety rule), so the real ceiling stands.
2. **Regulatory law**: 2.4 GHz indoor is almost universally capped well below 1 W
   (e.g. EU 20 dBm EIRP, US 30 dBm EIRP but that's *EIRP including antenna gain*,
   not conducted per-chain). 5 GHz sub-bands have their own caps and DFS. OpenWrt's
   regulatory database (CRDA/`wireless-regdb`) enforces this per your `country`.
3. **EIRP vs conducted**: the number you'll see (e.g. `20 dBm`) is conducted power
   per chain. With 2 chains + antenna gain, **effective radiated power (EIRP) is
   higher** than the single number — that's where real coverage comes from, and
   it's already legal/automatic. Chasing a bogus "30" gains nothing.

## What actually improves coverage (and is in this kit)
- Correct **country code** → unlocks the legal max for your region (set it!).
- **Clean channel** selection (survey-driven): 2.4 GHz 1/6/11, 5 GHz 36/40/44/48.
- **HT20 on 2.4 GHz** (less interference = better real-world throughput/range).
- **Both chains** active (2x2) — verify `iw phy` shows 2 spatial streams.
- Good placement, not heat (overheating throttles & destabilizes — opposite of help).

## How to read the REAL applied value (do this after flashing)
```sh
iw reg get                       # your enforced regulatory domain
iwinfo phy0 info | grep -i tx    # 2.4 GHz applied txpower + limits
iwinfo phy1 info | grep -i tx    # 5 GHz applied txpower + limits
iw phy phy0 info | grep -A40 'Frequencies'   # per-channel max dBm table
iw phy phy1 info | grep -A60 'Frequencies'
```
The `(X.0 dBm)` next to each frequency is the **legal+calibrated cap**. The value
in `iwinfo` is what's truly transmitting. **If you set 30 and `iwinfo` shows 20,
the truth is 20.** This kit will never claim otherwise.

## If you set a number anyway
`option txpower '30'` only ever **lowers** output to the min(requested, legal,
hardware). It cannot raise it above the calibrated/legal cap. Setting it lower than
max can *reduce* coverage. That's why we leave it unset = max legal.

## What we will NOT do (your safety rules, enforced)
- No `reghack` / patched `wireless-regdb` to fake a higher domain.
- No editing ART/EEPROM/Factory/calibration to inflate the power table.
- No country spoofing to display 30 dBm.
- No settings that overheat the PA and cause reboots/driver crashes.
