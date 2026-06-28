# Phase 4 — Before/After PROOF template  (you fill this on the CR6608)

> This is the ONLY acceptable proof. A higher number in `iwinfo` alone is NOT success.
> Success = higher power **AND** better signal/bitrate **AND** retries/failed not worse
> **AND** no thermal throttle **AND** no clipping (EVM/mask). Capture with a real client
> passing traffic (e.g. `iperf3` for 60 s) on each band.

## Capture commands (run BEFORE the change, then AFTER)
```sh
iwinfo
for p in phy0 phy1; do iw phy $p info | grep -A2 "Frequencies" | grep dBm; done
iw dev wlan0 station dump   # 2.4G client
iw dev wlan1 station dump   # 5G client
iw dev wlan0 survey dump
iw dev wlan1 survey dump
dmesg | grep -Ei "CR6608|MT7915|mt76|eeprom|factory|cal|power|txpower|thermal|chain"
cat /sys/class/thermal/thermal_zone*/temp
```

## Comparison table — FILL IN (do not leave placeholders if claiming success)

| Band | Channel | Before power | After power | Signal (dBm) | TX bitrate | RX bitrate | Retries | Failed | Verdict |
|------|---------|-------------|-------------|--------------|------------|------------|---------|--------|---------|
| 2.4G | 1/6/11  | 26          | `<fill>`    | `<fill>`     | `<fill>`   | `<fill>`   | `<fill>`| `<fill>`| `<fill>`|
| 5G   | 36      | 23          | `<fill>`    | `<fill>`     | `<fill>`   | `<fill>`   | `<fill>`| `<fill>`| `<fill>`|
| 5G   | 149     | `<fill>`    | `<fill>`    | `<fill>`     | `<fill>`   | `<fill>`   | `<fill>`| `<fill>`| `<fill>`|

## Pass criteria
- [ ] After-power > before-power on `iw phy` AND `iwinfo` (consistent, not just one).
- [ ] Client `signal` improved ≥ 2 dB at fixed distance (same spot, same client).
- [ ] TX/RX bitrate same-or-higher; `failed` and high retry % did **not** increase.
- [ ] No new `dmesg` thermal/throttle lines; thermal_zone temp not pinned near limit.
- [ ] Spectral check (if you have a SDR/analyzer): mask/OBW still pass = no clipping.

If power "rises" but signal/bitrate don't improve and retries climb → that is **clipping**, i.e. a
fake win. Record it as FAIL and revert (Phase 5).
