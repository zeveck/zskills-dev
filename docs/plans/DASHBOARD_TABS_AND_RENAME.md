---
issue: 229
title: Dashboard Tabs and Rename (Z Skills Monitor → Z Skills Dashboard)
created: 2026-05-12
status: active
---

# Plan: Dashboard Tabs and Rename

> **Landing mode: PR** -- This plan targets PR-based landing. All phases run
> inside a worktree on the feature branch **`feat/dashboard-tabs-rename`**
> (created in Phase 0 via `/create-worktree`). Each phase commits to that
> branch; the orchestrator dispatches `/land-pr` after Phase 4 completes.

## Overview

This is a **dashboard quality-of-life pass** on the `/zskills-dashboard`
skill (`skills/zskills-dashboard/`). It bundles a presentation refactor
(rename + tabs) with surgical fixes to three known functional bugs and a
verification step for a fourth user-reported concern.

Surfaces touched:

1. **Rename** "Z Skills Monitor" → "Z Skills Dashboard" across every
   user-facing surface (browser title, H1, SKILL.md echo strings, server.py
   help/log/docstring/fallback HTML, file-header JS comment) AND the test
   assertions that grep those strings.
2. **Tab navigation (3 tabs).** The dashboard at `http://127.0.0.1:<port>/`
   currently crams five panels (Plans, Issues, Branches, Worktrees, Recent
   Activity) onto a single page; the user must scroll through a wall of
   text to find the panel they want. This plan introduces a **mouse-first**
   tab pattern that splits **three destination panels (Plans, Issues,
   Branches)** into tabs. The former Worktrees panel is **collapsed into
   the Branches tab** by enriching `renderBranches` to surface
   worktree-derived info (path basename, age, landed-status pill) inline
   per backed branch. Recent Activity is promoted to a **persistent strip
   above the tablist** — Activity is signal, not destination, and should
   remain ambient.
3. **Functional bug fixes (Phase 5).** Three surgical fixes plus one
   verification step for user-reported dashboard issues: an Origin/CSRF
   check that 403s legitimate `/api/queue` POSTs from the user's deployment,
   a READY-column drop that doesn't persist, a disconnect banner that flaps
   during interactions, and a verification step for `/work-on-plans`
   queue-honoring. Diagnosis precedes fix in every sub-section — multiple
   symptoms may collapse to a single root cause.

Mouse-first, not keyboard-first: ARIA roles and visible `:focus-visible`
are retained; the WCAG APG arrow-key / Home / End keyboard handler is
explicitly out of scope. Native `<button>` semantics + browser-default Tab
key behavior are sufficient for keyboard accessibility.

Panel rendering, polling cadence (2s `setTimeout`-recursion), drag-and-drop
mechanics, modal flow, fingerprint-suppressed diff, and the `/api/state`
shape are all unchanged. Each render function continues to write to the
same slot element it writes to today; `renderBranches` gains a
worktree-info sub-row per backed branch but the `#branches-body` slot is
unchanged.

## Shared Conventions

These invariants apply across every phase and are the spec the implementing
agent must read before touching code.

### Files in scope

Under `skills/zskills-dashboard/`:

- `SKILL.md` (594 lines) — bash wrapper, ~11 user-facing "Monitor" strings.
- `scripts/zskills_monitor/server.py` (1130 lines) — 4 user-facing
  "monitor" strings (docstring line 3, fallback HTML 694, argparse 1051,
  startup log 1115). `class MonitorHandler` (540, 1034) and module path
  `zskills_monitor` are INTERNAL — preserve.
  - Origin/CSRF gate: `_origin_ok` is defined at line 601 and called from
    THREE endpoints (queue at 817, trigger at 850, work-state-reset at
    985). Phase 5b modifies the central definition once; all 3 call sites
    inherit. There is no `/api/move-plan` endpoint — the drag-and-drop
    POST goes to `/api/queue`. (Verified by `grep -n "_origin_ok"
    server.py` returning 4 lines = 1 def + 3 callers; `grep -nE
    "/api/move-plan" server.py` returns ZERO.)
  - CLI `--main-root` flag (server.py:14, 1055, 1064-1065) overrides the
    auto-resolved main root from `_resolve_main_root`. Phase 4 and any
    phase that starts a server in the worktree MUST pass
    `--main-root "$(git rev-parse --show-toplevel)"` to keep state files
    under the worktree, not the main checkout.
- `scripts/zskills_monitor/static/index.html` (89 lines) — title (6), H1
  (11) say "Z Skills Monitor". `<main id="grid">` contains the 5 panels.
- `scripts/zskills_monitor/static/app.css` (735 lines) — `.grid` (89-96)
  and `@media (min-width:900px) { grid-template-areas:... }` (98-110)
  are the layout rules tabs replace.
- `scripts/zskills_monitor/static/app.js` (1705 lines) — banner comment
  line 1 says "Z Skills Monitor". Render functions: `renderPlans`
  (575-617) → `#plans-body`; `renderBranches` (654-690) → `#branches-body`
  (enriched in Phase 2 to surface worktree info per backed branch);
  `renderIssues` (745-787) → `#issues-body`; `renderWorktrees` (798-834)
  → `#worktrees-body` (**REMOVED in Phase 2** along with
  `fingerprintWorktrees` 381 and the `applySnapshot` worktrees branch);
  `renderActivity` (846-875) → `#activity-body`.
  Current `boot()` body (1694-1699) is `modalInit();
  bindActionEvents(); schedulePoll(0); scheduleWorkPoll(0);` (verified
  at line 1695-1698). Tab init lands between `bindActionEvents()` and
  `schedulePoll(0)` — i.e., new lines at 1697.
  `backedBranchSet(worktrees)` (646-652) currently returns a `Set` of
  branch names; Phase 2 adds a sibling helper `worktreesByBranch(worktrees)`
  returning `Map<branchName, worktreeObj>` for the renderBranches
  enrichment. `setConnected` (130-138) and its three call sites in
  `fetchState` (148, 152, 155) are the disconnect-flap surface for
  Phase 5d. `commitQueueChange` (1022-1031) POSTs to `/api/queue` and is
  the surface for Phase 5b/5c (no `AbortController` / `.abort()` calls
  anywhere in app.js — verified by `grep -nE '\.abort\('` returning ZERO).

Outside the skill (still in scope for rename lockstep):

- `README.md` line 400 — `Batch-execute prioritized ready queue from the
  monitor dashboard` (the only "monitor" occurrence in README is on this
  one row of the skills table).
- `tests/test_zskills_monitor_dashboard_ui.sh` and
  `tests/test_zskills_dashboard_skill.sh` — see "Test files" below.

Test files that must update in lockstep with the rename:

- `tests/test_zskills_monitor_dashboard_ui.sh` — line 291-292 greps for
  `<title>Z Skills Monitor</title>` (renames in Phase 1); lines 141-147
  loop over `panel-plans panel-issues panel-worktrees panel-branches
  panel-activity` (5 entries). Phase 2 updates this loop to **3 entries**
  (`panel-plans panel-issues panel-branches`): `panel-worktrees` drops
  because the Worktrees tab is removed; `panel-activity` drops because
  Recent Activity moves to `#activity-strip` outside the `.panel` class.
  Line 346 currently asserts `"worktrees"` appears in `/api/state` JSON —
  this assertion is RETAINED: the `/api/state.worktrees` server response
  key continues to ship; only the dedicated panel disappears (data folds
  into `renderBranches`).
  Test additions for Phase 5 bug-fix verification land under
  `tests/test_zskills_monitor_csrf.sh` (5b) and
  `tests/test_zskills_dashboard_disconnect_debounce.sh` (5d); see Phase 5
  ACs for details.
- `tests/test_zskills_dashboard_skill.sh` — embeds in-test copies of the
  SKILL.md bash functions; ~14 string sites at lines 352, 363, 384, 415,
  428, 439, 467, 486, 522 (comment), 532-533, 572-575, 852-853 plus the
  in-function echo strings.

Mirror: `.claude/skills/zskills-dashboard/` is regenerated by
`bash scripts/mirror-skill.sh zskills-dashboard` (per-file, hook-safe).
**Never edit the mirror directly.** Source-of-truth is `skills/`.

### Invariants the refactor MUST preserve

- `/api/state` request/response shape — unchanged. The
  `/api/state.worktrees` key continues to ship (data is folded into
  `renderBranches` client-side; server response shape is untouched).
- 2-second polling cadence via `setTimeout`-recursion (NOT `setInterval`).
- `document.hidden` pause; `visibilitychange` force-load (`schedulePoll(0)`).
- Per-panel fingerprint diff suppression (`fingerprintPlans` 338,
  `fingerprintBranches` 359, `fingerprintIssues` 366,
  `fingerprintActivity` 388). `fingerprintWorktrees` 381 is **REMOVED** in
  Phase 2 along with `renderWorktrees`; its place in `applySnapshot`
  (262-266) is removed in the same commit. `lastFingerprint.worktrees`
  (114) is also removed.
- Slot element IDs (PRESERVED): `#plans-body`, `#branches-body`,
  `#issues-body`, `#activity-body`, plus Plans-panel-head IDs
  (`#run-status`, `#dm-phase`, `#dm-finish`, `#default-mode-footnote`,
  `#plans-live`) and `#issues-live`. Plus the new `#activity-strip`
  container ID introduced by this plan. `#worktrees-body` is **REMOVED**
  along with the worktrees panel.
- Class names on the section elements: `panel panel-plans`, `panel
  panel-issues`, `panel panel-branches` (3 entries — preserves the
  3-entry test loop introduced in Phase 2). `panel-worktrees` and
  `panel-activity` are **REMOVED** (worktrees panel deleted; activity
  moves to `#activity-strip` with its own classes).
- XSS policy: `textContent`/`appendChild`/`createTextNode` only. No
  `innerHTML` except for explicit `// chrome-only` comments.
- No new external dependencies. Stdlib-only Python serving raw
  HTML/CSS/JS. No build step. No JS framework.
- Modal dialog at `#modal-root` (76-85) at `z-index: 50` (app.css:263)
  remains top-level outside the tab structure.
- Globals OUTSIDE the tab structure: `.topbar` (10-15), `#conn-banner`
  (17-19), `#errors-banner` (21-23), `#toast-region` (25), `#modal-root`
  (76-85), AND the new `#activity-strip` introduced by this plan.
- CSRF check is **centralized in `_origin_ok` (server.py:601-610)**;
  modify the central definition, not per-call-site. THREE endpoints
  inherit (queue 817, trigger 850, work-state-reset 985). Verified by
  `grep -n "_origin_ok" server.py` returning 4 lines (1 def + 3 callers).
- Server `--main-root` CLI flag override (server.py:14, 1055, 1064-1065):
  any phase that starts a dashboard server in the worktree passes
  `--main-root "$(git rev-parse --show-toplevel)"` to isolate
  PID/state/audit/issues files under the worktree's `.zskills/`, NOT
  the main checkout's.
- Same-commit invariant: every commit that touches a file under
  `skills/zskills-dashboard/` MUST also bump
  `skills/zskills-dashboard/SKILL.md:13` `metadata.version` to
  `"YYYY.MM.DD+<hash>"` and regenerate the mirror in the same commit.
  Enforcement: `block-stale-skill-version.sh` PreToolUse hook on `git
  commit` (deny envelope), `/commit` Phase 5 step 2.5, CI
  `test-skill-conformance.sh`.

### Design decisions baked in from UI design agent review (refined)

The /draft-plan Phase 1 UI design agent recommended (and the adversarial
review accepted) a structure that overrides the issue body's first-pass
4-tab proposal. The /refine-plan pass collapsed Worktrees-as-its-own-tab
into Branches-with-worktree-info, per the user's mouse-first / 3-tab lock:

| Issue body proposal | UI agent recommendation | Plan adopts |
|---|---|---|
| OVERVIEW tab (Recent Activity) as default-visible | Persistent strip above tablist, always visible, capped at 5 rows with internal scroll | Persistent strip |
| ETC tab combining Worktrees + Branches | (refined) Single BRANCHES tab; worktree info surfaces inline per backed branch in `renderBranches` | Collapsed-into-Branches |
| OVERVIEW first as landing tab | PLANS default (primary work surface); strip serves "what just happened" globally | PLANS default |
| Pill / underline / strip not specified | 2px bottom underline in `var(--accent)` matching `.panel-title` motif | Underline |
| Mobile collapse behavior not specified | Horizontal-scroll tablist below 700px with `scroll-snap-type: x proximity` | Scroll strip |
| Tab-state persistence "out of scope" | Include URL-hash now (~20 lines, shareable links + reload survival) | Include |
| Keyboard nav: WCAG APG arrow-keys / Home / End + roving tabindex | (refined) Mouse-first: ARIA roles + `:focus-visible` retained; arrow / Home / End handler DROPPED; no roving tabindex; rely on native `<button>` Tab order | Mouse-first |

The corresponding issue-body AC "Dashboard loads with OVERVIEW tab active
by default (showing the Recent Activity panel)" is REFRAMED in this plan as
"Dashboard loads with PLANS tab active by default AND the Recent Activity
strip visible above the tablist." The underlying invariant — *default-visible
view contains the primary-attention content surface* — is preserved.

### Tab structure (final, 3 tabs, mouse-first)

```
.topbar
  └── h1 "Z Skills Dashboard"
  └── #updated-at
#conn-banner (global)
#errors-banner (global)
#activity-strip (global, persistent)
  ├── .strip-title "Recent"
  └── #activity-body  ← renderActivity continues to write here
.tablist [role=tablist, aria-label="Dashboard sections"]
  ├── [role=tab, id=tab-plans,      aria-controls=plans,      aria-selected=true]  Plans
  ├── [role=tab, id=tab-issues,     aria-controls=issues,     aria-selected=false] Issues
  └── [role=tab, id=tab-branches,   aria-controls=branches,   aria-selected=false] Branches
#tabpanels
  ├── #plans     [role=tabpanel, aria-labelledby=tab-plans,     tabindex=0]         contains <section class="panel panel-plans">
  ├── #issues    [role=tabpanel, aria-labelledby=tab-issues,    tabindex=0, hidden] contains <section class="panel panel-issues">
  └── #branches  [role=tabpanel, aria-labelledby=tab-branches,  tabindex=0, hidden] contains <section class="panel panel-branches">
                                                                                          (renderBranches surfaces worktree info inline)
#modal-root (global, z-index 50)
```

URL hash → active-tab slug mapping:
`#plans` ↔ Plans, `#issues` ↔ Issues, `#branches` ↔ Branches.
Unknown / empty hash defaults to `#plans`. `#worktrees` is NOT a valid
slug; deep-link to `#worktrees` falls through to the default (`#plans`).

**Note on `tabindex`**: tabs are native `<button>` elements (default
`tabindex=0`); no explicit `tabindex` attribute is set on tab buttons.
The arrow-key / Home / End keyboard handler from the original WCAG APG
spec is intentionally dropped (mouse-first lock); roving `tabindex="-1"`
on inactive tabs is also dropped because it would make inactive tabs
unreachable by Tab key — undesirable in a mouse-first design that still
wants keyboard accessibility via native Tab order. All three tab buttons
are reachable by Tab; clicking (mouse or Enter/Space via native button
semantics) activates.

### Skill version bump procedure (per phase)

After every phase's content edits and BEFORE staging the commit:

```bash
today=$(TZ=America/New_York date +%Y.%m.%d)
hash=$(bash scripts/skill-content-hash.sh skills/zskills-dashboard)
bash scripts/frontmatter-set.sh skills/zskills-dashboard/SKILL.md metadata.version "${today}+${hash}"
bash scripts/mirror-skill.sh zskills-dashboard
diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/   # must be empty
git add skills/zskills-dashboard/ .claude/skills/zskills-dashboard/
```

The hash projection excludes the redacted `metadata.version` line itself,
so bumping the version does NOT cause the hash to change recursively
(verified in `scripts/skill-content-hash.sh` header). The bump is required
even when only static files change because the canonical projection
includes every regular file under the skill dir.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 0 — Worktree setup | ✅ Done | (verification) | Layer 0/3 hooks verified |
| 1 — Rename "Z Skills Monitor" → "Z Skills Dashboard" | ✅ Done | 57907a9 | All user-facing strings + test assertions in lockstep |
| 2 — Tab scaffold (HTML + CSS) | ✅ Done | 2233a91 | 3 tabs (PLANS/ISSUES/BRANCHES) + activity strip; renderBranches enriched with worktree info; renderWorktrees removed |
| 3 — Tab behavior (JS + URL hash, mouse-first) | ✅ Done | 04f945a | Click + hashchange only; no arrow-key/Home/End handler; no roving tabindex |
| 4 — Manual playwright verification + automated tests | ✅ Done | a361685 | 12+9b playwright steps + 4 screenshots; tests 2933/2933; step 9b plan-text drift documented |
| 5 — Dashboard functional fixes | ⬚ | | Investigate-first sub-sections: Origin/CSRF (5b), READY drop (5c), disconnect-flap (5d), /work-on-plans verification (5e) |

---

## Phase 0 — Worktree setup

### Goal

Establish the `feat/dashboard-tabs-rename` worktree with verifier-cannot-run
defenses (Layer 0 + Layer 3 hooks) in place before any code edits.

### Work Items

- [ ] Run `bash .claude/skills/create-worktree/scripts/create-worktree.sh dashboard-tabs-rename --pipeline-id dashboard-tabs-rename --branch-name feat/dashboard-tabs-rename` from the main checkout root. Capture the printed worktree path; all subsequent phases `cd` to that worktree.
- [ ] Verify Layer 0 hook present: `test -x .claude/hooks/inject-bash-timeout.sh && head -5 .claude/hooks/inject-bash-timeout.sh`.
- [ ] Verify Layer 3 hook present: `test -x .claude/hooks/verify-response-validate.sh && head -5 .claude/hooks/verify-response-validate.sh`.
- [ ] Verify the verifier agent definition is present and has the full tools allowlist: `grep -E '^tools:.*Read.*Grep.*Glob.*Bash.*Edit.*Write' .claude/agents/verifier.md` returns a non-empty match (exit 0).
- [ ] Verify the worktree is clean: `git status` in the worktree returns "working tree clean" and is on branch `feat/dashboard-tabs-rename` tracking `dev/feat/dashboard-tabs-rename` (or equivalent remote).
- [ ] Confirm `.claude/zskills-config.json` resolves `execution.landing` to `pr` and `execution.branch_prefix` to `feat/` (matching the landing-mode hint in this plan).

### Design & Constraints

- The worktree path is printed to stdout by `create-worktree.sh`; capture it for subsequent phases. Do NOT delete or recreate worktrees mid-plan.
- `--pipeline-id` is REQUIRED by `create-worktree.sh` (exit 5 enforcement); if you omit it, the script fails fast.
- Verifier-cannot-run rule (CLAUDE.md): if any of the four checks above fails, STOP this phase and surface the failure to the user. Do not proceed with the plan until the hooks are restored.
- This phase does NOT touch `skills/zskills-dashboard/` content. No version bump required.
- **Remediation on hook/agent check failure**: if either Layer 0 (`inject-bash-timeout.sh`) or Layer 3 (`verify-response-validate.sh`) is missing or non-executable, run `/update-zskills` from the MAIN checkout (NOT the worktree) to reinstall, then retry Phase 0. If the verifier agent definition at `.claude/agents/verifier.md` is missing or has the wrong tools allowlist, surface to the user — do NOT edit that file from within this plan. The plan does not own the verifier-agent definition.

### Acceptance Criteria

- [ ] `git worktree list` shows the `feat/dashboard-tabs-rename` branch checked out at the worktree path.
- [ ] All four hook/agent verification commands exit 0 with the expected file content.
- [ ] No `skills/zskills-dashboard/` files modified in this phase (`git diff main -- skills/zskills-dashboard/` is empty).

### Dependencies

None. This is the first phase.

---

## Phase 1 — Rename "Z Skills Monitor" → "Z Skills Dashboard"

### Goal

Replace every user-facing "Z Skills Monitor" / "Monitor" string with "Z
Skills Dashboard" / "Dashboard" across the skill source AND update test
assertion strings in lockstep. Internal identifiers (Python package name
`zskills_monitor`, `class MonitorHandler`, `monitor-state.json`,
`verify_monitor_identity()`, the process-pattern regex) are preserved.

### Work Items

- [ ] **index.html** (`skills/zskills-dashboard/scripts/zskills_monitor/static/index.html`):
  - Line 6: `<title>Z Skills Monitor</title>` → `<title>Z Skills Dashboard</title>`
  - Line 11: `<h1>Z Skills Monitor</h1>` → `<h1>Z Skills Dashboard</h1>`
- [ ] **app.js** (`skills/zskills-dashboard/scripts/zskills_monitor/static/app.js`):
  - Line 1 banner comment: `// Z Skills Monitor — interactive dashboard renderer (Phase 7).` → `// Z Skills Dashboard — interactive dashboard renderer (Phase 7).`
- [ ] **server.py** (`skills/zskills-dashboard/scripts/zskills_monitor/server.py`):
  - Line 3 module docstring: `"""zskills_monitor.server — localhost-only HTTP API for the zskills monitor."""` → `"""zskills_monitor.server — localhost-only HTTP API for the zskills dashboard."""` (keep the package name `zskills_monitor.server` — that is internal; only the prose changes).
  - Line 694 fallback HTML body: `b"<!DOCTYPE html><meta charset=utf-8><title>zskills monitor</title>..."` → `b"...<title>zskills dashboard</title>..."`
  - Line 1051 argparse description: `description="Localhost HTTP API for zskills monitor (Phase 5).",` → `description="Localhost HTTP API for the zskills dashboard (Phase 5)."`
  - Line 1115 startup log: `f"zskills monitor listening on http://{BIND_HOST}:{port} ..."` → `f"zskills dashboard listening on http://{BIND_HOST}:{port} ..."`
  - Line 545: `server_version = "zskills-monitor/0.1"` → `server_version = "zskills-dashboard/0.1"`. The HTTP `Server:` response header value. Risk-free: zero tests grep `server_version` (verified `grep -rn server_version tests/` returns no hits). Per memory anchor `feedback_no_premature_backcompat.md` ("zskills has no external consumers; prefer cleaner change"), rename rather than retain.
  - DO NOT change `class MonitorHandler` (540, 1034) — internal Python class name.
- [ ] **collect.py** (`skills/zskills-dashboard/scripts/zskills_monitor/collect.py`) — user-facing prose at module head and argparse:
  - Line 3-4 module docstring: `zskills_monitor.collect — Pure-Python aggregation library for the\nzskills monitor dashboard (Phase 4 of ZSKILLS_MONITOR_PLAN).` → `... for the\nzskills dashboard (Phase 4 of ZSKILLS_MONITOR_PLAN).` (only line 4 prose changes; the package-name `zskills_monitor.collect` stays).
  - Line 1218 argparse `prog`: `prog="python3 -m zskills_monitor.collect"` — keep unchanged (this is the displayed module path in `--help`, an internal identifier).
  - Verify by `grep -n "monitor\\|Monitor" skills/zskills-dashboard/scripts/zskills_monitor/collect.py` — surviving hits should be ONLY `zskills_monitor.collect` (Python module path, line 3, 142, 1218), `_zskills_monitor_briefing` (env-var name, line 142), and `monitor-state.json` (filename, lines 1011, 1016, 1029, 1035, 1205 — internal).
- [ ] **SKILL.md** (`skills/zskills-dashboard/SKILL.md`) — user-facing string sites:
  - Line 16 H1: `# /zskills-dashboard — Local Monitor Dashboard` → `# /zskills-dashboard — Local Dashboard`
  - Line 18 prose: `\`/zskills-dashboard\` exposes the Phase 5 Python monitor server as a` → `\`/zskills-dashboard\` exposes the Phase 5 Python dashboard server as a`
  - Line 87 prose: `worktree's monitor — do NOT kill it.` → `worktree's dashboard — do NOT kill it.`
  - Line 306 echo: `"Monitor running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)"` → `"Dashboard running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)"`
  - Line 314 doc-comment (matches the line 335 echo): `1. No PID file → "No running monitor (no PID file)." Exit 0` → `1. No PID file → "No running dashboard (no PID file)." Exit 0`
  - Line 418 doc-comment (matches the line 434 echo): `1. No PID file → "Monitor not running." Exit 0.` → `1. No PID file → "Dashboard not running." Exit 0.`
  - Line 335 echo: `"No running monitor (no PID file)."` → `"No running dashboard (no PID file)."` (kept in this position to match doc-comment 314)
  - Line 335 echo: same string as 314 → same replacement
  - Line 335 prose echo (already covered above; do NOT double-replace).
  - Line 358 echo: `"Monitor PID file is stale (PID $STOP_PID is not running). Removing $PID_FILE."` → `"Dashboard PID file is stale (PID $STOP_PID is not running). Removing $PID_FILE."`
  - Line 372 diagnostic: `"PID $STOP_PID does not appear to be zskills-monitor for this repo ..."` → `"PID $STOP_PID does not appear to be zskills-dashboard for this repo ..."`. Per `feedback_no_premature_backcompat.md`: 4-site lockstep change with the test file (sites at test:397, 729, 773 — listed in Test lockstep below) is small enough to justify consistency.
  - Line 393 echo (stderr): `"Monitor did not exit within 5s..."` → `"Dashboard did not exit within 5s..."`
  - Line 410 echo: `"Monitor stopped (pid $STOP_PID, port ${STOP_PORT:-?})."` → `"Dashboard stopped (pid $STOP_PID, port ${STOP_PORT:-?})."`
  - Line 418 doc-comment — already covered above; do NOT double-replace.
  - Line 434 echo: `"Monitor not running."` → `"Dashboard not running."` (matches line 418 doc-comment)
  - Line 465 echo (stderr): `"Monitor PID file is stale (PID $ST_PID not running). Run 'lsof -i :$ST_PORT' to verify port is free, then retry /zskills-dashboard start."` → `"Dashboard PID file is stale ..."`
  - Line 485 heredoc first line: `Monitor running at http://127.0.0.1:$ST_PORT/` → `Dashboard running at http://127.0.0.1:$ST_PORT/`
  - DO NOT change lines 10 and 514 — these reference the on-disk filename `monitor-state.json` (internal identifier; the state file is not being renamed — that would require Python migration logic outside this presentation refactor).
  - DO NOT change `metadata.*` frontmatter fields (`name`, `disable-model-invocation`, `argument-hint`, `description`) except `metadata.version` (handled by the bump step below). The `disable-model-invocation: true` flag stays — it is a Skill-tool-dispatch gate, not a product name.
- [ ] **README.md** — line 400 column: `Batch-execute prioritized ready queue from the monitor dashboard` → `Batch-execute prioritized ready queue from the dashboard`.
- [ ] **Test lockstep — `tests/test_zskills_monitor_dashboard_ui.sh`**:
  - Lines 291-292: change `'<title>Z Skills Monitor</title>'` to `'<title>Z Skills Dashboard</title>'` in both the grep and the pass message.
- [ ] **Test lockstep — `tests/test_zskills_dashboard_skill.sh`** — update the embedded function-copy echo strings and the assertion greps in lockstep with the SKILL.md changes:
  - Line 352 (do_start echo `Monitor running...`) → `Dashboard running...`
  - Line 363 (do_stop echo `No running monitor (no PID file).`) → `No running dashboard (no PID file).`
  - Line 384 (do_stop echo `Monitor PID file is stale ...`) → `Dashboard PID file is stale ...`
  - Line 397 (do_stop diagnostic echo `does not appear to be zskills-monitor for this repo`) → `does not appear to be zskills-dashboard for this repo`
  - Line 415 (do_stop echo `Monitor did not exit ...`) → `Dashboard did not exit ...`
  - Line 428 (do_stop echo `Monitor stopped ...`) → `Dashboard stopped ...`
  - Line 439 (do_status echo `Monitor not running.`) → `Dashboard not running.`
  - Line 467 (do_status echo `Monitor PID file is stale ...`) → `Dashboard PID file is stale ...`
  - Line 486 (do_status heredoc first line `Monitor running at ...`) → `Dashboard running at ...`
  - Line 522 (comment `^Monitor running`) → `^Dashboard running`
  - Lines 532-533 (grep `'^Monitor running at http://127\.0\.0\.1:'`) → `'^Dashboard running at http://127\.0\.0\.1:'`
  - Lines 572-575 (greps `'^Monitor running'`) → `'^Dashboard running'`
  - Line 729 (grep `'does not appear to be zskills-monitor'`) → `'does not appear to be zskills-dashboard'`
  - Line 773 (grep `'does not appear to be zskills-monitor for this repo'`) → `'does not appear to be zskills-dashboard for this repo'`
  - Lines 852-853 (grep `'No running monitor'`, pass message) → `'No running dashboard'`
  - Recommended idiom: a single multi-pattern `sed -i` over the file, expanded to also catch comment-prose / `pass`/`fail` message prose that uses the words "monitor" / "Monitor" in non-assertion contexts:
    ```
    sed -i \
      -e 's/Monitor running/Dashboard running/g' \
      -e 's/No running monitor/No running dashboard/g' \
      -e 's/Monitor PID file is stale/Dashboard PID file is stale/g' \
      -e 's/Monitor did not exit/Dashboard did not exit/g' \
      -e 's/Monitor stopped/Dashboard stopped/g' \
      -e 's/Monitor not running/Dashboard not running/g' \
      -e 's/does not appear to be zskills-monitor/does not appear to be zskills-dashboard/g' \
      -e 's/non-monitor process/non-dashboard process/g' \
      -e 's/is the monitor\./is the dashboard./g' \
      -e "s/second monitor/second dashboard/g" \
      -e "s/FX_B's monitor/FX_B's dashboard/g" \
      -e 's/Launch a second monitor/Launch a second dashboard/g' \
      -e 's/live monitor/live dashboard/g' \
      tests/test_zskills_dashboard_skill.sh
    ```
    Then audit: `grep -nE 'monitor|Monitor' tests/test_zskills_dashboard_skill.sh | grep -vE 'zskills_monitor\\.server|verify_monitor_identity|zskills-monitor-(server|ui|collect)-test|nohup python3 -m zskills_monitor|PKG_PARENT.*zskills_monitor|zskills_monitor/server\\.py'` MUST return ZERO lines. Any remaining prose hit is a missed rename; fix with a targeted Edit call and re-audit.
- [ ] **Sequencing — finish ALL skill-file edits before computing the hash**. The bump command reads `skills/zskills-dashboard/` from disk; if you compute the hash while edits are pending, the version line will be set to a stale value and `block-stale-skill-version.sh` will deny the commit. Required order: (a) edit all `skills/zskills-dashboard/**` files (SKILL.md, index.html, app.js, server.py); (b) edit external files (README.md, tests/); (c) compute hash; (d) write version line; (e) mirror; (f) `diff -rq`; (g) verify-no-drift smoke; (h) stage; (i) commit. Test files do NOT enter the hash projection (`scripts/skill-content-hash.sh` walks only `skills/<name>/`).
- [ ] **Bump + mirror**:
  - `today=$(TZ=America/New_York date +%Y.%m.%d)`
  - `hash=$(bash scripts/skill-content-hash.sh skills/zskills-dashboard)`
  - `bash scripts/frontmatter-set.sh skills/zskills-dashboard/SKILL.md metadata.version "${today}+${hash}"`
  - `bash scripts/mirror-skill.sh zskills-dashboard`
  - `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` returns empty.
- [ ] **Verify-no-drift smoke** (TOCTOU guard, runs immediately before `git commit`):
  ```bash
  fresh=$(bash scripts/skill-content-hash.sh skills/zskills-dashboard)
  stored=$(grep -E '^\s*version:' skills/zskills-dashboard/SKILL.md | head -1 | sed -E 's/.*"[0-9.]+\+([a-f0-9]+)".*/\1/')
  [ "$fresh" = "$stored" ] || { echo "Hash drift: fresh=$fresh stored=$stored — re-run bump"; exit 1; }
  ```
  If drift, re-run the bump+mirror block.
- [ ] **Stage + commit**:
  ```
  git add skills/zskills-dashboard/ .claude/skills/zskills-dashboard/ \
          tests/test_zskills_monitor_dashboard_ui.sh \
          tests/test_zskills_dashboard_skill.sh \
          README.md
  git commit -m "rename: Z Skills Monitor → Z Skills Dashboard (#229)"
  ```
  The commit must include the version-line edit. If `block-stale-skill-version.sh` denies the commit, run the deny envelope's suggested bump command and re-issue (per CLAUDE.md `## Skill versioning` recovery).
  **Note**: `mirror-skill.sh` mirrors only `skills/<name>/` → `.claude/skills/<name>/`. README.md and `tests/` files are staged independently — they are NOT mirrored.

### Design & Constraints

- **No behavior change**: every changed string is prose / chrome. Bash control flow, Python control flow, JS behavior all unchanged.
- **Preserve case sensitivity**: "Monitor" (capitalized) → "Dashboard" (capitalized); lowercase `monitor` in server.py prose → `dashboard`. Match case.
- **Test assertion strings must update WITH the implementation, never separately**, or the test run between rename and test-update would falsely flag the rename as a regression. The plan structures both in a single commit.
- **NEVER weaken tests** (CLAUDE.md). The test update here is not loosening — it is updating the expected-string assertions to match the new behavior. The grep patterns remain equally strict.
- **Surviving "monitor" hits after rename** are expected and load-bearing: `zskills_monitor` package, `MonitorHandler` class, `monitor-state.json`, `verify_monitor_identity`, the `python3.*zskills_monitor.server` regex, the `does not appear to be zskills-monitor for this repo` diagnostic (SKILL.md:372). Confirm before committing.

### Acceptance Criteria

- [ ] `grep -rn 'Z Skills Monitor' skills/zskills-dashboard/ .claude/skills/zskills-dashboard/ tests/test_zskills_monitor_dashboard_ui.sh tests/test_zskills_dashboard_skill.sh README.md` returns ZERO lines.
- [ ] `grep -n 'monitor dashboard' README.md` returns ZERO lines.
- [ ] `grep -rn 'Z Skills Dashboard' skills/zskills-dashboard/scripts/zskills_monitor/static/` returns at least 2 lines (title + h1).
- [ ] `grep -rinE 'zskills[- ]monitor|zskills monitor' skills/zskills-dashboard/` returns ONLY load-bearing internal hits referencing the Python module path: `zskills_monitor.server`, `zskills_monitor/server.py`, `zskills_monitor.collect`. Specifically no hit on `zskills-monitor` (hyphen form — that was renamed to `zskills-dashboard` at SKILL.md:372 and server.py:545) and no hit on `zskills monitor` (lowercase space — collect.py:4 and server.py prose all renamed). The fixture file `tests/fixtures/monitor/minimal/plans/SAMPLE_PLAN.md` line 13 is OUT-OF-SKILL-DIR and OUT-OF-SCOPE (an accepted-comment hit; the directory name `tests/fixtures/monitor/` is preserved because renaming the fixture directory has filesystem ripples beyond this presentation refactor).
- [ ] `grep -nE 'Monitor (running|stopped|not running|did not exit|PID file is stale)' skills/zskills-dashboard/SKILL.md` returns ZERO lines (capitalized "Monitor" as a noun for the product is gone).
- [ ] `grep -nE 'monitor|Monitor' skills/zskills-dashboard/SKILL.md` returns ONLY load-bearing internal hits, all referencing the on-disk filename or the Python module path: `monitor-state.json` (lines 10, 514), `zskills_monitor.server` / `zskills_monitor\.server` (Python module path / `pgrep` pattern), `verify_monitor_identity` (bash function name). No prose hits.
- [ ] `grep -nE 'Monitor|monitor' tests/test_zskills_dashboard_skill.sh | grep -vE 'zskills_monitor\\.server|verify_monitor_identity|zskills-monitor-(server|ui|collect)-test|nohup python3 -m zskills_monitor|PKG_PARENT.*zskills_monitor|zskills_monitor/server\\.py'` returns ZERO lines (no prose / comment / pass-message hits survive).
- [ ] `grep -n 'server_version' skills/zskills-dashboard/scripts/zskills_monitor/server.py` returns line 545 reading `server_version = "zskills-dashboard/0.1"`.
- [ ] `grep -nE 'Monitor|monitor' skills/zskills-dashboard/scripts/zskills_monitor/collect.py` returns ONLY load-bearing internal hits: `zskills_monitor.collect` (module path, lines 3, 142, 1218), `_zskills_monitor_briefing` (env var, 142), `monitor-state.json` (filename, 1011/1016/1029/1035/1205). No prose hits.
- [ ] `bash tests/test_zskills_monitor_dashboard_ui.sh` passes (lines 141-147 panel-class loop still matches all 5 panels — `panel-activity` is NOT removed in this phase; line 291-292 title grep now matches "Z Skills Dashboard").
- [ ] `bash tests/test_zskills_dashboard_skill.sh` passes (echo-string asserts now match "Dashboard" variants and `zskills-dashboard` diagnostic).
- [ ] The verify-no-drift smoke (fresh hash == stored hash) passed before the commit.
- [ ] `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` is empty.
- [ ] The commit was accepted by `block-stale-skill-version.sh` (i.e., no deny envelope re-issued the commit).

### Dependencies

Phase 0 (worktree on `feat/dashboard-tabs-rename`).

---

## Phase 2 — Tab scaffold (HTML + CSS)

### Goal

Restructure `index.html` to host (a) a new persistent `#activity-strip`
section above the tablist, (b) a `<nav role="tablist">` with **three tab
buttons (PLANS / ISSUES / BRANCHES)**, and (c) three `<section
role="tabpanel">` wrappers around the existing Plans / Issues / Branches
panels. The former Worktrees panel is **removed entirely**; its data
folds into the Branches tab by enriching `renderBranches` to surface
worktree info (path basename, age, landed-status pill) inline per backed
branch. Add the corresponding CSS (tab visual styling, activity-strip
layout, hidden-panel rule). Remove the old `.grid` rule body and the
`@media (min-width:900px) { grid-template-areas... }` block. This phase
introduces a **small** JS change: `renderBranches` is enriched and
`renderWorktrees` / `fingerprintWorktrees` are deleted. Tab switching
behavior (click handler, hashchange listener) is wired in Phase 3.
Hidden tabpanels are hidden by static markup at this stage.

### Work Items

- [ ] **index.html** — restructure document body. Final structure (between
  `<body>` and `</body>`):

  ```html
  <header class="topbar">
    <h1>Z Skills Dashboard</h1>
    <div class="topbar-meta">
      <span id="updated-at" class="muted" aria-live="polite"></span>
    </div>
  </header>

  <div id="conn-banner" class="conn-banner" hidden>
    Disconnected &mdash; retrying&hellip;
  </div>

  <section id="errors-banner" class="errors-banner" hidden aria-label="Snapshot errors">
    <ul id="errors-list" class="errors-list"></ul>
  </section>

  <div id="toast-region" class="toast-region" aria-live="polite" role="status"></div>

  <section id="activity-strip" class="activity-strip" aria-label="Recent activity">
    <h2 class="strip-title">Recent</h2>
    <div id="activity-body" class="activity-strip-body"></div>
    <p id="activity-empty" class="empty muted" hidden>No recent activity.</p>
  </section>

  <nav class="tablist" role="tablist" aria-label="Dashboard sections" aria-orientation="horizontal">
    <button type="button" role="tab" id="tab-plans"     aria-controls="plans"     aria-selected="true">Plans</button>
    <button type="button" role="tab" id="tab-issues"    aria-controls="issues"    aria-selected="false">Issues</button>
    <button type="button" role="tab" id="tab-branches"  aria-controls="branches"  aria-selected="false">Branches</button>
  </nav>

  <main id="tabpanels" class="tabpanels">
    <div role="tabpanel" id="plans" aria-labelledby="tab-plans" tabindex="0">
      <section class="panel panel-plans" aria-label="Plans">
        <div class="panel-head">
          <h2 class="panel-title">Plans</h2>
          <div class="plans-controls">
            <div id="default-mode-area" class="default-mode-area">
              <span class="muted" id="default-mode-label">Default mode:</span>
              <div class="seg" role="group" aria-labelledby="default-mode-label">
                <button type="button" id="dm-phase" class="seg-btn" aria-pressed="false">Phase-by-phase</button>
                <button type="button" id="dm-finish" class="seg-btn" aria-pressed="false">Finish (one PR)</button>
              </div>
              <span id="default-mode-footnote" class="dm-footnote muted" hidden>
                Sprint in flight: change applies to plans not yet dispatched and to future sprints; in-flight plans keep their captured mode.
              </span>
            </div>
          </div>
        </div>
        <div id="run-status" class="run-status" aria-label="Run status"></div>
        <div id="plans-body" class="panel-body"></div>
        <p id="plans-empty" class="empty muted" hidden>No plans found.</p>
        <div id="plans-live" class="sr-only" aria-live="polite"></div>
      </section>
    </div>

    <div role="tabpanel" id="issues" aria-labelledby="tab-issues" tabindex="0" hidden>
      <section class="panel panel-issues" aria-label="Issues">
        <h2 class="panel-title">Issues</h2>
        <div id="issues-body" class="panel-body"></div>
        <p id="issues-empty" class="empty muted" hidden>No open issues.</p>
        <div id="issues-live" class="sr-only" aria-live="polite"></div>
      </section>
    </div>

    <div role="tabpanel" id="branches" aria-labelledby="tab-branches" tabindex="0" hidden>
      <section class="panel panel-branches" aria-label="Branches">
        <h2 class="panel-title">Branches</h2>
        <div id="branches-body" class="panel-body"></div>
        <p id="branches-empty" class="empty muted" hidden>No branches.</p>
      </section>
    </div>
  </main>

  <div id="modal-root" class="modal-root" hidden role="dialog" aria-modal="true" aria-labelledby="modal-title">
    <div class="modal-backdrop" id="modal-backdrop"></div>
    <div class="modal-card" id="modal-card" tabindex="-1">
      <header class="modal-head">
        <h2 id="modal-title" class="modal-title">&nbsp;</h2>
        <button id="modal-close" class="modal-close" aria-label="Close">&times;</button>
      </header>
      <div id="modal-body" class="modal-body"></div>
    </div>
  </div>

  <script type="module" src="/app.js"></script>
  ```

  Notes:
  - The **old `panel-activity` section is removed** from `<main>` — its
    body (`#activity-body`, `#activity-empty`) is relocated into
    `#activity-strip`. The `renderActivity` function (app.js:846-875) is
    unchanged; it still writes to `#activity-body`.
  - The **old `panel-worktrees` section is REMOVED entirely** from
    `<main>`. The worktree data (path/age/landed-status) is folded into
    the Branches tab via `renderBranches` enrichment (see app.js work
    item below).
  - The three remaining `<section class="panel panel-{plans,issues,branches}">`
    elements are moved verbatim into their respective `role="tabpanel"`
    wrappers. Their internal structure (panel-head, panel-body, slot
    IDs, sr-only live regions) is preserved byte-for-byte.

- [ ] **app.css** — three categories of change:
  1. **Delete** the `.grid` rule body (lines 89-96) AND the `@media
     (min-width: 900px) { .grid { grid-template-columns: ...;
     grid-template-areas: ... } .panel-* { grid-area: ... } }` block
     (lines 98-110) in their entirety. The `.grid` class no longer
     applies to `<main>`; the panel-area assignments are dead.
  2. **Add** `#activity-strip` styling. Insert after the topbar block:
     ```css
     .activity-strip {
       background: var(--surface);
       border-bottom: 1px solid var(--border);
       padding: 8px 24px;
       max-width: 1600px;
       margin: 0 auto;
       display: grid;
       grid-template-columns: max-content 1fr;
       gap: 12px;
       align-items: start;
       max-height: 140px;
       overflow-x: hidden;
       overflow-y: auto;
     }
     .strip-title {
       margin: 0;
       font-size: 0.75rem;
       text-transform: uppercase;
       letter-spacing: 0.06em;
       color: var(--text-dim);
       align-self: center;
     }
     .activity-strip-body {
       display: flex;
       flex-direction: column;
       gap: 4px;
       min-width: 0;          /* Allow grid track to shrink below content min */
     }
     .activity-strip-body .activity-row { min-width: 0; }
     .activity-strip-body .activity-row > * {
       min-width: 0;
       overflow: hidden;
       text-overflow: ellipsis;
       white-space: nowrap;
     }
     ```
     The `overflow-x: hidden` plus the cascading `min-width: 0` + ellipsis
     pattern prevents a long activity message (e.g. a long plan slug or
     phase name) from pushing horizontal scroll into the strip. Default
     grid `1fr` tracks have `min-width: auto`, which expands to fit
     content; the `min-width: 0` overrides that.
  3. **Add** `.tablist`, `.tab` (button), and `.tabpanels` / `.tabpanel`
     styling. Insert as a new section:
     ```css
     .tablist {
       display: flex;
       gap: 4px;
       padding: 0 24px;
       background: var(--surface);
       border-bottom: 1px solid var(--border);
       max-width: 1600px;
       margin: 0 auto;
       overflow-x: auto;
       scrollbar-width: thin;
       scroll-snap-type: x proximity;
     }
     .tab {
       background: transparent;
       border: none;
       border-bottom: 2px solid transparent;
       color: var(--text-dim);
       font-family: inherit;
       font-size: 0.85rem;
       text-transform: uppercase;
       letter-spacing: 0.06em;
       padding: 10px 16px;
       cursor: pointer;
       flex-shrink: 0;
       scroll-snap-align: start;
       white-space: nowrap;
     }
     .tab:hover {
       color: var(--text);
       border-bottom-color: var(--border);
     }
     .tab[aria-selected="true"] {
       color: var(--text);
       border-bottom-color: var(--accent);
       font-weight: 600;
     }
     .tab:focus-visible {
       outline: none;
       box-shadow: 0 0 0 2px rgba(88, 166, 255, 0.4);
       border-radius: 2px 2px 0 0;
     }
     .tabpanels {
       padding: 16px 24px;
       max-width: 1600px;
       margin: 0 auto;
       display: block;
     }
     .tabpanel { display: block; }
     .tabpanel[hidden] { display: none; }
     @media (max-width: 700px) {
       .tablist { padding: 0 12px; }
       .tab { padding: 10px 12px; }
       .activity-strip { padding: 8px 12px; }
       .tabpanels { padding: 12px; }
     }
     ```
     The `.tabpanel[hidden] { display: none; }` rule is defensive — it
     mirrors the precedent at app.css:272-277 where `.modal-root[hidden]`
     needed an explicit override to defeat a more-specific `display:flex`
     rule. Without this, future CSS edits could silently leave hidden
     panels visible.

  Do NOT modify `.panel`, `.panel-title`, `.panel-body`, `.panel-head`,
  `.columns`, `.pill`, `.seg`, `.activity-row`, `.modal-*`, or any other
  existing rule. The grid layout is the only structural change.

- [ ] **app.js — `renderBranches` enrichment + `renderWorktrees` removal**.
  Two coupled edits in the same commit. The Branches tab now owns the
  worktree-info display surface.

  1. **Add `worktreesByBranch(worktrees)` helper** near
     `backedBranchSet` (existing at lines 646-652). Suggested location:
     immediately after `backedBranchSet`.
     ```js
     function worktreesByBranch(worktrees) {
       const m = new Map();
       for (const w of worktrees || []) {
         if (w && w.branch) m.set(w.branch, w);
       }
       return m;
     }
     ```
     `backedBranchSet` is RETAINED — `renderBranches` still uses it to
     set the `card dim` class on backed branches (existing behavior at
     line 667). The new helper provides the per-branch worktree object
     lookup for inline info display.

  2. **Enrich `renderBranches(branches, worktrees)`** (existing at
     lines 654-690) to render a worktree-info sub-row inside each branch
     card that has a backing worktree. Construct the new sub-row using
     `textContent`/`appendChild` only — NO `innerHTML`. The existing
     card structure (title, last_commit_at, last_commit_subject,
     upstream) is preserved; the worktree sub-row appends AFTER the
     existing rows when present.
     ```js
     const byBranch = worktreesByBranch(worktrees);
     // ... existing per-branch loop ...
     const w = byBranch.get(b.name);
     if (w) {
       const status = w.landed ? w.landed.status : "not-landed";
       const wtRow = el("div", { cls: "card-row card-worktree-row" });
       wtRow.appendChild(el("span", {
         cls: "pill " + landedPillClass(status),
         text: status,
       }));
       if (w.path) {
         wtRow.appendChild(el("span", { cls: "mono card-sub", text: basename(w.path) }));
       }
       if (typeof w.age_seconds === "number") {
         wtRow.appendChild(el("span", {
           cls: "card-sub",
           text: ageSecondsToText(w.age_seconds),
         }));
       }
       card.appendChild(wtRow);
     }
     ```
     **Accessor + helper reuse — MANDATORY** (verified against current
     `renderWorktrees` body at app.js:798-834):
     - Landed status is `w.landed ? w.landed.status : "not-landed"` —
       `w.landed` is an OBJECT (or absent), NOT a string field
       `w.landed_status`. See app.js:820.
     - `landedPillClass(status)` (defined at app.js:791-796) — REUSE,
       do NOT duplicate the status→class mapping inline.
     - `basename(path)` (defined at app.js:89) — REUSE, do NOT
       open-code `path.split("/").filter(Boolean).pop()`.
     - `ageSecondsToText` is the existing helper used by
       `renderWorktrees`; reuse it (do NOT duplicate).

  3. **Delete `renderWorktrees`** (current lines 798-834) entirely. With
     no callers remaining (the Worktrees tab is gone, the worktree data
     is consumed by `renderBranches`), this function is dead code.
     **RETAIN** `landedPillClass` (app.js:791-796) and `basename`
     (app.js:89) — both are reused by the enriched `renderBranches`
     above. Do NOT remove them along with `renderWorktrees`.

  4. **Delete `fingerprintWorktrees`** (current line 381) entirely.

  5. **Update `applySnapshot`** (current lines 262-266) to drop the
     worktrees branch. The function currently dispatches per-key into
     `lastFingerprint` and calls `renderWorktrees(s.worktrees)`; remove
     the worktrees-key arm of that dispatch. `s.worktrees` is still
     passed to `renderBranches(s.branches, s.worktrees)` — that becomes
     the single consumer of `/api/state.worktrees`.

  6. **Remove `lastFingerprint.worktrees`** at the module-state
     declaration (current line 114) — the field is dead with
     `fingerprintWorktrees` gone.

  Verify the edits with:
  ```bash
  grep -n "renderWorktrees\|fingerprintWorktrees\|lastFingerprint.worktrees" \
    skills/zskills-dashboard/scripts/zskills_monitor/static/app.js
  # Must return ZERO lines.
  grep -n "worktreesByBranch" \
    skills/zskills-dashboard/scripts/zskills_monitor/static/app.js
  # Must return 2 lines (definition + use in renderBranches).
  grep -nE 'function (landedPillClass|basename)\b' \
    skills/zskills-dashboard/scripts/zskills_monitor/static/app.js
  # Must return 2 lines (1 per helper) — both retained for renderBranches reuse.
  ```

- [ ] **app.css — landed-status pill classes**. The three
  `.pill-landed-{full,partial,not}` classes ALREADY EXIST at
  app.css:213-215 (used today by `renderWorktrees`):
  ```css
  .pill-landed-full     { color: var(--green); border-color: var(--green); }
  .pill-landed-partial  { color: var(--orange); border-color: var(--orange); }
  .pill-landed-not      { color: var(--text-dim); border-color: var(--border); }
  ```
  Do NOT duplicate. Update in place ONLY if Phase 2's visual design
  requires a tweak (none is required for parity with current
  appearance). Add only the new card-row helper class:
  ```css
  .card-worktree-row .mono { font-size: 0.8em; }
  ```
  AC: `grep -cE '^\.pill-landed-(full|partial|not)' skills/zskills-dashboard/scripts/zskills_monitor/static/app.css`
  returns exactly `3` (no net add, no removal).

- [ ] **Initial visibility correctness check** (after JS edits): open
  the page with `python3 -m zskills_monitor.server --port 8080
  --main-root "$(git rev-parse --show-toplevel)"` and confirm the Plans
  tabpanel is visible (since its tab has `aria-selected="true"` and the
  tabpanel is NOT `hidden`) while Issues / Branches are hidden (they
  have the `hidden` attribute). Confirm the Branches panel, when made
  visible by removing its `hidden` attribute via DevTools, renders
  worktree info sub-rows for branches with backing worktrees. Tab clicks
  don't switch tabs yet — that's Phase 3.

- [ ] **Version bump + mirror + verify-no-drift + commit**:
  - `today=$(TZ=America/New_York date +%Y.%m.%d)`
  - `hash=$(bash scripts/skill-content-hash.sh skills/zskills-dashboard)`
  - `bash scripts/frontmatter-set.sh skills/zskills-dashboard/SKILL.md metadata.version "${today}+${hash}"`
  - `bash scripts/mirror-skill.sh zskills-dashboard`
  - `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` returns empty.
  - Verify-no-drift smoke (per Phase 1 pattern).
  - `git add skills/zskills-dashboard/ .claude/skills/zskills-dashboard/ tests/test_zskills_monitor_dashboard_ui.sh`
  - `git commit -m "tabs(dashboard): HTML+CSS scaffold for tab navigation (#229)"`

### Design & Constraints

- **Slot-element IDs**: `#plans-body`, `#issues-body`, `#branches-body`,
  `#activity-body` (PRESERVED). `#worktrees-body` is REMOVED along with
  the worktrees panel. `renderPlans`, `renderIssues`, `renderActivity`
  continue to write to their existing slots. `renderBranches` writes to
  `#branches-body` (now with enriched per-card content).
- **Class names on panel sections (3 entries)**: `panel panel-plans`,
  `panel panel-issues`, `panel panel-branches`. `panel-worktrees` and
  `panel-activity` are REMOVED (worktrees panel deleted; activity moved
  to `#activity-strip` with its own classes). The test loop at
  `test_zskills_monitor_dashboard_ui.sh:141-147` updates to 3 entries in
  lockstep — see "Test lockstep" below.
- **`#main` ID is renamed to `#tabpanels`** with `class="tabpanels"`. The
  old `id="grid" class="grid"` on the `<main>` element is gone. Any JS
  reference to `#grid` (none expected — verify via `grep -nE
  "getElementById\\(.grid|\\#grid" skills/zskills-dashboard/scripts/`)
  would need update; if found, treat as a Phase 2 work item.
- **Test lockstep** — `tests/test_zskills_monitor_dashboard_ui.sh:141-147`
  currently iterates over `panel-plans panel-issues panel-worktrees
  panel-branches panel-activity` (5 entries). Update the test's array
  to `panel-plans panel-issues panel-branches` (**3 entries**):
  `panel-activity` drops because it became `#activity-strip` outside
  `.panel`; `panel-worktrees` drops because the Worktrees panel is
  deleted entirely (data folds into `renderBranches`). This is a test
  update reflecting deliberate restructure, not weakening. Add NEW
  assertions in the same test:
  - `grep -q 'id="activity-strip"' "$INDEX_HTML"` with pass message
    `"AC: activity-strip present"`.
  - `! grep -q 'panel-worktrees\|id="worktrees-body"\|id="tab-worktrees"' "$INDEX_HTML"`
    with pass message `"AC: worktrees panel removed from index.html"`.
  - Line 346 (currently asserts `"worktrees"` appears in `/api/state` JSON)
    is RETAINED unchanged — `/api/state.worktrees` continues to ship as
    server data; only the client-side dedicated panel is removed.
- **Other tests unchanged**: `test_zskills_dashboard_skill.sh`,
  `test_zskills_monitor_collect.sh`, `test_zskills_monitor_server.sh` —
  none grep for `panel-activity`, `panel-worktrees`, or the `.grid` rule.
  Verify by `grep -nE 'panel-activity|panel-worktrees|class="grid"' tests/`
  before committing.
- **Polling preservation**: the rendered DOM structure inside each tab is
  unchanged for Plans / Issues / Branches. `pollOnce()` (app.js:189)
  continues to find the surviving slot IDs (`#plans-body`,
  `#issues-body`, `#branches-body`, `#activity-body`) regardless of
  which tab is active. The Worktrees panel slot (`#worktrees-body`)
  no longer exists; `renderWorktrees` is deleted; `applySnapshot` no
  longer dispatches into a worktrees-fingerprint arm. `renderBranches`
  is called with `(s.branches, s.worktrees)` and consumes both.

### Acceptance Criteria

- [ ] `grep -c 'role="tab"' skills/zskills-dashboard/scripts/zskills_monitor/static/index.html` returns **3**.
- [ ] `grep -c 'role="tabpanel"' skills/zskills-dashboard/scripts/zskills_monitor/static/index.html` returns **3**.
- [ ] `grep -c 'role="tablist"' skills/zskills-dashboard/scripts/zskills_monitor/static/index.html` returns 1.
- [ ] `grep -E 'id="(activity-strip|plans|issues|branches)"' skills/zskills-dashboard/scripts/zskills_monitor/static/index.html` returns **4** lines (one per ID).
- [ ] `grep -nE 'id="(worktrees|worktrees-body|tab-worktrees)"|panel-worktrees|aria-controls="worktrees"' skills/zskills-dashboard/scripts/zskills_monitor/static/index.html` returns ZERO lines (worktrees-related markup removed).
- [ ] `grep -nE 'grid-template-areas|\.panel-plans\s*\{|\.panel-branches\s*\{|\.panel-issues\s*\{|\.panel-worktrees\s*\{|\.panel-activity\s*\{' skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` returns ZERO lines (the old `.panel-* { grid-area: X }` rules at lines 105-109 in the pre-refactor file, and the `grid-template-areas` declaration at line 102, are all removed).
- [ ] `grep -nE '\.tablist|\.tab\[aria-selected|\.tabpanel\[hidden\]' skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` returns at least 3 hits (new tab CSS in place).
- [ ] `grep -nE '\.pill-landed-(full|partial|not)' skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` returns 3 hits (new landed-status pill classes).
- [ ] **app.js worktree-removal sentinel**:
      `grep -nE 'renderWorktrees|fingerprintWorktrees|lastFingerprint\.worktrees' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` returns ZERO lines.
- [ ] **app.js renderBranches enrichment sentinel**:
      `grep -nE 'worktreesByBranch|pill-landed-(full|partial|not)' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` returns at least 2 hits (helper + pill class application).
- [ ] **Render-pipeline preservation for surviving functions** — the four surviving render functions (`renderPlans`, `renderIssues`, `renderActivity`, plus the new fingerprint set `fingerprintPlans`, `fingerprintBranches`, `fingerprintIssues`, `fingerprintActivity`) have unchanged bodies. `renderBranches` body changes deliberately (enrichment). Verify with:
  ```bash
  for fn in renderPlans renderIssues renderActivity fingerprintPlans fingerprintBranches fingerprintIssues fingerprintActivity; do
    diff <(git show main:skills/zskills-dashboard/scripts/zskills_monitor/static/app.js | awk -v fn="$fn" '/^function /{p=0} $0 ~ "^function " fn "\\("{p=1} p') \
         <(awk -v fn="$fn" '/^function /{p=0} $0 ~ "^function " fn "\\("{p=1} p' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js) \
      || { echo "$fn body diverged"; exit 1; }
  done
  ```
  Returns clean (no `xxx body diverged` line). `renderWorktrees` and `fingerprintWorktrees` are NOT in this list because they are deleted entirely; their absence is checked by the worktree-removal sentinel above. `renderBranches` is NOT in this list because the enrichment is the entire point of Phase 2.
- [ ] `bash tests/test_zskills_monitor_dashboard_ui.sh` passes with the updated panel-class loop (**3 entries**: panel-plans, panel-issues, panel-branches) AND the new `activity-strip` assertion AND the new worktree-removal assertion.
- [ ] `grep -cE '^[[:space:]]*\.\w+\s*\{' skills/zskills-dashboard/scripts/zskills_monitor/static/index.html` returns 0 (no inline `<style>` regression).
- [ ] No `setInterval`, no `eval(`, no `innerHTML =` introduced (`grep -nE 'setInterval|innerHTML\s*=|\beval\(' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js | grep -v '// chrome-only'` returns ZERO hits).
- [ ] Re-assert rename is intact: `grep -rn 'Z Skills Monitor' skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` returns ZERO lines (guards against accidentally re-introducing the old string while pasting the new HTML body).
- [ ] `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` is empty after mirror.

### Dependencies

Phase 1 (rename) — the H1 string in the new HTML body relies on the rename
being complete.

---

## Phase 3 — Tab behavior (JS + URL hash, mouse-first)

### Goal

Wire up tab switching with a **mouse-first** design: click handler,
`aria-selected` management, `hidden` flip on tabpanels, and URL-hash
routing via `hashchange` + `history.replaceState`. **No arrow-key /
Home / End keyboard handler. No roving tabindex.** Native `<button>`
Tab-order behavior is sufficient for keyboard reachability; native
button Enter/Space-to-click handles activation. No changes to poll
plumbing, fingerprint diff, or surviving render functions.

### Work Items

- [ ] **app.js — add a `Tabs` module-scope block** near the existing
  `boot()` and module-scope state (around lines 120-130 / 1694-1699). The
  code must use `textContent` / DOM APIs only — no `innerHTML`. Suggested
  shape (specific to this codebase):

  ```js
  // ─── Tab navigation (mouse-first; click + hashchange only) ───
  const TAB_SLUGS = ["plans", "issues", "branches"];

  function readTabFromHash() {
    const h = (location.hash || "").replace(/^#/, "");
    return TAB_SLUGS.includes(h) ? h : "plans";
  }

  function setActiveTab(slug, { pushHash = true } = {}) {
    if (!TAB_SLUGS.includes(slug)) slug = "plans";
    for (const s of TAB_SLUGS) {
      const tab = document.getElementById("tab-" + s);
      const panel = document.getElementById(s);
      if (!tab || !panel) continue;
      const isActive = (s === slug);
      tab.setAttribute("aria-selected", isActive ? "true" : "false");
      if (isActive) {
        panel.removeAttribute("hidden");
      } else {
        panel.setAttribute("hidden", "");
      }
    }
    if (pushHash && location.hash !== "#" + slug) {
      history.replaceState(null, "", "#" + slug);
    }
  }

  function bindTabEvents() {
    const tablist = document.querySelector('[role="tablist"]');
    if (!tablist) return;
    // Click handler — native <button> handles Enter/Space → click automatically.
    tablist.addEventListener("click", (ev) => {
      const btn = ev.target.closest('[role="tab"]');
      if (!btn) return;
      const slug = btn.getAttribute("aria-controls");
      if (slug) setActiveTab(slug);
    });
    // hashchange (browser back/forward, or external link)
    window.addEventListener("hashchange", () => {
      setActiveTab(readTabFromHash(), { pushHash: false });
    });
  }
  ```

  Note the deliberate omissions:
  - No `keydown` handler. Arrow / Home / End navigation is OUT OF SCOPE
    (mouse-first lock).
  - No `tabIndex` management. Tabs are plain `<button>` elements with
    browser-default tab order. All three tabs are reachable by Tab key;
    `:focus-visible` styles in app.css indicate keyboard focus.
  - No `focus: true` argument on `setActiveTab` calls. The click handler
    intentionally does not move focus on click — the user already
    interacted with the tab to trigger the click, so focus management
    is the browser's job.

- [ ] **app.js — `boot()` integration**. The current `boot()` body
  (verified at lines 1694-1699) is:
  ```js
  function boot() {
    modalInit();
    bindActionEvents();
    schedulePoll(0);
    scheduleWorkPoll(0);
  }
  ```
  Insert two new lines BETWEEN `bindActionEvents();` and
  `schedulePoll(0);` (i.e., at the line currently numbered 1697 — text
  context: just after `bindActionEvents();`, just before
  `schedulePoll(0);`):
  ```js
  function boot() {
    modalInit();
    bindActionEvents();
    bindTabEvents();                                       // NEW
    setActiveTab(readTabFromHash(), { pushHash: false });  // NEW
    schedulePoll(0);
    scheduleWorkPoll(0);
  }
  ```
  Position matters: tabs must initialize before the first poll so the
  first render writes into a tabpanel whose initial visibility matches
  the URL hash.

- [ ] **Flash-mitigation for hash deep-link** (e.g. `/#branches`). Note:
  for `<script type="module">`, ES module scripts are deferred and
  evaluated AFTER initial paint of the parsed DOM. This means JS-only
  flash mitigation is best-effort — the first paint may briefly show
  `#plans` before `setActiveTab(readTabFromHash())` flips visibility.
  For a real no-flash deep-link, the proper fix is server-side OR an
  inline non-module `<script>` in `<head>` that toggles a `<html>`
  class before paint. That is OUT OF SCOPE for this presentation
  refactor (first-pass).
  Within scope: still add an inline early-init for the (rare) case
  where the module evaluates before paint and to call `setActiveTab`
  ASAP after `bindTabEvents` is defined. Place the call between the
  `bindTabEvents`/`setActiveTab` function definitions (which go at
  end-of-file, immediately BEFORE `function boot()` per Work Item
  above) AND the existing `boot()` definition:
  ```js
  // Inline initialization — best-effort flash mitigation. Module
  // scripts defer to after parse, so this often runs after first
  // paint; the boot() call (which also runs setActiveTab) is the
  // authoritative initializer. setActiveTab is idempotent; the
  // console.warn surfaces unexpected failures rather than swallowing.
  if (typeof document !== "undefined" && document.readyState !== "loading") {
    try { setActiveTab(readTabFromHash(), { pushHash: false }); }
    catch (e) { console.warn("tab-init early call failed:", e); }
  }
  ```
  The Phase 4 deep-link AC (step 9) accepts "end-state correct, brief
  sub-200ms transient frame acceptable" — explicitly NOT a strict
  no-flash assertion.

- [ ] **NO changes to**: `pollOnce`, `schedulePoll`, `pollAbort`,
  `visibilitychange` handler, `applySnapshot`, any `render*` function,
  any `fingerprint*` function, any modal-related function, drag-and-drop
  wiring. Verify by `git diff` review before committing.

- [ ] **Verify XSS policy**: the new code uses `getElementById`,
  `setAttribute`, `removeAttribute`, `tabIndex` property access — no
  `innerHTML`, no `eval`, no `Function`, no template-string DOM injection.

- [ ] **Version bump + mirror + verify-no-drift + commit**:
  - `today=$(TZ=America/New_York date +%Y.%m.%d)`
  - `hash=$(bash scripts/skill-content-hash.sh skills/zskills-dashboard)`
  - `bash scripts/frontmatter-set.sh skills/zskills-dashboard/SKILL.md metadata.version "${today}+${hash}"`
  - `bash scripts/mirror-skill.sh zskills-dashboard`
  - `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` returns empty.
  - Verify-no-drift smoke (immediately before commit):
    ```bash
    fresh=$(bash scripts/skill-content-hash.sh skills/zskills-dashboard)
    stored=$(grep -E '^\s*version:' skills/zskills-dashboard/SKILL.md | head -1 | sed -E 's/.*"[0-9.]+\+([a-f0-9]+)".*/\1/')
    [ "$fresh" = "$stored" ] || { echo "Hash drift: fresh=$fresh stored=$stored"; exit 1; }
    ```
  - `git add skills/zskills-dashboard/ .claude/skills/zskills-dashboard/`
  - `git commit -m "tabs(dashboard): JS state, click handler, URL-hash routing (#229)"`
  - Use explicit `git add` (NOT `git commit -am`) so newly-created mirror files under `.claude/skills/zskills-dashboard/` are staged. `-am` only restages tracked-and-modified files and misses new files.

### Design & Constraints

- **Mouse-first activation**. Tab switching is driven by click events on
  `<button>` tabs. Native `<button>` semantics translate keyboard
  Enter / Space into click events, so keyboard users can activate the
  currently-focused tab without any explicit `keydown` handler.
- **No roving tabindex**. All three tabs have browser-default `tabindex`
  (native `<button>` is 0). Tab key traverses them in DOM order. This
  is a deliberate departure from the WCAG APG arrow-key pattern: the
  user's design lock specifies mouse-first; arrow-key tablist navigation
  is OUT OF SCOPE. The tradeoff: Tab cycles through all three tab
  buttons before reaching the active tabpanel's content (an extra two
  Tab presses vs. roving tabindex). This is acceptable for a
  mouse-first dashboard.
- **`history.replaceState` not `pushState`** — tab switches should not
  pollute the back-stack with one entry per click. Reload-survival is
  the goal; navigation history is not.
- **`hashchange` listener is read-only** — when it fires (e.g., from
  external link or back/forward), call `setActiveTab(slug, { pushHash:
  false })` to avoid re-firing the listener via the same call's
  `replaceState`.
- **Polling untouched**: tab switching is DOM-only. The 2s poll loop
  continues to render into the surviving slot elements (Plans, Issues,
  Branches, Activity). Hidden tabpanels still receive DOM writes; the
  browser does not paint them but JS work proceeds normally, and
  `fingerprintPlans`-style diff suppression keeps the work cheap.
- **Tab key behavior after the tablist** is governed by natural DOM
  order. From the active tab, Tab advances to the next tab button (not
  yet into the tabpanel), then the next, then exits the tablist and
  enters the active tabpanel (`tabindex="0"` is retained on each
  tabpanel container — this gives a focus target when the panel is
  empty AND lets screen-reader users read the panel as a whole before
  drilling into content). Phase 4 step 3 accepts this Tab order without
  asserting roving behavior.

### Acceptance Criteria

- [ ] `grep -nE 'bindTabEvents\(\)|setActiveTab\(.*pushHash.*false' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` returns at least 2 hits inside `boot()`.
- [ ] `grep -nE 'TAB_SLUGS\s*=\s*\[' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` shows exactly one definition with three slug entries (`plans`, `issues`, `branches` — no `worktrees`).
- [ ] **Keyboard handler NOT present**: `grep -nE "addEventListener\\(\"keydown\"|ArrowLeft|ArrowRight" skills/zskills-dashboard/scripts/zskills_monitor/static/app.js | grep -v '// '` returns ZERO hits in the new tab code. (Other unrelated keydown handlers elsewhere in app.js may exist — Phase 3 must not add new ones in the tablist surface.)
- [ ] **Roving tabindex NOT applied**: `grep -nE 'tab\.tabIndex\s*=\s*(-1|0)' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` returns ZERO hits.
- [ ] `grep -nE 'setInterval|innerHTML\s*=|eval\(' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js | grep -v '// chrome-only'` returns ZERO hits.
- [ ] Manually exercised via playwright in Phase 4: (a) clicking each tab makes its panel visible and others hidden; (b) `aria-selected` updates correctly on each switch; (c) URL hash updates to `#<slug>` and reload restores the same tab; (d) drag-drop within Plans tab still works; (e) modal still opens from inside a tab; (f) Disconnect banner appears when server is killed regardless of active tab.
- [ ] `grep -nE 'pollOnce|schedulePoll|visibilitychange' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` shows the same set of definitions as before the phase. Surviving fingerprint definitions match the Phase-2 line (`fingerprintPlans`, `fingerprintBranches`, `fingerprintIssues`, `fingerprintActivity` — no `fingerprintWorktrees`). New code only ADDS `bindTabEvents`, `setActiveTab`, `readTabFromHash`, `TAB_SLUGS`.
- [ ] `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` is empty after mirror.

### Dependencies

Phase 2 (HTML scaffold + CSS). The tab buttons and tabpanel elements must
exist before the JS can bind to them.

---

## Phase 4 — Manual playwright-cli verification + automated tests

### Goal

Verify the rename + tabs work end-to-end with real mouse/keyboard events
via `playwright-cli`, capture screenshots, run the full automated test
suite, and confirm zero regressions. This phase MUST complete before
landing — per CLAUDE.md, manual testing catches issues that pure
test-suite passing does not (RPG incident).

**Verification is dispatched, not self-executed.** The implementing agent
does NOT run the playwright checklist itself. Per CLAUDE.md
"Verifier-cannot-run rule," the orchestrator dispatches a fresh
`verifier` subagent (`subagent_type: "verifier"`, defined at
`.claude/agents/verifier.md`) with the manual checklist below as its
prompt; the verifier's response is piped through
`bash .claude/hooks/verify-response-validate.sh`; a non-zero exit means
STOP and surface to the user. Inline self-verification by the
implementing agent is an anti-pattern.

### Work Items

- [ ] **Start the dev server** in the worktree. Use the raw Python entry
  with **`--main-root "$(git rev-parse --show-toplevel)"`** so the PID file is written under the
  worktree's `.zskills/` (NOT the main checkout's). NOT the
  `/zskills-dashboard` slash command (which has
  `disable-model-invocation: true` and cannot be dispatched via the
  Skill tool, per memory anchor `feedback_skill_invocation_flags.md`):
  ```bash
  # Port-collision pre-flight (avoid clobbering a parallel-pipeline server)
  ss -ltn '( sport = :8181 )' 2>/dev/null | grep -q LISTEN \
    && { echo "Port 8181 already in use; pick another"; exit 1; }
  nohup python3 -m zskills_monitor.server \
        --main-root "$(git rev-parse --show-toplevel)" --port 8181 \
        > /tmp/dashboard-phase4.log 2>&1 &
  echo $! > /tmp/dashboard-phase4.pid
  ```
  Subsequent steps use `http://127.0.0.1:8181/`. Verify startup via `curl
  -sf http://127.0.0.1:8181/api/state | head -c 20` returning JSON.

  **Why `--main-root "$(git rev-parse --show-toplevel)"`**: by default, `server.py` resolves
  `MAIN_ROOT` via `git rev-parse --git-common-dir` (collect.py:179-207),
  which from inside a worktree resolves to the **main checkout**, not
  the worktree. Without the flag, the phase-4 server would write
  `<MAIN_REPO>/.zskills/dashboard-server.pid` with `port=8181`,
  potentially clobbering the user's real dashboard PID file at port
  8080. The `--main-root` flag (server.py:14, 1055, 1064) overrides this
  resolution and keeps the phase-4 lifecycle isolated under the
  worktree.

- [ ] **Dispatch verifier subagent** with the manual playwright checklist
  below as its prompt. Use the canonical idiom (matches `.claude/skills/run-plan/SKILL.md:1542` and the other 4 conformance-locked callers).

  **BEFORE dispatching**, the orchestrator MUST inline Phase 5's
  diagnosis reproducers into checklist steps 11 and 12 (the templates
  below currently reference "the commands from 5b's diagnosis" — that
  prose is a placeholder for the orchestrator to expand at dispatch
  time):

  - **Step 12 (Origin-check)**: read
    `/tmp/dashboard-phase5/5b-repro.txt` (produced by Phase 5a). Inline
    the captured rejected-POST `curl` command (control case) AND the
    captured accepted-POST `curl` command (fix case) directly into
    step 12, replacing the "reuse them here" prose. If
    `docs/plans/DASHBOARD_TABS_AND_RENAME_5B_DEFERRED.md` exists OR
    `5b-repro.txt` does NOT exist (Phase 5b deferred / no-bug / not yet
    run), mark step 12 `N/A — Phase 5b deferred` in the verifier
    prompt and downgrade per B6 below.
  - **Step 11 (banner-no-flap)**: read
    `/tmp/dashboard-phase5/5d-repro.txt`. The drag-reproduction
    sequence is canonical (5 rapid drags via mousedown / mousemove /
    mouseup), so usually no inlining is needed beyond confirming the
    target-card slug. If `5D_DEFERRED.md` exists, downgrade per B6.

  This pre-dispatch inlining is the orchestrator's responsibility; the
  verifier subagent does NOT read Phase 5 artifacts itself — it
  receives a self-contained prompt.

  The dispatch idiom itself:
  ```bash
  # In the orchestrator (NOT the verifier):
  # 1. Dispatch via Agent tool with subagent_type: "verifier" and the
  #    prompt template below.
  # 2. Capture the verifier's response into $VERIFIER_RESPONSE.
  # 3. Pipe through verify-response-validate.sh:
  printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
  VALIDATE_EXIT=$?
  # 4. On VALIDATE_EXIT != 0 OR 45-min timeout, STOP per the canonical
  #    Failure Protocol at run-plan/SKILL.md:1555-1590:
  #    - Do NOT proceed to /land-pr.
  #    - Do NOT mark Phase 4 complete.
  #    - Do NOT re-dispatch automatically.
  #    - Do NOT inline-self-verify as recovery (CLAUDE.md anti-pattern).
  #    - Surface the verbatim STOP message to the user; halt the pipeline.
  ```
  When dispatched via `/run-plan`, the parent skill's failure protocol
  handles the STOP-and-surface automatically. When dispatched by any
  other orchestrator (or invoked directly), the orchestrator owns the
  STOP behavior — do not work around the validation failure.

  **Verifier prompt template** (the orchestrator substitutes EVERY
  `<WORKTREE_PATH>` placeholder — both angle-bracket and any remaining
  shell-style — with the absolute worktree path BEFORE dispatching;
  the verifier receives no unresolved placeholders):
  ```
  You are the verifier for Phase 4 of DASHBOARD_TABS_AND_RENAME.

  Worktree absolute path: <WORKTREE_PATH>  (cd here first)
  Dashboard URL: http://127.0.0.1:8181/
  Test-output capture path: TEST_OUT="/tmp/zskills-tests/$(basename <WORKTREE_PATH>)"
    mkdir -p "$TEST_OUT" first.
  The dashboard server was already started by the orchestrator via
    `nohup python3 -m zskills_monitor.server --main-root <WORKTREE_PATH> --port 8181 ...`
  Do NOT restart it.

  Pre-flight: if `curl -sf http://127.0.0.1:8181/api/state` returns
  non-zero or times out within 5s, mark every checklist step FAIL with
  reason `server unreachable`, return immediately, and let the
  orchestrator handle STOP. Do NOT retry, wait, or restart the server.

  Execute the 12-step manual playwright-cli checklist below (real
  mouse/keyboard events; eval ONLY for DOM inspection/assertions per
  CLAUDE.md). For each step: report PASS or FAIL with the literal eval
  output captured.

  Then run:
    bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  Report the final 2 lines of that file verbatim, plus exit code.

  Return a structured response with:
    1. Step-by-step PASS/FAIL table (12 + 9b rows = 13 total).
    2. Absolute paths of screenshot files written to .playwright/output/
       (orchestrator will `test -f` each — expect 4).
    3. The literal final two lines of $TEST_OUT/.test-results.txt.
    4. Final `bash tests/run-all.sh` exit code.

  [PASTE THE 12-STEP CHECKLIST FROM THIS PHASE HERE]
  ```
  Inserting the checklist verbatim is the orchestrator's responsibility
  when constructing the Agent tool call.

- [ ] **Manual playwright-cli checklist — real events only** (executed
  by the verifier subagent; no `eval` to simulate clicks; `eval` only for
  DOM inspection/assertions; per CLAUDE.md `## Playwright CLI`):

  1. **Default state on load**. Navigate to `http://127.0.0.1:8181/`. Assert:
     - `eval 'document.title'` returns `"Z Skills Dashboard"`.
     - `eval 'document.querySelector("h1").textContent'` returns `"Z Skills Dashboard"`.
     - `eval 'document.querySelector("[role=tab][aria-selected=true]").id'` returns `"tab-plans"`.
     - `eval 'document.getElementById("plans").hasAttribute("hidden")'` returns `false`.
     - `eval '["issues","branches"].every(s => document.getElementById(s).hasAttribute("hidden"))'` returns `true`.
     - `eval 'document.getElementById("activity-strip").offsetHeight > 0'` returns `true` (strip is visible).
     - `eval 'document.querySelectorAll("[role=tab]").length'` returns `3` (PLANS, ISSUES, BRANCHES — no WORKTREES).
     - `eval 'document.getElementById("tab-worktrees") === null'` returns `true` (worktrees tab is gone).
  2. **Click each tab in turn** (using real `click` events on the tab buttons via `playwright-cli click`):
     - Click `#tab-issues`. Wait 100ms. Assert `#issues` is visible, others hidden, `aria-selected` on `#tab-issues` is `"true"`, `location.hash === "#issues"`.
     - Click `#tab-branches`. Same checks for branches. Additionally assert worktree info surfaces inline for at least one backed branch: `eval 'document.querySelectorAll("#branches-body .pill-landed-full, #branches-body .pill-landed-partial, #branches-body .pill-landed-not").length >= 1'` returns `true` IF a worktree exists in the test fixture; if no worktrees exist, the assertion is N/A — document which case.
     - Click `#tab-plans`. Same checks for plans.
  3. **Keyboard reachability (mouse-first design — no arrow-key handler)**:
     - From the page-load default state (Plans active), press `Tab` repeatedly until focus enters the tablist. Assert `document.activeElement.getAttribute("role") === "tab"` on a tab button — Tab key reaches the tablist via natural DOM order.
     - Press `Enter` (or `Space`) on a focused inactive tab. Assert it activates (native `<button>` translates key → click). Verify `aria-selected="true"` flips.
     - Press `Tab` from an active tab. Assert focus moves DOM-forward (next tab button, then the active tabpanel or its first focusable descendant). Both are acceptable.
     - **Arrow-key behavior is NOT specified**: arrow keys may scroll the page or do nothing — that is intentional under the mouse-first design. Do NOT assert arrow-key tab navigation.
  4. **Drag-and-drop within Plans tab**: with `#tab-plans` active, drag the first plan card to a different queue column using real `mousedown` / `mousemove` / `mouseup`. Wait 2s for the next poll. Confirm the move persisted (next poll returns the reordered queue). Verify `eval 'document.getElementById("plans-live").textContent'` contains the literal prefix `Moved plan ` (the announcement string at app.js:1142 is `"Moved plan " + slug + " to " + PLAN_COLUMN_LABELS[targetCol] + " position " + (targetIdx + 1)`). Verify NO `#conn-banner` appears during or after the drag (regression check for 5d).
  5. **Switch tabs during a poll cycle**: with `#tab-plans` active, immediately click `#tab-issues`. Repeat 5 times quickly. Assert no JS console errors; assert `#issues-body` re-populates on next poll.
  6. **Modal flow inside a tab**: in the Plans tab, double-click a plan card. Assert modal opens with `#modal-root` visible. Press `Esc`. Assert modal closes; focus returns to the card that opened it.
  7. **Globals stay visible regardless of tab**: kill the server (`kill -TERM "$(cat /tmp/dashboard-phase4.pid)"`). Wait 5s. Switch through **all three tabs**. Assert `#conn-banner` is visible on every tab AND that `#conn-banner.closest("[role=tabpanel]")` is `null` (banner lives outside the tab structure). Restart the server via the same `nohup python3 ...` command used above.
  8. **Narrow viewport**: `playwright-cli resize 600 900` (NOT `--viewport-size`; the actual command is `resize <w> <h>` — verify via `playwright-cli --help | grep -i resize` first if the local build syntax differs). Assert: the tablist overflows horizontally with scroll (`eval 'getComputedStyle(document.querySelector(".tablist")).overflowX'` returns `"auto"`), tabs are still individually clickable, scroll-snap works. Take a screenshot.
  9. **URL hash deep-link**: navigate directly to `http://127.0.0.1:8181/#branches`. Assert page loads with `#tab-branches` active and `#branches` visible. (A brief sub-200ms flash of Plans is acceptable on slow devices; assert end-state, not transient frame.) Refresh (`playwright-cli reload`). Assert tab state survives. Then navigate to `http://127.0.0.1:8181/#worktrees`: assert page falls back to `#plans` active (since `worktrees` is not in `TAB_SLUGS`); `location.hash` may still read `#worktrees` (we never rewrite an unknown hash to avoid the back-stack churn) but `aria-selected="true"` is on `#tab-plans`.
  9b. **Browser back/forward**: from `/`, click `#tab-issues`, then `#tab-branches`. Press browser back (`playwright-cli back` or `window.history.back()` via `eval`). Assert URL is `/#issues` AND `#tab-issues` is `aria-selected="true"`. Press back again. Assert URL `/#plans` (default — replaceState wrote `#plans` on initial load if hash was empty) OR `/` (if initial hash was absent and never written). Either is correct given `history.replaceState` semantics. Document which behavior is observed.
  10. **Screenshots** (without `--filename`, so files land in `.playwright/output/` per `.devcontainer/setup.sh` config): take one per tab, plus one of the narrow viewport — **4 total**. Rename to `phase4-tab-{plans,issues,branches,narrow}.png` after capture.
  11. **Connection-banner-no-flap (validates Phase 5d fix)**: with
      server running and `#tab-plans` active, drag a plan card 5 times
      in rapid succession (mousedown / mousemove / mouseup, no
      inter-drag delay). Throughout the sequence, poll `eval
      'document.getElementById("conn-banner").hidden'` — assert it
      returns `true` on every poll (banner does NOT flap).

      **Conditional behavior** (orchestrator decides at prompt-inline
      time):
      - **If `docs/plans/DASHBOARD_TABS_AND_RENAME_5D_DEFERRED.md`
        exists** (5d deferred / no-bug / time-boxed-out): this step is
        DOWNGRADED to "document current banner behavior during 5 rapid
        drags." Capture `document.getElementById("conn-banner").
        textContent` AND `.hidden` at +500ms intervals across the drag
        sequence; attach the observations to the phase report. PASS
        regardless of whether the banner flapped — this is a baseline
        observation, not an assertion.
      - **Otherwise** (Phase 5d shipped a fix): assert
        `#conn-banner.hidden === true` throughout the 5-drag sequence.
        FAIL if any poll observes `.hidden === false`.

  12. **Origin-check accepts user's deployment (validates Phase 5b
      fix)**: from a separate shell, replay the rejected-POST and
      accepted-POST `curl` commands the orchestrator inlined into this
      step from `/tmp/dashboard-phase5/5b-repro.txt` (see "Dispatch
      verifier subagent" work item above).

      **Conditional behavior** (orchestrator decides at prompt-inline
      time):
      - **If `docs/plans/DASHBOARD_TABS_AND_RENAME_5B_DEFERRED.md`
        exists** (5b deferred / no-bug / time-boxed-out): this step is
        MARKED `N/A — Phase 5b deferred` and reported as a non-failing
        skip in the PASS/FAIL table. Do NOT attempt the reproducers.
      - **Otherwise** (Phase 5b shipped a fix): assert rejected POST
        returns 403 (control case) AND accepted POST returns 200 with
        the queue state updated (fix case verified via `/api/state`
        polled at +3s).

- [ ] **Automated test suite** — runs as part of the verifier subagent's
  responsibility per the prompt template above. The verifier executes:
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  ```
  and returns the final 2 lines + exit code to the orchestrator.
  Specifically required green:
  - `tests/test_zskills_monitor_dashboard_ui.sh` (3-entry panel-class loop, title rename, activity-strip presence, worktrees-panel-removed assertion)
  - `tests/test_zskills_dashboard_skill.sh` (do_start / do_stop / do_status echo strings)
  - `tests/test_zskills_monitor_server.sh` (HTTP endpoints; minimally touched by Phase 5b — if `_origin_ok` changes, this test stays green for the 3 endpoints it already covers)
  - `tests/test_zskills_monitor_collect.sh` (collector; untouched)
  - `tests/test-skill-conformance.sh` (CI gate — confirms `metadata.version` matches projection hash)
  - `tests/test_zskills_monitor_csrf.sh` (NEW in Phase 5b — `_origin_ok` policy coverage; runs only if Phase 5b shipped a fix)
  - `tests/test_zskills_dashboard_disconnect_debounce.sh` (NEW in Phase 5d — disconnect-flap regression coverage; runs only if Phase 5d shipped a fix)

- [ ] **Phase report**: write `$ZSKILLS_AUDIT_DIR/plan-dashboard-tabs-and-rename.md` (or the path resolved by `zskills-resolve-config.sh`) documenting:
  - The 10-step playwright checklist with each step marked pass/fail.
  - Paths to the screenshots.
  - The `bash tests/run-all.sh` summary line (e.g., `Tests: 47 passed, 0 failed`).
  - Any flakes encountered and how resolved.

- [ ] **Stop the dev server**: `kill -TERM "$(cat /tmp/dashboard-phase4.pid)"`. Confirm the PID is gone via `ps -p "$(cat /tmp/dashboard-phase4.pid)" || echo "stopped"`. Remove the PID file: `rm -f /tmp/dashboard-phase4.pid`. Do NOT escalate to SIGKILL (CLAUDE.md rule).

- [ ] **No content edits in this phase** unless a test assertion drifts
  from reality (in which case the drift signals a bug in Phases 1-3, NOT
  a license to weaken the test). If drift forces a fix, the fix lands as
  a follow-up commit on the same branch with version bump.

### Design & Constraints

- **Real mouse/keyboard events ONLY** for user-facing operations (click,
  drag, type, key). `eval` is allowed for DOM inspection and assertion
  setup only. Per CLAUDE.md: "Never use `page.evaluate()` or `eval` to
  call JS APIs that simulate user actions."
- **Screenshots without `--filename`** so files save to `.playwright/output/`
  per repo convention.
- **NEVER weaken tests** to make them pass. If a test fails, find the
  root cause — fix the code, not the test. If the failure is genuinely
  pre-existing (verify with `git log` that the test/source predates this
  branch), file a GitHub issue with the error output and mark the test
  `it.skip('name // #NNN')` ONLY for tests this branch did not touch.
- **Two-attempt maximum** on any failing fix. If the same test fails
  twice after two distinct fix attempts, STOP and surface (CLAUDE.md
  "NEVER thrash on a failing fix").
- **Capture test output to file, never pipe** (CLAUDE.md). The
  `$TEST_OUT/.test-results.txt` pattern is canonical.
- **Verifier-cannot-run rule**: if a dispatched verification subagent
  returns without running tests, that is a verification FAIL — STOP and
  surface. Do not "self-verify inline" as a recovery.

### Acceptance Criteria

- [ ] All 12 (+ 9b) manual playwright steps documented in the phase report with PASS or evidence of resolution.
- [ ] The verifier subagent's response was piped through `verify-response-validate.sh` via `printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"` and exited 0. The exit code is recorded in the phase report.
- [ ] **On verify-response-validate.sh non-zero exit OR 45-min agent timeout**: STOP per the canonical Failure Protocol at `.claude/skills/run-plan/SKILL.md:1555-1590`. The orchestrator MUST NOT inline-self-verify, MUST NOT auto-re-dispatch, MUST NOT dispatch `/land-pr`, MUST NOT mark Phase 4 complete. The verbatim STOP message is surfaced to the user; the pipeline halts.
- [ ] Verifier response includes the structured items required by the prompt template. Orchestrator MUST inspect with these programmatic checks BEFORE accepting:
  - `grep -cE '^\s*\|\s*[0-9]+(b)?\s*\|' <<< "$VERIFIER_RESPONSE"` returns ≥ 13 (rows 1-12 + 9b in a markdown pipe-table).
  - `grep -cE '(PASS|FAIL)' <<< "$VERIFIER_RESPONSE"` returns ≥ 13.
  - `grep -oE '/[^[:space:]]*\.playwright/output/[^[:space:]]+\.png' <<< "$VERIFIER_RESPONSE"` returns at least 4 paths; orchestrator runs `test -f` on each — all must exist.
  - The verifier response contains the literal "exit code" of `tests/run-all.sh`.
  If ANY check fails, treat as a verifier-cannot-run failure: STOP per the canonical Failure Protocol; do NOT inline-self-verify; surface to the user.
- [ ] `bash tests/run-all.sh` exits 0 with no failures (or only failures pre-existing on `main`, demonstrated via `git log` and skip-with-issue per the CLAUDE.md rule). The run includes the new Phase-5 automated tests (`tests/test_zskills_monitor_csrf.sh`, `tests/test_zskills_dashboard_disconnect_debounce.sh`) when they are added by Phase 5.
- [ ] At least 4 screenshots present in `.playwright/output/` and renamed per the convention `phase4-tab-{plans,issues,branches,narrow}.png`.
- [ ] Phase report's "Manual Test Plan" section enumerates pass-marked steps; no unchecked-but-claimed checkbox (per memory anchor `feedback_pr_test_plan_checkboxes.md`).
- [ ] `diff -rq skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` is empty (no orphan drift).
- [ ] Phase report committed at `$ZSKILLS_AUDIT_DIR/plan-dashboard-tabs-and-rename.md`.

### Dependencies

Phase 3 (tab JS) — the click handler and `hashchange` listener being
verified must exist. Phase 5 fixes may run before or after Phase 4
manual verification within the same /run-plan invocation; if Phase 5
ships fixes that materially affect dashboard behavior, Phase 4 SHOULD
re-run for the affected steps (11 and 12 specifically) after Phase 5
lands. The plan's recommended order is 0 → 1 → 2 → 3 → 5 → 4 (so the
final manual verification covers everything), but the orchestrator may
also run 4 → 5 → 4-redux for de-risking the presentation refactor
before touching server code. Either order is valid; the AC is that
Phase 4 manual verification covers the final state of all phases.

---

## Phase 5 — Dashboard functional fixes

### Goal

Three surgical functional fixes (CSRF/Origin policy at `_origin_ok`,
READY-column drop persistence, disconnect-banner flap) plus a
verification step for `/work-on-plans` queue-honoring (no fix expected
per V5; if a real bug surfaces during reproduction, file a follow-up
issue). Every sub-section follows **investigate-first**: reproduce the
user-reported symptom in a controlled environment BEFORE writing code.
Multiple symptoms may collapse to a single underlying cause (R6: e.g.,
a dashboard-port-vs-server-bind mismatch in the user's deployment); the
phase exits if 5a's diagnosis identifies one root cause for multiple
symptoms.

### Phase-level work items

- [ ] **Start a dedicated dashboard server in the worktree** with
  `--main-root "$(git rev-parse --show-toplevel)"` (server.py:1064-1065)
  so PID/state files land in the worktree's `.zskills/`, not the main
  checkout's. Use port 8181 (per Phase 4 convention). The Phase-5
  server lifecycle is independent of Phase 4's server start/stop.
- [ ] **Each sub-section ships its own commit** with version bump + mirror
  per the Shared Conventions procedure. Sub-section 5a may ship a
  diagnosis-report-only commit (touches `docs/plans/` only, no skill
  files) or fold its diagnosis into the same commit as 5b/5c/5d if the
  diagnosis materially informs the fix shape.
- [ ] **Time-box hard limits**: 5a investigation 30 min; 5b/5c/5d fix
  cycles 60 min each (per CLAUDE.md two-attempt thrashing rule);
  5e total 30 min (10-min reproduction + 20-min investigation if
  reproducible). If a sub-section blows its budget without root cause
  identified, file a follow-up GitHub issue with diagnosis-so-far and
  close the sub-section as deferred — do NOT thrash.

### Sub-section 5a — Diagnose first (no fixes)

Reproduce each of the three user-reported symptoms in a controlled
environment with the Phase-5 worktree dashboard:

1. **403 on `/api/queue` drag POST** — reproduce by triggering a
   drag-and-drop in the running dashboard while watching the server
   log. Capture: the request `Origin` header value, the host part of
   the request URL, the server's BIND_HOST, the `_origin_ok` return
   path taken. Save the captured `curl` reproducer to
   `/tmp/dashboard-phase5/5b-repro.txt`.
2. **READY column not accepting drops** — reproduce by dragging a card
   into the READY column. The dragover / dragenter / drop handlers
   live at app.js:1338-1380 (NOT line 599 — verified by reading
   `onDragOver` / `onDragEnter` / `onDrop` definitions). The reproducer
   must capture, via `eval`, the dropzone's dataset attributes when
   the drop fires: `eval 'document.querySelectorAll("ul.dropzone").forEach(dz => console.log(dz.dataset.kind, dz.dataset.column))'`
   (note: the attribute is `data-column`, NOT `data-col` — verified
   against the drop handler at app.js:1372 reading
   `dz.getAttribute("data-column")`). Confirm: the dropzone matches
   the drag `kind` predicate, the POST issued, the server response,
   the post-poll state. Save the JS console log to
   `/tmp/dashboard-phase5/5c-repro.txt`.
3. **Disconnect-banner flap during interaction** — reproduce by
   performing a drag while watching `#conn-banner`. Instrument
   `setConnected(false)` with `console.log(new Error().stack)` to
   identify the call site (V3 confirms there are NO `.abort()` calls;
   the call sites are 148, 152, 155 inside `fetchState`). Capture the
   stack trace + the network panel state at flap time. Save to
   `/tmp/dashboard-phase5/5d-repro.txt`.

#### Sub-section 5a Acceptance Criteria

- [ ] Three reproduction artifacts saved (`5b-repro.txt`,
  `5c-repro.txt`, `5d-repro.txt`).
- [ ] A consolidated diagnosis document at
  `docs/plans/DASHBOARD_TABS_AND_RENAME_5A_DIAGNOSIS.md` containing,
  per symptom: (a) reproducer commands, (b) observed behavior,
  (c) root-cause hypothesis with file:line evidence, (d) proposed
  fix shape, (e) whether this symptom collapses with another (e.g.,
  if 5c is fixed by 5b's `_origin_ok` change because the drop POST
  was 403-ing all along).
- [ ] Time-box not exceeded (30 min). If exceeded, the partial
  diagnosis is committed and Phase 5 closes with sub-section 5b/5c/5d
  marked deferred.
- [ ] **5c-subsumed-by-5b predicate (falsifiable)**: 5c may close as
  "subsumed by 5b" ONLY IF BOTH conditions hold:
  (a) the 5a-captured `/tmp/dashboard-phase5/5c-repro.txt` server-log
      shows HTTP 403 on the drop-POST line (proving the symptom WAS
      Origin-rejection, not a distinct dropzone bug), AND
  (b) after applying 5b's fix, re-running the 5c reproducer (drag a
      card into READY) returns HTTP 200 AND `/api/state` polled at
      +3s shows the card moved to the READY column.
  If EITHER condition fails (403 not observed in 5c-repro, OR drag
  still fails after 5b's fix), 5c must ship its own fix OR be
  reclassified as a deferred sub-section per the Phase 5 time-box
  deferral protocol. A "subsumed" close without both checks logged in
  the 5a diagnosis document is invalid.

### Sub-section 5b — Origin-check policy fix

Modify `_origin_ok` (server.py:601-610) once. All three call sites
(817, 850, 985) inherit the fix automatically — per the centralized
invariant in Shared Conventions.

The exact policy is determined by 5a diagnosis output. Likely options
(implementer selects from diagnosis):
- Accept any same-host Origin (host portion of Origin matches BIND_HOST
  + port), independent of scheme/path.
- Accept a configurable allowed-origins list read from
  `.claude/zskills-config.json`.
- Accept `null` Origin (some browsers send `null` for opaque origins,
  e.g., `file://` or sandbox iframes; relevant if user's deployment
  uses a proxy that strips Origin).

#### Sub-section 5b Acceptance Criteria

- [ ] `_origin_ok` body diverged from main. Diff is restricted to
  server.py:601-610 plus possibly a config-read helper.
- [ ] `tests/test_zskills_monitor_csrf.sh` (NEW) exists and exercises
  AT LEAST: (a) a same-host POST is accepted (200); (b) a cross-origin
  POST is rejected (403); (c) the specific user-deployment Origin
  captured in 5a-repro now succeeds. Test uses Python `http.client` or
  raw `curl` against a test-bound server; no `gh` / network deps.
- [ ] `bash tests/test_zskills_monitor_csrf.sh` exits 0.
- [ ] Manual replay of the 5a reproducer command returns 200 (was 403
  before fix).
- [ ] **`tests/run-all.sh` test-registration**: append
  `run_suite "test_zskills_monitor_csrf.sh" "tests/test_zskills_monitor_csrf.sh"`
  to `tests/run-all.sh` immediately after the existing
  `run_suite "test_zskills_monitor_server.sh" "tests/test_zskills_monitor_server.sh"`
  entry (currently at run-all.sh:94). `tests/run-all.sh` is an
  EXPLICIT-LIST runner (no auto-discovery); without this registration
  the new test exists on disk but never executes during Phase 4's
  `bash tests/run-all.sh` invocation. AC: `grep -F
  'test_zskills_monitor_csrf.sh' tests/run-all.sh` returns ≥1.
- [ ] Skill version bumped + mirror diff-rq empty.

### Sub-section 5c — READY drop diagnosis-and-fix

Per R3 / DA3: the dropzone class (`drop-target` set inside the
dragenter handler at app.js:1339-1345) is applied uniformly across
columns; the drag/drop handler family lives at app.js:1338-1380 (NOT
app.js:599 — that prior citation was inaccurate). If 5a finds that the symptom was
"drop appeared to fail because the POST was 403'd by `_origin_ok`,"
this sub-section closes as **fixed by 5b** with a single-line note in
the commit message.

Otherwise (5a finds a separate cause — e.g., column-specific dropzone
predicate, stale state, race with poll, column-name mismatch in
`PLAN_COLUMN_LABELS`), apply the minimal fix the diagnosis indicates.

#### Sub-section 5c Acceptance Criteria

- [ ] **If closed-by-5b**: commit message contains "Closes 5c
  (subsumed by 5b)"; no app.js changes for 5c specifically.
- [ ] **If separate fix shipped**: drag-to-READY now persists across
  poll cycles (verified manually + via an extension of
  `tests/test_zskills_monitor_dashboard_ui.sh` or a new fixture-driven
  test); the fix is < 30 LOC.

### Sub-section 5d — Disconnect-flap diagnosis-and-fix

Per V3 / R4 / DA3: the user's hypothesis ("cancelled POST → AbortError
→ setConnected(false)") cannot be the cause — `grep -nE
"\.abort\(|pollAbort\.|workPollAbort\."` returns ZERO in app.js, and
`commitQueueChange` doesn't use AbortController. The 5a stack trace
will identify which of the three `setConnected(false)` call sites
(148, 152, 155 inside `fetchState`) fires during the drag, and what
upstream condition triggers it.

Likely root cause (subject to 5a confirmation): the 2s poll's
`fetchState` happens to be in-flight when the drag occurs, the
`commitQueueChange` POST briefly contends with the poll on the server's
single-threaded handler, `fetchState` either times out or receives a
transient error, and `setConnected(false)` fires before the next
successful poll restores `setConnected(true)`.

Likely fix shape (subject to 5a): debounce `setConnected(false)` —
require N consecutive failures (e.g., 2) before showing the banner;
clear the count on the first success. This is a small change at
`fetchState` (~10 LOC).

#### Sub-section 5d Acceptance Criteria

- [ ] 5a diagnosis cites the specific `setConnected(false)` call site
  reached during the user's reproducer.
- [ ] Fix is < 30 LOC and confined to `fetchState` + module-state
  `connectionFailureCount` (or equivalent).
- [ ] `tests/test_zskills_dashboard_disconnect_debounce.sh` (NEW)
  exercises: (a) a single transient `fetchState` failure does NOT
  flip `#conn-banner` visible; (b) N consecutive failures DO flip it;
  (c) a single subsequent success clears it. Test uses a minimal
  `unittest`-style mock of `fetch` via injecting a stub on the
  module's `fetch` reference, or a Python-driven HTTP server that
  returns 500 then 200 — preserve no-build / stdlib-only invariant.
- [ ] `bash tests/test_zskills_dashboard_disconnect_debounce.sh`
  exits 0.
- [ ] **`tests/run-all.sh` test-registration**: append
  `run_suite "test_zskills_dashboard_disconnect_debounce.sh" "tests/test_zskills_dashboard_disconnect_debounce.sh"`
  to `tests/run-all.sh` (placement adjacent to the other dashboard
  entries — after `test_zskills_dashboard_skill.sh` at run-all.sh:99
  is the natural slot). `tests/run-all.sh` is an EXPLICIT-LIST runner
  (no auto-discovery); without this registration the new test exists
  on disk but never executes during Phase 4's `bash tests/run-all.sh`
  invocation. AC: `grep -F
  'test_zskills_dashboard_disconnect_debounce.sh' tests/run-all.sh`
  returns ≥1.
- [ ] Manual replay of the 5a reproducer no longer flaps the banner
  during 5 rapid drags (matches Phase 4 step 11).

### Sub-section 5e — `/work-on-plans` queue-honoring verification

Per V5 / R5: `/work-on-plans` already reads `.zskills/monitor-state.json`
(SKILL.md:7, 120, 164-166) and extracts `plans.ready`. The user's
"doesn't honor monitor queue" report is, on its face, contradicted by
evidence. This sub-section is a **verification step, not a fix
phase**: reproduce the user's reported issue; if it doesn't reproduce,
close as "no bug observed under the conditions tested" and document.
If it does reproduce, time-box investigation at 20 min and either
file a follow-up issue (with full reproducer) or fold a minimal fix.

#### Reproducer recipe

1. From the Phase-5 worktree dashboard at port 8181, drag two plans
   into the READY column.
2. Verify `.zskills/monitor-state.json` (worktree path, not main repo's)
   contains those two slugs under `plans.ready` with correct positions.
3. Run `/work-on-plans 1` from a shell in the worktree. Capture the
   dispatched slug.
4. Compare: did the dispatched slug match the front of `plans.ready`
   at dispatch time?

#### Sub-section 5e Acceptance Criteria

- [ ] Reproducer was attempted; result documented in
  `docs/plans/DASHBOARD_TABS_AND_RENAME_5E_VERIFICATION.md`.
- [ ] **If no-bug**: documentation says "verified queue-honoring
  works as designed; closing without code change." No file changes
  under `skills/` or `tests/`.
- [ ] **If reproducible AND root-caused within 20 min**: minimal fix
  shipped, AC list extended ad-hoc by the implementer.
- [ ] **If reproducible BUT not root-caused within 20 min**: follow-up
  GitHub issue filed with the verification document attached; phase
  ships the verification commit only.
- [ ] Time-box honored (10 min reproduction + 20 min investigation max).

### Phase 5 — top-level Acceptance Criteria

- [ ] Sub-section 5a delivered a diagnosis document at
  `docs/plans/DASHBOARD_TABS_AND_RENAME_5A_DIAGNOSIS.md`.
- [ ] Sub-section 5b shipped (or was justified as no-fix-needed by 5a).
- [ ] Sub-section 5c shipped, or closed-by-5b, or justified.
- [ ] Sub-section 5d shipped, or closed-by-5b, or justified.
- [ ] Sub-section 5e ran the reproducer and documented the outcome.
- [ ] Each commit that touches `skills/zskills-dashboard/` bumped
  `metadata.version` per the Shared Conventions; `diff -rq
  skills/zskills-dashboard/ .claude/skills/zskills-dashboard/` is
  empty after each.
- [ ] No `_origin_ok` call site duplicates the centralized check
  (`grep -nE "origin|Origin" server.py` outside the `_origin_ok` body
  returns only the existing 3 call-site invocations).
- [ ] Total Phase 5 LOC (all sub-sections combined, excluding
  diagnosis docs and new test files) ≤ ~150. If exceeded, the
  remaining work is scoped down or deferred to a follow-up PR — Phase 5
  must not balloon the dashboard refactor PR.
- [ ] Phase 5 produced 0 or more new test files under `tests/`; each
  new test runs in `bash tests/run-all.sh` and is green.

### Phase 5 Dependencies

Phase 0 (worktree). Phase 5 does NOT structurally depend on Phases
1-4; it can run in parallel with the rename/tab work in principle. In
practice, run Phase 5 AFTER Phase 3 so the dashboard's tab structure
is in its final shape — that avoids confusing 5a diagnosis with
mid-refactor noise. Phase 4's manual verification step 11 + 12
re-validate Phase 5's fixes end-to-end.

**Sub-section sequencing within Phase 5 (strict)**: `5a → (5b, 5c, 5d)`
partial order. 5a produces diagnosis outputs
(`/tmp/dashboard-phase5/{5b,5c,5d}-repro.txt` plus
`docs/plans/DASHBOARD_TABS_AND_RENAME_5A_DIAGNOSIS.md`) that 5b, 5c,
and 5d directly consume — the 5b origin policy is "determined by 5a
diagnosis output," 5c's subsumed-by-5b predicate reads
`5c-repro.txt`, and 5d's debounce-threshold N is informed by the 5a
stack trace. 5b/5c/5d may then run in any order or in parallel with
each other — they do NOT depend on each other (5b touches
server.py:601-610; 5c touches app.js drag/dropzone code; 5d touches
`fetchState` debounce logic). 5e is independent of 5a-d and may run
at any time (it reads `.zskills/monitor-state.json`, not Phase 5
outputs). An orchestrator dispatching sub-sections concurrently MUST
NOT start 5b/5c/5d before 5a's diagnosis commit is on the branch.

---

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review (orchestrator: claude-opus-4-7[1m]; reviewer / devil's-advocate / refiner subagents at general-purpose, inheriting Opus parent)
**Convergence:** Converged at end of round 3. Both round-3 agents independently recommended convergence with only polish-level findings (no blockers). Four polish fixes applied inline (`$PWD` → `git rev-parse --show-toplevel`; explicit announcement-string prefix in step 4; server-unreachable verifier instruction; programmatic schema checks for verifier response).
**Remaining concerns:**
- Module-script defer means inline early-init for hash deep-link is best-effort — first-paint flash for `/#worktrees`-style URLs is acceptable per the relaxed Phase 4 step 9 AC. A real no-flash fix (inline non-module `<script>` in `<head>`) is out of scope.
- The 5-row Activity strip cap is a design judgment from the UI agent; if usage shows it's wrong, easy to revisit post-landing.
- `tests/fixtures/monitor/` directory name is preserved (rename has filesystem ripples beyond the presentation refactor).
- Convergence math: across 3 rounds, ~9 findings were "Justified-not-fixed" (each with documented rationale); the remaining ~48 were "Fixed."

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 15 issues         | 15 issues                 | 26/30 fixed; 4 justified  |
| 2     | 11 issues         | 10 issues                 | 17/21 fixed; 4 justified  |
| 3     | 2 issues (LOW)    | 4 issues (2 MED, 2 LOW)   | 4 polish fixed; 2 cosmetic deferred; **CONVERGED** |

### Round 1 disposition

All empirical claims verified by re-running the cited grep / file:line
checks before acting (per `feedback_verify_agent_reports.md`).

| # | Finding (short) | Evidence | Disposition |
|---|---|---|---|
| R1 | Phase 3 `git commit -am` misses new mirror files | Plan line, verified by reading `mirror-skill.sh` behavior | **Fixed**: replaced with explicit `git add` + `git commit -m`. |
| R2 | Tab key lands on first focusable descendant, not panel | WAI-ARIA APG | **Fixed**: Phase 3 Design & Constraints documents the behavior; Phase 4 step 3 AC accepts either panel-itself OR focusable descendant. |
| R3 | Enter/Space not handled in keyboard switch | Plan JS sketch | **Justified**: native button click-on-Space + roving tabindex makes explicit handling unnecessary. Rationale added to Phase 3 Design & Constraints. |
| R4 / R5 | `/zskills-dashboard start` cannot be Bash-invoked + `disable-model-invocation: true` blocks Skill-tool dispatch | SKILL.md:3 + memory `feedback_skill_invocation_flags.md` | **Fixed**: Phase 4 uses raw `nohup python3 -m zskills_monitor.server`; stop uses `kill -TERM`. |
| R6 / DA7 | "Byte-identical panel-body content" AC unverifiable | Plan AC | **Fixed**: replaced with structural diff AC (`git diff main..HEAD -- app.js` shows only the line-1 rename; render fn line counts unchanged). |
| R7 | Tests/ edits don't enter projection — clarify | `scripts/skill-content-hash.sh` scope | **Fixed**: Sequencing work item explicitly notes tests/ are NOT mirrored or hashed. |
| R8 | CSS AC grep missing leading dot | app.css:105-109 actual selectors verified | **Fixed**: AC pattern uses `\.panel-plans\s*\{` etc. |
| R9 | `gh pr list --search "Z Skills Monitor"` AC is wrong | Verified rename eliminates the string | **Fixed**: replaced with phase-report checkbox audit. |
| R10 | Mirror scope clarification | `mirror-skill.sh` source | **Fixed**: explicit note in Phase 1 commit step. |
| R11 / DA13 | Deep-link flash before boot() runs setActiveTab | Plan boot() insertion timing | **Fixed**: added inline early-init (idempotent), guarded by `document.readyState`. Phase 4 step 9 AC relaxed to "end-state, not transient frame." |
| R12 | Verifier agent check needs explicit command | Phase 0 work item | **Fixed**: replaced narrative check with `grep -E '^tools:.*Read.*Grep.*Glob.*Bash.*Edit.*Write'`. |
| R13 / DA5 | playwright-cli `viewport-size` flag does not exist | `playwright-cli --help` returns `resize <w> <h>` (verified) | **Fixed**: Phase 4 step 8 uses `playwright-cli resize 600 900`. |
| R14 | Round-history cosmetic | Plan structure | **No fix needed** (acknowledged). |
| R15 | Frontmatter preservation note | SKILL.md frontmatter | **Fixed**: Phase 1 SKILL.md work item lists `disable-model-invocation`, `description` etc. as "DO NOT change." |
| DA1 | README.md:400 missed | `grep -n "monitor" README.md` returned line 400 (verified) | **Fixed**: added README.md work item + AC. |
| DA2 / DA3 | SKILL.md lines 18, 87, (10, 514) unaddressed | `sed -n '10p;18p;87p;514p'` verified | **Fixed**: 18 and 87 added to rename list; 10 and 514 explicitly retained with rationale (internal filename reference). AC whitelist updated to enumerate the only-surviving load-bearing hits. |
| DA4 | ARIA-live regions inside hidden tabpanels — theoretical SR risk | app.js:1001-1009 + plan HTML | **Justified + AC added**: in practice `announce()` fires only from interactions in the active panel, so the panel is always visible at announce time. Phase 4 step 4 now asserts `#plans-live` textContent updates after drag-drop. |
| DA6 | panel-activity test removal ordering | Plan phase boundaries | **Justified**: plan already structures Phase 1 (rename only, panel-activity intact) and Phase 2 (HTML restructure removes panel-activity + test loop entry) as separate commits in lockstep; Phase 2 work item makes the lockstep explicit. |
| DA8 | server_version + line 372 retention reasoning weak | `grep -rn server_version tests/` returns no hits (verified); test sites for 372 at 397/729/773 confirmed | **Fixed**: both renamed; 4-line test lockstep added. Per `feedback_no_premature_backcompat.md`. |
| DA9 | Activity strip horizontal overflow | Plan CSS sketch + `.activity-row` grid template | **Fixed**: added `overflow-x: hidden` + `min-width: 0` + ellipsis pattern on `.activity-row > *`. |
| DA10 | Phase 4 doesn't dispatch verifier | Plan phase prose | **Fixed**: Phase 4 Goal section now mandates verifier dispatch; checklist runs as verifier prompt; response piped through `verify-response-validate.sh`. |
| DA11 / DA15 | TOCTOU race in version bump + sequencing | `block-stale-skill-version.sh` semantics | **Fixed**: explicit ordering in Phase 1 work items; verify-no-drift smoke before each phase's commit. |
| DA12 | Phase 5 / Plan Quality stale | Plan Progress Tracker (5 phases 0-4) | **Fixed**: Plan Quality references "after Phase 4." |
| DA13 | boot() insertion point ambiguous | Verified `boot()` body at app.js:1694-1699 | **Fixed**: exact insertion shown with full before/after context. |
| DA14 | Browser back-button test missing | Phase 4 step list | **Fixed**: added step 9b. |
| DA15 | (Merged with DA11) | — | Fixed. |

### Round 2 disposition

All empirical claims verified before acting. The DA caught a HIGH-severity
issue (PID file pollution) that the reviewer-discipline of the round-1
flow had not surfaced.

| # | Finding (short) | Evidence | Disposition |
|---|---|---|---|
| R2-F1 | `collect.py` lines 3-4 + 1218 have user-facing "zskills monitor" prose | `grep -n "monitor" .../collect.py` (verified — lines 3, 4, 142, 1011, 1016, 1029, 1035, 1205, 1218) | **Fixed**: added Phase 1 collect.py work item; AC enumerates surviving internal hits. |
| R2-F2 / R2-F7 | AC grep missed lowercase form + fixture file `zskills-monitor` | `grep -rn "zskills monitor"` verified | **Fixed**: AC `grep -rinE 'zskills[- ]monitor\|zskills monitor'` added; fixture file documented as accepted-comment hit (directory name preserved — rename has filesystem ripples beyond presentation scope). |
| R2-F3 / R2-DA-4 | Structural render-pipeline AC trivially passes on body edits | The grep `'^[+-][^+-].*function (render\|fingerprint)'` only matches header lines, not body diff lines | **Fixed**: replaced with line-budget AC (`grep -cE '^[+-][^+-]'` returns ≤2 in Phase 2) AND a body-extraction `diff` over each named function. |
| R2-F4 | Inline early-init is theatrical for `<script type="module">` (ES modules defer past first paint) | Read app.js:1700-1705 + `<script type="module">` defer semantics | **Acknowledged as partial**: round-1 disposition reframed; plan now states "best-effort, may not prevent first-paint flash on deep-link"; out-of-scope full-fix path documented (inline non-module `<script>` in `<head>`); Phase 4 step 9 AC relaxed to "end-state, brief sub-200ms transient acceptable." |
| R2-F5 | Verifier prompt template missing | Phase 4 work-item review | **Fixed**: added full verifier-prompt template with worktree path / URL / TEST_OUT / responsibility partition. |
| R2-F6 / R2-DA-6 | No AC for verifier-cannot-run failure protocol | Phase 4 AC list | **Fixed**: explicit AC referencing run-plan/SKILL.md:1555-1590 (no inline-self-verify; no auto-re-dispatch; no /land-pr dispatch; halt + surface). |
| R2-F8 | Hook-fail recovery underspecified | Phase 0 prose | **Fixed**: Design & Constraints now points at `/update-zskills` for Layer 0/3 hook reinstall; explicitly out-of-scope for the verifier-agent definition. |
| R2-F9 | boot() insertion ambiguity (definition placement vs invocation placement) | Re-read Phase 3 work items | **Fixed**: explicit "definitions go at end-of-file immediately BEFORE `function boot()`"; "inline early-init call goes between the definitions and the existing `if (document.readyState === 'loading')` dispatch." |
| R2-F10 / R2-DA-2 | sed misses prose hits (comments, pass/fail messages) → AC fail | `grep -nE 'monitor\|Monitor' tests/test_zskills_dashboard_skill.sh` (verified — lines 663, 673, 743-745, 755, 779, 781, 785, 791, 812, 820 are prose) | **Fixed**: expanded sed recipe with prose-context patterns; post-grep audit AC now uses negation filter to exit zero on success. |
| R2-F11 | Verifier-response schema not enforced | `verify-response-validate.sh` checks stalled-string + min-length only | **Fixed**: prompt template now requires structured return (PASS/FAIL table, screenshot abs paths, final 2 lines of test-results, run-all exit code); AC enforces orchestrator `test -f` on each screenshot path. |
| R2-DA-1 (HIGH) | `python3 -m zskills_monitor.server` writes PID file to MAIN repo, clobbering user's real dashboard | `grep -n write_pid_file .../server.py` + `_resolve_main_root` (collect.py:179-207) verified — `--git-common-dir` returns main repo from worktree | **Fixed**: Phase 4 step 1 now uses `--main-root "$(git rev-parse --show-toplevel)"` (server.py:14, 1055, 1064) so PID file is written under worktree's `.zskills/`. Rationale documented in plan. |
| R2-DA-3 | SKILL.md lines 314 + 418 doc-comments mirror echo strings | `sed -n '312,316p;416,420p'` verified | **Fixed**: added line 314 and 418 to Phase 1 SKILL.md work-item list; AC at line 349 now passes. |
| R2-DA-5 | `verify-response-validate.sh` calling convention under-specified | Existing skills use `printf '%s' "$VERIFIER_RESPONSE" \| bash ...` (verified — run-plan:1542, do:730, commit:301, etc.) | **Fixed**: Phase 4 verifier dispatch block now shows the verbatim canonical idiom. |
| R2-DA-7 | Wholesale HTML paste fragility | Plan Phase 2 work item | **Justified**: 89-line file is small enough that wholesale replacement is acceptable; Phase 2 ACs (rename re-asserted, `role=tab`/`role=tabpanel` counts, mirror diff empty) catch transcription errors. Adding a diff-style work item would double plan length for marginal benefit. |
| R2-DA-8 | Tab key prose wrong about where focus lands first | WAI-ARIA APG + DOM tab order with `tabindex=0` on tabpanel | **Fixed**: prose reworded — Tab from active tab lands on tabpanel container FIRST (because it has `tabindex=0`), then a second Tab advances to descendants. |
| R2-DA-9 | No port-collision pre-flight | Phase 4 step 1 | **Fixed**: added `ss -ltn '( sport = :8181 )' \| grep -q LISTEN` pre-flight that fails fast. |
| R2-DA-10 | `try/catch (_)` swallows real errors silently | Inline early-init JS sketch | **Fixed**: replaced with `catch (e) { console.warn("tab-init early call failed:", e); }`. |

---

## Refinement Drift Log

This section records the scope expansion that occurred after the original
3-round /draft-plan convergence. The Round 1/2/3 disposition tables
ABOVE are preserved as a historical audit trail of the
presentation-only-scope convergence; they are **not modified**. The drift
log below identifies which of those rows are stale and adds a /refine-plan
Round 1 disposition table for the new scope.

### Original convergence pertained to presentation-only scope

The 3 rounds of /draft-plan adversarial review converged on a
presentation-only refactor (rename + 4-tab WCAG APG keyboard nav). The
user subsequently expanded scope to a **dashboard quality-of-life pass**:
collapsed Worktrees-as-its-own-tab into a single BRANCHES tab with
inline worktree-info, dropped the WCAG-APG arrow-key handler in favor
of a mouse-first design, and added a functional-bug-fix phase (Phase 5
sub-sections 5a/5b/5c/5d/5e).

### Structural comparison (Original /draft-plan output vs. Refined output)

| Phase | Original (post-/draft-plan) | Refined (post-/refine-plan Round 1) | Delta |
|---|---|---|---|
| 0 — Worktree setup | Unchanged | Unchanged | — |
| 1 — Rename | Unchanged | Unchanged | — |
| 2 — Tab scaffold | 4 tabs (PLANS/ISSUES/BRANCHES/WORKTREES); HTML moves 5 panels into 4 tabpanels; renderBranches body unchanged; renderWorktrees preserved | 3 tabs (PLANS/ISSUES/BRANCHES); HTML moves 3 panels into 3 tabpanels; renderBranches enriched with worktreesByBranch helper + inline pill/path/age sub-row per backed branch; renderWorktrees + fingerprintWorktrees + lastFingerprint.worktrees + applySnapshot worktrees-branch all DELETED | Major: -1 tab, -1 render fn, -1 fingerprint fn; new helper + enrichment in renderBranches; new CSS for landed-status pills; 3-entry panel-class test loop (was 5) |
| 3 — Tab behavior | Click handler + keyboard arrow/Home/End handler with roving tabindex + automatic activation; TAB_SLUGS has 4 entries; setActiveTab manages tab.tabIndex | Click handler + hashchange only; NO keydown handler; NO roving tabindex; TAB_SLUGS has 3 entries; setActiveTab does NOT manage tab.tabIndex; setActiveTab signature drops the `focus` argument | Major: keyboard-nav behavior DROPPED; mouse-first lock |
| 4 — Manual playwright + tests | 10-step checklist + step 9b; 5 screenshots; step 3 was keyboard nav | 12-step checklist + step 9b; 4 screenshots; step 3 reframed as keyboard-reachability-only (no arrow-key assertion); step 9 reframed to use #branches deep-link + #worktrees fall-through-to-#plans; new step 11 (banner-no-flap) + step 12 (Origin-check) | Major: +2 steps, -1 screenshot, step 3 reframed |
| 5 — Dashboard functional fixes | (did not exist) | NEW phase: 5a investigate-first; 5b `_origin_ok` policy fix at server.py:601-610; 5c READY-drop diagnose-and-fix (may close as fixed-by-5b); 5d disconnect-flap diagnose-and-fix; 5e /work-on-plans queue-honoring verification (likely no-bug per V5) | NEW |

### Stale rows in the historical disposition tables

The following rows in the Round 1/2/3 tables ABOVE are stale under the
refined scope. They are NOT modified (historical integrity); the
annotation here flags their current relevance:

- **R3** (Round 1) — "Enter/Space not handled in keyboard switch …
  rationale added to Phase 3 Design & Constraints." **STALE under
  mouse-first lock**: Enter/Space are handled natively by `<button>`
  semantics; the explanatory prose about roving tabindex is no longer
  applicable. The current Phase 3 Design & Constraints addresses the
  mouse-first design directly.
- **R11 / DA13** (Round 1) — "Deep-link flash before boot() runs
  setActiveTab … inline early-init (idempotent), guarded by
  `document.readyState`." **PARTIALLY STALE**: the original 4-slug
  deep-link case `/#worktrees` is now an invalid slug that falls
  through to `#plans` — no panel-switch happens for that hash. The
  inline early-init is still relevant for the surviving 3 slugs
  (`#plans` / `#issues` / `#branches`).
- **R2-DA-7** (Round 2) — "Wholesale HTML paste fragility … 89-line
  file is small enough that wholesale replacement is acceptable."
  **STALE prose**: the refined HTML body is shorter (3 tabpanels, not
  4). The justification still applies in principle, but the file is
  even smaller now.
- **R2-DA-8** (Round 2) — "Tab key prose wrong about where focus lands
  first." **PARTIALLY STALE**: the Tab key analysis for roving
  tabindex is no longer applicable (no roving tabindex under
  mouse-first). The new Phase 3 Design & Constraints describes DOM
  Tab order directly without invoking roving-tabindex semantics.
- **DA6** (Round 1) — "panel-activity ordering." **EXTENDED**: now
  also applies to `panel-worktrees`, which is removed in the same
  Phase 2 commit as `panel-activity`. Both removals are in lockstep
  with the test loop update from 5 entries to 3.

### /refine-plan Round 1 disposition table

Round 1 produced 12 reviewer findings (R1-R12), 12 devil's-advocate
findings (DA1-DA12), and 7 orchestrator-verified empirical claims
(V1-V7). The reviewer/DA streams overlap heavily — `R1=V1=DA1`,
`R10=V2=DA2`, etc. Disposition columns: **Fixed** = plan text edited;
**Justified** = no fix needed, rationale recorded. Evidence column:
**Verified** = orchestrator re-ran the cited grep / file:line check;
**Judgment** = scope/design decision; **Not reproduced** = empirical
claim that did not hold.

See the companion file `/tmp/refine-plan-refined-round-1-DASHBOARD_TABS_AND_RENAME.md`
for the full row-by-row disposition table (one row per R1-R12, DA1-DA12,
V1-V7).

### /refine-plan Round 2 disposition table

Round 2 surfaced 6 BLOCKING findings (B1-B6) plus 5 polish items
(P1-P5). Two of the blockers (B1, B2) were defects introduced by
Round 1's refinement itself — verified by re-reading the actual
`renderWorktrees` body at app.js:798-834 and `tests/run-all.sh`
(explicit `run_suite` list, no auto-discovery). Each Round 2 finding
was re-verified against the live tree before the orchestrator edited
the plan; see `/tmp/refine-plan-refined-round-2-DASHBOARD_TABS_AND_RENAME.md`
for the full row-by-row table.

| # | Finding (short) | Evidence | Disposition |
|---|---|---|---|
| B1 | Phase 2 enrichment used wrong accessors (`w.landed_status`, open-coded basename, duplicated pill class mapping) — Round 1 regression | Re-read app.js:798-834 — actual accessor is `w.landed ? w.landed.status : "not-landed"`; `landedPillClass` at app.js:791-796; `basename` at app.js:89 | **Fixed**: Phase 2 JS sketch rewritten with correct accessors; mandatory-reuse note added for `landedPillClass` / `basename` / `ageSecondsToText`; cleanup step now flags both helpers as RETAIN; verify-grep adds `function (landedPillClass\|basename)` survival check. |
| B2 | New tests (`test_zskills_monitor_csrf.sh`, `test_zskills_dashboard_disconnect_debounce.sh`) defined but never registered in `tests/run-all.sh` — Phase 4 `bash tests/run-all.sh` would not execute them | Re-read `tests/run-all.sh` — explicit `run_suite` list, no auto-discovery (verified — 4 dashboard-related entries enumerated at lines 93-99) | **Fixed**: Phase 5b and Phase 5d ACs now each include a `tests/run-all.sh` test-registration work item with explicit `run_suite` line + grep AC. |
| B3 | 5c subsumption predicate was hand-wavy ("if 5a finds the symptom was 403'd") | 5a AC list lacked a falsifiable check | **Fixed**: 5a AC now requires two-condition predicate — (a) `5c-repro.txt` server-log shows HTTP 403 on drop-POST; (b) post-5b-fix re-run returns 200 AND `/api/state` shows the card moved. Both must be logged in the 5a diagnosis document. |
| B4 | Phase 5 Dependencies did not state the 5a → 5b/c/d partial order, so a parallel-dispatch orchestrator could start 5b before 5a's outputs exist | 5b/5c/5d each explicitly consume 5a outputs (`5b-repro.txt`, `5c-repro.txt`, `5d-repro.txt`, `5A_DIAGNOSIS.md`) | **Fixed**: Phase 5 Dependencies section now states strict `5a → (5b, 5c, 5d)` partial order; 5b/5c/5d parallel-with-each-other; 5e independent. Orchestrator MUST gate dispatch on 5a commit landing. |
| B5 | Step 12 reproducer prose said "reuse them here" without specifying when/how the commands enter the verifier prompt — verifier has no access to `/tmp/dashboard-phase5/` | Phase 4 verifier prompt template uses `[PASTE THE 12-STEP CHECKLIST FROM THIS PHASE HERE]` — orchestrator does inline expansion at dispatch | **Fixed**: "Dispatch verifier subagent" work item now mandates pre-dispatch inlining — orchestrator reads `5b-repro.txt` and substitutes the captured curl commands into step 12 BEFORE dispatching. Mirror for step 11 / `5d-repro.txt`. |
| B6 | Steps 11/12 unconditionally asserted Phase 5 fixes; if 5b or 5d closed as deferred / no-bug, the verifier would FAIL Phase 4 | Re-read step 11/12 — vague "document that and accept current behavior as baseline" handling | **Fixed**: steps 11 and 12 restructured with explicit conditional behavior keyed off `DASHBOARD_TABS_AND_RENAME_5B_DEFERRED.md` / `_5D_DEFERRED.md` markers — DOWNGRADE to baseline-observation (PASS regardless) or assert-fix (FAIL on regression). Orchestrator inlines the branch at prompt-construction time. |
| P1 | Phase 2 CSS added 3 pill-landed classes already present at app.css:213-215 — duplication risk | `grep -n pill-landed app.css` — 3 classes exist | **Fixed**: Phase 2 CSS work item reframed as "DO NOT duplicate; update in place only if visual tweak is needed (none required for parity)"; new `.card-worktree-row .mono` is the only added selector; AC tightened to `grep -cE '^\.pill-landed-(full\|partial\|not)'` returns exactly 3 (no net add). |
| P2 | `app.js:599` cited as the dropzone class site, but the actual drag/drop handler family lives at app.js:1338-1380 | Re-read app.js — `onDragOver` at 1326, `onDragEnter` at 1339, `onDragLeave` at 1347, `onDrop` at 1365; line 599 is unrelated code | **Fixed**: 5a step 2 prose and 5c justification updated to cite app.js:1338-1380; 5c reproducer adds explicit `dz.dataset.kind` + `dz.dataset.column` (NOT `data-col`) eval snapshot — verified against app.js:1372 reading `dz.getAttribute("data-column")`. |
| P3 | Detached-HEAD worktrees surface visibility loss post-refactor not documented as Out-of-scope | Drift Log review | **Fixed** (P3 entry below in this Drift Log): added an Out-of-scope drift-log note flagging the surface-visibility regression for detached-HEAD worktrees (renderBranches enriches per-branch; a worktree on a detached HEAD has no branch row to attach to). |
| P4 | Phase 5 sub-row tracker missing — granular state per sub-section not tracked | Progress Tracker review | **Fixed** (P4 entry below in this Drift Log): added a recommended sub-row tracker layout that a future commit can apply to the live Progress Tracker without rebooting plan state. Live tracker is not edited in this round (the table currently has 1 row per phase; expansion to sub-rows is a Phase 5 implementation detail). |
| P5 | "Converged at end of round 3" caveat absent — claim applies to the original presentation-only scope, not the refined dashboard QoL scope | Plan Quality / Convergence section | **Fixed** (P5 entry below in this Drift Log): added a caveat under Convergence noting the original convergence pertained to presentation-only scope; the current plan re-converged under expanded scope via /refine-plan Rounds 1 and 2 — see Drift Log. |

#### Drift Log entries from Round 2

- **P3 — Out-of-scope: detached-HEAD worktrees lose surface visibility.**
  Round 2 collapsing the Worktrees tab into per-branch enrichment in
  `renderBranches` means a worktree whose HEAD is detached (no
  associated branch row) has no surface to attach to — that worktree
  becomes invisible in the dashboard UI. The Plans / Issues / Branches
  partition does not include a fallback list for orphan worktrees.
  This is a knowingly accepted trade-off (detached-HEAD worktrees are
  rare in zskills agent workflows; the worktree is still queryable via
  `git worktree list` and `/api/state.worktrees` in the JSON shape).
  Not a Phase 5 blocker. If usage shows this is a regression, a
  follow-up plan can re-introduce an "Other worktrees" section beneath
  the Branches list (~20 LOC).

- **P4 — Recommended Phase 5 sub-row tracker layout.** The live Progress
  Tracker table currently uses 1 row per phase. For granular Phase 5
  state, a future commit may expand row 5 into 5 sub-rows (one per
  sub-section). Recommended layout:
  ```
  | 5a — Diagnose first       | ⬚ |   |   |
  | 5b — Origin-check fix      | ⬚ |   |   |
  | 5c — READY drop diag/fix   | ⬚ |   |   |
  | 5d — Disconnect-flap fix   | ⬚ |   |   |
  | 5e — /work-on-plans verify | ⬚ |   |   |
  ```
  Not applied to the live tracker in this refinement round to avoid
  conflicts with the existing 1-row Phase 5 entry already on the
  branch; the implementing agent for Phase 5 may apply this layout as
  part of the 5a commit if it improves visibility.

- **P5 — Convergence caveat.** The "Converged at end of round 3" claim
  in the Plan Quality section pertains to the ORIGINAL presentation-only
  scope (rename + 4-tab WCAG APG). The current plan re-converged
  under the EXPANDED scope (3-tab merger + mouse-first lock + Phase 5
  functional fixes) via /refine-plan Round 1 (post-scope-expansion
  refinement) and Round 2 (this round — addressed 2 Round 1
  regressions plus 4 additional blockers). The Round 1/2/3 historical
  tables ABOVE in this plan are preserved as-is; their dispositions
  remain valid for the original scope but several rows are flagged
  STALE under the refined scope (see "Stale rows" section above).

#### Phase 4 structural-comparison update (Round 2 changes)

Steps 11 and 12 are now CONDITIONAL on Phase 5 deferral markers (vs.
unconditional assertions before Round 2). The structural-comparison
table above remains accurate for step counts (12 + 9b), but the
behavior of steps 11/12 now branches on
`DASHBOARD_TABS_AND_RENAME_5{B,D}_DEFERRED.md` file presence. The
verifier prompt's PASS/FAIL table accepts `N/A — Phase 5{b,d}
deferred` as a non-failing skip outcome for those rows.

## Plan Review

**Refinement process:** /refine-plan with 2 rounds of adversarial review
(reviewer + devil's-advocate dispatched in parallel each round; refiner
applies fixes with verify-before-fix discipline).

**Convergence:** Converged at end of round 2. All 42 findings across the
2 rounds dispositioned: 40 Fixed, 2 Justified (the same observation —
SKILL.md `metadata.description` is already neutral, no rename action
needed), 0 Not-reproduced, 0 Deferred.

**Remaining concerns:**
- Phase 5 sub-row tracker layout (P4) is recommended but not applied to
  the live Progress Tracker — the implementing agent for Phase 5 may
  expand the single Phase 5 row into 5 sub-rows when 5a lands, if that
  improves visibility during autonomous execution. Not a blocker.
- The original /draft-plan Round 1/2/3 disposition tables (above the
  Refinement Drift Log) document the presentation-only-scope
  convergence; several rows are flagged STALE under the refined scope
  but the historical content is preserved. Future agents reading those
  rows should consult the Refinement Drift Log's stale-row annotations.

### Refinement Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Total Substantive | Resolved |
|-------|-------------------|---------------------------|-------------------|----------|
| 1     | 12 (R1-R12)       | 12 (DA1-DA12)             | 31 incl. V1-V7    | 29 Fixed + 2 Justified |
| 2     | 7 (B1-B6, P1-P5)  | 8 (overlapping w/ B/P)    | 11 unique         | 11 Fixed |

### /refine-plan vs original /draft-plan scope

The earlier /draft-plan adversarial loop (3 rounds, 57 findings) converged
on a **presentation-only refactor**. The user subsequently expanded scope
to a **dashboard quality-of-life pass** absorbing functional bugs. The
/refine-plan pass closed factual errors in the user's scope-expansion
guidance (no `/api/move-plan` endpoint; `_origin_ok` has 3 callers not 4;
disconnect-flap hypothesis empirically false), locked the mouse-first /
3-tab user preferences, and added Phase 5 (with strict 5a→5b/c/d
sequencing and per-sub-section time-boxes) for the bug fixes. The plan is
ready for autonomous `/run-plan` execution.
