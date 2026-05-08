#!/bin/bash
# Tests for /update-zskills --migrate-paths (Phase 5a, ZSKILLS_PATH_CONFIG.md).
#
# Unlike test-update-zskills-rerender.sh / test-update-zskills-migration.sh
# (which encode the SKILL.md algorithm as bash oracles), this test invokes
# the actual `migrate-paths.sh` script directly — that script IS the
# deterministic move logic per Phase 5a.1 / DA finding 16.
#
# Coverage (matches Phase 5a.4 exactly):
#   1. Legacy-only fixture: synthetic repo with plans/FOO_PLAN.md,
#      plans/PLAN_INDEX.md, reports/plan-foo.md, SPRINT_REPORT.md,
#      var/dev.pid. Run migrate-paths.sh. Assert legacy paths absent,
#      new paths present (docs/plans/FOO_PLAN.md AND
#      .zskills/audit/PLAN_INDEX.md per the per-tier split),
#      .pre-paths-migration exists, manifest matches moves, config
#      gained output.plans_dir = "docs/plans" AND output.issues_dir =
#      ".zskills/issues" (BOTH keys, atomic).
#      Plus rerender-ordering CI guard sub-assertion: scan
#      update-zskills/SKILL.md Step C section for any new {{...}}
#      template placeholders that reference path-config keys; fail if
#      found.
#   2. Pre-configured fixture: output.plans_dir = "stash" AND
#      output.issues_dir = ".zskills/issues" already set. Plans land in
#      stash/, NOT docs/plans/.
#   3. Idempotent re-run: run twice. Second run prints "already
#      migrated" and exits 0; .pre-paths-migration mtime unchanged.
#   4. Empty fixture (no legacy): no-op. .pre-paths-migration NOT
#      created; config unchanged.
#
# Per CLAUDE.md test-output idiom, fixtures are written to
# /tmp/zskills-tests/$(basename "$REPO_ROOT")/paths-migration-fixture-*
# so they never appear in `git status` of the worktree.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_OUT="/tmp/zskills-tests/$(basename "$REPO_ROOT")"
mkdir -p "$TEST_OUT"

MIGRATE_SCRIPT="$REPO_ROOT/skills/update-zskills/scripts/migrate-paths.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s — %s\n' "$1" "$2"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# Build a minimal git-init'd fixture under the given dir. Caller adds
# files before/after as needed.
init_repo() {
  local dir="$1"
  rm -rf -- "$dir"
  mkdir -p "$dir"
  ( cd "$dir" \
    && git init -q -b paths-test \
    && git config user.email test@example.com \
    && git config user.name test \
    && touch .gitignore )
}

# Produce a minimal valid .claude/zskills-config.json with optional output
# block.
write_config() {
  local dir="$1" plans="${2:-}" issues="${3:-}"
  mkdir -p "$dir/.claude"
  if [ -n "$plans" ] || [ -n "$issues" ]; then
    {
      printf '{\n'
      printf '  "project_name": "fixture",\n'
      printf '  "output": {\n'
      printf '    "plans_dir": "%s",\n' "${plans:-docs/plans}"
      printf '    "issues_dir": "%s"\n' "${issues:-.zskills/issues}"
      printf '  }\n'
      printf '}\n'
    } > "$dir/.claude/zskills-config.json"
  else
    printf '{\n  "project_name": "fixture"\n}\n' > "$dir/.claude/zskills-config.json"
  fi
}

# Run the migration script with $PORTABLE pointing at the source tree
# (so step 2.5 finds hooks/block-unsafe-project.sh.template).
run_migrate() {
  local dir="$1"
  PORTABLE="$REPO_ROOT" bash "$MIGRATE_SCRIPT" "$dir"
}

# ─── Case 1: legacy-only fixture ──────────────────────────────────────────
case_1_legacy_only() {
  local D="$TEST_OUT/paths-migration-fixture-1"
  init_repo "$D"
  # Build legacy artifacts.
  mkdir -p "$D/plans" "$D/reports" "$D/var"
  echo "FOO plan body" > "$D/plans/FOO_PLAN.md"
  echo "plan-index body" > "$D/plans/PLAN_INDEX.md"
  echo "report body" > "$D/reports/plan-foo.md"
  echo "sprint body" > "$D/SPRINT_REPORT.md"
  echo "12345" > "$D/var/dev.pid"
  write_config "$D"
  # Run as untracked to exercise the `mv` (not `git mv`) branch.

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 1: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  # Sub-assertion: legacy paths absent.
  local missing=()
  for f in plans/FOO_PLAN.md plans/PLAN_INDEX.md reports/plan-foo.md \
           SPRINT_REPORT.md var/dev.pid; do
    [ -e "$D/$f" ] && missing+=("$f")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    pass "case 1: legacy paths absent post-migration"
  else
    fail "case 1: legacy paths still present" "${missing[*]}"
  fi

  # Sub-assertion: new paths present (per-tier split).
  if [ -e "$D/docs/plans/FOO_PLAN.md" ]; then
    pass "case 1: docs/plans/FOO_PLAN.md present (Tier 1 — durable plan)"
  else
    fail "case 1: docs/plans/FOO_PLAN.md missing" "$(ls -lR "$D/docs" 2>&1 | head -20)"
  fi
  if [ -e "$D/.zskills/audit/PLAN_INDEX.md" ]; then
    pass "case 1: .zskills/audit/PLAN_INDEX.md present (Tier 2 — regenerable)"
  else
    fail "case 1: .zskills/audit/PLAN_INDEX.md missing" "per-tier split broken"
  fi
  if [ -e "$D/.zskills/audit/SPRINT_REPORT.md" ]; then
    pass "case 1: .zskills/audit/SPRINT_REPORT.md present"
  else
    fail "case 1: .zskills/audit/SPRINT_REPORT.md missing" "$(ls "$D/.zskills/audit" 2>&1)"
  fi
  if [ -e "$D/.zskills/dev-server.pid" ]; then
    pass "case 1: .zskills/dev-server.pid present"
  else
    fail "case 1: .zskills/dev-server.pid missing" "$(ls "$D/.zskills" 2>&1)"
  fi

  # Sub-assertion: .pre-paths-migration exists.
  if [ -f "$D/.pre-paths-migration" ]; then
    pass "case 1: .pre-paths-migration manifest exists"
  else
    fail "case 1: .pre-paths-migration absent" "manifest not written"
    return
  fi

  # Sub-assertion: manifest matches moves (every entry is a tab-separated
  # from\tto pair pointing at a real new path).
  local bad_entries=0
  while IFS=$'\t' read -r src dst; do
    [ -z "$src" ] && continue
    if [ ! -e "$D/$dst" ]; then
      bad_entries=$((bad_entries + 1))
    fi
  done < "$D/.pre-paths-migration"
  if [ "$bad_entries" -eq 0 ]; then
    pass "case 1: every manifest entry's destination exists"
  else
    fail "case 1: manifest entries don't match filesystem" "$bad_entries dangling entries"
  fi

  # Sub-assertion: config gained BOTH output.plans_dir AND output.issues_dir
  # (atomic both-or-neither — Locked Decision 4).
  local cfg_body
  cfg_body=$(cat "$D/.claude/zskills-config.json")
  if echo "$cfg_body" | grep -q '"plans_dir"[[:space:]]*:[[:space:]]*"docs/plans"' \
     && echo "$cfg_body" | grep -q '"issues_dir"[[:space:]]*:[[:space:]]*"\.zskills/issues"'; then
    pass "case 1: config gained BOTH output.plans_dir AND output.issues_dir"
  else
    fail "case 1: config missing one or both output keys" "$cfg_body"
  fi

  # Sub-assertion (CI guard for rerender ordering, per round-2 DA F4):
  # scan update-zskills/SKILL.md's Step C section for any new {{...}}
  # template placeholders that reference path-config keys. If found,
  # fail with the prescribed message.
  local skill_file="$REPO_ROOT/skills/update-zskills/SKILL.md"
  local step_c
  step_c=$(awk '
    /^#### Step C — / { in_c = 1; next }
    /^#### Step C\./ { in_c = 1; next }
    /^#### Step / && !/^#### Step C/ { in_c = 0 }
    /^### / { in_c = 0 }
    in_c { print }
  ' "$skill_file")
  # Search for placeholder names that would reference path-config keys.
  if echo "$step_c" | grep -qE '\{\{(PLANS_DIR|ISSUES_DIR|OUTPUT_PLANS_DIR|OUTPUT_ISSUES_DIR|AUDIT_DIR)\}\}'; then
    fail "case 1: rerender-ordering CI guard" \
      "Step C now substitutes path-config keys; revisit migrate-paths.sh step 2.5/9 ordering."
  else
    pass "case 1: rerender-ordering CI guard — Step C does not template path-config keys"
  fi
}

# ─── Case 2: pre-configured fixture ───────────────────────────────────────
case_2_preconfigured() {
  local D="$TEST_OUT/paths-migration-fixture-2"
  init_repo "$D"
  mkdir -p "$D/plans"
  echo "BAR plan body" > "$D/plans/BAR_PLAN.md"
  # User pre-set both output keys.
  write_config "$D" "stash" ".zskills/issues"

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 2: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  # Plans land in stash/, NOT docs/plans/.
  if [ -e "$D/stash/BAR_PLAN.md" ] && [ ! -e "$D/docs/plans/BAR_PLAN.md" ]; then
    pass "case 2: pre-configured plans_dir=stash honored"
  else
    fail "case 2: plans landed in wrong dir" \
      "stash exists=$([ -e "$D/stash/BAR_PLAN.md" ] && echo yes || echo no) docs/plans exists=$([ -e "$D/docs/plans/BAR_PLAN.md" ] && echo yes || echo no)"
  fi

  # Issues dir present and used (no issue files in this fixture, but the
  # config's setting must have been preserved unchanged).
  local cfg_body
  cfg_body=$(cat "$D/.claude/zskills-config.json")
  if echo "$cfg_body" | grep -q '"plans_dir"[[:space:]]*:[[:space:]]*"stash"' \
     && echo "$cfg_body" | grep -q '"issues_dir"[[:space:]]*:[[:space:]]*"\.zskills/issues"'; then
    pass "case 2: config keys preserved (plans_dir=stash, issues_dir=.zskills/issues)"
  else
    fail "case 2: config keys mutated" "$cfg_body"
  fi
}

# ─── Case 3: idempotent re-run ────────────────────────────────────────────
case_3_idempotent() {
  local D="$TEST_OUT/paths-migration-fixture-3"
  init_repo "$D"
  mkdir -p "$D/plans"
  echo "BAZ plan body" > "$D/plans/BAZ_PLAN.md"
  write_config "$D"

  local out1 out2 rc1 rc2 mtime1 mtime2
  out1=$(run_migrate "$D" 2>&1); rc1=$?
  if [ "$rc1" -ne 0 ]; then
    fail "case 3: first run exit code" "rc=$rc1 out=$out1"
    return
  fi
  if [ ! -f "$D/.pre-paths-migration" ]; then
    fail "case 3: first run did not produce manifest" "no .pre-paths-migration"
    return
  fi
  mtime1=$(stat -c '%Y' "$D/.pre-paths-migration" 2>/dev/null \
           || stat -f '%m' "$D/.pre-paths-migration")

  # Second run.
  sleep 1  # ensure mtime resolution is sufficient to detect a write.
  out2=$(run_migrate "$D" 2>&1); rc2=$?
  if [ "$rc2" -ne 0 ]; then
    fail "case 3: second run exit code" "rc=$rc2 out=$out2"
    return
  fi
  if echo "$out2" | grep -q "already migrated"; then
    pass "case 3: second run prints 'already migrated'"
  else
    fail "case 3: second run did not detect prior migration" "out=$out2"
  fi
  mtime2=$(stat -c '%Y' "$D/.pre-paths-migration" 2>/dev/null \
           || stat -f '%m' "$D/.pre-paths-migration")
  if [ "$mtime1" = "$mtime2" ]; then
    pass "case 3: .pre-paths-migration mtime unchanged on second run"
  else
    fail "case 3: .pre-paths-migration was rewritten" "mtime1=$mtime1 mtime2=$mtime2"
  fi
}

# ─── Case 4: empty fixture (no legacy) ────────────────────────────────────
case_4_empty() {
  local D="$TEST_OUT/paths-migration-fixture-4"
  init_repo "$D"
  write_config "$D"
  # Capture the pre-run config bytes for unchanged-comparison.
  local pre_cfg
  pre_cfg=$(cat "$D/.claude/zskills-config.json")

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 4: migrate-paths.sh exit code on empty fixture" "rc=$rc out=$out"
    return
  fi

  if [ ! -f "$D/.pre-paths-migration" ]; then
    pass "case 4: no .pre-paths-migration on empty fixture"
  else
    fail "case 4: .pre-paths-migration created on empty fixture" \
      "$(cat "$D/.pre-paths-migration")"
  fi

  local post_cfg
  post_cfg=$(cat "$D/.claude/zskills-config.json")
  if [ "$pre_cfg" = "$post_cfg" ]; then
    pass "case 4: config unchanged on empty fixture"
  else
    fail "case 4: config mutated on empty fixture" \
      "$(diff <(echo "$pre_cfg") <(echo "$post_cfg"))"
  fi
}

# ─── Run ──────────────────────────────────────────────────────────────────
echo "Running tests/test-update-zskills-paths-migration.sh"
case_1_legacy_only
case_2_preconfigured
case_3_idempotent
case_4_empty

echo
echo "---"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '\033[32mResults: %d passed, 0 failed (of %d)\033[0m\n' "$PASS_COUNT" "$TOTAL"
  exit 0
else
  printf '\033[31mResults: %d passed, %d failed (of %d)\033[0m\n' "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL"
  exit 1
fi
