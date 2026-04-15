---
name: refine-plan
disable-model-invocation: false
argument-hint: "<plan-file> [rounds N]"
description: >-
  Refine an in-progress plan by reviewing remaining phases against completed
  work. Dispatches adversarial reviewer and devil's advocate agents to find
  stale references, invalidated assumptions, and specification gaps — then
  refines remaining phases until convergence. Completed phases are NEVER
  modified. Appends a Drift Log and Plan Review section.
  Usage: /refine-plan <plan-file> [rounds N]
---

# /refine-plan \<plan-file> [rounds N] — Adversarial Plan Refiner

Refines an existing plan that is partially executed. Completed phases
represent real, shipped work — they are **immutable context**, never
modification targets. The refiner reviews only the remaining phases against
what was actually built (not what was planned), then iteratively improves
them through adversarial review cycles.

The insight: plans drift during execution. Completed phases may have built
something different from what was originally specified. Remaining phases
still reference the original spec. `/refine-plan` closes this gap by
reviewing remaining phases against the *actual* state of completed work,
not the planned state.

**Completed phases are NEVER modified.** They are read-only context that
informs the review. Not even heading typo fixes. Immutability is verified
mechanically: completed phase sections must be byte-identical before and
after refinement.

**Ultrathink throughout.**

## Arguments

```
/refine-plan <plan-file> [rounds N]
```

- **plan-file** (required) — path to the plan `.md` file to refine.
- **rounds N** (optional) — max review/refine cycles. Default: 2. The
  process exits early if a round converges (no substantive new issues).
  Default is 2 (not 3 like `/draft-plan`) because this is a refinement
  pass on an existing plan, not blank-slate creation.

**Detection:** scan `$ARGUMENTS` from the start:
- The **first token** ending in `.md` or containing `/` is the plan file.
  If the token contains `/`, use as-is; otherwise prepend `plans/`.
- `rounds` followed by a number sets max cycles.
- If no plan file is detected, **error:** "No plan file specified.
  Usage: `/refine-plan <plan-file> [rounds N]`"

Examples:
- `/refine-plan plans/EXECUTION_MODES.md`
- `/refine-plan plans/EXECUTION_MODES.md rounds 3`
- `/refine-plan THERMAL_PLAN.md` -> reads `plans/THERMAL_PLAN.md`
- `/refine-plan rounds 2 plans/FEATURE.md` -> plan file is `plans/FEATURE.md`, 2 rounds

## Phase 1 — Parse Plan

### Tracking fulfillment

Determine the tracking ID: use the ID passed by the parent skill if this
is a delegated invocation, or derive from the plan file slug if standalone
(e.g., `plans/EXECUTION_MODES.md` -> `execution-modes`). Create the
fulfillment file in the MAIN repo:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking"
printf 'skill: refine-plan\nid: %s\nplan: %s\nstatus: started\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/fulfilled.refine-plan.$TRACKING_ID"
```

### Parse the plan file

1. **Read the plan file.** If it does not exist, **error:** "Plan file
   `<path>` not found."

2. **Parse YAML frontmatter** — extract `title`, `status`, `issue`, etc.

3. **Parse the Progress Tracker table.** For each phase row, classify:
   - **Completed:** Status column contains `Done`, a checkmark (`✅`),
     or `[x]` (case-insensitive).
   - **Remaining:** everything else — `⬚`, `In Progress`, `Blocked`,
     empty, or any other value.
   - Sub-phases (e.g., `3a`, `3b`) are classified independently.

4. **Extract phase sections.** For each phase heading (`## Phase N — Name`),
   extract the full section text. Associate each section with its
   completed/remaining classification from the Progress Tracker.

5. **Validate:**
   - At least one remaining phase must exist. If all phases are completed,
     exit cleanly: "All phases complete — nothing to refine. Run with a
     plan that has remaining phases."
   - If no Progress Tracker table is found, attempt to infer phase status
     from section content (e.g., presence of commit hashes, `[x]` in work
     items). If unable to infer, **error:** "No Progress Tracker found in
     `<path>`. Add a Progress Tracker table with phase status columns so
     the refiner can distinguish completed from remaining phases."

6. **Compute checksums** of each completed phase section (the full text
   from `## Phase N` to the next `## Phase` or end of file). These
   checksums are used in Phase 5 to verify byte-identical immutability.

7. **Write parsed state** to `/tmp/refine-plan-parsed-<slug>.md` where
   `<slug>` comes from the plan filename (e.g., `EXECUTION_MODES` from
   `plans/EXECUTION_MODES.md`). Include:
   - List of completed phases with checksums
   - List of remaining phases with full text
   - YAML frontmatter values
   - Plan file path

   This file persists across context compaction. All subsequent phases
   read from it if context is lost.

## Phase 2 — Adversarial Review (parallel agents)

Dispatch two agents simultaneously. Both receive:
- The full plan text
- Completed phases clearly marked as **READ-ONLY CONTEXT** (not review targets)
- Remaining phases as the **REVIEW TARGET**
- The parsed state file path (`/tmp/refine-plan-parsed-<slug>.md`)

### Establishing current reality (preamble — both agents)

Before applying any of the six review dimensions, both agents must
establish current reality. The dimensions ask whether remaining phases'
references, assumptions, and acceptance criteria hold — that question
has no meaningful answer without knowing what reality now looks like.

1. **Read the codebase state** for anything remaining phases will
   interact with — source files, skills, configs, docs, schemas,
   whatever. The plan text may be stale; reality is what exists.
2. **Check what completed phases actually produced** (via commit
   diffs or current file state) vs what they planned. Where they
   diverged, reality wins; note the divergence in the Drift Log but
   do NOT modify the completed phase section.
3. **Incorporate changes outside the plan** — recent external
   commits, known fixes, user-provided context. Reality includes
   everything, not just phase output.
4. **Treat remaining phases as a coherent whole.** Even if the plan
   was recently patched in only some sections, review how any
   changes ripple forward into all other remaining phases. Do not
   focus review only on recently-edited sections — the plan's
   cohesion comes from how ALL remaining phases fit together.

5. **Dry-run each remaining phase against current reality.** For each
   remaining phase, step through what it will do at execution time.
   Where does it invoke skills, touch files, query configs, or make
   API calls? At every external interaction point, check what current
   reality will produce:
   - **Skill invocation** → read the skill's current text and
     simulate each stage of its flow. At each stage, ask: does this
     stage's behavior still make sense given the mode/options the
     phase will invoke the skill in, and given anything completed
     phases added to the skill? Pay special attention to
     pre-existing stages that weren't touched by completed phases
     but will now run alongside new ones.
   - **File write** → check whether the file exists, what convention
     surrounds it, whether the write respects that convention.
   - **Config query** → check the config's current value, not the
     value the plan assumes.
   - **API/tool call** → check the current signature and behavior.

   Flag any step where reality produces different behavior than the
   remaining phase expects. This catches mode-conditional drift
   (rules written for an old default that silently misbehave under a
   new mode added by completed phases) that dimensions 1-6 can miss
   when applied only against plan text.

Only then apply dimensions 1-6 against that reality.

### Reviewer agent

Reviews remaining phases against the reality of completed work. Checks
these six dimensions:

1. **Stale references** — code, files, APIs, data structures, or paths
   mentioned in remaining phases that were replaced, renamed, or removed
   by **any source** (completed phases, external changes, or recent
   patches). The plan may reference `src/old-module.js` but reality
   moved it to `src/new-module.ts`.

2. **Consistency** — do remaining phase specs match **current reality**
   (the codebase, completed phases' actual output, recent changes) —
   not what the plan originally planned? Where completed phases
   deviated from their spec, or external changes shifted things, the
   code is reality.

3. **Sizing** — are remaining phases still right-sized (~3-5 components,
   ~500 lines) given what's known now? Completed work may have changed the
   scope of what remains.

4. **Specification gaps** — do remaining phases reference decisions, APIs,
   or data structures that are **missing from reality or inconsistent
   with it**? The gap may be in what completed phases were supposed to
   define but didn't, in what external changes introduced that the plan
   doesn't account for, or in remaining phases that reference a
   convention/rule elsewhere in the codebase that has since changed.

5. **Dependency correctness** — are remaining phase dependencies correct
   given completed work and remaining phase ordering? A dependency on
   Phase 2 may be satisfied if Phase 2 is done, or may need updating if
   Phase 2 built something different.

6. **Acceptance criteria coverage** — do acceptance criteria in remaining
   phases cover all work items? Are criteria still valid given what
   completed phases actually produced?

Each finding must be **specific and actionable**: cite the exact section,
line, or reference that's wrong and what it should say instead.

**Evidence discipline.** When a finding makes an empirical claim (a file
has/lacks X, a function does Y, a tool's input contains Z), include a
concrete **Verification:** line — the exact file:line, grep, schema
quote, or command output that reproduces the evidence. The refiner will
re-run these checks before acting. Structural/judgment findings
("this phase mixes too many concerns") don't need a reproducer, but
mark them explicitly: `Verification: judgment — no verifiable anchor`.
Never write an empirical-sounding claim without something the refiner
can independently re-check.

### Devil's Advocate agent

Genuinely adversarial — tries to find ways the remaining plan will fail
given what's already been built. Checks these six dimensions:

1. **Invalidated assumptions** — assumptions in remaining phases that
   completed work disproved. "Phase 4 assumes the solver returns a flat
   array, but Phase 2 actually returns a typed object."

2. **Unnecessary work items** — things remaining phases plan to do that
   completed phases already handled. Duplicate work wastes agent time
   and risks conflicts.

3. **Deferred hard parts** — difficult items hidden behind vague language
   in remaining phases. "Phase 5: integrate everything" — that's where
   all the complexity actually lives.

4. **Hidden dependencies** — undeclared dependencies between remaining
   phases. Phase 4 may silently need output from Phase 3 without listing
   it as a dependency.

5. **Scope drift** — remaining phases that grew beyond original intent
   without justification. Compare against the plan's Overview section.

6. **Integration risks** — ways remaining work will break when combined
   with completed work. What interfaces exist between completed and
   remaining phases? Are they compatible?

Each finding must be **specific and actionable** — not generic concerns.
"Phase 3 might be complex" is useless. "Phase 3 says 'implement the
export pipeline' but doesn't specify the serialization format, and
Phase 1 already committed to MessagePack in `src/io.ts` — the agent will
have to guess or conflict" is actionable.

The same **evidence discipline** from the reviewer section applies:
every empirical claim needs a `Verification:` line (file:line, grep,
schema quote, etc.). The devil's advocate is *especially* prone to
generating plausible-sounding-but-false claims because its job is
pattern-generating failure modes, not verifying them. Discipline is
load-bearing here.

### Write findings

Write combined findings to `/tmp/refine-plan-review-round-N-<slug>.md`
(e.g., `/tmp/refine-plan-review-round-1-EXECUTION_MODES.md`). Include
reviewer findings and devil's advocate findings in separate sections.
If the file already exists from a prior invocation, **overwrite** (not
append).

### Post-review tracking

After both agents return, create the review step marker:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'round: %s\ncompleted: %s\n' "$ROUND" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/step.refine-plan.$TRACKING_ID.review"
```

## Phase 3 — Refine

A single agent receives:
- The current remaining phases text
- All findings from Phase 2 (from the `/tmp/` findings file)
- Completed phases as **READ-ONLY CONTEXT** (for reference only)
- The parsed state file path

### Verify-before-fix (mandatory)

Before touching any phase text, the refiner must **attempt to reproduce
the cited evidence for each finding**. The reviewer/DA produce hypotheses;
the refiner is the gate that tests them against reality. This is not
optional.

For each finding with an empirical claim:
1. Read the `Verification:` line and run its check (Read the file, run
   the grep, check the schema, run the command).
2. Record one of three outcomes in the disposition table:
   - **Verified** — evidence reproduces. Proceed with fix or justification.
   - **Not reproduced** — the cited evidence does not match reality.
     Disposition: **Justified — evidence did not reproduce**. Note what
     was actually found. Do NOT fix based on this finding.
   - **No anchor** — finding is empirical-sounding but lacks a verifiable
     citation. Disposition: **Justified — claim not verifiable as stated**
     unless the refiner can locate a verifiable anchor itself.

Judgment findings (those explicitly marked `Verification: judgment`) skip
step 1 and go straight to fix-or-justify based on merit.

**Why this exists.** Past failure: a devil's advocate claimed a Claude
Code tool's input JSON lacked a `model` field and cited the hook
template as evidence. The hook template was real but irrelevant — the
actual falsifier was the tool's own schema, which did contain the field.
The refiner accepted the claim and pivoted a whole phase's architecture
based on nothing. If the refiner had tried to reproduce the evidence, it
would have discovered the claim was unsupported. Verify-before-fix turns
"I believe the DA" into "I checked."

### Address every finding

The agent addresses **every finding**. For each finding, it must either:
1. **Fix it** — update the remaining phase text to resolve the issue
2. **Justify** — explain with evidence why it's not actually a problem
   (including the "evidence did not reproduce" and "claim not verifiable"
   cases from the verify-before-fix block)

It may NOT ignore findings or defer them. Every finding gets a disposition.

The disposition table (written to the refined output) must include an
**Evidence** column with the outcome: `Verified`, `Not reproduced`,
`No anchor`, or `Judgment` (for non-empirical findings).

**Completed phases are NEVER modified.** The refiner operates only on
remaining phase text. If a finding suggests a completed phase has a
problem, the refiner notes it in the Plan Review section as a known
issue — it does not touch the completed phase.

Output is the updated remaining phases only. Write the refined text to
`/tmp/refine-plan-refined-round-N-<slug>.md` for persistence.

## Phase 4 — Convergence Check

After each round of review + refinement:

1. **Count substantive issues** — how many findings from the reviewer and
   devil's advocate were real problems (fixed by the refiner), not false
   positives (justified by the refiner)?

2. **Check convergence:**
   - **0 substantive issues** -> converged. Proceed to Phase 5.
   - **Substantive issues remain AND rounds < max** -> back to Phase 2
     with the refined draft as the new input.
   - **Max rounds reached** -> proceed to Phase 5 with a
     "remaining concerns" note listing unresolved issues.

3. **Track round history** — record each round's finding counts and
   resolutions. This goes into the Plan Review section in Phase 5.

## Phase 5 — Write Updated Plan

Reassemble the plan file by concatenating in order:

1. **Original YAML frontmatter** (unchanged, byte-for-byte)
2. **Original title + Overview section** (unchanged, byte-for-byte)
3. **Progress Tracker table** (unchanged, byte-for-byte)
4. **Completed phases** (unchanged, byte-for-byte — verified by comparing
   checksums from Phase 1 against the sections about to be written. If
   any checksum differs, **STOP** and report the mismatch. Do not write
   a file with modified completed phases.)
5. **Refined remaining phases** (from the last refinement round)

Write the reassembled plan **in place** to the original plan file path.
Do NOT write to a new path.

### Drift Log

Append a `## Drift Log` section after the last phase. This documents
where completed phases diverged from the plan-as-originally-written.
It is a **historical record for future readers** — it does NOT modify
completed phases.

To identify drift:

1. Run `git log --follow --stat <plan-file>` to find all commits that
   touched the plan (summary only, avoids context overflow). Use `--all`
   to search across all refs, including worktree branches where the
   original version may only exist.

2. Run `git show <earliest-reachable-commit>:<plan-file>` to retrieve
   the original version of the plan.

3. **Compare structurally** — not raw diffs. Compare:
   - Phase headings (added, removed, renamed)
   - Phase count (original vs current)
   - Work item counts per phase (original vs current)
   - Any phases that were split or merged

4. If only one commit exists for the file (no prior version), note:
   "No prior version available — drift log based on current state only."

5. Graceful fallback: if `git log` or `git show` fails (e.g., plan was
   created outside git, or the repo has no history), note the failure
   and produce a drift log based on internal evidence only (e.g.,
   completed phases whose work items don't match their acceptance
   criteria).

Format as a table:

```markdown
## Drift Log

Structural comparison of the plan as originally drafted vs current state.

| Phase | Planned | Actual | Delta |
|-------|---------|--------|-------|
| 1 — Setup | 4 work items | 6 work items | +2 items (auth added during impl) |
| 2 — Core | 3 components | 3 components | No drift |
| 3 — UI | "Dark mode toggle" | "Theme system" | Scope expanded |
```

### Plan Review

Append a `## Plan Review` section after the Drift Log. Document:

```markdown
## Plan Review

**Refinement process:** /refine-plan with N rounds of adversarial review
**Convergence:** [Converged at round M / Max rounds reached]
**Remaining concerns:** [None / List of unresolved issues]

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Substantive | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1     | 5 issues          | 4 issues                  | 7           | 7/7      |
| 2     | 1 issue           | 0 issues                  | 0           | Converged|
```

### Post-write tracking

After writing the updated plan file, create the finalize step marker and
update the fulfillment file to complete:
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
printf 'completed: %s\n' "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/step.refine-plan.$TRACKING_ID.finalize"

printf 'skill: refine-plan\nid: %s\nplan: %s\nstatus: complete\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$(TZ=America/New_York date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/fulfilled.refine-plan.$TRACKING_ID"
```

### Present the result

> Plan refined in N rounds (converged / max rounds reached).
> [Remaining concerns if any]
>
> Updated in place: `<plan-file>`
> Drift Log and Plan Review appended.
>
> Continue execution with: `/run-plan <plan-file>`

## Key Rules

- **NEVER modify completed phases.** They are immutable context — shipped
  work that cannot be changed by a plan refiner. Immutability is verified
  mechanically via checksums. Not even heading typo fixes.
- **NEVER rewrite from scratch.** Only refine remaining phases. The plan's
  structure, frontmatter, overview, progress tracker, and completed phases
  are preserved byte-for-byte.
- **Every finding must be addressed.** The refiner cannot ignore or defer
  reviewer/devil's-advocate findings. Fix it or justify why it's not a
  problem — with evidence.
- **Verify findings before baking fixes.** Reviewer and DA findings are
  hypotheses, not mandates. The refiner must reproduce each empirical
  claim before acting on it. A plausible-sounding claim with no
  verifiable anchor — or one whose evidence doesn't reproduce — is not a
  mandate to fix. It's a signal to scrutinize harder. Devil's advocate
  findings are *especially* prone to confidently-false empirical claims
  because the role incentivizes plausibility, not truth.
- **Convergence means no new substantive issues.** Not "the same issues
  rephrased." If the devil's advocate keeps finding real new problems, the
  plan isn't ready.
- **Write parsed state AND findings to /tmp/ files.** Context compaction
  will degrade in-memory state across multiple rounds. The `/tmp/` files
  persist through all phases. Read them if context is lost.
- **Plan file updated IN PLACE.** Do not write to a new path. The original
  path is the canonical location.
- **Ultrathink throughout.** Every agent in the process should use careful,
  thorough reasoning. Read completed phases carefully to understand what
  was actually built.
- **Ground in reality before reviewing.** The six dimensions work only
  if grounded in what actually exists. Shallow review of plan text alone
  — without reading the codebase, completed phases' real output, or
  recent external changes — applies the dimensions to an incomplete
  mental model and misses defects. This is the class of failure
  `/refine-plan` exists to prevent. The Phase 2 "Establishing current
  reality" preamble is mandatory, not advisory.
- **Default 2 rounds.** Lighter than `/draft-plan`'s 3 because this is a
  refinement pass on an existing plan, not blank-slate creation.

## Edge Cases

- **Plan with no remaining phases** — all phases are completed. Exit
  cleanly: "All phases complete — nothing to refine. Run with a plan that
  has remaining phases."
- **Plan with no completed phases** — review all phases. This is
  effectively a lighter `/draft-plan` review pass (2 rounds default vs 3).
  Still generate a Drift Log showing "No completed phases — all phases
  reviewed as remaining."
- **Plan file doesn't exist** — error: "Plan file `<path>` not found."
- **Plan file has no Progress Tracker** — attempt to infer status from
  phase section content (e.g., `[x]` checkboxes in work items, commit
  hashes in notes). If unable to infer, error: "No Progress Tracker found
  in `<path>`. Add a Progress Tracker table with phase status columns so
  the refiner can distinguish completed from remaining phases."
- **Plan mid-execution by another agent** — warn: "This plan may be
  actively executing. Refinement is advisory — changes will be written to
  the plan file but will not affect in-flight phase execution." Proceed
  with the review.
- **Plan has sub-phases (3a/3b)** — treat each sub-phase independently
  for completed/remaining classification. Sub-phase `3a` can be completed
  while `3b` is remaining.
- **Round findings file already exists from prior invocation** — overwrite,
  not append. Each invocation produces fresh findings.
