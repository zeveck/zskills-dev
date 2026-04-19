---
title: Improve /run-plan Staleness Detection (Arithmetic Drift)
created: 2026-04-19
status: active
---

# Plan: Improve /run-plan Staleness Detection (Arithmetic Drift)

## Overview

Harden `/run-plan` to catch the class of bug RESTRUCTURE_RUN_PLAN shipped on 2026-04-19: three phases had arithmetically unreachable acceptance bands (340-380 actual 277; 850-950 actual 1057; 700-900 actual 1534). Each was caught post-hoc by the implementation agent, flagged in the phase report as "non-blocking plan-text issue," then ignored by the orchestrator. Byte-preservation compensated, so no wrong code landed — but the plan file shipped with stale bands.

Two structural fixes layered on `/refine-plan`'s Dimension 7 (added in commit `fd9d03d`):

1. **Pre-dispatch gate** in `/run-plan` Phase 1 step 6: broaden the staleness check from textual markers to also re-derive numeric acceptance targets arithmetically and flag >10% drift before the implementation agent runs.
2. **Post-implement gate** (new Phase 3.5): parse the verification agent's report for a standardized `PLAN-TEXT-DRIFT:` token. For each drift within 20% with behavioral invariants intact, auto-correct the plan's acceptance criterion inline and commit with the landing flow. Above 20% or with invariant failure, invoke Failure Protocol.

Combined with `/refine-plan` Dimension 7, these form a defense-in-depth chain: **pre-authoring review** → **pre-dispatch gate** → **post-implement gate**. The same bug would be caught at the earliest possible layer, not via post-hoc process damage control.

**Scope:** `/run-plan` SKILL.md + one new helper script (`scripts/plan-drift-correct.sh`) + `docs/tracking/TRACKING_NAMING.md` update. No new skills. No new config keys. Shared `PLAN-TEXT-DRIFT:` vocabulary across `/refine-plan` (pre-exec), `/run-plan` Phase 1 (pre-dispatch), and `/run-plan` Phase 3.5 (post-implement).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Standardize `PLAN-TEXT-DRIFT:` token + `scripts/plan-drift-correct.sh`        | ⬚ | | |
| 2 — Post-implement auto-correct gate (Phase 3.5)                                  | ⬚ | | |
| 3 — Pre-dispatch arithmetic gate (Phase 1 step 6 extension) + tests + docs        | ⬚ | | |

---

## Phase 1 — Standardize `PLAN-TEXT-DRIFT:` token and ship `scripts/plan-drift-correct.sh`

### Goal

Define a single structured token that implementation + verification agents emit when they detect numeric acceptance-band drift, and ship a pure-shell helper that parses and auto-corrects it. This phase's helper script is what Phase 3.5 and Phase 3 (pre-dispatch) wrap — keeping parse/compute/edit logic in a testable script rather than skill-prose (same pattern as `scripts/compute-cron-fire.sh`, commit `64ee65b`).

### Work Items

- [ ] 1.1 Define token format (documented in SKILL.md):
      ```
      PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
      ```
      - `phase=<N>` — 1-indexed phase number (e.g., `phase=1`, `phase=4A`)
      - `bullet=<M>` — 1-indexed ordinal within the `### Acceptance Criteria` section of that phase (e.g., `bullet=3`)
      - `field=<str>` — short identifier, free-form but must NOT contain `:`, `=`, or ` actual=` / ` plan=` substrings (e.g., `field=skill-line-count`)
      - `plan=<stated>` — the exact literal from the acceptance criterion (e.g., `plan=340-380`, `plan=~357`, `plan=≥35`)
      - `actual=<measured>` — the measured value (e.g., `actual=277`)
      - One token per drift. Emit on its own line in the agent's final report.
      - Format is single-line, space-delimited `key=value`. Parseable with awk `$1 $2 $3 ...`.

      **Grammar forbids colons in `<str>` values.** Enforce via a leading parser regex check (Phase 1 WI 1.3).

- [ ] 1.2 Create `scripts/plan-drift-correct.sh` (executable bash, `set -eu`). Responsibilities:
      1. **Parse mode:** `scripts/plan-drift-correct.sh --parse <report-file>` — reads file, extracts all `PLAN-TEXT-DRIFT:` tokens, emits one normalized record per line: `<phase>|<bullet>|<field>|<stated>|<actual>`. Exit 0 on success, 1 if malformed token found (with stderr explaining which token and why).
      2. **Compute mode:** `scripts/plan-drift-correct.sh --drift <stated> <actual>` — parses `<stated>` (supporting forms below) and `<actual>` (integer), emits drift-percent as plain integer rounded up. Exit 0.
      3. **Correct mode:** `scripts/plan-drift-correct.sh --correct <plan-file> <phase> <bullet> <new-band> [--audit "original band"]` — edits the plan's `### Acceptance Criteria` section of `<phase>`, finds the `<bullet>`th numeric-bearing bullet, rewrites it with `<new-band>`, appends `<!-- Auto-corrected YYYY-MM-DD: was X, arithmetic says Y -->` inline comment. Uses `grep -Fn`-style anchored locating (NOT unanchored grep). Exit 0 on success; 1 if the target bullet can't be uniquely located.

      Supported `<stated>` forms for --drift parser:
      - `N-M` / `N–M` (range, both hyphen and en-dash): drift = `|actual - midpoint| / midpoint * 100`
      - `≤N` / `<=N` / `at most N`: drift = 0 if actual ≤ N, else `(actual - N) / N * 100`
      - `≥N` / `>=N` / `at least N`: drift = 0 if actual ≥ N, else `(N - actual) / N * 100`
      - `~N` / `approximately N` / `expected N` / literal N: drift = `|actual - N| / N * 100`
      - `exactly N`: drift = 0 if actual == N, else 999 (forces escalation)
      - Any other form: exit 2 with stderr "unsupported stated form: <stated>". Deliberately narrow — see Non-Goals.

- [ ] 1.3 Create `tests/test-plan-drift-correct.sh`:
      - 20 test cases covering: token parse (well-formed, malformed, multiple per file), drift compute (each supported `<stated>` form, plus "unsupported" exit-2 branch), correct (in-place edit with audit comment, multiple matching bullets → error, phase not found → error).
      - Uses `/tmp/zskills-tests/$(basename "$(pwd)")/` per CLAUDE.md output rule.
      - No network, no git operations.

- [ ] 1.4 Register `tests/test-plan-drift-correct.sh` in `tests/run-all.sh` (add `run_suite` line, alphabetical with existing tests).

- [ ] 1.5 Update `skills/run-plan/SKILL.md` — add a new H3 subsection `### Plan-text drift signals` under Phase 2 "Worktree mode" and Phase 2 "Delegate mode" sections. Content:
      > If during your work you observe a plan's acceptance criterion
      > contains a numeric target (lines / tests / cases / commits / files)
      > that doesn't match reality, emit a line of the form:
      > ```
      > PLAN-TEXT-DRIFT: phase=<N> bullet=<M> field=<str> plan=<stated> actual=<measured>
      > ```
      > in your final report. One per drift. Advisory — continue your work.

      Same content also added to Phase 3 "Worktree mode verification" and "Delegate mode verification" dispatch prompts. Verification agents MUST re-detect drift independently, not forward implementation-agent flags.

- [ ] 1.6 Update `skills/run-plan/SKILL.md` Key Rules section (H2 `## Key Rules`) with a new bullet:
      > - **Plan-text drift signals.** Implementation and verification
      >   agents MUST emit a `PLAN-TEXT-DRIFT:` token (format above) for
      >   each numeric acceptance criterion that doesn't match reality.
      >   Phase 3.5 parses these to decide whether to auto-correct the
      >   plan. Token format forbids `:` and `=` inside `<field>`.

- [ ] 1.7 Update `docs/tracking/TRACKING_NAMING.md` to document the new marker basename introduced in Phase 2 (referenced here so agents see both sides coherently):
      - Add to the phasestep-prefix allow-list: `phasestep.run-plan.<id>.<phase>.drift-detect` (informational only; the hook ignores phasestep.*).

- [ ] 1.8 Append CHANGELOG entry under today's date (or create `CHANGELOG.md` if it doesn't exist): "feat(run-plan): add `PLAN-TEXT-DRIFT:` structured token for acceptance-band drift flags; see skills/run-plan/SKILL.md Key Rules and `scripts/plan-drift-correct.sh`."

- [ ] 1.9 Mirror source-to-installed for /run-plan (per-file cp, NOT `rm -rf` — hook blocks it outside /tmp):
      ```
      cp skills/run-plan/SKILL.md .claude/skills/run-plan/SKILL.md
      diff -r skills/run-plan .claude/skills/run-plan   # empty
      ```
      If new `modes/` or `references/` were added: iterate per-file (the skill is post-RESTRUCTURE with a modes/ + references/ layout). Current dirs: check `ls skills/run-plan/`.

- [ ] 1.10 Commit: `feat(run-plan): add PLAN-TEXT-DRIFT token + scripts/plan-drift-correct.sh for acceptance-band drift detection`

### Design & Constraints

**Token anchors fix disambiguation.** The reviewer's F-6 (and DA-4) identified that free-form `<field>` can't reliably locate the target bullet. Adding `phase=<N> bullet=<M>` makes the token self-anchored: Phase 3.5 navigates directly to the correct `### Acceptance Criteria` section and bullet ordinal. No more unanchored `grep -n "<stated>"`.

**Why extract to `scripts/plan-drift-correct.sh`.** Same pattern as `compute-cron-fire.sh`: the parsing + arithmetic + in-place edit logic is testable in isolation, skill-prose stays thin, downstream skills (possibly /refine-plan later) can reuse the script. F-4 and DA-7 both argued for this — keeping parser in prose means it's never tested, and complex arithmetic in $(())-eval inside SKILL.md is an injection risk.

**Grammar of supported `<stated>` forms is deliberately narrow.** Five forms (range, ≤, ≥, ~N, exactly). "Any other form" exits 2. This means rare or ambiguous phrasings like "roughly 400-600" or "(40 + 12)" fall through as "unsupported" → skipped by the gate, logged in the phase report, not auto-corrected. Graceful degradation — better than silently guessing wrong.

**Grammar never $()-evals.** `<stated>` is parsed by regex + `awk` + `case`, never passed to `$(( ))` or eval. `<actual>` must parse as integer (leading digits, remainder discarded). DA-7's injection-surface concern is addressed.

**Verification-agent independence.** Verification agents MUST re-detect drift, not forward implementation's tokens. If implementation skipped the check OR implementation IS the source of drift, the verifier catches it. Phase 3.5 processes the UNION of both reports' tokens.

**No `:` or `=` in `<field>`.** Prevents greedy-regex parse ambiguity (DA-6). Enforced by token-parse rejecting malformed forms.

### Acceptance Criteria

Each acceptance bullet below is a post-Phase-1 state. Arithmetic targets explicitly show the derivation so Phase 3.5 can audit itself on this plan's own execution.

- [ ] `test -x scripts/plan-drift-correct.sh` (executable).
- [ ] `bash -n scripts/plan-drift-correct.sh` passes (syntax clean).
- [ ] `bash tests/test-plan-drift-correct.sh` exits 0 with ≥ 20 cases passing (covers the 5 `<stated>` forms × parse/compute/correct axes, plus error paths).
- [ ] `grep -c 'test-plan-drift-correct.sh' tests/run-all.sh` returns exactly 1 (registration).
- [ ] `grep -cE 'PLAN-TEXT-DRIFT:' skills/run-plan/SKILL.md` returns ≥ 5. **Expected locations (enumerated to avoid the F-5 self-stale-band class of bug):** (a) token definition in `### Plan-text drift signals` subsection under Phase 2 Worktree mode, (b) same subsection under Phase 2 Delegate mode, (c) same under Phase 3 Worktree verification, (d) same under Phase 3 Delegate verification, (e) Key Rules bullet. Arithmetic: 5 locations, each with one token mention, minimum count 5. If the implementer's edits produce more (e.g., doc cross-references), the ≥5 floor still holds.
- [ ] `grep -cE 'PLAN-TEXT-DRIFT:' .claude/skills/run-plan/SKILL.md` equals the source count (mirror parity).
- [ ] `diff -r skills/run-plan .claude/skills/run-plan` is empty.
- [ ] `grep -q 'phasestep.run-plan' docs/tracking/TRACKING_NAMING.md` succeeds (tracking doc updated for the Phase 2 marker).
- [ ] `grep -q 'PLAN-TEXT-DRIFT' CHANGELOG.md` succeeds (CHANGELOG entry present).
- [ ] `bash tests/run-all.sh` exits 0 with 100% pass rate (existing 531 + new 20 ≈ 551).
- [ ] **Byte-preservation check** (replacing the stale F-3 version):
      ```bash
      # Pre-Phase-1 regions: Arguments, Status, Now, Next, Stop, Phase 0
      # (all BEFORE Phase 1 Parse Plan at line 286 in the current source).
      # The correct check extracts the head 285 lines from HEAD AND
      # current, then diffs.
      diff <(git show HEAD:skills/run-plan/SKILL.md | sed -n '1,285p') \
           <(sed -n '1,285p' skills/run-plan/SKILL.md)
      ```
      Must be empty. (These regions aren't touched by any Phase 1 work item.)

### Dependencies

None. Foundational.

### Non-Goals

- Support for every conceivable `<stated>` phrasing. Five forms only.
- Machine-readable extraction-rule DSL. Phase 3's pre-dispatch parser uses the same narrow grammar.
- /refine-plan integration beyond reusing the `PLAN-TEXT-DRIFT:` vocabulary. /refine-plan's Dimension 7 already exists (commit `fd9d03d`).

---

## Phase 2 — Post-implement auto-correct gate (Phase 3.5)

### Goal

Insert a new Phase 3.5 between `/run-plan`'s Phase 3 (Verify) and Phase 4 (Update Progress Tracking). After Phase 3's `### Post-verification tracking` subsection writes `step.run-plan.$TRACKING_ID.verify`, Phase 3.5 scans implementation + verification reports for `PLAN-TEXT-DRIFT:` tokens via `scripts/plan-drift-correct.sh`, auto-corrects drifts within threshold, and writes a `phasestep.*.drift-detect` informational marker. Phase 4 then proceeds with the corrected plan file in its tracker commit.

### Work Items

- [ ] 2.1 Add H2 section `## Phase 3.5 — Detect and auto-correct plan-text drift` to `skills/run-plan/SKILL.md`, immediately after Phase 3's `### Post-verification tracking` subsection (which ends at approximately line 1036 in the current source) and before Phase 4. Full content spec below in 2.2.

- [ ] 2.2 Phase 3.5 content (verbatim spec for the orchestrator):
      ```markdown
      ## Phase 3.5 — Detect and auto-correct plan-text drift

      Runs AFTER Phase 3's `### Post-verification tracking` writes
      `step.run-plan.$TRACKING_ID.verify`, and BEFORE Phase 4's tracker
      commit. Reads both the implementation agent's and verification
      agent's reports for `PLAN-TEXT-DRIFT:` tokens and auto-corrects
      the plan file.

      ### 1. Gather reports

      Concatenate the implementation agent's final-message text and the
      verification agent's final-message text into a single parse input.
      Both agents' outputs are available from Phase 2 and Phase 3 agent
      dispatches.

      ### 2. Parse tokens

      ```bash
      bash scripts/plan-drift-correct.sh --parse <combined-reports>
      ```
      Produces one `<phase>|<bullet>|<field>|<stated>|<actual>` line per
      drift. Zero lines = no drifts → skip to step 6.

      ### 3. Per-drift decision

      For each record, compute drift via:
      ```bash
      bash scripts/plan-drift-correct.sh --drift "<stated>" "<actual>"
      ```
      Decision table:

      | Drift | Byte-preservation / test gate | Action |
      |-------|-------------------------------|--------|
      | ≤10%  | held                          | auto-correct + count |
      | 10-20% | held                         | auto-correct + count + note in phase report |
      | >20%  | held                          | ABORT: do NOT correct, report to user, escalate to Failure Protocol (plan intent likely wrong, not just arithmetic) |
      | any   | failed                        | Failure Protocol (byte-preservation failure always escalates) |
      | unsupported `<stated>` form (exit 2) | — | skip, log as "non-derivable" in phase report |

      ### 4. Auto-correct

      For each "auto-correct" record:
      ```bash
      NEW_BAND="$(bash scripts/plan-drift-correct.sh --drift-band <actual> 5)"  # ±5% of actual
      bash scripts/plan-drift-correct.sh --correct <plan-file> <phase> <bullet> "$NEW_BAND" --audit "was <stated>"
      ```
      `--audit` appends `<!-- Auto-corrected YYYY-MM-DD: was <stated>, arithmetic says <actual> -->` inline on the bullet.

      ### 5. Marker ordering and failure handling

      `.verify` is ALREADY written by Phase 3. That satisfies the hook's
      landing gate (`hooks/block-unsafe-project.sh.template:341 etc.`
      globs `step.*.verify`). If Phase 3.5 proceeds cleanly, write an
      informational marker:

      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
      printf 'phase: %s\ndrifts_found: %s\ndrifts_corrected: %s\ndrifts_escalated: %s\ncompleted: %s\n' \
        "$PHASE" "$FOUND" "$CORRECTED" "$ESCALATED" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/phasestep.run-plan.$TRACKING_ID.$PHASE.drift-detect"
      ```
      Uses the `phasestep.*` prefix (informational; hook ignores). The
      `step.*.verify` marker stays as-is.

      If Phase 3.5 fails (e.g., `scripts/plan-drift-correct.sh` exits
      non-zero mid-correction, or >20% drift case triggers), the
      orchestrator MUST:
      1. `git checkout -- <plan-file>` to revert any partial corrections.
      2. DELETE `step.run-plan.$TRACKING_ID.verify` (so the landing gate
         re-blocks — the pipeline is no longer verified-and-clean, it's
         verified-but-drift-escalated).
      3. Write `phasestep.run-plan.$TRACKING_ID.$PHASE.drift-fail` with
         the error detail.
      4. Invoke Failure Protocol.

      ### 6. Commit-location rule

      The auto-correction edits the plan file. Where does the edit commit?

      **Cherry-pick / direct mode:** commit on main, bundled with Phase 4's
      tracker commit. Combined message:
      ```
      chore: mark phase <name> in progress (+ auto-corrected <N> stale acceptance bands)
      ```
      If N == 0: default Phase 4 message.

      **PR mode:** commit inside the worktree on the feature branch,
      bundled with Phase 4's feature-branch tracker commit. Same combined
      message. The next phase's Phase 1 parse reads the plan file from
      the worktree (since `finish auto` PR-mode runs consecutive phases
      in the SAME worktree), so the corrected band is visible to the next
      phase's thrash-detection.

      ### 7. Thrash rule

      If the SAME `<phase>+<bullet>` pair gets a `PLAN-TEXT-DRIFT:` token
      on a subsequent Phase 3.5 invocation (across phases in the same
      `/run-plan finish auto` execution), the first correction was
      wrong. ABORT:
      1. Write `phasestep.*.drift-fail` with "thrash detected: phase
         P bullet B re-flagged after correction."
      2. Do NOT correct a second time.
      3. Invoke Failure Protocol.

      Thrash rule is scoped to the current `/run-plan` invocation's
      history, NOT across sessions. State is tracked in-memory by the
      orchestrator during `finish auto`; for cron-fired chunked runs,
      the rule relies on re-reading the plan file from the correct
      location (worktree for PR mode, main for cherry-pick / direct).

      ### 8. Interaction with /refine-plan

      Phase 3.5 corrects small arithmetic drift only. If the scan finds
      multiple fields with >10% drift OR the plan's own extraction rules
      are arithmetically inconsistent (detected by the pre-dispatch gate
      in Phase 1 step 6), append a recommendation to the phase report:
      "Recommend running `/refine-plan <plan-file>` after close-out; this
      plan has structural drift beyond per-band correction scope."

      Do NOT auto-dispatch `/refine-plan` mid-run — too expensive and
      scope-overlapping.
      ```

- [ ] 2.3 Extend Phase 4's opening prose in SKILL.md to reference Phase 3.5:
      > If Phase 3.5 auto-corrected any acceptance bands, those edits are
      > staged alongside the tracker update here and land as a single
      > commit.

- [ ] 2.4 Mirror `skills/run-plan/SKILL.md` → `.claude/skills/run-plan/SKILL.md` (per-file cp).

- [ ] 2.5 Add integration test cases to `tests/test-plan-drift-correct.sh` (already created in Phase 1; extend):
      - Simulated Phase 3.5 end-to-end: fake reports, fake plan file with stale band, invoke `--parse` → `--drift` → `--correct`, verify the plan file shows the new band with audit comment.
      - Thrash case: run --correct twice on same phase+bullet; verify the second invocation can be detected by re-parsing and seeing the comment pattern (the scripts don't enforce thrash themselves; the orchestrator does — but the test verifies script behavior is deterministic on repeat calls).
      - >20% drift escalation: verify `--drift` returns > 20 when appropriate (no correction).

- [ ] 2.6 Commit: `feat(run-plan): Phase 3.5 auto-correct gate for PLAN-TEXT-DRIFT tokens`

### Design & Constraints

**Marker ordering addresses DA-1.** `step.*.verify` is written by Phase 3 — the hook sees "verified" and would let landing proceed. Phase 3.5 runs AFTER that. If Phase 3.5 fails, it DELETES `.verify` so the hook re-blocks. This makes the atomic unit "verified AND drift-corrected" rather than "verified alone."

**phasestep prefix addresses DA-2.** Phase 3.5's marker is informational — the hook shouldn't gate on it. The existing `phasestep.*` convention (documented in SKILL.md's Post-landing tracking section for `finish` mode) covers this exactly. Reusing it avoids introducing a new basename pattern the hook would silently ignore without anyone noticing.

**Commit-location symmetry addresses DA-3.** In PR mode, next-phase Phase 1 reads the plan from the worktree (because `finish auto` reuses the same worktree across phases in PR mode per SKILL.md Phase 2 PR-mode block). So committing the correction to the feature-branch copy means the next phase sees it — no false-positive thrash. In cherry-pick mode, the correction lands on main in Phase 4's commit, and the next phase's worktree is recreated from main — again visible. DA-3's concern is addressed by documenting "which plan file is read where" explicitly, which we now do.

**Thrash-rule scope.** Per-execution only. Cross-session state isn't required because the rule's signal (same correction attempted twice) only matters within one `/run-plan finish auto` run. A new session reading a previously-corrected plan doesn't need to remember the history — it just sees the current band and verifies.

**Extraction to `scripts/plan-drift-correct.sh` is load-bearing.** DA-4, DA-6, DA-7 all argued parse/compute/edit should not be skill-prose. The script is unit-tested in isolation; Phase 3.5's orchestration is thin prose that calls the script. If the script's edge cases grow, tests grow; the skill doesn't bloat.

**Byte-preservation precondition.** "Held" means: byte-preservation diffs (if the plan's phase checks them) passed, AND the full test suite passes, AND `/verify-changes` didn't flag scope violations. Any failure → Failure Protocol, never auto-correct on top of a failing implementation.

**±5% correction tolerance.** Tight enough to catch future drift; loose enough to survive normal fluctuation (~3 lines of intro, etc.). Future drift within the ±5% band is silent; anything outside re-triggers correction.

### Acceptance Criteria

- [ ] Phase 3.5 section exists in `skills/run-plan/SKILL.md`. Verify:
      ```bash
      grep -c '^## Phase 3.5' skills/run-plan/SKILL.md    # expected: 1
      ```
- [ ] `step.*.verify` ordering rule documented (Phase 3.5 runs AFTER verify, failure deletes verify):
      ```bash
      grep -q 'DELETE `step.run-plan.\$TRACKING_ID.verify`' skills/run-plan/SKILL.md
      ```
- [ ] Thrash rule documented + scoped ("per-execution"):
      ```bash
      grep -q 'Thrash rule is scoped to the current' skills/run-plan/SKILL.md
      ```
- [ ] Decision-table with 5 rows (≤10, 10-20, >20, byte-preservation failed, unsupported) present verbatim.
- [ ] `tests/test-plan-drift-correct.sh` has ≥ 5 new integration cases for Phase 3.5 orchestration contract; total test count ≥ 25.
- [ ] `bash tests/run-all.sh` exits 0 with 100% pass rate.
- [ ] Mirror clean: `diff -r skills/run-plan .claude/skills/run-plan`.
- [ ] `grep -c '^## Phase ' skills/run-plan/SKILL.md` increases by exactly 1 vs pre-Phase-2 source (new Phase 3.5 heading).

### Dependencies

Phase 1. Phase 3.5 orchestration script (`plan-drift-correct.sh`) must exist before the Phase 3.5 prose can reference it.

### Non-Goals

- Phase 3.5 mutating implementation code or test files. Only the plan file.
- Phase 3.5 auto-dispatching `/refine-plan`. Always a recommendation, never a dispatch.
- Tracking drift across sessions. Per-execution only.

---

## Phase 3 — Pre-dispatch arithmetic gate (Phase 1 step 6 extension) + final tests + docs

### Goal

Extend `/run-plan`'s Phase 1 step 6 staleness check from textual-only to arithmetic-aware. Before dispatching the implementation agent, the orchestrator uses `scripts/plan-drift-correct.sh` to scan the target phase's acceptance criteria for numeric targets that are arithmetically derivable from the plan's stated extraction rules, re-derives the expected value, and flags >10% drift. Plus: round out testing, docs, CHANGELOG.

### Work Items

- [ ] 3.1 Edit Phase 1 step 6 in `skills/run-plan/SKILL.md` (currently ~lines 428-438). Restructure into two sub-checks, both run, neither short-circuits the other:
      ```markdown
      6. **Check for staleness.** Two independent checks:

         **a. Textual staleness.** (existing check, preserved verbatim
         — grep Dependencies section for "drafted before," "may need
         refresh," "based on [another plan's] design, not actual code.")

         **b. Arithmetic staleness (pre-dispatch).** For the target
         phase's `### Acceptance Criteria` section, extract numeric
         targets and verify against current source.

         Procedure:
         1. Read the target phase's `### Acceptance Criteria` bullets.
         2. For each bullet, attempt to match a numeric claim via the
            token-compatible grammar (Phase 1 `<stated>` forms: N-M,
            ≤N, ≥N, ~N, exactly N). Unmatched bullets skip.
         3. For each matched claim, locate the corresponding extraction
            rule (if any) in the target phase's `### Design &
            Constraints` section. Supported rules:
            - Literal arithmetic expression: "N - M + K" → evaluate via
              `scripts/plan-drift-correct.sh --eval "N - M + K"`
              (the script implements parse-only integer arithmetic; no
              shell eval, no injection surface).
            - "extract lines N..M" or "lines N-M" → value is M - N + 1.
            - "SKILL.md X lines down from Y" → value is Y - X or X (case-
              by-case; script uses a small fixed set of patterns).
            - No derivable rule → skip bullet, emit info line:
              "pre-dispatch arithmetic check: <bullet> skipped (no
              derivable rule)".
         4. Compute drift between stated target and derived value.
            Use the same `--drift` command as Phase 3.5.
         5. Collect findings per bullet.

         Decision:
         - **Without `auto`:** present findings:
           ```
           Pre-dispatch arithmetic drift:
           Phase <N>: <bullet-text>
             plan says: <stated>
             arithmetic says: <derived>
             drift: <pct>%
           ```
           Ask user: "(1) proceed (Phase 3.5 will post-correct small
           drift), (2) pause for `/refine-plan`, (3) override (suppress
           this check for this phase)?"
         - **With `auto`:** if any bullet has drift >20%, dispatch
           `/refine-plan <plan-file>` (plan-level issue, not per-band);
           after refresh, re-read and continue. If all drifts are
           ≤20%, log findings to the phase report and proceed — Phase
           3.5 will auto-correct post-hoc within the ≤20% band.

      ```

- [ ] 3.2 Mirror skill source: `cp skills/run-plan/SKILL.md .claude/skills/run-plan/SKILL.md`.

- [ ] 3.3 Add pre-dispatch test cases to `tests/test-plan-drift-correct.sh` (extending Phase 1's file):
      - Craft a plan with extraction rule "extract lines 100-200" and acceptance band "50-70 lines". Math: 200-100+1 = 101 actual; band 50-70; drift large.
      - Invoke `scripts/plan-drift-correct.sh --eval` and `--drift` as the pre-dispatch gate would.
      - Verify correct drift% computed; verify "non-derivable" skip path for bullets without matching rules.

- [ ] 3.4 Extend `scripts/plan-drift-correct.sh` with `--eval <expr>` mode:
      - Parses integer arithmetic `N [+-] N [+-] N …` (whitespace-tolerant, integer-only, no variables, no parentheses, no multiplication/division in v1).
      - Rejects with exit 2 on any unsupported operator or non-integer.
      - Emits the computed integer to stdout. Exit 0.
      - No `$(( ))` usage, no `eval`. Implemented via explicit token-loop.

- [ ] 3.5 Update `docs/tracking/TRACKING_NAMING.md` with a final pass: ensure all new marker basenames from Phases 1-3 are documented (at minimum: `phasestep.run-plan.<id>.<phase>.drift-detect`, `phasestep.run-plan.<id>.<phase>.drift-fail`).

- [ ] 3.6 Append CHANGELOG close-out entry: "feat(run-plan): Phase 3.5 post-implement auto-correct + Phase 1 pre-dispatch arithmetic staleness gate landed. See `plans/IMPROVE_STALENESS_DETECTION.md` for design."

- [ ] 3.7 Run `bash tests/run-all.sh`. Expect 100% pass.

- [ ] 3.8 Commit: `feat(run-plan): pre-dispatch arithmetic staleness gate (Phase 1 step 6 extension) + docs`

### Design & Constraints

**Why a pre-dispatch gate at all, given Phase 3.5 post-corrects.** Two reasons:
1. Non-auto runs benefit: user sees the drift immediately and can choose `/refine-plan` before wasting agent time.
2. Large drift (>20%) in `auto` mode should trigger `/refine-plan` pre-dispatch rather than the whole implementation-verify-land cycle. Pre-dispatch catches that class early.

**Extraction-rule grammar is narrow by design (addresses DA-7).** Three forms: literal integer arithmetic, "extract lines N-M," "lines N-M." All unevaluated-expression cases skip gracefully with a logged note. "Hard extraction parsing" is explicitly NOT attempted — the plan docs this as a Non-Goal. If a plan uses an unsupported form, the gate falls back to "non-derivable" and Phase 3.5 still catches the drift post-hoc.

**No shell eval.** `scripts/plan-drift-correct.sh --eval` uses a token-walking parser (awk or pure bash string ops), never `$(( ))`, never `eval`. DA-7's injection concern is closed.

**Decision on `/refine-plan` auto-dispatch (updated).** Only dispatched when pre-dispatch finds >20% drift — at that point the plan itself has structural issues and a refinement round is warranted. Smaller drifts continue through Phase 3.5's post-correction path. This balances autonomy (don't pause auto runs needlessly) with safety (don't mask structural authoring bugs).

### Acceptance Criteria

- [ ] Phase 1 step 6 in `skills/run-plan/SKILL.md` has sub-steps `a.` (textual) and `b.` (arithmetic):
      ```bash
      sed -n '/^6\.\ \*\*Check for staleness/,/^7\./p' skills/run-plan/SKILL.md | grep -c '^\s*\*\*[ab]\.'   # expected: 2
      ```
- [ ] `scripts/plan-drift-correct.sh --eval "417 - 94 - 60 + 15"` outputs `278`.
- [ ] `scripts/plan-drift-correct.sh --eval "417 * 2"` exits 2 (multiplication unsupported).
- [ ] Pre-dispatch test case in `tests/test-plan-drift-correct.sh` passes.
- [ ] `grep -c 'phasestep.run-plan.<id>.<phase>.drift' docs/tracking/TRACKING_NAMING.md` ≥ 2 (drift-detect + drift-fail).
- [ ] CHANGELOG has both Phase 1 and Phase 3 entries.
- [ ] `bash tests/run-all.sh` exits 0 with 100% pass rate.
- [ ] Mirror clean.
- [ ] `/run-plan plans/IMPROVE_STALENESS_DETECTION.md next` parses cleanly (read-only smoke, no dispatch).

### Dependencies

Phase 1 (script and token), Phase 2 (Phase 3.5 post-correction path that pre-dispatch defers to in `auto` mode for small drift).

### Non-Goals

- Parsing extraction rules expressed in natural language ("roughly N lines per Y files"). If the plan doesn't use one of the three supported forms, the bullet is skipped with a logged note.
- `--eval` supporting multiplication, division, parentheses, or variables. Integer `+` / `-` only.

---

## Non-Goals (plan-wide)

- Adding a new skill or tool. Entirely within `/run-plan` + 1 helper script.
- Machine-readable plan schema (YAML acceptance criteria, JSON extraction rules).
- Auto-dispatching `/refine-plan` on small drift. Reserved for >20% in pre-dispatch; Phase 3.5 never dispatches it.
- Cross-session / cross-invocation drift tracking. Per-execution only.
- Parsing free-form natural-language extraction rules. Three narrow forms only.
- **Phase 3.5 should find zero drift on self-execution of THIS plan.** (DA-5 non-goal preservation.) Any drift in this plan's own acceptance criteria is a meta-bug, not a demo. The enumerated acceptance-criterion arithmetic in Phase 1 AC ≥5 bullet is the primary guard.

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Unanchored grep corrupts wrong acceptance bullet | LOW (addressed) | Token includes `phase=N bullet=M` ordinal; `plan-drift-correct.sh --correct` navigates to phase + bullet, not unanchored grep |
| Greedy regex parse fails on certain stated values | LOW (addressed) | Token grammar forbids `:` `=` in `<field>`; parser uses `awk` field-split not greedy regex |
| Phase 3.5 crash leaves partial edits in plan file | LOW (addressed) | On any failure: `git checkout -- <plan-file>` + delete `.verify` marker + `drift-fail` phasestep + Failure Protocol |
| PR-mode stale-plan thrash false-positive across phases | LOW (addressed) | Commit correction to worktree's feature-branch copy; next phase reads from same worktree |
| Unsupported stated form silently guessed wrong | LOW (addressed) | `plan-drift-correct.sh --drift` exits 2 on unsupported forms; Phase 3.5 logs as "non-derivable" and skips, never guesses |
| Extraction-rule parser becomes injection surface | N/A (addressed) | `--eval` is integer +/- only; no `$(( ))`, no `eval`, token-walk implementation |
| Self-stale acceptance bands in this plan trigger Phase 3.5 on self-execution | LOW (addressed) | Each acceptance criterion enumerates its arithmetic; acceptance bullets are tight (e.g., ≥5 floor with 5 enumerated locations) |
| Hook silently ignores new marker basename | LOW (addressed) | Uses existing `phasestep.*` convention (hook ignores by design); documented in TRACKING_NAMING.md |
| Thrash rule fires unnecessarily on legitimate re-correction | LOW (addressed) | Thrash scope is per-execution; retries across sessions are allowed and read current plan state |

## Round 1 Disposition

Round 1 surfaced 8 reviewer findings (F-1…F-8) and 7 devil's-advocate findings (DA-1…DA-7). Verify-before-fix applied to each:

| ID | Severity | Evidence | Disposition |
|----|----------|----------|-------------|
| F-1 | HIGH | Verified: `grep -n "Plan-text issues flagged" skills/run-plan/SKILL.md` → empty | Fixed — deleted the original WI 1.4 (which referenced a nonexistent section); instead, WI 1.5 creates new `### Plan-text drift signals` subsections |
| F-2 | HIGH | Verified: Phase 4 commit is "mark … in progress"; Phase 6 is Done transition | Fixed — Phase 3.5 bundle message now reads "(+ auto-corrected N stale acceptance bands)"; for cherry-pick/direct lands with Phase 4 in-progress commit; for PR mode lands on feature branch; tracker scope clarified |
| F-3 | HIGH | Verified (partial): reviewer's claim "no Status/Now/Next/Stop sections" is WRONG — they exist at lines 155/186/198/212. But meta-point (head -225 is pre-Phase-1, not touched by any WI → trivial check) HOLDS | Fixed — replaced with proper `diff` between HEAD and current of lines 1-285 (pre-Phase-1 region); removed the trivial "head -225" phrasing |
| F-4 | MED | Verified: the canary was ungrounded — no script to test | Fixed — extracted parse/compute/edit into `scripts/plan-drift-correct.sh` (Phase 1 WI 1.2); canary tests the script directly |
| F-5 | MED | Verified via self-arithmetic: `≥3` floor, actual ≈5 expected locations → self-stale | Fixed — Acceptance bumped to `≥5` with the 5 locations enumerated inline |
| F-6 | MED | Verified: range vs single-value disambiguation unspecified; `–`/`-` both valid | Fixed — Phase 1 token grammar enumerates 5 forms with parser behavior per form; script unit-tests each form |
| F-7 | LOW | Judgment | Fixed — Phase 1 WI 1.7 + Phase 3 WI 3.5 update `docs/tracking/TRACKING_NAMING.md` for both `phasestep.*.drift-detect` and `phasestep.*.drift-fail` |
| F-8 | LOW | Verified: plan didn't mention CHANGELOG | Fixed — Phase 1 WI 1.8 and Phase 3 WI 3.6 add CHANGELOG entries |
| DA-1 | HIGH | Verified: hook globs `step.*.verify` only; `drift-detect` bypassed | Fixed — Phase 3.5 runs AFTER `.verify`; failure path DELETES `.verify` to block landing; success path writes `phasestep.*.drift-detect` (informational) |
| DA-2 | HIGH | Verified: phasestep.* convention exists, step.* is gate | Fixed — using phasestep.* for Phase 3.5 marker (informational by convention) |
| DA-3 | HIGH | Verified via SKILL.md Phase 2 PR-mode block: PR mode reuses worktree across phases in `finish auto` | Fixed — PR mode commits correction to feature-branch copy in worktree; next phase reads from same worktree; thrash rule explicit about which plan file is read where |
| DA-4 | HIGH | Verified: unanchored grep matches too broadly | Fixed — token includes `phase=N bullet=M`; script `--correct` uses phase+bullet navigation, not grep -n |
| DA-5 | MED | Judgment on self-regression | Fixed — explicit non-goal: "Phase 3.5 should find zero drift on self-execution of THIS plan"; acceptance criteria are tight (≥5 with enumeration) |
| DA-6 | MED | Verified: greedy regex + unbounded `<field>` | Fixed — grammar forbids `:` `=` in `<field>`; parser uses awk field-split, not greedy regex |
| DA-7 | MED | Verified: extraction-rule parser hand-waved | Fixed — extracted to `scripts/plan-drift-correct.sh --eval` (integer +/- only); narrow grammar documented as non-goal |

Convergence: 15 findings, 15 addressed (13 Fixed, 2 Verified-with-partial-correction-of-reviewer's-sub-claim). No findings ignored.

## Plan Quality

**Drafting process:** /draft-plan with 1 round of adversarial review (reviewer + devil's advocate).
**Convergence:** Converged at round 1 after verify-before-fix applied to all findings — a second round is likely to surface only wording polish, not structural issues (all HIGH + MED findings had concrete fixes with citations).
**Remaining concerns:** None blocking execution. Two judgment calls remain explicit:
1. Support grammar is narrow (5 `<stated>` forms, 3 extraction-rule forms) — rare phrasings fall through as "non-derivable" and get post-corrected by Phase 3.5. Trade-off accepted.
2. Thrash scope is per-execution — cross-session retries allowed. If a long-running plan spans multiple sessions and the same correction keeps re-applying, human review needed. Trade-off accepted.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 8 findings        | 7 findings                | 15/15    |
