# tests/lib/hooks-harness.sh — shared harness for the hooks test surface
# (Test Suite Parallelization plan, Phase 1a).
#
# SOURCEABLE LIBRARY, NOT A SUITE. Do NOT register in run-all.sh as a
# `run_suite` — exactly like tests/lib/extract-fence.sh,
# tests/lib/landpr-harness.sh, tests/lib/parse-results.sh, and
# tests/lib/suite-registry.sh (the Phase 0 libs). This file carries NO
# self-registration assertion.
#
# This factors ALL shared helpers that tests/test-hooks.sh depends on out of
# the monolith so a future per-sub-suite split (Phase 1b) can source ONE
# harness instead of re-typing drift-prone copies. In Phase 1a the monolith
# is UNCHANGED except that it sources this lib in place of its inline helper
# copies; no test section moves.
#
# ── Self-location & hook-path script-globals ─────────────────────────────
# The factored helpers close over module-level globals (the hook paths). When
# this harness is sourced from an arbitrary cwd by a Phase-1b sub-suite, those
# globals MUST resolve to absolute paths so e.g. `setup_project_test` copies
# the REAL hook template rather than silently `cp`-ing an empty/wrong source.
#
# REPO_ROOT: honour a value the caller already exported (test-hooks.sh sets it
# before sourcing); otherwise derive it from this file's own location so a
# sub-suite that sources the harness without pre-setting REPO_ROOT still works.
if [ -z "${REPO_ROOT:-}" ]; then
  _HH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$_HH_LIB_DIR/../.." && pwd)"
fi

# Hook-path globals the factored helpers (and the Phase-1b sub-suites) close
# over. Three are already absolute in the monolith; PROJECT_HOOK is defined
# RELATIVE there (cwd-fragile — line 974 `hooks/block-unsafe-project.sh.template`)
# and is ABSOLUTIZED here so `setup_project_test`'s `cp "$PROJECT_HOOK" …`
# resolves correctly from any cwd.
HOOK="$REPO_ROOT/hooks/block-unsafe-generic.sh"
PROJECT_HOOK="$REPO_ROOT/hooks/block-unsafe-project.sh.template"
AGENTS_HOOK="$REPO_ROOT/hooks/block-agents.sh.template"
WARN_HOOK="$REPO_ROOT/hooks/warn-config-drift.sh"

# Project-hook fixture state (cleared by teardown_project_test).
TEST_TMPDIR=""

# ── Pass / fail counters + reporters ─────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  ((FAIL_COUNT++))
}

# ── Generic-hook expectation helpers ─────────────────────────────────────
# --- Helper: run hook with a Bash command, expect deny ---
expect_deny() {
  local label="$1"
  local cmd="$2"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | bash "$HOOK")
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "deny: $label"
  else
    fail "deny: $label — expected deny, got: $result"
  fi
}

# --- Helper: run hook with a Bash command, expect allow (empty output) ---
expect_allow() {
  local label="$1"
  local cmd="$2"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | bash "$HOOK")
  if [[ -z "$result" ]]; then
    pass "allow: $label"
  else
    fail "allow: $label — got unexpected output: $result"
  fi
}

# --- Helpers: run hook from inside a temp repo on a specific branch ---
# Needed for `git push origin HEAD` testing — the generic hook resolves HEAD
# via `git branch --show-current` against the cwd's repo, so the branch
# context must be controlled per-case. Issue #556 / closes the property-test
# matrix gap left by #515's runtime fix.
#
# Caller pattern: set up a temp repo on the target branch ONCE per branch,
# then call expect_deny_from_repo / expect_allow_from_repo with the repo
# path repeatedly. Cleaner than mktemp-per-case (which would balloon to
# hundreds of mkdir/git-init syscalls).
make_branch_repo() {
  local branch="$1"
  local dir
  dir=$(mktemp -d)
  (cd "$dir" && \
   git init -q && \
   git checkout -q -b "$branch" 2>/dev/null && \
   git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null)
  echo "$dir"
}

expect_deny_from_repo() {
  local repo="$1"
  local label="$2"
  local cmd="$3"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | (cd "$repo" && bash "$HOOK"))
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "deny: $label"
  else
    fail "deny: $label — expected deny, got: $result"
  fi
}

expect_allow_from_repo() {
  local repo="$1"
  local label="$2"
  local cmd="$3"
  local result
  result=$(echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"}}" | (cd "$repo" && bash "$HOOK"))
  if [[ -z "$result" ]]; then
    pass "allow: $label"
  else
    fail "allow: $label — got unexpected output: $result"
  fi
}

# ── Project-hook fixture + expectation helpers ───────────────────────────
setup_project_test() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  mkdir -p "$TEST_TMPDIR/.zskills/tracking"

  # Copy the hook template. Post-Phase-1, test-cmd / UI-pattern values are
  # NOT install-filled — they are read at runtime from .claude/zskills-config.json.
  cp "$PROJECT_HOOK" "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"

  # Write the runtime config the hook expects.
  cat > "$TEST_TMPDIR/.claude/zskills-config.json" <<'EOF'
{
  "testing": {
    "unit_cmd": "npm test",
    "full_cmd": "npm run test:all"
  },
  "ui": {
    "file_patterns": "src/ui/"
  }
}
EOF

  # Create mock package.json with test script
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$TEST_TMPDIR/package.json"

  # Create mock transcript with test command AND pipeline ID declaration.
  # ZSKILLS_PIPELINE_ID triggers the transcript-based pipeline association
  # (tier 2) so tracking enforcement fires for orchestrator-on-main tests.
  printf 'ZSKILLS_PIPELINE_ID=run-plan.test-plan\nnpm run test:all\n' > "$TEST_TMPDIR/.transcript"

  # Initialize git repo (needed for git diff --cached, git-common-dir, etc.)
  (cd "$TEST_TMPDIR" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null)
}

teardown_project_test() {
  [ -n "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
  [ -n "$TEST_REMOTE" ] && rm -rf "$TEST_REMOTE"
  TEST_TMPDIR=""
  TEST_REMOTE=""
}

# Helper: set up a bare remote so git diff @{u}..HEAD works in push tests
setup_push_remote() {
  TEST_REMOTE=$(mktemp -d)
  # Detect the actual branch name (master vs main depending on git config).
  # Hardcoding origin/master broke when init.defaultBranch=main was set in CI.
  (cd "$TEST_TMPDIR" && \
   git clone --bare "$TEST_TMPDIR" "$TEST_REMOTE" 2>/dev/null && \
   git remote add origin "$TEST_REMOTE" 2>/dev/null && \
   git fetch origin 2>/dev/null && \
   _CB=$(git branch --show-current 2>/dev/null) && \
   git branch -u "origin/$_CB" 2>/dev/null)
}

expect_project_deny() {
  # Accept 1-arg (cmd) or 2-arg (label, cmd) forms. Legacy callers pass one
  # arg; newer callers pass a human-readable label + the command under test.
  local label cmd
  if [ -n "$2" ]; then label="$1"; cmd="$2"; else label="$1"; cmd="$1"; fi
  # JSON shape: "command" is the LAST field so the hook's greedy sed
  # extraction (`.*"command":"\(.*\)".*`) doesn't bleed envelope tokens
  # like `transcript_path` into COMMAND. Same fix as run_main_protected_test
  # (see comment at the build site there). Pre-BLOCK_UNSAFE_HARDENING the
  # bare-substring regexes were forgiving of greedy bleed; the post-Phase-3
  # tokenize-then-walk helper is strict, so command-last shape is required
  # for short commands like `git push` or `git -P commit`.
  local json="{\"tool_name\":\"Bash\",\"transcript_path\":\"$TEST_TMPDIR/.transcript\",\"tool_input\":{\"command\":\"$cmd\"}}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" TRACKING_ROOT="$TEST_TMPDIR" bash -c "cd '$TEST_TMPDIR' && bash '$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "$label → denied (expected)"
  else
    fail "$label → allowed (expected deny)"
  fi
}

expect_project_allow() {
  local label cmd
  if [ -n "$2" ]; then label="$1"; cmd="$2"; else label="$1"; cmd="$1"; fi
  # See expect_project_deny for the command-last JSON-shape rationale.
  local json="{\"tool_name\":\"Bash\",\"transcript_path\":\"$TEST_TMPDIR/.transcript\",\"tool_input\":{\"command\":\"$cmd\"}}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" TRACKING_ROOT="$TEST_TMPDIR" bash -c "cd '$TEST_TMPDIR' && bash '$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ -z "$result" ]] || [[ "$result" != *"deny"* ]]; then
    pass "$label → allowed (expected)"
  else
    fail "$label → denied (expected allow)"
  fi
}

# ── run_main_protected_test ──────────────────────────────────────────────
# Shared project-hook fixture runner: builds a temp repo on $branch with a
# rendered project hook + runtime config, then runs the hook against $cmd and
# echoes the hook's stdout (deny envelope or empty). Relocated into the harness
# in Phase 1b because it is now shared across three sub-suites
# (test-hooks-main-protected.sh, test-hooks-bypass-project.sh, and the PR-mode
# section of test-hooks-misc.sh); in the monolith it lived inline in the
# main_protected section. Closes over the absolutized $PROJECT_HOOK global.
run_main_protected_test() {
  local branch="$1"
  local config_content="$2"
  local cmd="$3"
  local test_tmpdir
  test_tmpdir=$(mktemp -d)

  mkdir -p "$test_tmpdir/.claude/hooks"
  mkdir -p "$test_tmpdir/.zskills/tracking"

  # Copy the hook template. Post-Phase-1 the hook reads test-cmd / UI values
  # at runtime from .claude/zskills-config.json.
  cp "$PROJECT_HOOK" "$test_tmpdir/.claude/hooks/block-unsafe-project.sh"

  # Create mock package.json and transcript
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$test_tmpdir/package.json"
  printf 'npm run test:all\n' > "$test_tmpdir/.transcript"

  # Initialize git repo on specified branch
  (cd "$test_tmpdir" && git init -q && git checkout -b "$branch" 2>/dev/null && git add -A && git commit -q -m "init" 2>/dev/null)

  # Write config: always include test-cmd fields so runtime read populates
  # FULL_TEST_CMD (used by the commit transcript gate). The caller-supplied
  # config_content may override (e.g., to add execution.main_protected).
  if [ -n "$config_content" ]; then
    # Caller supplied partial config (e.g. just {"execution": {...}}). Merge
    # default testing/ui fields so the runtime-read block populates the
    # hook's test-cmd / UI-pattern vars. python3 is available on CI.
    CALLER_CFG="$config_content" python3 -c '
import json, os
caller = json.loads(os.environ["CALLER_CFG"])
defaults = {"testing": {"unit_cmd": "npm test", "full_cmd": "npm run test:all"}, "ui": {"file_patterns": "src/ui/"}}
for k, v in defaults.items():
    caller.setdefault(k, v)
print(json.dumps(caller))
' > "$test_tmpdir/.claude/zskills-config.json"
  else
    cat > "$test_tmpdir/.claude/zskills-config.json" <<'EOF'
{
  "testing": {
    "unit_cmd": "npm test",
    "full_cmd": "npm run test:all"
  },
  "ui": {
    "file_patterns": "src/ui/"
  }
}
EOF
  fi

  # JSON shape: "command" is the LAST field so the hook's greedy sed
  # extraction (`.*"command":"\(.*\)".*`) doesn't bleed envelope tokens
  # like `transcript_path` into COMMAND. Single-line JSON is required by
  # the helper; reordering to put `command` last is the simplest way to
  # match production (where Claude Code's JSON is multi-line, also clean).
  # Issue #81: rule (c)'s PUSH_ARGS-based check needs a clean COMMAND so
  # the post-`git push` segment doesn't get JSON envelope words spliced in.
  local json="{\"tool_name\":\"Bash\",\"transcript_path\":\"$test_tmpdir/.transcript\",\"tool_input\":{\"command\":\"$cmd\"}}"
  # Override LOCAL_ROOT and TRACKING_ROOT so the hook resolves to the fixture,
  # not the caller's worktree. Without these, the hook's push-path tracking
  # block reads .zskills/tracked (legacy .zskills-tracked) + tracking markers from wherever the test was
  # invoked from (typically a zskills-tracked worktree with accumulated commits),
  # firing the tracking guard before the main_protected check this test asserts.
  local result
  # cd into the fixture repo before invoking the hook. The project hook's
  # HEAD-rewrite block (block-unsafe-project.sh.template:1057) calls
  # `git branch --show-current` against the cwd to resolve `git push origin
  # HEAD` to the local branch. Without cd, the hook sees the test runner's
  # outer cwd (the worktree where tests/test-hooks.sh lives) instead of the
  # fixture repo on $branch, breaking #556's branch-context assertions.
  # Existing assertions (using REPO_ROOT for is_on_main) are unaffected.
  result=$(echo "$json" | \
    REPO_ROOT="$test_tmpdir" \
    LOCAL_ROOT="$test_tmpdir" \
    TRACKING_ROOT="$test_tmpdir" \
    bash -c "cd '$test_tmpdir' && bash '$test_tmpdir/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)

  # Cleanup
  rm -rf "$test_tmpdir"
  echo "$result"
}

# ── setup_project_test_on_main ───────────────────────────────────────────
# Owned by the harness via sourcing tests/test-hooks-helpers.sh (single source
# of truth — no duplicate definition). setup_project_test is already defined
# above, so the helper file's stub fallback is skipped and the REAL fixture is
# used. The file's `BASH_SOURCE == $0` self-test guard does NOT fire here
# (sourced, not executed), so no stray standalone `Results:` line is emitted.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-hooks-helpers.sh"
