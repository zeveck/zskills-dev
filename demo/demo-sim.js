// Z Skills Dashboard — Interactive Demo Simulation (browser module).
//
// A faithful JavaScript port of the former demo/demo_server.py `Simulation`
// class. It reproduces the stateful, user-driven board simulation entirely in
// the browser so the demo can be hosted as static files (e.g. GitHub Pages)
// with NO backend process.
//
// The demo does NO autonomous column movement except:
//   1. Arrivals: new sci-fi-themed work appears over time (issues land in
//      Triage, plans land in Drafted) — the only "new card appears" motion.
//   2. Worked Ready items: an item the user drags into Ready becomes eligible
//      to be worked. At most `concurrency` items are in-flight at once
//      (default 3); each shows a claim chip, ticks its phases, and after a
//      timely period auto-advances to Completed — the only sim-driven column
//      transition.
//
// Everything else (Triage / Drafted / Reviewed / Backlog / Discarded) is driven
// entirely by the user dragging cards. Drags PERSIST: the sim holds mutable
// board state and applies /api/queue payloads to it.
//
// This module is pure logic (no DOM, no network). It is consumed by
// demo/index.html (which installs a window.fetch shim that routes the real
// dashboard's /api/* calls into this sim) and by the node-based self-test
// (tests/test-demo-sim.sh). It works in a browser (ES module) and under node
// (module.exports fallback at the bottom).

// ---------------------------------------------------------------------------
// Tunables (mirror demo_server.py)
// ---------------------------------------------------------------------------

const DEFAULT_CONCURRENCY = 3;

const WORK_DURATION_BASE = 32;       // seconds (lands ~20-45s with variance)
const WORK_DURATION_VARIANCE = 13;

const ARRIVAL_WINDOW_SECONDS = 300;  // all 20 arrive within ~5 minutes
const ARRIVAL_GAP_BASE = 15;         // ~every 6-24s with the variance below
const ARRIVAL_GAP_VARIANCE = 9;
const FIRST_ARRIVAL_DELAY = 0;       // the seeded pair is present at t=0

const PLAN_DRAG_COLUMNS = ["drafted", "reviewed", "ready", "backlog", "discarded"];
const ISSUE_DRAG_COLUMNS = ["triage", "ready", "backlog"];
const PLAN_ARRIVAL_COLUMN = "drafted";
const ISSUE_ARRIVAL_COLUMN = "triage";
const READY_COLUMN = "ready";
const COMPLETED_COLUMN = "completed";

const ACTIVITY_CAP = 200;
const WORKTREE_BASE = "/starship/.worktrees";
const LANDED_STATUS = "landed";

const DEFAULT_LANDING = "pr";        // project default (mirrors execution.landing)
const PLAN_LANDING_MODES = [
  null, "direct", null, null, "cherry-pick",
  null, null, null, null, null,
];

// Easter-egg plans (#3/#4): seeded at t=0 in fixed columns, OFF the timed
// arrival schedule. (slug, title, blurb, seedColumn, phaseDefs, landingMode)
const EASTER_EGG_DEFS = [
  ["take-over-the-universe", "Take Over the Universe",
    "Blocked — the speed of light got in the way.", "backlog", [
      "Assemble shadow council",
      "Acquire controlling stake in every shipyard",
      "Issue the galaxy-wide memo",
    ], null],
  ["adjust-the-speed-of-light", "Adjust the Speed of Light",
    "Unblocks: Take Over the Universe.", "discarded", [
      "Petition the laws of physics",
      "Retune the fine-structure constant",
      "Re-baseline every clock in the fleet",
    ], null],
];
const EASTER_EGG_SLUGS = EASTER_EGG_DEFS.map((d) => d[0]);

// ---------------------------------------------------------------------------
// Sci-fi content (mirror demo_server.py)
// ---------------------------------------------------------------------------

const PLAN_DEFS = [
  ["repair-hyperdrive-coupling", "Repair Hyperdrive Coupling", [
    "Diagnose harmonic resonance drift",
    "Replace flux capacitor array",
    "Calibrate thrust vectoring",
  ]],
  ["tachyon-anomaly-investigation", "Investigate Anomalous Tachyon Readings", [
    "Deploy sensor grid to sectors 7-12",
    "Correlate readings with stellar cartography",
    "Draft containment protocol",
    "Peer review with Science Division",
  ]],
  ["hull-breach-deck-7", "Patch Hull Breach in Deck 7", [
    "Emergency atmospheric seal",
    "Structural integrity field reinforcement",
    "Full hull plate replacement",
  ]],
  ["ai-core-alignment-audit", "AI Core Alignment Audit", [
    "Dump personality matrix logs",
    "Cross-reference with ethics subroutine v4.2",
    "Patch value-drift regression",
    "Run full alignment battery",
  ]],
  ["nebula-navigation-charts", "Update Nebula Navigation Charts", [
    "Scan Helix Nebula boundary shifts",
    "Recalculate safe transit corridors",
    "Distribute updated charts to fleet",
  ]],
  ["shields-harmonics-overhaul", "Shield Harmonics Overhaul", [
    "Benchmark current shield modulation",
    "Install phase-variant emitter array",
    "Stress-test against simulated plasma torpedoes",
  ]],
  ["crew-stasis-pod-maintenance", "Crew Stasis Pod Maintenance Cycle", [
    "Drain and clean bio-gel reservoirs",
    "Recalibrate neural induction coils",
    "Run occupant simulation health checks",
  ]],
  ["quantum-comm-relay-upgrade", "Quantum Comm Relay Upgrade", [
    "Decommission legacy subspace antenna",
    "Install entanglement pair buffers",
    "Validate zero-latency handshake",
    "Cut over from subspace to quantum",
  ]],
  ["asteroid-mining-drone-swarm", "Deploy Asteroid Mining Drone Swarm", [
    "Manufacture drone chassis batch",
    "Program swarm coordination AI",
    "Field test in Kuiper belt analog",
  ]],
  ["holodeck-physics-engine", "Holodeck Physics Engine Rewrite", [
    "Profile existing fluid dynamics module",
    "Implement SPH solver in ship-local coordinates",
    "Validate gravity simulation accuracy",
  ]],
  ["stellar-cartography-3d-map", "Stellar Cartography 3D Map Renderer", [
    "Parse galactic coordinate feeds",
    "Build real-time WebGL star renderer",
    "Add interactive sector overlays",
  ]],
];

const ISSUE_DEFS = [
  [101, "Plasma conduit leak in main engineering"],
  [102, "Navigation array returns NaN for subspace coordinates"],
  [103, "Turbolift stuck between decks 5 and 6"],
  [104, "Replicator produces Earl Grey at wrong temperature"],
  [105, "Inertial dampeners lag 200ms during course corrections"],
  [106, "Holodeck safety protocols intermittently disabled"],
  [107, "Phaser bank 3 fires 15 degrees off target"],
  [108, "Universal translator garbles Andorian sibilants"],
  [109, "Shuttle bay doors report closed when open"],
  [110, "Crew quarters lighting stuck on red alert spectrum"],
];

// ---------------------------------------------------------------------------
// Deterministic RNG (mirror Python random.Random's interface we use:
// randint(a,b) inclusive + shuffle). Python's Mersenne Twister produces a
// different stream than any JS PRNG, so seeded outputs will NOT match Python
// byte-for-byte — but the demo never relies on cross-language reproducibility,
// only on per-run determinism under a fixed seed. We implement a small
// mulberry32 PRNG with the same randint/shuffle API the sim uses.
// ---------------------------------------------------------------------------

class Rng {
  constructor(seed) {
    if (seed === null || seed === undefined) {
      seed = (Date.now() ^ Math.floor(Math.random() * 0xffffffff)) >>> 0;
    }
    this._state = seed >>> 0;
    if (this._state === 0) this._state = 0x9e3779b9;
  }

  // mulberry32 — returns a float in [0, 1).
  _next() {
    this._state = (this._state + 0x6d2b79f5) >>> 0;
    let t = this._state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  // Inclusive on both ends, like Python's random.randint.
  randint(a, b) {
    return a + Math.floor(this._next() * (b - a + 1));
  }

  // In-place Fisher-Yates (deterministic for a given seed/stream).
  shuffle(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(this._next() * (i + 1));
      const tmp = arr[i];
      arr[i] = arr[j];
      arr[j] = tmp;
    }
    return arr;
  }
}

// ---------------------------------------------------------------------------
// Time + ISO helpers
// ---------------------------------------------------------------------------

// Monotonic clock in SECONDS. performance.now() is monotonic in browsers;
// fall back to Date.now() under node where performance may be absent.
function monotonicNow() {
  if (typeof performance !== "undefined" && typeof performance.now === "function") {
    return performance.now() / 1000;
  }
  return Date.now() / 1000;
}

function isoNow() {
  return new Date().toISOString();
}

// ISO timestamp `seconds` in the past (clamped to >= 0).
function agoIso(seconds) {
  const ms = Date.now() - Math.max(0, seconds) * 1000;
  return new Date(ms).toISOString();
}

function pad7hex(n) {
  let s = (n >>> 0).toString(16);
  while (s.length < 7) s = "0" + s;
  return s.slice(-7);
}

// ---------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------

class PlanItem {
  constructor(slug, title, phaseDefs, arriveAt, rng, opts) {
    opts = opts || {};
    this.slug = slug;
    this.title = title;
    this.phaseDefs = phaseDefs;
    this.arriveAt = arriveAt;
    this.isEasterEgg = !!opts.isEasterEgg;
    this.blurb = opts.blurb !== undefined ? opts.blurb : null;
    this.seedColumn = opts.seedColumn !== undefined ? opts.seedColumn : null;
    this.column = null;
    this.arrived = false;
    this.completed = false;
    this.completedAtElapsed = null;
    this.startedAtElapsed = null;
    this.workDuration = WORK_DURATION_BASE
      + rng.randint(-WORK_DURATION_VARIANCE, WORK_DURATION_VARIANCE);
    this.pipelineId = "run-plan.demo-" + String(rng.randint(1000, 9999)).padStart(4, "0");
    this.landingMode = opts.landingMode !== undefined ? opts.landingMode : null;
    this.emitted = new Set();
  }

  get kind() { return "plan"; }
  get branchName() { return "feat/" + this.slug; }
  get worktreePath() { return WORKTREE_BASE + "/feat-" + this.slug; }
  get activitySkill() { return "run-plan"; }
  get idKey() { return this.slug; }
  get inFlight() { return this.startedAtElapsed !== null && !this.completed; }
}

class IssueItem {
  constructor(number, title, arriveAt, rng) {
    this.number = number;
    this.title = title;
    this.arriveAt = arriveAt;
    this.isEasterEgg = false;
    this.column = null;
    this.arrived = false;
    this.completed = false;
    this.completedAtElapsed = null;
    this.startedAtElapsed = null;
    this.workDuration = WORK_DURATION_BASE
      + rng.randint(-WORK_DURATION_VARIANCE, WORK_DURATION_VARIANCE);
    this.pipelineId = "fix-issues.demo-" + String(rng.randint(1000, 9999)).padStart(4, "0");
    this.emitted = new Set();
  }

  get kind() { return "issue"; }
  get branchName() { return "fix/issue-" + this.number; }
  get worktreePath() { return WORKTREE_BASE + "/fix-issue-" + this.number; }
  get activitySkill() { return "fix-issues"; }
  get idKey() { return this.number; }
  get inFlight() { return this.startedAtElapsed !== null && !this.completed; }
}

// ---------------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------------

const PHASE_SHAPE = {
  claimed:   ["claimed", "running"],
  implement: ["implement", "running"],
  verify:    ["verify", "pass"],
  landed:    ["land-pr", "complete"],
};

class Simulation {
  constructor(seed, concurrency) {
    if (concurrency === null || concurrency === undefined) {
      concurrency = DEFAULT_CONCURRENCY;
    }
    // Clock is LAZILY anchored: startTime stays null until the first
    // buildSnapshot() (= first /api/state).
    this.startTime = null;
    this.rng = new Rng(seed === undefined ? null : seed);
    this.concurrency = concurrency;
    this.plans = [];
    this.issues = [];
    this._bySlug = {};
    this._byNumber = {};
    // Recent Activity log: list of [elapsedAt, recordWithoutTimestamp],
    // appended chronologically, reversed at snapshot time (newest-first).
    this._activity = [];
    this._initItems();
  }

  _initItems() {
    const planDefs = PLAN_DEFS.map((d) => d.slice());
    const issueDefs = ISSUE_DEFS.map((d) => d.slice());

    this.rng.shuffle(planDefs);
    this.rng.shuffle(issueDefs);

    const seedPlan = planDefs[0];
    const seedIssue = issueDefs[0];

    const defs = [];
    // Seeded pair: arriveAt == 0 (present at the anchored t=0).
    defs.push(["plan", seedPlan[0], seedPlan[1], seedPlan[2], 0.0]);
    defs.push(["issue", seedIssue[0], seedIssue[1], null, 0.0]);

    // The rest arrive on a staggered timeline starting just after t=0.
    const rest = planDefs.slice(1).map((d) => ["plan", d[0], d[1], d[2]])
      .concat(issueDefs.slice(1).map((d) => ["issue", d[0], d[1], null]));
    this.rng.shuffle(rest);

    let t = FIRST_ARRIVAL_DELAY;
    for (const entry of rest) {
      let gap = ARRIVAL_GAP_BASE
        + this.rng.randint(-ARRIVAL_GAP_VARIANCE, ARRIVAL_GAP_VARIANCE);
      gap = Math.max(1, gap);
      t += gap;
      defs.push([entry[0], entry[1], entry[2], entry[3], t]);
    }

    // Landing-mode map keyed off the ORIGINAL PLAN_DEFS order so the mix is
    // stable per slug regardless of arrival shuffle.
    const modeBySlug = {};
    PLAN_DEFS.forEach((d, i) => {
      modeBySlug[d[0]] = PLAN_LANDING_MODES[i % PLAN_LANDING_MODES.length];
    });

    for (const entry of defs) {
      const kind = entry[0];
      const a = entry[1];
      const b = entry[2];
      const c = entry[3];
      const arriveAt = entry[4];
      if (kind === "plan") {
        const item = new PlanItem(a, b, c, arriveAt, this.rng,
          { landingMode: modeBySlug[a] });
        this.plans.push(item);
        this._bySlug[a] = item;
      } else {
        const item = new IssueItem(a, b, arriveAt, this.rng);
        this.issues.push(item);
        this._byNumber[a] = item;
      }
    }

    // Easter-egg plans (#3/#4): seeded at t=0 in fixed columns, OFF schedule.
    for (const eg of EASTER_EGG_DEFS) {
      const slug = eg[0];
      const title = eg[1];
      const blurb = eg[2];
      const seedColumn = eg[3];
      const phaseDefs = eg[4];
      const mode = eg[5];
      const egg = new PlanItem(slug, title, phaseDefs, 0.0, this.rng, {
        landingMode: mode,
        isEasterEgg: true,
        blurb: blurb,
        seedColumn: seedColumn,
      });
      this.plans.push(egg);
      this._bySlug[slug] = egg;
    }
  }

  _anchor() {
    if (this.startTime === null) {
      this.startTime = monotonicNow();
    }
  }

  elapsed() {
    if (this.startTime === null) return 0.0;
    return monotonicNow() - this.startTime;
  }

  *_allItems() {
    for (const it of this.plans) yield it;
    for (const it of this.issues) yield it;
  }

  _allItemsArr() {
    return this.plans.concat(this.issues);
  }

  // -- core tick -----------------------------------------------------

  tick() {
    this._tickLocked(this.elapsed());
  }

  _tickLocked(elapsed) {
    // 1. Arrivals.
    for (const item of this._allItemsArr()) {
      if (!item.arrived && elapsed >= item.arriveAt) {
        item.arrived = true;
        if (item.isEasterEgg && item.seedColumn) {
          item.column = item.seedColumn;
        } else if (item.kind === "plan") {
          item.column = PLAN_ARRIVAL_COLUMN;
        } else {
          item.column = ISSUE_ARRIVAL_COLUMN;
        }
      }
    }

    // 2. Complete any in-flight item whose work duration has elapsed.
    for (const item of this._allItemsArr()) {
      if (item.inFlight) {
        const age = elapsed - item.startedAtElapsed;
        if (age >= item.workDuration) {
          item.completed = true;
          item.completedAtElapsed = elapsed;
          item.startedAtElapsed = null;
          item.column = COMPLETED_COLUMN;
          this._emit(item, "verify", elapsed);
          this._emit(item, "landed", elapsed);
        }
      }
    }

    // 3. Fill free concurrency slots from waiting Ready items.
    const inFlight = this._allItemsArr().filter((it) => it.inFlight);
    const free = this.concurrency - inFlight.length;
    if (free > 0) {
      const waiting = this._allItemsArr().filter((it) =>
        it.arrived && !it.completed && !it.inFlight && it.column === READY_COLUMN);
      waiting.sort((x, y) => x.arriveAt - y.arriveAt);
      for (const it of waiting.slice(0, free)) {
        it.startedAtElapsed = elapsed;
        this._emit(it, "claimed", elapsed);
        this._emit(it, "implement", elapsed);
      }
    }
  }

  // -- activity feed -------------------------------------------------

  _emit(item, phase, elapsed) {
    if (item.emitted.has(phase)) return;
    item.emitted.add(phase);
    const shape = PHASE_SHAPE[phase];
    const kind = shape[0];
    const status = shape[1];
    const ident = item.kind === "plan" ? item.slug : String(item.number);
    let output;
    if (phase === "landed") {
      output = "merged " + item.branchName + " to main";
    } else if (phase === "claimed") {
      output = "claimed; created " + item.branchName;
    } else if (phase === "implement") {
      output = "implementing on " + item.branchName;
    } else {
      output = "verification " + status + " on " + item.branchName;
    }
    this._activity.push([elapsed, {
      pipeline: item.pipelineId,
      kind: kind,
      id: ident,
      skill: item.activitySkill,
      status: status,
      output: output,
      location: "pipeline",
      parent: null,
    }]);
    if (this._activity.length > ACTIVITY_CAP) {
      this._activity = this._activity.slice(this._activity.length - ACTIVITY_CAP);
    }
  }

  // -- queue POST application ----------------------------------------

  applyQueue(payload) {
    this._applyQueueLocked(payload);
  }

  _applyQueueLocked(payload) {
    const plans = (payload && payload.plans) || {};
    const issues = (payload && payload.issues) || {};

    for (const col of PLAN_DRAG_COLUMNS) {
      const entries = plans[col] || [];
      for (const entry of entries) {
        const slug = (entry && typeof entry === "object") ? entry.slug : entry;
        const item = this._bySlug[slug];
        if (!item || item.completed) continue;
        this._place(item, col);
      }
    }

    for (const col of ISSUE_DRAG_COLUMNS) {
      const entries = issues[col] || [];
      for (const num of entries) {
        const item = this._byNumber[num];
        if (!item || item.completed) continue;
        this._place(item, col);
      }
    }
  }

  _place(item, col) {
    if (item.column === col) return;
    if (item.inFlight && col !== READY_COLUMN) {
      item.startedAtElapsed = null;
    }
    item.column = col;
  }

  // -- progress / victory --------------------------------------------

  _isEgg(it) {
    return !!it.isEasterEgg;
  }

  allCompleted() {
    const arrived = this._allItemsArr().filter((it) => it.arrived && !this._isEgg(it));
    if (arrived.length === 0) return false;
    return arrived.every((it) => it.completed);
  }

  easterEggsCompleted() {
    const eggs = this.plans.filter((it) => this._isEgg(it));
    if (eggs.length < EASTER_EGG_DEFS.length) return false;
    return eggs.every((it) => it.completed);
  }

  overachiever() {
    return this.allCompleted() && this.easterEggsCompleted();
  }

  progress() {
    const arrived = this._allItemsArr().filter((it) => it.arrived && !this._isEgg(it));
    const done = arrived.filter((it) => it.completed).length;
    return [done, arrived.length];
  }

  // -- snapshot ------------------------------------------------------

  buildSnapshot() {
    // /api/state is the only caller — anchor the clock here on first call.
    this._anchor();
    this.tick();
    return this._buildSnapshotLocked(this.elapsed());
  }

  _buildSnapshotLocked(elapsed) {
    const nowIso = isoNow();

    const plansList = [];
    const planQueues = {};
    for (const c of PLAN_DRAG_COLUMNS) planQueues[c] = [];
    planQueues[COMPLETED_COLUMN] = [];

    for (const item of this.plans) {
      if (!item.arrived) continue;
      const col = item.column;
      const phaseDefs = item.phaseDefs;

      let phasesDone;
      if (item.completed) {
        phasesDone = phaseDefs.length;
      } else if (item.inFlight) {
        const age = elapsed - item.startedAtElapsed;
        const frac = Math.min(1.0, age / Math.max(1.0, item.workDuration));
        phasesDone = Math.max(1, Math.floor(frac * phaseDefs.length));
        if (phaseDefs.length > 1) {
          phasesDone = Math.min(phasesDone, phaseDefs.length - 1);
        }
      } else {
        phasesDone = 0;
      }

      const phases = [];
      for (let pi = 0; pi < phaseDefs.length; pi++) {
        const done = pi < phasesDone;
        phases.push({
          n: String(pi + 1),
          name: (pi + 1) + " -- " + phaseDefs[pi],
          status: done ? "done" : "pending",
          commit: done ? pad7hex(this.rng.randint(0, 0xFFFFFFF)) : null,
          notes: done ? "Completed successfully" : "",
        });
      }

      const status = item.completed ? "complete" : "active";
      let completedDt = null;
      const createdDt = agoIso(elapsed - item.arriveAt).slice(0, 10);
      if (item.completed) {
        completedDt = agoIso(elapsed - item.completedAtElapsed);
      }

      const idx = planQueues[col].length;
      if (col === COMPLETED_COLUMN) {
        planQueues[col].push(item.slug);
      } else {
        planQueues[col].push({ slug: item.slug, mode: null });
      }

      const planObj = {
        slug: item.slug,
        file: "docs/plans/" + item.slug.toUpperCase().replace(/-/g, "_") + ".md",
        title: item.title,
        status: status,
        created: createdDt,
        completed: completedDt,
        issue: null,
        blurb: (item.blurb !== null && item.blurb !== undefined)
          ? item.blurb
          : "Starship maintenance task: " + item.title.toLowerCase(),
        phase_count: phaseDefs.length,
        phases_done: phasesDone,
        phases: phases,
        category: null,
        meta_plan: null,
        sub_plans: null,
        landing_mode: (item.landingMode !== null && item.landingMode !== undefined)
          ? item.landingMode
          : DEFAULT_LANDING,
        landing_mode_explicit: (item.landingMode !== null && item.landingMode !== undefined),
        has_report: false,
        report_path: null,
        report: null,
        queue: { column: col, index: idx, mode: null },
      };

      if (item.inFlight) {
        const age = elapsed - item.startedAtElapsed;
        planObj.claim = {
          pipeline_id: item.pipelineId,
          sprint_id: null,
          current_phase: "Phase " + (phasesDone + 1),
          age_seconds: Math.round(age * 10) / 10,
          started_at: agoIso(age),
          pipeline_short: item.pipelineId.slice(-8),
        };
      }

      plansList.push(planObj);
    }

    const issuesList = [];
    const issueQueues = {};
    for (const c of ISSUE_DRAG_COLUMNS) issueQueues[c] = [];
    issueQueues[COMPLETED_COLUMN] = [];

    for (const item of this.issues) {
      if (!item.arrived) continue;
      const col = item.column;
      const idx = issueQueues[col].length;
      issueQueues[col].push(item.number);

      const createdDt = agoIso(elapsed - item.arriveAt);
      const issueObj = {
        number: item.number,
        title: item.title,
        labels: [],
        created_at: createdDt,
        body: "Reported by Engineering: " + item.title,
        queue: { column: col, index: idx },
      };

      if (item.completed) {
        issueObj.closed_at = agoIso(elapsed - item.completedAtElapsed);
      }

      if (item.inFlight) {
        const age = elapsed - item.startedAtElapsed;
        issueObj.claim = {
          pipeline_id: item.pipelineId,
          sprint_id: "demo-sprint",
          age_seconds: Math.round(age * 10) / 10,
          started_at: agoIso(age),
          pipeline_short: item.pipelineId.slice(-8),
        };
      }

      issuesList.push(issueObj);
    }

    const prog = this.progress();
    const done = prog[0];
    const total = prog[1];
    const inFlightCount = this._allItemsArr().filter((it) => it.inFlight).length;

    const bw = this._buildBranchesLocked(elapsed);
    const worktrees = bw[0];
    const branches = bw[1];
    const activity = this._buildActivityLocked(elapsed);

    return {
      version: "1.0",
      updated_at: nowIso,
      state_updated_at: nowIso,
      repo_root: "/starship/uss-enterprise",
      repo_url: "",
      plans: plansList,
      issues: issuesList,
      worktrees: worktrees,
      branches: branches,
      activity: activity,
      queues: {
        default_mode: "phase",
        plans: {
          drafted: planQueues.drafted,
          reviewed: planQueues.reviewed,
          ready: planQueues.ready,
          backlog: planQueues.backlog,
          discarded: planQueues.discarded,
          completed: planQueues[COMPLETED_COLUMN],
        },
        issues: {
          triage: issueQueues.triage,
          ready: issueQueues.ready,
          backlog: issueQueues.backlog,
          completed: issueQueues[COMPLETED_COLUMN],
        },
      },
      state_file_path: "(demo mode)",
      errors: [],
      issues_fetch_ok: true,
      flags: {
        closed_issues_truncated: false,
        closed_issues_limit: 500,
      },
      config: {
        dashboard_completed_days: 14,
      },
      demo: {
        active: true,
        interactive: true,
        progress_done: done,
        progress_total: total,
        in_flight: inFlightCount,
        concurrency: this.concurrency,
        all_completed: this.allCompleted(),
        core_cleared: this.allCompleted(),
        easter_eggs_completed: this.easterEggsCompleted(),
        overachiever: this.overachiever(),
        easter_egg_slugs: EASTER_EGG_SLUGS.slice(),
        elapsed_seconds: Math.round(elapsed * 10) / 10,
      },
    };
  }

  // -- branches / worktrees / activity from the work lifecycle --------

  *_workedItems() {
    for (const it of this._allItemsArr()) {
      if (it.emitted.has("claimed")) yield it;
    }
  }

  _buildBranchesLocked(elapsed) {
    const worktrees = [];
    const branches = [];
    for (const it of this._workedItems()) {
      const name = it.branchName;
      let lastAt;
      let subject;
      if (it.completed) {
        lastAt = elapsed - (it.completedAtElapsed !== null ? it.completedAtElapsed : elapsed);
        subject = it.kind === "plan"
          ? "land-pr: merged " + name
          : "fix: " + it.title;
      } else {
        const started = it.startedAtElapsed !== null ? it.startedAtElapsed : elapsed;
        lastAt = elapsed - started;
        subject = "wip: " + it.title;
      }
      let landed = null;
      let category = "active";
      if (it.completed) {
        landed = {
          status: LANDED_STATUS,
          date: agoIso(lastAt),
          source: it.activitySkill,
        };
        category = "landed";
      }
      let startedForAge = it.startedAtElapsed;
      if (startedForAge === null && !it.completed) {
        startedForAge = elapsed;
      }
      let ageSeconds;
      if (it.completed) {
        ageSeconds = Math.floor(Math.max(0.0, lastAt));
      } else {
        ageSeconds = Math.floor(Math.max(0.0, elapsed - (startedForAge !== null ? startedForAge : elapsed)));
      }
      worktrees.push({
        path: it.worktreePath,
        branch: name,
        category: category,
        landed: landed,
        ahead: it.completed ? 0 : 1,
        behind: 0,
        age_seconds: ageSeconds,
      });
      branches.push({
        name: name,
        last_commit_at: agoIso(lastAt),
        upstream: null,
        last_commit_subject: subject,
        locality: "local",
      });
    }
    return [worktrees, branches];
  }

  _buildActivityLocked(elapsed) {
    const out = [];
    for (const pair of this._activity) {
      const at = pair[0];
      const rec = pair[1];
      const row = Object.assign({}, rec);
      row.timestamp = agoIso(elapsed - at);
      out.push(row);
    }
    out.reverse();
    return out.slice(0, ACTIVITY_CAP);
  }
}

// ---------------------------------------------------------------------------
// Exports — ES module (browser) + CommonJS (node test harness).
// ---------------------------------------------------------------------------

const exported = {
  Simulation,
  PlanItem,
  IssueItem,
  Rng,
  // constants the test/shim reference
  DEFAULT_CONCURRENCY,
  WORK_DURATION_BASE,
  WORK_DURATION_VARIANCE,
  PLAN_DRAG_COLUMNS,
  ISSUE_DRAG_COLUMNS,
  PLAN_ARRIVAL_COLUMN,
  ISSUE_ARRIVAL_COLUMN,
  READY_COLUMN,
  COMPLETED_COLUMN,
  EASTER_EGG_DEFS,
  EASTER_EGG_SLUGS,
  PLAN_DEFS,
  ISSUE_DEFS,
};

export {
  Simulation,
  PlanItem,
  IssueItem,
  Rng,
  DEFAULT_CONCURRENCY,
  WORK_DURATION_BASE,
  WORK_DURATION_VARIANCE,
  PLAN_DRAG_COLUMNS,
  ISSUE_DRAG_COLUMNS,
  PLAN_ARRIVAL_COLUMN,
  ISSUE_ARRIVAL_COLUMN,
  READY_COLUMN,
  COMPLETED_COLUMN,
  EASTER_EGG_DEFS,
  EASTER_EGG_SLUGS,
  PLAN_DEFS,
  ISSUE_DEFS,
};

// CommonJS fallback for the node test harness (which requires() this file
// after stripping the export statement, or loads it via a small shim).
if (typeof module !== "undefined" && module.exports) {
  module.exports = exported;
}
