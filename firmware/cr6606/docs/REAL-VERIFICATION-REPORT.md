# CR6606 — Real verification report (txpower & features)

This answers your questions **honestly**. Values marked "PROVEN" come only from
YOUR device after running the scripts; values marked "EXPECTED" are what the US
regdb + mt7915 behaviour imply. I do not claim a number is real until `iwinfo`
shows it.

## Config (what the software REQUESTS — radio level, all channels)
```
wireless.radio0 (2.4 GHz): country=US  txpower=30
wireless.radio1 (5 GHz):   country=US  txpower=30
```
This is a genuine 30 dBm **request on the whole radio**, not tied to one channel.
Default channels (for stability): 2.4G = ch1 (HT20), 5G = ch36 (HE80). You can move
to any channel; the 30 request stays.

## The three power numbers (per your request)
| | Source | Value |
|---|---|---|
| Requested | `/etc/config/wireless` `txpower` | **30 dBm** (both radios) |
| Accepted by driver | `iw dev <if> info` → `txpower` | PROVEN by `verify-wifi.sh` |
| Applied/emitted | `iwinfo <phy> info` → `Tx-Power` | PROVEN by `verify-wifi.sh` |

Applied = **min( 30 , US-regdb-per-channel , device-caldata )**. Nothing here
patches regdb or caldata, so the hardware/legal ceiling stands.

## Is 30 dBm real? (honest, EXPECTED — confirm on device)
- **2.4 GHz:** US regdb allows 30 dBm. So `iwinfo` *may* show up to 30 **if** the
  CR6606 caldata permits. mt7915 caldata often caps ~20-23. → run the script to see
  the real number. If it shows <30, then **30 is NOT real on 2.4 GHz for this unit**
  and the shown value is the true max.
- **5 GHz:** US regdb itself limits channels by sub-band (this is law, not a setting):
  - ch 36-48 (UNII-1): ~23 dBm max → 30 is NOT possible here
  - ch 52-144 (UNII-2, DFS): ~24 dBm max → 30 is NOT possible here
  - ch 149-165 (UNII-3): 30 dBm allowed → 30 possible **if caldata permits**
  So on 5 GHz, **30 can only ever be real on ch149-165**, and only if the hardware
  caldata allows it. Everywhere else the legal max is 23-24.

## Highest real power / best distance (EXPECTED)
- 2.4 GHz: whatever `iwinfo` reports on ch1/6/11 (likely the highest single number).
- 5 GHz: ch149-165 give the highest legal headroom (up to 30 in regdb).
- Best *stable* distance = highest `actual` value on a **non-DFS** channel with **no
  mt7915 errors** in `logread`. The channel script ranks this for you.

## How to PROVE it (run after flashing, over LAN/SSH not Wi-Fi)
```sh
sh /root/verify-wifi.sh          | tee /tmp/proof.txt           # power + all features
sh /root/verify-wifi-channels.sh | tee /tmp/chan-proof.txt      # real power per channel
```
Send `proof.txt` + `chan-proof.txt` back and I will fill the final verdict:
- 30 real on 2.4 GHz? yes/no + actual number
- 30 real on each 2.4 GHz channel? which ones
- 30 real on 5 GHz? which channels
- highest real-power channels
- channels that won't reach 30
- best channel for real distance with no reboot/crash (from logread/dmesg check)

## What is NOT done (your rules, enforced)
No reghack, no regdb patch, no EEPROM/ART/Factory/Calibration edit, no LuCI number
spoofing. The number you see is the number the radio truly emits.
```
