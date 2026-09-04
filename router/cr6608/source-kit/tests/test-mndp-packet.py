#!/usr/bin/env python3

import os
import pathlib
import socket
import stat
import struct
import subprocess
import sys
import tempfile


def fail(message: str) -> None:
    raise SystemExit(f"mndp_packet=fail: {message}")


if len(sys.argv) != 2:
    fail("compiled sender path required")

sender = pathlib.Path(sys.argv[1])
if not sender.is_file():
    fail("compiled sender missing")

with tempfile.TemporaryDirectory(prefix="cr6608-mndp-") as temp_name:
    temp = pathlib.Path(temp_name)
    os.chmod(temp, 0o700)
    fields = temp / "fields"
    values = [
        "Customer CR6608",
        "SmartAP CR6608",
        "OpenWrt 25.12.0",
        "Xiaomi CR6608",
        "1",
        "30",
    ]
    fields.write_text("\n".join(values) + "\n", encoding="utf-8")
    os.chmod(fields, 0o600)

    drain_test = subprocess.run(
        [str(sender), "--drain-selftest"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if drain_test.returncode != 0 or drain_test.stdout.strip() != "mndp_drain_selftest=pass":
        fail("bounded nonblocking receive-drain selftest failed")

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe_receiver:
        probe_receiver.bind(("127.0.0.1", 0))
        probe_receiver.settimeout(1)
        probe_port = probe_receiver.getsockname()[1]
        live_probe = subprocess.run(
            [str(sender), "--inject-live-probe", str(probe_port)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if live_probe.returncode != 0 or live_probe.stdout.strip() != "mndp_live_queue_probe=sent:80":
            fail("deterministic live receive-queue injection probe failed")
        try:
            received_probe_count = sum(1 for _ in range(80) if probe_receiver.recv(16))
        except TimeoutError:
            fail("deterministic live receive-queue injection probe lost datagrams")
        if received_probe_count != 80:
            fail("deterministic live receive-queue injection probe count mismatch")

    command = [
        str(sender),
        "--encode-hex",
        "d4:35:38:d4:f3:c8",
        "192.168.1.1",
        "br-lan",
        str(0x78563412),
        str(fields),
    ]
    encoded = subprocess.check_output(command, text=True).strip()
    try:
        packet = bytes.fromhex(encoded)
    except ValueError as error:
        fail(f"sender emitted invalid hex: {error}")

    if packet[:2] != b"\x00\x01":
        fail(f"MNDP header mismatch: {packet[:4].hex()}")
    if packet[:4] != b"\x00\x01\xaa\x39":
        fail(f"deployed CR6608 checksum vector changed: {packet[:4].hex()}")

    def checksum_sum(payload: bytes) -> int:
        if len(payload) % 2:
            payload += b"\x00"
        total = sum(struct.unpack(f"!{len(payload) // 2}H", payload))
        while total >> 16:
            total = (total & 0xFFFF) + (total >> 16)
        return total

    zeroed = packet[:2] + b"\x00\x00" + packet[4:]
    expected_checksum = (~checksum_sum(zeroed)) & 0xFFFF
    if packet[2:4] != struct.pack("!H", expected_checksum):
        fail(
            f"wire checksum {packet[2:4].hex()} != {expected_checksum:04x}"
        )
    if checksum_sum(packet) != 0xFFFF:
        fail("complete packet does not verify to one's-complement 0xffff")
    corrupted = bytearray(packet)
    corrupted[-1] ^= 0x01
    if checksum_sum(bytes(corrupted)) == 0xFFFF:
        fail("checksum failed to detect a one-bit payload corruption")

    odd_values = values.copy()
    odd_values[0] += "X"
    fields.write_text("\n".join(odd_values) + "\n", encoding="utf-8")
    odd_packet = bytes.fromhex(subprocess.check_output(command, text=True).strip())
    if len(odd_packet) % 2 != 1:
        fail("odd-length checksum fixture unexpectedly became even")
    if checksum_sum(odd_packet) != 0xFFFF:
        fail("odd-length packet checksum does not verify")
    fields.write_text("\n".join(values) + "\n", encoding="utf-8")
    position = 4
    tlvs: list[tuple[int, bytes]] = []
    while position < len(packet):
        if position + 4 > len(packet):
            fail("truncated TLV header")
        tlv_type, tlv_len = struct.unpack_from("!HH", packet, position)
        position += 4
        if position + tlv_len > len(packet):
            fail(f"truncated TLV {tlv_type}")
        tlvs.append((tlv_type, packet[position : position + tlv_len]))
        position += tlv_len

    expected = [
        (1, bytes.fromhex("d43538d4f3c8")),
        (5, values[0].encode()),
        (7, values[2].encode()),
        (8, values[1].encode()),
        (12, values[3].encode()),
        (10, bytes.fromhex("12345678")),
        (11, b"SmartAP"),
        (16, b"br-lan"),
        (17, bytes([192, 168, 1, 1])),
    ]
    if tlvs != expected:
        fail(f"TLV contract mismatch: {tlvs!r}")
    expected_length = 4 + sum(4 + len(value) for _, value in expected)
    if len(packet) != expected_length:
        fail(f"payload length {len(packet)} != {expected_length}")

    vlan_command = command.copy()
    vlan_command[4] = "br-lan.100"
    vlan_packet = bytes.fromhex(subprocess.check_output(vlan_command, text=True).strip())
    if b"br-lan.100" not in vlan_packet:
        fail("br-lan VLAN interface TLV was not preserved")

    rescue_command = command.copy()
    rescue_command[3] = "221.221.221.221"
    if subprocess.run(rescue_command, stdout=subprocess.DEVNULL).returncode == 0:
        fail("rescue-only IPv4 address was advertised as a general MNDP neighbor")

    fields_link = temp / "fields-link"
    fields_link.symlink_to(fields)
    link_command = command.copy()
    link_command[-1] = str(fields_link)
    if subprocess.run(link_command, stdout=subprocess.DEVNULL).returncode == 0:
        fail("symlink fields file was accepted")

    os.chmod(fields, 0o644)
    if subprocess.run(command, stdout=subprocess.DEVNULL).returncode == 0:
        fail("non-private fields file was accepted")
    os.chmod(fields, 0o600)

    sentinel = temp / "sentinel"
    sentinel.write_text("DO-NOT-TOUCH\n", encoding="ascii")
    status = temp / "status"
    status.symlink_to(sentinel)
    subprocess.run(
        [str(sender), "--status", str(status), str(fields)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sentinel.read_text(encoding="ascii") != "DO-NOT-TOUCH\n":
        fail("preplanted status symlink clobbered its target")
    status_info = status.lstat()
    if not stat.S_ISREG(status_info.st_mode) or stat.S_IMODE(status_info.st_mode) != 0o600:
        fail("status was not atomically replaced by a private regular file")

    hostile = temp / "hostile"
    hostile.mkdir(mode=0o777)
    os.chmod(hostile, 0o777)
    hostile_status = hostile / "status"
    subprocess.run(
        [str(sender), "--status", str(hostile_status), str(fields)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if hostile_status.exists() or hostile_status.is_symlink():
        fail("sender published status in an attacker-writable directory")

print("mndp_packet=pass")
