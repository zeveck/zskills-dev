#!/usr/bin/env bash
# Sandbox integration test for block-stale-skill-version.sh + the
# install-helpers-into.sh driver.
#
# Plan B Phase 4 spec — proves end-to-end:
#   (1) The shared install driver populates a consumer repo's scripts/
#       with the 4 helpers required by block-stale-skill-version.sh.
#   (2) The hook, when fed a synthetic Bash `git commit` JSON envelope
#       with a stale-versioned skill staged, emits a deny envelope with
#       a STOP: reason.
#   (3) Collision policy: SKIP (pre-existing identical) leaves mtime
#       untouched; COPY (pre-existing different) updates mtime and
#       restores canonical content.
#
# This test does NOT invoke `claude -p` — it directly pipes JSON to the
# installed hook script, the same pattern as tests/test-block-stale-skill-version.sh.
# The Phase 1 reference doc's manual recipes already establish that the
# harness composes hooks correctly; this test proves install + invocation
# against the shared driver (closes C2: tests prove the binary works AND
# the install path works because they invoke the same script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/install-helpers-into.sh"
HOOK="$REPO_ROOT/hooks/block-stale-skill-version.sh"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  printf '\033[32m  PASS\033[0m %s\n' "$1"
  ((PASS_COUNT++))
}

fail() {
  printf '\033[31m  FAIL\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  ((FAIL_COUNT++))
}

skip() {
  printf '\033[33m  SKIP\033[0m %s\n' "$1"
  printf '    %s\n' "$2"
  ((SKIP_COUNT++))
}

echo "=== block-stale-skill-version-sandbox ==="

# ──────────────────────────────────────────────────────────────
# Sandbox setup.
# ──────────────────────────────────────────────────────────────
TMP=$(mktemp -d -p /tmp zskills-sandbox.XXXX)
trap 'rm -rf "$TMP"' EXIT INT TERM

CONSUMER="$TMP/consumer"
mkdir -p "$CONSUMER"

# Initialise consumer git repo.
(
  cd "$CONSUMER"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
)

# ──────────────────────────────────────────────────────────────
# Step 1: shared driver install.
# ──────────────────────────────────────────────────────────────
DRIVER_LOG=$(bash "$DRIVER" "$CONSUMER" 2>&1)
DRIVER_RC=$?

if [ "$DRIVER_RC" -eq 0 ]; then
  pass "driver install rc=0"
else
  fail "driver install rc=$DRIVER_RC" "$DRIVER_LOG"
fi

# AC1: scripts/ exists post-install (N7 — fresh repo had no scripts/).
if [ -d "$CONSUMER/scripts" ]; then
  pass "consumer scripts/ created (N7)"
else
  fail "consumer scripts/ missing" "expected $CONSUMER/scripts/"
fi

# All 4 helpers landed and are executable.
HELPERS=(
  skill-version-stage-check.sh
  skill-content-hash.sh
  frontmatter-get.sh
  frontmatter-set.sh
)
for h in "${HELPERS[@]}"; do
  if [ -x "$CONSUMER/scripts/$h" ]; then
    pass "helper installed and exec: $h"
  else
    fail "helper missing/not-exec: $h" "ls=$(ls -la "$CONSUMER/scripts/$h" 2>&1)"
  fi
done

# ──────────────────────────────────────────────────────────────
# Step 2: install hook + minimal settings.json (prose-only portion of
# /update-zskills Step C).
# ──────────────────────────────────────────────────────────────
mkdir -p "$CONSUMER/.claude/hooks"
cp "$REPO_ROOT/hooks/block-stale-skill-version.sh" "$CONSUMER/.claude/hooks/"
chmod +x "$CONSUMER/.claude/hooks/block-stale-skill-version.sh"

cat > "$CONSUMER/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/block-stale-skill-version.sh\""
          }
        ]
      }
    ]
  }
}
JSON

# Validate settings.json with python3.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
ok=any("block-stale-skill-version.sh" in h["command"]
       for ev in d["hooks"]["PreToolUse"]
       for h in ev.get("hooks", []))
sys.exit(0 if ok else 1)
' "$CONSUMER/.claude/settings.json"; then
    pass "settings.json registers block-stale-skill-version hook"
  else
    fail "settings.json missing hook registration" "$(cat "$CONSUMER/.claude/settings.json")"
  fi
else
  skip "settings.json validation" "python3 not available"
fi

# ──────────────────────────────────────────────────────────────
# Step 3: seed a fake skill with valid frontmatter, commit it, then edit
# its body without bumping metadata.version.
# ──────────────────────────────────────────────────────────────
mkdir -p "$CONSUMER/skills/foo"
cat > "$CONSUMER/skills/foo/SKILL.md" <<'SKILL'
---
name: foo
description: >-
  A fake test skill for sandbox integration testing.
metadata:
  version: "2026.05.02+aaaaaa"
---

# /foo — fake skill body
SKILL

(
  cd "$CONSUMER"
  git add skills/foo/SKILL.md
  git commit -q -m "seed: fake skill foo"
)

# Now edit body WITHOUT bumping the version → stale-version condition.
cat > "$CONSUMER/skills/foo/SKILL.md" <<'SKILL'
---
name: foo
description: >-
  A fake test skill for sandbox integration testing.
metadata:
  version: "2026.05.02+aaaaaa"
---

# /foo — fake skill body, EDITED to make the hash stale.
SKILL

(
  cd "$CONSUMER"
  git add skills/foo/SKILL.md
)

# ──────────────────────────────────────────────────────────────
# Step 4: synthetic-JSON deny test.
# ──────────────────────────────────────────────────────────────
DENY_INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}'
DENY_OUT=$(printf '%s' "$DENY_INPUT" \
  | CLAUDE_PROJECT_DIR="$CONSUMER" bash "$CONSUMER/.claude/hooks/block-stale-skill-version.sh" 2>/dev/null)
DENY_RC=$?

if [ "$DENY_RC" -eq 0 ] && [[ "$DENY_OUT" == *'"permissionDecision":"deny"'* ]]; then
  pass "deny on stale-version skill commit"
else
  fail "deny envelope not emitted" "rc=$DENY_RC stdout=$DENY_OUT"
fi

# Decode the JSON reason and verify STOP: prefix.
if command -v python3 >/dev/null 2>&1; then
  REASON=$(printf '%s' "$DENY_OUT" \
    | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["hookSpecificOutput"]["permissionDecisionReason"])' 2>/dev/null)
  if [[ "$REASON" == *"STOP:"* ]]; then
    pass "deny reason contains STOP:"
  else
    fail "deny reason missing STOP:" "decoded=$REASON"
  fi
else
  skip "deny reason JSON decode" "python3 not available"
fi

# ──────────────────────────────────────────────────────────────
# Step 5: negative test — bump the version correctly, re-stage, expect allow.
# ──────────────────────────────────────────────────────────────
# Compute the correct hash for the edited skill body.
NEW_HASH=$(bash "$REPO_ROOT/scripts/skill-content-hash.sh" "$CONSUMER/skills/foo")
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
NEW_VER="${TODAY}+${NEW_HASH}"

# Replace the metadata.version line in place.
python3 - "$CONSUMER/skills/foo/SKILL.md" "$NEW_VER" <<'PY'
import sys, re
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    txt = f.read()
txt = re.sub(r'(\n\s+version:\s*)"[^"]*"', r'\1"' + ver + '"', txt, count=1)
with open(path, 'w') as f:
    f.write(txt)
PY

(
  cd "$CONSUMER"
  git add skills/foo/SKILL.md
)

ALLOW_OUT=$(printf '%s' "$DENY_INPUT" \
  | CLAUDE_PROJECT_DIR="$CONSUMER" bash "$CONSUMER/.claude/hooks/block-stale-skill-version.sh" 2>/dev/null)
ALLOW_RC=$?

if [ "$ALLOW_RC" -eq 0 ] && [ -z "$ALLOW_OUT" ]; then
  pass "allow after correct bump"
else
  fail "allow expected, got deny" "rc=$ALLOW_RC stdout=$ALLOW_OUT"
fi

# ──────────────────────────────────────────────────────────────
# Step 6: AC10 collision-policy verification.
#   - SKIP path: rerun driver with helpers identical → mtime unchanged.
#   - COPY path: corrupt one helper, rerun driver → mtime updated AND
#                content restored to canonical source.
# ──────────────────────────────────────────────────────────────
DST="$CONSUMER/scripts/frontmatter-get.sh"
SRC="$REPO_ROOT/scripts/frontmatter-get.sh"

# Ensure DST is identical to SRC.
cp "$SRC" "$DST"
chmod +x "$DST"
mtime_before=$(stat -c %Y "$DST")
sleep 1
SKIP_LOG=$(bash "$DRIVER" "$CONSUMER" 2>&1)
mtime_after=$(stat -c %Y "$DST")

if echo "$SKIP_LOG" | grep -qF 'SKIP:' && [ "$mtime_after" = "$mtime_before" ]; then
  pass "SKIP path: identical helper untouched (mtime stable)"
else
  fail "SKIP path failed" "log=$SKIP_LOG mtime_before=$mtime_before mtime_after=$mtime_after"
fi

# COPY path: modify DST so it differs.
echo '# corrupted by sandbox test' >> "$DST"
mtime_before2=$(stat -c %Y "$DST")
sleep 1
COPY_LOG=$(bash "$DRIVER" "$CONSUMER" 2>&1)
mtime_after2=$(stat -c %Y "$DST")

if echo "$COPY_LOG" | grep -qF 'COPY:' \
   && [ "$mtime_after2" -gt "$mtime_before2" ] \
   && cmp -s "$SRC" "$DST"; then
  pass "COPY path: differing helper overwritten (mtime bump + content match)"
else
  fail "COPY path failed" "log=$COPY_LOG mtime_before=$mtime_before2 mtime_after=$mtime_after2 cmp_rc=$?"
fi

# ──────────────────────────────────────────────────────────────
# Step 7: explicit cleanup verification (do not rely solely on trap).
# ──────────────────────────────────────────────────────────────
# Reset trap; remove sandbox; verify gone.
trap - EXIT INT TERM
rm -rf "$TMP"
if [ ! -d "$TMP" ]; then
  pass "cleanup OK"
  echo "cleanup OK"
else
  fail "cleanup failed" "directory still exists: $TMP"
fi

echo ""
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
printf 'Results: %d passed, %d failed, %d skipped (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
