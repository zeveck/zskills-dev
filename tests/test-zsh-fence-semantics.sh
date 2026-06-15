#!/bin/bash
# tests/test-zsh-fence-semantics.sh — durable cross-shell semantics probe
# suite for the zsh fence-portability plan (ZSH_FENCE_WRAP_PLAN, #1155).
#
# WHY THIS SUITE EXISTS
# ---------------------
# On stock macOS, Claude Code snapshots the user's login shell (zsh 5.9) and
# skill-file bash fences execute under zsh, not bash. The plan's three-track
# remediation (Track W wrap, Track G setopt guard v2, Track R rewrites) plus
# the declare -A subscript normalization each rest on a claim that a specific
# idiom behaves byte-IDENTICALLY under bash and zsh. This suite is the
# committed, durable proof of every one of those claims: each section runs the
# EXACT idiom the plan ships under BOTH shells and diffs the output. A
# divergence here means the plan's assumptions are wrong for the running
# zsh/platform — STOP and surface (Phase-1 contract).
#
# It also pins the two RECORDED-DIVERGENCE expectations (so they cannot
# silently flip): (s3) the AS-WRITTEN mixed-quoted associative-array pattern
# MUST diverge (this is the declare -A misroute that motivates Branch B), and
# (s11/s12) the two accepted residuals (zsh special-parameter rejection,
# glob-in-var divergence under the v2 guard) are pinned so a future "the guard
# is full bash parity" assumption is impossible.
#
# DECISION RULE (declare -A, consumed by Phase 1 WI 1.2):
#   - s3 IDENTICAL                          → Branch A (accept as-written)
#   - s3 DIVERGES and s4 IDENTICAL (expected)→ Branch B (subscript normalize)
#   - s4 DIVERGES                            → Branch C + STOP-and-surface
#
# zsh-ABSENCE BEHAVIOR:
#   - zsh missing AND ${CI:-} non-empty → FAIL (CI must run this suite; the
#     "Install zsh" step in .github/workflows/test.yml, WI 1.6, provides it).
#   - zsh missing AND ${CI:-} empty (local dev) → one WARN line, exit 0.
#
# Run from repo root: bash tests/test-zsh-fence-semantics.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"
WORK="$(mktemp -d "$TEST_OUT/.zsh-sem-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

summary_and_exit() {
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
}

# ── zsh gate ─────────────────────────────────────────────────────────────
if ! command -v zsh >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    printf '\033[31m  FAIL\033[0m %s\n' \
      "zsh required in CI — the 'Install zsh' step in .github/workflows/test.yml (WI 1.6) should have provided it; run \`sudo apt-get install -y zsh\`"
    echo ""
    echo "---"
    printf '\033[31mResults: 0 passed, 1 failed (of 1)\033[0m\n'
    exit 1
  fi
  echo "WARN: SKIP (zsh not installed — semantics suite not exercised)"
  exit 0
fi

ZSH_VER="$(zsh -c 'echo $ZSH_VERSION' 2>/dev/null)"
echo "zsh version: ${ZSH_VER:-unknown}"
echo ""

# run_under <shell> <snippet-file> → stdout (stderr captured to .err sibling)
run_under() {
  local shell="$1" snippet="$2"
  "$shell" "$snippet" 2>"$snippet.$shell.err"
}

# probe_identical <section-label> <snippet-file>
# Runs the snippet under bash AND zsh, asserts byte-identical stdout.
probe_identical() {
  local label="$1" snippet="$2"
  local out_bash out_zsh
  out_bash="$(run_under bash "$snippet")"
  out_zsh="$(run_under zsh "$snippet")"
  if [ "$out_bash" = "$out_zsh" ]; then
    pass "$label — byte-identical bash/zsh"
  else
    fail "$label — bash/zsh DIVERGE" \
      "bash=$(printf '%q' "$out_bash") zsh=$(printf '%q' "$out_zsh")"
  fi
}

# probe_diverges <section-label> <snippet-file>
# Asserts the snippet's stdout DIFFERS between bash and zsh (recorded-
# divergence expectation — flipping to identical is itself a regression we
# want to know about).
probe_diverges() {
  local label="$1" snippet="$2"
  local out_bash out_zsh
  out_bash="$(run_under bash "$snippet")"
  out_zsh="$(run_under zsh "$snippet")"
  if [ "$out_bash" != "$out_zsh" ]; then
    pass "$label — RECORDED divergence holds (bash=$(printf '%q' "$out_bash") zsh=$(printf '%q' "$out_zsh"))"
  else
    fail "$label — expected divergence but bash==zsh" \
      "both produced $(printf '%q' "$out_bash") — the recorded expectation flipped; STOP and surface"
  fi
}

# ─────────────────────────────────────────────────────────────────────────
# s1 — Track G v2 guard + [[ =~ ]] / ${BASH_REMATCH[n]} + 0-based indexing
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s1.sh" <<'PROBE'
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
s="issue-1155: branch=feat/x"
if [[ "$s" =~ issue-([0-9]+):\ branch=([A-Za-z/_-]+) ]]; then
  echo "num=${BASH_REMATCH[1]} branch=${BASH_REMATCH[2]}"
else
  echo "NO_MATCH"
fi
arr=(alpha beta gamma)
echo "idx0=${arr[0]} idx2=${arr[2]} count=${#arr[@]}"
PROBE
probe_identical "s1: v2 guard + BASH_REMATCH + 0-based index" "$WORK/s1.sh"

# ─────────────────────────────────────────────────────────────────────────
# s2 — word-split `for tok in $SCALAR` under the v2 guard (SH_WORD_SPLIT)
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s2.sh" <<'PROBE'
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
ARGUMENTS="10 auto pr"
n=0
for tok in $ARGUMENTS; do
  n=$((n + 1))
  echo "tok$n=$tok"
done
echo "total=$n"
PROBE
probe_identical "s2: word-split for-in-scalar under v2 guard" "$WORK/s2.sh"

# ─────────────────────────────────────────────────────────────────────────
# s3 — AS-WRITTEN mixed-quoted assoc pattern — EXPECTED TO DIVERGE.
#   Two spellings, both the caller-loop misroute class:
#     (a) quoted-VARIABLE key:  LP["$KEY"]= ... read ${LP[STATUS]}
#     (b) quoted-LITERAL  key:  LP["STATUS"]= ... read ${LP[STATUS]}
#   Under bash both read back the stored value; under zsh both read empty
#   (zsh stores the subscript text verbatim, including the quote chars).
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s3.sh" <<'PROBE'
declare -A LP
# (a) quoted-variable key — the mixed caller-loop shape
KEY="STATUS"; VALUE="success"
LP["$KEY"]="$VALUE"
echo "a=${LP[STATUS]:-EMPTY}"
# (b) quoted-literal key — same misroute (correction 6)
declare -A L3
L3["STATUS"]="ok"
echo "b=${L3[STATUS]:-EMPTY}"
PROBE
probe_diverges "s3: mixed-quoted assoc (var + literal) — recorded DIVERGE" "$WORK/s3.sh"

# ─────────────────────────────────────────────────────────────────────────
# s4 — NORMALIZED assoc pattern (Branch B) — EXPECTED IDENTICAL.
#   Consistent-UNQUOTED assign + read across all THREE key shapes:
#   variable, ${tok%%:*} parameter-expansion, fixed literal — plus a
#   KEY=VALUE case-allowlist loop and a membership-set dedupe.
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s4.sh" <<'PROBE'
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
declare -A LP
# variable key, unquoted
KEY="STATUS"; VALUE="success"
LP[$KEY]="$VALUE"
case "${LP[STATUS]:-}" in
  success) echo "case=ok" ;;
  *) echo "case=MISROUTE" ;;
esac
echo "var=${LP[STATUS]:-EMPTY}"
# parameter-expansion key, unquoted
declare -A SKIP_TAGGED_SET
tok="123:dup-of-456"
SKIP_TAGGED_SET[${tok%%:*}]="${tok#*:}"
echo "pe=${SKIP_TAGGED_SET[123]:-EMPTY}"
# fixed-literal key, unquoted
declare -A FIX
FIX[STATUS]="lit"
echo "lit=${FIX[STATUS]:-EMPTY}"
# membership-set dedupe (RESEARCHED_SET shape)
declare -A SEEN
added=0
for n in 7 7 8; do
  if [ -z "${SEEN[$n]:-}" ]; then SEEN[$n]=1; added=$((added + 1)); fi
done
echo "added=$added"
PROBE
probe_identical "s4: normalized assoc (var/expansion/literal + set dedupe)" "$WORK/s4.sh"

# ─────────────────────────────────────────────────────────────────────────
# s5 — R1 mapfile replacement (incl. UNTERMINATED final line capture)
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s5.sh" <<'PROBE'
# Track-R fences KEEP/GAIN the v2 guard for their remaining fixable
# constructs (incl. 0-based indexed array access) — the rewrite removes only
# the UNFIXABLE construct (mapfile), not the guard. So the realistic R1 fence
# carries the guard, and indexed readback is 0-based under both shells.
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
# producer with NO trailing newline on the last line
emit() { printf 'a\nb\nc'; }
ARR=()
while IFS= read -r _line || [ -n "$_line" ]; do ARR+=("$_line"); done < <(emit)
echo "count=${#ARR[@]} last=${ARR[$((${#ARR[@]} - 1))]}"
# herestring variant
STR=$'x\ny\nz'
ARR2=()
while IFS= read -r _line || [ -n "$_line" ]; do ARR2+=("$_line"); done <<< "$STR"
echo "count2=${#ARR2[@]} last2=${ARR2[$((${#ARR2[@]} - 1))]}"
PROBE
probe_identical "s5: R1 mapfile replacement (unterminated final line)" "$WORK/s5.sh"

# ─────────────────────────────────────────────────────────────────────────
# s6a — R2 split: OLD `read -r -a` vs NEW R2 idiom UNDER BASH on multi-line,
#       single-line, whitespace-run, and empty inputs. The head -n 1 is what
#       keeps old==new on multi-line input (read -a stops at first newline).
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s6a.sh" <<'PROBE'
# OLD construct under test
old_split() {
  local s="$1"; local OLD=()
  read -r -a OLD <<<"$s"
  printf '%s\n' "${#OLD[@]}"
  printf '[%s]' "${OLD[@]}"; printf '\n'
}
# NEW R2 idiom
new_split() {
  local s="$1"; local NEW=()
  while IFS= read -r _tok || [ -n "$_tok" ]; do
    [ -n "$_tok" ] && NEW+=("$_tok")
  done < <(printf '%s' "$s" | head -n 1 | tr ' \t' '\n\n')
  printf '%s\n' "${#NEW[@]}"
  printf '[%s]' "${NEW[@]}"; printf '\n'
}
for input in "$(printf '1 2\n3 4')" "alpha beta gamma" "  lead   trail  " ""; do
  echo "--input--"
  o="$(old_split "$input")"
  n="$(new_split "$input")"
  if [ "$o" = "$n" ]; then echo "MATCH"; else echo "MISMATCH old=$o new=$n"; fi
done
PROBE
# s6a is a BASH-only old-vs-new regression axis (not a cross-shell diff).
S6A_OUT="$(bash "$WORK/s6a.sh" 2>"$WORK/s6a.err")"
if printf '%s\n' "$S6A_OUT" | grep -q 'MISMATCH'; then
  fail "s6a: R2 old read -a vs new idiom under bash" "MISMATCH: $S6A_OUT"
elif [ "$(printf '%s\n' "$S6A_OUT" | grep -c '^MATCH$')" -eq 4 ]; then
  pass "s6a: R2 old read -a vs new idiom byte-identical under bash (4 inputs)"
else
  fail "s6a: R2 old-vs-new (expected 4 MATCH)" "$S6A_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────
# s6b — NEW R2 idiom bash-vs-zsh byte-identical (incl. final-token guard)
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s6b.sh" <<'PROBE'
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
STR="alpha beta gamma"
NEW=()
while IFS= read -r _tok || [ -n "$_tok" ]; do
  [ -n "$_tok" ] && NEW+=("$_tok")
done < <(printf '%s' "$STR" | head -n 1 | tr ' \t' '\n\n')
echo "count=${#NEW[@]} first=${NEW[0]} last=${NEW[$((${#NEW[@]} - 1))]}"
PROBE
probe_identical "s6b: R2 new idiom bash-vs-zsh" "$WORK/s6b.sh"

# ─────────────────────────────────────────────────────────────────────────
# s7 — R3 tr-based lowercase (replacing ${var,,})
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s7.sh" <<'PROBE'
PR_STATE="MERGED"
PR_PHRASE="PR $(printf '%s' "$PR_STATE" | tr '[:upper:]' '[:lower:]')"
echo "$PR_PHRASE"
PROBE
probe_identical "s7: R3 tr lowercase" "$WORK/s7.sh"

# ─────────────────────────────────────────────────────────────────────────
# s8 — R4 printenv indirection (replacing ${!var})
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s8.sh" <<'PROBE'
export _ZSKILLS_TEST_RUNPLAN_RESULT_MYSLUG="DONE: phase ok"
_perslug_var="_ZSKILLS_TEST_RUNPLAN_RESULT_MYSLUG"
_perslug_val=$(printenv "$_perslug_var" 2>/dev/null || true)
if [ -n "$_perslug_val" ]; then
  echo "got=$_perslug_val"
else
  echo "FALLBACK"
fi
# absent var → fallback path
_perslug_var2="_ZSKILLS_TEST_RUNPLAN_RESULT_ABSENT"
_perslug_val2=$(printenv "$_perslug_var2" 2>/dev/null || true)
[ -z "$_perslug_val2" ] && echo "absent-ok"
PROBE
probe_identical "s8: R4 printenv indirection" "$WORK/s8.sh"

# ─────────────────────────────────────────────────────────────────────────
# s9 — R5 find-based glob-existence (replacing compgen -G), hit + no-hit
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s9.sh" <<'PROBE'
D="$1"
mkdir -p "$D/present" "$D/empty"
: > "$D/present/cron-recovery-needed.42"
for dir in "$D/present" "$D/empty" "$D/nonexistent"; do
  if [ -n "$(find "$dir" -maxdepth 1 -name 'cron-recovery-needed.*' -print -quit 2>/dev/null)" ]; then
    echo "HIT $(basename "$dir")"
  else
    echo "MISS $(basename "$dir")"
  fi
done
PROBE
# s9 takes a per-shell sandbox arg so the two runs don't collide.
S9_BASH="$WORK/s9-bash-d"; S9_ZSH="$WORK/s9-zsh-d"
out_bash="$(bash "$WORK/s9.sh" "$S9_BASH" 2>"$WORK/s9.bash.err")"
out_zsh="$(zsh "$WORK/s9.sh" "$S9_ZSH" 2>"$WORK/s9.zsh.err")"
if [ "$out_bash" = "$out_zsh" ] && printf '%s\n' "$out_bash" | grep -qx 'HIT present' \
   && printf '%s\n' "$out_bash" | grep -qx 'MISS empty' \
   && printf '%s\n' "$out_bash" | grep -qx 'MISS nonexistent'; then
  pass "s9: R5 find-based glob-existence (hit + no-hit) byte-identical"
else
  fail "s9: R5 find-based glob-existence" "bash=$(printf '%q' "$out_bash") zsh=$(printf '%q' "$out_zsh")"
fi

# ─────────────────────────────────────────────────────────────────────────
# s10 — Track W wrap rc propagation + nested-heredoc tolerance.
#   The quoted-heredoc wrap's compound rc IS the child's rc; an inner
#   `exit 3` yields compound rc 3. Nested heredocs inside the body are
#   tolerated (the quoted outer delimiter suppresses parent expansion).
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s10.sh" <<'PROBE'
bash <<'ZSKILLS_BASH_FENCE'
cat <<'INNER'
nested-line-1
nested-line-2
INNER
echo "before-exit"
exit 3
echo "unreachable"
ZSKILLS_BASH_FENCE
echo "rc=$?"
PROBE
probe_identical "s10: wrap rc-propagation + nested heredoc" "$WORK/s10.sh"
# Additionally assert the recorded rc value (3) and that nested lines printed.
S10_OUT="$(bash "$WORK/s10.sh" 2>/dev/null)"
if printf '%s\n' "$S10_OUT" | grep -qx 'rc=3' \
   && printf '%s\n' "$S10_OUT" | grep -qx 'nested-line-1' \
   && printf '%s\n' "$S10_OUT" | grep -qx 'before-exit' \
   && ! printf '%s\n' "$S10_OUT" | grep -qx 'unreachable'; then
  pass "s10: wrap inner exit 3 → compound rc 3, nested heredoc body printed, post-exit unreachable"
else
  fail "s10: wrap rc/nested specifics" "$S10_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────
# s11 — zsh special-parameter canary. `LINES=()` (array assign to a zsh
#   tied special) is REJECTED under zsh; bash accepts the rename control.
#   This pins WHY tripwire check (d) exists.
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s11-zsh.sh" <<'PROBE'
LINES=()
echo "zsh-accepted-LINES"
PROBE
# zsh side must FAIL (nonzero) on `LINES=()`.
if zsh "$WORK/s11-zsh.sh" >/dev/null 2>"$WORK/s11.zsh.err"; then
  fail "s11: zsh rejects LINES=() special-param assign" \
    "zsh ACCEPTED LINES=() — the special-param collision premise (check d) no longer holds"
else
  pass "s11: zsh REJECTS LINES=() array assign (pins check (d) rationale)"
fi
# bash control: the renamed var assigns fine.
cat > "$WORK/s11-bash.sh" <<'PROBE'
MY_LINES=()
MY_LINES+=("ok")
echo "rename-control=${MY_LINES[0]}"
PROBE
if [ "$(bash "$WORK/s11-bash.sh" 2>/dev/null)" = "rename-control=ok" ]; then
  pass "s11: bash rename control (MY_LINES) assigns cleanly"
else
  fail "s11: bash rename control" "unexpected output"
fi

# ─────────────────────────────────────────────────────────────────────────
# s12 — GLOB_SUBST residual pin. With ALL THREE v2 opts set, `v="*.md"; echo $v`
#   prints the LITERAL under zsh but glob-EXPANDS under bash — the v2 guard
#   deliberately does NOT set GLOB_SUBST. This pins that the guard is NOT
#   full bash parity; a future "add GLOB_SUBST" change must update this.
# ─────────────────────────────────────────────────────────────────────────
cat > "$WORK/s12.sh" <<'PROBE'
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
cd "$1" || exit 1
: > alpha.md; : > beta.md
v="*.md"
# count words the glob expands to (bash) vs the literal token (zsh)
set -- $v
echo "argc=$#"
PROBE
S12_BASH="$WORK/s12-bash-d"; S12_ZSH="$WORK/s12-zsh-d"
mkdir -p "$S12_BASH" "$S12_ZSH"
o_bash="$(bash "$WORK/s12.sh" "$S12_BASH" 2>/dev/null)"
o_zsh="$(zsh "$WORK/s12.sh" "$S12_ZSH" 2>/dev/null)"
# bash glob-expands "*.md" → 2 files → argc=2; zsh (no GLOB_SUBST) → literal → argc=1
if [ "$o_bash" = "argc=2" ] && [ "$o_zsh" = "argc=1" ]; then
  pass "s12: GLOB_SUBST residual pinned (bash expands glob-in-var, zsh keeps literal under v2 guard)"
else
  fail "s12: GLOB_SUBST residual" \
    "expected bash=argc=2 zsh=argc=1; got bash=$(printf '%q' "$o_bash") zsh=$(printf '%q' "$o_zsh") — if this flipped, the guard's parity profile changed; update the recorded residual + plan"
fi

summary_and_exit
