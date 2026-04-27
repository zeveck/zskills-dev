---
name: plans
disable-model-invocation: true
argument-hint: "[rebuild | next | details | work N [auto] [every SCHEDULE] [now]] | stop | next-run"
description: >-
  Plan dashboard and batch executor. View plan status, find the next
  ready plan, or work through plans automatically.
  Usage: /plans [rebuild | next | work N [auto] [every SCHEDULE]]
---

# /plans [rebuild | next | details | work N] — Plan Dashboard & Executor

Maintains `plans/PLAN_INDEX.md` — a structured index of all plan files with
their classification, status, and priority. Also supports batch execution
of ready plans (like `/fix-issues` for bugs).

**Modes:**

- **bare** `/plans` — display the current index (highlights top-priority ready plan)
- **rebuild** `/plans rebuild` — scan all plans, classify, regenerate
- **next** `/plans next` — show the highest-priority ready-to-run plan with command
- **details** `/plans details` — show every plan with a one-line description
- **work** `/plans work N [auto]` — batch-execute next N ready plans
- **stop** `/plans stop` — cancel scheduled runs
- **next-run** `/plans next-run` — when does the next scheduled run fire?

## Mode: Show (bare `/plans`)

1. Read `plans/PLAN_INDEX.md`
2. If the file does not exist, **auto-run rebuild** (Mode: Rebuild below) to
   create it, then display the newly generated index.
3. If the file exists, display a **actionable dashboard** — not a one-line
   summary. Show the actual plan names and status so the user can decide
   what to work on:

   ```
   Plans: 5 ready, 2 in progress, 10 complete, 6 canaries

   Ready to Run:
     EDITOR_GAPS_PLAN.md              9 gaps     High
     IMPORT_GAPS_PLAN.md              4 phases   Medium
     INLINE_CHARTS.md                 5 phases   Medium

   In Progress:
     FEATURE_PLAN.md                  Phase 4b   4/8 done
     CORRECTNESS_PLAN.md              Phase 1    1/3 done

   Needs Review: 3 plans (old format, status ambiguous)

   Canaries: 6 total (tracker state — not actual run history)

   Next: /run-plan plans/EDITOR_GAPS_PLAN.md
   ```

   Show Ready and In Progress tables with plan names, phase info, and
   priority. Collapse Complete/Reference/Canaries into counts. Highlight
   the top-priority ready plan with a suggested `/run-plan` command. The
   Canaries count comes from the index's Canaries section; never promote
   a canary into Ready/In Progress in the dashboard view.

4. If the file is older than 24 hours (check mtime), append:
   > ⚠️ Index is older than 24 hours. Run `/plans rebuild` to refresh.
5. **Exit.**

## Mode: Details (`/plans details`)

Show every plan with a one-line description, grouped by status. Useful
when you have many plans and can't remember what each one is about.

1. Read `plans/PLAN_INDEX.md` (auto-rebuild if missing).
2. For each plan in the index, read its `## Overview` section (first
   paragraph only) and extract a one-line blurb.
3. Display grouped by status (Ready, In Progress, Complete, Canaries),
   with the blurb after each plan name:

   ```
   Ready to Run:
     DOC_GAPS_PLAN.md (5 phases, Medium)
       Fill documentation gaps: missing READMEs, stale block counts, broken links

     BLOCK_EXPANSION_PLAN.md (4 phases, Medium)
       Add 15 missing blocks via /add-block delegate phases

   In Progress:
     CORRECTNESS_PLAN.md (13 phases, 7/13 done)
       Systematic solver accuracy improvements with analytical reference tests

   Complete:
     BRIEFING_SKILL_PLAN.md (7 phases)
       Activity briefing and review dashboard with 5 modes
     ...

   Canaries (tracker state — not actual run history):
     CANARY1_HAPPY.md (3 phases, Ready)
       Happy-path /run-plan single-phase canary
     CANARY11_SCOPE_VIOLATION.md (Manual — no tracker)
       Adversarial canary: agent attempts out-of-scope edits
     ...
   ```

   The Canaries group renders the index's Canaries section verbatim. Use
   the same symbol-counting rules from Mode: Rebuild Step 3 (`⬚` and `⬜`
   are both pending) when displaying tracker status. Do not promote
   canaries into other groups.

4. **Exit.**

## Mode: Rebuild (`/plans rebuild`)

Scan `plans/`, classify every `.md` file, and write a fresh `plans/PLAN_INDEX.md`.

### Step 1 — Inventory

```bash
ls plans/*.md
```

Get all plan files. Ignore subdirectories (e.g., `plans/blocks/`).

Also count block plan files for the coverage summary:
```bash
BLOCK_PLANS=$(find plans/blocks -name '*.md' 2>/dev/null | wc -l)
BLOCK_IMPLS=$(grep -c "    type: '" src/library/registry.js 2>/dev/null)
```
Use the registry file for the implementation count — it's the authoritative
registry. `find *Block.js` undercounts because some components (Resistor.js,
Capacitor.js, etc.) don't follow the `*Block.js` naming convention.

### Step 2 — Classify each file

For each file, read enough of the file to classify it correctly. **Do not
skim.** If the file has a Progress Tracker table, you MUST read every row of
that table and count the status symbols — not summarize, not eyeball. Read
the tracker in full even if it sits past the top of the file; do not stop
after a fixed line budget. Index accuracy is load-bearing: a wrong status
leads to wasted runs (re-executing done work) or missed work (skipping
ready plans).

Classify into one of four categories:

1. **Canary** — filename matches `CANARY*.md` OR `*_CANARY*.md` (case
   sensitive on `CANARY`). Examples: `CANARY1_HAPPY.md`,
   `CANARY11_SCOPE_VIOLATION.md`, `REBASE_CONFLICT_CANARY.md`,
   `CI_FIX_CYCLE_CANARY.md`, `PARALLEL_CANARYA.md`. The filename match
   takes precedence over executable-plan content detection: a plan with
   phases AND a `CANARY`-matching name is classified as a canary, not an
   executable plan. Canaries are re-runnable test fixtures and are listed
   in their own section so users do not confuse their tracker state with
   feature-plan progress.

2. **Executable plan** — has `## Phase` sections (numbered phases with work
   items) OR has a Progress Tracker table (`| Phase | Status |`). These are
   plans that `/run-plan` can execute.

   **Meta-plan detection:** If the plan's phases use `### Execution: delegate
   /run-plan` directives referencing other plan files, it's a meta-plan. Record
   which sub-plan files it references. In the index, sub-plans should be
   indented under their meta-plan rather than listed independently.

3. **Issue tracker** — filename ends in `_ISSUES.md` OR has an "Issue Tracker"
   or "Issue List" heading OR is primarily a table of GitHub issue numbers.
   List separately — these are not executable by `/run-plan`.
   **Deterministic rule:** Files ending in `_ISSUES.md` are ALWAYS classified
   as issue trackers, regardless of other content (e.g., phase sections).
   The filename suffix takes precedence over content-based classification.

4. **Reference document** — everything else (research docs, overviews, gap
   analyses, block library lists). List separately.

### Step 3 — Determine status for executable plans

For each executable plan, determine its status:

1. **Read the Progress Tracker** (if present) — a table with phase rows and
   status indicators. Read EVERY row; do not stop at the first few. Count the
   symbols.

   **Pending symbols (treat both as "not done"):**
   - `⬚` (U+2B1A SQUARE TILE) — used by some plans (e.g., ZSKILLS_MONITOR_PLAN)
   - `⬜` (U+2B1C WHITE LARGE SQUARE) — used by other plans (e.g., CANARY1_HAPPY)

   The classifier MUST match either symbol as pending. Real plans in this
   repo use both interchangeably; treating only one as pending causes the
   other set to misclassify.

   **Done symbols:** `✅` / `✔` / `Done` / `Complete` / a 7+ char hex commit hash.

   Status determination:
   - All phases done (no `⬚`/`⬜` or other pending markers remain) → **Complete**
   - Some phases done, others pending (`⬚`/`⬜`/`Not Started`/empty) →
     **In Progress** (note the current phase name and the next incomplete phase)
   - No phases done (all rows show `⬚`/`⬜`/`Not Started`/empty) → **Ready**

2. **No Progress Tracker?** Check for other completion signals:
   - Sections with `**Status:** Done` or `**Status:** Complete` → count as done
   - If all phase sections have completion markers → **Complete**
   - If some do → **In Progress**
   - If the plan has phases but no status indicators at all → **Needs Review**
     (old-format plan; status is ambiguous — may be complete, may not be)
   - Only classify as **Ready** if the plan clearly hasn't been started
     (e.g., freshly created by `/draft-plan`)

### Step 3b — Classify canaries within the Canaries section

For each canary file, determine its tracker-state classification using the
SAME symbol-counting rules from Step 3 (both `⬚` and `⬜` are pending; `✅` /
`Done` / commit hash are done). The result feeds the Canaries section, not
Ready/In Progress/Complete.

- Has Progress Tracker, all rows pending → **Ready** (within Canaries)
- Has Progress Tracker, some done → **In Progress** (within Canaries)
- Has Progress Tracker, all done → **Complete** (within Canaries)
- **No Progress Tracker** (e.g., CANARY8_PARALLEL, CANARY9_FINAL_VERIFY,
  CANARY11_SCOPE_VIOLATION) → list as **Manual — no tracker**

Do NOT use git history, PR resolution, or any other evidence beyond the
canary's own Progress Tracker. The canary section is intentionally allowed
to show stale entries — the point of the section is segregation, not
ground-truth run history.

### Step 4 — Determine priority for "Ready to Run" plans

Rank ready plans by:

1. **Plans referenced by `/fix-issues` "too complex" skips** — check
   `SPRINT_REPORT.md` for "Skipped -- Too Complex" entries that reference a
   plan file. Those plans are highest priority (blocking batch fixes).
2. **Recently created plans** — sort by git creation date (newest first).
   Use `git log --diff-filter=A --format=%aI -- <file>` to get each file's
   initial commit date. This avoids conflating "recently written" with
   "recently touched by any edit."
3. **Alphabetical** — tiebreaker.

Assign priority labels: **High** (referenced by fix-issues skips), **Medium**
(recent), **Low** (older/alphabetical fallback).

### Step 5 — Write `plans/PLAN_INDEX.md`

Write the index file with this structure:

```markdown
# Plan Index

Auto-generated by `/plans rebuild`. Last rebuilt: YYYY-MM-DD HH:MM ET.

## Ready to Run

| Plan | Phases | Next Phase | Priority | Notes |
|------|--------|------------|----------|-------|
| [EXAMPLE_PLAN.md](EXAMPLE_PLAN.md) | 5 | 1 -- Setup | High | Referenced by fix-issues skip #NNN |

## In Progress

| Plan | Phases | Current Phase | Next Phase | Notes |
|------|--------|---------------|------------|-------|
| [FEATURE_PLAN.md](FEATURE_PLAN.md) | 8 | 4b -- Phase B | 4c -- Phase C | 4 of 8 phases done |

## Needs Review

Old-format plans without progress trackers. Status is ambiguous — may be
complete, partially done, or not started. Triage these once: mark as
Complete, move to Ready, or rewrite with `/draft-plan plans/FILE.md`.

| Plan | Phases | Issue | Notes |
|------|--------|-------|-------|
| [BETTER_SCOPE_PLAN.md](BETTER_SCOPE_PLAN.md) | 3 | No progress tracker | Check if scope overhaul was implemented |

## Complete

| Plan | Phases | Notes |
|------|--------|-------|
| [RUNTIME_PARITY_META.md](RUNTIME_PARITY_META.md) | 4 | Meta-plan — all sub-plans done |
|   ↳ [RUNTIME_SIGNAL_FLOW_BLOCKS.md](RUNTIME_SIGNAL_FLOW_BLOCKS.md) | 3 | Sub-plan of RUNTIME_PARITY_META |
|   ↳ [RUNTIME_DEPLOY_SERIALIZATION.md](RUNTIME_DEPLOY_SERIALIZATION.md) | 2 | Sub-plan of RUNTIME_PARITY_META |
| [CODEGEN_PLAN.md](CODEGEN_PLAN.md) | 3 | All phases done |

## Canaries

Canaries are re-runnable test fixtures; their tracker state may not reflect
actual run history. To check whether a canary has run, examine git history
for its output file or a PR with its name.

| Canary | Tracker Status | Phases | Notes |
|--------|----------------|--------|-------|
| [CANARY1_HAPPY.md](CANARY1_HAPPY.md) | Ready | 3 | Symbol: ⬜ |
| [REBASE_CONFLICT_CANARY.md](REBASE_CONFLICT_CANARY.md) | In Progress | 4 | 2 of 4 phases done |
| [CANARY11_SCOPE_VIOLATION.md](CANARY11_SCOPE_VIOLATION.md) | Manual — no tracker | n/a | No Progress Tracker |

## Reference (not executable)

| File | Type | Description |
|------|------|-------------|
| [OVERVIEW.md](OVERVIEW.md) | Reference | Project overview |
| [ISSUES_PLAN.md](ISSUES_PLAN.md) | Issue Tracker | Master issue index |
| Block Plans (`plans/blocks/`) | Reference | {BLOCK_IMPLS}/{BLOCK_PLANS} implemented |
```

**Notes for each section:**
- If a section would be empty, include the table header with a single row:
  `| (none) | | | | |`
- Use relative links (just the filename, since index is in `plans/`)
- Count phases by counting `## Phase` headings (or progress tracker rows)
- For "In Progress" plans, identify both the current phase (last done) and
  the next phase (first incomplete)
- **Meta-plan grouping:** If a plan is a meta-plan (has `delegate /run-plan`
  phases referencing other plan files), indent its sub-plans beneath it
  with `↳` prefix. Sub-plans should NOT appear as separate top-level entries.
  This makes the hierarchy visible — e.g., RUNTIME_PARITY_META owns
  RUNTIME_SIGNAL_FLOW_BLOCKS and RUNTIME_DEPLOY_SERIALIZATION.
- **Canaries section:** any file whose name matches `CANARY*.md` or
  `*_CANARY*.md` belongs in the Canaries section, never in
  Ready/In Progress/Complete — even if its tracker shows the same shape.
  Tracker Status within the section uses the Step 3 / Step 3b symbol rules
  (`⬚`/`⬜` pending, `✅`/`Done`/commit hash done). Canaries with no
  Progress Tracker are listed with Tracker Status `Manual — no tracker`.
  Stale entries are acceptable: the section is for visual segregation,
  not ground-truth run history.

## Mode: Next (`/plans next`)

1. Read `plans/PLAN_INDEX.md`
2. If the file does not exist, **auto-run rebuild** to create it first.
3. Find the first entry in the "Ready to Run" table (highest priority)
4. If found, output:
   > **Next plan to run:** `EXAMPLE_PLAN.md`
   > Phases: 5, starting at Phase 1 -- Setup
   > Priority: High (referenced by fix-issues skip #NNN)
   >
   > Run with: `/run-plan plans/EXAMPLE_PLAN.md`
5. If the "Ready to Run" table is empty or has only `(none)`:
   > No plans ready to run. All executable plans are either in progress or complete.
   > Check "In Progress" plans in the index for plans that need attention.
6. **Exit.**

## Key Rules

- **Rebuild is idempotent** — running it twice produces the same result
  (assuming no plan files changed between runs).
- **Never modify plan files** — the index is read-only metadata. It reads
  plans but never changes them.
- **Skip `plans/blocks/` subdirectories** — those are block-specific plan
  files managed by `/add-block`, not executable plans.
- **Skip `PLAN_INDEX.md` itself** — don't index the index.
- **Relative links** — since the index lives in `plans/`, links are just
  filenames (e.g., `[FOO.md](FOO.md)`), not `plans/FOO.md`.
- **Timezone** — always use America/New_York (ET) for the "Last rebuilt"
  timestamp.
