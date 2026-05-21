#!/bin/bash
# tests/test-fix-issues-claim-acquire-inline.sh — T2.1 + T2.4 from
# plans/fix-issues-claims.md Phase 2.
#
# Coverage:
#   - Race-lost path (locked exit-0 shape, no `continue` token).
#   - Acquire-success path (claim dir created, create-worktree.sh invoked).
#   - Filesystem-error path (rc=11 via EACCES; no silent continue).
#   - Hook backstop deny on missing claim.
#   - Hook positive on claim-present.
#   - Hook scope negative control (non-fix-issue prefix passes through).
#   - Hook coverage for ensure-worktree.sh wrapper (round 4b R4.1/DA4.3).
#   - Hook argv tokenization disambiguation (DA4.2):
#       * --purpose values literally containing `issue=99` must NOT
#         override the positional slug.
#       * --branch-name MUST override --prefix-derived branch.
#   - T2.4 — worktree-add failure release (W2.5.5 simplified).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAIM_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"
HOOK_SH="$REPO_ROOT/hooks/block-fix-issue-unclaimed.sh"
SKILL_MD="$REPO_ROOT/skills/fix-issues/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

SCRATCH_ROOT="/tmp/test-fix-issues-claim-acquire-inline-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
}

# ── Fence-body extraction ────────────────────────────────────────────────
# The W2.2a locked-shape acquire body lives in SKILL.md. We run it as if
# the orchestrator had typed it. Extract it via a known anchor so changes
# to surrounding prose don't break the test.
#
# We rebuild the fence body by hand to guarantee the locked semantics; the
# test then independently asserts the SKILL.md source contains the right
# tokens (race-lost = exit 0, no bare `continue` within 10 lines).
fence_body() {
  cat <<'FENCE'
CLAIM_HELPER="__CLAIM_HELPER__"
bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" \
     --pipeline-id "$PIPELINE_ID" --sprint-id "$SPRINT_ID"
ACQ_RC=$?
if [ "$ACQ_RC" = 10 ]; then
  echo "fix-issues: claim race lost for issue $ISSUE_NUM" >&2
  exit 0
fi
if [ "$ACQ_RC" != 0 ]; then
  echo "fix-issues: claim acquire failed for issue $ISSUE_NUM (rc=$ACQ_RC); aborting sprint." >&2
  exit "$ACQ_RC"
fi
# At this point the acquire succeeded — simulate the create-worktree call.
"$MOCK_CREATE_WORKTREE_BIN" --prefix fix-issue --pipeline-id "$PIPELINE_ID" "$ISSUE_NUM"
FENCE
}

# Render the fence body with $CLAIM_HELPER substituted to the real path.
render_fence() {
  fence_body | sed "s|__CLAIM_HELPER__|$CLAIM_SH|"
}

echo "=== T2.1 + T2.4 inline-acquire and hook tests ==="

# ───────────────────────────────────────────────────────────────────────
# Test 1: race-lost path — pre-existing claim, fence exits 0, no
# create-worktree.sh invocation.
# ───────────────────────────────────────────────────────────────────────
t1_root="$SCRATCH_ROOT/t1"
make_repo "$t1_root"
mkdir -p "$t1_root/.zskills/claims/issue-42"
cat > "$t1_root/.zskills/claims/issue-42/claim.json" <<JSON
{"schema_version":1,"pipeline_id":"other-pipe","sprint_id":"other-sprint","issue":42,"started_at":"2026-05-21T00:00:00+00:00"}
JSON
t1_mock_log="$SCRATCH_ROOT/t1.mock.log"
t1_mock_bin="$SCRATCH_ROOT/t1.mock"
cat > "$t1_mock_bin" <<EOF
#!/bin/bash
echo "MOCK-CREATE-WORKTREE-INVOKED: \$*" >> "$t1_mock_log"
EOF
chmod +x "$t1_mock_bin"
: > "$t1_mock_log"
t1_script="$SCRATCH_ROOT/t1.sh"
{
  echo "ISSUE_NUM=42"
  echo "PIPELINE_ID=mine"
  echo "SPRINT_ID=mine-s"
  echo "MOCK_CREATE_WORKTREE_BIN=\"$t1_mock_bin\""
  render_fence
} > "$t1_script"
(cd "$t1_root" && bash "$t1_script") >/dev/null 2>&1
t1_rc=$?
t1_mock_lines=$(wc -l < "$t1_mock_log" 2>/dev/null || echo 0)
if [ "$t1_rc" -eq 0 ] && [ "$t1_mock_lines" -eq 0 ]; then
  pass "T2.1 race-lost: exit 0, no create-worktree.sh invocation (mock log empty)"
else
  fail "T2.1 race-lost" "rc=$t1_rc mock_lines=$t1_mock_lines (expected rc=0, mock_lines=0)"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 2: acquire-success path — no pre-existing claim, fence exits 0,
# claim dir created, create-worktree.sh IS invoked.
# ───────────────────────────────────────────────────────────────────────
t2_root="$SCRATCH_ROOT/t2"
make_repo "$t2_root"
t2_mock_log="$SCRATCH_ROOT/t2.mock.log"
t2_mock_bin="$SCRATCH_ROOT/t2.mock"
cat > "$t2_mock_bin" <<EOF
#!/bin/bash
echo "MOCK-CREATE-WORKTREE-INVOKED: \$*" >> "$t2_mock_log"
EOF
chmod +x "$t2_mock_bin"
: > "$t2_mock_log"
t2_script="$SCRATCH_ROOT/t2.sh"
{
  echo "ISSUE_NUM=42"
  echo "PIPELINE_ID=mine2"
  echo "SPRINT_ID=mine2-s"
  echo "MOCK_CREATE_WORKTREE_BIN=\"$t2_mock_bin\""
  render_fence
} > "$t2_script"
(cd "$t2_root" && bash "$t2_script") >/dev/null 2>&1
t2_rc=$?
t2_mock_lines=$(wc -l < "$t2_mock_log" 2>/dev/null || echo 0)
if [ "$t2_rc" -eq 0 ] && [ "$t2_mock_lines" -ge 1 ] && [ -d "$t2_root/.zskills/claims/issue-42" ]; then
  pass "T2.1 acquire-success: rc=0, claim dir created, create-worktree.sh invoked"
else
  fail "T2.1 acquire-success" "rc=$t2_rc mock_lines=$t2_mock_lines claim_dir_present=$([ -d "$t2_root/.zskills/claims/issue-42" ] && echo y || echo n)"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 3: filesystem-error path — chmod 0500 on .zskills so mkdir fails
# non-EEXIST. Fence must propagate exit 11.
# ───────────────────────────────────────────────────────────────────────
t3_root="$SCRATCH_ROOT/t3"
make_repo "$t3_root"
mkdir -p "$t3_root/.zskills"
chmod 0500 "$t3_root/.zskills"
t3_mock_log="$SCRATCH_ROOT/t3.mock.log"
t3_mock_bin="$SCRATCH_ROOT/t3.mock"
cat > "$t3_mock_bin" <<EOF
#!/bin/bash
echo "MOCK-CREATE-WORKTREE-INVOKED: \$*" >> "$t3_mock_log"
EOF
chmod +x "$t3_mock_bin"
: > "$t3_mock_log"
t3_script="$SCRATCH_ROOT/t3.sh"
{
  echo "ISSUE_NUM=42"
  echo "PIPELINE_ID=mine3"
  echo "SPRINT_ID=mine3-s"
  echo "MOCK_CREATE_WORKTREE_BIN=\"$t3_mock_bin\""
  render_fence
} > "$t3_script"
(cd "$t3_root" && bash "$t3_script") >/dev/null 2>&1
t3_rc=$?
chmod 0755 "$t3_root/.zskills"
t3_mock_lines=$(wc -l < "$t3_mock_log" 2>/dev/null || echo 0)
if [ "$t3_rc" -eq 11 ] && [ "$t3_mock_lines" -eq 0 ]; then
  pass "T2.1 filesystem-error: rc=11 propagated, no create-worktree.sh invocation"
else
  fail "T2.1 filesystem-error" "rc=$t3_rc mock_lines=$t3_mock_lines (expected rc=11, mock_lines=0)"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 4: SKILL.md shape lock — race-lost arm contains `exit 0` and NO
# bare `continue` within 10 lines of the acquire call.
# ───────────────────────────────────────────────────────────────────────
acquire_lines=$(grep -n 'claim-issue.sh.*acquire\|"\$CLAIM_HELPER" acquire' "$SKILL_MD" | grep -v 'rev-parse' | cut -d: -f1)
shape_ok=1
shape_reason=""
for line in $acquire_lines; do
  end=$((line + 12))
  window=$(sed -n "${line},${end}p" "$SKILL_MD")
  if ! grep -q 'exit 0' <<< "$window"; then
    shape_ok=0
    shape_reason="line $line: no exit 0 within 10 lines"
    break
  fi
  # Bare `continue` is forbidden in this window (no enclosing fenced loop).
  if grep -E '^\s*continue\b' <<< "$window" >/dev/null; then
    shape_ok=0
    shape_reason="line $line: bare \`continue\` found within 10 lines (forbidden — must be \`exit 0\`)"
    break
  fi
done
if [ -n "$acquire_lines" ] && [ "$shape_ok" -eq 1 ]; then
  pass "T2.1 shape-lock: SKILL.md acquire fences use exit 0, no bare continue (R4.3/DA4.5)"
else
  fail "T2.1 shape-lock" "${shape_reason:-no acquire lines found in SKILL.md}"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 5: Hook backstop — no claim, deny envelope emitted.
# ───────────────────────────────────────────────────────────────────────
t5_root="$SCRATCH_ROOT/t5"
make_repo "$t5_root"
payload='{"tool_name":"Bash","tool_input":{"command":"bash create-worktree.sh --prefix fix-issue 42"}}'
out=$(echo "$payload" | (cd "$t5_root" && bash "$HOOK_SH"))
if echo "$out" | grep -q '"permissionDecision":"deny"' && echo "$out" | grep -q 'fix-issue-42'; then
  pass "T2.1 hook deny: no claim → deny envelope with issue 42"
else
  fail "T2.1 hook deny" "out: $out"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 6: Hook allow — pre-create the claim, hook exits 0 with no deny.
# ───────────────────────────────────────────────────────────────────────
mkdir -p "$t5_root/.zskills/claims/issue-42"
out=$(echo "$payload" | (cd "$t5_root" && bash "$HOOK_SH"))
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "T2.1 hook allow: claim present → exit 0, no envelope"
else
  fail "T2.1 hook allow" "rc=$rc out: $out"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 7: Hook scope negative control — --prefix cp (non-fix-issue) →
# allow without any claim-dir check.
# ───────────────────────────────────────────────────────────────────────
t7_root="$SCRATCH_ROOT/t7"
make_repo "$t7_root"
payload='{"tool_name":"Bash","tool_input":{"command":"bash create-worktree.sh --prefix cp my-plan"}}'
out=$(echo "$payload" | (cd "$t7_root" && bash "$HOOK_SH"))
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "T2.1 hook scope: --prefix cp → no-op allow"
else
  fail "T2.1 hook scope --prefix cp" "rc=$rc out: $out"
fi
# Also: --prefix do-pr → allow.
payload='{"tool_name":"Bash","tool_input":{"command":"bash create-worktree.sh --prefix do-pr my-slug"}}'
out=$(echo "$payload" | (cd "$t7_root" && bash "$HOOK_SH"))
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "T2.1 hook scope: --prefix do-pr → no-op allow"
else
  fail "T2.1 hook scope --prefix do-pr" "rc=$rc out: $out"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 8: ensure-worktree.sh wrapper coverage (R4.1/DA4.3).
# ───────────────────────────────────────────────────────────────────────
t8_root="$SCRATCH_ROOT/t8"
make_repo "$t8_root"
payload='{"tool_name":"Bash","tool_input":{"command":"bash ensure-worktree.sh --prefix fix-issue 42"}}'
out=$(echo "$payload" | (cd "$t8_root" && bash "$HOOK_SH"))
if echo "$out" | grep -q '"permissionDecision":"deny"' && echo "$out" | grep -q 'fix-issue-42'; then
  pass "T2.1 hook ensure-worktree.sh: no claim → deny"
else
  fail "T2.1 hook ensure-worktree.sh deny" "out: $out"
fi
mkdir -p "$t8_root/.zskills/claims/issue-42"
out=$(echo "$payload" | (cd "$t8_root" && bash "$HOOK_SH"))
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "T2.1 hook ensure-worktree.sh: claim present → allow"
else
  fail "T2.1 hook ensure-worktree.sh allow" "rc=$rc out: $out"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 9: Argv tokenization disambiguation (DA4.2).
# --purpose value literally contains `issue=99` but positional slug is 42.
# Claim is at issue-42; hook should ALLOW (slug wins).
# ───────────────────────────────────────────────────────────────────────
t9_root="$SCRATCH_ROOT/t9"
make_repo "$t9_root"
mkdir -p "$t9_root/.zskills/claims/issue-42"
payload='{"tool_name":"Bash","tool_input":{"command":"bash create-worktree.sh --prefix fix-issue --purpose \"fix-issues; issue=99\" --pipeline-id X 42"}}'
out=$(echo "$payload" | (cd "$t9_root" && bash "$HOOK_SH"))
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "T2.1 hook argv disambiguation: positional 42 wins over purpose=issue=99 (allow)"
else
  fail "T2.1 hook argv disambiguation (allow)" "rc=$rc out: $out"
fi
# Now without ANY claim — should deny with issue 42 (not 99).
t9b_root="$SCRATCH_ROOT/t9b"
make_repo "$t9b_root"
out=$(echo "$payload" | (cd "$t9b_root" && bash "$HOOK_SH"))
if echo "$out" | grep -q '"permissionDecision":"deny"' && \
   echo "$out" | grep -q 'fix-issue-42' && \
   ! echo "$out" | grep -q 'fix-issue-99'; then
  pass "T2.1 hook argv disambiguation: deny names issue 42, not 99"
else
  fail "T2.1 hook argv disambiguation (deny)" "out: $out"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 10: --branch-name override wins (create-worktree.sh:222-228 precedence).
# ───────────────────────────────────────────────────────────────────────
t10_root="$SCRATCH_ROOT/t10"
make_repo "$t10_root"
mkdir -p "$t10_root/.zskills/claims/issue-77"
payload='{"tool_name":"Bash","tool_input":{"command":"bash create-worktree.sh --prefix fix-issue --branch-name fix/issue-77 42"}}'
out=$(echo "$payload" | (cd "$t10_root" && bash "$HOOK_SH"))
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "T2.1 hook --branch-name override: claim issue-77 present → allow (slug 42 ignored)"
else
  fail "T2.1 hook --branch-name override (allow)" "rc=$rc out: $out"
fi
# Remove claim — deny should name issue 77.
rm -rf "$t10_root/.zskills/claims/issue-77"
out=$(echo "$payload" | (cd "$t10_root" && bash "$HOOK_SH"))
if echo "$out" | grep -q '"permissionDecision":"deny"' && \
   echo "$out" | grep -q 'fix-issue-77' && \
   ! echo "$out" | grep -q 'fix-issue-42'; then
  pass "T2.1 hook --branch-name override: deny names issue 77, not 42"
else
  fail "T2.1 hook --branch-name override (deny)" "out: $out"
fi

# ───────────────────────────────────────────────────────────────────────
# Test 11 (T2.4): worktree-add failure release (W2.5.5 simplification).
# Simulate the cherry-pick/direct fence with a failing create-worktree.sh.
# Assert: (a) just-acquired claim is released; (b) script exits with the
# create-worktree RC (sprint-abort preserved).
# ───────────────────────────────────────────────────────────────────────
t11_root="$SCRATCH_ROOT/t11"
make_repo "$t11_root"
# Pre-existing claim for issue 41 (an earlier sibling) — must NOT be touched.
mkdir -p "$t11_root/.zskills/claims/issue-41"
cat > "$t11_root/.zskills/claims/issue-41/claim.json" <<JSON
{"schema_version":1,"pipeline_id":"mine-t11","sprint_id":"mine-t11-s","issue":41,"started_at":"2026-05-21T00:00:00+00:00"}
JSON

t11_failing_mock="$SCRATCH_ROOT/t11.failing-mock"
cat > "$t11_failing_mock" <<'EOF'
#!/bin/bash
echo "MOCK: create-worktree failed" >&2
exit 7
EOF
chmod +x "$t11_failing_mock"

# Render the FULL W2.2a-style fence body including the wrapped failure
# path, then run it in $t11_root.
t11_script="$SCRATCH_ROOT/t11.sh"
cat > "$t11_script" <<EOF
ISSUE_NUM=42
PIPELINE_ID=mine-t11
SPRINT_ID=mine-t11-s
CLAIM_HELPER="$CLAIM_SH"
bash "\$CLAIM_HELPER" acquire "\$ISSUE_NUM" \\
     --pipeline-id "\$PIPELINE_ID" --sprint-id "\$SPRINT_ID"
ACQ_RC=\$?
if [ "\$ACQ_RC" = 10 ]; then exit 0; fi
if [ "\$ACQ_RC" != 0 ]; then exit "\$ACQ_RC"; fi

# Simulate the create-worktree.sh call failing.
"$t11_failing_mock" --prefix fix-issue "\$ISSUE_NUM"
RC=\$?
if [ "\$RC" -ne 0 ]; then
  bash "\$CLAIM_HELPER" release "\$ISSUE_NUM" --require-pipeline "\$PIPELINE_ID" || true
  echo "create-worktree failed (rc=\$RC)" >&2
  exit "\$RC"
fi
EOF

(cd "$t11_root" && bash "$t11_script") >/dev/null 2>&1
t11_rc=$?
t11_42_released=1
t11_41_kept=1
[ -d "$t11_root/.zskills/claims/issue-42" ] && t11_42_released=0
[ -d "$t11_root/.zskills/claims/issue-41" ] || t11_41_kept=0
if [ "$t11_rc" -eq 7 ] && [ "$t11_42_released" -eq 1 ] && [ "$t11_41_kept" -eq 1 ]; then
  pass "T2.4 worktree-add-failure release: rc=7 propagated; issue-42 released; issue-41 (earlier) preserved"
else
  fail "T2.4 worktree-add-failure release" "rc=$t11_rc 42_released=$t11_42_released 41_kept=$t11_41_kept"
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
