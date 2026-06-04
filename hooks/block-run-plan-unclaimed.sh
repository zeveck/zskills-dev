#!/bin/bash
# zskills-hook-version: 2026.06.0
# block-run-plan-unclaimed.sh — PreToolUse hook on Bash.
#
# Backstops the /run-plan claim-acquire prose discipline (Phase 2 of
# plans/plans-claim-chip-parity.md). Denies any Bash invocation of
# create-worktree.sh / ensure-worktree.sh whose RESOLVED branch matches
# one of the THREE /run-plan branch shapes (D7):
#   - cp-<slug>                  (finish-mode cherry-pick)
#   - cp-<slug>-phase-<N>        (single-phase cherry-pick, multi-digit)
#   - ${BRANCH_PREFIX}<slug>     (PR mode; BRANCH_PREFIX from config)
# ... and lacks a matching ${MAIN_ROOT}/.zskills/claims/plan-<slug>/.
#
# All three cp-shapes resolve to the SAME plan-scoped claim dir
# (plan-<slug>/, NOT plan-<slug>-phase-N/) — the regex captures slug
# non-greedily so the optional -phase-<N> tail is discarded.
#
# Hook contract:
#   - Reads PreToolUse JSON envelope from stdin (tool_name, tool_input.command).
#   - Filters: only Bash tool calls; only commands invoking
#     (create-worktree|ensure-worktree)\.sh.
#   - Argv tokenisation is Python shlex (NOT regex over the command string).
#   - Computes branch name via create-worktree.sh's documented precedence:
#       --branch-name <v>  OVERRIDES  --prefix-<slug>  OVERRIDES  wt-<slug>
#   - Reads BRANCH_PREFIX from ${CLAUDE_PROJECT_DIR}/.claude/zskills-config.json
#     execution.branch_prefix (default "feat/") via inline Python json.
#   - Tries TWO regexes:
#       cp-variant:  ^(cp-)([a-z0-9][a-z0-9-]*?)(-phase-[0-9]+)?$
#       pr-variant:  ^(<escaped-branch-prefix>)([a-z0-9][a-z0-9-]*)$
#   - Sources zskills-paths.sh inline (via env passthrough) to resolve
#     ZSKILLS_PLANS_DIR for the slug-is-real-plan-file pass-through.
#   - Plan-file pass-through: if no ${ZSKILLS_PLANS_DIR}/<slug>.md exists,
#     the branch is a non-plan feature branch — pass through silently.
#   - On claim-absent: emits a PreToolUse deny envelope with recovery
#     instructions citing the exact `claim-plan.sh acquire` command.
#   - Pass-through: branch doesn't match the patterns, OR slug isn't a
#     real plan file, OR sanitisation rejects the slug.
#
# Subagent composition: once registered in .claude/settings.json, this
# hook fires on EVERY Bash tool call from BOTH the orchestrator AND
# implementer/verifier subagents. The hook is filter-scoped to the two
# script names; subagent Bash calls that don't invoke them are pass-through.
#
# NOTE: Per plan R2.5, the [0-9]+ validator pattern from the issue-side
# hook is NOT applicable — plan slugs are kebab-case, not integers. The
# slug validation here is a kebab-case regex match, not numeric.

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
  echo "block-run-plan-unclaimed.sh: WARN no working Python 3 found; hook is no-op — set ZSKILLS_PYTHON" >&2
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
case "$CMD" in
  *create-worktree.sh*|*ensure-worktree.sh*) ;;
  *) exit 0 ;;
esac

# ── Argv-walk via Python shlex (same shape as block-fix-issue-unclaimed.sh) ──
WALK=$("$PYTHON" - <<'PY' "$CMD"
import shlex, sys
cmd_str = sys.argv[1]
try:
    argv = shlex.split(cmd_str)
except ValueError:
    print("BRANCH=")
    print("SLUG=")
    sys.exit(0)

prefix = None
branch_name = None
positionals = []

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
        if i + 1 < n and not argv[i + 1].startswith("--"):
            i += 2
            continue
        i += 1
        continue
    positionals.append(tok)
    i += 1

slug = positionals[-1] if positionals else None

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
while IFS= read -r line; do
  case "$line" in
    BRANCH=*) BRANCH="${line#BRANCH=}" ;;
  esac
done <<< "$WALK"

[ -z "$BRANCH" ] && exit 0

# ── Resolve MAIN_ROOT (DA4.1 / DA7 symmetry with claim-plan.sh) ──────────
MAIN_ROOT=""
if COMMON_DIR=$(git rev-parse --git-common-dir 2>&1) && [ -n "$COMMON_DIR" ]; then
  if RESOLVED=$(cd "$COMMON_DIR/.." 2>&1 && pwd); then
    MAIN_ROOT="$RESOLVED"
  fi
fi
if [ -z "$MAIN_ROOT" ]; then
  MAIN_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# ── Read branch_prefix from config (D7 R2.1 option (b)) ──────────────────
# Default "feat/" matches the canonical preset. Inline Python json keeps
# the hook's "no jq" discipline.
CONFIG_FILE="${CLAUDE_PROJECT_DIR:-$MAIN_ROOT}/.claude/zskills-config.json"
BRANCH_PREFIX=$("$PYTHON" - <<PY "$CONFIG_FILE"
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f).get("execution", {})
    bp = d.get("branch_prefix")
    print(bp if bp else "feat/")
except Exception:
    print("feat/")
PY
)
[ -z "$BRANCH_PREFIX" ] && BRANCH_PREFIX="feat/"

# ── Match against the THREE branch shapes ────────────────────────────────
# Use Python regex for non-greedy capture + re.escape on prefix.
MATCH=$("$PYTHON" - <<PY "$BRANCH" "$BRANCH_PREFIX"
import re, sys
branch, branch_prefix = sys.argv[1], sys.argv[2]
# cp-variant (covers cp-<slug> AND cp-<slug>-phase-<N>):
m = re.match(r'^(cp-)([a-z0-9][a-z0-9-]*?)(-phase-[0-9]+)?$', branch)
if m:
    print("SLUG=" + m.group(2))
    sys.exit(0)
# pr-variant: ${BRANCH_PREFIX}<slug>
m = re.match(r'^(' + re.escape(branch_prefix) + r')([a-z0-9][a-z0-9-]*)$', branch)
if m:
    print("SLUG=" + m.group(2))
    sys.exit(0)
print("SLUG=")
PY
)

SLUG=""
case "$MATCH" in
  SLUG=*) SLUG="${MATCH#SLUG=}" ;;
esac

# No regex match -> not a /run-plan branch shape -> pass through.
[ -z "$SLUG" ] && exit 0

# Defensive: post-match validation (kebab-case). Should always pass given
# the regex, but guard against shlex pathology / future regex edits.
if ! [[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "block-run-plan-unclaimed.sh: WARN malformed slug '$SLUG' on branch '$BRANCH' — allowing" >&2
  exit 0
fi

# ── Resolve plans_dir + slug-is-real-plan-file pass-through ──────────────
# Source zskills-paths.sh to honour custom ZSKILLS_PLANS_DIR. Sourcing in
# a subshell so the hook's environment stays clean.
PLANS_DIR_RESOLVED=$(
  # Lane-portable resolution (W1.4 pattern 2): plugin lane resolves
  # zskills-paths.sh under ${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/...;
  # /update-zskills lane resolves it under the mirror
  # (.claude/skills/update-zskills/...), then the zskills source-tree
  # (skills/update-zskills/...).
  ZSK_PATHS=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    ZSK_PATHS="${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  if [ -z "$ZSK_PATHS" ]; then
    ZSK_PATHS="${MAIN_ROOT}/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  if [ ! -f "$ZSK_PATHS" ]; then
    ZSK_PATHS="${MAIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  if [ -f "$ZSK_PATHS" ]; then
    CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$MAIN_ROOT}" ZSKILLS_PATHS_ROOT="$MAIN_ROOT" \
      bash -c ". '$ZSK_PATHS' >/dev/null 2>&1; echo \"\$ZSKILLS_PLANS_DIR\""
  else
    echo "${MAIN_ROOT}/plans"
  fi
)
[ -z "$PLANS_DIR_RESOLVED" ] && PLANS_DIR_RESOLVED="${MAIN_ROOT}/plans"

PLAN_FILE="${PLANS_DIR_RESOLVED}/${SLUG}.md"
if [ ! -f "$PLAN_FILE" ]; then
  # Branch matched a /run-plan-like shape but there's no plan file. This
  # is a feature branch for non-plan work — pass through silently.
  exit 0
fi

# ── Claim-presence check ─────────────────────────────────────────────────
CLAIM_DIR="${MAIN_ROOT}/.zskills/claims/plan-${SLUG}"
if [ -d "$CLAIM_DIR" ]; then
  exit 0
fi

# ── Deny envelope ────────────────────────────────────────────────────────
# Lane-portable recovery-command path (W1.4 pattern 2 / F-DA1-7): on the
# plugin lane the recovery command must cite
# ${CLAUDE_PLUGIN_ROOT}/skills/run-plan/scripts/claim-plan.sh; on the
# /update-zskills lane it cites ${MAIN_ROOT}/.claude/skills/run-plan/...
# (the mirror). Resolve to whichever exists so the agent is told a command
# that actually resolves on its install lane.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/run-plan/scripts/claim-plan.sh" ]; then
  CLAIM_PLAN_PATH="${CLAUDE_PLUGIN_ROOT}/skills/run-plan/scripts/claim-plan.sh"
else
  CLAIM_PLAN_PATH="${MAIN_ROOT}/.claude/skills/run-plan/scripts/claim-plan.sh"
fi
STOP_MSG=$(cat <<EOF
STOP: create-worktree.sh for /run-plan branch '${BRANCH}' (plan slug '${SLUG}') denied — no claim found at ${MAIN_ROOT}/.zskills/claims/plan-${SLUG}/.

The /run-plan dispatch fence MUST call:

  bash ${CLAIM_PLAN_PATH} acquire ${SLUG} --pipeline-id "run-plan.${SLUG}"

immediately above the create-worktree.sh invocation. If this hook fired during a /run-plan invocation, the SKILL.md prose has drifted — STOP, do not retry, file an issue.

If acquire returns exit 10 (race lost — plan held by a concurrent pipeline), the plan is already in flight; do not double-dispatch. If exit 11 (filesystem error), abort the run.
EOF
)

ESC="${STOP_MSG//\\/\\\\}"
ESC="${ESC//\"/\\\"}"
ESC="${ESC//$'\n'/\\n}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$ESC"
exit 0
