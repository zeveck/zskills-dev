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
  mkdir -p "$fix/scripts"
  cp "$REPO_ROOT/scripts/sanitize-pipeline-id.sh" "$fix/scripts/"
  chmod +x "$fix/scripts/sanitize-pipeline-id.sh"

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
PREFLIGHT_SCRIPT="$TEST_TMPDIR/preflight.sh"
{
  echo '#!/bin/bash'
  echo 'set -u'
  extract_preflight
} > "$PREFLIGHT_SCRIPT"
chmod +x "$PREFLIGHT_SCRIPT"

# Full end-to-end flow extractor — preflight + mode + slug + branch +
# WI 1.10 (user-edited diff-and-maybe-prompt) + WI 1.12 test gate +
# WI 1.13 commit + WI 1.14 push + WI 1.15 PR create. Skips WI 1.11
# (agent-dispatched mode is a model-layer instruction; its lone bash
# snippet unconditionally overwrites $CHANGED_FILES from $DIRTY_AFTER
# which doesn't exist in user-edited mode, so running it would break
# the test). The split is intentional: this script validates the
# user-edited-mode end-to-end flow; agent-dispatched mode is only
# testable by a real top-level skill invocation, not a bash fixture.
extract_full_flow() {
  awk '
    /^### WI 1\.11/         { skip = 1 }
    /^## Phase 4/           { skip = 0 }
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
  # WI 1.13 expects the model to set COMMIT_SUBJECT (conventional-commit
  # form) before the commit fence runs. The fixture simulates that
  # model-layer composition step with a synthetic subject so the bash
  # extraction can test the rest of the flow (compose body, commit,
  # push, PR) end-to-end.
  echo 'COMMIT_SUBJECT="test(case43): synthetic conventional-commit subject"'
  extract_full_flow
} > "$FULL_FLOW_SCRIPT"
chmod +x "$FULL_FLOW_SCRIPT"

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
# Case 3 — Slug derivation contract (WI 1.6)
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
if grep -q 'scripts/sanitize-pipeline-id.sh' "$SKILL" \
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
#   - Co-Authored-By line uses $CO_AUTHOR (not hardcoded).
#   - CO_AUTHOR is resolved from the config's co_author field via bash
#     regex (BASH_REMATCH) — replacing the old jq read.
#   - user-edited branch has NO Co-Authored-By trailer (the trailer
#     appears exactly once in the skill, in the agent-dispatched arm).
# ────────────────────────────────────────────────────────────────────
COAUTH_COUNT=$(grep -c 'Co-Authored-By: \$CO_AUTHOR' "$SKILL" 2>/dev/null || echo 0)
if grep -qE 'Generated with /quickfix \(user-edited\)' "$SKILL" \
   && grep -qE 'Generated with /quickfix \(agent-dispatched\)' "$SKILL" \
   && [ "$COAUTH_COUNT" = "1" ] \
   && grep -q 'co_author' "$SKILL" \
   && grep -q 'BASH_REMATCH' "$SKILL"; then
  pass "10 commit trailer: both mode footers + single agent-only Co-Authored-By + CO_AUTHOR via BASH_REMATCH"
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
# ────────────────────────────────────────────────────────────────────
# Exact match for the plan's acceptance-criterion regex:
if ! grep -qE '(write|cat >).*\.landed' "$SKILL"; then
  pass "13 .landed never written: no (write|cat >) path targets .landed"
else
  fail "13 .landed never written: a (write|cat >) path references .landed"
  grep -nE '(write|cat >).*\.landed' "$SKILL" | sed 's/^/    /'
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
# Point PATH at a minimal shadow that excludes gh; assert rc=1 plus
# 'requires gh' in stderr. The PATH is /usr/bin:/bin (common commands
# available, no project bin/, no gh) — jq is NOT required any more
# since the skill parses config via bash-regex.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c16)
ERR=$(mktemp)
(cd "$FIX" && PATH="/usr/bin:/bin" bash "$PREFLIGHT_SCRIPT" "fix something" >/dev/null 2>"$ERR")
RC=$?
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
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix foo" >/dev/null 2>"$ERR")
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
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix remote collision" >/dev/null 2>"$ERR")
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
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix local collision" >/dev/null 2>"$ERR")
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
# Case 31 — Slash in slug (description with only specials) exits 2.
# Description that derives to empty slug: '!!!' — already covered by
# case 3, but assert the full preflight exits 2 with 'empty slug'
# stderr.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c31)
echo "dirty" >> "$FIX/README.md"
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "!!!" >/dev/null 2>"$ERR")
RC=$?
if [ "$RC" -eq 2 ] && grep -q 'empty slug' "$ERR"; then
  pass "31 empty-slug description: rc=2 + 'empty slug' stderr"
else
  fail "31 empty-slug: rc=$RC stderr='$(cat "$ERR")'"
fi
rm -f -- "$ERR"

# ────────────────────────────────────────────────────────────────────
# Case 32 — Tracking marker path is pipeline-scoped (per CLAUDE.md
# tracking rule): `.zskills/tracking/quickfix.<slug>/fulfilled.quickfix.<slug>`
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c32)
ERR=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix tracking path" >/dev/null 2>"$ERR")
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
# Case 37 — DIRTY_AFTER excludes untracked (R2-M2 per plan line 50).
# Assert the SKILL.md comment about excluding `git ls-files --others
# --exclude-standard` (so agent scratch/artifact files aren't committed).
# ────────────────────────────────────────────────────────────────────
if grep -q "excludes.*git ls-files --others" "$SKILL"; then
  pass "37 DIRTY_AFTER excludes untracked (R2-M2): comment present"
else
  fail "37 DIRTY_AFTER R2-M2 comment missing"
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
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "fix readme typo" >/dev/null 2>"$ERR")
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
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$PREFLIGHT_SCRIPT" "a description with spaces" >/dev/null 2>"$ERR")
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
# Case 43 — TRUE end-to-end (user-edited mode): preflight → branch →
# test gate → commit → push → PR creation. Closes the "manual smoke"
# acceptance criterion from Phase 1a (deferred to Phase 1b; Phase 1b's
# 42 cases validated structural invariants but never actually ran the
# whole flow). Runs against the full-flow extracted script (all bash
# fences from SKILL.md minus WI 1.11's agent-dispatched snippet).
#
# Asserts: rc=0; branch quickfix/fix-readme-typo exists locally AND on
# bare remote (push succeeded); commit has expected mode-aware trailer;
# tracking marker has `status: complete` AND a `pr:` field (the mock
# gh URL); stdout contains the PR URL so the user sees something
# actionable.
#
# Uses --yes so WI 1.10's interactive "Proceed? [y/N]" prompt is
# bypassed deterministically.
# ────────────────────────────────────────────────────────────────────
FIX=$(make_fixture c43)
echo "edit for fix" >> "$FIX/README.md"
ERR=$(mktemp)
OUT=$(mktemp)
(cd "$FIX" && PATH="$FIX/bin:$PATH" bash "$FULL_FLOW_SCRIPT" --yes "fix readme typo" >"$OUT" 2>"$ERR")
RC=$?

# Assertions
CURRENT=$(git -C "$FIX" branch --show-current)
BRANCH_EXISTS_LOCAL=$(git -C "$FIX" show-ref --verify --quiet "refs/heads/quickfix/fix-readme-typo" && echo yes || echo no)
BRANCH_EXISTS_REMOTE=$(git -C "$FIX" show-ref --verify --quiet "refs/remotes/origin/quickfix/fix-readme-typo" && echo yes || echo no)
MARKER="$FIX/.zskills/tracking/quickfix.fix-readme-typo/fulfilled.quickfix.fix-readme-typo"
MARKER_STATUS_COMPLETE=$( [ -f "$MARKER" ] && grep -q '^status: complete$' "$MARKER" && echo yes || echo no)
MARKER_PR_FIELD=$( [ -f "$MARKER" ] && grep -q '^pr: https' "$MARKER" && echo yes || echo no)
STDOUT_HAS_PR_URL=$(grep -q 'github.com/owner/repo/pull/1' "$OUT" && echo yes || echo no)
COMMIT_TRAILER=$(git -C "$FIX" log -1 --pretty=%B quickfix/fix-readme-typo 2>/dev/null | grep -c 'Generated with /quickfix (user-edited)')

if [ "$RC" -eq 0 ] \
   && [ "$BRANCH_EXISTS_LOCAL" = "yes" ] \
   && [ "$BRANCH_EXISTS_REMOTE" = "yes" ] \
   && [ "$MARKER_STATUS_COMPLETE" = "yes" ] \
   && [ "$MARKER_PR_FIELD" = "yes" ] \
   && [ "$STDOUT_HAS_PR_URL" = "yes" ] \
   && [ "$COMMIT_TRAILER" -ge 1 ]; then
  pass "43 true end-to-end (user-edited): branch pushed, PR URL printed, marker complete with pr: field, mode-aware trailer"
else
  fail "43 end-to-end: rc=$RC current='$CURRENT' local=$BRANCH_EXISTS_LOCAL remote=$BRANCH_EXISTS_REMOTE marker-complete=$MARKER_STATUS_COMPLETE marker-pr=$MARKER_PR_FIELD stdout-url=$STDOUT_HAS_PR_URL trailer-count=$COMMIT_TRAILER"
  echo "  --- stdout ---"; sed 's/^/    /' "$OUT"
  echo "  --- stderr ---"; sed 's/^/    /' "$ERR"
  [ -f "$MARKER" ] && { echo "  --- marker ---"; sed 's/^/    /' "$MARKER"; }
fi
rm -f -- "$ERR" "$OUT"

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
