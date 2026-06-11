# /run-plan subcommands: status, now, next, stop

These subcommands are early-exit paths — each one completes and exits
before Phase 1 (Parse Plan) runs. Variables `$ARGUMENTS`, `$LANDING_MODE`,
`$PLAN_FILE`, and config helpers are resolved in the SKILL.md argument-
detection section before this file is read.

## Status (if `status` is present)

If `$ARGUMENTS` contains `status` (case-insensitive):

1. Compute the authoritative plan-file path — same logic as Phase 1's
   "Read authority" section, duplicated here because `status` exits
   before Phase 1 preflight:
   ```bash
   # Status-mode PLAN_FILE resolution — mirrors #603's $ARGUMENTS-token
   # recipe (first `.md` token in $ARGUMENTS is the plan-file path).
   # Status-mode exits before Phase 1 preflight, so PLAN_FILE must be
   # resolved here rather than inheriting from Phase 1's later resolver.
   if [ -z "${PLAN_FILE:-}" ]; then
     for tok in $ARGUMENTS; do
       case "$tok" in *.md) PLAN_FILE="$tok"; break ;; esac
     done
   fi
   if [ -z "${PLAN_FILE:-}" ]; then
     echo "ERROR: /run-plan status requires a plan-file path in \$ARGUMENTS" >&2
     exit 2
   fi
   PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
   # Pre-worktree bootstrap: anchor on $CLAUDE_PROJECT_DIR (orchestrator's
   # project root, set by the harness) — WORKTREE_PATH is not yet in scope.
   MAIN_ROOT="$CLAUDE_PROJECT_DIR"
   PROJECT_NAME=$(basename "$MAIN_ROOT")
   PR_WORKTREE_PATH="/tmp/${PROJECT_NAME}-pr-${PLAN_SLUG}"
   if [ "$LANDING_MODE" = "pr" ] && [ -d "$PR_WORKTREE_PATH" ]; then
     PLAN_FILE_FOR_READ="$PR_WORKTREE_PATH/$PLAN_FILE"
   else
     PLAN_FILE_FOR_READ="$MAIN_ROOT/$PLAN_FILE"
   fi
   ```
   Read the plan from `$PLAN_FILE_FOR_READ` so PR-mode in-flight tracker
   updates (committed on the feature branch) surface correctly instead
   of main's stale copy.
2. Also read any companion progress document if referenced (same rule).
3. Parse all phases and their status (same parsing logic as Phase 1
   steps 2-3: "Extract phases and status" and "Determine target phase."
   Do NOT run preflight checks — `status` is read-only)
4. Present a progress table:

   ```
   Plan: plans/FEATURE_PLAN.md

   | Phase | Status |
   |-------|--------|
   | 4a — Electrical | Done (abc1234) |
   | 4b — Mechanical | Done (def5678) |
   | 4c — Smooth Nonlinear | Next ← |
   | 4d — Solver Fixes | Blocked (needs 4c) |
   | 4e — UI Polish | Blocked (needs 4d) |

   Next phase: 4c — Smooth Nonlinear Components
   Dependencies: 4a ✓, 4b ✓
   ```

5. If a cron is active, also show the schedule:
   > Scheduled: every 4h (~8:15 PM ET next, cron XXXX)

6. **Exit.** Read-only — no agents dispatched, no work done.

## Now (standalone — no plan-file provided)

If `$ARGUMENTS` is just `now` (no plan-file, no phase, no every):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /run-plan`
3. If found: extract the cron's prompt to get the plan-file, auto, and
   schedule. **Run the phase immediately** — proceed to Phase 1. Do NOT
   ask for confirmation — `now` IS the confirmation. The cron stays active.
4. If none found: report `No active /run-plan cron to trigger. Use
   /run-plan <plan-file> to run manually.` and **exit.**

## Next (if `next` is present)

If `$ARGUMENTS` contains `next` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Find any whose prompt starts with `Run /run-plan`
3. Report:
   - If found: parse the cron expression and compute the next fire time.
     Use `date +%Z` for the timezone. Show both relative and absolute:
     > Next run-plan phase in ~2h 15m (~8:30 PM ET, cron XXXX).
     > Prompt: Run /run-plan plans/FEATURE_PLAN.md auto every 4h
   - If none found: `No active /run-plan cron in this session.`
4. **Exit.** Do not proceed to any phase.

## Stop (if `stop` is present)

If `$ARGUMENTS` contains `stop` (case-insensitive):

1. Use `CronList` to list all cron jobs
2. Delete ALL whose prompt starts with `Run /run-plan` using `CronDelete`
3. Clean up any per-phase defer counters and recovery sentinels for this
   plan (#110). MAIN_ROOT and TRACKING_ID are not yet in scope here, so
   compute them inline:
   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')
   # `stop` is invoked from main session before any worktree exists — anchor
   # on $CLAUDE_PROJECT_DIR. Counters in PR-mode runs that wrote inside the
   # worktree get cleaned up by the worktree's own .zskills/landed-marker flow.
   MAIN_ROOT="$CLAUDE_PROJECT_DIR"
   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"
   PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/in-progress-defers."*
   rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/cron-recovery-needed."*
   ```
3.5. **Release all run-plan plan AND issue claims (W2a.4 site 1 + W3.4;
   Option A walk).** /run-plan stop is a session-wide halt by design
   (step 2 above already deletes ALL `Run /run-plan` crons, not just this
   plan's). Iterate `.zskills/claims/plan-*/` and call `claim-plan.sh
   release <slug> --require-pipeline run-plan.<slug>` for every claim whose
   `pipeline_id` starts with `run-plan.`; THEN iterate
   `.zskills/claims/issue-*/` and call `claim-issue.sh release <N>
   --require-pipeline run-plan.<slug>` for every issue claim whose
   `pipeline_id` starts with `run-plan.` (the #803 execution-window
   claims run-plan now holds). Mismatched pipelines are skipped (exit 12)
   — those claims belong to other in-flight runs (or to /fix-issues, which
   owns its own `issue-*/` claims) and must not be clobbered.
   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   CLAIMS_ROOT="$MAIN_ROOT/.zskills/claims"
   RELEASED=0
   SKIPPED=0
   if [ -d "$CLAIMS_ROOT" ]; then
     for d in "$CLAIMS_ROOT"/plan-*; do
       [ -d "$d" ] || continue
       slug=$(basename "$d" | sed 's/^plan-//')
       [ -n "$slug" ] || continue
       claim_file="$d/claim.json"
       if [ ! -f "$claim_file" ]; then
         continue
       fi
       claim_pid=$("${ZSKILLS_PYTHON:-python3}" -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('pipeline_id', ''))
except Exception:
    pass
" "$claim_file" 2>/dev/null)
       # Only touch run-plan-owned claims; never clobber a sibling
       # pipeline's claim (e.g., /fix-issues — but those use issue-*/
       # not plan-*/, so this guard is belt-and-braces).
       case "$claim_pid" in
         run-plan.*) ;;
         *) continue ;;
       esac
       set +e
       bash "$ZSKILLS_SKILLS_ROOT/run-plan/scripts/claim-plan.sh" \
         release "$slug" --require-pipeline "$claim_pid"
       rc=$?
       set -e
       case "$rc" in
         0) RELEASED=$((RELEASED + 1)) ;;
         12) SKIPPED=$((SKIPPED + 1)) ;;  # mismatched pipeline (multi-session)
         *) SKIPPED=$((SKIPPED + 1)) ;;
       esac
     done
     # ISSUE-CLAIM SWEEP (W3.4 / M2/M3): run-plan now ALSO owns issue-<N>
     # claims (the #803 execution-window protection). The plan-* loop above
     # is structurally blind to issue-*/ dirs, so this PARALLEL loop releases
     # every issue-<N> whose pipeline_id starts with `run-plan.` — mirroring
     # the plan-* guard, mismatch-skip (exit 12), and tally. /fix-issues-owned
     # issue claims (pipeline_id `fix-issues.*`) are skipped, never clobbered.
     for d in "$CLAIMS_ROOT"/issue-*; do
       [ -d "$d" ] || continue
       n=$(basename "$d" | sed 's/^issue-//')
       [ -n "$n" ] || continue
       claim_file="$d/claim.json"
       if [ ! -f "$claim_file" ]; then
         continue
       fi
       claim_pid=$("${ZSKILLS_PYTHON:-python3}" -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get('pipeline_id', ''))
except Exception:
    pass
" "$claim_file" 2>/dev/null)
       # Only touch run-plan-owned issue claims; never clobber /fix-issues'
       # (or any other pipeline's) issue claim.
       case "$claim_pid" in
         run-plan.*) ;;
         *) continue ;;
       esac
       set +e
       bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" \
         release "$n" --require-pipeline "$claim_pid"
       rc=$?
       set -e
       case "$rc" in
         0) RELEASED=$((RELEASED + 1)) ;;
         12) SKIPPED=$((SKIPPED + 1)) ;;  # mismatched pipeline (multi-session)
         *) SKIPPED=$((SKIPPED + 1)) ;;
       esac
     done
   fi
   echo "Stop released $RELEASED claim(s); skipped $SKIPPED claim(s) (pipeline mismatch)." >&2
   ```
4. Report what was cancelled:
   - If one cron found: `Run-plan cron stopped (was job ID XXXX, every INTERVAL).`
   - If multiple found: `Stopped N run-plan crons (IDs: XXXX, YYYY).`
   - If none found: `No active /run-plan cron found.`
5. **Exit.** Do not proceed to any phase. The `stop` command does nothing else.
