# Factsheet — `docs/skills/draft-plan.md`

Each row pairs a sentence (or claim) in the rewritten doc with the source line in
`skills/draft-plan/SKILL.md` that backs it. Quotes are verbatim from the cited line.

---

## Blockquote summary

- **Doc:** "Draft a high-quality plan through iterative adversarial review: research, draft, review, devil's-advocate, refine -- repeated until convergence. Output is a plan file ready for `/run-plan` execution."
  - `skills/draft-plan/SKILL.md:6`: `  Draft a high-quality plan through iterative adversarial review:`
  - `skills/draft-plan/SKILL.md:7`: `  research, draft, review, devil's-advocate, refine — repeated until`
  - `skills/draft-plan/SKILL.md:8`: `  convergence. Output is a plan file ready for /run-plan execution.`

## What it does

- **Doc:** "`/draft-plan` turns a description of work into a written plan file you can execute with `/run-plan`."
  - `skills/draft-plan/SKILL.md:17`: `until the plan is solid enough to execute with \`/run-plan\`.`

- **Doc:** "one pass researches the problem, another writes a first draft, and then reviewers and a deliberately adversarial 'devil's advocate' poke holes in it while a refiner addresses every finding."
  - `skills/draft-plan/SKILL.md:16`: `refinement. Multiple agents research, draft, review, poke holes, and refine`
  - `skills/draft-plan/SKILL.md:680`: `Genuinely adversarial — tries to find ways the plan will fail:`

- **Doc:** "This review-and-refine cycle repeats until the plan stops accumulating substantive problems (or hits the round budget you set)."
  - `skills/draft-plan/SKILL.md:793`: `   - **>0 substantive issues AND rounds < max** → another review+refine cycle. Honor the user's rounds budget; don't stop early.`
  - `skills/draft-plan/SKILL.md:794`: `   - **Only short-circuit before max rounds when remaining substantive issues are genuinely 0.**`

- **Doc:** "`/run-plan` executes a plan faithfully, so the quality of the plan is the quality of the result -- a weak plan executed perfectly is still a weak result."
  - `skills/draft-plan/SKILL.md:19`: `The insight: \`/run-plan\` executes a plan faithfully — so plan quality IS`
  - `skills/draft-plan/SKILL.md:21`: `downstream. A weak plan executed perfectly is still a weak result.`

- **Doc:** "an overview, a progress tracker, and numbered phases, each with goals, specific work items, design and constraints, and testable acceptance criteria."
  - `skills/draft-plan/SKILL.md:590`: `Brief description of what this plan accomplishes and why.` (Overview)
  - `skills/draft-plan/SKILL.md:592`: `## Progress Tracker`
  - `skills/draft-plan/SKILL.md:599`: `## Phase 1 — <Name>`
  - `skills/draft-plan/SKILL.md:601`: `### Goal`
  - `skills/draft-plan/SKILL.md:604`: `### Work Items`
  - `skills/draft-plan/SKILL.md:614`: `### Acceptance Criteria`

- **Doc:** "The file ends with a 'Plan Quality' section recording how many rounds ran, whether the plan converged, and any concerns left unresolved."
  - `skills/draft-plan/SKILL.md:801`: `1. **Add a Plan Quality section** to the end of the plan:`
  - `skills/draft-plan/SKILL.md:806`: `   **Drafting process:** /draft-plan with N rounds of adversarial review`
  - `skills/draft-plan/SKILL.md:807`: `   **Convergence:** [Converged at round M / Max rounds reached]`
  - `skills/draft-plan/SKILL.md:808`: `   **Remaining concerns:** [None / List of unresolved issues]`

- **Doc:** "When run on a repository that protects its main branch, `/draft-plan` does its work in an isolated worktree and commits the finished plan there on a feature branch, rather than leaving it as a loose file."
  - `skills/draft-plan/SKILL.md:832`: `3. **Auto-commit the plan file (if in a worktree).** When \`$TOPLEVEL\` is`
  - `skills/draft-plan/SKILL.md:833`: `   a worktree (not main), stage and commit \`$OUTPUT_FILE\` so the plan is`
  - `skills/draft-plan/SKILL.md:834`: `   captured on the feature branch rather than left as a dirty file in`
  - (worktree-when-protected: `skills/draft-plan/SKILL.md:914`: `   projects with \`execution.landing: pr\` + \`main_protected: true\`, the`)

- **Doc:** "If you pass `auto`, it then opens a pull request for the plan and merges it once checks pass; without `auto`, the commit stays on the branch and you land it yourself."
  - `skills/draft-plan/SKILL.md:917`: `   positional token, dispatch \`/land-pr\` so the branch pushes, a PR` (continues "opens, CI runs, and auto-merge lands the plan on main" on next lines)
  - `skills/draft-plan/SKILL.md:920`: `   to end. Without \`auto\`, the worktree commit stands and the caller`
  - `skills/draft-plan/SKILL.md:921`: `   lands manually.`

- **Doc:** "If the research turns up a task too broad to spec well in one plan -- too many phases, or sub-problems that share nothing -- `/draft-plan` will say so and recommend `/research-and-plan` to decompose it into focused sub-plans instead."
  - `skills/draft-plan/SKILL.md:417`: `- You'd need 8+ phases to cover the scope properly`
  - `skills/draft-plan/SKILL.md:434`: `> This task is too broad for one well-specified plan. It decomposes`
  - `skills/draft-plan/SKILL.md:436`: `> I recommend using \`/research-and-plan\` to handle the decomposition`
  - `skills/draft-plan/SKILL.md:437`: `> and draft focused sub-plans for each. Proceed?`

## Typical usage

- **Doc:** example `/draft-plan Add dark mode support to the editor` (single-sentence description).
  - `skills/draft-plan/SKILL.md:128`: `- **description** (required) — everything after the recognized keywords.`
  - `skills/draft-plan/SKILL.md:251` (in source): `- \`/draft-plan Add dark mode to the editor\`` (Examples block; doc paraphrases)

- **Doc:** "You can name the output file (otherwise the path is derived from the description), and you can raise the number of review rounds when the design is hairy."
  - `skills/draft-plan/SKILL.md:119`: `- **output FILE** (optional) — where to write the plan. Default:`
  - `skills/draft-plan/SKILL.md:121`: `- **rounds N** (optional) — max review/refine cycles. Default: 3. The`

- **Doc:** example `/draft-plan plans/THERMAL_PLAN.md auto Implement the thermal domain` (path + auto + chaining into execution).
  - `skills/draft-plan/SKILL.md:252`: `- \`/draft-plan THERMAL_PLAN.md Implement thermal domain\` → writes \`$ZSKILLS_PLANS_DIR/THERMAL_PLAN.md\``
  - `skills/draft-plan/SKILL.md:919`: `   \`/draft-plan plans/X.md auto && /run-plan plans/X.md auto\` work end` (the draft-then-run chaining)

- **Doc:** "`brainstorm` for co-designing a fuzzy idea, or `quiz` for a requirements interview" with examples `/draft-plan brainstorm Add a settings panel` and `/draft-plan quiz Add dark mode support`.
  - `skills/draft-plan/SKILL.md:149`: `  \`brainstorm\` loads the interactive brainstorm dialogue`
  - `skills/draft-plan/SKILL.md:151`: `  requirements interview before drafting by loading (\`references/quiz.md\`).`
  - `skills/draft-plan/SKILL.md:257`: `- \`/draft-plan brainstorm Add dark mode to the editor\` → \`STEERING_MODE=brainstorm\` (leading flag) — runs the interactive brainstorm dialogue first`
  - `skills/draft-plan/SKILL.md:258`: `- \`/draft-plan quiz Add dark mode to the editor\` → \`STEERING_MODE=quiz\` (leading flag) — runs the interactive requirements interview first`

## Companion skills

(All companion edges drawn from `COMPANIONS.md` row `draft-plan`; cross-checked against source.)

- **Doc:** "`/run-plan` is the next step. ... They are sequential, not alternatives."
  - `COMPANIONS.md:53-54`: "`/draft-plan` → `/run-plan` are sequential, not alternatives"
  - `skills/draft-plan/SKILL.md:17`: `until the plan is solid enough to execute with \`/run-plan\`.`

- **Doc:** "`/refine-plan` adjusts a plan that is already mid-execution when reality has drifted."
  - `COMPANIONS.md:81`: "`/refine-plan` adjusts it mid-flight"
  - `COMPANIONS.md:91`: "Adjusts an in-flight plan; sits between `/draft-plan` and `/run-plan`"

- **Doc:** "`/draft-tests` is the test-spec sibling of the plan-authoring family."
  - `COMPANIONS.md:82`: "Test-spec authoring sibling of the plan-authoring family."

- **Doc:** "`/research-and-plan` ... when a goal is broad enough to decompose into several sub-plans; `/draft-plan` will hand off to it when the task is too big for one plan."
  - `COMPANIONS.md:81`: companions include `research-and-plan`
  - `skills/draft-plan/SKILL.md:436`: `> I recommend using \`/research-and-plan\` to handle the decomposition`

- **Doc:** "`/do` (or `/quickfix`, where the project allows editing main in place) is lighter than drafting a full plan."
  - `COMPANIONS.md:81`: companions include `do`, `quickfix`
  - `COMPANIONS.md:48-52`: "`/quickfix` vs `/do` are PEERS ... `main_protected: true` → `/do`"

## Arguments

- **Doc:** usage line `[output FILE] [rounds N] [auto] [brainstorm|quiz] <description...>`
  - `skills/draft-plan/SKILL.md:116`: `/draft-plan [output FILE] [rounds N] [auto] [brainstorm|quiz] <description...>`

- **Doc:** "`description` (Yes) ... Can be brief ('add dark mode') or a detailed multi-paragraph brief. Everything after the recognized leading flags is the description."
  - `skills/draft-plan/SKILL.md:128`: `- **description** (required) — everything after the recognized keywords.`
  - `skills/draft-plan/SKILL.md:129`: `  Can be brief ("add dark mode") or detailed ("implement thermal domain`

- **Doc:** "`output FILE` (No) ... Defaults to a path derived from the description. May be given as `output <path>` or as a bare leading `*.md` token before the description begins."
  - `skills/draft-plan/SKILL.md:119`: `- **output FILE** (optional) — where to write the plan. Default:`
  - `skills/draft-plan/SKILL.md:120`: `  \`$ZSKILLS_PLANS_DIR/<slug-from-description>.md\``
  - `skills/draft-plan/SKILL.md:146`: `  recognized **ONLY as a leading flag token** — in the flag cluster before` (leading-cluster recognition incl. output/.md token)

- **Doc:** "`rounds N` (No) ... Defaults to 3. The process stops early if a round converges with no substantive new issues."
  - `skills/draft-plan/SKILL.md:121`: `- **rounds N** (optional) — max review/refine cycles. Default: 3. The`
  - `skills/draft-plan/SKILL.md:122`: `  process exits early if a round converges (no substantive new issues).`

- **Doc:** "`auto` (No) ... open a pull request, run checks, and merge it. Without `auto`, the plan is committed on the feature branch and you land it manually. Recognized anywhere in the arguments."
  - `skills/draft-plan/SKILL.md:123`: `- **auto** (optional positional token) — after the worktree auto-commit`
  - `skills/draft-plan/SKILL.md:124`: `  succeeds in Phase 6, dispatch \`/land-pr\` to push the branch, open a PR,`
  - `skills/draft-plan/SKILL.md:125`: `  monitor CI, and auto-merge. Without \`auto\`, the plan is committed in the`
  - `skills/draft-plan/SKILL.md:126`: `  worktree but no PR is opened — caller must land manually. Mirrors the`
  - (recognized-anywhere: `skills/draft-plan/SKILL.md:143`: `- \`auto\` (whitespace-anchored, case-insensitive) — sets \`AUTO_FLAG=1\``; regex at lines 168-170 matches anywhere)

- **Doc:** "`brainstorm` (No) ... Recognized only as a leading flag, before the description begins."
  - `skills/draft-plan/SKILL.md:149`: `  \`brainstorm\` loads the interactive brainstorm dialogue`
  - `skills/draft-plan/SKILL.md:146`: `  recognized **ONLY as a leading flag token** — in the flag cluster before`
  - `skills/draft-plan/SKILL.md:260`: `- \`/draft-plan output p.md brainstorm Add dark mode\` → \`STEERING_MODE=brainstorm\` (brainstorm is in the leading flag cluster — composability parity with quiz; #944 — no longer token[0]-only)`

- **Doc:** "`quiz` (No) ... Recognized only as a leading flag, before the description begins."
  - `skills/draft-plan/SKILL.md:150`: `  (\`references/brainstorm.md\`) before Phase 1; \`quiz\` conducts an interactive`
  - `skills/draft-plan/SKILL.md:151`: `  requirements interview before drafting by loading (\`references/quiz.md\`).`
  - `skills/draft-plan/SKILL.md:146`: `  recognized **ONLY as a leading flag token** — in the flag cluster before`

- **Doc:** "`brainstorm` and `quiz` are mutually exclusive -- ... asking for both at once is an error rather than a silent drop of one."
  - `skills/draft-plan/SKILL.md:153`: `  so they are **mutually exclusive** — requesting both (in either order,`
  - `skills/draft-plan/SKILL.md:191`: `\`brainstorm\` and \`quiz\` are **mutually exclusive** — both are pre-draft`
  - `skills/draft-plan/SKILL.md:264`: `- \`/draft-plan brainstorm quiz Add dark mode\` → **ERROR (exit 2)** — both \`brainstorm\` and \`quiz\` are leading-cluster flags and the two modes are mutually exclusive (#936, #944). Fails loud instead of silently dropping one.`

- **Doc:** "a description word like 'build a quiz app' does not trigger either mode; to enable a mode you must lead with the flag, not append it."
  - `skills/draft-plan/SKILL.md:261`: `- \`/draft-plan output p.md build a quiz app\` → \`STEERING_MODE\` empty — "quiz" is a description word, not the leading flag (NEGATIVE example; the selector is leading-only, never match-anywhere like \`auto\`)`
  - `skills/draft-plan/SKILL.md:263`: `- \`/draft-plan add dark mode quiz\` → \`STEERING_MODE\` empty — a **trailing** \`quiz\` is description text, not the flag. This is the accepted ergonomic limitation of leading-only parsing: to enable a mode, lead with the flag (\`/draft-plan quiz add dark mode\`).`

- **Doc:** "`auto` mirrors the same token in `/run-plan`, `/do`, `/fix-issues`, and `/quickfix`. It controls only whether the plan lands automatically -- it does not skip the review rounds or the brainstorm/quiz dialogue."
  - `skills/draft-plan/SKILL.md:127`: `  \`auto\` token in \`/run-plan\`, \`/do\`, \`/fix-issues\`, \`/quickfix\`.`
  - (does-not-skip review: review rounds at Phase 3-5 run regardless of `AUTO_FLAG`; `AUTO_FLAG` is only read in Phase 6 at `skills/draft-plan/SKILL.md:924`: `   if [ "${AUTO_FLAG:-0}" = "1" ] && [ "$TOPLEVEL" != "$MAIN_ROOT" ]; then`)

## Examples block

- All example lines are drawn from the source Examples block (`skills/draft-plan/SKILL.md:250-265`) and the Common-patterns equivalents. Specific negative examples:
  - `/draft-plan output p.md build a quiz app` → `skills/draft-plan/SKILL.md:261`
  - `/draft-plan add dark mode quiz` → `skills/draft-plan/SKILL.md:263`
  - `/draft-plan output p.md quiz rounds 5 Add dark mode` → `skills/draft-plan/SKILL.md:259`: `- \`/draft-plan output p.md quiz rounds 5 Add dark mode\` → \`STEERING_MODE=quiz\` (quiz is in the leading flag cluster, in any order with \`output\`/\`rounds\`)`

## Tips & Gotchas

- **Doc:** "each phase has clear, testable acceptance criteria."
  - `skills/draft-plan/SKILL.md:614`: `### Acceptance Criteria`
  - `skills/draft-plan/SKILL.md:632` (drafting rule): testable acceptance criteria

- **Doc:** "a comfortable review is a useless one."
  - `skills/draft-plan/SKILL.md:1018`: `   implementation time. A comfortable review is a useless review.`

- **Doc:** "Drafting against an existing plan file modernizes it rather than starting blank -- the old plan's intent is treated as research input, and the review checks that nothing from it was lost."
  - `skills/draft-plan/SKILL.md:269`: `If the output file already exists, read it first. The old plan IS research`
  - `skills/draft-plan/SKILL.md:272`: `\`<path>\`. Read it and incorporate its intent. This is a modernization,`
  - `skills/draft-plan/SKILL.md:273`: `not a blank-slate rewrite." The adversarial review should check that no`

- **Doc:** "If a plan does not converge within the round budget, it is still written, with a 'remaining concerns' section, and you decide whether to proceed or refine further."
  - `skills/draft-plan/SKILL.md:1048`: `- **Plan doesn't converge after max rounds** — write it with the "remaining`
  - `skills/draft-plan/SKILL.md:1049`: `  concerns" section. The user decides whether to proceed or refine further.`

- **Doc:** "If the goal is broad enough to decompose into multiple sub-plans, reach for `/research-and-plan` instead."
  - `skills/draft-plan/SKILL.md:436`: `> I recommend using \`/research-and-plan\` to handle the decomposition`

- **Doc:** "Reserve `/draft-plan` for work with non-trivial design surface ... A single, settled change is lighter as a `/do` or `/quickfix`."
  - `COMPANIONS.md:48-52` (peer routing); CLAUDE.md "Which skill for which input" — `/draft-plan` is "Plan-scale design surface — needs adversarial review before execution"; `/do`/`/quickfix` are one-commit PRs. (Routing fact, sourced from CLAUDE.md / COMPANIONS.md, not a draft-plan SKILL.md line.)

- **Doc:** "Choose between the interview modes by the bottleneck: `brainstorm` when the design surface is fuzzy ... `quiz` when you know roughly what you want but the requirements need to be drawn out precisely."
  - `skills/draft-plan/SKILL.md:149`: `  \`brainstorm\` loads the interactive brainstorm dialogue` (design dialogue)
  - `skills/draft-plan/SKILL.md:151`: `  requirements interview before drafting by loading (\`references/quiz.md\`).` (requirements interview)
  - (the bottleneck framing matches the prior doc's Tips line 89, but its "not mutually exclusive" claim is corrected — see PLAN-TEXT-DRIFT below)

---

## Claims deliberately NOT in the doc (R5 — internals stripped)

These were in the old doc or source but are implementer-voice and omitted:
- `STEERING_MODE`, `AUTO_FLAG`, `QUIZ_FLAG` variable names — banned (subagent/dispatch plumbing voice).
- Round/phase numbers ("Phase 1", "Phase 6"), tracking markers, `$TRACKING_ID`, `/tmp/...` notes-file paths, `collect.py` — internal plumbing (R5 banned list).
- "reviewer + devil's-advocate + refiner sub-agents in parallel", "top-level dispatch" preflight — agent-type / dispatch internals (R5).
- The 8-step brainstorm enumeration and the quiz state-machine bullets from the old doc — internal procedure detail; replaced with one plain sentence each.
- `disable-model-invocation: false` (`skills/draft-plan/SKILL.md:3`) — frontmatter field, banned.
