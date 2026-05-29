---
title: Skill Verification — Layer-1 Smokes + Layer-2 Dogfooding Measurement
created: 2026-05-28
status: complete
---

# Plan: Skill Verification — Layer-1 Smokes + Layer-2 Dogfooding Measurement

## Overview

Implements the Layer-1 and Layer-2 verification coverage identified by the
skill coverage ledger (`docs/reports/skill-coverage-ledger-2026-05-28.md`).
Per the 3-layer model (`feedback_canary_job_a_b_equivocation`): Layer 1 =
deterministic surface → shell smokes, CI-gated; Layer 2 = integration
reality → MEASURED dogfooding (not duplicated); Layer 3 = LLM-judgment →
**explicitly out of scope, not touched by this plan.**

**Key scope correction from research** (recorded so `/run-plan` agents don't
re-expand): of the 8 skills the ledger nominated for Layer-1 work, only **4
have a genuine executable behavioral surface** a shell smoke can drive
(fix-report, draft-plan, add-example, add-block). The other **4 are
LLM-judgment-bound with no executable surface** (doc, qe-audit,
session-report, review-feedback) — their only deterministic surface is
static SKILL.md structure, which overlaps `test-skill-conformance.sh`. The
plan therefore splits: behavioral smokes for the 4 strong skills (Phase 1),
minimal static-conformance additions for the 4 weak skills folded into the
existing conformance test (Phase 3), NOT four manufactured behavioral smoke
files. This is deliberate non-over-engineering: don't build behavioral
tests where there is no behavior.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Behavioral smokes for the 4 strong skills | ✅ Done | `398186b` | 4 smoke files (fix-report/draft-plan/add-example/add-block) |
| 2 — Retire CANARY_BYPASS_DETECT (add the one missing case) | ✅ Done | `4f87f61` | C32 flip added; canary archived; README row removed |
| 3 — Minimal static-conformance for the 4 weak skills | ✅ Done | `9d99d4e` | conformance invariants for doc/qe-audit/session-report/review-feedback |
| 4 — Layer-2 dogfooding measurement (briefing subcommand) | ✅ Done | `c14fc6f` | briefing.py dogfooding + test; landed via PR #795 |

## Conventions all phases must follow

Researched from existing `tests/test-*.sh` (`test-do.sh`,
`test-fix-issues-bootstrap.sh`, `test-cleanup-merged-ahead-gate.sh`,
`test-commit.sh`):

- **Harness boilerplate** every new `tests/test-*.sh` copies:
  ```bash
  #!/bin/bash
  set -u
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  PASS_COUNT=0; FAIL_COUNT=0
  pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
  fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }
  # ... cases ...
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  [ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
  ```
  The final `Results: <N> passed, <N> failed` line is **load-bearing** —
  `tests/run-all.sh:36` greps `^Results: [0-9]+ passed` to roll up counts,
  and the exit code flips `OVERALL_EXIT`.
- **Registration:** add one `run_suite "test-<name>.sh" "tests/test-<name>.sh"`
  line to `tests/run-all.sh` (the block around lines 99-107).
- **Sandboxing:** `TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT`; `git init -q -b main`
  a throwaway repo; stub binaries (`gh`, `git` where needed) into a `$STUBDIR`
  prepended to `PATH`. NO network, NO real `gh`/PR dispatch.
- **Skill bash is not sourceable** (it lives in `SKILL.md` fenced blocks).
  Use the established **extract-or-embed + parity-gate** pattern: either
  `awk`-extract the target fenced block from `SKILL.md` at runtime and run
  it (preferred — no drift), OR embed a faithful copy AND add a
  `grep -qF` parity assertion on the load-bearing fingerprint lines so
  source drift fails the test. Both are accepted in-repo
  (`test-cleanup-merged-ahead-gate.sh:105-109` extracts;
  `test-fix-issues-bootstrap.sh:81-152` embeds+parity).
- **No jq** — Python 3 stdlib `json` or bash regex (`BASH_REMATCH`).
- **Skill-versioning:** any `skills/**/SKILL.md` or `block-diagram/**/SKILL.md`
  edit (including a fingerprint comment) requires a `metadata.version` bump
  via `bash scripts/frontmatter-set.sh <skill>/SKILL.md metadata.version
  "$(TZ=... date +%Y.%m.%d)+$(scripts/skill-content-hash.sh ...)"`. Phases
  that ONLY add test files / scripts touch no SKILL.md and need no bump —
  prefer that where possible.

## Phase 1 — Behavioral smokes for the 4 strong skills

### Goal
Add CI-gated shell smokes for the deterministic executable surface of
fix-report, draft-plan, add-example, and add-block — the four skills with a
real bash surface a smoke can drive without invoking an LLM.

### Work Items
> **Line numbers below are indicative — grep the named landmark, do not
> trust the exact line.** Several citations were found off-by-one in review
> (e.g. fix-report's worktree loop is at `for wt in` ≈ line 352, not 351).
> The implementing agent MUST locate each block by its content fingerprint.

- [ ] `tests/test-fix-report-smoke.sh` covering:
  - **Worktree-gate exit-11** (grep `run /update-zskills` near the preamble,
    ≈ SKILL.md:43-69): run the preamble with the `ensure-worktree.sh` helper
    path pointed at a nonexistent file → assert exit 11 + the actionable
    "run /update-zskills to repair" message.
  - **`.landed`-status scan classification** (grep `for wt in` / the
    `case "$STATUS"` block, ≈ SKILL.md:352-388): the scan enumerates
    worktrees via `git worktree list`, so the fixture MUST register real
    worktrees with `git worktree add` (NOT bare `mkdir`) in a `git init`
    sandbox, each carrying a crafted `.landed`. **Use the ACTUAL status
    vocabulary the `case` arms recognize** (verified in review): `full|landed`,
    `pr-ready`, `pr-ci-failing`, `pr-failed`, `conflict`,
    `failed|direct-push-failed|direct-verify-failed`, `pr-state-unknown`,
    `partial`, and the `*)` UNKNOWN catch-all. There is **NO `not-landed`
    arm** — do not craft that fixture expecting a named classification (it
    falls to UNKNOWN). The **ACTIVE** classification is the *no-`.landed`-file*
    branch (the `else`), NOT a status value. Assert each real status →
    correct SAFE / NEEDS-ATTENTION / FAILED / UNKNOWN bucket, plus a
    no-`.landed` worktree → ACTIVE.
  - **PIPELINE_ID sanitization**: assert the constructed
    `FIX_REPORT_PIPELINE_ID` is routed through `sanitize-pipeline-id.sh`
    (drive with a dirty slug, assert collapsed to `[a-zA-Z0-9._-]`).
- [ ] `tests/test-draft-plan-args-smoke.sh` covering:
  - **OUTPUT_FILE / TRACKING_ID resolution** (grep the `for tok in` arg loop,
    ≈ SKILL.md:69-81): NOTE this block's first line `source`s
    `zskills-paths.sh` and depends on `$CLAUDE_PROJECT_DIR` + `$ARGUMENTS` +
    `$ZSKILLS_PLANS_DIR` — it is **NOT self-contained**, so use the
    **embed+parity** approach (embed a faithful copy, stub `$ZSKILLS_PLANS_DIR`,
    add a `grep -qF` parity gate on the `for tok in`/`case */*.md)` fingerprint
    lines), NOT extract-and-run. Feed `$ARGUMENTS` strings — `plans/X.md ...`
    (path token used as-is), `X.md ...` (bare → `$ZSKILLS_PLANS_DIR/X.md`),
    and no-`.md` (timestamped fallback) → assert resolved OUTPUT_FILE +
    lowercased-kebab TRACKING_ID.
  - **AUTO_FLAG regex** (grep the `[aA][uU][tT][oO]` regex, ≈ SKILL.md:144-148):
    this block IS self-contained (pure `[[ =~ ]]`) → extract-and-run is fine.
    Assert `auto` and `AUTO` set flag=1; `automatic`, `autopilot`, `auto-land`
    (no whitespace boundary) do NOT. Pin the whitespace-anchored boundary.
- [ ] `tests/test-add-example-smoke.sh` covering (block-diagram skill):
  - **3-tier PIPELINE_ID resolution** (≈ SKILL.md:69-90): tier-1
    `ZSKILLS_PIPELINE_ID` env, tier-2 `.zskills-tracked` file, tier-3
    `add-example.${NAME_SLUG}` fallback → assert each tier wins in order.
  - **fulfilled-marker write**: run the fulfillment block → assert
    `fulfilled.add-example.<slug>` exists at `$MAIN_ROOT/.zskills/tracking/<pid>/`
    with the ACTUAL fields the `printf` writes (verified in review):
    `skill:`, `name:` (NOT `id:`), `status:`, `date:`.
- [ ] `tests/test-add-block-smoke.sh` covering (block-diagram skill):
  - **3-tier PIPELINE_ID + BLOCK_SLUG sanitization + tracking mkdir**
    (SKILL.md:88-102): drive each tier; assert slug sanitization is
    deterministic and the tracking dir is created under `$MAIN_ROOT`.
- [ ] Register all four in `tests/run-all.sh`.
- [ ] Run `bash tests/run-all.sh`; confirm the four new suites appear in the
  rollup and pass, and no previously-passing suite regresses (compare pass
  count to baseline, not just "0 failed").

### Design & Constraints
- Use **extract-and-run** (awk-extract the fenced block from the real
  `SKILL.md`) wherever the block is self-contained, so the test exercises
  the actual source and cannot drift. Where the block depends on
  surrounding shell state, embed a faithful copy AND add a `grep -qF`
  parity gate on 1-2 fingerprint lines (cite the exact lines in a comment).
- `sanitize-pipeline-id.sh` and `zskills-paths.sh`/`zskills-resolve-config.sh`
  are already covered by their own tests — these smokes may *rely* on them,
  must NOT re-test them.
- These four test files touch NO SKILL.md → no `metadata.version` bump in
  this phase.
- All fixtures synthesized in `mktemp -d`; no network; no real `gh`.

### Acceptance Criteria
- [ ] Four new `tests/test-*-smoke.sh` files exist, each emitting the
  canonical `Results:` line and exiting non-zero on failure.
- [ ] Each is registered in `tests/run-all.sh` and runs in the rollup.
- [ ] **Binding is real, not decorative** (CI-checkable form): each smoke
  either (a) extract-and-runs the actual fenced block from `SKILL.md` at
  runtime, OR (b) embeds a copy AND contains a `grep -qF` parity assertion
  against a named fingerprint line of the source block. The acceptance check
  is "the extract call or the parity `grep -qF` is present and references the
  real fingerprint" — not a manual mutate-and-revert ritual.
- [ ] `bash tests/run-all.sh` total pass count = prior baseline + the new
  cases; zero failures; zero regressions (compare explicit pass COUNT to
  baseline, not just "0 failed").

### Dependencies
None (additive test files + one run-all.sh edit).

## Phase 2 — Retire CANARY_BYPASS_DETECT (add the one missing case)

### Goal
Convert the `CANARY_BYPASS_DETECT.md` markdown canary to shell coverage by
adding the single behavioral case the existing test lacks, then retire the
markdown.

### Work Items
- [ ] Add **one case** to `tests/test-block-bypassed-land-pr.sh`:
  **state-transition flip** — write a matching `requires.land-pr.<id>`
  marker, run a `gh pr create` envelope → assert Pattern 2 wording
  (`declared an intent to` / "land-pr invocation appears to have errored");
  then `rm` the marker and re-run the same envelope → assert Pattern 1
  wording (`outside a caller skill`). This proves the Pattern-2→Pattern-1
  selection is driven by marker presence/absence within one fixture — the
  only behavioral assertion the canary makes that the existing test's
  separate C1 (no marker → Pattern 1) + C3 (mismatched marker → Pattern 1)
  cases don't make as a *transition within one fixture*.
  (Do NOT add the previously-considered "pin Pattern-1 anchor on the
  empty-anchor deny cases" item — review confirmed those are `gh pr merge`
  deny checks that already assert `deny` + the `STOP:` string + valid JSON;
  they are NOT vacuous, and pinning a *create*-path Pattern-1 anchor on a
  *merge* deny would be wrong.)
- [ ] `git mv docs/plans/CANARY_BYPASS_DETECT.md docs/plans/archive/canaries/CANARY_BYPASS_DETECT.md`
  (retire — its behavioral coverage now fully lives in the shell test).
- [ ] Update the dangling doc reference: `README.md` has a table row
  advertising `CANARY_BYPASS_DETECT` as a live artifact (grep
  `CANARY_BYPASS_DETECT` in `README.md`) — update or remove that row so it
  reflects the retirement. (The `docs/plans/LAND_PR_BYPASS_HARDENING.md`
  mentions are historical prose about the hook's origin and may stay.)
- [ ] Run `tests/test-block-bypassed-land-pr.sh`; confirm the new case
  passes and the suite's `Results:` count increased by exactly the cases
  added.

### Design & Constraints
- Research finding (verify before relying): the existing
  `tests/test-block-bypassed-land-pr.sh` is already a strict SUPERSET of the
  canary on the static decision matrix (deny set, allow set, Pattern-2 on
  matching marker, marker-shape, wrapper carve-out) — ~30 `assert_deny`/
  `assert_allow` cases vs the canary's ~13, plus FP/recursion cases the
  canary never had. The ONLY
  unique behavioral coverage is the state-transition flip. The implementing
  agent MUST re-confirm this by reading both files before adding the case —
  do not add redundant cases.
- The canary's setup-step assertions (artifacts exist, run-all.sh includes
  the test, settings.json registration, conformance green) are owned by
  `test-hook-helper-drift.sh`, `run-all.sh`'s own listing, and
  `test-skill-conformance.sh` — retiring the canary loses none of them.
- No SKILL.md touched → no version bump. The hook (`block-bypassed-land-pr.sh`)
  is NOT modified.

### Acceptance Criteria
- [ ] `tests/test-block-bypassed-land-pr.sh` has the state-transition flip
  case; it passes and would fail if the hook's marker-driven Pattern
  selection broke.
- [ ] `docs/plans/CANARY_BYPASS_DETECT.md` is moved to
  `docs/plans/archive/canaries/`.
- [ ] `bash tests/run-all.sh` green; no regression.

### Dependencies
None.

## Phase 3 — Minimal static-conformance for the 4 weak skills

### Goal
Give the 4 LLM-judgment-bound skills (doc, qe-audit, session-report,
review-feedback) the only deterministic coverage they admit — thin static
invariants — by adding targeted assertions to the EXISTING
`tests/test-skill-conformance.sh`, NOT by manufacturing behavioral smoke
files for surfaces that have no behavior.

### Work Items
- [ ] For each of the 4 weak skills, first GREP `tests/test-skill-conformance.sh`
  to see what it already asserts about that skill (the ledger shows
  qe-audit=14, doc=0, session-report=0, review-feedback=0 conformance
  mentions). Only ADD assertions for genuinely-uncovered static invariants:
  - **doc**: the documented modes `blocks | examples | newsletter` are
    present in the argument-hint / mode prose; `disable-model-invocation: true`.
  - **qe-audit**: meta-command precedence prose (stop/next/now) present; the
    `## Files to change` issue-body format requirement present.
  - **session-report**: the report-format template structure + the
    "no bulk scans" prohibition present.
  - **review-feedback**: the severity-label mapping table + the
    one-issue-per-entry rule present.
- [ ] If a proposed assertion would duplicate an existing conformance check,
  SKIP it (record "already covered" in the phase notes). It is acceptable
  for this phase to add few or zero assertions for a skill if conformance
  already covers it — that is a finding, not a failure.
- [ ] Run `tests/test-skill-conformance.sh`; confirm green.

### Design & Constraints
- These are **static greps on SKILL.md content**, not behavioral tests.
  They guard against accidental deletion of a documented mode/format/rule —
  the only deterministic property these skills have.
- Do NOT create new `test-*-smoke.sh` files for these 4 skills. The honest
  conclusion from research is that a dedicated behavioral file would test
  nothing real. Folding into conformance is the non-over-engineered choice.
- This phase edits `tests/test-skill-conformance.sh` only (a test file) —
  no SKILL.md, no version bump.

### Acceptance Criteria
- [ ] `tests/test-skill-conformance.sh` asserts the listed static invariants
  for each weak skill that isn't already covered.
- [ ] The phase notes record, per skill, which invariants were added vs
  already-covered.
- [ ] `bash tests/run-all.sh` green; no regression.

### Dependencies
None.

## Phase 4 — Layer-2 dogfooding measurement (briefing subcommand)

### Goal
MEASURE real per-skill usage from existing durable signals and surface it —
display-first, with NO flaky hard-assert CI gate.

### Work Items
- [ ] Add a dogfooding measurement to `skills/briefing/scripts/briefing.py`
  (new subcommand, e.g. `briefing.py dogfooding [--since=<period>]`, reusing
  the existing `parse_landed`, `query_pr_state`, `parse_period`
  infrastructure). It:
  - Scans `.landed` markers across worktrees, reading the **`source:` field**
    (extend `parse_landed` to capture `source` — it currently does not) and
    `status:`/`ci:`/`pr_state:` to count only SUCCESSFUL lands
    (`status: landed`/`full` with `pr_state: MERGED` or `ci: pass`).
  - Backfills beyond the on-disk window with `gh pr list --state merged
    --json number,title,mergedAt` over `--since`, mapping conventional-commit
    scope prefixes to skills (best-effort; clearly labeled as a weaker
    signal than `.landed`). **The gh call MUST route through briefing.py's
    existing `run()` helper** (which catches all exceptions → '' on a missing
    `gh`) so the test is hermetic without a live `gh`. Do NOT add a raw
    `subprocess.run(['gh', ...])` that would raise `FileNotFoundError` and
    crash a PATH-stripped test.
  - **Canonicalizes** source variants to a single skill name (e.g.
    `fix-issues`, `fix-issues-sprint`, `fix-issues-pr-mode-*` → `fix-issues`)
    via an explicit map.
  - Emits per-skill `{landed_count, merged_pr_count, last_seen}` for the
    window.
- [ ] Surface it as a briefing section (and document the subcommand in
  `skills/briefing/SKILL.md`).
- [ ] **Mirror to the install lane.** This phase edits BOTH
  `skills/briefing/scripts/briefing.py` and `skills/briefing/SKILL.md` (the
  doc). The mirror-parity gate (`tests/test-skills-mirror-parity.sh`)
  requires the `.claude/skills/briefing/` copies be byte-identical, so copy
  the edited `briefing.py` to `.claude/skills/briefing/scripts/briefing.py`
  AND the edited `SKILL.md` to `.claude/skills/briefing/SKILL.md`. Bump
  `metadata.version` in the SOURCE SKILL.md (and mirror) per skill-versioning.
- [ ] Add `tests/test-briefing-dogfooding.sh` (or extend an existing
  briefing test) that runs the aggregation against a **fixture set of
  synthesized `.landed` files** in a tmpdir (no network; `gh` stubbed or the
  gh-backfill path disabled via a flag) and asserts the per-skill counts and
  canonicalization are correct and deterministic.
- [ ] Do NOT add a hard-assert "skill X ran ≥N times this week" CI gate — it
  false-fails on quiet periods and trains people to ignore the signal. At
  most, the displayed report may flag `0 in <window>` per skill as advisory
  text for a human to read.

### Design & Constraints
- `.landed` is the strongest signal (its `source:` field names the skill,
  and `ci:`/`pr_state:` distinguish success from attempt) but is gitignored
  and lives in `/tmp` worktrees → a rolling on-disk window, not a permanent
  ledger. `gh` merged-PR history is the durable backfill but only names the
  subsystem touched, not the skill → weaker per-skill attribution. Use both,
  label fidelity.
- Branch-name prefixes are convention, not invariant (the prefix is
  caller-supplied in `create-worktree.sh`), and cannot distinguish success
  from an abandoned branch → use as a hint only, never as the sole counter.
- `.zskills/tracking/` markers are ephemeral by design (gitignored,
  expire/cleared per-iteration) → NOT a measurement source.
- The briefing SKILL.md doc edit requires a `metadata.version` bump AND a
  mirror to `.claude/skills/briefing/SKILL.md`; the briefing.py edit requires
  a mirror to `.claude/skills/briefing/scripts/briefing.py` (no bump on its
  own, but the mirror-parity gate covers it). New `tests/` files need no bump
  and no mirror.

### Acceptance Criteria
- [ ] `briefing.py dogfooding --since=<period>` prints per-skill successful-usage
  counts with correct canonicalization, sourced from `.landed` + (labeled)
  gh backfill.
- [ ] `tests/test-briefing-dogfooding.sh` asserts the aggregation against
  synthesized fixtures, deterministically, with no network dependency, and
  is registered in `run-all.sh`.
- [ ] NO hard-assert per-skill usage-floor test exists (verify: grep the new
  test for any `must have run`/threshold assertion — there should be none).
- [ ] `.claude/skills/briefing/{SKILL.md,scripts/briefing.py}` are
  byte-identical to source; `tests/test-skills-mirror-parity.sh` green;
  `metadata.version` bumped in briefing SKILL.md.
- [ ] `bash tests/run-all.sh` green; no regression.

### Dependencies
None (independent of Phases 1-3; may run in any order).

## Plan Quality

**Drafting process:** /draft-plan with 1 round of adversarial review
(reviewer + devil's-advocate, dispatched in parallel) on top of 3 parallel
research agents.
**Convergence:** Converged at round 1 — all 15 findings dispositioned
(11 fixed, 4 confirmed-correct / no-action). Remaining substantive issues: 0.
**Remaining concerns:** None blocking. The line-number citations are
explicitly marked indicative (grep-the-landmark) because review found them
fragile/off-by-one; this is a known, mitigated risk, not an open issue.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 5 (1 MAJOR add-example `name:` not `id:`, 1 MAJOR fix-report no `not-landed` arm, 3 MINOR) | 10 (2 HIGH = embed-not-extract for draft-plan + fix-report phantom status, 5 MED/LOW gaps, 3 confirmed-correct) | 15/15 |

### Disposition table (verify-before-fix)
| Finding | Evidence | Disposition |
|---|---|---|
| R1 add-example marker is `name:` not `id:` | Verified (add-example SKILL.md:87-89) | Fixed (Phase 1 work item) |
| R2/DA-F2 fix-report has no `not-landed` arm; ACTIVE = no-`.landed` else | Verified (fix-report SKILL.md case arms) | Fixed (corrected status vocabulary + ACTIVE definition) |
| R3 mutation-test acceptance non-reproducible | Judgment | Fixed (replaced with parity-assertion-present check) |
| R4/DA-F7 empty-anchor deny cases not vacuous; pinning anchor wrong | Verified (test lines 178-185, 239-248) | Fixed (dropped the optional item, explained why) |
| R5 doc invariants already in frontmatter | Verified (doc SKILL.md:3-4) | Fixed (Phase 3 already had grep-first skip rule; reaffirmed) |
| DA-F1 draft-plan OUTPUT_FILE block not self-contained (sources helper) | Verified (draft-plan SKILL.md:70) | Fixed (mandated embed+parity for that block) |
| DA-F3 fix-report scan needs real `git worktree add` fixtures | Verified (fix-report SKILL.md `git worktree list`) | Fixed (Phase 1 work item) |
| DA-F4 line numbers fragile/off-by-one | Verified (`for wt in` ≈352) | Fixed (added grep-the-landmark banner) |
| DA-F5 README.md dangling CANARY_BYPASS_DETECT ref | Verified (README.md:367; no test/hook refs) | Fixed (added Phase 2 README update item) |
| DA-F6 case-count is ~30 not 31 | Verified (`grep -cE '^assert_'` = 30) | Fixed (softened to ~30) |
| DA-F8 Phase 4 gh must route through `run()` | Verified (briefing.py:102-110) | Fixed (mandated run() routing) |
| DA-F10 Phase 4 mirror-parity not called out | Verified (no mirror mention in draft) | Fixed (added mirror work item + acceptance) |
| DA-F9/R parse_landed lacks `source:` | Verified (briefing.py:142-200) | Confirmed-correct — plan's extend-parse_landed claim is right; no change |
| DA-F7 (dup of R4) | — | Confirmed-correct |
| Phase ordering / /run-plan parseability / em-dash headers | Verified (reviewer) | Confirmed-correct — no change |
