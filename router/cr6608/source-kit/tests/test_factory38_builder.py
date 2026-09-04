#!/usr/bin/env python3
"""Regression tests for the offline CR6608 Factory-38 artifact builder."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock


sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent
BUILDER_PATH = SCRIPT_DIR.parent / "factory38" / "build_factory38.py"
SPEC = importlib.util.spec_from_file_location("cr6608_build_factory38", BUILDER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {BUILDER_PATH}")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


def valid_factory_bytes() -> bytes:
    payload = bytearray(
        ((index * 37) + 11) & 0xFF for index in range(BUILDER.FACTORY_SIZE)
    )
    payload[0:2] = BUILDER.EXPECTED_CHIP_ID.to_bytes(2, "little")
    payload[BUILDER.WIFI_CONF + 7] = BUILDER.EXPECTED_WIFI_CONF7
    payload[BUILDER.RATE_DELTA_2G] = BUILDER.EXPECTED_RATE_DELTA_2G
    payload[BUILDER.RATE_DELTA_5G] = BUILDER.EXPECTED_RATE_DELTA_5G
    for change in BUILDER.target_changes():
        payload[int(change["offset"])] = int(change["expected_old"])
    return bytes(payload)


class Factory38BuilderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="cr6608-factory38-builder-test."
        )
        self.root = Path(self.temporary_directory.name)
        self.original = valid_factory_bytes()
        self.original_hash = BUILDER.sha256(self.original)
        self.source = self.root / "factory-original.bin"
        self.source.write_bytes(self.original)
        self.output = self.root / "release" / "factory-38.bin"
        self.block0 = self.root / "release" / "factory-38.block0.bin"
        self.manifest = self.root / "release" / "factory-38.manifest.json"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def build(
        self,
        *,
        source: Path | None = None,
        output: Path | None = None,
        block0: Path | None = None,
        manifest: Path | None = None,
        expected_hash: str | None = None,
    ) -> dict[str, object]:
        with mock.patch.object(
            BUILDER,
            "KNOWN_FACTORY_SHA256",
            expected_hash or self.original_hash,
        ):
            return BUILDER.build_factory38(
                source or self.source,
                output or self.output,
                block0 or self.block0,
                manifest or self.manifest,
            )

    def assert_private_regular_file(self, path: Path) -> None:
        self.assertTrue(path.is_file())
        self.assertFalse(path.is_symlink())
        if os.name == "posix":
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_deterministic_exact_diff_crc_manifest_and_preservation(self) -> None:
        first_manifest = self.build()
        first_output = self.output.read_bytes()
        first_block0 = self.block0.read_bytes()
        first_manifest_bytes = self.manifest.read_bytes()

        second_manifest = self.build()
        self.assertEqual(self.output.read_bytes(), first_output)
        self.assertEqual(self.block0.read_bytes(), first_block0)
        self.assertEqual(self.manifest.read_bytes(), first_manifest_bytes)
        self.assertEqual(second_manifest, first_manifest)

        expected_offsets = [
            int(change["offset"]) for change in BUILDER.target_changes()
        ]
        actual_offsets = [
            offset
            for offset, (old, new) in enumerate(zip(self.original, first_output))
            if old != new
        ]
        expected_offset_set = set(expected_offsets)
        self.assertEqual(len(actual_offsets), 36)
        self.assertEqual(actual_offsets, expected_offsets)
        for offset in range(len(self.original)):
            if offset not in expected_offset_set:
                self.assertEqual(first_output[offset], self.original[offset])
        self.assertEqual(first_block0, first_output[: BUILDER.ERASEBLOCK_SIZE])
        for offset in BUILDER.MAC_CELL_OFFSETS:
            self.assertEqual(
                first_output[offset : offset + BUILDER.MAC_CELL_SIZE],
                self.original[offset : offset + BUILDER.MAC_CELL_SIZE],
            )

        manifest = json.loads(first_manifest_bytes)
        formatted_offsets = [f"0x{offset:05x}" for offset in expected_offsets]
        self.assertEqual(manifest["schema"], BUILDER.MANIFEST_SCHEMA)
        self.assertEqual(
            manifest["schema_version"], BUILDER.MANIFEST_SCHEMA_VERSION
        )
        self.assertEqual(manifest["changed_byte_count"], 36)
        self.assertEqual(manifest["changed_offsets"], formatted_offsets)
        self.assertEqual(manifest["diff"]["changed_byte_count"], 36)
        self.assertEqual(manifest["diff"]["changed_offsets"], formatted_offsets)
        self.assertIs(manifest["diff"]["exact_declared_offsets"], True)
        self.assertEqual(manifest["source_sha256"], BUILDER.sha256(self.original))
        self.assertEqual(manifest["source_crc32"], BUILDER.crc32(self.original))
        self.assertEqual(manifest["output_sha256"], BUILDER.sha256(first_output))
        self.assertEqual(manifest["output_crc32"], BUILDER.crc32(first_output))
        self.assertEqual(
            manifest["eraseblock0"]["source_crc32"],
            BUILDER.crc32(self.original[: BUILDER.ERASEBLOCK_SIZE]),
        )
        self.assertEqual(
            manifest["eraseblock0"]["output_crc32"],
            BUILDER.crc32(first_block0),
        )
        self.assertEqual(manifest["source"], self.source.name)
        self.assertEqual(manifest["output"], self.output.name)
        self.assertEqual(manifest["manifest"], self.manifest.name)
        self.assertEqual(manifest["eraseblock0"]["output"], self.block0.name)
        self.assertNotIn(str(self.root.resolve()), first_manifest_bytes.decode())

        for path in (self.output, self.block0, self.manifest):
            self.assert_private_regular_file(path)

    def test_all_four_resolved_paths_must_be_pairwise_distinct(self) -> None:
        base_paths = {
            "source": self.source,
            "output": self.root / "distinct-output.bin",
            "block0": self.root / "distinct-block0.bin",
            "manifest": self.root / "distinct-manifest.json",
        }
        labels = tuple(base_paths)
        for index, left in enumerate(labels):
            for right in labels[index + 1 :]:
                with self.subTest(left=left, right=right):
                    paths = dict(base_paths)
                    paths[right] = paths[left]
                    with self.assertRaisesRegex(SystemExit, "paths must differ"):
                        self.build(**paths)

        alias_parent = self.root / "alias-parent"
        alias_parent.mkdir()
        lexical_alias = alias_parent / ".." / self.source.name
        with self.assertRaisesRegex(SystemExit, "paths must differ after resolve"):
            self.build(output=lexical_alias)

    def test_existing_hardlink_alias_is_rejected(self) -> None:
        hardlink = self.root / "source-hardlink.bin"
        try:
            os.link(self.source, hardlink)
        except OSError as error:
            self.skipTest(f"hard links are unavailable: {error}")
        with self.assertRaisesRegex(SystemExit, "must not alias the same file"):
            self.build(output=hardlink)

    def test_source_symlink_is_rejected(self) -> None:
        source_link = self.root / "source-link.bin"
        try:
            source_link.symlink_to(self.source)
        except OSError as error:
            # Windows commonly denies symlink creation without Developer Mode.
            # Keep the guard covered there by presenting an existing path whose
            # lstat classification is mocked as a link.
            source_link.write_bytes(b"simulated symlink")
            real_is_symlink = Path.is_symlink

            def simulated_is_symlink(path: Path) -> bool:
                return path == source_link or real_is_symlink(path)

            with mock.patch.object(Path, "is_symlink", simulated_is_symlink):
                with self.assertRaisesRegex(
                    SystemExit, "source path must not be a symbolic link"
                ):
                    self.build(source=source_link)
            self.assertIsInstance(error, OSError)
        else:
            with self.assertRaisesRegex(
                SystemExit, "source path must not be a symbolic link"
            ):
                self.build(source=source_link)

    def test_each_existing_target_symlink_is_rejected(self) -> None:
        sentinel = self.root / "sentinel.bin"
        sentinel.write_bytes(b"do not replace")
        targets = {
            "output": self.output,
            "block0": self.block0,
            "manifest": self.manifest,
        }
        for label, link in targets.items():
            with self.subTest(label=label):
                link.parent.mkdir(parents=True, exist_ok=True)
                try:
                    link.symlink_to(sentinel)
                except OSError as error:
                    link.write_bytes(b"simulated symlink")
                    real_is_symlink = Path.is_symlink

                    def simulated_is_symlink(path: Path) -> bool:
                        return path == link or real_is_symlink(path)

                    with mock.patch.object(
                        Path, "is_symlink", simulated_is_symlink
                    ):
                        with self.assertRaisesRegex(
                            SystemExit, f"{label} path must not be a symbolic link"
                        ):
                            self.build(**{label: link})
                    self.assertIsInstance(error, OSError)
                else:
                    with self.assertRaisesRegex(
                        SystemExit, f"{label} path must not be a symbolic link"
                    ):
                        self.build(**{label: link})
                self.assertEqual(sentinel.read_bytes(), b"do not replace")
                link.unlink(missing_ok=True)

    def test_wrong_source_hash_is_rejected_without_outputs(self) -> None:
        corrupt = bytearray(self.original)
        corrupt[0x1000] ^= 0x01
        self.source.write_bytes(corrupt)
        with self.assertRaisesRegex(SystemExit, "input SHA-256"):
            self.build(expected_hash=self.original_hash)
        self.assertFalse(self.output.exists())
        self.assertFalse(self.block0.exists())
        self.assertFalse(self.manifest.exists())

    def test_non_regular_source_is_rejected(self) -> None:
        directory_source = self.root / "source-directory"
        directory_source.mkdir()
        with self.assertRaisesRegex(SystemExit, "source must be a regular file"):
            self.build(source=directory_source)

    def test_atomic_writes_use_temporary_siblings_and_replace(self) -> None:
        real_replace = os.replace
        replacements: list[tuple[Path, Path]] = []

        def observed_replace(source: str | bytes, destination: str | bytes) -> None:
            source_path = Path(source)
            destination_path = Path(destination)
            replacements.append((source_path, destination_path))
            self.assertEqual(source_path.parent, destination_path.parent)
            self.assertTrue(source_path.name.startswith(f".{destination_path.name}."))
            self.assertTrue(source_path.name.endswith(".tmp"))
            real_replace(source, destination)

        with mock.patch.object(BUILDER.os, "replace", side_effect=observed_replace):
            self.build()

        self.assertEqual(
            [destination for _, destination in replacements],
            [
                self.output.resolve(),
                self.block0.resolve(),
                self.manifest.resolve(),
            ],
        )
        for temporary_path, _ in replacements:
            self.assertFalse(temporary_path.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
