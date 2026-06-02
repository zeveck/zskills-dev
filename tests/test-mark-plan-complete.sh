#!/usr/bin/env bash
# tests/test-mark-plan-complete.sh
# Asserts mark-plan-complete.sh writes BOTH status:complete AND completed:<ts>
# in the same invocation (#957).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PASS=0; FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PLAN="$TMP/plan.md"
cat > "$PLAN" <<'EOF'
---
title: Test plan
status: active
---

# Body
EOF

bash scripts/mark-plan-complete.sh "$PLAN" 2>/dev/null
grep -qE '^status: "?complete"?$' "$PLAN" && pass "status field is complete" || fail "status field NOT complete"
grep -qE '^completed: "?[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"?$' "$PLAN" \
  && pass "completed field is ISO-8601 UTC datetime" || fail "completed field MISSING or wrong format"

# Idempotency: re-run should not error and should refresh completed.
sleep 1
PRE="$(grep '^completed:' "$PLAN")"
bash scripts/mark-plan-complete.sh "$PLAN" 2>/dev/null
POST="$(grep '^completed:' "$PLAN")"
[ "$PRE" != "$POST" ] && pass "re-run refreshes completed timestamp" || fail "re-run did NOT refresh completed timestamp"

# Missing file → exit 2
bash scripts/mark-plan-complete.sh "$TMP/missing.md" 2>/dev/null
[ "$?" -eq 2 ] && pass "missing file → exit 2" || fail "missing file did NOT exit 2"

# Missing arg → exit 2
bash scripts/mark-plan-complete.sh 2>/dev/null
[ "$?" -eq 2 ] && pass "missing arg → exit 2" || fail "missing arg did NOT exit 2"

printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
exit "$FAIL"
