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
#   <reason>      Optional short string (informational; not consumed by
#                 the filter). Currently ignored; reserved for future use.
#
# Behavior:
#   - Resolves `$MAIN_ROOT` from `$ZSKILLS_MAIN_ROOT` if set, else from
#     `git rev-parse --git-common-dir`.
#   - Creates `.zskills/monitor-state.json` with `{}` if absent.
#   - Sets `data["issues"]["skipped"][str(N)] = "<skip-code>"`.
#   - Idempotent: if the same code is already recorded, exits 0 silently;
#     if a different code is recorded, overwrites (latest-classification
#     wins — the orchestrator may re-triage and re-classify).
#   - Atomic write via Python tempfile + `os.replace`.
#
# Exit:
#   0 — write succeeded (or no-op idempotent re-write).
#   1 — usage error (missing args, invalid skip-code, $MAIN_ROOT unresolvable).
#   2 — JSON parse / IO error.

set -u

if [ "$#" -lt 2 ]; then
  echo "usage: record-skip.sh <issue-num> <skip-code> [<reason>]" >&2
  exit 1
fi

ISSUE_NUM="$1"
SKIP_CODE="$2"
# reason argument reserved for future use; not consumed yet.

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

python3 - "$STATE_FILE" "$ISSUE_NUM" "$SKIP_CODE" <<'PY' || exit 2
import json, os, sys, tempfile

path, num_s, code = sys.argv[1], sys.argv[2], sys.argv[3]

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

# Idempotent — same code recorded already, exit silently.
if skipped.get(num_s) == code:
    print(f"/fix-issues: #{num_s} already recorded as skipped ({code}); no-op.", file=sys.stderr)
    sys.exit(0)

prev = skipped.get(num_s)
skipped[num_s] = code

tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(data, tmp, indent=2)
tmp.write('\n')
tmp.close()
os.replace(tmp.name, path)

if prev:
    print(f"/fix-issues: #{num_s} skip-state updated ({prev} -> {code}).", file=sys.stderr)
else:
    print(f"/fix-issues: #{num_s} recorded as skipped ({code}).", file=sys.stderr)
PY
