#!/usr/bin/env python3
"""Structural pixel asserts for the creature-STAGE scene capture (tasks 7+10).

No golden images — llvmpipe-deterministic STRUCTURAL tolerances (font/AA may
shift across mesa versions). Anchors come from the harness's probes.json
(computed from the rig metrics + the live camera — the TS manual transform
inverse — plus the scene's own UI geometry), passed in as floats.

Moments and their assert families (TS CreatureStage.ts refs by family):
  ARRIVAL  — the shore arrival banner card (hud.ts:314-319 kind colors +
             CreatureStage.ts:329-333 stage banner): dark stage-panel band
             over the sky, blue #7fd4ff title pixels, light subtitle pixels,
             the 560px panel width
  MEADOW   — the day meadow, full creature mid-gait (rig gaitPhase A vs
             A+pi/2 pair): green body at the rig anchor, the FEET box moves
             between the pair (leg stride), the TORSO box is a determinism
             twin (speed01 0 → bob 0), the body out-greens the lawn band
  DAY      — lawn band present, sky corner bluish, vignette darkens the
             corner, HP bar panel + fill at the TS inset (vh-108)  [task 7]
  ZSORT    — determinism twin of DAY + Ruling 14: the ent at z 100 draws
             ABOVE the player at z 50 — red wins the overlap, the player's
             tail end stays visible left of the ent                    [task 7]
  CHARM    — the charm minigame UI mid-hits (CreatureStage.ts:1493-1508):
             dark beat-bar panel, the green hit zone (0.35−hits·0.05 wide),
             the white marker at the pinned marker x, the yellow title
  NIGHT    — night raid moment, dayPhase 0.7 in the (0.55, 0.95) isNight
             window (TS:1318, 1460-1477): the rgba(10,10,40,~0.4) overlay
             dims the frame vs DAY, the 20 deterministic fireflies show as
             yellow-green dots, and the 60 deterministic stars show as
             neutral bright dots in the upper sky (backdrop.ts:122-128)
  DEATH    — the death card (TS:1510-1516): the rgba(60,0,10,~0.4) overlay
             dims the frame vs DAY, THE ISLAND RECLAIMS YOU title pixels,
             the light sub line, and the player body GONE from its green
             probe (deathFade > 0.4 hides the player)
  VOLCANO  — the aftermath through the real scheduler warn→apply
             (creatureEvents.ts volcano + CreatureStage.ts:1374-1384): two
             anchored lava glows (rgba(255,120,40,0.85) over the lawn), a
             frame-wide warm mass, and the smoke plume band above a hazard
  STAMPEDE — the herd through the real scheduler (CreatureStage.ts:1155-1169
             + the painter's TS:77-86 ground shadow): two herd bodies off
             the lawn-row median, and dark ground-shadow pixels under a herd
             ent
  EDITOR   — the editor open in creature (editor.gd draw): the rgba(3,6,16,
             0.88) backdrop dims the frame vs the pre-editor twin, the dark
             left panel, the blue DONE button, the light-blue DNA footer

Usage: visual_check_creature_scene.py PROBES_JSON PNG... ; exit 0 = all held.
PNG order: arrival meadow_a meadow_b day zsort charm night death volcano
stampede editor_before editor.
"""
import json
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


def box_diff(im_a, im_b, box):
    """Mean abs per-channel diff over a box, + the max single-channel diff."""
    x0, y0, x1, y1 = box
    total = 0
    n = 0
    mx = 0.0
    for yy in range(int(y0), int(y1) + 1):
        for xx in range(int(x0), int(x1) + 1):
            a = px(im_a, xx, yy)
            b = px(im_b, xx, yy)
            d = [abs(a[k] - b[k]) for k in range(3)]
            total += sum(d) / 3.0
            mx = max(mx, max(d))
            n += 1
    return total / max(1, n), mx


def grid_mean(im, side=6):
    W, H = im.size
    tot = 0.0
    n = 0
    for fy in range(1, side + 1):
        for fx in range(1, side + 1):
            tot += lum(patch_mean(im, W * fx / (side + 1.0), H * fy / (side + 1.0), 6))
            n += 1
    return tot / n


def row_median_lum(im, y, x0, x1, step=8):
    vals = []
    for xx in range(int(x0), int(x1), step):
        vals.append(lum(px(im, xx, y)))
    vals.sort()
    return vals[len(vals) // 2] if vals else 0.0


def main():
    with open(sys.argv[1]) as f:
        P = json.load(f)
    (arrival, meadow_a, meadow_b, day, zsort, charm, night, death, volcano,
     stampede, editor_before, editor) = [Image.open(p).convert("RGB") for p in sys.argv[2:14]]
    W, H = day.size
    failures = []

    def check(name, cond, detail):
        print(("OK  " if cond else "FAIL") + " %s %s" % (name, detail))
        if not cond:
            failures.append(name)

    vw = float(P["vw"])
    vh = float(P["vh"])

    # ---- ARRIVAL — the shore banner card (panel 560px at y 70..144) ----------
    # the dark probe sits in the bottom-left corner and the width run on the
    # top-padding row — the centered title/sub glyphs cross the middle
    a = P["arrival"]
    px0, py0, px1, py1 = a["panel"]
    c = patch_mean(arrival, px0 + 45, py1 - 8, 6)
    sky = patch_mean(arrival, (px0 + px1) / 2.0, max(8, py0 - 26), 6)
    check("arrival-panel", lum(c) < 80 and lum(sky) >= lum(c) + 20,
          "panel lum %.0f < sky %.0f + 20" % (lum(c), lum(sky)))
    n = 0
    for yy in range(int(a["title"][0]), int(a["title"][1])):
        for xx in range(int(px0), int(px1), 2):
            p = px(arrival, xx, yy)
            if p[2] - p[0] >= 30 and p[2] >= 130:
                n += 1
    check("arrival-title", n >= 12, "%d blue title px" % n)
    n = 0
    for yy in range(int(a["sub"][0]), int(a["sub"][1])):
        for xx in range(int(px0), int(px1), 2):
            if lum(px(arrival, xx, yy)) >= 165:
                n += 1
    check("arrival-sub", n >= 10, "%d light sub px" % n)
    ypad = int(py0) + 5
    run = 0
    best = 0
    for xx in range(int(px0) - 30, int(px1) + 30):
        if lum(px(arrival, xx, ypad)) < 90:
            run += 1
            best = max(best, run)
        else:
            run = 0
    check("arrival-width", best >= 0.85 * (px1 - px0),
          "dark run %d of %d" % (best, px1 - px0))

    # ---- MEADOW — full creature mid-gait (gait pair) --------------------------
    m = P["meadow"]
    bx, by = m["body"]
    c = px(meadow_a, bx, by)
    lawn = px(meadow_a, bx + 90, m["feet"][1] + 24)
    check("meadow-body", c[1] - c[0] >= 25 and c[1] >= 130, str(c))
    check("meadow-lawn-contrast", c[1] >= lawn[1] + 25,
          "body g %d vs lawn g %d" % (c[1], lawn[1]))
    mean_d, max_d = box_diff(meadow_a, meadow_b, m["feet_box"])
    check("meadow-gait", max_d >= 25, "feet box max diff %.0f (mean %.2f)" % (max_d, mean_d))
    mean_t, _ = box_diff(meadow_a, meadow_b, m["torso_box"])
    check("meadow-twin", mean_t <= 1.0, "torso twin mean diff %.2f" % mean_t)

    # ---- DAY (task 7, verbatim) ----------------------------------------------
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

    # ---- ZSORT (task 7, verbatim) --------------------------------------------
    # (e) determinism twin — the same frozen commands one frame apart
    diff = 0.0
    n = 0
    for fy in (0.2, 0.4, 0.6, 0.8):
        for fx in (0.2, 0.4, 0.6, 0.8):
            a2 = px(day, W * fx, H * fy)
            b2 = px(zsort, W * fx, H * fy)
            diff += sum(abs(a2[k] - b2[k]) for k in range(3)) / 3.0
            n += 1
    check("day-zsort-twin", diff / n <= 1.0, "mean abs diff %.2f" % (diff / n))
    # (f) RULING 14 — the ent at z 100 draws ABOVE the player at z 50
    z = P["day_zsort"]
    fpx, fpcy = float(z["px"]), float(z["player_cy"])
    fecx, fecy = float(z["ent_cx"]), float(z["ent_cy"])
    c = px(zsort, fpx, fpcy)
    check("zsort-ent-over-player", c[0] - c[1] >= 60 and c[0] >= 110, str(c))
    c = px(zsort, fecx, fecy)
    check("zsort-ent-body", c[0] - c[1] >= 60 and c[0] >= 110, str(c))
    c = px(zsort, float(z["green_x"]), fpcy)
    check("zsort-player-visible", c[1] - c[0] >= 30 and c[1] >= 95, str(c))

    # ---- CHARM — the beat bar mid-hits ---------------------------------------
    cm = P["charm"]
    pcx, pcy = cm["panel"]
    c = patch_mean(charm, pcx, pcy, 8)
    below = patch_mean(charm, pcx, float(cm["zone"][3]) + 26, 8)
    check("charm-panel", lum(c) < 80 and lum(below) >= lum(c) + 20,
          "panel lum %.0f, below %.0f" % (lum(c), lum(below)))
    zx0, zy0, zx1, zy1 = cm["zone"]
    n = 0
    for yy in range(int(zy0) + 2, int(zy1) - 1):
        for xx in range(int(zx0) + 2, int(zx1) - 1, 2):
            p = px(charm, xx, yy)
            if p[1] - p[0] >= 25 and p[1] >= 120:
                n += 1
    check("charm-zone", n >= 30, "%d green zone px" % n)
    mx = float(cm["marker_x"])
    my0, my1 = cm["marker_band"]
    n = 0
    for yy in range(int(my0), int(my1)):
        for xx in range(int(mx) - 3, int(mx) + 4):
            p = px(charm, xx, yy)
            if min(p) >= 195:
                n += 1
    check("charm-marker", n >= 4, "%d white marker px" % n)
    ty0, ty1 = cm["title_band"]
    n = 0
    for yy in range(int(ty0), int(ty1)):
        for xx in range(int(vw / 2 - 130), int(vw / 2 + 130), 2):
            p = px(charm, xx, yy)
            if p[0] >= 170 and p[1] >= 150 and p[2] <= 150:
                n += 1
    check("charm-title", n >= 8, "%d yellow title px" % n)

    # ---- NIGHT — overlay + fireflies + stars (task 7 asserts verbatim) -------
    pd = lum(patch_mean(day, W / 2.0, 200, 20))
    pn = lum(patch_mean(night, W / 2.0, 200, 20))
    check("night-dim", pn < pd - 18, "day %.0f -> night %.0f" % (pd, pn))
    n = 0
    for yy in range(0, H, 2):
        for xx in range(0, W, 2):
            a2 = px(night, xx, yy)
            b2 = px(day, xx, yy)
            if a2[0] - b2[0] >= 15 and a2[1] - b2[1] >= 15 and a2[1] - a2[2] >= 20:
                n += 1
    check("night-fireflies", n >= 8, "%d firefly px" % n)
    # stars: brighter at night, NEUTRAL white (b >= g — the green fireflies
    # the scan above counts are excluded), scattered over the visible sky band
    # (the parallax hills rise high at this pinned camera, so the band reaches
    # the 0.5·vh horizon; the night lawn is darker, never counted). The
    # overlay draws OVER the backdrop stars and most twinkle phases sit low —
    # a mid-twinkle star lands near lum ~107-118.
    n = 0
    for yy in range(0, int(H * 0.5)):
        for xx in range(0, W, 2):
            a2 = px(night, xx, yy)
            b2 = px(day, xx, yy)
            if lum(a2) >= 100 and lum(a2) - lum(b2) >= 15 and a2[2] >= a2[1] - 6:
                n += 1
    check("night-stars", n >= 6, "%d star px" % n)

    # ---- DEATH — the card + the player gone ----------------------------------
    d = P["death"]
    gm_day = grid_mean(day)
    gm_death = grid_mean(death)
    check("death-dim", gm_death < gm_day - 10,
          "grid %.1f vs day %.1f - 10" % (gm_death, gm_day))
    ty0, ty1 = d["title_band"]
    n = 0
    for yy in range(int(ty0), int(ty1)):
        for xx in range(int(W * 0.2), int(W * 0.8), 2):
            p = px(death, xx, yy)
            if p[0] - p[1] >= 25 and p[0] >= 140:
                n += 1
    check("death-title", n >= 10, "%d warm title px" % n)
    sy0, sy1 = d["sub_band"]
    n = 0
    for yy in range(int(sy0), int(sy1)):
        for xx in range(int(W * 0.2), int(W * 0.8), 2):
            p = px(death, xx, yy)
            if lum(p) >= 140 and p[0] >= p[1]:
                n += 1
    check("death-sub", n >= 6, "%d light sub px" % n)
    gx, gy = d["green_probe"]
    c = px(death, gx, gy)
    check("death-player-gone", not (c[1] - c[0] >= 25 and c[1] >= 130),
          "no green body at the probe %s" % (c,))

    # ---- VOLCANO — lava hazards + smoke through the real scheduler -----------
    v = P["volcano"]
    for i, (hxx, hyy) in enumerate(v["hazards"]):
        c = patch_mean(volcano, hxx, hyy, 5)
        check("lava-glow-%s" % chr(97 + i), c[0] - c[2] >= 50 and c[0] >= 140, str(c))
    n = 0
    for yy in range(0, H, 2):
        for xx in range(0, W, 2):
            p = px(volcano, xx, yy)
            if p[0] - p[1] >= 25 and p[0] >= 130:
                n += 1
    check("lava-mass", n >= 400, "%d warm px" % n)
    s = v["smoke"]
    n = 0
    for yy in range(int(s["y0"]), int(s["y1"])):
        for xx in range(int(s["x"] - s["half_w"]), int(s["x"] + s["half_w"])):
            p = px(volcano, xx, yy)
            if p[0] - p[2] >= 25:
                n += 1
    check("volcano-smoke", n >= 6, "%d warm plume px" % n)

    # ---- STAMPEDE — herd bodies + ground shadows ------------------------------
    ents = P["stampede"]["ents"]
    W2, H2 = stampede.size
    for i, (bxx, byy, fxx, fyy) in enumerate(ents[:2]):
        if not (0 <= bxx < W2 and 0 <= byy < H2 and 0 <= fxx < W2 and fyy + 40 < H2):
            check("herd-body-%s" % chr(97 + i), False,
                  "anchor out of bounds (%.0f, %.0f)" % (bxx, byy))
            continue
        row = row_median_lum(stampede, int(fyy + 30), W * 0.08, W * 0.92)
        c = px(stampede, bxx, byy)
        off = sum(abs(c[k] - row) for k in range(3)) / 3.0
        check("herd-body-%s" % chr(97 + i), off >= 40,
              "body %s vs lawn row %.0f (off %.0f)" % (c, row, off))
    bxx, byy, fxx, fyy = ents[0]
    row = row_median_lum(stampede, int(fyy + 30), W * 0.08, W * 0.92)
    n = 0
    for xx in range(int(fxx) - 40, int(fxx) + 41):
        if lum(px(stampede, xx, int(fyy) + 2)) < row - 12:
            n += 1
    check("herd-shadow", n >= 8, "%d shadow px under the lead ent" % n)

    # ---- EDITOR — the overlay dims + panels + blue DONE + DNA footer ----------
    e = P["editor"]
    gm_before = grid_mean(editor_before)
    gm_edit = grid_mean(editor)
    # the 0.88 backdrop's observed drop runs ~50-62 grid points depending on
    # the world behind (the live stampede scene); 35 still separates it from
    # any no-dim frame by a wide margin
    check("editor-dim", gm_edit < gm_before - 35,
          "grid %.1f vs before %.1f - 35" % (gm_edit, gm_before))
    pcx, pcy = e["panel"]
    c = patch_mean(editor, pcx, pcy, 8)
    check("editor-panel", lum(c) < 40, "panel lum %.0f" % lum(c))
    ccx, ccy = e["close"]
    # scan the whole button rect — the centered DONE (E) white glyph washes a
    # center-patch mean out
    n = 0
    for yy in range(int(ccy) - 16, int(ccy) + 17):
        for xx in range(int(ccx) - 50, int(ccx) + 51, 2):
            p = px(editor, xx, yy)
            if p[2] - p[0] >= 60 and p[2] >= 140:
                n += 1
    check("editor-close", n >= 40, "%d blue button px" % n)
    fx0, fy0, fx1, fy1 = e["footer"]
    n = 0
    for yy in range(int(fy0), int(fy1)):
        for xx in range(int(fx0), int(fx1), 2):
            p = px(editor, xx, yy)
            if p[2] - p[0] >= 20 and lum(p) >= 140:
                n += 1
    check("editor-dna", n >= 8, "%d light-blue footer px" % n)

    print("---")
    if failures:
        print("VISUAL_CHECK_FAIL: %s" % ", ".join(failures))
        return 1
    print("VISUAL_CHECK_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
