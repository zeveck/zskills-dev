# /draft-plan

> Draft a high-quality plan through iterative adversarial review: research, draft, review, devil's-advocate, refine -- repeated until convergence. Output is a plan file ready for `/run-plan` execution.

## Usage

```
/draft-plan [output FILE] [rounds N] [auto] [brainstorm] [quiz] <description...>
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `description` | Yes | What the plan should accomplish, in natural language |
| `output FILE` | No | Output path for the plan file (default: auto-derived from description). May appear as `output <path>` or as a bare leading `*.md` token |
| `rounds N` | No | Maximum adversarial review rounds (default: 3) |
| `auto` | No | After the Phase 6 worktree commit, dispatch `/land-pr` to push the branch, open a PR, monitor CI, and auto-merge. Without `auto`, the plan is committed in the worktree and the caller lands manually. Whitespace-anchored, case-insensitive, match-anywhere in `$ARGUMENTS`. |
| `brainstorm` | No | Before Phase 1, load `references/brainstorm.md` and run an 8-step interactive design dialogue that captures decisions/rationale/open questions into a durable `/tmp` notes file, then feeds the notes into the research fan-out. Whitespace-anchored, case-insensitive, match-anywhere -- but anchored so it does **not** match `brainstorming` / `brainstormed` / `brainstorms`. |
| `quiz` | No | Before Phase 1, load `references/quiz.md` and run an interactive Socratic requirements interview that elicits intent, scope, and priorities through conversation, persisting state to a durable `/tmp` file and seeding the deferred research fan-out with the captured requirements. **Leading-flag only** -- recognized only when it appears in the flag cluster before the description begins (like `output` / `rounds`), **not** match-anywhere like `auto` / `brainstorm`. A `quiz` inside the description text is description, not the flag. |

> `brainstorm` and `quiz` are progressive-disclosure references: their bodies are
> conditionally loaded only when the corresponding flag is set, keeping the base
> SKILL.md lean for the common case.

## Examples

```
/draft-plan Add dark mode support to the editor
/draft-plan output plans/DARK_MODE.md Add dark mode support
/draft-plan rounds 5 Redesign the solver architecture
/draft-plan auto Implement undo/redo for the block editor
/draft-plan brainstorm Add a settings panel             # interactive design dialogue first
/draft-plan quiz Add dark mode support                   # interactive requirements interview first
/draft-plan output p.md quiz rounds 5 Add dark mode      # quiz in the leading flag cluster, any order
/draft-plan output p.md build a quiz app                 # QUIZ_FLAG NOT set -- "quiz" is description
/draft-plan add dark mode quiz                           # QUIZ_FLAG NOT set -- trailing quiz is description
```

> `auto` mirrors the same token in `/run-plan`, `/do`, `/fix-issues`, and
> `/quickfix`: it triggers the post-commit `/land-pr` auto-merge dispatch. It
> does **not** skip the planning review rounds or the brainstorm/quiz dialogue.

## Brainstorm mode (`brainstorm`)

Loads [`references/brainstorm.md`](https://github.com/zeveck/zskills/blob/main/skills/draft-plan/references/brainstorm.md) and runs an 8-step interactive dialogue **before Phase 1**:

1. Restate the seed idea in 1-2 sentences.
2. Optionally offer a visual companion (live HTML demo or `playwright-cli` screenshot) when the idea is visual.
3. Ask clarifying questions one at a time -- most fundamental first.
4. Propose 2-3 approaches with trade-offs and an explicit recommendation at each fork.
5. Apply ruthless YAGNI and gentle pushback.
6. Capture decisions, rationale, and rejected alternatives into `/tmp/draft-plan-brainstorm-$TRACKING_ID.md` as they're made.
7. Offer the transition checkpoint when open questions are exhausted.
8. On affirmative confirm, flip the notes file status to `ready` and hand off to Phase 1.

The notes file is a **resumable state machine** -- if compaction interrupts the dialogue, re-entry resumes from `status: in-progress` rather than restarting. The Phase 1 research agents are then seeded with the literal notes-file path as the primary design seed; the Codebase/Patterns/Prior-art agents still run to ground the design against the repo. Demo HTML lives under `/tmp/draft-plan-demo-$TRACKING_ID/` on an OS-assigned ephemeral port, never inside the worktree.

## Quiz mode (`quiz`)

Loads [`references/quiz.md`](https://github.com/zeveck/zskills/blob/main/skills/draft-plan/references/quiz.md) and runs an interactive **requirements interview** before any research:

- **No research during the interview** -- conversation runs against the agent's existing knowledge. Codebase uncertainties are deferred to the post-interview fan-out as open questions, never interrogated out of the user.
- **Ask vs defer rule:** ask the *user* about intent, scope, priorities, preferences, and success criteria; defer any *codebase fact* the agent is unsure of to the fan-out's open-questions list.
- **Running understanding summary** is restated every turn (goal / in-scope / out-of-scope / confirmed assumptions / open) so the user can correct drift in one reply.
- **Persistence + recovery-read:** state is written to `/tmp/draft-plan-quiz-$TRACKING_ID.md` after every answer, and re-read on resume after compaction before issuing the next question.
- **Termination contract:** the agent proposes readiness each round; it terminates only on an explicit, normalized, whole-message go-word (`draft` / `go` / `ready` / `proceed`). A go-word embedded in a steering sentence does **not** exit. Bare affirmations count only when they directly answer a just-posed readiness offer.
- **On exit,** the Phase 1 research fan-out runs unchanged but seeded with the durable interview file as priors, and the deferred open questions are handed to the Codebase/Prior-art agents to resolve. Phase 6 finalize adds a "Requirements captured via quiz" subsection to the plan's `## Plan Quality` section -- a distillation, not a raw transcript.

`quiz` is deliberately leading-flag-only (unlike `auto` and `brainstorm`) so that a description like "build a quiz app" or an autonomously-dispatched call from `/research-and-plan` cannot accidentally hang on an interactive prompt with no human to answer.

## Common Patterns

- **Standard plan drafting:** `/draft-plan Implement physics simulation blocks` -- research, draft, review cycles until convergence
- **Custom output:** `/draft-plan output plans/PHYSICS_BLOCKS.md Implement physics simulation blocks`
- **More review rounds:** `/draft-plan rounds 5 Redesign the state machine`
- **Interactive design exploration:** `/draft-plan brainstorm <idea>` -- pre-Phase-1 dialogue with optional visual demo
- **Interactive requirements elicitation:** `/draft-plan quiz <idea>` -- pre-research Socratic interview, then seeded fan-out
- **Autonomous (from /research-and-go):** `/draft-plan auto <description>` -- skip confirmation checkpoints

## Tips & Gotchas

- Must run at top level -- internally dispatches reviewer, devil's-advocate, and refiner sub-agents in parallel
- The plan output is designed to be executed by `/run-plan` -- each phase has clear acceptance criteria
- Adversarial review means multiple agents poke holes in the plan from different angles before convergence
- Completed phases from a prior `/run-plan` execution are never modified during refinement
- If the goal is broad enough to decompose into multiple sub-plans, consider `/research-and-plan` instead
- Reserve `/draft-plan` for skills/workflows with non-trivial design surface (integration points, multiple commands, hook interactions) -- thin prompt changes don't need adversarial review
- `brainstorm` and `quiz` are not mutually exclusive at the parser level, but they target different gaps -- `brainstorm` for "design surface is fuzzy and I want a co-design conversation"; `quiz` for "I know roughly what I want but the agent needs to extract precise requirements." Pick the one that matches the bottleneck; using both at once is unusual.
- `quiz` is leading-only by design -- to enable it you must lead with the flag (`/draft-plan quiz <description>`), not append it (`/draft-plan <description> quiz`)
