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
# Sync mode TRACKING_ID — synthesized from timestamp since /fix-issues sync
# doesn't take a plan-file arg. Mirrors sprint mode's SPRINT_ID shape (later
# in this skill) with a `sync-` prefix so the namespace is unambiguous and
# downstream pipeline IDs (`fix-issues.${TRACKING_ID}`) are non-empty.
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
TRACKING_ID="${TRACKING_ID:-sync-$(TZ="${TIMEZONE:-UTC}" date +%Y%m%d-%H%M%S)}"
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
  on Main" sections of `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`

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

2. **Update `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`** — if the issue appears in an "Already
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

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: filename basename suffixed onto $ZSKILLS_REPORTS_DIR (resolved via zskills-paths.sh; issue #217); the basename token itself remains literal so the regex still flags the /SPRINT_REPORT.md tail -->
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

     ABS_FILE="$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md"
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
         # Fail loud: if git add fails (permissions, repo corruption, race
         # against another writer), the tracker would desync from the
         # working tree and sync would silently proceed — abort instead.
         if ! git -C "$TOPLEVEL" add -A "$ISSUES_REL"; then
           echo "fix-issues: git add -A $ISSUES_REL failed under $TOPLEVEL — aborting sync." >&2
           exit 1
         fi
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

   ```bash
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   # SYNC_TS: stable per sync invocation. SYNC_ID propagates to /land-pr.
   SYNC_TS="${SYNC_TS:-$(TZ="${TIMEZONE:-UTC}" date +%Y%m%d-%H%M%S)}"
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
       "$(TZ="${TIMEZONE:-UTC}" date +%F)"
     printf '## Test plan\n- [x] Sync-only diff: agent-facing tracker markdown; auto-merge.\n'
   } > "$BODY_FILE"

   PR_TITLE="sync: $(TZ="${TIMEZONE:-UTC}" date +%F)"
   SYNC_BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)

   # /land-pr arg vector. Always includes --auto: this dispatch ships
   # sync-driven tracker updates ONLY (research blurbs, ISSUES_PLAN row
   # adds, SPRINT_REPORT section append from sync). That content is
   # agent-facing markdown the agent reads back, not user-facing artifacts
   # warranting human review. The SUBSEQUENT "close approved issues on
   # GitHub" sub-step (Step 5 sub-step 3 below) is what remains
   # interactive — that requires human approval for the irreversible
   # `gh issue close` calls. The CI-monitor-suppression flag remains
   # omitted (CI monitoring is desired; the orchestrator awaits resting
   # state).
   LAND_ARGS="--branch=$SYNC_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sync --worktree-path=$TOPLEVEL --tracking-id=$SYNC_ID --auto"

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

