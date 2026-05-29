#!/usr/bin/env bash
# tests/test-render-managed-rules-correctness.sh
#
# Phase 2 (W2.2, A4) — golden-output correctness gate for
# scripts/render-managed-rules.py + scripts/managed_rules_substitution.py.
#
# Builds a small fixture template carrying every one of the 10 placeholders
# plus a fixture config, renders via the CLI wrapper, and asserts the output
# matches a hand-computed golden string. Also exercises: empty-field TODO
# fallbacks, the file_patterns markdown list, the unsubstituted-placeholder
# guard (exit 2), and the --sentinel prefix injection.

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

echo "=== render-managed-rules correctness ==="

# ── Fixture 1: full config, all placeholders resolve to real values ───────
cat > "$TMP/tmpl.md" <<'EOF'
project={{PROJECT_NAME}} tz={{TIMEZONE}} port={{DEFAULT_PORT}}
main={{MAIN_REPO_PATH}} unit={{UNIT_TEST_CMD}} full={{FULL_TEST_CMD}}
dev={{DEV_SERVER_CMD}} auth={{AUTH_BYPASS}}
patterns:
{{TEST_FILE_PATTERNS}}
layout={{SOURCE_LAYOUT}}
EOF

cat > "$TMP/cfg.json" <<'EOF'
{
  "project_name": "demo",
  "timezone": "UTC",
  "dev_server": { "default_port": 8080, "main_repo_path": "/srv/demo", "cmd": "make serve" },
  "testing": { "unit_cmd": "make test", "full_cmd": "make test-all", "file_patterns": ["a.sh", "b.sh"] },
  "ui": { "auth_bypass": "localStorage.x=1" }
}
EOF

"$PYTHON" "$RENDERER" --config "$TMP/cfg.json" --template "$TMP/tmpl.md" --out "$TMP/out.md"
rc=$?

EXPECTED="project=demo tz=UTC port=8080
main=/srv/demo unit=make test full=make test-all
dev=make serve auth=localStorage.x=1
patterns:
- \`a.sh\`
- \`b.sh\`
layout=<!-- TODO: SOURCE_LAYOUT has no config field; fill in project's architecture summary -->"

if [ "$rc" -eq 0 ] && [ "$(cat "$TMP/out.md")" = "$EXPECTED" ]; then
  pass "1. full config renders to the golden string"
else
  fail "1. full config render mismatch (rc=$rc)"
  diff <(printf '%s' "$EXPECTED") "$TMP/out.md" | head -20 | sed 's/^/      /'
fi

# ── Fixture 2: empty dev_server.cmd + ui.auth_bypass → TODO fallbacks ─────
cat > "$TMP/cfg2.json" <<'EOF'
{
  "project_name": "x",
  "timezone": "UTC",
  "dev_server": { "default_port": 1, "main_repo_path": "/x", "cmd": "" },
  "testing": { "unit_cmd": "u", "full_cmd": "f", "file_patterns": [] },
  "ui": {}
}
EOF
"$PYTHON" "$RENDERER" --config "$TMP/cfg2.json" --template "$TMP/tmpl.md" --out "$TMP/out2.md" 2>/dev/null
if grep -q 'dev=<!-- TODO: dev_server.cmd not set' "$TMP/out2.md" \
   && grep -q 'auth=<!-- TODO: ui.auth_bypass not set' "$TMP/out2.md" \
   && grep -q '<!-- TODO: testing.file_patterns is empty -->' "$TMP/out2.md"; then
  pass "2. empty fields render the documented TODO fallbacks"
else
  fail "2. empty-field TODO fallbacks missing"
  sed 's/^/      /' "$TMP/out2.md"
fi

# ── Fixture 3: unsubstituted placeholder guard → exit 2 ───────────────────
printf 'unknown={{NOT_A_REAL_PLACEHOLDER}}\n' > "$TMP/bad.md"
"$PYTHON" "$RENDERER" --config "$TMP/cfg.json" --template "$TMP/bad.md" --out "$TMP/badout.md" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "3. leftover placeholder triggers exit 2 (no broken {{...}} shipped)"
else
  fail "3. leftover placeholder did NOT trigger exit 2 (rc=$rc)"
fi

# ── Fixture 4: --sentinel prepends the D20(a) prefix line ─────────────────
"$PYTHON" "$RENDERER" --config "$TMP/cfg.json" --template "$TMP/tmpl.md" --out "$TMP/sent.md" --sentinel "2026.05.0"
if head -n 1 "$TMP/sent.md" | grep -Eq '^<!-- zskills-materialised: 2026.05.0 -->$'; then
  pass "4. --sentinel injects the HTML-comment materialiser prefix"
else
  fail "4. --sentinel prefix missing or malformed"
  head -1 "$TMP/sent.md" | sed 's/^/      /'
fi

# 5. With --sentinel the body below the prefix matches the no-sentinel render.
if [ "$(tail -n +2 "$TMP/sent.md")" = "$(cat "$TMP/out.md")" ]; then
  pass "5. sentinelled body equals the un-sentinelled render"
else
  fail "5. sentinelled body diverges from un-sentinelled render"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
