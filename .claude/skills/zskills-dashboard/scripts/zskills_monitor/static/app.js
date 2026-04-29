// Z Skills Monitor — interactive dashboard renderer (Phase 7).
//
// Loaded as a single ES module from /app.js. Polls /api/state every 2s
// via setTimeout recursion (NOT setInterval), pauses while document is
// hidden, and force-loads on visibilitychange. Per-panel diff detection
// so unchanged panels are not re-rendered. All user-authored content
// rendered via textContent / appendChild — no innerHTML except for
// hardcoded chrome marked `// chrome-only`.
//
// Phase 7 adds drag-and-drop columns for Plans (Drafted/Reviewed/Ready)
// and Issues (Triage/Ready), POSTs the full queue back to /api/queue
// on every reorder, polls /api/work-state for the Run/Status widget,
// and POSTs to /api/trigger and /api/work-state/reset.

const POLL_INTERVAL_MS = 2000;
const STATE_URL = "/api/state";
const WORK_STATE_URL = "/api/work-state";
const QUEUE_URL = "/api/queue";
const TRIGGER_URL = "/api/trigger";
const WORK_STATE_RESET_URL = "/api/work-state/reset";

// After a successful POST, suppress the next /api/state poll to avoid
// flicker from a stale GET that started before the POST landed.
const POST_RECONCILE_SUPPRESS_MS = 1500;

const PLAN_COLUMNS = ["drafted", "reviewed", "ready"];
const ISSUE_COLUMNS = ["triage", "ready"];
const PLAN_COLUMN_LABELS = {
  drafted: "Drafted",
  reviewed: "Reviewed",
  ready: "Ready",
};
const ISSUE_COLUMN_LABELS = {
  triage: "Triage",
  ready: "Ready",
};

// ---------------------------------------------------------------- helpers

function $(id) {
  return document.getElementById(id);
}

function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
}

function el(tag, opts) {
  const node = document.createElement(tag);
  if (!opts) return node;
  if (opts.cls) node.className = opts.cls;
  if (opts.text != null) node.textContent = String(opts.text);
  if (opts.attrs) {
    for (const k of Object.keys(opts.attrs)) {
      const v = opts.attrs[k];
      if (v != null) node.setAttribute(k, String(v));
    }
  }
  return node;
}

function relativeTime(iso) {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "";
  const diffMs = Date.now() - t;
  const sec = Math.round(diffMs / 1000);
  if (sec < 0) return "just now";
  if (sec < 60) return sec + "s ago";
  const min = Math.round(sec / 60);
  if (min < 60) return min + "m ago";
  const hr = Math.round(min / 60);
  if (hr < 24) return hr + "h ago";
  const day = Math.round(hr / 24);
  if (day < 30) return day + "d ago";
  const mo = Math.round(day / 30);
  if (mo < 12) return mo + "mo ago";
  return Math.round(mo / 12) + "y ago";
}

function ageSecondsToText(s) {
  if (s == null || s < 0) return "";
  if (s < 60) return s + "s";
  if (s < 3600) return Math.round(s / 60) + "m";
  if (s < 86400) return Math.round(s / 3600) + "h";
  return Math.round(s / 86400) + "d";
}

function basename(p) {
  if (!p) return "";
  const cleaned = String(p).replace(/\/+$/, "");
  const idx = cleaned.lastIndexOf("/");
  return idx >= 0 ? cleaned.slice(idx + 1) : cleaned;
}

function formatLocalTime(iso) {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "";
  const d = new Date(t);
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return hh + ":" + mm;
}

// --------------------------------------------------------------- snapshot

let lastSnapshot = null;
let lastWorkState = null;
const lastFingerprint = {
  errors: null,
  plans: null,
  branches: null,
  worktrees: null,
  issues: null,
  activity: null,
  workState: null,
  defaultMode: null,
};
let pollTimer = null;
let pollAbort = null;
let workPollTimer = null;
let workPollAbort = null;
let suppressNextStatePollUntil = 0;

// last-known-good queues — used to revert local DOM on POST failure.
let lastGoodQueues = null;
let lastGoodDefaultMode = "phase";

function setConnected(ok) {
  const banner = $("conn-banner");
  if (ok) {
    banner.hidden = true;
  } else {
    banner.hidden = false;
  }
}

async function fetchState() {
  const ctrl = new AbortController();
  pollAbort = ctrl;
  try {
    const res = await fetch(STATE_URL, {
      cache: "no-store",
      signal: ctrl.signal,
    });
    if (!res.ok) {
      setConnected(false);
      return null;
    }
    const data = await res.json();
    setConnected(true);
    return data;
  } catch (_err) {
    setConnected(false);
    return null;
  } finally {
    if (pollAbort === ctrl) pollAbort = null;
  }
}

async function fetchWorkState() {
  const ctrl = new AbortController();
  workPollAbort = ctrl;
  try {
    const res = await fetch(WORK_STATE_URL, {
      cache: "no-store",
      signal: ctrl.signal,
    });
    if (!res.ok) return null;
    return await res.json();
  } catch (_err) {
    return null;
  } finally {
    if (workPollAbort === ctrl) workPollAbort = null;
  }
}

function schedulePoll(delay) {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = setTimeout(pollOnce, delay);
}

function scheduleWorkPoll(delay) {
  if (workPollTimer) clearTimeout(workPollTimer);
  workPollTimer = setTimeout(pollWorkOnce, delay);
}

async function pollOnce() {
  if (document.hidden) {
    pollTimer = null;
    return;
  }
  // Reconciliation: skip a single state poll right after a successful
  // POST, so a GET in flight before the POST lands cannot flash stale
  // data over the user's just-applied reorder.
  if (Date.now() < suppressNextStatePollUntil) {
    schedulePoll(POLL_INTERVAL_MS);
    return;
  }
  const snap = await fetchState();
  if (snap) {
    lastSnapshot = snap;
    applySnapshot(snap);
  }
  schedulePoll(POLL_INTERVAL_MS);
}

async function pollWorkOnce() {
  if (document.hidden) {
    workPollTimer = null;
    return;
  }
  const ws = await fetchWorkState();
  if (ws) {
    lastWorkState = ws;
    applyWorkState(ws);
  }
  scheduleWorkPoll(POLL_INTERVAL_MS);
}

function applySnapshot(snap) {
  const updated = $("updated-at");
  if (updated) updated.textContent = "Updated " + relativeTime(snap.updated_at);

  // Errors banner uses JSON-stringified array as fingerprint (DA-10).
  const errFp = JSON.stringify(snap.errors || []);
  if (errFp !== lastFingerprint.errors) {
    lastFingerprint.errors = errFp;
    renderErrors(snap.errors || []);
  }

  // Capture last-known-good queues from snapshot.queues (server's view).
  const queues = snap.queues || { plans: {}, issues: {}, default_mode: "phase" };
  lastGoodQueues = deepCloneQueues(queues, snap.plans || [], snap.issues || []);
  lastGoodDefaultMode = queues.default_mode || "phase";

  const dmFp = String(lastGoodDefaultMode);
  if (dmFp !== lastFingerprint.defaultMode) {
    lastFingerprint.defaultMode = dmFp;
    renderDefaultMode(lastGoodDefaultMode);
  }

  const plansFp = fingerprintPlans(snap.plans || [], queues, lastGoodDefaultMode);
  if (plansFp !== lastFingerprint.plans) {
    lastFingerprint.plans = plansFp;
    renderPlans(snap.plans || [], queues, lastGoodDefaultMode);
  }

  const branchesFp = fingerprintBranches(snap.branches || [], snap.worktrees || []);
  if (branchesFp !== lastFingerprint.branches) {
    lastFingerprint.branches = branchesFp;
    renderBranches(snap.branches || [], snap.worktrees || []);
  }

  const issuesFp = fingerprintIssues(snap.issues || [], queues);
  if (issuesFp !== lastFingerprint.issues) {
    lastFingerprint.issues = issuesFp;
    renderIssues(snap.issues || [], queues);
  }

  const wtFp = fingerprintWorktrees(snap.worktrees || []);
  if (wtFp !== lastFingerprint.worktrees) {
    lastFingerprint.worktrees = wtFp;
    renderWorktrees(snap.worktrees || []);
  }

  const actFp = fingerprintActivity(snap.activity || []);
  if (actFp !== lastFingerprint.activity) {
    lastFingerprint.activity = actFp;
    renderActivity(snap.activity || []);
  }
}

function applyWorkState(ws) {
  const fp = JSON.stringify(ws);
  if (fp !== lastFingerprint.workState) {
    lastFingerprint.workState = fp;
    renderRunStatus(ws);
    renderDefaultModeFootnote(ws);
  }
}

// Build a queues dict that contains every plan/issue, populated from
// state where present and inferred from snapshot column hints otherwise.
// This is the local "source of truth" the UI POSTs back on every drag.
function deepCloneQueues(queues, plans, issues) {
  const out = {
    default_mode: queues.default_mode || "phase",
    plans: {},
    issues: {},
  };
  for (const c of PLAN_COLUMNS) out.plans[c] = [];
  for (const c of ISSUE_COLUMNS) out.issues[c] = [];

  // Pre-populate from queues (preserves order).
  const seenSlugs = new Set();
  for (const c of PLAN_COLUMNS) {
    const arr = (queues.plans && queues.plans[c]) || [];
    for (const e of arr) {
      const entry = (typeof e === "string") ? { slug: e } : (e || {});
      if (!entry.slug || seenSlugs.has(entry.slug)) continue;
      seenSlugs.add(entry.slug);
      const obj = { slug: entry.slug };
      if (c === "ready" && entry.mode != null) obj.mode = entry.mode;
      out.plans[c].push(obj);
    }
  }
  // Add inferred entries for plans not present in state.
  for (const p of plans) {
    if (seenSlugs.has(p.slug)) continue;
    const col = (p.queue && p.queue.column) || "drafted";
    if (PLAN_COLUMNS.indexOf(col) < 0) continue;
    seenSlugs.add(p.slug);
    out.plans[col].push({ slug: p.slug });
  }

  const seenNums = new Set();
  for (const c of ISSUE_COLUMNS) {
    const arr = (queues.issues && queues.issues[c]) || [];
    for (const n of arr) {
      const num = parseInt(n, 10);
      if (!Number.isFinite(num) || seenNums.has(num)) continue;
      seenNums.add(num);
      out.issues[c].push(num);
    }
  }
  for (const it of issues) {
    if (typeof it.number !== "number" || seenNums.has(it.number)) continue;
    const col = (it.queue && it.queue.column) || "triage";
    if (ISSUE_COLUMNS.indexOf(col) < 0) continue;
    seenNums.add(it.number);
    out.issues[col].push(it.number);
  }
  return out;
}

function fingerprintPlans(plans, queues, defaultMode) {
  // Include queue position so reorders re-render.
  const pos = {};
  for (const c of PLAN_COLUMNS) {
    const arr = (queues.plans && queues.plans[c]) || [];
    for (let i = 0; i < arr.length; i++) {
      const e = arr[i];
      const slug = (typeof e === "string") ? e : (e && e.slug);
      if (slug) pos[slug] = [c, i, (e && e.mode) || null];
    }
  }
  return JSON.stringify({
    dm: defaultMode,
    rows: plans.map(p => [
      p.slug, p.title, p.status, p.landing_mode,
      p.phase_count, p.phases_done, p.blurb,
      pos[p.slug] || [(p.queue && p.queue.column) || "drafted", -1, null],
    ]),
  });
}

function fingerprintBranches(branches, worktrees) {
  const wtSet = backedBranchSet(worktrees);
  return JSON.stringify(branches.map(b => [
    b.name, b.last_commit_at, b.last_commit_subject, b.upstream, wtSet.has(b.name),
  ]));
}

function fingerprintIssues(issues, queues) {
  const pos = {};
  for (const c of ISSUE_COLUMNS) {
    const arr = (queues.issues && queues.issues[c]) || [];
    for (let i = 0; i < arr.length; i++) {
      const n = parseInt(arr[i], 10);
      if (Number.isFinite(n)) pos[n] = [c, i];
    }
  }
  return JSON.stringify(issues.map(i => [
    i.number, i.title, (i.labels || []).slice().sort(), i.created_at,
    pos[i.number] || [(i.queue && i.queue.column) || "triage", -1],
  ]));
}

function fingerprintWorktrees(wts) {
  return JSON.stringify(wts.map(w => [
    w.path, w.branch, w.category, w.age_seconds,
    w.landed ? w.landed.status : null,
  ]));
}

function fingerprintActivity(act) {
  return JSON.stringify(act.slice(0, 20).map(a => [
    a.timestamp, a.pipeline, a.kind, a.id, a.skill, a.status, a.parent,
  ]));
}

// ---------------------------------------------------------------- errors

function renderErrors(errors) {
  const banner = $("errors-banner");
  const list = $("errors-list");
  clear(list);
  if (!errors.length) {
    banner.hidden = true;
    return;
  }
  banner.hidden = false;
  for (const e of errors) {
    const li = el("li");
    const src = el("span", { cls: "err-source", text: (e.source || "error") + ":" });
    const msg = el("span", { text: " " + (e.message || "") });
    li.appendChild(src);
    li.appendChild(msg);
    list.appendChild(li);
  }
}

// ----------------------------------------------------------------- plans

function statusPillClass(status) {
  const s = (status || "").toLowerCase();
  if (s === "done") return "pill-status-done";
  if (s === "blocked") return "pill-status-blocked";
  if (s === "paused") return "pill-status-paused";
  return "pill-status-active";
}

function modePillClass(mode) {
  const m = (mode || "").toLowerCase();
  if (m === "pr") return "pill-mode-pr";
  if (m === "direct") return "pill-mode-direct";
  return "pill-mode-unknown";
}

function planBySlug(plans, slug) {
  for (const p of plans) {
    if (p.slug === slug) return p;
  }
  return null;
}

function buildPlanCard(plan, slug, col, defaultMode) {
  const card = el("li", {
    cls: "card",
    attrs: {
      role: "listitem",
      tabindex: "0",
      draggable: "true",
      "data-kind": "plan",
      "data-slug": slug,
      "data-column": col,
      "aria-label": "Plan " + (plan ? (plan.title || slug) : slug),
    },
  });
  const head = el("div", { cls: "card-row" });
  head.appendChild(el("span", {
    cls: "card-title",
    text: (plan && plan.title) || slug,
  }));
  if (plan && plan.status) {
    const statusPill = el("span", {
      cls: "pill " + statusPillClass(plan.status),
      text: plan.status,
    });
    head.appendChild(statusPill);
  }
  card.appendChild(head);

  if (plan && plan.blurb) {
    card.appendChild(el("div", { cls: "card-blurb", text: plan.blurb }));
  }

  if (plan) {
    const meta = el("div", { cls: "card-row card-sub" });
    const ratio = (plan.phases_done || 0) + " / " + (plan.phase_count || 0) + " phases";
    meta.appendChild(el("span", { text: ratio }));
    const modePill = el("span", {
      cls: "pill " + modePillClass(plan.landing_mode),
      text: "mode: " + (plan.landing_mode || "unknown"),
    });
    meta.appendChild(modePill);
    card.appendChild(meta);

    const total = plan.phase_count || 0;
    const done = plan.phases_done || 0;
    if (total > 0) {
      const bar = el("div", { cls: "progress" });
      const fill = el("div", { cls: "progress-fill" });
      const pct = Math.max(0, Math.min(100, Math.round((done / total) * 100)));
      fill.style.width = pct + "%";
      bar.appendChild(fill);
      card.appendChild(bar);
    }
  }

  // Per-row mode chip on Ready cards (Phase 7).
  if (col === "ready") {
    const entryMode = currentEntryMode(slug);
    const isOverride = entryMode === "phase" || entryMode === "finish";
    const displayMode = isOverride ? entryMode : (defaultMode || "phase");
    const chip = el("button", {
      cls: "mode-chip",
      attrs: {
        type: "button",
        "data-action": "toggle-mode",
        "data-slug": slug,
        "data-source": isOverride ? "explicit" : "inherit",
        "aria-label": (
          isOverride
            ? ("Mode: " + displayMode + " (override). Click to toggle.")
            : ("Mode: " + displayMode + " (inherits default). Click to set explicit.")
        ),
      },
      text: displayMode,
    });
    card.appendChild(chip);
  }

  // Card controls: ↑ ↓ ← → and remove
  const controls = el("div", {
    cls: "card-controls",
    attrs: { role: "group", "aria-label": "Move this plan" },
  });
  controls.appendChild(makeMoveBtn("plan-up", slug, "↑", "Move up"));
  controls.appendChild(makeMoveBtn("plan-down", slug, "↓", "Move down"));
  controls.appendChild(makeMoveBtn("plan-left", slug, "←", "Move to previous column"));
  controls.appendChild(makeMoveBtn("plan-right", slug, "→", "Move to next column"));
  controls.appendChild(el("button", {
    cls: "remove-btn",
    attrs: {
      type: "button",
      "data-action": "plan-remove",
      "data-slug": slug,
      "aria-label": "Remove from queue",
    },
    text: "✕",
  }));
  card.appendChild(controls);

  return card;
}

function makeMoveBtn(action, slug, label, ariaLabel) {
  return el("button", {
    cls: "move-btn",
    attrs: {
      type: "button",
      "data-action": action,
      "data-slug": slug,
      "aria-label": ariaLabel,
    },
    text: label,
  });
}

function makeIssueMoveBtn(action, num, label, ariaLabel) {
  return el("button", {
    cls: "move-btn",
    attrs: {
      type: "button",
      "data-action": action,
      "data-number": String(num),
      "aria-label": ariaLabel,
    },
    text: label,
  });
}

function currentEntryMode(slug) {
  if (!lastGoodQueues) return null;
  const arr = lastGoodQueues.plans.ready || [];
  for (const e of arr) {
    if (e && e.slug === slug) return e.mode || null;
  }
  return null;
}

function renderPlans(plans, queues, defaultMode) {
  const body = $("plans-body");
  const empty = $("plans-empty");
  clear(body);
  if (!plans.length && allColumnsEmpty(queues.plans, PLAN_COLUMNS)) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;

  const slugToPlan = {};
  for (const p of plans) slugToPlan[p.slug] = p;

  const cols = el("div", { cls: "columns columns-3" });
  for (const c of PLAN_COLUMNS) {
    const colDiv = el("div", { cls: "column" });
    const headId = "plans-col-" + c;
    const head = el("div", { cls: "column-head", attrs: { id: headId } });
    head.appendChild(el("span", { text: PLAN_COLUMN_LABELS[c] }));
    const arr = (lastGoodQueues && lastGoodQueues.plans[c]) || [];
    head.appendChild(el("span", { cls: "muted", text: String(arr.length) }));
    colDiv.appendChild(head);

    const ul = el("ul", {
      cls: "dropzone",
      attrs: {
        role: "list",
        "data-column": c,
        "data-kind": "plan",
        "aria-labelledby": headId,
      },
    });
    for (const entry of arr) {
      const slug = (typeof entry === "string") ? entry : (entry && entry.slug);
      if (!slug) continue;
      const card = buildPlanCard(slugToPlan[slug] || null, slug, c, defaultMode);
      ul.appendChild(card);
    }
    colDiv.appendChild(ul);
    cols.appendChild(colDiv);
  }
  body.appendChild(cols);
}

function allColumnsEmpty(colsObj, columnNames) {
  if (!colsObj) return true;
  for (const c of columnNames) {
    const arr = colsObj[c] || [];
    if (arr.length) return false;
  }
  return true;
}

function renderDefaultMode(mode) {
  const phase = $("dm-phase");
  const finish = $("dm-finish");
  if (!phase || !finish) return;
  const isPhase = mode === "phase";
  phase.setAttribute("aria-pressed", isPhase ? "true" : "false");
  finish.setAttribute("aria-pressed", isPhase ? "false" : "true");
}

function renderDefaultModeFootnote(ws) {
  const note = $("default-mode-footnote");
  if (!note) return;
  const inFlight = ws && ws.state === "sprint";
  note.hidden = !inFlight;
}

// -------------------------------------------------------------- branches

function backedBranchSet(worktrees) {
  const set = new Set();
  for (const w of worktrees || []) {
    if (w && w.branch) set.add(w.branch);
  }
  return set;
}

function renderBranches(branches, worktrees) {
  const body = $("branches-body");
  const empty = $("branches-empty");
  clear(body);
  if (!branches.length) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  const backed = backedBranchSet(worktrees);
  for (const b of branches) {
    const dim = backed.has(b.name);
    const card = el("article", {
      cls: dim ? "card dim" : "card",
      attrs: {
        tabindex: "0",
        role: "button",
        "data-kind": "branch",
        "data-name": b.name,
        "aria-label": "Branch " + b.name,
      },
    });
    const head = el("div", { cls: "card-row" });
    head.appendChild(el("span", { cls: "card-title mono", text: b.name }));
    if (b.last_commit_at) {
      head.appendChild(el("span", { cls: "card-sub", text: relativeTime(b.last_commit_at) }));
    }
    card.appendChild(head);
    if (b.last_commit_subject) {
      card.appendChild(el("div", { cls: "card-blurb", text: b.last_commit_subject }));
    }
    if (b.upstream) {
      card.appendChild(el("div", { cls: "card-sub", text: "upstream: " + b.upstream }));
    }
    body.appendChild(card);
  }
}

// ---------------------------------------------------------------- issues

function buildIssueCard(issue, num, col) {
  const card = el("li", {
    cls: "card",
    attrs: {
      role: "listitem",
      tabindex: "0",
      draggable: "true",
      "data-kind": "issue",
      "data-number": String(num),
      "data-column": col,
      "aria-label": "Issue #" + num,
    },
  });
  const head = el("div", { cls: "card-row" });
  head.appendChild(el("span", {
    cls: "card-title",
    text: issue ? ("#" + num + " " + (issue.title || "")) : ("#" + num),
  }));
  if (issue && issue.created_at) {
    head.appendChild(el("span", { cls: "card-sub", text: relativeTime(issue.created_at) }));
  }
  card.appendChild(head);
  if (issue && (issue.labels || []).length) {
    const labels = el("div", { cls: "card-sub" });
    for (const lab of issue.labels) {
      labels.appendChild(el("span", { cls: "label-chip", text: lab }));
    }
    card.appendChild(labels);
  }
  const controls = el("div", {
    cls: "card-controls",
    attrs: { role: "group", "aria-label": "Move this issue" },
  });
  controls.appendChild(makeIssueMoveBtn("issue-up", num, "↑", "Move up"));
  controls.appendChild(makeIssueMoveBtn("issue-down", num, "↓", "Move down"));
  controls.appendChild(makeIssueMoveBtn("issue-left", num, "←", "Move to previous column"));
  controls.appendChild(makeIssueMoveBtn("issue-right", num, "→", "Move to next column"));
  controls.appendChild(el("button", {
    cls: "remove-btn",
    attrs: {
      type: "button",
      "data-action": "issue-remove",
      "data-number": String(num),
      "aria-label": "Remove issue from queue",
    },
    text: "✕",
  }));
  card.appendChild(controls);
  return card;
}

function renderIssues(issues, queues) {
  const body = $("issues-body");
  const empty = $("issues-empty");
  clear(body);
  if (!issues.length && allColumnsEmpty(queues.issues, ISSUE_COLUMNS)) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;

  const numToIssue = {};
  for (const it of issues) numToIssue[it.number] = it;

  const cols = el("div", { cls: "columns columns-2" });
  for (const c of ISSUE_COLUMNS) {
    const colDiv = el("div", { cls: "column" });
    const headId = "issues-col-" + c;
    const head = el("div", { cls: "column-head", attrs: { id: headId } });
    head.appendChild(el("span", { text: ISSUE_COLUMN_LABELS[c] }));
    const arr = (lastGoodQueues && lastGoodQueues.issues[c]) || [];
    head.appendChild(el("span", { cls: "muted", text: String(arr.length) }));
    colDiv.appendChild(head);

    const ul = el("ul", {
      cls: "dropzone",
      attrs: {
        role: "list",
        "data-column": c,
        "data-kind": "issue",
        "aria-labelledby": headId,
      },
    });
    for (const num of arr) {
      const n = parseInt(num, 10);
      if (!Number.isFinite(n)) continue;
      const card = buildIssueCard(numToIssue[n] || null, n, c);
      ul.appendChild(card);
    }
    colDiv.appendChild(ul);
    cols.appendChild(colDiv);
  }
  body.appendChild(cols);
}

// ------------------------------------------------------------- worktrees

function landedPillClass(status) {
  const s = (status || "").toLowerCase();
  if (s === "full") return "pill-landed-full";
  if (s === "partial") return "pill-landed-partial";
  return "pill-landed-not";
}

function renderWorktrees(wts) {
  const body = $("worktrees-body");
  const empty = $("worktrees-empty");
  clear(body);
  if (!wts.length) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  for (const w of wts) {
    const row = el("article", {
      cls: "card",
      attrs: {
        tabindex: "0",
        role: "button",
        "data-kind": "worktree",
        "data-path": w.path,
        "aria-label": "Worktree " + basename(w.path),
      },
    });
    const head = el("div", { cls: "card-row" });
    head.appendChild(el("span", { cls: "card-title mono", text: basename(w.path) }));
    const status = w.landed ? w.landed.status : "not-landed";
    head.appendChild(el("span", {
      cls: "pill " + landedPillClass(status),
      text: status,
    }));
    row.appendChild(head);
    const meta = el("div", { cls: "card-sub" });
    meta.appendChild(el("span", { text: "branch: " + (w.branch || "?") }));
    if (w.age_seconds != null) {
      meta.appendChild(el("span", { text: " · " + ageSecondsToText(w.age_seconds) }));
    }
    row.appendChild(meta);
    body.appendChild(row);
  }
}

// --------------------------------------------------------------- activity

function activityStatusClass(status) {
  const s = (status || "").toLowerCase();
  if (s === "pass" || s === "ok" || s === "complete" || s === "completed") return "a-status-pass";
  if (s === "fail" || s === "failed" || s === "error") return "a-status-fail";
  if (s === "running" || s === "started" || s === "in-progress") return "a-status-running";
  return "";
}

function renderActivity(activity) {
  const body = $("activity-body");
  const empty = $("activity-empty");
  clear(body);
  const rows = activity.slice(0, 20);
  if (!rows.length) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  for (const a of rows) {
    const row = el("div", { cls: "activity-row" });
    row.appendChild(el("span", { cls: "a-pipe mono", text: a.pipeline || "(legacy)" }));
    const mid = el("span");
    if (a.skill) {
      mid.appendChild(el("span", { cls: "a-skill mono", text: a.skill }));
    }
    mid.appendChild(el("span", { text: " " + (a.kind || "") + (a.id ? " " + a.id : "") }));
    if (a.status) {
      const cls = activityStatusClass(a.status);
      mid.appendChild(el("span", { cls: cls ? "pill " + cls : "pill", text: a.status }));
    }
    if (a.parent) {
      mid.appendChild(el("span", { cls: "a-parent", text: "← " + a.parent }));
    }
    row.appendChild(mid);
    row.appendChild(el("span", { cls: "a-time", text: relativeTime(a.timestamp) }));
    body.appendChild(row);
  }
}

// ----------------------------------------------------------- run-status

function renderRunStatus(ws) {
  const root = $("run-status");
  if (!root) return;
  clear(root);
  root.classList.remove("run-status-stale");
  const state = (ws && ws.state) || "idle";
  const warning = ws && ws.warning;

  if (state === "scheduled") {
    const sched = ws.schedule || "every ?h";
    const next = ws.next_fire_at ? formatLocalTime(ws.next_fire_at) : "?";
    root.appendChild(el("span", { cls: "run-label", text: "Schedule:" }));
    root.appendChild(el("span", {
      cls: "run-text",
      text: "Running " + sched + " · next fire " + next,
    }));
    const stop = el("button", {
      cls: "run-stop-btn",
      attrs: { type: "button", "data-action": "run-stop" },
      text: "Stop",
    });
    root.appendChild(stop);
    return;
  }
  if (state === "sprint") {
    const prog = ws.progress || {};
    const done = (prog.done != null) ? prog.done : 0;
    const total = (prog.total != null) ? prog.total : 0;
    const cur = prog.current_slug || "?";
    root.appendChild(el("span", { cls: "run-label", text: "Sprint:" }));
    root.appendChild(el("span", {
      cls: "run-text",
      text: "in progress: " + done + "/" + total + " plans done · current: " + cur,
    }));
    return;
  }
  if (state === "stale-scheduled") {
    root.classList.add("run-status-stale");
    root.appendChild(el("span", {
      cls: "run-text",
      text: "Schedule appears stale — restart with /work-on-plans every 4h",
    }));
    return;
  }
  if (state === "stale-sprint") {
    root.classList.add("run-status-stale");
    root.appendChild(el("span", {
      cls: "run-text",
      text: "Sprint appears abandoned (last update " + (ws.updated_at ? relativeTime(ws.updated_at) : "?") + ")",
    }));
    const clearBtn = el("button", {
      cls: "clear-stale-btn",
      attrs: { type: "button", "data-action": "clear-stale-sprint" },
      text: "Clear stale sprint state",
    });
    root.appendChild(clearBtn);
    return;
  }

  // idle (default)
  if (warning) {
    root.classList.add("run-status-stale");
    root.appendChild(el("span", { cls: "run-text", text: warning }));
  }
  const triggerConfigured = !!(ws && ws.trigger_configured);
  const dm = lastGoodDefaultMode || "phase";
  if (triggerConfigured) {
    root.appendChild(el("span", { cls: "run-label", text: "Idle:" }));
    const nInput = el("input", {
      cls: "run-n-input",
      attrs: {
        type: "number",
        min: "1",
        max: "99",
        value: "3",
        id: "run-n",
        "aria-label": "Number of plans to run",
      },
    });
    root.appendChild(nInput);
    const runBtn = el("button", {
      cls: "run-btn primary",
      attrs: { type: "button", "data-action": "run-top-n" },
      text: "▶ Run top N",
    });
    root.appendChild(runBtn);
  } else {
    root.appendChild(el("span", { cls: "run-label", text: "Copy and run:" }));
    const cmd = "/work-on-plans 3 " + dm;
    root.appendChild(el("code", { cls: "run-cmd-snippet", text: cmd }));
    const copyBtn = el("button", {
      cls: "copy-btn",
      attrs: { type: "button", "data-action": "copy-cmd", "data-cmd": cmd },
      text: "Copy",
    });
    root.appendChild(copyBtn);
  }
}

// ---------------------------------------------------------------- toasts

function showToast(message, kind) {
  const region = $("toast-region");
  if (!region) return;
  const toast = el("div", { cls: "toast " + (kind === "info" ? "toast-info" : "") });
  toast.appendChild(el("span", { text: String(message || "") }));
  const close = el("button", {
    cls: "toast-close",
    attrs: { type: "button", "aria-label": "Dismiss" },
    text: "×",
  });
  close.addEventListener("click", () => {
    if (toast.parentNode) toast.parentNode.removeChild(toast);
  });
  toast.appendChild(close);
  region.appendChild(toast);
  // Auto-dismiss after 8s.
  setTimeout(() => {
    if (toast.parentNode) toast.parentNode.removeChild(toast);
  }, 8000);
}

function announce(regionId, msg) {
  const region = $(regionId);
  if (!region) return;
  // Empty + repopulate so SRs re-announce identical text.
  region.textContent = "";
  // Force layout flush before reassign.
  void region.offsetHeight;
  region.textContent = msg;
}

// --------------------------------------------------------- POST queue

async function postQueue(queues, opts) {
  // Returns true on success; on failure shows toast and returns false.
  const payload = {
    default_mode: queues.default_mode || "phase",
    plans: queues.plans,
    issues: queues.issues,
  };
  let res;
  try {
    res = await fetch(QUEUE_URL, {
      method: "POST",
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    showToast("POST /api/queue failed: " + (err && err.message ? err.message : err), "err");
    return false;
  }
  if (!res.ok) {
    let body = "";
    try { body = await res.text(); } catch (_e) { /* ignore */ }
    const action = (opts && opts.action) || "update";
    showToast(action + " failed (" + res.status + "): " + body.slice(0, 240), "err");
    return false;
  }
  // Reconcile: suppress next state poll for ~1.5s to avoid stale-GET flicker.
  suppressNextStatePollUntil = Date.now() + POST_RECONCILE_SUPPRESS_MS;
  return true;
}

async function commitQueueChange(newQueues, opts) {
  const previous = lastGoodQueues
    ? JSON.parse(JSON.stringify(lastGoodQueues))
    : null;
  // Optimistic: snap UI to new queues immediately.
  lastGoodQueues = newQueues;
  if (newQueues.default_mode) lastGoodDefaultMode = newQueues.default_mode;
  // Force re-render now (don't wait for next poll).
  const snap = lastSnapshot || { plans: [], issues: [] };
  renderDefaultMode(lastGoodDefaultMode);
  renderPlans(snap.plans || [], lastGoodQueues, lastGoodDefaultMode);
  renderIssues(snap.issues || [], lastGoodQueues);
  lastFingerprint.plans = fingerprintPlans(snap.plans || [], lastGoodQueues, lastGoodDefaultMode);
  lastFingerprint.issues = fingerprintIssues(snap.issues || [], lastGoodQueues);
  lastFingerprint.defaultMode = String(lastGoodDefaultMode);

  const ok = await postQueue(newQueues, opts);
  if (!ok && previous) {
    // Revert immediately; do not wait for next poll.
    lastGoodQueues = previous;
    lastGoodDefaultMode = previous.default_mode || "phase";
    renderDefaultMode(lastGoodDefaultMode);
    renderPlans(snap.plans || [], lastGoodQueues, lastGoodDefaultMode);
    renderIssues(snap.issues || [], lastGoodQueues);
    lastFingerprint.plans = fingerprintPlans(snap.plans || [], lastGoodQueues, lastGoodDefaultMode);
    lastFingerprint.issues = fingerprintIssues(snap.issues || [], lastGoodQueues);
    lastFingerprint.defaultMode = String(lastGoodDefaultMode);
  }
  return ok;
}

// ----------------------------------------------------- queue-mutation ops

function findPlan(queues, slug) {
  for (const c of PLAN_COLUMNS) {
    const arr = queues.plans[c];
    for (let i = 0; i < arr.length; i++) {
      if (arr[i].slug === slug) return { col: c, idx: i };
    }
  }
  return null;
}

function findIssue(queues, num) {
  for (const c of ISSUE_COLUMNS) {
    const arr = queues.issues[c];
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] === num) return { col: c, idx: i };
    }
  }
  return null;
}

function clonedQueues() {
  return lastGoodQueues
    ? JSON.parse(JSON.stringify(lastGoodQueues))
    : {
        default_mode: "phase",
        plans: { drafted: [], reviewed: [], ready: [] },
        issues: { triage: [], ready: [] },
      };
}

async function movePlan(slug, dCol, dIdxAdjust) {
  const next = clonedQueues();
  const loc = findPlan(next, slug);
  if (!loc) return;
  const entry = next.plans[loc.col].splice(loc.idx, 1)[0];
  let targetCol = loc.col;
  let targetIdx = loc.idx;
  if (dCol === "up") {
    targetIdx = Math.max(0, loc.idx - 1);
  } else if (dCol === "down") {
    targetIdx = Math.min(next.plans[loc.col].length, loc.idx + 1);
  } else if (dCol === "left") {
    const ci = PLAN_COLUMNS.indexOf(loc.col);
    if (ci <= 0) {
      // Restore — no-op.
      next.plans[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = PLAN_COLUMNS[ci - 1];
    targetIdx = next.plans[targetCol].length;
  } else if (dCol === "right") {
    const ci = PLAN_COLUMNS.indexOf(loc.col);
    if (ci >= PLAN_COLUMNS.length - 1) {
      next.plans[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = PLAN_COLUMNS[ci + 1];
    targetIdx = next.plans[targetCol].length;
  } else if (typeof dCol === "object" && dCol && dCol.col) {
    targetCol = dCol.col;
    targetIdx = (dCol.idx == null) ? next.plans[targetCol].length : dCol.idx;
  }
  next.plans[targetCol].splice(targetIdx, 0, entry);
  const ok = await commitQueueChange(next, { action: "Move plan" });
  if (ok) {
    announce("plans-live", "Moved plan " + slug + " to " + PLAN_COLUMN_LABELS[targetCol] + " position " + (targetIdx + 1));
  }
}

async function removePlan(slug) {
  const next = clonedQueues();
  const loc = findPlan(next, slug);
  if (!loc) return;
  next.plans[loc.col].splice(loc.idx, 1);
  const ok = await commitQueueChange(next, { action: "Remove plan" });
  if (ok) announce("plans-live", "Removed plan " + slug);
}

async function moveIssue(num, dCol) {
  const next = clonedQueues();
  const loc = findIssue(next, num);
  if (!loc) return;
  const entry = next.issues[loc.col].splice(loc.idx, 1)[0];
  let targetCol = loc.col;
  let targetIdx = loc.idx;
  if (dCol === "up") {
    targetIdx = Math.max(0, loc.idx - 1);
  } else if (dCol === "down") {
    targetIdx = Math.min(next.issues[loc.col].length, loc.idx + 1);
  } else if (dCol === "left") {
    const ci = ISSUE_COLUMNS.indexOf(loc.col);
    if (ci <= 0) {
      next.issues[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = ISSUE_COLUMNS[ci - 1];
    targetIdx = next.issues[targetCol].length;
  } else if (dCol === "right") {
    const ci = ISSUE_COLUMNS.indexOf(loc.col);
    if (ci >= ISSUE_COLUMNS.length - 1) {
      next.issues[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = ISSUE_COLUMNS[ci + 1];
    targetIdx = next.issues[targetCol].length;
  } else if (typeof dCol === "object" && dCol && dCol.col) {
    targetCol = dCol.col;
    targetIdx = (dCol.idx == null) ? next.issues[targetCol].length : dCol.idx;
  }
  next.issues[targetCol].splice(targetIdx, 0, entry);
  const ok = await commitQueueChange(next, { action: "Move issue" });
  if (ok) {
    announce("issues-live", "Moved issue #" + num + " to " + ISSUE_COLUMN_LABELS[targetCol] + " position " + (targetIdx + 1));
  }
}

async function removeIssue(num) {
  const next = clonedQueues();
  const loc = findIssue(next, num);
  if (!loc) return;
  next.issues[loc.col].splice(loc.idx, 1);
  const ok = await commitQueueChange(next, { action: "Remove issue" });
  if (ok) announce("issues-live", "Removed issue #" + num);
}

async function setDefaultMode(mode) {
  if (mode !== "phase" && mode !== "finish") return;
  if (mode === lastGoodDefaultMode) return;
  const next = clonedQueues();
  next.default_mode = mode;
  const ok = await commitQueueChange(next, { action: "Set default mode" });
  if (ok) announce("plans-live", "Default mode: " + mode);
}

async function togglePlanMode(slug) {
  const next = clonedQueues();
  const loc = findPlan(next, slug);
  if (!loc || loc.col !== "ready") return;
  const entry = next.plans[loc.col][loc.idx];
  const cur = entry.mode || null;
  // Cycle: inherit -> phase -> finish -> inherit.
  let newMode;
  if (cur == null) newMode = "phase";
  else if (cur === "phase") newMode = "finish";
  else newMode = null;
  if (newMode == null) {
    delete entry.mode;
  } else {
    entry.mode = newMode;
  }
  const ok = await commitQueueChange(next, { action: "Toggle mode" });
  if (ok) {
    announce("plans-live",
      "Mode for " + slug + " set to " + (newMode || "inherit"));
  }
}

// -------------------------------------------------------------- trigger

async function postTrigger(command) {
  let res;
  try {
    res = await fetch(TRIGGER_URL, {
      method: "POST",
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command }),
    });
  } catch (err) {
    showToast("Trigger failed: " + (err && err.message ? err.message : err), "err");
    return false;
  }
  if (res.status === 501) {
    showToast(
      "No /work-on-plans trigger configured — set dashboard.work_on_plans_trigger in zskills-config.json.",
      "info"
    );
    return false;
  }
  if (!res.ok) {
    let body = "";
    try {
      const data = await res.json();
      body = (data && (data.stderr || data.error)) || "";
    } catch (_e) {
      try { body = await res.text(); } catch (_ignore) { /* */ }
    }
    showToast("Trigger error (" + res.status + "): " + body.slice(0, 240), "err");
    return false;
  }
  let data = null;
  try { data = await res.json(); } catch (_e) { /* */ }
  if (data && data.status === "error") {
    showToast("Trigger script error: " + (data.stderr || "(no stderr)").slice(0, 240), "err");
    return false;
  }
  showToast("Triggered.", "info");
  // Force a fresh work-state poll so the widget updates.
  scheduleWorkPoll(0);
  return true;
}

async function postWorkStateReset() {
  let res;
  try {
    res = await fetch(WORK_STATE_RESET_URL, {
      method: "POST",
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
  } catch (err) {
    showToast("Reset failed: " + (err && err.message ? err.message : err), "err");
    return false;
  }
  if (!res.ok) {
    showToast("Reset failed (" + res.status + ")", "err");
    return false;
  }
  showToast("Sprint state cleared.", "info");
  scheduleWorkPoll(0);
  return true;
}

// -------------------------------------------------------- drag-and-drop

let dragState = null;

function onDragStart(ev) {
  const card = ev.target.closest && ev.target.closest("li.card[draggable='true']");
  if (!card) return;
  const kind = card.getAttribute("data-kind");
  const slug = card.getAttribute("data-slug");
  const num = card.getAttribute("data-number");
  dragState = { kind, slug, num };
  if (ev.dataTransfer) {
    try {
      ev.dataTransfer.setData("text/plain", JSON.stringify(dragState));
      ev.dataTransfer.effectAllowed = "move";
    } catch (_e) { /* some browsers throw on programmatic types */ }
  }
  card.classList.add("dragging");
}

function onDragEnd(ev) {
  const card = ev.target.closest && ev.target.closest("li.card");
  if (card) card.classList.remove("dragging");
  dragState = null;
  const dropzones = document.querySelectorAll(".dropzone.drop-target");
  for (const dz of dropzones) dz.classList.remove("drop-target");
}

function onDragOver(ev) {
  const dz = ev.target.closest && ev.target.closest("ul.dropzone");
  if (!dz) return;
  if (!dragState) return;
  // Kind must match dropzone kind.
  if (dz.getAttribute("data-kind") !== dragState.kind) return;
  ev.preventDefault();
  if (ev.dataTransfer) ev.dataTransfer.dropEffect = "move";
}

function onDragEnter(ev) {
  const dz = ev.target.closest && ev.target.closest("ul.dropzone");
  if (!dz) return;
  if (!dragState) return;
  if (dz.getAttribute("data-kind") !== dragState.kind) return;
  dz.classList.add("drop-target");
}

function onDragLeave(ev) {
  const dz = ev.target.closest && ev.target.closest("ul.dropzone");
  if (!dz) return;
  // relatedTarget is the element being entered; only clear if leaving fully.
  const rel = ev.relatedTarget;
  if (rel && dz.contains(rel)) return;
  dz.classList.remove("drop-target");
}

function computeInsertIndex(dz, clientY) {
  const cards = Array.from(dz.querySelectorAll("li.card:not(.dragging)"));
  for (let i = 0; i < cards.length; i++) {
    const r = cards[i].getBoundingClientRect();
    if (clientY < r.top + r.height / 2) return i;
  }
  return cards.length;
}

async function onDrop(ev) {
  const dz = ev.target.closest && ev.target.closest("ul.dropzone");
  if (!dz) return;
  if (!dragState) return;
  if (dz.getAttribute("data-kind") !== dragState.kind) return;
  ev.preventDefault();
  dz.classList.remove("drop-target");
  const targetCol = dz.getAttribute("data-column");
  const targetIdx = computeInsertIndex(dz, ev.clientY);
  if (dragState.kind === "plan" && dragState.slug) {
    await movePlan(dragState.slug, { col: targetCol, idx: targetIdx });
  } else if (dragState.kind === "issue" && dragState.num) {
    const n = parseInt(dragState.num, 10);
    if (Number.isFinite(n)) await moveIssue(n, { col: targetCol, idx: targetIdx });
  }
  dragState = null;
}

// ------------------------------------------------------------------ modal

const modal = {
  root: null,
  card: null,
  title: null,
  body: null,
  close: null,
  invoker: null,
};

function modalInit() {
  modal.root = $("modal-root");
  modal.card = $("modal-card");
  modal.title = $("modal-title");
  modal.body = $("modal-body");
  modal.close = $("modal-close");
  modal.close.addEventListener("click", closeModal);
  $("modal-backdrop").addEventListener("click", closeModal);
  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape" && !modal.root.hidden) {
      ev.preventDefault();
      closeModal();
    }
  });
  modal.root.addEventListener("keydown", trapFocus);
}

function focusable(node) {
  return Array.from(node.querySelectorAll(
    'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
  )).filter(n => !n.hasAttribute("disabled") && !n.hidden);
}

function trapFocus(ev) {
  if (ev.key !== "Tab") return;
  const items = focusable(modal.card);
  if (!items.length) return;
  const first = items[0];
  const last = items[items.length - 1];
  if (ev.shiftKey && document.activeElement === first) {
    ev.preventDefault();
    last.focus();
  } else if (!ev.shiftKey && document.activeElement === last) {
    ev.preventDefault();
    first.focus();
  }
}

function openModalShell(title) {
  modal.invoker = document.activeElement;
  modal.title.textContent = title;
  clear(modal.body);
  modal.body.appendChild(el("p", { cls: "muted", text: "Loading…" }));
  modal.root.hidden = false;
  modal.close.focus();
}

function closeModal() {
  if (modal.root.hidden) return;
  modal.root.hidden = true;
  clear(modal.body);
  if (modal.invoker && typeof modal.invoker.focus === "function") {
    modal.invoker.focus();
  }
  modal.invoker = null;
}

async function openPlanModal(slug) {
  openModalShell("Plan: " + slug);
  let data;
  try {
    const res = await fetch("/api/plan/" + encodeURIComponent(slug), { cache: "no-store" });
    if (!res.ok) {
      renderModalError("Failed to load plan (" + res.status + ")");
      return;
    }
    data = await res.json();
  } catch (err) {
    renderModalError("Network error: " + err);
    return;
  }
  renderPlanModal(data);
}

function renderModalError(msg) {
  clear(modal.body);
  const p = el("p", { cls: "muted", text: msg });
  modal.body.appendChild(p);
}

function renderPlanModal(plan) {
  modal.title.textContent = plan.title || plan.slug || "Plan";
  clear(modal.body);

  if (plan.blurb) {
    const overview = el("section");
    overview.appendChild(el("h3", { text: "Overview" }));
    overview.appendChild(el("p", { text: plan.blurb }));
    modal.body.appendChild(overview);
  }

  const phasesSec = el("section");
  phasesSec.appendChild(el("h3", { text: "Phases" }));
  const phaseList = el("ul", { cls: "phase-list" });
  for (const ph of plan.phases || []) {
    const li = el("li", { cls: "phase-row" });
    li.appendChild(el("span", { cls: "mono", text: "#" + ph.n }));
    li.appendChild(el("span", { text: ph.name || "" }));
    const right = el("span");
    const statusCls = (() => {
      const s = (ph.status || "").toLowerCase();
      if (s === "done") return "phase-status-done";
      if (s === "active" || s === "in-progress") return "phase-status-active";
      return "phase-status-pending";
    })();
    right.appendChild(el("span", { cls: statusCls, text: ph.status || "pending" }));
    if (ph.commit) {
      right.appendChild(el("span", { cls: "phase-commit-ref", text: " · Landed in " + ph.commit }));
    } else {
      right.appendChild(el("span", { cls: "phase-commit-pending", text: " · Pending" }));
    }
    if (ph.notes) {
      right.appendChild(el("span", { cls: "card-sub", text: " — " + ph.notes }));
    }
    li.appendChild(right);
    phaseList.appendChild(li);
  }
  phasesSec.appendChild(phaseList);
  modal.body.appendChild(phasesSec);

  if (plan.report_path) {
    const rp = el("section");
    rp.appendChild(el("h3", { text: "Report" }));
    rp.appendChild(el("p", { cls: "mono", text: plan.report_path }));
    modal.body.appendChild(rp);
  }

  if (plan.report && plan.report.phases) {
    const repSec = el("section");
    repSec.appendChild(el("h3", { text: "Report Phases" }));
    const repList = el("ul", { cls: "work-items" });
    for (const rp of plan.report.phases) {
      const li = el("li");
      const cb = el("input", { attrs: { type: "checkbox", disabled: "disabled" } });
      if ((rp.status || "").toLowerCase() === "complete" || (rp.status || "").toLowerCase() === "done") {
        cb.checked = true;
      }
      const label = el("span", { text: (rp.phase_token || "") + " " + (rp.phase_name || "") });
      li.appendChild(cb);
      li.appendChild(label);
      repList.appendChild(li);
    }
    repSec.appendChild(repList);
    modal.body.appendChild(repSec);
  }
}

async function openIssueModal(num) {
  openModalShell("Issue #" + num);
  let data;
  try {
    const res = await fetch("/api/issue/" + encodeURIComponent(num), { cache: "no-store" });
    if (!res.ok) {
      renderModalError("Failed to load issue (" + res.status + ")");
      return;
    }
    data = await res.json();
  } catch (err) {
    renderModalError("Network error: " + err);
    return;
  }
  renderIssueModal(data);
}

function renderIssueModal(issue) {
  modal.title.textContent = "#" + (issue.number || "") + " " + (issue.title || "");
  clear(modal.body);
  if (issue.state) {
    modal.body.appendChild(el("p", { cls: "muted", text: "state: " + issue.state }));
  }
  if ((issue.labels || []).length) {
    const labels = el("div");
    for (const lab of issue.labels) {
      const name = (lab && lab.name) || lab;
      if (name) labels.appendChild(el("span", { cls: "label-chip", text: name }));
    }
    modal.body.appendChild(labels);
  }
  const bodyText = issue.body || "(no body)";
  const pre = el("pre");
  pre.textContent = bodyText;
  modal.body.appendChild(pre);
}

// --------------------------------------------------------- click dispatch

async function handleAction(action, target) {
  const slug = target.getAttribute("data-slug");
  const numStr = target.getAttribute("data-number");
  const num = numStr ? parseInt(numStr, 10) : NaN;

  if (action === "plan-up") return movePlan(slug, "up");
  if (action === "plan-down") return movePlan(slug, "down");
  if (action === "plan-left") return movePlan(slug, "left");
  if (action === "plan-right") return movePlan(slug, "right");
  if (action === "plan-remove") return removePlan(slug);
  if (action === "toggle-mode") return togglePlanMode(slug);

  if (action === "issue-up") return moveIssue(num, "up");
  if (action === "issue-down") return moveIssue(num, "down");
  if (action === "issue-left") return moveIssue(num, "left");
  if (action === "issue-right") return moveIssue(num, "right");
  if (action === "issue-remove") return removeIssue(num);

  if (action === "run-top-n") {
    const input = $("run-n");
    let n = 3;
    if (input) {
      const v = parseInt(input.value, 10);
      if (Number.isFinite(v) && v >= 1 && v <= 99) n = v;
    }
    const cmd = "/work-on-plans " + n + " " + (lastGoodDefaultMode || "phase");
    return postTrigger(cmd);
  }
  if (action === "run-stop") {
    return postTrigger("/work-on-plans stop");
  }
  if (action === "copy-cmd") {
    const cmd = target.getAttribute("data-cmd") || "";
    if (navigator.clipboard && navigator.clipboard.writeText) {
      try {
        await navigator.clipboard.writeText(cmd);
        showToast("Copied to clipboard.", "info");
      } catch (_err) {
        showToast("Copy failed — select text manually.", "err");
      }
    } else {
      showToast("Clipboard API unavailable.", "err");
    }
    return;
  }
  if (action === "clear-stale-sprint") {
    return postWorkStateReset();
  }
}

function bindActionEvents() {
  document.body.addEventListener("click", (ev) => {
    const target = ev.target.closest && ev.target.closest("[data-action]");
    if (!target) return;
    const action = target.getAttribute("data-action");
    if (!action) return;
    ev.preventDefault();
    handleAction(action, target);
  });

  // Default-mode segmented buttons.
  const phase = $("dm-phase");
  const finish = $("dm-finish");
  if (phase) phase.addEventListener("click", () => setDefaultMode("phase"));
  if (finish) finish.addEventListener("click", () => setDefaultMode("finish"));

  // Drag events at the document level.
  document.body.addEventListener("dragstart", onDragStart);
  document.body.addEventListener("dragend", onDragEnd);
  document.body.addEventListener("dragenter", onDragEnter);
  document.body.addEventListener("dragleave", onDragLeave);
  document.body.addEventListener("dragover", onDragOver);
  document.body.addEventListener("drop", onDrop);

  // Modal open: dblclick or Enter on a non-li card (worktree/branch/issue),
  // and dblclick (NOT single click) on plan/issue li cards (so single
  // clicks on buttons inside still work).
  document.body.addEventListener("dblclick", (ev) => {
    const card = ev.target.closest && ev.target.closest(".card");
    if (!card) return;
    // Don't open modal if click was on a button or the dblclick was
    // initiated inside the card-controls area.
    if (ev.target.closest("button")) return;
    onCardActivate(card);
  });
  document.body.addEventListener("keydown", (ev) => {
    if (ev.key !== "Enter") return;
    const card = ev.target.closest && ev.target.closest(".card");
    if (!card) return;
    if (card !== document.activeElement) return;
    ev.preventDefault();
    onCardActivate(card);
  });
}

function onCardActivate(card) {
  const kind = card.getAttribute("data-kind");
  if (kind === "plan") {
    openPlanModal(card.getAttribute("data-slug"));
  } else if (kind === "issue") {
    openIssueModal(card.getAttribute("data-number"));
  }
  // worktree / branch cards remain display-only.
}

// ------------------------------------------------------- visibility / boot

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    schedulePoll(0);
    scheduleWorkPoll(0);
  }
});

function boot() {
  modalInit();
  bindActionEvents();
  schedulePoll(0);
  scheduleWorkPoll(0);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot);
} else {
  boot();
}
