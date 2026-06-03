# Fact sheet — `docs/skills/verify-changes.md`

Every factual claim in the rewritten `docs/skills/verify-changes.md`, paired
with the verbatim source line that backs it. Format:
`doc sentence → skills/verify-changes/SKILL.md:LINE: "<verbatim quoted text>"`.
Companion/routing claims cite `COMPANIONS.md`; usage-shape claims cite
`USAGE_MAP.md`.

---

## Header / blurb

- Verify recent changes really work — review diffs, check tests cover them, run the suite, manually verify UI with playwright-cli, fix, re-verify, then report →
  skills/verify-changes/SKILL.md:5-9 (frontmatter description): "Verify all recent changes: review diffs, check that unit/e2e tests cover / the changes, run all tests, manually verify UI changes with / playwright-cli, fix problems, re-verify until clean, then report with / recommendations."

## "What it does" section

- Confirms the changes you just made actually work, before committing/landing →
  skills/verify-changes/SKILL.md:16: "Thoroughly verify all recent changes in the working tree (or a specified scope)."

- Default scope is everything uncommitted in the working tree →
  skills/verify-changes/SKILL.md:166: "  - (omit) — all uncommitted changes in the working tree (default)"

- Reads each changed file to understand what changed and whether it's correct →
  skills/verify-changes/SKILL.md:270: "3. **Read and understand every changed file.** For each file:"

- Checks that tests cover the changes →
  skills/verify-changes/SKILL.md:291: "For each changed file, verify appropriate tests exist:"

- Runs the test suite →
  skills/verify-changes/SKILL.md:342: "1. **Run the full test suite with output captured to a file** (resolve via the"

- Manually exercises UI changes in a browser →
  skills/verify-changes/SKILL.md:442: "**Agent verification (MANUAL):** The agent tests the change via playwright-cli."

- Fixes problems it finds →
  skills/verify-changes/SKILL.md:536: "## Phase 5 — Fix Problems"

- Re-verifies until clean →
  skills/verify-changes/SKILL.md:563: "## Phase 6 — Re-verify (max 2 rounds)"

- Then reports what passed and what needs a human to sign off →
  skills/verify-changes/SKILL.md:578: "## Phase 7 — Report"

- The reason is independence: you may have just written the code being verified →
  skills/verify-changes/SKILL.md:25: "You may have just written the code being verified — that's exactly why"

- Memory of what you changed is unreliable (context can be lost) →
  skills/verify-changes/SKILL.md:89: "Context compaction means your memory of what you changed may be incomplete"

- It never produces a verdict from memory; reads real diffs and runs real tests →
  skills/verify-changes/SKILL.md:24: "**NEVER verify from memory. Read actual diffs, run actual tests.**"

- (Past-failure motivation for the memory rule) →
  skills/verify-changes/SKILL.md:92: "Past failure: a verification was done entirely from memory without reading"

- When a test command is configured, code changes run the full suite →
  skills/verify-changes/SKILL.md:150: "- `TEST_MODE=config` — use `$FULL_TEST_CMD` verbatim in Phase 3 (resolved by the three-case decision tree above; helper source: `zskills-resolve-config.sh`)"

- The command is read from project config, not guessed or hardcoded →
  skills/verify-changes/SKILL.md:98: "Resolve `$FULL_TEST_CMD` explicitly — do NOT search the repo for test"

- No-tests / no-command project skips the run and records the skip in the report →
  skills/verify-changes/SKILL.md:151: "- `TEST_MODE=skipped` — do NOT run tests; explicitly note `\"Tests: skipped — no test infra\"` in the final report and tracking marker"

- (No-test-infra is a legitimate state — docs-only / greenfield) →
  skills/verify-changes/SKILL.md:136: "    # Case 3 — no test infra and no configured command. Legitimate state"

- Tests exist but no command configured → refuses to claim verification, tells you to fix config →
  skills/verify-changes/SKILL.md:127: "    # Case 2 — tests exist but no command configured. Misconfigured"
  skills/verify-changes/SKILL.md:132: "    echo \"  not be silently skipped. Run /update-zskills (or edit the config\" >&2"

- Will not silently skip a suite that exists →
  skills/verify-changes/SKILL.md:154: "The silent-fallback path (guess a command, search the repo, use a template"

- UI changes get a mandatory browser check via playwright-cli →
  skills/verify-changes/SKILL.md:443: "This is YOUR job. You MUST do this for any change that touches UI files."

- Takes screenshots as evidence →
  skills/verify-changes/SKILL.md:480: "   - Take screenshots as evidence"

- Exercises behavior with real clicks/keypresses →
  skills/verify-changes/SKILL.md:479: "   - Reproduce the scenario that exercises the change using real events"

- Some UI changes need a human to judge them (animation, layout, UX feel) →
  skills/verify-changes/SKILL.md:447: "**User verification (USER):** Some changes need the HUMAN to see them —"
  skills/verify-changes/SKILL.md:448: "judgment calls about animation quality, visual layout, UX feel. The agent"

- It flags those for sign-off but cannot close them itself →
  skills/verify-changes/SKILL.md:449: "flags these but cannot close them. Mechanically classified: if"

- Fixes rather than just listing: writes missing tests →
  skills/verify-changes/SKILL.md:540: "1. **Test gaps** — write the missing tests:"

- Fails get fixed at the root cause, never weakened to pass →
  skills/verify-changes/SKILL.md:546: "   - **Never weaken tests to make them pass.** Fix the code, not the test."

- Broken behavior gets corrected and re-verified →
  skills/verify-changes/SKILL.md:558: "4. **Manual verification failures** — fix the behavior, then re-verify."

- (Fix, don't just report — the goal is a clean verification) →
  skills/verify-changes/SKILL.md:772: "- **Fix, don't just report.** When problems are found, fix them — then re-verify."

- Up to two fix-and-verify rounds; stops if the same error survives both →
  skills/verify-changes/SKILL.md:573: "**Maximum 2 fix+verify rounds.** If the same error recurs after two fix"

- Output is always printed inline →
  skills/verify-changes/SKILL.md:580: "**Always output the report inline.** Additionally, write the report FILE"

- A report file is written only when items need human sign-off →
  skills/verify-changes/SKILL.md:582: "to `$ZSKILLS_REPORTS_DIR/verify-{scope-slug}.md` and regenerate the index — but ONLY"

- When all clean, says so inline and skips the file →
  skills/verify-changes/SKILL.md:583: "all items are clean (no `[ ]` checkboxes), say so inline and skip the file:"

- Report covers what changed, how each item was verified, test result, next steps →
  skills/verify-changes/SKILL.md:625: "**Changes Reviewed** — inventory table at the top:"
  skills/verify-changes/SKILL.md:681: "**Recommendations:**"

## "Typical usage" / scope semantics

- Bare invocation is the common case →
  USAGE_MAP.md:124: "- → typical: a scope (`branch`/`worktree`/`last N`), often dispatched."

- (default omit) verifies the working tree →
  skills/verify-changes/SKILL.md:166: "  - (omit) — all uncommitted changes in the working tree (default)"

- `worktree` = current worktree vs its base branch →
  skills/verify-changes/SKILL.md:167: "  - `worktree` — changes in the current worktree vs its base branch"

- `branch` = all commits on the current branch vs main →
  skills/verify-changes/SKILL.md:168: "  - `branch` — all commits on the current branch vs main"

- `last N` = the last N commits →
  skills/verify-changes/SKILL.md:170: "  - `last N` — the last N commits"

- `/verify-changes branch` is the final whole-feature pass →
  skills/verify-changes/SKILL.md:174: "Cron-fired top-level example (final cross-branch verification at the end of a"

## "Companion skills" section

- `/verify-changes` is the change-soundness gate; `/do`, `/run-plan`, `/research-and-go` call it; uses `/manual-testing` for UI →
  COMPANIONS.md:97: "| `verify-changes` | `manual-testing`, `fix-report`, `run-plan`, `research-and-go`, `create-worktree` | The change-soundness gate; `/do`, `/run-plan`, `/research-and-go` call it; uses `/manual-testing` for UI. |"

- `/do` runs `/verify-changes` on code changes; content-only skips the full suite and does a focused diff review →
  RUBRIC.md:77 (R4-c carve-out, canonical): "behavior in a way the user can hit — e.g. `/do` skips `/verify-changes` for / content-only changes (`skills/do/SKILL.md`, `modes/pr.md`)"
  COMPANIONS.md:79: "| `do` | `quickfix` (peer), ... Peer of `/quickfix`; triage may redirect to `/draft-plan`/`/run-plan`; lands via `/land-pr`; runs `/verify-changes`. |"

- `/manual-testing` supplies the UI-verification recipes `/verify-changes` follows →
  skills/verify-changes/SKILL.md:456: "Use the `/manual-testing` skill for recipes, selectors, and setup instructions."

- Contrast with `/qe-audit`: verify-changes checks YOUR recent changes (gates a commit); qe-audit hunts repo-wide and files issues (generates work) →
  COMPANIONS.md:61: "- **`/verify-changes` vs `/qe-audit`**: `/verify-changes` checks YOUR recent"
  COMPANIONS.md:62: "  changes (gates a commit); `/qe-audit` hunts repo-wide for gaps and files"
  COMPANIONS.md:63: "  issues (generates work)."

- `/fix-report` presents the items flagged as needing human sign-off →
  skills/verify-changes/SKILL.md:451: "UI/editor/styles files changed → `User Verify: NEEDED`. `/fix-report`"
  skills/verify-changes/SKILL.md:452: "Step 2 presents these to"

- `/commit` is the landing step run after a clean verification →
  COMPANIONS.md:42: "| Staged work in main, ready to commit (and optionally push/land/PR) | `/commit` |"
  COMPANIONS.md:41: "| Want to confirm recent changes really work (diffs + tests + manual UI) | `/verify-changes` |"

## "Arguments" section

- Scope is optional →
  skills/verify-changes/SKILL.md:165: "- **scope** (optional) — what changes to verify:"

- (omit) → all uncommitted working-tree changes (default) →
  skills/verify-changes/SKILL.md:166: "  - (omit) — all uncommitted changes in the working tree (default)"

- `worktree` → current worktree vs base branch →
  skills/verify-changes/SKILL.md:167: "  - `worktree` — changes in the current worktree vs its base branch"

- `branch` → all commits on the current branch vs main →
  skills/verify-changes/SKILL.md:168: "  - `branch` — all commits on the current branch vs main"

- `last` → only the last commit (same as `last 1`) →
  skills/verify-changes/SKILL.md:169: "  - `last` — only the last commit (same as `last 1`)"

- `last N` → the last N commits →
  skills/verify-changes/SKILL.md:170: "  - `last N` — the last N commits"

## "Examples" section (verbatim from source)

- `/verify-changes`, `/verify-changes worktree`, `/verify-changes last 3` →
  skills/verify-changes/SKILL.md:172: "Examples: `/verify-changes`, `/verify-changes worktree`, `/verify-changes last 3`"

- `/verify-changes branch` is a valid scope →
  skills/verify-changes/SKILL.md:168: "  - `branch` — all commits on the current branch vs main"

## "Tips & Gotchas"

- Never verifies from memory →
  skills/verify-changes/SKILL.md:767: "- **Never verify from memory.** Read actual diffs, actual files, run actual"

- Fixes problems then re-verifies; stops after two rounds →
  skills/verify-changes/SKILL.md:573: "**Maximum 2 fix+verify rounds.** If the same error recurs after two fix"

- It starts a dev server itself if one isn't running; "no dev server" is not a reason to skip →
  skills/verify-changes/SKILL.md:459: "dev server is running, START ONE:"
  skills/verify-changes/SKILL.md:774: "- **Start a dev server if needed.** \"No dev server\" is not an excuse to"

- Never commits/merges/pushes without permission, except worktree fixes for cherry-pick →
  skills/verify-changes/SKILL.md:760: "- **Never commit, merge, or push without explicit user permission** — unless"
  skills/verify-changes/SKILL.md:761: "  working in a worktree where committing fixes is part of the workflow (Phase 5)."

---

## R5 internals-stripping note (what was REMOVED vs the prior doc)

The previous `docs/skills/verify-changes.md` leaked implementer-voice terms
banned by `banned-terms.txt`. The rewrite removes all of them and describes the
behavior instead:

- `subagent_type: "verifier"` (banned: `subagent_type`) — removed. The doc now
  says "independence" / "verification against the actual diffs and a real test
  run" without naming the agent machinery.
- "Layer 3 response validation" — removed (internal dispatch-hook plumbing).
- "7-phase verification" / "Phase 1-7" (banned: `Phase [0-9]`) — removed. The
  doc describes what happens (review diffs, check coverage, run tests, verify
  UI, fix, re-verify, report) without numbering the phases.
- "Agent tool" / "inline single-context verification" — removed; replaced with
  the user-facing fact that verification is independent of your memory.

Acceptance command (must return no hits):

```
grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/skills/verify-changes.md
```
