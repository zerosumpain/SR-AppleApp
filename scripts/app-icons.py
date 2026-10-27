#!/usr/bin/env python3
"""Render the app's icons: the pixel `SR` and its bar, one per palette.

The primary icon is Prism's; each other palette in `SRPalette.swift` has an
alternate (`AppIcon-<Name>`), which the app switches to when the reader picks
that palette (Settings → Colours → "Matching app icon"). The geometry matches
`SRAppIconMark` in `ios/SRAppleApp/Settings/ColoursSheet.swift`, which draws
the same icon in the picker — change one, change both.

Pure standard library (zlib + struct): the box that renders these has no
imaging library, and a 1024-square RGB PNG needs none. No alpha channel:
App Store Connect refuses an icon that has one.

    python3 scripts/app-icons.py                 # every palette
    python3 scripts/app-icons.py candy citrus    # only these

Name only the palettes you changed: zlib's output is not promised to be the
same byte for byte across builds, so re-rendering the rest can churn PNGs
whose pixels did not change.
"""

import json
import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
ASSETS = Path(__file__).resolve().parent.parent / "ios/SRAppleApp/Assets.xcassets"
# The Watch app wears the primary (Prism) icon: watchOS has no alternate icons.
WATCH_ICON = Path(__file__).resolve().parent.parent / "ios/SRAppleWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

# The mark on an 11 x 7 grid: S in columns 0-4, R in 6-10.
MARK = [
    "#####.####.",
    "#.....#...#",
    "#.....#...#",
    "#####.####.",
    "....#.#.#..",
    "....#.#..#.",
    "#####.#...#",
]

# name: (asset, ground corners TL TR BL BR, mark ink, bar, sheen)
ICONS = {
    "prism": ("AppIcon", (0xFF7A59, 0xF472B6, 0x7C3AED, 0x3B4BF5), 0xFFFFFF, 0xFFFFFF, 0.22),
    "sherbet": ("AppIcon-Sherbet", (0xFFB85C, 0xFF9A8B, 0xF2545B, 0xB04EE0), 0xFFFFFF, 0xFFFFFF, 0.22),
    "ocean": ("AppIcon-Ocean", (0x5EEAD4, 0x60A5FA, 0x0B8EA0, 0x1D4ED8), 0xFFFFFF, 0xFFFFFF, 0.22),
    "sunset": ("AppIcon-Sunset", (0xFDBA74, 0xFF8A65, 0xE03A8A, 0x7C3AED), 0xFFFFFF, 0xFFFFFF, 0.22),
    "meadow": ("AppIcon-Meadow", (0xB5D86B, 0xF2CC5C, 0x23887C, 0x3E6F8E), 0xFFFFFF, 0xFFFFFF, 0.22),
    "classic": ("AppIcon-Classic", (0x1A1008, 0x1A1008, 0x1A1008, 0x1A1008), 0xEDE4D4, 0xE8863A, 0.06),
    # Candy's ground is too pale for a white mark: grape ink, a bubblegum bar.
    "candy": ("AppIcon-Candy", (0xFF9CCB, 0xFFE76A, 0x8FD8FF, 0x7DF2C9), 0x2A1235, 0xF2559A, 0.22),
    "citrus": ("AppIcon-Citrus", (0xFFC400, 0x7CB518, 0xFF7A00, 0xE63E62), 0xFFFFFF, 0xFFFFFF, 0.22),
    "berry": ("AppIcon-Berry", (0xE0306A, 0x8B2387, 0x3148C8, 0x3D1550), 0xFFFFFF, 0xFFFFFF, 0.22),
    "lavender": ("AppIcon-Lavender", (0xEE8FAE, 0xA98BEB, 0x7F95F0, 0x5CC9A6), 0xFFFFFF, 0xFFFFFF, 0.22),
    "arctic": ("AppIcon-Arctic", (0x7FDDBA, 0x8EC2F0, 0x3E86D0, 0x1E3F6E), 0xFFFFFF, 0xFFFFFF, 0.22),
    "forest": ("AppIcon-Forest", (0x4F7D2A, 0xC07A10, 0x1F5E45, 0x4A3424), 0xFFFFFF, 0xE8B04A, 0.16),
    "terracotta": ("AppIcon-Terracotta", (0xE8BF72, 0xC2593A, 0x8FAF8A, 0x5A7FA0), 0xFFFFFF, 0xFFFFFF, 0.22),
    "graphite": ("AppIcon-Graphite", (0x4A4F57, 0x3B4048, 0x2A2D33, 0x1C1E22), 0xF2F2F1, 0xFF5A1F, 0.10),
}


def rgb(hex_value):
    return ((hex_value >> 16) & 0xFF, (hex_value >> 8) & 0xFF, hex_value & 0xFF)


def shapes():
    """Every rounded rectangle on the icon: (x0, y0, x1, y1, radius)."""
    out = []
    for y, row in enumerate(MARK):
        for x, cell in enumerate(row):
            if cell != "#":
                continue
            left = 185 + x * 58 if x < 6 else 545 + (x - 6) * 58
            top = 260 + y * 58
            out.append((left + 4, top + 4, left + 54, top + 54, 12))
    bar = (185, 734, 835, 760, 13)
    return out, bar


def sdf(px, py, rect):
    """Signed distance from a point to a rounded rectangle; negative inside."""
    x0, y0, x1, y1, r = rect
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    dx, dy = abs(px - cx) - hx, abs(py - cy) - hy
    outside = math.hypot(max(dx, 0), max(dy, 0))
    return outside + min(max(dx, dy), 0) - r


def render(corners, ink, bar_colour, sheen):
    cells, bar = shapes()
    tl, tr, bl, br = (rgb(c) for c in corners)
    ink, bar_colour = rgb(ink), rgb(bar_colour)
    # Bucket the shapes by row band so each pixel tests only its neighbours.
    bands = {}
    for rect, colour in [(c, ink) for c in cells] + [(bar, bar_colour)]:
        for band in range(int(rect[1] - 24) // 32, int(rect[3] + 24) // 32 + 1):
            bands.setdefault(band, []).append((rect, colour))
    rows = []
    for y in range(SIZE):
        v = y / (SIZE - 1)
        near = bands.get(y // 32, [])
        row = bytearray()
        for x in range(SIZE):
            u = x / (SIZE - 1)
            colour = [
                (tl[i] * (1 - u) + tr[i] * u) * (1 - v) + (bl[i] * (1 - u) + br[i] * u) * v
                for i in range(3)
            ]
            # A soft sheen from the top-left, as on a Home tile.
            glow = sheen * max(0.0, 1 - math.hypot(x, y) / 760)
            colour = [c + (255 - c) * glow for c in colour]
            for rect, fill in near:
                if not (rect[0] - 24 <= x <= rect[2] + 24):
                    continue
                # A shadow under each cell, then the cell, antialiased.
                shadow = min(max((14 - sdf(x, y - 8, rect)) / 28, 0), 1) * 0.16
                colour = [c * (1 - shadow) for c in colour]
                cover = min(max(0.5 - sdf(x, y, rect), 0), 1)
                if cover:
                    colour = [c * (1 - cover) + f * cover for c, f in zip(colour, fill)]
            row.extend(int(round(min(max(c, 0), 255))) for c in colour)
        rows.append(row)
    return rows


def png(rows):
    raw = bytearray()
    for row in rows:
        # Filter 1 (Sub): a gradient's neighbours differ by a little, which
        # deflate packs far better than the raw values.
        raw.append(1)
        prev = [0, 0, 0]
        for i in range(0, len(row), 3):
            for k in range(3):
                raw.append((row[i + k] - prev[k]) & 0xFF)
                prev[k] = row[i + k]

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def main(names):
    unknown = [name for name in names if name not in ICONS]
    if unknown:
        sys.exit(f"no such palette: {', '.join(unknown)} (have {', '.join(ICONS)})")
    for name in names or ICONS:
        asset, corners, ink, bar, sheen = ICONS[name]
        folder = ASSETS / f"{asset}.appiconset"
        folder.mkdir(exist_ok=True)
        image = png(render(corners, ink, bar, sheen))
        (folder / f"{asset}.png").write_bytes(image)
        if asset == "AppIcon":
            WATCH_ICON.write_bytes(image)
        contents = {
            "images": [{"filename": f"{asset}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }
        (folder / "Contents.json").write_text(json.dumps(contents) + "\n")
        print(f"{name}: {folder.name}/{asset}.png")


if __name__ == "__main__":
    main(sys.argv[1:])
