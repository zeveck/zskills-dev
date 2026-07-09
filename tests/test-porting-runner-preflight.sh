#!/bin/bash
# tests/test-porting-runner-preflight.sh — refusal/preflight + dry-run-purity
# suite for the unified Codex porting runner (CODEX_PORT_PLAN Phase 1,
# WI 1.5). No real codex binary is required — run cases use
# tests/mocks/fake-codex.sh via --codex-bin.
#
# One pass/fail per ENUMERATED case; the case list is printed up front and
# the Results: count equals the enumerated case count (no external frozen
# integer). Each case's detail log is printed only on failure.
#
# The deep behavioral matrix (happy paths / failure modes / every-mode)
# lands in Phase 2 — this suite pins the refusal battery, the exit-code
# table, claim semantics, and dry-run purity.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/porting/zskills-runner.sh"
FAKE="$REPO_ROOT/tests/mocks/fake-codex.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python || true)}"
if [ -z "$PYTHON" ]; then
  echo "SKIP: no python3/python available (required by the runner)" >&2
  echo "Results: 0 passed, 0 failed (of 0)"
  exit 0
fi

if [ ! -f "$RUNNER" ] || [ ! -f "$FAKE" ]; then
  fail "runner or fake-codex not found ($RUNNER / $FAKE)"
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $((PASS_COUNT + FAIL_COUNT)))"
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-runner-preflight.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Short timeouts for the run-to-completion cases (env test overrides pinned
# by spec change 15).
export ZSKILLS_RUNNER_TIMEOUT_SECONDS=120
export ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS=60

# ── fixture helpers ──────────────────────────────────────────────────────────
DEFAULT_CONFIG='{
  "execution": { "landing": "cherry-pick" },
  "runner": { "max_chunks": 3, "log_dir": ".zskills/test-logs" }
}'

make_fixture() {
  # make_fixture <dir> [gitignore-content] [config-json]
  local dir="$1" ignore="${2:-.zskills/}" config="${3:-$DEFAULT_CONFIG}"
  git init -q -b main "$dir"
  git -C "$dir" config user.email runner-test@example.test
  git -C "$dir" config user.name "Runner Test"
  mkdir -p "$dir/plans" "$dir/.agents"
  cat > "$dir/plans/example.md" <<'MD'
# Example Plan

## Progress Tracker

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Fixture Phase | ⬜ Not Started | Runner test fixture. |
MD
  printf '%s\n' "$config" > "$dir/.agents/zskills-config.json"
  printf '%s\n' "$ignore" > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
}

runner_status_value() {
  # runner_status_value <repo> <key> [plan]
  bash "$RUNNER" status "${3:-plans/example.md}" --repo "$1" \
    | awk -F= -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }'
}

expect_rc() {
  # expect_rc <expected> <actual>
  if [ "$2" -ne "$1" ]; then
    echo "expected rc $1, got rc $2"
    return 1
  fi
}

expect_in_file() {
  # expect_in_file <file> <grep -E pattern> (-e form so patterns may start
  # with dashes, e.g. the refused --dangerously-* flag)
  if ! grep -qE -e "$2" "$1"; then
    echo "missing pattern '$2' in $1; contents:"
    cat "$1"
    return 1
  fi
}

# ── enumerated cases ─────────────────────────────────────────────────────────
CASES="
help-exit-code-table
non-git-repo
missing-codex
dangerous-bypass-flag
dangerous-bypass-codex-arg
lock-contention-owner-in-error
cherry-pick-residue
merge-residue
rebase-residue
unresolved-conflicts
stash-residue
stale-worktree-registry
tracking-not-ignored
direct-refusal
direct-dirty
direct-runner-residue
pr-stale-root-not-worktree
pr-stale-root-foreign-repo
pr-stale-root-missing-plan
config-precedence
cross-lane-config-conflict
same-basename-disambiguation
narrative-plan-refusal
claim-foreign-held
claim-self-reentry-success
dry-run-purity
fake-codex-fail-fast-99
"

case_help_exit_code_table() {
  local out="$WORK/help.out"
  bash "$RUNNER" --help > "$out" 2>&1 || { echo "--help exited nonzero"; return 1; }
  expect_in_file "$out" 'finish auto \[direct\|cherry-pick\|pr\]' || return 1
  expect_in_file "$out" 'every <SCHEDULE> \[auto\]' || return 1
  local code
  for code in 2 20 21 22 23 24 25 26 30 31 32 124 125; do
    expect_in_file "$out" "^  $code +" || { echo "exit code $code missing from --help table"; return 1; }
  done
}

case_non_git_repo() {
  local dir="$WORK/notgit" err="$WORK/notgit.err" rc
  mkdir -p "$dir"
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$dir" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'not a git worktree' || return 1
  expect_in_file "$err" 'runner_stop_reason=refused' || return 1
}

case_missing_codex() {
  local f="$WORK/f-missing-codex" err="$WORK/missing-codex.err" rc
  make_fixture "$f"
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$WORK/absent/codex" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'codex executable not found' || return 1
}

case_dangerous_bypass_flag() {
  local f="$WORK/f-danger1" err="$WORK/danger1.err" rc
  make_fixture "$f"
  bash "$RUNNER" run-plan plans/example.md finish auto \
    --dangerously-bypass-approvals-and-sandbox --repo "$f" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  # AC: stderr names the refused flag.
  expect_in_file "$err" '\-\-dangerously-bypass-approvals-and-sandbox' || return 1
  expect_in_file "$err" 'refused' || return 1
}

case_dangerous_bypass_codex_arg() {
  local f="$WORK/f-danger2" err="$WORK/danger2.err" rc
  make_fixture "$f"
  bash "$RUNNER" run-plan plans/example.md finish auto \
    --codex-arg --dangerously-bypass-approvals-and-sandbox --repo "$f" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" '\-\-dangerously-bypass-approvals-and-sandbox' || return 1
  expect_in_file "$err" 'codex-arg|smuggled' || return 1
}

case_lock_contention_owner_in_error() {
  local f="$WORK/f-lock" err="$WORK/lock.err" rc plan_key
  make_fixture "$f"
  plan_key=$(runner_status_value "$f" plan_key)
  [ -n "$plan_key" ] || { echo "could not resolve plan_key from status"; return 1; }
  mkdir -p "$f/.zskills/runner/$plan_key.lock"
  printf 'pid=424242\nstarted_at=2026-01-01T00:00:00Z\nplan=plans/example.md\n' \
    > "$f/.zskills/runner/$plan_key.lock/owner"
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'runner lock already exists' || return 1
  # Owner-file contents surfaced in the error.
  expect_in_file "$err" 'pid=424242' || return 1
}

residue_case() {
  # residue_case <fixture> <setup-cmd...> — shared body for git-residue cases.
  local f="$1" err="$2" pattern="$3" rc
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" "$pattern" || return 1
}

case_cherry_pick_residue() {
  local f="$WORK/f-cp-residue"
  make_fixture "$f"
  : > "$f/.git/CHERRY_PICK_HEAD"
  residue_case "$f" "$WORK/cp-residue.err" 'CHERRY_PICK_HEAD present'
}

case_merge_residue() {
  local f="$WORK/f-merge-residue"
  make_fixture "$f"
  : > "$f/.git/MERGE_HEAD"
  residue_case "$f" "$WORK/merge-residue.err" 'MERGE_HEAD present'
}

case_rebase_residue() {
  local f="$WORK/f-rebase-residue"
  make_fixture "$f"
  mkdir -p "$f/.git/rebase-merge"
  residue_case "$f" "$WORK/rebase-residue.err" 'rebase-merge present'
}

case_unresolved_conflicts() {
  local f="$WORK/f-conflicts"
  make_fixture "$f"
  # Build a real merge conflict, then clear MERGE_HEAD so the unmerged-index
  # check (diff-filter=U) is what fires, not the MERGE_HEAD residue check.
  git -C "$f" checkout -q -b side
  printf 'side change\n' >> "$f/plans/example.md"
  git -C "$f" commit -qam side
  git -C "$f" checkout -q main
  printf 'main change\n' >> "$f/plans/example.md"
  git -C "$f" commit -qam main
  git -C "$f" merge side > /dev/null 2>&1
  rm -f "$f/.git/MERGE_HEAD" "$f/.git/MERGE_MSG"
  residue_case "$f" "$WORK/conflicts.err" 'unresolved conflicts present'
}

case_stash_residue() {
  local f="$WORK/f-stash"
  make_fixture "$f"
  printf 'stash me\n' >> "$f/plans/example.md"
  git -C "$f" stash push -q
  residue_case "$f" "$WORK/stash.err" 'stash residue'
}

case_stale_worktree_registry() {
  local f="$WORK/f-stale-wt"
  make_fixture "$f"
  git -C "$f" worktree add -q -b tmp-branch "$WORK/stale-wt-dir" > /dev/null
  rm -rf "$WORK/stale-wt-dir"
  residue_case "$f" "$WORK/stale-wt.err" 'worktree-registry residue'
}

case_tracking_not_ignored() {
  local f="$WORK/f-tracking"
  make_fixture "$f" '# nothing ignored'
  mkdir -p "$f/.zskills/tracking"
  printf 'x\n' > "$f/.zskills/tracking/probe"
  residue_case "$f" "$WORK/tracking.err" 'not ignored by git'
}

DIRECT_CONFIG='{
  "execution": { "landing": "direct" },
  "runner": { "max_chunks": 3, "log_dir": ".zskills/test-logs" }
}'

case_direct_refusal() {
  local f="$WORK/f-direct1" err="$WORK/direct1.err" rc
  make_fixture "$f" '.zskills/' "$DIRECT_CONFIG"
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'direct landing is refused for unattended' || return 1
}

case_direct_dirty() {
  local f="$WORK/f-direct2" err="$WORK/direct2.err" rc
  make_fixture "$f" '.zskills/' "$DIRECT_CONFIG"
  printf 'dirty\n' > "$f/uncommitted.txt"
  bash "$RUNNER" run-plan plans/example.md finish auto --allow-direct-unattended \
    --repo "$f" --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'clean working tree' || return 1
}

case_direct_runner_residue() {
  local f="$WORK/f-direct3" err="$WORK/direct3.err" rc plan_key
  make_fixture "$f" '.zskills/' "$DIRECT_CONFIG"
  plan_key=$(runner_status_value "$f" plan_key)
  mkdir -p "$f/.zskills/runner"
  printf 'stale\n' > "$f/.zskills/runner/$plan_key.stop"
  bash "$RUNNER" run-plan plans/example.md finish auto --allow-direct-unattended \
    --repo "$f" --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'direct runner residue' || return 1
}

pr_config() {
  # PR-landing config with a per-case worktree parent dir.
  printf '{ "execution": { "landing": "pr" }, "runner": { "max_chunks": 3, "log_dir": ".zskills/test-logs", "worktree_parent_dir": "%s" } }' "$1"
}

case_pr_stale_root_not_worktree() {
  local f="$WORK/f-pr1" err="$WORK/pr1.err" rc parent="$WORK/wtparent1"
  make_fixture "$f" '.zskills/' "$(pr_config "$parent")"
  mkdir -p "$parent/$(basename "$f")-pr-example"
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'not a git worktree' || return 1
}

case_pr_stale_root_foreign_repo() {
  local f="$WORK/f-pr2" err="$WORK/pr2.err" rc parent="$WORK/wtparent2" foreign
  make_fixture "$f" '.zskills/' "$(pr_config "$parent")"
  foreign="$parent/$(basename "$f")-pr-example"
  make_fixture "$foreign"   # a DIFFERENT repo at the expected worktree path
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'different git repository' || return 1
}

case_pr_stale_root_missing_plan() {
  local f="$WORK/f-pr3" err="$WORK/pr3.err" rc parent="$WORK/wtparent3" wt
  make_fixture "$f" '.zskills/' "$(pr_config "$parent")"
  wt="$parent/$(basename "$f")-pr-example"
  mkdir -p "$parent"
  git -C "$f" worktree add -q -b feat-x "$wt" > /dev/null
  rm "$wt/plans/example.md"
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'missing the expected plan file' || return 1
}

case_config_precedence() {
  local f="$WORK/f-precedence" got_chunks got_config
  make_fixture "$f" '.zskills/' '{ "execution": { "landing": "cherry-pick" }, "runner": { "max_chunks": 7 } }'
  mkdir -p "$f/.claude"
  printf '{ "runner": { "max_chunks": 3 } }\n' > "$f/.claude/zskills-config.json"
  git -C "$f" add -A && git -C "$f" commit -q -m claude-config
  got_chunks=$(runner_status_value "$f" max_chunks)
  got_config=$(runner_status_value "$f" config)
  if [ "$got_chunks" != "7" ]; then
    echo "expected .agents config to win (max_chunks=7), got '$got_chunks'"
    return 1
  fi
  case "$got_config" in
    *.agents/zskills-config.json) ;;
    *) echo "expected active config to be .agents/zskills-config.json, got '$got_config'"; return 1 ;;
  esac
}

case_cross_lane_config_conflict() {
  local f="$WORK/f-conflict-cfg" err="$WORK/conflict-cfg.err" rc
  make_fixture "$f" '.zskills/' '{ "execution": { "landing": "pr" } }'
  mkdir -p "$f/.claude"
  printf '{ "execution": { "landing": "direct" } }\n' > "$f/.claude/zskills-config.json"
  git -C "$f" add -A && git -C "$f" commit -q -m conflicting-config
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'cross-lane config conflict on execution.landing' || return 1
}

case_same_basename_disambiguation() {
  local f="$WORK/f-basename" key1 key2 tid1 tid2
  make_fixture "$f"
  mkdir -p "$f/docs"
  cp "$f/plans/example.md" "$f/docs/example.md"
  git -C "$f" add -A && git -C "$f" commit -q -m second-plan
  key1=$(runner_status_value "$f" plan_key plans/example.md)
  key2=$(runner_status_value "$f" plan_key docs/example.md)
  tid1=$(runner_status_value "$f" tracking_id plans/example.md)
  tid2=$(runner_status_value "$f" tracking_id docs/example.md)
  [ -n "$key1" ] && [ -n "$key2" ] || { echo "plan_key resolution failed ('$key1' / '$key2')"; return 1; }
  if [ "$key1" = "$key2" ]; then
    echo "same-basename plans produced IDENTICAL plan_key '$key1' — locks/logs would collide"
    return 1
  fi
  if [ "$tid1" != "$tid2" ]; then
    echo "tracking_id should be basename-stable ('$tid1' vs '$tid2')"
    return 1
  fi
}

case_narrative_plan_refusal() {
  local f="$WORK/f-narrative" err="$WORK/narrative.err" rc
  make_fixture "$f"
  cat > "$f/plans/narrative.md" <<'MD'
# Narrative Plan

This plan is prose only. It describes an idea in flowing text with no
progress tracker of any recognized format, so the runner cannot derive a
mechanical completion signal from it.
MD
  git -C "$f" add -A && git -C "$f" commit -q -m narrative
  bash "$RUNNER" run-plan plans/narrative.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'narrative plan refused' || return 1
  expect_in_file "$err" 'no progress tracker' || return 1
}

write_claim() {
  # write_claim <fixture> <pipeline-id> — fixture per spec change 10: the
  # claim dir + a JSON metadata file naming a pipeline id.
  local f="$1" pid="$2"
  mkdir -p "$f/.zskills/claims/plan-example"
  printf '{ "pipeline_id": "%s", "writer": "test-fixture" }\n' "$pid" \
    > "$f/.zskills/claims/plan-example/claim.json"
}

case_claim_foreign_held() {
  local f="$WORK/f-claim-foreign" err="$WORK/claim-foreign.err" rc
  make_fixture "$f"
  write_claim "$f" "run-plan.some-other-pipeline"
  bash "$RUNNER" run-plan plans/example.md finish auto --repo "$f" \
    --codex-bin "$FAKE" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || return 1
  expect_in_file "$err" 'claim' || return 1
  expect_in_file "$err" 'run-plan.some-other-pipeline' || return 1
  # Never stolen: the foreign claim must survive the refusal.
  if [ ! -f "$f/.zskills/claims/plan-example/claim.json" ]; then
    echo "foreign claim was deleted by the refused runner"
    return 1
  fi
}

case_claim_self_reentry_success() {
  local f="$WORK/f-claim-self" out="$WORK/claim-self.out" err="$WORK/claim-self.err" rc
  make_fixture "$f"
  # Pre-seed OUR OWN pipeline id — acquire must succeed (ownership-aware
  # self-re-entry), and the full success run then completes end-to-end.
  write_claim "$f" "run-plan.example"
  FAKE_CODEX_MODE=success bash "$RUNNER" run-plan plans/example.md finish auto \
    --repo "$f" --codex-bin "$FAKE" > "$out" 2> "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'runner_stop_reason=complete' || return 1
  # Release at terminal stop: our claim is gone afterwards.
  if [ -d "$f/.zskills/claims/plan-example" ]; then
    echo "claim was not released at terminal stop"
    return 1
  fi
}

case_dry_run_purity() {
  local f="$WORK/f-dryrun" out="$WORK/dryrun.out" err="$WORK/dryrun.err" rc dirt
  make_fixture "$f"
  bash "$RUNNER" run-plan plans/example.md finish auto --dry-run --repo "$f" \
    > "$out" 2> "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  # Resolved child argv printed, containing `exec` and the prompt with the
  # RUNNER-MANAGED CHUNK contract.
  expect_in_file "$out" '^exec$' || return 1
  expect_in_file "$out" 'RUNNER-MANAGED CHUNK' || return 1
  # Zero tree mutation.
  dirt=$(git -C "$f" status --porcelain | wc -l | tr -d ' ')
  if [ "$dirt" != "0" ]; then
    echo "dry-run left $dirt dirty entries:"
    git -C "$f" status --porcelain
    return 1
  fi
  if [ -e "$f/.zskills" ]; then
    echo "dry-run created .zskills state"
    return 1
  fi
}

case_fake_codex_fail_fast_99() {
  local f="$WORK/f-fake99" err="$WORK/fake99.err" rc
  make_fixture "$f"
  # An UNPREPARED invocation (no FAKE_CODEX_MODE) must exit 99 loudly.
  env -u FAKE_CODEX_MODE bash "$FAKE" exec -C "$f" "prompt" 2> "$err"
  rc=$?
  expect_rc 99 "$rc" || return 1
  expect_in_file "$err" 'unprepared invocation' || return 1
  # An unknown mode is equally unprepared.
  FAKE_CODEX_MODE=definitely-not-a-mode bash "$FAKE" exec -C "$f" "prompt" 2> "$err"
  rc=$?
  expect_rc 99 "$rc" || return 1
  expect_in_file "$err" 'unknown FAKE_CODEX_MODE' || return 1
}

# ── driver ───────────────────────────────────────────────────────────────────
CASE_COUNT=0
for name in $CASES; do
  CASE_COUNT=$((CASE_COUNT + 1))
done
echo "Enumerated cases ($CASE_COUNT):"
for name in $CASES; do
  echo "  - $name"
done
echo ""

for name in $CASES; do
  fn="case_$(printf '%s' "$name" | tr '-' '_')"
  log="$WORK/case-$name.log"
  if "$fn" > "$log" 2>&1; then
    pass "$name"
  else
    fail "$name"
    sed 's/^/    /' "$log"
  fi
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed (of $CASE_COUNT)"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0
