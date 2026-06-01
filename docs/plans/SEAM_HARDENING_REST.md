---
title: Seam Hardening — REST (remaining shell-testable skills exercise production code)
created: 2026-05-31
status: active
---

# Plan: Seam Hardening — REST

## Overview

Part 2 of seam hardening. Sibling to `docs/plans/SEAM_HARDENING_HIGH.md`
(PR #830) — **same technique, different skills**, split only because 18
skills won't fit one `/run-plan`. Read SEAM_HARDENING_HIGH.md first; this
plan reuses its **Technique selection** framing and its `tests/lib/` helper
contract verbatim. Goal: every remaining shell-testable skill exercises
**production code**, not an embedded copy / re-implementation (#809
hollow-green class).

**Technique (inherited from #830 — do not re-derive): pick per fence.**
(1) extract-and-run the production fence (seed inputs + shim externals + run
the real logic) — preferred; (2) parity-gate-the-production-fence — sanctioned
fallback only where input-seeding is intractable, with the caveat it catches
*drift* not *always-wrong logic*; (3) anchor-grep + honest model-layer label
where there is no production code to run (the model emits it per prose).

**The discriminator for "convert vs leave alone"** (resolves a review
inconsistency): a test that **runs the real script/helper** already meets the
goal → leave it (confirm-only). A test that **runs an embedded COPY** of the
skill's bash (even one guarded by a `grep -qF` parity gate) does NOT exercise
production code → convert it. Parity-gate (technique #2) is the *fallback when
seeding is intractable*, not a pass for an embedded copy that IS seedable.

**Honest scope (from research — smaller than a naive "10 skills"):**
- **4 real conversions:** verify-changes (private parser copy → extract-and-run),
  fix-issues (loose 7-fingerprint parity over a stitched copy → extract-and-run),
  zskills-dashboard (transcribed bash → extract-and-run), research-and-go (one
  small extractable landing-regex fence; its decompose→dispatch core is
  **model-layer → anchor, not harness**).
- **briefing (real LOW gap):** 4 pure Python functions → direct importlib unit
  tests (no lib needed).
- **add-block + add-example (convert):** they run embedded copies under a
  `grep -qF` parity gate — small self-contained tracking-setup fences, cheap to
  extract-and-run with the lib. Converted for consistency with the goal.
- **cleanup-merged (marginal consolidation):** already extract-and-runs via
  bespoke inline awk — migrate to the shared lib (fidelity, not new coverage).
- **2 CONFIRM-ONLY (already invoke the real script — the goal; no work):**
  create-worktree (test invokes the real `create-worktree.sh`, 21 cases),
  draft-tests (tests invoke real helper scripts). Record "confirmed adequate +
  evidence"; do NOT manufacture work.

**Non-goals:** no Layer-3/judgment verification; never weaken an assertion
(converted test asserts ≥ the prior one, against production code — for
fix-issues TIGHTEN, don't loosen); **no live-repo mutation** (the
`test-backfill-plan-completed.sh` live-mutation bug is the cautionary example —
all fixtures in `mktemp -d`).

## Dependency on #830 (HARD)

This plan reuses `tests/lib/extract-fence.sh` (`extract_fence_between`,
`extract_sentinel_block`) built by SEAM_HARDENING_HIGH **Phase 1**. Research
confirmed it does NOT exist on main yet (#830 is plan-only, not executed). To
avoid two plans building divergent same-named libs (a real hazard — the lib
spec is prose, two implementer agents would diverge), this is a **HARD
dependency, not build-if-absent**:

- **Phase 1 = verify-the-lib-exists.** If `tests/lib/extract-fence.sh` is
  present with the documented functions → proceed. If ABSENT → **STOP** with:
  "SEAM_HARDENING_REST requires tests/lib/extract-fence.sh, built by
  SEAM_HARDENING_HIGH (#830) Phase 1. Run #830 first." Do NOT build a second
  copy.
- **Required sequencing: run #830 to completion before this plan.**
- Note: REST does NOT consume `landpr-harness.sh` (no land-pr caller loop in
  any phase) — only `extract-fence.sh`. Phase 1 verifies only that.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Verify `tests/lib/extract-fence.sh` exists (hard dep on #830) | ✅ Done | `verify-gate` | lib present + sourceable on main (HIGH #943 landed) |
| 2 — verify-changes: extract-and-run the real arg-parser | ⬚ | | |
| 3 — fix-issues: extract-and-run the 3 sprint fences (assert a row lands) | ⬚ | | |
| 4 — zskills-dashboard: extract-and-run (concatenated Step-0 + helpers) | ⬚ | | |
| 5a — briefing: importlib unit tests for 4 pure functions | ⬚ | | |
| 5b — research-and-go + add-block/add-example convert + cleanup-merged consolidation + 2 confirm-only | ⬚ | | |

## Conventions (all phases)

Identical to SEAM_HARDENING_HIGH — restated for self-containment:
- House style: `set -u`; `pass`/`fail`; final **`Results: N passed, N failed`**;
  non-zero exit on failure. Register every new `tests/test-*.sh` in
  `tests/run-all.sh`.
- **Anti-green-by-absence (M3):** every phase that ADDS a new test file MUST
  confirm it appears in the `bash tests/run-all.sh` output (registered +
  executed), not just that the file exists. `run-all.sh` is an explicit
  `run_suite` list (no glob) — an unregistered new file silently never runs.
  (Phases 2/3/4 only *convert* already-registered suites, so this applies to
  the new files in 5a/5b.)
- Sandbox: `mktemp -d` + `trap 'rm -rf' EXIT`; `git init`/`git worktree add`
  fixtures; NO network, NO real gh/PR, NO writes outside the sandbox.
- **No jq** (Python3 stdlib json / bash regex).
- **Verify each cited test/fence by reading it before converting** — line
  numbers indicative (grep the landmark; review found several off by 6-15 lines).
- **Preserve assertions:** converted test asserts ≥ prior. Replacing a
  presence-grep with a behavior test is strictly stronger and fine; deleting an
  assertion is not.
- SKILL.md edits → version bump + mirror. **This plan expects ~zero SKILL.md
  edits** (all conversions extract the EXISTING production fence; they don't
  change it — review verified the spurious `cd`/signature artifacts live in the
  TESTS, not production). Flag if any phase finds it must edit a SKILL.md.
- Each phase ends green on the FULL suite: `bash tests/run-all.sh` — assert
  **exit code 0 AND** the `Overall: N/M passed, 0 failed` line.

## Phase 1 — Verify `tests/lib/extract-fence.sh` exists (hard dep on #830)

### Goal
Confirm the shared extractor lib (built by #830) is present before consuming it.

### Work Items
- [ ] Check `tests/lib/extract-fence.sh` exists and is sourceable with
  `extract_fence_between` + `extract_sentinel_block`. If present → proceed.
- [ ] If ABSENT → STOP with the message above (run #830 first). Do NOT build a
  second copy (divergent-lib hazard).

### Acceptance Criteria
- [ ] `tests/lib/extract-fence.sh` present + its two functions sourceable, OR
  the phase STOPs cleanly directing to run #830 first.

### Dependencies
SEAM_HARDENING_HIGH (#830) executed.

## Phase 2 — verify-changes: extract-and-run the real arg-parser

### Goal
Kill the PRIVATE `parse_args()` copy inside `tests/test-hooks.sh` (~4077,
re-types the SKILL.md parser; drift keeps it green) — run the REAL parser.
Highest value: verify-changes guards the verification gate.

### Work Items
- [ ] Replace the private `parse_args()` (test-hooks.sh ~4076-4090) with
  `extract_fence_between` pulling the real self-contained ```bash fence under
  `### Parsing $ARGUMENTS` (≈ `skills/verify-changes/SKILL.md:188-196` — verify),
  wrapped `parse_args() { local ARGUMENTS="$1"; SCOPE=""; TRACKING_ID=""; <extracted>; }`.
  The real parser iterates `$ARGUMENTS` (private copy used `$1`) — the wrapper
  bridges it. No externals to shim (pure string parsing).
- [ ] Preserve ALL 8 cases (branch+tracking-id, order-independence,
  worktree-alone, `last N`, junk-tolerance, bare-`last`, number-without-`last`,
  empty) verbatim — only the parser source changes.

### Acceptance Criteria
- [ ] `test-hooks.sh` runs the REAL parser; no private copy; 8 cases preserved;
  mutating the SKILL.md parser fails the test (demonstrate).
- [ ] `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Phase 3 — fix-issues: extract-and-run the 3 sprint fences (assert a row lands)

### Goal
`test-fix-issues-bootstrap.sh` runs an EMBEDDED copy guarded by a LOOSE
7-substring parity gate (catches deleted lines, NOT logic drift between them).
Extract-and-run the real fences — and guard against introducing NEW hollowness.

### Work Items
- [ ] Replace the embedded `run_sync_bootstrap_and_rowwriter()` (~84-153) with
  the real `modes/sprint.md` fences via `extract_fence_between`: **fetch ≈304-316,
  bootstrap ≈327-361, row-writer ≈378-410** (verify ranges — review found the
  draft's were off). **Mixed indent:** fetch + row-writer are 3-space-indented,
  bootstrap is column-0 — pass `strip-indent` per fence accordingly or the
  concatenated eval is syntactically broken.
- [ ] **Cross-fence state (the #830-C1 problem here):** run the fetch fence
  FIRST so `$GH_OUT`/`$OPEN_NUMS` are populated before the row-writer's python3
  consumes them. **CRITICAL anti-no-op (review F4):** the fences source
  `zskills-resolve-config.sh` for `$ZSKILLS_ISSUES_DIR`; if the harness shims
  that away, `$ZSKILLS_ISSUES_DIR` is unset and the row-writer writes NOWHERE
  and the test passes against a no-op (new hollowness). The harness MUST seed
  `ZSKILLS_ISSUES_DIR` to the fixture dir AND **assert a row actually lands**
  (a file appears with expected content), not merely that the function ran.
- [ ] Reuse the existing gh-shim (~54-79) + real python3. Drop the now-redundant
  sprint-fingerprint `test_skill_md_parity`; KEEP `test_land_pr_dispatch_parity`
  (the /land-pr dispatch fence is model-layer dispatch wiring — anchor correct).
- [ ] Preserve all behavioral tests (empty-issues, dedup, zero-open-clean-exit,
  sync-and-land-smoke) — stronger running extracted code.

### Acceptance Criteria
- [ ] Runs the REAL sprint fences; a logic change between fingerprint lines now
  fails the test (demonstrate); a row actually lands in the fixture
  `ZSKILLS_ISSUES_DIR` (proves not a no-op); all behavioral tests preserved.
- [ ] `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Phase 4 — zskills-dashboard: extract-and-run (concatenated Step-0 + helpers)

### Goal
`test_zskills_dashboard_skill.sh` hand-transcribes the start/stop/status/marker
bash as `$1=MAIN_ROOT`-parameterized functions. Run the REAL fences instead.

### Work Items
- [ ] **Concatenate-into-one-eval (review F2 — the load-bearing fix):** the
  `start`/`stop`/`status` fences read globals (`PID_FILE`, `LOG_FILE`,
  `PORT_SCRIPT`, `SANITIZE_SCRIPT`, `PKG_PARENT`, `MAIN_ROOT`) set in the
  **Step-0 fence**, and CALL `verify_monitor_identity` / `write_tracking_marker`
  (production signatures: `verify_monitor_identity "$pid"` reading global
  `$MAIN_ROOT` — 1-arg, NOT the test's 2-arg copy). So extract **Step-0 +
  `verify_monitor_identity` + `write_tracking_marker` + the target mode fence,
  in dependency order, into ONE eval'd subshell** with `MAIN_ROOT` exported to
  the fixture (replicating production's Step-0 `cd "$MAIN_ROOT"` contract).
  Extracting a mode fence alone aborts under `set -u` on the first unset global.
  `seed_caller_loop_inputs` does NOT apply (it seeds land-pr vars, not dashboard
  globals).
  Fence landmarks (verify): Step-0 ≈79-98, `verify_monitor_identity` ≈118-164,
  `write_tracking_marker` ≈173-198, start ≈247-351, stop ≈373-455, status ≈472-534.
- [ ] Shims: `git` (fixture is a real git repo), `port.sh` +
  `sanitize-pipeline-id.sh` (source-resolved). Keep the live
  `python3 -m zskills_monitor.server`. **Harden the boot race (review F3):** the
  existing `sleep 0.25` + curl health-poll is a CI flake source — use a bounded
  retry-poll (e.g. up to ~3s in 0.25s steps), not a single sleep.
- [ ] Remove the test's spurious `cd "$MAIN_ROOT"` workaround + the 2-arg helper
  calls (artifacts of the transcription, absent from production).
- [ ] Preserve every AC — static-grep ACs + all live-server behavioral
  assertions (start→health→pidfile→marker; stop→SIGTERM→pidfile-removed;
  status→uptime; stale-pidfile; identity-mismatch refusal).

### Design & Constraints
- If the Step-0+helpers+mode concatenation proves intractable to run, parity-gate
  the fences as the sanctioned fallback (note it). Test-only; no SKILL.md edit.

### Acceptance Criteria
- [ ] Runs the REAL SKILL.md fences (concatenated); no transcribed copies / no
  spurious `cd`; mutating a production fence fails the test; boot-poll is a
  bounded retry; all prior ACs preserved.
- [ ] `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Phase 5a — briefing: importlib unit tests for 4 pure functions

### Goal
The real LOW gap: 4 pure `briefing.py` functions hit only indirectly via smoke.
Add direct hermetic unit tests (no lib needed — importlib pattern).

### Work Items
- [ ] Add `tests/test-briefing-units.sh` — importlib-load `briefing.py` (the
  `test-briefing-dogfooding.sh` pattern) and unit-test:
  - `parse_period` (`'1h'→'1 hour ago'`, `'2d'→'2 days ago'`, `'bogus'→'24 hours ago'`)
  - `scan_checkboxes_in_files` (one `[ ]` + one `[x]` under a heading; fenced
    code-block checkboxes ignored)
  - `check_staleness` (no-briefing warning + 7-day-stale-worktree warning)
  - `preserve_checkboxes` (same-day checked-state carry-forward; empty audit_dir
    is identity)
- [ ] Hermetic tmpdir fixtures; no network, no live-repo writes.
- [ ] **Register `test-briefing-units.sh` in `run-all.sh` AND confirm it appears
  in the rollup output** (M3).

### Acceptance Criteria
- [ ] All 4 functions have direct unit tests asserting the listed behaviors; the
  new suite is registered + runs; `bash tests/run-all.sh` exit 0; Overall 0.

### Dependencies
None (independent of Phase 1 — importlib, no lib).

## Phase 5b — research-and-go + add-block/add-example convert + cleanup-merged + confirm-only

### Goal
The remaining smaller items, grouped (none is a full phase alone).

### Work Items
- [ ] **research-and-go:** extract-and-run the **landing-mode regex** fence
  (SKILL.md ≈285-287: `[[ "$GOAL" =~ (^|[[:space:]])[pP][rR]... ]]` etc.) — seed
  GOAL strings incl. casing (`pr`/`PR`) and word-boundary negatives (`"reproduce"`
  must NOT match `pr`). The decompose→dispatch core is **model-layer** (judgment
  dispatch of `/draft-plan`+`/run-plan`) — use an **anchor-grep** that the
  dispatch lines + Agent-tool preflight are present, explicitly labeled
  "presence not behavior." Do NOT build a harness for it.
- [ ] **add-block + add-example (convert):** their smokes run an embedded
  tracking-setup fence under a `grep -qF` parity gate. Convert to
  `extract_fence_between` running the REAL fence (small + self-contained — cheap
  with the lib). Preserve the existing assertions (3-tier PIPELINE_ID resolution,
  sanitize routing, marker shape). This makes them exercise production code,
  consistent with the goal (the discriminator: they run a COPY → convert).
- [ ] **cleanup-merged (consolidation):** migrate the bespoke inline awk
  extractors in `test-cleanup-merged-ahead-gate.sh` / `-namelist.sh` to the
  shared `extract_fence_between`/`extract_sentinel_block` (fidelity; single
  audited extractor). Preserve all cases — refactor, not new coverage.
- [ ] **Confirm-only (record evidence, no new test — they already invoke the
  real script, which IS the goal):** create-worktree (`test-create-worktree.sh`
  invokes the real `create-worktree.sh`, 21 cases), draft-tests
  (`test-draft-tests-phase2-5` invoke real helper scripts). One-line "confirmed
  adequate + evidence" each in the phase report.
- [ ] Register any new test file; confirm in the rollup (M3).

### Acceptance Criteria
- [ ] research-and-go landing-regex runs the real fence (+ labeled anchor for the
  model-layer dispatch core); add-block/add-example run the REAL tracking-setup
  fence (no embedded copy); cleanup-merged extractors use the shared lib; the 2
  confirm-only skills recorded as adequate-with-evidence.
- [ ] `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Plan Quality

**Drafting process:** /draft-plan — 2 research agents (read the real
tests/fences for all 10 skills) + 1 adversarial round (reviewer +
devil's-advocate).
**Convergence:** Converged at round 1 — review produced ~13 findings (2 MAJOR,
3 HIGH, rest MED/MINOR/LOW), ALL dispositioned. 0 substantive issues open. The
findings materially improved the plan (hard #830 dependency, the Phase-3
anti-no-op assertion, the Phase-4 concatenation contract, the convert-vs-confirm
discriminator, the Phase-5 split).
**Remaining concerns:** None blocking. Honest residue, encoded in the plan:
(1) research-and-go's decompose→dispatch is model-layer (anchored, presence not
behavior); (2) Phase 4's live python server is a known flake surface (mitigated
by a bounded boot-poll, not eliminated); (3) the plan hard-depends on #830 being
executed first (stated as a STOP precondition).

### Round History
| Round | Reviewer | Devil's Advocate | Resolved |
|-------|----------|------------------|----------|
| 1 | 6 (1 MAJOR: landpr-harness dead-weight / Phase-1 dep; rest MINOR: stale ranges, GH_OUT seeding, per-phase reg-AC, ~zero-SKILL.md confirmed) | 7 (3 HIGH: Phase-1 divergent-lib hazard, Phase-4 unset-globals, Phase-3 no-op hollowness; 3 MED: Phase-5 over-bundle, confirm-only inconsistency, server flake; 1 LOW: anchor-is-presence) | 13/13 |

### Disposition (verify-before-fix; cross-checked against cited file:line)
| Finding | Disposition |
|---|---|
| DA-F1 / R-1+4: Phase-1 divergent-lib hazard; landpr-harness never consumed | Fixed — Phase 1 is HARD-dep verify-only (STOP if absent), builds nothing; only extract-fence.sh referenced; run #830 first |
| DA-F2: Phase-4 extracted fences abort on Step-0 globals; seed helper inapplicable | Fixed — concatenate Step-0 + helpers + mode fence into ONE eval; documented global contract |
| DA-F4 / R-3: Phase-3 shim-away → ZSKILLS_ISSUES_DIR unset → no-op hollowness; GH_OUT cross-fence; mixed indent; stale ranges | Fixed — seed ZSKILLS_ISSUES_DIR + assert a row lands; fetch-first for GH_OUT; per-fence strip-indent; ranges corrected |
| DA-F5: Phase-5 over-bundles 3+ sessions | Fixed — split into 5a (briefing units) + 5b (the rest) |
| DA-F6: confirm-only vs fix-issues inconsistency | Fixed — explicit discriminator (runs-a-copy → convert; runs-real-script → confirm-only); add-block/add-example upgraded to convert; create-worktree/draft-tests stay confirm-only (they invoke the real script) |
| DA-F3: Phase-4 live-server boot flake | Fixed — bounded retry boot-poll, not single sleep |
| DA-F7: research-and-go anchor is presence-not-behavior | Fixed — labeled exactly that |
| R-5: per-phase registration AC for new files | Fixed — M3 reg-confirm called out for 5a/5b new files |
| R-6 / R-2: ~zero SKILL.md edits; stale line numbers | Confirmed-correct (no hidden edit; spurious cd/signature live in tests) + ranges marked verify-before-use |
| R-1: Phase-2 8-case parser + $ARGUMENTS/$1 bridge; Phase-3 loose 7-fingerprint gate; Phase-4 transcribed-vs-global + real server; Phase-5 4 importable briefing fns + genuinely-solid confirm-only | Confirmed-correct — ground the plan |
