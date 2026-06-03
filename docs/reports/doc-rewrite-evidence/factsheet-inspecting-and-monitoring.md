# Fact sheet — `docs/guides/inspecting-and-monitoring.md`

Every factual claim in the rewritten guide, paired with the verbatim source
line that backs it. Format: `doc sentence → <source>:LINE: "<verbatim quote>"`.

This is a **light-touch** rewrite. A prior assessment rated the guide GOOD for
its "live state vs. durable record" framing — that table and its mental model
are preserved verbatim-in-substance. The rewrite strips the operator/consultant
voice the audit flagged ("Two read-only queue lenses sit side by side", the
"Audit recipes" framing, "human-auditable trail", the internal
`in-progress-defers.<phase>` marker path, the `ADAPTIVE_CRON_BACKOFF.md`
internal reference) into plain user prose, and corrects one factual error
(see R1 note).

## R5 note — banned-term check

`grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/guides/inspecting-and-monitoring.md`
returns exactly ONE line: the `current_phase` value sentence quoting
`"Phase 0 — acquired"`, `"Phase 1"`, `"Phase 2"`. `Phase [0-9]` is on the
banned list, but R5 permits a term the **user observably encounters** — and
`current_phase` is a field the user `cat`s directly out of `claim.json`, so
quoting its real values is the documented R5 exception, not implementer voice.
The prior version carried the same field but with a *fabricated* value
(`"Phase 3 — verified"`, R1-failing); the rewrite quotes the **actual** values
the code writes.

Internal-voice terms removed (not in banned-terms.txt but R5-governed):
"operator/observer guide", "human-auditable trail", "Two read-only queue
lenses sit side by side", "Audit recipes", "the adaptive-backoff counter",
`in-progress-defers.<phase>`, `ADAPTIVE_CRON_BACKOFF.md`, "machine markers"
softened to "machine markers"/"by hand".

## R1 note — the one factual correction

The prior doc said the live progress pointer reads e.g. `"Phase 3 — verified"`
and advances `implemented → verified → reported`. The code does NOT write those
strings. `set-phase` writes `"Phase $PHASE"` (e.g. `"Phase 3"`), and the
acquire-time value is `"Phase 0 — acquired"`:

- skills/run-plan/SKILL.md:1167: `set-phase "$PLAN_SLUG" --require-pipeline "$PIPELINE_ID" --current-phase "Phase $PHASE" || true`
- skills/run-plan/scripts/claim-plan.sh:301: `"current_phase":      "Phase 0 — acquired",`

The rewrite corrects this to the actual values.

## Content LEFT for #1002 (carve-out — not rewritten)

Per the #1002 carve-out, the dev-vs-prod URL content and the consumer-install-path
content (`skills/.../claim-*.sh` source-path vs `.claude/skills/...`) were left
as-is:

- The release-command bash block (Section 3) keeps the **source-tree** paths
  `skills/run-plan/scripts/claim-plan.sh` and
  `skills/fix-issues/scripts/claim-issue.sh` unchanged — these are the
  source-path-vs-`.claude/skills/...` content #1002 owns.
- The `clear-tracking.sh` housekeeping path (Section 7 + the cheat sheet)
  keeps `skills/update-zskills/scripts/clear-tracking.sh` unchanged — same
  source-install-path territory.
- The live-demo URL (`http://zskills.synapticnoise.com/demo/`) and the
  `localhost`/printed-URL phrasing are dev-vs-prod URL content; left untouched
  (the one place I touched URL phrasing was Section 1 / cheat sheet, replacing
  the bare `http://localhost:<port>` *instruction* with "the printed URL" —
  that is prose phrasing, not the dev-vs-prod URL *content*; the demo URL row
  is verbatim).

---

## Section 0 — Audience / scope blockquote

- This guide covers the views and files you read to observe a project →
  current behavior; descriptive framing, no single source line (it is the
  guide's own scope statement, re-derived from the sections below).

- For how hooks gate commits see `tracking-overview.md`; for the marker naming
  scheme see `docs/tracking/TRACKING_NAMING.md` →
  docs/tracking/TRACKING_NAMING.md:1: "# Tracking Marker Naming — Design Doc"
  (cross-doc reference; `tracking-overview.md` exists in docs/guides/)

## Section "You don't need an agent to watch zskills"

- Everything zskills records is a plain-text file or a web page →
  skills/zskills-dashboard/SKILL.md:6: "Local web dashboard — plans, issues, worktrees, branches, tracking"
  docs/tracking/TRACKING_NAMING.md:44: "Markers live in `.zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*`."

- The dashboard serves a normal web UI you open in your browser →
  skills/zskills-dashboard/SKILL.md:355: "echo \"Dashboard running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)\""

- Every claim, step, and completion marker is a small text file under
  `.zskills/` →
  docs/tracking/TRACKING_NAMING.md:44: "Markers live in `.zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*`."

- The hooks read the same files to decide whether a commit is allowed →
  docs/tracking/TRACKING_NAMING.md:11-14: "The reader (the commit-blocking hook) applies a PIPELINE_ID scope filter to tracking markers at nine sites"

## Section "The mental model: live state vs. durable record"

(Preserved table — rated GOOD by prior assessment. Cell-by-cell backing:)

- Live state lives in `.zskills/claims/`, `current_phase`, crons, `.landed` →
  skills/run-plan/scripts/claim-plan.sh:53: "{schema_version, kind, slug, pipeline_id, started_at, current_phase"
  docs/tracking/TRACKING_NAMING.md:232: "**Decision: `.landed` is NOT a tracking marker.**"

- Durable record lives in `fulfilled.*` markers, plan reports, git history →
  docs/tracking/TRACKING_NAMING.md:142 (Phase 4 layout) / clear-tracking preserves fulfilled.* →
  skills/update-zskills/scripts/clear-tracking.sh:2: "# Clear skill tracking bookkeeping. Preserves fulfilled.run-plan.*"

- Live state exists only while a pipeline is in flight; released when it
  finishes →
  skills/run-plan/scripts/claim-plan.sh:70-72: "the operator runs `claim-plan.sh release <slug> --require-pipeline <stored-id>` explicitly. No automated TTL-based"

- Durable record persists across runs; survives cleanup →
  skills/update-zskills/scripts/clear-tracking.sh:23: "Clears .zskills/tracking/* EXCEPT fulfilled.run-plan.* (completion history)."

## Section 1 — The four inspection skills

### `/briefing`

- Modes: summary (default), report, verify, current, worktrees; report takes a
  period 1h|6h|24h|2d|7d →
  skills/briefing/SKILL.md:6: "Modes: summary (default), report, verify, current, worktrees. Period: 1h, 6h, 24h, 2d, 7d."
  skills/briefing/SKILL.md:3: "argument-hint: \"[report [period]] | verify | current | worktrees | [summary] | stop | next\""

- `summary` is the default →
  skills/briefing/SKILL.md:29: "$ARGUMENTS = \"\"              → mode: summary"

- `report` defaults to a 24h window →
  skills/briefing/SKILL.md:31: "$ARGUMENTS = \"report\"        → mode: report, period: 24h"

- `every <SCHEDULE>` runs a recurring briefing →
  skills/briefing/SKILL.md:43: "**Schedule detection:** If `$ARGUMENTS` contains `every <SCHEDULE>`, strip the schedule"

### `/plans`

- Every plan's status + the next ready plan; read-only views are status / next
  / details / rebuild →
  skills/plans/SKILL.md:6: "Plan dashboard. View plan status, find the next ready plan. For batch"
  skills/plans/SKILL.md:20: "- **rebuild** `/plans rebuild` — scan all plans, classify, regenerate"
  skills/plans/SKILL.md:21: "- **next** `/plans next` — show the highest-priority ready-to-run plan with command"
  skills/plans/SKILL.md:22: "- **details** `/plans details` — show every plan with a one-line description"

- `/plans` is read-only; `/work-on-plans` runs the prioritized queue (the
  drag-order from the dashboard) via `/run-plan` per entry; default is one PR
  per plan; `phase` runs one phase at a time →
  skills/work-on-plans/SKILL.md:6-8: "Batch-execute the prioritized ready queue from the dashboard: reads .zskills/monitor-state.json (plans.ready) and dispatches /run-plan auto per entry (mode resolves to `finish` by default; `phase` opts out),"
  skills/work-on-plans/SKILL.md:27: "**Default mode is `finish`** (post-#988): with no token, no per-plan"

### `/zskills-dashboard`

- Starts a local web server in the background; start/stop/status/restart →
  skills/zskills-dashboard/SKILL.md:4: "argument-hint: \"[start|stop|status|restart]\""
  skills/zskills-dashboard/SKILL.md:18: "first-class skill. It launches the server detached (so it survives the"

- `start` prints the URL →
  skills/zskills-dashboard/SKILL.md:355: "echo \"Dashboard running at http://127.0.0.1:$PORT/  (pid ${NEW_PID:-?}, log $LOG_FILE)\""

- Shows plans, issues, worktrees, branches, tracking activity, a drag-and-drop
  priority queue →
  skills/zskills-dashboard/SKILL.md:6: "Local web dashboard — plans, issues, worktrees, branches, tracking"
  skills/zskills-dashboard/SKILL.md:7: "activity, drag-and-drop priority queue. Starts a detached Python HTTP"

- `restart` is stop-then-start, to pick up code changes →
  skills/zskills-dashboard/SKILL.md:35: "/zskills-dashboard restart  # stop then start (pick up Python changes)"
  skills/zskills-dashboard/SKILL.md:546: "to take effect. Use `restart` to pick up Python source changes without"

- Live demo at zskills.synapticnoise.com/demo/ → **#1002 carve-out content,
  left as-is** (dev-vs-prod URL); not re-verified per the carve-out.

### `/session-report`

- Reconciles what this session said vs. what shipped, checked against git,
  PRs, plans, worktrees, not memory →
  skills/session-report/SKILL.md:6: "Verifies session-mentioned items against ground truth (git, PRs, plans,"
  skills/session-report/SKILL.md:81: "already handles it — `git status` / `gh pr view` is ground truth regardless"

- CI / merged-PR is ground truth for "shipped" →
  skills/session-report/SKILL.md:143: "- **CI is ground truth for \"shipped.\" A merged PR with no main commit, or"

## Section 2 — Tracking markers as a record of what happened

- Tracking dir holds requires.* / step.* (gating) + fulfilled.* (durable) →
  docs/tracking/TRACKING_NAMING.md:44: "Markers live in `.zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*`."
  docs/tracking/TRACKING_NAMING.md:454: "The hook enforces `requires.*`, `fulfilled.*`, and `step.*` only."

- `step.*` stages are implement / verify / report / land →
  docs/tracking/TRACKING_NAMING.md:412-415: "step.phase2.implement … step.phase2.verify … step.phase2.report"
  skills/run-plan/SKILL.md:1162: "requires.land-pr.$TRACKING_ID" (land stage exists)

- `fulfilled.<skill>.<id>` is a completion record, one per landed invocation,
  durable / kept on cleanup →
  skills/update-zskills/scripts/clear-tracking.sh:2: "# Clear skill tracking bookkeeping. Preserves fulfilled.run-plan.*"

- Cleanup keeps fulfilled.* for run-plan / land-pr / commit / do / fix-issues /
  quickfix and clears the rest →
  skills/update-zskills/scripts/clear-tracking.sh:49: "    fulfilled.run-plan.*|fulfilled.land-pr.*|fulfilled.commit.*|fulfilled.do.*|fulfilled.fix-issues.*|fulfilled.quickfix.*)"

- Completion record contents (skill / id / plan / phase / status / date; land-pr
  has pr + branch) →
  skills/run-plan/SKILL.md:1160-1162: "printf 'skill: land-pr\\nparent: run-plan\\nid: %s\\nbranch: %s\\ndate: %s\\n'"
  (the fulfilled.run-plan body shape is the example in the prior doc, matching
  the marker fields written across run-plan; representative, not literal-quoted)

- A requires.* with no matching fulfilled.* = work declared but never completed;
  the hooks turn the same thing into a commit/push block →
  docs/tracking/TRACKING_NAMING.md:11-14: "The reader (the commit-blocking hook) applies a PIPELINE_ID scope filter to tracking markers"
  (and the prior doc's loop; tracking-overview.md carries the enforcement detail)

## Section 3 — Claims

- A pipeline claims a work item (issue or plan) before working it so two
  pipelines never double-work the same thing →
  CLAUDE.md "Claiming work items": "Claim any tracked work-item (issue or plan) before working it"
  docs/tracking/TRACKING_NAMING.md:1.1 (collision motivation) :21-23: "Concurrent pipelines with the same slug … cross-fulfill each other's markers"

- Claims live in `.zskills/claims/`; claim.json has pipeline_id, current_phase,
  started_at →
  skills/run-plan/scripts/claim-plan.sh:53: "{schema_version, kind, slug, pipeline_id, started_at, current_phase"

- current_phase starts at "Phase 0 — acquired", advances to "Phase 1",
  "Phase 2", … →
  skills/run-plan/scripts/claim-plan.sh:301: "\"current_phase\":      \"Phase 0 — acquired\","
  skills/run-plan/scripts/claim-plan.sh:56: "current_phase is initialised to \"Phase 0 — acquired\" at acquire and"
  skills/run-plan/SKILL.md:1167: "set-phase \"$PLAN_SLUG\" --require-pipeline \"$PIPELINE_ID\" --current-phase \"Phase $PHASE\" || true"

- Taken when work starts, released when work resolves, no timeout; a stale
  claim after a crash is the accepted cost of never killing an agent mid-work →
  skills/run-plan/scripts/claim-plan.sh:70-71: "the operator runs `claim-plan.sh release <slug> --require-pipeline <stored-id>` explicitly. No automated TTL-based"
  skills/run-plan/scripts/claim-plan.sh:43: "# TTL/heartbeat/sweep."

- A pipeline re-taking its OWN claim succeeds (not a collision) →
  skills/run-plan/scripts/claim-plan.sh:37-41: "Self-re-entry: the EEXIST arm of acquire delegates to … A pipeline re-acquiring its OWN claim (same pipeline_id) gets exit 0"

- Release command (source paths) → **#1002 carve-out, left as-is**
  skills/run-plan/scripts/claim-plan.sh:32: "#   release <slug> --require-pipeline <id>"
  skills/fix-issues/scripts/claim-issue.sh exists (issues variant)

## Section 4 — `.landed`

- `.landed` is worktree state, not a tracking marker →
  docs/tracking/TRACKING_NAMING.md:232: "**Decision: `.landed` is NOT a tracking marker.**"
  docs/tracking/TRACKING_NAMING.md:235-236: "`.landed` is a separate artifact written at worktree-root by `/commit land`"

- Written when a pipeline lands work →
  skills/commit/scripts/write-landed.sh:11-15: "Usage: … status: landed …"
  skills/commit/scripts/write-landed.sh:19: "# Writes: <worktree-path>/.landed (atomic via .tmp + mv)"

- status values (landed / pr-ready / pr-ci-failing / conflict / pr-failed /
  not-landed) →
  skills/commit/scripts/write-landed.sh:12: "#   status: landed"
  skills/fix-issues/modes/pr.md:371: "| PR open, CI passed, awaiting review | `pr-ready` | `pr` | `pass`/`none`/`skipped` | `OPEN` |"
  skills/fix-issues/modes/pr.md:373: "| PR open, CI failing after max attempts | `pr-ci-failing` | `pr` | `fail` | `OPEN` |"
  skills/fix-issues/modes/pr.md:374: "| Branch pushed, PR creation failed | `pr-failed` | `pr` | _(not set)_ | _(not set)_ |"
  (`not-landed` named in CLAUDE.md Worktree Rules "still write a marker with
  `status: not-landed`"; `conflict` is the rebase-conflict outcome —
  skills/fix-issues/modes/pr.md:339: "merged|pr-ready|pr-ci-failing|rebase-conflict|...")

- No `.landed` → check manually with `git log main..<branch>`, `git status` →
  CLAUDE.md Worktree Rules: "If no `.landed` marker: verify manually with (1) `git log main..<branch>`, (2) `git status`"

## Section 5 — Plan reports

- Reports live under the config `output.reports_dir`, this project `docs/reports/`;
  per-plan plan-<slug>.md newest phase at top; SPRINT_REPORT.md for /fix-issues →
  (config-resolved path; descriptive — prior doc cited output.reports_dir; the
  per-phase prepend behavior is run-plan's report-writing step, representative)
  skills/run-plan/SKILL.md (phase report prepend) — phase-by-phase report is
  run-plan's documented per-phase report write.

## Section 6 — Watching a running pipeline

- Claim current_phase updates as the run advances → (same as Section 3 cite)
  skills/run-plan/SKILL.md:1167: "set-phase … --current-phase \"Phase $PHASE\""

- Dashboard shows tracking activity + a run-status chip (queued / phase-N /
  finish / locked) →
  skills/zskills-dashboard/SKILL.md:6-7: "Local web dashboard — plans, issues, worktrees, branches, tracking activity"
  (chip states are the dashboard's monitor-state run-status vocabulary)

- A `finish auto` run schedules a recurring cron; `/run-plan <plan> status`,
  `next`, and `/run-plan stop` (releases claims) →
  skills/run-plan/SKILL.md (status/next/stop modes); claim release on stop:
  skills/run-plan/scripts/claim-plan.sh:32: "#   release <slug> --require-pipeline <id>"

## Section 7 — Cheat sheet + Housekeeping

- find/grep over fulfilled.* counts completion records → (same as Section 2)
- clear-tracking.sh sweeps requires.*/step.* and keeps fulfilled.* →
  skills/update-zskills/scripts/clear-tracking.sh:2: "# Clear skill tracking bookkeeping. Preserves fulfilled.run-plan.*"
  skills/update-zskills/scripts/clear-tracking.sh:23: "Clears .zskills/tracking/* EXCEPT fulfilled.run-plan.* (completion history)."
  (the clear-tracking source path is **#1002 carve-out** — left as-is)
