#!/bin/bash
# tests/test-canary-failures.sh — regression suite for silent-failure catches.
#
# Each section asserts loud-failure behavior for one enforcing layer
# (hook / script / skill prompt). Run standalone or via tests/run-all.sh.

set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
FIXTURES="$REPO_ROOT/tests/fixtures/canary"
PASS_COUNT=0
FAIL_COUNT=0
FIXTURE_DIRS=()

cleanup_fixtures() {
  if [ "${#FIXTURE_DIRS[@]}" -eq 0 ]; then return; fi
  local d
  for d in "${FIXTURE_DIRS[@]}"; do
    [ -n "$d" ] && [ -d "$d" ] && chmod -R u+w "$d" 2>/dev/null
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup_fixtures EXIT

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Hook helper: construct JSON on stdin, assert deny + substring
expect_deny_substring() {
  local label="$1" cmd="$2" want="$3" hook="$4"
  local json result
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  result=$(printf '%s' "$json" | bash "$hook" 2>/dev/null) || true
  if [[ "$result" == *'"permissionDecision":"deny"'* && "$result" == *"$want"* ]]; then
    pass "$label"
  else
    fail "$label — want deny with '$want', got: $result"
  fi
}

expect_allow() {
  local label="$1" cmd="$2" hook="$3"
  local json result
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  result=$(printf '%s' "$json" | bash "$hook" 2>/dev/null) || true
  if [[ -z "$result" ]]; then
    pass "$label"
  else
    fail "$label — expected empty stdout, got: $result"
  fi
}

# Script helper: run a command, assert rc + stderr substring
expect_script_exit() {
  local label="$1" want_rc="$2" want_stderr="$3"
  shift 3
  local out rc
  out=$("$@" 2>&1) || rc=$?
  rc=${rc:-0}
  if [ "$rc" -eq "$want_rc" ] && [[ "$out" == *"$want_stderr"* ]]; then
    pass "$label"
  else
    fail "$label — rc=$rc want=$want_rc; '$want_stderr' substring? $out"
  fi
}

# Fixture helper: throwaway git repo, auto-cleanup
setup_fixture_repo() {
  local tmp
  tmp=$(mktemp -d)
  FIXTURE_DIRS+=("$tmp")
  git -C "$tmp" init -q
  git -C "$tmp" config user.email "canary@test.local"
  git -C "$tmp" config user.name "canary"
  git -C "$tmp" commit --allow-empty -q -m "init"
  echo "$tmp"
}

setup_bare_origin() {
  local tmp
  tmp=$(mktemp -d)
  FIXTURE_DIRS+=("$tmp")
  git init -q --bare "$tmp"
  echo "$tmp"
}

mkdir -p "$FIXTURES"

# --- test sections appended by each phase ---

# (Phase 1 adds: stash)
# (Phase 2 adds: land-phase)
# (Phase 3 adds: invariants)
# (Phase 4 adds: block-agents)
# (Phase 5 adds: commit-reviewer)

HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"

section "Stash writes denied (6 cases)"
STASH_WRITE_DENY="BLOCKED: git-stash write subcommand forbidden"
STASH_DESTRUCTIVE_DENY="BLOCKED: git stash drop/clear destroys stashed work permanently"
expect_deny_substring "git stash"              "git stash"              "$STASH_WRITE_DENY"       "$HOOK"
expect_deny_substring "git stash -u"           "git stash -u"           "$STASH_WRITE_DENY"       "$HOOK"
expect_deny_substring 'git stash save "msg"'   'git stash save "msg"'   "$STASH_WRITE_DENY"       "$HOOK"
expect_deny_substring 'git stash push -m "msg"' 'git stash push -m "msg"' "$STASH_WRITE_DENY"     "$HOOK"
expect_deny_substring "git stash drop"         "git stash drop"         "$STASH_DESTRUCTIVE_DENY" "$HOOK"
expect_deny_substring "git stash clear"        "git stash clear"        "$STASH_DESTRUCTIVE_DENY" "$HOOK"

section "Stash reads allowed (7 cases)"
expect_allow "git stash apply"         "git stash apply"         "$HOOK"
expect_allow "git stash list"          "git stash list"          "$HOOK"
expect_allow "git stash show"          "git stash show"          "$HOOK"
expect_allow "git stash pop"           "git stash pop"           "$HOOK"
expect_allow "git stash create"        "git stash create"        "$HOOK"
expect_allow "git stash store abc123"  "git stash store abc123"  "$HOOK"
expect_allow "git stash branch foo"    "git stash branch foo"    "$HOOK"

section "Stash overmatch prevention (5 cases)"
expect_allow 'commit message mentions git stash' 'git commit -m "refactor: remove old git stash logic"' "$HOOK"
expect_allow 'echo "git stash push"'   'echo "git stash push"'   "$HOOK"
expect_allow 'grep "git stash" file'   'grep "git stash" somefile.txt' "$HOOK"
expect_allow "printf 'git stash save\\n'" "printf 'git stash save\\n'" "$HOOK"
expect_allow 'heredoc containing git stash -u' "$(printf 'cat <<EOF\ngit stash -u\nEOF')" "$HOOK"

echo
echo "Canary failure-injection: $PASS_COUNT passed, $FAIL_COUNT failed"
exit $((FAIL_COUNT > 0))
