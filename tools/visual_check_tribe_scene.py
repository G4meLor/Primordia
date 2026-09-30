#!/usr/bin/env python3
"""Structural pixel asserts for the tribe-STAGE scene capture (M4 task 4).

No golden images — llvmpipe-deterministic STRUCTURAL tolerances (font/AA may
shift across mesa versions). Anchors come from the harness's probes.json
(computed from the rig metrics + the live camera — the TS manual transform
inverse — plus the stage's own UI geometry), passed in as floats.

Moments and their assert families (TS TribeStage.ts refs by family):
  VILLAGE  — the day village (TribeStage.ts:1176-1423): green lawn band,
             hut wall/roof warm masses at the anchors, the great totem pole
             mid-build, the stockpile panel (dark + light text), both build
             buttons lit (hut green fill, totem amber fill), the totem label
  RAID     — the raid through the REAL raid clock (TS:327-339 → 561-584):
             the danger banner card (dark panel + warm #ff9a5a title), two
             hue-5 war-party bodies (red-dominant) at the anchors
  NIGHT    — night dayPhase 0.7 in the (0.55, 0.95) isNight window
             (TS:1380-1383): the flat rgba(10,10,40,0.4) overlay dims the
             frame vs VILLAGE, three festival campfire glows
             (rgba(255,140,40,0.65) r 34) at the anchors, and the backdrop
             stars show as neutral bright dots vs the day twin
  DEATH    — the death card (TS:1389-1393): the rgba(60,0,10,~0.48) veil
             dims the frame vs VILLAGE, THE CHIEF HAS FALLEN title pixels,
             the chief body GONE from its green probe (fade > 0.4 hides it)
  ZSORT    — Ruling 14 class: the red tribesman at z 100 draws OVER the
             green chief at z 60 — red at the tribesman's anchor, green at
             the chief's, and red wins the overlap scan down the tribesman's
             column across the chief's torso zone
  TOAST    — the toast-inset pair (hud toast_inset 190, TS:154): the toast
             panel appears in the band vh−30−190±, light text pixels, and
             the gap band between the toast and the stockpile panel stays
             twin-identical (the inset keeps the bottom-left UI clear)

Usage: visual_check_tribe_scene.py PROBES_JSON PNG... ; exit 0 = all held.
PNG order: village_day raid night death zsort toast_before toast.
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


def grid_mean(im, side=6):
    W, H = im.size
    tot = 0.0
    n = 0
    for fy in range(1, side + 1):
        for fx in range(1, side + 1):
            tot += lum(patch_mean(im, W * fx / (side + 1.0), H * fy / (side + 1.0), 6))
            n += 1
    return tot / n


def main():
    with open(sys.argv[1]) as f:
        P = json.load(f)
    (village, raid, night, death, zsort, toast_before, toast) = [
        Image.open(p).convert("RGB") for p in sys.argv[2:9]]
    W, H = village.size
    failures = []

    def check(name, cond, detail):
        print(("OK  " if cond else "FAIL") + " %s %s" % (name, detail))
        if not cond:
            failures.append(name)

    vw = float(P["vw"])
    vh = float(P["vh"])

    # ---- VILLAGE — the day village (lawn, hut, totem, panels, buttons) -------
    # (a) lawn band — green-dominant across the middle third below the horizon
    for frac in (0.55, 0.62):
        y = int(H * frac)
        n = ok = 0
        for xx in range(int(W / 3), int(2 * W / 3), 4):
            p = px(village, xx, y)
            n += 1
            if p[1] > p[0] + 12 and p[1] > p[2] + 12:
                ok += 1
        check("village-lawn-%d%%" % int(frac * 100), ok >= n * 0.55,
              "%d/%d green-dominant" % (ok, n))
    v = P["village"]
    # (b) hut wall — warm tan mass at the wall anchor (hsl(30,0.32,0.4))
    c = patch_mean(village, v["hut_wall"][0], v["hut_wall"][1], 5)
    check("village-hut-wall", c[0] - c[2] >= 25 and c[0] >= 100, str(c))
    # (c) hut roof — darker warm mass at the roof anchor (hsl(18,0.42,0.34))
    c = patch_mean(village, v["hut_roof"][0], v["hut_roof"][1], 5)
    check("village-hut-roof", c[0] - c[2] >= 30 and c[0] >= 90, str(c))
    # (d) great totem — warm pole mass at the progress-scaled anchor
    # (hsl(40,0.4,0.4), rect 20 x 90·p)
    c = patch_mean(village, v["totem_pole"][0], v["totem_pole"][1], 5)
    check("village-totem", c[0] - c[2] >= 40 and c[0] >= 110, str(c))
    # (e) stockpile panel — dark panel + light text (TS:1403-1405)
    sx0, sy0, sx1, sy1 = v["stockpile"]
    c = patch_mean(village, (sx0 + sx1) / 2.0, sy0 + 4, 6)
    check("village-stockpile-panel", lum(c) < 80, "lum %.0f" % lum(c))
    n = 0
    for yy in range(int(sy0), int(sy1)):
        for xx in range(int(sx0), int(sx1), 2):
            if lum(px(village, xx, yy)) >= 150:
                n += 1
    check("village-stockpile-text", n >= 20, "%d light text px" % n)
    # (f) hut button lit — green fill (rgba(60,120,80,0.9), TS:1413)
    bx0, by0, bx1, by1 = v["hut_btn"]
    c = patch_mean(village, (bx0 + bx1) / 2.0, (by0 + by1) / 2.0, 8)
    check("village-hut-btn", c[1] > c[0] and c[1] > c[2] and lum(c) < 140, str(c))
    # (g) totem button lit — amber fill (rgba(160,120,40,0.95), TS:1421)
    tx0, ty0, tx1, ty1 = v["totem_btn"]
    c = patch_mean(village, (tx0 + tx1) / 2.0, (ty0 + ty1) / 2.0, 8)
    check("village-totem-btn", c[0] > c[2] + 40 and c[1] > c[2] + 20, str(c))
    # (h) totem label — yellow pixels near the label anchor (#ffe08a)
    n = 0
    for yy in range(int(v["totem_label"][1]) - 12, int(v["totem_label"][1]) + 12):
        for xx in range(int(v["totem_label"][0]) - 60, int(v["totem_label"][0]) + 60, 2):
            p = px(village, xx, yy)
            if p[0] >= 180 and p[1] >= 160 and p[2] <= 160:
                n += 1
    check("village-totem-label", n >= 4, "%d yellow label px" % n)

    # ---- RAID — the real-clock raid (banner + war party) ----------------------
    r = P["raid"]
    bx0, by0, bx1, by1 = r["banner_panel"]
    c = patch_mean(raid, (bx0 + bx1) / 2.0, by1 - 8, 8)
    sky = patch_mean(raid, (bx0 + bx1) / 2.0, max(8, by0 - 26), 8)
    check("raid-banner-panel", lum(c) < 90 and lum(sky) >= lum(c) + 15,
          "panel lum %.0f < sky %.0f + 15" % (lum(c), lum(sky)))
    n = 0
    for yy in range(int(r["banner_title"][0]), int(r["banner_title"][1])):
        for xx in range(int(bx0), int(bx1), 2):
            p = px(raid, xx, yy)
            if p[0] - p[2] >= 60 and p[0] >= 150:
                n += 1
    check("raid-banner-title", n >= 12, "%d warm title px" % n)
    for i, (wxx, wyy) in enumerate(r["bodies"][:2]):
        c = patch_mean(raid, wxx, wyy, 6)
        check("raid-warrior-%s" % chr(97 + i), c[0] - c[1] >= 30 and c[0] >= 100, str(c))

    # ---- NIGHT — flat overlay + campfire glows + stars ------------------------
    gm_day = grid_mean(village)
    gm_night = grid_mean(night)
    check("night-dim", gm_night < gm_day - 12,
          "grid %.1f vs day %.1f - 12" % (gm_night, gm_day))
    for i, (fxx, fyy) in enumerate(P["night"]["fires"][:3]):
        c = patch_mean(night, fxx, fyy, 6)
        # the flat rgba(10,10,40,0.4) overlay sits ON the glow — the warm
        # center reads ~ (90, 65, 40) under it; warm dominance is the signal
        check("night-fire-%s" % chr(97 + i), c[0] - c[2] >= 35 and c[0] >= 70, str(c))
    n = 0
    for yy in range(0, H, 2):
        for xx in range(0, W, 2):
            a2 = px(night, xx, yy)
            b2 = px(village, xx, yy)
            if lum(a2) >= 100 and lum(a2) - lum(b2) >= 15 and a2[2] >= a2[1] - 6:
                n += 1
    check("night-stars", n >= 6, "%d star px vs day" % n)

    # ---- DEATH — the card + the chief gone -------------------------------------
    d = P["death"]
    gm_death = grid_mean(death)
    check("death-dim", gm_death < gm_day - 8,
          "grid %.1f vs day %.1f - 8" % (gm_death, gm_day))
    ty0, ty1 = d["title_band"]
    n = 0
    for yy in range(int(ty0), int(ty1)):
        for xx in range(int(W * 0.2), int(W * 0.8), 2):
            p = px(death, xx, yy)
            if p[0] - p[1] >= 25 and p[0] >= 140:
                n += 1
    check("death-title", n >= 10, "%d warm title px" % n)
    c = px(death, d["chief_body"][0], d["chief_body"][1])
    check("death-chief-gone", not (c[1] - c[0] >= 25 and c[1] >= 130),
          "no green body at the probe %s" % (c,))

    # ---- ZSORT — the tribesman at z 100 over the chief at z 60 -----------------
    z = P["zsort"]
    c = patch_mean(zsort, z["tm_body"][0], z["tm_body"][1], 5)
    check("zsort-tribesman-body", c[0] - c[1] >= 60 and c[0] >= 110, str(c))
    c = patch_mean(zsort, z["chief_body"][0], z["chief_body"][1], 5)
    check("zsort-chief-visible", c[1] - c[0] >= 25 and c[1] >= 110, str(c))
    # the overlap: down the tribesman's column across the chief's torso zone,
    # RED must win (the z-100 draw order) — count red vs green pixels in the box
    sx0, sy0, sx1, sy1 = z["scan"]
    red = green = 0
    for yy in range(int(sy0), int(sy1)):
        for xx in range(int(sx0), int(sx1)):
            p = px(zsort, xx, yy)
            if p[0] - p[1] >= 50 and p[0] >= 110:
                red += 1
            elif p[1] - p[0] >= 25 and p[1] >= 110:
                green += 1
    check("zsort-overlap", red >= 20 and red > green,
          "red %d vs green %d in the overlap box" % (red, green))

    # ---- TOAST — the inset pair ------------------------------------------------
    t = P["toast"]
    diff = box_diff(toast_before, toast, t["band"])
    check("toast-appears", diff >= 8.0, "band diff %.2f" % diff)
    # the toast panel's rows sit in the pinned band (vh−30−190 ± panel). The
    # vignette darkens the corner rows of BOTH twins — a row counts only when
    # the toast twin is meaningfully darker than the no-toast twin there.
    r0, r1 = t["rows"]
    toast_rows = []
    for yy in range(int(r0) - 24, int(r1) + 25):
        a_mean = 0.0
        b_mean = 0.0
        n = 0
        for xx in range(int(t["band"][0]), int(t["band"][2]), 2):
            a_mean += lum(px(toast, xx, yy))
            b_mean += lum(px(toast_before, xx, yy))
            n += 1
        if n > 0 and (b_mean - a_mean) / n >= 12.0:
            toast_rows.append(yy)
    ok_center = len(toast_rows) > 0 \
        and toast_rows[0] >= int(t["band"][1]) - 4 \
        and toast_rows[-1] <= int(t["band"][3]) + 4
    check("toast-position", ok_center,
          "toast rows %s..%s in band %s..%s" % (
              toast_rows[0] if toast_rows else -1, toast_rows[-1] if toast_rows else -1,
              int(t["band"][1]), int(t["band"][3])))
    n = 0
    for yy in range(int(t["text_band"][0]), int(t["text_band"][1])):
        for xx in range(int(t["band"][0]), int(t["band"][2]), 2):
            if lum(px(toast, xx, yy)) >= 150:
                n += 1
    check("toast-text", n >= 8, "%d light text px" % n)
    # the gap band between the toast and the stockpile panel stays twin-clean —
    # the 190 inset keeps the toast clear of the bottom-left UI
    gap = box_diff(toast_before, toast, t["gap_band"])
    check("toast-inset-gap", gap <= 2.0, "gap band diff %.2f" % gap)

    print("---")
    if failures:
        print("VISUAL_CHECK_FAIL: %s" % ", ".join(failures))
        return 1
    print("VISUAL_CHECK_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
