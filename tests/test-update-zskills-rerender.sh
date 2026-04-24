#!/bin/bash
# Integration test for /update-zskills Step B (render) + Step D (--rerender)
# and the root-CLAUDE.md migration sub-step (DRIFT_ARCH_FIX Phase 4).
#
# /update-zskills is an agent-executed command. We cannot literally invoke
# the skill from a shell test. Instead, we encode the algorithm documented
# in `skills/update-zskills/SKILL.md` "Step B" (render + migration) and
# "Step D — --rerender" as bash functions below, and run them against
# fixture directories. The functions are executable oracles — if SKILL.md's
# spec changes meaning, the oracles must be updated in lockstep.
#
# Coverage (matches WI 4.6 exactly):
#   1. Fresh install:       .claude/rules/zskills/managed.md created,
#                           contains current-config values; root CLAUDE.md
#                           absent or untouched.
#   2. --rerender after     managed.md reflects new values; no .new file;
#      config edit:         rc=0.
#   3. Migration happy:     fixture with zskills-rendered content in root
#                           CLAUDE.md → lines removed, backup at
#                           ./CLAUDE.md.pre-zskills-migration, managed.md
#                           has fresh values, stderr NOTICE emitted.
#   4. Migration no-op:     fixture with user-only root CLAUDE.md (no
#                           zskills lines) → untouched, no backup.
#   5. Migration idempotent: run install twice; backup exists only once,
#                           root CLAUDE.md unchanged on second run.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# --- Oracle: render template against config ---------------------------------
# Args: $1 = template content, $2..$N = KEY=VALUE pairs (placeholder substitutions).
# Prints the rendered content to stdout.
render_template() {
  local out="$1"; shift
  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    out="${out//\{\{${key}\}\}/$val}"
  done
  printf '%s' "$out"
}

# --- Oracle: Step B (render + migration) ------------------------------------
# Args: $1 = working directory containing CLAUDE_TEMPLATE.md and
#             .claude/zskills-config.json.
# Writes .claude/rules/zskills/managed.md. Performs root-CLAUDE.md migration.
# Prints stderr NOTICE on migration with non-zero candidates.
# Returns 0 always (on success). 1 if template missing.
run_step_b() {
  local dir="$1"
  local template="$dir/CLAUDE_TEMPLATE.md"
  local config="$dir/.claude/zskills-config.json"
  local rules_dir="$dir/.claude/rules/zskills"
  local rules_file="$rules_dir/managed.md"

  if [ ! -f "$template" ]; then
    echo "CLAUDE_TEMPLATE.md missing or unreadable; cannot render" >&2
    return 1
  fi

  # Extract simple placeholder values from config (bash regex; same idiom as
  # Step 0.5 of SKILL.md). Only the three fields the test fixtures use are
  # substituted.
  local config_content project_name dev_cmd timezone
  config_content=$(cat "$config" 2>/dev/null || echo "")
  project_name=""; dev_cmd=""; timezone=""
  if [[ "$config_content" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    project_name="${BASH_REMATCH[1]}"
  fi
  if [[ "$config_content" =~ \"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    dev_cmd="${BASH_REMATCH[1]}"
  fi
  if [[ "$config_content" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    timezone="${BASH_REMATCH[1]}"
  fi

  local template_content rendered
  template_content=$(cat "$template")
  rendered=$(render_template "$template_content" \
    "PROJECT_NAME=$project_name" \
    "DEV_SERVER_CMD=$dev_cmd" \
    "TIMEZONE=$timezone")

  # Write rules file (full overwrite).
  mkdir -p "$rules_dir"
  printf '%s' "$rendered" > "$rules_file"

  # Migration sub-step: if root ./CLAUDE.md exists, detect zskills-rendered
  # lines and remove them with ±2-line context match.
  local root_claude="$dir/CLAUDE.md"
  if [ ! -f "$root_claude" ]; then
    return 0
  fi

  local backup="$dir/CLAUDE.md.pre-zskills-migration"

  # Build the set of (value, template-line-number, template ±2 context) tuples.
  # For each non-empty placeholder value V, find template lines containing V
  # and record the context signature (5-line window, trailing-ws-trimmed).
  local tmp_candidates
  tmp_candidates=$(mktemp)

  # We'll use awk to scan the rendered template and produce context signatures.
  # Values we look for (non-empty only).
  local -a values=()
  [ -n "$project_name" ] && values+=("$project_name")
  [ -n "$dev_cmd" ]      && values+=("$dev_cmd")
  [ -n "$timezone" ]     && values+=("$timezone")

  if [ "${#values[@]}" -eq 0 ]; then
    rm -f "$tmp_candidates"
    return 0
  fi

  # Write the rendered template to a temp file so we can index it by line.
  local tmp_rendered
  tmp_rendered=$(mktemp)
  printf '%s' "$rendered" > "$tmp_rendered"

  # right-trim utility (bash):
  rtrim() { local s="$1"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

  # Read the root CLAUDE.md into an array (preserve trailing-newline behaviour
  # by using mapfile).
  local -a root_lines=() tmpl_lines=()
  mapfile -t root_lines < "$root_claude"
  mapfile -t tmpl_lines < "$tmp_rendered"

  # For each value V, for each template line i that contains V, build the
  # template ±2 signature and scan the root for a matching root line j
  # containing V whose ±2 signature matches.
  local i j v n_root n_tmpl
  n_root=${#root_lines[@]}
  n_tmpl=${#tmpl_lines[@]}
  local -A remove_root=()  # keys: root line indices to remove

  # Compute the trimmed 5-line signature at given index into a given array.
  # Args: $1 = "root"|"tmpl", $2 = center index, $3 = array length.
  # Echoes signature joined by \x1f.
  signature() {
    local arr="$1" idx="$2" n="$3"
    local k line
    local sig=""
    for k in $((idx - 2)) $((idx - 1)) "$idx" $((idx + 1)) $((idx + 2)); do
      if [ "$k" -lt 0 ] || [ "$k" -ge "$n" ]; then
        sig+=$'\x1e'  # sentinel: out-of-bounds
      else
        if [ "$arr" = "root" ]; then line="${root_lines[$k]}"; else line="${tmpl_lines[$k]}"; fi
        sig+=$(rtrim "$line")
      fi
      sig+=$'\x1f'
    done
    printf '%s' "$sig"
  }

  for v in "${values[@]}"; do
    # Find template line indices containing v.
    local -a tmpl_hits=()
    for ((i = 0; i < n_tmpl; i++)); do
      if [[ "${tmpl_lines[$i]}" == *"$v"* ]]; then
        tmpl_hits+=("$i")
      fi
    done
    [ "${#tmpl_hits[@]}" -eq 0 ] && continue
    # For each tmpl hit, compute its signature.
    local -a tmpl_sigs=()
    for i in "${tmpl_hits[@]}"; do
      tmpl_sigs+=("$(signature tmpl "$i" "$n_tmpl")")
    done
    # Scan root for lines containing v; compute signature; compare to any tmpl_sig.
    for ((j = 0; j < n_root; j++)); do
      [ -n "${remove_root[$j]:-}" ] && continue
      if [[ "${root_lines[$j]}" == *"$v"* ]]; then
        local root_sig
        root_sig=$(signature root "$j" "$n_root")
        local ts
        for ts in "${tmpl_sigs[@]}"; do
          if [ "$root_sig" = "$ts" ]; then
            remove_root[$j]=1
            break
          fi
        done
      fi
    done
  done

  rm -f "$tmp_candidates" "$tmp_rendered"

  # If no candidates, no-op (no backup, no notice).
  if [ "${#remove_root[@]}" -eq 0 ]; then
    return 0
  fi

  # Backup root CLAUDE.md only if the backup doesn't already exist.
  if [ ! -e "$backup" ]; then
    cp "$root_claude" "$backup"
  fi

  # Rewrite root CLAUDE.md, dropping the removed lines.
  local new_root
  new_root=$(mktemp)
  for ((i = 0; i < n_root; i++)); do
    if [ -z "${remove_root[$i]:-}" ]; then
      printf '%s\n' "${root_lines[$i]}" >> "$new_root"
    fi
  done
  # Preserve behaviour: if the original file ended without a trailing newline
  # and we wrote nothing, leave an empty file. mapfile + printf \n inherently
  # produces trailing newline per line kept.
  mv "$new_root" "$root_claude"

  cat >&2 <<'NOTICE'
NOTICE: Migrated zskills content from root ./CLAUDE.md to .claude/rules/zskills/managed.md.
Backup: ./CLAUDE.md.pre-zskills-migration.
If your Claude Code settings exclude .claude/** from context (e.g. claudeMdExcludes),
the new rules file will not auto-load — adjust your excludes or @-import it from root CLAUDE.md.
NOTICE

  return 0
}

# --- Oracle: Step D (--rerender) --------------------------------------------
# Args: $1 = working directory.
# Full-file rewrite of .claude/rules/zskills/managed.md against current config.
# Exit codes: 0 on success, 1 if template missing.
run_rerender() {
  local dir="$1"
  local template="$dir/CLAUDE_TEMPLATE.md"
  local config="$dir/.claude/zskills-config.json"
  local rules_dir="$dir/.claude/rules/zskills"
  local rules_file="$rules_dir/managed.md"

  if [ ! -f "$template" ]; then
    echo "CLAUDE_TEMPLATE.md missing or unreadable; cannot rerender" >&2
    return 1
  fi

  local config_content project_name dev_cmd timezone
  config_content=$(cat "$config" 2>/dev/null || echo "")
  project_name=""; dev_cmd=""; timezone=""
  if [[ "$config_content" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    project_name="${BASH_REMATCH[1]}"
  fi
  if [[ "$config_content" =~ \"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    dev_cmd="${BASH_REMATCH[1]}"
  fi
  if [[ "$config_content" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    timezone="${BASH_REMATCH[1]}"
  fi

  local template_content rendered
  template_content=$(cat "$template")
  rendered=$(render_template "$template_content" \
    "PROJECT_NAME=$project_name" \
    "DEV_SERVER_CMD=$dev_cmd" \
    "TIMEZONE=$timezone")

  mkdir -p "$rules_dir"
  printf '%s' "$rendered" > "$rules_file"
  return 0
}

# --- Fixture builder --------------------------------------------------------
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

Generic rules rendered by zskills.
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

# --- Test 1: fresh install --------------------------------------------------
echo "=== Test 1: fresh install — managed.md rendered, root CLAUDE.md untouched ==="
T1="$(mktemp -d)"
make_fixture "$T1" "acme" "npm start"
# No root CLAUDE.md on a fresh project.
run_step_b "$T1" 2>/tmp/rerender-stderr-t1
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 1a: rc=0 on fresh install"
else
  fail "Test 1a: rc should be 0" "got rc=$rc"
fi
if [ -f "$T1/.claude/rules/zskills/managed.md" ] \
   && grep -q '^# acme — Agent Reference' "$T1/.claude/rules/zskills/managed.md" \
   && grep -q '^npm start$' "$T1/.claude/rules/zskills/managed.md"; then
  pass "Test 1b: managed.md contains rendered values"
else
  fail "Test 1b: managed.md missing or malformed" \
    "$([ -f "$T1/.claude/rules/zskills/managed.md" ] && head -3 "$T1/.claude/rules/zskills/managed.md" || echo 'file missing')"
fi
if [ ! -f "$T1/CLAUDE.md" ]; then
  pass "Test 1c: root CLAUDE.md absent (never created)"
else
  fail "Test 1c: root CLAUDE.md was silently created" "file exists"
fi
rm -rf "$T1" /tmp/rerender-stderr-t1

# --- Test 2: --rerender after config edit -----------------------------------
echo ""
echo "=== Test 2: --rerender after config edit — managed.md reflects new values, rc=0 ==="
T2="$(mktemp -d)"
make_fixture "$T2" "acme-old" "npm start"
run_step_b "$T2" 2>/tmp/rerender-stderr-t2-a
# Simulate a config edit: rewrite config with new values.
cat > "$T2/.claude/zskills-config.json" <<CONFIG
{
  "project_name": "acme-new",
  "timezone": "America/New_York",
  "dev_server": {
    "cmd": "npm run serve"
  }
}
CONFIG
run_rerender "$T2" 2>/tmp/rerender-stderr-t2-b
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 2a: rc=0 on --rerender"
else
  fail "Test 2a: rc should be 0" "got rc=$rc"
fi
if grep -q '^# acme-new — Agent Reference' "$T2/.claude/rules/zskills/managed.md" \
   && grep -q '^npm run serve$' "$T2/.claude/rules/zskills/managed.md"; then
  pass "Test 2b: managed.md contains new config values"
else
  fail "Test 2b: managed.md not rerendered" "$(head -3 "$T2/.claude/rules/zskills/managed.md")"
fi
if [ ! -f "$T2/.claude/rules/zskills/managed.md.new" ]; then
  pass "Test 2c: no .new file created (byte-compare gone)"
else
  fail "Test 2c: unexpected .new file" "managed.md.new exists"
fi
rm -rf "$T2" /tmp/rerender-stderr-t2-a /tmp/rerender-stderr-t2-b

# --- Test 3: migration happy path -------------------------------------------
echo ""
echo "=== Test 3: migration happy path — zskills lines removed, backup created ==="
T3="$(mktemp -d)"
make_fixture "$T3" "acme" "npm start"
# Seed root CLAUDE.md with zskills-rendered content AND user content.
cat > "$T3/CLAUDE.md" <<'ROOT'
# acme — Agent Reference

## Dev Server

```bash
npm start
```

## Agent Rules

Generic rules rendered by zskills.

## My Personal Notes

I remember we used to have `npm start` but now we use something different.
Other personal notes go here.
ROOT
run_step_b "$T3" 2>/tmp/rerender-stderr-t3
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 3a: rc=0 on migration"
else
  fail "Test 3a: rc should be 0" "got rc=$rc"
fi
if [ -f "$T3/CLAUDE.md.pre-zskills-migration" ]; then
  pass "Test 3b: backup created at ./CLAUDE.md.pre-zskills-migration"
else
  fail "Test 3b: backup missing" "no backup file"
fi
if grep -q 'NOTICE: Migrated zskills content' /tmp/rerender-stderr-t3 \
   && grep -q '.claude/rules/zskills/managed.md' /tmp/rerender-stderr-t3 \
   && grep -q '.pre-zskills-migration' /tmp/rerender-stderr-t3; then
  pass "Test 3c: stderr NOTICE emitted"
else
  fail "Test 3c: NOTICE missing or malformed" "$(cat /tmp/rerender-stderr-t3)"
fi
# The template line `# acme — Agent Reference` (line 1 of root) should match
# (it occurs at line 1 of the rendered template too). Same for the dev-cmd
# block. The "I remember we used to have `npm start`" line is in a different
# context (no matching ±2 signature) and must be preserved.
if ! grep -q '^# acme — Agent Reference' "$T3/CLAUDE.md" \
   && grep -q 'I remember we used to have' "$T3/CLAUDE.md" \
   && grep -q '^## My Personal Notes' "$T3/CLAUDE.md"; then
  pass "Test 3d: zskills lines removed, user content + prose-mention preserved"
else
  fail "Test 3d: migration removed wrong lines or preserved too much" "$(cat "$T3/CLAUDE.md")"
fi
if [ -f "$T3/.claude/rules/zskills/managed.md" ] \
   && grep -q '^# acme — Agent Reference' "$T3/.claude/rules/zskills/managed.md"; then
  pass "Test 3e: managed.md rendered with fresh values"
else
  fail "Test 3e: managed.md missing" "file missing or malformed"
fi
rm -rf "$T3" /tmp/rerender-stderr-t3

# --- Test 4: migration no-op ------------------------------------------------
echo ""
echo "=== Test 4: migration no-op — user-only CLAUDE.md untouched, no backup ==="
T4="$(mktemp -d)"
make_fixture "$T4" "acme" "npm start"
cat > "$T4/CLAUDE.md" <<'USER_ONLY'
# My Project Notes

This is entirely my own content. I never used zskills rendering here.

- Some bullet
- Another bullet

## Random heading

Some paragraph.
USER_ONLY
PRE=$(cat "$T4/CLAUDE.md")
run_step_b "$T4" 2>/tmp/rerender-stderr-t4
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 4a: rc=0 on no-op migration"
else
  fail "Test 4a: rc should be 0" "got rc=$rc"
fi
POST=$(cat "$T4/CLAUDE.md")
if [ "$PRE" = "$POST" ]; then
  pass "Test 4b: root CLAUDE.md untouched (byte-identical)"
else
  fail "Test 4b: root CLAUDE.md was modified" "diff observed"
fi
if [ ! -e "$T4/CLAUDE.md.pre-zskills-migration" ]; then
  pass "Test 4c: no backup created (nothing to migrate)"
else
  fail "Test 4c: unexpected backup" "backup file exists"
fi
if ! grep -q 'NOTICE: Migrated zskills content' /tmp/rerender-stderr-t4; then
  pass "Test 4d: no NOTICE emitted"
else
  fail "Test 4d: unexpected NOTICE" "$(cat /tmp/rerender-stderr-t4)"
fi
rm -rf "$T4" /tmp/rerender-stderr-t4

# --- Test 5: migration idempotency ------------------------------------------
echo ""
echo "=== Test 5: migration idempotent — second run no-ops, backup not duplicated ==="
T5="$(mktemp -d)"
make_fixture "$T5" "acme" "npm start"
cat > "$T5/CLAUDE.md" <<'ROOT2'
# acme — Agent Reference

## Dev Server

```bash
npm start
```

## Agent Rules

Generic rules rendered by zskills.

## User Appendix

User's own content.
ROOT2
# First run: performs migration.
run_step_b "$T5" 2>/tmp/rerender-stderr-t5-a
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 5a: first run rc=0"
else
  fail "Test 5a: first rc should be 0" "got rc=$rc"
fi
if [ -f "$T5/CLAUDE.md.pre-zskills-migration" ]; then
  pass "Test 5b: backup exists after first run"
else
  fail "Test 5b: backup missing after first run" "no backup"
fi
POST_FIRST=$(cat "$T5/CLAUDE.md")
BACKUP_MTIME=$(stat -c %Y "$T5/CLAUDE.md.pre-zskills-migration")
sleep 1  # ensure any later write would have a different mtime
# Second run: should be a no-op.
run_step_b "$T5" 2>/tmp/rerender-stderr-t5-b
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "Test 5c: second run rc=0"
else
  fail "Test 5c: second rc should be 0" "got rc=$rc"
fi
POST_SECOND=$(cat "$T5/CLAUDE.md")
BACKUP_MTIME2=$(stat -c %Y "$T5/CLAUDE.md.pre-zskills-migration")
if [ "$POST_FIRST" = "$POST_SECOND" ]; then
  pass "Test 5d: root CLAUDE.md unchanged on second run"
else
  fail "Test 5d: root CLAUDE.md modified on second run" "diff observed"
fi
if [ "$BACKUP_MTIME" = "$BACKUP_MTIME2" ]; then
  pass "Test 5e: backup not overwritten (mtime stable)"
else
  fail "Test 5e: backup was overwritten" "$BACKUP_MTIME vs $BACKUP_MTIME2"
fi
if ! grep -q 'NOTICE: Migrated zskills content' /tmp/rerender-stderr-t5-b; then
  pass "Test 5f: no NOTICE on second run"
else
  fail "Test 5f: second run emitted NOTICE" "$(cat /tmp/rerender-stderr-t5-b)"
fi
rm -rf "$T5" /tmp/rerender-stderr-t5-a /tmp/rerender-stderr-t5-b

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
