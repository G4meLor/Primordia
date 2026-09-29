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
