#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
AUDIT = ROOT / "tools" / "cr6608-fleet-mac-audit.py"


def report(path: pathlib.Path, device: str, suffix: int) -> None:
    base = 0xD43538000000 + suffix * 16
    roles = {
        role: ":".join(f"{(base + offset):012x}"[i : i + 2] for i in range(0, 12, 2))
        for role, offset in zip(("lan", "wan", "wifi24", "wifi5"), range(4))
    }
    path.write_text(json.dumps({"ok": True, "status": "PASS", "device_id": device, "roles": roles}), encoding="utf-8")


with tempfile.TemporaryDirectory(prefix="cr6608-fleet-") as temp:
    root = pathlib.Path(temp)
    first, second = root / "a.json", root / "b.json"
    report(first, "unit-a", 1)
    report(second, "unit-b", 2)
    subprocess.run(
        [sys.executable, str(AUDIT), "--expected-devices", "2", str(first), str(second)],
        check=True,
        capture_output=True,
        text=True,
    )
    wrong_count = subprocess.run(
        [sys.executable, str(AUDIT), "--json", "--expected-devices", "50", str(first), str(second)],
        capture_output=True,
        text=True,
    )
    assert wrong_count.returncode == 1
    assert "expected 50 unique devices" in json.loads(wrong_count.stdout)["errors"][0]

    local = json.loads(second.read_text(encoding="utf-8"))
    local["roles"]["wifi5"] = "d6:35:38:00:00:01"
    second.write_text(json.dumps(local), encoding="utf-8")
    local_failed = subprocess.run(
        [sys.executable, str(AUDIT), "--json", str(first), str(second)],
        capture_output=True,
        text=True,
    )
    assert local_failed.returncode == 1
    assert "globally administered" in json.loads(local_failed.stdout)["errors"][0]
    report(second, "unit-b", 2)

    duplicate = json.loads(second.read_text(encoding="utf-8"))
    duplicate["roles"]["wan"] = json.loads(first.read_text(encoding="utf-8"))["roles"]["lan"]
    second.write_text(json.dumps(duplicate), encoding="utf-8")
    failed = subprocess.run([sys.executable, str(AUDIT), "--json", str(first), str(second)], capture_output=True, text=True)
    assert failed.returncode == 1
    assert json.loads(failed.stdout)["ok"] is False

print("fleet_mac_audit_tests=pass")
