---
title: Completed + Backlog dashboard sections
created: 2026-05-22
status: active
---

# Plan: Completed + Backlog dashboard sections

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Add two new horizontal "below-panel" bands to the zskills-dashboard, one beneath the **Plans** panel and one beneath the **Issues** panel. Each band exposes two sub-columns:

- **Completed** — read-only, derived from ground truth (GH `closedAt` for issues; plan-frontmatter `completed:` for plans, written by `/run-plan` Phase 5b), filtered to a recency window (configurable via `execution.dashboard_completed_days`, default 14).
- **Backlog** — persistent, explicit user-curated list stored in `monitor-state.json` under new `issues.backlog: [N,...]` and `plans.backlog: ["slug",...]` arrays. Bidirectional drag (Triage ↔ Backlog, Drafted ↔ Backlog).

The extension touches four layers in lockstep — `collect.py` (snapshot assembly), `server.py` (validator + version writers), `app.js` (rendering + drag handlers), `app.css` (new layout primitive) — and bumps the state-file schema from v1.1 → v1.2 while keeping `_read_state_file` tolerant of older files. Composes cleanly with PR #617 (move-all chevrons, suppressed on Completed), PR #600 (claim aria-disabled, suppressed on Completed cards), and PR #622 (claim-chip parity).

The dominant constraint is **"surface bugs don't patch"**: the existing `_infer_default_column` returns `None` for `status in ("complete","landed")` (collect.py:1251-1268), causing completed plans to be HIDDEN. Phase 1 fixes that at the inference site rather than working around it in the renderer. A symmetric `_infer_issue_default_column` is added because `_annotate_issues_queue` currently defaults unmatched issues to `triage` unconditionally (collect.py:1414-1424).

**Out of scope (deferred to follow-up issue):** Issue #618 (`landedPillClass` mapping gap — currently 2 explicit arms + fallthrough vs. canonical 11-status set from `briefing/SKILL.md:231-234` + `fix-report/SKILL.md:161`). The opportunistic close in earlier draft was based on a fabricated status set; a proper audit-then-implement is its own change. Filed as a follow-up before this plan lands.

## Locked Decisions

- **D1. Completed semantics.** Time-window-based, READ-ONLY. Default 14 days for both issues and plans. Config field `execution.dashboard_completed_days` (default 14). Source of truth: GH issue `closedAt` (for issues), plan-file `completed:` YAML frontmatter field written by `/run-plan` Phase 5b. **Plan-file `completed:` frontmatter is MANDATORY** — file-mtime fallback is structurally unreliable (Drift Log writes, typo fixes, formatter passes bump mtime); historical plans are backfilled in W1.5b via a **content-pickaxe** query (`git log -G"^status:[[:space:]]*complete$" --follow --reverse --format=%cI -- "$ZSKILLS_PLANS_DIR/<slug>.md" | tail -1`) — NOT `git log --diff-filter=AM` (which returns file-creation date, not status-introduction date). The `complete → None` mapping in `_infer_default_column` is fixed at the inference site (not at the renderer). **Verification:** grep `_infer_default_column` in `skills/zskills-dashboard/scripts/zskills_monitor/collect.py` (lines 1251-1268) confirms the `complete → None` return that this plan replaces with a windowed `complete → "completed"` branch. Empirically verified 2026-05-22: `--diff-filter=AM` returns the initial file-creation commit (when frontmatter was `status: active`); pickaxe `-G"^status:[[:space:]]*complete$"` returns ONLY commits whose diff introduced (or removed) the `status: complete` line, which is the desired semantic.

- **D2. Backlog semantics.** PERSISTENT explicit list in `monitor-state.json`. Source-of-truth is the JSON file: `state.issues.backlog: [N, ...]` and `state.plans.backlog: ["slug", ...]`. NOT a GH label, NOT an "untriaged" heuristic. Bidirectional drag: items can be demoted into Backlog from any active column AND promoted out of Backlog back to Triage/Drafted. **Verification:** read `_validate_queue_body` at `server.py:435-492` and `_read_state_file` at `collect.py:1276-1342` — both already iterate column tuples generically, so extending the tuples picks up new columns mechanically.

- **D3. Positioning.** Horizontal band BENEATH each panel — TWO new bands total. Each band has two sub-columns: Completed | Backlog. A new CSS layout primitive `.below-panel-band` is introduced as a **standalone** 2-column grid (`grid-template-columns: 1fr 1fr`), NOT a composition with `.columns-2` — kept separate so the band can collapse independently and align beneath the active row without forcing the active row to widen. Backlog ALWAYS renders as a drop-target (never `hidden`); Completed collapses to `hidden` when empty AND has no in-window members. **Verification:** existing column rules at `app.css` `.columns-2 / .columns-3` are 2-3 column horizontal grids — the new band layers a sibling block below them in the same panel container, NOT a new column inside the existing grid.

- **D4. Persistence.** HYBRID. Completed = derived per-snapshot from GH `closedAt` + plan `completed:` frontmatter. Backlog = persistent in `monitor-state.json`. Bump state version to 1.2 at ALL FOUR write sites (server.py:314, 325, 332, 929) — `_read_state_file` is already tolerant of unknown keys and v1.0/v1.1 entry shapes (line 1280 docstring; lines 1313-1334 iterate `plans_raw.items()` and `issues_raw.items()` generically). **Hard-cut migration boundary** (per DA6): v1.2 client + v1.1 server (old server, new state file) yields 400s on every POST because `_validate_queue_body` rejects unknown columns (server.py:452-454, 478-480). Operators MUST restart the server after upgrading; AC2.5 codifies this. **Verification:** schema migration test asserts v1.1 (no `backlog` keys) reads cleanly and produces empty backlog arrays in the snapshot; v1.2 with `backlog` arrays round-trips through POST /api/queue.

- **D5. Drag-target affordances.** Mirror existing left/right semantics. Backlog supports drag IN (demote from active column) AND OUT (promote back to active). **Drag OUT destination rule:** the destination is REWRITTEN to the leftmost active column (Triage for issues, Drafted for plans) regardless of which active column the user happens to drop on. Rationale: this is symmetric with how Backlog is conceptually "off the active flow" — promoting just means "make it active again," and rewrite-to-leftmost avoids forcing the user to remember column order. Completed is READ-ONLY — no `draggable=true`, no claim chip, no per-card move action buttons, no remove-from-queue ✕. Click-through to the GH issue (issues) or plan file path (plans, link to repo file) still works. Move-all chevrons (PR #617): NOT on Completed; OK on Backlog. **Verification:** grep `handleAction` in app.js — verify `movePlan`/`moveIssue` use COLUMNS array indexing so adding a new column entry extends the move-range without new action names.

- **D6. Performance.** Use a SEPARATE bounded fetch for closed issues instead of widening to `--state all`. **Two-knob design rationale (DA3.5):** the configuration exposes `dashboard_completed_days` AND `dashboard_completed_limit` as INDEPENDENT knobs (not a single derived value) because the two cost-axes are orthogonal — `days` controls the GH `search` window (server-side filter; cheap to widen for low-traffic repos), and `limit` controls the response-payload ceiling (caps wire transfer + render cost regardless of window). A consumer with a high-velocity repo can keep a tight 14-day window but raise `limit` to 1000+ to avoid truncation; a low-velocity consumer can widen `days` to 90 while keeping `limit` at 500 without paying for an over-large response. Collapsing into a single knob would either silently truncate high-velocity repos (current default 500 hits the cap, as DA2.1's empirical anchor demonstrates) or over-fetch on low-velocity repos. Active issues: keep existing `gh issue list --state open --limit 500` (collect.py:1172-1175). Completed issues: add `gh issue list --state closed --search "closed:>=YYYY-MM-DD" --limit $LIMIT`, where the date is `now - dashboard_completed_days` and `$LIMIT` defaults to **500** (configurable via `execution.dashboard_completed_limit`). Two GH calls (bounded, parallelizable in a future optimization) instead of one 740KB+ widened call; cold-start p95 < 2s (vs. measured 906ms for --state all --limit 1000 on slow networks → 3-5s — empirical anchor from DA2). **Limit empirically anchored 2026-05-22:** `gh issue list --state closed --search "closed:>=2026-05-08" --limit 200 | wc` returned 150 issues over a 14-day window in this very repo — the original 100-limit would have silently truncated 50 closed issues. 500 leaves comfortable headroom for busier weeks; consumers with heavier traffic raise the config field. **Truncation signal:** when the fetched closed-issue count `== limit`, set `snapshot.flags.closed_issues_truncated: true` AND `snapshot.flags.closed_issues_limit: <resolved limit>` (the actual integer value) so the dashboard can render a banner that quotes the live value (per DA3.4 — banner shows `"Showing 500 most-recent…"`, not `"Showing N most-recent…"`). Retain `issues_fetch_ok` prune-guard semantics — on either fetch's failure, that fetch's column-set retains prior state. **Live-issue-numbers rule** (R2 resolution): the client-side prune-guard at `app.js:444` (`if (issuesFetchOk && !liveIssueNumbers.has(num)) continue;`) builds `liveIssueNumbers` from ALL fetched issues (both the open call and the bounded-closed call). Backlog entries referencing a closed-out-of-window issue would prune unless the closed fetch covers them — which it does within the configured window. Entries older than the window are an acceptable edge case: they prune from Backlog the same way `pendingPosts > 0` already gates against the prune (live-set stale handling). **Cross-cache race** (DA2.5): the open-fetch and the bounded-closed-fetch have independent 60s TTL caches. An issue closed between an open-fetch cache hit and the closed-fetch call can briefly appear in NEITHER list, causing a one-cycle dropout. This is acceptable noise — documented as "live-set stale handling" with at most 60s convergence latency. **Verification:** read `list_issues` at `collect.py:1138-1244` — confirm the cache key + `issues_fetch_ok` return shape allow a second sibling call without altering the wider contract.

- **D7. Composition with PR #617 (move-all), PR #600 (claim aria-disabled), PR #622 (claim-chip parity).** New columns MUST: (a) NOT receive move-all chevrons on Completed (terminal state); (b) honor `aria-disabled` claim invariant by NOT rendering claim chips on Completed cards (a completed item is released by definition); (c) update the `deepCloneQueues` allocator at `app.js:396-404` and the `fingerprintPlans` / `fingerprintIssues` functions (lines 459, 487) to enumerate the new columns — exactly the path that broke in #355 and was fixed by PR #361. **All drag-induced POSTs MUST flow through the existing `postQueue(...)` helper at app.js:1294** (the `pendingPosts` race-guard lives there at line 1353-1358); conformance regression at AC4.8 asserts `grep -cE "fetch\([^)]*api/queue" app.js == 1` post-edit (anchored on the `fetch(` call-syntax, not a substring — survives comments / JSDoc / error strings mentioning the path). **Verification:** grep `aria-disabled\|claim-chip` in app.js to confirm chip emission goes through `buildIssueCard` (line 905-996) and `buildPlanCard`; a per-card guard on `data-column === "completed"` suffices to suppress.

- **D8. Migration shock + downstream consumer awareness.** Flipping `_infer_default_column` migrates ALL `status: complete` plans into the new Completed view on the next snapshot. This repo has 1; downstream consumers may have 50+. The 14-day window naturally bounds visible churn after the migration completes (out-of-window plans drop off), but the FIRST snapshot post-upgrade will show all in-window completes plus the backfill from W1.5b. PR body documents this for operators. (`landedPillClass` opportunistic close is out of scope — see Overview's "Out of scope.")

## What this plan does NOT do

- Does NOT introduce new top-level skills — extends existing `zskills-dashboard`.
- Does NOT close issue #618 — `landedPillClass` audit + extension to the canonical 11-status set is filed as a follow-up issue. The opportunistic close in earlier drafts was based on a fabricated status set (`pr-open`, `pr-merged`, `pr-closed`, `cherry-picked` have ZERO matches in the codebase; canonical set per `briefing/SKILL.md:231-234` + `fix-report/SKILL.md:161` is `full, partial, landed, pr-ready, pr-ci-failing, pr-failed, conflict, pr-state-unknown, failed, direct-push-failed, direct-verify-failed`).
- Does NOT reimplement column-rendering machinery — extends the existing `PLAN_COLUMNS` / `ISSUE_COLUMNS` whitelists in four synchronized places (collect.py, server.py, app.js constants, app.js `deepCloneQueues`).
- Does NOT introduce a "tabs" UI for switching between active/completed (rejected D3 option — collapses at-a-glance view).
- Does NOT auto-archive Completed cards beyond the configured window — out-of-window items simply drop off the panel; manual archival is out of scope.
- Does NOT add GH-label-based backlog (rejected D2 option — requires manual discipline the project doesn't practice).
- Does NOT alter the existing `issues_fetch_ok` prune-guard contract — the new closed-issue fetch's prune-guard rides the existing flag semantics.
- Does NOT extend any column outside the dashboard panels (no Tracking, Worktrees, Branches, or Activity changes).
- Does NOT persist Completed-band collapse state in localStorage (per DA7 resolution — pure count-derived collapse keeps the persistence surface minimal). Backlog never collapses.

## Acceptance Criteria (plan-level)

- **A1.** Closed GH issues within last `dashboard_completed_days` (default 14) appear in the new Completed band beneath the Issues panel. Verification: synthesize a fixture `monitor-state.json` + mock `gh issue list --state closed --search ...` response with one issue closed 7 days ago and one closed 30 days ago; assert the 7-day issue renders in Completed and the 30-day issue is omitted.
- **A2.** Plans with `status: complete` AND `completed:` frontmatter within last 14 days appear in the new Completed band beneath the Plans panel. Verification: fixture plan with `status: complete` + `completed: 2026-05-15T12:30:00Z` renders in Completed when "today" is 2026-05-22; fixture plan with `completed: 2026-05-01T00:00:00Z` does not. Historical plans without a `completed:` field are backfilled by W1.5b before this assertion is run. Plan files live under `$ZSKILLS_PLANS_DIR` (resolved from `output.plans_dir` in `.claude/zskills-config.json` via `zskills-paths.sh`; defaults to `docs/plans` in this repo) — NOT a hardcoded `plans/`.
- **A3.** Backlog membership is persistent across server restarts (lives in `monitor-state.json/{issues,plans}.backlog`). Verification: integration test writes a backlog entry via POST `/api/queue`, restarts the server, GETs `/api/state`, asserts the entry is present.
- **A4.** Drag Triage → Backlog moves the issue persistently; drag Backlog → Triage promotes it. Verification: `playwright-cli` interactive test simulates a real mouse drag from Triage to Backlog, asserts the `/api/queue` POST body contains `issues.backlog: [N]`, then drags it back and asserts `issues.triage: [N]` and `issues.backlog: []`. Drag from Backlog onto any active column rewrites the destination to the LEFTMOST active column (Triage for issues, Drafted for plans).
- **A5.** Completed cards are READ-ONLY — no `draggable`, no claim chip, no per-card action buttons, no remove ✕. Click-through to the GH issue (issues) or plan file path (plans) still works. Verification: DOM assertion — every `[data-column="completed"]` card has no `draggable="true"` attribute AND no `.claim-chip` element AND no `[data-action^="issue-"]` or `[data-action^="plan-"]` button.
- **A6.** Move-all chevrons (PR #617) do NOT appear on Completed columns. Verification: DOM assertion — `[data-column="completed"] .move-all-group` selector returns 0 elements; the same selector against `[data-column="backlog"]` returns the expected chevrons.
- **A7.** State-file schema migrates v1.1 → v1.2 without data loss. Older state files without `.backlog` arrays default to empty backlog. ALL FOUR `"version": "1.1"` write sites in server.py are bumped to `"1.2"`. Verification: unit test in `tests/test_zskills_monitor_collect.sh` parses a v1.1 fixture (no `backlog` keys), asserts `state.issues.backlog == []` and `state.plans.backlog == []`. Server-side test asserts POST → file-write → re-read yields `version == "1.2"` AND `grep -c '"version": "1.1"' server.py == 0`.
- **A8.** [Removed — #618 opportunistic close moved out of scope. Follow-up issue filed.]
- **A9.** All four `PLAN_COLUMNS` / `ISSUE_COLUMNS` literal sites are synchronized. Verification: section-scoped conformance grep in `tests/test-skill-conformance.sh` matches the FULL TUPLE ORDERING via symbol-pattern (e.g., `PLAN_COLUMNS *= *[(\[]"drafted", *"reviewed", *"ready", *"backlog"`). Sites covered: `server.py` (`PLAN_COLUMNS`, `ISSUE_COLUMNS`), `app.js` constant declarations (`const PLAN_COLUMNS = ...`, `const ISSUE_COLUMNS = ...`), and the `deepCloneQueues` allocator (which references the constants — anchored on `for (const c of PLAN_COLUMNS)` symbol). `collect.py` is iterative — see W5.1 comment-marker.
- **A10.** Full test suite (`bash tests/run-all.sh`) passes with `Overall: N/M passed, 0 failed` and per-skill pass-count matches baseline + the new tests added by this plan. Verification: run on a clean working tree, capture to `$TEST_OUT/.test-results.txt`, diff pass-count against pre-plan baseline.

## Progress Tracker

| Phase | Status | Name |
|---|---|---|
| 1 | ✅ | Backend — `collect.py` + `monitor-state.json` schema v1.2 (`75fa6e2`) |
| 2 | ✅ | Server — `PLAN_COLUMNS` / `ISSUE_COLUMNS` extension + version writers + validator (`d90d285`) |
| 3 | ✅ | Frontend — rendering + below-panel band layout (`894926c`) |
| 4 | ✅ | Drag-target wiring + Completed read-only semantics (`852dcb9`) |
| 5 | ⬚ | Integration, conformance, end-to-end verification |

---

## Phase 1 — Backend (`collect.py` + state schema v1.2)

### Goal

Surface Completed plans and issues in the snapshot returned by `collect_snapshot`, add persistent `backlog` arrays to the state-file shape (v1.2), and fix the `_infer_default_column` `complete → None` bug at its inference site. Symmetric fix on the issue side (no completed-inference today). Mandatory plan-frontmatter `completed:` field with historical backfill. No frontend changes in this phase; the new fields appear in `/api/state` JSON but are not yet rendered.

### Work Items

- **W1.1** — Add a SEPARATE bounded closed-issue fetch sibling to `list_issues` (collect.py:1138-1244). Keep the existing `--state open --limit 500` call unchanged. Add `list_closed_issues_in_window(days)` that runs `gh issue list --state closed --search "closed:>=YYYY-MM-DD" --limit 100` where the date is `now - days` (UTC). Return shape: `(closed_issues, ok)` mirroring the open-fetch contract. Each issue dict carries `closed_at` extracted from `entry.get("closedAt", "")`. The 60s TTL cache is per-call (separate cache key). On failure, `ok=False` → caller retains prior state for the closed column only (open column independent). `liveIssueNumbers` on the client (app.js:434-437) builds from BOTH fetches' results merged.
- **W1.2** — Add windowed completed-inference for plans in `_infer_default_column` (collect.py:1251-1268). New signature: `_infer_default_column(plan, *, now_utc, window_days)`. Replace the `if status in ("complete","landed"): return None` branch with: read the plan's `completed:` frontmatter field (ISO-8601 string); if within `window_days` of `now_utc`, return `"completed"`; if absent or outside window, return `None` (still hidden — historical completes drop off after backfill ages out).
- **W1.2b** — Add new function `_infer_issue_default_column(issue, *, now_utc, window_days)` that returns `"completed"` when `closedAt` is set AND within window, else `"triage"`. Wire into `_annotate_issues_queue` at the fallback path (collect.py:1423-1424 area, replacing the unconditional `{"column": "triage", "index": -1}` default with a call to the new inference function).
- **W1.3** — Extend `_annotate_plans_queue` (collect.py:1345-1366) and `_annotate_issues_queue` (collect.py:1369-1424) so the new `completed` and `backlog` columns populate from BOTH (a) state-file explicit positions (for `backlog`) and (b) inferred positions (for `completed` derived from `closedAt` / `completed:` frontmatter via W1.2 / W1.2b). **Precedence rules:** (i) State-file explicit-position WINS over inference (a plan in backlog stays in backlog even if `status: complete`; tested by W1.20). (ii) **Dedupe-prefer-closed (DA3.7):** if the same issue # is encountered in BOTH the open-fetch result list AND the closed-fetch result list (possible via the cross-cache race documented in D6 — open-fetch cache served a stale record before the issue was closed), the issue is rendered ONCE in the `completed` column, never duplicated. Implementation: when building the merged live-set inside `_annotate_issues_queue`, iterate the closed-fetch list AFTER the open-fetch list so the closed-side annotation overwrites the open-side annotation for any shared keys; tested by W1.19. The plan-side has no analogous derived-vs-derived race because plan `completed:` frontmatter is a single source of truth (no separate "closed" fetch); plan precedence is fully covered by rule (i).
- **W1.4** — Bump state-file schema version to 1.2 in `_read_state_file` (collect.py:1276-1342). The existing tolerant-iteration shape at lines 1313-1334 already accepts unknown column names, so v1.1 files without `backlog` keys still parse — assert this in a migration test rather than adding new branching. (Server.py write-side bumps live in Phase 2 / W2.X.)
- **W1.5** — **Mandatory** `completed:` frontmatter write in `/run-plan` Phase 5b. Read `skills/run-plan/SKILL.md` Phase 5b status-write site; on transition to `status: complete`, also write the **full ISO-8601 UTC datetime** (`completed: 2026-05-22T12:30:00Z`) — matching GH's `closedAt` format so cross-source date comparison is uniform. Implementation: `completed_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"` (NOT `date -I` or `cut -c1-10` — those produce date-only strings which mix poorly with full-datetime values from W1.5b and from GH `closedAt`). Use `bash scripts/frontmatter-set.sh <plan>.md completed "$completed_ts"` — the canonical writer. The plan-file path is `$ZSKILLS_PLANS_DIR/<slug>.md` (resolved via `zskills-paths.sh`) — NEVER hardcoded `plans/<slug>.md`.
- **W1.5b** — **Historical backfill.** New script: `skills/zskills-dashboard/scripts/backfill-plan-completed.sh`. For every plan with `status: complete` AND no `completed:` field, query the **content-pickaxe** `git log -G"^status:[[:space:]]*complete$" --follow --reverse --format=%cI -- "$ZSKILLS_PLANS_DIR/<slug>.md" | tail -1` to obtain the most-recent commit that introduced `status: complete` (using `--follow` to handle renames, `%cI` committer-date to match when main saw the state, and `tail -1` so a `complete → active → complete` re-upgrade picks the most-recent introduction — matches user mental model). **UTC normalization (DA3.1):** `%cI` returns the COMMITTER'S LOCAL TZ-offset (e.g. `2026-05-21T22:01:14-04:00`), NOT UTC `Z`. Empirically verified 2026-05-22: same `git log` invocation returns mixed `Z` and `-04:00` offsets in this repo. The captured timestamp MUST be normalized through `date -u -d "$raw_ts" +%Y-%m-%dT%H:%M:%SZ` before writing — yielding the canonical `YYYY-MM-DDTHH:MM:SSZ` form that W1.5 also emits and that GH `closedAt` uses. Without this step, downstream date-math is correct (UTC offsets are valid ISO-8601), but the on-disk format diverges from W1.5's emitted form, defeating the uniformity claim in D1. Pin via test W1.15b. Write the normalized ISO-UTC timestamp into the `completed:` field via `scripts/frontmatter-set.sh`. **DO NOT use `git log --diff-filter=AM`** — that returns the file-creation commit, not the status-introduction commit (verified empirically 2026-05-22). **DO NOT widen pickaxe regex too aggressively (DA3.3):** the canonical writers in `/run-plan` Phase 5b emit `status: complete` (unquoted, no trailing whitespace) — `-G"^status:[[:space:]]*complete$"` matches that form. If the pickaxe returns empty for a plan that genuinely has `status: complete` (rare — only if a human author quoted the value or added trailing whitespace), the script logs `WARN: pickaxe returned no commits for <slug>: completed-field cannot be backfilled; please set manually via 'bash scripts/frontmatter-set.sh <plan> completed <ISO-UTC>'` and continues with the next plan. The empty-pickaxe path is NOT silently skipped — the WARN makes the case inspectable; the final summary reports `N plans skipped due to empty pickaxe (manual fix required)`. The plans-dir MUST resolve from `$ZSKILLS_PLANS_DIR` (sourced via `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"` at the top of the script) — hardcoding `plans/` ships the wrong path to every downstream consumer (this repo: `docs/plans/`). The script MUST also `cd` to the git toplevel before running (DA3.2): the first line after `set -euo pipefail` is `cd "$(git rev-parse --show-toplevel)" || { echo "ERROR: not in a git repo" >&2; exit 1; }`, AND it precheck-asserts `[ -f .claude/zskills-config.json ] || { echo "ERROR: must run from a zskills-configured repo (no .claude/zskills-config.json at git toplevel)" >&2; exit 1; }` so CWD-ambiguity never bites. **Error handling for `frontmatter-set.sh` exit 3** (block-scalar overwrite refusal): log `WARN: skipping <slug>: frontmatter-set.sh refused block-scalar overwrite (exit 3)`, continue with next plan, and emit a final summary `N plans skipped due to block-scalar refusals (manual fix required)`; the operator handles those files by hand. **Recovery from a buggy prior backfill (DA3.6):** if an earlier (broken) run of this script wrote an INCORRECT `completed:` value, the script's idempotency guard (presence of `completed:` field) prevents re-write. Manual escape hatch: operators must first clear the bad value via `bash scripts/frontmatter-set.sh <plan>.md completed ''` (empty string clears the field), then re-run the backfill script. Document this in the script's `--help` text and in the PR body's "Operator notes" section. Run once before merging; idempotent (re-runs are no-ops because the field already exists). Add explicit AC: backfill leaves working tree dirty only with `completed:` field additions (no other diffs).
- **W1.5c** — Bump `skills/run-plan/SKILL.md metadata.version` (mandatory per CLAUDE.md skill-versioning, because W1.5 edits Phase 5b prose/logic).
- **W1.6** — Add new config fields `execution.dashboard_completed_days` (default 14) AND `execution.dashboard_completed_limit` (default **500**, per DA2.1 empirical anchor — this repo had 150 closed issues in a 14-day window, the original 100 silently truncated 50). Thread BOTH through to `collect_snapshot` via the existing config-read path. End-to-end signature plumbing: `collect_snapshot(...)` reads both config fields, passes `window_days` to `_annotate_plans_queue(..., now_utc=..., window_days=...)`, `_annotate_issues_queue(..., now_utc=..., window_days=...)`, which in turn pass it to `_infer_default_column(..., now_utc=..., window_days=...)` / `_infer_issue_default_column(..., now_utc=..., window_days=...)`, and passes `closed_limit` to `list_closed_issues_in_window(days=window_days, limit=closed_limit)`. **Truncation signal:** when `len(closed_issues) == closed_limit`, `collect_snapshot` sets `snapshot["flags"]["closed_issues_truncated"] = True` AND `snapshot["flags"]["closed_issues_limit"] = closed_limit` (the actual integer) so the renderer can banner the operator with the live value (per DA3.4). Resolver updates are split: `execution.dashboard_completed_days` is a thin integer field that fits the existing BASH_REMATCH resolver in `zskills-resolve-config.sh`; `execution.dashboard_completed_limit` likewise. Both are also accessible to Python via stdlib `json` (the `collect.py` config-read path).
- **W1.7** — Bump `skills/zskills-dashboard/SKILL.md metadata.version` (mandatory per CLAUDE.md skill-versioning).
- **W1.8** — Write test: extend `tests/test_zskills_monitor_collect.sh` with `list_closed_issues_in_window_bounded_by_date` case (mock subprocess runner returns 5 closed issues with varied dates; assert only the in-window ones come back).
- **W1.9** — Write test: extend `tests/test_zskills_monitor_collect.sh` with `infer_default_column_completed_within_window` and `infer_default_column_completed_outside_window` and `infer_issue_default_column_completed_within_window` cases.
- **W1.10** — Write test: extend `tests/test_zskills_monitor_collect.sh` with `read_state_file_v11_migration` case (v1.1 fixture parses cleanly, `backlog` defaults to `[]`).
- **W1.11** — Write test: extend `tests/test_zskills_monitor_collect.sh` with `annotate_issues_queue_assigns_completed` case (a closed-within-window issue not present in state-file lands in `completed` column).
- **W1.12** — Write test: end-to-end config plumbing — `config_dashboard_completed_days_flows_to_inference` case asserts that setting `execution.dashboard_completed_days: 7` in a fixture config narrows the Completed window to 7 days in the rendered snapshot.
- **W1.13** — Write test: `backfill_plan_completed_idempotent` case for the new W1.5b script (run twice, assert second run is a no-op).
- **W1.14** — Write test: `backfill_plan_completed_resolves_plans_dir_from_config` — fixture config with `output.plans_dir: "docs/plans"`, fixture plan at `docs/plans/<slug>.md` (NOT `plans/<slug>.md`); assert the backfill script writes the `completed:` field to the docs/plans-rooted file and NOT to a phantom `plans/` location. Anchor against the antipattern with a conformance grep: `grep -nE '"plans/" *<slug>|plans/\$slug|plans/\\\$slug' skills/zskills-dashboard/scripts/backfill-plan-completed.sh` MUST return zero matches.
- **W1.15** — Write test: `backfill_plan_completed_rename_survives` — create plan A under one name, commit `status: complete`, rename to B in a later commit; assert backfill (with `--follow`) finds the original status-introduction commit.
- **W1.15b** — Write test: `backfill_plan_completed_normalizes_local_tz_to_utc_z` — seed a fixture commit with `GIT_COMMITTER_DATE='2026-05-15T08:30:00-04:00' GIT_AUTHOR_DATE='2026-05-15T08:30:00-04:00'` that introduces `status: complete` on a fixture plan; run the backfill script; assert the resulting `completed:` field reads exactly `2026-05-15T12:30:00Z` (NOT `2026-05-15T08:30:00-04:00`). Pins DA3.1 — empirically verified that `git log --format=%cI` returns committer-local-TZ offset (mixed `Z` and `-04:00` in this repo) so the script's `date -u -d "$raw" +%Y-%m-%dT%H:%M:%SZ` normalization step is load-bearing.
- **W1.16** — Write test: `backfill_plan_completed_reupgrade_takes_latest` — plan transitions `active → complete → active → complete`; assert backfill picks the SECOND (most-recent) `status: complete` introduction (`tail -1`).
- **W1.17** — Write test: `backfill_plan_completed_handles_block_scalar_exit3` — fixture plan with frontmatter `completed:` already present as a block scalar (`completed: |`); assert backfill logs WARN, exits 0, and the summary count reflects the skip.
- **W1.18** — Write test: `backfill_plan_completed_cwd_precheck` — invoke the backfill script from a directory that is NOT inside a zskills-configured repo (e.g. `/tmp/empty-dir`); assert the script exits non-zero with the "must run from a zskills-configured repo" message. Then invoke from a subdirectory of a configured repo; assert the `cd "$(git rev-parse --show-toplevel)"` step recovers and the run succeeds. Pins DA3.2.
- **W1.19** — Write test: `annotate_issues_queue_prefers_closed_on_dual_membership` — fixture: an issue #N appears in BOTH the open-fetch result (e.g. cache race — the open-fetch cache hit returned a stale record before the issue was closed) AND the closed-fetch result; assert the snapshot lands the issue in `completed` (NOT in `triage`/`ready`). Pins DA3.7's dedupe-prefer-closed rule, ensuring cross-cache races never double-render.
- **W1.20** — Write test: `annotate_plans_queue_prefers_completed_on_dual_membership` — fixture plan appears in state-file's `drafted` column AND has `status: complete` + recent `completed:` field; per D2 ("state-file explicit-position WINS over inference"), assert the plan renders in `drafted` (NOT `completed`). This is the SYMMETRIC counter-test to W1.19 — it confirms that the explicit-state precedence rule from D2 applies to plans, while the cache-race dedupe in W1.19 is a closed-prefers-closed tiebreaker specifically for the issue-side derived-vs-derived case.

### Design & Constraints

- "Surface bugs don't patch" — fix `_infer_default_column` AND add `_infer_issue_default_column` at the inference sites, NOT by post-filtering at render. This is the canonical example the CLAUDE.md rule cites.
- Python stdlib `json` only; no jq.
- **Plans-dir resolution rule** (DA2.2): all references to the plans directory (in W1.5, W1.5b, the new backfill script, frontmatter writes, click-through paths, and tests) MUST source `$ZSKILLS_PLANS_DIR` from `$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh` (or, in Python contexts, read `output.plans_dir` from `.claude/zskills-config.json`). Hardcoding `plans/` is FORBIDDEN — this repo's config sets `output.plans_dir: "docs/plans"`, so a hardcoded `plans/` would silently target the wrong directory. Conformance grep at W1.14 anchors the antipattern.
- **Date format uniformity** (DA2.4): the `completed:` frontmatter field is **full ISO-8601 UTC datetime** (`YYYY-MM-DDTHH:MM:SSZ`) at BOTH write sites (W1.5 new-completion write AND W1.5b historical backfill). GH `closedAt` is also full ISO-8601. The Python date-math path normalizes both to `datetime.fromisoformat`-parsed UTC-aware datetimes BEFORE comparison. `datetime.fromisoformat` will parse date-only strings too — so the code MUST defensively normalize legacy date-only values (e.g., from earlier drafts) by appending `T00:00:00Z` before comparison, OR by branching on string length. Pick one in implementation; pin in tests.
- Date math uses `datetime.fromisoformat` on the `closedAt` / `completed:` ISO-8601 string and compares against `now_utc - timedelta(days=window_days)`. No third-party date library.
- The `issues_fetch_ok` contract (collect.py:1149-1158) MUST remain unchanged — its return shape `(issues, ok)` is the contract the client-side prune-guard depends on. The new sibling `list_closed_issues_in_window` returns the same shape independently.
- **Cross-cache race** (DA2.5): the open-fetch and the bounded-closed-fetch are independently cached at 60s TTL. An issue closed between an open-fetch cache hit and a closed-fetch call may briefly appear in NEITHER list — a one-snapshot dropout with at most 60s convergence latency. Documented as "live-set stale handling"; no code defense added (cost > benefit).
- **Truncation signal** (DA2.7 + DA3.4): when `len(closed_issues_returned) == dashboard_completed_limit`, `collect_snapshot` sets `snapshot["flags"]["closed_issues_truncated"] = True` AND `snapshot["flags"]["closed_issues_limit"] = <resolved limit>` (the live integer, so the banner can quote the actual value, not a placeholder). The frontend (Phase 3 work) reads both flags to render a banner that interpolates the live limit; absent the truncated flag (or `false`) → no banner.
- File-mtime fallback for plan completion date is REJECTED (DA3) — `completed:` frontmatter is mandatory; W1.5b backfills history.
- No working-tree-modifying test pattern (no `git stash` / `git checkout` for pre-existing-check).

### Tests

- `tests/test_zskills_monitor_collect.sh` — extended with W1.8, W1.9, W1.10, W1.11, W1.12, W1.13, W1.14, W1.15, W1.15b, W1.16, W1.17, W1.18, W1.19, W1.20 cases (14 new test cases).
- All new cases use the existing `_runner` / `_now` injection seams in `list_issues` — no subprocess hits on the test path.
- Capture output to `/tmp/zskills-tests/$(basename $(pwd))/.test-results.txt` per CLAUDE.md.
- Pass-count gating: assert the suite's `Overall: N/M passed` count grew by exactly 14 from this phase's baseline (Phase 1 deltas only; total deltas roll up in Phase 5).

### Acceptance Criteria (Phase 1)

- **AC1.1** — `_infer_default_column({status: "complete", completed: "<7 days ago>T00:00:00Z"}, now_utc=..., window_days=14) == "completed"`. **AC1.2** — `_infer_default_column({status: "complete", completed: "<30 days ago>T00:00:00Z"}, ..., window_days=14) is None`. **AC1.3** — `list_closed_issues_in_window(days=14, limit=500)` returns only issues with `closedAt` within 14 days, with `closed_at` populated. **AC1.4** — `_read_state_file` parses a v1.1 fixture without errors and yields empty `backlog` arrays. **AC1.5** — `collect_snapshot` JSON includes plans with `queue.column == "completed"` and issues with `queue.column == "completed"` and `queue.column == "backlog"` where state-file specifies. **AC1.6** — `skills/zskills-dashboard/SKILL.md metadata.version` AND `skills/run-plan/SKILL.md metadata.version` bumped this phase. **AC1.7** — Cold-fetch p95 (open + closed-in-window) < 2s (single sample on local fixture; full benchmark not required); payload size of `/api/state` snapshot < 200KB on a 14-day window with this repo's issue volume (empirical anchor for future regression). **AC1.8** — `backfill-plan-completed.sh` reads `output.plans_dir` from config (via `zskills-paths.sh` source), writes `completed:` fields under `$ZSKILLS_PLANS_DIR/<slug>.md` (this repo: `docs/plans/`), and contains zero hardcoded `plans/` literals (conformance grep). **AC1.9** — `backfill-plan-completed.sh` uses `git log -G"^status:[[:space:]]*complete$" --follow --reverse --format=%cI -- <plan> | tail -1` for date extraction (NOT `--diff-filter=AM`; conformance grep `grep -n -- "--diff-filter=AM" skills/zskills-dashboard/scripts/backfill-plan-completed.sh` returns zero matches). **AC1.10** — `snapshot["flags"]["closed_issues_truncated"]` is `true` when `len(closed_issues) == dashboard_completed_limit`, else `false` (or absent).

### Dependencies

- None (foundational phase). Subsequent phases depend on this.

---

## Phase 2 — Server validator + version writers (`server.py`)

### Goal

Extend the `PLAN_COLUMNS` and `ISSUE_COLUMNS` tuples in `server.py:74-75` so the `/api/queue` POST validator accepts `backlog` entries. Insert an explicit pre-loop reject for `completed` column writes (Completed is read-only on the API surface — derived per-snapshot, never persisted). Bump ALL FOUR hardcoded `"version": "1.1"` literals to `"1.2"`.

### Work Items

- **W2.1** — Extend `PLAN_COLUMNS = ("drafted", "reviewed", "ready", "backlog")` and `ISSUE_COLUMNS = ("triage", "ready", "backlog")` in `server.py:74-75`. Note: `completed` is NOT in either tuple — see W2.2.
- **W2.2** — Update `_validate_queue_body` (server.py:435-492). Insert an EXPLICIT pre-loop check BEFORE the generic `for col in plans.keys(): if col not in PLAN_COLUMNS: return f"unexpected plans column: ..."` (currently server.py:452-454). New code: `if "completed" in plans: return "completed column is read-only on the API; cannot accept POSTs (derived per-snapshot from plan frontmatter completed: field)"` and the analogous block for issues at server.py:478-480. The existing generic-unknown-column path keeps catching everything else.
- **W2.3** — Bump ALL FOUR `"version": "1.1"` write sites in server.py to `"1.2"`. Sites: line 314 (path-not-file bootstrap), line 325 (JSON-decode-error bootstrap), line 332 (not-dict bootstrap), line 929 (`_handle_queue_post` write-side). Add startup log line that records the column tuples at boot: `log.info("PLAN_COLUMNS=%s ISSUE_COLUMNS=%s state_version=1.2", PLAN_COLUMNS, ISSUE_COLUMNS)` so operators can diagnose the v1.1↔v1.2 hard-cut migration boundary at-a-glance.
- **W2.4** — Confirm `_handle_queue_post` (server.py:906) atomic-write path correctly serializes the new `backlog` arrays. No code change expected — the path is column-tuple-driven; assert this in the new tests.
- **W2.5** — Bump `skills/zskills-dashboard/SKILL.md metadata.version`.
- **W2.6** — Write test: extend `tests/test_zskills_monitor_server.sh` with `validate_queue_body_accepts_backlog` (POST with `issues.backlog: [123]` returns None error).
- **W2.7** — Write test: extend `tests/test_zskills_monitor_server.sh` with `validate_queue_body_rejects_completed_in_post` (POST with `plans.completed: [{slug: "x"}]` returns the specific read-only message; POST with `issues.completed: [123]` returns the analogous message). Assert the error string contains `"completed column is read-only"`.
- **W2.8** — Write test: extend `tests/test_zskills_monitor_server.sh` with `queue_post_roundtrip_backlog` (POST a backlog entry, GET /api/state, assert it's present AND the persisted state file's `"version"` field is `"1.2"`).
- **W2.9** — Write test: extend `tests/test_zskills_monitor_server.sh` with `state_file_version_bumped_all_sites` (assert `grep -c '"version": "1.1"' server.py == 0` AND `grep -c '"version": "1.2"' server.py >= 4`).

### Design & Constraints

- The validator is the security boundary — never relax it; only extend with explicit accept cases.
- `completed` rejection check must be EXPLICIT (per W2.2) — placed BEFORE the generic loop so the message is specific. Past failure pattern: generic error messages make client bugs hard to find without a stack-trace.
- No new top-level keys in the POST body shape (validator's `allowed_top` set at line 441 stays unchanged).
- Hard-cut migration boundary (DA6): v1.2 client + v1.1 server (old server, new state file) gets 400s on every POST. Operators MUST restart the server after upgrading; the startup log line at W2.3 makes the boundary inspectable.

### Tests

- `tests/test_zskills_monitor_server.sh` — extended with W2.6, W2.7, W2.8, W2.9 (4 new test cases).
- Existing `validate_queue_body_rejects_unknown_column` test must continue to pass (and a clarifying assertion that the message for `completed` differs from generic unknown-column message).

### Acceptance Criteria (Phase 2)

- **AC2.1** — POST `/api/queue` with `issues.backlog: [42]` returns 200 + the entry is persisted in `monitor-state.json`. **AC2.2** — POST `/api/queue` with `plans.completed: [{slug: "x"}]` returns 400 with the specific read-only message (containing `"completed column is read-only"`). **AC2.3** — Pre-existing validator tests still pass. **AC2.4** — `skills/zskills-dashboard/SKILL.md metadata.version` bumped this phase. **AC2.5** — `monitor-state.json` written by this server has `"version": "1.2"`. An old-version server (PLAN_COLUMNS without `backlog`) rejects v1.2 POSTs with 400 + clear error — operators must restart the server after upgrading (documented in PR body; startup log line at W2.3 makes the boundary inspectable at boot).

### Dependencies

- Phase 1 (server's validator changes don't require collect.py to land first, but Phase 2's tests assert against state-file behavior wired in Phase 1).

---

## Phase 3 — Frontend rendering + below-panel band layout

### Goal

Render the new Completed and Backlog sub-columns in two new "below-panel" bands (one beneath the Plans panel, one beneath the Issues panel). Wire the column constants, allocators, and fingerprint functions in `app.js` so the snapshot data flows through to the DOM. Implement the count-derived collapse rule (no localStorage). (Issue #618 / `landedPillClass` audit is OUT OF SCOPE — see Overview.)

### Work Items

- **W3.1** — Extend `PLAN_COLUMNS = ["drafted", "reviewed", "ready", "backlog", "completed"]` and `ISSUE_COLUMNS = ["triage", "ready", "backlog", "completed"]` at `app.js:26-27`. Extend `PLAN_COLUMN_LABELS` and `ISSUE_COLUMN_LABELS` at lines 31-39 with the new labels.
- **W3.2** — Update `deepCloneQueues` (app.js:396-404) so the new columns are pre-populated in the output. The existing `for (const c of PLAN_COLUMNS) out.plans[c] = []` pattern at lines 403-404 mechanically picks up the extended tuples — but a regression test asserts this so the #355 / PR #361 failure mode cannot recur silently. Verify `liveIssueNumbers` (app.js:434-437) is built from the full live `issues` array (which now includes closed-in-window via the new W1.1 fetch sibling).
- **W3.3** — Extend `fingerprintPlans` (app.js:459-) and `fingerprintIssues` (app.js:487-) to include the new column membership in the fingerprint. Without this, drag-into-backlog won't trigger a re-render because the fingerprint will hash to the same value.
- **W3.4** — Add new below-panel-band markup in `renderPlans` (app.js:716-) and `renderIssues` (app.js:1006-). Each band is a sibling `<div class="below-panel-band">` containing two `<ul class="dropzone" data-kind="plan|issue" data-column="completed|backlog">` children + their column headers. The band is appended to the same panel container as the active row, immediately after the `.columns` element. **Markup is standalone**, NOT composed with `.columns-2` (per D3) — the band has its own 2-column grid styling.
- **W3.5** — Extend `app.css` with a new `.below-panel-band` layout primitive: a 2-column grid (`grid-template-columns: 1fr 1fr`) with a visual separator from the active row above (e.g., `border-top: 1px dashed var(--border)`). Add `.below-panel-band[hidden] { display: none; }` for the empty-Completed collapse. **Do NOT compose with `.columns-2`** — `.below-panel-band` is a sibling block-level container, not a column-grid item.
- **W3.6** — [Removed — #618 opportunistic close moved out of scope. Follow-up issue filed.]
- **W3.7** — Add count-derived collapse logic (no localStorage): the Completed sub-column collapses (parent band `hidden=true`) ONLY when BOTH the band's Completed AND Backlog sub-columns are empty. **Backlog ALWAYS renders as a visible drop-target** even when empty (a "Drag here to defer" placeholder fills the empty `<ul>`). This resolves R7's drop-target contradiction.
- **W3.7b** — Render the truncation banner (DA2.7 + DA3.4): when `snapshot.flags.closed_issues_truncated === true`, render a non-dismissable banner above the Issues panel's below-band. **The banner text MUST quote the ACTUAL VALUES from the snapshot**, not the field name in the abstract. Snapshot extension: `collect_snapshot` writes `snapshot.flags.closed_issues_limit = <resolved limit>` (the actual integer value used for the fetch, e.g. `500`) alongside `closed_issues_truncated`. Banner template: `` `Showing ${closed_issues_limit} most-recent closed issues — there are probably more. To see all, raise execution.dashboard_completed_limit (currently ${closed_issues_limit}) in .claude/zskills-config.json.` ``. Two interpolations both pull from `snapshot.flags.closed_issues_limit` so the operator sees the literal current value, not a placeholder. Banner classes are `.truncation-banner` + `.muted`; no localStorage; banner disappears on the next snapshot where the flag is absent/false. Test W3.12b asserts the rendered text contains the actual limit value (not the placeholder `${closed_issues_limit}` and not the field name `execution.dashboard_completed_limit` alone).
- **W3.8** — Bump `skills/zskills-dashboard/SKILL.md metadata.version`.
- **W3.9** — Write test: extend `tests/test_zskills_monitor_dashboard_ui.sh` with `renders_completed_band_below_issues_panel` (load fixture snapshot with 1 completed issue, assert `.below-panel-band [data-column="completed"]` contains 1 card).
- **W3.10** — Write test: extend `tests/test_zskills_monitor_dashboard_ui.sh` with `renders_backlog_band_below_plans_panel` (fixture with 1 backlog plan).
- **W3.11** — Write test: extend `tests/test_zskills_monitor_dashboard_ui.sh` with `below_panel_band_visible_when_backlog_empty_but_no_completed` — assert the band stays visible (no `hidden` attribute) when Backlog is empty but is still a drop-target.
- **W3.12** — Write test: extend `tests/test_zskills_monitor_dashboard_ui.sh` with `below_panel_band_collapse_when_both_empty` (snapshot with empty Completed AND empty Backlog → band element has `hidden` attribute).
- **W3.12b** — Write test: extend `tests/test_zskills_monitor_dashboard_ui.sh` with `truncation_banner_renders_with_actual_limit_value` (fixture snapshot with `flags.closed_issues_truncated: true` AND `flags.closed_issues_limit: 500` → `.truncation-banner` element present above the issues below-band AND its `textContent` contains the literal string `500` AND does NOT contain the unrendered placeholder `${closed_issues_limit}`; fixture without `truncated` flag → no banner). Pins DA3.4.
- **W3.13** — Manual playwright-cli verification per `feedback_css_visual_verification`: load `/`, screenshot, judge visually that the bands appear below the panels and are visually distinct from the active row. Include selector-match count + interactive verification.

### Design & Constraints

- UI changes need playwright-cli render-DOM + interactive verification — NOT just computed-style assertions (memory anchor `feedback_css_visual_verification`).
- The four `PLAN_COLUMNS` / `ISSUE_COLUMNS` literal sites MUST stay synchronized — collect.py uses iteration over the state-file dict so it picks up new columns mechanically; server.py and app.js have explicit tuples; `deepCloneQueues` reads the app.js tuple. Phase 5's conformance check enforces this with full-tuple-ordering matching.
- Below-panel-band markup must not break the `aria-disabled` claim-chip invariant (PR #600) — Completed cards get NO claim chip per D7.
- Snapshot-then-recheck idiom (PR #617) — move-all chevrons read the column count from the rendered DOM; new bands MUST NOT receive chevrons on the Completed sub-column.
- Backlog click-through target for plan cards: link to the plan file path in the repo (`$ZSKILLS_PLANS_DIR/<slug>.md`, resolved via `zskills-paths.sh`; this repo: `docs/plans/<slug>.md`), opening in a new tab. Completed plan cards are NON-clickable on the title (per DA10 resolution) — title is plain text, no anchor. Click-through to the GH issue for issue cards remains as today.

### Tests

- `tests/test_zskills_monitor_dashboard_ui.sh` — extended with W3.9, W3.10, W3.11, W3.12, W3.12b (5 new test cases).
- Manual playwright-cli end-to-end screenshot + visual judgment per W3.13.
- Capture output to `/tmp/zskills-tests/$(basename $(pwd))/.test-results.txt`.

### Acceptance Criteria (Phase 3)

- **AC3.1** — Loading `/` renders a `.below-panel-band` sibling beneath both the Plans and the Issues panel. **AC3.2** — Each band contains exactly 2 sub-columns labeled "Completed" and "Backlog". **AC3.3** — When BOTH sub-columns are empty, the band element has `hidden=true`. When only Completed is empty but Backlog has items (or vice versa), the band is visible and Backlog is a drop-target. **AC3.4** — [Removed — #618 opportunistic close moved out of scope.] **AC3.5** — Pre-existing renderPlans / renderIssues tests still pass (the active row is unchanged). **AC3.6** — `skills/zskills-dashboard/SKILL.md metadata.version` bumped this phase.

### Dependencies

- Phase 1 (snapshot must contain `queue.column == "completed"` and `queue.column == "backlog"` entries before the frontend can render them).
- Phase 2 (validator must accept `backlog` POST bodies before drag tests in Phase 4 can pass — but Phase 3's read-only render tests can pass without Phase 2).

---

## Phase 4 — Drag-target wiring + Completed read-only semantics

### Goal

Wire drag-and-drop into the new bands. Backlog supports drag IN (demote from any active column) and drag OUT (promoted to LEFTMOST active column — Triage for issues, Drafted for plans, regardless of which active column the user drops onto). Completed cards are read-only — no `draggable`, no claim chip, no per-card action buttons, no remove ✕, no move-all chevrons.

### Work Items

- **W4.1** — Update `buildIssueCard` (app.js:905-) and `buildPlanCard` (search for the analog): when the card's `data-column === "completed"`, omit the `draggable="true"` attribute, omit the claim-chip element, omit per-card action buttons (remove ✕, move arrows), and omit the move-all chevron entirely. Click-through anchor remains for issues (GH URL) and is omitted for plans (plain title text per D3 resolution / DA10).
- **W4.2** — Extend `handleAction` (app.js:1998-) movePlan/moveIssue arms — backlog is just a new column index in the COLUMNS array, so the existing `idx + 1` / `idx - 1` indexing extends mechanically. Add explicit drop-target dispatch in `onDrop` (app.js:1696-) so `data-column="backlog"` drops route correctly. Reject `data-column="completed"` drops with a no-op + console.warn log.
- **W4.3** — Confirm move-all chevron exclusion on Completed columns — the chevron-renderer at lines 737-764 / 1038-1057 must check the column name and skip emission when `col === "completed"`. Move-all chevrons ARE valid for `col === "backlog"`.
- **W4.4** — Wire drag-source from Backlog with destination rewrite. When `event.dataTransfer` source has `data-source-column="backlog"`, the `onDrop` handler REWRITES the target column to the leftmost active column (`"triage"` for issues, `"drafted"` for plans) regardless of which column the user drops onto. Rationale: per D5, this avoids forcing the user to remember the column order — promoting just means "make it active again." Add explicit code comment citing D5.
- **W4.5** — **Race-guard composition.** ALL drag-induced /api/queue POSTs (including the new backlog drops) MUST flow through the existing `postQueue(...)` helper at `app.js:1294` (the `pendingPosts++ / pendingPosts--` race-guard lives at lines 1353-1358 inside that helper). Conformance regression: `grep -cE "fetch\([^)]*api/queue" app.js` must return exactly 1 post-edit (the single helper, anchored on `fetch(` call-syntax). New regression test in `tests/test-dashboard-backlog-bidir.sh` fires two drags within 200ms and asserts no optimistic state revert.
- **W4.6** — Composition checks: assert claim aria-disabled invariant (PR #600) still holds — claim chip is not rendered on Completed cards (already guaranteed by W4.1, but the test makes it inspectable); assert move-all loop (PR #617) skips Completed columns; assert `lastGoodQueues` deepClone (PR #361 / app.js:333) initializes new columns.
- **W4.7** — Bump `skills/zskills-dashboard/SKILL.md metadata.version`.
- **W4.8** — Write test: new file `tests/test-dashboard-completed-readonly.sh` — assert Completed cards have no `draggable`, no claim chip, no per-card buttons. Mirrors the chip-DOM assertion pattern from `tests/test-fix-issues-claim-render-dom.sh`.
- **W4.9** — Write test: new file `tests/test-dashboard-backlog-bidir.sh` — playwright-cli interactive test: drag Triage→Backlog (assert POST body + persisted state); drag Backlog→Triage (assert POST body has the entry in `triage` regardless of which active column the user dropped onto — leftmost-rewrite rule); race-guard test fires two drags within 200ms.
- **W4.10** — Write test: extend `tests/test-fix-issues-claim-render-dom.sh` with a `completed_column_no_claim_chip` case asserting `[data-column="completed"] .claim-chip` selector returns zero elements.
- **W4.11** — Write test: extend `tests/test_zskills_monitor_dashboard_ui.sh` with `move_all_chevron_absent_on_completed` (DOM assertion: `[data-column="completed"] .move-all-group` is empty; `[data-column="backlog"] .move-all-group` is NOT empty).
- **W4.12** — Write test: `single_fetch_helper_post` case in `tests/test_zskills_monitor_dashboard_ui.sh` asserts `grep -cE "fetch\([^)]*api/queue" skills/zskills-dashboard/scripts/zskills_monitor/static/app.js == 1` (the postQueue helper is the sole site; `fetch(` call-syntax anchor).

### Design & Constraints

- Real mouse/keyboard events for drag tests (per CLAUDE.md "Manual Testing Philosophy") — no `page.evaluate()` to simulate drags.
- The `onDrop` handler must reject `data-column="completed"` drops AT the handler, not by omitting the dropzone — a Completed sub-column still renders as a `<ul>` for visual consistency, but it has no drop semantics.
- `lastGoodQueues` deepClone at app.js:333 MUST initialize all 5 plan columns and all 4 issue columns. The #355 bug recurs if this is missed.
- Claim invariant (PR #600): `aria-disabled` is set on actively-claimed cards in `buildIssueCard`. Completed cards skip this entirely because they have no claim chip — but the test explicitly asserts the absence to lock the invariant.
- Move-all chevron (PR #617): emission is per-column-header. The skip rule is `col !== "completed"` (not `col === "backlog"` — chevrons INTO Backlog are valid).
- Drag from Backlog to active: per D5, ALWAYS rewrites destination to LEFTMOST active column. This is intentional UX, not a bug.
- Race-guard: ALL drag POSTs go through `postQueue(...)` (PR-#361-style invariant); single-fetch conformance is locked at AC4.8.

### Tests

- `tests/test-dashboard-completed-readonly.sh` (new file).
- `tests/test-dashboard-backlog-bidir.sh` (new file).
- `tests/test-fix-issues-claim-render-dom.sh` (extended with completed-column case).
- `tests/test_zskills_monitor_dashboard_ui.sh` (extended with chevron-absence case + single-fetch case).
- Total: 2 new files + 2 extended files.

### Acceptance Criteria (Phase 4)

- **AC4.1** — Completed cards have no `draggable="true"` attribute (DOM assertion). **AC4.2** — Completed cards have no `.claim-chip` element (DOM assertion). **AC4.3** — Completed columns have no `.move-all-group` element (DOM assertion). **AC4.4** — Drag Triage→Backlog POSTs `issues.backlog: [N]` and the entry persists. **AC4.5** — Drag Backlog→<any active column> POSTs `issues.triage: [N]` (LEFTMOST-rewrite rule per D5) and `issues.backlog: []` for that N. **AC4.6** — Dropping onto `[data-column="completed"]` is a no-op + does not POST. **AC4.7** — `skills/zskills-dashboard/SKILL.md metadata.version` bumped this phase. **AC4.8** — `grep -cE "fetch\([^)]*api/queue" skills/zskills-dashboard/scripts/zskills_monitor/static/app.js == 1` (single `postQueue` helper is the sole POST site; race-guard intact — anchored on `fetch(` call-syntax so comments / JSDoc / error strings mentioning the path don't false-match).

### Dependencies

- Phase 3 (drag targets need the rendered DOM).
- Phase 2 (drag POSTs need the validator to accept `backlog`).

---

## Phase 5 — Integration, conformance, end-to-end verification

### Goal

Run the four-site synchronization conformance check, validate the full test suite passes with the expected new pass-count, run the playwright-cli end-to-end interaction, file the #618 follow-up issue, and prepare the PR body.

### Work Items

- **W5.1** — Add a section-scoped conformance check in `tests/test-skill-conformance.sh` that greps the four `PLAN_COLUMNS` / `ISSUE_COLUMNS` literal sites with FULL-TUPLE-ORDERING patterns (NOT substring presence — per DA9). Patterns:
  - `server.py`: `PLAN_COLUMNS *= *\("drafted", *"reviewed", *"ready", *"backlog"\)` and `ISSUE_COLUMNS *= *\("triage", *"ready", *"backlog"\)`.
  - `app.js`: `const PLAN_COLUMNS *= *\["drafted", *"reviewed", *"ready", *"backlog", *"completed"\]` and `const ISSUE_COLUMNS *= *\["triage", *"ready", *"backlog", *"completed"\]`.
  - `app.js` `deepCloneQueues` allocator: anchored on `for (const c of PLAN_COLUMNS)` and `for (const c of ISSUE_COLUMNS)` symbol patterns (which by reference cover the full tuple).
  - `collect.py` is iterative — it doesn't have a literal site, so a comment marker `# state-file column iteration — picks up new columns from PLAN_COLUMNS / ISSUE_COLUMNS dynamically; conformance: tests/test-skill-conformance.sh` is added at `collect.py` to document the synchronization point.
- **W5.2** — Run full suite `bash tests/run-all.sh`, capture to `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}`, assert `Overall: N/M passed, 0 failed` AND **pass-count grew vs. baseline AND there are zero new failures** (per `feedback_verify_by_count_not_any_fail` — counts dominate "0 failed" because some failure modes don't render as visible FAIL lines, e.g., timeout truncation). Approximate new-case count: Phase 1 adds 14 cases (W1.8-1.17 + W1.15b + W1.18 + W1.19 + W1.20), Phase 2 adds 4, Phase 3 adds 5 (W3.9-3.12 + W3.12b), Phase 4 adds 5 — plus 2 new test files (`test-dashboard-completed-readonly.sh`, `test-dashboard-backlog-bidir.sh`) contributing their own per-file case counts. Final assertion: `new_pass_count >= baseline_pass_count + 28` AND `new_fail_count == baseline_fail_count` (where `baseline_fail_count` is captured pre-plan; almost always 0).
- **W5.3** — Playwright-cli end-to-end interactive verification: load `/`, screenshot the initial state, drag a Triage issue → Backlog via real mouse events, screenshot, drag it Backlog → Triage, screenshot (assert it landed in Triage even if dropped on Ready — leftmost-rewrite rule), reload the page and assert Completed band renders if there are any in-window closed issues. Per `feedback_css_visual_verification`, include one-sentence visual judgments alongside each screenshot.
- **W5.4** — File follow-up issue for #618 (`landedPillClass` 11-status mapping audit-and-implement). Body cites the canonical set: `full, partial, landed, pr-ready, pr-ci-failing, pr-failed, conflict, pr-state-unknown, failed, direct-push-failed, direct-verify-failed` (sourced from `briefing/SKILL.md:231-234` + `fix-report/SKILL.md:161`). Use `gh issue create`. Reference the new issue in this PR's body (NOT `Closes` — the close is the follow-up's responsibility).
- **W5.5** — Final `skills/zskills-dashboard/SKILL.md metadata.version` bump if not yet done in Phases 1-4. (Phase 5 edits `tests/test-skill-conformance.sh` which lives under `tests/` — NOT a tracked skill subtree — so this version-bump line is only for any incremental skill-prose edits this phase performs.)
- **W5.6** — Update PR test plan checkboxes per `feedback_pr_test_plan_checkboxes` — check items the implementer verified, annotate any unchecked items with what's needed.
- **W5.7** — Write test: extend `tests/test-skill-conformance.sh` with the four-site synchronization assertion (W5.1).

### Design & Constraints

- Never weaken tests; if a test fails, find the root cause in code, not in the test.
- Two-attempt thrash cap — if the same test fails after two fix attempts, STOP and surface.
- Capture test output to `/tmp/zskills-tests/$(basename $(pwd))/.test-results.txt`; never pipe.
- Verify by pass-count not "any failures" (memory anchor `feedback_verify_by_count_not_any_fail`).
- PR landing via /land-pr (main_protected=true), NOT direct `gh pr merge --auto`.
- `tests/test-skill-conformance.sh` is at `tests/`, NOT under a tracked skill subtree — so editing it does NOT mechanically require a SKILL.md metadata bump. (Earlier draft incorrectly claimed it does.)

### Tests

- `tests/test-skill-conformance.sh` — extended with W5.1 four-site full-tuple-ordering assertion.
- Full suite run with pass-count gating.
- Playwright-cli end-to-end (W5.3).

### Acceptance Criteria (Phase 5)

- **AC5.1** — `bash tests/run-all.sh` outputs `Overall: N/M passed, 0 failed` with N matching baseline + new-test count. **AC5.2** — Conformance check fails closed if any of the four PLAN_COLUMNS / ISSUE_COLUMNS sites loses a column literal OR reorders the tuple. **AC5.3** — Playwright-cli end-to-end screenshots show the bands rendering, drag interactions persisting, leftmost-rewrite-on-promote, and reload preserving state. **AC5.4** — PR body references the new follow-up issue for #618 (NOT `Closes #618` — the close lives in the follow-up). **AC5.5** — `skills/zskills-dashboard/SKILL.md metadata.version` final bump confirmed.

### Dependencies

- Phases 1-4 (this phase verifies all of them in concert).

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review (default budget)
**Convergence:** Converged at round 3
**Remaining concerns:** None — all 53 findings across 3 rounds dispositioned as Fixed

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 12 (2 Block, 6 Major, 3 Minor, 1 Affirm) | 11 (1 Block, 4 Major, 6 Minor) | 23/23 (22 Fixed, 1 Affirm) |
| 2     | 7 (1 Major, 3 Minor, 3 Affirm)           | 7 (2 Block, 2 Major, 3 Minor)  | 14/14 (11 Fixed, 3 Affirm) |
| 3     | 6 (1 Minor, 5 Affirm)                    | 7 (2 Major, 4 Minor, 1 Nit)    | 8/8 Fixed (7 Fixed, 1 Fixed-via-handler) |

### Key restructures during refinement

- **Round 1:** Dropped #618 opportunistic close (drafter invented a 9-status set with zero matches in real codebase); changed gh fetch strategy from `--state all --limit 1000` to bounded `--state closed --search closed:>=DATE`; made W1.5 mandatory + added W1.5b backfill script.
- **Round 2:** Fixed empirical truncation (`--limit 100` measured 150 in window → default raised to 500 + truncation signal); resolved hardcoded `plans/` vs `docs/plans/` everywhere (config-resolved); switched backfill from `--diff-filter=AM` (file-creation date) to pickaxe `-G"status: complete"` (content-introduction date) with `--follow` and `%cI tail -1`.
- **Round 3:** Normalized `%cI` to UTC `Z` (was committer-local-TZ); pinned backfill CWD via `git rev-parse --show-toplevel`; added dedupe-prefer-closed for cross-cache race.

### User context

Third in a series of dashboard-polish PRs (after PR #613 cache-bust, #617 move-all, #622 plans-claim-chip-parity plan). Adversarial review caught material defects each round — speculative landed-pill statuses (round 1), wrong plans directory (round 2), timezone mismatches in date normalization (round 3).
