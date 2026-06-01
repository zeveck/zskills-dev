#!/bin/bash
# tests/test-extract-fence-lib.sh — self-test for tests/lib/extract-fence.sh
# (SEAM_HARDENING_HIGH Phase 1).
#
# Makes the extract-and-run idiom itself a tested primitive. Asserts:
#   1. extract_fence_between round-trips a known column-0 ```bash fence from a
#      real SKILL.md (byte-identical to the source body).
#   2. fence-index selects the Nth fence between landmarks.
#   3. strip-indent=1 dedents a 3-space-indented fence (commit/SKILL.md).
#   4. extract_sentinel_block slices exactly BEGIN..END (exclusive of the
#      sentinel lines) from a real inline-sentinel fence.
#   5. Each extractor FAILS (non-zero) when its anchor is absent — so a broken
#      extraction cannot pass silently.
#
# If any of these break, the extract-and-run tests built on this lib would
# silently extract the wrong text; this suite is the tripwire.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

LANDPR="$REPO_ROOT/skills/land-pr/SKILL.md"
COMMIT="$REPO_ROOT/skills/commit/SKILL.md"
CALLER_LOOP="$REPO_ROOT/skills/land-pr/references/caller-loop-pattern.md"

PASS=0
FAIL=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

for f in "$LANDPR" "$COMMIT" "$CALLER_LOOP"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required source file not found: $f" >&2
    exit 1
  fi
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── 1. Round-trip a known column-0 fence (Step 7c of land-pr) ─────────
# Extract the fence between the Step 7c heading and the Step 8 heading and
# diff it against the same body sliced out of the source by sed. They must be
# byte-identical.
extract_fence_between "$LANDPR" \
  'Step 7c — Copy worktree tracking markers to main' \
  'Step 8 — Compose' 1 0 > "$TMP/extracted.sh"

# Independently slice the fence body straight from the source with awk: the
# first ```bash..``` block after the Step 7c heading.
awk '
  /Step 7c — Copy worktree tracking markers to main/ { armed=1 }
  armed && infence==0 && /^```bash[[:space:]]*$/ { infence=1; next }
  infence==1 && /^```[[:space:]]*$/ { exit }
  infence==1 { print }
' "$LANDPR" > "$TMP/reference.sh"

if [ -s "$TMP/extracted.sh" ] && diff -q "$TMP/extracted.sh" "$TMP/reference.sh" >/dev/null; then
  pass "[roundtrip] extract_fence_between byte-matches Step 7c source body"
else
  fail "[roundtrip] Step 7c body" "diff: $(diff "$TMP/reference.sh" "$TMP/extracted.sh" 2>&1 | head -5)"
fi

# The extracted fence must contain the load-bearing production line.
if grep -qF 'cp -af "$WT_TRACK/." "$MAIN_TRACK/"' "$TMP/extracted.sh"; then
  pass "[roundtrip] extracted fence carries the real cp -af copy line"
else
  fail "[roundtrip] cp -af line" "not found in extracted fence"
fi

# ── 2. fence-index selects the Nth fence between landmarks ────────────
# Build a fixture with two ```bash fences between two landmarks.
cat > "$TMP/two-fences.md" <<'EOF'
## START HERE

```bash
echo first-fence
```

some prose

```bash
echo second-fence
```

## STOP HERE
EOF

idx1=$(extract_fence_between "$TMP/two-fences.md" 'START HERE' 'STOP HERE' 1 0)
idx2=$(extract_fence_between "$TMP/two-fences.md" 'START HERE' 'STOP HERE' 2 0)
if [ "$idx1" = "echo first-fence" ]; then
  pass "[index] fence-index 1 selects the first fence"
else
  fail "[index] fence 1" "got: '$idx1'"
fi
if [ "$idx2" = "echo second-fence" ]; then
  pass "[index] fence-index 2 selects the second fence"
else
  fail "[index] fence 2" "got: '$idx2'"
fi

# ── 3. strip-indent dedents a 3-space-indented fence ──────────────────
# commit/SKILL.md line ~188: a 3-space-indented fence whose body is
# `   git status -s | grep -i <keyword>`. With strip-indent=1 the leading
# 3-space run is removed.
indented=$(extract_fence_between "$COMMIT" \
  'Keyword grep' 'Diff-check remaining files' 1 0)
dedented=$(extract_fence_between "$COMMIT" \
  'Keyword grep' 'Diff-check remaining files' 1 1)

# Without strip, the body retains its 3-space prefix.
if printf '%s\n' "$indented" | grep -q '^   git status -s'; then
  pass "[strip] strip-indent=0 preserves the 3-space prefix"
else
  fail "[strip] indent preserved" "got: '$indented'"
fi
# With strip, the prefix is gone (column-0).
if printf '%s\n' "$dedented" | grep -q '^git status -s' \
   && ! printf '%s\n' "$dedented" | grep -q '^   git status -s'; then
  pass "[strip] strip-indent=1 dedents the fence body to column 0"
else
  fail "[strip] dedent" "got: '$dedented'"
fi

# ── 4. extract_sentinel_block slices BEGIN..END exclusive ─────────────
# Real inline-sentinel fence in caller-loop-pattern.md.
sentinel=$(extract_sentinel_block "$CALLER_LOOP" \
  '# === BEGIN CANONICAL /land-pr CALLER LOOP ===' \
  '# === END CANONICAL /land-pr CALLER LOOP ===')

if [ -n "$sentinel" ]; then
  pass "[sentinel] extract_sentinel_block returns a non-empty slice"
else
  fail "[sentinel] non-empty" "slice was empty"
fi
# The sentinel lines themselves must NOT be in the slice.
if printf '%s\n' "$sentinel" | grep -qF '=== BEGIN CANONICAL'; then
  fail "[sentinel] BEGIN excluded" "BEGIN sentinel leaked into slice"
else
  pass "[sentinel] BEGIN sentinel line excluded from slice"
fi
if printf '%s\n' "$sentinel" | grep -qF '=== END CANONICAL'; then
  fail "[sentinel] END excluded" "END sentinel leaked into slice"
else
  pass "[sentinel] END sentinel line excluded from slice"
fi
# A known interior line must be present.
if printf '%s\n' "$sentinel" | grep -qF 'RESULT_FILE="/tmp/land-pr-result-$BRANCH_SLUG-$$.txt"'; then
  pass "[sentinel] slice carries a known interior loop line"
else
  fail "[sentinel] interior line" "expected RESULT_FILE line not in slice"
fi

# ── 5. Failure modes — missing anchors return non-zero ────────────────
if extract_fence_between "$LANDPR" \
     'NO_SUCH_START_LANDMARK_XYZ' 'STOP HERE' 1 0 >/dev/null 2>&1; then
  fail "[failmode] missing start landmark" "expected non-zero exit, got 0"
else
  pass "[failmode] extract_fence_between exits non-zero when start landmark absent"
fi
if extract_sentinel_block "$CALLER_LOOP" \
     '# === BEGIN NO_SUCH_SENTINEL_XYZ ===' \
     '# === END NO_SUCH_SENTINEL_XYZ ===' >/dev/null 2>&1; then
  fail "[failmode] missing sentinel" "expected non-zero exit, got 0"
else
  pass "[failmode] extract_sentinel_block exits non-zero when begin sentinel absent"
fi

echo ""
echo "---"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS" "$FAIL" "$TOTAL"
  exit 1
fi
