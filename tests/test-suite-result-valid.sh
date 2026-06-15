#!/bin/bash
# Tests for the provenance-result validator tests/lib/suite-result-valid.sh
# (SUITE_PROVENANCE Phase 1, #1166).
#
# The validator answers ONLY "is this result still TRUE for the current tree?"
# (non-empty fields + tree + CONTENT-fingerprint + age < 30min), NOT "did it
# pass?". Each fixture synthesizes a provenance header from LIVE values via the
# lib's OWN fingerprint formula (so the round-trip is self-consistent on any
# platform), then asserts the validator's exit code.
#
# Content-drift cases run against a `mktemp -d` SCRATCH git repo (the test must
# never mutate the worktree it runs in): the header is captured with REPO_ROOT
# pointed at the scratch repo, then the scratch tree's CONTENT is mutated, then
# the validator is re-run with the SAME REPO_ROOT — proving the
# content-sensitive fingerprint flips on a content-only change (the
# R1-1/DA1 regression the porcelain-path formula missed).
#
# Cases:
#   VALID                     — live tree/fingerprint, epoch=now            → 0
#   INVALID-tree              — fabricated tree SHA                          → 1
#   INVALID-fingerprint       — wrong fingerprint hash                       → 1
#   CONTENT-DRIFT             — same paths, different tracked CONTENT        → 1
#   UNTRACKED-CONTENT-DRIFT   — untracked file CONTENT changes              → 1
#   CLEAN-STABLE              — header from a clean tree validates again     → 0
#   STALE                     — epoch 31 min old                            → 1
#   FRESH-boundary            — epoch ~29 min old                           → 0
#   MISSING-file              — nonexistent path                            → 1
#   MISSING-header            — file with no provenance marker              → 1
#   GARBLED-header            — marker present but a field missing           → 1
#   EMPTY-FIELD               — header with an EMPTY tree=/fingerprint=/epoch= → 1
#   FUTURE-epoch              — epoch greater than now                       → 1
#
# Run from repo root: bash tests/test-suite-result-valid.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/tests/lib/suite-result-valid.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

summary_and_exit() {
  echo ""
  echo "---"
  local total=$((PASS_COUNT + FAIL_COUNT))
  if [ "$FAIL_COUNT" -eq 0 ]; then
    printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$total"
    exit 0
  else
    printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$total"
    exit 1
  fi
}

if [ ! -f "$LIB" ]; then
  fail "validator lib exists" "$LIB missing"
  summary_and_exit
fi

# Validate <file> against a given REPO_ROOT; echo the exit code. Runs in a
# subshell with REPO_ROOT exported so the lib's live git calls target the
# chosen repo, and unsets the function so each call re-sources cleanly.
validate_against() {
  local repo="$1" file="$2"
  ( export REPO_ROOT="$repo"; bash "$LIB" "$file"; echo "RC=$?" ) 2>/dev/null \
    | grep -oE 'RC=[0-9]+' | sed 's/RC=//'
}

# Compute the live content-sensitive fingerprint of a repo via the SAME formula
# the lib uses (so headers are self-consistent). Mirrors run-all.sh verbatim.
live_fingerprint() {
  local repo="$1"
  {
    git -C "$repo" rev-parse HEAD
    git -C "$repo" diff HEAD
    git -C "$repo" ls-files --others --exclude-standard -z \
      | while IFS= read -r -d '' f; do
          printf '%s\0' "$f"
          git -C "$repo" hash-object "$repo/$f"
        done
  } 2>/dev/null | git -C "$repo" hash-object --stdin 2>/dev/null
}

# Write a provenance header to <file>. Args: file tree fingerprint epoch.
# timestamp is derived from epoch-of-now (forensic-only; the validator never
# parses it, only requires non-empty).
write_header() {
  local file="$1" tree="$2" fp="$3" epoch="$4"
  {
    echo "zskills-suite-provenance: v1"
    echo "tree=$tree"
    echo "fingerprint=$fp"
    echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "epoch=$epoch"
    echo "command=tests/run-all.sh"
  } > "$file"
}

now_epoch() { date -u +%s; }

# ── Scratch repos / fixtures (all under mktemp; never a hardcoded /tmp path) ──
SCRATCH="$(mktemp -d)"
FIXT="$(mktemp -d)"
cleanup() { rm -rf "$SCRATCH" "$FIXT"; }
trap cleanup EXIT INT TERM

# A scratch git repo with one committed tracked file.
DRIFT_REPO="$SCRATCH/drift"
mkdir -p "$DRIFT_REPO"
git -C "$DRIFT_REPO" init -q
git -C "$DRIFT_REPO" config user.email t@t
git -C "$DRIFT_REPO" config user.name t
printf 'original\n' > "$DRIFT_REPO/f.txt"
git -C "$DRIFT_REPO" add f.txt
git -C "$DRIFT_REPO" commit -qm init
DRIFT_HEAD="$(git -C "$DRIFT_REPO" rev-parse HEAD)"

# ── Case VALID: live tree/fingerprint of the scratch repo, epoch=now → 0 ─────
echo "=== Case VALID: live tree/fingerprint, epoch=now → exit 0 ==="
F="$FIXT/valid.txt"
write_header "$F" "$DRIFT_HEAD" "$(live_fingerprint "$DRIFT_REPO")" "$(now_epoch)"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "0" ] && pass "VALID → exit 0" || fail "VALID" "expected 0 got '$RC'"

# ── Case INVALID-tree: fabricated tree SHA → 1 ───────────────────────────────
echo "=== Case INVALID-tree: fabricated tree SHA → exit 1 ==="
F="$FIXT/invtree.txt"
write_header "$F" "0000000000000000000000000000000000000000" "$(live_fingerprint "$DRIFT_REPO")" "$(now_epoch)"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "1" ] && pass "INVALID-tree → exit 1" || fail "INVALID-tree" "expected 1 got '$RC'"

# ── Case INVALID-fingerprint: wrong fingerprint hash → 1 ─────────────────────
echo "=== Case INVALID-fingerprint: wrong fingerprint → exit 1 ==="
F="$FIXT/invfp.txt"
write_header "$F" "$DRIFT_HEAD" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$(now_epoch)"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "1" ] && pass "INVALID-fingerprint → exit 1" || fail "INVALID-fingerprint" "expected 1 got '$RC'"

# ── Case CONTENT-DRIFT: capture fingerprint, mutate tracked CONTENT (same
# path/status), re-validate → fingerprint flips → 1 (the porcelain formula
# would COLLIDE here). ───────────────────────────────────────────────────────
echo "=== Case CONTENT-DRIFT: same paths, different tracked content → exit 1 ==="
# Make the tracked file dirty first (so both before/after are ` M f.txt`).
printf 'CONTENT_X\n' > "$DRIFT_REPO/f.txt"
F="$FIXT/drift.txt"
write_header "$F" "$DRIFT_HEAD" "$(live_fingerprint "$DRIFT_REPO")" "$(now_epoch)"
# Sanity: it validates BEFORE the content drift.
RC_BEFORE="$(validate_against "$DRIFT_REPO" "$F")"
# Now change CONTENT only (path + porcelain status ` M f.txt` unchanged).
printf 'CONTENT_Y_different\n' > "$DRIFT_REPO/f.txt"
RC_AFTER="$(validate_against "$DRIFT_REPO" "$F")"
if [ "$RC_BEFORE" = "0" ] && [ "$RC_AFTER" = "1" ]; then
  pass "CONTENT-DRIFT → valid before drift (0), invalid after content-only change (1)"
else
  fail "CONTENT-DRIFT" "before='$RC_BEFORE' (want 0) after='$RC_AFTER' (want 1)"
fi

# ── Case UNTRACKED-CONTENT-DRIFT: untracked-not-ignored file CONTENT changes
# → fingerprint flips → 1. ────────────────────────────────────────────────────
echo "=== Case UNTRACKED-CONTENT-DRIFT: untracked file content changes → exit 1 ==="
# Reset the tracked file to its committed content; add an untracked file.
git -C "$DRIFT_REPO" checkout -q -- f.txt
printf 'untracked_A\n' > "$DRIFT_REPO/u.txt"
F="$FIXT/udrift.txt"
write_header "$F" "$DRIFT_HEAD" "$(live_fingerprint "$DRIFT_REPO")" "$(now_epoch)"
RC_BEFORE="$(validate_against "$DRIFT_REPO" "$F")"
printf 'untracked_B_different\n' > "$DRIFT_REPO/u.txt"
RC_AFTER="$(validate_against "$DRIFT_REPO" "$F")"
if [ "$RC_BEFORE" = "0" ] && [ "$RC_AFTER" = "1" ]; then
  pass "UNTRACKED-CONTENT-DRIFT → valid before (0), invalid after content change (1)"
else
  fail "UNTRACKED-CONTENT-DRIFT" "before='$RC_BEFORE' (want 0) after='$RC_AFTER' (want 1)"
fi
rm -f "$DRIFT_REPO/u.txt"

# ── Case CLEAN-STABLE: two fingerprints of an unchanged clean tree are equal;
# a header from the first validates against the second → 0. ───────────────────
echo "=== Case CLEAN-STABLE: clean-tree fingerprint stable → exit 0 ==="
CLEAN_REPO="$SCRATCH/clean"
mkdir -p "$CLEAN_REPO"
git -C "$CLEAN_REPO" init -q
git -C "$CLEAN_REPO" config user.email t@t
git -C "$CLEAN_REPO" config user.name t
printf 'stable\n' > "$CLEAN_REPO/g.txt"
git -C "$CLEAN_REPO" add g.txt
git -C "$CLEAN_REPO" commit -qm init
CLEAN_HEAD="$(git -C "$CLEAN_REPO" rev-parse HEAD)"
FP1="$(live_fingerprint "$CLEAN_REPO")"
FP2="$(live_fingerprint "$CLEAN_REPO")"
F="$FIXT/clean.txt"
write_header "$F" "$CLEAN_HEAD" "$FP1" "$(now_epoch)"
RC="$(validate_against "$CLEAN_REPO" "$F")"
if [ "$FP1" = "$FP2" ] && [ "$RC" = "0" ]; then
  pass "CLEAN-STABLE → fingerprint stable across calls, header validates (0)"
else
  fail "CLEAN-STABLE" "fp1='$FP1' fp2='$FP2' rc='$RC' (want equal fps + rc 0)"
fi

# ── Case STALE: epoch 31 min old → 1 (epoch arithmetic; portable). ───────────
echo "=== Case STALE: epoch 31 min old → exit 1 ==="
F="$FIXT/stale.txt"
write_header "$F" "$DRIFT_HEAD" "$(live_fingerprint "$DRIFT_REPO")" "$(( $(now_epoch) - 1860 ))"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "1" ] && pass "STALE (31 min) → exit 1" || fail "STALE" "expected 1 got '$RC'"

# ── Case FRESH-boundary: epoch ~29 min old → 0. ──────────────────────────────
echo "=== Case FRESH-boundary: epoch ~29 min old → exit 0 ==="
F="$FIXT/fresh.txt"
write_header "$F" "$DRIFT_HEAD" "$(live_fingerprint "$DRIFT_REPO")" "$(( $(now_epoch) - 1740 ))"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "0" ] && pass "FRESH-boundary (29 min) → exit 0" || fail "FRESH-boundary" "expected 0 got '$RC'"

# ── Case MISSING-file: nonexistent path → 1. ─────────────────────────────────
echo "=== Case MISSING-file: nonexistent path → exit 1 ==="
RC="$(validate_against "$DRIFT_REPO" "$FIXT/does-not-exist.txt")"
[ "$RC" = "1" ] && pass "MISSING-file → exit 1" || fail "MISSING-file" "expected 1 got '$RC'"

# ── Case MISSING-header: file with no provenance marker → 1. ─────────────────
echo "=== Case MISSING-header: no provenance marker → exit 1 ==="
F="$FIXT/nomarker.txt"
{ echo "Tests: foo"; echo "Results: 3 passed, 0 failed"; echo "Overall: 3/3 passed, 0 failed"; } > "$F"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "1" ] && pass "MISSING-header → exit 1" || fail "MISSING-header" "expected 1 got '$RC'"

# ── Case GARBLED-header: marker present but a field missing → 1. ──────────────
echo "=== Case GARBLED-header: marker present, fingerprint field missing → exit 1 ==="
F="$FIXT/garbled.txt"
{
  echo "zskills-suite-provenance: v1"
  echo "tree=$DRIFT_HEAD"
  # fingerprint= line deliberately OMITTED
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "epoch=$(now_epoch)"
  echo "command=tests/run-all.sh"
} > "$F"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "1" ] && pass "GARBLED-header (missing field) → exit 1" || fail "GARBLED-header" "expected 1 got '$RC'"

# ── Case EMPTY-FIELD: header with EMPTY tree=/fingerprint=/epoch= → 1
# (clause 0; empty NEVER equals empty-as-valid — the DA3 fail-OPEN case). ──────
echo "=== Case EMPTY-FIELD: empty tree=/fingerprint=/epoch= → exit 1 ==="
EMPTY_FAILS=0
for fieldset in "tree" "fingerprint" "epoch"; do
  F="$FIXT/empty-$fieldset.txt"
  TREE_V="$DRIFT_HEAD"; FP_V="$(live_fingerprint "$DRIFT_REPO")"; EP_V="$(now_epoch)"
  case "$fieldset" in
    tree) TREE_V="" ;;
    fingerprint) FP_V="" ;;
    epoch) EP_V="" ;;
  esac
  write_header "$F" "$TREE_V" "$FP_V" "$EP_V"
  RC="$(validate_against "$DRIFT_REPO" "$F")"
  [ "$RC" = "1" ] && EMPTY_FAILS=$((EMPTY_FAILS + 1)) \
    || fail "EMPTY-FIELD ($fieldset)" "expected 1 got '$RC'"
done
[ "$EMPTY_FAILS" = "3" ] && pass "EMPTY-FIELD (tree/fingerprint/epoch each empty) → exit 1"

# ── Case FUTURE-epoch: epoch greater than now → 1 (defensive). ───────────────
echo "=== Case FUTURE-epoch: epoch greater than now → exit 1 ==="
F="$FIXT/future.txt"
write_header "$F" "$DRIFT_HEAD" "$(live_fingerprint "$DRIFT_REPO")" "$(( $(now_epoch) + 600 ))"
RC="$(validate_against "$DRIFT_REPO" "$F")"
[ "$RC" = "1" ] && pass "FUTURE-epoch → exit 1" || fail "FUTURE-epoch" "expected 1 got '$RC'"

summary_and_exit
