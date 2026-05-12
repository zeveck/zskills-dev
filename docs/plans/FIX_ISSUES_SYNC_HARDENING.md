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
- [ ] AC-P.3 — When the worktree+PR path is taken, `gh issue close` calls in Sync step 4 are deferred until AFTER `/land-pr` returns a success status (`created`, `monitored`, or `merged`). If `/land-pr` fails, no GitHub issues are closed (no state divergence).
- [ ] AC-P.4 — Sync producing zero net changes (no new issues, no closures, no annotations, no bootstrap write) is detected via `git status --porcelain` BEFORE worktree creation; sync exits cleanly with no PR.
- [ ] AC-P.5 — When `execution.main_protected: false` OR current branch is not `main`/`master`, sync executes the legacy direct-commit semantics (specified below — no pre-existing bash block exists; both paths are authored fresh by this plan).
- [ ] AC-P.6 — Both Standalone Sync (`skills/fix-issues/SKILL.md:183-295`) and Phase 1a Sync (`skills/fix-issues/SKILL.md:507-565`) bootstrap consistently. Sprint-mode auto-sync re-entry (`skills/fix-issues/SKILL.md:685-693`) also benefits from the step-5 fix because it re-enters standalone sync.
- [ ] AC-P.7 — `skills/fix-issues/SKILL.md` carries a current `metadata.version` after every commit (per-phase commits each bump; the final value is the hash of the final tree). `diff -rq skills/fix-issues .claude/skills/fix-issues` empty.
- [ ] AC-P.8 — `bash tests/run-all.sh` exits 0. `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-P.9a — The plan-landing PR body does NOT contain a GitHub auto-close directive against #231 or #233 (verb forms `close[sd]?`, `fixe[sd]?`, `resolve[sd]?` followed by `#231`/`#233`). Verification (case-insensitive, no `^` anchor, captures bulleted/inline forms): `gh pr view <plan-PR> --json body --jq '.body' | grep -ciE '\(close[sd]?\|fixe[sd]?\|resolve[sd]?\) #(231\|233)\b'` returns 0. Auto-close directives belong to the implementation PR (Phase 3's `/land-pr` PR), not to plan/refinement PRs.
- [ ] AC-P.9b — The plan-landing branch's commit messages also do NOT contain a GitHub auto-close directive against #231/#233. GitHub auto-closes from commit messages on squash-merge regardless of negation/quoting; "carries NO close-directive" prose still triggers. Verification: `git log --format=%B origin/main..HEAD | grep -ciE '\(close[sd]?\|fixe[sd]?\|resolve[sd]?\) #(231\|233)\b'` returns 0 on the plan-landing branch.
- [ ] AC-P.9c — The implementation-landing branch's commit messages DO contain the close directive against #231 and #233 (the implementation PR is where these issues should close on merge). Same regex against the implementation branch returns ≥1.
- [ ] AC-P.9d — Runtime sync PRs (those produced by `/fix-issues sync` after this plan lands) do NOT include an auto-close directive for issues that step 4b already closed via the GitHub API — avoids redundant API calls at merge.
- [ ] AC-P.10 — Pre-existing uncommitted/untracked work in the main repo that is unrelated to sync (paths outside `$ZSKILLS_ISSUES_DIR/` and `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`) is unaffected by sync's worktree-routing path.
- [ ] AC-P.11 — `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2 after this plan lands. Baseline before plan = 0 (verified). The 2 new commit sites: Protected-path commit on sync branch, and Direct-path commit. No additional `git commit` is introduced elsewhere in the skill. Locks in the "single sync commit logic in one spot, with two paths" invariant.
- [ ] AC-P.12 — Sync's `/land-pr` dispatch does NOT pass `--auto`. Verification (whole-file): `grep -cE -- '--auto' skills/fix-issues/SKILL.md` returns 0 (sync is human-review-only; merge happens manually after the user inspects the PR).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Worktree setup + plan scaffold | ⬚ | | Branch + frontmatter + plan parses |
| 2 — Bootstrap detector for empty issues_dir | ⬚ | | #231 root site fix; covers both Sync paths |
| 3 — `main_protected` worktree routing in Sync step 5 | ⬚ | | #233 root site fix; authors step-5 bash from scratch |
| 4 — Edge cases: zero-issues, untracked-aware diff, stash discipline, rc surfacing | ⬚ | | Hardening + smoke test wired into run-all.sh |
| 5 — Final version verification, conformance, run-all | ⬚ | | Verify (or rebump on verifier polish) + full test pass |

## Design & Constraints (plan-wide)

### Bootstrap filename — `ISSUES_PLAN.md`

Bootstrap creates `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md`, the historical canonical name. Sync's own glob (`skills/fix-issues/SKILL.md:519-525, 542`) explicitly accepts `*ISSUES*.md` OR the literal `ISSUES_PLAN.md`; path-migration script (`skills/update-zskills/scripts/migrate-paths.sh:613`) lists it first in its canonical filenames array; skill description (`skills/fix-issues/SKILL.md:31`) already names it. The dashboard does NOT scan `issues_dir` (`skills/zskills-dashboard/scripts/zskills_monitor/collect.py` only walks `plans_dir` at lines 1143-1147, 1249-1251), so tracker filename has no dashboard effect.

Bootstrap header template (written ONCE; subsequent sync runs read the existing file):

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

Row format added by sync's step-5 row-writer (one per open GH issue not yet in any tracker):

```markdown
### #NNN — <issue title>

**Labels:** <comma-separated labels from `gh issue view`>
**Verdict:** NOT YET RESEARCHED

(research blurb added by step-6 research-agent dispatch)
```

This template makes the no-blurb case visible (`grep -B1 'NOT YET RESEARCHED'` lists every issue still awaiting research).

### `main_protected` routing — when and how

**Conditional on net-diff** (not unconditional). Sync runs are frequently no-ops (no new issues, no closures, no annotations, no bootstrap needed). Creating a worktree + opening a PR on every protected-main sync would produce constant noise PRs.

**Net-diff detector** (run after step 4 edits, before step 5 commit). Detects tracked-file modifications AND untracked new files (the bootstrapped file is untracked at this point). `SPRINT_REPORT.md` is a secondary annotation site; included in the pathspec but tolerated absent (no error when missing):

```bash
SYNC_PATHS=("$ZSKILLS_ISSUES_DIR" "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
NET_DIFF=$(git status --porcelain -- "${SYNC_PATHS[@]}" 2>/dev/null)
if [ -z "$NET_DIFF" ]; then
  echo "Sync complete. No tracker changes."
  exit 0
fi
```

**Routing decision** (after net-diff confirms a change):

```bash
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." 2>/dev/null && pwd)}"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
MAIN_PROTECTED=0
CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ] && grep -qE '"main_protected"[[:space:]]*:[[:space:]]*true' "$CONFIG_FILE"; then
  MAIN_PROTECTED=1
fi
ON_PROTECTED_BRANCH=0
[[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]] && ON_PROTECTED_BRANCH=1
```

Both `main` and `master` are checked — `hooks/block-unsafe-project.sh.template:259` accepts either. `$PROJECT_ROOT` has an explicit `git rev-parse --git-common-dir` fallback so a fresh shell doesn't silently fall back to "/" or empty.

If `MAIN_PROTECTED == 1 && ON_PROTECTED_BRANCH == 1`: go to **Protected path**. Else: **Direct path**.

### Protected path — single bash block (worktree + `/land-pr` + deferred close)

The Protected path runs as ONE Bash tool invocation. All shell variables persist within a single invocation, so no cross-block state files are needed. The block mirrors the canonical caller pattern at `skills/fix-issues/modes/pr.md:80-220` — same structural shape (allow-list parsing, STATUS / CI_STATUS case-arms) but no retry loop and no fix-cycle agent dispatch.

`set -e` is NOT used (the recipe relies on explicit `|| { handler; exit N; }` after each fallible step so we control diagnostics). Each error path uses the `ERROR: <diagnostic>` prefix to stderr so the orchestrator surfaces it to the user.

```bash
SYNC_TS="$(TZ=America/New_York date +%Y%m%d-%H%M%S)"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
SYNC_BRANCH="sync/$SYNC_TS"
SLUG="sync-$SYNC_TS"
WT_PATH="/tmp/${PROJECT_NAME}-${SLUG}"
PIPELINE_ID="fix-issues.sync.$SYNC_TS"

### Step 1 — pre-flight stale-stash check
if git stash list | grep -qE 'On [^:]+: pre-sync-worktree-[0-9]+$'; then
  echo "ERROR: leftover 'pre-sync-worktree-<ts>' stash from a prior sync. Resolve: git stash list; git stash pop <id> OR git stash drop <id>" >&2
  exit 1
fi

### Step 2 — path-scoped stash (NOT blanket -u)
STASH_TS="$(date +%s)"
STASH_PATHS=("$ZSKILLS_ISSUES_DIR/")
[ -e "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" ] && STASH_PATHS+=("$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
git stash push -u -m "pre-sync-worktree-$STASH_TS" -- "${STASH_PATHS[@]}" \
  || { echo "ERROR: stash push failed" >&2; exit 1; }

### Step 3 — create or resume worktree
if [ -d "$WT_PATH" ]; then
  RESUME_BRANCH=$(cd "$WT_PATH" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$RESUME_BRANCH" != "$SYNC_BRANCH" ]; then
    echo "ERROR: resume worktree $WT_PATH is on branch '$RESUME_BRANCH', expected '$SYNC_BRANCH'. Remove the stale worktree or wait for the prior sync to complete." >&2
    exit 1
  fi
  cd "$WT_PATH"
else
  RC=0
  RESULT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
    --branch-name "$SYNC_BRANCH" --pipeline-id "$PIPELINE_ID" \
    --purpose "fix-issues sync" "$SLUG") || RC=$?
  case "$RC" in
    0)  WT_PATH="$RESULT"; cd "$WT_PATH" ;;
    2)  echo "ERROR: worktree path collision (rc=2). Inspect: ls -la /tmp/${PROJECT_NAME}-sync*" >&2; exit 2 ;;
    6)  echo "ERROR: fetch failed (rc=6). Re-run sync after network recovers." >&2; exit 6 ;;
    7)  echo "ERROR: local main has diverged from origin/main (rc=7). Pull or reset before re-running sync." >&2; exit 7 ;;
    10) echo "ERROR: local main is ahead of origin/main (rc=10). Resolve divergence (push or reset) and re-run sync." >&2; exit 10 ;;
    *)  echo "ERROR: create-worktree failed (rc=$RC). See stderr above." >&2; exit "$RC" ;;
  esac
fi

### Step 4 — pop the stash inside the worktree (stashes are repo-shared)
STASH_REF=$(git stash list | grep "pre-sync-worktree-$STASH_TS" | head -1 | cut -d: -f1)
if [ -z "$STASH_REF" ]; then
  echo "ERROR: pre-sync stash entry 'pre-sync-worktree-$STASH_TS' not found. Inspect: git stash list" >&2
  cd "$PROJECT_ROOT"
  git worktree remove --force "$WT_PATH" \
    || echo "Note: worktree $WT_PATH could not be auto-removed; remove manually." >&2
  exit 1
fi
git stash pop "$STASH_REF" || {
  echo "ERROR: stash pop conflicted in worktree (merge conflict). Inspect: cd $WT_PATH; git status; git stash list" >&2
  echo "Recovery: resolve conflicts in $WT_PATH then 'git stash drop $STASH_REF'; OR abandon: cd $PROJECT_ROOT; git worktree remove --force $WT_PATH; git stash pop $STASH_REF (re-apply on main)" >&2
  exit 1
}

### Step 5 — stage explicit paths + check non-empty
ADD_PATHS=("$ZSKILLS_ISSUES_DIR/")
[ -e "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" ] && ADD_PATHS+=("$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
git add -- "${ADD_PATHS[@]}"
STAGED=$(git diff --cached --name-only)
if [ -z "$STAGED" ]; then
  echo "Sync complete. No tracker changes after stash pop." >&2
  cd "$PROJECT_ROOT"
  exit 0
fi

### Step 6 — commit on the sync branch (NOT main; hook does not fire)
git commit -m "sync: update trackers + research blurbs ($SYNC_TS)" \
  || { echo "ERROR: commit on $SYNC_BRANCH failed" >&2; exit 1; }

### Step 7 — build PR body + dispatch /land-pr
# APPROVED_LIST and NEW_RESEARCHED_COUNT and BOOTSTRAP_NEW were computed earlier
# in sync steps 3-4 (in the same Bash invocation as this Protected path).
RESULT_FILE=$(mktemp)
BODY_FILE=$(mktemp)
PR_DATE=$(TZ=America/New_York date +%F)
PR_TS=$(TZ=America/New_York date -Iseconds)
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
  printf -- '- [x] Tracker diff reviewed by user before merge (sync is interactive; CI runs post-merge against the merge commit, not as a sync gate)\n\n'
  printf 'Generated by `/fix-issues sync` at %s\n' "$PR_TS"
} > "$BODY_FILE"
PR_TITLE="sync: trackers $PR_DATE"
LAND_ARGS="--branch=$SYNC_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sync --worktree-path=$WT_PATH"
# Body intentionally OMITS GitHub auto-close directives — sync closes
# approved issues itself via `gh issue close` in step 9 AFTER /land-pr success.
# No --auto (sync is human-review-only). No --no-monitor (canonical monitor
# flow runs so CI failures surface proactively at PR creation time).
#
# Dispatch via Skill tool:
#   Skill { skill: "land-pr", args: "$LAND_ARGS" }

### Step 8 — parse result with allow-list (canonical pattern from skills/fix-issues/modes/pr.md:112-125)
if [ ! -f "$RESULT_FILE" ]; then
  echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
  exit 1
fi
declare -A LP
while IFS='=' read -r KEY VALUE; do
  case "$KEY" in
    STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
    MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
    CONFLICT_FILES_LIST|CALL_ERROR_FILE)
      LP["$KEY"]="$VALUE" ;;
    "") ;;
    *) printf 'WARN: /land-pr result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
  esac
done < "$RESULT_FILE"
LAND_STATUS="${LP[STATUS]:-}"
LAND_CI_STATUS="${LP[CI_STATUS]:-}"
LAND_PR_URL="${LP[PR_URL]:-}"
LAND_REASON="${LP[REASON]:-}"

### Step 9 — deferred close gated on STATUS + CI_STATUS
# CI_STATUS contract per skills/land-pr/SKILL.md:162 and
# skills/land-pr/scripts/pr-monitor.sh:120-125:
#   pass|fail|pending|none|skipped|unknown|not-monitored
# Sync mapping:
#   - Success arm: ""|pass|none|skipped|not-monitored  → close GH issues
#   - Defer  arm: pending|unknown                       → leave open; re-run hint
#   - Punt   arm: fail                                  → diagnostic; NO fix-cycle agent
#   - Wildcard:   *                                     → defensive exit 1
case "$LAND_STATUS" in
  created|monitored|merged)
    case "$LAND_CI_STATUS" in
      ""|pass|none|skipped|not-monitored)
        echo "PR landed at $LAND_PR_URL (CI: ${LAND_CI_STATUS:-not-run})"
        for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
          [ -n "$ISSUE_NUM" ] || continue
          gh issue close "$ISSUE_NUM" --comment "Fixed; tracker updated in $LAND_PR_URL."
        done
        ;;
      pending|unknown)
        echo "PR created at $LAND_PR_URL — CI is $LAND_CI_STATUS." >&2
        echo "GH issues NOT closed yet (avoiding state divergence; close requires CI pass)." >&2
        echo "Re-run /fix-issues sync after CI completes, or close manually:" >&2
        for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
          [ -n "$ISSUE_NUM" ] || continue
          echo "  gh issue close $ISSUE_NUM --comment 'Fixed; tracker updated in $LAND_PR_URL.'" >&2
        done
        ;;
      fail)
        # Content-PR punt — canonical fix-cycle agent is specced for code+test PRs
        # and would mutate trackers chasing lint/snapshot noise. Case-arm terminates
        # with `;;` (NOT `break` — invalid bash outside a loop).
        echo "PR created at $LAND_PR_URL but CI failed (CI_STATUS=$LAND_CI_STATUS)." >&2
        echo "Sync does not dispatch a fix-cycle agent on content-only PRs (hazardous)." >&2
        echo "GH issues NOT closed. Inspect the PR on GitHub: $LAND_PR_URL" >&2
        ;;
      *)
        echo "ERROR: /land-pr returned unrecognized CI_STATUS=$LAND_CI_STATUS." >&2
        echo "GH issues NOT closed. Inspect $RESULT_FILE and $LAND_PR_URL." >&2
        exit 1
        ;;
    esac
    ;;
  rebase-conflict)
    echo "/land-pr returned rebase-conflict. Resolve in $WT_PATH or re-run sync." >&2
    exit 1 ;;
  push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
    echo "ERROR: /land-pr STATUS=$LAND_STATUS REASON=$LAND_REASON" >&2
    exit 1 ;;
  *)
    echo "ERROR: /land-pr returned unrecognized STATUS=$LAND_STATUS REASON=$LAND_REASON" >&2
    exit 1 ;;
esac

### Step 10 — write .landed marker (CLAUDE.md "ALWAYS write a .landed marker")
cat > "$WT_PATH/.landed" <<MARKER
status: full
date: $(TZ=America/New_York date -Iseconds)
source: fix-issues-sync
pr: $LAND_PR_URL
MARKER
```

**Cleanup posture.** The worktree at `$WT_PATH` is left in place after successful land. The user may inspect the diff, hand-edit, or re-run checks before merging on GitHub. The `.landed` marker is the cleanup signal — future cleanup tools (or the user) can prune `/tmp/<proj>-sync-*` worktrees with `status: full`. On the missing-stash auto-remove path (step 4), the worktree is removed. On the CI-fail punt, the worktree is left for inspection.

**Approval-set derivation.** `APPROVED_LIST` (bash array of bare issue numbers approved at sync step 3) is computed in the same Bash invocation as the Protected path above. It is read from the user's step-3 literal response (`231,233` / `all` / `none`):

```bash
APPROVED_LIST=()
case "$USER_RESPONSE" in
  none) ;;
  all)  for N in "${ALL_FIXED_NUMS[@]}"; do APPROVED_LIST+=("$N"); done ;;
  *)    IFS=',' read -r -a APPROVED_LIST <<< "${USER_RESPONSE// /}" ;;
esac
APPROVED_CLOSE_COUNT=${#APPROVED_LIST[@]}
```

The defensive `[ -n "$ISSUE_NUM" ] || continue` in step 9's close loops drops accidental empty elements so `gh issue close ""` is never reachable.

`BOOTSTRAP_NEW` is `yes` if step 4's bootstrap subroutine wrote the tracker this run (detected via `git status --porcelain -- "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" | grep -q '^??'` immediately after the bootstrap-write), else `no`. `NEW_RESEARCHED_COUNT` is the count of new `### #` rows written by step 4's row-writer.

`OPEN_NUMS` / `OPEN_COUNT` are populated from one `gh issue list` call:

```bash
GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1) \
  || { echo "ERROR: 'gh issue list' failed:" >&2; echo "$GH_OUT" >&2; exit 1; }
mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
OPEN_COUNT=${#OPEN_NUMS[@]}
```

`grep -cE` over single-line JSON would return 0-or-1 (line count); `grep -oE | mapfile` is the correct shape.

### Direct path — single bash block (legacy semantics)

Step 5 is prose-only in today's SKILL.md (lines 280-295); both paths are authored fresh by this plan:

```bash
ADD_PATHS=("$ZSKILLS_ISSUES_DIR/")
[ -e "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" ] && ADD_PATHS+=("$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
git add -- "${ADD_PATHS[@]}"
STAGED=$(git diff --cached --name-only)
if [ -z "$STAGED" ]; then
  echo "Sync complete. No tracker changes."
  exit 0
fi
git commit -m "sync: update trackers + research blurbs" \
  || { echo "ERROR: git commit failed in Direct path; not closing GH issues to avoid state divergence." >&2; exit 1; }
for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
  [ -n "$ISSUE_NUM" ] || continue
  gh issue close "$ISSUE_NUM" --comment "Fixed; tracker updated."
done
```

### `/land-pr` dispatch contract — caller-list note

`/fix-issues sync` is NOT a new conformance-locked `/land-pr` caller. The conformance fingerprint at `tests/test-skill-conformance.sh:519-538` lists five files (`skills/run-plan/modes/pr.md`, `skills/commit/modes/pr.md`, `skills/do/modes/pr.md`, `skills/fix-issues/modes/pr.md`, `skills/quickfix/SKILL.md`) and asserts each contains the substring `land-pr`. The new sync dispatch lives in `skills/fix-issues/SKILL.md` — a different file — and adds a `land-pr` reference there, which neither breaks the substring check on the five tracked files nor adds a new entry to the tracked list.

### Sync uses canonical monitor flow, but NO fix-cycle agent dispatch

Sync passes neither `--auto` nor `--no-monitor`. The canonical monitor flow runs so CI failures surface proactively at PR creation time, matching the 4 no-auto canonical callers (`/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`). What sync strips is the **fix-cycle agent dispatch** on `CI_STATUS=fail`: the canonical agent (`skills/land-pr/references/fix-cycle-agent-prompt-template.md`) is specced for code+test PRs (read CI log → diagnose → patch → commit). On a tracker-content PR, the agent has no legitimate fix to apply — a lint warning, a stale snapshot diff, or a flaky workflow would tempt it to mutate tracker entries, edit test workflows, or hallucinate fixes against lint warnings.

Sync is the first canonical-caller variant to skip fix-cycle entirely. The other 5 callers all default to `CI_MAX_ATTEMPTS=2` (verified at `skills/quickfix/SKILL.md:1076`). Precedent absence is acknowledged, not papered over; the principled justification (content-only PR, code-fix agent is hazardous) stands on its own.

### Skill versioning workflow (per phase)

Each phase that edits `skills/fix-issues/SKILL.md` ends with its own version bump and commit. The PreToolUse hook `block-stale-skill-version.sh` enforces this at every commit. Phase 5 handles the verifier-polish rebump case: if a Phase-4 verifier subagent committed a polish patch after the per-phase bump, Phase 5 detects the hash mismatch and emits a single rebump-commit on top:

```bash
HASH_NOW=$(bash scripts/skill-content-hash.sh skills/fix-issues)
VER_NOW=$(bash scripts/frontmatter-get.sh skills/fix-issues/SKILL.md metadata.version | sed 's/.*+//')
if [ "$HASH_NOW" != "$VER_NOW" ]; then
  TODAY=$(TZ=America/New_York date +%Y.%m.%d)
  bash scripts/frontmatter-set.sh skills/fix-issues/SKILL.md metadata.version "$TODAY+$HASH_NOW"
  bash scripts/mirror-skill.sh fix-issues
  git add skills/fix-issues/SKILL.md .claude/skills/fix-issues/SKILL.md
  git commit -m "polish: rebump skills/fix-issues metadata.version to current content hash"
fi
```

### Bootstrap fires regardless of caller — Phase 1a is shared

The bootstrap subroutine lives in Phase 1a Sync. Phase 1a is shared between standalone sync (`/fix-issues sync` step 1 delegates to Phase 1a) and sprint mode (`/fix-issues N`). Both flows now trigger bootstrap when `issues_dir` is empty.

In sprint mode, the bootstrap file is written to the main repo working tree at Phase 1a (before sprint creates per-issue worktrees). Sprint's later cherry-pick / PR-mode phases pick it up via the same `git status --porcelain` enumeration this plan uses — bootstrap rides along with whatever the sprint commits. Under `main_protected: true` in sprint mode, sprint's per-issue worktree+PR model is already worktree-routed, so the bootstrap file lands as part of a per-issue PR. No new commit path needed in sprint mode.

In standalone sync (and sprint-mode's "auto-sync before giving up" re-entry at `skills/fix-issues/SKILL.md:685-693`), Phase 3's step-5 routing covers both bootstrap file and tracker mods. The implementing agent must NOT short-circuit Phase 3's routing based on "we are inside sprint mode."

### Hard constraints

- Do NOT call `gh pr create` or `gh pr merge --auto` directly. Dispatch `/land-pr`.
- Do NOT pass `--auto` to `/land-pr` from sync (AC-P.12). Sync is human-review-only.
- Do NOT pass `--no-monitor` to `/land-pr` from sync. Canonical monitor flow runs.
- Do NOT add `jq` to `skills/fix-issues/SKILL.md`. Use BASH_REMATCH / `grep -oE`.
- Do NOT bypass hooks with `--no-verify`.
- Do NOT extend `main_protected` to landing modes other than sync.
- Do NOT extend the `block-direct-main-commit` hook tokenizer — Layer-1 carve-outs are accepted.
- **Never write a literal GitHub auto-close directive (`Close[sd]? #N` / `Fixe[sd]? #N` / `Resolve[sd]? #N` against a real issue number) in any PR body, commit message, or plan prose unless that PR/commit IS the one that should close issue N at merge time.** GitHub auto-closes from BOTH PR body and commit message at squash-merge, regardless of negation, quoting, or backticks. Reference issues by bare `#231` / `#233` when not closing. Past failures: PR #237 had the directive in the PR body; PR #243 had it in a commit message phrased as a negation. This plan itself uses bare `#231` / `#233` throughout; AC-P.9a/b enforce this on the plan-landing PR; AC-P.9c enforces the implementation PR DOES carry the directives.
- `metadata.version` bump on each `skills/fix-issues/SKILL.md` edit is mandatory.

### What this plan does NOT do

- Does not refactor sync's argument parsing or research-agent dispatch logic.
- Does not change sprint-mode (`/fix-issues N`) per-issue commit semantics.
- Does not add a `--auto` arg to sync.
- Does not modify Phase 1a Sync's commit semantics (Phase 1a doesn't commit; only step 5 does).
- Does not dispatch a `/land-pr` fix-cycle agent on sync's PR (content-only; canonical agent is code+test-specced).

---

## Phase 1 — Worktree setup + plan scaffold

### Goal

Establish the feature branch worktree this plan runs in and ensure `/run-plan` can parse the plan file. Bookkeeping-only; no behavior changes to `skills/fix-issues/SKILL.md`.

### Work Items

- [ ] WI 1.1 — Confirm the worktree exists, the branch is the agreed feature branch, and it's pushed to `origin`.
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

Address #231 — when sync scans `$ZSKILLS_ISSUES_DIR/` and finds zero tracker files, bootstrap an `ISSUES_PLAN.md` file with the header template specified in plan-wide Design & Constraints. Cover the shared Phase 1a code path.

### Work Items

- [ ] WI 2.1 — In `skills/fix-issues/SKILL.md` Phase 1a Sync, immediately before the gap-detection block at line 519-529, fetch the open-issue list AND count safely (single `gh` call, parsed for both count and number array). `grep -cE` over single-line JSON would return line-count not match-count — use `grep -oE | mapfile`:
  ```bash
  GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1) \
    || { echo "ERROR: 'gh issue list' failed:" >&2; echo "$GH_OUT" >&2; exit 1; }
  mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
  OPEN_COUNT=${#OPEN_NUMS[@]}
  ```
- [ ] WI 2.2 — Add the bootstrap subroutine before the existing `ls "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md ...` at line 521. **The heredoc body MUST be at column 0** when inserted into `skills/fix-issues/SKILL.md` — bash `<<TRACKER` (no `-` suffix) does not strip leading whitespace, and YAML frontmatter must start at column 0:
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

  Created by \`/fix-issues sync\` on $TODAY because this repo had no tracker files in \`\$ZSKILLS_ISSUES_DIR/\` when sync ran.

  ## Open Issues

  (rows added by sync step 5 below)
  TRACKER
    echo "Bootstrapped $ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
    BOOTSTRAP_NEW=yes
  else
    BOOTSTRAP_NEW=no
  fi
  ```
  (The heredoc body lines in this plan are shown indented for plan readability; in the SKILL.md insertion they must be at column 0.)
- [ ] WI 2.3 — Update the prose at `skills/fix-issues/SKILL.md:558-561` to add: "Empty `issues_dir` now triggers bootstrap; this failure mode is structurally prevented." (Prose-only edit.)
- [ ] WI 2.4 — Add an issue-row writer that runs BEFORE the commit-routing decision: for each open GH issue not yet in any tracker, append the row template. Iterate `OPEN_NUMS`; for each `N`, test membership with an **anchored** regex so `bug#23` doesn't match `#23`:
  ```bash
  if grep -qE '(^|[^0-9A-Za-z_])#'"$N"'($|[^0-9])' \
       "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null; then
    continue
  fi
  ```
  For the residual, fetch title+labels via `gh issue view "$N" --json title,labels`, parse via `grep -oE` (no jq), and append the row template to `ISSUES_PLAN.md`. Increment `NEW_RESEARCHED_COUNT` per row written.
- [ ] WI 2.5 — Add a cross-reference comment in the Standalone Sync section: `<!-- Bootstrap of empty $ZSKILLS_ISSUES_DIR/ happens in Phase 1a Sync; Standalone Sync inherits it via step 1's "Run Phase 1a" delegation. -->`
- [ ] WI 2.6 — Skill-version bump + mirror.

### Design & Constraints

Bootstrap fires unconditionally when `issues_dir` has zero trackers AND `OPEN_COUNT > 0`. If `OPEN_COUNT == 0`, sync exits early with a clean message — no empty tracker, no PR, no noise.

The bootstrap subroutine creates `$ZSKILLS_ISSUES_DIR` directory if missing.

Filename is `ISSUES_PLAN.md`. Row-writer regex is anchored so `bug#23` does not match `#23`.

### Acceptance Criteria

- [ ] AC-2.1 — `grep -nE 'ISSUES_PLAN\.md' skills/fix-issues/SKILL.md` returns ≥3 hits (existing line 521/525/542 patterns AND the new bootstrap-write site).
- [ ] AC-2.2 — `grep -nB1 -A8 'EXISTING_TRACKERS=' skills/fix-issues/SKILL.md | grep -E 'bootstrap|ISSUES_PLAN\.md'` returns ≥1 hit (bootstrap branch anchored to gap-detection site).
- [ ] AC-2.3 — `grep -nE 'OPEN_COUNT.*-eq 0|0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit (zero-issue early-exit).
- [ ] AC-2.4 — `grep -nE 'NOT YET RESEARCHED' skills/fix-issues/SKILL.md` returns ≥1 hit (row template).
- [ ] AC-2.5 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-2.6 — `bash scripts/skill-content-hash.sh skills/fix-issues` output matches the `metadata.version` suffix.
- [ ] AC-2.7 — `grep -nE 'Bootstrap of empty.*ISSUES_DIR|inherits.*bootstrap' skills/fix-issues/SKILL.md` returns ≥1 hit (WI 2.5 cross-reference).
- [ ] AC-2.8 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-2.9 — Row-writer membership check is anchored: `grep -nE '\(\^\|\[\^0-9A-Za-z_\]\)#' skills/fix-issues/SKILL.md` returns ≥1 hit.

### Dependencies

Phase 1.

---

## Phase 3 — `main_protected` worktree routing in Sync step 5

### Goal

Address #233 — author step 5's bash from scratch (currently prose-only at lines 280-295). The block has two paths — Protected and Direct — fully specified in plan-wide Design & Constraints. Each path is a single contiguous bash block (no cross-block state files).

### Work Items

- [ ] WI 3.1 — In `skills/fix-issues/SKILL.md` between step 4 prose (lines 266-278) and step 5 heading (line 280), insert the **net-diff detector** specified in plan-wide Design & Constraints.
- [ ] WI 3.2 — Insert the **routing decision** block (PROJECT_ROOT resolution, MAIN_PROTECTED detection, ON_PROTECTED_BRANCH check on both `main` and `master`).
- [ ] WI 3.3 — Author the **Protected path** as a single bash block per plan-wide Design & Constraints. The block contains steps 1-10 inline (stale-stash check, path-scoped stash, worktree create/resume, stash pop, stage, commit, body construction, `/land-pr` dispatch, result parsing + deferred close, `.landed` marker). Variables (`SYNC_TS`, `WT_PATH`, `APPROVED_LIST`, `BOOTSTRAP_NEW`, `NEW_RESEARCHED_COUNT`, etc.) persist within the single Bash invocation — no state files needed.
- [ ] WI 3.4 — Author the **Direct path** as a single bash block per plan-wide Design & Constraints — explicit `git add` pathspec, commit-success gate, immediate `gh issue close` loop.
- [ ] WI 3.5 — Update the step-5 report block to surface either `LAND_PR_URL` (Protected path) or commit hash (Direct path).
- [ ] WI 3.6 — Skill-version bump + mirror.

### Design & Constraints

All concrete logic is specified in plan-wide Design & Constraints. This phase inserts that logic into `skills/fix-issues/SKILL.md` at the right lines, with no design decisions deferred.

The single sync commit site invariant (AC-P.11) locks in: exactly 2 `git commit` invocations across the skill — one in Protected path, one in Direct path.

`/fix-issues sync` is not a new conformance-locked `/land-pr` caller; the cross-skill conformance check at `tests/test-skill-conformance.sh:519-538` uses substring matching on five specific files and is unaffected.

### Acceptance Criteria

- [ ] AC-3.1 — `grep -nE 'git status --porcelain -- "\$\{?SYNC_PATHS' skills/fix-issues/SKILL.md` returns ≥1 hit (net-diff detector uses `status --porcelain`).
- [ ] AC-3.2 — `grep -nE 'CURRENT_BRANCH.*==.*main.*\|\|.*CURRENT_BRANCH.*==.*master|ON_PROTECTED_BRANCH' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-3.3 — `grep -nE 'PROJECT_ROOT:-.*git-common-dir|git rev-parse --git-common-dir' skills/fix-issues/SKILL.md` returns ≥1 hit in Standalone Sync (explicit fallback).
- [ ] AC-3.4 — `grep -nE 'create-worktree\.sh' skills/fix-issues/SKILL.md` returns ≥1 hit in Standalone Sync. Timestamped slug: `grep -nE '\"sync-\$SYNC_TS\"|SLUG=\"sync-\$SYNC_TS\"' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-3.5 — `grep -cE 'land-pr|/land-pr' skills/fix-issues/SKILL.md` returns ≥2 (baseline = 0; the new Standalone Sync block adds at least 2 references).
- [ ] AC-3.6 — `grep -cE 'gh pr create|gh pr merge --auto' skills/fix-issues/SKILL.md` returns 0.
- [ ] AC-3.7 — `grep -nE 'pre-sync-worktree-' skills/fix-issues/SKILL.md` returns ≥2 hits (pre-flight check AND new stash creation).
- [ ] AC-3.8 — **STATUS + CI_STATUS contract.** `grep -nE 'case "\$LAND_STATUS" in|created\|monitored\|merged\)' skills/fix-issues/SKILL.md` returns ≥1 hit. `grep -cE -- '--no-monitor' skills/fix-issues/SKILL.md` returns 0 (canonical monitor flow). `grep -nE 'case "\$LAND_CI_STATUS" in' skills/fix-issues/SKILL.md` returns ≥1 hit. `grep -nE '""\|pass\|none\|skipped\|not-monitored\)' skills/fix-issues/SKILL.md` returns ≥1 hit (success arm). `grep -nE 'pending\|unknown\)' skills/fix-issues/SKILL.md` returns ≥1 hit (defer arm). `grep -nE '^[[:space:]]*fail\)' skills/fix-issues/SKILL.md` returns ≥1 hit (punt arm — `fail` alone, NOT `fail|failure`). `grep -nE 'skills/land-pr/SKILL\.md:162' skills/fix-issues/SKILL.md` returns ≥1 hit (contract citation).
- [ ] AC-3.9 — `grep -nB3 -A2 'gh issue close' skills/fix-issues/SKILL.md | grep -E 'LAND_STATUS|case .*created\|monitored\|merged|after.*land'` returns ≥1 hit (deferred-close gating).
- [ ] AC-3.10 — `grep -nE 'rc=10|ahead of origin/main' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-3.11 — `grep -nE '"\$\{APPROVED_LIST\[@\]\}"' skills/fix-issues/SKILL.md` returns ≥2 hits (array iteration in both paths).
- [ ] AC-3.12 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-3.13 — `bash scripts/skill-content-hash.sh skills/fix-issues` matches the staged version suffix.
- [ ] AC-3.14 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-3.15 — `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2 (AC-P.11 mirror).
- [ ] AC-3.16 — `grep -cE -- '--auto' skills/fix-issues/SKILL.md` returns 0 (whole-file).
- [ ] AC-3.17 — Failure case-arms exit non-zero: `grep -nE 'rebase-conflict\)|push-failed\|create-failed\|monitor-failed\|merge-failed\|rebase-failed\)' skills/fix-issues/SKILL.md` returns ≥1 hit.

### Dependencies

Phase 2.

---

## Phase 4 — Edge cases + smoke test wired into run-all.sh

### Goal

Verify and harden edge cases Phases 2-3 surface, AND add an executable smoke test asserting the four most error-prone structural invariants (column-0 heredoc, no `add -N` regression, stash pathspec shape, single-commit-site invariant). The smoke test gates landing via `tests/run-all.sh`.

### Work Items

- [ ] WI 4.1 — Verify and add ACs for **zero open GH issues + empty issues_dir** → exits before bootstrap with `Sync complete. 0 open issues, no trackers needed.`
- [ ] WI 4.2 — Verify and add ACs for **zero net diff after step 4** → exits before worktree creation with `Sync complete. No tracker changes.`
- [ ] WI 4.3 — Verify and add ACs for **worktree resume** — timestamped `WT_PATH=/tmp/${PROJECT_NAME}-sync-${SYNC_TS}`; if `[ -d "$WT_PATH" ]`, verify branch matches before reusing; branch-mismatch resume aborts.
- [ ] WI 4.4 — Verify and add ACs for **create-worktree.sh rc handling** (0, 2, 6, 7, 10, default — distinct branches with distinct messages).
- [ ] WI 4.5 — Add **non-main feature branch** path verification: `ON_PROTECTED_BRANCH=0 && MAIN_PROTECTED=1` falls through to Direct path. Inline-comment so future readers don't add a redundant guard.
- [ ] WI 4.6 — Verify and add AC for **gh issue list failure handling** — non-zero exit surfaces stderr verbatim and sync exits non-zero.
- [ ] WI 4.7 — Verify and add AC for **stash discipline**: pre-flight anchored-regex stash check + path-scoped `stash push -u -- <pathspec>` (NO `git add -N`) + post-pop missing-entry-vs-conflict split diagnostics + worktree cleanup on missing-entry.
- [ ] WI 4.8 — Verify and add AC for **pre-existing unrelated edits are unaffected** (AC-P.10).
- [ ] WI 4.9 — **Create `tests/test-fix-issues-sync-smoke.sh`** asserting four structural invariants:
  1. **Heredoc terminator AND body lines at column 0.** All three checks must pass:
     - `grep -cE '^TRACKER$' skills/fix-issues/SKILL.md` ≥1 (terminator).
     - `grep -cE '^title: Issues — Auto-Bootstrapped Tracker$' skills/fix-issues/SKILL.md` ≥1 (title at column 0).
     - `grep -cE '^status: active$' skills/fix-issues/SKILL.md` ≥1 (status at column 0).
  2. **No `git add -N`.** `grep -cE 'git[[:space:]]+add[[:space:]]+-N' skills/fix-issues/SKILL.md` returns 0.
  3. **Stash pathspec shape.** Exactly one `git stash push -u -m "pre-sync-worktree-...` and its pathspec includes `$ZSKILLS_ISSUES_DIR/`.
  4. **Single-commit-site invariant.** `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2.

  **Test-output format requirement.** Final line MUST match `Results: N passed, M failed (of Z)` for `tests/run-all.sh:run_suite()` count extraction. Follow `tests/test-skill-content-hash.sh:135`:
  ```bash
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  [ "$FAIL_COUNT" -gt 0 ] && exit 1
  exit 0
  ```
- [ ] WI 4.10 — **Wire the smoke test into `tests/run-all.sh`** by adding `run_suite "test-fix-issues-sync-smoke.sh" "tests/test-fix-issues-sync-smoke.sh"`.
- [ ] WI 4.11 — Skill-version bump + mirror.

### Design & Constraints

This phase has two scopes: (a) AC-only verification of Phases 2-3 edge cases, and (b) the new executable smoke test. The smoke test is structural (grep-anchored, no git-runtime emulation). End-to-end behavior remains a follow-up canary (`docs/plans/FIX_ISSUES_SYNC_CANARY.md`).

Hook-fail signals are real; never bypass.

### Acceptance Criteria

- [ ] AC-4.1 — `grep -nE '0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.2 — `grep -nE 'No tracker changes' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.3 — `grep -nE 'Resuming existing sync worktree|if \[ -d "\$WT_PATH"' skills/fix-issues/SKILL.md` returns ≥1 hit, AND `grep -nE 'resume worktree .* is on branch' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.4 — `grep -nE 'case "\$RC" in' skills/fix-issues/SKILL.md` returns ≥1 hit AND `grep -cE '\(rc=(2|6|7|10)\)' skills/fix-issues/SKILL.md` returns ≥4.
- [ ] AC-4.5 — `grep -nB1 -A3 'ON_PROTECTED_BRANCH=0|feature branch.*hook.*not.*fire' skills/fix-issues/SKILL.md | grep -E 'Direct path|not on main/master'` returns ≥1 hit (anchored prose).
- [ ] AC-4.6 — `grep -nE 'gh issue list.*failed|GH_OUT=\$\(gh issue list' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.7 — `grep -nE 'git stash push -u -m.*pre-sync-worktree-.*--' skills/fix-issues/SKILL.md` returns ≥1 hit. `grep -cE 'git add -N' skills/fix-issues/SKILL.md` returns 0. `grep -nE 'stash entry .pre-sync-worktree-.* not found|stash pop conflicted' skills/fix-issues/SKILL.md` returns ≥1 hit. `grep -nE 'if ! git worktree remove --force|git worktree remove --force .* \\\\$' skills/fix-issues/SKILL.md` returns ≥1 hit (the worktree-remove outcome is checked, not silenced).
- [ ] AC-4.8 — Manual verification (recorded in commit message): with `git status -s` showing an unrelated edit outside sync paths, running sync's worktree path preserves that edit on main untouched.
- [ ] AC-4.9 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-4.10 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-4.11 — **Smoke test exists and is wired into run-all.sh.**
  - File `tests/test-fix-issues-sync-smoke.sh` exists, is executable, exits 0 against current state.
  - `grep -q 'test-fix-issues-sync-smoke.sh' tests/run-all.sh` succeeds.
  - Invariant #1 expands to 3 column-0 checks (terminator, `title:`, `status:`), so the test emits ≥6 `pass`/`fail` lines total.
  - Final stdout line matches `Results: N passed, M failed`: `tail -1 <smoke-stdout> | grep -qE '^Results: [0-9]+ passed, [0-9]+ failed'`.

### Dependencies

Phases 2 and 3.

---

## Phase 5 — Final version verification, conformance, run-all (+ verifier-polish rebump)

### Goal

Verify the final state — version is current, conformance passes, full test suite passes, Progress Tracker is up to date. Handle the verifier-polish rebump case if a Phase-4 verifier subagent applied a content patch after the per-phase bump.

### Work Items

- [ ] WI 5.1 — **Verifier-polish detection + conditional rebump** per plan-wide Design & Constraints "Skill versioning workflow." No-op when hash matches; one rebump-commit when it doesn't.
- [ ] WI 5.2 — `bash scripts/mirror-skill.sh fix-issues` (idempotent — should be a no-op after WI 5.1). `diff -rq` empty.
- [ ] WI 5.3 — Full test suite captured to file (CLAUDE.md "Capture test output to a file, never pipe"):
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  ```
  Read results; fix at originating phase on failure (no thrash — two attempts max).
- [ ] WI 5.4 — Conformance: `bash tests/test-skill-conformance.sh`. Fail loudly on non-zero.
- [ ] WI 5.5 — Update plan Progress Tracker rows for Phases 1-5 to ✓ with commit refs.
- [ ] WI 5.6 — **Commit the canary follow-up stub.** Verify `docs/plans/FIX_ISSUES_SYNC_CANARY.md` exists with `status: draft` and contains the canary recipe from Plan-level Tests. Commit it on the feature branch.
- [ ] WI 5.7 — Plan frontmatter `status: complete` is set by `/run-plan finish` at land time.

### Design & Constraints

No structural SKILL.md edits in Phase 5 — at most a one-line rebump. Test failures get fixed at originating phase, not band-aided here. Hook fires are real signals — investigate, don't bypass.

### Acceptance Criteria

- [ ] AC-5.1 — `grep -nE '^  version:' skills/fix-issues/SKILL.md | head -1` shows `version: "20[0-9]{2}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}"`.
- [ ] AC-5.2 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-5.3 — `bash scripts/skill-version-stage-check.sh` exits 0.
- [ ] AC-5.4 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-5.5 — `bash tests/run-all.sh` exits 0; output captured to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`. The captured output includes a `Tests: test-fix-issues-sync-smoke.sh` section with all four invariants passing.
- [ ] AC-5.6 — Progress Tracker rows for Phases 1-5 show ✓ with commit refs.
- [ ] AC-5.7 — Content-hash matches version suffix.
- [ ] AC-5.8 — `docs/plans/FIX_ISSUES_SYNC_CANARY.md` exists, parses cleanly, has `status: draft`. `git log --oneline -- docs/plans/FIX_ISSUES_SYNC_CANARY.md` shows ≥1 commit on the feature branch.

### Dependencies

Phases 1-4 complete.

---

## Plan-level Tests (manual reproduction recipes + canary deferral)

The verifier-runnable ACs cover structural assertions. The Phase 4 smoke test (wired into `tests/run-all.sh`) gates the four error-prone invariants at CI time. These manual recipes prove the actual behavior change end-to-end.

### Manual repro #231 (bootstrap)

1. In a scratch repo with `$ZSKILLS_ISSUES_DIR/` empty and at least one open GH issue:
   ```bash
   rm -rf .zskills/issues
   gh issue create --title "test bootstrap" --body "synthetic"
   /fix-issues sync
   ```
2. Expected (after this plan): `.zskills/issues/ISSUES_PLAN.md` is created with frontmatter header and ≥1 `### #NNN — <title>` row; research-agent dispatch runs; sync summary reports `K=1 tracker file(s) updated`.
3. Control (before this plan): no file is created; `K=0 trackers updated` reported silently.

### Manual repro #233 (main_protected)

1. In a repo with `.claude/zskills-config.json` containing `execution.main_protected: true`, on `main`, with at least one open GH issue not yet in any tracker:
   ```bash
   git checkout main
   /fix-issues sync
   ```
2. Expected: sync detects `MAIN_PROTECTED=1 && ON_PROTECTED_BRANCH=1`, runs net-diff check (non-empty), pre-flight stash check, path-scoped stashes tracker dir + sprint report, creates worktree at `/tmp/<proj>-sync-YYYYMMDD-HHMMSS/` on branch `sync/YYYYMMDD-HHMMSS`, pops stash there, commits, dispatches `/land-pr` (canonical monitor flow, no `--auto`/`--no-monitor`), parses STATUS, defers `gh issue close` until success-AND-CI-pass. On `CI_STATUS=fail` it prints a punt diagnostic and falls through to cleanup (no fix-cycle agent). On `pending|unknown` it defers and emits a re-run hint.
3. Control: sync attempts `git commit` on main, the `block-direct-main-commit` hook denies it, sync exits with the hook's deny envelope visible.

### Regression test for non-protected path

1. With `execution.main_protected: false`, on `main`, with a new GH issue: `/fix-issues sync`.
2. Expected: Direct path commits tracker mods on main, runs `gh issue close` for approvals. No worktree, no PR.

### Pre-existing unrelated edits regression (AC-P.10)

1. With `main_protected: true` on `main`, make an unrelated edit `echo "wip" >> docs/README.md`. Then `/fix-issues sync`.
2. Expected: after sync (Protected path), `git status -s` in the main repo still shows `M docs/README.md` — sync's path-scoped stash didn't touch it.

### `/land-pr` failure recovery (AC-P.3)

1. Force a `/land-pr` failure.
2. Expected: sync reports `/land-pr STATUS=… REASON=…`, exits non-zero, GH issues approved at step 3 remain OPEN, tracker mods sit in worktree (and stash, if pop failed).

### Conformance gate (CI)

`bash tests/test-skill-conformance.sh` exits 0. The cross-skill `/land-pr` caller check at lines 519-538 still passes.

### Canary recipe — follow-up plan, NOT a hard AC

A full end-to-end canary is **valuable but not blocking**. `/run-plan auto` can't autonomously run `/fix-issues sync` (sync is interactive). Making canary success a hard AC would deadlock auto-mode.

This plan ships a `status: draft` follow-up plan stub at `docs/plans/FIX_ISSUES_SYNC_CANARY.md` (committed by Phase 5 WI 5.6). The follow-up plan is a real artifact; its execution is async.

Recipe to emit on land:

```bash
mkdir -p /tmp/fix-issues-sync-canary && cd /tmp/fix-issues-sync-canary
git init -q && git commit --allow-empty -m "init" -q
gh repo create --private --source=. --remote=origin --push
mkdir -p .claude .zskills/issues
cat > .claude/zskills-config.json <<JSON
{"execution":{"main_protected":true}}
JSON
gh issue create --title "canary: bootstrap+protected sync" --body "synthetic"
# Run /fix-issues sync interactively and verify:
#  1. Bootstrap creates .zskills/issues/ISSUES_PLAN.md with frontmatter at col 0
#  2. Net-diff detector fires, routes to Protected path
#  3. Worktree created at /tmp/fix-issues-sync-canary-sync-YYYYMMDD-HHMMSS
#  4. PR opened with `sync: trackers <date>` title, no auto-close directive in body
#  5. After human-approves the merge on GitHub, gh issue close fires
```

---

## Plan Quality

**Drafting process.** /draft-plan (3 rounds) + /refine-plan (3 rounds) + 1 simplification pass. Per-round dispositions are auditable via git history; the table below summarises round counts.

**Key design decisions** (settled through review):

- **Framing c/d** (sync uses canonical monitor flow but skips fix-cycle agent dispatch). Sync passes neither `--auto` nor `--no-monitor`. On `CI_STATUS=fail`, the case-arm prints a punt diagnostic and terminates with `;;` — no fix-cycle agent dispatch, because the canonical agent template is specced for code+test PRs and is hazardous on content (would chase lint/snapshot noise into tracker entries). Sync is the first canonical-caller variant to skip fix-cycle; precedent absence is acknowledged.
- **Single-block Protected path.** The Protected path runs as one Bash invocation. Shell variables (`SYNC_TS`, `WT_PATH`, `APPROVED_LIST`, `BOOTSTRAP_NEW`, `NEW_RESEARCHED_COUNT`) persist within that invocation; no cross-block state files, no `proceed` sentinels, no preamble. Errors propagate via explicit `|| { handler; exit N; }` — set-e-free, no advisory STOP markers. This matches the canonical caller pattern at `skills/fix-issues/modes/pr.md:80-220` (also one block).
- **Bootstrap filename `ISSUES_PLAN.md`.** Existing sync glob, migration script, and skill-description all align on this name. Dashboard doesn't scan `issues_dir`, so filename has no dashboard effect.
- **Deferred close.** `gh issue close` runs only after `/land-pr` returns success AND CI passed (or contract-equivalent: `pass`, `none`, `skipped`, `not-monitored`, empty). On `pending|unknown` sync defers; on `fail` sync punts. State divergence (GH closed but tracker unmerged) is impossible by construction.
- **No auto-close directives in plan/refinement PRs.** GitHub auto-closes from both PR body and commit messages at squash-merge, regardless of negation/quoting. AC-P.9a/b enforce zero hits on the plan-landing PR; AC-P.9c enforces the directives are present on the implementation PR.
- **Smoke test wired into `tests/run-all.sh`.** Four structural invariants (column-0 heredoc, no `add -N`, stash pathspec, single-commit-site) gate landing. End-to-end canary deferred to a `status: draft` stub.

**Remaining concerns:**

- Smoke test covers structural slips only; end-to-end canary lives in the follow-up stub (`docs/plans/FIX_ISSUES_SYNC_CANARY.md`).
- `monitored` is reachable; `merged` is parsed defensively (unreachable without `--auto`). `*)` arms exit 1 fail-safe if `/land-pr` introduces a new STATUS or CI_STATUS value.
- DA3.5 residual: Protected-path resume hardcodes `/tmp/` rather than reading `worktree_root` from config. `create-worktree.sh` honours `worktree_root` for initial creation; resume into a worktree at a non-default root will fall through to create-worktree.sh (acceptable for v1 since resume requires same-second `SYNC_TS`).

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Outcome |
|-------|-------------------|---------------------------|---------|
| 1 (/draft-plan) | 15 | 14 | 23 fix + 4 justified (4 cross-dups) |
| 2 (/draft-plan) | 8 | 9 | 14 fix (3 cross-dups, 4 blockers fixed) |
| 3 (/draft-plan) | 2 polish | 5 substantive (2 blockers) | 3 fix + 1 doc + 1 residual |
| 4 (/refine-plan R1) | 7 defects + 3 meta + 4 stale-ref | 11 defects | 24 fix + 1 justified-not-fix |
| 5 (/refine-plan R2) | 8 (incl. framing pivot) | 9 | 14 fix + 3 folded; framing pivoted (a)→(c/d) |
| 6 (/refine-plan R3) | 3 | 5 | 5 fix + 2 residuals (N3.R3, DA3.5); all 4 verified blockers fixed |
| 7 (simplification) | — | — | Protected path collapsed to single bash block (~150 lines removed); state-file machinery deleted; AC-P.9 split into a/b/c/d (commit-message coverage); prose trim |

**Convergence grep (post-simplification).** `grep -nEi 'deterministic|hygiene[^a-z]|single-shot|caller is special|content-only|tracker edits are' docs/plans/FIX_ISSUES_SYNC_HARDENING.md`: line 17 (hygiene-rejection, preserved verbatim per task constraint); `content-only` hits in the "Sync uses canonical monitor flow" subsection and "What this plan does NOT do" bullet (fix-cycle-agent rationale, principled). No new unprincipled framings introduced.
