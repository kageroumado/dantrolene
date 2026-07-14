#!/usr/bin/env python3
"""Regenerate the Dantrolene.icon SVG layers from the mark's parametric geometry.

The single source of truth for the arc-house is ``MarkGeometry`` in
``Dantrolene/MorphingMark.swift``; this script mirrors its home-pose constants and
emits the Icon Composer layers:

- ``roof.svg``  — the flared 5W roof arc, as a filled outline (dark ink)
- ``house.svg`` — a pale panel filling the region the body encloses, plus the body
  and door strokes as filled outlines on top

Strokes are pre-flattened to filled outlines (``shapely.buffer``, round caps)
because both Icon Composer and the symbol compiler mangle stroked paths.

Run from the repo root after changing MarkGeometry:

    python3 Scripts/generate-icon-assets.py
"""

import math
from pathlib import Path

from shapely.geometry import LineString

# MarkGeometry constants (MorphingMark.swift)
W = 2.1
AXIS = 16.0
BASE = 27.0
ORIGIN_Y = BASE - 4.5 * W  # the shared "wifi origin" of body cap and roof arc

ASSETS = Path(__file__).resolve().parent.parent / "Dantrolene" / "Dantrolene.icon" / "Assets"

PANEL_FILL = "#efe9ff"
INK_FILL = "#31265e"


def arc(cy, r, a0, a1, n, cx=AXIS):
    return [
        (cx + r * math.cos(a0 + (a1 - a0) * i / (n - 1)), cy - r * math.sin(a0 + (a1 - a0) * i / (n - 1)))
        for i in range(n)
    ]


def line(p0, p1, n):
    return [
        (p0[0] + (p1[0] - p0[0]) * i / (n - 1), p0[1] + (p1[1] - p0[1]) * i / (n - 1))
        for i in range(n)
    ]


def tangent_kick(cy, r, a, length, n):
    """Straight extension of the arc's tangent at angle `a` — the roof's eave kick."""
    sx, sy = AXIS + r * math.cos(a), cy - r * math.sin(a)
    dx, dy = abs(math.sin(a)), abs(math.cos(a))
    sign = 1 if math.cos(a) >= 0 else -1
    return [(sx + sign * dx * length * i / n, sy + dy * length * i / n) for i in range(1, n + 1)]


def home_strokes():
    sweep = math.pi / 3  # ±60° from apex
    roof = (
        list(reversed(tangent_kick(ORIGIN_Y, 5 * W, math.pi / 2 + sweep, 1.5 * W, 6)))
        + arc(ORIGIN_Y, 5 * W, math.pi / 2 + sweep, math.pi / 2 - sweep, 72)
        + tangent_kick(ORIGIN_Y, 5 * W, math.pi / 2 - sweep, 1.5 * W, 6)
    )
    body = (
        line((AXIS - 3 * W, BASE), (AXIS - 3 * W, ORIGIN_Y), 12)
        + arc(ORIGIN_Y, 3 * W, math.pi, 0, 56)
        + line((AXIS + 3 * W, ORIGIN_Y), (AXIS + 3 * W, BASE), 12)
    )
    door_c = BASE - 2.5 * W
    door = (
        line((AXIS - W, BASE), (AXIS - W, door_c), 8)
        + arc(door_c, W, math.pi, 0, 40)
        + line((AXIS + W, door_c), (AXIS + W, BASE), 8)
    )
    return roof, body, door


def path_d(points, close=True):
    d = "M " + " L ".join(f"{x:.3f},{y:.3f}" for x, y in points)
    return d + " Z" if close else d


def outline_d(points):
    """A stroke centerline flattened to its filled outline (round caps and joins)."""
    poly = LineString(points).buffer(W / 2, quad_segs=16)
    rings = [poly.exterior, *poly.interiors]
    return " ".join(path_d(list(ring.coords)) for ring in rings)


# Scale from design units to the 1024 canvas. 26 was the original hand-tuned value; the
# mark read too small on the icon grid, so it now sits 30% larger, centered on its own
# visual (stroke-expanded) bounding box.
SCALE = 33.8


def mark_bounds(strokes):
    """The union bounding box of the buffered strokes — the mark's visual extent."""
    xs, ys = [], []
    for stroke in strokes:
        x0, y0, x1, y1 = LineString(stroke).buffer(W / 2, quad_segs=16).bounds
        xs += [x0, x1]
        ys += [y0, y1]
    return min(xs), min(ys), max(xs), max(ys)


def svg(paths, transform):
    body = "\n".join(f"    {p}" for p in paths)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
        f'  <g transform="{transform}">\n'
        f"{body}\n"
        "  </g>\n"
        "</svg>\n"
    )


def main():
    roof, body, door = home_strokes()

    # Center the mark's visual bbox on the canvas. Both layers share one transform so
    # they stay registered.
    x0, y0, x1, y1 = mark_bounds([roof, body, door])
    tx = 512 - (x0 + x1) / 2 * SCALE
    ty = 512 - (y0 + y1) / 2 * SCALE
    transform = f"translate({tx:.1f},{ty:.1f}) scale({SCALE})"

    roof_svg = svg([f'<path d="{outline_d(roof)}" fill="{INK_FILL}" fill-rule="evenodd"/>'], transform)

    # The pale panel fills the region the body encloses (legs + cap, sealed along the base).
    panel_d = path_d(body)
    house_svg = svg([
        f'<path d="{panel_d}" fill="{PANEL_FILL}"/>',
        f'<path d="{outline_d(body)}" fill="{INK_FILL}" fill-rule="evenodd"/>',
        f'<path d="{outline_d(door)}" fill="{INK_FILL}" fill-rule="evenodd"/>',
    ], transform)

    (ASSETS / "roof.svg").write_text(roof_svg)
    (ASSETS / "house.svg").write_text(house_svg)
    print(f"wrote {ASSETS / 'roof.svg'}")
    print(f"wrote {ASSETS / 'house.svg'}")


if __name__ == "__main__":
    main()
