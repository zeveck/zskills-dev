#!/bin/bash
# tests/test-hooks-helpers.sh — harness extension shared between
# tests/test-hooks.sh project-hook section (Phase 3.4) and matrix loops
# (Phase 5.2). Source from those files via:
#   source "$(dirname "$0")/test-hooks-helpers.sh"
#
# When invoked directly, runs an end-to-end self-test (AC13) that calls
# `setup_project_test_on_main` and asserts:
#   (a) git -C "$TEST_TMPDIR" branch --show-current == main
#   (b) grep -F '"main_protected": true' "$TEST_TMPDIR/.claude/zskills-config.json"
#
# DEPENDENCIES: when sourced from test-hooks.sh, the real
# `setup_project_test` (defined in test-hooks.sh) is in scope and is
# used. When run standalone, a minimal local stub provides the same
# initial state so the self-test is hermetic.

# Inline stub fallback: defined ONLY if the real setup_project_test
# is not already in scope (e.g., when this file runs standalone).
if [ -z "$(type -t setup_project_test 2>/dev/null)" ]; then
  setup_project_test() {
    TEST_TMPDIR=$(mktemp -d)
    mkdir -p "$TEST_TMPDIR/.claude/hooks"
    mkdir -p "$TEST_TMPDIR/.zskills/tracking"
    cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{
  "testing": {
    "unit_cmd": "npm test",
    "full_cmd": "npm run test:all"
  },
  "ui": {
    "file_patterns": "src/ui/"
  }
}
EOF
    printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$TEST_TMPDIR/package.json"
    printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\nnpm run test:all\n' > "$TEST_TMPDIR/.transcript"
    (cd "$TEST_TMPDIR" && git init -q && git add -A && git commit -q -m "init")
  }
fi

# setup_project_test_on_main — extends setup_project_test by checking out
# `main` and writing main_protected: true into the runtime config. The
# existing run_main_protected_test pattern (tests/test-hooks.sh:950-1023)
# demonstrates the same shape; this helper shares the harness across the
# PR1-PR11 (Phase 3.4) and matrix (Phase 5.2) test surfaces.
setup_project_test_on_main() {
  setup_project_test
  # Switch to main (setup_project_test calls `git init`; default branch
  # may be master or main depending on init.defaultBranch). Force-rename.
  (cd "$TEST_TMPDIR" && \
   CB=$(git branch --show-current) && \
   [[ "$CB" != "main" ]] && git branch -m "$CB" main; \
   true)
  # Patch the config to enable main_protected. Reuses the same JSON file
  # setup_project_test already wrote.
  CFG="$TEST_TMPDIR/.claude/zskills-config.json"
  python3 -c "
import json
with open('$CFG') as f: c = json.load(f)
c.setdefault('execution', {})['main_protected'] = True
with open('$CFG', 'w') as f: json.dump(c, f)
"
}

# ─── Self-test (only when invoked directly) ───
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "=== test-hooks-helpers.sh self-test ==="

  PASS_COUNT=0
  FAIL_COUNT=0

  pass() {
    echo "PASS — $*"
    PASS_COUNT=$((PASS_COUNT + 1))
  }
  fail() {
    echo "FAIL — $*"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  }

  # Run setup_project_test_on_main and verify both AC13 assertions.
  setup_project_test_on_main

  # Assertion (a): branch is main
  ACTUAL_BRANCH=$(git -C "$TEST_TMPDIR" branch --show-current)
  if [ "$ACTUAL_BRANCH" = "main" ]; then
    pass "branch --show-current returns 'main' after setup_project_test_on_main"
  else
    fail "expected branch=main, got '$ACTUAL_BRANCH'"
  fi

  # Assertion (b): config contains "main_protected": true
  if grep -F '"main_protected": true' "$TEST_TMPDIR/.claude/zskills-config.json" >/dev/null; then
    pass "zskills-config.json contains \"main_protected\": true"
  else
    fail "zskills-config.json missing \"main_protected\": true"
    cat "$TEST_TMPDIR/.claude/zskills-config.json"
  fi

  # Cleanup
  rm -rf "$TEST_TMPDIR"

  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
  exit 0
fi
