# /draft-tests — Phase 5 (backfill mechanics + re-invocation)

Phase 5 of `/draft-tests`. The orchestrator dispatches here when Phase
1-4 ([modes/draft.md](draft.md)) completes and either:

- gap detection (5.1) classifies ≥ 1 Completed-phase AC as MISSING
  (backfill path), OR
- re-invocation detection (5.5) finds an existing `### Tests` subsection
  in the plan (refinement-mode path).

Both paths end at Phase 6 ([modes/land.md](land.md)). Variables defined
in the SKILL.md preamble and Phase 1-4 (`$PLAN_FILE`, `$PARSED_STATE`,
`$DETECT_STATE`, `$TRACKING_ID`, `$PIPELINE_ID`, `$MAIN_ROOT`,
`$TOPLEVEL`, `$WT_PATH`) are still in scope.

## Phase 5 — Backfill mechanics and re-invocation

This phase handles two re-entry scenarios:

- **Backfill.** A plan with Completed phases whose shipped work lacks
  test coverage. The skill classifies each Completed phase's ACs
  (COVERED / UNKNOWN / MISSING via the WI 5.1 three-level rubric),
  appends one or more new top-level
  `## Phase N — Backfill tests for completed phases X[, Y][, Z]`
  sections at the structurally correct position, then runs the normal
  draft → review loop against them in the same invocation.
- **Refinement.** A plan that already has `### Tests` subsections from
  a prior `/draft-tests` invocation. The existing specs are treated as
  the round-0 draft for Phase 4's review loop; the refined output is
  written back in place.

Both scenarios produce a `## Test Spec Revisions` section — deliberately
named distinct from `/refine-plan`'s `## Drift Log` so both skills can
coexist on one plan without history collisions.

The mechanical orchestration is implemented by six scripts under
`skills/draft-tests/scripts/`:

- `gap-detect.sh` — WI 5.1 three-level rubric. Reads parsed-state's
  `completed_phases:` and detection-state's `test_files:`; classifies
  each AC into COVERED / UNKNOWN / MISSING; writes a gaps file with
  `missing_phases:`, `unknown_phases:`, and `advisories:` lists.
- `append-backfill-phase.sh` — WI 5.2 + 5.3 + 5.3b. Reads the gaps file;
  clusters MISSING Completed phases into groups of 1–3; appends one
  backfill phase per cluster at the structurally correct position;
  authors the backfill phase body (Goal, Work Items, Design &
  Constraints, Acceptance Criteria, Dependencies); updates parsed-state's
  `non_delegate_pending_phases:` and `pending_phases:` lists with each
  backfill phase id (load-bearing for Phase 4's coverage-floor pre-check
  per AC-5.10).
- `insert-test-spec-revisions.sh` — WI 5.7. Appends (or updates) a
  `## Test Spec Revisions` section in 2-column `| Date | Change |`
  format, placed AFTER any existing `## Drift Log` and `## Plan Review`
  sections.
- `flip-frontmatter-status.sh` — WI 5.6. Single-purpose: flips
  frontmatter `status: complete` → `status: active` IFF a backfill
  phase is being appended. Every other frontmatter field byte-identical.
- `re-invocation-detect.sh` — WI 5.5. Detects whether the plan already
  has at least one `### Tests` subsection (refinement mode signal).
- `verify-completed-checksums.sh` — WI 5.8 / AC-5.9. Re-checksums every
  Completed phase before the final write; refuses to write if any has
  drifted from its Phase 1 checksum.

Each script takes the plan-file and the parsed-state path; tests stub
the agent layer (no live LLM dispatch — same convention as Phase 4).

### WI 5.1 — Gap detection for Completed phases

Implemented in `gap-detect.sh`. Using the test-file path list persisted
by Phase 2 (`test_files:` in detection-state — NOT a fresh discovery,
per AC-2.9), for each Completed phase's AC, classify into one of three
confidence levels:

- **COVERED** (high confidence): the AC's ID (e.g. `AC-3.2`) appears
  literally in any test file in the persisted list, OR the AC text
  contains a backticked identifier of length ≥ 4 that appears in
  exactly one test file. (We restrict the "concrete identifier"
  heuristic to backticked tokens because plain prose nouns can never
  be reliably attributed to a code identifier — see AC-5.2 below.)
- **UNKNOWN** (low confidence): no AC-ID match in any test file AND
  either no backticked tokens in the AC body OR every backticked token
  is present somewhere in the repo. Emits an advisory line; does NOT
  trigger backfill.
- **MISSING** (moderate confidence): no AC-ID match in any test file
  AND the AC body contains at least one **backticked token** (matched
  by `` `[^`]+` ``) AND that backticked token, when treated as a
  literal string, is absent from every file in the repo
  (`git grep -F -- "<token>"` returns no matches). Backticks are the
  explicit author signal that the token is a code identifier
  (function, file path, test name, error string) rather than prose.
  Plain-English nouns inside an AC — even uncommon ones — never trigger
  MISSING; they fall to UNKNOWN. Triggers backfill.

A Completed phase is flagged for backfill only when ≥ 1 AC is MISSING.
Phases with only UNKNOWN ACs emit an advisory listing in the skill's
final output (user-review path) but do NOT auto-append a backfill
phase. This is a deliberate conservative default to avoid
false-positive backfill thrash on large repos.

**AC-5.2 regression guard.** ACs containing only English prose nouns
(no backticked tokens) — even if some of those nouns happen to be
absent from the repo — fall to UNKNOWN and never trigger MISSING. This
guards against the prose-token false-positive bug where common
English words trigger spurious backfill. The classifier requires a
backticked token to even consider MISSING.

### WI 5.2 — Backfill phase construction

Implemented in `append-backfill-phase.sh`. When ≥ 1 Completed phase is
flagged MISSING, append a NEW top-level phase at the **correct
structural position**:

- Scan for the first trailing level-2 heading at column 0 that is NOT
  a `## Phase ...` heading, is NOT inside a fenced code block, and
  appears AFTER the last `## Phase`. **The rule is the broad form —
  ANY non-phase `## <name>` outside fenced code blocks terminates the
  search, not a closed list.** Use the same awk-style `in_code`
  state-tracker as the WI 1.5 / Phase 2 / Phase 3 / Phase 4 scans —
  heading detection runs only when `in_code == 0`. Real plans contain
  non-canonical trailing headings (e.g.,
  `## Anti-Patterns -- Hard Constraints` in
  `plans/EXECUTION_MODES.md`); a closed enumeration would skip past
  these and sandwich the backfill phase between them and
  `## Plan Quality`, breaking the structural invariant that all
  `## Phase ...` headings precede all non-phase trailing sections.
  Examples of trailing headings the rule terminates on (illustrative,
  NOT exhaustive): `## Drift Log`, `## Plan Review`, `## Plan
  Quality`, `## Test Spec Revisions`,
  `## Anti-Patterns -- Hard Constraints`, `## Non-Goals`, and any
  other `## <name>` the user has authored after the last phase.
- If any such trailing heading exists, insert the backfill phase
  IMMEDIATELY BEFORE it — all trailing sections stay in place,
  byte-identical, in their authored order.
- If no trailing heading exists, append at end of file.

Heading form (verbatim):

```markdown
## Phase N -- Backfill tests for completed phases X[, Y][, Z]
```

where `N` is one greater than the current max phase number, including
sub-letters (e.g., if the plan ends at `Phase 5b`, the backfill is
`Phase 6`). **Cluster 1–3 Completed phases per backfill phase** —
per research §Prior art (Feathers / legacy-code guidance that bulk
batch backfill is a death march). With 4+ MISSING Completed phases,
the skill produces multiple backfill phases (per AC-5.4) — never a
single mega-phase.

The Progress Tracker also gains a new row per backfill phase with
status `⬚` (Pending) and a note recording which Completed phases the
backfill targets.

### WI 5.3 — Backfill phase content

The authored body for each backfill phase contains:

- **Goal**: `Add missing test coverage for AC-X.1, AC-Y.3, ... that
  were flagged as MISSING by gap detection.`
- **Work Items**: one per AC gap.
- **Design & Constraints**: `Tests must verify the current state of
  shipped work, not the original AC text where reality diverged.`
  Plus the alias note (see WI 5.4).
- **Acceptance Criteria**: one per AC gap, using a backfill-local
  `AC-<backfill-phase>.<n>` ID that aliases the original.
- **Dependencies**: the listed Completed phases.

The new backfill phase is **Pending** — the normal draft → review loop
then runs against it in the same invocation.

### WI 5.3b — Update parsed-state on backfill insertion

Immediately after the backfill phase is appended to the plan (5.2) and
its body is authored (5.3), append the backfill phase's identifier to
the parsed-state file's `non_delegate_pending_phases:` list (and to
`pending_phases:` for completeness). Backfill phases are
author-created by the skill itself and never carry
`### Execution: delegate`, so they are always non-delegate by
construction — no delegate predicate evaluation is needed; the phase
identifier is appended directly.

This update is mandatory because Phase 4 WI 4.8 step 4 reads
`non_delegate_pending_phases:` from parsed-state and explicitly forbids
re-derivation; without this update, the coverage-floor pre-check would
not enforce the floor on the backfill phase's ACs, silently shipping
un-attested coverage on the very phase the backfill flow exists to
cover. **AC-5.10 closes this data-flow gap.**

### WI 5.4 — Completed-phase ACs are NOT modified

The Completed-phase ACs referenced by backfill phases are NEVER
modified. The backfill phase references them by their original ID; the
new backfill ACs use a backfill-local
`AC-<backfill-phase>.<n>` ID that aliases the original. Phase 1's
AC-ID assignment does not apply to Completed phases — instead, the
backfill phase quotes the AC text (or its identifier) and assigns the
local alias.

### WI 5.5 — Re-invocation detection

Implemented in `re-invocation-detect.sh`. If the plan already contains
at least one `### Tests` subsection (column 0, outside fenced code
blocks), treat the invocation as **refinement mode**: the existing
specs are the round-0 draft; the review loop from Phase 4 runs against
them; the refined output is written back in place. The orchestrator
calls this script before dispatching Phase 3's drafter; on
refinement-mode hit, Phase 3 is skipped (the existing specs ARE the
draft).

`append-tests-section.sh`'s idempotent skip (Phase 3) ensures
re-invocation does NOT duplicate `### Tests` headings or nest
subsections. Per AC-5.5, refining specs in place + appending one row
to `## Test Spec Revisions` per phase whose specs changed is the full
behavior.

### WI 5.6 — Frontmatter `status: complete` → `active` flip

Implemented in `flip-frontmatter-status.sh`. When the skill appends a
backfill phase to a plan whose YAML frontmatter has `status: complete`,
it MUST flip `status` to `active` in the same write. `/run-plan` treats
`status: complete` as terminal (see `skills/run-plan/SKILL.md:413` and
`:536`) and would otherwise refuse to execute the new backfill phase,
silently orphaning it.

This frontmatter flip is **the only frontmatter edit the skill is
permitted to make**. Every other frontmatter field is byte-identical
pre/post invocation. AC-5.8 verifies both branches (flip-on-backfill
and no-backfill-no-flip).

**Cron interaction (informational).** `/run-plan`'s terminal-cron
cleanup at `skills/run-plan/SKILL.md:413-419` runs only when
`status==complete`. When `/draft-tests` flips `status` complete →
active, the next `/run-plan` invocation enters the case-4 normal
preflight path (not case 1) — the cron correctly continues firing and
re-evaluates the plan with the new backfill phase. `/draft-tests` does
NOT touch registered crons; the status flip is the only frontmatter
mutation. Documented so a future "why doesn't /draft-tests delete the
cron when flipping status?" question has an answer in the spec.

### WI 5.7 — `## Test Spec Revisions` for re-invocation

Implemented in `insert-test-spec-revisions.sh`. When the skill modifies
a Pending phase's existing `### Tests` subsection or appends a new
backfill phase, append (or update) a `## Test Spec Revisions` section.
**Placement: AFTER any existing `## Drift Log` and `## Plan Review`
sections** (the trailing sections `/refine-plan` writes; see Phase 5
D&C "Co-skill ordering with /refine-plan" below for the rationale and
the cross-skill checksum-boundary interaction). **AC-5.11 codifies
this placement order**: last `## Phase ...` → `## Drift Log` →
`## Plan Review` → `## Test Spec Revisions` → user-authored trailing
sections (e.g., `## Plan Quality`).

Use a 2-column format:

```markdown
## Test Spec Revisions

One row per invocation. Column "Change" summarises structural deltas
(spec counts, AC coverage changes, backfill appends) -- never full
spec text.

| Date | Change |
|------|--------|
| 2026-04-29 | Phase 4: +3 specs for AC-4.1, AC-4.3; Phase 5: refined spec for AC-5.1 (input narrowed to literal); Appended Phase 7 for backfill of Completed phases 2, 3 |
```

This section is placed AFTER any existing `## Drift Log` and
`## Plan Review` and BEFORE all other user-authored trailing
non-phase level-2 sections — **the broad form:
any `## <name>` (other than `## Phase ...`) outside fenced code
blocks the user has authored after the last phase counts as a
trailing section, not a closed list.** Use the same awk-style `in_code` state-tracker as WI 1.5 / WI
5.2 — heading detection runs only when `in_code == 0` so `## `
headings inside ` ``` ` fences are not mistaken for trailing
sections. Named examples (illustrative, NOT exhaustive):
`## Drift Log`, `## Plan Review`, `## Plan Quality`,
`## Anti-Patterns -- Hard Constraints`, `## Non-Goals`. The column
names and section name are deliberately different from
`/refine-plan`'s `## Drift Log` (which uses
`| Phase | Planned | Actual | Delta |`) so a plan touched by both
skills carries two unambiguous histories.

### WI 5.8 — Completed-phase checksum verification before final write

Implemented in `verify-completed-checksums.sh`. Before the final write
in Phase 6, re-read each Completed phase section (using the same
broad-form, fenced-code-block-aware boundary as parse-plan.sh) and
re-checksum. If any differs from the Phase 1 value stored in
parsed-state's `completed_phases:`, the script aborts the run with a
clear error message listing each drifted phase. The plan file is NOT
written. This is the AC-5.9 guard — a Completed phase that drifted
during Phase 3/5 mutation is a defect; failing fast is the correct
response.

Invocation:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
VERIFY="$ZSKILLS_SKILLS_ROOT/draft-tests/scripts/verify-completed-checksums.sh"
bash "$VERIFY" "$PLAN_FILE" "$PARSED_STATE"
```

Source-tree zskills tests use the equivalent
`"$REPO_ROOT/skills/draft-tests/scripts/verify-completed-checksums.sh"`
form.

### Design & Constraints

- **Backfill is structural-insert, not append-to-EOF.** New phases go
  **immediately before** the first trailing non-phase level-2 heading
  after the last `## Phase ...` — **the broad form: ANY non-phase
  `## <name>` (column 0) terminates the scan, not a closed list of
  named sections.** Named examples (illustrative, NOT exhaustive):
  `## Drift Log`, `## Plan Review`, `## Plan Quality`, `## Test Spec
  Revisions`, `## Anti-Patterns -- Hard Constraints`, `## Non-Goals`.
  All such trailing sections stay byte-identical in their authored
  order; the skill NEVER excises and re-appends them. The Progress
  Tracker table gains a new row for each backfill phase with status
  `⬚`. Any attempt to move a non-phase section is a specification
  bug.
- **Test Spec Revisions vs Drift Log — deliberately distinct.** The
  `## Test Spec Revisions` section records spec-authoring actions by
  this skill across invocations. `/refine-plan`'s `## Drift Log`
  records plan-as-drafted vs reality-at-refine. Both may coexist on
  one plan; the skill never writes to `## Drift Log` and
  `/refine-plan` never writes to `## Test Spec Revisions`. The
  2-column schema (`| Date | Change |`) is chosen because
  Planned/Actual columns would be meaningless for spec-authoring
  actions.
- **Co-skill ordering with `/refine-plan`** (cross-skill integration
  risk, named explicitly). `/refine-plan`'s checksum boundary at
  `skills/refine-plan/SKILL.md:110` is closed-form — "the full text
  from `## Phase N` to the next `## Phase` or end of file" — not the
  broad-wildcard form `/draft-tests` uses. If `## Test Spec
  Revisions` is placed between the last `## Phase` and `## Drift
  Log`, `/refine-plan`'s next-invocation checksum on the last
  Completed phase will INCLUDE bytes through `## Test Spec Revisions`
  (its boundary scan only terminates at the next `## Phase`).
  Subsequent `/draft-tests` re-invocations that grow `## Test Spec
  Revisions` would then trigger a `/refine-plan` checksum mismatch
  and a false "Completed phase drifted" error. **Resolution
  (binding):** `/draft-tests` MUST place `## Test Spec Revisions`
  AFTER any existing `## Drift Log` and `## Plan Review` sections
  (and after any other user-authored trailing non-phase headings),
  so `/refine-plan`'s closed-form boundary scan still terminates at
  `## Drift Log` rather than seeing `## Test Spec Revisions` first.
  Additionally, **a plan touched by both skills should run
  `/refine-plan` BEFORE `/draft-tests` in any cycle** — `/refine-plan`
  computes its checksums in its own Phase 1, and any subsequent
  `/draft-tests` run modifies trailing sections (where `/refine-plan`
  is no longer scanning). Note: `/refine-plan`'s Phase 5 reassembly
  rebuilds frontmatter + Overview + Tracker + Completed +
  Refined-remaining + fresh Drift Log + fresh Plan Review and **does
  not preserve any pre-existing trailing sections beyond those it
  rebuilds** — so a `## Test Spec Revisions` section written by
  `/draft-tests` will be DESTROYED by a subsequent `/refine-plan` run.
  Broadening `/refine-plan`'s checksum boundary AND its reassembly
  preservation to recognise `## Test Spec Revisions` is **out of
  scope** (depends on a co-skill change, separate PR). Until that
  lands, callers must run `/draft-tests` AFTER `/refine-plan` if both
  are needed in one cycle, and re-run `/draft-tests` after every
  `/refine-plan` to recover any clobbered `## Test Spec Revisions`
  history.
- **Never record in `## Test Spec Revisions` that a Completed phase
  was modified.** If that ever happened, the checksum gate already
  refused the write. The only Completed-phase-adjacent entry is
  "Appended Phase N for backfill of Completed phases X, Y" — which
  documents an append, not a modification.
- **Backfill trigger threshold.** At least one Completed-phase AC
  must be classified MISSING per WI 5.1's three-level rubric. Phases
  with UNKNOWN ACs trigger an advisory note in the final output, not
  an auto-appended backfill phase. This is a conservative default to
  avoid false-positive backfill thrash; the skill is not for
  exhaustive audit (that's `/qe-audit`).
- **Frontmatter flip is single-purpose.** The only frontmatter edit
  this skill ever makes is `status: complete` → `status: active`
  when appending a backfill phase. Any other frontmatter change is
  out of scope.

### Per-script invocation summary

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
GAP="$ZSKILLS_SKILLS_ROOT/draft-tests/scripts/gap-detect.sh"
BACKFILL="$ZSKILLS_SKILLS_ROOT/draft-tests/scripts/append-backfill-phase.sh"
TSR="$ZSKILLS_SKILLS_ROOT/draft-tests/scripts/insert-test-spec-revisions.sh"
FLIP="$ZSKILLS_SKILLS_ROOT/draft-tests/scripts/flip-frontmatter-status.sh"
REINV="$ZSKILLS_SKILLS_ROOT/draft-tests/scripts/re-invocation-detect.sh"
VERIFY="$ZSKILLS_SKILLS_ROOT/draft-tests/scripts/verify-completed-checksums.sh"

# Step 1: gap detection (writes gaps file).
bash "$GAP" "$PLAN_FILE" "$PARSED_STATE" "$DETECT_STATE" "$GAPS_FILE"

# Step 2: re-invocation detection (informational; affects orchestration).
RE_MODE=$(bash "$REINV" "$PLAN_FILE" || true)

# Step 3: backfill (writes backfill-out, mutates parsed-state, mutates plan).
bash "$BACKFILL" "$PLAN_FILE" "$PARSED_STATE" "$GAPS_FILE" "$BACKFILL_OUT"

# Step 4: frontmatter flip IF backfill appended (single-purpose).
if [ -s "$BACKFILL_OUT" ]; then
  bash "$FLIP" "$PLAN_FILE" 1
fi

# Step 5: append/update Test Spec Revisions row.
bash "$TSR" "$PLAN_FILE" "$DATE" "$CHANGE_TEXT"

# Step 6: pre-write checksum verification (Phase 6 calls this too).
bash "$VERIFY" "$PLAN_FILE" "$PARSED_STATE"
```

Source-tree zskills tests use the equivalent `"$REPO_ROOT/skills/draft-tests/scripts/<name>"`
form (per `skills/update-zskills/references/script-ownership.md`).
