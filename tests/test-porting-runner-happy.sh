#!/bin/bash
# tests/test-porting-runner-happy.sh — happy-path behavioral matrix for the
# unified Codex porting runner (CODEX_PORT_PLAN Phase 2, WI 2.1). No real
# codex binary is required — every run uses tests/mocks/fake-codex.sh via
# --codex-bin.
#
# Pins: single-chunk success (summary.json fields + argv assertions incl.
# "Do not invoke zskills-runner.sh again"); multi-chunk to completion (fresh
# child per chunk, argv-log count, NO resume token in finish-auto argv);
# re-entry after interruption (durable state, idempotent Step-0 semantics);
# finish-auto mid-run stop (fake-codex mid-run-stop writes the stop marker
# DURING chunk 1 → exit 31 before chunk 2 — the codex fork's write-only
# stop-marker bug, pinned); streaming (child output appears live on the
# parent stdout); frontmatter `status: complete` short-circuit; checkbox
# tracker format; stable tracking id across chunks + env export visible to
# the child.
#
# One pass/fail per ENUMERATED case; the case list is printed up front and
# the Results: count equals the enumerated case count (no external frozen
# integer).

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-runner-happy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Env test overrides (spec change 15) — generous defaults so a loaded
# parallel test host never trips a spurious timeout; the timeout CASES live
# in the failures suite with tiny per-case values.
export ZSKILLS_RUNNER_TIMEOUT_SECONDS=120
export ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS=60

# ── fixture helpers ──────────────────────────────────────────────────────────
DEFAULT_CONFIG='{
  "execution": { "landing": "cherry-pick" },
  "runner": { "max_chunks": 6, "log_dir": ".zskills/test-logs" }
}'

table_plan() {
  # table_plan <n-rows> — a progress-tracker table plan with n todo rows.
  local n="$1" i=1
  printf '# Example Plan\n\n## Progress Tracker\n\n'
  printf '| Phase | Status | Notes |\n| --- | --- | --- |\n'
  while [ "$i" -le "$n" ]; do
    printf '| %s. Fixture Phase | ⬜ Not Started | Runner test fixture. |\n' "$i"
    i=$((i + 1))
  done
}

make_fixture() {
  # make_fixture <dir> [plan-content] [config-json]
  local dir="$1" plan="${2:-}" config="${3:-$DEFAULT_CONFIG}"
  git init -q -b main "$dir"
  git -C "$dir" config user.email runner-test@example.test
  git -C "$dir" config user.name "Runner Test"
  mkdir -p "$dir/plans" "$dir/.agents"
  if [ -n "$plan" ]; then
    printf '%s\n' "$plan" > "$dir/plans/example.md"
  else
    table_plan 1 > "$dir/plans/example.md"
  fi
  printf '%s\n' "$config" > "$dir/.agents/zskills-config.json"
  printf '.zskills/\n' > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
}

run_runner() {
  # run_runner <fixture> <out> <err> [extra runner args...] — finish-auto run
  # against plans/example.md with the fake codex. Returns the runner rc.
  local f="$1" out="$2" err="$3"
  shift 3
  FAKE_CODEX_MODE="${MODE_OVERRIDE:-success}" bash "$RUNNER" run-plan plans/example.md finish auto \
    --repo "$f" --codex-bin "$FAKE" "$@" > "$out" 2> "$err"
}

run_dir_of() {
  # run_dir_of <runner-stdout-file> — the run_dir=<path> line the runner prints.
  sed -n 's/^run_dir=//p' "$1" | sed -n '1p'
}

summary_value() {
  # summary_value <summary.json> <key>
  "$PYTHON" - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data.get(sys.argv[2])
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
elif isinstance(value, (list, dict)):
    print(json.dumps(value))
else:
    print(value)
PY
}

expect_rc() {
  if [ "$2" -ne "$1" ]; then
    echo "expected rc $1, got rc $2"
    return 1
  fi
}

expect_in_file() {
  if ! grep -qE -e "$2" "$1"; then
    echo "missing pattern '$2' in $1; contents:"
    cat "$1"
    return 1
  fi
}

expect_last_stderr_reason() {
  # expect_last_stderr_reason <err-file> <reason> — the authoritative stop
  # classification is the runner's LAST stderr line.
  local last
  last=$(tail -n 1 "$1")
  if [ "$last" != "runner_stop_reason=$2" ]; then
    echo "expected final stderr line 'runner_stop_reason=$2', got '$last'"
    return 1
  fi
}

line_count() {
  wc -l < "$1" | tr -d ' '
}

# ── enumerated cases ─────────────────────────────────────────────────────────
CASES="
single-chunk-success
multi-chunk-fresh-children
re-entry-after-interruption
finish-auto-mid-run-stop
streaming-live-output
frontmatter-complete-short-circuit
checkbox-format-plan
stable-tracking-id-and-env-export
"

case_single_chunk_success() {
  local f="$WORK/f-single" out="$WORK/single.out" err="$WORK/single.err" rc rundir summary argvlog
  make_fixture "$f" "$(table_plan 1)"
  run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_last_stderr_reason "$err" complete || return 1

  rundir=$(run_dir_of "$out")
  [ -n "$rundir" ] && [ -d "$rundir" ] || { echo "run_dir not printed/absent: '$rundir'"; return 1; }
  summary="$rundir/chunk-001.summary.json"
  [ -f "$summary" ] || { echo "chunk-001.summary.json missing in $rundir"; return 1; }

  # summary.json field battery.
  [ "$(summary_value "$summary" exit_code)" = "0" ] || { echo "summary exit_code != 0"; return 1; }
  case "$(summary_value "$summary" thread_id)" in
    fake-thread-*) ;;
    *) echo "summary thread_id not captured from thread.started: '$(summary_value "$summary" thread_id)'"; return 1 ;;
  esac
  case "$(summary_value "$summary" token_usage)" in
    *input_tokens*) ;;
    *) echo "summary token_usage not parsed from turn.completed"; return 1 ;;
  esac
  [ "$(summary_value "$summary" validation_result)" = "passed" ] || { echo "summary validation_result != passed"; return 1; }
  [ "$(summary_value "$summary" validated_tracking_id)" = "example" ] || { echo "summary validated_tracking_id != example"; return 1; }
  [ "$(summary_value "$summary" gate_result)" = "passed" ] || { echo "summary gate_result != passed"; return 1; }
  [ "$(summary_value "$summary" progress_signals)" != "[]" ] || { echo "summary progress_signals empty"; return 1; }
  [ "$(summary_value "$summary" runner_stop_reason)" = "complete" ] || { echo "summary runner_stop_reason != complete"; return 1; }

  # argv assertions: the forensic argv.json AND the child-side argv.log both
  # carry the RUNNER-MANAGED CHUNK contract line "Do not invoke
  # zskills-runner.sh again"; the fresh finish-auto call carries no resume.
  expect_in_file "$rundir/chunk-001.argv.json" 'zskills-runner.sh again' || return 1
  if grep -qE '"resume"' "$rundir/chunk-001.argv.json"; then
    echo "finish-auto argv.json contains a resume token"
    return 1
  fi
  argvlog="$f/.zskills/fake-codex/argv.log"
  [ -f "$argvlog" ] || { echo "fake-codex argv.log missing"; return 1; }
  [ "$(line_count "$argvlog")" = "1" ] || { echo "expected exactly 1 child invocation, got $(line_count "$argvlog")"; return 1; }
  expect_in_file "$argvlog" 'Do not invoke zskills-runner.sh again' || return 1
}

case_multi_chunk_fresh_children() {
  local f="$WORK/f-multi" out="$WORK/multi.out" err="$WORK/multi.err" rc rundir argvlog n
  make_fixture "$f" "$(table_plan 3)"
  run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_last_stderr_reason "$err" complete || return 1

  # One FRESH child per chunk: three invocations, zero resume tokens.
  argvlog="$f/.zskills/fake-codex/argv.log"
  n=$(line_count "$argvlog")
  [ "$n" = "3" ] || { echo "expected 3 child invocations (one per chunk), got $n"; return 1; }
  if grep -q 'resume' "$argvlog"; then
    echo "finish-auto argv.log contains a resume token:"
    cat "$argvlog"
    return 1
  fi
  rundir=$(run_dir_of "$out")
  local c
  for c in 001 002 003; do
    [ -f "$rundir/chunk-$c.summary.json" ] || { echo "chunk-$c.summary.json missing"; return 1; }
    [ "$(summary_value "$rundir/chunk-$c.summary.json" validation_result)" = "passed" ] \
      || { echo "chunk-$c validation_result != passed"; return 1; }
  done
  # Plan fully done.
  if grep -q '⬜' "$f/plans/example.md"; then
    echo "plan still has todo rows after completion"
    return 1
  fi
}

case_re_entry_after_interruption() {
  local f="$WORK/f-reentry" out1="$WORK/reentry1.out" err1="$WORK/reentry1.err"
  local out2="$WORK/reentry2.out" err2="$WORK/reentry2.err" rc done_rows
  make_fixture "$f" "$(table_plan 2)"

  # Run 1 — interrupted after one phase (max-chunks 1 exhausts the loop and
  # exits, leaving DURABLE state: half-done plan, handoff marker, report).
  run_runner "$f" "$out1" "$err1" --max-chunks 1
  rc=$?
  expect_rc 30 "$rc" || { cat "$err1"; return 1; }
  done_rows=$(grep -c '✅ Done' "$f/plans/example.md")
  [ "$done_rows" = "1" ] || { echo "expected 1 done row after interrupted run, got $done_rows"; return 1; }
  [ -f "$f/.zskills/tracking/run-plan.example/handoff.run-plan.example" ] \
    || { echo "handoff marker missing after interrupted run"; return 1; }

  # Run 2 — fresh runner invocation re-enters on the durable state (the
  # child's idempotent Step-0 semantics: the already-Done phase is not
  # redone) and drives the plan to completion.
  run_runner "$f" "$out2" "$err2"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err2"; return 1; }
  expect_last_stderr_reason "$err2" complete || return 1
  done_rows=$(grep -c '✅ Done' "$f/plans/example.md")
  [ "$done_rows" = "2" ] || { echo "expected 2 done rows after re-entry run, got $done_rows"; return 1; }
  # Exactly ONE chunk per run: the re-entry resumed from durable state
  # instead of redoing phase 1 (2 total child invocations, both fresh).
  [ "$(line_count "$f/.zskills/fake-codex/argv.log")" = "2" ] \
    || { echo "expected 2 total child invocations across both runs, got $(line_count "$f/.zskills/fake-codex/argv.log")"; return 1; }
  # Final markers written on completion; handoff removed.
  [ -f "$f/.zskills/tracking/run-plan.example/fulfilled.run-plan.example" ] \
    || { echo "fulfilled.run-plan.example missing after completion"; return 1; }
  if [ -f "$f/.zskills/tracking/run-plan.example/handoff.run-plan.example" ]; then
    echo "stale handoff marker not removed at completion"
    return 1
  fi
}

case_finish_auto_mid_run_stop() {
  local f="$WORK/f-midstop" out="$WORK/midstop.out" err="$WORK/midstop.err" rc rundir
  make_fixture "$f" "$(table_plan 2)"
  # mid-run-stop: chunk 1 makes real progress AND writes the runner's stop
  # marker DURING the chunk. The loop must honor it BEFORE chunk 2 (exit 31)
  # — the codex fork's original write-only stop-marker bug, pinned.
  MODE_OVERRIDE=mid-run-stop run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 31 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'stop marker honored' || return 1
  expect_last_stderr_reason "$err" stopped || return 1
  # Exactly ONE child ran — no chunk 2.
  [ "$(line_count "$f/.zskills/fake-codex/argv.log")" = "1" ] \
    || { echo "expected 1 child invocation before the stop, got $(line_count "$f/.zskills/fake-codex/argv.log")"; return 1; }
  rundir=$(run_dir_of "$out")
  if [ -f "$rundir/chunk-002.summary.json" ]; then
    echo "chunk 2 ran despite the stop marker"
    return 1
  fi
  # Chunk 1's progress was validated before the stop was honored.
  [ "$(summary_value "$rundir/chunk-001.summary.json" validation_result)" = "passed" ] \
    || { echo "chunk-001 validation_result != passed"; return 1; }
}

case_streaming_live_output() {
  local f="$WORK/f-stream" out="$WORK/stream.out" err="$WORK/stream.err" rc rundir
  make_fixture "$f" "$(table_plan 1)"
  run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  # STREAM (spec change 1): child output appears on the PARENT's stdout —
  # $out captured the runner's stdout, and the child's JSONL events are in
  # it, not only in the chunk stdout file.
  expect_in_file "$out" '"type":"thread.started"' || { echo "child thread.started not streamed to parent stdout"; return 1; }
  expect_in_file "$out" '"type":"item.completed"' || { echo "child item.completed not streamed to parent stdout"; return 1; }
  # ... AND captured to chunk-NNN.stdout.txt (tee, not redirect).
  rundir=$(run_dir_of "$out")
  expect_in_file "$rundir/chunk-001.stdout.txt" '"type":"item.completed"' || return 1
}

case_frontmatter_complete_short_circuit() {
  local f="$WORK/f-fmdone" out="$WORK/fmdone.out" err="$WORK/fmdone.err" rc
  make_fixture "$f" "$(printf -- '---\nstatus: complete\n---\n# Done Plan\n\n## Progress Tracker\n\n| Phase | Status | Notes |\n| --- | --- | --- |\n| 1. Fixture Phase | ✅ Done | already done |')"
  run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_last_stderr_reason "$err" complete || return 1
  # Authoritative terminal signal: NO child was ever invoked.
  if [ -e "$f/.zskills/fake-codex/argv.log" ]; then
    echo "frontmatter-complete plan still invoked a child:"
    cat "$f/.zskills/fake-codex/argv.log"
    return 1
  fi
}

case_checkbox_format_plan() {
  local f="$WORK/f-checkbox" out="$WORK/checkbox.out" err="$WORK/checkbox.err" rc boxes
  make_fixture "$f" "$(printf -- '# Checkbox Plan\n\n## Work Items\n\n- [ ] first unit\n- [ ] second unit')"
  run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_last_stderr_reason "$err" complete || return 1
  # Both boxes flipped; one chunk per box.
  boxes=$(grep -c -- '- \[x\]' "$f/plans/example.md")
  [ "$boxes" = "2" ] || { echo "expected 2 checked boxes, got $boxes"; return 1; }
  if grep -q -- '- \[ \]' "$f/plans/example.md"; then
    echo "unchecked boxes remain after completion"
    return 1
  fi
  [ "$(line_count "$f/.zskills/fake-codex/argv.log")" = "2" ] \
    || { echo "expected 2 child invocations, got $(line_count "$f/.zskills/fake-codex/argv.log")"; return 1; }
}

case_stable_tracking_id_and_env_export() {
  local f="$WORK/f-stable" out="$WORK/stable.out" err="$WORK/stable.err" rc envlog tdir
  make_fixture "$f" "$(table_plan 2)"
  run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }

  # Env export visible to the child (spec change 4): both chunks saw the
  # exported ZSKILLS_PIPELINE_ID / ZSKILLS_TRACKING_ID, with the SAME stable
  # values in every chunk.
  envlog="$f/.zskills/fake-codex/env.log"
  [ -f "$envlog" ] || { echo "fake-codex env.log missing"; return 1; }
  [ "$(line_count "$envlog")" = "2" ] || { echo "expected 2 env.log lines, got $(line_count "$envlog")"; return 1; }
  [ "$(sort -u "$envlog" | wc -l | tr -d ' ')" = "1" ] \
    || { echo "env export not stable across chunks:"; cat "$envlog"; return 1; }
  expect_in_file "$envlog" '^ZSKILLS_PIPELINE_ID=run-plan\.example ZSKILLS_TRACKING_ID=example$' || return 1

  # Stable tracking id across chunks: ONE pipeline dir, every marker named
  # with the plan-basename-derived tid.
  tdir="$f/.zskills/tracking"
  [ "$(ls "$tdir" | wc -l | tr -d ' ')" = "1" ] \
    || { echo "expected exactly 1 pipeline dir, got:"; ls "$tdir"; return 1; }
  [ -d "$tdir/run-plan.example" ] || { echo "pipeline dir run-plan.example missing"; return 1; }
  local stray
  stray=$(ls "$tdir/run-plan.example" | grep -cv '\.example')
  [ "$stray" = "0" ] || { echo "markers with a non-stable tracking id:"; ls "$tdir/run-plan.example"; return 1; }
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
