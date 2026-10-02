#!/usr/bin/env python3
"""Structural pixel asserts for the civ-STAGE scene capture (M5 task 3).

No golden images — llvmpipe-deterministic STRUCTURAL tolerances (font/AA may
shift across mesa versions). Anchors come from the harness's probes.json
(computed from the stage's own geometry seams + the live sim state), passed
in as floats.

Moments and their assert families (TS CivStage.ts refs by family):
  PLANET   — the planet-day render (CivStage.ts:530-562): the #02030a space
             base + twinkling stars, the ocean disc with the OFFSET light
             center (brighter top-left vs bottom-right), ≥ 2 of 3 continent
             blobs green-dominant at their seam anchors, the disc radius band
             (ocean inside vs space outside) and the atmosphere rim's falloff
  CITIES   — the 4 city discs (TS:589-614): owner-colored (capital green,
             r1 red / r2 purple / r3 teal), name labels, the '👑 yours'
             status, influence bars (green full at 100, green at 30, warm
             short at -60) and the hp bars
  ARMADA   — the armada through a REAL Digit1 press (TS:570-587 + the launch
             toast): the red ship disc + its glow at the live anchor, the
             dashed [4,6] trail (dash-on vs gap samples along the route vs
             the pre-launch twin), the toast in the inset-150 band
  SLIDERS  — the sliders panel (TS:628-649) with REAL key-press fixtures:
             the dark panel + the blue title, the full mil bar (red run ≥
             140), the 3px-floor empty culture/econ bars, and the full:empty
             ratio pin (≥ 15×)
  PORTRAIT — the ruler portrait (TS:617-626): creature pixels INSIDE the clip
             rect (the group clip), NONE in the panel ring outside it, the
             dark panel corner
  VICTORY  — the victory shimmer (TS:655-658): 'THE PLANET IS UNITED' gold
             pixels in the band vs their absence in the pre-victory twin,
             and the 3 former-rival discs turned green

Usage: visual_check_civ_scene.py PROBES_JSON PNG... ; exit 0 = all held.
PNG order: planet_day cities armada sliders portrait victory.
"""
import json
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


def median(v):
    s = sorted(v)
    return s[len(s) // 2]


def box_diff(im_a, im_b, box):
    """Mean abs per-channel diff over a box."""
    x0, y0, x1, y1 = box
    total = 0
    n = 0
    for yy in range(int(y0), int(y1) + 1):
        for xx in range(int(x0), int(x1) + 1):
            a = px(im_a, xx, yy)
            b = px(im_b, xx, yy)
            total += sum(abs(a[k] - b[k]) for k in range(3)) / 3.0
            n += 1
    return total / max(1, n)


def count_in(im, box, pred):
    x0, y0, x1, y1 = box
    n = 0
    for yy in range(int(y0), int(y1) + 1):
        for xx in range(int(x0), int(x1) + 1):
            if 0 <= xx < im.size[0] and 0 <= yy < im.size[1] and pred(px(im, xx, yy)):
                n += 1
    return n


def run_along(im_a, im_b, p0, p1, n=20):
    """Sample n points from t=0.12..0.88 along p0→p1; per-point red deltas
    vs the twin (the dash cadence lives in the deltas, not the absolutes)."""
    deltas = []
    for k in range(n):
        t = 0.12 + (0.88 - 0.12) * k / float(n - 1)
        x = p0[0] + (p1[0] - p0[0]) * t
        y = p0[1] + (p1[1] - p0[1]) * t
        a = px(im_a, x, y)
        b = px(im_b, x, y)
        deltas.append(a[0] - b[0])
    return deltas


def main():
    with open(sys.argv[1]) as f:
        P = json.load(f)
    planet_day, cities, armada, sliders, portrait, victory = [
        Image.open(p).convert("RGB") for p in sys.argv[2:8]]
    W, H = planet_day.size
    failures = []

    def check(name, cond, detail):
        print(("OK  " if cond else "FAIL") + " %s %s" % (name, detail))
        if not cond:
            failures.append(name)

    vw = float(P["vw"])
    vh = float(P["vh"])

    # ---- PLANET — space base, stars, ocean, continents, rim -------------------
    pl = P["planet"]
    c = patch_mean(planet_day, pl["corner"][0], pl["corner"][1], 6)
    check("planet-space-base", lum(c) < 40, "corner lum %.0f" % lum(c))
    box = pl["stars_box"]
    n = count_in(planet_day, box, lambda p: lum(p) >= 90)
    check("planet-stars", n >= 3, "%d star px in the corner box" % n)
    a = patch_mean(planet_day, pl["ocean_a"][0], pl["ocean_a"][1], 6)
    check("planet-ocean-blue", a[2] - a[0] >= 20 and a[2] >= 80, str(a))
    b = patch_mean(planet_day, pl["ocean_b"][0], pl["ocean_b"][1], 6)
    check("planet-ocean-gradient", lum(a) >= lum(b) + 20,
          "light-center %s vs dark-rim %s" % (str(a), str(b)))
    hits = 0
    for cc in pl["cont"]:
        c2 = patch_mean(planet_day, cc[0], cc[1], 8)
        if c2[1] - c2[2] >= 10 and c2[1] >= 55:
            hits += 1
    check("planet-continents", hits >= 2, "%d/3 continent blobs green" % hits)
    c = patch_mean(planet_day, pl["edge_in"][0], pl["edge_in"][1], 4)
    # the rim ocean IS the gradient's dark stop (hsl(220,0.55,0.16) — lum ≈ 32
    # by construction); at 0.93pr the fan + rim glow lands ≈ 38. The assert's
    # job is the disc band contrast: blue-dominant inside vs space outside
    # (lum ≈ 6) — the luminance floor only has to clear "not space".
    check("planet-disc-band", c[2] - c[0] >= 20 and lum(c) >= 28, str(c))
    c = patch_mean(planet_day, pl["edge_out"][0], pl["edge_out"][1], 4)
    check("planet-space-outside", lum(c) < 45, "outside lum %.0f" % lum(c))
    # the rim glow's falloff direction (median along the tangent segments —
    # robust to stray star pixels)
    def seg_blue(im, seg):
        p0, p1 = seg
        vals = []
        steps = 40
        for k in range(steps + 1):
            t = k / float(steps)
            vals.append(px(im, p0[0] + (p1[0] - p0[0]) * t,
                           p0[1] + (p1[1] - p0[1]) * t)[2])
        return median(vals)
    bin_ = seg_blue(planet_day, pl["rim_in_seg"])
    bout = seg_blue(planet_day, pl["rim_out_seg"])
    check("planet-rim-glow", bin_ >= bout + 2,
          "median b in %.0f vs out %.0f" % (bin_, bout))

    # ---- CITIES — owner-colored discs, labels, bars ----------------------------
    spots = P["cities"]["spots"]

    def dom_ok(c3, key):
        if key == "green":
            return c3[1] - c3[0] >= 25 and c3[1] >= 120
        if key == "red":
            return c3[0] - c3[1] >= 60 and c3[0] >= 150
        if key == "purple":
            return c3[0] - c3[1] >= 20 and c3[2] - c3[1] >= 60
        return c3[1] - c3[0] >= 60 and c3[1] - c3[2] >= 20  # teal

    for i, sp in enumerate(spots):
        c = patch_mean(cities, sp["disc"][0], sp["disc"][1], 3)
        check("cities-disc-%d-%s" % (i, sp["col"]), dom_ok(c, sp["col"]), str(c))
    cap = spots[0]
    x0, y0, x1, y1 = cap["inf_band"]
    n = 0
    for xx in range(int(x0), int(x1) + 1):
        p = px(cities, xx, (y0 + y1) / 2.0)
        if p[1] - p[0] >= 30 and p[1] >= 130:
            n += 1
    check("cities-cap-inf-full", n >= 45, "%d green px on the 64px band" % n)
    r2 = spots[2]
    x0, y0, x1, y1 = r2["inf_band"]
    n = 0
    for xx in range(int(x0), int(x1) + 1):
        p = px(cities, xx, (y0 + y1) / 2.0)
        if p[1] - p[0] >= 30 and p[1] >= 130:
            n += 1
    check("cities-r2-inf-green", n >= 30, "%d green px at influence 30" % n)
    r1 = spots[1]
    x0, y0, x1, y1 = r1["inf_band"]
    n = 0
    for xx in range(int(x0), int(x1) + 1):
        p = px(cities, xx, (y0 + y1) / 2.0)
        if p[0] - p[1] >= 30 and p[0] >= 150:
            n += 1
    check("cities-r1-inf-warm", n >= 8, "%d warm px at influence -60" % n)
    x0, y0, x1, y1 = cap["hp_band"]
    n = 0
    for xx in range(int(x0), int(x1) + 1):
        p = px(cities, xx, (y0 + y1) / 2.0)
        if p[2] - p[0] >= 40 and p[2] >= 150:
            n += 1
    check("cities-cap-hp", n >= 40, "%d blue px on the hp band" % n)
    nb = [cap["name"][0] - 45, cap["name"][1] - 8, cap["name"][0] + 45, cap["name"][1] + 8]
    n = count_in(cities, nb, lambda p: lum(p) >= 150)
    check("cities-name-label", n >= 4, "%d light label px" % n)
    sb = [cap["status"][0] - 30, cap["status"][1] - 6, cap["status"][0] + 30, cap["status"][1] + 6]
    n = count_in(cities, sb, lambda p: lum(p) >= 140)
    check("cities-status-label", n >= 2, "%d status px" % n)

    # ---- ARMADA — ship, glow, dashed trail, launch toast -----------------------
    ar = P["armada"]
    c = patch_mean(armada, ar["ship"][0], ar["ship"][1], 2)
    check("armada-ship", c[0] >= 140 and c[0] - c[2] >= 40, str(c))
    deltas = run_along(armada, cities, ar["route"][0], ar["route"][1])
    on = sum(1 for d in deltas if d >= 12)
    gap = sum(1 for d in deltas if d <= 4)
    check("armada-trail-dashes", on >= 4, "%d/20 dash-on samples" % on)
    check("armada-trail-gaps", gap >= 4, "%d/20 gap samples (the [4,6] cadence)" % gap)
    tb = ar["toast_band"]
    diff = box_diff(cities, armada, tb)
    check("armada-toast-appears", diff >= 6.0, "band diff %.2f" % diff)
    n = count_in(armada, tb, lambda p: lum(p) >= 150)
    check("armada-toast-text", n >= 8, "%d light toast px" % n)

    # ---- SLIDERS — panel, title, full vs floor bars -----------------------------
    sl = P["sliders"]
    pn = sl["panel"]
    c = patch_mean(sliders, (pn[0] + pn[2]) / 2.0, pn[1] + 6, 6)
    check("sliders-panel", lum(c) < 70, "panel lum %.0f" % lum(c))
    tb2 = [sl["title"][0] - 80, sl["title"][1] - 8, sl["title"][0] + 80, sl["title"][1] + 8]
    n = count_in(sliders, tb2, lambda p: p[2] - p[0] >= 30 and p[2] >= 150)
    check("sliders-title", n >= 3, "%d blue title px" % n)
    runs = []
    # dominance predicates, not absolute color boxes: the vignette (TS:660 —
    # drawn last over the whole stage) multiplies the panel corner by ~0.8,
    # which walks an absolute ±40 box off the fill colors while the hues stay
    # put (the value-label assert below is dominance-based for the same
    # reason). Track/panel/dark blues fail every predicate by construction.
    def red_dom(p):
        return p[0] - p[1] >= 45 and p[0] - p[2] >= 45
    def purple_dom(p):
        return p[2] - p[1] >= 50 and p[2] - p[0] >= 25
    def teal_dom(p):
        return p[1] - p[0] >= 55 and p[1] - p[2] >= 15
    doms = [red_dom, purple_dom, teal_dom]
    for bar, dom in zip(sl["bars"], doms):
        run = best = 0
        for xx in range(int(bar["x0"]), int(bar["x0"]) + 161):
            if dom(px(sliders, xx, bar["row"])):
                run += 1
                best = max(best, run)
            else:
                run = 0
        runs.append(best)
    check("sliders-mil-full", runs[0] >= 140, "red run %d px (want ~160)" % runs[0])
    check("sliders-culture-floor", 1 <= runs[1] <= 8, "purple run %d px (the 3px floor)" % runs[1])
    check("sliders-econ-floor", 1 <= runs[2] <= 8, "teal run %d px (the 3px floor)" % runs[2])
    check("sliders-ratio-pin", runs[0] >= 15 * max(1, runs[1]),
          "full %d vs floor %d (≥15×)" % (runs[0], runs[1]))
    vb = [sl["bars"][0]["val"][0] - 20, sl["bars"][0]["val"][1] - 8,
          sl["bars"][0]["val"][0] + 8, sl["bars"][0]["val"][1] + 8]
    n = count_in(sliders, vb, lambda p: p[0] - p[1] >= 40 and p[0] >= 150)
    check("sliders-value-label", n >= 2, "%d red value px at the mil row" % n)

    # ---- PORTRAIT — the clip rect holds the creature ----------------------------
    po = P["portrait"]
    clip = po["clip"]
    n = count_in(portrait, clip, lambda p: p[1] - p[0] >= 20 and p[1] >= 90)
    check("portrait-creature-in-clip", n >= 25, "%d green px inside the clip" % n)
    c = patch_mean(portrait, po["body"][0], po["body"][1], 4)
    check("portrait-body", c[1] - c[0] >= 20 and c[1] >= 90, str(c))
    # the panel ring OUTSIDE the clip rect: 4px inset left/right/top + the
    # bottom strip — no creature pixels may leak there
    panel = po["panel"]
    ring = [
        [panel[0], panel[1], clip[0], panel[3]],          # left strip
        [clip[2], panel[1], panel[2], panel[3]],          # right strip
        [panel[0], panel[1], panel[2], clip[1]],          # top strip
        [panel[0], clip[3], panel[2], panel[3]],          # bottom strip
    ]
    n = sum(count_in(portrait, rg, lambda p: p[1] - p[0] >= 20 and p[1] >= 90) for rg in ring)
    check("portrait-clip-holds", n <= 2, "%d green px in the exclusion ring" % n)
    c = patch_mean(portrait, po["corner"][0], po["corner"][1], 3)
    check("portrait-panel-dark", lum(c) < 55, "corner lum %.0f" % lum(c))

    # ---- VICTORY — the shimmer + the green board --------------------------------
    vi = P["victory"]
    band = vi["band"]
    n = count_in(victory, band, lambda p: p[0] >= 200 and p[1] >= 160 and p[2] <= 160)
    check("victory-shimmer", n >= 12, "%d gold title px" % n)
    n = count_in(planet_day, band, lambda p: p[0] >= 200 and p[1] >= 160 and p[2] <= 160)
    check("victory-absent-pre", n <= 2, "%d gold px in the pre-victory twin" % n)
    diff = box_diff(planet_day, victory, band)
    check("victory-band-diff", diff >= 8.0, "band diff %.2f" % diff)
    for i, sp in enumerate(vi["spots"]):
        c = patch_mean(victory, sp[0], sp[1], 3)
        check("victory-disc-%d-green" % i, c[1] - c[0] >= 25 and c[1] >= 120, str(c))

    print("---")
    if failures:
        print("VISUAL_CHECK_FAIL: %s" % ", ".join(failures))
        return 1
    print("VISUAL_CHECK_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
