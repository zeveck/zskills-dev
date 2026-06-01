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
| 1 — Shared `tests/lib/` extract + landpr harness (+ pilot) | ✅ Done | `259bfe3` | lib + self-test + Step-7c pilot; 6903/6903 pass |
| 2 — land-pr: extract Steps 6b/7b/7c fences | ✅ Done | `b4ad4c0` | 6b+7b+7d extract-and-run; +UNKNOWN re-poll; 6935/6935 pass |
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
    variables a caller-loop / Step-6b / Step-7d fence reads from sibling fences
    (`STATUS`, `CI_STATUS`, `AUTO_FLAG`, `PR_NUMBER`, `BRANCH`, `BRANCH_SLUG`,
    `BASE_BRANCH`, `WORKTREE_PATH`, `CI_TIMEOUT`, `MAIN_ROOT`/`COPY_MAIN_ROOT`,
    `TIMEZONE`, …). **Also seed the Step-6b/7d auto-rebase + terminal-drive
    inputs proactively (m5)** so Phase 2 consumes the lib without amending it:
    `REBASE_STDERR_FILE` (the sidecar stderr path; declared as an input at
    `land-pr/SKILL.md:174` and written via `REBASE_STDERR` at :466-513),
    `UNKNOWN_POLL_MAX` (the bounded UNKNOWN re-poll cap, `land-pr/SKILL.md:485`),
    and the Step-7d terminal-drive vars `PR_STATE` / `TW_ITER` / `REASON`
    (`land-pr/SKILL.md:705-882`). This is the C1 fix — the documented seam is
    the *input contract*, not a copy of the logic. The PUBLIC contract of
    `extract_fence_between` / `extract_sentinel_block` is FROZEN (the sibling
    plan SEAM_HARDENING_REST hard-depends on it); only `seed_caller_loop_inputs`
    grows, which is additive.
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
- [ ] `tests/test-land-pr-auto-rebase-behind.sh` → extract the Step 6b fence
  (`land-pr/SKILL.md:456-613`, plus the **second fence at 619-646** that
  follows the same step) via the lib; **use `seed_caller_loop_inputs`** for the
  sibling-fence vars (C1); PATH-shim `gh`/`git`/`pr-monitor.sh` (queue-driven).
  **NOTE the #875 drift (M2):** production now opens the step with a bounded
  **UNKNOWN→definite re-poll prelude** (`land-pr/SKILL.md:481-498`,
  `UNKNOWN_POLL_MAX=5`, `sleep 4` between probes) BEFORE the `BEHIND` loop;
  the current re-impl test maps `UNKNOWN→auto-rebase-blocked` and breaks
  (`tests/test-land-pr-auto-rebase-behind.sh:263-266`) — a live hollow-green
  the conversion must close. Enumerate the **10 cases** the converted suite
  preserves + the new one:
  1. BEHIND→CLEAN (single rebase, clears)
  2. BEHIND×3→behind-thrash (loop cap, `auto-rebase-max-iters`)
  3. AUTO_FLAG=0 skip-guard
  4. CI_STATUS≠green skip-guard
  5. PR_NUMBER-empty skip-guard
  6. STATUS≠merge-eligible skip-guard
  7. conflict → `--abort` + sidecar `REBASE_STDERR_FILE` populated
  8. BLOCKED mapping
  9. UNKNOWN mapping (terminal, after re-poll exhausts)
  10. initial-CLEAN (no rebase needed)
  11. **NEW (M2): UNKNOWN-then-BEHIND re-poll** — first `gh` probe returns
     UNKNOWN, a subsequent probe returns BEHIND; assert the re-poll prelude
     resolves to BEHIND and the rebase fires (not a silent no-op). Shim the
     `sleep` to a no-op and queue the `gh pr view --json mergeStateStatus`
     outputs. `seed_caller_loop_inputs` must export `REBASE_STDERR_FILE`
     (:174) and `UNKNOWN_POLL_MAX` (:485).
  Keep the Layer-1 anchor/schema/mapping greps.
- [ ] `tests/test-land-pr-post-merge-ff.sh` → extract Step 7b fence
  (`land-pr/SKILL.md:894-925`); keep the existing REAL git fixtures (no shim);
  seed only `MAIN_ROOT`. Preserve cases a–d + WARN/INFO asserts.
- [ ] (Step 7c — Step 7c fence is now `land-pr/SKILL.md:941-966`; done in
  Phase 1 pilot.)
- [ ] **Step 7d (C3) — `tests/test-land-pr-drive-automerge.sh` (NEW):** the
  ~178-line Step 7d added by #871 (`land-pr/SKILL.md:648` heading, fence
  **705-882**) drives a queued auto-merge to a terminal state, **re-using the
  Step-6b rebase machinery** (`gh pr view` poll → BEHIND-detect → rebase →
  `push --force-with-lease`) — so it carries the SAME hollow-green risk and is
  entirely outside the existing case-set. **Prefer ADDING cases** (cheaper than
  scoping out, and re-uses the harness): extract the 705-882 fence via the lib;
  `seed_caller_loop_inputs` exports the 7d inputs (`PR_STATE`, `TW_ITER`,
  `REASON`, plus the shared `PR_NUMBER`/`CI_TIMEOUT`/`BRANCH_SLUG`); shim `gh`
  and `git` queue-driven and shim `sleep` to a no-op. Preserve these terminal
  arms (each maps to a distinct `>&2` line in the fence):
  - MERGED reached (`:745` INFO) → loop exits success
  - BEHIND post-merge-request (`:776` INFO) → rebase + `--force-with-lease`
    (`:807` retry WARN on push failure)
  - mergeStateStatus=other / waiting-for-queue (`:843` INFO) → continue polling
  - surfacing non-recoverable state (`:848` WARN) → break + surface
  - no-terminus-within-timeout (`:870` WARN) → PR left OPEN, `REASON` set
- [ ] Confirm all suites still execute in the rollup.

### Design & Constraints
- Step 6b and Step 7d both call `gh pr view --json mergeStateStatus` mid-fence
  — shim `gh` to a queued mergeStateStatus sequence (the UNKNOWN re-poll and
  the 7d terminal-drive both consume a *sequence*, not a single value).
  Step 6b also calls `pr-monitor.sh` — shim to a queued CI_STATUS. Inject
  `MAIN_ROOT`/`REBASE_DIR` via env override or a real worktree fixture. Shim
  the in-fence `sleep` calls (UNKNOWN re-poll, 7d poll loop) to no-ops so the
  suite runs fast.
- Test-files only; no SKILL.md change. Do NOT modify `pr-*.sh`/`block-*`.

### Acceptance Criteria
- [ ] All three converted/new suites (auto-rebase-behind, post-merge-ff,
  drive-automerge) run the REAL fences; the 10 prior auto-rebase cases + the
  new UNKNOWN-re-poll case + the 5 Step-7d terminal arms are present; each
  FAILS under mutation of its production fence.
- [ ] The UNKNOWN-re-poll case (M2) proves a UNKNOWN-then-BEHIND sequence
  enters the rebase loop (not a no-op) — closing the live hollow-green.
- [ ] `bash tests/run-all.sh` exit 0; Overall 0 failed.

### Dependencies
Phase 1. (Consumes `seed_caller_loop_inputs`'s Step-6b/7d inputs added in
Phase 1 per m5 — `REBASE_STDERR_FILE`, `UNKNOWN_POLL_MAX`, `PR_STATE`,
`TW_ITER`, `REASON`.)

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
  `=== BEGIN…END CANONICAL /land-pr CALLER LOOP ===` (BEGIN at `pr.md:74`,
  END at `pr.md:312`), `seed_caller_loop_inputs`
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
Kill the hollow `TRIAGE_SIM`/`REVIEW_SIM` heredocs (they assert against
test-authored bash, not production). Per the review (C3), split into what IS
shell-testable vs what is model-layer. **NOTE (M5):** the `*_SIM` heredocs live
ONLY in `tests/test-quickfix.sh` — specifically **Cases 47 and 48**
(`tests/test-quickfix.sh:1431-1569`: `TRIAGE_SIM`@1431, `REVIEW_SIM`@1516).
`tests/test-do.sh` contains **no** `*_SIM` — it already has 19 cases and is
registered at `run-all.sh:110`.

### Work Items
- [ ] **Extract-and-run the genuinely-testable mechanics** (these ARE bash):
  the FORCE/ROUNDS/AUTO_FLAG pre-parse (already extracted via
  `extract_parser`/`extract_preflight` — keep), the **VERDICT-parser regex**
  (extract the parser fence and run it against APPROVE /
  `REVISE -- r` / `REJECT -- r` / malformed inputs), and the **cron-zombie
  ORDERING** (Phase 0a-before-0c) — drive dynamically, not the static Case-2
  grep.
- [ ] **De-hollow the message assertions (NOT a circular harness).** Delete the
  `*_SIM` heredocs (`test-quickfix.sh:1431-1569`, Cases 47/48). Replace with a
  `grep -qF` anchor that the **live** `skills/do/SKILL.md` and
  `skills/quickfix/SKILL.md` redirect-message **table rows** carry the correct
  PER-SKILL text. **Re-anchored drift target (C2):** the original `do=--force`
  vs `quickfix=force` drift target is DEAD — bare `force` was retired in #822
  (`eb75e4c`, predates this plan's draft `ce722ff`); both skills now use dashed
  `--force` uniformly (`do/SKILL.md:73,215`; `quickfix/SKILL.md:64,101`), so
  that anchor can never fire. Re-anchor onto a string that genuinely STILL
  differs per skill:
  - **quickfix-only landing-config soft-redirect** (`quickfix/SKILL.md:271`):
    `Triage: redirecting to /do worktree. Reason: /quickfix requires execution.landing == "pr" (got "worktree").`
    and `:274`'s `/commit` variant — `/do` has **no** landing-config redirect
    at all (its redirects are triage-only), so a grep that this string is
    PRESENT in `quickfix/SKILL.md` and ABSENT-as-`/quickfix`-self-named in
    `do/SKILL.md` catches a real per-skill divergence.
  - **per-skill ask-user target** (the skill names itself): `do/SKILL.md:403`
    `Re-invoke /do with a concrete description …` vs `quickfix/SKILL.md:434`
    `Re-invoke /quickfix with a concrete description …`. Anchor each skill's
    own self-name in its own ask-user row; a copy-paste cross-contamination
    (do's row saying `/quickfix`) fails the anchor.
  Add an explicit comment that message **emission** is model-layer (the model
  printf's per prose) — above the testable line; the anchor guards the source
  strings, not emission.
- [ ] **Convert `test-do.sh` Case 6 to behavioral extract-and-run (C1).**
  `test-do.sh` already exists and is registered, so it does NOT need creating.
  The ONE residual hollow gap is **Case 6 (`tests/test-do.sh:245-254`): it only
  `grep -qF`s the two verdict-parser regex strings against the SKILL.md, it
  never RUNS the parser.** Convert it to extract-and-run (mirror
  `test-quickfix.sh` Case 52): extract `do`'s real verdict-parser fence and
  execute it against `APPROVE` / `REVISE -- r` / `REJECT -- r` / malformed
  inputs, asserting the parsed verdict per input. (do's pre-parse, cron-ordering
  (Case 2), unset-guard, and `--force` are ALREADY covered by the existing 19
  cases — do not duplicate them.)
- [ ] Preserve every prior assertion in **Cases 47 and 48 of `test-quickfix.sh`**
  (the two SIM cases) that targeted real behavior (rc=0 on REDIRECT/REJECT path
  via the parser, no-marker, no-branch, unset-guard) and ADD the re-anchored
  divergent-string anchors (quickfix landing-redirect + per-skill ask-user
  self-name) when the SIMs are deleted.
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
- [ ] No test asserts against a `*_SIM` (Cases 47/48 of `test-quickfix.sh`
  converted). The verdict-parser/pre-parse/ordering run against production and
  fail under mutation.
- [ ] `test-do.sh` Case 6 RUNS the verdict parser (extract-and-run), not a
  grep-only check; it fails under mutation of `do`'s production parser fence.
- [ ] A drift on a genuinely-divergent per-skill string FAILS the anchor:
  demonstrate by editing `quickfix/SKILL.md`'s landing-config soft-redirect
  (`:271`/`:274`) OR a per-skill ask-user self-name (do `:403` / quickfix
  `:434`) and confirming the anchor catches it. (The dead `--force`-vs-`force`
  anchor is NOT used.)
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
- [ ] draft-plan: extract Phase-6 worktree-commit fence (`draft-plan/SKILL.md:638-711`;
  **3-space indent → `strip-indent`**, review #4 — confirmed: line 638 opens
  `   ```bash`) + land-pr-result-parse fence (`:723-772`) via the lib; git-init
  + `git worktree add` sandbox + faked result-file. Assert: MAIN-anchored
  OUTPUT_FILE remaps to TOPLEVEL; FILE_REL normalizes; escaping `../*` → exit 1;
  two-file staged set → exit 1; COMMIT_MSG_SUBJECT correct; allow-list parse +
  unknown-key-ignored + missing-file WARN. (args-smoke is already parity-gated
  — leave it.)
- [ ] refine-plan: create `tests/test-refine-plan.sh` (NONE exists) — same
  harness over Phase-5 fences (`refine-plan/SKILL.md:600-673` commit,
  `:685-734` land-pr) + tracking markers. **Per-skill indent asymmetry (M4):
  refine-plan's commit fence is FLUSH-LEFT (line 600 opens ` ```bash` with no
  3-space body indent) — so it is extracted WITHOUT `strip-indent`, unlike
  draft-plan's indented fence, even though both are the same per-skill-cased
  template.** Also note the commit subject is NOT a standalone literal: it
  drives through a **shared `case "$SKILL"` block at `refine-plan/SKILL.md:662-664`**
  (`refine-plan) COMMIT_MSG_SUBJECT="docs(plans): refine $BASE" ;;`), so the
  assertion `COMMIT_MSG_SUBJECT==docs(plans): refine <base>` must run the fence
  with `SKILL=refine-plan` set and read the case output. Assert: that subject,
  the exit-1 guards, marker lifecycle, faked result-file branches.
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
  `subcommands/add-rank-remove.md` mutator heredocs (`do_add`@179 …
  `do_default`@306, i.e. **~179-326**) and `schedule_under_1h` (`@369`) instead
  of re-defining them. **The production functions are
  `do_add`/`do_rank`/`do_remove`/`do_default`** (review #2 — the test currently
  mis-names them `skill_*`); rewrite call-sites to `do_*` and **co-extract the
  `ensure_monitor_state` fence (`@45`) that every `do_*` calls** (`do_add`@194,
  `do_rank`@241, `do_remove`@277, `do_default`@312), or the sourced function
  aborts at runtime.
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
- [ ] **Seam (`modes/execute.md`):** the sprint dispatch loop is **Step 5
  (`execute.md:311-471`)**; the `/run-plan` dispatch directive is the
  `Skill: { skill: "run-plan", … }` line at **`execute.md:358-359`** (M3 — the
  region was restructured; there is no "Steps 1–8 dispatch loop", and #877's
  in-flight guard (`@119`) + the D4 selection filter (`@158`) now sit between
  the entry point and the dispatch). **Re-scoped (M3): gate ONLY the dispatch
  directive — do NOT refactor the whole step into one executable fence (bigger
  and riskier than budgeted).** Gate the `/run-plan` dispatch at 358-359 on
  `_ZSKILLS_TEST_HARNESS=1` to read a per-slug injected result
  (`_ZSKILLS_TEST_RUNPLAN_RESULT_<SLUG>` or a newline slug→text map), plus an
  **entry-point unset-guard fence** (mirror `do/SKILL.md:206-211`'s, so
  production with the flag absent behaves EXACTLY as today). Version bump +
  mirror.
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
  dispatch at `execute.md:358-359` still emits the same
  `Skill: { skill: "run-plan", args: "…<FILE>.md auto" }` directive). **Validate
  this against the current Step-5 layout (M3):** the in-flight guard (`@119`),
  D4 selection filter (`@158`), and slug→file resolver (`@225`) already sit
  between the entry point and the dispatch — the gate must slot in WITHOUT
  perturbing those fragments, and the "production unchanged when flag absent"
  assertion must hold across that multi-fragment Step-5 layout, not a single
  monolithic fence. Version bump + mirror for execute.md's parent skill.
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
    the decision rule from `run-plan/SKILL.md` (~458-588; the cadence-sanity
    block is `:458-490`, the decision fences `:497-507`/`:578-588`) into
    `skills/run-plan/scripts/defer-backoff-decide.sh` taking
    `--counter --cadence --cronlist-match --create-result --case
    --recovery-marker`, **emitting the directive vocabulary the existing test
    already consumes (m2): `REPLACE_CRON T` / `WRITE_COUNTER N` /
    `DELETE_COUNTER` / `PROCEED <message-mode>`** (the invented
    `DELETE_ALL_MATCHING_CRONS`/`PROCEED`-bare tokens are NOT in production OR
    the test — `test-runplan-defer-backoff.sh` uses `REPLACE_CRON`/`WRITE_COUNTER`/
    `DELETE_COUNTER`/`PROCEED` at `:65,73,83,113-136`). Reuse those tokens to
    avoid a gratuitous rename; if a new directive is genuinely needed, note the
    rename explicitly in the phase report. SKILL.md prose interprets the
    directives (Cron* calls stay in prose). Re-point
    `test-runplan-defer-backoff.sh` to source the real script. **This
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
- [ ] Preserve all defer-backoff coverage: **14 logical cases / 34 pass-fail
  assertions** (m1 — `grep -cE '\b(pass|fail)\b' test-runplan-defer-backoff.sh`
  = 34; the preservation criterion is checkable against the assertion count,
  not the case count) + both anchors.

### Design & Constraints
- A: Cron* primitives stay in prose (not shell-testable); the script covers the
  DECISION (the bug-prone part). B: be explicit in the report that this is a
  deliberate non-extraction with compensating anchors.
- Document the choice + rationale in the phase report.

### Acceptance Criteria
- [ ] Either `defer-backoff-decide.sh` exists, is sourced by the test, AND is
  registered in script-ownership.md (A), OR anchors strengthened + exception
  documented (B).
- [ ] 14 logical cases / 34 assertions + anchors preserved; new/changed suite
  in rollup; `bash tests/run-all.sh` exit 0; Overall 0; mirror-parity green if
  SKILL.md touched.

### Dependencies
None (A factors a standalone script + sources it, like the gold-standard
sync-pr-body test; B is anchor-grep only — neither needs Phase 1's lib).

## Drift Log

The plan has **no completed phases** (all 8 are ⬚ remaining), so this log
records **staleness drift** — divergence between the original /draft-plan spec
(`ce722ff`, the plan's only prior commit, `docs(plans): draft
SEAM_HARDENING_HIGH (#830)`) and production reality at refine HEAD `c7d78ab`.
Production moved under the plan after drafting (notably #871 Step 7d, #875
land-pr UNKNOWN re-poll, #877 work-on-plans in-flight guard, #849 mode splits,
#822 bare-`force` retirement). The refine re-anchored every per-phase body to
HEAD; no phase scope was deleted except the false "do has no test" premise.

| Phase | Original spec | Current reality (HEAD c7d78ab) | Delta |
|---|---|---|---|
| 1 | `seed_caller_loop_inputs` seeds caller-loop vars only | Step-6b/7d need `REBASE_STDERR_FILE`/`UNKNOWN_POLL_MAX`/`PR_STATE`/`TW_ITER`/`REASON` | Added those inputs (m5, additive — public `extract_*` contract frozen for sibling plan) |
| 2 | 6b@~445-573, 7b@~613-644, 7c@~613, "10 cases" | 6b@456-613 + 619-646, 7b@894-925, 7c@941-966; #875 added a bounded UNKNOWN→definite re-poll prelude (481-498); #871 added a ~178-line Step 7d (705-882) re-using the rebase machinery | Re-anchored all 3; enumerated 10 cases + NEW UNKNOWN-re-poll case (M2 — current test maps UNKNOWN→blocked @263-266, a live hollow-green); ADDED a Step-7d work-item with 5 terminal arms (C3, M1) |
| 3 | pr.md caller-loop sentinel END @~321 | END @312 (BEGIN @74) | Bumped END anchor (m3) |
| 4 | "do gets its own test (today it has none)"; drift = do=`--force` vs quickfix=`force`; "47/48" assertions | `test-do.sh` exists (19 cases, run-all.sh:110); bare `force` retired in #822 (pre-dates draft) so both use `--force`; `*_SIM` only in test-quickfix.sh Cases 47/48 (1431-1569) | Deleted the false "do has no test" item; re-scoped to converting `test-do.sh` Case 6 (245-254, grep-only) to extract-and-run; re-anchored the dead drift target onto quickfix's landing-config soft-redirect (271/274) + per-skill ask-user self-name (do:403/quickfix:434); reworded "47/48"→"Cases 47 and 48" (C1, C2, M5) |
| 5 | draft-plan commit ~594-665, parse ~679-726; refine-plan commit ~591-671, parse ~683-731 | draft-plan commit 638-711 (3-space-indented), parse 723-772; refine-plan commit 600-673 FLUSH-LEFT (no strip-indent), subject via shared `case "$SKILL"` @662-664, parse 685-734 | Re-anchored both; flagged per-skill indent asymmetry (draft-plan needs strip-indent, refine-plan does not) + shared-case subject (M4) |
| 6a | mutator heredocs ~156-326, `ensure_monitor_state`@~44 | `do_add`@179…`do_default`@306 (~179-326), `ensure_monitor_state`@45, `schedule_under_1h`@369 | Bumped heredoc anchor to ~179-326 (m4) |
| 6b | "refactor Steps 1–8's dispatch loop into one executable fence" | No "Steps 1–8"; dispatch loop is Step 5 (311-471), `/run-plan` directive @358-359; #877 in-flight guard (119) + D4 filter (158) now sit between entry and dispatch | Re-anchored to Step 5; re-scoped from whole-step refactor to gating ONLY the dispatch directive + entry unset-guard (mirror do:206-211); re-validated production-unchanged against the multi-fragment layout (M3) |
| 7 | decision rule ~485-571; emit `DELETE_ALL_MATCHING_CRONS`/`PROCEED`; "14 cases" | decision region ~458-588; existing test uses `REPLACE_CRON`/`WRITE_COUNTER`/`DELETE_COUNTER`/`PROCEED`; 34 pass-fail assertions | Reconciled vocab to existing test tokens (m2); reconciled "14 cases"→"14 logical cases / 34 assertions" (m1) |

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

## Refine Review (refine-plan round 1)

A /refine-plan pass ran a reviewer + devil's-advocate over the 8 remaining
phases against production HEAD `c7d78ab`. Every finding's empirical anchor was
independently re-run by the orchestrator (verify-before-fix gate PASSED) and
spot-checked by the refiner before editing. All 13 findings were **Fixed** in
place (no Justified-not-fixed). Production-reality drift since the draft
(`ce722ff`) is itemized in the **Drift Log** above.

| Finding | Severity | Disposition | Evidence (Verified) | Note |
|---|---|---|---|---|
| C1 | CRITICAL | Fixed | `ls tests/test-do.sh` exists, `run-all.sh:110`; Case 6 @245-254 is `grep -qF`-only | Deleted false "do has no test"; re-scoped to converting Case 6 to extract-and-run |
| C2 | CRITICAL | Fixed | `do/SKILL.md:73,215` + `quickfix/SKILL.md:64,101` both dashed `--force`; bare `force` retired in `eb75e4c` (#822) pre-draft | Re-anchored drift target onto quickfix landing-redirect (271/274) + per-skill ask-user self-name (do:403/quickfix:434) |
| C3 | CRITICAL | Fixed | `land-pr/SKILL.md:648` Step 7d heading, fence 705-882, re-uses 6b rebase machinery | Added a Step-7d work-item with 5 terminal arms (MERGED/BEHIND/waiting/surface/no-terminus) |
| M1 | MAJOR | Fixed | step headings 6b@409, 7b@884, 7c@927; fences 6b@456-613+619-646, 7b@894-925, 7c@941-966 | Re-anchored all 3 + noted second 6b fence |
| M2 | MAJOR | Fixed | UNKNOWN re-poll @481-498 (`UNKNOWN_POLL_MAX=5`); test maps UNKNOWN→blocked @263-266 (live hollow-green); `REBASE_STDERR_FILE` input @174 | Added UNKNOWN-re-poll case; seed inputs in Phase 1 |
| M3 | MAJOR | Fixed | `execute.md` Steps 0/3/4/5/6; dispatch loop = Step 5 @311-471; `/run-plan` directive @358-359; in-flight guard @119, D4 filter @158 | Re-anchored to Step 5; re-scoped to gating only the directive + entry unset-guard (mirror do:206-211); re-validated production-unchanged |
| M4 | MAJOR | Fixed | draft-plan commit 638-711 (`   ```bash` indented), parse 723-772; refine-plan commit 600-673 FLUSH-LEFT, subject via shared case @662-664, parse 685-734 | Re-anchored; flagged indent asymmetry + shared-case subject |
| M5 | MAJOR | Fixed | `_SIM` only in test-quickfix.sh @1431 (TRIAGE_SIM) / @1516 (REVIEW_SIM); none in test-do.sh | Reworded "47/48"→"Cases 47 and 48"; noted SIM lives only in test-quickfix.sh |
| m1 | MINOR | Fixed | `grep -cE '\b(pass\|fail)\b' test-runplan-defer-backoff.sh` = 34 | Reconciled to "14 logical cases / 34 assertions" |
| m2 | MINOR | Fixed | test uses `REPLACE_CRON`/`WRITE_COUNTER`/`DELETE_COUNTER`/`PROCEED` @65-136; invented tokens absent | Reconciled emitted vocab to existing test tokens |
| m3 | MINOR | Fixed | `pr.md:312` `=== END CANONICAL /land-pr CALLER LOOP ===` (BEGIN @74) | Bumped END anchor 321→312 |
| m4 | MINOR | Fixed | `do_add`@179…`do_default`@306, `ensure_monitor_state`@45, `schedule_under_1h`@369 | Bumped heredoc anchor ~156-326 → ~179-326 |
| m5 | MINOR | Fixed | inputs `REBASE_STDERR_FILE`@174, `UNKNOWN_POLL_MAX`@485, 7d vars @705-882 | Added Step-6b/7d inputs to `seed_caller_loop_inputs`; PUBLIC `extract_*` contract untouched (sibling SEAM_HARDENING_REST hard-dep preserved) |

**Substantive issues remaining: 0.** All 13 findings Fixed in place; none
Justified-not-fixed. The plan's three-technique framing (extract-and-run /
parity-gate / anchor-grep) and the honest-residue / model-layer-above-the-line
stance are preserved verbatim. The Phase-1 lib's public function
signatures (`extract_fence_between`, `extract_sentinel_block`) and the
`tests/lib/extract-fence.sh` contract are unchanged (only the additive
`seed_caller_loop_inputs` grew), preserving the SEAM_HARDENING_REST hard-dep.
