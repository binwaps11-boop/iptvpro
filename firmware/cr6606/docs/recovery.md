# Backup, flashing, rollback & recovery (L, M, N)

> 🔴 DANGEROUS SECTION. Read fully. Commands are split SAFE vs DANGEROUS.
> Nothing here touches bootloader / factory / ART / calibration / MAC.

## L) Backup commands  ✅ SAFE (read-only / saves to /tmp)
```sh
# On the router:
# 1) Config backup (settings only)
sysupgrade -b /tmp/backup-$(cat /proc/sys/kernel/hostname)-$(date +%F).tar.gz

# 2) Note partition layout (DO NOT modify these)
cat /proc/mtd

# 3) READ-ONLY dump of important MTD partitions to /tmp (then scp off-device).
#    This READS only; it never writes back. Keep these safe — they contain your
#    factory/ART/calibration so you can verify nothing changed later.
for n in $(grep -oE '^mtd[0-9]+' /proc/mtd | sed 's/mtd//'); do
  name=$(sed -n "$((n+1))p" /proc/mtd | cut -d'"' -f2)
  cat /dev/mtd${n}ro > /tmp/mtd${n}-${name}.bin 2>/dev/null && \
    echo "saved /tmp/mtd${n}-${name}.bin ($name)"
done
```
Then from your PC:
```sh
scp root@192.168.100.1:/tmp/backup-*.tar.gz ./
scp root@192.168.100.1:'/tmp/mtd*-*.bin' ./cr6606-mtd-backup/
```
Store `cr6606-mtd-backup/` somewhere safe. **Never write these back unless doing a
documented factory recovery — and never the bootloader/factory.**

## M) Safe sysupgrade  🔴 DANGEROUS — gated on your diagnostics
> ⚠️ DO NOT RUN until you've (1) confirmed profile from `make info`, (2) verified
> the file is a `xiaomi_mi-router-cr6606 ... sysupgrade.bin`, (3) checked sha256,
> (4) taken the backup above, (5) pasted diagnostics so port/country are confirmed.

```sh
# On your PC: copy image to router
scp openwrt-*-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin root@192.168.100.1:/tmp/

# On the router: verify it's the right image + integrity
sha256sum /tmp/openwrt-*-sysupgrade.bin       # compare to sha256sums from build
strings /tmp/openwrt-*-sysupgrade.bin | grep -m1 cr6606   # sanity check

# Flash. KEEP settings off (-n) the FIRST time so uci-defaults apply cleanly:
sysupgrade -n /tmp/openwrt-*-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin
#   -n = do NOT keep old config (lets our defaults take over). Router reboots.
#   Drop -n on later upgrades if you want to keep your settings.
```
Do **not** power off during flashing. NAND write + reboot ~1–3 min.

## Safe network-change rollback (for VLAN/WAN edits, NOT flashing)  ✅ SAFE
Before applying any `templates/network-*` change, arm an auto-rollback so a bad
config can't lock you out:
```sh
# Apply changes WITHOUT committing, then test, then confirm:
# (uci commit writes to disk; instead use 'uci commit' only after confirm)
# Easiest built-in safety:
cp /etc/config/network /etc/config/network.bak
cp /etc/config/firewall /etc/config/firewall.bak
# ... make changes, reload ...
/etc/init.d/network reload
# If you LOSE access, on next failsafe/reboot restore:
#   cp /etc/config/network.bak /etc/config/network && reboot
```
Or use the kernel-level safety net: schedule a reboot, and cancel it only if you
still have access:
```sh
sleep 180 && reboot &        # reboots in 3 min unless you cancel
RB=$!                         # ...apply changes, test access...
kill $RB                      # cancel ONLY if everything still works
```

## N) Recovery steps (if flash/config goes wrong)
1. **Failsafe mode** (config bad, device still boots): power on, watch for the
   LED/flashing, press **reset** when it blinks → boots minimal, network at
   `192.168.1.1`, root no password. Then:
   ```sh
   mount_root           # mount overlay
   firstboot -y && reboot   # factory-reset OpenWrt config (NOT firmware)
   # or selectively restore: cp /etc/config/network.bak /etc/config/network
   ```
2. **TFTP / stock recovery** (bad image, won't boot OpenWrt): the CR660x uses the
   Xiaomi U-Boot recovery. Procedure is documented on the OpenWrt device page for
   the CR6606 — follow it exactly; it restores via TFTP without touching the
   bootloader. (Have your stock or OpenWrt factory image + a TFTP server ready.)
3. **Worst case**: re-flash the OpenWrt `factory`/`initramfs` image via the
   bootloader recovery, then sysupgrade again. Your saved `mtd*-*.bin` lets you
   verify factory/ART are intact (they should never have changed).

> If you can still SSH in, you almost never need TFTP — `firstboot` + restore is
> enough.
