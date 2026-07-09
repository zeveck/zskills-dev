#!/bin/bash
# tests/test-porting-runner-failures.sh — failure-taxonomy behavioral matrix
# for the unified Codex porting runner (CODEX_PORT_PLAN Phase 2, WI 2.2). No
# real codex binary is required — every run uses tests/mocks/fake-codex.sh
# via --codex-bin.
#
# Pins the mapped exit codes: 20 no-progress; 21 missing-handoff AND
# premature-final; 22 missing/malformed report AND stale-marker replay;
# 23 missing verifier markers AND missing tests-run AND
# claim-evidence-mismatch (schema mode); 24 terminal landing failure
# (.zskills/landed conflict / pr-failed hard-stop) with pr-ready re-entry;
# 25 dirty artifacts; 26 child-nonzero (raw child rc + stderr tail quoted
# from chunk-NNN.summary.json) AND sandbox-triage; 30 max-chunks; 124 wall
# timeout; 125 idle timeout; pr-wrong-tracking split-state. Plus the
# stderr-reason discipline sweep: for EVERY mapped exit code exercised, the
# FINAL stderr line carries the matching authoritative runner_stop_reason.
#
# Timeouts use the ZSKILLS_RUNNER_*_SECONDS env overrides + fake-codex sleep
# modes — never real waits.

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/zskills-runner-failures.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export ZSKILLS_RUNNER_TIMEOUT_SECONDS=120
export ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS=60

# stderr-reason discipline manifest: every case that exercises a mapped exit
# code records "<case>|<rc>|<expected-reason>|<err-file>" here; the sweep
# case asserts each err-file's FINAL stderr line is the matching
# runner_stop_reason and that the full mapped-code set was exercised.
REASON_MANIFEST="$WORK/reason-manifest.txt"
: > "$REASON_MANIFEST"
record_reason() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$REASON_MANIFEST"
}

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
  # make_fixture <dir> [n-plan-rows] [config-json]
  local dir="$1" rows="${2:-2}" config="${3:-$DEFAULT_CONFIG}"
  git init -q -b main "$dir"
  git -C "$dir" config user.email runner-test@example.test
  git -C "$dir" config user.name "Runner Test"
  mkdir -p "$dir/plans" "$dir/.agents"
  table_plan "$rows" > "$dir/plans/example.md"
  printf '%s\n' "$config" > "$dir/.agents/zskills-config.json"
  printf '.zskills/\n' > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
}

run_runner() {
  # run_runner <fixture> <out> <err> [extra runner args...]
  local f="$1" out="$2" err="$3"
  shift 3
  FAKE_CODEX_MODE="${MODE_OVERRIDE:-success}" bash "$RUNNER" run-plan plans/example.md finish auto \
    --repo "$f" --codex-bin "$FAKE" "$@" > "$out" 2> "$err"
}

run_dir_of() {
  sed -n 's/^run_dir=//p' "$1" | sed -n '1p'
}

summary_value() {
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

expect_summary_reason() {
  # expect_summary_reason <runner-stdout> <validation-reason-pattern>
  # → also prints the resolved summary path on stdout for reuse.
  local rundir summary
  rundir=$(run_dir_of "$1")
  [ -n "$rundir" ] || { echo "run_dir not printed"; return 1; }
  summary="$rundir/chunk-001.summary.json"
  [ -f "$summary" ] || { echo "chunk-001.summary.json missing"; return 1; }
  case "$(summary_value "$summary" validation_reason)" in
    *$2*) ;;
    *) echo "summary validation_reason '$(summary_value "$summary" validation_reason)' does not contain '$2'"; return 1 ;;
  esac
  printf '%s\n' "$summary"
}

line_count() {
  wc -l < "$1" | tr -d ' '
}

# ── enumerated cases ─────────────────────────────────────────────────────────
CASES="
no-progress-rc20
missing-handoff-rc21
premature-final-rc21
report-missing-rc22
report-malformed-rc22
stale-marker-replay-rc22
missing-verifier-rc23
missing-tests-run-rc23
dirty-artifacts-rc25
child-nonzero-rc26
wall-timeout-rc124
idle-timeout-rc125
sandbox-triage-rc26
max-chunks-rc30
pr-wrong-tracking-split-state
landed-conflict-hard-stop
landed-pr-failed-hard-stop
landed-pr-ready-re-entry
claim-evidence-mismatch-rc23
stderr-reason-discipline-sweep
"

case_no_progress_rc20() {
  local f="$WORK/f-rc20" out="$WORK/rc20.out" err="$WORK/rc20.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=no-progress run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 20 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'no durable progress detected' || return 1
  expect_summary_reason "$out" 'no durable progress' > /dev/null || return 1
  record_reason no-progress-rc20 20 no-progress "$err"
}

case_missing_handoff_rc21() {
  local f="$WORK/f-rc21h" out="$WORK/rc21h.out" err="$WORK/rc21h.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=missing-handoff run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 21 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'handoff marker missing after progress' || return 1
  record_reason missing-handoff-rc21 21 handoff-missing "$err"
}

case_premature_final_rc21() {
  local f="$WORK/f-rc21p" out="$WORK/rc21p.out" err="$WORK/rc21p.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=premature-final run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 21 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'final run-plan marker present before plan completion' || return 1
  record_reason premature-final-rc21 21 premature-final "$err"
}

case_report_missing_rc22() {
  local f="$WORK/f-rc22m" out="$WORK/rc22m.out" err="$WORK/rc22m.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=missing-report run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 22 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'report missing:' || return 1
  record_reason report-missing-rc22 22 report-invalid "$err"
}

case_report_malformed_rc22() {
  local f="$WORK/f-rc22f" out="$WORK/rc22f.out" err="$WORK/rc22f.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=malformed-report run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 22 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'report missing required pattern' || return 1
  record_reason report-malformed-rc22 22 report-invalid "$err"
}

case_stale_marker_replay_rc22() {
  local f="$WORK/f-rc22s" out="$WORK/rc22s.out" err="$WORK/rc22s.err" rc tdir m
  make_fixture "$f"
  # Replay fixture (spec change 4, marker_changed staleness): a pre-seeded
  # marker set from "a previous run" that the child does NOT re-touch must
  # not ride through. The handoff is deliberately NOT pre-seeded so the
  # ladder reaches the staleness rung (a stale handoff would already fail
  # the rung-3 handoff-touched contract).
  tdir="$f/.zskills/tracking/run-plan.example"
  mkdir -p "$tdir"
  for m in step.run-plan.example.implement step.run-plan.example.verify \
           step.run-plan.example.report requires.verify-changes.example \
           step.verify-changes.example.tests-run step.verify-changes.example.complete \
           fulfilled.verify-changes.example; do
    printf 'stale fixture content\n' > "$tdir/$m"
  done
  MODE_OVERRIDE=stale-markers run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 22 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'stale marker was not updated: step\.run-plan\.example\.implement' || return 1
  record_reason stale-marker-replay-rc22 22 stale-marker "$err"
}

case_missing_verifier_rc23() {
  local f="$WORK/f-rc23v" out="$WORK/rc23v.out" err="$WORK/rc23v.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=missing-verifier run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 23 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'verification marker evidence missing: requires\.verify-changes\.example' || return 1
  record_reason missing-verifier-rc23 23 verifier-evidence-missing "$err"
}

case_missing_tests_run_rc23() {
  local f="$WORK/f-rc23t" out="$WORK/rc23t.out" err="$WORK/rc23t.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=missing-tests-run run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 23 "$rc" || { cat "$err"; return 1; }
  # The one missing marker is exactly the tests-run requirement
  # (prompted-but-unvalidated in the codex fork; required per spec change 8).
  expect_in_file "$err" 'verification marker evidence missing: step\.verify-changes\.example\.tests-run' || return 1
  record_reason missing-tests-run-rc23 23 verifier-evidence-missing "$err"
}

case_dirty_artifacts_rc25() {
  local f="$WORK/f-rc25" out="$WORK/rc25.out" err="$WORK/rc25.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=dirty run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 25 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'unexpected dirty project artifact remains' || return 1
  expect_in_file "$err" 'dirty-artifact\.txt' || return 1
  record_reason dirty-artifacts-rc25 25 dirty-artifacts "$err"
}

case_child_nonzero_rc26() {
  local f="$WORK/f-rc26" out="$WORK/rc26.out" err="$WORK/rc26.err" rc summary raw tail_json
  make_fixture "$f"
  MODE_OVERRIDE=nonzero-exit run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 26 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'child exited nonzero \(raw child rc 7' || return 1

  # Code 26 forensics contract: the RAW child rc and its last stderr are
  # recorded in chunk-NNN.summary.json — never a raw passthrough.
  summary="$(run_dir_of "$out")/chunk-001.summary.json"
  [ -f "$summary" ] || { echo "chunk-001.summary.json missing"; return 1; }
  raw=$(summary_value "$summary" child_raw_rc)
  [ "$raw" = "7" ] || { echo "summary child_raw_rc expected 7, got '$raw'"; return 1; }
  tail_json=$(summary_value "$summary" child_stderr_tail)
  case "$tail_json" in
    *"simulated child failure"*) ;;
    *) echo "summary child_stderr_tail missing the child's stderr: $tail_json"; return 1 ;;
  esac
  # AC: quote the recorded summary fields in the suite's visible output.
  {
    echo "rc-26 summary.json forensics quote: child_raw_rc=$raw"
    echo "rc-26 summary.json forensics quote: child_stderr_tail=$tail_json"
  } >&3
  record_reason child-nonzero-rc26 26 child-failed "$err"
}

case_wall_timeout_rc124() {
  local f="$WORK/f-rc124" out="$WORK/rc124.out" err="$WORK/rc124.err" rc
  make_fixture "$f"
  # fake-codex sleep mode + tiny wall override — never a real 90-minute wait.
  MODE_OVERRIDE=sleep FAKE_CODEX_SLEEP_SECONDS=20 \
    ZSKILLS_RUNNER_TIMEOUT_SECONDS=2 ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS=30 \
    run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 124 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'chunk wall timeout after 2s' || return 1
  record_reason wall-timeout-rc124 124 chunk-timeout "$err"
}

case_idle_timeout_rc125() {
  local f="$WORK/f-rc125" out="$WORK/rc125.out" err="$WORK/rc125.err" rc
  make_fixture "$f"
  # idle mode: one output line, then silence longer than the idle override.
  MODE_OVERRIDE=idle FAKE_CODEX_SLEEP_SECONDS=20 \
    ZSKILLS_RUNNER_TIMEOUT_SECONDS=30 ZSKILLS_RUNNER_IDLE_TIMEOUT_SECONDS=2 \
    run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 125 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'chunk idle timeout after 2s of silence' || return 1
  record_reason idle-timeout-rc125 125 chunk-idle-timeout "$err"
}

case_sandbox_triage_rc26() {
  local f="$WORK/f-sandbox" out="$WORK/sandbox.out" err="$WORK/sandbox.err" rc
  make_fixture "$f"
  MODE_OVERRIDE=sandbox-fail run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 26 "$rc" || { cat "$err"; return 1; }
  # explain_child_failure (spec change 7): explicit remediation, NEVER
  # auto-escalate.
  expect_in_file "$err" 'will NOT retry with danger-full-access automatically' || return 1
  expect_in_file "$err" '\-\-sandbox danger-full-access' || return 1
  expect_in_file "$err" 'child failed while starting sandbox' || return 1
  record_reason sandbox-triage-rc26 26 sandbox-unavailable "$err"
}

case_max_chunks_rc30() {
  local f="$WORK/f-rc30" out="$WORK/rc30.out" err="$WORK/rc30.err" rc
  make_fixture "$f" 2
  run_runner "$f" "$out" "$err" --max-chunks 1
  rc=$?
  expect_rc 30 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'max chunks \(1\) exhausted before plan completion' || return 1
  record_reason max-chunks-rc30 30 max-chunks "$err"
}

pr_config() {
  printf '{ "execution": { "landing": "pr" }, "runner": { "max_chunks": 6, "log_dir": ".zskills/test-logs", "worktree_parent_dir": "%s" } }' "$1"
}

case_pr_wrong_tracking_split_state() {
  local f="$WORK/f-prwrong" out="$WORK/prwrong.out" err="$WORK/prwrong.err" rc
  local parent="$WORK/wtparent-prwrong" wt
  make_fixture "$f" 2 "$(pr_config "$parent")"
  mkdir -p "$parent"
  wt="$parent/$(basename "$f")-pr-example"
  git -C "$f" worktree add -q -b feat-pr-example "$wt" > /dev/null

  # The child writes its tracking markers into the PR WORKTREE's tracking
  # dir instead of the repo root's contract dir — the split-state must be
  # caught by validation (the repo-root evidence never appeared).
  MODE_OVERRIDE=pr-wrong-tracking run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 21 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'handoff marker missing after progress' || return 1
  # Split state proven: markers DID land under the worktree tracking dir...
  [ -f "$wt/.zskills/tracking/run-plan.example/step.run-plan.example.implement" ] \
    || { echo "expected wrong-root markers under the PR worktree"; return 1; }
  # ...and the repo-root contract dir has none.
  if ls "$f/.zskills/tracking/run-plan.example/" 2>/dev/null | grep -q .; then
    echo "repo-root tracking dir unexpectedly has markers:"
    ls "$f/.zskills/tracking/run-plan.example/"
    return 1
  fi
  record_reason pr-wrong-tracking-split-state 21 handoff-missing "$err"
}

case_landed_conflict_hard_stop() {
  local f="$WORK/f-conflict" out="$WORK/conflict.out" err="$WORK/conflict.err" rc
  make_fixture "$f" 1
  FAKE_CODEX_LANDED_STATUS=conflict run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 24 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'terminal landing failure recorded in \.zskills/landed: status=conflict' || return 1
  record_reason landed-conflict-hard-stop 24 landing-conflict "$err"
}

case_landed_pr_failed_hard_stop() {
  local f="$WORK/f-prfailed" out="$WORK/prfailed.out" err="$WORK/prfailed.err" rc
  make_fixture "$f" 1
  FAKE_CODEX_LANDED_STATUS=pr-failed run_runner "$f" "$out" "$err"
  rc=$?
  expect_rc 24 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'terminal landing failure recorded in \.zskills/landed: status=pr-failed' || return 1
  record_reason landed-pr-failed-hard-stop 24 landing-pr-failed "$err"
}

case_landed_pr_ready_re_entry() {
  local f="$WORK/f-prready" out="$WORK/prready.out" err="$WORK/prready.err" rc
  local wrapper="$WORK/flip-codex.sh" flag="$WORK/prready.flag"
  make_fixture "$f" 1
  # Wrapper codex-bin: first invocation lands as pr-ready (landing pending),
  # subsequent invocations land as landed — modeling a re-entry chunk whose
  # idempotent Step-0 resolves the pending PR landing.
  cat > "$wrapper" <<WRAP
#!/bin/bash
if [ -f "$flag" ]; then
  export FAKE_CODEX_LANDED_STATUS=landed
else
  : > "$flag"
  export FAKE_CODEX_LANDED_STATUS=pr-ready
fi
exec bash "$FAKE" "\$@"
WRAP
  chmod +x "$wrapper"
  FAKE_CODEX_MODE=success bash "$RUNNER" run-plan plans/example.md finish auto \
    --repo "$f" --codex-bin "$wrapper" > "$out" 2> "$err"
  rc=$?
  expect_rc 0 "$rc" || { cat "$err"; return 1; }
  # pr-ready scheduled a re-entry chunk instead of stopping or completing...
  expect_in_file "$out" 'landing pending \(re-entry\) — scheduling re-entry chunk' || return 1
  # ...and the re-entry chunk ran (two child invocations) and completed.
  [ "$(line_count "$f/.zskills/fake-codex/argv.log")" = "2" ] \
    || { echo "expected 2 child invocations (initial + re-entry), got $(line_count "$f/.zskills/fake-codex/argv.log")"; return 1; }
  record_reason landed-pr-ready-re-entry 0 complete "$err"
}

case_claim_evidence_mismatch_rc23() {
  local f="$WORK/f-mismatch" out="$WORK/mismatch.out" err="$WORK/mismatch.err" rc summary problems
  make_fixture "$f"
  # Schema mode: durable evidence says "phase done, plan NOT complete" while
  # the structured self-report CLAIMS complete — the lie-detection layer.
  MODE_OVERRIDE=claim-evidence-mismatch run_runner "$f" "$out" "$err" --output-schema
  rc=$?
  expect_rc 23 "$rc" || { cat "$err"; return 1; }
  expect_in_file "$err" 'claim-evidence-mismatch' || return 1
  expect_in_file "$err" "claims status 'complete' but durable evidence" || return 1
  summary=$(expect_summary_reason "$out" 'claim-evidence-mismatch') || return 1
  # The lying self-report + the detected problems are preserved as forensics.
  case "$(summary_value "$summary" self_report)" in
    *'"status": "complete"'*) ;;
    *) echo "summary self_report does not carry the claimed 'complete' status"; return 1 ;;
  esac
  problems=$(summary_value "$summary" self_report_problems)
  [ "$problems" != "[]" ] && [ -n "$problems" ] || { echo "summary self_report_problems empty"; return 1; }
  record_reason claim-evidence-mismatch-rc23 23 claim-evidence-mismatch "$err"
}

case_stderr_reason_discipline_sweep() {
  # For EVERY mapped exit code exercised above: the FINAL stderr line is the
  # matching authoritative runner_stop_reason.
  local entries bad=0 code_list covered
  local mname mrc mreason merrfile mlast
  entries=$(line_count "$REASON_MANIFEST")
  [ "$entries" -ge 18 ] || { echo "manifest too small ($entries entries) — earlier cases failed before recording"; return 1; }
  while IFS='|' read -r mname mrc mreason merrfile; do
    [ -n "$mname" ] || continue
    mlast=$(tail -n 1 "$merrfile")
    if [ "$mlast" != "runner_stop_reason=$mreason" ]; then
      echo "$mname (rc $mrc): expected final stderr line 'runner_stop_reason=$mreason', got '$mlast'"
      bad=1
    fi
  done < "$REASON_MANIFEST"
  [ "$bad" -eq 0 ] || return 1
  # Coverage: every mapped exit code this suite is responsible for appears.
  covered=$(awk -F'|' '{print $2}' "$REASON_MANIFEST" | sort -un | tr '\n' ' ')
  for code_list in 0 20 21 22 23 24 25 26 30 124 125; do
    case " $covered " in
      *" $code_list "*) ;;
      *) echo "mapped exit code $code_list was never exercised (covered: $covered)"; return 1 ;;
    esac
  done
  echo "stderr-reason discipline verified for exit codes: $covered"
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

# fd 3 → the suite's real stdout, for case output that must stay visible on
# PASS (the rc-26 forensics quote demanded by the phase AC).
exec 3>&1

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
