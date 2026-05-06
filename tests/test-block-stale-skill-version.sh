#!/usr/bin/env bash
# Tests for hooks/block-stale-skill-version.sh
# Run from repo root: bash tests/test-block-stale-skill-version.sh
#
# Coverage matrix (27 cases — see plans/SKILL_VERSION_PRETOOLUSE_HOOK.md
# Phase 2 spec for the canonical list and rationale):
#
#   C1  Non-Bash tool (Edit)              → allow, no stdout
#   C2  Non-git Bash (echo hello)         → allow, no stdout
#   C3  git status (not commit)           → allow, no stdout
#   C4  git commit, clean stage           → allow, no stdout
#   C5  git commit, stale skill staged    → DENY envelope, valid JSON,
#                                            permissionDecision=deny,
#                                            reason includes STOP:
#   C6  git commit -am                    → matches, script runs
#   C7  git commit --amend                → matches, script runs
#   C7a git -C /tmp/foo commit -m bar     → matches
#   C7b git -C /tmp/foo log               → does NOT match
#   C7c git -c user.email=x@y.z commit    → matches
#   C7d git --no-pager commit -m foo      → matches  (Round 2 N1)
#   C7e git --git-dir=/x commit           → matches
#   C7f git -P commit                     → matches
#   C7g git -C /tmp -c user.email=x commit→ matches  (mixed -C and -c)
#   C7h git --git-dir=/x --work-tree=/y …→ matches
#   C7i git --no-pager log                → does NOT match
#   C7j git -C /tmp diff                  → does NOT match
#   C8  FOO=bar git commit -m msg         → matches (env-var prefix)
#   C9  '   git commit' leading ws        → matches
#   C10 echo "git commit"                 → does NOT match
#   C10e bash -c 'git commit -m foo'      → does NOT match (carve-out;
#                                            Round 2 DA2-L-2 lock)
#   C11 git commit && git push            → matches (chained)
#   C12 Script missing (chmod -x)         → fail-open (allow)
#   C12a unset CLAUDE_PROJECT_DIR         → fail-open (allow); guards
#                                            ${X:-$PWD} against set -u
#   C13 Multi-line reason w/ " and \      → JSON parseable (python3)
#   C14 UTF-8 reason ('tëst skipped')     → byte-exact round-trip
#   C15 Reason w/ rare control bytes      → bytes stripped (POSIX [[:cntrl:]])

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-stale-skill-version.sh"
STAGE_CHECK="$REPO_ROOT/scripts/skill-version-stage-check.sh"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  ((FAIL_COUNT++))
}

skip() {
  printf '\033[33m  SKIP\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  ((SKIP_COUNT++))
}

echo "=== block-stale-skill-version.sh ==="

# Default the env var the hook expects.
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

# Helper — invoke the hook with a JSON envelope on stdin, capture stdout +
# exit. Stderr is captured separately and echoed back on failure for
# debugging.
run_hook() {
  local input="$1"
  local _stderr_file
  _stderr_file=$(mktemp)
  HOOK_OUT=$(printf '%s' "$input" | bash "$HOOK" 2>"$_stderr_file")
  HOOK_EXIT=$?
  HOOK_ERR=$(cat "$_stderr_file")
  rm -f "$_stderr_file"
}

# ──────────────────────────────────────────────────────────────
# Source the hook in a subshell so we can unit-test is_git_commit and
# json_escape directly without spinning up the full pipeline. The hook
# would normally read stdin and exit, so we extract just the function
# bodies via bash -c sourcing with a stubbed stdin.
# ──────────────────────────────────────────────────────────────
# Defines is_git_commit and json_escape in the current shell.
load_hook_funcs() {
  # Extract everything between the function header and the closing brace.
  # Simpler: source the file with a stub stdin that drops out via early
  # exit before the side-effecting code. We can't actually source because
  # the hook's set -u + control flow requires a stdin envelope.
  # Instead: extract the function bodies into a tmp file and source that.
  local tmp
  tmp=$(mktemp)
  awk '
    /^is_git_commit\(\) \{$/,/^\}$/ {print}
    /^json_escape\(\) \{$/,/^\}$/ {print}
  ' "$HOOK" > "$tmp"
  # shellcheck disable=SC1090
  . "$tmp"
  rm -f "$tmp"
}
load_hook_funcs

# ─────────────────── C1: Non-Bash tool ────────────────────────
run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x","old_string":"a","new_string":"b"}}'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass "C1: non-Bash tool → allow, no stdout"
else
  fail "C1: non-Bash tool" "exit=$HOOK_EXIT stdout=$HOOK_OUT"
fi

# ─────────────────── C2: Non-git Bash ─────────────────────────
run_hook '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass "C2: non-git Bash → allow, no stdout"
else
  fail "C2: non-git Bash" "exit=$HOOK_EXIT stdout=$HOOK_OUT"
fi

# ─────────────────── C3: git status ──────────────────────────
run_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
  pass "C3: git status → allow, no stdout"
else
  fail "C3: git status" "exit=$HOOK_EXIT stdout=$HOOK_OUT"
fi

# ──────────────────────────────────────────────────────────────
# Cases C4 / C5 / C6 / C7 / C7a / C7c / C7d / C7e / C7f / C7g / C7h /
# C8 / C9 / C11 — these match `git commit`, so they invoke the
# stage-check script. We use a sandbox temp dir as CLAUDE_PROJECT_DIR
# pointing at a fake script we control:
#   - clean-stage stub (rc=0)  → exit 0, empty stdout
#   - stale stub (rc=1, prints STOP message) → deny envelope
# ──────────────────────────────────────────────────────────────
SANDBOX=$(mktemp -d)
mkdir -p "$SANDBOX/scripts"

CLEAN_SCRIPT="$SANDBOX/scripts/skill-version-stage-check.sh"
cat > "$CLEAN_SCRIPT" <<'CLEAN_EOF'
#!/bin/bash
exit 0
CLEAN_EOF
chmod +x "$CLEAN_SCRIPT"

STALE_TEXT='STOP: skill version mismatch in staged commit:
  skills/foo: content changed (hash abc123 → def456) but staged metadata.version still 2026.05.01+abc123

To fix, for each affected skill <S>:
  hash=$(bash scripts/skill-content-hash.sh <S>)
  bash scripts/frontmatter-set.sh <S>/SKILL.md metadata.version "2026.05.03+$hash"
Then re-stage and re-run /commit.'

# Tests with the CLEAN script use this env var:
clean_env() {
  CLAUDE_PROJECT_DIR="$SANDBOX"
}

# ─────────────────── C4: git commit, clean stage ─────────────
(
  export CLAUDE_PROJECT_DIR="$SANDBOX"
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m hi"}}' | bash "$HOOK"
) > /tmp/c4.out 2>/tmp/c4.err
C4_EXIT=$?
C4_OUT=$(cat /tmp/c4.out)
if [ "$C4_EXIT" -eq 0 ] && [ -z "$C4_OUT" ]; then
  pass "C4: git commit, clean stage → allow, no stdout"
else
  fail "C4: git commit, clean stage" "exit=$C4_EXIT stdout=$C4_OUT err=$(cat /tmp/c4.err)"
fi
rm -f /tmp/c4.out /tmp/c4.err

# ─────────────────── C5: git commit, stale (DENY) ────────────
# Swap in a stale-printing stub.
STALE_SCRIPT="$SANDBOX/scripts/skill-version-stage-check.sh"
cat > "$STALE_SCRIPT" <<STALE_EOF
#!/bin/bash
cat >&2 <<'INNER_STOP'
$STALE_TEXT
INNER_STOP
exit 1
STALE_EOF
chmod +x "$STALE_SCRIPT"

(
  export CLAUDE_PROJECT_DIR="$SANDBOX"
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m hi"}}' | bash "$HOOK"
) > /tmp/c5.out 2>/tmp/c5.err
C5_EXIT=$?
C5_OUT=$(cat /tmp/c5.out)
# Validate JSON structure with python3 if available; assert deny + STOP.
C5_OK=1
if [ "$C5_EXIT" -ne 0 ]; then C5_OK=0; fi
[[ "$C5_OUT" == *'"permissionDecision":"deny"'* ]] || C5_OK=0
[[ "$C5_OUT" == *'STOP:'* ]] || C5_OK=0
if command -v python3 >/dev/null; then
  python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$C5_OUT" || C5_OK=0
fi
if [ "$C5_OK" -eq 1 ]; then
  pass "C5: git commit, stale stage → DENY envelope, valid JSON, includes STOP:"
else
  fail "C5: git commit, stale stage" "exit=$C5_EXIT stdout=$C5_OUT err=$(cat /tmp/c5.err)"
fi
rm -f /tmp/c5.out /tmp/c5.err

# Restore CLEAN script for the rest of the matching cases.
cp "$SANDBOX/scripts/skill-version-stage-check.sh" "$SANDBOX/scripts/skill-version-stage-check.sh.stale"
cat > "$SANDBOX/scripts/skill-version-stage-check.sh" <<'CLEAN_EOF'
#!/bin/bash
exit 0
CLEAN_EOF
chmod +x "$SANDBOX/scripts/skill-version-stage-check.sh"

# Helper: assert hook MATCHES (i.e., script ran; clean stub returns 0 → allow).
# We validate matching via is_git_commit directly to disambiguate "matched
# and script said clean" from "did not match at all".
assert_match() {
  local label="$1" cmd="$2"
  if is_git_commit "$cmd"; then
    pass "$label: is_git_commit('$cmd') → match"
  else
    fail "$label: should match" "is_git_commit returned 1 for: $cmd"
  fi
}

assert_no_match() {
  local label="$1" cmd="$2"
  if ! is_git_commit "$cmd"; then
    pass "$label: is_git_commit('$cmd') → no match"
  else
    fail "$label: should NOT match" "is_git_commit returned 0 for: $cmd"
  fi
}

# ─────────────────── C6 .. C11 — match assertions ────────────
assert_match    "C6"   "git commit -am 'wip'"
assert_match    "C7"   "git commit --amend"
assert_match    "C7a"  "git -C /tmp/foo commit -m bar"
assert_no_match "C7b"  "git -C /tmp/foo log"
assert_match    "C7c"  "git -c user.email=x@y.z commit -m msg"
assert_match    "C7d"  "git --no-pager commit -m foo"
assert_match    "C7e"  "git --git-dir=/x commit"
assert_match    "C7f"  "git -P commit"
assert_match    "C7g"  "git -C /tmp -c user.email=x commit"
assert_match    "C7h"  "git --git-dir=/x --work-tree=/y commit -m msg"
assert_no_match "C7i"  "git --no-pager log"
assert_no_match "C7j"  "git -C /tmp diff"
assert_match    "C8"   "FOO=bar git commit -m msg"
assert_match    "C9"   "   git commit"
assert_no_match "C10"  'echo "git commit"'
assert_no_match "C10e" "bash -c 'git commit -m foo'"
assert_match    "C11"  "git commit && git push"

# ─────────────────── C12: Script missing → fail-open ─────────
EMPTY_SANDBOX=$(mktemp -d)
mkdir -p "$EMPTY_SANDBOX/scripts"
# No script written — [ -x ] returns false → fail-open.
(
  export CLAUDE_PROJECT_DIR="$EMPTY_SANDBOX"
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m hi"}}' | bash "$HOOK"
) > /tmp/c12.out 2>/tmp/c12.err
C12_EXIT=$?
C12_OUT=$(cat /tmp/c12.out)
if [ "$C12_EXIT" -eq 0 ] && [ -z "$C12_OUT" ]; then
  pass "C12: stage-check script missing → fail-open (allow)"
else
  fail "C12: missing script should fail-open" "exit=$C12_EXIT stdout=$C12_OUT err=$(cat /tmp/c12.err)"
fi
rm -f /tmp/c12.out /tmp/c12.err
rm -rf "$EMPTY_SANDBOX"

# ─────────────────── C12a: unset CLAUDE_PROJECT_DIR ──────────
# Use env -i bash to ensure CLAUDE_PROJECT_DIR is genuinely unset; the
# ${X:-$PWD} fallback should resolve to a path where stage-check is absent
# → fail-open. Critically, this also asserts set -u doesn't crash.
C12A_OUT=$(env -i HOME="$HOME" PATH="$PATH" bash -c "cd /tmp && printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m hi\"}}' | bash \"$HOOK\"" 2>/tmp/c12a.err)
C12A_EXIT=$?
if [ "$C12A_EXIT" -eq 0 ] && [ -z "$C12A_OUT" ]; then
  pass "C12a: unset CLAUDE_PROJECT_DIR → fail-open (no set -u crash)"
else
  fail "C12a: unset env should fail-open" "exit=$C12A_EXIT stdout=$C12A_OUT err=$(cat /tmp/c12a.err)"
fi
rm -f /tmp/c12a.err

# ─────────────────── C13: Multi-line reason w/ " and \ ───────
# Drive json_escape directly with awkward content; check the resulting
# deny envelope parses as JSON.
if command -v python3 >/dev/null; then
  C13_INPUT=$'STOP: trouble.\nLine with "double quotes" and \\ backslash and a tab\there.\nAnother line.'
  C13_REASON=$(json_escape "$C13_INPUT")
  C13_ENVELOPE=$(printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$C13_REASON")
  if python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$C13_ENVELOPE" 2>/dev/null; then
    pass "C13: multi-line reason w/ \" and \\ → valid JSON envelope"
  else
    fail "C13: multi-line reason should round-trip" "envelope=$C13_ENVELOPE"
  fi
else
  skip "C13: multi-line reason JSON validation" "python3 not available"
fi

# ─────────────────── C14: UTF-8 round-trip ───────────────────
if command -v python3 >/dev/null; then
  C14_INPUT=$'tëst skipped — résumé naïve'
  C14_REASON=$(json_escape "$C14_INPUT")
  C14_ENVELOPE=$(printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$C14_REASON")
  C14_DECODED=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecisionReason"], end="")' <<< "$C14_ENVELOPE" 2>/dev/null)
  if [ "$C14_DECODED" = "$C14_INPUT" ]; then
    pass "C14: UTF-8 reason → byte-exact round-trip through json_escape"
  else
    fail "C14: UTF-8 round-trip mismatch" "input=$C14_INPUT decoded=$C14_DECODED"
  fi
else
  skip "C14: UTF-8 round-trip" "python3 not available"
fi

# ─────────────────── C15: Control-byte strip ─────────────────
if command -v python3 >/dev/null; then
  C15_INPUT=$'a\x01\x02\x07\x0bb'
  C15_REASON=$(json_escape "$C15_INPUT")
  C15_ENVELOPE=$(printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$C15_REASON")
  C15_DECODED=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecisionReason"], end="")' <<< "$C15_ENVELOPE" 2>/dev/null)
  if [ "$C15_DECODED" = "ab" ]; then
    pass "C15: control bytes 0x01/0x02/0x07/0x0b stripped → 'ab'"
  else
    fail "C15: control bytes not fully stripped" "decoded=$(printf '%s' "$C15_DECODED" | xxd)"
  fi
else
  skip "C15: control-byte strip" "python3 not available"
fi

# Cleanup sandbox.
rm -rf "$SANDBOX"

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
