#!/bin/bash
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
PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  # No Python — fail-open. Print a stderr warning so the operator sees the
  # gap rather than silently passing every invocation through.
  echo "block-fix-issue-unclaimed.sh: WARN no Python available; hook is no-op" >&2
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
# Emits two lines to stdout:
#   BRANCH=<resolved-branch-or-empty>
#   SLUG=<positional-slug-or-empty>
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
PY
)

BRANCH=""
SLUG=""
while IFS= read -r line; do
  case "$line" in
    BRANCH=*) BRANCH="${line#BRANCH=}" ;;
    SLUG=*)   SLUG="${line#SLUG=}" ;;
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
  exit 0
fi

# ── Deny envelope (plan DA4.4 — locked text) ─────────────────────────────
STOP_MSG=$(cat <<EOF
STOP: create-worktree.sh for fix-issue-${NNN} denied — no claim found at ${MAIN_ROOT}/.zskills/claims/issue-${NNN}/.

The per-issue dispatch fence at SKILL.md:2161-2186 (cherry-pick/direct) or SKILL.md:2219-2243 (PR mode) MUST call:

  bash ${MAIN_ROOT}/.claude/skills/fix-issues/scripts/claim-issue.sh acquire ${NNN} --pipeline-id "\$ZSKILLS_PIPELINE_ID" --sprint-id "\$SPRINT_ID"

immediately above the create-worktree.sh invocation. If this hook fired during a sprint, the SKILL.md prose has drifted — STOP, do not retry, file an issue.

If acquire returns exit 10 (race lost — issue held by a concurrent pipeline), skip and proceed to the next issue. If exit 11 (filesystem error), abort the sprint.
EOF
)

# Emit deny envelope. Escape for JSON: backslashes first, then quotes, then
# newlines. Mirrors block-unsafe-project.sh / block-main-edits.sh.
ESC="${STOP_MSG//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESC"
exit 0
