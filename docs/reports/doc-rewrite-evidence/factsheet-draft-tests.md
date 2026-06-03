# Fact sheet — `docs/skills/draft-tests.md`

Every factual claim in the rewritten `docs/skills/draft-tests.md`, paired with the
verbatim source line that backs it. Format:
`doc sentence → skills/draft-tests/SKILL.md:LINE: "<verbatim quoted text>"`.
Companion-relationship claims cite `COMPANIONS.md`; usage-shape claims cite `USAGE_MAP.md`.

---

## "What it does" section

- Takes an existing plan (the kind `/draft-plan` produces) and writes test specs into it →
  skills/draft-tests/SKILL.md:18: "machinery, scoped to test specifications. Given the path to an existing"

- For every pending phase it appends a `### Tests` subsection →
  skills/draft-tests/SKILL.md:19: "plan (the kind `/draft-plan` produces), this skill appends a"
  skills/draft-tests/SKILL.md:20: "`### Tests` subsection into every pending phase, then runs a senior-QE"

- It pressure-tests the specs through several rounds of adversarial review and refinement →
  skills/draft-tests/SKILL.md:17: "Sister skill to `/draft-plan`: same drafting + adversarial-review"
  skills/draft-tests/SKILL.md:20: "`### Tests` subsection into every pending phase, then runs a senior-QE"
  skills/draft-tests/SKILL.md:21: "review loop (reviewer + devil's advocate + refiner) until the specs hold"

- The specs live inside the plan, riding along in the phases `/run-plan` executes →
  skills/draft-tests/SKILL.md:25: "`/run-plan` dispatches — not a human — so specs ride along inside the"
  skills/draft-tests/SKILL.md:26: "phases `/run-plan` already executes. No companion document. No"

- There is no separate test document and no `/run-plan` setup →
  skills/draft-tests/SKILL.md:26: "phases `/run-plan` already executes. No companion document. No"
  skills/draft-tests/SKILL.md:27: "`/run-plan` loader patch."

- The reader of the specs is the implementing agent, not a human →
  skills/draft-tests/SKILL.md:24: "The reader of the appended specs is the AI implementing agent that"
  skills/draft-tests/SKILL.md:25: "`/run-plan` dispatches — not a human — so specs ride along inside the"

- Completed phases are never modified; only pending phases get specs →
  skills/draft-tests/SKILL.md:29: "**Completed phases are never mutated.** Checksum-gated, per"

- A gap in a completed phase is surfaced as a new backfill phase, not by editing the finished phase →
  skills/draft-tests/SKILL.md:32: "— a stricter invariant than `/refine-plan`. Test gaps in completed"
  skills/draft-tests/SKILL.md:33: "phases are surfaced by appending a new top-level"
  skills/draft-tests/SKILL.md:34: "`## Phase N — Backfill tests for completed phases X–Y` BEFORE any"
  skills/draft-tests/SKILL.md:35: "existing trailing sections."

- Sister skill / test-spec member of the plan-authoring family →
  skills/draft-tests/SKILL.md:17: "Sister skill to `/draft-plan`: same drafting + adversarial-review"
  COMPANIONS.md:82: "| `draft-tests` | `draft-plan`, `refine-plan`, `run-plan`, `do`, `quickfix`, `create-worktree` | Test-spec authoring sibling of the plan-authoring family. |"

- Scoped narrowly to adding test specs (vs `/draft-plan` drafting, `/refine-plan` adjusting) →
  skills/draft-tests/SKILL.md:32: "— a stricter invariant than `/refine-plan`. Test gaps in completed"
  COMPANIONS.md:91: "| `refine-plan` | `draft-plan`, `run-plan`, `draft-tests`, `do`, `quickfix`, `create-worktree` | Adjusts an in-flight plan; sits between `/draft-plan` and `/run-plan`. |"

## "Usage" / top-level dispatch

- Runs at the top level; cannot run as a subagent because it launches its own review agents →
  skills/draft-tests/SKILL.md:41: "This skill internally dispatches reviewer + devil's-advocate + refiner sub-agents in parallel. It MUST run in a context that has the `Agent` (or `Task`) tool available."

- Typed as a slash command or dispatched via the Skill tool →
  skills/draft-tests/SKILL.md:48: ">   - User slash command: `/draft-tests <plan-file>`"
  skills/draft-tests/SKILL.md:49: ">   - Top-level `Skill` tool: `Skill(skill=\"draft-tests\", args=\"<plan-file>\")`"

## "Typical usage" section

- Common form is a plan path, optionally with focus guidance →
  skills/draft-tests/SKILL.md:182: "- `/draft-tests plans/FEATURE.md`"
  skills/draft-tests/SKILL.md:185: "- `/draft-tests plans/FOO.md focus on integration tests`"

- A bare plan name resolves against the project's plans directory →
  skills/draft-tests/SKILL.md:184: "- `/draft-tests FEATURE.md` → reads `$ZSKILLS_PLANS_DIR/FEATURE.md`"

- Example shapes (`rounds 4`, integration-tests focus, property-based coverage) →
  skills/draft-tests/SKILL.md:183: "- `/draft-tests plans/FEATURE.md rounds 4`"
  skills/draft-tests/SKILL.md:185: "- `/draft-tests plans/FOO.md focus on integration tests`"
  skills/draft-tests/SKILL.md:186: "- `/draft-tests plans/FOO.md rounds 3 emphasize property-based coverage`"

- Guidance steers what the review focuses on →
  skills/draft-tests/SKILL.md:154: "  byte-identical reviewer/DA prompt output (regression-safe). Guidance"
  skills/draft-tests/SKILL.md:155: "  is **priming context** that shapes WHAT the agents pressure-test —"

- (`/draft-tests` is not observed in the cron-fire form; usage shapes pulled from the skill's own examples per R7) →
  USAGE_MAP.md:62: "**Never observed in the `Run /<skill>` cron form:** `/create-worktree`,"
  USAGE_MAP.md:63: "`/doc`, `/draft-tests`, `/fix-report`, `/manual-testing`, `/research-and-go`,"

## "Companion skills" section

- `/draft-plan` is the sister skill; run `/draft-tests` on a plan it produced →
  skills/draft-tests/SKILL.md:17: "Sister skill to `/draft-plan`: same drafting + adversarial-review"
  skills/draft-tests/SKILL.md:19: "plan (the kind `/draft-plan` produces), this skill appends a"
  COMPANIONS.md:82: "| `draft-tests` | `draft-plan`, `refine-plan`, `run-plan`, `do`, `quickfix`, `create-worktree` | Test-spec authoring sibling of the plan-authoring family. |"

- `/run-plan` executes the plan; the specs ride along inside the phases it runs →
  skills/draft-tests/SKILL.md:25: "`/run-plan` dispatches — not a human — so specs ride along inside the"

- `/refine-plan` adjusts a plan mid-flight; `/draft-tests` is the narrower test-spec tool; both leave completed phases untouched →
  COMPANIONS.md:91: "| `refine-plan` | `draft-plan`, `run-plan`, `draft-tests`, `do`, `quickfix`, `create-worktree` | Adjusts an in-flight plan; sits between `/draft-plan` and `/run-plan`. |"
  skills/draft-tests/SKILL.md:29: "**Completed phases are never mutated.** Checksum-gated, per"

- `/do`, `/quickfix` for one-off changes that don't need a plan (planning peers) →
  COMPANIONS.md:82: "| `draft-tests` | `draft-plan`, `refine-plan`, `run-plan`, `do`, `quickfix`, `create-worktree` | Test-spec authoring sibling of the plan-authoring family. |"
  COMPANIONS.md:110: "- **Planning peers:** `draft-plan`, `run-plan`, `refine-plan`, `draft-tests`,"

## "Arguments" section

- `plan-file` required; `/`-path used as-is, bare name resolved against the plans directory →
  skills/draft-tests/SKILL.md:134: "- **plan-file** (required) — path to the plan `.md` file. If the token"
  skills/draft-tests/SKILL.md:135: "  contains `/`, use as-is; otherwise resolve via"
  skills/draft-tests/SKILL.md:136: "  `$ZSKILLS_PLANS_DIR/<token>` (sourcing"

- `rounds N` is the max review/refine cycles; default 3 →
  skills/draft-tests/SKILL.md:139: "- **rounds N** (optional) — max review/refine cycles. Default: 3 (matches"

- `auto`: after the commit, open a PR, watch CI, auto-merge →
  skills/draft-tests/SKILL.md:143: "- **auto** (optional positional token) — after the worktree auto-commit"
  skills/draft-tests/SKILL.md:144: "  in Phase 6 succeeds, dispatch `/land-pr` to push the branch, open a"
  skills/draft-tests/SKILL.md:145: "  PR, monitor CI, and auto-merge. Without `auto`, the spec-augmented"
  skills/draft-tests/SKILL.md:146: "  plan is committed in the worktree but no PR is opened. Mirrors `auto`"

- Without `auto`, the change is committed but no PR is opened →
  skills/draft-tests/SKILL.md:145: "  PR, monitor CI, and auto-merge. Without `auto`, the spec-augmented"
  skills/draft-tests/SKILL.md:146: "  plan is committed in the worktree but no PR is opened. Mirrors `auto`"

- `guidance` = extra words steering what the review pressure-tests →
  skills/draft-tests/SKILL.md:149: "- **guidance...** (optional) — any tokens not matched as plan file,"
  skills/draft-tests/SKILL.md:154: "  byte-identical reviewer/DA prompt output (regression-safe). Guidance"
  skills/draft-tests/SKILL.md:155: "  is **priming context** that shapes WHAT the agents pressure-test —"

- Plan file detected as the first token containing `/` or ending in `.md` →
  skills/draft-tests/SKILL.md:160: "- The **first** token ending in `.md` OR containing `/` is the plan"
  skills/draft-tests/SKILL.md:161: "  file. If the token contains `/`, use as-is; otherwise resolve via"

- `rounds` with no number after it is treated as guidance →
  skills/draft-tests/SKILL.md:163: "- `rounds` followed by a numeric argument sets max cycles. (`rounds`"
  skills/draft-tests/SKILL.md:164: "  not followed by a number is treated as guidance text, not the"

- `auto` matched case-insensitively as a standalone word →
  skills/draft-tests/SKILL.md:166: "- `auto` (whitespace-anchored, case-insensitive) sets `AUTO_FLAG=1` for"

- Leftover tokens joined into guidance →
  skills/draft-tests/SKILL.md:169: "- Any tokens not matched as the plan file, `rounds N` keyword, or the"
  skills/draft-tests/SKILL.md:170: "  `auto` token are joined with spaces into guidance text."

- Guidance is priming context, not fact; verify-before-acting still applies →
  skills/draft-tests/SKILL.md:154: "  byte-identical reviewer/DA prompt output (regression-safe). Guidance"
  skills/draft-tests/SKILL.md:155: "  is **priming context** that shapes WHAT the agents pressure-test —"
  skills/draft-tests/SKILL.md:156: "  NOT factual claims they should act on without verification."
  skills/draft-tests/SKILL.md:157: "  Verify-before-fix discipline still applies in the refiner."

- No plan file → usage error and stop →
  skills/draft-tests/SKILL.md:171: "- If no plan file is detected, **error:**"
  skills/draft-tests/SKILL.md:172: "  `Usage: /draft-tests <plan-file> [rounds N] [auto] [guidance...]`"

## "Examples" section

(all verbatim from the source examples block)

- `/draft-tests plans/FEATURE.md` →
  skills/draft-tests/SKILL.md:182: "- `/draft-tests plans/FEATURE.md`"

- `/draft-tests plans/FEATURE.md rounds 4` →
  skills/draft-tests/SKILL.md:183: "- `/draft-tests plans/FEATURE.md rounds 4`"

- `/draft-tests FEATURE.md` →
  skills/draft-tests/SKILL.md:184: "- `/draft-tests FEATURE.md` → reads `$ZSKILLS_PLANS_DIR/FEATURE.md`"

- `/draft-tests plans/FOO.md focus on integration tests` →
  skills/draft-tests/SKILL.md:185: "- `/draft-tests plans/FOO.md focus on integration tests`"

- `/draft-tests plans/FOO.md rounds 3 emphasize property-based coverage` →
  skills/draft-tests/SKILL.md:186: "- `/draft-tests plans/FOO.md rounds 3 emphasize property-based coverage`"

- `/draft-tests plans/FEATURE.md auto` (auto token documented as a positional) →
  skills/draft-tests/SKILL.md:143: "- **auto** (optional positional token) — after the worktree auto-commit"

## "Common Patterns" / "Tips & Gotchas"

- Run on a freshly drafted plan to add specs before `/run-plan` executes →
  skills/draft-tests/SKILL.md:19: "plan (the kind `/draft-plan` produces), this skill appends a"
  skills/draft-tests/SKILL.md:26: "phases `/run-plan` already executes. No companion document. No"

- More rounds for a thorny surface →
  skills/draft-tests/SKILL.md:139: "- **rounds N** (optional) — max review/refine cycles. Default: 3 (matches"

- Trailing/non-phase sections left exactly as they were →
  skills/draft-tests/SKILL.md:30: "`/refine-plan`'s immutability pattern. `/draft-tests` ALSO preserves"
  skills/draft-tests/SKILL.md:31: "every trailing non-phase section byte-identical at the file-write level"

- `auto` is the same token used by `/draft-plan`, `/run-plan`, `/do`, `/fix-issues`, `/quickfix`, `/refine-plan` →
  skills/draft-tests/SKILL.md:146: "  plan is committed in the worktree but no PR is opened. Mirrors `auto`"
  skills/draft-tests/SKILL.md:147: "  in `/run-plan`, `/do`, `/fix-issues`, `/quickfix`, `/draft-plan`,"
  skills/draft-tests/SKILL.md:148: "  `/refine-plan`."

- `auto` controls landing, does not skip review →
  skills/draft-tests/SKILL.md:143: "- **auto** (optional positional token) — after the worktree auto-commit"
  skills/draft-tests/SKILL.md:144: "  in Phase 6 succeeds, dispatch `/land-pr` to push the branch, open a"
