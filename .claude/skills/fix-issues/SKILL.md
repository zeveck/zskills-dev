---
name: fix-issues
disable-model-invocation: true
argument-hint: "N [focus|dashboard] [auto] [every SCHEDULE] [now] [pr|direct] | sync | plan [auto] | stop | next"
description: >-
  Orchestrate a batch bug-fixing sprint: dispatch fixers in per-issue
  worktrees, verify, optionally auto-land via /land-pr. Recurring via
  every SCHEDULE; stop/next manage it. sync updates trackers + closes
  already-fixed issues; plan drafts plans for skipped ones.
metadata:
  version: "2026.05.17+42910a"
---

# /fix-issues N [focus|dashboard] [auto] [every SCHEDULE] [now] [pr|direct] | sync | plan [auto] | stop | next — Batch Bug-Fixing Sprint

Orchestrates large-scale bug fixing. Syncs trackers, prioritizes issues,
dispatches agent teams in worktrees, verifies fixes, writes a persistent
report, and optionally auto-lands to main. Can self-schedule for recurring runs.

**Ultrathink throughout.** Use careful, thorough reasoning at every step.

## Arguments

```
/fix-issues N [focus|dashboard] [auto] [every SCHEDULE] [now] [pr|direct]
/fix-issues sync | plan [auto] | stop | next
```

- **N** (required for sprints) — number of issues to fix (e.g., `30`)
- **focus** (optional) — prioritize a specific domain. The agent scans
  `$ZSKILLS_ISSUES_DIR/*_ISSUES.md` and `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` to discover tracker files
  and their domains. Common focus values: `new`, `correctness`, `codegen`,
  `ui`, `tests` — but any domain found in your tracker files works.
  Omit for default priority order.
- **dashboard** (optional) — source candidate issues from the dashboard's
  Ready queue (`.zskills/monitor-state.json` `issues.ready`) instead of
  the model-layer priority rubric. The Ready list reflects user drag
  order from the in-app feedback dashboard — it IS the priority.
  Intersects with the live open-issue list so closed issues drop out
  silently. Capped to N. Mutually exclusive with `focus`, `sync`,
  `plan`, `stop`, and `next`. Empty queue → exit 0 cleanly (no
  fall-through to default rubric). Designed for the queue-worker
  pattern: `/fix-issues 1 every 30m dashboard auto`.
- **auto** (optional) — bypass confirmation gates for autonomous operation.
  Behavior depends on context:
  - **Sprints:** skip Phase 2 issue list approval, auto-land to main via
    cherry-pick. Does NOT close GH issues or remove worktrees — those are
    `/fix-report` actions.
  - **plan auto:** draft plans for all found issues without selection
    (see Plan section).
  - **Not applicable to sync.** `sync` is always interactive — closing
    issues on GitHub requires human approval.
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Implies `auto` — scheduling only makes sense for autonomous runs
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior
  (bare invocation always runs immediately).
- **sync** — update all issue tracker files from GitHub, research new
  issues, AND verify/close issues that appear already fixed. Dispatches
  research agents that also check if open issues are already resolved in
  the codebase. Always interactive — presents findings and asks before
  closing. See Sync section for the full flow.
- **plan** — draft plans for issues previously skipped as "too complex."
  Scans `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` for skipped items, dispatches `/draft-plan`
  for each. No fixing — just creates plans for `/run-plan` to execute later.
- **stop** — cancel any existing `/fix-issues` cron and exit. **Takes
  precedence over all other arguments.**
- **next** — check when the next scheduled run will fire. **Takes precedence
  over all other arguments except `stop`.**
- **pr** (optional) — land each fixed issue via a per-issue PR on a named
  branch (`fix/issue-NNN`) in a dedicated worktree. Overrides the config
  default `execution.landing`.
- **direct** (optional) — land each fixed issue by fast-forward-merging
  its per-issue worktree branch (`fix-issue-NNN`) into main (no PR, no
  cherry-pick extraction). Overrides the config default. Incompatible
  with `execution.main_protected: true`.

**Detection:** scan `$ARGUMENTS` for:
- `stop` (case-insensitive) — cancel cron and exit (highest precedence)
- `next` (case-insensitive) — check schedule and exit
- `sync` (case-insensitive) — sync trackers, verify/close fixed issues, and exit
- `plan` (case-insensitive) — draft plans for skipped issues and exit
- `now` (case-insensitive) — run immediately
- `auto` (case-insensitive) — autonomous mode (behavior varies by context)
- `every` followed by a schedule expression — scheduling mode
- `pr` (case-insensitive) — PR landing mode (per-issue branches + PRs)
- `direct` (case-insensitive) — direct landing mode (commit on main)
- `dashboard` (case-insensitive) — source candidates from
  `.zskills/monitor-state.json` `issues.ready` instead of the model rubric

**Landing mode resolution** (same pattern as `/run-plan`):
1. Explicit argument wins: `pr` or `direct` in `$ARGUMENTS`
2. Config default: read `.claude/zskills-config.json` `execution.landing` field
3. Fallback: `cherry-pick`

```bash
# Detect landing mode (same logic as /run-plan)
LANDING_MODE="cherry-pick"
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]]; then
  LANDING_MODE="pr"
elif [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]]; then
  LANDING_MODE="direct"
else
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      CFG_LANDING="${BASH_REMATCH[1]}"
      [ -n "$CFG_LANDING" ] && LANDING_MODE="$CFG_LANDING"
    fi
  fi
fi

# Validation: direct + main_protected -> error
if [[ "$LANDING_MODE" == "direct" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
      echo "ERROR: direct mode is incompatible with main_protected: true. Use pr mode or change config."
      exit 1
    fi
  fi
fi
```

**Strip `pr`/`direct` from arguments** before parsing issue numbers, focus,
or other tokens (same pattern as stripping `auto`, `now`, etc.). The
downstream N/focus parser must not see `pr` or `direct` as an issue count
or domain name.

**Detect `dashboard` source mode.** Place this detection in the same
Phase 0 arg-detection block as `auto`/`pr`/`direct`/`now`. When
`DASHBOARD_MODE=1`, Phase 2 sources candidate issues from the
dashboard's Ready queue (`.zskills/monitor-state.json` `issues.ready`)
rather than the model-layer priority rubric. The strip line below
ensures `dashboard` never leaks into the leading-N integer parser.

```bash
DASHBOARD_MODE=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][aA][sS][hH][bB][oO][aA][rR][dD]($|[[:space:]]) ]]; then
  DASHBOARD_MODE=1
fi

# Strip dashboard from arguments before the leading-N integer parser
# (same pattern as stripping pr/direct/auto/now).
ARGUMENTS=$(printf '%s' "$ARGUMENTS" \
  | sed -E 's/(^|[[:space:]])[pP][rR]($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])[dD][aA][sS][hH][bB][oO][aA][rR][dD]($|[[:space:]])/ /')
```

**Mutual exclusion for `dashboard`.** `dashboard` is a source-of-truth
override for the candidate-selection step (Phase 2). It is incompatible
with any mode that either (a) defines its own priority rubric (`focus`)
or (b) is a different subcommand entirely (`sync`, `plan`, `stop`,
`next`). Place these checks AFTER all subcommands are detected and
BEFORE Phase 1 starts (i.e., after Phase 0 arg detection so we know
which mode is active):

```bash
if [ "$DASHBOARD_MODE" = "1" ]; then
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[fF][oO][cC][uU][sS]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with focus mode" >&2
    exit 2
  fi
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[sS][yY][nN][cC]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with sync mode" >&2
    exit 2
  fi
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][lL][aA][nN]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with plan mode" >&2
    exit 2
  fi
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[sS][tT][oO][pP]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with stop mode" >&2
    exit 2
  fi
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[nN][eE][xX][tT]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with next mode" >&2
    exit 2
  fi
fi
```

Examples:
- `/fix-issues 30` — interactive, 30 issues, run now
- `/fix-issues 10 correctness` — interactive, solver focus, run now
- `/fix-issues 5 auto` — autonomous, one-time, run now
- `/fix-issues 5 auto every 4h` — schedule every 4h (first run in ~4h)
- `/fix-issues 5 auto every 4h now` — schedule every 4h + run immediately
- `/fix-issues 10 auto every day at 9am` — schedule daily at 9am
- `/fix-issues 10 auto every weekday at 9am now` — schedule + run now
- `/fix-issues sync` — update trackers + verify/close fixed issues (always interactive)
- `/fix-issues plan` — draft plans for issues skipped as "too complex"
- `/fix-issues plan auto` — same, but plan all without selection
- `/fix-issues stop` — cancel the recurring cron
- `/fix-issues next` — check when the next sprint will run
- `/fix-issues 5 auto pr` — autonomous sprint, per-issue PR landing
- `/fix-issues 3 auto direct` — autonomous sprint, land commits on main directly
- `/fix-issues 1 every 30m dashboard auto` — queue-worker pattern: 1 issue
  every 30m sourced from dashboard Ready, auto-merge
- `/fix-issues 3 dashboard` — fix the top 3 issues from dashboard Ready
- `/fix-issues 1 dashboard auto pr` — single fix from dashboard Ready,
  auto-merge in PR mode

## Now (standalone — no N provided)

If `$ARGUMENTS` is just `now` (no N, no focus, no every — just the word
`now` by itself):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /fix-issues`
3. If found: extract the cron's prompt to get N, focus, auto, and schedule.
   **Run the sprint immediately** using those parameters — proceed to
   Phase 1 with the cron's N, focus, and auto settings. Do NOT ask for
   confirmation — `now` IS the confirmation. The cron itself stays active.
4. If none found: report `No active /fix-issues cron to trigger. Use
   /fix-issues N to run manually.` and **exit.**

## Next (if `next` is present)

If `$ARGUMENTS` contains `next` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /fix-issues`
3. Report:
   - If found: parse the cron expression and compute the next fire time.
     Use `date +%Z` for the timezone. Show both relative and absolute:
     > Next fix-issues sprint in ~2h 15m (~8:30 PM ET, cron XXXX).
     > Prompt: Run /fix-issues 5 auto every 4h
   - If none found: `No active /fix-issues cron in this session.`
4. **Exit.** Do not proceed to any phase.

## Stop (if `stop` is present)

If `$ARGUMENTS` contains `stop` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Delete ALL whose prompt starts with `Run /fix-issues` using `CronDelete`
3. Report what was cancelled:
   - If one cron found: `Fix-issues cron stopped (was job ID XXXX, every INTERVAL).`
   - If multiple found: `Stopped N fix-issues crons (IDs: XXXX, YYYY).`
   - If none found: `No active /fix-issues cron found.`
4. **Exit.** Do not proceed to any phase. The `stop` command does nothing else.

## Sync (if `sync` is present)

Update all issue trackers from GitHub, research new issues, and verify/close
issues that appear already fixed. This is the single command for issue
hygiene — it both syncs state AND cleans up resolved issues in one pass.

**Always interactive.** Closing issues on GitHub requires human approval —
there is no `auto` mode for sync. The agent presents verified-fixed
candidates and waits for the user to select which to close.

**All sync-mode work happens in a pre-created worktree.** Before fetching
trackers, dispatching research agents, or writing the SPRINT_REPORT.md
section, front-run the shared `ensure-worktree.sh` gate. Steps 1–5 then
run inside the worktree, so Step 4's SPRINT_REPORT.md write and Step 5's
commit naturally land on the feature branch (not main).

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
TOPLEVEL=$(git rev-parse --show-toplevel)
HELPER="$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/ensure-worktree.sh"
if [ ! -x "$HELPER" ]; then
  echo "fix-issues: ensure-worktree.sh missing at $HELPER — run /update-zskills to repair" >&2
  exit 11
fi
WT_PATH=$(bash "$HELPER" \
  --prefix fix-issues \
  --pipeline-id "fix-issues.${TRACKING_ID}" \
  --purpose "fix-issues sync; tracking=${TRACKING_ID}" \
  "${TRACKING_ID}")
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "ensure-worktree failed (rc=$RC) for /fix-issues" >&2
  exit "$RC"
fi
if [ -n "$WT_PATH" ]; then
  cd "$WT_PATH" || { echo "fix-issues: cd $WT_PATH failed" >&2; exit 1; }
  export ZSKILLS_PATHS_ROOT="$WT_PATH"  # R3-1 — re-anchor downstream path resolution
fi
```

### Step 1 — Fetch & update trackers

<!-- Bootstrap of empty $ZSKILLS_ISSUES_DIR/ happens in Phase 1a Sync; Standalone Sync inherits it via step 1's "Run Phase 1a" delegation. -->

1. **Run Phase 1a** (Preflight & Sync) — fetch all open issues, run sync
   script, update all tracker files.

### Step 2 — Research & verify

**Before dispatching any Agent:** check `agents.min_model` in `.claude/zskills-config.json`.
If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch
with a lower-ordinal model than the configured minimum.

Dispatch research agents for every open issue that lacks a research blurb
in its tracker file. Each agent does:

1. Read the full issue body and comments from GitHub
2. Grep the codebase for related files and code
3. Write a concise research blurb (what's wrong, where, suggested approach)
4. Add the blurb to the appropriate tracker file

**Additionally**, each agent checks whether the issue appears to already be
fixed in the codebase. This is the same pass — not a separate step. While
researching an issue, the agent naturally reads the relevant code and can
tell if the reported problem still exists. For each issue, the agent
produces a **verdict:**

- **FIXED** — code fix is present AND tests pass. Include: commit hash,
  what changed, which tests cover it.
- **LIKELY FIXED** — code fix appears present but no specific tests cover
  this exact issue. Include what was found and what's missing.
- **NOT FIXED** — the reported problem still exists in the code (normal —
  this is just a research blurb, the issue stays open).
- **UNCLEAR** — can't determine from code review alone (needs manual testing).

**Criteria for FIXED/LIKELY FIXED verdicts:**
- The specific code the issue reported as broken has been changed
- Tests exist that cover the reported behavior (FIXED) or not (LIKELY FIXED)
- The fix commit references the issue number or is clearly related
- Do NOT verdict as FIXED if: the issue is a feature request (not a bug),
  the fix is partial, or you're not confident

Also scan for additional close candidates from:
- **Tracker files** — `[x]` items that are still open on GitHub
- **Sprint reports** — entries in "Already Implemented" or "Already Fixed
  on Main" sections of `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`

For these candidates, dispatch verification agents with the same checklist
above (read issue body, check code, check tests, produce verdict).

### Step 3 — Present findings

Show the sync summary and any close candidates:

```
Sync complete. N open issues, M newly researched, K tracker files updated.
Gaps: [any GH issues not in any tracker]

Issues that appear already fixed (N candidates):

| # | Title | Verdict | Evidence |
|---|-------|---------|----------|
| #126 | Fcn block mapping | FIXED | SlxImporter.js:85, commit abc1234, 2 tests |
| #191 | Block stubs | FIXED | All 4 blocks implemented, 12 tests pass |
| #393 | Fcn codegen u(N) | FIXED | codegen emitter step 8, commit def5678 |
| #200 | Some bug | LIKELY FIXED | Code changed but no regression test |

Close 3 FIXED issues? (all / comma-separated numbers / none)
```

- Wait for user selection. LIKELY FIXED and UNCLEAR items are shown for
  context but NOT offered for closing — they need human judgment.
- **If no close candidates found:** skip this step, just show the sync
  summary.

### Step 4 — Stage local tracker + sprint-report updates for approved issues

For each approved issue:

1. **Update tracker files** — mark the issue `[x]` in all relevant trackers.

2. **Update `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`** — if the issue appears in an "Already
   Implemented" section, add a note: `Closed by /fix-issues sync`.

The `gh issue close` calls are deferred to Step 5 sub-step 3, AFTER
`/land-pr` returns `merged`. `created` and `monitored` mean the PR is
open but unmerged — closing on those statuses recreates the same AC-P.3
divergence PR #271 fixed (issue #282). If `/land-pr` returns any other
status, the issues remain OPEN on GitHub — preventing state divergence
between closed-on-GH and unmerged-in-main (AC-P.3 of
`docs/plans/FIX_ISSUES_SYNC_HARDENING.md`); the next sync run after
auto-merge completes will close them.

### Step 5 — Commit & report

1. **Commit** the SPRINT_REPORT.md section AND any modified tracker files
   (`*_ISSUES.md`, `ISSUES_PLAN.md`) to the worktree's feature branch.
   Tracker files now live under `output.issues_dir` (default `docs/issues/`)
   and are tracked in git, so the research blurbs and `[x]` annotations
   produced by sync mode persist via the resulting PR. The preamble (top
   of `## Sync`) already `cd`-ed into the worktree and exported
   `ZSKILLS_PATHS_ROOT`, so Step 4's SPRINT_REPORT.md write landed in
   `$TOPLEVEL/.zskills/audit/` and tracker writes landed in
   `$TOPLEVEL/$ZSKILLS_ISSUES_DIR/`.

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: filename basename suffixed onto $ZSKILLS_AUDIT_DIR (resolved via zskills-paths.sh); the basename token itself remains literal so the regex still flags the /SPRINT_REPORT.md tail -->
   ```bash
   # Defensive cwd restore; WT_PATH set by preamble at top of sync mode.
   [ -n "${WT_PATH:-}" ] && cd "$WT_PATH" 2>/dev/null || true
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   TOPLEVEL=$(git rev-parse --show-toplevel)
   if [ "$TOPLEVEL" != "$MAIN_ROOT" ]; then
     # R3-1: re-anchor under the worktree so $ZSKILLS_AUDIT_DIR resolves
     # to TOPLEVEL/.zskills/audit, not $CLAUDE_PROJECT_DIR/.zskills/audit.
     export ZSKILLS_PATHS_ROOT="$TOPLEVEL"
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"

     ABS_FILE="$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md"
     # Portable realpath (DA-R2-1; R3-6: adapted from warn-config-drift.sh:181-203).
     SPRINT_REL=""
     if SPRINT_REL=$(realpath --relative-to="$TOPLEVEL" "$ABS_FILE" 2>/dev/null) \
          && [ -n "$SPRINT_REL" ]; then
       case "$SPRINT_REL" in /*) SPRINT_REL="" ;; esac
     fi
     if [ -z "$SPRINT_REL" ]; then
       ABS_FILE_CANON=$(cd "$(dirname "$ABS_FILE")" 2>/dev/null && pwd)/$(basename "$ABS_FILE")
       case "$ABS_FILE_CANON" in
         "$TOPLEVEL"/*) SPRINT_REL="${ABS_FILE_CANON#"$TOPLEVEL"/}" ;;
         *) echo "fix-issues: cannot normalize $ABS_FILE vs $TOPLEVEL" >&2; exit 1 ;;
       esac
     fi
     case "$SPRINT_REL" in
       /*|../*) echo "fix-issues: $ABS_FILE is outside worktree $TOPLEVEL" >&2; exit 1 ;;
     esac

     # Stage SPRINT_REPORT.md plus any modified tracker files
     # (the *ISSUES* basenames) under $ZSKILLS_ISSUES_DIR. Tracker
     # files are now tracked in git (default docs/issues/), so research
     # blurbs and [x] annotations persist via the sync PR.
     git -C "$TOPLEVEL" add "$SPRINT_REL"
     if [ -n "${ZSKILLS_ISSUES_DIR:-}" ] && [ -d "$ZSKILLS_ISSUES_DIR" ]; then
       ISSUES_REL=$(realpath --relative-to="$TOPLEVEL" "$ZSKILLS_ISSUES_DIR" 2>/dev/null) || ISSUES_REL=""
       if [ -n "$ISSUES_REL" ]; then
         case "$ISSUES_REL" in /*|../*) ISSUES_REL="" ;; esac
       fi
       if [ -n "$ISSUES_REL" ]; then
         # Add only modified/new tracker files; -A scoped to the issues dir.
         git -C "$TOPLEVEL" add -A "$ISSUES_REL" 2>/dev/null || true
       fi
     fi
     STAGED=$(git -C "$TOPLEVEL" diff --cached --name-only)
     # Skip-if-empty guard: an empty sync (no FIXED candidates, nothing
     # annotated) leaves nothing staged — exit cleanly without erroring.
     if [ -z "$STAGED" ]; then
       echo "fix-issues: nothing to commit (empty sync); skipping commit" >&2
     else
       # Loosened check: any superset of staged files that includes
       # SPRINT_REPORT.md and/or tracker files is acceptable. Reject only
       # files outside the expected SPRINT_REL + ISSUES_REL footprint.
       UNEXPECTED=""
       while IFS= read -r f; do
         [ -z "$f" ] && continue
         case "$f" in
           "$SPRINT_REL") ;;
           *)
             if [ -n "${ISSUES_REL:-}" ]; then
               case "$f" in
                 "$ISSUES_REL"/*) ;;
                 *) UNEXPECTED="$UNEXPECTED $f" ;;
               esac
             else
               UNEXPECTED="$UNEXPECTED $f"
             fi
             ;;
         esac
       done <<EOF
$STAGED
EOF
       if [ -n "$UNEXPECTED" ]; then
         echo "fix-issues: unexpected staged files outside SPRINT_REPORT.md / $ISSUES_REL:$UNEXPECTED" >&2
         exit 1
       fi
       if [ -n "$COMMIT_CO_AUTHOR" ]; then
         git -C "$TOPLEVEL" commit --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" -m "docs(sync): tracker research + sprint annotation"
       else
         git -C "$TOPLEVEL" commit -m "docs(sync): tracker research + sprint annotation"
       fi
     fi
   fi
   ```

2. **Dispatch `/land-pr` to open the sync PR.** Sync commits live on the
   worktree's feature branch; this step opens (or detects) a PR and
   monitors CI. The tracking marker is written on main_root so
   `/land-pr` can satisfy it with a `fulfilled.land-pr.<id>` marker on
   successful merge — mirrors `/run-plan` PR mode's pattern
   (`skills/run-plan/modes/pr.md:339-348`, `skills/run-plan/SKILL.md:888`).

   <!-- allow-hardcoded: TZ=America/New_York reason: SYNC_TS is a user-facing wall-clock stamp on the PR title/body and SYNC_ID; matches the established sync-mode idiom for human-readable dates. Per-skill $TIMEZONE migration is scoped to plans/SKILL_FILE_DRIFT_FIX.md, not this issue -->
   ```bash
   # SYNC_TS: stable per sync invocation. SYNC_ID propagates to /land-pr.
   SYNC_TS="${SYNC_TS:-$(TZ=America/New_York date +%Y%m%d-%H%M%S)}"
   SYNC_ID="fix-issues.sync.${SYNC_TS}"

   # Resolve main_root and pipeline scope; derive PIPELINE_ID if not already
   # set by the sprint-mode preamble (sync may run standalone).
   MAIN_ROOT="${MAIN_ROOT:-$(cd "$(git rev-parse --git-common-dir)/.." && pwd)}"
   PIPELINE_ID="${PIPELINE_ID:-fix-issues.${SYNC_TS}}"
   mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"

   # Write the requires.land-pr marker on main_root BEFORE dispatch. The
   # matching fulfilled.land-pr.<SYNC_ID> is written by /land-pr ONLY on
   # STATUS=merged (created/monitored do not fulfill — by design; the
   # orchestrator may re-run sync after CI completes to fulfill).
   printf 'skill: land-pr\nrequired-by: fix-issues-sync\ndate: %s\n' \
     "$(TZ=UTC date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${SYNC_ID}"

   # Build the PR body file. Body intentionally OMITS GitHub auto-close
   # directives (Close[sd]? / Fixe[sd]? / Resolve[sd]? #N) — sync closes
   # approved issues itself via `gh issue close` in Step 5 sub-step 3,
   # only after /land-pr returns a success status (AC-P.3 of
   # `docs/plans/FIX_ISSUES_SYNC_HARDENING.md`).
   RESULT_FILE=$(mktemp)
   BODY_FILE=$(mktemp)
   {
     printf '## Summary\n`/fix-issues sync` on %s updated trackers.\n\n' \
       "$(TZ=America/New_York date +%F)"
     printf '## Test plan\n- [x] Tracker diff reviewed by user before merge.\n'
   } > "$BODY_FILE"

   PR_TITLE="sync: $(TZ=America/New_York date +%F)"
   SYNC_BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)

   # /land-pr arg vector. Mirrors run-plan PR mode (modes/pr.md:339-348)
   # MINUS the auto-merge flag. Sync is always interactive — closing
   # issues on GitHub requires human approval — so the auto-merge flag
   # is intentionally omitted. The CI-monitor-suppression flag is also
   # omitted (CI monitoring is desired; the orchestrator awaits resting
   # state).
   LAND_ARGS="--branch=$SYNC_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sync --worktree-path=$TOPLEVEL --tracking-id=$SYNC_ID"

   # Echo the pipeline id for transcript-propagation (matches /do pr's
   # tier-2 idiom at `skills/do/modes/pr.md:203`). Do NOT env-export
   # the variable — the conformance test at
   # `tests/test-skill-conformance.sh:1445` forbids the env-export form
   # of this variable as a side-channel; the echo form is the canonical
   # propagation idiom. Note: this means `/land-pr`'s Step 8b cannot
   # read PIPELINE_ID from the env in the same-shell case (it falls
   # back to `run-plan.$TRACKING_ID` which doesn't exist for sync —
   # issue #300). Sync therefore writes its own
   # `fulfilled.land-pr.<id>` marker after /land-pr returns merged
   # (Step 5 sub-step 3 below), closing the #300 hole without violating
   # the conformance discipline.
   echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

   # Dispatch /land-pr via the Skill tool. The Skill tool loads /land-pr's
   # prose into the current (orchestrator) context — its internal bash
   # blocks run here. After /land-pr returns, $RESULT_FILE is populated.
   #
   # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

   if [ ! -f "$RESULT_FILE" ]; then
     echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
     exit 1
   fi

   # Parse result-file via canonical allow-list pattern. Unknown keys WARN
   # but do not fail — forward-compatible with /land-pr schema additions.
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

   # LP[STATUS] drives sub-step 3 (close approved issues on success) and
   # the report below. fulfilled.land-pr.${SYNC_ID} is present on
   # main_root iff LP[STATUS]=merged.
   ```

3. **Close approved issues on GitHub** — only if `/land-pr` returned
   `merged`. `created` and `monitored` mean the PR is open but unmerged;
   the close happens on the NEXT sync run after auto-merge completes (or
   after a human merges the PR). Per memory
   `feedback_automerge_blocked_means_act.md`: auto-merge BLOCKED is the
   rest state to wait through, not to close on (issue #282 — closing on
   `created`/`monitored` recreates the AC-P.3 divergence that PR #271
   fixed). On any non-`merged` status (`created`, `monitored`,
   `push-failed`, `rebase-conflict`, `create-failed`, `monitor-failed`,
   `merge-failed`, `rebase-failed`), leave issues OPEN to prevent state
   divergence between closed-on-GH and unmerged-in-main (AC-P.3).

   ```bash
   case "${LP[STATUS]:-}" in
     merged)
       # Write the fulfilled.land-pr marker into the sync pipeline subdir
       # (issue #300). /land-pr's Step 8b can't write it itself: it falls
       # back to PIPELINE_ID=run-plan.$TRACKING_ID when ZSKILLS_PIPELINE_ID
       # is unset, and the conformance test (test-skill-conformance.sh:1445)
       # forbids env-exporting this variable. Sync therefore writes the
       # marker itself once /land-pr returns merged — same end-state, no
       # side-channel.
       printf 'skill: land-pr\nid: %s\npr: %s\nbranch: %s\ndate: %s\n' \
         "$SYNC_ID" "${LP[PR_URL]:-}" "$SYNC_BRANCH" \
         "$(TZ=UTC date -Iseconds)" \
         > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$SYNC_ID"
       # For each approved issue, close with the fix-commit reference.
       gh issue close <N> --comment "Fixed in commit <hash>. <brief description of fix>. Tests: <test file(s)>."
       ;;
     *)
       echo "Skipping gh issue close — /land-pr STATUS=${LP[STATUS]:-unknown}. Approved issues remain OPEN; re-run sync after CI completes (auto-merge) or after the underlying landing failure is resolved." >&2
       ;;
   esac
   ```

4. **Report:**
   ```
   Sync complete.
     Open issues: N
     Newly researched: M
     Tracker files updated: K
     Closed (verified fixed): J (#NNN, #NNN, ...)
     Likely fixed (needs human review): L (#NNN, #NNN)
     Gaps: [any GH issues not in any tracker]
     PR: ${LP[PR_URL]:-(none)} — STATUS=${LP[STATUS]:-unknown}
     Closed on GitHub (only if /land-pr success): J (#NNN, ...) or "deferred — /land-pr STATUS=<status>"
   ```

5. **Exit.**

## Plan (if `plan` is present)

Draft plans for issues previously skipped as "too complex for batch fix."
Accepts optional `auto` — `/fix-issues plan auto` skips the selection gate
and drafts plans for all found issues.

1. **Find skipped issues from `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`.** Scan the entire
   sprint report for issue numbers under "Skipped" / "Too Complex" /
   "Remaining Open" headings. Use grep to extract candidate numbers
   (handles bare `#NNN`, ranges like `#148-#168`, and `#NNN, #MMM` lists):

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: filename basename suffixed onto $ZSKILLS_AUDIT_DIR (resolved via zskills-paths.sh); the basename token itself remains literal so the regex still flags the /SPRINT_REPORT.md tail -->
   ```bash
   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   grep -nE '#[0-9]+' "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" | grep -iE 'skip|complex|remain'
   ```

   Then for each candidate `#N`:
   - Check `$ZSKILLS_PLANS_DIR/` for an existing executable plan covering it:
     `grep -l "#$N\b" "$ZSKILLS_PLANS_DIR"/*.md` (existing plan = skip)
   - Check GitHub state: `gh issue view "$N" --json state -q .state`
     (`OPEN` = candidate; `CLOSED` = skip)

   Build the working list of `needs-plan` issues from candidates that
   have NO existing plan AND are still `OPEN`. Skip the rest.

2. **Deduplicate** — check `plans/` for existing plans that already cover
   each issue. Also check whether the issue is still open on GitHub
   (`gh issue view <N> --json state`). Remove issues that already have
   a plan or are closed.

3. **Present findings** (unless `auto`):
   > Found N issues needing plans:
   > | # | Title | Source |
   > |---|-------|--------|
   > | #142 | Drag into subsystem | Sprint 2026-03-17: Skipped — Too Complex |
   > | #363 | Algebraic loop detection | Sprint 2026-03-16: Remaining Open |
   > ...
   > Already have plans: #NNN, #NNN (skipped)
   > Already closed: #NNN (skipped)
   >
   > Which issues should I draft plans for? (all / comma-separated numbers / none)

   Wait for the user's selection before proceeding. If `auto`, skip this
   step and plan all of them.

4. **For each selected issue**, create a delegation requirement marker and
   then dispatch `/draft-plan`. The marker goes under fix-issues' own
   per-sprint subdir ($PIPELINE_ID) — the parent reconciles child
   fulfillment in its own scope:
   ```bash
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
   printf 'skill: draft-plan\nparent: fix-issues\nissue: %s\ndate: %s\n' \
     "$ISSUE_NUMBER" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.draft-plan.$ISSUE_NUMBER"
   ```
   Then dispatch `/draft-plan` with:
   - The issue number and full body (`gh issue view <N> --json body`)
   - Any research blurb from the tracker files
   - Output path: `plans/{issue-slug}.md`

5. **Report:**
   > Plans drafted: N
   > - plans/foo-bar.md (#123) — [one-line summary]
   > - plans/baz-qux.md (#456) — [one-line summary]
   > Already had plans: M (skipped)
   > Closed issues: K (skipped)
   > User declined: J

6. **Exit.** Plans are ready for `/run-plan` execution.

## Phase 0 — Schedule (if `every` is present)

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression. The LLM interprets
   natural scheduling expressions.

   **For interval-based schedules** (`4h`, `2h`, `30m`): use the CURRENT
   minute as the offset so the first fire is a full interval from now, not
   aligned to midnight. Check the current minute with `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *` (fires at :09 past every 4th hour)
   - `2h` at minute 15 → `15 */2 * * *`
   - `30m` → `*/30 * * * *` (no offset needed for sub-hour)
   - `1h` at minute 9 → `9 * * * *`

   **For time-of-day schedules** (`day at 9am`, `weekday at 2pm`): offset
   round minutes by a few to avoid API busy marks:
   - `day at 9am` → `3 9 * * *`
   - `day at 14:00` → `3 14 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — use `CronList` to list existing cron jobs. Use
   `CronDelete` to remove any whose prompt starts with `Run /fix-issues`
   (prevents duplicate schedules from accumulating).

3. **Reconstruct the arguments** for the cron prompt. Always include `now`
   in the cron prompt so each cron fire runs immediately AND re-registers
   itself (self-perpetuating). Note: this `now` is for the CRON's invocation,
   not the current invocation — the user controls whether THIS run executes
   immediately via their own `now` flag:
   ```
   Run /fix-issues <N> [focus] auto every <schedule> now
   ```

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the reconstructed command from step 3

5. **Confirm** — tell the user, including the estimated wall-clock time of
   the next run. Compute from the cron expression. **Always show times in
   America/New_York (ET)** — use `TZ=America/New_York date` for conversion,
   not the system timezone (which may be UTC). Example:

   If `now` is present:
   > Fix-issues sprint scheduled every 4h. Running now.
   > Next auto-sprint after this one: ~8:15 PM ET (cron ID XXXX).

   If `now` is NOT present:
   > Fix-issues sprint scheduled every 4h.
   > First run: ~4:15 PM ET (cron ID XXXX).
   > Use `/fix-issues next` to check, `/fix-issues stop` to cancel.

6. **If `now` is present:** proceed to Phase 1 (run immediately).
   **If `now` is NOT present:** **Exit.** The cron will fire at the scheduled
   time. Do not run a sprint now.

**End-of-sprint scheduling note:** when a sprint finishes and a cron is
active, always include the estimated next run time with timezone in the
completion message. Example:
> Sprint complete. Next auto-sprint in ~3h 45m (~11:30 PM ET, cron XXXX).

**Dashboard + cron lifecycle note:** when `dashboard` is the source and
Ready is empty, each cron fire still re-registers normally (queue-worker
pattern — user manages lifecycle via `/fix-issues stop`). Do NOT auto-kill
the cron on empty Ready; new issues may drag onto Ready before the next fire.

If `every` is NOT present, skip this phase entirely and proceed to Phase 1
(bare invocation always runs immediately).

## Phase 1 — Preflight & Sync

**IMPORTANT: Complete ALL steps (1-6 + Phase 1b) before Phase 2.** Do NOT
skip tracker updates or research to "save time." Dispatching agents without
research blurbs causes misinterpretation — agents guess from titles and
implement the wrong fix. This has happened repeatedly.

### Sprint tracking sentinel

When mode is sprint (N provided), construct the per-sprint unique
`$SPRINT_ID` and `$PIPELINE_ID` FIRST (before any other tracking write),
then front-run the shared `ensure-worktree.sh` gate (mirror of standalone
`## Sync` mode — closes #325), THEN create the pipeline sentinel. All
subsequent Phase 1 writes (`ISSUES_PLAN.md` row-writer, tracker updates)
land inside the worktree because `ZSKILLS_PATHS_ROOT` is re-anchored to
the worktree root. Phase 5's `SPRINT_REPORT.md` append + commit + `/land-pr`
dispatch also run inside the worktree.

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking"

# Per-sprint unique ID (per Phase 1 design doc OQ3). Prevents concurrent
# fix-issues sessions from colliding on the literal "sprint" suffix. The
# ISSUE_TITLE slug is a human-readable tag; the UTC timestamp guarantees
# uniqueness across concurrent sprints on the same host.
#
# LIFTED above the ensure-worktree.sh preamble (closes #325) so the
# preamble's `--pipeline-id "$PIPELINE_ID"` has a value to bind to.
ISSUE_TITLE_SLUG=$(printf '%s' "${ISSUE_TITLE:-sprint}" | tr -cd 'a-z0-9' | head -c 8)
[ -z "$ISSUE_TITLE_SLUG" ] && ISSUE_TITLE_SLUG="sprint"
SPRINT_ID="sprint-$(date -u +%Y%m%d-%H%M%S)-$ISSUE_TITLE_SLUG"
PIPELINE_ID="fix-issues.$SPRINT_ID"
PIPELINE_ID=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
# Recover SPRINT_ID after sanitization (strip the "fix-issues." prefix).
SPRINT_ID="${PIPELINE_ID#fix-issues.}"
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
```

**Worktree gate (sprint-mode parity with standalone `## Sync` — closes #325).**
Before any Phase 1 write to a tracker file or `SPRINT_REPORT.md`, front-run
`ensure-worktree.sh` so all subsequent writes land inside the worktree, not
on `main`'s working tree. Mirrors the preamble at the top of `## Sync` above.

```bash
HELPER="$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/ensure-worktree.sh"
if [ ! -x "$HELPER" ]; then
  echo "fix-issues: ensure-worktree.sh missing at $HELPER — run /update-zskills to repair" >&2
  exit 11
fi
WT_PATH=$(bash "$HELPER" \
  --prefix fix-issues \
  --pipeline-id "$PIPELINE_ID" \
  --purpose "fix-issues sprint; sprint=${SPRINT_ID}" \
  "${SPRINT_ID}")
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "ensure-worktree failed (rc=$RC) for /fix-issues sprint mode" >&2
  exit "$RC"
fi
if [ -n "$WT_PATH" ]; then
  cd "$WT_PATH" || { echo "fix-issues: cd $WT_PATH failed" >&2; exit 1; }
  export ZSKILLS_PATHS_ROOT="$WT_PATH"  # R3-1 — re-anchor downstream path resolution
fi
```

Now write the pipeline sentinel under `$MAIN_ROOT/.zskills/tracking/` —
the sentinel is parent-scope tracking (by design) and stays on main_root
regardless of which worktree the sprint executes from:

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
if [ ! -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID" ]; then
  printf 'skill: fix-issues\nmode: sprint\ncount: %s\nfocus: %s\nstartedAt: %s\n' \
    "$N" "${FOCUS:-default}" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
    > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID"
fi
```

### Preflight checks (before doing anything else)

Before starting the sprint, check for stale state from a previous failed run:

1. **In-progress git operation?**
   ```bash
   ls .git/CHERRY_PICK_HEAD .git/MERGE_HEAD .git/REBASE_HEAD 2>/dev/null
   git status --porcelain | grep '^UU\|^AA\|^DD'
   ```
   If either command produces output, the working tree has an unfinished
   cherry-pick, merge, or rebase — likely from a previous failed sprint.
   **STOP.** Invoke the Failure Protocol.

   Note: normal uncommitted changes (modified plan files, logs) are expected
   and are NOT a reason to stop. Phase 6 stashes those before cherry-picking.

2. **Stash stack?**
   ```bash
   git stash list
   ```
   If there is a stash with message containing "pre-cherry-pick", a previous
   sprint's stash was never restored. **STOP.** Alert the user — they need to
   `git stash pop` or `git stash drop` before a new sprint can start safely.

3. **Leftover sprint worktrees?**
   ```bash
   git worktree list
   ```
   If worktrees from a previous sprint exist, warn the user. They may contain
   unapplied fixes. Do not remove them — just note their presence and continue.

If any preflight check fails, invoke the **Failure Protocol** (kill cron,
alert user, write failure to report).

### Sync

1. **Fetch all open GitHub issues:**
   ```bash
   gh issue list --state open --limit 500 --json number,title,labels,createdAt
   ```

   **Fetch the open-issue list AND count safely** for the bootstrap and
   row-writer steps below (single `gh` call, parsed for both count and
   number array). `grep -cE` over single-line JSON would return line-count
   not match-count — use `grep -oE | mapfile`:

   ```bash
   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   # Fetch number+title+labels in ONE call so the row-writer below can
   # reuse this blob (no N+1 `gh issue view` loop — see issue #280).
   GH_OUT=$(gh issue list --state open --limit 500 --json number,title,labels 2>&1) \
     || { echo "ERROR: 'gh issue list' failed:" >&2; echo "$GH_OUT" >&2; exit 1; }
   mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
   OPEN_COUNT=${#OPEN_NUMS[@]}
   ```

   **Bootstrap empty `$ZSKILLS_ISSUES_DIR/`.** If the issues directory has
   zero tracker files AND there are open issues, create
   `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` from a frontmatter+header template
   so subsequent steps have something to write rows into. If there are zero
   open issues, exit early — no empty tracker, no PR, no noise. Empty
   `issues_dir` now triggers bootstrap; this failure mode is structurally
   prevented.

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
   <!-- allow-hardcoded: TZ=America/New_York reason: bootstrap stamps the "created" date and the in-body "Created by /fix-issues sync on $TODAY" line in America/New_York to match the established tracker idiom across skills; per-skill $TIMEZONE migration is scoped to plans/SKILL_FILE_DRIFT_FIX.md, not this issue -->
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

   **Row-writer for residual issues.** For each open GH issue not yet
   referenced in any tracker, look up its title+labels in the batched
   `$GH_OUT` blob (single `gh issue list` call from the bootstrap step
   above — no N+1 `gh issue view` loop; see issue #280) and append a
   `### #N — <title>` row with `**Labels:**` and
   `**Verdict:** NOT YET RESEARCHED`. The membership check is **anchored**
   so `bug#23` does not match `#23`; it uses `grep -qP` with PCRE
   lookarounds so markdown-bold (`**#NNN**`) and `### #NNN` headings match
   (issue #301 — the prior ERE alternation `(^|[^0-9A-Za-z_])#$N($|[^0-9])`
   silently missed those formats). Title/labels parsing uses Python json
   so JSON-escaped quotes (`"Fix \"foo\" handling"`) don't truncate the
   row (issue #280 — `grep -oE '"title":"[^"]*"'` stopped at the first
   literal `"` and corrupted the tracker).

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
   ```bash
   NEW_RESEARCHED_COUNT=0
   for N in "${OPEN_NUMS[@]}"; do
     if grep -qP "(?<![0-9])#$N(?![0-9])" \
          "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null; then
       continue
     fi
     # Look up title+labels for issue $N in the cached $GH_OUT blob via
     # Python json. Per memory feedback_python_is_required.md + feedback_no_jq_in_skills.md:
     # Python json is the canonical parser for non-trivial JSON here; `jq`
     # the binary is what's prohibited, not all JSON parsers.
     ISSUE_META=$(printf '%s' "$GH_OUT" | python3 -c '
import json, sys
data = json.load(sys.stdin)
target = int(sys.argv[1])
for it in data:
    if it.get("number") == target:
        title = it.get("title", "")
        labels = ",".join(l.get("name", "") for l in it.get("labels", []) or [])
        # Two NUL-delimited fields so titles/labels with newlines/commas survive.
        sys.stdout.write(title + "\x1f" + labels)
        break
' "$N") || { echo "ERROR: python3 parse of cached gh issue list failed for #$N" >&2; exit 1; }
     ISSUE_TITLE_RAW="${ISSUE_META%%$'\x1f'*}"
     ISSUE_LABELS="${ISSUE_META#*$'\x1f'}"
     {
       printf '\n### #%s — %s\n' "$N" "$ISSUE_TITLE_RAW"
       printf '\n**Labels:** %s\n' "${ISSUE_LABELS:-(none)}"
       printf '\n**Verdict:** NOT YET RESEARCHED\n'
     } >> "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
     NEW_RESEARCHED_COUNT=$((NEW_RESEARCHED_COUNT + 1))
   done
   ```

2. **Find gaps** between GitHub open issues and plan tracker files. List
   the trackers, then for each open GH issue number check whether it
   appears in any tracker:

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
   ```bash
   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   ls "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null

   gh issue list --state open --limit 500 --json number -q '.[].number' \
     | while read -r N; do
         # PCRE lookarounds so markdown-bold (`**#NNN**`) and `### #NNN`
         # headings match — see issue #301.
         if ! grep -qP "(?<![0-9])#$N(?![0-9])" "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null; then
           echo "GAP: #$N not in any tracker"
         fi
       done
   ```

3. **Tally label distribution** to see current spread:

   ```bash
   gh issue list --state open --limit 500 --json labels \
     -q '.[].labels[].name' | sort | uniq -c | sort -rn
   ```

4. **Update ALL issue trackers** — scan `$ZSKILLS_ISSUES_DIR/` for tracker files:
   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
   ```bash
   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   ls "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null
   ```
   Ensure each tracker reflects current GitHub state. Add new issues to
   the appropriate tracker based on domain.

5. **Identify gaps** — any GH issues not tracked in any plan file? Add them to
   the appropriate tracker.

6. **Research new issues** — for each issue added in step 5 (or any issue
   lacking a research blurb in its tracker entry), dispatch research agents
   using the same workflow as the standalone `sync` command:
   1. Read the full issue body (`gh issue view <N>`)
   2. Search the codebase for the affected code
   3. Write a concise research blurb (what's wrong, where, suggested approach)
   4. Add the blurb to the appropriate tracker file

   Without this step, Phase 2 prioritizes from bare titles and Phase 3
   dispatches agents with no context — leading to misinterpretation.
   Past failure: #387 "reset button" was interpreted as "clear canvas"
   instead of "reset mappings to defaults" because only the title was read.

   In `auto` mode, dispatch research agents in parallel (up to 3 at a time)
   and proceed after all complete. In interactive mode, present the research
   blurbs before moving to Phase 1b.

## Phase 1b — Read Full Issue Bodies & Plan Context

**Before prioritizing**, gather full context for every candidate issue:

1. **Fetch the issue body and comments from GitHub:**
   ```bash
   gh issue view <N> --json number,title,body,labels,comments
   ```

2. **Fetch the research blurb from plan files:**
   ```bash
   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   grep -A 30 '#<N>' "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md 2>/dev/null
   ```
   Plan blurbs contain root cause analysis, affected files, suggested fixes,
   and effort estimates. This context was gathered when the issue was filed —
   don't waste time re-researching what's already documented.

Both steps are **mandatory**. Titles are often vague or misleading. The body
and plan blurb together are the spec. You cannot prioritize or write accurate
agent prompts without reading both.

For each candidate, note:
- What the user actually described (not what the title implies)
- Root cause and affected files (from plan blurb)
- Repro steps if provided
- Suggested fix approach (from plan blurb)
- Context metadata (model name, browser, screen size)

### Post-preflight tracking

After Phase 1 (preflight + sync + research) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.preflight"
```

## Phase 2 — Prioritize

### Dashboard source branch (if `dashboard` is present)

When `$DASHBOARD_MODE=1`, REPLACE the model-layer ranking below with a
direct read from the dashboard's Ready queue. The Ready array reflects
user drag order from the in-app feedback dashboard — it IS the priority.
No rubric, no boosting, no triage at the candidate-selection step (Phase
2's triage subsection still applies once the candidates are chosen).

Pure reads of `$MAIN_ROOT/.zskills/monitor-state.json` do NOT need
`flock -x` because dashboard writes use `os.replace()` (atomic on POSIX),
so concurrent readers always see a complete file — see
`skills/work-on-plans/SKILL.md:128-154` for the lock-on-write-only
convention. Parse the JSON with Python json (NOT bash regex on JSON
arrays — same discipline as Phase 1's row-writer).

```bash
if [ "$DASHBOARD_MODE" = "1" ]; then
  MAIN_ROOT="${MAIN_ROOT:-$(cd "$(git rev-parse --git-common-dir)/.." && pwd)}"
  MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"

  # Reuse the cached OPEN_NUMS array fetched in Phase 1's sync step (gh
  # issue list --state open ...). If for some reason it is not set in
  # this scope, refetch it the same way Phase 1 does.
  if [ -z "${OPEN_NUMS+x}" ]; then
    GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1) \
      || { echo "ERROR: 'gh issue list' failed:" >&2; echo "$GH_OUT" >&2; exit 1; }
    mapfile -t OPEN_NUMS < <(printf '%s' "$GH_OUT" | python3 -c '
import json, sys
for it in json.load(sys.stdin):
    n = it.get("number")
    if isinstance(n, int):
        print(n)
')
  fi

  # Three empty cases all behave the same:
  #   (1) monitor-state.json missing
  #   (2) .issues or .issues.ready key absent
  #   (3) issues.ready empty, OR intersection-with-open is empty
  # All three -> print message + exit 0. Do NOT fall through to the
  # default rubric. Do NOT error.
  if [ ! -f "$MONITOR_STATE" ]; then
    echo "Dashboard Ready is empty — nothing to do"
    exit 0
  fi

  # Read issues.ready in drag order; intersect with live open issues;
  # cap to N. Python json — never bash regex on a JSON array.
  DASHBOARD_PICKS=$(OPEN_NUMS_JOINED="$(printf '%s,' "${OPEN_NUMS[@]}")" \
    N="$N" python3 -c '
import json, os, sys
state_path = sys.argv[1]
try:
    with open(state_path, "r") as f:
        state = json.load(f)
except (OSError, json.JSONDecodeError):
    sys.exit(0)
issues = state.get("issues") or {}
ready = issues.get("ready") or []
if not isinstance(ready, list) or not ready:
    sys.exit(0)
open_raw = os.environ.get("OPEN_NUMS_JOINED", "")
open_set = set()
for tok in open_raw.split(","):
    tok = tok.strip()
    if tok.isdigit():
        open_set.add(int(tok))
n_cap = int(os.environ.get("N") or "0") or len(ready)
picks = []
for entry in ready:
    # ready entries may be ints or dicts with .number — be permissive
    if isinstance(entry, int):
        num = entry
    elif isinstance(entry, dict):
        num = entry.get("number")
    else:
        try:
            num = int(entry)
        except (TypeError, ValueError):
            continue
    if not isinstance(num, int):
        continue
    if num in open_set:
        picks.append(num)
        if len(picks) >= n_cap:
            break
print(" ".join(str(p) for p in picks))
' "$MONITOR_STATE")

  if [ -z "$DASHBOARD_PICKS" ]; then
    echo "Dashboard Ready is empty — nothing to do"
    exit 0
  fi

  # Hand the picks to the rest of Phase 2 via a CANDIDATE_ISSUES array.
  # Downstream triage subsection + Phase 3 dispatch consume this array
  # the same way they would consume the rubric's output. Skip the
  # rubric/focus/default-ranking text below — the picks ARE the order.
  read -r -a CANDIDATE_ISSUES <<<"$DASHBOARD_PICKS"
  echo "Dashboard candidates (drag order, capped to N=$N): ${CANDIDATE_ISSUES[*]}"
fi
```

When the dashboard branch returns picks, skip the ranking/focus rubric
below and proceed directly to the **Triage** subsection with
`CANDIDATE_ISSUES` as the input list. The triage routing (in-batch
fix-agent vs `/quickfix` vs `/draft-plan` vs skip) still applies — the
dashboard only overrides the *selection*, not the *routing*.

### Default rubric (when `dashboard` is NOT present)

Present the next N issues to fix as a ranked table:

| Priority | # | Title | Severity | Domain | Effort | Tracker |
|----------|---|-------|----------|--------|--------|---------|

**If a focus argument is provided**, issues in that domain are boosted to the
top, then the remaining slots filled by default priority.

**Default ranking criteria (in order):**
1. New issues not yet attempted (user feedback, recently filed)
2. Correctness defects (from issue trackers tagged as correctness)
3. Critical/high severity bugs
4. Quick wins (15 min – 1 hour)
5. Issues with clear repro steps
6. Test gaps (from issue trackers tagged as test quality)

### Triage: vague, complex, or interrelated issues

While building the ranked list, classify each candidate into ONE of the
five routing tiers below. Picking the right tier is the whole point of
triage — the wrong tier produces either a 1000-line plan for a 50-line
fix (over-routing to `/draft-plan`) or an unreviewed PR for a subtle
bug (under-routing to in-batch fix-agent).

- **Clear and doable as one PR** — repro steps, expected behavior,
  affected files identified, scope fits a single coherent commit.
  Include in the sprint as an in-batch fix-agent dispatch. This is the
  default and the cheapest path.

- **Clear and doable as one PR, but needs review** — clear spec, single
  PR scope, but the fix has multiple coordinate-with-discipline steps
  (e.g., touches multiple files, requires version bumps, has subtle
  scope-creep risk). Dispatch `/quickfix` for the issue, which adds
  pre-execution plan-review (catches scope drift before commit) plus CI
  poll + fix-cycle without you hand-orchestrating each step. Per-issue
  /quickfix dispatch replaces the in-batch fix-agent for this category.

- **Bug with unclear cause** — symptom is reported but no root-cause
  hypothesis emerges from the issue body or research blurb. Don't guess.
  Skip the issue with note: "Needs deeper investigation — could not
  determine root cause in batch mode. Run `/investigate #NNN`." This is
  a manual handoff (`/investigate` runs interactively, not in-batch).

- **Plan-scale** — clear spec but would require 500+ lines across
  multiple subsystems, multi-phase coordination, integration-point
  design, or hook interactions. Not a batch-fix item.
  - Interactive: report "this needs `/run-plan`, not `/fix-issues`"
  - Auto: skip it, report as "Skipped: plan-scale, run /draft-plan"
  - If `plans/PLAN_INDEX.md` exists, grep plan files for the issue
    number (e.g., `#NNN`). If a plan already covers this issue, note
    which plan in the skip reason. If no plan covers it, add to the
    skip note: "Consider `/draft-plan` for #NNN."

- **Too vague** — no repro steps, no expected behavior, body is empty or
  just "it's broken." You don't know WHAT to fix.
  - Interactive: flag it and ask the user for clarification
  - Auto: skip it, report as "Skipped: insufficient context" in
    $ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md

**"Too vague" means you don't know WHAT to do — not that you don't know
HOW.** If the issue clearly describes the problem but the fix is hard,
that's not vague — that's work. Never use "vague" as an excuse to skip
hard issues.

**Picking between in-batch fix-agent and `/quickfix`.** The in-batch
fix-agent is appropriate when the fix is mechanical enough that
post-execution diff review (which `/fix-issues` Phase 4 already
dispatches) is sufficient. `/quickfix` is appropriate when *before* the
fix, you want a second pair of eyes on the plan — typically when the
issue has multiple discipline surfaces (version bumps + mirror, test
updates + source change, doc update + behavior change). The
`/quickfix` plan-reviewer's auto-REVISE on >4 Acceptance bullets is
the mechanical signal that says "this is bigger than `/quickfix` —
escalate to `/draft-plan`."

### Group by dependency and file overlap

Before dispatching agents, check for interrelated issues:

- **Same root cause** — if #100 and #101 are both caused by an off-by-one
  in Solver.js, group them for the same agent. One agent, one worktree,
  one fix closes both.
- **Same file** — if #200 and #201 both need changes to Parser.js, group
  them for the same agent. Separate worktrees would produce conflicting
  cherry-picks.
- **Prerequisite relationship** — if fixing #300 requires the fix from #299
  to be in place, give both to the same agent in order.

Tell the agent when issues are related: "Issues #100 and #101 share
root cause X in file Y — consider fixing them together with a single commit."

**Bundling beyond N.** When prioritizing, if additional open issues would
naturally be fixed in the same session (same component, same area of code)
or appear to have the same root cause, the orchestrator should include
them alongside the selected issue for the same agent. These don't count
toward N. In interactive mode, show bundled extras in the approval list
with the rationale so the user can adjust. This keeps `/fix-issues 1
every 1h` efficient — one agent, one worktree, but it picks up tightly
coupled neighbors instead of leaving them for the next sprint.

### Present the list

- **Without `auto`:** **Wait for user approval** of the list before proceeding.
  Include the grouping rationale so the user can adjust.
- **With `auto`:** Present the ranked table for the record, then proceed
  immediately using the ranking criteria above.

### If no actionable issues found

If ALL candidates are too vague, too complex, or already attempted:

1. **Auto-sync before giving up.** Run the full Sync workflow (Steps
   1-5). In auto mode, auto-close issues with FIXED verdict (commit
   hash + tests — the same bar as interactive sync, just without the
   approval gate). LIKELY FIXED and UNCLEAR still require human
   judgment and are skipped. Then re-run Phase 1b and Phase 2 to
   re-evaluate the candidate pool. If actionable issues are now
   available, proceed to Phase 3 normally.

   **Only sync once per sprint.** If still empty after, proceed to step 2.

2. **If still no actionable issues after refresh:**
   - Write a minimal sprint section to `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`: `## Sprint —
     YYYY-MM-DD HH:MM [UNFINALIZED]` with "No actionable issues found
     (synced twice)" and the skip reasons.
   - **Do NOT kill the cron** — new issues may be filed before the next run.
   - After **3 consecutive empty runs**, add a note: "3 consecutive runs
     with no actionable issues. Run `/fix-issues stop` if no new issues
     are expected." Do NOT auto-stop — that's the user's call.
   - **Exit.** Skip Phases 3-6.

### Post-prioritize tracking

After Phase 2 (prioritize) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\nissueCount: %d\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" "$ISSUE_COUNT" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.prioritize"
```

## Phase 3 — Execute (agent teams in worktrees)

**All modes create a per-issue worktree via `.claude/skills/create-worktree/scripts/create-worktree.sh`
BEFORE dispatching the fix agent, and dispatch agents WITHOUT
`isolation: "worktree"`.** The distinction between modes is not *how* the
worktree is created — it is *what happens at landing*: `cherry-pick`
extracts commits from the worktree branch onto main, `direct` fast-forwards
the worktree branch into main (Phase 6 detail), and `pr` opens a PR per
issue. See the "Worktree setup (cherry-pick and direct modes)" subsection
below for the baseline `create-worktree.sh` invocation, and the "PR mode
(Phase 3)" subsection for PR-mode-specific branch naming.

**Before dispatching any fix Agent:** check `agents.min_model` in `.claude/zskills-config.json`.
If set, use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch
with a lower-ordinal model than the configured minimum.

**1 issue per agent, parallel dispatch.** Each issue gets its own agent
in its own pre-created worktree (materialised via `create-worktree.sh`
before dispatch for all modes — see "Worktree setup" below).

There are TWO distinct caps on parallelism — they look similar but solve
different problems and live at different scopes:

1. **Per-message dispatch I/O contention cap (hardcoded 3).** Within one
   Agent-tool dispatch message, dispatch at most 3 worktree agents per message.
   If you have more than 3, dispatch the first 3, wait for them to return,
   then dispatch the next batch. Five concurrent `git checkout` operations
   cause I/O contention on 9p filesystems — checkouts stall at ~72% and the
   Agent framework times out, leaving orphaned worktree directories. This
   is a property of dispatch-time filesystem contention; it does NOT bound
   how many worktrees end up alive simultaneously across the sprint.

2. **Sprint-wide aggregate live-worktree cap (`$ZSKILLS_MAX_CONCURRENT_WORKTREES`,
   default 3, from `execution.max_concurrent_worktrees` in
   `.claude/zskills-config.json`).** Bounds the total number of live
   `fix/issue-*` worktrees the sprint keeps alive at any moment. By
   mid-sprint, batches dispatched under cap (1) above would otherwise
   be all alive concurrently (each running tests, a verifier, a CI run)
   — which OOMs/stalls resource-constrained dev containers. This cap
   makes the sprint defer new dispatches when live count is already at
   the cap, and waits for prior worktrees to land via cron retry.

   See "Live worktree count check" below — this gate runs BEFORE the
   dispatch loop and either reduces the batch size or defers the whole
   fire.

- **Interrelated issues** (same root cause or same files from Phase 2
  grouping) share one agent and one worktree. Tell the agent which
  issues are grouped and why.
- **Unrelated issues get separate agents.** Never batch unrelated hard
  issues into one agent — this caused a 4.5h bottleneck when one agent
  got 4 diverse issues sequentially.

### Live worktree count check

Run this **before** the dispatch loop (cherry-pick / direct / PR mode all):

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: filename basename suffixed onto $ZSKILLS_AUDIT_DIR (resolved via zskills-paths.sh); the basename token itself remains literal so the regex still flags the /SPRINT_REPORT.md tail -->
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
# $ZSKILLS_MAX_CONCURRENT_WORKTREES is now set (defaults to 3 when the
# execution.max_concurrent_worktrees field is absent or malformed).

# Count live fix/issue-* worktrees across the repo (resume detection is
# directory-based, so this is the authoritative live-count). Both PR-mode
# (branch fix/issue-NNN) and cherry-pick/direct mode (branch fix-issue-NNN)
# branches are counted via two grep passes against `git worktree list
# --porcelain`. Each worktree contributes exactly one `branch refs/heads/...`
# line in the porcelain output.
LIVE_COUNT=$(git worktree list --porcelain \
  | grep -cE '^branch refs/heads/fix[/-]issue-')

CAP="$ZSKILLS_MAX_CONCURRENT_WORKTREES"
N_REQUESTED="${#TO_DISPATCH[@]}"  # how many fix agents this sprint wants to dispatch
SLOTS=$(( CAP - LIVE_COUNT ))
if [ "$SLOTS" -le 0 ]; then
  # All slots already taken — defer the entire fire.
  echo "Live worktree count ($LIVE_COUNT) >= cap ($CAP). Deferring this fire."
  # Append a section to SPRINT_REPORT.md so the deferral is auditable.
  cat >> "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" <<DEFER

### Sprint deferred — at live-worktree cap

Live count $LIVE_COUNT >= cap $CAP at $(TZ="${TIMEZONE:-UTC}" date -Iseconds).
No fix agents dispatched this fire. \`execution.max_concurrent_worktrees\`
in \`.claude/zskills-config.json\` controls the cap (default 3). Cron will
retry on the next fire — by then prior worktrees should have landed (PR
merged + worktree cleaned), opening slots.
DEFER
  exit 0
elif [ "$SLOTS" -lt "$N_REQUESTED" ]; then
  # Some slots, but not enough for the full batch. Dispatch the first SLOTS;
  # queue the rest for the next fire. The queued issues stay open and the
  # next cron tick (or `/fix-issues next`) will re-prioritise them.
  echo "Live count $LIVE_COUNT, cap $CAP — $SLOTS slots available, dispatching $SLOTS of $N_REQUESTED."
  QUEUED=( "${TO_DISPATCH[@]:$SLOTS}" )
  TO_DISPATCH=( "${TO_DISPATCH[@]:0:$SLOTS}" )
  # Note the deferred subset in the sprint report. The exact issue list
  # comes from the orchestrator's batched-priority array.
  cat >> "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" <<QUEUED_SEC

### Sprint partially deferred — at live-worktree cap

Live count $LIVE_COUNT, cap $CAP. Dispatched $SLOTS of $N_REQUESTED agents
this fire; queued for next fire: ${QUEUED[*]}
QUEUED_SEC
fi
# Otherwise SLOTS >= N_REQUESTED — proceed with the full dispatch loop below.
# The per-message I/O contention cap (3) still applies inside the dispatch
# loop, so a batch of 5 still pages out as 3+2 even when SLOTS=5.
```

Notes:
- `TO_DISPATCH` is the array of issue numbers the orchestrator built in
  Phase 2's prioritisation. The cap-check truncates it in place; the
  dispatch loop below iterates `TO_DISPATCH` as usual.
- The grep regex `^branch refs/heads/fix[/-]issue-` matches BOTH the PR-mode
  pattern `fix/issue-NNN` and the cherry-pick/direct-mode pattern
  `fix-issue-NNN`. Bracket alternation `[/-]` keeps it a single grep.
- The cap can be raised by editing `execution.max_concurrent_worktrees` in
  `.claude/zskills-config.json`. Raise above 3 only on hosts with ample
  CPU/memory/disk headroom — past containers OOMed at 8 concurrent live.

**Agent timeout: 1 hour.** Note the dispatch time for each agent. If an
agent hasn't returned after 1 hour, declare it **failed**:
- Mark its issues as "Timed out" in `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`
- Issues stay open for the next sprint
- The worktree is a cleanup artifact — do NOT auto-land late results
- If the agent eventually returns, ignore it. Timed out = failed, period.

**Agent dispatch prompts MUST include for each issue:**

1. **The verbatim issue body** from Phase 1b (`gh issue view`). Do NOT
   paraphrase or summarize — include the full text the user wrote. Titles are
   often vague; the body is the spec. If the body is empty, say so explicitly.
2. **The research blurb from issue tracker files** (`$ZSKILLS_ISSUES_DIR/*ISSUES*.md`).
   These contain root cause analysis, affected files, suggested fixes, and
   effort estimates written when the issue was filed. Grep the tracker files
   for the issue number and include any matching section verbatim.

The agent should have everything it needs to understand the problem without
re-researching from scratch. Missing context = wrong fix.

**For issue bodies or plan blurbs longer than ~100 lines:** write the
verbatim text to a temp file (e.g., `/tmp/issue-NNN.md`) and tell the agent
to `Read` the file. This avoids the natural LLM tendency to compress long
text when inlining it in a prompt. Shorter content can be inlined directly.

**Declare pipeline ID** early in execution (before any git operation).
`$PIPELINE_ID` was constructed at the top of Phase 1 ("Sprint tracking
sentinel") as `fix-issues.$SPRINT_ID`:
```bash
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"
```

The echo associates the orchestrator session with this pipeline (read by hook
from transcript). Each worktree's `.zskills-tracked` file is written
atomically by `create-worktree.sh --pipeline-id` during worktree
materialisation (see "Worktree setup" below).

Each agent follows this fix workflow:

1. Read the issue body (included in prompt) and relevant code
2. Reproduce the bug (unit test or manual)
3. Implement the fix
4. Write regression tests (unit and/or E2E as appropriate)
5. Run `$FULL_TEST_CMD` (resolve via
   `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
   if you don't already have it in your environment) — all suites must pass.
   **CRITICAL — Bash tool timeout:** invoke with `timeout: 600000` (10
   min). The default 120000ms is shorter than the suite's actual runtime
   (~3-4 min in zskills). **Do NOT recover from a timeout by retrying
   with `run_in_background: true` + `Monitor` / `BashOutput` polling** —
   wake events for background processes do not reliably deliver to
   subagents, so the wait never returns and the dispatch hangs at "Tests
   are running. Let me wait for the monitor." Past failure: 6+ subagent
   crashes with exactly that phrase across 2026-04-29 and 2026-04-30
   sessions. Always foreground-Bash with explicit long timeout; capture
   to file via `> "$TEST_OUT/$TEST_OUTPUT_FILE" 2>&1` and read the file
   when the Bash call returns.
6. **Agent verification** via `/manual-testing` if UI files changed —
   use playwright-cli with real events, take screenshots as evidence.
   The pre-commit hook will BLOCK your commit if UI files are staged
   but `playwright-cli` wasn't used in the session. This is not optional.
7. **Classify User Verify** — if any UI/editor/styles files changed
   (check your project's UI directories), mark `User Verify: NEEDED`
   in the sprint report. The user must see UI changes before the issue
   can be closed. This is in ADDITION to your agent verification.
8. Commit in the worktree (one issue per commit, clean history)
9. **Rebase onto current main before final commit:**
   ```bash
   git fetch origin main && git rebase origin/main
   ```
   This ensures the commit contains only the agent's changes, not stale
   copies of files other agents already fixed on main. If rebase conflicts,
   abort (`git rebase --abort`) and proceed — Phase 6 cherry-pick
   verification will catch stale files via selective extraction.

The implementation agent does NOT commit. The verification agent runs the full
test suite and commits if verification passes. This ensures the hook's test
gate is satisfied. The approval gate is landing to main (Phase 6).

### Worktree setup (cherry-pick and direct modes)

For `LANDING_MODE == cherry-pick` (default) and `LANDING_MODE == direct`,
create the per-issue worktree via `create-worktree.sh` BEFORE dispatching
the fix agent. The default branch name is `fix-issue-NNN` (derived from
`--prefix fix-issue` + the issue slug); the worktree lives at
`${WORKTREE_ROOT:-/tmp}/<project-name>-fix-issue-NNN`. PR mode overrides
the branch name to `fix/issue-NNN` via `--branch-name` — see that
subsection below.

```bash
ISSUE_NUM=42
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Resume detection stays directory-based: an existing fix worktree means
# we're resuming the same issue across cron turns.
WORKTREE_PATH="/tmp/$(basename "$MAIN_ROOT")-fix-issue-${ISSUE_NUM}"
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing fix worktree at $WORKTREE_PATH"
else
  WORKTREE_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
    --prefix fix-issue \
    --purpose "fix-issues; issue=${ISSUE_NUM}" \
    --pipeline-id "$PIPELINE_ID" \
    "${ISSUE_NUM}")
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "create-worktree failed (rc=$RC) for /fix-issues cherry-pick/direct mode" >&2
    exit "$RC"
  fi
fi
# create-worktree.sh owns pre-flight prune+fetch+ff-merge, the underlying
# safe add, .zskills-tracked (from --pipeline-id), and .worktreepurpose
# writes. The orchestrator does NOT separately write the tracking marker
# — the worktree directory does not exist until create-worktree.sh
# materialises it, so any pre-dispatch write would fail.
```

For grouped interrelated issues (same root cause or same files from
Phase 2 grouping), pass the **lowest issue number** as the slug — all
grouped issues share that one worktree. Mirrors the PR-mode convention.

**Dispatching fix agents in cherry-pick/direct mode:** Dispatch agents
WITHOUT `isolation: "worktree"` — the worktree already exists. The agent
prompt must include `FIRST: cd $WORKTREE_PATH` as the mandatory first
action. Without this instruction, the agent starts in the main repo.

### PR mode (Phase 3)

When `LANDING_MODE == pr`, each issue gets its **own named branch and
worktree** (one PR per issue, unlike `/run-plan` PR mode where all phases
share one branch).

**Differences from `/run-plan` PR mode:**
- Branch prefix is hardcoded `fix/` (not config `branch_prefix`)
- Branch name uses the issue number, not a plan slug
- Worktree path uses `fix-issue-NNN`, not `pr-<plan-slug>`
- One worktree per issue (not one per plan)

**Branch naming:** `fix/issue-NNN` where `NNN` is the GitHub issue number.

**Worktree path:** `/tmp/<project-name>-fix-issue-NNN`

```bash
ISSUE_NUM=42
BRANCH_NAME="fix/issue-${ISSUE_NUM}"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"

MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# Resume detection stays directory-based (R2-M1): an existing fix worktree
# means we're resuming the same issue across cron turns.
if [ -d "$WORKTREE_PATH" ]; then
  echo "Resuming existing fix worktree at $WORKTREE_PATH"
else
  WORKTREE_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
    --prefix fix-issue \
    --branch-name "fix/issue-${ISSUE_NUM}" \
    --allow-resume \
    --purpose "fix-issues; issue=${ISSUE_NUM}" \
    --pipeline-id "$PIPELINE_ID" \
    "${ISSUE_NUM}")
  RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "create-worktree failed (rc=$RC) for /fix-issues PR mode" >&2
    exit "$RC"
  fi
fi
# create-worktree.sh owns pre-flight prune+fetch+ff-merge, the
# underlying safe add (with ZSKILLS_ALLOW_BRANCH_RESUME=1 set via
# --allow-resume), .zskills-tracked (from --pipeline-id), and
# .worktreepurpose writes.
```

**Dispatching fix agents in PR mode:** Dispatch agents WITHOUT
`isolation: "worktree"` — the worktree already exists. The agent prompt
must include `FIRST: cd $WORKTREE_PATH` as the mandatory first action.
Without this instruction, the agent starts in the main repo.

For grouped interrelated issues (same root cause or same files from
Phase 2 grouping), pick the LOWEST issue number as the branch identifier
(`fix/issue-NNN`) and include all grouped issues in that one worktree.
The `.landed` marker's `issue:` field records the primary issue; group
members are listed separately in the sprint report.

### Post-execute tracking

After Phase 3 (execute) is complete — all agents have returned:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.execute"
```

## Phase 4 — Review

### Pre-verification tracking

Before dispatching verification agents, create a delegation requirement
marker so the hook can enforce that verification actually runs. The
marker lives in fix-issues' own per-sprint subdir (same pattern as
run-plan's delegation lock in Phase 3 of the tracking plan):
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
printf 'skill: verify-changes\nparent: fix-issues\nmode: sprint\ndate: %s\n' \
  "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.verify-changes.$SPRINT_ID"
```

### Dispatch protocol

**Check your tool list.** If `Agent` (or `Task`) is in your tool list,
you are at top level — dispatch fresh verification subagents per the
protocol below. The implementation subagents (in their per-issue
worktrees) and the verification subagent are sibling subagents of you,
the top-level orchestrator. The verifier has no memory of what the
implementer did because they're separate contexts.

**If you do NOT have the `Agent` tool**, you are running as a subagent
yourself (Claude Code subagents have no Agent tool, by Anthropic's
design at https://code.claude.com/docs/en/sub-agents). Run `/verify-changes
worktree` inline in your current context, once per worktree. This is
single-context inline verification — flag in the report whether you
were fresh relative to the implementer or not. This fallback is mostly
defensive since /fix-issues typically runs at top level.

**Before dispatching any verification Agent:** check `agents.min_model` in
`.claude/zskills-config.json`. If set, use that model or higher (ordinal:
haiku=1 < sonnet=2 < opus=3). Never dispatch with a lower-ordinal model than
the configured minimum.

After each agent completes, **dispatch a fresh agent** to run `/verify-changes
worktree` in its worktree. Do NOT run verification yourself — you wrote
the dispatch prompts, so you have implementer bias. The verification agent
must be a fresh agent with no memory of the implementation.

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. After the dispatch returns, pipe `$VERIFIER_RESPONSE` through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`; on exit 1 STOP that issue's flow and surface to the user. Per Anthropic's documented design, the verifier cannot dispatch sub-subagents — for the per-issue case this is fine: each verifier handles one issue's worktree. If a verification reveals a fix is needed, surface to the user (or to `/run-plan` if dispatched by it); the orchestrator dispatches any fix agent.

**Layer 3 — verifier response validation.** Immediately after each verification dispatch returns:

```bash
printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
VALIDATE_EXIT=$?
```

On `VALIDATE_EXIT=1` — STOP that issue's flow. Do NOT mark the issue
verified, do NOT write `step.fix-issues.<sprint>.verify`, do NOT proceed
to landing for that issue. Emit:

```
STOP: verifier returned without meaningful results for issue #<N>.

$(cat /tmp/last-validate-stderr)

This is a verification FAIL. Surface to the user. Do not auto-retry —
re-dispatching with the same agent type hits the same wall. If the
verifier agent file is missing, run /update-zskills.
```

This delegates the full review workflow (diff review, test coverage audit,
test run, manual verification, fix & re-verify cycle) to a separate agent.

Report the review results to the user.

### Post-verify tracking

After Phase 4 (verify) is complete — all verification agents have returned:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.verify"
```

## Phase 5 — Write Sprint Report (BEFORE landing)

**APPEND** a new sprint section to `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` BEFORE Phase 6
(landing). The report is a prerequisite for landing — if it's not written,
Phase 6 does not execute.

**APPEND, do not overwrite.** Multiple sprints may run between `/fix-report`
reviews (e.g., cron every 2h, user checks once a day). Each sprint adds a
new `## Sprint — YYYY-MM-DD HH:MM [UNFINALIZED]` section. `/fix-report`
processes all UNFINALIZED sections when the user reviews.

If the file doesn't exist, create it with a `# Sprint Report` heading.

Past failure: an agent skipped Phase 5 for 8 consecutive sprints to "keep
the hourly cadence fast." `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` was stale for 8 sprints,
making `/fix-report` useless. Another failure: the file was overwritten
each sprint, losing results from earlier sprints that were never reviewed.

**Report format** — each sprint appends a section like this:

```markdown
## Sprint — YYYY-MM-DD HH:MM [UNFINALIZED]

**Mode:** auto | interactive | **Focus:** <focus> | default

### Fixed
| # | Title | Worktree | Commit | Tests | Agent Verify | User Verify |
|---|-------|----------|--------|-------|-------------|-------------|
| #123 | Solver crash | wt-123 | abc1234 | 2 unit | PASS (tests) | N/A |
| #456 | Button offset | wt-456 | def5678 | 1 E2E | PASS (screenshot) | NEEDED |

**Agent Verify:** Did the agent test it? PASS (with method) or SKIPPED.
The pre-commit hook blocks commits without test evidence.

**User Verify:** Does the user need to see this? Mechanically classified:
if any UI/editor/styles files changed → `NEEDED`. Otherwise → `N/A`.
`/fix-report` Step 2
presents all `NEEDED` items for user review before closing.

### Skipped — Too Vague (need repro steps or clearer spec)
| # | Title | What's Missing |
|---|-------|----------------|

### Skipped — Too Complex (need /run-plan)
| # | Title | Why |
|---|-------|-----|

### Skipped — Cherry-Pick Conflict (will retry next sprint)
| # | Title | Conflict Details |
|---|-------|-----------------|
| #789 | Parser error | cherry-pick conflict on commit abc1234 |

### Not Fixed (agent attempted but failed)
| # | Title | Reason |
|---|-------|--------|
```

The file starts with `# Sprint Report` (created once). Each sprint
appends a new `## Sprint` section. `/fix-report` marks sections
`[FINALIZED]` after review. **Use actual data** — real issue numbers,
commit hashes, worktree paths, and test counts.

### Commit sprint artifacts + dispatch `/land-pr` (closes #325)

Phase 1 wrote tracker rows (`$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` and any
`*_ISSUES.md` files) and Phase 5 above appended the new `## Sprint —`
section to `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`. Both writes landed in
the worktree because the Phase 1 preamble re-anchored `ZSKILLS_PATHS_ROOT`.
Now stage them, commit on the worktree's feature branch, and dispatch
`/land-pr` to open the sprint PR. Sprint-mode landing is interactive
(matches standalone `## Sync` convention) — no `auto` argument is appended
to `LAND_ARGS`; per-issue auto-merge gating remains the responsibility of
Phase 6 mode-specific dispatch.

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: filename basename suffixed onto $ZSKILLS_AUDIT_DIR (resolved via zskills-paths.sh); the basename token itself remains literal so the regex still flags the /SPRINT_REPORT.md tail -->
<!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
```bash
# Defensive cwd restore; WT_PATH set by the Phase 1 preamble.
[ -n "${WT_PATH:-}" ] && cd "$WT_PATH" 2>/dev/null || true
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
TOPLEVEL=$(git rev-parse --show-toplevel)
if [ "$TOPLEVEL" != "$MAIN_ROOT" ]; then
  # R3-1: re-anchor under the worktree so $ZSKILLS_AUDIT_DIR /
  # $ZSKILLS_ISSUES_DIR resolve to TOPLEVEL/.zskills/audit and
  # TOPLEVEL/<issues_dir>, not the main repo.
  export ZSKILLS_PATHS_ROOT="$TOPLEVEL"
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"

  ABS_FILE="$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md"
  # Portable realpath (DA-R2-1; R3-6: adapted from warn-config-drift.sh:181-203).
  SPRINT_REL=""
  if SPRINT_REL=$(realpath --relative-to="$TOPLEVEL" "$ABS_FILE" 2>/dev/null) \
       && [ -n "$SPRINT_REL" ]; then
    case "$SPRINT_REL" in /*) SPRINT_REL="" ;; esac
  fi
  if [ -z "$SPRINT_REL" ]; then
    ABS_FILE_CANON=$(cd "$(dirname "$ABS_FILE")" 2>/dev/null && pwd)/$(basename "$ABS_FILE")
    case "$ABS_FILE_CANON" in
      "$TOPLEVEL"/*) SPRINT_REL="${ABS_FILE_CANON#"$TOPLEVEL"/}" ;;
      *) echo "fix-issues: cannot normalize $ABS_FILE vs $TOPLEVEL" >&2; exit 1 ;;
    esac
  fi
  case "$SPRINT_REL" in
    /*|../*) echo "fix-issues: $ABS_FILE is outside worktree $TOPLEVEL" >&2; exit 1 ;;
  esac

  # Stage SPRINT_REPORT.md plus any modified tracker files
  # (`docs/issues/*ISSUES*.md` and `ISSUES_PLAN.md`) under
  # $ZSKILLS_ISSUES_DIR. Tracker files are tracked in git.
  git -C "$TOPLEVEL" add "$SPRINT_REL"
  if [ -n "${ZSKILLS_ISSUES_DIR:-}" ] && [ -d "$ZSKILLS_ISSUES_DIR" ]; then
    ISSUES_REL=$(realpath --relative-to="$TOPLEVEL" "$ZSKILLS_ISSUES_DIR" 2>/dev/null) || ISSUES_REL=""
    if [ -n "$ISSUES_REL" ]; then
      case "$ISSUES_REL" in /*|../*) ISSUES_REL="" ;; esac
    fi
    if [ -n "$ISSUES_REL" ]; then
      git -C "$TOPLEVEL" add -A "$ISSUES_REL" 2>/dev/null || true
    fi
  fi
  STAGED=$(git -C "$TOPLEVEL" diff --cached --name-only)
  # Skip-if-empty guard: a sprint with no Phase 1 row-writer additions
  # AND no Phase 5 sprint-section append leaves nothing staged — exit
  # cleanly without erroring.
  if [ -z "$STAGED" ]; then
    echo "fix-issues: nothing to commit (empty sprint artifacts); skipping commit + /land-pr" >&2
  else
    UNEXPECTED=""
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in
        "$SPRINT_REL") ;;
        *)
          if [ -n "${ISSUES_REL:-}" ]; then
            case "$f" in
              "$ISSUES_REL"/*) ;;
              *) UNEXPECTED="$UNEXPECTED $f" ;;
            esac
          else
            UNEXPECTED="$UNEXPECTED $f"
          fi
          ;;
      esac
    done <<EOF
$STAGED
EOF
    if [ -n "$UNEXPECTED" ]; then
      echo "fix-issues: unexpected staged files outside SPRINT_REPORT.md / $ISSUES_REL:$UNEXPECTED" >&2
      exit 1
    fi
    if [ -n "$COMMIT_CO_AUTHOR" ]; then
      git -C "$TOPLEVEL" commit --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" -m "docs(sprint): tracker rows + sprint report (sprint=$SPRINT_ID)"
    else
      git -C "$TOPLEVEL" commit -m "docs(sprint): tracker rows + sprint report (sprint=$SPRINT_ID)"
    fi
  fi
fi
```

<!-- allow-hardcoded: TZ=America/New_York reason: SPRINT_TS is a user-facing wall-clock stamp on the PR title/body; matches the established sprint-mode idiom for human-readable dates. Per-skill $TIMEZONE migration is scoped to plans/SKILL_FILE_DRIFT_FIX.md, not this issue -->
```bash
# Dispatch /land-pr to open the sprint PR. The tracking marker is written
# on main_root so /land-pr can satisfy it with a fulfilled.land-pr.<id>
# marker on successful merge — mirrors standalone `## Sync` mode's
# Step 5 sub-step 2 (and /run-plan PR mode).
SPRINT_TS="${SPRINT_TS:-$(TZ=America/New_York date +%Y%m%d-%H%M%S)}"
LAND_ID="fix-issues.sprint.${SPRINT_ID}"

MAIN_ROOT="${MAIN_ROOT:-$(cd "$(git rev-parse --git-common-dir)/.." && pwd)}"
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"

# Write the requires.land-pr marker on main_root BEFORE dispatch. The
# matching fulfilled.land-pr.<LAND_ID> is written by /land-pr ONLY on
# STATUS=merged (created/monitored do not fulfill — by design).
printf 'skill: land-pr\nrequired-by: fix-issues-sprint\ndate: %s\n' \
  "$(TZ=UTC date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${LAND_ID}"

# Build the PR body file.
RESULT_FILE=$(mktemp)
BODY_FILE=$(mktemp)
{
  printf '## Summary\n`/fix-issues %s` sprint %s — tracker rows + sprint report.\n\n' \
    "$N" "$SPRINT_ID"
  printf '## Test plan\n- [x] Sprint artifacts reviewed by user before merge.\n'
} > "$BODY_FILE"

PR_TITLE="sprint: $(TZ=America/New_York date +%F) (${SPRINT_ID})"
SPRINT_BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)

# /land-pr arg vector. Mirrors standalone sync's invocation MINUS any
# auto-merge flag — sprint-mode landing is interactive (matches sync
# convention); Phase 6 mode-specific dispatch handles per-issue
# auto-merge gating separately.
LAND_ARGS="--branch=$SPRINT_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sprint --worktree-path=$TOPLEVEL --tracking-id=$LAND_ID"

# Transcript echo for PIPELINE_ID propagation (tier-2 idiom, matches
# /do pr and standalone sync). Conformance test forbids the env-export
# form — echo is the canonical channel.
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

# Dispatch /land-pr via the Skill tool. The Skill tool loads /land-pr's
# prose into the current (orchestrator) context — its internal bash
# blocks run here. After /land-pr returns, $RESULT_FILE is populated.
#
# Skill: { skill: "land-pr", args: "$LAND_ARGS" }

if [ ! -f "$RESULT_FILE" ]; then
  echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
  exit 1
fi

# Parse result-file via canonical allow-list pattern. Unknown keys WARN
# but do not fail — forward-compatible with /land-pr schema additions.
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

echo "Sprint PR: ${LP[PR_URL]:-(none)} — STATUS=${LP[STATUS]:-unknown}"
```

### Post-report tracking

After Phase 5 (report) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.report"
```

## Phase 6 — Land

**Landing mode dispatch:**
- `LANDING_MODE == cherry-pick` — default path (below).
- `LANDING_MODE == pr` — see "PR mode landing" subsection. One PR per
  fixed issue, with `Fixes #NNN` linking.
- `LANDING_MODE == direct` — see "Direct mode landing" in
  [modes/direct.md](modes/direct.md). Per-issue rebase + FF-merge of
  `fix-issue-NNN` into main, then push. Requires
  `execution.main_protected: false` (enforced at Phase 1 argument parse).

**Auto-flag gating depends on landing mode.** Without `auto`:

- **`LANDING_MODE == pr`:** run [modes/pr.md](modes/pr.md) end-to-end
  except for the final auto-merge call. Rebase, push, PR creation,
  CI polling, and the fix cycle ALL run regardless of `auto` — they
  either surface review (PR creation) or are reversible (the fix cycle
  pushes commits back to the feature branch, which the user can revert).
  This matches the canonical pattern that `/commit pr`, `/do pr`, and
  `/run-plan` PR mode already follow: hand the user the cleanest possible
  PR to review. **Only `gh pr merge --auto --squash` is gated on `auto`**;
  without it, the PR sits at status `pr-ready` (or `pr-ci-failing` if
  fix-cycle was exhausted) awaiting human review and merge on GitHub.
- **`LANDING_MODE == cherry-pick`:** Sprint complete. Output:
  > Sprint complete. Report written to `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`.
  > Run `/fix-report` to review fixes, land to main, and close issues.

  Cherry-picks land via `/fix-report`'s interactive walk-through.
- **`LANDING_MODE == direct`:** Sprint complete (same handoff as
  cherry-pick). Direct mode FF-merges into main; never run that without
  explicit `auto` consent.

With `auto`, all three modes run their full landing procedure end-to-end
including the merge call (modes/pr.md auto-merge, modes/cherry-pick.md
cherry-pick to main, modes/direct.md FF-merge into main).

Landing is per-issue. Select the mode based on the landing-mode
detection from the Arguments section, then **read the corresponding
mode file in full and follow its procedure end-to-end** per-issue.
Do not proceed until you have read the file.

- **cherry-pick** (default) → [modes/cherry-pick.md](modes/cherry-pick.md)
- **direct** → [modes/direct.md](modes/direct.md)
- **PR mode** → [modes/pr.md](modes/pr.md)

All mode files assume Phase 5 (Sprint Report) has written the
persistent report and Phase 4 (Review) has populated the
before-landing summary.

### Post-land tracking

After Phase 6 (land) is complete:
```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.land"
```

After the sprint completes (whether all issues landed or the sprint ended),
clean up the sentinel:

```bash
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID"
```

Also remove `.zskills-tracked` from each worktree that was used.

## Failure Protocol

**Read [references/failure-protocol.md](references/failure-protocol.md)**
for crash handling, cron cleanup, worktree restoration, and sprint
failure reporting.

## Key Rules

- **Worktrees only** — all fixes happen in isolated worktrees, never in the
  main working tree.
- **The verification agent commits after passing tests** — the implementation
  agent does not commit. This satisfies the hook's test gate.
- **Never cherry-pick to main without permission** — unless `auto` flag is set,
  in which case the user has pre-approved autonomous landing.
- **In `auto` mode, skip conflicting cherry-picks** — abort the conflict,
  skip all commits from that worktree (grouped issues depend on each
  other), mark as "Skipped: conflict" in the report, and continue
  landing from other worktrees. The skipped issues self-heal next sprint.
- **Always write `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`** — it's the handoff to `/fix-report`.
- **Never close GH issues, update trackers, or remove worktrees** — that's
  `/fix-report`'s job.
- **One issue per commit** — clean git history in worktrees.
- **`$FULL_TEST_CMD` before every commit** (resolve via
  `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
  if you don't already have it in your environment) — not just `npm test`.
- **Never weaken tests** — fix the code, not the test. Do not loosen
  tolerances, skip assertions, or remove test cases.
- **Never defer the hard parts** — finish all phases of the plan. Do not
  stop after the easy part and call remaining work "future phases."
- **Protect untracked files** — before stash/cherry-pick/merge, inventory
  untracked files (`git status -s | grep '^??'`). Use `git stash -u` or
  save them first.
- **`every` implies `auto`** — scheduling only makes sense for autonomous
  runs. If `every` is present but `auto` is not, treat it as if `auto` was set.
- **Deduplicate crons** — always remove existing `/fix-issues` crons before
  creating a new one. Never let duplicate schedules accumulate.
- **Crons are session-scoped** — they expire when the session dies. Tell the
  user to re-run `/fix-issues ... every` to restart scheduling.
- **Kill the cron on failure** — if anything in the sprint fails unrecoverably,
  the FIRST action is `CronDelete`. A broken sprint + live cron = the next run
  stomps on the bad state. See the Failure Protocol for the full sequence.
- **Read every issue body before acting** — `gh issue view <N>` is mandatory
  in Phase 1b. Titles are often vague or misleading. The body is the spec.
  Never paraphrase — include verbatim issue text in agent dispatch prompts.
  Past failure: #387 title "reset button" was interpreted as "clear canvas"
  instead of "reset mappings to defaults" because only the title was read.
- **Ultrathink** — use careful, thorough reasoning. Read code, understand
  what changed and why, verify correctness.
