#!/bin/bash
# Tests for skills/quickfix/SKILL.md — Phase 1a happy-path coverage.
#
# Phase 1a scope per plans/QUICKFIX_SKILL.md Phase 1a § Test Cases:
# "cases 1–10 + 14 (11 cases total)". Cases 1–10 cover structural and
# algorithmic invariants of the skill (argument parser, slug derivation,
# branch-name contract, gate wiring). Case 14 covers suite registration.
#
# The full E2E harness (fixture repo + bare-clone remote + mock gh +
# .claude/skills/ mirror) lands in Phase 1b (WI 1.17). Phase 1a keeps
# the harness self-contained and fast — no real git fixtures needed
# for the in-scope cases.
#
# Run from repo root: bash tests/test-quickfix.sh
# Parallel-safe: all temp artifacts are suffixed with $$.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/quickfix/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}
fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# --- Helpers ------------------------------------------------------------
# Slug derivation, extracted verbatim from skills/quickfix/SKILL.md WI 1.6.
# Keeping this in a helper lets us table-drive WI 1.6's contract.
derive_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+//; s/-+$//' \
    | cut -c1-40 \
    | sed -E 's/-+$//'
}

# Per-run scratch directory; never under $REPO_ROOT so `git status` stays clean.
TEST_TMPDIR="/tmp/zskills-quickfix-test-$$"
mkdir -p "$TEST_TMPDIR"
cleanup() {
  rm -rf -- "$TEST_TMPDIR"
}
trap cleanup EXIT

echo "=== quickfix — structural and algorithmic invariants ==="

# ────────────────────────────────────────────────────────────────────
# Case 1 — YAML frontmatter (WI 1.1)
# disable-model-invocation: true + name: quickfix + argument-hint
# ────────────────────────────────────────────────────────────────────
if grep -q '^disable-model-invocation: true$' "$SKILL" \
   && grep -q '^name: quickfix$' "$SKILL" \
   && grep -q '^argument-hint: "\[<description>\]' "$SKILL"; then
  pass "1  frontmatter: name/disable-model-invocation/argument-hint present"
else
  fail "1  frontmatter: missing one of name|disable-model-invocation|argument-hint"
fi

# ────────────────────────────────────────────────────────────────────
# Case 2 — Argument-parser flags (WI 1.2)
# All four flags recognized in the parser block.
# ────────────────────────────────────────────────────────────────────
if grep -q '[-][-]branch)' "$SKILL" \
   && grep -q '[-][-]yes|[-]y)' "$SKILL" \
   && grep -q '[-][-]from-here)' "$SKILL" \
   && grep -q '[-][-]skip-tests)' "$SKILL"; then
  pass "2  argument parser: --branch / --yes|-y / --from-here / --skip-tests"
else
  fail "2  argument parser: one or more flags missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 3 — Slug derivation contract (WI 1.6)
# Table-drive the six rows from the plan's slug-derivation contract.
# ────────────────────────────────────────────────────────────────────
slug_case() {
  local label="$1" input="$2" expected="$3" got
  got=$(derive_slug "$input")
  if [ "$got" = "$expected" ]; then
    pass "3  slug: $label"
  else
    fail "3  slug: $label — input='$input' expected='$expected' got='$got'"
  fi
}
slug_case "ASCII punctuation → kebab"          "Fix README typo!"                        "fix-readme-typo"
slug_case "embedded slash → dash"              "Fix the broken link in docs/intro.md"    "fix-the-broken-link-in-docs-intro-md"
slug_case "leading/trailing whitespace trim"   "  Update CHANGELOG  "                    "update-changelog"
slug_case "collapsed leading/trailing dashes"  "---Fix---foo---"                         "fix-foo"
# 41-char input chosen so cut -c1-40 lands on a dash; final sed must strip it.
slug_case "boundary-at-cut trailing dash"      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx FOO" \
                                               "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
slug_case "no alphanumerics → empty"           "!!!"                                     ""

# ────────────────────────────────────────────────────────────────────
# Case 4 — Branch-name contract (WI 1.7)
# Reproduce the four rows: default prefix, configured prefix, empty
# prefix, and --branch verbatim override. We simulate the branch-build
# step in shell using the same idiom as the skill.
# ────────────────────────────────────────────────────────────────────
build_branch() {
  local override="$1" prefix="$2" slug="$3"
  if [ -n "$override" ]; then
    printf '%s' "$override"
  else
    printf '%s%s' "$prefix" "$slug"
  fi
}
branch_case() {
  local label="$1" override="$2" prefix="$3" slug="$4" expected="$5" got
  got=$(build_branch "$override" "$prefix" "$slug")
  if [ "$got" = "$expected" ]; then
    pass "4  branch: $label"
  else
    fail "4  branch: $label — expected='$expected' got='$got'"
  fi
}
branch_case "default prefix quickfix/"     ""             "quickfix/" "fix-readme-typo" "quickfix/fix-readme-typo"
branch_case "configured prefix fix/"       ""             "fix/"      "fix-readme-typo" "fix/fix-readme-typo"
branch_case "empty prefix → bare slug"     ""             ""          "fix-readme-typo" "fix-readme-typo"
branch_case "--branch custom/foo verbatim" "custom/foo"   "quickfix/" "ignored"         "custom/foo"

# ────────────────────────────────────────────────────────────────────
# Case 5 — Test-cmd alignment gate wiring (WI 1.3 check 4)
# unit_cmd AND full_cmd both mentioned; alignment logic present.
# The exact if-test is grep-assertable.
# ────────────────────────────────────────────────────────────────────
if grep -q 'testing.unit_cmd' "$SKILL" \
   && grep -q 'testing.full_cmd' "$SKILL" \
   && grep -q 'full_cmd.*!=.*unit_cmd\|"\$FULL_CMD" != "\$UNIT_CMD"' "$SKILL"; then
  pass "5  test-cmd alignment gate: unit_cmd set AND full_cmd==unit_cmd check present"
else
  fail "5  test-cmd alignment gate: wiring not found"
fi

# ────────────────────────────────────────────────────────────────────
# Case 6 — Landing gate wiring (WI 1.3 check 3)
# execution.landing == "pr" check and non-pr exit 1 path.
# ────────────────────────────────────────────────────────────────────
if grep -q 'execution.landing' "$SKILL" \
   && grep -q 'requires execution.landing == "pr"' "$SKILL"; then
  pass "6  landing gate: execution.landing read, \"pr\"-required error present"
else
  fail "6  landing gate: wiring not found"
fi

# ────────────────────────────────────────────────────────────────────
# Case 7 — Mode detection truth table (WI 1.5)
# All four rows representable: user-edited, agent-dispatched, and the
# two exit-2 error strings distinguishable.
# ────────────────────────────────────────────────────────────────────
if grep -q 'MODE="user-edited"' "$SKILL" \
   && grep -q 'MODE="agent-dispatched"' "$SKILL" \
   && grep -q 'user-edited mode requires a description' "$SKILL" \
   && grep -q 'either in-flight edits or a description' "$SKILL"; then
  pass "7  mode detection: both modes + both exit-2 discriminators present"
else
  fail "7  mode detection: missing a mode assignment or an exit-2 discriminator"
fi

# ────────────────────────────────────────────────────────────────────
# Case 8 — Push form is bare-branch (WI 1.14)
# git push -u origin "$BRANCH" present; no refspec forms visible.
# ────────────────────────────────────────────────────────────────────
if grep -qE 'git push -u origin "\$BRANCH"' "$SKILL" \
   && ! grep -qE 'HEAD:main|HEAD:master' "$SKILL" \
   && ! grep -qE 'git push [^|]*:' "$SKILL"; then
  pass "8  push form: bare-branch only; no HEAD:main / src:dst refspec"
else
  fail "8  push form: bare-branch assertion failed or a refspec form is present"
fi

# ────────────────────────────────────────────────────────────────────
# Case 9 — Tracking setup (WI 1.8)
# sanitize-pipeline-id.sh invocation; ZSKILLS_PIPELINE_ID echo; marker
# path under .zskills/tracking/$PIPELINE_ID/fulfilled.quickfix.<slug>;
# EXIT trap to finalize.
# ────────────────────────────────────────────────────────────────────
if grep -q 'scripts/sanitize-pipeline-id.sh' "$SKILL" \
   && grep -qE 'echo.*ZSKILLS_PIPELINE_ID=\$PIPELINE_ID' "$SKILL" \
   && grep -q 'fulfilled.quickfix' "$SKILL" \
   && grep -q "trap 'finalize_marker \$?' EXIT" "$SKILL"; then
  pass "9  tracking: sanitize + echo + marker path + EXIT trap"
else
  fail "9  tracking: one or more wiring elements missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 10 — Commit trailer contract (WI 1.13)
# user-edited has NO Co-Authored-By trailer; agent-dispatched DOES.
# Both carry a /quickfix mode-suffix footer enabling git log --grep.
# ────────────────────────────────────────────────────────────────────
# Extract the user-edited and agent-dispatched commit-body heredocs and
# check each independently. We slice the file around the mode-specific
# heredoc markers "Generated with /quickfix (user-edited)" and
# "Generated with /quickfix (agent-dispatched)", then assert the
# Co-Authored-By trailer is present in one and absent in the other.
USER_EDITED_BODY=$(awk '
  /🤖 Generated with \/quickfix \(user-edited\)/  { want=1; found=1 }
  want && /^COMMIT_EOF$/ { want=0 }
  want && found          { print }
' "$SKILL")

AGENT_BODY=$(awk '
  /🤖 Generated with \/quickfix \(agent-dispatched\)/  { want=1; found=1 }
  want && /^COMMIT_EOF$/ { want=0 }
  want && found          { print }
' "$SKILL")

if [ -n "$USER_EDITED_BODY" ] \
   && [ -n "$AGENT_BODY" ] \
   && ! printf '%s' "$USER_EDITED_BODY" | grep -q 'Co-Authored-By: Claude' \
   &&   printf '%s' "$AGENT_BODY"       | grep -q 'Co-Authored-By: Claude'; then
  pass "10 commit trailer: user-edited omits Co-Authored-By; agent-dispatched includes it"
else
  fail "10 commit trailer: trailer contract not satisfied"
  # Debug: show what we extracted.
  printf '  user-edited-body:\n%s\n' "$USER_EDITED_BODY" | sed 's/^/    /'
  printf '  agent-body:\n%s\n' "$AGENT_BODY" | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 14 — run-all.sh registration (Phase 1a acceptance criterion)
# `grep -c 'test-quickfix.sh' tests/run-all.sh` ≥ 1.
# This is a self-referential check: this very test file must be wired
# into the aggregator so `bash tests/run-all.sh` picks it up.
# ────────────────────────────────────────────────────────────────────
RA_COUNT=$(grep -c 'test-quickfix.sh' "$REPO_ROOT/tests/run-all.sh" 2>/dev/null || echo 0)
if [ "${RA_COUNT:-0}" -ge 1 ]; then
  pass "14 run-all.sh registration: $RA_COUNT occurrence(s) of test-quickfix.sh"
else
  fail "14 run-all.sh registration: test-quickfix.sh not found in tests/run-all.sh"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
