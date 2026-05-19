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
#      "docs/issues" (BOTH keys, atomic).
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
# block. If $4 (reports) is non-empty, includes reports_dir as a third key.
write_config() {
  local dir="$1" plans="${2:-}" issues="${3:-}" reports="${4:-}"
  mkdir -p "$dir/.claude"
  if [ -n "$plans" ] || [ -n "$issues" ] || [ -n "$reports" ]; then
    {
      printf '{\n'
      printf '  "project_name": "fixture",\n'
      printf '  "output": {\n'
      printf '    "plans_dir": "%s",\n' "${plans:-docs/plans}"
      if [ -n "$reports" ]; then
        printf '    "issues_dir": "%s",\n' "${issues:-docs/issues}"
        printf '    "reports_dir": "%s"\n' "$reports"
      else
        printf '    "issues_dir": "%s"\n' "${issues:-docs/issues}"
      fi
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

  # Sub-assertion: config gained ALL THREE output keys
  # (atomic both-or-all-or-neither — Locked Decision 4 + 3-tuple extension).
  local cfg_body
  cfg_body=$(cat "$D/.claude/zskills-config.json")
  if echo "$cfg_body" | grep -q '"plans_dir"[[:space:]]*:[[:space:]]*"docs/plans"' \
     && echo "$cfg_body" | grep -q '"issues_dir"[[:space:]]*:[[:space:]]*"docs/issues"' \
     && echo "$cfg_body" | grep -q '"reports_dir"[[:space:]]*:[[:space:]]*"docs/reports"'; then
    pass "case 1: config gained ALL THREE output keys (plans_dir, issues_dir, reports_dir)"
  else
    fail "case 1: config missing one or more output keys" "$cfg_body"
  fi
  # Sub-assertion: post-migration config is valid JSON (validates the
  # 3-tuple awk's trailing-comma policy in WI 1.6 part d/d-bis).
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$D/.claude/zskills-config.json" 2>/dev/null; then
    pass "case 1: post-migration config parses as valid JSON"
  else
    fail "case 1: config is not valid JSON" "$cfg_body"
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
  # 3-tuple extension: reports_dir was absent in fixture; migrator must
  # inject the default (docs/reports) without altering the preserved keys.
  if echo "$cfg_body" | grep -q '"reports_dir"[[:space:]]*:[[:space:]]*"docs/reports"'; then
    pass "case 2: reports_dir newly injected with default 'docs/reports'"
  else
    fail "case 2: reports_dir missing" "$cfg_body"
  fi
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$D/.claude/zskills-config.json" 2>/dev/null; then
    pass "case 2: post-migration config parses as valid JSON"
  else
    fail "case 2: config is not valid JSON" "$cfg_body"
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
  # 3-tuple extension: config after first run has all 3 keys; second run
  # must produce zero config diff (idempotency at the config-write layer,
  # not just at the manifest layer).
  local cfg_body
  cfg_body=$(cat "$D/.claude/zskills-config.json")
  if echo "$cfg_body" | grep -q '"reports_dir"[[:space:]]*:[[:space:]]*"docs/reports"'; then
    pass "case 3: reports_dir present in config after migration"
  else
    fail "case 3: reports_dir missing after migration" "$cfg_body"
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

# ─── Case 5: customized stub ──────────────────────────────────────────────
# A consumer's `scripts/start-dev.sh` differs from the shipped failing-stub
# default. Per DA finding 5 deferral rule: migrate-paths.sh does NOT touch
# the file; it prints a deferral notice naming the upgrade prompt.
case_5_customized_stub() {
  local D="$TEST_OUT/paths-migration-fixture-5"
  init_repo "$D"
  mkdir -p "$D/scripts" "$D/var"
  echo "12345" > "$D/var/dev.pid"
  # Customized start-dev.sh body (different from any shipped default).
  cat > "$D/scripts/start-dev.sh" <<'SDS'
#!/bin/bash
# Custom dev server launcher (consumer-modified)
echo $$ > var/dev.pid
nohup ./bin/my-server --custom-flag > var/dev.log 2>&1 &
SDS
  chmod +x "$D/scripts/start-dev.sh"
  local pre_body
  pre_body=$(cat "$D/scripts/start-dev.sh")
  write_config "$D"

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 5: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  # Sub-assertion: scripts/start-dev.sh body unchanged.
  local post_body
  post_body=$(cat "$D/scripts/start-dev.sh")
  if [ "$pre_body" = "$post_body" ]; then
    pass "case 5: customized scripts/start-dev.sh unchanged"
  else
    fail "case 5: customized stub was modified" \
      "$(diff <(echo "$pre_body") <(echo "$post_body"))"
  fi

  # Sub-assertion: summary mentions upgrade prompt.
  if echo "$out" | grep -q "path-config-upgrade.md"; then
    pass "case 5: deferral notice references path-config-upgrade.md"
  else
    fail "case 5: deferral notice missing" "out=$out"
  fi
}

# ─── Case 6: cross-reference rewrite — structural references ──────────────
case_6_cross_ref_rewrite() {
  local D="$TEST_OUT/paths-migration-fixture-6"
  init_repo "$D"
  mkdir -p "$D/plans"
  cat > "$D/plans/CASE6_PLAN.md" <<'CASE6'
---
status: active
---

# CASE6 plan

[See BAR](plans/BAR.md) inline link.

`plans/BAZ.md` is backticked.

we used to keep these in `plans/` before this migration

A backup file plans/foo.md.bak should remain bare prose.
CASE6
  write_config "$D"

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 6: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  local body
  body=$(cat "$D/docs/plans/CASE6_PLAN.md")

  # Link rewritten.
  if echo "$body" | grep -qF "[See BAR](docs/plans/BAR.md)"; then
    pass "case 6: markdown link rewritten plans/ → docs/plans/"
  else
    fail "case 6: markdown link not rewritten" "$body"
  fi

  # Backtick span rewritten.
  if echo "$body" | grep -qF '`docs/plans/BAZ.md`'; then
    pass "case 6: backtick span rewritten plans/ → docs/plans/"
  else
    fail "case 6: backtick span not rewritten" "$body"
  fi

  # Naked prose preserved.
  if echo "$body" | grep -qF "we used to keep these in"; then
    pass "case 6: naked prose preserved (no rewrite)"
  else
    fail "case 6: naked prose was modified" "$body"
  fi
  # The naked-prose mention of `plans/` (in a backtick around just
  # `plans/`) is NOT a token match (no `.md` suffix), so should remain.
  if echo "$body" | grep -qF '`plans/`'; then
    pass "case 6: bare \`plans/\` token (no .md) preserved"
  else
    fail "case 6: bare backtick plans/ was incorrectly modified" "$body"
  fi
}

# ─── Case 7: completed-canary self-invocation ────────────────────────────
case_7_canary_self_invocation() {
  local D="$TEST_OUT/paths-migration-fixture-7"
  init_repo "$D"
  mkdir -p "$D/plans"
  cat > "$D/plans/CANARY7_TEST.md" <<'CANARY7'
---
status: complete
---

# CANARY7 archived narrative

Run /run-plan plans/CANARY7_TEST.md finish auto

Some prose mentioning plans/CANARY7_TEST.md without enclosure stays bare.
CANARY7
  write_config "$D"

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 7: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  local body
  body=$(cat "$D/docs/plans/CANARY7_TEST.md")

  # Slash-command line REWRITTEN despite status: complete.
  if echo "$body" | grep -qF "/run-plan docs/plans/CANARY7_TEST.md"; then
    pass "case 7: completed-canary slash-command self-invocation rewritten"
  else
    fail "case 7: canary slash-command line not rewritten" "$body"
  fi
}

# ─── Case 8: completed non-canary plan with legacy tokens ────────────────
case_8_completed_noncanary_warn() {
  local D="$TEST_OUT/paths-migration-fixture-8"
  init_repo "$D"
  mkdir -p "$D/plans"
  # Build a fixture where the legacy-token line lands on line 42.
  {
    printf -- '---\n'
    printf -- 'status: complete\n'
    printf -- '---\n'
    printf -- '\n'
    printf -- '# OLD_FEATURE_PLAN archived narrative\n'
    printf -- '\n'
    # Pad lines until we are about to write line 42.
    local i
    for i in $(seq 7 41); do
      printf -- 'pad line %s\n' "$i"
    done
    # Line 42:
    printf -- '[See OTHER](plans/OTHER.md)\n'
  } > "$D/plans/OLD_FEATURE_PLAN.md"
  write_config "$D"

  # Capture pre-migration body bytes for the byte-equal comparison
  # (after migration the file lives under docs/plans/, but body bytes
  # should be identical for the PRESERVED case).
  local pre_body
  pre_body=$(cat "$D/plans/OLD_FEATURE_PLAN.md")

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 8: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  local post_body
  post_body=$(cat "$D/docs/plans/OLD_FEATURE_PLAN.md")
  if [ "$pre_body" = "$post_body" ]; then
    pass "case 8: PRESERVED frozen plan body byte-equal"
  else
    fail "case 8: PRESERVED plan was rewritten" \
      "$(diff <(echo "$pre_body") <(echo "$post_body"))"
  fi

  # Stderr WARN line matching the regex.
  if echo "$out" | grep -qE "^WARN .*OLD_FEATURE_PLAN\.md:42: legacy token 'plans/OTHER\.md' preserved"; then
    pass "case 8: stderr WARN line emitted in correct format"
  else
    fail "case 8: stderr WARN line missing" "$out"
  fi

  # User-discoverable warnings file at .zskills/audit/migration-warnings.md
  # (relocated from repo-root .pre-paths-migration-warnings — placement
  # made user-discoverable per the audit-dir convention).
  if [ -f "$D/.zskills/audit/migration-warnings.md" ]; then
    if grep -qE "^WARN .*OLD_FEATURE_PLAN\.md:42: legacy token 'plans/OTHER\.md' preserved" "$D/.zskills/audit/migration-warnings.md"; then
      pass "case 8: .zskills/audit/migration-warnings.md contains WARN line"
    else
      fail "case 8: warnings file lacks WARN line" "$(cat "$D/.zskills/audit/migration-warnings.md")"
    fi
    # Markdown header should be present (user-discoverable doc).
    if head -1 "$D/.zskills/audit/migration-warnings.md" | grep -qE '^# Migration warnings'; then
      pass "case 8: warnings file has markdown H1 header"
    else
      fail "case 8: warnings file missing markdown header" "$(head -3 "$D/.zskills/audit/migration-warnings.md")"
    fi
    # Legacy repo-root location must NOT be created.
    if [ -e "$D/.pre-paths-migration-warnings" ]; then
      fail "case 8: legacy repo-root .pre-paths-migration-warnings should NOT exist" "found at $D/.pre-paths-migration-warnings"
    else
      pass "case 8: legacy repo-root .pre-paths-migration-warnings not created (relocated)"
    fi
  else
    fail "case 8: .zskills/audit/migration-warnings.md absent" "expected at audit dir"
  fi
}

# ─── Case 9: hook re-render and effective gitignore ──────────────────────
case_9_hook_rerender_gitignore() {
  local D="$TEST_OUT/paths-migration-fixture-9"
  init_repo "$D"
  mkdir -p "$D/plans"
  echo "QUUX plan" > "$D/plans/QUUX_PLAN.md"
  write_config "$D"

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 9: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  # (a) block-unsafe-project.sh has the broadened \.zskills regex (NOT
  # \.zskills/tracking).
  local hook="$D/.claude/hooks/block-unsafe-project.sh"
  if [ ! -f "$hook" ]; then
    fail "case 9: block-unsafe-project.sh missing" "no hook copied"
    return
  fi
  if grep -q '\\\.zskills/tracking' "$hook"; then
    fail "case 9: hook still has narrow \\\.zskills/tracking regex" \
      "broadened regex not in place"
  else
    if grep -q '\\\.zskills' "$hook"; then
      pass "case 9: hook has broadened \\\.zskills regex (no /tracking suffix)"
    else
      fail "case 9: hook missing any \\\.zskills regex" "$hook"
    fi
  fi

  # (b) git check-ignore -v .zskills/audit/dummy exits 0 with non-`!`
  # match.
  mkdir -p "$D/.zskills/audit"
  touch "$D/.zskills/audit/dummy"
  local check_out
  check_out=$( cd "$D" && git check-ignore -v .zskills/audit/dummy 2>&1 )
  local check_rc=$?
  if [ "$check_rc" -ne 0 ]; then
    fail "case 9: git check-ignore -v failed" "rc=$check_rc out=$check_out"
    return
  fi
  case "$check_out" in
    *!*) fail "case 9: positive include rule overrides ignore" "$check_out" ;;
    *) pass "case 9: .zskills/audit/dummy effectively ignored (no \`!\` override)" ;;
  esac
}

# ─── Case 10: --rewrite-only mid-version-skip recovery ───────────────────
case_10_rewrite_only_recovery() {
  local D="$TEST_OUT/paths-migration-fixture-10"
  init_repo "$D"

  # Phase A: simulate migrated tree under an older 5a-only run.
  mkdir -p "$D/docs/plans"
  cat > "$D/docs/plans/STILL_LEGACY.md" <<'SL'
---
status: active
---

# STILL_LEGACY plan

Run `/run-plan plans/SOMETHING.md`
SL
  printf 'plans/OLD\tdocs/plans/OLD\n' > "$D/.pre-paths-migration"
  write_config "$D" "docs/plans" ".zskills/issues"

  # Capture pre-trailer manifest bytes.
  local pre_manifest
  pre_manifest=$(cat "$D/.pre-paths-migration")

  # Phase B: invoke --rewrite-only.
  local out rc
  out=$( PORTABLE="$REPO_ROOT" bash "$MIGRATE_SCRIPT" --rewrite-only "$D" 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 10: --rewrite-only exit code" "rc=$rc out=$out"
    return
  fi

  # Plan content rewritten.
  local body
  body=$(cat "$D/docs/plans/STILL_LEGACY.md")
  if echo "$body" | grep -qF '/run-plan docs/plans/SOMETHING.md'; then
    pass "case 10: --rewrite-only rewrote slash-command line"
  else
    fail "case 10: slash-command line not rewritten" "$body"
  fi

  # .pre-paths-migration still exists, gained a trailer.
  if [ ! -f "$D/.pre-paths-migration" ]; then
    fail "case 10: --rewrite-only deleted manifest" "manifest missing"
    return
  fi
  if grep -qE '^rewrite-only:	[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z	[0-9]+$' "$D/.pre-paths-migration"; then
    pass "case 10: manifest gained rewrite-only trailer"
  else
    fail "case 10: manifest lacks expected trailer" "$(cat "$D/.pre-paths-migration")"
  fi

  # Config keys unchanged.
  local cfg_body
  cfg_body=$(cat "$D/.claude/zskills-config.json")
  if echo "$cfg_body" | grep -q '"plans_dir"[[:space:]]*:[[:space:]]*"docs/plans"' \
     && echo "$cfg_body" | grep -q '"issues_dir"[[:space:]]*:[[:space:]]*"\.zskills/issues"'; then
    pass "case 10: config keys unchanged after --rewrite-only"
  else
    fail "case 10: config mutated by --rewrite-only" "$cfg_body"
  fi

  # Idempotent re-run: invoke again, no plan content change, second
  # trailer line appears.
  local body_before second_out second_rc
  body_before=$(cat "$D/docs/plans/STILL_LEGACY.md")
  second_out=$( PORTABLE="$REPO_ROOT" bash "$MIGRATE_SCRIPT" --rewrite-only "$D" 2>&1 ); second_rc=$?
  if [ "$second_rc" -ne 0 ]; then
    fail "case 10: --rewrite-only second-run exit code" "rc=$second_rc out=$second_out"
    return
  fi
  local body_after
  body_after=$(cat "$D/docs/plans/STILL_LEGACY.md")
  if [ "$body_before" = "$body_after" ]; then
    pass "case 10: --rewrite-only second run is content-idempotent"
  else
    fail "case 10: --rewrite-only second run modified plan content" \
      "$(diff <(echo "$body_before") <(echo "$body_after"))"
  fi
  local trailer_count
  trailer_count=$(grep -cE '^rewrite-only:' "$D/.pre-paths-migration")
  if [ "$trailer_count" -eq 2 ]; then
    pass "case 10: manifest gained second rewrite-only trailer"
  else
    fail "case 10: expected 2 rewrite-only trailers, found $trailer_count" \
      "$(cat "$D/.pre-paths-migration")"
  fi

  # NEGATIVE precondition: pristine fixture WITHOUT .pre-paths-migration.
  local D2="$TEST_OUT/paths-migration-fixture-10-neg"
  init_repo "$D2"
  mkdir -p "$D2/docs/plans"
  echo "stub" > "$D2/docs/plans/X.md"
  write_config "$D2" "docs/plans" ".zskills/issues"
  local neg_out neg_rc
  neg_out=$( PORTABLE="$REPO_ROOT" bash "$MIGRATE_SCRIPT" --rewrite-only "$D2" 2>&1 ); neg_rc=$?
  if [ "$neg_rc" -ne 0 ] && echo "$neg_out" | grep -qF "no prior migration to rewrite"; then
    pass "case 10: --rewrite-only refuses pristine fixture (precondition)"
  else
    fail "case 10: --rewrite-only did not enforce precondition" \
      "rc=$neg_rc out=$neg_out"
  fi
}

# ─── Case 11: macOS chmod --reference fallback (round-2 DA D2) ───────────
# Force the `chmod --reference=...` call to fail (via a PATH shim whose
# `chmod` exits 2 when given `--reference=` on its arg list). The fallback
# `chmod 644` must run, so the rewritten plan ends up at mode 0644.
case_11_chmod_fallback() {
  local D="$TEST_OUT/paths-migration-fixture-11"
  init_repo "$D"
  mkdir -p "$D/plans"
  cat > "$D/plans/CASE11_PLAN.md" <<'CASE11'
---
status: active
---

# CASE11 plan

[See FOO](plans/FOO.md)
CASE11
  # Force the source mode to 0600 so any silent failure of the post-
  # rewrite chmod will leave the mode visibly wrong (not coincidentally
  # 0644).
  chmod 600 "$D/plans/CASE11_PLAN.md"
  write_config "$D"

  # Build a PATH shim that fails on `chmod --reference=...` (simulates
  # macOS) and falls through to /bin/chmod for everything else.
  local shim_dir="$TEST_OUT/case11-shim"
  rm -rf -- "$shim_dir"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/chmod" <<'SHIM'
#!/bin/bash
# Shim chmod: refuse --reference= (simulating macOS), defer to /bin/chmod
# for every other invocation.
for a in "$@"; do
  case "$a" in
    --reference=*)
      echo "shim chmod: --reference= not supported" >&2
      exit 2 ;;
  esac
done
exec /bin/chmod "$@"
SHIM
  chmod +x "$shim_dir/chmod"

  local out rc
  out=$( PATH="$shim_dir:$PATH" PORTABLE="$REPO_ROOT" bash "$MIGRATE_SCRIPT" "$D" 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 11: migrate-paths.sh exit code with chmod shim" "rc=$rc out=$out"
    return
  fi

  # The plan's mode after fallback should be 0644.
  local mode
  mode=$(stat -c '%a' "$D/docs/plans/CASE11_PLAN.md" 2>/dev/null \
         || stat -f '%Lp' "$D/docs/plans/CASE11_PLAN.md")
  if [ "$mode" = "644" ]; then
    pass "case 11: chmod 644 fallback applied (plan mode = 0644)"
  else
    fail "case 11: plan mode incorrect after fallback" "mode=$mode (expected 644)"
  fi

  # Sanity: rewrite still happened (link rewritten).
  if grep -qF "[See FOO](docs/plans/FOO.md)" "$D/docs/plans/CASE11_PLAN.md"; then
    pass "case 11: rewrite still applied under chmod shim"
  else
    fail "case 11: rewrite did not apply under chmod shim" \
      "$(cat "$D/docs/plans/CASE11_PLAN.md")"
  fi
}

# ─── Case 12: non-_PLAN.md plain plans get migrated ──────────────────────
# Regression for the catchall loop that covers kebab-case plans (e.g.
# cross-platform-hooks.md) and SCREAMING_SNAKE_CASE plans without the
# _PLAN suffix (e.g. EXECUTION_MODES.md). Without the catchall, ~35
# zskills plan files would be left under plans/ (Phase 6 self-migration
# surfaced the gap).
case_12_plain_plans_catchall() {
  local D="$TEST_OUT/paths-migration-fixture-12"
  init_repo "$D"
  mkdir -p "$D/plans"
  # Mix of patterns: matches old _PLAN, matches CANARY, kebab-case, and
  # SCREAMING_SNAKE without _PLAN.
  echo "FOO plan body" > "$D/plans/FOO_PLAN.md"
  echo "kebab plan body" > "$D/plans/cross-platform-hooks.md"
  echo "screaming plan body" > "$D/plans/EXECUTION_MODES.md"
  echo "canary body" > "$D/plans/CANARY1_HAPPY.md"
  write_config "$D"

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 12: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  # Sub-assertion: plans/ has no remaining *.md files.
  local leftover
  leftover=$(ls "$D"/plans/*.md 2>/dev/null | wc -l)
  if [ "$leftover" -eq 0 ]; then
    pass "case 12: plans/*.md all moved (no leftovers)"
  else
    fail "case 12: plans/*.md still present" "$(ls "$D"/plans/*.md 2>&1)"
  fi

  # Sub-assertion: each expected destination exists under docs/plans/.
  local missing=()
  for f in FOO_PLAN.md cross-platform-hooks.md EXECUTION_MODES.md \
           CANARY1_HAPPY.md; do
    [ -e "$D/docs/plans/$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    pass "case 12: all 4 plans landed under docs/plans/"
  else
    fail "case 12: missing destinations" "${missing[*]}"
  fi

  # Sub-assertion: manifest lists all 4 source paths.
  if [ ! -f "$D/.pre-paths-migration" ]; then
    fail "case 12: .pre-paths-migration absent" "manifest not written"
    return
  fi
  local manifest_misses=0
  for src in plans/FOO_PLAN.md plans/cross-platform-hooks.md \
             plans/EXECUTION_MODES.md plans/CANARY1_HAPPY.md; do
    if ! grep -qF "$(printf '%s\t' "$src")" "$D/.pre-paths-migration"; then
      manifest_misses=$((manifest_misses + 1))
    fi
  done
  if [ "$manifest_misses" -eq 0 ]; then
    pass "case 12: manifest lists all 4 moves"
  else
    fail "case 12: manifest missing entries" \
      "$manifest_misses missing; manifest=$(cat "$D/.pre-paths-migration")"
  fi
}

# ─── Case 13: cross_ref_rewrite preserves migration-doc lines (PR #211 fix) ─
# Regression test for the spec-corruption bug found post-Phase-6:
# the original 4-enclosure rule blindly rewrote tokens inside instruction
# prose ("Replace `plans/X.md` with ...") and bash fences documenting the
# migration's own `git mv plans/X.md ...` command. Damaged 13 sites in
# ZSKILLS_PATH_CONFIG.md alone. This case fixtures every shape of
# migration-doc context and asserts the legacy form is PRESERVED.
case_13_cross_ref_rewrite_migration_doc_guard() {
  local D="$TEST_OUT/paths-migration-fixture-13"
  init_repo "$D"
  write_config "$D"
  mkdir -p "$D/plans"

  # Active plan (so cross_ref_rewrite runs on it). Mix of:
  #  (a) lines that SHOULD be rewritten (real cross-refs)
  #  (b) lines that MUST be preserved (migration-doc context)
  cat > "$D/plans/MIXED_REFS_PLAN.md" <<'PLAN'
---
title: Mixed Refs Plan
status: active
---

# Plan

## Real cross-refs (should be REWRITTEN)

- See [the canary](plans/CANARY1_HAPPY.md) for happy path.
- Run `/run-plan plans/THERMAL_DOMAIN.md finish auto` to ship it.
- Backticked: `plans/FOO_PLAN.md` is the next thing.

## Migration-doc context (must be PRESERVED — legacy form intentional)

- Replace each occurrence of `plans/QE_ISSUES.md` with `$ZSKILLS_ISSUES_DIR/QE_ISSUES.md`.
- The bash fence below documents the migration's own command:

```bash
if [ -e plans/PLAN_INDEX.md ]; then
  git mv plans/PLAN_INDEX.md .zskills/audit/PLAN_INDEX.md
  echo "moved: plans/PLAN_INDEX.md to .zskills/audit/PLAN_INDEX.md"
fi
```

- Critical: `plans/SPRINT_REPORT.md` (wrong path) — old skill hardcoded this.
- MATCH/NON-MATCH table:
  | `[See PLAN_X](plans/PLAN_X.md)` | MATCH (markdown link) gives `[See PLAN_X](docs/plans/PLAN_X.md)` |
- WARN format example: `WARN docs/plans/OLD.md:42: legacy token 'plans/OTHER.md' preserved`.
PLAN

  ( cd "$D" && git add -A && git commit -q -m "fixture init" )

  # Run migration via the standard helper (sets $PORTABLE).
  run_migrate "$D" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 13: migration exited non-zero" "rc=$rc"
    return
  fi

  local out="$D/docs/plans/MIXED_REFS_PLAN.md"
  if [ ! -f "$out" ]; then
    fail "case 13: post-migration plan absent" "expected $out"
    return
  fi

  # (a) Real cross-refs SHOULD have been rewritten.
  if grep -q '\[the canary\](docs/plans/CANARY1_HAPPY.md)' "$out"; then
    pass "case 13: markdown link real-cross-ref REWRITTEN"
  else
    fail "case 13: markdown link should be rewritten to docs/plans/" "$(grep -F 'the canary' "$out")"
  fi
  if grep -qE '/run-plan[[:space:]]+docs/plans/THERMAL_DOMAIN\.md' "$out"; then
    pass "case 13: slash-command real-cross-ref REWRITTEN"
  else
    fail "case 13: slash-command should be rewritten" "$(grep -F THERMAL_DOMAIN "$out")"
  fi
  if grep -q '`docs/plans/FOO_PLAN.md`' "$out"; then
    pass "case 13: backticked real-cross-ref REWRITTEN"
  else
    fail "case 13: backtick real-cross-ref should be rewritten" "$(grep -F FOO_PLAN "$out")"
  fi

  # (b) Migration-doc context MUST be preserved (legacy form intact).
  if grep -qF '`plans/QE_ISSUES.md`' "$out"; then
    pass "case 13: 'Replace .plans/X.md.' instruction prose PRESERVED"
  else
    fail "case 13: instruction prose was incorrectly rewritten" "$(grep -F QE_ISSUES "$out")"
  fi
  if grep -qE 'git mv plans/PLAN_INDEX\.md \.zskills/audit/PLAN_INDEX\.md' "$out"; then
    pass "case 13: 'git mv plans/X.md ...' bash fence PRESERVED"
  else
    fail "case 13: git mv command was incorrectly rewritten" "$(grep -F 'git mv' "$out")"
  fi
  if grep -qE 'moved: plans/PLAN_INDEX\.md' "$out"; then
    pass "case 13: migration-stdout 'moved:' line PRESERVED"
  else
    fail "case 13: 'moved:' line was incorrectly rewritten" "$(grep -F 'moved:' "$out")"
  fi
  if grep -qF '`plans/SPRINT_REPORT.md` (wrong path)' "$out"; then
    pass "case 13: '(wrong path)' annotation PRESERVED"
  else
    fail "case 13: '(wrong path)' line was incorrectly rewritten" "$(grep -F 'wrong path' "$out")"
  fi
  if grep -qE 'PLAN_X\]\(plans/PLAN_X\.md\)' "$out"; then
    pass "case 13: MATCH-table 'before' column PRESERVED"
  else
    fail "case 13: MATCH-table before column was incorrectly rewritten" "$(grep -F 'PLAN_X' "$out")"
  fi
  if grep -qF "legacy token 'plans/OTHER.md'" "$out"; then
    pass "case 13: WARN-format example PRESERVED"
  else
    fail "case 13: WARN-format example was incorrectly rewritten" "$(grep -F 'legacy token' "$out")"
  fi

  cd "$REPO_ROOT" || true
  rm -rf -- "$D"
}

# ─── Case 14: partial — plans_dir + issues_dir set, reports_dir absent ─────
# Net-new for REPORTS_DIR_MIGRATION.md (DA-5 + AC-P.8 + AC-P.12). Primary
# regression for the d/d-bis trailing-comma awk extension: pre-migration
# config has the LAST output-block key (issues_dir) with NO trailing comma;
# injecting reports_dir after it must add a comma to the issues_dir line.
case_14_partial_reports_missing() {
  local D="$TEST_OUT/paths-migration-fixture-14"
  init_repo "$D"
  mkdir -p "$D/plans"
  echo "BAZ plan body" > "$D/plans/BAZ_PLAN.md"
  # Pre-set BOTH plans_dir + issues_dir with custom values; reports_dir
  # is intentionally absent (the d-bis edge case).
  write_config "$D" "stash" ".zskills/issues"

  local out rc
  out=$(run_migrate "$D" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "case 14: migrate-paths.sh exit code" "rc=$rc out=$out"
    return
  fi

  local cfg_body
  cfg_body=$(cat "$D/.claude/zskills-config.json")

  # (1) All three keys present.
  if echo "$cfg_body" | grep -q '"plans_dir"[[:space:]]*:[[:space:]]*"stash"' \
     && echo "$cfg_body" | grep -q '"issues_dir"[[:space:]]*:[[:space:]]*"\.zskills/issues"' \
     && echo "$cfg_body" | grep -q '"reports_dir"[[:space:]]*:[[:space:]]*"docs/reports"'; then
    pass "case 14: all 3 keys present (preserved custom values + injected default reports_dir)"
  else
    fail "case 14: missing or mutated keys" "$cfg_body"
  fi

  # (2) Output is VALID JSON — the load-bearing trailing-comma check.
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$D/.claude/zskills-config.json" 2>/dev/null; then
    pass "case 14: post-migration config parses as valid JSON (trailing-comma policy correct)"
  else
    fail "case 14: config is not valid JSON" "$cfg_body"
  fi
}

# ─── Case 15: partial-failure recovery — config-write failure aborts cleanly ─
# Regression for #394: pre-fix, the manifest was written BEFORE the config
# keys, so a Step 10 awk failure left the consumer permanently stranded
# (manifest on disk → re-run hit idempotency guard at Step 1 and exited 0
# while output.plans_dir was never written → helper fell back to legacy
# `plans/`, now empty). Post-fix, config write runs FIRST: an awk failure
# aborts with NO manifest, NO moved files. Re-run after fixing the config
# completes fully. Third run is an idempotent no-op.
case_15_partial_failure_recovery() {
  local D="$TEST_OUT/paths-migration-fixture-15"
  init_repo "$D"
  # Malformed config — missing closing brace breaks awk's outer-brace
  # locator in the no-output-object branch (write_output_block returns 2).
  mkdir -p "$D/.claude"
  printf '{\n  "project_name": "fixture"\n' > "$D/.claude/zskills-config.json"
  mkdir -p "$D/plans"
  echo "# test plan" > "$D/plans/SOME_PLAN.md"

  # Attempt 1 — must fail without moving files or writing manifest.
  local out1 rc1
  out1=$(run_migrate "$D" 2>&1); rc1=$?
  if [ "$rc1" -ne 0 ]; then
    pass "case 15: malformed config aborts migration (rc=$rc1)"
  else
    fail "case 15: malformed config should abort" "rc=$rc1 out=$out1"
    return
  fi
  if [ ! -f "$D/.pre-paths-migration" ]; then
    pass "case 15: NO manifest written on abort (re-runnable state preserved)"
  else
    fail "case 15: manifest written despite abort — strands consumer" \
      "$(cat "$D/.pre-paths-migration")"
  fi
  if [ -f "$D/plans/SOME_PLAN.md" ]; then
    pass "case 15: plan still in plans/ on abort (files not moved)"
  else
    fail "case 15: plan moved despite config-write failure" \
      "$(find "$D" -name SOME_PLAN.md 2>&1)"
  fi
  if [ ! -f "$D/docs/plans/SOME_PLAN.md" ]; then
    pass "case 15: docs/plans/SOME_PLAN.md absent on abort"
  else
    fail "case 15: plan moved to docs/plans/ despite config-write failure" \
      "$(ls "$D/docs/plans" 2>&1)"
  fi

  # Fix the config (multi-line so write_output_block's no-output-object
  # branch can locate the outer closing brace).
  printf '{\n  "project_name": "fixture"\n}\n' > "$D/.claude/zskills-config.json"

  # Attempt 2 — succeeds, manifest written, files moved.
  local out2 rc2
  out2=$(run_migrate "$D" 2>&1); rc2=$?
  if [ "$rc2" -eq 0 ]; then
    pass "case 15: post-fix re-run completes successfully (rc=0)"
  else
    fail "case 15: post-fix re-run failed" "rc=$rc2 out=$out2"
    return
  fi
  if [ -f "$D/.pre-paths-migration" ]; then
    pass "case 15: manifest written after successful re-run"
  else
    fail "case 15: manifest missing after successful re-run" "no manifest"
  fi
  if [ -f "$D/docs/plans/SOME_PLAN.md" ]; then
    pass "case 15: plan moved to docs/plans/ after successful re-run"
  else
    fail "case 15: plan did not move" "$(find "$D" -name SOME_PLAN.md 2>&1)"
  fi
  if grep -q '"output"' "$D/.claude/zskills-config.json"; then
    pass "case 15: config gained output keys after successful re-run"
  else
    fail "case 15: config missing output keys" \
      "$(cat "$D/.claude/zskills-config.json")"
  fi

  # Attempt 3 — idempotency guard fires, no-op.
  local out3 rc3
  out3=$(run_migrate "$D" 2>&1); rc3=$?
  if [ "$rc3" -eq 0 ] && echo "$out3" | grep -q "already migrated"; then
    pass "case 15: third run is idempotent no-op (\"already migrated\")"
  else
    fail "case 15: third run did not no-op" "rc=$rc3 out=$out3"
  fi
}

# ─── Run ──────────────────────────────────────────────────────────────────
echo "Running tests/test-update-zskills-paths-migration.sh"
case_1_legacy_only
case_2_preconfigured
case_3_idempotent
case_4_empty
case_5_customized_stub
case_6_cross_ref_rewrite
case_7_canary_self_invocation
case_8_completed_noncanary_warn
case_9_hook_rerender_gitignore
case_10_rewrite_only_recovery
case_11_chmod_fallback
case_12_plain_plans_catchall
case_13_cross_ref_rewrite_migration_doc_guard
case_14_partial_reports_missing
case_15_partial_failure_recovery

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
