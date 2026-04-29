// Z Skills Monitor — read-only dashboard renderer (Phase 6).
//
// Loaded as a single ES module from /app.js. Polls /api/state every 2s
// via setTimeout recursion (NOT setInterval), pauses while document is
// hidden, and force-loads on visibilitychange. Per-panel diff detection
// so unchanged panels are not re-rendered. All user-authored content
// rendered via textContent / appendChild — no innerHTML except for
// hardcoded chrome marked `// chrome-only`.

const POLL_INTERVAL_MS = 2000;
const STATE_URL = "/api/state";

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

// --------------------------------------------------------------- snapshot

let lastSnapshot = null;
const lastFingerprint = {
  errors: null,
  plans: null,
  branches: null,
  worktrees: null,
  issues: null,
  activity: null,
};
let pollTimer = null;
let pollAbort = null;

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

function schedulePoll(delay) {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = setTimeout(pollOnce, delay);
}

async function pollOnce() {
  if (document.hidden) {
    // Pause while tab hidden; visibilitychange handler restarts.
    pollTimer = null;
    return;
  }
  const snap = await fetchState();
  if (snap) {
    lastSnapshot = snap;
    applySnapshot(snap);
  }
  schedulePoll(POLL_INTERVAL_MS);
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

  const plansFp = fingerprintPlans(snap.plans || []);
  if (plansFp !== lastFingerprint.plans) {
    lastFingerprint.plans = plansFp;
    renderPlans(snap.plans || []);
  }

  const branchesFp = fingerprintBranches(snap.branches || [], snap.worktrees || []);
  if (branchesFp !== lastFingerprint.branches) {
    lastFingerprint.branches = branchesFp;
    renderBranches(snap.branches || [], snap.worktrees || []);
  }

  const issuesFp = fingerprintIssues(snap.issues || []);
  if (issuesFp !== lastFingerprint.issues) {
    lastFingerprint.issues = issuesFp;
    renderIssues(snap.issues || []);
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

function fingerprintPlans(plans) {
  return JSON.stringify(plans.map(p => [
    p.slug, p.title, p.status, p.landing_mode, p.phase_count, p.phases_done, p.blurb,
  ]));
}

function fingerprintBranches(branches, worktrees) {
  const wtSet = backedBranchSet(worktrees);
  return JSON.stringify(branches.map(b => [
    b.name, b.last_commit_at, b.last_commit_subject, b.upstream, wtSet.has(b.name),
  ]));
}

function fingerprintIssues(issues) {
  return JSON.stringify(issues.map(i => [
    i.number, i.title, (i.labels || []).slice().sort(), i.created_at,
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

function renderPlans(plans) {
  const body = $("plans-body");
  const empty = $("plans-empty");
  clear(body);
  if (!plans.length) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  for (const p of plans) {
    const card = el("article", {
      cls: "card",
      attrs: {
        tabindex: "0",
        role: "button",
        "data-kind": "plan",
        "data-slug": p.slug,
        "aria-label": "Plan " + (p.title || p.slug),
      },
    });
    const head = el("div", { cls: "card-row" });
    head.appendChild(el("span", { cls: "card-title", text: p.title || p.slug }));
    const statusPill = el("span", {
      cls: "pill " + statusPillClass(p.status),
      text: p.status || "active",
    });
    head.appendChild(statusPill);
    card.appendChild(head);

    if (p.blurb) {
      card.appendChild(el("div", { cls: "card-blurb", text: p.blurb }));
    }

    const meta = el("div", { cls: "card-row card-sub" });
    const ratio = (p.phases_done || 0) + " / " + (p.phase_count || 0) + " phases";
    meta.appendChild(el("span", { text: ratio }));
    const modePill = el("span", {
      cls: "pill " + modePillClass(p.landing_mode),
      text: "mode: " + (p.landing_mode || "unknown"),
    });
    meta.appendChild(modePill);
    card.appendChild(meta);

    const total = p.phase_count || 0;
    const done = p.phases_done || 0;
    if (total > 0) {
      const bar = el("div", { cls: "progress" });
      const fill = el("div", { cls: "progress-fill" });
      const pct = Math.max(0, Math.min(100, Math.round((done / total) * 100)));
      fill.style.width = pct + "%";
      bar.appendChild(fill);
      card.appendChild(bar);
    }

    body.appendChild(card);
  }
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

function renderIssues(issues) {
  const body = $("issues-body");
  const empty = $("issues-empty");
  clear(body);
  if (!issues.length) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  for (const it of issues) {
    const card = el("article", {
      cls: "card",
      attrs: {
        tabindex: "0",
        role: "button",
        "data-kind": "issue",
        "data-number": String(it.number),
        "aria-label": "Issue #" + it.number,
      },
    });
    const head = el("div", { cls: "card-row" });
    head.appendChild(el("span", { cls: "card-title", text: "#" + it.number + " " + (it.title || "") }));
    if (it.created_at) {
      head.appendChild(el("span", { cls: "card-sub", text: relativeTime(it.created_at) }));
    }
    card.appendChild(head);
    if ((it.labels || []).length) {
      const labels = el("div", { cls: "card-sub" });
      for (const lab of it.labels) {
        labels.appendChild(el("span", { cls: "label-chip", text: lab }));
      }
      card.appendChild(labels);
    }
    body.appendChild(card);
  }
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
  // Newest first (collect.py already sorts) — cap at 20.
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
  // Focus the close button so Esc/Tab work immediately.
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

  // Phase list
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

  // Report path (display-only)
  if (plan.report_path) {
    const rp = el("section");
    rp.appendChild(el("h3", { text: "Report" }));
    rp.appendChild(el("p", { cls: "mono", text: plan.report_path }));
    modal.body.appendChild(rp);
  }

  // Work-item checkboxes (display-only): rebuild from sub_plans + report
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

// --------------------------------------------------------- card dispatch

function onCardActivate(card) {
  const kind = card.getAttribute("data-kind");
  if (kind === "plan") {
    openPlanModal(card.getAttribute("data-slug"));
  } else if (kind === "issue") {
    openIssueModal(card.getAttribute("data-number"));
  }
  // worktree / branch cards are display-only in Phase 6.
}

function bindCardEvents() {
  document.body.addEventListener("dblclick", (ev) => {
    const card = ev.target.closest(".card");
    if (!card) return;
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

// ------------------------------------------------------- visibility / boot

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    // Force-load on becoming visible.
    schedulePoll(0);
  }
});

function boot() {
  modalInit();
  bindCardEvents();
  schedulePoll(0);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot);
} else {
  boot();
}
