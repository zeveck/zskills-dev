---
name: quickfix
disable-model-invocation: true
argument-hint: "[<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests]"
description: >-
  Ship an in-flight edit (or short agent-authored fix) as a PR without a
  worktree. Two auto-detected modes: user-edited (dirty tree + description →
  carry edits to a branch and commit) and agent-dispatched (clean tree +
  description → model-layer dispatch performs edits, then we commit). PR-only:
  requires execution.landing == "pr". Runs testing.unit_cmd (aligned with
  full_cmd to satisfy the project pre-commit hook), commits, pushes, and
  creates a PR via gh. No worktree; no .landed marker.
  Usage: /quickfix [<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests]
---

# /quickfix — In-Flight Fix → PR

`/quickfix` turns the current main checkout (with or without dirty edits)
into a one-commit PR without leaving main. No worktree. No cherry-pick.
Fire-and-forget: commit, push, open PR, print URL, exit.

**Ultrathink throughout.**

## Modes (auto-detected)

| DIRTY_FILES empty? | DESCRIPTION | Mode | Action |
|--------------------|-------------|------|--------|
| No  | non-empty | **user-edited** | pick up dirty tree, commit under description |
| No  | empty     | — | exit 2 (user-edited mode requires a description) |
| Yes | non-empty | **agent-dispatched** | model-layer dispatch of an agent to implement, then commit |
| Yes | empty     | — | exit 2 (need edits or description) |

The mode is discovered by looking at the working tree **before** branching,
so dirty edits made on main are carried across (via `git checkout -b`) into
the new feature branch.

## Coexistence with other skills

- `/do pr` — fresh worktree, agent-dispatched, for larger tasks.
- `/commit pr` — already on a feature branch with commits ready.
- `/fix-issues pr` — batches of GitHub-issue-driven fixes in per-issue worktrees.
- `/quickfix` — on **main** with in-flight edits (or clean main + description).

Pick `/quickfix` when the edit is small enough that leaving main is more
ceremony than the change is worth, but a PR is still required.

## Entry self-assertion (WI 1.1)

At entry, when the SDK exposes `$SKILL_SELF` (path to this file), assert
that the frontmatter still carries `disable-model-invocation: true`:

```bash
if [ -n "${SKILL_SELF:-}" ] && [ -f "$SKILL_SELF" ]; then
  if ! grep -q '^disable-model-invocation: true$' "$SKILL_SELF"; then
    echo "ERROR: /quickfix SKILL.md missing 'disable-model-invocation: true'" >&2
    exit 1
  fi
fi
# If $SKILL_SELF cannot be located (test-harness injection, older runtime),
# the check is a no-op — the frontmatter grep in tests/run-all.sh still
# enforces the invariant at CI time.
```

## Argument parser (WI 1.2)

Bash-regex idiom matching `skills/do/SKILL.md:70-92`. Recognized flags:
`--branch <name>`, `--yes` / `-y`, `--from-here`, `--skip-tests`. Everything
else becomes the DESCRIPTION (trimmed of leading/trailing whitespace).
Empty DESCRIPTION is allowed at parse time — mode detection (WI 1.5)
decides whether it is fatal.

```bash
ARGS=( "$@" )
DESCRIPTION=""
BRANCH_OVERRIDE=""
YES_FLAG=0
FROM_HERE=0
SKIP_TESTS=0

i=0
while [ $i -lt ${#ARGS[@]} ]; do
  arg="${ARGS[$i]}"
  case "$arg" in
    --branch)
      i=$((i+1))
      BRANCH_OVERRIDE="${ARGS[$i]:-}"
      ;;
    --yes|-y)    YES_FLAG=1 ;;
    --from-here) FROM_HERE=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    *)
      if [ -z "$DESCRIPTION" ]; then
        DESCRIPTION="$arg"
      else
        DESCRIPTION="$DESCRIPTION $arg"
      fi
      ;;
  esac
  i=$((i+1))
done

# Trim
DESCRIPTION="${DESCRIPTION#"${DESCRIPTION%%[![:space:]]*}"}"
DESCRIPTION="${DESCRIPTION%"${DESCRIPTION##*[![:space:]]}"}"
```

## Phase 1 — Pre-flight

### WI 1.3 — Config and environment gates

Resolve `MAIN_ROOT` first so every subsequent path is anchored:

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
```

Then run the fail-fast gates. Each prints a **single discriminator keyword
line** to stderr and exits:

**Check 1 — `gh` available.**

```bash
if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: /quickfix requires gh (not found on PATH)." >&2
  exit 1
fi
```

**Read config once (bash-regex parsing, no `jq` dependency).**

All subsequent config reads extract from this single capture. Pattern
matches `skills/update-zskills/SKILL.md` Step 0.5. An unmatched key
leaves its variable at the default assigned before the regex test; an
empty string in the config ("present but empty") matches the regex and
is passed through verbatim.

```bash
CONFIG_CONTENT=$(cat "$MAIN_ROOT/.claude/zskills-config.json")

LANDING="direct"
if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  LANDING="${BASH_REMATCH[1]}"
fi

UNIT_CMD=""
if [[ "$CONFIG_CONTENT" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  UNIT_CMD="${BASH_REMATCH[1]}"
fi

FULL_CMD=""
if [[ "$CONFIG_CONTENT" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  FULL_CMD="${BASH_REMATCH[1]}"
fi
```

**Check 2 — landing == pr.**

```bash
if [ "$LANDING" != "pr" ]; then
  echo "ERROR: /quickfix requires execution.landing == \"pr\" (got \"$LANDING\"). Use /commit or /do for non-PR landing." >&2
  exit 1
fi
```

**Check 3 — test-cmd alignment gate (LOAD-BEARING).**

The project's pre-commit hook (`hooks/block-unsafe-project.sh.template:188-229`)
rejects `git commit` with staged code files unless the Claude transcript
contains the configured `FULL_TEST_CMD`. `/quickfix` runs the project's
`unit_cmd` before committing, so we require `unit_cmd` is set AND — if
`full_cmd` is also set — `full_cmd == unit_cmd`. Otherwise the hook will
block our commit mid-flow.

```bash
if [ "$SKIP_TESTS" -eq 0 ] && [ -z "$UNIT_CMD" ]; then
  echo "ERROR: /quickfix requires testing.unit_cmd (or pass --skip-tests)." >&2
  exit 1
fi
if [ -n "$FULL_CMD" ] && [ "$FULL_CMD" != "$UNIT_CMD" ]; then
  echo "ERROR: testing.full_cmd differs from testing.unit_cmd. Project's pre-commit hook checks full_cmd in transcript; align the two or use /commit pr / /do pr." >&2
  exit 1
fi
```

### WI 1.3.5 — Parallel-invocation gate (with staleness)

Refuse to start if another `/quickfix` is already in flight. A marker is
considered **stale** once it is older than `STALE_AGE_SECONDS=3600` (one
hour) — in that case we warn and proceed; otherwise we exit 1.

```bash
STALE_AGE_SECONDS=3600
NOW_EPOCH=$(date +%s)
for marker in "$MAIN_ROOT"/.zskills/tracking/quickfix.*/fulfilled.quickfix.*; do
  [ -f "$marker" ] || continue
  if grep -q '^status: started' "$marker"; then
    # Extract `date:` — GNU date -d is required to parse ISO-8601 back to epoch.
    DATE_LINE=$(grep '^date:' "$marker" | head -n1 | sed 's/^date: //')
    MARKER_EPOCH=$(date -d "$DATE_LINE" +%s 2>/dev/null || echo 0)
    AGE=$((NOW_EPOCH - MARKER_EPOCH))
    if [ "$AGE" -lt "$STALE_AGE_SECONDS" ]; then
      echo "ERROR: another /quickfix is in progress ($marker, age ${AGE}s). Wait or remove the marker." >&2
      exit 1
    else
      echo "WARN: stale /quickfix marker ($marker, age ${AGE}s > ${STALE_AGE_SECONDS}s); proceeding." >&2
    fi
  fi
done
```

### WI 1.4 — Main-ref fetch

Verify we are on main or master (unless `--from-here` is passed). Capture
the current branch as `BASE_BRANCH` and fetch the remote ref. **Do NOT
a fast-forward merge of origin into a dirty working tree — paths that
overlap the incoming changes would abort the merge and leave us in a
partial state. Local main may stay stale; the branch creation step
(WI 1.9) branches directly from `origin/$BASE_BRANCH`.

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$FROM_HERE" -eq 0 ]; then
  case "$CURRENT_BRANCH" in
    main|master) ;;
    *)
      echo "ERROR: /quickfix must run on main or master (got '$CURRENT_BRANCH'). Pass --from-here to override." >&2
      exit 1
      ;;
  esac
fi
BASE_BRANCH="$CURRENT_BRANCH"

if ! git fetch origin "$BASE_BRANCH"; then
  echo "ERROR: failed to fetch origin/$BASE_BRANCH (network or auth?)." >&2
  exit 1
fi
```

## Phase 2 — Mode detection and slug

### WI 1.5 — Mode detection

Compute the dirty-file set on entry (deduplicated union of modified,
deleted, and untracked):

```bash
MODS=$(git diff --name-only HEAD)
DELS=$(git diff --name-only --diff-filter=D HEAD)
UNTRACKED=$(git ls-files --others --exclude-standard)
DIRTY_FILES=$(printf '%s\n%s\n%s\n' "$MODS" "$DELS" "$UNTRACKED" | sed '/^$/d' | sort -u)

if [ -n "$DIRTY_FILES" ] && [ -n "$DESCRIPTION" ]; then
  MODE="user-edited"
elif [ -n "$DIRTY_FILES" ] && [ -z "$DESCRIPTION" ]; then
  echo "ERROR: user-edited mode requires a description. Usage: /quickfix <description> [flags]" >&2
  exit 2
elif [ -z "$DIRTY_FILES" ] && [ -n "$DESCRIPTION" ]; then
  MODE="agent-dispatched"
else
  echo "ERROR: /quickfix needs either in-flight edits or a description. Usage: /quickfix [<description>] [flags]" >&2
  exit 2
fi
```

### WI 1.5.5 — Dirty-tree confirmation (model-layer)

This is a **model-layer instruction**, not a bash block.

When `MODE == "user-edited"` (i.e. `$DIRTY_FILES` is non-empty), the model
MUST, before proceeding to slug/branch creation:

1. Show the user the full dirty-file list (one per line).
2. Show the output of `git diff HEAD`.
3. Explicitly ask: **"Commit all of these files as part of '<DESCRIPTION>'? [y/N]"**
4. Only proceed if the user affirms. If the user declines or does not
   respond affirmatively, exit cleanly — set the tracking marker's
   `status` to `cancelled` and commit nothing. No branch is created yet at
   this point, so no rollback is needed.

**Rationale:** user-edited mode accepts dirty-tree input so the user can
ship a one-line fix without stashing. But without an explicit
confirmation, the model could loosely match `$DESCRIPTION` to the dirty
files and accidentally bundle unrelated in-flight work into the PR. Don't
rely on description-to-filename pattern-matching — always surface the full
diff and confirm before branching.

This confirmation supersedes WI 1.10's bash `read -r` prompt, which now
exists only as a fallback for the literal-script execution path used by
`tests/test-quickfix.sh` Case 43 (invoked with `--yes`).

### WI 1.6 — Slug derivation

Pipeline: lowercase → collapse non-alphanumerics to `-` → trim leading
and trailing `-` → `cut -c1-40` → **trim trailing `-` again** (the second
trim is load-bearing: when the cut boundary lands on a `-`, otherwise the
branch would end in `quickfix/fix-foo-`).

```bash
SLUG=$(printf '%s' "$DESCRIPTION" \
       | tr '[:upper:]' '[:lower:]' \
       | sed -E 's/[^a-z0-9]+/-/g' \
       | sed -E 's/^-+//; s/-+$//' \
       | cut -c1-40 \
       | sed -E 's/-+$//')

if [ -z "$SLUG" ]; then
  echo "ERROR: description produced an empty slug (no alphanumerics)." >&2
  exit 2
fi
case "$SLUG" in
  */*) echo "ERROR: slug must not contain '/' (got '$SLUG')." >&2; exit 2 ;;
esac
```

Examples:

| Input | Slug |
|-------|------|
| `Fix README typo!` | `fix-readme-typo` |
| `Fix the broken link in docs/intro.md` | `fix-the-broken-link-in-docs-intro-md` |
| `  Update CHANGELOG  ` | `update-changelog` |
| `---Fix---foo---` | `fix-foo` |
| `!!!` | `""` → exit 2 |

### WI 1.7 — Branch naming

`--branch` overrides verbatim. Otherwise prefix the slug with
`execution.branch_prefix` (default `quickfix/`; empty string allowed).

```bash
if [ -n "$BRANCH_OVERRIDE" ]; then
  BRANCH="$BRANCH_OVERRIDE"
else
  # branch_prefix: empty string ("present but empty") is legal and distinct
  # from the key being absent. Only fall back to the default when the key
  # is entirely missing.
  if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  else
    BRANCH_PREFIX="quickfix/"
  fi
  BRANCH="${BRANCH_PREFIX}${SLUG}"
fi
```

| `--branch` | `branch_prefix` | Slug | BRANCH |
|------------|-----------------|------|--------|
| (absent) | (absent) | `fix-readme-typo` | `quickfix/fix-readme-typo` |
| (absent) | `"fix/"` | `fix-readme-typo` | `fix/fix-readme-typo` |
| (absent) | `""` | `fix-readme-typo` | `fix-readme-typo` |
| `custom/foo` | (any) | (any) | `custom/foo` (verbatim) |

### WI 1.8 — Tracking setup

Construct `PIPELINE_ID` via the sanitizer (not a raw string), echo it to
the transcript (tier-2 tracking per `tests/test-hooks.sh:245`), and write
the `started` marker under the pipeline-scoped tracking dir.

```bash
PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "quickfix.$SLUG")
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

TRACK_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
MARKER="$TRACK_DIR/fulfilled.quickfix.$SLUG"
mkdir -p "$TRACK_DIR"

NOW_ISO=$(TZ=America/New_York date -Iseconds)
cat > "$MARKER" <<MARK
status: started
date: $NOW_ISO
skill: quickfix
mode: $MODE
slug: $SLUG
branch: $BRANCH
base: $BASE_BRANCH
MARK

CANCELLED=0
finalize_marker() {
  local rc="$1"
  local final
  if [ "$CANCELLED" -eq 1 ]; then
    final="cancelled"
  elif [ "$rc" -eq 0 ]; then
    final="complete"
  else
    final="failed"
  fi
  # Rewrite the status line, preserving the rest.
  if [ -f "$MARKER" ]; then
    sed -i "s/^status: started$/status: $final/" "$MARKER"
  fi
}
trap 'finalize_marker $?' EXIT
```

### WI 1.9 — Branch creation

Created from `MAIN_ROOT` so `git checkout -b` carries the dirty tree
across. Three checks before branching:

1. Local ref collision → exit 2.
2. Remote collision via `git ls-remote` — distinguish **network/auth
   failure** (non-zero rc → exit 1) from **branch exists on remote**
   (non-empty output → exit 2). Do not suppress errors here; the two
   outcomes have different remediations.
3. `git checkout -b "$BRANCH" "origin/$BASE_BRANCH"`.

```bash
cd "$MAIN_ROOT"

if git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  echo "ERROR: branch '$BRANCH' already exists locally. Pick a different slug, pass --branch, or delete the stale branch." >&2
  exit 2
fi

REMOTE_OUT=$(git ls-remote --heads origin "$BRANCH")
REMOTE_RC=$?
if [ "$REMOTE_RC" -ne 0 ]; then
  echo "ERROR: git ls-remote failed for 'origin $BRANCH' (network/auth). Rerun after fixing connectivity." >&2
  exit 1
fi
if [ -n "$REMOTE_OUT" ]; then
  echo "ERROR: branch '$BRANCH' already exists on origin. Pick a different slug or pass --branch." >&2
  exit 2
fi

if ! git checkout -b "$BRANCH" "origin/$BASE_BRANCH"; then
  echo "ERROR: git checkout -b failed (dirty-tree conflict with base?). Resolve and retry." >&2
  exit 5
fi
```

## Phase 3 — Make the change

### WI 1.10 — User-edited mode

Enumerate changed files, show the diff, optionally prompt. Re-compute
the three sets after the branch switch so `CHANGED_FILES` reflects what
will be staged (untracked files carry across; new untracked on the new
branch still count).

**Note:** The bash confirmation block below is vestigial in real
(model-driven) `/quickfix` invocation — WI 1.5.5 already obtained the
user's explicit confirmation. It remains in place to support
literal-script execution in `tests/test-quickfix.sh` Case 43, which
passes `--yes` to bypass the `read -r`. Do not re-prompt the user if WI
1.5.5 already did.

```bash
if [ "$MODE" = "user-edited" ]; then
  MODS=$(git diff --name-only HEAD)
  DELS=$(git diff --name-only --diff-filter=D HEAD)
  UNTRACKED=$(git ls-files --others --exclude-standard)
  CHANGED_FILES=$(printf '%s\n%s\n' "$MODS" "$UNTRACKED" | sed '/^$/d' | sort -u)

  echo "=== /quickfix user-edited mode ==="
  echo "Branch: $BRANCH (base: $BASE_BRANCH)"
  echo "Description: $DESCRIPTION"
  echo ""
  echo "Files changed:"
  echo "$CHANGED_FILES" | sed 's/^/  /'
  if [ -n "$DELS" ]; then
    echo "Files deleted:"
    echo "$DELS" | sed 's/^/  /'
  fi
  echo ""
  git --no-pager diff HEAD

  if [ "$YES_FLAG" -eq 0 ]; then
    printf 'Proceed? [y/N] '
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *)
        CANCELLED=1
        echo "Cancelled by user. Cleaning up branch." >&2
        if ! git checkout "$BASE_BRANCH"; then
          echo "ERROR: cleanup: failed to checkout $BASE_BRANCH. Repo may be in an intermediate state; manual recovery needed." >&2
          exit 6
        fi
        if ! git branch -D "$BRANCH"; then
          echo "ERROR: cleanup: failed to delete branch $BRANCH. Manual recovery: 'git branch -D $BRANCH'." >&2
          exit 6
        fi
        exit 0
        ;;
    esac
  fi
fi
```

### WI 1.11 — Agent-dispatched mode

This is a **model-layer instruction**, not a bash block. Skills cannot
dispatch agents from bash (per CREATE_WORKTREE R-F1). Same pattern as
`skills/do/SKILL.md:342-358`.

When `MODE == "agent-dispatched"`:

1. Capture `PRE_HEAD=$(git rev-parse HEAD)` before dispatching.
2. Check `agents.min_model` from `.claude/zskills-config.json`; if set
   to a specific model, include the hint in the dispatch prompt
   (default `auto` → omit, inherit parent model).
3. **Dispatch one Agent tool call** with a prompt that instructs the
   subagent to:
   - `cd $MAIN_ROOT`
   - Implement `$DESCRIPTION`
   - **Do NOT** `git commit`, `git add`, or modify the index
   - **Do NOT** run tests, builds, linters, or formatters
   - When finished, list newly untracked files in the "done" report
   - **IMPORTANT:** Only leave files untracked that you intend to commit
     as part of this change. Delete any scratch, debug, or log files you
     created during exploration before reporting done. The skill will
     include all your remaining untracked files in the commit — any
     lingering scratch will ship in the PR.
4. After the Agent returns, verify:
   - `POST_HEAD=$(git rev-parse HEAD)`; if `POST_HEAD != PRE_HEAD`, the
     agent committed unexpectedly → exit 5 with cleanup (checkout base,
     delete branch).
   - `DIRTY_AFTER` is the sorted union of tracked modifications AND
     newly untracked files. The agent is expected (per step 3's
     IMPORTANT clause) to have cleaned up scratch/debug/log files
     before reporting done, so any remaining untracked files ARE part
     of the intended commit and SHOULD be staged. Definition:
     ```bash
     DIRTY_AFTER=$(printf '%s\n%s\n' "$(git diff --name-only HEAD)" "$(git ls-files --others --exclude-standard)" | sed '/^$/d' | sort -u)
     ```
   - If `DIRTY_AFTER` is empty, the agent did not change the tree →
     exit 5 with cleanup.
5. Populate:
   ```bash
   CHANGED_FILES="$DIRTY_AFTER"
   DELS=$(git diff --name-only --diff-filter=D HEAD)
   ```
6. Proceed to the test gate (WI 1.12).

## Phase 4 — Test gate (WI 1.12)

When `--skip-tests` is passed, warn and skip. Otherwise run the project's
`unit_cmd` with output captured to a per-quickfix `/tmp/zskills-tests`
directory (never piped — see CLAUDE.md's "capture test output to a file,
never pipe" rule).

```bash
if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "WARN: --skip-tests passed; skipping $UNIT_CMD" >&2
else
  TEST_OUT="/tmp/zskills-tests/$(basename "$MAIN_ROOT")-quickfix-$SLUG"
  mkdir -p "$TEST_OUT"
  if ! bash -c "$UNIT_CMD" > "$TEST_OUT/.test-results.txt" 2>&1; then
    echo "ERROR: tests failed. See $TEST_OUT/.test-results.txt" >&2
    # Rollback: leave edits in the working tree (user may have work to save),
    # drop back to base, delete the feature branch.
    if ! git checkout "$BASE_BRANCH"; then
      echo "ERROR: cleanup: failed to checkout $BASE_BRANCH after test failure." >&2
      exit 6
    fi
    if ! git branch -D "$BRANCH"; then
      echo "ERROR: cleanup: failed to delete branch $BRANCH after test failure." >&2
      exit 6
    fi
    exit 4
  fi
fi
```

## Phase 5 — Commit (WI 1.13)

CLAUDE.md feature-complete discipline applies: stage by name only (never
`git add .` or `-A`). Reject directories — everything in `CHANGED_FILES`
must be a regular file path. Deletions are staged via `git add -u` on the
DELS list.

**Never bypass the pre-commit hook.** If the hook fires, fix the root
cause and rerun; do not pass any flag that would skip hook verification.

On commit failure, clean up verified-each-step: any cleanup step that
itself fails exits 6 (manual intervention).

```bash
# Stage: reject directory entries.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -d "$MAIN_ROOT/$f" ]; then
    echo "ERROR: refusing to stage directory '$f' (stage individual files only)." >&2
    exit 5
  fi
done <<< "$CHANGED_FILES"

# shellcheck disable=SC2086
# CHANGED_FILES is a newline-separated list; xargs -r0 with tr guards against spaces-in-paths.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  git add -- "$f"
done <<< "$CHANGED_FILES"

if [ -n "$DELS" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    git add -u -- "$f"
  done <<< "$DELS"
fi

# Resolve the co-author line from config (agent-dispatched mode only;
# the user-edited branch omits Co-Authored-By entirely). Default falls
# back to Claude Opus 4.7 when .commit.co_author is absent.
CO_AUTHOR="Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
if [[ "$CONFIG_CONTENT" =~ \"co_author\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  CO_AUTHOR="${BASH_REMATCH[1]}"
fi
```

**Compose the commit subject (model-layer).** Look at `git diff --cached`
and `git diff --cached --stat`. Set shell variable `COMMIT_SUBJECT` to a
conventional-commit line: `type(scope): summary` (type ∈ {feat, fix, docs,
refactor, chore, test, build, ci, style, perf, revert}; scope is the
primary skill/module/file being changed; summary ≤ 70 chars describing
what was actually changed). DESCRIPTION is the task spec — it goes into
the commit body as context, **not** the subject line.

The next bash fence consumes `$COMMIT_SUBJECT` to compose the full body
and invoke `git commit`. If the commit fails, the same fence runs the
cleanup (checkout base, delete branch, exit 5; each cleanup step
verified, any that itself fails exits 6 for manual intervention). Never
pass `--no-verify` — fix the root cause and retry (max 2 attempts on the
same error, then STOP and report).

```bash
# The model must set COMMIT_SUBJECT before this fence runs (see prose
# above). DESCRIPTION goes in the body as context, not the subject line.
if [ -z "${COMMIT_SUBJECT:-}" ]; then
  echo "ERROR: COMMIT_SUBJECT not set — model-layer composition step skipped." >&2
  exit 5
fi

if [ "$MODE" = "user-edited" ]; then
  # No Co-Authored-By: the human authored the edits.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (user-edited)
COMMIT_EOF
)
else
  # agent-dispatched: include Co-Authored-By from $CO_AUTHOR.
  COMMIT_BODY=$(cat <<COMMIT_EOF
$COMMIT_SUBJECT

$DESCRIPTION

🤖 Generated with /quickfix (agent-dispatched)

Co-Authored-By: $CO_AUTHOR
COMMIT_EOF
)
fi

if ! git commit -m "$COMMIT_BODY"; then
  echo "ERROR: git commit failed (pre-commit hook, hook exit, or other)." >&2
  if ! git reset HEAD -- . ; then
    echo "ERROR: cleanup: git reset HEAD failed." >&2
    exit 6
  fi
  if ! git checkout "$BASE_BRANCH"; then
    echo "ERROR: cleanup: failed to checkout $BASE_BRANCH." >&2
    exit 6
  fi
  if ! git branch -D "$BRANCH"; then
    echo "ERROR: cleanup: failed to delete branch $BRANCH." >&2
    exit 6
  fi
  exit 5
fi
```

## Phase 6 — Push (WI 1.14)

**Bare-branch form ONLY.** Never use a `src:dst` refspec when pushing
the feature branch (especially not one whose right-hand side targets a
protected ref). The refspec strip in `hooks/block-unsafe-generic.sh:215-220`
(`PUSH_TARGET="${PUSH_TARGET%%:*}"` followed by a protected-ref gate)
means refspec forms could bypass the guard when the right-hand side is a
protected ref — the bare form is independently sound and does not depend
on that strip.

On push failure, leave branch and commit intact; the user retries manually.

```bash
if ! git push -u origin "$BRANCH"; then
  echo "ERROR: git push failed. Branch '$BRANCH' and its commit are intact locally; retry manually once the remote is reachable." >&2
  exit 5
fi
```

## Phase 7 — PR creation (WI 1.15)

Title is the description truncated to 70 characters. Body is built via a
`<<-EOF` heredoc with **tab-indented** body lines (tabs are stripped by
`<<-`; using spaces would render the body as a code block on GitHub).

```bash
PR_TITLE=$(printf '%s' "$DESCRIPTION" | cut -c1-70)

PR_BODY=$(cat <<-EOF
	## Summary

	$DESCRIPTION

	Mode: \`$MODE\`
	Base: \`$BASE_BRANCH\`
	Slug: \`$SLUG\`

	## Test plan

	- Ran project \`unit_cmd\` before commit (or --skip-tests).
	- Review diff.

	🤖 Generated with /quickfix
	EOF
)

if ! PR_URL=$(gh pr create --base "$BASE_BRANCH" --head "$BRANCH" --title "$PR_TITLE" --body "$PR_BODY"); then
  echo "ERROR: gh pr create failed. Branch '$BRANCH' is pushed; create the PR manually on GitHub." >&2
  exit 5
fi

# WI 1.16 — append the PR URL to the fulfillment marker BEFORE the EXIT
# trap flips `status: started` → `status: complete`. The appended line is
# the only record of the PR URL in the tracking store (no worktree-state
# artifact is produced — see the note below on terminal marker states).
if [ -f "$MARKER" ]; then
  printf 'pr: %s\n' "$PR_URL" >> "$MARKER"
fi

echo "$PR_URL"
```

No `--watch`, no polling. CI runs on GitHub's side; the user follows the
URL. The EXIT trap finalizes the marker to `complete` on success.

### Terminal marker states

The fulfillment marker at `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.quickfix.$SLUG`
transitions from `status: started` at WI 1.8 entry to exactly one of:

- `status: complete` — PR created, URL appended via `pr: $PR_URL`.
- `status: cancelled` — user answered `n` at the user-edited confirmation prompt.
- `status: failed` — any non-zero exit path after the marker was written.

No `.landed` marker is written. `/quickfix` has no worktree, and PR state
is authoritative via `gh pr view` — there is no cherry-pick-landing step
to attest to.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (PR created) or user-cancelled confirmation |
| 1 | Config / environment error (landing, gh, not-on-main, fetch failed, unit_cmd unset, full_cmd mismatch, parallel in progress, ls-remote network) |
| 2 | Input error (no edits + no description; user-edited no description; branch exists local/remote; slug empty or contains slash) |
| 4 | Test failure (`unit_cmd` non-zero) |
| 5 | Commit / push / PR-create / agent failure |
| 6 | Cleanup failure — manual intervention needed (a rollback step returned non-zero; repo in intermediate state) |

## Key Rules

- **PR-only.** `execution.landing != "pr"` → hard error; point to `/commit` or `/do`.
- **Aligned test-cmd.** `unit_cmd` set and (if `full_cmd` set) `unit_cmd == full_cmd`; otherwise the project pre-commit hook will block our commit.
- **Dirty tree is input.** Show diff, optionally confirm, carry across via `git checkout -b`. Never stash.
- **Never bypass the pre-commit hook.** Hooks exist for safety; fix the root cause.
- **No error suppression on fallible operations.** Distinguish network failure from branch-exists; check each cleanup step.
- **Bare-branch push only.** `git push -u origin "$BRANCH"` — never a refspec pointed at a protected ref.
- **No `.landed` marker.** `/quickfix` has no worktree; PR state is authoritative via `gh pr view`.
- **Fire-and-forget.** End at `gh pr create`; print URL; exit. No polling, no `--watch`.
