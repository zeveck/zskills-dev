---
name: work-on-plans
disable-model-invocation: true
argument-hint: "N|all [phase|finish] [every SCHEDULE] [now] [continue] [--force] | default <phase|finish> | stop | next | (no args = list ready queue)"
description: >-
  Batch-execute the prioritized ready queue from the dashboard: reads
  .zskills/monitor-state.json (plans.ready) and dispatches /run-plan auto
  [finish] per entry, honoring each plan's queued mode. N|all composes with
  every SCHEDULE + now for the queue-worker pattern (N plans per fire). Also
  manages the queue (add/rank/remove/default) and recurring schedules.
  Mirrors /fix-issues for bugs.
metadata:
  version: "2026.06.01+af83cd"
---

# /work-on-plans N|all [phase|finish] [every SCHEDULE] [now] [continue] [--force] | default <phase|finish> | stop | next — Batch Plan Executor

Dispatches `/run-plan <plan> auto [finish]` per entry in the
prioritized ready queue from the monitor dashboard. Mirrors
`/fix-issues` for bugs but operates on plans instead. The count
(`N`/`all`) **composes** with `every SCHEDULE` + `now`: each recurring
fire drains the captured count of plans (the queue-worker pattern —
`/work-on-plans 1 every 1h finish now` runs one plan now and one per
hour thereafter), exactly as `/fix-issues N every SCHEDULE now` does.

**Ultrathink throughout.** Use careful, thorough reasoning at every
step.

> **Phase note.** Phases 1 and 3 are landed: read-only listing
> (`(no args)`, `next`), the dispatch path (`N|all [phase|finish]
> [every SCHEDULE] [now] [continue]`), and the queue-mutation +
> scheduling subcommands (`add`, `rank`, `remove`, `default`,
> `every`, `stop`). All read-modify-write paths use the cross-process
> flock on `.zskills/monitor-state.json.lock` (Shared Schemas).

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
/work-on-plans N    [phase|finish] [every SCHEDULE] [now] [continue] [--force]
/work-on-plans all  [phase|finish] [every SCHEDULE] [now] [continue] [--force]
/work-on-plans add <slug> [pos]
/work-on-plans rank <slug> <pos>
/work-on-plans remove <slug>
/work-on-plans default <phase|finish>
/work-on-plans stop
```

`N`/`all` **compose** with `every SCHEDULE` + `now` — they are no
longer mutually exclusive (this is the parity fix with `/fix-issues`,
issue #906):

- **No `every`** → one-shot dispatch of the count, exactly as before.
- **`every SCHEDULE` without `now`** → register the recurring cron
  only; do NOT dispatch this invocation.
- **`every SCHEDULE` with `now`** → register the recurring cron AND
  dispatch the count immediately.

The recurring cron prompt **carries the count**:
`Run /work-on-plans $N <mode> every $SCHEDULE now` (mirrors
`/fix-issues`'s `sprint.md` count-carrying cron). Each fire drains the
captured `N` plans — NOT unconditional `all` — so "1 plan per hour"
(`/work-on-plans 1 every 1h finish now`) is now expressible. (Bare
`every SCHEDULE` with no leading count still registers a recurring
schedule; absent an explicit count it drains `all` per fire, as
before.)

**Parsing rules.** Treat `$ARGUMENTS` as whitespace-separated tokens.
Trim and lowercase each (slugs come pre-lowercased per Shared Schemas).

1. **Empty `$ARGUMENTS` → no-args read-only mode.** Print the ready
   queue listing (see "No-args output format") and exit 0.

2. **First token is `next` → next read-only mode.** Print the active
   schedule line and exit 0.

3. **First token is `stop` → cancel any active `/work-on-plans`
   cron** (see Step 7 — `stop`).

4. **First token matches `^[0-9]+$` → dispatch path (N).** Set `N` to
   that integer.

5. **First token is `all` → dispatch path (all).** Set `ALL_MODE=1`;
   `N` resolves to the count of `plans.ready` after sync (at dispatch
   time, in `modes/execute.md`).

6. **First token is one of `add`, `rank`, `remove`, `default`,
   `every`** → mutating subcommand (see Step 7 — Mutating
   subcommands). Subcommand keywords match slot 1 literally. A slot-1
   value matching `^[0-9]+$` or `^all$` routes to the dispatch path
   (rules 4–5). Bare `every` as the first token (no leading count) is
   still the recurring-schedule subcommand and drains `all` per fire.

7. **First token is anything else → usage error.** Print:

   > Usage: /work-on-plans (no args) | next | stop | N|all [phase|finish] [every SCHEDULE] [now] [continue] [--force] | add <slug> [pos] | rank <slug> <pos> | remove <slug> | default <phase|finish>

   Exit 2.

On the dispatch path (rules 4–5), the remaining tokens are recognised
by name (order insensitive, no positional meaning):

- `phase` → `MODE_OVERRIDE=phase` (mutex with `finish`)
- `finish` → `MODE_OVERRIDE=finish` (mutex with `phase`)
- `continue` → `CONTINUE_ON_FAILURE=1`
- `every` followed by a SCHEDULE expression → `SCHEDULE` captured;
  register a recurring cron (see Step 7 — `every`). **Composes with
  `N`/`all`** — the count is carried into the cron prompt.
- `now` → `RUN_NOW=1`. With `every`, dispatch this invocation AND
  schedule. Without `every`, `now` is a no-op (the default is to run).
- `--force` → `FORCE=1` (take over a foreign live schedule; relevant
  only with `every`).
- anything else → usage error (same message as above)

If both `phase` and `finish` appear, error:

> Usage: /work-on-plans … : `phase` and `finish` are mutually exclusive.

Order-insensitive: `N finish continue` ≡ `N continue finish`.

**Composed-form routing.** When `every` is present on the dispatch
path, route as follows (mirrors `/fix-issues` Phase 0):

1. **Register the recurring cron FIRST** — follow Step 7's `every`
   procedure (`subcommands/add-rank-remove.md`), passing the captured
   `N`/`ALL_MODE` so the cron prompt carries the count
   (`Run /work-on-plans $N <mode> every $SCHEDULE now`). When
   `ALL_MODE=1`, the cron prompt carries `all` instead of an integer.
2. **Then decide whether to dispatch this invocation:**
   - `now` present → fall through to the dispatch path
     (`modes/execute.md`) and drain the count immediately.
   - `now` absent → **exit after registration.** Do NOT dispatch now;
     the cron fires on schedule.

**The mode override is per-batch only.** It does NOT mutate the saved
`mode` on individual ready-queue entries or the top-level
`default_mode` in `monitor-state.json`.

## Step 0 — Setup

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
ZSKILLS_PATHS_ROOT="$MAIN_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$MAIN_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
export ZSKILLS_PLANS_DIR ZSKILLS_ISSUES_DIR ZSKILLS_AUDIT_DIR
SANITIZE="$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
[ ! -x "$SANITIZE" ] && SANITIZE="$MAIN_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
mkdir -p "$MAIN_ROOT/.zskills/tracking" "$MAIN_ROOT/.zskills" "$ZSKILLS_AUDIT_DIR"
MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"
MONITOR_LOCK="$MAIN_ROOT/.zskills/monitor-state.json.lock"
WORK_STATE="$MAIN_ROOT/.zskills/work-on-plans-state.json"
PLAN_INDEX="$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md"
```

The sanitizer fallback path covers source-tree development. In normal
installed use the `.claude/skills/...` path is canonical.

### Cross-process flock contract

All read-modify-write paths against `$MONITOR_STATE` (every mutating
subcommand: `add`, `rank`, `remove`, `default`, plus `every`'s
bootstrap of `monitor-state.json` if missing) must serialize against
the Phase 5 HTTP server through `$MONITOR_LOCK`. The shell idiom is
`flock -x <fd>` over a file descriptor opened on the lock file:

```bash
ensure_lockfile() {
  # Creates $MONITOR_LOCK if absent. Never truncates an existing file.
  [ -e "$MONITOR_LOCK" ] || : > "$MONITOR_LOCK"
}

with_monitor_lock() {
  # Usage: with_monitor_lock <bash-callable>
  # Acquires LOCK_EX on $MONITOR_LOCK for the duration of the call,
  # then releases it. Holds an open fd 9 while the callable runs;
  # the lock is released when fd 9 closes.
  ensure_lockfile
  (
    exec 9>"$MONITOR_LOCK"
    flock -x 9
    "$@"
  )
}
```

The lock file is created lazily and never deleted — concurrent CLI
invocations and the Phase 5 server share it. `flock -x` blocks until
the lock is acquired, with no timeout (the writes are fast enough
that contention is bounded). `os.replace()` inside Python performs
the actual atomic rename so concurrent readers always see a complete
file.

## Step 1 — sync (read monitor-state.json)

Read `$MONITOR_STATE` and extract `plans.ready`. The schema is
documented in `$ZSKILLS_PLANS_DIR/ZSKILLS_MONITOR_PLAN.md` § "Shared Schemas".

### Missing-file behaviour (auto-create on first read)

If `$MONITOR_STATE` does not exist, **bootstrap** it:

1. **Pick the seed source** by precedence:
   - **(1)** if `$PLAN_INDEX` exists AND `[ -r "$PLAN_INDEX" ]`,
     parse it for the drafted/reviewed classification.
   - **(2)** else, scan `$ZSKILLS_PLANS_DIR/*.md` frontmatter and apply the
     default-column inference table from
     `$ZSKILLS_PLANS_DIR/ZSKILLS_MONITOR_PLAN.md` § "Default column inference".

   If `$PLAN_INDEX` exists but is **unreadable** (e.g., `chmod 000`)
   or fails to parse, fall back to the frontmatter scan and warn to
   stderr — do NOT fail. Example warning:

   > /work-on-plans: PLAN_INDEX.md unreadable, falling back to frontmatter scan.

2. **Build the JSON.** `ready` always starts empty. `drafted` and
   `reviewed` are seeded from the chosen source. Use Python (stdlib
   only) to emit the file:

   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
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

<!-- allow-hardcoded: 2a.10-AC-non-using-sites reason: Python embed operates on non-ZSKILLS state files; no source+export preamble needed per pragmatic AC interpretation -->
```bash
# No ZSKILLS_* env vars needed: this embed operates on $MONITOR_STATE
# only (state file in $MAIN_ROOT/.zskills/, not via the path-config helper).
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

<!-- allow-hardcoded: 2a.10-AC-non-using-sites reason: Python embed operates on non-ZSKILLS state files; no source+export preamble needed per pragmatic AC interpretation -->
```bash
# No ZSKILLS_* env vars needed: this embed operates on $WORK_STATE
# only (state file in $MAIN_ROOT/.zskills/, not via the path-config helper).
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

## Step 3 — Route to execution path

Select the execution path based on the parsed arguments, then **read
the corresponding reference file in full and follow its procedure
end-to-end**. Do not proceed until you have read the file.

| Condition | Reference file |
|-----------|----------------|
| No args, or `next` | [modes/execute.md](modes/execute.md) — Steps 3-6 (read-only listing + dispatch loop + sprint completion) |
| Integer `N` or `all`, **with `every`** | [subcommands/add-rank-remove.md](subcommands/add-rank-remove.md) — Step 7 `every` (register the count-carrying cron) FIRST, then [modes/execute.md](modes/execute.md) Steps 3-6 only if `now` is present |
| Integer `N` or `all`, no `every` (one-shot dispatch) | [modes/execute.md](modes/execute.md) — Steps 3-6 (read-only listing + dispatch loop + sprint completion) |
| Bare `add`, `rank`, `remove`, `default`, `every`, `stop` | [subcommands/add-rank-remove.md](subcommands/add-rank-remove.md) — Step 7 (mutating subcommands) |

Both reference files assume all variables from Steps 0-2 are already
set (`$MAIN_ROOT`, `$MONITOR_STATE`, `$MONITOR_LOCK`, `$WORK_STATE`,
`$READY_TSV`, `$DEFAULT_MODE`, etc.) and the `ensure_lockfile` /
`with_monitor_lock` helpers are defined.

## Key Rules

- **Top-level only.** Subagents have no Agent tool; `/work-on-plans`
  refuses to run from a subagent context. Same defense as
  `/fix-issues`.
- **Skill tool dispatch.** `/run-plan` is invoked as
  `Skill: { skill: "run-plan", args: "$ZSKILLS_PLANS_DIR/<FILE>.md auto [finish]" }`.
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
- **Cross-process flock.** Every read-modify-write path against
  `monitor-state.json` (mutating subcommands `add`, `rank`,
  `remove`, `default`, plus `every`'s bootstrap) acquires
  `flock -x` on `.zskills/monitor-state.json.lock` for the entire
  read-modify-write window. Phase 5's HTTP server uses the same
  lock file — this prevents lost-update across the server/CLI
  boundary.
- **Schedule mode-capture invariant.** `every` resolves
  `schedule_mode` once at registration (CLI flag > current
  `default_mode` > `"phase"`) and persists it in
  `work-on-plans-state.json`. Each cron fire dispatches with the
  captured mode, NOT live `default_mode`. To change mode, `stop`
  and re-register.
- **Count-carrying cron (issue #906).** When `every` composes with a
  leading `N`/`all`, the count is persisted as `schedule_count` in
  `work-on-plans-state.json` and baked into the cron prompt
  (`Run /work-on-plans $N <mode> every $SCHEDULE now`), mirroring
  `/fix-issues`'s `sprint.md:53`. Each fire drains that many plans —
  NOT unconditional `all`. Bare `every` (no leading count) carries
  `all` per fire, as before.
- **Prune on completion (issue #906).** When a dispatched `/run-plan`
  reports `status: complete` for a plan, remove that slug from
  `plans.ready` in `monitor-state.json` — through `with_monitor_lock`
  + atomic `os.replace`, the same locked read-modify-write path the
  mutating subcommands use (a merged plan must not linger in `ready`).
- **Finish-mode SCHEDULE ≥ 1h.** `/work-on-plans every <s> finish`
  refuses sub-hour intervals. Phase mode has no minimum.
- **Same-session re-registration is idempotent.** `every` from the
  same `session_id` cancels the previous cron and registers anew
  without `--force`. Different-session non-stale entries refuse
  unless `--force`. Stale entries are silently overwritten.
- **Mirror after editing.** Edit `skills/work-on-plans/` source,
  then `bash scripts/mirror-skill.sh work-on-plans`. Never edit
  `.claude/skills/work-on-plans/` directly.
