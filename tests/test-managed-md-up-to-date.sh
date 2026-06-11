#!/bin/bash
# tests/test-managed-md-up-to-date.sh
#
# Asserts that `.claude/rules/zskills/managed.md` matches the live render of
# `CLAUDE_TEMPLATE.md` against `.claude/zskills-config.json`.
#
# Companion of `/update-zskills --rerender` (Step D in
# `.claude/skills/update-zskills/SKILL.md`). If this test fails, the tracked
# rendered file has drifted from its inputs (someone edited CLAUDE_TEMPLATE.md
# or .claude/zskills-config.json but forgot to rerender). Remediation:
#   /update-zskills --rerender
#   git add .claude/rules/zskills/managed.md
#   git commit
#
# W2.7 (D24, F-DA2-2): this test no longer carries its own inlined
# `subs = {...}` substitution map. It invokes the canonical renderer
# `scripts/render-managed-rules.py` (which routes through the single
# source-of-truth `scripts/managed_rules_substitution.py`) and diffs its
# output against the checked-in managed.md — exactly the Step D code path.
# One map, three callers; no divergence possible.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

PASS=0
FAIL=0

RENDER_TMP="$(mktemp)"
trap 'rm -f "$RENDER_TMP"' EXIT

# Render via the canonical Step-D renderer (the checked-in managed.md is
# the /update-zskills-lane form).
render_err="$(
  "$PYTHON" scripts/render-managed-rules.py \
    --config .claude/zskills-config.json \
    --template CLAUDE_TEMPLATE.md \
    --out "$RENDER_TMP" 2>&1
)"
rc=$?

if [ "$rc" -eq 2 ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: render produced unsubstituted placeholders (template/substitution map out of sync)"
  echo ""
  echo "$render_err"
elif [ "$rc" -ne 0 ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: renderer errored (rc=$rc)"
  echo ""
  echo "$render_err"
elif diff -q "$RENDER_TMP" .claude/rules/zskills/managed.md >/dev/null 2>&1; then
  PASS=$((PASS + 1))
  echo "PASS: managed.md matches live render of CLAUDE_TEMPLATE.md + .claude/zskills-config.json"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: .claude/rules/zskills/managed.md is stale relative to CLAUDE_TEMPLATE.md / .claude/zskills-config.json"
  echo ""
  diff -u .claude/rules/zskills/managed.md "$RENDER_TMP" \
    | sed -e '1s#.*#--- .claude/rules/zskills/managed.md (tracked)#' \
          -e '2s#.*#+++ render(CLAUDE_TEMPLATE.md, .claude/zskills-config.json) (live)#' \
    | head -200
  echo ""
  echo "Remediation: run \`/update-zskills --rerender\` and commit the result."
fi

echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
