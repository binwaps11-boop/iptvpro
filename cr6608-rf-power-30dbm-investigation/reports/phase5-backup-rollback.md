# Phase 5 — Backup / Rollback (MANDATORY before any EEPROM/caldata write)

> Do NOT run any `mtd write` until you have a verified backup OFF the device and a recovery path.

## 1. Full Factory/caldata backup
```sh
FAC=$(grep -i factory /proc/mtd | cut -d: -f1)      # e.g. mtd5   (confirm name from /proc/mtd)
echo "Factory partition = /dev/$FAC"
cat /dev/$FAC > /tmp/factory-backup.bin
# Copy OFF the device immediately (router storage is volatile / will be reflashed):
#   scp /tmp/factory-backup.bin you@host:~/cr6608-factory-backup.bin
```

## 2. SHA256 BEFORE
```sh
sha256sum /tmp/factory-backup.bin
# Record here:  BEFORE = ________________________________________________
```

## 3. SHA256 AFTER (re-read the partition after any write)
```sh
cat /dev/$FAC > /tmp/factory-after.bin
sha256sum /tmp/factory-after.bin
# Record here:  AFTER  = ________________________________________________
# The two hashes MUST differ only if you intended a write; diff the bytes:
#   cmp -l /tmp/factory-backup.bin /tmp/factory-after.bin
```

## 4. Restore procedure
```sh
# From the saved-off backup, put it back on the router, then:
mtd write /root/cr6608-factory-backup.bin $FAC
reboot
# Verify: sha256sum of re-read partition == BEFORE hash.
```

## 5. UART / TFTP warning
- If a bad write corrupts cal AND the boot/wifi path, the GUI/SSH may still come up (cal ≠ bootloader),
  but **Wi-Fi will be broken** until restored.
- If you instead damage the **kernel/rootfs/ubi**, you need **UART (115200 8N1)** + **TFTP recovery**
  via U-Boot. Have a USB-TTL adapter and the stock/OpenWrt factory image ready *before* touching mtd.
- Xiaomi devices often need the bootloader unlocked / `boot_wait` set for TFTP — verify your unlock
  method first.

## 6. Permanent vs runtime
- `mtd write` to Factory = **PERMANENT** (survives reboot/flash unless you restore).
- `iw phy <phy> set txpower` / `sku_limit_en` debugfs = **RUNTIME only** (gone on reboot). Test here first.
- A driver patch (Phase 3) = persists only in *that* firmware image; reflashing stock reverts it.

## 7. Checksum
- MT7915 v1 flash EEPROM has **no driver-enforced global CRC**; mt76 will not reject an edited table.
- BUT TSSI/PA/thermal cal coefficients are interdependent — editing power bytes without matching cal
  can worsen EVM. There is no checksum to "fix"; the risk is RF quality, not a rejected blob.

## 8. Can it change MAC or break Wi-Fi?
- MAC is at `MT_EE_MAC_ADDR=0x004`. **Stay far from it.** Power fields are at `0x252/0x29d/0x2fc/0x34b`
  (v1) — different region, but a wrong offset/stride write *can* clobber MAC or per-chain cal.
- Worst realistic case: degraded/asymmetric chains, wrong MAC, or dead radio → restore from backup.
