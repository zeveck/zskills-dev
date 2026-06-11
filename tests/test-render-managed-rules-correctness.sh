#!/usr/bin/env bash
# tests/test-render-managed-rules-correctness.sh
#
# Correctness gate for scripts/render-managed-rules.py +
# scripts/managed_rules_substitution.py.
#
# INSTALL_REDESIGN Phase 4 — the template is fully DE-PARAMETERIZED and the
# substitution map is EMPTY, so the render contract is now:
#   - pass-through: output is byte-identical to the template;
#   - the unsubstituted-placeholder guard STILL fails loudly (exit 2) on any
#     surviving {{TOKEN}} (regression in the shipped template, or a
#     consumer-authored template carrying retired tokens);
#   - NEW no-config mode: --config is optional; when omitted the renderer
#     loads the canonical built-in defaults
#     (skills/update-zskills/scripts/zskills-defaults.json) and the render
#     succeeds with no config file at either tier.
# The pre-Phase-4 fixtures asserting the 10-placeholder golden render and the
# empty-field TODO fallbacks were subject-removals: those placeholders (and
# their TODO fallbacks) no longer exist in the map or the template.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

RENDERER="scripts/render-managed-rules.py"
DEFAULTS="skills/update-zskills/scripts/zskills-defaults.json"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== render-managed-rules correctness (de-parameterized, Phase 4) ==="

# ── Fixture: a token-less template (the post-Phase-4 norm) ────────────────
cat > "$TMP/tmpl.md" <<'EOF'
# Project Agent Rules

Resolve test commands from `.claude/zskills-config.json` at point of use
via the canonical prelude (`$UNIT_TEST_CMD`, `$FULL_TEST_CMD`).

## Worktree Rules

date: $(TZ=${TIMEZONE:-UTC} date -Iseconds)
EOF

cat > "$TMP/cfg.json" <<'EOF'
{
  "project_name": "demo",
  "timezone": "UTC",
  "dev_server": { "default_port": 8080, "cmd": "make serve" },
  "testing": { "unit_cmd": "make test", "full_cmd": "make test-all", "file_patterns": ["a.sh"] },
  "ui": { "auth_bypass": "localStorage.x=1" }
}
EOF

# 1. With a config: render is a byte-identical pass-through (empty map; the
#    config is accepted and ignored — the D24 call shape is unchanged).
"$PYTHON" "$RENDERER" --config "$TMP/cfg.json" --template "$TMP/tmpl.md" --out "$TMP/out.md"
rc=$?
if [ "$rc" -eq 0 ] && diff -q "$TMP/tmpl.md" "$TMP/out.md" >/dev/null 2>&1; then
  pass "1. --config render is a byte-identical pass-through of the template"
else
  fail "1. --config render mismatch (rc=$rc)"
  diff "$TMP/tmpl.md" "$TMP/out.md" | head -10 | sed 's/^/      /'
fi

# 2. NO-CONFIG mode: --config omitted → canonical defaults loaded, render
#    succeeds with no config file at either tier, same pass-through output.
"$PYTHON" "$RENDERER" --template "$TMP/tmpl.md" --out "$TMP/out-nocfg.md"
rc=$?
if [ "$rc" -eq 0 ] && diff -q "$TMP/tmpl.md" "$TMP/out-nocfg.md" >/dev/null 2>&1; then
  pass "2. no-config mode renders successfully (canonical defaults) and matches the template"
else
  fail "2. no-config render failed (rc=$rc) or diverged"
fi

# 2b. The no-config mode genuinely loads the CANONICAL defaults artifact:
#     pointing --defaults at a missing file must fail (no silent in-renderer
#     defaults copy), and the canonical file must parse as JSON.
"$PYTHON" "$RENDERER" --template "$TMP/tmpl.md" --out "$TMP/x.md" \
  --defaults "$TMP/nonexistent.json" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "2b. no-config mode fails closed when the defaults artifact is missing (rc=$rc)"
else
  fail "2b. renderer succeeded without any defaults source (hidden in-renderer copy?)"
fi
if "$PYTHON" -c 'import json,sys; json.load(open(sys.argv[1]))' "$DEFAULTS" 2>/dev/null; then
  pass "2c. canonical $DEFAULTS parses as JSON"
else
  fail "2c. canonical $DEFAULTS missing or invalid JSON"
fi

# 2d. Canonical defaults carry the documented built-in values (the plan's
#     Phase 4 table — ported from the materialiser seed).
DEFAULTS_CHECK="$("$PYTHON" - "$DEFAULTS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
checks = {
    "timezone": d.get("timezone") == "UTC",
    "landing": d.get("execution", {}).get("landing") == "direct",
    "main_protected": d.get("execution", {}).get("main_protected") is False,
    "branch_prefix": d.get("execution", {}).get("branch_prefix") == "feat/",
    "output_file": d.get("testing", {}).get("output_file") == ".test-results.txt",
    "default_port": d.get("dev_server", {}).get("default_port") == 8080,
    "ci_auto_fix": d.get("ci", {}).get("auto_fix") is True,
    "ci_max": d.get("ci", {}).get("max_fix_attempts") == 2,
    "min_model": d.get("agents", {}).get("min_model") == "auto",
    "plans_dir": d.get("output", {}).get("plans_dir") == "docs/plans",
    "issues_dir": d.get("output", {}).get("issues_dir") == "docs/issues",
    "reports_dir": d.get("output", {}).get("reports_dir") == "docs/reports",
}
bad = [k for k, ok in checks.items() if not ok]
print("OK" if not bad else "BAD:" + ",".join(bad))
PY
)"
if [ "$DEFAULTS_CHECK" = "OK" ]; then
  pass "2d. canonical defaults carry the documented built-in values"
else
  fail "2d. canonical defaults wrong: $DEFAULTS_CHECK"
fi

# 3. Leftover-placeholder guard: a {{TOKEN}} in the template → exit 2 (a
#    broken {{...}} must never ship — retired tokens fail loudly).
printf 'stale={{DEFAULT_PORT}}\n' > "$TMP/bad.md"
"$PYTHON" "$RENDERER" --config "$TMP/cfg.json" --template "$TMP/bad.md" --out "$TMP/badout.md" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "3. leftover/retired {{TOKEN}} triggers exit 2 (no broken {{...}} shipped)"
else
  fail "3. leftover placeholder did NOT trigger exit 2 (rc=$rc)"
fi

# (Former cases 4–5 — the --sentinel prefix-injection arm — were deleted in
# INSTALL_REDESIGN Phase 7 with the D20 sentinel convention:
# subject-removal; the renderer no longer has a --sentinel flag.)

# 6. The REAL shipped template is de-parameterized: zero {{ tokens, and the
#    real render (no-config) is a byte-identical pass-through.
if [ "$(grep -c '{{' "$REPO_ROOT/CLAUDE_TEMPLATE.md")" = "0" ]; then
  pass "6. shipped CLAUDE_TEMPLATE.md carries zero {{ tokens"
else
  fail "6. shipped CLAUDE_TEMPLATE.md still carries {{ tokens: $(grep -n '{{' "$REPO_ROOT/CLAUDE_TEMPLATE.md" | head -3)"
fi
"$PYTHON" "$RENDERER" --template "$REPO_ROOT/CLAUDE_TEMPLATE.md" --out "$TMP/real.md"
if [ "$?" -eq 0 ] && diff -q "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$TMP/real.md" >/dev/null 2>&1; then
  pass "6b. real template no-config render is a byte-identical pass-through"
else
  fail "6b. real template no-config render failed or diverged"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
