# CR6608 Smart AP v29 final source

The CR6608 Linux serial console is disabled in the device tree command line,
the MT7621 kernel configuration (`CONFIG_SERIAL_8250_CONSOLE`), and
`/etc/inittab`. The UART driver remains available, but Linux does not register
`ttyS0` as a kernel console or start a serial login. This does not modify the
bootloader or Factory/EEPROM partitions.

This is the single maintained source kit for the Xiaomi Mi Router CR6608.
It builds OpenWrt `v25.12.5` from the official source tag for the
`ramips/mt7621` target and `xiaomi_mi-router-cr6608` profile.

## Layout

- `build.sh`: clean source checkout, feeds, patch proof, full verbose build,
  and final artifact publication.
- `cr6608.seed.config`: package selection for the verified 25.12.5 runtime.
- `patches/997-cr6608-disable-8250-kernel-console.patch`: disables only the
  Linux 8250 console while retaining the UART driver.
- `patches/998-cr6608-disable-serial-console.patch`: removes serial console
  arguments from the CR6608 device tree.
- `patches/999-mt7915-cr6608-rf-38dbm-linear.patch`: the only local mt76
  driver patch.
- `files/`: the final Smart AP, LuCI/Argon, quick settings, security, network,
  LED, RF, and recovery overlay.

The Smart AP to LuCI transition uses `/www/cgi-bin/dashluci`. It validates the
existing Smart AP session and creates a short-lived LuCI ubus session. The
browser never receives or stores the SSH password. Logout destroys both
sessions and clears all related cookies.

## Ubuntu build

Install the standard OpenWrt build dependencies once, then run as an
unprivileged user:

```sh
cd /home/root123/CR6608-FINAL/kit
./build.sh
```

For an exact byte-for-byte rebuild, reuse the `smartap_build_epoch` recorded in
the release `build-manifest.txt` and the original private signing keys:

```sh
RELEASE_MANIFEST=/home/root123/CR6608-FINAL/output/current-v29/build-manifest.txt
SMARTAP_BUILD_EPOCH="$(sed -n 's/^smartap_build_epoch=//p' "$RELEASE_MANIFEST")" ./build.sh
```

Both signing private keys are deliberately excluded from this source archive.
Store the firmware key as
`/home/root123/CR6608-FINAL/secrets/key-build-v29` and the APK repository key as
`/home/root123/CR6608-FINAL/secrets/private-key-v29.pem`, both with mode `0600`.
Only `signing/key-build.pub` and `signing/public-key.pem` are distributable.
The build verifies both key pairs and checks the signed APK indexes.

The compile stage is exactly:

```sh
make -j$(nproc) V=s
```

The build publishes one release candidate:

```text
/home/root123/CR6608-FINAL/output/cr6608-SMARTAP-v29-CANDIDATE-sysupgrade.bin
```

Its SHA256 and source/patch manifest are written beside it. It is promoted to
`FINAL` only after rootfs inspection, `sysupgrade -T`, a real router boot,
Smart AP and Argon login tests, network tests, RF checks, and a second reboot.

## RF statement

The mt76 patch exposes the requested 38 dBm ceiling and a clear kernel marker.
`iw dev` is a driver-declared setting, not a calibrated RF measurement. Actual
conducted and radiated power remains limited by firmware, EEPROM/calibration,
PA/FEM hardware, antenna gain, per-rate tables, and applicable regulations.
Do not edit Factory/EEPROM data without a verified backup and recovery path.
