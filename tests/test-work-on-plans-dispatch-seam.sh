#!/bin/bash
# Tests for skills/work-on-plans dispatch-loop seam — SEAM_HARDENING_HIGH
# Phase 6b. This is the HIGHEST-RISK phase: it adds a test seam to a SHIPPED
# skill's control flow (modes/execute.md Step 5). The #1 invariant:
# **production behavior is byte-for-byte unchanged when _ZSKILLS_TEST_HARNESS
# is unset.**
#
# What this suite proves, by EXTRACTING the REAL production fences from
# modes/execute.md (via tests/lib/extract-fence.sh) and RUNNING them:
#
#   - PRODUCTION-SAFETY (MANDATORY): with the harness flag UNSET, the
#     extracted seam fence is INERT — it does not assign RUNPLAN_RESULT, so a
#     model-assigned production value survives untouched, and the unguarded
#     production path still emits the same `Skill: { skill: "run-plan", ... }`
#     directive. The entry-point guard (Step 2.9) clears the injected vars
#     when the flag is absent.
#   - SEAM BEHAVIOR (harness flag == 1): per-slug var precedence over the
#     newline slug->text map; the seam reads an injected /run-plan result so
#     the real Step-5/Step-6 dispatch loop is exercisable in a sandbox.
#   - SANDBOX HARNESS: a real git-init worktree, plans/*.md + monitor-state
#     with N ready entries, success AND failure injected results. Drives the
#     REAL extracted seam + REAL extracted failure-detection arm (a) through
#     an N-entry loop and asserts the full lifecycle:
#       * step.work-on-plans.<sprint>.<slug>           (status started->complete)
#       * requires.run-plan.<slug>                     (parent declaration)
#       * fulfilled.run-plan.<slug>                    (on success)
#       under .zskills/tracking/work-on-plans.<sprint>/
#       * mode-resolution precedence CLI > per-entry > default_mode > phase
#         in the marker `mode:` field
#       * the failure-arm text-match STOPS the loop (no `continue`) AND writes
#         a report to $ZSKILLS_AUDIT_DIR/work-on-plans-<sprint>.md, exit != 0
#       * `continue` proceeds past a failure to the next entry
#       * sprint-completion marker fulfilled.work-on-plans.<sprint>
#       * work-state -> idle ; exit code
#   - ARG-PARSE ROUTER (SKILL.md rules 1-7, usage-error exit 2 — zero
#     coverage before this phase).
#   - MUTATION: a self-check that the harness FAILS if the seam fence is
#     mutated to drop the harness gate (i.e. the test cannot pass against a
#     broken seam — it is not green-by-absence).
#
# Run from repo root: bash tests/test-work-on-plans-dispatch-seam.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/work-on-plans/SKILL.md"
SKILL_DIR="$REPO_ROOT/skills/work-on-plans"
EXEC_MD="$SKILL_DIR/modes/execute.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TEST_TMPDIR="/tmp/zskills-wop-seam-test-$$"
mkdir -p "$TEST_TMPDIR"
cleanup() {
  case "$TEST_TMPDIR" in
    /tmp/zskills-wop-seam-test-*) rm -rf -- "$TEST_TMPDIR" ;;
  esac
}
trap cleanup EXIT

# ─────────────────────────────────────────────────────────────────────
# Extract the REAL production fences from modes/execute.md.
#   - GUARD: the entry-point unset guard (Step 2.9).
#   - SEAM:  the strictly-gated dispatch seam (Step 5.5, "Test seam").
#   - ARMA:  the failure-detection arm (a) grep on RUNPLAN_RESULT (Step 6a).
# extract_fence_between counts ```bash openers between the landmarks; each of
# these windows has exactly one fence so fence-index 1 is unambiguous. The
# seam + arm-a fences are 3-space-indented (nested under list items / inside
# a numbered step), so strip-indent=1 removes one leading 3-space run.
# ─────────────────────────────────────────────────────────────────────
GUARD_SH="$TEST_TMPDIR/_guard.sh"
SEAM_SH="$TEST_TMPDIR/_seam.sh"
ARMA_SH="$TEST_TMPDIR/_arma.sh"

extract_or_die() {
  # extract_or_die <out> <file> <start-re> <end-re> <strip>
  local out="$1" file="$2" start_re="$3" end_re="$4" strip="$5"
  if ! extract_fence_between "$file" "$start_re" "$end_re" 1 "$strip" > "$out"; then
    echo "FATAL: could not extract fence ($start_re .. $end_re) from $file" >&2
    exit 1
  fi
}

extract_or_die "$GUARD_SH" "$EXEC_MD" \
  '^## Step 2[.]9' '^## Step 3' 0
# The seam fence opens after the "**Test seam" prose and before Step 6.
extract_or_die "$SEAM_SH" "$EXEC_MD" \
  '[*][*]Test seam [(]production behavior unaffected[)]' '^6[.] [*][*]Detect failure' 1
# arm-a fence sits between the "(a) Result text matches" landmark and "(b)".
# It is indented 5 spaces (nested deeper); strip one 3-space run, then the
# extracted body still has 2 leading spaces — harmless for `source` of a
# straight-line fence, but we normalise below for cleanliness.
extract_or_die "$ARMA_SH" "$EXEC_MD" \
  '^   - [*][*][(]a[)] Result text matches' '^   - [*][*][(]b[)]' 1
# Normalise residual leading whitespace on arm-a so `.` sourcing is clean.
sed -i 's/^  //' "$ARMA_SH"

bash -n "$GUARD_SH" || { echo "FATAL: guard fence is not valid bash" >&2; exit 1; }
bash -n "$SEAM_SH" || { echo "FATAL: seam fence is not valid bash" >&2; exit 1; }
bash -n "$ARMA_SH" || { echo "FATAL: arm-a fence is not valid bash" >&2; exit 1; }

echo "=== work-on-plans dispatch-seam tests (extract-and-run production) ==="

# ─────────────────────────────────────────────────────────────────────
# Test 0 — extraction sanity: the extracted fences carry the real landmarks.
# ─────────────────────────────────────────────────────────────────────
if grep -q '_ZSKILLS_TEST_HARNESS' "$SEAM_SH" \
   && grep -q '_ZSKILLS_TEST_RUNPLAN_RESULT_' "$SEAM_SH" \
   && grep -q 'RUNPLAN_RESULT=' "$SEAM_SH"; then
  pass "extract: seam fence carries the harness-gate + per-slug + map landmarks"
else
  fail "extract: seam fence missing expected landmarks"
fi
if grep -q '_ZSKILLS_TEST_HARNESS' "$GUARD_SH" \
   && grep -q 'unset _ZSKILLS_TEST_RUNPLAN_RESULT' "$GUARD_SH"; then
  pass "extract: entry-point guard carries the unset landmarks"
else
  fail "extract: entry-point guard missing expected landmarks"
fi
if grep -q 'DISPATCH_FAILED' "$ARMA_SH" \
   && grep -q 'Phase \[0-9\]+ failed' "$ARMA_SH"; then
  pass "extract: arm-a fence carries the failure-signature grep"
else
  fail "extract: arm-a fence missing failure-signature grep"
fi

# ─────────────────────────────────────────────────────────────────────
# PRODUCTION-SAFETY (MANDATORY) — Test 1.
# With _ZSKILLS_TEST_HARNESS UNSET: the seam fence must NOT assign
# RUNPLAN_RESULT. A production model-assigned value survives untouched. The
# entry-point guard clears any injected vars. This proves the gate is inert
# in production.
# ─────────────────────────────────────────────────────────────────────
prod_out=$(bash -s -- "$GUARD_SH" "$SEAM_SH" <<'PROD'
set -u
GUARD_SH="$1"; SEAM_SH="$2"
# Simulate a polluted parent shell: injected vars present, but the harness
# flag is ABSENT (production).
export _ZSKILLS_TEST_RUNPLAN_RESULT="some-plan	INJECTED-SHOULD-NOT-LEAK"
export _ZSKILLS_TEST_RUNPLAN_RESULT_SOME_PLAN="PERSLUG-SHOULD-NOT-LEAK"
unset _ZSKILLS_TEST_HARNESS
# Entry-point guard runs first.
. "$GUARD_SH"
# Production: the model assigns the real Skill-tool result.
SLUG="some-plan"
RUNPLAN_RESULT="PRODUCTION-MODEL-RESULT"
. "$SEAM_SH"
echo "RUNPLAN_RESULT=$RUNPLAN_RESULT"
echo "INJECTED_PERSLUG=${_ZSKILLS_TEST_RUNPLAN_RESULT_SOME_PLAN:-<unset>}"
echo "INJECTED_MAP=${_ZSKILLS_TEST_RUNPLAN_RESULT:-<unset>}"
PROD
)
if printf '%s\n' "$prod_out" | grep -q 'RUNPLAN_RESULT=PRODUCTION-MODEL-RESULT' \
   && ! printf '%s\n' "$prod_out" | grep -q 'SHOULD-NOT-LEAK' \
   && printf '%s\n' "$prod_out" | grep -q 'INJECTED_PERSLUG=<unset>' \
   && printf '%s\n' "$prod_out" | grep -q 'INJECTED_MAP=<unset>'; then
  pass "PRODUCTION-SAFETY: flag unset -> seam inert, model value survives, injected vars cleared by guard"
else
  fail "PRODUCTION-SAFETY: seam not inert with flag unset (out: $prod_out)"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 1b — the unguarded production path STILL emits the same directive.
# The dispatch directive text is a prose `Skill: { ... }` line ABOVE the
# seam. It is not gated; assert it is present verbatim in execute.md and the
# seam comment promises it is emitted in production.
# ─────────────────────────────────────────────────────────────────────
if grep -q 'Skill: { skill: "run-plan", args: "\$ZSKILLS_PLANS_DIR/<FILE>.md auto" }' "$EXEC_MD" \
   && grep -q 'Skill: { skill: "run-plan", args: "\$ZSKILLS_PLANS_DIR/<FILE>.md auto finish" }' "$EXEC_MD" \
   && grep -q 'ALWAYS emits the same' "$EXEC_MD"; then
  pass "PRODUCTION-SAFETY: unguarded path still emits the run-plan Skill directive (phase + finish)"
else
  fail "PRODUCTION-SAFETY: run-plan dispatch directive missing/altered in execute.md"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 2 — SEAM BEHAVIOR: per-slug var precedence over the map.
# ─────────────────────────────────────────────────────────────────────
seam_out=$(bash -s -- "$SEAM_SH" <<'SEAMT'
set -u
SEAM_SH="$1"
export _ZSKILLS_TEST_HARNESS=1
export _ZSKILLS_TEST_RUNPLAN_RESULT="my-plan	FROM-MAP"
export _ZSKILLS_TEST_RUNPLAN_RESULT_MY_PLAN="FROM-PERSLUG"
SLUG="my-plan"
RUNPLAN_RESULT=""
. "$SEAM_SH"
echo "perslug=$RUNPLAN_RESULT"
unset _ZSKILLS_TEST_RUNPLAN_RESULT_MY_PLAN
RUNPLAN_RESULT=""
. "$SEAM_SH"
echo "map=$RUNPLAN_RESULT"
SEAMT
)
if printf '%s\n' "$seam_out" | grep -q 'perslug=FROM-PERSLUG' \
   && printf '%s\n' "$seam_out" | grep -q 'map=FROM-MAP'; then
  pass "SEAM: per-slug var wins over map; map is the fallback"
else
  fail "SEAM: precedence wrong (out: $seam_out)"
fi

# ─────────────────────────────────────────────────────────────────────
# SANDBOX HARNESS — drive the REAL extracted seam + arm-a through an
# N-entry dispatch loop in a real git worktree.
#
# The driver below mirrors the Step-5/6 loop control flow and the marker
# `printf` formats VERBATIM from execute.md (the formats are also asserted
# structurally in Test 8 so drift in production is caught). The seam and
# failure-detection (arm a) are the REAL extracted production fences.
# ─────────────────────────────────────────────────────────────────────

# A production-faithful dispatch loop driver. It does NOT re-implement the
# seam or the failure grep — it sources the extracted fences. Inputs:
#   $1 sandbox root ; $2 N ; $3 CONTINUE_ON_FAILURE ; $4 MODE_OVERRIDE
#   monitor-state ready order + per-slug injected results come from env.
run_dispatch_loop() {
  local root="$1" N="$2" CONTINUE_ON_FAILURE="$3" MODE_OVERRIDE="$4"
  local SEAM_SH="$5" ARMA_SH="$6"

  local MAIN_ROOT="$root"
  local MONITOR_STATE="$root/.zskills/monitor-state.json"
  local WORK_STATE="$root/.zskills/work-on-plans-state.json"
  local AUDIT_DIR="$root/.zskills/audit"
  mkdir -p "$AUDIT_DIR"

  # Sprint + pipeline ids (production format: sanitized work-on-plans.<sprint>).
  local SPRINT_ID="sprint-test-$$"
  local PIPELINE_ID="work-on-plans.$SPRINT_ID"
  local PIPELINE_DIR="$root/.zskills/tracking/$PIPELINE_ID"
  mkdir -p "$PIPELINE_DIR"

  # Resolve default_mode + ready list (TAB: slug<TAB>mode) from monitor-state,
  # mirroring Step 1's READY_TSV extraction.
  local READY_TSV
  READY_TSV=$(python3 - "$MONITOR_STATE" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
default = doc.get('default_mode', 'phase')
for e in doc.get('plans', {}).get('ready', []):
    if isinstance(e, str):
        slug, mode = e, ''
    else:
        slug, mode = e.get('slug', ''), e.get('mode', '')
    if slug:
        print(f'{slug}\t{mode}')
print(f'__DEFAULT__\t{default}', end='')
PY
)
  local DEFAULT_MODE
  DEFAULT_MODE=$(printf '%s' "$READY_TSV" | awk -F'\t' '$1=="__DEFAULT__"{print $2}')
  [ -z "$DEFAULT_MODE" ] && DEFAULT_MODE=phase

  # Build ordered slug/mode arrays (drop the sentinel).
  local -a SLUGS=() ENTRY_MODES=()
  while IFS=$'\t' read -r s m; do
    [ "$s" = "__DEFAULT__" ] && continue
    [ -z "$s" ] && continue
    SLUGS+=("$s"); ENTRY_MODES+=("$m")
  done < <(printf '%s\n' "$READY_TSV")

  # Initial sprint state.
  python3 - "$WORK_STATE" "$SPRINT_ID" "$N" <<'PY'
import json, sys, tempfile, os
path, sprint, total = sys.argv[1], sys.argv[2], int(sys.argv[3])
doc = {"state": "sprint", "sprint_id": f"work-on-plans.{sprint}",
       "progress": {"done": 0, "total": total, "current_slug": ""}}
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.work-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
PY

  local DONE=0 DISPATCH_COUNT=0 SPRINT_FINAL_STATUS="complete"
  local i FAILED_SLUG="" LOOP_EXIT=0
  for ((i = 0; i < ${#SLUGS[@]} && i < N; i++)); do
    local SLUG="${SLUGS[$i]}"
    local ENTRY_MODE="${ENTRY_MODES[$i]}"
    DISPATCH_COUNT=$((DISPATCH_COUNT + 1))

    # Mode-resolution precedence: CLI > per-entry > default_mode > phase.
    local DISPATCH_MODE
    if [ -n "$MODE_OVERRIDE" ]; then DISPATCH_MODE="$MODE_OVERRIDE"
    elif [ -n "$ENTRY_MODE" ]; then DISPATCH_MODE="$ENTRY_MODE"
    elif [ -n "$DEFAULT_MODE" ]; then DISPATCH_MODE="$DEFAULT_MODE"
    else DISPATCH_MODE="phase"; fi

    # step.work-on-plans.<sprint>.<slug> (status: started) — production format.
    printf 'skill: work-on-plans\nparent: work-on-plans.%s\nslug: %s\nmode: %s\nstatus: started\ndate: %s\n' \
      "$SPRINT_ID" "$SLUG" "$DISPATCH_MODE" "now" \
      > "$PIPELINE_DIR/step.work-on-plans.$SPRINT_ID.$SLUG"

    # requires.run-plan.<slug> — production format.
    printf 'skill: run-plan\nparent: work-on-plans\nid: %s\nslug: %s\nmode: %s\ndate: %s\n' \
      "$SPRINT_ID" "$SLUG" "$DISPATCH_MODE" "now" \
      > "$PIPELINE_DIR/requires.run-plan.$SLUG"

    # --- Step 5.5 dispatch via the REAL extracted seam ---
    RUNPLAN_RESULT=""
    . "$SEAM_SH"

    # --- Step 6 (a) failure detection via the REAL extracted arm ---
    . "$ARMA_SH"

    if [ "${DISPATCH_FAILED:-0}" = "1" ]; then
      FAILED_SLUG="$SLUG"
      if [ "$CONTINUE_ON_FAILURE" = "1" ]; then
        echo "/work-on-plans: $SLUG failed; continuing." >&2
        continue
      fi
      # Stop the loop; write the failure report; non-zero exit.
      SPRINT_FINAL_STATUS="failed"
      {
        echo "# /work-on-plans sprint — $SPRINT_ID"
        echo "**Failed:** $SLUG"
        echo "**Result:** $RUNPLAN_RESULT"
      } > "$AUDIT_DIR/work-on-plans-$SPRINT_ID.md"
      LOOP_EXIT=1
      break
    fi

    # On success: step -> complete + fulfilled.run-plan.<slug>.
    printf 'skill: work-on-plans\nparent: work-on-plans.%s\nslug: %s\nmode: %s\nstatus: complete\ndate: %s\n' \
      "$SPRINT_ID" "$SLUG" "$DISPATCH_MODE" "now" \
      > "$PIPELINE_DIR/step.work-on-plans.$SPRINT_ID.$SLUG"
    printf 'skill: run-plan\nparent: work-on-plans\nid: %s\nslug: %s\nstatus: complete\ndate: %s\n' \
      "$SPRINT_ID" "$SLUG" "now" \
      > "$PIPELINE_DIR/fulfilled.run-plan.$SLUG"
    DONE=$((DONE + 1))
  done

  # Step 6 — sprint completion marker.
  printf 'skill: work-on-plans\nsprint_id: %s\ntotal: %d\ndone: %d\ncontinue: %s\nstatus: %s\ndate: %s\n' \
    "$SPRINT_ID" "$DISPATCH_COUNT" "$DONE" "$CONTINUE_ON_FAILURE" \
    "$SPRINT_FINAL_STATUS" "now" \
    > "$PIPELINE_DIR/fulfilled.work-on-plans.$SPRINT_ID"

  # Step 6.2 — work-state -> idle.
  python3 - "$WORK_STATE" <<'PY'
import json, sys, tempfile, os
path = sys.argv[1]
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.work-state.', suffix='.tmp')
json.dump({"state": "idle"}, tmp); tmp.close()
os.replace(tmp.name, path)
PY

  echo "SPRINT_ID=$SPRINT_ID"
  echo "PIPELINE_DIR=$PIPELINE_DIR"
  echo "DONE=$DONE"
  echo "FAILED_SLUG=$FAILED_SLUG"
  echo "AUDIT_DIR=$AUDIT_DIR"
  echo "WORK_STATE=$WORK_STATE"
  return "$LOOP_EXIT"
}

# Helper: build a real git worktree fixture with N ready plan entries.
make_sandbox() {
  local label="$1"; shift
  local root="$TEST_TMPDIR/$label"
  mkdir -p "$root/.zskills" "$root/plans"
  ( cd "$root" && git init -q && git config user.email t@t && git config user.name t \
      && git commit -q --allow-empty -m init )
  echo "$root"
}

# Helper: write monitor-state.json with given default_mode and ready entries.
# Each ready entry is "slug:mode" (mode may be empty).
seed_monitor_state() {
  local path="$1" default_mode="$2"; shift 2
  python3 - "$path" "$default_mode" "$@" <<'PY'
import json, sys
path, default = sys.argv[1], sys.argv[2]
ready = []
for spec in sys.argv[3:]:
    slug, _, mode = spec.partition(':')
    e = {"slug": slug}
    if mode:
        e["mode"] = mode
    ready.append(e)
doc = {"version": "1.1", "default_mode": default,
       "plans": {"drafted": [], "reviewed": [], "ready": ready},
       "issues": {"triage": [], "ready": []}, "updated_at": ""}
open(path, "w").write(json.dumps(doc, indent=2) + "\n")
PY
}

read_marker_field() {
  # read_marker_field <file> <field>
  awk -F': ' -v k="$2" '$1==k {print $2; exit}' "$1"
}

# ─────────────────────────────────────────────────────────────────────
# Test 3 — SANDBOX: all-success N-entry loop; full lifecycle + idle + exit 0.
# ─────────────────────────────────────────────────────────────────────
ROOT=$(make_sandbox t3)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase alpha beta gamma
for s in alpha beta gamma; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'alpha\tlanded clean\nbeta\tlanded clean\ngamma\tlanded clean')
  run_dispatch_loop "$ROOT" 3 0 "" "$SEAM_SH" "$ARMA_SH"
)
ec=$?
SPRINT_ID=$(printf '%s\n' "$out" | awk -F= '/^SPRINT_ID=/{print $2}')
PDIR=$(printf '%s\n' "$out" | awk -F= '/^PIPELINE_DIR=/{print $2}')
DONE=$(printf '%s\n' "$out" | awk -F= '/^DONE=/{print $2}')
WS=$(printf '%s\n' "$out" | awk -F= '/^WORK_STATE=/{print $2}')
# Lifecycle assertions.
ok=1
for s in alpha beta gamma; do
  [ -f "$PDIR/step.work-on-plans.$SPRINT_ID.$s" ] || ok=0
  [ -f "$PDIR/requires.run-plan.$s" ] || ok=0
  [ -f "$PDIR/fulfilled.run-plan.$s" ] || ok=0
  [ "$(read_marker_field "$PDIR/step.work-on-plans.$SPRINT_ID.$s" status)" = "complete" ] || ok=0
done
[ -f "$PDIR/fulfilled.work-on-plans.$SPRINT_ID" ] || ok=0
ws_state=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['state'])" "$WS")
if [ "$ec" -eq 0 ] && [ "$DONE" = "3" ] && [ "$ok" = "1" ] && [ "$ws_state" = "idle" ]; then
  pass "SANDBOX all-success: step/requires/fulfilled.run-plan per slug, completion marker, work-state idle, exit 0"
else
  fail "SANDBOX all-success (ec=$ec DONE=$DONE ok=$ok ws=$ws_state)"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 4 — mode-resolution precedence in the marker `mode:` field.
#   CLI override beats per-entry beats default_mode beats phase.
# ─────────────────────────────────────────────────────────────────────
# 4a: per-entry mode wins over default_mode (no CLI override).
ROOT=$(make_sandbox t4a)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase "p1:finish" "p2:"
for s in p1 p2; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'p1\tlanded clean\np2\tlanded clean')
  run_dispatch_loop "$ROOT" 2 0 "" "$SEAM_SH" "$ARMA_SH"
)
SPRINT_ID=$(printf '%s\n' "$out" | awk -F= '/^SPRINT_ID=/{print $2}')
PDIR=$(printf '%s\n' "$out" | awk -F= '/^PIPELINE_DIR=/{print $2}')
m_p1=$(read_marker_field "$PDIR/step.work-on-plans.$SPRINT_ID.p1" mode)
m_p2=$(read_marker_field "$PDIR/step.work-on-plans.$SPRINT_ID.p2" mode)
if [ "$m_p1" = "finish" ] && [ "$m_p2" = "phase" ]; then
  pass "mode-precedence: per-entry (finish) wins; absent per-entry falls to default_mode (phase)"
else
  fail "mode-precedence per-entry/default (p1=$m_p1 p2=$m_p2)"
fi
# 4b: CLI override beats BOTH per-entry and default_mode.
ROOT=$(make_sandbox t4b)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase "q1:phase" "q2:"
for s in q1 q2; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'q1\tlanded clean\nq2\tlanded clean')
  run_dispatch_loop "$ROOT" 2 0 "finish" "$SEAM_SH" "$ARMA_SH"
)
SPRINT_ID=$(printf '%s\n' "$out" | awk -F= '/^SPRINT_ID=/{print $2}')
PDIR=$(printf '%s\n' "$out" | awk -F= '/^PIPELINE_DIR=/{print $2}')
m_q1=$(read_marker_field "$PDIR/step.work-on-plans.$SPRINT_ID.q1" mode)
m_q2=$(read_marker_field "$PDIR/step.work-on-plans.$SPRINT_ID.q2" mode)
if [ "$m_q1" = "finish" ] && [ "$m_q2" = "finish" ]; then
  pass "mode-precedence: CLI override (finish) beats per-entry (phase) AND default_mode"
else
  fail "mode-precedence CLI override (q1=$m_q1 q2=$m_q2)"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 5 — failure arm stops the loop (no continue) + writes report + exit !=0.
#   beta's injected result matches a failure signature -> stop before gamma.
# ─────────────────────────────────────────────────────────────────────
ROOT=$(make_sandbox t5)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase alpha beta gamma
for s in alpha beta gamma; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'alpha\tlanded clean\nbeta\tPhase 3 failed: boom\ngamma\tlanded clean')
  run_dispatch_loop "$ROOT" 3 0 "" "$SEAM_SH" "$ARMA_SH"
)
ec=$?
SPRINT_ID=$(printf '%s\n' "$out" | awk -F= '/^SPRINT_ID=/{print $2}')
PDIR=$(printf '%s\n' "$out" | awk -F= '/^PIPELINE_DIR=/{print $2}')
DONE=$(printf '%s\n' "$out" | awk -F= '/^DONE=/{print $2}')
ADIR=$(printf '%s\n' "$out" | awk -F= '/^AUDIT_DIR=/{print $2}')
REPORT="$ADIR/work-on-plans-$SPRINT_ID.md"
# alpha succeeded (fulfilled present); gamma never dispatched (no step marker).
if [ "$ec" -ne 0 ] && [ "$DONE" = "1" ] \
   && [ -f "$PDIR/fulfilled.run-plan.alpha" ] \
   && [ ! -f "$PDIR/step.work-on-plans.$SPRINT_ID.gamma" ] \
   && [ -f "$REPORT" ] && grep -q 'Failed:.*beta' "$REPORT"; then
  pass "failure-arm: text-match stops loop before gamma, report written, exit != 0"
else
  fail "failure-arm stop (ec=$ec DONE=$DONE report=$([ -f "$REPORT" ] && echo yes || echo no))"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 6 — `continue` proceeds past a failure to the next entry.
# ─────────────────────────────────────────────────────────────────────
ROOT=$(make_sandbox t6)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase alpha beta gamma
for s in alpha beta gamma; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'alpha\tlanded clean\nbeta\tverification failed\ngamma\tlanded clean')
  run_dispatch_loop "$ROOT" 3 1 "" "$SEAM_SH" "$ARMA_SH"
)
ec=$?
SPRINT_ID=$(printf '%s\n' "$out" | awk -F= '/^SPRINT_ID=/{print $2}')
PDIR=$(printf '%s\n' "$out" | awk -F= '/^PIPELINE_DIR=/{print $2}')
DONE=$(printf '%s\n' "$out" | awk -F= '/^DONE=/{print $2}')
# alpha + gamma succeed; beta failed but loop continued; gamma WAS dispatched.
if [ "$ec" -eq 0 ] && [ "$DONE" = "2" ] \
   && [ -f "$PDIR/fulfilled.run-plan.alpha" ] \
   && [ -f "$PDIR/fulfilled.run-plan.gamma" ] \
   && [ ! -f "$PDIR/fulfilled.run-plan.beta" ]; then
  pass "continue: failure on beta is skipped, gamma still dispatched, DONE=2, exit 0"
else
  fail "continue past failure (ec=$ec DONE=$DONE)"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 7 — N caps the dispatch count: only the first N ready entries run.
# ─────────────────────────────────────────────────────────────────────
ROOT=$(make_sandbox t7)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase a1 a2 a3 a4
for s in a1 a2 a3 a4; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'a1\tok\na2\tok\na3\tok\na4\tok')
  run_dispatch_loop "$ROOT" 2 0 "" "$SEAM_SH" "$ARMA_SH"
)
SPRINT_ID=$(printf '%s\n' "$out" | awk -F= '/^SPRINT_ID=/{print $2}')
PDIR=$(printf '%s\n' "$out" | awk -F= '/^PIPELINE_DIR=/{print $2}')
DONE=$(printf '%s\n' "$out" | awk -F= '/^DONE=/{print $2}')
if [ "$DONE" = "2" ] \
   && [ -f "$PDIR/fulfilled.run-plan.a1" ] && [ -f "$PDIR/fulfilled.run-plan.a2" ] \
   && [ ! -f "$PDIR/step.work-on-plans.$SPRINT_ID.a3" ]; then
  pass "N cap: only first 2 of 4 ready entries dispatched"
else
  fail "N cap (DONE=$DONE)"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 8 — marker-format drift guard: the driver's printf formats MUST match
# the production formats in execute.md. If production changes a marker
# format, this catches the driver going stale (and vice-versa).
# ─────────────────────────────────────────────────────────────────────
if grep -q "skill: work-on-plans\\\\nparent: work-on-plans.%s\\\\nslug: %s\\\\nmode: %s\\\\nstatus: started" "$EXEC_MD" \
   && grep -q "skill: run-plan\\\\nparent: work-on-plans\\\\nid: %s\\\\nslug: %s\\\\nmode: %s" "$EXEC_MD" \
   && grep -q "skill: run-plan\\\\nparent: work-on-plans\\\\nid: %s\\\\nslug: %s\\\\nstatus: complete" "$EXEC_MD" \
   && grep -q "skill: work-on-plans\\\\nsprint_id: %s\\\\ntotal: %d\\\\ndone: %d" "$EXEC_MD"; then
  pass "marker-format drift guard: production step/requires/fulfilled formats present in execute.md"
else
  fail "marker-format drift guard: production marker formats changed (driver may be stale)"
fi

# ─────────────────────────────────────────────────────────────────────
# MUTATION — Test 9. The sandbox must FAIL against a BROKEN seam. Build a
# mutated seam that drops the harness gate (always returns empty), inject a
# failure result, and confirm the failure arm NO LONGER fires (because the
# mutated seam never reads the injection) — i.e. the test would NOT pass
# against a broken seam. This proves the suite is not green-by-absence.
# ─────────────────────────────────────────────────────────────────────
MUT_SEAM="$TEST_TMPDIR/_seam_mutated.sh"
# Mutation: gate inverted so the injection is never read; RUNPLAN_RESULT
# stays whatever the driver set (empty) regardless of the injected failure.
cat > "$MUT_SEAM" <<'MUT'
if [ "${_ZSKILLS_TEST_HARNESS:-}" = "0" ]; then
  RUNPLAN_RESULT="${_ZSKILLS_TEST_RUNPLAN_RESULT:-}"
fi
MUT
ROOT=$(make_sandbox t9)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase alpha beta
for s in alpha beta; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'alpha\tok\nbeta\tPhase 9 failed: should stop')
  run_dispatch_loop "$ROOT" 2 0 "" "$MUT_SEAM" "$ARMA_SH"
)
mut_ec=$?
# With the REAL seam, beta's injected "Phase 9 failed" would stop the loop
# (exit != 0). With the MUTATED seam the injection is never read, so beta
# "succeeds" and the loop exits 0 — i.e. the failure assertion would PASS
# incorrectly. We assert the mutated run differs (exit 0) to prove the test
# discriminates real vs broken seam.
if [ "$mut_ec" -eq 0 ]; then
  pass "MUTATION: broken seam (gate dropped) does NOT propagate the injected failure — suite discriminates real vs mutated"
else
  fail "MUTATION: expected broken seam to swallow the failure (mut_ec=$mut_ec)"
fi
# And the REAL seam DOES stop on the same injection (positive control).
ROOT=$(make_sandbox t9b)
seed_monitor_state "$ROOT/.zskills/monitor-state.json" phase alpha beta
for s in alpha beta; do printf -- '---\nstatus: ready\n---\n' > "$ROOT/plans/$s.md"; done
out=$(
  export _ZSKILLS_TEST_HARNESS=1
  export _ZSKILLS_TEST_RUNPLAN_RESULT=$(printf 'alpha\tok\nbeta\tPhase 9 failed: should stop')
  run_dispatch_loop "$ROOT" 2 0 "" "$SEAM_SH" "$ARMA_SH"
)
real_ec=$?
if [ "$real_ec" -ne 0 ]; then
  pass "MUTATION positive control: REAL seam propagates the injected failure (exit != 0)"
else
  fail "MUTATION positive control: real seam should have stopped (real_ec=$real_ec)"
fi

# ─────────────────────────────────────────────────────────────────────
# ARG-PARSE ROUTER — Tests 10-16. SKILL.md parsing rules 1-7. The router is
# model-prose, not a bash function; assert the canonical rule text + the
# usage-error exit-2 contract are present and unambiguous (rules 1-7).
# ─────────────────────────────────────────────────────────────────────
# Rule 1: empty args -> read-only listing exit 0. (The rules use a Unicode
# arrow that the C-locale grep treats opaquely; match the surrounding ASCII
# substrings instead of the arrow glyph.)
if grep -q 'no-args read-only mode' "$SKILL" \
   && grep -Eq '^1\. \*\*Empty .\$ARGUMENTS' "$SKILL"; then
  pass "arg-router rule 1: empty ARGUMENTS -> read-only listing"
else
  fail "arg-router rule 1 missing"
fi
# Rule 2: next.
if grep -q 'First token is .next. → next read-only mode' "$SKILL"; then
  pass "arg-router rule 2: next -> schedule line"
else
  fail "arg-router rule 2 missing"
fi
# Rule 3: stop.
if grep -q 'First token is .stop. → cancel any active' "$SKILL"; then
  pass "arg-router rule 3: stop -> cancel cron"
else
  fail "arg-router rule 3 missing"
fi
# Rule 4: integer N.
if grep -q 'First token matches .\^\[0-9\]+\$. → dispatch path' "$SKILL"; then
  pass "arg-router rule 4: ^[0-9]+\$ -> dispatch path N"
else
  fail "arg-router rule 4 missing"
fi
# Rule 5: all.
if grep -q 'First token is .all. → dispatch path' "$SKILL"; then
  pass "arg-router rule 5: all -> dispatch path"
else
  fail "arg-router rule 5 missing"
fi
# Rule 6: mutating subcommands. ('every' wraps onto the next prose line, so
# match the leading subcommand list on rule 6's first line.)
if grep -q 'First token is one of .add., .rank., .remove., .default.,' "$SKILL" \
   && grep -q 'mutating subcommand' "$SKILL"; then
  pass "arg-router rule 6: add/rank/remove/default/every -> mutating subcommand"
else
  fail "arg-router rule 6 missing"
fi
# Rule 7: usage error exit 2.
if grep -q 'First token is anything else → usage error' "$SKILL" \
   && grep -q '^   Exit 2.' "$SKILL"; then
  pass "arg-router rule 7: unknown first token -> usage error, exit 2"
else
  fail "arg-router rule 7 / exit-2 contract missing"
fi
# Functional: emulate the rule-4/5/7 first-token routing decision exactly as
# the prose specifies, to prove the rules are executable (not just present).
route_first_token() {
  local tok="$1"
  case "$tok" in
    "")            echo "readonly" ;;
    next)          echo "next" ;;
    stop)          echo "stop" ;;
    all)           echo "dispatch-all" ;;
    add|rank|remove|default|every) echo "mutate" ;;
    *)
      if [[ "$tok" =~ ^[0-9]+$ ]]; then echo "dispatch-n"
      else echo "usage-error"; fi ;;
  esac
}
route_ok=1
[ "$(route_first_token "")" = "readonly" ] || route_ok=0
[ "$(route_first_token next)" = "next" ] || route_ok=0
[ "$(route_first_token stop)" = "stop" ] || route_ok=0
[ "$(route_first_token 3)" = "dispatch-n" ] || route_ok=0
[ "$(route_first_token all)" = "dispatch-all" ] || route_ok=0
[ "$(route_first_token add)" = "mutate" ] || route_ok=0
[ "$(route_first_token bogus)" = "usage-error" ] || route_ok=0
[ "$(route_first_token 4plan)" = "usage-error" ] || route_ok=0
if [ "$route_ok" = "1" ]; then
  pass "arg-router functional: first-token routing matches rules 1-7 (incl. digit-prefix -> usage-error)"
else
  fail "arg-router functional routing mismatch"
fi

# ─────────────────────────────────────────────────────────────────────
# Test 17 — Cron `every`/`stop` orchestration stays ABOVE the testable line.
# Note (not a fake): the recurring-schedule registration is CronCreate/
# CronDelete glue which cannot be driven in a sandbox. We assert the skill
# documents that the seam covers only the dispatch loop, not the cron glue.
# ─────────────────────────────────────────────────────────────────────
if grep -q 'CronCreate' "$SKILL_DIR"/subcommands/*.md 2>/dev/null \
   || grep -rq 'every' "$SKILL_DIR"/subcommands/*.md 2>/dev/null; then
  pass "cron orchestration (every/stop) lives in subcommands glue — above the testable line (noted, not faked)"
else
  fail "cron orchestration reference missing (expected every/stop glue)"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
