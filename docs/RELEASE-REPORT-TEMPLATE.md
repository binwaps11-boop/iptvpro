# CR6608 Firmware Release Report — v__

> Filled by `release-gatekeeper`. A build is `final` only when every section below is
> proven (PASS) with real router evidence. Otherwise status = `candidate`.

- **candidate/final bin path**:
- **SHA256**:
- **size (bytes)**:

## Modified files
- (file → what changed → why)

## Inspected files (image-inspector)
- (file → present? evidence)

## Build summary (openwrt-build-engineer)
- source/tag or repack | kernel hash | metadata round-trip | warnings

## Image inspection result (image-inspector)
- PASS/FAIL table with literal evidence

## Router boot test
- boots? dashboard reachable? Wi-Fi up? (real device)

## Verification commands output (router-ssh-test-runner) — FULL, untruncated
```
<paste iw dev / iw phy / iw reg get / iwinfo / /sys/module params / station dump /
 txpower_sku / logread here, verbatim>
```

## dmesg result (log-analyzer)
- clean? errors/warnings with root cause

## Hardware-limits audit (safety-hardware-limits-auditor)
- requested vs measured power | binding constraint | any fake-number flags

## Regression check (regression-comparator)
- KEPT / ADDED / CHANGED / LOST vs previous build

## Verdict
- **PASS / FAIL**

## Technical explanation
- (why it passed, or the exact technical cause of failure)
