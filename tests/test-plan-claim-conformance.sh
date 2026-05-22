#!/bin/bash
# tests/test-plan-claim-conformance.sh — Phase 4 W4.1.
#
# Conformance battery for plans/plans-claim-chip-parity.md. Section-
# header-anchored grep asserts on skills/run-plan/SKILL.md +
# skills/work-on-plans/SKILL.md that lock the plan-claim mechanism's
# location-pinned invariants (DA2.6, DA2.10, DA3.1).
#
# Assertions:
#   A. Acquire call precedes the first `### Execution` mode header (A11).
#   B. Each of 6 section-scoped windows contains exactly one
#      `claim-plan.sh refresh` call (Parse plan, Post-implementation
#      tracking, Post-verification tracking, 5. Marker ordering and
#      failure handling, Post-report tracking, 0b. Final-verify gate).
#   C. Each of 3 section-scoped windows contains exactly one
#      `claim-plan.sh release` call (Stop, 0a. Idempotent early-exit,
#      Post-landing tracking).
#   D. NEGATIVE: zero `claim-plan.sh release` calls within Phase 5b §1-5
#      (between `### 1. Audit phase compliance` and the next
#      `### Post-report tracking` / `## Phase 5c`).
#   E. NEGATIVE: zero hits for the literal `LAND_OUTCOME` anywhere
#      (DA2.4 — that variable is /land-pr-internal).
#   F. work-on-plans Step 4 has `claim-plan.sh sweep` BEFORE
#      `filter-in-flight-plan-claims.sh` (line-number ordering).
#   G. `.claude/settings.json` registers `block-run-plan-unclaimed.sh`
#      as a PreToolUse / Bash hook.
#   H. Adjacency to Issue #604: `claim-plan.sh` writes only to
#      `.zskills/claims/`, never to `.zskills/tracking/` (release path
#      separation).
#
# Multi-line bash continuations (`\`-newline + spaces between
# `claim-plan.sh` and the action verb) are joined before counting per
# DA3.1 implementation note: the W4.1 spec asks for the literal
# `claim-plan.sh refresh` / `release` substring; in the source files
# the verb sits on the continuation line, so the test joins backslash-
# continuations first, then counts on the joined-form text. This
# preserves the spec's intent (one call site per window) while matching
# the file's actual shape.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RP_SKILL="$REPO_ROOT/skills/run-plan/SKILL.md"
WOP_SKILL="$REPO_ROOT/skills/work-on-plans/SKILL.md"
SETTINGS="$REPO_ROOT/.claude/settings.json"
CLAIM_SH="$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

echo "=== run-plan claim mechanism conformance ==="

# ───────────────────────────────────────────────────────────────────────
# Helper: extract a section by header-bracketed window (awk), then join
# bash `\`-continuations so `claim-plan.sh<continuation>action` collapses
# to a single line, then count matches of the action verb literal.
# ───────────────────────────────────────────────────────────────────────
count_in_section() {
  # $1 awk-program (sets p=1 after header, p=0 at next header)
  # $2 file
  # $3 action verb (refresh|release|acquire)
  local awkprog="$1" file="$2" verb="$3"
  awk "$awkprog" "$file" \
    | sed ':a;N;$!ba;s/\\\n[[:space:]]*/ /g' \
    | grep -cE "claim-plan\\.sh\"[[:space:]]+${verb}"
}

# ───────────────────────────────────────────────────────────────────────
# A. Acquire precedes the first `### Execution` header (A11).
# ───────────────────────────────────────────────────────────────────────
acq_line=$(awk '
BEGIN{buf=""; ln=0}
{
  if (buf == "") {ln = NR}
  if (substr($0, length($0)) == "\\") {
    buf = buf substr($0, 1, length($0)-1)
  } else {
    print ln":"buf $0
    buf = ""
  }
}
' "$RP_SKILL" \
  | grep -E 'claim-plan\.sh"[[:space:]]+acquire' \
  | head -1 \
  | cut -d: -f1)
exec_line=$(grep -nE '^### Execution' "$RP_SKILL" | head -1 | cut -d: -f1)
if [ -n "$acq_line" ] && [ -n "$exec_line" ] && [ "$acq_line" -lt "$exec_line" ]; then
  pass "acquire-before-Execution: claim-plan.sh acquire at line $acq_line precedes first ### Execution at $exec_line (A11)"
else
  fail "acquire-before-Execution (A11)" "acq_line=$acq_line exec_line=$exec_line — acquire must precede ### Execution mode header"
fi

# ───────────────────────────────────────────────────────────────────────
# B. Six section-scoped refresh windows — each must contain exactly 1
#    claim-plan.sh refresh call.
# ───────────────────────────────────────────────────────────────────────
declare -A REFRESH_SECTIONS=(
  ["Parse plan"]='/^### Parse plan$/{p=1; next} p && /^(###|## )/{p=0} p'
  ["Post-implementation tracking"]='/^### Post-implementation tracking$/{p=1; next} p && /^(###|## )/{p=0} p'
  ["Post-verification tracking"]='/^### Post-verification tracking$/{p=1; next} p && /^(###|## )/{p=0} p'
  ["5. Marker ordering and failure handling"]='/^### 5\. Marker ordering and failure handling$/{p=1; next} p && /^(###|## )/{p=0} p'
  ["Post-report tracking"]='/^### Post-report tracking$/{p=1; next} p && /^(###|## )/{p=0} p'
  ["0b. Final-verify gate"]='/^### 0b\. Final-verify gate$/{p=1; next} p && /^(###|## )/{p=0} p'
)

# Iterate in stable order for legible output.
REFRESH_ORDER=(
  "Parse plan"
  "Post-implementation tracking"
  "Post-verification tracking"
  "5. Marker ordering and failure handling"
  "Post-report tracking"
  "0b. Final-verify gate"
)
for sec in "${REFRESH_ORDER[@]}"; do
  prog="${REFRESH_SECTIONS[$sec]}"
  n=$(count_in_section "$prog" "$RP_SKILL" "refresh")
  if [ "$n" = "1" ]; then
    pass "refresh window '$sec' — exactly 1 claim-plan.sh refresh call (DA2.6 / DA3.1)"
  else
    fail "refresh window '$sec'" "expected 1, got $n"
  fi
done

# ───────────────────────────────────────────────────────────────────────
# C. Three release windows — each must contain exactly 1 release call.
# ───────────────────────────────────────────────────────────────────────
declare -A RELEASE_SECTIONS=(
  ["Stop"]='/^## Stop/{p=1; next} p && /^## /{p=0} p'
  ["0a. Idempotent early-exit"]='/^### 0a\. Idempotent early-exit$/{p=1; next} p && /^(###|## )/{p=0} p'
  ["Post-landing tracking"]='/^### Post-landing tracking$/{p=1; next} p && /^(###|## )/{p=0} p'
)
RELEASE_ORDER=(
  "Stop"
  "0a. Idempotent early-exit"
  "Post-landing tracking"
)
for sec in "${RELEASE_ORDER[@]}"; do
  prog="${RELEASE_SECTIONS[$sec]}"
  n=$(count_in_section "$prog" "$RP_SKILL" "release")
  if [ "$n" = "1" ]; then
    pass "release window '$sec' — exactly 1 claim-plan.sh release call (DA2.10 / DA3.1)"
  else
    fail "release window '$sec'" "expected 1, got $n"
  fi
done

# ───────────────────────────────────────────────────────────────────────
# D. NEGATIVE: no release call within Phase 5b §1-5 (the unclaimed-
# during-CI-poll regression window).
# ───────────────────────────────────────────────────────────────────────
neg_prog='/^### 1\. Audit phase compliance$/{p=1; next} p && /^### Post-report tracking|^## Phase 5c/{p=0} p'
neg_n=$(count_in_section "$neg_prog" "$RP_SKILL" "release")
if [ "$neg_n" = "0" ]; then
  pass "NEGATIVE: zero release calls within Phase 5b §1-5 (regression check, DA3.1)"
else
  fail "NEGATIVE Phase 5b §1-5 release-free" "expected 0, got $neg_n — release inside §1-5 reintroduces the unclaimed-during-CI-poll bug"
fi

# ───────────────────────────────────────────────────────────────────────
# E. NEGATIVE: zero hits for `LAND_OUTCOME` anywhere in run-plan SKILL.md
# (DA2.4 — that variable is /land-pr-internal; anchoring on it leaks
# /land-pr's contract into /run-plan).
# ───────────────────────────────────────────────────────────────────────
lo_n=$(grep -c 'LAND_OUTCOME' "$RP_SKILL")
if [ "$lo_n" = "0" ]; then
  pass "NEGATIVE: zero hits for LAND_OUTCOME in run-plan/SKILL.md (DA2.4)"
else
  fail "NEGATIVE LAND_OUTCOME absent" "expected 0 hits, got $lo_n — Phase 6 release must anchor on /run-plan's own marker, not /land-pr-internal LAND_OUTCOME"
fi

# ───────────────────────────────────────────────────────────────────────
# F. work-on-plans Step 4: sweep precedes filter (line-number ordering).
# ───────────────────────────────────────────────────────────────────────
sweep_line=$(grep -nE 'claim-plan\.sh.*sweep|"\$SWEEP"[[:space:]]+sweep' "$WOP_SKILL" | head -1 | cut -d: -f1)
filter_line=$(grep -nE 'filter-in-flight-plan-claims\.sh' "$WOP_SKILL" | head -1 | cut -d: -f1)
if [ -n "$sweep_line" ] && [ -n "$filter_line" ] && [ "$sweep_line" -lt "$filter_line" ]; then
  pass "work-on-plans Step 4: sweep at line $sweep_line precedes filter at line $filter_line (R2.6)"
else
  fail "work-on-plans sweep-before-filter (R2.6)" "sweep_line=$sweep_line filter_line=$filter_line — sweep must precede filter in Step 4"
fi

# ───────────────────────────────────────────────────────────────────────
# G. .claude/settings.json registers block-run-plan-unclaimed.sh on
# PreToolUse / Bash matcher.
# ───────────────────────────────────────────────────────────────────────
PYTHON=${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}
if [ -z "$PYTHON" ]; then
  fail "settings.json hook registration" "no Python interpreter available"
else
  reg_ok=$("$PYTHON" -c "
import json, sys
try:
    cfg = json.load(open('$SETTINGS'))
except Exception as e:
    print('PARSE_FAIL:' + str(e))
    sys.exit(0)
pre = cfg.get('hooks', {}).get('PreToolUse', [])
for entry in pre:
    if entry.get('matcher') != 'Bash':
        continue
    for h in entry.get('hooks', []):
        cmd = h.get('command', '')
        if 'block-run-plan-unclaimed.sh' in cmd:
            print('OK')
            sys.exit(0)
print('NOT_FOUND')
")
  case "$reg_ok" in
    OK) pass ".claude/settings.json registers block-run-plan-unclaimed.sh on PreToolUse/Bash" ;;
    *)  fail "settings.json hook registration" "result: $reg_ok" ;;
  esac
fi

# ───────────────────────────────────────────────────────────────────────
# H. Issue #604 adjacency: claim-plan.sh does NOT write release paths
# under .zskills/tracking/. All claim paths must be .zskills/claims/.
# Doc-comment hits are tolerated; path-construction hits are not.
# ───────────────────────────────────────────────────────────────────────
if [ ! -f "$CLAIM_SH" ]; then
  fail "claim-plan.sh path separation" "$CLAIM_SH missing"
else
  # Grep for any /tracking/ reference in path-construction position (i.e.
  # not in a doc comment that starts the line with `#`). We use a
  # strict literal-match here: any non-comment line that mentions
  # .zskills/tracking/ is a violation.
  tracking_hits=$(grep -nE '\.zskills/tracking/' "$CLAIM_SH" | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*#' || true)
  if [ -z "$tracking_hits" ]; then
    pass "claim-plan.sh: zero .zskills/tracking/ references in path-construction position (Issue #604 adjacency, W4.3)"
  else
    fail "claim-plan.sh path separation (Issue #604)" "release path leaks into .zskills/tracking/: $tracking_hits"
  fi
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
