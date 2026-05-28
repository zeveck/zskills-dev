#!/usr/bin/env python3
"""Headless sim-logic tests for demo/demo_server.py (interactive model).

Asserts (no HTTP, no browser — pure Simulation logic):
  (a) a dragged item persists across a state rebuild — apply a queue POST,
      confirm the next snapshot reflects the new column (no snap-back);
  (b) an item placed in Ready picks up a claim and eventually completes;
  (c) the concurrency cap holds — at most N in-flight even with >N in Ready;
  (d) items NOT in Ready never get a claim or auto-move.

The Simulation uses time.monotonic() for arrivals + work timing; tests
fast-forward by rewinding `sim.start_time`, which is exactly what an
elapsed()-based clock makes easy to control deterministically.

Run: python3 tests/test-demo-server-interactive.py
Exit 0 on all-pass, 1 on any failure.
"""

import importlib.util
import pathlib
import sys
import time

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEMO_PATH = REPO_ROOT / "demo" / "demo_server.py"

PASS = 0
FAIL = 0


def ok(label):
    global PASS
    PASS += 1
    print("OK %s" % label)


def bad(label, detail=""):
    global FAIL
    FAIL += 1
    print("FAIL %s%s" % (label, (" -- " + detail) if detail else ""))


def load_module():
    spec = importlib.util.spec_from_file_location("demo_server", DEMO_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fast_forward(sim, seconds):
    """Pretend `seconds` have elapsed by rewinding the monotonic origin."""
    sim.start_time -= seconds


def find_plan_obj(snap, slug):
    for p in snap["plans"]:
        if p["slug"] == slug:
            return p
    return None


def find_issue_obj(snap, number):
    for i in snap["issues"]:
        if i["number"] == number:
            return i
    return None


def main():
    mod = load_module()

    # ------------------------------------------------------------------
    # (a) A dragged item persists across a state rebuild.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=1, concurrency=3)
    # Force ALL items to have arrived by fast-forwarding past the whole
    # arrival window, then tick.
    fast_forward(sim, 10000)
    sim.tick()
    snap = sim.build_snapshot()

    plan_slug = sim.plans[0].slug
    # The arrival column for a plan is "drafted". Drag it to "backlog".
    payload = {
        "plans": {c: [] for c in mod.PLAN_DRAG_COLUMNS},
        "issues": {c: [] for c in mod.ISSUE_DRAG_COLUMNS},
    }
    # Rebuild every other plan/issue into its current column so the POST
    # is a full board snapshot (the frontend always POSTs the whole board).
    for p in snap["plans"]:
        col = p["queue"]["column"]
        if col == mod.COMPLETED_COLUMN:
            continue
        target = "backlog" if p["slug"] == plan_slug else col
        payload["plans"][target].append({"slug": p["slug"], "mode": None})
    for i in snap["issues"]:
        col = i["queue"]["column"]
        if col == mod.COMPLETED_COLUMN:
            continue
        payload["issues"][col].append(i["number"])

    sim.apply_queue(payload)
    snap2 = sim.build_snapshot()
    moved = find_plan_obj(snap2, plan_slug)
    if moved and moved["queue"]["column"] == "backlog":
        ok("(a) dragged plan persists in backlog across rebuild (no snap-back)")
    else:
        bad("(a) dragged plan did not persist",
            "got column=%s" % (moved and moved["queue"]["column"]))

    # Poll again immediately — still backlog (no autonomous motion).
    snap3 = sim.build_snapshot()
    moved3 = find_plan_obj(snap3, plan_slug)
    if moved3 and moved3["queue"]["column"] == "backlog":
        ok("(a) plan stays in backlog on a second poll (still no auto-move)")
    else:
        bad("(a) plan drifted on second poll",
            "got column=%s" % (moved3 and moved3["queue"]["column"]))

    # ------------------------------------------------------------------
    # (b) An item placed in Ready picks up a claim and eventually completes.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=2, concurrency=3)
    fast_forward(sim, 10000)
    sim.tick()
    snap = sim.build_snapshot()

    # Drag exactly one plan into Ready; everything else to backlog so it
    # doesn't compete for slots.
    target_slug = sim.plans[0].slug
    payload = {
        "plans": {c: [] for c in mod.PLAN_DRAG_COLUMNS},
        "issues": {c: [] for c in mod.ISSUE_DRAG_COLUMNS},
    }
    for p in snap["plans"]:
        if p["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        col = "ready" if p["slug"] == target_slug else "backlog"
        payload["plans"][col].append({"slug": p["slug"], "mode": None})
    for i in snap["issues"]:
        if i["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        payload["issues"]["backlog"].append(i["number"])
    sim.apply_queue(payload)

    # Next snapshot: the Ready plan should pick up a claim (in-flight).
    snap = sim.build_snapshot()
    pobj = find_plan_obj(snap, target_slug)
    if pobj and pobj["queue"]["column"] == "ready" and pobj.get("claim"):
        ok("(b) Ready plan picks up a claim chip")
    else:
        bad("(b) Ready plan did not pick up a claim",
            "col=%s claim=%s" % (pobj and pobj["queue"]["column"], pobj and pobj.get("claim")))

    # Phases should tick: confirm 0 < phases_done < phase_count mid-flight.
    if pobj and 0 < pobj["phases_done"] < pobj["phase_count"]:
        ok("(b) in-flight plan shows partial phase progress")
    else:
        bad("(b) phases not ticking mid-flight",
            "phases_done=%s of %s" % (pobj and pobj["phases_done"], pobj and pobj["phase_count"]))

    # Fast-forward past the work duration → it must auto-advance to completed.
    work_item = sim._by_slug[target_slug]
    fast_forward(sim, work_item.work_duration + 5)
    snap = sim.build_snapshot()
    pobj = find_plan_obj(snap, target_slug)
    if pobj and pobj["queue"]["column"] == mod.COMPLETED_COLUMN and pobj["status"] == "complete":
        ok("(b) worked plan auto-advances to Completed when work finishes")
    else:
        bad("(b) worked plan did not complete",
            "col=%s status=%s" % (pobj and pobj["queue"]["column"], pobj and pobj["status"]))
    if pobj and not pobj.get("claim"):
        ok("(b) completed plan has no claim chip")
    else:
        bad("(b) completed plan still carries a claim")

    # ------------------------------------------------------------------
    # (c) Concurrency cap holds — <=N in-flight even with >N in Ready.
    # ------------------------------------------------------------------
    CAP = 3
    sim = mod.Simulation(seed=3, concurrency=CAP)
    fast_forward(sim, 10000)
    sim.tick()
    snap = sim.build_snapshot()

    # Pile 6 plans into Ready.
    ready_slugs = [p.slug for p in sim.plans[:6]]
    payload = {
        "plans": {c: [] for c in mod.PLAN_DRAG_COLUMNS},
        "issues": {c: [] for c in mod.ISSUE_DRAG_COLUMNS},
    }
    for p in snap["plans"]:
        if p["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        col = "ready" if p["slug"] in ready_slugs else "backlog"
        payload["plans"][col].append({"slug": p["slug"], "mode": None})
    for i in snap["issues"]:
        if i["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        payload["issues"]["backlog"].append(i["number"])
    sim.apply_queue(payload)

    snap = sim.build_snapshot()
    in_ready = [p for p in snap["plans"] if p["queue"]["column"] == "ready"]
    claimed = [p for p in in_ready if p.get("claim")]
    waiting = [p for p in in_ready if not p.get("claim")]
    if len(claimed) == CAP:
        ok("(c) exactly %d Ready plans are in-flight (cap respected)" % CAP)
    else:
        bad("(c) wrong in-flight count", "claimed=%d (cap=%d)" % (len(claimed), CAP))
    if len(waiting) == len(ready_slugs) - CAP:
        ok("(c) the remaining %d Ready plans wait with no claim" % (len(ready_slugs) - CAP))
    else:
        bad("(c) wrong waiting count", "waiting=%d" % len(waiting))

    # After the first batch finishes, a waiting one should pick up a slot.
    max_dur = max(sim._by_slug[s].work_duration for s in ready_slugs)
    fast_forward(sim, max_dur + 5)
    snap = sim.build_snapshot()
    completed_now = [p for p in snap["plans"]
                     if p["slug"] in ready_slugs
                     and p["queue"]["column"] == mod.COMPLETED_COLUMN]
    still_inflight = [p for p in snap["plans"]
                      if p["queue"]["column"] == "ready" and p.get("claim")]
    if len(completed_now) >= CAP:
        ok("(c) first batch completed and freed slots")
    else:
        bad("(c) first batch did not complete", "completed=%d" % len(completed_now))
    if len(still_inflight) <= CAP:
        ok("(c) in-flight still capped at <=%d after slot churn" % CAP)
    else:
        bad("(c) cap violated after churn", "in_flight=%d" % len(still_inflight))

    # ------------------------------------------------------------------
    # (d) Items NOT in Ready never get a claim or auto-move.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=4, concurrency=3)
    fast_forward(sim, 10000)
    sim.tick()
    snap = sim.build_snapshot()

    # Place items across non-Ready columns and confirm: no claims, and the
    # columns hold after many polls + a long fast-forward.
    payload = {
        "plans": {c: [] for c in mod.PLAN_DRAG_COLUMNS},
        "issues": {c: [] for c in mod.ISSUE_DRAG_COLUMNS},
    }
    plan_cols = ["drafted", "reviewed", "backlog", "discarded"]
    for idx, p in enumerate(snap["plans"]):
        if p["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        col = plan_cols[idx % len(plan_cols)]
        payload["plans"][col].append({"slug": p["slug"], "mode": None})
    issue_cols = ["triage", "backlog"]
    placed_issue_cols = {}
    for idx, i in enumerate(snap["issues"]):
        if i["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        col = issue_cols[idx % len(issue_cols)]
        payload["issues"][col].append(i["number"])
        placed_issue_cols[i["number"]] = col
    sim.apply_queue(payload)

    # Capture the post-drag placement.
    snap = sim.build_snapshot()
    expected_plan_cols = {p["slug"]: p["queue"]["column"] for p in snap["plans"]}

    # Long fast-forward + several polls. Nothing in a non-Ready column may
    # gain a claim or move.
    fast_forward(sim, 600)
    any_claim = False
    moved = False
    for _ in range(3):
        snap = sim.build_snapshot()
        for p in snap["plans"]:
            col = p["queue"]["column"]
            if col != "ready" and col != mod.COMPLETED_COLUMN:
                if p.get("claim"):
                    any_claim = True
                if expected_plan_cols.get(p["slug"]) != col:
                    moved = True
        for i in snap["issues"]:
            col = i["queue"]["column"]
            if col != "ready" and col != mod.COMPLETED_COLUMN and i.get("claim"):
                any_claim = True

    if not any_claim:
        ok("(d) non-Ready items never carry a claim chip")
    else:
        bad("(d) a non-Ready item gained a claim")
    if not moved:
        ok("(d) non-Ready items never auto-move across polls/time")
    else:
        bad("(d) a non-Ready item auto-moved")

    # ------------------------------------------------------------------
    # Bonus structural checks the frontend depends on.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=5, concurrency=3)
    snap = sim.build_snapshot()
    q = snap["queues"]
    if "completed" in q["plans"] and "completed" in q["issues"]:
        ok("structural: queues expose read-only `completed` for both kinds")
    else:
        bad("structural: missing completed in queues object")
    if snap["demo"]["concurrency"] == 3 and snap["demo"]["interactive"] is True:
        ok("structural: demo block advertises interactive + concurrency")
    else:
        bad("structural: demo block missing interactive/concurrency")
    if mod.Simulation(seed=5).build_snapshot()["demo"]["all_completed"] is False:
        ok("structural: victory is False before any arrivals complete")
    else:
        bad("structural: victory true at t=0")

    print("")
    print("Results: %d passed, %d failed (of %d)" % (PASS, FAIL, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
