#!/usr/bin/env python3
"""Structural pixel asserts for the SPACE-stage scene capture (M6 task 5).

No golden images — llvmpipe-deterministic STRUCTURAL tolerances (font/AA may
shift across mesa versions). Anchors come from the harness's probes.json
(computed from the live camera transform + the stage's own geometry seams +
the rig metrics), passed in as floats.

Moments and their assert families (TS SpaceStage.ts refs by family):
  SYSTEM   — the system view (TS:896-962): the warm sun discs, the 3 planet
             discs kind-dominant at center with the OFFSET shadow gradient
             (lit up-left vs dark down-right), the faint orbit arc (median
             on-arc vs the radius-−40 control), planet 1's ring stroke vs
             its control
  PIRATES  — the pirates (TS:981-984 + drawPirate :1170-1188): the r-dominant
             4-point hulls, the ☠ markers above, the red glow lift
  BLACKHOLE— the black hole (TS:911-926): the black core, the purple radial
             profile rising 20→30→36 and falling toward 50/85 (the 37.2
             mid-stop band eyeball — the T4-review rider), the rotating arc
             vs its out-of-span control
  BEAM     — the abduction (TS:986-1014): the beam line (blue at the
             midpoint, ship-end brighter than planet-end — the vertex-quad
             gradient), the off-line control, the rising creature's green
             body
  CARGO    — the cargo bar (TS:1052-1074): creature pixels in slot 0, cell
             pixels in slot 1, the empty slot 3 (no specimen pixels, panel
             dark)
  PANEL    — the planet panel (TS:1195-1231): the dark frame, the
             enabled-blue vs disabled-grey fills, the hull-fraction label
             (mid-lum neutral glyphs) vs the white enabled label
  FF       — the fast-forward tint (TS:1032-1038): the 0.06 purple veil
             (blue-shifted twin diff), the EVOLUTION ACCELERATING label
  CHIP     — the colonies chip (TS:1027-1030): the green 0-colony label in
             the system twin vs the gold 3-thriving label, text changed
  ENDING   — the ending overlay (TS:1083-1122): the 0.86 veil over the sun,
             THE CHAOS CORE ACCEPTS YOU (purple 34), the stat lines, the
             gold sandbox line, the dim keys line

plus OBS lines: the zoom_obs series (the T4-review camera-zoom one-frame lag
on stage entry — recorded, documented, NOT asserted).

Usage: visual_check_space_scene.py PROBES_JSON PNG... ; exit 0 = all held.
PNG order: system pirates blackhole beam cargo panel ff_before ff_after chip
ending.
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


def patch_max_bd(im, x, y, r):
    """max (b−r) over a small patch — the arc/line samples sit on 1-2px AA
    strokes whose center may land between pixels."""
    best = -999
    for yy in range(int(y) - r, int(y) + r + 1):
        for xx in range(int(x) - r, int(x) + r + 1):
            if 0 <= xx < im.size[0] and 0 <= yy < im.size[1]:
                p = px(im, xx, yy)
                best = max(best, p[2] - p[0])
    return best


def main():
    with open(sys.argv[1]) as f:
        P = json.load(f)
    system, pirates, blackhole, beam, cargo, panel, ff_before, ff_after, chip, ending = [
        Image.open(p).convert("RGB") for p in sys.argv[2:12]]
    failures = []

    def check(name, cond, detail):
        print(("OK  " if cond else "FAIL") + " %s %s" % (name, detail))
        if not cond:
            failures.append(name)

    vw = float(P["vw"])
    vh = float(P["vh"])

    # ---- OBS: the zoom-lag series (documented, not asserted) ------------------
    for row in P.get("zoom_obs", []):
        print("OBS zoom frame %s cam_zoom %s rig_zoom %s (sim_time %s)"
              % (row["frame"], row["cam_zoom"], row["rig_zoom"], row["sim_time"]))

    # ---- SYSTEM — sun, planet discs + shadows, orbit arc, ring -----------------
    sy = P["system"]
    c = patch_mean(system, sy["sun"][0], sy["sun"][1], 6)
    check("system-sun-warm", c[0] >= 180 and c[1] >= 140 and c[0] - c[2] >= 60, str(c))
    doms = {
        "lush": lambda p: p[1] >= 60 and p[1] - p[0] >= 15 and p[1] - p[2] >= 15,
        "ocean": lambda p: p[2] >= 60 and p[2] - p[0] >= 25 and p[2] - p[1] >= 10,
        "volcanic": lambda p: p[0] >= 70 and p[0] - p[1] >= 25 and p[0] - p[2] >= 40,
    }
    for i, pl in enumerate(sy["planets"]):
        c = patch_mean(system, pl["c"][0], pl["c"][1], 5)
        check("system-planet-%d-%s" % (i, pl["kind"]), doms[pl["kind"]](c), str(c))
        lit = patch_mean(system, pl["lit"][0], pl["lit"][1], 3)
        dark = patch_mean(system, pl["dark"][0], pl["dark"][1], 3)
        check("system-planet-%d-shadow" % i, lum(lit) >= lum(dark) + 25,
              "lit %s vs dark %s" % (str(lit), str(dark)))
    on = median([patch_max_bd(system, p[0], p[1], 1) for p in sy["arc_pts"]])
    off = median([patch_max_bd(system, p[0], p[1], 1) for p in sy["arc_ctrl_pts"]])
    check("system-orbit-arc", on >= off + 3, "on %s vs ctrl %s" % (on, off))
    c = patch_mean(system, sy["ring"][0], sy["ring"][1], 2)
    cc = patch_mean(system, sy["ring_ctrl"][0], sy["ring_ctrl"][1], 2)
    check("system-ring", c[2] >= 80 and c[2] - c[0] >= 25 and c[2] - c[0] > cc[2] - cc[0],
          "ring %s vs ctrl %s" % (str(c), str(cc)))

    # ---- PIRATES — hulls, skull markers, glow ---------------------------------
    for i, sp in enumerate(P["pirates"]["spots"]):
        c = patch_mean(pirates, sp["c"][0], sp["c"][1], 2)
        check("pirates-hull-%d" % i,
              c[0] - c[1] >= 25 and c[0] - c[2] >= 25 and 30 <= lum(c) <= 170, str(c))
        # the ☠ renders at presence level but DIM — at size 11 the 2px dark
        # outline swallows most of the glyph (the outlined_text divergence
        # note), so the marker reads as warm r-dominant pixels, not #ffb0a0
        n = count_in(pirates, sp["skull"],
                     lambda p: lum(p) >= 55 and p[0] >= p[1] + 15)
        check("pirates-skull-%d" % i, n >= 12, "%d warm marker px" % n)
    sp0 = P["pirates"]["spots"][0]
    gin = patch_mean(pirates, sp0["glow_in"][0], sp0["glow_in"][1], 2)
    gout = patch_mean(pirates, sp0["glow_out"][0], sp0["glow_out"][1], 2)
    check("pirates-glow", gin[0] >= gout[0] + 8, "in %s vs out %s" % (str(gin), str(gout)))

    # ---- BLACKHOLE — the 37.2 band profile + the rotating arc ------------------
    ho = P["hole"]

    def bg(im, pt):
        c = patch_mean(im, pt[0], pt[1], 1)
        return c[2] - c[1]

    c = patch_mean(blackhole, ho["core"][0], ho["core"][1], 1)
    check("hole-core-black", lum(c) < 30, str(c))
    check("hole-flank-inner", bg(blackhole, ho["profile"]["r30"])
          >= bg(blackhole, ho["profile"]["r20"]) + 15,
          "r30 %s vs r20 %s" % (bg(blackhole, ho["profile"]["r30"]),
                                bg(blackhole, ho["profile"]["r20"])))
    check("hole-peak-372", bg(blackhole, ho["profile"]["r36"])
          >= bg(blackhole, ho["profile"]["r30"])
          and bg(blackhole, ho["profile"]["r36"]) >= bg(blackhole, ho["profile"]["r44"]),
          "r36 %s vs r30 %s / r44 %s" % (bg(blackhole, ho["profile"]["r36"]),
                                         bg(blackhole, ho["profile"]["r30"]),
                                         bg(blackhole, ho["profile"]["r44"])))
    check("hole-flank-outer", bg(blackhole, ho["profile"]["r50"])
          <= bg(blackhole, ho["profile"]["r36"]) - 25,
          "r50 %s vs r36 %s" % (bg(blackhole, ho["profile"]["r50"]),
                                bg(blackhole, ho["profile"]["r36"])))
    check("hole-faint-far", bg(blackhole, ho["profile"]["r85"])
          <= bg(blackhole, ho["profile"]["r50"]) - 20,
          "r85 %s vs r50 %s" % (bg(blackhole, ho["profile"]["r85"]),
                                bg(blackhole, ho["profile"]["r50"])))
    # the arc rides ON the (angularly uniform) gradient at the same radius —
    # the LUM delta isolates the arc's additive stroke
    arc_l = lum(patch_mean(blackhole, ho["arc"][0], ho["arc"][1], 1))
    arc_cl = lum(patch_mean(blackhole, ho["arc_ctrl"][0], ho["arc_ctrl"][1], 1))
    check("hole-arc", arc_l >= arc_cl + 25, "arc lum %s vs ctrl %s"
          % (arc_l, arc_cl))

    # ---- BEAM — the line gradient + the rising creature -------------------------
    bm = P["beam"]
    c = patch_mean(beam, bm["mid"][0], bm["mid"][1], 2)
    check("beam-line-mid", c[2] >= 110 and c[2] - c[0] >= 30, str(c))
    se = patch_mean(beam, bm["ship_end"][0], bm["ship_end"][1], 2)
    pe = patch_mean(beam, bm["planet_end"][0], bm["planet_end"][1], 2)
    check("beam-gradient", lum(se) >= lum(pe) + 15,
          "ship-end %s vs planet-end %s" % (str(se), str(pe)))
    off = patch_mean(beam, bm["off"][0], bm["off"][1], 2)
    check("beam-off-control", c[2] - c[0] >= off[2] - off[0] + 25,
          "mid %s vs off %s" % (str(c), str(off)))
    n = count_in(beam, [bm["body"][0] - 16, bm["body"][1] - 16,
                        bm["body"][0] + 16, bm["body"][1] + 16],
                 lambda p: p[1] - p[0] >= 25 and p[1] >= 90)
    check("beam-creature", n >= 20, "%d green body px" % n)

    # ---- CARGO — creature/cell/empty slots --------------------------------------
    ca = P["cargo"]
    n = count_in(cargo, ca["green_box"], lambda p: p[1] - p[0] >= 25 and p[1] >= 90)
    check("cargo-creature", n >= 25, "%d green px in slot 0" % n)
    n = count_in(cargo, ca["cell_box"], lambda p: p[2] - p[0] >= 30 and p[2] >= 90)
    check("cargo-cell", n >= 25, "%d blue px in slot 1" % n)
    n = count_in(cargo, ca["empty_box"],
                 lambda p: (p[1] - p[0] >= 25 and p[1] >= 90)
                 or (p[2] - p[0] >= 30 and p[2] >= 90))
    check("cargo-empty", n <= 2, "%d specimen px in the empty slot 3" % n)
    c = patch_mean(cargo, (ca["empty_box"][0] + ca["empty_box"][2]) / 2.0,
                   (ca["empty_box"][1] + ca["empty_box"][3]) / 2.0, 6)
    check("cargo-empty-dark", lum(c) < 60, str(c))

    # ---- PANEL — the frame, the button fills, the labels ------------------------
    # the fill probes read the 4px band ABOVE the text line (r.y+4): the long
    # labels run through the row centers and would lift the patch
    pn = P["panel"]
    c = patch_mean(panel, (pn["frame_top"][0] + pn["frame_top"][2]) / 2.0,
                   pn["frame_top"][1] + 1, 2)
    check("panel-frame-dark", lum(c) < 40, str(c))

    def fill_at(pt):
        return patch_mean(panel, pt[0], pt[1] - 11, 1)

    c = fill_at(pn["abduct_c"])
    check("panel-abduct-blue", c[2] - c[0] >= 60, str(c))
    c = fill_at(pn["merge_c"])
    check("panel-merge-blue", c[2] - c[0] >= 60, str(c))
    c = fill_at(pn["repair_c"])
    check("panel-repair-grey", c[2] - c[0] < 40, str(c))
    n = count_in(panel, pn["repair_label"],
                 lambda p: 90 <= lum(p) <= 190 and abs(p[0] - p[2]) <= 30)
    check("panel-repair-label-fraction", n >= 8, "%d mid-lum neutral label px" % n)
    n = count_in(panel, pn["abduct_label"], lambda p: lum(p) >= 200)
    check("panel-abduct-label-white", n >= 8, "%d white label px" % n)

    # ---- FF — the veil pair + the label ------------------------------------------
    ff = P["ff"]

    def mean_box(im, box):
        x0, y0, x1, y1 = box
        c = (0.0, 0.0, 0.0)
        n = 0
        for yy in range(int(y0), int(y1) + 1, 2):
            for xx in range(int(x0), int(x1) + 1, 2):
                p = px(im, xx, yy)
                c = (c[0] + p[0], c[1] + p[1], c[2] + p[2])
                n += 1
        return (c[0] / n, c[1] / n, c[2] / n)

    a = mean_box(ff_before, ff["tint"])
    b = mean_box(ff_after, ff["tint"])
    shifts = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    check("ff-veil-shift", shifts[2] >= 5, "rgb shift %s" % (str(shifts),))
    check("ff-veil-hue", shifts[2] >= shifts[1] + 1, "b-shift %s vs g-shift %s"
          % (shifts[2], shifts[1]))
    n = count_in(ff_after, ff["label"],
                 lambda p: p[0] >= 180 and p[2] >= 230 and 120 <= p[1] <= 210)
    check("ff-label", n >= 8, "%d purple label px" % n)
    n = count_in(ff_before, ff["label"],
                 lambda p: p[0] >= 180 and p[2] >= 230 and 120 <= p[1] <= 210)
    check("ff-label-absent-before", n <= 3, "%d purple px in the pre twin" % n)

    # ---- CHIP — the green 0-colony label vs the gold 3-thriving label ------------
    ch = P["chip"]
    n = count_in(system, ch["box"], lambda p: p[1] - p[0] >= 20 and p[1] >= 120)
    check("chip-green-before", n >= 6, "%d green label px in the system twin" % n)
    n = count_in(chip, ch["box"], lambda p: p[0] >= 200 and p[1] >= 170 and p[2] <= 170)
    check("chip-gold-after", n >= 6, "%d gold label px" % n)
    diff = box_diff(system, chip, ch["box"])
    check("chip-text-changed", diff >= 4, "box diff %.2f" % diff)

    # ---- ENDING — the veil + the title + the stat lines ---------------------------
    en = P["ending"]
    c_end = patch_mean(ending, en["sun"][0], en["sun"][1], 6)
    c_chip = patch_mean(chip, en["sun"][0], en["sun"][1], 6)
    check("ending-veil-over-sun", lum(c_end) <= lum(c_chip) - 80,
          "ending %s vs chip %s" % (str(c_end), str(c_chip)))
    n = count_in(ending, en["title"],
                 lambda p: p[0] >= 180 and p[2] >= 230 and 120 <= p[1] <= 210)
    check("ending-title", n >= 12, "%d purple title px" % n)
    n = count_in(ending, en["stats"], lambda p: lum(p) >= 150)
    check("ending-stats", n >= 30, "%d light stat px" % n)
    n = count_in(ending, en["sandbox"],
                 lambda p: p[0] >= 190 and p[1] >= 160 and p[2] <= 170)
    check("ending-sandbox", n >= 6, "%d gold sandbox px" % n)
    n = count_in(ending, en["keys"], lambda p: 60 <= lum(p) <= 150)
    check("ending-keys", n >= 6, "%d dim keys px" % n)

    print("---")
    if failures:
        print("VISUAL_CHECK_FAIL: %s" % ", ".join(failures))
        return 1
    print("VISUAL_CHECK_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
