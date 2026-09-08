#!/usr/bin/env python3
"""Install and open both real APKs; capture startup crashes before release publication."""
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "CardManagerApp/build/startup"
OUT.mkdir(parents=True, exist_ok=True)

def adb(*args, timeout=60, check=True):
    return subprocess.run(["adb", *args], capture_output=True, timeout=timeout, check=check)

results = []
for name, package in [("CardManager.apk", "com.binwaps.cardmanager"),
                      ("CardManager-Admin.apk", "com.binwaps.cardmanager.admin")]:
    result = {"apk": name, "package": package, "api": adb("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip()}
    try:
        adb("install", "-r", str(ROOT / name), timeout=120)
        # The runner is a disposable emulator with no user data.
        adb("shell", "pm", "clear", package)
        for attempt in range(2):
            adb("shell", "am", "force-stop", package)
            adb("logcat", "-c")
            start = adb("shell", "am", "start", "-W", "-n", package + "/com.binwaps.cardmanager.MainActivity")
            (OUT / f"{package}-{attempt}-launch.txt").write_bytes(start.stdout + start.stderr)
            for _ in range(12):
                time.sleep(1)
                if not adb("shell", "pidof", package, check=False).stdout.strip():
                    raise AssertionError("Application process exited after launch")
            activities = adb("shell", "dumpsys", "activity", "activities").stdout.decode(errors="replace")
            (OUT / f"{package}-{attempt}-activity.txt").write_text(activities)
            resumed = [line for line in activities.splitlines() if "ResumedActivity" in line]
            if not any(package + "/" in line for line in resumed):
                raise AssertionError("Application did not remain in the foreground")
            (OUT / f"{package}-{attempt}.png").write_bytes(adb("exec-out", "screencap", "-p").stdout)
        result["passed"] = True
    except Exception as error:
        result.update(passed=False, error=str(error))
    finally:
        crash = adb("logcat", "-d", "-b", "crash", check=False).stdout
        (OUT / f"{package}-crash.txt").write_bytes(crash)
        if not result.get("passed"):
            print(crash.decode(errors="replace")[-20000:])
        (OUT / f"{package}-logcat.txt").write_bytes(adb("logcat", "-d", "-s", "AndroidRuntime:E", "System.err:W", check=False).stdout)
        results.append(result)

(OUT / "results.json").write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
raise SystemExit(0 if all(item["passed"] for item in results) else 1)
