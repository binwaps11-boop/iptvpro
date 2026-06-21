# (O) Post-flash testing checklist

Work top to bottom. Stop and investigate the first failure.

## 1. Access
- [ ] `ssh root@192.168.100.1` works (change root pw immediately: `passwd`)
- [ ] LuCI loads at `https://192.168.100.1` / `http://192.168.100.1`
- [ ] `ubus call system board` shows model = Xiaomi Mi Router CR6606

## 2. Identity / defaults applied
- [ ] `uci get system.@system[0].hostname` = your hostname
- [ ] timezone correct: `date`
- [ ] `logread | grep custom-defaults` shows it ran

## 3. LAN / DHCP
- [ ] Wired client gets 192.168.100.x from DHCP
- [ ] `cat /tmp/dhcp.leases` shows leases

## 4. WAN / Internet
- [ ] `ifstatus wan` shows an IP (or PPPoE up)
- [ ] `ping -c3 1.1.1.1` works
- [ ] `nslookup openwrt.org` resolves (DNS ok)

## 5. Ports / DSA mapping  ← confirm against YOUR diagnostics
- [ ] `bridge link` lists lan1/lan2/lan3 in br-lan, wan separate
- [ ] Each physical LAN jack passes traffic; WAN jack is the internet one
- [ ] `ethtool lanX` shows 1000Mb/s full-duplex on a gigabit link

## 6. Wi-Fi — REAL values (see docs/txpower-explained.md)
- [ ] `iwinfo` shows both SSIDs (2.4 + 5 GHz) up
- [ ] `iw reg get` = your country code (NOT 00 if you set one)
- [ ] `iwinfo phy0 info | grep -i tx` — note the **actual** dBm
- [ ] `iwinfo phy1 info | grep -i tx` — note the **actual** dBm
- [ ] `iw phy phy0 info | grep -A40 Frequencies` — per-channel legal caps
- [ ] 2x2 confirmed: `iw phy phy0 info | grep -i 'TX/RX'` or stream count
- [ ] Clients connect on both bands; throughput sane (`iperf3`)

## 7. Stability (let it run, then check)
- [ ] `cat /proc/uptime` climbs (no unexpected reboots)
- [ ] `logread | grep -iE 'panic|oom|reset|watchdog|mt7915|reboot'` is clean
- [ ] `dmesg | grep -iE 'error|fail|hang'` clean
- [ ] `cat /var/log/healthcheck.log` shows no recurring failures
- [ ] temp sane: `cat /sys/class/thermal/thermal_zone*/temp` (divide by 1000 = °C)
- [ ] `free -m` available memory stable over hours (no leak/OOM)

## 8. Watchdog / health
- [ ] hardware watchdog active: `dmesg | grep -i watchdog`
- [ ] cron line present: `crontab -l | grep healthcheck`

## 9. Final hardening
- [ ] root password changed
- [ ] Wi-Fi keys changed from placeholder
- [ ] LuCI/SSH reachable only from LAN (WAN input = REJECT — already default)
- [ ] Take a fresh config backup: `sysupgrade -b /tmp/post-flash-good.tar.gz`
