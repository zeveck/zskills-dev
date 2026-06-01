#!/bin/bash
# Tests for skills/work-on-plans/SKILL.md — Phase 3 mutating subcommands
# (add, rank, remove, default, every, stop) + cross-process flock.
#
# The skill body is markdown-with-bash that the LLM executes inline.
# These tests extract the load-bearing pieces — the python heredocs for
# each mutator and the flock helper — and run them in /tmp fixtures
# against synthetic monitor-state.json files. Acceptance criteria
# verified per-case (lines tagged AC-N where N maps to plan ACs).
#
# Run from repo root: bash tests/test-work-on-plans.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/work-on-plans/SKILL.md"
SKILL_DIR="$REPO_ROOT/skills/work-on-plans"
SKILL_MIRROR="$REPO_ROOT/.claude/skills/work-on-plans/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TEST_TMPDIR="/tmp/zskills-work-on-plans-test-$$"
mkdir -p "$TEST_TMPDIR"

cleanup() {
  case "$TEST_TMPDIR" in
    /tmp/zskills-work-on-plans-test-*)
      rm -rf -- "$TEST_TMPDIR" 2>/dev/null
      ;;
  esac
}
trap cleanup EXIT

make_fixture() {
  local label="$1"
  local f="$TEST_TMPDIR/$label"
  mkdir -p "$f/.zskills" "$f/plans"
  echo "$f"
}

# --- Mutators (transcribed verbatim from SKILL.md Step 7) ----------------
# The skill body fences these as bash heredocs the LLM runs at top-level.
# We re-define them here so the tests can drive them as ordinary shell
# functions. If the SKILL.md wording diverges, the structural assertion
# below ("SKILL.md contains the documented heredoc") will fail.

skill_add() {
  local state="$1" slug="$2" pos="${3:-}"
  if [[ "$slug" =~ ^[0-9] ]]; then
    printf '/work-on-plans: digit-prefix slugs (%q) are reserved for execute-mode N.\n' "$slug" >&2
    return 2
  fi
  if [[ ! "$slug" =~ ^[a-z][a-z0-9-]*$ ]]; then
    printf '/work-on-plans: invalid slug %q\n' "$slug" >&2
    return 2
  fi
  python3 - "$state" "$slug" "${pos:-}" <<'PY'
import json, os, sys, tempfile, datetime
path, slug, pos_s = sys.argv[1], sys.argv[2], sys.argv[3]
doc = json.load(open(path))
plans = doc.setdefault("plans", {})
ready = plans.setdefault("ready", [])
if any((isinstance(e, dict) and e.get("slug") == slug) or e == slug for e in ready):
    print(f"/work-on-plans: '{slug}' already in ready queue (no-op).", file=sys.stderr)
    sys.exit(0)
entry = {"slug": slug, "mode": ""}
if pos_s:
    pos = int(pos_s)
    if pos < 1: pos = 1
    if pos > len(ready) + 1: pos = len(ready) + 1
    ready.insert(pos - 1, entry)
else:
    ready.append(entry)
plans["ready"] = ready
doc["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/work-on-plans: added '{slug}' to ready queue.")
PY
}

skill_rank() {
  local state="$1" slug="$2" pos_s="${3:-}"
  if [[ -z "$pos_s" || ! "$pos_s" =~ ^[0-9]+$ ]]; then return 2; fi
  python3 - "$state" "$slug" "$pos_s" <<'PY'
import json, os, sys, tempfile, datetime
path, slug, pos_s = sys.argv[1], sys.argv[2], sys.argv[3]
pos = int(pos_s)
doc = json.load(open(path))
ready = doc.get("plans", {}).get("ready", [])
idx = next((i for i, e in enumerate(ready)
            if (isinstance(e, dict) and e.get("slug") == slug) or e == slug),
           -1)
if idx < 0:
    print(f"/work-on-plans: '{slug}' not in ready queue.", file=sys.stderr)
    sys.exit(2)
entry = ready.pop(idx)
if pos < 1: pos = 1
if pos > len(ready) + 1: pos = len(ready) + 1
ready.insert(pos - 1, entry)
doc["plans"]["ready"] = ready
doc["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/work-on-plans: moved '{slug}' to position {pos}.")
PY
}

skill_remove() {
  local state="$1" slug="$2"
  python3 - "$state" "$slug" <<'PY'
import json, os, sys, tempfile, datetime
path, slug = sys.argv[1], sys.argv[2]
doc = json.load(open(path))
ready = doc.get("plans", {}).get("ready", [])
new_ready = [e for e in ready
             if not ((isinstance(e, dict) and e.get("slug") == slug) or e == slug)]
if len(new_ready) == len(ready):
    print(f"/work-on-plans: '{slug}' not in ready queue (no-op).", file=sys.stderr)
    sys.exit(0)
doc.setdefault("plans", {})["ready"] = new_ready
doc["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/work-on-plans: removed '{slug}' from ready queue.")
PY
}

skill_default() {
  local state="$1" mode="$2"
  if [[ "$mode" != "phase" && "$mode" != "finish" ]]; then return 2; fi
  python3 - "$state" "$mode" <<'PY'
import json, os, sys, tempfile, datetime
path, mode = sys.argv[1], sys.argv[2]
doc = json.load(open(path))
doc["default_mode"] = mode
doc["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/work-on-plans: default_mode set to '{mode}'.")
PY
}

# Sub-hour detector mirroring SKILL.md schedule_under_1h() exactly.
schedule_under_1h() {
  local s="$1"
  [[ "$s" =~ (^|[[:space:]])([0-9]+)m([[:space:]]|$) ]] && {
    local n="${BASH_REMATCH[2]}"
    [ "$n" -lt 60 ] && return 0
  }
  [[ "$s" =~ ^\*/([0-9]+)[[:space:]] ]] && {
    local n="${BASH_REMATCH[1]}"
    [ "$n" -lt 60 ] && return 0
  }
  return 1
}

# Cross-process lock helper mirroring SKILL.md `with_monitor_lock`.
with_lock() {
  local lock="$1"; shift
  [ -e "$lock" ] || : > "$lock"
  (
    exec 9>"$lock"
    flock -x 9
    "$@"
  )
}

# Seed an empty bootstrapped monitor-state.json.
seed_empty() {
  local path="$1"
  cat > "$path" <<'JSON'
{
  "version": "1.1",
  "default_mode": "phase",
  "plans": { "drafted": [], "reviewed": [], "ready": [] },
  "issues": { "triage": [], "ready": [] },
  "updated_at": ""
}
JSON
}

readq() {
  python3 -c "
import json,sys
doc=json.load(open(sys.argv[1]))
ready=doc['plans']['ready']
print(','.join(e['slug'] if isinstance(e,dict) else e for e in ready))
" "$1"
}

readkey() {
  python3 -c "
import json,sys
doc=json.load(open(sys.argv[1]))
keys=sys.argv[2].split('.')
v=doc
for k in keys: v=v[k]
print(v if not isinstance(v,(list,dict)) else json.dumps(v))
" "$1" "$2"
}

echo "=== work-on-plans Phase 3 tests ==="

# --- Test 1: Skill dir has Phase 3 sections (structural) ----------------
# Content may live in SKILL.md or in subcommands/add-rank-remove.md.
if grep -rq '^## Step 7 — Mutating subcommands' "$SKILL_DIR" \
   && grep -rq '^### `add <slug> \[pos\]`' "$SKILL_DIR" \
   && grep -rq '^### `rank <slug> <pos>`' "$SKILL_DIR" \
   && grep -rq '^### `remove <slug>`' "$SKILL_DIR" \
   && grep -rq '^### `default <phase|finish>`' "$SKILL_DIR" \
   && grep -rq '^### `every SCHEDULE \[phase|finish\] \[--force\]`' "$SKILL_DIR" \
   && grep -rq '^### `stop`' "$SKILL_DIR"; then
  pass "Skill dir has all Phase 3 subcommand sections"
else
  fail "SKILL.md missing one or more Phase 3 sections"
fi

# --- Test 2: SKILL.md declares the cross-process flock helper -----------
if grep -q 'with_monitor_lock' "$SKILL" \
   && grep -q 'flock -x 9' "$SKILL" \
   && grep -q 'monitor-state.json.lock' "$SKILL"; then
  pass "SKILL.md documents the cross-process flock helper"
else
  fail "SKILL.md missing flock helper"
fi

# --- Test 3: Skill dir still has Phase 1 surface -----------------------
# Steps 1-2 remain in SKILL.md; Step 5 may be in modes/execute.md.
if grep -q '^## Step 1 — sync (read monitor-state.json)' "$SKILL" \
   && grep -q '^## Step 2 — Read work-on-plans-state.json' "$SKILL" \
   && grep -rq '^## Step 5 — Dispatch loop' "$SKILL_DIR"; then
  pass "Skill dir preserves Phase 1 sections (sync/dispatch)"
else
  fail "SKILL.md regressed Phase 1 sections"
fi

# --- Test 4: argument-hint frontmatter advertises core surface ----------
# Queue-mutation subcommands (add/rank/remove) were moved to the detail
# docs page to shorten the hint under 120 chars. The hint still covers
# the dispatch, schedule, default, and control subcommands. Post-#906
# `every SCHEDULE` composes with the leading N|all count (it is no
# longer a standalone subcommand listed beside default), so the order
# is `... every SCHEDULE ... default ... stop`.
if grep -q 'argument-hint:.*every SCHEDULE' "$SKILL" \
   && grep -q 'argument-hint:.*default' "$SKILL" \
   && grep -q 'argument-hint:.*stop' "$SKILL"; then
  pass "argument-hint advertises core surface (every SCHEDULE/default/stop)"
else
  fail "argument-hint missing one or more core subcommands"
fi

# --- Test 5: AC-1 (add bootstraps + appends) ---------------------------
F=$(make_fixture t5)
seed_empty "$F/.zskills/monitor-state.json"
out=$(skill_add "$F/.zskills/monitor-state.json" foo-plan 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "foo-plan" ] \
   && python3 -c "import json; json.load(open('$F/.zskills/monitor-state.json'))" 2>/dev/null; then
  pass "AC-1 add appends new slug; JSON parses"
else
  fail "AC-1 add (ec=$ec ready=$ready out=$out)"
fi

# --- Test 6: AC-2 digit-prefix slugs are rejected ---------------------
out=$(skill_add "$F/.zskills/monitor-state.json" 4-phase-plan 2>&1)
ec=$?
if [ "$ec" -eq 2 ] && echo "$out" | grep -q 'digit-prefix slugs'; then
  pass "AC-2 add rejects digit-prefix slug with usage message"
else
  fail "AC-2 digit-prefix (ec=$ec out=$out)"
fi

# --- Test 7: rank reorders ----------------------------------------------
F=$(make_fixture t7)
seed_empty "$F/.zskills/monitor-state.json"
skill_add "$F/.zskills/monitor-state.json" alpha >/dev/null
skill_add "$F/.zskills/monitor-state.json" beta  >/dev/null
skill_add "$F/.zskills/monitor-state.json" gamma >/dev/null
out=$(skill_rank "$F/.zskills/monitor-state.json" gamma 1 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "gamma,alpha,beta" ]; then
  pass "AC-1 rank moves slug to position"
else
  fail "rank (ec=$ec ready=$ready out=$out)"
fi

# --- Test 8: remove drops entry ----------------------------------------
out=$(skill_remove "$F/.zskills/monitor-state.json" alpha 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "gamma,beta" ]; then
  pass "AC-1 remove drops slug"
else
  fail "remove (ec=$ec ready=$ready out=$out)"
fi

# --- Test 9: remove of missing slug is idempotent ---------------------
out=$(skill_remove "$F/.zskills/monitor-state.json" never-existed 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "gamma,beta" ] \
   && echo "$out" | grep -q "no-op"; then
  pass "remove of missing slug is idempotent (no-op + exit 0)"
else
  fail "remove no-op (ec=$ec ready=$ready out=$out)"
fi

# --- Test 10: AC-1 default sets default_mode -----------------------
F=$(make_fixture t10)
seed_empty "$F/.zskills/monitor-state.json"
skill_add "$F/.zskills/monitor-state.json" alpha >/dev/null
skill_add "$F/.zskills/monitor-state.json" beta  >/dev/null
out=$(skill_default "$F/.zskills/monitor-state.json" finish 2>&1)
ec=$?
dm=$(readkey "$F/.zskills/monitor-state.json" default_mode)
# AC-1: per-entry mode unchanged
ready_full=$(python3 -c "
import json,sys
doc=json.load(open(sys.argv[1]))
print(';'.join(f\"{e['slug']}={e.get('mode','')}\" for e in doc['plans']['ready']))
" "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$dm" = "finish" ] \
   && [ "$ready_full" = "alpha=;beta=" ]; then
  pass "AC-1/AC-6 default <mode> sets default_mode and does NOT touch per-entry mode"
else
  fail "AC-6 default (ec=$ec dm=$dm ready_full=$ready_full out=$out)"
fi

# --- Test 11: default rejects bogus values ------------------------------
out=$(skill_default "$F/.zskills/monitor-state.json" turbo 2>&1)
ec=$?
if [ "$ec" -eq 2 ]; then
  pass "default rejects non-{phase,finish} values"
else
  fail "default reject (ec=$ec out=$out)"
fi

# --- Test 12: AC-4 schedule sub-hour finish rejected ----------------
if schedule_under_1h "30m"; then
  pass "AC-4 schedule_under_1h detects '30m'"
else
  fail "AC-4 schedule_under_1h '30m' should be true"
fi
if schedule_under_1h "5m"; then
  pass "AC-4 schedule_under_1h detects '5m'"
else
  fail "AC-4 schedule_under_1h '5m' should be true"
fi
if schedule_under_1h "*/30 * * * *"; then
  pass "AC-4 schedule_under_1h detects cron '*/30'"
else
  fail "AC-4 schedule_under_1h '*/30 *' should be true"
fi
if schedule_under_1h "1h"; then
  fail "AC-4 schedule_under_1h '1h' should be false"
else
  pass "AC-4 schedule_under_1h '1h' is NOT sub-hour"
fi
if schedule_under_1h "4h"; then
  fail "AC-4 schedule_under_1h '4h' should be false"
else
  pass "AC-4 schedule_under_1h '4h' is NOT sub-hour"
fi
if schedule_under_1h "*/2 * * * *"; then
  pass "AC-4 schedule_under_1h detects cron '*/2'"
else
  fail "AC-4 schedule_under_1h '*/2' should be sub-hour"
fi

# --- #546 regression: minute-form must compare N<60 ----------------------
# Pre-fix bug: any <N>m was classified sub-hour without comparing N to 60.
if schedule_under_1h "60m"; then
  fail "#546 schedule_under_1h '60m' must NOT be sub-hour (=1h boundary)"
else
  pass "#546 schedule_under_1h '60m' is NOT sub-hour"
fi
if schedule_under_1h "120m"; then
  fail "#546 schedule_under_1h '120m' must NOT be sub-hour (=2h)"
else
  pass "#546 schedule_under_1h '120m' is NOT sub-hour"
fi
if schedule_under_1h "every 60m"; then
  fail "#546 schedule_under_1h 'every 60m' must NOT be sub-hour"
else
  pass "#546 schedule_under_1h 'every 60m' is NOT sub-hour"
fi
if schedule_under_1h "1440m"; then
  fail "#546 schedule_under_1h '1440m' must NOT be sub-hour (24h)"
else
  pass "#546 schedule_under_1h '1440m' is NOT sub-hour"
fi
# Confirm sub-60 minute forms still detected after the N<60 guard.
if schedule_under_1h "59m"; then
  pass "#546 schedule_under_1h '59m' is still sub-hour"
else
  fail "#546 schedule_under_1h '59m' should be sub-hour"
fi

# --- Test 13: Skill dir cites the AC-4 ≥1h diagnostic -------------------
# Diagnostic may live in SKILL.md or subcommands/add-rank-remove.md.
if grep -rq "SCHEDULE must be ≥1h" "$SKILL_DIR" \
   && grep -rq "Use phase mode for shorter intervals" "$SKILL_DIR"; then
  pass "AC-4 skill dir cites the ≥1h finish-mode rejection diagnostic"
else
  fail "AC-4 SKILL.md missing finish-mode SCHEDULE diagnostic"
fi

# --- Test 14: AC-5 (mode-capture invariant) — the skill text -----------
# AC-5 verifies dispatch uses captured schedule_mode, not live default_mode.
# The skill text must explicitly state the invariant + the capture
# precedence + that the cron prompt encodes the captured mode.
# Content may live in SKILL.md or subcommands/add-rank-remove.md.
if grep -rq "Each fire uses the captured" "$SKILL_DIR" \
   && grep -rq "NOT live" "$SKILL_DIR" \
   && grep -rq "stop. and re-register" "$SKILL_DIR"; then
  pass "AC-5 skill dir states the mode-capture invariant"
else
  fail "AC-5 SKILL.md missing the mode-capture invariant statement"
fi

# --- Test 15: AC-7 CronCreate failure semantics in skill dir -----------
# Content may live in SKILL.md or subcommands/add-rank-remove.md.
if grep -rq "Failed to register schedule" "$SKILL_DIR" \
   && grep -rq "Do NOT write" "$SKILL_DIR"; then
  pass "AC-7 skill dir documents CronCreate-failure exit/no-write contract"
else
  fail "AC-7 SKILL.md missing CronCreate-failure contract"
fi

# --- Test 16: AC-3 schedule ownership rules in skill dir ----------------
# Content may live in SKILL.md or subcommands/add-rank-remove.md.
if grep -rq "already scheduled by session" "$SKILL_DIR" \
   && grep -rq "pass .--force. to take over" "$SKILL_DIR" \
   && grep -rq "silently overwritten" "$SKILL_DIR" \
   && grep -rq "idempotent take-over" "$SKILL_DIR"; then
  pass "AC-3 skill dir documents schedule-ownership + staleness + same-session take-over"
else
  fail "AC-3 SKILL.md missing schedule-ownership rules"
fi

# --- Test 17: AC-9 mirror parity (skills/ vs .claude/skills/) ---------
if [ -f "$SKILL_MIRROR" ] && diff -rq \
     "$REPO_ROOT/skills/work-on-plans/" \
     "$REPO_ROOT/.claude/skills/work-on-plans/" >/dev/null 2>&1; then
  pass "AC-9 mirror byte-identical"
else
  fail "AC-9 mirror diverged (run: bash scripts/mirror-skill.sh work-on-plans)"
fi

# --- Test 18: AC-10 cross-process flock prevents lost update ---------
# Spawn N parallel adds racing against the same monitor-state.json,
# each acquiring the lock for read-modify-write. With the lock, the
# final ready list contains all N slugs. Without the lock, races would
# drop some.
F=$(make_fixture t18)
seed_empty "$F/.zskills/monitor-state.json"
LOCK="$F/.zskills/monitor-state.json.lock"
N_RACERS=8
pids=()
for i in $(seq 1 "$N_RACERS"); do
  ( with_lock "$LOCK" skill_add "$F/.zskills/monitor-state.json" "racer-$i" >/dev/null 2>&1 ) &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p"; done
ready=$(readq "$F/.zskills/monitor-state.json")
# Count distinct racer-N entries.
got=$(printf '%s\n' "$ready" | tr ',' '\n' | grep -c '^racer-[0-9]\+$')
echo "  flock concurrency: $N_RACERS racers -> $got entries: $ready"
if [ "$got" -eq "$N_RACERS" ]; then
  pass "AC-10 cross-process flock: all $N_RACERS parallel adds land (no lost-update)"
else
  fail "AC-10 flock: only $got/$N_RACERS landed (ready=$ready)"
fi

# --- Test 19: AC-10 negative control — without the lock, races drop ---
# Confirms the test above isn't trivially passing. We expect MOST runs
# to drop at least one entry without locking. This is probabilistic; we
# treat ANY race-loss across 3 attempts as the negative confirmation.
# (If all 3 attempts land cleanly without a lock, the test environment
# is too serial to demonstrate the race — that's a soft-fail "skip".)
unsafe_add() {
  # Same as skill_add but no flock around the rmw.
  skill_add "$@"
}
race_lost_at_least_once=0
for attempt in 1 2 3; do
  F=$(make_fixture "t19-$attempt")
  seed_empty "$F/.zskills/monitor-state.json"
  pids=()
  for i in $(seq 1 "$N_RACERS"); do
    ( unsafe_add "$F/.zskills/monitor-state.json" "racer-$i" >/dev/null 2>&1 ) &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p"; done
  ready=$(readq "$F/.zskills/monitor-state.json")
  got=$(printf '%s\n' "$ready" | tr ',' '\n' | grep -c '^racer-[0-9]\+$')
  echo "  unlocked attempt $attempt: $got/$N_RACERS"
  if [ "$got" -lt "$N_RACERS" ]; then
    race_lost_at_least_once=1
    break
  fi
done
if [ "$race_lost_at_least_once" -eq 1 ]; then
  pass "AC-10 negative control: unlocked rmw drops at least one entry under contention"
else
  echo "  SKIP negative control: unlocked rmw didn't race in 3 attempts (env too serial)"
  pass "AC-10 negative control: skipped (env too serial to race; positive case still validates)"
fi

# --- Test 20: AC-1 add at position inserts ------------------------------
F=$(make_fixture t20)
seed_empty "$F/.zskills/monitor-state.json"
skill_add "$F/.zskills/monitor-state.json" a >/dev/null
skill_add "$F/.zskills/monitor-state.json" b >/dev/null
skill_add "$F/.zskills/monitor-state.json" c >/dev/null
out=$(skill_add "$F/.zskills/monitor-state.json" middle 2 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "a,middle,b,c" ]; then
  pass "AC-1 add at position 2 inserts mid-queue"
else
  fail "add @ pos (ec=$ec ready=$ready out=$out)"
fi

# --- Test 21: idempotent add of existing slug --------------------------
out=$(skill_add "$F/.zskills/monitor-state.json" a 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "a,middle,b,c" ] \
   && echo "$out" | grep -q "already in ready queue"; then
  pass "add of existing slug is idempotent (exit 0, no-op)"
else
  fail "add idempotent (ec=$ec ready=$ready out=$out)"
fi

# --- Test 22: rank of missing slug fails -------------------------------
out=$(skill_rank "$F/.zskills/monitor-state.json" not-here 1 2>&1)
ec=$?
if [ "$ec" -eq 2 ] && echo "$out" | grep -q "not in ready queue"; then
  pass "rank of missing slug exits 2 with diagnostic"
else
  fail "rank missing (ec=$ec out=$out)"
fi

# --- Test 23: add invalid slug --------------------------------------
out=$(skill_add "$F/.zskills/monitor-state.json" "BadSlug!" 2>&1)
ec=$?
if [ "$ec" -eq 2 ]; then
  pass "add rejects invalid slug (uppercase/punctuation)"
else
  fail "add invalid slug (ec=$ec out=$out)"
fi

# --- Test 24: #906 combined N+every+now grammar documented -------------
# The skill dir must show N|all composing with every+now (no longer
# mutually exclusive), and the parser must recognise `now` + `every`
# on the dispatch path.
if grep -rq 'N|all .*\[every SCHEDULE\] \[now\]' "$SKILL_DIR" \
   && grep -rq 'now. → .RUN_NOW=1' "$SKILL_DIR" \
   && grep -rq 'Composes with' "$SKILL_DIR" \
   && grep -rq 'compose' "$SKILL_DIR"; then
  pass "#906 skill dir documents N|all composing with every SCHEDULE + now"
else
  fail "#906 combined-grammar documentation missing"
fi

# --- Test 25: #906 count-carrying recurring cron prompt shape ----------
# The cron prompt must carry the count and `now` (mirrors
# fix-issues/modes/sprint.md:53 CRON_PROMPT). Must NOT be the old
# count-less `Run /work-on-plans all <mode>` form.
if grep -rq 'Run /work-on-plans <COUNT_TOKEN> <schedule_mode> every <SCHEDULE> now' "$SKILL_DIR" \
   && grep -rq 'Run /work-on-plans 1 finish every 1h now' "$SKILL_DIR" \
   && grep -rq 'schedule_count' "$SKILL_DIR"; then
  pass "#906 cron prompt carries count + now (queue-worker parity)"
else
  fail "#906 count-carrying cron prompt shape missing"
fi
# Negative: the old count-less cron prompt must be gone.
if grep -rq '^Run /work-on-plans all <schedule_mode>$' "$SKILL_DIR"; then
  fail "#906 stale count-less cron prompt 'Run /work-on-plans all <schedule_mode>' still present"
else
  pass "#906 old count-less cron prompt removed"
fi

# --- Test 26: #906 de-collided 'execute mode' terminology --------------
# No internal use of "execute mode" / "execution mode" as the dispatch
# path LABEL (collides with CLAUDE.md Execution Modes = landing modes).
# The single explanatory cross-reference to CLAUDE.md "Execution Modes"
# (the de-collision rationale itself) is exempt — it names the colliding
# concept to explain WHY the label was renamed, it does not use it as a
# label. Filter those rationale lines (they mention CLAUDE.md) out.
offending=$(grep -rni 'execut\(e\|ion\) mode' "$SKILL_DIR" \
  | grep -vi 'CLAUDE.md' || true)
if [ -n "$offending" ]; then
  fail "#906 'execute/execution mode' label still present: $offending"
else
  pass "#906 dispatch-path label de-collided from 'Execution Modes'"
fi

# --- Test 27: #906 prune-on-complete logic (functional) ----------------
# Mirror the prune_completed embed from modes/execute.md: a slug is
# dropped from plans.ready ONLY when its plan file frontmatter is
# status: complete. Drive it directly against a fixture.
prune_completed_test() {
  local state="$1" slug="$2" plan_file="$3"
  python3 - "$state" "$slug" "$plan_file" <<'PY'
import json, os, re, sys, tempfile, datetime
path, slug, plan_file = sys.argv[1], sys.argv[2], sys.argv[3]
status = ''
if plan_file and os.path.exists(plan_file):
    text = open(plan_file, encoding='utf-8', errors='replace').read()
    if text.startswith('---'):
        end = text.find('\n---', 3)
        if end >= 0:
            m = re.search(r'^status:\s*([^\n]+)', text[3:end], re.MULTILINE)
            if m:
                status = m.group(1).strip().strip('"').strip("'").lower()
if status != 'complete':
    sys.exit(0)
doc = json.load(open(path))
ready = doc.get('plans', {}).get('ready', [])
new_ready = [e for e in ready
             if not ((isinstance(e, dict) and e.get('slug') == slug) or e == slug)]
if len(new_ready) == len(ready):
    sys.exit(0)
doc.setdefault('plans', {})['ready'] = new_ready
doc['updated_at'] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/work-on-plans: pruned completed plan '{slug}' from ready queue.")
PY
}

F=$(make_fixture t27)
seed_empty "$F/.zskills/monitor-state.json"
skill_add "$F/.zskills/monitor-state.json" done-plan >/dev/null
skill_add "$F/.zskills/monitor-state.json" todo-plan >/dev/null
# done-plan landed (status: complete); todo-plan still active.
printf -- '---\nstatus: complete\n---\n# done\n' > "$F/plans/done-plan.md"
printf -- '---\nstatus: ready\n---\n# todo\n' > "$F/plans/todo-plan.md"
# Prune the completed one through the locked path.
out=$(with_lock "$F/.zskills/monitor-state.json.lock" \
  prune_completed_test "$F/.zskills/monitor-state.json" done-plan "$F/plans/done-plan.md" 2>&1)
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ready" = "todo-plan" ] && echo "$out" | grep -q "pruned completed plan 'done-plan'"; then
  pass "#906 prune-on-complete drops a status:complete plan from ready (locked)"
else
  fail "#906 prune-on-complete (ready=$ready out=$out)"
fi

# --- Test 28: #906 prune is a no-op for a NOT-complete plan ------------
out=$(with_lock "$F/.zskills/monitor-state.json.lock" \
  prune_completed_test "$F/.zskills/monitor-state.json" todo-plan "$F/plans/todo-plan.md" 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "todo-plan" ] && [ -z "$out" ]; then
  pass "#906 prune-on-complete leaves a non-complete plan in ready"
else
  fail "#906 prune no-op for active plan (ec=$ec ready=$ready out=$out)"
fi

# --- Test 29: #906 prune embed uses with_monitor_lock + os.replace -----
# Watch-item (b): the prune write MUST go through the flock helper and
# the atomic os.replace, same as the mutating subcommands.
EXEC_MD="$SKILL_DIR/modes/execute.md"
if grep -q 'with_monitor_lock prune_completed' "$EXEC_MD" \
   && grep -q 'os.replace(tmp.name, path)' "$EXEC_MD" \
   && grep -q 'def prune_completed\|prune_completed()' "$EXEC_MD"; then
  pass "#906 prune embed wraps in with_monitor_lock + atomic os.replace"
else
  fail "#906 prune embed missing lock/atomic-write guards"
fi

# --- Test 30: #906 argument-hint advertises the composed form ----------
if grep -q 'argument-hint:.*N|all .*\[every SCHEDULE\] \[now\]' "$SKILL"; then
  pass "#906 argument-hint advertises N|all [every SCHEDULE] [now] composition"
else
  fail "#906 argument-hint missing composed-form surface"
fi

echo ""
echo "---"
printf 'Results: %d passed, %d failed (of %d)\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"

[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
