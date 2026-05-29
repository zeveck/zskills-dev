// Node ESM harness for demo/demo-sim.js. Loaded by tests/test-demo-sim.sh.
//
// Mirrors the retired tests/test-demo-server-interactive.py assertion-for-
// assertion (clock anchor, no-arrival-while-pinned, seed counts, in-flight
// cap, completion frees slots, branch/worktree lifecycle, activity newest-
// first, easter eggs, overachiever). Emits "OK <label>" / "FAIL <label>"
// lines the bash wrapper re-counts; exits 0 on all-pass, 1 on any failure.

import { pathToFileURL } from "node:url";

const SIM_JS_PATH = process.env.SIM_JS_PATH;
const mod = await import(pathToFileURL(SIM_JS_PATH).href);

const {
  Simulation,
  PLAN_DRAG_COLUMNS,
  ISSUE_DRAG_COLUMNS,
  COMPLETED_COLUMN,
  PLAN_ARRIVAL_COLUMN,
  ISSUE_ARRIVAL_COLUMN,
  EASTER_EGG_SLUGS,
  EASTER_EGG_DEFS,
} = mod;

let PASS = 0;
let FAIL = 0;
function ok(label) { PASS += 1; console.log("OK " + label); }
function bad(label, detail) {
  FAIL += 1;
  console.log("FAIL " + label + (detail ? " -- " + detail : ""));
}

// Fast-forward by rewinding the monotonic origin (seconds). The sim clock is
// LAZILY anchored, so anchor here first if a test fast-forwards before its
// first buildSnapshot — exactly what "page opened" would do.
function fastForward(sim, seconds) {
  sim._anchor();
  sim.startTime -= seconds;
}

function findPlanObj(snap, slug) {
  for (const p of snap.plans) if (p.slug === slug) return p;
  return null;
}
function findIssueObj(snap, number) {
  for (const i of snap.issues) if (i.number === number) return i;
  return null;
}

function emptyPayload() {
  const plans = {};
  for (const c of PLAN_DRAG_COLUMNS) plans[c] = [];
  const issues = {};
  for (const c of ISSUE_DRAG_COLUMNS) issues[c] = [];
  return { plans, issues };
}

// ------------------------------------------------------------------
// (a) A dragged item persists across a state rebuild.
// ------------------------------------------------------------------
{
  const sim = new Simulation(1, 3);
  fastForward(sim, 10000);
  sim.tick();
  let snap = sim.buildSnapshot();

  const planSlug = sim.plans[0].slug;
  const payload = emptyPayload();
  for (const p of snap.plans) {
    const col = p.queue.column;
    if (col === COMPLETED_COLUMN) continue;
    const target = p.slug === planSlug ? "backlog" : col;
    payload.plans[target].push({ slug: p.slug, mode: null });
  }
  for (const i of snap.issues) {
    const col = i.queue.column;
    if (col === COMPLETED_COLUMN) continue;
    payload.issues[col].push(i.number);
  }
  sim.applyQueue(payload);

  const snap2 = sim.buildSnapshot();
  const moved = findPlanObj(snap2, planSlug);
  if (moved && moved.queue.column === "backlog") {
    ok("(a) dragged plan persists in backlog across rebuild (no snap-back)");
  } else {
    bad("(a) dragged plan did not persist", "got column=" + (moved && moved.queue.column));
  }

  const snap3 = sim.buildSnapshot();
  const moved3 = findPlanObj(snap3, planSlug);
  if (moved3 && moved3.queue.column === "backlog") {
    ok("(a) plan stays in backlog on a second poll (still no auto-move)");
  } else {
    bad("(a) plan drifted on second poll", "got column=" + (moved3 && moved3.queue.column));
  }
}

// ------------------------------------------------------------------
// (b) An item placed in Ready picks up a claim and eventually completes.
// ------------------------------------------------------------------
{
  const sim = new Simulation(2, 3);
  fastForward(sim, 10000);
  sim.tick();
  let snap = sim.buildSnapshot();

  const targetSlug = sim.plans[0].slug;
  const payload = emptyPayload();
  for (const p of snap.plans) {
    if (p.queue.column === COMPLETED_COLUMN) continue;
    const col = p.slug === targetSlug ? "ready" : "backlog";
    payload.plans[col].push({ slug: p.slug, mode: null });
  }
  for (const i of snap.issues) {
    if (i.queue.column === COMPLETED_COLUMN) continue;
    payload.issues.backlog.push(i.number);
  }
  sim.applyQueue(payload);

  snap = sim.buildSnapshot();
  let pobj = findPlanObj(snap, targetSlug);
  if (pobj && pobj.queue.column === "ready" && pobj.claim) {
    ok("(b) Ready plan picks up a claim chip");
  } else {
    bad("(b) Ready plan did not pick up a claim",
      "col=" + (pobj && pobj.queue.column) + " claim=" + (pobj && pobj.claim));
  }

  // Regression guard: a freshly-claimed plan must START on Phase 1 with 0
  // phases done — not jump straight to "Phase 2" (the old max(1,...) bug).
  if (pobj && pobj.phases_done === 0 && pobj.claim &&
      pobj.claim.current_phase === "Phase 1") {
    ok("(b) freshly-claimed plan starts on Phase 1 (0 done), not Phase 2");
  } else {
    bad("(b) fresh claim did not start on Phase 1",
      "phases_done=" + (pobj && pobj.phases_done) +
      " current_phase=" + (pobj && pobj.claim && pobj.claim.current_phase));
  }

  // Then phases tick up while still in-flight (0 < done < count).
  const midItem = sim._bySlug[targetSlug];
  fastForward(sim, Math.ceil(midItem.workDuration * 0.6));
  sim.tick();
  snap = sim.buildSnapshot();
  pobj = findPlanObj(snap, targetSlug);
  if (pobj && pobj.phases_done > 0 && pobj.phases_done < pobj.phase_count) {
    ok("(b) in-flight plan ticks phases mid-flight (0 < done < count)");
  } else {
    bad("(b) phases not ticking mid-flight",
      "phases_done=" + (pobj && pobj.phases_done) + " of " + (pobj && pobj.phase_count));
  }

  const workItem = sim._bySlug[targetSlug];
  fastForward(sim, workItem.workDuration + 5);
  snap = sim.buildSnapshot();
  pobj = findPlanObj(snap, targetSlug);
  if (pobj && pobj.queue.column === COMPLETED_COLUMN && pobj.status === "complete") {
    ok("(b) worked plan auto-advances to Completed when work finishes");
  } else {
    bad("(b) worked plan did not complete",
      "col=" + (pobj && pobj.queue.column) + " status=" + (pobj && pobj.status));
  }
  if (pobj && !pobj.claim) {
    ok("(b) completed plan has no claim chip");
  } else {
    bad("(b) completed plan still carries a claim");
  }
}

// ------------------------------------------------------------------
// (c) Concurrency cap holds — <=N in-flight even with >N in Ready.
// ------------------------------------------------------------------
{
  const CAP = 3;
  const sim = new Simulation(3, CAP);
  fastForward(sim, 10000);
  sim.tick();
  let snap = sim.buildSnapshot();

  const readySlugs = sim.plans.slice(0, 6).map((p) => p.slug);
  const payload = emptyPayload();
  for (const p of snap.plans) {
    if (p.queue.column === COMPLETED_COLUMN) continue;
    const col = readySlugs.indexOf(p.slug) >= 0 ? "ready" : "backlog";
    payload.plans[col].push({ slug: p.slug, mode: null });
  }
  for (const i of snap.issues) {
    if (i.queue.column === COMPLETED_COLUMN) continue;
    payload.issues.backlog.push(i.number);
  }
  sim.applyQueue(payload);

  snap = sim.buildSnapshot();
  const inReady = snap.plans.filter((p) => p.queue.column === "ready");
  const claimed = inReady.filter((p) => p.claim);
  const waiting = inReady.filter((p) => !p.claim);
  if (claimed.length === CAP) {
    ok("(c) exactly " + CAP + " Ready plans are in-flight (cap respected)");
  } else {
    bad("(c) wrong in-flight count", "claimed=" + claimed.length + " (cap=" + CAP + ")");
  }
  if (waiting.length === readySlugs.length - CAP) {
    ok("(c) the remaining " + (readySlugs.length - CAP) + " Ready plans wait with no claim");
  } else {
    bad("(c) wrong waiting count", "waiting=" + waiting.length);
  }

  let maxDur = 0;
  for (const s of readySlugs) maxDur = Math.max(maxDur, sim._bySlug[s].workDuration);
  fastForward(sim, maxDur + 5);
  snap = sim.buildSnapshot();
  const completedNow = snap.plans.filter((p) =>
    readySlugs.indexOf(p.slug) >= 0 && p.queue.column === COMPLETED_COLUMN);
  const stillInflight = snap.plans.filter((p) =>
    p.queue.column === "ready" && p.claim);
  if (completedNow.length >= CAP) {
    ok("(c) first batch completed and freed slots");
  } else {
    bad("(c) first batch did not complete", "completed=" + completedNow.length);
  }
  if (stillInflight.length <= CAP) {
    ok("(c) in-flight still capped at <=" + CAP + " after slot churn");
  } else {
    bad("(c) cap violated after churn", "in_flight=" + stillInflight.length);
  }
}

// ------------------------------------------------------------------
// (d) Items NOT in Ready never get a claim or auto-move.
// ------------------------------------------------------------------
{
  const sim = new Simulation(4, 3);
  fastForward(sim, 10000);
  sim.tick();
  let snap = sim.buildSnapshot();

  const payload = emptyPayload();
  const planCols = ["drafted", "reviewed", "backlog", "discarded"];
  snap.plans.forEach((p, idx) => {
    if (p.queue.column === COMPLETED_COLUMN) return;
    const col = planCols[idx % planCols.length];
    payload.plans[col].push({ slug: p.slug, mode: null });
  });
  const issueCols = ["triage", "backlog"];
  snap.issues.forEach((i, idx) => {
    if (i.queue.column === COMPLETED_COLUMN) return;
    const col = issueCols[idx % issueCols.length];
    payload.issues[col].push(i.number);
  });
  sim.applyQueue(payload);

  snap = sim.buildSnapshot();
  const expectedPlanCols = {};
  for (const p of snap.plans) expectedPlanCols[p.slug] = p.queue.column;

  fastForward(sim, 600);
  let anyClaim = false;
  let moved = false;
  for (let r = 0; r < 3; r++) {
    snap = sim.buildSnapshot();
    for (const p of snap.plans) {
      const col = p.queue.column;
      if (col !== "ready" && col !== COMPLETED_COLUMN) {
        if (p.claim) anyClaim = true;
        if (expectedPlanCols[p.slug] !== col) moved = true;
      }
    }
    for (const i of snap.issues) {
      const col = i.queue.column;
      if (col !== "ready" && col !== COMPLETED_COLUMN && i.claim) anyClaim = true;
    }
  }
  if (!anyClaim) ok("(d) non-Ready items never carry a claim chip");
  else bad("(d) a non-Ready item gained a claim");
  if (!moved) ok("(d) non-Ready items never auto-move across polls/time");
  else bad("(d) a non-Ready item auto-moved");
}

// ------------------------------------------------------------------
// Bonus structural checks the frontend depends on.
// ------------------------------------------------------------------
{
  const sim = new Simulation(5, 3);
  const snap = sim.buildSnapshot();
  const q = snap.queues;
  if ("completed" in q.plans && "completed" in q.issues) {
    ok("structural: queues expose read-only `completed` for both kinds");
  } else {
    bad("structural: missing completed in queues object");
  }
  if (snap.demo.concurrency === 3 && snap.demo.interactive === true) {
    ok("structural: demo block advertises interactive + concurrency");
  } else {
    bad("structural: demo block missing interactive/concurrency");
  }
  if (new Simulation(5).buildSnapshot().demo.all_completed === false) {
    ok("structural: victory is False before any arrivals complete");
  } else {
    bad("structural: victory true at t=0");
  }
}

// ==================================================================
// NEW LIFECYCLE CASES
// ==================================================================

// (lifecycle a) Clock does NOT advance until the first /api/state.
{
  const sim = new Simulation(11, 3);
  if (sim.startTime === null && sim.elapsed() === 0.0) {
    ok("(a) fresh sim: clock unanchored (start_time None, elapsed 0)");
  } else {
    bad("(a) clock anchored before first /api/state",
      "start_time=" + sim.startTime + " elapsed=" + sim.elapsed());
  }

  sim.tick();
  const arrivedPre = sim._allItemsArr().filter((it) => it.arrived);
  const nonSeedArrived = arrivedPre.filter((it) => it.arriveAt > 0.0);
  if (nonSeedArrived.length === 0) {
    ok("(a) no non-seed item arrives while clock is pinned at t=0");
  } else {
    bad("(a) a future-arrival item arrived before the clock advanced",
      "count=" + nonSeedArrived.length);
  }

  const snap = sim.buildSnapshot();
  if (sim.startTime !== null && snap.demo.elapsed_seconds >= 0.0) {
    ok("(a) first /api/state anchors the clock (timeline begins at t=0)");
  } else {
    bad("(a) build_snapshot did not anchor the clock");
  }

  const anchorAfterFirst = sim.startTime;
  sim.buildSnapshot();
  if (sim.startTime === anchorAfterFirst) {
    ok("(a) subsequent polls do NOT reset the anchored clock");
  } else {
    bad("(a) anchor moved on a later poll");
  }
}

// (lifecycle b) Exactly one plan + one issue seeded at the anchor.
{
  const sim = new Simulation(12, 3);
  const snap = sim.buildSnapshot();
  const seededPlans = snap.plans;
  const seededIssues = snap.issues;
  const eggSlugs = new Set(EASTER_EGG_SLUGS);
  const coreSeedPlans = seededPlans.filter((p) => !eggSlugs.has(p.slug));
  const eggSeedPlans = seededPlans.filter((p) => eggSlugs.has(p.slug));
  if (coreSeedPlans.length === 1 && seededIssues.length === 1) {
    ok("(b) exactly one core plan + one core issue present at the anchored t=0");
  } else {
    bad("(b) wrong core seed count at t=0",
      "core_plans=" + coreSeedPlans.length + " issues=" + seededIssues.length);
  }
  if (eggSeedPlans.length === EASTER_EGG_DEFS.length) {
    ok("(b) both easter-egg plans present at the anchored t=0");
  } else {
    bad("(b) wrong easter-egg seed count at t=0", "eggs=" + eggSeedPlans.length);
  }
  if (coreSeedPlans.length && coreSeedPlans[0].queue.column === PLAN_ARRIVAL_COLUMN
      && seededIssues.length && seededIssues[0].queue.column === ISSUE_ARRIVAL_COLUMN) {
    ok("(b) seeded core plan is in Drafted, seeded issue is in Triage");
  } else {
    bad("(b) seeded items not in their arrival columns");
  }
}

// (lifecycle c) A claimed Ready item produces a branch + activity entries.
{
  const sim = new Simulation(13, 3);
  sim.buildSnapshot();
  fastForward(sim, 10000);
  let snap = sim.buildSnapshot();
  const target = sim.plans[0].slug;
  const payload = emptyPayload();
  for (const p of snap.plans) {
    if (p.queue.column === COMPLETED_COLUMN) continue;
    const col = p.slug === target ? "ready" : "backlog";
    payload.plans[col].push({ slug: p.slug, mode: null });
  }
  for (const i of snap.issues) {
    if (i.queue.column === COMPLETED_COLUMN) continue;
    payload.issues.backlog.push(i.number);
  }
  sim.applyQueue(payload);
  snap = sim.buildSnapshot();

  const branchName = "feat/" + target;
  const br = snap.branches.filter((b) => b.name === branchName);
  const wt = snap.worktrees.filter((w) => w.branch === branchName);
  if (br.length && wt.length) {
    ok("(c) claimed Ready plan produces a branch + worktree entry");
  } else {
    bad("(c) no branch/worktree for claimed plan",
      "branches=" + br.length + " worktrees=" + wt.length);
  }
  if (wt.length && wt[0].landed === null && wt[0].category === "active") {
    ok("(c) claimed-but-incomplete worktree -> Active bucket (landed None)");
  } else {
    bad("(c) claimed worktree not in Active bucket", "landed=" + (wt.length && JSON.stringify(wt[0].landed)));
  }
  const acts = snap.activity.filter((a) => a.id === target);
  const actKinds = new Set(acts.map((a) => a.kind));
  if (actKinds.has("claimed") && actKinds.has("implement")) {
    ok("(c) claimed plan emits claimed + implement activity entries");
  } else {
    bad("(c) missing claim/implement activity", "kinds=" + JSON.stringify([...actKinds]));
  }
  if (acts.length && acts.every((a) => a.skill === "run-plan")) {
    ok("(c) plan activity carries skill=run-plan");
  } else {
    bad("(c) plan activity skill not run-plan",
      "skills=" + JSON.stringify([...new Set(acts.map((a) => a.skill))]));
  }

  // (lifecycle d) On completion the branch flips to Landed + a land entry.
  fastForward(sim, sim._bySlug[target].workDuration + 5);
  snap = sim.buildSnapshot();
  const wt2 = snap.worktrees.filter((w) => w.branch === branchName);
  if (wt2.length && wt2[0].landed && wt2[0].category === "landed") {
    ok("(d) completed item's worktree flips to Landed (landed.status set)");
  } else {
    bad("(d) completed worktree did not flip to Landed",
      "landed=" + (wt2.length && JSON.stringify(wt2[0].landed)));
  }
  const acts2 = snap.activity.filter((a) => a.id === target);
  if (acts2.some((a) => a.kind === "land-pr")) {
    ok("(d) completion emits a land-pr activity entry");
  } else {
    bad("(d) no land-pr activity on completion",
      "kinds=" + JSON.stringify([...new Set(acts2.map((a) => a.kind))]));
  }
  const kindsOrder = acts2.map((a) => a.kind);
  if (kindsOrder.indexOf("land-pr") >= 0 && kindsOrder.indexOf("claimed") >= 0
      && kindsOrder.indexOf("land-pr") < kindsOrder.indexOf("claimed")) {
    ok("(d) activity feed is newest-first (land-pr before claimed)");
  } else {
    bad("(d) activity not newest-first", "order=" + JSON.stringify(kindsOrder));
  }
}

// (lifecycle e) Non-worked items produce NO branch and NO activity.
{
  const sim = new Simulation(14, 3);
  sim.buildSnapshot();
  fastForward(sim, 10000);
  let snap = sim.buildSnapshot();
  const payload = emptyPayload();
  for (const p of snap.plans) {
    if (p.queue.column === COMPLETED_COLUMN) continue;
    payload.plans.backlog.push({ slug: p.slug, mode: null });
  }
  for (const i of snap.issues) {
    if (i.queue.column === COMPLETED_COLUMN) continue;
    payload.issues.backlog.push(i.number);
  }
  sim.applyQueue(payload);
  fastForward(sim, 500);
  snap = sim.buildSnapshot();
  if (snap.branches.length === 0 && snap.worktrees.length === 0) {
    ok("(e) non-worked items produce NO branch and NO worktree");
  } else {
    bad("(e) phantom branches/worktrees for unworked items",
      "branches=" + snap.branches.length + " worktrees=" + snap.worktrees.length);
  }
  if (snap.activity.length === 0) {
    ok("(e) non-worked items produce NO activity entries");
  } else {
    bad("(e) phantom activity for unworked items", "count=" + snap.activity.length);
  }
}

// (lifecycle f) landing_mode is a LANDING dimension; mostly inherit, a couple
// explicit overrides; never carries phase/finish.
{
  const sim = new Simulation(15, 3);
  sim.buildSnapshot();
  fastForward(sim, 10000);
  const snap = sim.buildSnapshot();
  const modes = snap.plans.map((p) => p.landing_mode);
  const explicit = snap.plans.map((p) => p.landing_mode_explicit);
  if (!modes.some((m) => m === "phase" || m === "finish")) {
    ok("(f) landing_mode never carries phase/finish (correct dimension)");
  } else {
    bad("(f) landing_mode leaked phase/finish", "modes=" + JSON.stringify(modes));
  }
  const nExplicit = explicit.filter((e) => e).length;
  if (nExplicit > 0 && nExplicit < explicit.length) {
    ok("(f) mix of inherited (no pill) and explicit-override (pill) plans — "
      + nExplicit + "/" + explicit.length + " explicit");
  } else {
    bad("(f) landing override mix wrong", "n_explicit=" + nExplicit + " of " + explicit.length);
  }
  const okVals = snap.plans.every((p) =>
    ["pr", "direct", "cherry-pick", "worktree"].indexOf(p.landing_mode) >= 0);
  if (okVals) {
    ok("(f) explicit + inherited plans all carry real landing values");
  } else {
    bad("(f) bad landing value present", "modes=" + JSON.stringify(modes));
  }
}

// ==================================================================
// EASTER-EGG + OVERACHIEVER CASES
// ==================================================================

function dragAllTo(sim, snap, columns) {
  const pl = {};
  for (const c of PLAN_DRAG_COLUMNS) pl[c] = [];
  const iss = {};
  for (const c of ISSUE_DRAG_COLUMNS) iss[c] = [];
  for (const p of snap.plans) {
    if (p.queue.column === COMPLETED_COLUMN) continue;
    pl[columns[p.slug] || "backlog"].push({ slug: p.slug, mode: null });
  }
  for (const i of snap.issues) {
    if (i.queue.column === COMPLETED_COLUMN) continue;
    iss.backlog.push(i.number);
  }
  return { plans: pl, issues: iss };
}

function workToCompletion(sim, slugs) {
  let snap;
  for (let r = 0; r < 40; r++) {
    snap = sim.buildSnapshot();
    const remaining = slugs.filter((s) => !sim._bySlug[s].completed);
    if (remaining.length === 0) return snap;
    const cols = {};
    for (const s of remaining) cols[s] = "ready";
    sim.applyQueue(dragAllTo(sim, snap, cols));
    sim.buildSnapshot();
    let maxd = 0;
    for (const it of sim._allItemsArr()) maxd = Math.max(maxd, it.workDuration);
    fastForward(sim, maxd + 5);
  }
  return sim.buildSnapshot();
}

// (eg1) The two easter-egg plans seeded in Backlog/Discarded at t=0.
{
  const sim = new Simulation(21, 3);
  const snap = sim.buildSnapshot();
  const eggBySlug = {};
  for (const p of snap.plans) {
    if (EASTER_EGG_SLUGS.indexOf(p.slug) >= 0) eggBySlug[p.slug] = p;
  }
  const tou = eggBySlug["take-over-the-universe"];
  const asol = eggBySlug["adjust-the-speed-of-light"];
  if (tou && tou.title === "Take Over the Universe"
      && tou.queue.column === "backlog"
      && tou.blurb.indexOf("speed of light got in the way") >= 0) {
    ok("(eg1) 'Take Over the Universe' seeded in Backlog with right title/blurb");
  } else {
    bad("(eg1) Take Over the Universe seed wrong", "obj=" + JSON.stringify(tou));
  }
  if (asol && asol.title === "Adjust the Speed of Light"
      && asol.queue.column === "discarded"
      && asol.blurb.indexOf("Unblocks: Take Over the Universe") >= 0) {
    ok("(eg1) 'Adjust the Speed of Light' seeded in Discarded with right title/blurb");
  } else {
    bad("(eg1) Adjust the Speed of Light seed wrong", "obj=" + JSON.stringify(asol));
  }
  const eggs = sim.plans.filter((it) => it.isEasterEgg);
  if (eggs.length && eggs.every((it) => it.arriveAt === 0.0)) {
    ok("(eg1) easter eggs are seeded (arrive_at==0), not timed arrivals");
  } else {
    bad("(eg1) easter eggs have non-zero arrive_at",
      "arrive_ats=" + JSON.stringify(eggs.map((it) => it.arriveAt)));
  }

  // (eg2) The demo object exposes the overachiever flags.
  const d0 = snap.demo;
  if ("core_cleared" in d0 && "easter_eggs_completed" in d0 && "overachiever" in d0) {
    ok("(eg2) demo object exposes core_cleared/easter_eggs_completed/overachiever");
  } else {
    bad("(eg2) demo object missing overachiever flags", "keys=" + JSON.stringify(Object.keys(d0)));
  }
  if (d0.core_cleared === false && d0.easter_eggs_completed === false
      && d0.overachiever === false) {
    ok("(eg2) at t=0 all overachiever flags are False");
  } else {
    bad("(eg2) overachiever flags not all False at t=0",
      "core=" + d0.core_cleared + " eggs=" + d0.easter_eggs_completed + " oa=" + d0.overachiever);
  }
}

// (eg3) Completing core-only sets core_cleared but NOT overachiever.
{
  const sim = new Simulation(22, 4);
  sim.buildSnapshot();
  fastForward(sim, 10000);
  sim.buildSnapshot();
  const coreSlugs = sim.plans.filter((it) => !it.isEasterEgg).map((it) => it.slug);
  workToCompletion(sim, coreSlugs);
  // Work all core issues to completion (eggs parked in backlog).
  for (let r = 0; r < 40; r++) {
    const snap = sim.buildSnapshot();
    const remIss = sim.issues.filter((it) => !it.completed);
    if (remIss.length === 0) break;
    const pl = {}; for (const c of PLAN_DRAG_COLUMNS) pl[c] = [];
    const iss = {}; for (const c of ISSUE_DRAG_COLUMNS) iss[c] = [];
    for (const p of snap.plans) {
      if (p.queue.column === COMPLETED_COLUMN) continue;
      pl.backlog.push({ slug: p.slug, mode: null });
    }
    for (const i of snap.issues) {
      if (i.queue.column === COMPLETED_COLUMN) continue;
      iss.ready.push(i.number);
    }
    sim.applyQueue({ plans: pl, issues: iss });
    sim.buildSnapshot();
    let maxd = 0;
    for (const it of sim._allItemsArr()) maxd = Math.max(maxd, it.workDuration);
    fastForward(sim, maxd + 5);
  }
  const snap = sim.buildSnapshot();
  const d = snap.demo;
  const eggsDone = sim.plans.filter((it) => it.isEasterEgg).every((it) => it.completed);
  if (d.core_cleared === true && eggsDone === false) {
    ok("(eg3) core completed (eggs untouched): core_cleared True");
  } else {
    bad("(eg3) core not cleared with eggs untouched",
      "core_cleared=" + d.core_cleared + " eggs_done=" + eggsDone);
  }
  if (d.easter_eggs_completed === false && d.overachiever === false) {
    ok("(eg3) eggs untouched => easter_eggs_completed False, overachiever False");
  } else {
    bad("(eg3) overachiever tripped without eggs",
      "eggs=" + d.easter_eggs_completed + " oa=" + d.overachiever);
  }
}

// (eg4) Completing core + BOTH eggs sets overachiever True.
{
  const sim = new Simulation(23, 4);
  sim.buildSnapshot();
  fastForward(sim, 10000);
  sim.buildSnapshot();
  const allPlanSlugs = sim.plans.map((it) => it.slug);
  workToCompletion(sim, allPlanSlugs);
  for (let r = 0; r < 40; r++) {
    const snap = sim.buildSnapshot();
    const remIss = sim.issues.filter((it) => !it.completed);
    const remPlan = sim.plans.filter((it) => !it.completed);
    if (remIss.length === 0 && remPlan.length === 0) break;
    const pl = {}; for (const c of PLAN_DRAG_COLUMNS) pl[c] = [];
    const iss = {}; for (const c of ISSUE_DRAG_COLUMNS) iss[c] = [];
    for (const p of snap.plans) {
      if (p.queue.column === COMPLETED_COLUMN) continue;
      pl.ready.push({ slug: p.slug, mode: null });
    }
    for (const i of snap.issues) {
      if (i.queue.column === COMPLETED_COLUMN) continue;
      iss.ready.push(i.number);
    }
    sim.applyQueue({ plans: pl, issues: iss });
    sim.buildSnapshot();
    let maxd = 0;
    for (const it of sim._allItemsArr()) maxd = Math.max(maxd, it.workDuration);
    fastForward(sim, maxd + 5);
  }
  const snap = sim.buildSnapshot();
  const d = snap.demo;
  if (d.core_cleared === true && d.easter_eggs_completed === true) {
    ok("(eg4) core + both eggs completed (core_cleared + easter_eggs_completed)");
  } else {
    bad("(eg4) core/eggs not all completed",
      "core=" + d.core_cleared + " eggs=" + d.easter_eggs_completed);
  }
  if (d.overachiever === true) {
    ok("(eg4) overachiever True when core cleared AND both eggs completed");
  } else {
    bad("(eg4) overachiever not set with everything completed", "oa=" + d.overachiever);
  }
}

console.log("");
console.log("Results: " + PASS + " passed, " + FAIL + " failed (of " + (PASS + FAIL) + ")");
process.exitCode = FAIL === 0 ? 0 : 1;
