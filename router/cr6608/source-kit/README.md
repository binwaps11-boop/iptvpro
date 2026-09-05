# CR6608 Smart AP release-candidate source

The stock CR6608 Linux serial console remains available on `ttyS0` at
`115200n8` for boot diagnostics and authenticated recovery. No image performs
an automatic bootloader or Factory/EEPROM write.

This is the single maintained source kit for the Xiaomi Mi Router CR6608.
It builds OpenWrt `v25.12.5` from the official source tag for the
`ramips/mt7621` target and `xiaomi_mi-router-cr6608` profile.

## Layout

- `build.sh`: pinned source checkout, feeds, patch proof, full verbose build,
  and atomic release-candidate publication. Its explicit incremental mode keeps
  only verified compiler/toolchain caches while resetting source and images.
- `tools/cr6608_source_kit.py`: verifies the reviewed commit identity and
  creates a history-free, one-root Git bundle. The bundle is cloned and its
  source tests are rerun before it can be published or used for a full build.
- `cr6608.seed.config`: package selection for the verified 25.12.5 runtime.
- `patches/996-cr6608-dts-rf-38dbm-lab-mode.patch`: adds the CR6608-only DTS
  RF gate without affecting other mt7915 devices.
- `patches/996a-cr6608-dts-ul-muru-ram-gate.patch`: adds the separate
  CR6608-only UL-MURU DTS gate exclusively to the non-sale `ul-lab` build.
- `patches/140-net-dsa-mt7530-do-not-advertise-EEE-on-MT7621-switch.patch`:
  disables broken early EEE advertisement on all integrated MT7621 switch
  PHYs, addressing repeated link renegotiation before userspace can disable EEE.
- `patches/999-mt7915-cr6608-rf-38dbm-request-path.patch`: the CR6608-only,
  DTS-and-module-gated 1--38 dBm driver transaction. It pauses TX, snapshots
  the existing MCU SKU tables, applies the bounded rate table and the optional
  path table only when hardware data enables it, polls the MCU readback,
  publishes only a verified value, and performs verified conservative rollback
  or full firmware recovery on failure.
  While the CR6608 38 dBm request is armed, the legacy debugfs SKU writer is
  rejected so it cannot publish an unverified `Current power` value.
- `patches/zz-mt7915-cr6608-factory38-path.patch`: accepts the audited `0x40`
  (2.4 GHz) and `0x42` (5 GHz) targets only when the complete persisted
  Factory identity, rate/TSSI fields, and all 36 raw target bytes match. The
  four 2.4 GHz chain fields cover the band's shared group, while the 32 5 GHz
  fields cover all four chains in all eight EEPROM channel groups. It has no
  RAM floor and publishes read-only persisted-match telemetry. If the
  device/DTS/module request is armed but any persisted byte differs, both the
  raw targets and rate deltas are clamped to their audited stock-safe values,
  and the 38 dBm gate is off.
- `factory38/`: device-specific offline builder and a manually gated writer.
  The normal image contains neither the writer nor a writable Factory. The
  separately named maintenance build publishes only a RAM-boot initramfs,
  forces Wi-Fi off, and requires the exact marker, wired management, hashes,
  token, NAND health, and recovery attestation. It never publishes a
  maintenance sysupgrade or combined firmware image.
- `crashlog/`: a separate RAM-only maintenance builder and fail-closed
  sanitizer for the exact CR6608 `crash_log`/`mtd5` partition. It requires an
  off-device verified backup, wired SSH, exact NAND geometry/health, and an
  explicit token; the normal image keeps this partition read-only.
- `patches/993-luci-wireless-preserve-configured-txpower.patch`: exposes the
  complete compact `1 dBm` through `38 dBm` list without the old explanatory
  suffix. The separate current-power field remains sourced from the driver.
- `patches/992-uhttpd-normalize-dispatch-and-close-unread-body.patch`:
  normalizes percent-encoded, repeated-slash and dot-segment paths before
  prefix dispatch, and backports the upstream unread-request-body connection
  guard. Encoded LuCI paths therefore cannot fall through to the package CGI,
  and redirect responses cannot leave a keepalive stream out of sync.
- `files/`: the primary Smart AP browser interface, an authenticated one-click
  handoff to LuCI settings, retained LuCI RPC libraries, quick settings,
  security, network, LED, RF, and recovery overlay.
- `FEATURE-MATRIX.md`: release truth table separating live proof, packaged
  opt-in support, client-dependent behavior and MT7915 hardware limitations.
- `files/etc/uci-defaults/95-cr6608-enable-legacy-11b`: enables legacy
  802.11b rates on the 2.4 GHz radio only, including preserved upgrades; the
  5 GHz radio remains unchanged.
- `files/usr/bin/cr6608-txpower-verify`: read-only power-path report with an
  explicit one-shot `--probe-3800` mode.
- `files/usr/bin/cr6608-country-power-scan`: enumerates driver-reported country
  codes and records each channel limit plus the kernel response to a 3800 mBm
  request. `ELIGIBLE_BY_KERNEL` is deliberately not presented as RF proof.
- `files/usr/bin/cr6608-wifi-full-verify`: read-only channel inventory by
  default. `--run` backs up the exact wireless configuration, tests each
  kernel-advertised 2.4/5 GHz channel with supported HE20/HE40/HE80 widths,
  waits for DFS CAC, records requested/regulatory/driver/accepted power and
  restores the original configuration on every exit path. A runnable channel
  passes only when `iw` reports exactly 38 dBm and the stable, same-channel MCU
  telemetry proves the persisted Factory gate, exact half-dBm accounting, and
  a successful readback; disabled and no-IR channels remain explicit skips.
- `files/usr/sbin/cr6608-txpower-collect`: captures mac80211 state, the live
  MCU SKU table, and read-only `cr6608_rf_band*` telemetry. A sample is valid
  only when the telemetry generation is unchanged and even, the MCU generation
  matches, the MCU result is zero, and the readback-derived power matches
  `iw dev`; it never substitutes the configured request for current power.
- `files/usr/sbin/cr6608-ul-mu-evidence` (v4, phased): client-attributed uplink evidence
  from the patch-07 per-WCID counters; `--with-firmware --window N` adds the
  firmware's own `hetrig_*` TB PPDU statistics as an independent second source,
  reported as deltas over the window and never allowed to override a host
  disagreement. See `docs/CR6608-MURU-FAULT-ATTRIBUTION.md`.
- `files/usr/sbin/cr6608-ax-verify`: separates kernel capability, generated
  hostapd configuration, and over-air scheduling that still needs compatible
  clients. It does not claim OFDMA or MU-MIMO airtime activity from UCI alone.
- `files/usr/share/cr6608/ax-feature-support`: machine-readable support
  contract for the official upstream OpenWrt mac80211/mt76/mt7915e/hostapd
  stack. The image gate requires SU beamforming, downlink MU-MIMO and HE OFDMA
  support records and the runtime Background-CAC capability probe, while
  recording that upstream disabled original-MT7915 UL scheduling after TX
  hangs. The normal lab and retail profiles therefore omit the UL-MURU DTS
  property and boot with the legacy boolean off and `cr6608_muru_mask=0`.
  The separate `ul-lab` profile is a non-sale, initramfs-only qualification
  image: it alone adds the DTS property, keeps the legacy boolean off, and
  requests mask `15` (bit 0 DL OFDMA, bit 1 UL OFDMA, bit 2 DL
  MU-MIMO, bit 3 UL MU-MIMO). The port follows MediaTek's published OpenWrt
  25.12 `STA_REC_MURU` policy, requires a synchronous MCU response, records
  attempted/response-ok/failed/timeout transactions (where response-ok is not
  Firmware-apply or OTA proof), and clears every scheduler bit
  through a one-way kernel fault latch before firmware recovery. Legacy global
  MURU_CTRL sub-commands (the MediaTek-only `BSRP_CTRL`/`SUTX`/`MUMIMO_CTRL`/
  `MANUAL_CFG`/ack-policy/trigger-type/protection-threshold set) and the
  unregistered MediaTek vendor command are not used; only upstream's own
  `MURU_SET_PLATFORM_TYPE` and `RX_AIRTIME_CTRL` init commands are sent.
  See `docs/MT7915-MURU-VENDOR-BASELINE.md` and
  `docs/CR6608-STOCK-MURU-PORT.md`. A successful compile or an advertised HE
  capability is not official support or over-the-air proof; qualification still
  requires two compatible simultaneous upload clients, client-attributed
  capture hardware or per-peer scheduler telemetry (aggregate radio counters
  are correlation only), long-duration stress, and external RF/regulatory
  testing.
- `patches/zzzzzz-06-mt7915-cr6608-muru-fault-attribution.patch`: separates a
  MU-RU-attributed fault from an unrelated firmware recovery. Every recovery
  still disarms the scheduler before the reset, but only a MAC/MCU watchdog
  reset, a timed-out `STA_REC_UPDATE`, or a station-record mask race now spends
  the one-way latch. The shared `mt7915_mcu_schedule_full_recovery()` entry
  point - which the 38 dBm SKU transaction and the regulatory refresh both use -
  disarms and takes a strike instead, and the mask is re-armed from a one-way
  ceiling after a verified reset, before mac80211 replays the station records.
  Three unattributed strikes still end the experiment permanently. The patch
  also adds an upstream DL floor, so a retired or latched uplink experiment can
  no longer switch off DL OFDMA and DL MU-MIMO, which this radio supports on the
  plain upstream path.
- `patches/zzzzzz-07-mt7915-cr6608-muru-ul-tb-attribution.patch`: per-peer
  uplink evidence built from RX descriptors the driver already receives. A HE
  trigger-based PPDU exists only as a response to a Trigger frame this AP sent,
  and the descriptor carries the transmitting peer's WCID plus the HE RU
  allocation, so counting them per WCID is client-attributed proof that the
  scheduler solicited uplink airtime from one specific client. Two distinct
  peers sharing a PHY start timestamp are a real simultaneous uplink
  multi-user transmission: full-bandwidth UL MU-MIMO on the full operating
  bandwidth, UL OFDMA on a smaller RU. Read-only, and active only while an
  uplink bit is armed. See `docs/CR6608-MURU-FAULT-ATTRIBUTION.md`.
- `patches/zzzzzz-08-mt7915-cr6608-muru-live-refresh.patch`: after a verified
  partial reset re-arm, the runtime kill switch, or a debugfs mask write,
  replays every associated peer's station record through the standard
  `STA_REC_UPDATE` with the same `conn_state` last sent, so the live mask
  reaches firmware without a Wi-Fi reload. Also decays unattributed strikes
  after fifteen minutes without a disarm, so unrelated recoveries months apart
  can never spend the permanent latch. See
  `docs/CR6608-MURU-FAULT-ATTRIBUTION.md`.
- `patches/zzzzzz-09-mt7915-cr6608-muru-uniform-cfg-vendor-parity.patch`: sends the
  phy-wide `STA_REC_MURU` cfg bits identically to every peer (upstream
  `abd80cf6`: the firmware latches its MURU enable from the first station
  record; MediaTek's mt7915 build sends them uniformly), keeps per-peer
  eligibility in the peer's HE capability fields, restores exact upstream
  behaviour for non-MT7915 chips, and freezes the HE PHY CAP2 B22
  advertisement to a boot-time decision that defaults to MediaTek vendor parity
  (B22 off, scheduler armed); `cr6608_advertise_ul_mumimo=1` opts into the
  previous advertising behaviour for A/B over-the-air comparison.
- `patches/zzzzzz-10-mt7915-cr6608-muru-evidence-honesty.patch`: on MT7915 the
  RX PHY type is only reported with RXD group 5 (C-RXV), which upstream keeps
  off outside monitor mode (`d33943ba`), so the patch-07 per-peer counters are
  structurally zero in normal operation. The per-radio and per-peer nodes now
  report `rxv_group5_enabled=` and say `evidence=unavailable-crxv-disabled`
  when they cannot see PPDU types; a `0600` `cr6608_rxv_group5` knob lets the
  evidence tool enable group 5 for a bounded window (never by a profile).
  Also surfaces a failed `MURU_GET_TXC_TX_STATS` in `muru_stats` instead of an
  errno, and restores the `he_ext_su_cnt` accumulation upstream dropped.
- `patches/zzzzzz-11-mt7915-cr6608-muru-record-serialisation.patch`: fixes four
  verified defects in the live record refresh. The station transitions and the
  replay now run under `dev->mt76.mutex` (the `mt7996` pattern), so a replay
  can neither downgrade a peer that was authorised meanwhile nor touch a peer
  mac80211 is removing; a record overtaken by a one-way mask lowering is
  rebuilt or re-queued instead of spending the permanent latch; a `STA_REC`
  failure inside a recovery already in flight is attributed to that recovery
  (watchdog latches, anything else disarms with a strike) instead of latching on
  its own; every verified partial reset replays the records, so a refused re-arm
  can no longer leave firmware records armed while the host reports mask 0; and
  a replay that meets a reset window is parked and re-run when the band is
  released instead of being dropped. New host counter: `sta_rec_stale`.
- `patches/zzzzzz-12-mt7915-cr6608-muru-he-dcm-max-ru-upstream-e5932438.patch`:
  verbatim backport of upstream `e59324380042` (HE DCM max-RU encoding), which
  is on mt76 master but not in the `39c960c3` pin: DCM-capable peers were
  registered with a wrong `dcm_rx_max_nss` and `dcm_max_ru = 0`.
- `patches/zzzzzz-13-mt7915-cr6608-muru-recovery-lifecycle.patch`: the mask is
  touched only by the states that start a recovery (handshake acknowledgements
  no longer disarm); a strike is charged only when an uplink-bearing record was
  acknowledged since the last re-arm (a post-load recovery loop with zero peers
  can no longer latch); host-initiated recoveries (regulatory replay, ordering
  errors, a rejected 38 dBm request) never strike; strike decay and the record
  replay no longer depend on band 0's sticky post-reset bit; an operator
  `fw_ser` full reset disarms instead of latching; the debugfs mask writer
  lowers the ceiling first and validates against it; the firmware trigger
  statistics enable is re-sent after a firmware reload.
- `patches/zzzzzz-14-mt7915-cr6608-muru-ul-attribution-v2.patch`: per-peer TB
  counters are deduplicated per PPDU (raw descriptors kept as `he_tb_mpdu`),
  data-bearing PPDUs are split from the QoS-Null responses that the firmware's
  BSR polls solicit, every peer of a full-bandwidth group is credited, and
  `muru_stats` gains one `key=value` line per firmware counter with its source
  semantics. `schema=2` on both nodes; `cr6608-ul-mu-evidence` v4 consumes it.
- `patches/994-mt76-makefile-mac80211-debugfs.patch` (OpenWrt tree): the mt76
  package maps the MESH and TESTMODE options to driver defines but not
  `CONFIG_MAC80211_DEBUGFS`, so on every OpenWrt image the per-station debugfs
  hook is compiled out regardless of `CONFIG_PACKAGE_MAC80211_DEBUGFS`. The
  patch mirrors the MESH handling; the CI proof step checks the compiled
  module for the per-peer node strings.
- `packages/prplmesh`: pinned prplMesh Controller + Agent + IEEE1905 transport
  built against the generic NL80211 backend and the image's single
  `wpad-openssl` implementation. It is runtime-gated until all processes and
  the control plane pass on-device health checks; it never renames an SSID.

Smart AP remains the primary login and management interface. Direct or expired
LuCI requests return to `/`, avoiding a second inconsistent login page. After
Smart AP authentication, the explicit **OpenWrt Settings** button POSTs to the
same-origin `dashluci` bridge. The bridge validates the HttpOnly Smart AP
cookie, serializes session creation, grants the installed LuCI ACL groups, sets
a short-lived HttpOnly LuCI cookie, and opens the fixed wireless-settings URL.
The browser never receives either session bearer or the SSH password. Logout
revokes both sessions and clears the related cookies. Preserved broad Lua/ucode
prefixes that could shadow the canonical LuCI handler are normalized during
migration.

## Ubuntu build

Install the standard OpenWrt build dependencies once and work as an
unprivileged user. A full image build is accepted only from the verified
one-root source bundle; the reviewed development checkout may create that
bundle but may run source tests only:

```sh
cd /home/root123/CR6608-38DBM-WORK/kit
BUILD_EPOCH="$(date -u +%s)"
TRUST_RECORD=/home/root123/CR6608-38DBM-WORK/operator-trust-v86.txt
install -d -m 0755 /home/root123/CR6608-38DBM-WORK/source-kit-staging-v86
python3 -I -B tools/cr6608_source_kit.py create \
  --repo "$PWD" \
  --output-dir /home/root123/CR6608-38DBM-WORK/source-kit-staging-v86 \
  --kit-base 18c4f07f930a255becda4c8af0b73b0b4f8ef4b2 \
  --auth-fix 2fdeb2311364b8dfe5a31057cf0b8583cdf0c33c \
  --build-epoch "$BUILD_EPOCH" \
  --product-version v86 | tee "$TRUST_RECORD"
chmod 0444 "$TRUST_RECORD"
trusted_value() { sed -n "s/^$1=//p" "$TRUST_RECORD"; }
BUNDLE=/home/root123/CR6608-38DBM-WORK/source-kit-staging-v86/cr6608-source-kit.bundle
python3 -I -B tools/cr6608_source_kit.py verify-bundle \
  --bundle "$BUNDLE" \
  --clone-dir /home/root123/CR6608-38DBM-WORK/kit-v86 \
  --kit-base 18c4f07f930a255becda4c8af0b73b0b4f8ef4b2 \
  --auth-fix 2fdeb2311364b8dfe5a31057cf0b8583cdf0c33c \
  --product-version v86 \
  --build-epoch "$BUILD_EPOCH" \
  --expected-bundle-sha256 "$(trusted_value source_kit_bundle_sha256)" \
  --expected-original-commit "$(trusted_value source_kit_original_commit)" \
  --expected-original-tree "$(trusted_value source_kit_original_tree)" \
  --expected-container-commit "$(trusted_value source_kit_container_commit)" \
  --expected-container-tree "$(trusted_value source_kit_container_tree)" \
  --expected-payload-manifest-sha256 "$(trusted_value source_kit_payload_manifest_sha256)"
cd /home/root123/CR6608-38DBM-WORK/kit-v86
RESCUE_EVIDENCE_DIR=/home/root123/CR6608-38DBM-WORK/root-evidence-v86
RESCUE_EVIDENCE="$RESCUE_EVIDENCE_DIR/rescue-real-netns-evidence.txt"
install -d -m 0755 "$RESCUE_EVIDENCE_DIR"
test ! -e "$RESCUE_EVIDENCE"
sudo env \
  CR6608_REQUIRE_REAL_NETNS=1 \
  CR6608_RESCUE_REAL_EVIDENCE="$RESCUE_EVIDENCE" \
  CR6608_EVIDENCE_ORIGINAL_COMMIT="$(trusted_value source_kit_original_commit)" \
  CR6608_EVIDENCE_ORIGINAL_TREE="$(trusted_value source_kit_original_tree)" \
  CR6608_EVIDENCE_CONTAINER_COMMIT="$(trusted_value source_kit_container_commit)" \
  CR6608_EVIDENCE_CONTAINER_TREE="$(trusted_value source_kit_container_tree)" \
  CR6608_EVIDENCE_SOURCE_MANIFEST_SHA256="$(trusted_value source_kit_payload_manifest_sha256)" \
  sh tests/test-rescue-guard-contract.sh
CR6608_VERIFIED_SOURCE_BUNDLE="$BUNDLE" \
CR6608_EXPECTED_SOURCE_BUNDLE_SHA256="$(trusted_value source_kit_bundle_sha256)" \
CR6608_EXPECTED_ORIGINAL_COMMIT="$(trusted_value source_kit_original_commit)" \
CR6608_EXPECTED_ORIGINAL_TREE="$(trusted_value source_kit_original_tree)" \
CR6608_EXPECTED_CONTAINER_COMMIT="$(trusted_value source_kit_container_commit)" \
CR6608_EXPECTED_CONTAINER_TREE="$(trusted_value source_kit_container_tree)" \
CR6608_EXPECTED_PAYLOAD_MANIFEST_SHA256="$(trusted_value source_kit_payload_manifest_sha256)" \
CR6608_RESCUE_REAL_EVIDENCE="$RESCUE_EVIDENCE" \
SMARTAP_BUILD_EPOCH="$BUILD_EPOCH" ./build.sh
```

For deliberately network-free OpenWrt tag/feed preparation on the Ubuntu
worker, add `CR6608_OFFLINE_PINNED_SOURCES=1` to the final `build.sh`
environment. This mode performs no OpenWrt tag or feed network request. It
accepts only the existing annotated `v25.12.5` tag after verifying its pinned
object, peeled commit, official origin and OpenWrt release signature, then
restores the five feeds from `/home/root123/feeds-pinned-cache-20260809`.
Every archive has an immutable SHA-256 in `build.sh`; extraction rejects
absolute/parent-traversal paths and non-regular members, reconstructs the
worktree from the complete Git object closure, and requires the exact pinned
HEAD, clean status and official feed origin. A missing, tampered or
identity-mismatched cache fails closed. Without the opt-in, tag/feed network
checks use bounded retries and fall back to the same locally verified inputs
only for classified network failures; remote identity mismatches never fall back.

For a small follow-up build on the same trusted worker, add
`CR6608_REUSE_PREPARED_TREE=1`. The OpenWrt checkout is still forced to the
pinned commit and all source, feeds, configuration, overlay, temporary metadata,
and output images are reconstructed; only the existing `dl`, `build_dir`, and
`staging_dir` compiler/toolchain caches are retained after ownership and
non-symlink checks. The release records
`build_execution_mode=verified_incremental_cache`. Omit the variable for the
fully clean path.

The `verify-bundle` command above must be the copy from the separately reviewed
checkout, never the copy inside the bundle being verified. It hashes the bundle
before Git parses it, disables caller Git configuration/alternates/replacement
refs, checks the exact object closure before checkout, and retains that same
verified clone for the build. Keep `operator-trust-v86.txt` outside the release
directory and deliver its exact values through an authenticated, independent
channel; reading expected values from the bundle or its adjacent metadata is
not a trust bootstrap.

The command above builds the default non-sale `lab` candidate. A retail image
must be rebuilt from the same verified clone with
`CR6608_BUILD_PROFILE=retail`; it remains radio-locked, unprovisioned, and
`sale_ready=NO`. To produce the MURU qualification image, reuse the exact same
trusted variables and evidence while adding:

```sh
CR6608_BUILD_PROFILE=ul-lab \
  CR6608_VERIFIED_SOURCE_BUNDLE="$BUNDLE" \
  CR6608_EXPECTED_SOURCE_BUNDLE_SHA256="$(trusted_value source_kit_bundle_sha256)" \
  CR6608_EXPECTED_ORIGINAL_COMMIT="$(trusted_value source_kit_original_commit)" \
  CR6608_EXPECTED_ORIGINAL_TREE="$(trusted_value source_kit_original_tree)" \
  CR6608_EXPECTED_CONTAINER_COMMIT="$(trusted_value source_kit_container_commit)" \
  CR6608_EXPECTED_CONTAINER_TREE="$(trusted_value source_kit_container_tree)" \
  CR6608_EXPECTED_PAYLOAD_MANIFEST_SHA256="$(trusted_value source_kit_payload_manifest_sha256)" \
  CR6608_RESCUE_REAL_EVIDENCE="$RESCUE_EVIDENCE" \
  SMARTAP_BUILD_EPOCH="$BUILD_EPOCH" ./build.sh
```

That profile publishes only
`output/current-ul-muru-qualification/cr6608-SMARTAP-v86-UL-MURU-RAM-QUALIFICATION-initramfs-kernel.bin`.
It quarantines and removes the generated sysupgrade/combined-firmware
intermediates; never flash the qualification initramfs to NAND.

The privileged rescue gate is mandatory for every full build. It exercises
real Linux network namespaces, nftables bridge/inet packet paths, ARP and IPv4
spoof attempts, tagged `br-lan.100`, the standard firewall Stop path, and the
active/closed lifecycle. It emits a new root-owned, mode-`0444` evidence file
only after passing, refuses to overwrite an old file, and binds that evidence
to the exact verified source identities and rescue implementation hashes. The
unprivileged build revalidates its inode, hash, ownership, exact contents, and
copies it into the checksummed release.

The public source bundle in a full release is the byte-exact externally pinned
bundle used for that build, not a locally regenerated approximation. The tool
also rebuilds and reproduces the one-root bundle semantically with the local Git
version and records that separate hash. Schema v3 intentionally does not embed
the original commit object, avoiding disclosure of historical author/message/
parent metadata while preserving the externally pinned original commit and
tree identities.

For an exact byte-for-byte rebuild, use that independent operator trust record,
the trusted verifier, the delivered bundle, its recorded build epoch, and the
original private signing keys. Do not clone or execute the delivered bundle
before the external verification shown above.

For a delivered release, set `BUNDLE` to its bundle path, set `TRUST_RECORD`
to the independently received operator record, set `BUILD_EPOCH` from that
trusted record, and repeat the exact `verify-bundle` plus pinned-environment
sequence. The adjacent `build-manifest.txt` is evidence after trust is
established; it is not itself the external trust anchor.

Both signing private keys are deliberately excluded from this source archive.
By default, store the firmware key as
`/home/root123/CR6608-38DBM-WORK/secrets/key-build-v29` and the APK repository key as
`/home/root123/CR6608-38DBM-WORK/secrets/private-key-v29.pem`, both with mode `0600`.
The maintained production runner instead pins the existing protected copies at
`/home/root123/secrets/key-build-v29` and
`/home/root123/secrets/private-key-v29.pem` through `CR6608_FW_SIGNING_KEY` and
`CR6608_APK_SIGNING_KEY`; an exact rebuild must preserve those explicit inputs.
Only `signing/key-build.pub` and `signing/public-key.pem` are distributable.
The build verifies both key pairs and checks the signed APK indexes.

The source gate requires Node.js 18 or newer for the real Playwright layout
tests. On the maintained Ubuntu builder it selects
`$HOME/tools/node20/bin/node` before an older system Node.js. Browser tests are
pinned by `test-tools/playwright/package-lock.json` to playwright-core 1.58.2;
install its matching Chromium once with:

```sh
CR6608_NODE_BIN="$HOME/tools/node20/bin/node" ./tests/setup-browser-tests.sh
```

The release manifest records both the Playwright package hash and the exact
Chromium executable hash used by the tests. Prepared-tree reuse is rejected;
the OpenWrt checkout and all five feeds are rebuilt from their pinned commits. The
compile stage is exactly:

```sh
make -j$(nproc) V=s
```

The upstream OpenWrt/mt76 stack does not use the vendor-only
`CONFIG_DRIVER_11AX_SUPPORT` symbol. The build instead gates the actual
upstream components: `kmod-cfg80211`, `kmod-mac80211`, `kmod-mt7915e`,
`kmod-mt7915-firmware`, `hostapd-common`, and `wpad-openssl`.
The CR6608 runtime gate additionally requires the mt7915 AP capability report
to advertise SU beamformer/beamformee, MU beamformer and HE RU capability, and
requires generated hostapd configuration to enable 802.11ax, HE SU/MU
beamforming and MU-EDCA. This is official upstream-stack support, not a
vendor-only feature-symbol claim.

The default `lab` build publishes one non-sale release candidate:

```text
/home/root123/CR6608-38DBM-WORK/output/current-candidate/cr6608-SMARTAP-v86-LAB-NONSALE-CANDIDATE-UL-MURU-GUARDED-OPERATOR-LOCKED-OPEN-WIFI-38DBM-sysupgrade.bin
```

Its SHA256, inspection-only source archive, history-free cloneable Git bundle,
the 50-image mobile/desktop browser screenshot matrix,
payload/identity manifests, bundle-clone reproduction log, source tests, and
build log are written beside it. No raw history patch or all-refs bundle is
published, so deleted historical blobs cannot leak through the source kit. It
is promoted to a deployable
candidate only after rootfs inspection, `sysupgrade -T`, a real router boot,
Smart AP login and legacy-LuCI redirect tests, network tests, RF checks, and a second reboot.
It is never labelled `PASS_38` without the independent conducted-RF gate.

The normal build neither reads nor packages a device Factory backup. A private,
device-specific Factory-38 bundle is an explicit and separate opt-in. Its exact
destination must be outside the source, build, log, and public `output` trees,
must not already exist, and its parent must already be a private directory:

```sh
mkdir -m 0700 /home/root123/CR6608-38DBM-WORK/private-device-output
CR6608_FACTORY38_BUILD_MODE=maintenance \
CR6608_FACTORY_BACKUP=/home/root123/CR6608-38DBM-WORK/device-inputs/cr6608-factory-original.bin \
CR6608_FACTORY38_PRIVATE_OUTPUT=/home/root123/CR6608-38DBM-WORK/private-device-output/device-factory38 \
./build.sh
```

The private bundle is maintenance-only and is not generated until the complete
image inspection passes. Its manifest, README, binding record, and private
`SHA256SUMS` bind it to the inspected RAM-only image SHA-256, source-kit commit,
OpenWrt commit, inspector, and inspection log. The checksum manifest's own hash
and the exact eight-file bundle set are pinned and rechecked before and after
the atomic private publication. It is never copied into a public
release directory or named in the public `SHA256SUMS`. Do not distribute it: it
contains the router's original Factory data, MAC addresses, and calibration.

To build the guarded maintenance environment, select maintenance mode. The
published directory and `output/current-maintenance` contain the validated
initramfs plus audit evidence, but no sysupgrade or combined firmware:

```sh
CR6608_FACTORY38_BUILD_MODE=maintenance ./build.sh
```

Boot `cr6608-SMARTAP-v86-MAINTENANCE-RAMBOOT-ONLY-initramfs-kernel.bin` into RAM through the
proven bootloader/recovery procedure; never write it to a firmware partition.
If a private bundle is also needed, add the two explicit private-output
variables shown above. After a guarded Factory operation, reboot immediately
into the normal read-only-Factory image. A maintenance build never updates
`output/current-candidate`.

Settings-preserving upgrades run the board-scoped migration
`preserved_config_version=8`. On an unprovisioned operator image it sets the
deterministic Smart AP/LuCI recovery credential separately from the root
SSH/serial-console credential, repairs a missing rpcd root login/ACL, and
applies the open onboarding policy only to `radio0`, `radio1`, `wifinet0` and
`wifinet1`. On a unit carrying a valid, complete
`/etc/cr6608-retail-provisioned` marker and no pending journal, the same
migration never changes rpcd credentials or any wireless option, so it cannot
restore the shared Web hash or reopen protected APs. Provisioning first writes
and synchronizes `/etc/cr6608-retail-provisioning-pending`; it publishes the
complete marker only after the credential/TLS/wireless runtime audit passes.
Transient netifd/hostapd primary readiness is retried for a bounded 30-second
window under the same transaction locks; timeout restores the prior state.
Both markers are retained by a settings-preserving sysupgrade. If reboot sees
the pending journal or a malformed/incomplete complete marker, the migration
preserves credentials, disables both Wi-Fi radios, skips open onboarding, and
exits retryably. Only a genuinely unprovisioned unit with neither marker takes
the onboarding path. Both paths retain `/etc/shadow`, Dropbear, DHCP, LAN,
guest, mesh and additional Wi-Fi settings, disable old forced DSA/VLAN cleanup,
and keep MT7621 packet steering disabled while retaining software flow offload.
Factory/MTD is never modified. A clean install or `sysupgrade -n` returns to a
locked-root open-lab/onboarding state. Unique-device root, Wi-Fi and Web
provisioning installs WPA/PMF credentials, but deliberately records
`sale_ready=NO` and `radio_policy=LAB_ARTIFACT_BLOCKED`: it cannot turn this
generic lab rootfs into a sale artifact.

The migration script keeps its historical filename
`99-cr6608-preserved-config-v2` for upgrade compatibility; the authoritative,
tested migration marker inside it is version 8.

The shipped retail-radio auditor is a fail-closed QA tool for a future retail
profile. It cannot pass this lab artifact and does not replace exact flashed-
image hashes, a factory-reset/reboot proof, regulatory RF measurements, or
market approval.

To reproduce from the delivered Git bundle:

```sh
# Use the reviewed tool + independent operator trust record and repeat the
# verify-bundle and pinned-environment build sequence from "Ubuntu build".
```

## RF statement

UCI requests up to 38 dBm through netifd and cfg80211. This is an explicitly
non-retail CR6608 lab path: when the persisted Factory targets do not match the
expected 38 set, the gated driver may construct a volatile EEPROM shadow and
raise the channel request ceiling to 38 in RAM. It never rewrites the Factory
partition, then submits the Rate SKU cap and any hardware-enabled optional Path
SKU cap while TX is paused. Because this lab override can exceed the selected
country's regulatory ceiling, driver/MCU acceptance is not an RF measurement
or a sale/regulatory approval.
The Rate SKU table is always the required witness; the Path SKU table is also
verified only on hardware whose device data enables that optional table.
The target covers the single shared 2.4 GHz EEPROM group and every one of the
eight 5 GHz EEPROM channel groups; each channel transition still requires its
own MCU SKU readback before traffic resumes. Acceptance requires an exact
two-chain calculation and a complete MCU GET readback: every returned entry
must stay within its submitted cap, and the peak must equal the requested
half-dBm value after the path delta. SAR, DFS, per-rate and thermal protections
remain active and can force a verified lowering or a fail-closed recovery.

The LuCI selector shows `38 dBm` without an extra suffix. The current-power
field and the evidence collector are not hardcoded: they show 38 only after the
driver/MCU witness produces the corresponding readback.

The normal image keeps Factory kernel read-only. A separate maintenance-only
RAM-boot initramfs can expose the guarded one-eraseblock writer, but never runs
it automatically, is never published as flashable firmware, and must be
followed immediately by the normal read-only image.
Immediately after compilation, the maintenance build quarantines its
intermediate sysupgrade and combined-firmware files outside the OpenWrt binary
tree under a private tracked directory. The inspector consumes only those
references, then they are removed. EXIT and signal cleanup also purges them on
failure. SHA-256 values are captured before and checked after inspection, then
checked again against the staged and atomically published release. The
inspector's own hash is pinned before it runs and rechecked afterward; the
gate-passing inspection log is then pinned and compared in staging and in the
final release. Only the exact inspected RAM-boot initramfs remains deployable.
A successful readback proves firmware state, not physical RF output.
`iw dev` is a driver-declared setting, not a calibrated RF measurement. Actual
conducted and radiated power remains limited by firmware, EEPROM/calibration,
PA/FEM hardware, antenna gain, per-rate tables, and applicable regulations.
Do not edit Factory/EEPROM data without a verified backup and recovery path.
