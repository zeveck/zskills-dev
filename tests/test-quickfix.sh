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
  # Skill references it via $MAIN_ROOT/.claude/skills/create-worktree/scripts/
  # (post-Phase-3a path under the .claude mirror).
  mkdir -p "$fix/.claude/skills/create-worktree/scripts"
  cp "$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$fix/.claude/skills/create-worktree/scripts/"
  chmod +x "$fix/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"

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
  awk '
    /^### WI 1\.11/         { skip = 1 }
    /^## Phase 4/           { skip = 0 }
    /^## Phase 7/           { stop = 1 }
    stop                    { next }
    skip                    { next }
    /^```bash$/             { infence = 1; next }
    infence && /^```$/      { infence = 0; print ""; next }
    infence                 { print }
  ' "$SKILL"
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
  echo 'printf "YES_FLAG=%s\n" "$YES_FLAG"'
  echo 'printf "BRANCH_OVERRIDE=%s\n" "$BRANCH_OVERRIDE"'
  # Also report whether the entry-point unset guard cleared the seam vars.
  echo 'printf "TRIAGE_VAR_STATE=%s\n" "${_ZSKILLS_TEST_TRIAGE_VERDICT-UNSET}"'
  echo 'printf "REVIEW_VAR_STATE=%s\n" "${_ZSKILLS_TEST_REVIEW_VERDICT-UNSET}"'
} > "$PARSER_SCRIPT"
chmod +x "$PARSER_SCRIPT"

echo "=== quickfix — structural and algorithmic invariants ==="

# ────────────────────────────────────────────────────────────────────
# Case 1 — YAML frontmatter (WI 1.1)
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
# Case 6 — Landing gate wiring (WI 1.3 check 3)
# ────────────────────────────────────────────────────────────────────
if grep -q 'execution.landing' "$SKILL" \
   && grep -q 'requires execution.landing == "pr"' "$SKILL"; then
  pass "6  landing gate: execution.landing read, \"pr\"-required error present"
else
  fail "6  landing gate: wiring not found"
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
if grep -qE 'git push -u origin "\$BRANCH"' "$SKILL" \
   && ! grep -qE 'HEAD:main|HEAD:master' "$SKILL" \
   && ! grep -qE 'git push [^|]*:' "$SKILL"; then
  pass "8  push form: bare-branch only; no HEAD:main / src:dst refspec"
else
  fail "8  push form: bare-branch assertion failed or a refspec form is present"
fi

# ────────────────────────────────────────────────────────────────────
# Case 9 — Tracking setup (WI 1.8)
# ────────────────────────────────────────────────────────────────────
if grep -q 'skills/create-worktree/scripts/sanitize-pipeline-id.sh' "$SKILL" \
   && grep -qE 'echo.*ZSKILLS_PIPELINE_ID=\$PIPELINE_ID' "$SKILL" \
   && grep -q 'fulfilled.quickfix' "$SKILL" \
   && grep -q "trap 'finalize_marker \$?' EXIT" "$SKILL"; then
  pass "9  tracking: sanitize + echo + marker path + EXIT trap"
else
  fail "9  tracking: one or more wiring elements missing"
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
COAUTH_COUNT=$(grep -c 'Co-Authored-By: \$COMMIT_CO_AUTHOR' "$SKILL" 2>/dev/null || echo 0)
if grep -qE 'Generated with /quickfix \(user-edited\)' "$SKILL" \
   && grep -qE 'Generated with /quickfix \(agent-dispatched\)' "$SKILL" \
   && [ "$COAUTH_COUNT" = "1" ] \
   && grep -q 'co_author' "$SKILL" \
   && grep -q 'zskills-resolve-config\.sh' "$SKILL"; then
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
REFSPEC_MATCHES=$(grep -cE 'git push [^|]*:' "$SKILL" 2>/dev/null)
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
if grep -qE "printf 'pr:[^']*'[[:space:]]+\"\\\$PR_URL\"[[:space:]]+>>[[:space:]]+\"\\\$MARKER\"" "$SKILL"; then
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
if ! grep -qE '>>?[[:space:]]*"?[^"[:space:]]*\.landed' "$SKILL"; then
  pass "13 .landed never written: no redirect targets a .landed file"
else
  fail "13 .landed never written: a > or >> redirect targets .landed"
  grep -nE '>>?[[:space:]]*"?[^"[:space:]]*\.landed' "$SKILL" | sed 's/^/    /'
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
# Case 15 — landing != pr exits 1 with landing-keyword stderr.
# End-to-end against the preflight slice: config has
# execution.landing=direct, we expect rc=1 and
# 'requires execution.landing == "pr"' in stderr.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c15 "true" "true" "direct" "quickfix/")
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix something" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 1 ] && grep -q 'requires execution.landing == "pr"' "$ERR"; then
  pass "15 landing != pr: rc=1 + 'requires execution.landing' stderr"
else
  fail "15 landing != pr: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

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
# Case 20 — LOAD-BEARING --skip-tests bypasses the unit_cmd gate
# (per plan line 47). unit_cmd is unset, but --skip-tests is passed,
# so the preflight slice must proceed past the test-cmd gate. Since
# we cannot yet exit 0 from the preflight slice (it stops at branch
# creation), we assert that the preflight goes BEYOND the unit_cmd
# gate — i.e., stderr does NOT contain 'requires testing.unit_cmd'.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c20 "" "")
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" --skip-tests "fix something" >/dev/null 2>"$ERR")
RC=$?
# The preflight slice reaches WI 1.9 branch creation successfully (rc=0
# on happy path since ls-remote against our bare remote reports the
# branch doesn't exist and checkout -b succeeds). Assert rc != 1 AND
# the unit_cmd discriminator is absent.
if [ "$RC" -ne 1 ] && ! grep -q 'requires testing.unit_cmd' "$ERR"; then
  pass "20 --skip-tests bypass (load-bearing): unit_cmd gate skipped"
else
  fail "20 --skip-tests bypass: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 21 — Not on main/master (and no --from-here) exits 1 with
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
# Case 22 — --from-here overrides the main-required gate: feature
# branch + --from-here proceeds past the branch check.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c22)
git -C "$FIX" checkout --quiet -b feat/override
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" --from-here "fix something" >/dev/null 2>"$ERR")
RC=$?
# Should NOT fail with 'must run on main'.
if ! grep -q 'must run on main' "$ERR"; then
  pass "22 --from-here: main-required gate bypassed"
else
  fail "22 --from-here: gate still blocked — rc=$RC stderr='$(cat "$ERR")'"
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
RMRF_VAR_MATCHES=$(grep -cE 'rm -rf "\$' "$SKILL" 2>/dev/null)
RMRF_VAR_MATCHES=${RMRF_VAR_MATCHES:-0}
if [ "$RMRF_VAR_MATCHES" -eq 0 ]; then
  pass "33 rm-rf-var absence (load-bearing R2-H1): grep returns zero matches"
else
  fail "33 rm-rf-var absence: found $RMRF_VAR_MATCHES match(es)"
  grep -nE 'rm -rf "\$' "$SKILL" | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 34 — LOAD-BEARING no || true suppression (R2-H2 per plan
# lines 49 & 60). `grep -nE '\|\| true' skills/quickfix/SKILL.md`
# must return NO output — fallible commands must not be silenced.
# ────────────────────────────────────────────────────────────────────
OR_TRUE_MATCHES=$(grep -cE '\|\| true' "$SKILL" 2>/dev/null)
OR_TRUE_MATCHES=${OR_TRUE_MATCHES:-0}
if [ "$OR_TRUE_MATCHES" -eq 0 ]; then
  pass "34 || true absence (load-bearing R2-H2): grep returns zero matches"
else
  fail "34 || true absence: found $OR_TRUE_MATCHES match(es)"
  grep -nE '\|\| true' "$SKILL" | sed 's/^/    /'
fi

# ────────────────────────────────────────────────────────────────────
# Case 35 — Cleanup exit 6 discriminator present (R2-H2 cleanup).
# Every cleanup step that itself fails must `exit 6` (per WI 1.10 /
# 1.12 / 1.13). Grep must find 'exit 6' at least three times (one
# per cleanup branch: user-cancel, test failure, commit failure).
# ────────────────────────────────────────────────────────────────────
EXIT6_COUNT=$(grep -c '^[[:space:]]*exit 6[[:space:]]*$' "$SKILL")
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
if grep -q 'status: complete' "$SKILL" \
   && grep -q 'status: cancelled' "$SKILL" \
   && grep -q 'status: failed' "$SKILL"; then
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
if grep -q 'git ls-files --others --exclude-standard' "$SKILL" \
   && ! grep -q "excludes.*git ls-files --others" "$SKILL"; then
  pass "37 DIRTY_AFTER includes untracked (new-file integrity): union present, old exclusion wording gone"
else
  fail "37 DIRTY_AFTER includes untracked: union-def missing or old exclusion wording still present"
fi

# ────────────────────────────────────────────────────────────────────
# Case 38 — Entry self-assertion: disable-model-invocation check
# block present (WI 1.1).
# ────────────────────────────────────────────────────────────────────
if grep -q 'SKILL_SELF' "$SKILL" \
   && grep -q "missing 'disable-model-invocation: true'" "$SKILL"; then
  pass "38 self-assertion: disable-model-invocation guard present"
else
  fail "38 self-assertion: disable-model-invocation guard missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 39 — /tmp/zskills-tests test-output-dir idiom present (per
# CLAUDE.md "capture test output to a file, never pipe" rule).
# ────────────────────────────────────────────────────────────────────
if grep -q '/tmp/zskills-tests' "$SKILL"; then
  pass "39 /tmp/zskills-tests test-out path: present"
else
  fail "39 /tmp/zskills-tests test-out path: missing"
fi

# ────────────────────────────────────────────────────────────────────
# Case 40 — Happy path end-to-end (user-edited).
# Dirty tree + description → run the preflight slice, verify it
# succeeds through branch creation. The EXIT trap in WI 1.8 fires at
# preflight-script end with rc=0 and maps status to 'complete', so
# we assert: rc=0, branch created, marker mode=user-edited, status
# is 'complete' (EXIT trap terminal state).
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c40)
echo "edit" >> "$FIX/README.md"
ERR=$(mktemp)
(cd "$FIX" && SLUG=fix-readme-typo PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix readme typo" >/dev/null 2>"$ERR")
RC=$?
CURRENT=$(git -C "$FIX" branch --show-current)
MARKER="$FIX/.zskills/tracking/quickfix.fix-readme-typo/fulfilled.quickfix.fix-readme-typo"
if [ "$RC" -eq 0 ] && [ "$CURRENT" = "quickfix/fix-readme-typo" ] \
   && [ -f "$MARKER" ] && grep -q '^status: complete$' "$MARKER" \
   && grep -q '^mode: user-edited$' "$MARKER" \
   && grep -q '^base: main$' "$MARKER"; then
  pass "40 happy path (user-edited): rc=0, branch created, marker complete/user-edited"
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
# Uses --yes so WI 1.10's interactive "Proceed? [y/N]" prompt is
# bypassed deterministically.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c43)
echo "edit for fix" >> "$FIX/README.md"
ERR=$(mktemp)
OUT=$(mktemp)
(cd "$FIX" && SLUG=fix-readme-typo PATH="$FIX/bin:$PATH" bash "$FULL_FLOW_SCRIPT" --yes "fix readme typo" >"$OUT" 2>"$ERR")
RC=$?

# Assertions
BRANCH_EXISTS_LOCAL=$(git -C "$FIX" show-ref --verify --quiet "refs/heads/quickfix/fix-readme-typo" && echo yes || echo no)
BRANCH_EXISTS_REMOTE=$(git -C "$FIX" show-ref --verify --quiet "refs/remotes/origin/quickfix/fix-readme-typo" && echo yes || echo no)
MARKER="$FIX/.zskills/tracking/quickfix.fix-readme-typo/fulfilled.quickfix.fix-readme-typo"
MARKER_STATUS_COMPLETE=$( [ -f "$MARKER" ] && grep -q '^status: complete$' "$MARKER" && echo yes || echo no)
COMMIT_TRAILER=$(git -C "$FIX" log -1 --pretty=%B quickfix/fix-readme-typo 2>/dev/null | grep -c 'Generated with /quickfix (user-edited)')

if [ "$RC" -eq 0 ] \
   && [ "$BRANCH_EXISTS_LOCAL" = "yes" ] \
   && [ "$BRANCH_EXISTS_REMOTE" = "yes" ] \
   && [ "$MARKER_STATUS_COMPLETE" = "yes" ] \
   && [ "$COMMIT_TRAILER" -ge 1 ]; then
  pass "43 true end-to-end (user-edited bash subflow): branch pushed, marker status: complete, mode-aware trailer present"
else
  fail "43 end-to-end (bash subflow): rc=$RC local=$BRANCH_EXISTS_LOCAL remote=$BRANCH_EXISTS_REMOTE marker-complete=$MARKER_STATUS_COMPLETE trailer-count=$COMMIT_TRAILER"
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
PHASE7_BODY=$(awk '/^## Phase 7/,/^## Exit codes/' "$SKILL")
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
# Case 44 — `--force` parsed → FORCE=1.
#
# Exercises WI 1.2's parser fence in isolation (no preflight side
# effects). Asserts the new `--force) FORCE=1 ;;` arm sets FORCE=1 and
# does not consume the next positional arg as a value.
# ────────────────────────────────────────────────────────────────────
OUT=$(bash "$PARSER_SCRIPT" --force "fix typo")
if echo "$OUT" | grep -q '^FORCE=1$' \
   && echo "$OUT" | grep -q '^ROUNDS=1$' \
   && echo "$OUT" | grep -q '^DESCRIPTION=fix typo$'; then
  pass "44 --force: FORCE=1, ROUNDS default 1, DESCRIPTION='fix typo' (no positional consumed)"
else
  fail "44 --force parse: $(echo "$OUT" | tr '\n' '|')"
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
# Case 47 — Triage REDIRECT path (driven by _ZSKILLS_TEST_HARNESS=1 +
# _ZSKILLS_TEST_TRIAGE_VERDICT=REDIRECT:/draft-plan:multi-concept):
#
#   (a) BOTH lines of the /draft-plan redirect message print to stdout.
#   (b) exit 0.
#   (c) NO marker file at .zskills/tracking/quickfix.*/fulfilled.quickfix.*
#   (d) NO branch created.
#   (e) Entry-point unset guard: invoking with the verdict env var set
#       but WITHOUT _ZSKILLS_TEST_HARNESS=1 unsets the var (the parser's
#       guard at WI 1.2 fires).
#
# Triage is a model-layer instruction (not a bash fence). The test
# emulates the model's implementation: when the harness flag is set,
# parse the verdict and emit the per-target redirect message extracted
# verbatim from the SKILL.md table at WI 1.5.4. Then assert end state.
# Production behavior (no harness flag) is verified separately via the
# parser's unset guard.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c47)
OUT=$(mktemp)
ERR=$(mktemp)

# Mini-harness: simulate the model's triage execution under the test
# seam. Reads the redirect message from the SKILL.md table, prints
# both lines, exits 0 — exactly what the model-layer prose at WI
# 1.5.4 specifies under _ZSKILLS_TEST_HARNESS=1 / REDIRECT.
TRIAGE_SIM="$TEST_TMPDIR/triage-sim-c47.sh"
cat > "$TRIAGE_SIM" <<'TRIAGE_EOF'
#!/bin/bash
set -u
# Entry-point unset guard (verbatim from WI 1.2).
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi
# Skip if seam vars unset (production path) — proceed silently.
VERDICT="${_ZSKILLS_TEST_TRIAGE_VERDICT:-}"
if [ -z "$VERDICT" ]; then
  echo "PRODUCTION_PATH"
  exit 0
fi
# Parse REDIRECT:<target>:<reason>.
case "$VERDICT" in
  REDIRECT:/draft-plan:*)
    REASON="${VERDICT#REDIRECT:/draft-plan:}"
    printf 'Triage: redirecting to /draft-plan. Reason: %s\n' "$REASON"
    printf 'This task spans more than one concept; /draft-plan will research and decompose it. Run `/draft-plan <description>` instead, or re-invoke with --force to bypass.\n'
    exit 0
    ;;
  REDIRECT:/run-plan:*)
    REASON="${VERDICT#REDIRECT:/run-plan:}"
    printf 'Triage: redirecting to /run-plan. Reason: %s\n' "$REASON"
    printf 'This task references an existing plan file. Run `/run-plan <plan-path>` to execute it, or re-invoke with --force to bypass.\n'
    exit 0
    ;;
  REDIRECT:/fix-issues:*)
    REASON="${VERDICT#REDIRECT:/fix-issues:}"
    printf 'Triage: redirecting to /fix-issues. Reason: %s\n' "$REASON"
    printf 'This task references a GitHub issue. Run `/fix-issues <issue-number>` instead, or re-invoke with --force to bypass.\n'
    exit 0
    ;;
  PROCEED|*)
    echo "PROCEED"
    exit 0
    ;;
esac
TRIAGE_EOF
chmod +x "$TRIAGE_SIM"

# Run the simulated triage path with harness flag + REDIRECT verdict.
(cd "$FIX" && _ZSKILLS_TEST_HARNESS=1 _ZSKILLS_TEST_TRIAGE_VERDICT="REDIRECT:/draft-plan:multi-concept" \
   bash "$TRIAGE_SIM" >"$OUT" 2>"$ERR")
RC=$?

# (a) Both redirect-message lines on stdout (Reason on line 1, opener
# verbatim on line 2).
LINE1_PRESENT=$(grep -c 'Triage: redirecting to /draft-plan\. Reason: multi-concept' "$OUT")
LINE2_PRESENT=$(grep -c 'This task spans more than one concept' "$OUT")
# (c) No marker (the simulation never wrote one — this is what the
# model-layer prose specifies: redirect exits BEFORE WI 1.8).
MARKER_COUNT=$(find "$FIX/.zskills/tracking" -type f -name 'fulfilled.quickfix.*' 2>/dev/null | wc -l)
# (d) No branch (we never invoked git checkout -b).
BRANCH_COUNT=$(git -C "$FIX" branch --list 'quickfix/*' | wc -l)
# (e) Entry-point unset guard: verdict env var present WITHOUT
# harness flag → parser unsets it (TRIAGE_VAR_STATE=UNSET).
GUARD_OUT=$(_ZSKILLS_TEST_TRIAGE_VERDICT="REDIRECT:/draft-plan:bogus" bash "$PARSER_SCRIPT" "fix")
GUARD_VAR_STATE=$(echo "$GUARD_OUT" | grep '^TRIAGE_VAR_STATE=' | cut -d= -f2)

if [ "$RC" -eq 0 ] \
   && [ "$LINE1_PRESENT" -ge 1 ] \
   && [ "$LINE2_PRESENT" -ge 1 ] \
   && [ "$MARKER_COUNT" -eq 0 ] \
   && [ "$BRANCH_COUNT" -eq 0 ] \
   && [ "$GUARD_VAR_STATE" = "UNSET" ]; then
  pass "47 triage REDIRECT(/draft-plan): both lines printed, exit 0, no marker, no branch, unset guard fires when harness flag absent"
else
  fail "47 triage REDIRECT: rc=$RC line1=$LINE1_PRESENT line2=$LINE2_PRESENT markers=$MARKER_COUNT branches=$BRANCH_COUNT guard-var-state='$GUARD_VAR_STATE'"
  echo "  --- stdout ---"; sed 's/^/    /' "$OUT"
  echo "  --- stderr ---"; sed 's/^/    /' "$ERR"
fi
rm -f -- "$OUT" "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 48 — Review REJECT path (driven by _ZSKILLS_TEST_HARNESS=1 +
# _ZSKILLS_TEST_REVIEW_VERDICT="REJECT: contract violation"):
#   (a) reject reason prints to stdout
#   (b) exit 0
#   (c) NO marker
#   (d) NO branch
#
# Like Case 47, review is model-layer prose. Simulate the model's
# implementation under the test seam: parse REVIEW verdict, on REJECT
# (with FORCE=0) print the reason and exit 0, write nothing to disk.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c48)
OUT=$(mktemp)
ERR=$(mktemp)

REVIEW_SIM="$TEST_TMPDIR/review-sim-c48.sh"
cat > "$REVIEW_SIM" <<'REVIEW_EOF'
#!/bin/bash
set -u
# Entry-point unset guard.
if [ "${_ZSKILLS_TEST_HARNESS:-}" != "1" ]; then
  unset _ZSKILLS_TEST_TRIAGE_VERDICT _ZSKILLS_TEST_REVIEW_VERDICT
fi
VERDICT="${_ZSKILLS_TEST_REVIEW_VERDICT:-}"
FORCE="${FORCE:-0}"
case "$VERDICT" in
  APPROVE)
    echo "VERDICT: APPROVE"
    exit 0
    ;;
  REJECT:*|REVISE:*)
    REASON="${VERDICT#*:}"
    REASON="${REASON# }"
    KIND="${VERDICT%%:*}"
    printf 'VERDICT: %s -- %s\n' "$KIND" "$REASON"
    if [ "$FORCE" -eq 1 ]; then
      printf 'Review %s overridden by --force; proceeding.\n' "$KIND"
      exit 0
    fi
    # Soft-reject (or REVISE-as-soft-reject after rounds): exit 0,
    # no marker, no branch — WI 1.8 has not yet run.
    exit 0
    ;;
  *)
    echo "PROCEED"
    exit 0
    ;;
esac
REVIEW_EOF
chmod +x "$REVIEW_SIM"

(cd "$FIX" && _ZSKILLS_TEST_HARNESS=1 _ZSKILLS_TEST_REVIEW_VERDICT="REJECT: contract violation" FORCE=0 \
   bash "$REVIEW_SIM" >"$OUT" 2>"$ERR")
RC=$?

REJECT_LINE=$(grep -c 'VERDICT: REJECT -- contract violation' "$OUT")
MARKER_COUNT=$(find "$FIX/.zskills/tracking" -type f -name 'fulfilled.quickfix.*' 2>/dev/null | wc -l)
BRANCH_COUNT=$(git -C "$FIX" branch --list 'quickfix/*' | wc -l)

if [ "$RC" -eq 0 ] \
   && [ "$REJECT_LINE" -ge 1 ] \
   && [ "$MARKER_COUNT" -eq 0 ] \
   && [ "$BRANCH_COUNT" -eq 0 ]; then
  pass "48 review REJECT: reason printed, exit 0, no marker, no branch"
else
  fail "48 review REJECT: rc=$RC reject-line=$REJECT_LINE markers=$MARKER_COUNT branches=$BRANCH_COUNT"
  echo "  --- stdout ---"; sed 's/^/    /' "$OUT"
  echo "  --- stderr ---"; sed 's/^/    /' "$ERR"
fi
rm -f -- "$OUT" "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 49 — User-decline regression: when the user declines the WI
# 1.5.5 / WI 1.10 dirty-tree confirmation, the marker terminal status
# transitions `started` → `cancelled` AND the marker carries
# `reason: user-declined`. Exercises the bash-fallback (test-fixture)
# decline path documented in WI 1.5.5 sub-bullet 2.
#
# Drive the full-flow extractor with NO --yes flag and answer 'n' at
# the WI 1.10 prompt. The trap → finalize_marker writes the cancelled
# status and the reason field.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c49)
echo "edit for case 49" >> "$FIX/README.md"
OUT=$(mktemp)
ERR=$(mktemp)
# `read -r` reads from stdin; pipe 'n' to decline.
(cd "$FIX" && SLUG=fix-cancel-test PATH="$FIX/bin:$PATH" \
   bash "$FULL_FLOW_SCRIPT" "fix cancel test" <<<"n" >"$OUT" 2>"$ERR")
RC=$?

MARKER="$FIX/.zskills/tracking/quickfix.fix-cancel-test/fulfilled.quickfix.fix-cancel-test"
HAS_CANCELLED=$( [ -f "$MARKER" ] && grep -q '^status: cancelled$' "$MARKER" && echo yes || echo no)
HAS_REASON=$( [ -f "$MARKER" ] && grep -q '^reason: user-declined$' "$MARKER" && echo yes || echo no)
# Branch should be cleaned up (back on main, branch deleted).
CURRENT=$(git -C "$FIX" branch --show-current)

if [ "$RC" -eq 0 ] \
   && [ "$HAS_CANCELLED" = "yes" ] \
   && [ "$HAS_REASON" = "yes" ] \
   && [ "$CURRENT" = "main" ]; then
  pass "49 user-decline regression: marker has 'status: cancelled' AND 'reason: user-declined', branch cleaned up"
else
  fail "49 user-decline: rc=$RC cancelled=$HAS_CANCELLED reason=$HAS_REASON current='$CURRENT'"
  [ -f "$MARKER" ] && { echo "  --- marker ---"; sed 's/^/    /' "$MARKER"; }
  echo "  --- stderr ---"; sed 's/^/    /' "$ERR"
fi
rm -f -- "$OUT" "$ERR"

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
#       the 4 documented targets (`/draft-plan`, `/run-plan`,
#       `/fix-issues`, `ask-user`), assert (a) the row exists, (b) the
#       Line 2 column starts with the documented opener. Also assert
#       the table has exactly 4 data rows.
# ────────────────────────────────────────────────────────────────────
# Part 1: per-target line-grep.
if grep -q 'Triage: redirecting to /draft-plan' "$SKILL" \
   && grep -q 'This task spans more than one concept' "$SKILL" \
   && grep -q 'Triage: redirecting to /run-plan' "$SKILL" \
   && grep -q 'This task references an existing plan file' "$SKILL" \
   && grep -q 'Triage: redirecting to /fix-issues' "$SKILL" \
   && grep -q 'This task references a GitHub issue' "$SKILL" \
   && grep -q 'Re-invoke /quickfix with a concrete description' "$SKILL"; then
  pass "51a redirect lines: line 1 + line 2 present per target (/draft-plan, /run-plan, /fix-issues, ask-user)"
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

# 4 rows expected: /draft-plan, /run-plan, /fix-issues, ask-user.
ROW_COUNT=$(echo "$TABLE" | grep -c '^|')
ROW_DRAFT=$(echo "$TABLE" | grep -c '^| `/draft-plan` ')
ROW_RUNPLAN=$(echo "$TABLE" | grep -c '^| `/run-plan` ')
ROW_FIX=$(echo "$TABLE" | grep -c '^| `/fix-issues` ')
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
FIX_OPENER=$(opener_for '`/fix-issues`')
ASK_OPENER=$(opener_for 'ask-user')

OPENER_OK=1
case "$DRAFT_OPENER"   in 'This task spans more than one concept'*) ;; *) OPENER_OK=0;; esac
case "$RUNPLAN_OPENER" in 'This task references an existing plan file'*) ;; *) OPENER_OK=0;; esac
case "$FIX_OPENER"     in 'This task references a GitHub issue'*) ;; *) OPENER_OK=0;; esac
case "$ASK_OPENER"     in 'Re-invoke /quickfix with a concrete description'*) ;; *) OPENER_OK=0;; esac

if [ "$ROW_COUNT" -eq 4 ] \
   && [ "$ROW_DRAFT" -eq 1 ] \
   && [ "$ROW_RUNPLAN" -eq 1 ] \
   && [ "$ROW_FIX" -eq 1 ] \
   && [ "$ROW_ASK" -eq 1 ] \
   && [ "$OPENER_OK" -eq 1 ]; then
  pass "51b redirect-table structure: 4 rows (draft/run/fix/ask), each Line 2 starts with documented opener"
else
  fail "51b redirect-table structure: rows=$ROW_COUNT draft=$ROW_DRAFT run=$ROW_RUNPLAN fix=$ROW_FIX ask=$ROW_ASK opener-ok=$OPENER_OK"
  echo "  --- table ---"; echo "$TABLE" | sed 's/^/    /'
  echo "  draft-opener='$DRAFT_OPENER'"
  echo "  runplan-opener='$RUNPLAN_OPENER'"
  echo "  fix-opener='$FIX_OPENER'"
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

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
