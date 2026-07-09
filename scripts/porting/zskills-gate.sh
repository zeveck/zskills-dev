#!/usr/bin/env bash
# scripts/porting/zskills-gate.sh — unified READ-ONLY evidence gate for the
# Codex external runner (CODEX_PORT_PLAN Phase 1, WI 1.2 — spec change 13,
# GATE-UNIFY).
#
# Union of the two prior-fork gates:
#   - zskills-codex fork: four modes (pre-land|post-land|pre-push|pre-continue)
#     + the fix-issues.* pipeline arm (cheap; future-proofs a `/fix-issues N`
#     runner mode).
#   - zskills-cc fork: artifact-root/tracking-root split (--tracking-root),
#     in-gate premature-final detection, and the `tests-run` requirement.
#   - CURRENT-format updates (spec change 8): report patterns are the current
#     Phase-5 format (`^## Phase`, `**Status:**`, `### Verification` — NO
#     "Scope Assessment" requirement; that section lives in the verify-changes
#     report, not the plan report); the report path, when not passed, is
#     config-resolved the way zskills-paths.sh resolves it (output.reports_dir,
#     discovered-config cascade) — never hardcoded; the final-verify pair
#     (requires.verify-changes.final.<tid> → fulfilled.verify-changes.final.<tid>)
#     is required at post-land; `step.verify-changes.<tid>.manual-verified`
#     (UI phases) is TOLERATED — its presence is never an error and it is
#     never required.
#
# READ-ONLY BY CONTRACT: this script never mutates the repository — it
# surfaces missing evidence (surface, don't patch). Exit 0 = gate passed,
# exit 1 = gate failed (each failure printed as a GATE-FAIL line), exit 2 =
# usage / not-a-repo error.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-gate.sh --mode pre-land|post-land|pre-push|pre-continue
                  --pipeline <id> --tracking-id <id>
                  [--repo <artifact-root>] [--tracking-root <repo-root>]
                  [--plan-file <path>] [--report <path>] [--plan-slug <slug>]
                  [--base-ref <ref>]

Read-only evidence gate for runner-managed chunks. --repo is the ARTIFACT
root (PR worktree when one exists, else the repo root); --tracking-root is
where .zskills/tracking/ lives (always the repo root — defaults to --repo).
When --report is omitted the path is resolved from the discovered
zskills-config (output.reports_dir) as <artifact-root>/<reports_dir>/plan-<slug>.md.
EOF
}

die() {
  echo "zskills-gate: $*" >&2
  exit 2
}

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

PYTHON="$(zskills_resolve_python || true)"
[ -n "$PYTHON" ] || die "no working Python 3 interpreter found (install Python 3 or set ZSKILLS_PYTHON)"

MODE=""
REPO="."
TRACKING_ROOT=""
PIPELINE_ID=""
TRACKING_ID=""
PLAN_SLUG=""
PLAN_FILE=""
REPORT_PATH=""
BASE_REF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)          MODE="${2:-}"; shift 2 ;;
    --repo)          REPO="${2:-}"; shift 2 ;;
    --tracking-root) TRACKING_ROOT="${2:-}"; shift 2 ;;
    --pipeline)      PIPELINE_ID="${2:-}"; shift 2 ;;
    --tracking-id)   TRACKING_ID="${2:-}"; shift 2 ;;
    --plan-slug)     PLAN_SLUG="${2:-}"; shift 2 ;;
    --plan-file)     PLAN_FILE="${2:-}"; shift 2 ;;
    --report)        REPORT_PATH="${2:-}"; shift 2 ;;
    --base-ref)      BASE_REF="${2:-}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown argument '$1'" ;;
  esac
done

case "$MODE" in
  pre-land|post-land|pre-push|pre-continue) ;;
  *) die "unsupported --mode '$MODE' (pre-land|post-land|pre-push|pre-continue)" ;;
esac
[ -n "$PIPELINE_ID" ] || die "--pipeline is required"
[ -n "$TRACKING_ID" ] || die "--tracking-id is required"

git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "repo is not a git worktree: $REPO"
ARTIFACT_ROOT=$(git -C "$REPO" rev-parse --show-toplevel)

# Tracking-root split (cc fork): tracking markers ALWAYS live at the repo
# root, even when the artifacts under validation live in a PR worktree.
if [ -n "$TRACKING_ROOT" ]; then
  git -C "$TRACKING_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "tracking root is not a git worktree: $TRACKING_ROOT"
  TRACKING_ROOT=$(git -C "$TRACKING_ROOT" rev-parse --show-toplevel)
else
  TRACKING_ROOT="$ARTIFACT_ROOT"
fi

FAILED=0
fail() {
  echo "GATE-FAIL: $*" >&2
  FAILED=1
}
warn() {
  echo "GATE-WARN: $*" >&2
}

# ── tracking hygiene ─────────────────────────────────────────────────────────
if [ -d "$TRACKING_ROOT/.zskills/tracking" ]; then
  if ! git -C "$TRACKING_ROOT" check-ignore -q "$TRACKING_ROOT/.zskills/tracking" 2>/dev/null; then
    fail ".zskills/tracking/ exists but is not ignored by git"
  fi
fi

PIPELINE_DIR="$TRACKING_ROOT/.zskills/tracking/$PIPELINE_ID"
[ -d "$PIPELINE_DIR" ] || fail "tracking pipeline directory missing: $PIPELINE_DIR"

require_marker() {
  local marker="$1"
  [ -e "$PIPELINE_DIR/$marker" ] || fail "missing marker: $marker"
}

if [ -d "$PIPELINE_DIR" ]; then
  case "$PIPELINE_ID" in
    fix-issues.*)
      # fix-issues arm (codex fork) — future-proofs a `/fix-issues N` runner
      # mode; validated markers mirror the fix-issues pipeline vocabulary.
      require_marker "pipeline.fix-issues.$TRACKING_ID"
      for suffix in preflight prioritize execute verify report; do
        require_marker "step.fix-issues.$TRACKING_ID.$suffix"
      done
      if [ "$MODE" = "pre-land" ] || [ "$MODE" = "pre-push" ]; then
        require_marker "step.fix-issues.$TRACKING_ID.land"
        compgen -G "$PIPELINE_DIR/issue.*.selected" >/dev/null || fail "no per-issue selected markers found"
        compgen -G "$PIPELINE_DIR/issue.*.verified" >/dev/null || fail "no per-issue verified markers found"
      fi
      ;;
    *)
      # run-plan arm.
      for suffix in implement verify report; do
        require_marker "step.run-plan.$TRACKING_ID.$suffix"
      done
      if [ "$MODE" = "pre-continue" ]; then
        require_marker "handoff.run-plan.$TRACKING_ID"
        # Premature-final detection IN-GATE (cc fork): a non-final chunk that
        # leaves final markers behind is a defect even when the runner's own
        # ladder would also catch it — the gate is independently invokable.
        if [ -e "$PIPELINE_DIR/step.run-plan.$TRACKING_ID.land" ]; then
          fail "premature final marker present before plan completion: step.run-plan.$TRACKING_ID.land"
        fi
        if [ -e "$PIPELINE_DIR/fulfilled.run-plan.$TRACKING_ID" ]; then
          fail "premature final marker present before plan completion: fulfilled.run-plan.$TRACKING_ID"
        fi
      fi
      if [ "$MODE" = "post-land" ]; then
        require_marker "step.run-plan.$TRACKING_ID.land"
        require_marker "fulfilled.run-plan.$TRACKING_ID"
        # Final-verify pair — the current Phase 5b gate (spec change 8;
        # missing from BOTH prior forks).
        require_marker "requires.verify-changes.final.$TRACKING_ID"
        require_marker "fulfilled.verify-changes.final.$TRACKING_ID"
      fi
      ;;
  esac

  # Verifier evidence — required in EVERY mode for both arms. The set
  # INCLUDES step.verify-changes.<tid>.tests-run (prompted-but-unvalidated in
  # the codex fork; required here per spec change 8).
  # step.verify-changes.<tid>.manual-verified is TOLERATED: UI phases write
  # it in addition to the required set; it is never required and its
  # presence is never an error.
  require_marker "requires.verify-changes.$TRACKING_ID"
  require_marker "step.verify-changes.$TRACKING_ID.tests-run"
  require_marker "step.verify-changes.$TRACKING_ID.complete"
  require_marker "fulfilled.verify-changes.$TRACKING_ID"
fi

# ── report — config-resolved path + current Phase-5 patterns ─────────────────
if [ -z "$REPORT_PATH" ]; then
  SLUG="${PLAN_SLUG:-}"
  if [ -z "$SLUG" ] && [ -n "$PLAN_FILE" ]; then
    SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')
  fi
  if [ -n "$SLUG" ]; then
    # Resolve output.reports_dir from the discovered config, the same key
    # zskills-paths.sh reads (ported-tree discovery order, spec change 15).
    REPORTS_DIR_REL=$("$PYTHON" - "$ARTIFACT_ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
for rel in (".agents/zskills-config.json", "zskills-config.json",
            ".codex/zskills-config.json", ".claude/zskills-config.json"):
    path = os.path.join(root, rel)
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as f:
                cfg = json.load(f)
        except Exception:
            cfg = {}
        value = cfg.get("output", {}).get("reports_dir", "")
        if isinstance(value, str) and value:
            print(value)
        break
PY
)
    # allow-hardcoded: docs/reports reason: built-in fallback mirroring zskills-paths.sh output.reports_dir default, used only when no discovered config sets the key
    [ -n "$REPORTS_DIR_REL" ] || REPORTS_DIR_REL="docs/reports"
    case "$REPORTS_DIR_REL" in
      /*) REPORT_PATH="$REPORTS_DIR_REL/plan-$SLUG.md" ;;
      *)  REPORT_PATH="$ARTIFACT_ROOT/$REPORTS_DIR_REL/plan-$SLUG.md" ;;
    esac
  fi
fi

if [ -n "$REPORT_PATH" ]; then
  case "$REPORT_PATH" in
    /*) ;;
    *) REPORT_PATH="$ARTIFACT_ROOT/$REPORT_PATH" ;;
  esac
  if [ ! -f "$REPORT_PATH" ]; then
    fail "report missing: $REPORT_PATH"
  else
    # Current Phase-5 report format (spec change 8). Deliberately NOT
    # requiring "Scope Assessment" — that section belongs to the
    # verify-changes report; the fork gates validated a runner-invented
    # contract there.
    grep -qE '^## Phase' "$REPORT_PATH"        || fail "report missing required pattern: ^## Phase"
    grep -qE '\*\*Status:\*\*' "$REPORT_PATH"  || fail "report missing required pattern: **Status:**"
    grep -qE '^### Verification' "$REPORT_PATH" || fail "report missing required pattern: ### Verification"
  fi
else
  fail "report path unresolvable: pass --report, --plan-slug, or --plan-file"
fi

# ── plan file presence at the artifact root ──────────────────────────────────
if [ -n "$PLAN_FILE" ]; then
  case "$PLAN_FILE" in
    /*) ;;
    *) PLAN_FILE="$ARTIFACT_ROOT/$PLAN_FILE" ;;
  esac
  [ -f "$PLAN_FILE" ] || fail "plan file missing at artifact root: $PLAN_FILE"
fi

# ── base-ref availability (advisory) ─────────────────────────────────────────
if [ -n "$BASE_REF" ]; then
  git -C "$ARTIFACT_ROOT" rev-parse --verify "$BASE_REF" >/dev/null 2>&1 \
    || warn "base ref not available for freshness check: $BASE_REF"
fi

# ── dirty-tree scan (artifact root; ignored .zskills state exempt) ───────────
STATUS=$(git -C "$ARTIFACT_ROOT" status --short --untracked-files=all)
if [ -n "$STATUS" ]; then
  while IFS= read -r line; do
    path=${line#???}
    case "$path" in
      .zskills/*|.zskills-tracked) ;;
      *) fail "uncommitted or untracked project artifact remains: $line" ;;
    esac
  done <<EOF
$STATUS
EOF
fi

if [ "$FAILED" -ne 0 ]; then
  echo "zskills-gate artifact root: $ARTIFACT_ROOT" >&2
  echo "zskills-gate tracking root: $TRACKING_ROOT" >&2
  echo "zskills-gate FAILED for mode '$MODE'." >&2
  exit 1
fi

echo "zskills-gate passed for mode '$MODE'."
