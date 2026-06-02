#!/bin/bash
# .nojekyll regression gate (DOC_VIEWER Phase 5).
#
# `.nojekyll` at repo root is the load-bearing toggle that disables
# GitHub Pages' Jekyll preprocessor. Without it, Jekyll's Liquid templating
# evaluates `{{...}}` across ~700 of our MD files and silently breaks the
# prod build — every `{{TODO: …}}` or doc literal becomes a parse error
# or a missing variable substitution.
#
# This test asserts:
#   1. `.nojekyll` exists at repo root.
#   2. It is empty (the canonical form; documented in CLAUDE.md).
#
# Emits the canonical `Results: N passed, M failed` line consumed by
# tests/run-all.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NJ="$REPO_ROOT/.nojekyll"

pass=0
fail=0
check() {
  local name="$1" cond="$2" msg="${3:-}"
  if [[ "$cond" == "1" ]]; then
    echo "PASS  $name"
    ((pass++))
  else
    echo "FAIL  $name  $msg"
    ((fail++))
  fi
}

# T1: .nojekyll exists at repo root.
check "nojekyll.exists" "$([[ -f "$NJ" ]] && echo 1 || echo 0)" \
  "$NJ not found — GitHub Pages will run Jekyll across ~700 MD files and break {{…}}"

# T2: .nojekyll is empty (canonical form per CLAUDE.md). GitHub Pages
#     treats ANY presence as a disable signal, but the canonical form is
#     zero bytes. A non-empty .nojekyll suggests someone mistook it for a
#     config file and shoved Jekyll directives into it.
if [[ -f "$NJ" ]]; then
  size=$(wc -c < "$NJ" | tr -d ' ')
  check "nojekyll.empty" "$([[ "$size" -eq 0 ]] && echo 1 || echo 0)" \
    ".nojekyll is $size bytes; canonical form is empty"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
