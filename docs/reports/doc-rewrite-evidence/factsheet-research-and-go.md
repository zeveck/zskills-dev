# Fact sheet — `docs/skills/research-and-go.md`

Every factual claim in the rewritten `docs/skills/research-and-go.md`, paired
with the verbatim source line that backs it. Format:
`doc sentence → skills/research-and-go/SKILL.md:LINE: "<verbatim quoted text>"`.
Companion/routing claims cite `COMPANIONS.md:LINE`; typical-usage examples cite
`skills/research-and-go/SKILL.md` example lines or `USAGE_MAP.md`.

---

## Blockquote summary

- Full pipeline: decompose a broad goal into sub-plans, draft each with adversarial review, then execute all autonomously via `/run-plan`, walk away →
  skills/research-and-go/SKILL.md:5: "  Full pipeline: decompose a broad goal into sub-plans, draft each with"
  skills/research-and-go/SKILL.md:6: "  adversarial review, then execute all of them autonomously via /run-plan."
  skills/research-and-go/SKILL.md:7: "  One command, walk away."

## "What it does" section

- Takes a broad goal and carries it from idea to landed code without pausing for approval →
  skills/research-and-go/SKILL.md:14: "The full autonomous pipeline in one command. Decomposes a broad goal into"

- Researches the domain, breaks the goal into focused sub-plans, identifies dependencies →
  skills/research-and-go/SKILL.md:217: "1. Dispatches research agents to survey the domain"
  skills/research-and-go/SKILL.md:218: "2. Identifies sub-problems and dependencies"

- Drafts each sub-plan through adversarial review →
  skills/research-and-go/SKILL.md:15: "focused sub-plans, drafts each with adversarial review, writes a meta-plan,"
  skills/research-and-go/SKILL.md:222: "   (each gets full adversarial review in its own context)"

- Writes a single meta-plan and immediately runs it to completion →
  skills/research-and-go/SKILL.md:15: "focused sub-plans, drafts each with adversarial review, writes a meta-plan,"
  skills/research-and-go/SKILL.md:16: "and immediately executes it — all without pausing for approval."

- Drafting half is the same machinery as `/research-and-plan`; each sub-plan sized and written via dispatched `/draft-plan` →
  skills/research-and-go/SKILL.md:219: "3. Sizes scope for each sub-plan"
  skills/research-and-go/SKILL.md:221: "5. Drafts each sub-plan via dispatched `/draft-plan` agents"

- Result is a meta-plan whose phases each delegate to `/run-plan` →
  skills/research-and-go/SKILL.md:223: "6. Writes the meta-plan with pure implementation phases"
  skills/research-and-go/SKILL.md:329: "This executes all implementation phases sequentially -- each delegating"
  skills/research-and-go/SKILL.md:330: "to `/run-plan` on the corresponding sub-plan via chunked cron-fired turns."

- `/research-and-plan` stops at a reviewed meta-plan; `/research-and-go` continues into execution (pair framing) →
  COMPANIONS.md:55: "- **`/research-and-plan` vs `/research-and-go`**: same drafting machinery;"
  COMPANIONS.md:56: "  `-and-plan` stops after the meta-plan is ready, `-and-go` continues into"
  COMPANIONS.md:57: "  execution."

- `/research-and-plan` hands you a reviewed meta-plan to look over for control →
  skills/research-and-go/SKILL.md:19: "single description. For more control, use `/research-and-plan` (plan only)"
  skills/research-and-go/SKILL.md:20: "followed by `/run-plan` (execute)."

- Each sub-plan is implemented, verified, and landed in dependency order →
  skills/research-and-go/SKILL.md:331: "Full verification, testing, and landing at each phase."
  skills/research-and-go/SKILL.md:374: "- **Sub-plan staleness refresh applies.** If a later sub-plan depends"

- Autonomous but not reckless; hard failure stops and reports →
  skills/research-and-go/SKILL.md:370: "- **Failure still stops.** If `/run-plan` hits the Failure Protocol"
  skills/research-and-go/SKILL.md:371: "  (cherry-pick conflict, test failures after landing, verification"
  skills/research-and-go/SKILL.md:372: "  fails after 2 cycles), it stops and reports. `go` means autonomous,"
  skills/research-and-go/SKILL.md:373: "  not reckless."

- Final step is a cross-branch verification pass over the combined result →
  skills/research-and-go/SKILL.md:147: "The pipeline will end with a top-level `/verify-changes branch` invocation"
  skills/research-and-go/SKILL.md:148: "that runs as a cron-fired turn after the meta-plan execution completes. By"

- Must run at top level (slash command or `Skill` tool); cannot run as a sub-agent →
  skills/research-and-go/SKILL.md:24: "## Preflight — top-level dispatch required"
  skills/research-and-go/SKILL.md:34: ">   - Top-level `Skill` tool: `Skill(skill=\"research-and-go\", args=\"<description>\")`"
  skills/research-and-go/SKILL.md:30: "> ERROR: /research-and-go requires top-level Agent dispatch capability. This invocation is running as a subagent (no Agent tool — verified by inspecting your tool list). Subagents cannot dispatch sub-subagents (Anthropic design — https://code.claude.com/docs/en/sub-agents)."

## "Usage" / "Arguments" section

- `/research-and-go <description>` is the invocation form →
  skills/research-and-go/SKILL.md:44: "/research-and-go <description>"

- `description` is required, natural language, same format as `/research-and-plan` →
  skills/research-and-go/SKILL.md:47: "- **description** (required) — the broad goal, in natural language."
  skills/research-and-go/SKILL.md:48: "  Same format as `/research-and-plan`."

- A `pr` or `direct` word in the description is passed through to `/run-plan` for landing →
  skills/research-and-go/SKILL.md:290: "  LANDING_ARG=\"pr\""
  skills/research-and-go/SKILL.md:292: "  LANDING_ARG=\"direct\""
  skills/research-and-go/SKILL.md:312: "  RUN_PROMPT=\"Run /run-plan $META_PLAN_PATH finish auto $LANDING_ARG\""

- With neither word present, landing falls back to the configured default →
  skills/research-and-go/SKILL.md:297: "If the goal text does not mention either keyword, `LANDING_ARG` stays"
  skills/research-and-go/SKILL.md:298: "empty and `/run-plan` falls back to its config default (normally"
  skills/research-and-go/SKILL.md:299: "`cherry-pick`). Do NOT pass a literal empty token to `/run-plan` — omit"

## "Typical usage" / "Examples" section

- `/research-and-go Add physical modeling support for thermal and mechanical domains` is a real example →
  skills/research-and-go/SKILL.md:51: "- `/research-and-go Add physical modeling support for thermal and mechanical domains`"

- `/research-and-go Implement all missing block diagram tool blocks from the gap analysis` is a real example →
  skills/research-and-go/SKILL.md:52: "- `/research-and-go Implement all missing block diagram tool blocks from the gap analysis`"

- `/research-and-go Close the runtime deployment parity gap` is a real example →
  skills/research-and-go/SKILL.md:53: "- `/research-and-go Close the runtime deployment parity gap`"

- Reach for it when you trust the pipeline and want end-to-end execution from one description →
  skills/research-and-go/SKILL.md:18: "**Use when:** you trust the pipeline and want end-to-end execution from a"

- Note: `/research-and-go` is "Never observed in the `Run /<skill>` cron form" — usage examples pulled from the skill body, not USAGE_MAP cron counts (R7) →
  USAGE_MAP.md:62: "**Never observed in the `Run /<skill>` cron form:** `/create-worktree`,"
  USAGE_MAP.md:63: "`/doc`, `/draft-tests`, `/fix-report`, `/manual-testing`, `/research-and-go`,"

## "Companion skills" section

- `/research-and-plan` is the peer (continue-into-execution twin) →
  COMPANIONS.md:92: "| `research-and-go` | `research-and-plan` (peer), `draft-plan`, `run-plan`, `fix-issues`, `verify-changes`, `commit`, `create-worktree` | Continue-into-execution twin of `/research-and-plan`; decomposes + runs sub-plans. |"
  COMPANIONS.md:93: "| `research-and-plan` | `research-and-go` (peer), `draft-plan`, `refine-plan`, `run-plan`, `plans`, `fix-issues`, `verify-changes`, `create-worktree` | Stop-after-draft twin; decomposes a goal into sub-plans for review. |"

- `/draft-plan` is dispatched once per sub-plan during drafting →
  skills/research-and-go/SKILL.md:221: "5. Drafts each sub-plan via dispatched `/draft-plan` agents"

- `/run-plan` is the executor for each sub-plan, in dependency order →
  skills/research-and-go/SKILL.md:330: "to `/run-plan` on the corresponding sub-plan via chunked cron-fired turns."

- `/verify-changes` is the final cross-branch gate →
  skills/research-and-go/SKILL.md:339: "1. A cron firing `Run /verify-changes branch tracking-id=$META_PLAN_SLUG`"
  COMPANIONS.md:97: "| `verify-changes` | `manual-testing`, `fix-report`, `run-plan`, `research-and-go`, `create-worktree` | The change-soundness gate; `/do`, `/run-plan`, `/research-and-go` call it; uses `/manual-testing` for UI. |"

## "Tips & Gotchas" section

- Same drafting machinery as `/research-and-plan`; only difference is continuing into execution →
  COMPANIONS.md:55: "- **`/research-and-plan` vs `/research-and-go`**: same drafting machinery;"
  COMPANIONS.md:56: "  `-and-plan` stops after the meta-plan is ready, `-and-go` continues into"

- No approval checkpoints once started; typing the goal is blanket approval →
  skills/research-and-go/SKILL.md:367: "- **No confirmation checkpoints.** The user said `go` — that's blanket"
  skills/research-and-go/SKILL.md:368: "  approval for decomposition, planning, and execution. Do not pause"

- Stops on hard failure (cherry-pick conflict, tests failing after two cycles, failed verification) →
  skills/research-and-go/SKILL.md:370: "- **Failure still stops.** If `/run-plan` hits the Failure Protocol"
  skills/research-and-go/SKILL.md:371: "  (cherry-pick conflict, test failures after landing, verification"
  skills/research-and-go/SKILL.md:372: "  fails after 2 cycles), it stops and reports. `go` means autonomous,"

- Must run at top level, never as a sub-agent (dispatches its own research/review agents) →
  skills/research-and-go/SKILL.md:26: "This skill `Skill`-loads `/research-and-plan` and `/run-plan`, which internally dispatch reviewer + devil's-advocate + refiner sub-agents in parallel. It MUST run in a context that has the `Agent` (or `Task`) tool available."

- Sub-plans built and executed in dependency order; dependent sub-plan refreshed if earlier work changed assumptions →
  skills/research-and-go/SKILL.md:374: "- **Sub-plan staleness refresh applies.** If a later sub-plan depends"
  skills/research-and-go/SKILL.md:375: "  on an earlier one, `/run-plan` auto-refreshes it via `/draft-plan`"
  skills/research-and-go/SKILL.md:376: "  before execution (the staleness check in Phase 1 step 6)."
