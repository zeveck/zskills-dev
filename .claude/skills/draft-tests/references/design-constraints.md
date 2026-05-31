# /draft-tests — Design & Constraints

Cross-phase invariants for Phases 1-4. Referenced from
[modes/draft.md](../modes/draft.md). Phase 5's `### Design & Constraints`
subsection (which covers backfill placement, Test-Spec-Revisions
ordering, and co-skill ordering with `/refine-plan`) lives inline in
[modes/backfill.md](../modes/backfill.md) because it is scoped to that
phase's mechanics.

## Design & Constraints

- **Checksum gate (load-bearing).** Before the final write in Phase 6,
  re-read each Completed phase section and re-checksum; if any differs
  from the Phase 1 value, STOP and refuse. Copy `/refine-plan`'s
  Phase 1 + Phase 5 pattern, with TWO deliberate divergences:
  - **(a) Section-boundary rule is broadened** from "next `## Phase`
    or EOF" to "next level-2 heading (any `## <name>`) or EOF" — the
    rule is the broad wildcard form, NOT an enumeration of known
    section names. This keeps the skill usable on plans with
    non-canonical level-2 headings. Trailing whitespace INSIDE the
    phase section is included.
  - **(b) Reassembly is in-place edit, not whole-file concatenation.**
    `/refine-plan` Phase 5 (lines 397-409) rebuilds the plan by
    concatenating frontmatter + Overview + Tracker + Completed +
    Refined-remaining, then APPENDS fresh Drift Log + Plan Review (it
    does not preserve any pre-existing trailing section beyond the
    phases themselves, because it rebuilds those sections per
    invocation). `/draft-tests` cannot use that pattern: every
    trailing non-phase section (`## Drift Log`, `## Plan Review`,
    `## Plan Quality`, `## Test Spec Revisions`, plus any user-authored
    sections like `## Anti-Patterns -- Hard Constraints` /
    `## Non-Goals`) MUST be preserved byte-identical. The skill reads
    the current plan bytes, mutates only the targeted insertion points
    (AC-ID prefixes, appended `### Tests` subsections, appended
    backfill phase, `## Prerequisites` insertion, `## Test Spec
    Revisions` append/update, frontmatter `status:` flip), and writes
    the file back. **No section-by-section concatenation.** This is a
    STRONGER preservation invariant than `/refine-plan`'s.
- **AC-ID assignment is the only allowed edit to Pending phases
  outside of appending `### Tests`.** Document this as an explicit
  exception: the criterion text is unchanged; only an `AC-N.M — `
  prefix is added. If a reviewer flags AC-ID assignment as a
  modification, the justification is: "ID prefix is content-preserving
  metadata required to reference criteria from the appended specs."
- **Cross-skill script invocation.** Use the
  `"$ZSKILLS_SKILLS_ROOT/<owner>/scripts/<name>"` form
  for any helper from another skill (and from this skill's own
  scripts). The bare-`scripts/<name>` form is forbidden post-PR-#97 —
  those paths are removed by `/update-zskills`'s STALE_LIST migration
  on consumer checkouts. See
  `skills/update-zskills/references/script-ownership.md` for the full
  owner registry. **Source-tree zskills tests** use the equivalent
  `"$REPO_ROOT/skills/<owner>/scripts/<name>"` form, mirroring
  `skills/work-on-plans/SKILL.md` and `skills/zskills-dashboard/SKILL.md`.
- **No external JSON/YAML tooling.** Parse YAML and JSON (including
  `.claude/zskills-config.json` in later phases) via bash regex with
  `BASH_REMATCH`. Idiom:
  ```bash
  if [[ "$CONTENT" =~ \"key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    VALUE="${BASH_REMATCH[1]}"
  fi
  ```
- **Tracking marker scheme.** Markers live under
  `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/`. Basenames follow
  `fulfilled.draft-tests.$TRACKING_ID`,
  `step.draft-tests.$TRACKING_ID.research`, `.review`, `.refine`,
  `.finalize`. See `docs/tracking/TRACKING_NAMING.md`.
- **Persisted parsed state** (`/tmp/draft-tests-parsed-<slug>.md`)
  survives context compaction. All later phases read from it if
  in-memory state is lost — same pattern as `/refine-plan`'s
  `/tmp/refine-plan-parsed-*`.
