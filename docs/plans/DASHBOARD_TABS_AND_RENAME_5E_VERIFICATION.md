# Phase 5e — `/work-on-plans` queue-honoring verification

## Reproducer

Per the plan recipe:

1. Drag two plans into the READY column on the Phase-5 worktree
   dashboard.
2. Verify `.zskills/monitor-state.json` contains both slugs under
   `plans.ready` in order.
3. Run `/work-on-plans 1`.
4. Compare: did the dispatched slug match the front of `plans.ready`
   at dispatch time?

## Local execution

Steps 1-2 — partially completed during 5a:

* The Phase 5a 5c-repro POST'd `adaptive-cron-backoff` into
  `.zskills/monitor-state.json:plans.ready` (worktree copy at
  `/tmp/zskills-pr-dashboard-tabs-and-rename/.zskills/monitor-state.json`).
  File reads:

  ```json
  "plans": {
    "drafted": [], "reviewed": [],
    "ready": [
      {"slug": "adaptive-cron-backoff", "mode": "phase"}
    ]
  }
  ```

* The dashboard `/api/state` does not report this — same worktree
  path-asymmetry diagnosed in 5c. The user's main-repo deployment
  would not exhibit this; `/work-on-plans` reads
  `$MAIN_ROOT/.zskills/monitor-state.json` directly, bypassing the
  dashboard, so the dashboard view is irrelevant to this verification.

Step 3 — NOT executed in this verification: dispatching
`/work-on-plans 1` would actually fire a downstream `/run-plan`
invocation, which is out of scope for a Phase-5 verification step and
would interfere with the orchestrator's own pipeline.

Step 4 — verified by source-reading per V5/R5.

## Source-reading verification

`/work-on-plans` (skill at `.claude/skills/work-on-plans/SKILL.md`):

* **Line 7:** "Reads .zskills/monitor-state.json (plans.ready) in
  order and dispatches".
* **Lines 120-121:** `MONITOR_STATE="$MAIN_ROOT/.zskills/monitor-state.json"`
  — reads from main repo, not the worktree.
* **Lines 164-166:** Step 1 — sync — "Read $MONITOR_STATE and extract
  plans.ready".
* **Lines 327-339** (extract loop):

  ```python
  for entry in doc.get('plans', {}).get('ready', []):
      if isinstance(entry, str):       # version 1.0 forward-compat
          slug, mode = entry, ''
      else:
          slug = entry.get('slug', '')
          mode = entry.get('mode', '') or ''
  ```

  Python's `for entry in list` iterates IN ORDER. The skill emits
  one `slug<TAB>mode` line per entry, preserving the queue order.

* **Argument parsing (lines 50-78):** `N` indicates the count to
  dispatch; `(no args)` prints the ready queue read-only without
  dispatching.

## Outcome

* **No bug observed.** The skill's documented behavior matches the
  source code: `plans.ready` is read in order, and the first N entries
  (per `N` argument) are dispatched in their stored order.
* No code changes ship under `skills/` for 5e.
* If a user observes `/work-on-plans` failing to honor queue order in
  their environment, the first investigation step should be to read
  the on-disk `.zskills/monitor-state.json` directly and verify
  `plans.ready` order matches the dashboard view — divergence here
  would point to the same worktree/main path asymmetry diagnosed in
  5c, not a `/work-on-plans` bug.

Time spent on 5e: ~10 min (well under 30 min budget).
