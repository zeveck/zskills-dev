#!/usr/bin/env bash
# scripts/porting/zskills-runner.sh — unified foreground runner for Codex
# run-plan execution (CODEX_PORT_PLAN Phase 1, WI 1.1).
#
# THE SCHEDULING STORY (settled decision 5): the foreground runner IS the
# scheduler. Two modes, one durable-evidence validation ladder:
#   finish auto   loop-until-plan-done — one fresh `codex exec` child per
#                 phase, durable-evidence gates between chunks, output
#                 STREAMED live to the attached terminal.
#   every <SCHED> sleep-loop firing `codex exec resume` children into ONE
#                 durable named session (full history readable via
#                 `codex resume`), streamed live.
# Never fire-and-forget: every child's output is streamed to the attached
# terminal AND captured — a running plan must never look hung from the
# invoking shell.
#
# PROVENANCE: base = the zskills-codex fork's runner chassis (forensic
# per-chunk logging: argv.json / before-state / after-state / events.jsonl /
# summary.json; --dry-run; refusal preflight; documented exit-code taxonomy)
# plus the FIFTEEN named changes from the CODEX_PORT_PLAN unified runner
# spec. Each change is tagged where it lands:
#    1 STREAM              pumper tee — live terminal + files (run_child)
#    2 STOP-IN-LOOP        per-plan stop marker checked before EVERY
#                          chunk/fire; exit 31 `stopped`
#    3 STRICT-SHELL        `set -euo pipefail` from the top
#    4 STABLE-TRACKING-ID  TRACKING_ID from the plan basename (matches
#                          skills/run-plan/SKILL.md); exported to the child;
#                          marker_changed content-hash staleness; plan_key
#                          only for locks/logs
#    5 LANDING-POSITIONAL  `run-plan <plan> finish auto [direct|cherry-pick|pr]`
#    6 PR-DUAL-ROOT        artifact root vs tracking root split; stale-PR-root
#                          triage; --add-dir <worktree-parent> from config
#    7 SANDBOX-TRIAGE      explain_child_failure — bwrap grep, explicit
#                          remediation, NEVER auto-escalate
#    8 CURRENT-FORMAT-VALIDATORS  frontmatter-first plan-complete detection,
#                          narrative refusal, config-resolved report path,
#                          current report patterns, tests-run required,
#                          final-verify pair, .zskills/landed consumption
#    9 PHASE-5C-CONTRACT   handoff.run-plan.<tid> kept as prompt-reinforced
#                          ported-skill contract (guide recipe in Phase 4)
#   10 CLAIMS              inlined minimal claim semantics (mkdir + JSON
#                          metadata under <main-root>/.zskills/claims/)
#   11 EVERY-MODE          parse_schedule + sleep loop + durable session
#                          persistence; session loss = hard stop (exit 32)
#   12 JSON+SCHEMA         --json / -o kept; thread_id + usage into
#                          summary.json; optional --output-schema self-report
#                          cross-checked (claim-evidence-mismatch)
#   13 GATE-UNIFY          delegates to sibling zskills-gate.sh
#   14 INVARIANTS-REFORK   delegates to sibling post-run-invariants-codex.sh
#   15 CONFIG              ported-tree discovery order, cross-lane conflict
#                          check, minutes-based timeouts + env test overrides
#
# Exit code 26 (child-failed) is a deliberate DEVIATION from both forks'
# raw-child-rc passthrough: a child that itself exits 2, 20-25, 31, or 124
# must not masquerade as a runner verdict. The raw child rc and its last
# stderr lines are forensics, recorded in chunk-NNN.summary.json.
# `runner_stop_reason` in the final chunk summary — echoed as the runner's
# last stderr line — is the AUTHORITATIVE stop classification; exit codes
# are a convenience for shell callers.
#
# The runner is repo-agnostic: it requires nothing from the target repo
# beyond the `.zskills/` state contract. Tests never invoke real codex
# (--codex-bin points at tests/mocks/fake-codex.sh).
#
# PORTABILITY: BSD/macOS + Git-Bash/MSYS discipline — no `readlink -f`, no
# GNU-only `mktemp` suffix opts, no `date -d`, no `realpath -m`, no bash-4-isms
# (no associative arrays / mapfile; empty arrays expanded with the
# ${arr[@]+...} guard); temp/state under the repo's .zskills/; JSON via
# Python 3 heredocs (no jq — repo convention).

set -euo pipefail  # change 3: STRICT-SHELL

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE_SCRIPT="$SCRIPT_DIR/zskills-gate.sh"
INVARIANTS_SCRIPT="$SCRIPT_DIR/post-run-invariants-codex.sh"

# ---------------------------------------------------------------------------
# Python resolution — inlined verbatim from hooks/_lib/resolve-python.sh
# (source of truth; byte-equality enforced by tests/test-hook-helper-drift.sh,
# where this script is registered as a RESOLVE_PYTHON_CONSUMERS entry).
# ---------------------------------------------------------------------------

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

usage() {
  cat <<'EOF'
Usage:
  zskills-runner.sh --help
  zskills-runner.sh status <plan> [--repo <path>]
  zskills-runner.sh stop   <plan> [--repo <path>]
  zskills-runner.sh next   <plan> [--repo <path>]
  zskills-runner.sh run-plan <plan> finish auto [direct|cherry-pick|pr] [options]
  zskills-runner.sh run-plan <plan> every <SCHEDULE> [auto] [options]

Modes:
  finish auto      Loop until the plan is complete: one fresh `codex exec`
                   child per phase, durable-evidence validation between
                   chunks, output streamed live. Optional positional landing
                   mode (direct|cherry-pick|pr) overrides execution.landing.
  every <SCHEDULE> Sleep-loop scheduler: fires `codex exec resume` children
                   into ONE durable named session. SCHEDULE accepts
                   `<N>m|<N>h|<N>d` (optionally prefixed `every `),
                   `every hour`, and `weekday|day at H[:MM][am|pm]`.
                   Optional `auto` pre-authorizes autonomous landing (it
                   changes ONLY the per-fire prompt text, never the
                   validation ladder). Session loss is a HARD STOP (exit 32)
                   — never a silent fallback to a fresh exec.
  status           Print the resolved runner state for a plan (read-only).
  stop             Write the per-plan stop marker; the running loop honors
                   it before the next chunk/fire (exit 31).
  next             Print the next scheduled fire time, session id, and last
                   validation verdict for a plan (every-mode state).

Options:
  --repo <path>               Git repository to run from. Default: cwd.
  --dry-run                   Resolve config, print the child argv and the
                              full chunk prompt; mutate NOTHING; exit 0.
  --max-chunks <n>            Override runner.max_chunks (default 10).
  --chunk-timeout-min <n>     Override runner.chunk_timeout_minutes (default 90).
  --idle-timeout-min <n>      Override runner.idle_timeout_minutes (default 15).
  --log-dir <path>            Override runner.log_dir (default .zskills/logs).
  --sandbox <mode>            read-only | workspace-write | danger-full-access.
  --approval-policy <policy>  never | on-request | untrusted.
  --codex-bin <path>          Codex executable (default: $CODEX_BIN or codex).
  --codex-arg <arg>           Extra child codex arg. Repeatable. Scanned for
                              dangerous args — the bypass flag is refused
                              here too, not only as a direct flag.
  --output-schema             Enable the structured self-report cross-check
                              (child gets --output-schema; the self-report is
                              cross-checked against durable evidence;
                              discrepancy = claim-evidence-mismatch).
  --allow-direct-unattended   Permit landing mode `direct` for this run.

Safety:
  - Refuses --dangerously-bypass-approvals-and-sandbox (as a flag AND
    smuggled via --codex-arg). NEVER auto-escalates the sandbox.
  - Refuses non-git repos, unsafe git residue (merge/rebase/cherry-pick,
    conflicts, stashes, stale worktree registry), un-ignored tracking state,
    narrative plans with no tracker, and foreign-held plan claims.
  - Environment overrides for tests: ZSKILLS_RUNNER_TIMEOUT_SECONDS,
    ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS.

Exit codes:
  0    plan complete (or subcommand success)
  2    refusal / preflight die (incl. dangerous-bypass flag, lock contention,
       git residue, narrative-plan refusal, claim foreign-held)
  20   no durable progress detected
  21   handoff marker missing after progress / premature final markers mid-plan
  22   report invalid or missing / stale required marker (content hash unchanged)
  23   tracking-id underivable / verifier marker evidence missing
       (incl. claim-evidence-mismatch on the structured self-report)
  24   gate script failed (incl. terminal landing failure: conflict|pr-failed)
  25   dirty non-.zskills artifacts
  26   child-failed (child nonzero exit — raw child rc + last stderr recorded
       in chunk-NNN.summary.json; incl. sandbox-unavailable)
  30   max-chunks exhausted
  31   stopped (stop marker honored)
  32   session-lost (`exec resume` failed — every-mode hard stop)
  124  chunk wall timeout
  125  chunk idle timeout

Every terminal exit prints an authoritative `runner_stop_reason=<reason>`
line on stderr (also recorded in the final chunk summary when one exists).
EOF
}

# ── terminal-exit helpers ────────────────────────────────────────────────────
LAST_SUMMARY_FILE=""

emit_stop_reason() {
  # The AUTHORITATIVE stop classification — the runner's last stderr line.
  echo "runner_stop_reason=$1" >&2
}

record_stop_reason_in_summary() {
  local reason="$1"
  [ -n "$LAST_SUMMARY_FILE" ] && [ -f "$LAST_SUMMARY_FILE" ] || return 0
  "$PYTHON" - "$LAST_SUMMARY_FILE" "$reason" <<'PY'
import json, sys
path, reason = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}
data["runner_stop_reason"] = reason
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

die() {
  # Refusal / preflight failure — exit 2.
  echo "zskills-runner: $*" >&2
  record_stop_reason_in_summary "refused"
  emit_stop_reason "refused"
  exit 2
}

fail_run() {
  # Terminal run failure with a mapped exit code.
  local rc="$1" reason="$2"
  shift 2
  [ $# -eq 0 ] || echo "zskills-runner: $*" >&2
  record_stop_reason_in_summary "$reason"
  emit_stop_reason "$reason"
  exit "$rc"
}

finish_ok() {
  local reason="$1"
  record_stop_reason_in_summary "$reason"
  emit_stop_reason "$reason"
  exit 0
}

PYTHON="$(zskills_resolve_python || true)"
if [ -z "$PYTHON" ]; then
  echo "zskills-runner: no working Python 3 interpreter found (install Python 3 or set ZSKILLS_PYTHON)" >&2
  echo "runner_stop_reason=refused" >&2
  exit 2
fi

# ── argument parsing ─────────────────────────────────────────────────────────
MODE=""            # status | stop | next | run-plan
RUN_MODE=""        # finish-auto | every
PLAN=""
SCHEDULE=""
EVERY_AUTO=0
LANDING_ARG=""
REPO="."
DRY_RUN=0
MAX_CHUNKS=""
CHUNK_TIMEOUT_MINUTES=""
IDLE_TIMEOUT_MINUTES=""
LOG_DIR=""
SANDBOX=""
APPROVAL_POLICY=""
ALLOW_DIRECT_UNATTENDED=""
OUTPUT_SCHEMA_CHECK=""
CODEX_BIN="${CODEX_BIN:-codex}"
EXTRA_CODEX_ARGS=()

if [ $# -eq 0 ]; then
  usage >&2
  # Mapped code 2 (refusal) — the authoritative stop-reason line accompanies
  # EVERY mapped exit code, including this pre-parse usage refusal.
  echo "runner_stop_reason=refused" >&2
  exit 2
fi

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
  status|stop|next|run-plan)
    MODE="$1"
    shift
    ;;
  *)
    die "unknown command '$1' (status|stop|next|run-plan)"
    ;;
esac

case "$MODE" in
  status|stop|next)
    [ $# -gt 0 ] || die "$MODE requires a plan"
    PLAN="$1"
    shift
    ;;
  run-plan)
    [ $# -ge 3 ] || die "run-plan requires: <plan> finish auto [direct|cherry-pick|pr] OR <plan> every <SCHEDULE> [auto]"
    PLAN="$1"
    case "$2" in
      finish)
        [ "$3" = "auto" ] || die "run-plan <plan> finish requires the positional 'auto'"
        RUN_MODE="finish-auto"
        shift 3
        ;;
      every)
        RUN_MODE="every"
        SCHEDULE="$3"
        shift 3
        if [ $# -gt 0 ] && [ "$1" = "auto" ]; then
          EVERY_AUTO=1
          shift
        fi
        ;;
      *)
        die "run-plan supports: finish auto [direct|cherry-pick|pr] OR every <SCHEDULE> [auto]"
        ;;
    esac
    ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    # change 5: LANDING-POSITIONAL — upstream grammar accepts the landing
    # mode as a bare positional token after `finish auto`.
    direct|cherry-pick|pr)
      [ "$RUN_MODE" = "finish-auto" ] || die "positional landing mode '$1' is only valid after 'finish auto'"
      LANDING_ARG="$1"; shift ;;
    --repo)               REPO="${2:?--repo requires a value}"; shift 2 ;;
    --dry-run)            DRY_RUN=1; shift ;;
    --max-chunks)         MAX_CHUNKS="${2:?--max-chunks requires a value}"; shift 2 ;;
    --chunk-timeout-min)  CHUNK_TIMEOUT_MINUTES="${2:?--chunk-timeout-min requires a value}"; shift 2 ;;
    --idle-timeout-min)   IDLE_TIMEOUT_MINUTES="${2:?--idle-timeout-min requires a value}"; shift 2 ;;
    --log-dir)            LOG_DIR="${2:?--log-dir requires a value}"; shift 2 ;;
    --sandbox)            SANDBOX="${2:?--sandbox requires a value}"; shift 2 ;;
    --approval-policy)    APPROVAL_POLICY="${2:?--approval-policy requires a value}"; shift 2 ;;
    --codex-bin)          CODEX_BIN="${2:?--codex-bin requires a value}"; shift 2 ;;
    --codex-arg)          EXTRA_CODEX_ARGS+=("${2:?--codex-arg requires a value}"); shift 2 ;;
    --output-schema)      OUTPUT_SCHEMA_CHECK=true; shift ;;
    --allow-direct-unattended) ALLOW_DIRECT_UNATTENDED=true; shift ;;
    --dangerously-bypass-approvals-and-sandbox)
      die "refused: --dangerously-bypass-approvals-and-sandbox is never accepted by zskills-runner (the runner NEVER escalates the sandbox)"
      ;;
    *)
      die "unknown option '$1'"
      ;;
  esac
done

# Dangerous-arg scan over --codex-arg values (the bypass flag must not be
# smuggled to the child either).
for extra in ${EXTRA_CODEX_ARGS[@]+"${EXTRA_CODEX_ARGS[@]}"}; do
  case "$extra" in
    *dangerously-bypass-approvals-and-sandbox*)
      die "refused: --dangerously-bypass-approvals-and-sandbox smuggled via --codex-arg ('$extra') is never accepted by zskills-runner"
      ;;
  esac
done

# Numeric option validation (fail-closed on garbage; config-sourced values
# are re-checked after resolution below).
for numopt in "$MAX_CHUNKS" "$CHUNK_TIMEOUT_MINUTES" "$IDLE_TIMEOUT_MINUTES"; do
  case "$numopt" in
    *[!0-9]*) die "numeric option expected, got '$numopt'" ;;
  esac
done

# ── repo + config resolution (change 15: CONFIG) ─────────────────────────────
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "repo is not a git worktree: $REPO"
REPO_ROOT=$(git -C "$REPO" rev-parse --show-toplevel)
REPO_ROOT=$(cd "$REPO_ROOT" && pwd)
PROJECT_NAME=$(basename "$REPO_ROOT")

# Discovery order per the ported-tree layout: .agents/ → repo root → .codex/
# → legacy .claude/. FIRST present file is the active config. Cross-lane
# conflict check (cc fork, generalized): when MULTIPLE candidate configs are
# present and disagree on execution.landing or execution.main_protected, die
# — a split-brain config must be resolved by a human, never silently
# tie-broken.
CONFIG_LINES=$("$PYTHON" - "$REPO_ROOT" <<'PY'
import json, os, sys

root = sys.argv[1]
candidates = [
    ".agents/zskills-config.json",
    "zskills-config.json",
    ".codex/zskills-config.json",
    ".claude/zskills-config.json",
]
present = []
for rel in candidates:
    path = os.path.join(root, rel)
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as f:
                cfg = json.load(f)
        except Exception:
            cfg = {}
        present.append((rel, cfg))

def nested(cfg, dotted):
    cur = cfg
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur

# Cross-lane conflict check.
for key in ("execution.landing", "execution.main_protected"):
    values = [(rel, nested(cfg, key)) for rel, cfg in present]
    values = [(rel, v) for rel, v in values if v is not None]
    if len({json.dumps(v, sort_keys=True) for _, v in values}) > 1:
        detail = ", ".join(f"{rel}={v!r}" for rel, v in values)
        print(f"CONFIG_CONFLICT|{key}|{detail}")
        sys.exit(3)

config_path = present[0][0] if present else ""
config = present[0][1] if present else {}

def get(dotted, default):
    value = nested(config, dotted)
    return default if value is None else value

def emit(key, value):
    if isinstance(value, bool):
        value = "true" if value else "false"
    print(f"{key}={value}")

emit("config_path", config_path)
emit("landing", get("execution.landing", "cherry-pick"))
emit("base_branch", get("execution.base_branch", "main"))
emit("remote", get("execution.remote", "origin"))
emit("max_chunks", get("runner.max_chunks", 10))
emit("chunk_timeout_minutes", get("runner.chunk_timeout_minutes", 90))
emit("idle_timeout_minutes", get("runner.idle_timeout_minutes", 15))
emit("log_dir", get("runner.log_dir", ".zskills/logs"))
emit("sandbox", get("runner.sandbox", "workspace-write"))
emit("approval_policy", get("runner.approval_policy", "never"))
emit("allow_direct_unattended", get("runner.allow_direct_unattended", False))
emit("output_schema", get("runner.output_schema", False))
emit("worktree_parent", get("runner.worktree_parent_dir", ""))
emit("reports_dir", get("output.reports_dir", ""))
PY
) || {
  case "$CONFIG_LINES" in
    CONFIG_CONFLICT\|*)
      IFS='|' read -r _ conflict_key conflict_detail <<EOF
$CONFIG_LINES
EOF
      die "cross-lane config conflict on $conflict_key: $conflict_detail — resolve to a single value before running"
      ;;
    *)
      die "config resolution failed"
      ;;
  esac
}

cfg_value() {
  printf '%s\n' "$CONFIG_LINES" | awk -F= -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }'
}

CONFIG_FILE=$(cfg_value config_path)
EXECUTION_LANDING="${LANDING_ARG:-$(cfg_value landing)}"
BASE_BRANCH=$(cfg_value base_branch)
REMOTE=$(cfg_value remote)
[ -n "$MAX_CHUNKS" ] || MAX_CHUNKS=$(cfg_value max_chunks)
[ -n "$CHUNK_TIMEOUT_MINUTES" ] || CHUNK_TIMEOUT_MINUTES=$(cfg_value chunk_timeout_minutes)
[ -n "$IDLE_TIMEOUT_MINUTES" ] || IDLE_TIMEOUT_MINUTES=$(cfg_value idle_timeout_minutes)
[ -n "$LOG_DIR" ] || LOG_DIR=$(cfg_value log_dir)
[ -n "$SANDBOX" ] || SANDBOX=$(cfg_value sandbox)
[ -n "$APPROVAL_POLICY" ] || APPROVAL_POLICY=$(cfg_value approval_policy)
[ -n "$ALLOW_DIRECT_UNATTENDED" ] || ALLOW_DIRECT_UNATTENDED=$(cfg_value allow_direct_unattended)
[ -n "$OUTPUT_SCHEMA_CHECK" ] || OUTPUT_SCHEMA_CHECK=$(cfg_value output_schema)
WORKTREE_PARENT=$(cfg_value worktree_parent)
[ -n "$WORKTREE_PARENT" ] || WORKTREE_PARENT="${TMPDIR:-/tmp}"
WORKTREE_PARENT="${WORKTREE_PARENT%/}"
REPORTS_DIR_REL=$(cfg_value reports_dir)
# allow-hardcoded: docs/reports reason: built-in fallback mirroring zskills-paths.sh output.reports_dir default, used only when no discovered config sets the key
[ -n "$REPORTS_DIR_REL" ] || REPORTS_DIR_REL="docs/reports"

case "$EXECUTION_LANDING" in
  direct|cherry-pick|pr) ;;
  *) die "invalid landing mode '$EXECUTION_LANDING'" ;;
esac
case "$SANDBOX" in
  read-only|workspace-write|danger-full-access) ;;
  *) die "unsupported sandbox '$SANDBOX'" ;;
esac
case "$APPROVAL_POLICY" in
  never|on-request|untrusted) ;;
  *) die "unsupported approval policy '$APPROVAL_POLICY'" ;;
esac
case "$MAX_CHUNKS$CHUNK_TIMEOUT_MINUTES$IDLE_TIMEOUT_MINUTES" in
  *[!0-9]*) die "max-chunks / timeout values must be non-negative integers" ;;
esac

# ── identity derivation (change 4: STABLE-TRACKING-ID) ───────────────────────
# Repo-relative plan path (BSD-safe; no realpath -m).
REL_PLAN=$("$PYTHON" - "$REPO_ROOT" "$PLAN" <<'PY'
import os, sys
root, plan = sys.argv[1:3]
path = plan if os.path.isabs(plan) else os.path.join(root, plan)
print(os.path.relpath(os.path.abspath(path), root).replace(os.sep, "/"))
PY
)
case "$REL_PLAN" in
  ../*) die "plan file is outside the repo: $PLAN" ;;
esac
PLAN_PATH="$REPO_ROOT/$REL_PLAN"

# Stable tracking id — the SAME derivation as skills/run-plan/SKILL.md
# ("Idempotent re-entry check": basename, .md stripped, upper/underscore
# folded). The per-chunk timestamp ids and the "reuse the newest handoff
# suffix" child judgment from the codex fork are deliberately DROPPED.
TRACKING_ID=$(basename "$REL_PLAN" .md | tr '[:upper:]_' '[:lower:]-')
[ -n "$TRACKING_ID" ] || die "tracking id underivable from plan path '$PLAN'"

# Pipeline id, sanitized with the SAME rules as
# skills/create-worktree/scripts/sanitize-pipeline-id.sh (charset
# [a-zA-Z0-9._-], 128-char cap, empty refused).
sanitize_pipeline_id() {
  if [ -z "${1:-}" ]; then
    die "empty pipeline id — refusing (would create flat tracking markers)"
  fi
  printf '%s' "$1" | tr -c 'a-zA-Z0-9._-' '_' | cut -c 1-128
}
PIPELINE_ID=$(sanitize_pipeline_id "run-plan.$TRACKING_ID")

# plan_key — slug + short hash of the repo-relative path. Used ONLY for
# locks/logs (same-basename plan disambiguation); never for tracking.
PLAN_KEY=$("$PYTHON" - "$REL_PLAN" "$TRACKING_ID" <<'PY'
import hashlib, sys
rel, tid = sys.argv[1:3]
print(f"{tid}-{hashlib.sha256(rel.encode('utf-8')).hexdigest()[:10]}")
PY
)

# ── derived paths ────────────────────────────────────────────────────────────
RUNNER_STATE_DIR="$REPO_ROOT/.zskills/runner"
STOP_MARKER="$RUNNER_STATE_DIR/$PLAN_KEY.stop"     # change 2: per-plan path
LOCK_DIR="$RUNNER_STATE_DIR/$PLAN_KEY.lock"
SESSION_FILE="$RUNNER_STATE_DIR/$PLAN_KEY.session" # change 11: durable session
STATE_FILE="$RUNNER_STATE_DIR/$PLAN_KEY.state"
TRACKING_DIR="$REPO_ROOT/.zskills/tracking/$PIPELINE_ID"  # tracking: ALWAYS repo root
PR_WORKTREE_PATH="$WORKTREE_PARENT/${PROJECT_NAME}-pr-${TRACKING_ID}"
REPORT_REL="$REPORTS_DIR_REL/plan-$TRACKING_ID.md"
case "$LOG_DIR" in
  /*) LOG_ROOT="$LOG_DIR" ;;
  *)  LOG_ROOT="$REPO_ROOT/$LOG_DIR" ;;
esac

# change 6: PR-DUAL-ROOT — plan/report are validated at the ARTIFACT root
# (the PR worktree when it exists, else the repo root); tracking is always
# at the repo root.
artifact_root() {
  if [ "$EXECUTION_LANDING" = "pr" ] && [ -d "$PR_WORKTREE_PATH" ]; then
    printf '%s\n' "$PR_WORKTREE_PATH"
  else
    printf '%s\n' "$REPO_ROOT"
  fi
}
active_plan_path() {
  printf '%s/%s\n' "$(artifact_root)" "$REL_PLAN"
}
active_report_path() {
  case "$REPORTS_DIR_REL" in
    /*) printf '%s/plan-%s.md\n' "$REPORTS_DIR_REL" "$TRACKING_ID" ;;
    *)  printf '%s/%s\n' "$(artifact_root)" "$REPORT_REL" ;;
  esac
}

# ── plan-state detection (change 8: CURRENT-FORMAT-VALIDATORS) ───────────────
# Emits `tracker=<csv-of-formats-or-none>` and `complete=true|false`.
# Frontmatter `status: complete` is the AUTHORITATIVE terminal signal; else
# the tracker formats are checked structurally: progress-tracker table rows,
# checklist boxes, numbered `## Phase` sections. Narrative-only plans have
# no tracker — `finish auto`/`every` refuse them at preflight (never guess).
plan_state() {
  local file="$1"
  if [ ! -f "$file" ]; then
    printf 'tracker=missing\ncomplete=false\n'
    return 0
  fi
  "$PYTHON" - "$file" <<'PY'
import re, sys

with open(sys.argv[1], encoding="utf-8") as f:
    text = f.read()

formats = []

# Frontmatter status field (authoritative terminal signal when 'complete').
fm_complete = False
fm = re.match(r"\A---\n(.*?\n)---\n", text, re.S)
if fm:
    m = re.search(r"^status:\s*(.+?)\s*$", fm.group(1), re.M)
    if m:
        formats.append("frontmatter")
        fm_complete = m.group(1).strip().lower() == "complete"

# Progress-tracker table rows (structural | Phase ... | parse).
table_done = table_todo = 0
for line in text.splitlines():
    if not line.lstrip().startswith("|"):
        continue
    if re.search(r"✅|(^|\|)\s*Done\s*(\||$)", line):
        table_done += 1
    if re.search(r"⬜|⬚|🟡|Not Started|In Progress", line):
        table_todo += 1
if table_done + table_todo > 0:
    formats.append("table")

# Checklist boxes.
boxes_done = len(re.findall(r"^\s*[-*] \[[xX]\]", text, re.M))
boxes_todo = len(re.findall(r"^\s*[-*] \[ \]", text, re.M))
if boxes_done + boxes_todo > 0:
    formats.append("checkbox")

# Numbered phase sections. A tracker format for DETECTION (not narrative),
# but not mechanically completable — completion for section-only plans
# requires the frontmatter terminal signal.
sections = re.findall(r"^#{2,3}\s+Phase\b", text, re.M)
if sections:
    formats.append("sections")

if fm_complete:
    complete = True
elif table_done + table_todo > 0:
    complete = table_todo == 0 and table_done > 0
elif boxes_done + boxes_todo > 0:
    complete = boxes_todo == 0 and boxes_done > 0
else:
    complete = False

print("tracker=" + (",".join(formats) if formats else "none"))
print("complete=" + ("true" if complete else "false"))
PY
}

state_value() {
  printf '%s\n' "$1" | awk -F= -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }'
}

plan_is_complete() {
  local ps
  ps=$(plan_state "$(active_plan_path)")
  [ "$(state_value "$ps" complete)" = "true" ]
}

# ── snapshot machinery (durable-evidence hashes) ─────────────────────────────
# Writes plan_hash / report_hash / marker name CSV / per-marker content-hash
# CSV for the validation ladder. All hashing via Python (sha256sum is
# GNU-coreutils-only; BSD/macOS ships shasum instead).
collect_snapshot() {
  local out_file="$1"
  "$PYTHON" - "$(active_plan_path)" "$(active_report_path)" "$TRACKING_DIR" > "$out_file" <<'PY'
import hashlib, os, sys

plan, report, tracking = sys.argv[1:4]

def file_hash(path):
    if not os.path.isfile(path):
        return "<missing>"
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()

print(f"plan_hash={file_hash(plan)}")
print(f"report_hash={file_hash(report)}")

names = []
pairs = []
if os.path.isdir(tracking):
    for name in sorted(os.listdir(tracking)):
        path = os.path.join(tracking, name)
        if os.path.isfile(path):
            names.append(name)
            pairs.append(f"{name}:{file_hash(path)}")
print("tracking_markers=" + ",".join(names))
print("tracking_marker_hashes=" + ",".join(pairs))
PY
}

file_value() {
  awk -F= -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$1"
}

# ── status / stop / next (read-only + marker write) ──────────────────────────
print_resolved() {
  local ps
  cat <<EOF
mode=$MODE
run_mode=${RUN_MODE:-<none>}
repo=$REPO_ROOT
plan=$REL_PLAN
plan_path=$PLAN_PATH
tracking_id=$TRACKING_ID
pipeline_id=$PIPELINE_ID
plan_key=$PLAN_KEY
tracking_dir=$TRACKING_DIR
artifact_root=$(artifact_root)
report_path=$(active_report_path)
pr_worktree_path=$PR_WORKTREE_PATH
worktree_parent=$WORKTREE_PARENT
landing=$EXECUTION_LANDING
base_branch=$BASE_BRANCH
remote=$REMOTE
config=${CONFIG_FILE:-<none>}
max_chunks=$MAX_CHUNKS
chunk_timeout_minutes=$CHUNK_TIMEOUT_MINUTES
idle_timeout_minutes=$IDLE_TIMEOUT_MINUTES
log_dir=$LOG_DIR
stop_marker=$STOP_MARKER
sandbox=$SANDBOX
approval_policy=$APPROVAL_POLICY
allow_direct_unattended=$ALLOW_DIRECT_UNATTENDED
output_schema_check=$OUTPUT_SCHEMA_CHECK
codex_bin=$CODEX_BIN
schedule=${SCHEDULE:-<none>}
every_auto=$EVERY_AUTO
EOF
  ps=$(plan_state "$(active_plan_path)")
  printf '%s\n' "$ps"
}

if [ "$MODE" = "status" ]; then
  print_resolved
  if [ -f "$STOP_MARKER" ]; then
    echo "stop_marker_present=true"
  else
    echo "stop_marker_present=false"
  fi
  if [ -d "$LOCK_DIR" ]; then
    echo "lock_present=true"
  else
    echo "lock_present=false"
  fi
  if [ -f "$SESSION_FILE" ]; then
    echo "session_id=$(cat "$SESSION_FILE")"
  else
    echo "session_id=<none>"
  fi
  exit 0
fi

if [ "$MODE" = "stop" ]; then
  mkdir -p "$RUNNER_STATE_DIR"
  printf 'plan=%s\nstopped_at=%s\n' "$REL_PLAN" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STOP_MARKER"
  echo "stop marker written: $STOP_MARKER"
  echo "The running loop honors it before the next chunk/fire (exit 31)."
  exit 0
fi

if [ "$MODE" = "next" ]; then
  if [ -f "$SESSION_FILE" ]; then
    echo "session_id=$(cat "$SESSION_FILE")"
  else
    echo "session_id=<none>"
  fi
  if [ -f "$STATE_FILE" ]; then
    "$PYTHON" - "$STATE_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        state = json.load(f)
except Exception:
    print("state=<unreadable>")
    sys.exit(0)
print(f"schedule={state.get('schedule', '<none>')}")
print(f"next_fire={state.get('next_fire_iso', '<none>')}")
print(f"last_validation={state.get('last_validation', '<none>')}")
PY
  else
    echo "next_fire=<none>"
    echo "last_validation=<none>"
    echo "No every-mode state recorded for this plan."
  fi
  exit 0
fi

# ── MODE = run-plan from here on ─────────────────────────────────────────────
[ -f "$PLAN_PATH" ] || die "plan file not found: $PLAN_PATH"

# Narrative-plan refusal (change 8): a plan with NO recognizable tracker
# cannot be driven by durable-evidence gates — refuse rather than guess.
PS=$(plan_state "$PLAN_PATH")
PLAN_TRACKER=$(state_value "$PS" tracker)
if [ "$PLAN_TRACKER" = "none" ]; then
  die "narrative plan refused: $REL_PLAN has no progress tracker (no frontmatter status, no | Phase | table rows, no checklist boxes, no '## Phase' sections). '$RUN_MODE' needs a mechanical completion signal — add a tracker or drive the plan interactively."
fi

# every-mode schedule validation (change 11) — parse early so a bad
# expression refuses before any state is touched.
parse_schedule_seconds() {
  # Prints seconds until the next fire; recomputed before every fire so
  # at-time schedules (weekday/day at H:MM) stay correct.
  "$PYTHON" - "$1" <<'PY'
import re, sys
from datetime import datetime, timedelta, timezone

raw = sys.argv[1].strip()

def now():
    return datetime.now(timezone.utc).replace(microsecond=0)

if re.match(r"^every\s+hour$", raw, re.I):
    print(3600)
    sys.exit(0)
m = re.match(r"^(?:every\s+)?(\d+)\s*([mhd])$", raw, re.I)
if m:
    mult = {"m": 60, "h": 3600, "d": 86400}[m.group(2).lower()]
    seconds = int(m.group(1)) * mult
    if seconds <= 0:
        raise SystemExit("ERROR: schedule interval must be positive")
    print(seconds)
    sys.exit(0)
m = re.match(r"^(weekday|day)\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$", raw, re.I)
if m:
    kind, hour_s, minute_s, ampm = m.groups()
    hour = int(hour_s)
    minute = int(minute_s or "0")
    if ampm:
        ampm = ampm.lower()
        if hour == 12:
            hour = 0
        if ampm == "pm":
            hour += 12
    if hour > 23 or minute > 59:
        raise SystemExit("ERROR: invalid time in schedule")
    candidate = now().replace(hour=hour, minute=minute, second=0)
    if candidate <= now():
        candidate += timedelta(days=1)
    if kind.lower() == "weekday":
        while candidate.weekday() >= 5:
            candidate += timedelta(days=1)
    print(max(60, int((candidate - now()).total_seconds())))
    sys.exit(0)
raise SystemExit(f"ERROR: unsupported schedule expression: {raw}")
PY
}

if [ "$RUN_MODE" = "every" ]; then
  parse_schedule_seconds "$SCHEDULE" >/dev/null 2>/dev/null \
    || die "unsupported schedule expression: '$SCHEDULE' (accepted: <N>m|<N>h|<N>d, 'every hour', 'weekday|day at H[:MM][am|pm]')"
fi

# ── child prompt (verbatim template from the unified runner spec) ────────────
# The fake-codex harness parses the `- Label: value` lines — keep the line
# format machine-parsable. change 9 (PHASE-5C-CONTRACT): the handoff /
# final-marker contract block below reinforces what the ported run-plan
# Phase 5c writes natively.
build_chunk_prompt() {
  # $1 = first line (mode-specific run-plan invocation)
  # $2 = optional extra contract line (every-mode landing authorization)
  local first_line="$1" extra_line="${2:-}"
  local prompt
  prompt=$(cat <<EOF
$first_line

RUNNER-MANAGED CHUNK: You are running under zskills-runner.sh. Do not invoke
zskills-runner.sh again. Execute exactly one incomplete phase, then stop after
writing the required report, tracking markers, and landing evidence.

External ZSkills runner contract for this chunk:
- Repository root: $REPO_ROOT
- Active artifact root: $(artifact_root)
- Plan path: $(active_plan_path)
- Report path: $(active_report_path)
- PR worktree path: $PR_WORKTREE_PATH
- Pipeline id: $PIPELINE_ID
- Tracking directory: $TRACKING_DIR
- Tracking id: use exactly $TRACKING_ID for every marker written by this chunk.
- Environment: ZSKILLS_PIPELINE_ID=$PIPELINE_ID and ZSKILLS_TRACKING_ID=$TRACKING_ID
  are exported to this child process.
- Resolved landing mode: $EXECUTION_LANDING
- Base branch: $BASE_BRANCH
- Remote: $REMOTE
- Write run-plan markers: step.run-plan.<tid>.implement, step.run-plan.<tid>.verify,
  step.run-plan.<tid>.report.
- Write verifier markers: requires.verify-changes.<tid>,
  step.verify-changes.<tid>.tests-run, step.verify-changes.<tid>.complete,
  fulfilled.verify-changes.<tid>.
- If another phase remains: write handoff.run-plan.<tid>; do not write final
  run-plan markers.
- If the plan is complete: complete the final verify
  (requires.verify-changes.final.<tid> then fulfilled.verify-changes.final.<tid>),
  write step.run-plan.<tid>.land and fulfilled.run-plan.<tid>, and remove any stale
  handoff.run-plan.<tid>.
- Record landing state in .zskills/landed
  (status: landed|pr-ready|pr-ci-failing|conflict|pr-failed|partial|not-landed).
- The report must include a "## Phase" heading, a "**Status:**" line, and a
  "### Verification" section.
- Mark completed progress-tracker rows with exactly "✅ Done".
- Do not claim in the report that work was committed, cherry-picked, pushed, or
  landed until that git operation has actually succeeded.
- Leave no dirty project artifacts outside ignored .zskills state before exiting.
EOF
)
  if [ -n "$extra_line" ]; then
    printf '%s\n%s\n' "$prompt" "$extra_line"
  else
    printf '%s\n' "$prompt"
  fi
}

finish_auto_prompt() {
  build_chunk_prompt "run-plan $REL_PLAN finish auto $EXECUTION_LANDING"
}

every_fire_prompt() {
  # `auto` semantics (change 11): the token changes ONLY the per-fire prompt
  # text — it pre-authorizes autonomous landing — never the validation ladder.
  local auth
  if [ "$EVERY_AUTO" -eq 1 ]; then
    auth="- Landing authorization: pre-authorized (auto) — land without prompting."
  else
    auth="- Landing authorization: not pre-authorized — prepare the landing evidence but request confirmation before merging."
  fi
  build_chunk_prompt "run-plan $REL_PLAN $EXECUTION_LANDING" "$auth"
}

# ── child argv construction ──────────────────────────────────────────────────
# change 6: --add-dir is the config-derived worktree PARENT dir, replacing
# the codex fork's hardcoded `--add-dir /tmp`.
# change 12: --json and -o are always on; --output-schema when enabled.
build_child_argv() {
  # $1 = last-message file, $2 = schema file (empty = disabled),
  # $3 = resume session id (empty = fresh exec), $4 = prompt.
  local last_message="$1" schema_file="$2" resume_id="$3" prompt="$4"
  CHILD_ARGV=("$CODEX_BIN" "exec")
  if [ -n "$resume_id" ]; then
    CHILD_ARGV+=("resume" "$resume_id")
  fi
  CHILD_ARGV+=("-C" "$REPO_ROOT" "--add-dir" "$WORKTREE_PARENT"
               "--sandbox" "$SANDBOX" "-c" "approval_policy=\"$APPROVAL_POLICY\""
               "--json" "-o" "$last_message")
  if [ -n "$schema_file" ]; then
    CHILD_ARGV+=("--output-schema" "$schema_file")
  fi
  CHILD_ARGV+=(${EXTRA_CODEX_ARGS[@]+"${EXTRA_CODEX_ARGS[@]}"} "$prompt")
}

write_argv_json() {
  local out="$1"
  shift
  "$PYTHON" - "$out" "$@" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(sys.argv[2:], f)
    f.write("\n")
PY
}

# ── dry-run (mutates NOTHING) ────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  print_resolved
  echo "dry_run=true"
  DRY_LAST_MESSAGE="$LOG_ROOT/dry-run.last-message.txt"
  DRY_SCHEMA=""
  [ "$OUTPUT_SCHEMA_CHECK" = "true" ] && DRY_SCHEMA="$LOG_ROOT/dry-run.output-schema.json"
  if [ "$RUN_MODE" = "every" ]; then
    DRY_PROMPT=$(every_fire_prompt)
  else
    DRY_PROMPT=$(finish_auto_prompt)
  fi
  build_child_argv "$DRY_LAST_MESSAGE" "$DRY_SCHEMA" "" "$DRY_PROMPT"
  echo "--- resolved child argv (one element per line) ---"
  for arg in "${CHILD_ARGV[@]}"; do
    printf '%s\n' "$arg"
  done
  echo "--- end child argv ---"
  exit 0
fi

# ── preflight battery ────────────────────────────────────────────────────────
# Codex executable must resolve (path form → executable file; bare name →
# on PATH). Skipped only in --dry-run above.
case "$CODEX_BIN" in
  */*)
    [ -x "$CODEX_BIN" ] || die "codex executable not found or not executable: $CODEX_BIN"
    ;;
  *)
    command -v "$CODEX_BIN" >/dev/null 2>&1 || die "codex executable not found: $CODEX_BIN"
    ;;
esac

refuse_git_residue() {
  local git_dir
  git_dir=$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)
  [ ! -e "$git_dir/CHERRY_PICK_HEAD" ] || die "unsafe git state: CHERRY_PICK_HEAD present"
  [ ! -e "$git_dir/MERGE_HEAD" ]       || die "unsafe git state: MERGE_HEAD present"
  [ ! -e "$git_dir/REBASE_HEAD" ]      || die "unsafe git state: REBASE_HEAD present"
  [ ! -d "$git_dir/rebase-merge" ]     || die "unsafe git state: rebase-merge present"
  [ ! -d "$git_dir/rebase-apply" ]     || die "unsafe git state: rebase-apply present"
  [ -z "$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U)" ] \
    || die "unsafe git state: unresolved conflicts present"
  [ -z "$(git -C "$REPO_ROOT" stash list)" ] \
    || die "unsafe git state: stash entries present (stash residue) — inspect 'git stash list' and clear before running"
  [ -z "$(git -C "$REPO_ROOT" worktree prune --dry-run --verbose 2>&1)" ] \
    || die "unsafe git state: stale git worktree-registry residue present — inspect 'git worktree list' / prune manually"
}

tracking_is_ignored() {
  local dir="$REPO_ROOT/.zskills/tracking"
  [ -e "$dir" ] || return 0
  git -C "$REPO_ROOT" check-ignore -q "$dir" 2>/dev/null
}

dirty_project_state() {
  # Non-.zskills dirt (ignored-state carve-out shared with the ladder).
  local status line path
  status=$(git -C "$REPO_ROOT" status --short --untracked-files=all)
  [ -n "$status" ] || return 0
  while IFS= read -r line; do
    path=${line#???}
    case "$path" in
      .zskills/*|.zskills-tracked) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <<EOF
$status
EOF
}

preflight() {
  refuse_git_residue
  tracking_is_ignored || die ".zskills/tracking/ exists but is not ignored by git"

  # Direct-landing gates.
  if [ "$EXECUTION_LANDING" = "direct" ]; then
    if [ "$ALLOW_DIRECT_UNATTENDED" != "true" ]; then
      die "direct landing is refused for unattended runner execution (pass --allow-direct-unattended or set runner.allow_direct_unattended)"
    fi
    # direct-runner-residue: unattended direct demands pristine per-plan
    # runner state — stale stop/session/state files from a previous run must
    # be explicitly cleared, never silently consumed.
    local residue=""
    for f in "$STOP_MARKER" "$SESSION_FILE" "$STATE_FILE"; do
      [ -e "$f" ] && residue="$residue $f"
    done
    if [ -n "$residue" ]; then
      die "direct runner residue: previous runner state present:$residue — remove before an unattended direct run"
    fi
  fi

  # Stale-PR-root triage (change 6) — path exists but is not a worktree →
  # die; worktree of a DIFFERENT repo → die; worktree missing the plan → die.
  if [ "$EXECUTION_LANDING" = "pr" ] && [ -d "$PR_WORKTREE_PATH" ]; then
    if ! git -C "$PR_WORKTREE_PATH" rev-parse --show-toplevel >/dev/null 2>&1; then
      die "stale PR artifact root exists but is not a git worktree: $PR_WORKTREE_PATH"
    fi
    local repo_common pr_common
    repo_common=$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir)
    pr_common=$(git -C "$PR_WORKTREE_PATH" rev-parse --path-format=absolute --git-common-dir)
    if [ "$repo_common" != "$pr_common" ]; then
      die "stale PR artifact root belongs to a different git repository: $PR_WORKTREE_PATH"
    fi
    if [ ! -f "$PR_WORKTREE_PATH/$REL_PLAN" ]; then
      die "stale PR artifact root is missing the expected plan file $REL_PLAN: $PR_WORKTREE_PATH"
    fi
  fi

  # Clean-tree requirement (all modes — autonomous chunk validation depends
  # on attributing every diff to the child).
  local dirty
  dirty=$(dirty_project_state)
  if [ -n "$dirty" ]; then
    if [ "$EXECUTION_LANDING" = "direct" ]; then
      die "direct unattended execution requires a clean working tree: $dirty"
    fi
    die "foreground auto execution requires a clean working tree before launching child chunks: $dirty"
  fi

  # A pre-existing stop marker is honored-but-stale state: refuse explicitly
  # instead of an instant exit-31 surprise.
  if [ -f "$STOP_MARKER" ]; then
    die "stale stop marker present: $STOP_MARKER — a previous stop was honored; remove the marker to run again"
  fi
}

# ── claims (change 10 — inlined minimal claim semantics) ─────────────────────
# Mirrors the SEMANTICS (not the code) of skills/run-plan/scripts/
# claim-plan.sh: atomic mkdir of <main-root>/.zskills/claims/plan-<slug>/ +
# an atomically-written JSON metadata file storing the pipeline id.
# Acquire → rc 0 for fresh acquire OR ownership-aware self-re-entry; rc 10
# for foreign-held OR existing-claim-with-absent/malformed-metadata (never
# steal). Release at terminal stop is idempotent and refuses on pipeline-id
# mismatch. Main root via git-common-dir, never $PWD.
MAIN_ROOT=$(cd "$REPO_ROOT" && cd "$(git rev-parse --git-common-dir)/.." && pwd)
CLAIM_DIR="$MAIN_ROOT/.zskills/claims/plan-$TRACKING_ID"
CLAIM_META="$CLAIM_DIR/claim.json"
CLAIM_HELD=0

claim_meta_pipeline_id() {
  [ -f "$CLAIM_META" ] || return 1
  "$PYTHON" - "$CLAIM_META" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
pid = data.get("pipeline_id")
if not isinstance(pid, str) or not pid:
    sys.exit(1)
print(pid)
PY
}

acquire_claim() {
  mkdir -p "$MAIN_ROOT/.zskills/claims"
  if mkdir "$CLAIM_DIR" 2>/dev/null; then
    "$PYTHON" - "$CLAIM_META" "$PIPELINE_ID" "$REL_PLAN" <<'PY'
import json, os, sys, time
path, pipeline_id, plan = sys.argv[1:4]
doc = {
    "pipeline_id": pipeline_id,
    "plan": plan,
    "acquired_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "pid": os.getpid(),
    "writer": "zskills-runner",
}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
    CLAIM_HELD=1
    return 0
  fi
  # Claim dir already exists — ownership-aware re-entry check.
  local holder
  if ! holder=$(claim_meta_pipeline_id); then
    # Absent/malformed metadata: NEVER steal.
    return 10
  fi
  if [ "$holder" = "$PIPELINE_ID" ]; then
    CLAIM_HELD=1
    return 0
  fi
  echo "zskills-runner: plan claim is held by pipeline '$holder'" >&2
  return 10
}

release_claim() {
  # Idempotent; refuses on pipeline-id mismatch.
  [ "$CLAIM_HELD" -eq 1 ] || return 0
  [ -d "$CLAIM_DIR" ] || return 0
  local holder
  if holder=$(claim_meta_pipeline_id); then
    if [ "$holder" != "$PIPELINE_ID" ]; then
      echo "zskills-runner: refusing claim release — claim now held by pipeline '$holder' (ours: '$PIPELINE_ID')" >&2
      return 0
    fi
  fi
  rm -rf "$CLAIM_DIR"
}

# ── lock (mkdir-lock + owner file + EXIT trap) ───────────────────────────────
LOCK_HELD=0

runner_cleanup() {
  if [ "$LOCK_HELD" -eq 1 ]; then
    rm -rf "$LOCK_DIR"
  fi
  release_claim
}

acquire_lock() {
  mkdir -p "$RUNNER_STATE_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
    trap runner_cleanup EXIT
    printf 'pid=%s\nstarted_at=%s\nplan=%s\nmode=%s\n' \
      "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$REL_PLAN" "$RUN_MODE" > "$LOCK_DIR/owner"
    return 0
  fi
  if [ -f "$LOCK_DIR/owner" ]; then
    die "runner lock already exists: $LOCK_DIR (owner: $(tr '\n' ' ' < "$LOCK_DIR/owner"))"
  fi
  die "runner lock already exists: $LOCK_DIR"
}

# ── child execution (change 1: STREAM — the pumper tee) ──────────────────────
# Every child stdout line is written to the parent terminal LIVE and to
# chunk-NNN.stdout.txt + events.jsonl; stderr is streamed to the parent
# stderr and captured to chunk-NNN.stderr.txt. Wall/idle timeouts kill the
# child; the pumper records which timeout fired in a result file so a child
# that itself exits 124 cannot masquerade as a runner wall-timeout.
run_child() {
  # $1=events $2=stdout_file $3=stderr_file $4=result_file $5=wall_s $6=idle_s; rest = argv
  local events_file="$1" stdout_file="$2" stderr_file="$3" result_file="$4" wall_s="$5" idle_s="$6"
  shift 6
  ZSKILLS_PIPELINE_ID="$PIPELINE_ID" ZSKILLS_TRACKING_ID="$TRACKING_ID" \
    "$PYTHON" - "$events_file" "$stdout_file" "$stderr_file" "$result_file" "$wall_s" "$idle_s" "$@" <<'PY'
import json, queue, subprocess, sys, threading, time

events_file, stdout_file, stderr_file, result_file, wall_s, idle_s, *argv = sys.argv[1:]
wall_s = int(wall_s)
idle_s = int(idle_s)
start = time.time()
last_output = start
q = queue.Queue()

proc = subprocess.Popen(
    argv,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def reader(stream, tag):
    for line in stream:
        q.put((tag, line))

threading.Thread(target=reader, args=(proc.stdout, "stdout"), daemon=True).start()
threading.Thread(target=reader, args=(proc.stderr, "stderr"), daemon=True).start()

timed_out = False
idle_timed_out = False

def handle(tag, line, out, err, events):
    global last_output
    last_output = time.time()
    if tag == "stdout":
        sys.stdout.write(line)   # STREAM: live to the attached terminal
        sys.stdout.flush()
        out.write(line)
        out.flush()
    else:
        sys.stderr.write(line)
        sys.stderr.flush()
        err.write(line)
        err.flush()
    events.write(json.dumps({
        "event": "output", "stream": tag, "time": last_output,
        "line": line.rstrip("\n"),
    }) + "\n")
    events.flush()

with open(events_file, "w", encoding="utf-8") as events, \
     open(stdout_file, "w", encoding="utf-8") as out, \
     open(stderr_file, "w", encoding="utf-8") as err:
    events.write(json.dumps({"event": "start", "argv": argv, "time": start}) + "\n")
    while True:
        try:
            tag, line = q.get(timeout=0.2)
            handle(tag, line, out, err, events)
        except queue.Empty:
            pass
        now = time.time()
        if proc.poll() is not None:
            break
        if wall_s > 0 and now - start > wall_s:
            timed_out = True
            proc.kill()
            break
        if idle_s > 0 and now - last_output > idle_s:
            idle_timed_out = True
            proc.kill()
            break
    rc = proc.wait()
    # Drain anything left in the queue.
    while True:
        try:
            tag, line = q.get(timeout=0.2)
        except queue.Empty:
            break
        handle(tag, line, out, err, events)
    end = time.time()
    exit_rc = 124 if timed_out else (125 if idle_timed_out else rc)
    events.write(json.dumps({
        "event": "end", "time": end, "child_rc": rc, "exit_code": exit_rc,
        "timed_out": timed_out, "idle_timed_out": idle_timed_out,
    }) + "\n")

with open(result_file, "w", encoding="utf-8") as f:
    json.dump({"child_rc": rc, "timed_out": timed_out,
               "idle_timed_out": idle_timed_out}, f)
    f.write("\n")

sys.exit(exit_rc)
PY
}

pumper_flag() {
  # pumper_flag <result_file> <key> → true/false/number
  "$PYTHON" - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("")
    sys.exit(0)
value = data.get(sys.argv[2])
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print("" if value is None else value)
PY
}

# ── summary.json (change 12: thread_id + usage parsed in) ────────────────────
write_chunk_summary() {
  # $1=summary $2=argv.json $3=before $4=after $5=start $6=end $7=exit_code
  # $8=stdout_file $9=stderr_file
  "$PYTHON" - "$@" <<'PY'
import json, sys

(summary_file, argv_file, before_file, after_file,
 start_time, end_time, exit_code, stdout_file, stderr_file) = sys.argv[1:10]

def lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return [line.rstrip("\n") for line in f]
    except OSError:
        return []

with open(argv_file, encoding="utf-8") as f:
    argv = json.load(f)

thread_id = None
usage = None
for line in lines(stdout_file):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        event = json.loads(line)
    except Exception:
        continue
    if event.get("type") == "thread.started" and thread_id is None:
        thread_id = event.get("thread_id")
    if event.get("type") == "turn.completed":
        usage = event.get("usage")

data = {
    "command_argv": argv,
    "start_time": start_time,
    "end_time": end_time,
    "exit_code": int(exit_code),
    "thread_id": thread_id,
    "token_usage": usage,
    "child_stderr_tail": lines(stderr_file)[-20:],
    "phase_before": lines(before_file),
    "phase_after": lines(after_file),
    "validation_result": None,
    "validation_reason": None,
    "validated_tracking_id": None,
    "gate_result": None,
    "progress_signals": [],
    "runner_stop_reason": None,
}
with open(summary_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

update_summary_validation() {
  # $1=summary $2=result $3=reason $4=tracking_id $5=gate_result $6=signals
  "$PYTHON" - "$@" <<'PY'
import json, sys
summary_file, result, reason, tracking_id, gate_result, signals = sys.argv[1:7]
with open(summary_file, encoding="utf-8") as f:
    data = json.load(f)
data["validation_result"] = result
data["validation_reason"] = reason
data["validated_tracking_id"] = tracking_id or None
data["gate_result"] = gate_result
data["progress_signals"] = [s for s in signals.split(",") if s]
with open(summary_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

record_child_failure() {
  # $1=summary $2=raw child rc — the raw child rc + last stderr are FORENSICS
  # for the exit-26 mapping (never a raw passthrough).
  "$PYTHON" - "$1" "$2" <<'PY'
import json, sys
summary_file, raw_rc = sys.argv[1:3]
with open(summary_file, encoding="utf-8") as f:
    data = json.load(f)
data["child_raw_rc"] = int(raw_rc)
with open(summary_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

# ── sandbox triage (change 7 — NEVER auto-escalate) ──────────────────────────
sandbox_failure_detected() {
  local stdout_file="$1" stderr_file="$2"
  grep -qiE 'bwrap|bubblewrap|user namespace|new namespace|No permissions to create a new namespace|Operation not permitted' \
    "$stdout_file" "$stderr_file" 2>/dev/null
}

explain_sandbox_failure() {
  cat >&2 <<EOF
Codex child failed while starting the configured sandbox mode: $SANDBOX.
This environment appears to block bubblewrap/user-namespace sandbox setup.
The runner will NOT retry with danger-full-access automatically.
If this is a trusted disposable/dev-container environment, rerun explicitly with:
  --sandbox danger-full-access
Otherwise fix user-namespace/bubblewrap support and keep the default sandbox.
EOF
}

# ── structured self-report cross-check (change 12) ───────────────────────────
# Claims never substitute for evidence; they add a lie-detection layer.
# Returns 0 = consistent, 1 = mismatch (detail on stdout).
self_report_mismatch() {
  local last_message="$1" complete="$2" summary="$3"
  "$PYTHON" - "$last_message" "$complete" "$TRACKING_ID" "$summary" <<'PY'
import json, sys
path, complete, tid, summary_file = sys.argv[1:5]
try:
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
except Exception as exc:
    print(f"self-report missing or malformed JSON: {exc}")
    sys.exit(1)

problems = []
claimed_status = str(doc.get("status", "")).lower()
claimed_remaining = doc.get("remaining_phases")
claimed_tid = doc.get("tracking_id")
evidence_complete = complete == "true"

if claimed_tid != tid:
    problems.append(f"claimed tracking_id {claimed_tid!r} != evidence {tid!r}")
if evidence_complete and claimed_status != "complete":
    problems.append(f"evidence says plan complete but self-report status is {claimed_status!r}")
if not evidence_complete and claimed_status == "complete":
    problems.append("self-report claims status 'complete' but durable evidence says the plan is NOT complete")
if isinstance(claimed_remaining, int):
    if evidence_complete and claimed_remaining != 0:
        problems.append(f"evidence complete but self-report claims {claimed_remaining} remaining phases")
    if not evidence_complete and claimed_remaining == 0:
        problems.append("self-report claims 0 remaining phases but durable evidence says the plan is NOT complete")

try:
    with open(summary_file, encoding="utf-8") as f:
        data = json.load(f)
    data["self_report"] = doc
    data["self_report_problems"] = problems
    with open(summary_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
except Exception:
    pass

if problems:
    print("; ".join(problems))
    sys.exit(1)
sys.exit(0)
PY
}

# ── validation ladder (runs after every child, both modes) ───────────────────
VALIDATION_REASON=""
VALIDATED_TID=""
GATE_RESULT="not-run"
SIGNALS=""

marker_analysis() {
  # $1=before $2=after $3=complete(true/false) → key=value lines
  "$PYTHON" - "$1" "$2" "$3" "$TRACKING_ID" <<'PY'
import sys

before_file, after_file, complete, tid = sys.argv[1:5]

def read_state(path):
    values = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            key, sep, value = line.rstrip("\n").partition("=")
            if sep:
                values[key] = value
    return values

def parse_hashes(csv):
    result = {}
    for item in filter(None, csv.split(",")):
        name, sep, digest = item.partition(":")
        if sep:
            result[name] = digest
    return result

before = read_state(before_file)
after = read_state(after_file)
before_hashes = parse_hashes(before.get("tracking_marker_hashes", ""))
after_hashes = parse_hashes(after.get("tracking_marker_hashes", ""))

signals = []
if before.get("plan_hash") != after.get("plan_hash"):
    signals.append("plan_hash_changed")
if before.get("report_hash") != after.get("report_hash"):
    signals.append("report_hash_changed")
new_markers = sorted(set(after_hashes) - set(before_hashes))
changed_markers = sorted(
    name for name, digest in after_hashes.items()
    if name in before_hashes and before_hashes[name] != digest
)
if new_markers:
    signals.append("new_markers")
if changed_markers:
    signals.append("changed_markers")

def touched(name):
    # New OR content-changed (change 4: marker_changed staleness — a
    # pre-seeded stale marker set cannot ride through).
    return name in new_markers or name in changed_markers

handoff = f"handoff.run-plan.{tid}"
required = [
    f"step.run-plan.{tid}.implement",
    f"step.run-plan.{tid}.verify",
    f"step.run-plan.{tid}.report",
    f"requires.verify-changes.{tid}",
    f"step.verify-changes.{tid}.tests-run",
    f"step.verify-changes.{tid}.complete",
    f"fulfilled.verify-changes.{tid}",
]
if complete == "true":
    required += [
        f"step.run-plan.{tid}.land",
        f"fulfilled.run-plan.{tid}",
        f"requires.verify-changes.final.{tid}",
        f"fulfilled.verify-changes.final.{tid}",
    ]
else:
    required.append(handoff)

missing = [name for name in required if name not in after_hashes]
stale = [name for name in required if name in after_hashes and not touched(name)]

premature = "false"
if complete != "true":
    for name in (f"step.run-plan.{tid}.land", f"fulfilled.run-plan.{tid}"):
        if name in after_hashes:
            premature = "true"

print("signals=" + ",".join(signals))
print("handoff_touched=" + ("true" if touched(handoff) else "false"))
print("premature_final=" + premature)
print("missing_marker=" + (missing[0] if missing else ""))
print("stale_marker=" + (stale[0] if stale else ""))
PY
}

validate_chunk() {
  # $1=before_file $2=after_file $3=summary $4=gate_out — returns the ladder
  # rc (0 = passed). Sets VALIDATION_REASON / VALIDATED_TID / GATE_RESULT /
  # SIGNALS for the caller.
  local before_file="$1" after_file="$2" summary_file="$3" gate_out="$4"
  local complete analysis report gate_mode dirty
  VALIDATION_REASON=""
  VALIDATED_TID="$TRACKING_ID"
  GATE_RESULT="not-run"

  if plan_is_complete; then
    complete=true
  else
    complete=false
  fi

  analysis=$(marker_analysis "$before_file" "$after_file" "$complete")
  SIGNALS=$(state_value "$analysis" signals)

  # 2. Empty signal set — nothing durable changed.
  if [ -z "$SIGNALS" ]; then
    VALIDATION_REASON="no durable progress detected"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "" "not-run" "$SIGNALS"
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 20
  fi

  # 3. Handoff contract (change 9) + premature-final.
  if [ "$complete" != "true" ] && [ "$(state_value "$analysis" handoff_touched)" != "true" ]; then
    VALIDATION_REASON="handoff marker missing after progress"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "not-run" "$SIGNALS"
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 21
  fi
  if [ "$(state_value "$analysis" premature_final)" = "true" ]; then
    VALIDATION_REASON="final run-plan marker present before plan completion"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "not-run" "$SIGNALS"
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 21
  fi

  # 4. Report — current Phase-5 patterns at the config-resolved path (NO
  # "Scope Assessment" requirement) — then marker staleness.
  report=$(active_report_path)
  if [ ! -f "$report" ]; then
    VALIDATION_REASON="report missing: $report"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "not-run" "$SIGNALS"
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 22
  fi
  local pattern
  for pattern in '^## Phase' '\*\*Status:\*\*' '^### Verification'; do
    if ! grep -qE "$pattern" "$report"; then
      VALIDATION_REASON="report missing required pattern: $pattern"
      update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "not-run" "$SIGNALS"
      echo "validation_failed=$VALIDATION_REASON" >&2
      return 22
    fi
  done
  local stale_marker
  stale_marker=$(state_value "$analysis" stale_marker)
  if [ -n "$stale_marker" ]; then
    VALIDATION_REASON="stale marker was not updated: $stale_marker"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "not-run" "$SIGNALS"
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 22
  fi

  # 5. Full marker evidence set (incl. step.verify-changes.<tid>.tests-run;
  # step.verify-changes.<tid>.manual-verified is tolerated, never required).
  local missing_marker
  missing_marker=$(state_value "$analysis" missing_marker)
  if [ -n "$missing_marker" ]; then
    VALIDATION_REASON="verification marker evidence missing: $missing_marker"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "not-run" "$SIGNALS"
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 23
  fi

  # 5b. Structured self-report cross-check (change 12) when enabled.
  if [ "$OUTPUT_SCHEMA_CHECK" = "true" ]; then
    local mismatch
    if ! mismatch=$(self_report_mismatch "$LAST_MESSAGE_FILE" "$complete" "$summary_file"); then
      VALIDATION_REASON="claim-evidence-mismatch: $mismatch"
      update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "not-run" "$SIGNALS"
      echo "validation_failed=$VALIDATION_REASON" >&2
      return 23
    fi
  fi

  # 6. Gate (change 13): pre-continue (non-final) / post-land (final).
  if [ "$complete" = "true" ]; then
    gate_mode="post-land"
  else
    gate_mode="pre-continue"
  fi
  if bash "$GATE_SCRIPT" \
       --repo "$(artifact_root)" \
       --tracking-root "$REPO_ROOT" \
       --mode "$gate_mode" \
       --pipeline "$PIPELINE_ID" \
       --tracking-id "$TRACKING_ID" \
       --plan-file "$(active_plan_path)" \
       --report "$report" > "$gate_out" 2>&1; then
    GATE_RESULT="passed"
  else
    GATE_RESULT="failed"
    VALIDATION_REASON="$gate_mode gate failed"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "$GATE_RESULT" "$SIGNALS"
    cat "$gate_out" >&2
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 24
  fi

  # 7. Dirty non-.zskills artifacts.
  dirty=$(dirty_project_state)
  if [ -n "$dirty" ]; then
    VALIDATION_REASON="unexpected dirty project artifact remains"
    update_summary_validation "$summary_file" "failed" "$VALIDATION_REASON" "$TRACKING_ID" "$GATE_RESULT" "$SIGNALS"
    printf '%s\n' "$dirty" >&2
    echo "validation_failed=$VALIDATION_REASON" >&2
    return 25
  fi

  update_summary_validation "$summary_file" "passed" "durable progress validated" "$TRACKING_ID" "$GATE_RESULT" "$SIGNALS"
  echo "validation_result=passed"
  echo "validated_tracking_id=$TRACKING_ID"
  return 0
}

# ── landed-marker consumption + invariants (final chunk, change 8/14) ────────
landed_status() {
  # New path first; legacy root .landed fallback (drop the fallback if #1146
  # lands first — mirror upstream's state at that time).
  local root marker
  root=$(artifact_root)
  marker="$root/.zskills/landed"
  [ -f "$marker" ] || marker="$root/.landed"
  if [ -f "$marker" ]; then
    sed -n 's/^status: //p' "$marker" | sed -n '1p'
  fi
}

run_final_invariants() {
  local invariant_out="$1" status="$2"
  bash "$INVARIANTS_SCRIPT" \
    --worktree "" \
    --branch "" \
    --landed-status "$status" \
    --plan-slug "$TRACKING_ID" \
    --plan-file "$(active_plan_path)" \
    --report "$(active_report_path)" \
    --base-branch "$BASE_BRANCH" \
    --remote "$REMOTE" > "$invariant_out" 2>&1
}

# consume_final_landing <summary> <invariant_out> — decides the terminal
# action for a validated COMPLETE chunk. Sets FINAL_VERDICT to one of:
#   complete | re-entry
# Dies (via fail_run) on terminal landing failure. NOT run in a command
# substitution — fail_run must exit the real shell, not a subshell.
FINAL_VERDICT=""
consume_final_landing() {
  local summary_file="$1" invariant_out="$2" status
  status=$(landed_status)
  if ! run_final_invariants "$invariant_out" "${status:-landed}"; then
    cat "$invariant_out" >&2
    fail_run 24 "invariants-failed" "post-run invariants failed (see $invariant_out)"
  fi
  case "${status:-}" in
    landed|"")
      # landed → proceed/complete. An absent marker with a fully validated
      # post-land gate is accepted for non-PR landings (direct/cherry-pick
      # children may land without writing a worktree-state marker).
      FINAL_VERDICT="complete"
      ;;
    pr-ready|pr-ci-failing)
      # Schedule re-entry: the next chunk/fire re-enters and the child's
      # idempotent Step-0 resolves the pending landing.
      FINAL_VERDICT="re-entry"
      ;;
    conflict|pr-failed)
      fail_run 24 "landing-$status" "terminal landing failure recorded in .zskills/landed: status=$status"
      ;;
    *)
      fail_run 24 "landing-unresolved" "unrecognized landing status in .zskills/landed: '$status' (fail-closed)"
      ;;
  esac
}

# ── chunk execution shared by both modes ─────────────────────────────────────
WALL_SECONDS="${ZSKILLS_RUNNER_TIMEOUT_SECONDS:-$((CHUNK_TIMEOUT_MINUTES * 60))}"
IDLE_SECONDS="${ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS:-$((IDLE_TIMEOUT_MINUTES * 60))}"
RUN_DIR=""
LAST_MESSAGE_FILE=""
CHUNK_EXIT=0
CHUNK_RESUME=0

run_one_chunk() {
  # $1=chunk number, $2=prompt, $3=resume session id (empty = fresh exec).
  # Sets CHUNK_* globals; LAST_SUMMARY_FILE points at this chunk's summary.
  local chunk_number="$1" prompt="$2" resume_id="$3"
  local chunk_label chunk_prefix events_file stdout_file stderr_file result_file
  local argv_file summary_file schema_file start_time end_time
  chunk_label=$(printf 'chunk-%03d' "$chunk_number")
  chunk_prefix="$RUN_DIR/$chunk_label"
  events_file="$chunk_prefix.events.jsonl"
  stdout_file="$chunk_prefix.stdout.txt"
  stderr_file="$chunk_prefix.stderr.txt"
  result_file="$chunk_prefix.pumper.json"
  argv_file="$chunk_prefix.argv.json"
  summary_file="$chunk_prefix.summary.json"
  LAST_MESSAGE_FILE="$chunk_prefix.last-message.txt"
  schema_file=""
  if [ "$OUTPUT_SCHEMA_CHECK" = "true" ]; then
    schema_file="$chunk_prefix.output-schema.json"
    "$PYTHON" - "$schema_file" <<'PY'
import json, sys
schema = {
    "type": "object",
    "properties": {
        "phase_executed": {"type": "string"},
        "status": {"type": "string"},
        "landing_status": {"type": "string"},
        "tracking_id": {"type": "string"},
        "remaining_phases": {"type": "integer"},
    },
    "required": ["phase_executed", "status", "landing_status",
                 "tracking_id", "remaining_phases"],
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(schema, f, indent=2)
    f.write("\n")
PY
  fi

  CHUNK_RESUME=0
  [ -n "$resume_id" ] && CHUNK_RESUME=1
  CHUNK_BEFORE="$chunk_prefix.before-state.txt"
  CHUNK_AFTER="$chunk_prefix.after-state.txt"
  CHUNK_GATE_OUT="$chunk_prefix.gate.txt"
  CHUNK_INVARIANT_OUT="$chunk_prefix.post-run-invariants.txt"
  CHUNK_STDOUT="$stdout_file"
  CHUNK_STDERR="$stderr_file"

  collect_snapshot "$CHUNK_BEFORE"
  build_child_argv "$LAST_MESSAGE_FILE" "$schema_file" "$resume_id" "$prompt"
  write_argv_json "$argv_file" "${CHILD_ARGV[@]}"

  start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"event":"runner-start","chunk":%s,"resume":%s,"time":"%s"}\n' \
    "$chunk_number" "$CHUNK_RESUME" "$start_time" >> "$RUN_DIR/runner.jsonl"
  echo "zskills-runner: $chunk_label start (logs: $chunk_prefix.*)"

  set +e
  run_child "$events_file" "$stdout_file" "$stderr_file" "$result_file" \
    "$WALL_SECONDS" "$IDLE_SECONDS" "${CHILD_ARGV[@]}"
  CHUNK_EXIT=$?
  set -e

  end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  collect_snapshot "$CHUNK_AFTER"
  write_chunk_summary "$summary_file" "$argv_file" "$CHUNK_BEFORE" "$CHUNK_AFTER" \
    "$start_time" "$end_time" "$CHUNK_EXIT" "$stdout_file" "$stderr_file"
  LAST_SUMMARY_FILE="$summary_file"
  printf '{"event":"runner-end","chunk":%s,"time":"%s","exit_code":%s}\n' \
    "$chunk_number" "$end_time" "$CHUNK_EXIT" >> "$RUN_DIR/runner.jsonl"
  echo "zskills-runner: $chunk_label exit=$CHUNK_EXIT"
  echo "summary_file=$summary_file"
}

classify_child_failure() {
  # Called when CHUNK_EXIT != 0. Maps to the runner taxonomy — never a raw
  # child-rc passthrough (the code-26 deviation).
  local result_file="$RUN_DIR/$(printf 'chunk-%03d' "$1").pumper.json"
  local wall idle raw_rc
  wall=$(pumper_flag "$result_file" timed_out)
  idle=$(pumper_flag "$result_file" idle_timed_out)
  raw_rc=$(pumper_flag "$result_file" child_rc)
  if [ "$wall" = "true" ]; then
    fail_run 124 "chunk-timeout" "chunk wall timeout after ${WALL_SECONDS}s"
  fi
  if [ "$idle" = "true" ]; then
    fail_run 125 "chunk-idle-timeout" "chunk idle timeout after ${IDLE_SECONDS}s of silence"
  fi
  record_child_failure "$LAST_SUMMARY_FILE" "${raw_rc:-$CHUNK_EXIT}"
  if [ "$CHUNK_RESUME" -eq 1 ]; then
    # change 11: session loss is a HARD STOP — never a silent fallback to a
    # fresh exec, which would invisibly break the one-durable-session
    # contract.
    if sandbox_failure_detected "$CHUNK_STDOUT" "$CHUNK_STDERR"; then
      explain_sandbox_failure
    fi
    fail_run 32 "session-lost" "exec resume failed (raw child rc ${raw_rc:-$CHUNK_EXIT}) — durable session unusable; every-mode hard stop"
  fi
  if sandbox_failure_detected "$CHUNK_STDOUT" "$CHUNK_STDERR"; then
    explain_sandbox_failure
    fail_run 26 "sandbox-unavailable" "child failed while starting sandbox '$SANDBOX' (raw child rc ${raw_rc:-$CHUNK_EXIT})"
  fi
  fail_run 26 "child-failed" "child exited nonzero (raw child rc ${raw_rc:-$CHUNK_EXIT}; last stderr recorded in the chunk summary)"
}

# ── finish-auto mode ─────────────────────────────────────────────────────────
run_finish_auto() {
  local chunk=1 verdict rc
  while [ "$chunk" -le "$MAX_CHUNKS" ]; do
    # change 2: STOP-IN-LOOP — the marker is checked before EVERY chunk.
    if [ -f "$STOP_MARKER" ]; then
      fail_run 31 "stopped" "stop marker honored: $STOP_MARKER"
    fi
    if plan_is_complete && [ "$chunk" -eq 1 ]; then
      finish_ok "complete"
    fi

    run_one_chunk "$chunk" "$(finish_auto_prompt)" ""
    if [ "$CHUNK_EXIT" -ne 0 ]; then
      classify_child_failure "$chunk"
    fi

    set +e
    validate_chunk "$CHUNK_BEFORE" "$CHUNK_AFTER" "$LAST_SUMMARY_FILE" "$CHUNK_GATE_OUT"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      fail_run "$rc" "validation-failed" "chunk validation failed (rc $rc): $VALIDATION_REASON"
    fi

    if plan_is_complete; then
      consume_final_landing "$LAST_SUMMARY_FILE" "$CHUNK_INVARIANT_OUT"
      if [ "$FINAL_VERDICT" = "complete" ]; then
        finish_ok "complete"
      fi
      echo "zskills-runner: landing pending (${FINAL_VERDICT}) — scheduling re-entry chunk"
    fi
    chunk=$((chunk + 1))
  done
  fail_run 30 "max-chunks" "max chunks ($MAX_CHUNKS) exhausted before plan completion"
}

# ── every mode (change 11) ───────────────────────────────────────────────────
update_every_state() {
  # $1=next_fire_epoch-or-empty $2=last_validation
  "$PYTHON" - "$STATE_FILE" "$SCHEDULE" "$1" "$2" "$SESSION_FILE" <<'PY'
import json, os, sys, time
state_file, schedule, next_epoch, last_validation, session_file = sys.argv[1:6]
session_id = None
if os.path.isfile(session_file):
    with open(session_file, encoding="utf-8") as f:
        session_id = f.read().strip() or None
state = {
    "schedule": schedule,
    "session_id": session_id,
    "last_validation": last_validation or None,
}
if next_epoch:
    epoch = int(next_epoch)
    state["next_fire_epoch"] = epoch
    state["next_fire_iso"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))
tmp = state_file + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, state_file)
PY
}

extract_thread_id() {
  "$PYTHON" - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except Exception:
                continue
            if event.get("type") == "thread.started" and event.get("thread_id"):
                print(event["thread_id"])
                break
except OSError:
    pass
PY
}

run_every() {
  local fire=1 sleep_total remaining step now_epoch verdict rc session_id prompt
  echo "zskills-runner: every-mode scheduler started (schedule: $SCHEDULE, auto=$EVERY_AUTO)"
  while :; do
    if [ -f "$STOP_MARKER" ]; then
      update_every_state "" "${VALIDATION_REASON:-stopped}"
      fail_run 31 "stopped" "stop marker honored: $STOP_MARKER"
    fi
    if plan_is_complete; then
      update_every_state "" "complete"
      finish_ok "complete"
    fi

    sleep_total=$(parse_schedule_seconds "$SCHEDULE") \
      || die "unsupported schedule expression: '$SCHEDULE'"
    now_epoch=$("$PYTHON" -c 'import time; print(int(time.time()))')
    update_every_state "$((now_epoch + sleep_total))" "${VALIDATION_REASON:-pending}"
    echo "zskills-runner: next fire in ${sleep_total}s"

    # Sleep loop — the stop marker is honored DURING the wait, not only at
    # fire time (change 2 applies to fires too).
    remaining=$sleep_total
    while [ "$remaining" -gt 0 ]; do
      step=5
      [ "$remaining" -lt 5 ] && step=$remaining
      sleep "$step"
      remaining=$((remaining - step))
      if [ -f "$STOP_MARKER" ]; then
        update_every_state "" "${VALIDATION_REASON:-stopped}"
        fail_run 31 "stopped" "stop marker honored during sleep: $STOP_MARKER"
      fi
    done

    session_id=""
    [ -f "$SESSION_FILE" ] && session_id=$(cat "$SESSION_FILE")
    prompt=$(every_fire_prompt)
    run_one_chunk "$fire" "$prompt" "$session_id"
    if [ "$CHUNK_EXIT" -ne 0 ]; then
      classify_child_failure "$fire"
    fi

    if [ -z "$session_id" ]; then
      # FIRST fire — capture the durable session id from the thread.started
      # JSONL event and persist it. No id = the one-durable-session contract
      # cannot be maintained → hard stop (fail-closed), never silent fresh
      # execs.
      local thread_id
      thread_id=$(extract_thread_id "$CHUNK_STDOUT")
      if [ -z "$thread_id" ]; then
        fail_run 32 "session-lost" "first fire produced no thread.started thread_id in --json output — cannot maintain the one-durable-session contract"
      fi
      printf '%s\n' "$thread_id" > "$SESSION_FILE"
      echo "zskills-runner: durable session established: $thread_id"
    fi

    # Validation between fires is IDENTICAL to finish-auto's ladder —
    # durable evidence is the only freshness-independent protection once
    # contexts are resumed, not fresh.
    set +e
    validate_chunk "$CHUNK_BEFORE" "$CHUNK_AFTER" "$LAST_SUMMARY_FILE" "$CHUNK_GATE_OUT"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      update_every_state "" "failed: $VALIDATION_REASON"
      fail_run "$rc" "validation-failed" "fire validation failed (rc $rc): $VALIDATION_REASON"
    fi
    update_every_state "" "passed"

    if plan_is_complete; then
      consume_final_landing "$LAST_SUMMARY_FILE" "$CHUNK_INVARIANT_OUT"
      if [ "$FINAL_VERDICT" = "complete" ]; then
        update_every_state "" "complete"
        finish_ok "complete"
      fi
      echo "zskills-runner: landing pending (${FINAL_VERDICT}) — next fire re-enters"
    fi
    fire=$((fire + 1))
  done
}

# ── run-plan main sequence ───────────────────────────────────────────────────
preflight
acquire_lock

if ! acquire_claim; then
  die "plan claim refused (foreign-held or unreadable claim metadata): $CLAIM_DIR — never stolen; release it from the owning pipeline or remove it manually after inspection"
fi

mkdir -p "$TRACKING_DIR" "$LOG_ROOT"
RUN_DIR="$LOG_ROOT/run-plan-$PLAN_KEY-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$RUN_DIR"

echo "zskills-runner: foreground run-plan $RUN_MODE"
print_resolved
echo "run_dir=$RUN_DIR"

if [ "$RUN_MODE" = "every" ]; then
  run_every
else
  run_finish_auto
fi
