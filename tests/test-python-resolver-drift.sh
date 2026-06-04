#!/bin/bash
# tests/test-python-resolver-drift.sh — assert the $PYTHON resolver inlined into
# the canonical config prelude (skills/update-zskills/scripts/
# zskills-resolve-config.sh) stays in sync with the source-of-truth probe in
# hooks/_lib/resolve-python.sh (zskills_resolve_python). Issue #1083.
#
# The prelude inlines the probe as a loop (it sets $PYTHON, not a function),
# so byte-equality of the whole body is not the right gate. Instead we assert
# the two LOAD-BEARING invariants of the probe are present, identically, in
# BOTH files:
#   1. the candidate walk:    "${ZSKILLS_PYTHON:-}" python3 python
#   2. the version-3 check:   import sys; sys.exit(0 if sys.version_info[0]==3 else 1)
# If either file drifts (e.g. someone reorders the candidates in one place or
# loosens the version check), this fails closed.
#
# Both files MUST also export/use $PYTHON via `command -v` on the winning
# candidate (so callers get an absolute path, not a bare name).
# pass/fail inline (mirrors tests/test-resolve-python.sh:23-24).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/hooks/_lib/resolve-python.sh"
PRELUDE="$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# The exact substrings both files must contain. These are the probe's identity.
WALK='"${ZSKILLS_PYTHON:-}" python3 python'
VERCHECK='import sys; sys.exit(0 if sys.version_info[0]==3 else 1)'

for F in "$SRC" "$PRELUDE"; do
  NAME="$(basename "$F")"
  if [ ! -f "$F" ]; then
    fail "$NAME — file not found at $F"
    continue
  fi
  if grep -qF "$WALK" "$F"; then
    pass "$NAME — candidate walk (ZSKILLS_PYTHON → python3 → python) present"
  else
    fail "$NAME — candidate walk drifted; expected substring: $WALK"
  fi
  if grep -qF "$VERCHECK" "$F"; then
    pass "$NAME — python3 version probe present"
  else
    fail "$NAME — version probe drifted; expected substring: $VERCHECK"
  fi
done

# The prelude must export PYTHON (so sourcing fences pick it up) and resolve the
# winning candidate through `command -v` (absolute path, not bare name).
if grep -qE 'export[[:space:]]+PYTHON' "$PRELUDE"; then
  pass "prelude — exports PYTHON"
else
  fail "prelude — must 'export PYTHON' so sourcing fences inherit it"
fi
if grep -qF 'PYTHON="$(command -v "$_ZSK_PYCAND")"' "$PRELUDE"; then
  pass "prelude — resolves winning candidate via command -v (absolute path)"
else
  fail "prelude — winning candidate must resolve through command -v"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
