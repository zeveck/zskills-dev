// Z Skills Dashboard — interactive dashboard renderer (Phase 7).
//
// Loaded as a single ES module from /app.js. Polls /api/state every 2s
// via setTimeout recursion (NOT setInterval), slows to a ~60s heartbeat
// while document is hidden (HIDDEN_POLL_INTERVAL_MS) rather than stopping,
// and force-loads on visibilitychange. Per-panel diff detection
// so unchanged panels are not re-rendered. All user-authored content
// rendered via textContent / appendChild — no innerHTML except for
// hardcoded chrome marked `// chrome-only`.
//
// Phase 7 adds drag-and-drop columns for Plans (Drafted/Proposed/Accepted)
// and Issues (Triage/Ready), POSTs the full queue back to /api/queue
// on every reorder, polls /api/work-state for the Run/Status widget,
// and POSTs to /api/trigger and /api/work-state/reset.

const POLL_INTERVAL_MS = 2000;
// While the tab is hidden we keep polling, just much more slowly. The
// collector maintains a ~60s server-side snapshot cache, so a 60s hidden
// poll mostly hits warm cache instead of re-shelling git/gh. This keeps the
// open tab reasonably fresh (returning is near-instant) without paying the
// 2s-cadence collection cost while nobody is watching. Tunable.
const HIDDEN_POLL_INTERVAL_MS = 60000;
// Reschedule delay for the recursive poll loops: fast when visible, slow
// heartbeat when hidden. The loop is NEVER torn down — see pollOnce /
// pollWorkOnce, which reschedule via this on every tick.
function nextPollDelay() {
  return document.hidden ? HIDDEN_POLL_INTERVAL_MS : POLL_INTERVAL_MS;
}
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
// Phase-3-added `backlog` (writable) and `completed` (mostly read-only)
// columns.
//
// Server contract: `completed` is derived per-snapshot from plan
// frontmatter `completed:` (plans) and GH issue state (issues), and is
// the source of truth for routing. postQueue() strips `completed` by
// default to keep the writable→derived flow clean.
//
// Issue #905 — drag-to-Completed safety hatch (client-side half of
// #853): a plan whose frontmatter status is `complete` or `landed` MAY
// be dragged onto Completed; postQueue passes plans.completed through
// when opts.includeCompletedPlans is set (movePlan threads this when
// targetCol === "completed"). Server-side _validate_completed_plan_slugs
// re-checks each slug's status before persisting. Issues retain the
// unconditional strip (no analogous hatch — closed-ness is owned by GH).
const PLAN_COLUMNS = ["drafted", "reviewed", "ready", "backlog", "discarded", "completed"];
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
const BELOW_BAND_COLUMNS = ["backlog", "discarded", "completed"];
// Threshold above which the column-header move-all chevron prompts the
// user via confirm() before iterating. <= this count moves silently.
const MOVE_ALL_CONFIRM_THRESHOLD = 10;
const PLAN_COLUMN_LABELS = {
  drafted: "Drafted",
  reviewed: "Proposed",
  ready: "Accepted",
  backlog: "Backlog",
  discarded: "Discarded",
  completed: "Completed",
};
const ISSUE_COLUMN_LABELS = {
  triage: "Triage",
  ready: "Ready",
  backlog: "Backlog",
  completed: "Completed",
};

// Per-user, per-column collapse state. localStorage-backed so the choice
// survives reloads. Key shape: zskills:dashboard:collapsed:<kind>:<col>.
// Value "1" means collapsed; absence means expanded (default). The toggle
// button in column-head dispatches via data-action="column-collapse-toggle"
// (handleAction case below).
const COLLAPSE_KEY_PREFIX = "zskills:dashboard:collapsed:";

// Issue #676 — Per-user completed-window preference. localStorage-backed so
// the choice survives reloads. Key shape:
// zskills:dashboard:completed-window:<kind> where kind is "plan" or "issue".
// Value is a string number of days ("7", "14", "30", "90") or "all".
// Default comes from snapshot.config.dashboard_completed_days (server-side
// config, typically 14). The dropdown is injected into the Completed column
// header by renderBelowPanelBand.
const COMPLETED_WINDOW_KEY_PREFIX = "zskills:dashboard:completed-window:";
let configCompletedDays = 14; // overwritten by applySnapshot from snap.config

function getCompletedWindow(kind) {
  try {
    const raw = localStorage.getItem(COMPLETED_WINDOW_KEY_PREFIX + kind);
    if (raw === "all") return "all";
    const n = parseInt(raw, 10);
    if (Number.isFinite(n) && n > 0) return n;
  } catch (_e) { /* localStorage disabled */ }
  return configCompletedDays;
}

function setCompletedWindow(kind, value) {
  try {
    localStorage.setItem(COMPLETED_WINDOW_KEY_PREFIX + kind, String(value));
  } catch (_e) { /* localStorage disabled */ }
}

// Issue #677 — columns that start COLLAPSED when no per-user localStorage
// preference is recorded. Discarded plans are dismissed-but-not-deleted;
// the column exists for discoverability + restore, not active workflow,
// so hiding it by default keeps the board uncluttered until the user
// explicitly expands it. Per-user expand state still persists via
// localStorage (setCollapsed removes the key on expand, so the default
// applies only on first paint or after localStorage.clear()).
const COLLAPSED_BY_DEFAULT = new Set(["discarded", "branch-landed", "branch-local", "branch-remote-only"]);

function isCollapsed(kind, col) {
  try {
    const raw = localStorage.getItem(COLLAPSE_KEY_PREFIX + kind + ":" + col);
    if (raw === "1") return true;
    if (raw === "0") return false;
    // No preference recorded — fall back to the default for this column.
    // setCollapsed writes "0" on explicit expand of a collapsed-by-default
    // column so the user's choice survives reloads.
    return COLLAPSED_BY_DEFAULT.has(col);
  } catch (_e) { return COLLAPSED_BY_DEFAULT.has(col); }
}

function setCollapsed(kind, col, collapsed) {
  try {
    if (collapsed) {
      localStorage.setItem(COLLAPSE_KEY_PREFIX + kind + ":" + col, "1");
    } else if (COLLAPSED_BY_DEFAULT.has(col)) {
      // Explicit-expand of a collapsed-by-default column: write "0" so the
      // user's choice survives reloads (a bare removeItem would fall back
      // to the default = collapsed on next paint).
      localStorage.setItem(COLLAPSE_KEY_PREFIX + kind + ":" + col, "0");
    } else {
      localStorage.removeItem(COLLAPSE_KEY_PREFIX + kind + ":" + col);
    }
  } catch (_e) { /* localStorage disabled — runtime-only collapse */ }
}

var CHIP_TYPE_LABELS = {
  "in-flight": "in-flight",
  "plan-scale": "plan-scale",
  "needs-decision": "needs-decision",
  "deferred": "deferred",
  "bug-unclear-cause": "unclear-cause",
};

function cardChipType(card) {
  var claim = card.querySelector(".claim-chip--in-flight");
  if (claim) return "in-flight";
  var skip = card.querySelector("[class*='skip-chip--']");
  if (skip) {
    var m = skip.className.match(/skip-chip--(\S+)/);
    if (m) return m[1];
  }
  return null;
}

function applyCollapseStateToColumn(colDiv, kind, col, labelText) {
  const collapsed = isCollapsed(kind, col);
  if (collapsed) {
    colDiv.classList.add("collapsed");
  } else {
    colDiv.classList.remove("collapsed");
  }
  const toggle = colDiv.querySelector(".column-collapse-toggle");
  if (toggle) {
    toggle.setAttribute("aria-expanded", collapsed ? "false" : "true");
    const lbl = labelText || toggle.dataset.column || "";
    toggle.setAttribute("aria-label", (collapsed ? "Expand " : "Collapse ") + lbl);
    toggle.innerHTML = collapsed ? SVG_ICONS.plus : SVG_ICONS.minus; // chrome-only
  }
  // Collapsed-column preview: mini-card rows showing issue/plan IDs + titles
  // so the user gets real content visibility without expanding.
  const existingSummary = colDiv.querySelector(".collapsed-summary");
  if (!collapsed) {
    if (existingSummary) existingSummary.parentNode.removeChild(existingSummary);
    return;
  }
  const dz = colDiv.querySelector(".dropzone");
  const cards = dz ? dz.querySelectorAll("li.card") : [];
  const count = cards.length;
  const labels = (kind === "plan") ? PLAN_COLUMN_LABELS : ISSUE_COLUMN_LABELS;
  const colLabel = labels[col] || col;
  const summary = el("div", {
    cls: "collapsed-summary",
    attrs: {
      "data-action": "column-collapse-toggle",
      "data-kind": kind,
      "data-column": col,
      role: "button",
      "aria-label": "Expand " + colLabel + " (" + count + " items)",
    },
  });
  var maxPreview = 5;
  var chipTally = {};
  for (var i = 0; i < cards.length; i++) {
    var card = cards[i];
    var chipType = cardChipType(card);
    if (chipType) chipTally[chipType] = (chipTally[chipType] || 0) + 1;
    if (i >= maxPreview) continue;
    var titleEl = card.querySelector(".card-title, .card-title-link");
    if (!titleEl) continue;
    var fullText = titleEl.textContent || "";
    var idMatch = fullText.match(/^(#\d+)\s+/);
    var row = el("div", { cls: "collapsed-summary-row" });
    if (chipType) {
      row.appendChild(el("span", { cls: "collapsed-dot collapsed-dot--" + chipType }));
    }
    if (idMatch) {
      row.appendChild(el("span", { cls: "collapsed-summary-id", text: idMatch[1] }));
      var rest = fullText.slice(idMatch[0].length);
      if (rest.length > 50) rest = rest.slice(0, 47) + "...";
      row.appendChild(el("span", { cls: "collapsed-summary-title", text: rest }));
    } else {
      var t = fullText;
      if (t.length > 55) t = t.slice(0, 52) + "...";
      row.appendChild(el("span", { cls: "collapsed-summary-title", text: t }));
    }
    summary.appendChild(row);
  }
  if (count > maxPreview) {
    summary.appendChild(el("div", {
      cls: "collapsed-summary-more",
      text: "+" + (count - maxPreview) + " more",
    }));
  }
  var tallyKeys = Object.keys(chipTally);
  if (tallyKeys.length > 0) {
    var footer = el("div", { cls: "collapsed-summary-footer" });
    for (var k = 0; k < tallyKeys.length; k++) {
      var key = tallyKeys[k];
      var badge = el("span", {
        cls: "collapsed-footer-badge collapsed-footer-badge--" + key,
        text: chipTally[key] + " " + CHIP_TYPE_LABELS[key],
      });
      footer.appendChild(badge);
    }
    summary.appendChild(footer);
  }
  if (existingSummary) existingSummary.parentNode.removeChild(existingSummary);
  var head = colDiv.querySelector(".column-head");
  if (head && head.nextSibling) {
    colDiv.insertBefore(summary, head.nextSibling);
  } else {
    colDiv.appendChild(summary);
  }
}

// Append the per-column collapse toggle to a column-head. Caller passes
// the kind ("plan" / "issue"), column key, and the human label (used for
// the initial aria-label). The button carries data-action so the shared
// delegated click handler (handleAction) flips state and re-applies.
function appendCollapseToggle(head, kind, col, labelText) {
  const toggle = el("button", {
    cls: "column-head-btn column-collapse-toggle",
    attrs: {
      type: "button",
      "data-action": "column-collapse-toggle",
      "data-kind": kind,
      "data-column": col,
      "aria-expanded": "true",
      "aria-label": "Collapse " + labelText,
      title: "Collapse / expand",
    },
    html: SVG_ICONS.minus,
  });
  head.appendChild(toggle);
  return toggle;
}

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
  if (opts.html != null) node.innerHTML = opts.html; // chrome-only
  else if (opts.text != null) node.textContent = String(opts.text);
  if (opts.attrs) {
    for (const k of Object.keys(opts.attrs)) {
      const v = opts.attrs[k];
      if (v != null) node.setAttribute(k, String(v));
    }
  }
  return node;
}

var SVG_ICONS = {
  chevronLeft: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10 3L5 8l5 5"/></svg>',
  chevronRight: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3l5 5-5 5"/></svg>',
  chevronsLeft: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3L3 8l5 5"/><path d="M13 3L8 8l5 5"/></svg>',
  chevronsRight: '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3l5 5-5 5"/><path d="M8 3l5 5-5 5"/></svg>',
  arrowUp: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 13V3"/><path d="M3 7l5-5 5 5"/></svg>',
  arrowDown: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3v10"/><path d="M3 9l5 5 5-5"/></svg>',
  arrowLeft: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M13 8H3"/><path d="M7 3L2 8l5 5"/></svg>',
  arrowRight: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8h10"/><path d="M9 3l5 5-5 5"/></svg>',
  x: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M4 4l8 8"/><path d="M12 4l-8 8"/></svg>',
  copy: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M2 11V3a1.5 1.5 0 011.5-1.5H11"/></svg>',
  minus: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M4 8h8"/></svg>',
  plus: '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M4 8h8"/><path d="M8 4v8"/></svg>',
  lock: '<svg width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="7" width="10" height="7" rx="1.5"/><path d="M5.5 7V4.5a2.5 2.5 0 015 0V7"/></svg>',
};

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

// Issue #802 — unread-dot indicator. lastViewed[tab] holds the per-tab
// fingerprint as of the last time the user *viewed* that tab. An inactive
// tab shows a dot iff its current fingerprint differs from lastViewed.
// Initialized to null; the first applySnapshot seeds it from the first
// snapshot's fingerprints (see seedTabFingerprintsIfUnseen) so the board
// does NOT open covered in dots. The fingerprints reused here are the same
// volatile-safe ones that gate per-section re-renders — they exclude
// age_seconds / heartbeat / ticking timestamps, so volatile churn cannot
// produce a false dot. `activeTab` tracks which tab is currently shown so
// the render loop can skip dotting it and so setActiveTab can mark it seen.
const lastViewed = {
  plans: null,
  issues: null,
  branches: null,
};
// Most-recent per-tab fingerprints, refreshed every poll in applySnapshot.
// setActiveTab reads these to mark the just-opened tab as seen.
const currentTabFingerprint = {
  plans: null,
  issues: null,
  branches: null,
};
let activeTab = "plans";
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
  // Reconciliation: skip a single state poll right after a successful
  // POST, so a GET in flight before the POST lands cannot flash stale
  // data over the user's just-applied reorder. Still reschedule (at the
  // current cadence) — never tear the loop down.
  if (Date.now() < suppressNextStatePollUntil) {
    schedulePoll(nextPollDelay());
    return;
  }
  const snap = await fetchState();
  if (snap) {
    lastSnapshot = snap;
    applySnapshot(snap);
  }
  // Slow heartbeat while hidden (HIDDEN_POLL_INTERVAL_MS), fast when
  // visible (POLL_INTERVAL_MS). The loop is never stopped.
  schedulePoll(nextPollDelay());
}

async function pollWorkOnce() {
  const ws = await fetchWorkState();
  if (ws) {
    lastWorkState = ws;
    applyWorkState(ws);
  } else {
    // Issue #892 — fail OPEN, not stuck-locked. A null fetch (network
    // error / server restart / abort) used to leave lastWorkState stale
    // at state==="sprint". If the sprint ended during that gap, the
    // exec-mode chip stayed locked and the change-default-mode UI stayed
    // blocked until the next *successful* poll. Clearing to null releases
    // the lock: every lastWorkState consumer (renderDefaultMode,
    // renderDefaultModeFootnote, the setDefaultMode sprint guard) already
    // short-circuits on a falsy work-state, and null is the documented
    // bootstrap value, so no consumer null-derefs. Only re-apply if the
    // state actually changes (it was previously a sprint), so a transient
    // failure during idle is a no-op.
    if (lastWorkState) {
      lastWorkState = null;
      applyWorkState(null);
    }
  }
  // Slow heartbeat while hidden (HIDDEN_POLL_INTERVAL_MS), fast when
  // visible (POLL_INTERVAL_MS). The loop is never stopped.
  scheduleWorkPoll(nextPollDelay());
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
  // Issue #676 — Capture config.dashboard_completed_days for the
  // completed-window dropdown's default value.
  if (snap && snap.config && typeof snap.config.dashboard_completed_days === "number") {
    configCompletedDays = snap.config.dashboard_completed_days;
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
    renderDefaultMode(lastGoodDefaultMode, lastWorkState);
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

  // Issue #802 — unread-dot bookkeeping. Reuse the volatile-safe per-tab
  // fingerprints just computed above (plansFp / issuesFp / branchesFp) so
  // a dot appears only on a *meaningful* change to an inactive tab, never
  // from age/timestamp churn.
  currentTabFingerprint.plans = plansFp;
  currentTabFingerprint.issues = issuesFp;
  currentTabFingerprint.branches = branchesFp;
  // First snapshot seeds lastViewed so the board does not open in dots.
  for (const tab of TAB_SLUGS) {
    if (lastViewed[tab] === null) {
      lastViewed[tab] = currentTabFingerprint[tab];
    }
  }
  // The active tab is always "seen" — keep its baseline current so it never
  // dots and so its dot stays cleared while the user is looking at it.
  if (TAB_SLUGS.includes(activeTab)) {
    lastViewed[activeTab] = currentTabFingerprint[activeTab];
  }
  updateTabDots();
}

// Issue #802 — show/hide the per-tab unread dot. A tab is dotted iff it is
// not the active tab AND its current fingerprint differs from the snapshot
// the user last viewed. Safe to call before the DOM is ready (the element
// lookups simply no-op).
function updateTabDots() {
  if (typeof document === "undefined") return;
  for (const tab of TAB_SLUGS) {
    const btn = document.getElementById("tab-" + tab);
    if (!btn) continue;
    const dot = btn.querySelector(".tab-dot");
    const sr = btn.querySelector(".tab-dot-sr");
    const seen = lastViewed[tab];
    const cur = currentTabFingerprint[tab];
    const unread = (tab !== activeTab) && seen !== null && cur !== null && cur !== seen;
    if (dot) {
      if (unread) dot.removeAttribute("hidden");
      else dot.setAttribute("hidden", "");
    }
    if (sr) {
      if (unread) sr.removeAttribute("hidden");
      else sr.setAttribute("hidden", "");
    }
  }
}

function applyWorkState(ws) {
  const fp = JSON.stringify(ws);
  if (fp !== lastFingerprint.workState) {
    lastFingerprint.workState = fp;
    renderRunStatus(ws);
    renderDefaultModeFootnote(ws);
    // Issue #858 — re-render the chip whenever work-state changes so its
    // lock + displayed batch_mode track sprint start/stop transitions.
    // Skip if the snapshot poll hasn't landed yet (lastGoodDefaultMode
    // is still the bootstrap "phase"); renderDefaultMode is a no-op when
    // the chip DOM isn't ready, but skipping the redundant call keeps
    // the fingerprint logic simple.
    renderDefaultMode(lastGoodDefaultMode, ws);
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

  // Build slug→plan lookup BEFORE the state-pin loop so the completion
  // override (#853 / #905) can consult `p.queue.column` per slug. Used
  // later by the completed-window filter as well.
  const slugToPlanClone = {};
  for (const p of plans) slugToPlanClone[p.slug] = p;

  // Pre-populate from queues (preserves order).
  const seenSlugs = new Set();
  for (const c of PLAN_COLUMNS) {
    const arr = (queues.plans && queues.plans[c]) || [];
    for (const e of arr) {
      const entry = (typeof e === "string") ? { slug: e } : (e || {});
      if (!entry.slug || seenSlugs.has(entry.slug)) continue;
      // Completion override (#905 — client-side half of #853): the ONE
      // exception to W1.3/D2 rule (i), mirroring the server-side
      // completion override at collect.py:1785-1805. The state file
      // owns ordering for ACTIVE plans; for plans the server has
      // already routed to `completed` via the source-of-truth
      // override (status: complete|landed + parseable `completed:`),
      // the stale pin in `queues.plans.<col>` would otherwise lock the
      // card into its old column before the second loop's inferred
      // routing could relocate it. Skip the pin here and let the
      // second loop deposit the slug into out.plans.completed via
      // `p.queue.column`. Non-complete plans pinned to ANY column
      // still honor their pin — rule (i) only relaxes for
      // queue.column === "completed".
      const planForOverride = slugToPlanClone[entry.slug];
      if (planForOverride
          && planForOverride.queue
          && planForOverride.queue.column === "completed") {
        continue;
      }
      seenSlugs.add(entry.slug);
      const obj = { slug: entry.slug };
      if (c === "ready" && entry.mode != null) obj.mode = entry.mode;
      out.plans[c].push(obj);
    }
  }
  // Add inferred entries for plans not present in state.
  // Plans with no column (queue.column === null) are intentionally hidden
  // by _infer_default_column — historical completes without a backfilled
  // date. Do NOT default these to "drafted" (Bug B from PR #650): that
  // override inflates Drafted with plans the inference said to hide.
  //
  // Issue #676 — Client-side completed-window filter. The server now
  // returns ALL completed plans (no window cutoff). We filter here based
  // on the user's completed-window preference from localStorage.
  const planWindow = getCompletedWindow("plan");
  const planCutoff = (planWindow === "all") ? null : Date.now() - planWindow * 86400000;

  for (const p of plans) {
    if (seenSlugs.has(p.slug)) continue;
    const col = p.queue && p.queue.column;
    if (!col || PLAN_COLUMNS.indexOf(col) < 0) continue;
    // Client-side window filter for completed plans.
    if (col === "completed" && planCutoff !== null) {
      const completedRaw = p.completed || "";
      const completedMs = completedRaw ? Date.parse(completedRaw) : NaN;
      if (Number.isNaN(completedMs) || completedMs < planCutoff) continue;
    }
    seenSlugs.add(p.slug);
    out.plans[col].push({ slug: p.slug });
  }

  // Also filter already-queued completed plans against the window.
  if (planCutoff !== null) {
    const filtered = [];
    for (const entry of out.plans.completed) {
      const slug = (typeof entry === "string") ? entry : (entry && entry.slug);
      const plan = slug ? slugToPlanClone[slug] : null;
      const completedRaw = (plan && plan.completed) || "";
      const completedMs = completedRaw ? Date.parse(completedRaw) : NaN;
      if (!Number.isNaN(completedMs) && completedMs >= planCutoff) {
        filtered.push(entry);
      }
      // Plans without a parseable completed timestamp but already in the
      // completed queue are kept (defensive — shouldn't normally happen).
      else if (Number.isNaN(completedMs) && !completedRaw) {
        filtered.push(entry);
      }
    }
    out.plans.completed = filtered;
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
  // Issue #676 — Client-side completed-window filter for issues. The server
  // now returns ALL closed issues; filter here per user preference.
  const issueWindow = getCompletedWindow("issue");
  const issueCutoff = (issueWindow === "all") ? null : Date.now() - issueWindow * 86400000;
  // Build num→issue lookup for timestamp access during filtering.
  const numToIssueClone = {};
  for (const it of issues) {
    if (typeof it.number === "number") numToIssueClone[it.number] = it;
  }

  for (const it of issues) {
    if (typeof it.number !== "number" || seenNums.has(it.number)) continue;
    const col = (it.queue && it.queue.column) || "triage";
    if (ISSUE_COLUMNS.indexOf(col) < 0) continue;
    // Client-side window filter for completed issues.
    if (col === "completed" && issueCutoff !== null) {
      const closedRaw = it.closed_at || "";
      const closedMs = closedRaw ? Date.parse(closedRaw) : NaN;
      if (Number.isNaN(closedMs) || closedMs < issueCutoff) continue;
    }
    seenNums.add(it.number);
    out.issues[col].push(it.number);
  }

  // Also filter already-queued completed issues against the window.
  if (issueCutoff !== null) {
    const filtered = [];
    for (const num of out.issues.completed) {
      const issue = numToIssueClone[num];
      const closedRaw = (issue && issue.closed_at) || "";
      const closedMs = closedRaw ? Date.parse(closedRaw) : NaN;
      if (!Number.isNaN(closedMs) && closedMs >= issueCutoff) {
        filtered.push(num);
      } else if (Number.isNaN(closedMs) && !closedRaw) {
        filtered.push(num);
      }
    }
    out.issues.completed = filtered;
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
  // Issue #676 — completed-window in fingerprint. `typeof` guard for
  // standalone test harnesses that extract this function in isolation.
  const _gcw = (typeof getCompletedWindow !== "undefined") ? getCompletedWindow : null;
  return JSON.stringify({
    dm: defaultMode,
    cw: _gcw ? _gcw("plan") : null,
    rows: plans.map(p => [
      p.slug, p.title, p.status,
      p.phase_count, p.phases_done, p.blurb,
      pos[p.slug] || [
        (p.queue && p.queue.column) || null,
        -1,
        null,
      ],
      // Claim state — symmetric to fingerprintIssues' claim tuple.
      // We track `current_phase` (post-#684 cleanup removed
      // `last_heartbeat_at` as a duplicate of `started_at`). Phase
      // changes drive re-renders so the chip's `phase N/M` segment
      // updates as the pipeline progresses. The 2-tuple is enough —
      // pipeline_id changes when a new pipeline claims; current_phase
      // changes at each phase boundary; both null when no claim.
      p.claim ? [p.claim.pipeline_id || null, p.claim.current_phase || null] : null,
    ]),
  });
}

function fingerprintBranches(branches, worktrees) {
  const wtSet = backedBranchSet(worktrees);
  const byBranch = worktreesByBranch(worktrees);
  return JSON.stringify(branches.map(b => {
    const w = byBranch.get(b.name);
    const landedStatus = (w && w.landed) ? w.landed.status : null;
    return [b.name, b.last_commit_at, b.last_commit_subject, b.upstream, wtSet.has(b.name), landedStatus];
  }));
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
  // Issue #676 — completed-window in fingerprint (see symmetric plan-side
  // comment in fingerprintPlans). Guard for standalone test extraction.
  const _gcwI = (typeof getCompletedWindow !== "undefined") ? getCompletedWindow : null;
  return JSON.stringify({
    trunc: trunc,
    cw: _gcwI ? _gcwI("issue") : null,
    rows: issues.map(i => [
      i.number, i.title, (i.labels || []).map(function(l) { return (l && l.name) || l; }).sort(), i.created_at,
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
  // Issue #884 — plan-row mutation lock. A claim being held means a
  // /run-plan pipeline owns this plan; drag-reorder, drag-recolumn, and
  // the X (discard) all create split-brain with that pipeline. The
  // predicate is the SAME one #858/#874 wire into the chip lock:
  // `plan && plan.claim`. When set we (1) drop draggable + add a
  // claim-lock tooltip naming the in-flight pipeline short id, and
  // (2) render the X disabled + dimmed with the same tooltip (below).
  const isClaimLocked = !!(plan && plan.claim);
  const claimLockPidShort =
    isClaimLocked ? ((plan.claim.pipeline_short) || "?") : null;
  const claimLockTip = isClaimLocked
    ? "Locked while plan is being worked (pipeline " + claimLockPidShort + ")."
    : null;
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
    // Phase progress. Prefer the live claim's current_phase when the plan
    // is claimed (in-flight). For main_protected PR-mode /run-plan the plan
    // tracker on main shows ~0-1 done for the ENTIRE run (all phases land in
    // one PR at the end), so phases_done is structurally stale the whole
    // time work is in flight. The claim's current_phase is the live truth.
    // Fall back to phases_done for unclaimed plans (direct mode, or work
    // already landed to main).
    const total = plan.phase_count || 0;
    let done = plan.phases_done || 0;
    if (plan.claim && typeof plan.claim.current_phase === "string") {
      const cm = plan.claim.current_phase.match(/Phase\s+(\d+)/i);
      if (cm) done = parseInt(cm[1], 10);
    }
    const meta = el("div", { cls: "card-row card-sub" });
    const ratio = done + " / " + total + " phases";
    meta.appendChild(el("span", { text: ratio }));
    card.appendChild(meta);

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
  // The chip is the liveness/activity indicator: "working on phase N ·
  // <slug> · <age>". The N/M progress framing lives on the bar above (which
  // is driven from this same claim.current_phase when claimed), so the chip
  // drops the redundant "/M" denominator. Notes:
  //   1. Phase fragment: "working on phase N" parsed from current_phase
  //      ("Phase 3" → N=3). Non-numeric section headers (e.g. "Parse plan")
  //      show "working on <header>" verbatim; absent → bare "in-flight".
  //   2. Age string is derived from started_at (post-#684 cleanup
  //      removed last_heartbeat_at as a duplicate of started_at).
  //   3. The .claim-chip--in-flight class is retained — the collapsed-column
  //      footer badges aggregate by that class, not the visible text.
  //   4. data-kind="plan" is already encoded; the aria-disabled +
  //      removeAttribute("draggable") block is identical to the issue
  //      side and is honored by moveAllInColumn (kind-generic) and the
  //      plan-up/down/left/right/plan-discard guard in handleAction.
  if (plan && plan.claim) {
    const c = plan.claim;
    const startedAt = c.started_at || null;
    const rt = startedAt ? relativeTime(startedAt) : "";
    const ageStr = rt || "?";
    const pidShort = c.pipeline_short || "?";
    const cp = c.current_phase;
    let phaseFragment = "in-flight";
    if (typeof cp === "string" && cp) {
      const m = cp.match(/Phase\s+(\d+)/i);
      phaseFragment = m ? "working on phase " + m[1] : "working on " + cp;
    }
    const tip = c.pipeline_id
      ? "claim pipeline=" + c.pipeline_id +
        " started=" + (c.started_at || "?") +
        " current_phase=" + (c.current_phase || "?")
      : "claim metadata pending";
    const row = el("div", { cls: "card-sub" });
    row.appendChild(el("span", {
      cls: "claim-chip claim-chip--in-flight",
      attrs: { title: tip },
      text: phaseFragment + " · " + pidShort + " · " + ageStr,
    }));
    card.appendChild(row);
    card.setAttribute("aria-disabled", "true");
    card.removeAttribute("draggable");
    // Issue #884 — gate (a): the card is already non-draggable (no
    // draggable attr → onDragStart's `li.card[draggable='true']` match
    // fails, so no drag starts and no recolumn drop is possible). Add the
    // claim-lock affordance: a `claim-locked` class for CSS pointer-event
    // suppression on the drag surface + a tooltip naming the in-flight
    // pipeline short id (same string used on the disabled X below).
    card.className = (card.className ? card.className + " " : "") + "claim-locked";
    if (claimLockTip) card.setAttribute("title", claimLockTip);
  }

  // Per-row mode chip on Ready cards (issue #814 + follow-up).
  // Two effective states keyed on claim + effective dispatch mode:
  //   - running-finish  → LOCKED. /run-plan finish-auto holds the claim
  //                       across all phases and resolves mode from args
  //                       (not monitor-state.json), so a click would be
  //                       informationally inert. The lock makes that honest.
  //   - anything else   → togglable. Cycle inherit ⇄ phase ⇄ finish.
  //                       This includes both queued and running-phase:
  //                       in queued you can change your mind freely; in
  //                       running-phase /work-on-plans re-reads the chip
  //                       between phases, so toggles still take effect.
  //                       If a user toggles to finish, the next dispatch
  //                       picks up finish-auto and the chip locks then.
  // We still distinguish "queued" vs "running-phase" via data-state so
  // CSS can colorize running chips (signals "this is live"), but the
  // click behavior is the same in both.
  // Effective mode precedence (issue #874):
  //   1. plan.claim.dispatch_mode (persisted on the /run-plan claim;
  //      outlives the /work-on-plans wrapper that spawned it — sibling
  //      to #858's wrapper-lifetime batch_mode signal).
  //   2. currentEntryMode(slug) explicit override.
  //   3. defaultMode || "phase".
  // Pre-#874 claims lack dispatch_mode → collect.py surfaces None →
  // step 1 falls through to step 2 + step 3 unchanged. Back-compat is
  // structural, not flag-gated.
  if (col === "ready") {
    const entryMode = currentEntryMode(slug);
    const isOverride = entryMode === "phase" || entryMode === "finish";
    const claimDispatchMode =
      (plan && plan.claim && plan.claim.dispatch_mode) || null;
    const effectiveMode =
      claimDispatchMode || (isOverride ? entryMode : (defaultMode || "phase"));
    const isClaimed = !!(plan && plan.claim);
    const locked = isClaimed && effectiveMode === "finish";
    let state, ariaLabel;
    if (locked) {
      state = "running-finish";
      ariaLabel = "Mode: finish (locked while running).";
    } else if (isClaimed) {
      state = "running-phase";
      ariaLabel = "Mode: " + effectiveMode
        + " (running). Click to cycle inherit, phase, finish.";
    } else {
      state = "queued";
      ariaLabel = isOverride
        ? ("Mode: " + effectiveMode + " (override). Click to cycle inherit, phase, finish.")
        : ("Mode: " + effectiveMode + " (inherits default). Click to cycle inherit, phase, finish.");
    }
    const chipAttrs = {
      type: "button",
      "data-slug": slug,
      "data-state": state,
      "data-source": isOverride ? "explicit" : "inherit",
      "aria-label": ariaLabel,
    };
    if (locked) {
      chipAttrs["aria-disabled"] = "true";
      chipAttrs.disabled = "disabled";
    } else {
      chipAttrs["data-action"] = "toggle-mode";
    }
    const chipOpts = { cls: "mode-chip", attrs: chipAttrs };
    if (locked) {
      chipOpts.html = '<span class="mode-chip-lock" aria-hidden="true">'
        + SVG_ICONS.lock + '</span> ' + effectiveMode;
    } else {
      chipOpts.text = effectiveMode;
    }
    const chip = el("button", chipOpts);
    card.appendChild(chip);
  }

  // Card controls: ↑ ↓ ← → and remove. Omitted for completed plans
  // (Phase 4 / D5 — Completed is read-only; no per-card action buttons).
  // The copy button is always present (copying is safe regardless of
  // claim or completed state).
  {
    const controls = el("div", {
      cls: "card-controls",
      attrs: { role: "group", "aria-label": isCompleted ? "Plan actions" : "Move this plan" },
    });
    if (!isCompleted) {
      var writablePlanCols = ["drafted", "reviewed", "ready", "backlog", "discarded"];
      var planColIdx = writablePlanCols.indexOf(col);
      controls.appendChild(makeMoveBtn("plan-up", slug, "↑", "Move up"));
      controls.appendChild(makeMoveBtn("plan-down", slug, "↓", "Move down"));
      if (planColIdx > 0) {
        controls.appendChild(makeMoveBtn("plan-left", slug, "←", "Move to previous column"));
      }
      if (planColIdx >= 0 && planColIdx < writablePlanCols.length - 1) {
        controls.appendChild(makeMoveBtn("plan-right", slug, "→", "Move to next column"));
      }
      if (col !== "discarded") {
        // Issue #884 — gate (c): when a claim is held the X (discard) is
        // rendered disabled + dimmed (.remove-btn:disabled) with a tooltip
        // naming the in-flight pipeline. The runtime handleAction guard
        // (aria-disabled match) already no-ops the click; the disabled attr
        // + dim make the lock honest at the affordance level too. The
        // data-action is dropped when locked so the delegated dispatcher
        // never even routes the click. Back-compat: claim absent →
        // identical to before (enabled, no title, "data-action":
        // "plan-discard" present in the unclaimed object-literal below).
        if (isClaimLocked) {
          controls.appendChild(el("button", {
            cls: "remove-btn claim-locked",
            attrs: {
              type: "button",
              "data-slug": slug,
              "aria-label": "Discard plan (disabled — plan is in-flight)",
              disabled: "disabled",
              "aria-disabled": "true",
              title: claimLockTip,
            },
            html: SVG_ICONS.x,
          }));
        } else {
          controls.appendChild(el("button", {
            cls: "remove-btn",
            attrs: {
              type: "button",
              "data-action": "plan-discard",
              "data-slug": slug,
              "aria-label": "Discard plan (move to Discarded)",
            },
            html: SVG_ICONS.x,
          }));
        }
      }
    }
    controls.appendChild(makeCopyBtn((plan && plan.title) || slug));
    card.appendChild(controls);
  }

  return card;
}

var MOVE_ICON_MAP = {"↑": "arrowUp", "↓": "arrowDown", "←": "arrowLeft", "→": "arrowRight"};

function makeMoveBtn(action, slug, label, ariaLabel) {
  var icon = MOVE_ICON_MAP[label] ? SVG_ICONS[MOVE_ICON_MAP[label]] : label;
  return el("button", {
    cls: "move-btn",
    attrs: {
      type: "button",
      "data-action": action,
      "data-slug": slug,
      "aria-label": ariaLabel,
    },
    html: icon,
  });
}

function makeIssueMoveBtn(action, num, label, ariaLabel) {
  var icon = MOVE_ICON_MAP[label] ? SVG_ICONS[MOVE_ICON_MAP[label]] : label;
  return el("button", {
    cls: "move-btn",
    attrs: {
      type: "button",
      "data-action": action,
      "data-number": String(num),
      "aria-label": ariaLabel,
    },
    html: icon,
  });
}

// Copy-to-clipboard button. Uses a direct event listener (not the
// delegated data-action dispatch) so it bypasses the claim guard — copying
// title text is always safe. Shows a brief checkmark on success.
function makeCopyBtn(titleText) {
  var btn = el("button", {
    cls: "move-btn copy-btn",
    attrs: {
      type: "button",
      "data-action": "copy-title",
      "aria-label": "Copy title to clipboard",
    },
    html: SVG_ICONS.copy,
  });
  btn.addEventListener("click", function(e) {
    e.stopPropagation();
    e.preventDefault();
    navigator.clipboard.writeText(titleText).then(function() {
      btn.textContent = "✓";
      setTimeout(function() { btn.innerHTML = SVG_ICONS.copy; }, 1500); // chrome-only
    });
  });
  return btn;
}

// Column-header chevron button: triggers "move all non-claimed cards in
// this column to the adjacent column" (kind ∈ {plan, issue}; column is the
// source column slug; direction is "left" or "right"). Per-card iteration
// runs in moveAllInColumn(); claimed cards are skipped (with shake) — both
// at snapshot time AND on re-query inside the per-card loop, to close the
// race window where a poll-driven claim lands between the click and the
// per-card dispatch.
function makeColumnMoveAllBtn(action, kind, column, label, ariaLabel) {
  var icon = label === "«" ? SVG_ICONS.chevronsLeft : SVG_ICONS.chevronsRight;
  return el("button", {
    cls: "column-head-btn move-all-btn",
    attrs: {
      type: "button",
      tabindex: "0",
      "data-action": action,
      "data-kind": kind,
      "data-column": column,
      "aria-label": ariaLabel,
    },
    html: icon,
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

  // Issue #675 — Section-nav pill strip for below-band discoverability.
  const navStrip = buildSectionNavStrip("plan", lastGoodQueues);
  body.appendChild(navStrip);

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
    appendCollapseToggle(head, "plan", c, PLAN_COLUMN_LABELS[c]);
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
    applyCollapseStateToColumn(colDiv, "plan", c, PLAN_COLUMN_LABELS[c]);
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

// Issue #858 — when a sprint is in flight, the chip mirrors the captured
// batch_mode from work-on-plans-state.json (NOT the saved default_mode)
// and is locked: clicks no-op with a tooltip explaining the lock. The
// in-flight banner adjacent to the chip reserves layout space at all
// times via CSS visibility (see .dm-footnote-slot) so its appearance
// doesn't shift the chip row.
function renderDefaultMode(mode, ws) {
  const phase = $("dm-phase");
  const finish = $("dm-finish");
  if (!phase || !finish) return;
  const inFlight = !!(ws && ws.state === "sprint");
  const effectiveMode = (inFlight && ws.batch_mode) ? ws.batch_mode : mode;
  const isPhase = effectiveMode === "phase";
  phase.setAttribute("aria-pressed", isPhase ? "true" : "false");
  finish.setAttribute("aria-pressed", isPhase ? "false" : "true");
  const lockTitle = inFlight
    ? "Sprint in flight — default mode locked to the captured batch mode (" + effectiveMode + "). Stop the sprint to change it."
    : "";
  for (const btn of [phase, finish]) {
    if (inFlight) {
      // Use data-locked (not aria-disabled / disabled) so the click
      // still reaches the handler — setDefaultMode surfaces the lock
      // reason via a toast. aria-disabled would block click dispatch
      // under some test runners (and would also hide the chip from
      // some screen reader users). The tooltip + visual cue + toast
      // covers the affordance.
      btn.setAttribute("data-locked", "true");
      btn.setAttribute("title", lockTitle);
    } else {
      btn.removeAttribute("data-locked");
      btn.removeAttribute("title");
    }
  }
}

function renderDefaultModeFootnote(ws) {
  const note = $("default-mode-footnote");
  if (!note) return;
  const inFlight = ws && ws.state === "sprint";
  // Keep the slot in the layout always (CSS visibility) so the chip row
  // doesn't shift when a sprint starts/stops. Toggle a class instead of
  // the `hidden` attribute (which is display:none and reflows siblings).
  if (inFlight) {
    note.classList.add("is-visible");
  } else {
    note.classList.remove("is-visible");
  }
  // Defensive: clear any legacy `hidden` attribute that older builds set.
  note.removeAttribute("hidden");
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

// Issue #717 — Branch grouping constants.
var BRANCH_SECTIONS = ["active", "landed", "local", "remote-only"];
var BRANCH_SECTION_LABELS = {
  "active": "Active",
  "landed": "Landed",
  "local": "Local (no worktree)",
  "remote-only": "Remote only",
};

// Four accurate buckets:
//   active      — local branch WITH a live worktree, no .landed marker
//   landed      — local branch WITH a worktree carrying a .landed marker
//   local       — local branch with NO worktree (was mislabeled "remote-only")
//   remote-only — branch on origin but NOT checked out locally (was invisible)
// The collector tags each branch with `locality` ("local"|"remote-only"|
// "both"); a worktree match implies the branch is local, so we only need
// `locality === "remote-only"` to separate the genuinely-remote bucket.
function classifyBranch(b, byBranch) {
  var w = byBranch.get(b.name);
  if (w && w.landed) return "landed";
  if (w) return "active";
  if (b.locality === "remote-only") return "remote-only";
  return "local";
}

function branchStatePill(b, byBranch) {
  var w = byBranch.get(b.name);
  var hasWorktree = !!w;
  var hasRemote = !!b.upstream;
  if (hasWorktree && hasRemote) {
    return el("span", {
      cls: "branch-state-pill branch-state-pill--local-remote",
      text: "LOCAL · REMOTE",
      attrs: { title: "Has worktree and remote tracking branch" },
    });
  }
  if (hasWorktree) {
    return el("span", {
      cls: "branch-state-pill branch-state-pill--local",
      text: "LOCAL",
      attrs: { title: "Has worktree, not pushed to remote" },
    });
  }
  return el("span", {
    cls: "branch-state-pill branch-state-pill--remote",
    text: "REMOTE",
    attrs: { title: "No worktree" },
  });
}

function buildBranchCard(b, byBranch) {
  var card = el("article", {
    cls: "card",
    attrs: {
      tabindex: "0",
      role: "button",
      "data-kind": "branch",
      "data-name": b.name,
      "aria-label": "Branch " + b.name,
    },
  });
  var head = el("div", { cls: "card-row" });
  // Checkbox for bulk selection. Protected branches carry data-protected
  // so the bulk-copy command handler can defensively exclude them from the
  // emitted /cleanup-merged command (their checkboxes are also disabled by
  // the Half-A display change; this is belt-and-suspenders).
  var cbAttrs = { type: "checkbox", "data-branch-name": b.name, "aria-label": "Select " + b.name };
  if (b.protected) cbAttrs["data-protected"] = "true";
  var cb = el("input", {
    cls: "branch-select-cb",
    attrs: cbAttrs,
  });
  head.appendChild(cb);
  var url = branchUrl(b.name);
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
  // Config-protected shield (zskills cleanup.protected_branches — NOT
  // GitHub branch protection). Signals "/cleanup-merged skips this branch".
  if (b.protected) {
    head.appendChild(el("span", {
      cls: "branch-protected-shield",
      text: "🛡",
      attrs: {
        title: "Config-protected (cleanup.protected_branches) — /cleanup-merged skips this branch",
        "aria-label": "Config-protected branch",
      },
    }));
  }
  // State pill
  head.appendChild(branchStatePill(b, byBranch));
  if (b.last_commit_at) {
    head.appendChild(el("span", { cls: "card-sub branch-time", text: relativeTime(b.last_commit_at) }));
  }
  card.appendChild(head);
  if (b.last_commit_subject) {
    card.appendChild(el("div", { cls: "card-blurb", text: b.last_commit_subject }));
  }
  if (b.upstream) {
    card.appendChild(el("div", { cls: "card-sub", text: "upstream: " + b.upstream }));
  }
  var w = byBranch.get(b.name);
  if (w) {
    var status = w.landed ? w.landed.status : "not-landed";
    var wtRow = el("div", { cls: "card-row card-worktree-row" });
    wtRow.appendChild(el("span", {
      cls: "pill " + landedPillClass(status),
      // Display-only: `full` (cherry-pick landing) and `landed` (PR landing)
      // both mean "everything is on main"; show "LANDED" for both. Stored
      // marker status and landedPillClass color mapping are unchanged. (#776)
      text: status === "full" ? "landed" : status,
    }));
    if (w.path) {
      wtRow.appendChild(el("span", { cls: "mono card-sub", text: basename(w.path) }));
    }
    if (typeof w.age_seconds === "number") {
      wtRow.appendChild(el("span", {
        cls: "card-sub branch-age",
        text: ageSecondsToText(w.age_seconds),
      }));
    }
    card.appendChild(wtRow);
  }
  return card;
}

function buildBranchBulkBar(sectionKey, branchNames) {
  var bar = el("div", { cls: "branch-bulk-bar" });
  var label = el("label");
  var selectAll = el("input", {
    attrs: {
      type: "checkbox",
      "data-action": "branch-select-all",
      "data-section": sectionKey,
      "aria-label": "Select all in " + BRANCH_SECTION_LABELS[sectionKey],
    },
  });
  label.appendChild(selectAll);
  label.appendChild(document.createTextNode("Select all"));
  bar.appendChild(label);
  var copyBtn = el("button", {
    cls: "branch-bulk-copy-btn",
    attrs: {
      type: "button",
      "data-action": "branch-bulk-copy",
      "data-section": sectionKey,
      "aria-label": "Copy /cleanup-merged command for selected branches",
    },
    text: "Copy /cleanup-merged for 0 branches",
  });
  bar.appendChild(copyBtn);
  return bar;
}

function buildBranchSection(sectionKey, branchesInSection, byBranch) {
  var sec = el("div", {
    cls: "branch-section",
    attrs: {
      "data-branch-section": sectionKey,
      id: "branch-section-" + sectionKey,
    },
  });
  // Section header
  var head = el("div", {
    cls: "branch-section-head",
    attrs: {
      "data-action": "branch-section-toggle",
      "data-section": sectionKey,
      role: "button",
      tabindex: "0",
      "aria-expanded": "true",
      "aria-label": BRANCH_SECTION_LABELS[sectionKey] + " " + branchesInSection.length + " branches",
    },
  });
  head.appendChild(el("span", {
    cls: "branch-section-label",
    text: BRANCH_SECTION_LABELS[sectionKey],
  }));
  head.appendChild(el("span", {
    cls: "branch-section-count",
    text: "(" + branchesInSection.length + ")",
  }));
  var toggle = el("button", {
    cls: "branch-section-toggle",
    attrs: {
      type: "button",
      "data-action": "branch-section-toggle",
      "data-section": sectionKey,
      "aria-label": "Collapse " + BRANCH_SECTION_LABELS[sectionKey],
      title: "Collapse / expand",
    },
    html: SVG_ICONS.minus,
  });
  head.appendChild(toggle);
  sec.appendChild(head);
  // Bulk copy bar
  var names = branchesInSection.map(function(b) { return b.name; });
  sec.appendChild(buildBranchBulkBar(sectionKey, names));
  // Cards body
  var body = el("div", { cls: "branch-section-body" });
  for (var i = 0; i < branchesInSection.length; i++) {
    body.appendChild(buildBranchCard(branchesInSection[i], byBranch));
  }
  sec.appendChild(body);
  // Apply saved collapse state
  applyBranchSectionCollapse(sec, sectionKey);
  return sec;
}

function applyBranchSectionCollapse(secEl, sectionKey) {
  var collapsed = isCollapsed("branch", sectionKey);
  if (collapsed) {
    secEl.classList.add("collapsed");
  } else {
    secEl.classList.remove("collapsed");
  }
  var toggle = secEl.querySelector(".branch-section-toggle");
  if (toggle) {
    toggle.setAttribute("aria-expanded", collapsed ? "false" : "true");
    toggle.innerHTML = collapsed ? SVG_ICONS.plus : SVG_ICONS.minus; // chrome-only
    toggle.setAttribute("aria-label", (collapsed ? "Expand " : "Collapse ") + BRANCH_SECTION_LABELS[sectionKey]);
  }
  var head = secEl.querySelector(".branch-section-head");
  if (head) {
    head.setAttribute("aria-expanded", collapsed ? "false" : "true");
  }
}

function buildBranchNavStrip(groups) {
  var strip = el("nav", {
    cls: "section-nav-strip",
    attrs: { "aria-label": "Branch sections", "data-kind": "branch" },
  });
  for (var i = 0; i < BRANCH_SECTIONS.length; i++) {
    var key = BRANCH_SECTIONS[i];
    var count = (groups[key] || []).length;
    var pill = el("button", {
      cls: "section-nav-pill",
      attrs: {
        type: "button",
        "data-action": "branch-nav-pill",
        "data-target": "branch-section-" + key,
        "data-section": key,
        "aria-label": BRANCH_SECTION_LABELS[key] + " " + count + " branches — click to scroll",
      },
      text: BRANCH_SECTION_LABELS[key] + " " + count,
    });
    strip.appendChild(pill);
  }
  return strip;
}

function renderBranches(branches, worktrees) {
  var body = $("branches-body");
  var empty = $("branches-empty");
  clear(body);
  if (!branches.length) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  var byBranch = worktreesByBranch(worktrees);
  // Group branches into sections
  var groups = { "active": [], "landed": [], "local": [], "remote-only": [] };
  for (var i = 0; i < branches.length; i++) {
    var section = classifyBranch(branches[i], byBranch);
    groups[section].push(branches[i]);
  }
  // Nav strip at top
  body.appendChild(buildBranchNavStrip(groups));
  // Render each section
  for (var si = 0; si < BRANCH_SECTIONS.length; si++) {
    var key = BRANCH_SECTIONS[si];
    var arr = groups[key];
    if (!arr.length) continue;
    body.appendChild(buildBranchSection(key, arr, byBranch));
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
  // Closure-reason chip (issue #687) — only renders for Completed-column
  // cards whose stateReason is NOT "COMPLETED". Distinguishes "not planned"
  // closures from genuine completions. Reuses .claim-chip styling.
  if (isCompleted && issue && issue.state_reason !== "COMPLETED") {
    const reason = issue.state_reason === "NOT_PLANNED" ? "not planned" : "closed";
    const row = el("div", { cls: "card-sub" });
    row.appendChild(el("span", {
      cls: "closure-chip",
      attrs: { title: "stateReason: " + (issue.state_reason || "null") },
      text: reason,
    }));
    card.appendChild(row);
  }
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
  //
  // Mutual exclusion (#862): an issue with a live in-flight claim is NOT
  // also a skipped issue — the claim chip (rendered below) is the
  // authoritative live state, and showing BOTH an in-flight chip AND a
  // `skip:` chip is the split-brain this fix closes. A claimed card on a
  // non-completed column suppresses the skip chip entirely. (Completed
  // cards never carry a live claim, so an explicitly-skipped completed
  // item — rare — keeps its skip chip.)
  var hasLiveClaim = !!(issue && issue.claim && !isCompleted);
  if (!hasLiveClaim && issue && issue.skip_reason && issue.skip_reason.code && issue.skip_reason.code !== "unresearched") {
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
      const name = (lab && lab.name) || lab || "";
      const color = (lab && lab.color) || "";
      const chip = el("span", { cls: "label-chip", text: name });
      if (color) {
        chip.style.color = "#" + color;
        chip.style.borderColor = "#" + color;
        chip.style.background = "#" + color + "18";
      }
      labels.appendChild(chip);
    }
    card.appendChild(labels);
  }
  // Phase 4 / D5 — Completed cards skip per-card move/remove controls.
  // The copy button is always present (copying is safe regardless of
  // claim or completed state).
  {
    const controls = el("div", {
      cls: "card-controls",
      attrs: { role: "group", "aria-label": isCompleted ? "Issue actions" : "Move this issue" },
    });
    if (!isCompleted) {
      controls.appendChild(makeIssueMoveBtn("issue-up", num, "↑", "Move up"));
      controls.appendChild(makeIssueMoveBtn("issue-down", num, "↓", "Move down"));
      var writableIssueCols = ["triage", "ready", "backlog"];
      var colIdx = writableIssueCols.indexOf(col);
      if (colIdx > 0) {
        controls.appendChild(makeIssueMoveBtn("issue-left", num, "←", "Move to previous column"));
      }
      if (colIdx >= 0 && colIdx < writableIssueCols.length - 1) {
        controls.appendChild(makeIssueMoveBtn("issue-right", num, "→", "Move to next column"));
      }
    }
    const issueTitle = issue ? ("#" + num + " " + (issue.title || "")) : ("#" + num);
    controls.appendChild(makeCopyBtn(issueTitle));
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

  // Issue #675 — Section-nav pill strip for below-band discoverability.
  const navStrip = buildSectionNavStrip("issue", queues);
  body.appendChild(navStrip);

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
    appendCollapseToggle(head, "issue", c, ISSUE_COLUMN_LABELS[c]);
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
    applyCollapseStateToColumn(colDiv, "issue", c, ISSUE_COLUMN_LABELS[c]);
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

// ----------------------------------------- section-nav pill strip (Issue #675)

// Build a horizontal pill strip for a panel (kind="plan" or "issue") that
// shows section labels + live counts. Clicking a pill scrolls the target
// section into view. If the target column is collapsed (PR #668 machinery),
// it is expanded first. The strip uses `data-action="section-nav-pill"` so
// the shared delegated click handler in handleAction dispatches it.
//
// Sections: one pill per column (Drafted, Reviewed, Ready, ... for plans;
// Triage, Ready, Backlog, Completed for issues). Discarded skipped for issues.
function buildSectionNavStrip(kind, queues) {
  const strip = el("nav", {
    cls: "section-nav-strip",
    attrs: { "aria-label": "Jump to section", "data-kind": kind },
  });
  const queueDict = (kind === "plan")
    ? (queues && queues.plans) || {}
    : (queues && queues.issues) || {};
  const activeCols = (kind === "plan") ? ACTIVE_PLAN_COLUMNS : ACTIVE_ISSUE_COLUMNS;
  const labels = (kind === "plan") ? PLAN_COLUMN_LABELS : ISSUE_COLUMN_LABELS;

  // One pill per column — active columns first, then below-band.
  var allCols = (kind === "plan") ? PLAN_COLUMNS : ISSUE_COLUMNS;
  var prefix = (kind === "plan") ? "plans" : "issues";
  for (var ci = 0; ci < allCols.length; ci++) {
    var c = allCols[ci];
    if (c === "discarded" && kind !== "plan") continue;
    var count = (queueDict[c] || []).length;
    var headId = prefix + "-col-" + c;
    strip.appendChild(buildNavPill(labels[c], count, headId, kind, c));
  }
  return strip;
}

function buildNavPill(label, count, targetId, kind, col) {
  return el("button", {
    cls: "section-nav-pill",
    attrs: {
      type: "button",
      "data-action": "section-nav-pill",
      "data-target": targetId,
      "data-kind": kind,
      "data-column": col || "",
      "aria-label": label + " " + count + " items — click to scroll",
    },
    text: label + " " + count,
  });
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
    // Issue #677 — `discarded` is plans-only in v1; issues-side support
    // deferred to a follow-up (needs a live-set filter in
    // _annotate_issues_queue, separate from this PR). Skip the column
    // for the issues band so it doesn't render an empty placeholder.
    if (c === "discarded" && kind !== "plan") continue;
    const colDiv = el("div", { cls: "column" });
    const headId = (kind === "plan" ? "plans" : "issues") + "-col-" + c;
    const head = el("div", { cls: "column-head", attrs: { id: headId } });
    head.appendChild(el("span", { text: labels[c] }));
    const arr = queueDict[c] || [];
    head.appendChild(el("span", { cls: "muted", text: String(arr.length) }));
    // Issue #676 — Completed-window dropdown in the Completed column header.
    if (c === "completed") {
      const currentWindow = getCompletedWindow(kind);
      const select = el("select", {
        cls: "completed-window-select",
        attrs: {
          "data-action": "completed-window-change",
          "data-kind": kind,
          "aria-label": "Completed time window",
        },
      });
      const options = [
        { value: "7", text: "7d" },
        { value: "14", text: "14d" },
        { value: "30", text: "30d" },
        { value: "90", text: "90d" },
        { value: "all", text: "All" },
      ];
      for (const opt of options) {
        const optEl = el("option", { text: opt.text, attrs: { value: opt.value } });
        if (String(currentWindow) === opt.value) optEl.selected = true;
        select.appendChild(optEl);
      }
      head.appendChild(select);
    }

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
    appendCollapseToggle(head, kind, c, labels[c]);
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
    applyCollapseStateToColumn(colDiv, kind, c, labels[c]);
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
      attrs: { type: "button", "data-action": "copy-cmd", "data-cmd": cmd, "aria-label": "Copy command" },
      html: SVG_ICONS.copy,
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
  //
  // Issue #905 — Drag-to-Completed safety hatch (client-side half of
  // #853): the caller may set `opts.includeCompletedPlans = true` when
  // the originating action was a drag onto Completed for a plan whose
  // frontmatter status is `complete` / `landed` (gated on the UI side
  // by isCompletedDropAllowed in onDragOver/onDragEnter/onDrop). When
  // set, plans.completed passes through unstripped; the server-side
  // validator at server._validate_queue_body re-checks each slug's
  // resolved status from the plan file and rejects mismatched entries
  // (defense in depth — never trust the client's status assertion).
  // Issues remain unconditionally stripped — there is no drag-to-
  // Completed hatch for issues.
  const allowPlansCompleted = !!(opts && opts.includeCompletedPlans);
  const stripCompleted = (obj) => {
    const out = {};
    for (const k of Object.keys(obj || {})) {
      if (k === "completed") continue;
      out[k] = obj[k];
    }
    return out;
  };
  const plansForPayload = allowPlansCompleted
    ? Object.assign({}, queues.plans)  // pass `completed` through
    : stripCompleted(queues.plans);
  const payload = {
    default_mode: queues.default_mode || "phase",
    plans: plansForPayload,
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
  renderDefaultMode(lastGoodDefaultMode, lastWorkState);
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
    renderDefaultMode(lastGoodDefaultMode, lastWorkState);
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
        plans: { drafted: [], reviewed: [], ready: [], backlog: [], discarded: [], completed: [] },
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
    var writablePlanCols = ["drafted", "reviewed", "ready", "backlog", "discarded"];
    const ci = writablePlanCols.indexOf(loc.col);
    if (ci <= 0) {
      next.plans[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = writablePlanCols[ci - 1];
    targetIdx = next.plans[targetCol].length;
  } else if (dCol === "right") {
    var writablePlanCols2 = ["drafted", "reviewed", "ready", "backlog", "discarded"];
    const ci = writablePlanCols2.indexOf(loc.col);
    if (ci < 0 || ci >= writablePlanCols2.length - 1) {
      next.plans[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = writablePlanCols2[ci + 1];
    targetIdx = next.plans[targetCol].length;
  } else if (typeof dCol === "object" && dCol && dCol.col) {
    targetCol = dCol.col;
    targetIdx = (dCol.idx == null) ? next.plans[targetCol].length : dCol.idx;
  }
  next.plans[targetCol].splice(targetIdx, 0, entry);
  // Issue #905 — Drag-to-Completed safety hatch. When the user has
  // landed a card in the Completed column (gated upstream on
  // status: complete|landed by isCompletedDropAllowed), thread the
  // `includeCompletedPlans` opt through commitQueueChange→postQueue so
  // the normal `stripCompleted` defense doesn't drop the entry on the
  // floor. Server-side _validate_queue_body independently re-verifies
  // each slug's frontmatter status.
  const opts = { action: "Move plan" };
  if (targetCol === "completed") opts.includeCompletedPlans = true;
  const ok = await commitQueueChange(next, opts);
  if (ok) {
    announce("plans-live", "Moved plan " + slug + " to " + PLAN_COLUMN_LABELS[targetCol] + " position " + (targetIdx + 1));
  }
}

async function discardPlan(slug) {
  // Issue #677 — ✕ on a plan card moves it to the Discarded column
  // (state.plans.discarded) instead of just splicing from the explicit
  // state, which previously was a no-op (the post-snapshot inference
  // fallback re-routed status:active plans back to Drafted). "Discarded"
  // means dismissed-but-not-deleted: the plan file stays on disk; only
  // the dashboard board hides it (in a collapsed-by-default column).
  // No-op when already in the discarded column.
  const next = clonedQueues();
  const loc = findPlan(next, slug);
  if (!loc) return;
  if (loc.col === "discarded") return;
  const entry = next.plans[loc.col].splice(loc.idx, 1)[0];
  if (!next.plans.discarded) next.plans.discarded = [];
  next.plans.discarded.push(entry);
  const ok = await commitQueueChange(next, { action: "Discard plan" });
  if (ok) announce("plans-live", "Discarded plan " + slug);
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
    var writableIssueCols = ["triage", "ready", "backlog"];
    const ci = writableIssueCols.indexOf(loc.col);
    if (ci <= 0) {
      next.issues[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = writableIssueCols[ci - 1];
    targetIdx = next.issues[targetCol].length;
  } else if (dCol === "right") {
    var writableIssueCols2 = ["triage", "ready", "backlog"];
    const ci = writableIssueCols2.indexOf(loc.col);
    if (ci < 0 || ci >= writableIssueCols2.length - 1) {
      next.issues[loc.col].splice(loc.idx, 0, entry);
      return;
    }
    targetCol = writableIssueCols2[ci + 1];
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
  // Issue #858 — sprint-in-flight lock. The chip mirrors the captured
  // batch_mode and clicks no-op (with a toast nudge to surface the
  // reason). The setter also blocks at the DOM level (data-locked) but
  // we re-check here in case the chip render lagged the work-state
  // poll, or a programmatic caller bypasses the click path.
  if (lastWorkState && lastWorkState.state === "sprint") {
    showToast(
      "Default mode is locked while a sprint is in flight (captured: " +
        (lastWorkState.batch_mode || "phase") +
        "). Stop the sprint to change it.",
      "info",
    );
    return;
  }
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

// Escalate a running (claimed) plan's mode to finish. One-way: never sets
// back to phase or inherit. Issue #814. /work-on-plans re-reads the chip
// each round, so this takes effect at the next phase dispatch.
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
  // Issue #884 — gate (b): never start a drag on a claimed card. The
  // render path already drops draggable when a claim is held (so the
  // selector above normally excludes it), but aria-disabled is the
  // source-of-truth for claim-respect (cf. moveAllInColumn's in-loop
  // re-check). Guarding here closes the poll-race window where a claim
  // lands between render and the next snapshot: no dragState is set, so
  // the column drop-target never highlights and no recolumn/reorder POST
  // can fire for a locked card.
  if (card.getAttribute("aria-disabled") === "true") return;
  const kind = card.getAttribute("data-kind");
  const slug = card.getAttribute("data-slug");
  const num = card.getAttribute("data-number");
  // Capture the source column for postQueue (used elsewhere to strip
  // `completed` defensively, and for column-aware drag affordances).
  const sourceColumn = card.getAttribute("data-column");
  // Issue #905 — Drag-to-Completed safety hatch (client-side half of
  // #853). Capture the plan's effective status (lowercased) so the
  // drop-zone guards (onDragEnter / onDragOver / onDrop) can selectively
  // allow a drop onto the Completed column when — and only when — the
  // plan's frontmatter declares `status: complete` or `status: landed`.
  // For any other status (active, conflict, null, unknown) the Completed
  // drop zone refuses to highlight and the drop is hard-rejected, exactly
  // as today. `status` lookup is best-effort via the in-memory snapshot;
  // null when the slug is not in lastSnapshot.plans (defensive — caller
  // is the live DOM, so it should be present).
  let planStatus = null;
  if (kind === "plan" && slug) {
    const snap = (typeof lastSnapshot !== "undefined") ? lastSnapshot : null;
    const planList = (snap && snap.plans) || [];
    for (const p of planList) {
      if (p && p.slug === slug) {
        planStatus = (p.status || "").toLowerCase() || null;
        break;
      }
    }
  }
  dragState = { kind, slug, num, sourceColumn, planStatus };
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

// Issue #905 — Drag-to-Completed safety hatch (client-side half of #853).
// Returns true when the in-flight drag is allowed to land on the Completed
// drop zone: kind must be "plan" AND the dragged plan's frontmatter status
// must be "complete" or "landed". Non-complete plans (active, conflict,
// unknown, null) are blocked here so the drop zone never highlights and
// onDrop's existing hard-reject path stays the terminal guard. The
// server-side validator in server._validate_queue_body re-checks the
// plan's frontmatter status independently — this client guard is UI
// affordance, not the source of truth.
function isCompletedDropAllowed(dragState) {
  if (!dragState) return false;
  if (dragState.kind !== "plan") return false;
  const s = dragState.planStatus || "";
  return s === "complete" || s === "landed";
}

function onDragOver(ev) {
  const dz = ev.target.closest && ev.target.closest("ul.dropzone");
  if (!dz) return;
  if (!dragState) return;
  // Kind must match dropzone kind.
  if (dz.getAttribute("data-kind") !== dragState.kind) return;
  // Issue #905 — Completed drop zone is conditionally writable. Block
  // dragover for non-complete plans so the browser shows the no-drop
  // cursor and the existing onDrop reject path holds.
  if (dz.getAttribute("data-column") === "completed"
      && !isCompletedDropAllowed(dragState)) return;
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
  // Issue #905 — Completed drop zone refuses to highlight for non-complete
  // plans. Symmetric with the onDragOver guard above so the user never
  // sees the drop-target affordance on a drop they can't make.
  if (dz.getAttribute("data-column") === "completed"
      && !isCompletedDropAllowed(dragState)) return;
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
  // Phase 4 / W4.2 — Completed is normally read-only (terminal state
  // derived from GH closedAt / plan frontmatter — D1). Per D5 the column
  // still renders as a <ul> for visual consistency.
  //
  // Issue #905 — drag-to-Completed safety hatch (client-side half of
  // #853): a plan whose frontmatter status is `complete` or `landed` MAY
  // be dropped onto Completed (e.g. to manually unstick a card the
  // server-side override missed). For ANY other status the hard-reject
  // path below stays the terminal guard — symmetric with the highlight
  // guards in onDragOver / onDragEnter so a non-complete plan can't reach
  // here through normal UI. (Defense in depth: server.py's
  // _validate_queue_body independently re-checks the plan frontmatter
  // and rejects mismatched POSTs.)
  if (targetCol === "completed" && !isCompletedDropAllowed(dragState)) {
    console.warn(
      "Drop rejected: completed column is read-only for non-complete plans (kind=" +
      dragState.kind + ", id=" + (dragState.slug || dragState.num) +
      ", status=" + (dragState.planStatus || "<none>") + ")"
    );
    dragState = null;
    return;
  }
  // If the target column is currently collapsed, drop expands it AND
  // deposits the card — the user sees the column unfold with their card
  // inside. (Auto-expand on prolonged dragover is intentionally deferred
  // — see Step 4 of the collapsible-columns plan.)
  if (isCollapsed(dragState.kind, targetCol)) {
    setCollapsed(dragState.kind, targetCol, false);
    const colDiv = dz.closest && dz.closest(".column");
    if (colDiv) applyCollapseStateToColumn(colDiv, dragState.kind, targetCol);
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
      const name = (lab && lab.name) || lab || "";
      const color = (lab && lab.color) || "";
      if (name) {
        const chip = el("span", { cls: "label-chip", text: name });
        if (color) {
          chip.style.color = "#" + color;
          chip.style.borderColor = "#" + color;
          chip.style.background = "#" + color + "18";
        }
        labels.appendChild(chip);
      }
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
      action === "plan-discard") {
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
  if (action === "plan-discard") return discardPlan(slug);
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

  // Per-column collapse toggle (chevron at trailing edge of column-head).
  // Flips localStorage state and re-applies the .collapsed class + button
  // glyph/aria in-place — no re-render needed (the dropzone is preserved
  // beneath the head; CSS hides it via .column.collapsed > .dropzone).
  if (action === "column-collapse-toggle") {
    const col = target.getAttribute("data-column");
    const kind = target.getAttribute("data-kind");
    if (!col || !kind) return;
    const colDiv = target.closest(".column");
    if (!colDiv) return;
    const next = !isCollapsed(kind, col);
    setCollapsed(kind, col, next);
    // The button's aria-label was originally rendered with the human
    // label (e.g. "Drafted"); recover from data-column key — equivalent
    // for the columns we ship (drafted / reviewed / ready / triage /
    // backlog / completed). Cosmetic only.
    applyCollapseStateToColumn(colDiv, kind, col, target.dataset.column);
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

  // Issue #675 — Section-nav pill: scroll to the target section. If the
  // target column is collapsed, expand it first via applyCollapseStateToColumn.
  if (action === "section-nav-pill") {
    const targetId = target.getAttribute("data-target");
    const kind = target.getAttribute("data-kind");
    const col = target.getAttribute("data-column");
    const targetEl = $(targetId);
    if (!targetEl) return;
    // Expand collapsed column before scrolling.
    if (col && isCollapsed(kind, col)) {
      setCollapsed(kind, col, false);
      const colDiv = targetEl.closest(".column");
      if (colDiv) applyCollapseStateToColumn(colDiv, kind, col);
    }
    targetEl.scrollIntoView({ behavior: "smooth", block: "start" });
    return;
  }

  // Issue #717 — Branch section toggle (collapse/expand).
  if (action === "branch-section-toggle") {
    const sectionKey = target.getAttribute("data-section");
    if (!sectionKey) return;
    const secEl = target.closest(".branch-section") || document.querySelector('[data-branch-section="' + sectionKey + '"]');
    if (!secEl) return;
    const next = !isCollapsed("branch", sectionKey);
    setCollapsed("branch", sectionKey, next);
    applyBranchSectionCollapse(secEl, sectionKey);
    return;
  }

  // Issue #717 — Branch nav pill: scroll to section, expand if collapsed.
  if (action === "branch-nav-pill") {
    const targetId = target.getAttribute("data-target");
    const sectionKey = target.getAttribute("data-section");
    const targetEl = $(targetId);
    if (!targetEl) return;
    if (sectionKey && isCollapsed("branch", sectionKey)) {
      setCollapsed("branch", sectionKey, false);
      applyBranchSectionCollapse(targetEl, sectionKey);
    }
    targetEl.scrollIntoView({ behavior: "smooth", block: "start" });
    return;
  }

  // Issue #717 — Branch select-all checkbox.
  if (action === "branch-select-all") {
    const sectionKey = target.getAttribute("data-section");
    if (!sectionKey) return;
    const secEl = document.querySelector('[data-branch-section="' + sectionKey + '"]');
    if (!secEl) return;
    const checked = target.checked;
    const cbs = secEl.querySelectorAll(".branch-select-cb");
    for (let i = 0; i < cbs.length; i++) cbs[i].checked = checked;
    _updateBranchCopyCount(secEl, sectionKey);
    return;
  }

  // Issue #717 — Branch bulk copy. Emits a RUNNABLE /cleanup-merged
  // command (matching the Plans panel's "Copy and run:" pattern) rather
  // than bare branch names. The mode is driven by the section bucket.
  if (action === "branch-bulk-copy") {
    const sectionKey = target.getAttribute("data-section");
    if (!sectionKey) return;
    const secEl = document.querySelector('[data-branch-section="' + sectionKey + '"]');
    if (!secEl) return;
    const cbs = secEl.querySelectorAll(".branch-select-cb:checked");
    const names = [];
    for (let i = 0; i < cbs.length; i++) {
      // Defensive: never include a config-protected branch in the command,
      // even if its checkbox somehow got selected. /cleanup-merged would
      // skip it anyway, but emitting it would be misleading.
      if (cbs[i].getAttribute("data-protected") === "true") continue;
      const n = cbs[i].getAttribute("data-branch-name");
      if (n) names.push(n);
    }
    if (!names.length) {
      showToast("No branches selected.", "info");
      return;
    }
    const cmd = buildCleanupMergedCommand(sectionKey, names);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      try {
        navigator.clipboard.writeText(cmd);
        showToast("Copied command for " + names.length + " branch" + (names.length === 1 ? "" : "es") + ".", "info");
      } catch (_err) {
        showToast("Copy failed — select text manually.", "err");
      }
    } else {
      showToast("Clipboard API unavailable.", "err");
    }
    return;
  }
}

// Issue #717 follow-up — Build the runnable /cleanup-merged command for a
// branch-section bulk copy. The mode is driven by the section bucket: the
// `remote-only` bucket targets remote branches; the local buckets
// (active / landed / local) target local branches. The bulk bar is
// per-section, so each invocation only ever produces one mode.
function buildCleanupMergedCommand(sectionKey, names) {
  const mode = sectionKey === "remote-only" ? "remote" : "local";
  return "/cleanup-merged " + mode + " apply " + names.join(" ");
}

// Issue #717 — Update the copy button label with the count of selected branches.
function _updateBranchCopyCount(secEl, sectionKey) {
  const cbs = secEl.querySelectorAll(".branch-select-cb:checked");
  const btn = secEl.querySelector('.branch-bulk-copy-btn[data-section="' + sectionKey + '"]');
  if (btn) {
    btn.textContent = "Copy /cleanup-merged for " + cbs.length + " branch" + (cbs.length === 1 ? "" : "es");
  }
}

function bindActionEvents() {
  document.body.addEventListener("click", (ev) => {
    const target = ev.target.closest && ev.target.closest("[data-action]");
    if (!target) return;
    const action = target.getAttribute("data-action");
    if (!action) return;
    // Checkbox actions (e.g. branch-select-all) are driven via the `change`
    // listener below. Calling preventDefault() here would cancel the
    // checkbox's own toggle, so it would drive children but never show its
    // own check. Let the native toggle happen and skip the click path.
    if (target.tagName === "INPUT" && target.type === "checkbox") return;
    ev.preventDefault();
    handleAction(action, target);
  });

  // Issue #676 — Completed-window dropdown change handler. `<select>`
  // elements fire `change`, not `click`, so the delegated click handler
  // above cannot catch them. Bind once at the document level.
  document.body.addEventListener("change", (ev) => {
    const select = ev.target.closest && ev.target.closest(".completed-window-select");
    if (!select) return;
    const kind = select.getAttribute("data-kind");
    const value = select.value;
    setCompletedWindow(kind, value);
    // Force re-render — clear the panel fingerprint so the next
    // applySnapshot re-renders with the new filter applied.
    if (kind === "plan") lastFingerprint.plans = null;
    if (kind === "issue") lastFingerprint.issues = null;
    // Trigger an immediate poll so the UI updates now.
    schedulePoll(0);
  });

  // Issue #717 — Branch checkbox change handler. Updates per-section copy
  // count when individual branch checkboxes are toggled.
  document.body.addEventListener("change", (ev) => {
    const cb = ev.target.closest && ev.target.closest(".branch-select-cb");
    if (!cb) return;
    const secEl = cb.closest(".branch-section");
    if (!secEl) return;
    const sectionKey = secEl.getAttribute("data-branch-section");
    if (sectionKey) _updateBranchCopyCount(secEl, sectionKey);
  });

  // Select-all checkbox change handler. Routed through `change` (not the
  // delegated click path) so the checkbox's own checked state toggles
  // natively before we fan the state out to the per-row checkboxes.
  document.body.addEventListener("change", (ev) => {
    const sa = ev.target.closest && ev.target.closest('[data-action="branch-select-all"]');
    if (!sa) return;
    handleAction("branch-select-all", sa);
  });

  // Branch card body click → toggle its selection checkbox. The whole card
  // reads as clickable (pointer cursor) but only had a working name-link
  // before, so clicking anywhere else now selects the branch. The checkbox
  // itself and the name-link opt out so they keep their native behavior.
  document.body.addEventListener("click", (ev) => {
    const card = ev.target.closest && ev.target.closest('.card[data-kind="branch"]');
    if (!card) return;
    if (ev.target.closest("input, a, button")) return;
    const cb = card.querySelector(".branch-select-cb");
    if (!cb) return;
    cb.checked = !cb.checked;
    cb.dispatchEvent(new Event("change", { bubbles: true }));
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
  // Issue #802 — opening a tab marks it seen: snapshot its current
  // fingerprint into lastViewed and re-render dots so this tab clears.
  // currentTabFingerprint[slug] may still be null pre-first-snapshot; that
  // is fine (a null baseline never dots until the first snapshot seeds it).
  activeTab = slug;
  if (typeof currentTabFingerprint !== "undefined" &&
      currentTabFingerprint[slug] !== null) {
    lastViewed[slug] = currentTabFingerprint[slug];
  }
  if (typeof updateTabDots === "function") updateTabDots();
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

  // Persist activity-strip resize height across reloads.
  var actStrip = document.getElementById("activity-strip");
  if (actStrip) {
    var savedH = localStorage.getItem("zskills:dashboard:activity-height");
    if (savedH) actStrip.style.height = savedH;
    if (typeof ResizeObserver !== "undefined") {
      new ResizeObserver(function() {
        localStorage.setItem("zskills:dashboard:activity-height", actStrip.style.height || (actStrip.offsetHeight + "px"));
      }).observe(actStrip);
    }
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot);
} else {
  boot();
}
