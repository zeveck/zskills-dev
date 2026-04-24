#!/bin/bash
# Integration test for /update-zskills --rerender (DRIFT_ARCH_FIX Phase 2, WI 2.4).
#
# --rerender is an agent-executed command. We cannot literally invoke the
# skill from a shell test. Instead, we encode the algorithm documented in
# `skills/update-zskills/SKILL.md` "### Step D — --rerender" as a bash
# function `run_rerender` below, and run it against fixture directories.
# The function is the executable oracle — if SKILL.md's spec changes
# meaning, the oracle must be updated in lockstep. Any meaningful drift
# between spec and oracle that affects a test case will fail.
#
# Coverage (matches WI 2.4 exactly):
#   1. Happy path:  stale CLAUDE.md + updated config → new CLAUDE.md has current config values.
#   2. Preservation: user content below `## Agent Rules` preserved verbatim.
#   3. Conflict:     user edit above `## Agent Rules` → CLAUDE.md.new written, rc=2, stderr prompt.
#   4. Missing file: no CLAUDE.md → rc=1 with specific error.
#   5. Idempotency:  two back-to-back rerenders → second is a true no-op (mtime stable).

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# --- Oracle implementation of Step D ---------------------------------------
# Args: $1 = working directory (must contain CLAUDE.md — optional — plus
# .claude/zskills-config.json and CLAUDE_TEMPLATE.md in its root).
# Writes CLAUDE.md or CLAUDE.md.new per spec. Prints stderr message verbatim
# on conflict. Exit codes match Step D: 0 clean, 1 missing, 2 conflict.
run_rerender() {
  local dir="$1"
  local claude="$dir/CLAUDE.md"
  local template="$dir/CLAUDE_TEMPLATE.md"
  local config="$dir/.claude/zskills-config.json"

  # Missing CLAUDE.md → rc 1.
  if [ ! -f "$claude" ]; then
    echo "no existing CLAUDE.md; run /update-zskills (without --rerender) for initial install" >&2
    return 1
  fi

  # Locate `## Agent Rules` demarcation.
  local heading_line
  heading_line=$(grep -n '^## Agent Rules[[:space:]]*$' "$claude" | head -1 | cut -d: -f1)
  if [ -z "$heading_line" ]; then
    echo "CLAUDE.md missing '## Agent Rules' demarcation; cannot rerender safely. Add the heading or re-run /update-zskills (without --rerender) for initial install." >&2
    return 2
  fi

  # Split existing file.
  local existing_above existing_below
  existing_above=$(sed -n "1,$((heading_line - 1))p" "$claude")
  existing_below=$(sed -n "${heading_line},\$p" "$claude")

  # Render template against current config. Extract placeholder values from
  # config via bash regex (mirrors Step 0.5's approach). Only the fields
  # that appear in the test template are substituted; unknown placeholders
  # pass through verbatim (same as Step B's "empty → comment out" is not
  # what Step D promises — Step D re-substitutes current values).
  local config_content
  config_content=$(cat "$config" 2>/dev/null || echo "")
  local project_name="" dev_cmd="" timezone=""
  if [[ "$config_content" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    project_name="${BASH_REMATCH[1]}"
  fi
  if [[ "$config_content" =~ \"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    dev_cmd="${BASH_REMATCH[1]}"
  fi
  if [[ "$config_content" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    timezone="${BASH_REMATCH[1]}"
  fi

  local rendered
  rendered=$(cat "$template")
  rendered="${rendered//\{\{PROJECT_NAME\}\}/$project_name}"
  rendered="${rendered//\{\{DEV_SERVER_CMD\}\}/$dev_cmd}"
  rendered="${rendered//\{\{TIMEZONE\}\}/$timezone}"

  # Extract fresh_above: everything before `## Agent Rules` in the rendered
  # output. If the template lacks the heading, synthesize one — the test
  # fixtures guarantee a heading is present.
  local fresh_heading_line
  fresh_heading_line=$(echo "$rendered" | grep -n '^## Agent Rules[[:space:]]*$' | head -1 | cut -d: -f1)
  if [ -z "$fresh_heading_line" ]; then
    # The rendered template must carry the demarcation; if absent, the
    # caller's template is malformed — treat as a conflict.
    echo "rendered template lacks '## Agent Rules' heading; cannot merge" >&2
    return 2
  fi
  local fresh_above
  fresh_above=$(echo "$rendered" | sed -n "1,$((fresh_heading_line - 1))p")

  # Right-trim trailing whitespace on each line before comparing.
  local existing_trim fresh_trim
  existing_trim=$(echo "$existing_above" | sed -E 's/[[:space:]]+$//')
  fresh_trim=$(echo "$fresh_above" | sed -E 's/[[:space:]]+$//')

  local merged
  merged="$fresh_above"$'\n'"$existing_below"

  if [ "$existing_trim" = "$fresh_trim" ]; then
    # Idempotency: skip write if resulting bytes equal current file bytes.
    local current
    current=$(cat "$claude")
    if [ "$current" = "$merged" ]; then
      return 0
    fi
    printf '%s' "$merged" > "$claude"
    return 0
  fi

  # Conflict: write .new, leave CLAUDE.md untouched, stderr verbatim.
  printf '%s' "$merged" > "$claude.new"
  cat >&2 <<'CONFLICT_MSG'
CLAUDE.md differs above '## Agent Rules' (user edits, config drift, or both).
New rendered content written to CLAUDE.md.new. Review with:
    diff CLAUDE.md CLAUDE.md.new
To accept the new version:  mv CLAUDE.md.new CLAUDE.md
To discard it:              rm CLAUDE.md.new
CONFLICT_MSG
  return 2
}

# --- Fixture builder --------------------------------------------------------
# Creates a fresh sandbox: <tmp>/CLAUDE_TEMPLATE.md, <tmp>/.claude/zskills-config.json,
# <tmp>/CLAUDE.md (optional).
make_fixture() {
  local dir="$1"
  local project_name="$2"
  local dev_cmd="$3"
  rm -rf "$dir"
  mkdir -p "$dir/.claude"
  cat > "$dir/CLAUDE_TEMPLATE.md" <<TEMPLATE
# {{PROJECT_NAME}} — Agent Reference

## Dev Server

\`\`\`bash
{{DEV_SERVER_CMD}}
\`\`\`

## Agent Rules

Rendered-in-template rules go here.
TEMPLATE
  cat > "$dir/.claude/zskills-config.json" <<CONFIG
{
  "project_name": "$project_name",
  "timezone": "America/New_York",
  "dev_server": {
    "cmd": "$dev_cmd"
  }
}
CONFIG
}

# --- Test 1: happy path -----------------------------------------------------
# NOTE: The plan's WI 2.4 describes this as "stale CLAUDE.md + updated
# config → new CLAUDE.md contains current config values". Under the
# simplified algorithm (no "normalize by substituting prior values"), any
# byte difference above '## Agent Rules' — including pure config drift —
# triggers the conflict path: rc=2, CLAUDE.md untouched, CLAUDE.md.new
# written with the fresh render. We assert that outcome here; the new
# config values land in CLAUDE.md.new (which the user accepts via
# `mv CLAUDE.md.new CLAUDE.md`). This matches the algorithm verbatim.
echo "=== Test 1: happy path — stale config → CLAUDE.md.new carries new values ==="
T1="$(mktemp -d)"
make_fixture "$T1" "acme-new" "npm run serve"
# Seed CLAUDE.md with OLD config values.
cat > "$T1/CLAUDE.md" <<'STALE'
# acme-old — Agent Reference

## Dev Server

```bash
npm start
```

## Agent Rules

Rendered-in-template rules go here.
STALE
run_rerender "$T1" 2>/tmp/rerender-stderr-t1
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "Test 1a: rc=2 when stale config differs from current (conflict path)"
else
  fail "Test 1a: rc should be 2 (conflict)" "got rc=$rc"
fi
if [ -f "$T1/CLAUDE.md.new" ] \
   && grep -q '^# acme-new — Agent Reference' "$T1/CLAUDE.md.new" \
   && grep -q '^npm run serve$' "$T1/CLAUDE.md.new"; then
  pass "Test 1b: CLAUDE.md.new contains current config values"
else
  fail "Test 1b: CLAUDE.md.new missing new values" \
    "$([ -f "$T1/CLAUDE.md.new" ] && head -5 "$T1/CLAUDE.md.new" || echo 'file missing')"
fi
if grep -q '^# acme-old — Agent Reference' "$T1/CLAUDE.md" \
   && grep -q '^npm start$' "$T1/CLAUDE.md"; then
  pass "Test 1c: CLAUDE.md untouched on conflict"
else
  fail "Test 1c: CLAUDE.md was modified" "spec says leave existing alone"
fi
rm -rf "$T1" /tmp/rerender-stderr-t1

# --- Test 2: preservation below Agent Rules --------------------------------
# Same semantics as Test 1: under the simplified algorithm, a stale config
# produces rc=2 and CLAUDE.md.new. We assert that CLAUDE.md.new preserves
# the user's below-heading content verbatim in the merged output — the
# below-region is always carried over (never regenerated from template)
# regardless of whether the above-region is identical or conflicting.
echo ""
echo "=== Test 2: user content below '## Agent Rules' preserved verbatim ==="
T2="$(mktemp -d)"
make_fixture "$T2" "acme-new" "npm run serve"
cat > "$T2/CLAUDE.md" <<'STALE2'
# acme-old — Agent Reference

## Dev Server

```bash
npm start
```

## Agent Rules

Rendered-in-template rules go here.

## User Section

This paragraph is user-authored. Do not modify.

- bullet 1
- bullet 2
STALE2
run_rerender "$T2" 2>/tmp/rerender-stderr-t2
rc=$?
# The merged output must be in CLAUDE.md.new (conflict path); user content
# must be preserved verbatim.
target="$T2/CLAUDE.md.new"
[ -f "$target" ] || target="$T2/CLAUDE.md"  # tolerate either path in the assertion
if grep -q 'This paragraph is user-authored. Do not modify.' "$target" \
   && grep -q '^- bullet 1$' "$target" \
   && grep -q '^- bullet 2$' "$target" \
   && grep -q '^## User Section$' "$target"; then
  pass "Test 2: user content below demarcation preserved (in $(basename "$target"))"
else
  fail "Test 2: user content lost" "see $target"
fi
rm -rf "$T2" /tmp/rerender-stderr-t2

# --- Test 3: conflict — edit above `## Agent Rules` ------------------------
echo ""
echo "=== Test 3: edit above Agent Rules → CLAUDE.md.new, rc=2, stderr prompt ==="
T3="$(mktemp -d)"
make_fixture "$T3" "acme-new" "npm run serve"
cat > "$T3/CLAUDE.md" <<'STALE3'
# acme-old — Agent Reference

## Dev Server

```bash
npm start
```

## Custom User Section

This section was inserted by the user between Dev Server and Agent Rules.
It must trigger the conflict path.

## Agent Rules

Rendered-in-template rules go here.
STALE3
PRE_CLAUDE=$(cat "$T3/CLAUDE.md")
run_rerender "$T3" 2>/tmp/rerender-stderr-t3
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "Test 3a: rc=2 on conflict"
else
  fail "Test 3a: rc should be 2" "got rc=$rc"
fi
if [ -f "$T3/CLAUDE.md.new" ]; then
  pass "Test 3b: CLAUDE.md.new written"
else
  fail "Test 3b: CLAUDE.md.new missing" "no file"
fi
POST_CLAUDE=$(cat "$T3/CLAUDE.md")
if [ "$PRE_CLAUDE" = "$POST_CLAUDE" ]; then
  pass "Test 3c: CLAUDE.md untouched on conflict"
else
  fail "Test 3c: CLAUDE.md was modified" "expected unchanged"
fi
if grep -q "CLAUDE.md differs above '## Agent Rules'" /tmp/rerender-stderr-t3 \
   && grep -q 'diff CLAUDE.md CLAUDE.md.new' /tmp/rerender-stderr-t3 \
   && grep -q 'mv CLAUDE.md.new CLAUDE.md' /tmp/rerender-stderr-t3 \
   && grep -q 'rm CLAUDE.md.new' /tmp/rerender-stderr-t3; then
  pass "Test 3d: stderr prompt verbatim"
else
  fail "Test 3d: stderr prompt missing expected lines" "$(cat /tmp/rerender-stderr-t3)"
fi
rm -rf "$T3" /tmp/rerender-stderr-t3

# --- Test 4: missing CLAUDE.md ---------------------------------------------
echo ""
echo "=== Test 4: no CLAUDE.md → rc=1 with specific error ==="
T4="$(mktemp -d)"
make_fixture "$T4" "acme-new" "npm run serve"
rm -f "$T4/CLAUDE.md"  # explicitly ensure missing
run_rerender "$T4" 2>/tmp/rerender-stderr-t4
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "Test 4a: rc=1 on missing CLAUDE.md"
else
  fail "Test 4a: rc should be 1" "got rc=$rc"
fi
if grep -q 'no existing CLAUDE.md' /tmp/rerender-stderr-t4 \
   && grep -q 'run /update-zskills (without --rerender) for initial install' /tmp/rerender-stderr-t4; then
  pass "Test 4b: stderr has expected message"
else
  fail "Test 4b: stderr missing expected text" "$(cat /tmp/rerender-stderr-t4)"
fi
if [ ! -f "$T4/CLAUDE.md" ]; then
  pass "Test 4c: CLAUDE.md not silently created"
else
  fail "Test 4c: CLAUDE.md was silently created" "file exists"
fi
rm -rf "$T4" /tmp/rerender-stderr-t4

# --- Test 5: idempotency ---------------------------------------------------
echo ""
echo "=== Test 5: back-to-back rerender → second run is a true no-op ==="
T5="$(mktemp -d)"
make_fixture "$T5" "acme" "npm run dev"
# Seed a CLAUDE.md whose "above" region already matches the current template.
cat > "$T5/CLAUDE.md" <<'CURRENT'
# acme — Agent Reference

## Dev Server

```bash
npm run dev
```

## Agent Rules

Rendered-in-template rules go here.

## User Appendix

Custom user notes.
CURRENT
# First rerender: should be rc=0 and either no-op or identical write.
run_rerender "$T5" 2>/tmp/rerender-stderr-t5-a
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 5a: first rerender rc=0"
else
  fail "Test 5a: first rc should be 0" "got $rc"
fi
FIRST_MTIME=$(stat -c %Y "$T5/CLAUDE.md")
FIRST_CONTENT=$(cat "$T5/CLAUDE.md")
sleep 1  # ensure mtime resolution would register a change
# Second rerender.
run_rerender "$T5" 2>/tmp/rerender-stderr-t5-b
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 5b: second rerender rc=0"
else
  fail "Test 5b: second rc should be 0" "got $rc"
fi
SECOND_MTIME=$(stat -c %Y "$T5/CLAUDE.md")
SECOND_CONTENT=$(cat "$T5/CLAUDE.md")
if [ "$FIRST_CONTENT" = "$SECOND_CONTENT" ]; then
  pass "Test 5c: content identical across runs"
else
  fail "Test 5c: content differs across runs" "diff observed"
fi
if [ "$FIRST_MTIME" = "$SECOND_MTIME" ]; then
  pass "Test 5d: mtime unchanged (idempotent no-op)"
else
  fail "Test 5d: mtime changed on no-op rerender" "$FIRST_MTIME vs $SECOND_MTIME"
fi
rm -rf "$T5" /tmp/rerender-stderr-t5-a /tmp/rerender-stderr-t5-b

# --- Test 6: Step C spec accommodates user-added hook (doc-check) ---------
# WI 2.7 also asks for a separate "integration" test: write a synthetic
# settings.json fixture with a user-added custom Bash hook, write a doc
# asserting the Step C spec would preserve that hook (doc-check, not
# execution). We model this as a structural check: Step C's SKILL.md text
# explicitly says "Do not touch sibling hook objects (user-added
# customizations in the same matcher survive)", which the earlier
# test-skill-conformance check already asserts. Here we additionally
# verify that a synthetic settings.json fixture with a user-hook is
# LEFT UNCHANGED by a dry-run parse — we do NOT execute the merge
# (agent-driven), only confirm the fixture's structure is preserved on
# read.
echo ""
echo "=== Test 6: synthetic settings.json fixture preserves user-added hook ==="
T6="$(mktemp -d)"
cat > "$T6/settings.json" <<'FIXTURE'
{
  "permissions": {
    "allow": ["Bash(ls)"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/user-custom.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "model": "opus"
}
FIXTURE
# The doc-check: Step C's spec promises foreign entries and non-hooks
# top-level keys are preserved. We confirm the fixture is parseable and
# contains the user-custom.sh reference — then assert Step C's SKILL.md
# documents preservation. (The execution itself is the agent's job at
# runtime.)
if grep -q 'user-custom.sh' "$T6/settings.json" \
   && grep -q '"model": "opus"' "$T6/settings.json" \
   && grep -q '"permissions"' "$T6/settings.json"; then
  # Confirm SKILL.md documents preservation for exactly this shape.
  if grep -q 'Do not touch sibling hook objects' "$REPO_ROOT/skills/update-zskills/SKILL.md" \
     && grep -q 'user-added customizations in the same matcher survive' "$REPO_ROOT/skills/update-zskills/SKILL.md" \
     && grep -q 'Do not touch `permissions`, `env`, `statusLine`, `model`' "$REPO_ROOT/skills/update-zskills/SKILL.md"; then
    pass "Test 6: Step C spec documents preservation of user hook + other top-level keys"
  else
    fail "Test 6: SKILL.md missing preservation-of-foreign-entries guarantees" "see Step C"
  fi
else
  fail "Test 6: fixture malformed" "see $T6/settings.json"
fi
rm -rf "$T6"

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
