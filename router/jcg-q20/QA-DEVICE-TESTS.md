# SmartAP device-level QA (hardware-only tests)

Two reliability guarantees can only be proven on real Q20 / CR6608 hardware (CI builds the
image but never boots the PCIe/mt76 stack). Run these on a **test unit**, never production.

## 1. Warm-reboot Wi-Fi re-probe  (automated — finding #1)

The daily scheduled reboot exercises this fleet-wide, so it must be proven.

```sh
smartap-reboot-test arm 20            # Phase A: 20 pure warm-reboot cycles
#   ... device reboots repeatedly; then on any unit:
smartap-reboot-test status            # shows PASS (20/20) or FAIL@cycleN
smartap-reboot-test arm 20 --reload   # Phase B: inject `wifi reload` 5s before each reboot
smartap-reboot-test disarm            # stop early / clean up
```
PASS = every cycle came up with 2 phys (`/sys/class/ieee80211`) and ≥2 wifi interfaces
(`iw dev`); since Wi-Fi ships OPEN, 2 interfaces == both SSIDs beaconing. A FAIL halts the
loop with the box up for inspection (check `logread | grep mt7915`).

## 2. Commit-confirm rollback / failover  (manual — finding #6)

The safe-apply engine is the last defense against a bricked truck-roll. Verify all three:

- **Test A (timer expiry):** apply a management-blocking change from Quick Settings, do NOT
  press *Keep changes*; confirm management returns within `timeout + margin`
  (120 s normal, up to 720 s for DFS/HE160/auto-5G — the countdown now shows the real window).
- **Test B (power-cut):** arm the change, hard-cut power BEFORE the timer fires; confirm the
  boot rollback restores dropbear/uhttpd/LAN-IP/firewall from the tgz.
- **Test C (retain-IP):** change the LAN IP and confirm the retained OLD IP stays pingable
  until you explicitly confirm.

The `CR6608_SAFE_*` env vars make the state machine host-unit-testable for the logic, but the
true power-loss boot path needs hardware.
