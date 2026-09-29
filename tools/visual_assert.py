#!/usr/bin/env python3
"""Per-moment structural pixel asserts for the task-10 six-moment visual suite.

No golden images — llvmpipe-deterministic STRUCTURAL tolerances (the task-7
doctrine: assert structural pixels, never byte equality; font/AA may shift
across mesa versions). Reference captures live under tests/fixtures/visual/
(recorded, not diffed — the drift record refreshes with --record).

Moments (one capture each; menu/editor pair two captures for motion/delta):
  menu        title view — title text region, 3 distinct menu-panel label
              regions, soup-gradient direction, deep-blue corner
  menu_drift  the same view 1 s later — the ambient drifter zone moves
  cell_early  gameplay at ~3 s post-card — player membrane hue axis at the
              screen center (pinned genome hue 120), backdrop depth-gradient
              direction (TS depth model: surface band brighter than the deep
              band at equal vignette radius), HUD DNA counter region present
  chaos_banner t≈60 s with a chaos event forced through the sim's
              chaos.trigger — the banner panel carries the chaos tint
              (#2a0a14 fill + #ff5a8a stroke/title) and the event's meteor
              ring paints in the world band
  editor_a/b  the editor over real KeyE — ≥10 parts-row text bands, the CELL
              PARTS header, the dark overlay wash; the DNA footer region
              changes between a and b (a real row-click purchase)
  death       forced php=0 — the red-dark wash lifts r over g at spread
              samples, REBIRTH IS PAINFUL text pixels present, the player
              membrane hidden
  card        a titled go_to card — the (2,3,10) veil at the corners + the
              #bfe6ff title pixels

Usage: visual_assert.py <captures_dir> [--record out.json]; exit 0 = all held.
"""
import json
import math
import os
import sys

from PIL import Image


def load(d, name):
    return Image.open(os.path.join(d, name)).convert("RGB")


def px(im, x, y):
    return im.getpixel((int(x), int(y)))[:3]


def patch_mean(im, x, y, rad=2):
    n = [0, 0, 0]
    c = 0
    for yy in range(int(y) - rad, int(y) + rad + 1):
        for xx in range(int(x) - rad, int(x) + rad + 1):
            p = im.getpixel((xx, yy))[:3]
            for k in range(3):
                n[k] += p[k]
            c += 1
    return tuple(v / c for v in n)


def count_region(im, x0, y0, x1, y1, pred):
    n = 0
    for y in range(max(0, int(y0)), min(im.height, int(y1))):
        for x in range(max(0, int(x0)), min(im.width, int(x1))):
            if pred(im.getpixel((x, y))[:3]):
                n += 1
    return n


def lum(p):
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def near(p, ref, tol):
    return all(abs(p[k] - ref[k]) <= tol for k in range(3))


def main():
    d = sys.argv[1]
    record_path = None
    if len(sys.argv) > 3 and sys.argv[2] == "--record":
        record_path = sys.argv[3]
    menu = load(d, "menu.png")
    drift = load(d, "menu_drift.png")
    cell = load(d, "cell_early.png")
    chaos = load(d, "chaos_banner.png")
    ed_a = load(d, "editor_a.png")
    ed_b = load(d, "editor_b.png")
    death = load(d, "death.png")
    card = load(d, "card.png")
    W, H = menu.size
    failures = []
    record = {}

    def check(moment, name, cond, detail):
        print(("OK  " if cond else "FAIL") + " %s.%s %s" % (moment, name, detail))
        record["%s.%s" % (moment, name)] = detail
        if not cond:
            failures.append("%s.%s" % (moment, name))

    # ---- menu ---------------------------------------------------------------
    bright = lambda p: min(p) >= 180
    n = count_region(menu, W / 2 - 350, H * 0.24 - 60, W / 2 + 350, H * 0.24 + 60, bright)
    check("menu", "title-text", n >= 400, "%d bright px in the title band" % n)
    by = H * 0.55
    for i in range(3):
        y0 = by + i * 68
        n = count_region(menu, W / 2 - 150, y0 + 8, W / 2 + 150, y0 + 46, bright)
        check("menu", "panel-%d" % (i + 1), n >= 40, "%d label px in menu button %d" % (n, i + 1))
    top = patch_mean(menu, W * 0.15, H * 0.10)
    bot = patch_mean(menu, W * 0.15, H * 0.90)
    check("menu", "gradient-direction", lum(top) >= lum(bot) + 8,
          "top %s vs bottom %s (soup: surface band lighter)" % (
              tuple(round(v) for v in top), tuple(round(v) for v in bot)))
    c = px(menu, 4, 4)
    check("menu", "deep-corner", c[2] >= c[0] and max(c) >= 20, str(c))
    moved = 0
    for y in range(int(H * 0.30), int(H * 0.75), 2):
        for x in list(range(int(W * 0.02), int(W * 0.16), 2)) + list(range(int(W * 0.84), int(W * 0.98), 2)):
            a = px(menu, x, y)
            b = px(drift, x, y)
            if max(abs(a[k] - b[k]) for k in range(3)) >= 4:
                moved += 1
    check("menu", "drifters-animate", moved >= 120,
          "%d sampled side-zone px moved in 1 s" % moved)

    # ---- cell_early -----------------------------------------------------------
    cx, cy = W / 2.0, H / 2.0
    c = px(cell, cx, cy)
    check("cell_early", "center-hue120", abs(c[0] - c[2]) <= 12 and c[1] >= 75
          and c[1] - max(c[0], c[2]) >= 40, str(c))
    inside = px(cell, cx, cy - 8)
    check("cell_early", "membrane-inside-green", inside[1] > inside[2] + 20, str(inside))
    t = patch_mean(cell, W * 0.15, H / 2 - 150)
    b = patch_mean(cell, W * 0.15, H / 2 + 150)
    check("cell_early", "depth-gradient", t[2] >= t[0] and b[2] >= b[0] and t[2] - b[2] >= 6,
          "surface band %s vs deep band %s (equal vignette radius)" % (
              tuple(round(v) for v in t), tuple(round(v) for v in b)))
    helix = lambda p: p[2] >= 190 and p[1] >= 140 and p[0] <= 170
    n = count_region(cell, 18, 18, 168, 58, helix)
    check("cell_early", "dna-counter", n >= 40, "%d helix/text px in the DNA panel" % n)

    # ---- chaos_banner -----------------------------------------------------------
    bg = lambda p: near(p, (42, 10, 20), 25)
    n = count_region(chaos, W / 2 - 280, 70, W / 2 + 280, 144, bg)
    check("chaos_banner", "banner-tint", n >= 800, "%d chaos-bg px in the banner panel" % n)
    accent = lambda p: near(p, (255, 90, 138), 45)
    n = count_region(chaos, W / 2 - 280, 70, W / 2 + 280, 144, accent)
    check("chaos_banner", "banner-title", n >= 120, "%d stroke/title px" % n)
    ring = lambda p: p[0] >= 90 and p[1] <= 145 and p[0] - p[1] >= 25 and p[0] - p[2] >= 25
    n = count_region(chaos, 0, 200, W, H - 200, ring)
    check("chaos_banner", "meteor-ring", n >= 25, "%d red-ring px in the world band" % n)

    # ---- editor (a: open; b: after a real row purchase) --------------------------
    left_w = min(460.0, W * 0.42)
    right_x = 24.0 + left_w + 16.0
    right_w = W - right_x - 24.0
    left_h = H - 70.0 - 24.0
    dark = lambda p: min(p) >= 170
    rows_ok = 0
    for i in range(10):
        y0 = 70.0 + 52.0 + i * 44.0
        n = count_region(ed_a, right_x + 12, y0 + 4, right_x + right_w - 12, y0 + 24, dark)
        check("editor", "row-%d" % (i + 1), n >= 25, "%d name-text px in row band %d" % (n, i + 1))
        if n >= 25:
            rows_ok += 1
    header = lambda p: p[2] >= 200 and p[1] >= 170 and p[0] <= 190
    n = count_region(ed_a, right_x, 84, right_x + right_w, 106, header)
    check("editor", "parts-header", n >= 40, "%d CELL PARTS header px" % n)
    corner = px(ed_a, 8, 8)
    check("editor", "overlay-wash", max(corner) <= 60, str(corner))
    fy = 70.0 + left_h - 52.0
    diff = 0
    for y in range(int(fy) - 6, int(fy) + 34):
        for x in range(int(right_x) + 16, int(right_x) + 250):
            a = px(ed_a, x, y)
            b = px(ed_b, x, y)
            if max(abs(a[k] - b[k]) for k in range(3)) >= 10:
                diff += 1
    check("editor", "dna-display-updates", diff >= 40,
          "%d footer px changed after the real purchase click" % diff)

    # ---- death -------------------------------------------------------------------
    oks = 0
    samples = []
    for fy2 in (0.30, 0.70):
        for fx in (0.15, 0.35, 0.65, 0.85):
            p = patch_mean(death, W * fx, H * fy2)
            samples.append(tuple(round(v) for v in p))
            if p[0] >= p[1] + 4 and p[0] >= 20:
                oks += 1
    check("death", "red-wash", oks >= 6, "%d/8 samples lifted red: %s" % (oks, samples))
    rebirth = lambda p: near(p, (255, 154, 138), 45)
    n = count_region(death, W / 2 - 260, H / 2 - 45, W / 2 + 260, H / 2 + 15, rebirth)
    check("death", "rebirth-text", n >= 150, "%d REBIRTH IS PAINFUL px" % n)
    c = px(death, cx, cy)
    check("death", "player-hidden", not (c[1] - max(c[0], c[2]) >= 30), str(c))

    # ---- transition card -----------------------------------------------------------
    ok_corners = True
    for (x, y) in ((3, 3), (W - 4, H - 4)):
        p = px(card, x, y)
        if not near(p, (2, 3, 10), 2):
            ok_corners = False
            check("card", "veil", False, "corner (%d,%d) = %s want ~(2,3,10)" % (x, y, str(p)))
    if ok_corners:
        check("card", "veil", True, "corners at (2,3,10) ±2")
    title = lambda p: near(p, (191, 230, 255), 45)
    n = count_region(card, W / 2 - 300, H / 2 - 60, W / 2 + 300, H / 2 - 5, title)
    check("card", "card-title", n >= 300, "%d title px" % n)

    print("---")
    if record_path:
        with open(record_path, "w") as f:
            json.dump({"viewport": [W, H], "asserts": record}, f, indent=1)
        print("record written to %s" % record_path)
    if failures:
        print("VISUAL_SUITE_FAIL: %s" % ", ".join(failures))
        return 1
    print("VISUAL_SUITE_ALL_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
