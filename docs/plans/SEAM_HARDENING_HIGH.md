---
title: Seam Hardening — HIGH-priority skills (exercise production code, kill hollow-green)
created: 2026-05-29
status: active
---

# Plan: Seam Hardening — HIGH-priority skills

## Overview

The seam coverage ledger (`docs/reports/seam-coverage-ledger-2026-05-29.md`)
found 12 of 30 skills whose tests exercise a **re-implementation / embedded
copy** of the skill's bash, not production code — the #809 hollow-green class
(a green test over a path production never takes). This plan hardens the **8
HIGH-priority** skills (`do`, `quickfix`, `run-plan`, `land-pr`, `commit`,
`draft-plan`, `refine-plan`, `work-on-plans`) so their highest-bug-risk
mechanics are exercised through **production code**.

**Goal: a test should run the production logic, not a copy of it.** The
adversarial review of this plan surfaced that the naive "extract-and-run
everything" framing is wrong in three specific ways — this plan is honest
about them (see **Technique selection** below) rather than promising a clean
sweep.

**Scope is exactly these 8 skills.** The MED/LOW backlog is a deliberate
separate follow-up plan. **Non-goals:** no Layer-3/judgment verification;
**never weaken an assertion** during conversion (the converted test must
assert ≥ what it did before, against production code); Cron* orchestration is
harness-tool primitives (not bash) — left above the testable line and noted,
not faked.

## Technique selection — pick per fence, do NOT assume extract-and-run

Three techniques, chosen by the fence's nature (the review proved each is
needed somewhere; using the wrong one produces a vacuous or non-running test):

1. **Extract-and-run (preferred where feasible).** awk-extract the real fenced
   block from the SKILL.md (or source the real script) and execute it. The
   fence almost always reads **input variables set in *other* fences** (e.g.
   land-pr Step 6b reads `STATUS`/`CI_STATUS`/`AUTO_FLAG`/`PR_NUMBER`/… set in
   fences at lines ~65-131,214) — under `set -u` it aborts unless those are
   seeded. **Seeding the INPUTS is legitimate fixture setup** (you control the
   scenario, then run the *real* logic); it is NOT re-implementing the logic.
   The harness MUST provide this input-prelude + external-command shims. This
   is the cost the review flagged (C1): extract-and-run = *seed inputs + shim
   externals + run the real logic fence + assert outputs*.
2. **Parity-gate-the-production-fence (SANCTIONED FALLBACK only).** Where input
   seeding is genuinely intractable, keep an embedded copy BUT add a `grep -qF`
   assertion that the embedded text byte-matches the live production fence, AND
   keep the behavioral assertions running against the copy. **Caveat the review
   raised (C2):** a parity-gate catches *drift* (production changed, copy
   didn't) but NOT *always-wrong* logic — #809 was always-wrong, and a parity
   gate would not have caught it. So parity-gate is a fallback, never the
   default, and must be flagged in the test header as "copy + parity gate, not
   production-executed."
3. **Anchor-grep + honest model-layer label (where there is no production
   code at all).** Some "logic" is model-layer prose, not bash (do/quickfix
   redirect *messages* are markdown table cells the model printf's per prose;
   run-plan defer-backoff is a numbered prose recipe over Cron* tools). There
   is nothing executable to run. A harness that re-derives the messages from
   the same table and asserts they match is **circular/vacuous** (C3). The
   honest move: a cheap `grep -qF` that the **live SKILL.md** carries the
   correct strings (catches the real drift, e.g. do's `--force` vs quickfix's
   `force`), and an explicit note that *emission* is model-layer / above the
   testable line.

**Mandatory per phase (anti-green-by-absence, review M3):** every new
`tests/test-*.sh` MUST be registered in `tests/run-all.sh` AND the phase's
verification MUST confirm the new suite actually appears in the
`bash tests/run-all.sh` output (registered + executed) — not merely that the
file exists. A created-but-unregistered test is itself a #809-class hole.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Shared `tests/lib/` extract + landpr harness (+ pilot) | ⬚ | | |
| 2 — land-pr: extract Steps 6b/7b/7c fences | ⬚ | | |
| 3 — commit: arg-parser extract + caller-loop harness | ⬚ | | |
| 4 — do/quickfix: real mechanics extract + de-hollow message asserts | ⬚ | | |
| 5 — draft-plan + refine-plan: Phase-6/5 fence harnesses | ⬚ | | |
| 6a — work-on-plans: de-hollow mutator tests (test-only) | ⬚ | | |
| 6b — work-on-plans: dispatch-loop seam + sandbox harness (SKILL.md) | ⬚ | | |
| 7 — run-plan: defer-backoff decision + anchor hardening | ⬚ | | |

## Conventions (all phases)

- House style: `set -u`; `pass`/`fail` helpers; final **`Results: N passed, N
  failed`** line (load-bearing — `run-all.sh:36` greps it); non-zero exit on
  failure. **`run-all.sh` uses an explicit `run_suite` list (verified — no
  `tests/*.sh` glob), so `tests/lib/*.sh` will NOT auto-execute as suites, and
  a new test that isn't added to the list silently never runs** — hence the
  M3 registration-confirmation rule above.
- Sandbox: `TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT`; `git init`/`git
  worktree add` for real-worktree fixtures; no network; no real `gh`/PR; PATH-
  shim `gh`/`git`/`pr-monitor.sh` where a fence calls them.
- **No jq** (Python3 stdlib `json` or bash regex).
- **Verify each cited test/fence by reading it before converting** — line
  numbers are indicative (grep the landmark).
- **Preserve assertions:** a converted test asserts ≥ what the prior version
  did, now against production code. Replacing a presence-grep with a behavior
  test is strictly stronger and fine; deleting an assertion is not.
- SKILL.md edits REQUIRE `metadata.version` bump + byte-identical mirror to
  `.claude/skills/<skill>/`; **adding a regular file under a skill dir (e.g.
  Phase 7-A's new script) ALSO triggers the bump** (the trigger is the
  skill-dir change, not only SKILL.md text). Flagged per phase below.
- Each phase ends green on the FULL suite: `bash tests/run-all.sh` — assert
  **exit code 0 AND** the `Overall: N/M passed, 0 failed` line (some suites
  fail by exit code without a "failed" line; run-all wraps per-suite Results
  in ANSI — trust the Overall line + the exit code, not a `^Results:` grep).

## Phase 1 — Shared `tests/lib/` extract + landpr harness (+ pilot)

### Goal
Build the reusable primitives once so phases 2–6 consume them. The review (H2)
flagged that the *hard part* is input-seeding + external-shimming, not fence
selection — the lib must cover both.

### Work Items
- [ ] `tests/lib/extract-fence.sh` — sourceable, exposing:
  - `extract_fence_between <file> <start-regex> <end-regex> [fence-index]
    [strip-indent]` — awk-extract the Nth ```` ```bash ```` block between two
    landmark regexes. MUST handle 3-space-indented fences (`sub(/^   /,"")` via
    `strip-indent`) — needed by `commit/SKILL.md` AND `draft-plan/SKILL.md`
    Phase-5 fences.
  - `extract_sentinel_block <file> <begin-regex> <end-regex>` — extract a slice
    bounded by **inline comment sentinels INSIDE one fence** (review #3: the
    caller loops are bounded by `# === BEGIN CANONICAL /land-pr CALLER LOOP
    ===` / `# === END ===` *within* a single ```` ```bash ```` fence —
    fence-index extraction would grab the whole fence incl. pre-BEGIN lines).
  - Document the **fence-index + mixed-indent fragility** (review M1): when a
    section mixes indented and unindented fences, index counting is
    error-prone — callers should prefer tight start/end regexes over ordinal.
- [ ] `tests/lib/landpr-harness.sh` — sourceable, providing:
  - the git-shim (`mkshim` from `test-fix-issues-sprint-land-pr.sh:104+`).
  - `prepare_result_file` / `patch_caller_loop` (pre-stage `$RESULT_FILE`,
    rewrite `RESULT_FILE=$(mktemp)` → staged path, neuter
    `. …zskills-resolve-config.sh` sources).
  - **`seed_caller_loop_inputs`** — the input-prelude that exports the
    variables a caller-loop / Step-6b fence reads from sibling fences
    (`STATUS`, `CI_STATUS`, `AUTO_FLAG`, `PR_NUMBER`, `BRANCH`, `BRANCH_SLUG`,
    `BASE_BRANCH`, `WORKTREE_PATH`, `CI_TIMEOUT`, `MAIN_ROOT`/`COPY_MAIN_ROOT`,
    `TIMEZONE`, …). This is the C1 fix — the documented seam is the *input
    contract*, not a copy of the logic.
- [ ] Keep helpers THIN — extraction + shim + input-seeding only. Per-test
  assertions/fixtures stay in each test file.
- [ ] `tests/test-extract-fence-lib.sh` — self-test: assert the lib extracts a
  known fence from a real SKILL.md (round-trip diff vs source), strips indent,
  and the sentinel variant slices BEGIN..END correctly. Makes the
  extract-and-run idiom itself a tested primitive.
- [ ] **Pilot:** convert `tests/test-land-pr-tracking-copy.sh` (Step 7c — the
  cleanest, pure filesystem, only `COPY_MAIN_ROOT` to seed) to extract-and-run
  via the lib. Preserve cases a–g. Prove the lib end-to-end before scaling.
- [ ] Register new files in `run-all.sh`; confirm they execute in the rollup.

### Design & Constraints
- Test-infra only — no SKILL.md, no version bump.
- If `seed_caller_loop_inputs` can't be made general, provide per-call-site
  input maps in the consuming tests rather than bloating the lib.

### Acceptance Criteria
- [ ] `extract-fence.sh` (with both extractors) + `landpr-harness.sh` (with
  `seed_caller_loop_inputs`) exist + sourceable; `test-extract-fence-lib.sh`
  passes and fails if extraction breaks.
- [ ] `test-land-pr-tracking-copy.sh` runs the REAL Step 7c fence, preserves
  a–g, FAILS under mutation of the production fence (demonstrate).
- [ ] New suites appear in `bash tests/run-all.sh` output; exit 0; Overall 0
  failed.

### Dependencies
None.

## Phase 2 — land-pr: extract Steps 6b/7b/7c fences

### Goal
Convert the three re-implemented `land-pr` block tests to extract-and-run the
real SKILL.md fences (the logic is NOT in `pr-*.sh` — sourcing unavailable,
extraction is the fidelity path).

### Work Items
- [ ] `tests/test-land-pr-auto-rebase-behind.sh` → extract Step 6b fence
  (`land-pr/SKILL.md` ~445-573) via the lib; **use `seed_caller_loop_inputs`**
  for the ~10 sibling-fence vars (C1); PATH-shim `gh`/`git`/`pr-monitor.sh`
  (queue-driven). Preserve all 10 cases (BEHIND→CLEAN, BEHIND×3→behind-thrash,
  the AUTO/CI/PR_NUMBER/STATUS skip guards, conflict+sidecar, BLOCKED/UNKNOWN
  mapping, initial-CLEAN) + the Layer-1 anchor/schema/mapping greps.
- [ ] `tests/test-land-pr-post-merge-ff.sh` → extract Step 7b fence (~613-644);
  keep the existing REAL git fixtures (no shim); seed only `MAIN_ROOT`.
  Preserve cases a–d + WARN/INFO asserts.
- [ ] (Step 7c done in Phase 1 pilot.)
- [ ] Confirm both suites still execute in the rollup.

### Design & Constraints
- Step 6b calls `pr-monitor.sh` mid-fence — shim to a queued CI_STATUS. Inject
  `MAIN_ROOT`/`REBASE_DIR` via env override or a real worktree fixture.
- Test-files only; no SKILL.md change. Do NOT modify `pr-*.sh`/`block-*`.

### Acceptance Criteria
- [ ] Both tests run the REAL fences; prior cases preserved; each FAILS under
  fence mutation.
- [ ] `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Phase 3 — commit: arg-parser extract + caller-loop harness

### Goal
Replace `test-commit.sh`'s 100%-static-grep coverage with extract-and-run of
the real arg-parser + the real PR-mode caller loop. (`.landed` write/
cherry-pick is already exercised by `test-landed-schema.sh` et al. — leave it.)

### Work Items
- [ ] Arg-parser: extract `commit/SKILL.md` fences (~35-56, ~69-133; 3-space
  indent → `strip-indent`) and run with synthesized `$ARGUMENTS` + config.
  Assert: `pr`→pr; `fix pr format`→commit (mid-string `pr` MUST NOT trigger);
  `pr auto`/`auto`+config=pr→AUTO_FLAG=1 + `auto` stripped from SCOPE_HINT;
  explicit `push`+config=pr→explicit-wins; config=`cherry-pick`→exit 1 with its
  error text; missing/unknown config→commit.
- [ ] Caller loop: **`extract_sentinel_block`** the `commit/modes/pr.md`
  `=== BEGIN…END CANONICAL /land-pr CALLER LOOP ===` (~74-321), `seed_caller_loop_inputs`
  + faked result-file. Drive each STATUS×CI_STATUS; assert LAND_OUTCOME per
  combo, `fulfilled.commit.<id>` ends `complete` (merged/created/pr-ready) vs
  `failed`, `requires.land-pr.<id>` removed, no-result-file path inline cleanup
  + exit 1, `--auto` in LAND_ARGS iff AUTO_FLAG=1.
- [ ] New `tests/test-commit-parsing.sh` (+ caller-loop). **Explicitly migrate
  the static greps from `test-commit.sh` into behavioral assertions** (review
  #8) — do not leave the old presence-greps as the only coverage; the
  behavioral test supersedes them.

### Design & Constraints
- The /land-pr dispatch in `pr.md` is a comment → result-file is the injection
  point; **no `_ZSKILLS_TEST_` seam needed**. Test-files only.

### Acceptance Criteria
- [ ] Real arg-parser + caller-loop executed; assertions above pass + fail
  under mutation; static greps migrated to behavioral.
- [ ] New suite in rollup; `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Phase 4 — do/quickfix: real mechanics extract + de-hollow message asserts

### Goal
Kill the hollow `TRIAGE_SIM`/`REVIEW_SIM` (assert against test-authored bash;
already drifted from do's `--force`). Per the review (C3), split into what IS
shell-testable vs what is model-layer:

### Work Items
- [ ] **Extract-and-run the genuinely-testable mechanics** (these ARE bash):
  the FORCE/ROUNDS/AUTO_FLAG pre-parse (already extracted via
  `extract_parser`/`extract_preflight` — keep), the **VERDICT-parser regex**
  (extract the ```` ```regex ```` / parser fence and run it against APPROVE /
  `REVISE -- r` / `REJECT -- r` / malformed inputs), and the **cron-zombie
  ORDERING** (Phase 0a-before-0c) — drive dynamically, not the static Case-2
  grep.
- [ ] **De-hollow the message assertions (NOT a circular harness).** Delete the
  `*_SIM` heredocs. Replace with a `grep -qF` anchor that the **live**
  `skills/do/SKILL.md` and `skills/quickfix/SKILL.md` redirect-message **table
  rows** + the review override string carry the correct PER-SKILL text — this
  catches the real drift (do=`--force`, quickfix=`force`; the absent ask-user
  target). Add an explicit comment that message **emission** is model-layer
  (the model printf's per prose) — above the testable line; the anchor guards
  the source strings, not emission.
- [ ] **`do` gets its own test** (today it has none — falsely defers to
  quickfix's `force`-worded sim): a `test-do.sh` (or new file) case exercising
  do's REAL verdict-parser + pre-parse + cron-ordering, and the `--force`
  anchor.
- [ ] Preserve every prior 47/48 assertion that targeted real behavior (rc=0 on
  REDIRECT/REJECT path via the parser, no-marker, no-branch, unset-guard) and
  ADD the ask-user target + force-override anchors.
- [ ] (Optional, only if cheap and clearly better — NOT default: technique B,
  add a real ```` ```bash ```` emitter fence to each SKILL.md so emission
  becomes extractable. Heavier — version bump + mirror ×2. Default is the
  anchor approach; choose B only with explicit justification.)

### Design & Constraints
- Do NOT build a harness that re-derives messages from the table and asserts
  they match the table — that is circular (C3).
- Anchor approach is test-only (no bump). Technique B (if chosen) bumps +
  mirrors both SKILL.md.

### Acceptance Criteria
- [ ] No test asserts against a `*_SIM`. The verdict-parser/pre-parse/ordering
  run against production and fail under mutation. A drift in do's or quickfix's
  redirect message FAILS the anchor (demonstrate by editing one message).
- [ ] `do` has its own mechanics test; `--force` asserted.
- [ ] Message emission is documented as model-layer (above the line).
- [ ] New/changed suites in rollup; `bash tests/run-all.sh` exit 0; Overall 0.

### Dependencies
Phase 1.

## Phase 5 — draft-plan + refine-plan: Phase-6/5 fence harnesses

### Goal
Exercise the currently-unexercised Phase-6 (draft-plan) / Phase-5 (refine-plan)
worktree-commit + `/land-pr`-result-parse fences — high-bug-risk (multiple
exit-1 guards) and green-by-absence today.

### Work Items
- [ ] draft-plan: extract Phase-6 worktree-commit fence (~594-665; **3-space
  indent → `strip-indent`**, review #4) + land-pr-result-parse fence (~679-726)
  via the lib; git-init + `git worktree add` sandbox + faked result-file.
  Assert: MAIN-anchored OUTPUT_FILE remaps to TOPLEVEL; FILE_REL normalizes;
  escaping `../*` → exit 1; two-file staged set → exit 1; COMMIT_MSG_SUBJECT
  correct; allow-list parse + unknown-key-ignored + missing-file WARN.
  (args-smoke is already parity-gated — leave it.)
- [ ] refine-plan: create `tests/test-refine-plan.sh` (NONE exists) — same
  harness over Phase-5 fences (~591-671 commit, ~683-731 land-pr) + tracking
  markers. Assert COMMIT_MSG_SUBJECT==`docs(plans): refine <base>`, the exit-1
  guards, marker lifecycle, faked result-file branches.
- [ ] refine-plan **structural edit:** isolate an `## Argument parser` ```` ```bash ````
  fence (its parsing is split between the preamble loop and prose "Detection";
  only AUTO_FLAG is fenced) so plan-file/`rounds N`/`auto` parsing is
  extract-testable. Edits `refine-plan/SKILL.md` → version bump + mirror.
- [ ] Register new files; confirm in rollup.

### Design & Constraints
- No `_ZSKILLS_TEST_` verdict seam (reviewer/DA findings feed plan prose, not
  control flow; convergence is above-line orchestrator judgment).
- Only the refine-plan arg-parser-fence isolation touches a SKILL.md → bump +
  mirror that one. draft-plan work is test-only.

### Acceptance Criteria
- [ ] Both skills' commit + land-pr fences executed through production code;
  exit-1 guards proven under mutation.
- [ ] refine-plan arg-parser in an extractable fence + tested.
- [ ] New suites in rollup; `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Phase 6a — work-on-plans: de-hollow mutator tests (test-only)

### Goal
Fix the confirmed-hollow `test-work-on-plans.sh` (it re-defines the mutator
functions as transcribed copies) — extract the real heredocs. Test-only; split
from the seam work (review H1) so each is a bounded session.

### Work Items
- [ ] Re-point `test-work-on-plans.sh` (~52-180) to awk-extract the
  `subcommands/add-rank-remove.md` mutator heredocs (~156-326) and
  `schedule_under_1h` (~351-367) instead of re-defining them. **The production
  functions are `do_add`/`do_rank`/`do_remove`/`do_default`** (review #2 — the
  test currently mis-names them `skill_*`); rewrite call-sites to `do_*` and
  **co-extract the `ensure_monitor_state` fence (~44) that `do_add` calls**, or
  the sourced function aborts at runtime.
- [ ] Preserve all existing assertions (append/insert/idempotent/digit-prefix-
  reject, rank, remove, default, the #546 `schedule_under_1h` N<60 boundary,
  flock, mirror-parity).
- [ ] Confirm suite still in rollup.

### Design & Constraints
- Test-only; no SKILL.md change, no version bump.

### Acceptance Criteria
- [ ] `test-work-on-plans.sh` extracts the real `do_*` heredocs (+
  `ensure_monitor_state`); no re-defined functions remain; mutating a heredoc
  fails the test; all prior assertions preserved.
- [ ] `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1.

## Phase 6b — work-on-plans: dispatch-loop seam + sandbox harness

### Goal
Add the ONE genuine new seam this plan needs so the sprint dispatch loop is
exercised. **This edits a shipped skill's control flow** (review H1) — spec it
precisely and gate it strictly so the live path is unchanged when the harness
flag is absent.

### Work Items
- [ ] **Seam (`modes/execute.md`):** Step 5's `/run-plan` dispatch is a
  `Skill: {…}` comment + prose failure-detection — not result-file-drivable.
  Refactor Steps 1–8's dispatch loop into an executable fence; gate the
  `/run-plan` dispatch on `_ZSKILLS_TEST_HARNESS=1` to read a per-slug injected
  result (`_ZSKILLS_TEST_RUNPLAN_RESULT_<SLUG>` or a newline slug→text map),
  plus an entry-point unset-guard fence (mirror `do/SKILL.md`'s, so production
  with the flag absent behaves EXACTLY as today). Version bump + mirror.
- [ ] **Sandbox harness:** git-init + worktree; seed `plans/*.md` +
  monitor-state with N ready entries; inject success/failure results. Assert:
  `step.`/`requires.`/`fulfilled.run-plan.<slug>` lifecycle under
  `.zskills/tracking/work-on-plans.<sprint>/`; mode-resolution precedence
  (CLI > per-entry > default_mode > phase) in marker `mode:`; failure-arm
  text-match stops loop + writes report to
  `$ZSKILLS_AUDIT_DIR/work-on-plans-<sprint>.md`; `continue` proceeds past a
  failure; sprint-completion marker + work-state→idle + exit code.
- [ ] Add an arg-parse router test (rules 1–7, usage-error exit 2 — zero
  coverage today).

### Design & Constraints
- The seam is the single genuine `_ZSKILLS_TEST_` addition. **Production-safety:
  the gate must be inert when `_ZSKILLS_TEST_HARNESS` is unset** — add a
  conformance/test assertion that the unguarded path is unchanged (e.g. the
  dispatch still emits the same `Skill: {…}` directive). Version bump + mirror
  for execute.md's parent skill.
- `every`/`stop` Cron* orchestration stays above the testable line — note it.

### Acceptance Criteria
- [ ] `execute.md` dispatch loop has a strictly-gated `_ZSKILLS_TEST_HARNESS`
  seam; production path provably unchanged when the flag is absent.
- [ ] Sandbox test drives the full sprint loop (success + failure arms) through
  production code; arg-router tested.
- [ ] New suite in rollup; `bash tests/run-all.sh` exit 0; Overall 0;
  mirror-parity green.

### Dependencies
Phase 1; Phase 6a (same test file / skill — sequence to avoid churn).

## Phase 7 — run-plan: defer-backoff decision + anchor hardening

### Goal
Resolve run-plan's infeasible-to-extract gap honestly (the defer-backoff state
machine is a numbered prose recipe over Cron* tools, not bash) without faking a
test.

### Work Items
- [ ] **Choose (default A):**
  - **A (factor a decision-script — preferred, makes prose testable):** extract
    the decision rule from `run-plan/SKILL.md` (~485-571) into
    `skills/run-plan/scripts/defer-backoff-decide.sh` taking
    `--counter --cadence --cronlist-match --create-result --case
    --recovery-marker`, emitting the directive vocabulary
    (`DELETE_ALL_MATCHING_CRONS`/`REPLACE_CRON T`/`WRITE_COUNTER`/`PROCEED`);
    SKILL.md prose interprets the directives (Cron* calls stay in prose).
    Re-point `test-runplan-defer-backoff.sh` to source the real script. **This
    adds a regular file under the skill dir → version bump + mirror; AND
    register it in `references/script-ownership.md` — this is MANDATORY, not
    "if applicable"** (review M2; script ownership is a hard conformance gate).
  - **B (anchor-harden — lighter fallback):** keep the re-impl but strengthen
    the anchor-greps (the `in-progress-defers` count + the `*/10|*/30|*/60`
    cadence-table grep in `references/finish-mode.md`) so a cadence-boundary
    change in production fails the test, and document the re-impl as a known
    prose-coupled exception in the test header (per technique 2/3 framing).
- [ ] Cite `test-run-plan-sync-pr-body-progress.sh` as the gold-standard
  template (sources the real script) — no change needed.
- [ ] Preserve all 14 defer-backoff cases + both anchors.

### Design & Constraints
- A: Cron* primitives stay in prose (not shell-testable); the script covers the
  DECISION (the bug-prone part). B: be explicit in the report that this is a
  deliberate non-extraction with compensating anchors.
- Document the choice + rationale in the phase report.

### Acceptance Criteria
- [ ] Either `defer-backoff-decide.sh` exists, is sourced by the test, AND is
  registered in script-ownership.md (A), OR anchors strengthened + exception
  documented (B).
- [ ] 14 cases + anchors preserved; new/changed suite in rollup;
  `bash tests/run-all.sh` exit 0; Overall 0; mirror-parity green if SKILL.md
  touched.

### Dependencies
None (A factors a standalone script + sources it, like the gold-standard
sync-pr-body test; B is anchor-grep only — neither needs Phase 1's lib).

## Plan Quality

**Drafting process:** /draft-plan — 3 research agents (read the real
tests/fences) + 1 adversarial round (reviewer + devil's-advocate).
**Convergence:** Converged at round 1 — the review produced 3 CRITICALs + 2
MAJORs + minors, ALL dispositioned into the plan (the CRITICALs reshaped the
core technique framing and Phase 4; Phase 6 was split per H1). 0 substantive
issues left open. (An API interruption occurred between review and refine; the
refine was completed on resume against the captured findings.)
**Remaining concerns:** None blocking. The honest residue, now encoded in the
plan: (1) do/quickfix message *emission* and run-plan defer-backoff Cron*
orchestration are model-layer/harness-tool, above the shell-testable line — the
plan guards their source strings/decisions, not emission; (2) deep-state fences
require input-seeding (legitimate fixture setup, spec'd in Phase 1's
`seed_caller_loop_inputs`); (3) Phases 6b/7-A change shipped skills to add
testability — gated strictly and version-bumped, flagged for careful review.

### Round History
| Round | Reviewer | Devil's Advocate | Resolved |
|-------|----------|------------------|----------|
| 1 | 8 (2 MAJOR: Phase-6 `do_*`+`ensure_monitor_state` co-extract; lib sentinel-extraction gap. 6 MINOR) | 6 (3 CRITICAL: extracted fences need input-seeding; extract-vs-parity ROI; Phase-4 table-harness circular. 2 HIGH: Phase-6 over-scoped + production-mutation; lib under-specs the hard part. MED: ordinal-fragility, Phase-7 script-ownership, no-registration-check) | 14/14 |

### Disposition (verify-before-fix; each cross-checked against cited file:line)
| Finding | Disposition |
|---|---|
| DA-C1 extracted fences read sibling-fence vars → abort under `set -u` | Fixed — Technique 1 redefined as seed-inputs+shim+run; Phase 1 adds `seed_caller_loop_inputs` |
| DA-C2 parity-gate ROI vs extract | Fixed — parity-gate added as Technique 2 SANCTIONED FALLBACK, with the always-wrong-logic caveat; extract stays default |
| DA-C3 Phase-4 table-harness circular | Fixed — Phase 4 rewritten: extract real mechanics; messages → anchor-grep + model-layer label; dropped the circular harness |
| DA-H1 Phase 6 over-scoped + production-mutation | Fixed — split 6a (test-only) / 6b (seam); 6b adds production-safety gate-inert assertion |
| DA-H2 / R#3 lib under-specs hard part / sentinel extraction | Fixed — Phase 1 adds `seed_caller_loop_inputs` + `extract_sentinel_block` |
| R#2 Phase-6 `skill_*` vs `do_*` + `ensure_monitor_state` | Fixed — Phase 6a names `do_*`, co-extracts `ensure_monitor_state` |
| DA-M3 / no-registration-check (green-by-absence) | Fixed — mandatory per-phase "confirm suite in rollup" rule |
| R#4 draft-plan Phase-5 fence is 3-space-indented | Fixed — strip-indent flagged in Phase 5 |
| R#5 run-all `tests/lib/` glob worry | Fixed — Conventions state it's an explicit list (verified), glob worry dropped |
| R#6 / M2 Phase-7 version-bump cause + script-ownership "if applicable" | Fixed — bump cause corrected (skill-dir file add); script-ownership registration made MANDATORY |
| R#7 Phase-7 false Phase-1 dependency | Fixed — Phase 7 deps corrected to none |
| R#8 Phase-3/6 "preserve assertions" under-specified | Fixed — Phase 3 explicitly migrates static greps → behavioral |
| R#1 / DA confirm: all 5 feasibility claims (table-not-bash, fences-not-in-scripts, prose-recipe, hollow re-defs, comment-dispatch) | Confirmed-correct — no change; they ground the plan |
| M1 ordinal+mixed-indent fragility | Fixed — documented in Phase 1; callers prefer tight regexes |
