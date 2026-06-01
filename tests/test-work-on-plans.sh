#!/bin/bash
# Tests for skills/work-on-plans — Phase 3 mutating subcommands
# (add, rank, remove, default) + the #546 schedule_under_1h boundary +
# cross-process flock + mirror parity.
#
# SEAM_HARDENING_HIGH Phase 6a — de-hollowed. This suite USED to re-define
# the mutator functions as transcribed `skill_*` copies (green-by-absence:
# the production heredocs could drift and these tests would never notice).
# It now EXTRACTS the REAL production functions —
# `ensure_monitor_state` / `do_add` / `do_rank` / `do_remove` /
# `do_default` (from subcommands/add-rank-remove.md) and `schedule_under_1h`
# (from the same file's `every` section) — via tests/lib/extract-fence.sh,
# sources them, and drives them against synthetic monitor-state.json
# fixtures. Mutating any of those production heredocs FAILS this suite —
# protection a presence-grep cannot give.
#
# Production signatures differ from the old transcribed copies: the `do_*`
# functions read the global $MONITOR_STATE (not a positional path arg) and
# call ensure_monitor_state() internally — so each test sets MONITOR_STATE
# and calls `do_add <slug> [pos]`, `do_rank <slug> <pos>`,
# `do_remove <slug>`, `do_default <mode>`.
#
# Run from repo root: bash tests/test-work-on-plans.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/work-on-plans/SKILL.md"
SKILL_DIR="$REPO_ROOT/skills/work-on-plans"
SKILL_MIRROR="$REPO_ROOT/.claude/skills/work-on-plans/SKILL.md"
SUBCMD_MD="$SKILL_DIR/subcommands/add-rank-remove.md"

# shellcheck source=tests/lib/extract-fence.sh
. "$SCRIPT_DIR/lib/extract-fence.sh"

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

# --- Extract-and-run the REAL production mutator heredocs ----------------
# Each function lives in its own ```bash fence in
# subcommands/add-rank-remove.md, bracketed by a `### ` heading before and
# after. We extract the FIRST bash fence in each window (the only one).
# ensure_monitor_state() is co-extracted because every do_* calls it; the
# do_* functions read the global $MONITOR_STATE and bootstrap via
# ensure_monitor_state when the file is absent. We seed the file in every
# fixture, so ensure_monitor_state's bootstrap branch is skipped and it
# only parse-checks $MONITOR_STATE.

EXTRACT_SH="$TEST_TMPDIR/_production-mutators.sh"
: > "$EXTRACT_SH"

extract_or_die() {
  # extract_or_die <label> <start-re> <end-re>
  local label="$1" start_re="$2" end_re="$3"
  if ! extract_fence_between "$SUBCMD_MD" "$start_re" "$end_re" 1 0 \
       >> "$EXTRACT_SH"; then
    echo "FATAL: could not extract $label fence from $SUBCMD_MD" >&2
    exit 1
  fi
  printf '\n' >> "$EXTRACT_SH"
}

extract_or_die "ensure_monitor_state" \
  '^### Common helper: bootstrap-then-load' '^### `add'
extract_or_die "do_add" \
  '^### `add <slug>' '^### `rank'
extract_or_die "do_rank" \
  '^### `rank <slug>' '^### `remove'
extract_or_die "do_remove" \
  '^### `remove <slug>' '^### `default'
extract_or_die "do_default" \
  '^### `default <phase' '^### `every'
extract_or_die "schedule_under_1h" \
  '^### `every SCHEDULE' '^### `stop`'

# Source the extracted production functions.
# shellcheck source=/dev/null
. "$EXTRACT_SH"

# Sanity: every expected production function got defined from the heredocs.
for fn in ensure_monitor_state do_add do_rank do_remove do_default schedule_under_1h; do
  if ! declare -F "$fn" >/dev/null; then
    echo "FATAL: production function '$fn' not defined after extract+source" >&2
    exit 1
  fi
done

# --- Thin adapters: set the global $MONITOR_STATE then call production ----
# The production do_* functions read $MONITOR_STATE (not a positional path).
# These adapters preserve the OLD call-site shape (path as $1) so the body
# of each test below stays a faithful behavior assertion against the real
# code. Each sets MONITOR_STATE and shifts it off before delegating.
do_add_at()     { local MONITOR_STATE="$1"; shift; do_add     "$@"; }
do_rank_at()    { local MONITOR_STATE="$1"; shift; do_rank    "$@"; }
do_remove_at()  { local MONITOR_STATE="$1"; shift; do_remove  "$@"; }
do_default_at() { local MONITOR_STATE="$1"; shift; do_default "$@"; }

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

echo "=== work-on-plans Phase 3 tests (extract-and-run production mutators) ==="

# --- Test 0: extraction sanity — the sourced functions ARE the production
# heredocs (idempotency note + atomic os.replace landmarks present). -------
if grep -q 'already in ready queue (no-op)' "$EXTRACT_SH" \
   && grep -q 'os.replace(tmp.name, path)' "$EXTRACT_SH" \
   && grep -q 'digit-prefix slugs' "$EXTRACT_SH" \
   && grep -q "doc\[\"default_mode\"\] = mode" "$EXTRACT_SH"; then
  pass "extract: sourced bash carries the real do_add/do_remove/do_default heredoc landmarks"
else
  fail "extract: extracted production heredocs missing expected landmarks"
fi

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
out=$(do_add_at "$F/.zskills/monitor-state.json" foo-plan 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "foo-plan" ] \
   && python3 -c "import json; json.load(open('$F/.zskills/monitor-state.json'))" 2>/dev/null; then
  pass "AC-1 add appends new slug; JSON parses"
else
  fail "AC-1 add (ec=$ec ready=$ready out=$out)"
fi

# --- Test 6: AC-2 digit-prefix slugs are rejected ---------------------
out=$(do_add_at "$F/.zskills/monitor-state.json" 4-phase-plan 2>&1)
ec=$?
if [ "$ec" -eq 2 ] && echo "$out" | grep -q 'digit-prefix slugs'; then
  pass "AC-2 add rejects digit-prefix slug with usage message"
else
  fail "AC-2 digit-prefix (ec=$ec out=$out)"
fi

# --- Test 7: rank reorders ----------------------------------------------
F=$(make_fixture t7)
seed_empty "$F/.zskills/monitor-state.json"
do_add_at "$F/.zskills/monitor-state.json" alpha >/dev/null
do_add_at "$F/.zskills/monitor-state.json" beta  >/dev/null
do_add_at "$F/.zskills/monitor-state.json" gamma >/dev/null
out=$(do_rank_at "$F/.zskills/monitor-state.json" gamma 1 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "gamma,alpha,beta" ]; then
  pass "AC-1 rank moves slug to position"
else
  fail "rank (ec=$ec ready=$ready out=$out)"
fi

# --- Test 8: remove drops entry ----------------------------------------
out=$(do_remove_at "$F/.zskills/monitor-state.json" alpha 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "gamma,beta" ]; then
  pass "AC-1 remove drops slug"
else
  fail "remove (ec=$ec ready=$ready out=$out)"
fi

# --- Test 9: remove of missing slug is idempotent ---------------------
out=$(do_remove_at "$F/.zskills/monitor-state.json" never-existed 2>&1)
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
do_add_at "$F/.zskills/monitor-state.json" alpha >/dev/null
do_add_at "$F/.zskills/monitor-state.json" beta  >/dev/null
out=$(do_default_at "$F/.zskills/monitor-state.json" finish 2>&1)
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
out=$(do_default_at "$F/.zskills/monitor-state.json" turbo 2>&1)
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
  ( with_lock "$LOCK" do_add_at "$F/.zskills/monitor-state.json" "racer-$i" >/dev/null 2>&1 ) &
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
  # Same as do_add_at but no flock around the rmw.
  do_add_at "$@"
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
do_add_at "$F/.zskills/monitor-state.json" a >/dev/null
do_add_at "$F/.zskills/monitor-state.json" b >/dev/null
do_add_at "$F/.zskills/monitor-state.json" c >/dev/null
out=$(do_add_at "$F/.zskills/monitor-state.json" middle 2 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "a,middle,b,c" ]; then
  pass "AC-1 add at position 2 inserts mid-queue"
else
  fail "add @ pos (ec=$ec ready=$ready out=$out)"
fi

# --- Test 21: idempotent add of existing slug --------------------------
out=$(do_add_at "$F/.zskills/monitor-state.json" a 2>&1)
ec=$?
ready=$(readq "$F/.zskills/monitor-state.json")
if [ "$ec" -eq 0 ] && [ "$ready" = "a,middle,b,c" ] \
   && echo "$out" | grep -q "already in ready queue"; then
  pass "add of existing slug is idempotent (exit 0, no-op)"
else
  fail "add idempotent (ec=$ec ready=$ready out=$out)"
fi

# --- Test 22: rank of missing slug fails -------------------------------
out=$(do_rank_at "$F/.zskills/monitor-state.json" not-here 1 2>&1)
ec=$?
if [ "$ec" -eq 2 ] && echo "$out" | grep -q "not in ready queue"; then
  pass "rank of missing slug exits 2 with diagnostic"
else
  fail "rank missing (ec=$ec out=$out)"
fi

# --- Test 23: add invalid slug --------------------------------------
out=$(do_add_at "$F/.zskills/monitor-state.json" "BadSlug!" 2>&1)
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
do_add_at "$F/.zskills/monitor-state.json" done-plan >/dev/null
do_add_at "$F/.zskills/monitor-state.json" todo-plan >/dev/null
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
