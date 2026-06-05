---
name: cleanup-merged
disable-model-invocation: true
argument-hint: "[apply] [local | remote | all] [<branch>...]"
description: >-
  Post-PR-merge local normalization: fetch-and-prune origin, switch off
  merged feature branches, pull main, and delete local branches whose
  upstream is gone, whose PR has merged, or whose tip is fully contained
  in main (0 commits ahead). Preview by default — run
  `/cleanup-merged apply` to execute. `local` (default) / `remote` / `all`
  pick the scope; pass explicit branch names to narrow the candidate set.
  `--force` overrides the merged-check + unpushed guard for branches you
  explicitly name. Protected branches from config are NEVER deleted (even
  with `--force`) — they are always skipped.
metadata:
  version: "2026.06.05+4a9c2a"
---

# /cleanup-merged — Post-PR-merge local normalization

`/cleanup-merged` catches your local clone up after a PR merges on
GitHub. It does three things in order: fetch-and-prune, switch to the
main branch and pull, then delete local feature branches whose remotes
are gone or whose PRs are merged.

**Ultrathink throughout.**

**Preview by default.** Bare invocation shows what would be deleted.
Run `/cleanup-merged apply` to execute.

Safe to run any time. The skill bails on a dirty working tree and
never deletes a branch with unpushed commits.

## Interface

```
/cleanup-merged                       — preview local (show what would be deleted)
/cleanup-merged apply                 — execute local deletions (skip protected)
/cleanup-merged local                 — preview local (explicit local token)
/cleanup-merged local apply           — execute local deletions (skip protected)
/cleanup-merged remote                — preview remote branch deletions
/cleanup-merged remote apply          — execute remote deletions (skip protected)
/cleanup-merged all                   — preview both local + remote
/cleanup-merged all apply             — execute both (skip protected)
/cleanup-merged apply <br> <br>...    — narrow to NAMED local branches, then apply
/cleanup-merged remote apply <br>...  — narrow to NAMED remote branches, then apply
/cleanup-merged apply --force <br>... — override merged-check + unpushed guard for NAMED branches
```

- **Preview is default** — safe to run, self-documenting. Output shows
  the plan and ends with "run `/cleanup-merged apply` to execute."
- **`apply`** — positional token meaning "I saw the preview, do it."
  Terraform precedent.
- **`local`** — explicit scope token for local-branch cleanup. This is
  also the default when no scope token (`remote`/`all`) is given, so
  bare `/cleanup-merged` and `/cleanup-merged local` are equivalent
  (the token exists for symmetry with `remote`/`all`).
- **`remote`** — adds `git push origin --delete` for branches whose PRs
  are confirmed MERGED via `gh pr view`. Never deletes branches with
  open PRs.
- **`all`** — both local + remote.
- **Branch names** — any positional token that is not a recognized
  keyword is treated as an explicit branch NAME. Names **narrow** the
  candidate set: only the named branches are considered (the full-scan
  is skipped). Names do **not** bypass safety — every named branch is
  still subject to the merged-confirmation, the unpushed-commits guard,
  and the protected-skip. Names without `apply` → preview only.
- **`--force`** — overrides ONLY the merged-check and the unpushed-commits
  guard, and ONLY for branches you EXPLICITLY named. It lets you delete
  a named branch that is not yet confirmed merged (local: `git branch
  -D`). `--force` has no effect on un-named branches (the full-scan path
  ignores it) and **NEVER** overrides the protected-skip — see below.
  Dashed form (issue #810) — matches the `--force` convention in `/do`
  and `/work-on-plans`.
- **Protected branches** — config field in `.claude/zskills-config.json`:
  ```json
  { "cleanup": { "protected_branches": ["docs/run-order-guide"] } }
  ```
  Preview marks these as `PROTECTED (config)` and `apply` skips them
  automatically. **This is sacrosanct: a protected branch is NEVER
  deleted, even when named explicitly WITH `--force`.** Naming a protected
  branch (with or without `--force`) emits a loud `PROTECTED (config) — refusing
  to delete even with --force` notice and skips it. There is no flag, token,
  or naming combination that can delete a config-protected branch.

### Migration aliases

For one release cycle, `--dry-run` / `-n` map to preview (the new
default) and `--review` maps to `all` (preview both). Both emit a
deprecation notice. Remove after 2026-07-01.

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

Positional tokens: `apply`, `local`, `remote`, `all`. Dashed
safety-gate override: `--force`. Order-independent. Any positional that
is NOT a recognized keyword (and not a migration alias) is collected as
an explicit **branch name**. Legacy flags `--dry-run`, `-n`, `--review`
are accepted as migration aliases.

```bash
APPLY=0
FORCE=0
SCOPE="local"  # "local", "remote", or "all"
NAMED_BRANCHES=()  # explicit branch names — narrow the candidate set

for arg in "$@"; do
  case "$arg" in
    apply)  APPLY=1 ;;
    local)  SCOPE="local" ;;
    remote) SCOPE="remote" ;;
    all)    SCOPE="all" ;;
    # `--force` MUST appear BEFORE the `--*|-*` unknown-flag catchall,
    # else it would be rejected as an unknown flag. Issue #810: dashed
    # form normalised across /do, /work-on-plans, /cleanup-merged.
    --force) FORCE=1 ;;
    --dry-run|-n)
      echo "DEPRECATED: --dry-run/-n is now the default. Just run /cleanup-merged (no args) for preview."
      ;;
    --review)
      echo "DEPRECATED: --review is replaced by /cleanup-merged all. Treating as 'all'."
      SCOPE="all"
      ;;
    --*|-*)
      echo "ERROR: unknown flag '$arg'. Usage: /cleanup-merged [apply] [local | remote | all] [--force] [<branch>...]" >&2
      exit 2
      ;;
    *)
      # Any non-keyword positional is an explicit branch name.
      NAMED_BRANCHES+=("$arg")
      ;;
  esac
done

DO_LOCAL=0
DO_REMOTE=0
case "$SCOPE" in
  local)  DO_LOCAL=1 ;;
  remote) DO_REMOTE=1 ;;
  all)    DO_LOCAL=1; DO_REMOTE=1 ;;
esac

# When explicit branch names are given, they NARROW the candidate set:
# only the named branches are considered (the full ref-scan is skipped).
# `--force` only takes effect for explicitly-named branches.
HAVE_NAMES=0
[ "${#NAMED_BRANCHES[@]}" -gt 0 ] && HAVE_NAMES=1

is_named() {
  local branch="$1"
  [ "$HAVE_NAMES" -eq 0 ] && return 1
  local nb
  for nb in "${NAMED_BRANCHES[@]}"; do
    [ "$branch" = "$nb" ] && return 0
  done
  return 1
}

if [ "$FORCE" -eq 1 ] && [ "$HAVE_NAMES" -eq 0 ]; then
  echo "NOTE: '--force' has no effect without explicit branch names; it only overrides the merged-check / unpushed guard for branches you name. Ignoring." >&2
  FORCE=0
fi
```

**`--force` can never reach a protected branch.** The protected-skip
(`is_protected`) is evaluated FIRST in every deletion path, before any
`--force`-gated logic, and emits a loud refusal notice. There is no code
path where `FORCE=1` bypasses `is_protected`. This is the load-bearing
safety invariant of this skill.

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

### WI 1.4 — Load protected branches from config

Read `cleanup.protected_branches` from `.claude/zskills-config.json`.
Default empty array.

```bash
CONFIG_FILE=".claude/zskills-config.json"
PROTECTED_BRANCHES=()
if [ -f "$CONFIG_FILE" ]; then
  # Resolve a WORKING Python 3 (probe-RUN each candidate: on Windows
  # `command -v python3` finds a non-executable MS Store stub). Honors
  # ZSKILLS_PYTHON; empty if none works.
  zskills_resolve_python() {
    local cand
    for cand in "${ZSKILLS_PYTHON:-}" python3 python; do
      [ -n "$cand" ] || continue
      command -v "$cand" >/dev/null 2>&1 || continue
      if "$cand" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' >/dev/null 2>&1; then
        command -v "$cand"; return 0
      fi
    done
    return 1
  }
  PYTHON="$(zskills_resolve_python || true)"
  if [ -n "$PYTHON" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && PROTECTED_BRANCHES+=("$p")
    done < <("$PYTHON" -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    pats = cfg.get("cleanup", {}).get("protected_branches", []) or []
    for p in pats:
        print(p)
except Exception:
    pass
' "$CONFIG_FILE")
  fi
fi

is_protected() {
  local branch="$1"
  for pb in "${PROTECTED_BRANCHES[@]:-}"; do
    [ -z "$pb" ] && continue
    if [ "$branch" = "$pb" ]; then
      return 0
    fi
  done
  return 1
}
```

### WI 1.5 — Bail on dirty tree

Untracked files count as dirty: `/cleanup-merged` will `git checkout
main` and `git pull`, which would dump new untracked files back out or
could conflict with an uncommitted edit the user hasn't saved yet.

```bash
if [ -n "$(git status --porcelain)" ]; then
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
# so Phase 4's worktree->branch map reflects only live worktrees.
git worktree prune
```

`--prune` removes remote-tracking refs whose upstreams are gone. After
this, `git branch -vv` shows `: gone]` next to local branches whose
remote was deleted — the primary signal for detecting merged PRs when
GitHub's auto-delete-head-branches setting is on. `git worktree prune`
clears stale worktree entries so Phase 4 can reliably decide whether a
merged branch is still held by a live worktree.

## Phase 3 — Switch off a merged feature branch (if applicable)

If the current branch is not the main branch, check whether its PR is
merged or its upstream is gone. If so, switch to main so we can delete
the branch later. In preview mode (no `apply`), report what would
happen without switching.

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
SWITCHED=0

if [ "$CURRENT" != "$MAIN_BRANCH" ]; then
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
    if [ "$APPLY" -eq 1 ]; then
      echo "Current branch '$CURRENT' is safe to leave ($REASON). Switching to $MAIN_BRANCH..."
      if ! git checkout "$MAIN_BRANCH"; then
        echo "ERROR: failed to checkout $MAIN_BRANCH." >&2
        exit 5
      fi
      SWITCHED=1
    else
      echo "  WOULD-SWITCH from '$CURRENT' to $MAIN_BRANCH ($REASON)"
    fi
  else
    echo "Current branch '$CURRENT' is not merged (PR state: ${PR_STATE:-unknown}); staying here. Run from $MAIN_BRANCH or after merging to clean it up."
  fi
fi
```

## Phase 4 — Pull main

Only pull if we are on the main branch. Preview mode skips the pull
because we promised not to modify anything.

```bash
ON_MAIN=0
[ "$(git rev-parse --abbrev-ref HEAD)" = "$MAIN_BRANCH" ] && ON_MAIN=1

if [ "$ON_MAIN" -eq 1 ] && [ "$APPLY" -eq 1 ]; then
  echo "Pulling $MAIN_BRANCH..."
  if ! git pull origin "$MAIN_BRANCH"; then
    echo "ERROR: git pull failed." >&2
    exit 5
  fi
fi
```

## Phase 5 — Local branch scan

For every local branch other than the main branch and the currently
checked-out branch, check three signals: upstream gone, PR merged, or
the tip is fully contained in main (0 commits ahead —
`git merge-base --is-ancestor <branch> main`, issue #781). The
contained-in-main check is purely local and needs no `gh` call, so it
is evaluated first and the PR-state lookup is skipped when it holds.
Skip branches with unpushed commits unless the upstream is gone or the
branch is contained in main — if the remote is gone, the commits were
either squash-merged or the branch was abandoned; if the branch is
contained in main it carries zero unique commits; either way the local
commits match a ref already on main (the `git branch -d` below is the
losslessness backstop).

This phase is worktree-aware: if a merged branch is held by a worktree,
`git branch -D` will refuse. Before attempting the delete, the loop
maps each branch to its worktree (if any) via `git worktree list
--porcelain`. A worktree that is clean and is not the main repo itself
is removed first (`git worktree remove`); a dirty worktree, or the main
repo's own worktree, causes the branch to be skipped with a warning so
the user can intervene manually.

Protected branches (from `cleanup.protected_branches` config) are
marked `PROTECTED (config)` in preview and skipped in apply.

```bash
CURRENT=$(git rev-parse --abbrev-ref HEAD)
LOCAL_DELETED=0
LOCAL_SKIPPED=0
LOCAL_PROTECTED=0
LOCAL_PRESERVED=0
LOCAL_CANDIDATES=()  # branch names that are merged and deletable

# Preview-mode grouped-output accumulators. Each entry is
# "<branch>\t<suffix>" — split on the literal tab when emitting. Apply
# mode keeps per-line progress and does not read these arrays.
# Tracked counts (LOCAL_DELETED, LOCAL_SKIPPED, LOCAL_PROTECTED,
# LOCAL_PRESERVED) are updated in BOTH preview and apply paths so the
# summary in Phase 7 is always accurate.
LOCAL_TO_DELETE=()
LOCAL_PRESERVED_LIST=()
LOCAL_TO_SKIP=()
LOCAL_PROTECTED_LIST=()
LOCAL_DELETE_WT_COUNT=0     # of LOCAL_TO_DELETE, how many drag a worktree
LOCAL_PRESERVED_WT_COUNT=0  # of LOCAL_PRESERVED_LIST, how many have a worktree

if [ "$DO_LOCAL" -eq 1 ]; then
  echo ""
  echo "--- Local branches ---"

  while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    [ "$branch" = "$MAIN_BRANCH" ] && continue
    [ "$branch" = "$CURRENT" ] && continue

    # When explicit names were given, narrow to only those branches.
    if [ "$HAVE_NAMES" -eq 1 ] && ! is_named "$branch"; then
      continue
    fi

    # Worktree detection: does any registered worktree hold $branch?
    # Moved up so it is available to every classification arm (preserved
    # branches need to know if they have a worktree for the suffix; skip
    # arms inherit it; delete arms still use it for the worktree-remove
    # path).
    WORKTREE_FOR_BRANCH=""
    while IFS= read -r wt_path && IFS= read -r wt_branch; do
      if [ "${wt_branch#branch refs/heads/}" = "$branch" ]; then
        WORKTREE_FOR_BRANCH="${wt_path#worktree }"
        break
      fi
    done < <(git worktree list --porcelain | awk '/^worktree /{wt=$0} /^branch /{print wt; print $0}')

    # ── Protected branch check — ALWAYS FIRST, NEVER OVERRIDABLE ──────
    # This is the load-bearing safety invariant: a config-protected
    # branch is never deleted, no matter what. `--force` is evaluated only
    # AFTER this guard and cannot reach it. If the user explicitly named
    # a protected branch (with or without --force), emit a loud refusal.
    if is_protected "$branch"; then
      if is_named "$branch"; then
        if [ "$FORCE" -eq 1 ]; then
          PROT_NOTE="PROTECTED (config) — refusing to delete even with --force"
          [ "${APPLY:-0}" -eq 1 ] && echo "  PROTECTED (config) $branch — refusing to delete even with --force"
        else
          PROT_NOTE="PROTECTED (config) — refusing to delete (named explicitly)"
          [ "${APPLY:-0}" -eq 1 ] && echo "  PROTECTED (config) $branch — refusing to delete (named explicitly)"
        fi
      else
        PROT_NOTE="PROTECTED (config)"
        [ "${APPLY:-0}" -eq 1 ] && echo "  PROTECTED (config) $branch"
      fi
      LOCAL_PROTECTED_LIST+=("$branch"$'\t'"$PROT_NOTE")
      LOCAL_PROTECTED=$((LOCAL_PROTECTED+1))
      continue
    fi

    NAMED_FORCE=0
    if [ "$FORCE" -eq 1 ] && is_named "$branch"; then
      NAMED_FORCE=1
    fi

    UPSTREAM_GONE=0
    if git branch -vv | grep -qE "^  $branch .*: gone\]"; then
      UPSTREAM_GONE=1
    fi

    # Issue #781: a branch whose tip is fully contained in main (0 commits
    # ahead — `git merge-base --is-ancestor branch main` true) carries zero
    # unique commits, so deleting it loses nothing (reflog-recoverable
    # regardless). This is a LOCAL check needing NO `gh` call, so detect it
    # before the PR-state lookup and skip the gh round-trip when it holds.
    CONTAINED=0
    if git merge-base --is-ancestor "$branch" "$MAIN_BRANCH" 2>/dev/null; then
      CONTAINED=1
    fi

    PR_STATE=""
    if [ "$HAVE_GH" -eq 1 ] && [ "$CONTAINED" -eq 0 ]; then
      PR_STATE=$(gh pr view "$branch" --json state -q .state 2>/dev/null || echo "")
    fi

    MERGED=0
    if [ "$UPSTREAM_GONE" -eq 1 ] || [ "$PR_STATE" = "MERGED" ] || [ "$CONTAINED" -eq 1 ]; then
      MERGED=1
    fi

    # Plain-English PR-state phrase for the preserved/preview suffix.
    # Empty PR_STATE = `no PR`; CLOSED-not-merged = `closed PR`;
    # OPEN = `open PR`. (MERGED never reaches here as a preserved class.)
    case "$PR_STATE" in
      CLOSED) PR_PHRASE="closed PR" ;;
      OPEN)   PR_PHRASE="open PR" ;;
      "")     PR_PHRASE="no PR" ;;
      *)      PR_PHRASE="PR ${PR_STATE,,}" ;;
    esac

    # Merged-check: a named branch under `--force` skips the merged
    # requirement (the user vouched for it explicitly). Un-named branches
    # (full-scan path) without merged confirmation are PRESERVED in
    # preview output (so the user sees them) and silently skipped in apply.
    if [ "$MERGED" -eq 0 ]; then
      if [ "$NAMED_FORCE" -eq 1 ]; then
        [ "${APPLY:-0}" -eq 1 ] && echo "  FORCE  $branch (not confirmed merged; deleting because explicitly named with --force)"
      else
        # Classify as preserved (not-merged). Suffix: PR phrase, plus
        # `, has worktree` when a worktree holds the branch (it stays).
        if [ -n "$WORKTREE_FOR_BRANCH" ]; then
          PRESERVED_SUFFIX="${PR_PHRASE}, has worktree"
          LOCAL_PRESERVED_WT_COUNT=$((LOCAL_PRESERVED_WT_COUNT+1))
        else
          PRESERVED_SUFFIX="${PR_PHRASE}"
        fi
        LOCAL_PRESERVED_LIST+=("$branch"$'\t'"$PRESERVED_SUFFIX")
        LOCAL_PRESERVED=$((LOCAL_PRESERVED+1))
        continue
      fi
    fi

    # Unpushed-commit guard (squash-merge still counts commits as unpushed
    # because the squash SHA is different). Only honor the guard when the
    # upstream is NOT gone — a gone upstream plus PR=MERGED means the
    # commits reached main via squash. A named branch under `--force`
    # overrides this guard too.
    # A contained-in-main branch (issue #781) carries no commits not already
    # on main, so the unpushed guard cannot apply — the `git branch -d` below
    # is the losslessness backstop. Skip the guard for the contained class.
    UNPUSHED=""
    if [ "$UPSTREAM_GONE" -eq 0 ] && [ "$NAMED_FORCE" -eq 0 ] && [ "$CONTAINED" -eq 0 ]; then
      UNPUSHED=$(git log "$branch" --not --remotes --oneline 2>/dev/null | head -1)
    fi

    if [ -n "$UNPUSHED" ]; then
      SKIP_NOTE="has unpushed commits"
      LOCAL_TO_SKIP+=("$branch"$'\t'"$SKIP_NOTE")
      [ "${APPLY:-0}" -eq 1 ] && echo "  SKIP   $branch (has unpushed commits; delete manually with 'git branch -D $branch' if intentional, or re-run with '--force' and the branch name)"
      LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
      continue
    fi

    # Issue #516 / #755: post-merge-work gate. `gh pr view` is sticky
    # after merge, so PR=MERGED on a branch with a tip != main is normal
    # under squash-merge (the squash commit on main has a different SHA,
    # so `git rev-list --count main..branch` is ALWAYS > 0). The raw
    # ahead-count gate therefore skipped essentially every squash-merged
    # branch (#755). Instead, compare the local branch tip to the merged
    # PR's recorded head SHA:
    #   - tip == PR head  -> no post-merge work -> safe to delete (fall
    #     through; this is the normal squash-merged case).
    #   - tip is a DESCENDANT of PR head -> the branch carries commits
    #     made after the PR head -> genuine post-merge work -> SKIP
    #     (preserves the #516 protection precisely).
    #   - PR head unavailable (gh hiccup) -> fall back conservatively to
    #     the old ahead-count behavior so a gh failure never causes an
    #     unsafe delete.
    if [ "$PR_STATE" = "MERGED" ] && [ "$UPSTREAM_GONE" = "0" ] && [ "$NAMED_FORCE" -eq 0 ]; then
      PR_HEAD=$(gh pr view "$branch" --json headRefOid -q .headRefOid 2>/dev/null || echo "")
      LOCAL_TIP=$(git rev-parse "$branch" 2>/dev/null || echo "")
      if [ -n "$PR_HEAD" ]; then
        if [ "$LOCAL_TIP" != "$PR_HEAD" ] && git merge-base --is-ancestor "$PR_HEAD" "$LOCAL_TIP" 2>/dev/null; then
          SKIP_NOTE="PR merged, local tip ahead — investigate"
          LOCAL_TO_SKIP+=("$branch"$'\t'"$SKIP_NOTE")
          [ "${APPLY:-0}" -eq 1 ] && echo "  SKIP   $branch (PR merged but local tip is ahead of the merged PR head — post-merge work; investigate, do not auto-remove)"
          LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
          continue
        fi
        # tip == PR head (or diverged-but-not-descendant): no post-merge
        # commits beyond the PR head — safe to delete, fall through.
      else
        # gh could not report the PR head: fall back to the conservative
        # ahead-count gate so a gh hiccup never triggers an unsafe delete.
        AHEAD=$(git rev-list --count "$MAIN_BRANCH..$branch" 2>/dev/null || echo 0)
        [ -z "$AHEAD" ] && AHEAD=0
        if [ "$AHEAD" -gt 0 ]; then
          SKIP_NOTE="PR merged, gh head unavailable, $AHEAD commits not on main — investigate"
          LOCAL_TO_SKIP+=("$branch"$'\t'"$SKIP_NOTE")
          [ "${APPLY:-0}" -eq 1 ] && echo "  SKIP   $branch (PR merged but PR head unavailable from gh and branch has $AHEAD commits not on main — investigate; do not auto-remove)"
          LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
          continue
        fi
      fi
    fi

    # Apply-mode reason string (per-line progress in apply path).
    if [ "$NAMED_FORCE" -eq 1 ] && [ "$MERGED" -eq 0 ]; then
      REASON="forced (named, not confirmed merged)"
    elif [ "$PR_STATE" = "MERGED" ]; then
      REASON="PR merged"
    elif [ "$UPSTREAM_GONE" -eq 1 ]; then
      REASON="upstream gone"
    else
      # Issue #781: contained-in-main (0 ahead) — the only remaining way
      # MERGED=1 with no PR-merged / upstream-gone signal.
      REASON="contained in main"
    fi

    # Worktree action: a delete candidate may carry a worktree to remove.
    if [ -n "$WORKTREE_FOR_BRANCH" ]; then
      if [ "$WORKTREE_FOR_BRANCH" = "$MAIN_ROOT" ]; then
        SKIP_NOTE="checked out in main repo — checkout main first"
        LOCAL_TO_SKIP+=("$branch"$'\t'"$SKIP_NOTE")
        echo "  WARN: merged branch $branch is checked out in main repo; checkout main before cleanup-merged." >&2
        LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
        continue
      fi

      WT_DIRTY=$(git -C "$WORKTREE_FOR_BRANCH" status --porcelain 2>/dev/null)
      if [ -n "$WT_DIRTY" ]; then
        SKIP_NOTE="worktree has uncommitted changes — inspect manually"
        LOCAL_TO_SKIP+=("$branch"$'\t'"$SKIP_NOTE")
        echo "  WARN: worktree at $WORKTREE_FOR_BRANCH holds merged branch $branch but has uncommitted changes — inspect and remove manually." >&2
        LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
        continue
      fi

      if [ "$APPLY" -eq 0 ]; then
        LOCAL_TO_DELETE+=("$branch"$'\t'"and worktree")
        LOCAL_DELETE_WT_COUNT=$((LOCAL_DELETE_WT_COUNT+1))
        LOCAL_DELETED=$((LOCAL_DELETED+1))
        LOCAL_CANDIDATES+=("$branch")
        continue
      fi

      if ! git worktree remove "$WORKTREE_FOR_BRANCH"; then
        SKIP_NOTE="git worktree remove failed"
        LOCAL_TO_SKIP+=("$branch"$'\t'"$SKIP_NOTE")
        echo "  FAILED  $branch (git worktree remove $WORKTREE_FOR_BRANCH exited non-zero)" >&2
        LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
        continue
      fi
      echo "  REMOVED-WORKTREE $WORKTREE_FOR_BRANCH (held $branch)"
      LOCAL_DELETE_WT_COUNT=$((LOCAL_DELETE_WT_COUNT+1))
    fi

    if [ "$APPLY" -eq 0 ]; then
      # Preview path: no per-line WOULD-DELETE. Accumulate; grouped output
      # is emitted at the end of this phase.
      LOCAL_TO_DELETE+=("$branch"$'\t'"")
      LOCAL_DELETED=$((LOCAL_DELETED+1))
      LOCAL_CANDIDATES+=("$branch")
    else
      # Delete-flag selection. The default path only reaches here for
      # branches already CONFIRMED safe: PR=MERGED, upstream-gone, or
      # contained-in-main (issue #781, 0 ahead). Squash-merge means the
      # branch tip is NOT a fast-forward ancestor of main, so `git branch
      # -d` would wrongly refuse it. Use `-d` when the branch IS an
      # ancestor of main (clean — this is exactly the contained-in-main
      # class, deleted losslessly), and `-D` for the confirmed-merged-but-
      # not-ancestor (squash) case and for the explicit `--force` path. `-D`
      # is NEVER reached for an un-confirmed, un-named branch (the
      # merged-check above guarantees MERGED=1 unless NAMED_FORCE=1).
      # Issue #816: `-d` ALSO requires the branch be fully merged into its
      # configured upstream; when the remote-tracking ref still holds the
      # un-squashed PR head, `-d` refuses. In that case, if the branch is
      # an ancestor of main (the local content IS on main), escalate to
      # `-D` — lossless by construction.
      if [ "$NAMED_FORCE" -eq 1 ]; then
        DEL_FLAG="-D"   # user vouched for this named branch explicitly
      elif git merge-base --is-ancestor "$branch" "$MAIN_BRANCH" 2>/dev/null; then
        DEL_FLAG="-d"   # truly merged into main — safe non-force delete
      else
        DEL_FLAG="-D"   # confirmed merged via PR/upstream-gone (squash)
      fi
      if git branch "$DEL_FLAG" "$branch" >/dev/null; then
        echo "  DELETED $branch ($REASON)"
        LOCAL_DELETED=$((LOCAL_DELETED+1))
      elif [ "$DEL_FLAG" = "-d" ] && git merge-base --is-ancestor "$branch" "$MAIN_BRANCH" 2>/dev/null; then
        # Issue #816: -d refused — typically because the branch has a configured
        # upstream whose remote-tracking ref still holds the un-squashed PR head
        # (different SHA from the squash on main). But ancestor-of-main is the
        # strongest safety signal git has — the local content IS on main, so -D
        # loses nothing. Escalate.
        if git branch -D "$branch" >/dev/null; then
          echo "  DELETED $branch ($REASON; escalated -d → -D after upstream-divergence refusal)"
          LOCAL_DELETED=$((LOCAL_DELETED+1))
        else
          echo "  FAILED  $branch (escalation to -D also failed)" >&2
          LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
        fi
      else
        echo "  FAILED  $branch (git branch $DEL_FLAG exited non-zero)" >&2
        LOCAL_SKIPPED=$((LOCAL_SKIPPED+1))
      fi
    fi
  done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

  # Preview grouped output. Apply mode already emitted per-line progress
  # inside the loop above; the summary in Phase 7 prints the counters.
  if [ "$APPLY" -eq 0 ]; then
    emit_group() {
      # emit_group <header-prefix> <count> <count-suffix> <array-name>
      local header_prefix="$1" count="$2" count_suffix="$3" array_name="$4"
      [ "$count" -le 0 ] && return 0
      echo ""
      echo "${header_prefix}${count}${count_suffix}"
      eval "local _entries=(\"\${${array_name}[@]}\")"
      local entry name suffix
      for entry in "${_entries[@]}"; do
        name="${entry%%$'\t'*}"
        suffix="${entry#*$'\t'}"
        if [ -n "$suffix" ] && [ "$suffix" != "$entry" ]; then
          printf '  %-45s %s\n' "$name" "$suffix"
        else
          printf '  %s\n' "$name"
        fi
      done
    }
    emit_group "Local — " "$LOCAL_DELETED"   " to delete (PR merged):"    LOCAL_TO_DELETE
    emit_group "Local — " "$LOCAL_PRESERVED" " preserved (not merged):"   LOCAL_PRESERVED_LIST
    emit_group "Local — " "$LOCAL_SKIPPED"   " to skip:"                  LOCAL_TO_SKIP
    emit_group "Local — " "$LOCAL_PROTECTED" " protected:"                LOCAL_PROTECTED_LIST
  fi
fi
```

When a PR merges via the GitHub web UI or a manual `gh pr merge`
(bypassing `/land-pr`'s `STATUS=merged` release path), the per-issue
claim under `.zskills/claims/issue-NNN/` is left held. This is harmless:
`/fix-issues` claims are released at land-or-abandon, not aged out (the
TTL/sweep auto-reaper was removed in #739, same precedent as #684 for
plan claims). A later `/fix-issues` fire detects the leaked claim via
`acquire`'s EEXIST contract and skips that issue cleanly; if a claim is
genuinely stuck (the issue's PR will never land), clear it manually with
`claim-issue.sh release <N> --require-pipeline <id>`.

## Phase 6 — Remote branch scan

When `remote` or `all` scope is active, scan remote-tracking branches
for merged-PR candidates. For each `origin/<branch>` that is not the
main branch:

1. Check if the branch has a MERGED PR via `gh pr view`.
2. Skip branches with OPEN PRs — never delete an active branch.
3. Skip protected branches (from config).
4. In preview, the branch appears under the `Remote — N to delete (PR
   merged):` section; in apply, run `git push origin --delete <branch>`
   and emit `DELETED-REMOTE` per line as it executes.

Requires `gh` — if `gh` is unavailable and `remote`/`all` scope is
requested, warn and skip.

```bash
REMOTE_DELETED=0
REMOTE_SKIPPED=0
REMOTE_PROTECTED=0
REMOTE_PRESERVED=0

# Preview-mode grouped-output accumulators (remote phase). Same
# tab-delimited "<branch>\t<suffix>" convention as the local phase.
# Apply path still emits per-line progress.
REMOTE_TO_DELETE=()
REMOTE_PRESERVED_LIST=()
REMOTE_PROTECTED_LIST=()

if [ "$DO_REMOTE" -eq 1 ]; then
  echo ""
  echo "--- Remote branches ---"

  if [ "$HAVE_GH" -eq 0 ]; then
    echo "WARN: gh not available; remote branch cleanup requires gh for PR-state gating. Skipping." >&2
  else
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      # Strip "origin/" prefix
      branch="${ref#origin/}"

      [ "$branch" = "$MAIN_BRANCH" ] && continue
      [ "$branch" = "HEAD" ] && continue

      # When explicit names were given, narrow to only those branches.
      if [ "$HAVE_NAMES" -eq 1 ] && ! is_named "$branch"; then
        continue
      fi

      # ── Protected branch check — ALWAYS FIRST, NEVER OVERRIDABLE ────
      # Same sacrosanct invariant as the local path: `--force` can never
      # reach a protected branch.
      if is_protected "$branch"; then
        if is_named "$branch" && [ "$FORCE" -eq 1 ]; then
          RPROT_NOTE="PROTECTED (config) — refusing to delete even with --force"
          [ "${APPLY:-0}" -eq 1 ] && echo "  PROTECTED (config) origin/$branch — refusing to delete even with --force"
        elif is_named "$branch"; then
          RPROT_NOTE="PROTECTED (config) — refusing to delete (named explicitly)"
          [ "${APPLY:-0}" -eq 1 ] && echo "  PROTECTED (config) origin/$branch — refusing to delete (named explicitly)"
        else
          RPROT_NOTE="PROTECTED (config)"
          [ "${APPLY:-0}" -eq 1 ] && echo "  PROTECTED (config) origin/$branch"
        fi
        REMOTE_PROTECTED_LIST+=("origin/$branch"$'\t'"$RPROT_NOTE")
        REMOTE_PROTECTED=$((REMOTE_PROTECTED+1))
        continue
      fi

      NAMED_FORCE=0
      if [ "$FORCE" -eq 1 ] && is_named "$branch"; then
        NAMED_FORCE=1
      fi

      PR_STATE=$(gh pr view "$branch" --json state -q .state 2>/dev/null || echo "")

      # Plain-English PR phrase for the preserved-remote suffix (only the
      # PR class signals matter on the remote side — no worktree, no
      # contained-in-main, no upstream-gone).
      case "$PR_STATE" in
        CLOSED) RPR_PHRASE="closed PR" ;;
        OPEN)   RPR_PHRASE="open PR" ;;
        "")     RPR_PHRASE="no PR" ;;
        *)      RPR_PHRASE="PR ${PR_STATE,,}" ;;
      esac

      if [ "$PR_STATE" = "OPEN" ] && [ "$NAMED_FORCE" -eq 0 ]; then
        REMOTE_PRESERVED_LIST+=("origin/$branch"$'\t'"$RPR_PHRASE")
        REMOTE_PRESERVED=$((REMOTE_PRESERVED+1))
        continue  # Active PR — never delete (unless explicitly named + --force)
      fi

      if [ "$PR_STATE" != "MERGED" ] && [ "$NAMED_FORCE" -eq 0 ]; then
        REMOTE_PRESERVED_LIST+=("origin/$branch"$'\t'"$RPR_PHRASE")
        REMOTE_PRESERVED=$((REMOTE_PRESERVED+1))
        continue  # Only delete branches with confirmed MERGED PRs
      fi

      if [ "$NAMED_FORCE" -eq 1 ] && [ "$PR_STATE" != "MERGED" ]; then
        RREASON="forced (named, PR state: ${PR_STATE:-unknown})"
      else
        RREASON="PR merged"
      fi

      if [ "$APPLY" -eq 0 ]; then
        # Preview: accumulate; grouped output emitted at end of phase.
        REMOTE_TO_DELETE+=("origin/$branch"$'\t'"")
        REMOTE_DELETED=$((REMOTE_DELETED+1))
      else
        if git push origin --delete "$branch" 2>/dev/null; then
          echo "  DELETED-REMOTE origin/$branch ($RREASON)"
          REMOTE_DELETED=$((REMOTE_DELETED+1))
        else
          echo "  FAILED  origin/$branch (git push origin --delete exited non-zero)" >&2
          REMOTE_SKIPPED=$((REMOTE_SKIPPED+1))
        fi
      fi
    done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin/)
  fi

  # Preview grouped output for the remote phase. Apply mode keeps the
  # per-line progress emitted inside the loop above.
  if [ "$APPLY" -eq 0 ]; then
    emit_remote_group() {
      local header_prefix="$1" count="$2" count_suffix="$3" array_name="$4"
      [ "$count" -le 0 ] && return 0
      echo ""
      echo "${header_prefix}${count}${count_suffix}"
      eval "local _entries=(\"\${${array_name}[@]}\")"
      local entry name suffix
      for entry in "${_entries[@]}"; do
        name="${entry%%$'\t'*}"
        suffix="${entry#*$'\t'}"
        if [ -n "$suffix" ] && [ "$suffix" != "$entry" ]; then
          printf '  %-45s %s\n' "$name" "$suffix"
        else
          printf '  %s\n' "$name"
        fi
      done
    }
    emit_remote_group "Remote — " "$REMOTE_DELETED"   " to delete (PR merged):"  REMOTE_TO_DELETE
    emit_remote_group "Remote — " "$REMOTE_PRESERVED" " preserved (not merged):" REMOTE_PRESERVED_LIST
    emit_remote_group "Remote — " "$REMOTE_PROTECTED" " protected:"              REMOTE_PROTECTED_LIST
  fi
fi
```

## Phase 7 — Summary

```bash
# build_summary_line: render one summary row ("Local: ..." or
# "Remote: ..."). Sub-clauses with a zero count are dropped so the line
# stays terse on quiet days. Verb tense flips for apply (`deleted` vs
# `delete`); the `(N with worktrees)` parenthetical is local-only.
build_summary_line() {
  local label="$1" tense="$2" deleted="$3" wt_in_delete="$4" \
        preserved="$5" wt_in_preserved="$6" skipped="$7" protected="$8"
  local verb_delete verb_preserve verb_skip verb_protected
  if [ "$tense" = "past" ]; then
    verb_delete="deleted"; verb_preserve="preserved"
    verb_skip="skipped"; verb_protected="protected"
  else
    verb_delete="delete"; verb_preserve="preserved"
    verb_skip="skip"; verb_protected="protected"
  fi
  local parts=()
  if [ "$deleted" -gt 0 ]; then
    if [ "$wt_in_delete" -gt 0 ]; then
      parts+=("$deleted $verb_delete ($wt_in_delete with worktrees)")
    else
      parts+=("$deleted $verb_delete")
    fi
  fi
  if [ "$preserved" -gt 0 ]; then
    if [ "$wt_in_preserved" -gt 0 ]; then
      parts+=("$preserved $verb_preserve ($wt_in_preserved with worktrees)")
    else
      parts+=("$preserved $verb_preserve")
    fi
  fi
  [ "$skipped" -gt 0 ]   && parts+=("$skipped $verb_skip")
  [ "$protected" -gt 0 ] && parts+=("$protected $verb_protected")
  local n=${#parts[@]}
  if [ "$n" -eq 0 ]; then
    printf '  %-8s nothing\n' "$label:"
  else
    printf '  %-8s %s' "$label:" "${parts[0]}"
    local i
    for ((i=1; i<n; i++)); do
      printf ', %s' "${parts[i]}"
    done
    printf '\n'
  fi
}

echo ""
if [ "$APPLY" -eq 0 ]; then
  # Preview summary — emit the "Summary:" block, then the apply hint.
  TOTAL_WOULD=0
  echo "Summary:"
  if [ "$DO_LOCAL" -eq 1 ]; then
    build_summary_line "Local" present \
      "$LOCAL_DELETED" "$LOCAL_DELETE_WT_COUNT" \
      "$LOCAL_PRESERVED" "$LOCAL_PRESERVED_WT_COUNT" \
      "$LOCAL_SKIPPED" "$LOCAL_PROTECTED"
    TOTAL_WOULD=$((TOTAL_WOULD + LOCAL_DELETED))
  fi
  if [ "$DO_REMOTE" -eq 1 ]; then
    # Remote has no worktree concept — pass 0 for the wt sub-counts so the
    # parenthetical never renders.
    build_summary_line "Remote" present \
      "$REMOTE_DELETED" 0 \
      "$REMOTE_PRESERVED" 0 \
      "$REMOTE_SKIPPED" "$REMOTE_PROTECTED"
    TOTAL_WOULD=$((TOTAL_WOULD + REMOTE_DELETED))
  fi
  echo ""

  if [ "$TOTAL_WOULD" -gt 0 ]; then
    # Build the apply command hint
    APPLY_CMD="/cleanup-merged"
    [ "$SCOPE" != "local" ] && APPLY_CMD="$APPLY_CMD $SCOPE"
    APPLY_CMD="$APPLY_CMD apply"
    echo "Run \`$APPLY_CMD\` to execute."
  else
    echo "Nothing to clean up."
  fi
else
  # Apply summary — same shape, past-tense verbs.
  echo "Summary:"
  if [ "$DO_LOCAL" -eq 1 ]; then
    build_summary_line "Local" past \
      "$LOCAL_DELETED" "$LOCAL_DELETE_WT_COUNT" \
      "$LOCAL_PRESERVED" "$LOCAL_PRESERVED_WT_COUNT" \
      "$LOCAL_SKIPPED" "$LOCAL_PROTECTED"
  fi
  if [ "$DO_REMOTE" -eq 1 ]; then
    build_summary_line "Remote" past \
      "$REMOTE_DELETED" 0 \
      "$REMOTE_PRESERVED" 0 \
      "$REMOTE_SKIPPED" "$REMOTE_PROTECTED"
  fi

  if [ "$SWITCHED" -eq 1 ]; then
    echo "(switched to $MAIN_BRANCH and pulled.)"
  elif [ "$ON_MAIN" -eq 1 ]; then
    echo "(on $MAIN_BRANCH, pulled latest.)"
  fi
fi
exit 0
```

## Exit codes

| rc | Meaning |
|----|---------|
| 0 | Success (or preview complete) |
| 1 | Missing required tool (git) |
| 2 | Bad argument |
| 3 | Dirty working tree — refuses to proceed |
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

- After `/do pr`, `/commit pr`, or any PR-mode skill,
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
