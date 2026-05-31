---
name: plans
disable-model-invocation: true
argument-hint: "[rebuild | next | details]"
description: >-
  Plan dashboard. View plan status, find the next ready plan. For batch
  execution, see `/work-on-plans`.
metadata:
  version: "2026.05.31+e4e4af"
---

# /plans [rebuild | next | details] — Plan Dashboard

Maintains `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md` — a structured index of all plan files with
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

The six sections of `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md` are derived from the
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

1. Compute the source mtime — the most recently modified of
   `$ZSKILLS_PLANS_DIR/*.md` and `.zskills/monitor-state.json`. Compare
   against `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md`'s mtime. If the index is
   missing OR the source is newer, **auto-run Mode: Rebuild** before
   reading. There is no staleness warning — the source-staleness check
   guarantees the index reflects current source on every Mode: Show
   invocation. Drop-in script:

   ```bash
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
     . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
   else
     . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
   fi
   MAIN_ROOT=$(git rev-parse --show-toplevel)
   ZSKILLS_PATHS_ROOT="$MAIN_ROOT" \
     if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
       . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
     else
       source "$MAIN_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
     fi

   INDEX="$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md"
   STATE="$MAIN_ROOT/.zskills/monitor-state.json"

   needs_rebuild() {
     [ ! -f "$INDEX" ] && return 0
     local idx_mtime src_mtime f
     idx_mtime=$(stat -c %Y "$INDEX" 2>/dev/null || stat -f %m "$INDEX")
     src_mtime=0
     for f in "$ZSKILLS_PLANS_DIR"/*.md "$STATE"; do
       [ -e "$f" ] || continue
       local m
       m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
       [ "$m" -gt "$src_mtime" ] && src_mtime="$m"
     done
     [ "$src_mtime" -gt "$idx_mtime" ]
   }

   if needs_rebuild; then
     # Invoke Mode: Rebuild (see below).
     REBUILT_AT=$(TZ="${TIMEZONE:-UTC}" date '+%Y-%m-%d %H:%M %Z')
     mkdir -p "$ZSKILLS_AUDIT_DIR"
     PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts" \
       python3 -m zskills_monitor.collect \
       | python3 "$ZSKILLS_SKILLS_ROOT/plans/scripts/render-index.py" \
           --rebuilt-at "$REBUILT_AT" \
       > "$INDEX"
   fi
   ```

2. Read `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md`.
3. Display an **actionable dashboard** — not a one-line summary. Show the
   actual plan names and status so the user can decide what to work on:

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

4. Append a one-line footer:
   > Note: this ranking is independent of the monitor dashboard's Ready
   > queue. For interactive prioritization, open /zskills-dashboard.
5. **Exit.**

No 24-hour staleness warning is emitted — Step 1's source-staleness
auto-rebuild guarantees the index is never stale at display time. If
you ever see "this looks out of date" output, the bug is in Step 1's
mtime comparison, not a missing manual rebuild.

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

Regenerate `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md` from the aggregator
snapshot. **There is no in-prose classifier and no in-prose
renderer.** Classification (`category`, `status`, `phase_count`,
`meta_plan`, `queue.column`) lives in `collect.py`; section
bucketing, ordering, meta-plan sub-plan indentation, and markdown
emission live in `skills/plans/scripts/render-index.py`. The
implementing agent runs a single pipeline and exits.

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(git rev-parse --show-toplevel)
ZSKILLS_PATHS_ROOT="$MAIN_ROOT" \
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    source "$MAIN_ROOT/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi

REBUILT_AT=$(TZ="${TIMEZONE:-UTC}" date '+%Y-%m-%d %H:%M %Z')
mkdir -p "$ZSKILLS_AUDIT_DIR"

set -o pipefail
if ! PYTHONPATH="$MAIN_ROOT/skills/zskills-dashboard/scripts" \
       python3 -m zskills_monitor.collect \
     | python3 "$ZSKILLS_SKILLS_ROOT/plans/scripts/render-index.py" \
         --rebuilt-at "$REBUILT_AT" \
     > "$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md"; then
  echo "ERROR: python3 -m zskills_monitor.collect failed (or render-index.py rejected its output)" >&2
  echo "Cannot regenerate $ZSKILLS_AUDIT_DIR/PLAN_INDEX.md — bailing out." >&2
  exit 1
fi
```

The script ownership split — `collect.py` for classification,
`render-index.py` for rendering — is deliberate. PR #214 surfaced
a prose-driven rebuild that misclassified 5 canaries as Complete
because the precedence rule was buried in a parenthetical inside a
prose table; pulling rendering into a deterministic Python helper
removes that bug class. Section precedence (`category=="canary"`
NEVER promotes; `category` in `{reference, issue_tracker}` is the
second filter; only then does `status` apply), ordering (explicit
`queue.column=="ready"` by index, then default by recency), and
meta-plan sub-plan indentation are all enforced in code in
`render-index.py`.

The "Index → snapshot section mapping" table above stays as
documentation but is no longer load-bearing for execution — the
single source of truth is `render-index.py`.

### Optional context — block-plan coverage line

The renderer's "Reference (not executable)" section is generated
from the snapshot. If a downstream agent wants a block-plan coverage
note in the dashboard view, the count is available via:

```bash
BLOCK_PLANS=$(find "$ZSKILLS_PLANS_DIR/blocks" -name '*.md' 2>/dev/null | wc -l)
BLOCK_IMPLS=$(grep -c "    type: '" src/library/registry.js 2>/dev/null)
```

Use the registry file for the implementation count — it's the
authoritative registry. `find *Block.js` undercounts because some
components don't follow the `*Block.js` naming convention. The
renderer itself does not consult this — it's context for Mode: Show
prose if desired.

## Mode: Next (`/plans next`)

1. Invoke the canonical aggregator CLI (see "Single source of truth"
   above) and parse the JSON. Apply the section mapping to identify
   the **Ready to Run** set.
2. If `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md` is missing, **also auto-run rebuild** so
   the file exists for subsequent `/plans` calls. This is a
   side-effect, not the source of truth — `Mode: Next` reads its
   answer from the snapshot, not from the regenerated index.
3. Pick the highest-priority Ready entry using the renderer's ordering
   (mirrored in `render-index.py`'s `_sort_ready`):
   `queue.column == "ready"` items first (in `queue.index` order),
   then default-column Ready entries by recency (newest first;
   alphabetical tiebreak by `slug`).
4. If found, output:
   > **Next plan to run:** `EXAMPLE_PLAN.md`
   > Phases: 5, starting at Phase 1 -- Setup
   > Priority: High (referenced by fix-issues skip #NNN)
   >
   > Run with: `/run-plan plans/EXAMPLE_PLAN.md`

   The "starting at Phase 1 -- …" comes from the first entry in the
   snapshot plan's `phases[]` whose `status != "done"` (or, if
   `phases[]` is empty, from the first `## Phase` heading captured by
   `collect.py` and exposed via `phase_count`). Phase headings match
   the form `## Phase <N> <sep> Name` where `<sep>` is one of em-dash
   (`—`, canonical), en-dash (`–`), colon (`:`), or hyphen (`-`).
   Plans whose phase headings use any other separator are classified
   as Reference (`phase_count=0`) and will not appear in Ready-to-Run.
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
- **Skip `$ZSKILLS_PLANS_DIR/blocks/` subdirectories** — those are block-specific
  plan files managed by `/add-block`, not executable plans.
  `collect.py` already restricts to top-level `$ZSKILLS_PLANS_DIR/*.md`.
- **Skip `PLAN_INDEX.md` itself** — don't index the index.
- **Relative links** — since the index lives in `$ZSKILLS_PLANS_DIR`, links are
  just filenames (e.g., `[FOO.md](FOO.md)`), not the full path.
- **Timezone** — use the configured timezone (`TZ="${TIMEZONE:-UTC}" date`)
  for the "Last rebuilt" timestamp.
- **No bash fallback.** If `python3 -m zskills_monitor.collect` fails,
  every mode reports the failure and exits non-zero. Per
  `feedback_no_premature_backcompat`, this is intentional: maintaining
  two classifiers (the prose one and the Python one) was the bug
  Phase 9 closes.
