#!/usr/bin/env bash
# scripts/porting/codex-scan-gate.sh — fail-closed policy caller for the
# Claude-construct scanner (CODEX_PORT_PLAN Phase 3, WI 3.2 — the
# zsh-tripwire pattern: the scanner is a pure reporter, THIS script is the
# policy).
#
# PINNED CLI (later phases invoke it exactly this way):
#   codex-scan-gate.sh <root> [--mode gate|discover] [--scope <path>…]
#
#   --mode   default `gate`. gate = ported-tree judgment; discover =
#            porting-worklist census.
#   --scope  repeatable, paths relative to <root>; passes through VERBATIM
#            to codex-scan.py --scope (the slice phases' scoped-gate ACs
#            depend on this).
#
# BEHAVIOR
#   gate mode:     exit 1 on violations>0 OR unknown>0 OR an unparseable
#                  summary line.
#   discover mode: enforces the anti-vacuous census floors below; exit 1 if
#                  any class's hit count is below its floor, if any floor
#                  class is missing from the summary, or on an unparseable
#                  summary. FLOOR SCOPE PIN: floors are derived from, and
#                  the census check runs over, the SAME scope — `skills/` of
#                  the tree under test. When no --scope is passed and
#                  <root>/skills exists, discover mode therefore scopes the
#                  scan to `skills` (deriving floors over the full default
#                  scope while checking over skills/ would let a class
#                  concentrated outside skills/, e.g. plugin-root, set an
#                  unclearable floor).
#
# Exit codes: 0 = gate passed, 1 = gate failed, 2 = usage error.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: codex-scan-gate.sh <root> [--mode gate|discover] [--scope <path>...]
Fail-closed caller for scripts/porting/codex-scan.py. Default mode: gate.
EOF
}

die() {
  echo "codex-scan-gate: $*" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Anti-vacuous census floors (discover mode). Derived at implementation time
# (2026-07-09) from a skills/-scoped discovery run over THIS repo:
#   python3 scripts/porting/codex-scan.py --mode discover skills/
#   → per-class=cron:107,agent-dispatch:60,bg-monitor:18,skill-tool:29,
#     arguments:162,ask-user:9,plugin-root:819,project-dir:415,
#     frontmatter-flags:18,claude-model-dispatch:8
# Each floor is set at <=50% of the observed count and >0 for every v1 class
# (re-derivation, not a frozen expectation of exact counts — the floor's job
# is catching a gutted scanner or a vacuous scan, never pinning the tree).
# ---------------------------------------------------------------------------
CENSUS_FLOORS=(
  "cron:53"
  "agent-dispatch:30"
  "bg-monitor:9"
  "skill-tool:14"
  "arguments:81"
  "ask-user:4"
  "plugin-root:400"
  "project-dir:200"
  "frontmatter-flags:9"
  "claude-model-dispatch:4"
)

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
[ -n "$PYTHON" ] || die "install Python 3 (or set ZSKILLS_PYTHON)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/codex-scan.py"
[ -f "$SCANNER" ] || die "scanner not found at $SCANNER"

# ── argument parsing (pinned CLI) ───────────────────────────────────────────
ROOT=""
MODE="gate"
SCOPES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      [ $# -ge 2 ] || die "--mode needs a value (gate|discover)"
      MODE="$2"; shift 2 ;;
    --scope)
      [ $# -ge 2 ] || die "--scope needs a path"
      SCOPES+=("$2"); shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      usage >&2; die "unknown flag: $1" ;;
    *)
      [ -z "$ROOT" ] || die "multiple roots given: '$ROOT' and '$1'"
      ROOT="$1"; shift ;;
  esac
done
[ -n "$ROOT" ] || { usage >&2; die "missing <root>"; }
[ -d "$ROOT" ] || die "root is not a directory: $ROOT"
case "$MODE" in gate|discover) ;; *) die "invalid --mode: $MODE" ;; esac

# Floor scope pin (discover mode): census over skills/ of the tree under
# test, the SAME scope the floors were derived from (see header).
if [ "$MODE" = "discover" ] && [ ${#SCOPES[@]} -eq 0 ] && [ -d "$ROOT/skills" ]; then
  SCOPES=("skills")
fi

SCOPE_ARGS=()
for s in "${SCOPES[@]:-}"; do
  [ -n "$s" ] || continue
  SCOPE_ARGS+=(--scope "$s")
done

SCAN_OUT="$(mktemp "${TMPDIR:-/tmp}/codex-scan-gate.XXXXXX")"
trap 'rm -f "$SCAN_OUT"' EXIT

"$PYTHON" "$SCANNER" --mode "$MODE" ${SCOPE_ARGS[@]+"${SCOPE_ARGS[@]}"} "$ROOT" \
  > "$SCAN_OUT" || die "scanner invocation failed (it should never exit non-zero)"
cat "$SCAN_OUT"

SUMMARY="$(grep '^CODEX-SCAN-SUMMARY:' "$SCAN_OUT" | tail -1 || true)"

# ── fail-closed summary parse ───────────────────────────────────────────────
if ! [[ "$SUMMARY" =~ ^CODEX-SCAN-SUMMARY:\ files=([0-9]+)\ hits=([0-9]+)\ violations=([0-9]+)\ unknown=([0-9]+)\ per-class=([a-z0-9:,-]+)$ ]]; then
  echo "CODEX-SCAN-GATE: FAIL — unparseable summary line: '${SUMMARY:-<absent>}'" >&2
  exit 1
fi
FILES="${BASH_REMATCH[1]}"
VIOLATIONS="${BASH_REMATCH[3]}"
UNKNOWN="${BASH_REMATCH[4]}"
PER_CLASS="${BASH_REMATCH[5]}"

if [ "$MODE" = "gate" ]; then
  RC=0
  if [ "$VIOLATIONS" -gt 0 ]; then
    echo "CODEX-SCAN-GATE: FAIL — $VIOLATIONS violation(s) without a codex-port-allow marker (see findings above)" >&2
    RC=1
  fi
  if [ "$UNKNOWN" -gt 0 ]; then
    echo "CODEX-SCAN-GATE: FAIL — $UNKNOWN unknown construct(s); record the ruling and append a class to the scanner's class table (self-amendment rule) — never a per-line waiver" >&2
    RC=1
  fi
  if [ "$RC" -eq 0 ]; then
    echo "CODEX-SCAN-GATE: PASS (gate) — files=$FILES violations=0 unknown=0"
  fi
  exit "$RC"
fi

# ── discover mode: anti-vacuous census floors ───────────────────────────────
RC=0
for entry in "${CENSUS_FLOORS[@]}"; do
  cid="${entry%%:*}"
  floor="${entry##*:}"
  count=""
  if [[ ",$PER_CLASS," =~ ,"$cid":([0-9]+), ]]; then
    count="${BASH_REMATCH[1]}"
  fi
  if [ -z "$count" ]; then
    echo "CODEX-SCAN-GATE: FAIL — class '$cid' missing from the summary per-class census (scanner class table drifted from the floor table?)" >&2
    RC=1
    continue
  fi
  if [ "$count" -lt "$floor" ]; then
    echo "CODEX-SCAN-GATE: FAIL — census floor: class '$cid' hit count $count < floor $floor (vacuous scan, or the scanner's patterns regressed)" >&2
    RC=1
  fi
done
if [ "$RC" -eq 0 ]; then
  echo "CODEX-SCAN-GATE: PASS (discover census) — files=$FILES, every class cleared its floor"
fi
exit "$RC"
