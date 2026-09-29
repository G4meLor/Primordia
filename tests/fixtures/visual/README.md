# Visual capture baselines (task 7)

Reference PNGs from the cell-stage pixel-assert scene
(`tests/scenes/test_visual_cell.tscn`, run via `tools/test_visual.sh`):

- `cell_calm_reference.png` — fresh-save chaos (0.15), pinned seed 20260929,
  pinned player genome (size 1.0, hue 120, spots, flagella 2, jaw 1),
  captured when the arrival invuln has decayed (player at alpha 1).
- `cell_chaos_reference.png` — the same frozen sim frame with chaos forced
  to 0.8 (depth-gradient hue shift + pink chaos tint).
- `cell_glitch_reference.png` — the same frozen frame with the difference-
  composite glitch overlay forced on.

These are REFERENCES, not golden images: the assert is the structural
checker (`tools/visual_check.py`) — per-channel tolerances on sampled
structural pixels, never byte equality (llvmpipe is deterministic per run,
but font/AA may shift across mesa versions, and the calm frame's capture
condition can land one sim step earlier or later).

## Task 10 six-moment suite references

`tests/scenes/test_visual_suite.tscn` (run via `tools/test_visual_suite.sh`)
captures one PNG per moment from ONE scripted seed (0x51EED): `menu.png` +
`menu_drift.png` (title view, 1 s apart), `cell_early.png` (~3 s post-card),
`chaos_banner.png` (meteor forced via the sim's chaos.trigger at t=60 s),
`editor_a.png` + `editor_b.png` (real KeyE open; before/after a real mouse
purchase click), `death.png` (php forced 0, fade ≈ 0.8 s), `card.png` (a titled
go_to card mid-display). The copies here are the recorded references — the
gates are the structural asserts in `tools/visual_assert.py` (per-moment
table, per-assert tolerances; `reference.json` holds the measured numbers of
the recording run). Never byte-diffed, same doctrine as the task-7 files
above.
