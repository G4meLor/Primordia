#!/usr/bin/env python3
"""Structural pixel asserts for the cell-stage visual capture (task 7).

No golden images — llvmpipe-deterministic STRUCTURAL tolerances per the task
brief: assert structural pixels, not byte equality (font/AA may shift across
mesa versions).

Asserts (CALM capture):
  a) body-disc center ≈ hue-120 — the hue axis is exact for every membrane
     gradient stop at hue 120 (r == b: X = 0 in the [120,180) HSL sector),
     green-dominant over the blue backdrop. |r−b| ≤ 12, g ≥ 75, g−max ≥ 40.
  b) membrane ring — a vertical ray up from the center crosses the wobble rim
     (r ∈ [12, 16] px at size 1.0): fill→outline→backdrop is a ≥40/channel
     discontinuity inside the 11..19 search window.
  c) backdrop corner ≠ pure black — the depth gradient is a blue wash
     (hsl(222−·,.65,.1355) ≈ (12,26,57) at depth01 .409, vignette-darkened
     toward (0,0,10)); b ≥ r and some channel ≥ 25.
  d) two flagella tails — bright green strokes in the left-down (146°) and
     left-up (216°) canvas sectors behind the cell (anchor angles π ∓ 0.6
     rad), radius band 16.5..36 px (beyond the max membrane wobble 15.9),
     g-dominant filter (motes/caustics are bluish and excluded).
Chaos capture (sim frozen — only the tint differs):
  e) the chaos tint shifts the backdrop corner (depth-gradient hue 222→198 at
     chaos 0.8 plus the pink overlay) — |Δg| ≥ 6 at the corner.
Glitch capture (sim frozen, overlay forced visible — presence only, the
brief checks presence/tint, not exact blend math):
  f) the difference-composite overlay changes sampled pixels vs the chaos
     frame (the W3C difference math moves the whole frame at alpha ~0.09).

Usage: visual_check.py CALM_PNG CHAOS_PNG [GLITCH_PNG]; exit 0 = all held.
"""
import math
import sys

from PIL import Image


def px(im, x, y):
    return im.getpixel((int(x), int(y)))[:3]


def main():
    calm = Image.open(sys.argv[1]).convert("RGB")
    chaos = Image.open(sys.argv[2]).convert("RGB")
    glitch = Image.open(sys.argv[3]).convert("RGB") if len(sys.argv) > 3 else None
    W, H = calm.size
    cx, cy = W / 2.0, H / 2.0
    failures = []

    def check(name, cond, detail):
        print(("OK  " if cond else "FAIL") + " %s %s" % (name, detail))
        if not cond:
            failures.append(name)

    # (a) body-disc center ≈ hue-120
    c = px(calm, cx, cy)
    check("center-hue120", abs(c[0] - c[2]) <= 12 and c[1] >= 75
          and c[1] - max(c[0], c[2]) >= 40, str(c))

    # (b) membrane ring discontinuity on a vertical ray above the center
    ray = [px(calm, cx, cy - r) for r in range(4, 25)]
    max_step, max_at = 0, -1
    for i in range(1, len(ray)):
        r = 4 + i
        if 11 <= r <= 19:
            d = max(abs(ray[i][k] - ray[i - 1][k]) for k in range(3))
            if d > max_step:
                max_step, max_at = d, r
    check("membrane-edge", max_step >= 40,
          "max channel step %d at r=%d" % (max_step, max_at))
    inside = px(calm, cx, cy - 8)
    check("membrane-inside-green", inside[1] > inside[2] + 20, str(inside))

    # (c) backdrop corner is not pure black
    corner = px(calm, 2, 2)
    check("backdrop-corner", max(corner) >= 25 and corner[2] >= corner[0],
          str(corner))

    # (d) two flagella tails behind the cell
    def sector_count(center_deg):
        n = 0
        for yy in range(int(cy) - 40, int(cy) + 41):
            for xx in range(int(cx) - 40, int(cx) + 1):
                dx, dy = xx - cx, yy - cy
                r = math.hypot(dx, dy)
                if not 16.5 <= r <= 36.0:
                    continue
                ang = math.degrees(math.atan2(dy, dx)) % 360.0
                d = min(abs(ang - center_deg), 360.0 - abs(ang - center_deg))
                if d <= 35.0:
                    p = px(calm, xx, yy)
                    if p[1] >= 110 and p[1] - p[2] >= 35 and p[1] - p[0] >= 35:
                        n += 1
        return n

    n_down = sector_count(146.0)
    n_up = sector_count(216.0)
    check("flagella-tail-1", n_down >= 3, "%d green px left-down sector" % n_down)
    check("flagella-tail-2", n_up >= 3, "%d green px left-up sector" % n_up)

    # (e) chaos tint shifts the backdrop corner
    cc = px(chaos, 2, 2)
    dg = cc[1] - corner[1]
    check("chaos-corner-shift", abs(dg) >= 6,
          "calm %s chaos %s dg=%d" % (corner, cc, dg))

    # (f) glitch overlay presence — sampled pixels move vs the chaos frame
    if glitch is not None:
        W2, H2 = chaos.size
        moved = 0
        samples = 0
        for fy in (0.25, 0.5, 0.75):
            for fx in (0.25, 0.5, 0.75):
                sx, sy = int(W2 * fx), int(H2 * fy)
                a = px(chaos, sx, sy)
                b = px(glitch, sx, sy)
                samples += 1
                if max(abs(a[k] - b[k]) for k in range(3)) >= 3:
                    moved += 1
        check("glitch-overlay-presence", moved >= samples - 1,
              "%d/%d sampled px moved" % (moved, samples))

    print("---")
    if failures:
        print("VISUAL_CHECK_FAIL: %s" % ", ".join(failures))
        return 1
    print("VISUAL_CHECK_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
