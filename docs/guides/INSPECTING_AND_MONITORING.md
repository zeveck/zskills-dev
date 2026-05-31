# Inspecting & Monitoring a zskills Project

> **Audience:** anyone driving or observing a zskills-managed repo who wants to
> answer *"what is the system doing, what has it done, and what's stuck?"* —
> without reading git history by hand.
>
> **Scope:** this is the **operator/observer** guide. For the enforcement
> mechanics (how hooks gate commits) see
> [`ZSKILLS_TRACKING_OVERVIEW.md`](ZSKILLS_TRACKING_OVERVIEW.md); for the
> marker naming scheme see
> [`docs/tracking/TRACKING_NAMING.md`](../tracking/TRACKING_NAMING.md).

## You don't need an agent to watch zskills

Everything zskills records is a **plain-text file or a web page a human can
read directly**. The skills and hooks below are conveniences over that data —
they don't own it. Two consequences worth internalizing up front:

- **The dashboard is for you.** `/zskills-dashboard` serves a normal web UI in
  your browser — open it and click around; you don't need Claude in the loop to
  read plans, issues, worktrees, and tracking activity.
- **The trackers are a human-auditable trail.** Every claim, step, and
  completion marker is a small text file under `.zskills/`. You can verify what
  a pipeline actually did — phase by phase — with `ls`, `cat`, and `grep`
  yourself. The hooks read the same files to *enforce*; nothing stops you from
  reading them to *audit*. No skill invocation required.

## The mental model: live state vs. durable record

zskills leaves two kinds of trail, and most confusion comes from conflating
them:

| | **Live state** (what's happening *now*) | **Durable record** (what *happened*) |
|---|---|---|
| **Where** | `.zskills/claims/`, `current_phase` chips, crons, `.landed` | `fulfilled.*` markers, plan reports, git history |
| **Lifetime** | exists only while a pipeline is in-flight; released/removed at completion | persists across runs; survives `clear-tracking.sh` |
| **Answers** | "is anything running? is it stuck?" | "what has this project ever shipped, by which skill, when?" |
| **Inspect with** | `/briefing`, dashboard, `ls .zskills/claims` | `fulfilled.*` queries, `/session-report`, `docs/reports/` |

Everything below is one of these two lenses.

---

## 1. The four inspection skills

These are the high-level, human-friendly views. Reach for these first; drop to
the raw files (sections 2–4) when you want to verify them or go deeper.

| Skill | Shows | Reach for it when |
|-------|-------|-------------------|
| `/briefing` | worktree status, open checkboxes, recent commits | "where does the project stand right now?" |
| `/plans` | every plan's status + the next ready plan | "what plan should run next / what's blocked?" |
| `/zskills-dashboard` | local web UI: plans, issues, worktrees, branches, tracking activity, drag-and-drop priority queue | you want a live, clickable overview |
| `/session-report` | what **this session** said it would do vs. what actually shipped (verified against git/PRs/plans, not memory) | "did I actually land everything I claimed this session?" |

### `/briefing` — project status, with modes & a period window

The default at-a-glance view: recent commits, open checkboxes, worktree state.
It takes a mode and (for `report`) a time window:

```text
/briefing                # summary (default)
/briefing report 24h     # fuller report over a time window (1h|6h|24h|2d|7d)
/briefing verify         # verify recent changes hold up
/briefing current        # what's in flight
/briefing worktrees      # worktree inventory
/briefing every 6h       # schedule a recurring briefing (stop / next manage it)
```

### `/plans` — the plan queue

The in-terminal plan view: every plan's status and **the next ready plan to
run** (dependencies satisfied, not blocked, not already in flight). This is the
"what should happen next?" lens — the dashboard (below) is its clickable
web equivalent.

```text
/plans            # status of every plan + the next ready one
/plans details    # per-plan detail
/plans next       # just the next ready plan
/plans rebuild    # regenerate the plan index
```

**Two read-only queue lenses sit side by side.** `/plans` shows the *status of
every plan*; `/work-on-plans` (with no args) lists the *prioritized ready
queue* — the dashboard's drag-and-drop order, read from
`.zskills/monitor-state.json` (`plans.ready`) — and `/work-on-plans next` shows
whether a recurring batch run is scheduled. Both are read-only **until** you
hand them an action: `/plans rebuild` regenerates the index;
`/work-on-plans N|all [finish]` dispatches `/run-plan` per queued plan (the
execution mode — the bug-side analogue is `/fix-issues`).

### `/zskills-dashboard` — the browser view

Starts a detached local web server (Python `http`, port from `DEV_PORT` /
`dev_server.default_port` / `port.sh`) reading `.zskills/monitor-state.json`:

```text
/zskills-dashboard start | stop | status | restart
```

Then open `http://localhost:<port>` in your browser — a human-readable page
(plans, issues, worktrees, branches, tracking activity, a drag-and-drop
priority queue). `restart` = stop+start (use after code changes). Leave it
running and refresh to watch a pipeline progress without asking the agent
anything.

![The zskills dashboard: plan columns (Drafted/Proposed/Accepted/…), per-plan status chips and phase progress, the Recent-activity feed, and the `/work-on-plans` copy-and-run line.](assets/zskills-dashboard.png)

> **Try it live:** an interactive, browser-only demo of this dashboard runs at
> **<https://zeveck.github.io/zskills-dev/demo/>** — drop plans into *Accepted*
> (and issues into *Ready*) and watch them get worked, with the activity feed
> and run-status chips updating live. *(The screenshot above is from that demo;
> its plan names are illustrative placeholders.)*

### `/session-report` — the honesty check

Reconciles what **this session** *said* it would do against what actually
shipped — verified against **ground truth** (git, PRs, plans, worktrees), not
conversation memory. It takes no arguments; you run it at the end of a working
session. It catches the two failure modes memory can't: "I thought I shipped X
but the PR never merged," and "I did finish Y — in another session." Use it
before you trust a session's own summary of itself.

---

## 2. Tracking markers as an audit ledger

`.zskills/tracking/<pipeline-id>/` holds the markers the enforcement hooks use
(`requires.*`, `step.*`) **and** the durable completion records (`fulfilled.*`).
The audit value lives almost entirely in the `fulfilled.*` set — and, again,
these are plain files you can read yourself to verify any claim a skill makes.

### The marker families

| Family | Role | Lifetime |
|--------|------|----------|
| `requires.<skill>.<id>` | a declared obligation ("this skill must run before landing") | transient — cleared by `clear-tracking.sh` |
| `step.<skill>.<id>.<stage>` | progress within a pipeline (`implement` / `verify` / `report` / `land`) | transient |
| `fulfilled.<skill>.<id>` | **a completion record** — one per invocation that landed work | **durable** — preserved by `clear-tracking.sh` |

`clear-tracking.sh` is built around exactly this distinction: it **preserves**
`fulfilled.{run-plan,land-pr,commit,do,fix-issues,quickfix}.*` (the history)
and clears everything else (the in-flight scaffolding). So after cleanup, the
tracking dir *is* the completion ledger.

### What a completion record contains

```text
# fulfilled.run-plan.<plan-slug>
skill: run-plan
id: claim-work-item
plan: docs/plans/claim-work-item.md
phase: 4
status: complete
date: 2026-05-30T01:14:24-04:00

# fulfilled.land-pr.<id>
skill: land-pr
id: claim-work-item
pr: https://github.com/<org>/<repo>/pull/825
branch: feat/claim-work-item
date: 2026-05-30T01:14:23-04:00
```

That's enough to answer "which plan, which phase, landed via which PR, when" —
no git archaeology required.

### Verifying a pipeline's steps by hand

You can reconstruct exactly what a pipeline did, in order, without invoking
anything — the `step.*` markers are the per-stage breadcrumbs (present until
`clear-tracking.sh` sweeps them), and the `fulfilled.*` records are the final
word:

```bash
T=.zskills/tracking

# Walk one pipeline's steps in order (implement → verify → report → land):
ls -1 "$T"/run-plan.<plan-slug>/step.* 2>/dev/null
cat   "$T"/run-plan.<plan-slug>/step.run-plan.<plan-slug>.verify   # has result: pass

# Confirm it actually completed and landed:
cat "$T"/run-plan.<plan-slug>/fulfilled.run-plan.<plan-slug>      # status: complete
cat "$T"/run-plan.<plan-slug>/fulfilled.land-pr.<plan-slug>       # pr + date
```

### Audit recipes

```bash
T=.zskills/tracking

# Everything this project has ever landed, by skill:
find "$T" -name 'fulfilled.run-plan.*'   | wc -l   # plans completed via /run-plan
find "$T" -name 'fulfilled.land-pr.*'     | wc -l   # PRs landed via /land-pr
find "$T" -name 'fulfilled.fix-issues.*'  | wc -l   # issues resolved via /fix-issues

# Which plans actually reached "complete" (not just "started"):
grep -rl 'status: complete' "$T"/*/fulfilled.run-plan.* | wc -l

# Stalled work — a declared requirement with no matching fulfillment
# (a pipeline that started but never finished its obligation):
for r in "$T"/*/requires.*; do
  f="${r/requires./fulfilled.}"
  [ -e "$f" ] || echo "UNFULFILLED: $r"
done
```

(See `ZSKILLS_TRACKING_OVERVIEW.md` for how the hooks turn an unfulfilled
`requires.*` into a commit/push **block** — the same signal you can read by
hand here, enforced automatically there.)

---

## 3. Claims — what's running *right now*

A pipeline claims a work-item before working it (issue **or** plan) so two
pipelines never double-work the same thing. The claim is the single best
signal of "is something in flight?"

```bash
# What is in flight this moment:
ls -d .zskills/claims/*/                       # plan-<slug>/ and issue-<N>/ dirs
cat .zskills/claims/plan-<slug>/claim.json     # pipeline_id, current_phase, started_at
```

A claim's `current_phase` field is the live progress pointer (e.g.
`"Phase 3 — verified"`) — `cat` it again later to watch a run advance. Claims
are **acquire-on-pickup / release-on-resolve** with **no TTL** — a lingering
claim after a crash is the accepted cost of never killing a long-running agent
mid-work. They are ownership-aware: a pipeline re-acquiring its **own** claim
succeeds (it is not a collision). To clear a genuinely stale claim by hand:

```bash
bash skills/run-plan/scripts/claim-plan.sh release <slug> --require-pipeline <pid>
# issues: skills/fix-issues/scripts/claim-issue.sh release <N> --require-pipeline <pid>
```

---

## 4. `.landed` — per-worktree landing state

When a pipeline lands work it writes a `.landed` marker in the worktree. It is
**not** a tracking marker — it is worktree-state, and it's the fastest way to
tell whether a leftover worktree is safe to remove.

```bash
cat <worktree>/.landed
```

| `status:` | meaning |
|-----------|---------|
| `landed` | merged/cherry-picked to main — safe to remove |
| `pr-ready` | PR open, CI green, awaiting review |
| `pr-ci-failing` | PR open, CI failing after fix attempts |
| `conflict` / `pr-failed` | needs manual intervention |
| `not-landed` | agent finished without landing |

If a worktree has no `.landed`, verify manually before removing
(`git log main..<branch>`, `git status`). See the Worktree Rules in
`CLAUDE.md`.

---

## 5. Plan reports — the human-readable narrative

For prose detail (per-phase work items, verification results, sign-off items),
read the generated reports rather than the markers:

```text
docs/reports/plan-<slug>.md   # per-plan, newest phase prepended at the top
docs/reports/SPRINT_REPORT.md # /fix-issues sprint outcomes
<audit-dir>/PLAN_REPORT.md    # regenerated index across all plan reports
```

(Paths are config-resolved via `output.reports_dir`; this project uses
`docs/reports/`.) Each `/run-plan` phase prepends a section with status,
commit, work-item table, and verification tally — so the report is a
phase-by-phase audit trail in plain English, complementary to the machine
markers in section 2.

---

## 6. Monitoring a *running* pipeline

A long `finish auto` run leaves several live signals you can watch (refresh the
dashboard, or `cat` the files):

- **Claim `current_phase`** — `cat .zskills/claims/plan-<slug>/claim.json`
  updates as phases advance (`implemented` → `verified` → `reported`).
- **Dashboard activity** — `/zskills-dashboard` surfaces tracking activity and
  the execution-mode chip (queued / phase-N / finish / locked).
- **Defer counters** — `.zskills/tracking/<pid>/in-progress-defers.<phase>`
  shows how many times a chunked cron fire has deferred while a phase is in
  flight (the adaptive-backoff counter; see `ADAPTIVE_CRON_BACKOFF.md`).
- **The cron itself** — a `finish auto` run schedules a recurring `*/1` cron;
  `/run-plan <plan> status` shows phase progress, `/run-plan <plan> next` shows
  the next fire, `/run-plan stop` cancels it (and releases run-plan-held claims).

---

## 7. Cheat sheet

```bash
# --- live: what's running now ---
ls -d .zskills/claims/*/                                  # in-flight claims
git worktree list                                          # active worktrees
for w in $(git worktree list --porcelain | awk '/^worktree /{print $2}'); do
  [ -f "$w/.landed" ] && echo "$w: $(grep '^status:' "$w/.landed")"
done                                                       # landing state per worktree

# --- durable: what happened (audit by hand) ---
find .zskills/tracking -name 'fulfilled.*' | wc -l         # total completion records
grep -rl 'status: complete' .zskills/tracking/*/fulfilled.run-plan.*   # plans completed
ls docs/reports/plan-*.md                                  # per-plan narratives

# --- high-level views ---
/briefing                # project status
/plans                   # plan dashboard
/zskills-dashboard start # web UI (then open http://localhost:<port> in a browser)
/session-report          # this-session audit
```

**Housekeeping:** `bash skills/update-zskills/scripts/clear-tracking.sh` sweeps
the transient `requires.*` / `step.*` scaffolding and **preserves the
`fulfilled.*` completion ledger** — run it when the marker count grows large;
your audit history is never touched.

---

## See also

- [`ZSKILLS_TRACKING_OVERVIEW.md`](ZSKILLS_TRACKING_OVERVIEW.md) — the
  enforcement model: how markers gate commits, with worked examples and a
  troubleshooting section.
- [`docs/tracking/TRACKING_NAMING.md`](../tracking/TRACKING_NAMING.md) — the
  authoritative marker naming scheme, delegation semantics, and `.landed`
  semantics.
- [`docs/guides/WORKFLOWS.md`](WORKFLOWS.md) — end-to-end workflows (§11 is the short
  Status & monitoring index this doc expands on).
