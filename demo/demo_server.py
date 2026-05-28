#!/usr/bin/env python3
"""Z Skills Dashboard — Interactive Demo Server.

A standalone demo that serves the real dashboard frontend backed by a
*stateful, user-driven* simulation. Unlike the old auto-player, this demo
does NO autonomous column movement except:

  1. Arrivals: new sci-fi-themed work appears over time (issues land in
     Triage, plans land in Drafted) — the only "new card appears" motion.
  2. Worked Ready items: an item the user drags into Ready becomes
     eligible to be worked. At most --concurrency items are in-flight at
     once (default 3); each in-flight item shows a claim chip, ticks its
     phases, and after a timely period (~20-45s) auto-advances to
     Completed — the ONLY column transition the sim performs.

Everything else (Triage / Drafted / Reviewed / Backlog / Discarded) is
driven entirely by the user dragging cards. Drags PERSIST: the server
holds mutable board state and applies /api/queue POSTs to it, so the next
/api/state poll reflects the user's placement (no snap-back).

When the board is cleared (all arrived items reached Completed), the
victory overlay fires.

    python3 demo/demo_server.py [--port PORT] [--seed N] [--concurrency N]

No external dependencies — Python 3 stdlib only.
"""

import argparse
import json
import pathlib
import random
import sys
import threading
import time
from datetime import datetime, timezone, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

DEMO_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = DEMO_DIR.parent
STATIC_DIR = REPO_ROOT / "skills" / "zskills-dashboard" / "scripts" / "zskills_monitor" / "static"

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

# At most this many Ready items are "worked" (in-flight) at once. Extra
# Ready items wait — no claim chip — until a slot frees up.
DEFAULT_CONCURRENCY = 3

# Each in-flight item takes a timely period to complete so the lifecycle
# is visible: roughly WORK_DURATION_BASE +/- WORK_DURATION_VARIANCE seconds.
WORK_DURATION_BASE = 32        # seconds (lands ~20-45s with the variance)
WORK_DURATION_VARIANCE = 13

# Arrival cadence. There are 20 items total (10 plans + 10 issues). Two of
# them (one plan + one issue) are SEEDED at the anchored t=0 so the board is
# never empty. The remaining 18 arrive across ~5 minutes. With an average
# gap of ARRIVAL_GAP_BASE seconds that lands the last item at
# ~18 * 15s ≈ 270s, comfortably inside the window. Keep some randomness via
# the variance so arrivals don't look metronomic.
ARRIVAL_WINDOW_SECONDS = 300   # all 20 arrive within ~5 minutes
ARRIVAL_GAP_BASE = 15          # ~every 6-24s with the variance below
ARRIVAL_GAP_VARIANCE = 9
FIRST_ARRIVAL_DELAY = 0        # the seeded pair is present at t=0

# Real-frontend column shapes (mirror server.py's PLAN_COLUMNS /
# ISSUE_COLUMNS — `completed` is read-only, NOT in the POST body).
PLAN_DRAG_COLUMNS = ("drafted", "reviewed", "ready", "backlog", "discarded")
ISSUE_DRAG_COLUMNS = ("triage", "ready", "backlog")
PLAN_ARRIVAL_COLUMN = "drafted"
ISSUE_ARRIVAL_COLUMN = "triage"
READY_COLUMN = "ready"
COMPLETED_COLUMN = "completed"

# Branch + Recent-Activity lifecycle. Branches/worktrees/activity track ONLY
# actual in-flight + completed work (items the user dragged to Ready that got
# claimed). The activity feed is newest-first and bounded (the real collector
# caps in memory at 200; the UI renders the first 20).
ACTIVITY_CAP = 200
WORKTREE_BASE = "/starship/.worktrees"
LANDED_STATUS = "landed"  # canonical pill (Sampler set); classifyBranch -> "landed" bucket

# Realistic mix of plan landing_modes (#5). Most plans DON'T pin a mode —
# it's inherited from the session — so the realistic shape is mostly None
# (the absence of an override) with only a couple of explicit overrides.
# Index-aligned to the 10 PLAN_DEFS below.
PLAN_LANDING_MODES = [
    None, "phase", None, None, "finish",
    None, None, None, None, None,
]

# Easter-egg plans (#3/#4). These are NOT part of the timed-arrival schedule:
# they are SEEDED at the anchored t=0 in fixed columns (one in Backlog, one in
# Discarded). They are otherwise normal, workable plans — drag them to the
# Ready-key column ("Accepted" for plans) and they get worked like any plan.
# Completing BOTH (on top of the core board being cleared) trips the
# "overachiever" overlay (#5).
EASTER_EGG_DEFS = [
    # (slug, title, blurb, seed_column, phase_defs, landing_mode)
    ("take-over-the-universe", "Take Over the Universe",
     "Blocked — the speed of light got in the way.", "backlog", [
         "Assemble shadow council",
         "Acquire controlling stake in every shipyard",
         "Issue the galaxy-wide memo",
     ], "finish"),
    ("adjust-the-speed-of-light", "Adjust the Speed of Light",
     "Unblocks: Take Over the Universe.", "discarded", [
         "Petition the laws of physics",
         "Retune the fine-structure constant",
         "Re-baseline every clock in the fleet",
     ], "phase"),
]
EASTER_EGG_SLUGS = tuple(d[0] for d in EASTER_EGG_DEFS)

# ---------------------------------------------------------------------------
# Sci-fi content
# ---------------------------------------------------------------------------

PLAN_DEFS = [
    ("repair-hyperdrive-coupling", "Repair Hyperdrive Coupling", [
        "Diagnose harmonic resonance drift",
        "Replace flux capacitor array",
        "Calibrate thrust vectoring",
    ]),
    ("tachyon-anomaly-investigation", "Investigate Anomalous Tachyon Readings", [
        "Deploy sensor grid to sectors 7-12",
        "Correlate readings with stellar cartography",
        "Draft containment protocol",
        "Peer review with Science Division",
    ]),
    ("hull-breach-deck-7", "Patch Hull Breach in Deck 7", [
        "Emergency atmospheric seal",
        "Structural integrity field reinforcement",
        "Full hull plate replacement",
    ]),
    ("ai-core-alignment-audit", "AI Core Alignment Audit", [
        "Dump personality matrix logs",
        "Cross-reference with ethics subroutine v4.2",
        "Patch value-drift regression",
        "Run full alignment battery",
    ]),
    ("nebula-navigation-charts", "Update Nebula Navigation Charts", [
        "Scan Helix Nebula boundary shifts",
        "Recalculate safe transit corridors",
        "Distribute updated charts to fleet",
    ]),
    ("shields-harmonics-overhaul", "Shield Harmonics Overhaul", [
        "Benchmark current shield modulation",
        "Install phase-variant emitter array",
        "Stress-test against simulated plasma torpedoes",
    ]),
    ("crew-stasis-pod-maintenance", "Crew Stasis Pod Maintenance Cycle", [
        "Drain and clean bio-gel reservoirs",
        "Recalibrate neural induction coils",
        "Run occupant simulation health checks",
    ]),
    ("quantum-comm-relay-upgrade", "Quantum Comm Relay Upgrade", [
        "Decommission legacy subspace antenna",
        "Install entanglement pair buffers",
        "Validate zero-latency handshake",
        "Cut over from subspace to quantum",
    ]),
    ("asteroid-mining-drone-swarm", "Deploy Asteroid Mining Drone Swarm", [
        "Manufacture drone chassis batch",
        "Program swarm coordination AI",
        "Field test in Kuiper belt analog",
    ]),
    ("holodeck-physics-engine", "Holodeck Physics Engine Rewrite", [
        "Profile existing fluid dynamics module",
        "Implement SPH solver in ship-local coordinates",
        "Validate gravity simulation accuracy",
    ]),
    ("stellar-cartography-3d-map", "Stellar Cartography 3D Map Renderer", [
        "Parse galactic coordinate feeds",
        "Build real-time WebGL star renderer",
        "Add interactive sector overlays",
    ]),
]

ISSUE_DEFS = [
    (101, "Plasma conduit leak in main engineering"),
    (102, "Navigation array returns NaN for subspace coordinates"),
    (103, "Turbolift stuck between decks 5 and 6"),
    (104, "Replicator produces Earl Grey at wrong temperature"),
    (105, "Inertial dampeners lag 200ms during course corrections"),
    (106, "Holodeck safety protocols intermittently disabled"),
    (107, "Phaser bank 3 fires 15 degrees off target"),
    (108, "Universal translator garbles Andorian sibilants"),
    (109, "Shuttle bay doors report closed when open"),
    (110, "Crew quarters lighting stuck on red alert spectrum"),
]


# ---------------------------------------------------------------------------
# Simulation engine
# ---------------------------------------------------------------------------


def _iso(dt):
    return dt.isoformat()


def _ago_iso(seconds):
    """ISO timestamp `seconds` in the past (clamped to >= 0)."""
    return _iso(datetime.now(timezone.utc) - timedelta(seconds=max(0.0, seconds)))


class PlanItem:
    """A simulated plan. Lifecycle is entirely user-driven except work."""

    __slots__ = ("slug", "title", "phase_defs", "arrive_at",
                 "column", "arrived", "completed", "completed_at_elapsed",
                 "started_at_elapsed", "work_duration", "pipeline_id",
                 "landing_mode", "emitted", "is_easter_egg", "blurb",
                 "seed_column")

    def __init__(self, slug, title, phase_defs, arrive_at, rng,
                 landing_mode=None, is_easter_egg=False, blurb=None,
                 seed_column=None):
        self.slug = slug
        self.title = title
        self.phase_defs = phase_defs
        self.arrive_at = arrive_at
        # Easter-egg bookkeeping (#3/#4/#5). is_easter_egg flags the two
        # seeded-but-off-schedule plans; seed_column is the fixed column they
        # appear in at t=0; blurb overrides the generic plan blurb.
        self.is_easter_egg = is_easter_egg
        self.blurb = blurb
        self.seed_column = seed_column
        # column is None until the item arrives; then it sits in `drafted`
        # until the user moves it. The sim never moves it except to
        # `completed` when work finishes.
        self.column = None
        self.arrived = False
        self.completed = False
        self.completed_at_elapsed = None
        # In-flight bookkeeping (None unless currently being worked).
        self.started_at_elapsed = None
        self.work_duration = (WORK_DURATION_BASE
                              + rng.randint(-WORK_DURATION_VARIANCE,
                                            WORK_DURATION_VARIANCE))
        self.pipeline_id = "run-plan.demo-%04d" % rng.randint(1000, 9999)
        self.landing_mode = landing_mode
        # Set of lifecycle phase keys already emitted to the activity feed
        # (so each transition emits exactly once): "claimed","implement",
        # "verify","landed".
        self.emitted = set()

    # -- branch / worktree identity (only meaningful once worked) --------
    @property
    def branch_name(self):
        return "feat/%s" % self.slug

    @property
    def worktree_path(self):
        return "%s/feat-%s" % (WORKTREE_BASE, self.slug)

    @property
    def activity_skill(self):
        return "run-plan"

    @property
    def kind(self):
        return "plan"

    @property
    def id_key(self):
        return self.slug

    @property
    def in_flight(self):
        return self.started_at_elapsed is not None and not self.completed


class IssueItem:
    """A simulated GitHub issue. Same lifecycle model as PlanItem."""

    __slots__ = ("number", "title", "arrive_at",
                 "column", "arrived", "completed", "completed_at_elapsed",
                 "started_at_elapsed", "work_duration", "pipeline_id",
                 "emitted")

    def __init__(self, number, title, arrive_at, rng):
        self.number = number
        self.title = title
        self.arrive_at = arrive_at
        self.column = None
        self.arrived = False
        self.completed = False
        self.completed_at_elapsed = None
        self.started_at_elapsed = None
        self.work_duration = (WORK_DURATION_BASE
                              + rng.randint(-WORK_DURATION_VARIANCE,
                                            WORK_DURATION_VARIANCE))
        self.pipeline_id = "fix-issues.demo-%04d" % rng.randint(1000, 9999)
        self.emitted = set()

    # -- branch / worktree identity (only meaningful once worked) --------
    @property
    def branch_name(self):
        return "fix/issue-%d" % self.number

    @property
    def worktree_path(self):
        return "%s/fix-issue-%d" % (WORKTREE_BASE, self.number)

    @property
    def activity_skill(self):
        return "fix-issues"

    @property
    def kind(self):
        return "issue"

    @property
    def id_key(self):
        return self.number

    @property
    def in_flight(self):
        return self.started_at_elapsed is not None and not self.completed


class Simulation:
    """Stateful, user-driven board simulation.

    State the server owns:
      * per-item placement (`item.column`) — mutated by /api/queue POSTs
      * arrival schedule — drives the only "new card appears" motion
      * in-flight set + completion — the only sim-driven column transition
    """

    def __init__(self, seed=None, concurrency=DEFAULT_CONCURRENCY):
        # The simulation clock is LAZILY anchored: it does NOT start at
        # construction. `start_time` stays None until the FIRST /api/state
        # request (build_snapshot) anchors it via _anchor(). This lets the
        # server sit idle indefinitely — opening the dashboard begins the
        # timeline from t=0. /api/health does NOT anchor.
        self.start_time = None
        self.rng = random.Random(seed if seed is not None else int(time.time()))
        self.concurrency = concurrency
        self.lock = threading.Lock()
        self.plans = []
        self.issues = []
        self._by_slug = {}
        self._by_number = {}
        # Recent Activity feed: list of records (newest-first when emitted in
        # increasing-elapsed order then reversed at snapshot time). We append
        # in chronological order and store the elapsed-at so timestamps are
        # relative to the anchored clock.
        self._activity = []  # list of (elapsed_at, record-without-timestamp)
        self._init_items()

    def _init_items(self):
        # Interleave plan and issue arrivals on a single staggered timeline so
        # both kinds show up. Exactly one plan + one issue are SEEDED at the
        # anchored t=0 (arrive_at == 0) so the board is never empty. The
        # remaining 18 arrive across ~ARRIVAL_WINDOW_SECONDS with an average
        # gap of ARRIVAL_GAP_BASE +/- variance.
        plan_defs = list(PLAN_DEFS)
        issue_defs = list(ISSUE_DEFS)

        # Pick the seed pair (deterministic under --seed): first of each after
        # a shuffle, so it isn't always the same content.
        self.rng.shuffle(plan_defs)
        self.rng.shuffle(issue_defs)

        seed_plan = plan_defs[0]
        seed_issue = issue_defs[0]

        defs = []
        # Seeded pair: arrive_at == 0 (present at the anchored t=0).
        defs.append(("plan", seed_plan[0], seed_plan[1], seed_plan[2], 0.0))
        defs.append(("issue", seed_issue[0], seed_issue[1], None, 0.0))

        # The rest arrive on a staggered timeline starting just after t=0.
        rest = ([("plan", s, t, ph) for s, t, ph in plan_defs[1:]]
                + [("issue", n, t, None) for n, t in issue_defs[1:]])
        self.rng.shuffle(rest)

        t = float(FIRST_ARRIVAL_DELAY)
        for kind, a, b, c in rest:
            gap = ARRIVAL_GAP_BASE + self.rng.randint(-ARRIVAL_GAP_VARIANCE,
                                                       ARRIVAL_GAP_VARIANCE)
            gap = max(1, gap)
            t += gap
            defs.append((kind, a, b, c, t))

        # Map each plan slug to its landing_mode via the original PLAN_DEFS
        # order so the mix is stable per slug regardless of arrival shuffle.
        mode_by_slug = {
            slug: PLAN_LANDING_MODES[i % len(PLAN_LANDING_MODES)]
            for i, (slug, _t, _ph) in enumerate(PLAN_DEFS)
        }

        for kind, a, b, c, arrive_at in defs:
            if kind == "plan":
                item = PlanItem(a, b, c, arrive_at, self.rng,
                                landing_mode=mode_by_slug.get(a))
                self.plans.append(item)
                self._by_slug[a] = item
            else:
                item = IssueItem(a, b, arrive_at, self.rng)
                self.issues.append(item)
                self._by_number[a] = item

        # Easter-egg plans (#3/#4): seeded at the anchored t=0 in fixed
        # columns, OFF the timed-arrival schedule (arrive_at == 0). They are
        # normal workable plans otherwise.
        for slug, title, blurb, seed_column, phase_defs, mode in EASTER_EGG_DEFS:
            egg = PlanItem(slug, title, phase_defs, 0.0, self.rng,
                           landing_mode=mode, is_easter_egg=True,
                           blurb=blurb, seed_column=seed_column)
            self.plans.append(egg)
            self._by_slug[slug] = egg

    def _anchor(self):
        """Start the simulation clock on the first /api/state request.

        Idempotent: subsequent calls do NOT reset the clock, so ongoing polls
        never rewind the timeline. Caller must hold self.lock OR call before
        any concurrent access (build_snapshot holds the lock around tick/build,
        but anchoring itself is a cheap monotonic read)."""
        if self.start_time is None:
            self.start_time = time.monotonic()

    def elapsed(self):
        # Before the clock is anchored, no time has passed (t=0 / nothing
        # arrived). After anchoring, elapsed is measured from the anchor.
        if self.start_time is None:
            return 0.0
        return time.monotonic() - self.start_time

    # -- core tick -----------------------------------------------------

    def tick(self):
        """Advance arrivals and worked-item completion. Caller must NOT
        hold self.lock (this acquires it)."""
        with self.lock:
            self._tick_locked(self.elapsed())

    def _tick_locked(self, elapsed):
        # 1. Arrivals — new cards appear in their arrival column.
        for item in self._all_items():
            if not item.arrived and elapsed >= item.arrive_at:
                item.arrived = True
                if getattr(item, "is_easter_egg", False) and item.seed_column:
                    # Easter eggs land in their fixed seed column (Backlog /
                    # Discarded), not the default arrival column.
                    item.column = item.seed_column
                elif item.kind == "plan":
                    item.column = PLAN_ARRIVAL_COLUMN
                else:
                    item.column = ISSUE_ARRIVAL_COLUMN

        # 2. Complete any in-flight item whose work duration has elapsed.
        for item in self._all_items():
            if item.in_flight:
                age = elapsed - item.started_at_elapsed
                if age >= item.work_duration:
                    item.completed = True
                    item.completed_at_elapsed = elapsed
                    item.started_at_elapsed = None
                    item.column = COMPLETED_COLUMN
                    # Lifecycle: verify pass + land/merge entries.
                    self._emit(item, "verify", elapsed)
                    self._emit(item, "landed", elapsed)

        # 3. Fill free concurrency slots from waiting Ready items.
        #    "Waiting" = arrived, in Ready, not completed, not yet started.
        in_flight = [it for it in self._all_items() if it.in_flight]
        free = self.concurrency - len(in_flight)
        if free > 0:
            waiting = [it for it in self._all_items()
                       if it.arrived and not it.completed
                       and not it.in_flight
                       and it.column == READY_COLUMN]
            # Deterministic, fair-ish: oldest arrival first.
            waiting.sort(key=lambda it: it.arrive_at)
            for it in waiting[:free]:
                it.started_at_elapsed = elapsed
                # Lifecycle: a claim was just acquired — emit branch creation
                # + the implement phase start.
                self._emit(it, "claimed", elapsed)
                self._emit(it, "implement", elapsed)

    # -- activity feed --------------------------------------------------

    # Lifecycle phase -> (kind, status) shaping. `kind` mirrors the real
    # tracking-marker `kind` vocabulary; status drives activityStatusClass().
    _PHASE_SHAPE = {
        "claimed":   ("claimed", "running"),
        "implement": ("implement", "running"),
        "verify":    ("verify", "pass"),
        "landed":    ("land-pr", "complete"),
    }

    def _emit(self, item, phase, elapsed):
        """Append a Recent-Activity record for a work-lifecycle transition.

        Emits each phase at most once per item (guarded by item.emitted), so
        only ACTUAL in-flight/completed work produces activity. Records are
        shaped like the real collector's tracking-marker rows (timestamp,
        pipeline, kind, id, skill, status, output, location, parent)."""
        if phase in item.emitted:
            return
        item.emitted.add(phase)
        kind, status = self._PHASE_SHAPE[phase]
        ident = item.slug if item.kind == "plan" else str(item.number)
        if phase == "landed":
            output = "merged %s to main" % item.branch_name
        elif phase == "claimed":
            output = "claimed; created %s" % item.branch_name
        elif phase == "implement":
            output = "implementing on %s" % item.branch_name
        else:
            output = "verification %s on %s" % (status, item.branch_name)
        self._activity.append((elapsed, {
            "pipeline": item.pipeline_id,
            "kind": kind,
            "id": ident,
            "skill": item.activity_skill,
            "status": status,
            "output": output,
            "location": "pipeline",
            "parent": None,
        }))
        # Bound the log (newest kept). Activity is appended chronologically;
        # cap from the tail so the most-recent ACTIVITY_CAP survive.
        if len(self._activity) > ACTIVITY_CAP:
            self._activity = self._activity[-ACTIVITY_CAP:]

    def _all_items(self):
        for it in self.plans:
            yield it
        for it in self.issues:
            yield it

    # -- queue POST application ----------------------------------------

    def apply_queue(self, payload):
        """Adopt a /api/queue payload as the new board placement.

        Mirrors the real server's contract: the body carries `plans`
        (drafted/reviewed/ready/backlog/discarded) and `issues`
        (triage/ready/backlog). `completed` is read-only and NOT in the
        body — the sim owns it, so we never touch a completed item here.
        Items the user dragged INTO `completed` cannot exist (frontend
        strips it); items the user tries to drag OUT of completed simply
        won't appear in the payload, and we leave them completed.

        An in-flight item that the user moves OUT of Ready stops being
        worked (its claim is released on the next tick because the
        column check fails) — but per the spec the frontend disables
        dragging claimed cards, so in practice this only fires if a stale
        payload races. We defensively release the claim in that case.
        """
        with self.lock:
            self._apply_queue_locked(payload)

    def _apply_queue_locked(self, payload):
        plans = payload.get("plans", {}) or {}
        issues = payload.get("issues", {}) or {}

        # Plans: adopt the user's column for every slug present in the
        # body. Never override a completed item (sim-owned).
        for col in PLAN_DRAG_COLUMNS:
            entries = plans.get(col, []) or []
            for entry in entries:
                slug = entry.get("slug") if isinstance(entry, dict) else entry
                item = self._by_slug.get(slug)
                if item is None or item.completed:
                    continue
                self._place(item, col)

        # Issues: same, but entries are bare ints.
        for col in ISSUE_DRAG_COLUMNS:
            entries = issues.get(col, []) or []
            for num in entries:
                item = self._by_number.get(num)
                if item is None or item.completed:
                    continue
                self._place(item, col)

    def _place(self, item, col):
        if item.column == col:
            return
        # Moving out of Ready releases an in-flight claim (slot frees up).
        if item.in_flight and col != READY_COLUMN:
            item.started_at_elapsed = None
        item.column = col

    # -- progress / victory --------------------------------------------

    def _is_egg(self, it):
        return getattr(it, "is_easter_egg", False)

    def all_completed(self):
        """Core board cleared: every ARRIVED non-easter-egg item is completed.

        Easter eggs are excluded so the standard victory overlay fires on the
        core board regardless of whether the eggs were worked. The overachiever
        path (which requires the eggs too) layers on top via overachiever()."""
        arrived = [it for it in self._all_items()
                   if it.arrived and not self._is_egg(it)]
        if not arrived:
            return False
        return all(it.completed for it in arrived)

    def easter_eggs_completed(self):
        """Both easter-egg plans dragged through to Completed."""
        eggs = [it for it in self.plans if self._is_egg(it)]
        if len(eggs) < len(EASTER_EGG_DEFS):
            return False
        return all(it.completed for it in eggs)

    def overachiever(self):
        """Core board cleared AND both easter eggs completed."""
        return self.all_completed() and self.easter_eggs_completed()

    def progress(self):
        """Core progress (done, total) over arrived non-easter-egg items."""
        arrived = [it for it in self._all_items()
                   if it.arrived and not self._is_egg(it)]
        done = sum(1 for it in arrived if it.completed)
        return done, len(arrived)

    # -- snapshot ------------------------------------------------------

    def build_snapshot(self):
        # /api/state is the ONLY caller — anchor the clock here on first call.
        self._anchor()
        self.tick()
        with self.lock:
            return self._build_snapshot_locked(self.elapsed())

    def _build_snapshot_locked(self, elapsed):
        now_iso = _iso(datetime.now(timezone.utc))

        plans_list = []
        plan_queues = {c: [] for c in PLAN_DRAG_COLUMNS}
        plan_queues[COMPLETED_COLUMN] = []

        for item in self.plans:
            if not item.arrived:
                continue
            col = item.column
            phase_defs = item.phase_defs

            # Phase ticking: only in-flight (worked) plans show progress.
            if item.completed:
                phases_done = len(phase_defs)
            elif item.in_flight:
                age = elapsed - item.started_at_elapsed
                frac = min(1.0, age / max(1.0, item.work_duration))
                # At least 1 phase visibly done once work starts.
                phases_done = max(1, int(frac * len(phase_defs)))
                phases_done = min(phases_done, len(phase_defs) - 1) \
                    if len(phase_defs) > 1 else phases_done
            else:
                phases_done = 0

            phases = []
            for pi, pname in enumerate(phase_defs):
                done = pi < phases_done
                phases.append({
                    "n": str(pi + 1),
                    "name": "%d -- %s" % (pi + 1, pname),
                    "status": "done" if done else "pending",
                    "commit": "%07x" % self.rng.randint(0, 0xFFFFFFF) if done else None,
                    "notes": "Completed successfully" if done else "",
                })

            status = "complete" if item.completed else "active"
            completed_dt = None
            created_dt = _ago_iso(elapsed - item.arrive_at)[:10]
            if item.completed:
                completed_dt = _ago_iso(elapsed - item.completed_at_elapsed)

            idx = len(plan_queues[col])
            if col == COMPLETED_COLUMN:
                plan_queues[col].append(item.slug)
            else:
                plan_queues[col].append({"slug": item.slug, "mode": None})

            plan_obj = {
                "slug": item.slug,
                "file": "docs/plans/%s.md" % item.slug.upper().replace("-", "_"),
                "title": item.title,
                "status": status,
                "created": created_dt,
                "completed": completed_dt,
                "issue": None,
                "blurb": (item.blurb if item.blurb is not None
                          else "Starship maintenance task: %s" % item.title.lower()),
                "phase_count": len(phase_defs),
                "phases_done": phases_done,
                "phases": phases,
                "category": None,
                "meta_plan": None,
                "sub_plans": None,
                "landing_mode": item.landing_mode,
                "has_report": False,
                "report_path": None,
                "report": None,
                "queue": {"column": col, "index": idx, "mode": None},
            }

            # Claim chip ONLY on in-flight Ready plans.
            if item.in_flight:
                age = elapsed - item.started_at_elapsed
                plan_obj["claim"] = {
                    "pipeline_id": item.pipeline_id,
                    "sprint_id": None,
                    "current_phase": "Phase %d" % (phases_done + 1),
                    "age_seconds": round(age, 1),
                    "started_at": _ago_iso(age),
                    "pipeline_short": item.pipeline_id[-8:],
                }

            plans_list.append(plan_obj)

        issues_list = []
        issue_queues = {c: [] for c in ISSUE_DRAG_COLUMNS}
        issue_queues[COMPLETED_COLUMN] = []

        for item in self.issues:
            if not item.arrived:
                continue
            col = item.column
            idx = len(issue_queues[col])
            issue_queues[col].append(item.number)

            created_dt = _ago_iso(elapsed - item.arrive_at)
            issue_obj = {
                "number": item.number,
                "title": item.title,
                "labels": [],
                "created_at": created_dt,
                "body": "Reported by Engineering: %s" % item.title,
                "queue": {"column": col, "index": idx},
            }

            if item.completed:
                issue_obj["closed_at"] = _ago_iso(elapsed - item.completed_at_elapsed)

            if item.in_flight:
                age = elapsed - item.started_at_elapsed
                issue_obj["claim"] = {
                    "pipeline_id": item.pipeline_id,
                    "sprint_id": "demo-sprint",
                    "age_seconds": round(age, 1),
                    "started_at": _ago_iso(age),
                    "pipeline_short": item.pipeline_id[-8:],
                }

            issues_list.append(issue_obj)

        done, total = self.progress()
        in_flight_count = sum(1 for it in self._all_items() if it.in_flight)

        worktrees, branches = self._build_branches_locked(elapsed)
        activity = self._build_activity_locked(elapsed)

        return {
            "version": "1.0",
            "updated_at": now_iso,
            "state_updated_at": now_iso,
            "repo_root": "/starship/uss-enterprise",
            "repo_url": "",
            "plans": plans_list,
            "issues": issues_list,
            "worktrees": worktrees,
            "branches": branches,
            "activity": activity,
            "queues": {
                "default_mode": "phase",
                "plans": {
                    "drafted": plan_queues["drafted"],
                    "reviewed": plan_queues["reviewed"],
                    "ready": plan_queues["ready"],
                    "backlog": plan_queues["backlog"],
                    "discarded": plan_queues["discarded"],
                    "completed": plan_queues[COMPLETED_COLUMN],
                },
                "issues": {
                    "triage": issue_queues["triage"],
                    "ready": issue_queues["ready"],
                    "backlog": issue_queues["backlog"],
                    "completed": issue_queues[COMPLETED_COLUMN],
                },
            },
            "state_file_path": "(demo mode)",
            "errors": [],
            "issues_fetch_ok": True,
            "flags": {
                "closed_issues_truncated": False,
                "closed_issues_limit": 500,
            },
            "config": {
                "dashboard_completed_days": 14,
            },
            "demo": {
                "active": True,
                "interactive": True,
                "progress_done": done,
                "progress_total": total,
                "in_flight": in_flight_count,
                "concurrency": self.concurrency,
                "all_completed": self.all_completed(),
                # Easter-egg / overachiever flags (#5). core_cleared mirrors
                # all_completed (core board, eggs excluded); the injected JS
                # uses these to choose the standard vs. overachiever overlay.
                "core_cleared": self.all_completed(),
                "easter_eggs_completed": self.easter_eggs_completed(),
                "overachiever": self.overachiever(),
                "easter_egg_slugs": list(EASTER_EGG_SLUGS),
                "elapsed_seconds": round(elapsed, 1),
            },
        }

    # -- branches / worktrees / activity from the work lifecycle --------

    def _worked_items(self):
        """Items that have entered the work lifecycle (claimed at least once).

        These are exactly the items that produced a branch + worktree +
        activity. Items still in Triage/Drafted/Backlog/Discarded, or waiting
        in Ready beyond the concurrency cap, never get `claimed` emitted and
        so produce NO branch and NO activity."""
        for it in self._all_items():
            if "claimed" in it.emitted:
                yield it

    def _build_branches_locked(self, elapsed):
        """Build worktrees[] + branches[] for in-flight/completed work only.

        Shapes mirror the real collector (collect.py _list_worktrees /
        _list_branches). classifyBranch keys on the worktree association:
          * worked + not completed -> worktree.landed = None -> "active"
          * completed              -> worktree.landed = {status} -> "landed"
        """
        worktrees = []
        branches = []
        for it in self._worked_items():
            name = it.branch_name
            # When did this branch's last commit happen? Completion time if
            # completed, else when work started (claim time). Express relative
            # to the anchored clock.
            if it.completed:
                last_at = elapsed - (it.completed_at_elapsed or elapsed)
                subject = ("land-pr: merged %s" % name if it.kind == "plan"
                           else "fix: %s" % it.title)
            else:
                started = it.started_at_elapsed if it.started_at_elapsed is not None else elapsed
                last_at = elapsed - started
                subject = ("wip: %s" % it.title)
            landed = None
            category = "active"
            if it.completed:
                landed = {
                    "status": LANDED_STATUS,
                    "date": _ago_iso(last_at),
                    "source": it.activity_skill,
                }
                category = "landed"
            # age_seconds: how long the worktree has existed (since claim).
            started_for_age = it.started_at_elapsed
            if started_for_age is None and not it.completed:
                started_for_age = elapsed
            if it.completed:
                # No live in-flight start; age from completion baseline.
                age_seconds = int(max(0.0, last_at))
            else:
                age_seconds = int(max(0.0, elapsed - (started_for_age or elapsed)))
            worktrees.append({
                "path": it.worktree_path,
                "branch": name,
                "category": category,
                "landed": landed,
                "ahead": 1 if not it.completed else 0,
                "behind": 0,
                "age_seconds": age_seconds,
            })
            branches.append({
                "name": name,
                "last_commit_at": _ago_iso(last_at),
                "upstream": None,
                "last_commit_subject": subject,
                "locality": "local",
            })
        return worktrees, branches

    def _build_activity_locked(self, elapsed):
        """Recent Activity feed — newest-first, capped, timestamps relative to
        the anchored clock. Built from the chronological _activity log."""
        out = []
        for at, rec in self._activity:
            row = dict(rec)
            row["timestamp"] = _ago_iso(elapsed - at)
            out.append(row)
        # Newest-first (the log is appended chronologically).
        out.reverse()
        return out[:ACTIVITY_CAP]


# ---------------------------------------------------------------------------
# Demo overlay HTML (injected into the served index.html)
# ---------------------------------------------------------------------------

DEMO_OVERLAY_JS = r"""
<script>
(function() {
  var victoryShown = false;
  var overachieverShown = false;
  var banner = document.createElement('div');
  banner.id = 'demo-banner';
  banner.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:9998;'
    + 'background:linear-gradient(135deg,#1a1a2e,#16213e);color:#e0e0ff;'
    + 'text-align:center;padding:8px 16px;font-size:14px;font-family:monospace;'
    + 'border-bottom:2px solid #0f3460;';
  banner.innerHTML = '<span style="color:#e94560">&#9733;</span> '
    + '<strong>Z Skills Dashboard Demo</strong> &mdash; '
    + '<span id="demo-progress">Loading...</span> '
    + '<span style="color:#e94560">&#9733;</span>';
  document.body.prepend(banner);
  document.body.style.paddingTop = '40px';

  // --- DEMO label (#2): plain unobtrusive text in the lower-LEFT corner.
  // Not a button — just a quiet marker. Non-interactive
  // (pointer-events:none), survives re-render (outside the render root).
  var badgeStyle = document.createElement('style');
  badgeStyle.textContent =
    '#demo-badge{position:fixed;left:16px;bottom:12px;z-index:9997;'
    + 'pointer-events:none;font-family:monospace;font-size:12px;'
    + 'letter-spacing:1px;color:rgba(255,255,255,0.4);}';
  document.head.appendChild(badgeStyle);
  var badge = document.createElement('div');
  badge.id = 'demo-badge';
  badge.textContent = 'Demo';
  document.body.appendChild(badge);

  // --- Standard victory overlay (core board cleared).
  var overlay = document.createElement('div');
  overlay.id = 'demo-victory';
  overlay.style.cssText = 'display:none;position:fixed;inset:0;z-index:9999;'
    + 'background:rgba(10,10,30,0.92);justify-content:center;align-items:center;'
    + 'flex-direction:column;font-family:monospace;color:#e0e0ff;';
  overlay.innerHTML = '<div style="text-align:center;max-width:600px;padding:40px;">'
    + '<div style="font-size:72px;margin-bottom:20px;">&#x1F680;</div>'
    + '<h1 style="font-size:36px;color:#e94560;margin:0 0 16px;">Board Cleared</h1>'
    + '<p style="font-size:18px;line-height:1.6;color:#a0a0d0;">You drove every '
    + 'plan and issue through the board to Completed. The starship is fully '
    + 'operational.</p>'
    + '<p style="font-size:14px;color:#606080;margin-top:24px;">This was a demo of the '
    + 'Z&nbsp;Skills Dashboard &mdash; an agent workflow monitor. Drag cards between '
    + 'columns; drop one in Ready to watch it get worked (up to a few at a time). '
    + 'Psst &mdash; there are two extra plans hiding in Backlog and Discarded&hellip;</p>'
    + '<button onclick="document.getElementById(\'demo-victory\').style.display=\'none\'"'
    + ' style="margin-top:24px;padding:10px 32px;font-size:16px;cursor:pointer;'
    + 'background:#e94560;color:white;border:none;border-radius:6px;font-family:monospace;"'
    + '>Dismiss</button></div>';
  document.body.appendChild(overlay);

  // --- Overachiever overlay (#5): core cleared AND both easter eggs done.
  var oa = document.createElement('div');
  oa.id = 'demo-overachiever';
  oa.style.cssText = 'display:none;position:fixed;inset:0;z-index:10000;'
    + 'background:radial-gradient(circle at 50% 40%,#2a1659,#08010f 80%);'
    + 'justify-content:center;align-items:center;'
    + 'flex-direction:column;font-family:monospace;color:#f0e9ff;';
  oa.innerHTML = '<div style="text-align:center;max-width:640px;padding:40px;">'
    + '<div style="font-size:80px;margin-bottom:16px;">&#x1F30C;</div>'
    + '<h1 style="font-size:40px;margin:0 0 16px;'
    + 'background:linear-gradient(90deg,#ffd166,#e94560,#7b2ff7);'
    + '-webkit-background-clip:text;-webkit-text-fill-color:transparent;'
    + 'background-clip:text;">OVERACHIEVER</h1>'
    + '<p style="font-size:20px;line-height:1.6;color:#d8c8ff;">You bent the speed '
    + 'of light and took over the universe. &#x1F30C;</p>'
    + '<p style="font-size:14px;color:#9a86c8;margin-top:24px;">Core board cleared '
    + '<em>and</em> both secret plans &mdash; &ldquo;Take Over the Universe&rdquo; '
    + 'and &ldquo;Adjust the Speed of Light&rdquo; &mdash; driven to Completed. '
    + 'Nothing left to fix in this corner of the galaxy.</p>'
    + '<button onclick="document.getElementById(\'demo-overachiever\').style.display=\'none\'"'
    + ' style="margin-top:24px;padding:10px 32px;font-size:16px;cursor:pointer;'
    + 'background:#7b2ff7;color:white;border:none;border-radius:6px;font-family:monospace;"'
    + '>&#x1F32D; Bask in glory</button></div>';
  document.body.appendChild(oa);

  var origFetch = window.fetch;
  window.fetch = function(input) {
    var url = (typeof input === 'string') ? input : (input && input.url) || '';
    var isState = url.indexOf('/api/state') !== -1;
    return origFetch.apply(this, arguments).then(function(resp) {
      if (isState) {
        var clone = resp.clone();
        clone.json().then(function(data) {
          if (data.demo) {
            var d = data.demo;
            var p = document.getElementById('demo-progress');
            if (p) {
              var inflight = (typeof d.in_flight === 'number')
                ? (' — ' + d.in_flight + '/' + d.concurrency + ' working') : '';
              if (d.progress_total === 0) {
                p.textContent = 'Awaiting first arrivals…';
              } else if (d.overachiever) {
                p.textContent = 'Overachiever — speed of light bent, universe taken over';
              } else if (d.all_completed) {
                p.textContent = 'Board cleared — ' + d.progress_done + '/'
                  + d.progress_total + ' done';
              } else {
                // #1: name BOTH Ready-key columns by their real labels.
                p.textContent = 'Drop plans in Accepted, issues in Ready — '
                  + 'then watch them get worked — '
                  + d.progress_done + '/' + d.progress_total + ' completed'
                  + inflight;
              }
            }
            // Overachiever supersedes the standard victory: if both the core
            // board AND the eggs are done, show (only) the overachiever screen.
            if (d.overachiever && !overachieverShown) {
              overachieverShown = true;
              victoryShown = true;  // suppress a later standard-victory pop
              var vo = document.getElementById('demo-victory');
              if (vo) vo.style.display = 'none';
              var oae = document.getElementById('demo-overachiever');
              if (oae) oae.style.display = 'flex';
            } else if (d.all_completed && !victoryShown) {
              victoryShown = true;
              var v = document.getElementById('demo-victory');
              if (v) v.style.display = 'flex';
            }
          }
        }).catch(function(){});
      }
      return resp;
    });
  }.bind(window);
})();
</script>
"""


# ---------------------------------------------------------------------------
# HTTP server
# ---------------------------------------------------------------------------

class DemoHandler(BaseHTTPRequestHandler):
    server_version = "zskills-demo/2.0"
    sim = None  # set by main()

    def log_message(self, fmt, *args):
        sys.stderr.write("[demo] %s - %s\n" % (
            datetime.now().strftime("%H:%M:%S"), fmt % args))

    def _json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _static(self, path, content_type):
        try:
            data = path.read_bytes()
        except FileNotFoundError:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _serve_index(self):
        index_path = STATIC_DIR / "index.html"
        try:
            html = index_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            self.send_error(404, "index.html not found in %s" % STATIC_DIR)
            return
        html = html.replace("</body>", DEMO_OVERLAY_JS + "</body>")
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/" or path == "/index.html":
            self._serve_index()
            return

        if path == "/sampler.html":
            self._static(STATIC_DIR / "sampler.html", "text/html; charset=utf-8")
            return

        if path == "/app.js":
            self._static(STATIC_DIR / "app.js", "application/javascript; charset=utf-8")
            return

        if path == "/app.css":
            self._static(STATIC_DIR / "app.css", "text/css; charset=utf-8")
            return

        if path == "/favicon.svg":
            self._static(STATIC_DIR / "favicon.svg", "image/svg+xml")
            return

        if path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return

        if path == "/api/health":
            self._json({"status": "ok"})
            return

        if path == "/api/state":
            self._json(self.sim.build_snapshot())
            return

        if path == "/api/work-state":
            self._json({"status": "idle", "current": None, "history": []})
            return

        if path.startswith("/api/plan/"):
            slug = path[len("/api/plan/"):]
            item = self.sim._by_slug.get(slug)
            if item is not None:
                self._json({
                    "slug": slug,
                    "title": item.title,
                    "body": "# %s\n\nStarship maintenance plan." % item.title,
                })
                return
            self.send_error(404)
            return

        if path.startswith("/api/issue/"):
            try:
                num = int(path[len("/api/issue/"):])
            except ValueError:
                self.send_error(400)
                return
            item = self.sim._by_number.get(num)
            if item is not None:
                self._json({
                    "number": num,
                    "title": item.title,
                    "body": "Reported by Engineering: %s" % item.title,
                    "state": "CLOSED" if item.completed else "OPEN",
                })
                return
            self.send_error(404)
            return

        self._json({"error": "not found"}, 404)

    def do_POST(self):
        content_len = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(content_len) if content_len else b""

        path = urlparse(self.path).path

        if path == "/api/queue":
            try:
                payload = json.loads(raw.decode("utf-8") or "null")
            except (ValueError, UnicodeDecodeError) as exc:
                self._json({"error": "json parse: %s" % exc}, 400)
                return
            if not isinstance(payload, dict):
                self._json({"error": "body is not an object"}, 400)
                return
            # Reject `completed` like the real server — it's read-only.
            for grp in ("plans", "issues"):
                sub = payload.get(grp)
                if isinstance(sub, dict) and "completed" in sub:
                    self._json({"error": "completed column is read-only on "
                                "the API; cannot accept POSTs"}, 400)
                    return
            self.sim.apply_queue(payload)
            now = _iso(datetime.now(timezone.utc))
            self._json({"ok": True, "updated_at": now, "state_updated_at": now})
            return

        if path == "/api/trigger":
            self._json({"error": "trigger not available in demo mode"}, 501)
            return

        if path == "/api/work-state/reset":
            self._json({"ok": True})
            return

        self._json({"error": "not found"}, 404)


def main():
    parser = argparse.ArgumentParser(description="Z Skills Dashboard Interactive Demo")
    parser.add_argument("--port", type=int, default=9090, help="Port (default 9090)")
    parser.add_argument("--seed", type=int, default=None,
                        help="RNG seed for reproducible simulations")
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY,
                        help="Max items worked at once from Ready (default %d)"
                             % DEFAULT_CONCURRENCY)
    args = parser.parse_args()

    if not STATIC_DIR.is_dir():
        print("ERROR: static assets not found at %s" % STATIC_DIR, file=sys.stderr)
        print("Run from the repo root: python3 demo/demo_server.py", file=sys.stderr)
        sys.exit(1)

    if args.concurrency < 1:
        print("ERROR: --concurrency must be >= 1", file=sys.stderr)
        sys.exit(1)

    sim = Simulation(seed=args.seed, concurrency=args.concurrency)
    DemoHandler.sim = sim

    HTTPServer.allow_reuse_address = True
    server = HTTPServer(("127.0.0.1", args.port), DemoHandler)
    print("Z Skills Dashboard — Interactive Demo")
    print("  URL:         http://127.0.0.1:%d/" % args.port)
    print("  Seed:        %s" % (args.seed if args.seed is not None else "(random)"))
    print("  Concurrency: %d items worked at once" % args.concurrency)
    print()
    print("  Drag cards between columns (they persist). Drop one in Ready")
    print("  to watch it get worked; clear the board to win.")
    print()
    print("Press Ctrl+C to stop.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDemo server stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
