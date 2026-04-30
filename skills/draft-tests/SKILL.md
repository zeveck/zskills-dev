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

<!-- allow-hardcoded: TZ=America/New_York reason: illustrative tracking-marker idiom; per-skill $TIMEZONE migration is scoped to plans/SKILL_FILE_DRIFT_FIX.md, not this Phase 1 skeleton -->
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

<!-- allow-hardcoded: TZ=America/New_York reason: illustrative tracking-marker idiom; per-skill $TIMEZONE migration is scoped to plans/SKILL_FILE_DRIFT_FIX.md, not this Phase 1 skeleton -->
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

This phase detects the project's language(s) and test-file conventions
so the drafter (Phase 3) can calibrate against existing test style and
the Phase 5 backfill gap detection has a stable test-file map. It runs
AFTER Phase 1's parser writes the parsed-state file. It is purely
mechanical detection: no test runner is installed, scaffolded, or
executed.

The detection step is **config-first**: before any manifest sniff or
test-file discovery, the skill reads the consumer's
`.claude/zskills-config.json` and resolves the test command via the
same three-case decision tree used by `/verify-changes` (see
`skills/verify-changes/SKILL.md` lines 76–137 for the canonical
implementation; the same idioms apply here).

### Three-case test-cmd resolution (config-first)

```bash
PROJECT_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
DETECT_STATE="/tmp/draft-tests-detect-${SLUG}.md"
bash "$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/detect-language.sh" \
  "$PROJECT_ROOT" "$DETECT_STATE"
```

The Phase 2 detection-state file is **additive** to Phase 1's parsed-
state shape (introduced via `parse-plan.sh`): the new `case:`,
`languages:`, `recommendations:`, `test_files:`,
`calibration_signal_file:`, `no_test_setup:`, `recommendation_text:`,
`detection_status:`, `config_full_cmd:`, `config_unit_cmd:`, and
`advisories:` keys do not conflict with Phase 1's `plan_file:`,
`completed_phases:`, `pending_phases:`, `non_delegate_pending_phases:`,
`delegate_phases:`, `ac_less:`, `frontmatter_*:`, or `advisories:`
schema. (`advisories:` overlaps in name only — Phase 2 writes its own
file; consumers reading both can concatenate, sort, or merge as
needed.)

`detect-language.sh` writes a structured detection-state file recording:

- **case** (1, 2, or 3) — the three-case outcome.
- **languages:** — newline-separated list of detected languages.
- **recommendations:** — `<lang>: <runner>` lines (one per language).
- **test_files:** — `<lang>:<absolute-path>` entries listing every
  candidate test file found. **Phase 5 reads this list** for backfill
  gap detection without re-running discovery (per AC-2.9).
- **calibration_signal_file** — path to a separate file containing the
  bounded calibration signal (≤ 20 lines per language; reads at most 3
  test files per language; never raw test-file contents).
- **detection_status** — `ok`, `undetectable`, or `error`.
- **config_full_cmd** / **config_unit_cmd** — verbatim values from
  `.claude/zskills-config.json` `testing.full_cmd` / `testing.unit_cmd`.
  Empty if not set.
- **recommendation_text** — the verbatim `## Prerequisites` block to
  insert in case 3 (no test infra + no config). Empty otherwise.

The three cases:

1. **case 1** — `.claude/zskills-config.json` has `testing.full_cmd`
   or `testing.unit_cmd` set. The drafter prompt receives the value
   verbatim. Detection is downgraded to informational (framework
   recommendation only; no Prerequisites block; no recommendation
   text).
2. **case 2** — config is empty AND ≥ 1 test file was found via the
   language-aware heuristics below. The drafter prompt is given the
   detected framework recommendation plus the calibration signal. No
   command is asserted — the drafter is told to match existing style
   only.
3. **case 3** — config is empty AND no test infra exists. The skill
   emits a `## Prerequisites` recommendation block (per WI 2.4) and
   the drafter prompt and the inserted block both contain the literal
   string `no configured test runner` (per AC-2.4).

**Never sniff `package.json` scripts, `pytest.ini`, `Makefile`, or
similar to "guess" a test command.** Config-first is a deliberate
honesty boundary — see CLAUDE.md memory anchor
`feedback_verifier_test_ungated.md`.

### Language detection from manifest files (WI 2.1)

The language detection step recognises a small set of canonical
manifest files via `detect-language.sh`:

- `package.json` → JavaScript/TypeScript. Recommended runner: vitest.
  If `jest` is referenced anywhere in `package.json` (scripts or
  devDependencies), recommend jest instead.
- `pyproject.toml`, `setup.py`, or `requirements*.txt` → Python.
  Recommended runner: pytest.
- `go.mod` → Go. Recommended runner: `go test` (built in).
- `Cargo.toml` → Rust. Recommended runner: `cargo test` (built in).
- Heavy `*.sh` content (≥ 3 files at repo root or under `scripts/`)
  AND no other manifest → bash. Recommended runner: bats.
- **Multiple manifests** → polyglot. Per-subtree recommendations are
  emitted (one per detected language). Example: a project with
  `Cargo.toml` and `package.json` gets "Rust tests via `cargo test`;
  JS tests via vitest" — never a single winner.
- **None of the above** → report `language undetectable` and degrade
  to the WI 2.4 path.

**Graceful fallback (WI 2.7).** If any detection step errors (missing
permissions, malformed manifest), `detect-language.sh` logs the
failure to stderr, sets `detection_status: undetectable`, and
proceeds. Detection failure never aborts the run.

### Test-file discovery (WI 2.2)

Language-aware heuristics, NOT runner-sniffing:

- JS/TS: `*.test.{ts,tsx,js,jsx}`, `*.spec.{ts,tsx,js,jsx}`,
  `__tests__/` directories, `tests/` directory.
- Python: `test_*.py`, `*_test.py`, `tests/` directory.
- Go: `*_test.go`.
- Rust: files under `tests/` subtrees, `#[cfg(test)]` blocks (found via
  grep, not parsed).
- Bash: `tests/test-*.sh`, `tests/*_test.sh`.

If the repo has zero candidate files, the calibration signal is empty
and the drafter is told **"no existing tests to calibrate against —
use the recommended runner's defaults."**

### Calibration signal (WI 2.3, AC-2.8)

Bounded signal extraction:

- **Per language, read at most 3 test files**, preferring the file
  with the most imports (proxy for "canonical example for this
  project"). Ties broken by largest file. For polyglot projects, this
  cap applies per detected language.
- **Extract via a small regex panel**: imports (top 10 lines),
  presence of `describe(`/`it(`/`test(`/`test_`/`_test` patterns,
  `assertEqual`/`expect(`/`assert.`/`should` patterns,
  `beforeEach`/`fixture`/`setup` patterns, assertion library name.
- **Emit ≤ 20 lines per language** as a structured summary (framework
  name, naming convention, fixture style, assertion library, one
  representative test-file path). This is the *calibration signal*.
  Full test-file contents are never passed to the drafter.
- **Persist the full test-file path list** (not contents) under
  `test_files:` so Phase 5 can re-read candidate files for gap
  detection without re-running discovery (AC-2.9).

### No-test-setup path (WI 2.4) and `## Prerequisites` insertion (AC-2.10)

When `case == 3` (no test infra + no config), the skill writes the
`recommendation_text` block as a `## Prerequisites` section between
`## Overview` and `## Progress Tracker`. **Every other level-2 section
must remain byte-identical** — broad form, including non-canonical
user-authored sections like `## Anti-Patterns -- Hard Constraints`,
`## Non-Goals`, `## Risks and Mitigations`. Insertion is fenced-code-
block-aware (mirroring the parse-plan section-boundary scan).

```bash
if [ "$CASE" = "3" ]; then
  PREREQ_BODY="/tmp/draft-tests-prereq-${SLUG}.md"
  awk '
    /^recommendation_text_begin$/ { active=1; next }
    /^recommendation_text_end$/   { active=0; next }
    active                        { print }
  ' "$DETECT_STATE" > "$PREREQ_BODY"
  if [ -s "$PREREQ_BODY" ]; then
    bash "$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/insert-prerequisites.sh" \
      "$PLAN_FILE" "$PREREQ_BODY"
  fi
fi
```

`insert-prerequisites.sh` does the byte-preserving in-place edit:

- If the plan already has a `## Prerequisites` section (prior
  invocation), the existing block is replaced in place — not
  duplicated.
- If the plan has no `## Prerequisites`, the block is inserted on the
  blank line above `## Progress Tracker`.
- The skill writes the recommendation. It does **NOT** install,
  scaffold, or run anything. WI 2.5 — `--bootstrap` is explicitly out
  of scope for v1; the recommendation IS the entire no-test-setup
  behavior.

### Bootstrap is out of scope for v1 (WI 2.5)

A `--bootstrap` flag that prepends a Phase 0 to scaffold a missing
test runner is explicitly noted as future work and is NOT exposed in
v1. The written `## Prerequisites` recommendation is the entire
no-test-setup behavior.

### Client-project portability

`detect-language.sh` runs in **consumer repos**, not just zskills. It
takes `$PROJECT_ROOT` as its first argument and never assumes
`tests/run-all.sh`, `tests/test-*.sh`, or any zskills-specific layout.
All detection heuristics are expressed as generic file patterns. The
skill itself does not modify the project's environment.

## Phase 3 — Drafting agent and test-spec format

This phase dispatches a single drafting agent that reads the parsed-state
file (Phase 1) and the detection-state file (Phase 2), produces a
per-phase spec body for every Pending non-delegate non-ac-less phase,
writes those bodies to a SPECS FILE on disk, then calls the deterministic
orchestrator to insert each `### Tests` subsection into the plan at the
position-priority slot. Phase 4's adversarial review loop reads the
per-round drafter output file produced here.

The drafting agent is dispatched via the `Agent` tool (general-purpose,
inheriting the parent model — Opus by default; never Haiku, per CLAUDE.md
memory anchor `feedback_no_haiku.md`). The agent's role is to author
specs only; it does NOT mutate the plan file. File mutation is handled
by `append-tests-section.sh` via `draft-orchestrator.sh`.

### Drafting agent dispatch

```bash
DRAFT_ROUND_OUT="/tmp/draft-tests-draft-round-0-${SLUG}.md"
SPECS_FILE="/tmp/draft-tests-specs-round-0-${SLUG}.md"
```

The drafter agent prompt is assembled inline below. Before dispatch, the
orchestrator script writes the parsed-state list of targeted phases (the
non-delegate non-ac-less Pending phases) and the resolved test-command
context into the prompt — so the agent sees exactly which phases require
specs and which test runner (if any) is configured.

After dispatch, the agent's output is parsed for the spec bodies, written
to `$SPECS_FILE`, and the orchestrator runs:

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/draft-orchestrator.sh" \
  "$PLAN_FILE" "$PARSED_STATE" "$SPECS_FILE" "$DRAFT_ROUND_OUT" 0
```

The orchestrator handles: per-phase iteration, position-priority
insertion via `append-tests-section.sh`, idempotent skip when
`### Tests` already exists, and writing the round-N artifact with
`drafted_phases:`, `delegate_skipped_phases:`, `ac_less_skipped_phases:`,
and `idempotent_skipped_phases:` lists. Source-tree zskills tests use the
`"$REPO_ROOT/skills/draft-tests/scripts/draft-orchestrator.sh"` form
(per `skills/update-zskills/references/script-ownership.md`).

### Single-source-of-truth invariant

The drafter MUST consume `ac_less:` from the parsed-state file: it MUST
NOT re-derive ac-less-ness by re-scanning phase content
(single-source-of-truth, mirrors WI 3.6's delegate-skip pattern). The
drafter MUST consume `delegate_phases:` from the parsed-state file: it
MUST NOT re-grep the plan or apply its own heuristic
(single-source-of-truth invariant with WI 4.8). Both `delegate_phases:`
and `ac_less:` lists are read once from
`/tmp/draft-tests-parsed-<slug>.md` and reused — re-grepping the plan
body for `### Execution: delegate` or absence-of-`### Acceptance
Criteria` is a defect.

`draft-orchestrator.sh` reads the parsed-state lists and computes the
target set as `non_delegate_pending_phases - ac_less` — no re-derivation.

### Spec format — one-line bullet (canonical)

```
- [scope] [risk: AC-N.M] given <input>, when <action>, expect <literal>
```

Where:

- **scope** is one of `unit`, `integration`, `property`, `e2e`. The
  drafter picks the narrowest scope that exercises the AC. Reach for
  `[integration]` / `[e2e]` only when unit scope cannot observe the AC.
- **risk: AC-N.M** links the spec to the AC it exercises. The trailing
  `[a-z]?` after the second numeral admits sub-letter ACs (e.g.
  `[risk: AC-1.6c]`).
- **\<literal\>** is an exact value, named exception, or precisely-defined
  observable side effect. `assert f(0) == 0` is a literal. `Returns
  {status: 'ok', count: 3}` is a literal. `raises ValueError("empty
  input")` (named exception) counts as a literal. "Test the zero case"
  is NOT — that is a vague placeholder and is rejected by AC-3.3.

### Spec format — multi-line expansion

When a one-liner becomes unreadable (long inputs, multi-step setup,
non-trivial expected values), the drafter expands into:

```markdown
- [scope] [risk: AC-N.M] <short name>
  - Input: <literal>
  - Action: <literal>
  - Expected: <literal>
  - Rationale: <one sentence — why this spec exists, not how it works>
```

Expansion is the drafter's judgment call; the senior-QE review loop
(Phase 4) pushes back if one-liners are illegible or expansions are
gratuitous.

### Drafting agent prompt — senior-QE persona

The drafter is dispatched with the following persona prompt (verbatim
where indicated):

> You are a senior QE engineer with 15+ years of experience reviewing
> systems engineering work for testability. Your job is to author
> specs that an implementing agent (an AI dispatched by `/run-plan`)
> can mechanically translate into tests. **You do not write test code.
> You author specs.** The implementer will translate `[unit] [risk:
> AC-3.2] given f(0), when called, expect 0` into the project's
> existing assertion idiom (vitest `expect(f(0)).toBe(0)`, pytest
> `assert f(0) == 0`, Go `if got := f(0); got != 0 { t.Errorf(...) }`,
> bash `[ "$(f 0)" = "0" ] || fail`). Calibrate framework choice,
> naming conventions, fixture style, and assertion library to the
> project's existing tests per the Phase-2 calibration signal,
> unless this phase's requirements justify a different level (e.g.,
> existing tests are unit-only, this phase needs integration).
>
> **Senior-QE norms calibration** — your specs reflect the discipline
> of Bach (Heuristic Test Strategy: test against the product's stated
> operating conditions, not arbitrary edge cases), Bolton (specs are
> claims about behavior, not procedures), Beck (TDD: spec the smallest
> assertion that fails on the bug you're catching, not a barrage of
> sympathetic assertions), Hendrickson (exploratory testing surfaces
> ACs, not assertion theatre), and Crispin/Gregory (whole-team
> testing: every AC is a testable claim or it's not done). You are
> authoring specs for an implementer who will read them, write tests,
> and ship — write specs that a competent implementer can take
> mechanically.

This calibration is in the prompt body verbatim (not just the persona
label) per WI 3.3. The senior-QE-norms paragraph is not optional —
without it the drafter regresses to assertion-theatre style.

### Drafting agent inputs

The drafter receives:

- **Plan file** (full text, read fresh from disk).
- **Parsed-state file path** (`/tmp/draft-tests-parsed-<slug>.md`) — for
  the authoritative `non_delegate_pending_phases:`, `delegate_phases:`,
  and `ac_less:` lists.
- **Detection-state file path** (`/tmp/draft-tests-detect-<slug>.md`) —
  for languages, framework recommendation, and the calibration signal
  reference.
- **Calibration signal file path** (from detection-state's
  `calibration_signal_file:`).
- **Resolved test-command context.** If
  `.claude/zskills-config.json` has `testing.full_cmd` /
  `testing.unit_cmd`, those values are passed to the drafter prompt
  verbatim (per AC-3.4). If neither is configured, the drafter prompt
  contains the literal string `no configured test runner — scope tags
  remain valid; specs don't assume a runner` (also per AC-3.4 — the
  detection-state file's `config_unit_cmd:` empty triggers this path).
- **Phase-2 calibration outputs**: language list, framework
  recommendations, existing-test convention summary.

### Anti-pattern list (verbatim in drafter prompt)

The following anti-patterns are forbidden, listed verbatim in the
drafter's prompt:

> Anti-patterns — do NOT produce specs that exhibit any of the
> following:
>
> - **No happy-path-only coverage.** Every spec set must include at
>   least one error / boundary / negative case per AC, unless the AC
>   is provably positive-only.
> - **No assertion mirroring.** Do not assert that `f()` returns what
>   `f()` returns. Assert against an externally-known literal.
> - **No hallucinated APIs.** Check existence before referencing —
>   the implementer cannot test `widget.spin()` if no such method
>   exists. If the plan implies the API, name the AC; if it does
>   not, flag the gap to the user.
> - **No over-specific assertions baking in transient values.** Do
>   not pin to a specific timestamp, hash, or generated id; pin to
>   the structural claim ("returns a non-empty UUID v4 string").
> - **No mock-thrash.** Do not mock everything until the test
>   asserts on its own mock. Mock the boundary; assert on the
>   product code's behaviour.
> - **No empty try/catch scaffolds.** Every exception handler in a
>   spec must specify the exception type AND a partial message
>   match.
> - **No MAX_INT / Unicode / clock-skew cargo-cult tests** unless
>   the AC actually mentions those domains. The bar is product
>   intent, not folklore.

### Coverage requirement at draft time

Every AC in every Pending non-delegate non-ac-less phase MUST have at
least one spec referencing it via `risk: AC-N.M`. The drafter is told
this is a FLOOR, not a ceiling — more specs are welcome if they cover
orthogonal risks. Delegate-phase ACs are exempt (see WI 3.6).

If an AC appears untestable as-written, the drafter flags it back to
the user via a comment in the round-0 output — does NOT fabricate a
softer spec to satisfy the floor (per Design & Constraints "Drafter
never recommends weakening tests").

### Append logic and position priority

For each Pending non-delegate non-ac-less phase, the orchestrator
inserts a `### Tests` subsection at the position-priority slot:

1. Immediately after the phase's `### Acceptance Criteria` block
   (highest priority — the AC-and-its-spec stay co-located).
2. Else after `### Design & Constraints`.
3. Else after `### Work Items`.
4. **Never** before `### Goal`. **Never** inside an
   `### Execution: ...` subsection (delegate phases are skipped
   wholesale per WI 3.6 / AC-3.6; the inside-execution guard is a
   defensive secondary).

`append-tests-section.sh` implements this priority order. Boundary
detection is fenced-code-block-aware (mirrors parse-plan.sh's
invariant) so a `## ` heading inside a ` ``` ` fence does not falsely
terminate subsection boundaries.

### Idempotent re-invocation

If `### Tests` already exists in the phase (re-invocation),
`append-tests-section.sh` is a no-op — the plan file is left
byte-identical for that phase. Phase 5's refinement path handles
updates to existing `### Tests` content. Idempotency is verified by
running the orchestrator twice on the same fixture and asserting the
plan file is byte-identical on the second run (AC-3.5).

### Skip rules — single-source-of-truth

- **Skip phases listed in `ac_less:`** (parsed-state, per WI 1.7b) —
  these phases get NO `### Tests` subsection regardless of position
  priority. The WI 1.7b advisory line is emitted in their stead.
- **Skip phases listed in `delegate_phases:`** (parsed-state, per WI
  1.4b) — test coverage is the delegated skill's responsibility (the
  sub-skill authors its own tests inside the work it produces).

The drafter MUST consume those parsed-state lists and MUST NOT
re-derive either property from the plan body. `draft-orchestrator.sh`
enforces this by reading both lists from the parsed-state file and
computing the target set as a set-difference.

### Drafter output file (per-round artifact)

The orchestrator writes `/tmp/draft-tests-draft-round-0-<slug>.md`
before merging into the plan. This is the input for Phase 4's review
loop. Format:

```
plan_file: <path>
parsed_state: <path>
specs_file: <path>
round: <N>
drafted_phases:
  <phase-id>
  ...
delegate_skipped_phases:
  <phase-id>
  ...
ac_less_skipped_phases:
  <phase-id>
  ...
idempotent_skipped_phases:
  <phase-id>
  ...
specs_begin
phase: <phase-id>
<spec body>
phase: <phase-id>
<spec body>
specs_end
```

`delegate_skipped_phases:` is recorded so Phase 4's reviewer/DA prompts
and Phase 6's conformance test (AC-3.6) can read it as a concrete
artifact rather than parsing prose. AC-3.6 set-equality is verified
by parsing `delegate_phases:` from the parsed-state file and
`delegate_skipped_phases:` from the round-0 output, sorting both, and
diffing — empty diff = equal sets = pass.

### Drafter never writes test code

Specs only. Test code is the implementer's job during `/run-plan`.
Past failure mode: drafters wrap-up by writing illustrative test
snippets and the implementer copy-pastes them, baking the drafter's
guesses into the test suite. Hold the line — specs only.

## Phase 4 — Adversarial review loop (QE personas)

After Phase 3 has appended a `### Tests` subsection into every Pending
non-delegate non-ac-less phase, this phase wraps the drafter output in a
review loop calibrated to senior-QE norms. Reviewer + devil's advocate
agents are dispatched **in parallel** per round (matching `/draft-plan`
Phase 3); the refiner runs serially after both return; the orchestrator
mechanically determines convergence.
**Reviewer, DA, and refiner agents inherit the parent model** — never
pass a `model:` parameter on dispatch. QE judgment is judgment-class
work, not bulk pattern matching, per
CLAUDE.md memory anchor `feedback_no_haiku.md`. Past canary failures
have stemmed from Sonnet/Haiku optimisations on judgment-class tasks.

The mechanical orchestration is implemented by three scripts under
`skills/draft-tests/scripts/`:

- `coverage-floor-precheck.sh` — runs BEFORE each round's agent
  dispatch; merges drafter/refiner output into a per-round candidate
  file; greps the candidate for `risk: AC-N.M` references; synthesises
  one `Coverage floor violated: AC-N.M ...` finding per missing AC.
- `convergence-check.sh` — reads the refiner's disposition table, ignores
  any "CONVERGED" / "no further refinement needed" prose, applies the
  four positive conditions from Design & Constraints, returns 0 if
  converged or 1 if not.
- `review-loop.sh` — round driver. Calls the pre-check, dispatches
  reviewer + DA (mocked in tests via env-var stubs; live-LLM gated
  behind `ZSKILLS_TEST_LLM=1`), writes the per-round artifacts, calls
  the convergence check, exits with code 2 (partial-success) on max
  rounds + coverage floor unmet (per AC-4.6 / AC-4.7).

### Reviewer / DA prompt prefix — guidance directive (WI 4.1, WI 4.2)

If the user supplied positional-tail guidance (per the Arguments
section), prepend a `User-driven scope/focus directive:` section to
BOTH the reviewer and devil's-advocate prompts containing the guidance
text verbatim — exactly mirroring `skills/refine-plan/SKILL.md:50, :132`.
Empty guidance preserves byte-identical reviewer/DA prompt output (no
behavior change for invocations without trailing guidance tokens).

The agents treat this as **priming context** (what to pressure-test),
NOT as factual claims (still subject to verify-before-fix in the
refiner).

### Reviewer agent prompt — senior-QE persona (WI 4.1)

The reviewer is dispatched with the senior-QE persona (Bach / Bolton /
Beck / Hendrickson / Crispin/Gregory calibration; same calibration
paragraph as the Phase 3 drafter). It looks for findings of these
shapes:

- (a) a stated AC has no spec referencing it,
- (b) a spec has no literal expected value,
- (c) an assertion is so weak it would pass on a broken implementation,
- (d) a mock destroys the test's value (asserts on its own mock),
- (e) a specified observable side effect is not exercised,
- (f) a spec targets scope wrong (e.g., an integration-only AC has only
  unit specs).

**Landmine mitigation:** the prompt explicitly states **"test specs are
expansions of ACs, not replacements — if a spec and its AC conflict in
tone, that is a finding."** This prevents the `/run-plan`-parser
disambiguation failure mode (per research §Top 3 landmines).

### Devil's advocate prompt (WI 4.2)

Same persona, adversarial stance. Genuinely tries to find how the spec
set will leave real defects uncaught. Explicitly NOT a gotcha-generator —
the senior-QE-norms calibration text from Phase 3 applies. Same
guidance prepend semantics as the reviewer (WI 4.1).

### NOT-a-finding list (WI 4.3, authored fresh for this skill)

Inserted verbatim in BOTH reviewer and DA prompts. **NOT a finding:**

- Implausible failure modes under the product's stated operating
  conditions (Bach).
- Type-system-enforced preconditions.
- Performance / concurrency / security tests on non-load-bearing code.
- Tests duplicating existing specs in the same phase.
- MAX_INT / Unicode / clock-skew tests on code whose ACs don't mention
  those domains.
- Tests requiring infrastructure not present (e.g., "spin up postgres"
  when the project is config-only).
- Tests that exist only to increase coverage numbers.
- Tests of framework code rather than product code.
- Property-based tests for functions with no meaningful algebraic
  properties.

This list is **fresh for this skill** — `/draft-plan` has no
QE-specific NOT-a-finding list, so it is NOT inherited.

### Zero findings is valid and correct (WI 4.4, AC-4.1, AC-4.2, authored fresh)

Both prompts state this in the output-format block. If the reviewer has
nothing substantive to flag, it outputs `## Findings` with a single
explicit line: `No findings — spec set meets the stated criteria.`
The loop treats this as a round-pass, not a bug. **This zero-findings
path is NOT equivalent to "convergence"** — convergence is enforced
mechanically against the positive definition in Design & Constraints
(the orchestrator's check, not the refiner's self-call), and includes
the orchestrator-level coverage-floor pre-check that runs BEFORE agent
dispatch each round.

- **AC-4.1**: a round whose reviewer output is "No findings — spec set
  meets the stated criteria." with DA the same AND whose
  orchestrator-level coverage-floor pre-check produces zero synthetic
  findings does not cause the loop to error / stall / mark the plan
  incomplete; the loop treats this as convergence and proceeds.
- **AC-4.2**: on a plan where an AC lacks a spec AND both agents return
  "No findings", the orchestrator's pre-check injects a coverage-floor
  finding, the refiner addresses it, and the loop does NOT converge on
  that round.

### Mandatory blast-radius field (WI 4.5, AC-4.3, authored fresh)

Every finding **must end with**:

```
Blast radius: <minor|moderate|major> — <one-line description of what would happen if this gap shipped to prod>
```

- **Minor** findings are dropped at refiner stage.
- **Moderate** findings must be resolved.
- **Major** findings must be resolved or block convergence.

Findings missing the `Blast radius:` line are rejected by the refiner
with a `finding-format-violation` note in the disposition table. The
prompt makes this explicit so the reviewer/DA self-conform.

### Prior-rounds dedup (WI 4.6, authored fresh)

From round 2 onward, both agents receive the previous round's findings
list with the directive **"already addressed — do not re-raise in
rephrased form."** The refiner is the secondary gate: if a round-N
finding is semantically identical to a round-(N-1) finding, the refiner
marks it `Justified — duplicate of round N-1` in the disposition table.
The convergence check skips Justified-duplicate rows when counting
unresolved blockers.

### Evidence discipline — `Verification:` line on every empirical claim (WI 4.7)

Patterned on `/draft-plan`'s reviewer/DA sections (see
`skills/draft-plan/SKILL.md:369-374`): every empirical claim ("the
existing test file at X uses framework Y"; "AC-3.2 has no spec
referencing it") **ends with a `Verification:` line** containing the
exact grep, file:line, or command output reproducing the evidence.
Structural / judgment findings use `Verification: judgment — no
verifiable anchor` explicitly.

The refiner re-runs each `Verification:` check **before acting** —
verify-before-fix discipline. Devil's-advocate findings are
particularly prone to plausible-sounding-but-false claims because the
DA's role is generating failure modes, not verifying them. The
discipline is load-bearing: claims whose evidence doesn't reproduce do
not drive fixes.

### Orchestrator-level coverage-floor pre-check (WI 4.8, AC-4.8)

Runs BEFORE dispatching reviewer/DA each round. Implementation:
`skills/draft-tests/scripts/coverage-floor-precheck.sh`. The pre-check
operates on a **per-round candidate file** to unify first-invocation,
re-invocation, and backfill-invocation semantics. The algorithm:

1. Read the plan file's current bytes.
2. Read the round-N drafter output (or, on round ≥ 1, the refiner's
   round-(N-1) output).
3. Construct the candidate by overlaying the drafter / refiner's
   `### Tests` subsections into their target phases (in-memory merge —
   does not touch the plan-file on disk). Write the result to
   `/tmp/draft-tests-candidate-round-<N>-<slug>.md`.
4. Read the `non_delegate_pending_phases:` list from the parsed-state
   file (Phase 1, WI 1.4b) — this is the authoritative scope for ACs
   subject to the coverage floor. **The pre-check MUST NOT re-derive
   delegate-classification.**
5. For every AC in those phases, grep the candidate for a
   `risk: AC-<phase>.<n>[<sub-letter>]?` reference (sub-letter suffix
   admitted to match sub-letter ACs like `AC-1.6c`); for each AC
   lacking one, synthesise a finding of the form:

   ```
   Coverage floor violated: AC-N.M has no spec. Blast radius: major - coverage floor is the convergence precondition.
   ```

6. Inject these synthetic findings into the refiner's input alongside
   reviewer / DA findings.

Because the grep target is the **merged candidate** (not the plan file
alone, not the drafter-output alone), first-invocation round 0 finds
the drafter's specs (no spurious mass-violation), re-invocation finds
existing in-plan specs (no false redundancy), and backfill-invocation
finds specs from the round's drafter output merged on top of the
backfill phase. This closes both the zero-findings-vs-convergence
contradiction (WI 4.4 vs the Design & Constraints convergence rule)
AND the grep-target ambiguity (what "the current draft" resolves to per
invocation mode).

Invocation:

```bash
PRECHECK="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/coverage-floor-precheck.sh"
bash "$PRECHECK" \
  "$PLAN_FILE" "$PARSED_STATE" "$PREV_INPUT" \
  "$ROUND_N" "$SLUG" \
  "/tmp/draft-tests-candidate-round-${ROUND_N}-${SLUG}.md" \
  "/tmp/draft-tests-floor-findings-round-${ROUND_N}-${SLUG}.md"
```

Source-tree zskills tests use the equivalent
`"$REPO_ROOT/skills/draft-tests/scripts/coverage-floor-precheck.sh"`
form (per `skills/update-zskills/references/script-ownership.md`).

### Refiner agent — verify-before-fix and disposition table (WI 4.9)

The refiner receives:

- The current draft (read from `$PLAN_FILE`).
- The combined reviewer + DA findings.
- The synthesised coverage-floor findings from the pre-check.
- The previous round's findings list (round ≥ 2) for dedup.

**Verify-before-fix is mandatory.** For each finding, the refiner runs
the `Verification:` check (Read the file, run the grep, check the
schema, run the command). It records the outcome per finding in a
disposition table:

| Finding | Evidence | Disposition |
|---------|----------|-------------|
| <finding text including `Blast radius:`> | Verified \| Not-reproduced \| No-anchor \| Judgment | Fixed \| Justified — <reason> |

Per AC-4.4, the disposition table has **one row per finding** with
exactly these three columns.

For Verified findings with moderate / major blast radius, the refiner
fixes the draft. For Not-reproduced or No-anchor findings, it
justify-not-fixes with the reproduction attempt recorded. For
Justified-duplicate findings (round ≥ 2), it marks
`Justified — duplicate of round N-1`.

**The refiner produces a disposition table — it does NOT declare
convergence.** The refiner's role ends at its disposition table.
Convergence is the orchestrator's mechanical check (next section).

The refiner can **STOP and report** if it cannot resolve a finding and
cannot justify it away. The skill surfaces unresolved findings in the
final output rather than silently writing a spec set with known
defects.

The refiner **never writes to Completed phases**. Same immutability
contract as Phase 1.

### Per-round artifacts (WI 4.10)

Each round writes:

- `/tmp/draft-tests-candidate-round-<N>-<slug>.md` — merged candidate
  used by the pre-check.
- `/tmp/draft-tests-floor-findings-round-<N>-<slug>.md` — synthesised
  coverage-floor findings (empty if floor met).
- `/tmp/draft-tests-review-round-<N>-<slug>.md` — combined reviewer +
  DA + synthesised coverage-floor findings.
- `/tmp/draft-tests-refined-round-<N>-<slug>.md` — refiner output +
  disposition table.

These artifacts persist across context compaction. `review-loop.sh`
writes them.

### Convergence check (WI 4.11) — orchestrator's mechanical judgment

Implementation:
`skills/draft-tests/scripts/convergence-check.sh`. After each round, the
orchestrator reads the refiner's disposition table and applies the four
positive conditions from Design & Constraints below. **It NEVER accepts
"CONVERGED" / "no further refinement needed" / equivalent self-call
from the refiner agent's prose output.** The script literally does not
parse those strings.

On convergence or max rounds, the refined draft from the last round
becomes the final spec set used in Phase 5 / 6.

Invocation:

```bash
CONVERGENCE="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/convergence-check.sh"
bash "$CONVERGENCE" "$REFINED_OUT" "$FLOOR_FINDINGS"
# rc=0 -> CONVERGED; rc=1 -> NOT CONVERGED (reasons on stdout)
```

### Round driver — `review-loop.sh`

`skills/draft-tests/scripts/review-loop.sh` is the round driver. It:

1. Runs the coverage-floor pre-check (Step 1 above).
2. Dispatches reviewer + DA in parallel — in **test mode**, agent
   output is supplied via env-var stubs:
   `ZSKILLS_DRAFT_TESTS_REVIEWER_STUB_<N>` and `..._DA_STUB_<N>`. In
   **live mode**, the SKILL.md prose dispatches the agents and writes
   the same files; the script reads them. Live mode is gated behind
   `ZSKILLS_TEST_LLM=1` per AC-4.5.
3. Writes the combined review artifact (reviewer + DA + synthesised
   floor findings).
4. Dispatches the refiner — stub: `..._REFINER_STUB_<N>`.
5. Calls `convergence-check.sh`. On convergence, exits 0. Else carries
   the refined output forward as the next round's pre-check input.
6. On max rounds without convergence, writes the **"Remaining concerns"**
   note to `/tmp/draft-tests-remaining-concerns-<slug>.md` and exits
   with code 2 if the coverage floor is unmet (per AC-4.6 / AC-4.7) or
   code 3 if the floor is met but other convergence conditions still
   fail.

Tests stub all three roles (no live LLM dispatch in
`tests/test-draft-tests-phase4.sh`). CI skips live runs with the explicit
"Tests: skipped — LLM-in-the-loop ACs" note matching `/verify-changes`'s
skipped-test convention.

### Convergence is the orchestrator's judgment, not the refiner's self-call (AC-4.9)

Mirroring `skills/refine-plan/SKILL.md:383` and
`skills/draft-plan/SKILL.md:474`: the refiner produces a disposition
table; the orchestrator (the skill body itself, not the agent) reads
the table and applies the four positive conditions. **NEVER accept
"CONVERGED", "no further refinement needed", or equivalent self-call
from the refiner agent as authoritative** — the refiner just refined;
it is biased toward declaring its own work done. This is a recurring
failure mode in practice (see CLAUDE.md memory anchor
`feedback_convergence_orchestrator_judgment.md`).

This is the **AC-4.9 negative-case guard.** A refiner output containing
the literal text "CONVERGED" / "no further refinement needed" but
whose disposition table fails any of the four positive conditions
(missing AC coverage, non-literal expected, dup of round N-1,
unresolved moderate/major-blast-radius finding) does NOT cause the
skill to exit with convergence status. The orchestrator's mechanical
check on the disposition table overrides the refiner's self-call.

### Convergence (positive definition)

A round converges when **all four** of the following hold (orchestrator
counts these against the disposition table; refiner's prose claim of
convergence is ignored):

1. Every AC across all Pending non-delegate phases has ≥ 1 spec
   referencing it (coverage floor — enforced mechanically by the
   pre-check before agent dispatch).
2. Every spec has a literal expected value or named exception.
3. No finding from this round duplicates a previous round's finding
   (after refiner's dedup pass).
4. All findings are either resolved or have blast radius = minor
   (dropped at refiner stage).

**Negative-only convergence** ("no new findings this round") is
explicitly rejected — vulnerable to reviewer-ratchet where each round
finds a new wave of decreasingly-relevant issues. **Zero findings from
agents** is a valid round result but does NOT by itself imply
convergence — the positive criteria must all hold.

### Default rounds = 3

Matches `/draft-plan` (also default 3). Note: `/refine-plan` defaults
to 2 because it operates on an already-refined plan; `/draft-tests`'s 3
matches `/draft-plan` because the typical invocation is blank-slate (no
prior `### Tests` subsections) — Phase 4's senior-QE personas review
specs against fresh ACs whose shape they have never seen, more like
first-pass than refinement. On re-invocation against a plan that
already has specs (Phase 5 refinement path), 2 rounds would suffice —
but the simpler v1 contract is "default 3 always; early exit on
convergence handles the re-invocation case." Override with `rounds N`
per invocation.

### PLAN-TEXT-DRIFT tokens are out of scope

`/run-plan`'s `PLAN-TEXT-DRIFT:` pipeline (PRs #90-#92) detects
arithmetic divergence in plan bullets at execution time. Test specs
authored by `/draft-tests` are qualitative (scope / AC-link /
literal-expected) and contain no arithmetic claims a `/run-plan` agent
would measure — so the drafter does NOT emit `PLAN-TEXT-DRIFT:` tokens,
and the review loop does not check for them. AC-ID assignment touches
ONLY the `### Acceptance Criteria` block; the drafter's `### Tests`
output is treated as inert text by `plan-drift-correct.sh --correct`
(which targets `### Acceptance Criteria` numeric bullets only). This is
a correct non-integration; flagged here so a future implementer doesn't
introduce a spurious coupling.

### Max-rounds exit and partial-success — exit code 2 (AC-4.6, AC-4.7)

If the loop hits max rounds AND the coverage floor remains unmet, the
skill takes the AC-4.6 path (writes the partial spec set + a "Remaining
concerns" note listing each unresolved finding's one-line description
and blast radius) AND exits with **return code 2**, reserved for
**"partial-success — coverage floor not met."** The plan on disk
reflects the best-effort spec set; the non-zero exit blocks downstream
automation from advancing on un-attested coverage. The plan IS written
(no hard-abort that loses work). This is NOT a contradiction with
AC-4.6 — both ACs apply on this path, and exit code 2 is the
conjunction.

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
non-phase level-2 sections — **the broad form: any `## <name>` (other
than `## Phase ...`) outside fenced code blocks the user has authored
after the last phase counts as a trailing section, not a closed
list.** Use the same awk-style `in_code` state-tracker as WI 1.5 / WI
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
VERIFY="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/verify-completed-checksums.sh"
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
GAP="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/gap-detect.sh"
BACKFILL="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/append-backfill-phase.sh"
TSR="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/insert-test-spec-revisions.sh"
FLIP="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/flip-frontmatter-status.sh"
REINV="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/re-invocation-detect.sh"
VERIFY="$CLAUDE_PROJECT_DIR/.claude/skills/draft-tests/scripts/verify-completed-checksums.sh"

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
