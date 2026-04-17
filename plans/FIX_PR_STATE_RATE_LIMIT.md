---
issue: 26
title: Fix gh pr view Rate-Limit Silent Default to OPEN (zombie feature branches)
created: 2026-04-17
status: active
---

# Plan: Fix gh pr view Rate-Limit Silent Default to OPEN

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

`skills/run-plan/SKILL.md:2180` and `skills/do/SKILL.md:421` query PR
state with:

```bash
if ! PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null); then
  echo "WARNING: gh pr view failed ... — defaulting pr_state to OPEN" >&2
  PR_STATE="OPEN"
fi
```

When `gh pr view` returns non-zero (rate limit, 5xx, auth timeout,
transient network), the silent `PR_STATE="OPEN"` default causes the
skill to write `.landed` with `status: pr-ready`, skip cleanup, and
leave the feature branch on `origin`. If the PR had actually merged,
this produces a zombie feature branch on origin and local main
divergence from origin/main. The existing `post-run-invariants.sh`
`INVARIANT-WARN (#7)` detects divergence but only WARNs — it doesn't
fail — so the silent-failure cascade is never blocked.

This plan replaces the silent default with a bounded retry, an explicit
`UNKNOWN` state, and a new mechanical invariant (#8) that FAILs the run
when the ambiguous state is recorded.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Retry + pr-state-unknown at call sites | ✅ | `3679056` | landed via PR (squashed on main) |
| 2 — Invariant #8 + canary tests | ⬚ | | |

## Shared Conventions

- **Two sites only** — `skills/run-plan/SKILL.md:2180` and
  `skills/do/SKILL.md:421`. **Not** `skills/fix-issues/SKILL.md` —
  that file's `gh pr view` calls query `url` or `number`, never
  `state` (verified: `grep -n 'gh pr view' skills/fix-issues/SKILL.md`
  returns 2 matches, both for url/number extraction, neither for
  state).
- **Source + mirror**: every `skills/<name>/SKILL.md` change is
  followed by `rm -rf .claude/skills/<name>/ && cp -r
  skills/<name>/ .claude/skills/<name>/` in the same commit.
  Verification: `diff -r skills/run-plan .claude/skills/run-plan`
  clean after each edit.
- **Per-phase PR**: two phases, two PRs. Phase 2 depends on Phase 1
  (invariant must detect the status string written by the retry
  logic).

## Phase 1 — Retry + pr-state-unknown at call sites

### Goal

Replace the silent `PR_STATE="OPEN"` default with a 3-attempt retry
(sleeps 2s, 4s between tries), record `UNKNOWN` on total failure, and
write `.landed` with `status: pr-state-unknown` when state cannot be
determined.

### Work Items

- [ ] **`skills/run-plan/SKILL.md:2175-2190`**: replace the
      `if ! PR_STATE=...` block with the retry loop:
      ```bash
      PR_STATE="UNKNOWN"
      for attempt in 1 2 3; do
        if STATE_OUT=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>&1); then
          PR_STATE="$STATE_OUT"
          break
        fi
        echo "WARN: gh pr view attempt $attempt failed: $STATE_OUT" >&2
        [ $attempt -lt 3 ] && sleep $((attempt * 2))
      done
      if [ "$PR_STATE" = "UNKNOWN" ]; then
        echo "ERROR: gh pr view failed 3 times for PR #$PR_NUMBER. Recording pr-state-unknown." >&2
        LANDED_STATUS="pr-state-unknown"
      fi
      ```
      Then trace downstream: wherever `.landed` is written after this
      block, use `${LANDED_STATUS:-pr-ready}` (or the existing
      status variable) so UNKNOWN state propagates into the
      `.landed` marker's `status:` field. Verification:
      `grep -nA2 'PR_STATE=' skills/run-plan/SKILL.md` shows the
      retry loop; `grep -n 'pr-state-unknown\|LANDED_STATUS' skills/run-plan/SKILL.md`
      shows ≥2 occurrences (the definition + the downstream usage).
- [ ] **`skills/do/SKILL.md:417-427`**: same pattern. Note: `do` uses
      `"$PR_URL"` (not `"$PR_NUMBER"`) as the argument — preserve
      that. The retry loop is identical except for the argument.
      Verification: `grep -nA2 'PR_STATE=' skills/do/SKILL.md` shows
      the retry loop with `$PR_URL` argument.
- [ ] **Mirror sync** (both skills):
      ```bash
      for s in run-plan do; do
        rm -rf ".claude/skills/$s"
        cp -r "skills/$s" ".claude/skills/$s" || { echo "CP FAILED: $s"; exit 1; }
        diff -r "skills/$s" ".claude/skills/$s" > /dev/null || { echo "DIFF FAILED: $s"; exit 1; }
      done
      ```

### Design & Constraints

- **Sleep backoff**: attempts 1, 2, 3 with sleep `attempt*2` between,
  so total wait on triple-failure is 2+4 = 6 seconds. This is cheap
  enough to always run, and addresses transient rate-limit pressure.
  Do NOT exceed 3 attempts or 8 seconds total — the skill is
  interactive (cron-fired turn) and the user is watching.
- **`UNKNOWN` state propagation**: the CRITICAL invariant is that
  `.landed` is written with `status: pr-state-unknown` (NOT
  `pr-ready`, NOT `full`) when state could not be determined. Phase 2
  invariant #8 depends on this exact string.
- **Stderr, not stdout**: all diagnostic messages go to `>&2` so
  they're visible in the terminal but don't contaminate command
  output capture. Existing pattern at
  `skills/run-plan/SKILL.md:2181,2183` already uses `>&2`; preserve.
- **Preserve existing retry-on-auth-flow**: if `gh auth status` fails
  upstream of this block, the existing skill behavior (prompting the
  user) is untouched. This plan only fixes the already-authed-but-
  rate-limited failure mode.

### Acceptance Criteria

- [ ] `skills/run-plan/SKILL.md` and `skills/do/SKILL.md` contain
      retry loops; no `PR_STATE="OPEN"` silent default remains.
      Verification: `grep -n 'PR_STATE="OPEN"' skills/run-plan/SKILL.md skills/do/SKILL.md`
      returns no matches.
- [ ] `.landed` status `pr-state-unknown` is written on total
      failure. Verification: search both skills for
      `pr-state-unknown` — returns ≥2 occurrences (one per skill).
- [ ] Mirror clean: `diff -r skills/run-plan .claude/skills/run-plan`
      and `diff -r skills/do .claude/skills/do` both empty.
- [ ] Bash snippets compile: extract and run `bash -n` on each
      replaced block; no syntax errors.
- [ ] `bash tests/run-all.sh` passes (Phase 1's test updates land in
      Phase 2; this acceptance confirms no REGRESSION).

### Dependencies

None. This phase can start after Phase 1 of UNIFY_TRACKING_NAMES lands
(separate plan), or independently — no cross-plan dependency.

### Verification (phase-exit)

Dispatch a verification agent (Explore) with updated skill text +
current invariants doc. Ask: "trace what happens end-to-end when
`gh pr view` fails 3 times in a row — does `.landed` get written with
`status: pr-state-unknown`, and does the worktree remain on disk?"
Agent's answer must match expected behavior.

## Phase 2 — Invariant #8 + canary tests

### Goal

Add `INVARIANT-FAIL (#8)` to `scripts/post-run-invariants.sh` that
detects `.landed` files with `status: pr-state-unknown` and fails the
run. Add canary tests in `tests/test-canary-failures.sh` that produce
the failure scenario and assert the invariant fires.

### Work Items

- [ ] **`scripts/post-run-invariants.sh`**: insert invariant #8 after
      the #6 block (which is the last FAIL invariant before the WARN
      block at #7). Exact snippet:
      ```bash
      # #8: .landed recorded an UNKNOWN PR state (gh pr view rate-limited)
      # — manual reconciliation required.
      if [ -n "$WORKTREE_PATH" ] && [ -f "$WORKTREE_PATH/.landed" ]; then
        if grep -q '^status: pr-state-unknown$' "$WORKTREE_PATH/.landed"; then
          INVARIANT_FAILED=1
          echo "INVARIANT-FAIL (#8): $WORKTREE_PATH/.landed has status: pr-state-unknown — gh pr view could not verify; manual reconciliation required" >&2
        fi
      fi
      ```
      Placement: immediately after the #6 block ends (before #7 WARN).
      Verification: `grep -n 'INVARIANT-FAIL.*#8' scripts/post-run-invariants.sh`
      returns 1 match; `grep -cE 'INVARIANT-FAIL.*#[0-9]' scripts/post-run-invariants.sh`
      returns 7 (invariants 1–6, plus 8 — recall #7 is WARN).
- [ ] **Canary tests**: add a new section to
      `tests/test-canary-failures.sh` titled
      `section "post-run-invariants.sh: #8 pr-state-unknown (3 cases)"`:
      1. Fixture: worktree with `.landed` containing
         `status: pr-state-unknown`. Assert script exits rc=1 with
         `INVARIANT-FAIL (#8)` in stderr.
      2. Fixture: worktree with `.landed` containing
         `status: pr-ready`. Assert #8 does NOT fire.
      3. Fixture: worktree with no `.landed`. Assert #8 does NOT
         fire (the guard `[ -f "$WORKTREE_PATH/.landed" ]` short-
         circuits).
      Use existing harness idioms (`expect_script_exit`,
      `setup_fixture_repo`, `FIXTURE_DIRS+=()`).
- [ ] **Canary section count**: update the top-level
      `echo "Running N tests"` header if it tracks total count (or
      omit if the existing harness auto-computes).
      Verification: `bash tests/test-canary-failures.sh` reports a
      total ≥ (previous count + 3).

### Design & Constraints

- **Place #8 BEFORE #7 WARN**: because #7 is a warning (not fail),
  placing #8 after it would mean the ordinal "8" appears in a
  non-increasing sequence. Standard practice is FAIL→WARN ordering,
  so new FAILs go before the first WARN. Verification: after Phase 2,
  `grep -nE 'INVARIANT-(FAIL|WARN)' scripts/post-run-invariants.sh`
  shows ordering FAIL #1, #2, #3, #4, #5, #6, #8, WARN #7.
- **Exact status string**: `pr-state-unknown` — hyphenated,
  lowercase, as written in Phase 1. Any drift between Phase 1's
  writer and Phase 2's reader breaks detection. The greppable
  anchor `^status: pr-state-unknown$` is the contract between
  phases.
- **Worktree guard**: `[ -n "$WORKTREE_PATH" ]` avoids false-fire
  when invariants run outside a plan context. The existing
  invariants (#1-#6) use the same guard pattern.

### Acceptance Criteria

- [ ] `scripts/post-run-invariants.sh` contains invariant #8 exactly
      as specified. Verification: `grep -c 'INVARIANT-FAIL.*#8' scripts/post-run-invariants.sh`
      returns 1.
- [ ] `tests/test-canary-failures.sh` contains the new 3-case section.
      Verification: `grep -n 'pr-state-unknown' tests/test-canary-failures.sh`
      returns ≥3 matches (section header + 3 test fixtures).
- [ ] Full test suite passes. Verification: `bash tests/run-all.sh`
      returns 0.
- [ ] Bash syntax clean. Verification:
      `bash -n scripts/post-run-invariants.sh && bash -n tests/test-canary-failures.sh`.

### Dependencies

Phase 1 (the writer must produce `status: pr-state-unknown` before the
invariant can detect it).

### Verification (phase-exit)

End-to-end simulation: hand-craft a fake `.landed` with
`status: pr-state-unknown`, run
`WORKTREE_PATH=/tmp/fake-worktree bash scripts/post-run-invariants.sh`,
confirm rc=1 + stderr mentions `INVARIANT-FAIL (#8)`.

## Plan Quality

**Drafting process:** Truncated /draft-plan (scope-contained — 2
phases, 2 files touched per phase, a known spec from issue #26). Direct
author + self-adversarial review rather than full 2-round agent
process; spec text from issue #26 provided a pre-verified baseline.

**Verify-before-fix checks performed:**
1. Issue #26 claims three site files (run-plan, do, fix-issues) —
   **VERIFIED FALSE for fix-issues**. That file has `gh pr view` but
   only for URL/number queries, not state. Plan corrected to 2 sites.
   Verification: `grep -nE 'gh pr view.*state|PR_STATE=' skills/fix-issues/SKILL.md`
   returns 0 matches.
2. `scripts/post-run-invariants.sh` existing invariant count —
   **VERIFIED 6 FAIL + 1 WARN**. Invariant #8 placed between #6 and
   #7.
3. `.landed` marker writer pattern — **VERIFIED** via
   `scripts/write-landed.sh` and heredoc sites in skills. The new
   `pr-state-unknown` status string flows through the existing
   atomic-write helper.

**Remaining concerns:**
- The `LANDED_STATUS` variable introduced in Phase 1 must not
  collide with any existing variable name. Implementer should
  `grep -n 'LANDED_STATUS' skills/run-plan/SKILL.md` before
  committing — expect 0 pre-existing matches.
- If `gh pr view` fails but prints HTML or non-JSON output to stderr,
  the `$STATE_OUT` variable captures it. The downstream comparison
  `[ "$PR_STATE" = "UNKNOWN" ]` still works because `$PR_STATE` only
  changes if the command succeeds. Phase 1 implementer should confirm
  this behavior in an edge-case test (HTML response simulated via
  `gh_view_fail_helper`).
