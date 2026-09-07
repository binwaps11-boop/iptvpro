#!/usr/bin/env bash
set -euo pipefail
app_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
check_dir="$app_root/build/performance"
mkdir -p "$check_dir/classes"
java com.sun.tools.javac.Main --release 17 -Xlint:all -d "$check_dir/classes" \
  "$app_root/app/src/main/java/com/binwaps/cardmanager/performance/CodePool.java" \
  "$app_root/app/src/main/java/com/binwaps/cardmanager/performance/PageSlices.java" \
  "$app_root/app/src/main/java/com/binwaps/cardmanager/performance/ThroughputMeter.java" \
  "$app_root/app/src/main/java/com/binwaps/cardmanager/performance/PdfParts.java" \
  "$app_root/tools/performance/PerformanceChecks.java" \
  "$app_root/tools/performance/PdfRecoveryChecks.java"
java -cp "$check_dir/classes" PerformanceChecks | tee "$check_dir/report.json"
java -cp "$check_dir/classes" PdfRecoveryChecks | tee "$check_dir/recovery.json"
