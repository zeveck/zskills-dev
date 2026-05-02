---
name: plans
disable-model-invocation: true
argument-hint: "[rebuild | next | details]"
description: >-
  Plan dashboard. View plan status, find the next ready plan. For batch
  execution, see `/work-on-plans`.
metadata:
  version: "2026.05.02+03ddc6"
---

# /plans [rebuild | next | details] — Plan Dashboard

Maintains `plans/PLAN_INDEX.md` — a structured index of all plan files with
their classification, status, and priority.

**Modes:**

- **bare** `/plans` — display the current index (highlights top-priority ready plan)
- **rebuild** `/plans rebuild` — scan all plans, classify, regenerate
- **next** `/plans next` — show the highest-priority ready-to-run plan with command
- **details** `/plans details` — show every plan with a one-line description
- **For batch execution:** see `/work-on-plans`.

## Single source of truth

All four modes consume the **Phase 4 Python aggregator**
(`skills/zskills-dashboard/scripts/zskills_monitor/collect.py`) — never
re-parse plan frontmatter or progress trackers from skill prose. The
aggregator is the canonical classifier; this skill is a thin renderer
over its JSON output.

Canonical invocation (used by every mode below):

```bash
MAIN_ROOT=$(git rev-parse --show-toplevel)
PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts" \
  python3 -m zskills_monitor.collect
```

The CLI emits a single JSON document on stdout matching the
`collect_snapshot()` schema. The fields this skill consumes from each
`snapshot.plans[]` entry are:

- `slug`, `file`, `title`, `blurb`, `phase_count`, `phases_done`
- `status` — frontmatter value (`active`, `complete`, `landed`, `conflict`,
  or empty → defaults to `active`)
- `category` — one of `"canary"`, `"issue_tracker"`, `"reference"`,
  `"executable"` (set by `collect.py`'s `_categorize_plan`)
- `meta_plan` — `true` if the plan body invokes `Skill: { skill: "run-plan", … }`;
  `sub_plans` lists the slugs of its delegated children

Example aggregator emission (single plan entry, fields trimmed for
clarity — note the JSON shape this skill consumes):

```json
{
  "slug": "example-plan",
  "title": "Example Plan",
  "status": "active",
  "phase_count": 5,
  "phases_done": 0,
  "category": "executable",
  "meta_plan": false,
  "sub_plans": [],
  "queue": {"column": "drafted", "index": -1, "mode": null}
}
```

Canaries surface as `"category": "canary"`; issue-tracker docs as
`"category": "issue_tracker"`; reference docs as `"category": "reference"`;
and meta-plans add `"meta_plan": true` plus a non-empty `sub_plans[]`.
- `queue.column` — current monitor-state column (`ready`, `drafted`,
  `reviewed`, `landed`, etc.) or `null` if hidden
- `phases[]` — per-row tracker entries with `n`, `name`, `status`, `commit`

If `python3` is missing, the module fails to import, or the CLI exits
non-zero, every mode below reports the error to the user verbatim and
exits non-zero. **There is no bash fallback** — the prose classifier was
removed when this skill migrated to the aggregator.

## Index → snapshot section mapping

The six sections of `plans/PLAN_INDEX.md` are derived from the
aggregator's `category`, `status`, `phases_done`, and `queue.column`
fields per this mapping (used by Mode: Rebuild, Mode: Show, and Mode:
Details to group plans):

| Section | Selector |
|---------|----------|
| **Ready to Run** | `category=="executable"` AND `status=="active"` AND `phases_done == 0` AND `queue.column != "ready"`; OR `queue.column == "ready"` (any plan explicitly placed in the ready column wins regardless of phase progress) |
| **In Progress** | `category=="executable"` AND `status=="active"` AND `phases_done >= 1` AND `phases_done < phase_count` |
| **Needs Review** | `category=="executable"` AND `status=="conflict"` |
| **Complete** | `status` in `{"complete","landed"}` |
| **Canaries** | `category=="canary"` (regardless of status — canaries never promote into other sections) |
| **Reference (not executable)** | `category` in `{"reference","issue_tracker"}` |

**Meta-plans** (`meta_plan==true`) are listed at the top level of
whichever section their `status`/category place them in, with each entry
in `sub_plans[]` indented beneath them using `↳` prefix. Sub-plans do
NOT appear as separate top-level entries.

## Mode: Show (bare `/plans`)

1. Read `plans/PLAN_INDEX.md`.
2. If the file does not exist, **auto-run rebuild** (Mode: Rebuild below) to
   create it, then display the newly generated index.
3. If the file exists, display an **actionable dashboard** — not a one-line
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
5. Append a one-line footer:
   > Note: this ranking is independent of the monitor dashboard's Ready
   > queue. For interactive prioritization, open /zskills-dashboard.
6. **Exit.**

## Mode: Details (`/plans details`)

Show every plan with a one-line description, grouped by status. Useful
when you have many plans and can't remember what each one is about.

1. Invoke the canonical aggregator CLI (see "Single source of truth"
   above):

   ```bash
   MAIN_ROOT=$(git rev-parse --show-toplevel)
   SNAPSHOT=$(PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts" \
     python3 -m zskills_monitor.collect) || {
       echo "ERROR: zskills_monitor.collect failed (rc=$?)" >&2
       exit 1
     }
   ```

   Parse `$SNAPSHOT` as JSON.
2. Group `snapshot.plans[]` per the section mapping above
   (Ready / In Progress / Needs Review / Complete / Canaries /
   Reference). Use each plan's `blurb` field directly — `collect.py`
   already extracted the first paragraph after `## Overview`, trimmed
   to 240 characters.
3. Display grouped by status (Ready, In Progress, Complete, Canaries,
   Reference), with the blurb after each plan name:

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

   Within the Canaries group, derive the per-canary tracker state from
   the snapshot's `phases[]` array: all rows `done` → `Complete`; some
   `done` and some not → `In Progress`; none `done` → `Ready`; empty
   `phases[]` (no Progress Tracker present) → `Manual — no tracker`. Do
   not promote canaries into other groups.
4. **Exit.**

## Mode: Rebuild (`/plans rebuild`)

Regenerate `plans/PLAN_INDEX.md` from the aggregator snapshot. The
implementing agent shells out to `python3 -m zskills_monitor.collect`
and renders the six-section index from the returned JSON — there is
**no in-prose classifier**. All status, category, phase-count, and
meta-plan inference happens inside `collect.py`.

### Step 1 — Invoke the aggregator

```bash
MAIN_ROOT=$(git rev-parse --show-toplevel)
SNAPSHOT_JSON=$(PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts" \
  python3 -m zskills_monitor.collect)
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "ERROR: python3 -m zskills_monitor.collect failed (rc=$RC)" >&2
  echo "Cannot regenerate plans/PLAN_INDEX.md — bailing out." >&2
  exit 1
fi
```

If the invocation fails (e.g. `python3` missing, `zskills_monitor`
package unimportable, runtime exception), the rebuild aborts with a
non-zero exit and the diagnostic above. **Do not** synthesize a
fallback classifier — Phase 9 of `plans/ZSKILLS_MONITOR_PLAN.md`
explicitly removes the legacy bash classifier so that
`collect.py` is the single source of truth for plan classification.

### Step 2 — Group `snapshot.plans[]` into sections

Apply the section-selector table from "Index → snapshot section
mapping" above. Concretely (parse `$SNAPSHOT_JSON` with a JSON-aware
helper — `python3 -c 'import json,sys; …'` is fine):

- **Ready to Run** ← plan where (`category=="executable"` AND
  `status=="active"` AND `phases_done == 0` AND
  `queue.column != "ready"`) OR (`queue.column == "ready"`).
- **In Progress** ← plan where `category=="executable"` AND
  `status=="active"` AND `1 <= phases_done < phase_count`.
- **Needs Review** ← plan where `category=="executable"` AND
  `status=="conflict"`.
- **Complete** ← plan where `status` is `"complete"` or `"landed"`.
- **Canaries** ← plan where `category=="canary"`. Render
  per-canary tracker status from the snapshot's `phases[]`:
  all done → `Complete`; some done → `In Progress`; none done →
  `Ready`; no `phases[]` → `Manual — no tracker`.
- **Reference (not executable)** ← plan where `category` is
  `"reference"` or `"issue_tracker"`.

For each meta-plan (`meta_plan==true`), list its top-level entry under
its own section, then indent each slug in its `sub_plans[]` underneath
with `↳`. Sub-plans MUST NOT appear as separate top-level entries —
look them up in `snapshot.plans[]` by `slug` and write them only as
the meta-plan's children.

### Step 3 — Order within each section

- **Ready to Run**: items whose `queue.column == "ready"` come first
  (in their `queue.index` order from the snapshot — this preserves
  user-set priority from `/zskills-dashboard`). Then default-column
  Ready entries, ordered by recency (newest first; tiebreak alphabetical
  by `slug`). Assign priority labels: `High` for plans referenced as
  fix-issues "too complex" skips (check `SPRINT_REPORT.md` if it
  exists for context); `Medium` for plans created within the last 14
  days; `Low` otherwise.
- **In Progress / Complete / Reference / Canaries**: alphabetical by
  `slug`.
- **Needs Review**: alphabetical by `slug`.

### Step 4 — Write `plans/PLAN_INDEX.md`

Render with this structure (preserves the historical six-section shape):

```markdown
# Plan Index

Auto-generated by `/plans rebuild`. Last rebuilt: YYYY-MM-DD HH:MM ET.

Totals: N plans — A ready, B in progress, C complete, D canaries, E reference.

## Ready to Run

| Plan | Phases | Next Phase | Priority | Notes |
|------|--------|------------|----------|-------|
| [EXAMPLE_PLAN.md](EXAMPLE_PLAN.md) | 5 | 1 -- Setup | High | Referenced by fix-issues skip #NNN |

## In Progress

| Plan | Phases | Current Phase | Next Phase | Notes |
|------|--------|---------------|------------|-------|
| [FEATURE_PLAN.md](FEATURE_PLAN.md) | 8 | 4b -- Phase B | 4c -- Phase C | 4 of 8 phases done |

## Needs Review

Old-format plans without progress trackers, OR plans whose frontmatter
`status` is `conflict`. Status is ambiguous — may be complete, partially
done, or not started. Triage these once: mark as Complete, move to
Ready, or rewrite with `/draft-plan plans/FILE.md`.

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
  `| (none) | | | | |`.
- Use relative links (just the filename, since the index lives in
  `plans/`).
- `phase_count` from the snapshot drives the "Phases" column; for
  In Progress entries, the "Current Phase" is the last `phases[]` row
  with `status=="done"` and "Next Phase" is the first remaining row.
- Do NOT recompute classification by reading plan files in this skill;
  every category/status/phase value comes from the snapshot.
- Canary tracker status: derive from the snapshot's `phases[]` per
  Step 2's Canaries rule. Stale entries are acceptable — the section
  is for visual segregation, not ground-truth run history.

### Step 5 — Block-plan coverage line (optional context)

The "Reference (not executable)" footer line can include a count of
implemented blocks vs. block plans:

```bash
BLOCK_PLANS=$(find plans/blocks -name '*.md' 2>/dev/null | wc -l)
BLOCK_IMPLS=$(grep -c "    type: '" src/library/registry.js 2>/dev/null)
```

Use the registry file for the implementation count — it's the
authoritative registry. `find *Block.js` undercounts because some
components don't follow the `*Block.js` naming convention.

## Mode: Next (`/plans next`)

1. Invoke the canonical aggregator CLI (see "Single source of truth"
   above) and parse the JSON. Apply the section mapping to identify
   the **Ready to Run** set.
2. If `plans/PLAN_INDEX.md` is missing, **also auto-run rebuild** so
   the file exists for subsequent `/plans` calls. This is a
   side-effect, not the source of truth — `Mode: Next` reads its
   answer from the snapshot, not from the regenerated index.
3. Pick the highest-priority Ready entry using Mode: Rebuild Step 3's
   ordering: `queue.column == "ready"` items first (in
   `queue.index` order), then default-column Ready entries by
   recency.
4. If found, output:
   > **Next plan to run:** `EXAMPLE_PLAN.md`
   > Phases: 5, starting at Phase 1 -- Setup
   > Priority: High (referenced by fix-issues skip #NNN)
   >
   > Run with: `/run-plan plans/EXAMPLE_PLAN.md`

   The "starting at Phase 1 -- …" comes from the first entry in the
   snapshot plan's `phases[]` whose `status != "done"` (or, if
   `phases[]` is empty, from the first `## Phase` heading captured by
   `collect.py` and exposed via `phase_count`).
5. If the Ready-to-Run set is empty:
   > No plans ready to run. All executable plans are either in progress or complete.
   > Check "In Progress" plans in the index for plans that need attention.
6. **Exit.**

## Key Rules

- **Single source of truth.** All classification (`category`,
  `meta_plan`, status, phase counts) lives in
  `skills/zskills-dashboard/scripts/zskills_monitor/collect.py`. The
  prose in this skill never reproduces those rules — it only describes
  how to render the snapshot's already-computed fields.
- **Rebuild is idempotent** — running it twice produces the same result
  (assuming no plan files changed between runs).
- **Never modify plan files** — the index is read-only metadata. It
  reads plans (via the aggregator) but never changes them.
- **Skip `plans/blocks/` subdirectories** — those are block-specific
  plan files managed by `/add-block`, not executable plans.
  `collect.py` already restricts to top-level `plans/*.md`.
- **Skip `PLAN_INDEX.md` itself** — don't index the index.
- **Relative links** — since the index lives in `plans/`, links are
  just filenames (e.g., `[FOO.md](FOO.md)`), not `plans/FOO.md`.
- **Timezone** — always use America/New_York (ET) for the "Last
  rebuilt" timestamp.
- **No bash fallback.** If `python3 -m zskills_monitor.collect` fails,
  every mode reports the failure and exits non-zero. Per
  `feedback_no_premature_backcompat`, this is intentional: maintaining
  two classifiers (the prose one and the Python one) was the bug
  Phase 9 closes.
