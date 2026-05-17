#!/bin/bash
# test-fix-issues-dashboard.sh — behavioral coverage for the /fix-issues
# Phase 2 dashboard branch (PR #313, commit 233db9e).
#
# Issue #334: the existing test-fix-issues.sh suite covers the dashboard
# token with three sentinel-grep cases against SKILL.md prose only. None
# execute the dashboard branch's behavior. A future edit that breaks
# intersection, swallows the empty-state message, or drops a mutex case
# would pass the existing suite. This file adds behavioral tests:
#
#   1. Empty-Ready exit-0 unification (4 sub-cases):
#       (a) monitor-state.json missing
#       (b) issues.ready key absent
#       (c) issues.ready empty array
#       (d) intersection-with-open empty
#      All four must produce the unified "Dashboard Ready is empty"
#      message AND exit 0 (NOT exit nonzero, NOT fall through).
#
#   2. Open-issue intersection — picks ONLY entries that appear in both
#      issues.ready AND the open-issue list (OPEN_NUMS).
#
#   3. N-cap — when intersection exceeds N, the cap is honored and
#      drag-order is preserved.
#
#   4. Permissive entry shapes — issues.ready may contain ints, dicts
#      with `.number`, or stringified ints; non-numeric entries are
#      skipped without crashing.
#
#   5. Mutex error-exit-2 matrix — each of focus/sync/plan/stop/next
#      against `dashboard` exits with code 2 + emits the verbatim
#      diagnostic to stderr.
#
# Strategy: extract the actual Python intersection block AND the Phase 0
# detection + mutex bash blocks FROM SKILL.md at test time, run them
# against fixtures. Extraction-from-source keeps the test in sync with
# the real code path — a behavioral test against a duplicated copy
# would drift.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/fix-issues/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Sandbox for fixtures and extracted scripts.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# --- Extract the Python intersection block from SKILL.md ----------------
# The block lives between `N="$N" python3 -c '` and the matching
# closing `' "$MONITOR_STATE")`. We extract the inner Python source so
# we can invoke it directly with controlled env + fixture path.

PYSCRIPT="$TMP_ROOT/dashboard_picks.py"
awk '
  /N="\$N" python3 -c /{ in_block=1; next }
  in_block && /^'\'' "\$MONITOR_STATE"\)$/ { in_block=0; exit }
  in_block { print }
' "$SKILL" > "$PYSCRIPT"

if [ ! -s "$PYSCRIPT" ]; then
  fail "extract dashboard Python block from SKILL.md" "extraction produced empty file"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit 1
else
  pass "extract dashboard Python block from SKILL.md ($(wc -l < "$PYSCRIPT") lines)"
fi

# Helper — run the extracted Python with controlled env + state-file path.
# Echoes stdout (the picks line) and returns the script's exit code.
run_picks() {
  local state_path="$1" open_joined="$2" n="$3"
  OPEN_NUMS_JOINED="$open_joined" N="$n" python3 "$PYSCRIPT" "$state_path"
}

# --- 1a. monitor-state.json missing -------------------------------------
# Note: the missing-file case is handled by the BASH wrapper around the
# Python block (`if [ ! -f "$MONITOR_STATE" ]`) — Python is never invoked.
# When Python IS invoked with a missing path, json.load raises and the
# `except OSError` branch hits sys.exit(0). Same observable behavior:
# exit 0, empty stdout. We assert the Python branch directly here
# because that's what the test extracts; the bash guard is asserted via
# a source-grep below.

test_empty_missing_state_file() {
  local got rc
  got=$(run_picks "$TMP_ROOT/does-not-exist.json" "100,200,300" "5"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    pass "empty: missing monitor-state.json -> exit 0, empty stdout"
  else
    fail "empty: missing monitor-state.json -> exit 0, empty stdout" "rc=$rc stdout=[$got]"
  fi
}

# Also assert the bash guard is wired (defense in depth for the missing
# file case, which short-circuits before invoking Python).
test_bash_guard_missing_file_exits_zero() {
  # The guard's block grew from 2 lines (echo + exit) to 3 lines
  # (echo + ship_sync_only_or_cleanup call + exit) when the dashboard-empty
  # ship-or-cleanup routing landed. Widen the context window to -A3.
  if grep -qE 'if \[ ! -f "\$MONITOR_STATE" \]; then' "$SKILL" \
     && grep -A3 'if \[ ! -f "\$MONITOR_STATE" \]; then' "$SKILL" | grep -qF 'exit 0'; then
    pass "bash guard: missing state file -> echo + exit 0"
  else
    fail "bash guard: missing state file -> echo + exit 0" "guard or 'exit 0' not found near missing-file check"
  fi
}

# --- 1b. issues.ready key absent ----------------------------------------

test_empty_missing_ready_key() {
  local sf="$TMP_ROOT/no-ready.json"
  printf '%s' '{"issues":{"other":"unrelated"}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "100,200" "5"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    pass "empty: issues.ready key absent -> exit 0, empty stdout"
  else
    fail "empty: issues.ready key absent -> exit 0, empty stdout" "rc=$rc stdout=[$got]"
  fi
}

test_empty_top_level_issues_absent() {
  local sf="$TMP_ROOT/no-issues.json"
  printf '%s' '{"other":42}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "100,200" "5"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    pass "empty: top-level issues key absent -> exit 0, empty stdout"
  else
    fail "empty: top-level issues key absent -> exit 0, empty stdout" "rc=$rc stdout=[$got]"
  fi
}

# --- 1c. issues.ready empty array ---------------------------------------

test_empty_ready_array() {
  local sf="$TMP_ROOT/empty-ready.json"
  printf '%s' '{"issues":{"ready":[]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "100,200,300" "5"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    pass "empty: issues.ready empty array -> exit 0, empty stdout"
  else
    fail "empty: issues.ready empty array -> exit 0, empty stdout" "rc=$rc stdout=[$got]"
  fi
}

# --- 1d. intersection-with-open empty -----------------------------------

test_empty_intersection_no_overlap() {
  local sf="$TMP_ROOT/no-overlap.json"
  # ready has issues that aren't in the open list
  printf '%s' '{"issues":{"ready":[111,222,333]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "400,500" "5"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    pass "empty: intersection-with-open empty -> exit 0, empty stdout"
  else
    fail "empty: intersection-with-open empty -> exit 0, empty stdout" "rc=$rc stdout=[$got]"
  fi
}

# --- 1e. unified bash echo on empty intersection ------------------------
# The bash wrapper after the Python invocation echoes the unified
# "Dashboard Ready is empty — nothing to do" message on $DASHBOARD_PICKS
# being empty, then exits 0. We grep both the missing-file site AND the
# empty-picks site to confirm BOTH emit the verbatim string.

test_unified_empty_message_at_both_sites() {
  local hits
  hits=$(grep -cF 'Dashboard Ready is empty — nothing to do' "$SKILL")
  if [ "$hits" -ge 2 ]; then
    pass "unified empty message: present at >=2 sites ($hits) — missing-file + empty-picks"
  else
    fail "unified empty message: present at >=2 sites" "only $hits occurrence(s); the unification is broken"
  fi
}

# --- 2. Open-issue intersection -----------------------------------------

test_intersection_mixed_with_closed() {
  local sf="$TMP_ROOT/mixed.json"
  # Ready has 5 entries; only 100,300,500 are still open.
  printf '%s' '{"issues":{"ready":[100,200,300,400,500]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "100,300,500,999" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "100 300 500" ]; then
    pass "intersection: mixed open/closed -> only open in drag order ($got)"
  else
    fail "intersection: mixed open/closed -> only open in drag order" "rc=$rc stdout=[$got] expected '100 300 500'"
  fi
}

test_intersection_preserves_drag_order() {
  local sf="$TMP_ROOT/order.json"
  # Drag order: 500,100,300. All open. Output must follow drag order,
  # NOT OPEN_NUMS_JOINED order (which lists them differently).
  printf '%s' '{"issues":{"ready":[500,100,300]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "100,300,500" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "500 100 300" ]; then
    pass "intersection: drag order preserved (not OPEN_NUMS order)"
  else
    fail "intersection: drag order preserved" "rc=$rc stdout=[$got] expected '500 100 300'"
  fi
}

# --- 3. N-cap -----------------------------------------------------------

test_n_cap_honored() {
  local sf="$TMP_ROOT/cap.json"
  printf '%s' '{"issues":{"ready":[10,20,30,40,50,60,70]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20,30,40,50,60,70" "3"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "10 20 30" ]; then
    pass "N-cap: 3 of 7 ready+open -> first 3 in drag order"
  else
    fail "N-cap: 3 of 7 ready+open -> first 3 in drag order" "rc=$rc stdout=[$got] expected '10 20 30'"
  fi
}

test_n_cap_one() {
  local sf="$TMP_ROOT/cap1.json"
  printf '%s' '{"issues":{"ready":[10,20,30]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20,30" "1"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "10" ]; then
    pass "N-cap: N=1 picks only first open entry in drag order"
  else
    fail "N-cap: N=1 picks only first open entry in drag order" "rc=$rc stdout=[$got] expected '10'"
  fi
}

test_n_cap_unset_takes_all() {
  local sf="$TMP_ROOT/cap-all.json"
  printf '%s' '{"issues":{"ready":[10,20,30]}}' > "$sf"
  # N="" -> Python's `int(N or "0") or len(ready)` falls back to len(ready)
  local got rc
  got=$(run_picks "$sf" "10,20,30,40" ""); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "10 20 30" ]; then
    pass "N-cap: empty N falls back to len(ready)"
  else
    fail "N-cap: empty N falls back to len(ready)" "rc=$rc stdout=[$got] expected '10 20 30'"
  fi
}

# --- 4. Permissive entry shapes -----------------------------------------

test_dict_entries_with_number() {
  local sf="$TMP_ROOT/dicts.json"
  printf '%s' '{"issues":{"ready":[{"number":10,"title":"x"},{"number":20}]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "10 20" ]; then
    pass "permissive: dict entries with .number resolved"
  else
    fail "permissive: dict entries with .number resolved" "rc=$rc stdout=[$got] expected '10 20'"
  fi
}

test_mixed_int_and_dict_entries() {
  local sf="$TMP_ROOT/mixed-shapes.json"
  printf '%s' '{"issues":{"ready":[10,{"number":20},30]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20,30" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "10 20 30" ]; then
    pass "permissive: mixed int + dict entries resolved in order"
  else
    fail "permissive: mixed int + dict entries resolved in order" "rc=$rc stdout=[$got] expected '10 20 30'"
  fi
}

test_string_int_entries() {
  local sf="$TMP_ROOT/strings.json"
  printf '%s' '{"issues":{"ready":["10","20","30"]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20,30" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "10 20 30" ]; then
    pass "permissive: stringified-int entries coerced to int"
  else
    fail "permissive: stringified-int entries coerced to int" "rc=$rc stdout=[$got] expected '10 20 30'"
  fi
}

test_non_numeric_entries_skipped() {
  local sf="$TMP_ROOT/junk.json"
  # Garbage entries (None, lists, non-numeric strings, dicts without .number)
  # should be silently skipped — not crash.
  printf '%s' '{"issues":{"ready":[10,null,"foo",[1,2],{"no_number":1},20]}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "10 20" ]; then
    pass "permissive: non-numeric / malformed entries skipped (no crash)"
  else
    fail "permissive: non-numeric / malformed entries skipped (no crash)" "rc=$rc stdout=[$got] expected '10 20'"
  fi
}

test_ready_is_not_a_list_exits_zero() {
  local sf="$TMP_ROOT/ready-wrong-type.json"
  # ready as a dict (wrong type) — `not isinstance(ready, list)` -> exit 0.
  printf '%s' '{"issues":{"ready":{"a":1}}}' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    pass "permissive: issues.ready wrong type (dict not list) -> exit 0, empty"
  else
    fail "permissive: issues.ready wrong type (dict not list) -> exit 0, empty" "rc=$rc stdout=[$got]"
  fi
}

test_malformed_json_exits_zero() {
  local sf="$TMP_ROOT/malformed.json"
  printf '%s' '{this is not json' > "$sf"
  local got rc
  got=$(run_picks "$sf" "10,20" "10"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$got" ]; then
    pass "robust: malformed JSON -> exit 0, empty stdout (no crash)"
  else
    fail "robust: malformed JSON -> exit 0, empty stdout (no crash)" "rc=$rc stdout=[$got]"
  fi
}

# --- 5. Mutex error-exit-2 matrix ---------------------------------------
# Build a tiny harness that sources the Phase 0 mutex bash block from
# SKILL.md and runs it with controlled $ARGUMENTS + DASHBOARD_MODE=1.
# Each conflicting flag must exit 2 with the verbatim diagnostic on
# stderr.
#
# Extraction: the mutex block is the bash fenced block starting with
# `if [ "$DASHBOARD_MODE" = "1" ]; then` and ending with the matching
# `fi` closing the outer-if (followed by ``` close). We pull the lines
# between the open fence containing that signature and the next ``` .

MUTEX_BLOCK="$TMP_ROOT/mutex_block.sh"
awk '
  /^```bash$/ { in_fence=1; buf=""; next }
  in_fence && /^```$/ {
    if (buf ~ /if \[ "\$DASHBOARD_MODE" = "1" \]; then/ \
        && buf ~ /dashboard is incompatible with focus mode/) {
      print buf
      exit
    }
    in_fence=0; buf=""
    next
  }
  in_fence { buf = buf $0 "\n" }
' "$SKILL" > "$MUTEX_BLOCK"

if [ ! -s "$MUTEX_BLOCK" ]; then
  fail "extract mutex bash block from SKILL.md" "extraction produced empty file"
else
  pass "extract mutex bash block from SKILL.md ($(wc -l < "$MUTEX_BLOCK") lines)"
fi

# Run the mutex block in a subshell with controlled inputs.
# Returns rc; stderr captured to $TMP_ROOT/mutex.err.
run_mutex() {
  local arguments="$1"
  ( DASHBOARD_MODE=1
    ARGUMENTS="$arguments"
    # shellcheck disable=SC1090
    source "$MUTEX_BLOCK"
  ) 2>"$TMP_ROOT/mutex.err"
}

test_mutex_focus() {
  run_mutex "5 dashboard focus correctness"; local rc=$?
  local err; err=$(cat "$TMP_ROOT/mutex.err")
  if [ "$rc" -eq 2 ] && [[ "$err" == *"ERROR: dashboard is incompatible with focus mode"* ]]; then
    pass "mutex: dashboard + focus -> exit 2 + verbatim diagnostic"
  else
    fail "mutex: dashboard + focus -> exit 2 + verbatim diagnostic" "rc=$rc stderr=[$err]"
  fi
}

test_mutex_sync() {
  run_mutex "dashboard sync"; local rc=$?
  local err; err=$(cat "$TMP_ROOT/mutex.err")
  if [ "$rc" -eq 2 ] && [[ "$err" == *"ERROR: dashboard is incompatible with sync mode"* ]]; then
    pass "mutex: dashboard + sync -> exit 2 + verbatim diagnostic"
  else
    fail "mutex: dashboard + sync -> exit 2 + verbatim diagnostic" "rc=$rc stderr=[$err]"
  fi
}

test_mutex_plan() {
  run_mutex "dashboard plan"; local rc=$?
  local err; err=$(cat "$TMP_ROOT/mutex.err")
  if [ "$rc" -eq 2 ] && [[ "$err" == *"ERROR: dashboard is incompatible with plan mode"* ]]; then
    pass "mutex: dashboard + plan -> exit 2 + verbatim diagnostic"
  else
    fail "mutex: dashboard + plan -> exit 2 + verbatim diagnostic" "rc=$rc stderr=[$err]"
  fi
}

test_mutex_stop() {
  run_mutex "dashboard stop"; local rc=$?
  local err; err=$(cat "$TMP_ROOT/mutex.err")
  if [ "$rc" -eq 2 ] && [[ "$err" == *"ERROR: dashboard is incompatible with stop mode"* ]]; then
    pass "mutex: dashboard + stop -> exit 2 + verbatim diagnostic"
  else
    fail "mutex: dashboard + stop -> exit 2 + verbatim diagnostic" "rc=$rc stderr=[$err]"
  fi
}

test_mutex_next() {
  run_mutex "dashboard next"; local rc=$?
  local err; err=$(cat "$TMP_ROOT/mutex.err")
  if [ "$rc" -eq 2 ] && [[ "$err" == *"ERROR: dashboard is incompatible with next mode"* ]]; then
    pass "mutex: dashboard + next -> exit 2 + verbatim diagnostic"
  else
    fail "mutex: dashboard + next -> exit 2 + verbatim diagnostic" "rc=$rc stderr=[$err]"
  fi
}

# Negative control: clean dashboard invocation (no conflicting flag) does
# NOT exit 2 / does NOT emit any of the 5 mutex errors.
test_mutex_clean_passes() {
  run_mutex "5 dashboard auto"; local rc=$?
  local err; err=$(cat "$TMP_ROOT/mutex.err")
  if [ "$rc" -eq 0 ] && [ -z "$err" ]; then
    pass "mutex: clean 'dashboard auto' -> no exit-2, no error"
  else
    fail "mutex: clean 'dashboard auto' -> no exit-2, no error" "rc=$rc stderr=[$err]"
  fi
}

# Sub-token false-positive control: substrings of conflicting tokens
# must NOT trip the mutex. e.g., `5 dashboard refocus-thing` contains
# `focus` as a substring but not as a whole word — the regex uses
# `($|[[:space:]])` boundaries, so this MUST pass cleanly.
test_mutex_substring_not_tripped() {
  run_mutex "5 dashboard refocus-thing"; local rc=$?
  local err; err=$(cat "$TMP_ROOT/mutex.err")
  if [ "$rc" -eq 0 ] && [ -z "$err" ]; then
    pass "mutex: substring 'refocus' does not trip focus-mutex"
  else
    fail "mutex: substring 'refocus' does not trip focus-mutex" "rc=$rc stderr=[$err]"
  fi
}

# --- run ----------------------------------------------------------------

echo "=== /fix-issues Phase 2 dashboard branch — behavioral coverage (#334) ==="
test_empty_missing_state_file
test_bash_guard_missing_file_exits_zero
test_empty_missing_ready_key
test_empty_top_level_issues_absent
test_empty_ready_array
test_empty_intersection_no_overlap
test_unified_empty_message_at_both_sites
test_intersection_mixed_with_closed
test_intersection_preserves_drag_order
test_n_cap_honored
test_n_cap_one
test_n_cap_unset_takes_all
test_dict_entries_with_number
test_mixed_int_and_dict_entries
test_string_int_entries
test_non_numeric_entries_skipped
test_ready_is_not_a_list_exits_zero
test_malformed_json_exits_zero
test_mutex_focus
test_mutex_sync
test_mutex_plan
test_mutex_stop
test_mutex_next
test_mutex_clean_passes
test_mutex_substring_not_tripped

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
