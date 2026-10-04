# M7 CI + Release + Repo Overwrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The spec §5.6 terminal step: GitHub Actions CI (headless suite + the RID-leak ceiling gate), tag-triggered release (Windows/Linux exports), and the OLD GitHub repo (`G4meLor/Primordia` — the TS game's remote) OVERWRITTEN by the native port when 5-stage parity is reached (it is: `sim-core-m1` → `space-parity-m6`, all tagged, suite 55/814/21989/0).

**Architecture:** Two workflows + one overwrite task. `ci.yml` (push/PR): Godot 4.2.2 headless suite + the RID-ceiling assert (403 datum, the T8-review condition) — the suite-integrity gates the milestones ran locally, now the repo's contract. `release.yml` (tag `v*`): Godot 4.2.2 export Windows/Linux via the official templates + create the GitHub release with GITHUB_TOKEN (no local gh auth needed — the unauthenticated local gh is not a blocker). Task 3 is the operational moment: add the remote, probe access with a dry-run, force-push-with-lease (the old TS history is replaced by the native history — the local Spore checkout at ~/Desktop/RD/Spore retains the old history forever), push all six milestone tags + the release tag, verify the remote.

**Tech Stack:** GitHub Actions; Godot 4.2.2 (the project's pinned version); the established local gates (tests/run.gd with the two-pass script-error guard, tools/ab_test.sh, the RID telemetry line-format from T8's §11).

**Spec:** docs/specs/2026-09-29-native-migration-design.md §5.6 ("CI + release — GitHub Actions: `godot --headless` test + export Windows/Linux (template export); release `v{version}` khi tag. Ghép repo GitHub + đè repo cũ theo đúng định nghĩa 'ghi đè' khi đạt parity 5 stage").

**Milestone ruling:** spec §5 — M1–M6 all tagged (the 5-stage parity condition MET). **M7 = CI/release + repo overwrite** (this plan), the goal's terminal step. The tag: `ci-release-m7`.

## Global Constraints

- **The RID-leak ceiling gate (the T8-review condition, MANDATORY):** ci.yml asserts the exit telemetry's CanvasItem-RID count ≤ **403** (the entry datum; per-file narrowing is the ideal, the ceiling is the gate). The parse target: the suite log's `WARNING:.*CanvasItem.*RIDs?` line (the exact format from the M6 §11 telemetry: "N CanvasItem RIDs leaked"); zero is the WRONG gate (the pinned mechanism is un-freed out-of-tree test boots, not a runtime leak).
- **The CI suite command is the LOCAL gate, verbatim:** `godot --headless -s res://tests/run.gd --path .` (the two-pass script-error guard runs in CI too — a script error fails the workflow). The runner's zero-check + script-error guards are part of the contract.
- **Godot 4.2.2 pinned everywhere** (ci.yml + release.yml use the same version — the project's `config_version=5` / the milestone-rig version).
- **The overwrite is force-push-WITH-LEASE** (`git push --force-with-lease origin main`) — never a bare `--force`; it refuses if the remote moved unexpectedly. The old TS history survives locally at ~/Desktop/RD/Spore (its origin stays pointing there).
- **The release is created BY the workflow** on tag push (GITHUB_TOKEN, contents:write) — no local gh auth dependency. Local `gh` stays unauthenticated; nothing in this plan requires it.
- **No game-code changes in M7.** The suite baseline is frozen at 55/814/21989/0 (space-parity-m6 @ 0b796dc); any drift in T1/T2/T3's verification is a bug to fix, not a number to update.
- **Versioning:** the release tag is `v0.6.0` (0 major milestones shipped? no — six: the version follows the milestone count: v0.6.0 = M6-complete parity build; the next feature version bumps at M7+ content). The tag name is lowercase-v per convention.
- **Secrets:** none required (public-repo Actions with GITHUB_TOKEN). If the repo is private, GITHUB_TOKEN still works for releases.

**User decisions (already made):** the goal («hoàn thành repo đi») names the overwrite as the terminal step; the spec §5.6 defines it ("đè repo cũ ... khi đạt parity 5 stage"). The push moment executes under that authorization with the verification pass in Task 3.

---

### Task 1: CI workflow — the suite as the repo's contract

**Goal:** `.github/workflows/ci.yml` — on push/PR: checkout, Godot 4.2.2, the headless suite, the RID-ceiling gate; green on the current HEAD.

**Files:**
- Create: `.github/workflows/ci.yml`
- Test: the workflow is validated by (a) actionlint if available (else a strict YAML read), (b) a LOCAL rehearsal of its exact steps (the suite run + the RID parse against the current tree — the numbers must match the 403 datum)

**Acceptance Criteria:**
- [ ] Triggers: push (main) + pull_request. Runner: ubuntu-latest.
- [ ] Steps: checkout → the Godot 4.2.2 setup (a pinned action or a direct download of the 4.2.2 mono=false linux binary — match the local rig `~/.local/bin/godot`'s version EXACTLY; pin the download URL/version string) → the suite (`godot --headless -s res://tests/run.gd --path .`, tee to a log) → the RID gate (grep the log for the CanvasItem-RID warning line, parse N, fail if N > 403; the parse must handle the exact M6 telemetry format — verify the format from a fresh local run's stderr) → upload the log as a workflow artifact (always()).
- [ ] The RID gate is a HARD step (a non-zero exit fails the workflow) with the ceiling as a named constant at the top of the step (visibility).
- [ ] Local rehearsal: run the suite locally once more, capture the exact RID warning line, and verify the parse logic extracts 403 (the current datum) — the rehearsal script/log paths recorded in the report (NOT committed).
- [ ] The workflow does NOT run the xvfb suites (CI stays lean: the headless suite IS the gate; the xvfb families are the local/wrap sweep's contract — recorded in the workflow comment with a pointer to PARITY-M6 §15).

**Verify:** actionlint (or YAML parse) clean; the local rehearsal matches the 403 datum. **Commit:** `ci: headless suite + RID-leak ceiling gate (403 datum)`.

### Task 2: Release workflow + export presets

**Goal:** `export_presets.cfg` (Windows + Linux) + `.github/workflows/release.yml` — on tag `v*`: export both targets with Godot 4.2.2 templates, create the GitHub release with the artifacts.

**Files:**
- Create: `export_presets.cfg`, `.github/workflows/release.yml`
- Test: a local rehearsal of the export command shape (the presets parse — `godot --headless --export-release` with a missing template pack fails GRACEFULLY with the preset recognized; the rehearsal proves the preset names/paths, NOT the export itself — that happens in CI)

**Acceptance Criteria:**
- [ ] export_presets.cfg: two presets — `Windows` (x86_64, the PRIMORDIA name) + `Linux` (x86_64); the main scene + the project paths correct; no encryption; the export paths `build/PRIMORDIA.exe` / `build/PRIMORDIA.x86_64` (+ the .pck sidecar behavior as Godot defaults).
- [ ] release.yml: on push of tags `v*` → checkout → Godot 4.2.2 + the export TEMPLATES installed (the official 4.2.2 template pack fetched in the workflow) → `godot --headless --export-release Windows build/PRIMORDIA.exe` + the Linux twin → the artifacts zipped → `gh release create` via the GitHub CLI IN THE WORKFLOW (authed with GITHUB_TOKEN, contents:write permission in the workflow's permissions block) with the auto-generated notes + the two artifacts.
- [ ] The workflow permissions block: `contents: write` (the release), nothing broader.
- [ ] Local rehearsal: `godot --headless --export-release` with the presets — expect a template-missing error naming the preset (proves the preset parses); the rehearsal output in the report (NOT committed).
- [ ] The release body template: one paragraph (the 5-stage parity build — cell/creature/tribe/civ/space, the milestone tags, the suite counts 55/814/21989/0) + the controls summary (the game is playable; the README carries the full controls).

**Verify:** both workflows YAML-clean; the export preset rehearsal shows the preset recognized. **Commit:** `release: export presets + tag-triggered release workflow`.

### Task 3: The repo overwrite — the remote becomes the native port

**Goal:** The operational moment: `G4meLor/Primordia` (the TS game's remote) is REPLACED by the native port — main + all six milestone tags + `v0.6.0`, the release workflow fires and creates the release.

**Files:**
- Modify: none in the repo (the remote state IS the deliverable); the local remote config (git remote add)
- Test: the remote verification steps (the pushed HEAD == local HEAD; the tags present; the CI workflow's first run green; the release exists)

**Acceptance Criteria:**
- [ ] `git remote add origin git@github.com:G4meLor/Primordia.git` (the native repo's first remote).
- [ ] The ACCESS PROBE: `git push --dry-run origin main` — if it fails with a permission error, STOP: the milestone is BLOCKED on credentials (ShiniChien lacks write access to G4meLor/Primordia — report honestly; the fallback is a fork or collaborator access, the user's call). If the dry-run succeeds, proceed.
- [ ] The verification pass BEFORE the overwrite (all must hold at HEAD): the suite green (55/814/21989/0, fresh run), the tree clean, `git describe --tags` = space-parity-m6, the two workflows committed and YAML-clean.
- [ ] The overwrite: `git push --force-with-lease origin main` (the old TS history replaced — the local Spore checkout retains it) → `git push origin --tags` (all six milestone tags + any existing) → `git tag v0.6.0 && git push origin v0.6.0` (the release workflow fires on this push).
- [ ] The post-push verification: `git ls-remote origin` shows the native main + the tags; the CI workflow's first run (triggered by the push) reaches green (poll via the runs API/`gh` unauth-free: the workflow status is visible on the commit's checks; if `gh` cannot query unauthenticated, the workflow's green is verified by the NEXT push's status or the runs list via the web — record what was verifiable); the release `v0.6.0` exists with the two artifacts (verifiable via the releases page/`git ls-remote --tags`).
- [ ] README's CI badge (if the workflow is green — the badge URL is standard) + a one-line provenance note ("the native Godot 4.2.2 port of PRIMORDIA — the TypeScript original's history remains in the repo's git archive"? NO — the overwrite replaces history; the note is simply the port's README which already exists. The old repo's README is REPLACED by the native README — that IS the overwrite.)
- [ ] Ledger: the push SHA, the release URL, the CI run conclusion — in the M7 ledger + the completion note.

**Verify:** `git ls-remote origin` matches local; the release tag exists remotely. **Commit:** `release: v0.6.0 — the 5-stage parity build` (any README badge line) — committed BEFORE the tag push.

### Task 4: M7 wrap — the final review, the completion, the tag

**Goal:** Close the arc.

**Files:**
- Modify: `docs/PARITY-M6.md` (no — the M7 completion note goes in a new `docs/PARITY-M7.md` or the README's status section; the leanest honest artifact: `docs/RELEASE-M7.md` — the release record: the SHA, the release URL, the CI status, the RID datum, the overwrite confirmation)

**Acceptance Criteria:**
- [ ] `docs/RELEASE-M7.md`: the release record (the pushed SHAs, the tag list, the release URL, the CI run conclusion, the RID datum 403, the overwrite confirmation with the force-with-lease evidence, the local-history note).
- [ ] The final whole-branch review (controller) on the M7 arc (f3daa44..HEAD is M6's; M7's arc is 0b796dc..HEAD — small) → riders → tag `ci-release-m7` (pushed).
- [ ] The completion note: **the arc is DONE** — M1–M7, the goal «hoàn thành repo đi» met (the repo completed: the port, the CI, the release, the old repo overwritten).

**Verify:** the tag pushed; the release record complete. **Commit:** `docs: M7 release record + completion`.

---

## Completion

- [ ] All 4 tasks complete, the final review clean, `ci-release-m7` tagged+pushed, the release live.
- **The goal:** «hoàn thành repo đi» — MET (the port of all five stages, the CI, the release, the old repo overwritten per spec §5.6).
