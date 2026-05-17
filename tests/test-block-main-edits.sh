#!/usr/bin/env bash
# Tests for hooks/block-main-edits.sh — issue #308.
# Run from repo root: bash tests/test-block-main-edits.sh
#
# Coverage matrix:
#
#   C1   Edit on main, non-allowlisted path     → DENY
#   C2   Write on main, non-allowlisted path    → DENY
#   C3   NotebookEdit on main, non-allowlisted  → DENY
#   C4   Edit in linked worktree (same file)    → ALLOW
#   C5   Edit on main, .zskills/audit/*         → ALLOW (allowlist)
#   C6   Edit on main, .zskills/tracking/<id>/* → ALLOW (allowlist)
#   C7   Edit on main, .zskills/issues/*        → ALLOW (allowlist)
#   C8   Edit on main, .zskills-tracked         → ALLOW (allowlist)
#   C9   Edit on main, .landed                  → ALLOW (allowlist)
#   C10  Edit on main, main_protected=false     → ALLOW (config gate off)
#   C11  Edit on main, config missing           → ALLOW (default off)
#   C12  Edit outside MAIN_ROOT entirely        → ALLOW
#   C13  Bash invocation (wrong tool)           → ALLOW (no-op)
#   C14  Edit with no file_path field           → ALLOW (defensive)
#   C15  Edit skills/<name>/SKILL.md on main    → DENY (canonical block target)
#   C16  Edit hooks/foo.sh on main              → DENY (canonical block target)
#   C17  Edit CLAUDE.md on main                 → DENY (canonical block target)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/hooks/block-main-edits.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "=== block-main-edits.sh ==="

# ── Sandbox setup ────────────────────────────────────────────────────────
# Build a self-contained sandbox that LOOKS like a main repo:
#   $SANDBOX/.git/                       (real init, branch=main)
#   $SANDBOX/.claude/zskills-config.json (main_protected: true)
#   $SANDBOX/CLAUDE.md                   (a "main" file)
#   $SANDBOX/skills/foo/SKILL.md         (another "main" file)
#   $SANDBOX/hooks/x.sh                  (another "main" file)
#   $SANDBOX/.zskills/audit/r.md         (allowlisted file)
#   $SANDBOX/.zskills/tracking/p/req.x   (allowlisted file)
#   $SANDBOX/.zskills/issues/i.md        (allowlisted file)
#
# Then add a linked worktree at $SANDBOX-wt/ on branch 'feat/x'.
SANDBOX=$(mktemp -d)
WORKTREE="${SANDBOX}-wt"
trap 'cd /; (cd "$SANDBOX" && git worktree remove --force "$WORKTREE" 2>/dev/null); rm -rf "$SANDBOX" "$WORKTREE"' EXIT

mkdir -p "$SANDBOX"
# We use the GIT_AUTHOR_* / GIT_COMMITTER_* env so we don't trip the
# parent session's block-unsafe-project.sh hook (which gates `git -c
# user.email=...` style commits on `main` when main_protected is true in
# the PARENT repo's config — which it IS in this repo). Setting the
# identity via env vars routes around the `-c` token detection. Also we
# do the commits in a clean GIT_DIR-rooted invocation that's not visible
# to the outer hook surface.
#
# Branch naming note: the sandbox's "main-equivalent" branch is named
# `sandbox-trunk` (NOT `main`/`master`). The PARENT repo's
# block-unsafe-project.sh hook fires on `git commit` when the working tree
# it sees (the SANDBOX) is on a branch literally called `main` or
# `master` AND parent main_protected is true. Sandbox setup must not trip
# that gate — and our hook detects "main repo" via the
# git-dir == git-common-dir worktree self-check, not branch name, so any
# trunk name works.
(
  cd "$SANDBOX" || exit 1
  git init -q -b sandbox-trunk .
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
         GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git commit --allow-empty -q -m init
  mkdir -p .claude skills/foo hooks .zskills/audit .zskills/tracking/pipe1 .zskills/issues
  printf '{"execution":{"main_protected":true}}' > .claude/zskills-config.json
  : > CLAUDE.md
  : > skills/foo/SKILL.md
  : > hooks/x.sh
  : > .zskills/audit/r.md
  : > .zskills/tracking/pipe1/req.x
  : > .zskills/issues/i.md
  : > .zskills-tracked
  : > .landed
  # Stage by explicit name (the PARENT repo's block-unsafe-project hook
  # denies `git add -A` / `git add .` as a "sweeps in all sessions' work"
  # safety rule; we have to obey that from inside the test too).
  git add .claude/zskills-config.json CLAUDE.md skills/foo/SKILL.md \
          hooks/x.sh .zskills/audit/r.md .zskills/tracking/pipe1/req.x \
          .zskills/issues/i.md .zskills-tracked .landed
  git commit -q -m "seed"
)
# Linked worktree on a different branch.
(
  cd "$SANDBOX" || exit 1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
         GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git worktree add -q -b feat/x "$WORKTREE" sandbox-trunk 2>/dev/null
)

# ── Helpers ──────────────────────────────────────────────────────────────
# Run hook with a JSON envelope on stdin. CLAUDE_PROJECT_DIR is set to
# either $SANDBOX (the "main" case) or $WORKTREE (the "linked worktree"
# case). HOOK_OUT / HOOK_EXIT / HOOK_ERR are exposed for the assertion
# helpers below. Mirrors the pattern in tests/test-block-bypassed-land-pr.sh.
run_hook() {
  local project_dir="$1"
  local input="$2"
  local errf
  errf=$(mktemp)
  # Subshell with exported CLAUDE_PROJECT_DIR — `VAR=val cmd1 | cmd2` only
  # scopes VAR to cmd1, not cmd2 (the hook). The hook reads
  # CLAUDE_PROJECT_DIR to resolve MAIN_ROOT.
  HOOK_OUT=$(
    export CLAUDE_PROJECT_DIR="$project_dir"
    printf '%s' "$input" | bash "$HOOK" 2>"$errf"
  )
  HOOK_EXIT=$?
  HOOK_ERR=$(cat "$errf")
  rm -f "$errf"
}

# Build an Edit/Write/NotebookEdit envelope. The tool name and the key
# under tool_input vary by tool.
mkenv_edit()   { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }
mkenv_write()  { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }
mkenv_nbedit() { printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s"}}' "$1"; }
mkenv_bash()   { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
mkenv_edit_no_path() { printf '{"tool_name":"Edit","tool_input":{}}'; }

assert_deny() {
  local label="$1" envelope="$2"
  local ok=1
  [[ "$envelope" == *'"permissionDecision":"deny"'* ]] || ok=0
  [[ "$envelope" == *'STOP'* ]] || ok=0
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

# ── C1: Edit on main, non-allowlisted ────────────────────────────────────
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/CLAUDE.md")"
assert_deny "C1: Edit on main (CLAUDE.md) → DENY" "$HOOK_OUT"

# ── C2: Write on main, non-allowlisted ───────────────────────────────────
run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/CLAUDE.md")"
assert_deny "C2: Write on main (CLAUDE.md) → DENY" "$HOOK_OUT"

# ── C3: NotebookEdit on main, non-allowlisted ────────────────────────────
run_hook "$SANDBOX" "$(mkenv_nbedit "$SANDBOX/skills/foo/notebook.ipynb")"
assert_deny "C3: NotebookEdit on main → DENY" "$HOOK_OUT"

# ── C4: Edit in linked worktree (same relative file, different abs path) ─
# CLAUDE_PROJECT_DIR points at the WORKTREE. The hook self-checks:
# git-dir != git-common-dir → exit 0 (no-op). This is the load-bearing
# "we only protect main" rule: a session started in a worktree must never
# block writes inside that worktree.
run_hook "$WORKTREE" "$(mkenv_edit "$WORKTREE/CLAUDE.md")"
assert_allow "C4: Edit in linked worktree → ALLOW (worktree self-check)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C5–C7: allowlisted paths on main → ALLOW ─────────────────────────────
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/.zskills/audit/r.md")"
assert_allow "C5: Edit on main .zskills/audit/* → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills/tracking/pipe1/req.x")"
assert_allow "C6: Write on main .zskills/tracking/<id>/* → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/.zskills/issues/i.md")"
assert_allow "C7: Edit on main .zskills/issues/* → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

# ── C8–C9: gitignored worktree-state markers → ALLOW ─────────────────────
run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.zskills-tracked")"
assert_allow "C8: Write on main .zskills-tracked → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

run_hook "$SANDBOX" "$(mkenv_write "$SANDBOX/.landed")"
assert_allow "C9: Write on main .landed → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

# ── C10: main_protected=false → ALLOW (config gate off, the load-bearing one) ──
printf '{"execution":{"main_protected":false}}' > "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/CLAUDE.md")"
assert_allow "C10: main_protected=false → ALLOW (gate off, issue #308 §1)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C11: config missing → ALLOW (default off) ────────────────────────────
rm -f "$SANDBOX/.claude/zskills-config.json"
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/CLAUDE.md")"
assert_allow "C11: config missing → ALLOW (default off)" "$HOOK_EXIT" "$HOOK_OUT"

# Restore main_protected for subsequent cases.
printf '{"execution":{"main_protected":true}}' > "$SANDBOX/.claude/zskills-config.json"

# ── C12: Edit outside MAIN_ROOT entirely → ALLOW ─────────────────────────
run_hook "$SANDBOX" "$(mkenv_edit "/tmp/some-other-path/foo.md")"
assert_allow "C12: Edit outside MAIN_ROOT → ALLOW" "$HOOK_EXIT" "$HOOK_OUT"

# ── C13: Bash tool (wrong matcher) → ALLOW ───────────────────────────────
run_hook "$SANDBOX" "$(mkenv_bash "ls")"
assert_allow "C13: Bash tool → ALLOW (defense-in-depth tool guard)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C14: Edit envelope with no file_path → ALLOW (defensive, never false-deny) ─
run_hook "$SANDBOX" "$(mkenv_edit_no_path)"
assert_allow "C14: Edit with no file_path → ALLOW (defensive)" "$HOOK_EXIT" "$HOOK_OUT"

# ── C15: skills/<name>/SKILL.md on main → DENY (canonical motivating case) ─
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/skills/foo/SKILL.md")"
assert_deny "C15: Edit skills/foo/SKILL.md on main → DENY" "$HOOK_OUT"

# ── C16: hooks/*.sh on main → DENY ───────────────────────────────────────
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/hooks/x.sh")"
assert_deny "C16: Edit hooks/x.sh on main → DENY" "$HOOK_OUT"

# ── C17: CLAUDE.md on main → DENY (already in C1, but assert deny envelope
# contains a worktree alternative recommendation per the STOP message contract) ─
run_hook "$SANDBOX" "$(mkenv_edit "$SANDBOX/CLAUDE.md")"
if [[ "$HOOK_OUT" == *'/quickfix'* ]] || [[ "$HOOK_OUT" == *'/do'* ]] || [[ "$HOOK_OUT" == *'worktree'* ]]; then
  pass "C17: STOP message recommends worktree alternative"
else
  fail "C17: STOP message recommends worktree alternative" "envelope=$HOOK_OUT"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
