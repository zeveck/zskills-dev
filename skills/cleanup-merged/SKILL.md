---
name: cleanup-merged
disable-model-invocation: true
argument-hint: "[--dry-run | -n] [--review]"
description: >-
  Post-PR-merge local normalization: fetch-and-prune origin, switch off
  merged feature branches, pull main, and delete local branches whose
  upstream is gone or whose PR has merged. Bails on a dirty tree; skips
  branches with unpushed commits. --dry-run previews. --review classifies
  every local branch + worktree per merit rules and presents an
  interactive picker for cleanup actions.
metadata:
  version: "2026.05.21+c788ef"
---

# /cleanup-merged — Post-PR-merge local normalization

`/cleanup-merged` catches your local clone up after a PR merges on
GitHub. It does three things in order: fetch-and-prune, switch to the
main branch and pull, then delete local feature branches whose remotes
are gone or whose PRs are merged.

**Ultrathink throughout.**

Safe to run any time. The skill bails on a dirty working tree and
never deletes a branch with unpushed commits.

## Arguments

- `--dry-run` / `-n` — report what would happen without modifying
  anything. Useful to preview deletions on the first run.
- `--review` — opt into per-branch merit-based classification.
  Enumerates every local branch + worktree, classifies each per the rule
  table (see Phase 7), and prompts the user for actions via an
  alphabetized letter-keyed picker. Mutually exclusive with `--dry-run`
  (review mode is interactive — dry-run has no meaning).

## Phase 1 — Preflight

### WI 1.1 — Tool availability

```bash
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: /cleanup-merged requires git." >&2
  exit 1
fi

HAVE_GH=1
if ! command -v gh >/dev/null 2>&1; then
  HAVE_GH=0
  echo "NOTE: gh not on PATH; falling back to upstream-gone detection only." >&2
fi
```

### WI 1.2 — Argument parse

```bash
DRY_RUN=0
REVIEW=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --review) REVIEW=1 ;;
    *)
      echo "ERROR: unknown argument '$arg'. Usage: /cleanup-merged [--dry-run|-n] [--review]" >&2
      exit 2
      ;;
  esac
done

if [ "$DRY_RUN" -eq 1 ] && [ "$REVIEW" -eq 1 ]; then
  echo "ERROR: --dry-run and --review are mutually exclusive (review is interactive)." >&2
  exit 2
fi
```

### WI 1.3 — Locate main-repo root and detect main branch

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
cd "$MAIN_ROOT"

MAIN_BRANCH="main"
if ! git show-ref --verify --quiet refs/heads/main \
   && git show-ref --verify --quiet refs/heads/master; then
  MAIN_BRANCH="master"
fi
```

### WI 1.4 — Bail on dirty tree

Untracked files count as dirty: `/cleanup-merged` will `git checkout
main` and `git pull`, which would dump new untracked files back out or
could conflict with an uncommitted edit the user hasn't saved yet.

Review mode (`--review`) **does not** bail on a dirty tree — its job is
to inspect and surface dirty worktrees. It still avoids any destructive
operation on the dirty repo (no checkout, no pull, no auto-delete).

```bash
if [ "$REVIEW" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree is not clean. Commit, stash, or discard changes first." >&2
  git status --short >&2
  exit 3
fi
```

## Phase 2 — Fetch and prune

```bash
echo "Fetching origin with --prune..."
if ! git fetch origin --prune; then
  echo "ERROR: git fetch failed. Check network/auth." >&2
  exit 4
fi

# Drop orphaned worktree registrations (directories deleted from disk)
# so Phase 5's worktree→branch map reflects only live worktrees.
git worktree prune
```

`--prune` removes remote-tracking refs whose upstreams are gone. After
this, `git branch -vv` shows `: gone]` next to local branches whose
remote was deleted — the primary signal for detecting merged PRs when
GitHub's auto-delete-head-branches setting is on. `git worktree prune`
clears stale worktree entries so Phase 5 can reliably decide whether a
merged branch is still held by a live worktree.

## Phase 3 — Switch off a merged feature branch (if applicable)

If the current branch is not the main branch, check whether its PR is
merged or its upstream is gone. If so, switch to main so we can delete
the branch later. Review mode skips this phase (and Phases 4–6) and
jumps straight to Phase 7.

```bash
if [ "$REVIEW" -eq 1 ]; then
  # Review-mode skips Phases 3–6; jump to Phase 7 directly.
  SWITCHED=0
  ON_MAIN=0
  DELETED=0
  SKIPPED=0
fi

CURRENT=$(git rev-parse --abbrev-ref HEAD)
SWITCHED=0

if [ "$REVIEW" -eq 0 ] && [ "$CURRENT" != "$MAIN_BRANCH" ]; then
  UPSTREAM_GONE=0
  if git branch -vv | grep -qE "^\* $CURRENT .*: gone\]"; then
    UPSTREAM_GONE=1
  fi

  PR_STATE=""
  if [ "$HAVE_GH" -eq 1 ]; then
    PR_STATE=$(gh pr view "$CURRENT" --json state -q .state 2>/dev/null || echo "")
  fi

  if [ "$UPSTREAM_GONE" -eq 1 ] || [ "$PR_STATE" = "MERGED" ]; then
    REASON=$([ "$PR_STATE" = "MERGED" ] && echo "PR merged" || echo "upstream gone")
    echo "Current branch '$CURRENT' is safe to leave ($REASON). Switching to $MAIN_BRANCH..."
    if [ "$DRY_RUN" -eq 0 ]; then
      if ! git checkout "$MAIN_BRANCH"; then
        echo "ERROR: failed to checkout $MAIN_BRANCH." >&2
        exit 5
      fi
      SWITCHED=1
    fi
  else
    echo "Current branch '$CURRENT' is not merged (PR state: ${PR_STATE:-unknown}); staying here. Run from $MAIN_BRANCH or after merging to clean it up."
  fi
fi
```

## Phase 4 — Pull main

Only pull if we are on the main branch. A dry-run skips the pull
because we promised not to modify anything. Review mode skips this
phase entirely.

```bash
ON_MAIN=0
[ "$(git rev-parse --abbrev-ref HEAD)" = "$MAIN_BRANCH" ] && ON_MAIN=1

if [ "$REVIEW" -eq 0 ] && [ "$ON_MAIN" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "Pulling $MAIN_BRANCH..."
  if ! git pull origin "$MAIN_BRANCH"; then
    echo "ERROR: git pull failed." >&2
    exit 5
  fi
fi
```

## Phase 5 — Scan and delete merged branches

Review mode skips this phase — its per-branch action logic lives in
Phase 7 instead (the `if [ "$REVIEW" -eq 1 ]; then : else …` guard
below wraps the original loop).

For every local branch other than the main branch and the currently
checked-out branch, check the same two signals (upstream gone, PR
merged). Skip branches with unpushed commits unless the upstream is
gone — if the remote is gone, the commits were either squash-merged or
the branch was abandoned; either way, the local commits match no live
ref.

This phase is worktree-aware: if a merged branch is held by a worktree,
`git branch -D` will refuse. Before attempting the delete, the loop
maps each branch to its worktree (if any) via `git worktree list
--porcelain`. A worktree that is clean and is not the main repo itself
is removed first (`git worktree remove`); a dirty worktree, or the main
repo's own worktree, causes the branch to be skipped with a warning so
the user can intervene manually.

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
DELETED=0
SKIPPED=0

if [ "$REVIEW" -eq 1 ]; then
  : # Phase 5 main loop is bypassed in review mode (handled by Phase 7).
else
while IFS= read -r branch; do
  [ -z "$branch" ] && continue
  [ "$branch" = "$MAIN_BRANCH" ] && continue
  [ "$branch" = "$CURRENT" ] && continue

  UPSTREAM_GONE=0
  if git branch -vv | grep -qE "^  $branch .*: gone\]"; then
    UPSTREAM_GONE=1
  fi

  PR_STATE=""
  if [ "$HAVE_GH" -eq 1 ]; then
    PR_STATE=$(gh pr view "$branch" --json state -q .state 2>/dev/null || echo "")
  fi

  MERGED=0
  if [ "$UPSTREAM_GONE" -eq 1 ] || [ "$PR_STATE" = "MERGED" ]; then
    MERGED=1
  fi

  [ "$MERGED" -eq 0 ] && continue

  # Unpushed-commit guard (squash-merge still counts commits as unpushed
  # because the squash SHA is different). Only honor the guard when the
  # upstream is NOT gone — a gone upstream plus PR=MERGED means the
  # commits reached main via squash.
  UNPUSHED=""
  if [ "$UPSTREAM_GONE" -eq 0 ]; then
    UNPUSHED=$(git log "$branch" --not --remotes --oneline 2>/dev/null | head -1)
  fi

  if [ -n "$UNPUSHED" ]; then
    echo "  SKIP   $branch (has unpushed commits; delete manually with 'git branch -D $branch' if intentional)"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  # Issue #516: ahead-count gate. `gh pr view` is sticky after merge, so
  # PR=MERGED + ahead>0 means the local branch may carry post-merge
  # commits that would be silently reaped by `git branch -D`. Only gate
  # the PR=MERGED path (upstream-gone implies squash-merge, where ahead>0
  # is expected and the unpushed-commit guard above already handles the
  # un-squashed case).
  if [ "$PR_STATE" = "MERGED" ] && [ "$UPSTREAM_GONE" = "0" ]; then
    AHEAD=$(git rev-list --count "$MAIN_BRANCH..$branch" 2>/dev/null || echo 0)
    [ -z "$AHEAD" ] && AHEAD=0
    if [ "$AHEAD" -gt 0 ]; then
      echo "  SKIP   $branch (PR merged but branch has $AHEAD commits not on main — investigate; do not auto-remove)"
      SKIPPED=$((SKIPPED+1))
      continue
    fi
  fi

  # Worktree detection: does any registered worktree hold $branch?
  # `git worktree list --porcelain` emits blocks like:
  #     worktree /abs/path
  #     HEAD <sha>
  #     branch refs/heads/<name>
  #     (blank line)
  # Detached-HEAD worktrees have no "branch" line; the awk filter below
  # pairs every "worktree" line with its following "branch" line (if any)
  # and drops the unpaired detached ones.
  WORKTREE_FOR_BRANCH=""
  while IFS= read -r wt_path && IFS= read -r wt_branch; do
    if [ "${wt_branch#branch refs/heads/}" = "$branch" ]; then
      WORKTREE_FOR_BRANCH="${wt_path#worktree }"
      break
    fi
  done < <(git worktree list --porcelain | awk '/^worktree /{wt=$0} /^branch /{print wt; print $0}')

  REASON=$([ "$PR_STATE" = "MERGED" ] && echo "PR merged" || echo "upstream gone")

  if [ -n "$WORKTREE_FOR_BRANCH" ]; then
    if [ "$WORKTREE_FOR_BRANCH" = "$MAIN_ROOT" ]; then
      echo "WARN: merged branch $branch is checked out in main repo; checkout main before cleanup-merged." >&2
      SKIPPED=$((SKIPPED+1))
      continue
    fi

    WT_DIRTY=$(git -C "$WORKTREE_FOR_BRANCH" status --porcelain 2>/dev/null)
    if [ -n "$WT_DIRTY" ]; then
      echo "WARN: worktree at $WORKTREE_FOR_BRANCH holds merged branch $branch but has uncommitted changes — inspect and remove manually." >&2
      SKIPPED=$((SKIPPED+1))
      continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  WOULD-REMOVE-WORKTREE $WORKTREE_FOR_BRANCH (holds $branch)"
      echo "  WOULD-DELETE $branch ($REASON)"
      DELETED=$((DELETED+1))
      continue
    fi

    if ! git worktree remove "$WORKTREE_FOR_BRANCH"; then
      echo "  FAILED  $branch (git worktree remove $WORKTREE_FOR_BRANCH exited non-zero)" >&2
      SKIPPED=$((SKIPPED+1))
      continue
    fi
    echo "  REMOVED-WORKTREE $WORKTREE_FOR_BRANCH (held $branch)"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  WOULD-DELETE $branch ($REASON)"
    DELETED=$((DELETED+1))
  else
    if git branch -D "$branch" >/dev/null; then
      echo "  DELETED $branch ($REASON)"
      DELETED=$((DELETED+1))
    else
      echo "  FAILED  $branch (git branch -D exited non-zero)" >&2
      SKIPPED=$((SKIPPED+1))
    fi
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)
fi  # /REVIEW guard
```

After the worktree-pruning loop, sweep any stale `/fix-issues` claim
directories. When a PR merges via the GitHub web UI or a manual
`gh pr merge` (bypassing `/land-pr`'s `STATUS=merged` release path), the
per-issue claim under `.zskills/claims/issue-NNN/` leaks until its TTL
expires. `claim-issue.sh sweep` is the documented admin sweep — it walks
all claims, releases any whose age exceeds the TTL (default 7200s) or
whose dir mtime is older than 30s without a `claim.json` (crash window),
and is idempotent + always exits 0. `|| true` because sweep is best-
effort housekeeping; the surrounding cleanup-merged success criteria
should not regress on a stale-claim sweep failure.

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/fix-issues/scripts/claim-issue.sh" sweep || true
```

## Phase 6 — Summary

Review mode skips this phase; its summary is part of Phase 7's table
+ action report.

```bash
if [ "$REVIEW" -eq 0 ]; then
  echo ""
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "cleanup-merged (dry-run): would delete $DELETED, skip $SKIPPED. Nothing was modified."
  else
    echo "cleanup-merged: deleted $DELETED branches, skipped $SKIPPED."
    if [ "$SWITCHED" -eq 1 ]; then
      echo "(switched to $MAIN_BRANCH and pulled.)"
    elif [ "$ON_MAIN" -eq 1 ]; then
      echo "(on $MAIN_BRANCH, pulled latest.)"
    fi
  fi
  exit 0
fi
```

## Phase 7 — Review mode (--review)

When `--review` is set, enumerate every local branch + worktree,
classify each per the rule table below (first-match-wins), present an
alphabetized table with letter IDs and verdicts, then prompt for action.

### Classification rules (first-match wins)

| # | Condition | Verdict | Rationale |
|---|---|---|---|
| 1 | Worktree is `locked` | **KEEP** | Live process; never touch |
| 2 | Branch name matches `cleanup.long_running_patterns` config glob | **KEEP** | Explicitly preserved |
| 11 | PR=MERGED AND commits ahead of main | **DECIDE** | `gh pr view` is sticky after merge; ahead>0 means possible post-merge commits (issue #516) — surface, don't auto-remove |
| 3 | (upstream-gone OR PR=MERGED) AND worktree clean | **REMOVE** | Current `/cleanup-merged` default action |
| 4 | (upstream-gone OR PR=MERGED) AND worktree dirty | **DECIDE** | Merged but uncommitted changes — inspect first |
| 5 | Commits ahead AND PR=OPEN | **KEEP** | Active in-flight PR |
| 6 | Commits ahead AND no PR AND clean | **MAYBE** | Drafted-but-not-pushed; review intent |
| 7 | 0 commits ahead AND no PR AND clean AND `.landed status != landed` | **DECIDE** | Abandoned/failed sprint state |
| 8 | 0 commits ahead AND no PR AND clean AND no `.landed` | **REMOVE** | Empty stub — typical orphaned cron artifact |
| 9 | 0 commits ahead AND no PR AND tree dirty | **DECIDE** | Partial work or orphan; inspect diff |
| 10 | Commits ahead AND tree dirty | **DECIDE** | Active uncommitted work |
| — | (fallthrough) | **DECIDE** | Unclassified; manual review |

### WI 7.1 — Load long_running_patterns from config

Default empty array. Read via Python (zskills uses Python json, no jq).

```bash
if [ "$REVIEW" -eq 1 ]; then
  CONFIG_FILE=".claude/zskills-config.json"
  LONG_RUNNING_PATTERNS=()
  if [ -f "$CONFIG_FILE" ]; then
    PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
    if [ -n "$PYTHON" ]; then
      while IFS= read -r p; do
        [ -n "$p" ] && LONG_RUNNING_PATTERNS+=("$p")
      done < <("$PYTHON" -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    pats = cfg.get("cleanup", {}).get("long_running_patterns", []) or []
    for p in pats:
        print(p)
except Exception:
    pass
' "$CONFIG_FILE")
    fi
  fi
fi
```

### WI 7.2 — Enumerate branches + worktrees and classify

Walk every local branch (`git for-each-ref refs/heads/`) and every
worktree (`git worktree list --porcelain`). Build a unified row set
keyed by `(worktree_path, branch_name)`. A worktree-less branch yields
a row with `worktree=<none>`; a detached-HEAD worktree (no branch)
yields a row with `branch=<detached>`.

For each row, compute these signals:

- `LOCKED` — worktree has a `locked` line in `git worktree list --porcelain`.
- `AHEAD` — `git rev-list --count $MAIN_BRANCH..$branch` (0 if missing).
- `UPSTREAM_GONE` — `git branch -vv` shows `: gone]` for the branch.
- `PR_STATE` — `gh pr view $branch --json state` (empty if no PR).
- `DIRTY` — `git -C $worktree status --porcelain` non-empty.
- `LANDED_STATUS` — parse `status:` from `<worktree>/.landed`, or empty.

Then walk the rule table top-to-bottom; the first matching rule sets
`VERDICT` and `RULE_NUM`. `RULE_DESC` is a short one-liner from the
table.

```bash
if [ "$REVIEW" -eq 1 ]; then
  # Build worktree → (locked, branch) map via porcelain output.
  # Format blocks: "worktree /path", then optional "HEAD <sha>",
  # optional "branch refs/heads/<name>" OR "detached", optional "locked".
  declare -A WT_BRANCH
  declare -A WT_LOCKED
  WT_PATHS=()

  current_wt=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.*)$ ]]; then
      current_wt="${BASH_REMATCH[1]}"
      WT_PATHS+=("$current_wt")
      WT_BRANCH["$current_wt"]="<detached>"
      WT_LOCKED["$current_wt"]=0
    elif [[ "$line" =~ ^branch\ refs/heads/(.*)$ ]]; then
      WT_BRANCH["$current_wt"]="${BASH_REMATCH[1]}"
    elif [[ "$line" == "locked" || "$line" == locked\ * ]]; then
      WT_LOCKED["$current_wt"]=1
    fi
  done < <(git worktree list --porcelain)

  # Build branch → worktree reverse map.
  declare -A BRANCH_WT
  for wt in "${WT_PATHS[@]}"; do
    br="${WT_BRANCH[$wt]}"
    [ "$br" = "<detached>" ] && continue
    BRANCH_WT["$br"]="$wt"
  done

  # Snapshot `git branch -vv` once for fast UPSTREAM_GONE lookup.
  BRANCH_VV=$(git branch -vv)

  # Glob-match a branch name against the long_running_patterns array.
  # Uses bash's [[ "$name" == $pattern ]] glob (NOT regex).
  matches_long_running() {
    local name="$1" pat
    for pat in "${LONG_RUNNING_PATTERNS[@]:-}"; do
      [ -z "$pat" ] && continue
      # shellcheck disable=SC2053
      if [[ "$name" == $pat ]]; then
        return 0
      fi
    done
    return 1
  }

  # Classifier — given branch + worktree-path + signals, sets
  # VERDICT and RULE_NUM and RULE_DESC.
  classify() {
    local branch="$1" wt="$2" locked="$3" ahead="$4" upstream_gone="$5"
    local pr_state="$6" dirty="$7" landed_status="$8"

    # Rule 1
    if [ "$locked" = "1" ]; then
      VERDICT="KEEP"; RULE_NUM=1
      RULE_DESC="worktree locked; live process — never touch"
      return
    fi
    # Rule 2
    if [ "$branch" != "<detached>" ] && [ "$branch" != "<none>" ]; then
      if matches_long_running "$branch"; then
        VERDICT="KEEP"; RULE_NUM=2
        RULE_DESC="matches cleanup.long_running_patterns"
        return
      fi
    fi

    local merged=0
    if [ "$upstream_gone" = "1" ] || [ "$pr_state" = "MERGED" ]; then
      merged=1
    fi
    local has_dirty=0
    [ -n "$dirty" ] && has_dirty=1

    # Rule 3a (issue #516) — PR=MERGED + ahead>0 means the local branch
    # has commits not on main. `gh pr view` is sticky after merge, so a
    # diverged branch still reports MERGED. Surface for manual review
    # instead of silently reaping post-merge commits. Squash-merge alone
    # ALSO shows ahead>0 (different SHA), but distinguishing post-merge
    # divergence from squash-merge requires content comparison the
    # classifier doesn't do; the safe action in either case is DECIDE.
    if [ "$pr_state" = "MERGED" ] && [ "$ahead" -gt 0 ]; then
      VERDICT="DECIDE"; RULE_NUM=11
      RULE_DESC="PR merged but branch has $ahead commits not on main — investigate"
      return
    fi
    # Rule 3
    if [ "$merged" = "1" ] && [ "$has_dirty" = "0" ]; then
      VERDICT="REMOVE"; RULE_NUM=3
      RULE_DESC="merged (upstream-gone or PR=MERGED), worktree clean"
      return
    fi
    # Rule 4
    if [ "$merged" = "1" ] && [ "$has_dirty" = "1" ]; then
      VERDICT="DECIDE"; RULE_NUM=4
      RULE_DESC="merged but uncommitted changes — inspect first"
      return
    fi
    # Rule 5
    if [ "$ahead" -gt 0 ] && [ "$pr_state" = "OPEN" ]; then
      VERDICT="KEEP"; RULE_NUM=5
      RULE_DESC="active in-flight PR"
      return
    fi
    # Rule 6
    if [ "$ahead" -gt 0 ] && [ -z "$pr_state" ] && [ "$has_dirty" = "0" ]; then
      VERDICT="MAYBE"; RULE_NUM=6
      RULE_DESC="drafted but not pushed — review intent"
      return
    fi
    # Rule 7
    if [ "$ahead" = "0" ] && [ -z "$pr_state" ] && [ "$has_dirty" = "0" ] \
       && [ -n "$landed_status" ] && [ "$landed_status" != "landed" ] \
       && [ "$landed_status" != "full" ]; then
      VERDICT="DECIDE"; RULE_NUM=7
      RULE_DESC="abandoned/failed sprint state (.landed=$landed_status)"
      return
    fi
    # Rule 8
    if [ "$ahead" = "0" ] && [ -z "$pr_state" ] && [ "$has_dirty" = "0" ] \
       && [ -z "$landed_status" ]; then
      VERDICT="REMOVE"; RULE_NUM=8
      RULE_DESC="empty stub — typical orphaned cron artifact"
      return
    fi
    # Rule 9
    if [ "$ahead" = "0" ] && [ -z "$pr_state" ] && [ "$has_dirty" = "1" ]; then
      VERDICT="DECIDE"; RULE_NUM=9
      RULE_DESC="0-ahead + dirty — partial work or orphan; inspect diff"
      return
    fi
    # Rule 10
    if [ "$ahead" -gt 0 ] && [ "$has_dirty" = "1" ]; then
      VERDICT="DECIDE"; RULE_NUM=10
      RULE_DESC="commits ahead AND tree dirty — active uncommitted work"
      return
    fi
    # Fallthrough
    VERDICT="DECIDE"; RULE_NUM=0
    RULE_DESC="unclassified; manual review"
  }

  # Build row list: every branch (with optional worktree) plus every
  # detached worktree without a branch ref.
  ROWS=()  # Each row: VERDICT|RULE_NUM|RULE_DESC|PATH|BRANCH|AHEAD|PR_STATE|DIRTY_COUNT|LANDED_STATUS
  CLASSIFIED_BRANCHES=()

  while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    [ "$branch" = "$MAIN_BRANCH" ] && continue

    wt="${BRANCH_WT[$branch]:-}"
    locked=0
    if [ -n "$wt" ]; then
      locked="${WT_LOCKED[$wt]:-0}"
    fi

    ahead=$(git rev-list --count "$MAIN_BRANCH..$branch" 2>/dev/null || echo 0)
    [ -z "$ahead" ] && ahead=0

    upstream_gone=0
    if echo "$BRANCH_VV" | grep -qE "^[* ]+ ?$branch\b.*: gone\]"; then
      upstream_gone=1
    fi

    pr_state=""
    if [ "$HAVE_GH" -eq 1 ]; then
      pr_state=$(gh pr view "$branch" --json state -q .state 2>/dev/null || echo "")
    fi

    dirty=""
    dirty_count=0
    if [ -n "$wt" ]; then
      dirty=$(git -C "$wt" status --porcelain 2>/dev/null)
      [ -n "$dirty" ] && dirty_count=$(printf '%s\n' "$dirty" | wc -l | tr -d ' ')
    fi

    landed_status=""
    if [ -n "$wt" ] && [ -f "$wt/.landed" ]; then
      landed_status=$(grep -E '^status:' "$wt/.landed" 2>/dev/null \
        | head -1 | sed -E 's/^status:[[:space:]]*//')
    fi

    classify "$branch" "$wt" "$locked" "$ahead" "$upstream_gone" \
             "$pr_state" "$dirty" "$landed_status"

    ROWS+=("$VERDICT|$RULE_NUM|$RULE_DESC|${wt:-<no-worktree>}|$branch|$ahead|${pr_state:-none}|$dirty_count|${landed_status:-<none>}")
    CLASSIFIED_BRANCHES+=("$branch")
  done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

  # Detached-HEAD worktrees: not represented by any branch, but still
  # worth surfacing in the table.
  for wt in "${WT_PATHS[@]}"; do
    [ "${WT_BRANCH[$wt]}" != "<detached>" ] && continue
    locked="${WT_LOCKED[$wt]:-0}"
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null)
    dirty_count=0
    [ -n "$dirty" ] && dirty_count=$(printf '%s\n' "$dirty" | wc -l | tr -d ' ')
    landed_status=""
    if [ -f "$wt/.landed" ]; then
      landed_status=$(grep -E '^status:' "$wt/.landed" 2>/dev/null \
        | head -1 | sed -E 's/^status:[[:space:]]*//')
    fi
    classify "<detached>" "$wt" "$locked" 0 0 "" "$dirty" "$landed_status"
    ROWS+=("$VERDICT|$RULE_NUM|$RULE_DESC|$wt|<detached>|0|none|$dirty_count|${landed_status:-<none>}")
  done
fi
```

### WI 7.3 — Render the alphabetized table

Sort rows by worktree path (stable, deterministic), assign letter IDs
A-Z then AA, AB, … for >26 rows. Print the verdict/path/details/rule
table; then a one-line summary by verdict.

```bash
if [ "$REVIEW" -eq 1 ]; then
  # Sort rows alphabetically by the PATH field (column 4 after the
  # verb). We use Python sort for stable Unicode behaviour.
  PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
  SORTED_ROWS=()
  while IFS= read -r r; do
    [ -n "$r" ] && SORTED_ROWS+=("$r")
  done < <(printf '%s\n' "${ROWS[@]}" | "$PYTHON" -c '
import sys
rows = [l.rstrip("\n") for l in sys.stdin if l.strip()]
rows.sort(key=lambda r: r.split("|")[3])
for r in rows:
    print(r)
')

  # Letter-ID generator: A, B, …, Z, AA, AB, …, AZ, BA, …
  letter_for() {
    local n="$1" out=""
    while [ "$n" -ge 0 ]; do
      out="$(printf "\\$(printf '%03o' $((65 + n % 26)))")$out"
      n=$((n / 26 - 1))
    done
    printf '%s' "$out"
  }

  echo ""
  echo "/cleanup-merged --review"
  echo ""

  declare -A ROW_BY_LETTER
  declare -A SUGGESTED_BY_LETTER
  KEEP_N=0; MAYBE_N=0; DECIDE_N=0; REMOVE_N=0
  i=0
  for row in "${SORTED_ROWS[@]}"; do
    IFS='|' read -r verdict rule_num rule_desc path branch ahead pr_state dirty_count landed_status <<<"$row"
    letter=$(letter_for "$i")
    ROW_BY_LETTER["$letter"]="$row"
    SUGGESTED_BY_LETTER["$letter"]="$verdict"

    dirty_phrase="clean"
    [ "$dirty_count" -gt 0 ] && dirty_phrase="dirty:${dirty_count} file$([ "$dirty_count" -ne 1 ] && echo s)"
    pr_phrase="no PR"
    [ "$pr_state" != "none" ] && pr_phrase="PR=$pr_state"

    printf '  %s. %-6s %s\n' "$letter" "$verdict" "$path"
    printf '       [%s, %s ahead, %s, %s' "$branch" "$ahead" "$pr_phrase" "$dirty_phrase"
    [ "$landed_status" != "<none>" ] && printf ', .landed=%s' "$landed_status"
    printf ']\n'
    printf '       → rule %s: %s\n' "$rule_num" "$rule_desc"

    case "$verdict" in
      KEEP)   KEEP_N=$((KEEP_N+1)) ;;
      MAYBE)  MAYBE_N=$((MAYBE_N+1)) ;;
      DECIDE) DECIDE_N=$((DECIDE_N+1)) ;;
      REMOVE) REMOVE_N=$((REMOVE_N+1)) ;;
    esac
    i=$((i+1))
  done

  TOTAL=${#SORTED_ROWS[@]}
  echo ""
  echo "$TOTAL total: $KEEP_N KEEP, $MAYBE_N MAYBE, $DECIDE_N DECIDE, $REMOVE_N REMOVE"
fi
```

### WI 7.4 — Interactive picker

Read one line of input from the user. Recognized forms:

- blank (just Enter) OR `all-suggested` → apply all rows whose suggested
  verdict is `REMOVE`. Other verdicts left alone.
- `<letter>:<verb>` pairs separated by whitespace (e.g.,
  `A:remove D:keep F:remove`) → per-row override. Recognized verbs:
  `remove`, `keep`, `skip` (alias of `keep`). Unrecognized letters
  produce a warning and are skipped.
- `none` or empty stdin (e.g. pipe closed) → exit without action.

```bash
if [ "$REVIEW" -eq 1 ]; then
  echo ""
  echo "Pick action:"
  echo "  [Enter] / all-suggested  apply suggested REMOVEs only"
  echo "  <letter>:<verb> ...      per-row override (verbs: remove, keep, skip)"
  echo "  none                     exit without action"
  printf '  > '

  USER_INPUT=""
  if [ -t 0 ]; then
    IFS= read -r USER_INPUT || USER_INPUT="none"
  else
    # Non-interactive (CI, pipe): default to dry-listing only.
    USER_INPUT="none"
  fi

  USER_INPUT_TRIM=$(printf '%s' "$USER_INPUT" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')

  declare -A ACTION_BY_LETTER
  if [ -z "$USER_INPUT_TRIM" ] || [ "$USER_INPUT_TRIM" = "all-suggested" ]; then
    for letter in "${!SUGGESTED_BY_LETTER[@]}"; do
      if [ "${SUGGESTED_BY_LETTER[$letter]}" = "REMOVE" ]; then
        ACTION_BY_LETTER["$letter"]="remove"
      fi
    done
  elif [ "$USER_INPUT_TRIM" = "none" ]; then
    echo "Exiting without action."
    exit 0
  else
    # Parse <letter>:<verb> pairs.
    for token in $USER_INPUT_TRIM; do
      if [[ "$token" =~ ^([A-Za-z]+):([a-z]+)$ ]]; then
        letter="${BASH_REMATCH[1]}"
        verb="${BASH_REMATCH[2]}"
        letter=$(printf '%s' "$letter" | tr '[:lower:]' '[:upper:]')
        if [ -z "${ROW_BY_LETTER[$letter]:-}" ]; then
          echo "  WARN: unknown letter '$letter' — skipped." >&2
          continue
        fi
        case "$verb" in
          remove) ACTION_BY_LETTER["$letter"]="remove" ;;
          keep|skip) ACTION_BY_LETTER["$letter"]="keep" ;;
          *)
            echo "  WARN: unknown verb '$verb' for $letter — skipped." >&2
            ;;
        esac
      else
        echo "  WARN: malformed token '$token' (want <letter>:<verb>) — skipped." >&2
      fi
    done
  fi

  # Apply REMOVE actions. KEEP/skip are no-ops.
  R_DONE=0
  R_FAILED=0
  for letter in "${!ACTION_BY_LETTER[@]}"; do
    action="${ACTION_BY_LETTER[$letter]}"
    [ "$action" != "remove" ] && continue
    row="${ROW_BY_LETTER[$letter]}"
    IFS='|' read -r verdict rule_num rule_desc path branch ahead pr_state dirty_count landed_status <<<"$row"

    # Worktree removal — only if path is a registered worktree
    # distinct from MAIN_ROOT. Dirty worktrees require --force or
    # manual cleanup; for safety we skip them with a warning.
    if [ "$path" != "<no-worktree>" ] && [ "$path" != "$MAIN_ROOT" ]; then
      if [ "$dirty_count" -gt 0 ]; then
        echo "  SKIP $letter: $path is dirty ($dirty_count file(s)); inspect manually." >&2
        R_FAILED=$((R_FAILED+1))
        continue
      fi
      if git worktree remove "$path"; then
        echo "  REMOVED-WORKTREE $path"
      else
        echo "  FAILED to remove worktree $path" >&2
        R_FAILED=$((R_FAILED+1))
        continue
      fi
    fi

    # Branch deletion (only if a real branch and not main / current).
    if [ "$branch" != "<detached>" ] && [ "$branch" != "$MAIN_BRANCH" ] \
       && [ "$branch" != "$(git rev-parse --abbrev-ref HEAD)" ]; then
      if git branch -D "$branch" >/dev/null 2>&1; then
        echo "  DELETED branch $branch"
      else
        echo "  WARN: could not delete branch $branch (may not exist locally)" >&2
      fi
    fi

    R_DONE=$((R_DONE+1))
  done

  echo ""
  echo "cleanup-merged --review: $R_DONE action(s) applied, $R_FAILED skipped/failed."
  exit 0
fi
```

## Exit codes

| rc | Meaning |
|----|---------|
| 0 | Success (or dry-run complete, or `--review` finished) |
| 1 | Missing required tool (git) |
| 2 | Bad argument (or mutually-exclusive flag combo) |
| 3 | Dirty working tree — refuses to proceed (default mode only; `--review` tolerates) |
| 4 | `git fetch` failed |
| 5 | `git checkout` or `git pull` failed |

## Coexistence with other skills

- `/commit land` — post-landing cleanup for cherry-pick mode worktrees.
- `/cleanup-merged` — post-PR-merge cleanup for PR mode (this skill).

Different modes, different cleanup. Cherry-pick commits land on main
inline; PR merges are async (human clicks "merge" on GitHub), so PR
mode needs a separate normalize step.

## When to run

Any time a PR has merged on GitHub and you want your local clone to
reflect it. Typical cadence:

- After `/quickfix`, `/do pr`, `/commit pr`, or any PR-mode skill,
  once the PR has merged.
- Before starting a new feature so you're branching off up-to-date
  main.
- As a cleanup sweep when `git branch` shows stale feature branches
  piling up.

Running it with nothing to do is safe and fast — it fetches, confirms
main is current, finds no merged branches, and exits.

If a merged branch is still held by a clean worktree, `/cleanup-merged`
will remove the worktree before deleting the branch. A dirty worktree
is left untouched with a warning — inspect and remove it manually. The
main repo's own worktree is never removed; switch to the main branch
first if the merged branch is checked out there.
