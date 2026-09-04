#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import re


TEST_FILE = Path(__file__).resolve()
KIT_DIR = TEST_FILE.parent.parent
MIGRATION = KIT_DIR / "files/etc/uci-defaults/99-cr6608-preserved-config-v2"
FIXTURES = TEST_FILE.parent / "fixtures/preserved-config-migration"
RPCD_ROOT_PASSWORD = "$6$CR6608dashAdm$BQqw1LRyISWT1W76KgXLbFMpuB0lDBY4CVz7vdm4PMg1YZ6y9fh.GZ0hKRp8X9NGb4FR5dGd7lsMiuCOK3hwl."
SUPPORTED_BOARD = "xiaomi,mi-router-cr6608"
TEST_SHELL = os.environ.get("CR6608_TEST_SHELL", "/bin/sh")
TEST_SHELL_ARGS = shlex.split(os.environ.get("CR6608_TEST_SHELL_ARGS", ""))
TEST_TMPDIR = os.environ.get("CR6608_TEST_TMPDIR") or None
TEST_PATH_PREFIX = os.environ.get("CR6608_TEST_PATH_PREFIX") or None
WIRELESS_FIXTURE = {
    "wireless.radio0": "wifi-device",
    "wireless.radio0.disabled": "1",
    "wireless.radio1": "wifi-device",
    "wireless.radio1.disabled": "1",
    "wireless.wifinet0": "wifi-iface",
    "wireless.wifinet0.device": "radio0",
    "wireless.wifinet0.mode": "ap",
    "wireless.wifinet0.disabled": "1",
    "wireless.wifinet0.hidden": "1",
    "wireless.wifinet0.encryption": "psk2",
    "wireless.wifinet0.ieee80211w": "1",
    "wireless.wifinet0.key": "primary-24-secret-must-be-deleted",
    "wireless.wifinet0.sae_password": "primary-24-sae-must-be-deleted",
    "wireless.wifinet1": "wifi-iface",
    "wireless.wifinet1.device": "radio1",
    "wireless.wifinet1.mode": "ap",
    "wireless.wifinet1.disabled": "1",
    "wireless.wifinet1.hidden": "1",
    "wireless.wifinet1.encryption": "sae-mixed",
    "wireless.wifinet1.ieee80211w": "2",
    "wireless.wifinet1.key": "primary-5-secret-must-be-deleted",
    "wireless.wifinet1.sae_password": "primary-5-sae-must-be-deleted",
    "wireless.guest": "wifi-iface",
    "wireless.guest.device": "radio0",
    "wireless.guest.mode": "ap",
    "wireless.guest.disabled": "1",
    "wireless.guest.hidden": "1",
    "wireless.guest.encryption": "psk2",
    "wireless.guest.ieee80211w": "1",
    "wireless.guest.key": "guest-secret-must-not-change",
    "wireless.mesh": "wifi-iface",
    "wireless.mesh.device": "radio1",
    "wireless.mesh.mode": "mesh",
    "wireless.mesh.disabled": "1",
    "wireless.mesh.hidden": "1",
    "wireless.mesh.encryption": "sae",
    "wireless.mesh.ieee80211w": "2",
    "wireless.mesh.key": "mesh-key-must-not-change",
    "wireless.mesh.sae_password": "mesh-sae-must-not-change",
    "wireless.operator_extra": "wifi-iface",
    "wireless.operator_extra.device": "radio1",
    "wireless.operator_extra.mode": "ap",
    "wireless.operator_extra.disabled": "1",
    "wireless.operator_extra.hidden": "1",
    "wireless.operator_extra.encryption": "psk2",
    "wireless.operator_extra.key": "extra-secret-must-not-change",
}


SHA512_CRYPT_RE = re.compile(
    r"^\$6\$(?:rounds=([0-9]{1,9})\$)?([./0-9A-Za-z]{1,16})\$([./0-9A-Za-z]{86})$"
)


def preservable_lab_rpcd_hash(value):
    if not isinstance(value, str) or value == RPCD_ROOT_PASSWORD:
        return False
    match = SHA512_CRYPT_RE.fullmatch(value)
    if not match:
        return False
    if match.group(1) is not None and not 1000 <= int(match.group(1)) <= 999_999_999:
        return False
    return True


def shell_path(path):
    """Translate Windows paths only when an explicit MSYS test shell is used."""
    value = str(path)
    if os.name != "nt" or TEST_SHELL == "/bin/sh":
        return value
    drive, tail = os.path.splitdrive(value)
    if not drive:
        return value.replace("\\", "/")
    posix_tail = tail.replace("\\", "/")
    return f"/{drive[0].lower()}{posix_tail}"


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path, value):
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
    tmp.replace(path)


def fake_uci(argv):
    db_path = Path(os.environ["FAKE_UCI_DB"])
    ops_path = Path(os.environ["FAKE_UCI_OPS"])
    args = list(argv)
    while args and args[0].startswith("-"):
        args.pop(0)
    if not args:
        return 2

    command = args.pop(0)
    db = load_json(db_path)

    if command == "get" and len(args) == 1:
        key = args[0]
        if key not in db:
            return 1
        print(db[key])
        return 0

    if command == "add" and args == ["rpcd", "login"]:
        indexes = [
            int(match.group(1))
            for key in db
            if (match := re.fullmatch(r"rpcd\.@login\[(\d+)\]", key))
        ]
        section = f"@login[{max(indexes, default=-1) + 1}]"
        db[f"rpcd.{section}"] = "login"
        save_json(db_path, db)
        print(section)
        operation = ["add", "rpcd", "login", section]
    elif command == "set" and len(args) == 1 and "=" in args[0]:
        key, value = args[0].split("=", 1)
        db[key] = value
        save_json(db_path, db)
        operation = ["set", key, value]
    elif command == "add_list" and len(args) == 1 and "=" in args[0]:
        key, value = args[0].split("=", 1)
        db[key] = value
        save_json(db_path, db)
        operation = ["add_list", key, value]
    elif command == "delete" and len(args) == 1:
        key = args[0]
        if key not in db:
            return 1
        del db[key]
        save_json(db_path, db)
        operation = ["delete", key]
    elif command == "commit" and len(args) == 1:
        operation = ["commit", args[0]]
    else:
        return 2

    with ops_path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(operation, separators=(",", ":")) + "\n")
    return 0


def digest_tree(root):
    result = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        result[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def expected_after_migration(before, retail_provisioned=False):
    expected = dict(before)
    if not retail_provisioned:
        root_section = next(
            (
                key.rsplit(".", 1)[0]
                for key, value in before.items()
                if key.startswith("rpcd.@login[")
                and key.endswith(".username")
                and value == "root"
            ),
            None,
        )
        if root_section is None:
            indexes = [
                int(match.group(1))
                for key in before
                if (match := re.fullmatch(r"rpcd\.@login\[(\d+)\]", key))
            ]
            root_section = f"rpcd.@login[{max(indexes, default=-1) + 1}]"
            expected[root_section] = "login"
            expected[f"{root_section}.username"] = "root"
        preserved_password = before.get(f"{root_section}.password")
        expected[f"{root_section}.password"] = (
            preserved_password
            if preservable_lab_rpcd_hash(preserved_password)
            else RPCD_ROOT_PASSWORD
        )
        expected[f"{root_section}.read"] = "*"
        expected[f"{root_section}.write"] = "*"
    if before.get("cr6608quick.default"):
        expected["cr6608quick.default.clear_previous"] = "0"
    if before.get("smartap.quick"):
        expected["smartap.quick.delete_previous"] = "0"
    if before.get("network.globals.packet_steering") != "0":
        expected["network.globals.packet_steering"] = "0"
    if not retail_provisioned:
        for radio in ("radio0", "radio1"):
            expected[f"wireless.{radio}.disabled"] = "0"
        for iface in ("wifinet0", "wifinet1"):
            expected[f"wireless.{iface}.disabled"] = "0"
            expected[f"wireless.{iface}.hidden"] = "0"
            expected[f"wireless.{iface}.encryption"] = "none"
            expected[f"wireless.{iface}.ieee80211w"] = "0"
            expected.pop(f"wireless.{iface}.key", None)
            expected.pop(f"wireless.{iface}.sae_password", None)
    expected["smartap.migration"] = "migration"
    expected["smartap.migration.preserved_config_version"] = "8"
    return expected


def run_fixture(name, *, case_name=None, root_password_override=None):
    fixture = load_json(FIXTURES / f"{name}.json")
    case_name = case_name or name
    with tempfile.TemporaryDirectory(
        prefix=f"cr6608-migration-{case_name}-", dir=TEST_TMPDIR
    ) as temp_name:
        temp = Path(temp_name)
        board = temp / "board_name"
        board.write_text(fixture["board_name"] + "\n", encoding="utf-8")
        db = temp / "uci.json"
        initial_uci = dict(fixture["uci"])
        if root_password_override is not None:
            root_section = next(
                key.rsplit(".", 1)[0]
                for key, value in initial_uci.items()
                if key.startswith("rpcd.@login[")
                and key.endswith(".username")
                and value == "root"
            )
            initial_uci[f"{root_section}.password"] = root_password_override
        initial_uci.update(WIRELESS_FIXTURE)
        save_json(db, initial_uci)
        ops = temp / "operations.jsonl"
        ops.touch()
        fixture_root = temp / "rootfs"
        for relative, content in fixture["files"].items():
            target = fixture_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8", newline="\n")

        fake = temp / "uci"
        fake.write_text(
            "#!/bin/sh\nexec "
            + shlex.quote(shell_path(sys.executable))
            + " "
            + shlex.quote(shell_path(TEST_FILE))
            + " --fake-uci \"$@\"\n",
            encoding="utf-8",
            newline="\n",
        )
        fake.chmod(0o755)
        fake_stat = temp / "stat"
        fake_stat.write_text(
            "#!/bin/sh\n"
            "[ \"$1\" = -c ] || exit 2\n"
            "case \"$2\" in '%u') printf '0\\n' ;; '%a') printf '400\\n' ;; *) exit 2 ;; esac\n",
            encoding="utf-8",
            newline="\n",
        )
        fake_stat.chmod(0o755)

        env = os.environ.copy()
        if TEST_PATH_PREFIX:
            env["PATH"] = TEST_PATH_PREFIX + os.pathsep + env.get("PATH", "")
        env.update(
            {
                "CR6608_MIGRATION_BOARD_NAME_FILE": shell_path(board),
                "CR6608_MIGRATION_UCI_BIN": shell_path(fake),
                "CR6608_MIGRATION_LOGGER_BIN": "/bin/true",
                "CR6608_MIGRATION_RETAIL_MARKER": shell_path(
                    fixture_root / "etc/cr6608-retail-provisioned"
                ),
                "CR6608_MIGRATION_PENDING_MARKER": shell_path(
                    fixture_root / "etc/cr6608-retail-provisioning-pending"
                ),
                "CR6608_MIGRATION_STAT_BIN": shell_path(fake_stat),
                "FAKE_UCI_DB": str(db),
                "FAKE_UCI_OPS": str(ops),
            }
        )
        file_hashes = digest_tree(fixture_root)
        before = load_json(db)
        retail_provisioned = "etc/cr6608-retail-provisioned" in fixture["files"]

        command = [TEST_SHELL, *TEST_SHELL_ARGS, shell_path(MIGRATION)]
        first = subprocess.run(command, env=env, check=False)
        assert first.returncode == 0, f"{case_name}: migration exited {first.returncode}"
        after = load_json(db)
        assert digest_tree(fixture_root) == file_hashes, f"{case_name}: non-UCI sentinel changed"

        if fixture["board_name"] == SUPPORTED_BOARD:
            expected = expected_after_migration(before, retail_provisioned)
            unexpected = {
                key: {"expected": expected.get(key), "actual": after.get(key)}
                for key in sorted(set(expected) | set(after))
                if expected.get(key) != after.get(key)
            }
            assert after == expected, f"{case_name}: unexpected UCI mutation: {unexpected}"
            operation_lines = ops.read_text(encoding="utf-8").splitlines()
            operations = [json.loads(line) for line in operation_lines]
            for operation in operations:
                if len(operation) < 2:
                    continue
                target = operation[1]
                assert not any(
                    target.startswith(f"wireless.{section}")
                    for section in ("guest", "mesh", "operator_extra")
                ), f"{case_name}: migration touched an additional wireless interface: {operation}"
                if retail_provisioned:
                    assert not target.startswith(("rpcd.", "wireless.")), (
                        f"{case_name}: provisioned security state was modified: {operation}"
                    )
            operation_count = len(operation_lines)
            second = subprocess.run(command, env=env, check=False)
            assert second.returncode == 0, f"{case_name}: idempotent run exited {second.returncode}"
            assert load_json(db) == after, f"{case_name}: idempotent run changed UCI"
            assert len(ops.read_text(encoding="utf-8").splitlines()) == operation_count, (
                f"{case_name}: marker did not suppress repeated writes"
            )
        else:
            assert after == before, f"{case_name}: wrong board was modified"
            assert ops.read_text(encoding="utf-8") == "", f"{case_name}: wrong board invoked UCI writes"


def main():
    source = MIGRATION.read_text(encoding="utf-8")
    for forbidden in (
        "/etc/shadow",
        "chpasswd",
        "passwd root",
        "dropbear.",
        "dhcp.",
        ".ipaddr",
        "/dev/mtd",
        "factory.",
    ):
        assert forbidden not in source, f"migration contains forbidden mutation path: {forbidden}"

    run_fixture("clean")
    run_fixture(
        "clean",
        case_name="fresh-default-hash",
        root_password_override=RPCD_ROOT_PASSWORD,
    )
    run_fixture(
        "clean",
        case_name="invalid-sha512-hash",
        root_password_override="$6$validsalt$truncated",
    )
    run_fixture("preserved")
    run_fixture("marker-v3-stale")
    run_fixture("marker-v4-stale")
    run_fixture("missing-root")
    run_fixture("retail-provisioned")
    run_fixture("wrong-board")
    print("preserved_config_migration=pass")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--fake-uci":
        raise SystemExit(fake_uci(sys.argv[2:]))
    main()
