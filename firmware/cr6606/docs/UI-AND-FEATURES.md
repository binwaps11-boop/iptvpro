# CR6606 — UI & features (what is REAL, and how to prove it)

Principle: **official LuCI, no fake buttons.** Every item below either ships in
stock LuCI, comes from a real package, or is a tested script. Things that can't be
done are stated honestly, not faked.

## 1. Interface
- **Official LuCI** + **Argon theme** (`luci-theme-argon`) = nicer colors, cleaner
  dashboard, clear buttons. All official sections kept: Status, System, Services,
  Network, Wireless, Firewall. Nothing removed/broken.
- Bootstrap theme also included as fallback (switch in System → System → Language
  and Style).

## 2. Dashboard (real, in LuCI)
- **Status → Overview**: model, OpenWrt version, uptime, load, RAM, flash.
- **Status → Realtime Graphs**: live CPU/load/traffic per interface.
- **Statistics → Graphs** (`luci-app-statistics` + collectd): historical CPU, RAM,
  **per-interface traffic (per port)**, thermal.
- **vnStat** (`luci-app-vnstat2`): daily/monthly bandwidth per interface.
- Connected clients + signal: **Network → Wireless** (associated stations).
- DHCP leases: **Status → Overview** / **Network → DHCP and DNS**.

## 3. Quick Setup — REAL, via safe script (no untested web button)
`/root/quick-setup.sh` (menu) with **Safe Apply + auto-rollback** (you keep a change
only by running `confirm`, else it auto-reverts + reboots — you can't lock yourself out):
```
/root/quick-setup.sh router
/root/quick-setup.sh ap <mgmt_ip> <gateway>
/root/quick-setup.sh wan-dhcp
/root/quick-setup.sh wan-static <ip> <mask> <gw> <dns>
/root/quick-setup.sh pppoe <user> <pass> [mtu]     # +MSS clamp
/root/quick-setup.sh vlan <id> <lan1,lan2>         # access VLAN + DHCP + zone
/root/quick-setup.sh mesh <id> <2g|5g> [key]
/root/quick-setup.sh backup | restore <f> | confirm | revert | status
```
> A custom LuCI *web* page for this can be added later, but only after you can test
> it on the device — I won't ship an untested web button.

## 4. VLAN — real (DSA bridge-vlan)
- Works in LuCI: **Network → Interfaces → Devices → br-lan → Edit → Bridge VLAN
  filtering** (add VLAN IDs, set ports tagged/untagged). Or use `quick-setup.sh vlan`.
- Create / edit / delete, access & trunk ports, per-VLAN DHCP + firewall zone.
- Survives reboot (stored in /etc/config). Management port preserved (safe apply).
- Prove: `bridge vlan show` (also in `verify-ports.sh`).

## 5. Broadband — real
- WAN DHCP / Static / **PPPoE** all in **Network → Interfaces → WAN → Edit**
  (`luci-proto-ppp` installed). Username/pass, MTU, DNS, MSS clamp, NAT, zone.
- Connect/Reconnect: the **Connect/Disconnect** buttons on the WAN interface.
- Logs: **Status → System Log** (or `logread | grep pppd`).
- Prove: `ifstatus wan`.

## 6. Mesh (802.11s) — supported by the mt7915 driver
- mt76/mt7915 supports 802.11s mesh. Configure via `quick-setup.sh mesh` or
  **Network → Wireless → Add → Mode: 802.11s**.
- **Honest caveat:** encrypted mesh (SAE) needs a wpad build with mesh support. The
  default image uses `wpad-basic-mbedtls`. If encrypted mesh peers don't link,
  install `wpad-mesh-mbedtls` (`opkg update && opkg install wpad-mesh-mbedtls`) and
  retry; unencrypted mesh works as-is. Prove: `iw dev <mesh-if> station dump`.
- This is NOT faked: if your build/driver can't form a peer, the script tells you.

## 7. Wi-Fi power
- country **US**, **txpower 30 on both radios** (radio-level, all channels).
- Real applied value proven by `iwinfo` (see `verify-wifi.sh` / `verify-wifi-channels.sh`).
- No EEPROM/ART/calibration edits, no reghack, no LuCI number spoofing.

## 8. Port control — honest
- On **DSA there is no per-port on/off switch button** in stock LuCI. Real ways:
  - Bring a port up/down: `ip link set lan2 down` / `up`.
  - Assign access/trunk VLAN: bridge-vlan (LuCI Devices tab or `quick-setup.sh vlan`).
  - Per-port speed/link/RX-TX/errors/drops + VLAN membership: `verify-ports.sh`.
- I did **not** add a fake "disable port" button.

## 9. Verification scripts (all read-only except quick-setup)
```
/root/verify-all.sh            # system, services, network, vlan, wifi, errors
/root/verify-ports.sh          # per-port link/speed/duplex/RX-TX/errors/VLAN
/root/verify-services.sh       # uhttpd/dropbear/dnsmasq/odhcpd/firewall/watchdog
/root/verify-wifi.sh           # iwinfo/iw reg/txpower + feature checks
/root/verify-wifi-channels.sh  # real applied power per channel
```

## Packages (only what's needed — nothing random)
See `build/packages.txt`. Each maps to a feature above. Heavy ones (SQM, UPnP) ship
**disabled** to protect 256MB RAM; enable per need.
