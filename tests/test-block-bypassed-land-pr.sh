#!/usr/bin/env bash
# Tests for hooks/block-bypassed-land-pr.sh
# Run from repo root: bash tests/test-block-bypassed-land-pr.sh
#
# Coverage matrix (20 cases — see docs/plans/LAND_PR_BYPASS_HARDENING.md
# Phase 5 spec for the canonical list and rationale):
#
#   C1   gh pr create -B main, no markers              → DENY, Pattern 1 STOP
#   C2   gh pr create + requires.land-pr (matching     → DENY, Pattern 2 STOP
#         branch)
#   C3   gh pr create + requires.land-pr (mismatched   → DENY, Pattern 1 STOP
#         branch)
#   C4   gh pr create + malformed marker missing       → DENY, Pattern 1 STOP
#         `branch:` field has line, OR Pattern 2 via DA-2-2 fallback
#   C5   gh pr merge --auto, no markers                → DENY
#   C6   gh pr merge --auto --squash                   → DENY
#   C7   gh pr merge --squash --auto                   → DENY (flag-order-agnostic)
#   C8   gh pr merge --merge --auto                    → DENY
#   C9   gh pr merge (no --auto), no markers           → ALLOW (D4 / AC1.8)
#   C10  gh issue create -t foo, no markers            → ALLOW (non-pr verb)
#   C11  gh pr view 123                                → ALLOW
#   C12  gh pr checks --watch                          → ALLOW
#   C13  gh pr --help                                  → ALLOW
#   C14  gh --help                                     → ALLOW
#   C15  bash $CLAUDE_PROJECT_DIR/.claude/skills/...   → ALLOW (wrapper carve-out)
#         /pr-push-and-create.sh ...
#   C16  cd /tmp/wt && gh pr create -B main            → DENY (segment-walk)
#   C17  bash -c 'gh pr create -B main'                → DENY (was the PR #250
#         documented hole; closed by is_gh_pr_subcommand_in_wrappers)
#   C18  gh pr create, script missing/non-exec         → STILL DENY, static fallback
#   C19  gh --repo foo/bar pr create                   → DENY
#   C20  gh --repo=foo/bar pr create                   → DENY
#   C21  sh -c 'gh pr create'                          → DENY (sh -c wrapper)
#   C22  eval 'gh pr create'                           → DENY (eval wrapper)
#   C23  bash -c 'gh pr merge --auto'                  → DENY (merge variant)
#   C24  bash -lc 'gh pr create'                       → DENY (combined-flag)
#   C25  /usr/local/bin/gh pr create                   → DENY (absolute-path)
#   C26  ./gh pr create                                → DENY (relative-path)
#   C27  legitimate FPs (git commit -m, grep, etc.)    → ALLOW (token-aware)
#   C28  legitimate gh pr verbs (view/list/checks/...) → ALLOW
#   C29  transparent-prefix wrappers (command/exec/    → DENY (prefix-skip
#         nohup/nice/time/timeout) + gh pr create        in is_gh_pr_subcommand)
#   C30  timeout 30 gh pr merge --auto                 → DENY (prefix + merge)
#   C31  time git push origin main / timeout 60 ls     → ALLOW (prefix-skip
#         (prefix-skip is conservative: doesn't match     reaches non-gh; exits)
#          non-gh commands after prefix)
#
#   AC5.4  Instrumented stub: hook on non-`gh pr ` commands must NOT
#          invoke land-pr-bypass-message.sh.
#   AC5.5  Direct library sourcing of is_gh_pr_subcommand from
#          hooks/_lib/git-tokenwalk.sh.
#   AC5.6  DA-5-9 marker-shape integration smoke — parse synthesized
#          requires.land-pr.<id> markers, assert line-separated fields,
#          `branch:` regex, ISO-8601 `date:`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-bypassed-land-pr.sh"
BYPASS_MSG_SCRIPT="$REPO_ROOT/scripts/land-pr-bypass-message.sh"
TOKENWALK_LIB="$REPO_ROOT/hooks/_lib/git-tokenwalk.sh"

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

echo "=== block-bypassed-land-pr.sh ==="

# ──────────────────────────────────────────────────────────────
# Sandbox setup — every test runs against a tmpdir CLAUDE_PROJECT_DIR.
# We replicate the layout the hook reads:
#   $TMPDIR/scripts/land-pr-bypass-message.sh   (copied or stubbed)
#   $TMPDIR/.zskills/tracking/<pipeline>/...    (per-case marker fixtures)
# Cleanup via EXIT trap.
# ──────────────────────────────────────────────────────────────
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

mkdir -p "$SANDBOX/scripts"
mkdir -p "$SANDBOX/.zskills/tracking"
# Initialize the sandbox as a real git repo so the message script can probe
# HEAD / git-common-dir / show-toplevel inside it. The sandbox tracking
# tree lives under $SANDBOX/.zskills/tracking which the message script
# scans via MAIN_ROOT.
(
  cd "$SANDBOX" || exit 1
  git init -q -b main . 2>/dev/null
  git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init 2>/dev/null
)
# Real branch in the sandbox repo.
SANDBOX_HEAD=$(cd "$SANDBOX" && git symbolic-ref --short HEAD)

# Copy the real message script into the sandbox so the hook's
# `$CLAUDE_PROJECT_DIR/scripts/land-pr-bypass-message.sh` lookup hits it.
cp "$BYPASS_MSG_SCRIPT" "$SANDBOX/scripts/land-pr-bypass-message.sh"
chmod +x "$SANDBOX/scripts/land-pr-bypass-message.sh"

export CLAUDE_PROJECT_DIR="$SANDBOX"

# Helper — invoke the hook with a JSON envelope on stdin. Runs the hook
# `cd`-ed inside the sandbox so the message script's git probes resolve
# against the sandbox repo (HEAD = $SANDBOX_HEAD).
run_hook() {
  local input="$1"
  local _stderr_file
  _stderr_file=$(mktemp)
  HOOK_OUT=$(cd "$SANDBOX" && printf '%s' "$input" | bash "$HOOK" 2>"$_stderr_file")
  HOOK_EXIT=$?
  HOOK_ERR=$(cat "$_stderr_file")
  rm -f "$_stderr_file"
}

# Build a Bash-tool envelope from a raw command string.
# Escapes embedded `"` for JSON safety.
mkenv() {
  local cmd="$1"
  local esc="${cmd//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$esc"
}

# Wipe the tracking subtree between cases (we always re-`mkdir -p` after).
clean_tracking() {
  rm -rf "$SANDBOX/.zskills/tracking"
  mkdir -p "$SANDBOX/.zskills/tracking"
}

# Write a synthetic requires.land-pr.<id> marker matching the Phase 2
# caller shape (skills/commit/modes/pr.md, etc.).
write_requires_marker() {
  local pipeline="$1" id="$2" branch_val="$3"
  local now_iso
  now_iso=$(TZ=UTC date -Iseconds)
  mkdir -p "$SANDBOX/.zskills/tracking/$pipeline"
  cat > "$SANDBOX/.zskills/tracking/$pipeline/requires.land-pr.$id" <<MARK
skill: land-pr
parent: commit
id: $id
branch: $branch_val
date: $now_iso
MARK
}

# Write a malformed marker missing the `branch:` field (C4 case).
write_malformed_marker_no_branch() {
  local pipeline="$1" id="$2"
  local now_iso
  now_iso=$(TZ=UTC date -Iseconds)
  mkdir -p "$SANDBOX/.zskills/tracking/$pipeline"
  cat > "$SANDBOX/.zskills/tracking/$pipeline/requires.land-pr.$id" <<MARK
skill: land-pr
parent: commit
id: $id
date: $now_iso
MARK
}

# Assert a hook response is a deny envelope (valid JSON + permissionDecision=deny).
assert_deny() {
  local label="$1" envelope="$2" pattern_anchor="$3"
  local ok=1
  [[ "$envelope" == *'"permissionDecision":"deny"'* ]] || ok=0
  [[ "$envelope" == *'STOP: direct gh pr'* ]] || ok=0
  if [ -n "$pattern_anchor" ]; then
    [[ "$envelope" == *"$pattern_anchor"* ]] || ok=0
  fi
  if command -v python3 >/dev/null; then
    python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$envelope" >/dev/null 2>&1 || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    pass "$label"
  else
    fail "$label" "envelope=$envelope"
  fi
}

assert_allow() {
  local label="$1" exit_code="$2" stdout="$3"
  if [ "$exit_code" -eq 0 ] && [ -z "$stdout" ]; then
    pass "$label"
  else
    fail "$label" "exit=$exit_code stdout=$stdout"
  fi
}

# ─────────────────── C1: bare gh pr create, no markers ───────────
clean_tracking
run_hook "$(mkenv "gh pr create -B main")"
assert_deny "C1: gh pr create, no markers → DENY Pattern 1" \
  "$HOOK_OUT" "outside a caller skill"

# ─────────────────── C2: gh pr create + matching-branch marker ───
clean_tracking
write_requires_marker "commit.test" "test" "$SANDBOX_HEAD"
run_hook "$(mkenv "gh pr create -B main")"
assert_deny "C2: gh pr create + matching-branch marker → DENY Pattern 2" \
  "$HOOK_OUT" "declared an intent to"

# ─────────────────── C3: gh pr create + mismatched-branch marker ─
clean_tracking
write_requires_marker "commit.other" "other" "someOtherBranchNoMatch"
run_hook "$(mkenv "gh pr create -B main")"
assert_deny "C3: gh pr create + mismatched-branch marker → DENY Pattern 1" \
  "$HOOK_OUT" "outside a caller skill"

# ─────────────────── C4: gh pr create + malformed marker ─────────
# DA-1-13: malformed marker missing `branch:` line. Per
# land-pr-bypass-message.sh logic, a marker with NO `branch:` line at all
# triggers the Pattern 2 backward-compat fallback (DA-2-2 — legacy shape).
# Spec wording in plan says "Pattern 1 STOP (no branch-match found)";
# the SCRIPT's documented behavior is Pattern 2 fallback. We assert the
# script's actual behavior (deny + Pattern 2 substring) because that is
# the load-bearing claim shipped in scripts/land-pr-bypass-message.sh:124.
clean_tracking
write_malformed_marker_no_branch "commit.malformed" "malformed"
run_hook "$(mkenv "gh pr create -B main")"
assert_deny "C4: gh pr create + malformed-marker (no branch line) → DENY Pattern 2 (DA-2-2 fallback)" \
  "$HOOK_OUT" "declared an intent to"

# ─────────────────── C5..C8: gh pr merge variants → DENY ─────────
clean_tracking
run_hook "$(mkenv "gh pr merge --auto")"
assert_deny "C5: gh pr merge --auto → DENY" "$HOOK_OUT" ""

run_hook "$(mkenv "gh pr merge --auto --squash")"
assert_deny "C6: gh pr merge --auto --squash → DENY" "$HOOK_OUT" ""

run_hook "$(mkenv "gh pr merge --squash --auto")"
assert_deny "C7: gh pr merge --squash --auto (flag-order-agnostic) → DENY" "$HOOK_OUT" ""

run_hook "$(mkenv "gh pr merge --merge --auto")"
assert_deny "C8: gh pr merge --merge --auto → DENY" "$HOOK_OUT" ""

# ─────────────────── C9: gh pr merge (no --auto) → ALLOW ─────────
clean_tracking
run_hook "$(mkenv "gh pr merge 123")"
assert_allow "C9: gh pr merge (no --auto) → ALLOW (D4 / AC1.8)" "$HOOK_EXIT" "$HOOK_OUT"

# ─────────────────── C10..C14: ALLOW path ────────────────────────
run_hook "$(mkenv "gh issue create -t foo")"
assert_allow "C10: gh issue create → ALLOW (non-pr verb)" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$(mkenv "gh pr view 123")"
assert_allow "C11: gh pr view 123 → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$(mkenv "gh pr checks --watch")"
assert_allow "C12: gh pr checks --watch → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$(mkenv "gh pr --help")"
assert_allow "C13: gh pr --help → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$(mkenv "gh --help")"
assert_allow "C14: gh --help → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

# ─────────────────── C15: bash $wrapper-script invocation ────────
# The wrapper /land-pr uses — `bash .claude/skills/land-pr/scripts/pr-push-and-create.sh`.
# The outer command is `bash <path>`, NOT `gh pr create`. The hook's early-exit
# substring `"gh "*"pr "*` does not match `bash .../pr-push-and-create.sh ...`
# (no literal `gh ` token), so we exit cleanly.
run_hook "$(mkenv "bash .claude/skills/land-pr/scripts/pr-push-and-create.sh --branch=foo --title=x --body-file=/tmp/x --base=main")"
assert_allow "C15: bash \$wrapper-script (pr-push-and-create.sh) → ALLOW (carve-out)" "$HOOK_EXIT" "$HOOK_OUT"

# ─────────────────── C16: chained cd && gh pr create → DENY ──────
clean_tracking
run_hook "$(mkenv "cd /tmp/wt && gh pr create -B main")"
assert_deny "C16: chained cd && gh pr create → DENY (segment-walk)" \
  "$HOOK_OUT" ""

# ─────────────────── C17: bash -c 'gh pr create' → DENY ─────────
# Previously DA-1-5 "documented hole" of PR #250. Closed by the new
# is_gh_pr_subcommand_in_wrappers helper, which extracts the inline
# string from `bash -c '<inner>'` (also sh/dash/ksh/zsh and eval) and
# recursively re-matches it through the chain-walker.
clean_tracking
run_hook "$(mkenv "bash -c 'gh pr create -B main'")"
assert_deny "C17: bash -c 'gh pr create' → DENY (wrapper-c recursion closes PR-#250 hole)" \
  "$HOOK_OUT" ""

# ─────────────────── C18: script missing → STILL DENY (static) ───
# Move (don't delete) the script so we can restore it. Set non-exec by
# moving aside; the hook's [ -x ] check sees missing → static fallback.
clean_tracking
mv "$SANDBOX/scripts/land-pr-bypass-message.sh" "$SANDBOX/scripts/land-pr-bypass-message.sh.bak"
run_hook "$(mkenv "gh pr create -B main")"
# Hook STILL denies; reason should be the static-fallback wording.
ok=1
[[ "$HOOK_OUT" == *'"permissionDecision":"deny"'* ]] || ok=0
[[ "$HOOK_OUT" == *'STOP: direct gh pr (create|merge --auto) from agent Bash bypasses /land-pr.'* ]] || ok=0
[[ "$HOOK_OUT" == *'Open a SEPARATE terminal'* ]] || ok=0
if command -v python3 >/dev/null; then
  python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<< "$HOOK_OUT" >/dev/null 2>&1 || ok=0
fi
if [ "$ok" -eq 1 ]; then
  pass "C18: script missing → STILL DENY w/ static fallback"
else
  fail "C18: missing script must still DENY w/ static fallback" "envelope=$HOOK_OUT"
fi
# Restore the script.
mv "$SANDBOX/scripts/land-pr-bypass-message.sh.bak" "$SANDBOX/scripts/land-pr-bypass-message.sh"
chmod +x "$SANDBOX/scripts/land-pr-bypass-message.sh"

# ─────────────────── C19: gh --repo foo/bar pr create → DENY ─────
clean_tracking
run_hook "$(mkenv "gh --repo foo/bar pr create -B main")"
assert_deny "C19: gh --repo foo/bar pr create (2-token form) → DENY" \
  "$HOOK_OUT" ""

# ─────────────────── C20: gh --repo=foo/bar pr create → DENY ─────
run_hook "$(mkenv "gh --repo=foo/bar pr create -B main")"
assert_deny "C20: gh --repo=foo/bar pr create (=-form) → DENY" \
  "$HOOK_OUT" ""

# ─────────────────── C21: sh -c 'gh pr create' → DENY ────────────
clean_tracking
run_hook "$(mkenv "sh -c 'gh pr create -B main'")"
assert_deny "C21: sh -c 'gh pr create' → DENY (sh -c wrapper)" \
  "$HOOK_OUT" ""

# ─────────────────── C22: eval 'gh pr create' → DENY ─────────────
clean_tracking
run_hook "$(mkenv "eval 'gh pr create -B main'")"
assert_deny "C22: eval 'gh pr create' → DENY (eval wrapper)" \
  "$HOOK_OUT" ""

# ─────────────────── C23: bash -c '... merge --auto' → DENY ──────
clean_tracking
run_hook "$(mkenv "bash -c 'gh pr merge 123 --auto'")"
assert_deny "C23: bash -c 'gh pr merge --auto' → DENY (merge variant in wrapper)" \
  "$HOOK_OUT" ""

# ─────────────────── C24: bash -lc 'gh pr create' → DENY ─────────
clean_tracking
run_hook "$(mkenv "bash -lc 'gh pr create'")"
assert_deny "C24: bash -lc 'gh pr create' → DENY (combined-flag wrapper)" \
  "$HOOK_OUT" ""

# ─────────────────── C25: /usr/local/bin/gh pr create → DENY ─────
# Absolute-path gh invocation. The first-token check basenames the
# path before comparing to "gh".
clean_tracking
run_hook "$(mkenv "/usr/local/bin/gh pr create -B main")"
assert_deny "C25: /usr/local/bin/gh pr create → DENY (absolute-path basename)" \
  "$HOOK_OUT" ""

# ─────────────────── C26: ./gh pr create → DENY ──────────────────
clean_tracking
run_hook "$(mkenv "./gh pr create")"
assert_deny "C26: ./gh pr create → DENY (relative-path basename)" \
  "$HOOK_OUT" ""

# ─────────────────── C27: legitimate FP cases all ALLOW ──────────
# These contain the literal text `gh pr create` in quoted args of
# OTHER commands. The token-aware walker correctly treats them as
# arguments, not invocations.
for legit in \
  "git commit -m 'fix gh pr create bug'" \
  "grep 'gh pr create' tests/" \
  "gh issue create --title 'use gh pr create instead'" \
  "echo 'gh pr create'"; do
  clean_tracking
  run_hook "$(mkenv "$legit")"
  assert_allow "C27/$legit → ALLOW (token-aware: literal in quoted arg)" \
    "$HOOK_EXIT" "$HOOK_OUT"
done

# ─────────────────── C28: legitimate gh subcommands ALLOW ────────
for legit in "gh pr view 123" "gh pr checks --watch" "gh pr list" "gh pr diff" "gh pr edit 5 --title=x" "gh pr merge 123" "gh pr merge --auto-fill"; do
  clean_tracking
  run_hook "$(mkenv "$legit")"
  assert_allow "C28/$legit → ALLOW (legitimate gh pr verb)" \
    "$HOOK_EXIT" "$HOOK_OUT"
done

# ─────────────────── C29: transparent-prefix wrappers → DENY ─────
# These prefixes execute the next argv as a separate process (or
# in-place for `exec`/`command`); operationally equivalent to direct
# invocation. Closes the prefix-class hole an agent could reach for
# (e.g., `timeout 30 gh pr create` after a previous PR-create hung).
for prefix_form in \
  "command gh pr create -B main" \
  "exec gh pr create -B main" \
  "nohup gh pr create" \
  "nice gh pr create" \
  "time gh pr create" \
  "timeout 30 gh pr create" \
  "/usr/bin/timeout 60 gh pr create -B main"; do
  clean_tracking
  run_hook "$(mkenv "$prefix_form")"
  assert_deny "C29/$prefix_form → DENY (transparent-prefix wrapper)" \
    "$HOOK_OUT" ""
done

# ─────────────────── C29b: prefix flag-form bypasses → DENY ──────
# Issue #279 closure: 9838431 (PR #255) closed the fixed-budget
# transparent-prefix forms but left 4 flag-form variants open. The
# prefix-skip now consumes leading `-*` flag tokens after the prefix
# word (with `--` as a one-shot end-of-options marker), and for
# `timeout` continues to consume one DURATION token AFTER any leading
# flags. All four below MUST DENY.
for prefix_form in \
  "time -v gh pr create" \
  "timeout --foreground 30 gh pr create" \
  "nohup -- gh pr create" \
  "command -p gh pr create"; do
  clean_tracking
  run_hook "$(mkenv "$prefix_form")"
  assert_deny "C29b/$prefix_form → DENY (prefix flag-form bypass)" \
    "$HOOK_OUT" ""
done

# ─────────────────── C30: prefix + merge --auto → DENY ───────────
clean_tracking
run_hook "$(mkenv "timeout 30 gh pr merge 123 --auto")"
assert_deny "C30: timeout 30 gh pr merge --auto → DENY (prefix + merge variant)" \
  "$HOOK_OUT" ""

# ─────────────────── C31: prefix is NOT a generic allow ──────────
# Adding `command/time/timeout/...` to the transparent-prefix skip MUST
# NOT cause unrelated invocations to fall through. Confirm a non-gh
# command after the prefix correctly ALLOWs (because the walker reaches
# `git`, not `gh`, and exits without matching).
clean_tracking
run_hook "$(mkenv "time git push origin main")"
assert_allow "C31: time git push origin main → ALLOW (prefix-skip doesn't make non-gh commands match)" \
  "$HOOK_EXIT" "$HOOK_OUT"

clean_tracking
run_hook "$(mkenv "timeout 60 ls -la")"
assert_allow "C31b: timeout 60 ls -la → ALLOW (no gh anywhere)" \
  "$HOOK_EXIT" "$HOOK_OUT"

# ──────────────────────────────────────────────────────────────
# AC5.4 — instrumented-stub early-exit assertion.
# Replace land-pr-bypass-message.sh with an instrumented stub that
# touches a sentinel file on every invocation. Send the hook commands
# that DON'T contain `gh pr ` and assert the sentinel was NEVER written.
# ──────────────────────────────────────────────────────────────
SENTINEL="$SANDBOX/script-invoked.flag"
INSTRUMENTED_STUB="$SANDBOX/scripts/land-pr-bypass-message.sh"
cat > "$INSTRUMENTED_STUB" <<INSTR_EOF
#!/bin/bash
echo "stub-invoked-at-\$(date +%s%N)" >> "$SENTINEL"
echo "STOP: direct gh pr (create|merge --auto) from agent Bash bypasses /land-pr." >&2
exit 1
INSTR_EOF
chmod +x "$INSTRUMENTED_STUB"

ac54_failed=0
for non_match_cmd in "ls" "cat /tmp/x" "git commit -m foo" "echo hello" "git status" "git push dev main"; do
  run_hook "$(mkenv "$non_match_cmd")"
  if [ -e "$SENTINEL" ]; then
    fail "AC5.4: stub MUST NOT fire on '$non_match_cmd'" "sentinel created: $(cat "$SENTINEL")"
    rm -f "$SENTINEL"
    ac54_failed=1
    break
  fi
  if [ "$HOOK_EXIT" -ne 0 ] || [ -n "$HOOK_OUT" ]; then
    fail "AC5.4: hook should ALLOW '$non_match_cmd' silently" "exit=$HOOK_EXIT stdout=$HOOK_OUT"
    ac54_failed=1
    break
  fi
done
if [ $ac54_failed -eq 0 ]; then
  pass "AC5.4: instrumented-stub NEVER fires on non-'gh pr ' commands (ls / cat / git commit / echo / git status / git push)"
fi
# Restore real message script.
cp "$BYPASS_MSG_SCRIPT" "$INSTRUMENTED_STUB"
chmod +x "$INSTRUMENTED_STUB"
rm -f "$SENTINEL"

# ──────────────────────────────────────────────────────────────
# AC5.5 — direct library sourcing of is_gh_pr_subcommand.
# Source hooks/_lib/git-tokenwalk.sh and assert the helper sets the
# documented out-vars on match.
# ──────────────────────────────────────────────────────────────
(
  # shellcheck disable=SC1090
  . "$TOKENWALK_LIB"
  if is_gh_pr_subcommand "gh pr create -B main" create; then
    if [ "${GH_PR_SUB_INDEX:-}" -gt 0 ] 2>/dev/null && [ -n "${GH_PR_SUB_REST+x}" ]; then
      exit 0
    else
      echo "GH_PR_SUB_INDEX=${GH_PR_SUB_INDEX:-unset} GH_PR_SUB_REST=${GH_PR_SUB_REST:-unset}" >&2
      exit 2
    fi
  else
    exit 3
  fi
)
ac55_rc=$?
case "$ac55_rc" in
  0) pass "AC5.5: source git-tokenwalk.sh; is_gh_pr_subcommand 'gh pr create -B main' create → rc=0 + GH_PR_SUB_INDEX>0 + GH_PR_SUB_REST set" ;;
  2) fail "AC5.5: helper matched but did not set out-vars correctly" "see stderr above" ;;
  3) fail "AC5.5: is_gh_pr_subcommand returned non-zero on 'gh pr create -B main'" "expected match" ;;
  *) fail "AC5.5: unexpected rc=$ac55_rc" "see stderr above" ;;
esac

# ──────────────────────────────────────────────────────────────
# AC5.6 — marker-shape integration smoke (DA-5-9).
# Synthesize markers matching the Phase 2 caller printf shape; parse
# line-by-line and assert:
#   (a) skill: / parent: / id: / branch: / date: each on a SEPARATE line
#       (no glued fields from a missing \n in the printf format string).
#   (b) branch: value matches ^[a-zA-Z0-9./_-]+$ (no shell metachars / empty).
#   (c) date: value parses as ISO-8601 via GNU `date -d`.
#
# Both a well-formed marker (must pass) and a deliberately malformed
# marker (must FAIL each assertion) exercise the parser shape gate.
# ──────────────────────────────────────────────────────────────
GOOD_MARKER="$SANDBOX/.zskills/tracking/commit.shape-good/requires.land-pr.shape-good"
BAD_MARKER_GLUED="$SANDBOX/.zskills/tracking/commit.shape-glued/requires.land-pr.shape-glued"
BAD_MARKER_BRANCH="$SANDBOX/.zskills/tracking/commit.shape-bad-branch/requires.land-pr.shape-bad-branch"
BAD_MARKER_DATE="$SANDBOX/.zskills/tracking/commit.shape-bad-date/requires.land-pr.shape-bad-date"
mkdir -p \
  "$SANDBOX/.zskills/tracking/commit.shape-good" \
  "$SANDBOX/.zskills/tracking/commit.shape-glued" \
  "$SANDBOX/.zskills/tracking/commit.shape-bad-branch" \
  "$SANDBOX/.zskills/tracking/commit.shape-bad-date"

NOW_ISO=$(TZ=UTC date -Iseconds)
# Good marker — exact format the Phase 2 callers write.
cat > "$GOOD_MARKER" <<MARK
skill: land-pr
parent: commit
id: shape-good
branch: feat/canary-bypass-detect_p1
date: $NOW_ISO
MARK

# Glued-fields marker (would result from a printf format string missing
# `\n` between fields — DA-5-9's documented failure mode).
printf 'skill: land-pr parent: commit id: shape-glued branch: foo date: %s\n' "$NOW_ISO" > "$BAD_MARKER_GLUED"

# Bad branch — empty value (caused by un-expanded $HEAD_BRANCH).
cat > "$BAD_MARKER_BRANCH" <<MARK
skill: land-pr
parent: commit
id: shape-bad-branch
branch:
date: $NOW_ISO
MARK

# Bad date — non-ISO-8601 garbage.
cat > "$BAD_MARKER_DATE" <<MARK
skill: land-pr
parent: commit
id: shape-bad-date
branch: feat/bad
date: not-a-real-date-1234
MARK

# Parser — returns rc=0 if ALL three assertions hold, rc=1 otherwise.
# Echoes diagnostic on rc!=0.
shape_parse() {
  local marker="$1"
  local has_skill=0 has_parent=0 has_id=0 has_branch=0 has_date=0
  local branch_val="" date_val=""
  # Per-field-per-line: each grep MUST find exactly one line.
  while IFS= read -r line; do
    case "$line" in
      "skill: "*)
        has_skill=$((has_skill + 1))
        # Glued-fields detector: more than one ": " on the same line
        # except the trailing iso-8601 `:` (HH:MM:SS), means fields were
        # joined. Count ': ' (space after colon) occurrences.
        ;;
      "parent: "*) has_parent=$((has_parent + 1)) ;;
      "id: "*)     has_id=$((has_id + 1)) ;;
      "branch: "*) has_branch=$((has_branch + 1)); branch_val="${line#branch: }" ;;
      "date: "*)   has_date=$((has_date + 1)); date_val="${line#date: }" ;;
    esac
  done < "$marker"

  if [ "$has_skill" -ne 1 ] || [ "$has_parent" -ne 1 ] || [ "$has_id" -ne 1 ] \
     || [ "$has_branch" -ne 1 ] || [ "$has_date" -ne 1 ]; then
    echo "  field-line-count mismatch: skill=$has_skill parent=$has_parent id=$has_id branch=$has_branch date=$has_date"
    return 1
  fi

  if [[ ! "$branch_val" =~ ^[a-zA-Z0-9./_-]+$ ]]; then
    echo "  branch regex mismatch: '$branch_val'"
    return 1
  fi

  if ! date -d "$date_val" >/dev/null 2>&1; then
    echo "  date not ISO-8601: '$date_val'"
    return 1
  fi
  return 0
}

# Good marker MUST parse.
if out=$(shape_parse "$GOOD_MARKER" 2>&1); then
  pass "AC5.6a: well-formed marker → line-separated fields, branch regex OK, date ISO-8601 parseable"
else
  fail "AC5.6a: well-formed marker should pass shape gate" "$out"
fi

# Glued marker MUST fail (field-line-count mismatch — skill/parent/id/branch/date
# all collapsed to one line, so has_skill=1 but has_parent=0).
if out=$(shape_parse "$BAD_MARKER_GLUED" 2>&1); then
  fail "AC5.6b: glued-fields marker should FAIL shape gate but passed" ""
else
  pass "AC5.6b: glued-fields marker (missing printf \\n) → shape gate DETECTS"
fi

# Empty-branch marker MUST fail.
if out=$(shape_parse "$BAD_MARKER_BRANCH" 2>&1); then
  fail "AC5.6c: empty-branch marker should FAIL shape gate but passed" ""
else
  pass "AC5.6c: empty-branch marker → branch-regex DETECTS"
fi

# Bad-date marker MUST fail.
if out=$(shape_parse "$BAD_MARKER_DATE" 2>&1); then
  fail "AC5.6d: bad-date marker should FAIL shape gate but passed" ""
else
  pass "AC5.6d: bad-date marker → ISO-8601 parse DETECTS"
fi

# ──────────────────────────────────────────────────────────────
# C32 — state-transition flip within ONE fixture (absorbs the unique
# behavioral coverage of docs/plans/CANARY_BYPASS_DETECT.md's Phase 2
# fulfillment-teardown step, AC-P2.3). The existing C1/C3 (no/mismatched
# marker → Pattern 1) and C2 (matching marker → Pattern 2) are SEPARATE
# fixtures; this case proves the Pattern-2 → Pattern-1 SELECTION is driven
# by marker presence/absence within a single fixture: write a matching
# requires.land-pr.<id> marker, run `gh pr create` → Pattern 2; then `rm`
# the marker, re-run the SAME envelope → Pattern 1. State-driven, not
# heuristic. This is the canary's last un-absorbed assertion.
# ──────────────────────────────────────────────────────────────
clean_tracking
FLIP_PIPELINE="commit.canary-bypass-flip"
FLIP_ID="canary-bypass-flip"
write_requires_marker "$FLIP_PIPELINE" "$FLIP_ID" "$SANDBOX_HEAD"
FLIP_ENVELOPE="$(mkenv "gh pr create -B main")"

# Step 1 — marker present → Pattern 2.
run_hook "$FLIP_ENVELOPE"
flip_step1_ok=1
[[ "$HOOK_OUT" == *'"permissionDecision":"deny"'* ]] || flip_step1_ok=0
[[ "$HOOK_OUT" == *'declared an intent to'* ]] || flip_step1_ok=0

# Step 2 — remove the marker, re-run the SAME envelope → Pattern 1.
rm -f "$SANDBOX/.zskills/tracking/$FLIP_PIPELINE/requires.land-pr.$FLIP_ID"
run_hook "$FLIP_ENVELOPE"
flip_step2_ok=1
[[ "$HOOK_OUT" == *'"permissionDecision":"deny"'* ]] || flip_step2_ok=0
[[ "$HOOK_OUT" == *'outside a caller skill'* ]] || flip_step2_ok=0

if [ "$flip_step1_ok" -eq 1 ] && [ "$flip_step2_ok" -eq 1 ]; then
  pass "C32: marker present → Pattern 2; marker removed → Pattern 1 (state-transition flip, one fixture)"
else
  fail "C32: state-transition flip did not follow marker presence/absence" \
    "step1(Pattern2)=$flip_step1_ok step2(Pattern1)=$flip_step2_ok last_out=$HOOK_OUT"
fi

# Cleanup tracking sentinels.
clean_tracking

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
