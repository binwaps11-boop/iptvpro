#!/usr/bin/env python3
"""Generate the deterministic Smart AP browser and LuCI brand assets.

The renderer intentionally uses only the Python standard library so the same
assets can be reproduced in the isolated OpenWrt build VM.  PNGs are rendered
with sub-pixel sampling, while the ICO embeds real PNG frames for each declared
size instead of disguising one arbitrary PNG as an .ico file.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import math
import os
import pathlib
import struct
import sys
import zlib


ROOT = pathlib.Path(__file__).resolve().parents[1]
THEME = ROOT / "files/www/luci-static/argon"
ICON_DIR = THEME / "icon"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ASSET_VERSION = "smartap-v54"
MASTER_SIZE = 1024
ARC_START = -2.48
ARC_END = -0.66
ARC_START_COS = math.cos(ARC_START)
ARC_START_SIN = math.sin(ARC_START)
ARC_END_COS = math.cos(ARC_END)
ARC_END_SIN = math.sin(ARC_END)
PNG_SPECS = {
    "favicon-16x16.png": 16,
    "favicon-32x32.png": 32,
    "favicon-96x96.png": 96,
    "apple-icon-60x60.png": 60,
    "apple-icon-72x72.png": 72,
    "apple-icon-144x144.png": 144,
    "apple-icon-180x180.png": 180,
    "android-icon-192x192.png": 192,
    "android-icon-512x512.png": 512,
    "ms-icon-70x70.png": 70,
    "ms-icon-144x144.png": 144,
    "ms-icon-150x150.png": 150,
    "ms-icon-310x310.png": 310,
}
ICO_SIZES = [16, 32, 48, 64, 128, 256]
LOCK_PATH = ICON_DIR / "smart-ap-assets.json"


def blend(left: int, right: int, amount: float) -> int:
    return max(0, min(255, round(left + (right - left) * amount)))


def in_round_capped_arc(
    x: float,
    y: float,
    radius: float,
    width: float,
) -> bool:
    center_x, center_y = 0.5, 0.715
    dx, dy = x - center_x, y - center_y
    distance_squared = dx * dx + dy * dy
    inner = radius - width / 2
    outer = radius + width / 2
    # The two angles are symmetric about vertical. Avoiding atan2/hypot here
    # materially reduces deterministic asset-generation time.
    sector = dy < 0 and abs(dx) <= (-dy * 1.28)
    if sector and inner * inner <= distance_squared <= outer * outer:
        return True
    cap_radius = width / 2
    for cap_cos, cap_sin in (
        (ARC_START_COS, ARC_START_SIN),
        (ARC_END_COS, ARC_END_SIN),
    ):
        cap_x = center_x + radius * cap_cos
        cap_y = center_y + radius * cap_sin
        cap_dx, cap_dy = x - cap_x, y - cap_y
        if cap_dx * cap_dx + cap_dy * cap_dy <= cap_radius * cap_radius:
            return True
    return False


def logo_sample(x: float, y: float) -> tuple[int, int, int, int]:
    # Signed-distance rounded square with transparent outer corners.
    margin, radius = 0.045, 0.205
    half = 0.5 - margin
    qx = abs(x - 0.5) - (half - radius)
    qy = abs(y - 0.5) - (half - radius)
    if qx > 0 and qy > 0:
        inside = qx * qx + qy * qy <= radius * radius
    else:
        inside = max(qx, qy) <= radius
    if not inside:
        return (0, 0, 0, 0)

    # Deep blue to cyan, matching the Smart AP dashboard without depending on it.
    amount = max(0.0, min(1.0, 0.58 * x + 0.42 * y))
    red = blend(37, 6, amount)
    green = blend(99, 182, amount)
    blue = blend(235, 212, amount)
    shade = 1.0 - 0.17 * max(0.0, y - 0.38)
    red, green, blue = (round(red * shade), round(green * shade), round(blue * shade))

    signal = (
        in_round_capped_arc(x, y, 0.300, 0.058)
        or in_round_capped_arc(x, y, 0.195, 0.058)
        or (x - 0.5) ** 2 + (y - 0.715) ** 2 <= 0.047**2
    )
    if signal:
        return (244, 251, 255, 255)
    return (red, green, blue, 255)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = binascii.crc32(kind)
    checksum = binascii.crc32(payload, checksum) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def render_master() -> bytearray:
    pixels = bytearray(MASTER_SIZE * MASTER_SIZE * 4)
    offset = 0
    for pixel_y in range(MASTER_SIZE):
        y = (pixel_y + 0.5) / MASTER_SIZE
        for pixel_x in range(MASTER_SIZE):
            x = (pixel_x + 0.5) / MASTER_SIZE
            red, green, blue, alpha = logo_sample(x, y)
            pixels[offset] = red
            pixels[offset + 1] = green
            pixels[offset + 2] = blue
            pixels[offset + 3] = alpha
            offset += 4
    return pixels


def resample_square(master: bytearray, size: int) -> bytearray:
    # Four regularly-spaced samples per output pixel provide stable edge
    # antialiasing while retaining a single expensive vector rasterization.
    pixels = bytearray(size * size * 4)
    output_offset = 0
    for pixel_y in range(size):
        source_y0 = min(MASTER_SIZE - 1, int((pixel_y + 0.25) * MASTER_SIZE / size))
        source_y1 = min(MASTER_SIZE - 1, int((pixel_y + 0.75) * MASTER_SIZE / size))
        for pixel_x in range(size):
            source_x0 = min(MASTER_SIZE - 1, int((pixel_x + 0.25) * MASTER_SIZE / size))
            source_x1 = min(MASTER_SIZE - 1, int((pixel_x + 0.75) * MASTER_SIZE / size))
            offsets = (
                (source_y0 * MASTER_SIZE + source_x0) * 4,
                (source_y0 * MASTER_SIZE + source_x1) * 4,
                (source_y1 * MASTER_SIZE + source_x0) * 4,
                (source_y1 * MASTER_SIZE + source_x1) * 4,
            )
            first, second, third, fourth = offsets
            pixels[output_offset] = (
                master[first] + master[second] + master[third] + master[fourth] + 2
            ) // 4
            pixels[output_offset + 1] = (
                master[first + 1]
                + master[second + 1]
                + master[third + 1]
                + master[fourth + 1]
                + 2
            ) // 4
            pixels[output_offset + 2] = (
                master[first + 2]
                + master[second + 2]
                + master[third + 2]
                + master[fourth + 2]
                + 2
            ) // 4
            pixels[output_offset + 3] = (
                master[first + 3]
                + master[second + 3]
                + master[third + 3]
                + master[fourth + 3]
                + 2
            ) // 4
            output_offset += 4
    return pixels


def encode_png(width: int, height: int, pixels: bytearray) -> bytes:
    row_bytes = width * 4
    raw = bytearray()
    for pixel_y in range(height):
        raw.append(0)  # PNG filter type: None
        start = pixel_y * row_bytes
        raw.extend(pixels[start : start + row_bytes])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )


def make_ico(frames: list[tuple[int, bytes]]) -> bytes:
    header = struct.pack("<HHH", 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    directory = bytearray()
    payload = bytearray()
    for size, image in frames:
        dimension = 0 if size == 256 else size
        directory.extend(
            struct.pack(
                "<BBBBHHII",
                dimension,
                dimension,
                0,
                0,
                1,
                32,
                len(image),
                offset,
            )
        )
        payload.extend(image)
        offset += len(image)
    return header + bytes(directory) + bytes(payload)


def svg_source() -> bytes:
    return b"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-labelledby="smart-ap-title smart-ap-description">
  <title id="smart-ap-title">Smart AP</title>
  <desc id="smart-ap-description">Smart AP wireless access point mark</desc>
  <defs>
    <linearGradient id="smart-ap-gradient" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2563eb"/>
      <stop offset="1" stop-color="#06b6d4"/>
    </linearGradient>
  </defs>
  <rect x="24" y="24" width="464" height="464" rx="105" fill="url(#smart-ap-gradient)"/>
  <rect x="35" y="35" width="442" height="442" rx="94" fill="none" stroke="#94e0ff" stroke-opacity=".22" stroke-width="10"/>
  <g fill="none" stroke="#f4fbff" stroke-width="30" stroke-linecap="round">
    <path d="M111 238c75-88 215-88 290 0"/>
    <path d="M170 301c45-51 127-51 172 0"/>
  </g>
  <circle cx="256" cy="366" r="24" fill="#f4fbff"/>
</svg>
"""


def manifest_source() -> bytes:
    manifest = {
        "name": "Smart AP",
        "short_name": "Smart AP",
        "description": "Local Smart AP router management",
        "start_url": "/",
        "scope": "/",
        "display": "standalone",
        "background_color": "#05060b",
        "theme_color": "#2563eb",
        "icons": [
            {
                "src": f"/luci-static/argon/icon/android-icon-192x192.png?v={ASSET_VERSION}",
                "sizes": "192x192",
                "type": "image/png",
                "purpose": "any",
            },
            {
                "src": f"/luci-static/argon/icon/android-icon-512x512.png?v={ASSET_VERSION}",
                "sizes": "512x512",
                "type": "image/png",
                "purpose": "any",
            },
        ],
    }
    return (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def browserconfig_source() -> bytes:
    return f"""<?xml version="1.0" encoding="utf-8"?>
<browserconfig>
  <msapplication>
    <tile>
      <square70x70logo src="/luci-static/argon/icon/ms-icon-70x70.png?v={ASSET_VERSION}"/>
      <square150x150logo src="/luci-static/argon/icon/ms-icon-150x150.png?v={ASSET_VERSION}"/>
      <square310x310logo src="/luci-static/argon/icon/ms-icon-310x310.png?v={ASSET_VERSION}"/>
      <TileColor>#2563eb</TileColor>
    </tile>
  </msapplication>
</browserconfig>
""".encode("utf-8")


def expected_outputs() -> dict[pathlib.Path, bytes]:
    master = render_master()
    cache: dict[int, bytes] = {}

    def square(size: int) -> bytes:
        if size not in cache:
            cache[size] = encode_png(size, size, resample_square(master, size))
        return cache[size]

    outputs = {ICON_DIR / name: square(size) for name, size in PNG_SPECS.items()}
    outputs[THEME / "favicon.ico"] = make_ico(
        [(size, square(size)) for size in ICO_SIZES]
    )
    outputs[ICON_DIR / "smart-ap.svg"] = svg_source()
    outputs[ICON_DIR / "manifest.json"] = manifest_source()
    outputs[ICON_DIR / "browserconfig.xml"] = browserconfig_source()
    return outputs


def lock_source(outputs: dict[pathlib.Path, bytes]) -> bytes:
    lock = {
        "schema": "smart-ap-brand-assets-v1",
        "generator_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
        "assets": {
            path.relative_to(ROOT).as_posix(): {
                "sha256": hashlib.sha256(payload).hexdigest(),
                "size": len(payload),
            }
            for path, payload in sorted(outputs.items(), key=lambda item: item[0].as_posix())
        },
    }
    return (json.dumps(lock, indent=2, sort_keys=True) + "\n").encode("utf-8")


def check_lock() -> list[str]:
    problems: list[str] = []
    try:
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read asset lock: {error}"]
    if lock.get("schema") != "smart-ap-brand-assets-v1":
        problems.append("asset lock schema is invalid")
    generator_hash = hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
    if lock.get("generator_sha256") != generator_hash:
        problems.append("generator changed after the assets were rendered")
    assets = lock.get("assets")
    if not isinstance(assets, dict):
        return problems + ["asset lock has no assets object"]
    expected_paths = {
        (ICON_DIR / name).relative_to(ROOT).as_posix() for name in PNG_SPECS
    } | {
        (THEME / "favicon.ico").relative_to(ROOT).as_posix(),
        (ICON_DIR / "smart-ap.svg").relative_to(ROOT).as_posix(),
        (ICON_DIR / "manifest.json").relative_to(ROOT).as_posix(),
        (ICON_DIR / "browserconfig.xml").relative_to(ROOT).as_posix(),
    }
    if set(assets) != expected_paths:
        problems.append("asset lock path set differs from the generator contract")
    for relative in sorted(expected_paths):
        record = assets.get(relative)
        path = ROOT / relative
        if not isinstance(record, dict) or not path.is_file():
            problems.append(f"missing generated asset: {relative}")
            continue
        payload = path.read_bytes()
        if record.get("size") != len(payload):
            problems.append(f"generated asset size changed: {relative}")
        if record.get("sha256") != hashlib.sha256(payload).hexdigest():
            problems.append(f"generated asset hash changed: {relative}")
    return problems


def atomic_write(path: pathlib.Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    try:
        temporary.write_bytes(payload)
        temporary.chmod(0o644)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify that every generated file is byte-for-byte current",
    )
    args = parser.parse_args()
    if args.check:
        problems = check_lock()
        if problems:
            for problem in problems:
                print(f"smart_ap_brand_stale={problem}", file=sys.stderr)
            return 1
        print(f"smart_ap_brand_check=pass files={len(PNG_SPECS) + 4}")
        return 0

    outputs = expected_outputs()
    outputs[LOCK_PATH] = lock_source(outputs)
    for path, payload in outputs.items():
        atomic_write(path, payload)
    print(f"smart_ap_brand_generate=pass files={len(outputs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
