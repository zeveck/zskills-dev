# Mutating subcommands (`add`, `rank`, `remove`, `default`, `every`, `stop`)

> **Loaded by the router.** Variables `$MAIN_ROOT`, `$MONITOR_STATE`,
> `$MONITOR_LOCK`, `$WORK_STATE`, `$PLAN_INDEX`, `$SANITIZE`,
> `$READY_TSV`, `$DEFAULT_MODE`, `$WORK_STATE_VALUE` are set by
> Steps 0-2 in `SKILL.md` before this file is read. The
> `ensure_lockfile` / `with_monitor_lock` helpers from Step 0 are
> also available. All bash fences below reference those variables
> directly.

## Step 7 — Mutating subcommands (`add`, `rank`, `remove`, `default`, `every`, `stop`)

The mutating subcommands route from rule 6 (parsing). Each one

- bootstraps `$MONITOR_STATE` if missing (using the same Python
  helper from Step 1 — read-only modes already exercise that
  helper, so the bootstrap path is shared);
- acquires `$MONITOR_LOCK` via `with_monitor_lock` for the entire
  read-modify-write window;
- writes a `fulfilled.work-on-plans.<sprint-id>` marker (per
  Tracking marker reference). `next` does NOT (read-only). Each
  sprint-id for these subcommands is `mutate-<utc>-<pid8>`:

  ```bash
  SPRINT_ID="mutate-$(date -u +%Y%m%d-%H%M%S)-$(printf '%s' "$$" | tr -cd '0-9' | head -c 8)"
  PIPELINE_ID="work-on-plans.$SPRINT_ID"
  PIPELINE_ID=$(bash "$SANITIZE" "$PIPELINE_ID")
  SPRINT_ID="${PIPELINE_ID#work-on-plans.}"
  PIPELINE_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
  mkdir -p "$PIPELINE_DIR"
  echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"
  ```

The mutation Python helpers below run inside `with_monitor_lock`
under fd 9 already held; calling Python with the JSON path is safe.

### Common helper: bootstrap-then-load

If `$MONITOR_STATE` is missing, run the Step 1 bootstrap helper to
auto-create the file (`ready=[]`, `default_mode="finish"` post-#988).
Then load the JSON. If present but unparseable, halt with the same
diagnostic as Step 1.

```bash
ensure_monitor_state() {
  if [ ! -f "$MONITOR_STATE" ]; then
    # Re-run the Step 1 bootstrap helper. Same shape, same path.
    if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
      export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
      . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
    else
      source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
    fi
    export ZSKILLS_PLANS_DIR ZSKILLS_ISSUES_DIR ZSKILLS_AUDIT_DIR
    python3 - "$MONITOR_STATE" "$MAIN_ROOT" <<'PY'
# plans_dir resolved via zskills-paths.sh in the wrapping bash fence — see Phase 2a.10 of ZSKILLS_PATH_CONFIG plan.
import json, os, sys, pathlib, re, tempfile
out_path = sys.argv[1]
main_root = pathlib.Path(sys.argv[2])
plans_dir_env = os.environ.get("ZSKILLS_PLANS_DIR")
audit_dir_env = os.environ.get("ZSKILLS_AUDIT_DIR")
if not plans_dir_env or not audit_dir_env:
    print("FATAL: ZSKILLS_PLANS_DIR / ZSKILLS_AUDIT_DIR not exported by wrapping bash fence", file=sys.stderr)
    sys.exit(1)
plans_dir = pathlib.Path(plans_dir_env)
index = pathlib.Path(audit_dir_env) / "PLAN_INDEX.md"

drafted, reviewed = [], []

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
        status = ''
        if text.startswith('---'):
            end = text.find('\n---', 3)
            if end >= 0:
                fm = text[3:end]
                m = re.search(r'^status:\s*([^\n]+)', fm, re.MULTILINE)
                if m:
                    status = m.group(1).strip().strip('"').strip("'").lower()
        if status in ('complete', 'landed'):
            continue
        if status == 'conflict':
            r.append(slug)
        else:
            d.append(slug)
    return d, r

if index.exists() and os.access(index, os.R_OK):
    try:
        drafted, reviewed = from_index(index.read_text(encoding='utf-8'))
    except Exception:
        drafted, reviewed = from_scan()
else:
    drafted, reviewed = from_scan()

doc = {
    "version": "1.1",
    # Post-#988 default for new state files (chip removed; bare
    # /work-on-plans N resolves to `finish` per dispatch).
    "default_mode": "finish",
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
    json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
    os.replace(tmp.name, out_path)
except Exception:
    os.unlink(tmp.name); raise
PY
  fi
  # Halt if the file is now present but unparseable.
  python3 -c '
import json, sys
try: json.load(open(sys.argv[1]))
except Exception as e: print(f"unparseable: {e}", file=sys.stderr); sys.exit(1)
' "$MONITOR_STATE" || {
    echo "/work-on-plans: $MONITOR_STATE is not valid JSON. Fix or delete the file and retry." >&2
    exit 1
  }
}
```

### `add <slug> [pos]`

Append (or insert at 1-based `pos`) a `{"slug": <slug>, "mode": ""}`
entry into `plans.ready`. Validation:

- `<slug>` must match `^[a-z0-9][a-z0-9-]*$` (slugs are pre-lowercased
  per Shared Schemas; uppercase / `_` should be normalised by the
  caller via the canonical slug rule, then re-passed).
- **Reject digit-prefix slugs.** `^[0-9]` is reserved for execute-mode
  `N`. Print:

  > /work-on-plans: digit-prefix slugs (`<slug>`) are reserved for execute-mode N.
  > Use the dashboard or edit `.zskills/monitor-state.json` directly to add such a plan.

  Exit 2.

- If `<slug>` is already present in `plans.ready` (case-sensitive
  match), exit 0 idempotently with a stderr note (no marker write
  for the no-op? still write the marker — the user invoked the
  subcommand). The marker is written either way; the JSON file is
  not rewritten if already present.

```bash
do_add() {
  local slug="$1" pos="${2:-}"
  # Reject digit-prefix BEFORE the general slug regex, because slot 1
  # matching ^[0-9]+$ already routes to execute-mode N (rule 4). A
  # mixed-form like '4-phase-plan' starts with a digit, so it hits the
  # general regex but must still be refused here.
  if [[ "$slug" =~ ^[0-9] ]]; then
    printf '/work-on-plans: digit-prefix slugs (%q) are reserved for execute-mode N.\n' "$slug" >&2
    printf 'Use the dashboard or edit .zskills/monitor-state.json directly to add such a plan.\n' >&2
    return 2
  fi
  if [[ ! "$slug" =~ ^[a-z][a-z0-9-]*$ ]]; then
    printf '/work-on-plans: invalid slug %q (must match ^[a-z][a-z0-9-]*$).\n' "$slug" >&2
    return 2
  fi
  ensure_monitor_state
  python3 - "$MONITOR_STATE" "$slug" "${pos:-}" <<'PY'
import json, os, sys, tempfile, datetime
path, slug, pos_s = sys.argv[1], sys.argv[2], sys.argv[3]
doc = json.load(open(path))
plans = doc.setdefault("plans", {})
ready = plans.setdefault("ready", [])
# Idempotent: skip if already present.
if any((isinstance(e, dict) and e.get("slug") == slug) or e == slug for e in ready):
    print(f"/work-on-plans: '{slug}' already in ready queue (no-op).", file=sys.stderr)
    sys.exit(0)
entry = {"slug": slug, "mode": ""}
if pos_s:
    try:
        pos = int(pos_s)
    except ValueError:
        print(f"/work-on-plans: invalid pos '{pos_s}'.", file=sys.stderr)
        sys.exit(2)
    if pos < 1: pos = 1
    if pos > len(ready) + 1: pos = len(ready) + 1
    ready.insert(pos - 1, entry)
else:
    ready.append(entry)
doc["plans"]["ready"] = ready
doc["updated_at"] = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
tmp = tempfile.NamedTemporaryFile('w', delete=False,
    dir=os.path.dirname(path), prefix='.monitor-state.', suffix='.tmp')
json.dump(doc, tmp, indent=2); tmp.write('\n'); tmp.close()
os.replace(tmp.name, path)
print(f"/work-on-plans: added '{slug}' to ready queue.")
PY
}
```

### `rank <slug> <pos>`

Move an existing `ready` entry to 1-based position `pos`. If `<slug>`
is not present → exit 2 with a message. If `pos < 1` → 1; if `pos >
len(ready)` → end.

```bash
do_rank() {
  local slug="$1" pos_s="${2:-}"
  if [[ -z "$pos_s" || ! "$pos_s" =~ ^[0-9]+$ ]]; then
    printf '/work-on-plans: rank requires a positive integer position.\n' >&2
    return 2
  fi
  ensure_monitor_state
  python3 - "$MONITOR_STATE" "$slug" "$pos_s" <<'PY'
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
```

### `remove <slug>`

Drop the matching entry from `plans.ready`. Missing slug → idempotent
(stderr note, exit 0).

```bash
do_remove() {
  local slug="$1"
  ensure_monitor_state
  python3 - "$MONITOR_STATE" "$slug" <<'PY'
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
```

### `default <phase|finish>`

Set the top-level `default_mode`. Per-entry `mode` values are NOT
touched (in-flight sprints capture mode at start; this only changes
the inheritance default for newly added entries).

> **Note (#988):** the chip that exposed this subcommand visually was
> removed from the dashboard, and the dispatcher's bash floor now falls
> back to `"finish"` when `default_mode` is unset. The subcommand is
> retained as a back-compat path — it still writes the field, and the
> Step 1 read still honors a non-default value — but it is effectively
> a no-op for fresh installs. The whole `default <phase|finish>`
> machinery is a candidate for removal in a follow-up.

```bash
do_default() {
  local mode="$1"
  if [[ "$mode" != "phase" && "$mode" != "finish" ]]; then
    printf '/work-on-plans: default takes phase or finish (got %q).\n' "$mode" >&2
    return 2
  fi
  ensure_monitor_state
  python3 - "$MONITOR_STATE" "$mode" <<'PY'
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
```

### `every SCHEDULE [phase|finish] [--force]`

Register an in-session recurring cron via `CronCreate`. The cron
fires on schedule and re-runs `/work-on-plans <count> <schedule_mode>
every <SCHEDULE> now` (self-perpetuating: the cron itself dies with
the session).

**Count capture (issue #906 — parity with `/fix-issues`).** `every`
is reached two ways:

- **Composed with a leading `N`/`all`** on the dispatch path (router
  Step 3 composed-form routing): `$N` (or `ALL_MODE=1`) is already
  set. Capture it as the **`schedule_count`** — the cron prompt
  carries that count so each fire drains exactly `N` plans (or `all`
  when `ALL_MODE=1`), NOT unconditional `all`.
- **Bare `every SCHEDULE`** (no leading count, first-token
  subcommand): `schedule_count` is the literal `all` — drain the
  whole ready queue per fire, the pre-#906 behavior.

`COUNT_TOKEN` below is `$N` when an integer count was given, else
`all`. It is both persisted (`schedule_count` in `$WORK_STATE`) and
baked into the cron prompt.

**Mode capture.** At registration, resolve the captured `schedule_mode`
once and persist it: CLI flag (`phase` or `finish` token after
SCHEDULE) > current `default_mode` from `$MONITOR_STATE` > `"finish"`
(post-#988 default for unconfigured installs).
**Each fire uses the captured `schedule_mode`, NOT live
`default_mode`.** To change mode, `stop` and re-register.

**`schedule_mode = finish`** does NOT call `/run-plan finish` once
across all plans. It dispatches `/run-plan $ZSKILLS_PLANS_DIR/<file>.md auto
finish` per ready plan (one PR per plan); the cron then waits for
the next fire.

**Reject SCHEDULE < 1h when `schedule_mode=finish`.** Phase mode
has no minimum interval (cron risk is intrinsic to finish mode). The
LLM parses SCHEDULE — the only mechanical guard is the bash regex
below that detects sub-hour intervals (`m`-suffixed numbers,
`*/N * * * *` cron exprs with N < 60):

```bash
schedule_under_1h() {
  # Returns 0 (true) iff $1 looks like a sub-hour interval.
  local s="$1"
  # forms: "30m", "5m", "every 30m" (N<60 only — "60m"/"120m" are ≥1h)
  [[ "$s" =~ (^|[[:space:]])([0-9]+)m([[:space:]]|$) ]] && {
    local n="${BASH_REMATCH[2]}"
    [ "$n" -lt 60 ] && return 0
  }
  # forms: "*/30 * * * *", "*/5 * * * *"
  [[ "$s" =~ ^\*/([0-9]+)[[:space:]] ]] && {
    local n="${BASH_REMATCH[1]}"
    [ "$n" -lt 60 ] && return 0
  }
  return 1
}
```

If `schedule_mode=finish` AND `schedule_under_1h "$SCHEDULE"` returns
0, refuse:

> /work-on-plans: When using finish mode, SCHEDULE must be ≥1h to
> avoid nested cron collision with /run-plan's phase-chaining
> crons. Use phase mode for shorter intervals.

Exit 2.

**Schedule ownership.** Read `$WORK_STATE` before registering. The
**current `session_id`** is computed once: `<host>:<pid>:<now>`. If
`$WORK_STATE` contains `state == "scheduled"` AND `session_id !=
current_session_id`:

- If the existing entry is **stale** (per Shared Schemas), silently
  overwrite.
- Else, refuse without `--force`:

  > /work-on-plans: already scheduled by session <other> — pass `--force` to take over.

  Exit 2.

If `state == "scheduled"` AND `session_id == current_session_id`:
treat as idempotent take-over — `CronDelete` the existing
`/work-on-plans` cron (matched by `prompt` starting with
`Run /work-on-plans ` — the prompt now carries a count/`all` token
between the skill name and `every`, so match the broad prefix, the
same prefix `stop` uses), then proceed with the new registration.
`--force` is NOT required in the same-session case.

**`CronCreate` failure.** Exit 1 with:

> /work-on-plans: Failed to register schedule: <error>. The plan will
> not run automatically. You can run `/work-on-plans N phase`
> manually instead.

Do NOT write `$WORK_STATE` on `CronCreate` failure.

**On success**, write `$WORK_STATE`:

```json
{
  "state": "scheduled",
  "sprint_id": "work-on-plans.<sprint-id>",
  "session_id": "<host>:<pid>:<invocation_start_time>",
  "schedule": "every <SCHEDULE>",
  "schedule_mode": "phase|finish",
  "schedule_count": "<COUNT_TOKEN>",
  "session_started_at": "<iso>",
  "last_fire_at": "<iso == session_started_at>",
  "next_fire_at": "<iso>",
  "updated_at": "<iso>"
}
```

`last_fire_at = session_started_at` so staleness computes from the
schedule's birth, not epoch (Shared Schemas). `schedule_count` is the
captured count (`$N` or `all`) so the schedule's identity survives a
session-end-then-`next` query.

The `every` skill body uses the **`CronCreate`/`CronDelete`/`CronList`
tools** (not bash). The cron prompt is reconstructed with the captured
count and mode, and **always includes `now`** so each fire runs
immediately and re-registers itself (self-perpetuating — mirrors
`/fix-issues`'s `sprint.md:53` `CRON_PROMPT`):

```
Run /work-on-plans <COUNT_TOKEN> <schedule_mode> every <SCHEDULE> now
```

Examples:
- `/work-on-plans 1 every 1h finish now` →
  `Run /work-on-plans 1 finish every 1h now` (one plan per hour).
- `/work-on-plans all every 4h phase now` →
  `Run /work-on-plans all phase every 4h now`.
- bare `/work-on-plans every 2h` →
  `Run /work-on-plans all finish every 2h now` (mode resolves to the
  current `default_mode` if any historical value is on disk, otherwise
  `"finish"` post-#988; note finish-mode requires SCHEDULE ≥ 1h, so a
  bare sub-hour `every` falls back to `phase` only when a chip-set
  `default_mode=phase` is on disk).

(Captured count + mode win, regardless of `default_mode` /
queue size at fire time. The `now` in the cron prompt is for the
CRON's own re-invocation; whether THIS invocation runs immediately is
controlled by the user's own `now` flag per the router's composed-form
routing.)

For schedule expression conversion (interval → cron) and `CronCreate`
mechanics, mirror the `/fix-issues` Phase 0 implementation
(`skills/fix-issues/SKILL.md` "Phase 0 — Schedule (if `every` is
present)").

### `stop`

Cancel the active `/work-on-plans` cron and reset state.

1. `CronList` → find any cron whose `prompt` starts with `Run
   /work-on-plans `.
2. `CronDelete` each. Capture the cron IDs and SCHEDULE for the
   completion message.
3. Acquire `with_monitor_lock` (in case the in-progress server is
   holding the lock for a queue write — `stop` does NOT mutate the
   queue, but it DOES rewrite `$WORK_STATE`, and we serialize
   writes via the same lock for predictable ordering against
   future Phase 5 `/api/work-state` writers).
4. Rewrite `$WORK_STATE` to `{"state": "idle", "updated_at": "<iso>"}`
   atomically (Python `os.replace`).
5. Write the `fulfilled.work-on-plans.<sprint-id>` marker.
6. Print:

   - If a cron was found: `/work-on-plans schedule stopped (was
     cron <id>, <schedule>).`
   - Else: `No active /work-on-plans cron found.`

Exit 0.

### Subcommand-level marker

After every successful mutating subcommand (including `every` and
`stop`, NOT including `next`), write a sprint-completion marker:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
printf 'skill: work-on-plans\nsprint_id: %s\nsubcommand: %s\nstatus: complete\ndate: %s\n' \
  "$SPRINT_ID" "$SUBCOMMAND" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$PIPELINE_DIR/fulfilled.work-on-plans.$SPRINT_ID"
```

This satisfies the same tracking-marker contract that `N`/`all`
sprints write at completion (Step 6).
