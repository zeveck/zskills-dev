#!/bin/bash
# tests/test-fix-issues-claim-conformance.sh — Phase 4 W4.2.
#
# Conformance battery for plans/fix-issues-claims.md. Locks the source-
# code invariants that the runtime mechanism and the docs both depend on:
#
#   - Script + helper presence (source + mirror).
#   - Hook presence + executable + mirrored.
#   - .claude/settings.json registers the hook on PreToolUse/Bash.
#   - SKILL.md acquire-fence shape (TWO-PASS grep — implemented Phase 2
#     uses $CLAIM_HELPER indirection, not inline `claim-issue.sh acquire`).
#     PLAN-TEXT-DRIFT: phase=4 bullet=W4.2 field=anchor_regex
#       plan=claim-issue.sh"?[[:space:]]+acquire  actual=two-pass-grep
#   - claim-issue.sh acquire validates non-positive / non-numeric inputs.
#   - No inline `rm -r .zskills/claims` outside the script itself.
#   - Hook payload contract tests (positive, allow-on-claim, ensure-
#     worktree wrapper, argv tokenization, --branch-name override,
#     non-fix-issue prefix, non-Bash tool, MAIN_ROOT resolution from a
#     sprint worktree).
#   - Per-fence shape: `exit 0` within ±15 lines, no bare `continue`.
#   - .zskills/claims/ is gitignored.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"
CLAIM_HELPERS="$REPO_ROOT/skills/fix-issues/scripts/claim-fence-helpers.sh"
CLAIM_SH_MIRROR="$REPO_ROOT/.claude/skills/fix-issues/scripts/claim-issue.sh"
CLAIM_HELPERS_MIRROR="$REPO_ROOT/.claude/skills/fix-issues/scripts/claim-fence-helpers.sh"
HOOK="$REPO_ROOT/hooks/block-fix-issue-unclaimed.sh"
HOOK_MIRROR="$REPO_ROOT/.claude/hooks/block-fix-issue-unclaimed.sh"
SETTINGS="$REPO_ROOT/.claude/settings.json"
SKILL_MD="$REPO_ROOT/skills/fix-issues/modes/sprint.md"
GITIGNORE="$REPO_ROOT/.gitignore"
CREATE_WT="$REPO_ROOT/skills/create-worktree/scripts/create-worktree.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-claim-conformance-$$"
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

echo "=== fix-issues claim mechanism conformance ==="

# ───────────────────────────────────────────────────────────────────────
# Test 1: script + helpers exist in BOTH source and mirror.
# ───────────────────────────────────────────────────────────────────────
missing=""
for p in "$CLAIM_SH" "$CLAIM_HELPERS" "$CLAIM_SH_MIRROR" "$CLAIM_HELPERS_MIRROR"; do
  [ -f "$p" ] || missing="$missing $p"
done
if [ -z "$missing" ]; then
  pass "claim-issue.sh + claim-fence-helpers.sh exist in source + mirror"
else
  fail "claim scripts present" "missing:$missing"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 2: hook exists, executable, mirrored.
# ───────────────────────────────────────────────────────────────────────
if [ ! -f "$HOOK" ]; then
  fail "hook present" "$HOOK missing"
elif [ ! -x "$HOOK" ]; then
  fail "hook executable" "$HOOK not executable"
elif [ ! -f "$HOOK_MIRROR" ]; then
  fail "hook mirrored" "$HOOK_MIRROR missing"
else
  pass "block-fix-issue-unclaimed.sh exists, is executable, mirrored to .claude/hooks/"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 3: settings.json JSON-parse → confirm hook is registered on
# PreToolUse / Bash matcher.
# ───────────────────────────────────────────────────────────────────────
reg_ok=$(python3 -c "
import json, sys
try:
    cfg = json.load(open('$SETTINGS'))
except Exception as e:
    print('PARSE_FAIL:' + str(e))
    sys.exit(0)
pre = cfg.get('hooks', {}).get('PreToolUse', [])
for entry in pre:
    if entry.get('matcher') != 'Bash':
        continue
    for h in entry.get('hooks', []):
        cmd = h.get('command', '')
        if 'block-fix-issue-unclaimed.sh' in cmd:
            print('OK')
            sys.exit(0)
print('NOT_FOUND')
")
case "$reg_ok" in
  OK) pass ".claude/settings.json registers block-fix-issue-unclaimed.sh on PreToolUse/Bash" ;;
  *)  fail "settings.json hook registration" "result: $reg_ok" ;;
esac

# ───────────────────────────────────────────────────────────────────────
# Test 4: SKILL.md acquire-fence grep (TWO-PASS — accommodates the
# implemented Phase 2 $CLAIM_HELPER indirection).
# Counts (a) CLAIM_HELPER assignment pointing at claim-issue.sh and
# (b) `bash "$CLAIM_HELPER" acquire` invocations. Both must be >= 2
# (W2.2a cherry-pick/direct + W2.2b PR mode).
# ───────────────────────────────────────────────────────────────────────
ASSIGN_HITS=$(grep -cE 'CLAIM_HELPER="[^"]*claim-issue\.sh"' "$SKILL_MD")
INVOKE_HITS=$(grep -cE 'bash[[:space:]]+"\$CLAIM_HELPER"[[:space:]]+acquire' "$SKILL_MD")
if [ "$ASSIGN_HITS" -ge 2 ] && [ "$INVOKE_HITS" -ge 2 ]; then
  pass "SKILL.md acquire-fence two-pass grep: $ASSIGN_HITS CLAIM_HELPER assignments + $INVOKE_HITS \"\$CLAIM_HELPER\" acquire invocations (W2.2a + W2.2b both present)"
else
  fail "SKILL.md acquire-fence grep" "assignment hits=$ASSIGN_HITS, invocation hits=$INVOKE_HITS — both must be >= 2"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 5: claim-issue.sh acquire 0 rejects.
# ───────────────────────────────────────────────────────────────────────
out=$(bash "$CLAIM_SH" acquire 0 --pipeline-id x --sprint-id y 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "claim-issue.sh acquire 0 rejects (rc=$rc, non-zero)"
else
  fail "acquire 0 reject" "rc=$rc out=$out (expected non-zero)"
fi

# Test 6: claim-issue.sh acquire abc rejects.
out=$(bash "$CLAIM_SH" acquire abc --pipeline-id x --sprint-id y 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "claim-issue.sh acquire abc rejects (rc=$rc, non-zero)"
else
  fail "acquire abc reject" "rc=$rc out=$out (expected non-zero)"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 7: NO inline `rm -r|-rf|--recursive` against .zskills/claims/ in
# SKILL.md or modes/*.md — these are the consumer-facing surfaces where
# such a call would blow away live claims. Per plan regex (R2/R5/DA3):
#   \brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)[[:space:]]+[^;&|]*\.zskills/claims
# Tests/* are exempt — they manage their own per-PID /tmp/...$$ fixture
# scratch dirs and a fixture-cleanup `rm -rf $FIXTURE/.zskills/claims`
# does not threaten any live claim (the fixture is private to the test).
# ───────────────────────────────────────────────────────────────────────
search_targets=()
search_targets+=("$SKILL_MD")
if [ -d "$REPO_ROOT/skills/fix-issues/modes" ]; then
  while IFS= read -r f; do search_targets+=("$f"); done < <(find "$REPO_ROOT/skills/fix-issues/modes" -type f -name '*.md')
fi

violations=""
for f in "${search_targets[@]}"; do
  # ERE-safe form. Pattern: rm + space(s) + (-[letters]*r[letters]* | --recursive) + space + non-pipe* + .zskills/claims
  hits=$(grep -nE '(^|[^a-zA-Z_])rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)[[:space:]]+[^;&|]*\.zskills/claims' "$f" || true)
  if [ -n "$hits" ]; then
    violations="$violations\n$f:\n$hits\n"
  fi
done
if [ -z "$violations" ]; then
  pass "no inline 'rm -r .zskills/claims' in SKILL.md / modes/*.md (R2/R5/DA3 — tests/* exempt for fixture cleanup)"
else
  fail "inline rm -r .zskills/claims" "$(printf '%b' "$violations")"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 8-15: Hook payload contract tests. Use a real fixture git repo
# so MAIN_ROOT resolves cleanly.
# ───────────────────────────────────────────────────────────────────────
FIXTURE="$SCRATCH_ROOT/hookrepo"
mkdir -p "$FIXTURE"
( cd "$FIXTURE" && git init -q && git config user.email "t@t" && git config user.name "t" \
  && git commit --allow-empty -q -m "init" ) \
  || { echo "FATAL: hook fixture init failed" >&2; exit 1; }

# Helper: build a PreToolUse JSON envelope via Python json.dumps.
mkpayload() {
  python3 -c "
import json, sys
tool_name = sys.argv[1]
cmd = sys.argv[2]
print(json.dumps({'tool_name': tool_name, 'tool_input': {'command': cmd}}))
" "$@"
}

# ─── Test 8: hook positive — fix-issue-NNN payload with NO claim → deny.
(
  cd "$FIXTURE" || exit 1
  rm -rf "$FIXTURE/.zskills/claims"
  payload=$(mkpayload Bash "bash $CREATE_WT --prefix fix-issue 42")
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  rc=$?
  # Exit 0 is required (PreToolUse contract — deny is communicated via JSON, not exit code).
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON hook returned $rc (expected exit 0 — deny is JSON envelope)"
    exit 1
  fi
  if ! echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON missing deny envelope; out: $stdout"
    exit 1
  fi
  # Locked recovery-instruction text (DA4.4).
  if ! echo "$stdout" | grep -q 'STOP:'; then
    echo "FAIL_REASON deny envelope missing 'STOP:'; out: $stdout"
    exit 1
  fi
  if ! echo "$stdout" | grep -q 'claim-issue.sh acquire 42'; then
    echo "FAIL_REASON deny envelope missing 'claim-issue.sh acquire 42'; out: $stdout"
    exit 1
  fi
  if ! echo "$stdout" | grep -q 'exit 10'; then
    echo "FAIL_REASON deny envelope missing 'exit 10' race-skip guidance; out: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook positive: fix-issue-42 payload with no claim → deny envelope with locked STOP/acquire/exit-10 recovery text"
else
  fail "hook positive" "see FAIL_REASON above"
fi

# ─── Test 9: hook allow-on-claim — same payload, claim pre-created.
(
  cd "$FIXTURE" || exit 1
  rm -rf "$FIXTURE/.zskills/claims"
  mkdir -p "$FIXTURE/.zskills/claims/issue-42"
  payload=$(mkpayload Bash "bash $CREATE_WT --prefix fix-issue 42")
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON hook returned $rc, expected 0 (allow); out: $stdout"
    exit 1
  fi
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON hook denied despite claim present: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook allow-on-claim: claim issue-42/ exists → exit 0, no deny envelope"
else
  fail "hook allow-on-claim" "see FAIL_REASON above"
fi

# ─── Test 10: ensure-worktree.sh wrapper coverage (R4.1/DA4.3).
(
  cd "$FIXTURE" || exit 1
  rm -rf "$FIXTURE/.zskills/claims"
  # No claim → deny.
  payload=$(mkpayload Bash "bash $REPO_ROOT/skills/create-worktree/scripts/ensure-worktree.sh --prefix fix-issue 42")
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  if ! echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON ensure-worktree.sh + no claim → expected deny; got: $stdout"
    exit 1
  fi
  # Claim present → allow.
  mkdir -p "$FIXTURE/.zskills/claims/issue-42"
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON ensure-worktree.sh + claim present → unexpected deny: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook ensure-worktree wrapper: deny without claim, allow with claim (locks widened regex per R4.1/DA4.3)"
else
  fail "hook ensure-worktree wrapper" "see FAIL_REASON above"
fi

# ─── Test 11: argv tokenization disambiguation (DA4.2).
# --purpose value contains 'issue=99' but positional slug is 42.
# Hook must check claim for issue-42, NOT issue-99.
(
  cd "$FIXTURE" || exit 1
  rm -rf "$FIXTURE/.zskills/claims"
  mkdir -p "$FIXTURE/.zskills/claims/issue-42"
  payload=$(mkpayload Bash "bash $CREATE_WT --prefix fix-issue --purpose \"fix-issues; issue=99\" --pipeline-id X 42")
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON tokenization: claim-42 present + --purpose contains issue=99 → unexpected deny: $stdout"
    exit 1
  fi
  # Now with no claim at all → deny naming 42 (not 99).
  rm -rf "$FIXTURE/.zskills/claims"
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  if ! echo "$stdout" | grep -q 'fix-issue-42'; then
    echo "FAIL_REASON tokenization: deny envelope should name issue 42, got: $stdout"
    exit 1
  fi
  if echo "$stdout" | grep -q 'fix-issue-99'; then
    echo "FAIL_REASON tokenization: deny envelope wrongly named issue 99 (regex bled from --purpose value): $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook argv tokenization (DA4.2): positional slug 42 wins over 'issue=99' in --purpose value"
else
  fail "hook argv tokenization" "see FAIL_REASON above"
fi

# ─── Test 12: --branch-name override precedence.
# Hook must resolve branch to fix/issue-77 and check claim for issue 77.
(
  cd "$FIXTURE" || exit 1
  rm -rf "$FIXTURE/.zskills/claims"
  payload=$(mkpayload Bash "bash $CREATE_WT --prefix fix-issue --branch-name \"fix/issue-77\" 42")
  # No claim for 77 → deny naming 77 (not 42).
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  if ! echo "$stdout" | grep -q 'fix-issue-77'; then
    echo "FAIL_REASON --branch-name precedence: deny envelope should name issue 77, got: $stdout"
    exit 1
  fi
  # Now add claim for 77 → allow.
  mkdir -p "$FIXTURE/.zskills/claims/issue-77"
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON --branch-name precedence: claim-77 present → unexpected deny: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook --branch-name override resolves to fix/issue-77 (overrides --prefix fix-issue+slug 42)"
else
  fail "hook --branch-name override" "see FAIL_REASON above"
fi

# ─── Test 13: non-fix-issue prefix → allow (no claim check).
(
  cd "$FIXTURE" || exit 1
  rm -rf "$FIXTURE/.zskills/claims"
  payload=$(mkpayload Bash "bash $CREATE_WT --prefix cp 99")
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON --prefix cp returned $rc, expected 0; out: $stdout"
    exit 1
  fi
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON --prefix cp got deny envelope; out: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook non-fix-issue prefix (cp-99): exit 0, no claim check"
else
  fail "hook non-fix-issue prefix" "see FAIL_REASON above"
fi

# ─── Test 14: non-Bash tool → allow.
(
  cd "$FIXTURE" || exit 1
  rm -rf "$FIXTURE/.zskills/claims"
  payload=$(python3 -c "
import json
print(json.dumps({'tool_name': 'Edit', 'tool_input': {'file_path': '/tmp/x', 'old_string': 'a', 'new_string': 'b'}}))
")
  stdout=$(echo "$payload" | bash "$HOOK" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL_REASON non-Bash returned $rc, expected 0; out: $stdout"
    exit 1
  fi
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON non-Bash tool got deny envelope: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook non-Bash tool (Edit): exit 0, no claim check"
else
  fail "hook non-Bash tool filter" "see FAIL_REASON above"
fi

# ─── Test 15: MAIN_ROOT resolution from a sprint worktree (DA4.1).
# Allow case: cd into a sprint worktree, claim lives at MAIN_ROOT, hook
# must resolve MAIN_ROOT via git rev-parse --git-common-dir and find it.
SPRINT_WT="$SCRATCH_ROOT/sprint-wt"
(
  cd "$FIXTURE" && git worktree add -q "$SPRINT_WT" -b "feat/fixture-sprint" 2>&1
) >/dev/null
if [ ! -d "$SPRINT_WT" ]; then
  fail "hook MAIN_ROOT resolution: worktree fixture setup" "git worktree add failed"
else
(
  cd "$SPRINT_WT" || exit 1
  # Real claim at MAIN_ROOT.
  rm -rf "$FIXTURE/.zskills/claims" "$SPRINT_WT/.zskills/claims"
  mkdir -p "$FIXTURE/.zskills/claims/issue-42"
  # Unset CLAUDE_PROJECT_DIR so the hook is forced through git rev-parse.
  payload=$(mkpayload Bash "bash $CREATE_WT --prefix fix-issue 42")
  stdout=$(env -u CLAUDE_PROJECT_DIR bash -c "echo '$payload' | bash '$HOOK'" 2>&1)
  if echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON MAIN_ROOT (allow): claim at MAIN_ROOT, cwd=sprint-wt → unexpected deny: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook MAIN_ROOT resolution (allow): claim at MAIN_ROOT + cwd=sprint-worktree → allow via git-common-dir"
else
  fail "hook MAIN_ROOT resolution (allow)" "see FAIL_REASON above"
fi

# Deny case: claim at the WRONG root (sprint-worktree's .zskills/claims),
# no claim at MAIN_ROOT → must deny.
(
  cd "$SPRINT_WT" || exit 1
  rm -rf "$FIXTURE/.zskills/claims" "$SPRINT_WT/.zskills/claims"
  mkdir -p "$SPRINT_WT/.zskills/claims/issue-42"   # wrong root
  payload=$(mkpayload Bash "bash $CREATE_WT --prefix fix-issue 42")
  stdout=$(env -u CLAUDE_PROJECT_DIR bash -c "echo '$payload' | bash '$HOOK'" 2>&1)
  if ! echo "$stdout" | grep -q '"permissionDecision":"deny"'; then
    echo "FAIL_REASON MAIN_ROOT (deny): claim only at wrong root → expected deny; got: $stdout"
    exit 1
  fi
  exit 0
)
if [ "$?" -eq 0 ]; then
  pass "hook MAIN_ROOT resolution (deny): claim at WRONG root (sprint-wt) → deny (MAIN_ROOT alignment with claim-issue.sh)"
else
  fail "hook MAIN_ROOT resolution (deny)" "see FAIL_REASON above"
fi

# Cleanup the worktree before scratch teardown.
( cd "$FIXTURE" && git worktree remove --force "$SPRINT_WT" ) >/dev/null || true
fi

# ───────────────────────────────────────────────────────────────────────
# Test 16: per-fence shape — ±15 lines around each CLAIM_HELPER assign
# must contain `exit 0` and MUST NOT contain a bare `continue` token.
# (R4.3/DA4.5.)
# ───────────────────────────────────────────────────────────────────────
shape_ok=1
# Get line numbers of CLAIM_HELPER assignment hits.
while IFS=: read -r lineno _; do
  start=$((lineno - 15))
  [ "$start" -lt 1 ] && start=1
  end=$((lineno + 15))
  window=$(sed -n "${start},${end}p" "$SKILL_MD")
  if ! echo "$window" | grep -q 'exit 0'; then
    echo "FAIL_REASON fence at SKILL.md:$lineno missing 'exit 0' in ±15 lines"
    shape_ok=0
  fi
  # Bare `continue` — match `continue` as its own statement (start of line
  # after whitespace, optionally followed by whitespace + comment or EOL).
  if echo "$window" | grep -qE '^[[:space:]]*continue[[:space:]]*(#|$)'; then
    echo "FAIL_REASON fence at SKILL.md:$lineno contains bare 'continue' (should use 'exit 0' for prose-iterated fences)"
    shape_ok=0
  fi
done < <(grep -nE 'CLAIM_HELPER="[^"]*claim-issue\.sh"' "$SKILL_MD")
if [ "$shape_ok" = "1" ]; then
  pass "per-fence shape: each acquire fence has 'exit 0' within ±15 lines and no bare 'continue' (R4.3/DA4.5)"
else
  fail "per-fence shape" "see FAIL_REASON lines above"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 17: .zskills/claims/ is gitignored (likely via .zskills/ blanket).
# ───────────────────────────────────────────────────────────────────────
if grep -qE '^\.zskills(/|$)' "$GITIGNORE"; then
  pass ".gitignore covers .zskills/ (blanket rule includes .zskills/claims/)"
else
  fail ".gitignore .zskills/claims/" ".gitignore does not contain a .zskills entry"
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
