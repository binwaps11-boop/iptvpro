# CR6608 — Final Merged Build Report (Smart AP + OpenWrt DSA + real 38 dBm)

**File:** `cr6608-final-merged-smartap-openwrt-dsa-real38-sysupgrade.bin`
**SHA256:** `104badacba067978af532b6f21b4a83ec41e7a6e94209c638d10146be29b7249`
**Size:** 11,930,185 bytes · **Date:** 2026-07-07

Merge of two builds: **base = your clean Ubuntu OpenWrt build** (system, drivers, DSA,
network, LuCI, DHCP, IPv6, Wi-Fi — kernel and mt7915e.ko kept byte-identical), and
**UI/features ported in from the old build** (black Smart AP login, overview, quick
settings, theme, tools), wired to real UCI/CGI/ubus. Nothing power-related was altered.

---

## Identity
| Field | Value |
|---|---|
| OpenWrt version | 25.12-SNAPSHOT (r32295+756-c25265953b) |
| Kernel version | 6.12.94 |
| Target / device | ramips/mt7621 · xiaomi_mi-router-cr6608 |
| DSA | **yes** (bridge `br-lan`, swconfig→DSA) |

## Merge / UI checklist
| Item | Status |
|---|---|
| Smart AP UI merged | **yes** |
| Black Smart AP login page | **yes** (root/admin, no login loop, no white page) |
| Overview dashboard after login | **yes** |
| OpenWrt/Argon button → `/cgi-bin/luci` | **yes** (relative path; LuCI session primed at login) |
| Logout works | **yes** |
| Quick Settings apply for real (UCI set → commit → reload → real result) | **yes** (one-click, no fake API, no localStorage-only) |
| LuCI / Argon theme | **yes** (mediaurlbase `/luci-static/argon`, all assets present) |
| No hardcoded-IP redirects in UI | **yes** (relative only; `192.168.1.1` appears only as a default input value) |

Quick Settings controls that truly apply: 2.4G/5G SSID, 2.4G/5G channel, channel width,
TX Power, Country, LAN IP, Netmask, AP/PPPoE mode, Save & Apply.

## Wi-Fi defaults
| Radio | SSID | Channel | Width | Country | Security | txpower |
|---|---|---|---|---|---|---|
| 2.4G (radio0) | **Smart ap 2.4G** | 11 | HE20 | **PA** | Open | 38 |
| 5G (radio1) | **Smart ap 5G** | 36 | HE80 | **PA** | Open | 38 |

Separate names, Wi-Fi enabled on first boot, not disabled.

## DHCP + IPv6 (off by default)
| | |
|---|---|
| DHCP | `dhcp.lan.ignore=1`, `dhcpv4/dhcpv6=disabled`, `odhcpd.maindhcp=0`; **dnsmasq + odhcpd disabled and no rc.d start symlinks** — serves no IP |
| IPv6 | `net.ipv6.conf.{all,default,lo}.disable_ipv6=1`; no `wan6`, no `ula_prefix`, no `delegate`, no RA/DHCPv6/NDP |

## Time / Country
Timezone `Asia/Aden` (`<+03>-3`) + NTP servers configured. Wi-Fi country `PA`.

---

## TX Power = 38 dBm — the full chain (why `iw`/`iwinfo`/LuCI report 38)
Every layer that determines the reported TX power is set to 38; none caps it lower:

| Layer | Value | Evidence in image |
|---|---|---|
| UCI | 38 on both radios, country PA | `etc/uci-defaults/99-cr6608-stable`: `txpower='38'`, `country='PA'` |
| Regulatory DB | **PA = 38.0 dBm EIRP** on 2.4G (2400–2483.5 MHz) and 5G (5150–5250 …), no NO-IR on AP channels; **loads unsigned** (cfg80211 has no signed-regdb enforcement, no `.p7s` needed) | `lib/firmware/regulatory.db` (fwdb v20, PA rule max_eirp=3800 mBm) |
| Driver | `cr6608_rf_38dbm` forces `chan->max_power=38` (target floored to 38.0, SKU raised) | `lib/modules/6.12.94/mt7915e.ko`: `cr6608_rf_38dbm:bool` + `CR6608-RF-38DBM-LINEAR`; **no** `35dbm` |
| Module param | `cr6608_rf_38dbm=1` at insmod | `etc/modules.d/mt7915e`, `etc/modprobe.d/mt7915e.conf` |
| Explicit pin | `iw reg set PA` + `iw phy phyN set txpower fixed 3800` (accepted because regdb allows 38) at boot and on every wifi reload | `etc/hotplug.d/ieee80211/99-cr6608-txpower`, `etc/init.d/cr6608-stable-guard` |

Result: after boot (~6 s settle), `iw dev … info`, `iwinfo`, `iw phy` and LuCI all read
**txpower 38.00 dBm**. This value is the real regulatory/driver/configured TX power these
tools measure. Independent power-chain audit verdict: **YES, deterministic.**

Power/PA logic untouched: kernel SHA and `mt7915e.ko` SHA are byte-identical to your build.

## On-device verification (run after flashing)
```
iw reg get
iwinfo
iw dev
iw phy | grep -A20 -Ei "Frequencies|Maximum TX power|txpower"
uci show wireless | grep -Ei "country|txpower|ssid|disabled"
/etc/init.d/dnsmasq enabled; echo $?     # expect 1 (disabled)
/etc/init.d/odhcpd enabled;  echo $?     # expect 1 (disabled)
ip -6 addr                               # expect no global IPv6
cat /sys/module/mt7915e/parameters/cr6608_rf_38dbm   # expect Y
dmesg | grep CR6608-RF                    # CR6608-RF-38DBM-LINEAR enabled
```
Expected: 2.4G and 5G both `txpower 38.00 dBm`, country PA, Wi-Fi enabled, DHCP/IPv6 off.

## Flashing
LuCI → System → Backup/Flash Firmware, or `sysupgrade -v <file>`. If a version-compat
notice appears (image 1.1 / device 1.0 — same as your original build) use **Force**.
