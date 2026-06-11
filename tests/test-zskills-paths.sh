#!/bin/bash
# Tests for skills/update-zskills/scripts/zskills-paths.sh —
# the canonical path-resolution helper introduced in
# plans/ZSKILLS_PATH_CONFIG.md Phase 1.
#
# Cases (≥9 per Phase 1.8 table; cases 10a-13 added for reports_dir per
# REPORTS_DIR_MIGRATION.md Phase 1, WI 1.8; fallback expectations RE-SPECCED
# + cases 15-17 added by INSTALL_REDESIGN Phase 5 — config cascade
# project > user > built-in defaults, defaults = docs/{plans,issues,reports}
# pinned to zskills-defaults.json):
#   1. Empty config → $ZSKILLS_PLANS_DIR == $ROOT/docs/plans (built-in
#      default; Phase 5 re-spec — was legacy $ROOT/plans).
#   2. output.plans_dir = "docs/plans" → $ZSKILLS_PLANS_DIR == $ROOT/docs/plans.
#   3. output.plans_dir = "/tmp/x" → $ZSKILLS_PLANS_DIR == /tmp/x (absolute).
#   4. output.plans_dir = "../external/zskills" → $ROOT/../external/zskills (joined).
#   5. Both $CLAUDE_PROJECT_DIR AND $ZSKILLS_PATHS_ROOT unset → non-zero
#      with stderr naming both vars (subshell-unset idiom).
#   6a. Garbage config (not JSON) → silent fallback to docs/plans (re-spec).
#   6b. Truncated JSON → silent fallback (closing-brace anchor; re-spec).
#   7. output.plans_dir = "" (empty string) → built-in default (re-spec).
#   8. $ZSKILLS_PATHS_ROOT set, $CLAUDE_PROJECT_DIR unset → uses $ZSKILLS_PATHS_ROOT.
#   9. After source, env | grep '^ZSKILLS_PLANS_DIR=' is empty (vars not exported).
#   10a. Config file absent → $ZSKILLS_REPORTS_DIR == $ROOT/docs/reports
#      (Phase 5 re-spec — was legacy $ROOT/.zskills/audit).
#   10b. Config present, reports_dir key absent → $ROOT/docs/reports (re-spec).
#   11. output.reports_dir = "build/audit" → $ROOT/build/audit (relative joined).
#   12. output.reports_dir = "/abs/path/reports" → /abs/path/reports (absolute as-is).
#   13. Malformed JSON (truncated reports_dir) → docs/reports default (re-spec).
#   14. Source vs mirror byte-identical (parity check; was Case 10).
#   15. User tier alone (HOME-sandboxed) supplies output.* keys.
#   16. Precedence: project match wins per key; user fills project-absent keys.
#   17. Malformed user file → ignored; project + defaults result.
#
# HOME is sandboxed ($EMPTY_HOME / per-case user homes) in every
# value-asserting case — the helper reads the USER tier from
# $HOME/.claude/zskills-config.json (Phase 5 cascade).
#
# Run from repo root: bash tests/test-zskills-paths.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh"
MIRROR_HELPER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

# HOME sandbox (Phase 5 cascade): empty user tier for project-only /
# defaults-only assertions; cascade cases build their own user homes.
EMPTY_HOME=$(mktemp -d /tmp/zskills-paths-home-XXXXXX)

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if [ ! -f "$HELPER" ]; then
  fail "helper exists at expected path" "$HELPER missing"
  printf 'Results: %d passed, %d failed (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit 1
fi

# --- Case 1: empty config → built-in defaults -------------------------------
# Phase 5 RE-SPEC (intended assertion change, INSTALL_REDESIGN Phase 5):
# OLD: no config → legacy <root>/plans (pre-migration back-compat). NEW: no
# config at EITHER tier → the built-in defaults docs/{plans,issues}, PINNED
# ≡ zskills-defaults.json by the conformance congruence check — so a
# zero-config consumer gets the documented docs/ layout with no file at
# all. (The old REGRESSION ANCHOR comment guarding the legacy fallback is
# retired by this re-spec: the scaffold defaults and the resolver defaults
# are now deliberately the SAME values, kept congruent through the one
# canonical JSON.)
echo "=== Case 1: empty config — $ZSKILLS_PLANS_DIR defaults to <root>/docs/plans ==="
T1=$(mktemp -d /tmp/zskills-paths-t1-XXXXXX)
# No config file at all.
RESULT1=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T1" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR" "$ZSKILLS_AUDIT_DIR"'
)
C1_PLANS=$(printf '%s\n' "$RESULT1" | sed -n '1p')
C1_ISSUES=$(printf '%s\n' "$RESULT1" | sed -n '2p')
C1_AUDIT=$(printf '%s\n' "$RESULT1" | sed -n '3p')
[ "$C1_PLANS" = "$T1/docs/plans" ] \
  && pass "Case 1a: empty config → \$ZSKILLS_PLANS_DIR = '<root>/docs/plans' (built-in default)" \
  || fail "Case 1a: \$ZSKILLS_PLANS_DIR" "got '$C1_PLANS', expected '$T1/docs/plans'"
[ "$C1_ISSUES" = "$T1/docs/issues" ] \
  && pass "Case 1b: empty config → \$ZSKILLS_ISSUES_DIR = '<root>/docs/issues' (built-in default)" \
  || fail "Case 1b: \$ZSKILLS_ISSUES_DIR" "got '$C1_ISSUES', expected '$T1/docs/issues'"
[ "$C1_AUDIT" = "$T1/.zskills/audit" ] \
  && pass "Case 1c: \$ZSKILLS_AUDIT_DIR = '<root>/.zskills/audit'" \
  || fail "Case 1c: \$ZSKILLS_AUDIT_DIR" "got '$C1_AUDIT', expected '$T1/.zskills/audit'"
rm -rf "$T1"

# --- Case 2: relative plans_dir → joined with root --------------------------
echo ""
echo "=== Case 2: output.plans_dir = 'docs/plans' → \$ZSKILLS_PLANS_DIR = <root>/docs/plans ==="
T2=$(mktemp -d /tmp/zskills-paths-t2-XXXXXX)
mkdir -p "$T2/.claude"
cat > "$T2/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "plans_dir": "docs/plans",
    "issues_dir": "docs/issues"
  }
}
CFG
RESULT2=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T2" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR"'
)
C2_PLANS=$(printf '%s\n' "$RESULT2" | sed -n '1p')
C2_ISSUES=$(printf '%s\n' "$RESULT2" | sed -n '2p')
[ "$C2_PLANS" = "$T2/docs/plans" ] \
  && pass "Case 2a: \$ZSKILLS_PLANS_DIR = '<root>/docs/plans'" \
  || fail "Case 2a: \$ZSKILLS_PLANS_DIR" "got '$C2_PLANS', expected '$T2/docs/plans'"
[ "$C2_ISSUES" = "$T2/docs/issues" ] \
  && pass "Case 2b: \$ZSKILLS_ISSUES_DIR = '<root>/docs/issues'" \
  || fail "Case 2b: \$ZSKILLS_ISSUES_DIR" "got '$C2_ISSUES', expected '$T2/docs/issues'"
rm -rf "$T2"

# --- Case 3: absolute plans_dir → used as-is --------------------------------
echo ""
echo "=== Case 3: output.plans_dir = '/tmp/x' → \$ZSKILLS_PLANS_DIR = '/tmp/x' (absolute) ==="
T3=$(mktemp -d /tmp/zskills-paths-t3-XXXXXX)
mkdir -p "$T3/.claude"
cat > "$T3/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "plans_dir": "/tmp/x"
  }
}
CFG
C3_PLANS=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T3" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_PLANS_DIR"'
)
[ "$C3_PLANS" = "/tmp/x" ] \
  && pass "Case 3: absolute plans_dir used as-is" \
  || fail "Case 3: absolute plans_dir" "got '$C3_PLANS', expected '/tmp/x'"
rm -rf "$T3"

# --- Case 4: ../external joined with root ---------------------------------
echo ""
echo "=== Case 4: output.plans_dir = '../external/zskills' → joined with <root> ==="
T4=$(mktemp -d /tmp/zskills-paths-t4-XXXXXX)
mkdir -p "$T4/.claude"
cat > "$T4/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "plans_dir": "../external/zskills"
  }
}
CFG
C4_PLANS=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T4" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_PLANS_DIR"'
)
[ "$C4_PLANS" = "$T4/../external/zskills" ] \
  && pass "Case 4: '../external/zskills' joined with <root> (NOT caller cwd)" \
  || fail "Case 4: relative-up path" "got '$C4_PLANS', expected '$T4/../external/zskills'"
rm -rf "$T4"

# --- Case 5: both vars unset, contract depends on whether cwd is in a git repo
#
# Old contract (pre-CLAUDE_PROJECT_DIR-fallback PR): both unset → fail loud
# everywhere. New contract: in a git repo, fall back to git-common-dir with
# a one-time stderr WARN; outside a git repo, the old loud-failure path
# still applies because no clean fallback exists. See zskills-resolve-config.sh
# header and zskills-paths.sh resolution block.

echo ""
echo "=== Case 5a: both vars unset, IN a git repo → succeed via git-common-dir fallback ==="
# tests/run-all.sh exports CLAUDE_PROJECT_DIR globally; unset must happen
# INSIDE a subshell that inherits then unsets both. Subshell stays in the
# repo root, so `git rev-parse --git-common-dir` resolves successfully.
( unset CLAUDE_PROJECT_DIR ZSKILLS_PATHS_ROOT _ZSK_FALLBACK_WARNED
  source "$HELPER"
) 2> "$TEST_OUT/case5a.stderr"
rc=$?
if [ "$rc" = "0" ]; then
  pass "Case 5a: helper rc=0 via git-common-dir fallback"
else
  fail "Case 5a: helper rc=0 via fallback" \
    "expected 0, got $rc; stderr: $(cat "$TEST_OUT/case5a.stderr")"
fi
if grep -qE "WARN.*fell back.*git-common-dir" "$TEST_OUT/case5a.stderr"; then
  pass "Case 5a: stderr contains 'WARN ... fell back ... git-common-dir'"
else
  fail "Case 5a: stderr fallback WARN" \
    "got: $(cat "$TEST_OUT/case5a.stderr")"
fi

echo ""
echo "=== Case 5b: both vars unset, NOT in a git repo → fail loud ==="
# Fixture: a tempdir with no .git ancestor (mktemp paths under /tmp have
# no git parent). cd there before sourcing so git-common-dir returns
# non-zero and the fallback path falls through to the error branch.
T5B=$(mktemp -d /tmp/zskills-paths-t5b-XXXXXX)
( cd "$T5B"
  unset CLAUDE_PROJECT_DIR ZSKILLS_PATHS_ROOT _ZSK_FALLBACK_WARNED GIT_DIR GIT_WORK_TREE
  source "$HELPER"
) 2> "$TEST_OUT/case5b.stderr"
rc=$?
if [ "$rc" != "0" ]; then
  pass "Case 5b: helper exits non-zero when both vars unset and not in git repo (rc=$rc)"
else
  fail "Case 5b: helper exit code" \
    "expected non-zero, got $rc; stderr: $(cat "$TEST_OUT/case5b.stderr")"
fi
if grep -q "ZSKILLS_PATHS_ROOT" "$TEST_OUT/case5b.stderr"; then
  pass "Case 5b: stderr names ZSKILLS_PATHS_ROOT"
else
  fail "Case 5b: stderr ZSKILLS_PATHS_ROOT mention" \
    "got: $(cat "$TEST_OUT/case5b.stderr")"
fi
if grep -q "CLAUDE_PROJECT_DIR" "$TEST_OUT/case5b.stderr"; then
  pass "Case 5b: stderr names CLAUDE_PROJECT_DIR"
else
  fail "Case 5b: stderr CLAUDE_PROJECT_DIR mention" \
    "got: $(cat "$TEST_OUT/case5b.stderr")"
fi
rm -rf "$T5B"

# --- Case 6a: garbage (non-JSON) config → silent fallback ------------------
echo ""
echo "=== Case 6a: garbage config (not JSON at all) → silent fallback to docs/plans default ==="
T6A=$(mktemp -d /tmp/zskills-paths-t6a-XXXXXX)
mkdir -p "$T6A/.claude"
cat > "$T6A/.claude/zskills-config.json" <<'GARBAGE'
not json at all
GARBAGE
RESULT6A=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T6A" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR"' 2>&1
)
RC6A=$?
C6A_PLANS=$(printf '%s\n' "$RESULT6A" | sed -n '1p')
# Phase 5 re-spec: fallback target is the built-in default docs/plans.
if [ "$RC6A" -eq 0 ] && [ "$C6A_PLANS" = "$T6A/docs/plans" ]; then
  pass "Case 6a: garbage config → rc=0 + docs/plans default"
else
  fail "Case 6a: garbage config fallback" "rc=$RC6A plans='$C6A_PLANS' (expected '$T6A/docs/plans')"
fi
rm -rf "$T6A"

# --- Case 6b: truncated JSON → silent fallback (closing-brace anchor) ------
echo ""
echo "=== Case 6b: truncated JSON missing outer } → silent fallback ==="
T6B=$(mktemp -d /tmp/zskills-paths-t6b-XXXXXX)
mkdir -p "$T6B/.claude"
# Missing OUTER closing brace of the top-level object. The inner output
# object does close with } — so the regex's [^}]*\} clause WILL match the
# inner close. The closing-brace anchor's purpose is preventing
# unterminated VALUE strings, not unbalanced top-level objects per se.
# Per the plan's example: {"output":{"plans_dir":"DROP"} (missing outer
# }). This actually closes the inner output object so the regex matches
# and DROP is captured. The plan text describes a stricter expectation
# than the regex implements; honor what the regex does.
#
# To exercise the closing-brace anchor as the plan intends, write a
# fixture where the inner object is also unclosed: the value DROP is
# present but no closing brace anywhere after it. Then [^}]*\} cannot
# match and the helper falls back.
printf '%s' '{"output":{"plans_dir":"DROP"' > "$T6B/.claude/zskills-config.json"
RESULT6B=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T6B" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_PLANS_DIR"' 2>&1
)
RC6B=$?
C6B_PLANS=$(printf '%s\n' "$RESULT6B" | sed -n '1p')
# Phase 5 re-spec: fallback target is the built-in default docs/plans.
if [ "$RC6B" -eq 0 ] && [ "$C6B_PLANS" = "$T6B/docs/plans" ]; then
  pass "Case 6b: truncated JSON (no closing brace) → rc=0 + docs/plans default"
else
  fail "Case 6b: truncated JSON fallback" "rc=$RC6B plans='$C6B_PLANS' (expected '$T6B/docs/plans')"
fi
rm -rf "$T6B"

# --- Case 7: empty-string plans_dir → fallback ----------------------------
echo ""
echo "=== Case 7: output.plans_dir = '' → built-in defaults ==="
T7=$(mktemp -d /tmp/zskills-paths-t7-XXXXXX)
mkdir -p "$T7/.claude"
cat > "$T7/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "plans_dir": "",
    "issues_dir": ""
  }
}
CFG
RESULT7=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T7" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR"'
)
C7_PLANS=$(printf '%s\n' "$RESULT7" | sed -n '1p')
C7_ISSUES=$(printf '%s\n' "$RESULT7" | sed -n '2p')
# Phase 5 re-spec: empty-string values fall to the built-in defaults.
[ "$C7_PLANS" = "$T7/docs/plans" ] && [ "$C7_ISSUES" = "$T7/docs/issues" ] \
  && pass "Case 7: empty-string values fall back to built-in docs/ defaults" \
  || fail "Case 7: empty-string fallback" "plans='$C7_PLANS' issues='$C7_ISSUES'"
rm -rf "$T7"

# --- Case 8: ZSKILLS_PATHS_ROOT precedence over CLAUDE_PROJECT_DIR ---------
echo ""
echo "=== Case 8: \$ZSKILLS_PATHS_ROOT set, \$CLAUDE_PROJECT_DIR unset → uses ZSKILLS_PATHS_ROOT ==="
T8=$(mktemp -d /tmp/zskills-paths-t8-XXXXXX)
mkdir -p "$T8/.claude"
cat > "$T8/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "plans_dir": "alt-plans"
  }
}
CFG
C8_PLANS=$(
  ( unset CLAUDE_PROJECT_DIR
    HOME="$EMPTY_HOME" ZSKILLS_PATHS_ROOT="$T8" \
      bash -c 'unset CLAUDE_PROJECT_DIR; ZSKILLS_PATHS_ROOT="'"$T8"'" . "'"$HELPER"'" && printf "%s" "$ZSKILLS_PLANS_DIR"'
  )
)
[ "$C8_PLANS" = "$T8/alt-plans" ] \
  && pass "Case 8: ZSKILLS_PATHS_ROOT used when CLAUDE_PROJECT_DIR unset" \
  || fail "Case 8: ZSKILLS_PATHS_ROOT precedence" "got '$C8_PLANS', expected '$T8/alt-plans'"
rm -rf "$T8"

# --- Case 9: vars NOT exported by helper itself ----------------------------
echo ""
echo "=== Case 9: after source, env | grep '^ZSKILLS_PLANS_DIR=' is empty ==="
T9=$(mktemp -d /tmp/zskills-paths-t9-XXXXXX)
mkdir -p "$T9/.claude"
cat > "$T9/.claude/zskills-config.json" <<'CFG'
{ "output": { "plans_dir": "docs/plans" } }
CFG
# Source the helper; spawn a subprocess (env). Since helper does not export,
# the child's env should NOT contain ZSKILLS_PLANS_DIR.
ENV_HIT=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T9" \
  bash -c '. "'"$HELPER"'"; env | grep "^ZSKILLS_PLANS_DIR=" || true'
)
if [ -z "$ENV_HIT" ]; then
  pass "Case 9: \$ZSKILLS_PLANS_DIR is NOT exported by helper itself"
else
  fail "Case 9: vars not exported" "child env saw: '$ENV_HIT'"
fi
rm -rf "$T9"

# --- Case 10a: config file absent → reports_dir built-in default -----------
# Phase 5 RE-SPEC (intended assertion change): OLD legacy back-compat was
# <root>/.zskills/audit; NEW built-in default is docs/reports (pinned to
# zskills-defaults.json). $ZSKILLS_AUDIT_DIR itself stays .zskills/audit.
echo ""
echo "=== Case 10a: config file absent → \$ZSKILLS_REPORTS_DIR = <root>/docs/reports ==="
T10A=$(mktemp -d /tmp/zskills-paths-t10a-XXXXXX)
# No config file at all.
C10A_REPORTS=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T10A" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_REPORTS_DIR"'
)
[ "$C10A_REPORTS" = "$T10A/docs/reports" ] \
  && pass "Case 10a: no config file → reports built-in default '<root>/docs/reports'" \
  || fail "Case 10a: no config fallback" "got '$C10A_REPORTS', expected '$T10A/docs/reports'"
rm -rf "$T10A"

# --- Case 10b: config present but reports_dir key absent → built-in default
echo ""
echo "=== Case 10b: config has plans_dir + issues_dir but NO reports_dir → docs/reports default ==="
T10B=$(mktemp -d /tmp/zskills-paths-t10b-XXXXXX)
mkdir -p "$T10B/.claude"
cat > "$T10B/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "plans_dir": "docs/plans",
    "issues_dir": "docs/issues"
  }
}
CFG
C10B_REPORTS=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T10B" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_REPORTS_DIR"'
)
# Phase 5 re-spec: key absent at both tiers → built-in default docs/reports.
[ "$C10B_REPORTS" = "$T10B/docs/reports" ] \
  && pass "Case 10b: reports_dir absent → built-in default '<root>/docs/reports'" \
  || fail "Case 10b: reports_dir default" "got '$C10B_REPORTS', expected '$T10B/docs/reports'"
rm -rf "$T10B"

# --- Case 11: reports_dir relative → joined with root ----------------------
echo ""
echo "=== Case 11: output.reports_dir = 'build/audit' → \$ZSKILLS_REPORTS_DIR = <root>/build/audit ==="
T11=$(mktemp -d /tmp/zskills-paths-t11-XXXXXX)
mkdir -p "$T11/.claude"
cat > "$T11/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "plans_dir": "docs/plans",
    "issues_dir": "docs/issues",
    "reports_dir": "build/audit"
  }
}
CFG
C11_REPORTS=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T11" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_REPORTS_DIR"'
)
[ "$C11_REPORTS" = "$T11/build/audit" ] \
  && pass "Case 11: relative reports_dir joined with <root>" \
  || fail "Case 11: relative reports_dir" "got '$C11_REPORTS', expected '$T11/build/audit'"
rm -rf "$T11"

# --- Case 12: reports_dir absolute → used as-is ----------------------------
echo ""
echo "=== Case 12: output.reports_dir = '/abs/path/reports' → used as-is (absolute) ==="
T12=$(mktemp -d /tmp/zskills-paths-t12-XXXXXX)
mkdir -p "$T12/.claude"
cat > "$T12/.claude/zskills-config.json" <<'CFG'
{
  "output": {
    "reports_dir": "/abs/path/reports"
  }
}
CFG
C12_REPORTS=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T12" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_REPORTS_DIR"'
)
[ "$C12_REPORTS" = "/abs/path/reports" ] \
  && pass "Case 12: absolute reports_dir used as-is" \
  || fail "Case 12: absolute reports_dir" "got '$C12_REPORTS', expected '/abs/path/reports'"
rm -rf "$T12"

# --- Case 13: malformed JSON (no closing brace) → silent fallback ----------
echo ""
echo "=== Case 13: malformed truncated reports_dir JSON → docs/reports default ==="
T13=$(mktemp -d /tmp/zskills-paths-t13-XXXXXX)
mkdir -p "$T13/.claude"
# Inner object never closes (no `}` after the value) — regex closing-brace
# anchor refuses the match; fallback path used.
printf '%s' '{"output":{"reports_dir":"DROP"' > "$T13/.claude/zskills-config.json"
RESULT13=$(
  HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$T13" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_REPORTS_DIR"' 2>&1
)
RC13=$?
C13_REPORTS=$(printf '%s\n' "$RESULT13" | sed -n '1p')
# Phase 5 re-spec: malformed → built-in default docs/reports.
if [ "$RC13" -eq 0 ] && [ "$C13_REPORTS" = "$T13/docs/reports" ]; then
  pass "Case 13: malformed reports_dir JSON → rc=0 + docs/reports default"
else
  fail "Case 13: malformed reports_dir" "rc=$RC13 reports='$C13_REPORTS' (expected '$T13/docs/reports')"
fi
rm -rf "$T13"

# --- Case 14: source mirror parity check ----------------------------------
echo ""
echo "=== Case 14: helper present at .claude/skills/ mirror, byte-identical to source ==="
if [ -f "$MIRROR_HELPER" ]; then
  pass "Case 14a: mirror helper exists at .claude/skills/update-zskills/scripts/zskills-paths.sh"
else
  fail "Case 14a: mirror helper exists" "$MIRROR_HELPER missing"
fi
if diff -q "$HELPER" "$MIRROR_HELPER" >/dev/null 2>&1; then
  pass "Case 14b: source and mirror byte-identical"
else
  fail "Case 14b: source/mirror byte-identical" "diff returned non-zero"
fi

# --- Case 15: user tier alone supplies output.* (Phase 5 cascade) ----------
echo ""
echo "=== Case 15: HOME-sandboxed user tier — user config alone supplies output.* ==="
T15=$(mktemp -d /tmp/zskills-paths-t15-XXXXXX)
U15=$(mktemp -d /tmp/zskills-paths-u15-XXXXXX)
mkdir -p "$U15/.claude"
cat > "$U15/.claude/zskills-config.json" <<'UCFG'
{
  "output": {
    "plans_dir": "user-plans",
    "issues_dir": "user-issues",
    "reports_dir": "user-reports"
  }
}
UCFG
# No project config at all.
RESULT15=$(
  HOME="$U15" CLAUDE_PROJECT_DIR="$T15" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR" "$ZSKILLS_REPORTS_DIR"'
)
C15_PLANS=$(printf '%s\n' "$RESULT15" | sed -n '1p')
C15_ISSUES=$(printf '%s\n' "$RESULT15" | sed -n '2p')
C15_REPORTS=$(printf '%s\n' "$RESULT15" | sed -n '3p')
if [ "$C15_PLANS" = "$T15/user-plans" ] && [ "$C15_ISSUES" = "$T15/user-issues" ] \
  && [ "$C15_REPORTS" = "$T15/user-reports" ]; then
  pass "Case 15: user-tier output.* effective (joined with PROJECT root, not \$HOME)"
else
  fail "Case 15: user-tier output.*" "plans='$C15_PLANS' issues='$C15_ISSUES' reports='$C15_REPORTS'"
fi
rm -rf "$T15" "$U15"

# --- Case 16: precedence — project match wins; user fills absent keys ------
echo ""
echo "=== Case 16: precedence — project>user per key; user fills project-absent keys ==="
T16=$(mktemp -d /tmp/zskills-paths-t16-XXXXXX)
U16=$(mktemp -d /tmp/zskills-paths-u16-XXXXXX)
mkdir -p "$T16/.claude" "$U16/.claude"
cat > "$U16/.claude/zskills-config.json" <<'UCFG'
{
  "output": {
    "plans_dir": "user-plans",
    "issues_dir": "user-issues"
  }
}
UCFG
cat > "$T16/.claude/zskills-config.json" <<'PCFG'
{
  "output": {
    "plans_dir": "proj-plans"
  }
}
PCFG
RESULT16=$(
  HOME="$U16" CLAUDE_PROJECT_DIR="$T16" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR" "$ZSKILLS_REPORTS_DIR"'
)
C16_PLANS=$(printf '%s\n' "$RESULT16" | sed -n '1p')
C16_ISSUES=$(printf '%s\n' "$RESULT16" | sed -n '2p')
C16_REPORTS=$(printf '%s\n' "$RESULT16" | sed -n '3p')
[ "$C16_PLANS" = "$T16/proj-plans" ] \
  && pass "Case 16a: \$ZSKILLS_PLANS_DIR = '<root>/proj-plans' (project wins over user)" \
  || fail "Case 16a: project precedence" "got '$C16_PLANS', expected '$T16/proj-plans'"
[ "$C16_ISSUES" = "$T16/user-issues" ] \
  && pass "Case 16b: \$ZSKILLS_ISSUES_DIR = '<root>/user-issues' (user fills project-absent key)" \
  || fail "Case 16b: user fills absent key" "got '$C16_ISSUES', expected '$T16/user-issues'"
[ "$C16_REPORTS" = "$T16/docs/reports" ] \
  && pass "Case 16c: \$ZSKILLS_REPORTS_DIR = built-in default (absent at both tiers)" \
  || fail "Case 16c: default fills both-absent key" "got '$C16_REPORTS', expected '$T16/docs/reports'"
rm -rf "$T16" "$U16"

# --- Case 17: malformed USER file → ignored (fail-open) --------------------
echo ""
echo "=== Case 17: malformed user config — ignored; project + defaults result ==="
T17=$(mktemp -d /tmp/zskills-paths-t17-XXXXXX)
U17=$(mktemp -d /tmp/zskills-paths-u17-XXXXXX)
mkdir -p "$T17/.claude" "$U17/.claude"
printf '%s' '{"output":{"plans_dir":"USERDROP"' > "$U17/.claude/zskills-config.json"
cat > "$T17/.claude/zskills-config.json" <<'PCFG'
{ "output": { "plans_dir": "proj-plans" } }
PCFG
RESULT17=$(
  HOME="$U17" CLAUDE_PROJECT_DIR="$T17" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR"' 2>&1
)
RC17=$?
C17_PLANS=$(printf '%s\n' "$RESULT17" | sed -n '1p')
C17_ISSUES=$(printf '%s\n' "$RESULT17" | sed -n '2p')
if [ "$RC17" -eq 0 ] && [ "$C17_PLANS" = "$T17/proj-plans" ] \
  && [ "$C17_ISSUES" = "$T17/docs/issues" ]; then
  pass "Case 17: malformed user file ignored → project value + built-in default (rc=0)"
else
  fail "Case 17: malformed-user fallback" "rc=$RC17 plans='$C17_PLANS' issues='$C17_ISSUES'"
fi
rm -rf "$T17" "$U17"

rm -rf "$EMPTY_HOME"

# --- Summary ---------------------------------------------------------------
echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
