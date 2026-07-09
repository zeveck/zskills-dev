#!/bin/bash
# tests/test-porting-scanner.sh — suite for the Claude-construct scanner +
# fail-closed gate caller (CODEX_PORT_PLAN Phase 3, WIs 3.1/3.2/3.6).
#
# Fixture trees live under tests/fixtures/porting/: per-class known hits
# (every v1 class fires), a clean tree, allow-marked trees in BOTH comment
# syntaxes, an unknown-construct tree, a --scope tree, and a meta-record
# exemption tree. The live-repo census-floor check runs discovery scoped to
# skills/ — the SAME scope the gate's floors were derived from (WI 3.2).
#
# pass/fail inline (mirrors tests/test-porting-probe-kit.sh).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCANNER="$REPO_ROOT/scripts/porting/codex-scan.py"
GATE="$REPO_ROOT/scripts/porting/codex-scan-gate.sh"
FIX="$REPO_ROOT/tests/fixtures/porting"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

PYTHON="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON" ]; then
  echo "SKIP: no python3/python available (required by the scanner)" >&2
  echo "Results: 0 passed, 0 failed (of 0)"
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-codex-scan-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

for f in "$SCANNER" "$GATE"; do
  if [ ! -f "$f" ]; then
    fail "required script not found at $f"
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
    exit 1
  fi
done

# ── 1. --list-classes (recipe-parity contract) ──────────────────────────────
LIST_OUT="$WORK/classes.txt"
"$PYTHON" "$SCANNER" --list-classes > "$LIST_OUT"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "--list-classes exits 0"
else
  fail "--list-classes exited $rc"
fi
CLASS_N="$(grep -c '' "$LIST_OUT")"
if [ "$CLASS_N" -ge 10 ]; then
  pass "--list-classes size $CLASS_N >= 10 (v1 table)"
else
  fail "--list-classes size $CLASS_N < 10"
fi
if grep -qEv '^[a-z][a-z0-9-]*$' "$LIST_OUT"; then
  fail "--list-classes output is not pure ids: $(grep -Ev '^[a-z][a-z0-9-]*$' "$LIST_OUT" | sed -n '1p')"
else
  pass "--list-classes output is pure (one class id per line)"
fi
if sort "$LIST_OUT" | uniq -d | grep -q .; then
  fail "--list-classes contains duplicate ids"
else
  pass "--list-classes ids are unique"
fi

# ── 2. per-class known-hit fixture: every v1 class fires ────────────────────
HITS_SUMMARY="$("$PYTHON" "$SCANNER" --mode discover "$FIX/scan-hits" | tail -1)"
ALL_FIRE=1
while IFS= read -r cid; do
  if [[ ",${HITS_SUMMARY#*per-class=}," =~ ,"$cid":([0-9]+), ]]; then
    n="${BASH_REMATCH[1]}"
    if [ "$n" -gt 0 ]; then
      pass "known-hit fixture: class '$cid' fires ($n)"
    else
      fail "known-hit fixture: class '$cid' count is 0"
      ALL_FIRE=0
    fi
  else
    fail "known-hit fixture: class '$cid' missing from per-class census"
    ALL_FIRE=0
  fi
done < "$LIST_OUT"
[ "$ALL_FIRE" -eq 1 ] && pass "known-hit fixture: every v1 class fires at least once"

# ── 3. summary-line format parse ────────────────────────────────────────────
if printf '%s\n' "$HITS_SUMMARY" | grep -Eq '^CODEX-SCAN-SUMMARY: files=[0-9]+ hits=[0-9]+ violations=[0-9]+ unknown=[0-9]+ per-class=([a-z0-9-]+:[0-9]+,)*[a-z0-9-]+:[0-9]+$'; then
  pass "summary line is well-formed: format parses"
else
  fail "summary line malformed: '$HITS_SUMMARY'"
fi

# ── 4. scanner is a pure reporter (exit 0 even with gate-mode violations) ───
"$PYTHON" "$SCANNER" --mode gate "$FIX/scan-hits" > "$WORK/gate-mode-scan.out"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "scanner is a pure reporter (exit 0 with gate-mode violations present)"
else
  fail "scanner exited $rc in gate mode (policy belongs in the bash caller)"
fi

# ── 5. clean fixture: gate exit 0 (the pinned AC command) ───────────────────
if bash "$GATE" "$FIX/clean-tree" > "$WORK/clean.out" 2>&1; then
  pass "gate over clean-tree exits 0"
else
  fail "gate over clean-tree exited non-zero: $(tail -2 "$WORK/clean.out" | tr '\n' ' ')"
fi

# ── 6. unknown-construct fixture: gate exit 1, names file/line/unknown ─────
if bash "$GATE" "$FIX/unknown-tree" > "$WORK/unknown.out" 2>&1; then
  fail "gate over unknown-tree exited 0 (must fail closed on unknown>0)"
else
  pass "gate over unknown-tree exits non-zero"
fi
if grep -q 'notes\.md:[0-9]*: \[unknown-class\]' "$WORK/unknown.out"; then
  pass "unknown finding names the file, line, and unknown class"
else
  fail "unknown finding missing file:line [unknown-class]: $(sed -n '1p' "$WORK/unknown.out")"
fi

# ── 7. allow-marker, .md HTML form: suppresses; removal un-suppresses ───────
if bash "$GATE" "$FIX/allow-md" > "$WORK/allow-md.out" 2>&1; then
  pass "allow-marker case allow-md (.md HTML form): gate clean with marker present"
else
  fail "allow-md gate exited non-zero with marker present: $(tail -2 "$WORK/allow-md.out" | tr '\n' ' ')"
fi
mkdir -p "$WORK/allow-md-stripped"
grep -v 'codex-port-allow' "$FIX/allow-md/page.md" > "$WORK/allow-md-stripped/page.md"
if bash "$GATE" "$WORK/allow-md-stripped" > "$WORK/allow-md-stripped.out" 2>&1; then
  fail "allow-md: gate still passes with the marker removed"
else
  pass "allow-marker case allow-md (.md HTML form): removing the marker makes the gate exit non-zero"
fi

# ── 8. allow-marker, .sh hash form: suppresses; removal un-suppresses ───────
if bash "$GATE" "$FIX/allow-sh" > "$WORK/allow-sh.out" 2>&1; then
  pass "allow-marker case allow-sh (.sh # form): gate clean with marker present"
else
  fail "allow-sh gate exited non-zero with marker present: $(tail -2 "$WORK/allow-sh.out" | tr '\n' ' ')"
fi
mkdir -p "$WORK/allow-sh-stripped"
grep -v 'codex-port-allow' "$FIX/allow-sh/hook.sh" > "$WORK/allow-sh-stripped/hook.sh"
if bash "$GATE" "$WORK/allow-sh-stripped" > "$WORK/allow-sh-stripped.out" 2>&1; then
  fail "allow-sh: gate still passes with the marker removed"
else
  pass "allow-marker case allow-sh (.sh # form): removing the marker makes the gate exit non-zero"
fi

# ── 9. --scope pass-through (WI 3.2 — the slice ACs depend on this) ─────────
if bash "$GATE" "$FIX/scoped-tree" --scope clean > "$WORK/scoped.out" 2>&1; then
  pass "--scope clean: gate over scoped-tree exits 0 (violation outside the scope)"
else
  fail "--scope clean gate exited non-zero: $(tail -2 "$WORK/scoped.out" | tr '\n' ' ')"
fi
if bash "$GATE" "$FIX/scoped-tree" > "$WORK/unscoped.out" 2>&1; then
  fail "unscoped gate over scoped-tree exited 0 (must see dirty/skill.md)"
else
  pass "unscoped gate over the same tree exits non-zero"
fi
if grep -q 'dirty/skill\.md' "$WORK/unscoped.out"; then
  pass "unscoped gate names the out-of-scope violation file"
else
  fail "unscoped gate output does not name dirty/skill.md"
fi

# ── 10. meta-record exemption (WI 3.1 path exclusion, root-only) ────────────
if bash "$GATE" "$FIX/meta-tree" > "$WORK/meta.out" 2>&1; then
  pass "gate over meta-tree exits 0 (root GAPS.md/DEGRADATIONS.md/PORT_MANIFEST.json/PORTING-NOTES.md exempt)"
else
  fail "gate over meta-tree exited non-zero: $(tail -3 "$WORK/meta.out" | tr '\n' ' ')"
fi
if grep -Eq '(GAPS|DEGRADATIONS|PORTING-NOTES)\.md:|PORT_MANIFEST\.json:' "$WORK/meta.out"; then
  fail "meta-records were scanned (findings reference them): $(grep -E '(GAPS|DEGRADATIONS)\.md:' "$WORK/meta.out" | sed -n '1p')"
else
  pass "meta-records are unscanned (no finding references them)"
fi
# the SAME text in a root NOTES.md — not on the exempt list — must violate
mkdir -p "$WORK/meta-notes-tree"
cp "$FIX/meta-tree/README.md" "$WORK/meta-notes-tree/README.md"
cp "$FIX/meta-tree/GAPS.md" "$WORK/meta-notes-tree/NOTES.md"
if bash "$GATE" "$WORK/meta-notes-tree" > "$WORK/meta-notes.out" 2>&1; then
  fail "gate passes with the GAPS.md text in a root NOTES.md (exemption leaked past the exact-path list)"
else
  pass "the same text in a root NOTES.md (not exempt) makes the gate exit non-zero"
fi
if grep -q 'NOTES\.md:' "$WORK/meta-notes.out"; then
  pass "the NOTES.md violation names the file"
else
  fail "NOTES.md violation not named in gate output"
fi

# ── 11. live-repo census-floor check (skills/-scoped, same scope as floors) ─
if bash "$GATE" "$REPO_ROOT" --mode discover > "$WORK/census.out" 2>&1; then
  pass "discover-mode gate over the live repo clears every census floor (skills/-scoped)"
else
  fail "discover-mode census gate failed: $(grep 'CODEX-SCAN-GATE' "$WORK/census.out" | tr '\n' ' ')"
fi
LIVE_SUMMARY="$(grep '^CODEX-SCAN-SUMMARY:' "$WORK/census.out" | tail -1)"
LIVE_ALL_POS=1
while IFS= read -r cid; do
  if [[ ",${LIVE_SUMMARY#*per-class=}," =~ ,"$cid":([0-9]+), ]]; then
    [ "${BASH_REMATCH[1]}" -gt 0 ] || LIVE_ALL_POS=0
  else
    LIVE_ALL_POS=0
  fi
done < "$LIST_OUT"
if [ "$LIVE_ALL_POS" -eq 1 ]; then
  pass "live-tree census: every v1 class count > 0 ($LIVE_SUMMARY)"
else
  fail "live-tree census has a zero/missing class count: $LIVE_SUMMARY"
fi
# the AC's exact invocation shape (root = skills/ itself) must census-match
AC_SUMMARY="$("$PYTHON" "$SCANNER" --mode discover "$REPO_ROOT/skills" | tail -1)"
if [ "${AC_SUMMARY#*per-class=}" = "${LIVE_SUMMARY#*per-class=}" ]; then
  pass "AC-shape run (root=skills/) censuses identically to the gate's skills-scoped run"
else
  fail "root=skills/ census differs from --scope skills census: '$AC_SUMMARY' vs '$LIVE_SUMMARY'"
fi

# ── 12. floor/class-table parity (fail-closed against drift) ────────────────
# Every class id in the gate's CENSUS_FLOORS table must be a --list-classes
# id and vice versa (a drifted floor table would otherwise silently skip a
# class or fail on a phantom one).
FLOOR_IDS="$WORK/floor-ids.txt"
sed -n 's/^  "\([a-z0-9-]*\):[0-9]*"$/\1/p' "$GATE" | sort > "$FLOOR_IDS"
if diff <(sort "$LIST_OUT") "$FLOOR_IDS" > /dev/null; then
  pass "gate floor table ids match --list-classes exactly"
else
  fail "gate floor table ids drifted from --list-classes: $(diff <(sort "$LIST_OUT") "$FLOOR_IDS" | tr '\n' ' ')"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
