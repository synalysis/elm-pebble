#!/usr/bin/env python3
"""Generate tangram figure SVG and PDC assets for the watchface template."""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VECTORS_DIR = os.path.join(SCRIPT_DIR, "vectors")
TOOLS_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", "..", "tools"))
VENDOR_DIR = os.path.join(TOOLS_DIR, "svg2pdc_vendor")
SVG2PDC = os.path.join(TOOLS_DIR, "svg2pdc.py")

OFFSET_X = 66
OFFSET_Y = 58
VIEW_W = 132
VIEW_H = 126

COLORS = {
    "vividCerulean": "#0055FF",
    "pictonBlue": "#00AAFF",
    "tiffanyBlue": "#55FFFF",
    "cyan": "#00FFFF",
    "blueMoon": "#001133",
    "electricBlue": "#0055DD",
    "veryLightBlue": "#AADDFF",
}

FIGURES = [
    (
        "TangramBird",
        [
            ("vividCerulean", [(-8, -6), (-42, -30), (-52, 10)]),
            ("pictonBlue", [(8, -6), (42, -30), (52, 10)]),
            ("tiffanyBlue", [(-18, 2), (0, -12), (18, 2), (0, 18)]),
            ("cyan", [(18, -4), (36, -12), (32, 8)]),
            ("blueMoon", [(-18, 8), (-40, 0), (-46, 16), (-24, 24)]),
            ("electricBlue", [(-5, 18), (-28, 34), (4, 32)]),
            ("veryLightBlue", [(6, 18), (34, 32), (12, 36)]),
        ],
    ),
    (
        "TangramComet",
        [
            ("cyan", [(24, -4), (42, -22), (60, -4), (42, 14)]),
            ("vividCerulean", [(8, -12), (32, -4), (8, 14)]),
            ("pictonBlue", [(-10, -18), (12, -8), (-12, 2)]),
            ("tiffanyBlue", [(-26, -20), (-4, -8), (-28, 4)]),
            ("blueMoon", [(-48, -18), (-18, -8), (-8, 8), (-38, -2)]),
            ("electricBlue", [(-52, 4), (-16, 8), (-44, 24)]),
            ("veryLightBlue", [(-36, -36), (-8, -16), (-48, -16)]),
        ],
    ),
    (
        "TangramCrown",
        [
            ("blueMoon", [(-48, 12), (38, 12), (48, 30), (-38, 30)]),
            ("vividCerulean", [(-48, 12), (-30, -28), (-8, 12)]),
            ("pictonBlue", [(-16, 12), (0, -36), (16, 12)]),
            ("electricBlue", [(8, 12), (30, -28), (48, 12)]),
            ("cyan", [(-8, 2), (0, -10), (8, 2), (0, 14)]),
            ("tiffanyBlue", [(-36, 10), (-24, -8), (-12, 10)]),
            ("veryLightBlue", [(12, 10), (24, -8), (36, 10)]),
        ],
    ),
    (
        "TangramBoat",
        [
            ("blueMoon", [(-54, 18), (44, 18), (32, 38), (-34, 38)]),
            ("vividCerulean", [(-8, 14), (-8, -34), (-44, 14)]),
            ("pictonBlue", [(-4, 14), (28, -26), (36, 14)]),
            ("tiffanyBlue", [(-8, -34), (2, -8), (-8, 14), (-20, -8)]),
            ("cyan", [(-34, 28), (-14, 16), (4, 28), (-14, 40)]),
            ("electricBlue", [(10, 20), (30, 20), (20, 34)]),
            ("veryLightBlue", [(-48, 18), (-30, 8), (-24, 18)]),
        ],
    ),
    (
        "TangramFlower",
        [
            ("cyan", [(-12, 0), (0, -12), (12, 0), (0, 12)]),
            ("vividCerulean", [(-16, -10), (0, -44), (16, -10)]),
            ("pictonBlue", [(10, -16), (44, 0), (10, 16)]),
            ("tiffanyBlue", [(-16, 10), (0, 44), (16, 10)]),
            ("electricBlue", [(-10, -16), (-44, 0), (-10, 16)]),
            ("blueMoon", [(10, 10), (34, 16), (16, 34), (0, 20)]),
            ("veryLightBlue", [(-10, 10), (-34, 16), (-16, 34)]),
        ],
    ),
    (
        "TangramKite",
        [
            ("cyan", [(0, -48), (28, -10), (0, 12), (-28, -10)]),
            ("vividCerulean", [(0, -48), (28, -10), (0, -10)]),
            ("pictonBlue", [(0, -48), (0, -10), (-28, -10)]),
            ("blueMoon", [(-28, -10), (0, 12), (28, -10), (0, 34)]),
            ("tiffanyBlue", [(-12, 30), (0, 42), (12, 30)]),
            ("electricBlue", [(0, 42), (-16, 50), (2, 52)]),
            ("veryLightBlue", [(2, 52), (18, 58), (8, 64)]),
        ],
    ),
]


def shift(points):
    return [(x + OFFSET_X, y + OFFSET_Y) for x, y in points]


def points_attr(points):
    return " ".join(f"{x},{y}" for x, y in shift(points))


def write_svg(name, pieces):
    polygons = "\n".join(
        f'  <polygon points="{points_attr(points)}" fill="{COLORS[color]}"/>'
        for color, points in pieces
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {VIEW_W} {VIEW_H}">\n'
        f"{polygons}\n"
        f"</svg>\n"
    )


def main():
    os.makedirs(VECTORS_DIR, exist_ok=True)
    env = os.environ.copy()
    env["PYTHONPATH"] = f"{TOOLS_DIR}:{VENDOR_DIR}"

    manifest_entries = []

    for ctor, pieces in FIGURES:
        svg_path = os.path.join(VECTORS_DIR, f"{ctor}.svg")
        pdc_path = os.path.join(VECTORS_DIR, f"{ctor}.pdc")

        with open(svg_path, "w", encoding="utf-8") as handle:
            handle.write(write_svg(ctor, pieces))

        result = subprocess.run(
            [sys.executable, SVG2PDC, svg_path, "-o", pdc_path],
            env=env,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(result.stdout)
            print(result.stderr, file=sys.stderr)
            raise SystemExit(f"Failed to convert {svg_path}")

        os.remove(svg_path)
        size = os.path.getsize(pdc_path)
        manifest_entries.append(
            {
                "id": f"vector_{ctor.lower()}",
                "ctor": ctor,
                "filename": f"{ctor}.pdc",
                "mime": "application/octet-stream",
                "bytes": size,
                "source": "pdc",
            }
        )
        print(f"Wrote {pdc_path} ({size} bytes)")

    manifest = {"schema_version": 1, "entries": manifest_entries}
    manifest_path = os.path.join(SCRIPT_DIR, "vectors.json")
    import json

    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")

    print(f"Wrote {manifest_path}")


if __name__ == "__main__":
    main()
