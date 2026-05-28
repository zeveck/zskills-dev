# Execute mode + read-only listing

> **Loaded by the router.** Variables `$MAIN_ROOT`, `$MONITOR_STATE`,
> `$MONITOR_LOCK`, `$WORK_STATE`, `$PLAN_INDEX`, `$SANITIZE`,
> `$READY_TSV`, `$DEFAULT_MODE`, `$WORK_STATE_VALUE`, `$N`,
> `$ALL_MODE`, `$MODE_OVERRIDE`, `$CONTINUE_ON_FAILURE` are set by
> Steps 0-2 in `SKILL.md` before this file is read. All bash fences
> below reference those variables directly.

## Step 3 — Read-only modes (no args, `next`)

### No-args output format

```
Ready queue (<N> plans, default mode: <default>):
  1. <slug-a>       <mode>
  2. <slug-b>       <mode>
  ...
Default mode: <default>     Schedule: <schedule-line>
```

- `<mode>` per row is the entry's `mode` value, or `<default>
  (inherits default)` when absent.
- When `plans.ready` is empty: `Ready queue (0 plans, default mode:
  <default>):` followed by `Default mode: ... Schedule: ...`.
- `<schedule-line>` reflects `$WORK_STATE`: `idle` when state is
  absent/idle, `every <SCHEDULE> (mode=<m>, next fire <ts>)` when
  scheduled and live, `every <SCHEDULE> (mode=<m>, stale)` when
  scheduled but past `parse_schedule + 30min`.

Exit 0 after printing.

### `next` read-only mode

Print the active schedule line. Read `$WORK_STATE` and:

- If absent or `state == "idle"` → print
  `No active /work-on-plans schedule.` and exit 0.
- If `state == "scheduled"` and **stale** (per Shared Schemas:
  `last_fire_at` older than `parse_schedule(schedule) + 30min`) →
  print `Schedule <schedule> (mode=<schedule_mode>) — stale (last
  fire <ago>)` and exit 0. The next regular invocation of `every` or
  `stop` will overwrite this stale entry.
- If `state == "scheduled"` and live → print `Schedule <schedule>
  (mode=<schedule_mode>) — next fire <next_fire_at>` and exit 0.

Implementation reads `$WORK_STATE` once via Python (stdlib only) and
emits the appropriate line:

<!-- allow-hardcoded: 2a.10-AC-non-using-sites reason: Python embed operates on non-ZSKILLS state files; no source+export preamble needed per pragmatic AC interpretation -->
```bash
# No ZSKILLS_* env vars needed: this embed operates on $WORK_STATE
# only (state file in $MAIN_ROOT/.zskills/, not via the path-config helper).
python3 - "$WORK_STATE" <<'PY'
import json, os, sys, datetime, re

path = sys.argv[1]
if not os.path.exists(path):
    print("No active /work-on-plans schedule.")
    sys.exit(0)
try:
    doc = json.load(open(path))
except Exception:
    print("No active /work-on-plans schedule.")
    sys.exit(0)
if doc.get("state") != "scheduled":
    print("No active /work-on-plans schedule.")
    sys.exit(0)

sched = doc.get("schedule", "")
mode = doc.get("schedule_mode", "phase")
last_fire = doc.get("last_fire_at", "")
next_fire = doc.get("next_fire_at", "")

# parse_schedule: "every <interval>" or "every <cron>" → grace seconds.
def parse_schedule_grace(s):
    # Returns (interval_seconds, grace_seconds=interval+30min) or None
    m = re.match(r"^every\s+(\d+)([hm])\b", s.strip(), re.IGNORECASE)
    if not m:
        return None
    n = int(m.group(1))
    unit = m.group(2).lower()
    secs = n * (3600 if unit == "h" else 60)
    return secs + 1800

stale = False
if last_fire:
    try:
        last = datetime.datetime.fromisoformat(last_fire)
        now = datetime.datetime.now(tz=last.tzinfo)
        grace = parse_schedule_grace(sched)
        if grace is not None and (now - last).total_seconds() > grace:
            stale = True
    except Exception:
        pass

if stale:
    print(f"Schedule {sched} (mode={mode}) — stale (last fire {last_fire})")
else:
    print(f"Schedule {sched} (mode={mode}) — next fire {next_fire}")
PY
```

Exit 0. **No tracking marker is written for `next`** (read-only).

## Step 4 — Execute mode setup

For `N`/`all` invocations, build the dispatch list and write the
sprint sentinel.

```bash
# Dispatch list: take the first N ready entries (or all when "all").
mapfile -t READY_LINES < <(printf '%s' "$READY_TSV" \
  | awk -F'\t' '$1!="__DEFAULT__" && $1!="" {print}')
```

### Selection filter (D4) — drop in-flight plan claims

Pipe the just-built `READY_LINES` through `filter-in-flight-plan-claims.sh`
to drop slugs whose claim files indicate an in-flight pipeline. This is
the user-steering anchor — catching the in-flight pipeline at SELECTION
time (not at /run-plan acquire-time) keeps the user's typed
`/work-on-plans` from spinning up redundant dispatches. See
`plans/plans-claim-chip-parity.md` D4 + W2b.1.

```bash
. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
FILTER="$CLAUDE_PROJECT_DIR/.claude/skills/work-on-plans/scripts/filter-in-flight-plan-claims.sh"
if [ -x "$FILTER" ]; then
  FILTERED=$(printf '%s\n' "${READY_LINES[@]}" | bash "$FILTER")
  if [ -n "$FILTERED" ]; then
    mapfile -t READY_LINES <<< "$FILTERED"
  else
    READY_LINES=()
  fi
fi
```

(Defensive `[ -x ]` check so older installations without the script
don't break. Empty filter output rebuilds `READY_LINES` as an empty
array rather than a one-element array with an empty string.)

```bash
TOTAL_READY="${#READY_LINES[@]}"
if [ "$ALL_MODE" = "1" ]; then
  N="$TOTAL_READY"
fi
DISPATCH_COUNT=$(( N < TOTAL_READY ? N : TOTAL_READY ))

if [ "$DISPATCH_COUNT" -eq 0 ]; then
  echo "Ready queue is empty; nothing to dispatch."
  exit 0
fi
```

### Sprint ID + pipeline ID

```bash
SPRINT_ID="sprint-$(date -u +%Y%m%d-%H%M%S)-$(printf '%s' "$$" | tr -cd '0-9' | head -c 8)"
PIPELINE_ID="work-on-plans.$SPRINT_ID"
PIPELINE_ID=$(bash "$SANITIZE" "$PIPELINE_ID")
SPRINT_ID="${PIPELINE_ID#work-on-plans.}"
PIPELINE_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
mkdir -p "$PIPELINE_DIR"
echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"
```

The PID-derived suffix keeps concurrent invocations on the same host
(distinct shell processes) from colliding on the same `SPRINT_ID`.

### Build slug→file resolver (Phase 1 self-implementation)

Phase 1 implements the canonical slug rule inline as a one-line `tr`
applied to `basename(plan, ".md")`. Phase 4 later exposes the same
rule as a shared helper for reuse; Phase 1 must NOT depend on that
helper (it has not landed yet).

```bash
ZSKILLS_PATHS_ROOT="$MAIN_ROOT" \
  source "$MAIN_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
declare -A SLUG_TO_FILE
for f in "$ZSKILLS_PLANS_DIR"/*.md; do
  [ -e "$f" ] || continue
  bn=$(basename "$f" .md)
  [ "$bn" = "PLAN_INDEX" ] && continue
  slug=$(printf '%s' "$bn" | tr '[:upper:]_' '[:lower:]-')
  SLUG_TO_FILE["$slug"]="$f"
done
```

The `tr '[:upper:]_' '[:lower:]-'` matches `/run-plan` exactly
(`skills/run-plan/SKILL.md:405`). **Phase 4** later exposes the same
rule as a shared helper for reuse across skills; Phase 1 must NOT
depend on that helper (it has not landed).

### Resolve each ready slug to a plan file

For each ready entry, look up `SLUG_TO_FILE[$slug]`. On miss, fail
loud (no silent skip):

<!-- allow-hardcoded: ^plans/ reason: illustrative error-message fence (no-lang); the prose mentions plans/ as a generic concept in user-facing output, and the actual resolution uses $ZSKILLS_PLANS_DIR upstream -->
```
/work-on-plans: queued slug '<slug>' has no matching plan file in
plans/. The monitor state file references a plan that no longer
exists. Open the dashboard to remove it from the queue, or edit
.zskills/monitor-state.json directly.
```

Exit 1.

### Initial sprint state

Write `state=sprint` to `$WORK_STATE` before the first dispatch. The
file is rewritten between dispatches (heartbeat) and at the end:

<!-- allow-hardcoded: 2a.10-AC-non-using-sites reason: Python embed operates on non-ZSKILLS state files; no source+export preamble needed per pragmatic AC interpretation -->
```bash
# No ZSKILLS_* env vars needed: this embed operates on $WORK_STATE
# only (state file in $MAIN_ROOT/.zskills/, not via the path-config helper).
python3 - "$WORK_STATE" "$SPRINT_ID" "$DISPATCH_COUNT" <<'PY'
import json, os, sys, socket, tempfile, datetime
path, sprint_id, total = sys.argv[1], sys.argv[2], int(sys.argv[3])
now = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
doc = {
    "state": "sprint",
    "sprint_id": f"work-on-plans.{sprint_id}",
    "session_id": f"{socket.gethostname()}:{os.getpid()}:{now}",
    "started_at": now,
    "progress": {"done": 0, "total": total, "current_slug": ""},
    "updated_at": now,
}
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.work-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
PY
```

## Step 5 — Dispatch loop

For each ready entry in `plans.ready[0:N]`:

1. **Resolve dispatch mode** (precedence, highest first):
   - CLI override (`MODE_OVERRIDE` from arg parse), then
   - per-entry `mode` from the ready entry (if non-empty), then
   - top-level `default_mode`, then
   - `"phase"`.

2. **Write `step.work-on-plans.<sprint-id>.<slug>`** with
   `status: started` BEFORE dispatch:

   ```bash
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   STEP_FILE="$PIPELINE_DIR/step.work-on-plans.$SPRINT_ID.$SLUG"
   printf 'skill: work-on-plans\nparent: work-on-plans.%s\nslug: %s\nmode: %s\nstatus: started\ndate: %s\n' \
     "$SPRINT_ID" "$SLUG" "$DISPATCH_MODE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$STEP_FILE"
   ```

3. **Write `requires.run-plan.<slug>`** in this skill's own subdir
   BEFORE dispatch — this declares the parent's expectation of a
   child `/run-plan` invocation. The `parent:` field tags the marker
   for Phase 4's activity scan:

   ```bash
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   printf 'skill: run-plan\nparent: work-on-plans\nid: %s\nslug: %s\nmode: %s\ndate: %s\n' \
     "$SPRINT_ID" "$SLUG" "$DISPATCH_MODE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$PIPELINE_DIR/requires.run-plan.$SLUG"
   ```

4. **Heartbeat** `$WORK_STATE` (`progress.current_slug = $SLUG`,
   `updated_at = now`).

5. **Invoke `/run-plan` via the Skill tool.** Phase 1 always passes
   `auto`; for `finish` mode also pass `finish`:

   - Phase mode → `Skill: { skill: "run-plan", args: "$ZSKILLS_PLANS_DIR/<FILE>.md auto" }`
   - Finish mode → `Skill: { skill: "run-plan", args: "$ZSKILLS_PLANS_DIR/<FILE>.md auto finish" }`

   Where `$ZSKILLS_PLANS_DIR/<FILE>.md` is `SLUG_TO_FILE[$SLUG]` rendered as a
   path relative to `$MAIN_ROOT`. **Do not pass a landing-mode flag.**
   `/run-plan` resolves its own landing mode (currently `pr` per
   `.claude/zskills-config.json`).

   `/run-plan` itself uses `skills/create-worktree/scripts/create-worktree.sh`
   to create its worktree — `/work-on-plans` does not call that
   script directly.

6. **Detect failure.** `/run-plan` returns a result message; there
   is no exit code from a Skill invocation. Treat the dispatch as a
   FAILURE if **any** of:

   - **(a) Result text matches** any of (case-sensitive grep on the
     response):
     - `Phase \d+ failed`
     - `verification failed`
     - `rebase conflict`
   - **(b) Marker timeout.** The dispatched `/run-plan` wrote a
     `step.run-plan.*.implement` marker (under
     `$MAIN_ROOT/.zskills/tracking/run-plan.<child-slug>/`) but no
     matching `fulfilled.run-plan.*` within a 30-minute timeout.
   - **(c) Skill error.** The Skill invocation itself returned an
     error: text matches `^Error invoking skill\b` OR contains
     `Skill .* not found`. The dispatch never reached `/run-plan`.

   The text-grep arm (a) is fragile to `/run-plan` output changes;
   this is acknowledged debt — when `/run-plan` exposes a
   machine-readable failure indicator, prefer it.

7. **On success:**
   - Update step marker `status: complete` and append `date:`.
   - Write `fulfilled.run-plan.<slug>` in this skill's own subdir:

     ```bash
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
     printf 'skill: run-plan\nparent: work-on-plans\nid: %s\nslug: %s\nstatus: complete\ndate: %s\n' \
       "$SPRINT_ID" "$SLUG" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
       > "$PIPELINE_DIR/fulfilled.run-plan.$SLUG"
     ```

   - Heartbeat `$WORK_STATE` (`progress.done++`, `updated_at = now`).

   - Note: `/run-plan` writes its OWN
     `fulfilled.run-plan.<child-slug>` under
     `$MAIN_ROOT/.zskills/tracking/run-plan.<child-slug>/` via its
     normal logic. `/work-on-plans` does NOT touch that file.

8. **On failure:**
   - **Without `continue`:** stop the loop. Write a one-section
     summary to `$ZSKILLS_AUDIT_DIR/work-on-plans-<sprint-id>.md` listing the
     dispatched plans and the failure reason. Exit non-zero.
   - **With `continue`:** log the failure to stderr and proceed to
     the next entry.

## Step 6 — Sprint completion

After the dispatch loop ends (all done OR failure-with-continue OR
empty-after-failure):

1. Write `fulfilled.work-on-plans.<sprint-id>` (sprint completion
   marker):

   ```bash
   . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   printf 'skill: work-on-plans\nsprint_id: %s\ntotal: %d\ndone: %d\ncontinue: %s\nstatus: %s\ndate: %s\n' \
     "$SPRINT_ID" "$DISPATCH_COUNT" "$DONE" "${CONTINUE_ON_FAILURE:-0}" \
     "$SPRINT_FINAL_STATUS" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
     > "$PIPELINE_DIR/fulfilled.work-on-plans.$SPRINT_ID"
   ```

2. Rewrite `$WORK_STATE` to `{"state":"idle"}` (last-writer-wins):

   <!-- allow-hardcoded: 2a.10-AC-non-using-sites reason: Python embed operates on non-ZSKILLS state files; no source+export preamble needed per pragmatic AC interpretation -->
   ```bash
   # No ZSKILLS_* env vars needed: this embed operates on $WORK_STATE
   # only (state file in $MAIN_ROOT/.zskills/, not via the path-config helper).
   python3 - "$WORK_STATE" <<'PY'
   import json, os, sys, tempfile
   path = sys.argv[1]
   tmp = tempfile.NamedTemporaryFile('w', delete=False,
       dir=os.path.dirname(path), prefix='.work-state.', suffix='.tmp')
   json.dump({"state": "idle"}, tmp); tmp.close()
   os.replace(tmp.name, path)
   PY
   ```

3. Print the completion summary:

   ```
   /work-on-plans sprint <sprint-id>: <done>/<total> plans completed.
   Mode override: <none|phase|finish>     Continue: <0|1>
   Tracking: .zskills/tracking/<pipeline-id>/
   ```

   Exit 0 on full success, non-zero if any plan failed and
   `continue` was not set.

## Sprint report (failure path)

When stopping on first failure without `continue`, write
`$ZSKILLS_AUDIT_DIR/work-on-plans-<sprint-id>.md`:

```markdown
# /work-on-plans sprint — <sprint-id>

**Started:** <iso>
**Mode override:** <none|phase|finish>
**Continue on failure:** no
**Total dispatched:** <N>
**Completed:** <K>
**Failed:** <slug>  (<failure detection arm>)

## Plans
| # | Slug | Mode | Status | Failure |
|---|------|------|--------|---------|
| 1 | foo  | phase | complete | — |
| 2 | bar  | finish | failed | result text matched `Phase 2 failed` |
```

## Tracking marker reference

All markers live under
`$MAIN_ROOT/.zskills/tracking/work-on-plans.<sprint-id>/` (Option B
layout per `docs/tracking/TRACKING_NAMING.md`).

| Marker | When written | Body |
|--------|--------------|------|
| `step.work-on-plans.<sprint-id>.<slug>` | before dispatch (one per plan) | `skill: work-on-plans`, `parent: work-on-plans.<sprint-id>`, `slug:`, `mode:`, `status: started\|complete`, `date:` |
| `requires.run-plan.<slug>` | before dispatch (one per plan) | `skill: run-plan`, `parent: work-on-plans`, `id: <sprint-id>`, `slug:`, `mode:`, `date:` |
| `fulfilled.run-plan.<slug>` | after `/run-plan` returns success | `skill: run-plan`, `parent: work-on-plans`, `id: <sprint-id>`, `slug:`, `status: complete`, `date:` |
| `fulfilled.work-on-plans.<sprint-id>` | sprint completion (success or failure-with-continue) | `skill: work-on-plans`, `sprint_id:`, `total:`, `done:`, `continue:`, `status:`, `date:` |
| `fulfilled.work-on-plans.<sprint-id>` (mutate) | after `add`/`rank`/`remove`/`default`/`every`/`stop` | `skill: work-on-plans`, `sprint_id:`, `subcommand:`, `status: complete`, `date:` |

The `parent:` field is documented in
[docs/tracking/TRACKING_NAMING.md § Parent-tagged markers](../../docs/tracking/TRACKING_NAMING.md#parent-tagged-markers).
Phase 4's activity scan reads it to group dispatched runs under
their orchestrator. The child `/run-plan` writes its own
`fulfilled.run-plan.<child-slug>` under
`run-plan.<child-slug>/` via its existing logic; `/work-on-plans`
does not modify that file.

`/work-on-plans next` is read-only — **no markers are written**.

## Selection-aware plan-claim filter (D4)

`/work-on-plans` participates in the plan-claim mechanism owned by
`/run-plan` (see `plans/plans-claim-chip-parity.md`). Each `/run-plan`
invocation writes `.zskills/claims/plan-<slug>/claim.json` at Phase 1
acquire and releases at Phase 6 land-complete (or earlier via
`/run-plan stop` / Phase 5b §0a no-op). `/work-on-plans` reads those
claim files at Step 4 to skip slugs that are already in-flight.

**Selection filter at Step 4.** Before building the dispatch list,
`filter-in-flight-plan-claims.sh` reads every live
`.zskills/claims/plan-*/claim.json` and drops any `READY_LINES` entry
whose slug appears in the in-flight set. If a claim is known-orphaned
(crashed pipeline), the operator runs
`claim-plan.sh release <slug>` explicitly to clear it.

**Honest scope (DA2.7).** The selection filter closes the
*steady-state* parallel-selection race — when an existing
`/run-plan` pipeline has already acquired the claim and is mid-flight,
a new `/work-on-plans` dispatch will skip that slug. It does NOT
close the *fresh-start* race — two simultaneous `/work-on-plans N`
invocations against an empty claims directory both see no in-flight
slugs and both dispatch. The final atomic defense is
`claim-plan.sh acquire`'s `mkdir`-based race resolution inside
`/run-plan` Phase 1; the loser exits cleanly with the "declined"
message. The two layers compose to give the steady-state convergence
the user described in `plans/plans-claim-chip-parity.md` (User
steering mid-draft, round 1).
