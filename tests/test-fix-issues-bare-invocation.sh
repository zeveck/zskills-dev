#!/bin/bash
# test-fix-issues-bare-invocation.sh — conformance coverage for the bare
# /fix-issues guard (#1015).
#
# A bare `/fix-issues` (no N, no subcommand) previously fell through the
# execution-path table's "Otherwise (sprint mode with N)" row into
# modes/sprint.md, which dereferences $N with no default. The fix adds a
# Phase-0 guard (BARE_MODE) that routes a truly-bare call to the
# bare-invocation handler in subcommands/stop-next.md, which reports cron
# status (active-cron branch) or a general usage hint (no-cron branch) and
# exits 0 — never entering sprint mode.
#
# This suite asserts, by extracting and executing the real BARE_MODE guard
# block FROM SKILL.md (so the test stays in sync with the shipped code):
#
#   1. The bare guard block exists and is extractable.
#   2. BARE_MODE=1 for a truly-bare ($ARGUMENTS empty / whitespace-only).
#   3. BARE_MODE=0 for a leading N and for EVERY recognized subcommand/flag
#      (stop/next/sync/plan/now/every/pr/direct/dashboard/add/remove/
#      reconsider) — so the guard never steals a real subcommand or a sprint.
#   4. The execution-path table routes the bare case to stop-next.md and
#      NOT to sprint.md.
#   5. The bare-invocation handler section exists in stop-next.md and its
#      no-cron branch emits NO cron-status text (no "No active cron" line).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_ROUTER="$REPO_ROOT/skills/fix-issues/SKILL.md"
STOP_NEXT="$REPO_ROOT/skills/fix-issues/subcommands/stop-next.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# --- Extract the BARE_MODE guard bash block from SKILL.md ----------------
# The block is the fenced bash block that assigns BARE_MODE=0 and contains
# the leading-integer negative-match signature.
BARE_BLOCK="$TMP_ROOT/bare_block.sh"
awk '
  /^```bash$/ { in_fence=1; buf=""; next }
  in_fence && /^```$/ {
    if (buf ~ /BARE_MODE=0/ && buf ~ /\^\[\[:space:\]\]\*\[0-9\]\+/) {
      print buf
      exit
    }
    in_fence=0; buf=""
    next
  }
  in_fence { buf = buf $0 "\n" }
' "$SKILL_ROUTER" > "$BARE_BLOCK"

test_bare_block_extractable() {
  if [ -s "$BARE_BLOCK" ]; then
    pass "extract BARE_MODE guard block from SKILL.md ($(wc -l < "$BARE_BLOCK") lines)"
  else
    fail "extract BARE_MODE guard block from SKILL.md" "extraction produced empty file"
  fi
}

# Run the extracted guard with controlled $ARGUMENTS; echo the resulting
# BARE_MODE value.
run_bare() {
  local arguments="$1"
  ( ARGUMENTS="$arguments"
    # shellcheck disable=SC1090
    source "$BARE_BLOCK"
    printf '%s' "$BARE_MODE"
  )
}

# --- 2. Truly-bare -> BARE_MODE=1 ---------------------------------------
test_empty_args_is_bare() {
  local got; got=$(run_bare "")
  if [ "$got" = "1" ]; then
    pass "bare: empty \$ARGUMENTS -> BARE_MODE=1"
  else
    fail "bare: empty \$ARGUMENTS -> BARE_MODE=1" "BARE_MODE=$got"
  fi
}

test_whitespace_args_is_bare() {
  local got; got=$(run_bare "   ")
  if [ "$got" = "1" ]; then
    pass "bare: whitespace-only \$ARGUMENTS -> BARE_MODE=1"
  else
    fail "bare: whitespace-only \$ARGUMENTS -> BARE_MODE=1" "BARE_MODE=$got"
  fi
}

# --- 3. Leading N + every recognized subcommand -> BARE_MODE=0 ----------
test_not_bare() {
  local label="$1" args="$2"
  local got; got=$(run_bare "$args")
  if [ "$got" = "0" ]; then
    pass "not-bare: $label -> BARE_MODE=0"
  else
    fail "not-bare: $label -> BARE_MODE=0" "BARE_MODE=$got (args=[$args])"
  fi
}

# --- run guard cases -----------------------------------------------------
run_guard_cases() {
  test_not_bare "leading N (30)"            "30"
  test_not_bare "leading N + flags"         "5 auto pr"
  test_not_bare "stop"                      "stop"
  test_not_bare "next"                      "next"
  test_not_bare "sync"                      "sync"
  test_not_bare "plan"                      "plan"
  test_not_bare "now (standalone)"          "now"
  test_not_bare "every SCHEDULE"            "5 auto every 4h"
  test_not_bare "pr"                        "5 pr"
  test_not_bare "direct"                    "3 direct"
  test_not_bare "dashboard"                 "3 dashboard"
  test_not_bare "add <N>"                   "add 700"
  test_not_bare "remove <N>"                "remove 700"
  test_not_bare "reconsider <N>"            "reconsider 717"
}

# --- 4. Execution-path table routing ------------------------------------
test_table_bare_routes_to_stop_next() {
  # The bare row must point at subcommands/stop-next.md, NOT sprint.md.
  local row
  row=$(grep -iE '^\| *Bare .*BARE_MODE' "$SKILL_ROUTER")
  if [ -n "$row" ] \
     && printf '%s' "$row" | grep -qF 'subcommands/stop-next.md' \
     && ! printf '%s' "$row" | grep -qF 'sprint.md'; then
    pass "table: bare row routes to stop-next.md (not sprint.md)"
  else
    fail "table: bare row routes to stop-next.md (not sprint.md)" "row=[$row]"
  fi
}

# --- 5. Bare handler section + no-cron emits no cron status --------------
test_handler_section_present() {
  if grep -qiE '^## Bare invocation' "$STOP_NEXT"; then
    pass "handler: '## Bare invocation' section present in stop-next.md"
  else
    fail "handler: '## Bare invocation' section present in stop-next.md" "section heading not found"
  fi
}

test_no_cron_branch_emits_no_cron_status() {
  # Isolate the Bare-invocation section body and assert its no-cron branch
  # explicitly suppresses cron-status output. The handler must NOT print a
  # "No active cron" line in the no-cron branch.
  local section
  section=$(awk '
    /^## Bare invocation/ { capture=1; next }
    capture && /^## / { exit }
    capture { print }
  ' "$STOP_NEXT")

  if [ -z "$section" ]; then
    fail "no-cron: bare-invocation section body extractable" "empty section"
    return
  fi

  # Must explicitly call out emitting NO cron-status text on the no-cron path.
  if printf '%s' "$section" | grep -qiE 'no cron-status text|no cron' \
     && ! printf '%s' "$section" | grep -qiE 'No active .*cron found|No active /fix-issues cron in this session'; then
    pass "no-cron: handler suppresses cron-status text (no 'No active cron' line)"
  else
    fail "no-cron: handler suppresses cron-status text" \
         "expected an explicit no-cron-output instruction and NO 'No active cron' line in the bare section"
  fi
}

test_handler_says_general_usage_hint() {
  local section
  section=$(awk '
    /^## Bare invocation/ { capture=1; next }
    capture && /^## / { exit }
    capture { print }
  ' "$STOP_NEXT")
  # The no-cron branch must print the general usage hint (N [auto] + subcommands).
  if printf '%s' "$section" | grep -qF '/fix-issues N [auto]'; then
    pass "no-cron: general usage hint present ('/fix-issues N [auto]')"
  else
    fail "no-cron: general usage hint present" "expected '/fix-issues N [auto]' in bare section"
  fi
}

test_handler_never_enters_sprint() {
  local section
  section=$(awk '
    /^## Bare invocation/ { capture=1; next }
    capture && /^## / { exit }
    capture { print }
  ' "$STOP_NEXT")
  if printf '%s' "$section" | grep -qiE 'never .*sprint|do NOT .*sprint|not enter .*sprint\.md|never .*sprint\.md'; then
    pass "handler: explicitly forbids entering modes/sprint.md"
  else
    fail "handler: explicitly forbids entering modes/sprint.md" "no sprint.md prohibition found in section"
  fi
}

# --- run ----------------------------------------------------------------
echo "=== /fix-issues bare-invocation guard — conformance (#1015) ==="
test_bare_block_extractable
test_empty_args_is_bare
test_whitespace_args_is_bare
run_guard_cases
test_table_bare_routes_to_stop_next
test_handler_section_present
test_no_cron_branch_emits_no_cron_status
test_handler_says_general_usage_hint
test_handler_never_enters_sprint

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
