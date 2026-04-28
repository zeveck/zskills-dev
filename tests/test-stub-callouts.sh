#!/bin/bash
# Tests for skills/update-zskills/scripts/zskills-stub-lib.sh — the
# sourceable consumer stub-callout dispatcher.
#
# Run from repo root: bash tests/test-stub-callouts.sh
#
# 8 cases (per CONSUMER_STUB_CALLOUTS_PLAN.md WI 2.3):
#   1. stub-absent                     -> INVOKED=0, RC=0, STDOUT=""
#   2. stub-present-with-stdout        -> INVOKED=1, RC=0, STDOUT matches
#   3. stub-present-empty-stdout       -> INVOKED=1, RC=0, STDOUT=""
#   4. stub-non-executable             -> INVOKED=0, stderr warning emitted
#   5. stub-exits-nonzero              -> INVOKED=1, RC matches, stderr line emitted
#   6. first-run note                  -> stderr note on first call only
#   7. multi-invocation clean state    -> second call resets ZSKILLS_STUB_*
#   8. literal -- in stub args (DA10)  -> first -- consumed, second forwarded verbatim
#
# Tests source the lib via REPO_ROOT (the source tree under
# skills/update-zskills/scripts/zskills-stub-lib.sh) — not via the
# .claude/skills/ mirror — so the suite passes in fresh
# tests/run-all.sh runs without depending on mirror state.
#
# Each fixture lives in /tmp/<prefix>-fixture-$$ — per CLAUDE.md cleanup
# only rm -rf literal /tmp/* paths.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LIB="$REPO_ROOT/skills/update-zskills/scripts/zskills-stub-lib.sh"
if [ ! -f "$LIB" ]; then
  echo "FATAL: zskills-stub-lib.sh missing at $LIB" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Fixture pattern: /tmp/zskills-stub-callouts-fixture-N-$$ — minimal git
# repo with a scripts/ dir, used as <repo-root> arg to the dispatcher.
make_fixture() {
  local n="$1"
  local fix="/tmp/zskills-stub-callouts-fixture-${n}-$$"
  rm -rf -- "$fix"
  mkdir -p "$fix/scripts"
  git init --quiet -b main "$fix"
  git -C "$fix" config user.email "t@t"
  git -C "$fix" config user.name "t"
  echo "$fix"
}

cleanup_fixture() {
  local fix="$1"
  case "$fix" in
    /tmp/zskills-stub-callouts-fixture-*)
      rm -rf -- "$fix"
      ;;
    *)
      echo "REFUSING to clean non-/tmp path: $fix" >&2
      ;;
  esac
}

# Source the lib once at top — its function persists in this shell.
# (Each case re-invokes the function with a fresh fixture.)
# shellcheck disable=SC1090
. "$LIB"

echo "=== Phase 2 — zskills-stub-lib.sh (8 cases) ==="

# ────────────────────────────────────────────────────────────────────
# Case 1 — stub-absent: INVOKED=0, RC=0, STDOUT=""
# ────────────────────────────────────────────────────────────────────
F1=$(make_fixture 1)
ERR_1=$(mktemp)
zskills_dispatch_stub "missing-stub.sh" "$F1" -- 2>"$ERR_1"
if [ "$ZSKILLS_STUB_INVOKED" = "0" ] \
   && [ "$ZSKILLS_STUB_RC" = "0" ] \
   && [ -z "$ZSKILLS_STUB_STDOUT" ]; then
  pass "1  stub-absent: INVOKED=0 RC=0 STDOUT=''"
else
  fail "1  stub-absent: INVOKED='$ZSKILLS_STUB_INVOKED' RC='$ZSKILLS_STUB_RC' STDOUT='$ZSKILLS_STUB_STDOUT'"
  echo "  --- stderr ---"; cat "$ERR_1"
fi
rm -f -- "$ERR_1"
cleanup_fixture "$F1"

# ────────────────────────────────────────────────────────────────────
# Case 2 — stub-present-with-stdout: INVOKED=1, RC=0, STDOUT matches.
# ────────────────────────────────────────────────────────────────────
F2=$(make_fixture 2)
cat > "$F2/scripts/with-stdout.sh" <<'STUB'
#!/bin/bash
echo "hello-port-1234"
STUB
chmod +x "$F2/scripts/with-stdout.sh"
ERR_2=$(mktemp)
zskills_dispatch_stub "with-stdout.sh" "$F2" -- 2>"$ERR_2"
if [ "$ZSKILLS_STUB_INVOKED" = "1" ] \
   && [ "$ZSKILLS_STUB_RC" = "0" ] \
   && [ "$ZSKILLS_STUB_STDOUT" = "hello-port-1234" ]; then
  pass "2  stub-present-with-stdout: INVOKED=1 RC=0 STDOUT='hello-port-1234'"
else
  fail "2  stub-present-with-stdout: INVOKED='$ZSKILLS_STUB_INVOKED' RC='$ZSKILLS_STUB_RC' STDOUT='$ZSKILLS_STUB_STDOUT'"
  echo "  --- stderr ---"; cat "$ERR_2"
fi
rm -f -- "$ERR_2"
cleanup_fixture "$F2"

# ────────────────────────────────────────────────────────────────────
# Case 3 — stub-present-empty-stdout: INVOKED=1, RC=0, STDOUT="".
# ────────────────────────────────────────────────────────────────────
F3=$(make_fixture 3)
cat > "$F3/scripts/empty-out.sh" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$F3/scripts/empty-out.sh"
ERR_3=$(mktemp)
zskills_dispatch_stub "empty-out.sh" "$F3" -- 2>"$ERR_3"
if [ "$ZSKILLS_STUB_INVOKED" = "1" ] \
   && [ "$ZSKILLS_STUB_RC" = "0" ] \
   && [ -z "$ZSKILLS_STUB_STDOUT" ]; then
  pass "3  stub-present-empty-stdout: INVOKED=1 RC=0 STDOUT=''"
else
  fail "3  stub-present-empty-stdout: INVOKED='$ZSKILLS_STUB_INVOKED' RC='$ZSKILLS_STUB_RC' STDOUT='$ZSKILLS_STUB_STDOUT'"
  echo "  --- stderr ---"; cat "$ERR_3"
fi
rm -f -- "$ERR_3"
cleanup_fixture "$F3"

# ────────────────────────────────────────────────────────────────────
# Case 4 — stub-non-executable: INVOKED=0, stderr warning emitted.
# ────────────────────────────────────────────────────────────────────
F4=$(make_fixture 4)
cat > "$F4/scripts/non-exec.sh" <<'STUB'
#!/bin/bash
echo "should not run"
STUB
chmod -x "$F4/scripts/non-exec.sh"
ERR_4=$(mktemp)
zskills_dispatch_stub "non-exec.sh" "$F4" -- 2>"$ERR_4"
if [ "$ZSKILLS_STUB_INVOKED" = "0" ] \
   && [ "$ZSKILLS_STUB_RC" = "0" ] \
   && [ -z "$ZSKILLS_STUB_STDOUT" ] \
   && grep -qF 'scripts/non-exec.sh present but not executable; ignoring (chmod +x to enable)' "$ERR_4"; then
  pass "4  stub-non-executable: INVOKED=0, stderr warning matches"
else
  fail "4  stub-non-executable: INVOKED='$ZSKILLS_STUB_INVOKED' RC='$ZSKILLS_STUB_RC' STDOUT='$ZSKILLS_STUB_STDOUT'"
  echo "  --- stderr ---"; cat "$ERR_4"
fi
rm -f -- "$ERR_4"
cleanup_fixture "$F4"

# ────────────────────────────────────────────────────────────────────
# Case 5 — stub-exits-nonzero: INVOKED=1, RC matches, stderr line emitted.
# ────────────────────────────────────────────────────────────────────
F5=$(make_fixture 5)
cat > "$F5/scripts/fail-7.sh" <<'STUB'
#!/bin/bash
echo "partial-out"
exit 7
STUB
chmod +x "$F5/scripts/fail-7.sh"
ERR_5=$(mktemp)
zskills_dispatch_stub "fail-7.sh" "$F5" -- 2>"$ERR_5"
if [ "$ZSKILLS_STUB_INVOKED" = "1" ] \
   && [ "$ZSKILLS_STUB_RC" = "7" ] \
   && [ "$ZSKILLS_STUB_STDOUT" = "partial-out" ] \
   && grep -qF 'scripts/fail-7.sh exited 7' "$ERR_5"; then
  pass "5  stub-exits-nonzero: INVOKED=1 RC=7 STDOUT preserved, stderr line emitted"
else
  fail "5  stub-exits-nonzero: INVOKED='$ZSKILLS_STUB_INVOKED' RC='$ZSKILLS_STUB_RC' STDOUT='$ZSKILLS_STUB_STDOUT'"
  echo "  --- stderr ---"; cat "$ERR_5"
fi
rm -f -- "$ERR_5"
cleanup_fixture "$F5"

# ────────────────────────────────────────────────────────────────────
# Case 6 — first-run note: only emitted on first call; marker present
# at .zskills/stub-notes/<stub>.noted after first call.
# ────────────────────────────────────────────────────────────────────
F6=$(make_fixture 6)
cat > "$F6/scripts/note-stub.sh" <<'STUB'
#!/bin/bash
echo "ok"
STUB
chmod +x "$F6/scripts/note-stub.sh"
ERR_6A=$(mktemp)
zskills_dispatch_stub "note-stub.sh" "$F6" -- 2>"$ERR_6A"
ERR_6B=$(mktemp)
zskills_dispatch_stub "note-stub.sh" "$F6" -- 2>"$ERR_6B"

if grep -qF 'invoking consumer stub scripts/note-stub.sh (one-time note' "$ERR_6A" \
   && ! grep -qF 'invoking consumer stub scripts/note-stub.sh (one-time note' "$ERR_6B" \
   && [ -f "$F6/.zskills/stub-notes/note-stub.sh.noted" ]; then
  pass "6  first-run note: emitted once, marker present, suppressed on second call"
else
  fail "6  first-run note: marker-exists=$( [ -f "$F6/.zskills/stub-notes/note-stub.sh.noted" ] && echo yes || echo no )"
  echo "  --- first-call stderr ---"; cat "$ERR_6A"
  echo "  --- second-call stderr ---"; cat "$ERR_6B"
fi
rm -f -- "$ERR_6A" "$ERR_6B"
cleanup_fixture "$F6"

# ────────────────────────────────────────────────────────────────────
# Case 7 — multi-invocation clean state: stub-A returns "hello", then
# stub-B is absent; second call's STDOUT="" and INVOKED=0 (no stale
# state from first call).
# ────────────────────────────────────────────────────────────────────
F7=$(make_fixture 7)
cat > "$F7/scripts/stub-A.sh" <<'STUB'
#!/bin/bash
echo "hello"
STUB
chmod +x "$F7/scripts/stub-A.sh"
ERR_7A=$(mktemp)
zskills_dispatch_stub "stub-A.sh" "$F7" -- 2>"$ERR_7A"
A_INVOKED="$ZSKILLS_STUB_INVOKED"; A_STDOUT="$ZSKILLS_STUB_STDOUT"; A_RC="$ZSKILLS_STUB_RC"

ERR_7B=$(mktemp)
zskills_dispatch_stub "stub-B.sh" "$F7" -- 2>"$ERR_7B"
B_INVOKED="$ZSKILLS_STUB_INVOKED"; B_STDOUT="$ZSKILLS_STUB_STDOUT"; B_RC="$ZSKILLS_STUB_RC"

if [ "$A_INVOKED" = "1" ] && [ "$A_RC" = "0" ] && [ "$A_STDOUT" = "hello" ] \
   && [ "$B_INVOKED" = "0" ] && [ "$B_RC" = "0" ] && [ -z "$B_STDOUT" ]; then
  pass "7  multi-invocation clean state: A=(1,0,hello) B=(0,0,'')"
else
  fail "7  multi-invocation: A=($A_INVOKED,$A_RC,'$A_STDOUT') B=($B_INVOKED,$B_RC,'$B_STDOUT')"
  echo "  --- stub-A stderr ---"; cat "$ERR_7A"
  echo "  --- stub-B stderr ---"; cat "$ERR_7B"
fi
rm -f -- "$ERR_7A" "$ERR_7B"
cleanup_fixture "$F7"

# ────────────────────────────────────────────────────────────────────
# Case 8 — Literal -- in stub args (DA10): call dispatcher with
# `... -- foo -- bar`; verify the stub's $@ is (foo, --, bar)
# (the dispatcher consumes only the FIRST --, the second is forwarded
# verbatim).
# ────────────────────────────────────────────────────────────────────
F8=$(make_fixture 8)
cat > "$F8/scripts/echo-args.sh" <<'STUB'
#!/bin/bash
# Print each positional arg on its own line; surround with markers so
# blank/edge-case args are still distinguishable.
echo "ARGC=$#"
for a in "$@"; do
  echo "ARG=[$a]"
done
STUB
chmod +x "$F8/scripts/echo-args.sh"
ERR_8=$(mktemp)
zskills_dispatch_stub "echo-args.sh" "$F8" -- foo -- bar 2>"$ERR_8"
EXPECTED_8=$'ARGC=3\nARG=[foo]\nARG=[--]\nARG=[bar]'
if [ "$ZSKILLS_STUB_INVOKED" = "1" ] \
   && [ "$ZSKILLS_STUB_RC" = "0" ] \
   && [ "$ZSKILLS_STUB_STDOUT" = "$EXPECTED_8" ]; then
  pass "8  literal -- in stub args (DA10): dispatcher consumes first --, forwards second verbatim"
else
  fail "8  literal -- in stub args: STDOUT='$ZSKILLS_STUB_STDOUT' (expected '$EXPECTED_8')"
  echo "  --- stderr ---"; cat "$ERR_8"
fi
rm -f -- "$ERR_8"
cleanup_fixture "$F8"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
