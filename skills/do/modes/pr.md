# /do — PR Mode (Path A)

Full end-to-end PR flow: create branch, worktree, dispatch agents, open the PR, poll CI, then write the landing marker.
### Path A: PR mode (`LANDING_MODE="pr"`)

Selected when the user passes `pr` explicitly, or when
`execution.landing` in `.claude/zskills-config.json` is `"pr"`.

**This path runs its own end-to-end flow in place of the normal Phase 2–5 sequence. It performs its OWN verification gate (Step A6.5, equivalent to Phase 3) BEFORE handing off to `/land-pr`, then after the PR is created skips to Phase 5 Report. It does NOT re-run SKILL.md's Phase 3 or Phase 4 — those are folded into Step A6.5 (verify) and the `/land-pr` dispatch (push/land) here.**

**Step A1 — Compose task slug (model-layer).** Set shell variable
`TASK_SLUG` to a kebab-case identifier matching
`^[a-z0-9]+(-[a-z0-9]+)*$`, ≤30 chars, a 3–5 word summary of the task.
Compose from `$TASK_DESCRIPTION`'s essential verbs/nouns — not a verbatim
prefix of the input. Multi-line descriptions compose the same way as
single-line ones: distill the intent, don't splice lines.

```bash
if [ -z "${TASK_SLUG:-}" ]; then
  echo "ERROR: TASK_SLUG not set — model-layer composition step skipped." >&2
  exit 5
fi
if ! [[ "$TASK_SLUG" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ ${#TASK_SLUG} -gt 30 ]; then
  echo "ERROR: TASK_SLUG must match ^[a-z0-9]+(-[a-z0-9]+)*\$ and be ≤30 chars (got '$TASK_SLUG')." >&2
  exit 2
fi
```

**Step A2 — Same-task in-flight guard (issue #883, BEFORE collision check).**
Cron re-fires of `Run /do <task-description> ... every N now` would
otherwise re-run the SAME task while a previous turn is still mid-
flight. The shared `check-inflight-batch.sh` helper, called with the
per-work-identity `--pipeline-id "do.<unsuffixed-TASK_SLUG>"` filter,
detects the same-session same-task sentinel and exits clean — leaving
the in-flight turn to finish. This MUST run BEFORE the Step A2.5
collision check below: the collision check would suffix `TASK_SLUG`
when a worktree already exists, masking the very same-task signal we
want to detect. Crashed-turn worktrees ARE escaped by the helper's
staleness logic (2h max-age sentinel reclaim) — when the sentinel
ages out, the next fire proceeds AND the collision check still
suffixes around the stale worktree on disk.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
INFLIGHT_HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/check-inflight-batch.sh"
INFLIGHT_KEY="do.${TASK_SLUG}"
if [ -x "$INFLIGHT_HELPER" ]; then
  if bash "$INFLIGHT_HELPER" check do --pipeline-id "$INFLIGHT_KEY" > /tmp/.do-inflight.$$ 2>/dev/null; then
    rm -f /tmp/.do-inflight.$$
    echo "/do task $INFLIGHT_KEY in flight; skipping redundant cron re-fire" >&2
    exit 0
  fi
  rm -f /tmp/.do-inflight.$$
  # Write the sentinel immediately so a same-session re-fire arriving
  # within the helper-call window also skips. The check + write must
  # both use the UNSUFFIXED key so a future re-fire (which re-derives
  # the same unsuffixed TASK_SLUG from the same description) finds it.
  bash "$INFLIGHT_HELPER" write do --pipeline-id "$INFLIGHT_KEY" || \
    echo "do: WARN — could not write in-flight sentinel (continuing)" >&2
fi
```

**Step A2.5 — Collision check (BEFORE deriving BRANCH_NAME or WORKTREE_PATH):**
```bash
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
if [ -d "/tmp/${PROJECT_NAME}-do-${TASK_SLUG}" ]; then
  TASK_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
fi
```

**Step A3 — Derive BRANCH_NAME and WORKTREE_PATH from (possibly suffixed) TASK_SLUG:**
```bash
# Read .execution.branch_prefix via bash-regex (no external jq dependency).
# Preserve empty-string when the key is present-but-empty; default "feat/"
# only when the key is absent or the config file is missing.
BRANCH_PREFIX="feat/"
if [ -f .claude/zskills-config.json ]; then
  _CFG=$(cat .claude/zskills-config.json)
  if [[ "$_CFG" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  fi
  unset _CFG
fi
BRANCH_NAME="${BRANCH_PREFIX}do-${TASK_SLUG}"
WORKTREE_PATH="/tmp/${PROJECT_NAME}-do-${TASK_SLUG}"
```

**Step A4 — Sanitize TASK_SLUG + construct PIPELINE_ID (BEFORE worktree creation):**
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
# Route TASK_SLUG through the shared sanitizer (collapses any character
# outside [a-zA-Z0-9._-] into `_`, truncates to 128 bytes). KEEP this
# defensive call: removing would require exhaustive downstream audit of
# TASK_SLUG consumers (R2-M4). It is safe to run this BEFORE worktree
# creation because the sanitized slug is needed by --pipeline-id.
TASK_SLUG=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/sanitize-pipeline-id.sh" "$TASK_SLUG")
PIPELINE_ID="do.${TASK_SLUG}"
```

**Step A5 — Worktree creation (pre-flight prune+fetch+ff-merge is owned by create-worktree.sh):**
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
# /do expects a fresh branch per task — no legitimate resume.
# --pipeline-id passes $PIPELINE_ID explicitly; the script sanitizes it
# again internally (idempotent on already-safe inputs) and writes the
# sanitized value to the worktree's .zskills-tracked. No env var reliance,
# no cross-invocation pollution.
WORKTREE_PATH=$(bash "$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/create-worktree.sh" \
  --prefix do \
  --branch-name "${BRANCH_PREFIX}do-${TASK_SLUG}" \
  --purpose "do PR mode; task=${TASK_SLUG}" \
  --pipeline-id "$PIPELINE_ID" \
  "${TASK_SLUG}")
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "create-worktree failed (rc=$RC) for /do PR mode" >&2
  exit "$RC"
fi
# create-worktree.sh has now written $PIPELINE_ID (sanitized) to
# $WORKTREE_PATH/.zskills-tracked.
```
Do NOT echo `ZSKILLS_PIPELINE_ID=do.${TASK_SLUG}` as shell output in the main session — the `.zskills-tracked` file in the worktree is the single source of truth.

**Step A5.5 — Claim the issue(s) (when `${#ISSUE_NUMS[@]} -gt 0`).** Now
that `PIPELINE_ID="do.${TASK_SLUG}"` is set (A4) and the worktree exists
(A5), fan out the `claim-issue.sh` acquire across every element of
`ISSUE_NUMS` BEFORE dispatching the implementation agent (A6). This stops
a concurrent `/fix-issues` cron from double-working any of the same
issues. `ISSUE_NUMS` is propagated from `/do`'s Pre-flight pre-parse
(populated only when the description referenced one or more issues and
`--force` overrode the `/fix-issues` redirect). Skip entirely when
`ISSUE_NUMS` is empty (the common /do pr case). The A1 slug guards and
A5's `exit "$RC"` are PRE-acquire, so they need no release. The claims are
released in the explicit-finalize block at the end of the caller loop
(Step A8), and inline before every post-acquire-pre-finalize early exit.
**Partial-acquire rollback:** if any acquire returns rc=10 (foreign-held)
on issue K, release issues 1..K-1 (acquired earlier in this loop) before
declining. Same rollback applies on rc=11/2/* failures.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
  CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
  _ACQUIRED=()
  for ISSUE_NUM in "${ISSUE_NUMS[@]}"; do
    bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"
    ACQ_RC=$?
    case "$ACQ_RC" in
      0)  _ACQUIRED+=("$ISSUE_NUM") ;;  # acquired (fresh or self-re-entry) — proceed
      10|11|2|*)
        # Partial-acquire rollback: release everything this pipeline grabbed earlier in this loop.
        for _RB in "${_ACQUIRED[@]}"; do
          bash "$CLAIM_HELPER" release "$_RB" --require-pipeline "$PIPELINE_ID"
        done
        case "$ACQ_RC" in
          10) echo "issue #$ISSUE_NUM is being worked by another pipeline; declining (released ${#_ACQUIRED[@]} prior claim(s))." >&2; exit 0 ;;
          11) echo "claim-issue.sh: filesystem error acquiring issue #$ISSUE_NUM (released ${#_ACQUIRED[@]} prior claim(s)); stopping." >&2; exit 1 ;;
          2)  echo "claim-issue.sh: usage error (empty PIPELINE_ID or non-numeric ISSUE_NUM=$ISSUE_NUM; released ${#_ACQUIRED[@]} prior claim(s)) — internal bug; stopping." >&2; exit 1 ;;
          *)  echo "claim-issue.sh: unexpected exit $ACQ_RC acquiring issue #$ISSUE_NUM (released ${#_ACQUIRED[@]} prior claim(s)); stopping." >&2; exit 1 ;;
        esac ;;
    esac
  done
  unset _ACQUIRED _RB
fi
```

Do NOT copy `/fix-issues`'s HOLD-on-`created` arm: `/do pr` is one-shot
(no later sprint fire re-runs `/land-pr` to release), so a HOLD would leak
the claim forever.

**Step A6 — Dispatch implementation agent (wait for completion):**

**Dispatch shape.** Use the `Agent` tool with `subagent_type: "implementer"`.
This inherits the Layer 0 Bash-timeout extension (see
`.claude/agents/implementer.md` + the "Verifier-cannot-run rule" section in
CLAUDE.md) so the impl agent's Bash calls to run long test suites don't
trigger the bg+Monitor stall pattern.

**Before dispatching:** Check `agents.min_model` in `.claude/zskills-config.json`. If set,
use that model or higher (ordinal: haiku=1 < sonnet=2 < opus=3). Never dispatch with a
lower-ordinal model than the configured minimum.

Dispatch an Agent (without `isolation: "worktree"` — the worktree already exists) with this prompt:

```
You are implementing: $TASK_DESCRIPTION

FIRST: cd $WORKTREE_PATH
All work happens in that directory. Do NOT work in any other directory.
You are on branch $BRANCH_NAME (already checked out in the worktree).

Implement the task. Commit changes when done:
- Stage files by name (not git add .)
- Do NOT commit to main
- Commit message should summarize what was implemented

Check agents.min_model in .claude/zskills-config.json before dispatching
any sub-agents. Use that model or higher (haiku=1 < sonnet=2 < opus=3).
```

Wait for the implementation agent to complete. If the agent reports failure or exits without committing:
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
cat > "$WORKTREE_PATH/.landed" <<LANDED
status: conflict
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
source: do
branch: $BRANCH_NAME
LANDED
```
Exit with error directing the user to inspect `$WORKTREE_PATH`.

**Step A6.5 — Verify (before push/land):**

`/do pr` runs the SAME local verification gate as its worktree/direct
siblings (`/do` Phase 3) and as the other PR-mode callers (`/quickfix`
Phase 5.5, `/run-plan`, `/fix-issues`, `/commit`) BEFORE handing off to
`/land-pr`. Issue #1014 — `/do pr` was previously the only PR-mode caller
with no local verification gate: it relied solely on CI through
`/land-pr`. CI (via `/land-pr`'s `pr-monitor.sh`) is the **backstop**, not
the gate — a failing diff should be caught here, locally, before a branch
is pushed and a PR is opened.

Verification intensity matches the change type the implementation agent
produced (the content/code/mixed split from `/do` Phase 1, exactly as
Phase 3 applies it):

- **Content-only changes** (markdown, images, presentations, docs):
  dispatch a plain review agent — NO full test run. Tell the agent
  explicitly: "These are content-only changes (no code). Review the diff
  for correctness and completeness — do NOT run the full test suite. Your
  job is: do these changes make sense? Are the right files included?
  Anything accidentally staged? Formatting correct?" Do NOT invoke
  `/verify-changes` for content-only changes (it would run the full suite
  regardless).

  **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`.
  The verifier's tool allowlist (`Read, Grep, Glob, Bash, Edit, Write`) is
  sufficient for content review; the prose preamble above keeps it from
  running tests.

- **Code changes** (js, css, html, model files) **and mixed changes:**
  dispatch a separate verification agent running `/verify-changes`. This
  is the full 7-phase verification: diff review, test coverage audit,
  full test suite, manual verification if UI, fix problems, re-verify
  until clean. Push/land (Step A7/A8) only happens if this agent reports
  clean.

  **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`.
  This inherits the Layer 0 Bash-timeout extension
  (`.claude/agents/verifier.md` + CLAUDE.md "Verifier-cannot-run rule") so
  the verifier's long test runs don't trigger the bg+Monitor stall
  pattern. The prompt should include the branch name (`$BRANCH_NAME`), the
  task description (`$TASK_DESCRIPTION`), and the worktree path
  (`$WORKTREE_PATH`) so the verifier has full context. Tell it to run
  `/verify-changes` in `$WORKTREE_PATH`.

In BOTH cases, after the dispatch returns, pipe `$VERIFIER_RESPONSE`
through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`;
on exit 1 STOP — do NOT push and do NOT dispatch `/land-pr`.

**Layer 3 — verifier response validation:**

```bash
printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
VALIDATE_EXIT=$?
```

On `VALIDATE_EXIT=1` — or when the verifier agent reports a verification
FAILURE it could not resolve (tests still failing, diff unsound) — STOP.
Do NOT push and do NOT dispatch `/land-pr`. Write the `.landed` marker
(`status: pr-failed`) and release any acquired issue claim(s) before
exiting, reusing Step A6's failure shape:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
cat > "$WORKTREE_PATH/.landed" <<LANDED
status: pr-failed
date: $(TZ="${TIMEZONE:-UTC}" date -Iseconds)
source: do
branch: $BRANCH_NAME
reason: local verification failed before push/land (#1014)
LANDED
# C2 inline-release: this STOP is AFTER the Step A5.5 acquire and BEFORE
# the explicit-finalize block in Step A8, so release the issue claim(s)
# (only if any were acquired) before bailing or they leak. Same fan-out
# over $ISSUE_NUMS the abandon paths use.
if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
  for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
    bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
  done
  unset _ISSUE_N
fi
```

Then emit the STOP message and exit (do NOT continue to Step A7/A8):

```
STOP: verifier returned without meaningful results.

$(cat /tmp/last-validate-stderr)

This is a verification FAIL, not a license to push. Surface to the
user. If the verifier agent file is missing, run /update-zskills.
```

Only when verification is clean do you continue to Step A7.

**Step A7 — Compose PR title and body BEFORE invoking /land-pr:**

`/land-pr` owns rebase, push, PR creation, CI polling, fix-cycle, and the
`.landed` marker write (canonical schema, including `pr-state-unknown` on
exhausted `gh pr view` retries). `/do pr` is responsible only for the
title/body composition and the fix-cycle agent's task-context slot.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
cd "$WORKTREE_PATH"

# Compose $PR_TITLE (model-layer). Set shell variable PR_TITLE to a
# single-line title, ≤60 chars, that MUST begin with the literal prefix
# `do: ` (four characters: d, o, colon, space — preserving /do's existing
# convention). After the prefix, summarize what the task actually did —
# compose from the completed work, not a verbatim prefix of
# $TASK_DESCRIPTION.
if [ -z "${PR_TITLE:-}" ]; then
  echo "ERROR: PR_TITLE not set — model-layer composition step skipped." >&2
  # C2 inline-release: this exit is AFTER the Step A5.5 acquire and BEFORE
  # the explicit-finalize block, so release the issue claim(s) (only if any
  # were acquired) before bailing or they leak.
  if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
    for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
    done
    unset _ISSUE_N
  fi
  exit 5
fi
if [[ "$PR_TITLE" == *$'\n'* ]] || [ ${#PR_TITLE} -gt 60 ] || [[ "$PR_TITLE" != do:\ * ]]; then
  echo "ERROR: PR_TITLE must be a single line ≤60 chars starting with 'do: ' (got '$PR_TITLE')." >&2
  if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
    for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
      bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
    done
    unset _ISSUE_N
  fi
  exit 2
fi

# PR body: explicit, not --fill (the title and body are constructed by the
# skill, not auto-derived from commits). Per-BRANCH_SLUG path so
# concurrent /do pr invocations on parallel worktrees do not collide.
BRANCH_SLUG="${BRANCH_NAME//\//-}"
BODY_FILE="/tmp/pr-body-do-$BRANCH_SLUG.md"
cat > "$BODY_FILE" <<BODY
Task: ${TASK_DESCRIPTION}

Worktree: ${WORKTREE_PATH}
Commits: $(git log origin/main..HEAD --format='%h %s' | head -10)
BODY
```

**Step A8 — Dispatch `/land-pr` (canonical caller loop):**

`/do pr` no longer owns rebase, push, PR creation, CI polling, or the
`.landed` write — those move to `/land-pr` (see `skills/land-pr/SKILL.md`).
`/do pr` gains a fix-cycle on CI failure (drift fix) — the fix-cycle
agent's `<CALLER_WORK_CONTEXT>` slot is filled with the original task
description.

`/do pr` customizations of the canonical pattern:
- `$LANDED_SOURCE = "do"`
- `$WORKTREE_PATH` set (the per-task worktree from Step A5)
- `--auto` is gated on the positional `auto` token (issue #297 — matches
  /quickfix, /run-plan, /fix-issues). Without `auto`, auto-merge stays
  OFF and the PR settles at `pr-ready` after CI passes; with `auto`,
  `LAND_ARGS` includes `--auto` and `/land-pr`'s existing auto-merge
  path takes over.
- `<CALLER_PRE_INVOKE_BODY_PREP>` = empty (do's body is fixed at PR
  creation; no per-phase update like /run-plan does)
- `<CALLER_REBASE_CONFLICT_HANDLER>` = no agent-assisted resolution
  (single-task scope, no plan context); break and surface the bail
- `<DISPATCH_FIX_CYCLE_AGENT_HERE>` = task description (`$TASK_DESCRIPTION`)

```bash
# === BEGIN CANONICAL /land-pr CALLER LOOP ===
# Per skills/land-pr/references/caller-loop-pattern.md.

ATTEMPT=0
MAX="${CI_MAX_ATTEMPTS:-2}"
RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"

# Tracking-setup block (Plan LAND_PR_BYPASS_HARDENING Phase 2): write
# requires.land-pr.<id> and fulfilled.do.<id> markers BEFORE LAND_ARGS
# assembly. Re-resolve $MAIN_ROOT / $PIPELINE_ID at fence-top per the
# "Resolve config-derived vars at fence-top" rule (separate Bash tool
# invocations → variables do NOT survive across fences). $TASK_SLUG and
# $BRANCH_NAME were model-substituted at fence emission per /do's
# existing convention (Step A1 + Step A3).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="do.$TASK_SLUG"
# Echo (do not env-export) the pipeline id — matches /quickfix's tier-2
# transcript-propagation idiom (`skills/quickfix/SKILL.md:672`) and
# satisfies the conformance test at `tests/test-skill-conformance.sh:1050`
# which forbids the env-export side-channel form.
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
TRACK_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
mkdir -p "$TRACK_DIR"
NOW_ISO=$(TZ="${TIMEZONE:-UTC}" date -Iseconds)
# fulfilled.<skill>.<id> start-marker (per #228 Part B).
cat > "$TRACK_DIR/fulfilled.do.$TASK_SLUG" <<MARK
status: started
date: $NOW_ISO
skill: do
mode: pr
branch: $BRANCH_NAME
MARK
# requires.land-pr.<id> (drives hook STOP-message Pattern 2 + dashboard).
cat > "$TRACK_DIR/requires.land-pr.$TASK_SLUG" <<MARK
skill: land-pr
parent: do
id: $TASK_SLUG
branch: $BRANCH_NAME
date: $NOW_ISO
MARK

# LAND_OUTCOME tracker (R-5-8). Set by case arms below.
LAND_OUTCOME=__init__

LANDED_SOURCE="do"
LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=$LANDED_SOURCE --worktree-path=$WORKTREE_PATH --tracking-id=$TASK_SLUG"
# Issue #297: positional `auto` token (parsed in pre-flight pre-parse)
# opts /do pr into /land-pr's auto-merge path. Mirrors /quickfix,
# /run-plan, /fix-issues.
[ "${AUTO_FLAG:-0}" = "1" ] && LAND_ARGS="$LAND_ARGS --auto"

while :; do
  # <CALLER_PRE_INVOKE_BODY_PREP> — empty for /do pr.
  #
  # /do pr composes the body once before the loop (Step A7 above) and
  # never refreshes it. /land-pr touches the body only on initial PR
  # creation; on existing PRs (the second-iteration retry case) the body
  # is preserved as-is — fine for /do pr because the body content is a
  # static task-description + commit-log snapshot, not a progress
  # checklist that drifts.

  # Invoke /land-pr via the Skill tool. The Skill tool loads /land-pr's
  # prose into the current (orchestrator) context — its internal bash
  # blocks run here.
  #
  # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

  if [ ! -f "$RESULT_FILE" ]; then
    echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
    # Inline cleanup before exit (DA-3-1 / R-4-9 — this exit bypasses the
    # explicit-finalize block at end-of-fence). Variables in scope (same fence).
    rm -f "$TRACK_DIR/requires.land-pr.$TASK_SLUG"
    sed -i "s/^status: started$/status: failed/" "$TRACK_DIR/fulfilled.do.$TASK_SLUG"
    # C2 inline-release: post-acquire, pre-finalize early exit — release
    # the issue claim(s) (only if any were acquired) or they leak.
    if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
      for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
        bash "$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID"
      done
      unset _ISSUE_N
    fi
    exit 1
  fi

  # SAFE allow-list parsing (per WI 1.7). Never `source`. Reading line by
  # line and dispatching on a fixed key set guarantees that even
  # maliciously-crafted values cannot reach shell evaluation.
  declare -A LP
  while IFS='=' read -r KEY VALUE; do
    case "$KEY" in
      STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
      MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
      CONFLICT_FILES_LIST|CALL_ERROR_FILE|REBASE_STDERR_FILE)
        LP["$KEY"]="$VALUE" ;;
      "") ;;  # blank line — ignore
      *) printf 'WARN: /land-pr result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
    esac
  done < "$RESULT_FILE"

  STATUS="${LP[STATUS]:-}"
  CI_STATUS="${LP[CI_STATUS]:-}"
  PR_URL="${LP[PR_URL]:-}"
  PR_NUMBER="${LP[PR_NUMBER]:-}"

  # Sidecar cleanup paths. CI_LOG_FILE intentionally NOT in the array —
  # the fix-cycle agent below reads it.
  _CLEANUP_PATHS=("${LP[CALL_ERROR_FILE]:-}" "${LP[CONFLICT_FILES_LIST]:-}" "${LP[REBASE_STDERR_FILE]:-}")
  rm -f "$RESULT_FILE"

  case "$STATUS" in
    rebase-conflict)
      # <CALLER_REBASE_CONFLICT_HANDLER> — /do pr is single-task with no
      # plan context, so no agent-assisted resolution path. /land-pr
      # already wrote `.landed status=conflict` and aborted the rebase —
      # break and surface to user.
      echo "/land-pr returned rebase-conflict. Resolve manually in $WORKTREE_PATH and re-run \`/do pr\` (or land manually)." >&2
      LAND_OUTCOME=$STATUS
      break ;;
    push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
      echo "ERROR: /land-pr STATUS=$STATUS REASON=${LP[REASON]:-} (see ${LP[CALL_ERROR_FILE]:-no-error-file})" >&2
      LAND_OUTCOME=$STATUS
      break ;;
    behind-thrash)
      # Step 6b exhausted auto-rebase budget (issue #624). pr-ready
      # surface but the discriminator is preserved in $LAND_OUTCOME.
      echo "/land-pr STATUS=behind-thrash — auto-rebase budget exhausted, manual rebase needed" >&2
      LAND_OUTCOME=$STATUS
      break ;;
    auto-rebase-conflict|auto-rebase-blocked)
      # Step 6b auto-rebase merge-conflicted, or mergeStateStatus settled
      # at BLOCKED for non-CI reasons. Issue #624 — must NOT be silently
      # coerced to pr-ready by the CI-status check below.
      echo "/land-pr STATUS=$STATUS REASON=${LP[REASON]:-} — manual intervention needed" >&2
      LAND_OUTCOME=$STATUS
      break ;;
    created|monitored|merged) ;;  # fall through to CI-status check
    *)
      # Unknown STATUS — fail loud rather than coerce via CI-status
      # (issue #624 — closes the silent fall-through gap).
      echo "WARN: unrecognized /land-pr STATUS=$STATUS — settling at unknown-status" >&2
      LAND_OUTCOME="unknown-status-$STATUS"
      break ;;
  esac

  case "$CI_STATUS" in
    pass|none|skipped)
      if [ "${LP[PR_STATE]:-}" = "MERGED" ]; then
        LAND_OUTCOME=merged
      else
        LAND_OUTCOME=pr-ready
      fi
      break ;;  # /land-pr already requested merge if --auto
    pending)
      LAND_OUTCOME=pr-ready
      break ;;  # settle at pr-ready
    not-monitored)
      LAND_OUTCOME=created
      break ;;  # --no-monitor was used (none of /do pr's flows do this)
    fail)
      if [ "$ATTEMPT" -ge "$MAX" ]; then
        echo "INFO: CI fix-cycle exhausted ($ATTEMPT/$MAX); PR settles at pr-ci-failing" >&2
        LAND_OUTCOME=pr-ci-failing
        break
      fi
      # ===== <DISPATCH_FIX_CYCLE_AGENT_HERE> — /do pr customization =====
      #
      # Dispatch a fix-cycle agent at orchestrator level (NOT a nested
      # subagent — /land-pr was already invoked at orchestrator level
      # via the Skill tool; this dispatch is at the same level).
      #
      # Dispatch shape: use the `Agent` tool with subagent_type: "implementer".
      # This inherits the Layer 0 Bash-timeout extension
      # (.claude/agents/implementer.md + CLAUDE.md "Verifier-cannot-run rule")
      # so the fix-cycle agent's long test runs don't trigger the
      # bg+Monitor stall pattern.
      #
      # Prompt structure follows
      # skills/land-pr/references/fix-cycle-agent-prompt-template.md.
      # /do pr fills <CALLER_WORK_CONTEXT> with the original task
      # description — the agent gets the same brief as the implementation
      # agent did, plus the CI failure log.
      #
      # Inputs (substituted into the template):
      #   PR URL       = ${LP[PR_URL]}
      #   PR number    = ${LP[PR_NUMBER]}
      #   Branch       = $BRANCH_NAME
      #   Worktree     = $WORKTREE_PATH
      #   CI log file  = ${LP[CI_LOG_FILE]}
      #   Caller work context (CALLER_WORK_CONTEXT):
      #     Task: $TASK_DESCRIPTION
      #     Branch: $BRANCH_NAME
      #     Recent commits on this branch:
      #       $(cd "$WORKTREE_PATH" && git log origin/main..HEAD --format='%h %s')
      #
      # Constraints (verbatim from the template):
      #   - You are running at orchestrator level. Do NOT dispatch
      #     further Agent tools.
      #   - Do not invoke /land-pr yourself. The caller's loop owns
      #     re-invocation.
      #   - Do not modify .github/workflows/ unless the failure is
      #     clearly a workflow bug.
      #   - Honor existing tests (CLAUDE.md "NEVER weaken tests").
      #   - No --no-verify on commits.
      #
      # Procedure: read CI log → diagnose → state root cause → patch →
      # commit → push. The agent ends its reply with one line:
      #   FIX-CYCLE: root_cause="..." files_changed=N commit=<sha>
      # or
      #   FIX-CYCLE-PUNT: reason="..."
      #
      # After the agent completes, the caller's loop increments $ATTEMPT
      # and `continue`s — /land-pr is idempotent.
      # ====================================================================
      ATTEMPT=$((ATTEMPT + 1))
      continue ;;  # re-enter loop, /land-pr is idempotent
    unknown)
      echo "WARN: CI_STATUS=unknown — settling at pr-ready" >&2
      LAND_OUTCOME=pr-ready
      break ;;
    *)
      echo "WARN: CI_STATUS='$CI_STATUS' unrecognized — settling at pr-ready" >&2
      LAND_OUTCOME=pr-ready
      break ;;
  esac
done

# Sidecar cleanup (after final iteration). CI_LOG_FILE intentionally
# NOT in the array — useful for post-mortem inspection.
for f in "${_CLEANUP_PATHS[@]}"; do
  [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
done

# Body file cleanup — keep until after the loop in case a re-invocation
# needs it (only consumed on the first iteration where the PR doesn't
# exist yet, but defensive).
rm -f "$BODY_FILE"
# === END CANONICAL /land-pr CALLER LOOP ===
# Explicit-finalize block (Plan LAND_PR_BYPASS_HARDENING Phase 2 — must
# live in the SAME fence as the caller-loop per R-4-7 so $LAND_OUTCOME
# survives). R-5-6: no `cancelled)` arm — /do pr has no $CANCELLED.
case "$LAND_OUTCOME" in
  merged|created|pr-ready) FINAL=complete ;;
  *) FINAL=failed ;;
esac
sed -i "s/^status: started$/status: $FINAL/" "$TRACK_DIR/fulfilled.do.$TASK_SLUG"
rm -f "$TRACK_DIR/requires.land-pr.$TASK_SLUG"

# Release the issue claim(s) based on LAND_OUTCOME (mirrors
# fix-issues/modes/pr.md:337-345 so the two skills evolve in lockstep).
# Only if issue claims were acquired in Step A5.5. $PIPELINE_ID =
# do.$TASK_SLUG is re-resolved at the tracking-setup fence-top above and
# survives in this fence.
#
# Three groups (issue #864) × ISSUE_NUMS fan-out (issue #863):
#   - merged          → RELEASE (work is durably on main).
#   - pr-ready|created→ HOLD: the PR is OPEN on the remote awaiting human
#                       review/merge; releasing here would let a concurrent
#                       /fix-issues (or another /do pr) re-claim the same
#                       issue and duplicate the fix. /do is one-shot so
#                       there is no "later fire" to re-release — the
#                       stalled-PR claim is cleared manually via
#                       `claim-issue.sh release` once the human resolves
#                       the PR (same precedent as #684 for plan claims,
#                       and same shape as fix-issues PR mode's `created`
#                       arm at fix-issues/modes/pr.md:342-343).
#   - terminal-failure→ RELEASE (PR is dead-on-arrival; nothing to guard).
#
# Releases are idempotent per claim-issue.sh, so any claim already
# released by an inline-release early-exit upstream no-ops here.
if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
  CLAIM_HELPER="$ZSKILLS_SKILLS_ROOT/fix-issues/scripts/claim-issue.sh"
  for _ISSUE_N in "${ISSUE_NUMS[@]}"; do
    case "$LAND_OUTCOME" in
      merged)
        bash "$CLAIM_HELPER" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID" \
          || echo "do: claim release for #$_ISSUE_N returned non-zero (continuing)" >&2 ;;
      pr-ready|created)
        echo "do: holding claim for #$_ISSUE_N (LAND_OUTCOME=$LAND_OUTCOME — PR is in flight awaiting human review/merge); /do is one-shot so the claim is reaped manually via 'bash $CLAIM_HELPER release $_ISSUE_N' if the PR never lands" >&2 ;;
      pr-ci-failing|rebase-conflict|auto-rebase-conflict|auto-rebase-blocked|behind-thrash|rebase-failed|push-failed|create-failed|monitor-failed|merge-failed|unknown-status-*)
        bash "$CLAIM_HELPER" release "$_ISSUE_N" --require-pipeline "$PIPELINE_ID" \
          || echo "do: claim release for #$_ISSUE_N returned non-zero (continuing)" >&2 ;;
      *)
        echo "do: unknown LAND_OUTCOME=$LAND_OUTCOME for #$_ISSUE_N; defaulting to HOLD" >&2 ;;
    esac
  done
  unset _ISSUE_N
fi

# Issue #883 — clear the in-flight sentinel on every LAND_OUTCOME
# (terminal point for /do pr; Phase 5 in SKILL.md is bypassed by the
# `exit` at the end of this caller-loop). Use $INFLIGHT_KEY (the
# unsuffixed form set in Step A2) — it persists in the same shell
# session because /do pr's fences run inline. Falling back to
# $PIPELINE_ID when INFLIGHT_KEY is unset defends against any future
# refactor that drops Step A2's variable set without dropping the
# write.
INFLIGHT_HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/check-inflight-batch.sh"
if [ -x "$INFLIGHT_HELPER" ]; then
  bash "$INFLIGHT_HELPER" clear do --pipeline-id "${INFLIGHT_KEY:-$PIPELINE_ID}" || true
fi
```

**Note on the `.landed` schema:** `/land-pr` writes the canonical schema
(per its WI 1.11) — additive over the previous `/do pr` schema. Existing
fields (`status`, `date`, `source`, `branch`, `pr`) are all preserved;
new fields (`method`, `pr_state`, `merge_requested`, `merge_reason`,
`reason`, `commits`) are present when relevant. `/fix-report` and the
worktree-cleanup tooling handle the new fields gracefully (they read
fewer fields than the marker has — additive change is safe).

The `pr-state-unknown` status (when `gh pr view` exhausts retries) is now
emitted by `/land-pr`'s status-mapping table (WI 1.12 row 9), preserving
the previous /do pr behavior unchanged.

After the caller loop exits, output the Phase 5 PR report and **exit** (skip Phases 3-4).

