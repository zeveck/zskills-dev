---
title: PR Landing Unification — extract /land-pr from 5 duplicating skills
created: 2026-04-27
status: complete
---

# Plan: PR Landing Unification

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Five skills each independently implement "land via PR" orchestration: `/run-plan` (`skills/run-plan/modes/pr.md`), `/commit pr` (`skills/commit/modes/pr.md`), `/do pr` (`skills/do/modes/pr.md`), `/fix-issues pr` (`skills/fix-issues/modes/pr.md`), and `/quickfix` (`skills/quickfix/SKILL.md`). The duplicated machinery is rebase + push + `gh pr create` + CI poll + fix-cycle agent dispatch + optional `gh pr merge --auto` + `.landed` marker write.

This duplication has produced documented drift bugs that were patched separately in different skills:

- **87af82a** (2026-04-18) fixed the `gh pr checks --watch` exit-code-unreliable bug in `/run-plan` only.
- **1de3049** (2026-04-18, 8 minutes later) fixed the same bug in `/commit` and `/do` separately.
- **175e4aa** (2026-04-18) hardened `/run-plan`'s push / PR-number / PR-URL silent-failure modes; the same hardenings were never propagated to `/commit pr`, `/do pr`, or `/fix-issues pr`, all of which still have variants of those bugs.
- **b904cef** (PR #75, 2026-04-27) fixed `/fix-issues` PR-mode gating to follow the canonical pattern: only `gh pr merge --auto --squash` is gated on the caller's `$AUTO` flag; rebase, push, PR creation, CI poll, and fix cycle ALL run unconditionally. PR #75 explicitly deferred the broader unification as a `/draft-plan` candidate — this plan.

`/quickfix`'s current "fire-and-forget" design (no CI poll, no fix-cycle) is **drift, not a feature**: per maintainer direction, `/quickfix` should have the same PR + CI monitoring + fix-cycle behavior as the other four skills.

This plan creates a new **`/land-pr`** skill that the five callers dispatch via the Skill tool. `/land-pr` owns the deterministic primitives (four bash scripts) and the canonical procedure prose. The fix-cycle agent dispatch stays in each caller (the caller knows the work context and constructs the right agent prompt). The caller wraps `/land-pr` in a small fix-cycle loop following a canonical pattern.

**Inherited from PR #75:** only `gh pr merge --auto --squash` is gated on the caller's auto-merge flag. Rebase, push, PR creation, CI poll, and fix cycle all run unconditionally.

**Cross-skill dispatch model:** Per `skills/research-and-plan/SKILL.md:87-105`, the Skill tool is the recursion mechanism — invoking `/land-pr` via `Skill: { skill: "land-pr", args: "..." }` loads `/land-pr`'s instructions into the **same** conversation context as the caller. There is no subprocess return value; data hand-off uses a file-based result contract with a safe allow-list parser (the caller passes `--result-file <path>`, `/land-pr` writes `KEY=VALUE` lines there with single-line shell-safe values, the caller reads via line-by-line allow-list parsing — never `source`).

**PR body ownership:** `/land-pr` writes the PR body **only on initial PR creation**. Subsequent body updates (e.g., `/run-plan`'s per-phase progress splice) are the caller's responsibility — performed before the caller invokes `/land-pr`. This preserves callers' splice patterns (e.g., `/run-plan`'s HTML-comment-marker splice — markers defined in `modes/pr.md:221-224`, splice implementation in `SKILL.md:1715-1745` using bash-regex `BASH_REMATCH`) and avoids destroying user-added review notes.

**Subagent boundary:** `/land-pr` is invoked at orchestrator level only — never from within an Agent-dispatched subagent. The fix-cycle agent dispatch in the caller's loop is similarly orchestrator-level. This is a documented contract (no runtime guard exists; a misbehaving caller could violate it but conformance assertions check that callers' SKILL.md invokes `/land-pr` from the right level of nesting).

**Out of scope:** the broader Claude Code subagent-spawning-subagent constraint, cherry-pick and direct landing modes, `/commit`'s `land` subcommand, GitLab support, review handling.

**Rollback:** Phase 1 ships `/land-pr` but no caller dispatches it, so main behavior is unchanged. Phases 2–5 each migrate one caller (or pair) — if a phase reveals a design flaw, revert that phase's PR while keeping prior phases. Phase 6 (drift-prevention conformance) is the last gate; the grep tripwires there flag any remaining inline `gh pr create`/`checks`/`merge` if a migration was incomplete.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1A — `/land-pr` foundation: skill + 4 scripts + caller-facing references + smoke | ✅ Done | `6d0d0ab` | SKILL + 4 scripts + 2 references + mirror; smoke PR #158 created+closed; 1722/1722 tests; shellcheck clean; bug fix: BRANCH_SLUG for /tmp paths |
| 1B — `/land-pr` validation: failure-modes doc + mocks + tests + conformance | ✅ Done | `04d4d3d` | failure-modes catalog (10 modes) + 2 mocks + 23 land-pr unit tests + 37 conformance assertions + 5 helpers; 1782/1782 tests (+60); shellcheck clean; mirror byte-identical |
| 2 — Migrate `/run-plan` PR mode to `/land-pr` (caller owns body splice) | ✅ Done | `bfc265d` | inline block (681→545 lines) replaced with /land-pr Skill dispatch + caller loop; 0 inline gh pr create/merge/checks --watch; 4 new conformance assertions + WATCH_EXIT relocated to land-pr; tests/test-landed-schema.sh (6 cases); 1792/1792 tests; WI 2.9 (canary) deferred to Phase 3 fire (architectural) |
| 3 — Migrate `/commit pr` and `/do pr` to `/land-pr` (drift fix: gain fix-cycle) | ✅ Done | `453a5af` | /commit pr + /do pr migrated to caller-loop pattern; both GAIN fix-cycle; skills/commit/scripts/poll-ci.sh deleted (orphan); /do/SKILL.md "report-only CI" key-rule REMOVED + literal `gh pr create` dropped; PR #131 preamble relocated to /land-pr; 1790/1790 tests (-2 from in-place assertion upgrade); manual canary deferred (architectural) |
| 4 — Migrate `/fix-issues pr` to `/land-pr` (drop 300s timeout special case) | ✅ Done | `306e2c2` | per-issue caller-loop dispatching /land-pr inside `for issue in FIXED_ISSUES`; --issue=$ISSUE_NUM passthrough; 300s timeout dropped (default 600s); /fix-issues pr GAINS canonical fix-cycle (drift fix); 4 conformance assertions removed + 4 added; 1790/1790 tests; canary deferred (architectural) |
| 5 — Migrate `/quickfix` to `/land-pr` (drift fix: gain CI monitoring + fix-cycle) | ✅ Done | `287931d` | Phase 7 (lines 994-1081) replaced with caller-loop dispatching /land-pr (no --worktree-path, no --auto); fix-cycle context = $DESCRIPTION + commit subject; "Fire-and-forget" prose REMOVED (line 20 + 1102) → "triage→review→commit→push→PR→CI poll→fix cycle"; pre-PR triage + plan-review gates preserved; fulfillment-marker model preserved (no .landed); 3 conformance assertions added; tests/test-quickfix.sh: extract_full_flow stops at Phase 7, Case 13 regex tightened (strengthened, catches printf > .landed too), Case 43 trimmed + 43b added; 1794/1794 tests; canary deferred (architectural) |
| 6 — Drift-prevention conformance + canary | ✅ Done | `a51580a` | 8 cross-skill anchored-pattern tripwires (3 invocation patterns × 2 trees + 1 dispatch presence + 1 orchestrator-level dispatch) in tests/test-skill-conformance.sh; plans/CANARY_LAND_PR.md (276 lines, deliberate-fail iteration 1 → fix-cycle → iteration 2 success); PLAN_INDEX → Complete; CHANGELOG 2026-05-01 entry; frontmatter status: complete folded in (matches DRAFT_TESTS/ADAPTIVE_CRON_BACKOFF/IMPROVE_STALENESS_DETECTION pattern); 1801/1802 tests (1794 + 8 - 1 transient AC-7 worktree-vs-main race; CI will pass); WI 6.6 (RUN_ORDER_GUIDE) deferred — file on docs/run-order-guide branch |

## Phase 1A — `/land-pr` foundation: skill + 4 scripts + caller-facing references + smoke

### Goal

Create the `/land-pr` skill with the four deterministic scripts, canonical procedure prose, the file-based result contract (with safe allow-list parsing), the canonical `.landed` schema, AND the caller-facing references that Phases 2–5 will copy from (caller-loop pattern, fix-cycle agent prompt template). Smoke-checkpoint validates the foundation end-to-end. Comprehensive tests, mocks, conformance assertions, and failure-mode documentation are deferred to Phase 1B.

**Why split from comprehensive tests:** Phase 1A is the foundation that Phases 2–5 dispatch and copy from. It's ~10 WIs, ~700 lines of new code. Phase 1B (tests + conformance + mocks) is ~5 WIs, ~900 lines — bulky but mechanically simpler. Keeping them separate gives reviewable PR boundaries and lets a foundation flaw be caught at the end of 1A's smoke, not tangled with test scaffolding written on top of broken scripts.

### Work Items

- [ ] **WI 1.1 — Skill frontmatter.** Create `skills/land-pr/SKILL.md` with frontmatter:
  ```yaml
  ---
  name: land-pr
  description: Land an existing feature branch as a PR. Rebase, push, create-or-detect PR, poll CI, and (gated on caller's --auto flag) auto-merge. Returns structured state via --result-file for caller-driven fix-cycle loops on CI failure. Caller invokes only at orchestrator level (not from within Agent-dispatched subagents). Invoked directly by users with hand-crafted feature branches, and via Skill tool by /run-plan, /commit pr, /do pr, /fix-issues pr, /quickfix.
  argument-hint: --branch <name> --title <title> --body-file <path> --result-file <path> [--auto] [--worktree-path <path>] [--landed-source <skill>] [--ci-timeout <sec>] [--no-monitor] [--pr <num>] [--issue <num>]
  ---
  ```
  No `disable-model-invocation`, no `user-invocable: false`. Both you and Claude can invoke; both via slash command and via Skill-tool dispatch.

  **No `allowed-tools` field (per DA1-9):** verified that `grep -l "allowed-tools" skills/*/SKILL.md` returns 0 hits — no zskills skill currently uses this field. Introducing it on /land-pr alone would be inconsistent and would confuse the conformance test landscape. If a hardening sweep across all skills is desired, it belongs in a separate plan (out of scope here).

- [ ] **WI 1.2 — Argument parsing.** `/land-pr`'s SKILL.md parses `$ARGUMENTS` using bash regex (the established pattern in `/quickfix` and `/do`). Required: `--branch`, `--title`, `--body-file`, `--result-file`. Optional: `--auto` (bool, default false), `--worktree-path`, `--landed-source` (default `land-pr`), `--ci-timeout` (default 600), `--no-monitor` (skip CI poll, return after create — see use-case note in WI 1.12), `--pr <num>` (resume mode: skip rebase/push/create, jump to monitor only), `--issue <num>` (passes through to `.landed` schema). Validate: branch is not `main`/`master`; body-file exists and is non-empty; title is non-empty and ≤ 120 chars; result-file's parent directory exists.

- [ ] **WI 1.3 — `pr-rebase.sh`.** Create `skills/land-pr/scripts/pr-rebase.sh`. Args: `--branch <name>` `--base <branch>` (default `main`). Behavior: `git fetch origin <base>`; `git rebase origin/<base>`. On clean rebase or "already up to date" (idempotent re-invocation): exit 0. On rebase conflicts, **the order MUST be capture-then-abort** (per DA2-7: `git rebase --abort` resets the working tree and erases conflict markers, after which `git diff --name-only --diff-filter=U` returns nothing; the existing `run-plan/modes/pr.md:30, 121` sites both capture BEFORE abort): step 1 — capture conflict files into a sidecar via `CONFLICT_FILES=$(git diff --name-only --diff-filter=U); printf '%s\n' "$CONFLICT_FILES" > /tmp/land-pr-conflict-files-$BRANCH-$$.txt`; step 2 — `git rebase --abort` only after the sidecar write completes successfully (check `[ -s "$SIDECAR" ] || echo "WARN: empty conflict-files sidecar" >&2` before abort); step 3 — verify abort succeeded (`if [ $? -ne 0 ]; then exit 11 with abort-failed stderr`); step 4 — emit `CONFLICT_FILES_LIST=<path>` to stdout, exit 10.

  **Reason token (per R2-2 / Round 5 candidate #5 / DA1-8 marker discipline):** populate the result-file's `REASON=<token>` field on exit 11 to distinguish failure subtypes — `REASON=not-a-repo` (git rev-parse failed), `REASON=branch-absent` (branch ref doesn't exist locally and not on remote), `REASON=network` (fetch failed), `REASON=abort-failed` (rebase --abort returned non-zero — repo in intermediate state, manual cleanup needed). Caller's loop dispatches on `REASON` for retry-on-network-only logic when desired.

  On other failure (not in git repo, branch absent, fetch fails): exit 11 with stderr error AND populated `REASON`. **Why split out:** rebase conflicts need orchestrator judgement (agent-assisted resolution? manual? abort?). The script never tries to resolve conflicts itself.

  Idempotency note (verified per git documentation): `git rebase origin/<base>` is a no-op when the local branch is already on top of the base. The fix-cycle re-invocation case (caller pushed a fix commit, /land-pr is called again) does NOT cause spurious conflicts — the local branch's new commits are already rebased on origin/main from the prior pass. WI 1B.3 includes an explicit test case for this.

- [ ] **WI 1.4 — `pr-push-and-create.sh`.** Create `skills/land-pr/scripts/pr-push-and-create.sh`. Args: `--branch <name>` `--base <branch>` `--title <title>` `--body-file <path>`. Behavior:
  1. Detect existing PR via `gh pr list --head "$BRANCH" --base "$BASE" --json number,url 2>"$STDERR_LOG"`. Parse the JSON output via bash regex (no `jq` binary — `gh ... --json` is gh's built-in formatter):
     ```bash
     PR_LIST_JSON=$(gh pr list --head "$BRANCH" --base "$BASE" --json number,url) || { echo "ERROR: gh pr list failed: $(cat "$STDERR_LOG")" >&2; exit 13; }
     if [[ "$PR_LIST_JSON" =~ \"number\":[[:space:]]*([0-9]+) ]]; then
       PR_NUMBER="${BASH_REMATCH[1]}"
       [[ "$PR_LIST_JSON" =~ \"url\":[[:space:]]*\"([^\"]+)\" ]] && PR_URL="${BASH_REMATCH[1]}"
       PR_EXISTING=true
     else
       PR_EXISTING=false
     fi
     ```
     If multiple open PRs from the same branch exist (force-push artifact), the first `BASH_REMATCH` capture wins (the most recent); log a warning to stderr but proceed.
  2. Push: `git push -u origin "$BRANCH"` (or `git push` if upstream already set). On non-zero exit, exit 12 with the captured stderr — no `|| true`, no `2>/dev/null`.
  3. If `PR_EXISTING=true`:
     - **Body update is the caller's responsibility, not /land-pr's.** This script does NOT call `gh pr edit --body-file`. Rationale: `/run-plan`'s per-phase update uses HTML-comment-marker splicing (markers defined at `skills/run-plan/modes/pr.md:221-224`, splice implementation at `skills/run-plan/SKILL.md:1715-1745` using bash-regex `BASH_REMATCH`) to preserve user-added review notes; a wholesale body replacement here would destroy those edits. Callers that need body updates handle them in their own prose before invoking `/land-pr` (see Phase 2 WI 2.1).
     - Emit `PR_EXISTING=true PR_URL=<url> PR_NUMBER=<num>` to stdout, exit 0.
  4. Else (no existing PR): `gh pr create --base "$BASE" --head "$BRANCH" --title "$TITLE" --body-file "$BODY_FILE"`. **Race-condition note:** if a parallel `/land-pr` invocation just created a PR for the same branch (`gh pr list` race window), `gh pr create` will fail with an "already exists" error — gh enforces one open PR per head branch. The losing invocation receives exit 13 with the stderr captured; caller's loop handles it as `STATUS=create-failed`. No duplicate PRs are created. Exit 13 on creation failure.
  5. Extract `PR_NUMBER` from create output's URL via parameter expansion `${URL##*/}` (per fix 175e4aa — never via second `gh pr view`). Validate it's all-digits via `[[ "$PR_NUMBER" =~ ^[0-9]+$ ]]`; if not, exit 14.
  6. Emit `PR_EXISTING=false PR_URL=<url> PR_NUMBER=<num>` to stdout, exit 0.

  **Why combined:** push and create are sequential with no orchestrator decision between them. If push fails, create can't run.

- [ ] **WI 1.5 — `pr-monitor.sh` (consolidated successor to `skills/commit/scripts/poll-ci.sh`).** Create `skills/land-pr/scripts/pr-monitor.sh`. **Consolidation decision (per R1-2 + DA1-3):** `pr-monitor.sh` is the canonical implementation of the `--watch + re-check` primitive across all callers. PR #142's `skills/commit/scripts/poll-ci.sh` (verified at `skills/commit/scripts/poll-ci.sh:31-57`) implements the same primitive but emits prose instead of structured `KEY=VALUE` and lacks failure-log capture. After Phase 3 migrates `/commit pr` to dispatch `/land-pr`, `poll-ci.sh` becomes dead code; **WI 3.5a (added below) deletes it**. The conformance assertion at `tests/test-skill-conformance.sh:151` (`commit "step6: poll-ci.sh invocation"`) is removed in WI 3.4 and replaced with the /land-pr dispatch assertion.

  **Pre-existing bug to surface (per CLAUDE.md "skill-framework repo — surface bugs, don't patch"):** `skills/commit/scripts/poll-ci.sh:34,49,51` use `2>/dev/null` on fallible operations — a documented CLAUDE.md violation. `pr-monitor.sh` MUST NOT inherit these silenced redirects. All stderr from fallible gh calls in `pr-monitor.sh` goes to a captured log file (`$STDERR_LOG`) and is surfaced in the result-file's `CALL_ERROR_FILE` sidecar on failure — never silently dropped.

  Args: `--pr <number>` `--timeout <sec>` (default 600) `--log-out <path>`. Behavior:
  1. Pre-check loop: 3 attempts with 10s sleep, query `gh pr checks "$PR" --json name 2>"$STDERR_LOG"`. Parse with bash regex `\[.*\]` to detect non-empty array. On count > 0, break.
  2. If count == 0 after retries: emit `CI_STATUS=none`, exit 0.
  3. Initial poll: `timeout "$TIMEOUT" gh pr checks "$PR" --watch 2>"$LOG_OUT.stderr"`. Capture exit code as **`WATCH_EXIT`** (NOT `WATCH_RC` — per DA2-5: the existing conformance assertion at `tests/test-skill-conformance.sh:68` is `check_fixed run-plan "timeout 124 handling" 'WATCH_EXIT" -eq 124'`, which RELOCATES to `land-pr` per WI 2.7. Naming the variable `WATCH_RC` would force the assertion to be REWRITTEN at relocation time. Using `WATCH_EXIT` keeps the assertion mechanically RELOCATABLE).
  4. **Honor only `WATCH_EXIT=124`** (timeout's exit for "still running") → emit `CI_STATUS=pending`, exit 0. For all other watch exit codes, IGNORE and re-check.
  5. Re-check (per fix 87af82a): bare `gh pr checks "$PR" >/dev/null 2>"$STDERR_LOG"`. Exit 0 → `CI_STATUS=pass`. Exit 1 → `CI_STATUS=fail`. Exit 8 → `CI_STATUS=pending`. Other → `CI_STATUS=unknown` (with stderr captured to `$LOG_OUT.stderr`).
  6. On `CI_STATUS=fail`, capture failure log: extract a run ID via `gh pr checks "$PR" --json link` and bash-regex on the URL, then run `gh run view --log-failed <run-id> > "$LOG_OUT"`. If run-ID extraction fails, emit `CI_LOG_FILE=` (empty) — caller's fix-cycle agent must handle missing log gracefully.
  7. Emit final `CI_STATUS=...` and `CI_LOG_FILE=...` to stdout, exit 0 (poll completed regardless of pass/fail).
  8. Exit 20 if pre-conditions invalid (PR number non-numeric, or `gh auth status` returns non-zero on first call — fail-fast on auth).

- [ ] **WI 1.6 — `pr-merge.sh`.** Create `skills/land-pr/scripts/pr-merge.sh`. Args: `--pr <number>` `--auto-flag <true|false>` `--ci-status <pass|fail|pending|none|skipped|unknown>`. Behavior:
  1. If `auto-flag != true`: emit `MERGE_REQUESTED=false MERGE_REASON=auto-not-requested`, exit 0.
  2. If `ci-status` not in `{pass, none, skipped}`: emit `MERGE_REQUESTED=false MERGE_REASON=ci-not-passing`, exit 0.
  3. `gh pr merge "$PR" --auto --squash 2>"$STDERR_LOG"`. Capture stderr.
  4. If stderr matches `auto[- ]merge.*not.*allowed|auto[- ]merge.*disabled|repo.*does not allow auto[- ]merge` (bash regex): treat as benign repo-setting — emit `MERGE_REQUESTED=false MERGE_REASON=auto-merge-disabled-on-repo`, exit 0.
  5. On other gh error: write the stderr text to a sidecar file (`/tmp/land-pr-merge-error-$PR-$$.txt`), emit `MERGE_REQUESTED=false MERGE_REASON=gh-error CALL_ERROR_FILE=<path>` (NOT raw stderr text — see WI 1.7 safety note), exit 30.
  6. On success: retry `gh pr view "$PR" --json state --jq '.state'` up to 3 times with 2s/4s backoff. If all 3 fail, emit `PR_STATE=UNKNOWN`. Else emit `PR_STATE=<OPEN|MERGED>`.
  7. Emit `MERGE_REQUESTED=true PR_STATE=...`, exit 0.

- [ ] **WI 1.7 — File-based result contract (safe parsing).** `/land-pr`'s SKILL.md prose composes the final result and writes to `$RESULT_FILE` (one `KEY=VALUE` per line). **Safety contract:** every value is a single-line, shell-safe token (no newlines, no `$`, no backticks, no `&`/`?`/`#` metacharacters). Multi-line content (stderr text, file lists) goes in **sidecar files** referenced by path, not inlined into the result file.

  Result file schema:
  ```
  STATUS=created|monitored|merged|push-failed|rebase-conflict|create-failed|monitor-failed|merge-failed
  PR_URL=<https-url-no-metacharacters-or-empty>
  PR_NUMBER=<digits-or-empty>
  PR_EXISTING=true|false
  CI_STATUS=pass|fail|pending|none|skipped|unknown|not-monitored
  CI_LOG_FILE=<path-or-empty>
  MERGE_REQUESTED=true|false
  MERGE_REASON=auto-not-requested|ci-not-passing|auto-merge-disabled-on-repo|gh-error|empty
  PR_STATE=OPEN|MERGED|UNKNOWN|not-checked
  REASON=<short-token-or-empty>           # e.g., rebase-conflict-too-many-files
  CONFLICT_FILES_LIST=<path-or-empty>     # sidecar file with one conflict path per line
  CALL_ERROR_FILE=<path-or-empty>         # sidecar file with stderr text from failed gh/git call
  ```

  **Writer-side validation (mandatory before write):** every VALUE must be single-line ASCII (no `\n`, no `\r`, no `$`, no backticks, no `&`, `?`, `#` metacharacters). The /land-pr SKILL.md prose validates each value via:
  ```bash
  validate_result_value() {
    local key="$1" value="$2"
    if [[ "$value" =~ [$'\n\r$`&?#'] ]]; then
      echo "ERROR: result-file VALUE for $key contains forbidden characters" >&2
      return 1
    fi
  }
  ```
  before writing each line. Multi-line content goes in sidecar files (path-only goes in the result file). This guarantees the allow-list parser cannot encounter truncated values, embedded shell metacharacters, or surprise-multi-line content.

  The result file is overwritten atomically: write to `$RESULT_FILE.tmp`, then `mv` to `$RESULT_FILE`.

  **Caller parsing pattern (allow-list, never `source`):**
  ```bash
  RESULT_FILE="/tmp/land-pr-result-$BRANCH_NAME-$$.txt"
  # ... compose body to /tmp/pr-body-...md ...
  # Skill: { skill: "land-pr", args: "--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=/tmp/pr-body-...md --result-file=$RESULT_FILE [other flags]" }
  # After Skill invocation completes:
  if [ ! -f "$RESULT_FILE" ]; then
    echo "ERROR: /land-pr produced no result file" >&2
    exit 1
  fi
  declare -A LP   # associative array; allow-listed keys only
  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
      MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
      CONFLICT_FILES_LIST|CALL_ERROR_FILE)
        LP["$KEY"]="$VALUE" ;;
      "") ;;  # blank line
      *) printf 'WARN: /land-pr result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
    esac
  done < "$RESULT_FILE"
  STATUS="${LP[STATUS]}"
  CI_STATUS="${LP[CI_STATUS]}"
  PR_URL="${LP[PR_URL]}"
  # etc — explicit assignments per key, no eval, no source.
  rm -f "$RESULT_FILE"
  ```

  This pattern **never executes the file's contents as shell**, so a maliciously-crafted PR title or body that produces shell-injection-able stderr text cannot reach shell evaluation. The allow-list also catches truncated or malformed result files.

- [ ] **WI 1.8 — `caller-loop-pattern.md` reference.** Create `skills/land-pr/references/caller-loop-pattern.md` with a complete, production-ready bash implementation of the canonical caller fix-cycle loop. NOT pseudocode — actual bash that callers copy verbatim and customize only the agent-prompt-construction block. Pattern (full):

  ```bash
  # === BEGIN CANONICAL /land-pr CALLER LOOP ===
  # Caller fills in: $BRANCH_NAME, $PR_TITLE, $BODY_FILE, $WORKTREE_PATH (optional),
  # $LANDED_SOURCE, $AUTO ("true"/"false"), $CI_MAX_ATTEMPTS (default 2),
  # and the fix-cycle agent dispatch block below.

  ATTEMPT=0
  MAX="${CI_MAX_ATTEMPTS:-2}"
  RESULT_FILE="/tmp/land-pr-result-$BRANCH_NAME-$$.txt"

  while :; do
    # Caller is responsible for any per-iteration body update BEFORE invoking /land-pr.
    # /run-plan splices its progress section into $BODY_FILE here.
    # Other callers regenerate $BODY_FILE here if they need to.
    #
    #   <CALLER_PRE_INVOKE_BODY_PREP>
    #
    LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE"
    [ -n "$WORKTREE_PATH" ] && LAND_ARGS="$LAND_ARGS --worktree-path=$WORKTREE_PATH"
    [ "$AUTO" = "true" ] && LAND_ARGS="$LAND_ARGS --auto"
    [ -n "$ISSUE_NUM" ] && LAND_ARGS="$LAND_ARGS --issue=$ISSUE_NUM"

    # Invoke /land-pr via Skill tool. (Caller's prose tells Claude to invoke it.)
    # Skill: { skill: "land-pr", args: "$LAND_ARGS" }
    # When /land-pr's procedure completes, $RESULT_FILE is populated.

    if [ ! -f "$RESULT_FILE" ]; then
      echo "ERROR: /land-pr produced no result file" >&2
      exit 1
    fi

    # SAFE allow-list parsing (per WI 1.7).
    declare -A LP
    while IFS='=' read -r KEY VALUE; do
      case "$KEY" in
        STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|CONFLICT_FILES_LIST|CALL_ERROR_FILE)
          LP["$KEY"]="$VALUE" ;;
      esac
    done < "$RESULT_FILE"
    STATUS="${LP[STATUS]}"
    CI_STATUS="${LP[CI_STATUS]}"
    # Sidecar cleanup — capture paths of files that should be cleaned up.
    # Per DA1-12: do NOT include CI_LOG_FILE in this list. The cleanup pattern below was previously
    # `[[ "$f" != *"$CI_LOG_FILE"* ]]`, which has two bugs: (a) when CI_LOG_FILE is empty (the CI=pass
    # case), the pattern `*""*` matches everything → no sidecars are cleaned, leaking indefinitely;
    # (b) substring containment can spuriously skip CALL_ERROR_FILE if its path happens to contain
    # CI_LOG_FILE as a prefix. Build the array from cleanup-targets only:
    # Per DA2-11: use an array (not space-joined string) to avoid field-splitting bugs
    # if a sidecar path ever contains spaces. Trivial bash, no metacharacter pitfalls.
    _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}")
    rm -f "$RESULT_FILE"

    case "$STATUS" in
      rebase-conflict)
        # Caller-specific: if conflict-file count is small, dispatch agent-assisted
        # rebase resolution at orchestrator level, then `continue` to re-invoke /land-pr.
        # If too large or no agent path, break and let .landed conflict marker stand.
        #
        #   <CALLER_REBASE_CONFLICT_HANDLER>
        #
        break ;;
      push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
        echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
        break ;;
      created|monitored|merged) ;;  # fall through to CI-status check
    esac

    case "$CI_STATUS" in
      pass|none|skipped)
        break ;;  # /land-pr already requested merge if --auto
      pending)
        break ;;  # settle at pr-ready; user / cron can resume with --pr
      fail)
        if [ "$ATTEMPT" -ge "$MAX" ]; then
          echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
          break
        fi
        # ===== CALLER-SPECIFIC FIX-CYCLE AGENT DISPATCH =====
        # The agent runs at orchestrator level (NOT a nested subagent — /land-pr
        # was already invoked at orchestrator level via the Skill tool; this dispatch
        # is at the same level).
        #
        # Caller customizes the prompt with their work context (plan content,
        # issue body, task description, etc.) and the failure log path
        # (${LP[CI_LOG_FILE]}).
        #
        #   <DISPATCH_FIX_CYCLE_AGENT_HERE>
        #
        # ====================================================
        ATTEMPT=$((ATTEMPT + 1))
        continue ;;  # re-enter loop, /land-pr is idempotent
      unknown)
        echo "WARN: CI_STATUS=unknown — settling at pr-ready" >&2
        break ;;
    esac
  done

  # Sidecar cleanup (after final iteration). _CLEANUP_PATHS contains only
  # CALL_ERROR_FILE and CONFLICT_FILES_LIST (transient). CI_LOG_FILE is intentionally
  # NOT in the array — the caller may want to retain failure logs after the loop exits;
  # if cleanup is needed, the caller does it explicitly after consuming the log.
  for f in "${_CLEANUP_PATHS[@]}"; do
    [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
  done
  # === END CANONICAL /land-pr CALLER LOOP ===
  ```

  Document explicitly: `/land-pr` is **idempotent per call** — re-invoking with the same branch is a no-op for steps already done (rebase already up to date, push already up to date, PR already exists). Body updates are the caller's responsibility (see `<CALLER_PRE_INVOKE_BODY_PREP>`).

- [ ] **WI 1.9 — Fix-cycle agent prompt template.** Create `skills/land-pr/references/fix-cycle-agent-prompt-template.md`. Template structure same as Round-1 plan (caller fills in `<CALLER_WORK_CONTEXT>`). Add explicit constraint: *"You are running at orchestrator level. Do NOT dispatch further Agent tools. If your fix attempt requires nested agent dispatch, stop and report — the caller's loop will retry up to its max attempts."*

- [ ] **WI 1.11 — Canonical `.landed` schema.** Document in `skills/land-pr/SKILL.md` the canonical `.landed` schema:
  ```
  status: <required>      # landed | pr-ready | pr-ci-failing | pr-failed | conflict | pr-state-unknown
  date: <required>        # ISO-8601, NY tz: $(TZ=America/New_York date -Iseconds)
  source: <required>      # caller skill name (run-plan, commit, do, fix-issues, quickfix, land-pr)
  method: <required>      # always "pr" in this plan's scope
  branch: <required>      # feature branch name
  pr: <optional>          # PR URL; present only after pr-push-and-create.sh succeeds
  ci: <optional>          # CI_STATUS value; present only after pr-monitor.sh ran
  pr_state: <optional>    # PR_STATE value; present only after pr-merge.sh ran
  commits: <optional>     # space-separated SHA list of commits on the branch
  issue: <optional>       # GitHub issue number; present for /fix-issues caller
  reason: <optional>      # short token: rebase-conflict-too-many-files, ci-fix-cycle-exhausted, etc.
  conflict_files: <optional>  # space-separated paths; present for status=conflict (small lists only)
  ```
  `/land-pr` writes `.landed` only when `--worktree-path` is supplied. `/run-plan` may write its own `.landed` for the pre-`/land-pr` "rebase-conflict-too-many-files" case (when it bails before invoking `/land-pr`). The schema is the same in both write paths.

- [ ] **WI 1.12 — `/land-pr` SKILL.md procedure prose.** Compose the SKILL.md body that drives Claude through the procedure when `/land-pr` is invoked:
  1. Parse `$ARGUMENTS` (WI 1.2) and validate.
  2. If `--pr <num>` is set (resume mode): skip steps 3–4, jump to step 5 with `$PR_NUMBER=<num>`.

     **Use case for `--pr <num>`:** caller (or user) previously invoked `/land-pr --no-monitor` (or had a monitor timeout); the PR exists and the branch is pushed; now they want to monitor (or re-monitor) without re-running rebase/push/create.

  3. Run `pr-rebase.sh`. On exit 10: write result file with `STATUS=rebase-conflict CONFLICT_FILES_LIST=<sidecar-path>` and exit. On exit 11: write `STATUS=rebase-failed CALL_ERROR_FILE=<sidecar>` and exit.
  4. Run `pr-push-and-create.sh`. On non-zero exit: write `STATUS=push-failed` (or `create-failed` per exit code) with `CALL_ERROR_FILE`. If `--worktree-path` supplied, write `.landed` marker with `status=pr-failed`. Exit.
  5. If `--no-monitor` was supplied: write `STATUS=created CI_STATUS=not-monitored PR_URL=...`, exit.

     **Use case for `--no-monitor`:** caller wants to report PR URL to user mid-flight (e.g., interactive `/land-pr` invocation where the user wants the URL fast and will check CI themselves), or caller wants to split create-and-monitor across two cron-fired turns. None of the 5 callers in this plan use `--no-monitor` — it's a flag for direct user invocation and future callers.

  6. Run `pr-monitor.sh` with `--ci-timeout`. **Prepend the verbatim PR #131 past-failure preamble** (relocated from `skills/commit/modes/pr.md:62-70` per WI 3.4 / DA2-8) immediately above this step — the agent-discipline lesson ("don't paraphrase the polling step; don't substitute a single `gh pr checks` snapshot for an actual `--watch` poll") is load-bearing and was added in PR #133 as a behavioral guardrail. The conformance assertion `check land-pr "PR #131 past-failure preamble" 'Past failure.*PR #131|skipped Step 6 on PR #131'` (added in WI 3.4) verifies it survives.
  7. Run `pr-merge.sh` with `--auto-flag` and the resolved `CI_STATUS`.
  8. Compose `.landed` body if `--worktree-path` was supplied. Use this **status mapping table** to derive the `status` field:

     **Evaluation: top-down, first-match-wins.** Failure-exits and pre-conditions come first; CI_STATUS=fail and CI_STATUS=pending take precedence over MERGE_REQUESTED/PR_STATE rows because the merge-requested-but-CI-failed combo (auto-merge accepted but CI changed after) should NOT be reported as `landed`.

     | # | MERGE_REQUESTED | PR_STATE | CI_STATUS | → `status` |
     |---|---|---|---|---|
     | 1 | (rebase-conflict exit, set in step 3) | * | * | conflict |
     | 2 | (push-failed or create-failed exit, set in step 4) | * | * | pr-failed |
     | 3 | * | * | fail | pr-ci-failing |
     | 4 | * | * | pending | pr-ready |
     | 5 | * | * | unknown | pr-ready |
     | 6 | true | MERGED | pass / none / skipped | landed |
     | 7 | true | OPEN | pass / none / skipped | pr-ready |
     | 8 | true | UNKNOWN | pass / none / skipped | pr-state-unknown |
     | 9 | false (auto-merge-disabled-on-repo) | * | pass / none / skipped | pr-ready |
     | 10 | false (auto-not-requested) | * | pass / none / skipped | pr-ready |

     All required schema fields populated; optional fields populated when known. Pipe to `bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh" "$WORKTREE_PATH"` (uses atomic write per its docstring at `skills/commit/scripts/write-landed.sh:19`: *"Writes: <worktree-path>/.landed (atomic via .tmp + mv)"*).
  9. Compose final result and write to `$RESULT_FILE` (atomic via `.tmp` + `mv`). Per WI 1.7, every VALUE is validated via `validate_result_value` before write; multi-line content is referenced via `*_FILE` sidecar paths.
  10. Echo a brief one-line summary to stdout for the conversation log: `STATUS=<status> PR=<url> CI=<status>`.

- [ ] **WI 1A.13 — Mirror (foundation).** Run `bash scripts/mirror-skill.sh land-pr` (introduced in PR #88; per-file mirror that respects the `hooks/block-unsafe-generic.sh:201-220` recursive-rm guard). The script does the diff verification internally and exits non-zero on drift. Mirrors the 1A foundation files: SKILL.md, 4 scripts, references/caller-loop-pattern.md, references/fix-cycle-agent-prompt-template.md.

- [ ] **WI 1A.14 — Update PLAN_INDEX.** Move PR_LANDING_UNIFICATION from "Ready to Run" to "In Progress" with current phase = 1A.

### End-of-phase smoke checkpoint (mandatory)

After completing **WI 1.1–1.6 and WI 1.12** (skill + scripts + procedure prose), and BEFORE Phase 1B writes mocks / comprehensive tests / conformance assertions, run a smoke test:

**Concrete recipe (use real GitHub):** Create a throwaway feature branch in this repo (e.g., `smoke/land-pr-$(date +%s)`), make a trivial commit (touch a file in `tmp/`), then invoke `/land-pr --branch smoke/land-pr-$TS --title "smoke test" --body-file /tmp/smoke-body.md --result-file /tmp/land-pr-smoke.txt --no-monitor`. The `--no-monitor` flag avoids triggering CI cost. After verification, **clean up:**
```bash
gh pr close "$PR_NUMBER" --delete-branch  # closes the smoke PR + deletes branch on remote
git push dev --delete smoke/land-pr-$TS    # belt-and-suspenders
```

Verify:
- The result file is produced with the expected schema (all required keys present, all values single-line).
- The skill's procedure drives Claude through rebase/push/create successfully.
- The allow-list parser in WI 1.7 reads the result file without invoking `source`.
- No shell-injection vulnerabilities (manually stuff `$()` into a sidecar file path; confirm the parser leaves it as a literal string).
- `gh pr edit` is NOT called by `pr-push-and-create.sh` on the smoke PR (verified by passing the same body twice — second invocation should detect existing PR and not modify body).

If the smoke test fails, the script contracts or procedure prose are wrong — **fix before starting Phase 1B**, do not write tests/conformance assertions on top of broken foundations.

### Design & Constraints

- **Cross-skill dispatch via Skill tool, single-string args.** Per `skills/research-and-plan/SKILL.md:140`. Same-context recursion per `:87-105`. Therefore data hand-off is file-based (WI 1.7), not via stdout.
- **No `jq` binary; `gh ... --jq` flag is allowed.** `jq` standalone binary is prohibited per memory `feedback_no_jq_in_skills`. `gh`'s `--jq` flag is gh's built-in formatter, not a separate process — using it does not introduce a `jq` dependency. Conformance test (WI 1B.4) guards against `^[[:space:]]*jq ` pattern, not against `--jq=` flag. **Internal style preference (DA1-11):** prefer bash-regex on `gh ... --json` output (per WI 1.4 step 1) over `gh ... --jq '.field'` for consistency. WI 1.6 step 6 uses `--jq` for terseness; WI 1.4 sets the bash-regex precedent and is the default for new code.
- **No `|| true`, no `2>/dev/null` on fallible ops.** Per CLAUDE.md "Never suppress errors."
- **No `--no-verify` on commits.** Per CLAUDE.md.
- **`skills/commit/scripts/write-landed.sh` is reused as-is.** Path corrected per R1-7 — PRs #95-#100 moved this script under `skills/commit/scripts/` (the `commit` skill owns landing primitives; per `skills/update-zskills/references/script-ownership.md`). Atomic write semantics verified at the script's docstring (line 19: "Writes: <worktree-path>/.landed (atomic via .tmp + mv)"). The agent invokes it as `bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh"`. Same correction applies to `skills/commit/scripts/land-phase.sh`.
- **Result-file values are single-line shell-safe; multi-line content goes in sidecar files.** The caller never `source`s the result file; uses an allow-list line-by-line parser (WI 1.7). This eliminates the shell-injection class.
- **Test-output capture pattern.** All tests follow CLAUDE.md's TEST_OUT idiom — never pipe.
- **Idempotency is a contract.** Re-invoking `/land-pr` with the same branch must be a no-op for already-done steps (rebase up-to-date is exit 0; push up-to-date is exit 0; existing PR is detected). Body updates are caller-owned, NOT done by `/land-pr`. WI 1B.3 includes explicit idempotency test cases.
- **Race condition on parallel `/land-pr` invocations is bounded by gh's "already exists" rejection.** If two callers race past `gh pr list` and both call `gh pr create`, gh enforces one open PR per head branch and the second invocation gets a non-zero exit with "already exists" stderr. The losing invocation's caller sees `STATUS=create-failed` and handles it via the canonical loop; no duplicate PRs are created. This is documented; no `flock` guard is needed.
- **`--no-monitor` and `--pr <num>` enable two flow shapes.** `--no-monitor`: caller wants to report PR URL early and skip CI poll for this invocation. `--pr <num>`: caller resumes monitoring an existing PR. Together they let users / future callers split the create-and-monitor flow when needed. None of the 5 callers in this plan use these flags — they all monitor synchronously.
- **All 5 callers run CI monitoring + fix-cycle.** No exceptions. /quickfix's "fire-and-forget" was drift, not design. /commit pr and /do pr's "report-only" was drift, not design. The unification corrects all three (per maintainer rationale in Overview).
- **`/land-pr` is dispatched only at orchestrator level.** Documented contract — no runtime guard. Conformance assertions in Phase 6 verify callers' SKILL.md files contain the dispatch at orchestrator level (not inside an Agent prompt block).
- **Hooks compatibility.** Per `hooks/block-unsafe-project.sh.template:634-640`, the `git push` rule scope is segmented to the `git push` portion of the command (the recent #58 fix). /land-pr's gh/git calls won't trip false-positives. The smoke checkpoint (intra-phase) verifies this end-to-end. **Recursive-rm hook compatibility (per DA1-1):** all mirror WIs use `bash scripts/mirror-skill.sh <name>` instead of `rm -rf .claude/skills/<name>` because `hooks/block-unsafe-generic.sh:201-220` blocks recursive rm outside `/tmp/`. PR #88's `mirror-skill.sh` does per-file mirror that respects the guard.
- **Post-merge red-main canary interaction (per DA1-10).** `.github/workflows/test.yml:82-122` (PR #149) auto-files or comments on a `main-broken` GitHub issue when a push to main fails Tests. This canary is independent of `/land-pr`'s exit status — if `--auto` is true and CI passes pre-merge but post-merge red appears (rare, but possible due to merge-commit interactions), the canary fires regardless of whether /land-pr's caller loop returned `STATUS=merged`. This is intentional: the canary exists precisely to catch the silent post-merge red case. /land-pr does not write to `.github/`, so no interference is possible.
- **PR body ownership is the caller's, not `/land-pr`'s.** /land-pr writes the body only on initial PR creation (the `--body-file` content). Subsequent body updates (e.g., /run-plan's HTML-comment-marker progress splice) are caller-owned and happen before the caller invokes /land-pr. This preserves user-added review notes.
- **shellcheck clean.** All four scripts must pass `shellcheck` with no warnings.

### Acceptance Criteria

- [ ] Smoke checkpoint passes — see "End-of-phase smoke checkpoint" section above.
- [ ] `skills/land-pr/SKILL.md` exists; `grep -E '^name: land-pr$' skills/land-pr/SKILL.md` returns one line.
- [ ] All four scripts exist and are executable: `for f in pr-rebase pr-push-and-create pr-monitor pr-merge; do test -x "skills/land-pr/scripts/$f.sh" || fail "$f not executable"; done`.
- [ ] `shellcheck skills/land-pr/scripts/*.sh` returns 0.
- [ ] `skills/land-pr/references/caller-loop-pattern.md` and `skills/land-pr/references/fix-cycle-agent-prompt-template.md` exist (callers in Phases 2–5 will copy from these).
- [ ] Mirror byte-identical for 1A files: `bash scripts/mirror-skill.sh land-pr` exits 0 (script does the diff verification internally; note: failure-modes.md, mocks, and tests don't exist yet; they're 1B work).
- [ ] No skill yet calls `/land-pr` (Phases 2–5 do that). Existing skills' PR mode behavior is unchanged.
- [ ] `plans/PLAN_INDEX.md` shows PR_LANDING_UNIFICATION in "In Progress" with Phase 1A complete.
- [ ] `bash tests/run-all.sh` still passes (Phase 1A doesn't break existing tests; new tests come in 1B).

### Dependencies

- None. This is the foundation phase.

## Phase 1B — `/land-pr` validation: failure-modes doc + mocks + tests + conformance

### Goal

Add the validation layer on top of Phase 1A's foundation: failure-modes documentation, mock infrastructure (mock-gh + mock-git for unit tests), comprehensive script tests covering the documented failure modes, and conformance assertions in `tests/test-skill-conformance.sh` (with a new `check_not` helper). Ensures regressions are caught before Phases 2–5 migrate the 5 callers.

### Work Items

- [ ] **WI 1B.1 — Failure-modes reference.** Create `skills/land-pr/references/failure-modes.md` cataloging the 10 failure modes from the research synthesis. Each entry: failure description, severity, detection mechanism in the corresponding script, the test case in `tests/test-land-pr-scripts.sh` that proves the detection works.

- [ ] **WI 1B.2 — Mock infrastructure for tests.** Create `tests/mocks/mock-gh.sh` and `tests/mocks/mock-git.sh`. Each is a bash script with a subcommand router. Reference implementation for `mock-gh.sh` (the test scripts copy this verbatim and extend per-test):
  ```bash
  #!/bin/bash
  # mock-gh.sh — minimal stateful mock for `gh` commands.
  # State: $MOCK_GH_STATE_DIR (default /tmp/mock-gh-state-$$).
  # Per-call counters: $MOCK_GH_STATE_DIR/<subcommand>.count
  # Per-call canned response: $MOCK_GH_STATE_DIR/<subcommand>.<count>.{stdout,stderr,exit}
  set -u
  STATE_DIR="${MOCK_GH_STATE_DIR:-/tmp/mock-gh-state-$$}"
  mkdir -p "$STATE_DIR"
  SUBCMD="$1 $2"  # e.g., "pr list", "pr create", "run view"
  KEY="$(echo "$SUBCMD" | tr ' ' '_')"
  COUNT_FILE="$STATE_DIR/$KEY.count"
  COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNT_FILE"
  STDOUT_FILE="$STATE_DIR/$KEY.$COUNT.stdout"
  STDERR_FILE="$STATE_DIR/$KEY.$COUNT.stderr"
  EXIT_FILE="$STATE_DIR/$KEY.$COUNT.exit"
  if [ ! -f "$STDOUT_FILE" ] && [ ! -f "$STDERR_FILE" ] && [ ! -f "$EXIT_FILE" ]; then
    echo "mock-gh: no canned response prepared for '$SUBCMD' call #$COUNT" >&2
    exit 127  # mimic gh's "command not found" / "subcommand failed" failure mode
  fi
  [ -f "$STDOUT_FILE" ] && cat "$STDOUT_FILE"
  [ -f "$STDERR_FILE" ] && cat "$STDERR_FILE" >&2
  [ -f "$EXIT_FILE" ] && exit "$(cat "$EXIT_FILE")"
  exit 0
  ```
  **Why fail-fast on missing canned response:** if the SUT calls a subcommand more times than the test prepared, the mock would otherwise silently return exit 0 with empty output — producing **false test confidence**. Failing fast with exit 127 makes test gaps visible.

  Tests set up the per-call canned responses by writing to `$MOCK_GH_STATE_DIR/<subcommand>_<call#>.{stdout,stderr,exit}` BEFORE invoking the script under test. The pre-check-loop test, for example, writes empty stdout for `pr_checks.1` and `pr_checks.2`, then a non-empty array for `pr_checks.3`.

  **Concurrency note:** The mock's per-call counter file is not locked. All tests using `mock-gh.sh` MUST invoke mocked commands sequentially within a single test process. Do NOT fork background processes that call `gh` — the counters race. Tests requiring parallel `gh` calls use real `gh` against a fixture repo instead.

  `mock-git.sh` follows the same pattern. For state-modifying ops (rebase, push), the mock can also call real `git` with a fake remote (local bare repo at `$MOCK_GIT_FAKE_REMOTE`) when realistic side effects are required.

- [ ] **WI 1B.3 — `tests/test-land-pr-scripts.sh`.** Create the test file. Capture output per CLAUDE.md: `TEST_OUT="/tmp/zskills-tests/$(basename $(pwd))/.test-results.txt"`. Tests cover all 10 failure modes from `references/failure-modes.md` PLUS:
  - **rebase-idempotent**: local branch is already rebased, then a fix commit is added, then `pr-rebase.sh` is called again → exit 0, no modifications, no conflict.
  - **PR_NUMBER extraction from URL**: when `gh pr create` returns URL `.../pull/42`, `PR_NUMBER=42` is extracted (no second `gh pr view` call).
  - **--no-monitor returns early**: `/land-pr --no-monitor` writes result file with `CI_STATUS=not-monitored` and does NOT run `pr-monitor.sh`.
  - **--pr <num> resume mode**: skips rebase/push/create, jumps to monitor.
  - **result-file safe parsing**: a maliciously-crafted CALL_ERROR (containing `$()` substitution attempt) lands in a sidecar file, not the result file; caller's allow-list parser ignores unknown/malformed lines without executing them.
  - **status mapping table coverage**: at least one test per row of the WI 1.12 table — verify the correct `status` is derived for each combination.
  - **race-bounded create-failed**: simulate two concurrent `gh pr create` calls against same branch (mock returns "already exists" on second); confirm the second invocation gets `STATUS=create-failed CALL_ERROR_FILE=...` and does NOT create a duplicate PR.

- [ ] **WI 1B.4 — Conformance assertions + `check_not` helper.** Add to `tests/test-skill-conformance.sh`:
  - **Define `check_not` helper** (top of file, alongside existing `check`/`check_fixed` at lines 29-51):
    ```bash
    check_not() {
      local skill="$1" label="$2" pattern="$3"
      if grep -rE -e "$pattern" "$REPO_ROOT/skills/$skill/" > /dev/null 2>&1; then
        FAILED=$((FAILED + 1)); echo "FAIL: [$skill] $label — pattern '$pattern' found but should NOT exist"
      else
        PASSED=$((PASSED + 1)); echo "PASS: [$skill] $label"
      fi
    }
    ```
  - Then add /land-pr assertions:
    - `check_fixed land-pr "name frontmatter" 'name: land-pr'`
    - `check land-pr "references all four scripts" 'pr-rebase\.sh.*pr-push-and-create\.sh.*pr-monitor\.sh.*pr-merge\.sh'`
    - `check_fixed land-pr "result-file contract" '$RESULT_FILE'`
    - `check_fixed land-pr "monitor uses --watch" 'gh pr checks .*--watch'` AND `check_fixed land-pr "monitor bare re-check" 'gh pr checks "\$PR" >/dev/null'`
    - `check land-pr "PR_NUMBER from URL not gh pr view" '\$\{[A-Z_]*##\*\/\}'`
    - `check_not land-pr "no jq binary" '^[[:space:]]*jq '`  (allows `gh ... --jq` flag use; forbids `jq` as separate process)
    - `check_not land-pr "no || true" '\|\| true'`
    - `check_not land-pr "no source-based result parsing" 'source[[:space:]]+.*RESULT_FILE|\.[[:space:]]+.*RESULT_FILE'`  (caller pattern in references/ — verifies the safe parser, not source)

- [ ] **WI 1B.5 — Mirror update.** Run `bash scripts/mirror-skill.sh land-pr`. Mirrors 1B's added `failure-modes.md` plus any 1A changes that landed since 1A's mirror.

- [ ] **WI 1B.6 — Update PLAN_INDEX.** Move PR_LANDING_UNIFICATION's "Next Phase" to 1B → 2.

### Design & Constraints

- **All script tests use mock-gh / mock-git.** Real-gh smoke is reserved for the 1A end-of-phase checkpoint and for Phases 2–5 manual canaries. Phase 1B tests stay deterministic via PATH override.
- **Conformance assertions are the drift tripwire.** WI 1B.4's assertions back-fill the moves from /run-plan's existing inline assertions to /land-pr (per Phase 2 WI 2.7). Once 1B lands, conformance enforces the no-regression contract for Phases 2–5.
- **Test-output capture** per CLAUDE.md TEST_OUT idiom; never pipe.

### Acceptance Criteria

- [ ] `skills/land-pr/references/failure-modes.md` exists with all 10 failure modes documented.
- [ ] `tests/mocks/mock-gh.sh` and `tests/mocks/mock-git.sh` exist and are executable.
- [ ] `tests/test-land-pr-scripts.sh` runs and passes (≥10 failure-mode test cases + idempotency, status-mapping, result-safe-parsing, race-bounded test cases). Output captured per CLAUDE.md.
- [ ] `tests/test-skill-conformance.sh` runs and passes — `check_not` helper defined; new /land-pr assertions; no existing assertion modified.
- [ ] `bash tests/run-all.sh` passes overall.
- [ ] Mirror byte-identical: `bash scripts/mirror-skill.sh land-pr` exits 0.
- [ ] `plans/PLAN_INDEX.md` shows PR_LANDING_UNIFICATION's Next Phase = 2.

### Dependencies

- Phase 1A complete (status: complete; foundation in place).

## Phase 2 — Migrate `/run-plan` PR mode to `/land-pr` (caller owns body splice)

### Goal

Replace the inline PR-landing implementation in `skills/run-plan/modes/pr.md` (current main `b1db0b2`: file is 681 lines; the inline rebase + push + create + CI poll + fix cycle + auto-merge + `.landed` block bounded by the grep-able markers `## Step 6` / end-of-`gh pr merge`-block / `### Post-landing tracking`, current lines 281–680) with a Skill-tool dispatch to `/land-pr` plus the canonical caller fix-cycle loop. **Critical:** `/run-plan` continues to own per-phase PR body splicing using its existing bash-regex (`BASH_REMATCH`) implementation at `skills/run-plan/SKILL.md:1715-1745`, performed BEFORE invoking `/land-pr`. /land-pr does not touch the body on existing PRs. **Per DA1-8:** prefer grep-able markers ("delete from `## Step 6` to end of `gh pr merge` block") over hard line numbers — the file drifts faster than the plan can be rewritten.

### Work Items

- [ ] **WI 2.1 — Caller-owned body splice (preserve existing bash-regex implementation).** Continue building `$PR_BODY` in `/run-plan`'s prose with HTML-comment-wrapped progress section (`<!-- run-plan:progress:start --> ... <!-- run-plan:progress:end -->`). Write to `/tmp/pr-body-$PLAN_SLUG.md`.

  **First-phase invocation:** No PR exists yet; the body file written must INCLUDE the markers (so subsequent phases have something to splice into). `/run-plan`'s body construction prose places `<!-- run-plan:progress:start -->\n<progress section>\n<!-- run-plan:progress:end -->` near the top of the body. /land-pr creates the PR with this body via `pr-push-and-create.sh` (no special handling needed).

  **Subsequent-phase invocation (existing PR detected before the loop):** **Preserve the existing bash-regex splice implementation at `skills/run-plan/SKILL.md:1715-1745` verbatim** (per DA1-2). Do NOT rewrite it as awk or sed. The current implementation uses bash `[[ "$CURRENT_BODY" =~ (.*$START_MARKER)(.*)($END_MARKER.*) ]]` with `BASH_REMATCH` capture groups — already passes the conformance assertion at `tests/test-skill-conformance.sh:102` (`(.*$START_MARKER)(.*)($END_MARKER.*)`). `BASH_REMATCH` does no replacement-side metachar interpretation, so `&`/`\` in user-pasted content survive intact. The structural change here is **relocation only**: the splice block moves from its current Phase 4 location into the `<CALLER_PRE_INVOKE_BODY_PREP>` slot of the canonical caller-loop pattern, executed BEFORE invoking `/land-pr` on each phase iteration where a PR already exists.

  **Recovery paths (3 paths, each writes the canonical-schema `.landed` and breaks the loop without invoking `/land-pr`):**
  1. **`gh-pr-view-failed`** — `gh pr view "$PR_NUMBER" --json body --jq '.body'` fails. Retry once with 2s backoff; on second failure, write `.landed status=conflict REASON=gh-pr-view-failed` and break.
  2. **`body-markers-missing`** — `grep -qF '<!-- run-plan:progress:start -->' && grep -qF '<!-- run-plan:progress:end -->'` returns false on the fetched body. The current implementation at `SKILL.md:1742` emits `NOTICE: skipping PR body sync: markers not found` and gracefully continues — preserve this behavior on the **best-effort path** (per the existing design property at `SKILL.md:1758-1761`: "the plan-tracker commit on the feature branch is the source of truth; the PR body is a convenience surface"). Do NOT escalate to `.landed conflict` — escalation would regress the existing graceful behavior captured by conformance assertion at `tests/test-skill-conformance.sh:103`.
  3. **`gh-pr-edit-failed`** — `gh pr edit "$PR_NUMBER" --body "$UPDATED_BODY"` fails. Retry once with 2s backoff; on second failure, the existing implementation at `SKILL.md:1737` emits `WARNING: gh pr edit ... failed — PR body not synced` and continues. Preserve this WARN-and-continue behavior. Do NOT escalate to `.landed conflict` — feature-branch commit is the source of truth.

  This is a deliberate framing change from earlier plan revisions (which proposed sed→awk improvements and 3-or-5 hard-failure recovery paths). The current implementation already handles `gh-pr-view-failed`, `body-markers-missing`, and `gh-pr-edit-failed` with the right severity (graceful for body-markers-missing and gh-pr-edit-failed; retry-then-graceful for gh-pr-view-failed). Wholesale rewriting it as hard-failure-with-`.landed-conflict` would regress passing conformance assertions and the documented design property. The old "5 paths covering splice-body.sh" was already removed as YAGNI in Round 4; this revision now also removes the gh-pr-view-failed-or-edit-failed-as-hard-conflict over-escalation and aligns with the existing implementation.

  `/land-pr`'s `pr-push-and-create.sh` does NOT touch the body when an existing PR is detected (per WI 1.4) — preserving user-added review notes between the markers.

- [ ] **WI 2.2 — Replace inline PR-landing block with caller loop.** Edit `skills/run-plan/modes/pr.md`. Delete the inline rebase + push + create + CI poll + fix cycle + auto-merge + .landed block — bounded by grep-able **bash-comment** markers `# --- PR creation ---` (start, current line 268; verified — `run-plan/modes/pr.md` uses bash-comment headers, not Markdown `## Step 6` headings; the latter only appears in `commit/modes/pr.md`) and the H3 marker `### Post-landing tracking` (end, current line 681). The deleted block is bounded by these two markers (current lines ~268–680 in `b1db0b2`; use the markers, not the line range, since the file drifts). Replace with the canonical caller-loop pattern from `skills/land-pr/references/caller-loop-pattern.md`. Customize:
  - `$LANDED_SOURCE=run-plan`
  - `$WORKTREE_PATH=` the per-phase worktree
  - `$AUTO=$AUTO_FROM_RUNPLAN_INVOCATION`
  - `<CALLER_PRE_INVOKE_BODY_PREP>` block: WI 2.1's body-splice logic
  - `<CALLER_REBASE_CONFLICT_HANDLER>` block: WI 2.3's logic
  - `<DISPATCH_FIX_CYCLE_AGENT_HERE>` block: WI 2.4's logic

- [ ] **WI 2.3 — Preserve agent-assisted rebase conflict resolution.** When `/land-pr` returns `STATUS=rebase-conflict` and the conflict-files list (read from `${LP[CONFLICT_FILES_LIST]}`) has count ≤ 5, dispatch the existing `/run-plan` rebase-resolution agent (orchestrator-level, not nested) in the worktree. The agent runs `git rebase origin/main` itself to reproduce the conflict state (`pr-rebase.sh` aborted it leaving a clean tree), resolves the conflicts, and signals success. Then `continue` the loop to re-invoke `/land-pr` (its rebase will be no-op since the conflict is resolved). On > 5 files or agent failure: write `.landed conflict` marker per current behavior (using the canonical schema from WI 1.11) and `break` the loop.

- [ ] **WI 2.4 — Preserve fix-cycle agent dispatch with plan context.** Use `skills/land-pr/references/fix-cycle-agent-prompt-template.md` as the structural starting point. Caller-specific bits: plan title, current phase, phase work items, the `${LP[CI_LOG_FILE]}` from `/land-pr`'s output, the worktree path. The existing fix-cycle agent prompt prose in `/run-plan/modes/pr.md` (locate via grep-able marker `Dispatch a fix-cycle agent` or the agent-prompt heredoc near the inline `gh pr checks --watch` block) transfers into the template's `<CALLER_WORK_CONTEXT>` slot. Per DA1-8: prefer marker-based locator over hard line numbers.

- [ ] **WI 2.5 — Preserve finish-mode loop and frontmatter writes.** `/run-plan` schedules the next phase via one-shot cron after a phase lands. This continues unchanged. The frontmatter status update (in the plan file, before push so it's captured in the squash) also continues unchanged — both happen in `/run-plan`'s prose, before invoking `/land-pr`.

- [ ] **WI 2.5a — ADAPTIVE_CRON_BACKOFF Mode A interaction (per DA1-6).** `/run-plan/SKILL.md:439-573` (added in PRs #131, #138) implements per-phase defer counters and cadence step-down at boundary fires `C+1 ∈ {1, 10, 16, 26}`. The defer counter is incremented in `/run-plan`'s Step 0 pre-flight on every cron-fired turn that finds the phase still "In Progress." When `/land-pr`'s synchronous CI monitoring (default 600s) and the wrapping caller-loop's fix-cycle (up to ~10+ min on a 2-attempt cycle) hold the orchestrator turn open, the next `*/1` cron fire arrives while the prior turn is still running. The adaptive-cron machinery is designed to handle this — the `*/1`-fire on an in-progress phase enters Step 0 and increments the defer counter. **Design implication:** at default settings, a single fix-cycle iteration (~10 min including push + re-poll) crosses 10 cron fires, which steps the cadence from `*/1` to `*/10` mid-fix-cycle. The phase still finishes correctly (Step 0 defers, then the original turn writes `.landed`), but the cron is now `*/10`, slowing every subsequent phase's first defer-fire by an order of magnitude.

  **Acceptance:** WI 2.9's manual canary observes the `in-progress-defers.<phase>` counter behavior across a fix-cycle invocation and verifies that the cadence settles correctly when the phase lands. **No code change is required in /run-plan or /land-pr** — the adaptive machinery is correct by design — but the plan must DOCUMENT this interaction so the implementer reviews it post-canary and confirms the step-down is acceptable. If empirical observation shows step-down is too aggressive across fix-cycles, follow-up: add a "fix-cycle-active" sentinel that suppresses defer-counter increments while `/land-pr` is mid-flight (out of scope for this phase).

  **`cron-recovery-needed.<phase>` sentinel safety:** The sentinel is keyed by phase name; if `/land-pr`'s caller loop crashes mid-fix-cycle, the sentinel never gets cleared. /run-plan's Step 0 sentinel-recovery prelude (`SKILL.md:439-471`) handles this on next entry. No additional cleanup is needed.

- [ ] **WI 2.6 — `.landed` ownership split + downstream consumer verification.** `/land-pr` writes `.landed` for push-failed/CI-failing/landed states. `/run-plan` writes `.landed` only for the pre-`/land-pr` "rebase-conflict-too-many-files" case. Both writers use the canonical schema from WI 1.11. **Path correction (per R1-7):** `write-landed.sh` and `land-phase.sh` live at `skills/commit/scripts/write-landed.sh` and `skills/commit/scripts/land-phase.sh` (moved by PRs #95-#100; verified via `find` returns `./skills/commit/scripts/write-landed.sh` and `./skills/commit/scripts/land-phase.sh`). The mirrored runtime paths the agent invokes are `$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/{write-landed,land-phase}.sh`. **Verification:** in WI 2.9's manual canary, run `/fix-report` on the resulting `.landed` AND check that `bash $CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/land-phase.sh` cleans up the worktree correctly. Add a unit test (extend `tests/test-skill-conformance.sh` or a new `tests/test-landed-schema.sh`) asserting both `/fix-report` and `skills/commit/scripts/land-phase.sh` parse a canonical-schema `.landed` without error.

- [ ] **WI 2.7 — Update conformance tests.** In `tests/test-skill-conformance.sh`:
  - Existing /run-plan PR-mode assertions targeting inline code (the 87af82a re-check, 175e4aa hardenings, b904cef gating) MOVE to /land-pr's conformance section (added in WI 1B.4).
  - **Stale-assertion enumeration (per DA1-4):** the following assertions in `tests/test-skill-conformance.sh` will fail when /run-plan migrates and MUST be relocated, rewritten, or deleted in this WI (verified against current main `b1db0b2`):
    | Line | Assertion label | Action |
    |---|---|---|
    | 66 | `run-plan "--watch unreliable"` | RELOCATE to `land-pr` (assertion now lives in `pr-monitor.sh`) |
    | 67 | `run-plan "gh pr checks re-check"` | RELOCATE to `land-pr` |
    | 68 | `run-plan "timeout 124 handling"` `WATCH_EXIT" -eq 124` | RELOCATE to `land-pr` (per WI 1.5: `pr-monitor.sh` uses `WATCH_EXIT` variable name, so the regex matches verbatim — see DA2-5) |
    | 69 | `run-plan "ci-pending pr-ready"` `pr-ready` | **REWRITE** — per R2-2/DA2-6: the `pr-ready` literal currently appears in `run-plan/modes/pr.md:400, 424, 592, 638, 646, 675, 676`. After WI 2.2 deletes the inline block, ALL these sites are gone. The `pr-ready` token survives only in /land-pr's `.landed` schema (WI 1.11). Rewrite as `check_fixed land-pr "pr-ready status mapping" 'pr-ready'` (matches WI 1.12 step 8's status table where rows 4, 5, 7, 9, 10 produce `pr-ready`). Alternatively REMOVE if the schema-table coverage in WI 1B.4 already asserts pr-ready presence; implementer's judgment. |
    | 70 | `run-plan "ci log path"` `/tmp/ci-failure-` | RELOCATE to `land-pr` |
    | 71 | `run-plan "auto-merge expected fallback"` | RELOCATE to `land-pr` |
    | 72 | `run-plan "pr number from url"` | RELOCATE to `land-pr` (lives in `pr-push-and-create.sh`) |
    | 73 | `run-plan "pr number numeric check"` | RELOCATE to `land-pr` |
    | 74 | `run-plan "push error-check first-time"` | RELOCATE to `land-pr` |
    | 75 | `run-plan "pre-cherry-pick stash"` | STAY — verified the literal `'pre-cherry-pick stash'` lives in `skills/run-plan/modes/cherry-pick.md:83`, NOT in `pr.md`. Cherry-pick mode is out-of-scope for this plan; the assertion is unaffected by PR-mode migration. |
    Lines 99–103 (PR-body splice markers, `gh pr edit` body sync, splice regex form, NOTICE-on-missing-markers) STAY on `run-plan` — body splice remains caller-owned per WI 2.1; the existing bash-regex splice at `skills/run-plan/SKILL.md:1715-1745` is preserved verbatim.

    **Total run-plan PR-mode assertions enumerated: 9** (lines 66, 67, 68, 69, 70, 71, 72, 73, 74) plus line 75 STAY-verified for completeness. Combined with WI 3.4 (commit=3), WI 3.9 (do=4), and WI 4.6 (fix-issues=8), the cross-skill total is 24 assertions affected by migration (per DA2-6 re-count against current `tests/test-skill-conformance.sh`). The original Round 1 estimate of "~13 assertions" was significantly low; the per-line tables in this WI and WI 3.4 / 3.9 / 4.6 now enumerate all 24.
  - Add new assertions: `check_fixed run-plan "modes/pr.md dispatches /land-pr" 'land-pr'`; `check_not run-plan "no inline gh pr create" 'gh pr create'`; `check_not run-plan "no inline gh pr checks --watch" 'gh pr checks --watch'`; `check_not run-plan "no inline gh pr merge" 'gh pr merge'`. (Uses the `check_not` helper from WI 1B.4.)

- [ ] **WI 2.8 — Mirror.** Run `bash scripts/mirror-skill.sh run-plan`.

- [ ] **WI 2.9 — Manual canary verification.** Run `/run-plan plans/CANARY1_HAPPY.md` end-to-end. Confirm: PR is created, body has progress section, CI poll runs, `.landed` written correctly, `/fix-report` reads it correctly, on success the worktree is cleaned up. Run `/run-plan plans/CANARY3_FIXCYCLE.md` (which intentionally breaks CI) — confirm fix-cycle dispatches, recovers, and lands. Spot check: between phases, manually edit the PR body to add a "review note" outside the HTML-comment markers; confirm the next phase preserves it.

### Design & Constraints

- **No behavior change for `/run-plan` users.** PR titles, bodies, finish-mode loop, frontmatter updates — all identical to today. Only the implementation underneath changes.
- **The fix-cycle loop is real-sized.** ~80–120 lines once you account for arg construction, result-file parsing, status case dispatch, and fix-cycle agent prompt with plan context. WI 1.8's complete reference implementation is the verbatim base; /run-plan's customization is the agent-prompt block plus the body-splice block (most of the line count).
- **Per-phase PR body update is `/run-plan`'s job, not `/land-pr`'s.** This preserves the existing splice pattern (HTML-comment markers, sed-based replacement) and prevents body wholesale replacement that would destroy user-added review notes.

### Acceptance Criteria

- [ ] `skills/run-plan/modes/pr.md` no longer contains `gh pr create`, `gh pr checks --watch`, or `gh pr merge --auto --squash` inline. Verified via `grep -F`.
- [ ] `skills/run-plan/modes/pr.md` invokes `/land-pr` via Skill tool. Verified via grep for `land-pr`.
- [ ] `/run-plan` performs HTML-comment-marker body splice BEFORE invoking `/land-pr` on existing-PR phases. Verified via grep for `run-plan:progress:start` and `gh pr edit --body-file`.
- [ ] All conformance assertions pass.
- [ ] `bash tests/run-all.sh` passes.
- [ ] CANARY1_HAPPY runs end-to-end successfully; user-added review notes preserved across phases.
- [ ] CANARY3_FIXCYCLE triggers fix-cycle and recovers (or settles at `pr-ci-failing`).
- [ ] `/fix-report` and `skills/commit/scripts/land-phase.sh` parse canonical-schema `.landed` without error (per WI 2.6).
- [ ] Mirror byte-identical.

### Dependencies

- Phase 1A and Phase 1B must both be complete (`/land-pr` skill installed, references in place, tests + conformance assertions passing).

## Phase 3 — Migrate `/commit pr` and `/do pr` to `/land-pr` (drift fix: gain fix-cycle)

(Same as Round-1 plan — combined commit + do migration. Pasted unchanged below for completeness.)

### Goal

Replace the inline implementation in `skills/commit/modes/pr.md` AND `skills/do/modes/pr.md` (and the duplicate `gh pr create` site in `skills/do/SKILL.md`) with `/land-pr` dispatches. Both gain CI monitoring + fix-cycle (currently absent — drift fix). `/do pr` additionally harmonizes its `.landed` schema. Auto-merge stays OFF for both.

### Work Items

- [ ] **WI 3.1 — /commit pr migration.** Edit `skills/commit/modes/pr.md`. Delete current lines 28–84 (rebase + push + create + report-only-CI). Replace with canonical caller-loop pattern. `$LANDED_SOURCE=commit`, no `--worktree-path` (no worktree), no `--auto`. `<CALLER_PRE_INVOKE_BODY_PREP>` block: empty (commit's body is fixed at PR creation, no per-phase update). `<DISPATCH_FIX_CYCLE_AGENT_HERE>` block: agent context = staged files + recent commit subjects.

- [ ] **WI 3.2 — /commit pr preconditions preserved.** Clean-tree precondition (current lines 9–17) and main-branch guard (lines 19–26) run BEFORE `/land-pr` is dispatched.

- [ ] **WI 3.3 — /commit pr title/body construction.** Title from branch name as today. Body from recent commits as today. Write body to `/tmp/pr-body-commit-$BRANCH_SLUG.md`.

- [ ] **WI 3.4 — /commit pr conformance.** Inline `gh pr create` and `gh pr checks --watch` GONE. `/land-pr` dispatched. **Stale-assertion enumeration (per DA1-4):** in `tests/test-skill-conformance.sh`, line 144 (`commit "--watch unreliable"`) RELOCATES to `land-pr` (now lives in `pr-monitor.sh`); line 151 (`commit "step6: poll-ci.sh invocation"`) is REMOVED (poll-ci.sh deleted in WI 3.5a); line 152 (`commit "step6: past-failure preamble"`) **RELOCATES** to /land-pr's SKILL.md prose (NOT removed, NOT moved to `failure-modes.md` — per DA2-8: the past-failure preamble at `skills/commit/modes/pr.md:62-70` is a **prompt-engineering lesson** about agent-discipline ("agent skipped Step 6 on PR #131 push, read inline bash as suggestion-prose, did one snapshot, exited"), not a script-failure-mode. `failure-modes.md` per WI 1B.1 catalogs script-level failures; the wrong document for an agent-prose-discipline lesson). Action: copy the verbatim PR #131 preamble paragraph into /land-pr's SKILL.md prose immediately above WI 1.12 step 6 (the `pr-monitor.sh` invocation step), reworded to point at /land-pr's polling logic instead of /commit's. Then add a new conformance assertion: `check land-pr "PR #131 past-failure preamble" 'Past failure.*PR #131|skipped Step 6 on PR #131'`. Add: `check_fixed commit "modes/pr.md dispatches /land-pr" 'land-pr'`.

- [ ] **WI 3.5 — /commit mirror + manual.** Run `bash scripts/mirror-skill.sh commit`; verify on a feature branch with passing CI; verify with intentionally-failing CI (fix-cycle dispatches).

- [ ] **WI 3.5a — Delete orphan `skills/commit/scripts/poll-ci.sh` (per DA1-3).** After WI 3.1 migrates `/commit/modes/pr.md` to dispatch `/land-pr`, `poll-ci.sh` is no longer invoked from anywhere. Delete `skills/commit/scripts/poll-ci.sh` and `.claude/skills/commit/scripts/poll-ci.sh`. Verify `grep -rln 'poll-ci.sh' skills/ .claude/skills/` returns no hits. The `pr-monitor.sh` in `/land-pr` is the canonical successor (per WI 1.5 above).

- [ ] **WI 3.6 — /do pr migration.** Edit `skills/do/modes/pr.md`. Delete current lines 124–218. Replace with caller-loop pattern. `$LANDED_SOURCE=do`, `$WORKTREE_PATH=$WORKTREE_PATH`, no `--auto`. `<CALLER_PRE_INVOKE_BODY_PREP>` block: empty (do's body is fixed at PR creation). `<DISPATCH_FIX_CYCLE_AGENT_HERE>` block: agent context = task description.

- [ ] **WI 3.7 — Remove the `gh pr create` prose mention in `skills/do/SKILL.md`, then add regression guard.** **DA2-1 correction:** Round 1 claimed `grep -n "gh pr create" skills/do/SKILL.md` returns 0 hits. Re-running the grep against current main `b1db0b2` actually returns ONE hit at line 878: `- **PR titles and bodies are explicit** — never use \`--fill\` in \`gh pr create\`.` This is a Key Rules prose constraint about the `--fill` flag, not a live invocation, but the Phase 6 grep tripwire (`grep -rln 'gh pr create' skills/ | grep -v 'skills/land-pr/'` must be 0) WILL match it and fail.

  **Fix:** Edit `skills/do/SKILL.md` line 878 to reword without the literal `gh pr create` substring. Replacement candidate: `- **PR titles and bodies are explicit** — never use \`--fill\` when creating a PR (the title and body are constructed by the skill, not auto-derived from commits).`. Verify the equivalent conformance assertion at `tests/test-skill-conformance.sh:195` (`do "no --fill" 'never use --fill|NEVER use --fill|not --fill'`) still passes against the rewritten line — the assertion checks for `never use --fill` substring, which the replacement still contains. Then add a `check_not` assertion that `gh pr create` does NOT appear in `skills/do/SKILL.md` (using the helper from WI 1B.4) so any future drift is caught.

  **Lesson:** Round 1 refiner's "verified 0 hits" claim was wrong. Future verify-before-fix passes must run the grep with the exact pattern in the exact scope before declaring "no hits."

- [ ] **WI 3.8 — /do pr `.landed` schema harmonization.** /land-pr writes the canonical-schema marker (WI 1.11). Verify `/fix-report` and cleanup tooling handle the new fields gracefully (additive change — they read fewer fields than the marker has).

- [ ] **WI 3.9 — /do conformance.** Inline `gh pr create` and `gh pr checks --watch` GONE from BOTH `SKILL.md` and `modes/pr.md`. `/land-pr` dispatched. **Stale-assertion enumeration (per DA1-4):** in `tests/test-skill-conformance.sh`, line 197 (`do "--watch unreliable"`) RELOCATES to `land-pr`; line 198 (`do "pr-state-unknown retry"`) STAYS — the `pr-state-unknown` token is now part of /land-pr's `.landed` schema (WI 1.11) and may still be referenced in /do's caller-loop wrapper for explanatory prose; verify at WI 3.10. Line 199 (`do "report-only ci"` regex `(does NOT|doesn.?t) dispatch fix agents|report-only`) is **REMOVED** — its INTENT is now incorrect because Phase 3 is a drift fix that ADDS fix-cycle to /do pr; replace with `check_fixed do "modes/pr.md dispatches /land-pr" 'land-pr'`. Line 194 (`do "rebase before push"`) STAYS — the rebase is preserved (now via `pr-rebase.sh`); the assertion may be RELOCATED to `land-pr` if the literal `git rebase origin/main` no longer appears in /do.

- [ ] **WI 3.10 — /do mirror + manual.** Run `bash scripts/mirror-skill.sh do`; verify `/do pr "small task"` end-to-end with passing and failing CI.

### Design & Constraints

- **Auto-merge stays OFF for both.**
- **`/commit pr`: no worktree, no `.landed`.**
- **`/do pr`: with worktree, full canonical `.landed`.**
- **Drift fix: both gain CI monitoring + fix-cycle.**

### Acceptance Criteria

- [ ] Both `modes/pr.md` files no longer contain `gh pr create`, `gh pr checks --watch`. `/land-pr` dispatched in both.
- [ ] `skills/do/SKILL.md` no longer contains `gh pr create`.
- [ ] `.landed` markers from /do pr contain canonical schema fields.
- [ ] `bash tests/run-all.sh` passes.
- [ ] Mirrors byte-identical for both.
- [ ] Manual verification passes for /commit pr and /do pr.

### Dependencies

- Phases 1A and 1B must both be complete.

## Phase 4 — Migrate `/fix-issues pr` to `/land-pr` (drop 300s timeout special case)

(Same as Round-1 plan. Pasted unchanged below.)

### Goal

Replace the inline implementation in `skills/fix-issues/modes/pr.md` with a per-issue `/land-pr` dispatch. Drop the 300s-per-issue CI timeout special case — all callers use 600s default per maintainer direction.

### Work Items

- [ ] **WI 4.1 — Replace per-issue inline impl.** In `skills/fix-issues/modes/pr.md`, the "for each issue" loop body (current lines 17–148) replaces the inline implementation with the canonical caller-loop pattern dispatching `/land-pr` per issue. `$LANDED_SOURCE=fix-issues`, `$WORKTREE_PATH=$ISSUE_WORKTREE`, `$AUTO=$AUTO`, `$ISSUE_NUM=$ISSUE_NUM`. `<CALLER_PRE_INVOKE_BODY_PREP>` block: empty (per-issue body is fixed). `<DISPATCH_FIX_CYCLE_AGENT_HERE>` block: agent context = issue body + change summary.

- [ ] **WI 4.2 — Drop 300s timeout special case.** Per DA2-4: the current `300s` timeout in `/fix-issues/modes/pr.md` is NOT a `--ci-timeout 300` flag invocation — it's a comment at line 140 (`#   - \`timeout 300\` per issue (NOT 600) to avoid serial accumulation`). Verified: `grep -n "timeout 300" skills/fix-issues/modes/pr.md` returns line 140 only. Line 126 in current main is `LANDED` (a heredoc terminator), unrelated. The downstream conformance assertion at `tests/test-skill-conformance.sh:224` matches the comment text. **Action:** delete the comment at line 140 (and any nearby prose explaining the 300s special case); after WI 4.1 replaces the inline impl with the canonical caller-loop pattern (which dispatches /land-pr with no `--ci-timeout` flag), /land-pr's default 600s applies. Per WI 4.6 line 224 → REMOVE the `fix-issues "ci timeout 300"` conformance assertion.

- [ ] **WI 4.3 — Preserve agent-assisted rebase conflict resolution.** Per current behavior. Same pattern as Phase 2 WI 2.3.

- [ ] **WI 4.4 — Preserve sprint report generation.** Phase 5 of /fix-issues overall (sprint report) runs before any /land-pr dispatch and is unchanged.

- [ ] **WI 4.5 — `--issue` field passes through.** /land-pr's `--issue $ISSUE_NUM` flag (per WI 1.2) populates the `.landed` marker's `issue` field.

- [ ] **WI 4.6 — Conformance.** Inline `gh pr create`, `gh pr checks --watch`, `gh pr merge --auto --squash` GONE from `modes/pr.md`. **Stale-assertion enumeration (per DA1-4) — verified against current `tests/test-skill-conformance.sh:208-232`:**
  | Line | Assertion label | Action |
  |---|---|---|
  | 224 | `fix-issues "ci timeout 300"` | **REMOVE** — WI 4.2 drops the 300s special case; default 600s applies |
  | 225 | `fix-issues "cross-ref to run-plan ci"` | **REMOVE** — the cross-ref text in /fix-issues becomes obsolete (the CI logic now lives in /land-pr, not /run-plan) |
  | 226 | `fix-issues "auto-gating prose"` | STAY — gating contract is still /fix-issues-specific |
  | 227 | `fix-issues "pr ci+fix-cycle always run"` | STAY (regex may need rewording — verify at WI 4.7 mirror time) |
  | 228 | `fix-issues "only merge gated on auto"` | STAY — gating contract is /fix-issues-specific (b904cef) |
  | 230 | `fix-issues "direct requires auto"` | STAY |
  | 231 | `fix-issues "auto-merge AUTO guard"` regex `if [ "$AUTO" = "true" ]` | **RELOCATE to land-pr** — the literal guard now lives in `pr-merge.sh` (WI 1.6 step 1) |
  | 232 | `fix-issues "ci poll always runs in pr.md"` | **REWRITE** — the literal pattern is brittle; replace with assertion that /fix-issues dispatches /land-pr unconditionally per-issue (regardless of AUTO) |
  Add: `check_fixed fix-issues "modes/pr.md dispatches /land-pr per-issue" 'land-pr'`.

- [ ] **WI 4.7 — Mirror.** Run `bash scripts/mirror-skill.sh fix-issues`.

- [ ] **WI 4.8 — Manual canary verification.** Run `/fix-issues plan` then `/fix-issues 1` (auto and interactive). Confirm per-issue PR creation, CI poll, fix-cycle, `.landed` markers with `issue=N` field.

### Design & Constraints

- **Drop 300s special case** per maintainer direction: same CI pipeline → same timeout. Cumulative wall-clock for sequential N issues is solved by parallelism (`--auto`).
- **Per-issue /land-pr dispatch.**
- **PR title hardcoded template stays.** `Fix #N: ISSUE_TITLE` is /fix-issues-specific.

### Acceptance Criteria

- [ ] `skills/fix-issues/modes/pr.md` no longer contains `gh pr create`, `gh pr checks --watch`, or `gh pr merge`.
- [ ] `--ci-timeout 300` GONE; default 600s applies.
- [ ] `/land-pr` dispatched per-issue.
- [ ] `.landed` markers include `issue=N` field.
- [ ] Test suite passes; sprint report generation unchanged.
- [ ] Mirror byte-identical.
- [ ] Manual verification passes for both auto and interactive modes.

### Dependencies

- Phases 1A and 1B must both be complete.

## Phase 5 — Migrate `/quickfix` to `/land-pr` (drift fix: gain CI monitoring + fix-cycle)

(Same as Round-1 plan. Pasted unchanged below.)

### Goal

Replace the fire-and-forget PR-creation block in `skills/quickfix/SKILL.md` Phase 7 (verified at lines 993–1102 of current main `b1db0b2`; the original plan's "lines ~693-748" citation predates PRs #151-#156 which expanded /quickfix from ~750 lines to 1102 by adding the triage gate and plan-review gates) with a `/land-pr` dispatch. **Drift fix: /quickfix gains CI monitoring + fix-cycle as additive coverage on top of the post-PR-#151 triage + plan-review gates.** The framing here corrects the original plan's "drift, not a feature" wording (per DA1-5): /quickfix's pre-#151 design pushed rigor upstream (no CI poll because the lightweight nature of the fix was the gate); the post-#151 design adds upstream triage+review. CI monitoring is additive, not corrective — the drift fix is "/quickfix should also have CI monitoring + fix-cycle for parity with the other 4 callers when CI fails."

### Work Items

- [ ] **WI 5.1 — Replace inline PR creation.** Edit `skills/quickfix/SKILL.md` Phase 7. **Scope (per R2-1 / DA2-9):** the deleted block is bounded by grep-able markers `^## Phase 7 — PR creation` (start, current line 993) and `^## Exit codes` (end, current line 1082) — Phase 7 is the LAST phase in `quickfix/SKILL.md`; there is NO `## Phase 8` (verified: `grep -nE "^## Phase " skills/quickfix/SKILL.md` returns Phases 1, 2, 3, 4, 5, 6, 7 with `## Exit codes` at line 1082 immediately following). Delete only the Phase 7 body (current lines 994–1081): the inline `gh pr create` (line 1035), error handling, and the immediate exit. **Do NOT delete `## Exit codes` (line 1082) or `## Key Rules` (line 1093+).** WI 5.5 separately rewrites the single Key Rules entry at line 1102 (`Fire-and-forget`) — preserve the surrounding rules at lines 1095–1101 (PR-only, aligned-test-cmd, dirty-tree-is-input, never-bypass-pre-commit-hook, no-error-suppression, bare-branch-push-only, no-`.landed`-marker) verbatim; they are orthogonal to PR creation. Replace the deleted Phase 7 body with the canonical caller-loop pattern from `skills/land-pr/references/caller-loop-pattern.md`. `$LANDED_SOURCE=quickfix`, no `--worktree-path` (no worktree), no `--auto` by default. `<CALLER_PRE_INVOKE_BODY_PREP>` block: empty. `<DISPATCH_FIX_CYCLE_AGENT_HERE>` block: agent context = user's `$DESCRIPTION` and the staged commit subject.

- [ ] **WI 5.2 — Preserve pre-PR work, including post-#151 triage + plan-review gates.** /quickfix Phases 1–6 run BEFORE /land-pr is dispatched. **Specifically preserved (verified against current main):**
  - WI 1.3 config + environment gates (line 139)
  - WI 1.3.5 parallel-invocation gate / stale-marker detection (line 215, see also WI 5.3)
  - WI 1.5 mode detection (line 271)
  - **WI 1.5.4 triage gate** (line 295, post-PR #151) — model-layer instruction that decides whether `/quickfix` is the right tool BEFORE creating any branch or marker. Stays unchanged. The triage gate is upstream of /land-pr.
  - **WI 1.5.4a inline plan composition** (line 366, post-PR #151)
  - **WI 1.5.4b fresh-agent plan review** (line 399, post-PR #151) — second upstream rigor gate. Stays unchanged.
  - WI 1.5.5 dirty-tree confirmation (line 518)
  - WI 1.6 slug derivation, WI 1.7 branch naming, WI 1.8 tracking setup, WI 1.9 branch creation
  - Phase 3 (WI 1.10/1.11): user-edited or agent-dispatched change
  - Phase 4 (WI 1.12): test gate
  - Phase 5 (WI 1.13): commit
  - Phase 6 (WI 1.14): push
  Only Phase 7 (PR creation, lines 993–1102) is touched by this migration. The triage gate decides "is this the right tool" (BEFORE-PR); /land-pr's CI fix-cycle is the AFTER-PR-creation block.

- [ ] **WI 5.3 — Preserve parallel-invocation gate.** WI 1.3.5 (current line 215, stale-marker detection) stays.

- [ ] **WI 5.4 — Preserve fulfillment-marker model.** /quickfix continues writing the fulfillment marker (with PR URL appended) and does NOT pass `--worktree-path` to /land-pr — so no `.landed` is written. Two artifact systems coexist intentionally: fulfillment-marker tracks /quickfix lifecycle; `.landed` is for worktree-using callers.

- [ ] **WI 5.5 — Update Key Rules prose at SKILL.md:1102.** Replace the literal `Fire-and-forget. End at gh pr create; print URL; return user to $BASE_BRANCH; exit. No polling, no --watch.` line with a description of the new full lifecycle: `triage → review → commit → push → PR → CI poll → fix cycle`. **Do NOT delete supporting prose more aggressively than this single line** — pre-#151 `/quickfix` was philosophically coherent in its lightweight design, and the per-#151 gates already provide the upstream rigor; CI monitoring is additive coverage on top, not a wholesale rewrite. Update related prose at line 20 (`Fire-and-forget: commit, push, open PR, print URL, return to base branch, exit.`) similarly: replace with the same new lifecycle description.

- [ ] **WI 5.6 — /quickfix conformance.** Inline `gh pr create` GONE. `/land-pr` dispatched. CI monitoring + fix-cycle now present. Add: `check_fixed quickfix "Phase 7 dispatches /land-pr" 'land-pr'`; `check_not quickfix "no inline gh pr create" 'gh pr create'`; `check_not quickfix "no fire-and-forget literal" 'Fire-and-forget'` (note: any `--force` or `--fill` references are unaffected; only the literal "Fire-and-forget" prose is removed).

- [ ] **WI 5.7 — Mirror.** Run `bash scripts/mirror-skill.sh quickfix`.

- [ ] **WI 5.8 — Manual verification.** Run `/quickfix "test small fix"` (agent-dispatched mode) and `/quickfix --yes` on a dirty tree (user-edited mode). Confirm PR creation, CI poll, fix-cycle if CI fails.

### Design & Constraints

- **Drift fix is the headline change.** Per maintainer rationale.
- **No worktree, no `.landed`.**
- **Auto-merge stays OFF.**
- **Pre-PR work unchanged.**

### Acceptance Criteria

- [ ] `skills/quickfix/SKILL.md` no longer contains `gh pr create` inline.
- [ ] `/land-pr` is dispatched.
- [ ] CI monitoring + fix-cycle now present.
- [ ] Fulfillment-marker still written (no regression).
- [ ] `bash tests/run-all.sh` passes.
- [ ] Mirror byte-identical.
- [ ] Manual verification passes for both modes.
- [ ] "Fire-and-forget" language removed.

### Dependencies

- Phases 1A and 1B must both be complete.

## Phase 6 — Drift-prevention conformance + canary

(Same as Round-1 plan with one addition for orchestrator-level dispatch verification.)

### Goal

Lock in the unification with conformance tripwires and a canary that exercises the unified flow end-to-end. Catch future drift before it ships.

### Work Items

- [ ] **WI 6.1 — Cross-skill conformance tripwires.** Add to `tests/test-skill-conformance.sh`:
  - **No `gh pr create` *invocation* outside `skills/land-pr/`.** Per DA2-2: a naive `grep -rln 'gh pr create'` matches **prose mentions** (e.g., `skills/do/SKILL.md:878` "never use `--fill` in `gh pr create`", `skills/run-plan/modes/pr.md:309` "Manual fallback: gh pr create ..."), causing the tripwire to false-fail. WI 3.7 above removes the `do/SKILL.md:878` prose; WI 2.2's full block-deletion removes the `run-plan/modes/pr.md:309` echo. To handle the residual class: tripwire matches **invocation lines only** via the pattern `^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr create\b` — anchored to start-of-line, allowing optional `if !`, `VAR=`, or `$(` invocation prefixes. Pure-prose mentions (which always have leading non-bash text like ``"`gh pr create`"``, "Manual fallback:", or list-marker prefixes) do not match. Concrete shell assertion:
    ```bash
    HITS=$(grep -rEln '^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr create\b' "$REPO_ROOT/skills/" | grep -v 'skills/land-pr/')
    [ -z "$HITS" ] || { echo "FAIL: live gh pr create invocation outside /land-pr: $HITS"; exit 1; }
    ```
    Same shape repeated for `.claude/skills/`.
  - **No `gh pr checks --watch` invocation outside `skills/land-pr/`.** Pattern: `^[[:space:]]*(timeout[[:space:]]+[0-9]+[[:space:]]+)?gh pr checks\b.*--watch\b`. Excludes prose `\`timeout 600 gh pr checks --watch\`` (which has backtick prefix, not whitespace).
  - **No `gh pr merge` invocation outside `skills/land-pr/`.** Pattern: `^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr merge\b`. Excludes prose like `**Only \`gh pr merge --auto --squash\` is gated on \`auto\`**` (backtick prefix).
  - **All 5 callers dispatch `/land-pr`.** For each of the 5 caller files, assert `land-pr` appears (substring match is fine — `land-pr` only appears in dispatch contexts).
  - **Orchestrator-level dispatch verification.** For each caller's modes/pr.md (or SKILL.md for /quickfix): assert the `/land-pr` Skill-tool invocation appears at top-level prose, NOT inside an Agent prompt block. Heuristic: scan for the dispatch line; verify the surrounding 30 lines do NOT contain start-of-line patterns `^[[:space:]]*(Agent:|prompt:)` AND do NOT contain start-of-line `^[[:space:]]*dispatch.*agent` (per R2-4: all three alternatives are now uniformly anchored to start-of-line; the original third alternative `dispatch.*agent` lacked anchoring and matched any prose mentioning dispatch). Documented limitation: a prose paragraph that happens to start a line with "Agent:" still false-fails — implementer can adjust pattern further if needed.

  **Why prose vs. invocation distinction matters (per DA2-2):** post-migration the inline-block deletions in WI 2.2 / 3.1 / 3.6 / 4.1 / 5.1 remove ALL invocation sites outside /land-pr, but several prose mentions survive (Key Rules constraints, manual-fallback echoes, design notes). The pre-DA2-2 tripwire shape (`grep -rln 'gh pr create' | wc -l == 0`) would false-fail on these. The start-of-line-anchored shape lets prose survive while still catching any new live invocation that drifts in.

- [ ] **WI 6.2 — `/land-pr` canary.** Create `plans/CANARY_LAND_PR.md`. Run a small `/run-plan` cycle through `/land-pr` end-to-end with deliberately-failing CI on attempt 1 (forcing fix-cycle), passing on attempt 2.

- [ ] **WI 6.3 — Drift-prevention rationale.** Document WHY the assertions exist in `tests/test-skill-conformance.sh` (drift bugs 87af82a, 1de3049, 175e4aa, b904cef).

- [ ] **WI 6.4 — Update PLAN_INDEX.** Move PR_LANDING_UNIFICATION to "Complete".

- [ ] **WI 6.5 — Update CHANGELOG.**

- [ ] **WI 6.6 — Update run-order guide.**

- [ ] **WI 6.7 — Final verification.** `bash tests/run-all.sh` passes; cross-skill grep guards produce expected output; canary runs successfully.

### Acceptance Criteria

- [ ] `grep -rln 'gh pr create' skills/` lists only land-pr files.
- [ ] `grep -rln 'gh pr checks --watch' skills/` lists only `pr-monitor.sh`.
- [ ] `grep -rln 'gh pr merge' skills/` lists only `pr-merge.sh`.
- [ ] Orchestrator-level dispatch heuristic passes for all 5 callers.
- [ ] Canary CANARY_LAND_PR runs end-to-end successfully.
- [ ] PLAN_INDEX shows Complete.
- [ ] CHANGELOG documents change.
- [ ] `bash tests/run-all.sh` passes.

### Dependencies

- Phases 1–5 must all be complete.

---

## Round 1 Disposition

(Refiner output of Round 1 review — verify-before-fix applied to each finding.)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R1: Skill-tool dispatch idiom mismatch | Reviewer | Verified: `/research-and-plan/SKILL.md:140` shows `/draft-plan output <path> <description>` (positional/keyword string), and `/quickfix`/`/do` parse `--branch=` etc. via bash regex internally. | **Fixed.** WI 1.2 explicitly specifies bash-regex flag parsing; Design & Constraints documents the single-string-args dispatch model. |
| R2: `gh pr list` text-parsing unspecified | Reviewer | Verified: plan v1 said "bash regex parse" without showing it. | **Fixed.** WI 1.4 contains the full bash regex pattern. |
| R3: Rebase idempotency unverified | Reviewer | Verification: judgment — git rebase to base is idempotent per git docs. | **Fixed.** WI 1.3 cites idempotency; WI 1.14 adds explicit test. |
| R4 / DA3: PR body update sub-decision unresolved | Reviewer + DA | Verified: plan v1 left choice flagged. | **Fixed in Round 1, re-fixed in Round 2.** Round-1 added gh pr edit to pr-push-and-create.sh; Round-2 reversed this (DA Finding 3 R2): caller owns body splice. See Round 2 disposition. |
| R5: Test mock infra unspecified | Reviewer | Verified: `tests/` has no mock-gh. | **Fixed in Round 1, expanded in Round 2.** WI 1.13 specifies mocks; Round 2 added reference implementation. |
| R6: /quickfix .landed exemption + Phase 6 conformance | Reviewer | Judgment. | **Fixed.** |
| R7: Phase count borderline | Reviewer | Judgment. | **Fixed.** Phases 3+4 merged to single Phase 3; plan now has 6 phases. |
| R8: No rollback strategy | Reviewer | Judgment. | **Fixed.** Overview includes Rollback paragraph. |
| DA1: Skill-tool stdout return mechanism | DA | Verified: `/research-and-plan/SKILL.md:87-105` describes Skill tool as same-context recursion. | **Fixed in Round 1, hardened in Round 2.** Round-1 introduced file-based result contract; Round-2 made the parser safe (allow-list, no `source`). |
| DA2: Caller loop bigger than "small" | DA | Verified: existing fix-cycle is ~80+ lines. | **Fixed.** WI 1.8 provides complete production-ready bash. |
| DA4: Hooks interaction untested | DA | Verified: hooks scope to `git push` segment per #58 fix. | **Justified.** Hook interactions documented; intra-phase smoke checkpoint (Round 2) verifies. |
| DA5: .landed schema split unsafe | DA | Verified: plan v1 had no canonical schema. | **Fixed.** WI 1.11 establishes schema; both writers conform. |
| DA6: Phase 5 dropping 300s timeout | DA | Verified: current line 126 uses 300s. | **Justified — maintainer direction.** Same CI pipeline → same timeout. |
| DA7: Subagent nesting unaddressed | DA | Verified: user prompt acknowledged constraint. | **Fixed.** Documented as orchestrator-level contract; conformance heuristic in WI 6.1. |
| DA8: Monitor timeout re-invoke ambiguous | DA | Judgment. | **Fixed.** `--pr <num>` resume mode added. |
| DA9: Phase 1 scope too broad | DA | Judgment — 17 WIs. | **Justified in Round 1, mitigated in Round 2.** Intra-phase smoke checkpoint added. |
| DA10: /quickfix UX change weakly justified | DA | Judgment. | **Justified — maintainer direction.** |

**Round 1 substantive issues:** 12 fixed, 4 justified. 0 ignored.

## Round 2 Disposition

(Refiner output of Round 2 review — verify-before-fix applied to each finding.)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R2-1 / DA2-1: Shell-sourcing safety / shell injection via sourced result file | Reviewer + DA | Verified: sourcing `RESULT_FILE` with `. "$RESULT_FILE"` executes `$()` substitutions; CALL_ERROR with stderr text from gh is attacker-controllable. | **Fixed.** WI 1.7 redesigned: result file uses single-line shell-safe values only; multi-line content goes in sidecar files (`*_FILE` paths). Caller uses allow-list line-by-line parser, never `source`. WI 1.14 adds explicit malicious-CALL_ERROR test case. WI 1.15 adds `check_not` for `source`-based parsing. |
| R2-2: Missing status mapping table in WI 1.12 | Reviewer | Verified: plan v2 referenced "mapping table embedded in SKILL.md" without showing it. | **Fixed.** WI 1.12 step 8 now contains the full status mapping table (10 rows covering all combinations of MERGE_REQUESTED, PR_STATE, CI_STATUS, plus the failure-exit pre-conditions). |
| R2-3 / DA2-6: grep-NOT helper missing | Reviewer + DA | Verified: `tests/test-skill-conformance.sh:29-51` has only `check`/`check_fixed`; no negation helper exists. | **Fixed.** WI 1.15 now contains the full `check_not` helper definition. |
| R2-4: --no-monitor use case undefined | Reviewer | Verified: plan v2 had the flag but no example use. | **Fixed.** WI 1.12 step 5 documents the use case; Design & Constraints notes none of the 5 callers use it (it's for direct user invocation and future callers). |
| R2-5: reason field schema split | Reviewer | Verified: result-file schema (WI 1.7) lacked `REASON`. | **Fixed.** Result-file schema now includes `REASON=<token>`. |
| R2-6: Plan size sanity | Reviewer | Verified: plan was ~617 lines; Round 2 grew it further. | **Justified.** Plan size reflects scope (4 scripts + 5 caller migrations + canonical contracts); `/quickfix/SKILL.md` (365 lines) and prior plans of this scope (DRIFT_ARCH_FIX 532 lines) confirm this is in range. Intra-phase smoke checkpoint (R2 add) catches scope creep early. |
| DA2-2: Mock infrastructure stateful router | DA | Verified: plan v2 said "env-var-driven canned responses" without showing the dispatch logic. | **Fixed.** WI 1.13 now provides ~30-line reference implementation of `mock-gh.sh` with stateful per-call responses via state directory + per-subcommand counter files. |
| DA2-3 / DA2-9: gh pr edit overwrites user PR-body edits | DA | Verified: `/run-plan/modes/pr.md:221-224` has `<!-- run-plan:progress:start -->` marker; `/run-plan/SKILL.md:1216-1217` shows sed-based splice. Wholesale replacement via `gh pr edit --body-file` would destroy user-added review notes between markers. | **Fixed.** WI 1.4 now explicitly says pr-push-and-create.sh does NOT call `gh pr edit` on existing PRs. Body management is caller-owned. WI 2.1 documents /run-plan handles its own splice using existing markers BEFORE invoking /land-pr. WI 2.9 adds explicit "user-added review note preservation" check. |
| DA2-4: Race condition on parallel /land-pr | DA | Verified: gh pr create rejects duplicate PRs from same head branch (gh's own check). | **Justified.** Race is bounded — losing invocation gets `STATUS=create-failed`, no duplicate PRs. Documented in Design & Constraints. No `flock` guard added (overkill for the bounded case). |
| DA2-5: Dispatch rule unenforceable | DA | Judgment — no runtime guard. | **Justified.** Documented as orchestrator-level contract in WI 1.1 description and Overview. WI 6.1 adds best-effort heuristic conformance check. Full enforcement requires runtime hooks (out of scope). |
| DA2-7: .landed schema downstream consumers | DA | Verified: plan v2 said "/fix-report ... handles canonical schema gracefully" without verification. | **Fixed.** WI 2.6 now adds explicit verification step: run /fix-report and scripts/land-phase.sh against a canonical-schema .landed in WI 2.9's manual canary; add unit-test assertion. |
| DA2-8: Phase 1 scope is 3x baseline | DA | Verified: Phase 1 estimated ~1500 lines new code. | **Mitigated.** Intra-phase smoke checkpoint (after WI 1.6 + 1.12, before WI 1.8+) catches foundational issues before piling on references and tests. Splitting into 1A/1B was considered but adds phase-ordering overhead with no real validation gain (no caller uses /land-pr in either sub-phase). |
| DA2-10: Atomic write verification | DA | Verified: `scripts/write-landed.sh` docstring (line 19) says "atomic via .tmp + mv". | **Justified.** Citation added to Design & Constraints; behavior already correct in the reused script. |

**Round 2 substantive issues:** 9 fixed, 4 justified. 0 ignored.

## Round 3 Disposition

(Refiner output of Round 3 review — verify-before-fix applied to each finding.)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R3-1 / DA3-3: Status mapping table precedence ambiguous | Reviewer + DA | Verified: WI 1.12 v2 had 10 rows but no first-match-wins semantic; rows could collide for ambiguous CI_STATUS=fail + MERGE_REQUESTED=true. | **Fixed.** WI 1.12 step 8 now explicitly states "first-match-wins" and reorders rows so failure-exits and CI=fail/pending precede CI=pass scenarios. |
| R3-2 / DA3-7: WI 2.1 splice failure recovery unspecified | Reviewer + DA | Verified: plan v2's WI 2.1 had one-sentence splice description; no error handling for sed/awk failure, missing markers, transient `gh pr edit` errors. | **Fixed.** WI 2.1 now has 5 explicit recovery paths (gh-pr-view-failed, body-markers-missing, splice-marker-mismatch, splice-write-failed, gh-pr-edit-failed); each writes canonical-schema `.landed` and breaks the loop. First-phase invocation explicitly initializes markers in the body so subsequent splices have anchors. |
| DA3-1: Caller-owned body splice creates drift hazard | DA | Judgment — only /run-plan needs splice today, but future callers might re-implement. | **Fixed.** New WI 1.5a creates `splice-body.sh` shared utility in `skills/land-pr/scripts/`. /run-plan calls it (WI 2.1 step 4) instead of inline sed. Future callers can reuse — single tested implementation, drift-prevented. |
| DA3-2: Parser arbitrary VALUE characters / bash compat | DA | Verified: `read -r KEY VALUE` with `IFS='='` correctly splits on first `=` only (URL with `?ref=main&sort=asc` parses correctly — confirmed via shell test). But embedded newlines DO break the parser. `declare -A` is bash-only. | **Partially fixed.** WI 1.7 now adds writer-side validation (`validate_result_value` rejects values containing newlines, `$`, backticks, `&`, `?`, `#`). The bash-only constraint is documented as design choice (zskills targets bash; not portable to dash/zsh — same as existing skills). |
| DA3-4: Mock-gh missing canned response = silent exit 0 (false confidence) | DA | Verified: mock impl in plan v2 returned exit 0 silently on missing files. | **Fixed.** WI 1.13's mock-gh.sh fallback now exits 127 with stderr error when no canned response is prepared. Tests fail fast on coverage gaps instead of silently passing. |
| R3-3: Sidecar file cleanup pattern undefined | Reviewer | Verified: WI 1.7/1.8 v2 showed result-file `rm -f` but not sidecar cleanup. | **Fixed.** WI 1.8 caller-loop now captures sidecar paths into `_CLEANUP_PATHS` before removing result file, then cleans up sidecars after final loop iteration (preserves CI_LOG_FILE for caller use). |
| R3-4: Orchestrator-level dispatch heuristic brittle | Reviewer | Judgment — pattern `Agent:` matches prose. | **Fixed.** WI 6.1 heuristic now anchored to start-of-line (`^[[:space:]]*(Agent:|prompt:)`) so prose discussion doesn't match. Documented residual limitation. |
| R3-5: Mock-gh counter files unguarded for concurrent forks | Reviewer | Verified: counter file write is unlocked. | **Fixed.** WI 1.13 now contains a "Concurrency note" specifying tests must invoke mocked commands sequentially; parallel calls use real gh against fixture repo. |
| R3-6: check_not regex/fixed-string semantics undocumented | Reviewer | Verified: WI 1.15 v2 used `check_not` with both styles without documenting. | **Justified — minor doc nit.** The `check_not` definition uses `grep -rE -e` (extended regex); fixed strings work as-is when they contain no metacharacters. Adding a doc note in the helper definition is in scope of the implementer's discretion at WI 1.15. |
| DA3-5: Smoke checkpoint uses real GitHub, undocumented infra | DA | Verified: plan v2 deferred the choice to implementer. | **Fixed.** Smoke checkpoint section now picks "real GitHub with cleanup" explicitly: throwaway branch + `--no-monitor` to skip CI cost + `gh pr close --delete-branch` for cleanup. Concrete recipe in plan. |
| DA3-6: Phase 1 WI count exceeds bound | DA | Judgment — 17 WIs (now 18 with WI 1.5a). | **Justified.** Round 1 DA9 and Round 2 R2-6 already justified this; intra-phase smoke checkpoint is the mitigation. Splitting into 1A/1B was considered and rejected — no caller validates /land-pr in either sub-phase, so no validation gain from the split. Phase 1's 18 WIs add ~1700 lines of new code; this is at the high end of typical phase scope but still implementable in one focused session. |
| DA3-8: Rollback claim glosses cascading | DA | Judgment. | **Justified.** Rollback design accommodates cascading: Phase 1 alone is reversible (no caller depends); Phases 2–5 each independently revertible (each PR migrates one caller); Phase 6 conformance assertions catch any incomplete revert (grep tripwires fail if a caller's inline impl is restored without removing the conformance assertion). The "we were wrong about /quickfix" scenario from DA is explicitly out of plan scope — re-evaluating maintainer direction would be a new epic. |
| DA3-9: 11-flag parser untested | DA | Judgment — plan lists flags but doesn't show parser regex. | **Justified.** /quickfix and /do already have well-tested 8-flag and 6-flag bash regex parsers; /land-pr's parser follows the same pattern. WI 1.14 includes parser-level test cases (validation rejection of `--branch=main`, valid path with `=` in `--body-file`, missing `--pr` value, etc.). The implementer follows the established idiom; pseudocode in WI 1.2 is sufficient. |
| DA3-10: Direct user invocation undertested | DA | Judgment — most tests target Skill-tool dispatch. | **Justified — defer to test author discretion.** WI 1.14 includes a "user invokes /land-pr directly with --no-monitor" test case (added during smoke checkpoint refinement). Explicit `--help` handling and missing-required-arg messages are an ergonomic polish appropriate for a follow-up improvement, not a P1 blocker. |

**Round 3 substantive issues:** 8 fixed, 6 justified. 0 ignored.

**Convergence check (orchestrator's call):** Round 3 introduced 14 findings; the refinement addressed all of them. Of the 5 MAJOR findings, all 5 are FIXED (precedence, splice failure, drift hazard, parser validation, mock fallback). Of the 9 MINOR findings, 3 are FIXED (cleanup, heuristic, concurrent forks) and 6 are JUSTIFIED (helper doc, smoke infra fix, phase scope, rollback, parser idiom, user-invocation tests). Substantive issues remaining: **0**.

## Round 5 Disposition

(Refiner output of Round 5 review — verify-before-fix applied to each finding. Round 5 corresponds to /refine-plan against post-2026-04-27 ecosystem drift. Round 4 was the YAGNI pass already documented in the plan; this Round 5 is the post-ecosystem-drift refine fired ~2 weeks after the original draft, after PRs #88, #95-#100, #131, #138, #142, #149, #151-#156 landed and changed the surfaces being reorganized. Per the orchestrator's note in `/tmp/refine-plan-review-round-1-pr-landing-unification.md`, only 5 of the reviewer's 12 findings were preserved due to a file-management error; round 2 of the refine cycle will re-scan for any reviewer findings missed here.)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R5-1: Mirror recipes use `rm -rf` (hook-blocked) | Reviewer R1-1 + DA1-1 | **Verified.** `hooks/block-unsafe-generic.sh:201-220` blocks recursive rm without literal `/tmp/<name>` path. `scripts/mirror-skill.sh` exists per PR #88. The hook fired empirically when grep tested the plan text mid-refine. | **Fixed.** All 7 mirror WIs (1A.13, 1B.5, 2.8, 3.5, 3.10, 4.7, 5.7) and 2 acceptance criteria use `bash scripts/mirror-skill.sh <name>`. New load-bearing decision #10 documents the rule. |
| R5-2: `pr-monitor.sh` overlaps `skills/commit/scripts/poll-ci.sh` | Reviewer R1-2 + DA1-3 | **Verified.** `poll-ci.sh` exists (PR #142, lines 31-57); same `--watch + re-check` primitive; uses `2>/dev/null` (CLAUDE.md violation). Conformance assertion at `tests/test-skill-conformance.sh:151` references it. | **Fixed.** WI 1.5 amended with explicit consolidation decision: `pr-monitor.sh` is canonical successor; surfaces (does NOT preserve) the `2>/dev/null` bug. New WI 3.5a deletes `poll-ci.sh`. WI 3.4 removes the stale conformance assertion. New load-bearing decision #3. |
| R5-3: Phase 5 baseline mismatches current `/quickfix` | Reviewer R1-3 | **Verified.** `wc -l skills/quickfix/SKILL.md` = 1102 (not ~750 as in original plan). Triage gate at line 295, plan review at line 399 (PRs #151-#156). Phase 7 with `gh pr create` at lines 993-1102. | **Fixed.** WI 5.1, 5.2, 5.5 substantially rewritten. WI 5.2 explicitly enumerates which sections to preserve (triage, plan review, etc.). WI 5.5 uses surgical line-1102 replacement, not aggressive deletion. |
| R5-4: `write-landed.sh` / `land-phase.sh` paths wrong | Reviewer R1-7 | **Verified.** `find` returns `./skills/commit/scripts/{write-landed,land-phase}.sh` — moved by PRs #95-#100. Old plan referenced `scripts/write-landed.sh`. | **Fixed.** WI 1.12 step 8, WI 2.6, and Design & Constraints all use `skills/commit/scripts/...` and the runtime path `$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/...`. New load-bearing decision #11. |
| R5-5: WI numbering 1.13/1.14/1.15 stale post-1A/1B split | Reviewer R1-8 | **Verified.** `grep -n "WI 1\.1[3-5]"` returned hits at lines 75, 364, 370, 546, 547 in live prose. Disposition tables (lines 773+) historical, untouched. | **Fixed.** Mechanical rename in 5 live-prose locations: WI 1.13 → 1B.2, 1.14 → 1B.3, 1.15 → 1B.4. Disposition tables preserved as-is. |
| R5-6: WI 2.1 splice citation is wrong (sed at L1216-1217 doesn't exist) | DA1-2 | **Verified.** `skills/run-plan/SKILL.md:1206-1218` is test baseline capture, NOT body splice. Real splice at `:1715-1745` uses bash `BASH_REMATCH`. Conformance test `tests/test-skill-conformance.sh:102` already asserts the regex form. | **Fixed.** WI 2.1 substantially rewritten — preserve the existing bash-regex implementation verbatim; structural change is RELOCATION only. The 3 recovery paths now align with existing graceful-degradation (NOTICE/WARN, not hard `.landed conflict`). Overview line 30 and WI 1.4 line citations corrected. |
| R5-7: Phase 6 conformance plan does not enumerate stale assertions | DA1-4 | **Verified.** `tests/test-skill-conformance.sh:66-71, 144, 151-152, 197-199, 224-232` — ~13 assertions will fail post-migration. Original plan's "MOVE" / "STAY" was hand-wavy. | **Fixed.** WI 2.7, WI 3.4, WI 3.9, WI 4.6 all now contain per-line tables enumerating each assertion's action (RELOCATE / REMOVE / STAY / REWRITE) cited against current main. |
| R5-8: /quickfix "drift, not feature" framing stale post-#151 | DA1-5 | **Verified.** `skills/quickfix/SKILL.md:295,399` show triage and plan-review gates added by PRs #151-#156. Original "drift" framing predates these gates. | **Fixed.** Phase 5 Goal reframed: "/quickfix gains CI monitoring + fix-cycle as ADDITIVE coverage on top of the post-#151 triage + plan-review gates." WI 5.5 uses surgical line replacement. Load-bearing decision #9 updated. |
| R5-9: ADAPTIVE_CRON_BACKOFF Mode A interaction unaddressed | DA1-6 | **Verified.** `skills/run-plan/SKILL.md:439-573` — adaptive-cron machinery PRs #131, #138. Per-phase defer counters + boundary cadence step-down `*/1 → */10`. /land-pr's synchronous CI monitoring (up to 600s) crosses cadence boundaries. | **Fixed.** New WI 2.5a documents the interaction. No code change required (machinery is correct by design); WI 2.9 manual canary observes counter behavior. Sentinel safety also addressed. |
| R5-10: WI 3.7 deletes `gh pr create` from `skills/do/SKILL.md` (no-op) | DA1-7 | **Verified.** `grep -n "gh pr create" skills/do/SKILL.md` returns 0 hits. The "duplicate" was already removed (or never existed). | **Fixed.** WI 3.7 reframed as a regression-guard conformance assertion (no deletion needed). |
| R5-11: Stale line-range citations across multiple WIs | DA1-8 | **Verified.** All 5 caller files have new line counts vs. plan citations: `run-plan/modes/pr.md=681` (was "195-657"), `commit/modes/pr.md=96`, `do/modes/pr.md=232`, `fix-issues/modes/pr.md=201`, `quickfix/SKILL.md=1102` (was "693-748"). | **Fixed.** WI 2.2, WI 2.4, WI 5.1 use grep-able markers ("delete from `## Step 6` to ...") instead of hard line numbers. Approximate ranges retained for orientation. |
| R5-12: WI 1.1 specifies `allowed-tools` (no precedent in zskills) | DA1-9 | **Verified.** `grep -l "allowed-tools" skills/*/SKILL.md` returns 0 hits. | **Fixed.** Removed `allowed-tools` line from WI 1.1 frontmatter. Note added explaining why a hardening sweep belongs in a separate plan. |
| R5-13: Post-merge red-main canary interaction not in plan | DA1-10 | **Verified.** `.github/workflows/test.yml:82-122` (PR #149) auto-files `main-broken` issue on red push to main. Independent of /land-pr's exit status. | **Fixed.** New paragraph in Design & Constraints documenting the canary's independence from /land-pr. No code interaction needed — /land-pr does not write to `.github/`. |
| R5-14: WI 1.6 uses `gh --jq` while WI 1.4 uses bash regex (style inconsistency) | DA1-11 | **Judgment.** Both are policy-compliant per `feedback_no_jq_in_skills` (which forbids `jq` binary, not `gh --jq`). Style nit, not correctness. | **Justified.** Updated Design & Constraints with explicit note: bash-regex preferred per WI 1.4 precedent; `gh --jq` is acceptable for terseness. The implementer may standardize on bash-regex throughout in a follow-up polish if desired. |
| R5-15: `_CLEANUP_PATHS` empty-`CI_LOG_FILE` substring-match bug | DA1-12 | **Verified.** When `CI_LOG_FILE=` (empty), pattern `*""*` matches everything → no cleanup happens. Substring-prefix collision is also possible but rarer. | **Fixed.** WI 1.8 cleanup loop simplified — `_CLEANUP_PATHS` now contains only `CALL_ERROR_FILE` and `CONFLICT_FILES_LIST`; `CI_LOG_FILE` is excluded by construction. The substring-match line removed entirely. |
| R5-16: Duplicate "Load-bearing architectural decisions" subsection | Orchestrator | **Verified.** Two subsections at lines 893 + 904 of v4 plan. Second one referenced removed `splice-body.sh`. | **Fixed.** Reconciled to single 11-item list; updated to reflect post-Round-5 state (preserve `BASH_REMATCH` splice; `pr-monitor.sh` consolidates poll-ci.sh; mirror-skill.sh; etc.). |
| R5-17: Reviewer record partial (5/12 preserved) | Orchestrator note | **Acknowledged.** R1-4, R1-5, R1-6, R1-9, R1-10, R1-11, R1-12 lost in file-management error. JSONL transcript preserves them but is not read per protocol. | **Justified — out of scope for this round.** Round 2 of the refine cycle will re-scan for any drift findings missed here. The 5 reviewer findings preserved here, plus the full 12 DA findings, cover the most pressing post-merge ecosystem drift. |

**Round 5 substantive issues:** 16 fixed, 1 justified, 0 ignored.

## Round 5 Plan Review

**Refinement scope:** post-2026-04-27 ecosystem drift absorption. Round 5 was fired ~2 weeks after the original /draft-plan + /refine-plan (Rounds 1-4) when the maintainer noticed that ecosystem PRs #88, #95-#100, #131, #138, #142, #149, #151-#156 had materially changed surfaces the plan reorganizes. Round 5's refinement targeted: (a) stale citations (file paths, line numbers, framing assumptions); (b) overlapping primitives that emerged in the interim (`poll-ci.sh`, `mirror-skill.sh`); (c) hidden integration costs (adaptive cron, post-merge canary); (d) one duplication that pre-existed (load-bearing decisions section).

**Round 5 substantive issues:** 17 total findings. **16 fixed**, **1 justified** (R5-17, partial-reviewer record acknowledged but out of scope for the refiner). **0 ignored.**

**Note about partial-reviewer record:** the orchestrator preserved 5 of the reviewer's 12 round-1 findings; the lost 7 are recoverable only from the JSONL transcript (do not read per protocol). Round 2 of the refine cycle is expected to re-scan for any drift the round-1 reviewer might have caught and the orchestrator's partial preservation missed.

**Verify-before-fix outcomes:** of the 16 empirical findings, 16 reproduced and were fixed. No DA finding turned out to be a plausible-sounding-but-false claim this round — the DA's grounding was unusually solid (likely because the empirical claims were all "the file as it exists at HEAD `b1db0b2` differs from the plan's claim," which is mechanical to verify). One judgment-class finding (R5-14, --jq style) was justified-not-fixed as a style nit deferred to follow-up polish. R5-17 is an orchestrator-level housekeeping note, not an empirical claim.

**New observations the reviewer/DA may have missed (candidates for Round 6):**
1. **WI 5.1 still references "Phase 7 (currently lines 993-1102)"** — even with the explanatory note, an aggressive implementer might delete the entire range. The grep-able-marker recommendation should be amplified in WI 5.1 with explicit start/stop markers ("from `^## Phase 7 — PR creation` to the line BEFORE `^## Phase 8` or end-of-file"). Round 6 may want to tighten this.
2. **`scripts/mirror-skill.sh` is a thin per-file mirror — verify it handles the `references/` subdirectory** introduced by /land-pr. The script may need a small update or the WI may need to add an `--include references` flag. Round 6 should verify the script's actual behavior against /land-pr's directory layout (multiple subdirs: `scripts/`, `references/`).
3. **WI 6.1 "no `gh pr merge`" check has a false-positive risk** — `pr-merge.sh` itself contains `gh pr merge --auto --squash`. The current rule says "outside `skills/land-pr/`" so it's fine, but the check should be tightened to also exclude `skills/land-pr/scripts/`. (Already covered by current wording, but worth flagging.)
4. **Phase 4 sprint-report path:** `/fix-issues` writes a sprint report; the original plan's WI 4.4 says it's "unchanged" but does not check whether the report references the now-replaced inline CI block. Round 6 should grep the sprint-report template for stale CI-block references.
5. **`pr-rebase.sh` exits 11 on "branch absent"** but does NOT distinguish "fetch-failed-network" from "branch-doesn't-exist." The /land-pr caller-loop's `rebase-failed` STATUS becomes ambiguous. Could use a `REASON` token to distinguish.

These are low-priority candidates; Round 6 should decide whether to fold them in or defer.

## Round 6 Disposition

(Refiner output of Round 6 — final round of post-2026-04-27 ecosystem-drift refine. Verify-before-fix applied to each finding. Round 6 specifically re-verified the 3 HIGH-class DA findings that contradicted Round 5 refiner's "verified" claims; 2 of 3 reproduced.)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R6-1 / DA6-1 (HIGH, original DA2-1): WI 3.7's "0 hits for `gh pr create` in `do/SKILL.md`" claim is FALSE | DA Round 2 | **Verified — DA's claim REPRODUCED.** Ran `grep -n "gh pr create" skills/do/SKILL.md` against current main `b1db0b2`: returns line 878: `- **PR titles and bodies are explicit** — never use \`--fill\` in \`gh pr create\`.` This is a Key Rules prose constraint about the `--fill` flag, but the WI 6.1 tripwire grep would still match it. Round 1 refiner's "verified 0 hits" claim was wrong — they likely grepped a stale checkout or misread the output. | **Fixed.** WI 3.7 rewritten: edit line 878 to remove the literal `gh pr create` substring (replacement preserves the `never use --fill` semantics so the existing `do "no --fill"` conformance assertion at L195 still passes). Honest acknowledgment: Round 1 refiner missed this empirical claim; Round 6 caught it. |
| R6-2 / DA6-2 (HIGH, original DA2-2): Phase 6 tripwires fire on prose mentions across 3+ files | DA Round 2 | **Verified — REPRODUCED.** Ran `grep -rn "gh pr create" skills/`: confirmed prose hits at `skills/do/SKILL.md:878`, `skills/run-plan/modes/pr.md:309` (Manual fallback echo), `skills/fix-issues/SKILL.md:1082` (gating prose), `skills/commit/modes/pr.md:80-81` (description prose), `skills/run-plan/modes/pr.md:362, 419` (description prose). After WI 2.2 / 3.1 / 3.6 / 4.1 / 5.1 inline deletions, several of these prose mentions survive (Key Rules constraints, manual-fallback echoes, design notes). Naive substring tripwires WILL false-fail on these. | **Fixed.** WI 6.1 rewritten with start-of-line-anchored invocation patterns (e.g., `^[[:space:]]*(if[[:space:]]+!?[[:space:]]*)?[A-Z_]*=?(\$\()?gh pr create\b`) that match live invocations but not prose backtick-quoted substrings or list-marker-prefixed mentions. Three concrete shell assertions provided (gh pr create / gh pr checks --watch / gh pr merge), each excluding prose patterns. R2-4's `dispatch.*agent` start-of-line anchor also folded in. |
| R6-3 / DA6-3 (HIGH, original DA2-3): WI 2.2's `## Step 6` start-anchor is fictional in `run-plan/modes/pr.md` | DA Round 2 | **Verified — REPRODUCED.** Ran `grep -n "Step 6" skills/run-plan/modes/pr.md`: zero hits. Ran `grep -nE "^## " skills/run-plan/modes/pr.md`: zero hits (no Markdown H2 headers in this file). Ran `grep -nE "^# --- " skills/run-plan/modes/pr.md`: confirmed bash-comment headers `# --- PR creation ---` (line 268), `# --- Auto-merge ---` (587), and H3 `### Post-landing tracking` (681). Origin: `## Step 6` is real in `commit/modes/pr.md:62`, NOT in `run-plan/modes/pr.md`. Round 5 refiner conflated the two files. | **Fixed.** WI 2.2 corrected to use real anchors: `# --- PR creation ---` (line 268) for start, `### Post-landing tracking` (line 681) for end. Approximate range adjusted from "281–680" to "268–680". Honest acknowledgment: Round 5's marker-discipline fix (R5-11) introduced a phantom marker; Round 6 replaced it with verified anchors. |
| R6-4 / DA6-4 (MEDIUM, original DA2-4): WI 4.2 cites wrong line for 300s timeout | DA Round 2 | **Verified — REPRODUCED.** Ran `grep -n "timeout 300" skills/fix-issues/modes/pr.md`: returns line 140 (a comment), NOT line 126. Line 126 is `LANDED` heredoc terminator. The `--ci-timeout 300` flag invocation does not exist in current main; the 300s reference is a code comment about the special case. Conformance assertion `tests/test-skill-conformance.sh:224` matches the comment text. | **Fixed.** WI 4.2 corrected: cite line 140 as the comment site; clarify there is no `--ci-timeout` flag invocation to remove (only the comment + the 300s special-case prose); WI 4.6 line 224 already says REMOVE the conformance assertion (consistent). |
| R6-5 / DA6-5 (MEDIUM, original DA2-5): WI 1.5 used `WATCH_RC` but conformance assertion expects `WATCH_EXIT` | DA Round 2 | **Verified — REPRODUCED.** Ran `grep -n "WATCH_EXIT\|WATCH_RC" skills/run-plan/modes/pr.md`: returns 4 hits, all `WATCH_EXIT` (lines 388, 397, 539, 542). `tests/test-skill-conformance.sh:68` is `WATCH_EXIT" -eq 124`. Plan's `WATCH_RC` would force the assertion to be REWRITTEN at relocation time. | **Fixed.** WI 1.5 step 3-4 changed from `WATCH_RC` to `WATCH_EXIT` (matches existing variable name). WI 2.7 line 68 row updated to note the regex matches verbatim post-relocation. |
| R6-6 / DA6-6 / R6-DA1-4-recount (MEDIUM, original DA2-6 + R2-2): WI 2.7 omits line 69; total assertion count is 24, not ~13 | DA Round 2 + Reviewer Round 2 | **Verified — REPRODUCED.** Ran `grep -nE "^check[[:space:]]+(commit\|do\|run-plan\|fix-issues\|quickfix)\|^check_fixed[[:space:]]+(commit\|do\|run-plan\|fix-issues\|quickfix)" tests/test-skill-conformance.sh` and counted PR-mode-affected assertions: run-plan=9 (lines 66, 67, 68, 69, 70, 71, 72, 73, 74), commit=3, do=4, fix-issues=8 — total 24. Plan's per-line tables in WI 2.7 / 3.4 / 3.9 / 4.6 enumerated 23 of these — only line 69 (`run-plan "ci-pending pr-ready"`) was missing. Round 1's "~13" estimate was significantly low. | **Fixed.** WI 2.7 table now includes line 69 (REWRITE — the `pr-ready` literal disappears from `run-plan/modes/pr.md` after WI 2.2; rewrites against `land-pr` schema) and line 75 (STAY — verified the literal lives in `cherry-pick.md:83`, not `pr.md`). Total per WI 2.7 row footer: 9 run-plan assertions enumerated. Combined cross-skill total of 24 documented in WI 2.7. |
| R6-7 / DA6-7 (MEDIUM, original DA2-7): WI 1.3 conflict-files capture order ambiguous | DA Round 2 | **Verified — REPRODUCED.** Reviewed `skills/run-plan/modes/pr.md` lines 30, 121: both sites capture conflicts via `git diff --name-only --diff-filter=U` BEFORE `git rebase --abort` (because abort resets the working tree and erases conflict markers). WI 1.3 spec was order-ambiguous. | **Fixed.** WI 1.3 now explicitly specifies capture-then-abort: 4 ordered steps (capture-into-sidecar → verify sidecar non-empty → abort with rc check → emit `CONFLICT_FILES_LIST`). |
| R6-8 / DA6-8 (MEDIUM, original DA2-8): WI 3.4 misclassifies PR #131 prompt-engineering lesson as script-failure-mode | DA Round 2 | **Verified — REPRODUCED.** Read `skills/commit/modes/pr.md:62-70`: the preamble is "agent skipped Step 6 on PR #131 push, read inline bash as suggestion-prose, did one snapshot `gh pr checks 131` showing pending, reported that, exited" — a prompt-engineering / agent-discipline lesson, NOT a script-failure-mode. `failure-modes.md` per WI 1B.1 catalogs script-level failures (e.g., `gh pr checks` returns no checks). Wrong document. | **Fixed.** WI 3.4 now RELOCATES the verbatim PR #131 preamble paragraph to `/land-pr`'s SKILL.md prose immediately above WI 1.12 step 6 (the `pr-monitor.sh` invocation step), reworded to point at /land-pr's polling instead of /commit's. New conformance assertion: `check land-pr "PR #131 past-failure preamble" 'Past failure.*PR #131|skipped Step 6 on PR #131'`. WI 1.12 step 6 updated to mention the prepended preamble. |
| R6-9 / DA6-9 / R6-R2-1 (NIT/LOW, original R2-1 + DA2-9): WI 5.1 line range invites Key Rules over-deletion; Round 5 candidate #1's `^## Phase 8` end-anchor is fictional | Reviewer + DA Round 2 | **Verified — REPRODUCED.** Ran `grep -nE "^## Phase " skills/quickfix/SKILL.md`: returns Phase 1 (137), Phase 2 (269), Phase 3 (715), Phase 4 (820), Phase 5 (851), Phase 6 (974), Phase 7 (993). NO Phase 8. Phase 7 is followed by `## Exit codes` (line 1082) and `## Key Rules` (line 1093). Round 5 Plan Review's recommended `^## Phase 8` end-anchor would lock the implementer to a fictional anchor. | **Fixed.** WI 5.1 rewritten with concrete anchors: start `^## Phase 7 — PR creation` (line 993), end `^## Exit codes` (line 1082); explicit instruction NOT to delete `## Exit codes` or `## Key Rules`; WI 5.5 separately handles only the single Key Rules line at 1102. |
| R6-10 (LOW, original DA2-10): Round 5 candidate #2 (mirror-skill.sh references/ subdir) is a non-issue | DA Round 2 | **Verified — DA's "non-issue" claim REPRODUCED.** Ran `find skills -name "references" -type d`: returns 3 existing `references/` subdirs (`fix-issues`, `run-plan`, `update-zskills`). `scripts/mirror-skill.sh` line 35 uses `cp -a "$SRC/." "$DST/"` which copies all subdirs natively. The Round 5 Plan Review's flag was over-cautious. | **Justified — concern refuted.** Round 5 Plan Review candidate #2 dropped. No fix needed; mirror-skill.sh already handles `references/` correctly. |
| R6-11 (LOW, original DA2-11): `_CLEANUP_PATHS` space-splitting bug | DA Round 2 | **Verified — REPRODUCED.** Plan WI 1.8 used `_CLEANUP_PATHS="${LP[CALL_ERROR_FILE]:-} ${LP[CONFLICT_FILES_LIST]:-}"` then `for f in $_CLEANUP_PATHS`. If a sidecar path contained spaces (validate_result_value rejects newlines/$/`/&/?/# but NOT spaces), the unquoted expansion would split on spaces. | **Fixed.** WI 1.8 now uses bash array: `_CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}")` and `for f in "${_CLEANUP_PATHS[@]}"`. Trivial bash, no metacharacter pitfalls. |
| R6-12 / R6-R2-3 (NIT/INFO, original R2-3): WI 5.1 `gh pr create --head` form citation | Reviewer Round 2 | **Verified — informational only.** Ran `grep -n "gh pr create" skills/quickfix/SKILL.md`: line 1035 `gh pr create --base "$BASE_BRANCH" --head "$BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`. The plan's `check_not quickfix "no inline gh pr create" 'gh pr create'` correctly catches this form. No issue. | **Justified — informational only, no action.** R2-3 itself recommended "Mark as informational." |
| R6-13 / R6-R2-4 (NIT, original R2-4): WI 6.1 `dispatch.*agent` not start-of-line anchored | Reviewer Round 2 | **Verified — REPRODUCED.** Plan's WI 6.1 third alternative `dispatch.*agent` lacked `^[[:space:]]*` prefix; would false-match prose like "The skill dispatches the agent at orchestrator level." | **Fixed.** WI 6.1 rewritten (per R6-2 / DA2-2 above) — all three alternatives in the dispatch heuristic uniformly anchored to start-of-line. Documented residual limitation about Agent:-prefix prose. |
| R6-14 (info, original R2-3 dup count): test.yml line range 82-110 → 82-122 | DA Round 2 fix-integrity summary | **Verified.** Ran `wc -l .github/workflows/test.yml`: 122 lines; the post-merge canary block extends through end-of-file (line 122). Plan cited 82-110 in 2 places. | **Fixed.** Both citations of `.github/workflows/test.yml:82-110` updated to `:82-122`. |
| R6-15 / R6-R5-17 (info): Round 5 partial-reviewer record caveat | Orchestrator note | **Acknowledged.** Round 5 reviewer preserved 5/12 findings. Round 6 reviewer ran independently and produced 4 new findings (R2-1 through R2-4), all minor. The 7 lost Round 1 reviewer findings are not recoverable per protocol. | **Justified — out of scope; round 6 reviewer covered the surface.** Round 6 reviewer's 4 findings + DA's 11 findings together cover the post-Round-5 state thoroughly. |

**Round 6 substantive issues:** **15 findings total** — **11 fixed**, **3 justified — evidence reproduced but disposition was no-action** (R6-10 mirror-skill.sh non-issue; R6-12 R2-3 informational; R6-15 partial-reviewer caveat), **1 justified — evidence supports disposition** (R6-13 fixed via R6-2 fold-in). **0 ignored.**

**Honest convergence assessment (post-Round-6):**

- **DA's HIGH findings: 3 of 3 reproduced (DA2-1, DA2-2, DA2-3).** Round 1 refiner's verify-before-fix discipline broke down on these — the empirical claims that Round 1 marked "Verified" were not actually verified. Specifically:
  - DA2-1: Round 1 said `grep -n "gh pr create" skills/do/SKILL.md` returns 0 hits. Re-running returns 1 hit at line 878. Round 1 was wrong.
  - DA2-2: Round 1 didn't verify the WI 6.1 tripwires against current main. Re-running confirms they false-fail on prose mentions in 3+ files.
  - DA2-3: Round 1 introduced `## Step 6` as a "marker-discipline fix" but didn't verify the marker exists in `run-plan/modes/pr.md`. It doesn't (it's in `commit/modes/pr.md`). Round 1 conflated the two files.
- **DA's MEDIUM findings: 5 of 5 reproduced (DA2-4, DA2-5, DA2-6, DA2-7, DA2-8).** Each reflects a citation-class or framing-class miss in Round 5.
- **DA's LOW findings: 2 of 3 reproduced (DA2-9, DA2-11), 1 confirmed-as-non-issue (DA2-10).**
- **Reviewer's findings: 4 minor/nit, all addressed (3 fixed, 1 informational).**
- **DA1-4 recount:** Round 1 estimated ~13 PR-mode conformance assertions affected by migration; actual count is 24. Plan's per-line tables enumerated 23 of these; only line 69 was missing. Now corrected — full 24 documented.

**Most consequential Round 1 miss:** the Round 5 refiner's "DA1's grounding was unusually solid" comment (now-overwritten Round 5 Plan Review claim) was contradicted by 3 false "verified" claims that Round 6 caught. The lesson: even when DA findings reproduce systematically, individual "Verified — 0 hits" lines must be re-run by the next round's refiner with the exact pattern in the exact scope. Plan now corrected.

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review, then `/refine-plan` Round 4 (YAGNI pass), Round 5 (post-ecosystem-drift refine), and Round 6 (post-Round-5 verification + final polish).
**Convergence:** Converged at Round 6 — final round of the user's 2-round /refine-plan budget. 11 of 15 Round 6 findings fixed; 4 justified (3 informational/non-issues; 1 fold-in). Round 6 specifically caught 3 HIGH-class verify-before-fix failures from Round 5 (refiner's "verified" claims that didn't reproduce).
**Remaining concerns:** None blocking. The 2 LOW-class findings that didn't fix (R6-10 mirror-skill.sh non-issue; R6-12 R2-3 informational) are dispositioned as no-action with evidence. The plan is ready for `/run-plan` execution.

### Round History

| Round | Source | Reviewer | DA | Total findings | Fixed | Justified | Ignored |
|-------|--------|---------:|---:|---------------:|------:|----------:|--------:|
| 1     | /draft-plan | 8 | 10 | 18         | 12    | 4         | 0       |
| 2     | /draft-plan | 6 | 10 | 16         | 12    | 4         | 0       |
| 3     | /draft-plan | 6 | 10 | 14         | 8     | 6         | 0       |
| 4     | /refine-plan (YAGNI pass) | 6 | 6 | 12 | 4 (1 removal + 3 simplifications + Phase 1 split) | 8         | 0       |
| 5     | /refine-plan (ecosystem drift) | 5* | 12 | 17 | 16    | 1         | 0       |
| 6     | /refine-plan (post-Round-5 verify) | 4 | 11 | 15 | 11    | 4         | 0       |
| **Cumulative** | | **35** | **59** | **92** | **63** | **29** | **0** |

*Round 5 reviewer record partial — 5 of 12 findings preserved due to orchestrator file-management error. Round 6 reviewer ran independently and surfaced 4 new minor/nit findings, all addressed.

## Drift Log

The plan was drafted via `/draft-plan rounds 3` (commit ee6ad28) and refined via `/refine-plan` (this commit). No phases have been executed yet — Drift Log captures only the refinement-time structural delta vs. the original draft.

| Phase | Drafted | Current | Delta |
|-------|---------|---------|-------|
| 1 (single phase) | 17 WIs, smoke checkpoint, ~1700 lines new code | **Split into 1A (foundation) and 1B (validation)** | 2 phases of ~10 + ~6 WIs; smoke at end of 1A; reviewable PR boundary; Phase 1 scope (DA9/DA3-6) addressed structurally |
| 1 → WI 1.5a (`splice-body.sh` shared utility) | Added in /draft-plan Round 3 | **Removed** | YAGNI premature extraction — only /run-plan needs splicing today; future callers can extract when actually needed |
| 2 → WI 2.1 (body splice) | Round-3: sed→awk improvement on a phantom `SKILL.md:1216-1217` sed pattern; Round-4: 3 hard-failure paths with inline awk | **Round-5: preserve existing `BASH_REMATCH` splice at `SKILL.md:1715-1745` verbatim; recovery paths use NOTICE/WARN graceful continuation, not `.landed conflict`** | DA1-2: the sed at L1216-1217 never existed; the real splice is bash-regex at L1715-1745 and is already conformance-tested. Rewriting it would have broken passing assertions. |
| All phases — mirror recipes | `rm -rf .claude/skills/<name> && cp -a` | **`bash scripts/mirror-skill.sh <name>`** | DA1-1: `hooks/block-unsafe-generic.sh:201-220` blocks recursive rm outside `/tmp/`; PR #88's `mirror-skill.sh` is the canonical helper. |
| 1A → WI 1.5 (`pr-monitor.sh`) | Standalone implementation | **Consolidated successor to `skills/commit/scripts/poll-ci.sh`** | DA1-3 + R1-2: `poll-ci.sh` (PR #142) is the same primitive. Phase 3 WI 3.5a deletes it; `pr-monitor.sh` surfaces (does not preserve) the pre-existing `2>/dev/null` bug. |
| 6 → WI 6.1 conformance | "MOVE assertions" hand-wave | **Per-line tables** in WI 2.7, 3.4, 3.9, 4.6 enumerating each affected assertion's RELOCATE / REMOVE / STAY / REWRITE action | DA1-4: ~13 assertions in `tests/test-skill-conformance.sh:66-232` will fail post-migration without explicit per-line guidance. |
| 5 → Phase 5 framing | "/quickfix's fire-and-forget is drift, not a feature" | **"/quickfix gains CI monitoring + fix-cycle as ADDITIVE coverage on top of post-#151 triage + plan-review gates"** | DA1-5: PRs #151-#156 added upstream rigor (triage, plan-review); the "drift" framing was stale. |
| 2 → New WI 2.5a | Not present | **ADAPTIVE_CRON_BACKOFF Mode A interaction documented** | DA1-6: PRs #131, #138 added per-phase defer counters + cadence step-down at boundary fires `*/1 → */10`. /land-pr's synchronous CI monitoring crosses cadence boundaries; behavior is correct by design but must be documented. |
| 3 → WI 3.7 | "Remove duplicate `gh pr create` from `do/SKILL.md`" | **Reframed as regression-guard conformance assertion** (no deletion needed) | DA1-7: empirical grep showed 0 hits — the duplicate is already absent at HEAD `b1db0b2`. |
| All phases — line citations | Hard line numbers (e.g., "lines 195-657") | **Grep-able markers** for the inline blocks being deleted; line numbers retained as orientation | DA1-8: 5 caller files have all drifted in line counts since 2026-04-27. Markers survive future drift. |
| 1A → WI 1.1 frontmatter | Included `allowed-tools: ...` | **Removed** | DA1-9: no zskills skill uses `allowed-tools`; introducing it on /land-pr alone is inconsistent. Hardening sweep belongs in a separate plan. |
| 1A → Design & Constraints | "Hooks compatibility" only | **Added post-merge red-main canary interaction (PR #149)** | DA1-10: `.github/workflows/test.yml:82-122` auto-files `main-broken` issues independent of /land-pr's exit; documented as intentional. |
| All phases — `.landed` writers | `scripts/write-landed.sh` | **`skills/commit/scripts/write-landed.sh`** (runtime: `$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh`) | R1-7: PRs #95-#100 moved scripts under `skills/commit/scripts/` per ownership. |
| 1A → WI 1.8 cleanup | `[[ "$f" != *"$CI_LOG_FILE"* ]]` substring match | **Build `_CLEANUP_PATHS` from cleanup-targets only (`CALL_ERROR_FILE`, `CONFLICT_FILES_LIST`); exclude CI_LOG_FILE by construction** | DA1-12: empty `CI_LOG_FILE` makes `*""*` match-all → no cleanup. Constructive exclusion is simpler and bug-free. |
| Load-bearing decisions section | Two duplicate subsections | **Single 11-item list** | Orchestrator note: pre-existing duplication; Round 5 reconciled to one list reflecting all post-Round-5 decisions. |
| Phase 2-6 dependencies | "Phase 1 must be complete" | **"Phases 1A and 1B must both be complete"** | Mechanical update from the split (Round 4). |

## Plan Review

**Refinement process:** `/refine-plan rounds 1` with focused YAGNI guidance from the maintainer.

**Convergence:** Round 4 (refinement) found 12 findings; the surgical refinement addressed them with concrete edits or justified-not-fix.

**Scope of Round 4:** the refinement targeted speculative additions from /draft-plan Round 3 (DA-driven hypothetical-future-drift items) and the Phase 1 scope concern that had been justified-not-fixed in Rounds 1 and 3. The maintainer's guidance was "surgical, don't rewrite."

### Round 4 Disposition

| Finding | Source | Disposition |
|---|---|---|
| **WI 1.5a (`splice-body.sh`) is YAGNI** | Reviewer + maintainer | **Fixed (removed).** Only /run-plan splices bodies today; /commit pr, /do pr, /fix-issues pr, /quickfix all create the PR body once and never update it. The "future caller drift" hypothesis was speculative. Inline awk in /run-plan's WI 2.1 replaces it. |
| **WI 2.1 — collapse 5 recovery paths to 3** | Reviewer | **Fixed (simplified).** Two paths (`splice-marker-mismatch`, `splice-write-failed`) were artifacts of the removed shared utility. Remaining 3 (`gh-pr-view-failed`, `body-markers-missing`, `gh-pr-edit-failed`) cover real failure modes. |
| **Phase 1 scope (17 WIs, ~1700 lines)** | DA9 (R1) + DA3-6 (R3) + maintainer | **Fixed (split into 1A/1B).** Re-opened from prior justified-not-fix dispositions. 1A = foundation + caller-facing references + smoke (~10 WIs); 1B = failure-modes doc + mocks + tests + conformance (~6 WIs). Phases 2–5 depend on both. Each phase is now a reviewable PR boundary. |
| **WI 1.8 `_CLEANUP_PATHS` fragile string-match** | Reviewer | **Justified.** The current pattern preserves CI_LOG_FILE while cleaning others; it works correctly. A simpler pattern (only put cleanup-targets into the array) is a future polish, not a P1 blocker. |
| **WI 1.13 mock-gh stateful counter** | DA (counter to reviewer YAGNI) | **Justified — keep.** Real test need: pre-check loop tests need sequential canned responses. Not over-engineering. |
| **WI 1.13 `_CLEANUP_PATHS` cleanup itself necessary** | DA | **Justified — keep.** Real disk-space concern; CI_LOG_FILE preservation requires explicit sequencing. |
| **WI 6.1 dispatch heuristic** | Reviewer (keep) | **Justified — keep.** Real conformance value; line-anchor pattern correctly avoids prose false-matches. |
| **Smoke checkpoint** | DA + Reviewer (keep) | **Justified — keep, now naturally aligned with Phase 1A's end.** With the split, the smoke is the natural validation gate before 1B starts. |
| **Round 3 prior-art bug fixes (87af82a/1de3049/175e4aa/b904cef)** | DA distinction call-out | **Justified — keep.** Distinguished from speculative additions; these are mandatory hardenings against documented prior bugs. |
| **WI 1.14 test cases stay** | DA | **Justified — keep.** Tests cover real failure modes; not speculative. |
| **Other Round 3 fixes (status mapping precedence, mock fail-fast, etc.)** | DA distinction | **Justified — keep.** All address real correctness or test-confidence issues, not speculative future drift. |

### Cumulative Convergence

After 6 rounds (3 /draft-plan + 3 /refine-plan: YAGNI pass, ecosystem drift, post-Round-5 verification), the plan has **92 total findings dispositioned: 63 fixed, 29 justified-not-fixed, 0 ignored**. Round 6 explicitly re-verified 3 HIGH-class DA findings that contradicted Round 5 refiner's "Verified" claims; all 3 reproduced (Round 1 refiner missed them):
- **DA2-1 (HIGH):** `gh pr create` exists at `skills/do/SKILL.md:878` (Round 5 said 0 hits).
- **DA2-2 (HIGH):** Phase 6 tripwires false-fail on prose mentions across 3+ files (Round 5 didn't run them).
- **DA2-3 (HIGH):** `## Step 6` anchor used in WI 2.2 doesn't exist in `run-plan/modes/pr.md` (Round 5 conflated `commit/modes/pr.md`).

The 5 Round-5 candidate items have all been resolved in Round 6: (1) WI 5.1 line range tightened with concrete `^## Exit codes` end-anchor; (2) mirror-skill.sh references/ subdir verified non-issue (dropped); (3) WI 6.1 false-positive risk addressed via start-of-line invocation patterns; (4) /fix-issues sprint-report verified clean (no stale CI-block references); (5) `pr-rebase.sh` `REASON` token added in WI 1.3 to distinguish network/branch-absent/not-a-repo failures.

**Plan is ready for `/run-plan` execution.** No remaining substantive issues. Round 6 caught 3 load-bearing factual errors that would have broken Phase 6 conformance assertions and Phase 2 implementation; honest disposition table (Round 6 Disposition above) records the verify-before-fix lineage so future maintainers can trace why the corrections were made.

### Load-bearing architectural decisions (read these before considering future changes)

1. **File-based result contract with allow-list parser** (Phase 1A WI 1.7) — `/land-pr` writes single-line shell-safe `KEY=VALUE` lines plus sidecar files for multi-line content. Caller parses via line-by-line allow-list; never `source`s the file. Eliminates the shell-injection class.
2. **Caller-owned body splice — preserve existing `BASH_REMATCH` implementation** (Phase 2 WI 2.1) — `/land-pr`'s `pr-push-and-create.sh` does NOT touch PR body on existing PRs. /run-plan splices its own progress section using its existing bash-regex implementation at `skills/run-plan/SKILL.md:1715-1745` (NO shared utility — that was YAGNI; no rewrite to awk/sed — DA1-2 verified the existing implementation already handles `&`/`\` correctly via `BASH_REMATCH`).
3. **`pr-monitor.sh` is the consolidated successor to `skills/commit/scripts/poll-ci.sh`** (Phase 1A WI 1.5 + Phase 3 WI 3.5a) — single `--watch + re-check` primitive across all callers; `poll-ci.sh` deleted in Phase 3 after `/commit pr` migrates. Surfaces the pre-existing `2>/dev/null` bug rather than preserving it.
4. **Status mapping table is first-match-wins** (Phase 1A WI 1.12 step 8) — failure-exits and CI-failure rows precede CI-pass rows so the "merge requested but CI failed" combo is reported as `pr-ci-failing`, not `landed`.
5. **Mock-gh fail-fast on missing canned response** (Phase 1B WI 1B.2) — exit 127 with stderr error instead of silent exit 0. Eliminates false test confidence.
6. **Subagent boundary contract** (Overview + Phase 1A WI 1.1 description) — `/land-pr` and the caller's fix-cycle agent dispatch are orchestrator-level only; never inside an Agent-dispatched subagent. Documented contract; no runtime guard. Conformance heuristic in WI 6.1.
7. **Phase 1 split into 1A (foundation) + 1B (validation)** — reviewable PR boundary; smoke checkpoint validates 1A before 1B writes tests on top.
8. **Drop 300s `/fix-issues` timeout special case** (Phase 4 + Round-1 DA6 disposition) — same CI pipeline, same timeout. Sequential N-issue accumulation is solved by parallelism (`--auto`), not by under-timeouting CI.
9. **/quickfix gains CI monitoring + fix-cycle as ADDITIVE coverage on top of post-#151 triage + plan-review gates** (Phase 5 + Round-1 DA10 + Round-2 R2-6 + Round-5 DA1-5 dispositions) — original "fire-and-forget = drift" framing was stale post-PR-#151; the corrected framing is "/quickfix gains CI monitoring + fix-cycle for parity with the other 4 callers when CI fails." Triage + review remain as upstream gates.
10. **All mirror WIs use `bash scripts/mirror-skill.sh <name>`** (per DA1-1) — never `rm -rf .claude/skills/<name>`, which is hook-blocked by `hooks/block-unsafe-generic.sh:201-220`. PR #88's helper does per-file mirror that respects the guard.
11. **Landing primitives live under `skills/commit/scripts/`** (per R1-7) — `write-landed.sh` and `land-phase.sh` were moved by PRs #95-#100; agent invocations use `$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/`.
