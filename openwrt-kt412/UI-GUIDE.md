# KT412 — UI Guide (light, official LuCI, every button works)

Design rule honored: **keep official LuCI**, don’t replace it with a strange UI, don’t
delete official pages, no heavy charts, no fast auto‑refresh. Each “feature” below maps
to a **real** LuCI page or a **real** command button (`luci-app-commands`) — no fake buttons.

## Dashboard  → `Status → Overview`
Shows for real: model, OpenWrt version, uptime, CPU load, RAM/free RAM, flash usage,
running services, active WAN IP/uptime, and (if enabled) Wi‑Fi associations.
- **Recent errors:** `Status → System Log` (logread) and `Kernel Log` (dmesg).
- **Live traffic / per‑port RX‑TX:** `Status → Realtime Graphs` (built‑in, lightweight,
  only loads while the page is open — not a background poller).
> We deliberately did **not** add collectd/statistics dashboards (RAM‑heavy on 128 MB).

## Quick Setup  → `System → Custom Commands` + `Network → Interfaces`
Real one‑click buttons pre‑installed (System → Custom Commands):
| Button | Action |
|--------|--------|
| WAN: Reconnect | `ifup wan` |
| Wi‑Fi: Restart | `wifi` |
| Multi‑WAN: Status | `mwan3 status` |
| Verify: All / Ports / WAN / Services / Wi‑Fi | runs `/root/verify-*.sh` |

Mode changes use official, **safe‑apply** flow (LuCI’s *Save & Apply* has automatic
**rollback**: if you lose contact, config reverts in ~90 s):
- **Router mode** = default (LAN 192.168.100.1 + WAN). 
- **AP/Bridge mode** = set `wan` proto `none`, add LAN to upstream, disable DHCP.
- **WAN DHCP / Static / PPPoE** = `Network → Interfaces → wan → edit` (templates already in `/etc/config/network`).
- **Backup/Restore** = `System → Backup / Flash Firmware`.

## Port Control  → `Network → Switch` + `verify-ports.sh`
swconfig `switch0` page lets you really assign ports to VLAN1 (LAN) / VLAN2 (WAN) /
custom VLANs, enable/disable, and see link/speed. `verify-ports.sh` prints per‑port
link, speed, duplex, RX/TX, errors/drops, and VLAN mapping.
> Port “off/lan/wan_dhcp/wan_static/wan_pppoe” roles are achieved by moving the port’s
> VLAN membership + pointing the matching interface proto — all on the official Switch +
> Interfaces pages. The **CPU/management path (LAN1‑4 → br‑lan) is never broken** by these.

## WAN Manager / Multi‑WAN  → `luci-app-mwan3`  (`Network → Load Balancing`)
Real ECMP, failover, priority (**metric**), weight (**weight**), and health‑checks to
**1.1.1.1 / 8.8.8.8** — all preconfigured in `/etc/config/mwan3`:
- **ECMP/balanced** policy (weights 3:2), **failover** policy (wan→wan2), and a
  single‑WAN‑safe default so nothing breaks until you add a 2nd WAN.
- Status/troubleshoot: `Network → Load Balancing → Status`, or the *Multi‑WAN: Status* button.

## VLAN Manager  → `Network → Switch` + `Network → Interfaces`
Create/edit/delete VLANs on `switch0` (e.g. VLAN10 access on LAN port 5 → `eth0.10`),
mark Trunk (CPU `0t`) vs Access, attach DHCP and a firewall zone per VLAN, all on
official pages. Prove it with `bridge vlan show` / `swconfig dev switch0 show` (in
`verify-ports.sh`). Management VLAN1 (192.168.100.1) is protected.

## Health Monitor  → `mwan3` + `verify-*.sh`
- Link/Internet health: mwan3 tracks 1.1.1.1 & 8.8.8.8 every 10 s (low CPU), down after
  3 misses, up after 3 hits.
- System health: `verify-services.sh` (services + watchdog + recent errors),
  `verify-all.sh` (full snapshot). Hardware **watchdog** (`/dev/watchdog`) is active via procd.

## Wi‑Fi  → `Network → Wireless` + `verify-wifi.sh`
2.4G + 5G radios are present but **disabled by default** (predictable first boot). Enable
in `Network → Wireless`, set **country code** (required), SSID, channel/width. The page
shows associations and signal. **Real Tx power** is confirmed by `verify-wifi.sh`
(`iwinfo … tx-power`) — not a requested/fake value.
```
# enable quickly from CLI:
uci set wireless.radio0.disabled='0'; uci set wireless.radio1.disabled='0'
uci set wireless.radio0.country='SA'; uci set wireless.radio1.country='SA'  # your country!
uci commit wireless; wifi
```
