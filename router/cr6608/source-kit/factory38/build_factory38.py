#!/usr/bin/env python3
"""Build an offline CR6608 MT7915 Factory image with 38 dBm target fields.

This utility is deliberately device-specific.  It refuses any input other than
the known-good 512 KiB Factory backup and changes only the 36 mt7915 per-chain
target-power bytes documented in the generated manifest.

It does not write an MTD device and must never be copied into a router-side
automatic flashing path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import zlib


FACTORY_SIZE = 0x80000
ERASEBLOCK_SIZE = 0x20000
EEPROM_SIZE = 0xE00
KNOWN_FACTORY_SHA256 = "aca3a3b012d96972466e7492e150bb2e00ba24f9f43201912db0223a32c98439"

WIFI_CONF = 0x190
RATE_DELTA_2G = 0x252
RATE_DELTA_5G = 0x29D
TX0_POWER_2G = 0x2FC
TX0_POWER_5G = 0x34B

EXPECTED_CHIP_ID = 0x7915
EXPECTED_WIFI_CONF7 = 0x15
EXPECTED_RATE_DELTA_2G = 0xC6
EXPECTED_RATE_DELTA_5G = 0xC4
EXPECTED_2G_RAW = 0x28
EXPECTED_5G_RAW = 0x26
FACTORY38_2G_RAW = 0x40
FACTORY38_5G_RAW = 0x42
FACTORY38_CHAIN_COUNT = 4
FACTORY38_2G_CHANNEL_GROUP_COUNT = 1
FACTORY38_5G_CHANNEL_GROUP_COUNT = 8

MANIFEST_SCHEMA = "cr6608-factory38-offline-artifact"
MANIFEST_SCHEMA_VERSION = 1
PRIVATE_FILE_MODE = 0o600

MAC_CELL_OFFSETS = (0x3FFF4, 0x3FFFA)
MAC_CELL_SIZE = 6


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def crc32(data: bytes) -> str:
    return f"{zlib.crc32(data) & 0xFFFFFFFF:08x}"


def target_changes() -> list[dict[str, int | str]]:
    changes: list[dict[str, int | str]] = []
    for chain in range(FACTORY38_CHAIN_COUNT):
        changes.append(
            {
                "band": "2g",
                "chain": chain,
                "group": 0,
                "offset": TX0_POWER_2G + chain * 3,
                "expected_old": EXPECTED_2G_RAW,
                "new": FACTORY38_2G_RAW,
            }
        )
    for chain in range(FACTORY38_CHAIN_COUNT):
        for group in range(FACTORY38_5G_CHANNEL_GROUP_COUNT):
            changes.append(
                {
                    "band": "5g",
                    "chain": chain,
                    "group": group,
                    "offset": TX0_POWER_5G + chain * 12 + group,
                    "expected_old": EXPECTED_5G_RAW,
                    "new": FACTORY38_5G_RAW,
                }
            )
    return changes


def channel_group_coverage(
    changes: list[dict[str, int | str]],
) -> dict[str, object]:
    expected_2g = {
        (chain, group)
        for chain in range(FACTORY38_CHAIN_COUNT)
        for group in range(FACTORY38_2G_CHANNEL_GROUP_COUNT)
    }
    expected_5g = {
        (chain, group)
        for chain in range(FACTORY38_CHAIN_COUNT)
        for group in range(FACTORY38_5G_CHANNEL_GROUP_COUNT)
    }
    actual_2g = {
        (int(change["chain"]), int(change["group"]))
        for change in changes
        if change["band"] == "2g"
    }
    actual_5g = {
        (int(change["chain"]), int(change["group"]))
        for change in changes
        if change["band"] == "5g"
    }
    exact_2g = (
        len(actual_2g) == len(expected_2g)
        and sum(change["band"] == "2g" for change in changes) == len(expected_2g)
        and actual_2g == expected_2g
        and all(
            int(change["new"]) == FACTORY38_2G_RAW
            for change in changes
            if change["band"] == "2g"
        )
    )
    exact_5g = (
        len(actual_5g) == len(expected_5g)
        and sum(change["band"] == "5g" for change in changes) == len(expected_5g)
        and actual_5g == expected_5g
        and all(
            int(change["new"]) == FACTORY38_5G_RAW
            for change in changes
            if change["band"] == "5g"
        )
    )
    require(exact_2g, "2.4 GHz target changes do not cover every chain/group exactly")
    require(exact_5g, "5 GHz target changes do not cover every chain/group exactly")

    return {
        "chain_count": FACTORY38_CHAIN_COUNT,
        "all_supported_channels_targeted": exact_2g and exact_5g,
        "2g": {
            "group_count": FACTORY38_2G_CHANNEL_GROUP_COUNT,
            "groups": list(range(FACTORY38_2G_CHANNEL_GROUP_COUNT)),
            "all_supported_channels_targeted": exact_2g,
        },
        "5g": {
            "group_count": FACTORY38_5G_CHANNEL_GROUP_COUNT,
            "groups": list(range(FACTORY38_5G_CHANNEL_GROUP_COUNT)),
            "all_supported_channels_targeted": exact_5g,
        },
    }


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"REFUSED: {message}")


def _validate_raw_path(path: Path, label: str, *, source: bool) -> None:
    """Reject links and non-regular existing objects before resolving paths."""

    require(not path.is_symlink(), f"{label} path must not be a symbolic link")
    if source:
        require(path.exists(), f"{label} does not exist")
        try:
            mode = path.stat(follow_symlinks=False).st_mode
        except OSError as error:
            raise SystemExit(f"REFUSED: cannot stat {label}: {error}") from error
        require(stat.S_ISREG(mode), f"{label} must be a regular file")
    elif path.exists():
        try:
            mode = path.stat(follow_symlinks=False).st_mode
        except OSError as error:
            raise SystemExit(f"REFUSED: cannot stat existing {label}: {error}") from error
        require(stat.S_ISREG(mode), f"existing {label} must be a regular file")


def _resolve_and_validate_paths(
    source: Path, output: Path, block0_path: Path, manifest_path: Path
) -> tuple[Path, Path, Path, Path]:
    raw_paths = {
        "source": Path(source),
        "output": Path(output),
        "block0": Path(block0_path),
        "manifest": Path(manifest_path),
    }
    for label, path in raw_paths.items():
        _validate_raw_path(path, label, source=label == "source")

    resolved = {label: path.resolve() for label, path in raw_paths.items()}
    labels = tuple(resolved)
    for index, left_label in enumerate(labels):
        for right_label in labels[index + 1 :]:
            require(
                resolved[left_label] != resolved[right_label],
                f"{left_label} and {right_label} paths must differ after resolve",
            )

            left_raw = raw_paths[left_label]
            right_raw = raw_paths[right_label]
            if left_raw.exists() and right_raw.exists():
                try:
                    same_file = os.path.samefile(left_raw, right_raw)
                except OSError as error:
                    raise SystemExit(
                        f"REFUSED: cannot compare {left_label} and {right_label}: {error}"
                    ) from error
                require(
                    not same_file,
                    f"{left_label} and {right_label} must not alias the same file",
                )

    return (
        resolved["source"],
        resolved["output"],
        resolved["block0"],
        resolved["manifest"],
    )


def _read_regular_source(path: Path) -> bytes:
    """Open the source once and verify that the opened object is regular."""

    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise SystemExit(f"REFUSED: cannot open source: {error}") from error

    try:
        opened_stat = os.fstat(descriptor)
        require(stat.S_ISREG(opened_stat.st_mode), "source must be a regular file")
        with os.fdopen(descriptor, "rb", closefd=True) as source_file:
            descriptor = -1
            payload = source_file.read()
    finally:
        if descriptor >= 0:
            os.close(descriptor)

    require(not path.is_symlink(), "source became a symbolic link while reading")
    return payload


def _fsync_directory(directory: Path) -> None:
    """Persist the rename where directory fsync is supported."""

    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    try:
        descriptor = os.open(directory, flags)
    except OSError:
        return
    try:
        os.fsync(descriptor)
    except OSError:
        # Windows and some filesystems do not permit fsync on directories.
        pass
    finally:
        os.close(descriptor)


def _atomic_write(path: Path, payload: bytes, label: str) -> None:
    """Write a private file atomically using a temporary sibling."""

    path.parent.mkdir(parents=True, exist_ok=True)
    _validate_raw_path(path, label, source=False)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, PRIVATE_FILE_MODE)
        with os.fdopen(descriptor, "wb", closefd=True) as temporary_file:
            descriptor = -1
            temporary_file.write(payload)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_path, PRIVATE_FILE_MODE, follow_symlinks=False)

        # A pre-existing link is always refused, including one introduced
        # after the initial argument validation.
        _validate_raw_path(path, label, source=False)
        os.replace(temporary_path, path)
        os.chmod(path, PRIVATE_FILE_MODE, follow_symlinks=False)
        _fsync_directory(path.parent)
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
        raise


def build_factory38(
    source: Path, output: Path, block0_path: Path, manifest_path: Path
) -> dict[str, object]:
    source, output, block0_path, manifest_path = _resolve_and_validate_paths(
        source, output, block0_path, manifest_path
    )

    original = _read_regular_source(source)
    require(len(original) == FACTORY_SIZE, f"Factory size is {len(original)}, expected {FACTORY_SIZE}")
    require(sha256(original) == KNOWN_FACTORY_SHA256, "input SHA-256 is not the preserved CR6608 Factory backup")
    require(int.from_bytes(original[0:2], "little") == EXPECTED_CHIP_ID, "unexpected MT7915 chip ID")
    require(original[WIFI_CONF + 7] == EXPECTED_WIFI_CONF7, "unexpected TSSI/WIFI_CONF byte")
    require(original[RATE_DELTA_2G] == EXPECTED_RATE_DELTA_2G, "unexpected 2.4 GHz rate delta")
    require(original[RATE_DELTA_5G] == EXPECTED_RATE_DELTA_5G, "unexpected 5 GHz rate delta")

    changes = target_changes()
    coverage = channel_group_coverage(changes)
    modified = bytearray(original)
    for change in changes:
        offset = int(change["offset"])
        expected_old = int(change["expected_old"])
        require(modified[offset] == expected_old, f"unexpected byte 0x{modified[offset]:02x} at 0x{offset:05x}")
        modified[offset] = int(change["new"])

    changed_offsets = [index for index, (old, new) in enumerate(zip(original, modified)) if old != new]
    expected_offsets = [int(change["offset"]) for change in changes]
    require(changed_offsets == expected_offsets, "the generated binary contains an unexpected byte difference")
    require(all(offset < EEPROM_SIZE for offset in changed_offsets), "a changed byte is outside the mt7915 EEPROM cell")
    require(
        all(offset < ERASEBLOCK_SIZE for offset in changed_offsets),
        "a changed byte is outside Factory eraseblock 0",
    )
    for offset in MAC_CELL_OFFSETS:
        require(
            original[offset : offset + MAC_CELL_SIZE] == modified[offset : offset + MAC_CELL_SIZE],
            f"MAC cell at 0x{offset:05x} changed",
        )

    output_data = bytes(modified)
    block0_data = output_data[:ERASEBLOCK_SIZE]
    formatted_offsets = [f"0x{offset:05x}" for offset in changed_offsets]
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "warning": "EXPERIMENTAL OFFLINE ARTIFACT - DO NOT FLASH WITHOUT VERIFIED SERIAL/NAND RECOVERY AND RF TEST EQUIPMENT",
        "source": source.name,
        "source_size": len(original),
        "source_sha256": sha256(original),
        "source_crc32": crc32(original),
        "output": output.name,
        "output_size": len(output_data),
        "output_sha256": sha256(output_data),
        "output_crc32": crc32(output_data),
        "manifest": manifest_path.name,
        "eraseblock0": {
            "offset": 0,
            "size": ERASEBLOCK_SIZE,
            "source_sha256": sha256(original[:ERASEBLOCK_SIZE]),
            "source_crc32": crc32(original[:ERASEBLOCK_SIZE]),
            "output": block0_path.name,
            "output_sha256": sha256(block0_data),
            "output_crc32": crc32(block0_data),
            "contains_all_changed_bytes": True,
            "recommended_mtd_write_length": ERASEBLOCK_SIZE,
        },
        "changed_byte_count": len(changed_offsets),
        "changed_offsets": formatted_offsets,
        "diff": {
            "exact_declared_offsets": changed_offsets == expected_offsets,
            "changed_byte_count": len(changed_offsets),
            "changed_offsets": formatted_offsets,
        },
        "preserved": {
            "bytes_outside_declared_offsets": True,
            "mt7915_eeprom_tail_after_0xe00": True,
            "mac_cells": {
                f"0x{offset:05x}": original[offset : offset + MAC_CELL_SIZE].hex(":")
                for offset in MAC_CELL_OFFSETS
            },
            "wifi_conf7": f"0x{original[WIFI_CONF + 7]:02x}",
            "rate_delta_2g": f"0x{original[RATE_DELTA_2G]:02x}",
            "rate_delta_5g": f"0x{original[RATE_DELTA_5G]:02x}",
        },
        "target_math_half_dbm": {
            "2g": {
                "raw_target": FACTORY38_2G_RAW,
                "rate_delta": 6,
                "two_chain_path_delta": 6,
                "calculated_driver_bound": 76,
                "calculated_driver_bound_dbm": 38.0,
            },
            "5g": {
                "raw_target": FACTORY38_5G_RAW,
                "rate_delta": 4,
                "two_chain_path_delta": 6,
                "calculated_driver_bound": 76,
                "calculated_driver_bound_dbm": 38.0,
            },
        },
        "channel_group_coverage": coverage,
        "changes": [
            {
                **change,
                "offset": f"0x{int(change['offset']):05x}",
                "expected_old": f"0x{int(change['expected_old']):02x}",
                "new": f"0x{int(change['new']):02x}",
            }
            for change in changes
        ],
        "limitations": [
            "The values are EEPROM calibration/request bounds, not a calibrated RF power measurement.",
            "cfg80211/regulatory, SAR, per-rate, thermal, MCU firmware and physical PA limits still apply.",
            "Previous exact-38 MCU SKU readback did not confirm firmware acceptance.",
        ],
    }
    manifest_data = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")

    _atomic_write(output, output_data, "output")
    _atomic_write(block0_path, block0_data, "block0")
    _atomic_write(manifest_path, manifest_data, "manifest")

    require(output.read_bytes() == output_data, "output readback differs from generated bytes")
    require(
        block0_path.read_bytes() == block0_data,
        "eraseblock-0 output readback differs from generated bytes",
    )
    require(
        manifest_path.read_bytes() == manifest_data,
        "manifest readback differs from generated bytes",
    )

    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="known-good 512 KiB Factory backup")
    parser.add_argument("output", type=Path, help="offline experimental Factory output")
    parser.add_argument(
        "--manifest",
        type=Path,
        help="JSON manifest path (default: OUTPUT.manifest.json)",
    )
    parser.add_argument(
        "--block0",
        type=Path,
        help="first-eraseblock output (default: OUTPUT without .bin + .block0.bin)",
    )
    args = parser.parse_args()

    output = args.output
    manifest_path = args.manifest or output.with_name(output.name + ".manifest.json")
    block0_path = args.block0 or output.with_name(
        (output.name[:-4] if output.name.endswith(".bin") else output.name)
        + ".block0.bin"
    )
    manifest = build_factory38(args.source, output, block0_path, manifest_path)

    print(f"source_sha256={manifest['source_sha256']}")
    print(f"source_crc32={manifest['source_crc32']}")
    print(f"output_sha256={manifest['output_sha256']}")
    print(f"output_crc32={manifest['output_crc32']}")
    print(f"block0_sha256={manifest['eraseblock0']['output_sha256']}")
    print(f"block0_crc32={manifest['eraseblock0']['output_crc32']}")
    print(f"changed_byte_count={manifest['changed_byte_count']}")
    print(f"output={Path(output).resolve()}")
    print(f"block0={Path(block0_path).resolve()}")
    print(f"manifest={Path(manifest_path).resolve()}")


if __name__ == "__main__":
    main()
