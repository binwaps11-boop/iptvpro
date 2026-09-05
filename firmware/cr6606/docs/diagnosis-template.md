# (A) Diagnosis report — TEMPLATE

Run `build/00-collect-diagnostics.sh` on the router, then paste each section's
output below. Copy this file to `diagnosis-REPORT.md` and fill it in. The analysis
column is filled once your real outputs are in (I will not guess your unit's logs).

| # | Item | Source command | Your value | Analysis |
|---|------|----------------|-----------|----------|
| 1 | Target/subtarget/profile | openwrt_release / board | | expect ramips/mt7621/cr6606 |
| 2 | CPU / arch | /proc/cpuinfo | | expect MT7621 1004Kc x2 |
| 3 | RAM | free -m | | expect ~256MB |
| 4 | Flash | df -h, /proc/mtd | | expect 128MB NAND |
| 5 | Wi-Fi chipset/driver | dmesg, iwinfo | | expect mt7915e |
| 6 | 2.4GHz capability | iw list | | |
| 7 | 5GHz capability | iw list | | |
| 8 | Max txpower / band | iw phy / iwinfo | | legal+calibrated cap |
| 9 | Reg domain | iw reg get | | set your country |
| 10| Channels + txpower table | iw list | | |
| 11| DSA or swconfig | bridge link / swconfig | | expect DSA |
| 12| LAN/WAN port map | ip link, bridge link | | wan + lan1-3 |
| 13| network config | /etc/config/network | | |
| 14| wireless config | /etc/config/wireless | | |
| 15| firewall config | /etc/config/firewall | | |
| 16| reboot/freeze logs | logread | | root cause? |
| 17| kernel errors | dmesg | | |
| 18| Wi-Fi driver errors | dmesg/logread mt7915 | | |
| 19| switch/DSA errors | dmesg | | |
| 20| OOM / memory | logread, free | | |
| 21| watchdog resets | dmesg | | |
| 22| thermal/power signs | thermal_zone, logread | | |

## Stability checklist (fill as you verify)
- [ ] No `kernel panic` in logs
- [ ] No `Out of memory` / OOM-killer
- [ ] No `mt7915` reset/timeout loops
- [ ] No DSA/switch link flaps
- [ ] No watchdog-triggered reboots
- [ ] uptime grows without unexplained resets
- [ ] temp under load reasonable
- [ ] flash not full (`df -h` overlay has headroom)
- [ ] no broken/held opkg packages

## Common root-cause → fix map (apply only if the log shows it)
| Symptom in logs | Likely cause | Fix (no scheduled-reboot as primary) |
|---|---|---|
| `mt7915 ... reset` repeatedly | unstable htmode/txpower, heat | drop 5G to HE40/HE20, ensure txpower unset, improve airflow |
| `Out of memory`/OOM | too many heavy pkgs / leak | remove statistics/collectd, check leaking daemon |
| random reboot, no panic | power/PSU or watchdog | test PSU, check `dmesg` for wdt, see healthcheck log |
| `kernel panic` | bad image/flash | re-flash clean stable image (recovery.md) |
| LAN/WAN flaps | cable / port / DSA | swap cable, check `ethtool`, confirm port map |
| overlay full | logs/pkgs filling flash | clear logs, move logging to RAM, prune pkgs |
