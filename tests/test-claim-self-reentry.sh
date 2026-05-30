#!/bin/bash
# tests/test-claim-self-reentry.sh — Phase 1 (issue #803) W1.6.
#
# Tests ownership-aware self-re-entry:
#   (a) helper unit — skills/create-worktree/scripts/claim-self-reentry.sh:
#       - claim.json ABSENT → exit 10 (never steal)
#       - stored pipeline_id MATCHES caller → exit 0 (self)
#       - stored pipeline_id MISMATCHES caller → exit 10 (foreign)
#       - truncated/malformed claim.json → exit 10 (NOT a traceback / non-10)
#       - usage error (wrong arg count) → exit 2
#   (b) claim-issue.sh integration — acquire fresh → 0; re-acquire SAME
#       pipeline_id → 0; DIFFERENT pipeline_id → 10; dir-without-claim.json → 10
#   (c) claim-plan.sh integration — same four cases with a slug
#   (d) re-acquire-from-a-worktree-cwd — create a real git worktree, cd into
#       it, re-acquire the same id; assert exit 0 AND the claim dir is under
#       the shared common-dir's .zskills/claims/, NOT the worktree's $PWD
#       (proves MAIN_ROOT resolves to the shared common-dir, never $PWD).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/create-worktree/scripts/claim-self-reentry.sh"
ISSUE_SH="$REPO_ROOT/skills/fix-issues/scripts/claim-issue.sh"
PLAN_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# claim-plan.sh's _locate_sanitizer / _locate_self_reentry fall back to
# CLAUDE_PROJECT_DIR for the helper lookup; point it at REPO_ROOT.
export CLAUDE_PROJECT_DIR="$REPO_ROOT"

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"
if [ -z "$PYTHON" ]; then
  echo "FATAL: no Python interpreter available" >&2
  exit 1
fi

SCRATCH_ROOT="/tmp/test-claim-self-reentry-$$"
cleanup() {
  if [ -n "${TEST_KEEP_SCRATCH:-}" ]; then
    echo "TEST_KEEP_SCRATCH set — leaving $SCRATCH_ROOT" >&2
    return
  fi
  if [ -d "$SCRATCH_ROOT" ]; then
    find "$SCRATCH_ROOT" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$SCRATCH_ROOT" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$SCRATCH_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
mkdir -p "$SCRATCH_ROOT"

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && git config user.email "t@t" && git config user.name "t" \
    && git commit --allow-empty -q -m "init") || return 1
}

# Sanity: all three scripts present.
for f in "$HELPER" "$ISSUE_SH" "$PLAN_SH"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: missing $f" >&2
    exit 1
  fi
done

echo "=== claim-self-reentry.sh + twin self-re-entry tests ==="

# ───────────────────────────────────────────────────────────────────────
# (a) Helper unit tests.
# ───────────────────────────────────────────────────────────────────────
echo "--- (a) helper unit ---"

# a1: claim.json absent (dir present but no claim.json) → exit 10.
a_dir="$SCRATCH_ROOT/a-claimdir"
mkdir -p "$a_dir"
bash "$HELPER" "$a_dir" "pipe-X"
rc=$?
if [ "$rc" -eq 10 ]; then
  pass "(a1) claim.json absent → exit 10 (never steal)"
else
  fail "(a1) claim.json absent → 10" "got rc=$rc"
fi

# a2: matching pipeline_id → exit 0.
printf '{"pipeline_id": "pipe-X", "issue": 1}\n' > "$a_dir/claim.json"
bash "$HELPER" "$a_dir" "pipe-X"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(a2) matching pipeline_id → exit 0 (self)"
else
  fail "(a2) matching pipeline_id → 0" "got rc=$rc"
fi

# a3: mismatching pipeline_id → exit 10.
bash "$HELPER" "$a_dir" "pipe-OTHER"
rc=$?
if [ "$rc" -eq 10 ]; then
  pass "(a3) mismatching pipeline_id → exit 10 (foreign)"
else
  fail "(a3) mismatching pipeline_id → 10" "got rc=$rc"
fi

# a4: truncated/malformed claim.json → exit 10 (NOT a traceback / non-10).
trunc_dir="$SCRATCH_ROOT/a-trunc"
mkdir -p "$trunc_dir"
printf '{"pipeline_id": "x"' > "$trunc_dir/claim.json"  # no closing brace
helper_out=$(bash "$HELPER" "$trunc_dir" "x" 2>&1)
rc=$?
# Must be a clean exit 10, and stdout/stderr must NOT contain a python
# traceback (deterministic foreign, never steal, never crash).
if [ "$rc" -eq 10 ] && ! printf '%s' "$helper_out" | grep -q 'Traceback'; then
  pass "(a4) truncated/malformed claim.json → exit 10, no traceback"
else
  fail "(a4) truncated claim.json → 10" "got rc=$rc out=<$helper_out>"
fi

# a5: usage error (wrong arg count) → exit 2.
bash "$HELPER" "$a_dir" 2>/dev/null  # only one arg
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "(a5) wrong arg count → exit 2 (usage)"
else
  fail "(a5) usage → 2" "got rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# (b) claim-issue.sh integration.
# ───────────────────────────────────────────────────────────────────────
echo "--- (b) claim-issue.sh integration ---"
b_repo="$SCRATCH_ROOT/b-repo"
make_repo "$b_repo" || { echo "FATAL repo init"; exit 1; }

# b1: acquire fresh → 0.
(cd "$b_repo" && bash "$ISSUE_SH" acquire 42 --pipeline-id "fix-issues.A" --sprint-id "fix-issues.A")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(b1) issue acquire fresh → exit 0"
else
  fail "(b1) issue acquire fresh → 0" "got rc=$rc"
fi

# b2: re-acquire SAME pipeline_id → 0 (self-re-entry).
(cd "$b_repo" && bash "$ISSUE_SH" acquire 42 --pipeline-id "fix-issues.A" --sprint-id "fix-issues.A")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(b2) issue re-acquire SAME pipeline_id → exit 0 (self-re-entry)"
else
  fail "(b2) issue re-acquire SAME → 0" "got rc=$rc"
fi

# b3: re-acquire DIFFERENT pipeline_id → 10 (foreign).
(cd "$b_repo" && bash "$ISSUE_SH" acquire 42 --pipeline-id "fix-issues.B" --sprint-id "fix-issues.B") 2>/dev/null
rc=$?
if [ "$rc" -eq 10 ]; then
  pass "(b3) issue re-acquire DIFFERENT pipeline_id → exit 10 (foreign)"
else
  fail "(b3) issue re-acquire DIFFERENT → 10" "got rc=$rc"
fi

# b4: dir-without-claim.json → 10 (never steal a half-written/crashed stub).
b_stub="$b_repo/.zskills/claims/issue-99"
mkdir -p "$b_stub"   # claim dir exists but no claim.json
(cd "$b_repo" && bash "$ISSUE_SH" acquire 99 --pipeline-id "fix-issues.A" --sprint-id "fix-issues.A") 2>/dev/null
rc=$?
if [ "$rc" -eq 10 ]; then
  pass "(b4) issue dir-without-claim.json → exit 10 (never steal)"
else
  fail "(b4) issue dir-without-claim.json → 10" "got rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# (c) claim-plan.sh integration.
# ───────────────────────────────────────────────────────────────────────
echo "--- (c) claim-plan.sh integration ---"
c_repo="$SCRATCH_ROOT/c-repo"
make_repo "$c_repo" || { echo "FATAL repo init"; exit 1; }

# c1: acquire fresh → 0.
(cd "$c_repo" && bash "$PLAN_SH" acquire myplan --pipeline-id "run-plan.myplan")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(c1) plan acquire fresh → exit 0"
else
  fail "(c1) plan acquire fresh → 0" "got rc=$rc"
fi

# c2: re-acquire SAME pipeline_id → 0 (self-re-entry).
(cd "$c_repo" && bash "$PLAN_SH" acquire myplan --pipeline-id "run-plan.myplan")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(c2) plan re-acquire SAME pipeline_id → exit 0 (self-re-entry)"
else
  fail "(c2) plan re-acquire SAME → 0" "got rc=$rc"
fi

# c3: re-acquire DIFFERENT pipeline_id → 10 (foreign).
(cd "$c_repo" && bash "$PLAN_SH" acquire myplan --pipeline-id "run-plan.other") 2>/dev/null
rc=$?
if [ "$rc" -eq 10 ]; then
  pass "(c3) plan re-acquire DIFFERENT pipeline_id → exit 10 (foreign)"
else
  fail "(c3) plan re-acquire DIFFERENT → 10" "got rc=$rc"
fi

# c4: dir-without-claim.json → 10.
c_stub="$c_repo/.zskills/claims/plan-stub"
mkdir -p "$c_stub"
(cd "$c_repo" && bash "$PLAN_SH" acquire stub --pipeline-id "run-plan.myplan") 2>/dev/null
rc=$?
if [ "$rc" -eq 10 ]; then
  pass "(c4) plan dir-without-claim.json → exit 10 (never steal)"
else
  fail "(c4) plan dir-without-claim.json → 10" "got rc=$rc"
fi

# ───────────────────────────────────────────────────────────────────────
# (d) re-acquire-from-a-worktree-cwd: claim lands under the SHARED
# common-dir, and self-re-entry from inside the worktree returns 0.
# ───────────────────────────────────────────────────────────────────────
echo "--- (d) re-acquire from a worktree cwd ---"
d_main="$SCRATCH_ROOT/d-main"
make_repo "$d_main" || { echo "FATAL repo init"; exit 1; }
d_wt="$SCRATCH_ROOT/d-wt"
# Create a real linked worktree off the main repo.
(cd "$d_main" && git worktree add -q "$d_wt" -b feat/d-branch) || { echo "FATAL worktree add"; exit 1; }

# First acquire FROM the worktree cwd (issue side).
(cd "$d_wt" && bash "$ISSUE_SH" acquire 7 --pipeline-id "do.d7" --sprint-id "do.d7")
rc_first=$?
# The claim dir must be under the MAIN repo's .zskills/claims/, NOT the
# worktree's $PWD (MAIN_ROOT resolves via git-common-dir parent).
main_claim="$d_main/.zskills/claims/issue-7/claim.json"
wt_claim="$d_wt/.zskills/claims/issue-7/claim.json"
if [ "$rc_first" -eq 0 ] && [ -f "$main_claim" ] && [ ! -f "$wt_claim" ]; then
  pass "(d1) acquire from worktree cwd lands claim under shared common-dir, not \$PWD"
else
  fail "(d1) worktree acquire main-root anchor" "rc=$rc_first main=$([ -f "$main_claim" ] && echo yes || echo no) wt=$([ -f "$wt_claim" ] && echo yes || echo no)"
fi

# Re-acquire the SAME id from inside the worktree → self-re-entry → 0.
(cd "$d_wt" && bash "$ISSUE_SH" acquire 7 --pipeline-id "do.d7" --sprint-id "do.d7")
rc_re=$?
if [ "$rc_re" -eq 0 ] && [ -f "$main_claim" ] && [ ! -f "$wt_claim" ]; then
  pass "(d2) re-acquire SAME id from worktree cwd → exit 0; claim still under shared common-dir"
else
  fail "(d2) worktree self-re-entry" "rc=$rc_re main=$([ -f "$main_claim" ] && echo yes || echo no) wt=$([ -f "$wt_claim" ] && echo yes || echo no)"
fi

# Clean up the worktree before the trap (so rmdir of SCRATCH succeeds).
(cd "$d_main" && git worktree remove --force "$d_wt") 2>/dev/null || true

# ───────────────────────────────────────────────────────────────────────
# (e) Locale-independence: self-re-entry must work under a non-English
# LC_MESSAGES locale (issue #827). The twin scripts grep mkdir's stderr
# for the literal English "File exists" to detect EEXIST. On a localized
# locale the diagnostic translates and the case arm misses, silently
# returning rc=11 instead of routing to self-re-entry. The fix forces
# `LC_ALL=C` on the mkdir invocation. If a non-English locale is
# unavailable in this environment (devcontainers commonly only ship C +
# en_US.utf8), the test gracefully degrades and still asserts the
# C-locale path keeps working.
# ───────────────────────────────────────────────────────────────────────
echo "--- (e) locale-independence ---"

# Pick a non-English locale if one is installed. Prefer fr_FR.UTF-8;
# accept any non-C/non-en locale otherwise. `locale -a` is POSIX-portable.
pick_localized_locale() {
  local cand
  for cand in fr_FR.UTF-8 fr_FR.utf8 de_DE.UTF-8 de_DE.utf8 es_ES.UTF-8 es_ES.utf8 ja_JP.UTF-8 ja_JP.utf8; do
    if locale -a 2>/dev/null | grep -Fxq "$cand"; then
      printf '%s' "$cand"
      return 0
    fi
  done
  # Fall back to any installed locale that isn't C/POSIX/en*.
  cand=$(locale -a 2>/dev/null | grep -viE '^(C|POSIX|en[_.])' | head -n 1)
  if [ -n "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi
  return 1
}

e_repo="$SCRATCH_ROOT/e-repo"
make_repo "$e_repo" || { echo "FATAL repo init"; exit 1; }

# e1 (always runs): acquire under LC_ALL=C — fresh acquire → 0.
(cd "$e_repo" && LC_ALL=C bash "$ISSUE_SH" acquire 17 --pipeline-id "fix-issues.E" --sprint-id "fix-issues.E")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(e1) acquire under LC_ALL=C fresh → exit 0"
else
  fail "(e1) acquire under LC_ALL=C fresh → 0" "got rc=$rc"
fi

# e2 (always runs): re-acquire SAME id under LC_ALL=C — self-re-entry → 0.
(cd "$e_repo" && LC_ALL=C bash "$ISSUE_SH" acquire 17 --pipeline-id "fix-issues.E" --sprint-id "fix-issues.E")
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "(e2) re-acquire SAME id under LC_ALL=C → exit 0 (self-re-entry)"
else
  fail "(e2) re-acquire SAME id under LC_ALL=C → 0" "got rc=$rc"
fi

# e3: re-acquire SAME id under a NON-ENGLISH LC_ALL — must still route to
# self-re-entry (rc=0), NOT silently return rc=11 because the localized
# "File exists" diagnostic missed the case arm.
LOCALE=""
if LOCALE=$(pick_localized_locale); then
  (cd "$e_repo" && LC_ALL="$LOCALE" bash "$ISSUE_SH" acquire 17 --pipeline-id "fix-issues.E" --sprint-id "fix-issues.E")
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "(e3) re-acquire SAME id under LC_ALL=$LOCALE → exit 0 (self-re-entry survives localized mkdir diagnostic)"
  elif [ "$rc" -eq 11 ]; then
    fail "(e3) re-acquire SAME id under LC_ALL=$LOCALE → 0" "got rc=11 — LC_ALL=C prefix on mkdir is missing or ineffective (issue #827 regression)"
  else
    fail "(e3) re-acquire SAME id under LC_ALL=$LOCALE → 0" "got rc=$rc"
  fi

  # e4: same coverage for the plan twin.
  e_prepo="$SCRATCH_ROOT/e-prepo"
  make_repo "$e_prepo" || { echo "FATAL repo init"; exit 1; }
  (cd "$e_prepo" && LC_ALL=C bash "$PLAN_SH" acquire eplan --pipeline-id "run-plan.E") >/dev/null
  (cd "$e_prepo" && LC_ALL="$LOCALE" bash "$PLAN_SH" acquire eplan --pipeline-id "run-plan.E")
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "(e4) plan re-acquire SAME id under LC_ALL=$LOCALE → exit 0 (self-re-entry survives localized mkdir diagnostic)"
  elif [ "$rc" -eq 11 ]; then
    fail "(e4) plan re-acquire SAME id under LC_ALL=$LOCALE → 0" "got rc=11 — LC_ALL=C prefix on mkdir is missing or ineffective (issue #827 regression)"
  else
    fail "(e4) plan re-acquire SAME id under LC_ALL=$LOCALE → 0" "got rc=$rc"
  fi
else
  echo "  NOTE: no non-English locale installed (locale -a lists only C / POSIX / en*);" >&2
  echo "        skipping (e3,e4) localized-diagnostic assertions. The fix is" >&2
  echo "        still in place — LC_ALL=C prefix on mkdir in both claim-plan.sh" >&2
  echo "        and claim-issue.sh — and the C-locale path (e1,e2) covers" >&2
  echo "        the unchanged-behavior side. Install fr_FR.UTF-8 (or any" >&2
  echo "        non-English UTF-8 locale) to exercise the localized branch." >&2
fi

# ───────────────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (%d total)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (%d total)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
