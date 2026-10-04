# M7 Release Record — the CI/release/repo-overwrite milestone

Date: 2026-10-04 · The spec §5.6 terminal step: **the arc is DONE.**

## The overwrite

- **The remote `git@github.com:G4meLor/Primordia` now hosts the native port.**
  The old TypeScript history was replaced by force-push-WITH-LEASE (never a
  bare force); the old history survives locally at `~/Desktop/RD/Spore`
  (its origin config untouched).
- The remote state (verified via `git ls-remote` + the GitHub API):
  - `main` = the native lineage (…→ `d03b16f` ci → `da0d699` release →
    `18abb18` controls → `d31bc3e` tracker → `aca439f` worker/export fixes →
    `badb009` import metadata → `8ea587d` build-dir fix).
  - All six milestone tags: `sim-core-m1`, `cell-parity-m2`,
    `creature-parity-m3`, `tribe-parity-m4`, `civ-parity-m5`,
    `space-parity-m6` — plus `v0.6.0`.

## The release

- **`v0.6.0` published**: https://github.com/G4meLor/Primordia/releases/tag/v0.6.0
  — `PRIMORDIA-windows.zip` + `PRIMORDIA-linux.zip` (both exported by the
  `release.yml` workflow with the pinned Godot 4.2.2 + the official
  templates, sha256/sha512 double-verified).
- The release body links the README's Controls section (committed before the
  first tag push, per the T2-review gate).

## The CI

- `ci.yml` (push/PR): the headless suite verbatim (the two-pass script-error
  guard included) + the **RID-leak ceiling gate at 403** (the T8-review
  condition; zero is the wrong gate — the pinned mechanism is un-freed
  out-of-tree test boots, not a runtime leak).
- CI green on `aca439f` (the first full runner green) AND on the release
  commit `8ea587d` — both verified via the runs API at wrap time.

## The red chain (each root-caused + reproduced locally BEFORE its fix)

1. **rcedit** — the Windows preset's `modify_resources=true` requires rcedit
   (+Wine), absent on the runner → `modify_resources=false` (stub metadata,
   cosmetic).
2. **The worker display loss** — the suite's two-pass script-error guard
   re-executes as a worker subprocess whose args DROP the engine-consumed
   `--headless` flag; on the display-less runner the worker died instantly.
   The CI suite step now runs under `xvfb-run -a` (the display-backed
   telemetry the 403 datum was calibrated on; the datum reproduced exactly —
   NO re-datum needed).
3. **The import pass** — Godot 4.2 has NO auto-import on `--export-release`,
   and the repo's `.import` metadata files were never versioned → 22
   unimported-asset errors. Fixed: the `.import` files committed +
   `release.yml` runs a headless editor import pass (600 frames — a bare
   `--quit` aborts the scan mid-import).
4. **The build dir** — Godot 4.2.2's exporter fails when the OUTPUT DIRECTORY
   doesn't exist; a runner-fresh checkout has no `build/`. Fixed: `mkdir -p
   build` before both exports.

## The frozen invariants (unchanged through M7)

- Suite: **55 files / 814 tests / 21989 checks / 0 failures** (the M6 tag
  datum — re-verified at every push).
- A-B cell dump: `ea35920b…` unmoved since M2 (4 consecutive IDENTICAL
  windows).
- RID telemetry: 403 (the CI ceiling's entry datum).

## The goal

«hoàn thành repo đi» — **MET**: the native Godot 4.2.2 port of PRIMORDIA
(all five playable stages — cell, creature, tribe, civ, space — parity-pinned
against the frozen TypeScript authority across seven milestone tags, 814
tests), with CI, a live release, and the old repo overwritten per spec §5.6.
