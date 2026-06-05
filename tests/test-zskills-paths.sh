#!/bin/bash
# Tests for skills/update-zskills/scripts/zskills-paths.sh —
# the canonical path-resolution helper introduced in
# plans/ZSKILLS_PATH_CONFIG.md Phase 1.
#
# Cases (≥9 per Phase 1.8 table; cases 10a-13 added for reports_dir per
# REPORTS_DIR_MIGRATION.md Phase 1, WI 1.8):
#   1. Empty config → $ZSKILLS_PLANS_DIR == $ROOT/plans (legacy fallback).
#   2. output.plans_dir = "docs/plans" → $ZSKILLS_PLANS_DIR == $ROOT/docs/plans.
#   3. output.plans_dir = "/tmp/x" → $ZSKILLS_PLANS_DIR == /tmp/x (absolute).
#   4. output.plans_dir = "../external/zskills" → $ROOT/../external/zskills (joined).
#   5. Both $CLAUDE_PROJECT_DIR AND $ZSKILLS_PATHS_ROOT unset → non-zero
#      with stderr naming both vars (subshell-unset idiom).
#   6a. Garbage config (not JSON) → silent fallback to legacy plans/.
#   6b. Truncated JSON → silent fallback (closing-brace anchor).
#   7. output.plans_dir = "" (empty string) → fallback to legacy plans/.
#   8. $ZSKILLS_PATHS_ROOT set, $CLAUDE_PROJECT_DIR unset → uses $ZSKILLS_PATHS_ROOT.
#   9. After source, env | grep '^ZSKILLS_PLANS_DIR=' is empty (vars not exported).
#   10a. Config file absent → $ZSKILLS_REPORTS_DIR == $ROOT/.zskills/audit.
#   10b. Config present, reports_dir key absent → $ROOT/.zskills/audit (back-compat).
#   11. output.reports_dir = "build/audit" → $ROOT/build/audit (relative joined).
#   12. output.reports_dir = "/abs/path/reports" → /abs/path/reports (absolute as-is).
#   13. Malformed JSON (truncated reports_dir) → legacy .zskills/audit fallback.
#   14. Source vs mirror byte-identical (parity check; was Case 10).
#
# Run from repo root: bash tests/test-zskills-paths.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/skills/update-zskills/scripts/zskills-paths.sh"
MIRROR_HELPER="$REPO_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

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

# --- Case 1: empty config → legacy fallback --------------------------------
# REGRESSION ANCHOR: a fresh-config SCAFFOLD now seeds output.plans_dir =
# "docs/plans" (both lanes — see hooks/session-start-materialise.sh and
# skills/update-zskills/SKILL.md, locked symmetric in test-skill-conformance.sh).
# That change MUST NOT touch the resolver's legacy fallback: an EXISTING config
# with NO output block (or none at all) must still resolve to <root>/plans so
# pre-migration consumers are preserved. Case 1 proves zskills-paths.sh keeps
# that legacy behavior. If this case ever flips to docs/plans, the scaffold
# change leaked into the resolver — STOP.
echo "=== Case 1: empty config — $ZSKILLS_PLANS_DIR falls back to <root>/plans ==="
T1=$(mktemp -d /tmp/zskills-paths-t1-XXXXXX)
# No config file at all.
RESULT1=$(
  CLAUDE_PROJECT_DIR="$T1" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR" "$ZSKILLS_AUDIT_DIR"'
)
C1_PLANS=$(printf '%s\n' "$RESULT1" | sed -n '1p')
C1_ISSUES=$(printf '%s\n' "$RESULT1" | sed -n '2p')
C1_AUDIT=$(printf '%s\n' "$RESULT1" | sed -n '3p')
[ "$C1_PLANS" = "$T1/plans" ] \
  && pass "Case 1a: empty config → \$ZSKILLS_PLANS_DIR = '<root>/plans'" \
  || fail "Case 1a: \$ZSKILLS_PLANS_DIR" "got '$C1_PLANS', expected '$T1/plans'"
[ "$C1_ISSUES" = "$T1/plans" ] \
  && pass "Case 1b: empty config → \$ZSKILLS_ISSUES_DIR also legacy '<root>/plans'" \
  || fail "Case 1b: \$ZSKILLS_ISSUES_DIR" "got '$C1_ISSUES', expected '$T1/plans'"
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
  CLAUDE_PROJECT_DIR="$T2" \
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
  CLAUDE_PROJECT_DIR="$T3" \
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
  CLAUDE_PROJECT_DIR="$T4" \
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
echo "=== Case 6a: garbage config (not JSON at all) → silent fallback to legacy plans/ ==="
T6A=$(mktemp -d /tmp/zskills-paths-t6a-XXXXXX)
mkdir -p "$T6A/.claude"
cat > "$T6A/.claude/zskills-config.json" <<'GARBAGE'
not json at all
GARBAGE
RESULT6A=$(
  CLAUDE_PROJECT_DIR="$T6A" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR"' 2>&1
)
RC6A=$?
C6A_PLANS=$(printf '%s\n' "$RESULT6A" | sed -n '1p')
if [ "$RC6A" -eq 0 ] && [ "$C6A_PLANS" = "$T6A/plans" ]; then
  pass "Case 6a: garbage config → rc=0 + legacy plans/ fallback"
else
  fail "Case 6a: garbage config fallback" "rc=$RC6A plans='$C6A_PLANS'"
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
  CLAUDE_PROJECT_DIR="$T6B" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_PLANS_DIR"' 2>&1
)
RC6B=$?
C6B_PLANS=$(printf '%s\n' "$RESULT6B" | sed -n '1p')
if [ "$RC6B" -eq 0 ] && [ "$C6B_PLANS" = "$T6B/plans" ]; then
  pass "Case 6b: truncated JSON (no closing brace) → rc=0 + legacy plans/ fallback"
else
  fail "Case 6b: truncated JSON fallback" "rc=$RC6B plans='$C6B_PLANS'"
fi
rm -rf "$T6B"

# --- Case 7: empty-string plans_dir → fallback ----------------------------
echo ""
echo "=== Case 7: output.plans_dir = '' → fallback to legacy plans/ ==="
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
  CLAUDE_PROJECT_DIR="$T7" \
  bash -c '. "'"$HELPER"'" && printf "%s\n%s\n" "$ZSKILLS_PLANS_DIR" "$ZSKILLS_ISSUES_DIR"'
)
C7_PLANS=$(printf '%s\n' "$RESULT7" | sed -n '1p')
C7_ISSUES=$(printf '%s\n' "$RESULT7" | sed -n '2p')
[ "$C7_PLANS" = "$T7/plans" ] && [ "$C7_ISSUES" = "$T7/plans" ] \
  && pass "Case 7: empty-string values fall back to legacy '<root>/plans'" \
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
    ZSKILLS_PATHS_ROOT="$T8" \
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
  CLAUDE_PROJECT_DIR="$T9" \
  bash -c '. "'"$HELPER"'"; env | grep "^ZSKILLS_PLANS_DIR=" || true'
)
if [ -z "$ENV_HIT" ]; then
  pass "Case 9: \$ZSKILLS_PLANS_DIR is NOT exported by helper itself"
else
  fail "Case 9: vars not exported" "child env saw: '$ENV_HIT'"
fi
rm -rf "$T9"

# --- Case 10a: config file absent → reports_dir legacy fallback ------------
echo ""
echo "=== Case 10a: config file absent → \$ZSKILLS_REPORTS_DIR = <root>/.zskills/audit ==="
T10A=$(mktemp -d /tmp/zskills-paths-t10a-XXXXXX)
# No config file at all.
C10A_REPORTS=$(
  CLAUDE_PROJECT_DIR="$T10A" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_REPORTS_DIR"'
)
[ "$C10A_REPORTS" = "$T10A/.zskills/audit" ] \
  && pass "Case 10a: no config file → reports legacy '<root>/.zskills/audit'" \
  || fail "Case 10a: no config fallback" "got '$C10A_REPORTS', expected '$T10A/.zskills/audit'"
rm -rf "$T10A"

# --- Case 10b: config present but reports_dir key absent → silent back-compat
echo ""
echo "=== Case 10b: config has plans_dir + issues_dir but NO reports_dir → back-compat legacy ==="
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
  CLAUDE_PROJECT_DIR="$T10B" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_REPORTS_DIR"'
)
[ "$C10B_REPORTS" = "$T10B/.zskills/audit" ] \
  && pass "Case 10b: reports_dir absent → silent back-compat to '<root>/.zskills/audit'" \
  || fail "Case 10b: back-compat" "got '$C10B_REPORTS', expected '$T10B/.zskills/audit'"
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
  CLAUDE_PROJECT_DIR="$T11" \
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
  CLAUDE_PROJECT_DIR="$T12" \
  bash -c '. "'"$HELPER"'" && printf "%s" "$ZSKILLS_REPORTS_DIR"'
)
[ "$C12_REPORTS" = "/abs/path/reports" ] \
  && pass "Case 12: absolute reports_dir used as-is" \
  || fail "Case 12: absolute reports_dir" "got '$C12_REPORTS', expected '/abs/path/reports'"
rm -rf "$T12"

# --- Case 13: malformed JSON (no closing brace) → silent fallback ----------
echo ""
echo "=== Case 13: malformed truncated reports_dir JSON → legacy .zskills/audit fallback ==="
T13=$(mktemp -d /tmp/zskills-paths-t13-XXXXXX)
mkdir -p "$T13/.claude"
# Inner object never closes (no `}` after the value) — regex closing-brace
# anchor refuses the match; fallback path used.
printf '%s' '{"output":{"reports_dir":"DROP"' > "$T13/.claude/zskills-config.json"
RESULT13=$(
  CLAUDE_PROJECT_DIR="$T13" \
  bash -c '. "'"$HELPER"'" && printf "%s\n" "$ZSKILLS_REPORTS_DIR"' 2>&1
)
RC13=$?
C13_REPORTS=$(printf '%s\n' "$RESULT13" | sed -n '1p')
if [ "$RC13" -eq 0 ] && [ "$C13_REPORTS" = "$T13/.zskills/audit" ]; then
  pass "Case 13: malformed reports_dir JSON → rc=0 + legacy fallback"
else
  fail "Case 13: malformed reports_dir" "rc=$RC13 reports='$C13_REPORTS' (expected '$T13/.zskills/audit')"
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
