---
title: Unify Tracking-Marker File-Naming Convention
created: 2026-04-17
status: complete
---

# Plan: Unify Tracking-Marker File-Naming Convention

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

The reader in `hooks/block-unsafe-project.sh.template` applies a
PIPELINE_ID scope filter to tracking markers at 9 sites (lines 251,
264, 276, 359, 372, 384, 460, 473, 485). The filter strips the
orchestrator-prefix from PIPELINE_ID and expects marker basenames to
end with the stripped suffix. Writers across 5+ skills use
inconsistent suffix schemes (`$TRACKING_ID`, literal `sprint`, integer
`$i`, `$ISSUE_NUMBER`, `$TASK_SLUG`), so the filter misbehaves in
specific scenarios:

1. **Concurrent pipelines with the same slug** (e.g., re-running a
   plan after a failure) cross-fulfill each other's markers, violating
   the parallel-pipelines-are-core requirement.
2. **`fix-issues.sprint` collides** when two sprints run
   concurrently — both share the literal `sprint` suffix.
3. **research-and-go's integer markers** (`requires.run-plan.$i`) are
   invisible to its own session's scope filter — in most cases this
   is intentional (research-and-go never commits code itself), but the
   design isn't documented anywhere and is fragile.

This plan unifies the naming convention to eliminate the real bugs
(collisions #1 and #2), clarifies the intentional design decisions
(integer markers are spawn-metadata, not enforcement), and adds canary
tests that lock in the new scheme.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Decide scheme & document | ✅ | `261fd4c` | Option B (per-pipeline subdirs) |
| 2 — Reader changes | ✅ | `6000f3c` | hook dual-read + sanitizer + migration |
| 3 — Writer migration pass 1 ($TRACKING_ID skills) | ✅ | `b31adec` | run-plan, draft-plan, refine-plan, verify-changes |
| 4 — Writer migration pass 2 (fix-issues, r&g, r&p, do) | ✅ | `c14fd5c` | SPRINT_ID, meta.* prefix, sanitizer |
| 5 — Canary + integration test coverage | ✅ | `70ae07c` | +11 canary + tracking-integration suite |
| 6 — E2E validation + dual-read removal | ✅ | `d9efce1` | 11/11 e2e pass; 9 fallback blocks removed |

## Shared Conventions

All phases respect these invariants:

- **Marker location**: `.zskills/tracking/` (never `.claude/`).
- **Source + mirror**: every `skills/<name>/SKILL.md` change is followed
  by `cp -r skills/<name>/ .claude/skills/<name>/` in the same commit.
  Never edit `.claude/skills/` directly (triggers permission storms per
  `feedback_claude_skills_permissions.md`).
- **Hook source is the template only**. `hooks/block-unsafe-project.sh.template`
  is the ONLY project-scoped hook file in this repo (a non-template
  `block-unsafe-project.sh` does not exist here — it's generated in target
  projects by `scripts/update-zskills-install.sh`-equivalent machinery at
  install time, with placeholder substitutions for FULL_TEST_CMD,
  UNIT_TEST_CMD, UI_FILE_PATTERNS). Verification: `ls hooks/` shows
  `block-agents.sh.template`, `block-unsafe-generic.sh`,
  `block-unsafe-project.sh.template`, `canary3-bad.sh` — no
  `block-unsafe-project.sh`. The separate `block-unsafe-generic.sh`
  is a DIFFERENT hook (generic safety layer — stash rules, rm -rf,
  etc.); it does NOT contain the PIPELINE_ID scope filter and is
  untouched by this plan. Verification:
  `grep -c 'PIPELINE_ID' hooks/block-unsafe-generic.sh` returns 0.
- **Test isolation**: use the `/tmp/zskills-tests/` pattern from CLAUDE.md.
- **No weakened tests**: if an existing test no longer applies under
  the new scheme, *delete* it with a commit-message explanation; do
  NOT loosen or `it.skip` it.
- **Per-phase PRs**: each phase lands as its own PR that `/run-plan`
  opens via the worktree (same per-phase-PR pattern as the canary
  plan).
- **PIPELINE_ID sanitization** (writer responsibility): every writer
  that constructs a PIPELINE_ID from user-input or external data
  MUST sanitize to `[a-zA-Z0-9._-]+` before use. Sanitization is
  shared via a helper `scripts/sanitize-pipeline-id.sh`:
  ```bash
  sanitize_pipeline_id() {
    printf '%s\n' "$1" | tr -c 'a-zA-Z0-9._-' '_' | head -c 128
  }
  ```
  Added in Phase 2. All writers in Phases 3-4 source it before
  writing PIPELINE_ID to disk, `.zskills-tracked`, or transcript
  echoes. Verification: `test -x scripts/sanitize-pipeline-id.sh` and
  `grep -c 'sanitize_pipeline_id' skills/*/SKILL.md` ≥ 4 (run-plan,
  fix-issues, research-and-go, do).
- **Dual-read during migration window**: Phase 2's reader change
  enables subdir-scoped globs AND preserves the existing flat glob+
  filter path in parallel. The reader tries subdir first; if the
  subdir is missing OR empty, it falls back to the flat filter. This
  prevents the "Phase 2 lands but Phase 3+4 writers not yet migrated
  → no enforcement" failure mode. The dual-read is REMOVED in a
  **final cleanup phase** (Phase 6) after migration-script drain
  confirms zero legacy flat markers across a 1-hour real-project run.
  Verification: `grep -c 'legacy\|flat\|transitional' hooks/block-unsafe-project.sh.template`
  ≥ 3 comments labelling the dual-read block BEFORE Phase 6 lands, 0
  AFTER.

## Phase 1 — Decide scheme & document

### Goal

Produce a committed `TRACKING_NAMING.md` design doc under `plans/`
(or `docs/`) that (a) picks one of the three schemes below, (b)
resolves four open questions listed at the end of this phase, and
(c) is adopted as authoritative for phases 2-6. No code changes.

### Work Items

- [ ] Write `docs/tracking/TRACKING_NAMING.md` (or `plans/TRACKING_NAMING.md`
      if `docs/` doesn't exist — verify with `ls docs/ 2>&1 | head -3`).
      Contents: design evaluation, chosen scheme, migration strategy,
      delegation semantics, answer to each of the four open questions.
- [ ] Resolve **OQ1** — `research-and-go`'s integer markers
      (`requires.draft-plan.$i`, `requires.run-plan.$i`) — are they
      enforcement or metadata? The plan's **baseline decision**:
      **metadata**. Rationale: (a) research-and-go's session never
      commits code (it's a dispatcher; code-landing happens in child
      `/run-plan` worktrees with their own PIPELINE_IDs); (b) the
      child pipelines write their own `fulfilled.run-plan.<slug>`
      under THEIR subdir, not under research-and-go's subdir, so
      the integer `requires.run-plan.$i` could never be matched by a
      child's fulfillment regardless of scheme. Phase 1 must verify
      this baseline by running `grep -rn 'requires\\.run-plan\\.\\$i\\b'
      skills/research-and-go/` and tracing ALL uses of these markers
      in the skill. If any use path DOES require enforcement, flip
      to enforcement with documented evidence.
- [ ] Resolve **OQ2** — migration strategy for in-flight markers.
      Options: (a) drain (wait for existing pipelines to finish before
      landing Phase 2), (b) rewrite via one-shot script, (c) let
      expire (markers are already short-lived). Recommended: **(c)
      let expire**, because the scheme change is backward-compatible
      if the reader can read both old and new paths during transition.
- [ ] Resolve **OQ3** — per-sprint unique ID for `fix-issues`. Default
      recommendation: `$(date -u +%Y%m%d-%H%M%S)-$(echo "$ISSUE_TITLE"
      | tr -cd 'a-z0-9' | head -c 8)` → e.g.,
      `sprint-20260417-152301-foobar`. PIPELINE_ID becomes
      `fix-issues.$SPRINT_ID`, not `fix-issues.sprint`.
- [ ] Resolve **OQ4** — `.landed` marker semantics. Verify it's NOT a
      tracking marker under this scheme; it's a separate artifact
      managed by `/commit land` and `scripts/write-landed.sh`. Plan
      does NOT touch it.
- [ ] Add a summary block in `CLAUDE.md` (the zskills one) under a new
      "Tracking markers" subsection, pointing at
      `docs/tracking/TRACKING_NAMING.md`.

### Design & Constraints

Evaluate these three options in the design doc:

- **Option A — unified suffix**: every marker basename ends in
  `.$PIPELINE_ID` (orchestrator prefix + suffix, joined by `.`). Reader
  drops the `#*.` strip. Problem: delegation becomes puzzle — the
  child skill's own PIPELINE_ID differs from the parent's, so
  `requires.<child>.<parent-id>` and `fulfilled.<child>.<parent-id>`
  must both use the parent's ID, not the child's own. Writer change:
  pass parent-PIPELINE_ID through explicitly.
  Verification (prior art): see the suffix-matching discussion in
  `hooks/block-unsafe-project.sh.template:251,264,276,359,372,384,460,473,485`.

- **Option B — per-pipeline subdirectory**: markers live in
  `.zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*`. Reader
  globs `$TRACKING_DIR/$PIPELINE_ID/` instead of
  `$TRACKING_DIR/` + filter. The 9 filter sites collapse to 3 or fewer
  glob sites. Delegation is natural (child writes into parent's
  subdir with parent's ID). Migration: drain or let expire; reader
  can run in a transitional mode that reads BOTH flat and subdir
  markers for one release cycle.
  Verification (prior art):
  `hooks/block-unsafe-project.sh.template:231` (guard) +
  `:246-283` (commit block showing glob pattern).

- **Option C — narrow fix + annotate intent**: touch only the
  actually-collision-risky sites. `fix-issues.sprint` becomes
  `fix-issues.$SPRINT_ID`. Integer-indexed metadata markers in
  research-and-go / research-and-plan get moved from `requires.*` to
  a new `meta.*` prefix the reader doesn't scope-filter (documented
  as spawn-tracking, not enforcement). `$TRACKING_ID` users unchanged
  because their slug is already unique per-pipeline IF plans aren't
  re-run concurrently. This leaves the same-slug re-run collision
  unfixed; plan must either (a) accept that as a known limitation or
  (b) add a session-nonce to `$TRACKING_ID`.

### Recommendation rubric

The design doc MUST include this rubric, scoring each option:

| Criterion | A | B | C |
|-----------|---|---|---|
| Concurrent-same-slug isolation | ✅ | ✅ | ⚠ (needs nonce) |
| Migration risk | H | M | L |
| Reader simplification | ⚠ | ✅ | ❌ |
| Delegation semantics | Tricky | Clean | Unchanged |
| LOC change | ~30-40 | ~30-40 | ~5-10 |
| Test surface growth | M | M | L |

**Chosen scheme: Option B (per-pipeline subdirectory).** This is a
prescriptive choice by this plan, not a deferral. Rationale:
- Only option that mechanically solves concurrent-same-slug
  isolation without requiring session nonces.
- Only option that simplifies the reader (collapses 9 filter sites
  to ≤3 glob sites).
- Delegation is natural: parent's PIPELINE_ID IS the subdirectory;
  child writes siblings inside it.
- Existing precedent for non-enforcement markers via prefix
  discrimination — the `phasestep.*` prefix is already silently
  ignored by the hook's glob pattern (`step.*.implement` does not
  match `phasestep.*.implement` — verified:
  `grep -n 'step\\\.' hooks/block-unsafe-project.sh.template`
  shows only `step.*.implement` and `step.*.verify` patterns). We
  reuse this "prefix == scope" technique for integer metadata markers
  (Phase 4) under `meta.*`.

**Implementer override clause**: if during Phase 1 research the
implementer uncovers a concrete blocker (e.g., filesystem limitations,
a race condition that subdirectories aggravate), they may override
with Option A or C — but only by writing a ≥1-paragraph
"Blocker evidence" subsection in the design doc citing a reproducible
test case. No silent pivots.

### Acceptance Criteria

- [ ] `docs/tracking/TRACKING_NAMING.md` (or equivalent path) exists
      and is referenced from `CLAUDE.md`. Verification:
      `grep -q 'tracking/TRACKING_NAMING' CLAUDE.md && test -f docs/tracking/TRACKING_NAMING.md`
- [ ] Design doc answers all 4 open questions with a specific
      decision (not "TBD"). Verification: `grep -E
      '^(OQ1|OQ2|OQ3|OQ4)' docs/tracking/TRACKING_NAMING.md` returns
      4 lines, each followed by a non-empty decision paragraph.
- [ ] **OQ1 decision backed by evidence**: the OQ1 section in the
      design doc includes a "Trace" subsection citing file:line for
      every use of `requires.draft-plan.$i` / `requires.run-plan.$i`
      in research-and-go + research-and-plan (expected: lines 155,
      156, 163 in research-and-go, line 328 in research-and-plan —
      verify via `grep -n 'requires\.\(draft-plan\|run-plan\)\.\$i\b'
      skills/research-and-go/SKILL.md skills/research-and-plan/SKILL.md`).
      For each, the trace notes whether the marker is EVER read back
      (via `grep -rn 'requires\.draft-plan\.\|requires\.run-plan\.'
      skills/ hooks/`) and what triggers the read. If any read path
      is an enforcement path (hook check, pre-commit gate), OQ1 flips
      to enforcement. Verification: the design doc has a "Trace"
      subsection within OQ1 with ≥4 citation lines.
- [ ] Chosen option is one of A/B/C (or a labelled hybrid with
      justification). Verification: design doc includes a section
      "Chosen scheme" with the letter + a justification paragraph.
- [ ] Rubric table is present in the design doc.
      Verification: `grep -c '^| Criterion' docs/tracking/TRACKING_NAMING.md` ≥ 1.
- [ ] No code changes in this phase. Verification:
      `git diff --name-only main..HEAD` contains only `.md` files.

### Dependencies

None. This phase is foundational.

### Verification (phase-exit)

- Design doc reviewed by a dispatched review agent (Explore subagent
  with full doc + the three agent-report files in `/tmp/draft-plan-*`):
  does the doc correctly describe current writer/reader state?
- Implementer dry-runs the proposed delegation path (parent `run-plan` →
  child `draft-plan`) on paper, confirms markers would match under the
  chosen scheme.

## Phase 2 — Reader changes

### Goal

Update `hooks/block-unsafe-project.sh.template` and
`hooks/block-unsafe-project.sh` to implement the reader for the chosen
scheme (from Phase 1). If Option B: collapse 9 filter sites to a
single glob pattern pointing at
`.zskills/tracking/$PIPELINE_ID/`. If Option A: drop `#*.` from
the filter. If Option C: no reader changes; this phase is
renamed "Reader test updates" and only touches tests.

### Work Items

- [ ] Update `hooks/block-unsafe-project.sh.template` per the
      chosen scheme. Preserve:
      - the empty-PIPELINE_ID guard (`if [ -n "$PIPELINE_ID" ]`) at all
        check sites
      - the 3-block structure (commit lines 246-283, cherry-pick
        lines 353-391, push lines 432-488)
        Verification:
        `grep -c 'PIPELINE_ID' hooks/block-unsafe-project.sh.template`
        matches the updated site count (≤10 for A/B, unchanged for C).
- [ ] **No non-template sync needed** — per "Shared Conventions",
      only `.template` exists in this repo. Target-project
      installations regenerate the non-template at install time with
      substitutions. Verification: `ls hooks/block-unsafe-project.sh*`
      returns only `.template`.
- [ ] **Option B specifics** — reader rewrite. Replace each of the 9
      sites (currently matching `"$TRACKING_DIR"/requires.*`,
      `/step.*.implement`, `/step.*.verify`) with subdir-scoped
      globs:
      ```bash
      # Before (flat + filter):
      for req in "$TRACKING_DIR"/requires.*; do
        base=$(basename "$req")
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
          continue
        fi
        # ... check for matching fulfilled
      done

      # After (subdir, no filter needed):
      PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"
      if [ -d "$PIPELINE_SUBDIR" ]; then
        for req in "$PIPELINE_SUBDIR"/requires.*; do
          [ -e "$req" ] || continue  # glob no-match safety
          base=$(basename "$req")
          # ... check for matching fulfilled (no scope filter)
        done
      fi
      ```
      Note: `[ -e "$req" ] || continue` handles the bash glob's
      literal-expansion-on-no-match. Without it, `$req` becomes the
      literal pattern `"$PIPELINE_SUBDIR/requires.*"` and the inner
      check operates on a non-existent path. Verification:
      `PIPELINE_ID=nonexistent bash -c 'PIPELINE_SUBDIR=/tmp/no; for r in
      "$PIPELINE_SUBDIR"/requires.*; do echo "$r"; done'` prints the
      literal unexpanded pattern.
- [ ] **Transitional dual-read** (required — see "Shared Conventions").
      The reader now attempts subdir-scoped glob FIRST; if subdir
      missing or empty, falls back to the existing flat glob+filter
      path. Concrete pseudocode per check-site:
      ```bash
      PIPELINE_SUBDIR="$TRACKING_DIR/$PIPELINE_ID"
      found_any=0
      if [ -d "$PIPELINE_SUBDIR" ]; then
        for req in "$PIPELINE_SUBDIR"/requires.*; do
          [ -e "$req" ] || continue
          found_any=1
          # ... enforcement body
        done
      fi
      if [ "$found_any" -eq 0 ]; then
        # Transitional fallback: flat glob + scope filter (LEGACY — remove in Phase 6)
        for req in "$TRACKING_DIR"/requires.*; do
          [ -e "$req" ] || continue
          base=$(basename "$req")
          if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
            continue
          fi
          # ... enforcement body (same as above)
        done
      fi
      ```
      The fallback preserves the current filter's behavior exactly.
      Refactor enforcement body into a shell function to avoid
      duplication: `enforce_requires_marker "$req"`. Apply this
      dual-read pattern to all 3 check-blocks (commit/cherry-pick/push),
      for all 3 marker categories (requires/step-implement/step-verify).
      Total dual-read sites: 9 (same as before), each now checking
      both paths.
- [ ] **Migration script**: `scripts/migrate-tracking.sh` — non-interactive,
      idempotent, safe to re-run. Strategy: for each legacy flat marker
      file, compute its intended subdir from its basename (suffix =
      the scope-filtered part) and move it. If a marker has no
      detectable subdir-suffix (e.g., empty or ambiguous), leave it
      in place; dual-read will still find it.
      ```bash
      #!/bin/bash
      # Migrate flat markers to per-pipeline subdirs.
      # Idempotent — re-running is safe.
      TRACKING_DIR="${1:-$(pwd)/.zskills/tracking}"
      [ -d "$TRACKING_DIR" ] || { echo "no tracking dir"; exit 0; }
      cd "$TRACKING_DIR" || exit 1
      for f in requires.* fulfilled.* step.*.implement step.*.verify pipeline.* meta.*; do
        [ -e "$f" ] || continue
        [ -d "$f" ] && continue  # already a subdir
        # Derive pipeline ID from filename suffix.
        # Pattern: <category>.<skill>.<id-or-suffix>[.<stage>]
        # Best-effort: skip ambiguous; operator can hand-migrate.
        suffix="${f##*.}"
        # ... (detailed logic in Phase 2 implementation, with test coverage)
      done
      ```
      Invocation policy: run manually or in CI one-shot after Phase 2
      lands. NOT run automatically by the hook (hooks are latency-
      sensitive). Verification: `test -x scripts/migrate-tracking.sh
      && bash -n scripts/migrate-tracking.sh` + a unit test in Phase 5
      that feeds a synthetic `$TRACKING_DIR` with mixed flat markers
      and confirms all migrate-able ones moved.

### Design & Constraints

- Do NOT change marker-file CONTENTS (the printf bodies are the
  writer's concern; this phase only changes how the reader **finds**
  markers).
- Do NOT remove the empty-PIPELINE_ID guard. Unscoped sessions (e.g.,
  direct user commits outside a pipeline) must still skip enforcement
  entirely. Verification: `grep -B1 'PIPELINE_ID#\*\.' hooks/block-unsafe-project.sh.template`
  shows the guard before each filter site.
- Hook bash syntax: `set -u` is NOT set anywhere in the template — do
  not change that. If you introduce a new variable, initialize it
  explicitly (`MY_VAR=""`).

### Acceptance Criteria

- [ ] Hook template compiles cleanly: `bash -n
      hooks/block-unsafe-project.sh.template`.
- [ ] Hook non-template compiles cleanly: `bash -n
      hooks/block-unsafe-project.sh`.
- [ ] Existing tests pass: `bash tests/run-all.sh` returns 0.
      (Some tracking tests in `test-hooks.sh` / `test-tracking-integration.sh`
      will fail; see Phase 5. This phase ships ONLY when the
      canary suite is green AND tracking tests that still apply are
      green. The ones that break because they asserted old paths go
      with a NOTE in Phase 5, not this phase.)
- [ ] Option B: filter-site count reduces from 9 to ≤3. Verification:
      `grep -c 'PIPELINE_ID#\*\.' hooks/block-unsafe-project.sh.template`
      returns ≤3 OR the filter sites use a new glob idiom (e.g.,
      `for req in "$TRACKING_DIR/$PIPELINE_ID"/requires.*`). Count the
      sites however the chosen idiom expresses them.
- [ ] `diff hooks/block-unsafe-project.sh{,}.template` clean.
      Verification: command exits 0 when differences are only the
      placeholder values.

### Dependencies

Phase 1 (design doc must be committed so the implementer can reference
"chosen scheme" authoritatively).

### Verification (phase-exit)

Dispatch a fresh Explore agent with the updated hook + the unchanged
writers. Ask: "under PIPELINE_ID=`run-plan.thermal-domain`, will these
marker basenames be in scope?" Present 6 test cases:
- `fulfilled.run-plan.thermal-domain` (yes — same-pipeline fulfillment)
- `requires.verify-changes.thermal-domain` (yes — delegation)
- `requires.draft-plan.thermal-domain` (yes — delegation)
- `requires.run-plan.other-slug` (no — different pipeline)
- `requires.run-plan.1` — under baseline OQ1 decision (metadata):
  should be **no** (integer markers moved to `meta.*` prefix; the
  reader's enforcement globs never match `meta.*`). If OQ1 is flipped
  to enforcement, expected behavior is **yes** (marker enforces in
  whichever pipeline subdir it lives).
- `fulfilled.run-plan` (no — empty suffix)

Agent's answers must match the chosen-scheme's expected behavior. If
any disagree, block the phase.

## Phase 3 — Writer migration pass 1 ($TRACKING_ID skills)

### Goal

Update writers in `run-plan`, `draft-plan`, `refine-plan`, and
`verify-changes` to the chosen scheme. These are the "easy" skills —
all use `$TRACKING_ID`, all write into `.zskills/tracking/`.

### Work Items

- [ ] `skills/run-plan/SKILL.md` — update writer sites. There are **two
      distinct contexts** for the fulfilled marker (entry vs completion),
      not a single duplicate. Step-marker sites are per-stage per-tracking-id:
      - line 462 (**skill-entry**, `status: started`): `fulfilled.run-plan.$TRACKING_ID`
        → `$TRACKING_DIR/$PIPELINE_ID/fulfilled.run-plan.$TRACKING_ID`
      - line 469 (**entry, delegation lock**): `requires.verify-changes.$TRACKING_ID`
        → `$TRACKING_DIR/$PIPELINE_ID/requires.verify-changes.$TRACKING_ID`
      - line 2245 (**skill-completion**, `status: complete`): `fulfilled.run-plan.$TRACKING_ID`
        → same path as line 462 (the same file is updated, not duplicated)
      - line 2258 (**per-phase informational**): `phasestep.run-plan.$TRACKING_ID.$PHASE.implement`
        — this prefix is **already non-enforcing** (hook's glob
        `step.*.implement` does not match `phasestep.*`; verify:
        `grep -n 'step\.' hooks/block-unsafe-project.sh.template`).
        Under Option B, still move into the subdir for consistency:
        → `$TRACKING_DIR/$PIPELINE_ID/phasestep.run-plan.$TRACKING_ID.$PHASE.implement`
      - Plus 5 step writes (grep `step.run-plan.` in the file for exact
        lines — expect ~5 hits after step-marker audit).
        Verification: `grep -c '\.zskills/tracking/' skills/run-plan/SKILL.md`
        gives ≥11 sites (4 explicit above + 5 step + 2 for cleanup ops).
      - Site-count sanity: `grep -cE '\.zskills/tracking/' skills/run-plan/SKILL.md`
        BEFORE change = 11, AFTER change = 11 (sites don't multiply; only the
        path pattern changes from flat to subdir).
- [ ] `skills/draft-plan/SKILL.md` — update:
      - line 82: `fulfilled.draft-plan.$TRACKING_ID`
      - line 535: `fulfilled.draft-plan.$TRACKING_ID`
      Plus step markers (grep `step.draft-plan.` in that file for
      sites).
- [ ] `skills/refine-plan/SKILL.md` — update line 73, 454 + step
      markers. Grep pattern: `step.refine-plan.` and `fulfilled.refine-plan.`.
- [ ] `skills/verify-changes/SKILL.md` — update line 130, 548 + step
      markers. Note: this skill uses `$MARKER_STEM.$TRACKING_ID`
      where MARKER_STEM is the parent skill's name. Under Option B,
      still write to parent's subdir (parent passes PIPELINE_ID).
      Under Option A, suffix is the parent's full PIPELINE_ID.
- [ ] Mirror sync with rc verification. Run:
      ```bash
      for s in run-plan draft-plan refine-plan verify-changes; do
        rsync -a --delete "skills/$s/" ".claude/skills/$s/" || { echo "SYNC FAILED: $s" >&2; exit 1; }
        diff -r "skills/$s" ".claude/skills/$s" > /dev/null || { echo "DIFF FAILED: $s" >&2; exit 1; }
      done
      echo "mirror sync OK"
      ```
      Verification: running the block above prints exactly "mirror sync OK"
      and exits 0. `rsync -a --delete` replaces the rm-rf-then-cp-r pattern
      used in older plans: (a) it's atomic-ish (file-level replace, not
      dir-wipe-then-copy), (b) it does not trip `block-unsafe-generic.sh`'s
      destructive-ops guard, and (c) blast radius is equivalent — so the
      hook isn't actually losing any safety it was providing.

### Design & Constraints

- Every writer site preserves the marker's CONTENT (the printf body).
  Only the PATH and BASENAME change.
- `$TRACKING_ID` itself is NOT changed in these skills — it remains
  the plan slug / UUID. Under Option B, `$TRACKING_ID` becomes the
  suffix under the pipeline subdir; under A, it concatenates with
  the pipeline prefix.
- Every skill that changes must also echo `ZSKILLS_PIPELINE_ID=` (or
  write `.zskills-tracked` for `do`-pattern skills) at session entry.
  Verification:
  `grep -n 'ZSKILLS_PIPELINE_ID=\|PIPELINE_ID=' skills/run-plan/SKILL.md`
  shows an emission near the skill's entry point.
- **Delegation paths must still match.** When `run-plan` writes
  `requires.verify-changes.$TRACKING_ID` and `verify-changes` later
  writes `fulfilled.verify-changes.$TRACKING_ID`, these must end up
  in the same directory (Option B) or with the same suffix
  (Option A). Test this with a dry-run before committing.

### Acceptance Criteria

- [ ] All 4 skills updated. Verification:
      `git diff --name-only main..HEAD | grep -c 'SKILL.md'` ≥ 4
      (run-plan, draft-plan, refine-plan, verify-changes).
- [ ] Mirror in sync. Verification:
      `diff -r skills/.claude/skills/` returns nothing for these 4
      subdirs (or use `for s in run-plan draft-plan refine-plan
      verify-changes; do diff -r "skills/$s" ".claude/skills/$s" || exit 1; done`).
- [ ] Cross-skill delegation still works in dry-run. Verification:
      a throwaway script in `/tmp/` that simulates `run-plan` writing
      `requires.verify-changes.<id>` and `verify-changes` writing
      `fulfilled.verify-changes.<id>`, then checks both files land
      where the reader expects.
- [ ] Bash compiles for each SKILL (shell syntax quoted inside
      markdown):
      extract heredocs / bash blocks with a throwaway script and run
      `bash -n` on each. No syntax errors.
- [ ] `bash tests/run-all.sh` passes (except tracking-integration tests
      that this plan will update in Phase 5 — flag them with a comment
      marker, don't disable them).

### Dependencies

Phase 2 (reader must already accept the new scheme).

### Verification (phase-exit)

Integration-test dry-run: spin up a temp `$TRACKING_DIR` in `/tmp/`,
invoke the writer snippets from each of the 4 skills by hand, confirm
the resulting filesystem layout matches the design doc's
"expected layout" section.

## Phase 4 — Writer migration pass 2 (fix-issues, research-and-go, research-and-plan, do)

### Goal

Update the remaining writers — the "hard" ones with heterogeneous ID
schemes. Resolve the per-sprint uniqueness question for `fix-issues`
and the metadata-vs-enforcement distinction for research-and-go's
integer markers (per Phase 1's design doc).

### Work Items

- [ ] `skills/fix-issues/SKILL.md` — replace literal `sprint` suffix
      with per-sprint unique ID (per OQ3 decision). Update sites:
      - line 335: `requires.draft-plan.$ISSUE_NUMBER` → stays? Or
        move under pipeline subdir? (See design doc for OQ1 resolution
        applied to per-issue markers.)
      - line 434: `pipeline.fix-issues.sprint` → `pipeline.fix-issues.$SPRINT_ID`
      - line 550, 658, 814, 851, 922, 1254: `step.fix-issues.sprint.<stage>`
        → new path per scheme
      - line 827: `requires.verify-changes.sprint` → delegation marker,
        scheme-dependent
      - line 715: `ZSKILLS_PIPELINE_ID=fix-issues.sprint` →
        `ZSKILLS_PIPELINE_ID=fix-issues.$SPRINT_ID`
        Verification:
        `grep -n 'sprint' skills/fix-issues/SKILL.md` shows 0 remaining
        literal `sprint` suffixes (other than in comments or variable
        names like `$SPRINT_ID`).
- [ ] `skills/research-and-go/SKILL.md` — per OQ1 decision:
      - If integer markers are metadata: move from `requires.*` to
        `meta.*` prefix (hook ignores `meta.*`). Sites: 155, 156, 163.
      - If enforcement: migrate to new scheme (Option A: use parent
        PIPELINE_ID suffix; Option B: write into subdir).
      - line 56: `pipeline.research-and-go.$SCOPE` — pipeline sentinel,
        scheme-dependent path.
      - line 92: `requires.verify-changes.final.$META_PLAN_SLUG` —
        cross-branch final check, migrates under new scheme.
        Verification: `grep -E 'requires\.|meta\.|pipeline\.' skills/research-and-go/SKILL.md`
        shows the post-migration prefixes only.
- [ ] `skills/research-and-plan/SKILL.md` — line 328: `requires.run-plan.$i`.
      Same metadata-vs-enforcement decision as research-and-go.
      Apply identically.
- [ ] `skills/do/SKILL.md` — line 327: `PIPELINE_ID="do.$TASK_SLUG"` —
      PIPELINE_ID construction is fine; but if the skill writes any
      tracking markers, those need migration. Grep:
      `grep -n '\.zskills/tracking/' skills/do/SKILL.md` — if empty, no
      marker writes; only ensure the worktree `.zskills-tracked` file
      is populated correctly (unchanged).
- [ ] Mirror sync all 4. Verification:
      `diff -r skills/<name> .claude/skills/<name>` empty for each.
- [ ] Hook reader: if Option C chosen in Phase 1, add the
      `meta.*` prefix to the hook's IGNORE set so those files are
      skipped during enforcement. Verification: `grep -n 'meta\.' hooks/block-unsafe-project.sh.template`
      shows an explicit skip.

### Design & Constraints

- **Sprint ID format** (per OQ3): `$(date -u +%Y%m%d-%H%M%S)-$(slugify
  "$ISSUE_TITLE" | head -c 8)`. Must be unique across concurrent
  sprints. Write to `.zskills-tracked` in the fix-issues worktree so
  the hook can pick it up via the worktree-file path (same mechanism
  as `do`).
- **Backward compat**: any user mid-sprint when this phase lands
  must NOT be broken. The reader's transitional mode (Phase 2) handles
  legacy flat markers. But `fix-issues` specifically: if a session is
  resumed after the change, the skill must detect legacy `sprint`
  markers and either migrate or gracefully abort with a clear message.
  See design doc for chosen approach.
- **do-skill special case**: `do` doesn't emit PIPELINE_ID to the
  main session transcript (line 330 explicitly prohibits this — hook
  picks it up from the worktree's `.zskills-tracked`). Preserve that
  behavior. Verification: `grep -n 'ZSKILLS_PIPELINE_ID' skills/do/SKILL.md`
  shows only the worktree-file write, no main-session echo.

### Acceptance Criteria

- [ ] Literal `sprint` suffix eliminated from fix-issues writer sites.
      Verification:
      `grep -nE '\b(pipeline|requires|fulfilled|step)\.[^.]+\.sprint\b' skills/fix-issues/SKILL.md`
      returns no matches.
- [ ] Integer markers in research-and-go / research-and-plan either
      migrated to new scheme (if enforcement) or moved to `meta.*`
      prefix (if metadata).
      Verification:
      `grep -nE 'requires\.(draft-plan|run-plan)\.\$i\b' skills/research-and-go/SKILL.md skills/research-and-plan/SKILL.md`
      returns no matches.
- [ ] Mirror in sync for all 4.
- [ ] All skills' bash blocks compile (`bash -n` on extracted snippets).
- [ ] `bash tests/run-all.sh` passes (with Phase 5 test updates not
      yet landed — track pre-existing tracking-integration tests that
      this phase temporarily breaks, in the phase's NOTE section).

### Dependencies

Phase 2 (reader), Phase 3 (easy-skill writers — so delegation paths
from fix-issues → draft-plan / verify-changes work under the new
scheme).

### Verification (phase-exit)

Integration dry-run for two scenarios:
1. Two concurrent `fix-issues` sprints spawned. Each writes markers
   under its unique `$SPRINT_ID`. Hook enforces each independently.
2. One `research-and-go` session spawning 3 sub-`run-plan` pipelines.
   Confirm the integer markers behave as-designed (metadata-invisible
   or enforcement-visible) and don't cross-contaminate.

## Phase 5 — Canary + integration test coverage

### Goal

Add canary tests in `tests/test-canary-failures.sh` that lock in the
new scheme mechanically. Update
`tests/test-tracking-integration.sh` and `tests/test-hooks.sh` tracking
tests to use the new scheme, deleting any tests that no longer apply
(with explanatory commit message).

### Work Items

- [ ] New section in `tests/test-canary-failures.sh` titled
      "Tracking marker naming (subdir scope)" with ≥8 test cases:
      1. **Concurrent-same-slug isolation**: spawn two pipelines
         with the same `$TRACKING_ID` but different `$PIPELINE_ID`
         (e.g., `run-plan.foo` and `draft-plan.foo`). Under Option B,
         they write into different subdirs. Assert: each pipeline's
         markers are ONLY in its own subdir; neither sees the other's.
      2. **Glob-special chars in PIPELINE_ID**: PIPELINE_ID contains
         `*`, `?`, `[`, `]`, spaces. Assert: the subdir is created with
         the literal chars (quoted properly), the hook's glob does
         not expand them, and enforcement still works.
         Verification: this tests PIPELINE_ID sanitization — if the
         test fails, the writer skills must sanitize (e.g., replace
         `[^a-zA-Z0-9_-]` with `_`) before writing to disk. Add
         sanitization to the spec if needed.
      3. **Dots in `$TRACKING_ID`**: PIPELINE_ID = `run-plan.a.b.c`.
         Under Option B, the subdir is literally `run-plan.a.b.c`;
         no nesting. Assert: no nested-directory confusion.
      4. **Empty `$PIPELINE_ID`**: ambient commit in a session with
         NO `ZSKILLS_PIPELINE_ID` set. Hook must still function
         (enforcement skipped entirely per the empty-guard at
         `hooks/block-unsafe-project.sh.template:231`).
      5. **Missing subdir**: PIPELINE_ID set but subdir doesn't exist
         (fresh session, no markers yet). Hook must not fail or error;
         the `[ -d "$PIPELINE_SUBDIR" ]` guard handles this. Assert:
         hook exits 0 (no enforcement fires).
      6. **Glob no-match inside subdir**: subdir exists but is empty
         (`mkdir -p` but no markers). The inner `for req in …/requires.*`
         expands to literal unexpanded pattern. Assert: `[ -e "$req"
         ] || continue` safety holds; hook doesn't error.
      7. **`fix-issues` sprint isolation** (after Phase 4): two
         sprints with distinct `$SPRINT_ID`s — markers in different
         subdirs, no cross-pollination.
      8. **Metadata prefix (meta.*)**: a `meta.research-and-go.$i`
         file in a subdir is NOT matched by the hook's enforcement
         globs (`requires.*`, `step.*.implement`, `step.*.verify`,
         `fulfilled.*`). Assert: hook exits 0 regardless of presence
         or absence of a matching `fulfilled.*`.
      Verification: each new test uses `pass`/`fail` helpers;
      section header uses `section "Tracking marker naming (subdir scope) (8 cases)"`.
- [ ] Update `tests/test-tracking-integration.sh` — the existing 11
      e2e tests hard-code old marker basenames. Migrate each to the
      new scheme. For any test whose premise no longer applies (e.g.,
      "literal `sprint` is visible" — no longer true under the
      new scheme), DELETE it with an explanatory git-log message.
      Do NOT `it.skip` or comment out.
- [ ] Update `tests/test-hooks.sh` tracking tests (lines 195-487 per
      earlier inventory) to use the new scheme. Same delete-if-stale
      rule.
- [ ] Verify `tests/run-all.sh` still invokes `test-canary-failures.sh`
      and propagates exit codes. Verification: `grep -n
      test-canary-failures tests/run-all.sh` shows the invocation.
- [ ] Verify `tests/run-all.sh` invokes `test-tracking-integration.sh`
      too. If it doesn't, ADD the invocation (Phase 5 of the canary
      plan missed this — see memory `project_canary_coverage_gap.md`).
      Verification: `grep -c test-tracking-integration tests/run-all.sh`
      ≥ 1.

### Design & Constraints

- Follow existing canary test-harness idioms (from the recent canary
  plan): `section "…"` headers, `pass`/`fail`/`section` helpers,
  `setup_fixture_repo()`, `FIXTURE_DIRS+=(…)` cleanup.
- Use `/tmp/zskills-tests/<per-worktree>` for test state.
- Every new test has a one-line comment explaining the scenario. No
  multi-line docstrings.
- Fixtures live in `tests/fixtures/canary/` — add per the existing
  pattern. Keep fixtures minimal.

### Acceptance Criteria

- [ ] New "Tracking marker naming" section in canary with ≥5 tests
      covering the scenarios listed in Work Items.
      Verification: `grep -A1 'section "Tracking marker' tests/test-canary-failures.sh`
      shows a count ≥5.
- [ ] `tests/run-all.sh` invokes both canary and tracking-integration
      suites.
      Verification: `grep -cE 'test-(canary-failures|tracking-integration)\.sh'
      tests/run-all.sh` ≥ 2.
- [ ] Full suite green: `bash tests/run-all.sh` exits 0.
- [ ] No `it.skip` or commented-out tests introduced.
      Verification: `git diff main..HEAD -- tests/` should not
      contain new `it.skip` or `# TEMP DISABLED` patterns.

### Dependencies

Phases 2, 3, 4 (all writers + reader migrated before tests enforce
the new scheme).

### Verification (phase-exit)

Run `bash tests/run-all.sh` and confirm:
- Canary test count increased by ≥5
- Tracking-integration test count changed per Phase 5 migrations
- All suites pass
- No flakiness on 2 consecutive runs

## Phase 6 — End-to-end validation + dual-read removal

### Goal

Demonstrate in a real pipeline scenario that the unified scheme works
under concurrency. Lock in with an end-to-end smoke test that runs
`/run-plan` + a concurrent simulated `/fix-issues` sprint, confirming
no cross-pollination of markers. **Then remove the dual-read legacy
fallback from the hook**, since all writers are migrated and migration
script has been run.

### Work Items

- [ ] **Remove dual-read from hook**: after smoke validates all
      pipelines work under subdir-only reader, delete the
      `if [ "$found_any" -eq 0 ]; then ... flat fallback ... fi`
      blocks at all 9 sites in
      `hooks/block-unsafe-project.sh.template`. Also delete
      `scripts/migrate-tracking.sh` (no longer needed).
      Verification: `grep -c 'legacy\|transitional\|found_any' hooks/block-unsafe-project.sh.template`
      returns 0; `test -f scripts/migrate-tracking.sh` returns 1
      (file absent).
- [ ] Write `tests/e2e-parallel-pipelines.sh` (new file) that:
      - Creates two temp git repos in `/tmp/`.
      - In repo 1, bootstraps a minimal plan in `plans/SMOKE1.md`
        with 1 trivial phase.
      - In repo 2, bootstraps a minimal `fix-issues`-like workflow.
      - Simulates both pipelines writing markers concurrently (use
        `&` + `wait`).
      - Asserts: repo 1's markers are ONLY in repo 1's
        `.zskills/tracking/$PIPELINE_ID/` (or matching-scheme path),
        and repo 2's markers are ONLY in repo 2's path.
      - Asserts: the hook, invoked in each repo, correctly blocks /
        allows commits per the per-pipeline enforcement.
- [ ] Add the e2e smoke to `tests/run-all.sh` (optional — runs only
      if `$RUN_E2E` env var is set, to avoid slowing the default
      suite).
      Verification: `grep -n RUN_E2E tests/run-all.sh` shows the
      conditional.
- [ ] Run the e2e smoke manually and paste the output into the PR
      description for Phase 6.
      Verification: PR body contains the smoke-run output under a
      "E2E smoke output" section.
- [ ] Update `plans/PLAN_INDEX.md` (if it exists) to mark this plan
      as complete. Update frontmatter `status: complete` on this
      plan file.
      Verification: `grep -n 'UNIFY_TRACKING_NAMES' plans/PLAN_INDEX.md`
      shows a "complete" row; `head -5 plans/UNIFY_TRACKING_NAMES.md`
      shows `status: complete`.

### Design & Constraints

- The e2e smoke MUST use real git repos (mktemp'd), real
  `.zskills/tracking/` directories, and real hook invocations. No
  mocks.
- Cleanup on exit: trap that removes both `mktemp -d` temp repos. Note:
  `rm -rf` is blocked by `block-unsafe-generic.sh`; use `rsync -a
  --delete /dev/null/ "$TMPDIR"/ 2>/dev/null; rmdir "$TMPDIR"` or simply
  `find "$TMPDIR" -mindepth 1 -delete && rmdir "$TMPDIR"`. Verify
  cleanup ran by checking `test -d "$TMPDIR"` returns 1 after trap fires.
- The smoke is not a unit test — expected runtime ≤30s.

### Acceptance Criteria

- [ ] `tests/e2e-parallel-pipelines.sh` exists and is executable.
      Verification: `test -x tests/e2e-parallel-pipelines.sh`.
- [ ] Running it returns 0.
      Verification: `bash tests/e2e-parallel-pipelines.sh; echo "rc=$?"`
      ends in `rc=0`.
- [ ] PR description for this phase includes the smoke output.
      Verification: manual review.
- [ ] `plans/UNIFY_TRACKING_NAMES.md` frontmatter shows `status: complete`.
- [ ] Plan index updated (if it exists). If it doesn't, skip.

### Dependencies

Phases 1-5.

### Verification (phase-exit)

Manual: PR reviewer confirms the e2e smoke output, and confirms the
concurrent-pipeline case demonstrably works under the new scheme.

## Drift Log

This is the initial draft of the plan — no prior versions exist.
Drift tracking will begin after the first phase lands.

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review
**Convergence:** Converged at round 2 with 2 outstanding non-blocking
concerns (see below).

**Remaining concerns:**
- **Phase 3 delegation dry-run verification is prose-level, not
  code-level.** The "throwaway script" mentioned in Phase 3
  Verification is not specified concretely. Implementer should write
  a ~20-line bash script that simulates parent writing `requires.*`
  + child writing `fulfilled.*` under the new scheme, then verifies
  by direct file-system check. Not a blocker — the phase-exit
  verification can reject if absent.
- **Migration-script sanitization edge case**: `scripts/migrate-tracking.sh`
  detailed logic is sketched, not written out. Phase 2 implementer
  must write a unit test for it (covered in Phase 5 Work Items) to
  exercise the ambiguous-suffix case. Not a blocker.

### Round History

| Round | Reviewer Findings | DA Findings | Substantive | Resolved |
|-------|------------------:|------------:|------------:|----------|
| 1 | 7 | 19 | 12 | 12/12 (fixed or justified after verify-before-fix rejected claims that didn't reproduce) |
| 2 | 2 new + 6 follow-up | 3 new + 6 follow-up | 5 | 5/5 |

Round 2 DA flagged a genuine BLOCKING issue (per-phase-PR + atomic-
cutover contradiction) that Round 1's refinement introduced. Fixed
by restoring dual-read transitional mode with a final cleanup in
Phase 6. Round 2 DA also surfaced the sanitization-ownership gap
(who sanitizes PIPELINE_ID) — fixed by moving sanitization to a
shared `scripts/sanitize-pipeline-id.sh` helper sourced by every
writer.
