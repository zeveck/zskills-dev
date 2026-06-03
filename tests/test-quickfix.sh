#!/bin/bash
# Tests for skills/quickfix/SKILL.md — structural + behavioral coverage.
#
# Phase 1a (cases 1-10, 14) covers argument parsing, slug derivation,
# branch-name contract, and static wiring of the gates.
#
# Phase 1b (cases 11-35) adds:
#   - Structural regression guards BY NUMBER (11, 33, 34) that catch
#     past-seen failures — push-refspec reintroduction, rm-rf-var
#     reintroduction, || true reintroduction.
#   - Load-bearing config-gate cases BY NUMBER (18, 19, 20) that run
#     a trimmed-to-preflight copy of the skill against a fixture repo
#     and assert exit codes plus discriminator keywords.
#   - Happy-path end-to-end fixtures (both modes' commit-trailer
#     contract, cancel path, untracked inclusion, test-cmd rollback).
#   - Edge-case behavior: concurrent invocation, stale marker, remote
#     collision, agent no-op, path with spaces, dirty-after excludes
#     untracked, cleanup exit 6, ls-remote network failure.
#
# Harness per plan WI 1.17: per-case `mktemp -d -t zskills-quickfix.XXXXXX`
# under /tmp/ (so `is_safe_destruct` allows rm -rf on teardown), init a
# mini repo, clone a bare-remote alongside, write a mock
# .claude/zskills-config.json with aligned unit_cmd/full_cmd, and mock
# `gh` via a PATH wrapper that echoes a fake URL.
#
# Idiom base: tests/test-hooks.sh:226-254 (setup_project_test).
# Fixture-repo-under-/tmp base: tests/test-create-worktree.sh:22 (case 22).
#
# Run from repo root: bash tests/test-quickfix.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/quickfix/SKILL.md"
# Issue #836: /quickfix was split into a router SKILL.md (frontmatter →
# Phase 2 mode detection + branch creation) plus two mode files and a
# reference. Content the lifecycle greps below key on now lives in:
#   - SKILL_EXECUTE — Phases 3–6 (make-the-change → test gate → commit →
#     verify → push)
#   - SKILL_LAND    — Phase 7 (PR creation, CI poll, /land-pr caller loop,
#     explicit-finalize) + terminal-marker-states prose
#   - SKILL_REFS    — Exit codes + Key Rules
# Assertions that previously grepped the single $SKILL were repointed to
# the file the literal actually moved into (the asserted literal is what
# matters, not the file). Whole-lifecycle assertions use $SKILL_ALL, a
# temp concatenation of all four files.
SKILL_EXECUTE="$REPO_ROOT/skills/quickfix/modes/execute.md"
SKILL_LAND="$REPO_ROOT/skills/quickfix/modes/land.md"
SKILL_REFS="$REPO_ROOT/skills/quickfix/references/exit-codes-and-rules.md"

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
#
# WI 1.6 is now model-composed: the model sets $SLUG before any bash
# fence runs, and a bash validator enforces shape. Tests that drive the
# preflight slice set $SLUG explicitly in the environment (via the
# `SLUG=…` prefix on the `bash "$PREFLIGHT_SCRIPT" …` invocation). A
# harness-wide default is also injected into the extracted preflight /
# full-flow scripts below so cases that only exercise pre-slug gates
# (e.g. landing-gate, gh-gate, test-cmd gate) still proceed.

# Per-run scratch directory; never under $REPO_ROOT so `git status` stays clean.
TEST_TMPDIR="/tmp/zskills-quickfix-test-$$"
mkdir -p "$TEST_TMPDIR"

# Whole-lifecycle concatenation (issue #836): some structural greps assert
# a literal appears SOMEWHERE in the /quickfix lifecycle, not in one
# specific phase. After the split those literals live across SKILL.md +
# the two mode files + the reference; $SKILL_ALL lets such greps stay
# file-agnostic. Located-content greps (push form, caller loop, etc.)
# still target the specific file the content moved into.
SKILL_ALL="$TEST_TMPDIR/skill-all.md"
cat "$SKILL" "$SKILL_EXECUTE" "$SKILL_LAND" "$SKILL_REFS" > "$SKILL_ALL"

# List of per-case fixture dirs so the EXIT trap can purge them all. Each
# case that uses a fixture pushes onto FIXTURES[].
FIXTURES=()
register_fixture() { FIXTURES+=("$1"); }

cleanup() {
  local f
  for f in "${FIXTURES[@]:-}"; do
    [ -z "$f" ] && continue
    # Literal /tmp/ path guard — hook's is_safe_destruct requires no $ in
    # the command, but this trap runs inside the test script (not a tool
    # call), so the hook does not inspect it. Still: defence-in-depth.
    if [ -d "$f" ] && [[ "$f" == /tmp/* ]]; then
      rm -rf -- "$f" 2>/dev/null || true
    fi
  done
  rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT

# ──────────────────────────────────────────────────────────────────────
# Fixture builder: init a fresh git repo + bare-remote clone + mock
# `.claude/zskills-config.json` + PATH-shadow `gh` wrapper. Returns the
# fixture dir via stdout; the caller uses `cd "$FIX"`.
#
# Modeled on test-hooks.sh:395-416 (setup_project_test) and extended for
# the quickfix harness needs (bare remote + gh mock + aligned
# unit_cmd/full_cmd).
# ──────────────────────────────────────────────────────────────────────
make_fixture() {
  local name="$1"              # short slug used in the tmpdir name
  # ${var-default} (no colon) lets the caller pass EMPTY strings to
  # disable unit_cmd/full_cmd (load-bearing for cases 18, 19, 20).
  # Defaults apply only when the argument is UNSET.
  local unit_cmd="${2-true}"   # aligned with full_cmd by default
  local full_cmd="${3-$unit_cmd}"
  local landing="${4-pr}"
  local branch_prefix="${5-quickfix/}"

  local fix
  fix=$(mktemp -d -t "zskills-quickfix.$name.XXXXXX")
  register_fixture "$fix"

  # Bare remote adjacent to the fixture.
  local bare="$fix.bare"
  register_fixture "$bare"

  # Init repo with branch=main and a seed commit.
  git init --quiet -b main "$fix"
  git -C "$fix" config user.email "t@t"
  git -C "$fix" config user.name "t"
  echo "seed" > "$fix/README.md"
  # .gitignore must exclude the harness scaffolding from the skill's
  # mode-detection DIRTY_FILES set — .claude/, scripts/, bin/, and the
  # tracking directory are test harness, not "user edits".
  cat > "$fix/.gitignore" <<'GITIGNORE'
.claude/
scripts/
bin/
.zskills/
GITIGNORE
  git -C "$fix" add README.md .gitignore
  git -C "$fix" commit --quiet -m "seed"

  # Bare-remote clone so `git push -u origin main` and `git ls-remote origin`
  # both succeed. The skill's ls-remote-based remote-collision gate and
  # final `git push -u origin $BRANCH` both target `origin`.
  # All output is suppressed because this function's stdout must contain
  # ONLY the fixture path (callers use `FIX=$(make_fixture ...)`).
  git clone --quiet --bare "$fix" "$bare" >/dev/null 2>&1
  git -C "$fix" remote add origin "$bare" >/dev/null 2>&1
  git -C "$fix" fetch --quiet origin >/dev/null 2>&1
  git -C "$fix" branch --set-upstream-to=origin/main main >/dev/null 2>&1

  # Provide the scripts the skill depends on (sanitize-pipeline-id.sh).
  # Issue #868: skill now resolves the sanitize path via $ZSKILLS_SKILLS_ROOT
  # (set by zskills-resolve-config.sh, which sources zskills-paths.sh). Both
  # helpers also need to ship in the fixture so the skill's `.` source line
  # actually exports the variable.
  mkdir -p "$fix/.claude/skills/create-worktree/scripts"
  cp "$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$fix/.claude/skills/create-worktree/scripts/"
  chmod +x "$fix/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
  mkdir -p "$fix/.claude/skills/update-zskills/scripts"
  cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-resolve-config.sh" "$fix/.claude/skills/update-zskills/scripts/"
  cp "$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh" "$fix/.claude/skills/update-zskills/scripts/"
  chmod +x "$fix/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  chmod +x "$fix/.claude/skills/update-zskills/scripts/zskills-paths.sh"

  # Config with aligned unit_cmd / full_cmd (default: `true` passes).
  mkdir -p "$fix/.claude"
  cat > "$fix/.claude/zskills-config.json" <<JSON
{
  "execution": { "landing": "$landing", "branch_prefix": "$branch_prefix" },
  "testing":   { "unit_cmd": "$unit_cmd", "full_cmd": "$full_cmd" }
}
JSON

  # gh PATH-shadow: echoes a stable fake URL so the skill's
  # `PR_URL=$(gh pr create …)` succeeds deterministically.
  mkdir -p "$fix/bin"
  cat > "$fix/bin/gh" <<'SHELL'
#!/bin/bash
# Mock gh: handle `pr create` by printing a fake URL; anything else → 0.
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "create" ]; then
  echo "https://github.com/owner/repo/pull/1"
  exit 0
fi
exit 0
SHELL
  chmod +x "$fix/bin/gh"

  printf '%s\n' "$fix"
}

# ──────────────────────────────────────────────────────────────────────
# Extract the pre-flight slice of SKILL.md (through WI 1.9 branch
# creation) as a runnable script. Later cases run this slice with
# different configs / environments to exercise the exit-code + stderr
# contract end-to-end. We stop at the end of WI 1.9 so cases don't need
# the full commit/push/gh path; the slice is enough to exercise every
# gate the plan's load-bearing cases require.
#
# The plan keeps SKILL.md as the source of truth; this extractor lets
# the tests exercise the exact bash, not a hand-ported copy.
# ──────────────────────────────────────────────────────────────────────
extract_preflight() {
  # Extract bash fences from the SKILL.md, but stop at Phase 3
  # (user-edited / agent-dispatched — which require interactive input
  # and agent dispatch, not covered here). The slice ends at the
  # "## Phase 3 — Make the change" header.
  awk '
    /^## Phase 3 — Make the change/ { stop=1 }
    stop                            { next }
    /^```bash$/                     { infence=1; next }
    infence && /^```$/              { infence=0; print ""; next }
    infence                         { print }
  ' "$SKILL"
}

# Extract to a shared helper script for the cases that run it.
#
# WI 1.6 is model-composed: the model sets $SLUG before the validator
# fence runs. The test harness simulates that by injecting a default
# `SLUG` from the environment (or falling back to a harness default) at
# the top of the extracted script. Individual cases that care about a
# specific slug export `SLUG=…` before invoking.
PREFLIGHT_SCRIPT="$TEST_TMPDIR/preflight.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  echo ': "${SLUG:=fix-stub}"'
  # The skill sources zskills-resolve-config.sh which requires
  # CLAUDE_PROJECT_DIR. Inside a test fixture, $(pwd) equals $FIX (the
  # fixture root) — use it as the project dir so the helper finds
  # .claude/zskills-config.json under the fixture.
  echo ': "${CLAUDE_PROJECT_DIR:=$(pwd)}"'
  echo 'export CLAUDE_PROJECT_DIR'
  # Legacy-lane faithful under the generated script's `set -u`: production
  # fences run WITHOUT `set -u`, so the new resolution idiom's bare
  # ${CLAUDE_PLUGIN_ROOT} token expands empty → else/legacy branch. Bind it
  # EMPTY (not a real path) so the same legacy else-branch is exercised without
  # an unbound-variable abort under the injected `set -u`.
  echo ': "${CLAUDE_PLUGIN_ROOT:=}"'
  echo 'export CLAUDE_PLUGIN_ROOT'
  extract_preflight
} > "$PREFLIGHT_SCRIPT"
chmod +x "$PREFLIGHT_SCRIPT"

# Full end-to-end flow extractor — preflight + mode + slug + branch +
# WI 1.10 (user-edited diff-and-maybe-prompt) + WI 1.12 test gate +
# WI 1.13 commit + WI 1.14 push. Skips WI 1.11 (agent-dispatched mode
# is a model-layer instruction; its lone bash snippet unconditionally
# overwrites $CHANGED_FILES from $DIRTY_AFTER which doesn't exist in
# user-edited mode, so running it would break the test).
#
# PHASE 5 (PR_LANDING_UNIFICATION) NOTE: WI 1.15 (Phase 7) used to be
# a pure-bash inline `gh pr create` that the extractor included end-to-
# end. After Phase 5 migrated /quickfix to dispatch /land-pr via the
# Skill tool, Phase 7 is no longer self-contained bash — its main
# action is a comment-form Skill-tool invocation that the bash
# extractor cannot execute (it would loop forever waiting for a
# $RESULT_FILE that no real /land-pr call produces). The extractor
# therefore stops at the start of `## Phase 7`. Case 43 below asserts
# the user-edited-mode flow end-to-end through push (preflight →
# branch → test gate → commit → push), and a separate structural
# assertion (Case 43b) verifies that Phase 7 dispatches /land-pr with
# the WI 1.16 `pr: $PR_URL` marker-append idiom on the result. The
# real /land-pr integration is exercised by /land-pr's own test
# scripts (tests/test-land-pr-scripts.sh) and by the Phase 6 cron-fire
# canary.
extract_full_flow() {
  # Issue #836: Phases 3–6 (WI 1.10 user-edited, WI 1.12 test gate, WI
  # 1.13 commit, WI 1.14 push) moved from SKILL.md into modes/execute.md.
  # The full-flow extractor therefore reads SKILL.md (frontmatter → Phase
  # 2 branch creation) THEN modes/execute.md (Phases 3–6). Phase 7 is in
  # modes/land.md and still extractor-excluded (its dispatch is a
  # comment-form Skill-tool invocation bash cannot run); the `## Phase 7`
  # stop guard is retained as defence-in-depth in case content moves back.
  awk '
    /^### WI 1\.11/         { skip = 1 }
    /^## Phase 4/           { skip = 0 }
    /^## Phase 7/           { stop = 1 }
    stop                    { next }
    skip                    { next }
    /^```bash$/             { infence = 1; next }
    infence && /^```$/      { infence = 0; print ""; next }
    infence                 { print }
  ' "$SKILL" "$SKILL_EXECUTE"
}

FULL_FLOW_SCRIPT="$TEST_TMPDIR/full-flow.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  # WI 1.6 and 1.13 expect the model to set shell variables (SLUG,
  # COMMIT_SUBJECT) before the corresponding bash validator/commit
  # fences run. The fixture simulates those model-layer composition
  # steps so the bash extraction can test the rest of the flow (branch
  # creation, test gate, commit, push) end-to-end through Phase 6.
  # PR_TITLE is set too — even though Phase 7 is now extractor-
  # excluded post-PR_LANDING_UNIFICATION (Skill-tool dispatch can't
  # run as bash), keeping PR_TITLE defined is harmless and would let
  # the extractor reinclude Phase 7's pre-loop validator if a future
  # refactor moves it back into self-contained bash. Individual cases
  # that care about a specific slug export `SLUG=…` before invoking;
  # the default below makes cases that don't care "just work".
  echo ': "${SLUG:=fix-stub}"'
  echo 'COMMIT_SUBJECT="test(case43): synthetic conventional-commit subject"'
  echo 'PR_TITLE="test: synthetic PR title"'
  # The skill sources zskills-resolve-config.sh which requires
  # CLAUDE_PROJECT_DIR. The fixture cd's into $FIX before running, so
  # $(pwd) equals the fixture root.
  echo ': "${CLAUDE_PROJECT_DIR:=$(pwd)}"'
  echo 'export CLAUDE_PROJECT_DIR'
  # Legacy-lane faithful under the generated script's `set -u`: bind the new
  # resolution idiom's bare ${CLAUDE_PLUGIN_ROOT} token EMPTY (not a real path)
  # so the legacy else-branch is exercised without an unbound-variable abort.
  echo ': "${CLAUDE_PLUGIN_ROOT:=}"'
  echo 'export CLAUDE_PLUGIN_ROOT'
  extract_full_flow
} > "$FULL_FLOW_SCRIPT"
chmod +x "$FULL_FLOW_SCRIPT"

# ──────────────────────────────────────────────────────────────────────
# Argument-parser-only extractor (Phase 1b cases 44–46).
#
# Cases 44–46 exercise the `## Argument parser (WI 1.2)` parser fence in
# isolation — without preflight side effects (no git, no config, no
# tracking dir). The fence lives between `## Argument parser (WI 1.2)`
# and `## Phase 1 — Pre-flight`; there is exactly one ```bash fence in
# that range. We extract it, wrap it as a script that echoes the parser
# outputs (FORCE / ROUNDS / DESCRIPTION), and exec against synthetic
# arg vectors.
# ──────────────────────────────────────────────────────────────────────
extract_parser() {
  awk '
    /^## Argument parser/         { in_section = 1; next }
    /^## Phase 1/                 { in_section = 0 }
    !in_section                   { next }
    /^```bash$/                   { infence = 1; next }
    infence && /^```$/            { infence = 0; print ""; next }
    infence                       { print }
  ' "$SKILL"
}

PARSER_SCRIPT="$TEST_TMPDIR/parser.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  extract_parser
  # Emit results in a stable, parseable form for assertions.
  echo 'printf "FORCE=%s\n" "$FORCE"'
  echo 'printf "ROUNDS=%s\n" "$ROUNDS"'
  echo 'printf "DESCRIPTION=%s\n" "$DESCRIPTION"'
  echo 'printf "FROM_HERE=%s\n" "$FROM_HERE"'
  echo 'printf "SKIP_TESTS=%s\n" "$SKIP_TESTS"'
  echo 'printf "BRANCH_OVERRIDE=%s\n" "$BRANCH_OVERRIDE"'
  echo 'printf "AUTO_FLAG=%s\n" "$AUTO_FLAG"'
  # Also report whether the entry-point unset guard cleared the seam vars.
  echo 'printf "TRIAGE_VAR_STATE=%s\n" "${_ZSKILLS_TEST_TRIAGE_VERDICT-UNSET}"'
  echo 'printf "REVIEW_VAR_STATE=%s\n" "${_ZSKILLS_TEST_REVIEW_VERDICT-UNSET}"'
} > "$PARSER_SCRIPT"
chmod +x "$PARSER_SCRIPT"

echo "=== quickfix — structural and algorithmic invariants ==="

# ────────────────────────────────────────────────────────────────────
# Case 1 — YAML frontmatter (WI 1.1)
# Note: disable-model-invocation was lifted in #287 so the Skill-tool
# can dispatch /quickfix from /fix-issues' middle-tier triage. The
# previous assertion that the flag MUST be present is obsolete; the
# new invariant is that the flag must be ABSENT (or not set true).
# ────────────────────────────────────────────────────────────────────
if grep -q '^name: quickfix$' "$SKILL" \
   && grep -q '^argument-hint: "\[<description>\]' "$SKILL" \
   && ! grep -q '^disable-model-invocation: true$' "$SKILL"; then
  pass "1  frontmatter: name/argument-hint present, dmi-true absent (per #287)"
else
  fail "1  frontmatter: missing one of name|argument-hint, OR dmi-true still present"
fi

# ────────────────────────────────────────────────────────────────────
# Case 2 — Argument-parser flags (WI 1.2)
# Post-migration-redirect-removal: --yes / --from-here / --skip-tests /
# --force migration arms were dropped entirely (per
# feedback_no_premature_backcompat.md). Only positional bracket-class
# tokens remain (plus --branch / --rounds value-takers).
# ────────────────────────────────────────────────────────────────────
if grep -q '[-][-]branch)' "$SKILL" \
   && grep -qE '^[[:space:]]*\[fF\]\[rR\]\[oO\]\[mM\]-\[hH\]\[eE\]\[rR\]\[eE\]\) FROM_HERE=1' "$SKILL" \
   && grep -qE '^[[:space:]]*\[sS\]\[kK\]\[iI\]\[pP\]-\[tT\]\[eE\]\[sS\]\[tT\]\[sS\]\) SKIP_TESTS=1' "$SKILL" \
   && grep -qE '^[[:space:]]*--force\) FORCE=1' "$SKILL" \
   && ! grep -qE '^[[:space:]]*\[fF\]\[oO\]\[rR\]\[cC\]\[eE\]\) FORCE=1' "$SKILL" \
   && grep -qE '^[[:space:]]*\[aA\]\[uU\]\[tT\]\[oO\]\)' "$SKILL"; then
  pass "2  argument parser: --branch + positional from-here/skip-tests/auto + --force (dashed; issue #810)"
else
  fail "2  argument parser: one or more arms missing OR bare 'force' bracket-class arm still present"
fi

# ────────────────────────────────────────────────────────────────────
# Case 3 — SLUG validator-shape contract (WI 1.6)
#
# WI 1.6 is now model-composed: the model sets $SLUG, a bash validator
# enforces shape. This case table-drives the validator regex + length
# cap by running the actual fence block from the skill and asserting
# that valid SLUGs pass and malformed ones fail with the expected exit
# code. Regex: `^[a-z0-9]+(-[a-z0-9]+)*$`; max length 40.
# ────────────────────────────────────────────────────────────────────
slug_validator() {
  local slug="$1"
  # Exact fence copy of WI 1.6's validator — kept in sync with the
  # skill source. If this block drifts from skills/quickfix/SKILL.md
  # WI 1.6, the test suite falsely passes; a targeted grep below
  # asserts the fence is still present in source.
  if [ -z "${slug:-}" ]; then
    return 5
  fi
  if ! [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || [ ${#slug} -gt 40 ]; then
    return 2
  fi
  return 0
}
slug_accept() {
  local label="$1" input="$2"
  slug_validator "$input"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "3  slug accept: $label ('$input')"
  else
    fail "3  slug accept: $label ('$input') — got rc=$rc, expected 0"
  fi
}
slug_reject() {
  local label="$1" input="$2" expected_rc="$3"
  slug_validator "$input"
  local rc=$?
  if [ "$rc" -eq "$expected_rc" ]; then
    pass "3  slug reject: $label ('$input') → rc=$rc"
  else
    fail "3  slug reject: $label ('$input') — got rc=$rc, expected $expected_rc"
  fi
}
slug_accept "single char"                "a"
slug_accept "two segments"               "a-b"
slug_accept "alphanumeric segments"      "ab-cd"
slug_accept "typical 3-word"             "fix-readme-typo"
slug_reject "uppercase"                  "Foo"                                             2
slug_reject "leading dash"               "-foo"                                            2
slug_reject "trailing dash"              "foo-"                                            2
slug_reject "double dash"                "a--b"                                            2
slug_reject "empty"                      ""                                                5
slug_reject "slash"                      "a/b"                                             2
slug_reject "41-char overflow"           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"       2

# Also assert the validator fence itself is still literally present
# in the skill source (guards against drift between test and skill).
if grep -qE '^\s*echo "ERROR: SLUG not set — model-layer composition step skipped\."' "$SKILL" \
   && grep -qE '^\s*if \! \[\[ "\$SLUG" =~ \^\[a-z0-9\]\+\(-\[a-z0-9\]\+\)\*\$ \]\] \|\| \[ \$\{#SLUG\} -gt 40 \]; then' "$SKILL"; then
  pass "3  slug validator fence: present in skill source"
else
  fail "3  slug validator fence: NOT present in skill source — test harness and skill have drifted"
fi

# ────────────────────────────────────────────────────────────────────
# Case 4 — Branch-name contract (WI 1.7)
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
# ────────────────────────────────────────────────────────────────────
if grep -q 'testing.unit_cmd' "$SKILL" \
   && grep -q 'testing.full_cmd' "$SKILL" \
   && grep -q 'full_cmd.*!=.*unit_cmd\|"\$FULL_CMD" != "\$UNIT_CMD"' "$SKILL"; then
  pass "5  test-cmd alignment gate: unit_cmd set AND full_cmd==unit_cmd check present"
else
  fail "5  test-cmd alignment gate: wiring not found"
fi

# ────────────────────────────────────────────────────────────────────
# Case 6 — Landing gate wiring (WI 1.3 check 3, soft-redirect form per #293)
#
# Post-#293: the hard error was replaced with a two-line redirect using
# the WI 1.5.4 printf template. Wiring assertion: LANDING is read AND
# both worktree → /do worktree AND direct → /commit redirect branches
# are present in the bash check, AND each branch exits 0.
# ────────────────────────────────────────────────────────────────────
if grep -q 'execution.landing' "$SKILL" \
   && grep -qE '\[ "\$LANDING" = "worktree" \]' "$SKILL" \
   && grep -qE '\[ "\$LANDING" = "direct" \]' "$SKILL" \
   && grep -q 'redirecting to /do worktree' "$SKILL" \
   && grep -q 'redirecting to /commit' "$SKILL"; then
  pass "6  landing gate: execution.landing read; worktree → /do, direct → /commit soft-redirects present"
else
  fail "6  landing gate: soft-redirect wiring not found"
fi

# ────────────────────────────────────────────────────────────────────
# Case 7 — Mode detection truth table (WI 1.5)
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
# ────────────────────────────────────────────────────────────────────
# Issue #836: WI 1.14 push moved to modes/execute.md; the refspec-absence
# guard runs over the whole lifecycle ($SKILL_ALL).
if grep -qE 'git push -u origin "\$BRANCH"' "$SKILL_EXECUTE" \
   && ! grep -qE 'HEAD:main|HEAD:master' "$SKILL_ALL" \
   && ! grep -qE 'git push [^|]*:' "$SKILL_ALL"; then
  pass "8  push form: bare-branch only; no HEAD:main / src:dst refspec"
else
  fail "8  push form: bare-branch assertion failed or a refspec form is present"
fi

# ────────────────────────────────────────────────────────────────────
# Case 9 — Tracking setup (WI 1.8) — explicit-finalize, NO trap.
#
# Issue #241 (2026-05-14): the prior `trap 'finalize_marker $?' EXIT`
# pattern fired when WI 1.8's bash code fence ended (skill entry), NOT
# when the skill flow ended — every /quickfix invocation stamped
# `status: complete` almost immediately regardless of actual outcome.
# Fix: replace with explicit-finalize matching /commit pr / /do pr /
# /fix-issues pr — start-marker write at WI 1.8 (unchanged); end-of-
# Phase-7-fence finalize based on $LAND_OUTCOME; per-failure-path
# inline `sed -i` cleanup at WI 1.10 / Phase 4 / 5 / 6 / no-result.
#
# Assertions:
#   (a) WI 1.8 wiring elements still present (sanitize + echo + marker path).
#   (b) The trap literal is GONE from source (regression guard against
#       reintroducing the broken pattern).
#   (c) The explicit-finalize block (matching /commit pr) is present:
#       a `case "${LAND_OUTCOME:-__init__}" in` followed by a sed -i
#       rewriting `status: started` → `status: $FINAL`.
# ────────────────────────────────────────────────────────────────────
# Issue #836: WI 1.8 tracking setup (sanitize + echo + fulfilled.quickfix)
# stays in SKILL.md; the LAND_OUTCOME case + explicit sed-finalize moved to
# modes/land.md. The trap-absence regression guard runs over the whole
# lifecycle ($SKILL_ALL).
TRAP_LITERAL_COUNT=$(grep -c "trap 'finalize_marker \$?' EXIT" "$SKILL_ALL" 2>/dev/null | head -1)
TRAP_LITERAL_COUNT=${TRAP_LITERAL_COUNT:-0}
LAND_OUTCOME_FINALIZE=$(grep -c 'case "${LAND_OUTCOME:-__init__}" in' "$SKILL_LAND" 2>/dev/null | head -1)
LAND_OUTCOME_FINALIZE=${LAND_OUTCOME_FINALIZE:-0}
EXPLICIT_SED=$(grep -cE 'sed -i "s/\^status: started\$/status: \$FINAL/"' "$SKILL_LAND" 2>/dev/null | head -1)
EXPLICIT_SED=${EXPLICIT_SED:-0}

# Issue #868: dual-lane migration — sanitize-pipeline-id.sh path is now
# resolved via $ZSKILLS_SKILLS_ROOT (set by zskills-resolve-config.sh)
# instead of the mirror-only $MAIN_ROOT/.claude/skills/ literal that broke
# plugin-lane consumers. Accept either the lane-portable resolved form OR
# any direct `create-worktree/scripts/sanitize-pipeline-id.sh` suffix.
if grep -qE 'create-worktree/scripts/sanitize-pipeline-id\.sh' "$SKILL" \
   && grep -qE 'echo.*ZSKILLS_PIPELINE_ID=\$PIPELINE_ID' "$SKILL" \
   && grep -q 'fulfilled.quickfix' "$SKILL" \
   && [ "$TRAP_LITERAL_COUNT" -eq 0 ] \
   && [ "$LAND_OUTCOME_FINALIZE" -ge 1 ] \
   && [ "$EXPLICIT_SED" -ge 1 ]; then
  pass "9  tracking: sanitize + echo + marker path; trap gone; LAND_OUTCOME case + explicit sed-finalize present (issue #241)"
else
  fail "9  tracking: trap-literal-count=$TRAP_LITERAL_COUNT (want 0), land-outcome-case=$LAND_OUTCOME_FINALIZE (want >=1), explicit-sed=$EXPLICIT_SED (want >=1)"
fi

# Issue #868 regression guard: the mirror-only `.claude/skills/...`
# sanitize-pipeline-id path MUST NOT come back. Both the source SKILL.md
# and the legacy-lane mirror MUST resolve the script via a lane-portable
# variable (typically $ZSKILLS_SKILLS_ROOT).
MIRROR_ONLY_SANITIZE=$(grep -cE '\.claude/skills/create-worktree/scripts/sanitize-pipeline-id\.sh' "$SKILL" 2>/dev/null | head -1)
MIRROR_ONLY_SANITIZE=${MIRROR_ONLY_SANITIZE:-0}
if [ "$MIRROR_ONLY_SANITIZE" -eq 0 ]; then
  pass "9b tracking: mirror-only .claude/skills/.../sanitize-pipeline-id.sh path absent from SKILL.md (issue #868)"
else
  fail "9b tracking: mirror-only .claude/skills/.../sanitize-pipeline-id.sh path STILL PRESENT in SKILL.md (count=$MIRROR_ONLY_SANITIZE) — breaks plugin-lane consumers (issue #868)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 10 — Commit trailer contract (WI 1.13). Model composes
# COMMIT_SUBJECT; bash fence composes the body from it + DESCRIPTION.
# Asserts the design invariants textually:
#   - Both mode-specific footers present: "Generated with /quickfix
#     (user-edited)" and "(agent-dispatched)".
#   - Co-Authored-By line uses $COMMIT_CO_AUTHOR (resolved by the
#     canonical helper zskills-resolve-config.sh, not hardcoded).
#   - co_author field referenced (resolution logic now in the helper —
#     no BASH_REMATCH for co_author in the skill itself post-Phase-2
#     drift fix).
#   - user-edited branch has NO Co-Authored-By trailer; the trailer
#     also gates on $COMMIT_CO_AUTHOR being non-empty (consumer opt-out
#     when blank).
# ────────────────────────────────────────────────────────────────────
# Issue #836: WI 1.13 commit (trailer composition) moved to modes/execute.md.
COAUTH_COUNT=$(grep -c 'Co-Authored-By: \$COMMIT_CO_AUTHOR' "$SKILL_EXECUTE" 2>/dev/null || echo 0)
if grep -qE 'Generated with /quickfix \(user-edited\)' "$SKILL_EXECUTE" \
   && grep -qE 'Generated with /quickfix \(agent-dispatched\)' "$SKILL_EXECUTE" \
   && [ "$COAUTH_COUNT" = "1" ] \
   && grep -q 'co_author' "$SKILL_EXECUTE" \
   && grep -q 'zskills-resolve-config\.sh' "$SKILL_EXECUTE"; then
  pass "10 commit trailer: both mode footers + single agent-only Co-Authored-By: \$COMMIT_CO_AUTHOR + helper-sourced"
else
  fail "10 commit trailer: contract not satisfied (coauth_count=$COAUTH_COUNT)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 11 — LOAD-BEARING push-refspec absence (per plan lines 44, 64).
# `grep -E 'git push [^|]*:' skills/quickfix/SKILL.md` MUST find nothing.
# If this fires, someone reintroduced a src:dst refspec push that could
# bypass the protected-ref guard in hooks/block-unsafe-generic.sh:215-220.
# ────────────────────────────────────────────────────────────────────
# Issue #836: refspec-absence guard runs over the whole lifecycle.
REFSPEC_MATCHES=$(grep -cE 'git push [^|]*:' "$SKILL_ALL" 2>/dev/null)
REFSPEC_MATCHES=${REFSPEC_MATCHES:-0}
if [ "$REFSPEC_MATCHES" -eq 0 ]; then
  pass "11 push-refspec absence (load-bearing): grep returns zero matches"
else
  fail "11 push-refspec absence: found $REFSPEC_MATCHES match(es) — refspec form reintroduced"
fi

# ────────────────────────────────────────────────────────────────────
# Case 12 — pr: $PR_URL marker append (WI 1.16).
# On success, the marker must carry a `pr:` line. The SKILL.md must
# contain the `printf 'pr: %s\n' "$PR_URL" >> "$MARKER"` idiom (or
# equivalent append).
# ────────────────────────────────────────────────────────────────────
# Issue #836: WI 1.16 pr:-append lives in Phase 7 → modes/land.md.
if grep -qE "printf 'pr:[^']*'[[:space:]]+\"\\\$PR_URL\"[[:space:]]+>>[[:space:]]+\"\\\$MARKER\"" "$SKILL_LAND"; then
  pass "12 pr: URL marker append: printf-append idiom present (WI 1.16)"
else
  fail "12 pr: URL marker append: printf-append idiom missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 13 — .landed marker is NOT written (load-bearing rule).
# /quickfix has no worktree, so .landed must never appear in any
# write path. Per Phase 1b acceptance criterion:
# `grep -qE '(write|cat >).*\.landed' skills/quickfix/SKILL.md` FAILS.
# Documentation mentions of ".landed" in prose are allowed — only the
# act of WRITING to a .landed file is forbidden.
#
# PHASE 5 NOTE: Phase 5 added prose at WI 1.15 explaining the
# coexistence of /quickfix's fulfillment-marker model with /land-pr's
# .landed model — including the literal phrase "does NOT write a
# `.landed` marker". The original regex `(write|cat >).*\.landed`
# matched that prose (a `write` token followed by `.landed`) even
# though no actual code-write targets `.landed`. Tightened to match
# only a true write operation: a redirection operator (`>`, `>>`)
# followed by a path component ending in `.landed`. This is the
# write idiom across the codebase (e.g. /do/modes/pr.md uses
# `cat > "$WORKTREE_PATH/.landed"`). Prose mentions of "write a
# `.landed` marker" no longer false-positive. The assertion is
# STRENGTHENED, not weakened: it now requires an actual redirect
# operator, ruling out prose without losing any code-write patterns
# the loose pattern would have caught (every code-form .landed write
# in the codebase uses `>` or `>>`).
# ────────────────────────────────────────────────────────────────────
# Issue #836: .landed-write absence guard runs over the whole lifecycle.
if ! grep -qE '>>?[[:space:]]*"?[^"[:space:]]*\.landed' "$SKILL_ALL"; then
  pass "13 .landed never written: no redirect targets a .landed file"
else
  fail "13 .landed never written: a > or >> redirect targets .landed"
  grep -nE '>>?[[:space:]]*"?[^"[:space:]]*\.landed' "$SKILL_ALL" | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 14 — run-all.sh registration (Phase 1a acceptance criterion)
# ────────────────────────────────────────────────────────────────────
RA_COUNT=$(grep -c 'test-quickfix.sh' "$REPO_ROOT/tests/run-all.sh" 2>/dev/null || echo 0)
if [ "${RA_COUNT:-0}" -ge 1 ]; then
  pass "14 run-all.sh registration: $RA_COUNT occurrence(s) of test-quickfix.sh"
else
  fail "14 run-all.sh registration: test-quickfix.sh not found in tests/run-all.sh"
fi

# ────────────────────────────────────────────────────────────────────
# Case 15 — landing=direct soft-redirects to /commit and exits 0.
# End-to-end against the preflight slice: config has
# execution.landing=direct. Per issue #293, the hard error was
# replaced with a two-line redirect (line 1 names target + reason,
# line 2 gives re-invocation hint). We expect rc=0 and the
# 'redirecting to /commit' phrase on stdout.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c15 "true" "true" "direct" "quickfix/")
OUT=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >"$OUT" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] \
   && grep -q 'redirecting to /commit' "$OUT" \
   && grep -q 'Run `/commit`' "$OUT"; then
  pass "15 landing=direct: rc=0 + /commit redirect on stdout (two-line template)"
else
  fail "15 landing=direct: rc=$RC out='$(cat "$OUT")'"
fi
rm -f -- "$OUT"

# ────────────────────────────────────────────────────────────────────
# Case 15b — landing=worktree soft-redirects to /do worktree and exits 0.
# Sibling of case 15 covering the other non-PR mode.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c15b "true" "true" "worktree" "quickfix/")
OUT=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >"$OUT" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] \
   && grep -q 'redirecting to /do worktree' "$OUT" \
   && grep -q 'Run `/do worktree' "$OUT"; then
  pass "15b landing=worktree: rc=0 + /do worktree redirect on stdout (two-line template)"
else
  fail "15b landing=worktree: rc=$RC out='$(cat "$OUT")'"
fi
rm -f -- "$OUT"

# ────────────────────────────────────────────────────────────────────
# Case 15c — landing=pr does NOT short-circuit at the landing check.
# The preflight slice must proceed past the landing check (it may
# still exit later on other gates the fixture doesn't satisfy — gh
# is mocked, but the slice has additional checks downstream).
# Assertion is purely that the landing-check redirect was NOT taken:
# no 'redirecting to /commit' AND no 'redirecting to /do worktree' on
# combined output. This guards fall-through.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c15c "true" "true" "pr" "quickfix/")
OUT=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >"$OUT" 2>&1)
# We don't assert RC — the slice may exit non-zero on a later gate.
# What matters: the landing redirect path was NOT taken.
if ! grep -q 'redirecting to /commit' "$OUT" \
   && ! grep -q 'redirecting to /do worktree' "$OUT"; then
  pass "15c landing=pr: fall-through preserved (no landing redirect emitted)"
else
  fail "15c landing=pr: unexpected landing redirect — out='$(cat "$OUT")'"
fi
rm -f -- "$OUT"

# ────────────────────────────────────────────────────────────────────
# Case 16 — gh missing exits 1 with gh-keyword stderr.
# Build a narrow shadow bin that explicitly excludes gh. /usr/bin/gh is
# preinstalled on GitHub Actions runners, so PATH="/usr/bin:/bin" does
# NOT hide it there. Instead, construct a PATH that contains only the
# commands the preflight needs, found at their actual locations via
# `command -v`, and NO gh. Assert rc=1 plus 'requires gh' in stderr.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c16)
ERR=$(mktemp)
SHADOW_BIN=$(mktemp -d)
for cmd in bash cat grep sed awk date mkdir head basename git printf env tr cut; do
  src=$(command -v "$cmd" 2>/dev/null) || continue
  ln -s "$src" "$SHADOW_BIN/$cmd"
done
(cd "$FIX" && PATH="$SHADOW_BIN" bash "$PREFLIGHT_SCRIPT" "fix something" >/dev/null 2>"$ERR")
RC=$?
rm -rf -- "$SHADOW_BIN"
if [ "$RC" -eq 1 ] && grep -q 'requires gh' "$ERR"; then
  pass "16 gh missing: rc=1 + 'requires gh' stderr"
else
  fail "16 gh missing: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 18 — LOAD-BEARING full_cmd != unit_cmd exits 1 (R-H1 guard).
# Per plan line 46: exit 1 with 'full_cmd differently' substring.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c18 "npm test" "npm run test:all")
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 1 ] && grep -q 'full_cmd differs' "$ERR"; then
  pass "18 full_cmd mismatch (load-bearing): rc=1 + 'full_cmd differs' stderr"
else
  fail "18 full_cmd mismatch: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 19 — LOAD-BEARING unit_cmd unset exits 1 with
# 'requires testing.unit_cmd' stderr (per plan line 46).
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c19 "" "")
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 1 ] && grep -q 'requires testing.unit_cmd' "$ERR"; then
  pass "19 unit_cmd unset (load-bearing): rc=1 + 'requires testing.unit_cmd' stderr"
else
  fail "19 unit_cmd unset: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 20 — LOAD-BEARING skip-tests bypasses the unit_cmd gate
# (per plan line 47). unit_cmd is unset, but positional `skip-tests`
# is passed, so the preflight slice must proceed past the test-cmd
# gate. Since we cannot yet exit 0 from the preflight slice (it stops
# at branch creation), we assert that the preflight goes BEYOND the
# unit_cmd gate — i.e., stderr does NOT contain 'requires
# testing.unit_cmd'.
# Phase 4 grammar (QUICKFIX_GRAMMAR_REDESIGN): positional `skip-tests`
# is the working form.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c20 "" "")
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" skip-tests >/dev/null 2>"$ERR")
RC=$?
# The preflight slice reaches WI 1.9 branch creation successfully (rc=0
# on happy path since ls-remote against our bare remote reports the
# branch doesn't exist and checkout -b succeeds). Assert rc != 1 AND
# the unit_cmd discriminator is absent.
if [ "$RC" -ne 1 ] && ! grep -q 'requires testing.unit_cmd' "$ERR"; then
  pass "20 skip-tests bypass (load-bearing): unit_cmd gate skipped"
else
  fail "20 skip-tests bypass: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 21 — Not on main/master (and no from-here) exits 1 with
# 'must run on main' discriminator.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c21)
git -C "$FIX" checkout --quiet -b feature/x
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 1 ] && grep -q 'must run on main' "$ERR"; then
  pass "21 not on main: rc=1 + 'must run on main' stderr"
else
  fail "21 not on main: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 22 — positional from-here overrides the main-required gate:
# feature branch + from-here proceeds past the branch check.
# Phase 4 grammar (QUICKFIX_GRAMMAR_REDESIGN): positional `from-here`
# is the working form.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c22)
git -C "$FIX" checkout --quiet -b feat/override
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" from-here >/dev/null 2>"$ERR")
RC=$?
# Should NOT fail with 'must run on main'.
if ! grep -q 'must run on main' "$ERR"; then
  pass "22 from-here: main-required gate bypassed"
else
  fail "22 from-here: gate still blocked — rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 23 — Empty description + clean tree exits 2 with
# 'needs either in-flight edits' discriminator.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c23)
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 2 ] && grep -q 'needs either in-flight edits' "$ERR"; then
  pass "23 no edits + no description: rc=2 + 'needs either' stderr"
else
  fail "23 no edits + no description: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 24 — Dirty tree + empty description exits 2 with
# 'user-edited mode requires a description' stderr.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c24)
echo "dirty" >> "$FIX/README.md"
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 2 ] && grep -q 'user-edited mode requires a description' "$ERR"; then
  pass "24 dirty + no description: rc=2 + 'user-edited mode requires a description' stderr"
else
  fail "24 dirty + no description: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 25 — Empty-prefix branch_prefix yields a bare-slug branch.
# Config has branch_prefix="". Run the preflight slice against a
# clean-tree + description (agent-dispatched mode) and inspect the
# marker written by WI 1.8 to confirm `branch: fix-foo` (no prefix).
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c25 "true" "true" "pr" "")
ERR=$(mktemp)
# Model-composed SLUG injected explicitly (simulates WI 1.6's model-layer
# composition step). The test specifically exercises empty-prefix
# branch-name assembly, not slug derivation.
(cd "$FIX" && SLUG=fix-foo PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix foo" >/dev/null 2>"$ERR")
RC=$?
MARKER="$FIX/.zskills/tracking/quickfix.fix-foo/fulfilled.quickfix.fix-foo"
if [ -f "$MARKER" ] && grep -q '^branch: fix-foo$' "$MARKER"; then
  pass "25 empty-prefix bare-slug branch: marker 'branch: fix-foo' (no prefix)"
else
  fail "25 empty-prefix bare-slug branch: marker missing or wrong — rc=$RC"
  [ -f "$MARKER" ] && grep '^branch:' "$MARKER" | sed 's/^/    /'
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 26 — Concurrent-invocation refused.
# Seed a fresh `status: started` marker in .zskills/tracking/ and
# invoke the preflight slice; expect rc=1 with 'another /quickfix is
# in progress' stderr.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c26)
# Plant an existing `started` marker for a *different* slug (so the
# parallel-invocation gate fires even before our own marker is written).
mkdir -p "$FIX/.zskills/tracking/quickfix.prior-run"
cat > "$FIX/.zskills/tracking/quickfix.prior-run/fulfilled.quickfix.prior-run" <<EOF
status: started
date: $(TZ=America/New_York date -Iseconds)
skill: quickfix
slug: prior-run
EOF
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something new" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 1 ] && grep -q 'another /quickfix is in progress' "$ERR"; then
  pass "26 concurrent invocation: rc=1 + 'another /quickfix is in progress' stderr"
else
  fail "26 concurrent invocation: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 27 — Stale (>1h) marker warns and proceeds.
# Plant a `started` marker with a 2-hour-old date; expect the preflight
# to WARN and continue (no 'in progress' rc=1 exit).
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c27)
mkdir -p "$FIX/.zskills/tracking/quickfix.stale-run"
# Two hours ago in ISO-8601.
STALE_DATE=$(TZ=America/New_York date -d '2 hours ago' -Iseconds)
cat > "$FIX/.zskills/tracking/quickfix.stale-run/fulfilled.quickfix.stale-run" <<EOF
status: started
date: $STALE_DATE
skill: quickfix
slug: stale-run
EOF
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix stale" >/dev/null 2>"$ERR")
RC=$?
if ! grep -q 'another /quickfix is in progress' "$ERR" && grep -q 'stale /quickfix marker' "$ERR"; then
  pass "27 stale marker (>1h): warn-and-proceed (no rc=1 in-progress exit)"
else
  fail "27 stale marker: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 28 — Remote branch collision exits 2.
# Pre-create the target branch on the bare remote. Expect rc=2 with
# 'already exists on origin' stderr.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c28)
# Push a branch to the bare remote with the exact name the slug derives
# to: quickfix/fix-remote-collision. We create it by pushing a local
# throwaway branch.
git -C "$FIX" checkout --quiet -b quickfix/fix-remote-collision
git -C "$FIX" push --quiet origin quickfix/fix-remote-collision
git -C "$FIX" checkout --quiet main
git -C "$FIX" branch -D quickfix/fix-remote-collision >/dev/null 2>&1
ERR=$(mktemp)
(cd "$FIX" && SLUG=fix-remote-collision PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix remote collision" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 2 ] && grep -q 'already exists on origin' "$ERR"; then
  pass "28 remote branch collision: rc=2 + 'already exists on origin' stderr"
else
  fail "28 remote collision: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 29 — Local branch collision exits 2 (distinct discriminator).
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c29)
# Pre-create a LOCAL branch with the target slug name.
git -C "$FIX" branch quickfix/fix-local-collision
ERR=$(mktemp)
(cd "$FIX" && SLUG=fix-local-collision PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix local collision" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 2 ] && grep -q "'quickfix/fix-local-collision' already exists locally" "$ERR"; then
  pass "29 local branch collision: rc=2 + 'already exists locally' stderr"
else
  fail "29 local collision: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 30 — ls-remote network failure is DISTINCT from "branch exists".
# Point `origin` at a nonexistent URL so `git ls-remote` fails with
# non-zero rc. Expect rc=1 + 'git ls-remote failed' (not rc=2 + 'exists').
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c30)
git -C "$FIX" remote set-url origin "/nonexistent/path/to/missing-remote.git"
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix network failure" >/dev/null 2>"$ERR")
RC=$?
# ls-remote with a bad path: git prints an error and returns non-zero.
# But the earlier `git fetch origin main` will also fail — expect rc=1.
if [ "$RC" -eq 1 ] && { grep -q 'git ls-remote failed' "$ERR" || grep -q 'failed to fetch origin' "$ERR"; }; then
  pass "30 ls-remote network failure: rc=1, distinct from branch-exists rc=2"
else
  fail "30 ls-remote network failure: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 31 — Malformed SLUG (slash) is rejected by the WI 1.6 validator
# at rc=2 with a 'SLUG must match' discriminator. Exercises the new
# model-composed contract: the model sets $SLUG, the bash validator
# enforces kebab-shape. A slash is outside the validator regex.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c31)
echo "dirty" >> "$FIX/README.md"
ERR=$(mktemp)
(cd "$FIX" && SLUG="a/b" PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 2 ] && grep -q 'SLUG must match' "$ERR"; then
  pass "31 malformed SLUG (slash): rc=2 + 'SLUG must match' stderr"
else
  fail "31 malformed SLUG: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 32 — Tracking marker path is pipeline-scoped (per CLAUDE.md
# tracking rule): `.zskills/tracking/quickfix.<slug>/fulfilled.quickfix.<slug>`
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c32)
ERR=$(mktemp)
(cd "$FIX" && SLUG=fix-tracking-path PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix tracking path" >/dev/null 2>"$ERR")
MARKER="$FIX/.zskills/tracking/quickfix.fix-tracking-path/fulfilled.quickfix.fix-tracking-path"
if [ -f "$MARKER" ] && grep -q '^skill: quickfix$' "$MARKER" && grep -q '^slug: fix-tracking-path$' "$MARKER"; then
  pass "32 tracking path: pipeline-scoped subdir + marker basename + fields"
else
  fail "32 tracking path: marker missing or malformed"
  [ -f "$MARKER" ] && cat "$MARKER" | sed 's/^/    /'
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 33 — LOAD-BEARING mirror literal-path idiom (R2-H1 per plan
# lines 48 & 59). `grep -E 'rm -rf "\$' skills/quickfix/SKILL.md` must
# return NO output — no variable-expansion rm -rf anywhere in the
# skill source.
# ────────────────────────────────────────────────────────────────────
# Issue #836: rm-rf-var absence guard runs over the whole lifecycle.
RMRF_VAR_MATCHES=$(grep -cE 'rm -rf "\$' "$SKILL_ALL" 2>/dev/null)
RMRF_VAR_MATCHES=${RMRF_VAR_MATCHES:-0}
if [ "$RMRF_VAR_MATCHES" -eq 0 ]; then
  pass "33 rm-rf-var absence (load-bearing R2-H1): grep returns zero matches"
else
  fail "33 rm-rf-var absence: found $RMRF_VAR_MATCHES match(es)"
  grep -nE 'rm -rf "\$' "$SKILL_ALL" | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 34 — LOAD-BEARING no || true suppression (R2-H2 per plan
# lines 49 & 60). `grep -nE '\|\| true' skills/quickfix/SKILL.md`
# must return NO output — fallible commands must not be silenced.
# ────────────────────────────────────────────────────────────────────
# Issue #836: || true absence guard runs over the whole lifecycle.
OR_TRUE_MATCHES=$(grep -cE '\|\| true' "$SKILL_ALL" 2>/dev/null)
OR_TRUE_MATCHES=${OR_TRUE_MATCHES:-0}
if [ "$OR_TRUE_MATCHES" -eq 0 ]; then
  pass "34 || true absence (load-bearing R2-H2): grep returns zero matches"
else
  fail "34 || true absence: found $OR_TRUE_MATCHES match(es)"
  grep -nE '\|\| true' "$SKILL_ALL" | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 35 — Cleanup exit 6 discriminator present (R2-H2 cleanup).
# Every cleanup step that itself fails must `exit 6` (per WI 1.10 /
# 1.12 / 1.13). Grep must find 'exit 6' at least three times (one
# per cleanup branch: user-cancel, test failure, commit failure).
# ────────────────────────────────────────────────────────────────────
# Issue #836: cleanup branches (WI 1.10 / 1.12 / 1.13) live in
# modes/execute.md.
EXIT6_COUNT=$(grep -c '^[[:space:]]*exit 6[[:space:]]*$' "$SKILL_EXECUTE")
if [ "$EXIT6_COUNT" -ge 3 ]; then
  pass "35 cleanup exit 6: $EXIT6_COUNT occurrence(s) across cleanup branches"
else
  fail "35 cleanup exit 6: only $EXIT6_COUNT occurrence(s) (expected ≥3)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 36 — Terminal-state comment documents all three final statuses
# (status: complete, status: cancelled, status: failed) for grep-ability
# per Phase 1b acceptance criterion.
# ────────────────────────────────────────────────────────────────────
# Issue #836: terminal-state documentation spans Phase 7 (land.md) +
# Exit codes (refs); run over the whole lifecycle.
if grep -q 'status: complete' "$SKILL_ALL" \
   && grep -q 'status: cancelled' "$SKILL_ALL" \
   && grep -q 'status: failed' "$SKILL_ALL"; then
  pass "36 terminal marker states: 'status: complete/cancelled/failed' all documented"
else
  fail "36 terminal marker states: one of complete/cancelled/failed missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 37 — DIRTY_AFTER includes untracked (new-file integrity).
# Assert the SKILL.md's WI 1.11 DIRTY_AFTER definition now unions
# tracked modifications with `git ls-files --others --exclude-standard`
# so new files created by the dispatched agent are counted. Also
# assert the old exclusion wording is gone — a present "excludes ...
# git ls-files --others" comment would mean the old behavior
# regressed.
# ────────────────────────────────────────────────────────────────────
# Issue #836: WI 1.11 DIRTY_AFTER definition lives in modes/execute.md
# (Phase 3 agent-dispatched). git ls-files appears in both SKILL.md (WI
# 1.5 mode detection) and execute.md, so the union-present check uses the
# whole lifecycle; the old-exclusion-wording absence guard also spans both.
if grep -q 'git ls-files --others --exclude-standard' "$SKILL_ALL" \
   && ! grep -q "excludes.*git ls-files --others" "$SKILL_ALL"; then
  pass "37 DIRTY_AFTER includes untracked (new-file integrity): union present, old exclusion wording gone"
else
  fail "37 DIRTY_AFTER includes untracked: union-def missing or old exclusion wording still present"
fi

# Case 38 was removed in #287 — the entry self-assertion that grepped
# for `disable-model-invocation: true` in the SKILL.md body was obsolete
# after the dmi flag was lifted to make /quickfix Skill-tool-dispatchable.
# Numbering preserved for continuity; the assertion itself does not exist.

# ────────────────────────────────────────────────────────────────────
# Case 39 — /tmp/zskills-tests test-output-dir idiom present (per
# CLAUDE.md "capture test output to a file, never pipe" rule).
# ────────────────────────────────────────────────────────────────────
# Issue #836: the test-output-dir idiom lives in the Phase 4 test gate →
# modes/execute.md.
if grep -q '/tmp/zskills-tests' "$SKILL_EXECUTE"; then
  pass "39 /tmp/zskills-tests test-out path: present"
else
  fail "39 /tmp/zskills-tests test-out path: missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 40 — Happy path end-to-end (user-edited).
# Dirty tree + description → run the preflight slice, verify it
# succeeds through branch creation. Post-#241 the marker reflects ONLY
# what the preflight slice did: tracking set up with `status: started`.
# `status: complete` is now written by the Phase 7 explicit-finalize
# block (not extracted by PREFLIGHT_SCRIPT), so the correct invariant
# after preflight-only is `status: started` (the in-progress state).
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c40)
echo "edit" >> "$FIX/README.md"
ERR=$(mktemp)
(cd "$FIX" && SLUG=fix-readme-typo PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix readme typo" >/dev/null 2>"$ERR")
RC=$?
CURRENT=$(git -C "$FIX" branch --show-current)
MARKER="$FIX/.zskills/tracking/quickfix.fix-readme-typo/fulfilled.quickfix.fix-readme-typo"
if [ "$RC" -eq 0 ] && [ "$CURRENT" = "quickfix/fix-readme-typo" ] \
   && [ -f "$MARKER" ] && grep -q '^status: started$' "$MARKER" \
   && grep -q '^mode: user-edited$' "$MARKER" \
   && grep -q '^base: main$' "$MARKER"; then
  pass "40 happy path (user-edited): rc=0, branch created, marker status: started (Phase 7 finalize not extracted; issue #241)"
else
  fail "40 happy path (user-edited): rc=$RC current='$CURRENT' marker=$( [ -f "$MARKER" ] && echo present || echo missing)"
  [ -f "$MARKER" ] && cat "$MARKER" | sed 's/^/    /'
  echo "  --- stderr ---"; cat "$ERR" | sed 's/^/    /'
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 41 — Path with spaces in description (happy path): derives a
# valid kebab slug and creates the branch.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c41)
echo "edit" >> "$FIX/README.md"
ERR=$(mktemp)
# Explicit SLUG stub — the model-composed identifier is what drives
# branch assembly now; the description isn't re-derived in bash.
(cd "$FIX" && SLUG=a-description-with-spaces PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "a description with spaces" >/dev/null 2>"$ERR")
RC=$?
CURRENT=$(git -C "$FIX" branch --show-current)
if [ "$RC" -eq 0 ] && [ "$CURRENT" = "quickfix/a-description-with-spaces" ]; then
  pass "41 description with spaces: slug kebab'd, branch created"
else
  fail "41 description with spaces: rc=$RC current='$CURRENT'"
  echo "  --- stderr ---"; cat "$ERR" | sed 's/^/    /'
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 42 — --branch override verbatim wins over slug+prefix.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c42)
echo "edit" >> "$FIX/README.md"
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" --branch "hotfix/urgent-123" "fix urgent thing" >/dev/null 2>"$ERR")
RC=$?
CURRENT=$(git -C "$FIX" branch --show-current)
if [ "$RC" -eq 0 ] && [ "$CURRENT" = "hotfix/urgent-123" ]; then
  pass "42 --branch override: 'hotfix/urgent-123' used verbatim"
else
  fail "42 --branch override: rc=$RC current='$CURRENT'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 43 — TRUE end-to-end (user-edited mode) — bash-extractable
# subflow: preflight → branch → test gate → commit → push. Closes the
# "manual smoke" acceptance criterion from Phase 1a (deferred to
# Phase 1b; Phase 1b's 42 cases validated structural invariants but
# never actually ran the whole flow). Runs against the full-flow
# extracted script (bash fences from SKILL.md minus WI 1.11's
# agent-dispatched snippet AND minus Phase 7).
#
# PHASE 5 (PR_LANDING_UNIFICATION) NOTE: Phase 7 (PR creation, CI
# poll, fix-cycle) was migrated to dispatch `/land-pr` via the Skill
# tool. The Skill-tool invocation is a comment-form instruction that
# bash cannot execute, so the extractor stops at `## Phase 7`. The
# bash-runnable flow now ends at push. Case 43 asserts EVERYTHING
# the original case asserted that survives the trim:
#   - rc=0
#   - branch exists locally AND on bare remote (push succeeded)
#   - tracking marker has `status: complete` (EXIT trap finalized
#     `started` → `complete` on rc=0; this assertion is UNCHANGED)
#   - commit has expected mode-aware trailer (UNCHANGED)
# Case 43 NO LONGER asserts the `pr:` marker line, the PR URL on
# stdout, or the return-to-base — those happen inside Phase 7's
# /land-pr caller loop, exercised by /land-pr's own test scripts and
# the Phase 6 cron-fire canary. Case 43b below adds a STRUCTURAL
# assertion that Phase 7 wires those behaviors correctly. Case 12
# above already independently asserts the `pr: $PR_URL` marker append
# idiom is present in SKILL.md.
#
# This is STRENGTHENED, not weakened: the bash-runnable assertions
# are unchanged, and a new structural assertion (43b) verifies the
# new architecture explicitly. Case 43 + 43b together cover what the
# pre-migration Case 43 did, scoped to what each layer can actually
# verify.
#
# Post-Phase 4 (QUICKFIX_GRAMMAR_REDESIGN): WI 1.10's interactive
# "Proceed? [y/N]" `read -r` block was DELETED — the model-layer
# WI 1.5.5 confirmation is the sole scope-protection gate. The
# bash-extractable flow therefore proceeds without any prompt; --yes
# was removed from this invocation along with the deleted block.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c43)
echo "edit for fix" >> "$FIX/README.md"
ERR=$(mktemp)
OUT=$(mktemp)
(cd "$FIX" && SLUG=fix-readme-typo PATH="$FIX/bin:$PATH" bash "$FULL_FLOW_SCRIPT" "fix readme typo" >"$OUT" 2>"$ERR")
RC=$?

# Assertions
BRANCH_EXISTS_LOCAL=$(git -C "$FIX" show-ref --verify --quiet "refs/heads/quickfix/fix-readme-typo" && echo yes || echo no)
BRANCH_EXISTS_REMOTE=$(git -C "$FIX" show-ref --verify --quiet "refs/remotes/origin/quickfix/fix-readme-typo" && echo yes || echo no)
MARKER="$FIX/.zskills/tracking/quickfix.fix-readme-typo/fulfilled.quickfix.fix-readme-typo"
# Post-#241: the FULL_FLOW_SCRIPT extractor stops at `## Phase 7`, so the
# end-of-Phase-7 explicit-finalize block does NOT run as part of this
# test. The correct invariant after the user-edited subflow (preflight
# → branch → commit → push, Phase 6 successful) is `status: started` —
# the in-progress state pending Phase 7's finalize. Pre-#241 this slot
# was `status: complete` due to the trap firing on script-exit, but
# that was the bug being fixed.
MARKER_STATUS_STARTED=$( [ -f "$MARKER" ] && grep -q '^status: started$' "$MARKER" && echo yes || echo no)
COMMIT_TRAILER=$(git -C "$FIX" log -1 --pretty=%B quickfix/fix-readme-typo 2>/dev/null | grep -c 'Generated with /quickfix (user-edited)')

if [ "$RC" -eq 0 ] \
   && [ "$BRANCH_EXISTS_LOCAL" = "yes" ] \
   && [ "$BRANCH_EXISTS_REMOTE" = "yes" ] \
   && [ "$MARKER_STATUS_STARTED" = "yes" ] \
   && [ "$COMMIT_TRAILER" -ge 1 ]; then
  pass "43 true end-to-end (user-edited bash subflow): branch pushed, marker status: started (Phase 7 finalize not extracted; issue #241), mode-aware trailer present"
else
  fail "43 end-to-end (bash subflow): rc=$RC local=$BRANCH_EXISTS_LOCAL remote=$BRANCH_EXISTS_REMOTE marker-started=$MARKER_STATUS_STARTED trailer-count=$COMMIT_TRAILER"
  echo "  --- stdout ---"; sed 's/^/    /' "$OUT"
  echo "  --- stderr ---"; sed 's/^/    /' "$ERR"
  [ -f "$MARKER" ] && { echo "  --- marker ---"; sed 's/^/    /' "$MARKER"; }
fi
rm -f -- "$ERR" "$OUT"

# ────────────────────────────────────────────────────────────────────
# Case 43b — Phase 7 STRUCTURAL assertion: /land-pr dispatch + WI 1.16
# marker append idiom. Pairs with Case 43 above to cover what the
# pre-PR_LANDING_UNIFICATION-Phase-5 Case 43 covered end-to-end (PR
# created, marker `pr:` line, return-to-base). Those behaviors are now
# owned by /land-pr; /quickfix's responsibility is to wire them
# correctly. Three assertions:
#   (1) Phase 7 contains the `Skill: { skill: "land-pr"` invocation
#       comment (the canonical caller-loop dispatch line).
#   (2) Phase 7 has the WI 1.16 `pr: $PR_URL` marker append (Case 12
#       independently asserts presence in SKILL.md; this case
#       additionally asserts the append is INSIDE Phase 7, not
#       elsewhere — preventing a refactor that moves it out of the
#       loop where PR_URL is available).
#   (3) Phase 7 contains the WI 1.17 return-to-base `git checkout
#       "$BASE_BRANCH"` (preserved post-migration; ran after the
#       caller loop on success).
# Phase 7 boundary: from `^## Phase 7` to `^## Exit codes`.
# ────────────────────────────────────────────────────────────────────
# Issue #836: Phase 7 is the whole of modes/land.md (Phase-7 prose +
# terminal-marker-states; Exit codes moved to references/). The body is
# the entire file rather than an awk slice between phase headers.
PHASE7_BODY=$(cat "$SKILL_LAND")
PHASE7_LANDPR=$(echo "$PHASE7_BODY"   | grep -c 'Skill: { skill: "land-pr"')
PHASE7_PR_APPEND=$(echo "$PHASE7_BODY" | grep -cE "printf 'pr:[^']*'[[:space:]]+\"\\\$PR_URL\"[[:space:]]+>>[[:space:]]+\"\\\$MARKER\"")
PHASE7_RETURN_BASE=$(echo "$PHASE7_BODY" | grep -c 'git checkout "$BASE_BRANCH"')

if [ "$PHASE7_LANDPR" -ge 1 ] \
   && [ "$PHASE7_PR_APPEND" -eq 1 ] \
   && [ "$PHASE7_RETURN_BASE" -ge 1 ]; then
  pass "43b Phase 7 wiring: dispatches /land-pr ($PHASE7_LANDPR), appends pr: \$PR_URL to marker (=$PHASE7_PR_APPEND), returns to \$BASE_BRANCH ($PHASE7_RETURN_BASE)"
else
  fail "43b Phase 7 wiring: land-pr-dispatch=$PHASE7_LANDPR pr-append=$PHASE7_PR_APPEND return-base=$PHASE7_RETURN_BASE"
fi

# ────────────────────────────────────────────────────────────────────
# Case 44 — `--force` (dashed) parsed → FORCE=1.
#
# Exercises WI 1.2's parser fence in isolation (no preflight side
# effects). Asserts the dashed `--force) FORCE=1` arm sets FORCE=1
# and does not consume any positional arg as a value. Bare positional
# `force` is now treated as DESCRIPTION text (issue #810: normalised
# on dashed --force across /do, /work-on-plans, /quickfix, /cleanup-merged).
# ────────────────────────────────────────────────────────────────────
OUT=$(bash "$PARSER_SCRIPT" --force "fix typo")
if echo "$OUT" | grep -q '^FORCE=1$' \
   && echo "$OUT" | grep -q '^ROUNDS=1$' \
   && echo "$OUT" | grep -q '^DESCRIPTION=fix typo$'; then
  pass "44 --force: FORCE=1, ROUNDS default 1, DESCRIPTION='fix typo' (no positional consumed)"
else
  fail "44 --force parse: $(echo "$OUT" | tr '\n' '|')"
fi

# Sub-case 44b — bare positional `force` is NO LONGER a force token; it
# falls through to DESCRIPTION (issue #810 — no backwards-compat alias).
OUT_B=$(bash "$PARSER_SCRIPT" force "fix typo")
if echo "$OUT_B" | grep -q '^FORCE=0$' \
   && echo "$OUT_B" | grep -qE '^DESCRIPTION=.*force.*fix typo$'; then
  pass "44b bare 'force' falls through to DESCRIPTION (no longer a force token; issue #810)"
else
  fail "44b bare 'force' still treated as force token: $(echo "$OUT_B" | tr '\n' '|')"
fi

# ────────────────────────────────────────────────────────────────────
# Case 45 — `--rounds 3` → ROUNDS=3 (numeric consumed); `--rounds
# notanumber` → ROUNDS stays at default 1 AND `--rounds notanumber`
# falls through to DESCRIPTION (greedy-fallthrough per WI 1a.1). This
# documents the user-prose-containing-`--rounds` case: a description
# like `fix --rounds in docs` must round-trip into DESCRIPTION rather
# than rejecting at parse time.
# ────────────────────────────────────────────────────────────────────
# Sub-case 45a: numeric argument consumed.
OUT_A=$(bash "$PARSER_SCRIPT" --rounds 3 "fix something")
# Sub-case 45b: non-numeric argument → both `--rounds` and the
# non-numeric token fall through to DESCRIPTION; ROUNDS stays at 1.
OUT_B=$(bash "$PARSER_SCRIPT" "fix" --rounds notanumber)
if echo "$OUT_A" | grep -q '^ROUNDS=3$' \
   && echo "$OUT_A" | grep -q '^DESCRIPTION=fix something$' \
   && echo "$OUT_B" | grep -q '^ROUNDS=1$' \
   && echo "$OUT_B" | grep -qE '^DESCRIPTION=.*--rounds.*notanumber.*$'; then
  pass "45 --rounds: numeric (3) consumed; non-numeric falls through to DESCRIPTION (ROUNDS stays 1)"
else
  fail "45 --rounds: A=$(echo "$OUT_A" | tr '\n' '|') B=$(echo "$OUT_B" | tr '\n' '|')"
fi

# ────────────────────────────────────────────────────────────────────
# Case 46 — `--rounds 0` → ROUNDS=0 (parser); skill source contains
# the `WARN: --rounds 0 skips` stderr discriminator emitted by WI
# 1.5.4b (model-layer prose, not a bash fence — verified via grep).
# Together: parser parses 0 cleanly; the model-layer skip path is
# documented and grep-able.
# ────────────────────────────────────────────────────────────────────
OUT=$(bash "$PARSER_SCRIPT" --rounds 0 "do thing")
WARN_DOC=$(grep -c 'WARN: --rounds 0 skips' "$SKILL")
if echo "$OUT" | grep -q '^ROUNDS=0$' \
   && echo "$OUT" | grep -q '^DESCRIPTION=do thing$' \
   && [ "$WARN_DOC" -ge 1 ]; then
  pass "46 --rounds 0: ROUNDS=0 parsed AND 'WARN: --rounds 0 skips' present in skill source ($WARN_DOC)"
else
  fail "46 --rounds 0: parser=$(echo "$OUT" | tr '\n' '|') warn-doc-count=$WARN_DOC"
fi

# ────────────────────────────────────────────────────────────────────
# Case 47 — Triage REDIRECT: real-behavior + per-skill divergent-string
# anchor (Phase 4 de-hollow, C2/C3).
#
# DE-HOLLOWED: the prior version of this case carried a `TRIAGE_SIM`
# heredoc that re-implemented the model's redirect logic in test-authored
# bash and asserted against ITS OWN output — a circular, hollow check
# that exercised no production code. That heredoc is DELETED.
#
# MESSAGE EMISSION IS MODEL-LAYER: triage is prose, not a bash fence. The
# model printf's the redirect lines per the WI 1.5.4 table; there is no
# shell to run. So this case does NOT assert that a message was emitted —
# it (a) runs the REAL WI 1.2 parser and asserts its unset guard fires,
# (b) asserts the redirect/no-op path leaves NO marker and NO branch on a
# real fixture, and (c) anchors the genuinely PER-SKILL-DIVERGENT source
# strings the model is instructed to print. The anchor guards the SOURCE
# strings (which DO drift on a copy-paste edit), not the emission.
#
# Re-anchor rationale (C2): the original `do=--force` vs `quickfix=force`
# drift target is DEAD — bare `force` was retired in #822; both skills now
# use dashed `--force`. We re-anchor onto strings that genuinely STILL
# differ per skill: (1) the quickfix-ONLY landing-config soft-redirect
# (quickfix/SKILL.md WI: `redirecting to /do worktree` + `redirecting to
# /commit`), which /do has NO equivalent of (its redirects are triage-
# only); and (2) each skill's own ask-user self-name (`Re-invoke /do` vs
# `Re-invoke /quickfix`), where a cross-contaminated copy-paste fails.
# ────────────────────────────────────────────────────────────────────
DO_SKILL="$REPO_ROOT/skills/do/SKILL.md"
FIX=$(make_fixture c47)

# (a) Real WI 1.2 parser: verdict env var present WITHOUT the harness
# flag → the parser's entry-point unset guard clears it (production
# guard, run against extracted production code, NOT a sim).
GUARD_OUT=$(_ZSKILLS_TEST_TRIAGE_VERDICT="REDIRECT:/draft-plan:bogus" bash "$PARSER_SCRIPT" "fix")
GUARD_RC=$?
GUARD_VAR_STATE=$(echo "$GUARD_OUT" | grep '^TRIAGE_VAR_STATE=' | cut -d= -f2)

# (b) No marker, no branch on the real fixture (the redirect path exits
# before WI 1.8 marker-write / WI 2 branch-creation; nothing here touches
# either, so the fixture must remain clean).
MARKER_COUNT=$(find "$FIX/.zskills/tracking" -type f -name 'fulfilled.quickfix.*' 2>/dev/null | wc -l)
BRANCH_COUNT=$(git -C "$FIX" branch --list 'quickfix/*' | wc -l)

# (c) Per-skill divergent SOURCE-string anchors.
#   c1: quickfix HAS the landing-config soft-redirect (both variants);
#       /do has NEITHER (no landing-config redirect at all).
QF_LAND_WORKTREE=$(grep -c 'Triage: redirecting to /do worktree\. Reason: /quickfix requires execution.landing' "$SKILL")
QF_LAND_COMMIT=$(grep -c 'Triage: redirecting to /commit\. Reason: /quickfix requires execution.landing' "$SKILL")
DO_LAND_REDIRECT=$(grep -c 'requires execution.landing' "$DO_SKILL")
#   c2: per-skill ask-user self-name — quickfix says /quickfix, do says
#       /do; each must NOT carry the other's self-name in its ask-user row.
QF_SELFNAME=$(grep -c 'Re-invoke /quickfix with a concrete description' "$SKILL")
QF_CROSS=$(grep -c 'Re-invoke /do with a concrete description' "$SKILL")
DO_SELFNAME=$(grep -c 'Re-invoke /do with a concrete description' "$DO_SKILL")
DO_CROSS=$(grep -c 'Re-invoke /quickfix with a concrete description' "$DO_SKILL")

if [ "$GUARD_RC" -eq 0 ] \
   && [ "$GUARD_VAR_STATE" = "UNSET" ] \
   && [ "$MARKER_COUNT" -eq 0 ] \
   && [ "$BRANCH_COUNT" -eq 0 ] \
   && [ "$QF_LAND_WORKTREE" -ge 1 ] && [ "$QF_LAND_COMMIT" -ge 1 ] \
   && [ "$DO_LAND_REDIRECT" -eq 0 ] \
   && [ "$QF_SELFNAME" -ge 1 ] && [ "$QF_CROSS" -eq 0 ] \
   && [ "$DO_SELFNAME" -ge 1 ] && [ "$DO_CROSS" -eq 0 ]; then
  pass "47 triage REDIRECT: real parser unset-guard fires (rc=0, UNSET), no marker, no branch; per-skill divergent anchors (quickfix landing-redirect present + absent in /do; each skill self-names its own ask-user row)"
else
  fail "47 triage REDIRECT: guard-rc=$GUARD_RC guard-var='$GUARD_VAR_STATE' markers=$MARKER_COUNT branches=$BRANCH_COUNT qf-land-wt=$QF_LAND_WORKTREE qf-land-commit=$QF_LAND_COMMIT do-land=$DO_LAND_REDIRECT qf-self=$QF_SELFNAME qf-cross=$QF_CROSS do-self=$DO_SELFNAME do-cross=$DO_CROSS"
fi

# ────────────────────────────────────────────────────────────────────
# Case 48 — Review REJECT: real-behavior + per-skill divergent-string
# anchor (Phase 4 de-hollow, C2/C3).
#
# DE-HOLLOWED: the prior version carried a `REVIEW_SIM` heredoc that
# re-implemented the model's REVIEW verdict-parse + reject-print in
# test-authored bash and asserted against ITS OWN output — circular and
# hollow. That heredoc is DELETED.
#
# MESSAGE EMISSION IS MODEL-LAYER: review is prose; the model printf's the
# REJECT verdict/override line per WI 1.5.5 / WI 1.5.4b. So instead of
# asserting an emitted message, this case:
#   (a) extract-and-RUNS the REAL verdict regex (the production
#       ```regex fence) against a REJECT-with-reason input, proving a
#       `VERDICT: REJECT -- contract violation` line PARSES as a valid
#       REJECT (and that the same regex rejects a bare REJECT — the `--`
#       requirement is load-bearing);
#   (b) asserts NO marker / NO branch on a real fixture and that the
#       REVIEW-seam unset guard fires in the real WI 1.2 parser;
#   (c) anchors the genuinely PER-SKILL-DIVERGENT review-REJECT source
#       prose: quickfix's `**No marker is written** (WI 1.8 has not yet
#       run).` + bare `Continue.` vs /do's `(no tracking for /do)` +
#       `Continue to Phase 0c.` A copy-paste cross-contamination flips
#       these and the anchor fails.
# ────────────────────────────────────────────────────────────────────
DO_SKILL="$REPO_ROOT/skills/do/SKILL.md"
FIX=$(make_fixture c48)

# (a) Extract the production REVISE/REJECT regex (the same ```regex fence
# Case 52 parses, WI 1.5.4b) and run it against the REJECT reason input.
# Extracted locally so this case is independent of Case 52's ordering.
C48_REVREJ_REGEX=$(awk '
  /^### WI 1\.5\.4b/   { in_section = 1; next }
  /^### WI 1\.5\.5/    { in_section = 0 }
  !in_section          { next }
  /^```regex$/         { infence = 1; next }
  infence && /^```$/   { infence = 0; next }
  infence              { print }
' "$SKILL" | grep -E '^\^VERDICT:.*REVISE\|REJECT' | head -1)

C48_PARSE_OK=0
if [ -n "$C48_REVREJ_REGEX" ]; then
  set +u
  REJECT_INPUT="VERDICT: REJECT -- contract violation"
  REJECT_BARE="VERDICT: REJECT"
  # Reason WITHOUT the `--` separator must NOT match — load-bearing input
  # that catches a production regex that drops the `--` requirement.
  REJECT_NO_SEP="VERDICT: REJECT contract violation"
  if [[ "$REJECT_INPUT" =~ $C48_REVREJ_REGEX ]] \
     && ! [[ "$REJECT_BARE" =~ $C48_REVREJ_REGEX ]] \
     && ! [[ "$REJECT_NO_SEP" =~ $C48_REVREJ_REGEX ]]; then
    C48_PARSE_OK=1
  fi
  set -u
fi

# (b) No marker / no branch on the real fixture; REVIEW-seam unset guard.
MARKER_COUNT=$(find "$FIX/.zskills/tracking" -type f -name 'fulfilled.quickfix.*' 2>/dev/null | wc -l)
BRANCH_COUNT=$(git -C "$FIX" branch --list 'quickfix/*' | wc -l)
GUARD_OUT=$(_ZSKILLS_TEST_REVIEW_VERDICT="REJECT: bogus" bash "$PARSER_SCRIPT" "fix")
REVIEW_VAR_STATE=$(echo "$GUARD_OUT" | grep '^REVIEW_VAR_STATE=' | cut -d= -f2)

# (c) Per-skill divergent review-REJECT prose anchors.
QF_NOMARKER=$(grep -c '\*\*No marker is written\*\* (WI 1.8 has not yet' "$SKILL")
DO_NOMARKER=$(grep -c '\*\*No marker is written\*\* (no tracking for /do)' "$DO_SKILL")
# Cross-contamination guards: quickfix must NOT carry /do's variant and
# vice-versa.
QF_HAS_DO_VARIANT=$(grep -c 'no tracking for /do' "$SKILL")
DO_HAS_QF_VARIANT=$(grep -c 'WI 1.8 has not yet' "$DO_SKILL")

if [ "$C48_PARSE_OK" -eq 1 ] \
   && [ "$MARKER_COUNT" -eq 0 ] \
   && [ "$BRANCH_COUNT" -eq 0 ] \
   && [ "$REVIEW_VAR_STATE" = "UNSET" ] \
   && [ "$QF_NOMARKER" -ge 1 ] && [ "$DO_NOMARKER" -ge 1 ] \
   && [ "$QF_HAS_DO_VARIANT" -eq 0 ] && [ "$DO_HAS_QF_VARIANT" -eq 0 ]; then
  pass "48 review REJECT: production regex parses 'REJECT -- reason' (and rejects bare REJECT); no marker, no branch, REVIEW unset-guard fires; per-skill divergent no-marker prose anchored (quickfix 'WI 1.8' vs /do 'no tracking for /do', no cross-contamination)"
else
  fail "48 review REJECT: parse-ok=$C48_PARSE_OK markers=$MARKER_COUNT branches=$BRANCH_COUNT review-var='$REVIEW_VAR_STATE' qf-nomarker=$QF_NOMARKER do-nomarker=$DO_NOMARKER qf-has-do=$QF_HAS_DO_VARIANT do-has-qf=$DO_HAS_QF_VARIANT regex='$C48_REVREJ_REGEX'"
fi

# ────────────────────────────────────────────────────────────────────
# Case 49 — DELETED in Phase 4 (QUICKFIX_GRAMMAR_REDESIGN, WI 4.6b).
# The user-decline regression exercised the WI 1.10 bash-fallback
# `read -r` confirmation block; per DA H7 / WI 4.5 that block was
# deleted because production scope-protection lives at model-layer
# (WI 1.5.5 + WI 1.5.5a). User-decline coverage moves to the
# "model-layer testability gap" documented in QUICKFIX_GRAMMAR_REDESIGN
# Phase 5's testability caveat — not testable from this bash harness.
# Case numbering preserved for continuity; the assertion no longer
# exists. (Case 57 — which mirrored the source-level cancel-finalize
# assertion — is similarly DELETED for the same reason.)
# ────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────
# Case 50 — Phase-1.5 block-position assertion (ORDERING + ADJACENCY).
# Phase 1a's heading-presence ACs already enforce that the WI 1.5,
# WI 1.5.4, WI 1.5.4a, WI 1.5.4b, and WI 1.5.5 headings all exist;
# this case asserts ORDERING — the line numbers must be strictly
# ascending in that exact sequence. Catches a regression where a
# future edit moves a heading without removing it (presence-grep would
# still pass; ordering breaks).
# ────────────────────────────────────────────────────────────────────
LN_15=$(grep -nE '^### WI 1\.5\b' "$SKILL" | head -1 | cut -d: -f1)
LN_154=$(grep -nE '^### WI 1\.5\.4\b' "$SKILL" | head -1 | cut -d: -f1)
LN_154a=$(grep -nE '^### WI 1\.5\.4a\b' "$SKILL" | head -1 | cut -d: -f1)
LN_154b=$(grep -nE '^### WI 1\.5\.4b\b' "$SKILL" | head -1 | cut -d: -f1)
LN_155=$(grep -nE '^### WI 1\.5\.5\b' "$SKILL" | head -1 | cut -d: -f1)

if [ -n "$LN_15" ] && [ -n "$LN_154" ] && [ -n "$LN_154a" ] \
   && [ -n "$LN_154b" ] && [ -n "$LN_155" ] \
   && [ "$LN_15" -lt "$LN_154" ] \
   && [ "$LN_154" -lt "$LN_154a" ] \
   && [ "$LN_154a" -lt "$LN_154b" ] \
   && [ "$LN_154b" -lt "$LN_155" ]; then
  pass "50 WI 1.5.x ordering: 1.5 < 1.5.4 < 1.5.4a < 1.5.4b < 1.5.5 (lines $LN_15 < $LN_154 < $LN_154a < $LN_154b < $LN_155)"
else
  fail "50 WI 1.5.x ordering: lines 1.5=$LN_15 1.5.4=$LN_154 1.5.4a=$LN_154a 1.5.4b=$LN_154b 1.5.5=$LN_155"
fi

# ────────────────────────────────────────────────────────────────────
# Case 51 — Redirect-message exact-text guard.
#
# Two parts:
#   (1) Per-target line-grep: BOTH line 1 ("Triage: redirecting to
#       <skill>") and line 2 (per-target opener) appear in the skill
#       source as separate physical lines. Validates each redirect
#       message survives editing.
#   (2) Strengthened structural assertion (replaces the weak
#       `! grep -F 'Reason: <reason>\nThis task'`): extract the
#       redirect-message markdown table from WI 1.5.4, then for EACH of
#       the 3 documented targets (`/draft-plan`, `/run-plan`,
#       `ask-user`), assert (a) the row exists, (b) the Line 2 column
#       starts with the documented opener. Also assert the table has
#       exactly 3 data rows.
#
# The `/fix-issues` redirect was retired once /quickfix's mode files
# gained their own claim-issue.sh acquire/release machinery — issue-
# numbered descriptions now claim and proceed instead of being kicked
# to /fix-issues. The table dropped from 4 rows to 3.
# ────────────────────────────────────────────────────────────────────
# Part 1: per-target line-grep.
if grep -q 'Triage: redirecting to /draft-plan' "$SKILL" \
   && grep -q 'This task spans more than one concept' "$SKILL" \
   && grep -q 'Triage: redirecting to /run-plan' "$SKILL" \
   && grep -q 'This task references an existing plan file' "$SKILL" \
   && grep -q 'Re-invoke /quickfix with a concrete description' "$SKILL"; then
  pass "51a redirect lines: line 1 + line 2 present per target (/draft-plan, /run-plan, ask-user)"
else
  fail "51a redirect lines: at least one per-target line missing in skill source"
fi

# Part 2: structural table assertion. Extract the table between the
# header `| target | Line 1 | Line 2 |` and the next blank line.
TABLE=$(awk '
  /^### WI 1\.5\.4 /              { in_section = 1 }
  /^### WI 1\.5\.4a /             { in_section = 0 }
  !in_section                     { next }
  /^\| target \| Line 1 \| Line 2 \|/ { in_table = 1; next }
  in_table && /^\|---/            { next }
  in_table && /^$/                { in_table = 0; next }
  in_table                        { print }
' "$SKILL")

# 3 rows expected: /draft-plan, /run-plan, ask-user. The /fix-issues row
# was retired (see Part 1 header comment above).
ROW_COUNT=$(echo "$TABLE" | grep -c '^|')
ROW_DRAFT=$(echo "$TABLE" | grep -c '^| `/draft-plan` ')
ROW_RUNPLAN=$(echo "$TABLE" | grep -c '^| `/run-plan` ')
ROW_ASK=$(echo "$TABLE" | grep -c '^| ask-user ')

# Check Line 2 opener for each row by extracting the third pipe column.
# Awk-based column 3 extraction; line 2 column starts after the 3rd
# pipe and ends before the 4th. Strips a single leading backtick if
# present (the markdown table wraps targets and Line 2 content in
# backticks, except for the `ask-user` row which is bare).
opener_for() {
  echo "$TABLE" | awk -F'|' -v target="$1" '
    {
      col2 = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", col2)
      if (col2 == target) {
        col4 = $4
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", col4)
        # Strip a single leading backtick wrapper if present.
        sub(/^`/, "", col4)
        print col4
        exit
      }
    }'
}
# Note: the table column 1 wraps the slash-prefixed targets in single
# backticks; ask-user is bare. The opener_for helper compares column 1
# verbatim including the wrapping backticks.
DRAFT_OPENER=$(opener_for '`/draft-plan`')
RUNPLAN_OPENER=$(opener_for '`/run-plan`')
ASK_OPENER=$(opener_for 'ask-user')

OPENER_OK=1
case "$DRAFT_OPENER"   in 'This task spans more than one concept'*) ;; *) OPENER_OK=0;; esac
case "$RUNPLAN_OPENER" in 'This task references an existing plan file'*) ;; *) OPENER_OK=0;; esac
case "$ASK_OPENER"     in 'Re-invoke /quickfix with a concrete description'*) ;; *) OPENER_OK=0;; esac

# Defensive: assert the retired /fix-issues row is NOT present.
ROW_FIX=$(echo "$TABLE" | grep -c '^| `/fix-issues` ')

if [ "$ROW_COUNT" -eq 3 ] \
   && [ "$ROW_DRAFT" -eq 1 ] \
   && [ "$ROW_RUNPLAN" -eq 1 ] \
   && [ "$ROW_FIX" -eq 0 ] \
   && [ "$ROW_ASK" -eq 1 ] \
   && [ "$OPENER_OK" -eq 1 ]; then
  pass "51b redirect-table structure: 3 rows (draft/run/ask), /fix-issues row absent, each Line 2 starts with documented opener"
else
  fail "51b redirect-table structure: rows=$ROW_COUNT draft=$ROW_DRAFT run=$ROW_RUNPLAN fix=$ROW_FIX ask=$ROW_ASK opener-ok=$OPENER_OK"
  echo "  --- table ---"; echo "$TABLE" | sed 's/^/    /'
  echo "  draft-opener='$DRAFT_OPENER'"
  echo "  runplan-opener='$RUNPLAN_OPENER'"
  echo "  ask-opener='$ASK_OPENER'"
fi

# ────────────────────────────────────────────────────────────────────
# Case 52 — VERDICT regex contract: bare APPROVE; REVISE/REJECT MUST
# include `--` separator + reason. Extracted from the `regex` fence in
# WI 1.5.4b (NOT a bash fence — see DA1 / WI 1a.5 fence-tag discipline;
# a bash fence here would be extracted by extract_full_flow and exec'd
# as commands). The AWK extractor for THIS case matches `^```regex$`.
#
# Plus a fence-tag co-discipline assertion: NO ```bash fence between
# WI 1.5.4b and WI 1.5.5 may contain a literal `^VERDICT:` line — that
# would silently break Case 43's stderr cleanliness if reintroduced.
# ────────────────────────────────────────────────────────────────────
# Extract regex fence body from WI 1.5.4b. Strip comment lines and
# blank lines; we expect exactly 2 regex patterns.
REGEX_BODY=$(awk '
  /^### WI 1\.5\.4b/   { in_section = 1; next }
  /^### WI 1\.5\.5/    { in_section = 0 }
  !in_section          { next }
  /^```regex$/         { infence = 1; next }
  infence && /^```$/   { infence = 0; next }
  infence              { print }
' "$SKILL")

# Two patterns: (1) bare APPROVE, (2) REVISE|REJECT with separator.
APPROVE_REGEX=$(echo "$REGEX_BODY" | grep -E '^\^VERDICT:.*APPROVE' | head -1)
REVREJ_REGEX=$(echo "$REGEX_BODY"  | grep -E '^\^VERDICT:.*REVISE\|REJECT' | head -1)

if [ -z "$APPROVE_REGEX" ] || [ -z "$REVREJ_REGEX" ]; then
  fail "52 verdict regex extraction: APPROVE='$APPROVE_REGEX' REVREJ='$REVREJ_REGEX'"
else
  match_test() {
    local input="$1" want="$2" rx="$3" label="$4"
    local got
    if [[ "$input" =~ $rx ]]; then got=match; else got=nomatch; fi
    if [ "$got" = "$want" ]; then
      echo "    ok: $label ('$input' → $got)"
      return 0
    else
      echo "    FAIL: $label ('$input' → $got, want $want)"
      return 1
    fi
  }

  TOTAL_OK=1
  RESULTS=$(
    set +u
    match_test "VERDICT: APPROVE"                          match    "$APPROVE_REGEX" "bare APPROVE"          || exit 1
    match_test "VERDICT: APPROVE because plan is fine"     nomatch  "$APPROVE_REGEX" "APPROVE+free-text → no" || exit 1
    match_test "VERDICT: APPROVE because plan is fine"     nomatch  "$REVREJ_REGEX"  "APPROVE+free-text → no (revrej)" || exit 1
    match_test "VERDICT: REVISE -- one-line reason"        match    "$REVREJ_REGEX"  "REVISE -- reason"      || exit 1
    match_test "VERDICT: REVISE"                           nomatch  "$REVREJ_REGEX"  "REVISE bare → no"      || exit 1
    match_test "VERDICT: REVISE"                           nomatch  "$APPROVE_REGEX" "REVISE bare → no (approve)" || exit 1
    match_test "VERDICT: REJECT -- contract violation"     match    "$REVREJ_REGEX"  "REJECT -- reason"      || exit 1
  )
  RES_RC=$?

  # Fence-tag co-discipline: NO bash-tagged fence between 1.5.4b and
  # 1.5.5 may contain a literal VERDICT-prefixed line.
  BASH_VERDICT_LEAK=$(awk '
    /^### WI 1\.5\.4b/   { in_section = 1; next }
    /^### WI 1\.5\.5/    { in_section = 0 }
    !in_section          { next }
    /^```bash$/          { infence = 1; next }
    infence && /^```$/   { infence = 0; next }
    infence              { print }
  ' "$SKILL" | grep -c '^VERDICT:')

  if [ "$RES_RC" -eq 0 ] && [ "$BASH_VERDICT_LEAK" -eq 0 ]; then
    pass '52 VERDICT regex: bare APPROVE matches; APPROVE+text rejected; REVISE/REJECT require -- + reason; no bash-tagged fence in 1.5.4b leaks VERDICT'
  else
    fail "52 VERDICT regex: results-rc=$RES_RC bash-verdict-leak=$BASH_VERDICT_LEAK"
    echo "$RESULTS" | sed 's/^/  /'
  fi
fi

# ────────────────────────────────────────────────────────────────────
# Case 53 — `--rounds 0` skip path documented in BOTH prose AND the
# stderr WARN literal. Catches a regression where the WARN message is
# removed without removing the prose ROUNDS=0 mention (or vice versa).
# ────────────────────────────────────────────────────────────────────
PROSE_DOC=$(grep -cE 'rounds.*0.*skip|skip.*rounds.*0|--rounds 0' "$SKILL")
WARN_DOC=$(grep -c 'WARN: --rounds 0 skips' "$SKILL")

if [ "$PROSE_DOC" -ge 1 ] && [ "$WARN_DOC" -ge 1 ]; then
  pass "53 --rounds 0 skip path: prose mention ($PROSE_DOC) AND 'WARN: --rounds 0 skips' literal ($WARN_DOC) present"
else
  fail "53 --rounds 0 skip path: prose=$PROSE_DOC warn=$WARN_DOC"
fi

# ────────────────────────────────────────────────────────────────────
# Case 54 — Issue #235: positional `auto` token at END of args.
# `/quickfix <description> auto` → AUTO_FLAG=1, DESCRIPTION='<description>'
# (the `auto` token does NOT fall through to DESCRIPTION).
# ────────────────────────────────────────────────────────────────────
OUT=$(bash "$PARSER_SCRIPT" "fix readme typo" auto)
if echo "$OUT" | grep -q '^AUTO_FLAG=1$' \
   && echo "$OUT" | grep -q '^DESCRIPTION=fix readme typo$'; then
  pass "54 positional auto (end): AUTO_FLAG=1, DESCRIPTION clean (no 'auto' token leak) — issue #235"
else
  fail "54 positional auto (end): $(echo "$OUT" | tr '\n' '|')"
fi

# ────────────────────────────────────────────────────────────────────
# Case 55 — Issue #235: positional `auto` token at START of args.
# `/quickfix auto <description>` → AUTO_FLAG=1 (same as above; mirrors
# /run-plan and /fix-issues which accept `auto` anywhere in the args).
# ────────────────────────────────────────────────────────────────────
OUT=$(bash "$PARSER_SCRIPT" auto "fix readme typo")
if echo "$OUT" | grep -q '^AUTO_FLAG=1$' \
   && echo "$OUT" | grep -q '^DESCRIPTION=fix readme typo$'; then
  pass "55 positional auto (start): AUTO_FLAG=1, DESCRIPTION clean — issue #235"
else
  fail "55 positional auto (start): $(echo "$OUT" | tr '\n' '|')"
fi

# ────────────────────────────────────────────────────────────────────
# Case 56 — Issue #235: no `auto` token → AUTO_FLAG=0 (preserves
# pre-#235 pr-ready-without-merge behavior).
# Also assert Phase 7 LAND_ARGS conditionally appends `--auto` when
# AUTO_FLAG=1 (textual presence of the gated append).
# ────────────────────────────────────────────────────────────────────
OUT=$(bash "$PARSER_SCRIPT" "fix readme typo")
# Issue #836: Phase 7 LAND_ARGS append lives in modes/land.md.
GATED_APPEND=$(grep -cE '\[ "\$\{AUTO_FLAG:-0\}" = "1" \] && LAND_ARGS="\$LAND_ARGS --auto"' "$SKILL_LAND" 2>/dev/null || echo 0)
GATED_APPEND=${GATED_APPEND:-0}
if echo "$OUT" | grep -q '^AUTO_FLAG=0$' \
   && echo "$OUT" | grep -q '^DESCRIPTION=fix readme typo$' \
   && [ "$GATED_APPEND" -ge 1 ]; then
  pass "56 no-auto (default off) + Phase 7 LAND_ARGS conditional --auto append present — issue #235"
else
  fail "56 no-auto: parser-out=$(echo "$OUT" | tr '\n' '|') land-args-gated-append-count=$GATED_APPEND"
fi

# ────────────────────────────────────────────────────────────────────
# Case 56b — Issue #267: positional `auto` token is fully case-
# insensitive. The pattern was widened from `auto|AUTO|Auto` to
# `[aA][uU][tT][oO]` so that mixed-case variants (e.g. `AuTo`, `aUtO`,
# `AUto`) also set AUTO_FLAG=1. Mirrors /commit's [aA][uU][tT][oO]
# convention — fixes the cosmetic asymmetry where /quickfix was
# narrower than /commit.
# ────────────────────────────────────────────────────────────────────
OUT=$(bash "$PARSER_SCRIPT" "fix readme typo" AuTo)
if echo "$OUT" | grep -q '^AUTO_FLAG=1$' \
   && echo "$OUT" | grep -q '^DESCRIPTION=fix readme typo$'; then
  pass "56b positional auto (mixed-case 'AuTo'): AUTO_FLAG=1, DESCRIPTION clean — issue #267"
else
  fail "56b positional auto (mixed-case 'AuTo'): $(echo "$OUT" | tr '\n' '|')"
fi

# ────────────────────────────────────────────────────────────────────
# Cases 62a–69 — WI 4.7 smoke tests (Phase 4 grammar): legacy
# `--`-prefixed forms fall through to DESCRIPTION as prose (migration
# redirects deleted per feedback_no_premature_backcompat.md); new
# positional tokens set the corresponding flag (case-insensitive);
# `--branch` still consumes its next arg verbatim; `--rounds`
# greedy-fallthrough on non-numeric arg leaves description/force token
# semantics intact.
# ────────────────────────────────────────────────────────────────────

# Cases 60-62 — DELETED: previously asserted --yes / --from-here /
# --skip-tests / --force hard-stop with corrective error. The migration
# redirects were removed per feedback_no_premature_backcompat.md; legacy
# `--`-prefixed tokens now fall through to DESCRIPTION as prose (see new
# Case 62a below).

# Case 62a — positive fallthrough: `--from-here` (legacy `--`-prefixed
# form) is no longer a recognized arm; it falls through to DESCRIPTION
# as user-prose. Exit code is 0 and the token appears in DESCRIPTION.
# Locks in the post-removal behavior.
ERR62a=$(mktemp)
OUT62a=$(bash "$PARSER_SCRIPT" --from-here 2>"$ERR62a")
RC62a=$?
if [ "$RC62a" -eq 0 ] \
   && echo "$OUT62a" | grep -q '^FROM_HERE=0$' \
   && echo "$OUT62a" | grep -q '^DESCRIPTION=--from-here$'; then
  pass "62a positive fallthrough: --from-here exits 0, treated as DESCRIPTION prose (FROM_HERE=0)"
else
  fail "62a positive fallthrough: rc=$RC62a out=$(echo "$OUT62a" | tr '\n' '|') stderr=$(tr '\n' '|' <"$ERR62a")"
fi
rm -f -- "$ERR62a"

# Case 63 — positional from-here sets FROM_HERE=1, DESCRIPTION unchanged (AC4.4).
OUT63=$(bash "$PARSER_SCRIPT" "fix broken docs link" from-here 2>&1)
if echo "$OUT63" | grep -q '^FROM_HERE=1$' \
   && echo "$OUT63" | grep -q '^DESCRIPTION=fix broken docs link$'; then
  pass "63 positional from-here: FROM_HERE=1, DESCRIPTION clean"
else
  fail "63 positional from-here: $(echo "$OUT63" | tr '\n' '|')"
fi

# Case 64 — positional SKIP-TESTS (case-insensitive) sets SKIP_TESTS=1 (AC4.5).
OUT64=$(bash "$PARSER_SCRIPT" "fix typo" SKIP-TESTS 2>&1)
if echo "$OUT64" | grep -q '^SKIP_TESTS=1$' \
   && echo "$OUT64" | grep -q '^DESCRIPTION=fix typo$'; then
  pass "64 positional SKIP-TESTS (case-insensitive): SKIP_TESTS=1"
else
  fail "64 positional SKIP-TESTS: $(echo "$OUT64" | tr '\n' '|')"
fi

# Case 65 — Issue #810: bare positional `Force` (mixed-case) MUST now fall
# through to DESCRIPTION; the dashed --force form is the only force token.
OUT65=$(bash "$PARSER_SCRIPT" "fix typo" Force 2>&1)
if echo "$OUT65" | grep -q '^FORCE=0$' \
   && echo "$OUT65" | grep -qE '^DESCRIPTION=fix typo Force$'; then
  pass "65 bare 'Force' (mixed-case) falls through to DESCRIPTION (issue #810)"
else
  fail "65 bare 'Force' (mixed-case): $(echo "$OUT65" | tr '\n' '|')"
fi

# Case 66 — `--branch --force fix typo` → BRANCH_OVERRIDE="--force"
# (--branch consumes next arg unconditionally), DESCRIPTION="fix typo",
# FORCE=0 (the --force token was consumed by --branch).
OUT66=$(bash "$PARSER_SCRIPT" --branch myfeat --force fix typo 2>&1)
if echo "$OUT66" | grep -q '^BRANCH_OVERRIDE=myfeat$' \
   && echo "$OUT66" | grep -q '^DESCRIPTION=fix typo$' \
   && echo "$OUT66" | grep -q '^FORCE=1$'; then
  pass "66 --branch myfeat --force: BRANCH_OVERRIDE=myfeat, FORCE=1, DESCRIPTION clean"
else
  fail "66 --branch myfeat --force fix typo: $(echo "$OUT66" | tr '\n' '|')"
fi

# Case 67 — Issue #810: bare positional 'force' is no longer a token, so
# `fix bug --rounds force` keeps --rounds and trailing 'force' as
# DESCRIPTION prose; FORCE stays 0.
OUT67=$(bash "$PARSER_SCRIPT" fix bug --rounds force 2>&1)
if echo "$OUT67" | grep -qE '^DESCRIPTION=fix bug --rounds force$' \
   && echo "$OUT67" | grep -q '^FORCE=0$' \
   && echo "$OUT67" | grep -q '^ROUNDS=1$'; then
  pass "67 greedy-fallthrough: --rounds w/ non-numeric next → all prose; bare 'force' no longer a token (issue #810)"
else
  fail "67 fix bug --rounds force: $(echo "$OUT67" | tr '\n' '|')"
fi

# Case 68 — non-hyphenated `fromhere` MUST fall through to DESCRIPTION
# (the bracket-class pattern requires the literal hyphen between
# classes). Documents the exact-string boundary.
OUT68=$(bash "$PARSER_SCRIPT" fromhere "fix typo" 2>&1)
if echo "$OUT68" | grep -q '^FROM_HERE=0$' \
   && echo "$OUT68" | grep -q '^DESCRIPTION=fromhere fix typo$'; then
  pass "68 'fromhere' (no hyphen) does NOT match positional from-here; falls through to DESCRIPTION"
else
  fail "68 fromhere boundary: $(echo "$OUT68" | tr '\n' '|')"
fi

# Case 69 — argument-hint shape (AC4.9): exact positional hint.
# Issue #810: bare `force` → dashed `--force` for cross-skill consistency.
# Issue #961: --force de-advertised from the slash-menu teaser (still parsed
# + documented; see Case 66 parser coverage). The hint no longer lists it.
HINT=$(grep '^argument-hint' "$SKILL" | sed -E 's/^argument-hint: "(.*)"$/\1/')
EXPECTED='[<description>] [auto] [from-here] [skip-tests] [--branch <name>] [--rounds N]'
if [ "$HINT" = "$EXPECTED" ]; then
  pass "69 argument-hint (AC4.9, AC4.12, #961): positional shape (len=${#HINT})"
else
  fail "69 argument-hint: got='$HINT' expected='$EXPECTED'"
fi

# Case 70 — WI 1.5.5 confirmation block contains the AUTO_FLAG=1
# skip-and-proceed rule. When the user passes `auto`, the model bypasses
# the WI 1.5.5 confirmation prompt and proceeds to WI 1.6, emitting a
# stderr NOTE. This makes /quickfix's `auto` semantic match /run-plan
# and /fix-issues, where `auto` = skip skill-internal gates + auto-merge.
# The grep is whitespace-collapsed so the prose can wrap across lines.
SKILL_FLAT=$(tr '\n' ' ' < "$SKILL" | tr -s '[:space:]' ' ')
if echo "$SKILL_FLAT" | grep -qE 'AUTO_FLAG=1[^.]*skip this WI' \
   && echo "$SKILL_FLAT" | grep -qE 'WI 1\.5\.5 confirmation skipped \(auto\)' \
   && echo "$SKILL_FLAT" | grep -qE 'proceed to WI 1\.6'; then
  pass "70 WI 1.5.5 prose contains AUTO_FLAG=1 skip-and-proceed rule (auto bypasses scope-confirmation prompt)"
else
  fail "70 WI 1.5.5 prose missing AUTO_FLAG=1 skip rule (need 'AUTO_FLAG=1 skip this WI', NOTE 'WI 1.5.5 confirmation skipped (auto)', and 'proceed to WI 1.6')"
fi

# ────────────────────────────────────────────────────────────────────
# Case 57 — DELETED in Phase 4 (QUICKFIX_GRAMMAR_REDESIGN, WI 4.5/4.6b).
# The source-level cancel-finalize invariant (`sed -i status: started →
# cancelled` + `reason: user-declined` append) was the SOURCE-side
# mirror of Case 49's runtime assertion. Both became dead code when
# WI 4.5 deleted the WI 1.10 `read -r` block; production scope-
# protection moved to model-layer (WI 1.5.5 + WI 1.5.5a). The
# `status: cancelled` terminal is still documented in the Exit codes
# section of SKILL.md (Case 36 above still asserts that documentation
# survives) — only the bash-fallback cancel-finalize implementation
# was removed.
# ────────────────────────────────────────────────────────────────────

# ────────────────────────────────────────────────────────────────────
# Case 58 — Issue #241: every documented failure path (Phase 4 test
# failure, Phase 5 commit failure, Phase 6 push failure, Phase 7
# no-result-file) has an inline `sed -i "s/^status: started$/status:
# failed/"` BEFORE its exit. Counts the inline-fail-finalize literal
# and requires at least 4 occurrences (1 per failure path) to ensure
# no path slips back to silent unfinalized state.
# ────────────────────────────────────────────────────────────────────
# Issue #836: the 4 fail-finalize paths span modes/execute.md (Phase 4
# test / Phase 5 commit / Phase 6 push) and modes/land.md (Phase 7
# no-result-file); count over the whole lifecycle.
INLINE_FAIL_FINALIZE=$(grep -cE 'sed -i "s/\^status: started\$/status: failed/"' "$SKILL_ALL" 2>/dev/null || echo 0)
INLINE_FAIL_FINALIZE=${INLINE_FAIL_FINALIZE:-0}
if [ "$INLINE_FAIL_FINALIZE" -ge 4 ]; then
  pass "58 explicit fail-finalize on every cleanup path (issue #241): $INLINE_FAIL_FINALIZE occurrences (>=4 expected)"
else
  fail "58 explicit fail-finalize: $INLINE_FAIL_FINALIZE occurrence(s) of inline status: failed sed (expected >=4 for Phase 4/5/6/7-no-result paths)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 59 — Issue #241: end-of-Phase-7-fence explicit-finalize block
# (the success-path finalize). Matches /commit pr's pattern: a
# `case "${LAND_OUTCOME:-__init__}" in` followed by `sed -i ... status:
# $FINAL`. Asserts the block lives BETWEEN the BEGIN/END canonical
# anchors (in-fence with the caller loop so $LAND_OUTCOME survives).
# ────────────────────────────────────────────────────────────────────
# Issue #836: the canonical caller-loop fence (Phase 7) lives in
# modes/land.md.
BEGIN_LINE=$(grep -nF '# === BEGIN CANONICAL /land-pr CALLER LOOP ===' "$SKILL_LAND" | head -1 | cut -d: -f1)
CLOSE_LINE=$(awk -v start="$BEGIN_LINE" 'NR>start && /^```[[:space:]]*$/ {print NR; exit}' "$SKILL_LAND")
if [ -n "$BEGIN_LINE" ] && [ -n "$CLOSE_LINE" ]; then
  FENCE_BODY=$(sed -n "${BEGIN_LINE},${CLOSE_LINE}p" "$SKILL_LAND")
  CASE_IN_FENCE=$(echo "$FENCE_BODY" | grep -cE 'case "\$\{LAND_OUTCOME:-__init__\}" in' || true)
  CASE_IN_FENCE=${CASE_IN_FENCE:-0}
  SED_IN_FENCE=$(echo "$FENCE_BODY" | grep -cE 'sed -i "s/\^status: started\$/status: \$FINAL/"' || true)
  SED_IN_FENCE=${SED_IN_FENCE:-0}
  if [ "$CASE_IN_FENCE" -ge 1 ] && [ "$SED_IN_FENCE" -ge 1 ]; then
    pass "59 end-of-Phase-7 explicit-finalize in-fence (issue #241): LAND_OUTCOME case + sed-status-FINAL between L$BEGIN_LINE..L$CLOSE_LINE"
  else
    fail "59 end-of-Phase-7 explicit-finalize: case-in-fence=$CASE_IN_FENCE sed-in-fence=$SED_IN_FENCE (BEGIN L$BEGIN_LINE END L$CLOSE_LINE)"
  fi
else
  fail "59 end-of-Phase-7 explicit-finalize: BEGIN/CLOSE anchors not located (BEGIN_LINE=$BEGIN_LINE CLOSE_LINE=$CLOSE_LINE)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 71 — Pre-flight ISSUE_NUM regex is anchored to start-of-description
# (with optional close-keyword + leading whitespace, case-insensitive).
# A `#NNN` literal appearing later in prose — quoted example, line ref,
# follow-up "see also #N" — must NOT capture an issue number, otherwise
# the claim-issue.sh acquire in WI 1.8 claims an unrelated issue.
#
# Replicates the regex from skills/quickfix/SKILL.md Pre-flight and
# exercises it directly. The regex source-of-truth is the SKILL.md; this
# test re-implements it as a behavioral fixture so a future edit that
# breaks one of these cases fails closed.
# ────────────────────────────────────────────────────────────────────
# qf_parse_issue_nums replicates the SKILL.md parser. Sets the
# ISSUE_NUMS array (and back-compat ISSUE_NUM = first) for the caller.
# Strong separators (`/`, `+`, `&`) accept bare `#N`; weak separators
# (`,`, `;`, ` and `, ` or `) require a close-keyword before `#N`.
qf_parse_issue_nums() {
  local input="$1"
  ISSUE_NUMS=()
  local _KW='([cC][lL][oO][sS][eE][sSdD]?|[fF][iI][xX]([eE][sSdD])?|[rR][eE][sS][oO][lL][vV][eE][sSdD]?)'
  # #920: optional `issue[s]?:?` filler tolerated between kw and `#N`.
  local _FILLER='([iI][sS][sS][uU][eE][sS]?:?[[:space:]]+)?'
  if [[ "$input" =~ ^[[:space:]]*${_KW}[[:space:]]+${_FILLER}#([0-9]+) ]]; then
    ISSUE_NUMS+=("${BASH_REMATCH[4]}")
  elif [[ "$input" =~ ^[[:space:]]*#([0-9]+) ]]; then
    ISSUE_NUMS+=("${BASH_REMATCH[1]}")
  fi
  local _REM="$input"
  while [[ "$_REM" =~ [[:space:]]*[/+\&][[:space:]]*(${_KW}[[:space:]]+${_FILLER})?#([0-9]+) ]]; do
    ISSUE_NUMS+=("${BASH_REMATCH[5]}")
    _REM="${_REM#*"${BASH_REMATCH[0]}"}"
  done
  _REM="$input"
  while [[ "$_REM" =~ ([[:space:]]*[,\;][[:space:]]*|[[:space:]](and|or|AND|OR|And|Or)[[:space:]]+)${_KW}[[:space:]]+${_FILLER}#([0-9]+) ]]; do
    ISSUE_NUMS+=("${BASH_REMATCH[6]}")
    _REM="${_REM#*"${BASH_REMATCH[0]}"}"
  done
  declare -A _SEEN=()
  local _UNIQUE=()
  local _n
  for _n in "${ISSUE_NUMS[@]:-}"; do
    [ -z "$_n" ] && continue
    if [ -z "${_SEEN[$_n]:-}" ]; then _UNIQUE+=("$_n"); _SEEN[$_n]=1; fi
  done
  ISSUE_NUMS=("${_UNIQUE[@]}")
  ISSUE_NUM="${ISSUE_NUMS[0]:-}"
}

# test_issue_num_qf — back-compat scalar (= ISSUE_NUMS[0]) check.
test_issue_num_qf() {
  local input="$1"
  local expected="$2"
  local label="$3"
  qf_parse_issue_nums "$input"
  if [ "${ISSUE_NUM:-}" = "$expected" ]; then
    pass "71 ISSUE_NUM: $label (got '${ISSUE_NUM:-}')"
  else
    fail "71 ISSUE_NUM: $label (expected '$expected', got '${ISSUE_NUM:-}')"
  fi
}

# test_issue_nums_qf — multi-issue array check; expected_csv is the
# comma-joined expected array (empty string asserts empty).
test_issue_nums_qf() {
  local input="$1"
  local expected_csv="$2"
  local label="$3"
  qf_parse_issue_nums "$input"
  local got_csv=""
  if [ "${#ISSUE_NUMS[@]}" -gt 0 ]; then
    got_csv=$(IFS=','; echo "${ISSUE_NUMS[*]}")
  fi
  if [ "$got_csv" = "$expected_csv" ]; then
    pass "71m ISSUE_NUMS: $label (got '$got_csv')"
  else
    fail "71m ISSUE_NUMS: $label (expected '$expected_csv', got '$got_csv')"
  fi
}
# Positive — should capture issue number
test_issue_num_qf "Fix #853 — auto-route completed plans" "853" "Fix #N at start (capital F)"
test_issue_num_qf "fix #853 — lowercase" "853" "fix #N at start (lowercase)"
test_issue_num_qf "Fixes #853 typo" "853" "Fixes #N at start"
test_issue_num_qf "Fixed #853" "853" "Fixed #N at start"
test_issue_num_qf "Closes #853 follow-up work" "853" "Closes #N at start"
test_issue_num_qf "closed #853" "853" "closed #N at start"
test_issue_num_qf "Resolves #853" "853" "Resolves #N at start"
test_issue_num_qf "#853 work item" "853" "bare #N at start"
test_issue_num_qf "   Fix #853 leading whitespace" "853" "leading whitespace + Fix #N"
# Quickfix Pre-flight runs after the quoted-head carve-out is normalized,
# so it does not need to tolerate a leading literal `"`. (/do's regex
# does tolerate it for its different invocation shape.) The quickfix
# regex deliberately omits `\"?`.

# Negative — should NOT capture
test_issue_num_qf "Remove the example 'fix #142' from prose" "" "fix #N in mid-prose quote → no capture"
test_issue_num_qf "Update file X, see also #853 for context" "" "#N after see-also → no capture"
test_issue_num_qf "Edit collect.py:#142 line reference" "" "#N as path/line reference → no capture"
test_issue_num_qf "Some text fix #142 mid prose" "" "fix #N in middle of prose → no capture"
test_issue_num_qf "Just a regular description" "" "no # at all → no capture"
test_issue_num_qf "Description mentioning #N letter" "" "#N where N is a letter → no capture"
test_issue_num_qf "address #853 work" "" "non-recognized keyword (address) → no capture"
test_issue_num_qf "work on #853" "" "non-recognized verb (work) → no capture"

# ────────────────────────────────────────────────────────────────────
# Case 71i — #920: optional `issue[s]?:?` filler token tolerated between
# the close-keyword and `#N`. Mirrors test-do.sh Case 18i — the parser
# shape is unified across /do and /quickfix (#863) and the #920 fix
# extends both in lockstep.
# ────────────────────────────────────────────────────────────────────
# Positive — kw + filler + #N captures
test_issue_num_qf "Fix issue #906: bring /work-on-plans into spec" "906" "Fix issue #N (live #920 regression case)"
test_issue_num_qf "fixes issue #906" "906" "fixes issue #N"
test_issue_num_qf "Fixed issue #906" "906" "Fixed issue #N"
test_issue_num_qf "Closes issue #906" "906" "Closes issue #N"
test_issue_num_qf "closed issue #906" "906" "closed issue #N"
test_issue_num_qf "Resolves issue #906" "906" "Resolves issue #N"
test_issue_num_qf "fixes issues #906" "906" "fixes issues #N (plural)"
test_issue_num_qf "Closes issues #906" "906" "Closes issues #N (plural)"
test_issue_num_qf "Resolves issue: #906" "906" "Resolves issue: #N (colon variant)"
test_issue_num_qf "Fix issue #906 the bug" "906" "Fix issue #N followed by prose"
# Negative — filler word but NOT adjacent to #N → no capture
test_issue_num_qf "Fix issue ticketing for #906" "" "word between 'issue' and #N → no capture (adjacency required)"
test_issue_num_qf "Fix issue with #906" "" "'with' between 'issue' and #N → no capture"
# Existing forms still work
test_issue_num_qf "Closes #906" "906" "Closes #N (no filler) still works"

# ────────────────────────────────────────────────────────────────────
# Case 71m — Multi-issue parser (#863). Description references multiple
# `#N` issues via strong separators (`/`, `+`, `&` — bare `#N` allowed)
# or weak separators (`,`, `;`, ` and `, ` or ` — close-keyword required).
# All captured into ISSUE_NUMS array; back-compat ISSUE_NUM stays as
# first element.
# ────────────────────────────────────────────────────────────────────
test_issue_nums_qf "Closes #832 / Closes #833"           "832,833"     "slash-separated double Closes (canonical multi-issue pattern)"
test_issue_nums_qf "fix #832 + #833"                     "832,833"     "plus-separated bare #N (strong sep)"
test_issue_nums_qf "Closes #832 & #833"                  "832,833"     "ampersand-separated bare #N (strong sep)"
test_issue_nums_qf "fix #832 and fix #833"               "832,833"     "and-separated keyword + #N (weak sep + kw OK)"
test_issue_nums_qf "Closes #832; Resolves #833"          "832,833"     "semicolon-separated different keywords (weak sep + kw OK)"
test_issue_nums_qf "Fix #832, Closes #833"               "832,833"     "comma-separated keyword + #N (weak sep + kw OK)"
test_issue_nums_qf "Closes #832 / Closes #833 + #834"    "832,833,834" "triple-fanout slash + plus (mixed strong seps)"
test_issue_nums_qf "Fix #853"                            "853"         "single-issue case still works"
test_issue_nums_qf "Just a regular description"          ""            "zero-issue case → empty array"
test_issue_nums_qf "Closes #832, see also #999"          "832"         "see-also after comma → only #832 (weak sep, no kw before #999)"
test_issue_nums_qf "Closes #832, #833"                   "832"         "bare #N after comma (weak sep) → only #832"
test_issue_nums_qf "fix #832 and #833"                   "832"         "bare #N after 'and' (weak sep) → only #832"
test_issue_nums_qf "fix #832 and fix #832"               "832"         "dedupe: duplicate #N captured once"
# #920: filler token across separator passes
test_issue_nums_qf "Closes issue #832 / Closes issue #833"        "832,833"     "slash-separated double Closes-issue (kw+filler, strong sep)"
test_issue_nums_qf "Fixes issues #832 + #833"                     "832,833"     "Fixes issues (plural) + bare #N (strong sep, kw absent on RHS)"
test_issue_nums_qf "Fix issue #832 and Closes issue #833"         "832,833"     "and-separated kw+filler on both sides (weak sep)"
test_issue_nums_qf "Fix issue #832, Closes #833"                  "832,833"     "comma-separated: kw+filler then bare-kw (weak sep)"
# #920 negative — filler-without-adjacency in weak-sep position
test_issue_nums_qf "Fix issue #832, see also issue #999"          "832"         "see-also after comma → only #832 even though 'issue' near #999 (no kw before #999)"
test_issue_nums_qf "fixes issues #906 and #907"                   "906"         "plural 'issues' in leading does NOT loosen weak-sep guard (no kw before #907)"

# ────────────────────────────────────────────────────────────────────
# Case 71w — Unclaimed-reference WARNING (#907). When the description
# carries a `#N` token that the claim-position rules did NOT capture into
# ISSUE_NUMS, /quickfix warns (non-fatal) that no claim was acquired for
# it — the footgun that let `/do Build … for #877` run unclaimed and
# duplicate a parallel /fix-issues sprint (closed PR #888). Replicates the
# SKILL.md warning loop (source-of-truth is SKILL.md; anchored by 71w-src).
# Mirrors test-do.sh Case 18w.
# ────────────────────────────────────────────────────────────────────
# qf_warn_unclaimed echoes "WARN #N" per unclaimed reference (the real
# skill writes the full sentence to stderr). Assumes qf_parse_issue_nums
# already populated ISSUE_NUMS.
qf_warn_unclaimed() {
  local input="$1" _REM="$1" _REF _CLAIMED _n out=""
  while [[ "$_REM" =~ \#([0-9]+) ]]; do
    _REF="${BASH_REMATCH[1]}"
    _REM="${_REM#*"${BASH_REMATCH[0]}"}"
    _CLAIMED=0
    for _n in "${ISSUE_NUMS[@]:-}"; do
      [ "$_n" = "$_REF" ] && { _CLAIMED=1; break; }
    done
    [ "$_CLAIMED" -eq 0 ] && out+="WARN #$_REF"$'\n'
  done
  printf '%s' "$out"
}
test_qf_warn() {
  local input="$1" expected_csv="$2" label="$3"
  qf_parse_issue_nums "$input"
  local got_csv
  got_csv=$(qf_warn_unclaimed "$input" | grep -oE '#[0-9]+' | tr -d '#' | paste -sd, -)
  if [ "$got_csv" = "$expected_csv" ]; then
    pass "71w warn: $label (got '${got_csv:-none}')"
  else
    fail "71w warn: $label (expected '$expected_csv', got '$got_csv')"
  fi
}
test_qf_warn "Build the guard for #877"        "877" "bare mid-prose #N → WARN (the #888 footgun)"
test_qf_warn "Fix #853 — auto-route"           ""    "claim-positioned #N → NO warn"
test_qf_warn "Closes #832 / Closes #833"       ""    "both claimed (multi) → NO warn"
test_qf_warn "Closes #832, see also #999"      "999" "claimed #832 + unclaimed #999 → warn only #999"
test_qf_warn "Just a regular description"      ""    "no #N → NO warn"
test_qf_warn "Edit collect.py:#142 line ref"   "142" "stray #N → WARN (accepted non-fatal false-positive)"
# 71w-src — anchor the replication to the SKILL.md source so a future edit
# that removes the warning fails closed.
if grep -qF 'is not in claim position — NO claim was acquired' "$SKILL"; then
  pass "71w-src SKILL.md carries the unclaimed-reference WARN (#907)"
else
  fail "71w-src SKILL.md missing the unclaimed-reference WARN (#907)"
fi

# ────────────────────────────────────────────────────────────────────
# Case 71x — Foreign-held stray-`#N` STOP (#959). The #907 warn fails
# UNSAFE in autonomous use; #959 upgrades it to a read-only foreign-held
# check that STOPS (decline) when a stray `#N` is currently claimed by a
# DIFFERENT pipeline. Foreign-vs-self is decided by reading
# `.zskills/claims/issue-N/claim.json`'s pipeline_id and comparing to this
# run's pipeline_id — exactly the pattern block-fix-issue-unclaimed.sh uses.
# `--no-claim` suppresses the stop. Missing/malformed claim.json → not-held
# → warn + proceed (fail-open). Self-claim (stored == caller) → no stop.
# Mirrors test-do.sh Case 18x.
# ────────────────────────────────────────────────────────────────────
PY_BIN="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"

# qf_stray_check replicates the SKILL.md #959 stray-ref decision. Echoes one
# of: "STOP <ref> <stored_pid>", "WARN <ref>" per stray ref. Assumes
# qf_parse_issue_nums already populated ISSUE_NUMS. Args:
#   $1 = description, $2 = claims-root dir, $3 = caller pipeline_id,
#   $4 = NO_CLAIM (0/1).
qf_stray_check() {
  local input="$1" claims_root="$2" self_pid="$3" no_claim="$4"
  local _REM="$input" _REF _CLAIMED _n _claim_file _stored out=""
  [ "$no_claim" -eq 1 ] && { printf ''; return; }
  while [[ "$_REM" =~ \#([0-9]+) ]]; do
    _REF="${BASH_REMATCH[1]}"
    _REM="${_REM#*"${BASH_REMATCH[0]}"}"
    _CLAIMED=0
    for _n in "${ISSUE_NUMS[@]:-}"; do
      [ "$_n" = "$_REF" ] && { _CLAIMED=1; break; }
    done
    [ "$_CLAIMED" -eq 1 ] && continue
    _claim_file="${claims_root}/issue-${_REF}/claim.json"
    _stored=""
    if [ -f "$_claim_file" ] && [ -n "$PY_BIN" ]; then
      _stored=$("$PY_BIN" - "$_claim_file" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        sys.stdout.write(json.load(f).get("pipeline_id", "") or "")
except Exception:
    pass
PY
)
    fi
    if [ -n "$_stored" ] && [ "$_stored" != "$self_pid" ]; then
      out+="STOP $_REF $_stored"$'\n'
    else
      out+="WARN $_REF"$'\n'
    fi
  done
  printf '%s' "$out"
}

qf_mk_claim() {
  # $1 = claims-root, $2 = issue number, $3 = pipeline_id
  local dir="$1/issue-$2"
  mkdir -p "$dir"
  printf '{"pipeline_id": "%s", "started_at": "now"}\n' "$3" > "$dir/claim.json"
}

# Fixture claims dir.
QF_STRAY_ROOT="$TEST_TMPDIR/claims-stray"
register_fixture "$QF_STRAY_ROOT"
mkdir -p "$QF_STRAY_ROOT"
qf_mk_claim "$QF_STRAY_ROOT" 340 "fix-issues.sprint-foreign"   # foreign holder
qf_mk_claim "$QF_STRAY_ROOT" 555 "quickfix.this-run-slug"      # self holder

# (a) stray #N with a foreign live claim → STOP signalled.
qf_parse_issue_nums "fix tooltip, related to #340"
GOT=$(qf_stray_check "fix tooltip, related to #340" "$QF_STRAY_ROOT" "quickfix.this-run-slug" 0)
if printf '%s' "$GOT" | grep -qE '^STOP 340 fix-issues\.sprint-foreign$'; then
  pass "71x foreign-held stray #340 → STOP (names holder)"
else
  fail "71x foreign-held stray #340 → STOP (got: '$(printf '%s' "$GOT" | tr '\n' '|')')"
fi

# (b) stray #N with NO claim → warn + proceed (no stop).
qf_parse_issue_nums "fix tooltip, related to #999"
GOT=$(qf_stray_check "fix tooltip, related to #999" "$QF_STRAY_ROOT" "quickfix.this-run-slug" 0)
if printf '%s' "$GOT" | grep -qE '^WARN 999$' && ! printf '%s' "$GOT" | grep -q '^STOP'; then
  pass "71x not-held stray #999 → WARN, no STOP"
else
  fail "71x not-held stray #999 → WARN (got: '$(printf '%s' "$GOT" | tr '\n' '|')')"
fi

# (c) stray #N whose claim.json pipeline_id == caller (self) → NO stop.
qf_parse_issue_nums "fix tooltip, related to #555"
GOT=$(qf_stray_check "fix tooltip, related to #555" "$QF_STRAY_ROOT" "quickfix.this-run-slug" 0)
if printf '%s' "$GOT" | grep -qE '^WARN 555$' && ! printf '%s' "$GOT" | grep -q '^STOP'; then
  pass "71x self-claimed stray #555 → no STOP (self-exclusion)"
else
  fail "71x self-claimed stray #555 → no STOP (got: '$(printf '%s' "$GOT" | tr '\n' '|')')"
fi

# (d) --no-claim present → stray-ref stop suppressed (no STOP, no WARN).
qf_parse_issue_nums "fix tooltip, related to #340"
GOT=$(qf_stray_check "fix tooltip, related to #340" "$QF_STRAY_ROOT" "quickfix.this-run-slug" 1)
if [ -z "$GOT" ]; then
  pass "71x --no-claim suppresses foreign-held STOP (and warn)"
else
  fail "71x --no-claim should suppress all stray output (got: '$(printf '%s' "$GOT" | tr '\n' '|')')"
fi

# 71x-src — anchor the foreign-held STOP + --no-claim handling to SKILL.md.
if grep -qF 'is currently held by a foreign pipeline' "$SKILL" \
   && grep -qF 'claims/issue-${_QF_REF}/claim.json' "$SKILL"; then
  pass "71x-src SKILL.md carries the foreign-held stray-ref STOP (#959)"
else
  fail "71x-src SKILL.md missing the foreign-held stray-ref STOP (#959)"
fi
if grep -qE 'NO_CLAIM=0' "$SKILL" \
   && grep -qF 'if [ "$NO_CLAIM" -ne 1 ]; then' "$SKILL"; then
  pass "71x-src SKILL.md parses --no-claim and gates the stray check on it"
else
  fail "71x-src SKILL.md missing --no-claim parse / gate"
fi
# The case-parser arm must consume --no-claim (so it never falls through
# into DESCRIPTION and never leaks into the soft-redirect prompts).
if grep -qE '^[[:space:]]*--no-claim\) NO_CLAIM=1 ;;' "$SKILL"; then
  pass "71x-src --no-claim consumed by the case parser (no leak into DESCRIPTION)"
else
  fail "71x-src --no-claim case arm missing (would leak into DESCRIPTION / redirect prompts)"
fi
# Both the STOP message AND the #907 warn must reference --no-claim.
if grep -qF 're-run with --no-claim' "$SKILL" \
   && grep -qF 'pass --no-claim to silence' "$SKILL"; then
  pass "71x-src STOP + #907 warn both reference --no-claim"
else
  fail "71x-src STOP and/or #907 warn missing --no-claim reference"
fi

# ────────────────────────────────────────────────────────────────────
# Case 71y — Documentation discipline for --no-claim (#959):
#   - argument-hint frontmatter must NOT contain --no-claim (#961 lean).
#   - the Arguments body MUST document --no-claim (bullet present).
# Mirrors test-do.sh Case 18y.
# ────────────────────────────────────────────────────────────────────
if grep -qE '^argument-hint:' "$SKILL" \
   && grep -E '^argument-hint:' "$SKILL" | grep -q -- '--no-claim'; then
  fail "71y argument-hint frontmatter must NOT contain --no-claim"
else
  pass "71y argument-hint frontmatter does NOT contain --no-claim"
fi
if grep -qE '^\- \*\*--no-claim\*\*' "$SKILL"; then
  pass "71y Arguments body documents --no-claim (bullet present)"
else
  fail "71y Arguments body missing --no-claim bullet"
fi

# ────────────────────────────────────────────────────────────────────
# Case 72 — Phase 0a triage rubric NO LONGER contains the
# "References a GitHub issue number → /fix-issues" REDIRECT row.
# After PR 825 wired ISSUE_NUM + claim-issue.sh into the mode files,
# the redirect made the claim machinery unreachable on the default
# path. The row, its worked example, the per-target message template
# row, and the test-stub-verdict entry are all expected to be absent.
# ────────────────────────────────────────────────────────────────────
SKILL="$REPO_ROOT/skills/quickfix/SKILL.md"
if grep -qE 'References a GitHub issue number.*REDIRECT.*/fix-issues' "$SKILL"; then
  fail "72a Phase 0a rubric still contains the issue-number REDIRECT row"
else
  pass "72a Phase 0a rubric: issue-number REDIRECT row removed"
fi
if grep -qE '/quickfix fix #142.*REDIRECT.*/fix-issues' "$SKILL"; then
  fail "72b Worked-example row '/quickfix fix #142 → REDIRECT → /fix-issues' still present"
else
  pass "72b Worked-example row removed"
fi
if grep -qE '^\| `/fix-issues` \| `Triage: redirecting to /fix-issues' "$SKILL"; then
  fail "72c Per-target redirect-message-template row for /fix-issues still present"
else
  pass "72c /fix-issues message-template row removed"
fi
if grep -qE 'REDIRECT:/fix-issues:reason' "$SKILL"; then
  fail "72d Recognized test-stub verdict list still includes REDIRECT:/fix-issues:reason"
else
  pass "72d Test-stub verdict list pruned"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
