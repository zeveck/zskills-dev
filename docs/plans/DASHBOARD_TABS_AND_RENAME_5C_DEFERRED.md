# Phase 5c — READY drop: DEFERRED

## Subsumed-by-5b predicate evaluation (per plan AC)

* Condition (a) — 5c-repro shows HTTP 403 on the drop-POST line:
  **NOT SATISFIED.** The POST in our environment returned HTTP 200
  (`Origin: http://127.0.0.1:8181` was already on the original
  accept list, even before the 5b broadening). See
  `/tmp/dashboard-phase5/5c-repro.txt`.
* Condition (b) — after 5b's fix, re-running 5c reproducer returns 200
  AND state updates: **NOT SATISFIED.** Post-5b, the POST still returns
  200 (it always did), but `/api/state` continues to report
  `queues.plans.ready: []` despite the on-disk
  `.zskills/monitor-state.json` containing the dropped slug.

Conclusion: 5c is **NOT subsumed by 5b**. Per plan AC:

> If EITHER condition fails (403 not observed in 5c-repro, OR drag
> still fails after 5b's fix), 5c must ship its own fix OR be
> reclassified as a deferred sub-section per the Phase 5 time-box
> deferral protocol.

Choosing the deferred path. Rationale below.

## Root cause observed in the worktree environment

`server.py:_handle_queue_post()` writes to
`ctx["main_root"] / ".zskills" / "monitor-state.json"`, where
`ctx["main_root"]` is the literal `--main-root` argument
(`/tmp/zskills-pr-dashboard-tabs-and-rename` for the Phase 5 server).

`server.py:_handle_state()` calls `collect.collect_snapshot(main_root)`
which internally calls `collect._resolve_main_root(repo_root)` at
`collect.py:179`. That function ALWAYS hops to the main worktree root
via `git rev-parse --git-common-dir`, so when invoked from inside the
worktree it returns `/workspaces/zskills`.

Result: POST writes to the worktree's `.zskills/`, but GET reads from
the main repo's `.zskills/`. The card appears to vanish.

## Why this is NOT the user's reported bug

The user runs the dashboard from their main checkout. In that
deployment, the `main_root` argument and the `_resolve_main_root` hop
both resolve to the same path; the asymmetry is invisible. The
user-reported "READY column not accepting drops" symptom must therefore
have a different cause specific to their environment.

Possible candidates from the plan / diagnosis context (NONE confirmed
locally):

1. The `data-column` attribute on the READY `ul.dropzone` may not
   match the `data-kind` predicate at `app.js:1345-1347` in some
   render path. The current `app.js:480` does have `if (col === "ready")`
   special-handling for mode-buttons; if a render bug ever produced a
   READY dropzone without a `data-column="ready"` attribute, the drop
   handler at `app.js:1348` would compute `targetCol = null` and the
   resulting POST might be malformed enough that the server rejects
   it. Static reading shows that attribute IS set unconditionally
   (`app.js:434`, `app.js:588`), so this is unlikely.
2. The optimistic-update branch at `commitQueueChange` reverts on
   `postQueue` failure (`app.js:1037-1048`). If a transient 403/500
   races with a drop, the UI reverts and looks like "drop did not
   take". After 5b's broadening this should be less common.
3. Some users may have additional cards in their queue that collide
   with the optimistic-render fingerprint (`fingerprintPlans`) and
   end up overwritten on the next poll.

## Why the local fix exceeds Phase 5 surgical scope

The local-reproducible cause (POST/GET path asymmetry) is a structural
invariant of how `_resolve_main_root` is intentionally used to centralize
state on the main repo. The CORRECT behaviors are:

* POST handler MAY honor "always write to main" by also calling
  `_resolve_main_root(ctx['main_root'])` before deriving the target
  path. (Defensible: ~5 LOC change.)
* OR: the server should refuse to start with `--main-root` pointing at
  a worktree (validate at boot, fail-fast).

Either change touches behavior beyond the surgical 3-symptom scope of
Phase 5, and may interact with the Phase 4 server lifecycle conventions
and the queue-mode tests. It also fixes a symptom NOT actually reported
by the user.

## Disposition

* No app.js / server.py changes for 5c in this PR.
* Filing follow-up GitHub issue (out-of-band of this commit) to track:
  "[dashboard] POST /api/queue writes to --main-root but /api/state
  reads via _resolve_main_root — silent state divergence when server
  runs in a worktree."
* If the user's reported "READY column not accepting drops" recurs
  after Phase 5 lands, the next investigation should instrument the
  actual user's `app.js` console for `data-column` attributes at drop
  time and the `postQueue` response status — neither of which we can
  reproduce remotely.

Time spent on 5c: ~10 min (well under 60 min budget).
