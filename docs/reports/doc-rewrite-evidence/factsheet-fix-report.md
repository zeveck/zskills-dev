# Factsheet — `docs/skills/fix-report.md`

Every claim in the rewritten doc, paired with the verbatim source line that
supports it. Source of truth: `skills/fix-report/SKILL.md` (read in full).
Verifier checks each citation against the cited line.

---

## Summary blurb

**Doc sentence:** "`/fix-report` is the interactive review companion to
`/fix-issues`: it walks you through every sprint result that hasn't been
signed off yet — confirming fixes, landing them, closing the matching GitHub
issues, and tidying up afterward."

- `skills/fix-report/SKILL.md:16`: `Interactive companion to \`/fix-issues\`. Covers ALL unreported sprint results`
- `skills/fix-report/SKILL.md:8-9` (description): `Review ALL unreported sprint results: walk through manual verifications, / land fixes to main, close GitHub issues, update trackers, clean up`

---

## What it does

**Doc sentence:** "After `/fix-issues` has run — often unattended on a
schedule — its results pile up unreviewed. `/fix-report` gathers all of that
unreviewed work into one picture and walks you through clearing it."

- `skills/fix-report/SKILL.md:17-20`: `Covers ALL unreported sprint results / — not just the latest ... If sprints have been running on a / cron every 2 hours and the user hasn't checked in a day, \`/fix-report\` / should present everything from those 12 sprints.`

**Doc sentence:** "It is always interactive: it shows you what happened, then
stops and waits for your go-ahead before doing anything. Nothing lands,
closes, or gets deleted without your say-so."

- `skills/fix-report/SKILL.md:21-22`: `This skill is always interactive — no \`auto\` flag. It's the human review / counterpart to \`/fix-issues auto\`.`
- `skills/fix-report/SKILL.md:24-26`: `**Every step ends with STOP AND WAIT.** Do not advance to the next step until / the user explicitly says to proceed. Present information, then stop. The user / drives the pace — not you.`
- `skills/fix-report/SKILL.md:514-515`: `**Always interactive** — every landing, closing, and cleanup action requires / explicit user approval.`

**Doc sentence:** "First it presents a combined summary of every sprint that
hasn't been signed off — what was fixed, what still needs you to eyeball it,
and what was skipped (and why: too vague, too complex, or a merge conflict
that a later run will retry)."

- `skills/fix-report/SKILL.md:85`: `Present the COMBINED picture across all unfinalized sprints:`
- `skills/fix-report/SKILL.md:102-106`: `**Always break out skip reasons.** The user needs to know which skipped / issues need clarification (too vague → user adds repro steps), which need / a different approach (too complex → \`/run-plan\`), and which will self-heal / (cherry-pick conflict → next sprint picks them up).`

**Doc sentence:** "For any fix that touched the UI, it gives you concrete
steps to check it in the browser and asks you to mark it pass or fail."

- `skills/fix-report/SKILL.md:208-216`: `For each issue with \`User Verify: NEEDED\`: ... **Provide concrete verification instructions:** ... What to look at ... Steps to reproduce ... What "correct" looks like`
- `skills/fix-report/SKILL.md:223`: `Ask the user: **Pass or Fail?**`

**Doc sentence:** "Once you approve, it lands the fixes that aren't on `main`
yet, closes the GitHub issues they resolve, marks them done in your issue
trackers, removes the worktrees that are safe to remove, and writes a final
report you can sign off against."

- `skills/fix-report/SKILL.md:238-240`: `## Step 3 — Sprint Approval Gate / / This is the "clear the sprint" moment.`
- `skills/fix-report/SKILL.md:289`: `For each approved fix that has NOT been landed:`
- `skills/fix-report/SKILL.md:338-345`: `Close the GitHub issue: ... Update ALL relevant issue tracker files`
- `skills/fix-report/SKILL.md:351`: `## Step 6 — Worktree Cleanup`
- `skills/fix-report/SKILL.md:431-433`: `## Step 7 — Write ... FIX_REPORT.md / / Write ... to the repo root.`

**Doc sentence:** "Fixes that `/fix-issues` already opened as pull requests
are recognized as such — `/fix-report` shows you the PR link and its CI
status instead of trying to re-land them."

- `skills/fix-report/SKILL.md:158-161`: `### PR-aware reporting / / Scan every worktree's \`.landed\` marker for \`method: pr\`. These come from / \`/fix-issues <N> auto pr\` runs`
- `skills/fix-report/SKILL.md:270-272`: `**PR mode fixes are landed via merge, not cherry-pick.** ... \`status: landed\` — the PR was auto-merged; the fix is already on main`
- `skills/fix-report/SKILL.md:169`: `Present PR-linked fixes with their URLs alongside the issue numbers:`

---

## Typical usage

**Doc sentence:** "There is nothing to configure — you run it bare and it
walks you through the rest."

- `skills/fix-report/SKILL.md:4`: `argument-hint: ""`
- `skills/fix-report/SKILL.md:21`: `This skill is always interactive — no \`auto\` flag.`

**Doc sentence (example `/fix-report`):** bare invocation is the only form.

- `skills/fix-report/SKILL.md:4`: `argument-hint: ""`

**Doc sentence:** "The usual moment to run it is after `/fix-issues` has been
working a backlog on a schedule and you want to catch up on everything it
did."

- `skills/fix-report/SKILL.md:17-20`: `If sprints have been running on a / cron every 2 hours and the user hasn't checked in a day, \`/fix-report\` / should present everything from those 12 sprints.`

---

## Companion skills (per COMPANIONS.md row `fix-report`)

COMPANIONS.md:84: `fix-report | fix-issues, commit, create-worktree, manual-testing, run-plan, update-zskills | The reporting companion of /fix-issues.`

**Doc sentence (`/fix-issues`):** "the skill `/fix-report` reviews. `/fix-issues`
does the fixing; `/fix-report` clears the results."

- `skills/fix-report/SKILL.md:16`: `Interactive companion to \`/fix-issues\`.`
- COMPANIONS.md:83: `fix-issues | fix-report, ... | ... \`fix-report\` summarizes a sprint`

**Doc sentence (`/commit`):** "how you land the report and tracker changes
from the worktree when you are done — typically `/commit pr`."

- `skills/fix-report/SKILL.md:40-41`: `The / final landing of audit + tracker file changes is the user's call / (typically \`/commit pr\` from the worktree once the user has approved`

**Doc sentence (`/manual-testing`):** "used to drive the in-browser checks for
UI fixes during verification."

- `skills/fix-report/SKILL.md:221-222`: `Run the verification via \`/manual-testing\` or guide the user through / manual steps`

**Doc sentence (`/run-plan`):** "where skipped-as-too-complex fixes are
pointed; `/fix-report` flags those for you."

- `skills/fix-report/SKILL.md:104`: `which need / a different approach (too complex → \`/run-plan\`)`

---

## Arguments

**Doc sentence:** "`/fix-report` takes no arguments. It is always interactive
and has no `auto` flag — it guides you one step at a time and waits for your
approval at each one."

- `skills/fix-report/SKILL.md:4`: `argument-hint: ""`
- `skills/fix-report/SKILL.md:21`: `This skill is always interactive — no \`auto\` flag.`
- `skills/fix-report/SKILL.md:24`: `**Every step ends with STOP AND WAIT.**`

---

## Internals deliberately stripped (R5)

These appear in the source but are implementer-voice and were kept OUT of the
user doc: `Phase`/`Step N` numbers (e.g. SKILL.md:75,238,431); state-file
paths (`$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`, `$ZSKILLS_AUDIT_DIR/FIX_REPORT.md`,
`.landed` markers, `method: pr`, the `status:` enum at SKILL.md:165-167);
`git-common-dir` and `ensure-worktree.sh` plumbing (SKILL.md:49-73); the
`main_protected`/worktree-gate mechanism (SKILL.md:29-42) — the doc says
"from the worktree" only where the user observably runs `/commit pr` there.
The old doc's "Works in a pre-created worktree under
`execution.main_protected: true`" tail line leaked the config field and the
internal worktree-gate; dropped per R5.
