---
name: work-on-plans
disable-model-invocation: true
argument-hint: "(no args = list ready queue) | [N|all] [phase|finish] [continue] | add <slug> [pos] | rank <slug> <pos> | remove <slug> | default <phase|finish> | every SCHEDULE [phase|finish] [--force] | stop | next"
description: >-
  Batch-execute the prioritized ready queue from the dashboard. Reads
  .zskills/monitor-state.json (plans.ready) in order and dispatches
  /run-plan <plan> auto [finish] per entry. Per-plan mode (phase or
  finish) is honored from the queue, with a default-mode fallback.
  Also manages the queue itself (add/rank/remove/default) and recurring
  schedules. Mirrors /fix-issues for bugs.
---

# /work-on-plans — Batch Plan Executor

Dispatches `/run-plan <plan> auto [finish]` per entry in the
prioritized ready queue from the monitor dashboard. Mirrors
`/fix-issues` for bugs but operates on plans instead.

**Ultrathink throughout.** Use careful, thorough reasoning at every
step.

> **Phase note.** This is the Phase 1 implementation: read-only listing
> (`(no args)`, `next`) and execute slots (`N|all [phase|finish]
> [continue]`). The argument-hint advertises the full Phase 3 surface
> (`add`, `rank`, `remove`, `default`, `every`, `stop`) so the
> frontmatter is authoritative across phases; those subcommands print a
> "not yet implemented (Phase 3)" diagnostic and exit 2 until Phase 3
> lands.

## Top-level invariant

`/work-on-plans` runs at the parent session and dispatches `/run-plan`
via the **Skill tool**. Per CLAUDE.md memory
`project_subagent_architecture`, Claude Code subagents cannot dispatch
subagents — Skill is a top-level-only primitive. Before any work,
verify you have access to the Agent tool (a top-level marker):

- If `Agent` (or `Task`) is **not** in your tool list, you are running
  as a subagent. Print:

  > `/work-on-plans` must run at top-level to dispatch /run-plan

  and **exit 2.** This is the same defense `/fix-issues` uses.

## Arguments

```
/work-on-plans                       # list ready queue (read-only)
/work-on-plans next                  # print active schedule (read-only)
/work-on-plans N [phase|finish] [continue]
/work-on-plans all [phase|finish] [continue]
```

**Parsing rules (Phase 1 surface).** Treat `$ARGUMENTS` as
whitespace-separated tokens. Trim and lowercase each.

1. **Empty `$ARGUMENTS` → no-args read-only mode.** Print the ready
   queue listing (see "No-args output format") and exit 0.

2. **First token is `next` → next read-only mode.** Print the active
   schedule line and exit 0.

3. **First token is `stop` (Phase 3) → not yet implemented.** Print
   `/work-on-plans stop is implemented in Phase 3 (not yet landed).`
   and exit 2.

4. **First token matches `^[0-9]+$` → execute mode (N).** Set `N` to
   that integer.

5. **First token is `all` → execute mode (all).** Set `N` to the count
   of `plans.ready` after sync (resolved at dispatch time).

6. **First token is one of `add`, `rank`, `remove`, `default`,
   `every`** → not-yet-implemented diagnostic:

   > /work-on-plans <subcommand> is implemented in Phase 3 (not yet landed).

   Exit 2.

7. **First token is anything else → usage error.** Print:

   > Usage: /work-on-plans (no args) | next | N [phase|finish] [continue] | all [phase|finish] [continue]

   Exit 2.

In execute mode, the remaining tokens are recognised by name (order
insensitive, no positional meaning):

- `phase` → `MODE_OVERRIDE=phase` (mutex with `finish`)
- `finish` → `MODE_OVERRIDE=finish` (mutex with `phase`)
- `continue` → `CONTINUE_ON_FAILURE=1`
- anything else → usage error (same message as above)

If both `phase` and `finish` appear, error:

> Usage: /work-on-plans … : `phase` and `finish` are mutually exclusive.

Order-insensitive: `N finish continue` ≡ `N continue finish`.

**The mode override is per-batch only.** It does NOT mutate the saved
`mode` on individual ready-queue entries or the top-level
`default_mode` in `monitor-state.json`.

## Step 0 — Setup

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
SANITIZE="$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
[ ! -x "$SANITIZE" ] && SANITIZE="$MAIN_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
mkdir -p "$MAIN_ROOT/.zskills/tracking" "$MAIN_ROOT/.zskills" "$MAIN_ROOT/reports"
MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"
WORK_STATE="$MAIN_ROOT/.zskills/work-on-plans-state.json"
PLAN_INDEX="$MAIN_ROOT/plans/PLAN_INDEX.md"
```

The sanitizer fallback path covers source-tree development. In normal
installed use the `.claude/skills/...` path is canonical.

## Step 1 — sync (read monitor-state.json)

Read `$MONITOR_STATE` and extract `plans.ready`. The schema is
documented in `plans/ZSKILLS_MONITOR_PLAN.md` § "Shared Schemas".

### Missing-file behaviour (auto-create on first read)

If `$MONITOR_STATE` does not exist, **bootstrap** it:

1. **Pick the seed source** by precedence:
   - **(1)** if `$PLAN_INDEX` exists AND `[ -r "$PLAN_INDEX" ]`,
     parse it for the drafted/reviewed classification.
   - **(2)** else, scan `plans/*.md` frontmatter and apply the
     default-column inference table from
     `plans/ZSKILLS_MONITOR_PLAN.md` § "Default column inference".

   If `$PLAN_INDEX` exists but is **unreadable** (e.g., `chmod 000`)
   or fails to parse, fall back to the frontmatter scan and warn to
   stderr — do NOT fail. Example warning:

   > /work-on-plans: PLAN_INDEX.md unreadable, falling back to frontmatter scan.

2. **Build the JSON.** `ready` always starts empty. `drafted` and
   `reviewed` are seeded from the chosen source. Use Python (stdlib
   only) to emit the file:

   ```bash
   python3 - "$MONITOR_STATE" "$MAIN_ROOT" <<'PY'
   import json, os, sys, pathlib, re, tempfile
   out_path = sys.argv[1]
   main_root = pathlib.Path(sys.argv[2])
   plans_dir = main_root / "plans"
   index = plans_dir / "PLAN_INDEX.md"

   drafted, reviewed = [], []
   def emit_warn(msg):
       print(msg, file=sys.stderr)

   def from_index(text):
       d, r = [], []
       section = None
       row_re = re.compile(r'^\|\s*\[([^\]]+\.md)\]')
       for line in text.splitlines():
           if line.startswith('## '):
               h = line[3:].strip().lower()
               if 'ready' in h: section = 'ready'
               elif 'in progress' in h: section = 'inprog'
               elif 'complete' in h: section = 'complete'
               elif 'canar' in h or 'reference' in h: section = None
               else: section = None
               continue
           if section in ('ready', 'inprog'):
               m = row_re.match(line)
               if m:
                   slug = m.group(1)[:-3].lower().replace('_', '-')
                   (d if section == 'ready' else r).append(slug)
       return d, r

   def from_scan():
       d, r = [], []
       for p in sorted(plans_dir.glob('*.md')):
           if p.name == 'PLAN_INDEX.md':
               continue
           slug = p.stem.lower().replace('_', '-')
           text = ''
           try:
               text = p.read_text(encoding='utf-8', errors='replace')
           except Exception:
               continue
           # Frontmatter status: extract
           status = ''
           if text.startswith('---'):
               end = text.find('\n---', 3)
               if end >= 0:
                   fm = text[3:end]
                   m = re.search(r'^status:\s*([^\n]+)', fm, re.MULTILINE)
                   if m:
                       status = m.group(1).strip().strip('"').strip("'").lower()
           # Inference per Shared Schemas table
           if status in ('complete', 'landed'):
               continue  # hidden
           if status == 'conflict':
               r.append(slug)
           else:
               d.append(slug)
       return d, r

   used_index = False
   if index.exists() and os.access(index, os.R_OK):
       try:
           drafted, reviewed = from_index(index.read_text(encoding='utf-8'))
           used_index = True
       except Exception as e:
           emit_warn(f'/work-on-plans: PLAN_INDEX.md parse failed ({e}), '
                     'falling back to frontmatter scan.')
   if not used_index:
       if index.exists() and not os.access(index, os.R_OK):
           emit_warn('/work-on-plans: PLAN_INDEX.md unreadable, '
                     'falling back to frontmatter scan.')
       drafted, reviewed = from_scan()

   doc = {
       "version": "1.1",
       "default_mode": "phase",
       "plans": {
           "drafted":  [{"slug": s} for s in drafted],
           "reviewed": [{"slug": s} for s in reviewed],
           "ready":    [],
       },
       "issues": {"triage": [], "ready": []},
       "updated_at": "",
   }
   tmp = tempfile.NamedTemporaryFile('w', delete=False,
       dir=os.path.dirname(out_path), prefix='.monitor-state.', suffix='.tmp')
   try:
       json.dump(doc, tmp, indent=2)
       tmp.write('\n')
       tmp.close()
       os.replace(tmp.name, out_path)
   except Exception:
       os.unlink(tmp.name)
       raise
   PY
   ```

3. **Continue.** Read-only invocations (`(no args)`, `next`) print the
   resulting (empty) ready queue and exit 0. Execute invocations
   (`N`/`all`) proceed with `plans.ready = []` — there is nothing to
   dispatch, so they print the empty-queue listing and exit 0.

### Unparseable monitor-state.json

If `$MONITOR_STATE` exists but does not parse as JSON, halt:

```bash
python3 -c '
import json, sys
try: json.load(open(sys.argv[1]))
except Exception as e: print(f"unparseable: {e}", file=sys.stderr); sys.exit(1)
' "$MONITOR_STATE" || {
  echo "/work-on-plans: $MONITOR_STATE is not valid JSON. Fix or delete the file and retry." >&2
  exit 1
}
```

Per Shared Schemas the readers are defensive against transient
corruption; here Phase 1 chooses the conservative halt — there is no
recoverable interpretation when `monitor-state.json` is the canonical
source of the queue.

### Extracting plans.ready

Read the JSON and emit `slug<TAB>mode` lines on stdout (one per ready
entry, in order). `mode` is `phase`, `finish`, or empty (inherits
default):

```bash
READY_TSV=$(python3 - "$MONITOR_STATE" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
default = doc.get('default_mode', 'phase')
for entry in doc.get('plans', {}).get('ready', []):
    if isinstance(entry, str):       # version 1.0 forward-compat
        slug, mode = entry, ''
    else:
        slug = entry.get('slug', '')
        mode = entry.get('mode', '')
    if not slug:
        continue
    print(f'{slug}\t{mode}')
print(f'__DEFAULT__\t{default}', end='')
PY
)
DEFAULT_MODE=$(printf '%s' "$READY_TSV" | awk -F'\t' '$1=="__DEFAULT__" {print $2}')
[ -z "$DEFAULT_MODE" ] && DEFAULT_MODE=phase
```

The `__DEFAULT__` sentinel separates the queue rows from the default
mode without two reads.

## Step 2 — Read work-on-plans-state.json (state lifecycle)

Read `$WORK_STATE` defensively. If missing, treat as `{"state":"idle"}`.
If present but unparseable as JSON, **rewrite** it to
`{"state":"idle"}` with a stderr warning and proceed — never block
dispatch on a corrupt state file:

```bash
WORK_STATE_VALUE=$(python3 - "$WORK_STATE" <<'PY'
import json, os, sys, tempfile
path = sys.argv[1]
if not os.path.exists(path):
    print('idle')
    sys.exit(0)
try:
    doc = json.load(open(path))
except Exception as e:
    print(f'/work-on-plans: {path} unparseable JSON ({e}); '
          'resetting to idle.', file=sys.stderr)
    doc = {'state': 'idle'}
    tmp = tempfile.NamedTemporaryFile('w', delete=False,
        dir=os.path.dirname(path), prefix='.work-state.', suffix='.tmp')
    json.dump(doc, tmp); tmp.close()
    os.replace(tmp.name, path)
print(doc.get('state', 'idle'))
PY
)
```

### Stale-sprint reset

If `state == "sprint"` and `updated_at` is older than 30 minutes,
reset to `{"state":"idle"}` without prompting. Implemented in the
read helper above by extending the check (omitted from the snippet
for brevity but applied at dispatch time before sprint state is
written).

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
- `<schedule-line>` is `idle` in Phase 1 (no `every` registration
  exists yet — Phase 3 fills in `every <SCHEDULE> (next fire <ts>)`
  and `stale (last fire <age>)`).

Exit 0 after printing.

### `next` read-only mode

Print the active schedule line. Phase 1 always prints:

> No active /work-on-plans schedule (every-mode lands in Phase 3).

Exit 0. **No tracking marker is written for `next`** (read-only).

## Step 4 — Execute mode setup

For `N`/`all` invocations, build the dispatch list and write the
sprint sentinel.

```bash
# Dispatch list: take the first N ready entries (or all when "all").
mapfile -t READY_LINES < <(printf '%s' "$READY_TSV" \
  | awk -F'\t' '$1!="__DEFAULT__" && $1!="" {print}')
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
declare -A SLUG_TO_FILE
for f in "$MAIN_ROOT"/plans/*.md; do
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

```bash
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
   STEP_FILE="$PIPELINE_DIR/step.work-on-plans.$SPRINT_ID.$SLUG"
   printf 'skill: work-on-plans\nparent: work-on-plans.%s\nslug: %s\nmode: %s\nstatus: started\ndate: %s\n' \
     "$SPRINT_ID" "$SLUG" "$DISPATCH_MODE" "$(TZ=America/New_York date -Iseconds)" \
     > "$STEP_FILE"
   ```

3. **Write `requires.run-plan.<slug>`** in this skill's own subdir
   BEFORE dispatch — this declares the parent's expectation of a
   child `/run-plan` invocation. The `parent:` field tags the marker
   for Phase 4's activity scan:

   ```bash
   printf 'skill: run-plan\nparent: work-on-plans\nid: %s\nslug: %s\nmode: %s\ndate: %s\n' \
     "$SPRINT_ID" "$SLUG" "$DISPATCH_MODE" "$(TZ=America/New_York date -Iseconds)" \
     > "$PIPELINE_DIR/requires.run-plan.$SLUG"
   ```

4. **Heartbeat** `$WORK_STATE` (`progress.current_slug = $SLUG`,
   `updated_at = now`).

5. **Invoke `/run-plan` via the Skill tool.** Phase 1 always passes
   `auto`; for `finish` mode also pass `finish`:

   - Phase mode → `Skill: { skill: "run-plan", args: "plans/<FILE>.md auto" }`
   - Finish mode → `Skill: { skill: "run-plan", args: "plans/<FILE>.md auto finish" }`

   Where `plans/<FILE>.md` is `SLUG_TO_FILE[$SLUG]` rendered as a
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
     printf 'skill: run-plan\nparent: work-on-plans\nid: %s\nslug: %s\nstatus: complete\ndate: %s\n' \
       "$SPRINT_ID" "$SLUG" "$(TZ=America/New_York date -Iseconds)" \
       > "$PIPELINE_DIR/fulfilled.run-plan.$SLUG"
     ```

   - Heartbeat `$WORK_STATE` (`progress.done++`, `updated_at = now`).

   - Note: `/run-plan` writes its OWN
     `fulfilled.run-plan.<child-slug>` under
     `$MAIN_ROOT/.zskills/tracking/run-plan.<child-slug>/` via its
     normal logic. `/work-on-plans` does NOT touch that file.

8. **On failure:**
   - **Without `continue`:** stop the loop. Write a one-section
     summary to `reports/work-on-plans-<sprint-id>.md` listing the
     dispatched plans and the failure reason. Exit non-zero.
   - **With `continue`:** log the failure to stderr and proceed to
     the next entry.

## Step 6 — Sprint completion

After the dispatch loop ends (all done OR failure-with-continue OR
empty-after-failure):

1. Write `fulfilled.work-on-plans.<sprint-id>` (sprint completion
   marker):

   ```bash
   printf 'skill: work-on-plans\nsprint_id: %s\ntotal: %d\ndone: %d\ncontinue: %s\nstatus: %s\ndate: %s\n' \
     "$SPRINT_ID" "$DISPATCH_COUNT" "$DONE" "${CONTINUE_ON_FAILURE:-0}" \
     "$SPRINT_FINAL_STATUS" "$(TZ=America/New_York date -Iseconds)" \
     > "$PIPELINE_DIR/fulfilled.work-on-plans.$SPRINT_ID"
   ```

2. Rewrite `$WORK_STATE` to `{"state":"idle"}` (last-writer-wins):

   ```bash
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
`reports/work-on-plans-<sprint-id>.md`:

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

The `parent:` field is documented in
[docs/tracking/TRACKING_NAMING.md § Parent-tagged markers](../../docs/tracking/TRACKING_NAMING.md#parent-tagged-markers).
Phase 4's activity scan reads it to group dispatched runs under
their orchestrator. The child `/run-plan` writes its own
`fulfilled.run-plan.<child-slug>` under
`run-plan.<child-slug>/` via its existing logic; `/work-on-plans`
does not modify that file.

`/work-on-plans next` is read-only — **no markers are written**.

## Key Rules

- **Top-level only.** Subagents have no Agent tool; `/work-on-plans`
  refuses to run from a subagent context. Same defense as
  `/fix-issues`.
- **Skill tool dispatch.** `/run-plan` is invoked as
  `Skill: { skill: "run-plan", args: "plans/<FILE>.md auto [finish]" }`.
  Never the Agent tool — the chain would lose the Agent tool one
  level deeper and `/run-plan`'s internal dispatches would fail.
- **CLI mode override is per-batch.** It does not mutate saved
  `mode` on individual entries or `default_mode` in
  `monitor-state.json`. Phase 3's `default <phase|finish>`
  subcommand is the only path that mutates `default_mode`.
- **Fail loud on unknown slug.** Never silently skip a queued slug
  whose plan file is missing — the user needs to remove it from the
  queue.
- **Stdlib JSON only.** Use Python (stdlib) for JSON read/write and
  bash regex (`BASH_REMATCH`) for inline matching. Per zskills
  convention, no third-party JSON CLI is invoked from skill bodies.
- **Self-implement the slug rule.** Phase 1 must use the inline
  one-line `tr '[:upper:]_' '[:lower:]-'`; the shared helper from
  Phase 4 has not landed yet at the time this skill ships.
- **No landing-mode flag passed to `/run-plan`.** It resolves its
  own from arg/config (currently `pr`).
- **Heartbeat `work-on-plans-state.json`** between every dispatch
  so 30-minute staleness detection works for long-running plans.
- **Corrupt `work-on-plans-state.json` is recoverable.** Reset to
  `{"state":"idle"}` with a stderr warning and proceed — never
  block dispatch.
- **Unparseable `monitor-state.json` halts.** It is the canonical
  source of the queue; no recoverable interpretation exists. Print
  a diagnostic and exit 1.
- **Mirror after editing.** Edit `skills/work-on-plans/` source,
  then `bash scripts/mirror-skill.sh work-on-plans`. Never edit
  `.claude/skills/work-on-plans/` directly.
