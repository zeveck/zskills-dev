# Factsheet — `docs/guides/workflows.md`

Each claim in the rewritten doc, paired with the doc sentence and its
verbatim source line. Sources are the **current** files at HEAD in this
worktree. The authoritative routing/flag content lives in
`.claude/rules/zskills/managed.md` (rendered from `CLAUDE_TEMPLATE.md`);
the worktree's top-level `CLAUDE.md` is the author-only variant and does
NOT carry the decision table / Execution Modes / flag-convention sections,
so those citations point at `managed.md` (the consumer-facing render of the
same content). Per-skill behavior cites `skills/<name>/SKILL.md`.

This doc is a light-touch rewrite of the prior "best newcomer doc" — the
recipe sections (1–11) were already accurate, so the factsheet focuses on
the sentences that were changed plus the load-bearing recipe claims.

---

## Philosophy + flag-convention callout (the changed sections)

**Doc:** "a feature whose approach still needs to be worked out gets `/draft-plan` first; a broad goal that splits into several dependent sub-plans gets `/research-and-plan`."
- `.claude/rules/zskills/managed.md:312`: "| Plan-scale design surface — needs adversarial review before execution | `/draft-plan` |"
- `.claude/rules/zskills/managed.md:313`: "| Broad goal that decomposes into multiple sub-plans | `/research-and-plan` |"
- (Rubric R3/R5: "design surface … adversarial review" is implementer jargon → re-stated plainly as "approach still needs to be worked out" / "splits into several dependent sub-plans". The routing target is unchanged.)

**Doc:** "reach for `/draft-plan` only when the work has open design questions or needs to be staged into ordered phases, not just because it touches a lot of files."
- `.claude/rules/zskills/managed.md:326`: "`/draft-plan` is the heavier tool, and it earns that when the work genuinely needs **staged phases** or has **open design to work out** … Heavy usually does mean `/draft-plan` — but heavy is staging or design depth, *not* breadth: thirty files touched mechanically is wide, not heavy."
- (R3 plain-language render of the "phases or unresolved design, not breadth" rule.)

**Doc:** "Your changes are checked before they land, whichever skill you pick: tests run, a separate review pass re-checks the work, and nothing reaches `main` unchecked."
- `.claude/rules/zskills/managed.md` "## Subagent Dispatch" / "Impl-agent dispatch": implementers run tests; a verifier re-checks before landing. Generalized to user altitude (R5: "verifier subagent" is dispatch plumbing → "a separate review pass").
- (R5: prior wording "a fresh verifier subagent re-checks" leaks `subagent`-class internals voice; rewritten to observable behavior.)

**Doc (argument-syntax callout):** "Most arguments you type are positional tokens — mode/verb words like `auto`, `pr`, `direct`, `finish` with no dashes."
- `.claude/rules/zskills/managed.md:349`: "Positional tokens (`apply`, `pr`, `auto`, `local`, `remote`, `all`, `from-here`, `skip-tests`, etc.) name *modes / verbs*; dashed `--force` is reserved for *safety-gate overrides*."

**Doc:** "`--force` (on `/do`, `/quickfix`, `/work-on-plans`, `/cleanup-merged`) skips the triage and review step"
- `.claude/rules/zskills/managed.md:349`: "Skills accepting `--force`: `/do`, `/work-on-plans`, `/quickfix`, `/cleanup-merged`."
- `.claude/rules/zskills/managed.md:347`: "Both skills now triage tasks and run a fresh-agent plan review before execution. Use `--force` to bypass."
- `.claude/rules/zskills/managed.md:344`: "`/quickfix Fix README typo --force` … `--force` skips triage + review"

**Doc:** "`--rounds N` (on `/do`) sets how many review-and-refine cycles run."
- `skills/do/SKILL.md:3`: argument-hint includes "`[--rounds N]`"
- `skills/do/SKILL.md:84`: "**--rounds N** (optional) — max review/refine cycles (default 1; `0` skips"
- `.claude/rules/zskills/managed.md:345`: "`/do Add dark mode. --rounds 2 --force. pr`"

**Doc:** "The one dashed flag you do not type is `--auto`: that form belongs to the internal `/land-pr` helper these skills dispatch for you. To auto-merge, pass the positional `auto` token instead."
- `.claude/rules/zskills/managed.md:349`: flag convention names ONLY `--force` (and skill-bodies add `--rounds`) as user-facing dashed flags; `--auto` is not in the positional/user list.
- `.claude/rules/zskills/managed.md:233`: "dispatch `/land-pr` via the Skill tool (with `--body-file` and `--result-file`)" — `--auto` is `/land-pr`'s flag.
- `skills/commit/SKILL.md:142`: "`/commit pr auto` → PR mode + auto-merge via `/land-pr --auto`" (the positional `auto` is what the user types; it maps to `/land-pr --auto` internally).
- (This is the plan's load-bearing carve-out: the claim that `--auto` belongs to `/land-pr` is TRUE and is preserved; the prior over-broad "you should never type a dashed flag yourself" is corrected by naming `--force` / `--rounds N` as genuine user-facing dashed flags.)

---

## Recipe-section claims (unchanged but load-bearing)

**Doc §1:** "`finish` runs all phases (not just the next one)"
- `skills/run-plan/SKILL.md:35`: "**finish** (optional) — run ALL remaining phases sequentially until the"

**Doc §1:** "`/draft-plan` … Add `brainstorm` for an interactive design dialogue before research, or `quiz` for an interactive requirements interview"
- `skills/draft-plan/SKILL.md:4`: argument-hint "`[brainstorm|quiz]`"
- `skills/draft-plan/SKILL.md:149-151`: "`brainstorm` loads the interactive brainstorm dialogue (`references/brainstorm.md`) before Phase 1; `quiz` conducts an interactive requirements interview before drafting"

**Doc §3:** "`/research-and-plan` … produces a meta-plan … then stops"; "`/research-and-go` uses the same drafting machinery but continues straight into execution."
- `.claude/rules/zskills/managed.md:325`: "same drafting machinery; `-and-plan` stops after the meta-plan is ready for review, `-and-go` continues into execution."

**Doc §5:** "`/fix-issues N` runs a batch sprint, fixing up to `N` issues each in its own worktree."
- `skills/fix-issues/SKILL.md:367`: "**Worktrees only** — all fixes happen in isolated worktrees"
- `skills/fix-issues/SKILL.md:95`: references "its per-issue worktree branch (`fix-issue-NNN`)"

**Doc §6:** "`/investigate` does deep root-cause debugging: it proves why the bug happens and produces a regression test"
- `skills/investigate/SKILL.md:209`: "**Write the regression test FIRST.** Before changing any source code"
- `skills/investigate/SKILL.md:158`: "If you can't state this chain, you haven't found the root cause yet."

**Doc §6/§7:** "`/do` and `/quickfix` are peers, not tiers — same lifecycle (triage → review → commit → PR → land)"; "main_protected: true projects must use `/do`"
- `.claude/rules/zskills/managed.md:323`: "They are PEERS, not TIERS. Same lifecycle (triage → review → commit → PR → land) … `/quickfix` does `git checkout -b` on main; `/do` uses a worktree. Pick by project policy, not task size: in `main_protected: true` projects, use `/do` (always)"
- `.claude/rules/zskills/managed.md:307`: "| One-commit PR — edit in-place on main, no worktree (only valid when `main_protected: false`) | `/quickfix` |"
- `.claude/rules/zskills/managed.md:310`: "| One-commit PR — needs worktree isolation (required when `main_protected: true`) | `/do` |"
- `.claude/rules/zskills/managed.md:363`: "When `main_protected: true`, agents cannot commit, cherry-pick, or push to main."

**Doc §8:** "`/commit pr` commits the work and opens a PR by dispatching `/land-pr` for you"
- `skills/commit/SKILL.md:8`: "opens a PR via /land-pr. Positional auto enables auto-merge"
- `skills/commit/SKILL.md:142`: "`/commit pr auto` → PR mode + auto-merge via `/land-pr --auto`"

**Doc §9:** "`/cleanup-merged` … is safe to run anytime and bails on a dirty tree."
- `skills/cleanup-merged/SKILL.md:31`: "Safe to run any time. The skill bails on a dirty working tree"
- `skills/cleanup-merged/SKILL.md:239`: "### WI 1.5 — Bail on dirty tree"

**Doc §10:** "`/qe-audit` proactively scans the repo for test-coverage gaps and likely bugs and files GitHub issues"
- `skills/qe-audit/SKILL.md:18`: "missing tests, and bugs. Files GitHub issues for findings."
- `skills/qe-audit/SKILL.md:23`: "Both modes file GitHub issues"

**Doc §10:** "`/manual-testing` gives browser-based verification recipes (driven by `playwright-cli`)"
- `docs/reports/doc-rewrite-evidence/COMPANIONS.md:87`: "UI-verification helper used by `/verify-changes`, `/do`, `/qe-audit`."

---

## Execution-mode framing

**Doc Philosophy:** "Landing mode (cherry-pick / locked-main-pr / direct) is install-time configuration"; "pass `pr` or `direct` as a positional override"
- `.claude/rules/zskills/managed.md:334-338`: the three-row Execution Modes table — Cherry-pick (default), PR (`pr`), Direct (`direct`).
- `.claude/rules/zskills/managed.md:353-361`: "Config default: Set in `.claude/zskills-config.json` … `"landing": "pr"`".

---

## Companion-skill consistency (R6)

The "See also" / cross-references and the per-recipe skill pairings match
`COMPANIONS.md` and the decision table:
- `/draft-plan` → `/run-plan` sequential (COMPANIONS.md:53, :81).
- `/fix-issues` → `/fix-report` reporting companion (COMPANIONS.md:83).
- `/investigate` → `/quickfix`|`/do` (COMPANIONS.md:58, :85).
- `/verify-changes` gates a commit vs `/qe-audit` generates work (COMPANIONS.md:61-63).
- `/cleanup-merged` run AFTER any landing skill (COMPANIONS.md:76).
