# Plan Report — Zskills Monitor Dashboard

## Phase — 6 Read-only dashboard UI [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** 1239f6c (impl: HTML+CSS+JS + 45 tests), 5f27e06 (tracker mark in-progress)

### Work Items

11 WIs done. Files at `skills/zskills-dashboard/scripts/zskills_monitor/static/`:
- `index.html` (64 lines) — 5 panels + modal-root + `<script type="module" src="/app.js">`
- `app.css` (326 lines) — minimal styling, ≥3 CSS vars (`--bg`, `--surface`, `--accent`)
- `app.js` (547 lines) — fetch/render pipeline, modals, keyboard accessibility

### Safety audit (verifier-confirmed)

- **No `.innerHTML =`** assignments anywhere (XSS-safe; uses `textContent` + DOM construction)
- **No `setInterval`** (visibility-aware `setTimeout` recursion — pauses when tab hidden)
- **No remote module imports** (`https://...` in `import` statements: 0 hits)
- **No inline event handlers** (`onclick=`/`onload=` in HTML/CSS: 0 hits)
- `cache: 'no-store'` on all 3 fetch sites (poll, plan modal, issue modal)
- `<script type="module">` in index.html (no script global pollution)
- `aria-modal="true"` + `role="dialog"` on modal element

### 5 panels + 2 modals

- **Plans**: title, blurb, phase ratio, status badge, landing-mode pill (+ `unknown` warning style)
- **Issues**: number, title, labels, created date
- **Worktrees**: basename, branch, `.landed` status pill, age
- **Branches**: name, last commit + age, upstream; worktree-backed branches dimmed via `.card.dim`
- **Activity**: capped at 20, newest first, with `parent` for dispatched-child surface
- **Plan detail modal**: `/api/plan/<slug>` with phase list — "Landed in <ref>" / "Pending" branching
- **Issue detail modal**: `/api/issue/<N>` preformatted body

### Keyboard accessibility

- All cards `tabindex="0"` (Tab cycles)
- Enter on focused card opens modal
- Esc closes modal; focus restored to invoker
- Focus-trap inside open modal

### Deterministic rendering

- `errors[]` pre-sorted by Phase 4 `collect.py`; verifier confirmed two consecutive `/api/state` GETs returned byte-equal JSON
- Plans/issues/worktrees stable ordering
- Activity capped at 20 entries, JSON-fingerprint-based diff

### Verification

- Test suite: PASSED (1111/1111 — Phase 6 added +45; rebase brought in 8 from main's parallel sessions)
- Live UI smoke (verifier-run on port 55933):
  - `GET /` → 200, `text/html`, 2560B
  - `GET /app.js` → 200, `application/javascript`, 21482B
  - `GET /app.css` → 200, `text/css`, 8072B
  - `GET /api/state` x2 → byte-equal `errors[]`
- Server smoke clean shutdown via SIGTERM

### PLAN-TEXT-DRIFT findings

Zero. No TODO/FIXME/HACK/PLAN-TEXT-DRIFT/TBD markers in static/ or new test file.

### Notes

- Working-tree had a pre-existing whitespace-only reformat of `.claude/zskills-config.json` from another session/process. Per CLAUDE.md "never revert/discard changes you didn't make," verifier left it untouched. Resolved rebase initially via `--autostash`. The change remains in the worktree as `M .claude/zskills-config.json` — outside Phase 6's commit.

---

## Phase — 5 HTTP server [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** 63747e5 (impl: server.py + 53 tests), 50b9b55 (tracker mark in-progress)

### Work Items

All WIs done per implementer + verifier audit. Files:
- `skills/zskills-dashboard/scripts/zskills_monitor/server.py` (1099 lines, ThreadingHTTPServer + BaseHTTPRequestHandler)
- `skills/zskills-dashboard/scripts/zskills_monitor/static/.gitkeep` (Phase 6 placeholder)
- `tests/test_zskills_monitor_server.sh` (812 lines, 53 cases)
- `tests/run-all.sh` (one-line registration)

### Security audit (verifier-confirmed)

- **Bind**: `BIND_HOST = "127.0.0.1"` only; verified via `ss -ltn` smoke. NO 0.0.0.0 anywhere.
- **Trigger contract**: Origin check → command allowlist (`^/work-on-plans(\s|$)`) → path resolved against MAIN_ROOT + relative_to recheck → `subprocess.run([str(resolved), command], shell=False, ...)` → env scrubbed to `{PATH, HOME, USER, LANG}` (drops ZSKILLS_*) → `cwd=str(main_root)` → `timeout=30`
- **Slug/issue regex**: applied AFTER `urllib.parse.unquote` → directory traversal blocked (`..%2F..%2Fetc` decodes to `../../etc` → contains `/` → fails regex → 400)
- **Plan lookup**: in-memory dict via `plans_dir.glob("*.md")`, NOT `os.path.join` against user input — `grep -nE 'os\.path\.join'` returned 0 hits
- **No `eval`/`exec`/`shell=True`** anywhere
- **PID file**: written AFTER bind succeeds (so EADDRINUSE doesn't leave stale PID); format `pid=N\nport=N\nstarted_at=ISO`

### Endpoints (9 total)

GET: `/api/health`, `/api/state`, `/api/plan/<slug>`, `/api/issue/<N>`, `/api/work-state`, `/`, `/app.js`, `/app.css`
POST: `/api/queue`, `/api/trigger`, `/api/work-state/reset`

### Cross-process flock

`fcntl.flock(LOCK_EX)` on `.zskills/monitor-state.json.lock` + module-level `_STATE_THREAD_LOCK` for in-process serialization. All write paths (`/api/queue`, work-state stale-rewrite, `/api/work-state/reset`) wrapped via `with _state_lock(main_root):`. Atomic via `os.replace()` with same-dir `.tmp`.

### Port resolution chain

1. `--port` arg
2. `DEV_PORT` env
3. config `dev_server.default_port` (BASH_REMATCH-style regex on JSON)
4. `port.sh` (checks BOTH `.claude/skills/update-zskills/scripts/port.sh` AND `skills/update-zskills/scripts/port.sh`)
5. Friendly diagnostic + `exit 2` (no Python traceback)

NO use of removed `dev_server.port_script` field (deleted in PR #99).

### Verification

- Test suite: PASSED (1058/1058 — Phase 5 added +53; another parallel session contributed 5 more)
- Independent server smoke: bind to 127.0.0.1 verified via `ss -ltn`; SIGTERM exit in 506ms with PID file removal; PID file format matches Shared Schemas
- Trigger security tested live: empty config → 501; non-`/work-on-plans` → 400; argv literal command (shell=False) verified; env scrubbed; path-escape → 500

### Notable verifier-flagged minor notes (non-blocking)

1. server.py is 1099 lines, not the implementer-reported "~720" (count error in report; implementation is solid).
2. `_state_lock` relies on `os.close(fd)` in `finally` to release the flock rather than explicit `LOCK_UN`. Linux semantics make this correct (closing the fd releases the flock), but a more defensive pattern would explicitly `LOCK_UN` in `finally`. Not a blocker.

### PLAN-TEXT-DRIFT findings

Zero. Implementer's claim independently re-confirmed by verifier.

---

## Phase — 4 Python data aggregation library [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** b720fbb (impl: Python module + 12 fixtures + 29 tests), e04a711 (tracker mark in-progress)

### Work Items

All WIs done per implementer + verifier report. Module at `skills/zskills-dashboard/scripts/zskills_monitor/` (post-Phase-B norm; relocated from flat `scripts/` per refine-plan DA-4 fix):

- `__init__.py` + `collect.py` (1277 lines)
- `parse_plan(path)` — frontmatter, blurb, landing-mode, phases, tracker, category, meta_plan, sub_plans
- `parse_report(slug)` — both `## Phase 5c — N` and `## Phase — 5c N` shapes
- `slug_of(path)` — canonical `tr '[:upper:]_' '[:lower:]-'` rule (verified parity with Phase 1's inline tr)
- Tracking-marker scan with subdir-wins dedup + conflict logging
- Worktree + branch listing reusing briefing helpers via `importlib.util.spec_from_file_location` (NOT broken `from scripts.briefing`)
- 60s issue cache with `_runner` injection seam
- v1.0 + v1.1 state-file merge (queue.mode annotation; default_mode surfaced)
- `errors[]` sorted by (source, message), capped at 100 + 1 summary entry
- `repo_root` resolved via `git rev-parse --git-common-dir` (worktree-portable)
- 12 fixture sets covering: minimal, with-state, corrupt-state, slug-uppercase, category-{canary,issues,meta}, error-cap, landing-{pr,unknown}, tracking-dedup, state-v10
- `tests/test_zskills_monitor_collect.sh` — 29 test assertions, registered in run-all.sh

### Verification

- Test suite: PASSED (1000/1000, +29 from Phase 3 baseline 971)
- All 18 ACs pass
- collect.py audit: no eval, no shell=True, no os.system, no `2>/dev/null`, no `|| true`, no jq, no PyYAML
- Categorization rules verified against fixtures: `^CANARY` → canary, `_ISSUES.md` → issue_tracker, executable+meta detection via Skill-tool delegate args parsing
- errors[] ordering: byte-deterministic across re-runs; cap at 100 with summary lands deterministically
- Worktree-portable: REPL test from worktree returned MAIN_ROOT (`/workspaces/zskills`), not the worktree path
- 18 ACs all pass per implementer's report; verifier independently re-ran them

### Notable extension noted by verifier

`parse_report` is fully implemented; snapshot includes `plans[].report` (full parsed report dict) in addition to `has_report`/`report_path`. Additive — minimum key set is satisfied; Phases 5-7 can rely on the `report` field.

### Notes

- This was a "rate-limit recovery" landing: the previous implementation agent hit a 5-hour-window error mid-flow (mis-reported as "monthly limit") after writing collect.py (1277 lines, 18 tool uses). The retry agent on this turn read collect.py end-to-end + added the 12 fixture sets + test script + run-all.sh registration. Verifier did fresh-eyes audit on collect.py since the originating implementer's report was lost.
- 1000/1000 tests pass, ground-truth matches plan, no PLAN-TEXT-DRIFT.

---

## Phase — 3 /work-on-plans queue mutation + scheduling [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** f9290b7 (impl: 6 subcommands + flock + 28 tests), 905099b (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 3.1 | CLI parse for queue mutate (add/rank/remove/default) + schedule (every/stop) subcommands | Done | f9290b7 |
| 3.2 | Cross-process flock helper for monitor-state.json RMW | Done | f9290b7 |
| 3.3 | every cron + mode capture (captured > live default precedence) | Done | f9290b7 |
| 3.4 | schedule_under_1h() rejection of <1h with finish + verbatim diagnostic | Done | f9290b7 |
| 3.5 | stop deletes via CronDelete + state idle reset; next reads $WORK_STATE | Done | f9290b7 |
| 3.6 | fulfilled.work-on-plans.<sprint-id> markers for mutating subcommands | Done | f9290b7 |
| 3.7 | Mirror parity for /work-on-plans skill | Done | f9290b7 |

### Verification

- Test suite: PASSED (971/971, +28 from baseline 943)
- All 10 ACs pass
- Cross-process flock: 8/8 racers land with lock; 5/8 without (negative control proves race + that the lock prevents lost updates)
- Slug regex `^[a-z][a-z0-9-]*$` forbids leading digit (per AC-2 — leading digits reserved for execute-mode N)
- Schedule rejection: `30m`/`5m`/`*/30 *`/`*/2 *` all detected as <1h; `1h`/`4h` accepted
- No `eval` over user input, no `jq`, no `kill -9`
- Mirror byte-identical

### Notable scope decisions (verifier-accepted)

1. Slug regex is `^[a-z][a-z0-9-]*$` with explicit `^[0-9]` reject before general regex — belt-and-braces for AC-2's "digit-prefix reserved for execute-mode N" rule.
2. ensure_monitor_state() bootstrap helper duplicates Phase 1's heredoc (rather than `source`-ing) because SKILL.md remains a single-file LLM-driven prompt with no shared `.sh` to import.
3. .gitignore extended now (Phase 3) instead of Phase 5 — Phase 3 is the first phase that creates `monitor-state.json` / `work-on-plans-state.json` / `monitor-state.json.lock` in the working tree.

### Notes

- Phase 3 completes the `/work-on-plans` skill surface. The remaining phases shift to data aggregation (4), HTTP server (5), dashboard UI (6, 7), `/zskills-dashboard` skill (8), and `/plans rebuild` migration (9).
- One transient flake observed in `test-briefing-parity` from a parallel session's worktree appearing/vanishing during the implementer's run; pre-existing environmental flake, not introduced by Phase 3. Verifier's full-suite run was clean.

---

## Phase — 2 Remove /plans work modes [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** 76dbece (impl: 5 files updated), 783db9d (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 2.1 | skills/plans/SKILL.md — argument-hint, description, H1 trimmed; pointer to /work-on-plans; work/stop/next-run removed | Done | 76dbece |
| 2.2 | README.md — /plans row drops "batch execution"; new /work-on-plans row | Done | 76dbece |
| 2.3 | CHANGELOG.md — Migration entry + Cron-cleanup scope paragraph (session-scoped caveat) | Done | 76dbece |
| 2.4 | PRESENTATION.html — cron-scheduling row example uses /work-on-plans | Done | 76dbece |
| 2.5 | /plans bare-mode footer ranking-independent note | Done | 76dbece |
| 2.6 | Cron cleanup (best-effort, session-scoped) | Done | 76dbece |
| 2.7 | Mirror parity for /plans skill | Done | 76dbece |

### Verification

- Test suite: PASSED (943/943, no delta — docs/skill-text only)
- All 7 ACs pass; verifier independently re-detected zero PLAN-TEXT-DRIFT
- PRESENTATION.html row Skill cell change (`/plans` → `/work-on-plans`) verified consistent with table pattern
- /plans skill no longer claims batch execution; pointer to /work-on-plans is canonical migration path

### Notes

- Phase 2 is the cleanup half of the Phase 1+2 migration. Phase 1 shipped /work-on-plans; Phase 2 retires the older /plans work modes.
- Cron cleanup is session-scoped (CronList/CronDelete only see this session's crons) — caveat noted in CHANGELOG.

---

## Phase — 1 /work-on-plans execute-only CLI [UNFINALIZED]

**Plan:** plans/ZSKILLS_MONITOR_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-zskills-monitor-plan
**Branch:** feat/zskills-monitor-plan
**Commits:** 12270a0 (impl: new skill + parent: marker docs), 08e18c3 (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 1.1 | skills/work-on-plans/SKILL.md (677 lines) with frontmatter | Done | 12270a0 |
| 1.2 | CLI parse: read-only (no args, next) + execute (N\|all [phase\|finish] [continue]); Phase 3 subcommands stub | Done | 12270a0 |
| 1.3 | Sync sub-step: reads .zskills/monitor-state.json, auto-creates with bootstrap precedence | Done | 12270a0 |
| 1.4 | Resolve sub-step: inline tr-based slug rule, unknown-slug fail-loud | Done | 12270a0 |
| 1.5 | Dispatch sub-step: mode precedence (CLI > entry > default > "phase"), Skill-tool dispatch | Done | 12270a0 |
| 1.6 | Failure policy: 3-arm detection (text grep, marker timeout, Skill error); stop or continue | Done | 12270a0 |
| 1.7 | Sprint state lifecycle: state=sprint → heartbeat → idle; corrupt JSON resets | Done | 12270a0 |
| 1.8 | Tracking markers: step.work-on-plans, requires.run-plan with parent: work-on-plans, fulfilled.* | Done | 12270a0 |
| 1.9 | docs/tracking/TRACKING_NAMING.md "Parent-tagged markers" subsection (refine F-10 fix) | Done | 12270a0 |
| 1.10 | Mirror parity: bash scripts/mirror-skill.sh work-on-plans | Done | 12270a0 |

### Verification

- Test suite: PASSED (943/943, no delta — skill-body-only change)
- All ACs pass
- No jq, no eval over user input, no `$(())` over uncontrolled values
- Canonical post-Phase-B caller form for sanitize-pipeline-id.sh (`$MAIN_ROOT/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh`)
- Mirror byte-identical
- "Parent-tagged markers" subsection inserted at line 317 of TRACKING_NAMING.md

### PLAN-TEXT-DRIFT findings

2 spec-gap drifts flagged (non-numeric, non-blocking — Phase 3.5 doesn't auto-correct these):

1. Phase 1 WI says "acquire cross-process flock" but Shared Schemas line 94 says "no cross-process file locks" until Phase 5. Implementer correctly used `os.replace()` (POSIX-atomic) per Shared Schemas. WI text contradicts Shared Schemas constraint — should reconcile in a future refine.
2. AC's cross-process-lock test references `/work-on-plans add` — a Phase 3 subcommand. Cannot be exercised in Phase 1; SKILL.md correctly stubs `add` with "Phase 3 not yet landed" diagnostic.

Both are spec-gap inconsistencies, not numeric drift. Verifier independently confirmed.

### Notes

- Phase 1 is foundational: ships the read+execute path of `/work-on-plans`. Phase 2 retires `/plans work` modes. Phase 3 adds queue mutation + scheduling subcommands.
- This is a 9-phase plan. Phases 4-7 build the data aggregation library, HTTP server, dashboard UI, and write-back. Phase 8 creates `/zskills-dashboard` skill. Phase 9 migrates `/plans rebuild` to the new Python aggregator.
