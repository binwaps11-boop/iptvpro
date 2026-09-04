# CR6608 crash-log sanitation maintenance image

This directory is intentionally separate from the normal firmware. The normal
kernel keeps `crash_log` read-only. The maintenance builder changes only the
CR6608 `crash_log` DT node and publishes one RAM-boot initramfs; it must never
be flashed as sysupgrade or firmware.

Build the normal v83 image successfully first, then use the same prepared and
verified OpenWrt tree:

```sh
./crashlog/build-cr6608-crashlog-initramfs.sh \
  /absolute/path/to/openwrt \
  /absolute/new/output/crashlog-maintenance
```

The destination must not exist. The publication contains exactly the
RAM-boot image, its SHA-256 file, and a manifest. Any generated flashable image
is quarantined and destroyed before publication. The builder restores the
normal `.config`, DTS, overlay, and published normal binaries. Because the
maintenance build starts from a prepared (necessarily patched) OpenWrt tree,
its manifest records hashes but is not a substitute for the normal build's
source-input manifest.

Before erasing anything:

1. Boot the maintenance initramfs in RAM using the already-proven recovery
   method. Never write it to NAND.
2. Connect through wired LAN SSH and verify that every Wi-Fi interface is down.
3. Copy the exact 262144-byte `/dev/mtd5ro` image to storage outside the router,
   calculate its SHA-256 on both sides, and verify that the hashes match.
4. Create `/etc/cr6608-crashlog-external-backup.attestation` as root mode `0400`
   with exactly these five lines, replacing `HASH` with that verified hash:

```text
CR6608_CRASHLOG_EXTERNAL_BACKUP_ATTESTATION=1
BACKUP_STORED_OFF_DEVICE=1
CRASH_LOG_PRE_ERASE_SHA256=HASH
EXTERNAL_BACKUP_SHA256=HASH
EXTERNAL_BACKUP_VERIFIED=1
```

Only then run:

```sh
cr6608-crashlog-sanitize erase CR6608_CRASH_LOG_ERASE_OFF_DEVICE_BACKUP_VERIFIED
```

The sanitizer accepts only the CR6608, exact `mtd5` label/geometry, healthy
NAND counters, a verified wired peer, the signed maintenance marker, and the
matching off-device backup attestation. Its only destructive command is
`mtd erase /dev/mtd5`; post-erase data must hash to the exact all-FF image.
Reboot immediately into the normal read-only kernel after success. Never edit
Factory, Bdata, EEPROM/calibration, firmware, or any other MTD partition.
