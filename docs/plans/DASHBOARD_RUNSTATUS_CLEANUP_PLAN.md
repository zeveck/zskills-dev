---
title: Dashboard Run-Status Cleanup
created: 2026-06-02
status: active
---

# Plan: Dashboard Run-Status Cleanup

> **Landing mode: PR** (`main_protected: true`). Implementer runs in a worktree; landing is via `/land-pr` dispatched by `/run-plan`.

## Overview

This plan combines the work tracked in **GitHub issues #1005 (Plans cleanup) and #1006 (Issues × dismiss)** into a single cohesive `/run-plan` execution. The deliverable is a focused cleanup of the dashboard's run-status surface plus per-card mode-related affordances. Net effect: more code deleted than added; clearer behavioral contracts for `/work-on-plans` mode resolution and dashboard chip semantics.

The cleanup has three behavioral pillars:

1. **RIP the top-level run-status pill and all trigger-script plumbing.** The pill (its top-level `#run-status` `div` in the dashboard markup, the JS render path that populates it, the `/api/trigger` endpoint that drives it, the `/api/work-state/reset` "clear-stale-sprint" escape hatch, the `dashboard.work_on_plans_trigger` config field, and the `/update-zskills` backfill that writes it) has accumulated edge-case patches across #930, #933, #995/#997, and is consistently a bug surface. PR #997 was the most recent patch; this plan supersedes it by removing the container outright. The work-state file (`work-on-plans-state.json`) and `/api/work-state` GET endpoint stay (used by other consumers + the per-batch `batch_mode` writeback), but `/api/trigger` and `/api/work-state/reset` go.

2. **Make per-plan mode pins a hard constraint at the `/work-on-plans` boundary, not a default override.** Today, `/work-on-plans <N> phase` will silently override a plan pinned to `finish`. After this plan, an explicit per-plan pin that conflicts with the explicit sprint batch mode causes that plan to be SKIPPED (with a skip marker written to `monitor-state.json` under the `plans.skipped` field), and a skip event flows through to the dashboard's activity feed. (A directly typed `/run-plan <slug> finish` still bypasses the pin — that's an explicit one-shot CLI override, not a batch dispatch; see Phase 2 Design & Constraints for the scoping rationale.) The chip becomes a three-state UI (INHERIT / PHASE / FINISH) with the INHERIT label rendered explicitly rather than collapsing to a literal `"finish"` token. The mode chip locks (disabled toggle) when a FINISH claim is in-flight; PHASE claims remain togglable because the next inter-phase dispatch re-reads the pin.

3. **Give both Plans and Issues skip-chips a × dismiss affordance — with deliberately asymmetric semantics.** **Plans skip is EPHEMERAL** (per-event): the marker auto-clears via three paths — claim acquire (system-resolved), pin-toggle (user re-pinned to match), and × click (user dismisses). **Issues skip is STICKY** (post-#808/#862): clicking × on an Issues skip-chip dispatches the existing `/fix-issues reconsider <N>` write (append to `issues.reconsider[]`); the chip stays until the next `/fix-issues` fire re-triages. The × buttons LOOK the same; the write paths differ. The plan explicitly does NOT try to unify these two skip mechanisms into one schema — that asymmetry is intentional.

**Explicit non-goal:** This plan does not make Plans-skip and Issues-skip semantically parallel. They share a visual affordance only. Anyone reading this plan and tempted to extract a "shared skip-clear infrastructure" should stop — that work is out of scope and the asymmetry is by design (see Prior Art research §7 + #813/#862 history).

Issues addressed: #1005 (this plan covers items 1–7) and #1006 (item 8). Both issues will be closed by the same merged PR via PR-body `Closes #1005` / `Closes #1006` footers (one keyword per issue — comma-list silently misses the rest; ref `feedback_pr_closes_keyword_per_issue`).

## Shared Conventions

### Files in scope (by role, not by line number)

The implementer reads each file at HEAD before editing. Line numbers shift; roles do not.

**Dashboard skill (`skills/zskills-dashboard/`):**
- The static `index.html` shell that holds the `#run-status` div inside the Plans panel.
- The dashboard front-end script (`scripts/zskills_monitor/static/app.js`) — multiple roles touched: the run-status surface (TRIGGER_URL constant, `renderRunStatus`, `fetchWorkState`, `pollWorkOnce`, `scheduleWorkPoll`, `applyWorkState`, `postTrigger`, `postWorkStateReset`, and the action-handler arms for `run-top-n` / `run-stop` / `clear-stale-sprint`); the per-plan mode-chip render path inside `buildPlanCard`; the existing issues skip-chip render path; the action delegator `handleAction`; the fingerprint helpers `fingerprintPlans` and `fingerprintIssues`.
- The stylesheet (`scripts/zskills_monitor/static/app.css`) — run-status block, run-* / clear-stale-* button rules, the skip-chip base + variant rules, the activity-status pill rules, the mode-chip rules.
- The server (`scripts/zskills_monitor/server.py`) — the trigger-config validator, the request-dispatch table, the trigger and work-state POST handlers (`_handle_trigger_post`, `_handle_work_state_reset`), the work-state GET handler (`_handle_work_state_get` — KEPT minus its `trigger_configured` field injection), the state-error block in `_handle_state`, the queue POST handler (which Phase 1 broadens to preserve-by-default; the role is "the handler that re-writes the monitor-state queue document on dashboard drag-drop"), and the prose comments at the top of the file and inline that reference trigger config.
- The state reader inside the collector (`scripts/zskills_monitor/collect.py`) — the function that loads `monitor-state.json` and shapes it for the dashboard snapshot; the `_annotate_plans_queue` path that attaches per-slug annotations to plans cards.
- The dashboard skill SKILL.md — the Configuration section that documents the trigger-script feature.

**Work-on-plans skill (`skills/work-on-plans/`):**
- SKILL.md — the cross-process flock contract paragraph (where the `with_monitor_lock` shape is documented inline).
- `modes/execute.md` — Step 0 argument parsing (already exports `MODE_OVERRIDE`); the SPRINT_ID / PIPELINE_ID computation block; the existing in-flight-claim filter pipe (the new mode-mismatch filter is wired in IMMEDIATELY AFTER it); the `BATCH_MODE` resolution line (whose ordering is NOT changed); the dispatch-count derivation downstream of the filter; the status-line slot just before the empty-queue exit; the step-marker write block.
- A NEW sibling script under `skills/work-on-plans/scripts/` — see Phase 2.

**Run-plan skill (`skills/run-plan/`):**
- `scripts/claim-plan.sh` — specifically the `cmd_acquire` function and, within it, the fresh-acquire success path AFTER the python embed that performs the atomic write of the claim file (Phase 2 hooks the best-effort skip-clear into the bash that resumes after the heredoc terminator, BEFORE the function returns).

**Fix-issues skill (`skills/fix-issues/`):**
- `subcommands/reconsider.md` — the canonical Python embed for `reconsider <N>` is referenced as a TEMPLATE for the new dashboard server endpoint; no source edit to fix-issues is required.

**Update-zskills skill (`skills/update-zskills/`):**
- SKILL.md — Step 3.6 backfill prose for the trigger-script field; the greenfield-write JSON sample that includes the trigger field.

**Config schema (`config/zskills-config.schema.json`):**
- The `dashboard` block — currently exists only to declare `work_on_plans_trigger`. Block goes entirely if that's the only property at edit time; otherwise drop the property only.

**Tests:**
- `tests/test-dashboard-run-status-locks.sh` — whole file dies in Phase 1.
- `tests/test_zskills_monitor_dashboard_ui.sh` — prune all assertions targeting the removed surface (deny-list grep below).
- `tests/test_zskills_monitor_server.sh` — prune the work-state/reset and trigger phase blocks (deny-list grep below).
- `tests/test-mode-chip-three-state.sh` — rewrite the INHERIT-related cases (Q1 + RF2 + new cases below).
- `tests/test-work-on-plans-dispatch-seam.sh` — add mode-mismatch-skip cases.
- New tests added per phase (enumerated in each phase).

### Invariants the refactor MUST preserve

1. **No new external dependencies.** Stdlib-only Python; no bundler; no jq; raw HTML/CSS/JS. (CLAUDE.md "Architecture", `feedback_no_jq_in_skills`.)
2. **`monitor-state.json` mutations are atomic.** Canonical Python embed: `tempfile.NamedTemporaryFile(prefix='.monitor-state.', dir=os.path.dirname(path))` → `json.dump` → `os.replace`. Inside server context: wrapped in `_state_lock(main_root)`. Inside CLI/script context: wrapped in `with_monitor_lock`. (See the cross-process flock contract paragraph in `skills/work-on-plans/SKILL.md`.)
3. **Single source of truth for skip-reason.** Any new `plans.skipped` reader must use IDENTICAL precedence in dashboard collector AND `/work-on-plans` selection filter. The Issue side already learned this (#862 / `_resolve_effective_skip_reason`); the Plan side must not split-brain.
4. **Mutual exclusion: live claim suppresses skip chip.** Plans and Issues both. An actively-claimed card never simultaneously renders a skip chip. (Mirrors the existing issues-side check that gates the issues skip-chip render on the absence of a live claim.)
5. **Selection-time vs. acquire-time discipline.** Mode-mismatch skip fires INSIDE `/work-on-plans` Step 4 (after the in-flight-claim filter, before `BATCH_MODE` is committed to dispatch). It must NOT fire at `/run-plan` Phase 0 acquire (cost-burning anti-pattern from plans-claim-chip-parity D4).
6. **XSS policy.** `textContent` / `appendChild` / `createTextNode` only. No `innerHTML` except for `// chrome-only` SVG icon injection (the existing lock-icon injection in `buildPlanCard` is the one legitimate use). The × button MUST be built via the `el()` helper.
7. **Polling cadence + fingerprinting.** 2s recursive `setTimeout`, NOT `setInterval`. The Plans-SKIP-chip render must be included in `fingerprintPlans` so × clicks trigger a re-render on the next poll.
8. **CSRF: `_origin_ok`.** Every new mutating endpoint gates on `_origin_ok` (the central helper in server.py). Modify the central helper, not per-call-site.
9. **Plans skip ≠ Issues skip — do not converge them.** Plans skip is ephemeral; auto-clears on claim/toggle/×. Issues skip is sticky; clears only via `/fix-issues reconsider`. The × buttons share visual CSS but invoke different endpoints.
10. **Skill versioning is non-negotiable.** Every phase touching `skills/<name>/` files MUST bump `metadata.version` in the same commit, mirror via `scripts/mirror-skill.sh`, and verify `diff -rq` is empty. Four enforcement points (`warn-config-drift.sh`, `/commit` step 2.5, `tests/test-skill-conformance.sh`, `hooks/block-stale-skill-version.sh`) will fail closed otherwise.
11. **Server-spawned in worktree tests: pass `--main-root "$(git rev-parse --show-toplevel)"`** so state files land under the worktree, not the main checkout.
12. **No `kill -9`, `killall`, `pkill`, `fuser -k`, `lsof -ti | xargs kill`.** Test cleanup uses SIGTERM via PID-file pairing or trap-on-EXIT script teardown.
13. **Test output to file, not piped.** Per CLAUDE.md test-output rule:
    ```bash
    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
    mkdir -p "$TEST_OUT"
    bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
    ```
14. **playwright-cli verification is mandatory for UI shipping.** Node-DOM stubs cannot render real CSS or fire real `matchMedia` (`feedback_playwright_mandatory_for_ui_ship`). The final phase includes a playwright-cli verification walk-through.
15. **Server-spawn test cleanup.** Tests that spawn the `zskills_monitor` server (`tests/test-monitor-state-queue-post-preservation.sh`, `tests/test-plan-skip-clear-paths.sh`, `tests/test-issue-reconsider-endpoint.sh`) MUST use trap-on-EXIT SIGTERM cleanup — NO `kill -9`, NO `pkill`, NO `fuser -k`, NO `lsof -ti | xargs kill` (CLAUDE.md "Dev Server" prohibition). Mirror the `start_server` / `stop_server` helper pattern already used in `tests/test_zskills_monitor_server.sh`.

### Design decisions baked in from research

- **`plans.skipped[<slug>]` schema:** `{"code": "mode-mismatch", "reason": "<batch_mode>≠<pinned_mode>", "sprint_id": "<sprint-id>", "at": "<iso8601>"}`. Symmetric with `issues.skipped` dict shape from #862. Multi-field so the activity feed and chip tooltip can both source from one record.
- **"Explicitly set" batch mode:** `MODE_OVERRIDE` (the CLI-passed token; non-empty iff user typed `phase` or `finish` on the `/work-on-plans` invocation). The default fall-through to `"finish"` is NOT "explicit" — a bare `/work-on-plans 3` has `MODE_OVERRIDE=""` and never causes a skip. Encoded as: skip-check arm runs only when `[ -n "$MODE_OVERRIDE" ]`.
- **Selection-filter rule (in prose):** Accept a plan if the sprint batch mode is unspecified (`MODE_OVERRIDE=""`), OR the plan's per-plan mode is unset (INHERIT pin), OR they match exactly. Otherwise drop the plan from the dispatch set AND write the skip marker + an activity step-marker. Formally: `accepts(plan, sprint) = (sprint.batch_mode is null) OR (plan.mode is INHERIT) OR (plan.mode === sprint.batch_mode)`.
- **Where skip-mismatch detection lives:** new sibling script `skills/work-on-plans/scripts/filter-mode-mismatch-plans.sh`, invoked after the existing in-flight-claim filter and before `BATCH_MODE` is committed to dispatch state. Reuses the existing single-responsibility seam pattern; does NOT extend the in-flight-claim filter (#1005 calls out single-responsibility).
- **Three Plans-skip clear paths (final commit shape):**
  - (a) `claim-plan.sh acquire` succeeds → locked delete of `plans.skipped[<slug>]` (graceful: failure to take the lock is logged-and-continue; the claim still succeeds).
  - (b) Pin-toggle via `togglePlanMode` → POST to the queue endpoint → server-side queue handler clears `plans.skipped[<slug>]` for any slug whose pin CHANGED in the incoming body.
  - (c) × click → POST to the dedicated `/api/plan-skip-dismiss` endpoint → narrow handler that only deletes `plans.skipped[<slug>]`. Does NOT alter the pin (user can leave the pin alone and wait for the matching batch).
- **Issues × click:** POST to a new `/api/issue-reconsider` endpoint with `{number: <N>}` → appends N to `monitor-state.json`'s `issues.reconsider` list (dedup, idempotent). Does NOT clear `issues.skipped[<N>]` immediately — the chip stays until the next `/fix-issues` fire re-triages, matching the post-#862 sticky semantics. (Decision resolved as: mirror the CLI exactly, do NOT clear early — preserves the post-#862 contract; chip-staying-visible is acceptable because Issues sprints fire on cron, and the visual change is one cron cycle away, not a UX dead end.)
- **`/api/work-state/reset` (clear-stale-sprint) RIP:** decided yes. The path is gated by the pill UI; without the pill it has no surface. If users ever hit a stuck stale-sprint state, recovery is `bash .claude/skills/update-zskills/scripts/clear-tracking.sh` or manual editing — this is a rare-failure-mode escape hatch and not worth a dedicated endpoint to maintain.
- **`top-level default_mode` field:** stays as tolerated-no-op (per #993). The server still tolerates writing/reading it; no chip surfaces it. This plan does NOT remove it (out of scope per #1005).
- **`work-on-plans-state.json` + `/api/work-state` GET:** STAY. They persist `batch_mode` for the per-plan chip resolution chain. Only the `trigger_configured` field on the served payload and the `/api/work-state/reset` POST go.

### Skill version bump procedure (per phase)

Run for EACH skill whose source files change in the phase. Embed verbatim in the implementer's prompt:

```bash
today=$(TZ=America/New_York date +%Y.%m.%d)
hash=$(bash scripts/skill-content-hash.sh skills/<name>)
bash scripts/frontmatter-set.sh skills/<name>/SKILL.md metadata.version "${today}+${hash}"
bash scripts/mirror-skill.sh <name>
diff -rq skills/<name>/ .claude/skills/<name>/   # must be empty
git add skills/<name>/ .claude/skills/<name>/
```

Skills that will be bumped at least once in this plan: `zskills-dashboard`, `work-on-plans`, `run-plan`, `update-zskills`. `fix-issues` ONLY if a SKILL.md or subcommand file is edited (likely not — the new endpoint lives in server.py inside `zskills-dashboard`).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Rip run-status pill + trigger plumbing + broaden queue POST preserve-by-default | ✅ Done | 9ecd939 | 18 files, +457/-1997; 7397/7397 tests pass; #1005 |
| 2 — Plans chip three-state + mode-conflict skip + SKIP chip × dismiss (three clear paths) | ✅ Done | f6f134e | 25 files, +2571/-67; 7464/7464 tests pass; 6/6 playwright checks; #1005 |
| 3 — Issues × dismiss + activity-feed SKIP pill + wrap-up | ⬚ | | |

---

## Phase 1 — Rip run-status pill + trigger plumbing + broaden queue POST preserve-by-default

### Goal

Delete the top-level run-status pill, its JS render path, its CSS, the `/api/trigger` and `/api/work-state/reset` server endpoints, the trigger-script config field + schema entry, and the `/update-zskills` backfill. Leave `/api/work-state` GET intact (with `trigger_configured` field dropped). In the same pass, refactor the dashboard server's queue POST handler to preserve-by-default — closing a pre-existing latent bug for `issues.skipped` / `issues.reconsider` (#813/#733) AND gating Phase 2 from regressing on the same shape.

### Work Items

- [ ] **Dashboard `index.html`** — delete the `<div id="run-status" class="run-status" aria-label="Run status">` element inside the Plans panel. Verify the surrounding `<section class="panel panel-plans">` still contains its `<h2>Plans</h2>` head and `#plans-body`.

- [ ] **Dashboard `app.js`** — delete every artifact of the trigger / work-status surface. The implementer reads the file at HEAD and removes:
  - The `TRIGGER_URL` constant.
  - The work-polling state vars (`workPollTimer`, `workPollAbort`).
  - The `lastFingerprint.workState` key. (Verified: the dict has 5 keys; deletion leaves 4. No sole-property concern.)
  - The functions `fetchWorkState`, `scheduleWorkPoll`, `pollWorkOnce`.
  - The function `applyWorkState` in its entirety (verified: its only callers are inside `pollWorkOnce` and its only effect is to call `renderRunStatus` — both also slated for deletion).
  - The function `renderRunStatus(ws)`.
  - The function `postTrigger(command)`.
  - The function `postWorkStateReset()`.
  - The three action-handler arms in the click delegator: `if (action === "run-top-n") { … postTrigger(cmd); }`, `if (action === "run-stop") return postTrigger("/work-on-plans stop");`, `if (action === "clear-stale-sprint") return postWorkStateReset();`. All three go.
  - Any `WORK_STATE_RESET_URL` constant.
  - Every session-bootstrap call to `pollWorkOnce()` / `scheduleWorkPoll()`. Verified four sites — two inside `postTrigger` / `postWorkStateReset` (die with their containing functions) and two standalone bootstraps (one in the init path, one in the theme-change re-bootstrap). Both standalone calls must be removed explicitly. After edit, `grep -n 'pollWorkOnce\|scheduleWorkPoll\|fetchWorkState' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` must return 0 hits.

- [ ] **Dashboard `app.css`** — surgical deletes. The implementer reads each rule at HEAD:
  - The full `.run-status` block including its `.run-status[hidden]` (#995 patch), `.run-status.run-status-stale`, `.run-status .run-label`, `.run-status .run-text` rules.
  - A shared selector list that bundles `.run-btn, .copy-btn, .run-stop-btn, .clear-stale-btn, .add-mini-btn { … }` (and its hover/focus counterpart) — SURGICALLY drop the three run-* selectors; KEEP `.copy-btn` and `.add-mini-btn`. Verify after edit via `grep -n 'copy-btn\|add-mini-btn' skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` — should still return hits.
  - The standalone `.copy-btn { margin-left: auto; }` rule — KEEP.
  - The `.run-btn.primary` rule — delete.
  - The `.run-n-input` rule — delete.

- [ ] **Dashboard `server.py`** — delete:
  - The `TRIGGER_TIMEOUT_SECS` constant.
  - The `validate_trigger_config(main_root, cfg)` function in its entirety.
  - The dispatch-table entries for `POST /api/trigger` and `POST /api/work-state/reset`.
  - Inside `_handle_state`: the `validate_trigger_config` append-to-`snapshot["errors"]` block.
  - The full `_handle_trigger_post()` function.
  - The full `_handle_work_state_reset()` function.
  - Inside `_handle_work_state_get()` — KEEP the function; DELETE the `trigger_configured` field injection AND the now-orphan `_read_config(main_root)` call that only feeds that field.
  - The `TRIGGER_CMD_RE` regex constant.
  - The top-of-file and inline prose comments that frame trigger-config — reframe to preserve the read-only-config invariant while dropping the trigger-specific framing (one-line edit each; do NOT touch unrelated comment prose).

- [ ] **Dashboard `server.py` — refactor the queue POST handler to preserve-by-default.** The behavior the handler must implement, in prose:
  1. Take the state lock for `main_root`.
  2. Read the existing `monitor-state.json` document via the handler's existing reader. The reader returns the FULL dict — verify at the call site that it does not filter top-level keys.
  3. Build the new output document by deep-copying the existing dict as the base. This preserves every key the handler does not own — `plans.skipped`, `issues.skipped`, `issues.reconsider`, and anything future schemas add — automatically.
  4. Overlay ONLY the writable column allow-lists from the payload: for each column in `PLAN_COLUMNS` (and the `completed` column if the payload includes it), set `new_doc["plans"][col]` to `payload["plans"].get(col, [])`. For each column in `ISSUE_COLUMNS`, set `new_doc["issues"][col]` to `payload["issues"].get(col, [])`.
  5. Overlay `default_mode` from the payload (or default to the existing value if the payload omits it). Set `version = "1.2"`. Set `updated_at` via the timestamp helper convention used elsewhere in server.py.
  6. Atomic-write the new document via the handler's existing atomic-write helper.

  Critical: the deep-copy base means `new_doc["plans"]["skipped"]`, `new_doc["issues"]["skipped"]`, `new_doc["issues"]["reconsider"]`, and any other nested key are carried in by reference. Phase 2 will add a selective `plans.skipped[slug]` pop for pin-change cases on top of this base; it does NOT need to rebuild the writer further.

- [ ] **Dashboard `app.js` — verify outbound queue-change payload behavior.** The existing `applyQueueChange` path sends the full client snapshot; verify it does NOT already deep-merge with the seeded `plans.skipped` from collect.py. If it does (and would re-send `plans.skipped[<slug>]` in the queue POST), the server-side preserve-by-default plus Phase 2's selective pop will compose correctly — but the implementer must confirm `applyQueueChange` does not OVERRIDE the server's preservation by sending a stale `skipped` snapshot. Recommend: `applyQueueChange` should NOT send `plans.skipped` in the queue POST body (the server owns that key); if it does today, strip it from the outbound payload.

- [ ] **Config schema** — delete the entire `dashboard` block in `config/zskills-config.schema.json` (since `work_on_plans_trigger` is the only property today; if any other property exists at edit time, keep the block and drop only the property).

- [ ] **`skills/update-zskills/SKILL.md`** — delete:
  - The Step 3.6 backfill prose for the trigger-script field.
  - The greenfield-write `"dashboard": { "work_on_plans_trigger": "" }` block in the JSON sample (and the trailing comma on the prior line — verify the sample remains valid JSON).

- [ ] **`skills/zskills-dashboard/SKILL.md`** — delete the Configuration section that documents the trigger-script feature (including its example trigger script block).

- [ ] **Tests — pruning (grep-based, not line-anchored):**
  - **DELETE entire file:** `tests/test-dashboard-run-status-locks.sh` (~280 lines, all run-status DOM behavior + trigger_configured gates). Also delete its registration from `tests/run-all.sh` if it's enumerated there.
  - **Prune `tests/test_zskills_monitor_dashboard_ui.sh`:** delete every assertion / fetch that targets the removed surface. **Acceptance criterion:** after the edit, this grep must return 0 hits:
    ```bash
    grep -cE '/api/trigger|/api/work-state/reset|trigger_configured|work_on_plans_trigger|#run-status|TRIGGER_URL|WORK_STATE_RESET_URL|postTrigger|run-btn|run-stop-btn|clear-stale-btn|run-n-input|renderRunStatus|fetchWorkState|pollWorkOnce|scheduleWorkPoll' tests/test_zskills_monitor_dashboard_ui.sh
    ```
    Initial count was 33; final must be 0. KEEP any test that targets `/api/work-state` GET (state-shape contract for the per-plan chip resolution chain) — the regex above does not match the bare `/api/work-state` substring; the implementer must visually distinguish keep-GET vs prune-reset cases.
  - **Prune `tests/test_zskills_monitor_server.sh`:** locate the work-state/reset phase block and the `/api/trigger` phase block (the implementer greps `/api/work-state/reset` to find the start; the trigger block follows immediately after). Prune both contiguous phase blocks. Also prune residual `work_on_plans_trigger` fixture writes throughout the file. **Acceptance criterion:** after the edit, this grep must return 0 hits:
    ```bash
    grep -cE '/api/trigger|/api/work-state/reset|trigger_configured|work_on_plans_trigger' tests/test_zskills_monitor_server.sh
    ```
    KEEP `/api/work-state` GET coverage (visible distinction — no `/reset` suffix).

- [ ] **NEW test: `tests/test-monitor-state-queue-post-preservation.sh`** — server integration. For each of `plans.skipped`, `issues.skipped`, `issues.reconsider`:
  - Spawn server with `--main-root $WORKTREE`.
  - Seed `monitor-state.json` with the key populated (e.g. `issues.reconsider = [42, 99]`).
  - POST `/api/queue` with a body that mutates only `plans.ready` and `issues.triage` (omits the preserved keys entirely).
  - Assert: response is 200; re-read `monitor-state.json`; the seeded key is still present with the same shape and values; `updated_at` changed.
  - Negative-case: also assert that the unrelated payload key `version` was bumped to `"1.2"` (writer-owned override) and `default_mode` was set from payload (or defaulted from existing).

- [ ] **Skill version bumps:** bump `metadata.version` for `zskills-dashboard` and `update-zskills` (both source files changed). Mirror each. Verify `diff -rq` empty.

### Design & Constraints

- The pill's empty-state bug (PR #997) is subsumed by removing the pill. No special-casing needed; the `.run-status[hidden]` rule dies WITH the pill, not before.
- `/api/work-state` GET stays because the `batch_mode` field of `work-on-plans-state.json` is still read by the per-plan chip resolution chain (Phase 2 → `entryMode + claim.dispatch_mode + batch_mode` precedence). Only the `trigger_configured` injection goes.
- Do NOT touch `default_mode` field in monitor-state.json or in server JSON read/write — it's tolerated-no-op per #993 and removing it is out of scope for #1005.
- The action-handler delete must be COMPLETE — leaving orphan `data-action="run-top-n"` strings anywhere will cause silent UX failures. After editing, run `grep -nE '"(run-top-n|run-stop|clear-stale-sprint)"' skills/zskills-dashboard/scripts/zskills_monitor/static/` — should return nothing.
- Any test that spawns the dashboard server inside the worktree MUST pass `--main-root "$(git rev-parse --show-toplevel)"` so state files don't leak to the main checkout.
- The `copy.deepcopy(existing)` cost in the queue-POST refactor is bounded — `monitor-state.json` is small (<100KB in practice). Not a hot-path concern.
- The queue-POST refactor is ADDITIVE for unknown keys: a future writer extending the schema (Phase 2's `plans.skipped`, Phase 3's `issues.reconsider` via the new endpoint) inherits the preservation contract automatically.
- The pin-change-driven `plans.skipped.pop(slug)` logic from Phase 2 is layered ON TOP of this base — Phase 2 modifies the SAME handler, but only adds a small diff arm after the deep-copy overlay; it does NOT reshape the writer further.
- This refactor closes a pre-existing latent bug for `issues.skipped` / `issues.reconsider`. The CHANGELOG entry in Phase 3 must mention it as a side-benefit.

### Invariants & Watch-outs

- The deletion is a tree-shake of one container plus everything that fed it. The implementer enumerates symbols by greping at HEAD, never from this plan's named list alone — names drift; the grep is the floor.
- KEEP `/api/work-state` GET — it serves the per-plan chip resolution chain. Only the `trigger_configured` field injected into its response goes.
- KEEP `default_mode` end-to-end in server and state — out of scope per #993.
- KEEP the `.copy-btn` and `.add-mini-btn` CSS rules — they're co-located in shared selector lists with run-* rules but serve other consumers; the surgical-drop verification grep is the floor on that mistake.
- Action-handler arms in click delegators die WITH their target functions — orphan `data-action` strings on buttons that no longer have handlers produce silent UX dead ends; the post-edit grep across the static dir is the floor.
- **The queue POST handler MUST preserve `plans.skipped`, `issues.skipped`, and `issues.reconsider` when reconstructing the document.** Without this preservation, every drag-drop on the dashboard wipes the skip-state and reconsider-list fields. This is the load-bearing invariant of the refactor. The deep-copy base is the mechanism; the implementer can use any equivalent technique that yields the same property, but the property is non-negotiable.
- **The client's outbound queue-change payload MUST NOT echo `plans.skipped` back to the server.** The server owns that key. If the client snapshot includes it and the server treats `payload["plans"]["skipped"]` as authoritative, Phase 2's three clear-paths compete with the client's stale snapshot and × clicks visually fail. Strip on the way out, or have the server explicitly ignore that key on the way in. Pick one; both is belt-and-suspenders.
- **The reader the handler uses MUST return the full top-level dict unfiltered.** If a future refactor narrows the reader to writer-owned keys, the preservation invariant collapses silently. Add a comment at the reader's call site inside the queue handler reminding maintainers that the handler depends on full-shape reads.

### Acceptance Criteria

- [ ] `grep -rn "renderRunStatus\|postTrigger\|postWorkStateReset\|TRIGGER_URL\|fetchWorkState\|scheduleWorkPoll\|pollWorkOnce\|work_on_plans_trigger\|trigger_configured\|TRIGGER_CMD_RE\|TRIGGER_TIMEOUT_SECS\|/api/trigger\|/api/work-state/reset" skills/zskills-dashboard/ skills/update-zskills/ config/` returns NO HITS.
- [ ] `grep -nE 'run-status|run-btn|run-stop-btn|clear-stale-btn|run-n-input|#run-status' skills/zskills-dashboard/scripts/zskills_monitor/static/{index.html,app.js,app.css}` returns NO HITS.
- [ ] `grep -nE 'copy-btn|add-mini-btn' skills/zskills-dashboard/scripts/zskills_monitor/static/app.css` STILL returns hits (regression check on the surgical CSS edit).
- [ ] `grep -n 'copy.deepcopy\|preserve' skills/zskills-dashboard/scripts/zskills_monitor/server.py` returns hits inside the queue POST handler.
- [ ] `bash tests/test-monitor-state-queue-post-preservation.sh > $TEST_OUT/test-queue-post-preservation.txt 2>&1` exits 0; all three preservation cases (plans.skipped, issues.skipped, issues.reconsider) pass.
- [ ] `bash tests/run-all.sh > $TEST_OUT/.test-results.txt 2>&1` — all suites pass; the deleted file does not appear in the run list.
- [ ] `python3 -c 'import json; json.load(open("config/zskills-config.schema.json"))'` — schema parses cleanly.
- [ ] Skill metadata.version bumps verified: `bash scripts/skill-content-hash.sh skills/zskills-dashboard` matches the value written to `skills/zskills-dashboard/SKILL.md`'s `metadata.version` post-`+`. Same for `skills/update-zskills`. (Hard-gated by `tests/test-skill-conformance.sh`.)

### Dependencies

None — this is the foundational rip + writer-refactor. Subsequent phases assume the pill is gone AND the queue POST handler preserves unknown keys by default.

---

## Phase 2 — Plans chip three-state + mode-conflict skip + SKIP chip × dismiss (three clear paths)

### Goal

Build the entire per-plan card mode surface in one coherent phase: the three-state mode chip with explicit INHERIT label (and FINISH-claim chip lock anchored on the claim's `dispatch_mode`), the selection-time mode-conflict skip filter in `/work-on-plans` (writes `plans.skipped[<slug>]` markers), and the SKIP chip rendering with × dismiss button wired through the three independent clear paths (claim-acquire, pin-toggle, × click).

### Work Items

#### 2A — Three-state mode chip with INHERIT label + FINISH-claim lock

- [ ] **Dashboard `app.js` — modify the chip-render path inside `buildPlanCard`.** Behavior the implementer codes to:

  - **The chip text source.** Today the chip text falls through to `"finish"` when `entryMode` is null and no claim is present. The new derivation:
    - `pinSource` is `"inherit"` when `entryMode === null`; `"explicit"` otherwise.
    - `displayMode` is `claim.dispatch_mode` if a claim is present; otherwise `entryMode` (which may be null).
    - `chipText` is the string `"inherit"` (lowercase) when `displayMode === null`; otherwise `displayMode` itself.
    - `effectiveMode` (used by the lock condition only) is `displayMode || "finish"`.

  The `claim.dispatch_mode` is the dispatch-lifetime captured mode (#874/#886); it supersedes the pin for the chip's "running" state. This is the same anchoring trap #930 hit — **the chip's running-state text and its lock condition MUST derive from `claim.dispatch_mode` (the claim is the dispatch-lifetime authority), NOT from `ws.batch_mode` (the wrapper-lifetime authority).** The current code already routes through `claim.dispatch_mode`; do not regress.

  - **The chip-text-binding update.** Replace the existing `text: effectiveMode` argument to `el()` with `text: chipText`.
  - **The `data-source` attribute.** Bind to `pinSource` (should already align — verify).
  - **The lock condition.** Stays as `const locked = isClaimed && effectiveMode === "finish";`. This is correct: an INHERIT-pinned plan that becomes claimed via FINISH dispatch shows `chipText="finish"` (sourced from `claim.dispatch_mode`) and `locked=true`.

- [ ] **Casing convention:** the locked-chip branch in `buildPlanCard` embeds the chip text (lowercase, e.g. `" finish"`) inside SVG-wrapped HTML. The plan's INHERIT label is also rendered LOWERCASE for consistency — chip text reads `"inherit"`, `"phase"`, `"finish"`. Aria-labels use the same lowercase form.
  - Use `chipText = displayMode === null ? "inherit" : displayMode` (lowercase throughout). Update tests Q1/RF2 accordingly to assert lowercase `"inherit"`.
  - Update the locked-branch HTML to embed `chipText` (the resolved string) instead of `effectiveMode`. After the change, the locked-branch HTML composes the SVG lock icon span plus a space plus `chipText`; the leading-space artifact (`" finish"`) persists because of the post-`</span>` whitespace; this is intentional for spacing the lock icon from the text. Tests for locked chips MUST use `.textContent.trim()` to absorb that whitespace.
  - The `data-state` attribute values (`queued`, `running-phase`, `running-finish`) are keyed on lowercase token comparisons — keep that aligned.

- [ ] **`aria-label` updates** — match the new label. All four chip states get consistent lowercase aria-labels:
  - Queued + inherit: `"Mode: inherit (inherits batch). Click to cycle inherit, phase, finish."`
  - Queued + explicit: `"Mode: <m> (pinned). Click to cycle inherit, phase, finish."`
  - Running-phase: `"Mode: <m> (running). Click to cycle inherit, phase, finish."`
  - Running-finish (locked): `"Mode: finish (locked while finish-mode /run-plan is in flight; releases on completion)."`

- [ ] **CSS — verify INHERIT visual is distinctive.** Locate the `.mode-chip[data-state="queued"][data-source="inherit"]` rule in `app.css`. Confirm it renders distinctly from `data-source="explicit"`. If the existing rule depends on the chip text being literal `"finish"` for sizing/centering, adjust so the chip renders cleanly with the literal `"inherit"` label (likely a `min-width` or `padding` tweak; verify visually via playwright in Phase 3).

- [ ] **`tests/test-mode-chip-three-state.sh` — REWRITE failing cases.** **Assertion idiom:** locked-chip text assertions MUST use `chip.textContent.trim()` to absorb the post-SVG whitespace; non-locked-chip assertions use exact `===` equality.
  - **Q1 (the existing `entryMode = null`, no claim case)**: today asserts chip text contains `"finish"`. Change to assert `chip.textContent === "inherit"` (exact). Assert `data-source="inherit"`. Assert `aria-label` contains `"inherit"` (lowercase).
  - **RF2 (the existing claimed + entry.mode=null + claim.dispatch_mode='finish' case)**: today asserts `running-finish` state with chip text fallthrough-to-finish. Claim ALWAYS writes `dispatch_mode`, so a claimed card resolves via `plan.claim.dispatch_mode`. Assert `chip.textContent.trim() === "finish"`, `data-state="running-finish"`, `locked=true`, `aria-disabled="true"`.
  - **NEW case**: claimed + entry.mode=null + claim.dispatch_mode='phase'. Assert `chip.textContent === "phase"`, `data-state="running-phase"`, NOT locked, click handler dispatches.
  - **NEW case**: unclaimed + entry.mode='phase'. Assert `chip.textContent === "phase"`, `data-source="explicit"`, NOT locked.
  - **NEW case**: FINISH-claim lock click — simulate click on a locked chip; assert NO POST is made. The click delegator already short-circuits on `aria-disabled="true"`; verify the test stubs the click delegator correctly so the no-POST assertion is meaningful.

#### 2B — Mode-conflict skip filter in /work-on-plans

- [ ] **NEW: `skills/work-on-plans/scripts/filter-mode-mismatch-plans.sh`** — new sibling to `filter-in-flight-plan-claims.sh`. Reads `READY_LINES` (TSV `slug<TAB>mode`) on stdin, plus four env-var inputs:
  - `MODE_OVERRIDE` — the explicit CLI batch-mode token (`"phase"` | `"finish"` | `""`).
  - `SPRINT_ID` — the sprint identifier (already exported by execute.md's Step 0 / SPRINT_ID computation block).
  - `PIPELINE_ID` — full pipeline ID `work-on-plans.$SPRINT_ID` (also exported by execute.md's Step 0; needed for the `.zskills/tracking/$PIPELINE_ID/` step-marker path).
  - `MAIN_ROOT` — repo root for state-file path.

  Output behavior:
  - If `MODE_OVERRIDE` is empty: passthrough — emit every input line unchanged.
  - Else: for each `slug<TAB>mode` line:
    - If `mode` is empty (INHERIT pin) OR `mode == MODE_OVERRIDE`: emit unchanged.
    - Else: do NOT emit — instead, take the monitor-state.json flock and write:
      - `plans.skipped[slug] = {"code": "mode-mismatch", "reason": "<MODE_OVERRIDE>≠<mode>", "sprint_id": "<SPRINT_ID>", "at": "<iso8601>"}`
    - Also write a step-marker for activity feed (see below).

  **Locking model.** `with_monitor_lock` is defined inline in `skills/work-on-plans/SKILL.md`'s cross-process flock contract paragraph; it is NOT exported by `zskills-resolve-config.sh` or `zskills-paths.sh`. Decision: the new filter script **reimplements `flock -x` on `$MAIN_ROOT/.zskills/monitor-state.json.lock` inline** (smaller scope than extracting `with_monitor_lock` into a sourceable helper, which is a separate refactor out of scope here). The lock IS load-bearing because `monitor-state.json` is written concurrently by the dashboard server's queue handler / plan-skip-dismiss handler / issue-reconsider handler and any concurrent `/work-on-plans` cron fire. Pattern:

  ```bash
  MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"
  MONITOR_LOCK="$MAIN_ROOT/.zskills/monitor-state.json.lock"
  mkdir -p "$(dirname "$MONITOR_LOCK")"
  # Take exclusive lock before the python embed runs. The lock auto-releases
  # when FD 9 closes (subshell exit).
  (
    flock -x 9
    python3 - "$MONITOR_STATE" "$SLUG" "$MODE_OVERRIDE" "$PIN" "$SPRINT_ID" <<'PY'
    # ... embed body below ...
    PY
  ) 9> "$MONITOR_LOCK"
  ```

  **Idempotency guard.** The Python embed checks for an existing skip record with the same `(code, reason)` tuple and short-circuits if present. Only `updated_at` and `sprint_id` are refreshed on re-fire; the embed returns a sentinel string on stdout that the bash caller reads to decide whether to write the step-marker (avoids per-fire marker accumulation in the activity feed).

  The Python embed for the state write follows the canonical atomic-write pattern (NamedTemporaryFile → write+rename via `os.replace`) and uses the timestamp helper convention native to the rest of the codebase. Behavior in prose:
  - Load the existing `monitor-state.json` (tolerating absent / malformed: treat as empty dict).
  - Resolve `plans.skipped` (creating intermediate dicts as needed).
  - Compute `now_iso` via the standard UTC ISO timestamp helper.
  - Determine `fresh` = (no existing record for this slug) OR (existing record has different `code` or `reason`).
  - Write the new record with shape `{"code": "mode-mismatch", "reason": f"{batch}≠{pin}", "sprint_id": sprint_id, "at": ...}`, where `at` is PRESERVED across re-fires if the record is not fresh (preserves original skip-time for UX), and is `now_iso` for fresh records.
  - Bump the document's `updated_at` to `now_iso` unconditionally (the file did get re-written; the bump drives dashboard re-poll fingerprint refresh).
  - Atomic-write via tempfile + `os.replace`.
  - Print `"FRESH"` or `"STALE"` on stdout for the bash caller to read.

  And the bash caller:
  ```bash
  IS_FRESH=$(flock -x 9; python3 - ... <<'PY' ... PY)  # captures stdout from embed
  if [ "$IS_FRESH" = "FRESH" ]; then
      # write step.work-on-plans.${SPRINT_ID}.${SLUG} marker (see below)
  fi
  ```

  Activity-feed marker write (same script, after the state write):

  ```bash
  PIPELINE_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
  mkdir -p "$PIPELINE_DIR"
  MARKER="$PIPELINE_DIR/step.work-on-plans.${SPRINT_ID}.${SLUG}"
  ISO=$(${TZ:+TZ="$TZ"} date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$MARKER" <<MARKER_EOF
  skill: work-on-plans
  parent: work-on-plans.${SPRINT_ID}
  slug: ${SLUG}
  mode: ${MODE_OVERRIDE}
  pin: ${PIN}
  status: skip
  output: mode_mismatch: ${MODE_OVERRIDE}≠${PIN}
  date: ${ISO}
  MARKER_EOF
  ```

- [ ] **`skills/work-on-plans/modes/execute.md`** — wire the new filter into the dispatch pipeline. `MODE_OVERRIDE` is set by Step 0 argument parsing, well BEFORE the existing in-flight-claim filter pipe. The filter only needs `MODE_OVERRIDE`, NOT the merged `BATCH_MODE`. Do NOT move the `BATCH_MODE="${MODE_OVERRIDE:-${DEFAULT_MODE:-finish}}"` resolution — that line still owns dispatch-default semantics. The skip-check arm reads `MODE_OVERRIDE` directly.
  - Locate the existing in-flight-claim filter pipe (where `filter-in-flight-plan-claims.sh` runs against `READY_LINES`).
  - Add a SECOND filter pipe AFTER the in-flight-claim filter, passing the necessary env vars:
    ```bash
    READY_LINES=$(
      MODE_OVERRIDE="$MODE_OVERRIDE" \
      SPRINT_ID="$SPRINT_ID" \
      PIPELINE_ID="$PIPELINE_ID" \
      MAIN_ROOT="$MAIN_ROOT" \
      printf '%s\n' "$READY_LINES" | \
        bash "$ZSKILLS_SKILLS_ROOT/work-on-plans/scripts/filter-mode-mismatch-plans.sh"
    )
    ```
    Note on ordering: `SPRINT_ID` and `PIPELINE_ID` are computed by the SPRINT_ID block, which runs BEFORE the existing filter pipe. The implementer reads execute.md at HEAD to verify ordering and reorder if needed.
  - Re-read `TOTAL_READY` after the filter — it must reflect the post-skip count so `DISPATCH_COUNT` doesn't undercount because of plans that got skipped before dispatch.
  - **Status-line insertion:** immediately after the re-read of `TOTAL_READY` and before the empty-queue exit, add:
    ```bash
    if [ "$MM_SKIP_COUNT" -gt 0 ] 2>/dev/null; then
      echo "Mode-mismatch skipped: $MM_SKIP_COUNT plan(s)"
    fi
    ```
    The filter script outputs `MM_SKIP_COUNT` via a stderr counter line or a separate marker file — pick one and document it in the filter script's prologue.

- [ ] **`skills/work-on-plans/SKILL.md`** — add a brief paragraph in the "Cross-process flock contract" or a new "Mode-mismatch skip" subsection documenting:
  - Trigger: `MODE_OVERRIDE` set AND per-entry pin set AND they differ.
  - Effect: plan is dropped from this sprint's dispatch; `monitor-state.json:plans.skipped[<slug>]` recorded; activity marker emitted.
  - Clear paths: claim acquire (system), pin-toggle (user), × dismiss on dashboard (user).
  - Asymmetry with Issues skip: ephemeral, not sticky.

- [ ] **`tests/test-work-on-plans-dispatch-seam.sh`** — add cases:
  - **NEW: `mode_mismatch_pin_phase_batch_finish_skips`**: seed `plans.ready = [{slug:"p1", mode:"phase"}, {slug:"p2"}]`, invoke with `MODE_OVERRIDE=finish`. Assert: p1 SKIPPED (no `step.*.started` marker, presence of `step.*` marker with `status: skip`), `monitor-state.json:plans.skipped["p1"]` shape matches `{code, reason, sprint_id, at}`, p2 dispatched normally (INHERIT-pin matches any batch).
  - **NEW: `mode_mismatch_pin_finish_batch_phase_skips`**: mirror with reversed pin/batch.
  - **NEW: `mode_match_pin_phase_batch_phase_dispatches`**: matching pin + batch → both dispatched, no skip marker.
  - **NEW: `bare_invocation_no_skip`**: `MODE_OVERRIDE=""`; seed `[{slug:"p1", mode:"phase"}, {slug:"p2", mode:"finish"}]`. Both dispatched (no batch override). No `plans.skipped` writes.
  - **NEW: `inherit_pin_never_skipped`**: `MODE_OVERRIDE=finish`; seed `[{slug:"p1"}]`. Dispatched. No skip.

  **Test invocation pattern:** `filter-mode-mismatch-plans.sh` is a standalone shell script, NOT a markdown-embedded fence. Invoke it directly as `bash skills/work-on-plans/scripts/filter-mode-mismatch-plans.sh` with env vars set in the test harness. Do NOT use `tests/lib/extract-fence.sh` (that helper is for markdown-embedded fences). Mirror the pattern in `tests/test-fix-issues-skip-persistence.sh` which runs `bash skills/fix-issues/scripts/record-skip.sh ...` directly. Assert state-file mutation via `python3 -c 'import json,sys; print(json.load(open(sys.argv[1])))["plans"]["skipped"]' "$MONITOR_STATE"`.

  **NEW idempotency test: `mode_mismatch_twice_produces_one_step_marker`** — run the filter TWICE with same `READY_LINES` (same slug + same pin) and same `MODE_OVERRIDE`, but with different `SPRINT_ID` values. Assert:
  - Only ONE step marker exists per unique `(slug, code, reason)` tuple (the second fire detects the existing record via the FRESH/STALE sentinel and skips the step-marker write).
  - The `plans.skipped[slug].at` value is preserved across the two fires (NOT bumped to the second fire's timestamp).
  - The `plans.skipped[slug].sprint_id` value is REFRESHED to the second fire's `SPRINT_ID` (so the dashboard knows the most-recent sprint that triggered the skip).
  - `monitor-state.json:updated_at` IS bumped (the file did get re-written; the bump drives dashboard re-poll fingerprint refresh).

#### 2C — Plans SKIP chip with × dismiss + three clear paths

- [ ] **Dashboard `collect.py` — surface `plans.skipped` through the state reader.** The existing state-reader loop walks `plans_raw.items()` and skips every entry whose value is not a list. `plans.skipped` is a DICT (slug→record), so it is silently filtered out by the current code. The fix:
  - After the existing per-column list-iteration loop, explicitly resolve `plans_skipped`. The implementer reads the codebase to confirm the shape filter and adds an extraction that tolerates the dict shape (defaulting to `{}` when absent or when the value is not a dict).
  - Thread `plans_skipped` through the function's return shape so it lives under the `plans` sub-dict alongside the per-column lists. Verify downstream consumers (the `_annotate_plans_queue` path) iterate `plans_out` columns via known column NAMES, not `.items()` — so the new `"skipped"` key in the `plans` dict does NOT pollute the column iteration. Audit at edit time.
  - In `_annotate_plans_queue`, for each ready/backlog plan dict, attach `plan["skip_reason"] = monitor_plans_skipped.get(slug)` (None if absent). Mirror the issue-side pattern in `_resolve_effective_skip_reason`, keeping the data shape uniform. The `monitor_plans_skipped` source comes from the state-reader's return value's `plans.skipped` key (now properly surfaced after the fix above).

- [ ] **Dashboard `app.js` — extend `buildPlanCard` to render the SKIP chip.**
  - Insert the SKIP-chip render between the claim-chip block and the mode-chip block. **DOM layout:** the chip span is structured as a wrapper containing TWO child spans — a label span and the × button (avoids the `textContent` + `appendChild` flat-sibling trap):
    ```js
    // Mutual exclusion (mirror #862/#898): live claim suppresses the skip chip.
    const hasLiveClaim = !!(plan && plan.claim);
    const skipReason = (!hasLiveClaim && plan && plan.skip_reason) ? plan.skip_reason : null;
    if (skipReason && col === "ready") {
      const row = el("div", { cls: "card-sub" });
      const chip = el("span", {
        cls: "skip-chip skip-chip--" + String(skipReason.code || ""),
        attrs: { title: String(skipReason.reason || "") },
      });
      // Harmonize body shape with issues chip: "skip: <code> — <label>"
      // where label = reason for plans (auto-generated "finish≠phase").
      const label = el("span", {
        cls: "skip-chip-label",
        text: "skip: " + String(skipReason.code || "") +
              (skipReason.reason ? " — " + String(skipReason.reason) : ""),
      });
      const dismiss = el("button", {
        cls: "skip-dismiss-btn",
        attrs: {
          type: "button",
          "data-action": "plan-skip-dismiss",
          "data-slug": slug,
          "aria-label": "Dismiss skip for " + slug,
          title: "Dismiss",
        },
        html: SVG_ICONS.x,  // use existing SVG icon, not literal × character
      });
      chip.appendChild(label);
      chip.appendChild(dismiss);
      row.appendChild(chip);
      card.appendChild(row);
    }
    ```
  - **Click-delegator arm:** the click delegator (`handleAction(action, target)`) receives `target` as a direct argument (NOT `ev.target`). The arm goes inside `handleAction`, NOT in a separate `ev`-scoped handler. The `data-slug` attribute lives on the BUTTON; the click may bubble from a child SVG path, so use `target.closest('[data-action="plan-skip-dismiss"]')` to walk up to the button:
    ```js
    if (action === "plan-skip-dismiss") {
      const btn = target.closest('[data-action="plan-skip-dismiss"]') || target;
      const s = btn.getAttribute("data-slug");
      if (s) return postPlanSkipDismiss(s);
    }
    ```
  - Add the new fetch helper. **Use `showToast(message, kind, opts)`:**
    ```js
    async function postPlanSkipDismiss(slug) {
      try {
        const resp = await fetch("/api/plan-skip-dismiss", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ slug }),
        });
        if (!resp.ok) {
          showToast("Dismiss failed: " + resp.status, "err");
          return;
        }
        // On 2xx, the next poll will see plans.skipped[slug] gone and re-render.
      } catch (err) {
        showToast("Dismiss error: " + (err && err.message ? err.message : err), "err");
      }
    }
    ```
  - **Extend `fingerprintPlans`:** add `p.skip_reason ? [p.skip_reason.code, p.skip_reason.reason] : null` to the row tuple inside `fingerprintPlans`. Without this, × clicks won't trigger a re-render on the next poll cycle. Test at the unit level: flip `skip_reason` between snapshots, assert fingerprint changes.

- [ ] **Dashboard `app.css` — add styles.** Wrapper-span layout:
  ```css
  /* Plans skip chip — ephemeral, has × dismiss. Reuse skip-chip base class
     plus a code-specific variant for mode-mismatch and a × button rule. */
  .skip-chip--mode-mismatch {
    background: rgba(247, 120, 186, 0.14);
    border-color: var(--pink);
    color: var(--pink);
  }
  /* Inline-flex layout: label + dismiss button side-by-side, vertically centered. */
  .skip-chip {
    display: inline-flex;
    align-items: center;
    gap: 0;
  }
  .skip-chip-label { display: inline-block; }
  .skip-dismiss-btn {
    background: transparent;
    border: 0;
    color: inherit;
    cursor: pointer;
    padding: 0 0 0 6px;
    margin: 0;
    line-height: 1;
    display: inline-flex;
    align-items: center;
  }
  .skip-dismiss-btn svg { width: 12px; height: 12px; }  /* SVG_ICONS.x sizing */
  .skip-dismiss-btn:hover,
  .skip-dismiss-btn:focus { opacity: 0.7; outline: none; }
  ```

- [ ] **Dashboard `server.py` — add the `/api/plan-skip-dismiss` handler.** Mirror the shape of the existing queue POST handler. Behavior in prose:
  - Gate on `_origin_ok()` (CSRF).
  - Read the request body via the server's existing request-body reader (the implementer matches its ACTUAL return signature when consuming it — it is NOT a bare string; verify at edit time).
  - Parse JSON; require a non-empty string `slug`; return 400 on missing/invalid.
  - Take the state lock; read the state via the server's standard state reader.
  - Resolve `plans.skipped`. **Idempotent: if the slug is absent, NO WRITE occurs; the 200 response returns the existing `updated_at` unchanged. Asymmetric with `/api/issue-reconsider` (Phase 3) which always writes (dedup-append).**
  - If the slug is present: delete it; bump `updated_at` via the timestamp helper convention used elsewhere in server.py; atomic-write via the standard helper.
  - Respond 200 with `{ok: true, slug, updated_at}`.

  Add the dispatch-table entry: `POST /api/plan-skip-dismiss → _handle_plan_skip_dismiss_post`.

- [ ] **Dashboard `server.py` — extend the queue POST handler (built in Phase 1) to clear `plans.skipped[<slug>]` for any slug whose pin CHANGED in the incoming body.** **This layer is additive ON TOP of Phase 1's preserve-by-default refactor** — the deep-copy base has already preserved `plans.skipped` as-is; this arm selectively pops slugs whose pin changed. The pin diff must flatten across ALL columns where a pin can live (`drafted`, `reviewed`, `ready`, `backlog`, `discarded`, AND `completed` — see Invariants below), not just `ready`. A slug can change columns at the same time as the pin changes, and a slug can move between columns without changing the pin (drag-reorder).
  - Build `prev_modes = {slug: mode}` by flattening `existing["plans"][col]` for every plan column that may carry pins.
  - Build `new_modes = {slug: mode}` by flattening `payload["plans"][col]` for every plan column that may carry pins.
  - For each slug present in BOTH (`prev_modes` AND `new_modes`): if `new_modes[slug] != prev_modes[slug]` → `new_doc["plans"]["skipped"].pop(slug, None)`. The "pin changed" comparison covers:
    - `None → "phase"` (added a pin)
    - `"phase" → None` (removed a pin)
    - `"phase" → "finish"` (changed a pin)
    - NOT `"phase" → "phase"` (no change; just reorder/move) — skip mark survives.
  - Slugs that DISAPPEARED from all columns (deleted entirely) — also pop their skip marker (the slug no longer has a queue identity).
  - Slugs newly APPEARED (no prev_mode entry) — leave the skip dict alone (they're new; no prior skip to preserve OR clear).
  - **Regression test:** drag a plan with skip-mark from `ready→backlog` without toggling the pin → skip-mark SURVIVES. Drag and toggle in one POST → skip-mark CLEARS. Add a sibling slug toggle in the same POST → only the toggled slug's mark clears; unrelated slugs' marks survive.

- [ ] **`skills/run-plan/scripts/claim-plan.sh` — extend `cmd_acquire` with a best-effort skip-clear.** The acquire's atomic-write of the claim file lives INSIDE a Python heredoc. The bash hook point is in the bash that resumes after the heredoc terminator, between the `then` that opens the success branch and the `return 0` that closes the function. Concretely (the implementer reads the current source at HEAD before editing):
  - **Hook location:** between the `fi` that closes the `if ! "$_CLAIM_PYTHON" - ...` block and the function's `return 0`. The python embed has already succeeded (the atomic-write inside the embed made the claim durable); we now layer the best-effort skip-clear call on top.
  - **Call shape:**
    ```bash
    # python embed already ran successfully here (claim file is durable).
    # Best-effort: clear plans.skipped[<slug>] if a server wrote one earlier.
    clear_plan_skip_if_present "$SLUG" "$MAIN_ROOT"
    return 0
    ```
  - The helper `clear_plan_skip_if_present`:
    - Resolves `MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"` and `MONITOR_LOCK="$MAIN_ROOT/.zskills/monitor-state.json.lock"`.
    - Returns 0 immediately if `MONITOR_STATE` doesn't exist (acquire-side pre-bootstrap tolerance).
    - Acquires the flock (`flock -x` on FD 9 opened against `MONITOR_LOCK`) and runs an inline Python embed that:
      - Reads the state file.
      - `data.get("plans", {}).get("skipped", {}).pop(SLUG, None)`.
      - Writes back via tempfile + os.replace, only if a change occurred (to avoid spurious `updated_at` churn).
    - **Graceful degradation:** on ANY failure (lock contention, malformed JSON, write error), LOG to stderr and return 0. The claim already succeeded; we don't fail the acquire for a clear-skip best-effort. The contention window is microseconds (flock+write is sub-ms); graceful-degrade is acceptable but the visual asymmetry is documented in the test (see acceptance criterion below).
  - The helper is implemented as a bash function in `claim-plan.sh` (or a sourced fragment from `claim-self-reentry.sh`'s neighborhood). Do NOT shell out to a separate script — the acquire is hot-path.
  - **Self-reentry path:** the self-reentry success path returns 0 WITHOUT reaching the new hook point. This is intentional: the original (fresh) acquire already cleared the skip mark; the self-reentry inherits that state. Document this in the helper's prologue comment. If defense-in-depth becomes desired in a future iteration, calling the (idempotent) helper on the reentry path too is harmless.

- [ ] **NEW test: `tests/test-plans-skip-chip.sh`** — Node-DOM stub mirroring `tests/test-mode-chip-three-state.sh`:
  - Case: plan with `skip_reason = {code: "mode-mismatch", reason: "finish≠phase"}`, no claim → SKIP chip rendered with text `"skip: finish≠phase"` and × button present.
  - Case: same skip_reason BUT plan has a live claim → SKIP chip NOT rendered (mutual exclusion).
  - Case: × click → fetch to `/api/plan-skip-dismiss` with `{slug}` body (mock fetch; assert the call).

- [ ] **NEW test: `tests/test-plan-skip-clear-paths.sh`** — integration:
  - **Path a (claim-acquire):** seed `monitor-state.json:plans.skipped = {"p1": {...}}` + spawn server with `--main-root $WORKTREE`; invoke `claim-plan.sh acquire --slug p1 --pipeline-id test_pl`; assert state file now has `plans.skipped = {}` (or no `p1` key).
  - **Path b (pin-toggle):** seed `plans.skipped = {"p1": {...}}` and `plans.ready = [{slug:"p1"}]`; POST `/api/queue` with body that has `plans.ready = [{slug:"p1", mode:"finish"}]`; assert `plans.skipped` no longer has `p1`.
  - **Path b' (column-cross drag without pin change):** seed `plans.skipped = {"p1": {...}}` and `plans.ready = [{slug:"p1", mode:"phase"}]`; POST `/api/queue` with body that has `plans.backlog = [{slug:"p1", mode:"phase"}]` (moved column, no pin change); assert `plans.skipped["p1"]` SURVIVES (pin didn't change).
  - **Path b'' (drag a different slug, sibling preservation):** seed `plans.skipped = {"p1": {...}, "p2": {...}}` and `plans.ready = [{slug:"p1"}, {slug:"p2"}]`; POST a queue change toggling pin on `p1` only; assert `plans.skipped["p1"]` cleared, `plans.skipped["p2"]` SURVIVES.
  - **Path c (× dismiss):** seed `plans.skipped = {"p1": {...}}`; POST `/api/plan-skip-dismiss` with `{slug:"p1"}`; assert state file `plans.skipped` no longer has `p1`. Also assert `updated_at` bumped.
  - **Idempotency:** record `existing.updated_at` BEFORE; call dismiss when `plans.skipped[p1]` does NOT exist; assert 200 response, AND assert `existing.updated_at` AFTER === `existing.updated_at` BEFORE (no spurious write).
  - **Race:** spawn a thread that holds the state lock for ~50ms; invoke claim-plan.sh acquire with `--slug p1` against a state with `plans.skipped["p1"]` set; assert: (1) the acquire returns 0 (claim succeeded), (2) `plans.skipped["p1"]` MAY OR MAY NOT be cleared (race outcome), (3) a subsequent poll's snapshot still hides the skip chip because the claim is now in `_annotate_plans_queue`'s mutual-exclusion path. Document the test as "race outcome is non-deterministic but UX-correct."
  - **Bad payload:** missing slug → 400. Malformed JSON → 400.

- [ ] **Skill version bumps** for `zskills-dashboard`, `work-on-plans`, and `run-plan`. Mirror each. Verify `diff -rq` empty for all three.

### Design & Constraints

- The cycle `INHERIT → PHASE → FINISH → INHERIT` does NOT change — `togglePlanMode` is already correct. Only the render label changes.
- During PHASE claims the chip stays editable; clicking it changes the saved pin which the NEXT inter-phase dispatch re-reads. This matches `/run-plan` PHASE semantics (claim released between phases).
- FINISH-claim lock condition is `isClaimed && effectiveMode === "finish"` and MUST source from `claim.dispatch_mode` (dispatch-lifetime), NOT from `ws.batch_mode` (wrapper-lifetime). The current code already does this; the lesson from #930 is "do not regress to wrapper-lifetime."
- Click-handler short-circuit: the click delegator checks `aria-disabled` before routing `toggle-mode` (existing pattern). Confirm this still gates correctly with the chip's new `aria-disabled="true"` attribute when `locked === true`.
- DO NOT introduce a new "INHERIT chip on claimed card" path — claim always pins a concrete `dispatch_mode`, so a claimed card never renders INHERIT.
- The skip-check arm runs only when `[ -n "$MODE_OVERRIDE" ]` — never when the user typed a bare `/work-on-plans` (the default `BATCH_MODE="finish"` is NOT "explicit").
- The Python embed in `filter-mode-mismatch-plans.sh` uses `setdefault` defensively for `plans.skipped` (the key may not yet exist; `monitor-state.json` may not yet exist).
- The `<!-- allow-hardcoded -->` annotation discipline: any new fence in `execute.md` referencing `monitor-state.json` directly should source the canonical config prelude — see existing fences in the file for the pattern. Standalone `.sh` scripts under `scripts/` are NOT covered by the skill-file hardcode deny-list (CLI scripts can hardcode safely).
- DO NOT extend the in-flight-claim filter — single-responsibility (one filter does one thing). Plans-claim-chip-parity D4 anchored this design.
- DO NOT fire the skip-check at `/run-plan` Phase 0 acquire — selection-time discipline.
- **Scope of the mode-pin constraint:** the hard constraint applies AT THE `/work-on-plans` SELECTION BOUNDARY ONLY. A directly typed `/run-plan <slug>` (without going through `/work-on-plans`) bypasses the pin — this is intentional, not a gap:
  - A user typing `/run-plan <slug> finish` against a `phase`-pinned plan is making an explicit one-shot override (the typed CLI arg IS the user's most recent intent).
  - `/run-plan` and `/work-on-plans` are different surfaces — the latter is a batch dispatcher operating on a saved queue; the former is a direct invocation.
  - This decision is referenced in the Overview as: "make per-plan mode pins a hard constraint AT THE `/work-on-plans` BOUNDARY" — the qualifier matters.
  - Extending the constraint to `/run-plan acquire` would require a new error path in `claim-plan.sh:cmd_acquire` and a new rc code; that's a separate plan if anyone wants it, not part of this scope.
- Failure mode: if the state-write fails (disk full, permission), exit non-zero and let `/work-on-plans` surface the error. Do NOT silently swallow — `feedback_or_true_pattern` applies.
- The dedicated `/api/plan-skip-dismiss` endpoint exists separately from `/api/queue` because `/api/queue` is a full-shape write (the client sends all queues; server replaces). A minimal dismiss doesn't have all queues to send. Narrow endpoints are easier to test and more honest about intent.
- The pin-toggle clear path (in the queue POST handler) clears skip when the pin CHANGED — NOT every time a queue write happens. The diff check prevents unnecessary state-bump churn during reorder operations.
- The × button MUST be built via `el()` not raw `innerHTML`. The `html: SVG_ICONS.x` carveout for SVG-icon injection is the existing chrome-only exception (per the XSS-policy invariant). Use `SVG_ICONS.x` (the existing SVG-icon helper used elsewhere in the codebase for consistent visual idiom) — do NOT use a literal × character.
- Mutual exclusion: `hasLiveClaim` check mirrors the existing issues-side pattern. A claim IS always a stronger signal than a stale skip — if both are present, the claim won.
- `claim-plan.sh` graceful-degradation rationale: the acquire is the hot path; a transient lock-contention with a server write must NOT block claim-acquire. The skip-clear catches up on the next poll (the chip will momentarily disappear visually because the claim now suppresses it via mutual exclusion).
- **Three-clear-paths race-mode:** the three independent clear paths (acquire-side best-effort, queue POST pin-change, dismiss endpoint) converge on the same `plans.skipped[slug]`. The acceptance test explicitly covers the worst case: the acquire-side clear-skip races with a server write and fails-gracefully → the SKIP chip is masked by the active claim (mutual exclusion); a subsequent claim release re-surfaces the skip mark only if the underlying mark was never cleared. Document this as expected behavior, not a bug — the visual asymmetry is bounded by the next poll cycle.
- Fingerprint extension: without including `plan.skip_reason` in `fingerprintPlans`, the dashboard's diff-suppression will not re-render after a × dismiss, and the chip will appear stuck.

### Invariants & Watch-outs

- **The FINISH-claim chip lock MUST be anchored on the active claim's captured `dispatch_mode`, never on the wrapper's `batch_mode`.** The claim is the dispatch-lifetime authority; the wrapper is the call-lifetime authority. This is the same anchoring trap #930 hit. If a future refactor regresses to `ws.batch_mode`, a wrapper that finishes its sprint while a claim is still in flight will silently unlock the chip mid-dispatch.
- **The acceptance rule for mode-conflict skipping is:** `accepts(plan, sprint) = (sprint.batch_mode is null) OR (plan.mode is INHERIT) OR (plan.mode === sprint.batch_mode)`. Any reformulation must compute the same truth table.
- **Chip text and aria-label use ONE consistent casing (lowercase) across all four states.** A mix produces a visible / aria asymmetry users can detect (`"INHERIT"` chip vs `" finish"` locked branch).
- **Locked-chip textContent carries a leading space from the SVG injection.** Tests asserting locked-chip text MUST use `.textContent.trim()`. Non-locked chips have no SVG branch; exact `===` is fine. This asymmetry is INTENTIONAL (it spaces the lock icon from the text); don't try to remove it.
- **A claimed card never renders INHERIT.** Claim acquire always writes a concrete `dispatch_mode`. If you find yourself adding a "claimed + inherit" branch, you're solving a problem that doesn't exist.
- **Click-delegator's `aria-disabled` short-circuit is the load-bearing UX lock**, not the visual style alone. Tests must verify the no-POST behavior on the locked chip, not just the visual lock icon.
- **The skip-check fires ONLY when `MODE_OVERRIDE` is non-empty.** A bare `/work-on-plans 3` (no explicit mode) must NOT skip any plan, regardless of pin. The default-to-`finish` fall-through is NOT "explicit." This is the user-pinning contract: the user only loses dispatch if THEY typed two conflicting intents.
- **The mode-mismatch constraint applies at the `/work-on-plans` boundary only.** A directly typed `/run-plan <slug> finish` against a `phase`-pinned plan is an explicit one-shot CLI override and bypasses the pin. If you find yourself adding an error path to `claim-plan.sh:cmd_acquire`, you're scope-creeping — that's a separate plan.
- **Idempotency: re-firing the filter against the same `(slug, code, reason)` MUST NOT produce a second step marker.** The FRESH/STALE sentinel from the Python embed is the gate; the bash caller writes the marker only on FRESH. Without this, every cron fire pollutes the activity feed.
- **The skipped record's `at` field is PRESERVED across re-fires; `sprint_id` is REFRESHED.** The `at` carries the original observation time (UX wants the long-tail "skipped for 3 days now" reading). The `sprint_id` tracks the most-recent triggering sprint (dashboard wants the most-recent one).
- **The new filter MUST run AFTER the in-flight-claim filter, never before.** Selection-time discipline: an in-flight claim wins over a queued mode-mismatch. Reordering breaks the invariant that `plans.skipped` never contains an actively-claimed slug.
- **The script reimplements `flock -x` inline** rather than waiting for a `with_monitor_lock` helper extraction. If a future refactor extracts the helper, this script becomes a candidate caller; until then, the inline lock is correct.
- **The single-responsibility seam:** do NOT extend the in-flight-claim filter to also do mode-mismatch detection. One filter, one responsibility.
- **The plan-column iteration set the queue-POST pin-diff walks MUST include EVERY column where a pin can live, including `completed`.** A naive iteration over a constant like `("drafted","reviewed","ready","backlog","discarded")` that omits `completed` silently wipes skip markers on drag-to-completed. The implementer reads the current column allow-list at edit time and ensures the pin-diff walks the SAME set. Verify in the regression test: drag-to-completed with a stale skip mark must clear the mark via the pin-diff path if and only if the pin changed.
- **The state-reader's shape filter MUST tolerate `plans.skipped` as a DICT, not silently drop it.** The existing filter inspects per-column values and discards non-lists. `plans.skipped` is a dict (slug→record). The fix is explicit: extract `plans.skipped` separately, BEFORE or AFTER the per-column loop, and thread it through the return. Verify in a dedicated unit test that a state file with `plans.skipped` populated produces a snapshot whose plans dict carries the same key with the same shape.
- **Mutual exclusion is load-bearing for UX correctness.** A claimed card NEVER renders a skip chip — the claim won, the skip is stale. The `hasLiveClaim` check inside the SKIP-chip render is the gate. Tests must explicitly assert: claim present + skip_reason present → NO chip rendered.
- **Three clear paths converge on the same `plans.skipped[slug]` key.** They are independent and can race. The three clear paths all use the same atomic-write protocol; claim-acquire's clear is idempotent (no-op when marker doesn't exist); claim-acquire's clear failure must NOT abort the acquire (graceful degradation). Race-mode behavior is documented as: acquire-side fails-gracefully on contention; the chip is masked by mutual exclusion immediately anyway; a subsequent release re-surfaces the chip only if the underlying mark was never cleared by another path.
- **Idempotent dismiss: when the slug is absent, NO WRITE occurs.** The 200 response carries the existing `updated_at` unchanged. Asymmetric with `/api/issue-reconsider` (Phase 3) which always writes (dedup-append) — that asymmetry mirrors the deeper Plans-vs-Issues asymmetry and is intentional.
- **The × button is constructed via `el()` with `html: SVG_ICONS.x`** — the SVG-icon injection is the one legitimate XSS carveout for chrome. The literal × character is not used: it produces idiom inconsistency with the rest of the codebase. Tests should grep `app.js` for the literal character inside the dismiss-button render path to catch regressions.
- **`fingerprintPlans` MUST include `skip_reason`.** Without it, × clicks update the state but the poll diff-suppression hides the change for one cycle, producing a visibly stuck chip.
- **The acquire-side helper runs ONLY on fresh-acquire success.** Self-reentry returns 0 from an earlier code path that does not reach the helper. This is correct: the original fresh acquire already cleared. A future implementer reading this code might be tempted to "fix" the asymmetry by calling the helper on self-reentry too — that's harmless (the helper is idempotent), but not required.
- **Plans skip is EPHEMERAL — auto-clears on claim/toggle/dismiss.** Don't accidentally adopt /fix-issues:skipped's sticky precedence model. Plans skip and Issues skip have deliberately asymmetric semantics; do not converge them.

### Acceptance Criteria

- [ ] `grep -n '"inherit"' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` returns hits at the chip-text derivation site.
- [ ] `bash tests/test-mode-chip-three-state.sh > $TEST_OUT/test-mode-chip.txt 2>&1` exits 0; all listed cases pass; the new inherit/lock cases are present and pass.
- [ ] Manual node-DOM stub: unclaimed plan with no pin renders chip text `"inherit"`, `data-source="inherit"`. Unclaimed plan pinned to `phase` renders chip text `"phase"`, `data-source="explicit"`. Claimed plan with `claim.dispatch_mode="finish"` renders `"finish"` (`.textContent.trim()`), `data-state="running-finish"`, `aria-disabled="true"`. Claimed plan with `claim.dispatch_mode="phase"` renders `"phase"`, `data-state="running-phase"`, click dispatches (not aria-disabled).
- [ ] `bash skills/work-on-plans/scripts/filter-mode-mismatch-plans.sh` exists, is executable, has a usage block.
- [ ] `bash tests/test-work-on-plans-dispatch-seam.sh > $TEST_OUT/test-dispatch-seam.txt 2>&1` exits 0; all five new cases pass; idempotency case passes.
- [ ] Manual sandbox: seed `plans.ready = [{slug:"a", mode:"phase"}, {slug:"b", mode:"finish"}, {slug:"c"}]`; run `MODE_OVERRIDE=finish SPRINT_ID=test_s1 ... filter-mode-mismatch-plans.sh < ready.tsv` → stdout shows only `b` and `c`; `monitor-state.json:plans.skipped["a"]` exists with `code: "mode-mismatch"`, `reason: "finish≠phase"`, `sprint_id: "test_s1"`, valid ISO `at`.
- [ ] `grep -n 'plans.skipped\|mode-mismatch\|filter-mode-mismatch-plans' skills/work-on-plans/` returns hits in execute.md (filter pipe) AND scripts/ (new script).
- [ ] `grep -nE 'plan-skip-dismiss|skip-dismiss-btn|postPlanSkipDismiss' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` returns hits.
- [ ] `grep -n '_handle_plan_skip_dismiss_post\|/api/plan-skip-dismiss' skills/zskills-dashboard/scripts/zskills_monitor/server.py` returns hits.
- [ ] `grep -n 'clear_plan_skip_if_present\|plans.skipped' skills/run-plan/scripts/claim-plan.sh` returns hits.
- [ ] `bash tests/test-plans-skip-chip.sh > $TEST_OUT/test-plans-skip-chip.txt 2>&1` exits 0.
- [ ] `bash tests/test-plan-skip-clear-paths.sh > $TEST_OUT/test-plan-skip-clear-paths.txt 2>&1` exits 0 — all three clear paths + idempotency + bad-payload cases pass.
- [ ] `bash tests/run-all.sh > $TEST_OUT/.test-results.txt 2>&1` — all suites pass.
- [ ] Manual sandbox: seed `plans.skipped = {"a": {code:"mode-mismatch", reason:"finish≠phase", sprint_id:"S1", at:"..."}}` + `plans.ready = [{slug:"a", mode:"phase"}]`; spawn server with `--main-root $WORKTREE`; load dashboard; SKIP chip visible on `a`'s ready card with × button; click × → chip disappears within 2s (one poll cycle).

### Dependencies

Phase 1 (the run-status pill must be gone so the per-plan chip is the only mode affordance on screen — avoids confusing parallel UI; the queue POST handler's preserve-by-default refactor is the load-bearing precondition for the SKIP-chip three-clear-paths model — Phase 2's pin-toggle clear is an ADDITIVE layer on top of the deep-copy base).

---

## Phase 3 — Issues × dismiss + activity-feed SKIP pill + wrap-up

### Goal

Add the × dismiss button to existing Issues SKIP chips (POSTs to a new `/api/issue-reconsider` endpoint with sticky semantics — the chip stays until the next `/fix-issues` fire re-triages). Wire the activity-feed renderer to recognize `status: skip` from Phase 2's step markers with a new `a-status-skip` CSS class. Run final mirror-sync for every touched skill, end-to-end playwright verification of all chip + dismiss behaviors, write the CHANGELOG entry, and final `bash tests/run-all.sh` clean.

### Work Items

#### 3A — Issues SKIP chip × dismiss → reconsider endpoint

- [ ] **Dashboard `app.js` — extend the existing Issues skip-chip render.** The current chip uses `text: "skip: " + code + " — " + label,` — a single textContent assignment. Restructure the chip span (same way Phase 2 does) into a wrapper span containing two children: a `skip-chip-label` span and the × button. Keep the existing label format `"skip: " + code + " — " + label` (this is the canonical body shape; Phase 2's chip is harmonized TO this format, not the other way).
  - Replace the existing single-text skip-chip span with:
    ```js
    const chip = el("span", {
      cls: "skip-chip skip-chip--" + code,
      attrs: { title: source },
    });
    const labelSpan = el("span", {
      cls: "skip-chip-label",
      text: "skip: " + code + " — " + label,
    });
    const dismiss = el("button", {
      cls: "skip-dismiss-btn",
      attrs: {
        type: "button",
        "data-action": "issue-skip-dismiss",
        "data-issue-number": String(issue.number),
        "aria-label": "Reconsider issue #" + issue.number,
        title: "Reconsider (re-triage on next /fix-issues fire)",
      },
      html: SVG_ICONS.x,
    });
    chip.appendChild(labelSpan);
    chip.appendChild(dismiss);
    row.appendChild(chip);
    ```
  - **Click-delegator arm:** add inside `handleAction(action, target)`:
    ```js
    if (action === "issue-skip-dismiss") {
      const btn = target.closest('[data-action="issue-skip-dismiss"]') || target;
      const n = parseInt(btn.getAttribute("data-issue-number"), 10);
      if (Number.isInteger(n) && n > 0) return postIssueReconsider(n);
    }
    ```
  - Add the new fetch helper. **Use `showToast(message, kind, opts)`:**
    ```js
    async function postIssueReconsider(number) {
      try {
        const resp = await fetch("/api/issue-reconsider", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ number }),
        });
        if (!resp.ok) {
          showToast("Reconsider failed: " + resp.status, "err");
          return;
        }
        // Sticky semantics: chip stays until next /fix-issues fire re-triages.
        // Show a toast so the user understands the click was received but the
        // chip will not immediately disappear.
        showToast("Issue #" + number + " queued for re-triage on next /fix-issues fire", "info");
      } catch (err) {
        showToast("Reconsider error: " + (err && err.message ? err.message : err), "err");
      }
    }
    ```

- [ ] **Extend `fingerprintIssues`:** the current Issues fingerprint row tuple omits `i.skip_reason`. Without including it, after `/fix-issues` clears `issues.skipped[N]` (one-shot consume of `issues.reconsider`), the dashboard's poll diff-suppression keeps showing the chip until something else changes. Add `i.skip_reason ? [i.skip_reason.code, i.skip_reason.label] : null` to the row tuple. Symmetric with Phase 2's `fingerprintPlans` extension. Add a node-DOM test case (in `test-issues-skip-dismiss-ui.sh`) that flips `skip_reason` between snapshots and asserts re-render.

- [ ] **Dashboard `server.py` — add the `/api/issue-reconsider` handler.** Mirror the body of the canonical Python embed in `skills/fix-issues/subcommands/reconsider.md` and the shape of the existing dashboard POST handlers. Behavior in prose:
  - Gate on `_origin_ok()`.
  - Read the request body via the server's existing request-body reader — match its actual return signature when reading (the previous draft assumed a bare string; the actual signature differs; the implementer verifies at edit time).
  - Parse JSON; require an integer `number` greater than 0; return 400 otherwise.
  - Take the state lock; read the state via the standard reader.
  - Resolve `issues.reconsider` (creating intermediate dicts as needed). Append `number` if absent (dedup, idempotent).
  - Bump `updated_at` via the timestamp helper convention used elsewhere in server.py; atomic-write via the standard helper.
  - Respond 200 with `{ok: true, number, reconsider, updated_at}`.

  Add the dispatch-table entry: `POST /api/issue-reconsider → _handle_issue_reconsider_post`.

  Does NOT clear `issues.skipped[<N>]` — that's the next `/fix-issues` fire's job via its existing filter-unresearched-candidates flow. Sticky-by-design.

- [ ] **NEW test: `tests/test-issue-reconsider-endpoint.sh`** — server integration:
  - Spawn server with `--main-root $WORKTREE`.
  - Seed `monitor-state.json:issues.skipped = {"42": {code:"plan-scale", reason:"too big"}}`.
  - POST `/api/issue-reconsider` `{number: 42}` → 200; `issues.reconsider` now contains `[42]`; `issues.skipped["42"]` STILL PRESENT (sticky).
  - POST again with same number → 200; `issues.reconsider` still `[42]` (dedup).
  - Bad payload (`{}`, `{number:0}`, `{number:"x"}`, malformed JSON) → 400.
  - Wrong Origin header (CSRF) → 403.

- [ ] **NEW test: `tests/test-issues-skip-dismiss-ui.sh`** — Node-DOM stub mirroring the Plans test:
  - Case: issue with `skip_reason = {code:"plan-scale", label:"too big"}`, no claim → SKIP chip rendered with × button.
  - Case: same skip_reason BUT issue has a live claim → SKIP chip NOT rendered (mutual exclusion from #862/#898).
  - Case: × click → fetch to `/api/issue-reconsider` with `{number}` body.

#### 3B — Activity-feed SKIP pill + wrap-up

- [ ] **Dashboard `app.js` — extend `activityStatusClass`:**
  ```js
  function activityStatusClass(status) {
    const s = (status || "").toLowerCase();
    if (s === "pass" || s === "ok" || s === "complete" || s === "completed") return "a-status-pass";
    if (s === "fail" || s === "failed" || s === "error") return "a-status-fail";
    if (s === "running" || s === "started" || s === "in-progress") return "a-status-running";
    if (s === "skip" || s === "skipped") return "a-status-skip";
    return "";
  }
  ```

- [ ] **Dashboard `app.css` — add a rule alongside the existing activity-status pill rules:**
  ```css
  .activity-row .a-status-skip   { color: var(--pink); border-color: var(--pink); }
  ```
  (Palette: pink matches `.skip-chip`'s magenta so the activity-feed pill reads as the same semantic family as the per-card skip chip.)

- [ ] **NEW test: `tests/test-activity-feed-skip-status.sh`** — Node-DOM stub:
  - Provide an activity record `{kind:"step", id:"work-on-plans.S1.p1", status:"skip", output:"mode_mismatch: finish≠phase"}` to `renderActivity` (extract via `tests/lib/extract-fence.sh`).
  - Assert the rendered status pill has class `a-status-skip`.
  - Assert the output text renders (renderActivity already passes `a.output` through — verify).

- [ ] **Verify the marker-write from Phase 2 hits the activity feed end-to-end.** Spin up the collector against a fixture state where:
  - A `.zskills/tracking/PIPELINE/step.work-on-plans.S1.p1` marker exists with `status: skip`.
  - Assert `collect_snapshot()['activity']` contains a record with `status="skip"` and the marker fields.

- [ ] **Full mirror sweep** — for EVERY skill whose source files changed in any prior phase, re-run the per-phase bump+mirror recipe and assert `diff -rq` empty. Skills to verify:
  - `zskills-dashboard` — touched in Phases 1, 2, 3.
  - `work-on-plans` — touched in Phase 2.
  - `run-plan` — touched in Phase 2.
  - `update-zskills` — touched in Phase 1.
  - `fix-issues` — likely NOT touched at the source-file level (verify with `git diff origin/main..HEAD -- skills/fix-issues/`); skip bump if no diff.

  Final assertion script:
  ```bash
  for s in zskills-dashboard work-on-plans run-plan update-zskills; do
    diff -rq "skills/$s/" ".claude/skills/$s/" || { echo "MIRROR DRIFT: $s"; exit 1; }
  done
  ```

- [ ] **Skill version bump** for `zskills-dashboard` (Phase 3 source changes). Mirror. (`fix-issues` SKILL.md only needs a bump if SKILL.md prose changes; verify via `grep -n "issue-reconsider" skills/fix-issues/SKILL.md` — likely no edit needed.)

- [ ] **playwright-cli end-to-end verification** (MANDATORY per `feedback_playwright_mandatory_for_ui_ship`). Spawn the dashboard server with `--main-root "$(git rev-parse --show-toplevel)"`. Seed:
  - `monitor-state.json:plans.ready = [{slug:"a"}, {slug:"b", mode:"phase"}, {slug:"c", mode:"finish"}]`
  - `monitor-state.json:plans.skipped = {"b": {code:"mode-mismatch", reason:"finish≠phase", sprint_id:"S1", at:"<iso>"}}`
  - `monitor-state.json:issues.ready = [42]` with `issues.skipped = {"42": {code:"plan-scale", reason:"too big"}}`

  Walk-through:
  0. **End-to-end producer test:** before the seeded UI walk, EXERCISE the producer path: start from a clean state with `plans.ready = [{slug:"e2e_plan", mode:"finish"}]` (pinned finish, no pre-seeded skip). Invoke `/work-on-plans 1 phase` (cron-shape). Assert (a) `monitor-state.json:plans.skipped["e2e_plan"]` is now populated with `{code:"mode-mismatch", reason:"phase≠finish", sprint_id:<>, at:<>}`; (b) a `step.work-on-plans.<sprint>.e2e_plan` marker exists under `.zskills/tracking/work-on-plans.<sprint>/` with `status: skip`; (c) the dashboard's `/api/state` snapshot's activity array includes a record with `status="skip"` and the marker fields; (d) reload the dashboard, the SKIP chip is now visible on `e2e_plan`'s card with the × button. Then proceed to step 1 with the original seeded state.
  1. `playwright-cli screenshot` the initial dashboard — name the file `dashboard-cleanup-initial.png`. Verify visually: NO `#run-status` pill at the top of the Plans column. Plan `a` shows `inherit` chip (lowercase). Plan `b` shows `phase` chip + SKIP chip with × (mutual-exclusion: not claimed). Plan `c` shows `finish` chip. Issue 42 shows skip chip with ×.
  2. Click × on Plan `b`'s SKIP chip. Wait ~2s. Screenshot `dashboard-cleanup-after-plans-dismiss.png`. SKIP chip on `b` should be gone.
  3. Click Plan `c`'s mode chip (toggle to INHERIT). Verify it cycles. Click again (PHASE). Click again (FINISH). Click again (INHERIT). All four states render distinctly.
  4. Simulate a FINISH claim on `c` via the production code path: `bash skills/run-plan/scripts/claim-plan.sh acquire c --pipeline-id pw_test --dispatch-mode finish`. (Do NOT hand-write the claim.json — the script writes the full schema including `started_at` and `current_phase`; a hand-written file may miss fields collect.py reads.) Reload. Verify `c`'s chip is locked (visual lock-icon + `aria-disabled="true"`). Click it — no POST should fire.
  5. Click × on Issue 42's skip chip. Wait ~2s. Screenshot `dashboard-cleanup-after-issues-dismiss.png`. Toast `"Issue #42 queued for re-triage on next /fix-issues fire"` should have appeared. Chip should STILL BE PRESENT (sticky).
  6. Verify `monitor-state.json:issues.reconsider` now contains `[42]`.

  Each screenshot saves to `.playwright/output/` (per playwright-cli config); rename to descriptive name. Attach to PR body in Phase 3's Notes.

- [ ] **CHANGELOG.md** — add one cohesive entry at the top under `## Unreleased`:
  ```markdown
  ### Dashboard run-status cleanup (#1005 + #1006)

  - Removed the top-level run-status pill and all trigger-script plumbing
    (`#run-status` div, `renderRunStatus`, `/api/trigger`,
    `/api/work-state/reset`, `dashboard.work_on_plans_trigger` config field,
    and the `/update-zskills` backfill). The pill's empty-state bug (#995/#997)
    is subsumed.
  - Per-plan mode chip is now a true three-state UI: explicit `INHERIT`
    label replaces the silent fallthrough-to-`finish`. PHASE / FINISH labels
    unchanged. The chip locks (disabled toggle) when an in-flight FINISH
    claim is held; PHASE claims remain togglable for the next inter-phase
    dispatch.
  - `/work-on-plans` now treats an explicit batch-mode + explicit per-plan
    pin mismatch as a SKIP (not an override). Skipped plans record a
    `plans.skipped[<slug>]` marker in `monitor-state.json`, flow into the
    activity feed via a new `a-status-skip` pill, and surface a SKIP chip
    on the dashboard ready card. The skip auto-clears on three paths:
    `claim-plan.sh acquire`, pin-toggle via the chip, or × dismiss on the
    SKIP chip itself (new `/api/plan-skip-dismiss` endpoint).
  - Issues SKIP chips now carry a × dismiss button that POSTs to
    `/api/issue-reconsider`, mirroring the existing `/fix-issues reconsider
    <N>` CLI semantics. Issues skip stays sticky (clears on next
    `/fix-issues` fire); the toast confirms the click was received.
  - Side-benefit: the dashboard's queue POST handler now preserves
    unknown / nested keys by default (deep-copy base + writable-column
    overlay), closing a pre-existing latent bug that wiped
    `issues.skipped` and `issues.reconsider` on every drag-drop
    (#813/#733).

  Closes #1005. Closes #1006.
  ```
  Two separate `Closes` keywords (one per issue), even in the CHANGELOG prose, prevents the implementer from propagating a comma- or "and"-form into the PR-body footer where it would silently miss #1006. The PR-body footer in `## Final landing checklist` uses the SAME two-keyword pattern.

- [ ] **Final test pass:**
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  ```
  Read `"$TEST_OUT/.test-results.txt"`. All suites pass. Each suite enumerated explicitly.

### Design & Constraints

- The endpoint name `/api/issue-reconsider` (singular) matches the CLI `reconsider <N>` semantics. Avoid pluralizing — one issue per call.
- The toast message is REQUIRED because the chip stays visible (sticky). Without a toast the user thinks the click was lost. `showToast` has an 8-second auto-dismiss + explicit close button; the ~60-char message `"Issue #N queued for re-triage on next /fix-issues fire"` is well within rendering bounds.
- Mutual exclusion (live claim suppresses chip) is ALREADY in place at the existing chip render; no change needed for that invariant — only the × button addition inside the chip.
- DO NOT change the existing Issues skip-chip RENDER logic — only ADD the × button. The post-#862 sticky semantics are deliberate; this phase preserves them while giving users a dashboard affordance to opt-in to re-triage.
- The endpoint MUST gate on `_origin_ok` (CSRF). The CLI's `record-skip.sh` doesn't because it's not network-reachable; the server endpoint is.
- DO NOT touch `subcommands/reconsider.md` — it stays as the CLI canonical. The server endpoint REIMPLEMENTS the same Python locally (factoring into a shared helper is more invasive than copying the ~5 lines).
- The activity-feed marker path was already established by Phase 2's `filter-mode-mismatch-plans.sh` — Phase 3 only adds the rendering arm + CSS.
- The CHANGELOG entry uses one cohesive paragraph cluster — do NOT split into per-PR sub-entries (this is one PR, one merge, one entry).
- The `Closes #1005\nCloses #1006` footer in the PR body (and same form in the CHANGELOG) must use one `Closes` keyword per issue — comma-list or "and"-form silently misses the second (ref `feedback_pr_closes_keyword_per_issue`). Implementer ensures this in the PR body when `/run-plan` dispatches `/land-pr`.
- **Per-phase mirror discipline:** the `/commit` step 2.5 + `block-stale-skill-version.sh` PreToolUse hook enforces that EVERY commit touching a skill carries a current `metadata.version`. Phases 1 and 2 each MUST run the per-phase bump+mirror recipe BEFORE the phase commit lands; Phase 3's "full mirror sweep" is a FINAL VERIFICATION that the prior bumps were complete, not a substitute for them.
- The screenshot review IS the load-bearing verification. Per `feedback_playwright_mandatory_for_ui_ship`: Node-DOM stubs cannot fire real CSS / `matchMedia`. Six visible UI bugs in DOC_VIEWER PR #980 made it past 7336 node-stub tests.

### Invariants & Watch-outs

- **Issues skip is STICKY — the × dismiss appends to `issues.reconsider[]`, it does NOT clear `issues.skipped[N]` immediately.** The next /fix-issues fire reads reconsider list and re-triages. The chip remains visible until that fire happens. The toast informs the user; the chip-stuck behavior is correct, not a bug.
- **Plans × and Issues × LOOK identical to the user but invoke DIFFERENT write paths backed by DIFFERENT semantic models. Do not converge them.** Plans × calls `/api/plan-skip-dismiss` (ephemeral clear). Issues × calls `/api/issue-reconsider` (sticky append). The visual parity is a UX affordance; the semantic difference is by design. Do not refactor into a "shared dismiss" abstraction — see Overview "Explicit non-goal."
- **The activity feed SKIP entry's source data is whatever Phase 2 writes** (a tracking marker under `.zskills/tracking/$PIPELINE_ID/step.work-on-plans.${SPRINT_ID}.${SLUG}` with `status: skip`). The pill style adopts the existing `activityStatusClass` mapping — adding a single `"skip"`/`"skipped"` → `"a-status-skip"` arm.
- **`fingerprintIssues` MUST include `skip_reason`.** Symmetric with Phase 2's `fingerprintPlans` extension. Without it, the next `/fix-issues` fire clears the skip-state but the dashboard's diff-suppression keeps the chip visible until something else changes.
- **The endpoint dedup is idempotent.** Re-clicking × on the same issue produces a second 200 but does NOT duplicate the number in `issues.reconsider`. Tests must assert both the success status AND the list shape after re-click.
- **CSRF gate is non-negotiable for the network-reachable endpoint.** The CLI bypasses `_origin_ok` because it isn't reachable from a browser; the server endpoint MUST gate.
- **The canonical reconsider Python embed lives in `skills/fix-issues/subcommands/reconsider.md`.** The server endpoint COPIES the ~5-line append-with-dedup logic; it does NOT shell out, source, or otherwise reuse the CLI fence. If the CLI logic ever changes meaningfully, both sites must be updated — record this dependency in a comment at the server-side embed.
- **Screenshots ARE the verification.** Node-DOM stubs do not render real CSS or fire real `matchMedia`. A green stub suite tells you nothing about whether the user sees a `#run-status` pill, whether the INHERIT chip is visually distinct, whether the lock icon renders, or whether the SKIP chip's × button is hittable. The playwright shots in this phase are the floor, not optional.
- **The producer walk (Step 0) is load-bearing.** Without it, the seeded-state UI walk verifies only the CONSUMER side. The producer side (Phase 2's filter writing the skip marker, the activity feed picking it up) needs its own end-to-end fire to prove the integration. Don't skip Step 0 because "we tested the unit."
- **The PR body footer uses TWO separate `Closes` keywords, one per issue.** Comma-list (`Closes #1005, #1006`) and conjunction (`Closes #1005 and #1006`) both silently miss the second issue at merge time.
- **Mirror sync is per-phase, not deferred.** The PreToolUse `block-stale-skill-version.sh` hook fails closed on any commit that touches a skill source file without bumping its `metadata.version` in the same commit. Phases 1 and 2 EACH bump and mirror their touched skills BEFORE the phase commit lands; Phase 3's sweep is the verification, not the substitution.
- **The activity-feed `a-status-skip` class belongs to the same semantic family as the per-card skip chip.** Color match (`var(--pink)`) is the affordance — a user seeing both pieces of UI should recognize them as the same event. Don't repaint to a different palette.

### Acceptance Criteria

- [ ] `grep -nE 'issue-skip-dismiss|postIssueReconsider' skills/zskills-dashboard/scripts/zskills_monitor/static/app.js` returns hits.
- [ ] `grep -n '_handle_issue_reconsider_post\|/api/issue-reconsider' skills/zskills-dashboard/scripts/zskills_monitor/server.py` returns hits.
- [ ] `bash tests/test-issue-reconsider-endpoint.sh > $TEST_OUT/test-reconsider-ep.txt 2>&1` exits 0 (5+ cases including dedup, idempotent, bad-payload, CSRF).
- [ ] `bash tests/test-issues-skip-dismiss-ui.sh > $TEST_OUT/test-issues-skip-ui.txt 2>&1` exits 0.
- [ ] `grep -nE 'a-status-skip' skills/zskills-dashboard/scripts/zskills_monitor/static/{app.js,app.css}` returns hits in both files.
- [ ] `bash tests/test-activity-feed-skip-status.sh > $TEST_OUT/test-activity-skip.txt 2>&1` exits 0.
- [ ] For each touched skill `S in {zskills-dashboard, work-on-plans, run-plan, update-zskills}`: `diff -rq skills/$S/ .claude/skills/$S/` is empty.
- [ ] `bash scripts/skill-content-hash.sh skills/<name>` matches the value AFTER the `+` in `skills/<name>/SKILL.md`'s `metadata.version` for each touched skill.
- [ ] `bash tests/test-skill-conformance.sh > $TEST_OUT/test-skill-conformance.txt 2>&1` exits 0.
- [ ] Six playwright screenshots saved + verified visually (initial; after-plans-dismiss; INHERIT/PHASE/FINISH/INHERIT cycle; FINISH-locked; after-issues-dismiss). NO empty `#run-status` pill anywhere in any screenshot. SKIP chips on Plans `b` (initial) and Issues 42 (initial + still-present after click) render with × buttons. INHERIT chip on Plan `a` renders the literal text `inherit`.
- [ ] CHANGELOG.md has the new entry as the top item under `## Unreleased`.
- [ ] Manual sandbox: spawn server with `--main-root $WORKTREE`; seed `issues.skipped = {"42":{...}}`; dashboard shows × on issue 42's skip chip; click × → toast `"Issue #42 queued for re-triage on next /fix-issues fire"` appears; chip stays visible (sticky); `monitor-state.json:issues.reconsider` now contains `[42]`.
- [ ] `bash tests/run-all.sh > $TEST_OUT/.test-results.txt 2>&1` — every suite passes, enumerated.

### Dependencies

Phases 1 and 2 complete. Phase 1 provides the queue-POST preserve-by-default refactor that protects `issues.reconsider` from being wiped on drag-drop. Phase 2 introduces the `.skip-dismiss-btn` CSS class + `el()` × button pattern that Phase 3 reuses (DRY), and Phase 2's filter-mode-mismatch step markers are the producer for the activity-feed SKIP pill rendered here.

---

## Final landing checklist

When `/run-plan` reaches Phase 3 done, the dispatch into `/land-pr` should:

- Title: `do: dashboard run-status cleanup + Plans/Issues × dismiss (#1005, #1006)`
- Body footer: two literal lines `Closes #1005` then `Closes #1006` (separate lines, one keyword each — per `feedback_pr_closes_keyword_per_issue`; comma or "and" forms silently miss the second issue).
- `--auto` flag: include (issue+plan are pre-authorized; this is agent-facing dashboard work — no human-eyeballs gate beyond the screenshots already verified).
- CI must pass; on failure, run the fix-cycle template via `/land-pr`'s dispatch.

---

## Plan Quality

### Drafting Process

1 review round + 1 re-anchor pass + 1 consolidation pass; phases consolidated from 6 to 3 to right-size for the implementation surface. The original 6-phase shape (Phase 1 rip, Phase 1.5 queue-POST refactor, Phase 2 chip three-state, Phase 3 mode-conflict filter, Phase 4 Plans SKIP × dismiss, Phase 5 Issues × dismiss, Phase 6 activity-feed + wrap-up) was fragmented relative to the actual work coherence: the queue-POST refactor is a precondition for the same surface Phase 1 rips, and the chip-three-state + mode-conflict + SKIP-chip work all touch the same per-plan card UI in the same code paths. The consolidated shape preserves every work item, invariant, design decision, and acceptance criterion; only phase boundaries moved.

### Justifications carried forward from Round 1 refinement

- **R-23 (test command labels):** `bash tests/run-all.sh` is the only test entry point — `CLAUDE.md`'s "Unit tests only -- fast" vs "ALL suites" duplication is a stale doc artifact; both lines invoke the same command. The plan uses one form consistently and does not attempt to label runs as "unit only." No plan change needed.
- **R-17 (× character RTL):** speculation, not anchored — U+00D7 has Unicode bidi class ON (Other Neutral), not bidirectional-flipping. Resolved by R-15 instead: use `SVG_ICONS.x` rather than the literal character.
- **R-4 (lastFingerprint sole-property worry):** verified the dict literal has 5 keys; deleting `workState` leaves 4. The cautionary parenthetical was vestigial. Plan now explicitly notes the post-delete key count.
- **DA-7 (typed `/run-plan` bypasses pin):** scoping decision — the hard-constraint promise applies at the `/work-on-plans` selection boundary ONLY. Typed `/run-plan <slug> finish` against a `phase`-pinned plan is treated as an explicit one-shot CLI override (consistent with how the `dispatch_mode` override already works in `claim-plan.sh`). Extending the constraint to `/run-plan acquire` would require a new error path and rc code — a separate plan if anyone wants it.

### Round 1 Disposition

| ID | Title | Evidence | Disposition | Notes |
|---|---|---|---|---|
| R-1 | Queue POST handler does not preserve unknown / sibling state keys | Verified — `grep "issues.skipped\|issues.reconsider" server.py` = 0 hits; output-doc dict literal has no `existing[*]` carry beyond `existing_dm` | Fixed | New **Phase 1.5** broadens the writer to preserve-by-default via `copy.deepcopy(existing)`; regression test covers all three preserved keys |
| R-2 | Test-prune scope in `test_zskills_monitor_dashboard_ui.sh` under-counted | Verified — grep returns 33 hits vs plan's ~5 anchors | Fixed | Phase 1 test-prune now uses grep-based acceptance criterion (post-edit must return 0 hits); line anchors removed |
| R-3 | `test_zskills_monitor_server.sh` prune range starts too late | Verified — reset block precedes the original anchor | Fixed | Phase 1 range described by role (reset block + trigger block, contiguous); grep-based criterion added |
| R-4 | `lastFingerprint.workState` removal — sole-property worry vestigial | Verified — dict has 5 keys; 4 remain after delete | Justified | Plan now states verified key count; struck the cautionary parenthetical |
| R-5 | `scheduleWorkPoll(0)` bootstrap sites not enumerated | Verified — four sites in app.js (two die with containing functions; two standalone bootstraps) | Fixed | Plan describes the sites by ROLE (init bootstrap, theme-change bootstrap) + names the post-edit grep that catches misses |
| R-6 | Locked-chip render uses lowercase chip-text source, plan prose used uppercase `INHERIT/PHASE/FINISH` | Verified — locked branch embeds the chip-text source (lowercase) | Fixed | Phase 2 now consistently uses LOWERCASE for chip text + aria-labels uniformly; tests + acceptance criteria updated |
| R-7 | Locked-chip text assertion idiom not specified | Verified — SVG injection adds leading whitespace to textContent | Fixed | Phase 2 explicitly requires `.textContent.trim()` for locked chips; exact equality for non-locked |
| R-8 | Python embed lacks bash-level `with_monitor_lock` wrap | Verified — `with_monitor_lock` is defined only in SKILL.md, not in a sourceable helper | Fixed | Phase 3 now shows the inline `flock -x` on FD 9 pattern explicitly (resolved per DA-4 too) |
| R-9 | "Move BATCH_MODE earlier" conflates MODE_OVERRIDE and BATCH_MODE | Verified — `MODE_OVERRIDE` is set by Step 0 well before the filter; only it is needed by the new arm | Fixed | Phase 3 wiring instructions corrected: pass `MODE_OVERRIDE` directly; do NOT move the `BATCH_MODE` resolution |
| R-10 | Step-marker write references `$PIPELINE_ID` not in the documented inputs | Verified — script's env-var contract listed only MODE_OVERRIDE/SPRINT_ID/MAIN_ROOT | Fixed | Phase 3 work item now lists 4 env-var inputs including `PIPELINE_ID` (computed in execute.md's SPRINT_ID block) |
| R-11 | `extract-fence.sh` misused for standalone `.sh` file | Verified — `extract-fence.sh` is for markdown-embedded fences; standalone scripts are invoked directly (per `test-fix-issues-skip-persistence.sh` precedent) | Fixed | Phase 3 test guidance now uses direct `bash skills/.../filter-mode-mismatch-plans.sh` invocation |
| R-12 | Queue POST handler extension under-described — same root cause as R-1 | Verified per R-1 | Fixed | Same Phase 1.5 broadening; the Phase 4 pin-toggle clear is now an additive layer on top |
| R-13 | `clear_plan_skip_if_present` not called on self-reentry path | Verified — claim-plan.sh's self-reentry path returns 0 without reaching the new hook point | Fixed | Phase 4 design constraint explicitly documents: self-reentry SKIPS the clear (original acquire already did it); if defense-in-depth is wanted later, the idempotent helper makes a redundant call harmless |
| R-14 | Chip with `text:` + `appendChild` produces flat sibling layout | Verified — `el()` helper assigns textContent THEN appendChild | Fixed | Phase 4 restructured chip to wrapper-span with two children (`skip-chip-label` + `skip-dismiss-btn`); CSS updated to `inline-flex` |
| R-15 | `SVG_ICONS.x` exists; using literal × creates idiom inconsistency | Verified — `SVG_ICONS.x` is the existing SVG-icon helper used in multiple chrome sites | Fixed | Phases 4 + 5 now both use `html: SVG_ICONS.x` (chrome-only XSS carveout); literal × character struck |
| R-16 | Idempotent-200 semantics under-documented | Verified — logic was sound, prose was thin | Fixed | Phase 4 server prose now has explicit comment: "Idempotent: when slug absent, NO WRITE; returns existing updated_at unchanged" |
| R-17 | "× RTL-sensitive" speculation | Verified — U+00D7 has bidi class ON, not RTL-flipping | Justified | Resolved by R-15 (use SVG_ICONS.x instead of literal); RTL note struck; rationale captured in Plan Quality |
| R-18 | Phase 5 inherits the same flat-sibling layout issue | Verified per R-14 | Fixed | Phase 5 restructured to wrapper-span with `skip-chip-label` + `skip-dismiss-btn`, same as Phase 4 |
| R-19 | `/api/issue-reconsider` writes get wiped by queue POST handler | Verified per R-1 | Fixed | Phase 1.5 closes this; Phase 5 endpoint then layers on top |
| R-20 | `toast()` signature unverified for ~60-char message | Verified — `showToast(message, kind, opts)` has 8s auto-dismiss + close button; 60 chars renders fine | Fixed | Phase 5 design constraint documents the verified signature; combined with DA-3, all `toast()` calls were changed to `showToast(...)` |
| R-21 | Hand-written claim.json bypasses production schema | Verified — schema includes `started_at`, `current_phase`, etc.; manual writes risk omitting | Fixed | Phase 6 step 4 now invokes `claim-plan.sh acquire c --pipeline-id pw_test --dispatch-mode finish` directly |
| R-22 | CHANGELOG / PR-body `Closes` keyword usage risks comma/and-form trap | Verified per `feedback_pr_closes_keyword_per_issue` | Fixed | CHANGELOG block now uses two separate sentences; Final landing checklist uses explicit two-line `Closes #1005\nCloses #1006` form |
| R-23 | `bash tests/run-all.sh` "unit only" framing is stale doc | Verified — both CLAUDE.md lines run the same command | Justified | Plan does not attempt to differentiate suite subsets; rationale recorded above |
| R-24 | Mirror-sweep must be per-phase, not deferred to Phase 6 | Verified — `block-stale-skill-version.sh` PreToolUse gates every commit; Phase-N commits without bumps fail closed | Fixed | Phase 6 design constraints now explicitly call out per-phase mirror discipline; phase-N commits must carry the bump |
| R-25 | Server-spawning tests need trap-on-EXIT cleanup discipline | Verified — CLAUDE.md "Dev Server" prohibition applies; existing `test_zskills_monitor_server.sh` pattern is the model | Fixed | Added Invariant #15 to Shared Conventions; spec'd test-cleanup pattern |
| R-26 | Status-line insertion site for `Mode-mismatch skipped: N` not named | Verified — execute.md has a status-line slot just before the empty-queue exit | Fixed | Phase 3 work item now names the slot by role + provides the exact echo block |
| DA-1 | Queue POST handler clobbers `plans.skipped` / `issues.skipped` / `issues.reconsider` | Verified — same root cause as R-1; confirmed via `grep "issues.skipped\|issues.reconsider" server.py` = 0 hits | Fixed | Phase 1.5 broadens the writer; covers pre-existing latent bug for `issues.skipped`/`issues.reconsider` — CHANGELOG mentions as side-benefit |
| DA-2 | State reader filters out `plans.skipped` (dict, not list) before it reaches collector | Verified — the per-column loop discards non-list values; `plans.skipped` is a dict | Fixed | Phase 4 collect.py work item now explicitly extracts `plans.skipped` separately AND threads it through the return |
| DA-3 | `toast(...)` is not defined — helper is `showToast(...)` | Verified — `grep "^function toast" app.js` = 0 hits; `showToast` exists | Fixed | All `toast()` calls in Phase 4 + Phase 5 prose changed to `showToast(message, kind, opts)` with explicit kind tokens |
| DA-4 | `with_monitor_lock` not sourceable; not in `zskills-resolve-config.sh` | Verified — grep on resolve-config / paths-config returned 0 hits | Fixed | Phase 3 spec now reimplements `flock -x` inline against `.zskills/monitor-state.json.lock` (option b in DA-4's suggested fix); rationale captured |
| DA-5 | Cron multi-fire spams skip markers + activity-feed pollution | Verified — embed had no idempotency guard; SPRINT_ID regenerates per fire | Fixed | Phase 3 python embed now uses FRESH/STALE sentinel; only writes step marker on first occurrence of (slug, code, reason); preserves `at`, refreshes `sprint_id` |
| DA-6 | Three-clear-paths race has no acceptance test | Verified per code reading | Fixed | Phase 4 acceptance criteria now includes a race test (held lock for ~50ms) asserting claim succeeds even on clear-skip lock contention, and mutual-exclusion makes the chip-render outcome bounded |
| DA-7 | Typed `/run-plan` bypasses pin — scope ambiguity | Verified — `claim-plan.sh:cmd_acquire` accepts `--dispatch-mode` unconditionally | Justified | Plan now scopes the constraint to the `/work-on-plans` boundary explicitly (Overview pillar 2 qualifier + Phase 3 D&C); typed `/run-plan` override is intentional behavior, not a gap |
| DA-8 | Pin-change diff over `ready` only misses column-cross moves | Verified — Phase 4 spec referenced only `existing.plans.ready` | Fixed | Phase 4 pin-diff spec now flattens `(slug → mode)` across ALL plan columns (including `completed`); new test cases for column-cross-without-toggle and sibling-preservation added |
| DA-9 | Issue chip body `"skip: code — label"` differs from Plans chip pseudocode `"skip: reason"` | Verified — issue side uses the canonical body shape | Fixed | Phase 4 chip text harmonized to the issue-side format `"skip: " + code + " — " + reason` (DA-9 suggested fix variant) |
| DA-10 | `fingerprintIssues` lacks `skip_reason` — sticky-clear won't trigger re-render | Verified — the existing row tuple has no `skip_reason` | Fixed | Phase 5 now explicitly extends `fingerprintIssues` symmetrically with Phase 4's `fingerprintPlans` extension; new node-DOM test asserts re-render on skip_reason flip |
| DA-11 | Acquire hook is INSIDE python heredoc, not bash-callable | Verified — heredoc terminator separates python body from bash; bash resumes after | Fixed | Phase 4 hook-point description rewritten to specify the bash hook between heredoc-close and `return 0` |
| DA-12 | `applyWorkState` post-delete is unambiguously vestigial | Verified — its only callers and effects are in the deletion set | Fixed | Phase 1 now directs DELETE `applyWorkState` firmly, not as a conditional hedge |
| DA-13 | Click delegator uses `ev.target` but `handleAction(action, target)` takes target directly | Verified — handler signature receives `target` directly | Fixed | Phase 4 + Phase 5 delegator arms rewritten to use `target.closest('[data-action="..."]')` pattern; eliminates bubble-from-SVG-child trap |
| DA-14 | No volume / per-fire test asserts idempotency at marker level | Verified per DA-5 | Fixed | Phase 3 new test case `mode_mismatch_twice_produces_one_step_marker` added — runs filter twice with different SPRINT_IDs, asserts single marker per unique (slug, code, reason) |
| DA-15 | Idempotent dismiss case doesn't assert `updated_at` preservation | Verified per R-16 | Fixed | Phase 4 idempotency test now records `existing.updated_at` BEFORE and AFTER, asserts equality on the no-op path |
| DA-16 | Playwright walk skips end-to-end producer→consumer | Verified per code reading | Fixed | Phase 6 walk-through gains a Step 0 that invokes `/work-on-plans 1 phase` against a finish-pinned plan, asserts the state mutation + step marker + activity-feed pill + UI chip materialize before proceeding to the seeded-state UI walk |

(Phase references in the disposition table are preserved from the original 6-phase draft — they are the design history. The consolidated 3-phase mapping is: original Phase 1 → Phase 1; original Phase 1.5 → Phase 1; original Phases 2, 3, 4 → Phase 2; original Phases 5, 6 → Phase 3.)

### Round 2 — Re-anchor pass (drift-resistance)

The Round 1 plan referenced source code by helper name and line number heavily — `_state_path()`, `_handle_queue_post` at line 1670, `PLAN_COLUMNS = ("drafted","reviewed","ready","backlog","discarded")` (which omitted `completed`), `datetime.utcnow()` in pseudocode, `_read_request_body()` typed as returning a string. Several of those references were wrong against current HEAD; all of them were brittle against any future refactor that renames a helper or moves code.

Round 2 trades that precision for behavior-level descriptions and explicit per-phase **Invariants & Watch-outs** subsections. The new shape:

- File-in-scope entries describe each touched file by ROLE (e.g. "the queue POST handler in server.py" instead of "line 1670"). The implementer reads at HEAD before editing; the plan does not pretend to know line numbers that will shift between draft and execution.
- Code embeds that survive (Phase 2's `flock -x` pattern, Phase 2's chip-rendering JS, Phase 3's CHANGELOG, server-handler skeletons) carry the EXACT shape the implementer should code to. Embeds the prose can describe equally well in behavior (the queue-POST refactor, the Python skip-write embed, the dismiss handlers, the reconsider handler) are rewritten as prose so an implementer who finds a cleaner equivalent isn't blocked by stale pseudocode.
- Helper-name references that won't drift (e.g. `el()`, `showToast`, `SVG_ICONS.x`, `_origin_ok`, `claim-plan.sh:cmd_acquire`) stay literal because they are stable surface-API names, not internal scaffolding.
- Each phase gains a dedicated **Invariants & Watch-outs** subsection that captures the load-bearing constraints the implementer must respect. These invariants are drift-resistant because they describe BEHAVIOR (what must be true after the edit), not source code (where the edit lands). The most critical ones:
  - Phase 1: the queue POST handler MUST preserve `plans.skipped`, `issues.skipped`, `issues.reconsider` — the deep-copy base is the mechanism, the preservation is the contract.
  - Phase 1: the state-reader the queue handler depends on MUST return full top-level shape; the handler depends on it.
  - Phase 2: the FINISH-claim chip lock MUST anchor on the claim's captured `dispatch_mode`, NEVER on the wrapper's `batch_mode` — same trap #930 hit.
  - Phase 2: the skip-check fires ONLY when `MODE_OVERRIDE` is non-empty; the default fall-through to `"finish"` is NOT "explicit"; bare invocations never skip.
  - Phase 2: the pin-diff walks EVERY plan column where a pin can live, including `completed`; a constant column list that omits `completed` silently wipes skip markers on drag-to-completed.
  - Phase 2: the state-reader's shape filter must tolerate `plans.skipped` as a DICT (slug→record), not silently drop it as a non-list value.
  - Phase 3: Issues skip is STICKY (clears via the next `/fix-issues` fire); Plans skip is EPHEMERAL (three clear paths). The × buttons look identical; the write paths differ.

The disposition table above (Round 1) is preserved verbatim — it is the design history and remains the authoritative record of which research findings drove which decisions.
