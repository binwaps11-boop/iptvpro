#!/usr/bin/env python3
"""Recreate locally signed APKs from verified CI bytes and public signing metadata.

The manifest contains no private key. Both input and output hashes are mandatory.
"""
import base64
import hashlib
import json
from pathlib import Path
import sys

manifest_path, input_dir, output_dir = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text())
expected = {"CardManager.apk", "CardManager-Admin.apk"}
assert {item["output"] for item in manifest["apks"]} == expected
output_dir.mkdir(parents=True, exist_ok=True)
for item in manifest["apks"]:
    assert item["input"] in {"CardManager-unsigned.apk", "CardManager-Admin-unsigned.apk"}
    original = (input_dir / item["input"]).read_bytes()
    assert hashlib.sha256(original).hexdigest() == item["input_sha256"], "Different build bytes"
    chunks = []
    for part in item["parts"]:
        if "copy" in part:
            offset, length = part["copy"]
            assert isinstance(offset, int) and isinstance(length, int)
            assert offset >= 0 and length > 0 and offset + length <= len(original)
            chunks.append(original[offset:offset + length])
        else:
            chunks.append(base64.b64decode(part["data"], validate=True))
    signed = b"".join(chunks)
    assert hashlib.sha256(signed).hexdigest() == item["output_sha256"], "Signature reconstruction mismatch"
    (output_dir / item["output"]).write_bytes(signed)
    print(item["output"], item["output_sha256"])
