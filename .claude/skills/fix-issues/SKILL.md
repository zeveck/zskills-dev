---
name: fix-issues
disable-model-invocation: true
argument-hint: "N [<focus>|dashboard] [auto] [every SCHEDULE] [now] | sync | plan [auto] | stop | next"
description: >-
  Orchestrate a batch bug-fixing sprint: dispatch implementers in per-issue
  worktrees, verify, optionally auto-land via /land-pr. Recurring via
  every SCHEDULE; stop/next manage it. sync updates trackers + closes
  already-fixed issues; plan drafts plans for skipped ones.
metadata:
  version: "2026.06.15+2e2c75"
---

# /fix-issues N [<focus>|dashboard] [auto] [every SCHEDULE] [now] | sync | plan [auto] | stop | next | add <N> [column] [pos] | remove <N> [column] — Batch Bug-Fixing Sprint

Orchestrates large-scale bug fixing. Syncs trackers, prioritizes issues,
dispatches agent teams in worktrees, verifies fixes, writes a persistent
report, and optionally auto-lands to main. Can self-schedule for recurring runs.

**Ultrathink throughout.** Use careful, thorough reasoning at every step.

## Arguments

```
/fix-issues N [focus|dashboard] [auto] [every SCHEDULE] [now] [pr|direct]
/fix-issues sync | plan [auto] | stop | next
/fix-issues add <N> [column] [pos]
/fix-issues remove <N> [column]
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
  - **Sprints:** skip Phase 2 issue list approval, auto-land per-issue
    fix PRs, AND auto-merge the Phase 6 sprint-report PR (its content
    describes the sprint's fix work, so it follows your `auto` choice).
    Does NOT close GH issues or remove worktrees — those are
    `/fix-report` actions.
  - **Sync-only tracker PRs always auto-merge regardless of `auto`.**
    Three dispatch sites ship sync-driven tracker updates ONLY (no fix
    work): the standalone `/fix-issues sync` PR, the sprint
    no-actionable ship branch, and the dashboard-empty ship branch.
    Those PRs contain agent-facing markdown that the agent reads back,
    not user-facing artifacts warranting human review.
  - **plan auto:** draft plans for all found issues without selection
    (see Plan section).
  - **Sync `gh issue close` step is still interactive.** `auto` does NOT
    bypass the human-approval gate on the irreversible `gh issue close`
    sub-step in standalone sync (Step 5 sub-step 3); only the tracker-PR
    auto-merge is unconditional.
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Implies `auto` — scheduling only makes sense for autonomous runs
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` needs no `every` to take
  effect — a sprint with `now` (or a standalone `now` against an active cron)
  runs immediately rather than only scheduling. (A *truly bare* `/fix-issues`
  with no N and no subcommand does NOT start a sprint — it reports cron status
  + a usage hint and exits; see the Execution path bare row.)
- **sync** — update all issue tracker files from GitHub, research new
  issues, AND verify/close issues that appear already fixed. Dispatches
  research agents that also check if open issues are already resolved in
  the codebase. Always interactive — presents findings and asks before
  closing. See Sync section for the full flow.
- **plan** — draft plans for issues previously skipped as "too complex."
  Scans `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md` for skipped items, dispatches `/draft-plan`
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
- `add` followed by a positive integer — add issue to queue column and exit
- `remove` followed by a positive integer — remove issue from queue column and exit

**Flag pre-parse — `AUTO_FLAG`** (WI 2.3). The canonical bash variable
so model-layer "Without `auto` / With `auto`" gates bind to a single
source of truth. Placement: BEFORE the first user-facing prose that
references the flag. Per D8 round-2: do NOT add an AUTO_FLAG gate to
`gh issue close` — the existing `case "${LP[STATUS]:-}" in merged) ...`
gate stays unchanged.

```bash
# Argument parsing — extract canonical flags from $ARGUMENTS.
AUTO_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
```

**Landing mode resolution** (same pattern as `/run-plan`):
1. Explicit argument wins: `pr` or `direct` in `$ARGUMENTS`
2. Config default: read `.claude/zskills-config.json` `execution.landing` field
3. Fallback: `cherry-pick`

```bash
# Detect landing mode (same logic as /run-plan)
# Resolve repo root before any config read. $PROJECT_ROOT is never exported
# into a SKILL.md fence (it is only set inside post-run-invariants.sh, a
# separate process), so anchor it on $CLAUDE_PROJECT_DIR -- the established
# peer pattern used elsewhere in this skill family (#791).
PROJECT_ROOT="${PROJECT_ROOT:-$CLAUDE_PROJECT_DIR}"
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

**Concurrent `dashboard` runs and the claim mechanism.** Two
`/fix-issues N dashboard auto` sessions launched concurrently from two
terminals (or two cron fires that overlap) read the same Ready queue
and would otherwise pick the same head-of-queue issue twice. The
`claim-issue.sh` helper at `scripts/claim-issue.sh` provides a
filesystem-anchored atomic claim per issue: each per-issue dispatch
fence calls `bash "$CLAIM_HELPER" acquire "$ISSUE_NUM"` (D2 — inline
acquire) which `mkdir`s `${MAIN_ROOT}/.zskills/claims/issue-NNN/`
atomically; exit 0 wins the claim, exit 10 means another pipeline holds
it and this fence skips to the next issue (D1 — filesystem markers).
The dashboard surfaces live claims as in-flight chips on the affected
issues so concurrent runs are visible to the operator (D6 — dashboard
chip). The PreToolUse hook `hooks/block-fix-issue-unclaimed.sh` denies
any `create-worktree.sh --prefix fix-issue NNN` invocation that lacks a
matching claim, so omitting the acquire fence fails closed at runtime.

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
  | sed -E 's/(^|[[:space:]])[dD][aA][sS][hH][bB][oO][aA][rR][dD]($|[[:space:]])/ /' \
  | sed -E 's/(^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]])/ /')
```

**Detect `add`/`remove`/`reconsider` subcommands.** These are early-exit
queue-mutation commands that modify `.zskills/monitor-state.json` and exit
— they do NOT proceed to Phase 0/1/2. Detection must happen BEFORE the
leading-N integer parser (which would misinterpret the issue number after
`add`/`remove`/`reconsider` as the sprint count). `add`, `remove`, and
`reconsider` are mutually exclusive with each other and with all other
subcommands (`sync`, `plan`, `stop`, `next`, `dashboard`).

```bash
ADD_MODE=0
REMOVE_MODE=0
RECONSIDER_MODE=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][dD][dD][[:space:]]+([0-9]+) ]]; then
  ADD_MODE=1
  ADD_ISSUE_NUM="${BASH_REMATCH[2]}"
fi
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[rR][eE][mM][oO][vV][eE][[:space:]]+([0-9]+) ]]; then
  REMOVE_MODE=1
  REMOVE_ISSUE_NUM="${BASH_REMATCH[2]}"
fi
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[rR][eE][cC][oO][nN][sS][iI][dD][eE][rR][[:space:]]+([0-9]+) ]]; then
  RECONSIDER_MODE=1
  RECONSIDER_ISSUE_NUM="${BASH_REMATCH[2]}"
fi
```

**Detect a truly-bare invocation (no N, no subcommand).** A bare
`/fix-issues` with no leading integer `N` AND none of the recognized
subcommands/flags (`stop`/`next`/`sync`/`plan`/`now`/`every`/`pr`/`direct`/
`dashboard`/`add`/`remove`/`reconsider`) must NOT fall through to
`modes/sprint.md` (which dereferences `$N` with no default). Route it to the
bare-invocation handler in `subcommands/stop-next.md` instead. This guard
fires ONLY for the empty case — a standalone `now` (handled by its own row),
any subcommand, or a leading `N` all leave `BARE_MODE=0`. Place this AFTER
all subcommand detection so every recognized token has already been seen.

```bash
BARE_MODE=0
if ! [[ "$ARGUMENTS" =~ ^[[:space:]]*[0-9]+ ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[sS][tT][oO][pP]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[nN][eE][xX][tT]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[sS][yY][nN][cC]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][lL][aA][nN]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[nN][oO][wW]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[eE][vV][eE][rR][yY]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[pP][rR]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][iI][rR][eE][cC][tT]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[dD][aA][sS][hH][bB][oO][aA][rR][dD]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][dD][dD]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[rR][eE][mM][oO][vV][eE]($|[[:space:]]) ]] \
   && ! [[ "$ARGUMENTS" =~ (^|[[:space:]])[rR][eE][cC][oO][nN][sS][iI][dD][eE][rR]($|[[:space:]]) ]]; then
  BARE_MODE=1
fi
```

When `BARE_MODE=1`, route to the bare-invocation handler in
[subcommands/stop-next.md](subcommands/stop-next.md) (the "Bare invocation"
section): report active-cron status + cron-control hint if a `/fix-issues`
cron exists, else a general usage hint with no cron output, then `exit 0`.
NEVER enter `modes/sprint.md`.

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
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][dD][dD]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with add mode" >&2
    exit 2
  fi
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[rR][eE][mM][oO][vV][eE]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with remove mode" >&2
    exit 2
  fi
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[rR][eE][cC][oO][nN][sS][iI][dD][eE][rR]($|[[:space:]]) ]]; then
    echo "ERROR: dashboard is incompatible with reconsider mode" >&2
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
- `/fix-issues add 700` — add issue #700 to Ready queue
- `/fix-issues add 700 triage` — add #700 to Triage column
- `/fix-issues add 700 ready 1` — add #700 at position 1 in Ready
- `/fix-issues remove 700` — remove #700 from Ready queue
- `/fix-issues remove 700 triage` — remove #700 from Triage
- `/fix-issues reconsider 717` — flag #717 for re-evaluation on next sprint

## Execution path

Select the execution path based on the detected mode, then **read the
corresponding mode file in full and follow its procedure end-to-end**.
Do not proceed until you have read the file.

| Detected mode | File |
|---|---|
| `add` | [subcommands/add-remove.md](subcommands/add-remove.md) |
| `remove` | [subcommands/add-remove.md](subcommands/add-remove.md) |
| `reconsider` | [subcommands/reconsider.md](subcommands/reconsider.md) |
| `now` (standalone — no N provided) | [subcommands/stop-next.md](subcommands/stop-next.md) |
| `next` | [subcommands/stop-next.md](subcommands/stop-next.md) |
| `stop` | [subcommands/stop-next.md](subcommands/stop-next.md) |
| `sync` | [modes/sync.md](modes/sync.md) |
| `plan` | [modes/plan.md](modes/plan.md) |
| Bare (`BARE_MODE=1` — no N, no subcommand) | [subcommands/stop-next.md](subcommands/stop-next.md) |
| Otherwise (sprint mode with N) | [modes/sprint.md](modes/sprint.md) |

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
- **Always write `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`** — it's the handoff to `/fix-report`.
- **Never close GH issues, update trackers, or remove worktrees** — that's
  `/fix-report`'s job.
- **One issue per commit** — clean git history in worktrees.
- **`$FULL_TEST_CMD` before every commit** (canonical form — maintainers: see
  `references/canonical-config-prelude.md` §1 in the zskills source) — not
  just `npm test`.
- **Result-provenance de-duplication (de-dup, NOT skip).** The impl agent's
  pre-commit `$FULL_TEST_CMD` run produces a STAMPED results file carrying a
  provenance header (tree + content-sensitive fingerprint + epoch). Because
  fix-issues uses the verifier-commits-after model (the impl agent does NOT
  commit; the verification agent commits AFTER passing tests, above), that
  stamped result IS reusable by the verification agent: at verify time the
  working tree is the SAME dirty pre-commit tree the impl agent measured, so
  `tests/lib/suite-result-valid.sh` validates it (exit 0) and the verifier
  de-duplicates — verify the tally, ALWAYS run the cross-cutting concern
  suites (`test-skill-conformance.sh`, `test-skills-mirror-parity.sh`,
  `test-skill-version-enforcement.sh`, `test-doc-viewer-catalog.sh`,
  `test-managed-md-up-to-date.sh`, `test-agents-parity.sh`), and re-run only
  the targeted suites for the changed area. Run the FULL suite on invalid/stale
  (exit 1), an empty/uncertain target, or a shared-infra / `skills/**/*.md` /
  `agents/*.md` / `CLAUDE_TEMPLATE.md` diff. Honest caveat: a result captured
  BEFORE the impl agent's LAST edit drifts in content → fingerprint mismatch →
  exit 1 → full re-run (the predicate working, not a foreclosure). Reuse is NOT
  foreclosed across a commit boundary — the model is identical to run-plan.
  (fix-issues impl agents are `subagent_type: "implementer"`.)
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
- **Enterprise GitHub host (#1162)** — before the inline `gh issue view` /
  `gh issue close` calls, export `GH_HOST` from the repo's actual remote so
  `gh` targets *your* host (not the github.com default) on a GitHub
  Enterprise repo. Source the shared helper once near the top of the
  sprint's gh-using shell (it exports `GH_HOST` when resolvable, fail-open
  otherwise, and respects a pre-set value):

  ```bash
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/land-pr/scripts/gh-host.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/land-pr/scripts/gh-host.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/gh-host.sh"
  fi
  ```
