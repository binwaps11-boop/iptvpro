#!/usr/bin/env python3
"""Reject invalid or duplicate CR6608 factory identities across a fleet.

Each input is a JSON file produced by `cr6608-mac-verify --json`. The filename
is used as the unit identifier unless the document contains `device_id`.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


ROLES = ("lan", "wan", "wifi24", "wifi5")
MAC_RE = re.compile(r"^[0-9a-f]{2}(?::[0-9a-f]{2}){5}$")


def fail(message: str) -> None:
    raise ValueError(message)


def load_unit(path: pathlib.Path) -> tuple[str, dict[str, str]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"{path}: unreadable verifier JSON: {exc}")
    unit = str(payload.get("device_id") or path.stem).strip()
    if not unit:
        fail(f"{path}: empty device identifier")
    if payload.get("ok") is not True or payload.get("status") != "PASS":
        fail(f"{unit}: on-device MAC verification did not pass")
    roles = payload.get("roles")
    if not isinstance(roles, dict):
        fail(f"{unit}: roles object is missing")
    normalized: dict[str, str] = {}
    for role in ROLES:
        value = str(roles.get(role, "")).lower()
        if not MAC_RE.fullmatch(value):
            fail(f"{unit}: invalid {role} MAC {value!r}")
        first = int(value[0:2], 16)
        if first & 3 or value in {"00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff"}:
            fail(f"{unit}: MAC for {role} is not a globally administered unicast address: {value}")
        normalized[role] = value
    if len(set(normalized.values())) != len(ROLES):
        fail(f"{unit}: duplicate factory role MAC within device")
    return unit, normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+", type=pathlib.Path)
    parser.add_argument("--json", action="store_true", dest="as_json")
    parser.add_argument("--expected-devices", type=int, default=None)
    args = parser.parse_args()

    units: dict[str, dict[str, str]] = {}
    owners: dict[str, tuple[str, str]] = {}
    errors: list[str] = []
    for report in args.reports:
        try:
            unit, roles = load_unit(report)
            if unit in units:
                fail(f"duplicate device identifier {unit!r}")
            for role, mac in roles.items():
                if mac in owners:
                    other_unit, other_role = owners[mac]
                    fail(f"{unit}/{role} duplicates {other_unit}/{other_role}: {mac}")
                owners[mac] = (unit, role)
            units[unit] = roles
        except ValueError as exc:
            errors.append(str(exc))

    if args.expected_devices is not None:
        if args.expected_devices < 1:
            errors.append("--expected-devices must be at least 1")
        elif len(units) != args.expected_devices:
            errors.append(
                f"expected {args.expected_devices} unique devices, received {len(units)} valid reports"
            )

    result = {
        "ok": not errors,
        "devices": len(units),
        "identities": len(owners),
        "errors": errors,
    }
    if args.as_json:
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    else:
        status = "PASS" if result["ok"] else "FAIL"
        print(f"fleet_mac_audit={status} devices={result['devices']} identities={result['identities']}")
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
