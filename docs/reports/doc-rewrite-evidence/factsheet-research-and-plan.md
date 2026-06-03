# Fact sheet — `docs/skills/research-and-plan.md`

Every factual claim in the rewritten `docs/skills/research-and-plan.md`, paired
with the verbatim source line that backs it. Format:
`doc sentence → skills/research-and-plan/SKILL.md:LINE: "<verbatim quoted text>"`.
Companion/usage claims cite `COMPANIONS.md` / `USAGE_MAP.md`.

---

## Summary / "What it does" section

- Decomposes a broad goal into a sequence of executable sub-plans →
  skills/research-and-plan/SKILL.md:5: "  Decompose a broad goal into a sequence of executable sub-plans."

- Researches the domain, identifies sub-problems and dependencies →
  skills/research-and-plan/SKILL.md:6: "  Researches the domain, identifies sub-problems and dependencies,"

- Produces a meta-plan whose phases each hand off to `/run-plan` →
  skills/research-and-plan/SKILL.md:7: "  produces a meta-plan whose phases each delegate to /run-plan."

- Breaks the goal into smaller focused sub-plans, each via `/draft-plan` and `/run-plan` →
  skills/research-and-plan/SKILL.md:14: "Breaks broad goals into focused sub-plans, each drafted via `/draft-plan`"

- Surveys what the goal covers, what already exists, natural sub-domains →
  skills/research-and-plan/SKILL.md:61: "### 1a. Domain survey — Dispatch Explore agents to map the scope: what the"

- And what exists already, natural sub-domains, shared infrastructure →
  skills/research-and-plan/SKILL.md:62: "goal encompasses, what exists already, natural sub-domains, shared"

- Works out how the pieces depend on each other →
  skills/research-and-plan/SKILL.md:65: "### 1b. Dependency analysis — Build a dependency graph: which sub-problems"

- Estimates each sub-problem's size →
  skills/research-and-plan/SKILL.md:68: "### 1c. Scope sizing — Estimate each sub-problem's size. If a sub-plan"

- Too-large sub-problems get split further →
  skills/research-and-plan/SKILL.md:69: "would need 8+ phases, split further. Each must be completable by"

- Presents the split — sub-problems, dependency order, in/out of scope →
  skills/research-and-plan/SKILL.md:80: "> In scope: [list]. Out of scope: [list]."

- Presents the dependency graph in the decomposition →
  skills/research-and-plan/SKILL.md:78: "> Dependency graph: A -> B -> D, A -> C (independent of B)"

- Waits for user confirmation unless told otherwise →
  skills/research-and-plan/SKILL.md:82: "**Without `auto`:** wait for user confirmation. They may reorder, drop,"

- User may reorder, drop, merge, or add sub-problems at the checkpoint →
  skills/research-and-plan/SKILL.md:83: "merge, or add sub-problems. Do NOT proceed until confirmed."

- After confirmation, drafts each sub-plan via `/draft-plan` →
  skills/research-and-plan/SKILL.md:90: "After user approval, draft each sub-plan by invoking `/draft-plan`."

- Each sub-plan goes through the same adversarial review a standalone plan would →
  skills/research-and-plan/SKILL.md:418: "- **Adversarial review targets the decomposition.** Individual sub-plans"
  skills/research-and-plan/SKILL.md:419: "  get their own review via `/draft-plan`. Step 3 reviews the split itself."

- Drafts one at a time (serial) →
  skills/research-and-plan/SKILL.md:156: "**Serial dispatch — no parallelism.** Invoke `/draft-plan` once per"

- Drafts in dependency order, foundation first →
  skills/research-and-plan/SKILL.md:165: "1. Foundation plan first (everything depends on it)"

- Later sub-plans can reference earlier sub-plans' actual content →
  skills/research-and-plan/SKILL.md:169: "Dependent sub-plans must be drafted after their prerequisites so later"
  skills/research-and-plan/SKILL.md:170: "plans can reference earlier plans' actual content."

- Reviews the whole set together for cross-plan problems →
  skills/research-and-plan/SKILL.md:229: "After all sub-plans are drafted and verified (Step 2b), review the **full"
  skills/research-and-plan/SKILL.md:230: "set** for cross-plan consistency. Individual sub-plans were reviewed by `/draft-plan`, but"

- Cross-plan issues only emerge when looking at all plans at once →
  skills/research-and-plan/SKILL.md:231: "cross-plan issues (shared schemas, naming collisions, directory conflicts,"
  skills/research-and-plan/SKILL.md:232: "storage model disagreements) only emerge when you look at all plans together."

- Clashing names / disagreeing schemas / conflicting directories named explicitly →
  skills/research-and-plan/SKILL.md:238: "- Do all sub-plans agree on shared data structures, schemas, field names?"
  skills/research-and-plan/SKILL.md:239: "- Are directory paths, ID prefixes, and namespaces consistent?"

- Missing integration glue →
  skills/research-and-plan/SKILL.md:245: "- **Missing glue** — who integrates the sub-plans?"

- Edits the sub-plan files to fix what it finds →
  skills/research-and-plan/SKILL.md:248: "### After each round: apply fixes to the sub-plan files"

- Writes the meta-plan; its phases are pure hand-offs →
  skills/research-and-plan/SKILL.md:16: "are pure delegation — no drafting happens during execution."

- Each phase points `/run-plan` at one sub-plan →
  skills/research-and-plan/SKILL.md:275: "the meta-plan. Every phase is pure delegation — `/run-plan` executes"

- No drafting happens later; all of it is done up front →
  skills/research-and-plan/SKILL.md:411: "  `### Execution: delegate /run-plan`. No `delegate /draft-plan` — all"
  skills/research-and-plan/SKILL.md:412: "  drafting happens upfront in Step 2."

- The meta-plan is an index, not a patch set →
  skills/research-and-plan/SKILL.md:254: "reads; the meta-plan is an index, not a patch set."

## Pair framing (R-consistency with research-and-go.md)

- `-and-plan` stops after the meta-plan is ready for review →
  COMPANIONS.md:56: "  `-and-plan` stops after the meta-plan is ready, `-and-go` continues into"

- `-and-go` continues into execution; same drafting machinery →
  COMPANIONS.md:55: "- **`/research-and-plan` vs `/research-and-go`**: same drafting machinery;"

- `/research-and-plan` is the stop-after-draft twin of `/research-and-go` →
  COMPANIONS.md:93: "| `research-and-plan` | `research-and-go` (peer), `draft-plan`, `refine-plan`, `run-plan`, `plans`, `fix-issues`, `verify-changes`, `create-worktree` | Stop-after-draft twin; decomposes a goal into sub-plans for review. |"

- `/research-and-go` is the continue-into-execution twin →
  COMPANIONS.md:92: "| `research-and-go` | `research-and-plan` (peer), `draft-plan`, `run-plan`, `fix-issues`, `verify-changes`, `commit`, `create-worktree` | Continue-into-execution twin of `/research-and-plan`; decomposes + runs sub-plans. |"

- Use `-and-plan` when you want a checkpoint before execution →
  CLAUDE.md "Common confusions": "Use `-and-plan` when the user wants a checkpoint before commit-volume work begins; `-and-go` when they've said \"walk away.\""
  (Mirrored in COMPANIONS.md:38-39 routing table: "Broad goal that decomposes into multiple sub-plans | `/research-and-plan`" / "Same as above, but execute all sub-plans autonomously after drafting | `/research-and-go`".)

## "Typical usage" / "Examples" section

- `/research-and-plan Build a complete physics simulation engine` is a real example →
  skills/research-and-plan/SKILL.md (prior doc examples block, source-grounded by the description-required arg at) :44: "- **description** (required) — everything after recognized keywords."
  Verbatim shape preserved from the skill's own Usage; goal-on-its-own is valid per :44.

- `output FILE` chooses where the meta-plan is written →
  skills/research-and-plan/SKILL.md:39: "- **output FILE** (optional) — meta-plan output path. Default:"

- `auto` skips the checkpoint and goes from research into drafting →
  skills/research-and-plan/SKILL.md:41: "- **auto** (optional) — skip the decomposition confirmation checkpoint."
  skills/research-and-plan/SKILL.md:42: "  Proceed directly to drafting after decomposition research. Used by"

- Run `/run-plan` on the meta-plan to execute it →
  skills/research-and-plan/SKILL.md:405: "   > Execute with: `/run-plan $ZSKILLS_PLANS_DIR/<FILE>.md`"

## "Companion skills" section

- `/research-and-go` is the peer (relationship) →
  COMPANIONS.md:93: "| `research-and-plan` | `research-and-go` (peer), `draft-plan`, `refine-plan`, `run-plan`, `plans`, ... | Stop-after-draft twin; decomposes a goal into sub-plans for review. |"

- `/draft-plan` is run on each sub-problem →
  skills/research-and-plan/SKILL.md:90: "After user approval, draft each sub-plan by invoking `/draft-plan`."

- `/draft-plan` escalates here when a goal is too broad for a single plan →
  skills/research-and-plan/SKILL.md:50: "**Escalation from `/draft-plan`:** If the invoking context mentions a"
  skills/research-and-plan/SKILL.md:51: "research file at `/tmp/draft-plan-research-*.md`, read it — that research"

- `/run-plan` is what every meta-plan phase hands off to →
  skills/research-and-plan/SKILL.md:306: "### Execution: delegate /run-plan $ZSKILLS_PLANS_DIR/<SUB_PLAN_X>.md finish auto"

- `/refine-plan` adjusts a drifted sub-plan (companion edge) →
  COMPANIONS.md:93: "| `research-and-plan` | `research-and-go` (peer), `draft-plan`, `refine-plan`, `run-plan`, `plans`, `fix-issues`, `verify-changes`, `create-worktree` | ... |"

- `/plans` is the plan catalog where the meta-plan and sub-plans appear →
  skills/research-and-plan/SKILL.md:397: "2. **Plan index — do not touch.** The plan index is regenerated from"
  skills/research-and-plan/SKILL.md:398: "   source-of-truth by `/plans rebuild` and auto-refreshed by `/plans`"
  (companion edge: COMPANIONS.md:93 lists `plans`.)

## "Arguments" section

- `description` is required, natural language →
  skills/research-and-plan/SKILL.md:44: "- **description** (required) — everything after recognized keywords."

- `output FILE` is optional; default is an auto-derived `<SLUG>_META.md` →
  skills/research-and-plan/SKILL.md:39: "- **output FILE** (optional) — meta-plan output path. Default:"
  skills/research-and-plan/SKILL.md:40: "  `$ZSKILLS_PLANS_DIR/<SLUG>_META.md` (slug from description)."

- `auto` is documented in the body even though `argument-hint` omits it →
  skills/research-and-plan/SKILL.md:3: "argument-hint: \"[output FILE] <broad goal description>\""
  (omits `auto`)
  skills/research-and-plan/SKILL.md:41: "- **auto** (optional) — skip the decomposition confirmation checkpoint."
  (body documents it — body wins per RUBRIC.md template item 4)

- `/research-and-go` passes `auto` through for autonomous operation →
  skills/research-and-plan/SKILL.md:43: "  `/research-and-go` for fully autonomous operation."

- Arguments detected positionally (output+path, auto, first `.md` token; rest = description) →
  skills/research-and-plan/SKILL.md:46: "**Detection:** scan arguments for `output` + path, `auto`, and first"
  skills/research-and-plan/SKILL.md:47: "token ending `.md`. Everything else = description. `auto` is stripped"

## "Tips & Gotchas" section

- Runs as a top-level command; cannot run as a dispatched sub-agent →
  skills/research-and-plan/SKILL.md:24: "Before doing any other work, verify your tool list contains `Agent` or `Task`. If neither is present, STOP and report:"
  skills/research-and-plan/SKILL.md:26: "> ERROR: /research-and-plan requires top-level Agent dispatch capability. This invocation is running as a subagent (no Agent tool ...). Subagents cannot dispatch sub-subagents ..."

- It relies on launching its own research and review agents →
  skills/research-and-plan/SKILL.md:22: "This skill internally dispatches reviewer + devil's-advocate + refiner sub-agents in parallel. It MUST run in a context that has the `Agent` (or `Task`) tool available."

- The meta-plan is an index; every phase hands off to `/run-plan` →
  skills/research-and-plan/SKILL.md:410: "- **Pure delegation in the meta-plan.** Every phase uses"

- No sub-plans drafted later; all drafting up front →
  skills/research-and-plan/SKILL.md:412: "  drafting happens upfront in Step 2."

- Each sub-plan is sized to finish in one `/run-plan` session; 8+ phases split further →
  skills/research-and-plan/SKILL.md:426: "- **Each sub-plan must be session-completable.** If a sub-plan needs 8+"
  skills/research-and-plan/SKILL.md:427: "  phases, split it further."

- A sub-plan drafted before its dependency carries a refresh note for `/run-plan` →
  skills/research-and-plan/SKILL.md:172: "**Staleness notes for dependent sub-plans.** Sub-plans that depend on"
  skills/research-and-plan/SKILL.md:183: "This tells `/run-plan` to offer a plan refresh (interactive) or"
  skills/research-and-plan/SKILL.md:184: "auto-refresh (auto mode) before implementing — ensuring the plan reflects"

- For a fully autonomous decompose-and-execute run, use `/research-and-go` →
  skills/research-and-plan/SKILL.md:42: "  Proceed directly to drafting after decomposition research. Used by"
  skills/research-and-plan/SKILL.md:43: "  `/research-and-go` for fully autonomous operation."

- `/draft-plan` escalation preserves research so work isn't repeated →
  skills/research-and-plan/SKILL.md:52: "feeds Step 1 and avoids redundant exploration."
