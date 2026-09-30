#!/usr/bin/env python3
"""Structural pixel asserts for the creature-painter visual capture (M3 task 6B).

No golden images — llvmpipe-deterministic STRUCTURAL tolerances (the cell
suite's doctrine). Sample positions are re-derived from the frozen TS
formulas (src/gfx/creature.ts metrics/spine/leg/tail/eye) for the pinned
genome (size 1.2, legs 4, hue 120, sat 0.55, fur+spots, tail, 2 eyes,
herbivore) at pose x=240 y=240 facing=1 speed=0.5 t=3.0 — the python replica
below IS the provenance (comment cites the TS lines per block).

Captures (from test_visual_creature.gd):
  BASE   — gaitPhase 0, mood idle, herbivore (no teeth)
  BASE2  — the same state captured a frame later (llvmpipe determinism twin)
  GAIT   — gaitPhase π/2 (feet move)
  ANGRY  — mood angry (brow + pupil)
  DEAD   — mood dead (rotate)
  CARN   — diet carnivore, jaw 3, size 2.2 (teeth — at 1.2 they are
           sub-pixel ~1.3px triangles, uncountable)
  SCALES — coat scales instead of fur

Asserts:
  a) determinism: BASE and BASE2 byte-identical (frozen state, same commands)
  b) body-disc center ≈ hue-120 at L 0.52 (r==b in the [90,150) HSL sector;
     green-dominant) — sample spine[2]
  c) belly band BELOW the body center is lighter (L+0.16 direction)
  d) far-side lower-leg segment darker than near-side (baseDark vs limb);
     sampled at the knee→foot midpoint (below the silhouette — far legs draw
     BEFORE the body union fill, so hip-side shafts are covered)
  e) eye at the head offset: sclera near-white + pupil near-black nearby
  f) tail stroke shoulder: the wide baseDark stroke shows OUTSIDE the body
     union between tail discs 4-5 (the polyline draws UNDER the union fill and
     the narrow base stroke overpaints it on the line center, so the sample
     sits perpendicular off the line, past the end discs' radius)
  g) fur strokes: light pixels in the upper-body band (coat fur, L+0.1 @0.7)
  h) scales capture differs structurally from BASE in the same band
  i) CARN has white teeth pixels the herbivore BASE lacks (sclera cancels)
  j) ANGRY vs BASE differs in the brow box above the eye
  k) DEAD vs BASE differs widely (the rotate moves the whole body)
  l) GAIT vs BASE differs in the lower leg band (feet at gaitPhase π/2)

Usage: visual_check_creature.py BASE BASE2 GAIT ANGRY DEAD CARN SCALES
exit 0 = all held.
"""
import math
import sys
from PIL import Image

PX, PY = 240.0, 240.0          # the pinned pose anchor
SIZE = 1.2
LEGS = 4
SPEED = 0.5
T = 3.0
GAIT = 0.0


def metrics_for(size):
    leg_h = (20.0 + min(LEGS, 6) * 1.5) * size
    body_r = 13.0 * size
    body_len = 40.0 * size
    body_y = -leg_h - body_r * 0.72
    bob = math.sin(GAIT * 2) * 1.6 * size * SPEED
    stride = 12.0 * size * (0.25 + SPEED)
    lift = 7.0 * size * SPEED
    return leg_h, body_r, body_len, body_y, bob, stride, lift


def metrics():
    return metrics_for(SIZE)


def spine_for(size):
    leg_h, body_r, body_len, body_y, bob, stride, lift = metrics_for(size)
    out = []
    for i in range(6):
        u = i / 5.0
        px = (u - 0.42) * body_len
        profile = math.sin(math.pi * min(1.0, u * 0.85 + 0.12))
        pr = body_r * (0.42 + profile * 0.62)
        py = (body_y + bob
              + math.sin(T * 2.2 + u * 2.4) * 1.1 * size * (0.3 + SPEED)
              + u * u * -2.0 * size)
        out.append((px, py, pr))
    return out


def spine():
    return spine_for(SIZE)


def leg(i, sp):
    leg_h, body_r, body_len, body_y, bob, stride, lift = metrics()
    u = i / (LEGS - 1) if LEGS > 1 else 0.5
    at = sp[1 + round(u * 3)]
    hx = at[0] + (u - 0.5) * body_len * 0.3
    hy = at[1] + at[2] * 0.45
    phase = GAIT + (i % 2) * math.pi + math.floor(i / 2) * 1.1
    fx = hx + (u - 0.5) * 6.0 * SIZE + math.cos(phase) * stride
    fy = -max(0.0, math.sin(phase)) * lift
    l1 = l2 = leg_h * 0.58
    dx, dy = fx - hx, fy - hy
    d = math.hypot(dx, dy)
    reach = l1 + l2 - 0.01
    if d > reach:
        dx *= reach / d
        dy *= reach / d
        d = reach
    if d < abs(l1 - l2) + 0.01:
        d = abs(l1 - l2) + 0.01
    a = (d * d + l1 * l1 - l2 * l2) / (2 * d)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    ux, uy = dx / d, dy / d
    bend = 1.0 if u < 0.45 else -1.0
    kx = hx + ux * a - uy * h * bend
    ky = hy + uy * a + ux * h * bend
    return (hx, hy), (kx, ky), (fx, fy)


def W(pt):
    return (PX + pt[0], PY + pt[1])


def tail_pts(sp0):
    """TS:137-150 / rig tail_points replica — disc centers only."""
    cx, cy = sp0[0] - sp0[2] * 0.6, sp0[1]
    ang = math.pi + 0.15
    out = []
    for k in range(5):
        ang += math.sin(T * 2.6 - k * 0.9) * 0.22 * (0.4 + SPEED) + 0.06
        cx += math.cos(ang) * 6.0 * SIZE
        cy += math.sin(ang) * 6.0 * SIZE * 0.6
        out.append((cx, cy))
    return out


def median_color(im, x, y, r):
    xs = []
    for yy in range(int(y) - r, int(y) + r + 1):
        for xx in range(int(x) - r, int(x) + r + 1):
            xs.append(px(im, xx, yy))
    return tuple(sorted(c[i] for c in xs)[len(xs) // 2] for i in range(3))


def px(im, x, y):
    return im.getpixel((int(round(x)), int(round(y))))[:3]


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def count_in(im, x0, y0, x1, y1, pred):
    n = 0
    for yy in range(int(y0), int(y1)):
        for xx in range(int(x0), int(x1)):
            if pred(px(im, xx, yy)):
                n += 1
    return n


def diff_count(im1, im2, x0, y0, x1, y1):
    n = 0
    for yy in range(int(y0), int(y1)):
        for xx in range(int(x0), int(x1)):
            a, b = px(im1, xx, yy), px(im2, xx, yy)
            if abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) > 24:
                n += 1
    return n


def main():
    base_p, base2_p, gait_p, angry_p, dead_p, carn_p, scales_p = sys.argv[1:8]
    base = Image.open(base_p).convert("RGB")
    base2 = Image.open(base2_p).convert("RGB")
    gait = Image.open(gait_p).convert("RGB")
    angry = Image.open(angry_p).convert("RGB")
    dead = Image.open(dead_p).convert("RGB")
    carn = Image.open(carn_p).convert("RGB")
    scales = Image.open(scales_p).convert("RGB")

    results = []

    def check(name, cond, detail):
        results.append((name, cond, detail))

    sp = spine()
    bc = W(sp[2])          # spine[2] disc center (u=0.4)
    _, body_r, _, body_y, _, _, _ = metrics()
    # the BACK above the belly band: the belly ellipse top reaches
    # body_y − 1.1 (canvas ≈ 196.5), so the disc center at 198.2 is INSIDE it —
    # sample 8px up the spine disc for the bare base fill
    back = (bc[0], bc[1] - 8.0)

    # a) determinism
    check("determinism_base2", list(base.getdata()) == list(base2.getdata()),
          "BASE vs BASE2 byte-identical (frozen state)")

    # b) body fill green-dominant, r≈b (hue 120) — 7×7 median so a seeded
    # pattern spot or fur line landing on the site cannot flip the sample
    c = median_color(base, back[0], back[1], 3)
    check("body_hue120", abs(c[0] - c[2]) <= 14 and c[1] >= 75 and c[1] - max(c[0], c[2]) >= 30,
          "back median %s" % (c,))

    # c) belly band lighter than the back (belly center is pose-local
    # (0, body_y + 0.55·body_r) — TS:261-264)
    bl = median_color(base, *W((0.0, body_y + body_r * 0.55)), 2)
    check("belly_lighter", lum(bl) - lum(c) >= 8,
          "belly %s vs back %s" % (bl, c))

    # d) far lower-leg segment darker than near (knee→foot midpoints — below
    # the silhouette; the hip-side shaft of far legs hides under the body
    # fill). Pair legs[3] (u=1, far) vs legs[2] (u=2/3, near): legs[0]/legs[1]
    # cross near their sample rows, legs[2]/legs[3] stay ~5px apart
    _, k3, f3 = leg(3, sp)   # far (odd)
    _, k2, f2 = leg(2, sp)   # near (even)
    far = median_color(base, *W(((k3[0] + f3[0]) / 2, (k3[1] + f3[1]) / 2)), 1)
    near = median_color(base, *W(((k2[0] + f2[0]) / 2, (k2[1] + f2[1]) / 2)), 1)
    check("far_darker_than_near", lum(far) < lum(near) - 8,
          "far %s vs near %s" % (far, near))

    # e) eye: sclera + pupil around the head offset
    head = sp[5]
    hr = head[2]
    ex, ey = W((head[0] + hr * 0.42, head[1] - hr * 0.28))
    box_r = 6
    whites = count_in(base, ex - box_r, ey - box_r, ex + box_r, ey + box_r,
                      lambda p: min(p) >= 170)
    darks = count_in(base, ex - box_r, ey - box_r, ex + box_r, ey + box_r,
                     lambda p: max(p) <= 70)
    check("eye_sclera_pupil", whites >= 3 and darks >= 2,
          "whites %d darks %d" % (whites, darks))

    # f) tail stroke shoulder between discs 4-5: offset perpendicular from the
    # line (past the narrow base stroke's halfwidth 0.2·body_r = 3.12, inside
    # the wide baseDark stroke's 0.35·body_r = 5.46) and outside the end discs
    # (r = 0.18·body_r = 2.81 each) → the baseDark shoulder, no fill over it
    tp = tail_pts(sp[0])
    t4, t5 = tp[3], tp[4]
    dxx, dyy = t5[0] - t4[0], t5[1] - t4[1]
    dl = math.hypot(dxx, dyy)
    nx, ny = -dyy / dl, dxx / dl
    mx, my = (t4[0] + t5[0]) / 2 + nx * 4.3, (t4[1] + t5[1]) / 2 + ny * 4.3
    tail_c = px(base, *W((mx, my)))
    check("tail_behind_body", tail_c[1] >= 40 and tail_c[1] - max(tail_c[0], tail_c[2]) >= 20
          and lum(tail_c) < lum(c) - 10,
          "tail shoulder %s vs body %s" % (tail_c, c))

    # g) fur strokes in the upper-body band
    fur_whites = count_in(base, bc[0] - 24, bc[1] - 22, bc[0] + 24, bc[1] - 6,
                          lambda p: lum(p) - lum(c) >= 20)
    check("fur_strokes", fur_whites >= 4, "light strokes %d" % fur_whites)

    # h) scales capture differs in the same band
    sd = diff_count(scales, base, bc[0] - 24, bc[1] - 22, bc[0] + 24, bc[1] - 6)
    check("scales_differs", sd >= 40, "scale-arc diff px %d" % sd)

    # i) carnivore teeth — snout-front box in head-radius units around the
    # CARN replica's head (the carn variant draws at size 2.2 so the ~1.3px
    # triangles at 1.2 become pixel-resolvable). The eyes overlap the box top
    # but are identical in both captures (cancel); the herbivore muzzle fills
    # the same region at under the ≥170 threshold
    head_c = spine_for(2.2)[5]
    hr_c = head_c[2]
    teeth_box = (W((head_c[0] + 0.25 * hr_c, head_c[1]))[0],
                 W((0, head_c[1] + 0.10 * hr_c))[1],
                 W((head_c[0] + 1.30 * hr_c, head_c[1]))[0],
                 W((0, head_c[1] + 0.75 * hr_c))[1])
    cw = count_in(carn, *teeth_box, lambda p: min(p) >= 170)
    bw = count_in(base, *teeth_box, lambda p: min(p) >= 170)
    check("teeth_carnivore", cw - bw >= 5, "carn whites %d vs base %d" % (cw, bw))

    # j) angry brow above the eye
    brow = diff_count(angry, base, ex - 8, ey - 12, ex + 8, ey - 2)
    check("angry_brow", brow >= 4, "brow diff px %d" % brow)

    # k) dead pose rotates the body
    dd = diff_count(dead, base, 120, 120, 360, 320)
    check("dead_rotates", dd >= 800, "whole-body diff px %d" % dd)

    # l) gait moves the feet
    gd = diff_count(gait, base, bc[0] - 40, bc[1], bc[0] + 40, 300)
    check("gait_moves_feet", gd >= 30, "lower-band diff px %d" % gd)

    failed = [(n, d) for (n, ok, d) in results if not ok]
    for (n, ok, d) in results:
        print(("OK   " if ok else "FAIL ") + n + "  — " + d)
    if failed:
        print("VISUAL_TEST_FAIL: %d/%d asserts failed" % (len(failed), len(results)))
        sys.exit(1)
    print("VISUAL_TEST_OK (%d asserts)" % len(results))


if __name__ == "__main__":
    main()
