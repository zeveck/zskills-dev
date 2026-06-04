#!/bin/bash
# zskills-hook-version: 2026.06.4
# block-fix-issue-unclaimed.sh — PreToolUse hook on Bash.
#
# Backstops the /fix-issues inline-acquire prose discipline (plans/fix-issues-claims.md
# Phase 2, W2.2c, round 4 option C). Denies any Bash invocation of
# create-worktree.sh / ensure-worktree.sh whose RESOLVED branch matches
# `fix-issue-NNN` or `fix/issue-NNN` and lacks a matching
# `${MAIN_ROOT}/.zskills/claims/issue-NNN/` directory.
#
# Hook contract (from plan W2.2c):
#   - Reads PreToolUse JSON envelope from stdin (tool_name, tool_input.command).
#   - Filters: only Bash tool calls; only commands invoking
#     (create-worktree|ensure-worktree)\.sh\b.
#   - Argv tokenization is Python shlex (NOT regex over the command string)
#     — values of --purpose or --branch-name contain `issue=NNN` substrings
#     that would mislead a naive regex.
#   - Computes branch name via create-worktree.sh's precedence:
#       --branch-name <v>  OVERRIDES  --prefix-<slug>  OVERRIDES  wt-<slug>
#   - If resolved branch matches ^fix-issue-[0-9]+$ or ^fix/issue-[0-9]+$,
#     extracts the issue number NNN and checks ${MAIN_ROOT}/.zskills/claims/issue-NNN/.
#   - If no claim exists: emits a PreToolUse deny envelope (same JSON shape
#     as hooks/block-main-edits.sh:175) with verbatim recovery instructions
#     mirroring the block-stale-skill-version.sh precedent.
#   - If a claim DOES exist (issue #865): read claim.json:pipeline_id and
#     compare to the caller's --pipeline-id (captured from the create-worktree
#     argv). Same pipeline_id → allow (self-re-entry, e.g. cron re-fire of
#     the same sprint). Different pipeline_id → deny (foreign pipeline trying
#     to materialise on an already-claimed issue). Absent or malformed
#     claim.json → fail-OPEN with stderr WARN (hook's existing infra-error
#     discipline; do not block on unverifiable state — only deny on a
#     concrete mismatch). NOTE: this is INTENTIONALLY different from
#     claim-self-reentry.sh's "absent claim.json → foreign (10)" semantics:
#     the acquire path must never STEAL an unverifiable claim, but the hook
#     is a backstop and must never false-deny when it cannot prove a
#     conflict.
#   - All other branch patterns (non-fix-issue prefixes like pr-<slug>,
#     cp-<slug>, wt-<slug>) pass through (exit 0) immediately.
#   - MAIN_ROOT resolution: `git rev-parse --git-common-dir` parent
#     (script-side symmetry with claim-issue.sh per plan DA4.1), falling
#     back to ${CLAUDE_PROJECT_DIR:-$PWD} only if git rev-parse fails.
#
# Subagent composition (plan R4.2): once registered in .claude/settings.json,
# this hook fires on EVERY Bash tool call from BOTH the orchestrator AND
# implementer/verifier subagents — same additive pattern as
# block-stale-skill-version.sh. The hook is filter-scoped to the two
# script names; subagent Bash calls that don't invoke them are pass-through.
#
# No `2>/dev/null` on fallible ops — failures should be visible. The hook
# is fail-open on its own infrastructure errors (defensive: never false-
# deny on git-not-installed, Python-missing, etc.) but emits stderr.

# D16(a) plugin-lane conditional-skip shim. No-op on the /update-zskills
# lane (CLAUDE_PLUGIN_ROOT unset → guard below skips the source). On the
# plugin lane it defers to a settings.json-registered copy of this hook to
# prevent double-fire when both install lanes are active. Must be the first
# executable line; the shim controls its own exit/return.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh" ] && source "${CLAUDE_PLUGIN_ROOT}/hooks/_lib/plugin-hook-skip-if-mirrored.sh"

INPUT=$(cat) || exit 0
[ -z "$INPUT" ] && exit 0

# ── Tool-name gate ────────────────────────────────────────────────────────
TOOL_NAME=""
if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  TOOL_NAME="${BASH_REMATCH[1]}"
fi
[ "$TOOL_NAME" = "Bash" ] || exit 0

# ── Extract command string ────────────────────────────────────────────────
# tool_input.command is the bash command line as the agent typed it. Use
# Python's json to decode safely (strings may contain escaped quotes,
# embedded newlines, backslashes). Bash regex over the raw JSON envelope
# loses to escape sequences — Python json.loads is the canonical parser.
# zskills_resolve_python — print path to a working Python 3 interpreter, or
# empty if none. Probe-RUNS each candidate (existence is NOT enough: on Windows
# `command -v python3` finds the MS Store App-Execution-Alias stub, which exits
# non-zero when run). Honors ZSKILLS_PYTHON. Rejects python2.
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
if [ -z "$PYTHON" ]; then
  # No working Python — fail-open. Print a stderr warning so the operator sees
  # the gap rather than silently passing every invocation through.
  echo "block-fix-issue-unclaimed.sh: WARN no working Python 3 found; hook is no-op — set ZSKILLS_PYTHON" >&2
  exit 0
fi

CMD=$("$PYTHON" - <<'PY' "$INPUT"
import json, sys
try:
    env = json.loads(sys.argv[1])
    cmd = (env.get("tool_input") or {}).get("command") or ""
    sys.stdout.write(cmd)
except Exception:
    pass
PY
)
[ -z "$CMD" ] && exit 0

# ── Filter: only create-worktree.sh / ensure-worktree.sh invocations ─────
# Widened from create-worktree\.sh\b per plan R4.1/DA4.3 so a future
# refactor that routes per-issue materialisation through the ensure-worktree
# wrapper stays gated.
case "$CMD" in
  *create-worktree.sh*|*ensure-worktree.sh*) ;;
  *) exit 0 ;;
esac

# ── Argv-walk via Python shlex (plan DA4.2) ──────────────────────────────
# Resolve the branch name using create-worktree.sh's documented precedence:
#   --branch-name <v>     wins outright
#   else --prefix <v> + positional <slug>   ->   <prefix>-<slug>
#   else positional <slug>                  ->   wt-<slug>
# Emits three lines to stdout:
#   BRANCH=<resolved-branch-or-empty>
#   SLUG=<positional-slug-or-empty>
#   PIPELINE_ID=<caller-pipeline-id-or-empty>   (issue #865 — captured for
#                                                the ownership check below)
WALK=$("$PYTHON" - <<'PY' "$CMD"
import shlex, sys
cmd_str = sys.argv[1]
try:
    argv = shlex.split(cmd_str)
except ValueError:
    # Malformed quoting — fail-open at the parse layer; print empty.
    print("BRANCH=")
    print("SLUG=")
    sys.exit(0)

prefix = None
branch_name = None
pipeline_id = None  # issue #865 — captured for ownership check
positionals = []

# Walk to the script-path token (whatever ends in create-worktree.sh or
# ensure-worktree.sh). Everything before is wrapper noise (bash, env, etc.).
i = 0
n = len(argv)
while i < n and not argv[i].endswith(("create-worktree.sh", "ensure-worktree.sh")):
    i += 1
i += 1  # skip past the script path itself

while i < n:
    tok = argv[i]
    if tok == "--branch-name" and i + 1 < n:
        branch_name = argv[i + 1]
        i += 2
        continue
    if tok == "--prefix" and i + 1 < n:
        prefix = argv[i + 1]
        i += 2
        continue
    if tok == "--pipeline-id" and i + 1 < n:
        # issue #865 — capture the caller's pipeline-id so the post-existence
        # ownership check below can compare against claim.json:pipeline_id.
        # Mirrors --branch-name / --prefix capture shape (symmetric two-arg
        # consume). Without this branch the generic --* fall-through silently
        # swallowed the value, leaving the hook unable to enforce ownership.
        pipeline_id = argv[i + 1]
        i += 2
        continue
    if tok.startswith("--"):
        # Generic two-arg flag skip — every known flag on create-worktree.sh
        # takes exactly one value. If next tok is also a flag, treat this
        # as a value-less flag and consume one.
        if i + 1 < n and not argv[i + 1].startswith("--"):
            i += 2
            continue
        i += 1
        continue
    positionals.append(tok)
    i += 1

slug = positionals[-1] if positionals else None

# Apply precedence to compute branch.
if branch_name:
    branch = branch_name
elif prefix and slug:
    branch = "{}-{}".format(prefix, slug)
elif slug:
    branch = "wt-{}".format(slug)
else:
    branch = ""

print("BRANCH=" + (branch or ""))
print("SLUG=" + (slug or ""))
print("PIPELINE_ID=" + (pipeline_id or ""))
PY
)

BRANCH=""
SLUG=""
CALLER_PIPELINE_ID=""
while IFS= read -r line; do
  case "$line" in
    BRANCH=*)      BRANCH="${line#BRANCH=}" ;;
    SLUG=*)        SLUG="${line#SLUG=}" ;;
    PIPELINE_ID=*) CALLER_PIPELINE_ID="${line#PIPELINE_ID=}" ;;
  esac
done <<< "$WALK"

# No resolvable branch -> nothing to gate.
[ -z "$BRANCH" ] && exit 0

# ── Branch-pattern gate ──────────────────────────────────────────────────
# Strictly anchor to the two /fix-issues branch shapes — all other
# patterns pass through. Capture NNN.
NNN=""
if [[ "$BRANCH" =~ ^fix-issue-([0-9]+)$ ]]; then
  NNN="${BASH_REMATCH[1]}"
elif [[ "$BRANCH" =~ ^fix/issue-([0-9]+)$ ]]; then
  NNN="${BASH_REMATCH[1]}"
fi
[ -z "$NNN" ] && exit 0

# Defensive: if prefix-derived branch ended up looking like fix-issue-<slug>
# but slug is non-numeric or non-positive, log a stderr warning and ALLOW
# (don't deny — prevents accidental partial-match on malformed fences).
case "$NNN" in
  ''|*[!0-9]*)
    echo "block-fix-issue-unclaimed.sh: WARN malformed slug '$NNN' on branch '$BRANCH' — allowing" >&2
    exit 0
    ;;
esac
if [ "$NNN" -le 0 ] 2>/dev/null; then
  echo "block-fix-issue-unclaimed.sh: WARN non-positive issue number on branch '$BRANCH' — allowing" >&2
  exit 0
fi

# ── Resolve MAIN_ROOT (script-side symmetry with claim-issue.sh, DA4.1) ──
MAIN_ROOT=""
if COMMON_DIR=$(git rev-parse --git-common-dir 2>&1) && [ -n "$COMMON_DIR" ]; then
  # git rev-parse --git-common-dir is relative to $PWD; resolve absolutely.
  if RESOLVED=$(cd "$COMMON_DIR/.." 2>&1 && pwd); then
    MAIN_ROOT="$RESOLVED"
  fi
fi
if [ -z "$MAIN_ROOT" ]; then
  MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# ── Claim-presence check ─────────────────────────────────────────────────
CLAIM_DIR="${MAIN_ROOT}/.zskills/claims/issue-${NNN}"
if [ -d "$CLAIM_DIR" ]; then
  # ── Ownership check (issue #865) ─────────────────────────────────────
  # Existence alone is insufficient: a foreign pipeline holding the claim
  # would otherwise let any other pipeline materialise on top of it. Read
  # claim.json:pipeline_id and compare to the caller's --pipeline-id.
  #
  # Fail-open discipline mirrors the rest of this hook (see header §
  # "fail-open on its own infrastructure errors"): we only DENY on a
  # concrete mismatch. Absent claim.json, malformed JSON, missing caller
  # pipeline-id, or absent Python all WARN-and-allow — never false-deny
  # on unverifiable state. Contrast claim-self-reentry.sh which returns
  # 10 (foreign) on the same conditions; that path is enforcing
  # never-steal at acquire time, this path is enforcing never-false-deny
  # at backstop time.
  CLAIM_FILE="${CLAIM_DIR}/claim.json"
  if [ ! -f "$CLAIM_FILE" ]; then
    echo "block-fix-issue-unclaimed.sh: WARN claim.json missing under $CLAIM_DIR; cannot verify ownership — allowing" >&2
    exit 0
  fi
  if [ -z "$CALLER_PIPELINE_ID" ]; then
    echo "block-fix-issue-unclaimed.sh: WARN caller did not pass --pipeline-id; cannot verify ownership of issue-${NNN} claim — allowing" >&2
    exit 0
  fi
  STORED_PIPELINE_ID=$("$PYTHON" - "$CLAIM_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        sys.stdout.write(json.load(f).get("pipeline_id", "") or "")
except Exception:
    pass
PY
)
  if [ -z "$STORED_PIPELINE_ID" ]; then
    echo "block-fix-issue-unclaimed.sh: WARN claim.json at $CLAIM_FILE is malformed or missing pipeline_id; cannot verify ownership — allowing" >&2
    exit 0
  fi
  if [ "$STORED_PIPELINE_ID" = "$CALLER_PIPELINE_ID" ]; then
    # Self-re-entry — caller already owns this claim.
    exit 0
  fi
  # Concrete mismatch — foreign pipeline interference. Emit the
  # ownership-mismatch deny envelope (separate STOP_MSG below).
  OWNERSHIP_DENY=1
fi

# ── Deny envelope (plan DA4.4 — locked text) ─────────────────────────────
# Lane-portable recovery-command path (W1.4 pattern 2 / F-DA1-7): on the
# plugin lane cite ${CLAUDE_PLUGIN_ROOT}/skills/fix-issues/scripts/...; on
# the /update-zskills lane cite ${MAIN_ROOT}/.claude/skills/fix-issues/...
# (the mirror). Resolve to whichever exists.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/fix-issues/scripts/claim-issue.sh" ]; then
  CLAIM_ISSUE_PATH="${CLAUDE_PLUGIN_ROOT}/skills/fix-issues/scripts/claim-issue.sh"
else
  CLAIM_ISSUE_PATH="${MAIN_ROOT}/.claude/skills/fix-issues/scripts/claim-issue.sh"
fi
if [ "${OWNERSHIP_DENY:-0}" = "1" ]; then
  # Ownership-mismatch deny (issue #865): claim dir exists and
  # claim.json's pipeline_id differs from the caller's --pipeline-id.
  # Treat as race-lost (exit 10 semantics in claim-issue.sh acquire) —
  # the caller pipeline should SKIP this issue and proceed to the next.
  STOP_MSG=$(cat <<EOF
STOP: create-worktree.sh for fix-issue-${NNN} denied — issue is held by a foreign pipeline.

Claim at ${MAIN_ROOT}/.zskills/claims/issue-${NNN}/claim.json:
  stored pipeline_id: ${STORED_PIPELINE_ID}
  caller pipeline_id: ${CALLER_PIPELINE_ID}

This is the same outcome as ${CLAIM_ISSUE_PATH} acquire returning exit 10 (race lost). The caller pipeline should SKIP issue ${NNN} and proceed to the next. Do NOT remove the claim dir or steal the claim — the holding pipeline will release it on land-or-abandon.

If you believe this is wrong (e.g., a stale claim from a crashed pipeline), inspect claim.json's started_at, sprint_id, and pipeline_id, then escalate to the operator. The hook is a backstop and intentionally fails closed only on a concrete pipeline_id mismatch.
EOF
)
else
  STOP_MSG=$(cat <<EOF
STOP: create-worktree.sh for fix-issue-${NNN} denied — no claim found at ${MAIN_ROOT}/.zskills/claims/issue-${NNN}/.

The per-issue dispatch fence in fix-issues modes/sprint.md (the "Worktree setup (cherry-pick and direct modes)" section, and the "PR mode (Phase 3)" section) MUST call:

  bash ${CLAIM_ISSUE_PATH} acquire ${NNN} --pipeline-id "\$ZSKILLS_PIPELINE_ID" --sprint-id "\$SPRINT_ID"

immediately above the create-worktree.sh invocation. If this hook fired during a sprint, the SKILL.md prose has drifted — STOP, do not retry, file an issue.

If acquire returns exit 10 (race lost — issue held by a concurrent pipeline), skip and proceed to the next issue. If exit 11 (filesystem error), abort the sprint.
EOF
)
fi

# Emit deny envelope. Escape for JSON: backslashes first, then quotes, then
# newlines. Mirrors block-unsafe-project.sh / block-main-edits.sh.
ESC="${STOP_MSG//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESC"
exit 0
