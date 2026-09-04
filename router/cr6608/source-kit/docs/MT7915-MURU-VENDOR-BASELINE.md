# MT7915 MURU vendor baseline

This project ports only the small, auditable MURU policy used by MediaTek's
OpenWrt 25.12 downstream tree. It does not import Xiaomi's proprietary
`mt_wifi` implementation or its undocumented firmware commands.

Pinned public references (checked 2026-08-26):

- MediaTek `mtk-openwrt-feeds` commit:
  `629dc1c1f90cf135394312bb5ee919f4b1999146`
- MediaTek mt76 patch `0099-cp-mtk-mt76-mt7915-add-connac2-support.patch`:
  SHA-256 `351db16dc70ea486570b3f70fa1e3f1a4637c8054ed4e60a6cfa39d42da32cd1`
- MediaTek hostapd patch `0020-mtk-hostapd-Add-hostapd-MU-SET-GET-control.patch`:
  SHA-256 `31cf52dd5d31c9d9d8af872611245f3dcd9eced4967acc14bbc5381066283404`
- mt76 source commit used by OpenWrt 25.12.5:
  `39c960c3ada558b4c2e7915772483d3731573d09`
- `mt7915_rom_patch.bin` SHA-256:
  `43883a5d78758e895b2a294478e3fd136cf98737100fe44ba1f57cb54332317f`
- `mt7915_wa.bin` SHA-256:
  `686d6a049a7fa07b47bd09fdcb86c7b807f66f6a9808af55440d5e5276e4c860`
- `mt7915_wm.bin` SHA-256:
  `73ae4c95fcef55f2e537e2d122d267d4cb666f896e96ec5e88573839bcf985b2`

The MediaTek bitmap is preserved exactly: bit 0 DL OFDMA, bit 1 UL OFDMA,
bit 2 DL MU-MIMO, and bit 3 UL MU-MIMO. The local port adds independent bits,
MCU-response telemetry, and a kernel one-way fault latch before recovery.

Important limitation: MediaTek's current patch deliberately returns before
registering its nl80211 vendor commands, and it does not remove mt76's MT7915
HE UL-MU advertisement guard. Therefore this remains a controlled downstream
qualification candidate until over-the-air tests and long-duration stress pass;
the source alone is not a retail certification.
