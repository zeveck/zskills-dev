#!/bin/bash
# test-no-conflict-markers.sh — CI guard against leftover git
# merge-conflict markers in tracked files.
#
# Closes #771. This is the regression guard for the #769 / PR #770
# class of bug: app.css shipped with literal `<<<<<<<` / `=======` /
# `>>>>>>>` lines (invalid CSS, broke the dashboard) and NO test caught
# it.
#
# DETECTION CONTRACT
# ------------------
# We match ONLY the unambiguous, label-bearing conflict-marker forms:
#   - lines beginning with `<<<<<<< ` (7 angle-brackets + a SPACE)
#   - lines beginning with `>>>>>>> ` (7 angle-brackets + a SPACE)
# A real merge conflict ALWAYS emits these opener/closer lines with a
# ref/label after the space, so matching them is sufficient to prove a
# conflict — you cannot have one without them.
#
# We deliberately do NOT match a bare `^=======$` (exactly 7 equals on
# its own line): that collides with Markdown setext-header underlines
# and `---`-style horizontal rules and would false-positive on docs.
#
# SCOPE + EXCLUDES
# ----------------
# We scan ALL tracked files via `git grep` (operates on committed/tracked
# content only — never untracked or .gitignore'd junk). The exclude list
# below is explicit and inspectable: each pathspec exclusion carries a
# comment explaining why. As of this writing the tree has ZERO hits, so
# the exclude list is empty — but it is kept here as the documented seam
# for any future legitimate marker-bearing file. The canary fixture
# tests/test-skill-version-canary-parallel-merge.sh holds marker strings
# only MID-LINE inside bash `[[ "$x" == *"<<<<<<<"* ]]` comparisons,
# which the strict `^<<<<<<< ` / `^>>>>>>> ` anchors do NOT match, so it
# needs no exclude.
#
# POSITIVE-CASE PROOF WITHOUT POISONING THE TREE
# ----------------------------------------------
# To prove the guard actually catches markers we do NOT commit a fixture
# containing real anchored `^<<<<<<< ` lines (that file would then be
# flagged by the guard scanning this very tree). Instead the negative
# test builds a throwaway git repo AT RUNTIME, plants the markers in a
# tracked file there, runs the exact detection command against it, and
# asserts it fires. Then the live test runs detection against the real
# repo and asserts it comes back clean.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# The canonical detection pattern. Anchored to start-of-line; requires a
# trailing space (label-bearing form). Shared by every test below and by
# the live tree scan so the guard and its proof use the SAME logic.
CONFLICT_RE='^(<<<<<<<|>>>>>>>) '

# Explicit, inspectable exclude list (git pathspec exclusions). Empty
# today — the tree is clean and the strict anchor sidesteps the only
# marker-bearing fixture. Add `:(exclude)<path>` entries WITH a comment
# if a future legitimate file must be skipped.
CONFLICT_EXCLUDES=(
  # (none — see header note on the canary fixture)
)

# ---------------------------------------------------------------------
# Test 1: the live repo tree is clean.
# This is the actual CI guard: it must catch a real leftover marker that
# slips into any tracked, shippable file.
# ---------------------------------------------------------------------
test_live_tree_clean() {
  local hits
  hits=$(cd "$REPO_ROOT" && git grep -nE "$CONFLICT_RE" -- . "${CONFLICT_EXCLUDES[@]}" 2>/dev/null)
  if [ -z "$hits" ]; then
    pass "no leftover conflict markers in tracked files"
  else
    fail "no leftover conflict markers in tracked files" \
      "found anchored conflict-marker lines:
$hits"
  fi
}

# ---------------------------------------------------------------------
# Test 2 (negative case): the detection logic FIRES on a planted marker.
# Build a throwaway git repo, commit a file with real anchored markers,
# run the exact detection command, and assert it returns a hit. This
# proves the guard works WITHOUT committing a marker fixture into the
# real tree (which would make Test 1 fail).
# ---------------------------------------------------------------------
test_detection_fires_on_planted_marker() {
  local tmp
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  (
    cd "$tmp" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    # Plant a file with real, anchored conflict markers.
    {
      printf '.foo {\n'
      printf '<<<<<<< HEAD\n'
      printf '  color: red;\n'
      printf '=======\n'
      printf '  color: blue;\n'
      printf '>>>>>>> feature-branch\n'
      printf '}\n'
    } > app.css
    git add app.css
    git commit -qm "plant conflict markers"
  )

  local hits
  hits=$(cd "$tmp" && git grep -nE "$CONFLICT_RE" -- . 2>/dev/null)
  if [ -n "$hits" ]; then
    pass "detection fires on planted anchored markers (runtime fixture)"
  else
    fail "detection fires on planted anchored markers (runtime fixture)" \
      "detection returned no hits on a file that contains real markers"
  fi
}

# ---------------------------------------------------------------------
# Test 3 (false-positive guard): the strict anchor does NOT match a bare
# `^=======$` line (markdown setext underline / horizontal rule), nor
# mid-line marker strings like `*"<<<<<<<"*`. Proves the pattern won't
# flag the legitimate canary fixture or docs.
# ---------------------------------------------------------------------
test_detection_ignores_benign_lines() {
  local tmp
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  (
    cd "$tmp" || exit 1
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    {
      printf 'Heading\n'
      printf '=======\n'                          # markdown setext underline
      printf 'some prose\n'
      printf 'if [[ "$x" == *"<<<<<<<"* ]]; then\n' # mid-line marker string
      printf '  echo hi\n'
      printf 'fi\n'
      printf 'a <<<<<<< inline reference\n'         # marker not at line start
    } > doc.md
    git add doc.md
    git commit -qm "benign marker-like content"
  )

  local hits
  hits=$(cd "$tmp" && git grep -nE "$CONFLICT_RE" -- . 2>/dev/null)
  if [ -z "$hits" ]; then
    pass "detection ignores setext '=======' / mid-line marker strings"
  else
    fail "detection ignores setext '=======' / mid-line marker strings" \
      "strict anchor false-positived on benign content:
$hits"
  fi
}

# ---------------------------------------------------------------------
# Test 4: the real canary fixture is specifically NOT flagged.
# This is the named acceptance case from the issue.
# ---------------------------------------------------------------------
test_canary_fixture_not_flagged() {
  local fixture="tests/test-skill-version-canary-parallel-merge.sh"
  if [ ! -f "$REPO_ROOT/$fixture" ]; then
    pass "canary fixture absent (assertion skipped)"
    return
  fi
  local hits
  hits=$(cd "$REPO_ROOT" && git grep -nE "$CONFLICT_RE" -- "$fixture" 2>/dev/null)
  if [ -z "$hits" ]; then
    pass "canary parallel-merge fixture is not flagged"
  else
    fail "canary parallel-merge fixture is not flagged" \
      "strict anchor matched marker strings in the canary fixture:
$hits"
  fi
}

echo "=== leftover-conflict-marker guard tests ==="
test_live_tree_clean
test_detection_fires_on_planted_marker
test_detection_ignores_benign_lines
test_canary_fixture_not_flagged

echo ""
echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ]
