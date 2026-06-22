# KT412 / DW02-412H — Recovery (you are in U-Boot, you have serial)

Cause of the "No working init" loop: a `*-sysupgrade.bin` is a **tar**, not a raw
image — it must be applied by the `sysupgrade` command, never written raw via
U-Boot/`nand write`. Fix = boot a clean OpenWrt from RAM, then sysupgrade properly.

## Files (from the Release)
- RAM-boot: `official-128m-initramfs-kernel.bin`
- Flash:    `official-128m-squashfs-sysupgrade.bin`
Release: https://github.com/binwaps11-boop/iptvpro/releases/tag/kt412-fw

## Step 1 — PC as TFTP server
- Connect PC to a **LAN** port (not WAN). Set PC IP = `192.168.1.2/24`.
- Put `official-128m-initramfs-kernel.bin` in the TFTP root, rename to `init.bin`.

## Step 2 — U-Boot (type these; RAM-boot only, does NOT touch flash)
```
setenv ipaddr 192.168.1.1
setenv serverip 192.168.1.2
tftpboot 0x81000000 init.bin
bootm 0x81000000
```
If your U-Boot uses different names, send me `printenv` and I’ll adjust.

## Step 3 — device now runs OpenWrt from RAM at 192.168.1.1
From the PC, copy the real flash image over:
```
scp official-128m-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
```

## Step 4 — flash correctly (THE right way)
On the device shell (serial or `ssh root@192.168.1.1`):
```
sysupgrade -n -v /tmp/official-128m-squashfs-sysupgrade.bin
```
Device reboots into a working OpenWrt at 192.168.1.1. ✅

## Step 5 — apply the full KT412 setup (light, real)
Copy `setup-kt412.sh` to the device and run it. It sets Management 192.168.100.1,
NAT+flow-offload, mwan3 (ECMP/failover, health 1.1.1.1/8.8.8.8), light tuning,
real command buttons, and /root/verify-*.sh — installing packages if WAN has internet.
```
scp setup-kt412.sh root@192.168.1.1:/root/
ssh root@192.168.1.1 'sh /root/setup-kt412.sh'
# afterwards reach LuCI at http://192.168.100.1
```

> Do NOT flash any `*-sysupgrade.bin` from U-Boot again. Only via the `sysupgrade`
> command from a running system. `factory.img` is the only U-Boot-writable image,
> but that needs exact nand addresses — send `printenv` first if you want that route.
