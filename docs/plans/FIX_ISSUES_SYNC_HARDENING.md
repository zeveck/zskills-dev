---
issues: [231, 233]
title: /fix-issues sync — bootstrap empty issues_dir + honor execution.main_protected
created: 2026-05-12
status: active
---

# Plan: /fix-issues sync — bootstrap empty issues_dir + honor execution.main_protected

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

`/fix-issues sync` has two correctness gaps that bundle naturally:

- **#231 — bootstrap gap.** When `$ZSKILLS_ISSUES_DIR/` has no tracker files (no `*_ISSUES.md`, no `ISSUES_PLAN.md`), `skills/fix-issues/SKILL.md:521,542` does `ls ... 2>/dev/null` and silently returns empty. The research-and-record loop has nothing to write into and silently no-ops; the sync summary reports `K=0 trackers updated` without flagging the gap.
- **#233 — `main_protected` violation.** Sync's prose at `skills/fix-issues/SKILL.md:282` ("**Commit** updated tracker files.") is implemented by the orchestrator as a bare `git commit` in whatever cwd the orchestrator started in (typically the main repo, branch `main`). Under `execution.main_protected: true`, the `block-direct-main-commit` hook at `hooks/block-unsafe-project.sh.template:475-477` deterministically denies the commit, leaving research blurbs written to the working tree with no way to land. `main_protected` is currently honored at admission for `direct` landing mode (`skills/fix-issues/SKILL.md:109-119`); sync was scoped pre-`main_protected` as a hygiene op and is exempt, but tracker files are versioned content and the boundary applies equally.

The two issues bundle because the #233 fix (route the step-5 commit through a worktree + `/land-pr` when `main_protected: true`) is what makes #231's bootstrap write safe under protection. Splitting would force either a partial fix or duplicate worktree plumbing.

## Acceptance Criteria (plan-level)

- [ ] AC-P.1 — `/fix-issues sync` on a repo with empty `$ZSKILLS_ISSUES_DIR/` and at least one open GH issue bootstraps a tracker file, populates it with the open issues, and runs the research-agent dispatch on those entries. The `K=0 trackers updated` silent-no-op from #231 is no longer reachable.
- [ ] AC-P.2 — `/fix-issues sync` on a repo with `execution.main_protected: true` and current branch in `{main, master}` does not attempt a direct `git commit` on the protected branch. Tracker-file commits are routed through a sync worktree branch + `/land-pr`.
- [ ] AC-P.3 — When the worktree+PR path is taken, `gh issue close` calls in Sync step 4 are deferred until AFTER `/land-pr` returns `STATUS=created` or `STATUS=merged`. If `/land-pr` fails, no GitHub issues are closed (no state divergence).
- [ ] AC-P.4 — Sync producing zero net changes (no new issues, no closures, no annotations, no bootstrap write) is detected via `git status --porcelain` BEFORE worktree creation; sync exits cleanly with no PR.
- [ ] AC-P.5 — When `execution.main_protected: false` OR current branch is not `main`/`master`, sync executes the legacy direct-commit semantics (specified below — no pre-existing bash block exists; both paths are authored fresh by this plan).
- [ ] AC-P.6 — Both Standalone Sync (`skills/fix-issues/SKILL.md:183-295`) and Phase 1a Sync (`skills/fix-issues/SKILL.md:507-565`) bootstrap consistently. Sprint-mode auto-sync re-entry (`skills/fix-issues/SKILL.md:685-693`) also benefits from the step-5 fix because it re-enters standalone sync.
- [ ] AC-P.7 — `skills/fix-issues/SKILL.md` carries a current `metadata.version` after every commit (per-phase commits each bump; the final value is the hash of the final tree). `diff -rq skills/fix-issues .claude/skills/fix-issues` empty.
- [ ] AC-P.8 — `bash tests/run-all.sh` exits 0. `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-P.9a — The PR landing THIS plan includes `Closes #231` and `Closes #233` in the body so merge auto-closes both.
- [ ] AC-P.9b — Runtime sync PRs (the ones produced by `/fix-issues sync` after this plan lands) do NOT include `Closes #N` for issues that step 4b already closed via the GitHub API (avoids redundant API calls at merge).
- [ ] AC-P.10 — Pre-existing uncommitted/untracked work in the main repo that is unrelated to sync (paths outside `$ZSKILLS_ISSUES_DIR/` and `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`) is unaffected by sync's worktree-routing path.
- [ ] AC-P.11 — `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2 after this plan lands. Baseline before plan = 0 (verified). The 2 new commit sites: Protected-path step 7 (commit on sync branch) and Direct-path commit. No additional `git commit` is introduced elsewhere in the skill. Locks in the "single sync commit logic in one spot, with two paths" invariant.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Worktree setup + plan scaffold | ⬚ | | Branch + frontmatter + plan parses |
| 2 — Bootstrap detector for empty issues_dir | ⬚ | | #231 root site fix; covers both Sync paths |
| 3 — `main_protected` worktree routing in Sync step 5 | ⬚ | | #233 root site fix; authors step-5 bash from scratch |
| 4 — Edge cases: zero-issues, untracked-aware diff, stash discipline, rc surfacing | ⬚ | | Hardening |
| 5 — Final version verification, conformance, run-all | ⬚ | | Verify (not re-bump) + full test pass |

## Design & Constraints (plan-wide)

### Bootstrap filename — `ISSUES_PLAN.md`

Bootstrap creates `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md`, the historical canonical name. Reasoning:

- **Sync's own glob** (`skills/fix-issues/SKILL.md:519-525, 542`) explicitly accepts `*ISSUES*.md` OR the literal `ISSUES_PLAN.md`. The literal form is the documented canonical name.
- **Path-migration script** (`skills/update-zskills/scripts/migrate-paths.sh:613`) lists `ISSUES_PLAN.md` first in its canonical issues-filenames array.
- **The dashboard does NOT scan `issues_dir`.** `skills/zskills-dashboard/scripts/zskills_monitor/collect.py` only walks `plans_dir` (`docs/plans/`) at lines 1143-1147 and 1249-1251. The `_ISSUES.md$` regex at line 482 categorizes files under `plans_dir`, never under `issues_dir`. So tracker filename has no effect on dashboard discovery, and the earlier "dashboard regex requires `_ISSUES.md` suffix" rationale was incorrect. (An earlier draft of this plan chose `GENERAL_ISSUES.md` for dashboard-compatibility reasons that turned out to be unfounded; reverted per the adversarial review.)
- **Skill description** (`skills/fix-issues/SKILL.md:31`) already names `ISSUES_PLAN.md` as a recognized discovery filename — no description-update WI needed.

Bootstrap header template (written ONCE, when the bootstrap subroutine fires; subsequent sync runs read the existing file):

```markdown
---
title: Issues — Auto-Bootstrapped Tracker
status: active
created: YYYY-MM-DD
---

# Issues — Auto-Bootstrapped Tracker

Created by `/fix-issues sync` on YYYY-MM-DD because this repo had no tracker files in `$ZSKILLS_ISSUES_DIR/` when sync ran. Split into domain-specific `*_ISSUES.md` files as patterns emerge — sync's glob picks them all up.

## Open Issues

(rows added by sync step 5; one row per open GH issue not yet researched)
```

Date in `America/New_York` per `.claude/zskills-config.json:timezone`.

Row format for the issue-rows-added-in-step-5 (sync step 4 writes these into the tracker, format mirrored from existing trackers in the wild):

```markdown
### #NNN — <issue title>

**Labels:** <comma-separated labels from `gh issue view`>
**Verdict:** NOT YET RESEARCHED

(research blurb added by step-6 research-agent dispatch)
```

This template makes the no-blurb case visible (`grep -B1 'NOT YET RESEARCHED'` lists every issue still awaiting research).

### `main_protected` routing — when and how

**Conditional on net-diff** (not unconditional). Sync runs are frequently no-ops (no new issues, no closures, no annotations, no bootstrap needed). Creating a worktree + opening a PR on every protected-main sync would produce constant noise PRs.

**Net-diff detector** (run after step 4 edits, before step 5 commit). Must detect both tracked-file modifications AND untracked new files (the bootstrapped file is untracked at this point):

```bash
SYNC_PATHS=("$ZSKILLS_ISSUES_DIR" "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
NET_DIFF=$(git status --porcelain -- "${SYNC_PATHS[@]}" 2>/dev/null)
if [ -z "$NET_DIFF" ]; then
  echo "Sync complete. No tracker changes."
  exit 0  # within the sync flow, before step 5
fi
```

`git status --porcelain` covers `??` (untracked), `M ` (modified), `A ` (added), etc. — the bootstrap file shows as `??` and triggers the non-empty branch correctly. This obsoletes the earlier draft's `BOOTSTRAPPED` shell-variable approach (which would not persist across separate Bash tool invocations and depended on an ad-hoc flag).

**Routing decision** (after net-diff confirms there IS a change):

```bash
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." 2>/dev/null && pwd)}"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
MAIN_PROTECTED=0
CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_CONTENT=$(cat "$CONFIG_FILE")
  if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
    MAIN_PROTECTED=1
  fi
fi
ON_PROTECTED_BRANCH=0
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  ON_PROTECTED_BRANCH=1
fi
```

Both `main` and `master` are checked — `hooks/block-unsafe-project.sh.template:259` accepts either, and a repo with `master` as default branch and `main_protected: true` is a real (if rare) configuration. `$PROJECT_ROOT` is resolved with an explicit fallback to `git rev-parse --git-common-dir`, since the variable is not exported anywhere in `skills/fix-issues/SKILL.md` today; the existing consumers at lines 99/111 rely on harness env, and the new sync code must not silently fall back to "/" or empty on a fresh shell.

If `MAIN_PROTECTED == 1 && ON_PROTECTED_BRANCH == 1`: go to **Protected path**. Else: **Direct path**.

### Protected path — worktree + `/land-pr` + deferred close

Spec for step 5 under protection:

1. **Pre-flight stash check.** A stale stash from a previously-crashed protected sync would silently lose data on the next sync. Mirror the `pre-cherry-pick` discipline at `skills/fix-issues/SKILL.md:491-495`. Anchor the regex precisely so it doesn't false-positive on a user-authored stash message that happens to contain the literal phrase:
   ```bash
   if git stash list | grep -qE 'On [^:]+: pre-sync-worktree-[0-9]+$'; then
     echo "ERROR: leftover 'pre-sync-worktree-<ts>' stash from a prior sync. Resolve: git stash list; git stash pop <id> OR git stash drop <id>" >&2
     exit 1
   fi
   ```
2. **Path-scoped stash** (NOT blanket `-u`). The user may have unrelated edits in `src/`, `docs/`, etc. — those must stay on main, not get swept into the sync worktree (CLAUDE.md "NEVER revert, discard, or 'clean up' changes you didn't make"). `git stash push -u` supports a pathspec and captures untracked files within that pathspec by itself — do NOT `git add -N` first (empirically: `add -N` followed by path-scoped `stash push -u` errors with `Entry not uptodate. Cannot merge.` and creates no stash):
   ```bash
   STASH_TS="$(date +%s)"
   git stash push -u -m "pre-sync-worktree-$STASH_TS" -- \
     "$ZSKILLS_ISSUES_DIR/" "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" \
     || { echo "ERROR: stash push failed" >&2; exit 1; }
   ```
   Verified empirically: with the bootstrapped `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` left untracked (no `add -N`), `git stash push -u -- "$ZSKILLS_ISSUES_DIR/"` captures it, removes from working tree, and restores on pop intact. The earlier draft's `add -N` step turned out to break the stash; removed.
3. **Worktree path stable, branch name timestamped.** The path must match what `create-worktree.sh` actually returns. Script logic at `skills/create-worktree/scripts/create-worktree.sh:191-207`: with NO `--prefix`, the path is `${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}` = `/tmp/${PROJECT_NAME}-sync` (when slug is literally `sync`). With `--prefix sync` AND slug `sync`, the path would be `/tmp/${PROJECT_NAME}-sync-sync` — wrong for our resume check. So we omit `--prefix` and pass slug `sync` only:
   ```bash
   PROJECT_NAME=$(basename "$PROJECT_ROOT")
   SYNC_TS="$(TZ=America/New_York date +%Y%m%d-%H%M%S)"
   SYNC_BRANCH="sync/$SYNC_TS"
   WT_PATH="/tmp/${PROJECT_NAME}-sync"
   PIPELINE_ID="fix-issues.sync.$SYNC_TS"
   ```
   On worktree resume (WT_PATH already exists): `cd "$WT_PATH"` and continue. On fresh: dispatch create-worktree.sh.
4. **`create-worktree.sh` invocation + rc handling.** Capture rc via `|| RC=$?` (errexit-neutral, no `set +e`/`set -e` pair needed):
   ```bash
   if [ -d "$WT_PATH" ]; then
     echo "Resuming existing sync worktree at $WT_PATH"
     cd "$WT_PATH"
   else
     RC=0
     RESULT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
       --branch-name "$SYNC_BRANCH" \
       --pipeline-id "$PIPELINE_ID" \
       --purpose "fix-issues sync" \
       "sync") || RC=$?
     case "$RC" in
       0)  WT_PATH="$RESULT"; cd "$WT_PATH" ;;
       2)  echo "ERROR: worktree path collision (rc=2). Inspect: ls -la /tmp/${PROJECT_NAME}-sync*" >&2; exit 2 ;;
       6)  echo "ERROR: fetch failed (rc=6). Re-run sync after network recovers." >&2; exit 6 ;;
       7)  echo "ERROR: local main has diverged from origin/main (rc=7). Pull or reset before re-running sync." >&2; exit 7 ;;
       10) echo "ERROR: local main is ahead of origin/main (rc=10). Resolve divergence (push or reset) and re-run sync." >&2; exit 10 ;;
       *)  echo "ERROR: create-worktree failed (rc=$RC). See stderr above." >&2; exit "$RC" ;;
     esac
   fi
   ```
   Each rc has a distinct diagnostic prefixed with `rc=N)` for greppable uniformity. No silent swallowing (memory: `feedback_or_true_pattern`).
5. **Pop stash inside the worktree.** Stashes are repo-shared so the entry is visible from any worktree of the same repo. Split missing-entry vs conflict so diagnostics don't mislead:
   ```bash
   STASH_REF=$(git stash list | grep "pre-sync-worktree-$STASH_TS" | head -1 | cut -d: -f1)
   if [ -z "$STASH_REF" ]; then
     echo "ERROR: pre-sync stash entry 'pre-sync-worktree-$STASH_TS' not found. Inspect: git stash list" >&2
     # Worktree was created but nothing to pop — clean up so the user isn't stuck with a dangling worktree.
     cd "$PROJECT_ROOT"
     git worktree remove --force "$WT_PATH" 2>/dev/null || echo "Note: worktree $WT_PATH could not be auto-removed; remove manually." >&2
     exit 1
   fi
   if ! git stash pop "$STASH_REF"; then
     echo "ERROR: stash pop conflicted in worktree (merge conflict). Inspect: cd $WT_PATH; git status; git stash list" >&2
     echo "Recovery: resolve conflicts in $WT_PATH then 'git stash drop $STASH_REF'; OR abandon: cd $PROJECT_ROOT; git worktree remove --force $WT_PATH; git stash pop $STASH_REF (re-apply on main)" >&2
     exit 1
   fi
   ```
6. **Stage explicit paths** (CLAUDE.md "When staging files, prefer adding specific files by name"):
   ```bash
   git add -- "$ZSKILLS_ISSUES_DIR/" "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" 2>/dev/null || true
   # tolerate SPRINT_REPORT.md not existing in a brand-new repo
   STAGED=$(git diff --cached --name-only)
   if [ -z "$STAGED" ]; then
     echo "Sync complete. No tracker changes after stash pop." >&2
     # Recover: pop unstashed nothing, no work to land, exit clean.
     cd "$PROJECT_ROOT"
     exit 0
   fi
   ```
7. **Commit on the sync branch** (no main-on-branch hook fire — worktree HEAD is `sync/$SYNC_TS`):
   ```bash
   git commit -m "sync: update trackers + research blurbs ($SYNC_TS)"
   ```
8. **Dispatch `/land-pr` via the Skill tool.** Reuse the canonical caller pattern in `skills/fix-issues/modes/pr.md:72-160` (same-skill reference, not `quickfix`). Sync uses a **single-shot dispatch (no fix-cycle)** — tracker edits are deterministic and have no CI gates that could fail recoverably. Strip the `while :; do … case STATUS in conflict|pr-ci-failing) …` retry scaffold from the cloned pattern.

   **Pass `--no-monitor`** so `/land-pr` returns immediately after PR creation without waiting on CI. The default `--ci-timeout 600` would block sync for up to 10 minutes per `skills/land-pr/SKILL.md:47` — directly contradicting the "single-shot" framing. With `--no-monitor`, `/land-pr` returns `STATUS=created CI_STATUS=not-monitored` (per `skills/land-pr/SKILL.md:316,325-326`); the user reviews the PR (which sync's interactive mode already requires) and either approves the merge or asks sync to re-run. CI status is not sync's concern — sync's payload is content-only edits with no CI gates that could recoverably fail.

   **PR-body construction.** Use a quoted heredoc (`<<'EOF'`) for the literal template, then `printf` to substitute computed variables — prevents command injection from any future title text and keeps `$VAR` references in the static template unexpanded:
   ```bash
   RESULT_FILE=$(mktemp)
   BODY_FILE=$(mktemp)
   PR_DATE=$(TZ=America/New_York date +%F)
   PR_TS=$(TZ=America/New_York date -Iseconds)
   # APPROVED_LIST_RENDERED: space-separated bare numbers joined by ', ' for the body line,
   # or "(none)" if APPROVED_LIST array is empty. See "Variable derivation" below.
   if [ "${#APPROVED_LIST[@]}" -eq 0 ]; then
     APPROVED_LIST_RENDERED="(none)"
   else
     APPROVED_LIST_RENDERED=$(printf '#%s, ' "${APPROVED_LIST[@]}")
     APPROVED_LIST_RENDERED="${APPROVED_LIST_RENDERED%, }"
   fi
   {
     printf '## Summary\n'
     printf '`/fix-issues sync` on %s updated tracker files.\n\n' "$PR_DATE"
     printf -- '- Bootstrapped tracker: %s\n' "$BOOTSTRAP_NEW"
     printf -- '- New issues researched: %s\n' "$NEW_RESEARCHED_COUNT"
     printf -- '- Issues approved for close (will close after PR merge via API): %s — %s\n\n' "$APPROVED_CLOSE_COUNT" "$APPROVED_LIST_RENDERED"
     printf '## Test plan\n'
     printf -- '- [x] Tracker diff reviewed (single-shot dispatch, no CI gates for content edits)\n\n'
     printf '🤖 Generated by `/fix-issues sync` at %s\n' "$PR_TS"
   } > "$BODY_FILE"
   PR_TITLE="sync: trackers $PR_DATE"
   LAND_ARGS="--branch=$SYNC_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sync --worktree-path=$WT_PATH --no-monitor"
   # Dispatch:
   # Skill { skill: "land-pr", args: "$LAND_ARGS" }
   ```
   Note: the body intentionally does NOT include `Closes #N` lines — sync closes those issues itself via `gh issue close` in step 10 of this recipe, AFTER `/land-pr` returns success. Including `Closes #N` would cause GitHub to re-process the close at merge time, redundantly (and noisily in the audit log).
   No `--auto` is passed: sync is always interactive (`skills/fix-issues/SKILL.md:42-43`). The user reviews the PR before merging. Variables `BOOTSTRAP_NEW`, `NEW_RESEARCHED_COUNT`, `APPROVED_CLOSE_COUNT`, `APPROVED_LIST` are computed inline during steps 3-4 from the user's approval set and sync's bookkeeping.
9. **Parse result with allow-list:**
   ```bash
   LAND_STATUS=""; LAND_PR_URL=""; LAND_PR_NUMBER=""; LAND_REASON=""
   while IFS='=' read -r KEY VALUE; do
     case "$KEY" in
       STATUS) LAND_STATUS="$VALUE" ;;
       PR_URL) LAND_PR_URL="$VALUE" ;;
       PR_NUMBER) LAND_PR_NUMBER="$VALUE" ;;
       REASON) LAND_REASON="$VALUE" ;;
     esac
   done < "$RESULT_FILE"
   ```
   `STATUS=merged` is included in the case branch because GitHub repo-level auto-merge (if enabled by the user outside sync) can mark the PR merged before the result file is written; the parser tolerates it without treating it as an error.
10. **Step 4b — deferred GH issue close.** Only after `/land-pr` returns a success status do we close GitHub issues that step 3 user-approved. Iterate `APPROVED_LIST` as a bash array (avoids word-splitting on `$IFS`). The success-status set per `skills/land-pr/SKILL.md:158,316,366,394` is `{created, monitored, merged}`: `created` is what we get with `--no-monitor` (our case); `monitored` is the CI-pass-no-auto case; `merged` is the auto-merged case. Match the canonical caller pattern at `skills/fix-issues/modes/pr.md:150` which uses `created|monitored|merged`:
    ```bash
    case "$LAND_STATUS" in
      created|monitored|merged)
        echo "PR landed at $LAND_PR_URL"
        # NOW close the approved issues — state-divergence safe.
        for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
          gh issue close "$ISSUE_NUM" --comment "Fixed; tracker updated in $LAND_PR_URL."
        done
        ;;
      *)
        echo "/land-pr did not land: STATUS=$LAND_STATUS, REASON=$LAND_REASON" >&2
        echo "GH issues NOT closed (avoiding state divergence). Re-run sync after resolving." >&2
        exit 1
        ;;
    esac
    ```
    Closes deferred to AFTER successful landing means a `/land-pr` failure leaves GitHub state and tracker state both unchanged from before sync — no divergence to recover (verified design decision against the alternative of "close before land," which would leave GH closed but tracker unmerged on failure).
11. **Cleanup** — write `.landed` marker in worktree (CLAUDE.md "ALWAYS write a `.landed` marker"). The heredoc terminator MUST be at column 0 (no leading whitespace) when this block is inserted into `skills/fix-issues/SKILL.md`:
    ```bash
    cat > "$WT_PATH/.landed" <<MARKER
    status: full
    date: $(TZ=America/New_York date -Iseconds)
    source: fix-issues-sync
    pr: $LAND_PR_URL
    MARKER
    ```

### Variable derivation (sync runtime state)

The Protected and Direct paths reference variables computed during sync's earlier steps. Source each from filesystem or step-3 user-approval state — never from a shell flag that won't persist across Bash tool invocations:

- **`BOOTSTRAP_NEW`** — `yes` if the bootstrap wrote a new `ISSUES_PLAN.md` this run, `no` otherwise. Derive from filesystem:
  ```bash
  if git status --porcelain -- "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" | grep -q '^??'; then
    BOOTSTRAP_NEW=yes
  else
    BOOTSTRAP_NEW=no
  fi
  ```
- **`APPROVED_LIST`** — bash array of bare integer issue numbers (no `#` prefix) the user approved at step 3. The orchestrator (Claude Code, executing sync's prose) captures the user's literal step-3 response into `$USER_RESPONSE` before evaluating the case-block — sync's SKILL.md is orchestrator-execution prose, not a script, so the variable enters the bash context the same way other interactive inputs do today (e.g., the existing step-3 approval flow at lines 261-264 of SKILL.md). Then the parser populates the array:
  ```bash
  # From user response "231,233" or "all" or "none":
  APPROVED_LIST=()
  case "$USER_RESPONSE" in
    none) ;;
    all)  for N in "${ALL_FIXED_NUMS[@]}"; do APPROVED_LIST+=("$N"); done ;;
    *)    IFS=',' read -r -a APPROVED_LIST <<< "${USER_RESPONSE// /}" ;;
  esac
  ```
- **`APPROVED_CLOSE_COUNT`** — `APPROVED_CLOSE_COUNT=${#APPROVED_LIST[@]}`.
- **`NEW_RESEARCHED_COUNT`** — count of new tracker entries written by step 4's row-writer. Either incremented inside the row-writer loop, or computed post-hoc from `grep -c '^### #' "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md` minus the pre-sync count (capture both before/after).
- **`OPEN_NUMS`** — bash array of all currently-open GH issue numbers. Derive from `$GH_OUT` (the cached `gh issue list --json number` result):
  ```bash
  mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
  OPEN_COUNT=${#OPEN_NUMS[@]}
  ```
  This replaces the earlier draft's `grep -cE '"number"'`, which counts LINES (always 1 for single-line JSON) rather than matches. `grep -oE` emits one match per line, then `wc -l` / `mapfile` count correctly.

### Direct path — author the legacy semantics

Step 5 is **prose-only** in today's SKILL.md (lines 280-295: "**Commit** updated tracker files."). There is no pre-existing bash block. Both the Direct path and the Protected path are authored fresh by this plan. The Direct path implements the documented step-5 behavior literally:

```bash
git add -- "$ZSKILLS_ISSUES_DIR/" "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" 2>/dev/null || true
STAGED=$(git diff --cached --name-only)
if [ -z "$STAGED" ]; then
  echo "Sync complete. No tracker changes."
  exit 0
fi
# Gate close loop on commit success — mirror Protected-path divergence-safety.
if ! git commit -m "sync: update trackers + research blurbs"; then
  echo "ERROR: git commit failed in Direct path; not closing GH issues to avoid state divergence." >&2
  exit 1
fi
# Direct path closes happen here, as today (array iteration; not $IFS-split)
for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
  gh issue close "$ISSUE_NUM" --comment "Fixed; tracker updated."
done
```

### `/land-pr` dispatch contract — caller-list note

`/fix-issues sync` is NOT a new conformance-locked `/land-pr` caller. The conformance fingerprint at `tests/test-skill-conformance.sh:518-531` lists five files (`skills/run-plan/modes/pr.md`, `skills/commit/modes/pr.md`, `skills/do/modes/pr.md`, `skills/fix-issues/modes/pr.md`, `skills/quickfix/SKILL.md`) and asserts each contains the substring `land-pr`. The new sync dispatch lives in `skills/fix-issues/SKILL.md` — a different file from `modes/pr.md` — and adds a `land-pr` reference there, which neither breaks the substring check on the five tracked files (the five files are unaffected) nor adds a new entry to the tracked list. Verified at `tests/test-skill-conformance.sh:526-531`.

### `gh issue list` failure handling

Throughout the new code, treat `gh issue list` non-zero exit as a hard error, NOT as "zero issues." A network failure or auth lapse must NOT silently skip the bootstrap or the gap detection:

```bash
GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1)
if [ "$?" -ne 0 ]; then
  echo "ERROR: 'gh issue list' failed:" >&2
  echo "$GH_OUT" >&2
  exit 1
fi
# Then count from GH_OUT, not from a fresh invocation.
```

### Skill versioning workflow (per phase, NOT a "final supersede")

Each phase that edits `skills/fix-issues/SKILL.md` ends with its own version bump and commit. The PreToolUse hook `block-stale-skill-version.sh` enforces this at every commit; there is no way to defer the bump to a final phase. Phase 5 is a *verification* step (the version on the final commit already reflects the final content hash; Phase 5 confirms it), not a re-bump:

```bash
# Per phase that edits SKILL.md:
HASH=$(bash scripts/skill-content-hash.sh skills/fix-issues)
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
bash scripts/frontmatter-set.sh skills/fix-issues/SKILL.md metadata.version "$TODAY+$HASH"
bash scripts/mirror-skill.sh fix-issues
git add skills/fix-issues/SKILL.md .claude/skills/fix-issues/SKILL.md
git commit -m "..."
```

### Bootstrap fires regardless of caller — Phase 1a is shared

The bootstrap subroutine lives in Phase 1a Sync (lines ~538-548 region). Phase 1a is shared between standalone sync (`/fix-issues sync` step 1 delegates to Phase 1a) and sprint mode (`/fix-issues N`). Both flows now trigger bootstrap when issues_dir is empty.

In **sprint mode**, the bootstrap file is written to the main repo working tree at Phase 1a (before sprint creates per-issue worktrees). Sprint's later cherry-pick / PR-mode phases pick it up via the same `git status --porcelain` enumeration this plan uses for the net-diff check — so the bootstrap file rides along with whatever the sprint commits. Under `main_protected: true` in sprint mode, sprint's per-issue worktree+PR landing model is already worktree-routed, so the bootstrap file lands as part of a per-issue PR. No new commit path needed in sprint mode for the bootstrap.

In **standalone sync** (and in sprint-mode's "auto-sync before giving up" re-entry at `skills/fix-issues/SKILL.md:685-693`), the step-5 fix in Phase 3 of this plan covers both the bootstrap file and the tracker mods. Sprint-mode auto-sync re-entry IS covered — the implementing agent must NOT short-circuit Phase 3's routing based on "we are inside sprint mode."

### Hard constraints

- Do NOT call `gh pr create` or `gh pr merge --auto` directly (CLAUDE.md "Git Rules"). Dispatch `/land-pr`.
- Do NOT add a `jq` invocation to `skills/fix-issues/SKILL.md`. Use BASH_REMATCH on raw config JSON, matching the existing pattern at lines 101-105. (`gh issue list ... -q 'EXPR'` is a `gh` CLI flag, not a `jq` invocation; existing precedent at line 523 — the new code inherits this precedent, not extends it.)
- Do NOT bypass hooks with `--no-verify` (CLAUDE.md "Git Rules").
- Do NOT extend `main_protected` to landing modes other than sync — `direct` mode is already gated at lines 109-119.
- Do NOT extend the `block-direct-main-commit` hook tokenizer — Layer-1 carve-outs are accepted (CLAUDE.md / #225).
- `metadata.version` bump on each `skills/fix-issues/SKILL.md` edit is mandatory.

### What this plan does NOT do

- Does not refactor sync's argument parsing or research-agent dispatch logic.
- Does not change sprint-mode (`/fix-issues N`) per-issue commit semantics; that already routes through worktrees in Phase 3 onward.
- Does not add a `--auto` arg to sync (`skills/fix-issues/SKILL.md:42-43` — closing issues on GitHub requires human approval).
- Does not modify Phase 1a Sync's COMMIT semantics — Phase 1a doesn't commit on its own (only step 5 does). Phase 2's edits to Phase 1a are scope-limited to gap-detection / bootstrap-write prose, not commit-flow changes.

---

## Phase 1 — Worktree setup + plan scaffold

### Goal

Establish the feature branch worktree this plan runs in and ensure `/run-plan` can parse the plan file. Bookkeeping-only; no behavior changes to `skills/fix-issues/SKILL.md`.

### Work Items

- [ ] WI 1.1 — Confirm the worktree at `/tmp/zskills-draftplan-fix-issues-sync-hardening` (or its rename) exists, the branch is `draftplan-fix-issues-sync-hardening` (or whatever the orchestrator agreed with the user), and it's pushed to `origin`.
- [ ] WI 1.2 — Confirm `docs/plans/FIX_ISSUES_SYNC_HARDENING.md` parses cleanly: frontmatter has `issues: [231, 233]`, `status: active`, Landing-mode blockquote is `PR`, phase headings use em-dash.
- [ ] WI 1.3 — Initial commit of the plan file on the feature branch (if not already committed).

### Design & Constraints

No `skills/fix-issues/SKILL.md` edits in this phase → no `metadata.version` bump.

### Acceptance Criteria

- [ ] AC-1.1 — `git rev-parse --abbrev-ref HEAD` returns the plan's feature branch name (not `main`/`master`).
- [ ] AC-1.2 — `head -10 docs/plans/FIX_ISSUES_SYNC_HARDENING.md | grep -E '^issues:'` returns a line with `[231, 233]`.
- [ ] AC-1.3 — `grep -nE '^## Phase [0-9]+ — ' docs/plans/FIX_ISSUES_SYNC_HARDENING.md` returns ≥5 phase headings with em-dash separator.
- [ ] AC-1.4 — `git log -1 --pretty=%s` includes the plan filename or a clear reference to it.

### Dependencies

None.

---

## Phase 2 — Bootstrap detector for empty `$ZSKILLS_ISSUES_DIR/`

### Goal

Close #231: when sync scans `$ZSKILLS_ISSUES_DIR/` and finds zero tracker files, bootstrap a `ISSUES_PLAN.md` file with the header template specified in plan-wide Design & Constraints. Cover the shared Phase 1a code path (which both Standalone Sync and Sprint Phase 1a call).

### Work Items

- [ ] WI 2.1 — In `skills/fix-issues/SKILL.md` Phase 1a Sync, immediately before the gap-detection block at line 519-529, fetch the open-issue list AND count safely (single `gh` call, parsed for both count and number array). `grep -cE` over single-line JSON would return 0-or-1 (line count) — use `grep -oE | wc -l` for the actual match count, and `mapfile` for the number array:
  ```bash
  GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1)
  if [ "$?" -ne 0 ]; then
    echo "ERROR: 'gh issue list' failed:" >&2
    echo "$GH_OUT" >&2
    exit 1
  fi
  mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
  OPEN_COUNT=${#OPEN_NUMS[@]}
  ```
- [ ] WI 2.2 — Add the bootstrap subroutine before the existing `ls "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md ...` at line 521. **The heredoc body must be inserted at column-0 indentation** when written into `skills/fix-issues/SKILL.md` — bash `<<TRACKER` (no `-` suffix) does not strip leading whitespace, and YAML frontmatter must start at column 0 to be parsed:
  ```bash
  mkdir -p "$ZSKILLS_ISSUES_DIR"
  EXISTING_TRACKERS=$(ls "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null | head -1)
  if [ -z "$EXISTING_TRACKERS" ]; then
    if [ "$OPEN_COUNT" -eq 0 ]; then
      echo "Sync complete. 0 open issues, no trackers needed."
      exit 0
    fi
    TODAY=$(TZ=America/New_York date +%Y-%m-%d)
    cat > "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" <<TRACKER
---
title: Issues — Auto-Bootstrapped Tracker
status: active
created: $TODAY
---

# Issues — Auto-Bootstrapped Tracker

Created by \`/fix-issues sync\` on $TODAY because this repo had no tracker files in \`\$ZSKILLS_ISSUES_DIR/\` when sync ran. Split into domain-specific \`*_ISSUES.md\` files as patterns emerge — sync's glob picks them all up.

## Open Issues

(rows added by sync step 5 below)
TRACKER
    echo "Bootstrapped $ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
  fi
  ```
  (The heredoc body in this plan-spec block is shown dedented to column 0 to match how it must appear in SKILL.md. The surrounding `if` / `cat` lines retain their 2-space bash-block indent.)
- [ ] WI 2.3 — Update the prose at `skills/fix-issues/SKILL.md:558-561` to reflect that the structural cause of "Phase 2 prioritizes from bare titles" is closed; the self-warning may stay as historical context, but add: "Empty `issues_dir` now triggers bootstrap; this failure mode is structurally prevented." (Prose-only edit, no behavior change.)
- [ ] WI 2.4 — Add an issue-row writer that runs in step 5 BEFORE the commit-routing decision: for each open GH issue not yet in any tracker, append the row template. Iterate `OPEN_NUMS` (the array populated by WI 2.1); for each `N`, `grep -q "#$N\b"` across existing `$ZSKILLS_ISSUES_DIR/*_ISSUES.md $ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` to skip already-tracked issues; for the residual, fetch title+labels via `gh issue view "$N" --json title,labels`, parse via `grep -oE` (no jq), and append to `ISSUES_PLAN.md` (or the appropriate `*_ISSUES.md` if one exists for the issue's domain — keep the existing "appropriate tracker" prose). Row template (column-0):
  ```markdown
  ### #NNN — <issue title>

  **Labels:** <comma-separated labels>
  **Verdict:** NOT YET RESEARCHED

  ```
- [ ] WI 2.5 — Add a cross-reference comment in the Standalone Sync section (lines 183-295) pointing to Phase 1a's bootstrap path: `<!-- Bootstrap of empty $ZSKILLS_ISSUES_DIR/ happens in Phase 1a Sync; Standalone Sync inherits it via step 1's "Run Phase 1a" delegation. -->`
- [ ] WI 2.6 — Skill-version bump + mirror (per the per-phase versioning workflow in plan-wide Design & Constraints).

### Design & Constraints

Bootstrap fires unconditionally when issues_dir has zero trackers AND `OPEN_COUNT > 0`. If `OPEN_COUNT == 0`, sync exits early with a clean message — no empty tracker, no PR, no noise.

The bootstrap subroutine creates `$ZSKILLS_ISSUES_DIR` directory if missing (handles the "issues_dir doesn't exist at all" edge case).

Filename is `ISSUES_PLAN.md`, NOT `GENERAL_ISSUES.md`. See plan-wide Design & Constraints for the dashboard-non-issue rationale.

### Acceptance Criteria

- [ ] AC-2.1 — `grep -nE 'ISSUES_PLAN\.md' skills/fix-issues/SKILL.md` returns ≥3 hits (existing line 521/525/542 patterns AND the new bootstrap-write site).
- [ ] AC-2.2 — `grep -nB1 -A8 'EXISTING_TRACKERS=' skills/fix-issues/SKILL.md | grep -E 'bootstrap|ISSUES_PLAN\.md'` returns ≥1 hit (the bootstrap branch is anchored to the gap-detection site).
- [ ] AC-2.3 — `grep -nE 'OPEN_COUNT.*-eq 0|0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit (the zero-issue early-exit).
- [ ] AC-2.4 — `grep -nE 'NOT YET RESEARCHED' skills/fix-issues/SKILL.md` returns ≥1 hit (the row template for new entries).
- [ ] AC-2.5 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty (mirror in sync).
- [ ] AC-2.6 — `bash scripts/skill-content-hash.sh skills/fix-issues` output matches the `metadata.version` suffix in `skills/fix-issues/SKILL.md`.
- [ ] AC-2.7 — `grep -nE 'Bootstrap of empty.*ISSUES_DIR|inherits.*bootstrap' skills/fix-issues/SKILL.md` returns ≥1 hit in the Standalone Sync section (the cross-reference WI 2.5).
- [ ] AC-2.8 — `bash tests/test-skill-conformance.sh` exits 0.

### Dependencies

Phase 1.

---

## Phase 3 — `main_protected` worktree routing in Sync step 5

### Goal

Close #233: author step 5's bash block from scratch (currently prose-only at lines 280-295). The block has two paths — Protected and Direct — fully specified in plan-wide Design & Constraints. This phase implements them in `skills/fix-issues/SKILL.md` Standalone Sync.

### Work Items

- [ ] WI 3.1 — In `skills/fix-issues/SKILL.md` between the existing step 4 prose (lines 266-278) and the step 5 heading (line 280), insert the **net-diff detector** specified in plan-wide Design & Constraints (uses `git status --porcelain`, NOT `git diff --quiet`).
- [ ] WI 3.2 — Insert the **routing decision** block (PROJECT_ROOT resolution, MAIN_PROTECTED detection, ON_PROTECTED_BRANCH check on both `main` and `master`).
- [ ] WI 3.3 — Author the **Protected path** bash block in step 5, full specification per plan-wide Design & Constraints:
  1. pre-flight stash check for stale `pre-sync-worktree-<ts>` (anchored regex)
  2. path-scoped `git stash push -u -m ... -- <sync-paths>` (NO `git add -N` — empirically breaks the stash; `-u` alone captures matching untracked files)
  3. compute stable WT_PATH (slug `sync`, no `--prefix` — script returns `/tmp/${PROJECT_NAME}-sync`) + timestamped SYNC_BRANCH
  4. dispatch create-worktree.sh with rc handling (0, 2, 6, 7, 10, default)
  5. stash pop in worktree
  6. explicit pathspec `git add`
  7. commit on sync branch
  8. dispatch `/land-pr` via Skill tool (single-shot, no fix-cycle)
  9. allow-listed result parsing
  10. **deferred** `gh issue close` only on STATUS=created|merged
  11. `.landed` marker write
- [ ] WI 3.4 — Author the **Direct path** bash block (the else branch) per plan-wide Design & Constraints — explicit `git add` pathspec, commit, immediate `gh issue close` (no defer needed — no separation between commit and close in this path).
- [ ] WI 3.5 — Update the step-5 report block to surface either `LAND_PR_URL` (Protected path) or commit hash (Direct path).
- [ ] WI 3.6 — Skill-version bump + mirror.

### Design & Constraints

All concrete logic is specified in plan-wide Design & Constraints sections "Protected path" and "Direct path." This phase's job is to insert that logic into `skills/fix-issues/SKILL.md` at the right lines, with no design decisions deferred.

The single sync commit site remains step 5 — locked in by AC-P.11 (grep-count invariant).

`/fix-issues sync` is not a new conformance-locked `/land-pr` caller; the cross-skill conformance check at `tests/test-skill-conformance.sh:518-531` uses substring matching on five specific files and is unaffected by adding a `land-pr` reference inside `skills/fix-issues/SKILL.md` (a different file from the listed `skills/fix-issues/modes/pr.md`).

### Acceptance Criteria

- [ ] AC-3.1 — `grep -nE 'git status --porcelain -- "\$\{?SYNC_PATHS' skills/fix-issues/SKILL.md` returns ≥1 hit (net-diff detector uses status --porcelain, not diff --quiet).
- [ ] AC-3.2 — `grep -nE 'CURRENT_BRANCH.*==.*main.*\|\|.*CURRENT_BRANCH.*==.*master|ON_PROTECTED_BRANCH' skills/fix-issues/SKILL.md` returns ≥1 hit (both default-branch names handled).
- [ ] AC-3.3 — `grep -nE 'PROJECT_ROOT:-.*git-common-dir|git rev-parse --git-common-dir' skills/fix-issues/SKILL.md` returns ≥1 hit in the Standalone Sync section (PROJECT_ROOT has an explicit fallback).
- [ ] AC-3.4 — `grep -nE 'create-worktree\.sh' skills/fix-issues/SKILL.md` returns ≥1 hit in the Standalone Sync section AND the dispatch does NOT pass `--prefix sync` (so the returned path is `/tmp/${PROJECT_NAME}-sync`, matching `WT_PATH`). Verify: `grep -nA10 'create-worktree\.sh' skills/fix-issues/SKILL.md | grep -E 'Standalone Sync|sync' | head` shows the dispatch in context, and `grep -nE 'create-worktree\.sh.*--prefix sync' skills/fix-issues/SKILL.md` returns 0 hits.
- [ ] AC-3.5 — `grep -cE 'land-pr|/land-pr' skills/fix-issues/SKILL.md` returns ≥2 (baseline = 0; the new Standalone Sync block adds at least 2 references — the dispatch comment and the LAND_ARGS construction). Sprint-mode caller pattern at `skills/fix-issues/modes/pr.md` is a different file, unaffected.
- [ ] AC-3.6 — `grep -cE 'gh pr create|gh pr merge --auto' skills/fix-issues/SKILL.md` returns 0 (no direct dispatch).
- [ ] AC-3.7 — `grep -nE 'pre-sync-worktree-' skills/fix-issues/SKILL.md` returns ≥2 hits (pre-flight check AND the new stash creation).
- [ ] AC-3.8 — `grep -nE 'case "\$LAND_STATUS" in|created\|monitored\|merged\)' skills/fix-issues/SKILL.md` returns ≥1 hit (deferred-close branch matches the canonical /land-pr success-status set, including `monitored`). `grep -nE '--no-monitor' skills/fix-issues/SKILL.md` returns ≥1 hit (sync passes --no-monitor for snap-back single-shot dispatch).
- [ ] AC-3.9 — `grep -nB3 -A2 'gh issue close' skills/fix-issues/SKILL.md | grep -E 'LAND_STATUS|case .*created\|merged|after.*land'` returns ≥1 hit (`gh issue close` in the Protected path is documented as deferred).
- [ ] AC-3.10 — `grep -nE 'rc=10|ahead of origin/main' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-3.11 — `grep -nE '"\$\{APPROVED_LIST\[@\]\}"' skills/fix-issues/SKILL.md` returns ≥2 hits (APPROVED_LIST iterated as a bash array, not unquoted-word-split, in both Protected and Direct paths).
- [ ] AC-3.12 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-3.13 — `bash scripts/skill-content-hash.sh skills/fix-issues` matches the staged version suffix.
- [ ] AC-3.14 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-3.15 — Single sync commit site invariant: `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2 (baseline = 0; one in Protected path step 7, one in Direct path). Spec at AC-P.11.

### Dependencies

Phase 2 (bootstrap path must exist before the worktree path can carry the bootstrapped file through to the PR).

---

## Phase 4 — Edge cases: zero-issues, untracked-aware diff, stash discipline, rc surfacing, gh-failure surfacing

### Goal

Verify and harden the edge cases the design surfaces. Most of this is AC-only verification of Phases 2-3; new code is minimal (stash pop conflict abort, additional rc cases beyond `0/2/6/7/10`).

### Work Items

- [ ] WI 4.1 — Verify and add ACs for **zero open GH issues + empty issues_dir** → exits before bootstrap with `Sync complete. 0 open issues, no trackers needed.`
- [ ] WI 4.2 — Verify and add ACs for **zero net diff after step 4** → exits before worktree creation with `Sync complete. No tracker changes.`
- [ ] WI 4.3 — Verify and add ACs for **worktree resume** — stable `WT_PATH=/tmp/${PROJECT_NAME}-sync` (matches create-worktree.sh's `${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}` with slug=`sync` and no `--prefix`); if `[ -d "$WT_PATH" ]`, reuse without re-running create-worktree.sh.
- [ ] WI 4.4 — Verify and add ACs for **create-worktree.sh rc handling** (each of 0, 2, 6, 7, 10, default has a distinct branch with its own error message).
- [ ] WI 4.5 — Add **non-main feature branch** path verification: `ON_PROTECTED_BRANCH=0 && MAIN_PROTECTED=1` falls through to the Direct path (commit on the feature branch — hook doesn't fire). Inline-comment so future readers don't add a redundant guard.
- [ ] WI 4.6 — Verify and add AC for **gh issue list failure handling** — non-zero `gh issue list` exit surfaces stderr verbatim and sync exits non-zero (NOT silent zero-fallback).
- [ ] WI 4.7 — Verify and add AC for **stash discipline**: pre-flight anchored-regex stash check + path-scoped `stash push -u -- <pathspec>` (NO `git add -N`) + post-pop missing-entry-vs-conflict split diagnostics + worktree cleanup on missing-entry failure.
- [ ] WI 4.8 — Verify and add AC for **pre-existing unrelated working-tree edits are unaffected** — paths outside `$ZSKILLS_ISSUES_DIR/` and `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` stay on main (AC-P.10 enforcement).
- [ ] WI 4.9 — Skill-version bump + mirror.

### Design & Constraints

This phase makes minimal new logic edits. Its purpose is to anchor each edge case with at least one verifier-runnable AC so the verifier subagent can confirm the Phase 2-3 implementations cover what the design specifies.

### Acceptance Criteria

- [ ] AC-4.1 — `grep -nE '0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.2 — `grep -nE 'No tracker changes' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.3 — `grep -nE 'Resuming existing sync worktree|if \[ -d "\$WT_PATH"' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.4 — `grep -nE 'case "\$RC" in' skills/fix-issues/SKILL.md` returns ≥1 hit AND each rc error string uses the uniform `rc=N)` format: `grep -cE '\(rc=(2|6|7|10)\)' skills/fix-issues/SKILL.md` returns ≥4 (one per enumerated rc).
- [ ] AC-4.5 — `grep -nB1 -A3 'ON_PROTECTED_BRANCH=0|feature branch.*hook.*not.*fire' skills/fix-issues/SKILL.md | grep -E 'Direct path|hook only fires on main'` returns ≥1 hit (anchored — see R1.12 mitigation).
- [ ] AC-4.6 — `grep -nE 'gh issue list.*failed|GH_OUT=\$\(gh issue list' skills/fix-issues/SKILL.md` returns ≥1 hit (gh failure handling at the bootstrap entry).
- [ ] AC-4.7 — `grep -nE 'git stash push -u -m.*pre-sync-worktree-.*--' skills/fix-issues/SKILL.md` returns ≥1 hit (path-scoped stash). `grep -cE 'git add -N' skills/fix-issues/SKILL.md` returns 0 inside the Standalone Sync block (the `add -N` step was empirically broken and removed). `grep -nE 'stash entry .pre-sync-worktree-.* not found|stash pop conflicted' skills/fix-issues/SKILL.md` returns ≥1 hit (split diagnostics).
- [ ] AC-4.8 — Manual verification (recorded in the commit message): with `git status -s` showing an unrelated edit outside sync paths, running sync's worktree path preserves that edit on main untouched. (Not all ACs need to be grep — this one is documented as a manual recipe in the plan-level Tests section.)
- [ ] AC-4.9 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-4.10 — `bash tests/test-skill-conformance.sh` exits 0.

### Dependencies

Phases 2 and 3.

---

## Phase 5 — Final version verification, conformance, run-all

### Goal

Verify the final state — version is current (each prior phase's commit already bumped its own; this phase confirms the latest commit's version reflects the final content hash), conformance passes, full test suite passes, Progress Tracker is up to date. NOT a new version bump — that would be either a no-op (hash unchanged since Phase 4) or a date-only churn.

### Work Items

- [ ] WI 5.1 — `bash scripts/skill-content-hash.sh skills/fix-issues` and confirm its output matches the `metadata.version` suffix in the current `skills/fix-issues/SKILL.md` (i.e., Phase 4's bump is still correct). If they don't match, find why (was there an edit not followed by a bump?) — but per the PreToolUse hook this should be structurally impossible.
- [ ] WI 5.2 — `bash scripts/mirror-skill.sh fix-issues` (idempotent re-mirror — should be a no-op after Phase 4). `diff -rq skills/fix-issues .claude/skills/fix-issues` empty.
- [ ] WI 5.3 — Full test suite: `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1`. Read results; if any failure, stop and fix at originating phase (no thrash — two attempts max per CLAUDE.md).
- [ ] WI 5.4 — Conformance: `bash tests/test-skill-conformance.sh`. Fail loudly on non-zero.
- [ ] WI 5.5 — Update plan Progress Tracker rows for Phases 1-5 to ✓ with commit refs.
- [ ] WI 5.6 — Plan frontmatter `status: complete` is set by `/run-plan finish` at land time (not by this phase).

### Design & Constraints

Phase 5 makes no SKILL.md edits → no new version bump expected. If the verifier finds `bash scripts/skill-version-stage-check.sh` fails when there are no staged edits, that's a hook misconfiguration, not a plan bug.

If any test failure surfaces in Phase 5, fix at the originating phase. Don't band-aid in Phase 5.

### Acceptance Criteria

- [ ] AC-5.1 — `grep -nE '^  version:' skills/fix-issues/SKILL.md | head -1` shows `version: "20[0-9]{2}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}"`, with date = today (or the most-recent-phase commit date) in `America/New_York`.
- [ ] AC-5.2 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-5.3 — `bash scripts/skill-version-stage-check.sh` exits 0 (no stale-version mismatch when nothing is staged this phase).
- [ ] AC-5.4 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-5.5 — `bash tests/run-all.sh` exits 0; output captured to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`.
- [ ] AC-5.6 — Progress Tracker rows for Phases 1-5 show ✓ with commit refs.

### Dependencies

Phases 1-4 complete.

---

## Plan-level Tests (manual reproduction recipes)

The verifier-runnable ACs above cover the structural assertions. These manual recipes prove the actual behavior change end-to-end and serve as the test plan for the landing PR (AC-P.9a) and any future regression checks.

### Manual repro #231 (bootstrap)

1. In a scratch repo with `$ZSKILLS_ISSUES_DIR/` empty (or nonexistent) and at least one open GH issue:
   ```bash
   rm -rf .zskills/issues
   gh issue create --title "test bootstrap" --body "synthetic"
   /fix-issues sync
   ```
2. Expected (after this plan): `.zskills/issues/ISSUES_PLAN.md` is created with the frontmatter header and at least one `### #NNN — <title>` row; research-agent dispatch runs against the new entries; sync summary reports `K=1 tracker file(s) updated`.
3. Expected (before this plan, control): no file is created; `K=0 trackers updated` is reported silently.

### Manual repro #233 (main_protected)

1. In a repo with `.claude/zskills-config.json` containing `execution.main_protected: true`, on branch `main`, with at least one open GH issue not yet in any tracker:
   ```bash
   git checkout main
   /fix-issues sync
   ```
2. Expected (after this plan): sync detects `MAIN_PROTECTED=1 && ON_PROTECTED_BRANCH=1`, runs the net-diff check (non-empty due to bootstrap or tracker mods), pre-flight-checks stash, path-scoped stashes tracker dir + sprint report, creates worktree at `/tmp/<proj>-sync/` on branch `sync/YYYYMMDD-HHMMSS`, pops stash there, commits, dispatches `/land-pr` interactively, parses STATUS=created from result file, defers `gh issue close` until that confirmation. Reports the PR URL in the summary.
3. Expected (before this plan, control): sync attempts `git commit` on main, the `block-direct-main-commit` hook denies it, sync exits with the hook's deny envelope visible, research blurbs remain in the main repo working tree uncommitted.

### Regression test for non-protected path

1. In a repo with `execution.main_protected: false`, on `main`, with a new GH issue:
   ```bash
   /fix-issues sync
   ```
2. Expected: sync's Direct path commits tracker mods directly on main, runs `gh issue close` for any approved closes. No worktree, no PR.

### Pre-existing unrelated edits regression (AC-P.10)

1. With `main_protected: true` on `main`, make an unrelated edit:
   ```bash
   echo "wip note" >> docs/README.md
   git status -s  # should show ' M docs/README.md'
   /fix-issues sync
   ```
2. Expected: after sync completes (Protected path), `git status -s` in the main repo still shows ` M docs/README.md` — sync's path-scoped stash didn't touch it, and the worktree didn't sweep it in.

### `/land-pr` failure recovery (AC-P.3)

1. Force a `/land-pr` failure (e.g., set `--branch` to a name that already has a closed PR with merge conflicts, or simulate by deleting the worktree mid-flight).
2. Expected: sync reports `/land-pr did not land: STATUS=…, REASON=…`, exits non-zero, GH issues approved at step 3 remain OPEN on GitHub, tracker mods sit in the worktree (and stash, if pop failed). User can re-run sync after resolving.

### Conformance gate (CI)

`bash tests/test-skill-conformance.sh` exits 0. The cross-skill `/land-pr` caller check at lines 518-531 still passes (5 listed files unchanged; the new `land-pr` reference inside `skills/fix-issues/SKILL.md` adds a substring hit but doesn't break the assertion).

---

## Plan Quality

**Drafting process:** /draft-plan with up to 3 rounds of adversarial review.

**Round-1 findings + dispositions:** 29 total findings (15 reviewer + 14 devil's advocate, 4 cross-duplicates). 23 fix-required + 4 justified-not-fix. Disposition at `/tmp/draft-plan-review-FIX_ISSUES_SYNC_HARDENING-round-1.md`.

**Round-2 findings + dispositions:** 17 new findings (8 reviewer + 9 devil's advocate, 3 cross-duplicates). 4 new blockers (R2.1 OPEN_COUNT grep semantics, R2.2 indented heredoc, DA2.1 wrong WT_PATH from --prefix, DA2.2 broken `add -N` + stash). All blockers + majors + minors fixed in the round-2 refinement. Disposition at `/tmp/draft-plan-review-FIX_ISSUES_SYNC_HARDENING-round-2.md`.

Round 2 found real structural bugs in the round-1 spec (broken stash recipe; wrong worktree path math; YAML frontmatter rendered at column 2 → invalid). These were empirically reproduced before fixing.

**Round-3 findings + dispositions:** Reviewer side declared CONVERGED with 1 minor + 1 nit (N3.1 set -e fragility on `$?`-after-substitution, N3.2 `2>/dev/null` on `git worktree remove` swallows useful stderr — folded into Phase 3 implementation as polish items). DA side found 2 blockers + 1 major + 2 minors: DA3.1 missing `monitored` in deferred-close case-statement (would misclassify the canonical successful no-auto-CI-pass outcome as failure); DA3.2 entangled `--no-monitor` not passed → 10-min CI block contradicting single-shot framing; DA3.3 Direct-path silent commit-failure → state divergence; DA3.4 no end-to-end smoke test in Phase 4 ACs; DA3.5 USER_RESPONSE source unspecified. The 2 blockers and 1 major are fixed in this final refinement: deferred-close case now matches `created|monitored|merged`, `--no-monitor` is passed in LAND_ARGS, Direct path gates closes on commit success. DA3.4 (smoke test) is accepted as a residual concern — added a manual recipe in plan-level Tests rather than expanding Phase 4 scope. DA3.5 is closed via a one-line clarification in the Variable derivation block.

**Convergence:** CONVERGED at round 3 (after final refinement integrating DA3.1-3.3). The full-monitor mismatch DA3.1+DA3.2 was a late-round drift bug — adversarial review caught exactly the kind of caller-pattern divergence the canonical-pattern reference was meant to prevent.

**Remaining concerns:** DA3.4 (no executable smoke test gating Phase 4) is acknowledged. The plan relies on grep-based structural ACs + manual repro recipes; an implementing agent that copy-pastes the heredocs without dedenting (despite the in-plan column-0 annotation) or that mistypes a printf format string could still pass Phase 4 ACs while producing a runtime-broken sync. Mitigation: the four blockers Round 2 found, plus DA3.1-DA3.3, were all caught by adversarial reviewers running grep + the actual scripts — implementers should run the same primitives during execution, and the verifier subagent should be told to do likewise per CLAUDE.md "Verifier-cannot-run rule." If this turns out to be insufficient in practice, a follow-up plan can add an executable smoke-test phase.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 15 issues         | 14 issues                 | 23 fix + 4 justified (4 cross-dups) |
| 2     | 8 issues          | 9 issues                  | 14 fix (3 cross-dups, 4 blockers found+fixed) |
| 3     | 0 substantive + 2 polish | 5 substantive (2 blockers, 1 major, 2 minors) | 3 fix (blockers + major), 2 minor → 1 doc fix + 1 accepted residual |
