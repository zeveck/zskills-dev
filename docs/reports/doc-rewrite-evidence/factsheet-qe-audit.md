# Fact sheet — `docs/skills/qe-audit.md`

Every factual claim in the rewritten `docs/skills/qe-audit.md`, paired with the
verbatim source line that backs it. Format:
`doc sentence → skills/qe-audit/SKILL.md:LINE: "<verbatim quoted text>"`.
Companion/usage claims cite `COMPANIONS.md` / `USAGE_MAP.md`.

---

## "What it does" section

- `/qe-audit` runs a QE pass over recent work and files GitHub issues for findings →
  skills/qe-audit/SKILL.md:7: "- **Commit audit** (default) — review recent commits for test coverage gaps,"
  skills/qe-audit/SKILL.md:8: "  missing tests, and bugs. Files GitHub issues for findings."

- It does not fix anything; it finds and files →
  skills/qe-audit/SKILL.md:556: "- **File issues, don't fix inline** — QE audit finds problems. `/fix-issues`"
  skills/qe-audit/SKILL.md:557: "  fixes them. Keep the separation clean."

- Default mode is commit audit; reviews commits since the last audit, reading each diff and related tests →
  skills/qe-audit/SKILL.md:224: "1. **Find the last audit checkpoint** — read the bottom of `the QE issues tracker (e.g., `$ZSKILLS_ISSUES_DIR/QE_ISSUES.md`)`"
  skills/qe-audit/SKILL.md:235: "4. **Audit each commit** — For each commit with code changes, **dispatch"
  skills/qe-audit/SKILL.md:240: "   - Read the diff (`git show <hash>`)"
  skills/qe-audit/SKILL.md:241: "   - Read related test files"

- Commit audit asks whether tests are meaningful, whether anything is uncovered, whether bugs slipped in →
  skills/qe-audit/SKILL.md:242: "   - Assess: Are tests good (testing real behavior, not no-ops)? Are there"
  skills/qe-audit/SKILL.md:243: "     coverage gaps? Are there bugs?"

- Bash mode is adversarial stress-testing of a feature →
  skills/qe-audit/SKILL.md:9: "- **Bash** — adversarial stress-testing of features. Pick a specific area"

- Bash mode picks an area you name or an under-tested one it chooses →
  skills/qe-audit/SKILL.md:9: "- **Bash** — adversarial stress-testing of features. Pick a specific area"
  skills/qe-audit/SKILL.md:10: "  or let the agent choose under-tested areas. Try to break things with edge"

- Bash tries to break things with edge cases, unusual inputs, unexpected workflows →
  skills/qe-audit/SKILL.md:10: "  or let the agent choose under-tested areas. Try to break things with edge"
  skills/qe-audit/SKILL.md:11: "  cases, unusual inputs, and unexpected workflows."

- Bash edge cases: empty values, boundary conditions, rapid/out-of-order actions, invalid state →
  skills/qe-audit/SKILL.md:448: "   - Edge cases (empty inputs, zero values, NaN, Infinity, negative numbers)"
  skills/qe-audit/SKILL.md:449: "   - Boundary conditions (max array size, deeply nested structures)"
  skills/qe-audit/SKILL.md:450: "   - Race conditions (rapid undo/redo, concurrent operations)"
  skills/qe-audit/SKILL.md:451: "   - Invalid state (corrupted model data, missing references)"

- Both modes file GitHub issues and write a report of what they did →
  skills/qe-audit/SKILL.md:23: "Both modes file GitHub issues and update `the QE issues tracker (e.g., `$ZSKILLS_ISSUES_DIR/QE_ISSUES.md`)`. Both are"
  skills/qe-audit/SKILL.md:386: "8. **Report** — Summarize findings: issues filed, notable positives, and"
  skills/qe-audit/SKILL.md:513: "8. **Report** — Summarize:"

- Every finding is verified against the actual code before an issue is filed →
  skills/qe-audit/SKILL.md:271: "5. **Verify each finding against ground truth before durable-state action.**"
  skills/qe-audit/SKILL.md:272: "   For every \"FILE ISSUE\" or \"MOVE TO RESOLVED\" finding from a dispatched"
  skills/qe-audit/SKILL.md:273: "   agent, perform the cited check yourself before calling `gh issue create`"

- A finding that claims a file says something / a line is missing / a commit fixed a bug is confirmed against source →
  skills/qe-audit/SKILL.md:279: "   - If the finding cites a file:line, `Read` or `grep -n` that file:line and"
  skills/qe-audit/SKILL.md:282: "   - If the finding cites \"X is absent\" / \"Y is not tested\" / \"Z was removed,\""
  skills/qe-audit/SKILL.md:285: "   - If the finding cites \"issue #N was fixed by commit X,\" `git show X` and"

- A finding that can't be confirmed is recorded as unverified, not filed →
  skills/qe-audit/SKILL.md:290: "   tracker entry (e.g., `Verified: \\`grep -n 'pattern' file\\` → line 441`). A"
  skills/qe-audit/SKILL.md:291: "   finding that cannot be verified against ground truth is logged in the"
  skills/qe-audit/SKILL.md:292: "   tracker under an \"Unverified findings\" subsection with the reason, not"
  skills/qe-audit/SKILL.md:293: "   filed as an issue or moved between sections."

- The bar for filing is high; a finding must be a real problem a user/agent would plausibly hit, not theoretically possible →
  skills/qe-audit/SKILL.md:249: "2. Real user/agent plausibly hits this within ~1 month? (NOT \"technically possible,\" NOT \"constructible adversarially\")"
  skills/qe-audit/SKILL.md:258: "- \"Could trigger via contrived input\""

- A run filing nothing is a normal healthy result, not a failure →
  skills/qe-audit/SKILL.md:253: "If a candidate fails any of the 3, the agent stands down. Yield 0-1 issues is a CONVERGENCE SIGNAL, not failure."

- Files issues rather than fixing; `/fix-issues` fixes; they form a feedback loop →
  skills/qe-audit/SKILL.md:24: "schedulable. Together they form the quality feedback loop: audit finds gaps →"
  skills/qe-audit/SKILL.md:25: "`/fix-issues` fixes them → audit validates the fixes."

## "Usage" / "Typical usage" sections

- Bare `/qe-audit` runs a commit audit immediately →
  skills/qe-audit/SKILL.md:65: "- `/qe-audit` — audit recent commits now"
  skills/qe-audit/SKILL.md:167: "(bare invocation always runs immediately)."

- `bash` switches to stress-test mode →
  skills/qe-audit/SKILL.md:36: "- **bash** (optional) — switch to bash/stress-test mode instead of commit audit"

- `/qe-audit bash` picks an under-tested area for you; name an area to target it →
  skills/qe-audit/SKILL.md:66: "- `/qe-audit bash` — bash random under-tested features now"
  skills/qe-audit/SKILL.md:67: "- `/qe-audit bash \"undo/redo\"` — bash a specific feature now"

- `every SCHEDULE` schedules recurring runs; `now` also runs immediately →
  skills/qe-audit/SKILL.md:41: "- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:"
  skills/qe-audit/SKILL.md:46: "  - With `now`: schedules AND runs immediately"

- Typical shape is bare or with a focus phrase, usually on a cron →
  USAGE_MAP.md:115: "- → typical: bare or with a focus phrase, usually on a cron."

- `Run /qe-audit every Nh now` is a real typical invocation →
  USAGE_MAP.md:112: "- `Run /qe-audit every Nh now` (281)"

- `/qe-audit next` reports the next run; `/qe-audit stop` cancels →
  skills/qe-audit/SKILL.md:73: "- `/qe-audit next` — when's the next audit?"
  skills/qe-audit/SKILL.md:74: "- `/qe-audit stop` — cancel scheduled audits"

## "Companion skills" section

- `/qe-audit` companions are `draft-plan`, `fix-issues`, `manual-testing` →
  COMPANIONS.md:89: "| `qe-audit` | `draft-plan`, `fix-issues`, `manual-testing`, `create-worktree` | Files issues that `/fix-issues` then drives; big findings go to `/draft-plan`. |"

- `/fix-issues` drives the issues `/qe-audit` files →
  COMPANIONS.md:89: "| `qe-audit` | `draft-plan`, `fix-issues`, `manual-testing`, `create-worktree` | Files issues that `/fix-issues` then drives; big findings go to `/draft-plan`. |"

- `/verify-changes` checks YOUR recent changes (gates a commit); `/qe-audit` hunts repo-wide and files issues (generates work) →
  COMPANIONS.md:61: "- **`/verify-changes` vs `/qe-audit`**: `/verify-changes` checks YOUR recent"
  COMPANIONS.md:62: "  changes (gates a commit); `/qe-audit` hunts repo-wide for gaps and files"
  COMPANIONS.md:63: "  issues (generates work)."

- Big findings go to `/draft-plan` →
  COMPANIONS.md:89: "| `qe-audit` | `draft-plan`, `fix-issues`, `manual-testing`, `create-worktree` | Files issues that `/fix-issues` then drives; big findings go to `/draft-plan`. |"
  skills/qe-audit/SKILL.md:164: "the calibration drifted at the agent level — tighten the prompt for next pass (apply TIGHT-BAR more aggressively)."

- `/manual-testing` is used inside bash mode to exercise UI features through a real browser →
  skills/qe-audit/SKILL.md:420: "   **a. Manual UI testing** (for editor, UI, interaction features):"
  skills/qe-audit/SKILL.md:421: "   - Use `/manual-testing` recipes with playwright-cli"
  COMPANIONS.md:87: "| `manual-testing` | `verify-changes`, `update-zskills` | UI-verification helper used by `/verify-changes`, `/do`, `/qe-audit`. (Note: #1012 makes it `user-invocable: false`.) |"

## "Arguments" section

- `bash` switches to stress-test mode instead of commit audit →
  skills/qe-audit/SKILL.md:36: "- **bash** (optional) — switch to bash/stress-test mode instead of commit audit"

- `area` (with bash) is a specific feature; omit and it picks an under-tested area →
  skills/qe-audit/SKILL.md:37: "- **area** (optional, with bash) — specific feature or area to bash. If"
  skills/qe-audit/SKILL.md:38: "  omitted, the agent picks under-tested areas based on coverage data and"

- area examples: undo/redo, solver, codegen →
  skills/qe-audit/SKILL.md:39: "  recent changes. Examples: `\"undo/redo\"`, `\"state machine editor\"`, `\"solver\"`,"
  skills/qe-audit/SKILL.md:40: "  `\"codegen\"`, `\"block parameters\"`"

- `every SCHEDULE` accepts intervals (4h, 2h, 30m, 12h) and time-of-day (day at 9am, weekday at 9am) →
  skills/qe-audit/SKILL.md:42: "  - Accepts intervals: `4h`, `2h`, `30m`, `12h`"
  skills/qe-audit/SKILL.md:43: "  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`"

- `now` runs immediately; with `every` runs now AND schedules; bare invocation already runs immediately →
  skills/qe-audit/SKILL.md:49: "- **now** (optional) — run immediately. When combined with `every`, runs"
  skills/qe-audit/SKILL.md:50: "  immediately AND schedules. Without `every`, `now` is the default behavior"
  skills/qe-audit/SKILL.md:51: "  (bare invocation always runs immediately)."

- `stop` cancels the recurring run and takes precedence over everything →
  skills/qe-audit/SKILL.md:52: "- **stop** — cancel any existing `/qe-audit` cron and exit. **Takes"
  skills/qe-audit/SKILL.md:53: "  precedence over all other arguments.**"

- `next` reports the next run and takes precedence over everything but `stop` →
  skills/qe-audit/SKILL.md:54: "- **next** — check when the next scheduled run will fire. **Takes precedence"
  skills/qe-audit/SKILL.md:55: "  over all other arguments except `stop`.**"

- `now` only matters alongside `every` (bare always runs immediately) →
  skills/qe-audit/SKILL.md:51: "  (bare invocation always runs immediately)."

- Scheduling re-registers itself each run so recurrence continues →
  skills/qe-audit/SKILL.md:47: "  - Each run re-registers the cron (self-perpetuating)"

- A scheduled audit runs autonomously, no approval pause →
  skills/qe-audit/SKILL.md:554: "- **`every` implies autonomous operation** — scheduled audits run without"
  skills/qe-audit/SKILL.md:555: "  user approval."

- The schedule lasts as long as the session; it dies when the session dies →
  skills/qe-audit/SKILL.md:48: "  - Cron is session-scoped — dies when the session dies"

## "Examples" section

(all verbatim from the source examples block, lines 65–74)

- `/qe-audit` →
  skills/qe-audit/SKILL.md:65: "- `/qe-audit` — audit recent commits now"
- `/qe-audit bash` →
  skills/qe-audit/SKILL.md:66: "- `/qe-audit bash` — bash random under-tested features now"
- `/qe-audit bash undo/redo` →
  skills/qe-audit/SKILL.md:67: "- `/qe-audit bash \"undo/redo\"` — bash a specific feature now"
- `/qe-audit bash solver every 6h` →
  skills/qe-audit/SKILL.md:68: "- `/qe-audit bash \"solver\" every 6h` — schedule solver bashing every 6h"
- `/qe-audit every day at 9am` →
  skills/qe-audit/SKILL.md:69: "- `/qe-audit every day at 9am` — schedule daily commit audit (first run at 9am)"
- `/qe-audit every day at 9am now` →
  skills/qe-audit/SKILL.md:70: "- `/qe-audit every day at 9am now` — schedule daily + run now"
- `/qe-audit every weekday at 9am` →
  skills/qe-audit/SKILL.md:71: "- `/qe-audit every weekday at 9am` — weekday mornings only"
- `/qe-audit bash every 12h now` →
  skills/qe-audit/SKILL.md:72: "- `/qe-audit bash every 12h now` — bash random features every 12h, start now"
- `/qe-audit next` →
  skills/qe-audit/SKILL.md:73: "- `/qe-audit next` — when's the next audit?"
- `/qe-audit stop` →
  skills/qe-audit/SKILL.md:74: "- `/qe-audit stop` — cancel scheduled audits"

## "Common Patterns" / "Tips & Gotchas"

- Both modes file GitHub issues for findings and end with a report →
  skills/qe-audit/SKILL.md:8: "  missing tests, and bugs. Files GitHub issues for findings."
  skills/qe-audit/SKILL.md:386: "8. **Report** — Summarize findings: issues filed, notable positives, and"

- The commit audit examines commits since the last audit, not the whole codebase; no new commits → reports and stops →
  skills/qe-audit/SKILL.md:230: "2. **List new commits** — `git log --oneline <last_commit>..HEAD`. Skip"
  skills/qe-audit/SKILL.md:233: "3. **If no new commits** — report \"no new commits since last audit\" and stop."

- A zero-issue run is normal; only confirmed, worth-acting-on findings are filed →
  skills/qe-audit/SKILL.md:253: "If a candidate fails any of the 3, the agent stands down. Yield 0-1 issues is a CONVERGENCE SIGNAL, not failure."

- Bash mode is adversarial — it actively tries to break the feature →
  skills/qe-audit/SKILL.md:9: "- **Bash** — adversarial stress-testing of features. Pick a specific area"

- Files issues but never fixes inline; pair with `/fix-issues` →
  skills/qe-audit/SKILL.md:556: "- **File issues, don't fix inline** — QE audit finds problems. `/fix-issues`"

- Scheduling follows the same `every SCHEDULE` pattern; schedule dies with the session →
  skills/qe-audit/SKILL.md:41: "- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:"
  skills/qe-audit/SKILL.md:48: "  - Cron is session-scoped — dies when the session dies"
