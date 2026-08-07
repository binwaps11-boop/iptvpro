# SmartAP Q20 — RF, performance & stability tuning, with sources

This is the aggregated result of researching the real, documented problems and the
community/independent-builder tuning for the **MT7621 + MT7915 (mt76, kernel 6.12)**
class of device, and applying only the changes that have evidence behind them and do not
trade away stability. Every claim below has a source; every honest tradeoff is stated.

The short version: **the shipped config already implements every safe, evidence-backed
win, and already avoids every documented regression.** Most famous "turbo" mods are
placebo or a stability/security risk on this SoC, so they are deliberately *not* here.

---

## 1. The 38 dBm reality (why the number is honest, not magic)

38 dBm is *requested* at every software layer — the driver's EEPROM target
(`mt7915_eeprom_get_target_power → 76` half-dBm), `regulatory.db` (182 countries), and
`txpower 38` on both radios. But the applied power is
`min(regdb ceiling, board per-rate/per-channel table, UCI txpower) − antenna_gain`, and
the **board table binds first** — which is exactly why raising `txpower` in UCI often does
nothing (openwrt/mt76#942, #633, #657).

The MT7915 PA's **linear region tops out around ~20–21 dBm conducted per chain** for
OFDM/HE; 2×2 combining adds ~3 dB. Pushing past that (country/EEPROM tricks) drives the PA
into **compression → EVM rises → high-MCS rates fall back → *lower* real throughput and
often *shorter* usable range**, plus more heat. So the build asks for 38 for headroom and
transparency, but real coverage comes from the levers in §2, not the number on screen.
- Sources: openwrt/mt76#633, #657, #942, #1059; spinics linux-wireless msg221720.

## 2. Wi-Fi range & stability — what is applied and why (all rootfs/UCI)

Validated against community consensus; every one of these is already in
`files/etc/config/wireless`:

| Option (shipped value) | Effect | Verdict / source |
|---|---|---|
| `disassoc_low_ack '0'` | AP does **not** kick weak/distant clients on ACK loss | **Highest-value single "range" toggle.** luci#5781, #5771 |
| `antenna_gain '0'` | gain is *subtracted* from the conducted limit; 0 lets the driver push the board-cap max | correct in-spec way to maximize EIRP. mt76 power-limits |
| `country 'US'` | permissive-but-legal per-channel ceilings | legitimate EIRP lever |
| `htmode HE80` (5 GHz) / `HE40` (2.4) | 80 MHz, **not** 160 | **These devices are officially AX1800** — 5 GHz 2×2 802.11ax peaks at **1201 Mbps on an 80 MHz channel** per the vendor spec (JCG Q20 / Xiaomi CR6608). 160 MHz would be AX3000-class (2402 Mbps), which the OEM stock firmware itself does **not** offer, so we don't either — it is not officially supported on this hardware. (Also 160 MHz on a 2×2 7915 has no spare chain for DFS radar → unreliable upstream, mt76#748.) All 5 GHz **channels** stay selectable as before; only the 160 MHz *width* is capped to 80 |
| `cell_density '0'` | normal basic-rate floor = **largest cell** | raising it *shrinks* range; keep 0 for distance. patchwork ozlabs cell_density |
| `legacy_rates '0'` / `htmode HE80` (5 GHz) | throughput-first shipped defaults | **Operator range switch — `smartap-range-mode {off\|on\|max\|status}`.** The single biggest range lever is 5 GHz **channel width**: narrower = lower receiver noise floor (N=kTB, ~3 dB per halving) **and** higher power-spectral-density per subcarrier, i.e. a stronger link **both** directions (AP→client and the AP hearing a weak far client). `on` = 5 GHz **HE40** + 2.4 GHz CCK/1 Mb/s beacons (~+3 dB, 5 GHz peak ~halved). `max` = 5 GHz **HE20** + CCK (~+6 dB, peak ~quartered). `off` = HE80 + OFDM-only (default). HE20/HE40 are the most-tested MT7915 widths (instability is 160 MHz-only), so this is real, not placebo. The choice survives reboot and is mirrored into Quick Settings so a later Save & Apply keeps it. Always-on reliability settings (LDPC, STBC, beamforming, `distance=1000`, `mcast_rate 6000`, `disassoc_low_ack=0`, `cell_density=0`, no RSSI-reject) already maximise weak-client reach for free — only the throughput-costly width/CCK moves are gated behind this switch |
| `ieee80211k '1'` + `bss_transition '1'` (802.11v) | neighbor reports + BSS-transition hints | safe, no downside |
| `ldpc / tx_stbc / rx_stbc / short_gi` | error-correction + antenna diversity + rate | small real SNR edge on supported clients |
| `he_su/mu_beamformer` + `mu_beamformer` (MU-MIMO) | focus energy toward clients | small real gain; on where useful |
| power-save | AP interfaces don't PS; not force-toggled | mt76#987 (PS-disconnect is a client-side issue) |

**Deliberately NOT changed (documented tradeoffs, left to the operator):**
- **`noscan '1'` on 2.4 GHz** — forces 40 MHz without the co-channel scan. Raises
  throughput but is a spec bend that **can hurt reliability in crowded RF**. Kept because
  it helps in a clean environment; set to `0` if you are surrounded by neighbours.
  (forum.gl-inet noscan thread.)
- **802.11r fast roaming** — only helps with *multiple* APs and can cause reconnect/band
  flapping with mixed clients; it is **not a range feature** and does nothing on a single
  AP. openwrt#9767.
- **160 MHz** — see above; stability-first stays at 80 MHz. mt76#748.
- **RSSI-based kick scripts** — these *reduce* reach (push weak clients off); only for
  multi-AP band-steering. Not used. barbieri wifi-disconnect-low-signal.

## 3. Throughput / CPU — the only real MT7621 wins (already applied)

MT7621 is a 2013 dual-core MIPS SoC with **hardware NAT (PPE) for wired routing** but
**no WED** (Wireless Ethernet Dispatch) block — so **there is no wireless hardware offload
on this SoC at all**; Wi-Fi is CPU-bound (~300 Mbps at 100% CPU) no matter the firmware.
Anyone selling "Wi-Fi turbo" for MT7621 is fighting the CPU. (openwrt/mt76#868.)

Applied, evidence-backed, upstream-blessed:
- **`packet_steering '2'`** in `network.globals` — spreads RX/TX softirq across both cores.
  Upstream enables packet steering by default on mt7621, which is a strong signal it
  measurably helps this exact SoC. (forum packet-steering 199045; ramips packet-steering
  default commit.)
- **`flow_offloading '1'` (software) + `flow_offloading_hw '0'`** in `firewall.defaults` —
  the nftables flowtable fastpath, in-tree. HW offload is intentionally **off**: it breaks
  SQM/QoS, has a history of PPPoE/firewall4 breakage on mt7621, and gives **zero** Wi-Fi
  benefit. Software offload is the safe baseline. (openwrt commit 424a9ae; #10354, #8837,
  #9241; gl-inet HW-accel docs.)

**Deliberately rejected as placebo/risky on this SoC:**
- **Shortcut-FE / SFE** (the coolsnowwolf/Turboacc headline) — redundant with the in-tree
  flowtable, out-of-tree, **kernel-panic history**, fragile across kernel bumps. turboacc
  README; forum SFE kernel-panic 11871.
- **BBR "acceleration"** — a router *forwards* traffic; BBR only affects flows the router
  originates, so it does nothing for client throughput. turboacc README.
- **Full-cone NAT** — needs patched core packages, security posture slightly weaker, and
  sometimes silently stays symmetric; only worth it for gaming/P2P NAT-type-A. immortalwrt#1177.
- **Experimental HWNAT driver ports / MT7621 "overclock" DTS** — panic-prone / heat &
  instability for little gain. coolsnowwolf/lede#9450.
- **irqbalance** — near-cosmetic once packet steering is on. forum 250246.

## 4. Device-specific defects (sourced) and how this build handles each

- **NAND ECC too weak — 4b/512B vs the chip's 8b/512B (openwrt#20878).** Real, but the fix
  is kernel/DTS-level and cannot be proven safe without flashing hardware, so it is an
  **opt-in** (`apply_nand_ecc=true`) in the from-source workflow; the default build keeps
  stock ECC = guaranteed boot. See `kernel-build/patch-dts.py`.
- **WAN no-DHCP regression on newer kernels (openwrt#16083).** A PHY/DSA change, not a Q20
  config error, and unfixed upstream. This box is primarily a **bridged AP** (WAN reserved
  for optional PPPoE), so the blast radius is small; if you use PPPoE WAN, verify the link
  on your target build or use a 23.05-based image. **Note:** the Q20 WAN uses a *real*
  gigabit PHY (`phy-handle = <&ethphy0>`), so a `fixed-link` "fix" does **not** apply and
  would break it — which is why the DTS script never touches gmac1.
- **mt7915 "message timed out" radio wedge (the biggest 7915 stability bug).** Fixed by
  recovery patches long since merged into mt76; the v25.12.5 tree (kernel 6.12) and the
  stock driver both already carry them. freifunk-gluon#3436.
- **Warm-reboot Wi-Fi death (openwrt#17895 / mt76#644).** mt7915e can fail init
  ("Message timeout") after a warm reboot because the stock `pcie-mt7621` PERST/init
  delays (100 ms) are too short for the chip's reset — Wi-Fi then stays dead until a
  power cycle. The from-source builds carry
  `kernel-build/patches/399-pcie-mt7621-longer-reset-delays.patch` (100 → 500 ms, pure
  timing, ~1.2 s slower boot) — the community-verified workaround, still unmerged
  upstream. On top of that, the Wi-Fi sentinel escalates to a full mt7915e module
  reload if a targeted heal fails twice (mt76#1083 DBDC zombie recovery), so even an
  undiagnosed radio wedge self-heals without a reboot.
- **Thermal-mutex throughput regression on MT7621 (openwrt/mt76#1059).** Reverting the
  mutex restores ~200→440 Mbps, but only matters if something reads the *mt7915* thermal
  sysfs at high frequency — and it reintroduces an MCU-access race. **This build avoids the
  regression by design:** the dashboard's frequent poll reads the cheap SoC
  `thermal_zone` sensor, and the mt7915 sensor is read only by the on-demand RF diagnostic
  (`cr6608-txpower-collect`, run-once, no cron loop). So the patch would add risk for no
  gain and is intentionally **not** applied.

## 5. Bottom line

The biggest real wins — recent mt76 (recovery patches), `disassoc_low_ack 0`, correct
`antenna_gain` + permissive country, 80 MHz, packet steering, software flow offload — are
all present. The biggest myths/risks — cranking dBm past PA linearity, `noscan` as "free
speed", 802.11r as a stability fix, SFE/BBR/fullcone turbo, and WED on a SoC that has no
WED — are understood and avoided. There is no secret sauce in any modded fork that unlocks
MT7621 silicon this build is leaving on the table; the honest ceiling is the CPU and the
PA, and the config already sits at it.

### Source index
- openwrt/mt76: #633 #657 #748 #868 #942 #987 #1059 · freifunk-gluon#3436
- openwrt/openwrt: #16083 #20878 #10354 #8837 #9241 · commit 424a9ae (mt7621 HW-NAT) · ramips packet-steering default
- luci: #5771 #5781 · openwrt#9767 (802.11r)
- coolsnowwolf/lede#9450 · immortalwrt#1177 · chenmozhijin/turboacc README
- gl-inet hardware-acceleration & SQM docs · patchwork ozlabs cell_density · spinics linux-wireless msg221720
