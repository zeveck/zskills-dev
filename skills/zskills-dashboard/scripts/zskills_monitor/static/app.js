// Z Skills Dashboard — interactive dashboard renderer (Phase 7).
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

// Full tuples used for rendering (active row + below-panel band),
// deepCloneQueues allocation, fingerprintPlans/Issues membership, and
// findPlan/findIssue / movePlan / moveIssue navigation. Includes the
// Phase-3-added `backlog` (writable) and `completed` (read-only) columns.
//
// Server contract: `completed` is read-only on /api/queue — collect.py
// derives it per-snapshot from plan frontmatter `completed:` (plans) and
// GH issue state (issues). postQueue() MUST strip `completed` before
// sending so the server's validator does not 400 on an otherwise-valid
// drag commit. See server.py:459-467 / 494-502 for the explicit reject.
const PLAN_COLUMNS = ["drafted", "reviewed", "ready", "backlog", "completed"];
const ISSUE_COLUMNS = ["triage", "ready", "backlog", "completed"];
// Sub-tuples used by renderPlans/renderIssues to draw the active
// horizontal column row (above the below-panel-band). Keeps the active
// row's grid at 3 / 2 columns regardless of how many "after the active
// flow" columns join PLAN_COLUMNS / ISSUE_COLUMNS (D3 — band is a
// standalone sibling layout, NOT a composition with .columns-2/.columns-3).
const ACTIVE_PLAN_COLUMNS = ["drafted", "reviewed", "ready"];
const ACTIVE_ISSUE_COLUMNS = ["triage", "ready"];
// Sub-tuple used by renderBelowPanelBand to draw the Backlog | Completed
// sub-columns. Backlog is always a drop-target; Completed is read-only
// (no draggable cards, no claim chip, no move-all chevron — Phase 4
// suppresses chevron + chip per-card via the column-membership check).
const BELOW_BAND_COLUMNS = ["backlog", "completed"];
// Threshold above which the column-header move-all chevron prompts the
// user via confirm() before iterating. <= this count moves silently.
const MOVE_ALL_CONFIRM_THRESHOLD = 10;
const PLAN_COLUMN_LABELS = {
  drafted: "Drafted",
  reviewed: "Reviewed",
  ready: "Ready",
  backlog: "Backlog",
  completed: "Completed",
};
const ISSUE_COLUMN_LABELS = {
  triage: "Triage",
  ready: "Ready",
  backlog: "Backlog",
  completed: "Completed",
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

// titleNode(text, href) — returns a span containing either plain text
// (when href is empty) or an <a> with target=_blank. Anchors carry
// draggable=false so they don't fight the card's HTML5 drag handler;
// click+drag from anywhere ELSE on the card still works.
function titleNode(text, href) {
  if (href) {
    return el("a", {
      cls: "card-title-link",
      text: text,
      attrs: {
        href: href,
        target: "_blank",
        rel: "noopener noreferrer",
        draggable: "false",
      },
    });
  }
  return el("span", { cls: "card-title", text: text });
}

function planUrl(plan) {
  if (!repoUrl || !plan || !plan.file) return "";
  return repoUrl + "/blob/main/" + plan.file;
}

function issueUrl(issueNum) {
  if (!repoUrl || !issueNum) return "";
  return repoUrl + "/issues/" + issueNum;
}

function branchUrl(branchName) {
  if (!repoUrl || !branchName) return "";
  return repoUrl + "/tree/" + branchName;
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
// Repo URL ("https://github.com/<owner>/<repo>") for entry-link
// construction. Populated from /api/state.repo_url; empty when origin
// is missing, unparseable, or running in fixture mode.
let repoUrl = "";
const lastFingerprint = {
  errors: null,
  plans: null,
  branches: null,
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
// updated_at (ISO string) returned by the most recent successful POST
// /api/queue. Used by applySnapshot to discard stale GET snapshots that
// were produced BEFORE our last commit hit the server — closes the
// in-flight-GET race that survived the suppressNextStatePollUntil
// window (which only skips the NEXT scheduled poll, not a poll already
// awaiting fetchState()).
let lastCommittedAt = null;
// Incremented while a /api/queue POST is in flight; applySnapshot drops
// snapshots that arrive during this window, since their `queues` block
// may be older than the in-flight write.
let pendingPosts = 0;

// last-known-good queues — used to revert local DOM on POST failure.
let lastGoodQueues = null;
let lastGoodDefaultMode = "phase";

// Phase 5d: debounce setConnected(false) to avoid banner flap on a
// single transient fetchState failure. Require DISCONNECT_FAILURE_THRESHOLD
// consecutive failures before showing the banner; any success resets.
const DISCONNECT_FAILURE_THRESHOLD = 2;
let connectionFailureCount = 0;

function setConnected(ok) {
  const banner = $("conn-banner");
  if (ok) {
    connectionFailureCount = 0;
    banner.hidden = true;
    return;
  }
  connectionFailureCount += 1;
  if (connectionFailureCount >= DISCONNECT_FAILURE_THRESHOLD) {
    banner.hidden = false;
  }
}

// Test hook: reset disconnect-debounce state. Used by
// tests/test_zskills_dashboard_disconnect_debounce.sh only.
function _resetConnectionDebounceForTests() {
  connectionFailureCount = 0;
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
  // In-flight-POST guard: while a /api/queue POST is awaiting its
  // response, any GET snapshot already composed by the server has a
  // `queues` block older than what we're about to commit. Drop it
  // outright; postQueue's lastCommittedAt update will gate subsequent
  // late-arriving snapshots once the POST settles.
  if (pendingPosts > 0) return;
  // Stale-snapshot guard: if our most recent committed POST has an
  // updated_at newer than this snapshot's state_updated_at (the state
  // file's authoritative timestamp, propagated through collect_snapshot),
  // the server hadn't yet processed our write when this GET was
  // generated. Applying it would clobber the user's just-applied reorder
  // with the pre-commit state ("snap-back"). Comparing against
  // state_updated_at — not snap.updated_at (snapshot composition time) —
  // closes the TOCTOU window where composition time outraces the
  // state-file write. String comparison on ISO-8601 with UTC offset is
  // lexicographic-monotonic; sufficient here.
  if (lastCommittedAt && snap && snap.state_updated_at && snap.state_updated_at < lastCommittedAt) {
    return;
  }
  // Capture repo_url for entry-link construction in render*().
  if (snap && typeof snap.repo_url === "string") {
    repoUrl = snap.repo_url;
  }
  const updated = $("updated-at");
  if (updated) updated.textContent = "Updated " + relativeTime(snap.updated_at);

  // Errors banner uses JSON-stringified array as fingerprint (DA-10).
  const errFp = JSON.stringify(snap.errors || []);
  if (errFp !== lastFingerprint.errors) {
    lastFingerprint.errors = errFp;
    renderErrors(snap.errors || []);
  }

  // Capture last-known-good queues from snapshot.queues (server's view).
  // `issues_fetch_ok` (issue #336): server signals whether the most recent
  // `gh issue list` succeeded. When false, deepCloneQueues skips its
  // prune-against-live-issues pass so a transient cold-start fetch failure
  // doesn't wipe the user's persisted ordering on the next POST. Missing
  // key (older snapshot shape) is treated as true to preserve current
  // steady-state behavior.
  const queues = snap.queues || { plans: {}, issues: {}, default_mode: "phase" };
  const issuesFetchOk = snap.issues_fetch_ok !== false;
  lastGoodQueues = deepCloneQueues(
    queues, snap.plans || [], snap.issues || [], issuesFetchOk,
  );
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

  // Use lastGoodQueues (deepCloneQueues output, includes inferred entries
  // for new GH issues not yet in monitor-state.json's queue arrays), NOT
  // raw snap.queues. Post-#353 renderIssues honors its queues arg and
  // only renders cards present in queues.issues[c] — a new issue that
  // gh returned but monitor-state.json hasn't seen yet would otherwise
  // never appear. Mirror commitQueueChange's pattern (lines 1182-1202).
  const issuesFp = fingerprintIssues(snap.issues || [], lastGoodQueues);
  if (issuesFp !== lastFingerprint.issues) {
    lastFingerprint.issues = issuesFp;
    renderIssues(snap.issues || [], lastGoodQueues);
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
//
// `issuesFetchOk` (issue #336): when false, the server's `issues` array
// is NOT a reliable picture of live GitHub state — the most recent
// `gh issue list` failed. In that case the prune-against-live-issues
// pass below would drop EVERY queued number on a cold-start failure
// (empty `issues` + populated state-file queues), and a subsequent
// drag-POST would persist the wiped queues. Skip the prune; preserve
// the state-file's queues verbatim until a successful fetch lands.
// Defaults to true so older snapshots (pre-#336 server) still prune.
function deepCloneQueues(queues, plans, issues, issuesFetchOk) {
  if (issuesFetchOk === undefined) issuesFetchOk = true;
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
  // Plans with no column (queue.column === null) are intentionally hidden
  // by _infer_default_column — historical completes, out-of-window, or
  // unbackfilled. Do NOT default these to "drafted" (Bug B from PR #650):
  // that override inflates Drafted with plans the inference said to hide.
  for (const p of plans) {
    if (seenSlugs.has(p.slug)) continue;
    const col = p.queue && p.queue.column;
    if (!col || PLAN_COLUMNS.indexOf(col) < 0) continue;
    seenSlugs.add(p.slug);
    out.plans[col].push({ slug: p.slug });
  }

  // GitHub owns issue existence; this file only owns ordering. Drop any
  // queue entry whose number isn't in the live `issues` array so closed
  // issues self-prune from monitor-state.json on the next POST.
  // Issue #336: only enforce this when `issuesFetchOk` — otherwise the
  // "live" array is unreliable (gh fetch failed) and pruning would wipe
  // the user's ordering on the next drag-POST.
  const liveIssueNumbers = new Set();
  for (const it of issues) {
    if (typeof it.number === "number") liveIssueNumbers.add(it.number);
  }
  const seenNums = new Set();
  for (const c of ISSUE_COLUMNS) {
    const arr = (queues.issues && queues.issues[c]) || [];
    for (const n of arr) {
      const num = parseInt(n, 10);
      if (!Number.isFinite(num) || seenNums.has(num)) continue;
      if (issuesFetchOk && !liveIssueNumbers.has(num)) continue;
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
      pos[p.slug] || [
        (p.queue && p.queue.column) || null,
        -1,
        null,
      ],
      // Claim state — symmetric to fingerprintIssues' claim tuple.
      // We track `last_heartbeat_at` (NOT `started_at`) so the chip
      // re-renders when the pipeline emits a phase heartbeat —
      // `ageStr` in the chip text is derived from heartbeat freshness,
      // so a started_at-only fingerprint would let the chip's age go
      // stale between phases. The 2-tuple is enough — pipeline_id
      // changes when a new pipeline claims; last_heartbeat_at changes
      // every phase refresh; both null when no claim.
      p.claim ? [p.claim.pipeline_id || null, p.claim.last_heartbeat_at || null] : null,
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
  // W3.7b — Truncation flag participates in the fingerprint so the
  // banner appears/disappears on the next poll where the flag toggles.
  // Without this, the banner can become stale if the only change
  // between snapshots is the flag itself. Use `typeof` so the harness in
  // tests/test-fix-issues-claim-render-dom.sh (which extracts this
  // function standalone without the module-level `lastSnapshot`
  // declaration) doesn't ReferenceError.
  const _ls = (typeof lastSnapshot !== "undefined") ? lastSnapshot : null;
  const flags = (_ls && _ls.flags) || {};
  const trunc = [
    !!flags.closed_issues_truncated,
    Number.isFinite(flags.closed_issues_limit) ? flags.closed_issues_limit : null,
  ];
  return JSON.stringify({
    trunc: trunc,
    rows: issues.map(i => [
      i.number, i.title, (i.labels || []).slice().sort(), i.created_at,
      pos[i.number] || [(i.queue && i.queue.column) || "triage", -1],
      // Claim state — DA5: without this, the fingerprint is byte-identical
      // between "no claim" and "claim present" snapshots, so applySnapshot
      // skips renderIssues and the chip never appears/disappears between
      // polls. The 2-tuple is enough — pipeline_id changes when a new
      // pipeline claims, started_at changes per-claim, and both are null
      // when no claim is held.
      i.claim ? [i.claim.pipeline_id || null, i.claim.started_at || null] : null,
    ]),
  });
}

function fingerprintActivity(act) {
  return JSON.stringify(act.slice(0, 20).map(a => [
    a.timestamp, a.pipeline, a.kind, a.id, a.skill, a.status, a.parent,
    a.subject, a.pr,
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
  // Phase 4 / D5 / D7 — Completed cards are READ-ONLY. Omit draggable
  // attribute, omit per-card action controls, omit the move-all chevron
  // (handled in renderPlans), omit the plan-title click-through link
  // (DA10: plain title text for completed plans). Issues retain the
  // GH click-through anchor (handled in buildIssueCard).
  const isCompleted = col === "completed";
  const cardAttrs = {
    role: "listitem",
    tabindex: "0",
    "data-kind": "plan",
    "data-slug": slug,
    "data-column": col,
    "aria-label": "Plan " + (plan ? (plan.title || slug) : slug),
  };
  if (!isCompleted) cardAttrs.draggable = "true";
  const card = el("li", { cls: "card", attrs: cardAttrs });
  const head = el("div", { cls: "card-row" });
  if (isCompleted) {
    // DA10 — plain title text (no anchor) for completed plans.
    head.appendChild(el("span", {
      cls: "card-title",
      text: (plan && plan.title) || slug,
    }));
  } else {
    head.appendChild(titleNode((plan && plan.title) || slug, planUrl(plan)));
  }
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

  // Claim chip (run-plan claim — plans/plans-claim-chip-parity.md Phase 3).
  // Mirrors buildIssueCard's chip with three plan-context differences:
  //   1. Chip text adds a phase fragment: "phase N/M" parsed from
  //      claim.current_phase ("Phase 3" → N=3); falls back to "phase ?/M"
  //      for unparseable section-name headers (e.g. "Parse plan").
  //   2. Age string is derived from last_heartbeat_at (not started_at)
  //      so the chip reflects heartbeat freshness — matches the
  //      fingerprint discipline above.
  //   3. data-kind="plan" is already encoded; the aria-disabled +
  //      removeAttribute("draggable") block is identical to the issue
  //      side and is honored by moveAllInColumn (kind-generic) and the
  //      plan-up/down/left/right/plan-remove guard in handleAction.
  if (plan && plan.claim) {
    const c = plan.claim;
    const hb = c.last_heartbeat_at || c.started_at || null;
    const rt = hb ? relativeTime(hb) : "";
    const ageStr = rt || "?";
    const pidShort = c.pipeline_short || "?";
    // Parse "Phase N" from current_phase. Section-name headers like
    // "Parse plan" or "Post-landing tracking" yield NaN → fallback "?".
    let curN = "?";
    const cp = c.current_phase;
    if (typeof cp === "string" && cp) {
      const m = cp.match(/Phase\s+(\d+)/i);
      if (m) curN = m[1];
    }
    const totalPhases = (plan.phase_count != null) ? plan.phase_count : "?";
    const phaseStr = "phase " + curN + "/" + totalPhases;
    const tip = c.pipeline_id
      ? "claim pipeline=" + c.pipeline_id +
        " started=" + (c.started_at || "?") +
        " heartbeat=" + (c.last_heartbeat_at || "?") +
        " current_phase=" + (c.current_phase || "?")
      : "claim metadata pending";
    const row = el("div", { cls: "card-sub" });
    row.appendChild(el("span", {
      cls: "claim-chip claim-chip--in-flight",
      attrs: { title: tip },
      text: "in-flight · " + pidShort + " · " + phaseStr + " · " + ageStr,
    }));
    card.appendChild(row);
    card.setAttribute("aria-disabled", "true");
    card.removeAttribute("draggable");
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

  // Card controls: ↑ ↓ ← → and remove. Omitted for completed plans
  // (Phase 4 / D5 — Completed is read-only; no per-card action buttons).
  if (!isCompleted) {
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
  }

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

// Column-header chevron button: triggers "move all non-claimed cards in
// this column to the adjacent column" (kind ∈ {plan, issue}; column is the
// source column slug; direction is "left" or "right"). Per-card iteration
// runs in moveAllInColumn(); claimed cards are skipped (with shake) — both
// at snapshot time AND on re-query inside the per-card loop, to close the
// race window where a poll-driven claim lands between the click and the
// per-card dispatch.
function makeColumnMoveAllBtn(action, kind, column, label, ariaLabel) {
  return el("button", {
    cls: "move-all-btn",
    attrs: {
      type: "button",
      tabindex: "0",
      "data-action": action,
      "data-kind": kind,
      "data-column": column,
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
  for (const c of ACTIVE_PLAN_COLUMNS) {
    const colDiv = el("div", { cls: "column" });
    const headId = "plans-col-" + c;
    const head = el("div", { cls: "column-head", attrs: { id: headId } });
    head.appendChild(el("span", { text: PLAN_COLUMN_LABELS[c] }));
    const arr = (lastGoodQueues && lastGoodQueues.plans[c]) || [];
    head.appendChild(el("span", { cls: "muted", text: String(arr.length) }));
    // Column-header chevron buttons (move-all). Adjacent-only; the
    // first column gets only », the last only «, and Reviewed both.
    const moveAllGroup = el("span", {
      cls: "move-all-group",
      attrs: { role: "group", "aria-label": "Move all in " + PLAN_COLUMN_LABELS[c] },
    });
    const ci = PLAN_COLUMNS.indexOf(c);
    if (ci > 0) {
      const prevLabel = PLAN_COLUMN_LABELS[PLAN_COLUMNS[ci - 1]];
      moveAllGroup.appendChild(makeColumnMoveAllBtn(
        "plan-move-all-left",
        "plan",
        c,
        "«",
        "Move all unclaimed " + PLAN_COLUMN_LABELS[c] + " plans to " + prevLabel,
      ));
    }
    if (ci < PLAN_COLUMNS.length - 1) {
      const nextLabel = PLAN_COLUMN_LABELS[PLAN_COLUMNS[ci + 1]];
      moveAllGroup.appendChild(makeColumnMoveAllBtn(
        "plan-move-all-right",
        "plan",
        c,
        "»",
        "Move all unclaimed " + PLAN_COLUMN_LABELS[c] + " plans to " + nextLabel,
      ));
    }
    head.appendChild(moveAllGroup);
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

  // Below-panel band — Backlog | Completed sub-columns (W3.4 / W3.7).
  // Backlog is always a drop-target; Completed is read-only. Whole band
  // collapses (hidden=true) only when BOTH sub-columns are empty.
  const band = renderBelowPanelBand({
    kind: "plan",
    queues: lastGoodQueues,
    slugToPlan: slugToPlan,
    defaultMode: defaultMode,
  });
  body.appendChild(band);
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

function worktreesByBranch(worktrees) {
  const m = new Map();
  for (const w of worktrees || []) {
    if (w && w.branch) m.set(w.branch, w);
  }
  return m;
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
  const byBranch = worktreesByBranch(worktrees);
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
    const url = branchUrl(b.name);
    if (url) {
      head.appendChild(el("a", {
        cls: "card-title-link mono",
        text: b.name,
        attrs: {
          href: url,
          target: "_blank",
          rel: "noopener noreferrer",
          draggable: "false",
        },
      }));
    } else {
      head.appendChild(el("span", { cls: "card-title mono", text: b.name }));
    }
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
    const w = byBranch.get(b.name);
    if (w) {
      const status = w.landed ? w.landed.status : "not-landed";
      const wtRow = el("div", { cls: "card-row card-worktree-row" });
      wtRow.appendChild(el("span", {
        cls: "pill " + landedPillClass(status),
        text: status,
      }));
      if (w.path) {
        wtRow.appendChild(el("span", { cls: "mono card-sub", text: basename(w.path) }));
      }
      if (typeof w.age_seconds === "number") {
        wtRow.appendChild(el("span", {
          cls: "card-sub",
          text: ageSecondsToText(w.age_seconds),
        }));
      }
      card.appendChild(wtRow);
    }
    body.appendChild(card);
  }
}

// ---------------------------------------------------------------- issues

function buildIssueCard(issue, num, col) {
  // Phase 4 / D5 / D7 — Completed cards are READ-ONLY. Omit draggable
  // attribute, omit the claim-chip + aria-disabled wiring (a completed
  // item is released by definition), omit per-card action controls.
  // The GH click-through anchor REMAINS (issueUrl honored below).
  const isCompleted = col === "completed";
  const cardAttrs = {
    role: "listitem",
    tabindex: "0",
    "data-kind": "issue",
    "data-number": String(num),
    "data-column": col,
    "aria-label": "Issue #" + num,
  };
  if (!isCompleted) cardAttrs.draggable = "true";
  const card = el("li", { cls: "card", attrs: cardAttrs });
  const head = el("div", { cls: "card-row" });
  head.appendChild(titleNode(
    issue ? ("#" + num + " " + (issue.title || "")) : ("#" + num),
    issueUrl(num),
  ));
  if (issue && issue.created_at) {
    head.appendChild(el("span", { cls: "card-sub", text: relativeTime(issue.created_at) }));
  }
  card.appendChild(head);
  // Skip-reason chip (issue #445) — only renders for Ready-column issues
  // whose tracker blurb resolves to a *genuine* skip-class (needs-decision,
  // plan-scale, bug-unclear-cause). `unresearched` is excluded: it signals
  // "tracker has no blurb yet for this issue" rather than a true skip —
  // /fix-issues N dashboard auto-syncs (Phase 1a) and researches these on
  // next invocation, so the per-card chip carries no actionable signal
  // for a human reader. The underlying `skip_reason` data stays in
  // /api/state so a future aggregate signal (e.g. column-header
  // "N untracked" badge) can consume it. Tooltip carries the verbatim
  // Action-now / Verdict source line. Non-interactive — card remains
  // drag-and-droppable.
  if (issue && issue.skip_reason && issue.skip_reason.code && issue.skip_reason.code !== "unresearched") {
    const sr = issue.skip_reason;
    const code = String(sr.code || "");
    const label = String(sr.label || code || "");
    const source = String(sr.source || "");
    const row = el("div", { cls: "card-sub" });
    row.appendChild(el("span", {
      cls: "skip-chip skip-chip--" + code,
      attrs: { title: source },
      text: "skip: " + code + " — " + label,
    }));
    card.appendChild(row);
  }
  // Claim chip (fix-issues claim — plans/fix-issues-claims.md Phase 3).
  // Non-interactive, in-flight indicator. Reuses `relativeTime` (R8) and
  // coalesces empty output to `"?"` (R2.7) so a parsable-but-unhelpful
  // started_at never produces a trailing-dot-space-empty chip. Also
  // marks the card aria-disabled and removes draggable so drag-reorder
  // can't fight an in-flight pipeline (DA11). The keyboard
  // move/remove buttons live in the action dispatcher below — see the
  // matching aria-disabled guard there (DA2.3).
  // Phase 4 — Completed cards skip the claim chip entirely (a completed
  // item is released by definition; PR #600 / D7 invariant).
  if (issue && issue.claim && !isCompleted) {
    const c = issue.claim;
    const rt = c.started_at ? relativeTime(c.started_at) : "";
    const ageStr = rt || "?";
    const pidShort = c.pipeline_short || "?";
    const tip = c.pipeline_id
      ? "claim pipeline=" + c.pipeline_id + " started=" + c.started_at
      : "claim metadata pending";
    const row = el("div", { cls: "card-sub" });
    row.appendChild(el("span", {
      cls: "claim-chip claim-chip--in-flight",
      attrs: { title: tip },
      text: "in-flight · " + pidShort + " · " + ageStr,
    }));
    card.appendChild(row);
    card.setAttribute("aria-disabled", "true");
    card.removeAttribute("draggable");
  }
  if (issue && (issue.labels || []).length) {
    const labels = el("div", { cls: "card-sub" });
    for (const lab of issue.labels) {
      labels.appendChild(el("span", { cls: "label-chip", text: lab }));
    }
    card.appendChild(labels);
  }
  // Phase 4 / D5 — Completed cards skip per-card action controls.
  if (!isCompleted) {
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
  }
  return card;
}

function renderIssues(issues, queues) {
  const body = $("issues-body");
  const empty = $("issues-empty");
  clear(body);
  if (!issues.length) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;

  const numToIssue = {};
  for (const it of issues) numToIssue[it.number] = it;

  // Mirror renderPlans: column membership and order come from the
  // `queues` argument (typically lastGoodQueues.issues), NOT from the
  // per-issue server annotation. This lets commitQueueChange's
  // optimistic lastGoodQueues update render the dragged card in its
  // new column immediately, before the next poll arrives.
  const cols = el("div", { cls: "columns columns-2" });
  for (const c of ACTIVE_ISSUE_COLUMNS) {
    const colDiv = el("div", { cls: "column" });
    const headId = "issues-col-" + c;
    const head = el("div", { cls: "column-head", attrs: { id: headId } });
    head.appendChild(el("span", { text: ISSUE_COLUMN_LABELS[c] }));
    const arr = (queues && queues.issues && queues.issues[c]) || [];
    head.appendChild(el("span", { cls: "muted", text: String(arr.length) }));
    // Column-header chevron buttons (move-all). Triage gets only »,
    // Ready gets only «.
    const moveAllGroup = el("span", {
      cls: "move-all-group",
      attrs: { role: "group", "aria-label": "Move all in " + ISSUE_COLUMN_LABELS[c] },
    });
    const ci = ISSUE_COLUMNS.indexOf(c);
    if (ci > 0) {
      const prevLabel = ISSUE_COLUMN_LABELS[ISSUE_COLUMNS[ci - 1]];
      moveAllGroup.appendChild(makeColumnMoveAllBtn(
        "issue-move-all-left",
        "issue",
        c,
        "«",
        "Move all unclaimed " + ISSUE_COLUMN_LABELS[c] + " issues to " + prevLabel,
      ));
    }
    if (ci < ISSUE_COLUMNS.length - 1) {
      const nextLabel = ISSUE_COLUMN_LABELS[ISSUE_COLUMNS[ci + 1]];
      moveAllGroup.appendChild(makeColumnMoveAllBtn(
        "issue-move-all-right",
        "issue",
        c,
        "»",
        "Move all unclaimed " + ISSUE_COLUMN_LABELS[c] + " issues to " + nextLabel,
      ));
    }
    head.appendChild(moveAllGroup);
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
      const issue = numToIssue[num];
      if (!issue) continue;
      ul.appendChild(buildIssueCard(issue, num, c));
    }
    colDiv.appendChild(ul);
    cols.appendChild(colDiv);
  }
  body.appendChild(cols);

  // W3.7b — Truncation banner. Server signals via snap.flags.closed_issues_truncated
  // when the bounded closed-issues fetch saturated the configured limit;
  // captured at the module level by applySnapshot. Render BETWEEN the
  // active column row and the below-panel band (D6: banner sits above
  // the band per Phase 3 spec).
  renderTruncationBanner(body);

  // Below-panel band — Backlog | Completed (W3.4 / W3.7).
  const band = renderBelowPanelBand({
    kind: "issue",
    queues: queues,
    numToIssue: numToIssue,
  });
  body.appendChild(band);
}

// ----------------------------------------------- below-panel band (Phase 3)

// Build a sibling block-level container with two sub-columns
// (Backlog | Completed). Returns the band element with `hidden=true`
// set when BOTH sub-columns are empty. Backlog ALWAYS renders as a
// drop-target (empty UL with placeholder text); Completed renders
// per-card buildPlanCard / buildIssueCard for read-only display.
//
// `opts.kind` is "plan" or "issue". For plans, opts.slugToPlan +
// opts.defaultMode are required. For issues, opts.numToIssue is required.
function renderBelowPanelBand(opts) {
  const kind = opts.kind;
  const queues = opts.queues;
  const labels = (kind === "plan") ? PLAN_COLUMN_LABELS : ISSUE_COLUMN_LABELS;
  const queueDict = (kind === "plan")
    ? (queues && queues.plans) || {}
    : (queues && queues.issues) || {};

  // Below-panel band ALWAYS renders (post-#650 reversal). Backlog stays a
  // visible drop-target even when empty (D5 affordance + "Drag here to
  // defer" placeholder); Completed renders even when empty so the user
  // sees a stable two-column band rather than the band appearing /
  // disappearing as state changes.
  const band = el("div", {
    cls: "below-panel-band",
    attrs: { "data-kind": kind, role: "group", "aria-label": "Backlog and Completed" },
  });

  for (const c of BELOW_BAND_COLUMNS) {
    const colDiv = el("div", { cls: "column" });
    const headId = (kind === "plan" ? "plans" : "issues") + "-col-" + c;
    const head = el("div", { cls: "column-head", attrs: { id: headId } });
    head.appendChild(el("span", { text: labels[c] }));
    const arr = queueDict[c] || [];
    head.appendChild(el("span", { cls: "muted", text: String(arr.length) }));
    // Phase 4 / W4.3 / D7 — Move-all chevron: VALID for backlog (drag-back
    // to adjacent active column), SUPPRESSED for completed (terminal /
    // read-only state). Backlog only gets « (move-all back to active);
    // the right-chevron from backlog would target completed which is
    // read-only.
    if (c === "backlog") {
      const moveAllGroup = el("span", {
        cls: "move-all-group",
        attrs: { role: "group", "aria-label": "Move all in " + labels[c] },
      });
      const cols = (kind === "plan") ? PLAN_COLUMNS : ISSUE_COLUMNS;
      const ci = cols.indexOf(c);
      if (ci > 0) {
        const prevLabel = labels[cols[ci - 1]];
        moveAllGroup.appendChild(makeColumnMoveAllBtn(
          (kind === "plan") ? "plan-move-all-left" : "issue-move-all-left",
          kind,
          c,
          "«",
          "Move all unclaimed " + labels[c] + " " + (kind === "plan" ? "plans" : "issues") + " to " + prevLabel,
        ));
      }
      head.appendChild(moveAllGroup);
    }
    colDiv.appendChild(head);

    const ul = el("ul", {
      cls: "dropzone",
      attrs: {
        role: "list",
        "data-column": c,
        "data-kind": kind,
        "aria-labelledby": headId,
      },
    });

    if (kind === "plan") {
      for (const entry of arr) {
        const slug = (typeof entry === "string") ? entry : (entry && entry.slug);
        if (!slug) continue;
        const card = buildPlanCard(
          opts.slugToPlan[slug] || null, slug, c, opts.defaultMode,
        );
        ul.appendChild(card);
      }
    } else {
      for (const num of arr) {
        const issue = opts.numToIssue[num];
        if (!issue) continue;
        ul.appendChild(buildIssueCard(issue, num, c));
      }
    }

    // Backlog placeholder when empty — keeps the drop-target visually
    // discoverable per D5 ("Drag here to defer"). Completed empty stays
    // bare (read-only column, no drop affordance).
    if (c === "backlog" && arr.length === 0) {
      ul.appendChild(el("li", {
        cls: "dropzone-placeholder muted",
        attrs: { "aria-hidden": "true" },
        text: "Drag here to defer",
      }));
    }
    colDiv.appendChild(ul);
    band.appendChild(colDiv);
  }
  return band;
}

// W3.7b — Truncation banner. Read snap.flags.closed_issues_truncated +
// closed_issues_limit from the module-level lastSnapshot. Banner classes
// `.truncation-banner` + `.muted`; appended above the Issues panel's
// active row (and thus above the below-band by extension). Non-dismissable:
// disappears automatically on the next snapshot where the flag is absent
// / false (renderIssues runs from scratch each fingerprint diff, so no
// stale banner persists).
function renderTruncationBanner(body) {
  const _ls = (typeof lastSnapshot !== "undefined") ? lastSnapshot : null;
  const flags = (_ls && _ls.flags) || {};
  if (!flags.closed_issues_truncated) return;
  const closed_issues_limit = flags.closed_issues_limit;
  const banner = el("div", {
    cls: "truncation-banner muted",
    attrs: { role: "status", "aria-live": "polite" },
    text: `Showing ${closed_issues_limit} most-recent closed issues — there are probably more. To see all, raise execution.dashboard_completed_limit (currently ${closed_issues_limit}) in .claude/zskills-config.json.`,
  });
  body.appendChild(banner);
}

// ------------------------------------------------------------- worktrees

function landedPillClass(status) {
  // Canonical `.landed` status vocabulary (tests/test-landed-status-vocabulary.sh):
  //   full, landed                                            -> green  (landed-full)
  //   partial                                                 -> orange (landed-partial)
  //   pr-ready                                                -> blue   (landed-pr-ready)
  //   pr-ci-failing, pr-failed, conflict, pr-state-unknown    -> orange (landed-pr-needs-attention)
  //   failed, direct-push-failed, direct-verify-failed        -> red    (landed-failed)
  // Issue #618 (mirror of #602 prose-side / #621 briefing.py).
  const s = (status || "").toLowerCase();
  if (s === "full" || s === "landed") return "pill-landed-full";
  if (s === "partial") return "pill-landed-partial";
  if (s === "pr-ready") return "pill-landed-pr-ready";
  if (s === "pr-ci-failing" || s === "pr-failed" || s === "conflict" || s === "pr-state-unknown") {
    return "pill-landed-pr-needs-attention";
  }
  if (s === "failed" || s === "direct-push-failed" || s === "direct-verify-failed") {
    return "pill-landed-failed";
  }
  return "pill-landed-not";
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
    if (a.kind === "commit") {
      // Git-history row: short SHA + commit subject. Subject already
      // conveys what changed; no need for pipeline/skill columns.
      row.appendChild(el("span", { cls: "a-pipe mono", text: a.id || "" }));
      const mid = el("span");
      mid.appendChild(el("span", { cls: "a-subject", text: a.subject || "" }));
      if (a.pr) {
        const prHref = repoUrl ? (repoUrl + "/pull/" + a.pr) : "";
        if (prHref) {
          mid.appendChild(el("a", {
            cls: "a-parent a-pr-link",
            text: " #" + a.pr,
            attrs: {
              href: prHref,
              target: "_blank",
              rel: "noopener noreferrer",
            },
          }));
        } else {
          mid.appendChild(el("span", { cls: "a-parent", text: " #" + a.pr }));
        }
      }
      row.appendChild(mid);
      row.appendChild(el("span", { cls: "a-time", text: relativeTime(a.timestamp) }));
    } else {
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
    }
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
  //
  // Server contract: `completed` is read-only on /api/queue (server.py
  // 459-467 / 494-502 reject any body containing it). Strip both
  // plans.completed and issues.completed before sending — Completed
  // cards are derived per-snapshot from plan frontmatter / GH issue
  // state, never from monitor-state.json's queue arrays. Sending an
  // EMPTY `completed: []` would still trip the validator's explicit
  // reject, so we remove the key entirely (Phase 3 / D5).
  const stripCompleted = (obj) => {
    const out = {};
    for (const k of Object.keys(obj || {})) {
      if (k === "completed") continue;
      out[k] = obj[k];
    }
    return out;
  };
  const payload = {
    default_mode: queues.default_mode || "phase",
    plans: stripCompleted(queues.plans),
    issues: stripCompleted(queues.issues),
  };
  let res;
  // Phase 4 / W4.5 / AC4.8 — Single-fetch invariant: this is the SOLE
  // call to POST /api/queue in app.js. The conformance grep
  // (`grep -cE 'fetch \([^)]*api/queue' app.js`) is anchored on the
  // call-syntax with the literal `api/queue` argument so that every
  // drag-induced POST flows through `postQueue`, which holds the
  // `pendingPosts++/--` race-guard at commitQueueChange. Do not
  // introduce a sibling site for this URL — extend this helper instead.
  try {
    res = await fetch("/api/queue", {
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
  // Capture updated_at from the response so applySnapshot can discard
  // any stale GET snapshot that was generated before this commit landed
  // on the server. Belt-and-suspenders with the
  // suppressNextStatePollUntil window below: that handles the NEXT
  // scheduled poll; this handles an in-flight poll whose GET was
  // awaiting fetchState() at the moment this POST returned.
  try {
    const body = await res.json();
    if (body && typeof body.state_updated_at === "string") {
      lastCommittedAt = body.state_updated_at;
    }
  } catch (_e) { /* tolerable — guard just becomes a no-op for this commit */ }
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

  pendingPosts++;
  let ok;
  try {
    ok = await postQueue(newQueues, opts);
  } finally {
    pendingPosts--;
  }
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
        plans: { drafted: [], reviewed: [], ready: [], backlog: [], completed: [] },
        issues: { triage: [], ready: [], backlog: [], completed: [] },
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
  // Capture the source column for postQueue (used elsewhere to strip
  // `completed` defensively, and for column-aware drag affordances).
  const sourceColumn = card.getAttribute("data-column");
  dragState = { kind, slug, num, sourceColumn };
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
  removeInsertIndicator();
}

function onDragOver(ev) {
  const dz = ev.target.closest && ev.target.closest("ul.dropzone");
  if (!dz) return;
  if (!dragState) return;
  // Kind must match dropzone kind.
  if (dz.getAttribute("data-kind") !== dragState.kind) return;
  ev.preventDefault();
  if (ev.dataTransfer) ev.dataTransfer.dropEffect = "move";
  // Visible insertion-point feedback: blue line at the computed index.
  // Required for intra-column reordering to feel precise.
  updateInsertIndicator(dz, ev.clientY);
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
  removeInsertIndicator();
}

function computeInsertIndex(dz, clientY) {
  const cards = Array.from(dz.querySelectorAll("li.card:not(.dragging)"));
  for (let i = 0; i < cards.length; i++) {
    const r = cards[i].getBoundingClientRect();
    if (clientY < r.top + r.height / 2) return i;
  }
  return cards.length;
}

// Insertion-point indicator: a thin --accent line rendered inside the
// dropzone at the computed insertion position. Lets the user see WHERE
// the drop will land before releasing the mouse. Inserted/moved on
// every dragover; removed on dragend / dragleave (full leave) / drop.
// pointer-events: none in the CSS prevents the indicator itself from
// firing dragenter/dragleave on the parent.
function updateInsertIndicator(dz, clientY) {
  removeInsertIndicator();
  if (!dz) return;
  const cards = Array.from(dz.querySelectorAll("li.card:not(.dragging)"));
  const idx = computeInsertIndex(dz, clientY);
  const indicator = document.createElement("div");
  indicator.className = "drop-indicator";
  if (idx >= cards.length) {
    dz.appendChild(indicator);
  } else {
    dz.insertBefore(indicator, cards[idx]);
  }
}

function removeInsertIndicator() {
  const els = document.querySelectorAll(".drop-indicator");
  for (const el of els) {
    if (el.parentNode) el.parentNode.removeChild(el);
  }
}

async function onDrop(ev) {
  const dz = ev.target.closest && ev.target.closest("ul.dropzone");
  if (!dz) return;
  if (!dragState) return;
  if (dz.getAttribute("data-kind") !== dragState.kind) return;
  ev.preventDefault();
  dz.classList.remove("drop-target");
  // Compute the index BEFORE removing the indicator (so insertion math
  // uses the same DOM state the user saw on the indicator).
  let targetCol = dz.getAttribute("data-column");
  let targetIdx = computeInsertIndex(dz, ev.clientY);
  removeInsertIndicator();
  // Phase 4 / W4.2 — Reject drops onto Completed. Completed is read-only
  // (terminal state derived from GH closedAt / plan frontmatter — D1).
  // Per D5 the column still renders as a <ul> for visual consistency,
  // but the handler hard-rejects with a no-op + warn (no POST).
  if (targetCol === "completed") {
    console.warn(
      "Drop rejected: completed column is read-only (kind=" + dragState.kind +
      ", id=" + (dragState.slug || dragState.num) + ")"
    );
    dragState = null;
    return;
  }
  // Backlog→active: land where dropped (overrides plan D5; see PR description).
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

// ---------------------------------------------------- column move-all loop

// Briefly attach a `.shake` class to the card and remove it after the
// animation. Used when a card is skipped during a move-all loop because
// it's claimed (snapshot-time OR claim landed via poll mid-loop).
function shakeCard(card) {
  if (!card) return;
  card.classList.remove("shake");
  // Force reflow so re-adding the class restarts the animation when the
  // same card is shaken in quick succession.
  void card.offsetWidth;
  card.classList.add("shake");
  setTimeout(() => {
    card.classList.remove("shake");
  }, 400);
}

// Move all NON-claimed cards in `column` (of kind `plan` or `issue`) to
// the adjacent column in `direction` ("left" or "right"). Per-card
// sequential dispatch — there is no bulk endpoint; each iteration calls
// the same movePlan / moveIssue used by the single-card chevron buttons.
//
// Claim-respect: source of truth is `aria-disabled="true"` on the card.
// We snapshot non-claimed cards at click-time, then INSIDE each iteration
// re-query the live card's aria-disabled. A claim landing via the 2s poll
// between click and iteration N still gets respected (card is skipped and
// shaken instead of moved).
async function moveAllInColumn(kind, column, direction) {
  const kindLabels = (kind === "plan") ? PLAN_COLUMN_LABELS : ISSUE_COLUMN_LABELS;
  const cols = (kind === "plan") ? PLAN_COLUMNS : ISSUE_COLUMNS;
  const ci = cols.indexOf(column);
  if (ci < 0) return;
  const adjIdx = (direction === "left") ? ci - 1 : ci + 1;
  if (adjIdx < 0 || adjIdx >= cols.length) return;
  const srcLabel = kindLabels[column];
  const dstLabel = kindLabels[cols[adjIdx]];

  // Snapshot the non-claimed cards in this column (live DOM query).
  const selector = 'ul.dropzone[data-kind="' + kind + '"][data-column="' + column + '"] > li.card';
  const allCards = Array.from(document.querySelectorAll(selector));
  const targets = [];
  for (const card of allCards) {
    if (card.getAttribute("aria-disabled") === "true") {
      // Snapshot-time claimed — shake so user sees what was skipped.
      shakeCard(card);
      continue;
    }
    const idAttr = (kind === "plan") ? "data-slug" : "data-number";
    const id = card.getAttribute(idAttr);
    if (!id) continue;
    targets.push({ id: id, card: card });
  }
  if (targets.length === 0) return;

  const noun = (kind === "plan") ? "plans" : "issues";
  if (targets.length > MOVE_ALL_CONFIRM_THRESHOLD) {
    const msg = "Move " + targets.length + " unclaimed " + srcLabel + " " + noun + " to " + dstLabel + "?";
    if (!window.confirm(msg)) return;
  }

  // Per-card sequential dispatch with in-loop re-check on aria-disabled.
  for (const t of targets) {
    // Re-query the live element each iteration — a render between the
    // last commit and now may have replaced the cached `t.card` node.
    const liveSelector = (
      'ul.dropzone[data-kind="' + kind + '"] > li.card[data-' +
      (kind === "plan" ? "slug" : "number") + '="' + t.id + '"]'
    );
    const live = document.querySelector(liveSelector);
    if (live && live.getAttribute("aria-disabled") === "true") {
      // Claim landed via poll between click and this iteration. Skip
      // + shake (matches snapshot-time skip behaviour).
      shakeCard(live);
      continue;
    }
    if (kind === "plan") {
      await movePlan(t.id, direction);
    } else {
      const num = parseInt(t.id, 10);
      if (Number.isFinite(num)) await moveIssue(num, direction);
    }
  }
}

// --------------------------------------------------------- click dispatch

async function handleAction(action, target) {
  const slug = target.getAttribute("data-slug");
  const numStr = target.getAttribute("data-number");
  const num = numStr ? parseInt(numStr, 10) : NaN;

  // Guard: claimed plans are in-flight on another /run-plan pipeline.
  // Block move and remove actions to prevent ghost-claim footgun
  // (symmetric to the issue-side guard below — DA2.3 / DA11 of
  // plans/plans-claim-chip-parity.md). Drag-disable alone is cosmetic;
  // the keyboard move/remove buttons bypass the drag handler entirely.
  // toggle-mode is allowed — the user can still re-pick landing mode
  // on a claimed plan; only column/queue mutations are blocked.
  if (action === "plan-up" || action === "plan-down" ||
      action === "plan-left" || action === "plan-right" ||
      action === "plan-remove") {
    const claimedCard = target.closest('li.card[aria-disabled="true"][data-kind="plan"]');
    if (claimedCard) {
      showToast("Plan is in-flight; release the claim or wait for completion.", "info");
      return;
    }
  }

  if (action === "plan-up") return movePlan(slug, "up");
  if (action === "plan-down") return movePlan(slug, "down");
  if (action === "plan-left") return movePlan(slug, "left");
  if (action === "plan-right") return movePlan(slug, "right");
  if (action === "plan-remove") return removePlan(slug);
  if (action === "toggle-mode") return togglePlanMode(slug);

  // Column-header chevron: move-all in column, adjacent column only.
  if (action === "plan-move-all-left" || action === "plan-move-all-right" ||
      action === "issue-move-all-left" || action === "issue-move-all-right") {
    const col = target.getAttribute("data-column");
    const kind = target.getAttribute("data-kind");
    const dir = action.endsWith("-left") ? "left" : "right";
    if (col && kind) return moveAllInColumn(kind, col, dir);
    return;
  }

  // Guard: claimed issues are in-flight on another pipeline. Block move
  // and remove actions to prevent ghost-claim footgun (DA2.3 / DA11).
  // Drag-disable alone is cosmetic — the keyboard move/remove buttons
  // bypass the drag handler entirely.
  if (action === "issue-up" || action === "issue-down" ||
      action === "issue-left" || action === "issue-right" ||
      action === "issue-remove") {
    const claimedCard = target.closest('li.card[aria-disabled="true"][data-kind="issue"]');
    if (claimedCard) {
      showToast("Issue is in-flight; release the claim or wait for completion.", "info");
      return;
    }
  }
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

// ─── Tab navigation (mouse-first; click + hashchange only) ───
const TAB_SLUGS = ["plans", "issues", "branches"];

function readTabFromHash() {
  const h = (location.hash || "").replace(/^#/, "");
  return TAB_SLUGS.includes(h) ? h : "plans";
}

function setActiveTab(slug, { pushHash = true } = {}) {
  if (!TAB_SLUGS.includes(slug)) slug = "plans";
  for (const s of TAB_SLUGS) {
    const tab = document.getElementById("tab-" + s);
    const panel = document.getElementById(s);
    if (!tab || !panel) continue;
    const isActive = (s === slug);
    tab.setAttribute("aria-selected", isActive ? "true" : "false");
    if (isActive) {
      panel.removeAttribute("hidden");
    } else {
      panel.setAttribute("hidden", "");
    }
  }
  if (pushHash && location.hash !== "#" + slug) {
    history.replaceState(null, "", "#" + slug);
  }
}

function bindTabEvents() {
  const tablist = document.querySelector('[role="tablist"]');
  if (!tablist) return;
  // Click handler — native <button> handles Enter/Space → click automatically.
  tablist.addEventListener("click", (ev) => {
    const btn = ev.target.closest('[role="tab"]');
    if (!btn) return;
    const slug = btn.getAttribute("aria-controls");
    if (slug) setActiveTab(slug);
  });
  // hashchange (browser back/forward, or external link)
  window.addEventListener("hashchange", () => {
    setActiveTab(readTabFromHash(), { pushHash: false });
  });
}

// Inline initialization — best-effort flash mitigation. Module
// scripts defer to after parse, so this often runs after first
// paint; the boot() call (which also runs setActiveTab) is the
// authoritative initializer. setActiveTab is idempotent; the
// console.warn surfaces unexpected failures rather than swallowing.
if (typeof document !== "undefined" && document.readyState !== "loading") {
  try { setActiveTab(readTabFromHash(), { pushHash: false }); }
  catch (e) { console.warn("tab-init early call failed:", e); }
}

function boot() {
  modalInit();
  bindActionEvents();
  bindTabEvents();                                       // NEW
  setActiveTab(readTabFromHash(), { pushHash: false });  // NEW
  schedulePoll(0);
  scheduleWorkPoll(0);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot);
} else {
  boot();
}
