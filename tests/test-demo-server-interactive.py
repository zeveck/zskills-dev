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
    """Pretend `seconds` have elapsed by rewinding the monotonic origin.

    The sim clock is LAZILY anchored (start_time is None until the first
    /api/state request), so anchor it here first if a test fast-forwards
    before its first build_snapshot — exactly what a "page opened" would do.
    """
    sim._anchor()
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

    # ==================================================================
    # NEW LIFECYCLE CASES (first-load clock anchor, seed, branches +
    # activity from the work lifecycle, realistic landing_modes).
    # ==================================================================

    # ------------------------------------------------------------------
    # (lifecycle a) Clock does NOT advance until the first /api/state.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=11, concurrency=3)
    # No build_snapshot yet — clock is unanchored.
    if sim.start_time is None and sim.elapsed() == 0.0:
        ok("(a) fresh sim: clock unanchored (start_time None, elapsed 0)")
    else:
        bad("(a) clock anchored before first /api/state",
            "start_time=%s elapsed=%s" % (sim.start_time, sim.elapsed()))

    # Tick directly (as a poll-without-state would NOT, but to prove no
    # arrivals happen at t=0 beyond the seeded pair) — nothing should arrive
    # because elapsed() is pinned to 0 until anchored.
    sim.tick()
    arrived_pre = [it for it in sim._all_items() if it.arrived]
    # At elapsed==0 the seeded pair (arrive_at==0) DOES arrive on tick; that
    # is the seed, covered below. The key assertion: no NON-seed item arrived.
    non_seed_arrived = [it for it in arrived_pre if it.arrive_at > 0.0]
    if not non_seed_arrived:
        ok("(a) no non-seed item arrives while clock is pinned at t=0")
    else:
        bad("(a) a future-arrival item arrived before the clock advanced",
            "count=%d" % len(non_seed_arrived))

    # Simulate the first /api/state call: build_snapshot anchors the clock.
    snap = sim.build_snapshot()
    if sim.start_time is not None and snap["demo"]["elapsed_seconds"] >= 0.0:
        ok("(a) first /api/state anchors the clock (timeline begins at t=0)")
    else:
        bad("(a) build_snapshot did not anchor the clock")

    # A second poll does NOT reset the anchor.
    anchor_after_first = sim.start_time
    sim.build_snapshot()
    if sim.start_time == anchor_after_first:
        ok("(a) subsequent polls do NOT reset the anchored clock")
    else:
        bad("(a) anchor moved on a later poll")

    # ------------------------------------------------------------------
    # (lifecycle b) Exactly one plan + one issue seeded at the anchor.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=12, concurrency=3)
    snap = sim.build_snapshot()  # first /api/state at t=0
    seeded_plans = [p for p in snap["plans"]]
    seeded_issues = [i for i in snap["issues"]]
    egg_slugs = set(mod.EASTER_EGG_SLUGS)
    # At t=0: one core plan (Drafted) + two easter-egg plans (Backlog /
    # Discarded) + one core issue (Triage). Separate the core plan out.
    core_seed_plans = [p for p in seeded_plans if p["slug"] not in egg_slugs]
    egg_seed_plans = [p for p in seeded_plans if p["slug"] in egg_slugs]
    if len(core_seed_plans) == 1 and len(seeded_issues) == 1:
        ok("(b) exactly one core plan + one core issue present at the anchored t=0")
    else:
        bad("(b) wrong core seed count at t=0",
            "core_plans=%d issues=%d" % (len(core_seed_plans), len(seeded_issues)))
    if len(egg_seed_plans) == len(mod.EASTER_EGG_DEFS):
        ok("(b) both easter-egg plans present at the anchored t=0")
    else:
        bad("(b) wrong easter-egg seed count at t=0",
            "eggs=%d" % len(egg_seed_plans))
    if (core_seed_plans and core_seed_plans[0]["queue"]["column"] == mod.PLAN_ARRIVAL_COLUMN
            and seeded_issues and seeded_issues[0]["queue"]["column"] == mod.ISSUE_ARRIVAL_COLUMN):
        ok("(b) seeded core plan is in Drafted, seeded issue is in Triage")
    else:
        bad("(b) seeded items not in their arrival columns")

    # ------------------------------------------------------------------
    # (lifecycle c) A claimed Ready item produces a branch (Active bucket via
    # worktrees) + activity entries.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=13, concurrency=3)
    sim.build_snapshot()      # anchor
    fast_forward(sim, 10000)  # all arrived
    snap = sim.build_snapshot()
    target = sim.plans[0].slug
    payload = {
        "plans": {c: [] for c in mod.PLAN_DRAG_COLUMNS},
        "issues": {c: [] for c in mod.ISSUE_DRAG_COLUMNS},
    }
    for p in snap["plans"]:
        if p["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        col = "ready" if p["slug"] == target else "backlog"
        payload["plans"][col].append({"slug": p["slug"], "mode": None})
    for i in snap["issues"]:
        if i["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        payload["issues"]["backlog"].append(i["number"])
    sim.apply_queue(payload)
    snap = sim.build_snapshot()

    branch_name = "feat/%s" % target
    br = [b for b in snap["branches"] if b["name"] == branch_name]
    wt = [w for w in snap["worktrees"] if w["branch"] == branch_name]
    if br and wt:
        ok("(c) claimed Ready plan produces a branch + worktree entry")
    else:
        bad("(c) no branch/worktree for claimed plan",
            "branches=%d worktrees=%d" % (len(br), len(wt)))
    # classifyBranch: worktree present + landed None -> Active bucket.
    if wt and wt[0]["landed"] is None and wt[0]["category"] == "active":
        ok("(c) claimed-but-incomplete worktree -> Active bucket (landed None)")
    else:
        bad("(c) claimed worktree not in Active bucket",
            "landed=%s" % (wt and wt[0]["landed"]))
    # Activity entries for the claim lifecycle.
    acts = [a for a in snap["activity"] if a["id"] == target]
    act_kinds = {a["kind"] for a in acts}
    if {"claimed", "implement"}.issubset(act_kinds):
        ok("(c) claimed plan emits claimed + implement activity entries")
    else:
        bad("(c) missing claim/implement activity", "kinds=%s" % act_kinds)
    if acts and all(a["skill"] == "run-plan" for a in acts):
        ok("(c) plan activity carries skill=run-plan")
    else:
        bad("(c) plan activity skill not run-plan",
            "skills=%s" % {a["skill"] for a in acts})

    # ------------------------------------------------------------------
    # (lifecycle d) On completion the branch flips to Landed + a land entry.
    # ------------------------------------------------------------------
    fast_forward(sim, sim._by_slug[target].work_duration + 5)
    snap = sim.build_snapshot()
    wt = [w for w in snap["worktrees"] if w["branch"] == branch_name]
    if wt and wt[0]["landed"] and wt[0]["category"] == "landed":
        ok("(d) completed item's worktree flips to Landed (landed.status set)")
    else:
        bad("(d) completed worktree did not flip to Landed",
            "landed=%s" % (wt and wt[0]["landed"]))
    acts = [a for a in snap["activity"] if a["id"] == target]
    if any(a["kind"] == "land-pr" for a in acts):
        ok("(d) completion emits a land-pr activity entry")
    else:
        bad("(d) no land-pr activity on completion",
            "kinds=%s" % {a["kind"] for a in acts})
    # Activity is newest-first: the land-pr entry should precede claimed.
    kinds_order = [a["kind"] for a in acts]
    if ("land-pr" in kinds_order and "claimed" in kinds_order
            and kinds_order.index("land-pr") < kinds_order.index("claimed")):
        ok("(d) activity feed is newest-first (land-pr before claimed)")
    else:
        bad("(d) activity not newest-first", "order=%s" % kinds_order)

    # ------------------------------------------------------------------
    # (lifecycle e) Non-worked items produce NO branch and NO activity.
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=14, concurrency=3)
    sim.build_snapshot()      # anchor
    fast_forward(sim, 10000)  # all arrived
    snap = sim.build_snapshot()
    # Place EVERYTHING in non-Ready columns (no work ever starts).
    payload = {
        "plans": {c: [] for c in mod.PLAN_DRAG_COLUMNS},
        "issues": {c: [] for c in mod.ISSUE_DRAG_COLUMNS},
    }
    for p in snap["plans"]:
        if p["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        payload["plans"]["backlog"].append({"slug": p["slug"], "mode": None})
    for i in snap["issues"]:
        if i["queue"]["column"] == mod.COMPLETED_COLUMN:
            continue
        payload["issues"]["backlog"].append(i["number"])
    sim.apply_queue(payload)
    fast_forward(sim, 500)
    snap = sim.build_snapshot()
    if not snap["branches"] and not snap["worktrees"]:
        ok("(e) non-worked items produce NO branch and NO worktree")
    else:
        bad("(e) phantom branches/worktrees for unworked items",
            "branches=%d worktrees=%d" % (len(snap["branches"]), len(snap["worktrees"])))
    if not snap["activity"]:
        ok("(e) non-worked items produce NO activity entries")
    else:
        bad("(e) phantom activity for unworked items",
            "count=%d" % len(snap["activity"]))

    # ------------------------------------------------------------------
    # (lifecycle f) landing_modes include a mix (not all null).
    # ------------------------------------------------------------------
    sim = mod.Simulation(seed=15, concurrency=3)
    sim.build_snapshot()
    fast_forward(sim, 10000)  # ensure all 20 plans arrived
    snap = sim.build_snapshot()
    modes = [p["landing_mode"] for p in snap["plans"]]
    distinct = set(modes)
    has_phase = "phase" in distinct
    has_finish = "finish" in distinct
    has_null = None in distinct
    all_null = all(m is None for m in modes)
    if has_phase and has_finish and has_null and not all_null:
        ok("(f) landing_modes are a realistic mix (phase + finish + some null)")
    else:
        bad("(f) landing_modes not a proper mix",
            "distinct=%s n=%d" % (distinct, len(modes)))

    # ==================================================================
    # EASTER-EGG + OVERACHIEVER CASES (#3/#4/#5).
    # ==================================================================

    def drag_all_to(snap, columns):
        """Build a full-board /api/queue payload placing each non-completed
        plan into columns[slug] (default 'backlog') and every issue into
        'backlog'. Returns the payload dict."""
        pl = {c: [] for c in mod.PLAN_DRAG_COLUMNS}
        iss = {c: [] for c in mod.ISSUE_DRAG_COLUMNS}
        for p in snap["plans"]:
            if p["queue"]["column"] == mod.COMPLETED_COLUMN:
                continue
            pl[columns.get(p["slug"], "backlog")].append(
                {"slug": p["slug"], "mode": None})
        for i in snap["issues"]:
            if i["queue"]["column"] == mod.COMPLETED_COLUMN:
                continue
            iss["backlog"].append(i["number"])
        return {"plans": pl, "issues": iss}

    def work_to_completion(sim, slugs):
        """Drag the given plan slugs to Ready and fast-forward until all of
        them are completed (everything else parked in backlog). Concurrency is
        the sim's cap; we loop fast-forwarding past each batch's work."""
        for _ in range(40):  # generous bound
            snap = sim.build_snapshot()
            remaining = [s for s in slugs if not sim._by_slug[s].completed]
            if not remaining:
                return snap
            cols = {s: "ready" for s in remaining}
            sim.apply_queue(drag_all_to(snap, cols))
            sim.build_snapshot()  # let claims attach
            # Fast-forward past the longest possible work duration.
            maxd = max(it.work_duration for it in sim._all_items())
            fast_forward(sim, maxd + 5)
        return sim.build_snapshot()

    # (eg1) The two easter-egg plans are seeded in Backlog/Discarded at the
    # anchored t=0 with the right titles + blurbs, and are NOT in the timed
    # arrival set (arrive_at == 0).
    sim = mod.Simulation(seed=21, concurrency=3)
    snap = sim.build_snapshot()  # anchor at t=0
    egg_by_slug = {p["slug"]: p for p in snap["plans"]
                   if p["slug"] in set(mod.EASTER_EGG_SLUGS)}
    tou = egg_by_slug.get("take-over-the-universe")
    asol = egg_by_slug.get("adjust-the-speed-of-light")
    if (tou and tou["title"] == "Take Over the Universe"
            and tou["queue"]["column"] == "backlog"
            and "speed of light got in the way" in tou["blurb"]):
        ok("(eg1) 'Take Over the Universe' seeded in Backlog with right title/blurb")
    else:
        bad("(eg1) Take Over the Universe seed wrong",
            "obj=%s" % tou)
    if (asol and asol["title"] == "Adjust the Speed of Light"
            and asol["queue"]["column"] == "discarded"
            and "Unblocks: Take Over the Universe" in asol["blurb"]):
        ok("(eg1) 'Adjust the Speed of Light' seeded in Discarded with right title/blurb")
    else:
        bad("(eg1) Adjust the Speed of Light seed wrong",
            "obj=%s" % asol)
    # NOT in the timed-arrival set: arrive_at must be exactly 0.0.
    eggs = [it for it in sim.plans if it.is_easter_egg]
    if eggs and all(it.arrive_at == 0.0 for it in eggs):
        ok("(eg1) easter eggs are seeded (arrive_at==0), not timed arrivals")
    else:
        bad("(eg1) easter eggs have non-zero arrive_at",
            "arrive_ats=%s" % [it.arrive_at for it in eggs])
    # And they must be present at t=0 (snapshot at elapsed 0) — already shown
    # above since they appeared in the t=0 snapshot.

    # (eg2) The demo object exposes the overachiever flags.
    d0 = snap["demo"]
    if ("core_cleared" in d0 and "easter_eggs_completed" in d0
            and "overachiever" in d0):
        ok("(eg2) demo object exposes core_cleared/easter_eggs_completed/overachiever")
    else:
        bad("(eg2) demo object missing overachiever flags",
            "keys=%s" % sorted(d0.keys()))
    if (d0["core_cleared"] is False and d0["easter_eggs_completed"] is False
            and d0["overachiever"] is False):
        ok("(eg2) at t=0 all overachiever flags are False")
    else:
        bad("(eg2) overachiever flags not all False at t=0",
            "core=%s eggs=%s oa=%s" % (d0["core_cleared"],
                                       d0["easter_eggs_completed"],
                                       d0["overachiever"]))

    # (eg3) Completing core-only sets core_cleared but NOT overachiever.
    sim = mod.Simulation(seed=22, concurrency=4)
    sim.build_snapshot()       # anchor
    fast_forward(sim, 10000)   # all (incl. eggs) arrived
    sim.build_snapshot()
    core_slugs = [it.slug for it in sim.plans if not it.is_easter_egg]
    work_to_completion(sim, core_slugs)
    # Also work all core issues to completion.
    for _ in range(40):
        snap = sim.build_snapshot()
        rem_iss = [it.number for it in sim.issues if not it.completed]
        if not rem_iss:
            break
        pl = {c: [] for c in mod.PLAN_DRAG_COLUMNS}
        iss = {c: [] for c in mod.ISSUE_DRAG_COLUMNS}
        for p in snap["plans"]:
            if p["queue"]["column"] == mod.COMPLETED_COLUMN:
                continue
            # keep eggs parked in backlog (do NOT complete them here)
            pl["backlog"].append({"slug": p["slug"], "mode": None})
        for i in snap["issues"]:
            if i["queue"]["column"] == mod.COMPLETED_COLUMN:
                continue
            iss["ready"].append(i["number"])
        sim.apply_queue({"plans": pl, "issues": iss})
        sim.build_snapshot()
        maxd = max(it.work_duration for it in sim._all_items())
        fast_forward(sim, maxd + 5)
    snap = sim.build_snapshot()
    d = snap["demo"]
    eggs_done = all(it.completed for it in sim.plans if it.is_easter_egg)
    if d["core_cleared"] is True and eggs_done is False:
        ok("(eg3) core completed (eggs untouched): core_cleared True")
    else:
        bad("(eg3) core not cleared with eggs untouched",
            "core_cleared=%s eggs_done=%s" % (d["core_cleared"], eggs_done))
    if d["easter_eggs_completed"] is False and d["overachiever"] is False:
        ok("(eg3) eggs untouched => easter_eggs_completed False, overachiever False")
    else:
        bad("(eg3) overachiever tripped without eggs",
            "eggs=%s oa=%s" % (d["easter_eggs_completed"], d["overachiever"]))

    # (eg4) Completing core + BOTH eggs sets overachiever True.
    sim = mod.Simulation(seed=23, concurrency=4)
    sim.build_snapshot()
    fast_forward(sim, 10000)
    sim.build_snapshot()
    all_plan_slugs = [it.slug for it in sim.plans]  # includes both eggs
    work_to_completion(sim, all_plan_slugs)
    # Work all issues too.
    for _ in range(40):
        snap = sim.build_snapshot()
        rem_iss = [it.number for it in sim.issues if not it.completed]
        rem_plan = [it.slug for it in sim.plans if not it.completed]
        if not rem_iss and not rem_plan:
            break
        pl = {c: [] for c in mod.PLAN_DRAG_COLUMNS}
        iss = {c: [] for c in mod.ISSUE_DRAG_COLUMNS}
        for p in snap["plans"]:
            if p["queue"]["column"] == mod.COMPLETED_COLUMN:
                continue
            pl["ready"].append({"slug": p["slug"], "mode": None})
        for i in snap["issues"]:
            if i["queue"]["column"] == mod.COMPLETED_COLUMN:
                continue
            iss["ready"].append(i["number"])
        sim.apply_queue({"plans": pl, "issues": iss})
        sim.build_snapshot()
        maxd = max(it.work_duration for it in sim._all_items())
        fast_forward(sim, maxd + 5)
    snap = sim.build_snapshot()
    d = snap["demo"]
    if d["core_cleared"] is True and d["easter_eggs_completed"] is True:
        ok("(eg4) core + both eggs completed (core_cleared + easter_eggs_completed)")
    else:
        bad("(eg4) core/eggs not all completed",
            "core=%s eggs=%s" % (d["core_cleared"], d["easter_eggs_completed"]))
    if d["overachiever"] is True:
        ok("(eg4) overachiever True when core cleared AND both eggs completed")
    else:
        bad("(eg4) overachiever not set with everything completed",
            "oa=%s" % d["overachiever"])

    print("")
    print("Results: %d passed, %d failed (of %d)" % (PASS, FAIL, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
