---
name: draft-tests
disable-model-invocation: false
argument-hint: "<plan-file> [rounds N] [guidance...]"
description: >-
  Draft test specifications into an existing plan through iterative
  adversarial review. Given a plan file, classifies phases, computes
  immutability checksums of completed phases, assigns AC IDs, then
  appends a `### Tests` subsection per pending phase, running a senior-QE
  reviewer + devil's-advocate + refiner loop until the specs hold up.
  Completed phases are never modified (checksum-gated). Sister skill to
  /draft-plan, scoped to test specs.
  Usage: /draft-tests <plan-file> [rounds N] [guidance...]
---

# /draft-tests \<plan-file> [rounds N] [guidance...] — Adversarial Test-Spec Drafter

Sister skill to `/draft-plan`: same drafting + adversarial-review
machinery, scoped to test specifications. Given the path to an existing
plan (the kind `/draft-plan` produces), this skill appends a
`### Tests` subsection into every pending phase, then runs a senior-QE
review loop (reviewer + devil's advocate + refiner) until the specs hold
up.

The reader of the appended specs is the AI implementing agent that
`/run-plan` dispatches — not a human — so specs ride along inside the
phases `/run-plan` already executes. No companion document. No
`/run-plan` loader patch.

**Completed phases are never mutated.** Checksum-gated, per
`/refine-plan`'s immutability pattern. `/draft-tests` ALSO preserves
every trailing non-phase section byte-identical at the file-write level
— a stricter invariant than `/refine-plan`. Test gaps in completed
phases are surfaced by appending a new top-level
`## Phase N — Backfill tests for completed phases X–Y` BEFORE any
existing trailing sections.

**Ultrathink throughout.**

## Arguments

```
/draft-tests <plan-file> [rounds N] [guidance...]
```

- **plan-file** (required) — path to the plan `.md` file. If the token
  contains `/`, use as-is; otherwise prepend `plans/`.
- **rounds N** (optional) — max review/refine cycles. Default: 3 (matches
  `/draft-plan`; `/refine-plan`'s default is 2 because it operates on an
  already-refined plan, while `/draft-tests` is typically blank-slate
  spec drafting).
- **guidance...** (optional) — any tokens not matched as plan file or
  `rounds N` are joined with spaces into **guidance text** — prepended
  to BOTH the reviewer and devil's-advocate prompts in Phase 4 as a
  "User-driven scope/focus directive" section, mirroring
  `/refine-plan`'s positional-tail semantics. Empty guidance preserves
  byte-identical reviewer/DA prompt output (regression-safe). Guidance
  is **priming context** that shapes WHAT the agents pressure-test —
  NOT factual claims they should act on without verification.
  Verify-before-fix discipline still applies in the refiner.

**Detection:** scan `$ARGUMENTS` from the start:
- The **first** token ending in `.md` OR containing `/` is the plan
  file. If the token contains `/`, use as-is; otherwise prepend
  `plans/`.
- `rounds` followed by a numeric argument sets max cycles. (`rounds`
  not followed by a number is treated as guidance text, not the
  keyword.)
- Any tokens not matched as the plan file or `rounds N` keyword are
  joined with spaces into guidance text.
- If no plan file is detected, **error:**
  `Usage: /draft-tests <plan-file> [rounds N] [guidance...]`

Examples:
- `/draft-tests plans/FEATURE.md`
- `/draft-tests plans/FEATURE.md rounds 4`
- `/draft-tests FEATURE.md` → reads `plans/FEATURE.md`
- `/draft-tests plans/FOO.md focus on integration tests`
- `/draft-tests plans/FOO.md rounds 3 emphasize property-based coverage`

## Phase 1 — Skeleton, Ingestion, and Checksum Gate

This phase parses the plan file, classifies phases, computes
immutability checksums, assigns AC IDs, and writes parsed state. It is
the foundation for every subsequent phase.

### Tracking fulfillment

Determine the tracking ID from the plan filename (mirroring
`/draft-plan` and `/refine-plan`):

```bash
TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
```

Two-tier PIPELINE_ID resolution: if `$ZSKILLS_PIPELINE_ID` is set
(delegated invocation), use it verbatim; else construct
`draft-tests.$TRACKING_ID`. **Pass any constructed PIPELINE_ID** (NOT
the env-var-supplied value) through the canonical sanitiser before
writing to disk. The bare-relative `scripts/sanitize-pipeline-id.sh`
form is FORBIDDEN — that path no longer exists post-PR-#97.

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
if [ -n "${ZSKILLS_PIPELINE_ID:-}" ]; then
  PIPELINE_ID="$ZSKILLS_PIPELINE_ID"
else
  RAW_PIPELINE_ID="draft-tests.$TRACKING_ID"
  PIPELINE_ID=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh" "$RAW_PIPELINE_ID")
fi
mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
printf 'skill: draft-tests\nid: %s\nplan: %s\nstatus: started\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.draft-tests.$TRACKING_ID"
```

The fulfillment marker is updated to `status: complete` at the end of
Phase 6. Step markers
(`step.draft-tests.$TRACKING_ID.research|review|refine|finalize`) are
written at the end of each phase, mirroring `/draft-plan`.

### Refuse-to-run checks

- If the plan file does not exist: **error:** `Plan file '<path>' not found.`
- If the plan file lacks a `## Progress Tracker` section: **error:**
  `No Progress Tracker found in '<path>'. Add a Progress Tracker table with phase status columns so the drafter can distinguish completed from pending phases.`
- **Do NOT exit on zero-Pending alone.** A plan with all-Completed
  phases is the primary scenario for backfill (a shipped plan lacking
  tests). Route to Phase 5's backfill gap detection. Only exit clean if
  BOTH zero Pending phases AND zero Completed-phase gaps are detected.
  In that case, emit:
  `All phases complete and all ACs appear to have matching tests — nothing to draft or backfill. Re-run after adding new phases or after asserting gaps exist.`

### Parse the plan file

Invoke the bundled parser script. It performs all of: YAML frontmatter
extraction, Progress Tracker parsing, phase boundary detection
(fenced-code-block-aware), Completed/Pending classification (per
`/refine-plan`'s rules — `Done` / `✅` / `[x]` case-insensitive in the
Status column; everything else Pending including `⬚`, `⬜`,
`In Progress`, `Blocked`, empty cells, or any other glyph), delegate
classification (single canonical predicate
`grep -q '^### Execution: delegate'` per phase body, persisted to
parsed-state as `delegate_phases:` and paired
`non_delegate_pending_phases:` lists), SHA-256 checksum of every
Completed phase section, AC-ID assignment in Pending phase
`### Acceptance Criteria` blocks (three-predicate classifier — see
"AC-ID assignment" below), ac-less Pending phase detection (a Pending
non-delegate phase with no `### Acceptance Criteria` block is appended
to `ac_less:` and an advisory line is emitted), and persistence to a
parsed-state file:

```bash
SLUG="$TRACKING_ID"
PARSED_STATE="/tmp/draft-tests-parsed-${SLUG}.md"
bash "$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/parse-plan.sh" \
  "$PLAN_FILE" "$PARSED_STATE"
```

Source-tree zskills tests use the equivalent
`"$REPO_ROOT/skills/draft-tests/scripts/parse-plan.sh"` form (see
`skills/update-zskills/references/script-ownership.md` cross-skill
caller convention).

The parser writes the file in this format:

```
plan_file: <path>
frontmatter_title: <title>
frontmatter_status: <status>
completed_phases:
  <phase-id>:<sha256>
  ...
pending_phases:
  <phase-id>
  ...
non_delegate_pending_phases:
  <phase-id>
  ...
delegate_phases:
  <phase-id>
  ...
ac_less:
  <phase-id>
  ...
advisories:
  <line>
  ...
```

This file persists across context compaction. All later phases read
from it if in-memory state is lost — same pattern as `/refine-plan`'s
`/tmp/refine-plan-parsed-*`.

### Section-boundary rule (load-bearing)

A Completed phase section spans from `## Phase N` through the byte just
before the NEXT line that starts with `## ` (any level-2 heading) at
column 0 AND is NOT inside a fenced code block, OR end of file,
whichever comes first. **The rule is the broad form — ANY `## <name>`
outside fenced code blocks terminates the section, not a closed list.**

**Fenced-code-block awareness is mandatory.** Real plans (e.g.,
`plans/EXECUTION_MODES.md` lines 236, 2079, 2082) contain `## `
headings at column 0 inside ` ``` ` fences as illustrative examples; a
naive `^## ` scan would terminate the prior phase's checksum at the
in-code heading, silently dropping authentic phase content from the
gate. The parser implements a single-pass awk-style state-tracker
toggling an `in_code` flag on each ` ``` ` line; heading detection runs
only when `in_code == 0`. The checksummed bytes still INCLUDE the
fenced-code-block content (the fenced lines are part of the Completed
phase's authored body); only the boundary detection skips them.

Real plans contain non-canonical level-2 headings (`## Non-Goals`,
`## Risks and Mitigations`, `## Anti-Patterns -- Hard Constraints`,
`## Changes`, `## Test plan`, `## Round 1 Disposition`, etc.); a closed
enumeration would sweep these into the last Completed phase's checksum
and produce false "Completed phase drifted" errors when the user later
edits an unrelated trailing section. Examples of headings the rule
terminates on (illustrative, NOT exhaustive): `## Phase`, `## Drift Log`,
`## Plan Review`, `## Plan Quality`, `## Test Spec Revisions` (this
skill's own trailing section — see Phase 5), and any other `## <name>`
the user has authored outside fenced code blocks.

### AC-ID assignment

Per Pending phase's `### Acceptance Criteria` block (scope limited to
the lines between that phase's `### Acceptance Criteria` heading and
the next `### ` heading or `## ` heading), classify each bullet by its
post-`- [ ] ` head using three predicates evaluated in order:

1. **Already-prefixed (canonical, idempotent skip):** matches the
   anchored regex
   `^- \[[ xX]\] AC-[0-9]+[a-z]?\.[0-9]+[a-z]? — ` (note the em-dash `—`
   and trailing space; the trailing `[a-z]?` after the second `[0-9]+`
   matches sub-letter forms like `AC-1.6b`/`AC-1.6c` — canonical, NOT
   ambiguous, preserved byte-identical on idempotent skip). Skip —
   bullet is left byte-identical.
2. **Ambiguous prefix (refuse to assign, surface advisory):** matches
   `^- \[[ xX]\] (?:[0-9A-Z]|\[)` (begins with a digit, a capital
   letter, OR a literal `[` — the bracket case catches scope-tag-leading
   bullets like `- [ ] [scope] given input`) but does NOT match the
   canonical predicate above. This catches work-item-style numerical
   prefixes (`- [ ] 1.1 — text`), bare AC references without the
   canonical separator (`- [ ] AC-3.2 covered when X happens`),
   scope-tag-leading lines (`- [ ] [scope] ...`), and any other bullet
   whose head looks ID-like. Do NOT prepend `AC-N.M — ` (that would
   yield double numerals like `AC-1.1 — 1.1 — text` or semantic
   conflicts like `AC-1.1 — AC-3.2 covered ...`). Instead, leave the
   bullet byte-identical and emit an advisory line:
   `Refused AC-ID assignment for "<plan-relative-path>:<lineno>" — ambiguous prefix; rewrite to canonical "AC-N.M — text" form to enable assignment.`
3. **Plain (assign):** the bullet's head begins with a lowercase
   letter, a backtick, or any non-digit/non-uppercase character — the
   unambiguous "no prefix" case. Rewrite to
   `- [ ] AC-<phase>.<n> — <text>` where `<phase>` is the phase number
   (including sub-letter, e.g. `3b`) and `<n>` increments per phase
   across the assigned bullets in that phase only.

**Never touch bullets outside `### Acceptance Criteria` blocks. Never
modify Completed phases' AC blocks.** AC-ID assignment is the only
allowed edit to Pending phases outside of appending `### Tests` (Phase
3). The criterion text is unchanged; only an `AC-N.M — ` prefix is
added. Justification, if a reviewer flags this as a modification: "ID
prefix is content-preserving metadata required to reference criteria
from the appended specs."

### Ac-less Pending phase

If a Pending non-delegate phase has no `### Acceptance Criteria` block
at all, the parser:

1. Appends the phase identifier to the parsed-state `ac_less:` list
   (newline-separated phase identifiers, mirroring the
   `delegate_phases:` schema).
2. Retains the same identifier in `non_delegate_pending_phases:` so
   Phase 4 WI 4.8 step 4's per-AC inner loop is automatically vacuous
   on it (no separate exclusion needed).
3. Emits the advisory line:
   `Phase N has no \`### Acceptance Criteria\` block — \`### Tests\` not appended; consider adding ACs and re-running.`

Phase 3 MUST NOT append a `### Tests` subsection to phases in
`ac_less:` (no ACs to verify against). Phase 4 MUST NOT enforce the
coverage floor on ac-less phases (the scope is empty by construction).

### Post-parse tracking

After the parser returns, write the research step marker:

```bash
printf 'completed: %s\n' "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.draft-tests.$TRACKING_ID.research"
```

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
  `"$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"` form
  for any helper from another skill (and from this skill's own
  scripts). The bare-`scripts/<name>` form is forbidden post-PR-#97 —
  those paths are removed by `/update-zskills`'s STALE_LIST migration
  on consumer checkouts. See
  `skills/update-zskills/references/script-ownership.md` for the full
  owner registry. **Source-tree zskills tests** use the equivalent
  `"$REPO_ROOT/skills/<owner>/scripts/<name>"` form, mirroring
  `skills/work-on-plans/SKILL.md` and `skills/zskills-dashboard/SKILL.md`.
- **No jq.** Parse YAML and JSON (including `.claude/zskills-config.json`
  in later phases) via bash regex with `BASH_REMATCH`. Idiom:
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

## Phase 2 — Language detection, test-file discovery, no-test-setup path

(Implementation deferred to Phase 2 of `plans/DRAFT_TESTS_SKILL_PLAN.md`.)

## Phase 3 — Drafting agent and test-spec format

(Implementation deferred to Phase 3 of `plans/DRAFT_TESTS_SKILL_PLAN.md`.)

The drafter MUST consume `ac_less:` from the parsed-state file: it MUST
NOT re-derive ac-less-ness by re-scanning phase content
(single-source-of-truth, mirrors WI 3.6's delegate-skip pattern). The
drafter MUST consume `delegate_phases:` from the parsed-state file: it
MUST NOT re-grep the plan or apply its own heuristic
(single-source-of-truth invariant with WI 4.8).

## Phase 4 — Adversarial review loop (QE personas)

(Implementation deferred to Phase 4 of `plans/DRAFT_TESTS_SKILL_PLAN.md`.)

### Reviewer / DA prompt prefix — guidance directive

If the user supplied positional-tail guidance (per the Arguments
section), prepend a `User-driven scope/focus directive:` section to
BOTH the reviewer and devil's-advocate prompts containing the guidance
text verbatim — exactly mirroring `skills/refine-plan/SKILL.md:50, :132`.
Empty guidance preserves byte-identical reviewer/DA prompt output (no
behavior change for invocations without trailing guidance tokens).

The agents treat this as **priming context** (what to pressure-test),
NOT as factual claims (still subject to verify-before-fix in the
refiner).

### NOT-a-finding list (authored fresh for this skill)

Inserted verbatim in BOTH reviewer and DA prompts. **NOT a finding:**
implausible failure modes under the product's stated operating
conditions (Bach); type-system-enforced preconditions;
performance/concurrency/security tests on non-load-bearing code; tests
duplicating existing specs in the same phase; MAX_INT/Unicode/clock-skew
tests on code whose ACs don't mention those domains; tests requiring
infrastructure not present (e.g., "spin up postgres" when the project
is config-only); tests that exist only to increase coverage numbers;
tests of framework code rather than product code; property-based tests
for functions with no meaningful algebraic properties.

### Zero findings is valid and correct (authored fresh for this skill)

Both prompts must state this in the output-format block. If the
reviewer has nothing substantive to flag, it outputs `## Findings` with
a single explicit line: `No findings — spec set meets the stated
criteria.` The loop treats this as a round-pass, not a bug. This
zero-findings path is NOT equivalent to "convergence" — convergence is
enforced mechanically against the positive definition in Design &
Constraints (which is the orchestrator's check, not the refiner's
self-call), and includes an orchestrator-level coverage-floor pre-check
that runs BEFORE agent dispatch each round.

### Orchestrator-level coverage-floor pre-check

Runs BEFORE dispatching reviewer/DA each round. The pre-check operates
on a per-round candidate file (see Phase 4 spec for full algorithm) and
reads `non_delegate_pending_phases:` from the parsed-state file as the
authoritative scope for ACs subject to the coverage floor. The
pre-check MUST NOT re-derive delegate-classification.

### Convergence is the orchestrator's judgment, not the refiner's self-call

Mirroring `skills/refine-plan/SKILL.md:383` and
`skills/draft-plan/SKILL.md:474`: the refiner produces a disposition
table; the orchestrator (the skill body itself, not the agent) reads
the table and applies the four positive conditions. NEVER accept
"CONVERGED", "no further refinement needed", or equivalent self-call
from the refiner agent as authoritative — the refiner just refined; it
is biased toward declaring its own work done. This is a recurring
failure mode in practice (see CLAUDE.md memory anchor
`feedback_convergence_orchestrator_judgment.md`).

## Phase 5 — Backfill mechanics and re-invocation

(Implementation deferred to Phase 5 of `plans/DRAFT_TESTS_SKILL_PLAN.md`.)

### Backfill phase placement (broad form)

Scan for the first trailing level-2 heading at column 0 that is NOT a
`## Phase ...` heading, is NOT inside a fenced code block, and appears
AFTER the last `## Phase`. **The rule is the broad form — ANY non-phase
`## <name>` outside fenced code blocks terminates the search, not a
closed list.** Use the same awk-style `in_code` state-tracker as the
checksum-boundary scan — heading detection runs only when
`in_code == 0`.

### `## Test Spec Revisions` placement (broad form)

This section is placed AFTER any existing trailing non-phase level-2
sections — **the broad form: any `## <name>` (other than `## Phase ...`)
outside fenced code blocks the user has authored after the last phase
counts as a trailing section, not a closed list.** Use the same
awk-style `in_code` state-tracker — heading detection runs only when
`in_code == 0` so `## ` headings inside ` ``` ` fences are not mistaken
for trailing sections.

## Phase 6 — Tests, conformance, worked example, mirror

(Implementation deferred to Phase 6 of `plans/DRAFT_TESTS_SKILL_PLAN.md`.)

## Key Rules

- **NEVER modify Completed phases.** Immutability is verified
  mechanically via SHA-256 checksums. Not even heading typo fixes. AC-ID
  assignment is allowed ONLY in Pending phases.
- **Section boundary is the broad form, fenced-code-block-aware.** Any
  `## <name>` at column 0 outside fenced code blocks terminates the
  prior section. The bytes within fences are still part of the section;
  only the boundary detection skips them.
- **Single source of truth for delegate / ac-less classification.** The
  parsed-state file's `delegate_phases:` and `ac_less:` lists are the
  authoritative source. Phase 3 and Phase 4 MUST consume them — never
  re-derive by re-scanning the plan body.
- **Convergence is the orchestrator's call** based on the refiner's
  disposition table, not the refiner's self-declaration. Run all
  budgeted rounds unless the four positive conditions are all met.
- **Empty guidance preserves byte-identical reviewer/DA prompts.** The
  `User-driven scope/focus directive:` section is emitted ONLY when
  guidance text is non-empty.
- **No jq.** Bash regex with `BASH_REMATCH` for all JSON / YAML
  parsing.
- **Edit `skills/draft-tests/` only.** Mirror to
  `.claude/skills/draft-tests/` via `bash scripts/mirror-skill.sh
  draft-tests` — NEVER inline `cp` / `rm -rf`. Per CLAUDE.md memory
  anchor `feedback_claude_skills_permissions.md`, edits to
  `.claude/skills/` trigger permission storms; mirror discipline is the
  workaround.
- **Ultrathink throughout.** Every agent should use careful, thorough
  reasoning.

## Edge Cases

- **Plan file doesn't exist** — error: `Plan file '<path>' not found.`
- **Plan file has no Progress Tracker** — error: `No Progress Tracker
  found in '<path>'. ...`
- **Plan with all-Completed phases AND no gaps** — exit clean with the
  `nothing to draft or backfill` message.
- **Plan with all-Completed phases AND ≥1 Completed-phase gap** — does
  NOT exit; proceeds into Phase 5 backfill.
- **Plan with sub-phases (3a/3b)** — each sub-phase classified
  independently. Sub-phase `3a` can be Completed while `3b` is Pending.
- **Pending phase with no `### Acceptance Criteria` block** — appended
  to `ac_less:`. No `### Tests` subsection is appended in Phase 3. No
  coverage-floor finding is synthesised in Phase 4. The advisory line
  is emitted in the skill's final output.
- **Pending phase with `### Execution: delegate ...`** — listed in
  `delegate_phases:`. No `### Tests` subsection is appended in Phase 3
  (test coverage is the delegated skill's responsibility). The
  coverage floor does not enforce on this phase.
- **Bullet inside an AC block with an ambiguous prefix** (`- [ ] 1.1 —
  ...`, `- [ ] AC-3.2 covered when X happens`, `- [ ] [scope] ...`) —
  left byte-identical. Advisory emitted naming the file:line.
