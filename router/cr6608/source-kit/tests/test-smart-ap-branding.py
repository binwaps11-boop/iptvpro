#!/usr/bin/env python3
"""Contract tests for the Smart AP browser and LuCI identity."""

from __future__ import annotations

import json
import pathlib
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parents[1]
FILES = ROOT / "files"
WEB = FILES / "www"
THEME = WEB / "luci-static/argon"
ICONS = THEME / "icon"
TEMPLATES = FILES / "usr/share/ucode/luci/template/themes/argon"
GENERATOR = ROOT / "tools/generate-smart-ap-brand.py"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

PNG_SPECS = {
    "favicon-16x16.png": (16, 16),
    "favicon-32x32.png": (32, 32),
    "favicon-96x96.png": (96, 96),
    "apple-icon-60x60.png": (60, 60),
    "apple-icon-72x72.png": (72, 72),
    "apple-icon-144x144.png": (144, 144),
    "apple-icon-180x180.png": (180, 180),
    "android-icon-192x192.png": (192, 192),
    "android-icon-512x512.png": (512, 512),
    "ms-icon-70x70.png": (70, 70),
    "ms-icon-144x144.png": (144, 144),
    "ms-icon-150x150.png": (150, 150),
    "ms-icon-310x310.png": (310, 310),
}


def fail(message: str) -> None:
    print(f"smart_ap_branding_test=fail: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def read_regular(path: pathlib.Path) -> bytes:
    require(path.is_file() and not path.is_symlink(), f"missing or symlinked file: {path}")
    payload = path.read_bytes()
    require(payload, f"empty file: {path}")
    return payload


def png_dimensions(payload: bytes, label: str) -> tuple[int, int]:
    require(payload.startswith(PNG_SIGNATURE), f"{label}: invalid PNG signature")
    require(len(payload) >= 33, f"{label}: truncated PNG")
    length = struct.unpack(">I", payload[8:12])[0]
    require(length == 13 and payload[12:16] == b"IHDR", f"{label}: IHDR is invalid")
    width, height, depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", payload[16:29]
    )
    require(depth == 8, f"{label}: expected 8-bit channels")
    require(color_type == 6, f"{label}: expected RGBA color type")
    require((compression, filtering, interlace) == (0, 0, 0), f"{label}: unsupported PNG flags")
    return width, height


def web_path(url: str) -> pathlib.Path:
    require(url.startswith("/"), f"asset URL is not root-relative: {url}")
    path, separator, query = url.partition("?")
    if separator:
        require(query == "v=smartap-v54", f"asset URL has the wrong cache version: {url}")
    require(".." not in pathlib.PurePosixPath(path).parts, f"asset URL traverses upward: {url}")
    return WEB.joinpath(*pathlib.PurePosixPath(path).parts[1:])


def check_generator_lock() -> None:
    result = subprocess.run(
        [sys.executable, "-B", str(GENERATOR), "--check"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
        check=False,
    )
    require(result.returncode == 0, f"generated assets are stale: {result.stdout.strip()}")
    require("smart_ap_brand_check=pass" in result.stdout, "generator check did not report success")


def check_pngs_and_ico() -> None:
    for name, dimensions in PNG_SPECS.items():
        payload = read_regular(ICONS / name)
        require(png_dimensions(payload, name) == dimensions, f"{name}: dimensions do not match its name")

    ico = read_regular(THEME / "favicon.ico")
    require(not ico.startswith(PNG_SIGNATURE), "favicon.ico is a renamed PNG rather than an ICO")
    require(len(ico) >= 6, "favicon.ico is truncated")
    reserved, kind, count = struct.unpack("<HHH", ico[:6])
    require((reserved, kind, count) == (0, 1, 6), "favicon.ico header or frame count is invalid")
    expected_sizes = [16, 32, 48, 64, 128, 256]
    observed_sizes = []
    for index in range(count):
        start = 6 + index * 16
        entry = ico[start : start + 16]
        require(len(entry) == 16, "favicon.ico directory is truncated")
        width_byte, height_byte, colors, reserved_byte, planes, depth, length, offset = struct.unpack(
            "<BBBBHHII", entry
        )
        width = width_byte or 256
        height = height_byte or 256
        require(width == height, f"favicon.ico frame {index}: frame is not square")
        require((colors, reserved_byte, planes, depth) == (0, 0, 1, 32),
                f"favicon.ico frame {index}: invalid metadata")
        require(offset + length <= len(ico), f"favicon.ico frame {index}: payload exceeds file")
        frame = ico[offset : offset + length]
        require(png_dimensions(frame, f"favicon.ico frame {index}") == (width, height),
                f"favicon.ico frame {index}: embedded PNG size mismatch")
        observed_sizes.append(width)
    require(observed_sizes == expected_sizes, "favicon.ico does not contain the canonical size set")


def check_svg_manifest_and_browserconfig() -> None:
    svg_payload = read_regular(ICONS / "smart-ap.svg")
    svg = ET.fromstring(svg_payload)
    require(svg.tag.endswith("svg"), "Smart AP SVG root is invalid")
    require(svg.attrib.get("viewBox") == "0 0 512 512", "Smart AP SVG viewBox is wrong")
    titles = [element.text for element in svg.iter() if element.tag.endswith("title")]
    require(titles == ["Smart AP"], "Smart AP SVG title is missing or ambiguous")

    manifest = json.loads(read_regular(ICONS / "manifest.json").decode("utf-8"))
    require(manifest.get("name") == "Smart AP", "manifest name is not Smart AP")
    require(manifest.get("short_name") == "Smart AP", "manifest short name is not Smart AP")
    require(manifest.get("start_url") == "/" and manifest.get("scope") == "/",
            "manifest start URL or scope is wrong")
    require(manifest.get("display") == "standalone", "manifest display mode is wrong")
    require(manifest.get("theme_color") == "#2563eb", "manifest theme color is wrong")
    manifest_icons = manifest.get("icons")
    require(isinstance(manifest_icons, list) and len(manifest_icons) == 2,
            "manifest must contain exactly the 192 and 512 icons")
    observed = {}
    for icon in manifest_icons:
        require(icon.get("type") == "image/png" and icon.get("purpose") == "any",
                "manifest icon metadata is invalid")
        url = icon.get("src")
        require(isinstance(url, str) and url.startswith("/luci-static/argon/icon/") and
                url.endswith("?v=smartap-v54"),
                "manifest icon URL is invalid")
        payload = read_regular(web_path(url))
        dimensions = png_dimensions(payload, url)
        observed[icon.get("sizes")] = dimensions
    require(observed == {"192x192": (192, 192), "512x512": (512, 512)},
            "manifest icon declarations and files disagree")

    browserconfig = ET.fromstring(read_regular(ICONS / "browserconfig.xml"))
    expected_tiles = {
        "square70x70logo": "/luci-static/argon/icon/ms-icon-70x70.png?v=smartap-v54",
        "square150x150logo": "/luci-static/argon/icon/ms-icon-150x150.png?v=smartap-v54",
        "square310x310logo": "/luci-static/argon/icon/ms-icon-310x310.png?v=smartap-v54",
    }
    for tag, expected_url in expected_tiles.items():
        element = browserconfig.find(f"./msapplication/tile/{tag}")
        require(element is not None and element.attrib.get("src") == expected_url,
                f"browserconfig {tag} is missing or wrong")
        read_regular(web_path(expected_url))
    tile_color = browserconfig.find("./msapplication/tile/TileColor")
    require(tile_color is not None and tile_color.text == "#2563eb",
            "browserconfig tile color is wrong")


def check_references_and_visible_identity() -> None:
    require(not (THEME / "img/argon.jpg").exists(), "legacy MD/Argon bitmap is still shipped")
    index = read_regular(WEB / "index.html").decode("utf-8")
    required_index = [
        '<meta name="application-name" content="Smart AP">',
        '<meta name="theme-color" content="#2563eb">',
        '/luci-static/argon/icon/browserconfig.xml',
        '/luci-static/argon/icon/smart-ap.svg',
        '/luci-static/argon/favicon.ico',
        '/luci-static/argon/icon/favicon-32x32.png',
        '/luci-static/argon/icon/apple-icon-180x180.png',
        '/luci-static/argon/icon/manifest.json',
        '<title>Smart AP</title>',
    ]
    for marker in required_index:
        require(marker in index, f"Smart AP index is missing {marker!r}")
    require('href="data:,' not in index, "Smart AP index still suppresses its favicon")
    for marker in required_index[2:8]:
        require(f'{marker}?v=smartap-v54' in index,
                f"Smart AP index does not version {marker!r} against stale MD cache")

    for url in set(re.findall(r'(?:href|content)="(/luci-static/argon/(?:favicon\.ico|icon/[^"?]+)\?v=smartap-v54)"', index)):
        read_regular(web_path(url))

    for name in ("header.ut", "header_login.ut"):
        source = read_regular(TEMPLATES / name).decode("utf-8")
        for marker in (
            "<title>Smart AP",
            'content="Smart AP"',
            '{{ media }}/icon/browserconfig.xml',
            '{{ media }}/icon/smart-ap.svg',
            '{{ media }}/favicon.ico',
            '{{ media }}/icon/apple-icon-180x180.png',
            '{{ media }}/icon/manifest.json',
        ):
            require(marker in source, f"{name} is missing {marker!r}")
        require(" - LuCI</title>" not in source, f"{name} still exposes the old browser title")

    header = read_regular(TEMPLATES / "header.ut").decode("utf-8")
    require(header.count('<a class="brand" href="/">Smart AP</a>') == 2,
            "authenticated LuCI header is not consistently branded")
    # luci-base's outer header already loads luci.js and derives the resource
    # cache key from that script URL.  Loading it again from the theme can make
    # the first (stale) URL win after an upgrade and leave views at
    # "Loading view...".  Themes may add cbi.js, but never luci.js itself.
    for name in ("header.ut", "header_login.ut"):
        source = read_regular(TEMPLATES / name).decode("utf-8")
        require("/luci.js" not in source and "resource }}/luci.js" not in source,
                f"{name} duplicates luci-base's mandatory luci.js loader")

    sysauth = read_regular(TEMPLATES / "sysauth.ut").decode("utf-8")
    require("http.redirect('/');" in sysauth,
            "unauthenticated LuCI does not return to the Smart AP login")
    require("Smart AP owns password entry" in sysauth,
            "LuCI sysauth does not document the single-login contract")
    require('<form' not in sysauth and 'type="password"' not in sysauth,
            "LuCI exposes a second password page instead of Smart AP")
    require("img/argon.jpg" not in sysauth, "LuCI login still references the MD/Argon bitmap")

    for name in ("footer.ut", "footer_login.ut"):
        source = read_regular(TEMPLATES / name).decode("utf-8")
        require("<span>Smart AP</span>" in source, f"{name} lacks the Smart AP identity")
        require("ArgonTheme" not in source, f"{name} still exposes the ArgonTheme link")


def main() -> int:
    check_generator_lock()
    check_pngs_and_ico()
    check_svg_manifest_and_browserconfig()
    check_references_and_visible_identity()
    print("smart_ap_brand_generator_lock=pass")
    print(f"smart_ap_brand_png_dimensions=pass files={len(PNG_SPECS)}")
    print("smart_ap_brand_ico_frames=pass frames=6")
    print("smart_ap_brand_manifest_references=pass")
    print("smart_ap_brand_visible_identity=pass")
    print("smart_ap_branding_test=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
