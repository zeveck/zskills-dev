# Plan Report — Dashboard Tabs and Rename

## Phase — 4 Manual playwright verification + automated tests

**Plan:** docs/plans/DASHBOARD_TABS_AND_RENAME.md
**Status:** Completed (verified) — substantively PASSED with 1 PLAN-TEXT-DRIFT documented
**Worktree:** /tmp/zskills-pr-dashboard-tabs-and-rename
**Branch:** feat/dashboard-tabs-and-rename
**Commits:** a361685 (Phase 4 marked done) + 8fad769 (tracker row fix)
**Server:** started by orchestrator on port 8181 with `--main-root /tmp/zskills-pr-dashboard-tabs-and-rename`; verifier ran checklist against it; orchestrator stops it post-phase

### Step-by-step PASS/FAIL summary

| Step | Result | Evidence |
|------|--------|----------|
| 1 — Default state on load | PASS | title + h1 = "Z Skills Dashboard"; active tab = `tab-plans`; activity-strip visible; 3 tabs; no `tab-worktrees` |
| 2 — Click each tab (Issues) | PASS | aria-selected flip + hash + visibility correct |
| 2 — Click each tab (Branches) | PASS | 20 `.pill-landed-*` elements present in Branches body (worktree info inline confirmed) |
| 2 — Click each tab (Plans) | PASS | aria-selected flip + hash + visibility correct |
| 3 — Keyboard reachability | PASS | Tab reaches tab buttons via DOM order; Enter activates focused inactive tab; DOM-forward Tab traversal |
| 4 — Drag-and-drop within Plans | PASS | `plans-live` textContent has literal `"Moved plan "` prefix; no `#conn-banner` during/after drag |
| 5 — Switch tabs during poll | PASS | 5× rapid switches; no new JS errors; `#issues-body` re-populates on next poll |
| 6 — Modal flow inside tab | PASS | Double-click → modal open; Esc → modal close + focus returns to card |
| 7 — Globals stay visible across tabs | PASS | After SIGTERM, `#conn-banner` visible on all 3 tabs; `closest("[role=tabpanel]") === null` confirmed (banner outside tab structure); server restarted, banner returned to hidden |
| 8 — Narrow viewport (600×900) | PASS | `.tablist` overflowX `auto`; tabs still clickable; screenshot saved |
| 9 — URL hash deep-link | PASS | `/#branches` activates branches tab; reload preserves; `/#worktrees` falls back to `tab-plans` (hash kept as-is, no rewrite) |
| 9b — Browser back/forward | DRIFT | Plan asserts back → `#issues`; implementation uses `history.replaceState` (per Phase 3 design — no back-stack pollution). Back skips past tab clicks. See drift section below. |
| 10 — Screenshots (4 total) | PASS | All 4 files saved + renamed |
| 11 — Connection banner during 5 rapid drags (DOWNGRADED) | PASS | Phase 5d not yet run; baseline observation: `#conn-banner.hidden === true` throughout (no flap observed; banner element exists with static template) |
| 12 — Origin-check | N/A | Phase 5b deferred (4→5 order) — reproducers don't exist; skipped per prompt-template gating |

### Test run

**Overall: 2933/2933 passed, 0 failed.** Exit code: 0.

Required-green tests confirmed:
- `tests/test_zskills_monitor_dashboard_ui.sh` — PASS
- `tests/test_zskills_dashboard_skill.sh` — PASS
- `tests/test_zskills_monitor_server.sh` — PASS
- `tests/test_zskills_monitor_collect.sh` — PASS
- `tests/test-skill-conformance.sh` — PASS

Phase 5 tests (`test_zskills_monitor_csrf.sh`, `test_zskills_dashboard_disconnect_debounce.sh`) don't exist yet — expected for 4→5 order.

### Programmatic AC checks (orchestrator)

- ≥13 rows in PASS/FAIL pipe table: ✓ (14 rows)
- ≥13 PASS/FAIL literals: ✓
- ≥4 screenshot paths matching `/.../\.playwright/output/.*\.png`: ✓ (4 paths, all `test -f` confirmed)
- Response contains literal "exit code": ✓
- Layer 3 (`verify-response-validate.sh`): PASS

### Screenshots

- `/tmp/zskills-pr-dashboard-tabs-and-rename/.playwright/output/phase4-tab-plans.png` (133634 bytes)
- `/tmp/zskills-pr-dashboard-tabs-and-rename/.playwright/output/phase4-tab-issues.png` (89872 bytes)
- `/tmp/zskills-pr-dashboard-tabs-and-rename/.playwright/output/phase4-tab-branches.png` (110490 bytes)
- `/tmp/zskills-pr-dashboard-tabs-and-rename/.playwright/output/phase4-tab-narrow.png` (104226 bytes)

### PLAN-TEXT-DRIFT — Step 9b (logical contradiction with Phase 3 design)

**Token:** `PLAN-TEXT-DRIFT: phase=4 bullet=9b field=back-button-history-semantics plan=back-returns-to-#issues actual=back-skips-tab-clicks-due-to-replaceState`

The verifier flagged that Phase 4 step 9b's assertion ("press browser back, assert URL ends with `#issues`") is logically impossible under Phase 3's design choice. Specifically:

- **Phase 3 design constraint** (`/tmp/phase-3-text.md` line 165): "`history.replaceState` not `pushState` — tab switches should not pollute the back-stack with one entry per click. Reload-survival is the goal; navigation history is not."
- **Phase 3 AC #1 (re-verified Phase 3)**: `history.replaceState` confirmed at app.js:1693; zero new `pushState` usages.
- **Phase 4 step 9b assertion (this phase)**: "press back, URL → `#issues`" — requires `pushState` so that the tab click creates a history entry that back can navigate to.

These two are mutually exclusive. The implementation correctly follows Phase 3's chosen UX (tabs are a view-state, not navigation; back exits the dashboard rather than cycling tabs). Step 9b's assertion is a plan-text bug, NOT an implementation defect.

**Resolution path for plan author:**
1. **Option A (recommended):** amend step 9b to read "press back, assert browser navigates away from dashboard (e.g., to previous page in the back-stack), since `replaceState` means tab clicks do not enter history." This matches Phase 3 design and is the verifier's observed behavior.
2. **Option B:** change Phase 3 to use `pushState` (one history entry per tab click) — but this conflicts with the explicit design rationale ("should not pollute the back-stack").

The user should choose Option A unless they want tab clicks in history. Either way, **no implementation change is required** — Phase 3 + Phase 4 are correct except for this one AC text.

### Verification

- Verifier subagent (manual playwright + automated tests): all structural ACs met (14 rows, 4 screenshots, exit-code surfaced)
- Layer 3 response validation: PASS (no stalled-string match; response >>200 bytes; substantive content)
- 12 of 14 step rows PASS; 1 N/A (deferred to Phase 5b); 1 DRIFT (documented above)
- Tests: **2933/2933 PASS**

### User Sign-off

- [ ] **P4-1 — Title rename visible:** open the dashboard at `http://127.0.0.1:<port>/` in a real browser. Confirm the window title says "Z Skills Dashboard" (not "Z Skills Monitor"). See screenshot: `.playwright/output/phase4-tab-plans.png`.
- [ ] **P4-2 — 3 tabs visible, no Worktrees tab:** confirm the tablist shows only PLANS / ISSUES / BRANCHES. No WORKTREES button. See screenshot: `.playwright/output/phase4-tab-plans.png`.
- [ ] **P4-3 — Activity strip persistent above tablist:** confirm the activity strip is above the tablist on every tab (Plans, Issues, Branches). See all 3 tab screenshots.
- [ ] **P4-4 — Branches tab shows worktree info inline:** click the Branches tab. For backed branches, confirm a sub-row appears showing path basename + age + landed-status pill. See screenshot: `.playwright/output/phase4-tab-branches.png` (20 `.pill-landed-*` elements verified).
- [ ] **P4-5 — Narrow viewport works:** resize browser to ~600px wide. Confirm the tablist scrolls horizontally instead of wrapping; tabs remain clickable. See screenshot: `.playwright/output/phase4-tab-narrow.png`.
- [ ] **P4-6 — URL hash deep-link works:** open `/#branches` directly; the Branches tab should be active on load (brief Plans flash <200ms acceptable).
- [ ] **P4-7 — Plan author to decide Step 9b resolution:** review the back-button drift signal above; pick Option A (amend plan AC text — recommended) or Option B (change implementation to pushState). Either way, file a follow-up commit. This is a plan-text fix, not a code fix.

---

## Phase — 3 Tab behavior (JS + URL hash, mouse-first)

**Plan:** docs/plans/DASHBOARD_TABS_AND_RENAME.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-dashboard-tabs-and-rename
**Branch:** feat/dashboard-tabs-and-rename
**Commits:** 04f945a (impl, 4 files, +112/-2) + 9827845 (tracker → ✅ Done)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | `TAB_SLUGS = ["plans", "issues", "branches"]` constant | Done | line 1671 |
| 2 | `readTabFromHash()` function | Done | line 1673 |
| 3 | `setActiveTab(slug, {pushHash})` function | Done | line 1678; uses `history.replaceState` (not pushState) |
| 4 | `bindTabEvents()` function — click + hashchange listeners | Done | line 1697 |
| 5 | `boot()` integration — `bindTabEvents()` + `setActiveTab(readTabFromHash(), {pushHash: false})` between `bindActionEvents()` and `schedulePoll(0)` | Done | lines 1726-1727 |
| 6 | Inline early-init block (best-effort flash mitigation) | Done | line 1718; guarded by `document.readyState !== "loading"` |
| 7 | Version bump + mirror + verify-no-drift | Done | 2026.05.13+2681bb → 2026.05.13+acfe93 |

### Mouse-first lock (verified)

- NO `keydown` handler added in new code
- NO `Arrow`/`Home`/`End` key references
- NO roving `tab.tabIndex` management
- NO `pushState`; only `replaceState` (no back-stack pollution)
- NO `innerHTML =`, NO `eval(`, NO `new Function`, NO `setInterval(`

### Verification

- Implementation agent: 8 ACs PASS (with one false-alarm drift signal about version-bump history; verifier confirmed no actual issue)
- Verifier agent (independent): 12 ACs PASS — all `git diff --cached` `^+` line checks return zero new prohibited tokens; boot() body verified verbatim
- Layer 3 response validation: PASS
- Tests: **2933/2933 passed** on clean re-run (one transient flake on `test-briefing-parity.sh` — unrelated to Phase 3; root cause: parity test reads live `git worktree list` and another concurrent process can flip the count mid-suite)
- Mirror diff: empty
- Phase 1 rename intact: 0 hits
- Untouched symbols: `pollOnce`/`schedulePoll`/`pollAbort`/`applySnapshot`/all `render*`/all `fingerprint*`/`visibilitychange` confirmed unchanged

### Ambient flake observation

`test-briefing-parity.sh` had a one-off `worktrees: node keys=[list:21] vs py keys=[list:22]` mismatch on the first run, then passed cleanly on re-run. The test reads `git worktree list` from two subprocesses; another agent creating/removing a worktree between the two reads produces a one-off diff. Not blocking. Worth filing as an ambient-flake issue post-pipeline if it recurs.

### User Sign-off

- [ ] **P3-1** — Tab switching (mouse): open the dashboard at `http://127.0.0.1:<port>/`, click each tab (Plans → Issues → Branches → Plans). Expect:
  1. Clicked tab gains underline + bold (`aria-selected="true"`).
  2. Previously-active tab's panel hides; clicked tab's panel becomes visible.
  3. URL bar updates to `#plans` / `#issues` / `#branches`.
  4. Browser back/forward (or external `#issues` link) updates active tab via `hashchange`.
  5. Reload preserves the active tab (URL hash is the source of truth).
- [ ] **P3-2** — Tab key behavior: `Tab` cycles through `Plans → Issues → Branches → <next focusable in active tabpanel>` in DOM order. No roving tabindex; all three tab buttons are reachable. Enter/Space on focused tab activates it (native button semantics).
- [ ] **P3-3** — Deep-link `/#branches` opens the Branches tab. A brief sub-200ms transient frame showing Plans first is acceptable (module scripts defer to after parse; flash mitigation is best-effort).
- [ ] **P3-4** — Polling unaffected: with Issues tab active, watch a plan progress through phases; switch to Plans — see fresh state. The 2s poll renders into all slots regardless of active tab.

(Phase 4 will exercise all of these via playwright-cli with screenshots.)

---

## Phase — 2 Tab scaffold (HTML + CSS)

**Plan:** docs/plans/DASHBOARD_TABS_AND_RENAME.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-dashboard-tabs-and-rename
**Branch:** feat/dashboard-tabs-and-rename
**Commits:** 2233a91 (impl, 9 files, +342/-226) + 59b1776 (tracker → ✅ Done)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | index.html — body restructure | Done | activity-strip + tablist (3 tabs) + tabpanels around Plans/Issues/Branches; worktrees panel removed |
| 2 | app.css — delete `.grid` + media-query block | Done | lines 89-110 of old file removed |
| 3 | app.css — add `.activity-strip`, `.tablist`, `.tab`, `.tabpanels`, `.tabpanel`, `.card-worktree-row .mono` | Done | `.pill-landed-*` retained (existing); `.tabpanel[hidden]{display:none}` defensive rule present |
| 4 | app.js — add `worktreesByBranch` helper near `backedBranchSet` | Done | exactly 2 grep hits (def + use) |
| 5 | app.js — enrich `renderBranches(branches, worktrees)` with worktree sub-row | Done | reuses `landedPillClass`, `basename`, `ageSecondsToText`; uses `textContent`/`appendChild` only (no `innerHTML`) |
| 6 | app.js — delete `renderWorktrees`, `fingerprintWorktrees`, `lastFingerprint.worktrees`, worktrees arm of `applySnapshot` | Done | 0 grep hits for any removed symbol |
| 7 | app.js — retain `landedPillClass` + `basename` for reuse | Done | both present |
| 8 | tests/test_zskills_monitor_dashboard_ui.sh — panel-class loop 5→3 + new assertions | Done | activity-strip-present + worktrees-removed pass |
| 9 | Version bump + mirror + verify-no-drift smoke | Done | 2026.05.13+957fa2 → 2026.05.13+2681bb; diff empty; smoke PASS |

### Verification

- Implementation agent: 16 ACs PASS
- Verifier agent (independent): 20 ACs PASS + 7 function-body diffs all CLEAN (renderPlans, renderIssues, renderActivity, fingerprintPlans, fingerprintBranches, fingerprintIssues, fingerprintActivity byte-equal vs main)
- Layer 3 response validation: PASS
- Tests: **2933/2933 passed, 0 failed** (`test_zskills_monitor_dashboard_ui.sh` includes 3 new PASS lines)
- Initial visibility: Plans tabpanel NO `hidden`; Issues + Branches both `hidden` (matches plan)
- `diff -rq` source vs mirror: empty
- Phase 1 rename intact: `grep -rn 'Z Skills Monitor' skills/zskills-dashboard/` → 0 hits

### Independent drift signals

None.

### User Sign-off

The dashboard now visually has 3 tabs (Plans / Issues / Branches) and a persistent activity strip — but tab click switching is **NOT WIRED YET** (that's Phase 3). The Branches tab also gains inline worktree info (path/age/landed-status pill) when made visible.

Manual sign-off for this phase's UI visuals is bundled into Phase 4's manual playwright verification — clicking tabs won't switch them until Phase 3 lands, so spot-checking Phase 2 in isolation isn't meaningful (the static markup is what tests + greps already verified).

- [ ] **P2-1** — Once Phase 3 lands and you can navigate, confirm:
  1. Open `http://127.0.0.1:<port>/` in a browser.
  2. Confirm Plans tab is active by default (underline + bold).
  3. Confirm activity strip appears persistently above the tablist.
  4. Confirm Branches panel (once clickable) shows worktree info sub-rows for backed branches.

---

## Phase — 1 Rename "Z Skills Monitor" → "Z Skills Dashboard"

**Plan:** docs/plans/DASHBOARD_TABS_AND_RENAME.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-dashboard-tabs-and-rename
**Branch:** feat/dashboard-tabs-and-rename
**Commits:** 57907a9 (rename impl, 13 files, 87/87 ins/del) + e969fcc (tracker → ✅ Done)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | index.html — title + h1 | Done | "Z Skills Monitor" → "Z Skills Dashboard" |
| 2 | app.js — banner comment | Done | Line 1 |
| 3 | server.py — docstring, fallback HTML, argparse, log, `server_version` | Done | line 545: `"zskills-dashboard/0.1"`; class `MonitorHandler` preserved |
| 4 | collect.py — docstring prose | Done | module path `zskills_monitor.collect` preserved; +1 hit found at line 1220 ("zskills monitor state") edited per intent |
| 5 | SKILL.md — H1, prose, ~11 echo strings, `zskills-monitor` diagnostic | Done | filename `monitor-state.json` and `verify_monitor_identity` preserved |
| 6 | README.md — work-on-plans row | Done | "monitor dashboard" → "dashboard" |
| 7 | test_zskills_monitor_dashboard_ui.sh — title grep | Done | lines 291-292 |
| 8 | test_zskills_dashboard_skill.sh — sed pass + comment-prose hits | Done | 9 echo-string sites + 3 prose-in-comment hits (745/785/791) |
| 9 | Skill version bump + mirror | Done | 2026.05.07+a3fc3c → 2026.05.13+957fa2 |
| 10 | Verify-no-drift smoke | Done | fresh=957fa2 stored=957fa2 |
| 11 | `diff -rq` source vs mirror | Done | empty (no `__pycache__` drift after cleanup) |

### Verification

- Implementation agent: all ACs PASS
- Verifier agent (independent): 8/8 verification checks PASS
- Layer 3 response validation: PASS
- Tests: **2933/2933 passed, 0 failed** (full suite — baseline-truncated last suite ran cleanly post-impl)
- `test_zskills_monitor_dashboard_ui.sh`: 92/92 PASS
- `test_zskills_dashboard_skill.sh`: 35/35 PASS
- Baseline comparison: zero regressions, zero pre-existing failures

### PLAN-TEXT-DRIFT signals (informational; intent satisfied)

Four drift signals emitted during impl + verify; none required Phase 3.5 rollback. All ACs intent-satisfied even where the literal regex didn't match its prose description.

1. `phase=1 bullet=collect.py field=enumerated-prose-sites` — argparse description at line 1220 also had a prose hit ("zskills monitor state"); edited in lockstep with plan intent.
2. `phase=1 bullet=server.py field=line-3-docstring` — docstring was multi-line wrapped, not single-line; edited per intent.
3. `phase=1 bullet=AC7-audit-filter field=filter-regex` — AC filter regex doesn't escape `\.` correctly; line 211's load-bearing pattern slips through. Intent (filter out load-bearing hits) is met; the AC's filter regex is the imperfection.
4. `phase=1 bullet=AC4 field=expected-result` — AC text says "ONLY load-bearing hits" but its regex `[- ]` only matches hyphen/space, both of which were renamed; "zero hits" is the regex-correct result and consistent with rename success.

### Branch-name discrepancy (carried from Phase 0)

Plan literal: `feat/dashboard-tabs-rename`. Actual: `feat/dashboard-tabs-and-rename`. All ACs evaluated against the actual branch.

### User Sign-off

None required for Phase 1 (mechanical text rename; no behavior change; no UI flow change). The dashboard's window title now says "Z Skills Dashboard" but the user will see this confirmed in Phase 4's manual playwright verification.

---

## Phase — 0 Worktree setup

**Plan:** docs/plans/DASHBOARD_TABS_AND_RENAME.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-dashboard-tabs-and-rename
**Branch:** feat/dashboard-tabs-and-rename
**Commits:** 0bae915 (chore: mark phase 0 done — worktree setup verified)

### Work Items

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | Worktree created on feature branch | Done | `git worktree list` shows `/tmp/zskills-pr-dashboard-tabs-and-rename` at `feat/dashboard-tabs-and-rename` |
| 2 | Layer 0 hook (inject-bash-timeout.sh) executable | Done | `test -x` passes; PreToolUse hook for Bash confirmed |
| 3 | Layer 3 hook (verify-response-validate.sh) executable | Done | 7-pattern stalled-string array + 200-byte threshold confirmed |
| 4 | Verifier agent definition tools allowlist | Done | `Read, Grep, Glob, Bash, Edit, Write` all present |
| 5 | Worktree clean, on expected branch | Done | `nothing to commit, working tree clean`; HEAD = `feat/dashboard-tabs-and-rename` |
| 6 | Config landing=pr, branch_prefix=feat/ | Done | confirmed in `.claude/zskills-config.json` |
| 7 | No `skills/zskills-dashboard/` modifications | Done | `git diff main -- skills/zskills-dashboard/` empty |

### Verification

- Implementation agent: 7/7 PASS
- Verifier agent (independent): 7/7 PASS
- Layer 3 response validation: PASS
- Tests: skipped — no code changes in Phase 0 (no diff to test)
- Acceptance criteria: all met

### Branch-name discrepancy (informational)

The plan text references branch `feat/dashboard-tabs-rename` (no "and"), but the
actual created branch is `feat/dashboard-tabs-and-rename` (with "and"), derived
by /run-plan's PR-mode slug logic from filename `DASHBOARD_TABS_AND_RENAME.md`.

All Phase 0 ACs that reference the literal `feat/dashboard-tabs-rename` were
evaluated against the actual branch and pass — substantively identical. The
discrepancy is purely a text drift in the plan's literal branch label, not a
structural issue.

**Recommendation for plan author:** in a later phase (or now via /refine-plan),
update plan AC text to read `feat/dashboard-tabs-and-rename`. This avoids
confusion if anyone reads the plan in isolation.

### User Sign-off

None required for Phase 0 (no UI changes, no code changes).

---
