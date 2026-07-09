#!/usr/bin/env bash
# tests/mocks/fake-codex.sh — standalone fake `codex` CLI for the porting
# runner test harness (CODEX_PORT_PLAN Phase 1, WI 1.4).
#
# Architecture kept from the zskills-codex fork: a standalone script,
# behavior dispatched on the FAKE_CODEX_MODE env var, contract values parsed
# out of the runner prompt's `- Label: value` lines, and FAIL-FAST on
# unprepared calls (exit 99, like tests/mocks/mock-gh.sh — never exit 0 with
# empty output, which would silently produce false test confidence).
#
# PROBE-ID ANCHORING (anti-circularity, spec reference item 6): every Codex
# semantic this fake simulates carries a source comment citing the
# scripts/porting/codex-probe.sh probe id that validates it. fake-codex
# simulates ONLY probe-covered behavior — it is DOWNSTREAM of the probe
# contract, never an independent oracle. When an owner probe result deviates
# from a simulated semantic, the Phase-4 probe triage (WI 4.0b) names this
# file and its suites as rework targets for that id.
#
# Accepted argv (subset of real codex, per the probe contract):
#   fake-codex --version
#   fake-codex exec [resume <ID>] [-C <repo>] [--add-dir <dir>]
#              [--sandbox <mode>] [-c key=value] [--json]
#              [-o|--output-last-message <file>] [--output-schema <file>]
#              <prompt>
#
# State (all under <repo>/.zskills/fake-codex/):
#   argv.log    one line per invocation (full argv) — tests assert on it
#               (e.g. fresh-mode `finish auto` calls must NEVER contain
#               `resume`).
#   thread-id   the durable session id issued by the most recent fresh exec.
#
# FAKE_CODEX_MODE values (failure-mode matrix = union of both prior forks'
# modes + the Phase-1 additions):
#   success               one unit of durable progress; handoff when phases
#                         remain, final markers + .zskills/landed when done
#   multi-progress        alias of success (multi-phase plans progress one
#                         unit per call until complete)
#   no-progress           output only; zero durable writes
#   missing-handoff       progress but no handoff marker
#   missing-verifier      progress but no verifier marker set at all
#   missing-tests-run     progress with full set EXCEPT step.verify-changes.
#                         <tid>.tests-run
#   missing-report        progress but the report is never written
#   malformed-report      report written WITHOUT the required current-format
#                         patterns (## Phase / **Status:** / ### Verification)
#   premature-final       final run-plan markers written while phases remain
#   dirty                 progress + a stray non-.zskills artifact left behind
#   stale-markers         progress, but pre-existing markers are NOT
#                         re-touched (content hash unchanged → stale)
#   sleep                 silent sleep (drives the wall timeout)
#   idle                  one line, then silence (drives the idle timeout)
#   nonzero-exit          exits 7 with stderr (raw child failure)
#   sandbox-fail          bwrap/user-namespace stderr, exit 1 (sandbox triage)
#   pr-wrong-tracking     markers written under the ARTIFACT root's tracking
#                         dir instead of the contract tracking directory
#                         (violates the tracking-root split)
#   mid-run-stop          success behavior + writes the runner's stop marker
#                         during the chunk (the loop must honor it before the
#                         NEXT chunk)
#   resume-mismatch       resume calls fail with the distinct mismatch error
#   session-lost          fresh exec behaves like success; resume calls fail
#                         with a distinguishable session-not-found error
#   schema-conforming     success + a schema-CONFORMING JSON self-report in
#                         the -o file
#   claim-evidence-mismatch  durable evidence says "phase done, plan NOT
#                         complete" while the JSON self-report CLAIMS the
#                         plan is complete (lie-detection fixture)
#
# Tunables: FAKE_CODEX_SLEEP_SECONDS (default 5),
#           FAKE_CODEX_LANDED_STATUS (default landed).

set -euo pipefail

PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python || true)}"
if [ -z "$PYTHON" ]; then
  echo "fake-codex: python3/python is required" >&2
  exit 99
fi

if [ "${1:-}" = "--version" ]; then
  echo "fake-codex 2.0"
  exit 0
fi

if [ "${1:-}" != "exec" ]; then
  echo "fake-codex: expected 'exec' as the first argument (got '${1:-}')" >&2
  exit 99
fi
shift

# FAIL-FAST: an exec invocation without a prepared mode is an unprepared
# call — exit 99 loudly (mock-gh.sh doctrine), never a silent success.
MODE="${FAKE_CODEX_MODE:-}"
if [ -z "$MODE" ]; then
  echo "fake-codex: unprepared invocation — FAKE_CODEX_MODE is not set (args: exec $*)" >&2
  exit 99
fi

RESUME=0
RESUME_ID=""
# `exec resume <ID> ...` — resume is a positional subcommand of exec.
# Probe anchors: exec.resume.same-session, exec.resume.prompt-and-json
# (positional prompt accepted non-interactively on a resumed turn).
if [ "${1:-}" = "resume" ]; then
  RESUME=1
  RESUME_ID="${2:-}"
  shift 2
fi

REPO=""
JSON_MODE=0
LAST_MESSAGE=""
OUTPUT_SCHEMA=""
PROMPT=""
ORIG_ARGS=("exec")
[ "$RESUME" -eq 1 ] && ORIG_ARGS+=("resume" "$RESUME_ID")
while [ $# -gt 0 ]; do
  case "$1" in
    -C)                        REPO="$2"; ORIG_ARGS+=("$1" "$2"); shift 2 ;;
    --add-dir|--sandbox|-c)    ORIG_ARGS+=("$1" "$2"); shift 2 ;;
    --json)                    JSON_MODE=1; ORIG_ARGS+=("$1"); shift ;;
    # Probe anchor: exec.output-last-message (the file contains the final
    # message).
    -o|--output-last-message)  LAST_MESSAGE="$2"; ORIG_ARGS+=("$1" "$2"); shift 2 ;;
    # Probe anchor: exec.output-schema (schema-conforming/violating
    # self-report behavior recorded either way).
    --output-schema)           OUTPUT_SCHEMA="$2"; ORIG_ARGS+=("$1" "$2"); shift 2 ;;
    *)                         PROMPT="$1"; ORIG_ARGS+=("$1"); shift ;;
  esac
done

if [ -z "$REPO" ]; then
  echo "fake-codex: unprepared invocation — no -C <repo> given" >&2
  exit 99
fi

STATE_DIR="$REPO/.zskills/fake-codex"
mkdir -p "$STATE_DIR"

# Argv log — one line per invocation. Tests assert e.g. that fresh-mode
# (`finish auto`) invocations never contain ` resume ` in the logged argv.
{
  printf '%s' "${ORIG_ARGS[0]}"
  i=1
  while [ "$i" -lt "${#ORIG_ARGS[@]}" ]; do
    printf ' %s' "$(printf '%s' "${ORIG_ARGS[$i]}" | tr '\n' ' ')"
    i=$((i + 1))
  done
  printf '\n'
} >> "$STATE_DIR/argv.log"

THREAD_FILE="$STATE_DIR/thread-id"

# ── resume semantics ─────────────────────────────────────────────────────────
# Probe anchor: exec.resume.session-loss — resume of a bogus/deleted id fails
# with a non-zero, DISTINGUISHABLE error, never a silent fresh session.
if [ "$RESUME" -eq 1 ]; then
  case "$MODE" in
    session-lost)
      echo "fake-codex: error: session not found: ${RESUME_ID:-<empty>} (simulated session loss)" >&2
      exit 1
      ;;
    resume-mismatch)
      echo "fake-codex: error: resume-mismatch: presented session id '${RESUME_ID:-<empty>}' does not match the stored session" >&2
      exit 1
      ;;
    *)
      # Probe anchor: exec.resume.same-session — a resumed turn reaches the
      # SAME durable session; the fake enforces it structurally: the
      # presented id must equal the stored one.
      STORED_ID=""
      [ -f "$THREAD_FILE" ] && STORED_ID="$(cat "$THREAD_FILE")"
      if [ -z "$STORED_ID" ]; then
        echo "fake-codex: error: session not found: ${RESUME_ID:-<empty>} (no session was ever started)" >&2
        exit 1
      fi
      if [ "$RESUME_ID" != "$STORED_ID" ]; then
        echo "fake-codex: error: resume-mismatch: presented session id '${RESUME_ID:-<empty>}' != stored '$STORED_ID'" >&2
        exit 1
      fi
      THREAD_ID="$STORED_ID"
      ;;
  esac
else
  # Fresh exec — issue a new durable session id and persist it.
  THREAD_ID="fake-thread-$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
  printf '%s\n' "$THREAD_ID" > "$THREAD_FILE"
fi

# ── JSONL emission ───────────────────────────────────────────────────────────
# Probe anchor: exec.json.thread-id — the thread.started JSONL event carries
# a thread id that a subsequent `exec resume <ID>` accepts.
emit_thread_started() {
  [ "$JSON_MODE" -eq 1 ] || return 0
  printf '{"type":"thread.started","thread_id":"%s"}\n' "$THREAD_ID"
}
emit_item_completed() {
  [ "$JSON_MODE" -eq 1 ] || { printf '%s\n' "fake-codex: $1"; return 0; }
  printf '{"type":"item.completed","item":{"type":"agent_message","text":"%s"}}\n' "$1"
}
emit_turn_completed() {
  [ "$JSON_MODE" -eq 1 ] || return 0
  printf '{"type":"turn.completed","usage":{"input_tokens":123,"output_tokens":45}}\n'
}

# ── contract-value parsing (`- Label: value` lines of the runner prompt) ────
contract_value() {
  local label="$1" fallback="${2:-}"
  local value
  value=$(printf '%s\n' "$PROMPT" | sed -n "s/^- $label: //p" | sed -n '1p')
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

ARTIFACT_ROOT="$(contract_value 'Active artifact root' "$REPO")"
PLAN_PATH="$(contract_value 'Plan path' "$REPO/plans/example.md")"
REPORT_PATH="$(contract_value 'Report path' "$REPO/docs/reports/plan-example.md")"
PIPELINE_ID="$(contract_value 'Pipeline id' 'run-plan.example')"
TRACKING_DIR="$(contract_value 'Tracking directory' "$REPO/.zskills/tracking/$PIPELINE_ID")"
# The Tracking-id contract line reads:
#   - Tracking id: use exactly <tid> for every marker written by this chunk.
TRACKING_ID=$(printf '%s\n' "$PROMPT" \
  | sed -n 's/^- Tracking id: use exactly \([^ ]*\) .*$/\1/p' | sed -n '1p')
[ -n "$TRACKING_ID" ] || TRACKING_ID="${PIPELINE_ID#run-plan.}"

# Unique-per-invocation marker payload so every re-touched marker's content
# hash CHANGES (the runner's marker_changed staleness check keys on content,
# not existence).
STAMP="$(date -u +%Y%m%dT%H%M%SZ).$$.$RANDOM"

# ── plan mutation in CURRENT artifact formats ────────────────────────────────
# Mutates ONE incomplete unit across the current tracker formats: progress
# table row (✅ Done), checkbox (- [x]), and — when the mutation completes the
# plan — the frontmatter `status:` flip. Prints "remaining=<n>" on stdout.
advance_plan() {
  "$PYTHON" - "$PLAN_PATH" <<'PY'
import re, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()

changed = False

# 1. Progress-tracker table: flip the first not-started/in-progress row.
table_todo = re.compile(r"^(\|[^\n]*?\|\s*)(⬜|⬚|🟡)[^|\n]*(\|[^\n]*)$", re.M)
m = table_todo.search(text)
if m:
    text = text[:m.start()] + m.group(1) + "✅ Done " + m.group(3) + text[m.end():]
    changed = True

# 2. Checklist: flip the first unchecked box (only when no table row was
#    available — one unit of progress per invocation).
if not changed:
    m = re.search(r"^(\s*[-*] )\[ \]", text, re.M)
    if m:
        text = text[:m.start()] + m.group(1) + "[x]" + text[m.end():]
        changed = True

# Count remaining incomplete units across formats.
remaining = 0
remaining += len(re.findall(r"^\|[^\n]*(⬜|⬚|🟡)[^\n]*$", text, re.M))
remaining += len(re.findall(r"^\s*[-*] \[ \]", text, re.M))

# 3. Frontmatter status flip when the plan just completed.
if changed and remaining == 0:
    fm = re.match(r"\A---\n(.*?\n)---\n", text, re.S)
    if fm:
        body = fm.group(1)
        if re.search(r"^status:", body, re.M):
            body = re.sub(r"^status:.*$", "status: complete", body, count=1, flags=re.M)
        else:
            body = body + "status: complete\n"
        text = "---\n" + body + "---\n" + text[fm.end():]

with open(path, "w", encoding="utf-8") as f:
    f.write(text)

print(f"remaining={remaining}")
print(f"changed={'yes' if changed else 'no'}")
PY
}

plan_phase_number() {
  # Count of ✅/[x] units AFTER the mutation — used as the phase number in
  # the prepended report section.
  "$PYTHON" - "$PLAN_PATH" <<'PY'
import re, sys
with open(sys.argv[1], encoding="utf-8") as f:
    text = f.read()
done = len(re.findall(r"✅\s*Done", text)) + len(re.findall(r"^\s*[-*] \[x\]", text, re.M))
print(done or 1)
PY
}

# ── report prepend in the CURRENT Phase-5 format ─────────────────────────────
write_report() {
  local malformed="${1:-no}" phase
  phase="$(plan_phase_number)"
  mkdir -p "$(dirname "$REPORT_PATH")"
  local existing=""
  [ -f "$REPORT_PATH" ] && existing="$(cat "$REPORT_PATH")"
  if [ "$malformed" = "yes" ]; then
    {
      printf 'Fixture report without the required patterns.\n'
      printf 'phase %s stamp %s\n' "$phase" "$STAMP"
      if [ -n "$existing" ]; then printf '\n%s\n' "$existing"; fi
    } > "$REPORT_PATH"
    return 0
  fi
  # Sections are PREPENDED newest-first (current report contract).
  {
    printf '## Phase %s — Fixture Progress\n\n' "$phase"
    printf '**Status:** Complete\n\n'
    printf 'Fixture progress for runner validation (stamp %s).\n\n' "$STAMP"
    printf '### Verification\n\n'
    printf -- '- fake verifier passed; tests run.\n'
    if [ -n "$existing" ]; then printf '\n%s\n' "$existing"; fi
  } > "$REPORT_PATH"
}

# ── marker writes ────────────────────────────────────────────────────────────
write_marker() {
  # write_marker <dir> <name> [skip-if-present]
  local dir="$1" name="$2" skip="${3:-no}"
  mkdir -p "$dir"
  if [ "$skip" = "yes" ] && [ -e "$dir/$name" ]; then
    return 0
  fi
  printf '%s %s\n' "$name" "$STAMP" > "$dir/$name"
}

write_landed() {
  local status="${FAKE_CODEX_LANDED_STATUS:-landed}"
  mkdir -p "$ARTIFACT_ROOT/.zskills"
  cat > "$ARTIFACT_ROOT/.zskills/landed" <<LANDED
status: $status
date: $STAMP
source: fake-codex
commits: fixture
LANDED
}

commit_artifacts() {
  # Keep the tree clean the way a real chunk lands its work. Commit in the
  # artifact root's git tree (repo root or PR worktree).
  git -C "$ARTIFACT_ROOT" add -A -- "$PLAN_PATH" "$REPORT_PATH"
  if ! git -C "$ARTIFACT_ROOT" diff --cached --quiet 2>/dev/null; then
    git -C "$ARTIFACT_ROOT" -c user.email=fake-codex@example.test -c user.name=fake-codex \
      commit -q -m "fixture chunk progress ($STAMP)"
  fi
}

# ── self-report (last message / --output-schema) ─────────────────────────────
# Probe anchors: exec.output-last-message, exec.output-schema.
write_self_report() {
  # write_self_report <status> <remaining>
  local status="$1" remaining="$2"
  [ -n "$LAST_MESSAGE" ] || return 0
  if [ -n "$OUTPUT_SCHEMA" ] || [ "$MODE" = "schema-conforming" ] || [ "$MODE" = "claim-evidence-mismatch" ]; then
    "$PYTHON" - "$LAST_MESSAGE" "$status" "$remaining" "$TRACKING_ID" <<'PY'
import json, sys
path, status, remaining, tid = sys.argv[1:5]
doc = {
    "phase_executed": "fixture-phase",
    "status": status,
    "landing_status": "landed" if status == "complete" else "pending",
    "tracking_id": tid,
    "remaining_phases": int(remaining),
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(doc, f)
    f.write("\n")
PY
  else
    printf 'fake-codex last message (%s, remaining=%s)\n' "$MODE" "$remaining" > "$LAST_MESSAGE"
  fi
}

# ── shared progress engine ───────────────────────────────────────────────────
REMAINING=""
run_progress() {
  # run_progress <handoff:yes|no> <verifier:full|none|no-tests-run>
  #              <report:normal|missing|malformed> <final:auto|force|suppress>
  #              <markers:fresh|stale-skip> <tracking-dir-override or ->
  local handoff="$1" verifier="$2" report="$3" final="$4" markers="$5" tdir="$6"
  [ "$tdir" = "-" ] && tdir="$TRACKING_DIR"
  local skip=no
  [ "$markers" = "stale-skip" ] && skip=yes

  local advance_out
  advance_out="$(advance_plan)"
  REMAINING="$(printf '%s\n' "$advance_out" | sed -n 's/^remaining=//p')"

  case "$report" in
    normal)    write_report no ;;
    malformed) write_report yes ;;
    missing)   : ;;
  esac

  write_marker "$tdir" "step.run-plan.$TRACKING_ID.implement" "$skip"
  write_marker "$tdir" "step.run-plan.$TRACKING_ID.verify" "$skip"
  write_marker "$tdir" "step.run-plan.$TRACKING_ID.report" "$skip"
  case "$verifier" in
    full)
      write_marker "$tdir" "requires.verify-changes.$TRACKING_ID" "$skip"
      write_marker "$tdir" "step.verify-changes.$TRACKING_ID.tests-run" "$skip"
      write_marker "$tdir" "step.verify-changes.$TRACKING_ID.complete" "$skip"
      write_marker "$tdir" "fulfilled.verify-changes.$TRACKING_ID" "$skip"
      ;;
    no-tests-run)
      write_marker "$tdir" "requires.verify-changes.$TRACKING_ID" "$skip"
      write_marker "$tdir" "step.verify-changes.$TRACKING_ID.complete" "$skip"
      write_marker "$tdir" "fulfilled.verify-changes.$TRACKING_ID" "$skip"
      ;;
    none) : ;;
  esac

  local is_final=no
  case "$final" in
    force) is_final=yes ;;
    suppress) is_final=no ;;
    auto) [ "${REMAINING:-1}" = "0" ] && is_final=yes ;;
  esac

  if [ "$is_final" = "yes" ]; then
    write_marker "$tdir" "requires.verify-changes.final.$TRACKING_ID" "$skip"
    write_marker "$tdir" "fulfilled.verify-changes.final.$TRACKING_ID" "$skip"
    write_marker "$tdir" "step.run-plan.$TRACKING_ID.land" "$skip"
    write_marker "$tdir" "fulfilled.run-plan.$TRACKING_ID" "$skip"
    rm -f "$tdir/handoff.run-plan.$TRACKING_ID"
    write_landed
  elif [ "$handoff" = "yes" ]; then
    write_marker "$tdir" "handoff.run-plan.$TRACKING_ID" "$skip"
  fi

  case "$report" in
    normal|malformed) commit_artifacts ;;
  esac
}

# ── mode dispatch ────────────────────────────────────────────────────────────
emit_thread_started

case "$MODE" in
  success|multi-progress|schema-conforming|mid-run-stop|session-lost|dirty|stale-markers)
    MARKERS=fresh
    [ "$MODE" = "stale-markers" ] && MARKERS=stale-skip
    run_progress yes full normal auto "$MARKERS" -
    if [ "$MODE" = "dirty" ]; then
      printf 'dirty %s\n' "$STAMP" > "$ARTIFACT_ROOT/dirty-artifact.txt"
    fi
    if [ "$MODE" = "mid-run-stop" ]; then
      # Derive the runner's per-plan stop-marker path from its own lock dir
      # (<plan_key>.lock is held for the whole run); the loop must honor the
      # marker BEFORE the next chunk.
      for lock in "$REPO/.zskills/runner/"*.lock; do
        [ -d "$lock" ] || continue
        stop_path="${lock%.lock}.stop"
        printf 'stopped-by: fake-codex mid-run-stop\nstamp: %s\n' "$STAMP" > "$stop_path"
      done
    fi
    STATUS_WORD=$([ "${REMAINING:-1}" = "0" ] && echo complete || echo in-progress)
    emit_item_completed "progress ($MODE, remaining=$REMAINING)"
    emit_turn_completed
    write_self_report "$STATUS_WORD" "${REMAINING:-0}"
    exit 0
    ;;
  claim-evidence-mismatch)
    # Durable evidence: one phase done, handoff written, plan NOT complete.
    # Self-report: CLAIMS the plan is complete with zero remaining phases.
    run_progress yes full normal suppress fresh -
    emit_item_completed "progress (claim-evidence-mismatch, remaining=$REMAINING)"
    emit_turn_completed
    write_self_report "complete" "0"
    exit 0
    ;;
  no-progress)
    emit_item_completed "no progress"
    emit_turn_completed
    write_self_report "in-progress" "1"
    exit 0
    ;;
  missing-handoff)
    run_progress no full normal suppress fresh -
    emit_item_completed "progress without handoff"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  missing-verifier)
    run_progress yes none normal suppress fresh -
    emit_item_completed "progress without verifier markers"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  missing-tests-run)
    run_progress yes no-tests-run normal suppress fresh -
    emit_item_completed "progress without tests-run marker"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  missing-report)
    run_progress yes full missing suppress fresh -
    emit_item_completed "progress without report"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  malformed-report)
    run_progress yes full malformed suppress fresh -
    emit_item_completed "progress with malformed report"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  premature-final)
    run_progress yes full normal force fresh -
    emit_item_completed "progress with premature final markers"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  pr-wrong-tracking)
    # Violates the tracking-root split: markers land under the ARTIFACT
    # root's tracking dir instead of the repo root's contract dir.
    run_progress yes full normal auto fresh "$ARTIFACT_ROOT/.zskills/tracking/$PIPELINE_ID"
    emit_item_completed "progress with wrong tracking root"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  sleep)
    sleep "${FAKE_CODEX_SLEEP_SECONDS:-5}"
    emit_item_completed "slept"
    write_self_report "in-progress" "1"
    exit 0
    ;;
  idle)
    emit_item_completed "before idle"
    sleep "${FAKE_CODEX_SLEEP_SECONDS:-5}"
    write_self_report "in-progress" "1"
    exit 0
    ;;
  nonzero-exit)
    echo "fake-codex: simulated child failure" >&2
    exit 7
    ;;
  sandbox-fail)
    # Sandbox-triage fixture (spec change 7): the runner greps the child
    # output for bwrap/user-namespace failure signatures.
    echo "bwrap: No permissions to create a new namespace — Operation not permitted" >&2
    exit 1
    ;;
  resume-mismatch)
    # A FRESH call in resume-mismatch mode still behaves like success so the
    # scenario's first fire can establish state; the mismatch fires on the
    # resume branch above.
    run_progress yes full normal auto fresh -
    emit_item_completed "progress (resume-mismatch mode, fresh call)"
    emit_turn_completed
    write_self_report "in-progress" "${REMAINING:-1}"
    exit 0
    ;;
  *)
    echo "fake-codex: unprepared invocation — unknown FAKE_CODEX_MODE='$MODE'" >&2
    exit 99
    ;;
esac
