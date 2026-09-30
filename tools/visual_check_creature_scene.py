#!/usr/bin/env python3
"""Structural pixel asserts for the creature-STAGE scene capture (task 7).

No golden images — llvmpipe-deterministic STRUCTURAL tolerances (font/AA may
shift across mesa versions). The z-sort probe anchors are computed by the
GDScript harness from the rig metrics + the live camera (the TS manual
transform inverse) and passed in as floats.

Captures (all one frozen fixture world: player hue-120 at z 50, a hue-15 ent
at z 100 overlapping):
  DAY    — lawn band present, sky corner bluish, vignette darkens the corner,
           HP bar panel + fill at the TS inset (vh-108, centered, w<=340)
  ZSORT  — determinism twin of DAY (same frozen commands) + Ruling 14: the
           ent at z 100 draws ABOVE the player at z 50 — the ent's body (red)
           covers the player's body center, while the player's tail end stays
           visible left of the ent (green, at the harness-supplied probe)
  NIGHT  — dayPhase forced to 0.7 (inside the (0.55, 0.95) isNight window):
           the rgba(10,10,40,~0.38) overlay dims the frame vs DAY, and the 20
           deterministic fireflies show as yellow-green dots in the upper 60%

Usage: visual_check_creature_scene.py DAY_PNG ZSORT_PNG NIGHT_PNG
           PX PLAYER_CY ENT_CX ENT_CY GREEN_X; exit 0 = all held.
"""
import math
import sys

from PIL import Image


def px(im, x, y):
    return im.getpixel((int(x), int(y)))[:3]


def patch_mean(im, cx, cy, r):
    n = 0
    sr = sg = sb = 0
    for yy in range(int(cy) - r, int(cy) + r + 1):
        for xx in range(int(cx) - r, int(cx) + r + 1):
            if 0 <= xx < im.size[0] and 0 <= yy < im.size[1]:
                p = px(im, xx, yy)
                sr += p[0]
                sg += p[1]
                sb += p[2]
                n += 1
    return (sr / n, sg / n, sb / n)


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def main():
    day = Image.open(sys.argv[1]).convert("RGB")
    zsort = Image.open(sys.argv[2]).convert("RGB")
    night = Image.open(sys.argv[3]).convert("RGB")
    fpx, fpcy, fecx, fecy, fgx = (float(v) for v in sys.argv[4:9])
    W, H = day.size
    failures = []

    def check(name, cond, detail):
        print(("OK  " if cond else "FAIL") + " %s %s" % (name, detail))
        if not cond:
            failures.append(name)

    # (a) sky corner — the day sky gradient is bluish; the hill ridges at the
    # far left sit at y >= ~100 (pinned by the layer seeds), so the top-left
    # corner is sky, not hill
    c = patch_mean(day, 12, 12, 10)
    check("day-sky-corner", c[2] >= c[1] - 5 and c[1] >= c[0] - 5 and c[2] >= 45,
          str(tuple(round(v) for v in c)))

    # (b) lawn band — green-dominant across the middle third at 55%/62% height
    for frac in (0.55, 0.62):
        y = int(H * frac)
        n = ok = 0
        for xx in range(int(W / 3), int(2 * W / 3), 4):
            p = px(day, xx, y)
            n += 1
            if p[1] > p[0] + 12 and p[1] > p[2] + 12:
                ok += 1
        check("day-lawn-%d%%" % int(frac * 100), ok >= n * 0.55,
              "%d/%d green-dominant" % (ok, n))

    # (c) vignette — the corner is darker than the mid-field
    corner = lum(patch_mean(day, 14, 14, 12))
    mid = lum(patch_mean(day, W * 0.25, H * 0.72, 12))
    check("day-vignette", corner < mid - 8,
          "corner %.0f < mid %.0f - 8" % (corner, mid))

    # (d) HP bar at the TS inset: panel (dark) row above the fill, fill row
    hy = H - 108
    hpw = min(340.0, W * 0.3)
    hx = W / 2.0 - hpw / 2.0
    dark = fill = 0
    for xx in range(int(hx - 6), int(hx + hpw + 6), 2):
        p = px(day, xx, hy - 4)
        if sum(p) <= 200:
            dark += 1
    for xx in range(int(hx), int(hx + hpw), 2):
        p = px(day, xx, hy + 4)
        if (p[1] >= 140 and p[1] - p[0] >= 40) or (p[0] >= 180 and p[0] - p[1] >= 60):
            fill += 1
    check("day-hpbar-panel", dark >= 60, "%d dark panel px" % dark)
    check("day-hpbar-fill", fill >= 30, "%d fill px" % fill)

    # (e) determinism twin — the same frozen commands one frame apart
    diff = 0.0
    n = 0
    for fy in (0.2, 0.4, 0.6, 0.8):
        for fx in (0.2, 0.4, 0.6, 0.8):
            a = px(day, W * fx, H * fy)
            b = px(zsort, W * fx, H * fy)
            diff += sum(abs(a[k] - b[k]) for k in range(3)) / 3.0
            n += 1
    check("day-zsort-twin", diff / n <= 1.0, "mean abs diff %.2f" % (diff / n))

    # (f) RULING 14 — the ent at z 100 draws ABOVE the player at z 50: the
    # ent's body covers the player's body center (red wins the overlap)
    c = px(zsort, fpx, fpcy)
    check("zsort-ent-over-player", c[0] - c[1] >= 60 and c[0] >= 110, str(c))
    # and at the ent's own body center
    c = px(zsort, fecx, fecy)
    check("zsort-ent-body", c[0] - c[1] >= 60 and c[0] >= 110, str(c))
    # the player's tail end stays visible left of the ent (green)
    c = px(zsort, fgx, fpcy)
    check("zsort-player-visible", c[1] - c[0] >= 30 and c[1] >= 95, str(c))

    # (i) night overlay dims the frame (same frozen content, only dayPhase moved)
    pd = lum(patch_mean(day, W / 2.0, 200, 20))
    pn = lum(patch_mean(night, W / 2.0, 200, 20))
    check("night-dim", pn < pd - 18, "day %.0f -> night %.0f" % (pd, pn))

    # (j) fireflies — DAY-vs-NIGHT differential: the rgba(10,10,40) overlay
    # darkens every world pixel, so the only pixels BRIGHTER at night are the
    # 20 deterministic fireflies (yellow-green: g > b) and the stars (neutral
    # blue-white: b >= g, excluded)
    n = 0
    for yy in range(0, H, 2):
        for xx in range(0, W, 2):
            a = px(night, xx, yy)
            b = px(day, xx, yy)
            if a[0] - b[0] >= 15 and a[1] - b[1] >= 15 and a[1] - a[2] >= 20:
                n += 1
    check("night-fireflies", n >= 8, "%d firefly px" % n)

    print("---")
    if failures:
        print("VISUAL_CHECK_FAIL: %s" % ", ".join(failures))
        return 1
    print("VISUAL_CHECK_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
