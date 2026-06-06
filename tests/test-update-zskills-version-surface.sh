#!/bin/bash
# Phase 5b — Integration test for /update-zskills's three version-data
# UI surface sites (audit gap report, install final report, update final
# report) and the rerender-stays-silent contrast.
#
# /update-zskills is agent-executed. This test acts as an oracle: it
# encodes the SKILL.md algorithm for each of the three sites in bash,
# exercises it against fixture state, and asserts the rendered output
# matches the documented format. It also asserts textual structure
# directly on SKILL.md (heading anchors, required keywords) so a
# refactor that drops the version surface fails this test.
#
# Coverage:
#   1. Site A — audit gap report renders `Versions: zskills <inst>→<cur>; <N> skills changed`
#   2. Site A — pre-Phase-5 install (no zskills_version field) renders `(none)`
#   3. Site A — source clone with no tags renders `(unversioned)` placeholder
#   4. Site B — install final report renders `Repo version:` + Per-skill versions list
#   5. Site C — update final report renders structured table:
#                Repo version: <old> → <new>
#                Updated: N skills
#                  <name>  <old> → <new>
#                  <name>  <ver> (unchanged)
#                New: M items installed
#   6. Site C — addon rows hidden by default, shown with --with-block-diagram-addons
#   7. CONTRAST — rerender output silent on `Repo version|metadata.version`
#   8. CONTRAST — managed.md silent on `Repo version|metadata.version`
#   9. SKILL.md textual invariants (anchors + keywords for all 3 sites)
#  10. Step F.5 / Pull Latest 5.7 mirror-the-tag-into-config step exists
#
# Run from repo root: bash tests/test-update-zskills-version-surface.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$REPO_ROOT/skills/update-zskills/SKILL.md"
DELTA="$REPO_ROOT/skills/update-zskills/scripts/skill-version-delta.sh"
RESOLVE="$REPO_ROOT/skills/update-zskills/scripts/resolve-repo-version.sh"
JSON_SET="$REPO_ROOT/skills/update-zskills/scripts/json-set-string-field.sh"
GET_HELPER="$REPO_ROOT/scripts/frontmatter-get.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Pre-flight: helpers exist.
for f in "$SKILL_MD" "$DELTA" "$RESOLVE" "$JSON_SET" "$GET_HELPER"; do
  if [ ! -f "$f" ]; then
    fail "pre-flight: $f exists" "missing"
  fi
done
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf 'Results: %d passed, %d failed (of %d)\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit 1
fi

# ----------------------------------------------------------------------
# Oracle: read installed `zskills_version` from .claude/zskills-config.json
# via inline BASH_REMATCH (the pattern Site A documents).
# ----------------------------------------------------------------------
read_installed_zskills_ver() {
  local cfg="$1"
  [ -f "$cfg" ] || { echo ""; return 0; }
  local body
  body=$(cat "$cfg")
  if [[ "$body" =~ \"zskills_version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# ----------------------------------------------------------------------
# Oracle: render Site A's `Versions:` line. Mirrors the SKILL.md spec.
# ----------------------------------------------------------------------
render_site_a_line() {
  local zskills_path="$1" claude_dir="$2"
  local current installed n_changed delta_tsv
  current=$(bash "$RESOLVE" "$zskills_path")
  installed=$(read_installed_zskills_ver "$claude_dir/.claude/zskills-config.json")
  delta_tsv=$(CLAUDE_PROJECT_DIR="$claude_dir" bash "$DELTA" "$zskills_path")
  n_changed=$(printf '%s\n' "$delta_tsv" | awk -F'\t' '$5 == "bumped" || $5 == "new"' | wc -l)
  [ -z "$current" ]   && current="(unversioned) — source clone has no tags"
  [ -z "$installed" ] && installed="(none)"
  echo "Repo version: ${installed} → ${current}"
  echo "Versions: zskills ${installed}→${current}; ${n_changed} skills changed"
}

# ----------------------------------------------------------------------
# Oracle: render Site B's per-skill versions block (install final report).
# Every row shows `<name>  <metadata.version>  (new)` for fresh install.
# Optionally include addon rows.
# ----------------------------------------------------------------------
render_site_b_block() {
  local zskills_path="$1" claude_dir="$2" show_addons="${3:-0}"
  local delta_tsv
  delta_tsv=$(CLAUDE_PROJECT_DIR="$claude_dir" bash "$DELTA" "$zskills_path")
  printf '%s\n' "$delta_tsv" | awk -F'\t' -v show_addons="$show_addons" '
    $2 == "addon" && show_addons == 0 { next }
    { printf "  %-20s %s  (%s)\n", $1, $3, $5 }
  '
}

# ----------------------------------------------------------------------
# Oracle: render Site C's table (update final report).
# Updated rows (bumped: old → new), unchanged rows (ver), New rows.
# ----------------------------------------------------------------------
render_site_c_table() {
  local zskills_path="$1" claude_dir="$2" show_addons="${3:-0}"
  local delta_tsv old_ver new_ver
  delta_tsv=$(CLAUDE_PROJECT_DIR="$claude_dir" bash "$DELTA" "$zskills_path")
  old_ver=$(read_installed_zskills_ver "$claude_dir/.claude/zskills-config.json")
  [ -z "$old_ver" ] && old_ver="(unversioned)"
  new_ver=$(bash "$RESOLVE" "$zskills_path")
  [ -z "$new_ver" ] && new_ver="(unversioned)"

  echo "Z Skills updated."
  echo ""
  echo "Repo version: ${old_ver} → ${new_ver}"
  echo ""
  echo "Updated: skills"
  printf '%s\n' "$delta_tsv" | awk -F'\t' -v show_addons="$show_addons" '
    $2 == "addon" && show_addons == 0 { next }
    $5 == "bumped"   { printf "  %-20s %s → %s\n", $1, $4, $3 }
    $5 == "unchanged"{ printf "  %-20s %s (unchanged)\n", $1, $3 }
  '
  echo "New: items installed"
  printf '%s\n' "$delta_tsv" | awk -F'\t' -v show_addons="$show_addons" '
    $2 == "addon" && show_addons == 0 { next }
    $5 == "new" { printf "  %s\n", $1 }
  '
}

# ----------------------------------------------------------------------
# Fixture builder. Creates an isolated tree with:
#   $FIXT/source/                (zskills source clone, optionally git-init + tag)
#     skills/<name>/SKILL.md
#     block-diagram/<name>/SKILL.md
#     scripts/frontmatter-get.sh   (so DELTA helper finds it)
#   $FIXT/consumer/              (consumer project)
#     .claude/skills/<name>/SKILL.md
#     .claude/zskills-config.json
# ----------------------------------------------------------------------
write_skill() {
  local dir="$1" name="$2" ver="$3"
  mkdir -p "$dir"
  if [ -n "$ver" ]; then
    cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: synthetic
metadata:
  version: "$ver"
---
body
EOF
  else
    cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: synthetic
---
body
EOF
  fi
}

# ----------------------------------------------------------------------
# Test 1: Site A renders Versions line, populated case.
# ----------------------------------------------------------------------
echo "=== Test 1: Site A — audit gap report renders Versions: line (populated) ==="
T1=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
trap 'rm -rf /tmp/zskills-test-vsurf-*' EXIT

# Source clone with one tag.
mkdir -p "$T1/source/skills" "$T1/source/scripts" "$T1/source/block-diagram"
cp "$GET_HELPER" "$T1/source/scripts/frontmatter-get.sh"
chmod +x "$T1/source/scripts/frontmatter-get.sh"
write_skill "$T1/source/skills/run-plan" run-plan "2026.05.02+aaaaaa"
write_skill "$T1/source/skills/briefing" briefing "2026.05.02+bbbbbb"
write_skill "$T1/source/skills/commit"   commit   "2026.05.02+cccccc"
( cd "$T1/source" && git init -q && git config user.email t@e && git config user.name t \
  && git add -A && git commit -q -m init && git tag 2026.05.0 )

# Consumer with installed zskills_version + 2-of-3 skills installed at older versions.
mkdir -p "$T1/consumer/.claude/skills"
write_skill "$T1/consumer/.claude/skills/run-plan" run-plan "2026.04.20+999999"
write_skill "$T1/consumer/.claude/skills/briefing" briefing "2026.05.02+bbbbbb"
cat > "$T1/consumer/.claude/zskills-config.json" <<EOF
{
  "project_name": "acme",
  "zskills_version": "2026.04.0"
}
EOF

OUT=$(render_site_a_line "$T1/source" "$T1/consumer")
# Expect TWO lines:
#   Repo version: 2026.04.0 → 2026.05.0
#   Versions: zskills 2026.04.0→2026.05.0; 2 skills changed
# (run-plan = bumped, commit = new, briefing = unchanged → 2 changed)
if echo "$OUT" | grep -q '^Repo version: 2026\.04\.0 → 2026\.05\.0$'; then
  pass "Site A populated: 'Repo version:' line correct"
else
  fail "Site A populated: 'Repo version:'" "got: $OUT"
fi
if echo "$OUT" | grep -qE '^Versions: zskills 2026\.04\.0→2026\.05\.0; 2 skills changed$'; then
  pass "Site A populated: 'Versions:' line correct"
else
  fail "Site A populated: 'Versions:'" "got: $OUT"
fi

# ----------------------------------------------------------------------
# Test 2: Site A — pre-Phase-5 consumer (no zskills_version field) renders (none).
# ----------------------------------------------------------------------
echo ""
echo "=== Test 2: Site A — installed (none) when zskills_version absent ==="
T2=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
mkdir -p "$T2/source/skills" "$T2/source/scripts"
cp "$GET_HELPER" "$T2/source/scripts/frontmatter-get.sh"
write_skill "$T2/source/skills/run-plan" run-plan "2026.05.02+aaaaaa"
( cd "$T2/source" && git init -q && git config user.email t@e && git config user.name t \
  && git add -A && git commit -q -m init && git tag 2026.05.0 )
mkdir -p "$T2/consumer/.claude/skills"
cat > "$T2/consumer/.claude/zskills-config.json" <<'EOF'
{
  "project_name": "acme"
}
EOF
OUT=$(render_site_a_line "$T2/source" "$T2/consumer")
if echo "$OUT" | grep -q '(none) → 2026\.05\.0' && echo "$OUT" | grep -q '(none)→2026\.05\.0'; then
  pass "Site A (none) for missing zskills_version on both Repo version + Versions lines"
else
  fail "Site A (none)" "got: $OUT"
fi

# ----------------------------------------------------------------------
# Test 3: Site A — unversioned source clone (no tags).
# ----------------------------------------------------------------------
echo ""
echo "=== Test 3: Site A — source clone with no tags renders (unversioned) ==="
T3=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
mkdir -p "$T3/source/skills" "$T3/source/scripts"
cp "$GET_HELPER" "$T3/source/scripts/frontmatter-get.sh"
write_skill "$T3/source/skills/run-plan" run-plan "2026.05.02+aaaaaa"
( cd "$T3/source" && git init -q && git config user.email t@e && git config user.name t \
  && git add -A && git commit -q -m init )
# NO tag created.
mkdir -p "$T3/consumer/.claude/skills"
cat > "$T3/consumer/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme" }
EOF
OUT=$(render_site_a_line "$T3/source" "$T3/consumer")
if echo "$OUT" | grep -q '(unversioned)'; then
  pass "Site A (unversioned) for tagless source with NO plugin.json"
else
  fail "Site A (unversioned)" "got: $OUT"
fi

# ----------------------------------------------------------------------
# Test 3b (#1124): tagless source WITH a .claude-plugin/plugin.json →
# resolve-repo-version.sh falls back to the plugin.json version, so the
# Repo version is the plugin.json value, NOT (unversioned).
# ----------------------------------------------------------------------
echo ""
echo "=== Test 3b (#1124): tagless source WITH plugin.json → plugin.json version ==="
T3B=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
mkdir -p "$T3B/source/skills" "$T3B/source/scripts" "$T3B/source/.claude-plugin"
cp "$GET_HELPER" "$T3B/source/scripts/frontmatter-get.sh"
write_skill "$T3B/source/skills/run-plan" run-plan "2026.05.02+aaaaaa"
cat > "$T3B/source/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "zs",
  "displayName": "Z Skills",
  "version": "2026.06.0",
  "hooks": { "version": "nested-must-not-be-picked" }
}
EOF
( cd "$T3B/source" && git init -q && git config user.email t@e && git config user.name t \
  && git add -A && git commit -q -m init )
# NO tag created — exercise the plugin.json fallback path.
mkdir -p "$T3B/consumer/.claude/skills"
cat > "$T3B/consumer/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme" }
EOF
RV=$(bash "$RESOLVE" "$T3B/source")
if [ "$RV" = "2026.06.0" ]; then
  pass "resolve-repo-version.sh tagless+plugin.json → plugin.json version (2026.06.0), nested key not picked"
else
  fail "resolve tagless+plugin.json" "expected 2026.06.0 got '$RV'"
fi
OUT=$(render_site_a_line "$T3B/source" "$T3B/consumer")
if echo "$OUT" | grep -q 'Repo version: (none) → 2026.06.0' && ! echo "$OUT" | grep -q '(unversioned)'; then
  pass "Site A: tagless-but-complete clone shows plugin.json version, NOT (unversioned)"
else
  fail "Site A tagless+plugin.json" "got: $OUT"
fi

# ----------------------------------------------------------------------
# Test 4: Site B — install final report's Per-skill versions block.
# ----------------------------------------------------------------------
echo ""
echo "=== Test 4: Site B — install renders Per-skill versions list ==="
T4=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
mkdir -p "$T4/source/skills" "$T4/source/scripts" "$T4/source/block-diagram"
cp "$GET_HELPER" "$T4/source/scripts/frontmatter-get.sh"
write_skill "$T4/source/skills/run-plan" run-plan "2026.05.02+aaaaaa"
write_skill "$T4/source/skills/briefing" briefing "2026.05.02+bbbbbb"
write_skill "$T4/source/block-diagram/add-block" add-block "2026.05.02+adadad"
mkdir -p "$T4/consumer/.claude/skills"  # empty install
cat > "$T4/consumer/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme" }
EOF
BLOCK=$(render_site_b_block "$T4/source" "$T4/consumer" 0)
if echo "$BLOCK" | grep -q 'run-plan' \
   && echo "$BLOCK" | grep -q 'briefing' \
   && echo "$BLOCK" | grep -q '(new)'; then
  pass "Site B core skills shown with (new): block has run-plan, briefing, (new)"
else
  fail "Site B core skills" "block:
$BLOCK"
fi
if echo "$BLOCK" | grep -q 'add-block'; then
  fail "Site B addon hidden by default" "add-block leaked into block:
$BLOCK"
else
  pass "Site B addon hidden by default (no add-block row)"
fi
# Now with addon flag.
BLOCK_ADD=$(render_site_b_block "$T4/source" "$T4/consumer" 1)
if echo "$BLOCK_ADD" | grep -q 'add-block'; then
  pass "Site B addon shown with --with-block-diagram-addons"
else
  fail "Site B addon shown" "block:
$BLOCK_ADD"
fi

# ----------------------------------------------------------------------
# Test 5: Site C — update report renders structured table.
# Reuse Test 1's fixture (already has both old and new state).
# ----------------------------------------------------------------------
echo ""
echo "=== Test 5: Site C — update final report renders structured table ==="
TABLE=$(render_site_c_table "$T1/source" "$T1/consumer" 0)
# Expected lines:
#   Repo version: 2026.04.0 → 2026.05.0
#   run-plan        2026.04.20+999999 → 2026.05.02+aaaaaa
#   briefing        2026.05.02+bbbbbb (unchanged)
#   commit          (in New section, status=new)
if echo "$TABLE" | grep -q 'Repo version: 2026.04.0 → 2026.05.0'; then
  pass "Site C: Repo version delta line"
else
  fail "Site C: Repo version delta" "table:
$TABLE"
fi
if echo "$TABLE" | grep -qE 'run-plan +2026\.04\.20\+999999 → 2026\.05\.02\+aaaaaa'; then
  pass "Site C: bumped row shows old → new"
else
  fail "Site C: bumped row" "table:
$TABLE"
fi
if echo "$TABLE" | grep -qE 'briefing +2026\.05\.02\+bbbbbb \(unchanged\)'; then
  pass "Site C: unchanged row labeled (unchanged)"
else
  fail "Site C: unchanged row" "table:
$TABLE"
fi
if echo "$TABLE" | grep -q '^  commit$'; then
  pass "Site C: new row appears under New: section"
else
  fail "Site C: new row" "table:
$TABLE"
fi

# ----------------------------------------------------------------------
# Test 6: CONTRAST — rerender silent + managed.md silent.
# Encode the rerender oracle inline (mirrors Step D's documented spec:
# template + simple placeholders → managed.md, NO version data).
# ----------------------------------------------------------------------
echo ""
echo "=== Test 6: CONTRAST — rerender output + managed.md version-data-free ==="
T6=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
mkdir -p "$T6/.claude"
cat > "$T6/CLAUDE_TEMPLATE.md" <<'EOF'
# {{PROJECT_NAME}} — Agent Reference
Generic rules.
EOF
cat > "$T6/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme", "zskills_version": "2026.05.0" }
EOF
# Inline rerender oracle (matches Step D spec).
RERENDER_OUT="/tmp/zskills-test-vsurf-rerender-out-$$"
{
  template_content=$(cat "$T6/CLAUDE_TEMPLATE.md")
  cfg=$(cat "$T6/.claude/zskills-config.json")
  project_name=""
  if [[ "$cfg" =~ \"project_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    project_name="${BASH_REMATCH[1]}"
  fi
  rendered="${template_content//\{\{PROJECT_NAME\}\}/$project_name}"
  mkdir -p "$T6/.claude/rules/zskills"
  printf '%s' "$rendered" > "$T6/.claude/rules/zskills/managed.md"
  echo "Re-render complete."
} > "$RERENDER_OUT" 2>&1

if grep -E 'Repo version|metadata\.version' "$RERENDER_OUT" >/dev/null; then
  fail "rerender output silent" "leaked: $(grep -E 'Repo version|metadata\.version' "$RERENDER_OUT")"
else
  pass "rerender output is version-data-free"
fi
if grep -E 'Repo version|metadata\.version' "$T6/.claude/rules/zskills/managed.md" >/dev/null; then
  fail "managed.md silent" "leaked: $(grep -E 'Repo version|metadata\.version' "$T6/.claude/rules/zskills/managed.md")"
else
  pass "managed.md is version-data-free"
fi
rm -f "$RERENDER_OUT"

# Contrast complement: install/update flows DO surface version data.
INSTALL_OUT=$(render_site_b_block "$T4/source" "$T4/consumer" 0)
UPDATE_OUT=$(render_site_c_table "$T1/source" "$T1/consumer" 0)
if echo "$INSTALL_OUT$UPDATE_OUT" | grep -qE '2026\.0[0-9]\.[0-9]+\+'; then
  pass "install/update flows DO surface metadata.version-style version data (contrast)"
else
  fail "install/update contrast" "no version data found in install or update render"
fi

# ----------------------------------------------------------------------
# Test 7: SKILL.md textual invariants — required anchors and keywords.
# ----------------------------------------------------------------------
echo ""
echo "=== Test 7: SKILL.md textual invariants (anchors + keywords) ==="
# Site A
if grep -q 'Versions: zskills' "$SKILL_MD"; then
  pass "SKILL.md contains Site A 'Versions: zskills' template line"
else
  fail "SKILL.md Site A line" "missing 'Versions: zskills' template"
fi
# AC #1: Step 6 (audit gap report) contains a 'Repo version:' line.
STEP6_BLOCK=$(awk '/^### Step 6 — Produce the gap report/,/^## Default Mode|^---$/' "$SKILL_MD")
if echo "$STEP6_BLOCK" | grep -q 'Repo version:'; then
  pass "AC #1: Step 6 contains 'Repo version:' line"
else
  fail "AC #1: Step 6 'Repo version:'" "Step 6 block has no 'Repo version:' line"
fi
# Site B
if grep -q 'Per-skill versions:' "$SKILL_MD"; then
  pass "SKILL.md contains Site B 'Per-skill versions:' label"
else
  fail "SKILL.md Site B label" "missing 'Per-skill versions:'"
fi
# Site C
if grep -qE 'Repo version: <old_zskills_ver> → <new_zskills_ver>' "$SKILL_MD"; then
  pass "SKILL.md contains Site C 'Repo version: <old> → <new>' template"
else
  fail "SKILL.md Site C template" "missing Repo version delta template"
fi
# Step F.5 + Pull Latest 5.7 mirror-tag-into-config
if grep -q '#### Step F.5 — Mirror the source-repo tag' "$SKILL_MD"; then
  pass "SKILL.md contains '#### Step F.5 — Mirror the source-repo tag' heading"
else
  fail "SKILL.md Step F.5 heading" "missing"
fi
if grep -qE '^5\.7\. \*\*Mirror the source-repo tag' "$SKILL_MD"; then
  pass "SKILL.md contains Pull Latest step '5.7. **Mirror the source-repo tag'"
else
  fail "SKILL.md Pull Latest 5.7" "missing"
fi
# json-set-string-field referenced in mirror steps
if [ "$(grep -c 'json-set-string-field.sh' "$SKILL_MD")" -ge 2 ]; then
  pass "SKILL.md references json-set-string-field.sh in both mirror steps (count >= 2)"
else
  fail "SKILL.md mirror references" "expected >=2, got $(grep -c json-set-string-field.sh "$SKILL_MD")"
fi
# AC #2 from plan: metadata.version count >= 2
if [ "$(grep -c 'metadata.version' "$SKILL_MD")" -ge 2 ]; then
  pass "SKILL.md grep -c 'metadata.version' >= 2 (AC #2)"
else
  fail "SKILL.md metadata.version count" "expected >=2, got $(grep -c 'metadata.version' "$SKILL_MD")"
fi
# AC #8: no jq INVOCATIONS (documentation disclaimers like "no `jq`" are
# exempt — they assert absence rather than perform a call). The regex
# matches actual jq command shapes:
#   `| jq`       — pipe into jq
#   `$(jq ...)`  — command substitution
#   `` `jq ...` `` — backtick command substitution
#   `jq -<flag>` — jq with a CLI flag (e.g. -r, -n)
#   `jq '...'` / `jq "..."` — jq with a quoted JSONPath argument
#   `^jq <arg>`  — jq as the leading token on a line
JQ_INVOCATION_RE='\| *jq( |$)|\$\(jq |`jq |jq +-[a-zA-Z]|jq +['"'"'"]|^jq +'
JQ_INVOCATIONS=$(grep -cE "$JQ_INVOCATION_RE" "$SKILL_MD")
if [ "$JQ_INVOCATIONS" = "0" ]; then
  pass "SKILL.md has zero jq invocations (AC #8 — documentation disclaimers exempt)"
else
  fail "SKILL.md jq invocation count" "expected 0, got $JQ_INVOCATIONS:
$(grep -nE "$JQ_INVOCATION_RE" "$SKILL_MD")"
fi

# ----------------------------------------------------------------------
# Test 8: json-set-string-field round-trip — Step F.5 mirror works.
# ----------------------------------------------------------------------
echo ""
echo "=== Test 8: json-set-string-field round-trip (mirror tag into config) ==="
T8=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
cat > "$T8/cfg.json" <<'EOF'
{
  "project_name": "acme"
}
EOF
bash "$JSON_SET" "$T8/cfg.json" zskills_version "2026.05.0"
NEW=$(read_installed_zskills_ver "$T8/cfg.json")
if [ "$NEW" = "2026.05.0" ]; then
  pass "Step F.5 mirror: json-set-string-field inserts zskills_version when absent"
else
  fail "Step F.5 mirror insert" "expected 2026.05.0 got '$NEW'; cfg:
$(cat "$T8/cfg.json")"
fi
# Update path: change the value.
bash "$JSON_SET" "$T8/cfg.json" zskills_version "2026.05.1"
NEW=$(read_installed_zskills_ver "$T8/cfg.json")
if [ "$NEW" = "2026.05.1" ]; then
  pass "Step F.5 mirror: json-set-string-field updates zskills_version when present"
else
  fail "Step F.5 mirror update" "expected 2026.05.1 got '$NEW'"
fi

# ----------------------------------------------------------------------
# Oracle: render the bare-preset config-only version nudge.
# Mirrors the SKILL.md `## Bare-preset config-only short-circuit` spec:
#   best-effort `git fetch --tags` (offline-safe), reuse resolve-repo-version
#   + installed `zskills_version`, print the nudge line ONLY when installed
#   is strictly behind current (sort -V). Otherwise emit nothing.
# ----------------------------------------------------------------------
render_bare_preset_nudge() {
  local zskills_path="$1" claude_dir="$2"
  local current installed
  # Best-effort tag refresh (offline-safe — failure never aborts).
  if [ -n "$zskills_path" ] && [ -d "$zskills_path/.git" ]; then
    git -C "$zskills_path" fetch --tags --quiet 2>/dev/null || true
  fi
  current=""
  [ -n "$zskills_path" ] && current=$(bash "$RESOLVE" "$zskills_path")
  installed=$(read_installed_zskills_ver "$claude_dir/.claude/zskills-config.json")
  # Skip silently unless BOTH present AND installed strictly behind current.
  [ -z "$current" ] && return 0
  [ -z "$installed" ] && return 0
  [ "$installed" = "$current" ] && return 0
  local earliest
  earliest=$(printf '%s\n%s\n' "$installed" "$current" | sort -V | head -1)
  [ "$earliest" = "$installed" ] || return 0  # installed is NOT behind
  echo "zskills ${installed} → ${current} available. Run /update-zskills (no args) to pull + update."
}

# ----------------------------------------------------------------------
# Test 9: Bare preset is config-only (does NOT render/run the update or
# audit pass) and emits the config-only confirmation + version nudge —
# while `install <preset>` still does both. Asserted as SKILL.md textual
# invariants (the skill is agent-executed; the oracle encodes the spec).
# ----------------------------------------------------------------------
echo ""
echo "=== Test 9: bare preset config-only short-circuit (SKILL.md invariants) ==="
SHORTCIRCUIT_BLOCK=$(awk '/^## Bare-preset config-only short-circuit/,/^## Default Mode — Smart Detection/' "$SKILL_MD")
if [ -n "$SHORTCIRCUIT_BLOCK" ]; then
  pass "SKILL.md has '## Bare-preset config-only short-circuit' section"
else
  fail "SKILL.md bare-preset section" "missing '## Bare-preset config-only short-circuit' heading"
fi
# The short-circuit must forbid audit/pull/fill on a bare preset.
if echo "$SHORTCIRCUIT_BLOCK" | grep -qi 'do .*NOT.* run the audit' \
   && echo "$SHORTCIRCUIT_BLOCK" | grep -qi 'NOT.* pull'; then
  pass "bare-preset section documents: no audit, no pull"
else
  fail "bare-preset no-audit/no-pull" "section does not forbid audit/pull:
$SHORTCIRCUIT_BLOCK"
fi
# Config-only confirmation wording present.
if echo "$SHORTCIRCUIT_BLOCK" | grep -q 'config only — no skills pulled or updated'; then
  pass "bare-preset section contains config-only confirmation line"
else
  fail "bare-preset confirmation" "missing 'config only — no skills pulled or updated' line"
fi
# Version-availability nudge line present, pointing at the bare command.
if echo "$SHORTCIRCUIT_BLOCK" | grep -q 'available. Run /update-zskills (no args) to pull + update'; then
  pass "bare-preset section contains version-availability nudge line"
else
  fail "bare-preset nudge" "missing version-availability nudge line"
fi
# Best-effort, offline-safe fetch documented.
if echo "$SHORTCIRCUIT_BLOCK" | grep -q 'fetch --tags' \
   && echo "$SHORTCIRCUIT_BLOCK" | grep -qi 'offline-safe'; then
  pass "bare-preset section documents best-effort offline-safe git fetch --tags"
else
  fail "bare-preset fetch" "missing best-effort offline-safe 'git fetch --tags'"
fi
# Reuses existing machinery (resolve-repo-version.sh) — no new comparison logic.
if echo "$SHORTCIRCUIT_BLOCK" | grep -q 'resolve-repo-version.sh'; then
  pass "bare-preset section reuses resolve-repo-version.sh (no new comparison logic)"
else
  fail "bare-preset reuse" "section does not reference resolve-repo-version.sh"
fi
# Behavior-by-invocation: bare preset is config-only; install <preset> does both.
BEHAVIOR_BLOCK=$(awk '/^Behavior by invocation:/,/^---$/' "$SKILL_MD")
if echo "$BEHAVIOR_BLOCK" | grep -qi 'bare.* preset' \
   && echo "$BEHAVIOR_BLOCK" | grep -qi 'config-only'; then
  pass "Behavior-by-invocation documents bare preset as config-only"
else
  fail "Behavior bare preset" "behavior section does not mark bare preset config-only:
$BEHAVIOR_BLOCK"
fi
if echo "$BEHAVIOR_BLOCK" | grep -q 'install <preset>' \
   && echo "$BEHAVIOR_BLOCK" | grep -qi 'install AND set config'; then
  pass "Behavior-by-invocation: install <preset> still installs AND sets config"
else
  fail "Behavior install <preset>" "behavior section does not keep install <preset> doing both:
$BEHAVIOR_BLOCK"
fi

# ----------------------------------------------------------------------
# Test 10: Bare-preset version-nudge oracle — behind, current, ahead,
# missing-version, and tagless (offline-safe) cases.
# ----------------------------------------------------------------------
echo ""
echo "=== Test 10: bare-preset version-nudge oracle (only-when-behind, offline-safe) ==="
# Reuse Test 1's source (tag 2026.05.0) + consumer (installed 2026.04.0 → behind).
NUDGE=$(render_bare_preset_nudge "$T1/source" "$T1/consumer")
if echo "$NUDGE" | grep -qF 'zskills 2026.04.0 → 2026.05.0 available. Run /update-zskills (no args) to pull + update.'; then
  pass "nudge printed when installed behind (2026.04.0 → 2026.05.0)"
else
  fail "nudge when behind" "got: '$NUDGE'"
fi
# Up-to-date consumer → no nudge.
T10=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
mkdir -p "$T10/source/skills" "$T10/source/scripts"
cp "$GET_HELPER" "$T10/source/scripts/frontmatter-get.sh"
write_skill "$T10/source/skills/run-plan" run-plan "2026.05.02+aaaaaa"
( cd "$T10/source" && git init -q && git config user.email t@e && git config user.name t \
  && git add -A && git commit -q -m init && git tag 2026.05.0 )
mkdir -p "$T10/consumer/.claude/skills"
cat > "$T10/consumer/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme", "zskills_version": "2026.05.0" }
EOF
NUDGE=$(render_bare_preset_nudge "$T10/source" "$T10/consumer")
if [ -z "$NUDGE" ]; then
  pass "no nudge when installed == current (2026.05.0)"
else
  fail "no nudge when current" "unexpected nudge: '$NUDGE'"
fi
# Installed AHEAD of source tag → no nudge.
cat > "$T10/consumer/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme", "zskills_version": "2026.06.1" }
EOF
NUDGE=$(render_bare_preset_nudge "$T10/source" "$T10/consumer")
if [ -z "$NUDGE" ]; then
  pass "no nudge when installed ahead of source tag (offline-safe / no false nudge)"
else
  fail "no nudge when ahead" "unexpected nudge: '$NUDGE'"
fi
# Tagless source (offline-safe: no tags → no nudge, no failure).
T10B=$(mktemp -d /tmp/zskills-test-vsurf-XXXXXX)
mkdir -p "$T10B/source/skills" "$T10B/source/scripts"
cp "$GET_HELPER" "$T10B/source/scripts/frontmatter-get.sh"
write_skill "$T10B/source/skills/run-plan" run-plan "2026.05.02+aaaaaa"
( cd "$T10B/source" && git init -q && git config user.email t@e && git config user.name t \
  && git add -A && git commit -q -m init )  # NO tag
mkdir -p "$T10B/consumer/.claude/skills"
cat > "$T10B/consumer/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme", "zskills_version": "2026.04.0" }
EOF
NUDGE=$(render_bare_preset_nudge "$T10B/source" "$T10B/consumer")
if [ -z "$NUDGE" ]; then
  pass "no nudge when source clone tagless (offline-safe)"
else
  fail "no nudge when tagless" "unexpected nudge: '$NUDGE'"
fi
# Missing installed zskills_version → no nudge (nothing to compare against).
cat > "$T10/consumer/.claude/zskills-config.json" <<'EOF'
{ "project_name": "acme" }
EOF
NUDGE=$(render_bare_preset_nudge "$T10/source" "$T10/consumer")
if [ -z "$NUDGE" ]; then
  pass "no nudge when installed zskills_version absent"
else
  fail "no nudge when installed absent" "unexpected nudge: '$NUDGE'"
fi

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
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
