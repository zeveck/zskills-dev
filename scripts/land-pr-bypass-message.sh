#!/bin/bash
# scripts/land-pr-bypass-message.sh — emit a STOP message diagnosing why
# the agent's direct `gh pr create` / `gh pr merge --auto` invocation was
# blocked. Invoked by hooks/block-bypassed-land-pr.sh after the
# tokenize-walk classifier matches; the hook captures stderr and serves
# it as the deny envelope's `permissionDecisionReason`.
#
# Behavior:
#   1. Probe current branch (HEAD) — `git symbolic-ref --short HEAD`.
#      `2>/dev/null` is the documented exception (mirrors /land-pr
#      SKILL.md:250-252) because recovery-to-empty is explicitly handled:
#      empty HEAD → skip the branch-match scan → fall to Pattern 1.
#   2. Resolve MAIN_ROOT (main repo's top-level dir) and WORKTREE_ROOT
#      (current worktree's top-level dir).
#   3. Scan {MAIN_ROOT,WORKTREE_ROOT}/.zskills/tracking/*/requires.land-pr.*
#      markers. A marker matches when:
#        - its body contains `^branch: $HEAD$` (this caller is mid-flight
#          for THIS branch — strong signal of an errored /land-pr), OR
#        - its body has NO `branch:` line at all (legacy marker shape,
#          predates this plan — treat as Pattern 2 fallback because the
#          ambiguous "some caller mid-flight, branch unknown" wording is
#          safer than implying no caller exists; DA-2-2).
#   4. Match → Pattern 2 (caller mid-flight, /land-pr errored).
#      No match → Pattern 1 (true direct bypass).
#   5. Exit 1 in both cases (the hook treats this as "deny").
#
# Constraints:
#   - ASCII-only message bodies (no Unicode bullets / em-dashes); use
#     `- ` for list items.
#   - Pure bash; no jq, no external interpreters.
#   - `2>/dev/null` is permitted ONLY on `git rev-parse` / `git
#     symbolic-ref` probes whose recovery-to-empty path is handled
#     explicitly below. Every other fallible op uses no suppression.

set -u

emit_pattern_1() {
  cat >&2 <<'STOP'
STOP: direct gh pr create / merge --auto from agent Bash bypasses /land-pr.

There is no requires.land-pr.* marker pointing at this branch, which means
no caller skill is currently mid-flight for the PR landing on this branch.
You appear to be invoking gh pr create or gh pr merge --auto directly,
outside a caller skill. That bypasses the discipline /land-pr enforces
(rebase against base, PR creation, CI poll, fix-cycle on failure,
auto-merge handling).

Use one of the caller skills instead:
- /commit pr        (general PR landing from a feature branch)
- /quickfix         (one-shot bug fix to PR-and-land)
- /do pr            (action-based PR workflow)
- /fix-issues pr    (PR-mode CI fix-up)

Or dispatch /land-pr directly via the Skill tool:
Skill { skill: "land-pr" }

If you need a true manual one-off, open a SEPARATE terminal outside the Claude Code session.
STOP
}

emit_pattern_2() {
  cat >&2 <<'STOP'
STOP: direct gh pr create / merge --auto from agent Bash bypasses /land-pr.

A requires.land-pr.* marker for this branch is present in the tracking
tree. That means a caller skill on this pipeline (e.g., /run-plan,
/commit pr, /do pr, /fix-issues pr, /quickfix) declared an intent to
land the PR via /land-pr - and you are running gh pr create / gh pr
merge --auto directly instead. Don't do that. The caller pipeline
expects /land-pr to do the work; bypassing it skips rebase, CI
polling, the fix-cycle loop, the .landed marker, and the fulfilled
marker the pipeline needs to consider itself done.

What to do:
- Dispatch /land-pr via the Skill tool (it is idempotent, so if a
  previous attempt errored mid-way it picks up cleanly):
    Skill { skill: "land-pr", args: "..." }
  In practice the caller skill that owns this pipeline should drive
  the landing - re-invoke whichever skill set up the requires marker
  (/run-plan, /commit pr, etc.) and let it dispatch /land-pr.
- If you have confirmed the marker is stale (no live caller, prior
  session crashed, pipeline was abandoned), clear it with:
    bash .claude/skills/update-zskills/scripts/clear-tracking.sh
  Then re-dispatch the caller skill cleanly.

If you need a true manual one-off outside any pipeline, open a SEPARATE terminal outside the Claude Code session.
STOP
}

# Step 1: probe HEAD. Empty recovery is explicitly handled below.
HEAD=$(git symbolic-ref --short HEAD 2>/dev/null)

# Step 2: resolve roots. These also use 2>/dev/null with explicit empty
# recovery — if we are not in a git repo at all, both come back empty
# and the scan loop skips with no candidates → Pattern 1.
MAIN_ROOT=""
WORKTREE_ROOT=""
_GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
if [ -n "$_GIT_COMMON_DIR" ]; then
  MAIN_ROOT=$(cd "$_GIT_COMMON_DIR/.." 2>/dev/null && pwd)
fi
WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

# Step 3: if HEAD is empty (detached / non-repo cwd), skip the scan and
# emit Pattern 1 (R-2-7 — branch correlation impossible).
if [ -z "$HEAD" ]; then
  emit_pattern_1
  exit 1
fi

# Step 4: scan tracking trees for a matching requires.land-pr.* marker.
matched=0
for ROOT in "$MAIN_ROOT" "$WORKTREE_ROOT"; do
  [ -z "$ROOT" ] && continue
  TRACKING_DIR="$ROOT/.zskills/tracking"
  [ -d "$TRACKING_DIR" ] || continue
  # Iterate every pipeline subdir's requires.land-pr.* markers.
  # Use a nullglob-style guard via explicit existence check on each
  # candidate (bash without `shopt -s nullglob` leaves unmatched globs
  # as the literal pattern, which `[ -f ... ]` then rejects).
  for marker in "$TRACKING_DIR"/*/requires.land-pr.*; do
    [ -f "$marker" ] || continue
    # Read marker body once.
    body=$(cat "$marker")
    # Strong match: marker body contains `^branch: $HEAD$`.
    if printf '%s\n' "$body" | grep -Fxq "branch: $HEAD"; then
      matched=1
      break 2
    fi
    # Backward-compat fallback (DA-2-2): marker has NO `branch:` line
    # at all → treat as Pattern 2 (legacy shape, mid-flight, branch
    # unknown — safer-default wording).
    if ! printf '%s\n' "$body" | grep -q '^branch:'; then
      matched=1
      break 2
    fi
  done
done

if [ "$matched" -eq 1 ]; then
  emit_pattern_2
else
  emit_pattern_1
fi
exit 1
