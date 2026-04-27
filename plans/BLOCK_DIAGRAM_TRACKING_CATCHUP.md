---
title: Block-Diagram Tracking-Naming Catch-up
created: 2026-04-26
status: active
---

# Plan: Block-Diagram Tracking-Naming Catch-up

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

Issue #65: `block-diagram/add-block/SKILL.md` and
`block-diagram/add-example/SKILL.md` still write tracking markers to the
**flat** layout `.zskills/tracking/<basename>` at 19 sites combined.
`plans/UNIFY_TRACKING_NAMES.md` migrated all `skills/` writers to the
per-pipeline subdir layout (`$TRACKING_DIR/$PIPELINE_ID/<basename>`)
across Phases 3-4, then **Phase 6 (commit `d9efce1`) deleted the
hook's dual-read flat-glob fallback** along with
`scripts/migrate-tracking.sh`. Result: every marker the two block-diagram
skills write is invisible to the three enforcement-gate clusters at
`hooks/block-unsafe-project.sh.template:421,497,589`. Delegation pairs
(parent's `requires.add-example.<slug>` ↔ child's
`fulfilled.add-example.<slug>`) never meet at the same path; the hook
silently allows commits whose enforcement these markers were supposed
to gate.

This plan catches block-diagram up. It is the third framework-wide
migration that almost missed `block-diagram/` (the prior two:
`isolation: "worktree"` removal — caught reactively by PR #66 lint;
this tracking migration — caught reactively by issue #65). Phase 3
of this plan asks whether we should add a CI guard that prevents a
fourth recurrence and gives the answer.

`block-diagram/` is **not** mirrored to `.claude/skills/`, so no mirror
sync is required for the SKILL.md edits. The PR-mode worktree branch
should be named `feat/block-diagram-tracking-catchup` (single PR per
phase, three phases, three PRs).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Migrate add-block + add-example writers (paired) | ⬚ | | One commit; 19 sites; bundled per delegation. |
| 2 — Lint guard + canary cases for block-diagram | ⬚ | | Mirrors `tests/test-skill-invariants.sh:128-134`; extends canary by 2 cases. |
| 3 — Framework-coverage CI guard for block-diagram (recommended) | ⬚ | | Decision in Design & Constraints below; one-work-item phase. |

## Shared Conventions

All phases respect these invariants:

- **Marker location**: `.zskills/tracking/$PIPELINE_ID/` (never flat,
  never under `.claude/`).
- **No mirror sync**: `block-diagram/` is NOT mirrored to
  `.claude/skills/`. Verification:
  `ls .claude/skills/add-block .claude/skills/add-example 2>&1 | grep -c
  'No such file'` returns 2.
- **No in-tree migration script**: per `docs/tracking/TRACKING_NAMING.md`
  OQ2 ("let expire") and Phase 6's deletion of
  `scripts/migrate-tracking.sh`. Pure code change. Block-diagram has no
  in-flight users mid-flow.
- **PIPELINE_ID sanitization**: every constructed PIPELINE_ID is sanitized
  via `bash scripts/sanitize-pipeline-id.sh "$PIPELINE_ID"` BEFORE the
  first `mkdir -p`. The sanitizer (`scripts/sanitize-pipeline-id.sh:9-10`)
  is `tr -c 'a-zA-Z0-9._-' '_' | head -c 128`. Do NOT introduce a
  second sanitizer.
- **Basename slugging (NEW vs prior draft)**: marker basename suffixes
  use sanitised slugs `${BLOCK_SLUG}` / `${NAME_SLUG}`, NOT the raw
  user-supplied `${BLOCK_NAME}` / `${NAME}`. Rationale: the sanitizer
  collapses whitespace and shell-special chars to `_`, so the
  PIPELINE_ID `add-block.My Block` becomes the directory
  `add-block.My_Block`, but a literal `requires.add-example.My Block`
  basename inside that dir would never pair with a child-written
  `fulfilled.add-example.My_Block` (or vice-versa). Sanitising the
  suffix at the same step the dir name is sanitised guarantees parent
  and child basenames pair-match for any user input. This supersedes
  the original draft's "preserve basenames verbatim" stance. The
  sanitizer is idempotent — running it on already-clean input
  (`Gain` → `Gain`, `math-batch` → `math-batch`) is a no-op, so existing
  callers that pass simple identifiers are unaffected.
- **Empty `${BLOCK_NAME}` / `${NAME}` is the orchestrator's
  responsibility**: the sanitizer returns empty for empty input,
  which would degrade marker basenames to `requires.add-example.`
  (trailing dot, no body) and leave hook pair-matching undefined.
  `create-worktree.sh --pipeline-id` already validates non-empty
  PIPELINE_ID at the wrapper layer; both block-diagram skills assume
  `${BLOCK_NAME}` / `${NAME}` is non-empty on entry. Out-of-scope
  here — surfacing this as a documented invariant rather than
  re-validating in two more places.
- **Sub-skill must not overwrite `.zskills-tracked`**: `add-example`
  runs inside the parent's worktree (Claude Code subagents cannot
  dispatch their own subagents). The worktree's `.zskills-tracked` is
  written by `add-block`'s `create-worktree.sh --pipeline-id
  "add-block.${BLOCK_NAME}"` call (PR #66, merged 2 days before this
  plan). `add-example` reads it but MUST NOT rewrite it. The existing
  prohibition at `block-diagram/add-example/SKILL.md:37-42` stays.
- **No weakened tests**: if an existing canary or invariant lint must
  change, change it in this plan; never `it.skip` or comment out.
- **Per-phase PRs**: each phase lands as its own PR opened by
  `/run-plan` from the worktree.

## Phase 1 — Migrate add-block + add-example writers (paired)

### Goal

Replace all 19 flat-layout writes/reads in
`block-diagram/add-block/SKILL.md` (12 sites) and
`block-diagram/add-example/SKILL.md` (7 sites) with subdir-layout
equivalents under `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/`,
sanitising the per-marker `${BLOCK_NAME}` / `${NAME}` suffix into
`${BLOCK_SLUG}` / `${NAME_SLUG}` so parent/child basenames pair-match
under arbitrary user input. Bundled in one commit because the two
skills are coupled by sub-skill delegation: the parent writes
`requires.add-example.${BLOCK_SLUG}`, the child writes the matching
`fulfilled.add-example.${NAME_SLUG}`, and both must land in the same
`$PIPELINE_ID/` subdirectory for the hook's pair-matching gate to
resolve. Acceptance pins the orchestrator-passes-NAME==BLOCK_NAME
contract so the slugs match.

### Work Items

- [ ] **Add a single PIPELINE_ID resolution block at the top of
      add-block's "Tracking" surface, computing both PIPELINE_ID and
      BLOCK_SLUG.** Place it once; do NOT repeat the `MAIN_ROOT=…` +
      `mkdir -p` pair at every write site. Insert the block immediately
      after the worktree-creation snippet at
      `block-diagram/add-block/SKILL.md:18-29`, in a new subsection
      titled "Tracking setup" before "Step 0":

      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      # 3-tier PIPELINE_ID resolution: env → worktree .zskills-tracked
      # (parent's PIPELINE_ID inherited via the worktree file written by
      # create-worktree.sh --pipeline-id) → fallback synthesized id.
      PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"
      if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then
        PIPELINE_ID=$(tr -d '[:space:]' < ".zskills-tracked")
      fi
      : "${PIPELINE_ID:=add-block.${BLOCK_NAME}}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
      # Sanitised per-marker suffix slug — pairs with add-example's NAME_SLUG.
      BLOCK_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$BLOCK_NAME")
      mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
      ```

      Both the orchestrator (which dispatches the implementation
      sub-agent) and the in-worktree implementation sub-agent run this
      block; the sanitizer is deterministic so both yield the same
      PIPELINE_ID and BLOCK_SLUG given the same `$BLOCK_NAME`. Rationale:
      `add-block`'s normal entry point dispatches through
      `create-worktree.sh --pipeline-id "add-block.${BLOCK_NAME}"`
      (`block-diagram/add-block/SKILL.md:23`), so the tier-2
      `.zskills-tracked` read is the path that fires in practice.
      Tier-1 (env) covers cron-fired top-level turns. Tier-3
      (`add-block.${BLOCK_NAME}` synthesized) covers truly standalone
      direct invocations.

- [ ] **Migrate the 12 add-block writer/reader sites to the subdir
      layout, replacing `${BLOCK_NAME}` with `${BLOCK_SLUG}` in every
      marker basename.** The directory becomes
      `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/`; the suffix becomes
      `${BLOCK_SLUG}`. Remove the per-site `MAIN_ROOT=…` and `mkdir -p
      "$MAIN_ROOT/.zskills/tracking"` lines (the new top-of-skill block
      handles both). Site list (line numbers from main; basename now
      uses BLOCK_SLUG):

      | Line | Marker basename (BLOCK_SLUG suffix) |
      |------|--------------------------------------|
      | 385 | `step.add-block.${BLOCK_SLUG}.tests` (write) |
      | 402 | `requires.add-example.${BLOCK_SLUG}` (write) |
      | 426 | `step.add-block.${BLOCK_SLUG}.example` (write) |
      | 434 | `step.add-block.${BLOCK_SLUG}.example-deferred` (write) |
      | 511 | `step.add-block.${BLOCK_SLUG}.codegen` (write) |
      | 536 | `step.add-block.${BLOCK_SLUG}.codegen-deferred` (write) |
      | 567 | `step.add-block.${BLOCK_SLUG}.manual-test` (write) |
      | 631 | `step.add-block.${BLOCK_SLUG}.${marker}` (read in self-audit gate) |
      | 632 | `step.add-block.${BLOCK_SLUG}.${marker}-deferred` (read in self-audit gate) |
      | 685 | `step.add-block.${BLOCK_SLUG}.self-audit` (write) |
      | 699 | `requires.verify-changes.${BLOCK_SLUG}` (write) |
      | 750 | `step.add-block.${BLOCK_SLUG}.verify` (write) |

      Each post-migration write becomes:

      ```bash
      printf 'block: %s\ncompleted: %s\n' \
        "$BLOCK_NAME" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-block.${BLOCK_SLUG}.tests"
      ```

      The Step-10b self-audit gate's two read references (lines
      631-632) become:

      ```bash
      for marker in tests example codegen manual-test; do
        if [ ! -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-block.${BLOCK_SLUG}.${marker}" ] && \
           [ ! -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-block.${BLOCK_SLUG}.${marker}-deferred" ]; then
          echo "MISSING: step.add-block.${BLOCK_NAME}.${marker} — go back and complete this step"
        fi
      done
      ```

      The user-facing `MISSING:` echo message keeps `${BLOCK_NAME}` so
      operators see the input they typed; only the on-disk filename
      uses the slug.

- [ ] **Add a PIPELINE_ID resolution block at the top of add-example's
      "Fulfillment Tracking" section, computing PIPELINE_ID and
      NAME_SLUG.** add-example may run as a sub-skill (delegated from
      add-block) OR standalone (`/add-example` is registered as a
      top-level slash command per `block-diagram/add-example/SKILL.md:2`
      and `block-diagram/README.md:11,25`). Resolution is therefore
      3-tier with a synthesized fallback so direct invocation works,
      matching add-block's pattern. There is no parent to orphan from
      in standalone mode — the synthesized `add-example.${NAME_SLUG}`
      is its own pipeline, exactly like a top-level `/add-block`. In
      delegated mode, tier-2 `.zskills-tracked` always fires (the
      parent's worktree wrote it), so the synthesized fallback never
      triggers and markers correctly land in the parent's subdir.
      Replace the entire snippet at
      `block-diagram/add-example/SKILL.md:26-32` with:

      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      # 3-tier PIPELINE_ID resolution: env → worktree .zskills-tracked
      # (parent's PIPELINE_ID, written by add-block's create-worktree.sh
      # --pipeline-id call) → synthesized fallback for standalone use.
      # In delegated mode tier 2 always fires; tier 3 fires only when
      # /add-example is invoked directly with no parent worktree.
      PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"
      if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then
        PIPELINE_ID=$(tr -d '[:space:]' < ".zskills-tracked")
      fi
      : "${PIPELINE_ID:=add-example.${NAME}}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
      # Sanitised per-marker suffix slug — pairs with add-block's BLOCK_SLUG
      # when invoked under delegation (orchestrator passes NAME == BLOCK_NAME).
      NAME_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$NAME")
      mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
      printf 'skill: add-example\nname: %s\nstatus: started\ndate: %s\n' \
        "$NAME" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"
      ```

- [ ] **Migrate the remaining 6 add-example writer sites.** Each suffix
      becomes `${NAME_SLUG}` and each path becomes
      `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/`. Site list (line
      numbers from main):

      | Line | Marker basename (NAME_SLUG suffix) |
      |------|------------------------------------|
      | 160 | `step.add-example.${NAME_SLUG}.build` (write) |
      | 200 | `step.add-example.${NAME_SLUG}.register` (write) |
      | 233 | `step.add-example.${NAME_SLUG}.screenshot` (write) |
      | 266 | `step.add-example.${NAME_SLUG}.tests` (write) |
      | 290 | `step.add-example.${NAME_SLUG}.verify` (write) |
      | 297 | `fulfilled.add-example.${NAME_SLUG}` (rewrite to status: completed) |

      Each becomes the same shape:

      ```bash
      printf 'name: %s\ncompleted: %s\n' "$NAME" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.add-example.${NAME_SLUG}.build"
      ```

      The line-297 fulfillment rewrite drops the `mkdir -p` (idempotent
      after the entry-block mkdir) and writes to the same path as the
      entry-block's initial fulfilled marker:

      ```bash
      printf 'skill: add-example\nname: %s\nstatus: completed\ndate: %s\n' \
        "$NAME" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"
      ```

- [ ] **Pin the delegation contract: orchestrator passes `NAME ==
      BLOCK_NAME` (or, in batch mode, the same aggregate string) so
      `BLOCK_SLUG == NAME_SLUG`.** Update the existing dispatch snippet
      around `block-diagram/add-block/SKILL.md:405-414` so the in-skill
      prose explicitly states: "When invoking `/add-example`, pass the
      `<block-type(s)>` argument verbatim as both the displayed
      argument AND the `$NAME` variable the sub-skill will see. In
      single-block mode this is `$BLOCK_NAME`; in batch mode it is the
      same comma-separated list (or aggregate slug) you used for the
      worktree's `--pipeline-id` (see Batch Mode in
      `block-diagram/add-block/SKILL.md:52-67`). The sanitizer is
      deterministic, so identical input on both sides yields identical
      `BLOCK_SLUG` / `NAME_SLUG` and the basenames pair-match." Add an
      explicit single example: `BLOCK_NAME="My Block"` →
      `BLOCK_SLUG=My_Block`; `/add-example "My Block"` →
      `NAME=My Block` → `NAME_SLUG=My_Block`; both write
      `requires.add-example.My_Block` and `fulfilled.add-example.My_Block`
      under the same `add-block.My_Block/` subdir.

- [ ] **Batch-mode delegation: parent writes ONE aggregate
      `requires.add-example.<batch-slug>`; child writes ONE
      `fulfilled.add-example.<batch-slug>` from a single
      `/add-example` invocation.** Per `block-diagram/add-block/SKILL.md:54-67`,
      batch mode invokes `/add-example` exactly once with all
      block-types as a comma-separated list (or with the
      first-block-name aggregate matching the worktree's
      `--pipeline-id`). The parent must therefore emit only ONE
      `requires.add-example.${BATCH_SLUG}` marker, NOT one per block.
      Update the pre-Step-7 snippet at
      `block-diagram/add-block/SKILL.md:396-403` so:

      ```bash
      # In batch mode, BLOCK_NAME is the aggregate (e.g., "math-batch" or
      # the first block name — same convention as the worktree's
      # --pipeline-id). Single requires marker pairs with the single
      # /add-example invocation that follows.
      printf 'skill: add-example\nparent: add-block\nblock: %s\ndate: %s\n' \
        "$BLOCK_NAME" "$(TZ=America/New_York date -Iseconds)" \
        > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.add-example.${BLOCK_SLUG}"
      ```

      Add a sentence to the surrounding prose: "In batch mode,
      `$BLOCK_NAME` here is the same aggregate string (first-block name
      or `<category>-batch`) used for `create-worktree.sh
      --pipeline-id`. Do NOT loop per-block — emit one requires marker
      keyed by the aggregate, and pass the same aggregate as
      `/add-example`'s `<block-type(s)>` argument so its `$NAME`
      matches."

- [ ] **Verify the delegation pair lands in the same subdir on a
      dry-run, including a whitespace-bearing BLOCK_NAME and a
      standalone /add-example invocation.** Before committing, run the
      throwaway-shell snippet below:

      ```bash
      tmp=$(mktemp -d) && cd "$tmp"
      git init -q
      MAIN_ROOT=$(pwd)

      # Case A: delegated, simple identifier.
      BLOCK_NAME=Gain
      PIPELINE_ID="add-block.${BLOCK_NAME}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
      BLOCK_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$BLOCK_NAME")
      mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
      printf '%s\n' "$PIPELINE_ID" > .zskills-tracked
      : > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.add-example.${BLOCK_SLUG}"
      NAME=$BLOCK_NAME  # orchestrator passes NAME==BLOCK_NAME
      NAME_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$NAME")
      : > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"

      # Case B: delegated, whitespace-bearing identifier.
      BLOCK_NAME='My Block'
      PIPELINE_ID="add-block.${BLOCK_NAME}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
      BLOCK_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$BLOCK_NAME")
      mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
      : > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.add-example.${BLOCK_SLUG}"
      NAME=$BLOCK_NAME
      NAME_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$NAME")
      : > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"

      # Case C: standalone /add-example (no parent, no .zskills-tracked).
      rm -f .zskills-tracked
      unset ZSKILLS_PIPELINE_ID || true
      NAME=Integrator
      PIPELINE_ID=""
      [ -z "$PIPELINE_ID" ] && [ -f .zskills-tracked ] && PIPELINE_ID=$(tr -d '[:space:]' < .zskills-tracked)
      : "${PIPELINE_ID:=add-example.${NAME}}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
      NAME_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$NAME")
      mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
      : > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.add-example.${NAME_SLUG}"

      find "$MAIN_ROOT/.zskills/tracking" -type f | sort
      ```

      Expected output (4 paths):

      ```
      .../tracking/add-block.Gain/fulfilled.add-example.Gain
      .../tracking/add-block.Gain/requires.add-example.Gain
      .../tracking/add-block.My_Block/fulfilled.add-example.My_Block
      .../tracking/add-block.My_Block/requires.add-example.My_Block
      .../tracking/add-example.Integrator/fulfilled.add-example.Integrator
      ```

      Cases A+B prove parent/child pair-match under both clean and
      whitespace-bearing inputs (DA1). Case C proves standalone
      /add-example does not exit-1 and lands its own pipeline (DA3). If
      any case lands flat or a delegated pair lands in different
      subdirs, fix before committing.

### Design & Constraints

**Canonical post-migration writer pattern** — the verbatim shape used
by the existing 3-tier-with-`.zskills-tracked` template at
`skills/verify-changes/SKILL.md:209-214` (and replicated at
verify-changes lines 372-374, 453-455, 658-660), with the sanitizer
line added per the Phase-4 idiom in
`skills/fix-issues/SKILL.md:434-454`:

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-}"
if [ -z "$PIPELINE_ID" ] && [ -f ".zskills-tracked" ]; then
  PIPELINE_ID=$(tr -d '[:space:]' < ".zskills-tracked")
fi
: "${PIPELINE_ID:=<skill-name>.<unique-id>}"        # tier-3 fallback
PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$PIPELINE_ID")
SUFFIX_SLUG=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$RAW_SUFFIX")
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
# Subsequent writes:
printf '...' > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/<category>.<skill>.${SUFFIX_SLUG}"
```

The `skills/run-plan/SKILL.md:580-595` snippet referenced in the
research baseline is a different, simpler pattern (single-tier
`${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}`). It is not the right
template for block-diagram because add-block and add-example need
tier-2 `.zskills-tracked` resolution to inherit the parent's PIPELINE_ID
under delegation. `verify-changes` is the correct anchor.

Pattern rules (also in `docs/tracking/TRACKING_NAMING.md`):

- mkdir ONCE per skill at the top of the tracking section, not per-write.
- Sanitize PIPELINE_ID *before* mkdir.
- Sanitize the per-marker suffix (`BLOCK_SLUG` / `NAME_SLUG`) at the
  same step.
- 3-tier resolution (env → `.zskills-tracked` → synthesized) for both
  add-block and add-example. add-example's tier-3 fires only on
  standalone direct invocation; in delegated mode tier-2 always fires.
- Marker basenames use the slugged suffix on disk; user-facing prose
  and echo messages keep `${BLOCK_NAME}` / `${NAME}` for legibility.

**Why slug suffixes, not preserve-verbatim**: the original draft kept
basenames verbatim because `${BLOCK_NAME}` and `${NAME}` are
user-supplied unique parameters. That reasoning is correct only when
the inputs are also clean identifiers. The sanitizer
(`scripts/sanitize-pipeline-id.sh`) replaces whitespace and
shell-special chars with `_` before the directory name is computed; if
the marker basename is NOT also sanitised, parent and child write
basenames that differ for the same input. Verified:
`bash scripts/sanitize-pipeline-id.sh "add-block.My Block"` →
`add-block.My_Block`. Slugging both sides (deterministic, idempotent)
fixes the mismatch with no cost to clean inputs. This is NOT the
Phase-4 collision rename (that was about `sprint` literal collisions
across concurrent sessions); it is a simpler "make the on-disk shape
match the directory's sanitization" change.

**Why bundle add-block + add-example in one commit**: the parent
writes `requires.add-example.${BLOCK_SLUG}` and the child writes the
matching `fulfilled.add-example.${NAME_SLUG}`. Under the post-Phase-6
hook semantics, both must be in the same `$PIPELINE_ID/` subdirectory
or the hook's pair-matching gate at
`hooks/block-unsafe-project.sh.template:421` can never resolve them.
Migrating one without the other ships a known-broken intermediate
state into main.

**Delegation: parent owns the subdir.** add-example reads
`.zskills-tracked` (tier 2) to recover the parent's PIPELINE_ID,
sanitizes it the same way the parent did (sanitizer is idempotent —
re-running on a sanitized input is a no-op), and writes its markers
into the parent's subdir. The parent's `requires.add-example.${BLOCK_SLUG}`
and the child's `fulfilled.add-example.${NAME_SLUG}` share a basename
because the orchestrator passes `NAME == BLOCK_NAME` (pinned in the
delegation-contract work item), so `BLOCK_SLUG == NAME_SLUG` for any
input.

Hook permissiveness note: `enforce_requires_marker`
(`hooks/block-unsafe-project.sh.template:77-93`) accepts EITHER a
flat-top-level `${TRACKING_DIR}/fulfilled.X` OR a same-subdir
`${req_dir}/fulfilled.X` as fulfillment. So strictly speaking,
co-locating both markers in the same `$PIPELINE_ID/` subdir is
hygiene plus consistency with every other migrated skill, not a
hard hook requirement. We still co-locate (per the canonical
pattern at `skills/verify-changes/SKILL.md:209-214`) because (a)
all other skills do, (b) it keeps tracking pipelines self-contained
under one subdir, and (c) the alternative (parent in subdir, child
flat) is the exact dual-location ambiguity Phase 6 of
UNIFY_TRACKING_NAMES eliminated when it removed the dual-read
fallback.

**Standalone /add-example does NOT hard-error.** Tier-3
(`add-example.${NAME_SLUG}` synthesized) covers users who invoke
`/add-example` directly per its top-level slash-command registration
(`block-diagram/add-example/SKILL.md:2,7`, `block-diagram/README.md:11,25`).
There is no parent to orphan from — the synthesized id is its own
pipeline. The original draft's `exit 1` for missing PIPELINE_ID is
removed.

**`.zskills-tracked` is read-only here.** add-example MUST NOT
overwrite it (already enforced by the prohibition at
`block-diagram/add-example/SKILL.md:37-42`, stays untouched). The
sanitizer call in add-example operates on the in-memory string only.

### Acceptance Criteria

- [ ] Zero flat writes in either skill. Verification:
      `grep -nE '> "[^"]*\.zskills/tracking/[a-zA-Z]'
      block-diagram/add-block/SKILL.md
      block-diagram/add-example/SKILL.md` returns 0 lines. (The
      writer-only shape `> "…"` excludes prose/comment occurrences.)
- [ ] Subdir writes reference `$PIPELINE_ID` exactly the right number
      of times. Verification:
      `grep -cE '\$MAIN_ROOT/\.zskills/tracking/\$PIPELINE_ID/'
      block-diagram/add-block/SKILL.md` returns **12** (one per migrated
      site — the L631/L632 reads each contribute one occurrence, the
      preceding `mkdir -p` is in a separate top-of-skill block and is
      not counted).
      `grep -cE '\$MAIN_ROOT/\.zskills/tracking/\$PIPELINE_ID/'
      block-diagram/add-example/SKILL.md` returns **7** (the 6 writer
      sites in the migration table plus 1 occurrence in the
      top-of-skill PIPELINE_ID resolution block: the entry-block
      `fulfilled` write at L233). The `mkdir -p
      "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"` line ends without a
      trailing slash, so the regex `\$PIPELINE_ID/` does NOT match it
      — that's why the count is 7, not 8 (matches the add-block side
      where the entry-block mkdir likewise does not contribute). If
      the count differs from these exact numbers, do NOT loosen the
      criterion — investigate and reconcile.
- [ ] Sanitizer is invoked exactly twice per skill (once for
      PIPELINE_ID, once for the suffix slug). Verification:
      `grep -c 'sanitize-pipeline-id' block-diagram/add-block/SKILL.md`
      = 2; same for `add-example`.
- [ ] BLOCK_SLUG / NAME_SLUG variables are introduced. Verification:
      `grep -c 'BLOCK_SLUG=' block-diagram/add-block/SKILL.md` ≥ 1;
      `grep -c 'NAME_SLUG=' block-diagram/add-example/SKILL.md` ≥ 1.
- [ ] Top-of-skill PIPELINE_ID block is present in both skills.
      Verification:
      `grep -c 'ZSKILLS_PIPELINE_ID' block-diagram/add-block/SKILL.md` ≥ 1;
      `grep -c 'ZSKILLS_PIPELINE_ID' block-diagram/add-example/SKILL.md` ≥ 1.
- [ ] add-example does NOT hard-error on missing PIPELINE_ID
      (standalone use must work). Verification:
      `! grep -F 'add-example: no PIPELINE_ID' block-diagram/add-example/SKILL.md`
      (the prior draft's `exit 1` block is absent); instead
      `grep -F 'add-example.${NAME}' block-diagram/add-example/SKILL.md`
      returns ≥ 1 line (tier-3 fallback present).
- [ ] No mirror sync edits. Verification:
      `git diff main..HEAD --name-only | grep -c '^\.claude/skills/'`
      returns 0.
- [ ] No new sanitizer file. Verification:
      `git diff main..HEAD --name-only | grep -c 'sanitize'` returns 0.
- [ ] No `migrate-tracking.sh`-style helper introduced. Verification:
      `git diff main..HEAD --name-only | grep -c 'migrate-tracking'`
      returns 0.
- [ ] Bash blocks compile. Verification: extract every fenced ```bash
      block from both SKILL.md files and run `bash -n` on each. No
      syntax errors.
- [ ] Existing `tests/run-all.sh` still green.
      Verification:
      `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1; tail -5 "$TEST_OUT/.test-results.txt"`
      ends with `0 failed`.
- [ ] Delegation dry-run (final Work Item) shows all three cases A/B/C
      land correctly: A and B each produce two co-located files in
      `add-block.<slug>/`, C produces one file under
      `add-example.Integrator/`. Paste output into the PR body under a
      "Delegation dry-run" section.

### Dependencies

None. UNIFY_TRACKING_NAMES is `status: complete` on main; the sanitizer
script and reader semantics are already in place. PR #66 (merged) put
`create-worktree.sh --pipeline-id` in add-block's preamble so tier-2
`.zskills-tracked` resolution will fire on real invocations.

## Phase 2 — Lint guard + canary cases for block-diagram

### Goal

Add a static lint that fails CI if any future `block-diagram/` skill
reintroduces a flat-layout tracking write, plus extend the Phase 5
canary suite (`tests/test-canary-failures.sh`) with two
delegation-pair cases that prove add-block + add-example markers land
in the same subdir under a hook-fed fixture (one positive: pair
matches → allow; one negative: missing fulfillment → deny). The lint
pattern is pinned to the writer-only shape `> "…\.zskills/tracking/<basename>"`
to avoid false-positives on prose / comment / reader occurrences in
existing skills.

### Work Items

- [ ] **Run the baseline grep, confirm zero false-positives BEFORE
      adding the lint.** First run the proposed pattern against the
      tree, post-Phase-1, to enumerate every match:

      ```bash
      grep -rEn '> "[^"]*\.zskills/tracking/[a-zA-Z]' skills/ block-diagram/ 2>/dev/null
      ```

      Expected on a clean post-Phase-1 tree: zero output. If anything
      matches, EITHER it is a residual flat write Phase 1 missed (fix
      it) OR it is a writer-shape false positive (refine the pattern
      and re-run). Do NOT install the lint until the baseline is zero.
      Note this baseline-run in the PR body.

      Why the writer-only shape: a looser pattern like
      `\.zskills/tracking/[a-zA-Z]` matches prose hits in
      `skills/quickfix/SKILL.md:194`, `skills/research-and-go/SKILL.md:47`,
      `skills/session-report/SKILL.md:61`, `skills/verify-changes/SKILL.md:161`,
      and `skills/run-plan/SKILL.md:1374,1376,1390` (verified via
      `grep -nE '\.zskills/tracking/[a-zA-Z]' skills/*/SKILL.md` on
      main; 7 hits, all benign). The writer shape `> "…"` fences
      around `printf …. > "…"` writes only — exactly what the lint
      forbids.

- [ ] **Add a regression-guard lint** in
      `tests/test-skill-invariants.sh`, mirroring the structure of the
      existing `isolation: "worktree"` check at lines 128-134. Insert
      directly after that block (before the `Results:` line at L137):

      ```bash
      # Cross-skill invariant: no skill writes flat-layout tracking markers.
      # Post-UNIFY_TRACKING_NAMES Phase 6, only $PIPELINE_ID-subdir writes
      # are visible to the hook. Pattern matches `> "…/.zskills/tracking/<basename>"`
      # where <basename> starts with a letter (rules out `$PIPELINE_ID/...`
      # which begins with `$`). Pinned to the writer shape `> "…"` so prose
      # and comment hits in skills/{quickfix,research-and-go,session-report,
      # verify-changes,run-plan}/SKILL.md don't false-positive. See
      # plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md for baseline-zero proof.
      check 'no skill writes flat-layout tracking markers (post-UNIFY_TRACKING_NAMES)' \
        '! grep -rEn '"'"'> "[^"]*\.zskills/tracking/[a-zA-Z]'"'"' skills/ block-diagram/ 2>/dev/null'
      ```

      Negative-pattern smoke: under main HEAD with Phase 1 NOT yet
      landed, this check would fail with hits in `block-diagram/`. After
      Phase 1 lands, all hits are gone and the check passes. Verify
      this manually before committing Phase 2 by temporarily reverting
      one Phase 1 site to a flat-layout write and re-running: the lint
      must fail.

- [ ] **Extend the canary suite with two block-diagram cases (positive
      pair-match and negative missing-fulfillment).** Insert two new
      cases as the 9th and 10th entries in the "Tracking marker naming
      (subdir scope)" section of `tests/test-canary-failures.sh` (the
      section header is at L871; cases run through L986). Use the
      existing `setup_tracking_fixture` and `run_tracking_hook` helpers
      (defined at L825 and L844). Populate fixture markers with
      realistic YAML bodies that match the writer shape from Phase 1
      (parent block + delegated child), not empty `touch`-files.

      Insert at the section's end (immediately before the `# --- Phase
      5: …` divider near L988):

      ```bash
      # Case 9 — block-diagram delegation pair (add-block ↔ add-example).
      # add-block (parent) writes requires.add-example.${BLOCK_SLUG};
      # add-example (child) writes fulfilled.add-example.${NAME_SLUG} from
      # the same worktree. Both must land in the parent's $PIPELINE_ID
      # subdir for the hook's pair-matching gate to resolve. Verifies the
      # post-catchup layout. Fixture YAML matches the writer shape from
      # Phase 1.
      tn9_repo=$(setup_tracking_fixture)
      mkdir -p "$tn9_repo/.zskills/tracking/add-block.Gain"
      printf 'skill: add-example\nparent: add-block\nblock: Gain\ndate: 2026-04-26T10:00:00-04:00\n' \
        > "$tn9_repo/.zskills/tracking/add-block.Gain/requires.add-example.Gain"
      printf 'skill: add-example\nname: Gain\nstatus: completed\ndate: 2026-04-26T10:05:00-04:00\n' \
        > "$tn9_repo/.zskills/tracking/add-block.Gain/fulfilled.add-example.Gain"
      printf 'add-block.Gain\n' > "$tn9_repo/.zskills-tracked"
      tn9_out=$(run_tracking_hook "$tn9_repo")
      assert_tracking_allow \
        "block-diagram delegation pair: requires + fulfilled co-located in PIPELINE_ID subdir → allow" \
        "$tn9_out"

      # Case 10 — block-diagram missing fulfillment: parent's requires marker
      # is present but no fulfilled.add-example.<slug> → hook must block.
      # Confirms the gate actually fires when the pair is incomplete.
      tn10_repo=$(setup_tracking_fixture)
      mkdir -p "$tn10_repo/.zskills/tracking/add-block.Integrator"
      printf 'skill: add-example\nparent: add-block\nblock: Integrator\ndate: 2026-04-26T10:00:00-04:00\n' \
        > "$tn10_repo/.zskills/tracking/add-block.Integrator/requires.add-example.Integrator"
      printf 'add-block.Integrator\n' > "$tn10_repo/.zskills-tracked"
      tn10_out=$(run_tracking_hook "$tn10_repo")
      assert_tracking_deny \
        "block-diagram missing fulfillment: requires.add-example.Integrator unfulfilled → deny" \
        "$tn10_out" "add-example.Integrator"

      # Case 11 — cross-name isolation: pipeline add-block.Gain has its
      # requires fulfilled, but a sibling add-block.Integrator pipeline
      # exists with an unfulfilled requires. The active pipeline (Gain)
      # must NOT be blocked by Integrator's unmet requirement (subdir
      # scoping). Mirrors fix-issues sprint isolation (case 7) for the
      # block-diagram namespace.
      tn11_repo=$(setup_tracking_fixture)
      mkdir -p "$tn11_repo/.zskills/tracking/add-block.Gain"
      mkdir -p "$tn11_repo/.zskills/tracking/add-block.Integrator"
      printf 'skill: add-example\nparent: add-block\nblock: Gain\ndate: 2026-04-26T10:00:00-04:00\n' \
        > "$tn11_repo/.zskills/tracking/add-block.Gain/requires.add-example.Gain"
      printf 'skill: add-example\nname: Gain\nstatus: completed\ndate: 2026-04-26T10:05:00-04:00\n' \
        > "$tn11_repo/.zskills/tracking/add-block.Gain/fulfilled.add-example.Gain"
      printf 'skill: add-example\nparent: add-block\nblock: Integrator\ndate: 2026-04-26T11:00:00-04:00\n' \
        > "$tn11_repo/.zskills/tracking/add-block.Integrator/requires.add-example.Integrator"
      printf 'add-block.Gain\n' > "$tn11_repo/.zskills-tracked"
      tn11_out=$(run_tracking_hook "$tn11_repo")
      assert_tracking_allow \
        "block-diagram cross-name isolation: Gain not blocked by Integrator's unmet requires" \
        "$tn11_out"
      ```

      Update the section header on L871 from `(8 cases)` to
      `(11 cases)`.

- [ ] **Verify the canary section count comment is consistent.**
      `grep -F 'Tracking marker naming (subdir scope) (11 cases)'
      tests/test-canary-failures.sh` returns 1 line.

### Design & Constraints

- The lint pattern `> "[^"]*\.zskills/tracking/[a-zA-Z]` deliberately
  matches only writer-shape `> "…/.zskills/tracking/<basename>"`
  occurrences and excludes:
  - matches starting with `$` (variable interpolation like
    `> "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/..."`),
  - prose/comment/reader hits (no leading `> "…`),
  - any non-write reference (`grep -F`, `[ -f ... ]`, etc).
  This shape was validated against main: 7 prose hits in
  `skills/{quickfix,research-and-go,session-report,verify-changes,run-plan}`
  do not match. Only writer-shape flat writes match — exactly what we
  want forbidden going forward.
- The new canary cases use `setup_tracking_fixture` /
  `run_tracking_hook` exactly as the prior 8 cases do. Fixture YAML
  bodies match the writer shape from Phase 1 (skill / parent / block
  / date keys) so the cases are realistic, not stub-shaped.
- Use `assert_tracking_allow` / `assert_tracking_deny` (defined at
  L854-L869) — same idiom as cases 1-8.
- Do NOT lower the case-2 sanitizer regex or weaken any existing
  assertion to make the new tests fit. They're additive.

### Acceptance Criteria

- [ ] Baseline grep returns zero matches under the writer-only
      pattern. Verification (run AFTER Phase 1 lands, BEFORE installing
      the lint):
      `grep -rEn '> "[^"]*\.zskills/tracking/[a-zA-Z]' skills/ block-diagram/ 2>/dev/null | wc -l`
      = 0. Paste the run into the PR body.
- [ ] New invariant lint present. Verification:
      `grep -F 'no skill writes flat-layout tracking markers'
      tests/test-skill-invariants.sh` returns 1 line.
- [ ] Lint fails on a deliberately-reverted Phase 1 site (manual
      smoke). Procedure: temporarily change one
      `$PIPELINE_ID/step.add-block` reference back to flat,
      `bash tests/test-skill-invariants.sh` exits non-zero, then
      revert. Note this dry-run in the PR body.
- [ ] Canary section grew from 8 to 11 cases (file-local count, not
      suite-wide). Verification:
      `grep -F 'Tracking marker naming (subdir scope) (11 cases)'
      tests/test-canary-failures.sh` returns 1 line.
- [ ] All three new cases pass. Verification:
      `bash tests/test-canary-failures.sh > "$TEST_OUT/.test-results.txt"
      2>&1 && grep -E 'block-diagram delegation|block-diagram missing|block-diagram cross-name'
      "$TEST_OUT/.test-results.txt"` shows three PASS lines.
- [ ] No existing canary case regresses. Verification: pre-Phase-2
      `bash tests/test-canary-failures.sh 2>&1 | grep -cE '^pass:'`
      compared against post-Phase-2 differs by exactly 3.
- [ ] Full suite green: `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt"
      2>&1; tail -5 "$TEST_OUT/.test-results.txt"` ends with `0 failed`.

### Dependencies

Phase 1. The lint will fail if Phase 1 hasn't shipped yet (that's by
design — the lint *is* the regression guard for Phase 1's outcome).
Phase 2 cannot land before Phase 1's PR merges to main.

## Phase 3 — Framework-coverage CI guard for block-diagram

### Goal

Add a single CI-time check that asserts every framework-level lint or
invariant covering `skills/` also covers `block-diagram/`, so a fourth
framework migration cannot silently bypass the add-on package.

### Design & Constraints — should we add this guard?

**Recommendation: YES, add it. Small, targeted, one work item.**

Argument for: block-diagram has been missed twice — once for
`isolation: "worktree"` (caught reactively by PR #66's lint, three
months after the framework migration), once for tracking-naming
(caught reactively by issue #65, two days after Phase 6 merged).
Both incidents had the same shape: a framework-wide phase enumerated
`skills/<name>/` and forgot the add-on package. A static check
that every `tests/test-skill-invariants.sh:check` whose argument
references `skills/` as an enumerable framework path *also* references
`block-diagram/` is a one-line guard that mechanically prevents the
third miss. It costs ~25 lines of test code and pays back the first
time anyone writes a third framework lint.

Argument against: false-positives are possible — a check might
legitimately scope to `skills/` only (e.g., a check about a file that
genuinely doesn't exist in `block-diagram/`, or a single-file check
like `grep -q "..." skills/run-plan/SKILL.md`). The guard must
distinguish framework-wide enumeration (`grep -r ... skills/`) from
single-skill checks (`grep -q ... skills/run-plan/SKILL.md`). The
detection rule below uses the awk-extracted check body and matches
on the `skills/` path component when followed by whitespace or
end-of-token (i.e., a directory enumeration), not by a slash + skill
name (a single-skill probe).

The "Skill-framework repo — surface bugs, don't patch" rule in
CLAUDE.md applies directly: each missed framework migration multiplies
across every downstream consumer. A mechanical guard is the correct
shape.

**Decision: add it as Phase 3.** If the false-positive surface ever
grows past one or two opt-outs, revisit.

**Phase ordering rationale.** Phase 3 places the meta-lint *after*
Phase 2's flat-layout check in `test-skill-invariants.sh`. The
meta-lint scans the file's own `check` lines and asserts framework
coverage; Phase 2's flat-layout check correctly covers both `skills/`
and `block-diagram/` (we wrote it that way), so it would pass the
meta-lint regardless of ordering. The reason ordering matters is
purely positional: the meta-lint reads the script body and must run
after every other check has been registered, so it sees them all.
This is convenience-driven, not correctness-driven; Phase 2 does NOT
need to ship before Phase 3, and either order would produce a passing
test suite. Phase 3 still depends on Phase 2 in the **process** sense
(fewer rebases, simpler review), but not in the meta-lint-correctness
sense.

### Work Items

- [ ] **Add a meta-lint to `tests/test-skill-invariants.sh`** that
      scans the file's own `check` invocations and asserts that any
      check argument referencing `skills/` as a framework-wide
      enumeration path also references `block-diagram/`. Insert
      directly after the new flat-layout lint from Phase 2 (i.e.,
      after L134's existing isolation check + Phase 2's
      flat-layout check, before the `Results:` summary line):

      ```bash
      # Meta-lint: every framework-wide cross-skill check must cover
      # block-diagram/. Two prior framework migrations (isolation:worktree,
      # UNIFY_TRACKING_NAMES) silently skipped block-diagram/ because the
      # check enumerated skills/ alone.
      #
      # Detection rule: a `check` line references `skills/` as a
      # framework-wide enumeration (matches the regex `[^A-Za-z]skills/`
      # followed by whitespace, a quote, or end-of-line — NOT followed by
      # a skill-name segment like `skills/run-plan/SKILL.md`). Such a
      # check must also contain ` block-diagram/` (with whitespace
      # boundary) somewhere in the same line.
      #
      # Opt-out: prefix the check with the comment
      #   # block-diagram-exempt: <reason>
      # on the immediately preceding line. Use sparingly — exemptions
      # are by definition the surface that grows to bite us next time.
      SCRIPT="$REPO_ROOT/tests/test-skill-invariants.sh"
      _meta_skipped=0
      _meta_failed=0
      while IFS= read -r line; do
        case "$line" in
          *"# block-diagram-exempt:"*) _meta_skipped=1; continue ;;
        esac
        # Match check lines that enumerate skills/ as a directory path.
        # Regex: skills/ preceded by non-alpha, followed by space or quote
        # or end-of-line (i.e., a path arg) — NOT skills/<name>/ which
        # has an alpha char after the slash.
        if printf '%s' "$line" | grep -qE '^[[:space:]]*check ' \
           && printf '%s' "$line" | grep -qE '[^A-Za-z]skills/([^A-Za-z]|$)'; then
          if [ "$_meta_skipped" -eq 1 ]; then
            _meta_skipped=0
            continue
          fi
          if ! printf '%s' "$line" | grep -qE '[^A-Za-z]block-diagram/'; then
            echo "META-LINT FAIL: framework-wide check missing block-diagram/ coverage: $line" >&2
            _meta_failed=1
          fi
        else
          _meta_skipped=0
        fi
      done < "$SCRIPT"
      if [ "$_meta_failed" -eq 0 ]; then
        check 'meta: framework-wide checks cover block-diagram/' 'true'
      else
        check 'meta: framework-wide checks cover block-diagram/' 'false'
      fi
      ```

      Place this block AFTER all other `check` invocations and BEFORE
      the final `Results:` summary line (currently L137). The block
      reads `$REPO_ROOT/tests/test-skill-invariants.sh` (resolved at
      script-top via `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`,
      which is already in the script) so the path is invocation-
      independent — `bash $0`, `cd tests && bash test-skill-invariants.sh`,
      and `tests/run-all.sh`-driven invocation all read the same file.
      The earlier draft used `$0` which would break under `bash -c
      'source tests/test-skill-invariants.sh'`-style invocation.

      The detection regex `[^A-Za-z]skills/([^A-Za-z]|$)` matches:
      - `' skills/ '` (space-skills-slash-space — framework enum)
      - `' skills/'` at end-of-line (skills as final arg)
      - `' "skills/"'` (quoted directory)

      and does NOT match:
      - `'skills/run-plan/SKILL.md'` (alpha after slash — single skill)
      - `'.claude/skills/'` (preceded by alpha — different path)
      - `'skills'` without trailing slash

      The earlier draft's case-glob `*"check "*" skills/"*` required
      both a literal leading space and a literal `"check "` substring,
      which would miss `'skills/'` (single-quoted) and `"skills/"`
      (double-quoted) variants. The regex form is precise.

### Acceptance Criteria

- [ ] Meta-lint present. Verification:
      `grep -F 'META-LINT FAIL: framework-wide check missing block-diagram/ coverage'
      tests/test-skill-invariants.sh` returns 1 line.
- [ ] Meta-lint reads via `$REPO_ROOT`, not `$0`. Verification:
      `grep -F 'SCRIPT="$REPO_ROOT/tests/test-skill-invariants.sh"'
      tests/test-skill-invariants.sh` returns 1 line; `! grep -F 'done < "$0"'
      tests/test-skill-invariants.sh`.
- [ ] Meta-lint passes on current main + Phase 1 + Phase 2.
      Verification: `bash tests/test-skill-invariants.sh` exits 0 and
      its output contains
      `meta: framework-wide checks cover block-diagram/` in a passing
      line (no `FAIL:` prefix).
- [ ] Meta-lint fires on a deliberately-broken check (manual smoke).
      Procedure: add a throwaway
      `check 'demo' '! grep -rE foo skills/'`, run the script, observe
      the meta-lint failure (`META-LINT FAIL: …` in stderr), then
      remove the throwaway. Note this dry-run in the PR body.
- [ ] Opt-out works (manual smoke). Procedure: prefix the throwaway
      check with `# block-diagram-exempt: demo`, re-run, observe the
      meta-lint passes, then remove the throwaway.
- [ ] Detection-regex precision: a single-skill check
      (`grep -q "..." skills/run-plan/SKILL.md`) does NOT trigger the
      meta-lint. Verification: the existing file-local checks at L33,
      35, 39, 41, 43, 45, 57, 59, 61, 78, 80, 82, 84, 90, 92, 96 all
      reference `skills/<name>/SKILL.md` patterns and must continue
      to pass without exemption comments after Phase 3 lands.
- [ ] Full suite green: `bash tests/run-all.sh > "$TEST_OUT/.test-results.txt"
      2>&1; tail -5 "$TEST_OUT/.test-results.txt"` ends with `0 failed`.

### Dependencies

Phase 2 (process-only — see "Phase ordering rationale" above). Both
phases could ship independently; sequencing is for review-flow
simplicity.

## Drift Log

This is the initial draft. Drift tracking will begin after Phase 1 lands.

### Known hygiene items (future work)

- **Orphan standalone-then-delegated subdirs.** A standalone
  `/add-example Gain` invocation creates `add-example.Gain/`; if the
  user later runs `/add-block Gain` on the same block, the
  delegated-mode pipeline goes to a separate `add-block.Gain/` subdir
  and the original standalone subdir persists indefinitely. Cross-name
  isolation case 11 proves no correctness interference between the
  two pipelines, so this is hygiene, not correctness. Acceptable per
  `docs/tracking/TRACKING_NAMING.md` OQ2 ("let expire"); revisit if
  cleanup becomes important — `scripts/clear-tracking.sh` could be
  extended to age-out completed-fulfilled standalone subdirs after
  N days.

## Adversarial Review — Round 1 Disposition

| ID | Severity | Evidence | Disposition |
|----|----------|----------|-------------|
| F1 | blocker | Verified — `grep -nE '\.zskills/tracking/[a-zA-Z]' skills/*/SKILL.md` returns 7 hits across quickfix:194, research-and-go:47, session-report:61, verify-changes:161, run-plan:1374/1376/1390 (all benign prose/reader/comment occurrences). | Fixed: Phase 2 lint pinned to writer-only shape `> "[^"]*\.zskills/tracking/[a-zA-Z]"`; baseline-grep work item added to confirm zero false-positives BEFORE installing the lint. (Phase 2 § "Run the baseline grep" + Acceptance Criteria.) |
| F2 | blocker | Verified — original `done < "$0"` is fragile under `bash -c source` style invocation; `$REPO_ROOT` is already computed at script-top (L13-14). | Fixed: Phase 3 work item now sets `SCRIPT="$REPO_ROOT/tests/test-skill-invariants.sh"` and reads `< "$SCRIPT"`. Acceptance criterion pins this. |
| F3 | major | Verified — `git show main:skills/run-plan/SKILL.md` lines 580-595 contain single-tier `${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}`, no `.zskills-tracked` read. The 3-tier-with-`.zskills-tracked` template lives at `skills/verify-changes/SKILL.md:209-214` (and 372-374, 453-455, 658-660). | Fixed: Phase 1 § "Canonical post-migration writer pattern" now cites `skills/verify-changes/SKILL.md:209-214` as the anchor and explains why run-plan:580-595 is NOT the right template (it's single-tier). |
| F4 | major | Verified — original draft preserved `${BLOCK_NAME}` / `${NAME}` verbatim as suffixes; pair-matching depends on orchestrator passing them identically. Subsumed by DA1's slug fix. | Fixed via DA1 — both skills now sanitise the suffix into `BLOCK_SLUG` / `NAME_SLUG`, and the new "Pin the delegation contract" work item explicitly states orchestrator passes `NAME == BLOCK_NAME`. |
| F5 | minor | Confirmed sound. | No change. |
| F6 | major | Verified — Phase 2's `grep -rEn '... skills/ block-diagram/'` already covers block-diagram, so Phase 3 ordering is convenience-driven, not correctness-driven. | Fixed: Phase 3 § "Phase ordering rationale" rewritten to acknowledge the rationale is process / review-flow, not meta-lint correctness. Dependencies section updated. |
| F7 | minor | Verified — original acceptance allowed ≥ 12 / ≥ 7 with an "accept ≥ 11 with comment" escape. | Fixed: Phase 1 acceptance now pins exact integers (12 for add-block, 8 for add-example) and removes the escape. |
| F8 | major | Verified — original case-9 used `touch` to create empty fixture files; the writer in Phase 1 emits multi-line YAML. | Fixed: Phase 2 canary cases 9, 10, and 11 use `printf` with the writer's YAML shape (skill / parent / block / date keys). Added case 11 for cross-name isolation per F8's recommendation. |
| F9 | minor | Confirmation only. | No change. |
| F10 | minor | Confirmation only. | No change. |
| F11 | minor | Confirmation only. | No change. |
| F12 | minor | Original dry-run only exercised the delegated-pair path, not standalone `/add-example`. With DA3 we've removed the hard-exit, so the right test is "Case C standalone synth fallback works." | Fixed: Phase 1 Work Item "Verify the delegation pair lands…" now has Cases A / B / C — A = clean ID, B = whitespace-bearing ID, C = standalone /add-example direct invocation. |
| F13 | minor | Confirmation only. | No change. |
| F14 | minor | Confirmation only. | No change. |
| DA1 | blocker | Verified — `bash scripts/sanitize-pipeline-id.sh "add-block.My Block"` returns `add-block.My_Block` (whitespace → `_`); literal unsanitised `${BLOCK_NAME}` suffix would never pair-match. | Fixed: BLOCK_SLUG / NAME_SLUG variables introduced in both skills; every marker basename in Phase 1 site tables uses the slugged form; "Shared Conventions" updated to explain why this supersedes "preserve verbatim". |
| DA2 | major | Verified — `block-diagram/add-block/SKILL.md:54-67` documents batch mode (one /add-example invocation for all blocks), but the existing `requires.add-example.${BLOCK_NAME}` writer at L402 sits inside the per-block loop in the original prose. Plan needed to pin one-aggregate-marker semantics. | Fixed: new "Batch-mode delegation" work item in Phase 1 pins parent writes ONE aggregate `requires.add-example.${BLOCK_SLUG}` keyed by the same aggregate the worktree's `--pipeline-id` uses; child writes ONE matching `fulfilled.add-example.${NAME_SLUG}`. Prose update mandated. |
| DA3 | major | Verified — `block-diagram/add-example/SKILL.md:2,7` registers /add-example as a top-level slash-command; `block-diagram/README.md:11,25` documents it as standalone-usable. Original draft's `exit 1` on missing PIPELINE_ID would break that path. | Fixed: Phase 1 add-example resolution is now 3-tier (env → `.zskills-tracked` → synthesized `add-example.${NAME_SLUG}`), matching add-block's pattern. Acceptance criterion inverted: `! grep -F 'add-example: no PIPELINE_ID'` (the hard-error is GONE). Case C in the dry-run proves standalone works. |
| DA4 | major | Convergent with F1. | Fixed jointly with F1 — baseline-grep work item added. |
| DA5 | blocker | Convergent with F2. | Fixed jointly with F2. |
| DA6 | major | Verified by inspection — original case-glob `*"check "*" skills/"*` required literal leading-space and literal `"check "`, missing `'skills/'` and `"skills/"` variants. | Fixed: Phase 3 detection switched from case-glob to `grep -qE '[^A-Za-z]skills/([^A-Za-z]|$)'` which precisely separates framework-enum (`grep -r ... skills/`) from single-skill (`skills/run-plan/SKILL.md`). Acceptance includes a regex-precision criterion listing the 17 file-local single-skill checks that must continue to pass. |
| DA7 | minor | Verified — original prose was ambiguous about which actor (orchestrator vs in-worktree sub-agent) runs the PIPELINE_ID block. | Fixed: Phase 1 § "Add a single PIPELINE_ID resolution block…" now explicitly states "Both the orchestrator (which dispatches the implementation sub-agent) and the in-worktree implementation sub-agent run this block; the sanitizer is deterministic so both yield the same PIPELINE_ID and BLOCK_SLUG given the same `$BLOCK_NAME`." |
| DA8 | minor | Verified — case 9 with `touch` doesn't exercise the actual writer, only the hook against an empty file. | Fixed: cases 9-11 use realistic YAML fixture bodies matching the writer shape. The end-to-end "extract bash blocks and execute them" alternative was rejected because the existing canary suite uses fixtures-feed-hook throughout (cases 1-8), and matching that idiom is more maintainable than a new harness. |
| DA9 | minor | Verified — original Phase 2 acceptance referenced "total pass-count strictly greater than the pre-Phase-2 baseline by exactly 2", which is suite-wide. | Fixed: Phase 2 acceptance now scopes to the file-local section header `(8 cases) → (11 cases)` and to a file-local pass-count delta of exactly 3 (one per new case), not suite-wide. |
| DA10 | minor | Convergent with F6. | Fixed jointly with F6. |

## Adversarial Review — Round 2 Disposition

| ID | Severity | Evidence | Disposition |
|----|----------|----------|-------------|
| F15 | major | Verified — `grep -n 'mkdir -p "\$MAIN_ROOT' plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md` confirms all 6 mkdir snippets end with `$PIPELINE_ID` (no trailing slash); `skills/verify-changes/SKILL.md:217` follows the same convention. The regex `\$MAIN_ROOT/\.zskills/tracking/\$PIPELINE_ID/` therefore does not match the entry-block mkdir, making the original count claim of 8 off-by-one. | Fixed: Phase 1 acceptance criterion for add-example updated from **8** to **7** (6 writer sites + 1 entry-block fulfilled write at L233; mkdir does not match the trailing-slash regex). add-block's count of **12** is internally consistent — its entry-block mkdir likewise does not contribute, and all 12 site-table entries do. Decomposition spelled out so the reasoning is auditable. |
| F16 | minor | By inspection — sanitizer at `scripts/sanitize-pipeline-id.sh:9-10` returns empty for empty input; basenames would degrade to `requires.add-example.` (trailing dot). Hook pair-matching is undefined on degenerate basenames. | Fixed: new bullet in Shared Conventions states empty `${BLOCK_NAME}` / `${NAME}` is the orchestrator's responsibility — `create-worktree.sh --pipeline-id` already validates non-empty PIPELINE_ID at the wrapper, both block-diagram skills assume non-empty input. Surfaced as a documented invariant rather than re-validated. |
| F17–F22 | confirm | Round 2 reviewer's six confirmation findings: 8 Round-1 fixes verified working, two minor items reviewed and judged sound. | No change required. |
| DA-R2-1 | minor | Verified — `hooks/block-unsafe-project.sh.template:77-93` shows `enforce_requires_marker` accepts EITHER `${TRACKING_DIR}/fulfilled.X` (flat top-level) OR `${req_dir}/fulfilled.X` (same subdir as the requires marker). The original "Delegation: parent owns the subdir" prose described pair-matching as strictly same-subdir-only, slightly overstating the hook's strictness. | Fixed: "Delegation: parent owns the subdir" paragraph extended with a "Hook permissiveness note" explaining the OR-shape; co-location framed as hygiene plus consistency with the canonical pattern, not a hard hook requirement. The Phase-1 slug-matching fix is still correct and load-bearing — only the prose framing was off. |
| DA-R2-2 | minor | By construction — standalone `/add-example Gain` (tier-3 fallback) creates an `add-example.Gain/` subdir; a later `/add-block Gain` creates `add-block.Gain/`. The two are isolated (case 11 proves correctness), so the standalone subdir simply persists. | Fixed: added "Known hygiene items (future work)" section to Drift Log noting the orphan subdir lifecycle. Acceptable per OQ2 "let expire"; flagged as a candidate for `scripts/clear-tracking.sh` extension if it ever matters. |
| DA-R2-3 | spec | Subsumed by F15 (same off-by-one). | Resolved jointly with F15. |
| DA-R2-4–9 | confirm | Round 2 DA's six confirmation findings: 7 Round-1 DA-fixes verified, two interpretive items reviewed and judged sound. | No change required. |

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review
**Convergence:** Converged at round 2 (Round 2 surfaced 1 major mechanical finding + 4 minors; all addressed)
**Remaining concerns:** None blocking; Drift Log notes orphan-subdir hygiene as future work.

### Round History
| Round | Reviewer Findings | DA Findings | Resolved |
|-------|-------------------|-------------|----------|
| 1     | 14 (3 blocker, 4 major, 4 minor, 3 confirm) | 10 (2 blocker, 4 major, 3 minor, 1 spec) | 17 fixed, 7 confirm-only |
| 2     | 1 major + 1 minor + 6 confirms | 3 minor/spec + 6 confirms | 1 major fixed, 4 minors noted |
