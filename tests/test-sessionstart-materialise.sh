#!/usr/bin/env bash
# tests/test-sessionstart-materialise.sh
#
# Phase 2 (W2.1, D11, D20, A3) — the SessionStart materialiser writes the
# five consumer-side artifacts into a fresh fixture project's .claude/.
#
# Assertions (>= 9):
#   1-5. All five destinations are written.
#   6.   Materialised *.sh hooks are executable.
#   7.   managed.md carries the rendered substitution tokens (project name).
#   8.   Each artifact carries a kind-appropriate materialiser sentinel
#        (frontmatter YAML-comment / shell-comment line 2 / HTML-comment).
#   9.   mtime is STABLE on a no-change re-run (idempotency).
#   10.  Cross-version upgrade rewrites the artifact (mtime advances) when
#        the plugin version changes.
#   11.  Frontmatter survives — verifier.md still parses as `---`-delimited
#        with its `name:` field intact below the injected sentinel.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MAT="hooks/session-start-materialise.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Build a FRESH fixture project: a .claude/zskills-config.json + a root
# CLAUDE_TEMPLATE.md (so the materialiser renders managed.md from the live
# template). Fresh = no pre-existing .claude artifacts (lane=fresh).
PROJ="$TMP/proj"
mkdir -p "$PROJ/.claude"
cp "$REPO_ROOT/.claude/zskills-config.json" "$PROJ/.claude/"
cp "$REPO_ROOT/CLAUDE_TEMPLATE.md" "$PROJ/"

PROJECT_NAME="$(python3 -c 'import json;print(json.load(open("'"$PROJ"'/.claude/zskills-config.json")).get("project_name",""))')"

run_mat() {
  env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/$MAT"
}

echo "=== SessionStart materialiser (fresh fixture) ==="

run_mat

V="$PROJ/.claude/agents/verifier.md"
I="$PROJ/.claude/agents/implementer.md"
H1="$PROJ/.claude/hooks/inject-bash-timeout.sh"
H2="$PROJ/.claude/hooks/verify-response-validate.sh"
M="$PROJ/.claude/rules/zskills/managed.md"

# 1-5. Destinations written.
[ -f "$V" ]  && pass "1. verifier.md written"               || fail "1. verifier.md missing"
[ -f "$I" ]  && pass "2. implementer.md written"            || fail "2. implementer.md missing"
[ -f "$H1" ] && pass "3. inject-bash-timeout.sh written"    || fail "3. inject-bash-timeout.sh missing"
[ -f "$H2" ] && pass "4. verify-response-validate.sh written" || fail "4. verify-response-validate.sh missing"
[ -f "$M" ]  && pass "5. managed.md written"                || fail "5. managed.md missing"

# 6. Hooks executable.
if [ -x "$H1" ] && [ -x "$H2" ]; then
  pass "6. materialised hooks are executable"
else
  fail "6. materialised hooks not executable"
fi

# 7. Substitution token present in managed.md.
if [ -n "$PROJECT_NAME" ] && grep -qF "$PROJECT_NAME" "$M" 2>/dev/null; then
  pass "7. managed.md contains the substituted project name ($PROJECT_NAME)"
elif [ -z "$PROJECT_NAME" ]; then
  # Empty project name in config — assert no unrendered placeholder remains.
  if ! grep -q '{{' "$M" 2>/dev/null; then
    pass "7. managed.md has no unrendered {{...}} placeholders"
  else
    fail "7. managed.md has unrendered placeholders"
  fi
else
  fail "7. managed.md missing the substituted project name"
fi

# 8. Sentinels — kind-appropriate.
if head -n 3 "$V" | grep -Eq '^# zskills-materialised:' \
   && head -n 1 "$V" | grep -q '^---$'; then
  pass "8a. verifier.md sentinel is a YAML-comment inside frontmatter"
else
  fail "8a. verifier.md frontmatter sentinel malformed"
  head -3 "$V" | sed 's/^/      /'
fi
if head -n 2 "$H1" | grep -Eq '^# zskills-materialised:' \
   && head -n 1 "$H1" | grep -q '^#!'; then
  pass "8b. inject-bash-timeout.sh sentinel is a shell-comment on line 2"
else
  fail "8b. hook shell-comment sentinel malformed"
  head -2 "$H1" | sed 's/^/      /'
fi
if head -n 1 "$M" | grep -Eq '^<!-- zskills-materialised: .* -->$'; then
  pass "8c. managed.md sentinel is an HTML-comment on line 1"
else
  fail "8c. managed.md HTML-comment sentinel malformed"
  head -1 "$M" | sed 's/^/      /'
fi

# 9. Idempotency — mtime stable on no-change re-run.
m_before="$(stat -c %Y "$V")"
sleep 1
run_mat
m_after="$(stat -c %Y "$V")"
if [ "$m_before" = "$m_after" ]; then
  pass "9. mtime stable on no-change re-run (idempotent)"
else
  fail "9. mtime advanced on no-change re-run (before=$m_before after=$m_after)"
fi

# 10. Cross-version upgrade — bump the plugin version stamp inside the
#     destination's sentinel so content stays equal-modulo-version (no
#     rewrite expected, mtime stable), THEN change actual body to force a
#     rewrite. Simulate an upgrade by corrupting the sentinelled copy's body
#     but keeping the sentinel; a re-run must restore canonical content.
#     We assert the materialiser overwrites a sentinelled-but-stale file.
{
  # Replace body below the frontmatter sentinel with garbage, keep sentinel.
  printf '%s\n' '---' '# zskills-materialised: 0.0.0' 'GARBAGE BODY' > "$V"
}
sleep 1
run_mat
if grep -q '^name: verifier' "$V" && ! grep -q 'GARBAGE BODY' "$V"; then
  pass "10. cross-version/stale sentinelled artifact is overwritten with canonical content"
else
  fail "10. stale sentinelled artifact was NOT refreshed"
  head -5 "$V" | sed 's/^/      /'
fi

# 11. Frontmatter survival — verifier.md is still a valid `---` block with
#     name: verifier reachable.
if [ "$(head -n 1 "$V")" = "---" ] && grep -q '^name: verifier' "$V"; then
  pass "11. verifier.md frontmatter survives sentinel injection"
else
  fail "11. verifier.md frontmatter broken"
fi

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
exit "$FAIL_COUNT"
