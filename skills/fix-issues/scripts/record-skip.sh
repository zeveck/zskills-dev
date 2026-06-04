#!/bin/bash
# record-skip.sh — persist a /fix-issues triage-decline as a skip-tag in
# `$MAIN_ROOT/.zskills/monitor-state.json` under `issues.skipped`.
#
# Issue #808: When `/fix-issues` declines an issue as plan-scale (or any
# other auto-skip tier — bug-unclear-cause, needs-decision, deferred),
# that decision was only *reported* to SPRINT_REPORT.md, never persisted
# as machine-readable skip-state. Every subsequent fire re-triaged and
# re-declined the same issue indefinitely (acute in dashboard mode where
# raw-dragged issues have no tracker row at all — #803 case).
#
# This helper writes the decline to `monitor-state.json` (gitignored,
# symmetric with `issues.reconsider`) so the next fire's
# `filter-unresearched-candidates.sh` drops the candidate BEFORE triage.
# `reconsider <N>` clears the entry (the two are duals).
#
# `monitor-state.json` is gitignored by design — it holds operational
# queue state. We deliberately do NOT write the skip-tag to a committed
# tracker file from the main-checkout triage path: a one-line skip-write
# during a fire would leave main's working tree dirty (gets swept into
# the next commit; violates clean-tree rule) or trigger a worktree + PR +
# land cycle per skip (absurd overhead). Researched-row promotion to
# ISSUES_PLAN.md still happens via the existing scratchpad path inside
# the per-issue worktree (sprint.md ~1888 / ~2106) — that path is durable
# tracker knowledge; this script is operational queue state.
#
# Usage:
#   bash record-skip.sh <issue-num> <skip-code> [<reason>]
#
# Arguments:
#   <issue-num>   Positive integer (GitHub issue number). REQUIRED.
#   <skip-code>   One of: plan-scale | bug-unclear-cause | needs-decision
#                 | deferred. REQUIRED. These mirror the canonical
#                 dashboard skip-codes the filter recognizes.
#   <reason>      Optional short free-text string (e.g. "needs author A/B/C
#                 scope decision"). When present, the persisted entry becomes
#                 the dict shape `{"code": <code>, "reason": <reason>}` and the
#                 reason flows through to the dashboard skip chip's label
#                 (#862). When absent, the legacy bare-string shape
#                 `"<skip-code>"` is preserved (back-compat).
#
# Behavior:
#   - Resolves `$MAIN_ROOT` from `$ZSKILLS_MAIN_ROOT` if set, else from
#     `git rev-parse --git-common-dir`.
#   - Creates `.zskills/monitor-state.json` with `{}` if absent.
#   - Sets `data["issues"]["skipped"][str(N)]` to either the bare code
#     string (no reason given) or `{"code": <code>, "reason": <reason>}`
#     (reason given). Both shapes are accepted by every reader
#     (filter-unresearched-candidates.sh + collect.py).
#   - Idempotent: if the same {code, reason} is already recorded, exits 0
#     silently; if a different code/reason is recorded, overwrites
#     (latest-classification wins — the orchestrator may re-triage and
#     re-classify).
#   - Atomic write via Python tempfile + `os.replace`.
#
# Exit:
#   0 — write succeeded (or no-op idempotent re-write).
#   1 — usage error (missing args, invalid skip-code, $MAIN_ROOT unresolvable).
#   2 — JSON parse / IO error.

set -u

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
_RS_PYTHON="$(zskills_resolve_python || true)"
if [ -z "$_RS_PYTHON" ]; then
  echo "record-skip.sh: install Python 3 (or set ZSKILLS_PYTHON)" >&2
  exit 2
fi

if [ "$#" -lt 2 ]; then
  echo "usage: record-skip.sh <issue-num> <skip-code> [<reason>]" >&2
  exit 1
fi

ISSUE_NUM="$1"
SKIP_CODE="$2"
# Optional free-text reason (#862). Empty when omitted; when present it is
# persisted alongside the code as `{"code": ..., "reason": ...}` and rendered
# in the dashboard skip chip's label.
REASON="${3:-}"

case "$ISSUE_NUM" in
  ''|*[!0-9]*)
    echo "record-skip.sh: invalid issue number '$ISSUE_NUM' (must be positive integer)" >&2
    exit 1
    ;;
esac

case "$SKIP_CODE" in
  plan-scale|bug-unclear-cause|needs-decision|deferred) ;;
  *)
    echo "record-skip.sh: invalid skip-code '$SKIP_CODE' (expected plan-scale|bug-unclear-cause|needs-decision|deferred)" >&2
    exit 1
    ;;
esac

MAIN_ROOT="${ZSKILLS_MAIN_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd)}"
if [ -z "$MAIN_ROOT" ] || [ ! -d "$MAIN_ROOT" ]; then
  echo "record-skip.sh: cannot resolve MAIN_ROOT (set ZSKILLS_MAIN_ROOT or run from inside a git repo)" >&2
  exit 1
fi

STATE_DIR="$MAIN_ROOT/.zskills"
STATE_FILE="$STATE_DIR/monitor-state.json"
mkdir -p "$STATE_DIR"

# Initialise empty state file if missing — symmetric with how
# reconsider.md treats it.
if [ ! -f "$STATE_FILE" ]; then
  printf '{}\n' > "$STATE_FILE"
fi

"$_RS_PYTHON" - "$STATE_FILE" "$ISSUE_NUM" "$SKIP_CODE" "$REASON" <<'PY' || exit 2
import json, os, sys, tempfile

path, num_s, code = sys.argv[1], sys.argv[2], sys.argv[3]
reason = sys.argv[4] if len(sys.argv) > 4 else ""
reason = reason.strip()

try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (json.JSONDecodeError, FileNotFoundError):
    data = {}

issues = data.setdefault('issues', {})
skipped = issues.setdefault('skipped', {})
if not isinstance(skipped, dict):
    # Defensive: replace malformed value with a fresh dict.
    skipped = {}
    issues['skipped'] = skipped


def _norm(entry):
    """Normalise either skip-entry shape to (code, reason) for comparison.

    Accepts both the legacy bare-string shape (`"<code>"`) and the
    dict shape (`{"code": ..., "reason": ...}`) so idempotency holds
    across a mix of old and new writers (#862)."""
    if isinstance(entry, dict):
        return (entry.get('code'), entry.get('reason') or '')
    return (entry, '')


# When a reason is supplied, persist the dict shape so the chip can
# render it; otherwise keep the legacy bare-string shape (back-compat).
new_value = {'code': code, 'reason': reason} if reason else code

# Idempotent — same (code, reason) recorded already, exit silently.
prev_entry = skipped.get(num_s)
if _norm(prev_entry) == _norm(new_value):
    print(f"/fix-issues: #{num_s} already recorded as skipped ({code}); no-op.", file=sys.stderr)
    sys.exit(0)

prev_code = _norm(prev_entry)[0] if prev_entry is not None else None
skipped[num_s] = new_value

tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(data, tmp, indent=2)
tmp.write('\n')
tmp.close()
os.replace(tmp.name, path)

suffix = f" — {reason}" if reason else ""
if prev_code:
    print(f"/fix-issues: #{num_s} skip-state updated ({prev_code} -> {code}{suffix}).", file=sys.stderr)
else:
    print(f"/fix-issues: #{num_s} recorded as skipped ({code}{suffix}).", file=sys.stderr)
PY
