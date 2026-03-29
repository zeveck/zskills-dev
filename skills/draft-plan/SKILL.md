---
name: draft-plan
disable-model-invocation: false
argument-hint: "[output FILE] [rounds N] <description...>"
description: >-
  Draft a high-quality plan through iterative adversarial review. Multiple
  rounds of research, drafting, review, devil's advocate, and refinement
  until the plan converges. Output is a plan file ready for /run-plan.
  Usage: /draft-plan [output FILE] [rounds N] <description...>
---

# /draft-plan [output FILE] [rounds N] \<description...> — Adversarial Plan Drafter

Produces high-quality plan documents through iterative adversarial
refinement. Multiple agents research, draft, review, poke holes, and refine
until the plan is solid enough to execute with `/run-plan`.

The insight: `/run-plan` executes a plan faithfully — so plan quality IS
output quality. Investing in adversarial plan refinement pays off massively
downstream. A weak plan executed perfectly is still a weak result.

**Ultrathink throughout.**

## Arguments

```
/draft-plan [output FILE] [rounds N] <description...>
```

- **output FILE** (optional) — where to write the plan. Default:
  `plans/<slug-from-description>.md`
- **rounds N** (optional) — max review/refine cycles. Default: 3. The
  process exits early if a round converges (no substantive new issues).
- **description** (required) — everything after the recognized keywords.
  Can be brief ("add dark mode") or detailed ("implement thermal domain
  with conduction, convection, radiation, and multi-domain coupling to
  electrical via Joule heating").

**Detection:** scan `$ARGUMENTS` from the start for recognized patterns:
- `output` followed by a path — explicit output file
- The **first token** ending in `.md` — output file (only when it's the
  first argument, before the description starts). This avoids false
  positives on description words like `README.md` or `CLAUDE.md`.
  If the token contains `/`, use as-is; otherwise prepend `plans/`.
- `rounds` followed by a number — max review cycles
- Everything else (from the first unrecognized non-flag token onward) is
  the description

Examples:
- `/draft-plan Add dark mode to the editor`
- `/draft-plan THERMAL_PLAN.md Implement thermal domain` → writes `plans/THERMAL_PLAN.md`
- `/draft-plan plans/THERMAL_PLAN.md Implement thermal domain` → same
- `/draft-plan output plans/THERMAL_PLAN.md rounds 5 Implement thermal domain`
- `/draft-plan rounds 5 Implement thermal domain with multi-domain coupling`
- `/draft-plan Fix the README.md formatting` → description only, no output file detected

## Pre-check — Existing file

If the output file already exists, read it first. The old plan IS research
input — it contains the original intent, structure, and possibly partial
progress. Tell the research agents: "An existing plan file exists at
`<path>`. Read it and incorporate its intent. This is a modernization,
not a blank-slate rewrite." The adversarial review should check that no
intent from the original was lost.

This handles the common case of modernizing old-format plans:
`/draft-plan plans/OLD_PLAN.md Modernize with progress tracker and phases`

## Phase 1 — Research (parallel agents)

Dispatch multiple Explore agents in parallel to investigate the problem space.
Each agent gets the full description and a specific research focus:

1. **Codebase agent** — find all relevant source files, understand current
   architecture, identify what exists and what needs to change. Map
   dependencies, shared infrastructure, and potential conflicts.

2. **Patterns agent** — read existing plans in `plans/` for format and style
   reference. Read `CLAUDE.md` for constraints (no external solvers, no
   bundlers, etc.). Identify conventions and rules that the plan must respect.

3. **Domain agent** — research the specific technical domain. For solver
   work: understand the math, numerical methods, stability requirements.
   For UI work: understand the interaction model, accessibility, existing
   patterns. For infrastructure: understand the deployment, CI, hosting.

4. **Prior art agent** — check git history for related work, previous
   attempts, known issues. Read any existing plan files or progress docs
   that overlap with the description. Find relevant GitHub issues.

**Consolidate** the research into a single summary and **write it to a file**
(e.g., `/tmp/draft-plan-research-<slug>.md`). The `<slug>` comes from the
output filename if one was provided (e.g., `FEATURE_EXPORT`
→ `/tmp/draft-plan-research-FEATURE_EXPORT.md`). If no output
file was given, derive from the description. Do not rely on keeping the
research in memory — context compaction will degrade it across multiple
rounds of adversarial review. The file persists through all phases.

The summary should cover:
- What exists today (relevant code, architecture)
- What needs to change or be built
- Constraints and rules that apply
- Prior art and lessons learned
- Open questions or uncertainties

**Similarly, write each round's review findings to files:**
- `/tmp/draft-plan-review-round-N.md` — reviewer + devil's advocate findings
- Pass these file paths to the refiner agent so it has the full context

**Scope check — is this too big for one plan?** After consolidating
research, assess whether you can write a plan where every phase has
specific, implementable work items and testable acceptance criteria,
in roughly 6 or fewer phases. The question is not "can I list phases"
but "can I spec each phase precisely enough that an implementing agent
won't have to guess?"

Signs the task is too big for one plan:
- You'd need 8+ phases to cover the scope properly
- Phases would be vague ("implement thermal domain") because the breadth
  prevents precise specs for each one
- The task contains 2+ sub-problems that share no files or infrastructure
- You find yourself thinking "Phase 4 will probably need to be broken
  into sub-phases at implementation time"

Past failure: a Dashboard Blocks plan covered too much — phases were
vague, the implementing agent took shortcuts, and each phase had to be
broken into 5-10 sub-phases at execution time with no adversarial review.

Common pattern: tasks that add multiple block types alongside new engine
infrastructure (new solver, new domain, new codegen path) should
decompose into infrastructure-first plan + block additions via
`/add-block` delegate phases after the engine lands.

If the task is too big, present this to the user:
> This task is too broad for one well-specified plan. It decomposes
> into N sub-problems: [list them with one-line descriptions].
> I recommend using `/research-and-plan` to handle the decomposition
> and draft focused sub-plans for each. Proceed?

On approval, invoke `/research-and-plan` with:
- The original description (full, unmodified)
- The research file path (`/tmp/draft-plan-research-<slug>.md`)
Then **exit** — do not proceed to Phase 2. `/research-and-plan` takes
over from here.

If the user says no (e.g., "just plan the first part"), narrow the scope
per their feedback and proceed to Phase 2 with the focused scope.

**Present the research summary to the user.** If running interactively
(user invoked `/draft-plan` directly), wait for input:
> Research complete. Summary written to `/tmp/draft-plan-research-<slug>.md`.
> Here's the overview: [brief summary]
> [Scope check result — either "this fits in one plan" or the decomposition recommendation above]
>
> Anything to add, correct, or steer before I draft the plan?

Incorporate any user feedback, then **immediately proceed to Phase 2.**
Do not stop here. The checkpoint is a pause for steering, not the end of
the skill. After the user responds (even if they just say "looks good" or
"continue"), move to Phase 2 without being asked again.

**If running as a subagent** (dispatched by `/research-and-plan` or
`/research-and-go`), skip the user checkpoint — proceed directly to
Phase 2. The decomposition was already approved by the user in the
parent skill.

## Phase 2 — Draft

A single agent produces the initial plan based on the consolidated research
and user feedback. The plan MUST follow a format that `/run-plan` can
consume:

### Required plan structure

```markdown
# Plan: <Title>

## Overview
Brief description of what this plan accomplishes and why.

## Progress Tracker
| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — <name> | ⬚ | | |
| 2 — <name> | ⬚ | | |
| ...         | ⬚ | | |

## Phase 1 — <Name>

### Goal
One-sentence summary of what this phase accomplishes.

### Work Items
- [ ] Item 1 — specific, implementable description
- [ ] Item 2 — ...

### Design & Constraints
Verbatim specs: formulas, state equations, algorithms, data structures,
API contracts. Everything an implementing agent needs to write the code
without guessing. If there are formulas, write the formulas. If there are
constraints, state them explicitly.

### Acceptance Criteria
- [ ] Criterion 1 — specific, testable condition
- [ ] Criterion 2 — e.g., "test free vibration x(t) = A cos(ωt) within 1e-6"

### Dependencies
Which phases must be complete before this one can start.

## Phase 2 — <Name>
...
```

### Drafting rules

- **Be specific, not vague.** "Implement the Spring component using F = -kx
  with internal displacement state" — not "implement springs."
- **Include formulas and algorithms verbatim.** The implementing agent will
  have ONLY the plan text. If the formula isn't in the plan, the agent will
  guess it wrong.
- **Acceptance criteria must be testable.** "Works correctly" is not testable.
  "Test produces output matching analytical solution within 1e-6 tolerance"
  is testable.
- **Phase boundaries at natural breaks.** Each phase should be independently
  implementable and verifiable. Don't put shared infrastructure in Phase 3
  if Phases 1 and 2 need it.
- **Size phases for agent execution.** Each phase should be completable by
  one agent in under 2 hours: implement, test, verify, commit. Scope by
  concrete units (components, files, features) — NOT by time estimates.
  A phase with ~3-5 components and ~500 lines of new code is right. A
  phase with 15 components or 2000+ lines should be split. Do NOT use
  time estimates ("this will take 2 weeks") — LLMs cannot estimate time.
  Use scope: number of components, files touched, test count.
- **Estimate scope honestly.** If a phase has 7 components, list all 7. Don't
  say "implement key components" and hope the agent picks the right ones.
- **Dependencies must be explicit.** If Phase 3 needs the base class from
  Phase 1, say so.

## Phase 3 — Adversarial Review (parallel)

Dispatch two agents simultaneously against the current draft. Each gets the
full draft AND the research summary from Phase 1.

### Reviewer agent

Checks for completeness, correctness, and feasibility:

- Are all work items specific enough to implement without guessing?
- Do acceptance criteria cover every work item?
- Are dependencies correct and complete?
- Is the phase ordering optimal? (shared infrastructure first?)
- Are there missing phases? (tests? documentation? integration?)
- Is the scope realistic per phase? (1000+ lines each is the norm)
- Does the plan respect all constraints from CLAUDE.md and research?
- Are formulas and algorithms correct?
- Will `/run-plan` be able to parse phases and status from this format?

### Devil's advocate agent

Genuinely adversarial — tries to find ways the plan will fail:

- **Wrong assumptions** — what does the plan assume that might not be true?
  ("Assumes the solver handles stiff systems" — does it actually?)
- **Missing edge cases** — what will break at implementation time that the
  plan doesn't address? ("What happens when the spring constant is zero?")
- **Deferred hard parts** — are the difficult items buried in later phases
  or hidden behind vague language? ("Phase 4: integrate everything" — that's
  where all the complexity is.)
- **Hidden dependencies** — does Phase 3 actually need something from Phase 2
  that isn't listed as a dependency?
- **Overly optimistic scope** — is "implement 7 components" in one phase
  actually feasible? Should it be split?
- **Specification gaps** — "when an agent tries to implement Phase 2b using
  ONLY the text in this plan, what will go wrong? What will it have to guess?"
- **Integration risks** — will phases that work in isolation break when
  combined? What integration testing is missing?
- **Constraint violations** — does any phase implicitly require an external
  library, a build step, or something else CLAUDE.md prohibits?

The devil's advocate must produce **specific, actionable findings** — not
generic concerns. "Phase 3 might be complex" is useless. "Phase 3 says
'implement the DAE solver' but doesn't specify the index reduction method,
matrix factorization approach, or convergence criteria — the agent will have
to guess all three" is actionable.

## Phase 4 — Refine

A single agent receives:
- The current draft
- The reviewer's findings
- The devil's advocate's findings

It produces an improved draft that **addresses every finding**. For each
finding, it must either:
1. **Fix it** — update the plan to resolve the issue
2. **Justify** — explain why it's not actually a problem (with evidence)

It may NOT ignore findings or defer them. The refiner's output is the new
draft for the next round.

## Phase 5 — Convergence Check

After each round of review + refinement:

1. **Count substantive issues** — how many findings from the reviewer and
   devil's advocate were real problems (not false positives)?

2. **Check convergence:**
   - **0 substantive issues** → converged. Proceed to Phase 6.
   - **Substantive issues remain AND rounds < max** → back to Phase 3
     with the refined draft.
   - **Max rounds reached** → proceed to Phase 6 with a "remaining
     concerns" section noting unresolved issues.

3. **Track round history** — keep a log of each round's findings and
   resolutions. This goes into the final plan's quality section.

## Phase 6 — Finalize

1. **Add a Plan Quality section** to the end of the plan:

   ```markdown
   ## Plan Quality

   **Drafting process:** /draft-plan with N rounds of adversarial review
   **Convergence:** [Converged at round M / Max rounds reached]
   **Remaining concerns:** [None / List of unresolved issues]

   ### Round History
   | Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
   |-------|-------------------|---------------------------|----------|
   | 1     | 5 issues          | 7 issues                  | 12/12    |
   | 2     | 2 issues          | 3 issues                  | 5/5      |
   | 3     | 0 issues          | 0 issues                  | Converged|
   ```

2. **Write the plan file** to the output path. The user can't review what
   they can't read — plans are often too large to meaningfully summarize
   in chat. Write first, then let the user read the actual file.

3. **Update the plan index:**
   - If `plans/PLAN_INDEX.md` exists, add a row to the "Ready to Run" table
     with the new plan's filename (as a relative link), phase count, first
     phase name, priority `Medium`, and a one-line note from the overview.
   - If `plans/PLAN_INDEX.md` does not exist, include in the report:
     > Run `/plans rebuild` to generate a plan index.

4. **Present the result:**
   > Plan drafted in N rounds (converged / max rounds reached).
   > [Remaining concerns if any]
   >
   > Written to `plans/THERMAL_PLAN.md` — open it up and let me know
   > what to change.
   >
   > Execute with: `/run-plan plans/THERMAL_PLAN.md`
   > Or with scheduling: `/run-plan plans/THERMAL_PLAN.md auto every 4h now`

## Key Rules

- **The plan is the spec.** Every implementing agent will have ONLY the plan
  text. If it's not in the plan, it doesn't exist. Write formulas, not
  descriptions of formulas. Write acceptance criteria, not hopes.
- **Devil's advocate must be genuinely adversarial.** Not a rubber stamp.
  The goal is to find real problems before `/run-plan` hits them at
  implementation time. A comfortable review is a useless review.
- **Every finding must be addressed.** The refiner cannot ignore or defer
  reviewer/devil's-advocate findings. Fix it or justify why it's not a
  problem.
- **Convergence means no new substantive issues.** Not "the same issues
  rephrased." If the devil's advocate keeps finding real new problems, the
  plan isn't ready.
- **Respect constraints.** The plan must not require anything CLAUDE.md
  prohibits: no external solvers, no bundlers, no external dependencies
  without approval.
- **Phase boundaries at natural breaks.** Each phase must be independently
  implementable and verifiable by `/run-plan`.
- **Progress tracker is mandatory.** `/run-plan` needs it to track status.
  Start all phases as `⬚` (not started).
- **Ultrathink throughout.** Every agent in the process should use careful,
  thorough reasoning.

## Edge Cases

- **Description is very brief** ("add dark mode") — the research phase does
  the heavy lifting, exploring what "dark mode" means for this codebase
- **Description is very detailed** (multi-paragraph brief) — research agents
  validate and expand rather than starting from scratch
- **Plan converges in round 1** — great, write it. Don't force unnecessary
  rounds.
- **Plan doesn't converge after max rounds** — write it with the "remaining
  concerns" section. The user decides whether to proceed or refine further.
- **User adds context after research** — incorporate it into the draft.
  Don't ignore user input.
- **Output file already exists** — warn the user, ask before overwriting
- **Plan is too large for one file** — suggest splitting into multiple plan
  files, one per major phase group
