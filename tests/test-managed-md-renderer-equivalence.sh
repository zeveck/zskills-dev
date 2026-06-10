#!/usr/bin/env bash
# tests/test-managed-md-renderer-equivalence.sh
#
# Phase 2 (D24, A11, F-DA1-5) — the renderer-equivalence belt-and-suspenders
# gate. Post-W2.7 there is ONE substitution map
# (scripts/managed_rules_substitution.py) consumed by THREE callers; this
# test is the canary that catches a refactor that re-introduces divergence.
#
# It exercises the TWO render code paths against 5 fixture (config, template)
# pairs and asserts byte-equal output:
#
#   Path A — the /update-zskills Step D wrapper path: invoke
#     render-managed-rules.py with NO --sentinel (Step D writes the
#     checked-in, unsentinelled managed.md).
#   Path B — the plugin SessionStart materialiser path: invoke the SAME
#     render-managed-rules.py WITH --sentinel <version>, then strip the
#     leading sentinel line. The body below the sentinel must equal Path A's
#     output byte-for-byte.
#
# Because both paths route through managed_rules_substitution.build_substitutions
# + apply, equivalence is structural; a divergence means someone forked the
# substitution logic.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
[ -n "$PYTHON" ] || { echo "ERROR: install Python 3 (or set ZSKILLS_PYTHON)" >&2; exit 1; }

RENDERER="scripts/render-managed-rules.py"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== managed.md renderer equivalence (Step D path vs materialiser path) ==="

# INSTALL_REDESIGN Phase 4 — the template is DE-PARAMETERIZED (zero
# {{TOKEN}}s; the substitution map is empty and the render a structural
# pass-through). The placeholder-bearing fixture template was a
# subject-removal; what this canary still guards is the TWO render code
# paths (Step D no-sentinel vs materialiser --sentinel) staying byte-equal
# below the sentinel line across configs.
cat > "$TMP/tmpl.md" <<'EOF'
# Project Agent Rules
Resolve `$UNIT_TEST_CMD` / `$FULL_TEST_CMD` from `.claude/zskills-config.json`
via the canonical prelude at point of use.
date: $(TZ=${TIMEZONE:-UTC} date -Iseconds)
Special chars survive: `--ours` vs `--theirs`, 100% pass-through — "quoted".
EOF

# 5 distinct fixture configs.
cat > "$TMP/c1.json" <<'EOF'
{"project_name":"alpha","timezone":"UTC","dev_server":{"default_port":8080,"main_repo_path":"/a","cmd":"npm start"},"testing":{"unit_cmd":"npm test","full_cmd":"npm run test:all","file_patterns":["x.js","y.js"]},"ui":{"auth_bypass":"sessionStorage.k=1"}}
EOF
cat > "$TMP/c2.json" <<'EOF'
{"project_name":"beta","timezone":"America/New_York","dev_server":{"default_port":3000,"main_repo_path":"/b","cmd":""},"testing":{"unit_cmd":"make t","full_cmd":"make ta","file_patterns":[]},"ui":{}}
EOF
cat > "$TMP/c3.json" <<'EOF'
{"project_name":"","timezone":"Europe/London","dev_server":{"default_port":9999,"main_repo_path":"","cmd":"cargo run"},"testing":{"unit_cmd":"cargo test","full_cmd":"cargo test --all","file_patterns":["tests/**/*.rs"]},"ui":{"auth_bypass":""}}
EOF
cat > "$TMP/c4.json" <<'EOF'
{"project_name":"delta with spaces","timezone":"Asia/Tokyo","dev_server":{"default_port":4321,"main_repo_path":"/d/e","cmd":"python manage.py runserver"},"testing":{"unit_cmd":"pytest","full_cmd":"pytest -q","file_patterns":["a","b","c"]},"ui":{"auth_bypass":"document.cookie='x'"}}
EOF
cat > "$TMP/c5.json" <<'EOF'
{"project_name":"epsilon","timezone":"UTC","dev_server":{},"testing":{},"ui":{}}
EOF

for i in 1 2 3 4 5; do
  cfg="$TMP/c$i.json"
  # Path A — Step D wrapper (no sentinel).
  "$PYTHON" "$RENDERER" --config "$cfg" --template "$TMP/tmpl.md" --out "$TMP/a$i.md" 2>/dev/null
  rcA=$?
  # Path B — plugin materialiser (with sentinel), then strip the prefix.
  "$PYTHON" "$RENDERER" --config "$cfg" --template "$TMP/tmpl.md" --out "$TMP/b$i.raw.md" --sentinel "2026.05.0" 2>/dev/null
  rcB=$?
  tail -n +2 "$TMP/b$i.raw.md" > "$TMP/b$i.md"

  if [ "$rcA" -ne 0 ] || [ "$rcB" -ne 0 ]; then
    fail "fixture $i: a render path errored (A=$rcA B=$rcB)"
    continue
  fi
  if diff -q "$TMP/a$i.md" "$TMP/b$i.md" >/dev/null 2>&1; then
    pass "fixture $i: Step D path == materialiser path (byte-equal)"
  else
    fail "fixture $i: render paths DIVERGE"
    diff "$TMP/a$i.md" "$TMP/b$i.md" | head -20 | sed 's/^/      /'
  fi
done

# Fixture 6 — NO-CONFIG mode (INSTALL_REDESIGN Phase 4): Path A and Path B
# with --config omitted (canonical defaults loaded) must also stay
# byte-equal below the sentinel, and equal the config-present renders
# (pass-through render is config-independent).
"$PYTHON" "$RENDERER" --template "$TMP/tmpl.md" --out "$TMP/a6.md" 2>/dev/null
rcA=$?
"$PYTHON" "$RENDERER" --template "$TMP/tmpl.md" --out "$TMP/b6.raw.md" --sentinel "2026.05.0" 2>/dev/null
rcB=$?
tail -n +2 "$TMP/b6.raw.md" > "$TMP/b6.md"
if [ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] \
   && diff -q "$TMP/a6.md" "$TMP/b6.md" >/dev/null 2>&1 \
   && diff -q "$TMP/a6.md" "$TMP/a1.md" >/dev/null 2>&1; then
  pass "fixture 6: no-config Step D path == no-config materialiser path == config-present render"
else
  fail "fixture 6: no-config render paths diverged or errored (A=$rcA B=$rcB)"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
