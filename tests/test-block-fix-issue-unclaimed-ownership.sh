#!/bin/bash
# tests/test-block-fix-issue-unclaimed-ownership.sh — issue #865.
#
# Covers the pipeline-ownership check added on top of the bare existence
# check in hooks/block-fix-issue-unclaimed.sh. Existing baseline behaviour
# (deny on no claim, allow on present claim for the SAME pipeline) is
# covered by tests/test-fix-issues-claim-regression-single.sh; this file
# adds the ownership-mismatch and infra-failure-fail-open arms.
#
# Cases:
#   1. Self-re-entry pass — claim.json.pipeline_id == caller --pipeline-id
#      → hook exits 0 with no deny envelope.
#   2. Foreign-pipeline deny — claim.json.pipeline_id != caller
#      --pipeline-id → hook emits a deny envelope citing both ids.
#   3. Fail-open on absent claim.json — claim dir exists but claim.json is
#      missing (e.g. mid-acquire crash window) → hook exits 0 with WARN to
#      stderr; no deny.
#   4. Fail-open on malformed claim.json — claim dir + claim.json with
#      invalid JSON → hook exits 0 with WARN; no deny.
#   5. Fail-open when caller omits --pipeline-id — claim dir + valid
#      claim.json but the create-worktree command line has no
#      --pipeline-id flag → hook exits 0 with WARN; no deny. (Cannot
#      false-deny on unverifiable state.)
#   6. Baseline no-claim deny still fires — sanity backstop confirming
#      the ownership extension didn't break the existence-only path.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# DA9 (CASCADE v2, ENFORCEMENT_V2 Phase 4): sandbox HOME so a dev machine's
# personal ~/.claude/zskills-config.json (which Phase 6 promotes creating)
# cannot flip the claim-hook's branch_prefix two-tier read.
TMP_HOME="$(mktemp -d /tmp/zskills-block-fix-issue-home-XXXXXX)"; export HOME="$TMP_HOME"
printf '[user]\n\tname = zskills-test\n\temail = zskills-test@example.com\n[safe]\n\tdirectory = *\n' > "$TMP_HOME/.gitconfig"
HOOK="$REPO_ROOT/hooks/block-fix-issue-unclaimed.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-block-fix-issue-unclaimed-ownership-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -mindepth 1 -delete || true
    rmdir "$SCRATCH_ROOT" || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

if [ ! -f "$HOOK" ]; then
  echo "FATAL: $HOOK missing" >&2; exit 1
fi

echo "=== block-fix-issue-unclaimed.sh ownership check (#865) ==="

# Per-case fixture initialised on demand. Each test cd's into a fresh git
# working tree so MAIN_ROOT resolution (git rev-parse --git-common-dir
# parent) lands on a known root, and stages its own .zskills/claims/issue-N
# state.
init_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  ( cd "$dir" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init" )
}

write_claim() {
  # write_claim <fixture_dir> <issue> <pipeline_id>
  local fixture="$1" n="$2" pid="$3"
  local claim_dir="$fixture/.zskills/claims/issue-$n"
  mkdir -p "$claim_dir"
  python3 -c "
import json, sys
body = {
    'schema_version': 1,
    'pipeline_id': sys.argv[1],
    'sprint_id': 'sprint-test',
    'issue': int(sys.argv[2]),
    'started_at': '2026-05-31T00:00:00+00:00',
}
with open(sys.argv[3], 'w') as f:
    json.dump(body, f, sort_keys=True)
    f.write('\n')
" "$pid" "$n" "$claim_dir/claim.json"
}

write_malformed_claim() {
  # write_malformed_claim <fixture_dir> <issue>
  local fixture="$1" n="$2"
  local claim_dir="$fixture/.zskills/claims/issue-$n"
  mkdir -p "$claim_dir"
  printf '{not valid json' > "$claim_dir/claim.json"
}

write_empty_claim_dir() {
  # write_empty_claim_dir <fixture_dir> <issue>  (no claim.json — simulates
  # mid-acquire crash window)
  local fixture="$1" n="$2"
  mkdir -p "$fixture/.zskills/claims/issue-$n"
}

build_payload() {
  # build_payload <issue> <pipeline_id_arg_or_empty>
  # When pipeline_id_arg is empty, the resulting command omits
  # --pipeline-id entirely (used by case 5).
  local n="$1" pid="$2"
  local cmd
  if [ -n "$pid" ]; then
    cmd="bash $REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh --prefix fix-issue --purpose \"fix-issues; issue=$n\" --pipeline-id $pid $n"
  else
    cmd="bash $REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh --prefix fix-issue --purpose \"fix-issues; issue=$n\" $n"
  fi
  python3 -c "
import json, sys
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': { 'command': sys.argv[1] },
}))
" "$cmd"
}

run_hook() {
  # run_hook <fixture_dir> <payload>
  # Returns the captured rc; stdout in $LAST_STDOUT, stderr in $LAST_STDERR.
  local fixture="$1" payload="$2"
  local out_file="$SCRATCH_ROOT/_out.$$"
  local err_file="$SCRATCH_ROOT/_err.$$"
  (
    cd "$fixture" || exit 1
    echo "$payload" | bash "$HOOK"
  ) >"$out_file" 2>"$err_file"
  LAST_RC=$?
  LAST_STDOUT=$(cat "$out_file")
  LAST_STDERR=$(cat "$err_file")
  rm -f "$out_file" "$err_file"
}

# ───────────────────────────────────────────────────────────────────────
# Test 1: self-re-entry pass.
# ───────────────────────────────────────────────────────────────────────
F1="$SCRATCH_ROOT/f1"
init_fixture "$F1" || { fail "test 1" "fixture init"; }
write_claim "$F1" 10 "pipe-self"
PAYLOAD=$(build_payload 10 "pipe-self")
run_hook "$F1" "$PAYLOAD"
if [ "$LAST_RC" -ne 0 ]; then
  fail "self-re-entry pass" "hook exited $LAST_RC, expected 0; stdout=$LAST_STDOUT stderr=$LAST_STDERR"
elif echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"'; then
  fail "self-re-entry pass" "hook emitted deny envelope despite matching pipeline_id: $LAST_STDOUT"
else
  pass "self-re-entry — caller pipeline_id matches claim.json:pipeline_id; hook allows"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 2: foreign-pipeline deny.
# ───────────────────────────────────────────────────────────────────────
F2="$SCRATCH_ROOT/f2"
init_fixture "$F2"
write_claim "$F2" 11 "pipe-A-holder"
PAYLOAD=$(build_payload 11 "pipe-B-intruder")
run_hook "$F2" "$PAYLOAD"
if [ "$LAST_RC" -ne 0 ]; then
  fail "foreign-pipeline deny" "hook exited $LAST_RC, expected 0 (deny envelope on stdout); stderr=$LAST_STDERR"
elif ! echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"'; then
  fail "foreign-pipeline deny" "hook did NOT emit deny envelope on pipeline mismatch; stdout=$LAST_STDOUT"
elif ! echo "$LAST_STDOUT" | grep -q 'pipe-A-holder'; then
  fail "foreign-pipeline deny" "deny envelope omitted the stored pipeline_id; stdout=$LAST_STDOUT"
elif ! echo "$LAST_STDOUT" | grep -q 'pipe-B-intruder'; then
  fail "foreign-pipeline deny" "deny envelope omitted the caller pipeline_id; stdout=$LAST_STDOUT"
elif ! echo "$LAST_STDOUT" | grep -q 'fix-issue-11'; then
  fail "foreign-pipeline deny" "deny envelope omitted the issue number; stdout=$LAST_STDOUT"
else
  pass "foreign-pipeline deny — claim.json.pipeline_id != caller --pipeline-id; hook denies with both ids cited"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 3: fail-open on absent claim.json (mid-acquire crash window).
# ───────────────────────────────────────────────────────────────────────
F3="$SCRATCH_ROOT/f3"
init_fixture "$F3"
write_empty_claim_dir "$F3" 12
PAYLOAD=$(build_payload 12 "pipe-any")
run_hook "$F3" "$PAYLOAD"
if [ "$LAST_RC" -ne 0 ]; then
  fail "fail-open on absent claim.json" "hook exited $LAST_RC, expected 0 (allow); stdout=$LAST_STDOUT stderr=$LAST_STDERR"
elif echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"'; then
  fail "fail-open on absent claim.json" "hook false-denied on unverifiable state: $LAST_STDOUT"
elif ! echo "$LAST_STDERR" | grep -q 'WARN.*claim.json missing'; then
  fail "fail-open on absent claim.json" "hook did not emit WARN to stderr; stderr=$LAST_STDERR"
else
  pass "fail-open on absent claim.json — hook allows + WARN to stderr (mid-acquire crash window not false-denied)"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 4: fail-open on malformed claim.json.
# ───────────────────────────────────────────────────────────────────────
F4="$SCRATCH_ROOT/f4"
init_fixture "$F4"
write_malformed_claim "$F4" 13
PAYLOAD=$(build_payload 13 "pipe-any")
run_hook "$F4" "$PAYLOAD"
if [ "$LAST_RC" -ne 0 ]; then
  fail "fail-open on malformed claim.json" "hook exited $LAST_RC, expected 0 (allow); stdout=$LAST_STDOUT stderr=$LAST_STDERR"
elif echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"'; then
  fail "fail-open on malformed claim.json" "hook false-denied on unverifiable state: $LAST_STDOUT"
elif ! echo "$LAST_STDERR" | grep -q 'WARN.*malformed'; then
  fail "fail-open on malformed claim.json" "hook did not emit malformed WARN to stderr; stderr=$LAST_STDERR"
else
  pass "fail-open on malformed claim.json — hook allows + WARN to stderr"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 5: fail-open when caller omits --pipeline-id.
# ───────────────────────────────────────────────────────────────────────
F5="$SCRATCH_ROOT/f5"
init_fixture "$F5"
write_claim "$F5" 14 "pipe-holder"
PAYLOAD=$(build_payload 14 "")  # no --pipeline-id arg on the command line
run_hook "$F5" "$PAYLOAD"
if [ "$LAST_RC" -ne 0 ]; then
  fail "fail-open on missing caller --pipeline-id" "hook exited $LAST_RC, expected 0 (allow); stdout=$LAST_STDOUT stderr=$LAST_STDERR"
elif echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"'; then
  fail "fail-open on missing caller --pipeline-id" "hook false-denied on unverifiable caller id: $LAST_STDOUT"
elif ! echo "$LAST_STDERR" | grep -q 'WARN.*caller did not pass --pipeline-id'; then
  fail "fail-open on missing caller --pipeline-id" "hook did not emit caller-pipeline-id WARN; stderr=$LAST_STDERR"
else
  pass "fail-open when caller omits --pipeline-id — hook allows + WARN (cannot false-deny on unverifiable input)"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 6: baseline no-claim deny still fires.
# ───────────────────────────────────────────────────────────────────────
F6="$SCRATCH_ROOT/f6"
init_fixture "$F6"
# Intentionally NO write_claim call — the claim dir does not exist.
PAYLOAD=$(build_payload 15 "pipe-any")
run_hook "$F6" "$PAYLOAD"
if [ "$LAST_RC" -ne 0 ]; then
  fail "baseline no-claim deny" "hook exited $LAST_RC, expected 0 (deny envelope on stdout); stderr=$LAST_STDERR"
elif ! echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"'; then
  fail "baseline no-claim deny" "existence check regressed — no deny on missing claim; stdout=$LAST_STDOUT"
elif ! echo "$LAST_STDOUT" | grep -q 'no claim found'; then
  fail "baseline no-claim deny" "deny envelope no longer cites 'no claim found'; stdout=$LAST_STDOUT"
else
  pass "baseline no-claim deny — existence-check path still fires (ownership extension is additive)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# ENFORCEMENT_V2_PLAN Phase 2 (#1159) — issue_unclaimed demotion + bypass parity.
# issue_unclaimed is DEMOTABLE: autonomous/unwatched → BLOCK; watched → SILENT
# by shipped default; opt-in "warn". Bypass parity asserts the autonomous deny
# is intact under explicit permission_mode:"bypassPermissions".
# ═══════════════════════════════════════════════════════════════════════════

build_payload_pm() {
  # build_payload_pm <issue> <pipeline_id_or_empty> <permission_mode>
  local n="$1" pid="$2" pm="$3" cmd
  if [ -n "$pid" ]; then
    cmd="bash $REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh --prefix fix-issue --purpose \"fix-issues; issue=$n\" --pipeline-id $pid $n"
  else
    cmd="bash $REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh --prefix fix-issue --purpose \"fix-issues; issue=$n\" $n"
  fi
  python3 -c "
import json, sys
print(json.dumps({
    'tool_name': 'Bash',
    'tool_input': { 'command': sys.argv[1] },
    'permission_mode': sys.argv[2],
}))
" "$cmd" "$pm"
}

write_hooks_config() {
  # write_hooks_config <fixture_dir> <json-config-body>
  mkdir -p "$1/.claude"
  printf '%s' "$2" > "$1/.claude/zskills-config.json"
}

# ── P1: bypass-parity (foreign-pipeline deny under bypassPermissions) ──────
FP1="$SCRATCH_ROOT/fp1"
init_fixture "$FP1"
write_claim "$FP1" 21 "pipe-A-holder"
PAYLOAD=$(build_payload_pm 21 "pipe-B-intruder" "bypassPermissions")
run_hook "$FP1" "$PAYLOAD"
if echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"' \
   && echo "$LAST_STDOUT" | grep -q '\[hooks.tracking.issue_unclaimed'; then
  pass "P1: foreign-pipeline deny under bypassPermissions (bypass parity 1/5) + names toggle"
else
  fail "P1: foreign-pipeline deny under bypass" "stdout=$LAST_STDOUT"
fi

# ── P2: bypass-parity (no-claim deny under bypassPermissions) ──────────────
FP2="$SCRATCH_ROOT/fp2"
init_fixture "$FP2"
PAYLOAD=$(build_payload_pm 22 "pipe-any" "bypassPermissions")
run_hook "$FP2" "$PAYLOAD"
if echo "$LAST_STDOUT" | grep -q '"permissionDecision":"deny"' \
   && echo "$LAST_STDOUT" | grep -q 'no claim found' \
   && echo "$LAST_STDOUT" | grep -q '\[hooks.tracking.issue_unclaimed'; then
  pass "P2: no-claim deny under bypassPermissions (bypass parity 2/5) + names toggle"
else
  fail "P2: no-claim deny under bypass" "stdout=$LAST_STDOUT"
fi

# ── P3: watched (default) + no toggle → SILENT (allow, emits nothing) ──────
FP3="$SCRATCH_ROOT/fp3"
init_fixture "$FP3"
PAYLOAD=$(build_payload_pm 23 "pipe-any" "default")
run_hook "$FP3" "$PAYLOAD"
if [ "$LAST_RC" -eq 0 ] && [ -z "$LAST_STDOUT" ]; then
  pass "P3: watched no-claim, no toggle → SILENT allow (demotable shipped default)"
else
  fail "P3: watched no-toggle → SILENT" "rc=$LAST_RC stdout=$LAST_STDOUT"
fi

# ── P4: toggle "warn" + watched → ALLOW + warn-channel carries the tag ─────
FP4="$SCRATCH_ROOT/fp4"
init_fixture "$FP4"
write_hooks_config "$FP4" '{"hooks":{"tracking":{"issue_unclaimed":"warn"}}}'
PAYLOAD=$(build_payload_pm 24 "pipe-any" "default")
run_hook "$FP4" "$PAYLOAD"
if [ "$LAST_RC" -eq 0 ] \
   && echo "$LAST_STDOUT" | grep -q '"systemMessage"' \
   && echo "$LAST_STDOUT" | grep -q '\[hooks.tracking.issue_unclaimed' \
   && ! echo "$LAST_STDOUT" | grep -q 'permissionDecision'; then
  pass "P4: toggle warn + watched → ALLOW + decision-less warn naming the toggle"
else
  fail "P4: toggle warn + watched → warn" "rc=$LAST_RC stdout=$LAST_STDOUT"
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
