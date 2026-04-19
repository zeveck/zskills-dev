---
title: Zskills Monitor Dashboard
created: 2026-04-18
status: active
---

# Plan: Zskills Monitor Dashboard

## Overview

Stand up a local web dashboard that gives a "live as possible" view of the
zskills repo — plans, issues, worktrees, branches, and recent tracking
activity — and closes the loop by letting the user drag plans and issues
between prioritized queue columns. A new `/zskills-monitor` skill launches
the server as a detached background subprocess (PID file at
`.zskills/monitor-server.pid`), and a new `/work-on-plans` skill consumes
the prioritized ready queue and dispatches `/run-plan <plan> auto` per
entry — mirroring how `/fix-issues` batch-executes bug fixes.

The server is Python stdlib only (no new dependencies) and uses
`http.server.ThreadingHTTPServer`. The frontend is a vanilla ES-module
HTML page (no framework, no build step) that polls `GET /api/state`
every 2 seconds. All queue state — which plans are in `drafted` /
`reviewed` / `ready` columns, and in what order — lives exclusively in
`.zskills/monitor-state.json`. **The server never mutates plan files.**
Default column assignment for plans not yet in the state file is inferred
from plan frontmatter `status:` at read time only; no write-back to plan
frontmatter ever occurs.

This plan also retires the `work`, `stop`, and `next-run` modes of
`/plans`. Going forward `/plans` keeps only `bare`, `rebuild`, `next`,
`details` (read-only index maintenance). All batch plan execution moves
to the new `/work-on-plans` skill, which takes its input from the
monitor-owned ready queue. The migration touches `skills/plans/SKILL.md`
(argument-hint + mode summary), `README.md` (skill catalog), and
`CHANGELOG.md` (migration note).

Scope boundaries: no new package dependencies (stdlib Python + native
browser APIs only); no plan-file mutation from the server; no
`kill -9` / `killall` / `pkill` on the server process — graceful SIGTERM
only, with `lsof -i :<port>` documented as the fallback when the PID
file is stale. The UI ships in two phases (read-only dashboard first,
interactive queue + drag-and-drop second) so the read-only surface can
be validated before drag-and-drop lands.

## Shared Schemas

Three data shapes are referenced by multiple phases. They are defined
once here so Phases 1, 2, 4, and 6A all anchor to the same canonical
spec.

### `.zskills/monitor-state.json` (written by Phase 2, read by Phases 1/4/6A)

```json
{
  "version": "1.0",
  "plans": {
    "drafted":  ["slug-a", "slug-b"],
    "reviewed": ["slug-c"],
    "ready":    ["slug-d", "slug-e"]
  },
  "issues": {
    "triage": [101, 102],
    "ready":  [103]
  },
  "updated_at": "2026-04-18T14:30:00-04:00"
}
```

- `version` is hardcoded `"1.0"` for now. Consumers tolerate but ignore
  unknown top-level keys (forward-compat).
- Arrays preserve user-visible order exactly (first element = topmost
  in column).
- `updated_at` is set server-side on every successful POST.

### Default column inference — source of truth

Plans not yet in `monitor-state.json` are placed via this rule. (No
existing plan uses `status: draft`; real values seen in `plans/*.md`
are `active`, `complete`, `conflict`, `landed`, `pr-failed`,
`pr-ready`.)

| Frontmatter `status:` | Progress state | Column |
|-----------------------|----------------|--------|
| absent or `active` | no phases done yet | `drafted` |
| `active` | ≥1 phase done | `reviewed` |
| `complete`, `landed`, `pr-ready` | — | hidden (not shown in any column) |
| `conflict`, `pr-failed` | — | `reviewed` (needs attention) |
| anything else | — | `drafted` |

Issues not in the state file default to column `triage`.

### Landing-mode hint regex — source of truth

The existing format in every real plan is the blockquote line

```
> **Landing mode: PR** -- This plan targets PR-based landing. All phases
```

(note the **asterisks**, the **space** between "Landing" and "mode",
and value case — `PR`, `direct`, `cherry-pick`). The regex that
matches the real format is:

```python
# case-insensitive; captures the MODE token; tolerates ** wrappers
LANDING_MODE_RE = re.compile(
    r"^\s*>\s*\*{0,2}Landing\s+mode:\s*([A-Za-z_-]+)\s*\*{0,2}",
    re.IGNORECASE | re.MULTILINE,
)
```

Captured value is lowercased before use. Verified to match at least 10
existing plan files (`CHUNKED_CRON_CANARY.md`, `PARALLEL_CANARYA.md`,
`FIX_WORKTREE_POISONED_BRANCH.md`, `CANARY_FAILURE_INJECTION.md`,
`REBASE_CONFLICT_CANARY.md`, `UNIFY_TRACKING_NAMES.md`, etc.).

Note: `/run-plan` itself does NOT currently parse the plan-body hint
(it reads only `$ARGUMENTS` and `.claude/zskills-config.json`
`execution.landing`); the monitor's display of `landing_mode` is
therefore informational only for now. Phase 6A does not pass a
landing-mode flag; `/run-plan` continues to resolve from its own rules.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Data aggregation library | ⬚ | | |
| 2 — HTTP server | ⬚ | | |
| 3 — Read-only dashboard UI | ⬚ | | |
| 4 — Interactive queue + write-back | ⬚ | | |
| 5 — `/zskills-monitor` skill | ⬚ | | |
| 6 — `/work-on-plans` skill + remove `/plans work` | ⬚ | | |

---

## Phase 1 — Data aggregation library

### Goal

Create a pure-Python, stdlib-only module at `scripts/zskills_monitor/`
that aggregates every data source the dashboard will render into **one
JSON document** via a single public entry point `collect_snapshot()`.
Pure functions with file paths / git output as inputs, dict as output.
Unit-testable without a running server.

### Work Items

- [ ] Create package directory `scripts/zskills_monitor/` with
  `__init__.py` (empty) and `collect.py`.
- [ ] Implement `parse_plan(path: Path) -> dict` — a new plan-markdown
  parser (not a reuse of `briefing.scan_plans`, which returns a
  different field set). Extracts frontmatter, Overview blurb,
  Landing-mode hint (per Shared Schemas regex), phase-heading list,
  and progress-tracker table with status-glyph → status mapping.
  `scripts/briefing.py:scan_plans` is a reference only for the
  frontmatter-delimiter idiom; the parser is otherwise new code.
- [ ] Implement report parsing: `reports/plan-<slug>.md` → per-phase
  structured metadata. See "Report parsing rules" below.
- [ ] Implement tracking-marker scan: walk BOTH the flat top-level of
  `.zskills/tracking/` AND one-level-deep pipeline-id subdirs (the
  current on-disk layout is mixed — 20+ flat `fulfilled.*` files
  coexist with subdirs). Parse
  `requires.*` / `fulfilled.*` / `step.*`; produce a time-ordered
  activity list. Flat-file records are tagged `location: "legacy"`
  in the activity record so the UI can distinguish them if
  needed.
- [ ] Implement worktree listing via `git worktree list --porcelain` and
  `.landed` marker reads (reuse logic from `scripts/briefing.py`:
  `parse_worktree_list`, `parse_landed`, `classify_worktrees`).
- [ ] Implement branch listing via
  `git for-each-ref refs/heads/ --format='<fmt>'`.
- [ ] Implement GitHub issue listing via
  `gh issue list --state open --limit 500 --json number,title,labels,createdAt,body`
  with a 60-second in-memory cache (module-level dict).
- [ ] Implement state-file merge: read `.zskills/monitor-state.json`
  (canonical schema — see Shared Schemas) and annotate each plan /
  issue record with `queue: {"column": <str>, "index": <int>}`. If
  the state file is missing, treat as empty queues. If the file is
  unparseable (`json.JSONDecodeError`), append to `errors[]` with
  `source: ".zskills/monitor-state.json"`, treat as empty queues,
  do NOT raise. Fallback default-column inference uses the table in
  Shared Schemas (never `status: draft`, which no plan uses).
- [ ] Implement `collect_snapshot(repo_root: Path) -> dict` returning
  the stable top-level JSON shape. Accepts `Path` or `str`; coerces
  to `Path(repo_root)` internally.
- [ ] CLI entry point: `python3 -m zskills_monitor.collect [--fixture <path>]`
  prints the JSON snapshot to stdout for shell-test consumption.
- [ ] Unit test: `tests/test_zskills_monitor_collect.sh` — invokes the
  CLI against fixture directories under `tests/fixtures/monitor/*`
  (a tiny plan, a tiny report, a tiny tracking tree) and asserts JSON
  keys and types. Route output to `$TEST_OUT/.test-results.txt` per
  CLAUDE.md (`TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"`),
  never pipe.

### Design & Constraints

**Module layout:**

```
scripts/zskills_monitor/
├── __init__.py
├── collect.py          # this phase
├── server.py           # Phase 2
└── static/
    ├── index.html      # Phase 3
    ├── app.css         # Phase 3
    └── app.js          # Phases 3 + 4
```

**Stdlib only.** Imports allowed: `json`, `subprocess`, `re`, `pathlib`,
`os`, `sys`, `time`, `datetime`, `argparse`, `typing`. **Forbidden:**
`yaml`, `pyyaml`, `requests`, any pip install, any Node tooling. Regex
line-parse the YAML frontmatter the same way `scripts/briefing.py`
already does (see `scan_plans` lines 557–577: open/close `---` delim
tracking + `^(\w+):\s*(.+)` key/value regex).

**JSON shape — `collect_snapshot()` return value, verbatim:**

```json
{
  "version": "1.0",
  "updated_at": "2026-04-18T14:30:00-04:00",
  "repo_root": "/workspaces/zskills",
  "plans": [
    {
      "slug": "zskills-monitor-plan",
      "file": "plans/ZSKILLS_MONITOR_PLAN.md",
      "title": "Zskills Monitor Dashboard",
      "status": "active",
      "created": "2026-04-18",
      "issue": null,
      "landing_mode": "cherry-pick",
      "blurb": "Stand up a local web dashboard ...",
      "phase_count": 6,
      "phases_done": 0,
      "phases": [
        {"n": 1, "name": "Data aggregation library",
         "status": "todo", "commit": null, "notes": ""}
      ],
      "has_report": false,
      "report_path": null,
      "queue": {"column": "reviewed", "index": 2}
    }
  ],
  "issues": [
    {"number": 42, "title": "...", "labels": ["bug"],
     "created_at": "2026-04-17T...", "queue": {"column": "triage", "index": 0}}
  ],
  "worktrees": [
    {"path": "/workspaces/zskills/worktrees/foo",
     "branch": "feat/foo", "category": "named",
     "landed": {"status": "full", "date": "..."} ,
     "ahead": 0, "behind": 0, "age_seconds": 3600}
  ],
  "branches": [
    {"name": "feat/foo", "last_commit_at": "2026-04-18T...",
     "last_commit_subject": "...", "upstream": "dev/feat/foo"}
  ],
  "activity": [
    {"timestamp": "2026-04-18T14:29:00-04:00",
     "pipeline": "run-plan.zskills-monitor-plan",
     "kind": "fulfilled", "skill": "run-plan",
     "id": "zskills-monitor-plan",
     "status": "complete", "output": "..."}
  ],
  "queues": { /* same shape as Shared Schemas monitor-state.json: plans + issues keys */ },
  "state_file_path": ".zskills/monitor-state.json",
  "errors": [
    {"source": "gh issue list", "message": "gh not authenticated"}
  ]
}
```

Top-level keys are stable: `version`, `updated_at`, `repo_root`,
`plans`, `issues`, `worktrees`, `branches`, `activity`, `queues`,
`state_file_path`, `errors`. Downstream consumers (Phase 3 UI, Phase 4
write-back, Phase 6 `/work-on-plans`) depend on this exact shape.

**Plan parsing rules:**

- Slug = lowercased basename without extension, with `_` → `-` and
  stripped of non-`[a-z0-9-]`. Example: `ZSKILLS_MONITOR_PLAN.md` →
  `zskills-monitor-plan`. Plan → slug is **lossy**; reverse mapping
  for `/work-on-plans` is deferred to Phase 6A (which resolves slug
  back to the original `plans/<FILE>.md` path by scanning the plans
  directory once).
- Blurb = first non-empty paragraph of `## Overview` (everything from
  `## Overview` up to the next blank line after the first non-blank
  content line). Trim to 240 chars for the dashboard.
- `landing_mode` resolution order: (1) Landing-mode blockquote in the
  plan if present — use the canonical regex from Shared Schemas:
  `r"^\s*>\s*\*{0,2}Landing\s+mode:\s*([A-Za-z_-]+)\s*\*{0,2}"` with
  `re.IGNORECASE | re.MULTILINE`, lowercased on capture; else (2)
  `.claude/zskills-config.json` `execution.landing`; else (3)
  `"cherry-pick"`.
- If `.claude/zskills-config.json` is missing or `json.JSONDecodeError`:
  fall through to `"cherry-pick"` and append to `errors[]` with
  `source: ".claude/zskills-config.json"`. Do NOT raise.
- Phase headings: `^##\s+Phase\s+(\d+)\s*[—-]\s*(.+)$`.
- Progress tracker table: locate `^\|\s*Phase\s*\|`, parse rows by
  `|`-splitting; status glyph map: `⬚`=`todo`, `⏳`/`⚙️`=`in-progress`,
  `✅`=`done`, `🔴`=`blocked`.
- `phases_done` = count of progress-tracker rows with status `done`.

**Report parsing rules (`parse_report(slug: str) -> dict | None`):**

Reports live at `reports/plan-<slug>.md`. If absent, return `None` and
set plan's `has_report=false`. If present, parse section-by-section:

- Section boundary: `^## Phase\s*[—-]\s*(\d+[a-z]?)\s+(.+)$` — group 1
  is the phase token (real reports use `1`, `4`, `5a`, `5b`, `5c` —
  verified by `grep '^## Phase' reports/plan-*.md`); group 2 is the
  descriptive name. Everything up to the next `^## ` is that phase's
  block. If a heading has no leading number (rare), fall back to
  `^## Phase\s*[—-]\s*(.+)$` and leave `phase_token: null`.
- Per-phase fields (all optional, missing → `null`):
  - `^\*\*Status:\*\*\s*(.+)$` → `status`
  - `^\*\*Worktree:\*\*\s*(.+)$` → `worktree`
  - `^\*\*Branch:\*\*\s*(.+)$` → `branch`
  - `^\*\*Commits?:\*\*\s*(.+)$` → `commits` (comma-split to list)
- Return shape:
  ```python
  {"path": "reports/plan-<slug>.md",
   "markdown": "<full file text>",
   "phases": [
     {"phase_token": "5c", "name": "Infrastructure ...",
      "status": "Completed (verified)",
      "worktree": "/tmp/...", "branch": "feat/...",
      "commits": ["1839bb8"]},
     ...
   ]}
  ```
- Phase 3 reconciliation keys plan-progress-tracker row `n` against
  `int(phase_token.rstrip('abcdefghij'))` so a sub-letter like `5c`
  maps to plan phase 5; if `phase_token` is `null`, fall through to
  name-based matching.
- The `markdown` field is included so the Phase 3 modal can render the
  raw text; the `phases[]` structured view is what the dashboard uses
  to reconcile report status against plan progress tracker.

**Tracking marker scan:**

Walk TWO locations:
1. Top-level flat files in `.zskills/tracking/*` (legacy layout —
   `ls .zskills/tracking/` today shows 20+ flat `fulfilled.run-plan.*`
   files alongside pipeline-id subdirs; ignoring them silently would
   make the dashboard's Activity panel appear empty on day 1).
2. One level deep: `.zskills/tracking/*/` per-pipeline subdirs (the
   current spec per `docs/tracking/TRACKING_NAMING.md`).

For each file whose basename matches
`^(requires|fulfilled|step)\.(.+)$`, parse key/value lines
(`^(\w+):\s*(.+)$`) and emit an activity record. Flat-file records
carry `location: "legacy"`; subdir records carry
`location: "pipeline"` plus `pipeline: <subdir-name>`.

Sort descending by `datetime.fromisoformat(date).astimezone(timezone.utc)`
(parse-then-sort — never raw string sort). Today every marker in the
repo uses `-04:00`, but cron workers / remote triggers / non-ET
contributors can write other offsets; lexicographic string sort on
raw `date:` produces wrong order as soon as offsets diverge
(`+` < `-` in ASCII, so `+00:00` sorts before `-04:00` even when the
ET marker is chronologically later). Keep the most recent 200 in
memory; UI trims to 20.

**GitHub issues cache:**

```python
_ISSUE_CACHE = {"fetched_at": 0.0, "data": None}
_ISSUE_CACHE_TTL = 60.0  # seconds

def list_issues():
    now = time.time()
    if _ISSUE_CACHE["data"] is not None and \
       now - _ISSUE_CACHE["fetched_at"] < _ISSUE_CACHE_TTL:
        return _ISSUE_CACHE["data"]
    result = subprocess.run(
        ["gh", "issue", "list", "--state", "open", "--limit", "500",
         "--json", "number,title,labels,createdAt,body"],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode != 0:
        # Record in errors[], return last cached value or []
        return _ISSUE_CACHE["data"] or []
    data = json.loads(result.stdout)
    _ISSUE_CACHE.update({"fetched_at": now, "data": data})
    return data
```

**Never use `|| true` or `2>/dev/null`.** If `gh` fails, append to the
returned snapshot's `errors[]` list with `source` and `message`. Do
not swallow silently.

**Reuse from `scripts/briefing.py` (do not reimplement):**
`parse_worktree_list`, `parse_for_each_ref`, `parse_landed`,
`classify_worktrees`, `find_repo_root`. Import via
`sys.path.insert(0, str(Path(__file__).parent.parent))` then
`from briefing import ...`.

**NOT reused:** `briefing.scan_plans` returns only
`{file, title, issue, status, created, all_phases_done, has_report,
phase_count}` — none of the new fields (slug, blurb, phases[] with
names, progress tracker detail, landing_mode) are in its output.
Phase 1 writes a new `parse_plan()` from scratch, using `scan_plans`
as a reference for the frontmatter-delimiter idiom only.

**Performance target:**

`collect_snapshot()` must complete in under 500ms on a repo with ~50
plans and a warm `gh` cache (no subprocess call). Unverified targets
are acceptance-blocking: add a fixture `tests/fixtures/monitor/
thirty-plans/` with synthetic plan files; acceptance criterion
`time python3 -m zskills_monitor.collect --fixture
tests/fixtures/monitor/thirty-plans` real time < 0.5s. If exceeded,
add per-file `(path, mtime)` memoization to `parse_plan`.

**CLI shape:**

```
python3 -m zskills_monitor.collect                # prints JSON to stdout
python3 -m zskills_monitor.collect --fixture DIR  # use DIR as repo_root
```

### Acceptance Criteria

- [ ] `python3 -m zskills_monitor.collect --fixture
  tests/fixtures/monitor/minimal | jq 'keys'` exits 0 and prints an
  array containing exactly the top-level keys listed in Design &
  Constraints (fixture-based; no cwd sensitivity).
- [ ] `python3 -m zskills_monitor.collect --fixture
  tests/fixtures/monitor/minimal | jq -e '.plans[0].slug != null and
  .plans[0].phase_count != null'` exits 0.
- [ ] **Queue annotation** (explicit): given a fixture with
  `.zskills/monitor-state.json` containing
  `{"plans":{"ready":["zskills-monitor-plan"]}}`,
  `collect_snapshot(<fixture>)` returns `plans[0].queue ==
  {"column":"ready","index":0}`.
- [ ] **State-file absent**: with no `.zskills/monitor-state.json`,
  snapshot returns without error; every plan's `queue.column`
  follows the default inference table in Shared Schemas.
- [ ] **State-file corrupt**: with a state file containing invalid
  JSON, snapshot returns without raising; `errors[]` contains an
  entry with `source: ".zskills/monitor-state.json"`.
- [ ] **Landing-mode**: on a fixture plan whose body contains
  `> **Landing mode: PR** --`, `plans[0].landing_mode == "pr"`.
- [ ] **Legacy tracking markers**: a flat
  `.zskills/tracking/fulfilled.run-plan.canary-happy` file is
  surfaced in `activity[]` with `location == "legacy"`.
- [ ] `grep -E '^import\s+(yaml|requests)'
  scripts/zskills_monitor/collect.py` returns no matches (stdlib only).
- [ ] Missing `gh` or `gh issue list` failure does NOT raise — the
  snapshot returns with `issues: []` and `errors:
  [{"source": "gh issue list", ...}]`.
- [ ] Calling `collect_snapshot()` twice within 60s hits the issue
  cache (verified by mocking `subprocess.run` or inspecting
  `_ISSUE_CACHE`).
- [ ] Performance: `time python3 -m zskills_monitor.collect --fixture
  tests/fixtures/monitor/thirty-plans` shows real<0.5s after the
  `gh` cache is warm.

### Dependencies

- External: Python 3.9+, `git` CLI, `gh` CLI (optional — snapshot
  degrades gracefully).
- Internal: `scripts/briefing.py` (imported for worktree / landed
  helpers — treat as a stable API within this repo).
- Plan/report file layout: `plans/*.md`, `reports/plan-<slug>.md`.
- Tracking marker layout per `docs/tracking/TRACKING_NAMING.md`.

---

## Phase 2 — HTTP server

### Goal

Expose Phase 1's `collect_snapshot()` over a small localhost-only HTTP
API, plus static file serving for the Phase 3 UI, with a detachable
background lifecycle (PID file + graceful SIGTERM).

### Work Items

- [ ] Create `scripts/zskills_monitor/server.py` using
  `http.server.ThreadingHTTPServer` and a `BaseHTTPRequestHandler`
  subclass.
- [ ] Implement routing per the route table below, with input
  validation: `<slug>` must match `^[a-z0-9-]+$`, `<N>` must match
  `^[0-9]+$`. Mismatch → HTTP 400 before any subprocess dispatch.
- [ ] Implement `GET /api/state` → `collect_snapshot()` JSON.
- [ ] Implement `GET /api/plan/<slug>` → single-plan detail (all phases,
  work items, report if present, tracking events for this slug).
  Look up `<slug>` in an in-memory slug → file-path dict built from
  `plans/*.md` glob; NEVER `os.path.join(plans_dir, slug + ".md")`
  (defense-in-depth against traversal even though regex already
  rejects `..`).
- [ ] Implement `GET /api/issue/<N>` → shell out to
  `gh issue view <N> --json number,title,body,labels,comments,state`
  with `timeout=15`; on timeout return HTTP 504 with JSON
  `{"error":"gh issue view timed out"}`.
- [ ] Implement `POST /api/queue` → enforce CSRF / origin check, body
  size limit, strict JSON shape validation, atomic write to
  `.zskills/monitor-state.json`.
- [ ] Implement `GET /api/health` → `{"status": "ok", "uptime": <secs>,
  "pid": <int>, "port": <int>}`.
- [ ] Static file serving for `GET /`, `GET /app.js`, `GET /app.css`
  from `scripts/zskills_monitor/static/`.
- [ ] Bind to `127.0.0.1` only. Port resolution: shell out to
  `bash scripts/port.sh` at startup; `DEV_PORT` env var overrides.
  Wrap the `ThreadingHTTPServer(...)` constructor in
  `try/except OSError` to print the friendly port-busy message on
  `EADDRINUSE` instead of a stack trace.
- [ ] PID file write to `.zskills/monitor-server.pid` on startup AFTER
  successful bind; file format is JSON `{"pid": <int>, "port": <int>,
  "started_at": "<ISO>"}` so `stop` / `status` read the port
  without re-running `port.sh`.
- [ ] SIGTERM handler: call `server.shutdown()`, remove PID file, exit 0.
- [ ] Extend `.gitignore` with `.zskills/monitor-server.pid`,
  `.zskills/monitor-server.log`, and `.zskills/monitor-state.json`
  (not currently ignored — verified: `.gitignore` covers only
  `.zskills/tracking/` and `.zskills-tracked`). Add to the same
  commit as this phase.
- [ ] Test: `tests/test_zskills_monitor_server.sh` — starts server in
  background, `curl` each route, checks response shapes, stops via
  SIGTERM, verifies PID file removed. Route output to
  `$TEST_OUT/.test-results.txt` per CLAUDE.md (`TEST_OUT="/tmp/
  zskills-tests/$(basename "$(pwd)")"`), never pipe.
- [ ] Register both Phase 1 and Phase 2 test scripts in
  `tests/run-all.sh` as new `run_suite` calls so `bash
  tests/run-all.sh` exercises them on every run.

### Design & Constraints

**Route table — canonical:**

| Method | Path | Response | Notes |
|--------|------|----------|-------|
| GET | `/` | `static/index.html` (text/html) | |
| GET | `/app.js` | `static/app.js` (application/javascript) | ES module |
| GET | `/app.css` | `static/app.css` (text/css) | |
| GET | `/api/health` | `{"status":"ok","uptime":<secs>,"pid":<int>}` | |
| GET | `/api/state` | Phase 1 snapshot JSON | `Cache-Control: no-store` |
| GET | `/api/plan/<slug>` | Plan detail JSON (see below) | 404 if slug unknown |
| GET | `/api/issue/<N>` | `gh issue view` JSON | 404 if gh returns non-zero |
| POST | `/api/queue` | `{"ok":true,"updated_at":"..."}` | See validation below |

**Plan detail shape (`GET /api/plan/<slug>`):**

```json
{
  "slug": "...",
  "file": "plans/...",
  "title": "...",
  "status": "active",
  "landing_mode": "cherry-pick",
  "blurb": "...",
  "overview_full": "full Overview section markdown",
  "phases": [
    {"n": 1, "name": "...", "status": "todo", "commit": null, "notes": "",
     "goal": "...", "work_items": [
       {"text": "Create the module", "checked": false}
     ],
     "acceptance_criteria": [...],
     "design_constraints_md": "raw markdown",
     "dependencies_md": "raw markdown"}
  ],
  "report": {"path": "reports/plan-<slug>.md", "markdown": "..."} ,
  "activity": [ /* same shape as top-level activity[] but filtered */ ]
}
```

**POST /api/queue request body (strict shape — reject unknown keys):**

The canonical state schema is defined in Shared Schemas. The POST body
matches it exactly (same top-level `plans` / `issues` keys; server
fills `version` and `updated_at` on write — client-supplied values are
ignored).

**Request preconditions (checked BEFORE reading body):**
- `Content-Length` header present and ≤ 65536 (64 KiB). Missing or
  over-limit → HTTP 413 `{"error":"body too large"}`. The state file
  is under 10 KiB at any realistic repo scale.
- `Content-Type: application/json` (exact, case-insensitive match on
  the media type; parameters allowed). Mismatch → HTTP 415.
- `Origin` header must equal `http://127.0.0.1:<PORT>` where `<PORT>`
  is the port the server bound to. Missing or mismatched →
  HTTP 403 `{"error":"origin not allowed"}`. This defeats drive-by
  CSRF from malicious pages that use
  `fetch('http://127.0.0.1:<port>/api/queue', {mode:'no-cors', ...})`:
  browsers send the real `Origin` header and the check rejects.

**Body-shape validation rules (after reading body):**
- Top-level keys must be exactly `{"plans", "issues"}` — reject others.
- `plans` columns must be exactly `{"drafted","reviewed","ready"}`.
- `issues` columns must be exactly `{"triage","ready"}`.
- List items for `plans` are strings matching `^[a-z0-9-]+$`; for
  `issues` are ints (not strings).
- No duplicate entries within a column; no entry appears in more than
  one column of the same panel.
- On any violation: HTTP 400 with `{"error":"...","detail":"..."}`.
- If the existing state file is unparseable (`JSONDecodeError` on read
  during the merge step), the server treats it as empty and
  overwrites via the atomic tmp+replace path; no data loss risk because
  the client sends the full desired state.

**Atomic write helper (thread-safe — `ThreadingHTTPServer` serves each
POST on its own handler thread):**

```python
import json, os, threading
from pathlib import Path

STATE_PATH = Path(".zskills/monitor-state.json")
_STATE_LOCK = threading.Lock()  # serializes concurrent POSTs

def write_state_atomic(new_state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    # Per-writer unique tmp name: two threads opening the same fixed tmp
    # path with mode "w" would truncate each other's in-flight writes
    # (Python docs: "'w' open for writing, truncating the file first"),
    # producing a 0-byte window that os.replace would then atomically
    # move into production. Per-thread tmp + module lock eliminates
    # both the truncation race and non-deterministic last-write-wins.
    tmp = STATE_PATH.parent / (
        f"{STATE_PATH.name}.tmp.{os.getpid()}.{threading.get_ident()}"
    )
    with _STATE_LOCK:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(new_state, f, indent=2, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, STATE_PATH)  # atomic on POSIX (same-FS rename)
```

`os.replace()` is atomic on POSIX for same-filesystem renames
(https://docs.python.org/3/library/os.html#os.replace). The per-thread
tmp name ensures a second writer never opens the same inode as an
in-flight first writer; the `_STATE_LOCK` serializes the replace so
last-write-wins is deterministic.

**Signal handling skeleton:**

```python
import errno, json, signal, subprocess, sys, os, time
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer
from pathlib import Path

_SERVER = None
_PID_PATH = Path(".zskills/monitor-server.pid")
_STARTED_AT = time.time()
_PORT = None  # set in main()

def _shutdown(signum, frame):
    if _SERVER is not None:
        _SERVER.shutdown()
    try:
        _PID_PATH.unlink()
    except FileNotFoundError:
        pass
    sys.exit(0)

def main():
    global _SERVER, _PORT
    _PORT = int(os.environ.get("DEV_PORT") or
                subprocess.check_output(["bash", "scripts/port.sh"],
                                        text=True).strip())
    try:
        _SERVER = ThreadingHTTPServer(("127.0.0.1", _PORT), MonitorHandler)
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            sys.stderr.write(
                f"Port {_PORT} is already in use. "
                f"Run 'lsof -i :{_PORT}' to find the holder; stop it "
                "manually (no kill -9), then retry /zskills-monitor start.\n"
            )
            sys.exit(2)
        raise
    _PID_PATH.parent.mkdir(parents=True, exist_ok=True)
    # JSON format so `stop`/`status` can read the bound port without
    # re-running scripts/port.sh (which is path-derived and can
    # change between start and stop if cwd or DEV_PORT differs).
    _PID_PATH.write_text(json.dumps({
        "pid": os.getpid(),
        "port": _PORT,
        "started_at": datetime.now(timezone.utc).isoformat(),
    }))
    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)
    _SERVER.serve_forever()
```

**Port-busy fallback text (printed to stderr, exit code 2):**

```
Port <N> is already in use. The monitor server cannot start.
Check what is holding the port:
    lsof -i :<N>
Stop that process manually, then retry /zskills-monitor start.
If .zskills/monitor-server.pid exists but the PID is dead, remove
the stale file and retry: rm .zskills/monitor-server.pid
```

**Rules that apply to this phase in particular:**
- **Bind to 127.0.0.1 only.** Not `0.0.0.0`. No CORS needed.
- **No `kill -9`.** The server never force-terminates itself, and the
  skill (Phase 5) never force-terminates it either.
- **No `|| true`.** `subprocess.check_output(["bash","scripts/port.sh"])`
  raises if `port.sh` fails — let it.
- **No `2>/dev/null`.** Let errors surface.
- **Atomic writes only** for the state file (tmp + `os.replace`).
- **Write PID file AFTER successful bind**, not before — binding may
  fail and we don't want a stale PID for a process that never served.

### Acceptance Criteria

- [ ] Server starts: `python3 -m zskills_monitor.server &` then
  `sleep 0.5 && curl -sf http://127.0.0.1:$(bash scripts/port.sh)/api/health |
  jq -e '.status == "ok"'` returns 0.
- [ ] PID file exists at `.zskills/monitor-server.pid` while server is
  running and contains the live PID (verified by
  `kill -0 "$(cat .zskills/monitor-server.pid)"` returning 0).
- [ ] SIGTERM causes graceful exit:
  `kill -TERM "$(cat .zskills/monitor-server.pid)"` then waiting ≤5s
  results in PID file removed and port freed.
- [ ] `curl -sf http://127.0.0.1:$PORT/api/state | jq -e '.version == "1.0"'`
  returns 0.
- [ ] `curl -sf http://127.0.0.1:$PORT/api/plan/does-not-exist -o /dev/null -w '%{http_code}'`
  prints `404`.
- [ ] Slug-validation: `curl -o /dev/null -w '%{http_code}'
  http://127.0.0.1:$PORT/api/plan/..%2F..%2Fetc` prints `400`.
- [ ] Integer-validation: `curl -o /dev/null -w '%{http_code}'
  http://127.0.0.1:$PORT/api/issue/abc` prints `400`.
- [ ] Valid POST to `/api/queue`:
  `curl -sf -X POST -H 'Content-Type: application/json'
  -H "Origin: http://127.0.0.1:$PORT" -d
  '{"plans":{"drafted":[],"reviewed":[],"ready":["foo"]},"issues":{"triage":[],"ready":[]}}'
  http://127.0.0.1:$PORT/api/queue` returns 200 and
  `.zskills/monitor-state.json` contains the new state after the call.
- [ ] CSRF: POST with no `Origin` header returns HTTP 403.
- [ ] CSRF: POST with `Origin: https://evil.example` returns HTTP 403.
- [ ] Body-size: POST with `Content-Length: 1048576` (1 MiB) returns
  HTTP 413 without reading the body.
- [ ] Wrong content-type: POST with `Content-Type: text/plain` returns
  HTTP 415.
- [ ] Invalid POST (unknown top-level key, well-formed Origin) returns
  HTTP 400.
- [ ] Port-busy: starting a second server while the first is running
  produces the friendly port-busy message on stderr and exits 2
  (no Python stack trace).
- [ ] PID-file shape: `jq -e '.pid and .port and .started_at'
  .zskills/monitor-server.pid` exits 0; `.port` matches `ss -ltn`.
- [ ] `.gitignore` covers monitor files: `git check-ignore
  .zskills/monitor-server.pid .zskills/monitor-server.log
  .zskills/monitor-state.json` exits 0 for all three.
- [ ] `tests/test_zskills_monitor_server.sh` exits 0.
- [ ] `grep -nE '2>/dev/null|\|\|\s*true' scripts/zskills_monitor/server.py`
  returns no matches.
- [ ] Server binds only to 127.0.0.1 (verified by
  `ss -ltn | grep :$PORT | grep '127.0.0.1:'`).

### Dependencies

- Phase 1's `collect_snapshot()` (direct import).
- `scripts/port.sh` (shell-out for port selection).
- `.zskills/` is writable (create dir if missing).
- `gh` CLI for issue detail route (graceful 404 if missing).

---

## Phase 3 — Read-only dashboard UI

### Goal

Single-page vanilla HTML dashboard that renders the `/api/state`
snapshot into four panels — Plans, Issues, Worktrees, Recent
Activity — with drill-down modals on plan and issue. No drag-and-drop
yet (Phase 4 adds that). Polls every 2 seconds. Matches
`PRESENTATION.html` theme.

### Work Items

- [ ] Create `scripts/zskills_monitor/static/index.html` (target per
  "File budget" in Design & Constraints below).
- [ ] Create `scripts/zskills_monitor/static/app.css` (target per
  "File budget" below).
- [ ] Create `scripts/zskills_monitor/static/app.js` (target per
  "File budget" below), loaded as `<script type="module">`.
- [ ] Implement fetch + render pipeline: setTimeout recursion (see
  skeleton below; NOT `setInterval` — acceptance greps enforce this)
  where `load()` GETs `/api/state`, diffs against last rendered state,
  and only re-renders changed panels (simple list-equality check on
  each panel's backing array). Pause on `document.hidden`, force a
  reload on `visibilitychange` → visible.
- [ ] Plans panel: card per plan, showing title, blurb, phase-progress
  ratio (e.g. `2/6 ✅`), status badge, landing-mode pill.
- [ ] Issues panel: card per open issue — number, title, labels,
  created date.
- [ ] Worktrees panel: row per worktree — path basename, branch,
  `.landed` status badge, age (relative).
- [ ] Recent Activity panel: last 20 tracking events, newest first.
- [ ] Plan detail modal: opened on double-click or Enter keypress;
  fetches `/api/plan/<slug>`; shows full Overview, phase list with
  status/commit/notes, work-item checkboxes (display-only), report
  path if present.
- [ ] Issue detail modal: double-click opens; fetches `/api/issue/<N>`;
  renders body as pre-wrapped text.
- [ ] Keyboard accessibility: every card has `tabindex="0"`, Enter
  opens modal, Esc closes, focus returns to the invoking card.
- [ ] Error banner: if `/api/state` returns non-2xx or times out, show
  a banner at the top saying "Disconnected — retrying…".

### Design & Constraints

**File budget (soft guidelines, NOT hard caps):**
- `index.html` target ≤ 250 lines
- `app.css` target ≤ 400 lines
- `app.js` target ≤ 700 lines (Phase 3 only; Phase 4 adds drag/ARIA/
  keyboard fallback that will push this toward 900)

Rationale: the feature set — 4 panels, polling with visibility gating,
error banner, 2 drill-down modals with focus trap, Tab/Enter/Esc
handling, connection-status indicator, diff-rendering, responsive
grid — is at the high end for a single vanilla ES module. Line counts
are reported in the phase report but NOT enforced as blocking
acceptance criteria. The enforced rules are: no framework, no build
step, no external script imports, no inline handlers (see below).

**CSS variables — copy verbatim from `PRESENTATION.html`:**

```css
:root {
  --bg: #0d1117;
  --surface: #161b22;
  --surface2: #1c2129;
  --border: #30363d;
  --text: #e6edf3;
  --text-dim: #8b949e;
  --accent: #58a6ff;
  --accent2: #bc8cff;
  --green: #3fb950;
  --orange: #d29922;
  --red: #f85149;
  --pink: #f778ba;
}
```

These are the exact names used at `PRESENTATION.html` lines 8–21.
Do not invent new variable names. All semantic colors (success =
`--green`, warn = `--orange`, blocked = `--red`, in-progress =
`--accent`) must use these tokens.

**DOM skeleton (verbatim — `index.html` body):**

```html
<body>
  <nav class="top">
    <span class="logo">Z Skills Monitor</span>
    <span class="spacer"></span>
    <span id="connection" class="conn-ok">connected</span>
    <span id="updated-at"></span>
  </nav>

  <main class="grid">
    <section id="panel-plans" class="panel" aria-label="Plans">
      <header><h2>Plans</h2><span class="count" id="plans-count">0</span></header>
      <!-- Phase 3: single flat list. Phase 4 replaces with 3 columns. -->
      <div id="plans-list" class="cards"></div>
    </section>

    <section id="panel-issues" class="panel" aria-label="Issues">
      <header><h2>Issues</h2><span class="count" id="issues-count">0</span></header>
      <div id="issues-list" class="cards"></div>
    </section>

    <section id="panel-worktrees" class="panel" aria-label="Worktrees">
      <header><h2>Worktrees</h2><span class="count" id="wt-count">0</span></header>
      <div id="worktrees-list" class="rows"></div>
    </section>

    <section id="panel-activity" class="panel" aria-label="Recent Activity">
      <header><h2>Recent Activity</h2></header>
      <ol id="activity-list" class="activity"></ol>
    </section>
  </main>

  <div id="modal-root" class="modal-root hidden" role="dialog" aria-modal="true"></div>

  <script type="module" src="/app.js"></script>
</body>
```

**Grid layout (in `app.css`):**

```css
.grid {
  display: grid;
  grid-template-columns: 2fr 1fr;
  grid-template-rows: auto auto;
  grid-template-areas:
    "plans     issues"
    "worktrees activity";
  gap: 16px;
  padding: 72px 16px 16px;
  max-width: 1400px;
  margin: 0 auto;
}
#panel-plans     { grid-area: plans; }
#panel-issues    { grid-area: issues; }
#panel-worktrees { grid-area: worktrees; }
#panel-activity  { grid-area: activity; }

@media (max-width: 900px) {
  .grid {
    grid-template-columns: 1fr;
    grid-template-areas: "plans" "issues" "worktrees" "activity";
  }
}
```

**`app.js` module structure:**

```js
// app.js — Phase 3 shape
const POLL_MS = 2000;
let lastSnapshot = null;
let pollTimer = null;

async function load() {
  try {
    const res = await fetch('/api/state', { cache: 'no-store' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const snap = await res.json();
    setConnected(true);
    render(snap);
    lastSnapshot = snap;
  } catch (e) {
    setConnected(false);
  } finally {
    // setTimeout recursion (NOT setInterval) — the next poll does not
    // start until the current one completes. Prevents dogpiling when
    // /api/state is slow (e.g. a cold `gh` cache with a 30s subprocess
    // timeout).
    if (!document.hidden) {
      pollTimer = setTimeout(load, POLL_MS);
    }
  }
}

function render(snap) {
  renderPlans(snap.plans);
  renderIssues(snap.issues);
  renderWorktrees(snap.worktrees);
  renderActivity(snap.activity);
  document.getElementById('updated-at').textContent = snap.updated_at;
}

// renderPlans, renderIssues, renderWorktrees, renderActivity,
// openPlanModal(slug), openIssueModal(number), closeModal()...

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeModal();
});

// Force-reload whenever the tab becomes visible again: otherwise
// external mutations (e.g. /work-on-plans modifying state while the
// tab was hidden) would be invisible until the next poll, and a user
// drag in the first 2s after focus would overwrite that mutation.
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) {
    clearTimeout(pollTimer);
    load();
  }
});

load();
```

**Card markup convention — every card:**
- `<article class="card" tabindex="0" role="button"
  data-kind="plan" data-slug="..." aria-label="Plan: <title>">`
- Enter / double-click → opens modal.
- Modal `<dialog>` is avoided (inconsistent focus handling across
  browsers) in favor of a custom div with `role="dialog"
  aria-modal="true"`; ESC handler in global keydown listener;
  focus is trapped via a simple first/last focusable element trap.

**Polling hygiene:**
- `setTimeout` recursion (not `setInterval`) — next poll only starts
  after the current one finishes. Prevents concurrent fetches when
  `/api/state` is slow (cold `gh` cache → 30s timeout).
- `cache: 'no-store'` on every fetch.
- If the page is hidden (`document.hidden`), pause polling entirely;
  on `visibilitychange` → visible, force an immediate `load()` before
  resuming. See skeleton above.

**XSS escape policy (MANDATORY):**

All user-authored content from plan files, issue bodies, worktree
paths, branch names, and tracking output is rendered via
`element.textContent` or `document.createTextNode`, NEVER via
`innerHTML`, template-string interpolation into HTML, or
`insertAdjacentHTML`.

- Acceptable: `card.textContent = plan.title`, `code.textContent =
  issue.body`, `document.createElement('div')` + append.
- Forbidden for user content: `el.innerHTML = ...`,
  ``el.innerHTML = `<p>${plan.blurb}</p>` ``,
  `document.write`, `insertAdjacentHTML`.
- Hardcoded chrome (panel headers, icons, class-only scaffolding) MAY
  use `innerHTML` for convenience, but every such site must carry the
  trailing comment `// chrome-only` on the **same line** as the
  `innerHTML =` assignment (a longer justification may appear on a
  preceding comment line; `grep` is per-line, so the marker MUST be
  on the assignment line itself).
- The modal renders plan Overview and issue body as preformatted text
  (`<pre>` with `textContent`), not as rendered markdown. Markdown
  rendering is out of scope for this plan.

This rule defeats the vector where a malicious issue body or plan
body contains `<img src=x onerror="fetch('/api/queue', {method:'POST',
...})">` and silently wipes the user's queue.

Acceptance enforcement (Phase 3 and Phase 4 both):

```bash
grep -nE '\.innerHTML\s*=' scripts/zskills_monitor/static/app.js |
  grep -vE '//\s*chrome-only'
```

Must return no lines. The `chrome-only` marker is a single token (no
space) so `grep -v 'chrome only'` is NOT used — that phrasing would
have falsely excluded a preceding-line comment while the assignment
itself had no marker.

**Rules that apply to this phase in particular:**
- No npm, no build step, no bundler. Single HTML file + 1 CSS file + 1
  ES-module JS file.
- No framework runtime (React, Vue, etc.).
- No inline event handlers (`onclick=`). Use `addEventListener`.
- Keyboard accessibility is a requirement, not a nice-to-have.
- XSS escape policy above is blocking.

### Acceptance Criteria

- [ ] `grep -c '^\s*--bg:\|^\s*--surface:\|^\s*--accent:'
  scripts/zskills_monitor/static/app.css` returns ≥ 3 (CSS vars present).
- [ ] `grep -nE 'onclick=|onload=' scripts/zskills_monitor/static/`
  returns no matches (no inline handlers).
- [ ] XSS: `grep -nE '\.innerHTML\s*=' scripts/zskills_monitor/static/
  app.js | grep -vE '//\s*chrome-only'` returns no matches.
- [ ] Polling: `grep -nE 'setInterval\s*\(' scripts/zskills_monitor/
  static/app.js` returns no matches (setTimeout recursion only).
- [ ] Manual playwright-cli test checklist documented in the phase
  report: (1) page loads at dashboard URL; (2) four panels visible;
  (3) plan card double-click opens modal with phase list;
  (4) Esc closes modal; (5) Tab reaches every card; (6) Enter on a
  focused card opens its modal; (7) killing the server shows the
  "Disconnected" banner within one poll cycle.
- [ ] `grep -nE 'import\s+.+from\s+["\x27]https?:' scripts/zskills_monitor/static/app.js`
  returns no matches (no external script imports — stdlib/native only).

### Dependencies

- Phase 2's server serving `/api/state`, `/api/plan/<slug>`,
  `/api/issue/<N>`, and static files.
- Phase 1's JSON shape stable.

---

## Phase 4 — Interactive queue + write-back

### Goal

Turn the Plans panel into three drag-and-drop columns (`Drafted`,
`Reviewed`, `Ready (priority)`) and the Issues panel into two columns
(`Triage`, `Ready`). Dropping a card changes its queue assignment;
dropping within Ready changes priority. POST the full new state to
`/api/queue`, which atomically rewrites `.zskills/monitor-state.json`.
Keyboard fallback for non-drag users.

### Work Items

- [ ] Extend `app.js` to render Plans as 3 columns, Issues as 2
  columns, using the same `data-column` / `data-slug` / `data-number`
  hooks on card elements.
- [ ] Implement HTML5 native drag: `draggable="true"`, `dragstart`,
  `dragover` (with `preventDefault`), `drop`, `dragend` handlers.
- [ ] On drop → build the new queue-state dict from current DOM order,
  POST to `/api/queue`, on success let the next poll cycle confirm
  (optimistic UI allowed but the server copy is authoritative).
- [ ] Default column inference for plans NOT in state file: use the
  table in Shared Schemas (no plan uses `status: draft` today; the
  real statuses are `active`, `complete`, `conflict`, `landed`,
  `pr-failed`, `pr-ready`). **Never write this inference back to
  plan files.**
- [ ] Default column inference for issues NOT in state file: `triage`.
- [ ] Keyboard fallback per card: four buttons `↑ ↓ ← →` —
  up/down reorder within column, left/right move to adjacent column.
  Buttons are standard `<button>` elements in tab order.
- [ ] ARIA: each column is a plain `<ul role="list">` (or bare `<ul>`
  — `role="list"` is only needed if CSS removes the default role),
  each card is `<li role="listitem">`. Do NOT use `role="listbox"` /
  `role="option"` here — the APG listbox pattern
  (https://www.w3.org/WAI/ARIA/apg/patterns/listbox/) forbids
  interactive children inside options, and each card contains four
  `<button>` controls. Column header has `id="col-ready-label"`
  referenced by `aria-labelledby` on the `<ul>`. After each successful
  move, announce via `aria-live="polite"` element (e.g. `"Moved Foo
  Plan to Ready, position 2 of 5"`).
- [ ] Verify that Phase 1's `collect_snapshot` already annotates plans
  with `queue.column` / `queue.index` (it does — see Phase 1 Work
  Items + Acceptance). No additional Phase 1 edits are needed from
  this phase; if they appear necessary, that is a Phase 1 bug to
  fix upstream.
- [ ] Manual a11y test checklist added to phase report.

### Design & Constraints

**State file shape:** see Shared Schemas (section at top of plan).
Phase 4's UI triggers the first write by POSTing to Phase 2's
`POST /api/queue` handler; the atomic write itself lives in Phase 2's
`write_state_atomic` helper. Phase 1 / Phase 6A are readers. All phases
share the single canonical schema.

**Concurrency model:** last-write-wins. Two browser tabs reordering
simultaneously will each POST a full snapshot; the second POST wins.
This is acceptable at single-user-local scale. Do **not** add locking,
ETags, or merge logic. A brief UI flicker on reconciliation (next poll)
is expected and acceptable.

**Plans panel DOM (replaces Phase 3's single list):**

```html
<section id="panel-plans" class="panel" aria-label="Plans">
  <header><h2>Plans</h2></header>
  <div class="columns">
    <div class="column" data-column="drafted">
      <h3 id="col-drafted-label">Drafted</h3>
      <ul class="dropzone" data-column="drafted" role="list"
          aria-labelledby="col-drafted-label"></ul>
    </div>
    <div class="column" data-column="reviewed">
      <h3 id="col-reviewed-label">Reviewed</h3>
      <ul class="dropzone" data-column="reviewed" role="list"
          aria-labelledby="col-reviewed-label"></ul>
    </div>
    <div class="column" data-column="ready">
      <h3 id="col-ready-label">Ready (priority)</h3>
      <ul class="dropzone" data-column="ready" role="list"
          aria-labelledby="col-ready-label"></ul>
    </div>
  </div>
  <!-- Each card is an <li role="listitem"> with the four move buttons
       as children; no role="option" because the APG listbox pattern
       forbids interactive children inside options. -->

  <div id="plans-live" aria-live="polite" class="sr-only"></div>
</section>
```

**Drag handler skeleton (`app.js` additions):**

```js
function wireDragForCard(card) {
  card.draggable = true;
  card.addEventListener('dragstart', (e) => {
    e.dataTransfer.setData('text/plain', card.dataset.slug ||
                                          card.dataset.number);
    e.dataTransfer.effectAllowed = 'move';
    card.classList.add('dragging');
  });
  card.addEventListener('dragend', () => card.classList.remove('dragging'));
}

function wireDragForZone(zone) {
  zone.addEventListener('dragenter', (e) => {
    e.preventDefault();
    zone.classList.add('drop-hover');
  });
  zone.addEventListener('dragleave', (e) => {
    // Only clear when leaving the zone itself, not a child.
    if (e.target === zone) zone.classList.remove('drop-hover');
  });
  zone.addEventListener('dragover', (e) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    // Optional: compute insertion marker based on clientY
  });
  zone.addEventListener('drop', async (e) => {
    e.preventDefault();
    zone.classList.remove('drop-hover');
    const id = e.dataTransfer.getData('text/plain');
    const card = findCardByIdentifier(id);
    if (!card) return;
    const before = computeInsertionSibling(zone, e.clientY);
    zone.insertBefore(card, before);
    const ok = await postQueue();
    if (ok) {
      announce(`Moved ${card.dataset.label || id} to `
        + `${zone.dataset.column}, position `
        + `${[...zone.children].indexOf(card) + 1} of ${zone.children.length}`);
    }
  });
}

async function postQueue() {
  const body = buildQueueStateFromDOM();
  const res = await fetch('/api/queue', {
    method: 'POST',
    // Origin header is sent automatically by the browser and checked
    // server-side (see Phase 2 CSRF rules).
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    announce('Move failed — reverting on next sync');
    return false;
  }
  return true;
}
```

**Keyboard fallback buttons per card:**

```html
<div class="card-controls" role="group" aria-label="Move this plan">
  <button aria-label="Move up"   data-move="up">↑</button>
  <button aria-label="Move down" data-move="down">↓</button>
  <button aria-label="Move to previous column" data-move="left">←</button>
  <button aria-label="Move to next column"     data-move="right">→</button>
</div>
```

**Manual a11y test checklist (must appear in phase report):**

- [ ] Tab from document start reaches the first Plans card within 6
  Tabs (header + column labels + card).
- [ ] On a card, pressing Enter opens the detail modal.
- [ ] On a card, focus moves to its `↑ ↓ ← →` buttons via Tab.
- [ ] Clicking `↓` on a card moves it one slot down in the same
  column, announces "Moved X to column, position N of M", and
  `.zskills/monitor-state.json` reflects the new order.
- [ ] Clicking `→` on a card in Drafted moves it to Reviewed (first
  position).
- [ ] Dragging a card between columns updates the state file.
- [ ] Two browser tabs reordering: both persist their own POSTs; the
  last one wins; neither crashes.
- [ ] Plans not yet listed in state file default per the Shared
  Schemas mapping: `active` + zero phases-done → `drafted`; `active`
  + ≥1 phase done → `reviewed`; `conflict` / `pr-failed` →
  `reviewed`; `complete` / `landed` / `pr-ready` → hidden. Verified
  against a fixture repo with one plan per status value.
- [ ] **No plan file in `plans/` has its frontmatter modified during
  any drag/drop operation** — verified by `git diff plans/ | wc -l`
  = 0 after a full drag-drop session.

**Rules that apply to this phase in particular:**
- **Never write plan frontmatter from the server.** The column state
  lives exclusively in `.zskills/monitor-state.json`. Any code path
  that looks like it might open a plan file for writing in `server.py`
  is a bug — reject in review.
- **Atomic writes only** for the state file (reuse Phase 2's
  `write_state_atomic`).
- **No optimistic deletion.** If a POST fails, the next poll cycle
  restores the server-truth state; do not remove anything locally.
- **No drag hints outside the Plans / Issues panels** — Worktrees and
  Activity remain read-only.

### Acceptance Criteria

- [ ] Dragging a plan card between columns results in
  `.zskills/monitor-state.json` containing the new column assignment
  within 2 seconds (verified by diffing the file pre/post).
- [ ] `.zskills/monitor-state.json` is valid JSON after 100 consecutive
  POSTs from a test script (no partial writes — atomic tmp+replace
  guarantees this).
- [ ] **Concurrent POSTs** (race regression): 20 parallel `curl -X POST`
  with distinct bodies complete without 5xx; the final state file is
  valid JSON matching one of the posted bodies; no intermediate 0-byte
  read is observed (stat the file after each response — `%s` > 0).
- [ ] `git diff plans/` is empty after any drag-drop session (no plan
  file mutation).
- [ ] Keyboard-only: `↓` button moves card down one position; verified
  by DOM inspection and state file diff.
- [ ] `aria-live` announcement appears in `#plans-live` after each
  successful move (verified by playwright-cli reading textContent).
- [ ] POST with invalid shape (e.g., unknown column name) returns 400
  and does NOT modify the state file.
- [ ] Two-tab concurrent reorder test: after both tabs POST, the state
  file matches whichever POST arrived last, and no error is thrown in
  either tab's console.

### Dependencies

- Phase 3's UI scaffold (panel layout, modal system).
- Phase 2's `POST /api/queue` with strict validation.
- Phase 1's `queue` annotation on plan / issue records.
- Phase 6A reads this state file — must not change shape without
  updating Phase 6A.

---

## Phase 5 — `/zskills-monitor` skill

### Goal

Expose the server as a first-class skill: `/zskills-monitor
[start|stop|status]`. Start launches the server as a detached
background process with a PID file. Stop sends SIGTERM (never
`kill -9`). Status reports uptime + URL.

### Work Items

- [ ] Create `skills/zskills-monitor/SKILL.md` with the frontmatter
  shape below.
- [ ] Implement the `start` mode: detect existing running instance via
  PID file + `kill -0`; if running, print URL and exit. Otherwise,
  launch server as detached subprocess.
- [ ] Implement the `stop` mode: read PID file, send SIGTERM, wait ≤5s
  polling `kill -0`; verify port is freed via `lsof -i :<port>`;
  remove stale PID file if present.
- [ ] Implement the `status` mode: read PID file; if process alive,
  print URL, port, PID, uptime; if stale PID file, print a warning and
  suggest `lsof -i :<port>`.
- [ ] Mirror source to `.claude/skills/zskills-monitor/SKILL.md` via
  a single `cp -r skills/zskills-monitor .claude/skills/` (batch copy,
  never per-file Edit — see CLAUDE.md memory on permission storms
  when editing `.claude/skills/` directly).
- [ ] Tracking markers: per-invocation write
  `fulfilled.zskills-monitor.<id>` under
  `.zskills/tracking/zskills-monitor.<id>/`, where `<id>` is sanitized
  via `scripts/sanitize-pipeline-id.sh`.

### Design & Constraints

**Frontmatter (verbatim):**

```yaml
---
name: zskills-monitor
disable-model-invocation: false
argument-hint: "[start|stop|status]"
description: >-
  Stand up a local web dashboard for this repo — plans, issues,
  worktrees, tracking activity, and a drag-and-drop priority queue.
  Starts a detached Python HTTP server on a port derived from
  scripts/port.sh; stop sends SIGTERM. State lives in
  .zskills/monitor-state.json. Usage: /zskills-monitor [start|stop|status].
---
```

**Start mode (sequenced steps the skill body prescribes):**

1. If `.zskills/monitor-server.pid` exists:
   a. Read the JSON PID file:
      `PID=$(jq -r .pid .zskills/monitor-server.pid)` and
      `PORT=$(jq -r .port .zskills/monitor-server.pid)` (same idiom as
      Stop mode — do NOT re-run `scripts/port.sh`, whose output can
      diverge between start and the prior start if `cwd` or `DEV_PORT`
      differs).
   b. `kill -0 $PID` to check liveness.
   c. If alive → print `Dashboard already running at http://127.0.0.1:$PORT/`
      and exit 0.
   d. If dead → print warning that PID file is stale; remove it;
      continue.
2. Compute port: `PORT=$(bash scripts/port.sh)`.
3. Check port free:
   `if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null; then
     echo "Port $PORT busy — run 'lsof -i :$PORT' to investigate"; exit 2; fi`.
4. Launch detached — the skill body runs **bash** (skills execute shell
   commands, not Python), so the canonical form is:
   ```bash
   mkdir -p .zskills
   nohup python3 -m zskills_monitor.server \
     > .zskills/monitor-server.log 2>&1 < /dev/null &
   disown
   ```
   The `subprocess.Popen([..., start_new_session=True, ...],
   stdout=<log>, stderr=STDOUT, stdin=DEVNULL)` form is documented
   here only as a reference for test harnesses that launch the server
   from Python. The skill does not use it.
5. Sleep 500ms. Curl `http://127.0.0.1:$PORT/api/health`. If 200 OK:
   print `Dashboard running at http://127.0.0.1:$PORT/`. Exit 0.
6. If health check fails: print the last 20 lines of
   `.zskills/monitor-server.log` and exit 1 — do NOT send SIGTERM
   (there might be nothing running; log is the diagnostic).
7. Verify detachment: `ps -o ppid= -p "$(cat .zskills/monitor-server.pid
   | jq -r .pid)"` should print `1` (init) on Linux after
   `start_new_session=True` / `disown`. This is logged to the skill
   output but does not fail the start; it is assertion-tested in
   Acceptance Criteria.

**Stop mode:**

1. If `.zskills/monitor-server.pid` missing → print
   `No running monitor (no PID file).` Exit 0 (idempotent).
2. Read the PID file as JSON:
   `PID=$(jq -r .pid .zskills/monitor-server.pid)` and
   `PORT=$(jq -r .port .zskills/monitor-server.pid)`. The port is
   read from the PID file, NOT re-computed via `bash scripts/port.sh`
   — `port.sh`'s output can diverge between start and stop if `cwd`
   or `DEV_PORT` changed, yielding a wrong `lsof` target.
3. `kill -0 $PID`. If dead → remove stale PID file; exit 0.
4. `kill -TERM $PID`.
5. Wait up to 5s (poll `kill -0` at 200ms intervals).
6. If still alive after 5s: print
   `Monitor did not exit within 5s. Run 'lsof -i :$PORT' to
   investigate; do NOT kill -9.` Exit 1. (Do not escalate to
   SIGKILL — that is a CLAUDE.md rule violation.)
7. Confirm port free: `lsof -iTCP:$PORT -sTCP:LISTEN`; print result.
8. Remove PID file. Exit 0.

**Status mode:**

1. If no PID file: print `Monitor not running.` Exit 0.
2. Read PID and port from the JSON PID file (same `jq` idiom as stop).
3. `kill -0 $PID`.
4. If alive: look up start time. The JSON PID file already contains
   `started_at` (ISO-8601) — use that as the primary source, since it
   is portable and recorded at actual bind-success time:
   ```bash
   STARTED=$(jq -r .started_at .zskills/monitor-server.pid)
   # Uptime as human-readable "Nh Mm" via awk / date arithmetic.
   ```
   `ps -o lstart= -p $PID` is a portable (Linux + macOS) fallback if
   the JSON file is missing the field. `/proc/$PID` mtime is
   **avoided** — it is Linux-only and `stat -c` is not on macOS BSD.
   Print:
   ```
   Monitor running
     URL:    http://127.0.0.1:<port>/
     PID:    <pid>
     Uptime: <human>
     Log:    .zskills/monitor-server.log
   ```
5. If dead: `Monitor PID file is stale (PID <N> not running).
   Run 'lsof -i :<port>' to verify port is free; then retry
   /zskills-monitor start.` Exit 1.

**Tracking markers:**

After every invocation, write
`.zskills/tracking/zskills-monitor.<id>/fulfilled.zskills-monitor.<id>`
with content:

```
skill: zskills-monitor
id: <id>
status: complete
date: <ISO-8601>
output: <start|stop|status result summary>
```

where `<id>` = sanitized via `bash scripts/sanitize-pipeline-id.sh
"zskills-monitor-$(date -u +%Y%m%dT%H%M%SZ)"`. **Never construct the
pipeline-id subdir path by string concatenation without sanitizing**
(CLAUDE.md rule).

**Mirror to `.claude/skills/` — one command, not per-file Edit:**

```bash
rm -rf .claude/skills/zskills-monitor
cp -r skills/zskills-monitor .claude/skills/zskills-monitor
```

Run this once at the end of the phase — never Edit files under
`.claude/skills/` directly (memory: permission storm).

**Rules that apply to this phase in particular:**
- **No `kill -9` / `killall` / `pkill` / `fuser -k`** — anywhere in the
  skill body. Only SIGTERM. If SIGTERM fails within 5s, report and bail
  out, do not escalate.
- **No `2>/dev/null` on fallible ops.** `kill -0` failure is expected
  (process is dead), so its stderr is harmless — but do not silence it
  on `kill -TERM`, `rm`, or the `cp -r` mirror step.
- **Verify after state change.** After `stop`: verify PID gone via
  `kill -0` and port free via `lsof`. After `start`: verify via
  `curl /api/health`. Do not declare success without verification.
- **Do not commit `.zskills/monitor-server.log`, `.pid`, or
  `monitor-state.json`.** `.gitignore` does NOT cover these today
  (verified: the current `.gitignore` only lists `.zskills/tracking/`
  and `.zskills-tracked`). Phase 2's Work Items include adding the
  three entries to `.gitignore`; do not defer that work to this phase.
  After Phase 2 lands, `git check-ignore .zskills/monitor-server.pid`
  exits 0.

### Acceptance Criteria

- [ ] `skills/zskills-monitor/SKILL.md` exists with the specified
  frontmatter.
- [ ] `.claude/skills/zskills-monitor/SKILL.md` exists and is
  byte-identical to the source (`diff -q` returns 0).
- [ ] `/zskills-monitor start` (or equivalent test harness) creates
  `.zskills/monitor-server.pid` and `/api/health` returns 200 within
  1s of completion.
- [ ] `/zskills-monitor status` after start prints a line matching
  `^Monitor running`.
- [ ] `/zskills-monitor stop` removes `.zskills/monitor-server.pid`
  and frees the port within 5s.
- [ ] `grep -nE '\bkill\s+-9|killall|pkill|fuser\s+-k'
  skills/zskills-monitor/SKILL.md` returns no matches.
- [ ] Running `start` twice in a row does not create a second server
  — the second invocation detects the live PID and prints the URL
  without launching.
- [ ] Running `stop` twice is idempotent — the second run prints
  `No running monitor (no PID file).` and exits 0.
- [ ] Tracking marker is written under
  `.zskills/tracking/zskills-monitor.<sanitized-id>/fulfilled.zskills-monitor.<sanitized-id>`
  with valid `skill:`/`id:`/`status:`/`date:` fields after every
  invocation.
- [ ] **Detachment** (concrete survival test): start the server in one
  bash session; exit that session; in a NEW bash session, assert:
  (a) `jq -r .pid .zskills/monitor-server.pid` points at a live
  process (`kill -0` returns 0); (b) `ps -o ppid= -p "$PID"` prints
  `1` (Linux init; macOS launchd behaves equivalently — parent ≠
  original session shell); (c) `curl -sf
  http://127.0.0.1:$(jq -r .port .zskills/monitor-server.pid)/api/
  health | jq -e '.status == "ok"'` exits 0.

### Dependencies

- Phase 2's server (launch target) and `.gitignore` updates.
- `scripts/port.sh` (path-derived port hash + `DEV_PORT` override).
- `scripts/sanitize-pipeline-id.sh` — already present in the repo
  (verified: `ls scripts/sanitize-pipeline-id.sh` returns the file);
  use via `bash scripts/sanitize-pipeline-id.sh "$RAW_ID"`.
- `.zskills/` writable.
- `lsof`, `kill`, `ps`, `jq` present (standard on all supported
  Linux + macOS hosts).

---

## Phase 6 — `/work-on-plans` skill + remove `/plans work`

This phase has two independent sub-parts. 6A is an addition; 6B is a
removal. Both must land together so the skill catalog and user-facing
CLI stay consistent.

### Goal

(A) Ship `/work-on-plans` — a batch executor that reads the
monitor-owned ready queue and dispatches `/run-plan <plan> auto` per
entry, modeled after `/fix-issues`. (B) Remove the now-redundant
`work`, `stop`, and `next-run` modes from `/plans` SKILL.md,
argument-hint, and all downstream references (README, CHANGELOG,
PRESENTATION).

### Work Items — 6A (`/work-on-plans`)

- [ ] Create `skills/work-on-plans/SKILL.md` with frontmatter.
- [ ] Implement CLI parse: `N [auto|continue]`, `all [auto|continue]`,
  `every SCHEDULE`, `stop`, `next`.
- [ ] Implement "sync" sub-step: read `.zskills/monitor-state.json`
  (canonical schema — see Shared Schemas), extract `plans.ready` in
  order. If the file does not exist: treat as an empty state
  (`{"plans":{"ready":[]}, ...}`) and print:
  `No monitor state file found. The ready queue is empty — start
  the monitor with /zskills-monitor start and drag plans to Ready.`
  Exit 0 (do NOT raise `FileNotFoundError`). If the file is
  unparseable JSON: print the path and exit 1 with a diagnostic; do
  NOT silently ignore.
- [ ] Implement "resolve" sub-step: map each ready-queue slug back to
  `plans/<ORIGINAL_FILE>.md` by scanning `plans/*.md` once and
  computing each file's slug via the same rule Phase 1 used; build a
  slug → path dict; fail loud if a queued slug has no matching file.
- [ ] Implement "dispatch" sub-step: per plan, invoke
  `/run-plan plans/<FILE>.md auto` via the **Skill tool** (see
  Dispatch mechanism subsection below). **No landing-mode flag** —
  `/run-plan` itself resolves from its own argument + config rules
  (per verified `skills/run-plan/SKILL.md` behavior).
- [ ] Implement failure policy: stop on first `/run-plan` failure
  unless `continue` flag is set. Empty-args behavior: print usage
  string and exit 0 (do NOT default-run anything).
- [ ] Implement `every SCHEDULE`: same cron self-registration pattern
  as `/fix-issues` — treat as in-session cron; each run re-registers.
- [ ] Implement `stop`: cancel the `/work-on-plans` cron if any.
- [ ] Implement `next`: print when the next scheduled run fires.
- [ ] Tracking: write `fulfilled.work-on-plans.<sprint-id>` under
  `.zskills/tracking/work-on-plans.<sprint-id>/` on each invocation
  (sanitized id).
- [ ] Mirror `skills/work-on-plans` → `.claude/skills/work-on-plans`
  via `cp -r` (batch, not Edit).

### Work Items — 6B (remove `/plans work`)

- [ ] Edit `skills/plans/SKILL.md`:
  - Line 4: change `argument-hint` from
    `"[rebuild | next | details | work N [auto] [every SCHEDULE] [now]] | stop | next-run"`
    to `"[rebuild | next | details]"`.
  - Lines 7–8 (description): remove the "batch execution" sentence
    and the `/plans [... work N ...]` usage example; replace with
    "View plan status, find the next ready plan. For batch execution,
    see `/work-on-plans`."
  - Line 11 (H1): change `# /plans [rebuild | next | details | work N]
    — Plan Dashboard & Executor` to `# /plans [rebuild | next |
    details] — Plan Dashboard` (drop "& Executor").
  - Lines 23–25 (mode summary bullets): delete the three bullets for
    `work`, `stop`, `next-run` entirely. Replace with a single
    pointer: "- **For batch execution:** see `/work-on-plans`."
  - **Do not** delete any `## Mode:` section — there are none for
    `work`/`stop`/`next-run` (they appear only in the mode-summary
    bullets at the top; verified: `grep "^## " skills/plans/SKILL.md`
    shows only Show, Details, Rebuild, Next + tracker sub-headings).
- [ ] Edit `README.md` skill catalog (verified: the string `/plans
  work` does NOT appear in README.md — only `plans` appears on lines
  78, 79, 81; line 81 reads
  `| /plans | Plan dashboard: index, status tracking, priority
  ranking, batch execution |`). Two edits:
  1. Change the `/plans` row to remove "batch execution":
     `| /plans | Plan dashboard: index, status tracking, priority
     ranking |`.
  2. Add a new row directly beneath the `/plans` row:
     `| /work-on-plans | Batch-execute prioritized ready queue from
     the monitor dashboard |`.
- [ ] Edit `CHANGELOG.md`: add entry
  `### Migration — /plans work removed`
  explaining that batch plan execution moved to `/work-on-plans` and
  that users running `/plans work N` should now run
  `/work-on-plans N`. List the affected skills.
- [ ] Edit `PRESENTATION.html` line 504 (example
  `<code>/plans work 3 auto every 6h</code>`): replace with
  `<code>/work-on-plans 3 auto every 6h</code>`.
- [ ] Mirror `skills/plans` → `.claude/skills/plans` via `cp -r`.

### Design & Constraints — 6A

**Frontmatter (verbatim):**

```yaml
---
name: work-on-plans
disable-model-invocation: true
argument-hint: "N [auto] [continue] | all [auto] [continue] | every SCHEDULE | stop | next"
description: >-
  Batch-execute the prioritized ready queue built in the monitor
  dashboard. Reads .zskills/monitor-state.json (plans.ready) in order
  and dispatches /run-plan <plan> auto for each. Mirrors /fix-issues
  for bugs — same scheduling, same failure policy, same reporting.
  Usage: /work-on-plans N [auto] [continue] | all | every SCHEDULE |
  stop | next.
---
```

**Slug → file path resolution (single source of truth):**

```python
# Same rule as Phase 1 collect.py
def slug_of(plan_path: Path) -> str:
    name = plan_path.stem          # basename without .md
    s = name.lower().replace("_", "-")
    s = re.sub(r"[^a-z0-9-]", "", s)
    return s

# Build the reverse dict
def build_slug_index(plans_dir: Path) -> dict[str, Path]:
    out = {}
    for p in sorted(plans_dir.glob("*.md")):
        out[slug_of(p)] = p
    return out
```

If a ready-queue slug is not in the index: fail the entire run with:

```
/work-on-plans: queued slug '<slug>' has no matching plan file in plans/.
The monitor state file references a plan that no longer exists on disk.
Open the dashboard to remove it from the queue, or edit
.zskills/monitor-state.json directly.
```

**Dispatch mechanism (pinned — NOT "same as /fix-issues"):**

`/fix-issues` does NOT dispatch `/run-plan` — it dispatches `/draft-plan`
for skipped issues and uses the Agent (Task) tool directly for per-issue
worktree fix agents (verified in `skills/fix-issues/SKILL.md`). The
"pattern /fix-issues uses" that this plan inherits is the
**CLI surface + scheduling + failure policy + reporting** — NOT the
dispatch target.

For invoking `/run-plan` from `/work-on-plans`, the mechanism is:

- `/work-on-plans` runs at top level (parent session). It dispatches
  `/run-plan plans/<FILE>.md auto` via the **Skill tool**
  (`skill: run-plan`, `args: "plans/<FILE>.md auto"`).
- It does NOT spawn an Agent (Task) subagent that then calls the Skill
  tool — per CLAUDE.md memory `project_subagent_architecture`, Claude
  Code subagents cannot themselves dispatch subagents, and Skill is
  a top-level-only primitive in that architecture. Running
  `/work-on-plans` at top level and having IT call `Skill` is the
  only supported path.
- If `/work-on-plans` is itself invoked from inside a subagent context
  (no `Agent` tool visible), it cannot dispatch; document this case
  by printing `/work-on-plans must run at top-level to dispatch
  /run-plan (subagents cannot invoke Skill)` and exiting 2. This
  mirrors the guidance in `skills/fix-issues/SKILL.md` "Dispatch
  protocol" where the orchestrator checks for the presence of the
  Agent tool.

**Dispatch loop:**

For each plan in `plans.ready[0:N]` (in order):

1. Record the dispatch: create a `step.work-on-plans.<sprint-id>.<slug>`
   marker with `status: started`.
2. Invoke `Skill(skill="run-plan", args="plans/<FILE>.md auto")`.
3. On success: mark the step `status: complete`.
4. On failure:
   - Without `continue` flag → stop immediately, write a summary
     report to `reports/work-on-plans-<sprint-id>.md`, exit non-zero.
   - With `continue` flag → log failure, continue to next plan.

**Landing-mode policy:**

`/work-on-plans` passes NO landing-mode flag to `/run-plan`. `/run-plan`
resolves its landing mode from `$ARGUMENTS` (`pr` / `direct`) then
`.claude/zskills-config.json` `execution.landing` then the
`cherry-pick` fallback — as verified in
`skills/run-plan/SKILL.md:75–105`. `/run-plan` does NOT currently
parse the plan-body Landing-mode hint; the monitor displays that
hint for the user as informational metadata only. If plan-body hints
should drive actual landing, that is a `/run-plan` change owned by a
different plan, not this one.

**CLI parsing — priority order (mirrors `/fix-issues`):**
- **No args** → print usage string, exit 0 (do NOT default to `next`
  or `1 auto`; explicit is better than implicit).
- `stop` (case-insensitive) → highest precedence
- `next` → second highest
- `every <SCHEDULE>` → scheduling mode (implies `auto`)
- Otherwise: `N` (integer) or `all`, optionally with `auto` and/or
  `continue`

**Failure-policy default:** stop on first failure. `continue` is opt-in.

**Cron self-registration pattern:** same as `/fix-issues` — in-session
cron registered via `CronCreate`, self-perpetuating (each run
re-registers). Document that the cron dies with the Claude Code session.

**Tracking markers:**
- `fulfilled.work-on-plans.<sprint-id>` — one per invocation, at end.
- `step.work-on-plans.<sprint-id>.<slug>` — one per dispatched plan.

All IDs sanitized via `scripts/sanitize-pipeline-id.sh`.

### Design & Constraints — 6B

**Exact edits to `skills/plans/SKILL.md` (re-verified: the modes are
stubs named in the argument-hint and mode-summary only — NO dedicated
`## Mode: Work`, `## Mode: Stop`, or `## Mode: Next-Run` sections
exist in the file, and no Step / Rule body elsewhere references these
three modes by name).** Relevant current lines (from
`grep "^## " skills/plans/SKILL.md`):

```
27:## Mode: Show (bare `/plans`)
61:## Mode: Details (`/plans details`)
92:## Mode: Rebuild (`/plans rebuild`)
234:## Mode: Next (`/plans next`)
250:## Key Rules
```

Leave lines 27, 61, 92, 234, 250 UNCHANGED. Only change frontmatter
and mode-summary bullets (lines 4, 7–8, 11, 23–25).

**Enumeration check — blocking acceptance:**

Before declaring Phase 6B complete, re-run:

```bash
grep -niE '\bwork\s+N\b|\bnext-run\b|/plans\s+(work|stop|next-run)' \
  skills/plans/SKILL.md
```

This must return zero lines. `\bstop\b` alone is not checked (too
many legitimate uses of the word "stop"). If any matches appear,
the removal was incomplete — the mode-summary or argument-hint
still references a deleted mode, OR a mode body that research missed
actually exists. Fix before landing.

**Add a reconciliation note to `/plans bare`:**

The `/plans bare` output (lines 36–51 of `skills/plans/SKILL.md`)
still classifies plans as "Ready to Run" / "In Progress" / etc. —
parallel vocabulary to the monitor's `drafted/reviewed/ready`. Add a
one-sentence footer to the bare output:

> Note: this ranking is independent of the monitor dashboard's Ready
> queue. For interactive prioritization, open /zskills-monitor.

This is a tiny copy change; it prevents user confusion when the two
surfaces disagree.

**PRESENTATION.html — verified existing reference:**

```
504:      <td><code>/plans work 3 auto every 6h</code></td>
```

Replace the code content only; do not restructure the table.

**Rules that apply to this phase in particular:**
- **Never edit `.claude/skills/` directly.** Edit `skills/` source,
  then `cp -r skills/plans .claude/skills/plans && cp -r
  skills/work-on-plans .claude/skills/work-on-plans`.
- **6A and 6B must land in the same push** (not necessarily the same
  commit). Two commits are acceptable:
  - (a) `/work-on-plans: add skill + mirror + tracker`
  - (b) `/plans: remove work/stop/next-run + migrate README/CHANGELOG/
    PRESENTATION`
  Either they are both on the pushed branch together, or neither is.
  CLAUDE.md's "feature-complete commit" rule is about dependency
  bundles (an imported file must ship with its importer); it does
  NOT require every co-shipped doc to be in one commit. Splitting
  helps pre-commit hooks that size-limit per-commit file counts.
- **Do not run `/plans rebuild`** as part of this phase — that
  touches `plans/PLAN_INDEX.md` which is orthogonal, and leaving it
  out keeps the commit focused.

### Acceptance Criteria

- [ ] `skills/work-on-plans/SKILL.md` exists with the specified
  frontmatter (`grep '^name: work-on-plans' skills/work-on-plans/SKILL.md`
  matches).
- [ ] `.claude/skills/work-on-plans/SKILL.md` exists and is
  byte-identical to source.
- [ ] `/work-on-plans` with **no args** prints the usage string and
  exits 0 (does not default-run anything).
- [ ] `/work-on-plans next` with an empty ready queue prints
  `No plans in the ready queue.` and exits 0.
- [ ] `/work-on-plans next` with **no state file present** prints the
  "No monitor state file found ..." message (see Work Items) and
  exits 0, without raising `FileNotFoundError`.
- [ ] `/work-on-plans 1 auto` with one plan in `plans.ready` dispatches
  `/run-plan plans/<FILE>.md auto` via the Skill tool (no Agent / Task
  spawn) — verified by presence of
  `step.work-on-plans.<sprint-id>.<slug>` marker.
- [ ] A queued slug with no matching file yields the fail-loud error
  message from Design & Constraints (no silent skip).
- [ ] Enumeration check (blocking):
  `grep -niE '\bwork\s+N\b|\bnext-run\b|/plans\s+(work|stop|next-run)'
  skills/plans/SKILL.md` returns zero lines.
- [ ] `skills/plans/SKILL.md` argument-hint equals exactly
  `"[rebuild | next | details]"`.
- [ ] `grep -nE '^\| `?/work-on-plans`? ' README.md` returns exactly
  one row (the new catalog entry). `grep -niE
  '\bbatch\s+execution\b' README.md | grep -i plans` returns zero
  lines (the `/plans` row's phrase was removed).
- [ ] `CHANGELOG.md` contains a `Migration — /plans work removed` entry
  (or equivalently-titled section) introduced in this commit.
- [ ] `grep -n '/plans work' PRESENTATION.html` returns no matches
  (line 504 was migrated).
- [ ] `diff -q skills/plans/SKILL.md .claude/skills/plans/SKILL.md`
  returns 0 (mirror synced).
- [ ] `diff -q skills/work-on-plans/SKILL.md
  .claude/skills/work-on-plans/SKILL.md` returns 0 (mirror synced).
- [ ] Tracking marker
  `fulfilled.work-on-plans.<sprint-id>` appears under
  `.zskills/tracking/work-on-plans.<sprint-id>/` after a test
  invocation.

### Dependencies

- Phase 4's `.zskills/monitor-state.json` (input data).
- `/run-plan` skill (dispatch target — must accept
  `<plan-path> auto` signature).
- `scripts/sanitize-pipeline-id.sh` (tracking id sanitization).
- `/fix-issues` skill body (reference pattern for CLI parsing,
  scheduling, reporting — read but not modified).
- 6A and 6B must land in a single commit (see in-phase rule above).

---

## Plan Quality

**Drafting process:** `/draft-plan` with 2 rounds of adversarial review
**Convergence:** Converged at round 2 (findings trajectory 40 → 10 → all resolved)
**Remaining concerns:** None substantive. Minor compression opportunities deferred (`/tmp/draft-plan-refiner-round-2.md` F8) judged below threshold.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 17 (4 critical, 8 major, 5 minor) | 23 (6 critical, 11 major, 6 minor) | 39 fixed / 1 justified (phase-4 split declined per user decision) |
| 2 | 8 (0 critical, 2 major, 3 minor, 3 compression) | 5 (0 critical, 1 major, 4 minor) | 13 raw → 10 actionable, all fixed |

### Key round-1 fixes
- `.gitignore` work item added (was claiming coverage that didn't exist).
- Landing-mode parse regex corrected to match real `> **Landing mode: PR**` format.
- Default-column inference corrected (no plan uses `status: draft`).
- Flat + nested tracking-marker walk (mixed legacy layout handled).
- `/work-on-plans` dispatch pinned to `Skill(skill="run-plan", args="plans/<FILE>.md auto")`.
- Shared Schemas section added to prevent per-phase drift.
- CSRF / body-size / path-param validation on HTTP routes.
- XSS escape policy (`textContent` default, `// chrome-only` marker for exceptions).
- Detached-subprocess `ppid=1` survival test added.
- JSON PID file (pid + port) so `stop` doesn't recompute port.

### Key round-2 fixes
- Phase 3 Work Items reconciled with updated Design & Constraints (`setTimeout`+visibilitychange; 250/400/700 line budget).
- `write_state_atomic` race fixed: per-thread tmp name + `threading.Lock()`.
- XSS acceptance grep tightened (single-token `// chrome-only` marker on same line).
- Report-phase regex corrected for `## Phase — 5c Name` format.
- ARIA listbox anti-pattern replaced with plain `role="list"` / `role="listitem"`.
- Activity-list sort normalized to UTC before ordering.

### Research and review artifacts (ephemeral)
- `/tmp/draft-plan-research-ZSKILLS_MONITOR_PLAN.md`
- `/tmp/draft-plan-review-round-1-reviewer.md`, `-devil.md`, `-refiner-round-1.md`
- `/tmp/draft-plan-review-round-2-reviewer.md`, `-devil.md`, `-refiner-round-2.md`
