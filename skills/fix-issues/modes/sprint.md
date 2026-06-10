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
   immediately via their own `now` flag.

   **Assemble the prompt from `$AUTO_FLAG` state, not from literal
   `$ARGUMENTS` substrings.** Cron-fired `every`-mode runs MUST advance
   without human interaction, so include `auto` unconditionally for new
   `every` crons (auto = autonomous = skip approval gates + auto-merge):
   ```bash
   CRON_TOKENS=""
   # `auto` is mandatory for `every`-mode crons (selection / approval
   # gates must be skipped non-interactively). Default-on regardless of
   # $AUTO_FLAG.
   CRON_TOKENS="$CRON_TOKENS auto"
   # Propagate `dashboard` source-of-truth (issue #362) — without this, cron
   # fire #2+ loses the dashboard-Ready source and falls back to the
   # model-layer priority rubric.
   [ "$DASHBOARD_MODE" = "1" ] && CRON_TOKENS="$CRON_TOKENS dashboard"
   # Propagate explicit landing mode so subsequent cron fires reproduce the
   # user's pr/direct choice (config default is re-resolved per-fire when
   # the token is absent, matching current behavior).
   case "$LANDING_MODE" in
     pr) CRON_TOKENS="$CRON_TOKENS pr" ;;
     direct) CRON_TOKENS="$CRON_TOKENS direct" ;;
   esac
   CRON_PROMPT="Run /fix-issues $N${FOCUS:+ $FOCUS}$CRON_TOKENS every $SCHEDULE now"
   ```
   Default new-cron shape:
   ```
   Run /fix-issues <N> [focus] auto [dashboard] [pr|direct] every <schedule> now
   ```

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the reconstructed command from step 3

5. **Confirm** — tell the user, including the estimated wall-clock time of
   the next run. Compute from the cron expression. **Always show times in the
   configured timezone** — use `TZ="${TIMEZONE:-UTC}" date` for conversion,
   not the system timezone (which may differ). Example:

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
(a sprint with N and no `every` runs immediately — no scheduling needed).

## Phase 1 — Preflight & Sync

**IMPORTANT: Complete ALL steps (1-6 + Phase 1b) before Phase 2.** Do NOT
skip tracker updates or research to "save time." Dispatching agents without
research blurbs causes misinterpretation — agents guess from titles and
implement the wrong fix. This has happened repeatedly.

### Sprint identity

When mode is sprint (N provided), construct the per-sprint unique
`$SPRINT_ID` and `$PIPELINE_ID` FIRST — BEFORE the worktree gate
below and before any tracking write — so both the gate's
`--pipeline-id` arg and the downstream sentinel write agree on the
same id:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking"

# Per-sprint unique ID (per Phase 1 design doc OQ3). Prevents concurrent
# fix-issues sessions from colliding on the literal "sprint" suffix. The
# ISSUE_TITLE slug is a human-readable tag; the UTC timestamp guarantees
# uniqueness across concurrent sprints on the same host.
ISSUE_TITLE_SLUG=$(printf '%s' "${ISSUE_TITLE:-sprint}" | tr -cd 'a-z0-9' | head -c 8)
[ -z "$ISSUE_TITLE_SLUG" ] && ISSUE_TITLE_SLUG="sprint"
SPRINT_ID="sprint-$(date -u +%Y%m%d-%H%M%S)-$ISSUE_TITLE_SLUG"
PIPELINE_ID="fix-issues.$SPRINT_ID"
PIPELINE_ID=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
# Recover SPRINT_ID after sanitization (strip the "fix-issues." prefix).
SPRINT_ID="${PIPELINE_ID#fix-issues.}"
```

### Shared in-flight guard (issue #877)

**Cron pickup-fires can land while a previous sprint is still running**
(CronCreate's "fires only while idle" is turn-level idle, not task-level).
The shared `check-inflight-batch.sh` helper detects "my session already
has an in-flight fix-issues sprint" via session-scoped sentinels and
exits clean when so, leaving the in-flight run to finish on its own
turns. The check runs ONLY on sprint mode entry — subcommand routing
(`stop` / `next` / `sync` / `plan` / `add` / `remove` / `reconsider`)
in `SKILL.md` peels off before this file is loaded, so the carve-out
is structural. The two robustness traps (session-scoping + staleness
escape with `ZSKILLS_INFLIGHT_MAX_AGE_SECONDS` default 2h) live in the
helper; this fence is just the call site.

```bash
INFLIGHT_HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/check-inflight-batch.sh"
if [ -x "$INFLIGHT_HELPER" ]; then
  if bash "$INFLIGHT_HELPER" check fix-issues > /tmp/.fix-issues-inflight.$$ 2>/dev/null; then
    INFLIGHT_LINE=$(cat /tmp/.fix-issues-inflight.$$)
    rm -f /tmp/.fix-issues-inflight.$$
    INFLIGHT_PIPELINE=$(printf '%s' "$INFLIGHT_LINE" | awk -F'\t' '{print $2}')
    echo "fix-issues sprint ${INFLIGHT_PIPELINE:-(unknown)} in flight; skipping redundant cron pickup" >&2
    exit 0
  fi
  rm -f /tmp/.fix-issues-inflight.$$
fi
```

### Live worktree count check (defer-all gate)

**Run this BEFORE the sprint worktree gate below.** If the host is already
at the live-worktree cap, defer the whole fire here — exit cleanly with no
worktree created, no sentinel marker, no Phase 1 work. Co-located bugs from
PR #320 (predicate over-counted because it didn't skip already-landed
worktrees) and PR #329 (the cap-check used to run AFTER the sprint
worktree gate, so a defer-all that appended to `SPRINT_REPORT.md` stranded
the write in a worktree that never shipped — sprint-level `/land-pr` is in
Phase 6, past the `exit 0`). Fix: move the gate up here and skip
`.landed status: landed` worktrees from the count. The partial-dispatch
arm (when 0 < SLOTS < N_REQUESTED) moves to its own spot in Phase 3 —
it needs `TO_DISPATCH` which Phase 2 builds.

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: the SPRINT_REPORT.md basename appears only inside a comment explaining WHY the defer-all gate does NOT write to it (strand bug from #329); no actual `cat >> SPRINT_REPORT.md` heredoc lives in this fence — see tests/test-fix-issues-sprint-worktree-gate.sh assertion 8 -->
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# $ZSKILLS_MAX_CONCURRENT_WORKTREES is now set (defaults to 3 when the
# execution.max_concurrent_worktrees field is absent or malformed).

# Count live fix/issue-* worktrees across the repo, SKIPPING any whose
# `.landed` marker says `status: landed`. Done-but-uncleaned worktrees
# (every PR that ever merged through /fix-issues whose dir wasn't swept
# by /cleanup-merged yet) used to trip the cap; the awk/while shape
# below filters them out. Both PR-mode (`fix/issue-NNN`) and
# cherry-pick/direct mode (`fix-issue-NNN`) branches count via the
# bracket alternation `fix[/-]issue-`. Each worktree contributes exactly
# one `branch refs/heads/...` line in the porcelain output, preceded by
# a `worktree <path>` line — awk pairs them.
LIVE_COUNT=$(
  git worktree list --porcelain \
    | awk '/^worktree /{wt=$2} /^branch refs\/heads\/fix[/-]issue-/{print wt}' \
    | while read -r wt; do
        if [ -f "$wt/.landed" ] && grep -q '^status: landed' "$wt/.landed"; then
          continue
        fi
        echo X
      done \
    | wc -l \
    | tr -d ' '
)

CAP="$ZSKILLS_MAX_CONCURRENT_WORKTREES"
if [ "$LIVE_COUNT" -ge "$CAP" ]; then
  # All slots already taken — defer the entire fire BEFORE creating a
  # worktree. No `cat >> SPRINT_REPORT.md` here: the audit-write would
  # land in a worktree that never ships (sprint-level /land-pr is in
  # Phase 6, past this exit). One stderr line is the whole audit trail
  # — defer events are transient; the audit value is in real-dispatch
  # sprints.
  echo "fix-issues: live worktree count ($LIVE_COUNT) >= cap ($CAP); deferring sprint $PIPELINE_ID. Cron will retry on the next fire." >&2
  exit 0
fi
```

### Sprint worktree gate

**All sprint-mode work happens in a pre-created worktree.** Before
preflight checks, tracker fetches, Phase 3 dispatches, or the Phase 5
SPRINT_REPORT.md write, front-run the shared `ensure-worktree.sh` gate.
Phases 1–5 then run inside the worktree, so Phase 5's SPRINT_REPORT.md
append naturally lands on the sprint feature branch (not main). Closes
the same hole PR #252 closed for sync mode — sprint mode was missed in
that rollout (issue #325). Per-issue worktrees dispatched in Phase 3
remain independent of the sprint-level worktree; only the
SPRINT_REPORT.md append rides this gate. When `execution.main_protected`
is `false` (or unset), the helper no-ops and the sprint runs on main
as before.

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
TOPLEVEL=$(git rev-parse --show-toplevel)
HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/ensure-worktree.sh"
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
  echo "ensure-worktree failed (rc=$RC) for /fix-issues sprint" >&2
  exit "$RC"
fi
if [ -n "$WT_PATH" ]; then
  cd "$WT_PATH" || { echo "fix-issues: cd $WT_PATH failed" >&2; exit 1; }
  export ZSKILLS_PATHS_ROOT="$WT_PATH"  # R3-1 — re-anchor downstream path resolution
fi
```

### Sprint tracking sentinel

Now that `$SPRINT_ID` and `$PIPELINE_ID` are set and the worktree gate
has run, create the pipeline sentinel. The sentinel lives on
`$MAIN_ROOT` (NOT inside the sprint worktree) — tracking markers are
always read from `$MAIN_ROOT/.zskills/tracking/` so cross-worktree
sibling-check (the requires.*/fulfilled.* protocol) works regardless of
which worktree any sub-dispatch runs in:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"

if [ ! -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID" ]; then
  printf 'skill: fix-issues\nmode: sprint\ncount: %s\nfocus: %s\nstartedAt: %s\n' \
    "$N" "${FOCUS:-default}" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
    > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID"
fi

# Issue #877 — write the shared in-flight sentinel so subsequent cron
# pickup-fires in this session detect this sprint as live and skip.
# Cleared at sprint completion ("Post-land tracking" at the end of this file).
INFLIGHT_HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/check-inflight-batch.sh"
if [ -x "$INFLIGHT_HELPER" ]; then
  bash "$INFLIGHT_HELPER" write fix-issues --pipeline-id "$PIPELINE_ID" || \
    echo "fix-issues: WARN — could not write in-flight sentinel (continuing)" >&2
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
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
   else
     source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   fi
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
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
mkdir -p "$ZSKILLS_ISSUES_DIR"
EXISTING_TRACKERS=$(ls "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null | head -1)
if [ -z "$EXISTING_TRACKERS" ]; then
  if [ "$OPEN_COUNT" -eq 0 ]; then
    echo "Sync complete. 0 open issues, no trackers needed."
    exit 0
  fi
  TODAY=$(TZ="${TIMEZONE:-UTC}" date +%Y-%m-%d)
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
   # Resolve $PYTHON (Windows MS-Store-stub guard, #1083).
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   [ -n "$PYTHON" ] || { echo "ERROR: zskills requires Python 3 — install it or set ZSKILLS_PYTHON" >&2; exit 1; }
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
     ISSUE_META=$(printf '%s' "$GH_OUT" | "$PYTHON" -c '
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
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
   else
     source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   fi
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
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
   else
     source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   fi
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
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
   else
     source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
   fi
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
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
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
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  fi
  [ -n "$PYTHON" ] || { echo "ERROR: zskills requires Python 3 — install it or set ZSKILLS_PYTHON" >&2; exit 1; }
  MAIN_ROOT="${MAIN_ROOT:-$(cd "$(git rev-parse --git-common-dir)/.." && pwd)}"
  MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"

  # Helper: ship-or-cleanup. Called from each of the two dashboard-empty
  # exits below. If $WT_PATH is set and the worktree has uncommitted
  # changes from Phase 1a sync, stage + commit + dispatch /land-pr --auto
  # (sync-only content, same rationale as the no-actionable ship branch
  # at `### If no actionable issues found`). If clean, remove the empty
  # worktree. Inlined rather than function-shared with the no-actionable
  # site because those live in separate bash fences — bash functions do
  # not span skill fences.
  ship_sync_only_or_cleanup() {
    [ -z "${WT_PATH:-}" ] && return 0
    cd "$WT_PATH" || { echo "fix-issues: cd $WT_PATH failed (dashboard-empty)" >&2; return 1; }
    local TOPLEVEL
    TOPLEVEL=$(git rev-parse --show-toplevel)
    if [ -n "$(git -C "$TOPLEVEL" status --porcelain)" ]; then
      echo "fix-issues dashboard-empty: Phase 1a sync wrote updates; shipping sync-only PR" >&2
      git -C "$TOPLEVEL" add -A
      local STAGED
      STAGED=$(git -C "$TOPLEVEL" diff --cached --name-only)
      if [ -z "$STAGED" ]; then
        echo "fix-issues dashboard-empty: status reported dirty but nothing staged — removing worktree" >&2
        cd "$MAIN_ROOT" && git worktree remove --force "$WT_PATH"
        return 0
      fi
      if [ -n "${COMMIT_CO_AUTHOR:-}" ]; then
        git -C "$TOPLEVEL" commit --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" \
          -m "docs(sync): tracker refresh from /fix-issues fire $SPRINT_ID"
      else
        git -C "$TOPLEVEL" commit -m "docs(sync): tracker refresh from /fix-issues fire $SPRINT_ID"
      fi

      local SPRINT_LAND_ID="fix-issues.dashboard-sync.${SPRINT_ID}"
      [ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
      mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
      printf 'skill: land-pr\nrequired-by: fix-issues-dashboard-empty\ndate: %s\n' \
        "$(TZ=UTC date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${SPRINT_LAND_ID}"

      local RESULT_FILE BODY_FILE PR_TITLE SPRINT_BRANCH LAND_ARGS
      RESULT_FILE=$(mktemp)
      BODY_FILE=$(mktemp)
      {
        printf '## Summary\n`/fix-issues` dashboard fire %s: Ready queue empty; Phase 1a sync produced tracker updates that ship here.\n\n' "$SPRINT_ID"
        printf '## Test plan\n- [x] Sync-only diff; no per-issue work executed this fire.\n'
      } > "$BODY_FILE"

      PR_TITLE="sync: tracker refresh from /fix-issues dashboard fire $SPRINT_ID"
      SPRINT_BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)
      # This dispatch fires when the dashboard Ready queue is empty but
      # Phase 1a sync wrote tracker updates. The PR commits only sync-driven
      # content (`git add -A` against the worktree after sync ran), so it
      # ALWAYS auto-merges regardless of user's `auto` arg — same rationale
      # as standalone sync's Phase 5 dispatch and the no-actionable ship
      # branch later in this skill.
      LAND_ARGS="--branch=$SPRINT_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-dashboard-empty --worktree-path=$TOPLEVEL --tracking-id=$SPRINT_LAND_ID --auto"

      echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

      # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

      if [ ! -f "$RESULT_FILE" ]; then
        echo "ERROR: /land-pr (dashboard-empty sync-land) produced no result file at $RESULT_FILE" >&2
      else
        local -A LP_DASH
        local KEY VALUE
        while IFS='=' read -r KEY VALUE; do
          case "$KEY" in
            STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
            MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
            CONFLICT_FILES_LIST|CALL_ERROR_FILE)
              LP_DASH["$KEY"]="$VALUE" ;;
            "") ;;
            *) printf 'WARN: /land-pr (dashboard-empty sync-land) result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
          esac
        done < "$RESULT_FILE"
        case "${LP_DASH[STATUS]:-}" in
          merged)
            printf 'skill: land-pr\nid: %s\npr: %s\nbranch: %s\ndate: %s\n' \
              "$SPRINT_LAND_ID" "${LP_DASH[PR_URL]:-}" "$SPRINT_BRANCH" \
              "$(TZ=UTC date -Iseconds)" \
              > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$SPRINT_LAND_ID"
            ;;
          *)
            echo "fix-issues dashboard-empty sync-land: /land-pr STATUS=${LP_DASH[STATUS]:-unknown} — sync PR left open" >&2
            ;;
        esac
      fi
    else
      echo "fix-issues dashboard-empty: no sync updates; cleaning up empty worktree" >&2
      cd "$MAIN_ROOT" && git worktree remove --force "$WT_PATH"
    fi
  }

  # Reuse the cached OPEN_NUMS array fetched in Phase 1's sync step (gh
  # issue list --state open ...). If for some reason it is not set in
  # this scope, refetch it the same way Phase 1 does.
  if [ -z "${OPEN_NUMS+x}" ]; then
    GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1) \
      || { echo "ERROR: 'gh issue list' failed:" >&2; echo "$GH_OUT" >&2; exit 1; }
    mapfile -t OPEN_NUMS < <(printf '%s' "$GH_OUT" | "$PYTHON" -c '
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
    ship_sync_only_or_cleanup
    exit 0
  fi

  # Read issues.ready in drag order; intersect with live open issues.
  # Do NOT cap to N here — return ALL intersected-open candidates in drag
  # order. The orchestrator triage loop caps to N actionable picks AFTER
  # triage (so a top-of-queue plan-scale/vague item doesn't block the
  # whole queue). Python json — never bash regex on a JSON array.
  DASHBOARD_PICKS=$(OPEN_NUMS_JOINED="$(printf '%s,' "${OPEN_NUMS[@]}")" \
    "$PYTHON" -c '
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
print(" ".join(str(p) for p in picks))
' "$MONITOR_STATE")

  if [ -z "$DASHBOARD_PICKS" ]; then
    echo "Dashboard Ready is empty — nothing to do"
    ship_sync_only_or_cleanup
    exit 0
  fi

  # Hand the picks to the rest of Phase 2 via a CANDIDATE_ISSUES array.
  # Downstream triage subsection + Phase 3 dispatch consume this array
  # the same way they would consume the rubric's output. Skip the
  # rubric/focus/default-ranking text below — the picks ARE the order.
  read -r -a CANDIDATE_ISSUES <<<"$DASHBOARD_PICKS"
  echo "Dashboard candidates (drag order, uncapped — triage caps to N=$N actionable): ${CANDIDATE_ISSUES[*]}"
fi
```

#### Source-filter un-researched candidates (issue #408)

Phase 1's research dispatch (step 5 + step 6) is prose-only "should run"
and skipped repeatedly across ~50 sprints. When it skips, candidates
arrive at Phase 2 with no tracker blurb, the orchestrator triages from
bare titles + body previews, and the just-landed #402 independent-sizing
discipline does not bite (it requires a tracker blurb to read against).
The fix is structural: at Phase 2 entry, source-filter candidates by
whether they have a tracker blurb with an `**Action now:**` line.
`Action now:` is the Phase-2-consumed tier field — *not* `**Verdict:**`,
which legitimately reads `LIKELY FIXED` / `UNCLEAR` for fully-researched
candidates and `NOT YET RESEARCHED` for stub rows (presence-checking
Verdict would no-op the gate).

In `auto` mode, dispatch research agents in parallel for the missing
ones (reusing Phase 1 step-6's parallel-up-to-3 pattern) and re-filter
once they commit blurbs. In interactive mode, abort with a diagnostic
pointing at `/fix-issues sync`.

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
fi
eval "$(ZSKILLS_ISSUES_DIR="$ZSKILLS_ISSUES_DIR" \
  bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/filter-unresearched-candidates.sh" \
  "${CANDIDATE_ISSUES[@]}")"
# eval populated two bash vars: RESEARCHED (space-sep nums) and MISSING.
read -r -a RESEARCHED_ARR <<<"${RESEARCHED:-}"
read -r -a MISSING_ARR <<<"${MISSING:-}"

if [ ${#MISSING_ARR[@]} -gt 0 ]; then
  if [ "$AUTO_FLAG" = "1" ]; then
    # AUTO MODE — dispatch research agents in parallel for MISSING_ARR,
    # reusing Phase 1 step-6's pattern (up to 3 at a time). Each agent
    # reads `gh issue view <N>`, greps the codebase for affected files,
    # writes the row content to `.zskills/research-staging/$PIPELINE_ID/issue-${N}.md` (scratchpad)
    # and returns without touching $ZSKILLS_ISSUES_DIR/*ISSUES*.md or committing. The orchestrator
    # promotes scratchpads to committed tracker rows in Phase 3 per the acquire-outcome decision
    # tree (see "Per-issue dispatch loop (B-proper)" below).
    #
    # Orchestrator action: for each N in MISSING_ARR, dispatch a
    # general-purpose research agent (max 3 concurrent). After all
    # return, rebuild RESEARCHED_SET as the union of filter-RESEARCHED
    # (prior-fire committed rows) and scratchpads-just-created (this fire).
    echo "fix-issues Phase 2: ${#MISSING_ARR[@]} candidate(s) lack research blurbs in auto mode: ${MISSING_ARR[*]}" >&2
    echo "Dispatching research agents in parallel (up to 3 at a time). Blocking until research scratchpads ready." >&2
    # (Agent dispatches happen at the orchestrator level; this fence
    # marks the intent and re-derives state after.)
    # After research dispatches return, RESEARCHED_SET is the union of:
    #   (a) candidates with committed tracker rows from prior fires (filter-RESEARCHED)
    #   (b) candidates whose scratchpads this pipeline just created
    eval "$(ZSKILLS_ISSUES_DIR="$ZSKILLS_ISSUES_DIR" \
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/filter-unresearched-candidates.sh" \
      "${CANDIDATE_ISSUES[@]}")"
    read -r -a RESEARCHED_ARR <<<"${RESEARCHED:-}"
    read -r -a MISSING_ARR <<<"${MISSING:-}"
    declare -A RESEARCHED_SET=()
    for __r in "${RESEARCHED_ARR[@]}"; do RESEARCHED_SET["$__r"]=1; done
    for N in "${MISSING_ARR[@]}"; do
      if [ -f ".zskills/research-staging/$PIPELINE_ID/issue-${N}.md" ]; then
        RESEARCHED_SET["$N"]=1
      fi
    done
    unset __r N
    # MISSING_ARR retains only candidates that have NEITHER committed row NOR scratchpad.
    # In auto-mode, this should be empty after a successful dispatch; if non-empty,
    # the message warns and Phase 3 will retry research-on-demand for them.
    declare -a STILL_MISSING=()
    for N in "${MISSING_ARR[@]}"; do
      if [ -z "${RESEARCHED_SET[$N]:-}" ]; then STILL_MISSING+=("$N"); fi
    done
    if [ "${#STILL_MISSING[@]}" -gt 0 ]; then
      echo "fix-issues Phase 2: research agents did not produce scratchpads for: ${STILL_MISSING[*]} — Phase 3 will retry research-on-demand" >&2
    fi
  else
    echo "fix-issues Phase 2: ${#MISSING_ARR[@]} candidate(s) lack research blurbs: ${MISSING_ARR[*]}" >&2
    echo "Run \`/fix-issues sync\` first to populate tracker rows, then re-run the sprint." >&2
    exit 1
  fi
fi

# Preserve `CANDIDATE_ISSUES` as the full uncapped Ready∩Open list (drag
# order). Expose `RESEARCHED` as a parallel associative-array index so the
# Phase 3 dispatch loop can ask "is this candidate researched yet?" per
# iteration. Without this preservation, Phase 3 cannot reach the
# unresearched tail when it advances past race-lost or skipped candidates
# (B-proper structural change; see "Per-issue dispatch loop" in Phase 3).
# If RESEARCHED_ARR ends up empty after auto-research, Phase 3's loop
# still iterates CANDIDATE_ISSUES — each candidate triggers synchronous
# research-on-demand on cache miss, and the existing "no actionable
# issues" path fires only if zero candidates pass triage.
# (When the auto-mode branch above fires, RESEARCHED_SET is already
# populated from the union rebuild; this fence is the no-MISSING fallthrough.)
if ! declare -p RESEARCHED_SET >/dev/null 2>&1; then
  declare -A RESEARCHED_SET=()
  for __r in "${RESEARCHED_ARR[@]}"; do
    RESEARCHED_SET["$__r"]=1
  done
  unset __r
fi

# PR-2 / A+F: drop SKIP_TAGGED candidates from CANDIDATE_ISSUES. The
# filter-script SKIP_TAGGED line lists `<num>:<skip-code>` for rows
# whose `Action now:` value resolves to a canonical dashboard skip-code
# (plan-scale / bug-unclear-cause / needs-decision). These were
# classified as non-actionable in prior fires; skip re-research and
# re-triage now (#606 tax fix).
read -r -a SKIP_TAGGED_ARR <<<"${SKIP_TAGGED:-}"
declare -A SKIP_TAGGED_SET=()
for tok in "${SKIP_TAGGED_ARR[@]+"${SKIP_TAGGED_ARR[@]}"}"; do
  case "$tok" in
    *:*) SKIP_TAGGED_SET["${tok%%:*}"]="${tok#*:}" ;;
  esac
done
unset tok
if [ "${#SKIP_TAGGED_SET[@]}" -gt 0 ]; then
  declare -a _FILTERED=()
  for N in "${CANDIDATE_ISSUES[@]}"; do
    if [ -z "${SKIP_TAGGED_SET[$N]:-}" ]; then
      _FILTERED+=("$N")
    else
      echo "fix-issues Phase 2: dropping skip-tagged #$N (${SKIP_TAGGED_SET[$N]}) — already classified" >&2
    fi
  done
  # `+` suffix guards `set -u` when _FILTERED is empty (all candidates dropped).
  CANDIDATE_ISSUES=("${_FILTERED[@]+"${_FILTERED[@]}"}")
  unset _FILTERED N
fi

echo "Candidates after Phase 2 source-filter: ${CANDIDATE_ISSUES[*]:-(none)}"
echo "  researched (will dispatch directly): ${RESEARCHED_ARR[*]:-(none)}"
echo "  un-researched (Phase 3 will research-on-demand): ${MISSING_ARR[*]:-(none)}"
```

**Auto-mode research dispatch — orchestrator pattern.** When the auto
branch fires, the orchestrator dispatches one `general-purpose` Agent per
MISSING entry (max 3 concurrent), each with this prompt shape:

> Research GitHub issue #N for `/fix-issues` Phase 1 backfill. Read
> `gh issue view N` for the full body. Grep the codebase for affected
> files. Append a tracker row to the appropriate
> `$ZSKILLS_ISSUES_DIR/*ISSUES*.md` (match domain — `ISSUES_PLAN.md` for
> orchestration/skill prose; `QE_ISSUES.md` for test-quality; or the
> existing per-domain file). Row format mirrors existing entries (see
> `### #338` / `### #336` / `### #390` blurbs in `ISSUES_PLAN.md` for
> shape): `### #N — <title>` H3, `**Labels:** ... | **Verdict:** ...`
> line, `**Problem.**` paragraph, `**Fix outline.**` paragraph,
> `**Complexity:** S/M/L. **Action now:** /do pr — <one-liner>` line.
> Write the row content to `.zskills/research-staging/$PIPELINE_ID/issue-${N}.md`
> in the MAIN REPO root (use `mkdir -p .zskills/research-staging/$PIPELINE_ID && cat > .zskills/research-staging/$PIPELINE_ID/issue-${N}.md <<'ROW' ... ROW`).
> Do NOT touch `$ZSKILLS_ISSUES_DIR/*ISSUES*.md`. Do NOT `git add` or
> `git commit`. The orchestrator promotes the scratchpad to a committed
> tracker row after seeing the per-issue claim-acquire outcome.

(The `<<'ROW' ... ROW` heredoc keeps the row content literal; do NOT use
a double-quoted heredoc — variables in the row body would expand
unexpectedly.)

The orchestrator MUST block until each dispatched agent writes its
scratchpad, THEN rebuild `RESEARCHED_SET` as the union of
filter-RESEARCHED (committed rows from prior fires) and
scratchpads-just-created (this fire). See Phase 2's
"After research dispatches return" block.

When the dashboard branch returns picks, skip the ranking/focus rubric
below and proceed directly to the **Triage** subsection with
`CANDIDATE_ISSUES` as the input list. The triage routing (in-batch
fix-agent vs `/do pr` vs `/draft-plan` vs skip) still applies — the
dashboard only overrides the *selection*, not the *routing*.

**Cap to N happens AFTER triage, not before.** Phase 2 triage produces a
full classified list across the researched subset of `CANDIDATE_ISSUES`
in drag order — it does NOT cap at N. Phase 3 then iterates the full
`CANDIDATE_ISSUES` array (including unresearched tail; see B-proper
"Per-issue dispatch loop" below), dispatching synchronous
research-on-demand on cache miss, classifying each issue narratively
per the 7-bucket rubric, attempting a claim-acquire per actionable
pick, and KEEPING the first N that route to **in-batch fix-agent** or
**/do pr** AND that successfully acquire the per-issue claim. Issues
that triage to **"Bug with unclear cause"**, **"Plan-scale"**, **"Too
vague"**, **"Author decision needed"**, or that race-lose / fail
research are recorded as skips and do NOT count toward N — Phase 3
keeps iterating. Stop iterating once N successfully-dispatched picks
have been collected (or `CANDIDATE_ISSUES` exhausts). If candidates
exhaust before N actionable are found, dispatch what was found
(partial-fill is normal); if zero are dispatched, the existing "no
actionable issues" path fires unchanged. This prevents a single
top-of-queue plan-scale/vague/race-lost item from stalling the entire
queue behind it.

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

#### Source-filter un-researched candidates (issue #408)

After ranking, build `CANDIDATE_ISSUES` from the ranked list (top N
candidates in priority order) and apply the same Phase 2 source-filter
the dashboard branch uses. Without this filter, Phase 1's prose-only
research dispatch can skip silently and Phase 2 triages from bare
titles — bypassing #402's independent-sizing prose (which requires a
tracker blurb to read against).

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
fi
# CANDIDATE_ISSUES is populated from the ranking table above (top N in
# priority order). Apply the same filter the dashboard branch uses.
eval "$(ZSKILLS_ISSUES_DIR="$ZSKILLS_ISSUES_DIR" \
  bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/filter-unresearched-candidates.sh" \
  "${CANDIDATE_ISSUES[@]}")"
read -r -a RESEARCHED_ARR <<<"${RESEARCHED:-}"
read -r -a MISSING_ARR <<<"${MISSING:-}"

if [ ${#MISSING_ARR[@]} -gt 0 ]; then
  if [ "$AUTO_FLAG" = "1" ]; then
    # AUTO MODE — dispatch general-purpose research agents in parallel
    # for MISSING_ARR (up to 3 at a time), mirroring Phase 1 step 6.
    # Each agent writes the row content to `.zskills/research-staging/$PIPELINE_ID/issue-${N}.md` (scratchpad)
    # and returns without touching $ZSKILLS_ISSUES_DIR/*ISSUES*.md or committing. The orchestrator
    # promotes scratchpads to committed tracker rows in Phase 3 per the acquire-outcome decision
    # tree (see "Per-issue dispatch loop (B-proper)" below).
    # See the dashboard branch's expanded prose for the agent prompt shape.
    echo "fix-issues Phase 2: ${#MISSING_ARR[@]} candidate(s) lack research blurbs in auto mode: ${MISSING_ARR[*]}" >&2
    echo "Dispatching research agents in parallel (up to 3 at a time). Blocking until research scratchpads ready." >&2
    # After research dispatches return, RESEARCHED_SET is the union of:
    #   (a) candidates with committed tracker rows from prior fires (filter-RESEARCHED)
    #   (b) candidates whose scratchpads this pipeline just created
    eval "$(ZSKILLS_ISSUES_DIR="$ZSKILLS_ISSUES_DIR" \
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/filter-unresearched-candidates.sh" \
      "${CANDIDATE_ISSUES[@]}")"
    read -r -a RESEARCHED_ARR <<<"${RESEARCHED:-}"
    read -r -a MISSING_ARR <<<"${MISSING:-}"
    declare -A RESEARCHED_SET=()
    for __r in "${RESEARCHED_ARR[@]}"; do RESEARCHED_SET["$__r"]=1; done
    for N in "${MISSING_ARR[@]}"; do
      if [ -f ".zskills/research-staging/$PIPELINE_ID/issue-${N}.md" ]; then
        RESEARCHED_SET["$N"]=1
      fi
    done
    unset __r N
    # MISSING_ARR retains only candidates that have NEITHER committed row NOR scratchpad.
    # In auto-mode, this should be empty after a successful dispatch; if non-empty,
    # the message warns and Phase 3 will retry research-on-demand for them.
    declare -a STILL_MISSING=()
    for N in "${MISSING_ARR[@]}"; do
      if [ -z "${RESEARCHED_SET[$N]:-}" ]; then STILL_MISSING+=("$N"); fi
    done
    if [ "${#STILL_MISSING[@]}" -gt 0 ]; then
      echo "fix-issues Phase 2: research agents did not produce scratchpads for: ${STILL_MISSING[*]} — Phase 3 will retry research-on-demand" >&2
    fi
  else
    echo "fix-issues Phase 2: ${#MISSING_ARR[@]} candidate(s) lack research blurbs: ${MISSING_ARR[*]}" >&2
    echo "Run \`/fix-issues sync\` first to populate tracker rows, then re-run the sprint." >&2
    exit 1
  fi
fi

# Preserve `CANDIDATE_ISSUES` as the full uncapped ranked list and expose
# `RESEARCHED_SET` as a parallel index. See the dashboard branch's
# expanded prose above for the rationale; Phase 3's per-issue dispatch
# loop iterates `CANDIDATE_ISSUES` and dispatches synchronous
# research-on-demand on cache miss.
# (When the auto-mode branch above fires, RESEARCHED_SET is already
# populated from the union rebuild; this fence is the no-MISSING fallthrough.)
if ! declare -p RESEARCHED_SET >/dev/null 2>&1; then
  declare -A RESEARCHED_SET=()
  for __r in "${RESEARCHED_ARR[@]}"; do
    RESEARCHED_SET["$__r"]=1
  done
  unset __r
fi

# PR-2 / A+F: drop SKIP_TAGGED candidates from CANDIDATE_ISSUES. Mirrors
# the dashboard branch's block — see expanded prose there. Functions
# don't span skill fences so the block is duplicated literally.
read -r -a SKIP_TAGGED_ARR <<<"${SKIP_TAGGED:-}"
declare -A SKIP_TAGGED_SET=()
for tok in "${SKIP_TAGGED_ARR[@]+"${SKIP_TAGGED_ARR[@]}"}"; do
  case "$tok" in
    *:*) SKIP_TAGGED_SET["${tok%%:*}"]="${tok#*:}" ;;
  esac
done
unset tok
if [ "${#SKIP_TAGGED_SET[@]}" -gt 0 ]; then
  declare -a _FILTERED=()
  for N in "${CANDIDATE_ISSUES[@]}"; do
    if [ -z "${SKIP_TAGGED_SET[$N]:-}" ]; then
      _FILTERED+=("$N")
    else
      echo "fix-issues Phase 2: dropping skip-tagged #$N (${SKIP_TAGGED_SET[$N]}) — already classified" >&2
    fi
  done
  CANDIDATE_ISSUES=("${_FILTERED[@]+"${_FILTERED[@]}"}")
  unset _FILTERED N
fi

echo "Candidates after Phase 2 source-filter: ${CANDIDATE_ISSUES[*]:-(none)}"
echo "  researched (will dispatch directly): ${RESEARCHED_ARR[*]:-(none)}"
echo "  un-researched (Phase 3 will research-on-demand): ${MISSING_ARR[*]:-(none)}"
```

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
  scope-creep risk). Dispatch `/do pr` for the issue, which adds
  pre-execution plan-review (catches scope drift before commit) plus CI
  poll + fix-cycle without you hand-orchestrating each step. Per-issue
  /do pr dispatch replaces the in-batch fix-agent for this category.

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
  - **Counter-signal — detailed spec means EASIER, not harder.** A long
    issue body with locked design decisions (proposed interface, specific
    file locations, explicit scope section, worked examples) is evidence
    the design work is already done. Do NOT classify as plan-scale solely
    because the body is long or has multiple sections. Heuristic: classify
    as actionable (one of the first two tiers) unless the implementation
    genuinely touches 3+ skills/subsystems or requires new infrastructure
    that doesn't exist yet. A pre-planned issue is the opposite of
    plan-scale — it's a well-specified fix waiting to be dispatched.

- **Too vague** — no repro steps, no expected behavior, body is empty or
  just "it's broken." You don't know WHAT to fix.
  - Interactive: flag it and ask the user for clarification
  - Auto: skip it, report as "Skipped: insufficient context" in
    $ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md

- **Author decision needed** (`needs-decision`) — the tracker blurb's
  `**Action now:**` line value is literally `none` AND the trailing
  reason contains "author decision" or "decide" (e.g., `Action now:
  none — author decision needed on which option`). The research blurb
  has explicitly deferred tier-choice to a human; `/fix-issues` is NOT
  the right surface to second-guess that.
  - Interactive: surface the blurb's verbatim `Action now:` value
    alongside the issue number and a one-line note ("author decision
    needed before fix can dispatch"). Do NOT dispatch a fix; wait for
    the user to choose (e.g., re-file, /draft-plan, manual triage).
  - Auto: skip it with note `Skipped: needs-decision — Action
    now: <verbatim value>`. **Does NOT count toward N** — keep
    iterating (same as the other skip buckets per the "Cap to N happens
    AFTER triage" rule above). The skip MUST appear in the per-fire
    user-facing summary (see "Per-fire user-facing summary" below) so
    repeated cron fires do not silently no-op while a single stable
    `Action now: none` blurb sits at the top of the queue.

- **Deferred** (`deferred`) — the tracker blurb's `**Action now:**`
  line value is literally `none` BUT the trailing reason does NOT
  contain "author decision" or "decide" (e.g., `Action now: none —
  leave open as architectural memo`, `none — waiting on prerequisite
  plans`). The agent decided no action is needed now; this is NOT
  awaiting human input. Without this bucket, such blurbs get
  conflated with `needs-decision` and the dashboard misleadingly
  implies action is required.
  - Interactive: surface the blurb's verbatim `Action now:` value
    alongside the issue number and a one-line note ("deferred — no
    action now"). Do NOT dispatch a fix.
  - Auto: skip it with note `Skipped: deferred — Action now:
    <verbatim value>`. **Does NOT count toward N**.

**Independently size the smallest coherent fix that closes the reported
defect.** Identify the specific file:line / code-change shape that would
fix the bug as filed, then tier THAT fix — not whatever the body's
"Recommended tier" / "Implementation tier" / "Larger-than-issue" /
"Structural" sections claim. Body framings are HINTS; the agent is the
sizer. Common anti-pattern: body pairs a ship-now fix with a
structural-rewrite musing under one tier — separate them. Ship the
immediate fix at its true tier; file the structural concern as a
follow-up issue. Don't conflate the two.

**Worked examples (2026-05-18 calibration):**
- **#380** (tests false-PASS pre-commit). Body said "Both [Fix A
  test-side + Fix B verifier-discipline] are /draft-plan tier."
  Independent sizing: Fix A = 2 known test files + one-grep audit =
  **implementer-tier**; Fix B = same prose at ~6 verifier-dispatch
  sites = **/do pr-tier**. Neither was /draft-plan.
- **#390** (warn-config-drift mirror stale). Body's "Larger-than-issue"
  framing suggested structural rewrite. Independent sizing: the body's
  "preferred" `cp` + byte-equality conformance test IS the structural
  fix; the mirror is load-bearing for prompt-avoidance.
  **Implementer-tier as written.**

**"Too vague" means you don't know WHAT to do — not that you don't know
HOW.** If the issue clearly describes the problem but the fix is hard,
that's not vague — that's work. Never use "vague" as an excuse to skip
hard issues.

**Picking between in-batch fix-agent and `/do pr`.** The in-batch
fix-agent is appropriate when the fix is mechanical enough that
post-execution diff review (which `/fix-issues` Phase 4 already
dispatches) is sufficient. `/do pr` is appropriate when *before* the
fix, you want a second pair of eyes on the plan — typically when the
issue has multiple discipline surfaces (version bumps + mirror, test
updates + source change, doc update + behavior change). The
`/do pr` plan-reviewer's auto-REVISE on >4 Acceptance bullets is
the mechanical signal that says "this is bigger than `/do pr` —
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

- **Without `auto`:** **Wait for user approval** of the list before
  proceeding. Include the grouping rationale so the user can adjust.
- **With `auto`:** Present the ranked table for the record, then
  proceed immediately using the ranking criteria above. `auto` skips
  the approval gate AND triggers auto-merge via `/land-pr --auto` (see
  "Auto-flag gating depends on landing mode" below).

### Per-fire user-facing summary

The orchestrator MUST print a structured per-fire summary as part of
its **user-facing response** on EVERY sprint fire (both the productive branch and the no-actionable branch — the `exit 0` arm in the next subsection — emit it; after triage selects work for Phase 3 dispatch on productive fires, before exit on no-op fires).
Without this, stable skips (`Action now: none`, "author decision
needed") are invisible and a recurring cron silently no-ops fire after
fire while the user has no signal as to why. Past failure: 2026-05-19,
12+ consecutive `every 30m` cron fires no-op'd because #432's blurb
read `Action now: none — author decision needed` and the only
user-facing output was a single stderr line saying "no actionable
issues this fire (open=$OPEN_COUNT)" — the user had to ask directly
why nothing was happening.

Construct the summary from in-scope state (the list of issues
dispatched in Phase 3, the skip-record collected during triage, and
`$OPEN_COUNT` from Phase 1b). This is a **model-layer instruction**:
the orchestrator emits the summary as prose in its final response, in
addition to (not replacing) the stderr line at the no-actionable exit
and any sprint-report writes Phase 5 does on productive fires.

Required shape (markdown-friendly, one block):

```
Picked: #N (bucket) — <one-line>           (one per dispatched issue; or "(none)")
Skipped: #N (bucket: <name>) — Action now: <verbatim value> — <one-sentence rationale>   (one per skipped issue)
Pool: <count> open candidates considered
```

Rules:

- **`Picked:`** — one line per Phase-3-dispatched issue, with the
  triage bucket in parens and a one-line summary. If zero issues were
  dispatched (no-actionable branch), emit `Picked: (none)`.
- **`Skipped:`** — one line per skipped issue, with the bucket name,
  the blurb's `**Action now:**` value verbatim (the exact string after
  `Action now:`, including any trailing rationale or command), and a
  one-sentence rationale. Quote the Action-now value EXACTLY — don't
  paraphrase, don't truncate; it is the load-bearing signal the user
  needs to decide whether to act. Bucket names enumerated by the
  7-tier triage rubric plus Phase 3's two run-time skip classes:
  `plan-scale`, `bug-unclear-cause`, `needs-decision`, `deferred`,
  `too-vague`, `author-decision`, **`race-lost`** (claim-acquire returned exit 10 —
  concurrent pipeline holds the issue; B-proper loop advanced to the
  next candidate), and **`research-failed`** (Phase 3
  research-on-demand agent did not commit a tracker row for an
  un-researched candidate; loop advanced past it). For `race-lost` and
  `research-failed`, the verbatim `Action now:` value may be empty
  (the latter never got a row written); render as
  `Action now: (n/a — research did not complete)` or
  `Action now: <verbatim>` per what is available.
- **`Pool:`** — the count of open candidates considered this fire
  (equal to `$OPEN_COUNT` or the dashboard-Ready intersection size,
  whichever sourced this fire's candidate list).
- The summary goes to **stdout** as part of the user-facing response.
  The existing stderr one-liner at the no-actionable exit is PRESERVED
  (it remains useful as a terse log signal); this section ADDS the
  structured stdout report on top.

Worked example (the #432 fire that motivated this section):

```
Picked: (none)
Skipped: #432 (bucket: Author decision needed) — Action now: none — author decision needed — research blurb defers tier choice to user; no fix can dispatch until /draft-plan or re-triage.
Pool: 1 open candidate considered
```

This makes the cron's stable no-op state immediately legible — the
user can see #432 is stuck on author input, and decide whether to
re-file, run `/draft-plan #432`, or stop the cron.

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

2. **If still no actionable issues after refresh:** the sprint-level
   worktree the gate at Phase 1 created earlier (`$WT_PATH`) is still
   on disk. Two branches — ship sync's tracker discoveries if it
   wrote anything, otherwise remove the empty worktree. Either way,
   end with `exit 0` and no stranded `/tmp/zskills-fix-issues-sprint-*`
   directory. **Do NOT** write to `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`
   in either branch (mirrors the defer-all arm's stderr-only shape from
   #331). The user decides when to stop the cron from cron list +
   recent PR history signals; no nag counter, no marker, no read-back.

   The ship branch mirrors the Phase 6 sprint-level `/land-pr`
   dispatch (`### Sprint-level SPRINT_REPORT.md landing` later in this
   skill) — same arg vector, same tracking-pair pattern — scoped to
   the tracker-only changes Phase 1a sync produced, with a different
   `SPRINT_LAND_ID` namespace (`fix-issues.sync.${SPRINT_ID}`) so it
   does not collide with the Phase 6 sprint-report land. The cleanup
   branch leaves the worktree (`git worktree remove --force`) so disk
   does not accumulate across exhausted-queue cron fires.

   <!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: the SPRINT_REPORT.md basename appears only inside a comment explaining WHY the no-actionable arm does NOT write to it (strand bug sibling to #331); no actual `cat >> SPRINT_REPORT.md` heredoc lives in this fence — see tests/test-fix-issues-sprint-worktree-gate.sh assertion 9 -->
   ```bash
   if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)

   if [ -n "${WT_PATH:-}" ]; then
     # Re-anchor in case Phase 1a sync or any sub-dispatch cd'd away.
     cd "$WT_PATH" || { echo "fix-issues: cd $WT_PATH failed (no-actionable)" >&2; exit 1; }
     export ZSKILLS_PATHS_ROOT="$WT_PATH"

     TOPLEVEL=$(git rev-parse --show-toplevel)
     # Detect tracker changes Phase 1a sync may have produced in the
     # sprint worktree. Use --porcelain so a clean tree yields empty
     # stdout. Includes both unstaged and staged.
     if [ -n "$(git -C "$TOPLEVEL" status --porcelain)" ]; then
       # SHIP branch — tracker refresh from sync. Mirrors the Phase 6
       # sprint-level /land-pr dispatch shape (see "### Sprint-level
       # SPRINT_REPORT.md landing" later in this skill).
       git -C "$TOPLEVEL" add -A
       STAGED=$(git -C "$TOPLEVEL" diff --cached --name-only)
       if [ -z "$STAGED" ]; then
         # Defensive: somehow nothing staged after add -A → fall through
         # to cleanup to avoid an empty commit.
         echo "fix-issues no-actionable: status reported dirty but nothing staged — removing worktree" >&2
         cd "$MAIN_ROOT" && git worktree remove --force "$WT_PATH"
       else
         if [ -n "${COMMIT_CO_AUTHOR:-}" ]; then
           git -C "$TOPLEVEL" commit --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" \
             -m "docs(sync): tracker refresh from /fix-issues fire $SPRINT_ID"
         else
           git -C "$TOPLEVEL" commit -m "docs(sync): tracker refresh from /fix-issues fire $SPRINT_ID"
         fi

         SPRINT_LAND_ID="fix-issues.sync.${SPRINT_ID}"
         [ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
         mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
         printf 'skill: land-pr\nrequired-by: fix-issues-no-actionable\ndate: %s\n' \
           "$(TZ=UTC date -Iseconds)" \
           > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${SPRINT_LAND_ID}"

         RESULT_FILE=$(mktemp)
         BODY_FILE=$(mktemp)
         {
           printf '## Summary\n`/fix-issues` fire %s found no actionable issues; Phase 1a sync produced tracker updates that ship here.\n\n' "$SPRINT_ID"
           printf '## Test plan\n- [x] Sync-only diff; no per-issue work executed this fire.\n'
         } > "$BODY_FILE"

         PR_TITLE="sync: tracker refresh from /fix-issues fire $SPRINT_ID"
         SPRINT_BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)
         # This dispatch fires when Phase 2 found no actionable issues but
         # Phase 1a sync wrote tracker updates. The PR commits only sync-driven
         # content (`git add -A` against the worktree after sync ran, before any
         # fix work), so it ALWAYS auto-merges regardless of user's `auto` arg —
         # same rationale as standalone sync's Phase 5 dispatch at the top of
         # this skill.
         LAND_ARGS="--branch=$SPRINT_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-no-actionable --worktree-path=$TOPLEVEL --tracking-id=$SPRINT_LAND_ID --auto"

         echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

         # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

         if [ ! -f "$RESULT_FILE" ]; then
           echo "ERROR: /land-pr (no-actionable sync-land) produced no result file at $RESULT_FILE" >&2
         else
           declare -A LP_NOACT
           while IFS='=' read -r KEY VALUE; do
             case "$KEY" in
               STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
               MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
               CONFLICT_FILES_LIST|CALL_ERROR_FILE)
                 LP_NOACT["$KEY"]="$VALUE" ;;
               "") ;;
               *) printf 'WARN: /land-pr (no-actionable sync-land) result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
             esac
           done < "$RESULT_FILE"
           case "${LP_NOACT[STATUS]:-}" in
             merged)
               printf 'skill: land-pr\nid: %s\npr: %s\nbranch: %s\ndate: %s\n' \
                 "$SPRINT_LAND_ID" "${LP_NOACT[PR_URL]:-}" "$SPRINT_BRANCH" \
                 "$(TZ=UTC date -Iseconds)" \
                 > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$SPRINT_LAND_ID"
               ;;
             *)
               echo "fix-issues no-actionable sync-land: /land-pr STATUS=${LP_NOACT[STATUS]:-unknown} — sync PR left open" >&2
               ;;
           esac
         fi
       fi
     else
       # CLEANUP branch — sync wrote nothing; worktree is empty.
       # Leave $WT_PATH before `git worktree remove` so we are not
       # standing inside the directory being removed.
       cd "$MAIN_ROOT" && git worktree remove --force "$WT_PATH"
     fi
   fi

   echo "fix-issues: no actionable issues this fire (open=$OPEN_COUNT); cron will retry on next fire." >&2
   exit 0
   ```

   **Before `exit 0`: emit the per-fire user-facing summary.** Per the
   "Per-fire user-facing summary" subsection above, the orchestrator's
   final response on this no-actionable branch MUST include the
   structured `Picked: (none)` / `Skipped: ...` / `Pool: ...` block —
   listing every candidate considered this fire with its bucket and
   verbatim `**Action now:**` value. The stderr line above is preserved
   as a terse log signal; the structured stdout summary is the
   user-facing report. This is the only way a recurring cron can
   surface stable skips (e.g., `Action now: none — author decision
   needed`) instead of silently no-op'ing fire after fire.

### Post-prioritize tracking

After Phase 2 (prioritize) is complete:
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
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

   See "Live worktree count check (defer-all gate)" in Phase 1 — that
   block exits the sprint cleanly (no worktree, no markers) if all slots
   are taken at entry. See "Live worktree count check (partial-dispatch
   trim)" below — that block trims `TO_DISPATCH` if the available slots
   are fewer than the batch size built in Phase 2.

- **Interrelated issues** (same root cause or same files from Phase 2
  grouping) share one agent and one worktree. Tell the agent which
  issues are grouped and why.
- **Unrelated issues get separate agents.** Never batch unrelated hard
  issues into one agent — this caused a 4.5h bottleneck when one agent
  got 4 diverse issues sequentially.

### Live worktree count check (partial-dispatch trim)

Run this **before** the dispatch loop (cherry-pick / direct / PR mode all).
The defer-all arm of this gate already ran in Phase 1 ("Live worktree count
check (defer-all gate)") — if we reached this point, at least one slot was
free at sprint entry. Here we only handle the partial-dispatch case: if
the available slot count is now less than the batch the orchestrator built
in Phase 2, trim `TO_DISPATCH` in place and re-prioritise the remainder on
the next fire. We re-compute `LIVE_COUNT` because slots may have changed
between Phase 1 and here (other concurrent pipelines, etc.).

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: the SPRINT_REPORT.md basename appears only inside comments explaining WHY this trim does NOT write to it (symmetry with the Phase 1 defer-all gate); no actual `cat >> SPRINT_REPORT.md` heredoc lives in this fence — see tests/test-fix-issues-sprint-worktree-gate.sh assertion 8 -->
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# $ZSKILLS_MAX_CONCURRENT_WORKTREES is now set (defaults to 3 when the
# execution.max_concurrent_worktrees field is absent or malformed).

# Recount live fix/issue-* worktrees, skipping `.landed status: landed`
# entries (same predicate as the Phase 1 defer-all gate — see that block
# for the why; this is the symmetric per-batch trim).
LIVE_COUNT=$(
  git worktree list --porcelain \
    | awk '/^worktree /{wt=$2} /^branch refs\/heads\/fix[/-]issue-/{print wt}' \
    | while read -r wt; do
        if [ -f "$wt/.landed" ] && grep -q '^status: landed' "$wt/.landed"; then
          continue
        fi
        echo X
      done \
    | wc -l \
    | tr -d ' '
)

CAP="$ZSKILLS_MAX_CONCURRENT_WORKTREES"
N_REQUESTED="${#TO_DISPATCH[@]}"  # how many fix agents this sprint wants to dispatch
SLOTS=$(( CAP - LIVE_COUNT ))
if [ "$SLOTS" -le 0 ]; then
  # Edge case: slots vanished between the Phase 1 defer-all gate and now
  # (concurrent pipeline filled the cap). Defer the whole batch — no
  # audit-write to SPRINT_REPORT.md here either (defer events are
  # transient; see Phase 1 defer-all gate comment).
  echo "fix-issues: live count ($LIVE_COUNT) re-saturated cap ($CAP) before dispatch; deferring sprint $PIPELINE_ID. Cron will retry." >&2
  exit 0
elif [ "$SLOTS" -lt "$N_REQUESTED" ]; then
  # Some slots, but not enough for the full batch. Dispatch the first SLOTS;
  # queue the rest for the next fire. The queued issues stay open and the
  # next cron tick (or `/fix-issues next`) will re-prioritise them. No
  # `cat >> SPRINT_REPORT.md` audit-write — symmetry with the defer-all
  # gate above; the queued-subset signal lives on stderr.
  echo "fix-issues: live count $LIVE_COUNT, cap $CAP — $SLOTS slots available, dispatching $SLOTS of $N_REQUESTED. Queued for next fire: ${TO_DISPATCH[*]:$SLOTS}" >&2
  TO_DISPATCH=( "${TO_DISPATCH[@]:0:$SLOTS}" )
fi
# Otherwise SLOTS >= N_REQUESTED — proceed with the full dispatch loop below.
# The per-message I/O contention cap (3) still applies inside the dispatch
# loop, so a batch of 5 still pages out as 3+2 even when SLOTS=5.
```

Notes:
- `TO_DISPATCH` is the array of issue numbers the orchestrator built in
  Phase 2's prioritisation. The cap-check truncates it in place; the
  dispatch loop below iterates `TO_DISPATCH` as usual.
- The awk/while predicate matches BOTH the PR-mode pattern
  `fix/issue-NNN` and the cherry-pick/direct-mode pattern
  `fix-issue-NNN` (bracket alternation `fix[/-]issue-`), and skips
  any worktree whose `.landed` marker reads `status: landed` — those
  are done-but-uncleaned cleanup artifacts, not live work.
- The cap can be raised by editing `execution.max_concurrent_worktrees` in
  `.claude/zskills-config.json`. Raise above 3 only on hosts with ample
  CPU/memory/disk headroom — past containers OOMed at 8 concurrent live.

**Agent timeout: 1 hour.** Note the dispatch time for each agent. If an
agent hasn't returned after 1 hour, declare it **failed**:
- Mark its issues as "Timed out" in `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`
- Issues stay open for the next sprint
- The worktree is a cleanup artifact — do NOT auto-land late results
- If the agent eventually returns, ignore it. Timed out = failed, period.
- **Release the per-issue claim** so a later sprint (or a concurrent
  pipeline) can pick the issue up again. For each timed-out issue, call:

  ```bash
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  fi
  bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" \
       release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
  ```

  `|| true` because release is idempotent and best-effort at this terminal
  arm; the timeout itself is the load-bearing signal — release failure
  surfaces only as a stderr line and the claim is harmless until the next
  pipeline re-acquires (acquire-EEXIST detects the live claim).

**Agent dispatch prompts MUST include for each issue:**

1. **The verbatim issue body** from Phase 1b (`gh issue view`). Do NOT
   paraphrase or summarize — include the full text the user wrote. Titles are
   often vague; the body is the spec. If the body is empty, say so explicitly.
2. **The research blurb from issue tracker files** (`$ZSKILLS_ISSUES_DIR/*ISSUES*.md`).
   These contain root cause analysis, affected files, suggested fixes, and
   effort estimates written when the issue was filed. Grep the tracker files
   for the issue number and include any matching section verbatim.
3. **Tier-1 hash-registration directive** (verbatim — copy this paragraph
   into every fix-impl prompt; do not paraphrase or omit, even if the
   issue body looks unrelated to Tier-1 files):

   > **Tier-1 file discipline.** If your fix modifies a Tier-1 script
   > (any file whose name appears as a row with column-3 == `1` in
   > `skills/update-zskills/references/script-ownership.md` — the
   > `tier1-shipped-hashes.txt` registry tracks their blob SHAs), the
   > SAME commit MUST also register the new blob hash in
   > `skills/update-zskills/references/tier1-shipped-hashes.txt`.
   > Detection + registration recipe (run AFTER staging your fix, BEFORE
   > `git commit`):
   > ```bash
   > # 1. Enumerate Tier-1 source paths from script-ownership.md.
   > TIER1_PATHS=$(awk -F'|' 'NR>1 && $3 ~ /^[[:space:]]*1[[:space:]]*$/ {
   >   gsub(/[[:space:]`]/, "", $2);
   >   owner=$4; sub(/^[[:space:]`]+/, "", owner);
   >   sub(/[[:space:]`(].*$/, "", owner);
   >   if (length($2) > 0) {
   >     src="skills/" owner "/scripts/" $2;
   >     if (system("test -f " src) == 0) print src;
   >   }
   > }' skills/update-zskills/references/script-ownership.md)
   > # 2. Intersect with your staged changes.
   > STAGED=$(git diff --cached --name-only)
   > for f in $STAGED; do
   >   if grep -qxF "$f" <<<"$TIER1_PATHS"; then
   >     NEW_HASH=$(git hash-object "$f")
   >     if ! grep -qxF "$NEW_HASH" skills/update-zskills/references/tier1-shipped-hashes.txt; then
   >       echo "$NEW_HASH" >> skills/update-zskills/references/tier1-shipped-hashes.txt
   >       sort -o skills/update-zskills/references/tier1-shipped-hashes.txt skills/update-zskills/references/tier1-shipped-hashes.txt
   >       git add skills/update-zskills/references/tier1-shipped-hashes.txt
   >       echo "Registered Tier-1 hash for $f -> $NEW_HASH" >&2
   >     fi
   >   fi
   > done
   > ```
   > Without this step the Tier-1 drift invariant in
   > `tests/test-skill-invariants.sh` fails on CI, requiring a follow-up
   > commit to recover. Past failures: sprint-20260520 issues #468, #474
   > each lost a full CI cycle to this gap (see SPRINT_REPORT.md). This
   > directive is canonical — orchestrators must NOT hand-inject it
   > per-invocation; it ships with every fix-impl prompt as part of
   > `/fix-issues` source.

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
5. Run `$FULL_TEST_CMD` (canonical form — maintainers: see
   `references/canonical-config-prelude.md` §1 in the zskills source) — all
   suites must pass.
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
8. **Scope-grep verification — before declaring done, verify all files
   in scope were touched.** Grep the issue body for a `## Files to change`
   section. For each file path listed, verify the implementer's diff
   touched it:
   ```bash
   git diff origin/main..HEAD --name-only | grep -qF "<path>"
   ```
   If any listed file was NOT modified in the diff, the fix is incomplete.
   Either fix the remaining file(s) or explicitly note in the commit message
   why a listed file was not changed (e.g., "not changed because the root
   cause was entirely in file X"). Do not declare done until every file in
   the `## Files to change` section is accounted for. This closes the
   #629/#649 closure-incomplete pattern where agents fixed the titled file
   but missed companion files named deeper in the body.
9. Commit in the worktree (one issue per commit, clean history)
10. **Rebase onto current main before final commit:**
   ```bash
   # Verify we are on a feature branch before rebasing.
   git rev-parse --abbrev-ref HEAD
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

#### Selection filter (#641) — drop in-flight issue claims

Pipe the just-finalized `CANDIDATE_ISSUES` through
`filter-in-flight-issue-claims.sh` to drop issue numbers whose
`.zskills/claims/issue-<N>/claim.json` indicates an in-flight pipeline.
This is the unified downstream point — both Phase 2 paths (dashboard-mode
at ~line 1460, rubric-mode at the ranked-table block) have populated and
finalized `CANDIDATE_ISSUES` by here, and Phase 3's `for ISSUE_NUM in
"${CANDIDATE_ISSUES[@]}"` loop below is the first dispatch read. Mirrors
`/work-on-plans` Step 4's D4 filter (PR #645), adapted for integer issue
numbers instead of kebab-case plan slugs. See
`plans/plans-claim-chip-parity.md` for the parity rationale.

**Honest scope (DA2.7 mirror).** This filter closes the **steady-state**
race only — the claim is already on disk when both `/fix-issues`
invocations run filter. It does NOT close the **fresh-start** race
(both pipelines observe an empty claims-dir before either acquires);
that residual window is bounded by `claim-issue.sh`'s acquire-EEXIST
atomic mkdir → exit 10 contract, which Phase 3's per-iteration acquire
already handles via the `race-lost` skip-record arm. Same architecture
as `/work-on-plans` + `/run-plan`.

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
FILTER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/filter-in-flight-issue-claims.sh"
if [ -x "$FILTER" ] && [ "${#CANDIDATE_ISSUES[@]}" -gt 0 ]; then
  FILTERED=$(printf '%s\n' "${CANDIDATE_ISSUES[@]}" | bash "$FILTER")
  if [ -n "$FILTERED" ]; then
    mapfile -t CANDIDATE_ISSUES <<< "$FILTERED"
  else
    CANDIDATE_ISSUES=()
  fi
fi
```

(Defensive `[ -x ]` check so older installations without the script
don't break. Empty filter output rebuilds `CANDIDATE_ISSUES` as an empty
array rather than a one-element array with an empty string. The
`${#CANDIDATE_ISSUES[@]} -gt 0` guard is symmetric with the existing
SKIP_TAGGED fence guards above — both arms are no-ops when the array
is already empty.)

**Per-issue dispatch loop (B-proper).** The dispatch is an explicit
fenced `for` loop over `CANDIDATE_ISSUES` (the full uncapped Ready∩Open
list Phase 2 preserved) bounded by `DISPATCHED < N`. On each iteration:
(1) if the candidate is NOT in `RESEARCHED_SET`, dispatch a synchronous
research agent (same prompt shape Phase 1 step 6 / Phase 2 source-filter
auto-mode uses) and refresh the index — if research still does not commit
a row, record `research-failed` and continue; (2) narratively classify
the candidate per the 7-bucket triage rubric in
"### Triage: vague, complex, or interrelated issues" above — if
non-actionable (plan-scale / bug-unclear-cause / needs-decision /
deferred / too-vague / author-decision), record the skip and continue; (3) attempt
the per-issue claim acquire — on race-loss (exit 10), record
`race-lost` and continue to the next candidate; on filesystem error
(exit 11+), abort the sprint; on success, materialise the worktree and
dispatch the impl agent. The `record_skip "$ISSUE_NUM" "$BUCKET"` step
appends to the skip-record consumed by Phase 5 SPRINT_REPORT.md AND the
per-fire user-facing summary block (see "Per-fire user-facing summary"
above) — both destinations now enumerate `race-lost` and
`research-failed` alongside the existing 5 triage buckets.

Replaces the older PROSE-iterated fence shape where each acquire's
race-loss arm did `exit 0` to terminate the per-issue fence and the
orchestrator narratively "proceeded to the next issue." That shape was
observably broken: in the 2026-05-22 incident the orchestrator
race-lost two top picks, fell through to the no-actionable arm, and
30 minutes of cron time produced no work. The explicit loop forces the
loser to do real fix work on the next available candidates.

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)

DISPATCHED=0
declare -a SKIP_RECORD=()   # appended as "<bucket>:<issue_num>" tokens
                            # — consumed by Phase 5 sprint report + the
                            # per-fire user-facing summary.

for ISSUE_NUM in "${CANDIDATE_ISSUES[@]}"; do
  [ "$DISPATCHED" -ge "$N" ] && break

  # 1. Research-on-demand. If this candidate has no committed tracker row,
  # dispatch a synchronous general-purpose research agent (same prompt
  # shape Phase 2 source-filter auto-mode uses; block until it commits a
  # row) and refresh the index. If still unresearched after the call,
  # record `research-failed` and advance.
  if [ -z "${RESEARCHED_SET[$ISSUE_NUM]:-}" ]; then
    # Orchestrator action: Agent dispatch for issue $ISSUE_NUM with
    # `subagent_type: "general-purpose"`, same prompt shape as Phase 2
    # source-filter auto-mode (read `gh issue view`, grep codebase, write
    # row content to `.zskills/research-staging/$PIPELINE_ID/issue-${N}.md`,
    # no commit). After the dispatch returns, refresh RESEARCHED_SET by
    # unioning filter-RESEARCHED with the scratchpad-existence check.
    eval "$(ZSKILLS_ISSUES_DIR="$ZSKILLS_ISSUES_DIR" \
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/filter-unresearched-candidates.sh" \
      "${CANDIDATE_ISSUES[@]}")"
    read -r -a RESEARCHED_ARR <<<"${RESEARCHED:-}"
    RESEARCHED_SET=()
    for __r in "${RESEARCHED_ARR[@]}"; do RESEARCHED_SET["$__r"]=1; done
    unset __r
    # Also count scratchpads from THIS pipeline as researched:
    for f in .zskills/research-staging/"$PIPELINE_ID"/issue-*.md; do
      [ -f "$f" ] || continue
      N=$(basename "$f" .md | sed 's/^issue-//')
      RESEARCHED_SET["$N"]=1
    done
    unset f N
    if [ -z "${RESEARCHED_SET[$ISSUE_NUM]:-}" ]; then
      echo "fix-issues Phase 3: research-on-demand did not produce a scratchpad for #$ISSUE_NUM — skipping." >&2
      SKIP_RECORD+=("research-failed:$ISSUE_NUM")
      continue
    fi
  fi

  # 2. Narratively classify per the 7-bucket rubric (see "Triage" section
  # above). Orchestrator reads the issue body + tracker blurb and selects
  # ONE of: actionable-in-batch, actionable-do-pr, plan-scale,
  # bug-unclear-cause, needs-decision, deferred,
  # too-vague, author-decision. Skip buckets do NOT count toward N.
  # CLASS is computed inline-narratively (no helper script):
  #   CLASS="actionable-in-batch" | "actionable-do-pr"
  #       | "plan-scale" | "bug-unclear-cause" | "needs-decision"
  #       | "deferred" | "too-vague" | "author-decision"
  case "$CLASS" in
    actionable-in-batch|actionable-do-pr) ;;
    plan-scale|bug-unclear-cause|needs-decision|deferred|too-vague|author-decision)
      # PR-2 / A+F write-back: rewrite the scratchpad's `**Action now:**`
      # line to the canonical skip-value BEFORE promotion + commit, so the
      # next fire's filter-script SKIP_TAGGED output picks up this
      # classification and Phase 2 A drops the candidate without re-research
      # (#606 tax fix). `too-vague` is intentionally left untouched (no
      # canonical dashboard skip-code; vague rows need user clarification,
      # not auto-tagging — re-classified next fire by design).
      #
      # #808 — persistent skip-state in monitor-state.json. The scratchpad
      # write-back ONLY persists the decision when a tracker row lands
      # (research blurb existed). For the raw dashboard-drag case (#803:
      # issue dragged to Ready with no prior research, declined plan-scale
      # before any blurb existed) there is no scratchpad → no row write →
      # the next fire re-litigates the same decline indefinitely. Record
      # the decline in monitor-state.json (gitignored, symmetric with
      # `issues.reconsider`) so the filter drops the candidate next fire
      # regardless of tracker-row presence. `too-vague` is excluded — vague
      # rows need user clarification, not auto-tagging (kept for the next
      # fire so the user can see and act). `author-decision` is aliased to
      # `needs-decision` (the filter's canonical code).
      MONITOR_SKIP_CODE=""
      case "$CLASS" in
        plan-scale)         MONITOR_SKIP_CODE="plan-scale" ;;
        bug-unclear-cause)  MONITOR_SKIP_CODE="bug-unclear-cause" ;;
        needs-decision|author-decision) MONITOR_SKIP_CODE="needs-decision" ;;
        deferred)           MONITOR_SKIP_CODE="deferred" ;;
        too-vague)          : ;;  # do not persist; re-triage next fire
      esac
      if [ -n "$MONITOR_SKIP_CODE" ]; then
        ZSKILLS_MAIN_ROOT="$MAIN_ROOT" bash \
          "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/record-skip.sh" \
          "$ISSUE_NUM" "$MONITOR_SKIP_CODE" \
          || echo "WARN: fix-issues: record-skip.sh failed for #$ISSUE_NUM ($MONITOR_SKIP_CODE) — next fire may re-litigate" >&2
      fi

      SCRATCH=".zskills/research-staging/$PIPELINE_ID/issue-${ISSUE_NUM}.md"
      if [ -f "$SCRATCH" ]; then
        NEW_ACTION_NOW=""
        case "$CLASS" in
          plan-scale)
            NEW_ACTION_NOW="**Action now:** /draft-plan — plan-scale design surface; needs adversarial plan review before any fix."
            ;;
          bug-unclear-cause)
            NEW_ACTION_NOW="**Action now:** /investigate — root cause unclear; needs structured investigation before patching."
            ;;
          needs-decision|author-decision)
            NEW_ACTION_NOW="**Action now:** none — author decision needed on direction; not auto-fixable."
            ;;
          deferred)
            NEW_ACTION_NOW="**Action now:** none — deferred; no action needed now."
            ;;
          too-vague)
            : ;;  # leave scratchpad untouched
        esac
        if [ -n "$NEW_ACTION_NOW" ]; then
          # Replace the entire `**Action now:** ...` line content. Line-anchored
          # sed regex (period `.` is fine here because `sed` is line-mode by
          # default; we use `[^\n]*` semantics via the explicit charclass to be
          # clear about intent). Replacing the whole line drops any trailing
          # research-agent rationale that would otherwise be semantically
          # attached to the new canonical directive.
          sed -i "s|\*\*Action now:\*\*[^\n]*|$NEW_ACTION_NOW|" "$SCRATCH" \
            || echo "WARN: fix-issues write-back: sed rewrite failed for $SCRATCH (proceeding with original scratchpad content)" >&2
        fi
        {
          echo ""
          cat "$SCRATCH"
        } >> "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
        git add "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
        git commit -m "fix-issues: research blurb + skip-class triage (${CLASS}) for #${ISSUE_NUM}"
        rm -f "$SCRATCH"
      fi
      SKIP_RECORD+=("$CLASS:$ISSUE_NUM")
      continue
      ;;
    *)
      echo "fix-issues Phase 3: unrecognised triage class '$CLASS' for #$ISSUE_NUM — aborting sprint." >&2
      exit 1
      ;;
  esac

  # 3. Acquire a single-host atomic claim BEFORE materialising the
  # worktree. On race-loss (exit 10), record skip and advance to next
  # candidate (B-proper: the loop visibly continues; no `exit 0` arm).
  # On filesystem error (exit 11+), abort the sprint. The PreToolUse
  # backstop hook (block-fix-issue-unclaimed.sh) denies the
  # create-worktree.sh call below if no matching claim exists, so
  # omitting this acquire fails closed at runtime.
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" \
       --pipeline-id "$PIPELINE_ID" --sprint-id "$SPRINT_ID"
  ACQ_RC=$?
  if [ "$ACQ_RC" = 10 ]; then
    echo "fix-issues: claim race lost for issue $ISSUE_NUM (concurrent pipeline holds it); advancing to next candidate." >&2
    rm -f ".zskills/research-staging/$PIPELINE_ID/issue-${ISSUE_NUM}.md"
    SKIP_RECORD+=("race-lost:$ISSUE_NUM")
    continue
  fi
  if [ "$ACQ_RC" != 0 ]; then
    echo "fix-issues: claim acquire failed for issue $ISSUE_NUM (rc=$ACQ_RC); aborting sprint." >&2
    exit "$ACQ_RC"
  fi

  # 3b. Final GitHub-state guard (race-condition defense). The issue may
  # have been auto-closed by a sibling PR merge between the Ready-queue
  # read and this dispatch. Check live state; if CLOSED, release the
  # claim and skip — don't waste a worktree + agent cycle.
  LIVE_STATE=$(gh issue view "$ISSUE_NUM" --json state -q .state 2>/dev/null || echo "UNKNOWN")
  if [ "$LIVE_STATE" = "CLOSED" ]; then
    echo "fix-issues: issue #$ISSUE_NUM is CLOSED on GitHub (race — closed after Ready-queue read); releasing claim and skipping." >&2
    bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
    SKIP_RECORD+=("closed-on-github:$ISSUE_NUM")
    continue
  fi

  # 4. Materialise worktree + dispatch impl agent.
  WORKTREE_PATH="/tmp/$(basename "$MAIN_ROOT")-fix-issue-${ISSUE_NUM}"
  if [ -d "$WORKTREE_PATH" ]; then
    # Resume detection stays directory-based: an existing fix worktree
    # means we're resuming the same issue across cron turns.
    echo "Resuming existing fix worktree at $WORKTREE_PATH"
  else
    WORKTREE_PATH=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
      --prefix fix-issue \
      --purpose "fix-issues; issue=${ISSUE_NUM}" \
      --pipeline-id "$PIPELINE_ID" \
      "${ISSUE_NUM}")
    RC=$?
    if [ "$RC" -ne 0 ]; then
      # W2.5.5 — release the just-acquired claim before sprint-abort so
      # it doesn't leak. Only THIS issue's claim is in-flight
      # at this moment (earlier iterations' agents are running with
      # their own claims correctly held; later iterations haven't been
      # acquired yet). `|| true` because release-after-failure is
      # best-effort cleanup.
      bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
      echo "create-worktree failed (rc=$RC) for /fix-issues cherry-pick/direct mode (issue $ISSUE_NUM); released claim before abort" >&2
      exit "$RC"
    fi
  fi
  # create-worktree.sh owns pre-flight prune+fetch+ff-merge, the
  # underlying safe add, .zskills-tracked (from --pipeline-id), and
  # .worktreepurpose writes. The orchestrator does NOT separately write
  # the tracking marker — the worktree directory does not exist until
  # create-worktree.sh materialises it, so any pre-dispatch write would
  # fail.

  # Promote scratchpad row into the per-issue worktree's tracker file. This
  # commit is orchestrator-owned (not the impl agent's) so the row lands even
  # if the impl agent returns without a commit (e.g., no-op verifier failure).
  SCRATCH=".zskills/research-staging/$PIPELINE_ID/issue-${ISSUE_NUM}.md"
  if [ -f "$SCRATCH" ]; then
    (
      cd "$WORKTREE_PATH"
      {
        echo ""
        cat "$MAIN_ROOT/$SCRATCH"
      } >> "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
      git add "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
      git commit -m "fix-issues: backfill research blurb for #${ISSUE_NUM}"
    )
    rm -f "$SCRATCH"
  fi

  # Orchestrator action: Agent dispatch for issue $ISSUE_NUM with
  # `subagent_type: "implementer"`, prompt prefixed with
  # `FIRST: cd $WORKTREE_PATH`, body per the "Agent dispatch prompts
  # MUST include" rules above (verbatim issue body, tracker blurb,
  # Tier-1 hash-registration directive).
  DISPATCHED=$((DISPATCHED + 1))
done

# Post-loop: promote leftover scratchpads for ranked-but-not-iterated
# candidates (CANDIDATE_ISSUES that sat past N — research investment is
# preserved so the next cron fire's filter sees committed rows for them).
# Only runs in cherry-pick/direct mode; PR-mode leftovers are deferred to
# PR 2 (see PR-mode loop carve-out below).
declare -a LEFTOVER_ROWS=()
for N in "${CANDIDATE_ISSUES[@]}"; do
  SCRATCH=".zskills/research-staging/$PIPELINE_ID/issue-${N}.md"
  [ -f "$SCRATCH" ] || continue
  {
    echo ""
    cat "$SCRATCH"
  } >> "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
  LEFTOVER_ROWS+=("$N")
  rm -f "$SCRATCH"
done
if [ "${#LEFTOVER_ROWS[@]}" -gt 0 ]; then
  git add "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
  git commit -m "fix-issues: backfill research blurbs for ranked-but-not-iterated candidates (sprint ${SPRINT_ID}) — issues ${LEFTOVER_ROWS[*]}"
fi
unset N SCRATCH LEFTOVER_ROWS
```

For grouped interrelated issues (same root cause or same files from
Phase 2 grouping), pass the **lowest issue number** as the slug — all
grouped issues share that one worktree. Mirrors the PR-mode convention.

**Dispatching fix agents in cherry-pick/direct mode:** Dispatch agents
WITHOUT `isolation: "worktree"` — the worktree already exists. The agent
prompt must include `FIRST: cd $WORKTREE_PATH` as the mandatory first
action. Without this instruction, the agent starts in the main repo.

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "implementer"`.
This inherits the Layer 0 Bash-timeout extension (see
`.claude/agents/implementer.md` + the "Verifier-cannot-run rule" section in
CLAUDE.md) so the fix agent's Bash calls to run long test suites don't
trigger the bg+Monitor stall pattern.

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

**Per-issue dispatch loop (B-proper, PR mode).** Same shape as the
cherry-pick/direct loop above — iterate `CANDIDATE_ISSUES`, advance on
research-failed / triage-skip / race-lost, bound by `DISPATCHED < N`.
The only PR-mode-specific divergence is the `create-worktree.sh`
invocation (passes `--branch-name fix/issue-NNN --allow-resume`) so
each issue gets its own named branch + worktree (one PR per issue,
unlike `/run-plan` PR mode where all phases share one branch). See the
cherry-pick/direct subsection above for the rationale (B-proper
structural change replacing the older PROSE-iterated `exit 0`
race-loss arm).

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])ISSUES_PLAN\.md reason: filename basename suffixed onto $ZSKILLS_ISSUES_DIR (resolved via zskills-paths.sh); the basename token remains literal so the regex still flags the /ISSUES_PLAN.md tail -->
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PROJECT_NAME=$(basename "$PROJECT_ROOT")

DISPATCHED=0
declare -a SKIP_RECORD=()   # appended as "<bucket>:<issue_num>" tokens.

for ISSUE_NUM in "${CANDIDATE_ISSUES[@]}"; do
  [ "$DISPATCHED" -ge "$N" ] && break

  # 1. Research-on-demand (same shape as cherry-pick/direct loop above).
  if [ -z "${RESEARCHED_SET[$ISSUE_NUM]:-}" ]; then
    # Orchestrator dispatches `subagent_type: "general-purpose"`
    # research agent for $ISSUE_NUM. Blocks until the agent writes the
    # row content to `.zskills/research-staging/$PIPELINE_ID/issue-${N}.md`
    # (no commit). Then refresh RESEARCHED_SET by unioning filter-RESEARCHED
    # with the scratchpad-existence check.
    eval "$(ZSKILLS_ISSUES_DIR="$ZSKILLS_ISSUES_DIR" \
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/filter-unresearched-candidates.sh" \
      "${CANDIDATE_ISSUES[@]}")"
    read -r -a RESEARCHED_ARR <<<"${RESEARCHED:-}"
    RESEARCHED_SET=()
    for __r in "${RESEARCHED_ARR[@]}"; do RESEARCHED_SET["$__r"]=1; done
    unset __r
    # Also count scratchpads from THIS pipeline as researched:
    for f in .zskills/research-staging/"$PIPELINE_ID"/issue-*.md; do
      [ -f "$f" ] || continue
      N=$(basename "$f" .md | sed 's/^issue-//')
      RESEARCHED_SET["$N"]=1
    done
    unset f N
    if [ -z "${RESEARCHED_SET[$ISSUE_NUM]:-}" ]; then
      echo "fix-issues Phase 3 (PR mode): research-on-demand did not produce a scratchpad for #$ISSUE_NUM — skipping." >&2
      SKIP_RECORD+=("research-failed:$ISSUE_NUM")
      continue
    fi
  fi

  # 2. Narrative triage classification — see "Triage" section above.
  # CLASS computed inline by the orchestrator.
  case "$CLASS" in
    actionable-in-batch|actionable-do-pr) ;;
    plan-scale|bug-unclear-cause|needs-decision|deferred|too-vague|author-decision)
      # PR-2 / A+F write-back: rewrite the scratchpad's `**Action now:**`
      # line NOW so when the end-of-Phase-3 sync-PR ships these rows they
      # carry the canonical skip-tag. main_protected blocks direct commit
      # here — the scratchpad is held in `.zskills/research-staging/` for
      # the end-of-loop batch sync-PR that mirrors the dashboard-empty
      # pattern at SKILL.md ~1303-1378.
      #
      # #808 — persistent skip-state in monitor-state.json. Symmetric with
      # the cherry-pick-mode write-back above: record the decline in
      # `monitor-state.json` (gitignored) so the next fire's filter drops
      # the candidate BEFORE re-triage, even when the issue has no
      # tracker row (raw dashboard-drag case — #803). `too-vague` is
      # intentionally excluded (vague rows need user clarification, not
      # auto-tagging); `author-decision` is aliased to `needs-decision`
      # (the filter's canonical code).
      MONITOR_SKIP_CODE=""
      case "$CLASS" in
        plan-scale)         MONITOR_SKIP_CODE="plan-scale" ;;
        bug-unclear-cause)  MONITOR_SKIP_CODE="bug-unclear-cause" ;;
        needs-decision|author-decision) MONITOR_SKIP_CODE="needs-decision" ;;
        deferred)           MONITOR_SKIP_CODE="deferred" ;;
        too-vague)          : ;;  # do not persist; re-triage next fire
      esac
      if [ -n "$MONITOR_SKIP_CODE" ]; then
        ZSKILLS_MAIN_ROOT="$MAIN_ROOT" bash \
          "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/record-skip.sh" \
          "$ISSUE_NUM" "$MONITOR_SKIP_CODE" \
          || echo "WARN: fix-issues PR-mode: record-skip.sh failed for #$ISSUE_NUM ($MONITOR_SKIP_CODE) — next fire may re-litigate" >&2
      fi

      SCRATCH=".zskills/research-staging/$PIPELINE_ID/issue-${ISSUE_NUM}.md"
      if [ -f "$SCRATCH" ]; then
        NEW_ACTION_NOW=""
        case "$CLASS" in
          plan-scale)
            NEW_ACTION_NOW="**Action now:** /draft-plan — plan-scale design surface; needs adversarial plan review before any fix."
            ;;
          bug-unclear-cause)
            NEW_ACTION_NOW="**Action now:** /investigate — root cause unclear; needs structured investigation before patching."
            ;;
          needs-decision|author-decision)
            NEW_ACTION_NOW="**Action now:** none — author decision needed on direction; not auto-fixable."
            ;;
          deferred)
            NEW_ACTION_NOW="**Action now:** none — deferred; no action needed now."
            ;;
          too-vague)
            : ;;  # leave scratchpad untouched
        esac
        if [ -n "$NEW_ACTION_NOW" ]; then
          sed -i "s|\*\*Action now:\*\*[^\n]*|$NEW_ACTION_NOW|" "$SCRATCH" \
            || echo "WARN: fix-issues PR-mode write-back: sed rewrite failed for $SCRATCH" >&2
        fi
      fi
      SKIP_RECORD+=("$CLASS:$ISSUE_NUM")
      continue
      ;;
    *)
      echo "fix-issues Phase 3 (PR mode): unrecognised triage class '$CLASS' for #$ISSUE_NUM — aborting sprint." >&2
      exit 1
      ;;
  esac

  # 3. Acquire single-host atomic claim. On race-loss (exit 10), advance
  # to next candidate (B-proper: visible `continue`, no `exit 0`). On
  # filesystem error (exit 11+), abort sprint.
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" \
       --pipeline-id "$PIPELINE_ID" --sprint-id "$SPRINT_ID"
  ACQ_RC=$?
  if [ "$ACQ_RC" = 10 ]; then
    echo "fix-issues: claim race lost for issue $ISSUE_NUM (concurrent pipeline holds it); advancing to next candidate." >&2
    rm -f ".zskills/research-staging/$PIPELINE_ID/issue-${ISSUE_NUM}.md"
    SKIP_RECORD+=("race-lost:$ISSUE_NUM")
    continue
  fi
  if [ "$ACQ_RC" != 0 ]; then
    echo "fix-issues: claim acquire failed for issue $ISSUE_NUM (rc=$ACQ_RC); aborting sprint." >&2
    exit "$ACQ_RC"
  fi

  # 3b. Final GitHub-state guard (race-condition defense). The issue may
  # have been auto-closed by a sibling PR merge between the Ready-queue
  # read and this dispatch. Check live state; if CLOSED, release the
  # claim and skip — don't waste a worktree + agent cycle.
  LIVE_STATE=$(gh issue view "$ISSUE_NUM" --json state -q .state 2>/dev/null || echo "UNKNOWN")
  if [ "$LIVE_STATE" = "CLOSED" ]; then
    echo "fix-issues: issue #$ISSUE_NUM is CLOSED on GitHub (race — closed after Ready-queue read); releasing claim and skipping." >&2
    bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
    SKIP_RECORD+=("closed-on-github:$ISSUE_NUM")
    continue
  fi

  # 4. Materialise per-issue PR-mode worktree.
  BRANCH_NAME="fix/issue-${ISSUE_NUM}"
  WORKTREE_PATH="/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}"
  # Resume detection stays directory-based (R2-M1): an existing fix
  # worktree means we're resuming the same issue across cron turns.
  if [ -d "$WORKTREE_PATH" ]; then
    echo "Resuming existing fix worktree at $WORKTREE_PATH"
  else
    WORKTREE_PATH=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
      --prefix fix-issue \
      --branch-name "$BRANCH_NAME" \
      --allow-resume \
      --purpose "fix-issues; issue=${ISSUE_NUM}" \
      --pipeline-id "$PIPELINE_ID" \
      "${ISSUE_NUM}")
    RC=$?
    if [ "$RC" -ne 0 ]; then
      # W2.5.5 — release just-acquired claim before sprint-abort.
      bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true
      echo "create-worktree failed (rc=$RC) for /fix-issues PR mode (issue $ISSUE_NUM); released claim before abort" >&2
      exit "$RC"
    fi
  fi
  # create-worktree.sh owns pre-flight prune+fetch+ff-merge, the
  # underlying safe add (with ZSKILLS_ALLOW_BRANCH_RESUME=1 set via
  # --allow-resume), .zskills-tracked (from --pipeline-id), and
  # .worktreepurpose writes.

  # Promote scratchpad row into the per-issue worktree's tracker file. This
  # commit is orchestrator-owned (not the impl agent's) so the row lands even
  # if the impl agent returns without a commit (e.g., no-op verifier failure).
  # PR-mode `$WORKTREE_PATH` is `/tmp/${PROJECT_NAME}-fix-issue-${ISSUE_NUM}`
  # on a `fix/issue-${ISSUE_NUM}` branch — the standalone worktree commit
  # lands there and ships with the fix PR.
  SCRATCH=".zskills/research-staging/$PIPELINE_ID/issue-${ISSUE_NUM}.md"
  if [ -f "$SCRATCH" ]; then
    (
      cd "$WORKTREE_PATH"
      {
        echo ""
        cat "$MAIN_ROOT/$SCRATCH"
      } >> "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
      git add "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
      git commit -m "fix-issues: backfill research blurb for #${ISSUE_NUM}"
    )
    rm -f "$SCRATCH"
  fi

  # Orchestrator action: Agent dispatch for issue $ISSUE_NUM with
  # `subagent_type: "implementer"`, prompt prefixed with
  # `FIRST: cd $WORKTREE_PATH`. PR mode: each branch's PR is opened in
  # Phase 6 via `/land-pr` (per-issue).
  DISPATCHED=$((DISPATCHED + 1))
done

# PR-2 / A+F: end-of-PR-mode-Phase-3 sprint-tracker rollup. Collect any
# remaining scratchpads in `.zskills/research-staging/$PIPELINE_ID/`
# (skip-class write-back from triage above, plus any
# ranked-but-not-iterated leftovers — PR mode held both intentionally so
# the canonical skip-tag rewrite ships in ISSUES_PLAN.md). If non-empty,
# ship as a tracker-only sync PR via the dashboard-empty pattern at
# SKILL.md ~1283-1378. The sync-PR ALWAYS auto-merges regardless of the
# user's `auto` arg — tracker-only content has no code-review surface;
# review gates apply to code PRs only (same rationale as the
# dashboard-empty sync at lines 1338-1341).
declare -a TRACKER_SCRATCHPADS=()
for N in "${CANDIDATE_ISSUES[@]+"${CANDIDATE_ISSUES[@]}"}"; do
  S=".zskills/research-staging/$PIPELINE_ID/issue-${N}.md"
  [ -f "$S" ] && TRACKER_SCRATCHPADS+=("$S")
done
unset N S

if [ "${#TRACKER_SCRATCHPADS[@]}" -gt 0 ]; then
  echo "fix-issues PR-mode: shipping ${#TRACKER_SCRATCHPADS[@]} skip-tag / leftover row(s) as sprint-tracker PR" >&2
  TRACKER_WT=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
    --prefix tracker \
    --branch-name "fix-issues-tracker/$SPRINT_ID" \
    --purpose "fix-issues sprint-tracker skip-tag rollup" \
    --pipeline-id "$PIPELINE_ID" \
    "$SPRINT_ID")
  TRACKER_RC=$?
  if [ "$TRACKER_RC" -ne 0 ]; then
    echo "fix-issues PR-mode: tracker worktree creation failed (rc=$TRACKER_RC); scratchpads retained for next fire" >&2
  else
    (
      cd "$TRACKER_WT" || exit 1
      for S in "${TRACKER_SCRATCHPADS[@]}"; do
        {
          echo ""
          cat "$MAIN_ROOT/$S"
        } >> "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
      done
      git add "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
      if [ -n "${COMMIT_CO_AUTHOR:-}" ]; then
        git commit --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" \
          -m "docs(sync): /fix-issues skip-tag rollup sprint $SPRINT_ID"
      else
        git commit -m "docs(sync): /fix-issues skip-tag rollup sprint $SPRINT_ID"
      fi
    )
    # Dispatch /land-pr --auto for the tracker PR. Mirrors the
    # dashboard-empty pattern's LAND_ARGS shape (always --auto because
    # this is sync-only content with no code-review surface).
    TRACKER_LAND_ID="fix-issues.tracker-rollup.${SPRINT_ID}"
    TRACKER_RESULT=$(mktemp)
    TRACKER_BODY=$(mktemp)
    {
      printf '## Summary\n`/fix-issues` PR-mode sprint %s: %d skip-tag / leftover row(s) shipped as tracker-only sync.\n\n' \
        "$SPRINT_ID" "${#TRACKER_SCRATCHPADS[@]}"
      printf '## Test plan\n- [x] Tracker-only diff; no per-issue work in this PR.\n'
    } > "$TRACKER_BODY"
    [ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
    mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
    printf 'skill: land-pr\nrequired-by: fix-issues-pr-mode-tracker-rollup\ndate: %s\n' \
      "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
      > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${TRACKER_LAND_ID}"
    TRACKER_LAND_ARGS="--branch=fix-issues-tracker/$SPRINT_ID --title=\"sync: /fix-issues skip-tag rollup sprint $SPRINT_ID\" --body-file=$TRACKER_BODY --result-file=$TRACKER_RESULT --landed-source=fix-issues-pr-mode-tracker-rollup --worktree-path=$TRACKER_WT --tracking-id=$TRACKER_LAND_ID --auto"
    echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"
    # Skill: { skill: "land-pr", args: "$TRACKER_LAND_ARGS" }
    # (Allow-list parser handles result file; mirrors dashboard-empty pattern.)
    # On success, remove the scratchpads. On failure, retain for next fire.
    if [ -f "$TRACKER_RESULT" ]; then
      while IFS='=' read -r K V; do
        if [ "$K" = "STATUS" ] && [ "$V" = "merged" ]; then
          for S in "${TRACKER_SCRATCHPADS[@]}"; do rm -f "$S"; done
          printf 'skill: land-pr\nid: %s\npr: -\nbranch: fix-issues-tracker/%s\ndate: %s\n' \
            "$TRACKER_LAND_ID" "$SPRINT_ID" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
            > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$TRACKER_LAND_ID"
        fi
      done < "$TRACKER_RESULT"
    fi
    rm -f "$TRACKER_RESULT" "$TRACKER_BODY"
  fi
fi
unset TRACKER_SCRATCHPADS TRACKER_WT TRACKER_RC S
```

**Dispatching fix agents in PR mode:** Dispatch agents WITHOUT
`isolation: "worktree"` — the worktree already exists. The agent prompt
must include `FIRST: cd $WORKTREE_PATH` as the mandatory first action.
Without this instruction, the agent starts in the main repo.

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "implementer"`.
This inherits the Layer 0 Bash-timeout extension (see
`.claude/agents/implementer.md` + the "Verifier-cannot-run rule" section in
CLAUDE.md) so the fix agent's Bash calls to run long test suites don't
trigger the bg+Monitor stall pattern.

For grouped interrelated issues (same root cause or same files from
Phase 2 grouping), pick the LOWEST issue number as the branch identifier
(`fix/issue-NNN`) and include all grouped issues in that one worktree.
The `.landed` marker's `issue:` field records the primary issue; group
members are listed separately in the sprint report.

### Post-execute tracking

After Phase 3 (execute) is complete — all agents have returned:
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
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
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
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
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.verify"
```

## Phase 5 — Write Sprint Report (BEFORE landing)

**APPEND** a new sprint section to `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md` BEFORE Phase 6
(landing). The report is a prerequisite for landing — if it's not written,
Phase 6 does not execute.

**The Sprint worktree gate at Phase 1 already `cd`-ed into the sprint
worktree and exported `ZSKILLS_PATHS_ROOT`.** Under
`execution.main_protected: true`, this append lands inside the sprint
worktree's `.zskills/audit/SPRINT_REPORT.md` — not on main. Phase 6
ships it via a sprint-level `/land-pr` dispatch after the per-issue
landing loop completes. Under `main_protected: false`, the gate
no-ops and the append lands on main as before (preserves the
pre-#325 behaviour for unprotected repos).

**APPEND, do not overwrite.** Multiple sprints may run between `/fix-report`
reviews (e.g., cron every 2h, user checks once a day). Each sprint adds a
new `## Sprint — YYYY-MM-DD HH:MM [UNFINALIZED]` section. `/fix-report`
processes all UNFINALIZED sections when the user reviews.

If the file doesn't exist, create it with a `# Sprint Report` heading.

Past failure: an agent skipped Phase 5 for 8 consecutive sprints to "keep
the hourly cadence fast." `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md` was stale for 8 sprints,
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

### Post-report tracking

After Phase 5 (report) is complete:
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
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

**Auto-flag gating depends on landing mode.** This block governs the
`--auto` (auto-merge) pass-through to `/land-pr` per landing mode.
Without `auto`:

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
  > Sprint complete. Report written to `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`.
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

### Sprint-level SPRINT_REPORT.md landing (after per-issue loop)

When the Sprint worktree gate at Phase 1 created a worktree (i.e.
`$WT_PATH` is non-empty — `execution.main_protected: true`), Phase 5
wrote `SPRINT_REPORT.md` inside that worktree. After all per-issue
landing dispatches (cherry-pick / direct / PR mode) have completed,
ship the SPRINT_REPORT.md commit via a dedicated sprint-level
`/land-pr`. Mirrors sync mode Step 5's `/land-pr` dispatch
(`skills/fix-issues/SKILL.md` `## Sync` Step 5) — one commit, one PR,
one tracking pair on `$MAIN_ROOT`. Skipped under `main_protected:
false` (gate no-op'd; SPRINT_REPORT.md is already on main and Phase
6's per-issue cherry-picks include it transitively via `/fix-report`).

**cwd discipline for sprint-land scripts (orchestrator-side, lived #472).**
Two recurring failure modes have surfaced when the orchestrator
constructs ad-hoc sprint-land reconstruction scripts (e.g. when the
fence below is paraphrased into a one-off bash invocation):

1. **Double-`sprint-` prefix.** `$SPRINT_ID` is constructed as
   `sprint-YYYYMMDD-HHMMSS-<slug>` at the top of this skill (see line
   `SPRINT_ID="sprint-$(date ...)-$ISSUE_TITLE_SLUG"`) — it ALREADY
   carries the literal `sprint-` prefix. Do NOT add another `sprint-`
   when reconstructing the worktree path: the worktree directory is
   `/tmp/<basename>-fix-issues-${SPRINT_ID}`, NOT
   `/tmp/<basename>-fix-issues-sprint-${SPRINT_ID}` (would yield
   `/tmp/<basename>-fix-issues-sprint-sprint-YYYYMMDD-...`, a path that
   doesn't exist). The canonical recovery is `WT_PATH=$(git worktree
   list --porcelain | awk -v id="$SPRINT_ID" '...')` — query, don't
   reconstruct. Any `cd "$RECONSTRUCTED_PATH"` MUST be followed by
   `|| { echo "cd failed" >&2; exit 1; }` so silent-cd-to-main is
   impossible.

2. **Leading `cd /workspaces/<project>` collides with
   `extract_cd_target`.** The `block-unsafe-project.sh` hook's
   `extract_cd_target` helper picks the FIRST `cd` target in a shell
   chain to determine the operating worktree (used to decide whether
   the call is gated as "on main"). A pipeline that leads with
   `cd /workspaces/zskills && ... && cd $WT_PATH && git commit ...`
   resolves to MAIN, and the hook blocks the commit. Two acceptable
   patterns to avoid the collision:

   - **Use `git -C <wt> ...` for all main-AND-worktree mixed
     operations.** The fence below uses `git -C "$TOPLEVEL"` for every
     git op after the one `cd "$WT_PATH"` re-anchor. No subsequent
     `cd` to main is needed.
   - **If you must reference main, use a subshell:**
     `( cd /workspaces/zskills && git ... )` so the outer chain's
     `cd` target remains the worktree.

   NEVER lead a sprint-land bash invocation with `cd /workspaces/<project>`
   before a later `cd $WT_PATH && git push|commit`. The hook will see
   main as the operating root and block the call.

The fence below already follows both rules — it `cd`s into `$WT_PATH`
once (with `|| exit`), then uses `git -C "$TOPLEVEL"` for the rest.
Mirror this shape in any orchestrator-side recovery scripts.

<!-- allow-hardcoded: (^|[^A-Za-z0-9_])SPRINT_REPORT\.md reason: filename basename suffixed onto $ZSKILLS_AUDIT_DIR (resolved via zskills-paths.sh); the basename token itself remains literal so the regex still flags the /SPRINT_REPORT.md tail; mirrors the sync-mode Step 5 fence at the top of the same skill -->
```bash
if [ -n "${WT_PATH:-}" ]; then
  # Re-anchor in case any per-issue dispatch cd'd away.
  cd "$WT_PATH" || { echo "fix-issues: cd $WT_PATH failed (sprint-land)" >&2; exit 1; }
  export ZSKILLS_PATHS_ROOT="$WT_PATH"
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  fi

  TOPLEVEL=$(git rev-parse --show-toplevel)
  MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)

  # Stage + commit SPRINT_REPORT.md if Phase 5 wrote anything.
  ABS_FILE="$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md"
  SPRINT_REL=""
  if SPRINT_REL=$(realpath --relative-to="$TOPLEVEL" "$ABS_FILE" 2>/dev/null) \
       && [ -n "$SPRINT_REL" ]; then
    case "$SPRINT_REL" in /*) SPRINT_REL="" ;; esac
  fi
  if [ -z "$SPRINT_REL" ]; then
    ABS_FILE_CANON=$(cd "$(dirname "$ABS_FILE")" 2>/dev/null && pwd)/$(basename "$ABS_FILE")
    case "$ABS_FILE_CANON" in
      "$TOPLEVEL"/*) SPRINT_REL="${ABS_FILE_CANON#"$TOPLEVEL"/}" ;;
      *) echo "fix-issues: cannot normalize $ABS_FILE vs $TOPLEVEL (sprint-land)" >&2; exit 1 ;;
    esac
  fi
  case "$SPRINT_REL" in
    /*|../*) echo "fix-issues: $ABS_FILE is outside worktree $TOPLEVEL (sprint-land)" >&2; exit 1 ;;
  esac

  git -C "$TOPLEVEL" add "$SPRINT_REL"
  STAGED=$(git -C "$TOPLEVEL" diff --cached --name-only)
  if [ -z "$STAGED" ]; then
    echo "fix-issues: nothing to commit at sprint-land (no SPRINT_REPORT.md changes)" >&2
  else
    if [ -n "$COMMIT_CO_AUTHOR" ]; then
      git -C "$TOPLEVEL" commit --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" \
        -m "docs(sprint-report): sprint $SPRINT_ID results"
    else
      git -C "$TOPLEVEL" commit -m "docs(sprint-report): sprint $SPRINT_ID results"
    fi

    # Dispatch /land-pr for the sprint-level SPRINT_REPORT.md commit.
    # Mirrors sync mode's /land-pr arg vector at $TOPLEVEL.
    SPRINT_LAND_ID="fix-issues.sprint.${SPRINT_ID}"
    [ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
    mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
    printf 'skill: land-pr\nrequired-by: fix-issues-sprint\ndate: %s\n' \
      "$(TZ=UTC date -Iseconds)" \
      > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${SPRINT_LAND_ID}"

    RESULT_FILE=$(mktemp)
    BODY_FILE=$(mktemp)
    {
      printf '## Summary\n`/fix-issues` sprint %s.\n\n' "$SPRINT_ID"
      printf '## Test plan\n- [x] Sprint report content reviewed by user before merge.\n'
    } > "$BODY_FILE"

    PR_TITLE="sprint-report: $SPRINT_ID"
    SPRINT_BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)
    LAND_ARGS="--branch=$SPRINT_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sprint --worktree-path=$TOPLEVEL --tracking-id=$SPRINT_LAND_ID"
    [ "${AUTO:-false}" = "true" ] && LAND_ARGS="$LAND_ARGS --auto"

    echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"

    # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

    if [ ! -f "$RESULT_FILE" ]; then
      echo "ERROR: /land-pr (sprint-land) produced no result file at $RESULT_FILE" >&2
    else
      declare -A LP_SPRINT
      while IFS='=' read -r KEY VALUE; do
        case "$KEY" in
          STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
          MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
          CONFLICT_FILES_LIST|CALL_ERROR_FILE)
            LP_SPRINT["$KEY"]="$VALUE" ;;
          "") ;;
          *) printf 'WARN: /land-pr (sprint-land) result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
        esac
      done < "$RESULT_FILE"
      case "${LP_SPRINT[STATUS]:-}" in
        merged)
          printf 'skill: land-pr\nid: %s\npr: %s\nbranch: %s\ndate: %s\n' \
            "$SPRINT_LAND_ID" "${LP_SPRINT[PR_URL]:-}" "$SPRINT_BRANCH" \
            "$(TZ=UTC date -Iseconds)" \
            > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.land-pr.$SPRINT_LAND_ID"
          ;;
        *)
          echo "fix-issues sprint-land: /land-pr STATUS=${LP_SPRINT[STATUS]:-unknown} — sprint report PR left open" >&2
          ;;
      esac
    fi
  fi
fi
```

### Post-land tracking

After Phase 6 (land) is complete:
```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.fix-issues.$SPRINT_ID.land"
```

After the sprint completes (whether all issues landed or the sprint ended),
clean up the sentinel:

```bash
rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/pipeline.fix-issues.$SPRINT_ID"

# Issue #877 — clear the shared in-flight sentinel so the next cron
# fire is free to pick up fresh work.
INFLIGHT_HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/check-inflight-batch.sh"
if [ -x "$INFLIGHT_HELPER" ]; then
  bash "$INFLIGHT_HELPER" clear fix-issues --pipeline-id "$PIPELINE_ID" || true
fi
```

Also remove `.zskills-tracked` from each worktree that was used.

## Failure Protocol

**Read [references/failure-protocol.md](references/failure-protocol.md)**
for crash handling, cron cleanup, worktree restoration, and sprint
failure reporting.

