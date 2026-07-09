#!/usr/bin/env bash
# scripts/porting/render-agents-md.sh — AGENTS.md renderer wrapper
# (CODEX_PORT_PLAN Phase 3, WI 3.5).
#
# THIN WRAPPER over the ONE canonical renderer,
# scripts/render-managed-rules.py (D24: extend, never fork). It passes
# --template/--out/--defaults/--config through untouched and adds exactly one
# post-render check: Codex concatenates the AGENTS.md chain under a 32 KiB
# DEFAULT cap (`project_doc_max_bytes` — capability map row "CLAUDE.md /
# managed rules"; probe id agentsmd.cap-32k). If the rendered output exceeds
# 32768 bytes this wrapper exits 1 with the dual-delivery instruction.
#
# This wrapper does NOT transform content — content transformation is
# porting-agent work per the guide's AGENTS.md recipe.
#
# USAGE
#   render-agents-md.sh --template <ported-template.md> --out <target>/AGENTS.md
#                       [--defaults <defaults.json>] [--config <cfg.json>]
#
# Exit codes: 0 = rendered and within the cap; 1 = render failed or output
# exceeds the 32 KiB default cap; 2 = usage error.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: render-agents-md.sh --template <tmpl.md> --out <AGENTS.md>
                           [--defaults <defaults.json>] [--config <cfg.json>]
Thin wrapper over scripts/render-managed-rules.py with the Codex 32 KiB
AGENTS.md default-cap check (project_doc_max_bytes).
EOF
}

die() {
  echo "render-agents-md: $*" >&2
  exit 2
}

# Codex's AGENTS.md default cap (bytes). Raised per-project via
# `project_doc_max_bytes` in Codex config — see the failure message below.
AGENTS_MD_DEFAULT_CAP=32768

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
RENDERER="$SCRIPT_DIR/../render-managed-rules.py"
[ -f "$RENDERER" ] || die "canonical renderer not found at $RENDERER"

TEMPLATE=""
OUT=""
PASS_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --template)
      [ $# -ge 2 ] || die "--template needs a path"
      TEMPLATE="$2"; shift 2 ;;
    --out)
      [ $# -ge 2 ] || die "--out needs a path"
      OUT="$2"; shift 2 ;;
    --defaults|--config)
      [ $# -ge 2 ] || die "$1 needs a path"
      PASS_ARGS+=("$1" "$2"); shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage >&2; die "unknown argument: $1" ;;
  esac
done
[ -n "$TEMPLATE" ] || { usage >&2; die "missing --template"; }
[ -n "$OUT" ] || { usage >&2; die "missing --out"; }

# Canonical render — pass-through, no content transformation.
if ! "$PYTHON" "$RENDERER" --template "$TEMPLATE" --out "$OUT" \
     ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}; then
  echo "render-agents-md: FAIL — canonical renderer exited non-zero" >&2
  exit 1
fi

# Post-render cap check. BSD/MSYS-safe byte count: `wc -c < file` (arithmetic
# expansion strips BSD wc's leading whitespace).
BYTES=$(( $(wc -c < "$OUT") ))
if [ "$BYTES" -gt "$AGENTS_MD_DEFAULT_CAP" ]; then
  cat >&2 <<EOF
render-agents-md: FAIL — rendered AGENTS.md is $BYTES bytes, over Codex's
$AGENTS_MD_DEFAULT_CAP-byte default cap (project_doc_max_bytes). Dual-delivery
instruction: split — keep a SHORT AGENTS.md and deliver the rest per-session
via a SessionStart-hook \`additionalContext\` payload (the exact analog of the
plugin lane's session-rules-context.sh; see the guide's AGENTS.md recipe) —
or raise \`project_doc_max_bytes\` in the Codex config.
EOF
  exit 1
fi

echo "render-agents-md: rendered $OUT ($BYTES bytes, within the $AGENTS_MD_DEFAULT_CAP-byte default cap)"
exit 0
