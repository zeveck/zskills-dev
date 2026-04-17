---
title: Fix Worktree-Add Silent Attach to Poisoned Stale Branches
created: 2026-04-17
status: active
---

# Plan: Fix Worktree-Add Silent Attach to Poisoned Stale Branches

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

Three sites (run-plan:810, fix-issues:787, do:321) use an identical
fallback pattern:

```bash
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main 2>/dev/null \
  || git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
```

The primary form (`-b`) creates a fresh branch from `main`. When that
fails (because the branch already exists), the fallback re-attaches to
the existing branch — **without any verification of whether that
branch is fit to resume on**. This silent attach to stale or poisoned
branches causes real incidents:

- **Aborted previous run left the branch diverged**: the new agent
  resumes mid-broken state, cherry-picks or commits on top of
  poisoned history.
- **Merged-and-not-deleted remote branch**: the local re-attach pulls
  the merged branch which is now equivalent to main — agent does
  zero real work but writes success markers.
- **Different plan slugs colliding on branch names**: cross-plan
  pollution when `$BRANCH_NAME` collides.

The fallback is NEEDED for legitimate multi-phase PR-mode resumes
(Phase 2 reuses Phase 1's feature branch). The fix must
**discriminate** legitimate resume from poisoning — not eliminate the
fallback.

**Discrimination signal**: in legitimate PR-mode resume, the
worktree directory either (a) already exists with a `.worktreepurpose`
file (handled by the existing `if [ -d "$WORKTREE_PATH" ]` branch at
run-plan:806 — this case never reaches the `-b` block) OR (b) does NOT
exist and the branch is fresh (so `-b` succeeds). The fallback path
(`-b` failing) indicates **the branch exists without a worktree
attached to it** — which in practice is always one of the poisoning
cases above.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Poisoned-branch discriminator helper + 3 call sites | 🟡 | | |
| 2 — Canary test coverage | ⬚ | | |

## Shared Conventions

- **Three sites, one helper.** Extract the discrimination logic to
  `scripts/worktree-add-safe.sh` to avoid triplicating bash in skill
  SKILL.md files.
- **Source + mirror sync** after every SKILL.md edit.
- **Per-phase PR**, same pattern as prior plans.
- **Verbatim pattern** (for the grep-anchor that detects the
  unsafe fallback has NOT been removed from any skill): this plan
  MUST NOT leave any remaining
  `git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" main 2>/dev/null \\$`
  line in skills/. Verification after Phase 1:
  `grep -rnE 'git worktree add -b.*main 2>/dev/null' skills/`
  returns no matches.

## Phase 1 — Poisoned-branch discriminator helper + 3 call sites

### Goal

Create `scripts/worktree-add-safe.sh` that encapsulates the
"create-fresh-or-fail-loud" decision and call it from all 3 sites.
Eliminate the silent fallback.

### Work Items

- [ ] **Write `scripts/worktree-add-safe.sh`** with this logic:
      ```bash
      #!/bin/bash
      # scripts/worktree-add-safe.sh BRANCH_NAME WORKTREE_PATH [BASE_BRANCH=main]
      # Creates a git worktree safely — either fresh, or a verified-legitimate
      # resume. Fails loud on poisoned or ambiguous branch state.
      set -eu
      BRANCH_NAME="${1:?missing branch name}"
      WORKTREE_PATH="${2:?missing worktree path}"
      BASE="${3:-main}"

      # Case 1: worktree dir already exists. Caller should have handled this
      # upstream; if we get here, it's a bug.
      if [ -d "$WORKTREE_PATH" ]; then
        echo "ERROR: worktree path $WORKTREE_PATH already exists — caller must" \
             "handle resume before invoking this helper." >&2
        exit 2
      fi

      # Case 2: branch does not exist anywhere — fresh create from BASE.
      if ! git rev-parse --verify --quiet "$BRANCH_NAME" >/dev/null; then
        if ! git rev-parse --verify --quiet "origin/$BRANCH_NAME" >/dev/null; then
          # Fresh branch — create and attach.
          git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE"
          exit 0
        fi
      fi

      # Case 3: branch exists locally or on remote. Classify.
      #
      # Prefer LOCAL branch info if available; else inspect origin.
      REF="$BRANCH_NAME"
      if ! git rev-parse --verify --quiet "$REF" >/dev/null; then
        REF="origin/$BRANCH_NAME"
      fi

      # Count commits ahead of BASE on the candidate branch.
      AHEAD=$(git rev-list --count "$BASE..$REF" 2>/dev/null || echo "0")
      BEHIND=$(git rev-list --count "$REF..$BASE" 2>/dev/null || echo "0")

      # Classify:
      if [ "$AHEAD" = "0" ] && [ "$BEHIND" = "0" ]; then
        # Branch is equivalent to BASE (likely merged-and-not-deleted).
        # Delete it and create fresh.
        echo "NOTE: branch $BRANCH_NAME is equivalent to $BASE — deleting stale ref and creating fresh." >&2
        git branch -D "$BRANCH_NAME" 2>/dev/null || true
        git push origin --delete "$BRANCH_NAME" 2>/dev/null || true
        git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE"
        exit 0
      fi

      if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" = "0" ]; then
        # Branch is strictly behind BASE — this means BASE advanced and
        # branch wasn't rebased. This is a poisoning indicator.
        echo "ERROR: branch $BRANCH_NAME is $BEHIND commits BEHIND $BASE with zero commits ahead — poisoned stale branch." >&2
        echo "       Manual reconciliation required: either rebase the branch, delete it, or use a different plan slug." >&2
        exit 3
      fi

      # Branch is ahead of BASE — potentially legitimate resume.
      # Require caller to opt in via env var ZSKILLS_ALLOW_BRANCH_RESUME=1.
      if [ "${ZSKILLS_ALLOW_BRANCH_RESUME:-}" != "1" ]; then
        echo "ERROR: branch $BRANCH_NAME exists with $AHEAD commits ahead of $BASE." >&2
        echo "       This may be a legitimate multi-phase resume OR a poisoned stale branch." >&2
        echo "       To proceed: set ZSKILLS_ALLOW_BRANCH_RESUME=1 (caller must verify branch fitness first)." >&2
        echo "       To abort and reset: git branch -D $BRANCH_NAME && git push origin --delete $BRANCH_NAME" >&2
        exit 4
      fi

      # Caller opted in — attach worktree to existing branch.
      echo "NOTE: resuming on existing branch $BRANCH_NAME ($AHEAD commits ahead of $BASE)." >&2
      git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
      exit 0
      ```
      Make executable: `chmod +x scripts/worktree-add-safe.sh`.
      Verification: `test -x scripts/worktree-add-safe.sh && bash -n scripts/worktree-add-safe.sh`.

- [ ] **Replace `skills/run-plan/SKILL.md:810-811`** with:
      ```bash
      # Legitimate multi-phase PR-mode resume — opt into branch resume.
      ZSKILLS_ALLOW_BRANCH_RESUME=1 \
        bash scripts/worktree-add-safe.sh "$BRANCH_NAME" "$WORKTREE_PATH" main
      ```
      (The opt-in is set because run-plan's PR-mode is specifically
      designed for multi-phase resume.) Verification:
      `grep -n 'worktree-add-safe.sh' skills/run-plan/SKILL.md` returns 1 match.

- [ ] **Replace `skills/fix-issues/SKILL.md:787-788`** identically.
      fix-issues ALSO supports multi-phase resume within a sprint, so
      same opt-in applies.

- [ ] **Replace `skills/do/SKILL.md:321-322`**:
      ```bash
      # /do expects a fresh branch per task — no legitimate resume.
      bash scripts/worktree-add-safe.sh "$BRANCH_NAME" "$WORKTREE_PATH" main
      ```
      (No opt-in — `/do` is a single-task helper; existing branch with
      `$TASK_SLUG`-derived name is always poisoned.)

- [ ] **Update `skills/update-zskills/SKILL.md` script list** to include
      `scripts/worktree-add-safe.sh` alongside the other core scripts
      (write-landed.sh, land-phase.sh, etc.). Verification:
      `grep -n 'worktree-add-safe' skills/update-zskills/SKILL.md` ≥ 1.

- [ ] **Mirror sync** for run-plan, fix-issues, do, update-zskills.

### Design & Constraints

- **Why an env-var opt-in** (not a script argument flag): the skills
  that have legitimate resume semantics (run-plan, fix-issues) know
  their context at invocation time. The env var keeps the script's
  contract simple (3 positional args) and makes the opt-in visible in
  shell-scan tools. Alternative (flag like `--allow-resume`) would
  require the skills to thread the flag through — more brittle.
- **`git push origin --delete` + `|| true`** — we genuinely DO want
  to silently succeed on push-delete failure, because in CI / no-auth
  environments the remote may not be writable. The local branch
  delete is what matters for subsequent `git worktree add -b`.
- **Classification completeness**: the 4 exit codes (0 success,
  2 misuse, 3 poisoned-behind, 4 ambiguous-ahead) cover the
  classification taxonomy. Anything not in these cases falls into
  exit 0 (fresh create) or exit 4 (ahead without opt-in).
- **`set -eu`**: helper must fail fast. No `2>/dev/null` around the
  actual `git worktree add` operations — errors from git must
  propagate.
- **Tracking marker preservation**: both skills write
  `.zskills-tracked` AFTER worktree creation. The helper doesn't
  touch that step — it returns cleanly and the skill proceeds to
  its own marker write.

### Acceptance Criteria

- [ ] `scripts/worktree-add-safe.sh` exists, is executable, and
      passes `bash -n`. Verification: `test -x scripts/worktree-add-safe.sh && bash -n scripts/worktree-add-safe.sh`.
- [ ] No skill contains the unsafe fallback anymore.
      Verification: `grep -rnE 'git worktree add -b.*2>/dev/null' skills/`
      returns no matches.
- [ ] Each of the 3 skill files now invokes the helper.
      Verification: `grep -c 'worktree-add-safe.sh' skills/run-plan/SKILL.md skills/fix-issues/SKILL.md skills/do/SKILL.md`
      returns 3 (one per file).
- [ ] `do` is the ONLY skill that calls the helper WITHOUT
      `ZSKILLS_ALLOW_BRANCH_RESUME=1`. Verification:
      `grep -B1 'worktree-add-safe.sh' skills/do/SKILL.md` shows no
      env-var prefix; `grep -B1 'worktree-add-safe.sh' skills/run-plan/SKILL.md skills/fix-issues/SKILL.md`
      shows `ZSKILLS_ALLOW_BRANCH_RESUME=1`.
- [ ] Mirror clean. Verification: `diff -r skills/run-plan .claude/skills/run-plan`
      and equivalents for fix-issues, do, update-zskills, all empty.
- [ ] `bash tests/run-all.sh` passes. Existing tests must not regress
      (new-test coverage lands in Phase 2).

### Dependencies

None — this is standalone.

### Verification (phase-exit)

Dispatch a verification agent with the updated skills + the helper.
Present 4 scenarios and ask agent to trace each:
1. Fresh branch, worktree doesn't exist → expected: `-b` form runs, exit 0.
2. Branch equivalent to main (merged/not-deleted) → expected: delete + `-b`, exit 0.
3. Branch behind main, 0 ahead → expected: exit 3 (poisoned).
4. Branch 3 commits ahead of main, `ZSKILLS_ALLOW_BRANCH_RESUME=1` →
   expected: attach, exit 0.
Agent's traced answers must match.

## Phase 2 — Canary test coverage

### Goal

Add canary tests in `tests/test-canary-failures.sh` for the helper's
classification logic, exercising the 4 scenarios above plus edge cases.

### Work Items

- [ ] Add a new section
      `section "worktree-add-safe.sh: poisoned-branch discrimination (6 cases)"`:
      1. **Fresh branch**: no local or remote branch exists → helper
         exits 0, creates worktree via `-b`.
      2. **Equivalent-to-main**: branch exists but `git rev-list
         --count main..branch` = 0 AND `branch..main` = 0 → helper
         deletes stale branch, creates fresh, exits 0.
      3. **Behind-only (poisoned)**: branch exists, behind main with
         0 commits ahead → helper exits 3 with `INVARIANT`-style
         stderr message.
      4. **Ahead without opt-in**: branch ahead of main, no
         `ZSKILLS_ALLOW_BRANCH_RESUME` set → helper exits 4 with
         guidance message.
      5. **Ahead WITH opt-in**: branch ahead, env var set → helper
         exits 0, attaches worktree to existing branch.
      6. **Worktree path already exists (caller bug)**: helper exits
         2 with "caller must handle" error.
      Use `setup_fixture_repo` to build each scenario. Helper asserts:
      `expect_script_exit scripts/worktree-add-safe.sh <args> <expected-rc> <stderr-grep>`.
      Use `FIXTURE_DIRS+=()` for cleanup.

### Design & Constraints

- **Fixture setup** for scenario 2 (equivalent-to-main): in the temp
  repo, create a branch from main, then `git merge --no-ff branch`
  back into main (or rebase branch onto main). Verify `rev-list`
  counts are both 0 before invoking helper.
- **Fixture setup** for scenario 3 (behind): create branch from an
  OLD main commit, then advance main with new commits. Now branch
  is behind.
- **Canary test's `FIXTURE_DIRS` discipline**: every fixture must be
  cleaned up on trap-exit (existing harness handles this). Do not
  rely on `/tmp/` auto-expiration.
- **Follow existing canary style**: one-line comments per test, no
  multi-line docstrings.

### Acceptance Criteria

- [ ] Canary has a new section covering the 6 scenarios.
      Verification: `grep -n 'worktree-add-safe.sh' tests/test-canary-failures.sh`
      returns ≥6 matches (one per test case) + 1 section header.
- [ ] Full canary suite passes. Verification: `bash tests/test-canary-failures.sh`
      exits 0; passed count increases by ≥6 from baseline.
- [ ] `bash tests/run-all.sh` returns 0.
- [ ] No flakiness: run twice in a row, both pass.

### Dependencies

Phase 1 (the helper must exist and be called correctly before tests
can exercise it).

### Verification (phase-exit)

Run the canary suite twice. Confirm all 6 new tests pass on both runs.
Spot-check 2 fixture repos are properly cleaned up (no leftover dirs
under `/tmp/zskills-tests/`).

## Plan Quality

**Drafting process:** Truncated /draft-plan (scope-contained — 2
phases, 1 helper script, 4 skill edits, 6 canary tests). Direct author
+ self-adversarial review.

**Verify-before-fix checks performed:**
1. All 3 sites exist at expected lines (810, 787, 321) — **VERIFIED**
   via `grep -n 'git worktree add -b' skills/run-plan/SKILL.md skills/fix-issues/SKILL.md skills/do/SKILL.md`.
2. `.worktreepurpose` is the documented "legitimate worktree"
   signal — **VERIFIED** via
   `skills/run-plan/SKILL.md:627-636`.
3. The existing `if [ -d "$WORKTREE_PATH" ]` branch handles the
   directory-exists case upstream of the `-b` fallback —
   **VERIFIED** via
   `skills/run-plan/SKILL.md:806-811`.
4. No existing `scripts/worktree-*.sh` helper (we're not colliding
   with a pre-existing script). Verification:
   `ls scripts/worktree-* 2>&1` returns "no such file or directory".

**Remaining concerns:**
- The `ZSKILLS_ALLOW_BRANCH_RESUME=1` env-var opt-in is a trust
  signal, not a verification. run-plan and fix-issues set it blindly
  when the branch exists ahead of main — they don't actually verify
  the branch's commits are theirs. For truly adversarial poisoning
  (an attacker pushes commits to the shared branch name between
  phases), the helper still attaches. Mitigation is out of scope
  for this plan (would require branch signing or a zskills-tracked
  commit-id manifest). Flag as known limitation.
- The classification treats "behind-only" as poisoned, which is
  conservative. In principle, someone could want to resume on a
  branch whose base has advanced. They can work around by rebasing
  the branch onto main before invoking. Documented in the exit-3
  error message.
