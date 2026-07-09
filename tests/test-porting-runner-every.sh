#!/bin/bash
# tests/test-porting-runner-every.sh — every-mode scheduler + durable-session
# behavioral matrix for the unified Codex porting runner (CODEX_PORT_PLAN
# Phase 2, WI 2.3). No real codex binary is required — every run uses
# tests/mocks/fake-codex.sh via --codex-bin.
#
# Pins: stop marker pre-seeded → exit 31 BEFORE fire 1 (STOP-IN-LOOP, spec
# change 2); stop honored between fires; the parse_schedule grammar matrix
# (`30m`, `4h`, `every hour`, `weekday at 9am`, invalid → refusal); `next`
# output (fire time + session id + last validation verdict); session created
# ONCE then N resumes with the SAME id; resume-mismatch error; session-lost
# hard stop (exit 32) with NO silent fresh-exec fallback (argv-log
# asserted); `auto` vs no-`auto` per-fire prompt difference.
#
# Fire intervals use the ZSKILLS_RUNNER_SCHEDULE_SECONDS test override —
# never real minutes-scale waits (the schedule expression itself is still
# parsed and validated).

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-runner-every.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export ZSKILLS_RUNNER_TIMEOUT_SECONDS=120
export ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS=60
# Default fire interval for the multi-fire cases: 1s (overridden per case
# where the scenario needs a wider between-fires window).
export ZSKILLS_RUNNER_SCHEDULE_SECONDS=1

# ── fixture helpers ──────────────────────────────────────────────────────────
DEFAULT_CONFIG='{
  "execution": { "landing": "cherry-pick" },
  "runner": { "max_chunks": 6, "log_dir": ".zskills/test-logs" }
}'

table_plan() {
  local n="$1" i=1
  printf '# Example Plan\n\n## Progress Tracker\n\n'
  printf '| Phase | Status | Notes |\n| --- | --- | --- |\n'
  while [ "$i" -le "$n" ]; do
    printf '| %s. Fixture Phase | ⬜ Not Started | Runner test fixture. |\n' "$i"
    i=$((i + 1))
  done
}

make_fixture() {
  # make_fixture <dir> [n-plan-rows]
  local dir="$1" rows="${2:-2}"
  git init -q -b main "$dir"
  git -C "$dir" config user.email runner-test@example.test
  git -C "$dir" config user.name "Runner Test"
  mkdir -p "$dir/plans" "$dir/.agents"
  table_plan "$rows" > "$dir/plans/example.md"
  printf '%s\n' "$DEFAULT_CONFIG" > "$dir/.agents/zskills-config.json"
  printf '.zskills/\n' > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
}

run_every() {
  # run_every <fixture> <out> <err> <schedule> [extra tokens/args...]
  local f="$1" out="$2" err="$3" sched="$4"
  shift 4
  FAKE_CODEX_MODE="${MODE_OVERRIDE:-success}" bash "$RUNNER" run-plan plans/example.md every "$sched" \
    "$@" --repo "$f" --codex-bin "$FAKE" > "$out" 2> "$err"
}

runner_status_value() {
  bash "$RUNNER" status plans/example.md --repo "$1" \
    | awk -F= -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }'
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
stop-pre-seeded-exit31-before-fire1
stop-honored-between-fires
parse-schedule-matrix
next-output-during-run
session-created-once-then-resumes
resume-mismatch-error
session-lost-exit32-no-fresh-exec
auto-vs-no-auto-prompt
"

case_stop_pre_seeded_exit31_before_fire1() {
  local f="$WORK/f-preseed" out="$WORK/preseed.out" err="$WORK/preseed.err" rc plan_key
  make_fixture "$f"
  plan_key=$(runner_status_value "$f" plan_key)
  [ -n "$plan_key" ] || { echo "could not resolve plan_key from status"; return 1; }
  mkdir -p "$f/.zskills/runner"
  printf 'pre-seeded stop\n' > "$f/.zskills/runner/$plan_key.stop"
  # STOP-IN-LOOP (spec change 2): the pre-seeded marker is honored with exit
  # 31 BEFORE fire 1 — never a refusal, never a first fire.
  run_every "$f" "$out" "$err" 30m
  rc=$?
  expect_rc 31 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'stop marker honored' || return 1
  expect_last_stderr_reason "$err" stopped || return 1
  if [ -e "$f/.zskills/fake-codex/argv.log" ]; then
    echo "a fire ran despite the pre-seeded stop marker:"
    cat "$f/.zskills/fake-codex/argv.log"
    return 1
  fi
}

case_stop_honored_between_fires() {
  local f="$WORK/f-between" out="$WORK/between.out" err="$WORK/between.err" rc
  make_fixture "$f" 3
  # mid-run-stop: fire 1 makes real progress AND writes the stop marker
  # DURING the fire; the loop must honor it before fire 2.
  MODE_OVERRIDE=mid-run-stop run_every "$f" "$out" "$err" 30m
  rc=$?
  expect_rc 31 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'stop marker honored' || return 1
  expect_last_stderr_reason "$err" stopped || return 1
  [ "$(line_count "$f/.zskills/fake-codex/argv.log")" = "1" ] \
    || { echo "expected exactly 1 fire before the stop, got $(line_count "$f/.zskills/fake-codex/argv.log")"; return 1; }
}

case_parse_schedule_matrix() {
  local f="$WORK/f-sched" out="$WORK/sched.out" err="$WORK/sched.err" rc got
  make_fixture "$f"

  # Valid grammar → --dry-run resolves and prints schedule_seconds.
  local expr expected
  for expr in "30m|1800" "4h|14400" "every hour|3600"; do
    expected="${expr##*|}"
    expr="${expr%|*}"
    bash "$RUNNER" run-plan plans/example.md every "$expr" --dry-run \
      --repo "$f" --codex-bin "$FAKE" > "$out" 2> "$err"
    rc=$?
    expect_rc 0 "$rc" || { echo "schedule '$expr' refused:"; cat "$err"; return 1; }
    got=$(sed -n 's/^schedule_seconds=//p' "$out" | sed -n '1p')
    [ "$got" = "$expected" ] || { echo "schedule '$expr': expected ${expected}s, got '$got'"; return 1; }
  done

  # weekday at 9am — value depends on wall clock; must be a positive integer
  # of at least a minute and at most 4 days (weekend + slack) away.
  bash "$RUNNER" run-plan plans/example.md every "weekday at 9am" --dry-run \
    --repo "$f" --codex-bin "$FAKE" > "$out" 2> "$err"
  rc=$?
  expect_rc 0 "$rc" || { echo "schedule 'weekday at 9am' refused:"; cat "$err"; return 1; }
  got=$(sed -n 's/^schedule_seconds=//p' "$out" | sed -n '1p')
  case "$got" in
    ''|*[!0-9]*) echo "'weekday at 9am' produced non-integer schedule_seconds '$got'"; return 1 ;;
  esac
  if [ "$got" -lt 60 ] || [ "$got" -gt 345600 ]; then
    echo "'weekday at 9am' schedule_seconds out of plausible range: $got"
    return 1
  fi

  # Invalid expression → refusal (exit 2) naming the unsupported schedule.
  bash "$RUNNER" run-plan plans/example.md every "every fortnight" --dry-run \
    --repo "$f" --codex-bin "$FAKE" > "$out" 2> "$err"
  rc=$?
  expect_rc 2 "$rc" || { echo "invalid schedule was not refused"; cat "$out"; return 1; }
  expect_in_file "$err" 'unsupported schedule expression' || return 1
  expect_last_stderr_reason "$err" refused || return 1
}

case_next_output_during_run() {
  local f="$WORK/f-next" out="$WORK/next.out" err="$WORK/next.err" rc pid
  local nextout="$WORK/next-cmd.out" tries session_id file_session
  make_fixture "$f" 6
  # A wide (15s) between-fires window so `next` can be queried mid-run.
  ZSKILLS_RUNNER_SCHEDULE_SECONDS=15 MODE_OVERRIDE=success \
    run_every "$f" "$out" "$err" 30m &
  pid=$!

  # Poll `next` until fire 1 has validated: session id present, a next fire
  # time scheduled, last validation verdict recorded.
  tries=0
  while :; do
    bash "$RUNNER" next plans/example.md --repo "$f" > "$nextout" 2>&1 || true
    if grep -q '^session_id=fake-thread-' "$nextout" \
       && grep -q '^next_fire=20' "$nextout" \
       && grep -q '^last_validation=passed$' "$nextout"; then
      break
    fi
    tries=$((tries + 1))
    if [ "$tries" -ge 90 ]; then
      echo "next never showed a fired+scheduled state; last output:"
      cat "$nextout"
      bash "$RUNNER" stop plans/example.md --repo "$f" > /dev/null 2>&1
      wait "$pid" 2>/dev/null
      return 1
    fi
    sleep 1
  done

  # `next` output pinned: fire time + session id + last validation verdict.
  expect_in_file "$nextout" '^session_id=fake-thread-' || return 1
  expect_in_file "$nextout" '^schedule=30m$' || return 1
  expect_in_file "$nextout" '^next_fire=20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$' || return 1
  expect_in_file "$nextout" '^last_validation=passed$' || return 1
  session_id=$(sed -n 's/^session_id=//p' "$nextout" | sed -n '1p')
  file_session=$(cat "$f/.zskills/runner/"*.session 2>/dev/null)
  [ "$session_id" = "$file_session" ] \
    || { echo "next session_id '$session_id' != persisted session '$file_session'"; return 1; }

  # `stop` subcommand: the sleeping loop honors the marker mid-wait.
  bash "$RUNNER" stop plans/example.md --repo "$f" > /dev/null 2>&1 \
    || { echo "stop subcommand failed"; return 1; }
  wait "$pid"
  rc=$?
  expect_rc 31 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'stop marker honored' || return 1
  expect_last_stderr_reason "$err" stopped || return 1
}

case_session_created_once_then_resumes() {
  local f="$WORK/f-sess" out="$WORK/sess.out" err="$WORK/sess.err" rc
  local argvlog session_id resumes
  make_fixture "$f" 3
  run_every "$f" "$out" "$err" 30m
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_last_stderr_reason "$err" complete || return 1
  expect_in_file "$out" 'durable session established: fake-thread-' || return 1

  argvlog="$f/.zskills/fake-codex/argv.log"
  [ "$(line_count "$argvlog")" = "3" ] || { echo "expected 3 fires, got $(line_count "$argvlog")"; return 1; }
  # Fire 1: FRESH exec (no resume subcommand token — anchored so prompt text
  # or fixture paths containing the word can never false-positive). Fires
  # 2..N: `exec resume <SAME id>`.
  if sed -n '1p' "$argvlog" | grep -q '^exec resume '; then
    echo "fire 1 unexpectedly used resume: $(sed -n '1p' "$argvlog")"
    return 1
  fi
  session_id=$(cat "$f/.zskills/runner/"*.session)
  [ -n "$session_id" ] || { echo "no persisted session id"; return 1; }
  resumes=$(grep -c "^exec resume $session_id " "$argvlog")
  [ "$resumes" = "2" ] \
    || { echo "expected 2 resume fires into session '$session_id', got $resumes:"; cat "$argvlog"; return 1; }
}

case_resume_mismatch_error() {
  local f="$WORK/f-mismatch" out="$WORK/mismatch.out" err="$WORK/mismatch.err" rc
  make_fixture "$f" 2
  # Fire 1 (fresh) succeeds and establishes the session; fire 2's resume is
  # rejected with the DISTINCT mismatch error → hard stop, exit 32.
  MODE_OVERRIDE=resume-mismatch run_every "$f" "$out" "$err" 30m
  rc=$?
  expect_rc 32 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'resume-mismatch' || return 1
  expect_in_file "$err" 'exec resume failed' || return 1
  expect_last_stderr_reason "$err" session-lost || return 1
}

case_session_lost_exit32_no_fresh_exec() {
  local f="$WORK/f-lost" out="$WORK/lost.out" err="$WORK/lost.err" rc argvlog
  make_fixture "$f" 2
  MODE_OVERRIDE=session-lost run_every "$f" "$out" "$err" 30m
  rc=$?
  # Session loss is a HARD STOP (exit 32, session-lost) — never a silent
  # fallback to a fresh exec, which would invisibly break the
  # one-durable-session contract.
  expect_rc 32 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'session not found' || return 1
  expect_in_file "$err" 'every-mode hard stop' || return 1
  expect_last_stderr_reason "$err" session-lost || return 1

  # argv-log proof: exactly 2 invocations — the fresh fire 1, then the
  # FAILED resume — and NOTHING after the loss (no silent fresh `exec`).
  argvlog="$f/.zskills/fake-codex/argv.log"
  [ "$(line_count "$argvlog")" = "2" ] \
    || { echo "expected exactly 2 invocations (fresh + failed resume), got $(line_count "$argvlog"):"; cat "$argvlog"; return 1; }
  if ! sed -n '2p' "$argvlog" | grep -q '^exec resume '; then
    echo "invocation 2 was not the resume attempt: $(sed -n '2p' "$argvlog")"
    return 1
  fi
  if ! tail -n 1 "$argvlog" | grep -q '^exec resume '; then
    echo "an invocation happened AFTER the failed resume (silent fresh-exec fallback):"
    cat "$argvlog"
    return 1
  fi
}

case_auto_vs_no_auto_prompt() {
  local f="$WORK/f-auto" out_auto="$WORK/auto.out" out_plain="$WORK/plain.out" err="$WORK/auto.err" rc
  make_fixture "$f"
  # `auto` changes ONLY the per-fire prompt text (pre-authorized autonomous
  # landing), never the validation ladder — assert the two prompt variants
  # via dry-run (which prints the resolved child argv incl. the prompt).
  bash "$RUNNER" run-plan plans/example.md every 30m auto --dry-run \
    --repo "$f" --codex-bin "$FAKE" > "$out_auto" 2> "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$out_auto" 'every_auto=1' || return 1
  expect_in_file "$out_auto" 'Landing authorization: pre-authorized \(auto\) — land without prompting\.' || return 1
  if grep -q 'not pre-authorized' "$out_auto"; then
    echo "auto prompt also carries the no-auto confirmation text"
    return 1
  fi

  bash "$RUNNER" run-plan plans/example.md every 30m --dry-run \
    --repo "$f" --codex-bin "$FAKE" > "$out_plain" 2> "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$out_plain" 'every_auto=0' || return 1
  expect_in_file "$out_plain" 'Landing authorization: not pre-authorized — prepare the landing evidence but request confirmation before merging\.' || return 1
  if grep -q 'land without prompting' "$out_plain"; then
    echo "no-auto prompt also carries the auto authorization text"
    return 1
  fi
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
