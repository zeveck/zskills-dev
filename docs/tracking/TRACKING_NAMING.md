# Tracking Marker Naming — Design Doc

Authoritative specification for the tracking-marker naming scheme used by
`hooks/block-unsafe-project.sh.template` and by every skill that writes
under `.zskills/tracking/`. Adopted as the baseline for Phases 2-6 of
`plans/UNIFY_TRACKING_NAMES.md`.

## Background

The reader (the commit-blocking hook) applies a PIPELINE_ID scope filter
to tracking markers at nine sites
(`hooks/block-unsafe-project.sh.template:251,264,276,359,372,384,460,473,485`).
The filter strips the orchestrator-prefix from `PIPELINE_ID` and expects
marker basenames to end with the stripped suffix:

```sh
if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".${PIPELINE_ID#*.}" ]]; then
  continue
fi
```

Writers across 5+ skills use inconsistent suffix schemes
(`$TRACKING_ID`, literal `sprint`, integer `$i`, `$ISSUE_NUMBER`,
`$TASK_SLUG`). Concrete failure modes observed:

1. **Concurrent pipelines with the same slug** (e.g., re-running a plan
   after a failure) cross-fulfill each other's markers, violating the
   parallel-pipelines-are-core requirement.
2. **`fix-issues.sprint` collides** when two sprints run concurrently —
   both share the literal `sprint` suffix.
3. **research-and-go's integer markers** (`requires.run-plan.$i`) are
   invisible to its own session's scope filter. In most cases this is
   intentional (research-and-go never commits code itself), but the
   design isn't documented anywhere and is fragile.

This doc resolves the scheme, answers four open questions, and defines
the delegation and migration semantics that the follow-up phases depend
on.

## Chosen scheme

**Option B — per-pipeline subdirectory.**

Markers live in `.zskills/tracking/$PIPELINE_ID/{fulfilled,requires,step}.*`.
The reader globs `$TRACKING_DIR/$PIPELINE_ID/` instead of
`$TRACKING_DIR/` + suffix filter. The nine filter sites collapse to
three or fewer glob sites. Delegation is natural: a child skill writes
siblings into the parent's subdirectory using the parent's
`PIPELINE_ID`.

This is a prescriptive choice by `plans/UNIFY_TRACKING_NAMES.md`, not a
deferral. No blocker was uncovered during Phase 1 research, so the
baseline stands; the **implementer override clause** (§"Blocker
evidence" in the plan) was not triggered.

Justification:

- Only option that mechanically solves the concurrent-same-slug
  collision without requiring session nonces — two pipelines with the
  same slug live in different subdirectories, so the reader cannot
  cross-match them.
- Only option that simplifies the reader — the nine suffix-filter
  sites collapse into a handful of `"$TRACKING_DIR/$PIPELINE_ID"/…`
  globs.
- Delegation falls out of the filesystem: the parent's `PIPELINE_ID`
  is literally the directory name, so when a child skill is invoked
  under it (e.g., `/run-plan` dispatching `/draft-plan`) the child
  simply writes into the same directory under its own `fulfilled.*`
  basename. No cross-process ID plumbing required beyond the existing
  `ZSKILLS_PIPELINE_ID` transcript echo.
- Existing precedent: non-enforcement markers already distinguished by
  prefix (`phasestep.*` is silently ignored because the hook globs
  `step.*.implement` and `step.*.verify`, not `phasestep.*`). We reuse
  this "prefix == scope" technique for integer metadata markers in
  Phase 4 (moved under `meta.*`).

## Recommendation rubric

All three options were evaluated in the plan prelude and reproduced
here for the decision record:

| Criterion                          | A          | B     | C                 |
|------------------------------------|------------|-------|-------------------|
| Concurrent-same-slug isolation     | ✅         | ✅    | ⚠ (needs nonce)  |
| Migration risk                     | H          | M     | L                 |
| Reader simplification              | ⚠         | ✅    | ❌               |
| Delegation semantics               | Tricky     | Clean | Unchanged         |
| LOC change                         | ~30-40     | ~30-40 | ~5-10            |
| Test surface growth                | M          | M     | L                 |

- **Option A — unified suffix.** Every marker basename ends in
  `.$PIPELINE_ID` (orchestrator prefix + suffix, joined by `.`). Reader
  drops the `#*.` strip. Problem: delegation becomes a puzzle — the
  child skill's own `PIPELINE_ID` differs from the parent's, so
  `requires.<child>.<parent-id>` and `fulfilled.<child>.<parent-id>`
  must both use the parent's ID, not the child's. Every writer has to
  be updated to accept and emit the parent's ID explicitly. Suffix-
  match prior art:
  `hooks/block-unsafe-project.sh.template:251,264,276,359,372,384,460,473,485`.
- **Option B — per-pipeline subdirectory.** Chosen (see above). Prior
  art: `hooks/block-unsafe-project.sh.template:231` (guard) +
  `:246-283` (commit block showing glob pattern).
- **Option C — narrow fix + annotate intent.** Touch only the
  collision-risky sites: `fix-issues.sprint` becomes
  `fix-issues.$SPRINT_ID`; integer-indexed metadata markers move from
  `requires.*` to a new `meta.*` prefix the reader doesn't scope-
  filter; `$TRACKING_ID` writers unchanged. Does **not** solve the
  same-slug-re-run collision unless a session nonce is also added to
  `$TRACKING_ID` — leaves the bug partly unfixed.

## Open questions — decisions

### OQ1 — Integer markers (`requires.draft-plan.$i`, `requires.run-plan.$i`)

**Decision: metadata (not enforcement).**

Rationale:

- `research-and-go`'s own session never commits code — it is a
  dispatcher. Code-landing happens in the child `/run-plan` worktrees,
  each of which runs with its own `PIPELINE_ID` (e.g.,
  `run-plan.$TRACKING_ID` per
  `skills/run-plan/SKILL.md:301`). The parent's own pre-commit hook
  never runs against application code, so an unfulfilled
  `requires.run-plan.$i` in the parent's tracking dir cannot actually
  block a commit.
- Even if it did run, the reader's scope filter (`*".${PIPELINE_ID#*.}"`)
  matches the parent's PIPELINE_ID suffix, which is `$SCOPE` (from
  `skills/research-and-go/SKILL.md:65` —
  `ZSKILLS_PIPELINE_ID=research-and-go.$SCOPE`). A marker ending in
  `.1`, `.2`, or `.meta` never matches `.$SCOPE`, so the integer
  markers are not visible to the filter regardless of scheme.
- The child pipelines write their own `fulfilled.run-plan.<slug>`
  under THEIR subdir (Option B) or with their own suffix (flat
  scheme), not under the parent's scope, so the integer
  `requires.run-plan.$i` could never be matched by a child's
  fulfillment under any of the three options either.

Under Option B, these integer markers are moved out of the
`requires.*` namespace entirely in Phase 4 — they become `meta.*`
files, making the metadata intent explicit in the marker basename.
This parallels the existing `phasestep.*` convention: both are
silently ignored by the hook because their prefix does not match the
hard-coded `requires.*` / `fulfilled.*` / `step.*` globs.

If a future design actually needs enforcement of the integer plan, the
child dispatch already carries `tracking-index=$i` through its prompt
(`skills/research-and-go/SKILL.md:170-173`), so the child can write
back `fulfilled.run-plan.$i` into the parent's subdir. That capability
is preserved but not currently required.

#### Trace — every use of the integer markers

These citations are file:line, one per use, covering
`skills/research-and-go` and `skills/research-and-plan`:

- `skills/research-and-go/SKILL.md:155` —
  `requires.draft-plan.$i` write, dispatcher-time metadata. **Not
  read-back anywhere** (see below).
- `skills/research-and-go/SKILL.md:156` —
  `requires.run-plan.$i` write, dispatcher-time metadata. **Not
  read-back anywhere.**
- `skills/research-and-go/SKILL.md:163` —
  `requires.run-plan.meta` write, meta-plan execution metadata.
  **Not read-back anywhere.**
- `skills/research-and-plan/SKILL.md:328` —
  `requires.run-plan.$i` write when invoked inside an active pipeline
  (post-meta-plan requirement seeding). **Not read-back anywhere.**
- `hooks/block-unsafe-project.sh.template:247` — reader globs
  `requires.*` and then applies the scope filter at line 251. Integer
  markers fail the scope filter because the parent
  `PIPELINE_ID=research-and-go.$SCOPE` strips to `$SCOPE`, and no
  integer suffix (`.1`, `.2`, `.meta`) ends in `.$SCOPE`.
- `hooks/block-unsafe-project.sh.template:356` — second instance of
  the same `requires.*` glob + scope filter (pre-push path). Same
  analysis: integer markers are filtered out.
- `hooks/block-unsafe-project.sh.template:457` — third instance
  (worktree-root path). Same analysis.

Read-back search:
`grep -rn 'requires\.draft-plan\.\|requires\.run-plan\.' skills/ hooks/`
yielded only the writers listed above and the generic `requires.*` glob
in the hook. **No enforcement path reads back the integer markers by
name.** The baseline metadata decision therefore holds — no flip to
enforcement is warranted.

### OQ2 — Migration strategy for in-flight markers

**Decision: let expire.**

Markers are short-lived and the Phase 2 reader change is
backward-compatible: it tries the new subdir-scoped glob first and
falls back to the legacy flat `requires.*`/`fulfilled.*`/`step.*` glob
+ suffix filter when the subdir is missing or empty. This "dual-read"
window stays in place through Phases 3-5 while writers are migrated,
and is removed in Phase 6 after a 1-hour real-project run confirms
zero legacy flat markers remain. No one-shot rewriter script and no
forced drain are required. Users running pipelines across the upgrade
boundary observe identical behaviour; markers written before the
upgrade are read via the legacy path until they naturally clear.

### OQ3 — Per-sprint unique ID for `fix-issues`

**Decision: `sprint-$(date -u +%Y%m%d-%H%M%S)-<8-char-slug>`, with
`PIPELINE_ID="fix-issues.$SPRINT_ID"`.**

The current writer uses the literal `fix-issues.sprint`
(`skills/fix-issues/SKILL.md:715`), which means two concurrent sprints
cross-fulfill each other's markers. Replace with:

```sh
SPRINT_ID="sprint-$(date -u +%Y%m%d-%H%M%S)-$(
  printf '%s' "$ISSUE_TITLE" | tr -cd 'a-z0-9' | head -c 8
)"
PIPELINE_ID="fix-issues.$SPRINT_ID"
```

The UTC timestamp guarantees uniqueness across concurrent sprints on
the same host (seconds resolution is enough because
`sanitize_pipeline_id` runs after construction and a sprint is always
kicked off by a human interaction at least a second apart). The
8-char issue-title slug is a convenience tag so the `PIPELINE_ID` is
still legible to a human reading logs.

Per the shared conventions in `plans/UNIFY_TRACKING_NAMES.md`, every
writer sources `scripts/sanitize-pipeline-id.sh` before writing the
constructed ID to disk. The sanitizer collapses any character outside
`[a-zA-Z0-9._-]` into `_` and truncates to 128 bytes — safe for
filesystem and glob use.

### OQ4 — `.landed` marker semantics

**Decision: `.landed` is NOT a tracking marker.**

`.landed` is a separate artifact written at worktree-root by
`/commit land` and `scripts/write-landed.sh` when cherry-picked
commits have been confirmed on `main`. It records landing state for
worktree-cleanup tools; it does not participate in pre-commit
enforcement and is not read by the hook's `requires.*`/`fulfilled.*`/
`step.*` globs. It lives outside `.zskills/tracking/`.

This plan does not touch `.landed` at all — neither its contents nor
its location nor its writer. Any confusion that arises because
`.landed` sounds tracking-ish is resolved by this explicit statement:
it is a worktree-state artifact, not a scope-filtered marker.

## Migration strategy

The migration is staged across Phases 2-6:

1. **Phase 2 (reader).** The hook reader is updated to try the new
   subdir-scoped glob first
   (`"$TRACKING_DIR/$PIPELINE_ID"/requires.*`, etc.) and fall back to
   the legacy flat glob + suffix filter if the subdir is absent. The
   fallback is explicitly labelled `legacy`/`flat`/`transitional` in
   hook comments so Phase 6 can mechanically grep-and-remove it.
   `scripts/sanitize-pipeline-id.sh` lands here so Phases 3-4 writers
   can source it.
2. **Phase 3 (writers, pass 1).** Skills whose `PIPELINE_ID` is
   already effectively unique per invocation (`$TRACKING_ID`-based:
   `run-plan`, `do`) are migrated to write under the subdir. Because
   the reader is dual-mode, there is no flag-day.
3. **Phase 4 (writers, pass 2).** The skills with collision risk
   (`fix-issues`, `research-and-go`, `research-and-plan`) switch to
   the OQ3 `SPRINT_ID` scheme and to writing under the subdir.
   Integer metadata markers move from `requires.*` to `meta.*` so
   they are trivially ignored by the hook's enforcement globs.
4. **Phase 5 (canaries).** Regression canaries lock in the new
   scheme: concurrent-same-slug isolation, delegation semantics,
   `sprint-$SPRINT_ID` uniqueness. Tests that were written against
   the flat scheme and no longer apply are **deleted**, not `skip`-ed,
   per CLAUDE.md's "no weakened tests" rule.
5. **Phase 6 (cleanup).** After a 1-hour real-project run confirms
   the legacy path is dormant, the dual-read block is removed and the
   legacy comments are stripped. Reader becomes single-path subdir-
   scoped.

No one-shot migrator runs. In-flight markers written under the old
scheme simply expire (via their own pipeline finishing) or are picked
up by the legacy glob during the dual-read window.

## Delegation semantics

Under Option B, delegation is intrinsic to the filesystem layout.

- **Parent `/run-plan` dispatching child `/draft-plan`.** Parent's
  `PIPELINE_ID=run-plan.$TRACKING_ID` creates
  `.zskills/tracking/run-plan.$TRACKING_ID/` and writes
  `requires.draft-plan.<slug>` inside it. When the child executes and
  the parent receives control back, it writes
  `fulfilled.draft-plan.<slug>` into the **same** directory. The
  child does not need to know the parent's ID to satisfy the
  requirement — the parent writes its own fulfillment as part of the
  normal post-dispatch flow. This is identical to today's behavior,
  just under a subdir.
- **Parent `/research-and-go` dispatching child `/run-plan`.** Parent
  writes metadata (`meta.draft-plan.$i`, `meta.run-plan.$i`) into its
  own subdir. Child runs with its own `PIPELINE_ID=run-plan.<slug>`
  and its own subdir. The parent's subdir is never read by the
  child's hook — no cross-contamination possible. Enforcement lives
  with the child pipeline, which is the session that actually commits
  code.
- **`fix-issues` sprint with multiple issues.** Parent writes
  `requires.draft-plan.$ISSUE_NUMBER` and
  `requires.run-plan.$ISSUE_NUMBER` into its own subdir
  (`fix-issues.$SPRINT_ID/`). Each issue's `/run-plan` invocation
  writes its own fulfillment back to the parent's subdir (same
  mechanism as the `/run-plan` dispatch above). Concurrent sprints
  get distinct subdirectories by construction, eliminating the
  literal-`sprint`-suffix collision.

All three delegation paths use the same pattern: **the parent writes
requires AND fulfillment into its own subdir**. Child skills never
need to know the parent's `PIPELINE_ID` for correctness — the parent
reconciles the tracking state itself after the child returns.

## Design evaluation

The three schemes trade off differently against the same criteria:

- **Concurrent isolation.** Both A (suffix) and B (subdir) isolate by
  `PIPELINE_ID`. C leaves `$TRACKING_ID`-based pipelines exposed
  unless a nonce is added, which is a de-facto scheme change anyway.
  B wins on simplicity (directories are obviously isolated; suffix
  equality requires careful writer discipline).
- **Reader cost.** B collapses the nine filter sites to at most three
  `"$TRACKING_DIR/$PIPELINE_ID"/…` globs. A removes the
  `#*.`-strip but still iterates the full `$TRACKING_DIR`. C barely
  changes the reader at all.
- **Writer cost.** A and B are roughly the same LOC (30-40 lines
  across the writers) — both require every writer to know the
  `PIPELINE_ID` prefix. C is smallest (~5-10 lines) but leaves known
  bugs unfixed.
- **Migration.** B has a clean dual-read window because the subdir
  simply doesn't exist pre-migration, so the fallback is unambiguous.
  A requires the reader to understand two suffix formats
  simultaneously, which is more error-prone. C has nothing to
  migrate in pass 1 but still has to migrate in pass 2 if the nonce
  is added.
- **Delegation.** B is self-documenting (the subdir is the scope). A
  requires writers to plumb the parent `PIPELINE_ID` through to child
  invocations. C unchanged — which is currently underspecified and
  therefore fragile.
- **Test growth.** A and B both need the full concurrent-isolation +
  delegation canary. C needs less coverage but provides less
  guarantee.

The tiebreaker is **delegation clarity**. B is the only option where
the delegation semantics fall out of the filesystem rather than being
implemented by convention across multiple writers.

## Expected layout

Under Option B, a fully populated tracking tree for a
`run-plan.thermal-domain` pipeline that dispatched a `/draft-plan`
sub-skill and is mid-phase-2 looks like:

```
.zskills/tracking/
  run-plan.thermal-domain/
    requires.draft-plan.thermal-domain      # child skill invocation required
    fulfilled.draft-plan.thermal-domain     # written back after /draft-plan returns
    step.phase2.implement                   # implementation started
    step.phase2.verify                      # verifier ran
    step.phase2.report                      # report written — commit now allowed
```

A concurrent `fix-issues` sprint handling two issues:

```
.zskills/tracking/
  fix-issues.sprint-20260417-152301-foobar/
    requires.draft-plan.123                 # issue #123 needs a plan
    requires.run-plan.123                   # issue #123 needs execution
    requires.draft-plan.456
    requires.run-plan.456
    fulfilled.draft-plan.123                # written after /draft-plan for #123
    …
```

A concurrent `research-and-go` session in dispatch phase (metadata
only — the orchestrator itself never commits code):

```
.zskills/tracking/
  research-and-go.cooling-system/
    meta.draft-plan.1                       # metadata (Phase 4 renames from requires.*)
    meta.draft-plan.2
    meta.run-plan.1
    meta.run-plan.2
    meta.run-plan.meta
  run-plan.subplan-1/                       # child pipeline, separate subdir
    requires.draft-plan.subplan-1
    fulfilled.draft-plan.subplan-1
    step.phase1.implement
    …
```

The isolation is structural — two concurrent pipelines cannot see
each other's markers because they live in disjoint subdirectories.

## References

- `plans/UNIFY_TRACKING_NAMES.md` — the plan that commissions this doc
- `hooks/block-unsafe-project.sh.template:231` — `TRACKING_DIR` guard
- `hooks/block-unsafe-project.sh.template:246-283` — first enforcement
  block (commit path)
- `hooks/block-unsafe-project.sh.template:355-384` — pre-push path
- `hooks/block-unsafe-project.sh.template:456-485` — worktree-root
  path
- `skills/run-plan/SKILL.md:301,699` — `PIPELINE_ID=run-plan.$TRACKING_ID`
- `skills/fix-issues/SKILL.md:715` — legacy `fix-issues.sprint`
  writer (migrated in Phase 4)
- `skills/research-and-go/SKILL.md:65,155,156,163` — scope echo and
  integer-marker writes
- `skills/research-and-plan/SKILL.md:328` — integer-marker write
- `skills/do/SKILL.md:327` — `PIPELINE_ID=do.${TASK_SLUG}`
