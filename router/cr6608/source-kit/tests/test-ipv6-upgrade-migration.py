#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


TEST_FILE = Path(__file__).resolve()
MIGRATION = TEST_FILE.parent.parent / "files/etc/uci-defaults/95-cr6608-dhcp-off"
SH_BIN = os.environ.get("CR6608_TEST_SH_BIN") or shutil.which("sh") or "/bin/sh"


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def save(path, value):
    path.write_text(json.dumps(value, sort_keys=True) + "\n", encoding="utf-8")


def fake_uci(argv):
    args = list(argv)
    while args and args[0].startswith("-"):
        args.pop(0)
    if not args:
        return 2
    command = args.pop(0)
    db_path = Path(os.environ["CR6608_TEST_UCI_DB"])
    db = load(db_path)

    if command == "get" and len(args) == 1:
        if args[0] not in db:
            return 1
        value = db[args[0]]
        print(value if not isinstance(value, list) else " ".join(value))
        return 0
    if command in ("set", "add_list") and len(args) == 1 and "=" in args[0]:
        key, value = args[0].split("=", 1)
        if command == "set":
            db[key] = value
        else:
            current = db.get(key, [])
            if not isinstance(current, list):
                current = [current]
            current.append(value)
            db[key] = current
        save(db_path, db)
        return 0
    if command == "delete" and len(args) == 1:
        key = args[0]
        found = False
        for candidate in list(db):
            if candidate == key or candidate.startswith(key + "."):
                del db[candidate]
                found = True
        if not found:
            return 1
        save(db_path, db)
        return 0
    if command == "commit" and len(args) == 1:
        with Path(os.environ["CR6608_TEST_COMMIT_LOG"]).open("a", encoding="utf-8") as handle:
            handle.write(args[0] + "\n")
        return 0
    return 2


def make_command(path, body):
    path.write_text("#!/bin/sh\n" + body + "\n", encoding="utf-8", newline="\n")
    path.chmod(0o755)


def base_db():
    return {
        "dhcp.@dnsmasq[0]": "dnsmasq",
        "dhcp.@dnsmasq[0].filter_aaaa": "1",
        "dhcp.odhcpd": "odhcpd",
        "dhcp.odhcpd.disabled": "1",
        "dhcp.odhcpd.maindhcp": "0",
        "network.loopback": "interface",
        "network.loopback.ipv6": "0",
        "network.lan": "interface",
        "network.lan.ipv6": "0",
        "network.lan.delegate": "0",
        "network.wan": "interface",
        "network.wan.disabled": "0",
        "network.wan.ipv6": "0",
        "network.wlanrescue": "interface",
        "network.wlanrescue.ipv6": "0",
        "cr6608quick.default": "quick",
        "smartap.quick": "quicksettings",
    }


def run_case(name, initial, runs=2):
    with tempfile.TemporaryDirectory(prefix=f"cr6608-ipv6-{name}-") as temp_name:
        temp = Path(temp_name)
        db_path = temp / "uci.json"
        save(db_path, initial)
        commit_log = temp / "commits.log"
        commit_log.touch()
        service_log = temp / "services.log"
        sysctl_log = temp / "sysctl.log"
        legacy_sysctl = temp / "12-cr6608-ipv6-off.conf"
        legacy_sysctl.write_text("net.ipv6.conf.all.disable_ipv6=1\n", encoding="utf-8")
        initd = temp / "init.d"
        initd.mkdir()

        fake_uci_path = temp / "uci"
        make_command(
            fake_uci_path,
            "exec " + shlex.quote(sys.executable) + " " + shlex.quote(str(TEST_FILE)) + ' --fake-uci "$@"',
        )
        fake_sysctl = temp / "sysctl"
        make_command(fake_sysctl, 'printf "%s\\n" "$*" >> "$CR6608_TEST_SYSCTL_LOG"')
        for service in ("odhcpd", "dnsmasq", "firewall"):
            make_command(
                initd / service,
                f'printf "{service} %s\\n" "$*" >> "$CR6608_TEST_SERVICE_LOG"',
            )

        env = os.environ.copy()
        env.update(
            {
                "CR6608_IPV6_UCI_BIN": str(fake_uci_path),
                "CR6608_IPV6_SYSCTL_BIN": str(fake_sysctl),
                "CR6608_IPV6_INITD_DIR": str(initd),
                "CR6608_IPV6_LEGACY_SYSCTL": str(legacy_sysctl),
                "CR6608_TEST_UCI_DB": str(db_path),
                "CR6608_TEST_COMMIT_LOG": str(commit_log),
                "CR6608_TEST_SERVICE_LOG": str(service_log),
                "CR6608_TEST_SYSCTL_LOG": str(sysctl_log),
            }
        )
        for iteration in range(runs):
            result = subprocess.run([SH_BIN, str(MIGRATION)], env=env, check=False)
            assert result.returncode == 0, f"{name}: migration run {iteration + 1} exited {result.returncode}"
        # Kernel IPv6 and ::1 are intentionally outside the product-policy
        # contract.  This harness keeps their compatibility inputs available,
        # but assertions below cover only routed interfaces and services.
        return load(db_path), commit_log.read_text(encoding="utf-8"), service_log.read_text(encoding="utf-8")


def assert_firewall(db, name):
    expected = {
        "cr6608_allow_dhcpv6": "Allow-DHCPv6",
        "cr6608_allow_mld": "Allow-MLD",
        "cr6608_allow_icmpv6_input": "Allow-ICMPv6-Input",
        "cr6608_allow_icmpv6_forward": "Allow-ICMPv6-Forward",
    }
    for section, rule_name in expected.items():
        assert db.get(f"firewall.{section}") == "rule", f"{name}: missing {section}"
        assert db.get(f"firewall.{section}.name") == rule_name, f"{name}: wrong {section} name"
        assert db.get(f"firewall.{section}.family") == "ipv6", f"{name}: wrong {section} family"
        assert db.get(f"firewall.{section}.target") == "ACCEPT", f"{name}: wrong {section} target"
    assert "packet-too-big" in db["firewall.cr6608_allow_icmpv6_input.icmp_type"]
    assert "packet-too-big" in db["firewall.cr6608_allow_icmpv6_forward.icmp_type"]
    for key, value in db.items():
        if key.startswith("firewall.cr6608_allow_") and isinstance(value, list):
            assert len(value) == len(set(value)), f"{name}: duplicate list values in {key}"


def main():
    legacy_pppoe = base_db()
    legacy_pppoe["network.wan.proto"] = "pppoe"
    legacy_pppoe["dhcp.lan"] = "dhcp"
    migrated, commits, services = run_case("legacy-pppoe", legacy_pppoe)
    assert migrated["network.lan.ipv6"] == "0"
    assert migrated["network.wan.ipv6"] == "0"
    assert migrated["network.lan.delegate"] == "0"
    assert "network.lan.ip6assign" not in migrated
    assert migrated["dhcp.odhcpd.disabled"] == "1"
    assert migrated["dhcp.@dnsmasq[0].filter_aaaa"] == "1"
    assert migrated["dhcp.lan.dhcpv6"] == "disabled"
    assert migrated["dhcp.lan.ra"] == "disabled"
    assert "dhcp.lan.ra_slaac" not in migrated
    assert migrated["dhcp.lan.ndp"] == "disabled"
    assert migrated["cr6608quick.default.ipv6_enabled"] == "0"
    assert migrated["smartap.quick.ipv6_enabled"] == "0"
    assert migrated["network.wlanrescue.ipv6"] == "0"
    assert not any(key.startswith("firewall.cr6608_allow_") for key in migrated)
    assert "firewall\n" not in commits and "firewall reload\n" not in services
    assert "odhcpd disable\n" in services and "odhcpd stop\n" in services

    legacy_ap = base_db()
    legacy_ap["network.wan.proto"] = "none"
    legacy_ap["dhcp.odhcpd.disabled"] = "0"
    migrated, _, _ = run_case("legacy-ap", legacy_ap)
    assert migrated["network.lan.ipv6"] == "0"
    assert migrated["network.wan.ipv6"] == "0"
    assert migrated["dhcp.odhcpd.disabled"] == "1"
    assert migrated["dhcp.@dnsmasq[0].filter_aaaa"] == "1"
    assert migrated["cr6608quick.default.ipv6_enabled"] == "0"
    assert migrated["smartap.quick.ipv6_enabled"] == "0"
    assert migrated["network.wlanrescue.ipv6"] == "0"
    assert not any(key.startswith("firewall.cr6608_allow_") for key in migrated)

    explicit_on = base_db()
    explicit_on["network.wan.proto"] = "pppoe"
    explicit_on["network.wan.ipv6"] = "auto"
    explicit_on["network.lan.ipv6"] = "0"
    explicit_on["network.lan.delegate"] = "0"
    explicit_on["dhcp.lan"] = "dhcp"
    explicit_on["cr6608quick.default.ipv6_enabled"] = "1"
    explicit_on["smartap.quick.ipv6_enabled"] = "1"
    migrated, commits, services = run_case("explicit-on", explicit_on)
    # A preserved explicit On choice is no longer authoritative: v86 adopts
    # the fixed product-off policy and synchronizes both legacy stores.
    assert migrated["network.lan.ipv6"] == "0"
    assert migrated["network.wan.ipv6"] == "0"
    assert migrated["network.lan.delegate"] == "0"
    assert "network.lan.ip6assign" not in migrated
    assert migrated["dhcp.odhcpd.disabled"] == "1"
    assert migrated["dhcp.@dnsmasq[0].filter_aaaa"] == "1"
    assert migrated["dhcp.lan.dhcpv6"] == "disabled"
    assert migrated["dhcp.lan.ra"] == "disabled"
    assert "dhcp.lan.ra_slaac" not in migrated
    assert migrated["dhcp.lan.ndp"] == "disabled"
    assert migrated["cr6608quick.default.ipv6_enabled"] == "0"
    assert migrated["smartap.quick.ipv6_enabled"] == "0"
    assert not any(key.startswith("firewall.cr6608_allow_") for key in migrated)
    assert "firewall\n" not in commits and "firewall reload\n" not in services
    assert "odhcpd disable\n" in services and "odhcpd stop\n" in services

    explicit_off = base_db()
    explicit_off["network.wan.proto"] = "pppoe"
    explicit_off["network.wan6"] = "interface"
    explicit_off["network.wan6.proto"] = "dhcpv6"
    explicit_off["network.wan6.disabled"] = "0"
    explicit_off["dhcp.lan"] = "dhcp"
    explicit_off["dhcp.lan.dhcpv6"] = "server"
    explicit_off["dhcp.lan.ra"] = "server"
    explicit_off["dhcp.lan.ra_slaac"] = "1"
    explicit_off["dhcp.odhcpd.disabled"] = "0"
    explicit_off["dhcp.@dnsmasq[0].filter_aaaa"] = "0"
    explicit_off["cr6608quick.default.ipv6_enabled"] = "0"
    explicit_off["smartap.quick.ipv6_enabled"] = "0"
    migrated, commits, services = run_case("explicit-off", explicit_off)
    assert migrated["network.lan.ipv6"] == "0"
    assert migrated["network.wan.ipv6"] == "0"
    assert migrated["network.wan6.disabled"] == "1"
    assert migrated["network.lan.delegate"] == "0"
    assert migrated["dhcp.odhcpd.disabled"] == "1"
    assert migrated["dhcp.@dnsmasq[0].filter_aaaa"] == "1"
    assert migrated["dhcp.lan.dhcpv6"] == "disabled"
    assert migrated["dhcp.lan.ra"] == "disabled"
    assert "dhcp.lan.ra_slaac" not in migrated
    assert migrated["network.wlanrescue.ipv6"] == "0"
    assert not any(key.startswith("firewall.cr6608_allow_") for key in migrated)
    assert "firewall\n" not in commits and "firewall reload\n" not in services
    assert "odhcpd disable\n" in services and "odhcpd stop\n" in services

    print("ipv6_upgrade_migration=pass")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--fake-uci":
        raise SystemExit(fake_uci(sys.argv[2:]))
    main()
