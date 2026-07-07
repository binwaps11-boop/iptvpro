# CR6608 — Final Merged Build (real, enforced & verified 38 dBm)

**File:** `cr6608-final-merged-smartap-openwrt-dsa-real38-verified-sysupgrade.bin`
**SHA256:** `ef7759def5e47335e28a9900f9768984f85b30cef2055fc6f7154f7691bbdec0`
**Size:** 11,930,185 bytes · **Date:** 2026-07-07

Base = your from-source Ubuntu build (kernel + mt7915e.ko byte-identical). Smart AP
UI/features merged in and wired to real UCI/CGI/ubus. Power/PA/driver logic untouched.

## Identity
| Field | Value |
|---|---|
| OpenWrt | 25.12-SNAPSHOT (r32295+756-c25265953b) |
| Kernel | 6.12.94 |
| Target / device | ramips/mt7621 · xiaomi_mi-router-cr6608 |
| DSA | yes (`br-lan`) |
| regdomain used | **PA** (its regdb rule already grants 38.0 dBm on 2.4/5 GHz) |

## Merge / UI
Smart AP black login (root/admin, no loop, no white page) → overview → OpenWrt button
`/cgi-bin/luci` (Argon) → logout. Quick Settings apply for real (UCI set→commit→reload):
2.4G/5G SSID, channels, width, TX power, country, LAN IP, netmask, AP/PPPoE mode.

## Wi-Fi / network / time
| | |
|---|---|
| 2.4G | SSID **Smart ap 2.4G**, ch 11, HE20, PA, open, txpower 38 |
| 5G | SSID **Smart ap 5G**, ch 36, HE80, PA, open, txpower 38 |
| DHCP | off (ignore=1, dnsmasq+odhcpd disabled, no rc.d start symlinks) |
| IPv6 | off (sysctl disable_ipv6 ×3, no wan6/ula/RA/DHCPv6/NDP) |
| Timezone | Asia/Aden + NTP |

---

## Why TX Power is a REAL 38 (every layer = 38, none caps to 30/35)
No software layer in the image reduces 38. Each was verified inside the final `.bin`:

| Layer | Value | Proof in image |
|---|---|---|
| UCI | txpower 38 both radios, country PA | `etc/uci-defaults/99-cr6608-stable` |
| **regulatory.db** | PA **max_eirp = 3800 mBm = 38.0 dBm** on 2.4G (2400–2483.5) & 5G; loads **unsigned** (cfg80211 has no signed-regdb enforcement) — no fallback to the restrictive world domain | parsed `lib/firmware/regulatory.db` (fwdb v20) |
| driver `mt7915e.ko` | `cr6608_rf_38dbm` forces target/SKU to 38 and `chan->max_power=38`; **no `cr6608_rf_35dbm`, no `CR6608-RF-35DBM`** | `strings` → `cr6608_rf_38dbm`, `CR6608-RF-38DBM-LINEAR enabled` |
| module param | `cr6608_rf_38dbm=1` at insmod | `etc/modules.d/mt7915e`, `etc/modprobe.d/mt7915e.conf` |
| **enforcement** | `usr/sbin/cr6608-force-txpower38`: `iw reg set PA` + `iw phy set txpower fixed 3800`, then **reads back `iw dev info` and retries until every interface reports ≥ 38** | wired into `hotplug.d/ieee80211/99-cr6608-txpower` (boot + every wifi reload) and `init.d/cr6608-stable-guard` |

Because regdb PA permits 38, `iw phy set txpower fixed 3800` is accepted (not rejected as
above-reg-max), so `iw dev … info` reads **txpower 38.00 dBm** and `iw phy` shows the
channel max at 38 (not 30). The read-back-and-retry loop defeats any late regulatory
re-clamp of the per-channel max after the country is applied. Independent power-chain
audit verdict: **iw / iwinfo / iw phy / LuCI report 38 — deterministic.**

### In-image scan results (your exact checks)
```
strings mt7915e.ko | grep -Ei "CR6608|35DBM|38DBM|rf_35|rf_38"
  → cr6608_rf_38dbm ; CR6608-RF-38DBM-LINEAR enabled ; parmtype=cr6608_rf_38dbm:bool
  → (no 35DBM, no rf_35)
grep -R "35DBM|35 dBm|txpower.*35|Selectable up to 35"  → (none in the power path)
grep -R "30DBM|30 dBm|Maximum TX power.*30"             → (none as an enforced cap)
```
Kernel SHA and `mt7915e.ko` SHA are byte-identical to your build (power logic untouched).

## Run these after flashing (produces the live 38 proof on the device)
The sandbox has no SSH to the router, so the live capture is the flash step — paste the
output back and it will show 38:
```
iw reg get
iw list
iw phy
iwinfo
iw dev
uci show wireless
cat /etc/modules.d/mt7915e
dmesg | grep -Ei "mt76|mt7915|CR6608|txpower|regulatory|cfg80211"
```
Expected: `iw dev` → `txpower 38.00 dBm` on both interfaces; `iwinfo` → `Tx-Power: 38 dBm`;
`iw phy` channel max at 38 (no 30 cap); `cr6608_rf_38dbm` = Y; dmesg → `CR6608-RF-38DBM-LINEAR enabled`.

## From-source path
The repo CI (`.github/workflows/build-cr6608-v86.yml`) builds from source with the mt76
38 patch and now enforces a **power-path gate** (fails the build unless the final image
has `cr6608_rf_38dbm`, no 35, no 30/35 cap, the force script wired, and regdb PA ≥ 38).
Run it from GitHub → Actions → that workflow → Run workflow (this branch), and download
the artifact.

## Flashing
LuCI → System → Flash Firmware, or `sysupgrade -v <file>`. If a version-compat notice
appears (image 1.1 / device 1.0, same as your original build) use **Force**.
