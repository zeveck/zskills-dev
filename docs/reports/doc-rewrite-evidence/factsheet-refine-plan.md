# Factsheet — docs/skills/refine-plan.md

Each doc claim is paired with the verbatim source line that supports it.
Source of truth: `skills/refine-plan/SKILL.md` (current HEAD).
Companion claims trace to `docs/reports/doc-rewrite-evidence/COMPANIONS.md`.

---

## Summary blockquote

**Doc:** "Refine an in-progress plan by reviewing its remaining phases against the work that has actually been built. Surfaces stale references, invalidated assumptions, and specification gaps, then refines until the review converges. Completed phases are never modified."

- `skills/refine-plan/SKILL.md:8-10`: "Refine an in-progress plan by reviewing remaining phases against / completed work. Dispatches reviewer + devil's-advocate agents to surface / stale references, invalidated assumptions, and specification gaps, then / refines until convergence."
- `skills/refine-plan/SKILL.md:9`: "Completed phases are NEVER modified."

## What it does — paragraph 1 (brings unfinished phases in line; reviews remaining against actual built, not planned)

**Doc:** "it reviews only the remaining phases against what was *actually* built, not what was *planned*, and rewrites them so the rest of the execution stays accurate."

- `skills/refine-plan/SKILL.md:18-21`: "The refiner reviews only the remaining phases against / what was actually built (not what was planned), then iteratively improves / them through adversarial review cycles."
- `skills/refine-plan/SKILL.md:23-27`: "The insight: plans drift during execution. Completed phases may have built / something different from what was originally specified. Remaining phases / still reference the original spec. `/refine-plan` closes this gap by / reviewing remaining phases against the *actual* state of completed work, / not the planned state."

## What it does — paragraph 2 (completed work is fixed context, never changed, including typo fixes — stated as a user guarantee, not the checksum mechanism per R5)

**Doc:** "The work you have already completed is treated as fixed, shipped reality. `/refine-plan` reads it for context but **never changes it** — not a single phase that is already done, not even a heading typo."

- `skills/refine-plan/SKILL.md:16-21`: "Completed phases / represent real, shipped work — they are **immutable context**, never / modification targets."
- `skills/refine-plan/SKILL.md:29-30`: "**Completed phases are NEVER modified.** They are read-only context that / informs the review. Not even heading typo fixes."
- Note (R5): SKILL.md:30-33 also states immutability is "verified mechanically" via byte-identical checksums. Per RUBRIC R5 the checksum mechanic is internals voice and is dropped; the user-facing guarantee ("never changes it") is kept (R4 — keep the true carve-out as a clear guarantee).

## What it does — paragraph 3 (two adversarial review passes + dimensions; findings fixed or justified; evidence re-checked; repeats rounds)

**Doc:** "One pass reviews them for stale references, inconsistencies, mis-sized work, specification gaps, broken dependencies, and acceptance criteria that no longer hold; a second, deliberately skeptical pass hunts for ways the remaining work will fail given what is already built — invalidated assumptions, duplicated work, deferred hard parts, hidden dependencies, scope creep, and integration risks."

- `skills/refine-plan/SKILL.md:351-353`: "### Reviewer agent / Reviews remaining phases against the reality of completed work. Checks / these six dimensions:" — dimensions at:
  - `:357` "1. **Stale references**"
  - `:361` "2. **Consistency**"
  - `:367` "3. **Sizing**"
  - `:371` "4. **Specification gaps**"
  - `:380` "5. **Dependency correctness**"
  - `:384` "6. **Acceptance criteria coverage**"
- `skills/refine-plan/SKILL.md:416-418`: "### Devil's Advocate agent / Genuinely adversarial — tries to find ways the remaining plan will fail / given what's already been built." — dimensions at:
  - `:420` "1. **Invalidated assumptions**"
  - `:424` "2. **Unnecessary work items**" (doc: "duplicated work")
  - `:428` "3. **Deferred hard parts**"
  - `:431` "4. **Hidden dependencies**"
  - `:435` "5. **Scope drift**" (doc: "scope creep")
  - `:438` "6. **Integration risks**"

**Doc:** "every finding is either fixed in the plan text or justified with evidence, and the cited evidence is re-checked before any fix is applied."

- `skills/refine-plan/SKILL.md:535-540`: "The agent addresses **every finding**. For each finding, it must either: / 1. **Fix it** — update the remaining phase text to resolve the issue / 2. **Justify** — explain with evidence why it's not actually a problem"
- `skills/refine-plan/SKILL.md:504-507`: "Before touching any phase text, the refiner must **attempt to reproduce / the cited evidence for each finding**."

**Doc:** "This repeats for a few rounds until the review stops turning up substantive problems."

- `skills/refine-plan/SKILL.md:563-566`: "**Check convergence:** / - **0 substantive issues** -> converged -> next phase. / - **>0 substantive issues AND rounds < max** -> another review+refine cycle"

## What it does — paragraph 4 (writes back in place; appends Drift Log + Plan Review; points at /run-plan)

**Doc:** "`/refine-plan` writes the updated plan back to the same file, in place."

- `skills/refine-plan/SKILL.md:584-585`: "Write the reassembled plan **in place** to the original plan file path. / Do NOT write to a new path."

**Doc:** "a **Drift Log** documenting where completed phases diverged from the plan as originally drafted"

- `skills/refine-plan/SKILL.md:587-592`: "### Drift Log / Append a `## Drift Log` section after the last phase. This documents / where completed phases diverged from the plan-as-originally-written."

**Doc:** "and a **Plan Review** summarizing the rounds of review and any concerns left open."

- `skills/refine-plan/SKILL.md:633-635`: "### Plan Review / Append a `## Plan Review` section after the Drift Log."
- `skills/refine-plan/SKILL.md:640-642`: "**Convergence:** [Converged at round M / Max rounds reached] / **Remaining concerns:** [None / List of unresolved issues]"

**Doc:** "It then points you at `/run-plan` to continue execution."

- `skills/refine-plan/SKILL.md:824`: "Continue execution with: `/run-plan <plan-file>`"

## What it does — paragraph 5 (no remaining phases → clean exit)

**Doc:** "If the plan has no remaining phases — everything is already done — `/refine-plan` exits cleanly and tells you there is nothing to refine."

- `skills/refine-plan/SKILL.md:865-867`: "**Plan with no remaining phases** — all phases are completed. Exit / cleanly: \"All phases complete — nothing to refine. Run with a plan that / has remaining phases.\""

## Usage / Arguments line

**Doc:** "`/refine-plan <plan-file> [rounds N] [auto] [guidance...]`"

- `skills/refine-plan/SKILL.md:4`: `argument-hint: "<plan-file> [rounds N] [auto] [guidance...]"`
- `skills/refine-plan/SKILL.md:127`: "`/refine-plan <plan-file> [rounds N] [auto] [guidance...]`"

## Arguments — plan-file

**Doc:** "Path to the plan `.md` file to refine. A bare filename is resolved against your plans directory; a path with a `/` is used as-is."

- `skills/refine-plan/SKILL.md:130`: "**plan-file** (required) — path to the plan `.md` file to refine."
- `skills/refine-plan/SKILL.md:142`: "The **first token** ending in `.md` is the plan file. If the token contains `/`, use as-is; otherwise resolve via `$ZSKILLS_PLANS_DIR/<token>` ..."

## Arguments — rounds N (default 2; early convergence exit)

**Doc:** "Maximum review/refine cycles. Default is 2. The process exits early if a round converges (no substantive new issues)."

- `skills/refine-plan/SKILL.md:131-133`: "**rounds N** (optional) — max review/refine cycles. Default: 2. The / process exits early if a round converges (no substantive new issues)."

## Arguments — auto (commits, then PR + CI + auto-merge; without auto, committed-not-PR'd)

**Doc:** "After the refined plan is committed, open a pull request, monitor CI, and auto-merge. Without `auto`, the refined plan is committed but no PR is opened — you land it yourself."

- `skills/refine-plan/SKILL.md:135-139`: "**auto** (optional positional token) — after the worktree auto-commit / in Phase 5 succeeds, dispatch `/land-pr` to push the branch, open a / PR, monitor CI, and auto-merge. Without `auto`, the refined plan is / committed in the worktree but no PR is opened."

## Arguments — guidance (trailing free text; steers review; priming not fact)

**Doc:** "Any trailing free text becomes guidance that steers what the review focuses on. It is treated as priming for the review, not as fact to act on blindly."

- `skills/refine-plan/SKILL.md:145`: "Any tokens not matched as the plan file or `rounds N` keyword OR the `auto` token are joined with spaces into **guidance text** ..."
- `skills/refine-plan/SKILL.md:299`: "Agents treat this as priming context that shapes WHAT they pressure-test — NOT as factual claims they should act on without verification"

## Arguments note — default 2 lighter than draft-plan's 3; auto mirrors siblings

**Doc:** "The default of 2 rounds is lighter than `/draft-plan`'s 3 ... The `auto` token mirrors the same token in `/run-plan`, `/do`, `/fix-issues`, `/quickfix`, and `/draft-plan`."

- `skills/refine-plan/SKILL.md:133-134`: "Default is 2 (not 3 like `/draft-plan`) because this is a refinement / pass on an existing plan, not blank-slate creation."
- `skills/refine-plan/SKILL.md:138-139`: "Mirrors `auto` in / `/run-plan`, `/do`, `/fix-issues`, `/quickfix`, `/draft-plan`."

## Companion skills (R6 — from COMPANIONS.md)

**Doc:** "`/draft-plan` — creates the plan ... `/refine-plan` adjusts that file once execution is underway."

- `COMPANIONS.md:81`: "`draft-plan` | ... `/refine-plan` adjusts it mid-flight."
- `COMPANIONS.md:91`: "`refine-plan` | `draft-plan`, `run-plan`, `draft-tests`, `do`, `quickfix`, `create-worktree` | Adjusts an in-flight plan; sits between `/draft-plan` and `/run-plan`."

**Doc:** "`/run-plan` — executes the plan, phase by phase. Run `/run-plan` to continue after `/refine-plan` ... sequential steps, not alternatives."

- `COMPANIONS.md:94`: "`run-plan` | `draft-plan` (prior step), `refine-plan`, ... | Executes a drafted plan; ... `/refine-plan` corrects drift."
- `COMPANIONS.md:53`: "**`/draft-plan` → `/run-plan`** are sequential, not alternatives"

**Doc:** "`/draft-tests` — the test-spec sibling in the planning family"

- `COMPANIONS.md:91`: companion list for `refine-plan` includes `draft-tests`.
- `COMPANIONS.md:111-112`: "**Planning peers:** `draft-plan`, `run-plan`, `refine-plan`, `draft-tests`, `plans`."

**Doc (flow line):** "`/draft-plan` (create) → `/run-plan` (execute) → `/refine-plan` (refine mid-execution ...) → `/run-plan` (resume)."

- `COMPANIONS.md:40`: "Plan is mid-execution and reality has drifted from the spec | `/refine-plan`"
- `COMPANIONS.md:91`: "Adjusts an in-flight plan; sits between `/draft-plan` and `/run-plan`."

## Tips & Gotchas — preserves frontmatter/overview/tracker/completed byte-for-byte

**Doc:** "the refined file preserves them, the frontmatter, the overview, and the progress tracker exactly as they were."

- `skills/refine-plan/SKILL.md:573-583`: "Reassemble the plan file by concatenating in order: / 1. **Original YAML frontmatter** (unchanged...) / 2. **Original title + Overview section** (unchanged...) / 3. **Progress Tracker table** (unchanged...) / 4. **Completed phases** (unchanged, byte-for-byte...)"
- `skills/refine-plan/SKILL.md:831-833`: "The plan's / structure, frontmatter, overview, progress tracker, and completed phases / are preserved byte-for-byte."

---

## R5 internals deliberately stripped (present in SKILL.md, omitted from doc)

- Checksum / byte-identical immutability *mechanism* (SKILL.md:30-33, :278, :578-581) — kept the guarantee, dropped the mechanism.
- Agent-type names "reviewer / devil's-advocate / refiner sub-agents", parallel dispatch, top-level Agent preflight (SKILL.md:36-51, :291-293) — described as "an adversarial review" in plain terms.
- Worktree preamble, `ensure-worktree.sh`, `ZSKILLS_PATHS_ROOT`, `git-common-dir`, `--pipeline-id` (SKILL.md:53-122) — dropped entirely.
- Tracking markers, `PIPELINE_ID`, `sanitize-pipeline-id.sh`, `.zskills/tracking/...` (SKILL.md:224-246, :478-492, :794-814) — dropped.
- `/tmp/refine-plan-*` persistence files, checksums, disposition table mechanics (SKILL.md:280-289, :471-475, :553) — dropped.
- `/land-pr` dispatch plumbing, result-file allow-list parse (SKILL.md:733-792) — collapsed to "open a pull request, monitor CI, and auto-merge".
