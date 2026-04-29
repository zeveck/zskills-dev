---
title: Zskills Monitor Dashboard
created: 2026-04-18
status: complete
---

# Plan: Zskills Monitor Dashboard

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use
> worktree isolation with a named feature branch and PR per phase.

## Overview

Stand up a local web dashboard that gives a "live as possible" view of the
zskills repo — plans, issues, worktrees, branches, and recent tracking
activity — and closes the loop by letting the user drag plans and issues
between prioritized queue columns. A new `/zskills-dashboard` skill launches
the server as a detached background subprocess (PID file at
`.zskills/dashboard-server.pid`), and a new `/work-on-plans` skill consumes
the prioritized ready queue and dispatches `/run-plan <plan> auto` per
entry — mirroring how `/fix-issues` batch-executes bug fixes.

The server is Python stdlib only (no new dependencies) and uses
`http.server.ThreadingHTTPServer`. The frontend is a vanilla ES-module
HTML page (no framework, no build step) that polls `GET /api/state`
every 2 seconds. All queue state lives exclusively in
`.zskills/monitor-state.json`. **The server never mutates plan files.**
Default column for plans not yet in the state file is inferred from
plan frontmatter `status:` at read time only.

This plan also retires the `work`, `stop`, and `next-run` modes of
`/plans`. Going forward `/plans` keeps only `bare`, `rebuild`, `next`,
`details` (read-only index maintenance). All batch plan execution moves
to the new `/work-on-plans` skill, which takes its input from the
monitor-owned ready queue. Phase 9 reconciles the surviving
`/plans rebuild` classifier with Phase 4's Python aggregator so a
single classification source remains.

The monitor server itself runs in the main repo (no worktree) — it is a
long-lived background process, not a phase that lands a commit.
Implementation phases use the standard `/run-plan` worktree flow via
`scripts/create-worktree.sh`; this plan does not re-spec worktree
creation.

Scope boundaries: stdlib Python + native browser APIs only; no
plan-file mutation from the server; no `kill -9` / `killall` / `pkill`
on the server process — graceful SIGTERM only.

## Shared Schemas

Three data shapes are referenced by multiple phases. They are defined
once here so Phases 1, 3, 4, 5, and 7 all anchor to the same canonical
spec. Phase bodies must reference these by section name; do not
re-quote.

### `.zskills/monitor-state.json` (written by Phase 5, read by Phases 1/3/4/7)

```json
{
  "version": "1.1",
  "default_mode": "phase",
  "plans": {
    "drafted":  [{"slug": "slug-a"}, {"slug": "slug-b"}],
    "reviewed": [{"slug": "slug-c"}],
    "ready":    [{"slug": "slug-d", "mode": "phase"},
                 {"slug": "slug-e", "mode": "finish"}]
  },
  "issues": {
    "triage": [101, 102],
    "ready":  [103]
  },
  "updated_at": "2026-04-18T14:30:00-04:00"
}
```

- `version` = `"1.1"`. Consumers tolerate but ignore unknown top-level keys.
- Plan queue entries are objects: `{"slug": <str>}` always; `ready` entries
  may also carry `"mode": "phase" | "finish"`. `mode` is meaningful only on
  `ready` (drafted/reviewed don't dispatch). Absent `mode` → inherit
  `default_mode`; absent `default_mode` → `"phase"`.
- `default_mode` is the top-level toggle written by Phase 7 UI or
  `/work-on-plans default <mode>`.
- Mode dispatch mapping: `"phase"` → `/run-plan plans/<file>.md auto`
  (one phase per dispatch, multi-PR); `"finish"` → `/run-plan
  plans/<file>.md auto finish` (all remaining phases, single PR).
- **Version semantics.** On read, a `"version": "1.0"` file is treated as
  "all entries are phase mode, no `default_mode`" (forward-compat). On
  first write, the server upgrades to `"1.1"` schema and rewrites every
  `ready` entry as an object.
- Arrays preserve user-visible order exactly (first = topmost in column).
- `updated_at` is set server-side on every successful POST.
- **Cross-process consistency.** `os.replace()` is POSIX-atomic on the
  same filesystem: a concurrent reader sees either the previous or the
  new file in full, never a partial write. The plan does not use
  cross-process file locks; readers must still be defensive against
  unparseable JSON (treated as transient corruption — log and retry on
  next invocation).

### `.zskills/dashboard-server.pid` — `.env`-style key=value (no jq)

```
pid=12345
port=8080
started_at=2026-04-25T10:00:00-04:00
```

Lines are `key=value` (no spaces around `=`, no quotes). Bash readers
use `BASH_REMATCH` once, e.g.

```bash
PIDFILE_TXT=$(<.zskills/dashboard-server.pid)
[[ "$PIDFILE_TXT" =~ pid=([0-9]+) ]]        && PID="${BASH_REMATCH[1]}"
[[ "$PIDFILE_TXT" =~ port=([0-9]+) ]]       && PORT="${BASH_REMATCH[1]}"
[[ "$PIDFILE_TXT" =~ started_at=([^[:space:]]+) ]] && STARTED="${BASH_REMATCH[1]}"
```

Acceptance shape check is `grep -qE '^pid=[0-9]+$'` etc. — never jq.
jq is permitted in standalone Python/bash test fixtures only when bash
regex would be awkward; never in skill bodies.

### `.zskills/work-on-plans-state.json` (written by Phases 1/3, read by Phase 5's `/api/work-state`)

Tracks `/work-on-plans` activity so the dashboard can render Run/Status.
Three valid `state` values, each with its own additional fields:

```json
// state: idle
{ "state": "idle", "updated_at": "..." }

// state: sprint (one-shot N or all)
{ "state": "sprint", "sprint_id": "work-on-plans.<id>",
  "session_id": "<host>:<pid>:<invocation_start_time>",
  "started_at": "...",
  "progress": { "done": 1, "total": 3, "current_slug": "foo-plan" },
  "updated_at": "..." }

// state: scheduled (recurring `every`)
{ "state": "scheduled", "sprint_id": "work-on-plans.<id>",
  "session_id": "<host>:<pid>:<invocation_start_time>",
  "schedule": "every 4h", "schedule_mode": "phase",
  "session_started_at": "...", "last_fire_at": "...",
  "next_fire_at": "...", "updated_at": "..." }
```

- `session_id` = `<host>:<pid>:<invocation_start_time>` where
  `invocation_start_time` is ISO-8601 of when `/work-on-plans` first
  wrote to the state file. Compared as full string. PID reuse is
  harmless (new process gets a different `invocation_start_time`).
- **Initial fire-time.** At `every` registration, set
  `last_fire_at = session_started_at` so staleness computes from the
  schedule's birth, not epoch. First cron fire updates normally.
- **Scheduled staleness.** When `state == "scheduled"` and
  `last_fire_at` is older than `parse_schedule(schedule) + 30min`,
  readers render idle with a warning. `every` silently overwrites a
  stale entry; refuses to overwrite a non-stale entry from a different
  `session_id` without `--force`. Re-registration from the SAME
  `session_id` is treated as idempotent take-over: cancel the existing
  cron via `CronDelete`, then register the new schedule. `--force` is
  not required in the same-session case.
- **Sprint staleness.** When `state == "sprint"` and `updated_at` is
  older than 30min, treat as stale. `/api/work-state` returns
  `"state": "stale-sprint"`; UI offers a "Clear stale sprint state"
  button (POSTs `/api/work-state/reset`). `/work-on-plans` itself, on
  any read, detects stale-sprint and resets to idle without prompting.
- **Sprint heartbeat.** The orchestrator updates `updated_at` after
  every plan completion (between dispatches) — 30min survives a single
  long plan.
- **Atomic write.** Same as `monitor-state.json`: write `.tmp`, then
  `os.replace()`. No locking — last-writer-wins.
- The sprint entry stores its own `mode` at start (in-flight sprints
  unaffected by `default_mode` changes).

### `.claude/zskills-config.json` — `dashboard` block (read by Phase 5)

This plan adds one new top-level config block:

```json
"dashboard": {
  "work_on_plans_trigger": ""
}
```

- Empty/missing = no auto-trigger; `POST /api/trigger` returns 501 with
  `{"command": <cmd>}` so the UI can copy-paste.
- Set to a path → Phase 5 invokes the script per the **`POST /api/trigger`
  security contract** (Phase 5). The script is user-owned plumbing (write
  a marker, send a notification, ssh to a tmux pane, …); no default ships.
- Path resolution: resolved against `MAIN_ROOT` (not cwd); `Path.resolve()`
  is followed by symlinks, then re-checked to be inside `MAIN_ROOT`. A
  path that escapes (`../`) → HTTP 500 `{"error": "trigger path escapes
  MAIN_ROOT"}`. Non-executable / missing → HTTP 500 with the captured
  error; UI shows a toast.
- The block does NOT exist in the current `.claude/zskills-config.json`
  (verified). Phase 5's startup adds it if absent, with the empty default
  shown above.

### Canonical slug rule (single source of truth)

Slug = `basename(plan_path, ".md") | tr '[:upper:]_' '[:lower:]-'`.
This matches `/run-plan` exactly (`skills/run-plan/SKILL.md:405`)
so that `reports/plan-<slug>.md` lookups agree across `/run-plan`,
Phase 1's `/work-on-plans` slug→file resolver, and Phase 4's
snapshot. Phase 1 implements the rule inline (one-line `tr`) so it
can land before Phase 4; Phase 4 exposes the same rule as
`slug_of(path)` for reuse by later phases. **No other slug rule is
permitted in this plan.** Phase 4's accept tests must include at
least one fixture filename containing uppercase and `_` so Phase 1's
inline `tr` and Phase 4's `slug_of()` are exercised against the same
input shape.

### Default column inference — source of truth

Plans not yet in `monitor-state.json` are placed via this rule. Real
frontmatter `status:` values observed today (verified):
`active`, `complete`, `conflict`, `landed`, plus the literal placeholder
`$LANDED_STATUS`. (`pr-failed`/`pr-ready` only appear inside `.landed`
markers, never in plan frontmatter.)

| Frontmatter `status:` | Progress | Column |
|-----------------------|----------|--------|
| absent | any | `drafted` |
| `active` | no phases done | `drafted` |
| `active` | ≥1 phase done | `reviewed` |
| `complete`, `landed` | any | hidden |
| `conflict` | any | `reviewed` (needs attention) |
| `$LANDED_STATUS` (literal placeholder) | any | re-evaluate against `active` row |
| anything else | any | `drafted` |

Issues not in the state file default to `triage`.

### Landing-mode hint regex — source of truth

```python
LANDING_MODE_RE = re.compile(
    r"^\s*>\s*\*{0,2}Landing\s+mode:\s*([A-Za-z_-]+)\s*\*{0,2}",
    re.IGNORECASE | re.MULTILINE,
)
```

Captured value is lowercased. The dashboard's `landing_mode` field is
informational metadata; `/run-plan` resolves its own landing mode from
`$ARGUMENTS`/config (which is currently `"pr"` per
`.claude/zskills-config.json`). When the plan body has no hint AND
`.claude/zskills-config.json` is unreadable, the snapshot field is the
sentinel `"unknown"` (never silently `"cherry-pick"`); the parse error
is appended to `errors[]`.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — `/work-on-plans` execute-only CLI | ✅ Done | `12270a0` | landed via PR squash; new skill (677 lines) + parent: marker docs; 943/943 |
| 2 — Remove `/plans work` modes | ✅ Done | `76dbece` | landed via PR squash; 5 files updated; /plans work retired; 943/943 |
| 3 — `/work-on-plans` queue mutation + scheduling | ✅ Done | `f9290b7` | landed via PR squash; 6 subcommands + flock; SKILL 677→1249; +28 tests; 971/971 |
| 4 — Data aggregation library | ✅ Done | `b720fbb` | landed via PR squash; Python module at skills/zskills-dashboard/scripts/zskills_monitor/; 1277-line collect.py; 12 fixture sets; +29 tests; 1000/1000 |
| 5 — HTTP server | ✅ Done | `63747e5` | landed via PR squash; server.py 1099 lines; 9 endpoints; 127.0.0.1 only; trigger security contract; flock + atomic writes; +53 tests |
| 6 — Read-only dashboard UI | ✅ Done | `1239f6c` | landed via PR squash; static HTML/CSS/JS; 5 panels + 2 modals; XSS-safe; +45 tests; 1111/1111 |
| 7 — Interactive queue + write-back | ✅ Done | `208fb7f` | landed via PR #115 squash; drag-drop + default-mode + per-row chips + run-status + POST write-back; +47 tests; 1158/1158 |
| 8 — `/zskills-dashboard` skill | ✅ Done | `8ac36d9` | landed via PR #116 squash; SKILL.md 583 lines; start/stop/status w/ cmd+cwd identity check; SIGTERM-only; +35 tests; 1193/1193 |
| 9 — Migrate `/plans rebuild` to Python aggregator | ✅ Done | `84521bd` | landed via PR #117 squash; SKILL.md +69 lines; 3 modes wire to python3 -m zskills_monitor.collect; no bash fallback; +20 tests; 1213/1213 |

---

## Phase 1 — `/work-on-plans` execute-only CLI

### Goal

Ship the read+execute path of `/work-on-plans` — a batch executor
that reads the monitor-owned ready queue and dispatches `/run-plan
<plan> auto` per entry, modeled after `/fix-issues`. This phase is
the migration target for `/plans work` (retired in Phase 2). Queue
mutation and recurring-schedule subcommands land in Phase 3.

### Work Items

- [ ] Create `skills/work-on-plans/SKILL.md` with frontmatter.
- [ ] Implement CLI parse for the execute-only surface:
  - **Read-only:** `(no args)` lists ready queue + default + schedule;
    `next` prints active schedule + `next_fire_at`.
  - **Execute:** `N [phase|finish] [continue]` and `all [phase|finish]
    [continue]` — mode arg overrides per-entry/default for the batch
    only (does NOT mutate saved `mode`/`default_mode`).
- [ ] **sync** sub-step: read
  `MAIN_ROOT/.zskills/monitor-state.json` (Shared Schemas); extract
  `plans.ready` preserving each entry's `slug` and `mode`. Missing-file
  behaviour by subcommand: read-only (no args, `next`) auto-create
  `monitor-state.json` with `default_mode="phase"` and columns seeded
  per the **bootstrap precedence** rule below; `ready` starts empty —
  then print the (empty) ready-queue listing and exit 0; execute
  subcommands (`N`/`all`) use the same shared auto-create helper on
  first read so the bootstrapped file is identical regardless of
  entry point. Unparseable JSON → print path + diagnostic, exit 1.
  Unparseable / unreadable `monitor-state.json` AND
  `plans/PLAN_INDEX.md` are independent: an unreadable
  `PLAN_INDEX.md` falls back to frontmatter scan with a warning to
  stderr; an unparseable `monitor-state.json` halts (exit 1).
  All read-modify-write paths acquire the cross-process flock per
  Shared Schemas.
- [ ] **resolve** sub-step: build a slug→`plans/<FILE>.md` dict by
  scanning `plans/*.md` once and applying the canonical slug rule
  (Shared Schemas) inline as a one-line `tr` (`basename | tr
  '[:upper:]_' '[:lower:]-'`). Phase 1 self-implements the rule —
  it does NOT import `slug_of` from Phase 4 (which has not landed
  yet at the time Phase 1 ships). A queued slug with no matching
  file → fail loud with the message under Design.
- [ ] **dispatch** sub-step: for each plan, compute its dispatch mode
  (CLI override > per-entry `mode` > `default_mode` > `"phase"`), then
  invoke `/run-plan` via the **Skill tool** (see Dispatch mechanism)
  with args `plans/<FILE>.md auto` (mode=phase) or
  `plans/<FILE>.md auto finish` (mode=finish). No landing-mode flag —
  `/run-plan` resolves its own (currently `pr` per config).
  `/run-plan` itself uses `skills/create-worktree/scripts/create-worktree.sh`
  for worktree creation; `/work-on-plans` does not call it directly.
- [ ] Failure policy: stop on first `/run-plan` failure unless
  `continue` is set. Failure detection: see Design.
- [ ] Sprint-state tracking: `N`/`all` modes write
  `work-on-plans-state.json` with `state=sprint` at start (capturing
  resolved per-plan mode), update `progress.{done,current_slug}` AND
  `updated_at` on each completion (heartbeat per Shared Schemas
  sprint-staleness rule), and rewrite to `{"state":"idle"}` at end
  (or failure-without-continue). Any read path detecting a stale-sprint
  entry resets to idle without prompting. Any read path detecting an
  unparseable `work-on-plans-state.json` (invalid JSON) rewrites it to
  `{"state":"idle"}` with a warning to stderr — never blocks dispatch.
- [ ] Tracking markers (per `docs/tracking/TRACKING_NAMING.md`,
  Option B layout):
  - `.zskills/tracking/work-on-plans.<sprint-id>/
    fulfilled.work-on-plans.<sprint-id>` — written for `sprint` mode
    (NOT `next`, which is read-only).
  - `.zskills/tracking/work-on-plans.<sprint-id>/
    step.work-on-plans.<sprint-id>.<slug>` — one per dispatched plan.
  - When dispatching `/run-plan`: BEFORE dispatch, write
    `requires.run-plan.<plan-slug>` with `parent: work-on-plans` and
    `id: <sprint-id>` into the work-on-plans subdir (the parent's own
    subdir). AFTER `/run-plan` returns, write
    `fulfilled.run-plan.<plan-slug>` (same fields plus `status:
    complete` and `date:`) into the same parent subdir. Do NOT
    instruct `/run-plan` to emit `parent:` — `/run-plan` does not
    accept the field. The `parent:` field schema is: an optional
    `parent: <skill-name>` line in marker bodies, written by the
    parent skill when it writes `requires.*`/`fulfilled.*` for a
    dispatched child; consumed by Phase 4's activity scan to group
    dispatched runs under their orchestrator. (Documented inline
    here pending a section addition to `docs/tracking/TRACKING_NAMING.md`
    — see Phase 1 work item below.) The child `/run-plan` continues
    to write its own `fulfilled.run-plan.<plan-slug>` under
    `run-plan.<plan-slug>/` via its existing logic; `/work-on-plans`
    does not modify it. This matches `/fix-issues`'s actual pattern
    (`skills/fix-issues/SKILL.md`, anchor `grep -n 'parent: fix-issues'`
    locates the pattern at lines 346 and 924 of the file as of refine
    time — parent writes `requires.draft-plan.*` /
    `fulfilled.draft-plan.*` with `parent: fix-issues` into its own
    subdir).
  - Phase 4's activity scan reads `parent:` from the work-on-plans
    subdir's parent-tagged markers to group dispatched runs under
    their orchestrator in the UI.
  - All ids sanitized via
    `bash "$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"`.
- [ ] **Document the `parent:` marker field schema** in
  `docs/tracking/TRACKING_NAMING.md`. Add a sub-section "Parent-tagged
  markers" describing the field as: optional one-line `parent: <skill-name>`
  in `requires.*` / `fulfilled.*` marker bodies; written by the parent
  skill into its own subdir when dispatching a child; ignored by the
  child; consumed by readers (Phase 4 activity scan) to group dispatched
  runs. Cross-link from the Delegation semantics section. This closes
  the documentation gap raised in F-10.
- [ ] Mirror `skills/work-on-plans/` → `.claude/skills/work-on-plans/`
  via `bash scripts/mirror-skill.sh work-on-plans` (one shot, never
  per-file Edit; uses the hook-compatible mirror tool).

### Design & Constraints

**Frontmatter (verbatim):**

```yaml
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
```

The full argument-hint is shipped in this phase even though some
subcommands (`add`/`rank`/`remove`/`default`/`every`/`stop`) only
become functional in Phase 3 — the frontmatter is authoritative and
must not be rewritten between phases. Phase 1 implements the
read+execute slots; Phase 3 fills in the remaining slots.

**Positional-arg parsing (execute slots).** Slot 1 matching `^[0-9]+$`
or `^all$` routes to execute mode. In execute mode, tokens after
`N`/`all` are token-recognised: `phase` and `finish` are mode tokens
(mutex); `continue` is a flag; anything else errors. Order-insensitive
(`N finish continue` ≡ `N continue finish`). Phase 3 extends slot-1
recognition with subcommand keywords (`add`, `rank`, `remove`,
`default`, `every`, `stop`, `next`).

**Bootstrap precedence (PLAN_INDEX.md vs. frontmatter scan).**
`monitor-state.json` is seeded thus: (1) if `plans/PLAN_INDEX.md`
exists and is readable, parse it for the drafted/reviewed
classification; (2) else, scan `plans/*.md` frontmatter and apply the
default-column inference table (Shared Schemas). Both paths leave
`ready` empty. If `PLAN_INDEX.md` exists but is unreadable / parse
fails, fall back to the frontmatter scan and warn to stderr (do NOT
fail). `PLAN_INDEX.md` freshness is advisory only — Phase 1 does not
invoke `/plans rebuild`. Phase 9 later retrofits `/plans rebuild`
itself to call Phase 4's aggregator, at which point both producers
agree by construction.

**Slug → file path resolution.** Inline `tr '[:upper:]_' '[:lower:]-'`
applied to `basename(plan_path, ".md")` (Shared Schemas canonical
slug rule). Phase 1 self-implements; Phase 4 will later expose the
same rule as `slug_of(path)` for reuse by other phases. On unknown
slug:

```
/work-on-plans: queued slug '<slug>' has no matching plan file in
plans/. The monitor state file references a plan that no longer
exists. Open the dashboard to remove it from the queue, or edit
.zskills/monitor-state.json directly.
```

**Dispatch mechanism.** `/work-on-plans` runs at top level (parent
session). It dispatches `/run-plan` via the **Skill tool**, not the
Agent tool, using the canonical syntax documented in
`skills/research-and-plan/SKILL.md` § "Why /draft-plan must be invoked
via the Skill tool, not the Agent tool":

> invoke `Skill: { skill: "run-plan", args: "plans/<FILE>.md auto" }`

Per CLAUDE.md memory `project_subagent_architecture`, Claude Code
subagents cannot dispatch subagents; Skill is a top-level-only
primitive. `/work-on-plans` is a top-level skill (it is invoked
directly by the user or by cron, never as an Agent subagent), so
the Skill→Skill chain is supported. If `/work-on-plans` is somehow
invoked from a subagent context (no Agent tool visible), it prints
"`/work-on-plans` must run at top-level to dispatch /run-plan" and
exits 2 — same defense `/fix-issues` uses for its dispatch protocol.

**Dispatch loop.** For each plan in `plans.ready[0:N]`:
1. Resolve dispatch mode: CLI arg (if present) > entry's `mode` >
   `default_mode` > `"phase"`.
2. Write `step.work-on-plans.<sprint-id>.<slug>` with
   `status: started` and `parent: work-on-plans.<sprint-id>`.
3. Invoke `Skill: { skill: "run-plan", args: "plans/<FILE>.md auto" }`
   for `phase`, or `Skill: { skill: "run-plan", args: "plans/<FILE>.md
   auto finish" }` for `finish`.
4. On success → mark step `status: complete`.
5. On failure → without `continue`: stop, write summary to
   `reports/work-on-plans-<sprint-id>.md`, exit non-zero. With
   `continue`: log and proceed.

**No-args output format.** `/work-on-plans` (no args):

```
Ready queue (3 plans, default mode: phase):
  1. foo-plan       phase
  2. bar-plan       finish
  3. baz-plan       phase    (inherits default)
Default mode: phase     Schedule: idle
```

`Schedule:` line shows `idle`, `every <SCHEDULE> (next fire <ts>)`, or
`stale (last fire <age>)` based on `work-on-plans-state.json` — the
recurring-schedule branch is filled in by Phase 3; Phase 1 always
prints `Schedule: idle` since no `every` registration path exists yet.

**Failure detection.** `/run-plan` returns a result message; there
is no exit code. Treat the dispatch as a failure when ANY of:
(a) the result text contains `Phase \d+ failed`, `verification
failed`, or `rebase conflict` (case-sensitive grep on the response);
(b) the dispatched `/run-plan` wrote a `step.run-plan.*.implement`
marker but no matching `fulfilled.run-plan.*` within a 30-minute
timeout; (c) the Skill invocation itself returned an error (text
matches `^Error invoking skill\b` or contains `Skill .* not found`),
indicating the dispatch never reached `/run-plan`. The text-grep
arm is fragile to `/run-plan` output changes; this is acknowledged
debt — when `/run-plan` exposes a machine-readable failure indicator
(future work), prefer it.

**Tracking markers.** Option B layout (subdir = pipeline id) per
`docs/tracking/TRACKING_NAMING.md`. The `parent:` field is written by
`/work-on-plans` itself into ITS OWN subdir's `requires.run-plan.*`
and `fulfilled.run-plan.*` markers — matching the precedent in
`skills/fix-issues/SKILL.md` (anchor `grep -n 'parent: fix-issues'`).
The field schema is documented inline in this phase's Tracking-markers
work item AND added to `docs/tracking/TRACKING_NAMING.md` as a Phase 1
work item (closes F-10).

**Phase rules:**
- Never edit `.claude/skills/` directly. Edit `skills/` source,
  then mirror via `bash scripts/mirror-skill.sh <name>`.
- No jq in skill body.
- Phase 1 must self-implement the slug rule inline; importing
  `slug_of` would create a hard dependency on Phase 4 and block
  the migration ordering.

### Acceptance Criteria

- [ ] `skills/work-on-plans/SKILL.md` exists with the specified
  frontmatter (`grep '^name: work-on-plans' …` matches).
- [ ] Mirror byte-identical: `diff -q skills/work-on-plans/SKILL.md
  .claude/skills/work-on-plans/SKILL.md` returns 0; `diff -rq
  skills/work-on-plans/ .claude/skills/work-on-plans/` returns 0
  (catches sibling-file drift not caught by the single-file diff).
- [ ] `/work-on-plans` with no args prints the ready queue list per
  the no-args output format (priority + per-row mode), including
  default-mode and schedule status; exits 0 (read-only).
- [ ] Positional-arg parsing (execute slots): `/work-on-plans 3
  continue finish` and `/work-on-plans 3 finish continue` are
  equivalent and accepted; `/work-on-plans 3 banana` is rejected
  with a usage message.
- [ ] `/work-on-plans` (no args) on first run auto-creates
  `monitor-state.json` (bootstrap with empty `ready`, seeded
  drafted/reviewed columns from `plans/PLAN_INDEX.md` if present
  and readable, else a frontmatter scan), then prints the
  empty-queue listing.
- [ ] Bootstrap fallback: with `plans/PLAN_INDEX.md` made unreadable
  (e.g., `chmod 000`) `/work-on-plans` falls back to frontmatter
  scan, warns to stderr, and exits 0.
- [ ] State-file corruption recovery: with `work-on-plans-state.json`
  overwritten to invalid JSON, the next `/work-on-plans` invocation
  rewrites it to `{"state":"idle"}` with a stderr warning and
  proceeds.
- [ ] `/work-on-plans 1 phase` with one Ready plan dispatches
  `/run-plan plans/<FILE>.md auto`; CLI mode override does NOT mutate
  the entry's saved `mode`. Verified by: (a)
  `step.work-on-plans.<sprint-id>.<slug>` marker under
  `.zskills/tracking/work-on-plans.<sprint-id>/`; (b)
  `requires.run-plan.<slug>` AND `fulfilled.run-plan.<slug>` markers
  under the SAME `work-on-plans.<sprint-id>/` subdir, each carrying
  `parent: work-on-plans` and `id: <sprint-id>`; (c) `/run-plan`'s
  own `fulfilled.run-plan.<slug>` continues to land under
  `run-plan.<slug>/` (no `parent:` field, written by `/run-plan`
  itself, untouched by `/work-on-plans`).
- [ ] `/work-on-plans 1 finish` with one Ready plan dispatches
  `/run-plan plans/<FILE>.md auto finish`.
- [ ] Sprint state lifecycle: `/work-on-plans 2 phase` writes
  `work-on-plans-state.json` with `state=sprint` at start, updates
  `progress.done` after each plan, and rewrites to `{"state":"idle"}`
  at end (verified by snapshotting at three points).
- [ ] No-Agent-tool path: when invoked from a context lacking the
  Agent tool, `/work-on-plans` exits 2 with the documented
  diagnostic.
- [ ] Skill-error path: when the Skill invocation returns
  `Error invoking skill` or `Skill 'run-plan' not found`,
  `/work-on-plans` treats the dispatch as failed (stops without
  `continue`, logs and proceeds with `continue`).
- [ ] Unknown slug → fail-loud message (no silent skip).
- [ ] No jq in skill body: `grep -nE '\bjq\b'
  skills/work-on-plans/SKILL.md` returns no matches.
- [ ] Slug rule self-implemented (no `slug_of` import in Phase 1):
  `grep -nE 'slug_of|from\s+zskills_monitor' skills/work-on-plans/SKILL.md`
  returns no matches.
- [ ] Tracking marker `fulfilled.work-on-plans.<sprint-id>` appears
  under `.zskills/tracking/work-on-plans.<sprint-id>/` after
  `sprint`. After `next`, no new marker.
- [ ] `docs/tracking/TRACKING_NAMING.md` contains a "Parent-tagged
  markers" sub-section after this phase
  (`grep -n '## .*Parent-tagged' docs/tracking/TRACKING_NAMING.md`
  returns at least one match).
- [ ] Cross-process lock acquisition: a parallel-write fixture
  (two `/work-on-plans add <slug>` invocations forked in the same
  shell) produces a final `monitor-state.json` containing both new
  entries — verifies the flock prevents lost-update.

### Dependencies

- `/run-plan` skill (dispatch target; finish mode supported).
- `skills/create-worktree/scripts/sanitize-pipeline-id.sh` (invoked at
  install-time as `$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh`;
  in source-tree zskills tests as
  `$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh`).
- `skills/create-worktree/scripts/create-worktree.sh` (used by
  `/run-plan` itself; not invoked directly here).
- `/fix-issues` skill body (reference for CLI parsing, scheduling,
  reporting, and the `parent:` marker pattern — read-only).
- `scripts/mirror-skill.sh` (Tier-2; replaces the now-hook-blocked
  `rm -rf .claude/skills/<name> && cp -r …` recipe).
- No prior plan phase is required (this phase lands first).

---

## Phase 2 — Remove `/plans work` modes

### Goal

Retire the `work`, `stop`, `next-run` modes from `/plans` SKILL.md,
argument-hint, README, CHANGELOG, and PRESENTATION. `/plans` keeps
only `bare`, `rebuild`, `next`, `details` (read-only index
maintenance). Batch execution moves to `/work-on-plans` (Phase 1).

### Work Items

- [ ] Edit `skills/plans/SKILL.md`:
  - `argument-hint` becomes `"[rebuild | next | details]"`.
  - Remove the "batch execution" sentence and the `/plans work`
    usage example from the description; replace with "View plan
    status, find the next ready plan. For batch execution, see
    `/work-on-plans`."
  - H1 becomes `# /plans [rebuild | next | details] — Plan
    Dashboard` (drop "& Executor").
  - Delete the three mode-summary bullets for `work`, `stop`,
    `next-run`. Replace with one bullet: "**For batch execution:**
    see `/work-on-plans`."
  - Do NOT delete any `## Mode:` section — none exist for
    work/stop/next-run.
- [ ] Edit `README.md`: change the `/plans` row to drop "batch
  execution"; add a new row `| /work-on-plans | Batch-execute
  prioritized ready queue from the monitor dashboard |`.
- [ ] Edit `CHANGELOG.md`: add `### Migration — /plans work
  removed` explaining the move to `/work-on-plans` and listing
  affected skills. The entry MUST call out the cron-cleanup
  scope limitation (see Design): `CronDelete` only sees crons
  registered in the running session; users with `/plans work …
  every <N>` crons in OTHER sessions must run `CronList` +
  manual `CronDelete` from each affected session OR wait for
  those sessions to terminate (in-session crons die with the
  session).
- [ ] Edit `PRESENTATION.html` example. Reference by content
  anchor, not line number: replace `<code>/plans work 3 auto every
  6h</code>` with `<code>/work-on-plans 3 auto every 6h</code>`.
- [ ] Add a one-line footer to `/plans bare` output:
  > Note: this ranking is independent of the monitor dashboard's
  > Ready queue. For interactive prioritization, open
  > /zskills-dashboard.
- [ ] Cancel any in-session `/plans work … every SCHEDULE` crons
  before completing this phase. Run `CronList`; for every entry
  whose prompt matches `^/plans\s+work\b` (or the equivalent `Run
  /plans work` form), print the entry, then `CronDelete` it.
  Mirrors `/run-plan stop`'s cron-cleanup pattern. Skip prompts
  that don't match (don't touch `/run-plan` or `/fix-issues`
  schedules).
- [ ] Mirror `skills/plans/` → `.claude/skills/plans/` via
  `bash scripts/mirror-skill.sh plans`.

### Design & Constraints

The three retired modes (`work`, `stop`, `next-run`) appear in
`skills/plans/SKILL.md` ONLY in the argument-hint and mode-summary
bullets — there are no dedicated `## Mode:` sections to delete.
Verified existing top-level sections: Show, Details, Rebuild, Next,
Key Rules. Leave those unchanged.

`/plans rebuild` survives this phase unchanged. Phase 9 later
rewrites its body to invoke Phase 4's Python aggregator; until then
the existing bash/prose classifier is left in place — no
intermediate "TODO Phase 9" stub is added (zskills is
pre-backwards-compat, per `feedback_no_premature_backcompat`
memory).

**Cron-cleanup scope.** `CronList`/`CronDelete` are session-scoped
(per `project_scheduling_primitives` memory). When this phase runs
in a worktree (PR landing mode), it sees ONLY the worktree-session's
crons, not crons registered in the user's main session or other
sprints. The cleanup is therefore best-effort. The CHANGELOG entry
must document this so users know to run the cleanup from each
session that ever ran `/plans work … every`. In-session crons die
with the session, so any session that has terminated needs no
cleanup.

**Enumeration check (blocking).** Before declaring this phase complete:

```bash
grep -niE '\bwork\s+N\b|\bnext-run\b|/plans\s+(work|stop|next-run)' \
  skills/plans/SKILL.md
```

Returns zero lines. (`\bstop\b` alone is not checked — too many
legitimate uses.)

**Phase rules:**
- Never edit `.claude/skills/` directly. Edit `skills/` source,
  then `bash scripts/mirror-skill.sh plans`.
- Do not run `/plans rebuild` as part of this phase.

### Acceptance Criteria

- [ ] Enumeration check above returns zero lines.
- [ ] `skills/plans/SKILL.md` argument-hint equals exactly
  `"[rebuild | next | details]"`.
- [ ] README.md: `grep -nE '^\| `?/work-on-plans`? ' README.md`
  returns one row; `grep -niE '\bbatch\s+execution\b' README.md
  | grep -i plans` returns zero lines.
- [ ] CHANGELOG.md contains a `Migration — /plans work removed`
  entry introduced in this commit, including the cron-cleanup
  scope-limitation paragraph.
- [ ] PRESENTATION.html: `grep -n '/plans work' PRESENTATION.html`
  returns no matches AND `grep -cE '<code>/work-on-plans 3 auto every 6h</code>'
  PRESENTATION.html` returns exactly 1 (replacement present, not
  just removal).
- [ ] `diff -rq skills/plans/ .claude/skills/plans/` returns 0
  (catches mirror drift on sibling files).
- [ ] No surviving in-session `/plans work … every SCHEDULE` crons
  after `CronList` (best-effort; cross-session crons documented in
  CHANGELOG).

### Dependencies

- Phase 1 (`/work-on-plans` must exist as the migration target
  before retiring `/plans work`).
- `scripts/mirror-skill.sh`.

---

## Phase 3 — `/work-on-plans` queue mutation + scheduling

### Goal

Extend `/work-on-plans` (Phase 1) with the queue-mutation and
recurring-schedule subcommands. After this phase the full
argument-hint surface is functional.

### Work Items

- [ ] Implement CLI parse for the remaining surface:
  - **Queue manage:** `add <slug> [pos]`, `rank <slug> <pos>`,
    `remove <slug>` — modify `ready`. `default <phase|finish>` sets
    top-level `default_mode`.
  - **Schedule:** `every SCHEDULE [phase|finish] [--force]` registers
    a recurring sprint (refuses to overwrite non-stale entry from
    another `session_id` without `--force`); `stop` cancels.
- [ ] Extend the **sync** sub-step's missing-file branch: mutating
  subcommands (`add`/`rank`/`remove`/`default`/`every`) auto-create
  `monitor-state.json` via the same shared helper Phase 1 used (one
  bootstrap helper for both phases — separate call sites, identical
  output). `ready` starts empty. All read-modify-write paths acquire
  the cross-process flock per Shared Schemas.
- [ ] `every SCHEDULE [phase|finish]`: in-session cron via
  `CronCreate`, self-perpetuating like `/fix-issues`. **Mode-capture
  invariant.** At registration the resolved mode (CLI flag > current
  `default_mode` > `"phase"`) is captured as `schedule_mode`. Each
  fire uses the captured `schedule_mode`, NOT live `default_mode`. To
  change mode, `stop` and re-register. **`schedule_mode = finish` does
  NOT call `/run-plan finish`** — it dispatches `/run-plan
  plans/<file>.md auto finish` per ready plan (one PR per plan); the
  cron then waits for the next interval. Writes
  `work-on-plans-state.json` with `state=scheduled`,
  `session_id=<host>:<pid>:<invocation_start_time>`, `last_fire_at`,
  `next_fire_at` on each fire. At initial registration set
  `last_fire_at = session_started_at` (Shared Schemas). Run/Status
  widget shows captured `schedule_mode`, not `default_mode`.
- [ ] **Reject SCHEDULE < 1h when `schedule_mode=finish`** with a
  usage error: "When using finish mode, SCHEDULE must be ≥1h to
  avoid nested cron collision with /run-plan's phase-chaining
  crons. Use phase mode for shorter intervals." Phase mode has no
  minimum interval (cron risk is intrinsic to finish mode only).
- [ ] `stop` cancels the `/work-on-plans` cron via `CronDelete` and
  rewrites `work-on-plans-state.json` to `{"state":"idle"}`. `next`
  reads `work-on-plans-state.json` and prints the active schedule
  (or "no schedule") plus `next_fire_at` — the read-only `next`
  subcommand from Phase 1 is now backed by a real schedule.
- [ ] Tracking markers (extending Phase 1):
  `fulfilled.work-on-plans.<sprint-id>` is also written for
  `schedule` and `stop` modes (NOT `next`, still read-only).
- [ ] Mirror `skills/work-on-plans/` → `.claude/skills/work-on-plans/`
  via `bash scripts/mirror-skill.sh work-on-plans` (one shot, never
  per-file Edit).

### Design & Constraints

**Positional-arg parsing (extension).** Subcommand keywords (`add`,
`rank`, `remove`, `default`, `every`, `stop`, `next`) match slot 1
literally; slot 1 matching `^[0-9]+$` or `^all$` continues to route
to execute mode (Phase 1). `add <slug>` rejects digit-prefix slugs
(reserved for execute-mode `N`); such slugs must be added via the
dashboard or by editing `monitor-state.json`.

**Cron interactions.** `/work-on-plans every SCHEDULE [phase|finish]`
registers an in-session cron via `CronCreate` (each fire re-registers;
cron dies with the session). Each fire walks `plans.ready` and
dispatches `/run-plan plans/<FILE>.md auto` (when `schedule_mode=phase`)
or `/run-plan plans/<FILE>.md auto finish` (when `schedule_mode=finish`)
per resolved per-plan mode. **Caveat for `finish`:** `/run-plan`'s
finish mode self-registers its own short-interval crons (~5min) for
phase chaining; under recurring `every` fires this can cause two
nested cron generations. The `every` cron must therefore use a SCHEDULE
strictly larger than the per-plan finish completion window — the
minimum supported `SCHEDULE` for `every … finish` is `1h`, enforced
at registration (work item above). The `next` mode prints
`next_fire_at` from `work-on-plans-state.json`.

**Coexistence with `/run-plan` standalone crons.** `/run-plan` also
registers its own crons (e.g. via `/run-plan X.md auto finish` in a
separate session). `/work-on-plans every` does not check or remove
those — they are user-owned and operate on different state. If a
user has both a `/run-plan X.md` cron and a `/work-on-plans every
4h` cron whose ready queue includes plan `X`, both will dispatch and
the user is responsible for choosing one. Documented as expected
behavior; no auto-conflict resolution.

**Schedule ownership.** `every` consults `work-on-plans-state.json`
before registering: if `state=scheduled` from a different `session_id`
and not stale, refuse with "already scheduled by session X — pass
`--force` to take over." A stale entry is silently overwritten.
A non-stale entry from the SAME `session_id` is treated as idempotent
take-over: cancel the existing cron via `CronDelete` and register the
new one without requiring `--force` (per Shared Schemas).

**`CronCreate` failure.** If `CronCreate` returns an error, exit 1
with "Failed to register schedule: <error>. The plan will not run
automatically. You can run `/work-on-plans N phase` manually
instead." Do NOT write `work-on-plans-state.json` on failure.

**Phase rules:**
- Never edit `.claude/skills/` directly. Edit `skills/` source,
  then `bash scripts/mirror-skill.sh work-on-plans`.
- This phase only writes `monitor-state.json` and
  `work-on-plans-state.json` — it does NOT read the snapshot from
  Phase 4 (the dashboard is the read-side consumer of those files).

### Acceptance Criteria

- [ ] `/work-on-plans add <slug>` with no state file auto-creates
  `monitor-state.json` (bootstrap, same shape as Phase 1) and
  appends to `ready`; `rank`, `remove`, `default <phase|finish>`
  mutate the file as specified (verified by JSON parse pre/post).
  `default` does not touch per-entry `mode` values.
- [ ] `/work-on-plans add 4-phase-plan` is rejected with a usage
  message (digit-prefix slugs reserved; user must use the dashboard
  or edit `monitor-state.json` directly).
- [ ] Schedule ownership + staleness: `every` against a non-stale
  entry from another `session_id` refuses without `--force`; against
  a stale entry, overwrites silently and `next` prints `stale`
  beforehand. Same-session re-registration replaces the cron without
  `--force`.
- [ ] `/work-on-plans every 30m finish` → rejected with the
  ≥1h usage error; `/work-on-plans every 1h finish` → accepted.
  `/work-on-plans every 5m phase` → accepted (no minimum on phase
  mode).
- [ ] Schedule mode-capture invariant: register `every 4h` with
  `default_mode=phase`; flip `default_mode=finish` via UI; fire the
  cron and verify dispatch used captured `schedule_mode=phase`.
- [ ] Stale-sprint recovery: sprint state with `updated_at` 60min ago
  → GET returns `state:"stale-sprint"`; POST `/api/work-state/reset`
  rewrites to idle (JSON parse verified).
- [ ] `default <mode>` mid-sprint: in-flight sprint's recorded per-plan
  modes are unchanged (captured at start).
- [ ] `CronCreate` failure: simulate failure (mock or fixture); the
  skill exits 1, prints the diagnostic, and does NOT write
  `work-on-plans-state.json`.
- [ ] Tracking marker `fulfilled.work-on-plans.<sprint-id>` appears
  under `.zskills/tracking/work-on-plans.<sprint-id>/` after
  `schedule` or `stop`. After `next`, no new marker.
- [ ] Mirror byte-identical: `diff -rq skills/work-on-plans/
  .claude/skills/work-on-plans/` returns 0.
- [ ] Cross-process lock acquisition: a parallel mutation fixture
  (server POST + CLI `add` racing) yields a final `monitor-state.json`
  that contains both edits — verifies the flock prevents lost-update.

### Dependencies

- Phase 1 (extends the same skill body and shares the
  bootstrap-`monitor-state.json` helper).
- `skills/create-worktree/scripts/sanitize-pipeline-id.sh` (invoked
  via the canonical `$MAIN_ROOT/.claude/skills/create-worktree/scripts/`
  install-time path, or `$REPO_ROOT/skills/create-worktree/scripts/`
  in zskills source-tree tests).
- `CronCreate`/`CronDelete`/`CronList` primitives.
- `scripts/mirror-skill.sh`.
- This phase does NOT depend on Phase 4 — it only writes
  `monitor-state.json` / `work-on-plans-state.json`. Reads of
  those files happen in the dashboard stack (Phases 4–7).

---

## Phase 4 — Data aggregation library

### Goal

Pure-Python, stdlib-only module at
`skills/zskills-dashboard/scripts/zskills_monitor/` (owned by the
`/zskills-dashboard` skill created in Phase 8) that aggregates every
data source the dashboard renders into a single JSON document via
`collect_snapshot(repo_root)`. Pure functions, dict out.
Unit-testable without a server. **Standalone-callable invariant:**
`collect.py` MUST remain importable and runnable independently of
`server.py` (Phase 5) — the CLI
(`PYTHONPATH=…/skills/zskills-dashboard/scripts python3 -m zskills_monitor.collect`)
is the canonical isolation test. Future callers (notably Phase 9's
`/plans rebuild` migration) depend on this module having no
HTTP-server coupling. `collect.py` must not import from `server.py`.

**Module-location rationale.** Per `CLAUDE.md` and
`skills/update-zskills/references/script-ownership.md`, post-Phase-B
skill machinery lives at `skills/<owner>/scripts/`. Phase 8 creates
`/zskills-dashboard`; that skill is the natural owner for the
collector + server + static UI. Placing the package at the flat
`scripts/zskills_monitor/` would create a divergent precedent and
ship `/zskills-dashboard` without owning its own machinery.

### Work Items

- [ ] Create package `skills/zskills-dashboard/scripts/zskills_monitor/`
  with `__init__.py` (empty) and `collect.py`.
  (The `skills/zskills-dashboard/` directory is also touched by
  Phase 8's `SKILL.md`. The two phases edit disjoint files within
  the same skill directory; mirror discipline runs at the end of
  whichever phase lands last in any given sprint.)
- [ ] Implement `parse_plan(path) -> dict` — extract frontmatter,
  Overview blurb (first non-empty paragraph after `## Overview`,
  trimmed to 240 chars), Landing-mode hint (Shared Schemas regex),
  phase-heading list, and progress-tracker table with status-glyph
  map (`⬚`=todo, `⏳`/`⚙️`=in-progress, `✅`=done, `🔴`=blocked).
  Frontmatter parsed via the same regex idiom as
  `skills/briefing/scripts/briefing.py` (anchor: `def scan_plans` at
  the time of refine — locate via `grep -n '^def scan_plans'`).
  No PyYAML. Also derive `category`, `meta_plan`, and `sub_plans`
  per the categorization rules below.
- [ ] Implement `parse_report(slug) -> dict | None` — see "Report
  parsing rules" in Design.
- [ ] Implement `slug_of(path) -> str` exposing the canonical slug
  rule (Shared Schemas) for reuse by Phase 9 and any later caller.
  Behavior identical to Phase 1's inline `tr` rule.
- [ ] Implement tracking-marker scan — walk **both** flat top-level
  `.zskills/tracking/*` (legacy) and one-level-deep
  `.zskills/tracking/*/` subdirs. Dedup: when a file with the same
  basename appears in both layouts for the same pipeline-id,
  prefer the subdir copy and drop the flat one. If both copies
  exist with differing timestamps, the subdir copy still wins
  (the legacy flat copy is treated as informational); the conflict
  is recorded in `errors[]` with `source: "tracking dedup"` and the
  basename. Emit time-ordered activity list; flat-only entries
  carry `location: "legacy"`, subdir entries carry
  `location: "pipeline"` plus `pipeline: <subdir-name>` and (if
  present in marker text) a `parent: <parent-pipeline-id>` field.
- [ ] Implement worktree + branch listing reusing helpers from
  `skills/briefing/scripts/briefing.py`. Required helpers (located
  via `grep -n '^def …' skills/briefing/scripts/briefing.py` at
  refine time): `find_repo_root`, `parse_landed`,
  `classify_worktrees`, `parse_worktree_list`, `parse_for_each_ref`.
  Wrap helper invocations: any exception or non-zero subprocess
  return appends to `errors[]` with `source: "git worktree"` /
  `"git for-each-ref"` and returns an empty list. The aggregator
  never raises on git failure.
- [ ] Implement `list_issues()` — caches `gh issue list --state open
  --limit 500 --json number,title,labels,createdAt,body` for 60s in
  module-level state; on `gh` failure returns last cache or `[]`
  and appends to `errors[]`. Never raises. Cache is per-Python-process;
  CLI invocations from `/plans rebuild` and the server are independent
  cache scopes — documented limitation, not a bug (per DA-14).
- [ ] Implement state-file merge: read
  `MAIN_ROOT/.zskills/monitor-state.json` (path resolved via
  `find_repo_root` — always main, never cwd-relative); annotate each
  plan with `queue: {column, index, mode}` (mode = entry's `mode`
  if present on a `ready` entry, else `null`); annotate each issue
  with `queue: {column, index}`. Tolerate version `"1.0"` (flat string
  arrays — treat as `{slug: <str>, mode: null}`) and `"1.1"` (object
  arrays). Missing → empty queues silently. Unparseable → empty
  queues + append to `errors[]` with
  `source: ".zskills/monitor-state.json"` and the parse error
  message. Never raise.
- [ ] Surface top-level `default_mode` in the snapshot at
  `queues.default_mode` (default `"phase"` if absent).
- [ ] Implement `collect_snapshot(repo_root) -> dict` returning the
  stable JSON shape below. `repo_root` accepts `Path` or `str`.
- [ ] CLI: `PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts"
  python3 -m zskills_monitor.collect [--fixture DIR]` prints JSON to
  stdout for shell-test consumption. The CLI invocation pattern is
  documented inline in this phase's Design.
- [ ] **`errors[]` ordering & cap** (per DA-10). Sort by
  `(source, message)` ascending so the array is a deterministic
  function of the underlying error set. Soft cap at 100 entries; if
  exceeded, drop the oldest-source-first overflow and append one
  entry `{"source": "errors-cap", "message": "<N> errors elided"}`.
- [ ] Create test fixtures under `tests/fixtures/monitor/` (verify
  directory does not pre-exist before creating; current
  `tests/fixtures/` has only a `canary/` subdir, so `monitor/` is
  open):
  - `minimal/` — one plan, one report, one tracking marker.
  - `with-state/` — same plus a populated `monitor-state.json`.
  - `corrupt-state/` — same plus a malformed `monitor-state.json`
    to exercise the error path.
  - `slug-uppercase/` — plan filename `MY_PLAN_FILE.md` exercising
    the canonical slug rule (verifies Phase 1's inline `tr` and
    Phase 4's `slug_of()` produce identical output).
  - `category-canary/` — filename `CANARY42.md` with a small body
    (exercises the `category: "canary"` rule).
  - `category-issues/` — filename `BUG_TRACKER_ISSUES.md`
    (exercises `category: "issue_tracker"`).
  - `category-meta/` — plan body containing
    `Skill: { skill: "run-plan", args: "plans/sub.md auto" }`
    (exercises `meta_plan: true` + `sub_plans: ["sub"]`).
- [ ] `tests/test_zskills_monitor_collect.sh` — runs the CLI against
  each fixture, asserts JSON keys and types. Test output goes to
  `$TEST_OUT/.test-results.txt` per CLAUDE.md (never pipe). Register
  in `tests/run-all.sh`.

### Design & Constraints

**Module layout:**

```
skills/zskills-dashboard/
├── SKILL.md              # Phase 8
└── scripts/
    └── zskills_monitor/
        ├── __init__.py
        ├── collect.py    # this phase — pure aggregation, no HTTP
        ├── server.py     # Phase 5 (imports collect, NOT vice versa)
        └── static/       # Phase 6
            ├── index.html
            ├── app.css
            └── app.js
```

(The `static/` directory is conventionally a sibling of `scripts/`
in Python packaging, but here it ships INSIDE the `zskills_monitor`
package so the server can locate it via `pathlib.Path(__file__).parent
/ "static"` without PYTHONPATH gymnastics. This is acceptable for a
small embedded UI; if the static tree grows or needs CDN-ing, lift
it to `skills/zskills-dashboard/static/`.)

**PYTHONPATH discipline.** Every CLI invocation of the package, in
any phase, MUST set PYTHONPATH OR cd into the parent directory.
Canonical recipe:

```bash
MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts:${PYTHONPATH:-}" \
  python3 -m zskills_monitor.collect [args]
```

Equivalent for tests:

```python
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(MAIN_ROOT) /
                       "skills/zskills-dashboard/scripts"))
from zskills_monitor.collect import collect_snapshot
```

The `from scripts.zskills_monitor.…` import shape from earlier drafts
is RETIRED. The package is `zskills_monitor`, root-relative to its
own enclosing `scripts/` directory.

**Stdlib + internal helpers only.** Allowed external imports:
`json`, `subprocess`, `re`, `pathlib`, `os`, `sys`, `time`,
`datetime`, `argparse`, `typing`, `importlib.util`. **Forbidden:**
`yaml`, `pyyaml`, `requests`, any pip install, any Node tooling.

**Reuse from `briefing.py`.** Load via path-based import — the
canonical Python recipe for importing a module from outside the
import path:

```python
import importlib.util, pathlib
def _load_briefing(main_root):
    spec = importlib.util.spec_from_file_location(
        "briefing",
        pathlib.Path(main_root) / "skills" / "briefing" / "scripts" / "briefing.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
```

Helpers reused: `parse_worktree_list`, `parse_for_each_ref`,
`parse_landed`, `classify_worktrees`, `find_repo_root`. Locate by
anchor (`grep -n '^def <name>' skills/briefing/scripts/briefing.py`)
since briefing.py has been edited and line numbers drift.
`briefing.scan_plans` is NOT reused — its slug rule
(`os.path.splitext(basename)`) differs from the canonical slug rule
above; using it would break report lookups for any plan whose
basename contains uppercase or `_`.

(An equivalent simpler form is `sys.path.insert(0,
"$MAIN_ROOT/skills/briefing/scripts"); import briefing`. Either path
works; the spec_from_file_location form is preferred when the
collector is imported from contexts that already have a competing
top-level `briefing` module, which Phase 4 does not currently have
but is robust against.)

These internal imports do NOT count as "server coupling" — `briefing.py`
is part of the test harness and is exercised in the existing test
suite. `collect.py` must still not import `server.py` or any HTTP/socket
module.

**MAIN_ROOT resolution.** Every path that touches repo state
(`.zskills/`, `plans/`, `reports/`) is constructed as `MAIN_ROOT /
<rel>` where `MAIN_ROOT = find_repo_root()` — never cwd-relative.
This means `collect_snapshot` produces the same answer when invoked
from a worktree as from main.

**JSON shape — `collect_snapshot()` return value:**

```json
{
  "version": "1.0",
  "updated_at": "2026-04-18T14:30:00-04:00",
  "repo_root": "/workspaces/zskills",
  "plans": [
    {
      "slug": "zskills-dashboard-plan",
      "file": "plans/ZSKILLS_MONITOR_PLAN.md",
      "title": "Zskills Monitor Dashboard",
      "status": "active",
      "created": "2026-04-18",
      "issue": null,
      "landing_mode": "pr",
      "blurb": "Stand up a local web dashboard ...",
      "phase_count": 6,
      "phases_done": 0,
      "phases": [
        {"n": 1, "name": "Data aggregation library",
         "status": "todo", "commit": null, "notes": ""}
      ],
      "category": "executable",
      "meta_plan": false,
      "sub_plans": [],
      "has_report": false,
      "report_path": null,
      "queue": {"column": "reviewed", "index": 2, "mode": null}
    }
  ],
  "issues": [
    {"number": 42, "title": "...", "labels": ["bug"],
     "created_at": "...", "queue": {"column": "triage", "index": 0}}
  ],
  "worktrees": [
    {"path": "...", "branch": "feat/foo", "category": "named",
     "landed": {"status": "full", "date": "..."},
     "ahead": 0, "behind": 0, "age_seconds": 3600}
  ],
  "branches": [
    {"name": "feat/foo", "last_commit_at": "...",
     "last_commit_subject": "...", "upstream": "dev/feat/foo"}
  ],
  "activity": [
    {"timestamp": "...", "pipeline": "run-plan.<slug>",
     "kind": "fulfilled", "skill": "run-plan", "id": "<id>",
     "status": "complete", "output": "...",
     "location": "pipeline", "parent": null}
  ],
  "queues": { "plans": {...}, "issues": {...} },
  "state_file_path": ".zskills/monitor-state.json",
  "errors": [
    {"source": "gh issue list", "message": "..."}
  ]
}
```

Top-level keys are stable: `version`, `updated_at`, `repo_root`,
`plans`, `issues`, `worktrees`, `branches`, `activity`, `queues`,
`state_file_path`, `errors`. The shape is a contract consumed by
Phases 5–7 and Phase 9; any change is a breaking change and
requires updating those callers in the same commit.

**Plan parsing rules:**

- Slug per Shared Schemas (`tr '[:upper:]_' '[:lower:]-'`) exposed
  as `slug_of(path)`. Use this rule for the
  `reports/plan-<slug>.md` lookup.
- `landing_mode` resolution order: (1) plan-body Landing-mode regex
  (Shared Schemas); else (2) `.claude/zskills-config.json`
  `execution.landing`; else (3) **sentinel `"unknown"`**. Never
  silently fall through to `"cherry-pick"`. If config is missing or
  unparseable, append an error to `errors[]` and use `"unknown"`.
- Phase headings: `^##\s+Phase\s+(\d+)\s*[—-]\s*(.+)$`.
- Progress tracker table: locate the row with `^\|\s*Phase\s*\|`,
  parse subsequent `|`-separated rows, apply the status-glyph map.
- `phases_done` = count of progress-tracker rows with status `done`.
- **Categorization** (drives Phase 9's index sections):
  - `category = "canary"` if filename basename matches `^CANARY`
    (case-sensitive; `CANARY42.md`, `CANARY_TRACKING.md`).
  - `category = "issue_tracker"` if basename matches
    `_ISSUES\.md$` (case-sensitive on `ISSUES`; e.g.
    `BUG_TRACKER_ISSUES.md`).
  - `category = "reference"` if frontmatter has
    `executable: false` OR (heuristic) the plan body has zero
    `## Phase N` headings AND zero progress-tracker table.
  - Otherwise `category = "executable"`.
- **Meta-plan detection**: `meta_plan = true` if the plan body
  contains at least one `Skill: { skill: "run-plan"` literal
  (regex: `Skill\s*:\s*\{\s*skill\s*:\s*["']run-plan["']`).
  When true, `sub_plans` is the list of slugs extracted from the
  `args:` field of each such Skill directive. Empty list when no
  matches.

**Report parsing rules (`parse_report(slug)`):**

Reports live at `reports/plan-<slug>.md`. If absent, return `None`.
Section boundary: a level-2 heading starting with `## Phase` followed
by an em-dash or hyphen and a descriptive name. The phase token may
appear EITHER before the dash (`## Phase 5c — Name`, dominant in
non-canary reports) OR after it (`## Phase — 5c Name`, used in canary
reports). The token may be alphanumeric (`A`, `5c`, `12`); when no
distinct token is present (`## Phase — A`), treat the entire descriptive
text as both the token and the name. Implementer must pick a parser
that handles both shapes; add fixtures in `tests/fixtures/monitor/` for
both. Per-phase fields (all optional):

| Pattern | Field |
|---------|-------|
| `^\*\*Status:\*\*\s*(.+)$` | `status` |
| `^\*\*Worktree:\*\*\s*(.+)$` | `worktree` |
| `^\*\*Branch:\*\*\s*(.+)$` | `branch` |
| `^\*\*Commits?:\*\*\s*(.+)$` | `commits` (comma-split list) |

Reconcile to plan progress-tracker via
`int(phase_token.rstrip('abcdefghij'))`; on null `phase_token`, fall
through to name-based matching. Include the full markdown so the
Phase 6 modal can render it as preformatted text.

**Tracking marker scan:**

Walk both layouts (flat + per-pipeline subdir). For each file whose
basename matches `^(requires|fulfilled|step)\.(.+)$`, parse `key:
value` lines (`^(\w+):\s*(.+)$`) and emit an activity record. The
record's timestamp is the `date` field if present, else the `completed`
field (`step.*` markers use `completed:`; `requires.*`/`fulfilled.*`
use `date:`); if neither is present, drop the record and append to
`errors[]`. Sort descending by
`datetime.fromisoformat(timestamp).astimezone(timezone.utc)`
(parse-then-sort; never raw string sort — different offsets break
lexicographic order). Keep most-recent 200 in memory; UI trims to 20.
Dedup: if `fulfilled.X` appears both flat and inside `X/`, prefer the
subdir copy. On differing content/timestamps between the two copies,
subdir still wins; flat-copy timestamp/contents are not consulted but
the conflict is logged to `errors[]`.

**`gh` issue cache.** `list_issues()` caches results for 60s in
module-level state; on `gh` non-zero exit returns last cache or `[]`
and appends to `errors[]` with `source: "gh issue list"`. Never raises.
Per-process cache; documented limitation per DA-14.

**`errors[]` ordering & cap.** Sorted by `(source, message)`. Soft
cap at 100; overflow drops the oldest-source-first entries and adds
one summary entry. Per DA-10 — closes the per-poll re-render bug
where the UI's order-sensitive equality check would re-render when
the underlying error SET hadn't changed.

**Never use `|| true` or `2>/dev/null`.** Failures append to
`errors[]` with diagnostic source/message. Phase 6 surfaces these
to the UI as a banner.

### Acceptance Criteria

- [ ] `PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts"
  python3 -m zskills_monitor.collect --fixture
  tests/fixtures/monitor/minimal` exits 0 and the JSON contains all
  top-level keys listed in Design.
- [ ] **Standalone-callable check.** From a fresh Python REPL
  (no server running):
  ```python
  import sys, pathlib
  sys.path.insert(0, str(pathlib.Path(MAIN_ROOT) /
                         "skills/zskills-dashboard/scripts"))
  from zskills_monitor.collect import collect_snapshot, slug_of
  collect_snapshot(MAIN_ROOT)
  ```
  returns a dict with the documented top-level keys.
  `grep -nE 'from\s+\.server|from\s+zskills_monitor\.server|import\s+http\.server|import\s+socketserver'
  skills/zskills-dashboard/scripts/zskills_monitor/collect.py` returns
  no matches.
- [ ] **Snapshot key contract.** Output JSON top-level keys are
  exactly the set `{version, updated_at, repo_root, plans, issues,
  worktrees, branches, activity, queues, state_file_path, errors}`
  (no extras, no missing). Each `plans[]` entry has at minimum
  `{slug, file, title, status, phases, category, meta_plan, sub_plans,
  queue}`.
- [ ] **Category inference**: with the `category-canary/`,
  `category-issues/`, and `category-meta/` fixtures, snapshot's
  per-plan `category` is `"canary"`, `"issue_tracker"`, and
  `"executable"` respectively; `meta_plan` is `false, false, true`;
  `sub_plans` for the meta fixture is `["sub"]`.
- [ ] Queue annotation: with a fixture state file containing
  `{"version":"1.1","plans":{"ready":[{"slug":"zskills-dashboard-plan","mode":"finish"}]}}`,
  snapshot's `plans[0].queue == {"column":"ready","index":0,"mode":"finish"}`.
- [ ] Version 1.0 compat: a fixture with `{"version":"1.0",
  "plans":{"ready":["foo-plan"]}}` is read without error; the entry's
  `queue.mode == null`.
- [ ] Slug-rule parity: with the `slug-uppercase/` fixture
  (`MY_PLAN_FILE.md`), Phase 4's `slug_of()` and Phase 1's inline
  `tr` rule both produce `my-plan-file`.
- [ ] State-file absent: snapshot returns; every plan's `queue.column`
  follows the Shared Schemas inference table.
- [ ] State-file corrupt (`corrupt-state` fixture): snapshot returns
  without raising; `errors[]` contains one entry with `source:
  ".zskills/monitor-state.json"` and a non-empty `message`.
- [ ] `errors[]` is sorted: a fixture with three intentional errors
  yields snapshot's `errors[]` ordered by `(source, message)`
  ascending. Re-running `collect_snapshot` against the same fixture
  produces a byte-identical `errors[]` array (deterministic).
- [ ] `errors[]` cap: a fixture with 150 simulated errors yields
  100 entries plus one `{"source": "errors-cap", ...}` summary entry.
- [ ] Landing-mode resolution: a plan with `> **Landing mode: PR**`
  in body → `landing_mode == "pr"`. With config missing AND no
  blockquote → `landing_mode == "unknown"` and `errors[]` has the
  config-source entry.
- [ ] Tracking dedup: a fixture with both
  `fulfilled.run-plan.x` (flat) and `run-plan.x/fulfilled.run-plan.x`
  (subdir) yields one activity entry, not two; the subdir copy wins.
  Differing-content variant: same fixture but the two files have
  different `date:` values → still one entry (subdir wins) and
  `errors[]` has a `source: "tracking dedup"` entry.
- [ ] No PyYAML/requests:
  `grep -nE '^import\s+(yaml|requests)' skills/zskills-dashboard/scripts/zskills_monitor/collect.py`
  returns no matches.
- [ ] Briefing helpers reused via path import (NOT bare
  `from scripts.briefing`):
  `grep -nE '^from\s+scripts\.briefing\b'
  skills/zskills-dashboard/scripts/zskills_monitor/collect.py` returns
  no matches; `grep -nE 'spec_from_file_location|sys\.path\.insert.+briefing'
  skills/zskills-dashboard/scripts/zskills_monitor/collect.py` returns
  at least one match.
- [ ] Missing `gh`: snapshot returns with `issues: []` and `errors[]`
  entry; no exception propagated.
- [ ] Missing/broken `git`: simulate by mocking `briefing.run` to
  return empty/error; snapshot still returns; `worktrees: []`,
  `branches: []`; `errors[]` has a `source: "git ..."` entry.
- [ ] Issue cache: two consecutive `collect_snapshot()` calls within
  60s invoke `subprocess.run` once (verified by mocking).
- [ ] Worktree-portable: snapshot from a worktree (`/tmp/zskills-pr-…`)
  matches snapshot from main byte-for-byte (state-file paths resolve
  via `MAIN_ROOT`, not cwd).
- [ ] `tests/test_zskills_monitor_collect.sh` exits 0 and is
  registered in `tests/run-all.sh`.

### Dependencies

- External: Python 3.9+, `git`, `gh` (optional — degrades gracefully).
- Internal: `skills/briefing/scripts/briefing.py` helpers.
- Plan/report layout: `plans/*.md`, `reports/plan-<slug>.md`.
- Tracking layout per `docs/tracking/TRACKING_NAMING.md`.
- Phases 1 and 3 produce the `work-on-plans.<sprint-id>/` parent-tagged
  markers this snapshot scans (tolerated absent — no hard dependency).

---

## Phase 5 — HTTP server

### Goal

Expose Phase 4's `collect_snapshot()` over a localhost-only HTTP API
plus static file serving for the Phase 6 UI, with a detachable
background lifecycle (PID file + graceful SIGTERM).

### Work Items

- [ ] Create `skills/zskills-dashboard/scripts/zskills_monitor/server.py`
  using `http.server.ThreadingHTTPServer` and a
  `BaseHTTPRequestHandler` subclass.
- [ ] Implement routes per the route table; validate `<slug>` against
  `^[a-z0-9-]+$` and `<N>` against `^[0-9]+$` before any subprocess
  dispatch.
- [ ] `GET /api/state` → `collect_snapshot()` JSON.
- [ ] `GET /api/plan/<slug>` → plan detail. Look up via in-memory
  slug→file dict built from `plans/*.md` glob; never
  `os.path.join(plans_dir, slug+".md")` (defense-in-depth).
- [ ] `GET /api/issue/<N>` → `gh issue view <N> --json
  number,title,body,labels,comments,state` with `timeout=15`. On
  timeout: HTTP 504. On any other non-zero exit: HTTP 502 with
  `{"error": <gh stderr first line>}`.
- [ ] `POST /api/queue` → Origin check, JSON parse, strict shape
  validation, atomic write to `MAIN_ROOT/.zskills/monitor-state.json`.
  Acquires the cross-process flock (Shared Schemas) for the entire
  read+modify+write duration.
- [ ] `GET /api/work-state` → reads
  `MAIN_ROOT/.zskills/work-on-plans-state.json` (auto-creates as
  `{"state": "idle"}` if missing OR if existing file is unparseable
  JSON; in the unparseable case, append to a server-side error log
  and return idle); applies the staleness rule (Shared Schemas)
  before returning. Stale entries return as
  `{"state": "idle", "warning": "<message>"}`.
- [ ] `POST /api/trigger` → body `{"command": "/work-on-plans 3 phase"}`.
  Per the **`POST /api/trigger` security contract** below. Empty
  `dashboard.work_on_plans_trigger` → HTTP 501 + `{"command": <cmd>}`.
  Failures surface to UI; no silent swallow.
- [ ] `POST /api/work-state/reset` → Origin-checked, idempotent.
  Atomically writes `{"state": "idle", "updated_at": "..."}` via the
  read-then-write lock (cross-process flock + module-level
  threading.Lock); returns 200 with the new state. UI uses this to
  clear stale sprint/scheduled entries.
- [ ] `GET /api/health` → `{"status":"ok","uptime":<secs>,"pid":<int>,
  "port":<int>}`.
- [ ] Static file serving for `/`, `/app.js`, `/app.css` from
  `skills/zskills-dashboard/scripts/zskills_monitor/static/`
  (resolved server-side via
  `pathlib.Path(__file__).parent / "static"`).
- [ ] Bind to `127.0.0.1` only. **Port resolution chain** (replaces
  the legacy `bash scripts/port.sh` direct invocation):
  1. `DEV_PORT` env var if set and numeric → use it.
  2. Else read `dev_server.default_port` from
     `$MAIN_ROOT/.claude/zskills-config.json` using the
     `BASH_REMATCH`-equivalent regex idiom (Python `re`, not bash);
     same regex shape as `port.sh` and `scripts/test-all.sh`.
     If found and numeric → use it.
  3. Else invoke
     `bash "$MAIN_ROOT/.claude/skills/update-zskills/scripts/port.sh"`
     (or, in source-tree zskills tests,
     `$MAIN_ROOT/skills/update-zskills/scripts/port.sh`); `port.sh`
     itself reads `default_port` from config and additionally hashes
     worktree paths to derive a deterministic non-default port. If
     `port.sh` is missing or returns non-numeric output, print the
     friendly diagnostic to stderr ("port resolution failed: <error>;
     set DEV_PORT or restore .claude/skills/update-zskills/scripts/port.sh,
     or set dev_server.default_port in .claude/zskills-config.json")
     and exit 2 with no Python stack trace.
- [ ] Ensure the state-file directory exists before any write:
  `os.makedirs(MAIN_ROOT/'.zskills', exist_ok=True)` on startup
  (idempotent; covers the case where Phase 5 is started without
  Phase 8's `start` mode having pre-created the dir).
- [ ] Validate `dashboard.work_on_plans_trigger` config at startup
  if present: if the path resolves outside `MAIN_ROOT` or is not
  executable, append an entry to `errors[]` (visible in
  `/api/state`) with the diagnostic. Do NOT exit — the server still
  serves read-only routes; only `POST /api/trigger` will return
  500/400 per the security contract.
- [ ] Add the `dashboard` block to `.claude/zskills-config.json` if
  absent, with the empty default
  (`"dashboard": { "work_on_plans_trigger": "" }`). The current
  config file (verified) lacks this block; Phase 5 owns its
  introduction.
- [ ] PID file write to `MAIN_ROOT/.zskills/dashboard-server.pid`
  AFTER successful bind, in `.env`-style (Shared Schemas).
- [ ] SIGTERM/SIGINT handler: `server.shutdown()`, remove PID file,
  exit 0.
- [ ] Add `.zskills/monitor-state.json`,
  `.zskills/monitor-state.json.lock`,
  `.zskills/work-on-plans-state.json`, AND
  `.zskills/dashboard-server.pid` to `.gitignore` in this phase.
  (`.zskills/dashboard-server.log` is added in Phase 8 — that file
  is not written until Phase 8's `nohup` redirect.)
- [ ] `tests/test_zskills_monitor_server.sh` — start in background,
  curl each route, verify shapes, SIGTERM, verify PID-file removed.
  Output to `$TEST_OUT/.test-results.txt`. Register in
  `tests/run-all.sh`. Test launches the server with the canonical
  `PYTHONPATH=$MAIN_ROOT/skills/zskills-dashboard/scripts python3 -m
  zskills_monitor.server` recipe.

### Design & Constraints

**Route table:**

| Method | Path | Response | Notes |
|--------|------|----------|-------|
| GET | `/` | `static/index.html` (text/html) | |
| GET | `/app.js` | `static/app.js` (application/javascript) | ES module |
| GET | `/app.css` | `static/app.css` (text/css) | |
| GET | `/api/health` | `{status, uptime, pid, port}` | |
| GET | `/api/state` | Phase 4 snapshot JSON | `Cache-Control: no-store` |
| GET | `/api/plan/<slug>` | Plan detail JSON | 404 if slug unknown |
| GET | `/api/issue/<N>` | `gh issue view` JSON | 504 on timeout, 502 on other gh failure |
| POST | `/api/queue` | `{ok, updated_at}` | Origin check + shape validation + flock |
| GET | `/api/work-state` | work-on-plans-state.json + staleness | Auto-creates idle if missing |
| POST | `/api/trigger` | `{status, stdout, stderr, returncode}` or 501 + `{command}` | Origin check + security contract; subprocesses `dashboard.work_on_plans_trigger` if set |
| POST | `/api/work-state/reset` | `{state:"idle", updated_at}` | Origin check; clears stale sprint/scheduled state |

**Why a trigger hook?** The Python `http.server` cannot directly invoke
Claude Code skills — skills only run in the user's REPL session. The
dashboard therefore has to either (a) tell the user the command to
paste, or (b) call a user-provided trigger script that bridges back to
a session (e.g., writing a marker file a hook watches, sending a
notification, ssh'ing to a tmux pane). The plan ships option (a) by
default and supports option (b) via the
`dashboard.work_on_plans_trigger` config field. The trigger script is
user-owned plumbing; the plan does not ship a default.

**`POST /api/trigger` security contract:**

1. **Origin/Host check** — same as `/api/queue` (`127.0.0.1:<port>` or
   `localhost:<port>` only).
2. **Command allowlist** — body's `command` MUST match
   `^/work-on-plans(\s|$)`. Else HTTP 400 `{"error": "command must
   start with /work-on-plans"}`. The regex matches the URL-decoded
   command string; URL-encoded payloads are decoded by the HTTP
   layer before validation.
3. **Path validation** — `dashboard.work_on_plans_trigger` resolved
   against `MAIN_ROOT`; symlinks followed then re-checked inside
   `MAIN_ROOT`. Escape (`../`) → HTTP 500 `{"error": "trigger path
   escapes MAIN_ROOT"}`.
4. **Argv invocation, never shell** — invoke as `[<resolved_path>,
   <command>]` with `shell=False`. `shell=True` is non-compliant.
   Rationale: the command string is user-supplied and may contain
   shell metacharacters (pipes, redirects, backticks); `shell=False`
   passes the whole string as one argv element so the OS shell
   never interprets it.
5. **Environment scrubbing** — drop `ZSKILLS_PIPELINE_ID` and any
   `ZSKILLS_*` variable; pass through `PATH`, `HOME`, `USER`, `LANG`.
6. **Working directory** — `cwd=MAIN_ROOT`.
7. **Timeout** — 30s; on kill, HTTP 504 with stderr captured.
8. **Result encoding** — `{"status": "triggered"|"error", "stdout":
   "...", "stderr": "...", "returncode": N}`. Failures surface to UI;
   do NOT silently swallow.

**Slug validation order (`GET /api/plan/<slug>`).** The HTTP layer
decodes the URL-encoded path before regex match. The decoded
`<slug>` is matched against `^[a-z0-9-]+$`. Any non-matching value
(including `..%2F..%2Fetc` after decode → contains `/`) returns
HTTP 400. Lookup is via in-memory dict, never `os.path.join`.

**Plan detail shape (`GET /api/plan/<slug>`):**

```json
{
  "slug": "...",
  "file": "plans/...",
  "title": "...",
  "status": "active",
  "landing_mode": "pr",
  "blurb": "...",
  "overview_full": "<full Overview section markdown>",
  "phases": [
    {"n": 1, "name": "...", "status": "todo", "commit": null,
     "notes": "", "goal": "...",
     "work_items": [{"text": "...", "checked": false}],
     "acceptance_criteria": [...],
     "design_constraints_md": "...",
     "dependencies_md": "..."}
  ],
  "report": {"path": "reports/plan-<slug>.md", "markdown": "..."},
  "activity": [ /* filtered to this slug */ ]
}
```

**POST /api/queue body** matches Shared Schemas exactly. The server
fills `version` and `updated_at` (client-supplied values are ignored).

**Request validation (only the load-bearing checks):**
- `Origin` must equal `http://127.0.0.1:<bound-port>`. Missing or
  mismatched → HTTP 403. This kills drive-by CSRF; browsers always
  send a real `Origin` header on cross-site POSTs.
- Body parses as JSON and matches the exact shape: top-level keys
  `{default_mode?, plans, issues}`; `plans` columns
  `{drafted, reviewed, ready}`; `issues` columns `{triage, ready}`;
  plan entries are objects with required `slug` (matches `^[a-z0-9-]+$`)
  and optional `mode` (one of `"phase"`, `"finish"`, only meaningful on
  `ready`); `default_mode` (if present) is one of `"phase"`, `"finish"`;
  issue items are ints; no duplicate slugs within or across plan columns
  and no duplicate issue numbers within or across issue columns.
  Violation → HTTP 400. (No body-size cap and no Content-Type
  strictness — local-only server, JSON parse already rejects garbage.)

**Atomic write contract.** State file at
`MAIN_ROOT/.zskills/monitor-state.json`. Writes go through one
helper that: (1) acquires the cross-process `fcntl.flock(LOCK_EX)`
on `MAIN_ROOT/.zskills/monitor-state.json.lock` (Shared Schemas);
(2) acquires the module-level `threading.Lock` (in-process
serialization); (3) writes to a single tmp path inside the same
directory; (4) calls `os.replace(tmp, target)` (POSIX-atomic on same
filesystem); (5) releases the locks in reverse order. Pick
lock-OR-per-thread-tmp (one mechanism, not both — the threading.Lock
suffices for in-process serialization). Never write outside
`MAIN_ROOT/.zskills/`. **Cross-process scope.** The `flock` covers
concurrent CLI writers (Phases 1/3); `os.replace` covers concurrent
readers (snapshot, dashboard). Transient JSON parse failures on the
reader side are handled per Phase 1's "unparseable JSON" recovery
(idle reset / warn + retry).

**Read-then-write serialization.** Routes that read-then-write
(`GET /api/work-state` on stale detection, `POST /api/work-state/reset`,
`POST /api/queue`) acquire the `flock` + module-level
`threading.Lock` for the read+write duration. Atomic-write via
`os.replace` still applies.

**Server lifecycle contract.** `main()` resolves port (per the
**Port resolution chain** above), creates `.zskills/` if absent,
binds `ThreadingHTTPServer ("127.0.0.1", port)`, prints the friendly
port-busy message + exit 2 on `EADDRINUSE` (no Python stack trace),
writes the PID file (Shared Schemas key=value format) only after
successful bind, installs SIGTERM/SIGINT handlers that call
`server.shutdown()` + remove the PID file + `sys.exit(0)`, then
`serve_forever()`.

**Port-busy stderr text:**

```
Port <N> is already in use. Run 'lsof -i :<N>' to find the holder
and stop it manually (no kill -9). If .zskills/dashboard-server.pid is
stale, rm it and retry /zskills-dashboard start.
```

**Phase rules:**
- Bind to 127.0.0.1 only. Not `0.0.0.0`.
- No `kill -9`. No `|| true`. No `2>/dev/null`. Atomic writes only
  for the state file.
- Write PID file **after** successful bind.

### Acceptance Criteria

- [ ] Server starts: `PYTHONPATH=$MAIN_ROOT/skills/zskills-dashboard/scripts
  python3 -m zskills_monitor.server &` then
  `sleep 0.5 && curl -sf http://127.0.0.1:$PORT/api/health` returns
  200 with `status:"ok"` (verify with `grep -q '"status":[[:space:]]*"ok"'`,
  not jq).
- [ ] PID file shape: `grep -qE '^pid=[0-9]+$' .zskills/dashboard-server.pid
  && grep -qE '^port=[0-9]+$' … && grep -qE '^started_at=[0-9T:+-]+$' …`.
  Bash regex (Shared Schemas) extracts each field. The tightened
  `started_at` value pattern catches malformed timestamps that would
  break Phase 8's `date -d` arithmetic (per DA-8).
- [ ] PID liveness: `kill -0 $(grep -oE '^pid=[0-9]+'
  .zskills/dashboard-server.pid | cut -d= -f2)` returns 0.
- [ ] SIGTERM exit ≤5s: PID file removed and port freed.
- [ ] Fresh-repo bootstrap: with `.zskills/` removed,
  `python3 -m zskills_monitor.server &` succeeds; the dir is
  re-created and writes (PID, state) succeed.
- [ ] **Port resolution chain (replaces F-15 vacuous AC):** Verified
  in three sub-cases.
  (a) `DEV_PORT=9999 python3 -m zskills_monitor.server` → server binds 9999.
  (b) `DEV_PORT` unset, config has `dev_server.default_port: 8765` → server
      binds 8765.
  (c) `DEV_PORT` unset, `dev_server.default_port` removed from config,
      `.claude/skills/update-zskills/scripts/port.sh` made non-executable
      → server prints the friendly diagnostic (containing the words
      "port resolution failed") to stderr and exits 2 with no Python
      stack trace.
- [ ] Config-block bootstrap: `.claude/zskills-config.json` lacking
  the `dashboard` block before this phase contains it after the
  server has started once (`grep -E '"dashboard":' .claude/zskills-config.json`
  matches).
- [ ] Trigger-config validation surfaces in `/api/state`: with
  `dashboard.work_on_plans_trigger` set to a non-existent path,
  `/api/state` includes an entry in `errors[]` whose `source` mentions
  the trigger config.
- [ ] `curl -sf .../api/state | grep -q '"version":[[:space:]]*"1\.[01]"'` exits 0.
- [ ] `curl -o /dev/null -w '%{http_code}' .../api/plan/does-not-exist`
  prints `404`; slug `..%2F..%2Fetc` prints `400`; issue `abc` prints `400`.
- [ ] Valid POST returns 200 and the state file contains the new state.
- [ ] CSRF: POST without `Origin` returns 403; mismatched `Origin`
  returns 403.
- [ ] Invalid POST shape returns 400 and does NOT modify the state file.
- [ ] `/api/work-state`: GET with no state file returns
  `{"state":"idle"}` and creates the file; with a stale `scheduled`
  entry, returns `{"state":"idle","warning":...}` and rewrites idle.
  GET with an unparseable JSON file rewrites it to idle and returns
  `{"state":"idle"}` with the server-side error logged.
- [ ] `/api/trigger`: empty `dashboard.work_on_plans_trigger` → 501 +
  `{"command": <cmd>}`; configured script → `{status:"triggered",
  stdout, stderr, returncode}` with `returncode != 0` on script failure
  (no silent stderr swallow).
- [ ] `/api/trigger` security contract: (a) body `{"command": "rm -rf
  /"}` → 400; `/work-on-plans 3 phase` accepted. (b) trigger script
  echoing its argv shows `argv[1]` equal to the literal `command`
  string AND server source has `shell=False` / argv list (no
  `shell=True`). (c) trigger path `../../../tmp/evil.sh` → 500
  path-escape. (d) trigger script dumping `env` contains `PATH`/`HOME`
  but NOT `ZSKILLS_*`. (e) trigger script `pwd` equals `MAIN_ROOT`.
  (f) script that sleeps 60s returns 504 within ~30s.
- [ ] `/api/work-state/reset`: POST with stale `sprint` writes
  `{"state": "idle"}` atomically; concurrent GETs while reset is
  in-flight return consistent results (no half-rewritten file).
- [ ] Port-busy: starting a second server prints the friendly stderr
  message and exits 2 (no Python stack trace).
- [ ] `.gitignore` covers monitor-state, lock file, work-state, AND
  PID file: `git check-ignore .zskills/monitor-state.json
  .zskills/monitor-state.json.lock
  .zskills/work-on-plans-state.json .zskills/dashboard-server.pid`
  all exit 0.
- [ ] `grep -nE '2>/dev/null|\|\|\s*true'
  skills/zskills-dashboard/scripts/zskills_monitor/server.py` returns
  no matches.
- [ ] Bind only on 127.0.0.1: `ss -ltn | grep :$PORT | grep '127.0.0.1:'`.
- [ ] Worktree-portable: launching from a worktree writes the PID +
  state files under main repo's `.zskills/`, not the worktree.
- [ ] Cross-process flock acquisition: a parallel-write integration
  test (server POST + CLI mutation racing) yields a final state
  containing both edits.

### Dependencies

- Phase 4's `collect_snapshot()`.
- `skills/update-zskills/scripts/port.sh` (invoked at install-time
  as `$MAIN_ROOT/.claude/skills/update-zskills/scripts/port.sh`; in
  source-tree zskills tests as
  `$REPO_ROOT/skills/update-zskills/scripts/port.sh`). Port resolution
  also reads `dev_server.default_port` from `.claude/zskills-config.json`
  directly (Python `re`, BASH_REMATCH-equivalent idiom).
- `skills/briefing/scripts/briefing.py` (`find_repo_root` resolves
  `MAIN_ROOT`).
- `gh` CLI (graceful 502/504 if missing or slow).
- `fcntl` (stdlib) for cross-process flock.

---

## Phase 6 — Read-only dashboard UI

### Goal

Single-page vanilla HTML dashboard rendering the `/api/state` snapshot
into five panels — Plans, Issues, Worktrees, Branches, Recent
Activity — plus a top-level errors banner and drill-down modals for
plan and issue. No drag-and-drop yet (Phase 7). Polls every 2 seconds.
Matches `PRESENTATION.html` theme.

### Work Items

- [ ] Create
  `skills/zskills-dashboard/scripts/zskills_monitor/static/index.html`,
  `app.css`, and `app.js` (loaded as `<script type="module">`).
- [ ] Implement fetch + render pipeline. Behavioral contract: poll
  `/api/state` every 2s via `setTimeout` recursion (NOT
  `setInterval`); pause when `document.hidden`; force-load on
  `visibilitychange → visible`; diff per-panel (simple list-equality
  on backing array; for `errors[]`, hash the JSON-stringified array
  per DA-10 to make the equality check order-deterministic) and only
  re-render changed panels. Show a "Disconnected — retrying…" banner
  on non-2xx or fetch failure.
- [ ] Render `snapshot.errors[]` as a dismissible top banner (one
  line per error, `source: message`). The banner is the user-visible
  surface for parse/config/gh failures collected by Phase 4; without
  it, errors silently accumulate. Order is deterministic per
  Phase 4's sort; UI re-renders only when the JSON-stringified array
  changes.
- [ ] Plans panel: card per plan with title, blurb, phase-progress
  ratio, status badge, landing-mode pill (renders `unknown` as a
  warning pill).
- [ ] Issues panel: card per open issue (number, title, labels,
  created date).
- [ ] Worktrees panel: row per worktree (path basename, branch,
  `.landed` status badge, age).
- [ ] **Branches panel:** row per branch from `snapshot.branches[]`
  (name, last commit subject + age, upstream). User asked for
  "branches and worktrees" — both are surfaced. **Worktree-backing
  dedup:** for each branch, if any worktree has
  `worktree.branch == branch.name`, dim the branch row (CSS
  `opacity: 0.55`). Multiple worktrees on the same branch dim the
  row once (dedup is per branch name, not per worktree count). The
  match runs at render time off the snapshot's `worktrees[]` /
  `branches[]` arrays — no backref field is added to Phase 4.
- [ ] Recent Activity panel: last 20 tracking events (newest first)
  spanning every zskills skill invocation (run-plan, fix-issues,
  draft-plan, work-on-plans, zskills-dashboard, …). Each row shows
  pipeline-id, kind, skill, status, timestamp, and (if present)
  `parent` to surface dispatched-child relationships
  (e.g. `/work-on-plans` → `/run-plan`).
- [ ] Plan detail modal: opened on double-click or Enter; fetches
  `/api/plan/<slug>`; shows full Overview, phase list with
  status/commit/notes (commit shown as "Landed in <ref>" when
  non-null, "Pending" when null), work-item checkboxes
  (display-only), report path if present.
- [ ] Issue detail modal: same UX; renders body as preformatted text.
- [ ] Keyboard accessibility: every card has `tabindex="0"`, Enter
  opens modal, Esc closes, focus returns to the invoking card.

### Design & Constraints

**File budget (soft, reported only — not blocking):** `index.html`
~250 lines, `app.css` ~400, `app.js` ~700 in Phase 6 (Phase 7 grows
app.js). If a phase ends materially over budget, the Plan Review /
Drift Log records the actual size; this plan does not block on
budget. Hard rules: no framework, no build step, single ES module,
no inline event handlers (`addEventListener` only), no external
script imports.

**CSS variables.** Reuse `:root` variables verbatim from
`PRESENTATION.html:8-21` (`--bg`, `--surface`, `--surface2`,
`--border`, `--text`, `--text-dim`, `--accent`, `--accent2`,
`--green`, `--orange`, `--red`, `--pink`). Do not invent new names.

**Grid layout.** 5 panels in a responsive grid; on widths ≥900px
arrange Plans (largest) and Branches stacked at top, with Issues,
Worktrees, Activity flowing alongside. Below 900px, single-column
stack. Errors banner pinned at the top; modal is a full-document
overlay.

**Card markup convention.** Every card is `<article class="card"
tabindex="0" role="button" data-kind="…" data-slug|number="…"
aria-label="…">`. Modal uses a custom `role="dialog" aria-modal=
"true"` div (not `<dialog>` — focus inconsistencies); ESC handler is
global; focus is trapped via simple first/last-focusable tracking.

**Polling hygiene.** `setTimeout` recursion (not `setInterval`).
`cache: 'no-store'` on every fetch. Pause on `document.hidden`;
force-reload on `visibilitychange`. Naive 2s retry on fetch failure
(local-only server; no exponential-backoff complexity warranted —
the user can stop polling by closing the tab).

**Diff stability for `errors[]`.** Phase 4 sorts `errors[]` by
`(source, message)` and caps at 100 entries (per DA-10). Phase 6's
re-render check therefore compares
`JSON.stringify(state.errors)` to the previous value — equal strings
mean no re-render. Without the Phase 4 deterministic sort, ordering
churn between polls would force a banner re-render on every cycle.

**XSS escape policy (MANDATORY).** All user-authored content (plan,
issue, worktree, branch, tracking text) is rendered via
`element.textContent` or `document.createTextNode`. `innerHTML` is
allowed only for hardcoded chrome (panel headers, icons, scaffolding);
each such site carries the trailing comment `// chrome-only` on the
**same line** as the assignment.

Acceptance grep:

```bash
grep -nE '\.innerHTML\s*=' \
  skills/zskills-dashboard/scripts/zskills_monitor/static/app.js |
  grep -vE '//\s*chrome-only'
```

Must return no lines.

**Phase rules:** no npm / build step / bundler / framework; no
inline handlers; XSS policy is blocking.

### Acceptance Criteria

- [ ] Five panels visible (Plans, Issues, Worktrees, Branches,
  Activity) plus an errors banner element. Branches panel renders
  `snapshot.branches[]` with non-empty content when the repo has
  branches.
- [ ] Errors banner renders one row per `snapshot.errors[]` entry;
  hides when the array is empty.
- [ ] Errors banner re-render stability: a fixture where two
  consecutive `/api/state` GETs return errors in the same set
  (Phase 4's sorted order ensures byte-equal arrays) does NOT
  trigger a banner DOM re-render. Verify by mutation observer on
  the banner element.
- [ ] Branch dedup: with a fixture where a worktree backs branch
  `feat/foo`, the Branches panel row for `feat/foo` has the dimmed
  CSS class; an unbacked branch is rendered at full opacity.
- [ ] CSS vars present:
  `grep -c '^\s*--bg:\|^\s*--surface:\|^\s*--accent:'
  skills/zskills-dashboard/scripts/zskills_monitor/static/app.css`
  ≥ 3.
- [ ] No inline handlers: `grep -nE 'onclick=|onload='
  skills/zskills-dashboard/scripts/zskills_monitor/static/` returns
  no matches.
- [ ] XSS grep (above) returns no lines.
- [ ] No `setInterval`: `grep -nE 'setInterval\s*\('
  skills/zskills-dashboard/scripts/zskills_monitor/static/app.js`
  returns no matches.
- [ ] No external imports: `grep -nE 'import\s+.+from\s+["\x27]https?:'
  skills/zskills-dashboard/scripts/zskills_monitor/static/app.js`
  returns no matches.
- [ ] Plan detail modal: with a fixture plan having one phase with a
  non-null `commit` and another with null, the modal shows
  "Landed in <ref>" for the first row and "Pending" for the second.
- [ ] Manual playwright-cli checklist documented in the phase report
  covering: page loads; five panels visible; error banner renders
  when state has errors; plan card double-click opens modal with
  phase list; Esc closes modal; Tab reaches every card; Enter on
  focused card opens its modal; killing the server shows the
  Disconnected banner within one poll cycle.

### Dependencies

- Phase 5's server (static + API routes).
- Phase 4's snapshot shape stable (especially `errors[]`,
  `branches[]`, `activity[]`).

---

## Phase 7 — Interactive queue + write-back

### Goal

Turn the Plans panel into three drag-and-drop columns
(`Drafted`, `Reviewed`, `Ready`) and the Issues panel into two
(`Triage`, `Ready`). Drop changes column / priority. POST the new
full state to `/api/queue`, which atomically rewrites
`.zskills/monitor-state.json`. Keyboard fallback for non-drag users.

### Work Items

- [ ] Extend `app.js` to render Plans as 3 columns and Issues as 2,
  using `data-column` / `data-slug` / `data-number` hooks.
- [ ] Implement HTML5 native drag. Behavioral contract: each card is
  `draggable=true`; `dragstart` puts slug/number in `dataTransfer`;
  drop zones implement `dragenter`/`dragleave`/`dragover`(preventDefault)/
  `drop`. On drop, reorder DOM using a `clientY`-based insertion
  point, build the queue dict from current DOM order, POST to
  `/api/queue`, and on non-2xx revert immediately to the
  last-known-good local state and announce the failure.
- [ ] Default column inference for plans/issues NOT in state file
  follows Shared Schemas. **Never write inference back to plan
  files.**
- [ ] Reconciliation. After a successful POST, suppress the next
  poll cycle for `1.5s` and snap state to the POST response (which
  echoes the canonical state). On POST failure, immediately revert
  to last-known-good local state — do not wait for a poll. This
  prevents the visible flicker where a stale GET arrives between
  a user drag and the POST round-trip.
- [ ] Keyboard fallback per card: four buttons `↑ ↓ ← →` (move
  within column / between adjacent columns), each a real `<button>`
  in tab order with `aria-label`.
- [ ] ARIA: each column is `<ul role="list">` (interactive children
  rule out the listbox pattern); each card is `<li role="listitem">`.
  Column header has an `id` referenced by `aria-labelledby` on the
  `<ul>`. After each successful move, append a non-empty
  announcement to `#plans-live` (`aria-live="polite"`).
- [ ] **Default-mode toggle** in the Plans panel header
  (`Default mode: [Phase-by-phase | Finish (one PR)]`); click POSTs
  `/api/queue` with the new `default_mode`. When a sprint is in
  flight (per `/api/work-state`), render a small footnote next to
  the toggle: "Sprint in flight: change applies to plans not yet
  dispatched and to future sprints; in-flight plans keep their
  captured mode." (Per DA-13 — closes the cross-component
  surprise.)
- [ ] **Per-row mode chip** on each `Ready` card (`phase` / `finish`);
  click toggles the entry's `mode` via `/api/queue`. Chip styled
  differently for inherit vs. explicit override. Drafted/Reviewed
  cards have no chip.
- [ ] **Run / Status widget** at the top of the Plans panel, polling
  `/api/work-state` alongside `/api/state`. Render four states:
  - `scheduled` → "Running every 4h · next fire 14:30 · [Stop]" (Stop
    POSTs `/api/trigger` with `/work-on-plans stop`)
  - `sprint` → "Sprint in progress: 1/3 plans done · current: foo-plan"
  - `idle` + trigger configured → "[▶ Run top N]" button (POSTs
    `/api/trigger`); small numeric input for N, defaults to 3
  - `idle` + no trigger → "Copy and run: `/work-on-plans N <mode>`"
    with copy button (uses current `default_mode`)
  - stale-scheduled → "Schedule appears stale — restart with
    `/work-on-plans every 4h`" (user re-issues manually)
  - `stale-sprint` → "Sprint appears abandoned (last update Nm ago) ·
    [Clear stale sprint state]" (button POSTs `/api/work-state/reset`)
- [ ] Trigger-script-failure UI: on `/api/trigger` non-2xx other than
  501, surface stderr as a dismissible toast.
- [ ] Manual a11y test checklist documented in the phase report —
  must cover tab/enter/esc, ↑↓←→ buttons, drag, two-tab concurrent
  reorder, plan-file no-mutation invariant, default-mode toggle,
  per-row chip, and the in-flight-sprint footnote.

### Design & Constraints

**State file shape.** See Shared Schemas. Phase 7 is the first
writer; the atomic write helper (cross-process flock + atomic
rename) lives in Phase 5's `server.py`.
Phases 1, 3, and 4 are readers; Phases 1 and 3 also write via the
same flock contract.

**Mode UI vs. data.** The default-mode toggle and per-row chip mutate
`monitor-state.json` only — never `work-on-plans-state.json`. Mode
selection at dispatch time happens in `/work-on-plans`, not the UI.

**In-flight default-mode change semantics (per DA-13).** The default-mode
toggle changes `monitor-state.json:default_mode` immediately. Effects:
- Plans NOT yet dispatched in the current sprint, plus all future
  sprints, will resolve mode using the new `default_mode` (subject
  to per-entry `mode` overrides which are unchanged).
- Plans ALREADY dispatched in the current sprint keep their captured
  mode (per Shared Schemas sprint-state contract — the in-flight
  sprint stores its own `mode` at start).
- Newly-dragged-into-Ready plans get the new `default_mode` as their
  fallback.

The Plans panel renders a small footnote next to the toggle when
`/api/work-state.state == "sprint"` so users see the rule before
toggling.

**Concurrency model.** Last-write-wins on the server; the
cross-process flock + module-level `_STATE_LOCK` serialize POSTs
across both server and CLI writers. "Last" = "last to commit on
server clock," not user wall clock. Two tabs reordering is
acceptable; UI flickers briefly, neither tab crashes. The plan does
NOT add a per-tab "your changes were overwritten" warning UI —
local-only single-user dashboard, the briefly-flickering
reconciliation is treated as sufficient feedback.

**Plans panel DOM** (Phase 6's single list is replaced by a
`<div class="columns">` wrapping three `<div class="column">`
children, each containing an `<h3>` label + a `<ul class="dropzone"
role="list" aria-labelledby="…">`). Each card is `<li
role="listitem">` containing the card body plus a
`<div class="card-controls" role="group" aria-label="Move this
plan">` with the four `↑ ↓ ← →` buttons. Add `<div id="plans-live"
aria-live="polite" class="sr-only"></div>` inside the panel for
announcements.

**Phase rules:**
- **Never write plan frontmatter from the server.** Column state
  lives only in `.zskills/monitor-state.json`. Any code path that
  opens a plan file for writing in `server.py` is a bug.
- Atomic writes only (Phase 5's helper, including the flock).
- No optimistic deletion. POST failure → revert local DOM to
  last-known-good state immediately, then resume polling.
- No drag hints outside Plans / Issues panels — Worktrees,
  Branches, Activity remain read-only.

### Acceptance Criteria

- [ ] Dragging a plan card between columns updates
  `.zskills/monitor-state.json` within 2s (verify by diffing the
  file pre/post).
- [ ] State file is valid JSON after 100 consecutive POSTs.
- [ ] Concurrent POSTs (20 parallel `curl`): all complete without
  5xx, final state is valid JSON matching one of the bodies, no
  intermediate 0-byte read observed.
- [ ] **Cross-process lost-update integration test (per DA-6)**:
  with the server running, dispatch one POST `/api/queue` and one
  CLI `/work-on-plans add <slug>` in parallel (both target
  `monitor-state.json`); the final file contains both edits (the
  CLI's added slug AND the POST's column reordering). Verifies the
  flock prevents lost-update across the server/CLI boundary.
- [ ] `git diff plans/` is empty after any drag-drop session.
- [ ] Keyboard-only: `↓` button moves card down one position;
  verified by DOM + state-file diff.
- [ ] `aria-live` announcement: after each successful move,
  `#plans-live` contains non-empty text (length > 0; exact wording
  not asserted).
- [ ] Invalid POST (unknown column name) returns 400 and does NOT
  modify the state file.
- [ ] Two-tab last-write-wins: POST1 orders `[A,B,C]`, POST2 orders
  `[C,B,A]` arriving ~1ms after POST1 (sequential `curl`s with
  `&`); after both return, the state file matches POST2 (the later
  writer). Final read is exactly one of the two payloads, never a
  half-merged ordering.
- [ ] POST failure: simulating a 500 on `/api/queue` causes the UI
  to revert the dragged card to its previous slot within 200ms (no
  reliance on the next 2s poll).
- [ ] Default-mode toggle flips `default_mode` in the state file
  (verify by JSON parse pre/post).
- [ ] Per-row mode chip on a Ready card flips that entry's `mode`
  (verify by JSON parse); chip on inherit vs. override visually
  distinct (manual a11y check).
- [ ] **In-flight sprint footnote**: with `/api/work-state` stubbed
  to `{"state":"sprint", ...}`, the default-mode toggle area
  contains the footnote text "Sprint in flight"; with state
  `"idle"`, the footnote is absent.
- [ ] Run/Status widget renders the idle / sprint / scheduled /
  stale-scheduled / stale-sprint states from a stubbed
  `/api/work-state` response. The stale-sprint render exposes the
  "Clear stale sprint state" button which POSTs
  `/api/work-state/reset`.
- [ ] Manual a11y checklist documented in the phase report.

### Dependencies

- Phase 6's UI scaffold.
- Phase 5's `POST /api/queue`, `GET /api/work-state`, `POST /api/trigger`,
  cross-process flock contract.
- Phase 4's `queue` annotation (with `mode` field).
- Phases 1 and 3 read+write the state file under the same flock —
  schema changes must update them.

---

## Phase 8 — `/zskills-dashboard` skill

### Goal

Expose the server as a first-class skill: `/zskills-dashboard
[start|stop|status]`. Start launches the server detached with a PID
file. Stop sends SIGTERM (never `kill -9`). Status reports uptime + URL.

### Work Items

- [ ] Create `skills/zskills-dashboard/SKILL.md` with the frontmatter
  below. (The `skills/zskills-dashboard/scripts/zskills_monitor/`
  package is created by Phase 4; this phase adds the skill body. The
  two phases edit disjoint files in the same skill directory.)
- [ ] Implement `start`, `stop`, `status` mode bodies per the
  contracts below.
- [ ] Mirror to `.claude/skills/zskills-dashboard/` via
  `bash scripts/mirror-skill.sh zskills-dashboard` (hook-compatible
  per-file orphan removal; never `rm -rf` + `cp -r`).
- [ ] Tracking markers: write
  `fulfilled.zskills-dashboard.<id>` under
  `.zskills/tracking/zskills-dashboard.<id>/` for **state-changing
  invocations only** (`start`, `stop`). Skip for `status` (read-only)
  to avoid flooding tracking with one subdir per status check.
  `<id>` = `bash "$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"
  "zskills-dashboard-$(date -u +%Y%m%dT%H%M%SZ)"`
  (in source-tree zskills tests, use the `$REPO_ROOT/skills/...`
  prefix). Per `docs/tracking/TRACKING_NAMING.md`, the subdir name
  IS the pipeline-id (Option B layout).
- [ ] Add `.zskills/dashboard-server.log` to `.gitignore` (this
  phase owns the log; PID, monitor-state, lock, work-state files'
  gitignore moved into Phase 5 alongside the state files).
- [ ] Document `dashboard.work_on_plans_trigger` config field in
  CHANGELOG/README with an example trigger script (no default script
  is shipped — it is user-owned plumbing).

### Design & Constraints

**Frontmatter (verbatim):**

```yaml
---
name: zskills-dashboard
disable-model-invocation: true
argument-hint: "[start|stop|status]"
description: >-
  Local web dashboard for this repo — plans, issues, worktrees,
  branches, tracking activity, drag-and-drop priority queue.
  Starts a detached Python HTTP server on a port resolved from
  DEV_PORT / dev_server.default_port / port.sh; stop sends SIGTERM.
  State at .zskills/monitor-state.json. Usage:
  /zskills-dashboard [start|stop|status].
---
```

(`disable-model-invocation: true` matches the orchestrator-skill
convention — `/fix-issues`, `/plans`, `/quickfix`, `/do`, `/commit`
all do the same. The flag suppresses model auto-invocation; explicit
user invocation `/zskills-dashboard start` still works (per DA-12 —
flag does not break user-typed slash commands).)

**PID-file format.** See Shared Schemas (`.env`-style key=value, read
via `BASH_REMATCH` in one regex per field; never jq).

**MAIN_ROOT anchoring.** All three modes (start/stop/status) resolve
`MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` as
their first step and read/write the PID file as
`$MAIN_ROOT/.zskills/dashboard-server.pid` — never cwd-relative. Without
this anchor, invoking the skill from a worktree session would miss
the PID file in the main repo and the modes would diverge.

**Process-identity check (shared by start and stop).** Whenever a
PID is read from the PID file:
1. Run `ps -p $PID -o command=` and require the output to match
   `python3.*zskills_monitor.server`.
2. Additionally, verify the process's cwd matches `MAIN_ROOT` (per
   F-11). On Linux: `readlink /proc/$PID/cwd` must equal
   `$MAIN_ROOT`. On macOS (or Linux without `/proc`): fall back to
   `lsof -p $PID -d cwd -Fn` (parses the `n<path>` line). If the
   readlink/lsof itself fails (permission denied or tool missing),
   skip the cwd check and rely on command-name match alone (logged
   to stderr).

If EITHER check fails (command-name mismatch OR cwd-mismatch when
verifiable), treat the PID as stale or PID-reused: do NOT `kill` it;
instead remove the PID file and continue. The cwd check defends
against a different worktree's session matching `python3.*zskills_monitor.server`
on the same host.

**Start mode contract.**
1. If PID file exists: parse `pid`/`port` via `BASH_REMATCH`. `kill
   -0 $PID`. If alive AND process-identity check matches (command +
   cwd) → print "already running at http://127.0.0.1:$PORT/" and
   exit 0. Otherwise the PID is stale or PID-reuse or different-repo
   process → warn and remove the file before continuing.
2. Compute port: invoke
   `bash "$MAIN_ROOT/.claude/skills/update-zskills/scripts/port.sh"`
   (in source-tree tests:
   `$REPO_ROOT/skills/update-zskills/scripts/port.sh`). The script
   itself reads `DEV_PORT` env and `dev_server.default_port` config
   (Phase 5's resolution chain is the same logic, factored into the
   server; the skill body just calls the canonical script).
3. Pre-flight: if `lsof -iTCP:$PORT -sTCP:LISTEN` shows another
   holder, print the friendly busy message and exit 2.
4. Launch detached:
   ```bash
   mkdir -p "$MAIN_ROOT/.zskills"
   ( cd "$MAIN_ROOT" && \
     PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts:${PYTHONPATH:-}" \
     nohup python3 -m zskills_monitor.server \
       > .zskills/dashboard-server.log 2>&1 < /dev/null & disown )
   ```
   The PYTHONPATH prefix is required so the server's package
   (`skills/zskills-dashboard/scripts/zskills_monitor/`) is on
   `sys.path` when running with cwd=$MAIN_ROOT (per DA-5).
5. Sleep 500ms; `curl -sf http://127.0.0.1:$PORT/api/health` and
   verify `"status":"ok"` via `grep -q` (not jq). On success: print
   the URL and exit 0. On failure: print the last 20 lines of the
   log and exit 1 (do NOT send SIGTERM — there may be nothing
   running).

**Stop mode contract.**
1. No PID file → print "No running monitor (no PID file)." Exit 0.
2. Parse `pid`/`port` via `BASH_REMATCH`. `kill -0 $PID`; if dead,
   remove stale PID file and exit 0.
3. **Process-identity check** — both command name AND cwd (per
   F-11). If EITHER fails, print "PID $PID does not appear to be
   zskills-monitor for this repo (matched: <command>; cwd:
   <cwd-or-unknown>). Refusing to kill. Remove the PID file
   manually if stale." Exit 1. (Symmetric with start mode; prevents
   killing an unrelated process on PID-reuse OR a different
   worktree's monitor server.)
4. `kill -TERM $PID`. Poll `kill -0 $PID` every 200ms for up to 5s.
5. If still alive after 5s: print "Monitor did not exit within 5s.
   Run 'lsof -i :$PORT' and stop manually; do NOT kill -9." Exit 1
   (no escalation to SIGKILL — CLAUDE.md rule).
6. Verify port free with `lsof -iTCP:$PORT -sTCP:LISTEN`. Remove
   PID file. Exit 0.

**Status mode contract.**
1. No PID file → "Monitor not running." Exit 0.
2. Parse `pid`/`port`/`started_at` via `BASH_REMATCH`. The
   `started_at` value must match `^[0-9T:+-]+$` — if not, treat the
   PID file as malformed: print "PID file at <path> has malformed
   started_at; rm it and retry /zskills-dashboard start" and exit 1
   (per DA-8).
3. `kill -0 $PID`. If dead: print "Monitor PID file is stale (PID
   $PID not running). Run 'lsof -i :$PORT' to verify port is free,
   then retry /zskills-dashboard start." Exit 1.
4. Compute uptime from `started_at` (ISO-8601) using `date -d`
   arithmetic; print URL, PID, uptime, log path.

**Detachment.** `nohup … & disown` on Linux re-parents to PID 1
under most init systems. Acceptance verifies "process survives
parent shell exit" — checked by `kill -0 $PID` from a NEW shell —
without prescribing the specific reparent target (which varies:
PID 1 with sysvinit, `systemd --user` with user namespaces, launchd
on macOS). Hook-compatibility of `nohup … & disown` was verified at
plan refine time (`grep -n 'nohup\|disown'
.claude/hooks/block-unsafe-generic.sh` returned no matches).

**Mirror.** One command at the end of the phase (replaces the
hook-blocked `rm -rf` + `cp -r` recipe — per F-5/DA-1):

```bash
bash scripts/mirror-skill.sh zskills-dashboard
```

`mirror-skill.sh` is hook-compatible (per-file `rm`, no `-r` flag);
it handles file additions, updates, and orphan removal in one
invocation. Verified self-doc'd at
`scripts/mirror-skill.sh:1-9`.

**Phase rules:**
- No `kill -9` / `killall` / `pkill` / `fuser -k` anywhere.
- No jq in the skill body (Shared Schemas — `BASH_REMATCH` only).
- No `2>/dev/null` on fallible operations except where the failure
  is the expected branch (e.g. `kill -0` to detect a dead PID, or
  `readlink /proc/$PID/cwd` failing on non-Linux).
- Verify after every state change (start → curl health; stop →
  `kill -0` + `lsof`).

### Acceptance Criteria

- [ ] `skills/zskills-dashboard/SKILL.md` exists with the specified
  frontmatter.
- [ ] `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/`
  returns 0 (whole-tree mirror including SKILL.md and the
  `scripts/zskills_monitor/` package shipped with the skill).
- [ ] `grep -nE '\bjq\b' skills/zskills-dashboard/SKILL.md` returns 0
  matches.
- [ ] `grep -nE '\bkill\s+-9|killall|pkill|fuser\s+-k'
  skills/zskills-dashboard/SKILL.md` returns 0 matches.
- [ ] `start` writes a PID file and `/api/health` returns 200 within
  1s; `status` after start prints `^Monitor running`.
- [ ] PID-file shape: `grep -qE '^pid=[0-9]+$'
  .zskills/dashboard-server.pid && grep -qE '^port=[0-9]+$' … &&
  grep -qE '^started_at=[0-9T:+-]+$' …` (tightened pattern catches
  malformed timestamps that would break Phase 8 status mode's
  `date -d` arithmetic, per DA-8).
- [ ] `stop` removes the PID file and frees the port within 5s.
- [ ] `start` twice → second run detects live PID + matching command
  name + matching cwd and prints the URL without launching a duplicate.
- [ ] `stop` twice → second run prints the no-PID-file message,
  exits 0.
- [ ] **Stop mode PID-mismatch defense (command-name).** Write a
  PID file pointing at a long-running unrelated process (e.g. a
  sleep loop with a known PID); run `/zskills-dashboard stop` and
  verify it prints the mismatch diagnostic, does NOT kill the
  unrelated process, and exits 1.
- [ ] **Stop mode PID-mismatch defense (cwd).** Launch a second
  monitor server in a worktree (different `MAIN_ROOT`); from the
  first repo, write a PID file pointing at the worktree's PID and
  run `/zskills-dashboard stop`. The cwd check fails (worktree's
  cwd ≠ this repo's MAIN_ROOT), the skill prints the mismatch
  diagnostic, does NOT kill the worktree's server, and exits 1.
- [ ] State-changing tracking marker: after `start` (or `stop`),
  `.zskills/tracking/zskills-dashboard.<sanitized-id>/
  fulfilled.zskills-dashboard.<sanitized-id>` exists with
  `skill:`/`id:`/`status:`/`date:` fields. After `status` no new
  marker is written.
- [ ] Detachment survival: in a NEW shell after the launching shell
  exited, `kill -0 $(grep -oE '^pid=[0-9]+'
  .zskills/dashboard-server.pid | cut -d= -f2)` returns 0 AND
  `curl -sf http://127.0.0.1:$PORT/api/health | grep -q '"status"'`
  exits 0.
- [ ] PID-reuse defense: a PID file pointing at a non-monitor
  process (e.g. `bash`) is treated as stale; `start` does not
  print "already running" against it.
- [ ] PYTHONPATH discipline: `grep -nE 'PYTHONPATH=.*skills/zskills-dashboard/scripts'
  skills/zskills-dashboard/SKILL.md` returns at least one match
  (start-mode contract sets PYTHONPATH).
- [ ] Mirror tool used: `grep -nE 'mirror-skill\.sh'
  skills/zskills-dashboard/SKILL.md` returns at least one match;
  `grep -nE 'rm\s+-rf\s+\.claude/skills'
  skills/zskills-dashboard/SKILL.md` returns no matches.

### Dependencies

- Phase 5's server (launch target).
- `skills/update-zskills/scripts/port.sh` (invoked at install-time
  as `$MAIN_ROOT/.claude/skills/update-zskills/scripts/port.sh`; in
  source-tree zskills tests as
  `$REPO_ROOT/skills/update-zskills/scripts/port.sh`).
- `skills/create-worktree/scripts/sanitize-pipeline-id.sh` (canonical
  `$MAIN_ROOT/.claude/skills/create-worktree/scripts/...` install path).
- `scripts/mirror-skill.sh` (Tier-2 hook-compatible mirror tool).
- `lsof`, `kill`, `ps`, `readlink` / `lsof -p` for cwd check
  (standard on supported Linux + macOS).
- `.zskills/` writable.

---

## Phase 9 — Migrate `/plans rebuild` to Python aggregator

### Goal

Eliminate the duplicated classifier between `/plans rebuild` (prose
spec in `skills/plans/SKILL.md`) and Phase 4's
`skills/zskills-dashboard/scripts/zskills_monitor/collect.py`. After
this phase `/plans rebuild | next | details` continues to expose the
same CLI surface to users, but its implementation reads classification
from the Python aggregator instead of restating the rules in skill
prose. Single source of truth for plan classification: `collect.py`.

### Work Items

- [ ] Edit `skills/plans/SKILL.md`'s `## Mode: Rebuild` section to
  invoke the Phase 4 aggregator. The new prose instructs the
  implementing agent to:
  1. Run `PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts"
     python3 -m zskills_monitor.collect` (which calls
     `collect_snapshot(repo_root)`) and parse the resulting JSON.
  2. Group `snapshot.plans[]` into the index sections using the
     `category`, `meta_plan`, `status`, and `phases_done` fields.
     Mapping (per the current `/plans rebuild` index — six sections):
     - **Ready to Run** ← `category=="executable"` AND
       `status=="active"` AND `phases_done == 0` AND
       `queue.column != "ready"` (top of the run-eligible list);
       OR `queue.column == "ready"`.
     - **In Progress** ← `category=="executable"` AND
       `status=="active"` AND `phases_done >= 1` AND
       `phases_done < phase_count`.
     - **Needs Review** ← `category=="executable"` AND
       `status=="conflict"` (any progress).
     - **Complete** ← `status in {"complete","landed"}`.
     - **Canaries** ← `category=="canary"`.
     - **Reference (not executable)** ← `category in
       {"reference","issue_tracker"}`.
     - Meta-plans (`meta_plan==true`) are listed under their
       sub-plan's section per existing prose convention; the
       implementing agent surfaces them as a parent-of-list.
  3. Render `plans/PLAN_INDEX.md` from the grouped data, preserving
     the existing index file shape (header, sections, last-rebuilt
     timestamp).
  - The existing prose-spec classification rules in `Mode: Rebuild`
    are removed (they now live in `collect.py`'s plan parsing +
    default-column inference + categorization).
- [ ] Update `## Mode: Next` and `## Mode: Details` similarly: read
  `collect_snapshot()` instead of re-parsing plan frontmatter. Keep
  user-visible behavior identical.
- [ ] Add a sanity test under `tests/test_plans_rebuild_uses_collect.sh`
  that runs `/plans rebuild` (or invokes the same code path) and
  asserts `plans/PLAN_INDEX.md` is regenerated and references the
  same set of plans `python3 -m zskills_monitor.collect` reports
  (matching SECTION-by-SECTION via the categorization rules above).
  Output goes to `$TEST_OUT/.test-results.txt`. Register in
  `tests/run-all.sh`.
- [ ] Mirror `skills/plans/` → `.claude/skills/plans/` via
  `bash scripts/mirror-skill.sh plans`.

### Design & Constraints

`/plans` is `disable-model-invocation: true` and the rebuild logic
is implemented by the parent agent reading the skill prose. The
migration is a prose rewrite, not new code: the agent's instructions
change from "read plan frontmatter, classify per these rules" to
"shell out to `PYTHONPATH=… python3 -m zskills_monitor.collect`,
then group the returned plans into index sections per the
category/meta_plan mapping above." The Python aggregator's
`slug_of()`, `parse_plan()`, default-column inference, and the new
`category`/`meta_plan`/`sub_plans` fields (added in Phase 4 per
F-12) are sufficient to drive the index render.

**No CLI surface change.** `/plans bare | rebuild | next | details`
keep their argument-hint, descriptions, and user-visible output
unchanged. Migration is internal.

**Standalone-callable dependency.** This phase relies on Phase 4's
**Standalone-callable invariant** (Phase 4 Goal): `collect.py` must
be importable and runnable independent of `server.py`. `/plans
rebuild` invokes the collector via the CLI
(`PYTHONPATH=…/skills/zskills-dashboard/scripts python3 -m
zskills_monitor.collect`) — no HTTP server is required.
If the CLI invocation fails (module missing, import error, non-zero
exit), `/plans rebuild` reports the error to the user and exits
non-zero — there is no fallback to a legacy bash classifier.

**Python 3.9+ precondition (per DA-7).** After this phase, `/plans
rebuild` requires Python 3.9+ in the user's environment. Environments
without Python 3 cannot run `/plans rebuild`. This is consistent with
Phase 4's runtime requirement and with the project's pre-backwards-compat
posture (`feedback_no_premature_backcompat`). The DA noted this as a
regression vector for fresh clones; the design choice prioritizes
single-source-of-truth over preserving the bash classifier.

**Pre-backwards-compat note.** Per
`feedback_no_premature_backcompat`, this phase is a clean cut: the
old prose classifier is removed entirely, not preserved alongside
the new path.

### Acceptance Criteria

- [ ] `skills/plans/SKILL.md`'s `## Mode: Rebuild` section invokes
  `python3 -m zskills_monitor.collect` (verified by `grep -nE
  'zskills_monitor\.collect|collect_snapshot' skills/plans/SKILL.md`
  returning at least one match) and uses the canonical PYTHONPATH
  prefix `PYTHONPATH=.*skills/zskills-dashboard/scripts` (verified
  by `grep -nE 'PYTHONPATH.*skills/zskills-dashboard/scripts'
  skills/plans/SKILL.md` returning at least one match).
- [ ] Section mapping uses Phase 4's `category`/`meta_plan` fields:
  `grep -nE '"category"\s*:\s*"(canary|issue_tracker|reference|executable)"|"meta_plan"\s*:\s*true'
  skills/plans/SKILL.md` returns at least one match (the prose
  references the field names so the implementer knows what to
  consume).
- [ ] The old prose classifier rules are removed: `grep -nE
  'classify as \*\*Ready\*\*|classify every \`\.md\`'
  skills/plans/SKILL.md` returns no matches (or only matches
  inside the new wrapper prose, not the old algorithm).
- [ ] `diff -rq skills/plans/ .claude/skills/plans/` returns 0.
- [ ] `tests/test_plans_rebuild_uses_collect.sh` exits 0 and is
  registered in `tests/run-all.sh`. The test verifies that the
  plan-set in the regenerated `plans/PLAN_INDEX.md` matches the
  plan-set in `python3 -m zskills_monitor.collect`'s output AND
  that section assignment matches the Phase 4 categorization rules
  (canary plans land in Canaries section, etc.).
- [ ] Smoke: invoking `/plans rebuild` regenerates
  `plans/PLAN_INDEX.md` with a fresh "Last rebuilt:" timestamp and
  no Python tracebacks.
- [ ] User-visible output of `/plans bare`, `/plans next`, and
  `/plans details` is unchanged in shape (manual spot-check
  documented in the phase report).
- [ ] Python-missing failure is loud: with `python3` removed from
  PATH (via a wrapper or `env -i PATH=/`), `/plans rebuild` reports
  the error and exits non-zero (no silent fallback).

### Dependencies

- Phase 4 (`collect_snapshot`, `slug_of`, `category`/`meta_plan`
  fields, fixture parity tests must exist and pass).
- `skills/plans/SKILL.md` source (Phase 2 already trimmed the retired
  modes; this phase rewrites Rebuild/Next/Details bodies).
- `scripts/mirror-skill.sh` (Tier-2 mirror tool).
- Python 3.9+ in user's environment (a precondition; missing →
  clean exit non-zero with diagnostic, no bash fallback).
- No dependency on Phases 5–8 (the dashboard server is not invoked
  by `/plans rebuild`).

## Drift Log

Structural comparison: this plan was authored 2026-04-18 and refreshed in PR #70 (2026-04-27) before any phase was executed. No completed phases — all 9 phases reviewed as remaining in the 2026-04-28 `/refine-plan` round 1 pass. Drift sources absorbed:

| Source | Landed | Drift impact | Disposition |
|--------|--------|--------------|-------------|
| `scripts/port.sh` → `skills/update-zskills/scripts/port.sh` | PR #97 (2026-04-28) | Phase 5/8 referenced old path | Updated to `$MAIN_ROOT/.claude/skills/update-zskills/scripts/port.sh` |
| `scripts/sanitize-pipeline-id.sh` → `skills/create-worktree/scripts/sanitize-pipeline-id.sh` | PR #97 | Phase 1/3/8 referenced old path | Updated to canonical post-Phase-B form |
| `scripts/briefing.py` → `skills/briefing/scripts/briefing.py` | PR #96 | Phase 4's Python `from scripts.briefing` import was broken | Switched to `importlib.util.spec_from_file_location` against the new path |
| `rm -rf .claude/skills/X && cp -r` recipe | hook-blocked since PR #88 | Phase 8's mirror recipe would hit a hook block on first invocation | All 5 mirror recipes use `bash scripts/mirror-skill.sh <name>` |
| `dev_server.port_script` removed; `dev_server.default_port` added | PR #97 + #99 | Phase 5 HTTP server port resolution referenced old field | Phase 5 port-resolution chain rewritten to consult `default_port` first |

Substantive design changes in round 1 (verifier-flagged + DA-flagged):

| Change | Phases | Why |
|--------|--------|-----|
| Python module relocated to `skills/zskills-dashboard/scripts/zskills_monitor/` (was `scripts/zskills_monitor/`) | 4-9 | DA-4: flat `scripts/` violates post-Phase-B norm (Tier-1 lives in skills/<owner>/scripts/) |
| `PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts"` prefix added to all `python3 -m zskills_monitor.*` invocations | 4-9 | DA-5: module discovery would fail without it |
| Phase 4 `plans[]` JSON schema gained `category`, `meta_plan`, `sub_plans` fields | 4, 9 | F-12: Phase 9 couldn't reproduce the 6-section PLAN_INDEX without categorization rules |
| Cross-process `flock` for `monitor-state.json` writes (server + CLI) | shared schemas | DA-6: read-modify-write race between Phase 5 server and Phase 1/3 CLI |
| Phase 8 process-identity check now compares cwd in addition to command name | 8 | F-11: prevents falsely killing a different worktree's monitor server |
| `parent:` marker schema documented inline in Phase 1 + new WI to update `docs/tracking/TRACKING_NAMING.md` | 1 | F-10: TRACKING_NAMING.md was cited as authority but had zero `parent:` references |

## Plan Review

**Refinement process:** `/refine-plan` with 1 round of adversarial review (reviewer + devil's advocate, with user-supplied scope/focus directive citing post-PR-#100 SCRIPTS_INTO_SKILLS landing).

**Convergence:** Converged at round 1. 30 findings (15 reviewer + 15 DA), 25 Fixed, 5 Justified-not-fixed (all with explicit reasoning):
- DA-7: Python precondition is intentional design per `feedback_no_premature_backcompat`
- DA-9: Phase 5 split would renumber phases — out of round-1 surgical scope; logged for follow-up
- DA-11: no anchor; implementer naturally enumerates fixture paths
- DA-12: flag controls auto-invoke not user-typed `/`
- DA-14: per-process `gh` cache acceptable; documented

**Verify-before-fix outcomes:** Every empirical finding had its `Verification:` line independently reproduced before fixes were applied. Notable:
- F-10 (`parent:` marker schema): TRACKING_NAMING.md cited as authority but `grep parent: docs/tracking/TRACKING_NAMING.md` returned ZERO matches. Field is attested only in `skills/fix-issues/SKILL.md:346,924`. Refiner Verified the false attribution and added a documentation WI rather than treating the citation as authoritative.
- DA-1 (mirror recipe hook block): refiner reproduced the block by reading `block-unsafe-generic.sh:220`, confirmed Phase 8's recipe would be blocked, applied the `mirror-skill.sh` substitution.

**Remaining concerns:** None blocking execution.

### Round History

| Round | Reviewer Findings | DA Findings | Substantive | Resolved | Outcome |
|-------|-------------------|-------------|-------------|----------|---------|
| 1     | 15                | 15          | 30          | 25 Fixed, 5 Justified-with-reason | Converged |
