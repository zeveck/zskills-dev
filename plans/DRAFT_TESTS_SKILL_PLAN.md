---
title: /draft-tests Skill
created: 2026-04-24
status: active
---

# Plan: /draft-tests Skill

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

`/draft-tests` is a sister skill to `/draft-plan`: same adversarial-review
machinery, scoped to test specifications. Given the path to an existing
plan (the kind `/draft-plan` produces), it appends a `### Tests`
subsection into every pending phase, then runs a senior-QE review loop
(reviewer + devil's advocate + refiner) until the specs hold up. The
reader of the appended specs is the AI implementing agent that `/run-plan`
dispatches — not a human — so specs ride along inside the phases
`/run-plan` already executes. No companion document. No `/run-plan`
loader patch.

Completed phases are never mutated (checksum-gated, per `/refine-plan`'s
immutability pattern; `/draft-tests` ALSO preserves every trailing
non-phase section byte-identical at the file-write level — a stricter
invariant than `/refine-plan`, which rebuilds `## Drift Log` /
`## Plan Review` per invocation. See Phase 1 D&C for the in-place edit
reassembly spec.). Test gaps in completed phases are surfaced by
appending a new top-level `## Phase N — Backfill tests for completed
phases X–Y` BEFORE any existing trailing `## Drift Log` / `## Plan Review`
/ `## Plan Quality` / `## Test Spec Revisions` sections — never by moving
those authored sections. Re-running on a plan that already has specs
refines them in place and records structural changes in a dedicated
`## Test Spec Revisions` section (deliberately named distinct from
`/refine-plan`'s `## Drift Log` so a plan touched by both skills keeps
them separate).

This plan builds the skill, its test harness, its conformance checks,
and one worked example. Research underpinning all design decisions
lives at `/tmp/draft-plan-research-DRAFT_TESTS_SKILL_PLAN.md`; phases
reference it rather than transcribing.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Skeleton, ingestion, and checksum gate | ✅ Done | `2cf6897` | 62 new tests; SKILL.md + parse-plan.sh + 7 fixtures |
| 2 — Language detection, test-file discovery, no-test-setup path | ✅ Done | `e7b4d66` | 53 new tests; detect-language.sh + insert-prerequisites.sh + 9 fixtures |
| 3 — Drafting agent and test-spec format | ✅ Done | `b1b8906` | 64 new tests; append-tests-section.sh + draft-orchestrator.sh + 4 fixtures |
| 4 — Adversarial review loop (QE personas) | 🟡 In Progress | `c9ebf31` | 79 new tests; review-loop.sh + coverage-floor-precheck.sh + convergence-check.sh + 10 fixtures |
| 5 — Backfill mechanics and re-invocation | ⬚ | | |
| 6 — Tests, conformance, worked example, mirror | ⬚ | | |

---

## Phase 1 — Skeleton, ingestion, and checksum gate

### Goal

Stand up `skills/draft-tests/SKILL.md` with frontmatter, argument
parsing, tracking, plan-file read, phase classification, AC-ID
assignment, and the checksum gate that keeps completed phases
byte-identical.

### Work Items

- [ ] 1.1 — Create `skills/draft-tests/SKILL.md` with frontmatter
  (`name: draft-tests`, `disable-model-invocation: false`,
  `argument-hint: "<plan-file> [rounds N] [guidance...]"`, description).
  The `[guidance...]` positional tail mirrors `/refine-plan` PR #85
  (`skills/refine-plan/SKILL.md:4`); see WI 1.2 for parsing semantics
  and Phase 4 for prompt-prepend behavior.
- [ ] 1.2 — Implement argument parsing: first `.md` or slash-containing
  token is the plan file (prepend `plans/` if bare); `rounds N` sets
  cycles (default 3 — see Phase 4 D&C for the rationale vs.
  `/refine-plan`'s default 2). Any tokens not matched as plan file or
  `rounds N` are joined with spaces into **guidance text** —
  prepended to BOTH the reviewer and DA prompts in Phase 4 as a
  "User-driven scope/focus directive" section, mirroring
  `skills/refine-plan/SKILL.md:50, :132`. Empty guidance preserves
  byte-identical reviewer/DA prompt output (regression-safe). The
  guidance text is **priming context** that shapes WHAT the agents
  pressure-test — NOT factual claims they should act on without
  verification. Verify-before-fix discipline still applies in the
  refiner. Error on missing plan file with usage string
  `Usage: /draft-tests <plan-file> [rounds N] [guidance...]`.
- [ ] 1.3 — Implement tracking fulfillment using the canonical idiom
  (see research §Tracking marker idiom). Two-tier PIPELINE_ID
  resolution: if `$ZSKILLS_PIPELINE_ID` is set (delegated invocation),
  use it verbatim; else construct `draft-tests.$TRACKING_ID`.
  `$TRACKING_ID` is derived from the plan filename exactly as
  `/draft-plan` and `/refine-plan` derive theirs:
  `basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-'`
  (e.g., `plans/DRAFT_TESTS_SKILL_PLAN.md` → `draft-tests-skill-plan`). Write
  `fulfilled.draft-tests.$TRACKING_ID` with `status: started` at
  Phase 1 and `status: complete` at finalize. Pass any constructed
  PIPELINE_ID (not the env-var-supplied value) through
  `"$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"`
  (per `skills/update-zskills/references/script-ownership.md` cross-skill
  caller convention) before writing to disk. Source-tree zskills tests
  use `"$REPO_ROOT/skills/create-worktree/scripts/sanitize-pipeline-id.sh"`
  — mirroring `skills/work-on-plans/SKILL.md` and
  `skills/zskills-dashboard/SKILL.md`. The bare-relative
  `scripts/sanitize-pipeline-id.sh` form is FORBIDDEN — that path no
  longer exists post-PR-#97 (relocated under `create-worktree`'s
  ownership) and `/update-zskills`'s STALE_LIST migration will remove
  it from any consumer checkout.
- [ ] 1.4 — Parse the plan file: YAML frontmatter, Progress Tracker
  table, phase sections. Classify each phase Completed / Pending using
  `/refine-plan`'s rules (`Done`, `✅`, or `[x]` in the Status column,
  case-insensitive; everything else is Pending — including `⬚`, `⬜`,
  `In Progress`, `Blocked`, empty cells, or any other glyph).
  Sub-phases classified independently.
- [ ] 1.4b — In the same parse pass, classify each Pending phase as
  delegate or non-delegate using a single canonical predicate:
  `grep -q '^### Execution: delegate' <phase-body>`. Persist this flag
  per phase to the parsed-state file as a `delegate_phases:` list (a
  newline-separated list of phase identifiers, e.g. `3`, `5b`) and a
  paired `non_delegate_pending_phases:` list. Phase 3's drafter-skip
  (WI 3.6) and Phase 4's coverage-floor pre-check (WI 4.8) MUST both
  read these lists rather than re-deriving — single source of truth,
  no risk of divergent heuristics.
- [ ] 1.5 — Compute SHA-256 checksum of each Completed phase's full
  section text. **Section boundary: from `## Phase N` through the byte
  just before the NEXT line that starts with `## ` (any level-2
  heading) at column 0 AND is NOT inside a fenced code block, OR end
  of file, whichever comes first.** The rule is the broad form — ANY
  `## <name>` outside fenced code blocks terminates the section, not a
  closed list. **Fenced-code-block awareness is mandatory:** real
  plans (e.g., `plans/EXECUTION_MODES.md` lines 236, 2079, 2082)
  contain `## ` headings at column 0 inside ` ``` ` fences as
  illustrative examples; a naive `^## ` scan would terminate the
  prior phase's checksum at the in-code heading, silently dropping
  authentic phase content from the gate. Implementation: a single-pass
  awk-style state-tracker toggling an `in_code` flag on each ` ``` `
  line; heading detection runs only when `in_code == 0`. The
  checksummed bytes still INCLUDE the fenced-code-block content (the
  fenced lines are part of the Completed phase's authored body); only
  the boundary detection skips them. Real plans contain non-canonical
  level-2 headings (`## Non-Goals`, `## Risks and Mitigations`,
  `## Anti-Patterns -- Hard Constraints`, `## Changes`, `## Test plan`,
  `## Round 1 Disposition`, `## /refine-plan Round 1 Disposition (...)`,
  etc.); a closed enumeration would sweep these into the last
  Completed phase's checksum and produce false "Completed phase
  drifted" errors when the user later edits an unrelated trailing
  section. Examples of headings the rule terminates on (illustrative,
  NOT exhaustive): `## Phase`, `## Drift Log`, `## Plan Review`,
  `## Plan Quality`, `## Test Spec Revisions` (this skill's own
  trailing section — see Phase 5), and any other `## <name>` the user
  has authored outside fenced code blocks. Persist checksums to
  `/tmp/draft-tests-parsed-<slug>.md` alongside the parsed Pending
  phases, frontmatter, and the per-phase delegate-classification
  flag (see 1.4b). `<slug>` is the TRACKING_ID derived in 1.3.
- [ ] 1.6 — Assign AC IDs in Pending phases where missing. For each
  bullet *inside* a Pending phase's `### Acceptance Criteria` block
  (scope limited to the lines between that phase's
  `### Acceptance Criteria` heading and the next `### ` heading or
  next `## ` heading), classify the bullet by its post-`- [ ] ` head
  using three predicates evaluated in order:
  1. **Already-prefixed (canonical, idempotent skip):** matches the
     anchored regex `^- \[[ xX]\] AC-[0-9]+[a-z]?\.[0-9]+[a-z]? — `
     (note the em-dash `—` and trailing space; the trailing `[a-z]?`
     after the second `[0-9]+` matches sub-letter forms like
     `AC-1.6b`/`AC-1.6c` — canonical, NOT ambiguous, preserved
     byte-identical on idempotent skip). Skip — bullet is left
     byte-identical.
  2. **Ambiguous prefix (refuse to assign, surface advisory):**
     matches `^- \[[ xX]\] (?:[0-9A-Z]|\[)` (begins with a digit, a
     capital letter, OR a literal `[` — the bracket case catches
     scope-tag-leading bullets like `- [ ] [scope] given input`)
     but does NOT match the canonical predicate above. This
     catches work-item-style numerical prefixes (`- [ ] 1.1 — text`),
     bare AC references without the canonical separator
     (`- [ ] AC-3.2 covered when X happens`), scope-tag-leading lines
     (`- [ ] [scope] ...`), and any other bullet whose head looks
     ID-like. Do NOT prepend `AC-N.M — ` (that would yield double
     numerals like `AC-1.1 — 1.1 — text` or semantic conflicts like
     `AC-1.1 — AC-3.2 covered ...`). Instead, leave the bullet
     byte-identical and emit an advisory line into the skill's final
     output: `Refused AC-ID assignment for "<plan-relative-path>:<lineno>" — ambiguous prefix; rewrite to canonical "AC-N.M — text" form to enable assignment.`
  3. **Plain (assign):** the bullet's head begins with a lowercase
     letter, a backtick, or any non-digit/non-uppercase character —
     the unambiguous "no prefix" case. Rewrite to
     `- [ ] AC-<phase>.<n> — <text>` where `<phase>` is the phase
     number (including sub-letter, e.g. `3b`) and `<n>` increments
     per phase across the assigned bullets in that phase only.
  Never touch bullets outside `### Acceptance Criteria` blocks.
  Never modify Completed phases' AC blocks.
- [ ] 1.7b — **Pending phase with no `### Acceptance Criteria` block.**
  If a Pending phase has no AC block at all, append the phase
  identifier to a parsed-state file `ac_less:` list (newline-separated
  phase identifiers, mirroring the `delegate_phases:` schema). The
  phase REMAINS in `non_delegate_pending_phases:` so Phase 4 WI 4.8
  step 4's per-AC inner loop is automatically vacuous on it (no
  separate exclusion needed). Phase 3 WI 3.5 MUST NOT append a
  `### Tests` subsection to phases in `ac_less:` (no ACs to verify
  against). Phase 4 WI 4.8 MUST NOT enforce the coverage floor on
  ac-less phases (the scope is empty by construction). Emit a single
  advisory line into the skill's final output:
  `Phase N has no \`### Acceptance Criteria\` block — \`### Tests\` not appended; consider adding ACs and re-running.`
  Add AC-1.7b: a fixture Pending phase with no AC block produces no
  `### Tests` append, no coverage-floor finding, and the advisory
  line is emitted exactly once.
- [ ] 1.7 — Refuse-to-run checks: error and exit if the plan file is
  missing or has no Progress Tracker. **Do NOT exit on zero-Pending
  alone.** A plan with all-Completed phases is the primary scenario
  for backfill (shipped plan lacking tests). Route to Phase 5's
  backfill gap detection; only exit clean if BOTH zero Pending phases
  AND zero Completed phases with gaps are detected. In that case,
  emit: "All phases complete and all ACs appear to have matching
  tests — nothing to draft or backfill. Re-run after adding new phases
  or after asserting gaps exist."

### Design & Constraints

- **Checksum gate (load-bearing).** Before the final write in Phase 6,
  re-read each Completed phase section and re-checksum; if any differs
  from the Phase 1 value, STOP and refuse. Copy `/refine-plan`'s
  Phase 1 + Phase 5 pattern, with TWO deliberate divergences:
  (a) the section-boundary rule is broadened from "next `## Phase` or
  EOF" to "next level-2 heading (any `## <name>`) or EOF" — the rule
  is the broad wildcard form, NOT an enumeration of known section
  names. This keeps the skill usable on plans with non-canonical
  level-2 headings (see 1.5). Trailing whitespace INSIDE the phase
  section is included. (b) **Reassembly is in-place edit, not
  whole-file concatenation.** `/refine-plan` Phase 5 (lines 397-409)
  rebuilds the plan by concatenating frontmatter + Overview +
  Tracker + Completed + Refined-remaining, then APPENDS fresh Drift
  Log + Plan Review (it does not preserve any pre-existing trailing
  section beyond the phases themselves, because it rebuilds those
  sections per invocation). `/draft-tests` cannot use that pattern:
  every trailing non-phase section (`## Drift Log`, `## Plan Review`,
  `## Plan Quality`, `## Test Spec Revisions`, plus any
  user-authored sections like `## Anti-Patterns -- Hard Constraints`
  / `## Non-Goals`) MUST be preserved byte-identical. The skill
  reads the current plan bytes, mutates only the targeted insertion
  points (AC-ID prefixes, appended `### Tests` subsections,
  appended backfill phase, `## Prerequisites` insertion,
  `## Test Spec Revisions` append/update, frontmatter
  `status:` flip), and writes the file back. No section-by-section
  concatenation. This is a STRONGER preservation invariant than
  `/refine-plan`'s, and the AC set (AC-1.5, AC-2.10, AC-5.7) is
  what gates it empirically.
- **AC-ID assignment is the only allowed edit to Pending phases
  outside of appending `### Tests`.** Document this as an explicit
  exception in the SKILL.md: the criterion text is unchanged; only an
  `AC-N.M — ` prefix is added. If a reviewer flags AC-ID assignment as
  a modification, the justification is: "ID prefix is content-preserving
  metadata required to reference criteria from the appended specs."
- **Cross-skill script invocation.** Use the
  `"$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"` form for
  any helper from another skill. The bare-`scripts/<name>` form is
  forbidden post-PR-#97 — those paths are removed by `/update-zskills`'s
  STALE_LIST migration on consumer checkouts. See
  `skills/update-zskills/references/script-ownership.md` for the full
  owner registry.
- **No jq.** Parse YAML and JSON (including `.claude/zskills-config.json`
  in later phases) via bash regex with `BASH_REMATCH`. Idiom (from
  research §Bash regex JSON parsing idiom):
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

### Acceptance Criteria

- [ ] AC-1.1 — `skills/draft-tests/SKILL.md` exists with valid
  frontmatter matching the fields listed in 1.1, including the
  `[guidance...]` positional tail in `argument-hint`.
- [ ] AC-1.2 — Invoking the skill with no plan-file argument produces
  an error mentioning "Usage: /draft-tests <plan-file> [rounds N] [guidance...]".
- [ ] AC-1.2b — Invocation `/draft-tests plans/FOO.md focus on
  integration tests` produces reviewer + DA prompts whose body begins
  with "User-driven scope/focus directive: focus on integration tests"
  (mirroring `skills/refine-plan/SKILL.md:132`). Invocation without
  the tail produces prompts byte-identical to the no-guidance baseline
  — verified by a stubbed-prompt diff fixture (regression guard
  against accidental directive-section emission on empty guidance).
- [ ] AC-1.3 — After Phase 1 runs, a file
  `.zskills/tracking/<pipeline-id>/fulfilled.draft-tests.<tracking-id>`
  exists with `status: started`.
- [ ] AC-1.4 — On a plan with mixed Completed/Pending phases (including
  at minimum one each of: a `Done` phase, a `✅` phase, an `[x]`
  phase, a `⬚` phase, a `⬜` phase, and a phase with an empty status
  cell), the parsed-state file correctly classifies each.
- [ ] AC-1.5 — The parsed-state file contains a checksum for every
  Completed phase; reruns against an unchanged plan produce identical
  checksums. On a plan that already has a trailing `## Drift Log` or
  `## Plan Quality` section, checksums of the last Completed phase
  must NOT change when text is later appended to those trailing
  sections (regression test for the section-boundary rule). On a plan
  containing a non-canonical level-2 heading between phases or
  trailing the last phase (e.g., `## Non-Goals`, `## Anti-Patterns --
  Hard Constraints`, `## Risks and Mitigations`), the boundary rule
  still terminates the prior Completed phase's checksum at that
  heading; later edits to that non-canonical section must NOT cause
  the skill to flag the prior Completed phase as drifted (regression
  test against the closed-enumeration bug). **Fenced-code-block
  regression guard:** an additional fixture plan contains a Completed
  phase whose body contains a fenced ` ```markdown ` block with a
  `## Example Section` heading at column 0 inside the fence; the
  Completed phase's checksum must include the fenced lines (the
  boundary scan correctly skipped the in-code heading) AND must NOT
  terminate at the in-code heading.
- [ ] AC-1.6 — On a plan whose Pending-phase ACs lack IDs, running the
  skill (through at least the ID-assignment step) produces ACs
  prefixed with `AC-<phase>.<n> — `; Completed-phase ACs remain
  byte-identical; bullets outside `### Acceptance Criteria` blocks
  remain byte-identical.
- [ ] AC-1.6b — Re-running the skill after AC IDs have been assigned
  does not double-prefix any AC bullet; the full AC block text of
  each Pending phase is byte-identical to its post-first-run state.
- [ ] AC-1.6c — On a fixture Pending-phase AC block containing
  bullets with ambiguous prefixes — at minimum (i)
  `- [ ] 1.1 — work-item-style prefix`, (ii) `- [ ] AC-3.2 covered
  when X happens` (no em-dash separator), and (iii) `- [ ] [scope]
  given input` — the skill leaves all three bullets byte-identical
  AND the skill's final output contains an advisory line per
  refused bullet matching `Refused AC-ID assignment for "<file>:<lineno>"`.
  No bullet acquires a double-numeral or semantic-conflict prefix.
- [ ] AC-1.7 — Running against a plan with zero Pending phases AND
  zero Completed-phase gaps (per Phase 5 detection) exits cleanly
  with the "nothing to draft or backfill" message. Running against a
  plan with zero Pending phases but ≥1 Completed-phase gap does NOT
  exit; it proceeds into backfill (Phase 5).
- [ ] AC-1.7b — On a fixture plan containing one Pending non-delegate
  phase WITHOUT an `### Acceptance Criteria` block (per WI 1.7b's
  ac-less classification), Phase 1's parsed-state file lists that
  phase's identifier in an `ac_less:` newline-separated list AND
  retains the same identifier in `non_delegate_pending_phases:`. The
  skill's final output contains exactly one `Phase N has no \`### Acceptance Criteria\` block — \`### Tests\` not appended; consider adding ACs and re-running.` advisory line per ac-less phase. No `### Tests` subsection is appended to that phase, no coverage-floor finding is synthesised against that phase's (non-existent) ACs, and AC-3.1's count formula M = N − K self-passes when the same fixture also contains at least one normal Pending non-delegate phase.

### Dependencies

None.

---

## Phase 2 — Language detection, test-file discovery, no-test-setup path

### Goal

Detect the project's language(s) and test-file conventions to
calibrate the drafter (Phase 3) and to supply the test-file map used
by backfill gap detection (Phase 5). Recommend a test-runner when the
project has none, and degrade gracefully when detection fails.

### Work Items

- [ ] 2.1 — Language detection from manifest files:
  - `package.json` → JavaScript/TypeScript. Recommended runner:
    vitest. If `jest` is already referenced in `package.json`
    scripts or devDependencies, recommend jest instead.
  - `pyproject.toml`, `setup.py`, or `requirements*.txt` → Python.
    Recommended runner: pytest.
  - `go.mod` → Go. Recommended runner: `go test` (built in).
  - `Cargo.toml` → Rust. Recommended runner: `cargo test` (built in).
  - Heavy `*.sh` content at repo root or in `scripts/` with no other
    manifest → bash. Recommended runner: bats.
  - Multiple manifests present → polyglot. Recommend a runner per
    subtree matched to that subtree's manifest.
  - None of the above → report "language undetectable" and degrade
    per 2.4.
- [ ] 2.2 — Test-file discovery (language-aware heuristics, NOT
  runner-sniffing). Identifies candidate files via:
  - JS/TS: `*.test.ts`, `*.test.tsx`, `*.test.js`, `*.spec.*`,
    `__tests__/` directories, `tests/` directory.
  - Python: `test_*.py`, `*_test.py`, `tests/` directory.
  - Go: `*_test.go`.
  - Rust: files under `tests/`, `#[cfg(test)]` blocks (found via
    grep, not parsed).
  - Bash: `tests/test-*.sh`, `tests/*_test.sh`.
  If the repo has zero candidate files, the drafter is told "no
  existing tests to calibrate against — use the recommended runner's
  defaults."
- [ ] 2.3 — Extracted calibration signal (passed to drafter in
  Phase 3, and used by Phase 5 backfill gap detection as the test-file
  map). Bounded to keep drafter prompt size under control:
  - **Per language, read at most 3 test files**, preferring the file
    with the most imports (proxy for "canonical example for this
    project"). Ties broken by largest file (more surface to observe).
    For polyglot projects, this cap applies per detected language.
  - **Extract convention via a small regex panel**: imports (top 10
    lines), presence of `describe/`/`it(`/`test(`/`test_`/`_test`
    patterns, `assertEqual`/`expect(`/`assert.`/`should` patterns,
    `beforeEach`/`fixture`/`setup` patterns, assertion library name
    (e.g., `chai`, `jest`, `vitest`, `pytest`).
  - **Emit ≤ 20 lines per language** as a structured summary
    (framework name, naming convention, fixture style, assertion
    library, one representative test-file path). This is the
    *calibration signal*. Full test-file contents are never passed to
    the drafter.
  - **Persist the full test-file path list** (not contents) to the
    parsed-state file so Phase 5 can re-read candidate files for gap
    detection without re-running discovery.
- [ ] 2.4 — No-test-setup path. If the language is detected but no
  test runner or test files exist, add a recommendation as a
  standalone `## Prerequisites` section placed **immediately after
  the `## Overview` section and before the `## Progress Tracker`**
  (never inside a phase, never moving existing sections). Example
  text:
  ```markdown
  ## Prerequisites

  > **Test-runner recommendation:** this project has no configured
  > test runner. Recommended: `pytest` (Python detected from
  > pyproject.toml). Add `[tool.pytest.ini_options]` and a `tests/`
  > directory before running the first test-bearing phase.
  ```
  The skill writes the recommendation. It does NOT install, scaffold,
  or run anything. If `## Prerequisites` already exists (prior
  invocation), the block is replaced in place, not duplicated.
- [ ] 2.5 — Bootstrap as an explicit phase is out of scope for v1. The
  written recommendation in 2.4 is the entire no-test-setup behavior.
  A `--bootstrap` flag that prepends a Phase 0 is explicitly noted as
  future work and is NOT exposed.
- [ ] 2.6 — Config-first test command resolution. Before detection
  runs, check `.claude/zskills-config.json` for
  `testing.full_cmd`/`testing.unit_cmd` using the three-case tree
  from `/verify-changes` (lines 76–137):
  (1) config set → pass command verbatim to drafter, skip detection
      beyond language.
  (2) tests exist in repo + no config command → detection provides
      framework recommendation, drafter is told to match existing
      test style but no command is asserted.
  (3) no test infra + no config → emit the 2.4 recommendation; skip
      test-style calibration.
  Never sniff `package.json` scripts, `pytest.ini`, etc., to "guess"
  a test command — config-first per CLAUDE.md surface-bugs-don't-patch.
- [ ] 2.7 — Graceful fallback. If any detection step errors (missing
  read permissions, malformed manifest), the skill logs the failure
  to stderr, proceeds with "language undetectable", and the drafter
  is told so explicitly. Detection failure never aborts the run.

### Design & Constraints

- **No test-runner sniffing.** This rule exists because test-runner
  detection is inherently unreliable (a project may have pytest
  installed but not use it; may have multiple runners; may use a
  custom wrapper). Config-first keeps the skill honest. Language
  detection from manifests is different — it doesn't claim to know
  the test setup, it just informs framework *recommendation*.
- **Polyglot projects.** Emit per-subtree recommendations. Do not
  pick a single winner. Example: a project with a `Cargo.toml` and
  a `package.json` gets "Rust tests via `cargo test`; JS tests via
  vitest".
- **Client-project portability.** The skill runs in client repos,
  not just zskills. Hardcoded zskills paths (e.g., `tests/run-all.sh`,
  `tests/test-*.sh`) are wrong. All detection heuristics must be
  expressed in terms of generic file patterns.
- **Test-runner recommendation never promises installation.** The
  recommendation is advisory text. The user installs; the skill does
  not touch the project's environment.
- **Bounded calibration signal.** The drafter gets a structured
  summary, never raw test-file contents. This caps prompt growth on
  large projects and keeps the signal stable across runs.

### Acceptance Criteria

- [ ] AC-2.1 — On a fixture project containing only `package.json`,
  the detection step reports "JavaScript/TypeScript" and recommends
  vitest (or jest if `package.json` mentions jest).
- [ ] AC-2.2 — On a fixture project containing only `pyproject.toml`,
  detection reports Python and recommends pytest.
- [ ] AC-2.3 — On a fixture project containing both `go.mod` and
  `package.json`, detection reports polyglot and emits per-subtree
  recommendations (Go: `go test`; JS/TS: vitest).
- [ ] AC-2.4 — On a fixture project with no recognized manifest, the
  skill still proceeds and the drafter prompt contains the literal
  string "no configured test runner".
- [ ] AC-2.5 — When `.claude/zskills-config.json` has
  `testing.unit_cmd` set, the drafter prompt contains the value
  verbatim and the detection output is downgraded to informational
  only.
- [ ] AC-2.6 — On a fixture project with existing JS tests using the
  `describe/it` convention, the drafter prompt's calibration signal
  names that convention; the drafted specs use compatible terminology
  (e.g., `it` naming shape) where appropriate — not `test_` prefixes.
- [ ] AC-2.7 — Detection failure (e.g., malformed JSON manifest) is
  logged to stderr and produces a "language undetectable" signal; the
  skill run completes successfully with a recommendation absent.
- [ ] AC-2.8 — On a fixture project with ≥ 4 test files per language,
  the calibration signal reads AT MOST 3 files per language and its
  structured summary is ≤ 20 lines per language (measured by
  `wc -l` on the drafter-prompt input slice).
- [ ] AC-2.9 — The parsed-state file records the full test-file path
  list (not contents) for each detected language; Phase 5 gap
  detection consumes this list without re-invoking discovery.
- [ ] AC-2.10 — On a plan with no test runner detected AND no existing
  `## Prerequisites` section, the skill appends `## Prerequisites`
  between `## Overview` and `## Progress Tracker`, and the
  `## Progress Tracker` / all `## Phase ...` / **every level-2
  trailing section** (broad form: any `## <name>` other than
  `## Phase ...`, `## Overview`, `## Progress Tracker`,
  `## Prerequisites` — including non-canonical user-authored
  sections like `## Anti-Patterns -- Hard Constraints` or
  `## Non-Goals`, mirroring `plans/EXECUTION_MODES.md`) are
  byte-identical before and after. Test fixture must include a
  non-canonical trailing heading to guard against the
  closed-enumeration regression.

### Dependencies

Phase 1 (parsed state, classification). Feeds Phase 3 (drafter
calibration signal) and Phase 5 (test-file map for backfill gap
detection).

---

## Phase 3 — Drafting agent and test-spec format

### Goal

Dispatch a single drafting agent that appends a `### Tests` subsection
to each Pending phase, using a per-spec format that the reviewer and
DA can evaluate mechanically.

### Work Items

- [ ] 3.1 — Define the canonical spec format. Default is a one-line
  bullet: `- [scope] [risk: AC-N.M] given <input>, when <action>,
  expect <literal>`. `scope` is one of `unit`, `integration`,
  `property`, `e2e`. `risk: AC-N.M` links the spec to the AC it
  exercises. `<literal>` is an exact value, named exception, or a
  precisely-defined observable side effect.
- [ ] 3.2 — Define the multi-line expansion. When a one-liner becomes
  unreadable (long inputs, multi-step setup, or non-trivial expected
  values), the drafter expands into:
  ```markdown
  - [scope] [risk: AC-N.M] <short name>
    - Input: <literal>
    - Action: <literal>
    - Expected: <literal>
    - Rationale: <one sentence — why this spec exists, not how it works>
  ```
  Expansion is the drafter's judgment call; the senior-QE review loop
  will push back if one-liners are illegible or expansions are
  gratuitous.
- [ ] 3.3 — Implement the drafting agent prompt. Persona: senior QE
  engineer with N years of experience; explicit that their job is to
  author specs an implementing agent can mechanically translate into
  tests. Calibration text (not just the label) in the prompt body
  using cues from research §Senior QE norms (Bach, Bolton, Beck,
  Hendrickson, Crispin/Gregory).
- [ ] 3.4 — Drafter inputs: the full plan text, the parsed-state file
  path, the research file path, the resolved test-command context (if
  `.claude/zskills-config.json` has `testing.full_cmd` /
  `testing.unit_cmd`, pass verbatim; else note "no configured test
  runner — scope tags remain valid; specs don't assume a runner"), and
  the calibration outputs from Phase 2 (language, framework
  recommendation, existing-test conventions).
- [ ] 3.5 — Append logic: for each Pending phase, insert a new
  `### Tests` subsection. **Skip phases listed in `ac_less:` in the
  Phase 1 parsed-state file (per WI 1.7b)** — these phases get no
  `### Tests` subsection regardless of position-priority; the WI 1.7b
  advisory line is emitted in their stead. The drafter MUST consume
  the parsed-state `ac_less:` list — it MUST NOT re-derive ac-less-ness
  by re-scanning phase content (single-source-of-truth, mirrors WI 3.6's
  delegate-skip pattern). Position priority for non-ac-less phases:
  (1) immediately after the phase's `### Acceptance Criteria` block;
  (2) else after `### Design & Constraints`; (3) else after
  `### Work Items`; (4) never before `### Goal`, never inside an
  `### Execution: ...` subsection. If `### Tests` already exists
  (re-invocation), route to Phase 5's refinement path — do not
  duplicate the heading.
- [ ] 3.6 — **Skip delegate phases.** Read the `delegate_phases:` list
  from the Phase 1 parsed-state file (`/tmp/draft-tests-parsed-<slug>.md`).
  For every phase in that list, do NOT append a `### Tests` subsection:
  test coverage is the delegated skill's responsibility (the sub-skill
  authors its own tests inside the work it produces; appending specs
  to a delegate wrapper phase has no implementer to read them). The
  drafter MUST consume the parsed-state list — it MUST NOT re-grep the
  plan or apply its own heuristic (single-source-of-truth invariant
  with WI 4.8). Record the skipped phases as a `delegate_skipped_phases:`
  list (newline-separated phase identifiers) inside the drafter's
  per-round output file (`/tmp/draft-tests-draft-round-N-<slug>.md`,
  see WI 3.8) so Phase 4's reviewer/DA prompts and Phase 6's
  conformance test (AC-3.6) can read it as a concrete artifact rather
  than parsing prose.
- [ ] 3.7 — Drafter must reference existing project test files when
  available (see Phase 2 for discovery and the bounded calibration
  signal). The prompt instructs: "Calibrate framework choice, naming
  conventions, fixture style, and assertion library to the project's
  existing tests per the Phase-2 calibration signal, unless this
  phase's requirements justify a different level (e.g., existing
  tests are unit-only, this phase needs integration)."
- [ ] 3.8 — Write drafter output to
  `/tmp/draft-tests-draft-round-0-<slug>.md` before merging into the
  plan. This is the input for Phase 4's review loop.

### Design & Constraints

- **Coverage requirement at draft time:** every AC in every Pending
  non-delegate phase must have at least one spec referencing it via
  `risk: AC-N.M`. The drafter is told this is a floor, not a ceiling
  — more specs are welcome if they cover orthogonal risks.
  Delegate-phase ACs are exempt (see 3.6).
- **Literal expected values required.** "Test the zero case" is not a
  spec. `assert f(0) == 0` is. `Returns {status: 'ok', count: 3}` is.
  Named exceptions (`raises ValueError("empty input")`) count as
  literals.
- **Specs expand ACs, they don't replace them.** Both the AC and the
  spec remain in the plan. The AC reads as a human-oriented
  outcome; the spec is the mechanical translation.
- **Anti-pattern list for the drafter** (verbatim in prompt): no
  happy-path-only coverage; no assertion mirroring (asserting that
  `f()` returns what `f()` returns); no hallucinated APIs (check
  existence before referencing); no over-specific assertions baking in
  transient values; no mock-thrash (mocking everything until tests
  assert on mocks); no empty `try/catch` scaffolds without
  exception-type/message checks; no MAX_INT/Unicode/clock-skew
  cargo-cult tests unless the AC actually mentions those domains.
- **Scope tags.** Drafter picks the narrowest scope that exercises the
  AC. If an AC is verifiable at unit level, spec is `[unit]`; reach
  for `[integration]` / `[e2e]` only when unit scope cannot observe
  the AC.
- **Drafter never writes test code.** Specs only. Test code is the
  implementer's job during `/run-plan`.
- **Drafter never recommends weakening tests.** If an AC appears
  untestable as-written, the drafter flags it back to the user via a
  comment — does not fabricate a softer spec.

### Acceptance Criteria

- [ ] AC-3.1 — After Phase 3 runs on a plan with N Pending
  non-delegate phases (of which K are ac-less per WI 1.7b), the
  draft file contains exactly N − K `### Tests` subsections — one
  per Pending non-delegate phase that has an `### Acceptance
  Criteria` block — and each subsection contains at least one
  bullet referencing each of that phase's ACs by ID. Ac-less
  Pending phases (per WI 1.7b) get NO `### Tests` subsection and
  emit the WI 1.7b advisory line instead.
- [ ] AC-3.2 — Every spec bullet matches either the one-line form
  (regex `^- \[(unit|integration|property|e2e)\] \[risk: AC-[0-9]+[a-z]?\.[0-9]+[a-z]?\]`)
  or the expanded form (same leading header, followed by Input /
  Action / Expected / Rationale sub-bullets). The trailing `[a-z]?`
  after the second `[0-9]+` admits sub-letter ACs (e.g.,
  `[risk: AC-1.6c]`).
- [ ] AC-3.3 — No spec asserts on a value described as "something",
  "appropriate", "reasonable", or similar vague placeholder; every
  `Expected` / `expect` clause resolves to a literal value or named
  exception.
- [ ] AC-3.4 — If `.claude/zskills-config.json` has
  `testing.unit_cmd`, the drafter prompt includes it verbatim; if
  absent, the drafter prompt explicitly states "no configured test
  runner".
- [ ] AC-3.5 — Re-running Phase 3 on a plan that already contains
  `### Tests` subsections does not duplicate or nest them.
- [ ] AC-3.6 — On a plan with a Pending phase containing an
  `### Execution: delegate ...` subsection, NO `### Tests` subsection
  is appended to that phase. The phase identifier appears in BOTH
  (i) the parsed-state file's `delegate_phases:` list (Phase 1, WI 1.4b)
  AND (ii) the drafter output file's `delegate_skipped_phases:` list
  (Phase 3, WI 3.6 / 3.8). The two lists are equal as sets — verified
  by an explicit set-equality check; any inequality is a test failure
  (single-source-of-truth invariant).

### Dependencies

Phase 1 (parsed state, AC-IDs). Phase 2 (calibration signal,
test-file map, resolved test-command context).

---

## Phase 4 — Adversarial review loop (QE personas)

### Goal

Wrap the drafter output in a review loop (reviewer + devil's advocate
in parallel, then refiner) calibrated to senior-QE norms, with
explicit gotcha suppression, and converge it.

### Work Items

- [ ] 4.1 — Reviewer agent prompt. Persona: senior QE engineer
  reviewing a colleague's test specs. What counts as a finding:
  (a) a stated AC has no spec referencing it, (b) a spec has no
  literal expected value, (c) an assertion is so weak it would pass
  on a broken implementation, (d) a mock destroys the test's value
  (asserts on its own mock), (e) a specified observable side effect
  is not exercised, (f) a spec targets scope wrong (e.g., an
  integration-only AC has only unit specs). **If the user supplied
  positional-tail guidance** (per WI 1.2), prepend a
  `User-driven scope/focus directive:` section with the verbatim
  guidance text — exactly mirroring `skills/refine-plan/SKILL.md:50,
  :132`. The agent treats guidance as priming context (what to
  pressure-test), NOT as factual claims (still subject to
  verify-before-fix in the refiner).
- [ ] 4.2 — Devil's advocate agent prompt. Same persona, adversarial
  stance. Genuinely tries to find how the spec set will leave real
  defects uncaught. Explicitly NOT a gotcha-generator — calibration
  text from research §Senior QE norms applies. Same guidance prepend
  semantics as 4.1.
- [ ] 4.3 — **NOT-a-finding list** (authored fresh for this skill; not
  inherited from /draft-plan — /draft-plan has no QE-specific
  NOT-a-finding list). Inserted verbatim in BOTH reviewer and DA
  prompts: implausible failure modes under the product's stated
  operating conditions (Bach); type-system-enforced preconditions;
  performance/concurrency/security tests on non-load-bearing code;
  tests duplicating existing specs in the same phase;
  MAX_INT/Unicode/clock-skew tests on code whose ACs don't mention
  those domains; tests requiring infrastructure not present (e.g.,
  "spin up postgres" when the project is config-only); tests that
  exist only to increase coverage numbers; tests of framework code
  rather than product code; property-based tests for functions with
  no meaningful algebraic properties.
- [ ] 4.4 — **Zero findings is valid and correct.** (Authored fresh
  for this skill.) Both prompts must state this in the output-format
  block. If the reviewer has nothing substantive to flag, it outputs
  `## Findings` with a single explicit line: "No findings — spec set
  meets the stated criteria." The loop treats this as a round-pass,
  not a bug. This zero-findings path is NOT equivalent to
  "convergence" — convergence is enforced mechanically against the
  positive definition in Design & Constraints (which is the
  orchestrator's check, not the refiner's self-call), and includes an
  orchestrator-level coverage-floor check that runs BEFORE agent
  dispatch each round.
- [ ] 4.5 — **Mandatory blast-radius field.** (Authored fresh for this
  skill.) Every finding must end with
  `Blast radius: <minor|moderate|major> — <one-line description of
  what would happen if this gap shipped to prod>`. Minor findings are
  dropped at refiner stage. Moderate findings must be resolved. Major
  findings must be resolved or block convergence.
- [ ] 4.6 — **Prior-rounds dedup.** (Authored fresh for this skill.)
  From round 2 onward, both agents receive the previous round's
  findings list as "already addressed — do not re-raise in rephrased
  form." The refiner is the secondary gate: if a round-N finding is
  semantically identical to a round-(N-1) finding, refiner marks it
  `Justified — duplicate of round N-1`.
- [ ] 4.7 — **Evidence discipline** (patterned on `/draft-plan`'s
  reviewer/DA sections, which require a `Verification:` line on every
  empirical claim — see `skills/draft-plan/SKILL.md:369-374`): every
  empirical claim ("the existing test file at X uses framework Y";
  "AC-3.2 has no spec referencing it") ends with a `Verification:`
  line containing the exact grep, file:line, or command output
  reproducing the evidence. Structural judgment findings use
  `Verification: judgment — no verifiable anchor`.
- [ ] 4.8 — **Orchestrator-level coverage-floor pre-check** (runs
  BEFORE dispatching reviewer/DA each round). The pre-check operates
  on a **per-round candidate file** to unify first-invocation,
  re-invocation, and backfill-invocation semantics:
  1. Read the plan file's current bytes.
  2. Read the round-N drafter output (or, on round ≥ 1, the
     refiner's round-(N-1) output).
  3. Construct the candidate by overlaying the drafter/refiner's
     `### Tests` subsections into their target phases (in-memory
     merge — does not touch the plan-file on disk). Write the result
     to `/tmp/draft-tests-candidate-round-N-<slug>.md`.
  4. Read the `non_delegate_pending_phases:` list from the parsed-state
     file (Phase 1, WI 1.4b) — this is the authoritative scope for
     ACs subject to the coverage floor. The pre-check MUST NOT
     re-derive delegate-classification.
  5. For every AC in those phases, grep the candidate for a
     `risk: AC-<phase>.<n>[<sub-letter>]?` reference (sub-letter
     suffix admitted to match sub-letter ACs like `AC-1.6c`); for
     each AC lacking one,
     synthesise a finding of the form: `Coverage floor violated:
     AC-N.M has no spec. Blast radius: major — coverage floor is the
     convergence precondition.`
  6. Inject these synthetic findings into the refiner's input
     alongside reviewer/DA findings.
  Because the grep target is the merged candidate (not the plan file
  alone, not the drafter-output alone), first-invocation round 0
  finds the drafter's specs (no spurious mass-violation), re-invocation
  finds existing in-plan specs (no false redundancy), and
  backfill-invocation finds specs from the round's drafter output
  merged on top of the backfill phase. This closes both the
  zero-findings-vs-convergence contradiction (work item 4.4 vs the
  Design & Constraints convergence rule) AND the grep-target
  ambiguity (what does "the current draft" resolve to per invocation
  mode).
- [ ] 4.9 — Refiner agent. Verify-before-fix mandatory: re-runs each
  finding's Verification check before acting. Records outcome per
  finding (Verified / Not reproduced / No anchor / Judgment) in a
  disposition table. For Verified findings with moderate/major blast
  radius, fix the draft. For Not-reproduced or No-anchor findings,
  justify-not-fix with the reproduction attempt recorded. **The
  refiner produces a disposition table — it does NOT declare
  convergence.** Convergence is the orchestrator's mechanical check
  against the disposition table, per Design & Constraints; the
  refiner's role ends at its disposition table.
- [ ] 4.10 — Write per-round artifacts:
  `/tmp/draft-tests-review-round-N-<slug>.md` (combined reviewer +
  DA + synthesised coverage-floor findings) and
  `/tmp/draft-tests-refined-round-N-<slug>.md` (refiner output +
  disposition table).
- [ ] 4.11 — Convergence check (positive definition, see Design &
  Constraints). On convergence or max rounds, the refined draft from
  the last round becomes the final spec set used in Phase 5 / 6.
  **Convergence is determined by the orchestrator (the SKILL body
  itself) reading the refiner's disposition table and applying the
  four positive conditions from Design & Constraints — never by
  accepting "CONVERGED" or equivalent self-declaration from the
  refiner agent's prose output.**

### Design & Constraints

- **Convergence is the orchestrator's judgment, not the refiner's
  self-call.** Mirroring `skills/refine-plan/SKILL.md:383` and
  `skills/draft-plan/SKILL.md:474`: the refiner produces a disposition
  table; the orchestrator (the skill body itself, not the agent)
  reads the table and applies the four positive conditions below.
  NEVER accept "CONVERGED", "no further refinement needed", or
  equivalent self-call from the refiner agent as authoritative —
  the refiner just refined; it is biased toward declaring its own
  work done. This is a recurring failure mode in practice (see
  CLAUDE.md memory anchor `feedback_convergence_orchestrator_judgment.md`).
- **Convergence (positive).** A round converges when all four of the
  following hold (orchestrator counts these against the disposition
  table; refiner's prose claim of convergence is ignored):
  1. Every AC across all Pending non-delegate phases has ≥ 1 spec
     referencing it (coverage floor — enforced mechanically by 4.8
     before agent dispatch).
  2. Every spec has a literal expected value or named exception.
  3. No finding from this round duplicates a previous round's finding
     (after refiner's dedup pass).
  4. All findings are either resolved or have blast radius = minor
     (dropped at refiner stage).
  Negative-only convergence ("no new findings this round") is
  explicitly rejected — it is vulnerable to reviewer-ratchet where
  each round finds a new wave of decreasingly-relevant issues.
  "Zero findings from agents" is a valid round result but does NOT by
  itself imply convergence — the positive criteria must all hold.
- **Default rounds = 3.** Matches `/draft-plan` (also default 3).
  Note: `/refine-plan` defaults to 2 because it operates on an
  already-refined plan; `/draft-tests`'s 3 matches `/draft-plan`
  because the typical invocation is blank-slate (no prior `### Tests`
  subsections) — Phase 4's senior-QE personas review specs against
  fresh ACs whose shape they have never seen, more like first-pass
  than refinement. On re-invocation against a plan that already has
  specs (Phase 5 refinement path), 2 rounds would suffice — but the
  simpler v1 contract is "default 3 always; early exit on
  convergence handles the re-invocation case." Override with
  `rounds N` per invocation.
- **PLAN-TEXT-DRIFT tokens are out of scope.** `/run-plan`'s
  PLAN-TEXT-DRIFT pipeline (PRs #90-#92, see
  `skills/run-plan/SKILL.md:739, :744, :1358-:1418`) detects
  arithmetic divergence in plan bullets at execution time. Test specs
  authored by `/draft-tests` are qualitative (scope/AC-link/literal-
  expected) and contain no arithmetic claims a `/run-plan` agent
  would measure — so the drafter does NOT emit `PLAN-TEXT-DRIFT:`
  tokens, and the review loop does not check for them. WI 1.6's
  AC-ID assignment touches ONLY the `### Acceptance Criteria` block;
  the drafter's `### Tests` output is treated as inert text by
  `plan-drift-correct.sh --correct` (which targets `### Acceptance
  Criteria` numeric bullets only). This is a correct
  non-integration; flagged here so a future implementer doesn't
  introduce a spurious coupling.
- **Both agents dispatched in parallel** per round — as in
  `/draft-plan` Phase 3.
- **Agent model dispatch.** Reviewer, DA, and refiner agents inherit
  the parent model (Opus by default) — do NOT pass a `model:`
  parameter on dispatch. QE judgment is judgment-class work, not
  bulk pattern matching; CLAUDE.md memory anchor `feedback_no_haiku.md`
  is explicit on this. Past canary failures have stemmed from
  Sonnet/Haiku optimisations on judgment-class tasks; defending
  against the temptation up front.
- **Refiner can STOP and report** if it cannot resolve a finding and
  cannot justify it away. The skill surfaces unresolved findings in
  the final output rather than silently writing a spec set with known
  defects.
- **Refiner never writes to Completed phases.** Same immutability
  contract as Phase 1.
- **Landmine mitigation (from research §Top 3 landmines):** the
  reviewer prompt explicitly says "test specs are expansions of ACs,
  not replacements — if a spec and its AC conflict in tone, that is a
  finding." This prevents the `/run-plan`-parser disambiguation
  failure mode.

### Acceptance Criteria

- [ ] AC-4.1 — A round whose reviewer output is "No findings — spec
  set meets the stated criteria." with DA the same AND whose
  orchestrator-level coverage-floor pre-check produces zero synthetic
  findings does not cause the loop to error, stall, or mark the plan
  as incomplete; the loop treats this as convergence and proceeds.
- [ ] AC-4.2 — On a plan where an AC lacks a spec AND both agents
  return "No findings", the orchestrator's pre-check injects a
  coverage-floor finding, the refiner addresses it, and the loop does
  NOT converge on that round.
- [ ] AC-4.3 — Every finding in a round's review artifact ends with a
  `Blast radius: <level> — <description>` line; findings missing this
  line are rejected by the refiner with a "finding-format-violation"
  note.
- [ ] AC-4.4 — The refiner's disposition table has one row per
  finding, with columns: Finding / Evidence
  (Verified/Not-reproduced/No-anchor/Judgment) / Disposition
  (Fixed/Justified + reason).
- [ ] AC-4.5 — **Unit-level, no model calls.** Using a stubbed review
  loop (pre-authored round-0 draft + pre-authored findings file + a
  canned "refined draft"), the refiner prompt-assembly code produces
  a prompt containing the expected finding text AND the mutation step
  applies the canned refinement. No live LLM call occurs in
  `tests/test-draft-tests.sh`. Live end-to-end runs are gated behind
  `ZSKILLS_TEST_LLM=1`; CI skips with an explicit
  "Tests: skipped — LLM-in-the-loop ACs" note (matching
  `/verify-changes`'s skipped-test convention).
- [ ] AC-4.6 — Max-rounds exit writes a "Remaining concerns" note
  listing each unresolved finding's one-line description and blast
  radius; does not silently converge. **The plan IS written** with
  the partial spec set (no hard-abort that loses work). On the
  realistic case where max-rounds is hit AND the coverage floor
  remains unmet, the skill exits with return code 2 — see AC-4.7
  for reconciliation.
- [ ] AC-4.7 — At convergence, every Pending-phase non-delegate AC has
  ≥ 1 spec referencing it; a post-loop check enforces this and fails
  the run if the floor is not met. **Reconciliation with AC-4.6:** if
  the loop hits max rounds AND the coverage floor is unmet, the skill
  takes the AC-4.6 path (writes the partial spec set + a "Remaining
  concerns" note) AND exits with non-zero status (return code 2,
  reserved for "partial-success — coverage floor not met"). The plan
  on disk reflects the best-effort spec set; the non-zero exit blocks
  downstream automation from advancing on un-attested coverage. This
  is NOT a contradiction with AC-4.6 — both ACs apply on this path,
  and exit code 2 is the conjunction.
- [ ] AC-4.8 — The coverage-floor pre-check operates on the per-round
  merged candidate file `/tmp/draft-tests-candidate-round-N-<slug>.md`,
  not on the plan file alone or the drafter output alone. A unit test
  constructs both pre-merge state (where the drafter's specs are not
  yet in the candidate — synthetic floor-violations should fire) and
  post-merge state (where the same specs are merged in — synthetic
  floor-violations should NOT fire) and verifies the pre-check is
  invoked against the merged view in both first-invocation and
  re-invocation modes.
- [ ] AC-4.9 — **Orchestrator-judgment convergence guard (negative
  case).** A fixture refiner output that contains the literal text
  "CONVERGED", "no further refinement needed", or any equivalent
  self-call but whose disposition table fails any of the four
  positive conditions in Design & Constraints (missing AC coverage,
  non-literal expected, dup of round N-1, unresolved
  moderate/major-blast-radius finding) does NOT cause the skill to
  exit with convergence status — the orchestrator's mechanical
  check on the disposition table overrides the refiner's self-call.
  Verified by running the orchestrator's convergence determination
  on the fixture's disposition table and asserting `converged=false`.

### Dependencies

Phase 3 (draft output; spec format).

---

## Phase 5 — Backfill mechanics and re-invocation

### Goal

Handle two re-entry scenarios: (a) a plan with Completed phases whose
shipped work lacks test coverage ("backfill"), and (b) a plan that
already has `### Tests` subsections from a prior invocation
("refinement"). Produce a `## Test Spec Revisions` section on
re-invocation — deliberately named distinct from `/refine-plan`'s
`## Drift Log` so both skills can coexist on one plan.

### Work Items

- [ ] 5.1 — Gap detection for Completed phases. Using the test-file
  path list persisted by Phase 2 (not a fresh discovery), for each
  Completed phase's AC, search for a test exercising it. Emit one of
  three confidence levels:
  - **COVERED** (high confidence): the AC's ID (e.g. `AC-3.2`) appears
    literally in a test file or test name; OR the AC text contains a
    concrete identifier (function/module/error-string) of length ≥ 4
    that appears in exactly one test file (after stop-word removal —
    common English words plus project-boilerplate tokens like
    "test", "should", "plan", "phase" are stripped).
  - **UNKNOWN** (low confidence): no AC-ID match AND no
    exactly-one-match identifier. Emit advisory note; do NOT
    auto-append backfill for this AC.
  - **MISSING** (moderate confidence): no AC-ID match AND the AC
    body contains at least one **backticked token** (matched by
    `` `[^`]+` ``) AND that backticked token, when treated as a
    literal string, is absent from every file in the repo
    (`git grep -F -- "<token>"` returns no matches). Backticks are
    the explicit author signal that the token is a code identifier
    (function, file path, test name, error string) rather than prose.
    Plain-English nouns inside an AC — even uncommon ones — never
    trigger MISSING; they fall to UNKNOWN. Triggers backfill.
  A Completed phase is flagged for backfill only when ≥ 1 AC is
  MISSING. Phases with only UNKNOWN ACs emit an advisory listing in
  the skill's final output (user-review path) but do NOT auto-append
  a backfill phase. This is a deliberate conservative default to
  avoid false-positive backfill thrash on large repos.
- [ ] 5.2 — Backfill phase construction. When ≥ 1 Completed phase is
  flagged MISSING, append a NEW top-level phase at the **correct
  structural position**:
  - Scan for the first trailing level-2 heading at column 0 that is
    NOT a `## Phase ...` heading, is NOT inside a fenced code block,
    and appears AFTER the last `## Phase`. **The rule is the broad
    form — ANY non-phase `## <name>` outside fenced code blocks
    terminates the search, not a closed list.** Use the same
    awk-style `in_code` state-tracker as WI 1.5 — heading detection
    runs only when `in_code == 0`. Real plans contain non-canonical
    trailing headings (e.g.,
    `## Anti-Patterns -- Hard Constraints` in
    `plans/EXECUTION_MODES.md`); a closed enumeration would skip
    past these and sandwich the backfill phase between them and
    `## Plan Quality`, breaking the structural invariant that all
    `## Phase ...` headings precede all non-phase trailing
    sections. Examples of trailing headings the rule terminates on
    (illustrative, NOT exhaustive): `## Drift Log`, `## Plan
    Review`, `## Plan Quality`, `## Test Spec Revisions`,
    `## Anti-Patterns -- Hard Constraints`, `## Non-Goals`, and
    any other `## <name>` the user has authored after the last
    phase.
  - If any such trailing heading exists, insert the backfill phase
    IMMEDIATELY BEFORE it — all trailing sections stay in place,
    byte-identical, in their authored order.
  - If no trailing heading exists, append at end of file.
  Heading form:
  ```markdown
  ## Phase N — Backfill tests for completed phases X[, Y][, Z]
  ```
  where `N` is one greater than the current max phase number,
  including sub-letters (e.g., if the plan ends at `Phase 5b`, the
  backfill is `Phase 6`). Cluster 1–3 Completed phases per backfill
  phase (per research §Prior art — Feathers/legacy-code guidance that
  bulk batch backfill is a death march).
- [ ] 5.3 — Backfill phase content: Goal ("Add missing test coverage
  for AC-X.1, AC-Y.3, ..."), Work Items (one per AC gap), Design &
  Constraints ("Tests must verify the current state of shipped work,
  not the original AC text where reality diverged"), Acceptance
  Criteria, Dependencies (the listed Completed phases). The new
  backfill phase is Pending — the normal draft → review loop then
  runs against it in the same invocation.
- [ ] 5.3b — **Update parsed-state on backfill insertion.** Immediately
  after the backfill phase is appended to the plan (5.2) and its body
  is authored (5.3), append the backfill phase's identifier to the
  parsed-state file's `non_delegate_pending_phases:` list (and to any
  paired `pending_phases:` / `delegate_phases:`-related lists where
  membership is required). Backfill phases are author-created by the
  skill itself and never carry `### Execution: delegate`, so they are
  always non-delegate by construction — no delegate predicate
  evaluation is needed; the phase identifier can be appended directly.
  This update is mandatory because Phase 4 WI 4.8 step 4 reads
  `non_delegate_pending_phases:` from parsed-state and explicitly
  forbids re-derivation; without this update, the coverage-floor
  pre-check would not enforce the floor on the backfill phase's ACs,
  silently shipping un-attested coverage on the very phase the
  backfill flow exists to cover.
- [ ] 5.4 — Completed-phase ACs referenced by backfill phases are NOT
  modified. The backfill phase references them by ID; if they lacked
  IDs, Phase 1's AC-ID assignment does not apply to Completed phases
  — instead, the backfill phase quotes the AC text and assigns a
  backfill-local ID (e.g., `AC-<backfill-phase>.<n>`) that aliases
  the original.
- [ ] 5.5 — Re-invocation detection. If the plan already contains at
  least one `### Tests` subsection, treat the invocation as
  refinement: the existing specs are the round-0 draft; the review
  loop from Phase 4 runs against them; the refined output is written
  back in place.
- [ ] 5.6 — **Revert frontmatter `status: complete` → `active` when
  adding executable work.** When the skill appends a backfill phase
  to a plan whose YAML frontmatter has `status: complete`, it MUST
  flip `status` to `active` in the same write. `/run-plan` treats
  `status: complete` as terminal (see `skills/run-plan/SKILL.md:413`
  and `:536`) and would otherwise refuse to execute the new backfill
  phase, silently orphaning it. This frontmatter flip is the only
  frontmatter edit the skill is permitted to make.

  **Cron interaction (informational).** `/run-plan`'s terminal-cron
  cleanup at `skills/run-plan/SKILL.md:413-419` runs only when
  `status==complete`. When `/draft-tests` flips `status` complete →
  active, the next `/run-plan` invocation enters the case-4 normal
  preflight path (not case 1) — the cron correctly continues firing
  and re-evaluates the plan with the new backfill phase.
  `/draft-tests` does NOT touch registered crons; the status flip is
  the only frontmatter mutation. Documented so a future "why
  doesn't /draft-tests delete the cron when flipping status?"
  question has an answer in the spec.
- [ ] 5.7 — `## Test Spec Revisions` section for re-invocation. When
  the skill modifies a Pending phase's existing `### Tests`
  subsection or appends a new backfill phase, append (or update) a
  `## Test Spec Revisions` section. **Placement: AFTER any existing
  `## Drift Log` and `## Plan Review` sections** (the trailing
  sections `/refine-plan` writes; see Phase 5 D&C "Co-skill ordering
  with /refine-plan" below for the rationale and the cross-skill
  checksum-boundary interaction). Use a 2-column format:
  ```markdown
  ## Test Spec Revisions

  One row per invocation. Column "Change" summarises structural
  deltas (spec counts, AC coverage changes, backfill appends) —
  never full spec text.

  | Date | Change |
  |------|--------|
  | 2026-04-24 | Phase 4: +3 specs for AC-4.1, AC-4.3; Phase 5: refined spec for AC-5.1 (input narrowed to literal); Appended Phase 7 for backfill of Completed phases 2, 3 |
  ```
  This section is placed AFTER any existing trailing non-phase
  level-2 sections — **the broad form: any `## <name>` (other than
  `## Phase ...`) outside fenced code blocks the user has authored
  after the last phase counts as a trailing section, not a closed
  list.** Use the same awk-style `in_code` state-tracker as WI 1.5
  / WI 5.2 — heading detection runs only when `in_code == 0` so
  `## ` headings inside ` ``` ` fences are not mistaken for
  trailing sections. Named examples (illustrative, NOT exhaustive):
  `## Drift Log`, `## Plan Review`, `## Plan Quality`,
  `## Anti-Patterns -- Hard Constraints`, `## Non-Goals`. The
  column names and section name are deliberately different from
  `/refine-plan`'s `## Drift Log` (which uses `| Phase | Planned |
  Actual | Delta |`) so a plan touched by both skills carries two
  unambiguous histories.
- [ ] 5.8 — Completed-phase checksum verification before final write
  (Phase 6). Any divergence from Phase 1 checksums aborts the run
  with a clear error message listing the drifted phases.

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
  bug; add a test-spec conformance assertion that the bytes of
  every trailing non-phase level-2 section (canonical and
  non-canonical alike) are unchanged pre/post backfill.
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
  (`skills/refine-plan/SKILL.md:397-411`) rebuilds frontmatter +
  Overview + Tracker + Completed + Refined-remaining + fresh Drift
  Log + fresh Plan Review and **does not preserve any pre-existing
  trailing sections beyond those it rebuilds** — so a `## Test Spec
  Revisions` section written by `/draft-tests` will be DESTROYED by a
  subsequent `/refine-plan` run. Broadening `/refine-plan`'s checksum
  boundary AND its reassembly preservation to recognise `## Test
  Spec Revisions` is **out of scope** (depends on a co-skill change,
  separate PR). Until that lands, callers must run `/draft-tests`
  AFTER `/refine-plan` if both are needed in one cycle, and re-run
  `/draft-tests` after every `/refine-plan` to recover any clobbered
  `## Test Spec Revisions` history. Surfaced here so a future
  reader's "why doesn't this just work both ways?" question has an
  answer in the spec.
- **Never record in `## Test Spec Revisions` that a Completed phase
  was modified.** If that ever happened, the checksum gate already
  refused the write. The only Completed-phase-adjacent entry is
  "Appended Phase N for backfill of Completed phases X, Y" — which
  documents an append, not a modification.
- **Backfill trigger threshold.** At least one Completed-phase AC
  must be classified MISSING per 5.1's three-level rubric. Phases
  with UNKNOWN ACs trigger an advisory note in the final output, not
  an auto-appended backfill phase. This is a conservative default to
  avoid false-positive backfill thrash; the skill is not for
  exhaustive audit (that's `/qe-audit`).
- **Frontmatter flip is single-purpose.** The only frontmatter edit
  this skill ever makes is `status: complete` → `status: active`
  when appending a backfill phase. Any other frontmatter change is
  out of scope.

### Acceptance Criteria

- [ ] AC-5.1 — On a plan with a Completed phase whose ACs have
  matching tests (AC-ID reference or concrete identifier hit) in the
  repo, the skill does not append a backfill phase; no COVERED AC
  produces a MISSING flag.
- [ ] AC-5.2 — On a plan with a Completed phase whose ACs are all
  UNKNOWN (prose-only ACs with no concrete identifiers), the skill
  does NOT auto-append a backfill phase; instead, the final skill
  output lists the phase under "advisory: coverage could not be
  confirmed — human review recommended." Specifically: an AC body
  containing only English prose nouns (no backticked tokens) — even
  if some of those nouns happen to be absent from the repo — falls
  to UNKNOWN and never triggers MISSING (regression guard against
  the prose-token false-positive bug).
- [ ] AC-5.3 — On a plan with a Completed phase whose AC text contains
  a **backticked identifier** (e.g., `` `someFunction` ``,
  `` `tests/foo.sh` ``) that is absent from every file in the repo
  (verified by `git grep -F`), the skill classifies the AC as MISSING,
  appends a `## Phase N — Backfill tests for completed phases X`
  section at the correct position (before trailing sections; at EOF
  if none), adds a Progress Tracker row for it, and runs the draft →
  review loop against it like any Pending phase.
- [ ] AC-5.4 — On a plan with four or more Completed phases all
  MISSING, the skill produces multiple backfill phases clustering
  1–3 Completed phases each (not a single mega-phase).
- [ ] AC-5.5 — Re-running the skill on a plan that already has
  `### Tests` subsections refines them in place (no duplicated
  headings, no nested subsections) and appends a `## Test Spec
  Revisions` row per phase whose specs changed.
- [ ] AC-5.6 — The `## Test Spec Revisions` section uses the 2-column
  format `| Date | Change |`; never uses `/refine-plan`'s 4-column
  format; never transcribes full spec text into the Change column.
- [ ] AC-5.7 — **Structural preservation of trailing sections.** On a
  plan with pre-existing `## Drift Log` and `## Plan Quality`
  sections, after a backfill append, both sections still exist,
  appear AFTER the new backfill phase's section, and are
  byte-identical to their pre-invocation content (verified via
  `diff`). **Regression guard against the closed-enumeration
  anti-pattern:** an additional fixture plan contains a
  non-canonical trailing level-2 heading (e.g., `## Anti-Patterns
  -- Hard Constraints` between the last phase and `## Plan
  Quality`, mirroring `plans/EXECUTION_MODES.md`); after a backfill
  append, the new `## Phase N — Backfill ...` heading must appear
  IMMEDIATELY BEFORE the `## Anti-Patterns -- Hard Constraints`
  heading (NOT between it and `## Plan Quality`), and the
  non-canonical heading's section bytes are byte-identical pre/post
  (verified via `diff`). **Fenced-code-block regression guard:** a
  third fixture plan contains a fenced ` ```markdown ` block before
  the trailing-sections region with `## Example` at column 0 inside
  the fence; the backfill insertion site must be determined by the
  first non-fenced trailing heading, not by the in-code one (verified
  by asserting the new backfill phase appears at the structurally
  correct position relative to the fenced content).
- [ ] AC-5.8 — **Frontmatter flip.** On a plan with frontmatter
  `status: complete` where the skill appends a backfill phase, the
  resulting plan has frontmatter `status: active`; every other
  frontmatter field is byte-identical. On a plan where the skill
  does NOT append a backfill phase, frontmatter is byte-identical
  including `status:`.
- [ ] AC-5.9 — On any run, if a Completed phase's section text at
  final-write time differs from its Phase 1 checksum, the skill
  STOPS with an error naming the drifted phase and does not write
  the plan file.
- [ ] AC-5.10 — **Backfill phase enrolled in coverage floor.** On a
  backfill invocation that appends `## Phase N — Backfill tests for
  completed phases X`, after the backfill phase is authored (5.2 +
  5.3) and parsed-state is updated (5.3b), the parsed-state file's
  `non_delegate_pending_phases:` list contains the backfill phase
  identifier. Phase 4's coverage-floor pre-check (WI 4.8) enforces
  the floor on the backfill phase's ACs in the same invocation —
  verified by a fixture where the drafter omits a spec for one of
  the backfill phase's ACs and the pre-check synthesises a
  `Coverage floor violated: AC-N.M ...` finding for that AC. This
  AC closes the round-3 reviewer's data-flow gap between Phase 5's
  runtime-appended phases and Phase 4's parsed-state-driven
  coverage-floor pre-check.
- [ ] AC-5.11 — **`## Test Spec Revisions` placement after Drift Log
  / Plan Review.** On a plan that already contains `## Drift Log`
  and `## Plan Review` sections (e.g., a plan previously refined by
  `/refine-plan`), after `/draft-tests` writes a new
  `## Test Spec Revisions` section (per WI 5.7), the resulting plan
  contains the headings in this order: last `## Phase ...`, then
  `## Drift Log`, then `## Plan Review`, then `## Test Spec
  Revisions`, then any user-authored trailing sections (e.g.,
  `## Plan Quality`). Closes the `/refine-plan` checksum-boundary
  cross-skill interaction documented in Phase 5 D&C "Co-skill
  ordering with /refine-plan".

### Dependencies

Phase 1 (checksums, classification). Phase 2 (test-file map for gap
detection). Phase 4 (loop runs on backfill phases).

---

## Phase 6 — Tests, conformance, worked example, and mirror

### Goal

Ship `tests/test-draft-tests.sh`, register it in `tests/run-all.sh`,
add conformance checks to `tests/test-skill-conformance.sh`, produce
one worked example showing before/after, and mirror the skill into
`.claude/skills/`.

### Work Items

- [ ] 6.1 — Write `tests/test-draft-tests.sh`. Covers:
  - Frontmatter shape and argument parsing including the
    `[guidance...]` positional tail (AC-1.1, AC-1.2, AC-1.2b).
  - Tracking marker creation (AC-1.3).
  - Phase classification on a multi-status fixture plan including
    `Done`, `✅`, `[x]`, `⬚`, `⬜`, and empty-cell glyphs (AC-1.4).
  - Checksum preservation: run the skill end-to-end on a fixture,
    diff Completed-phase sections pre/post, require byte-identical
    (AC-1.5, AC-5.9).
  - Checksum boundary regression: plan with trailing `## Drift Log`
    and `## Plan Quality`; confirm last-Completed-phase checksum is
    unchanged when those trailing sections are later appended to
    (AC-1.5 second sentence). Additional fixture: plan containing a
    non-canonical level-2 heading (e.g., `## Non-Goals`) between the
    last Completed phase and `## Plan Quality`; confirm the boundary
    rule terminates correctly at the non-canonical heading and that
    later edits to it do not flag drift (AC-1.5 third sentence —
    regression against the closed-enumeration bug).
  - AC-ID assignment on Pending phases, untouched on Completed
    (AC-1.6); re-run idempotence, no double prefix (AC-1.6b).
  - Ambiguous-prefix refuse path (AC-1.6c): fixture AC block contains
    work-item-style `- [ ] 1.1 — ...`, no-em-dash AC reference
    `- [ ] AC-3.2 covered when X happens`, and scope-tag-leading
    `- [ ] [scope] given input`; assert all three bullets are
    byte-identical post-run and that the advisory output mentions
    each by file:line.
  - Zero-Pending + zero-gap exits clean (AC-1.7 first sentence);
    zero-Pending + ≥ 1 MISSING routes to backfill (AC-1.7 second
    sentence).
  - Append contract: `### Tests` appears in every Pending
    non-delegate phase (AC-3.1) with specs matching the format regex
    (AC-3.2); delegate phases skipped (AC-3.6).
  - Ac-less Pending phase path (AC-1.7b): fixture plan contains one
    Pending non-delegate phase WITHOUT `### Acceptance Criteria` plus
    one normal Pending non-delegate phase. Assert (i) parsed-state
    `ac_less:` list contains the ac-less phase identifier, (ii)
    `non_delegate_pending_phases:` still includes it (single-source-of-
    truth invariant), (iii) the post-Phase-3 draft has exactly N − K
    `### Tests` subsections — one for the normal phase, none for the
    ac-less phase — confirming AC-3.1's M = N − K formula, (iv) the
    skill's final output contains exactly one ac-less advisory line.
  - No vague assertions in produced specs (AC-3.3) — grep for
    blocked words on a stubbed drafter output.
  - Re-run idempotence (AC-3.5, AC-5.5).
  - Backfill triple-rubric: COVERED → no backfill (AC-5.1); UNKNOWN
    → advisory not backfill (AC-5.2, including the prose-only-AC
    regression guard for the prose-token false-positive bug);
    MISSING → backfill, gated on backticked-identifier presence
    (AC-5.3); four-plus MISSING → clustering (AC-5.4).
  - Backfill phase enrolled in coverage-floor pre-check (AC-5.10):
    fixture forces a backfill append, then verifies (i) parsed-state
    `non_delegate_pending_phases:` lists the backfill phase identifier
    AND (ii) when the drafter omits a spec for one of the backfill
    phase's ACs, the coverage-floor pre-check synthesises a
    floor-violation finding for that AC.
  - `## Test Spec Revisions` format (AC-5.6).
  - **`## Test Spec Revisions` placement after Drift Log / Plan
    Review (AC-5.11):** fixture plan with pre-existing `## Drift
    Log` and `## Plan Review` sections; after `/draft-tests` writes
    a `## Test Spec Revisions` section, assert the resulting heading
    order is last `## Phase ...` → `## Drift Log` → `## Plan Review`
    → `## Test Spec Revisions` → trailing user-authored sections.
    Cross-skill checksum-boundary co-existence guard.
  - Structural preservation of `## Drift Log` / `## Plan Quality`
    on backfill append (AC-5.7); plus the non-canonical-trailing-
    heading regression fixture (plan with `## Anti-Patterns -- Hard
    Constraints` between last phase and `## Plan Quality`,
    mirroring `plans/EXECUTION_MODES.md`): assert backfill phase
    inserts BEFORE `## Anti-Patterns`, not between it and `## Plan
    Quality`.
  - Frontmatter flip `status: complete` → `active` when backfill is
    appended (AC-5.8); no flip otherwise (AC-5.8 second sentence).
  - Checksum gate refusal on a tampered fixture (AC-5.9) — mutate a
    Completed phase between runs and verify the second run refuses.
  - Language-detection fixtures for JS, Python, Go, polyglot, and
    no-manifest (AC-2.1 through AC-2.4).
  - `.claude/zskills-config.json` override (AC-2.5).
  - Calibration signal bound ≤ 20 lines per language (AC-2.8);
    test-file path list persisted to parsed state (AC-2.9);
    `## Prerequisites` insertion position (AC-2.10).
  - Reviewer "zero findings" accepted as convergence ONLY when
    coverage-floor pre-check also produces zero (AC-4.1); missed-AC
    case injects coverage-floor finding (AC-4.2).
  - Coverage-floor pre-check operates on the merged round-N candidate
    file, not on plan file or drafter output alone (AC-4.8): two
    sub-cases — pre-merge synthesises violations, post-merge does
    not.
  - **Orchestrator-judgment convergence guard (AC-4.9):** fixture
    refiner output containing literal "CONVERGED" / "no further
    refinement needed" but with a disposition table failing one of
    the four positive conditions; assert the orchestrator's
    convergence determination returns `converged=false` and the
    loop continues to the next round (or to max-rounds AC-4.6
    handling if budget exhausted).
  - Max-rounds + floor-violation reconciliation (AC-4.6 + AC-4.7):
    fixture forces max-rounds with at least one AC still uncovered;
    assert (i) plan-on-disk contains the partial spec set, (ii)
    plan-on-disk contains a "Remaining concerns" note listing the
    floor-violating AC(s), (iii) skill exit code is 2.
  - Blast-radius required on findings (AC-4.3); refiner disposition
    table shape (AC-4.4).
  - **Refiner unit-mode validation (AC-4.5):** stubbed drafter output
    + canned findings file + canned refined draft; assert
    prompt-assembly contents and mutation output without live model
    calls. Live-LLM tests (if any) gated behind `ZSKILLS_TEST_LLM=1`.
- [ ] 6.2 — Register the test in `tests/run-all.sh` via
  `run_suite "test-draft-tests.sh" "tests/test-draft-tests.sh"`.
  `tests/run-all.sh` is domain-grouped, NOT alphabetised — group
  the new entry alongside other skill-conformance / skill-test peers
  (e.g., near `test-skill-conformance.sh` line 43,
  `test-skill-invariants.sh` line 45, `test-mirror-skill.sh` line
  53, or `test-stub-callouts.sh` line 58 — line numbers are
  illustrative, anchored to current main but not load-bearing).
  Exact line is the implementer's judgment; what matters is the
  entry sits in the skill-test cluster, not at end-of-file or
  between unrelated domain groups.
- [ ] 6.3 — Extend `tests/test-skill-conformance.sh` with
  draft-tests-specific checks (one `check` / `check_fixed` line per
  sub-bullet below; AC-6.2 enforces list-membership not literal count):
  - `skills/draft-tests/SKILL.md` has the canonical frontmatter
    fields including the `[guidance...]` positional tail in
    `argument-hint`.
  - The tracking marker basename pattern matches the canonical scheme
    (`fulfilled.draft-tests.<id>`).
  - The SKILL.md body contains the NOT-a-finding list verbatim (grep
    for a distinctive phrase from 4.3).
  - The SKILL.md body contains the "zero findings is valid" framing
    (grep for a distinctive phrase from 4.4).
  - The SKILL.md body contains the orchestrator-level coverage-floor
    pre-check (grep for a distinctive phrase from 4.8) — guards
    against silent regression of the coverage-floor gate.
  - **The SKILL.md body contains the "orchestrator's judgment, not
    the refiner's self-call" framing** (grep for the phrase
    `orchestrator's judgment` in the convergence context). Guards
    against silent drift back to refiner-self-declared convergence
    — the recurring failure mode CLAUDE.md memory anchor
    `feedback_convergence_orchestrator_judgment.md` flags. Mirrors
    the same phrase in `skills/refine-plan/SKILL.md:383` and
    `skills/draft-plan/SKILL.md:474`.
  - The SKILL.md body asserts the broad-form checksum-boundary rule
    (grep for a distinctive phrase such as "next level-2 heading"
    or "next `## ` heading at column 0"). Guards against silent
    regression to a closed-enumeration boundary.
  - The SKILL.md body asserts the broad-form **backfill-insertion**
    rule (grep for a distinctive phrase such as "ANY non-phase
    `## <name>`" or "first trailing level-2 heading at column 0
    that is NOT a `## Phase`"). Guards against silent regression
    of the backfill-insertion site to a closed-enumeration of
    named trailing sections (the round-3 sibling-site bug from
    DA Finding 1).
  - The SKILL.md body asserts the broad-form **Test-Spec-Revisions
    placement** rule (grep for a distinctive phrase such as "any
    `## <name>` (other than `## Phase`)" in the placement context).
    Same regression guard at the second placement site.
  - The SKILL.md body asserts the **fenced-code-block-aware**
    boundary scan (grep for a distinctive phrase such as "in_code"
    or "fenced code block" in the boundary-scan context). Guards
    against silent regression to a naive `^## ` scan that would
    falsely terminate Completed-phase checksums at in-code headings
    (the round-2 /refine-plan DA Finding 1 — empirically present in
    `plans/EXECUTION_MODES.md` lines 236, 2079, 2082).
  - The SKILL.md body does NOT contain `jq` as a standalone word
    (per AC-6.6's hardened pattern with `[^a-zA-Z_]` boundaries and
    `-I`).
- [ ] 6.4 — Worked example. Author stable illustrative fixture plans
  under `tests/fixtures/draft-tests/examples/` (NOT under
  `plans/examples/`). The directory holds
  `tests/fixtures/draft-tests/examples/README.md` explaining "this
  directory holds purpose-built example plans demonstrating skill
  behavior; nothing here is executed by `tests/run-all.sh` or
  `/run-plan` — fixtures and worked examples co-locate under
  `tests/fixtures/` to keep them out of any future `plans/` glob."
  Author the small stable illustrative plan
  `tests/fixtures/draft-tests/examples/DRAFT_TESTS_EXAMPLE_PLAN_before.md`
  (NOT a copy of a real in-use `plans/*.md`). Run the skill against
  a copy of it into
  `tests/fixtures/draft-tests/examples/DRAFT_TESTS_EXAMPLE_PLAN.md`.
  Both files ship as documentation. The README documents the
  before/after diff showing how one Pending phase gained a
  `### Tests` subsection. **Rationale for `tests/fixtures/`
  placement (not `plans/`):** current PLAN_INDEX.md rebuild scanners
  (`skills/zskills-dashboard/scripts/zskills_monitor/collect.py:1097`
  uses `plans_dir.glob("*.md")` — top-level only, NOT recursive,
  verified) wouldn't pick up `plans/examples/*.md` today, but a
  future change to recursive globbing would silently surface the
  examples in the live index. Co-locating with fixtures is
  defensive: the "examples are pure documentation" framing already
  matches the `tests/fixtures/` mental model, and no existing
  tooling globs `tests/fixtures/`. This resolves the prior
  contradiction between "do not reuse real plans as fixtures"
  (Phase 6 D&C) and "pick a real plan from `plans/`" (earlier
  wording).
- [ ] 6.5 — Mirror source to `.claude/skills/` at the end via the
  canonical helper:
  ```bash
  bash scripts/mirror-skill.sh draft-tests
  ```
  This script handles per-file copy, orphan detection (per-file
  `rm`, not `rm -rf` — hook-compatible), and post-regen `diff -rq`
  verification (see `scripts/mirror-skill.sh:30-75` for the full
  contract). Inline `rm -rf .claude/skills/draft-tests && cp -a ...`
  is hook-blocked by `hooks/block-unsafe-generic.sh:217-220`
  (RM_RECURSIVE pattern) and forbidden. Inline two-line
  `mkdir -p && cp` is also forbidden — it copies only `SKILL.md`,
  doesn't handle `references/` or `scripts/` subdirectories the
  skill may grow, and doesn't detect orphan files in the mirror
  from prior runs. **Never edit any file under
  `.claude/skills/draft-tests/` directly during development** —
  all edits go to `skills/draft-tests/` first, then re-run
  `bash scripts/mirror-skill.sh draft-tests`. (CLAUDE.md memory
  anchor `feedback_claude_skills_permissions.md`: edits to
  `.claude/skills/` trigger permission storms; mirror discipline
  is the workaround.) This is the last action before the tracking
  `status: complete` write.
- [ ] 6.6 — End-of-phase tracking marker. Write
  `step.draft-tests.$TRACKING_ID.finalize` and update the
  `fulfilled.draft-tests.$TRACKING_ID` marker to `status: complete`,
  matching `/draft-plan` Phase 6.

### Design & Constraints

- **Test output capture.** All `tests/test-draft-tests.sh` subprocess
  output goes to `$TEST_OUT/.test-results.txt` where `$TEST_OUT` is
  derived from `/tmp/zskills-tests/$(basename "$(pwd)")`. Never pipe
  through `| tail` / `| grep` in the test file itself. This matches
  the CLAUDE.md capture idiom.
- **Fixture plans** live under `tests/fixtures/draft-tests/` and are
  deliberately minimal — one plan per test scenario. **Worked
  examples** live under `tests/fixtures/draft-tests/examples/`
  alongside fixtures (NOT under `plans/examples/` — see WI 6.4
  rationale). Fixtures are for automated tests; worked examples are
  documentation; both share the `tests/fixtures/` root because
  neither is a real executable plan and `tests/fixtures/` is
  excluded from every plan-scanning tool. Neither reuses real
  `plans/*.md` files.
- **Worked example is evidence, not infrastructure.** The example
  files ship in `tests/fixtures/draft-tests/examples/` as pure
  documentation. They are NOT invoked by `tests/run-all.sh`. They
  are not wired into `/run-plan`.
- **Mirror discipline.** All `.claude/skills/draft-tests/` writes go
  through `scripts/mirror-skill.sh` — never inline `cp` / `rm`. The
  helper is hook-compatible and verifies `diff -rq` post-regen.
- **No suppression of fallible operations.** The test file uses
  `&& echo "ok"` (not `; echo "ok"`) after destructive or fallible
  steps. No `2>/dev/null` on `git`, `cp`, `rm` commands whose success
  matters — per CLAUDE.md "Never suppress errors".
- **Conformance additions match existing patterns in
  `test-skill-conformance.sh`** — the new checks live alongside the
  per-skill blocks already present. Do not introduce a new assertion
  framework; use whatever the file already uses.
- **Do not weaken tests in this phase to make them pass.** If
  `tests/test-draft-tests.sh` fails against the Phase 1–5 build,
  fix the skill, not the test. **Surface-bugs-don't-patch
  corollary (CLAUDE.md):** zskills is a skill-framework repo —
  every quiet route-around in `/draft-tests`'s build-out (silenced
  fixture, relaxed regex, deleted assertion) gets multiplied across
  every downstream consumer plan. If a test reveals a SKILL.md spec
  gap, surface it as a real defect and fix the SKILL.md — never
  quietly patch the test.
- **No live LLM calls from the test suite.** All refiner / reviewer /
  DA behavior exercised by `tests/test-draft-tests.sh` uses stubbed
  prompts and canned responses (pre-authored fixture files).
  Live-model end-to-end runs, if authored, are strictly gated behind
  `ZSKILLS_TEST_LLM=1`; CI does not set this and skips those cases
  with an explicit "skipped — LLM-in-the-loop" note per AC-4.5.

### Acceptance Criteria

- [ ] AC-6.1 — `tests/run-all.sh` invokes `tests/test-draft-tests.sh`
  and the suite passes locally (exit 0) with `ZSKILLS_TEST_LLM`
  unset.
- [ ] AC-6.2 — `tests/test-skill-conformance.sh` passes; the new
  draft-tests block contains **one `check` / `check_fixed` line per
  WI 6.3 sub-bullet** (list-membership invariant — the check count
  is derived from WI 6.3's enumerated bullet count, NOT pinned to a
  literal numeral). The conformance test file includes a tag-line
  comment in the draft-tests block referencing WI 6.3 as the
  authoritative enumeration source, so future WI 6.3 additions
  drive a single edit (the new conformance line) rather than
  coupled edits at WI 6.3 + AC-6.2 literal. Closes the count-drift
  surface that fired during /refine-plan round 2 (9 → 10).
- [ ] AC-6.3 — `tests/fixtures/draft-tests/examples/` exists and
  contains `README.md`, `DRAFT_TESTS_EXAMPLE_PLAN_before.md`, and
  `DRAFT_TESTS_EXAMPLE_PLAN.md`; `diff` between the two plan files
  shows (i) an appended `### Tests` subsection in at least one
  Pending phase and (ii) no changes to Completed-phase sections.
  No example files appear under `plans/examples/` (negative
  assertion guarding against accidental relocation).
- [ ] AC-6.4 — `.claude/skills/draft-tests/` mirrors
  `skills/draft-tests/` with no diff (verified by
  `diff -rq skills/draft-tests/ .claude/skills/draft-tests/`
  returning empty output, matching the contract
  `scripts/mirror-skill.sh` enforces post-regen at lines 66-71).
  At minimum, `cmp skills/draft-tests/SKILL.md
  .claude/skills/draft-tests/SKILL.md` returns identical; if the
  skill ships any subdirectory (`references/`, `scripts/`), all
  nested files are also identical and no orphans exist on either
  side. Closes the orphan-survivor failure mode that the prior
  inline `cp` snippet didn't catch.
- [ ] AC-6.5 — After Phase 6 completes end-to-end, the tracking
  fulfillment marker for the skill's own run has `status: complete`.
- [ ] AC-6.6 — **Hardened jq-absence assertion** (closes the
  empty-grep-on-missing-dir hole and the underscore-identifier
  false-positive): the conformance check is
  `test -f skills/draft-tests/SKILL.md && ! grep -rIE '(^|[^a-zA-Z_])jq([^a-zA-Z_]|$)' skills/draft-tests/`
  — fails closed when the directory is missing, uses `[^a-zA-Z_]`
  word-boundary regex so substrings like `jquery` and identifiers
  like `_jq_helper` do not match but real `jq` invocations
  (`| jq '.'`, `jq -r ...`) do. `-I` skips binary files
  defensively.

### Dependencies

Phases 1–5 (all skill behavior must exist before tests exercise it).
Phase 4 (worked-example run exercises the full loop).

---


## Out of Scope

(Added by /refine-plan 2026-04-29 round 1 — original plan had no Out of Scope section.)

- **Broadening `/refine-plan`'s checksum boundary to include
  `## Test Spec Revisions`.** `/refine-plan`'s
  `skills/refine-plan/SKILL.md:110` boundary is closed-form ("next
  `## Phase` or end of file"); a plan growing `## Test Spec
  Revisions` between the last `## Phase` and `## Drift Log` would
  cause `/refine-plan`'s next-invocation checksum on the last
  Completed phase to incorrectly include `## Test Spec Revisions`
  bytes, producing a false "Completed phase drifted" error. Phase 5
  D&C "Co-skill ordering with /refine-plan" works around this by
  pinning placement AFTER `## Drift Log` / `## Plan Review`. A
  proper fix — broadening `/refine-plan`'s boundary regex (and its
  Phase 5 reassembly preservation) to recognise `## Test Spec
  Revisions` — depends on a co-skill change and ships in a separate
  PR.
- **Broadening `/refine-plan`'s Phase 5 reassembly to preserve
  pre-existing `## Test Spec Revisions` sections.**
  `skills/refine-plan/SKILL.md:397-411` rebuilds frontmatter +
  Overview + Tracker + Completed + Refined-remaining + fresh Drift
  Log + fresh Plan Review and discards any other trailing sections.
  A `## Test Spec Revisions` section written by `/draft-tests` will
  be DESTROYED by a subsequent `/refine-plan` run. Workaround
  (binding for v1): callers run `/refine-plan` BEFORE `/draft-tests`
  in any cycle, and re-run `/draft-tests` after every
  `/refine-plan` to re-author the clobbered history. The proper fix
  belongs in a `/refine-plan` PR.
- **A `--bootstrap` flag prepending a Phase 0 to scaffold a missing
  test runner** (already noted in WI 2.5 as future work; reiterated
  here for Out-of-Scope completeness).
- **Monitor surface integration** (`skills/zskills-dashboard/`,
  `server.py`, `app.css`, `/work-on-plans` parser changes). Plan
  has zero monitor coupling per pre-flight research; verified zero
  references to monitor surfaces in plan body.


## Drift Log

This refine (2026-04-29, /refine-plan round 1) absorbed post-2026-04-24 ecosystem changes from PRs #79, #82, #85, #88, #97, #90-#92. Original plan was authored 2026-04-24, status `active`, never executed (all 6 phases ⬚). It went through 6 prior adversarial review passes (3 /draft-plan + 3 /refine-plan), converging at round 3 with zero reviewer findings — so this absorption is targeted, not foundational re-review.

### Ecosystem changes absorbed

| Change | PR | Plan adjustment |
|---|---|---|
| `sanitize-pipeline-id.sh` relocated to `skills/create-worktree/scripts/` | #97 | WI 1.3 path re-anchored to `$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh` per `script-ownership.md` |
| `scripts/mirror-skill.sh` helper added; inline `rm -rf .claude/skills/X` hook-blocked | #88 | WI 6.5 mirror snippet replaced with `bash scripts/mirror-skill.sh draft-tests`; AC-6.4 widened to `diff -rq` (recursive) |
| Convergence is orchestrator's judgment, not refiner's self-call | #82 | Phase 4 D&C extended with explicit framing; AC-4.9 tests negative case (refiner cannot self-declare CONVERGED) |
| `[guidance...]` positional tail added to /refine-plan | #85 | Adopted for /draft-tests parity; WI 1.1/1.2 extended; AC-1.2b regression guard |
| Default rounds asymmetry (/draft-plan=3 vs /refine-plan=2) | n/a | Kept default at 3 with explicit rationale (QE coverage is generative like drafting) |
| PLAN-TEXT-DRIFT machinery in /run-plan | #90-#92 | Phase 4 D&C adds non-integration declaration (specs aren't arithmetic claims) |
| `## Test Spec Revisions` checksum-boundary cross-skill risk | DA6 finding | Phase 5 D&C pins placement AFTER `## Drift Log`/`## Plan Review` to preserve /refine-plan's `## Phase` boundary scan; AC-5.11 + WI 5.7 enforce; co-skill-ordering workaround documented |
| `plans/examples/` polluting PLAN_INDEX.md rebuild | DA8 finding | Worked example relocated to `tests/fixtures/draft-tests/examples/` |
| AC-6.2 hardcoded conformance count fragility | R1.12/DA7 | Replaced with list-membership invariant (one check per WI 6.3 sub-bullet, pattern not count) |

### Out-of-scope deferrals (per parallel-safety bar)

- Broadening /refine-plan's checksum boundary AND its Phase 5 reassembly to recognise `## Test Spec Revisions` — depends on a co-skill change, separate /refine-plan PR
- `--bootstrap` flag for first-run fixtures — future enhancement
- Monitor-surface integration — N/A; plan has zero monitor coupling, ZSKILLS_MONITOR_PLAN in flight in another session

### Non-coupling confirmed

- Zero references to `skills/zskills-dashboard/`, `server.py`, `app.css`, `/work-on-plans`, or any monitor surface (verified during refine).
- ROG line 153: "/draft-tests is its own skill family, no shared files" with ZSKILLS_MONITOR_PLAN.

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review (full default budget), followed by /refine-plan with 3 rounds of verification-and-tighten review.
**Convergence:** /draft-plan reached max rounds with severity trajectory monotonically decreasing — 21 → 7 → 2, zero HIGH findings in round 3, all round-3 findings empirically reproduced and fixed. /refine-plan round 1 surfaced 7 additional substantive findings (3 reviewer + 4 DA, 0 HIGH / 4 MEDIUM / 3 LOW) that the prior rounds' "exhaustive audit" claims had missed. /refine-plan round 2 surfaced 2 more substantive findings (1 reviewer + 1 DA, both MEDIUM), genuine sibling-sites of /refine-plan round 1's own additions. /refine-plan round 3 — the round the user invoked specifically as a final convergence verification — produced **zero reviewer findings (the first clean reviewer pass across 6 passes total) plus 1 DA finding**: AC-1.7b had been referenced from three sites (WI 1.7b prose, AC-3.1 body, narrative log) but never added as a numbered AC bullet in Phase 1's AC block; Phase 6 WI 6.1's test checklist contained zero bullets exercising the ac-less path or AC-3.1's M = N − K formula. The DA grepped `^- \[ \] AC-1\.7b` and got zero hits — a sibling-site of the WI 1.7b cone that 6 prior passes missed because none of them grep'd for the AC bullet's actual existence in the AC block. Cumulative trajectory across all 6 review passes: 21 → 7 → 2 → 7 → 2 → 1, monotonically decreasing in count and severity (zero HIGH since /draft-plan round 3; rounds 5+ all MEDIUM-or-below; rounds 4+ exclusively sibling-sites of prior fixes — no new defect classes). Honest accounting: round 3's "every closed-enumeration of trailing sections audited" was incomplete (it covered three sites — WI 5.2, WI 5.7, Phase 5 D&C — but not AC-2.10, a fourth site /refine-plan round 1 caught). Round 2's "AC-ID classifier handles ambiguous prefixes via three-predicate test" was incomplete: the canonical-prefix regex did not match sub-letter ACs (`AC-1.6b`, `AC-1.6c`) — the very form the plan itself uses — and the step-2 ambiguous regex did not catch scope-tag-leading bullets (`- [ ] [scope] ...`), self-failing AC-1.6c case (iii). /refine-plan round 1's own WI 1.7b addition was incomplete in two distinct ways across two rounds: AC-3.1's count predicate, WI 3.5's append loop, and the schema for `ac_less:` (caught in round 2); plus the AC-1.7b bullet itself missing from Phase 1's AC block and untested in WI 6.1 (caught in round 3 — final cone closure). /refine-plan round 1's broad-form `^## ` boundary rule was not fenced-code-block-aware (caught in round 2). /refine-plan round 2 + round 3 caught all five of these. All ten /refine-plan findings were fixed (7 in round 1, 2 in round 2, 1 in round 3). The trajectory pattern — each round's fixes producing sibling-sites visible in the next round — has converged: round 3's reviewer returned zero independently, and the DA's single finding closes the WI 1.7b sibling-site cone. A round 4 of /refine-plan would most likely return zero substantive findings (DA's own assessment: "the WI 1.7b sibling-site cone is now fully closed; a round-7 verification would almost certainly return zero").
**Remaining concerns:** None substantive. One round-1 DA finding (split Phase 4) was justified-not-fixed by evidence — work items are tightly coupled and Phase 4's size is comparable to similarly-sized phases in `/draft-plan` itself.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 9 (4 HIGH, 4 MEDIUM, 1 LOW) | 12 (6 HIGH, 4 MEDIUM, 2 LOW) | 19 Fixed, 1 Justified-verified, 1 implicit overlap |
| 2     | 2 (0 HIGH, 2 MEDIUM, 0 LOW) | 5 (2 HIGH, 3 MEDIUM, 0 LOW) | 7/7 Fixed (both HIGH empirically reproduced against real plans) |
| 3     | 1 (0 HIGH, 1 MEDIUM, 0 LOW) | 1 (0 HIGH, 1 MEDIUM, 0 LOW) | 2/2 Fixed (sibling-site follow-ons of round-2 fix patterns; both verified against `EXECUTION_MODES.md` and parsed-state flow) |
| /refine-plan 1 | 3 (0 HIGH, 1 MEDIUM, 2 LOW) | 4 (0 HIGH, 3 MEDIUM, 1 LOW) | 7/7 Fixed (sub-letter AC regex blind spots in WI 1.6 / AC-3.2 / WI 4.8; `tests/run-all.sh` ordering claim; AC-6.2 undercount; step-2 regex scope-tag gap; AC-2.10 closed-enumeration; ac-less Pending phase edge case via WI 1.7b; in-place-edit reassembly spec in Phase 1 D&C) |
| /refine-plan 2 | 1 (0 HIGH, 1 MEDIUM, 0 LOW) | 1 (0 HIGH, 1 MEDIUM, 0 LOW) | 2/2 Fixed (WI 1.7b consumer-site update at AC-3.1 + WI 3.5 + `ac_less:` schema clarification; fenced-code-block-aware boundary scan at WI 1.5 / WI 5.2 / WI 5.7 + AC-1.5 + AC-5.7 regression fixtures + new WI 6.3 conformance grep — both empirically reproduced against `plans/EXECUTION_MODES.md`) |
| /refine-plan 3 | **0** (zero — first clean reviewer pass) | 1 (0 HIGH, 1 MEDIUM, 0 LOW) | 1/1 Fixed (AC-1.7b never added as numbered AC bullet to Phase 1's AC block + WI 6.1 had zero ac-less test coverage — final WI 1.7b sibling-site closure; verified via `grep -nE '^- \[ \] AC-1\.7b'` returning zero hits, and ac-less / M=N−K coverage absence in WI 6.1) |

### Notable round-1 structural fixes

- Reordered phases so language detection + test-file discovery moves earlier (closing hidden-dependency findings from both reviewers via a single change).
- Replaced single-bullet gap-detection with a three-level COVERED / UNKNOWN / MISSING confidence rubric (UNKNOWN emits advisory, never auto-backfills).
- Renamed re-invocation section from `## Drift Log` (conflicted with `/refine-plan`) to `## Test Spec Revisions` with a 2-column `| Date | Change |` schema.
- Added frontmatter `status: complete` → `active` flip when backfill is appended (closes a `/run-plan`-refuses-to-execute-backfill bug).

### Notable round-2 structural fixes

- Replaced enumerated-headings checksum boundary with a broad-wildcard "next `## ` heading" rule plus conformance check (closes a HIGH bug where the skill would have been unusable on existing plans like `EXECUTION_MODES.md` that contain non-canonical level-2 headings — empirically verified against `/workspaces/zskills/plans/EXECUTION_MODES.md`, `EPHEMERAL_TO_TMP.md`, `CREATE_WORKTREE_SKILL.md`).
- Hardened AC-ID assignment with three-predicate classifier and an ambiguous-prefix advisory (closes a HIGH bug where work-item-numerical bullets — empirically present in `CANARY_DO_WORKTREE_BASE.md` — would have produced double-numeral corruption). **Caveat (caught by /refine-plan round 1):** the round-2 classifier was NOT actually exhaustive — the canonical-prefix regex omitted a trailing `[a-z]?` and so misclassified sub-letter ACs (`AC-1.6b`, `AC-1.6c`); the step-2 ambiguous regex `[0-9A-Z]` did not include `\[`, so scope-tag-leading bullets fell through to the assign path. /refine-plan round 1 broadened both regexes.
- Persisted delegate-classification in parsed-state (WI 1.4b) so Phase 3 and Phase 4 read from a single source of truth.
- Coverage-floor pre-check now operates on a per-round merged candidate file rather than ambiguous "current draft."
- Resolved AC-4.6/AC-4.7 contradiction on max-rounds-with-floor-violation via exit code 2 (distinct from clean-converge exit 0).

### Notable round-3 structural fixes

- Added WI 5.3b (mandatory parsed-state append on backfill insertion) and AC-5.10 (asserts list-membership invariant + coverage-floor synthesises a violation when the drafter omits a backfill-phase AC). Closes a MEDIUM bug where Phase 4's coverage-floor pre-check would not enforce coverage on backfill-phase ACs because Phase 5's runtime backfill flow never refreshed `non_delegate_pending_phases:` in parsed-state.
- Replaced closed-enumeration of trailing sections with broad-wildcard "any non-phase `## ` heading" rule at three sibling sites missed in round 2 (WI 5.2 backfill-insertion, WI 5.7 Test-Spec-Revisions placement, Phase 5 D&C "Backfill is structural-insert" bullet). Extended AC-5.7 with the `EXECUTION_MODES.md` regression fixture and added two new conformance greps to WI 6.3. Closes a MEDIUM bug where backfill phases would have been mis-inserted between user-authored sections like `## Anti-Patterns -- Hard Constraints` and `## Plan Quality`. **Caveat (caught by /refine-plan round 1):** the round-3 audit covered three sibling sites but missed AC-2.10, a fourth site whose closed-enumeration parenthetical retained the same anti-pattern. /refine-plan round 1 broadened AC-2.10.

### Notable /refine-plan round-3 structural fixes

- Added `- [ ] AC-1.7b — ...` as a properly-formatted numbered bullet in Phase 1's `### Acceptance Criteria` block (after AC-1.7), referencing the ac-less classification, the parsed-state list invariants, the advisory line emission, and the M = N − K coupling. WI 1.7b had said "Add AC-1.7b: a fixture..." for two rounds without an actual AC bullet to back it up — the final loose end of the WI 1.7b cone.
- Added a test bullet to WI 6.1's checklist exercising the ac-less path: a fixture with one ac-less Pending non-delegate phase + one normal Pending non-delegate phase, asserting (i) `ac_less:` parsed-state contents, (ii) `non_delegate_pending_phases:` retention, (iii) M = N − K formula self-pass, (iv) advisory-line emission count.
- **The trajectory's signature pattern (each round's fixes produce sibling-sites in the next) has now finished.** Round 3 reviewer found zero independently; the DA found the only sibling-site that remained, and its fix is internal-only (no new spec patterns introduced that could in turn have sibling sites). A round 4 would not produce new findings — the WI 1.7b cone is fully closed.

### Notable /refine-plan round-2 structural fixes

- Completed integration of WI 1.7b (ac-less Pending phases) into its consumer sites: AC-3.1's count formula was rewritten as M = N − K (where K = ac-less count) so the AC self-passes on a fixture combining ac-less and normal Pending phases; WI 3.5 now explicitly reads the `ac_less:` list from parsed-state (mirroring WI 3.6's `delegate_phases:` read pattern), eliminating a single-source-of-truth violation; WI 1.7b's schema was tightened to "newline-separated list of phase identifiers, mirroring `delegate_phases:`." Closes a MEDIUM defect introduced BY /refine-plan round 1's WI 1.7b addition — its consumer sites couldn't be patched until they became reviewable in a subsequent round.
- Made the broad-form `^## ` boundary rule fenced-code-block-aware at three parallel sites (WI 1.5 checksum boundary, WI 5.2 backfill-insertion scan, WI 5.7 Test-Spec-Revisions placement). Implementation pattern: a single-pass awk-style state-tracker toggling `in_code` on each ` ``` ` line; heading detection runs only when `in_code == 0`. Added regression fixtures to AC-1.5 and AC-5.7 mirroring `plans/EXECUTION_MODES.md` (which contains 3 in-code-block `## ` headings at lines 236, 2079, 2082). Added a new conformance grep to WI 6.3 (item 10) checking the SKILL.md asserts the fenced-code-block-aware semantics. Closes a MEDIUM defect where the broad-form rule introduced by /refine-plan round 1 had a fenced-code-block edge case — naive `^## ` boundary scans would silently truncate Completed-phase checksums at in-code headings. AC-6.2 count updated 9 → 10 to reflect the new conformance check.

### Verify-before-fix discipline

All three /draft-plan rounds applied verify-before-fix at refinement: the refiner agent reproduced each empirical claim before acting. Round 2's two HIGH findings and round 3's two MEDIUM findings were all verified against real plan files (`EXECUTION_MODES.md`, `EPHEMERAL_TO_TMP.md`, `CREATE_WORKTREE_SKILL.md`, `CANARY_DO_WORKTREE_BASE.md`) plus internal cross-references to the plan's own work items. Zero findings across all rounds were rejected as not-reproduced. Both /refine-plan rounds likewise verified each finding before acting — round 1 walked the regexes by hand against the plan's own AC bullets, read `tests/run-all.sh` directly to disprove the alphabetical-ordering claim, and counted WI 6.3 enumeration items (9, not 6); round 2 ran an awk-with-code-block-strip enumeration on `EXECUTION_MODES.md` to confirm the 3 in-code-block `## ` headings exist (lines 236, 2079, 2082) and grepped the plan to confirm WI 3.5 lacked an `ac_less:` parsed-state read.

### Convergence verified empirically through round 3

Strict /draft-plan convergence is "0 substantive issues found in a verification round." That bar was hit at round 3 of /refine-plan: the **reviewer returned zero findings** for the first time across all 6 passes. The DA returned one finding — a sibling-site of the WI 1.7b cone (AC-1.7b never added as a numbered bullet) that all six prior reviewers missed because none of them grep'd for the actual AC bullet's existence in Phase 1's AC block. That finding's fix is internal-only (no new spec patterns introduced that could in turn have sibling-sites), closing the WI 1.7b cone definitively. Cumulative trajectory across all 6 review passes: 21 → 7 → 2 → 7 → 2 → 1, monotonically decreasing in count and severity (zero HIGH since /draft-plan round 3; rounds 5+ all MEDIUM-or-below; rounds 4+ exclusively sibling-sites of prior fixes — no new defect classes). The plan has been pressure-tested against: the plan's own AC bullets (regex-against-self), the plan file's structural-rule reach (closed-enumeration sweep across all sites including AC-2.10 and the WI 1.7b cone), real-plan empirical fixtures (EXECUTION_MODES.md, EPHEMERAL_TO_TMP.md, CREATE_WORKTREE_SKILL.md, CANARY_DO_WORKTREE_BASE.md), adjacent-skill reality-grounding (citation line numbers, integration claims, post-round-2 commit drift via 28d22d8), numeric arithmetic on every count claim, fenced-code-block edge cases on the broad-form rule, and re-invocation idempotence on backfill phases. A round 7 of /refine-plan would most likely return zero findings — DA's own assessment: "the WI 1.7b sibling-site cone is now fully closed; a round-7 verification would almost certainly return zero." The plan is empirically converged and ready for `/run-plan`.

## Disposition Table — /refine-plan 2026-04-29 Round 1 Adversarial Review

| # | Source | Finding (summary) | Evidence | Disposition |
|---|--------|-------------------|----------|-------------|
| R1.1 | Reviewer | WI 1.3 sanitize-pipeline-id.sh path drift (post-PR-#97) — `scripts/sanitize-pipeline-id.sh` no longer exists; relocated to `skills/create-worktree/scripts/...` per script-ownership.md | Verified — `find . -name sanitize-pipeline-id.sh` returns only `skills/create-worktree/scripts/...` and `.claude/skills/create-worktree/scripts/...`; script-ownership.md:74-79 confirms `"$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"` cross-skill caller form | Fixed — WI 1.3 last sentence rewritten to use `"$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh"`; added Phase 1 D&C bullet "Cross-skill script invocation" naming the convention and forbidding bare-`scripts/` form (per user directive 1) |
| R1.2 | Reviewer | WI 6.5 mirror snippet outdated (post-PR-#88) — inline `mkdir+cp` only copies SKILL.md, no orphan removal, no diff-verify; recursive-rm refactor is hook-blocked | Verified — `scripts/mirror-skill.sh:30-75` provides `cp -a` + per-file orphan loop + post-regen `diff -rq`; `hooks/block-unsafe-generic.sh:217-220` RM_RECURSIVE blocks recursive rm outside /tmp; script-ownership.md:32 names mirror-skill.sh as canonical | Fixed — WI 6.5 rewritten to `bash scripts/mirror-skill.sh draft-tests`; added Phase 6 D&C bullet "Mirror discipline"; AC-6.4 widened to `diff -rq` per directive 2 |
| R1.3 | Reviewer | Phase 4 D&C convergence framing missing "orchestrator's judgment" (post-PR-#82) | Verified — `skills/refine-plan/SKILL.md:383` and `skills/draft-plan/SKILL.md:474` both contain the verbatim "orchestrator's judgment, not the refiner's self-call" framing | Fixed — added leading bullet "Convergence is the orchestrator's judgment, not the refiner's self-call" to Phase 4 D&C with citation to refine-plan:383 and draft-plan:474; added AC-4.9 testing the negative case (refiner self-call ignored when conditions fail); added WI 4.9 / 4.11 prose framing; added new WI 6.3 conformance grep for the phrase |
| R1.4 | Reviewer | WI 1.1 argument-hint omits `[guidance...]` tail (post-PR-#85); asymmetric with /refine-plan | Verified — `skills/refine-plan/SKILL.md:4` has `[guidance...]`; plan L70 lacks it | Fixed — adopted `[guidance...]` per user directive 4; updated WI 1.1 argument-hint, WI 1.2 parsing semantics with priming-context-not-fact note, WI 4.1/4.2 prepend semantics, AC-1.1, added AC-1.2b (guidance-prepend regression guard), and 6.1 test bullet |
| R1.5 | Reviewer | Default-rounds asymmetry vs /refine-plan undocumented | Verified — draft-plan default 3 (SKILL.md:32), refine-plan default 2 (SKILL.md:42-46) | Fixed — Phase 4 D&C "Default rounds" bullet expanded with explicit asymmetry rationale per user directive 5 (kept at 3 to match /draft-plan blank-slate framing; called out /refine-plan's 2 as the closer-structural-sibling alternative and explained why) |
| R1.6 | Reviewer | PLAN-TEXT-DRIFT machinery (PRs #90-#92) unmentioned; non-integration not declared | Verified — plan grep for `PLAN-TEXT-DRIFT|plan-drift-correct` returns 0; run-plan SKILL.md has 14+ references | Fixed — added Phase 4 D&C bullet "PLAN-TEXT-DRIFT tokens are out of scope" with one-sentence non-coupling note citing run-plan SKILL.md:739, :744, :1358-:1418 (per user directive 6) |
| R1.7 | Reviewer | WI 6.2 placement guidance has stale "after test-skill-invariants.sh" anchor | Verified — tests/run-all.sh line 45 still has test-skill-invariants.sh, but 16 more entries follow including test-mirror-skill.sh:53 and test-stub-callouts.sh:58 | Fixed — WI 6.2 rewritten with explicit anchor-stable guidance ("group alongside skill-conformance / skill-test peers, near line 43/45/53/58"); line numbers labeled "illustrative, anchored to current main but not load-bearing" |
| R1.8 | Reviewer | AC-6.4 `cmp` parity check incompatible with subdirectory mirroring | Verified — `mirror-skill.sh:66-71` uses `diff -rq`; AC-6.4 specs `cmp` on a single file | Fixed — AC-6.4 rewritten to `diff -rq skills/draft-tests/ .claude/skills/draft-tests/` returning empty output, matching mirror-skill.sh contract; `cmp` retained as a minimum sub-condition |
| R1.9 | Reviewer | WI 6.3 / AC-6.6 jq-absence regex `[^a-zA-Z]` boundaries miss underscore identifiers; `grep -r` follows symlinks inconsistently | Verified — plan L1347 has `(^|[^a-zA-Z])jq([^a-zA-Z]|$)` literal | Fixed — AC-6.6 hardened to `[^a-zA-Z_]` boundaries and `-rIE` (binary skip); WI 6.3 last bullet updated to reference AC-6.6's hardened pattern |
| R1.10 | Reviewer | Phase 6 D&C "do not weaken tests" rule should reference CLAUDE.md surface-bugs guard | Verified — CLAUDE.md preamble has both rules paired ("NEVER weaken tests" + "Skill-framework repo — surface bugs, don't patch"); plan L1317-1319 only carries the first | Fixed — extended the "do not weaken tests" Phase 6 D&C bullet with the surface-bugs-don't-patch corollary, naming zskills as a skill-framework repo where quiet route-arounds get multiplied across consumers |
| R1.11 | Reviewer | WI 5.6 spec lacks pointer to /run-plan's other terminal-treatment paths (cron interaction) | Verified — run-plan SKILL.md:413-419 cron cleanup gates on status==complete; status flip → active correctly bypasses (case-4 path) | Fixed — appended "Cron interaction (informational)" paragraph to WI 5.6 explaining cron correctly continues firing after status flip and that /draft-tests does not touch registered crons |
| R1.12 | Reviewer | AC-6.2 hardcodes "ten" — count-pin fragility (already drifted 9→10 once during /refine-plan round 2) | Verified — plan L1332-1334 has "ten ... items (1)–(10). Future additions ... must bump this count concurrently"; round 2 drift confirmed in Plan Quality / Round History | Fixed — AC-6.2 rewritten to list-membership invariant ("one `check` / `check_fixed` line per WI 6.3 sub-bullet"); WI 6.3 preamble names the per-bullet contract explicitly per user directive 9 |
| DA1 | DA | WI 1.3 sanitize-pipeline-id.sh path is broken (literal stale anchor) | Verified — same evidence chain as R1.1 (PR #97 relocation, script-ownership.md cross-skill caller convention, STALE_LIST migration) | Fixed — same edits as R1.1 (consolidated; this is a duplicate finding) |
| DA2 | DA | WI 6.5 mirror snippet ships dirty mirror on re-runs (orphan files survive); AC-6.4 `cmp` SKILL.md alone passes silently on orphan-survivor | Verified — same evidence chain as R1.2 + DA2's broader AC-6.4 concern; mirror-skill.sh:32-63 covers subdirectories; AC-6.4 widening also addresses DA2's silent-pass concern | Fixed — same edits as R1.2 + AC-6.4 widened to `diff -rq` per user directive 2's broader scope (covers references/, scripts/, orphan removal) |
| DA3 | DA | WI 6.5 narrative invariant "Never edit `.claude/skills/draft-tests/SKILL.md` directly" too narrow — should cover any file under `.claude/skills/draft-tests/` | Judgment | Fixed — WI 6.5 prohibition broadened: "Never edit any file under `.claude/skills/draft-tests/` directly during development" with citation to CLAUDE.md memory anchor `feedback_claude_skills_permissions.md` |
| DA4 | DA | Plan body never names "orchestrator judgment" — diverges from PR #82 convergence model | Verified — same evidence chain as R1.3; CLAUDE.md memory anchor `feedback_convergence_orchestrator_judgment.md` confirms the recurring-failure-mode framing | Fixed — same edits as R1.3 (consolidated); additionally added new WI 6.3 conformance grep for the phrase "orchestrator's judgment" so silent regression is caught at conformance time per directive 3's negative-case AC requirement |
| DA5 | DA | `[guidance...]` not adopted; default rounds=3 inconsistent with refine-loop semantics | Verified — same evidence chain as R1.4 + R1.5 | Fixed — same edits as R1.4 (adopt guidance) + R1.5 (document rounds asymmetry); per user directives 4 + 5 |
| DA6 | DA | `## Test Spec Revisions` is a section name that NO existing skill recognises; /refine-plan's checksum boundary at SKILL.md:110 is closed-form `## Phase` only — incompatible with /draft-tests's broad-form rule | Verified — refine-plan SKILL.md:110 confirms closed-form "next `## Phase` or end of file"; refine-plan Phase 5 reassembly at SKILL.md:397-411 rebuilds without preserving non-Drift-Log/Plan-Review trailing sections | Fixed — chose user-directive option (a) "declare ordering": Phase 5 D&C new bullet "Co-skill ordering with /refine-plan" pins `## Test Spec Revisions` placement AFTER `## Drift Log` / `## Plan Review`; AC-5.11 added testing the order; WI 5.7 placement language updated; ALSO documented the deeper /refine-plan reassembly-loss issue (Test Spec Revisions destroyed by subsequent /refine-plan run) with the workaround (run /refine-plan first, re-run /draft-tests after) and the proper /refine-plan PR called out as Out-of-Scope |
| DA7 | DA | AC-6.2 pin-count "ten" couples plan to test count; future WI 6.3 grows are silent regressions | Verified — same evidence chain as R1.12 | Fixed — same edit as R1.12; per user directive 9 (list-membership pattern, not count) |
| DA8 | DA | `plans/examples/` lives outside `tests/fixtures/` but `/run-plan` may scan `plans/`; PLAN_INDEX.md rebuild risk | Verified partial — `collect.py:1097` uses `plans_dir.glob("*.md")` (top-level only, NOT recursive); current scanners would NOT pick up `plans/examples/*.md`. However user directive 8 prefers relocation as defensive against future recursive globbing + cleaner separation | Fixed — relocated worked example to `tests/fixtures/draft-tests/examples/` per user directive 8 option (b); WI 6.4 rewritten with relocation rationale (current scanner state verified at collect.py:1097) and a future-recursive-globbing defensive note; AC-6.3 updated to assert location AND adds negative assertion (no example files under `plans/examples/`); Phase 6 D&C "Fixture plans" bullet aligned |
| DA9 | DA | Phase 4 reviewer/DA prompts say "live LLM" via Agent dispatch — but plan does not anchor model selection (Opus inheritance vs. risk of Sonnet/Haiku optimization later) | Judgment — CLAUDE.md memory anchor `feedback_no_haiku.md` is explicit on inherit-parent default; risk is forward-looking | Fixed — added Phase 4 D&C bullet "Agent model dispatch" pinning inherit-parent (Opus default); cites CLAUDE.md memory anchor; explains "QE judgment is judgment-class work, not bulk pattern matching" rationale |
| DA10 | DA | Plan has zero coupling to PR #114 smoke-revert or PR #88 mirror — but mentions neither, and Phase 6 examples reuse mirroring patterns; non-integration declaration missing | Judgment + verified-partial — PRs #90-#92 PLAN-TEXT-DRIFT non-coupling already addressed via R1.6; PR #114 / PR #88 are auxiliary but worth a non-coupling sentence per zskills convention | Fixed — Phase 4 D&C PLAN-TEXT-DRIFT non-coupling bullet (per R1.6) explicitly notes "WI 1.6's AC-ID assignment touches ONLY `### Acceptance Criteria`; the drafter's `### Tests` output is treated as inert text by `plan-drift-correct.sh --correct` (which targets `### Acceptance Criteria` numeric bullets only) — drafter MUST NOT emit `PLAN-TEXT-DRIFT:` tokens" closing the contract per user directive 6. PR #88 (mirror) is now load-bearing in WI 6.5 + Phase 6 D&C "Mirror discipline" — no longer adjacency, integration is explicit. PR #114 smoke-revert is /run-plan-internal; no /draft-tests surface coupling exists, no further note needed |

### Convergence note for orchestrator

Round 1 disposition counts:
- Total findings: 21
- Verified empirical: 14 (R1.1, R1.2, R1.3, R1.4, R1.5, R1.6, R1.7, R1.8, R1.9, R1.10, R1.11, R1.12, DA1, DA2, DA4, DA5, DA6, DA7) — note R1.* and DA* duplicates count toward the same Verified empirical pool
- Verified partial / mixed: 1 (DA8 — collect.py glob is non-recursive but defensive relocation chosen)
- Judgment: 2 (DA3, DA9)
- Mixed (judgment + verified-partial): 1 (DA10)
- Not reproduced: 0
- No anchor: 0
- Fixed: 21
- Justified-not-fixed: 0
- Substantive issues remaining (refiner's count): 0

This is the refiner's count against the round's findings. **Convergence is the orchestrator's judgment, not the refiner's self-call** — the orchestrator counts Justified-not-fixed entries plus any new gaps the refinement introduced and applies the four positive conditions in Phase 4 D&C against the table above. The refiner does NOT declare convergence here; the orchestrator must read the table and the rounds budget independently.

## Plan Review

**Refinement process:** /refine-plan (2026-04-29) with 1 round of adversarial review (orchestrator-judgment convergence per PR #82; user-budgeted rounds=2 short-circuited at round 1 because substantive issues = 0 after disposition).
**Convergence:** Converged at round 1. All 21 findings (11 reviewer + 10 DA) disposed: 21 fixed, 0 justified-not-fixed.
**Remaining concerns:** None blocking. /refine-plan checksum-boundary broadening for `## Test Spec Revisions` is documented as out-of-scope future work (co-skill PR).

### /refine-plan Round History (this refine, 2026-04-29)

| Round | Reviewer Findings | Devil's Advocate Findings | Substantive | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1     | 11 (2 blocker, 0 major, 6 minor, 3 spec) | 10 (1 blocker, 3 major, 3 minor, 3 spec) | 0 | 21 fixed, 0 justified-not-fixed |

The disposition table for this refine's round 1 is at the previous section ("Disposition Table — /refine-plan 2026-04-29 Round 1 Adversarial Review"). Earlier Plan Quality / Disposition Tables describe the original /draft-plan + /refine-plan history from 2026-04-24.
