#!/bin/bash
# Tests for /update-zskills Step C extension — agent + new-hook install path.
#
# /update-zskills is an agent-executed command. We cannot literally invoke
# the skill from a shell test. Instead, we encode the algorithm documented
# in `skills/update-zskills/SKILL.md` Step C "Custom subagent definitions"
# block and the surrounding hook-copy prose as a bash function below
# (`run_step_c_install`) and run it against fixture directories. The
# function is an executable oracle — if SKILL.md's spec changes meaning,
# the oracle must be updated in lockstep.
#
# Coverage (matches Phase 5 WI 5.4 acceptance criteria exactly):
#   1.  Fresh consumer install — verifier.md + 2 new hook scripts land in
#       expected locations; commit-reviewer.md (D'' dropped) is NOT
#       installed; .claude/scripts/ is NOT created.
#   2.  Byte-equivalence — installed verifier.md matches source.
#   3.  Idempotency — re-running with no changes prints no "Updated" lines.
#   4.  Update path — modifying consumer's verifier.md and re-running
#       prints "Updated agent: verifier.md".
#
# Per CLAUDE.md test-output idiom, this script writes scratch fixtures
# to /tmp/zskills-tests/$(basename "$REPO_ROOT")/agent-install-* so they
# never appear in `git status` of the worktree.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_BASE="/tmp/zskills-tests/$(basename "$REPO_ROOT")/agent-install"
mkdir -p "$WORK_BASE"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }
skip() { printf '\033[33m  SKIP\033[0m %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT+1)); }

# --- Oracle: Step C install (hook + agent copy) ---------------------------
# Args:
#   $1 = $PORTABLE root (contains .claude/agents/*.md and hooks/*.sh)
#   $2 = consumer dir (the install target — pwd-equivalent)
#
# Stdout: "Installed agent: ...", "Updated agent: ...", and per-hook copies.
# Return: 0 on success.
#
# Encodes the SKILL.md Step C agent-copy block verbatim plus a minimal
# hook-copy loop for the 2 new hooks. The 2 new hooks have NO
# settings.json wiring (loaded via verifier.md frontmatter and direct
# skill invocation respectively), so this oracle does NOT touch
# settings.json.
run_step_c_install() {
  local PORTABLE="$1" PROJECT_DIR="$2"

  # --- Hook copy (for the 2 new hooks only — block-* and warn-* are out
  # of scope for this test) ---
  mkdir -p "$PROJECT_DIR/.claude/hooks"
  for hook in inject-bash-timeout.sh verify-response-validate.sh; do
    local src="$PORTABLE/hooks/$hook"
    local dst="$PROJECT_DIR/.claude/hooks/$hook"
    [ -e "$src" ] || continue
    if [ ! -f "$dst" ]; then
      cp -a "$src" "$dst" && echo "Installed hook: $hook"
    elif ! cmp -s "$src" "$dst"; then
      cp -a "$src" "$dst" && echo "Updated hook: $hook"
    fi
  done

  # --- Agent copy (verbatim from SKILL.md Step C "Custom subagent
  # definitions" bash block; pwd-relative paths replaced with
  # $PROJECT_DIR-anchored paths so the oracle is testable without `cd`) ---
  if [ -d "$PORTABLE/.claude/agents" ]; then
    mkdir -p "$PROJECT_DIR/.claude/agents"
    for src in "$PORTABLE/.claude/agents"/*.md; do
      [ -e "$src" ] || continue
      local name
      name=$(basename "$src")
      local dst="$PROJECT_DIR/.claude/agents/$name"
      if [ ! -f "$dst" ]; then
        cp -a "$src" "$dst" && echo "Installed agent: $name"
      elif ! cmp -s "$src" "$dst"; then
        cp -a "$src" "$dst" && echo "Updated agent: $name"
      fi
    done
    echo "WARN: agent definitions auto-discover at session start. Restart Claude Code (or open a new session) before invoking verifier-using skills (/run-plan, /commit, /fix-issues, /do, /verify-changes). There is no in-session reload command."
  fi

  return 0
}

# --- Helpers ---------------------------------------------------------------

# Build a fresh sandbox $PORTABLE populated from the worktree's actual
# .claude/agents/ and hooks/ — but FILTERED to ensure we don't accidentally
# ship anything beyond what Phase 5 expects. Specifically:
#   - .claude/agents/verifier.md       → COPY
#   - .claude/agents/canary-readonly.md → COPY (it ships with zskills)
#   - .claude/agents/commit-reviewer.md → DELIBERATELY OMIT (D'' dropped)
#   - hooks/inject-bash-timeout.sh     → COPY
#   - hooks/verify-response-validate.sh → COPY
#   - all other hooks                  → omit (out of scope for this test)
make_portable() {
  local label="$1"
  local portable="$WORK_BASE/portable-$label-$$"
  rm -rf -- "$portable"
  mkdir -p "$portable/.claude/agents" "$portable/hooks"

  # Copy the real verifier.md and canary-readonly.md from the worktree.
  cp -a "$REPO_ROOT/.claude/agents/verifier.md" "$portable/.claude/agents/"
  if [ -f "$REPO_ROOT/.claude/agents/canary-readonly.md" ]; then
    cp -a "$REPO_ROOT/.claude/agents/canary-readonly.md" "$portable/.claude/agents/"
  fi

  # Copy the 2 new hook scripts.
  cp -a "$REPO_ROOT/hooks/inject-bash-timeout.sh" "$portable/hooks/"
  cp -a "$REPO_ROOT/hooks/verify-response-validate.sh" "$portable/hooks/"

  # Ensure executable bits set (cp -a preserves; belt-and-suspenders).
  chmod +x "$portable/hooks/inject-bash-timeout.sh"
  chmod +x "$portable/hooks/verify-response-validate.sh"

  echo "$portable"
}

# Build a fresh consumer dir with empty .claude/.
make_consumer() {
  local label="$1"
  local consumer="$WORK_BASE/consumer-$label-$$"
  rm -rf -- "$consumer"
  mkdir -p "$consumer/.claude"
  echo "$consumer"
}

# --- Test cases ------------------------------------------------------------

# Case 1: Fresh consumer install — agent + 2 hooks land; commit-reviewer.md
# does NOT install; .claude/scripts/ is NOT created.
test_case_1_fresh_install() {
  local label="case1"
  local portable; portable=$(make_portable "$label")
  local consumer; consumer=$(make_consumer "$label")

  local out
  out=$(run_step_c_install "$portable" "$consumer" 2>&1)

  local ok=1
  [ -f "$consumer/.claude/agents/verifier.md" ] || { ok=0; fail "case 1: verifier.md present" "missing"; }
  [ -x "$consumer/.claude/hooks/inject-bash-timeout.sh" ] || { ok=0; fail "case 1: inject-bash-timeout.sh exec" "missing or not exec"; }
  [ -x "$consumer/.claude/hooks/verify-response-validate.sh" ] || { ok=0; fail "case 1: verify-response-validate.sh exec" "missing or not exec"; }
  [ ! -f "$consumer/.claude/agents/commit-reviewer.md" ] || { ok=0; fail "case 1: commit-reviewer.md NOT installed" "present (D'' dropped this agent)"; }
  [ ! -d "$consumer/.claude/scripts" ] || { ok=0; fail "case 1: .claude/scripts NOT created" "directory exists (hook scripts must go to .claude/hooks/)"; }
  echo "$out" | grep -qF 'WARN: agent definitions auto-discover at session start' \
    || { ok=0; fail "case 1: WARN line emitted" "not in output"; }

  if [ "$ok" -eq 1 ]; then
    pass "case 1: fresh install — agent + 2 hooks land; commit-reviewer absent; no .claude/scripts/"
  fi
  rm -rf -- "$portable" "$consumer"
}

# Case 2: Byte-equivalence — installed verifier.md matches source.
test_case_2_byte_equivalence() {
  local label="case2"
  local portable; portable=$(make_portable "$label")
  local consumer; consumer=$(make_consumer "$label")

  run_step_c_install "$portable" "$consumer" >/dev/null 2>&1

  if cmp -s "$portable/.claude/agents/verifier.md" "$consumer/.claude/agents/verifier.md"; then
    pass "case 2: installed verifier.md byte-equivalent to source"
  else
    fail "case 2: installed verifier.md byte-equivalent to source" \
      "$(diff "$portable/.claude/agents/verifier.md" "$consumer/.claude/agents/verifier.md" | head -10)"
  fi
  rm -rf -- "$portable" "$consumer"
}

# Case 3: Idempotency — re-run prints no "Updated" lines.
test_case_3_idempotent_rerun() {
  local label="case3"
  local portable; portable=$(make_portable "$label")
  local consumer; consumer=$(make_consumer "$label")

  run_step_c_install "$portable" "$consumer" >/dev/null 2>&1

  local out2
  out2=$(run_step_c_install "$portable" "$consumer" 2>&1)

  if echo "$out2" | grep -qE '^(Updated agent|Updated hook):'; then
    fail "case 3: idempotent re-run — no 'Updated' lines" \
      "$(echo "$out2" | grep -E '^Updated')"
  else
    pass "case 3: idempotent re-run — no spurious 'Updated' lines"
  fi
  rm -rf -- "$portable" "$consumer"
}

# Case 4: Update path — modifying consumer's verifier.md and re-running
# prints "Updated agent: verifier.md".
test_case_4_update_on_change() {
  local label="case4"
  local portable; portable=$(make_portable "$label")
  local consumer; consumer=$(make_consumer "$label")

  run_step_c_install "$portable" "$consumer" >/dev/null 2>&1

  # Mutate the consumer's verifier.md.
  echo "# consumer-modified marker $$" >> "$consumer/.claude/agents/verifier.md"

  local out2
  out2=$(run_step_c_install "$portable" "$consumer" 2>&1)

  if echo "$out2" | grep -qF 'Updated agent: verifier.md'; then
    # And confirm overwrite restored byte-equivalence (consumer-customization
    # handling: framework owns the file, install OVERWRITES).
    if cmp -s "$portable/.claude/agents/verifier.md" "$consumer/.claude/agents/verifier.md"; then
      pass "case 4: modified consumer file → 'Updated agent' line + overwrite restores source"
    else
      fail "case 4: modified consumer file → overwrite restores source" \
        "byte-diff after re-install"
    fi
  else
    fail "case 4: modified consumer file → 'Updated agent' line" \
      "out=$out2"
  fi
  rm -rf -- "$portable" "$consumer"
}

# --- Run ------------------------------------------------------------------

echo "Running tests/test-update-zskills-agent-install.sh"
test_case_1_fresh_install
test_case_2_byte_equivalence
test_case_3_idempotent_rerun
test_case_4_update_on_change

echo
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  if [ "$SKIP_COUNT" -gt 0 ]; then
    printf '\033[32mResults: %d passed, 0 failed, %d skipped (of %d)\033[0m\n' \
      "$PASS_COUNT" "$SKIP_COUNT" "$TOTAL"
  else
    printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  fi
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed, %d skipped (of %d)\033[0m\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"
  exit 1
fi
