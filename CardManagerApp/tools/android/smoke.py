#!/usr/bin/env python3
"""Install and open both real APKs; capture startup crashes before release publication."""
import json
import os
from pathlib import Path
import subprocess
import time
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "CardManagerApp/build/startup"
OUT.mkdir(parents=True, exist_ok=True)

def adb(*args, timeout=60, check=True):
    return subprocess.run(["adb", *args], capture_output=True, timeout=timeout, check=check)

api = adb("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip()
OUT = OUT / ("api-" + api)
OUT.mkdir(parents=True, exist_ok=True)
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
            # Android 8 logd may refuse clearing one buffer. Clearing is only
            # housekeeping; process, foreground and crash-log checks remain required.
            cleared = adb("logcat", "-c", check=False)
            if cleared.returncode:
                print("Log buffer clear unavailable:", cleared.stderr.decode(errors="replace").strip())
            start = adb("shell", "am", "start", "-W", "-n", package + "/com.binwaps.cardmanager.MainActivity")
            (OUT / f"{package}-{attempt}-launch.txt").write_bytes(start.stdout + start.stderr)
            for _ in range(12):
                time.sleep(1)
                if not adb("shell", "pidof", package, check=False).stdout.strip():
                    raise AssertionError("Application process exited after launch")
            if attempt == 0:
                # Exercise the post-setup form, where the old mixed-unit label animation crashed.
                adb("shell", "uiautomator", "dump", "/sdcard/cardmanager-ui.xml")
                tree = ET.fromstring(adb("shell", "cat", "/sdcard/cardmanager-ui.xml").stdout)
                fields = [n for n in tree.iter('node') if n.get('class') == 'android.widget.EditText']
                if not fields: raise AssertionError('No setup field rendered')
                def tap_node(n):
                    x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get('bounds', '')))
                    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
                tap_node(fields[0])
                adb('shell','input','text','https://example.invalid')
                adb('shell','input','keyevent','4')
                adb('shell','uiautomator','dump','/sdcard/cardmanager-ui.xml')
                tree = ET.fromstring(adb('shell','cat','/sdcard/cardmanager-ui.xml').stdout)
                buttons = [n for n in tree.iter('node') if n.get('text') == 'حفظ ومتابعة']
                if not buttons: raise AssertionError('Continue button missing')
                tap_node(buttons[0])
                time.sleep(3)
                if not adb('shell','pidof',package,check=False).stdout.strip():
                    raise AssertionError('Application exited on subscription form')
            activities = adb("shell", "dumpsys", "activity", "activities").stdout.decode(errors="replace")
            (OUT / f"{package}-{attempt}-activity.txt").write_text(activities)
            resumed = [line for line in activities.splitlines() if "ResumedActivity" in line]
            if not any(package + "/" in line for line in resumed):
                raise AssertionError("Application did not remain in the foreground")
            (OUT / f"{package}-{attempt}.png").write_bytes(adb("exec-out", "screencap", "-p").stdout)
        crash_log = adb("logcat", "-d", "-b", "crash", check=False).stdout
        if b"FATAL EXCEPTION" in crash_log or b"Fatal signal" in crash_log:
            raise AssertionError("Crash recorded during startup")
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
