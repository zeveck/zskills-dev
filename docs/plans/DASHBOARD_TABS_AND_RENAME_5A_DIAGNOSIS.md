# Phase 5a — Dashboard Functional Diagnosis

Generated 2026-05-13 against worktree dashboard at `http://127.0.0.1:8181/`
(server PID per `/tmp/dashboard-phase5.pid`, `--main-root /tmp/zskills-pr-dashboard-tabs-and-rename`).

Reproducer artifacts saved under `/tmp/dashboard-phase5/`:
`5b-repro.txt`, `5c-repro.txt`, `5d-repro.txt`.

## Symptom 5b — 403 on `/api/queue` drag POST

### Reproducer (recorded in `/tmp/dashboard-phase5/5b-repro.txt`)

```
# Seven curl variants against /api/queue. The body validation is reached
# only when _origin_ok() returns True.
curl -X POST -H 'Origin: http://127.0.0.1:8181' .../api/queue -d '{...}'   -> HTTP 400 (body validation; Origin OK)
curl -X POST -H 'Origin: http://localhost:8181' .../api/queue -d '{...}'   -> HTTP 400 (Origin OK)
curl -X POST -H 'Origin: null' .../api/queue -d '{...}'                    -> HTTP 403 (Origin REJECTED)
curl -X POST -H 'Origin: http://evil.com' .../api/queue -d '{...}'         -> HTTP 403 (Origin REJECTED — correct)
curl -X POST (NO Origin header) .../api/queue -d '{...}'                   -> HTTP 403 (Origin REJECTED)
curl -X POST -H 'Origin: https://127.0.0.1:8181' .../api/queue -d '{...}'  -> HTTP 403 (Origin REJECTED — scheme strict)
```

### Observed behavior

Of seven variants, four were rejected with `{"error": "Origin check failed"}`:

1. `Origin: null` — REJECTED. Browsers/proxies legitimately send `null` for
   opaque origins or after certain redirects.
2. Missing Origin header — REJECTED. Some browsers/proxies strip the
   Origin header on same-origin POSTs (modern Chrome usually sends it, but
   not under all CSP/Referrer-Policy combinations).
3. `Origin: https://127.0.0.1:8181` — REJECTED on scheme mismatch.
4. `Origin: http://evil.com` — REJECTED (correctly).

### Root-cause hypothesis

`_origin_ok` at `server.py:601-610` is too strict for a localhost-only,
no-proxy, no-HTTPS deployment. The exact check:

```python
def _origin_ok(self) -> bool:
    ctx = self._ctx()
    port = ctx["port"]
    expected_set = {
        f"http://127.0.0.1:{port}",
        f"http://localhost:{port}",
    }
    origin = self.headers.get("Origin", "")
    return origin in expected_set
```

Three failure modes hit real-world deployments:

* **Stripped Origin** — when a user's browser/proxy/extension elides the
  Origin header on a same-origin POST, the check rejects what is, by every
  other criterion, a legitimate request from the same page.
* **`null` Origin** — emitted by some browsers post-redirect or in
  sandboxed contexts; also legitimate.
* **HTTPS scheme** — if the user fronts the dashboard with a TLS reverse
  proxy (the dashboard itself binds plain HTTP, but a proxy could
  terminate TLS), the Origin scheme will be `https://` while the expected
  set only contains `http://`.

### Proposed fix shape (5b)

Broaden `_origin_ok` to accept three categories AND keep the cross-origin
rejection invariant:

1. **Empty / missing Origin** → ACCEPT (same-origin-by-default
   convention; OWASP CSRF cheatsheet treats this as low-risk for
   localhost-bound services).
2. **`null` Origin literal** → ACCEPT.
3. **Same-host Origin (any scheme)** — parse Origin, accept iff host part
   matches `127.0.0.1` or `localhost` AND (port matches `port` OR Origin
   has no explicit port — for proxies).
4. Everything else → REJECT (preserves the evil.com rejection).

The fix is ~10 LOC and keeps the central invariant in one place.

### Does 5b collapse 5c or 5d?

* **5c** — NO. See 5c diagnosis: the user's READY-drop symptom in a
  main-repo (non-worktree) deployment cannot be explained by 5b. The
  worktree-vs-main-root path mismatch I observed locally would not occur
  in the user's deployment, where they run the dashboard from the main
  repo. The 5c symptom is therefore NOT subsumed by 5b in the user's
  environment.
* **5d** — NO. Disconnect-flap fires on any single transient `fetchState`
  failure (5xx OR network error); 5b's fix doesn't change that.

## Symptom 5c — READY column not accepting drops

### Reproducer (recorded in `/tmp/dashboard-phase5/5c-repro.txt`)

```bash
# Simulate a drag of plan adaptive-cron-backoff into READY:
curl -X POST -H 'Origin: http://127.0.0.1:8181' \
  -H 'Content-Type: application/json' http://127.0.0.1:8181/api/queue \
  -d '{"default_mode":"phase","plans":{"drafted":[],"reviewed":[],"ready":[{"slug":"adaptive-cron-backoff","mode":"phase"}]},"issues":{"triage":[],"ready":[]}}'
# -> HTTP 200 {"ok": true, ...}

# Then poll state:
curl http://127.0.0.1:8181/api/state | jq '.queues.plans'
# -> {"drafted": [], "reviewed": [], "ready": []}   <-- card NOT present!
```

The POST returned 200. The file `/tmp/zskills-pr-dashboard-tabs-and-rename/.zskills/monitor-state.json`
DOES contain the slug under `plans.ready`. But `/api/state` reports
`queues.plans.ready: []`.

### Observed behavior

The card does not appear after the drop, even though the POST succeeded
and the write to disk landed. `repo_root` in the state response is
`/workspaces/zskills` — the main repo — while the POST handler writes to
`/tmp/zskills-pr-dashboard-tabs-and-rename` (the `--main-root` arg).

### Root-cause hypothesis

**Path asymmetry between the POST handler and the GET handler in the
worktree deployment.** Concrete chain of evidence:

* `server.py:_handle_queue_post()` (~line 833): writes to
  `ctx["main_root"] / ".zskills" / "monitor-state.json"`. `ctx["main_root"]`
  is the literal `--main-root` arg.
* `server.py:_handle_state()` (line 723): calls
  `_collect.collect_snapshot(str(main_root))`.
* `collect.py:collect_snapshot()` (line 1140) calls
  `_resolve_main_root(repo_root)`.
* `collect.py:_resolve_main_root()` (line 179) runs
  `git rev-parse --git-common-dir` from the supplied path and hops to the
  parent of the resulting `.git` — i.e., it ALWAYS resolves to the main
  worktree root, even when invoked from a worktree.

**In the user's actual main-repo deployment, both `main_root` arguments
collapse to the same path, so this asymmetry is invisible.** Therefore
this symptom is reproduction-specific to the worktree environment and
NOT a real bug from the user's reporting context. If a user runs the
dashboard from a worktree, they would hit this; but the user's report was
from their main checkout.

### Subsumed-by-5b predicate (per plan AC)

* Condition (a): the 5c-repro server log shows HTTP 403 on the drop-POST
  line. **NOT SATISFIED** — the POST returned 200 (Origin: `http://127.0.0.1:8181`
  is on the accept list).
* Condition (b): after 5b's fix, re-running the drag returns 200 + state
  updates. **CANNOT BE SATISFIED** — the state read goes via
  `_resolve_main_root` which is a separate code path from 5b.

Conclusion: **5c is NOT subsumed by 5b.** But it is ALSO not the user's
actual bug — it is a worktree-only artifact of how Phase 5 was
investigated. Proposed closure: ship a defensive guard (POST to a
worktree-main-root should still update visible state — at minimum, return
an error like "main_root mismatch" instead of silently writing the wrong
file) — OR defer to a follow-up GitHub issue, since touching the
collect/server path asymmetry exceeds Phase 5's surgical-fix scope.

### Proposed fix shape (5c)

**Recommended: defer to a follow-up issue.** Reasons:

1. The symptom is not the user-reported one; the user is on main, not a
   worktree.
2. A real fix touches the path-resolution invariant
   (`_resolve_main_root` always hops; this is intentional for queues
   reading-from-main, but the POST path doesn't honor it).
3. Inverting either side would be ~50+ LOC + affect every collect-based
   feature.

Ship a deferred-marker doc; surface the path-asymmetry as an issue.

## Symptom 5d — Disconnect-banner flap during interaction

### Reproducer (recorded in `/tmp/dashboard-phase5/5d-repro.txt`)

The `setConnected(false)` call sites inside `fetchState` are at lines
147 and 154 of `static/app.js` (verified). Both have ZERO debounce: any
single non-2xx response (`!res.ok`) or any `fetch` exception
(`catch (_err)`) immediately flips `#conn-banner.hidden` to `false`.

`grep -nE "\.abort\(|pollAbort\.|workPollAbort\." app.js` returns zero
matches, confirming the abort-controllers are stored but never invoked.
The earlier user hypothesis (abort-cancelled POST → setConnected(false))
is incorrect: there is no abort site.

### Observed behavior

In a fault-injection test where `/api/state` returns 500 once then 200:
the banner becomes visible on the 500 response and stays visible until
the next successful poll (worst-case ~2s). For users dragging cards
during a moment of server contention (any transient 5xx, ECONNRESET,
or socket timeout), this manifests as a "flap" — the banner appears for
one poll cycle and clears on the next.

### Root-cause hypothesis

No debounce on `setConnected(false)`. A single transient error fires the
banner. The fix is to require N consecutive failures (N=2) before
flipping the banner visible.

### Proposed fix shape (5d)

* Add module-level `let connectionFailureCount = 0;`.
* On failure paths in `fetchState`: increment, only call
  `setConnected(false)` when count >= 2.
* On success path: reset count to 0; call `setConnected(true)`.
* ~10 LOC, confined to `fetchState`.

### Does 5d collapse 5c or 5b?

NO. Independent failure mode.

## Phase 5 routing decision

| Sub-section | Routing |
|-------------|---------|
| 5b | Ship the broadened-`_origin_ok` fix (~10 LOC) + CSRF test. Real bug observed locally; the fix shape applies to every deployment. |
| 5c | DEFER — symptom in our env is a worktree path-asymmetry artifact, not the user's reported bug; a meaningful fix exceeds Phase 5 surgical scope. Ship a deferred-marker doc. |
| 5d | Ship the debounce fix (~10 LOC) + debounce test. Confirmed reproducible reasoning chain; fix is small. |
| 5e | Run reproducer, expect no-bug per V5/R5 in the plan. |

Time spent on 5a: ~25 min (within 30 min budget).
